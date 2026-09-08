import AppKit
import Combine
import SwiftUI
import WeiBeiCore

/// Owns the sole vertical scroll position, explicit row heights and current-surface display data.
@MainActor
final class NativeConversationController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    struct ReadingAnchor {
        var messageID: UUID
        var characterOffset: Int?
        var rowOffset: CGFloat
        var viewportOffset: CGFloat
        var intent: UInt64
        var attachmentPosition: NativeChatAttachmentReadingPosition?
    }
    private enum Row: Equatable { case history, message(UUID), waiting }
    private struct Turn {
        var id: UUID
        var index: Int
        var question: String
        var answer: String
    }
    let scrollView = ConversationScrollView()
    let tableView = NSTableView()
    private(set) var states: [UUID: NativeConversationMessageState] = [:]
    private(set) var followsLatest = true
    private(set) var heightTransactionCount = 0
    private(set) var structuralUpdateCount = 0
    var openSettings: () -> Void = {}
    private let store: WorkspaceStore
    private let navigation: NativeConversationNavigation
    private var rows: [Row] = []
    private var rowByID: [UUID: Int] = [:]
    private var messages: [AgentMessage] = []
    private var turns: [Turn] = []
    private var turnIDByMessage: [UUID: String] = [:]
    private var sessionID: UUID?
    private var visibleLimit = AgentHistoryRevealPolicy.pageSize
    private var wide = false
    private var textScale: CGFloat = 1
    private var isSurfaceVisible = true
    private var appearanceKey = ""
    private var language: WeiBeiInterfaceLanguage = .chinese
    private var columnWidth: CGFloat = 0
    private var subscriptions: Set<AnyCancellable> = []
    private var streamingSubscriptions: Set<AnyCancellable> = []
    private weak var streaming: AgentStreamingState?
    private var observers: [NSObjectProtocol] = []
    private var updateScheduled = false
    private var streamScheduled = false
    private var heightScheduled = false
    private var pendingHeights: [UUID: CGFloat] = [:]
    private var pendingAnchor: ReadingAnchor?
    private var readingAnchor: ReadingAnchor?
    private var userIntent: UInt64 = 0
    private var inTransaction = false
    private var liveScroll = false
    private var revealingHistory = false
    private var previousY: CGFloat = 0
    private var hasWaitingRow = false
    private weak var waitingView: NSHostingView<AnyView>?

    init(store: WorkspaceStore, navigation: NativeConversationNavigation) {
        self.store = store
        self.navigation = navigation
        super.init(nibName: nil, bundle: nil)
        navigation.controller = self
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 10, left: 0, bottom: 12, right: 0)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.usesAutomaticRowHeights = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.intercellSpacing = NSSize(width: 0, height: 12)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.resizingMask = []
        column.minWidth = 1
        column.maxWidth = .greatestFiniteMagnitude
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityIdentifier("native-conversation-list")
        scrollView.documentView = tableView
        view = scrollView
        scrollView.onUserScroll = { [weak self] in self?.userWillScroll() }
        scrollView.onWidthChange = { [weak self] in self?.beginLayoutChange() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.scrolled() } })
        observers.append(center.addObserver(forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                self?.userWillScroll()
                self?.liveScroll = true
            } })
        observers.append(center.addObserver(forName: NSScrollView.didEndLiveScrollNotification,
            object: scrollView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.liveScroll = false; self?.revealingHistory = false }
            })
        store.$messages.sink { [weak self] _ in self?.scheduleMessagesUpdate() }.store(in: &subscriptions)
        store.$activeStudySessionID.removeDuplicates().sink { [weak self] _ in self?.scheduleMessagesUpdate() }.store(in: &subscriptions)
        connectStreaming()
        updateMessages()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard isSurfaceVisible else { return }
        let width = max(1, scrollView.contentSize.width)
        guard width != columnWidth else { return }
        beginLayoutChange()
        columnWidth = width
        tableView.tableColumns.first?.width = width
        tableView.frame.size.width = width
        invalidateRowWidths()
        for cell in visibleRows() { cell.needsLayout = true }
        scheduleHeightTransaction()
    }

    func configure(wide: Bool, textScale: CGFloat, isVisible: Bool) {
        loadViewIfNeeded()
        let restyle = self.wide != wide || self.textScale != textScale
            || appearanceKey != store.appearanceMode.rawValue || language != store.interfaceLanguage
        self.wide = wide
        self.textScale = textScale
        let becameVisible = !isSurfaceVisible && isVisible
        isSurfaceVisible = isVisible
        if restyle {
            beginLayoutChange()
            appearanceKey = store.appearanceMode.rawValue
            language = store.interfaceLanguage
            tableView.intercellSpacing.height = wide ? 22 : 12
            scrollView.appearance = NSAppearance(named: store.appearanceMode.isDark ? .darkAqua : .aqua)
            invalidateRowWidths()
            for cell in visibleRows() { configure(cell) }
        }
        connectStreaming()
        let waiting = store.isAgentRunningInActiveChat && !store.hasPersistedGeneratingAgentReply
        if hasWaitingRow != waiting {
            hasWaitingRow = waiting
            rebuildRows()
        }
        if isVisible { view.needsLayout = true }
        if becameVisible { scheduleHeightTransaction() }
    }

    func disconnect() {
        subscriptions.removeAll()
        streamingSubscriptions.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        for state in states.values { state.invalidate() }
        states.removeAll()
        navigation.controller = nil
    }

    private func connectStreaming() {
        let next = store.agentStreaming
        guard streaming !== next else { return }
        streamingSubscriptions.removeAll()
        streaming = next
        next.objectWillChange.sink { [weak self] in
            guard let self, !self.streamScheduled else { return }
            self.streamScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.streamScheduled = false
                self.updateStreamingMessage()
            }
        }.store(in: &streamingSubscriptions)
    }

    private func scheduleMessagesUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.updateMessages()
        }
    }

    private func updateMessages() {
        let changedSession = sessionID != store.activeStudySessionID
        let next = store.messages
        let oldIDs = messages.map(\.id), newIDs = next.map(\.id)
        let structureChanged = oldIDs != newIDs
        if changedSession {
            userIntent &+= 1
            pendingAnchor = nil
            readingAnchor = nil
            pendingHeights.removeAll()
            for state in states.values { state.invalidate() }
            states.removeAll()
            let previousRows = IndexSet(rows.indices)
            rows.removeAll()
            rowByID.removeAll()
            withoutAnimation { tableView.removeRows(at: previousRows, withAnimation: []) }
            visibleLimit = AgentHistoryRevealPolicy.pageSize
            followsLatest = true
            sessionID = store.activeStudySessionID
            connectStreaming()
        } else if let appended = AgentHistoryRevealPolicy.appendedMessageCount(previousMessageIDs: oldIDs, currentMessageIDs: newIDs) {
            visibleLimit += appended
        } else if !oldIDs.isEmpty && structureChanged && !newIDs.suffix(oldIDs.count).elementsEqual(oldIDs) {
            visibleLimit = AgentHistoryRevealPolicy.pageSize
        }
        beginLayoutChange()
        let previous = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        messages = next
        if oldIDs.isEmpty && !next.isEmpty { store.paneState.dockInitialAgentComposer() }
        let currentIDs = Set(newIDs)
        for id in Array(states.keys) where !currentIDs.contains(id) {
            states.removeValue(forKey: id)?.invalidate()
        }
        for message in next where previous[message.id] != message {
            if let state = states[message.id] {
                state.update(message, displayedText: displayedText(for: message))
                if let cell = cell(for: message.id) { configure(cell) }
            }
        }
        rebuildTurns()
        if structureChanged || changedSession { rebuildRows() }
        updateStreamingMessage()
        scheduleHeightTransaction()
    }

    private func displayedText(for message: AgentMessage) -> String {
        streaming?.isDisplaying(message.id) == true ? streaming!.text : store.agentDisplayText(for: message)
    }

    private func updateStreamingMessage() {
        waitingView?.rootView = waitingContent
        guard let streaming, let id = streaming.displayingMessageID,
              streaming.displayingChatID == store.activeStudySessionID,
              let state = states[id] else { return }
        state.update(state.message, displayedText: streaming.text)
        if let cell = cell(for: id) { cell.updateControls(activity: streaming.activityText) }
        if let turnID = turnIDByMessage[id], let index = navigation.items.firstIndex(where: { $0.id == turnID }) {
            let excerpt = preview(streaming.text)
            let item = navigation.items[index]
            if !excerpt.isEmpty && item.excerpt != excerpt {
                navigation.items[index] = ContentRailItem(id: item.id, position: item.position,
                    title: item.title, excerpt: excerpt, metadata: item.metadata)
            }
        }
    }

    private func rebuildRows() {
        beginLayoutChange()
        var next: [Row] = messages.count > visibleLimit ? [.history] : []
        next += messages.suffix(visibleLimit).map { .message($0.id) }
        if hasWaitingRow { next.append(.waiting) }
        guard next != rows else { return }
        let previous = rows
        let delta = next.difference(from: previous)
        let removed = IndexSet(delta.compactMap { if case let .remove(index, _, _) = $0 { return index }; return nil })
        let inserted = IndexSet(delta.compactMap { if case let .insert(index, _, _) = $0 { return index }; return nil })
        rows = next
        rowByID = Dictionary(uniqueKeysWithValues: rows.enumerated().compactMap {
            if case let .message(id) = $0.element { return (id, $0.offset) }; return nil
        })
        for message in messages.suffix(visibleLimit) where states[message.id] == nil {
            let state = NativeConversationMessageState(message: message)
            state.update(message, displayedText: displayedText(for: message))
            states[message.id] = state
            state.onChange = { [weak self, weak state] in
                guard let self, let state, self.states[state.message.id] === state else { return }
                if let cell = self.cell(for: state.message.id) { self.configure(cell) }
            }
            state.renderer.onWillChange = { [weak self, weak state] edit in
                guard let self, let state else { return }
                self.beginLayoutChange()
                if self.pendingAnchor?.messageID == state.message.id,
                   let offset = self.pendingAnchor?.characterOffset, let edit {
                    self.pendingAnchor?.characterOffset = edit.mapSelection(NSRange(location: offset, length: 0)).location
                    self.readingAnchor = self.pendingAnchor
                }
            }
            state.renderer.onViewportLayout = { [weak self, weak state] in
                guard let self, let state, !self.followsLatest, !self.inTransaction,
                      let anchor = self.readingAnchor, anchor.messageID == state.message.id,
                      anchor.intent == self.userIntent,
                      let target = self.textAnchorTarget(anchor),
                      abs(target - self.scrollView.contentView.bounds.minY) > 0.5 else { return }
                // TextKit can correct fragment positions without changing its total extent.
                self.pendingAnchor = anchor
                self.scheduleHeightTransaction()
            }
        }
        let newIDs = inserted.compactMap { index -> UUID? in
            if case let .message(id) = rows[index] { return id }; return nil
        }
        invalidateRowWidths()
        for id in newIDs {
            if let height = pendingHeights.removeValue(forKey: id) { states[id]?.height = height }
        }
        structuralUpdateCount += 1
        withoutAnimation {
            tableView.beginUpdates()
            if !removed.isEmpty { tableView.removeRows(at: removed, withAnimation: []) }
            if !inserted.isEmpty { tableView.insertRows(at: inserted, withAnimation: []) }
            tableView.endUpdates()
        }
        scheduleHeightTransaction()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        // This callback only reads records. Querying table geometry here can recursively tile.
        switch rows[row] {
        case let .message(id): return states[id]?.height ?? 60
        case .history: return 40
        case .waiting: return 44
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case let .message(id):
            guard let state = states[id] else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("native-message")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? NativeConversationMessageRow)
                ?? NativeConversationMessageRow(frame: .zero)
            cell.identifier = identifier
            cell.bind(state)
            configure(cell)
            return cell
        case .history:
            let button = NSButton(title: store.ui("查看更早的 \(min(AgentHistoryRevealPolicy.pageSize, messages.count - visibleLimit)) 条消息", "Show earlier messages"),
                target: self, action: #selector(revealEarlierHistory))
            button.bezelStyle = .inline
            return button
        case .waiting:
            let host = NSHostingView(rootView: waitingContent)
            host.sizingOptions = []
            waitingView = host
            return host
        }
    }

    private var waitingContent: AnyView {
        AnyView(AgentThinkingIndicator(activityText: streaming?.activityText, chatWideTypography: wide)
            .environmentObject(store).environment(\.weiBeiTextScale, textScale))
    }

    func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
        for case let cell as NativeConversationMessageRow in rowView.subviews { cell.unbind() }
    }

    private func configure(_ cell: NativeConversationMessageRow) {
        guard let state = cell.state else { return }
        cell.configure(store: store, textScale: textScale, wide: wide,
            activity: streaming?.activityText, onOpenSettings: { [weak self] in self?.openSettings() }, onHeight: { [weak self, weak state] height in
                guard let self, let state, self.states[state.message.id] === state else { return }
                self.submitHeight(height, for: state)
            })
        state.prepare()
    }

    private func invalidateRowWidths() {
        guard columnWidth > 1 else { return }
        let column = min(960, max(1, columnWidth - (wide ? 56 : 24)))
        for state in states.values {
            let user = state.message.role == .user
            let width = user ? min(state.userNaturalWidth ?? 490, max(1, column - 30)) : max(1, column - 28)
            let font = (user ? 14.5 : (wide || column >= 620 ? 16 : 14)) * textScale
            if let height = state.invalidateLayout(width: width, fontSize: font) { pendingHeights[state.message.id] = height }
        }
    }

    private func visibleRows() -> [NativeConversationMessageRow] {
        let visible = tableView.rows(in: scrollView.contentView.bounds)
        guard visible.location != NSNotFound, visible.length > 0 else { return [] }
        return (visible.location..<min(rows.count, NSMaxRange(visible))).compactMap {
            tableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? NativeConversationMessageRow
        }
    }

    private func cell(for id: UUID) -> NativeConversationMessageRow? {
        guard let row = rowByID[id] else { return nil }
        return tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NativeConversationMessageRow
    }

    private func submitHeight(_ height: CGFloat, for state: NativeConversationMessageState) {
        guard height.isFinite, height > 0, abs((pendingHeights[state.message.id] ?? state.height) - height) > 0.5 else { return }
        beginLayoutChange()
        pendingHeights[state.message.id] = ceil(height)
        scheduleHeightTransaction()
    }

    private func beginLayoutChange() {
        if pendingAnchor == nil, !followsLatest, !inTransaction {
            pendingAnchor = readingAnchor ?? captureReadingAnchor()
            readingAnchor = pendingAnchor
        }
    }

    private func scheduleHeightTransaction() {
        guard !heightScheduled else { return }
        heightScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flushHeights() }
    }

    private func flushHeights() {
        heightScheduled = false
        guard isSurfaceVisible else { return }
        let heights = pendingHeights
        pendingHeights.removeAll()
        let anchor = pendingAnchor
        pendingAnchor = nil
        inTransaction = true
        defer { inTransaction = false }
        let indexes = IndexSet(heights.keys.compactMap { rowByID[$0] })
        if !indexes.isEmpty {
            heightTransactionCount += 1
            for (id, height) in heights { states[id]?.height = height }
            withoutAnimation { tableView.noteHeightOfRows(withIndexesChanged: indexes) }
        }
        view.layoutSubtreeIfNeeded()
        if followsLatest { scrollToBottom() }
        else if let anchor, anchor.intent == userIntent { restore(anchor) }
        updateNavigation()
    }

    func captureReadingAnchor() -> ReadingAnchor? {
        let clip = scrollView.contentView
        let y = clip.bounds.minY + clip.bounds.height * 0.32
        let row = tableView.row(at: CGPoint(x: 1, y: y))
        guard rows.indices.contains(row), case let .message(id) = rows[row] else { return nil }
        let rect = tableView.rect(ofRow: row)
        var anchor = ReadingAnchor(messageID: id, characterOffset: nil,
            rowOffset: y - rect.minY, viewportOffset: y - clip.bounds.minY, intent: userIntent)
        if let text = cell(for: id)?.textView, let manager = text.textLayoutManager,
           let content = manager.textContentManager {
            let point = CGPoint(x: 1, y: text.convert(CGPoint(x: 0, y: y), from: tableView).y)
            if let fragment = manager.textLayoutFragment(for: point) {
                for provider in fragment.textAttachmentViewProviders {
                    if let attachment = provider.textAttachment as? NativeChatTextAttachment,
                       let position = attachment.readingPosition(at: point, in: text) {
                        anchor.characterOffset = content.offset(from: content.documentRange.location, to: provider.location)
                        anchor.attachmentPosition = position
                        return anchor
                    }
                }
            }
            if let fragment = manager.textLayoutFragment(for: point),
               let line = fragment.textLineFragment(forVerticalOffset: point.y - fragment.layoutFragmentFrame.minY, requiresExactMatch: false),
               let location = content.location(fragment.textElement?.elementRange?.location ?? fragment.rangeInElement.location, offsetBy: line.characterRange.location) {
                anchor.characterOffset = content.offset(from: content.documentRange.location, to: location)
                let lineY = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
                anchor.viewportOffset = text.convert(CGPoint(x: 0, y: lineY), to: clip).y - clip.bounds.minY
            }
        }
        return anchor
    }

    private func restore(_ anchor: ReadingAnchor) {
        guard let row = rowByID[anchor.messageID] else { return }
        var target = tableView.rect(ofRow: row).minY + anchor.rowOffset - anchor.viewportOffset
        if let offset = anchor.characterOffset, let text = cell(for: anchor.messageID)?.textView,
           let manager = text.textLayoutManager, let content = manager.textContentManager,
           let location = content.location(content.documentRange.location, offsetBy: min(offset, text.string.utf16.count)) {
            // A single saved text position, never the whole document or a retained NSTextLocation.
            manager.ensureLayout(for: NSTextRange(location: location))
            if let fragment = manager.textLayoutFragment(for: location),
               let line = fragment.textLineFragment(for: location, isUpstreamAffinity: false) {
                target = text.convert(CGPoint(x: 0, y: fragment.layoutFragmentFrame.minY + line.typographicBounds.minY),
                    to: scrollView.contentView).y - anchor.viewportOffset
            }
        }
        scroll(to: textAnchorTarget(anchor) ?? target)
    }

    private func textAnchorTarget(_ anchor: ReadingAnchor) -> CGFloat? {
        guard let offset = anchor.characterOffset, let text = cell(for: anchor.messageID)?.textView,
              let manager = text.textLayoutManager, let content = manager.textContentManager else { return nil }
        if let position = anchor.attachmentPosition, let storage = text.textStorage, offset < storage.length,
           let attachment = storage.attribute(.attachment, at: offset, effectiveRange: nil) as? NativeChatTextAttachment,
           let y = attachment.readingY(for: position, in: scrollView.contentView) { return y - anchor.viewportOffset }
        guard
              let location = content.location(content.documentRange.location, offsetBy: min(offset, text.string.utf16.count)),
              let fragment = manager.textLayoutFragment(for: location),
              let line = fragment.textLineFragment(for: location, isUpstreamAffinity: false) else { return nil }
        return text.convert(CGPoint(x: 0, y: fragment.layoutFragmentFrame.minY + line.typographicBounds.minY),
                            to: scrollView.contentView).y - anchor.viewportOffset
    }

    func userWillScroll() {
        userIntent &+= 1
        pendingAnchor = nil
        readingAnchor = nil
        followsLatest = false
    }

    private func scrolled() {
        let clip = scrollView.contentView
        let y = clip.bounds.minY
        defer { previousY = y }
        guard !inTransaction else { return }
        if liveScroll || scrollView.handlingUserScroll {
            pendingAnchor = nil
            readingAnchor = nil
            let bottomDistance = tableView.bounds.maxY - clip.bounds.maxY
            followsLatest = bottomDistance < 40
            if AgentHistoryRevealPolicy.shouldRevealEarlierPage(distanceFromTop: y,
                isUserScrolling: true, isScrollingTowardTop: y < previousY,
                hiddenMessageCount: messages.count - visibleLimit, revealInFlight: revealingHistory) {
                revealEarlierHistory()
            }
        }
        updateNavigation()
    }

    @objc func revealEarlierHistory() {
        guard visibleLimit < messages.count else { return }
        followsLatest = false
        beginLayoutChange()
        revealingHistory = true
        visibleLimit = AgentHistoryRevealPolicy.expandedVisibleLimit(currentLimit: visibleLimit, totalMessageCount: messages.count)
        rebuildRows()
    }

    func jumpToLatest() {
        userIntent &+= 1
        pendingAnchor = nil
        readingAnchor = nil
        followsLatest = true
        scrollToBottom()
        scheduleHeightTransaction()
    }

    private func scrollToBottom() {
        scroll(to: tableView.bounds.maxY - scrollView.contentView.bounds.height + scrollView.contentInsets.bottom)
    }

    private func scroll(to y: CGFloat) {
        let clip = scrollView.contentView
        let origin = clip.constrainBoundsRect(NSRect(x: 0, y: y, width: clip.bounds.width, height: clip.bounds.height)).origin
        // AppKit may already have compensated. Apply only the remaining displacement.
        guard abs(origin.y - clip.bounds.minY) > 0.5 else { return }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    func navigate(to railID: String) {
        guard let turn = turns.first(where: { "chat-turn-\($0.id.uuidString)" == railID }) else { return }
        userWillScroll()
        visibleLimit = max(visibleLimit, messages.count - turn.index)
        rebuildRows()
        pendingAnchor = ReadingAnchor(messageID: turn.id, characterOffset: 0, rowOffset: 0,
            viewportOffset: 10, intent: userIntent)
        readingAnchor = pendingAnchor
        if let row = rowByID[turn.id] { scroll(to: tableView.rect(ofRow: row).minY) }
        updateNavigation()
    }

    private func rebuildTurns() {
        turns = []
        turnIDByMessage.removeAll(keepingCapacity: true)
        for (index, message) in messages.enumerated() {
            if message.role == .user || turns.isEmpty {
                turns.append(Turn(id: message.id, index: index,
                    question: message.role == .user ? preview(message.text) : store.ui("对话回复", "Response"), answer: ""))
            }
            if message.role == .assistant, turns[turns.count - 1].answer.isEmpty {
                turns[turns.count - 1].answer = preview(message.text)
            }
            turnIDByMessage[message.id] = "chat-turn-\(turns[turns.count - 1].id.uuidString)"
        }
        navigation.items = turns.enumerated().map { index, turn in
            ContentRailItem(id: "chat-turn-\(turn.id.uuidString)",
                position: turns.count > 1 ? CGFloat(index) / CGFloat(turns.count - 1) : 0,
                title: turn.question, excerpt: turn.answer.isEmpty ? store.ui("等待回复", "Waiting for response") : turn.answer,
                metadata: store.ui("第 \(index + 1) / \(turns.count) 轮", "Turn \(index + 1) / \(turns.count)"))
        }
    }

    private func preview(_ text: String) -> String {
        String(String(text.prefix(300)).replacingOccurrences(of: #"[`*_>#\[\]()]"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(180))
    }

    private func updateNavigation() {
        let clip = scrollView.contentView
        let show = tableView.bounds.maxY - clip.bounds.maxY > 160
        if navigation.showsJumpToLatest != show { navigation.showsJumpToLatest = show }
        let row = tableView.row(at: CGPoint(x: 1, y: clip.bounds.minY + clip.bounds.height * 0.32))
        guard rows.indices.contains(row), case let .message(id) = rows[row],
              let active = turnIDByMessage[id] else { return }
        if navigation.activeID != active { navigation.activeID = active }
    }

    private func withoutAnimation(_ body: () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            body()
        }
    }

    final class ConversationScrollView: NSScrollView {
        var onUserScroll: (() -> Void)?
        var onWidthChange: (() -> Void)?
        private(set) var handlingUserScroll = false
        override func setFrameSize(_ size: NSSize) {
            if size.width != frame.width { onWidthChange?() }
            super.setFrameSize(size)
        }
        override func scrollWheel(with event: NSEvent) {
            onUserScroll?()
            handlingUserScroll = true
            super.scrollWheel(with: event)
            handlingUserScroll = false
        }
    }
}
