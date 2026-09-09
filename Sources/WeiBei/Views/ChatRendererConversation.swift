#if CHAT_RENDERER_LAB
import AppKit
import ChatRendererKit
import Combine
import SwiftUI
import WeiBeiCore

@MainActor
final class ChatRendererSession {
    @MainActor final class MessageState {
        let document = CandidateDocument()
        let markdownMemo = AgentMessageMarkdownMemo()
        let imageHandler = MarkdownImageSchemeHandler()
        var heights: [CGFloat: CGFloat] = [:]
        var lastHeight: CGFloat = 96
        var actionDrafts: [UUID: AgentReplyActionDraft] = [:]
    }
    private var conversations: [UUID?: [UUID: MessageState]] = [:]
    private(set) var activeSessionID: UUID?
    var messages: [UUID: MessageState] { conversations[activeSessionID] ?? [:] }
    var preparedDocuments: [CandidateDocument] { conversations.values.flatMap { $0.values.map(\.document) } }
    weak var list: ChatRendererListView?
    // CoreText/code/table layout stays in a small recent working set. Parsed
    // documents and measurements survive native view eviction.
    let surfaces = NSCache<NSString, CandidateTextView>()
    init() { surfaces.countLimit = 8 }
    func activate(_ id: UUID?) { activeSessionID = id }
    private func surfaceKey(_ id: UUID, in conversationID: UUID?) -> NSString {
        "\((conversationID ?? activeSessionID)?.uuidString ?? "empty")/\(id.uuidString)" as NSString
    }
    func surface(for id: UUID, in conversationID: UUID?) -> CandidateTextView {
        let key = surfaceKey(id, in: conversationID)
        // SwiftUI can create the replacement host before dismantling the old
        // one. A mounted NSView must never be handed to both hosts.
        if let view = surfaces.object(forKey: key), view.superview == nil { return view }
        let view = CandidateTextView()
        surfaces.setObject(view, forKey: key)
        return view
    }
    func state(for id: UUID, in conversationID: UUID? = nil) -> MessageState {
        let key = conversationID ?? activeSessionID
        if let value = conversations[key]?[id] { return value }
        let value = MessageState()
        conversations[key, default: [:]][id] = value
        return value
    }
    func discardRemovedMessages(keeping ids: Set<UUID>) {
        for id in messages.keys where !ids.contains(id) {
            conversations[activeSessionID]?[id]?.imageHandler.invalidate()
            conversations[activeSessionID]?[id] = nil
            surfaces.removeObject(forKey: surfaceKey(id, in: activeSessionID))
        }
    }
}

private struct ChatRendererConversationIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

private struct ChatRendererSessionKey: EnvironmentKey {
    static let defaultValue: ChatRendererSession? = nil
}
extension EnvironmentValues {
    var chatRendererConversationID: UUID? {
        get { self[ChatRendererConversationIDKey.self] }
        set { self[ChatRendererConversationIDKey.self] = newValue }
    }
    var chatRendererSession: ChatRendererSession? {
        get { self[ChatRendererSessionKey.self] }
        set { self[ChatRendererSessionKey.self] = newValue }
    }
}

/// The real AgentBubble supplies the row, including sources and editable actions.
/// Only this host owns the outer scroll position.
struct ChatRendererConversation: NSViewRepresentable {
    var sessionID: UUID?
    var messages: [AgentMessage]
    let session: ChatRendererSession
    var presentationID: String = ""
    var columnWidth: CGFloat?
    let makeRow: (AgentMessage) -> AnyView
    var onReading: (UUID?, Bool) -> Void = { _, _ in }
    var onContentHeight: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> ChatRendererListView { ChatRendererListView(session: session) }
    func updateNSView(_ view: ChatRendererListView, context: Context) {
        view.columnWidth = columnWidth
        view.makeRow = makeRow
        view.onReading = onReading
        view.onContentHeight = onContentHeight
        view.update(sessionID: sessionID, messages: messages, presentationID: presentationID)
    }
}

@MainActor
final class ChatRendererListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    let scroll = ChatRendererScrollView()
    let table = NSTableView()
    let session: ChatRendererSession
    var columnWidth: CGFloat? {
        willSet { if newValue != columnWidth, pendingAnchor == nil { pendingAnchor = captureAnchor() } }
        didSet { if oldValue != columnWidth { needsLayout = true } }
    }
    var makeRow: ((AgentMessage) -> AnyView)?
    var onReading: (UUID?, Bool) -> Void = { _, _ in }
    var onContentHeight: (CGFloat) -> Void = { _ in }
    private var sessionID: UUID?
    private var presentationID = ""
    private var messages: [AgentMessage] = []
    private var byID: [UUID: AgentMessage] = [:]
    private var indices: [UUID: Int] = [:]
    private var visibleIDs: [UUID] = []
    private var loadedCount = AgentHistoryRevealPolicy.pageSize
    private var observers: [NSObjectProtocol] = []
    private var pendingRows: Set<UUID> = []
    private var heightUpdateQueued = false
    private var updatingGeometry = false
    private var pendingAnchor: ReadingAnchor?
    private var lastWidth: CGFloat = 0
    private var lastReportedID: UUID?
    private var lastReportedFollowing: Bool?
    private var lastScrollOrigin: CGPoint = .zero
    private(set) var followsLatest = true
    private(set) var fullReloadCount = 0
    private(set) var updatedRowCount = 0
    private(set) var heightUpdateCount = 0
    private(set) var timings: [LabTiming] = []
    override var isFlipped: Bool { true }

    struct ReadingAnchor {
        let id: UUID
        let rowOffset: CGFloat
        let character: Int?
        let characterOffset: CGFloat
    }

    init(session: ChatRendererSession) {
        self.session = session
        super.init(frame: .zero)
        session.list = self
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.intercellSpacing = .zero
        table.usesAutomaticRowHeights = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let column = NSTableColumn(identifier: .init("message"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.delegate = self; table.dataSource = self
        scroll.documentView = table
        addSubview(scroll)
        scroll.contentView.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.didScroll() }
            })
        scroll.onUserScroll = { [weak self] in self?.followsLatest = false }
        observers.append(NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification,
            object: scroll, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.followsLatest = false; self?.pendingAnchor = nil }
            })
        observers.append(NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification,
            object: scroll, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.followsLatest = self.distanceFromBottom < 48
                    self.reportReading()
                }
            })
    }
    required init?(coder: NSCoder) { nil }
    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    private var rowWidth: CGFloat {
        max(1, min(table.bounds.width, columnWidth ?? min(table.bounds.width - 24, AgentChatLayoutMetrics.wideMaxWidth)))
    }
    private var distanceFromBottom: CGFloat { table.bounds.height - scroll.contentView.bounds.maxY }
    private var hiddenCount: Int { max(0, messages.count - loadedCount) }

    func update(sessionID nextSessionID: UUID?, messages next: [AgentMessage], presentationID: String = "") {
        let changedPresentation = self.presentationID != presentationID
        self.presentationID = presentationID
        let changedSession = sessionID != nextSessionID
        if !changedSession, !changedPresentation, next == messages { return }
        let old = byID
        let nextIDs = next.map(\.id)
        let oldAllIDs = messages.map(\.id)
        let anchor = changedSession ? nil : captureAnchor()
        pendingAnchor = anchor
        sessionID = nextSessionID
        session.activate(nextSessionID)
        if changedSession {
            loadedCount = AgentHistoryRevealPolicy.pageSize; followsLatest = true
            pendingRows.removeAll()
        } else if nextIDs.starts(with: oldAllIDs) {
            loadedCount += next.count - messages.count
        }
        messages = next
        byID = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        let ids = Array(nextIDs.suffix(loadedCount))
        updatingGeometry = true
        if changedSession || !Self.isSingleInsertion(from: visibleIDs, to: ids) {
            if visibleIDs != ids || changedSession {
                visibleIDs = ids
                rebuildIndices()
                table.reloadData(); fullReloadCount += 1
            }
        } else if visibleIDs != ids {
            let oldIDs = Set(visibleIDs)
            visibleIDs = ids; rebuildIndices()
            let inserted = IndexSet(ids.enumerated().filter { !oldIDs.contains($0.element) }.map { $0.offset + 1 })
            table.insertRows(at: inserted, withAnimation: [])
        }
        if !changedSession {
            session.discardRemovedMessages(keeping: Set(nextIDs))
        }
        if changedPresentation {
            for state in session.messages.values { state.heights.removeAll() }
        }
        for id in visibleIDs where changedPresentation || old[id] != byID[id] {
            guard let index = indices[id], let message = byID[id] else { continue }
            session.state(for: id).heights.removeAll()
            if let row = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? ChatRendererRow {
                configure(row, message: message)
                enqueueHeightChange(id)
                updatedRowCount += 1
            }
        }
        if let button = table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? NSButton { configureHistory(button) }
        table.layoutSubtreeIfNeeded()
        if followsLatest { scrollToBottom() } else if let anchor { restore(anchor) }
        updatingGeometry = false
    }

    private static func isSingleInsertion(from old: [UUID], to new: [UUID]) -> Bool {
        guard new.count >= old.count else { return false }
        let oldSet = Set(old)
        return new.filter { oldSet.contains($0) } == old
    }
    private func rebuildIndices() { indices = Dictionary(uniqueKeysWithValues: visibleIDs.enumerated().map { ($0.element, $0.offset + 1) }) }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleIDs.count + 1 }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if row == 0 { return hiddenCount > 0 ? 44 : 18 }
        guard visibleIDs.indices.contains(row - 1) else { return 96 }
        let state = session.state(for: visibleIDs[row - 1])
        return state.heights[rowWidth] ?? state.lastHeight
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row == 0 {
            let button = NSButton(title: "", target: self, action: #selector(loadEarlier))
            button.bezelStyle = .inline; configureHistory(button); return button
        }
        guard visibleIDs.indices.contains(row - 1), let message = byID[visibleIDs[row - 1]] else { return nil }
        let view = (table.makeView(withIdentifier: .init("chat-renderer-row"), owner: self) as? ChatRendererRow) ?? ChatRendererRow()
        view.identifier = .init("chat-renderer-row")
        configure(view, message: message)
        enqueueHeightChange(message.id)
        return view
    }
    private func configureHistory(_ button: NSButton) {
        button.isHidden = hiddenCount == 0
        button.title = hiddenCount > 0 ? "查看更早的 \(min(AgentHistoryRevealPolicy.pageSize, hiddenCount)) 条消息" : ""
        button.isEnabled = hiddenCount > 0
    }
    private func configure(_ row: ChatRendererRow, message: AgentMessage) {
        guard let makeRow else { return }
        if row.messageID != message.id { row.measuredContent = nil }
        row.messageID = message.id
        row.onSizeChange = { [weak self] in self?.enqueueHeightChange(message.id) }
        row.host.rootView = makeRow(message)
            .environment(\.chatRendererSession, session)
            .environment(\.chatRendererConversationID, sessionID)
            .id("\(sessionID?.uuidString ?? "empty")/\(message.id.uuidString)")
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear
                    .onAppear { [weak row] in row?.reportContentSize(geometry.size, messageID: message.id) }
                    .onChange(of: geometry.size) { [weak row] _, size in row?.reportContentSize(size, messageID: message.id) }
            }).eraseToAnyView()
        row.contentWidth = rowWidth
    }

    @objc func loadEarlier() {
        guard hiddenCount > 0 else { return }
        let anchor = captureAnchor()
        pendingAnchor = anchor
        let previous = visibleIDs.count
        loadedCount += min(AgentHistoryRevealPolicy.pageSize, hiddenCount)
        visibleIDs = Array(messages.suffix(loadedCount).map(\.id)); rebuildIndices()
        updatingGeometry = true
        table.insertRows(at: IndexSet(integersIn: 1..<(visibleIDs.count - previous + 1)), withAnimation: [])
        updateTableHeights(IndexSet(integer: 0))
        if let button = table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? NSButton { configureHistory(button) }
        table.layoutSubtreeIfNeeded()
        if let anchor { restore(anchor) }
        updatingGeometry = false
        followsLatest = false
    }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize.width != frame.width, pendingAnchor == nil { pendingAnchor = captureAnchor() }
        super.setFrameSize(newSize)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        updatingGeometry = true
        scroll.frame = bounds
        scroll.tile()
        table.setFrameSize(NSSize(width: max(1, scroll.contentView.bounds.width), height: table.frame.height))
        table.tableColumns.first?.width = table.bounds.width
        if lastWidth != rowWidth {
            lastWidth = rowWidth
            for row in mountedRows() { row.contentWidth = rowWidth; enqueueHeightChange(row.messageID) }
        }
        updatingGeometry = false
    }

    func enqueueHeightChange(_ id: UUID) {
        guard indices[id] != nil else { return }
        if pendingAnchor == nil, !followsLatest, !updatingGeometry { pendingAnchor = captureAnchor() }
        pendingRows.insert(id)
        guard !heightUpdateQueued else { return }
        heightUpdateQueued = true
        DispatchQueue.main.async { [weak self] in self?.flushHeightChanges() }
    }

    func flushHeightChanges() {
        heightUpdateQueued = false
        let ids = pendingRows; pendingRows.removeAll(keepingCapacity: true)
        guard !ids.isEmpty else { return }
        let anchor = pendingAnchor ?? captureAnchor(); pendingAnchor = nil
        let start = ProcessInfo.processInfo.systemUptime
        var changed = IndexSet()
        updatingGeometry = true
        for id in ids {
            guard let index = indices[id], let row = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? ChatRendererRow,
                  row.messageID == id else { continue }
            guard let height = row.measure(width: rowWidth), height.isFinite, height > 0 else { continue }
            let state = session.state(for: id)
            let previous = table.rect(ofRow: index).height
            state.heights[rowWidth] = height; state.lastHeight = height
            if abs(previous - height) > 0.5 { changed.insert(index) }
        }
        if !changed.isEmpty {
            updateTableHeights(changed)
            heightUpdateCount += changed.count
            table.layoutSubtreeIfNeeded()
        }
        if followsLatest { scrollToBottom() } else if let anchor { restore(anchor) }
        updatingGeometry = false
        reportReading()
        onContentHeight(table.bounds.height)
        timings.append(.init(operation: "list_layout_transaction", milliseconds:
            (ProcessInfo.processInfo.systemUptime - start) * 1_000, revision: heightUpdateCount))
    }

    private func updateTableHeights(_ rows: IndexSet) {
        // Row origins must match the new height before restoring text anchors.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            table.noteHeightOfRows(withIndexesChanged: rows)
            table.layoutSubtreeIfNeeded()
        }
    }

    func captureAnchor() -> ReadingAnchor? {
        let top = scroll.contentView.bounds.minY
        let rowIndex = max(1, table.row(at: NSPoint(x: 1, y: top + 1)))
        guard visibleIDs.indices.contains(rowIndex - 1) else { return nil }
        let id = visibleIDs[rowIndex - 1]
        let row = table.view(atColumn: 0, row: rowIndex, makeIfNecessary: false)
        let text = row.flatMap { firstText(in: $0) }
        let position = text?.readingPosition(at: NSPoint(x: 1, y: top), in: table)
        return ReadingAnchor(id: id, rowOffset: top - table.rect(ofRow: rowIndex).minY,
            character: position?.index, characterOffset: position?.offset ?? 0)
    }
    func restore(_ anchor: ReadingAnchor) {
        guard let row = indices[anchor.id] else { return }
        var y = table.rect(ofRow: row).minY + anchor.rowOffset
        if let index = anchor.character,
           let rowView = table.view(atColumn: 0, row: row, makeIfNecessary: false), let text = firstText(in: rowView) {
            text.layoutSubtreeIfNeeded()
            if let point = text.readingPoint(index: index, offset: anchor.characterOffset, in: table) { y = point.y }
        }
        setScrollY(y)
    }
    func scrollToBottom() { followsLatest = true; setScrollY(table.bounds.height - scroll.contentView.bounds.height) }
    func reveal(_ id: UUID) {
        followsLatest = false
        pendingAnchor = ReadingAnchor(id: id, rowOffset: 0, character: nil, characterOffset: 0)
        if indices[id] == nil, let index = messages.firstIndex(where: { $0.id == id }) {
            loadedCount = max(loadedCount, messages.count - index)
            visibleIDs = Array(messages.suffix(loadedCount).map(\.id)); rebuildIndices()
            table.reloadData(); fullReloadCount += 1
        }
        guard let index = indices[id] else { return }
        followsLatest = false
        setScrollY(table.rect(ofRow: index).minY)
    }
    private func setScrollY(_ y: CGFloat) {
        let maximum = max(0, table.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, y))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func didScroll() {
        if lastWidth != rowWidth { needsLayout = true }
        let origin = scroll.contentView.bounds.origin
        let moved = origin != lastScrollOrigin
        lastScrollOrigin = origin
        guard !updatingGeometry else { return }
        // Scrolling outside our layout transaction includes keyboard and
        // accessibility actions, which do not deliver scroll-wheel events.
        if moved {
            pendingAnchor = nil; followsLatest = distanceFromBottom < 48
        }
        reportReading()
    }
    private func reportReading() {
        let index = max(1, table.row(at: CGPoint(x: 1, y: scroll.contentView.bounds.minY + 1)))
        let id = visibleIDs.indices.contains(index - 1) ? visibleIDs[index - 1] : nil
        guard id != lastReportedID || followsLatest != lastReportedFollowing else { return }
        lastReportedID = id; lastReportedFollowing = followsLatest
        let following = followsLatest
        let currentSessionID = sessionID
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionID == currentSessionID else { return }
            self.onReading(id, following)
        }
    }
    private func mountedRows() -> [ChatRendererRow] {
        var rows: [ChatRendererRow] = []
        table.enumerateAvailableRowViews { _, index in
            if let row = self.table.view(atColumn: 0, row: index, makeIfNecessary: false) as? ChatRendererRow {
                rows.append(row)
            }
        }
        return rows
    }
    private func firstText(in view: NSView) -> CandidateTextView? {
        if let text = view as? CandidateTextView { return text }
        for child in view.subviews { if let text = firstText(in: child) { return text } }
        return nil
    }
}

@MainActor
final class ChatRendererScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?
    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        super.scrollWheel(with: event)
    }
}

@MainActor
private final class ChatRendererRow: NSTableCellView {
    var messageID = UUID()
    let host = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))
    var onSizeChange: (() -> Void)?
    var measuredContent: CGSize?
    var contentWidth: CGFloat = 640 { didSet { if oldValue != contentWidth { needsLayout = true } } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        host.sizingOptions = []
        addSubview(host)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        host.frame = NSRect(x: max(0, (bounds.width - contentWidth) / 2), y: 10,
            width: contentWidth, height: max(1, bounds.height - 20))
    }
    func reportContentSize(_ size: CGSize, messageID: UUID) {
        guard self.messageID == messageID, size != measuredContent else { return }
        measuredContent = size
        onSizeChange?()
    }
    func measure(width: CGFloat) -> CGFloat? {
        contentWidth = width
        host.setFrameSize(NSSize(width: width, height: max(1, host.frame.height)))
        host.layoutSubtreeIfNeeded()
        guard let measuredContent, abs(measuredContent.width - width) < 1 else { return nil }
        return ceil(measuredContent.height) + 24
    }
}

private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}
#endif
