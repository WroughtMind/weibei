import UIKit
import Litext
import MarkdownView
import QuartzCore

final class ConversationController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, UITextViewDelegate {
    let store = ContentStore()
    let flow = UICollectionViewFlowLayout()
    lazy var collection = UICollectionView(frame: .zero, collectionViewLayout: flow)
    let input = UITextView()
    private let toolbar = UIStackView()
    private let status = UILabel()
    private let send = UIButton(type: .system)
    private let latest = UIButton(type: .system)
    private var preparation: Task<Void, Never>?
    private var replay: Task<Void, Never>?
    private var scenarioGeneration = 0
    private var scenario = "rich"
    private var earlier = 480
    private var layoutTransaction = false
    private var laidOutWidth: CGFloat = 0
    private(set) var messages: [LabMessage] = []
    private(set) var followsLatest = true
    private(set) var bodyWidth: CGFloat = 680
    var maximumBodyWidth: CGFloat = 760
    var openWorkspace: ((Int) -> Void)?
    var toggleWorkspace: (() -> Void)?
    var saveNote: ((String) -> Void)?
    lazy var selection = ConversationSelection(controller: self)
    let metrics = LabMetrics()
    private var pendingChanges: [String: PreparedBlock] = [:]
    private var changeScheduled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        collection.backgroundColor = .clear
        collection.dataSource = self; collection.delegate = self
        collection.register(MessageCell.self, forCellWithReuseIdentifier: "message")
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .none
        collection.accessibilityLabel = "会话消息列表"
        flow.minimumLineSpacing = 0
        for child in [toolbar, status, collection, input, send, latest] { view.addSubview(child) }
        toolbar.spacing = 16; toolbar.alignment = .center
        toolbar.addArrangedSubview(button("阅读区", symbol: "sidebar.left", action: { [weak self] in self?.toggleWorkspace?() }))
        let title = UILabel(); title.text = "会话实验"; title.font = .systemFont(ofSize: 18, weight: .semibold)
        toolbar.addArrangedSubview(title)
        toolbar.addArrangedSubview(button("载入更早记录", symbol: "clock.arrow.circlepath", action: { [weak self] in self?.prependHistory() }))
        let menu = UIButton(type: .system)
        menu.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        menu.accessibilityLabel = "样本与验证"
        menu.widthAnchor.constraint(equalToConstant: 30).isActive = true
        menu.showsMenuAsPrimaryAction = true
        menu.menu = UIMenu(children: [
            UIAction(title: "长历史 · 240 条起步") { [weak self] _ in self?.loadScenario("history") },
            UIAction(title: "单条长回答 · 140 节") { [weak self] _ in self?.loadScenario("long") },
            UIAction(title: "富内容与桌面操作") { [weak self] _ in self?.loadScenario("rich") },
            UIAction(title: "开始固定流式重放") { [weak self] _ in self?.startReplay() },
            UIAction(title: "运行必要行为检查") { [weak self] _ in self?.runChecks() },
            UIAction(title: "采样连续滚动与热回看") { [weak self] _ in self?.sampleScroll() },
            UIAction(title: "导出本次性能记录") { [weak self] _ in self?.exportEvidence() }
        ])
        toolbar.addArrangedSubview(menu)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabel
        status.text = "固定重放 · 未接通模型 · 独立合成资料"
        input.font = .systemFont(ofSize: 16)
        input.backgroundColor = .secondarySystemBackground
        input.layer.cornerRadius = 8
        input.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        input.delegate = self
        input.accessibilityLabel = "输入问题，⌘回车发送；当前使用固定重放"
        send.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        send.accessibilityLabel = "发送并重放固定回答"
        send.addTarget(self, action: #selector(sendPressed), for: .touchUpInside)
        latest.setTitle("回到最新", for: .normal)
        latest.backgroundColor = .secondarySystemBackground
        latest.layer.cornerRadius = 6
        latest.addAction(UIAction { [weak self] _ in self?.scrollToLatest() }, for: .touchUpInside)
        latest.isHidden = true
        store.changed = { [weak self] in self?.contentChanged($0) }
        store.openLink = { [weak self] url in self?.open(url) }
        store.saveNote = { [weak self] text in self?.saveNote?(text) }
        store.interaction = { [weak self] body in self?.selection.bind(body) }
        NotificationCenter.default.addObserver(self, selector: #selector(imageDidLoad(_:)), name: LabImages.didLoad, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if messages.isEmpty, preparation == nil {
            loadScenario("rich")
            if CommandLine.arguments.contains("--self-check") {
                Task {
                    await preparation?.value
                    runChecks { success in exit(success ? 0 : 1) }
                }
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let nextWidth = max(240, min(maximumBodyWidth, width - 56))
        let anchor = laidOutWidth > 0 && nextWidth != bodyWidth ? captureAnchor() : nil
        toolbar.frame = CGRect(x: 28, y: 12, width: min(width - 56, 370), height: 34)
        status.frame = CGRect(x: 28, y: 48, width: width - 56, height: 24)
        input.frame = CGRect(x: 24, y: view.bounds.height - 112, width: width - 88, height: 88)
        send.frame = CGRect(x: width - 56, y: view.bounds.height - 90, width: 40, height: 40)
        collection.frame = CGRect(x: 0, y: 78, width: width, height: max(100, view.bounds.height - 202))
        latest.frame = CGRect(x: width - 120, y: collection.frame.maxY - 38, width: 96, height: 28)
        if nextWidth != bodyWidth || laidOutWidth == 0 {
            let started = CACurrentMediaTime()
            layoutTransaction = true
            bodyWidth = nextWidth
            let inset = max(0, (width - bodyWidth) / 2)
            flow.sectionInset = UIEdgeInsets(top: 14, left: inset, bottom: 10, right: inset)
            for message in messages { for block in message.blocks { autoreleasepool { _ = store.measure(block, width: bodyWidth) } } }
            flow.invalidateLayout(); collection.layoutIfNeeded()
            if let anchor { restore(anchor) }
            layoutTransaction = false
            if laidOutWidth > 0 { metrics.record("resize_ms", (CACurrentMediaTime() - started) * 1000) }
        }
        laidOutWidth = width
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { messages.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        messages[section].blocks.count + 2
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt path: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "message", for: path) as! MessageCell
        configure(cell, at: path)
        return cell
    }
    func configure(_ cell: MessageCell, at path: IndexPath) {
        let message = messages[path.section]
        if path.item == 0 { cell.showHeader(message) }
        else if path.item <= message.blocks.count {
            cell.show(body: store.view(for: message.blocks[path.item - 1], width: bodyWidth))
            selection.paint(cell.body!)
        } else {
            cell.showActions(message, copy: { UIPasteboard.general.string = message.markdown },
                             quote: { [weak self] in self?.quote(message.markdown) },
                             source: { [weak self] in self?.openWorkspace?(0) })
        }
    }
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt path: IndexPath) -> CGSize {
        let message = messages[path.section]
        let height: CGFloat = path.item == 0 ? 30 : (path.item > message.blocks.count ? 42 : message.blocks[path.item - 1].height + 14)
        return CGSize(width: bodyWidth, height: height)
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt path: IndexPath) {
        (cell as? MessageCell)?.body?.saveInteractionState()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collection, !layoutTransaction else { return }
        followsLatest = distanceToBottom < 32
        latest.isHidden = followsLatest
    }
    var distanceToBottom: CGFloat {
        max(0, collection.contentSize.height - collection.bounds.height - collection.contentOffset.y)
    }

    func loadScenario(_ name: String) {
        stopReplay()
        replay = nil
        send.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
        preparation?.cancel()
        scenarioGeneration += 1
        scenario = name
        let generation = scenarioGeneration
        selection.clear()
        messages = []
        store.reset()
        collection.reloadData()
        earlier = name == "history" ? 480 : 0
        status.text = "正在准备\(name == "history" ? "长历史" : name == "long" ? "长回答" : "富内容")…"
        send.isEnabled = false
        let started = CACurrentMediaTime()
        preparation = Task { [weak self] in
            guard let self else { return }
            var prepared: [LabMessage] = []
            if name == "history" {
                prepared = (480..<720).map { LabMessage(id: "history-\($0)", author: "魏碑 · 合成历史 \($0 + 1)", markdown: LabFixture.history($0)) }
            }
            prepared.append(LabMessage(id: "\(name)-answer", author: "魏碑 · 独立候选", markdown: name == "long" ? LabFixture.longAnswer : LabFixture.rich))
            for message in prepared {
                guard !Task.isCancelled, generation == scenarioGeneration else { return }
                _ = await store.prepare(message, width: bodyWidth)
            }
            guard !Task.isCancelled, generation == scenarioGeneration else { return }
            messages = prepared
            layoutTransaction = true
            collection.reloadData(); collection.layoutIfNeeded()
            if name == "history" { scrollToLatest() } else { collection.contentOffset = .zero; followsLatest = false }
            layoutTransaction = false
            metrics.record("\(name)_first_prepare_and_layout_ms", (CACurrentMediaTime() - started) * 1000)
            metrics.record("\(name)_message_count", Double(messages.count))
            metrics.record("\(name)_body_block_count", Double(messages.reduce(0) { $0 + $1.blocks.count }))
            metrics.record("\(name)_source_utf16_count", Double(messages.reduce(0) { $0 + $1.markdown.utf16.count }))
            if let memory = LabMetrics.residentMemory() { metrics.record("\(name)_resident_memory_bytes", Double(memory)) }
            status.text = "\(messages.count) 条会话 · 固定重放，未接通模型"
            send.isEnabled = true
            preparation = nil
        }
    }

    func prependHistory() {
        guard preparation == nil, earlier > 0 else { status.text = "这个样本没有更早历史"; return }
        let end = earlier, start = max(0, end - 80)
        let generation = scenarioGeneration
        status.text = "载入更早的 80 条…"
        preparation = Task { [weak self] in
            guard let self else { return }
            let incoming = (start..<end).map { LabMessage(id: "history-\($0)", author: "魏碑 · 合成历史 \($0 + 1)", markdown: LabFixture.history($0)) }
            for message in incoming {
                _ = await store.prepare(message, width: bodyWidth)
                guard !Task.isCancelled, generation == scenarioGeneration else { return }
            }
            let anchor = captureAnchor()
            layoutTransaction = true
            messages.insert(contentsOf: incoming, at: 0)
            UIView.performWithoutAnimation {
                collection.performBatchUpdates { collection.insertSections(IndexSet(integersIn: 0..<incoming.count)) }
            }
            collection.layoutIfNeeded()
            if let anchor { restore(anchor) }
            layoutTransaction = false
            earlier = start; preparation = nil
            status.text = "已载入 \(messages.count) 条 · 阅读位置保留"
        }
    }

    @objc func sendPressed() {
        if replay != nil { stopReplay(); return }
        guard input.markedTextRange == nil, !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = input.text!
        input.text = ""
        startReplay(question: text)
    }
    func startReplay(question: String = "请按固定事件重放这段回答，便于比较阅读体验。") {
        guard preparation == nil, replay == nil else { return }
        let generation = scenarioGeneration
        replay = Task { [weak self] in
            guard let self else { return }
            let question = LabMessage(author: "你", markdown: question)
            _ = await store.prepare(question, width: bodyWidth)
            guard generation == scenarioGeneration else { return }
            guard !Task.isCancelled else { replay = nil; return }
            let answer = LabMessage(author: "魏碑 · 固定事件重放", markdown: "")
            answer.state = .streaming
            layoutTransaction = true
            let first = messages.count
            messages.append(contentsOf: [question, answer])
            UIView.performWithoutAnimation {
                collection.performBatchUpdates { collection.insertSections(IndexSet(integersIn: first..<messages.count)) }
            }
            collection.layoutIfNeeded(); scrollToLatest()
            layoutTransaction = false
            send.setImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
            send.accessibilityLabel = "停止重放并保留正文"
            let characters = Array(LabFixture.replay)
            var cursor = 0
            let clock = ContinuousClock()
            var deadline = clock.now
            while cursor < characters.count, !Task.isCancelled, generation == scenarioGeneration {
                let end = min(characters.count, cursor + 24)
                let old = answer.blocks
                answer.append(String(characters[cursor..<end]))
                cursor = end
                let started = CACurrentMediaTime()
                _ = await store.prepare(answer, width: bodyWidth)
                guard generation == scenarioGeneration else { return }
                applyBlocks(answer, previous: old)
                metrics.record("stream_apply_ms", (CACurrentMediaTime() - started) * 1000)
                deadline += .milliseconds(70)
                do { try await clock.sleep(until: deadline) } catch { break }
            }
            guard generation == scenarioGeneration else { return }
            if answer.state != .stopped { answer.state = Task.isCancelled ? .stopped : .complete }
            refreshFooter(answer)
            send.setImage(UIImage(systemName: "arrow.up.circle.fill"), for: .normal)
            send.accessibilityLabel = "发送并重放固定回答"
            status.text = answer.state == .complete ? "重放完成 · 正文与尾字保留" : "已停止 · 已收到的正文保留"
            replay = nil
        }
    }
    func stopReplay() {
        replay?.cancel()
        if let message = messages.last, message.state == .streaming { message.state = .stopped; refreshFooter(message) }
    }
    private func applyBlocks(_ message: LabMessage, previous: [PreparedBlock]) {
        guard let section = messages.firstIndex(where: { $0 === message }) else { return }
        let anchor = followsLatest ? nil : captureAnchor()
        let follow = followsLatest
        layoutTransaction = true
        let old = previous.count, new = message.blocks.count
        UIView.performWithoutAnimation {
            collection.performBatchUpdates {
                if new > old { collection.insertItems(at: (old+1...new).map { IndexPath(item: $0, section: section) }) }
                if old > new { collection.deleteItems(at: (new+1...old).map { IndexPath(item: $0, section: section) }) }
                flow.invalidateLayout()
            }
        }
        for index in 0..<new where index >= old || previous[index] !== message.blocks[index] {
            let path = IndexPath(item: index + 1, section: section)
            if let cell = collection.cellForItem(at: path) as? MessageCell { configure(cell, at: path) }
        }
        collection.layoutIfNeeded()
        if follow { scrollToLatest() } else if let anchor { restore(anchor) }
        layoutTransaction = false
    }
    private func refreshFooter(_ message: LabMessage) {
        guard let section = messages.firstIndex(where: { $0 === message }) else { return }
        let path = IndexPath(item: message.blocks.count + 1, section: section)
        if let cell = collection.cellForItem(at: path) as? MessageCell { configure(cell, at: path) }
    }

    private func contentChanged(_ block: PreparedBlock) {
        guard messages.contains(where: { $0.blocks.contains(where: { $0 === block }) }) else { return }
        pendingChanges[block.id] = block
        guard !changeScheduled else { return }
        changeScheduled = true
        Task { [weak self] in
            guard let self else { return }
            let anchor = followsLatest ? nil : captureAnchor()
            let follow = followsLatest
            let changes = pendingChanges; pendingChanges.removeAll(); changeScheduled = false
            layoutTransaction = true
            for block in changes.values where messages.contains(where: { $0.blocks.contains(where: { $0 === block }) }) {
                block.width = 0
                let body = store.view(for: block, width: bodyWidth)
                if case .markdown = block.kind { body.markdown.invalidateInlineDecoration() }
                block.height = body.measure(width: bodyWidth)
            }
            flow.invalidateLayout(); collection.layoutIfNeeded()
            if follow { scrollToLatest() } else if let anchor { restore(anchor) }
            layoutTransaction = false
        }
    }

    @objc private func imageDidLoad(_ notification: Notification) {
        guard let source = notification.object as? String else { return }
        // Image readiness belongs to content, even if the original cell/view
        // has already left the bounded pool.
        for message in messages {
            for block in message.blocks where block.imageSources.contains(source) { contentChanged(block) }
        }
    }

    struct Anchor {
        let messageID: String
        let item: Int
        let character: Int?
        let offset: CGFloat
    }
    func captureAnchor() -> Anchor? {
        let paths = collection.indexPathsForVisibleItems.sorted()
        let y = collection.contentOffset.y + 4
        guard let path = paths.first(where: { (collection.layoutAttributesForItem(at: $0)?.frame.maxY ?? 0) > y }),
              path.section < messages.count, let frame = collection.layoutAttributesForItem(at: path)?.frame else { return nil }
        let message = messages[path.section]
        if let body = (collection.cellForItem(at: path) as? MessageCell)?.body, case .markdown = body.record?.kind {
            let character = body.character(at: CGPoint(x: 3, y: max(0, y - frame.minY)))
            let textY = body.rect(for: character)?.minY ?? 0
            return Anchor(messageID: message.id, item: path.item, character: character, offset: frame.minY + textY - collection.contentOffset.y)
        }
        return Anchor(messageID: message.id, item: path.item, character: nil, offset: frame.minY - collection.contentOffset.y)
    }
    func restore(_ anchor: Anchor) {
        guard let section = messages.firstIndex(where: { $0.id == anchor.messageID }) else { return }
        let message = messages[section]
        let path = IndexPath(item: min(anchor.item, message.blocks.count + 1), section: section)
        guard let frame = collection.layoutAttributesForItem(at: path)?.frame else { return }
        var textY: CGFloat = 0
        if let character = anchor.character, path.item > 0, path.item <= message.blocks.count {
            let body = store.view(for: message.blocks[path.item - 1], width: bodyWidth)
            textY = body.rect(for: character)?.minY ?? 0
        }
        collection.contentOffset.y = min(max(0, frame.minY + textY - anchor.offset), max(0, collection.contentSize.height - collection.bounds.height))
    }
    func scrollToLatest() {
        let wasUpdating = layoutTransaction
        layoutTransaction = true
        defer { layoutTransaction = wasUpdating }
        collection.layoutIfNeeded()
        collection.contentOffset.y = max(0, collection.contentSize.height - collection.bounds.height)
        followsLatest = true; latest.isHidden = true
    }
    func selectionScroll(by distance: CGFloat) {
        collection.contentOffset.y = min(max(0, collection.contentOffset.y + distance), max(0, collection.contentSize.height - collection.bounds.height))
        followsLatest = false
    }
    func quote(_ text: String) {
        input.text += (input.text.isEmpty ? "" : "\n\n") + text.split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n") + "\n\n"
        input.becomeFirstResponder()
    }
    func open(_ url: URL) {
        if url.scheme == "weibei-lab" { openWorkspace?(url.host == "notes" ? 1 : 0) }
        else if url.scheme == "https" || url.scheme == "http" { UIApplication.shared.open(url) }
    }
    override var keyCommands: [UIKeyCommand]? {
        let send = UIKeyCommand(title: "发送固定重放", action: #selector(sendPressed), input: "\r", modifierFlags: .command)
        let copy = UIKeyCommand(title: "复制会话选区", action: #selector(copySelection), input: "c", modifierFlags: .command)
        copy.wantsPriorityOverSystemBehavior = true
        var commands = [send, UIKeyCommand(title: "聚焦输入框", action: #selector(focusInput), input: "l", modifierFlags: .command)]
        if selection.hasSelection && selection.ownsFirstResponder { commands.append(copy) }
        return commands
    }
    @objc private func copySelection() { if selection.hasSelection { UIPasteboard.general.string = selection.text() } }
    @objc private func focusInput() { input.becomeFirstResponder() }
    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal); button.accessibilityLabel = title
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    func sampleScroll(completed: (() -> Void)? = nil) {
        guard preparation == nil, replay == nil else { return }
        let beforeParse = store.parseCount
        let beforeMeasure = store.measureCount
        let beforeRender = store.renderedCount
        let distance = max(0, collection.contentSize.height - collection.bounds.height)
        status.text = "正在采样连续滚动与回看…"
        let name = scenario
        metrics.record("\(name)_scroll_message_count", Double(messages.count))
        metrics.record("\(name)_scroll_source_utf16_count", Double(messages.reduce(0) { $0 + $1.markdown.utf16.count }))
        metrics.record("\(name)_scroll_distance_pt", Double(distance))
        metrics.scrollSample(name: name, step: { [weak self] elapsed in
            guard let self else { return }
            // Forward pass followed by a return pass over the same content.
            let fraction = elapsed < 6 ? elapsed / 6 : 1 - (elapsed - 6) / 6
            collection.contentOffset.y = distance * min(1, max(0, fraction))
        }, completed: { [weak self] in
            guard let self else { return }
            metrics.record("\(name)_scroll_new_parses", Double(store.parseCount - beforeParse))
            metrics.record("\(name)_scroll_new_measurements", Double(store.measureCount - beforeMeasure))
            metrics.record("\(name)_scroll_view_reconstructions", Double(store.renderedCount - beforeRender))
            do {
                _ = try metrics.write(controller: self)
                status.text = "采样已保存 · 显示回调间隔，不等同于 FPS"
            } catch { status.text = "记录写入失败：\(error.localizedDescription)" }
            completed?()
        })
    }

    func exportEvidence() {
        do {
            let url = try metrics.write(controller: self)
            present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), animated: true)
        } catch { status.text = "记录导出失败：\(error.localizedDescription)" }
    }

    func runChecks(completed: ((Bool) -> Void)? = nil) {
        guard preparation == nil, replay == nil else { return }
        metrics.checks.removeAll()
        Task { [weak self] in
            guard let self else { return }
            struct Failure: Error, LocalizedError {
                let message: String
                var errorDescription: String? { message }
            }
            func expect(_ condition: Bool, _ message: String) throws {
                guard condition else { throw Failure(message: message) }
            }
            do {
                try expect(UIDevice.current.userInterfaceIdiom == .mac, "运行界面不是 Mac idiom")
                loadScenario("history")
                await preparation?.value
                let parses = store.parseCount
                collection.contentOffset.y = min(4300, collection.contentSize.height / 3)
                collection.layoutIfNeeded()
                guard let anchor = captureAnchor() else { throw Failure(message: "无法取得历史阅读锚点") }
                prependHistory()
                await preparation?.value
                guard let after = captureAnchor() else { throw Failure(message: "前插后阅读锚点丢失") }
                try expect(after.messageID == anchor.messageID && after.item == anchor.item && after.character == anchor.character && abs(after.offset - anchor.offset) <= 1,
                           "历史前插改变了正在阅读的文字或屏幕位置")
                try expect(store.parseCount - parses == 80, "前插重复解析了已有历史")
                metrics.checks["prepend_preserves_reading_text"] = "passed"

                maximumBodyWidth = bodyWidth - 72
                view.setNeedsLayout(); view.layoutIfNeeded()
                guard let resized = captureAnchor() else { throw Failure(message: "改宽后锚点丢失") }
                try expect(resized.messageID == anchor.messageID && resized.item == anchor.item, "改宽离开了原来的正文段落")
                metrics.checks["resize_preserves_reading_paragraph"] = "passed"
                maximumBodyWidth = 760
                view.setNeedsLayout(); view.layoutIfNeeded()
                await withCheckedContinuation { continuation in sampleScroll { continuation.resume() } }

                let message = LabMessage(author: "检查样本", markdown: "第一段：中文与 emoji 👩🏽‍💻。\n\n第二段尚在增长")
                _ = await store.prepare(message, width: bodyWidth)
                let first = message.blocks[0]
                message.append("，尾字已经收到。")
                _ = await store.prepare(message, width: bodyWidth)
                try expect(message.blocks[0] === first, "流式更新替换了未改变的段落")
                let rendered = store.view(for: message.blocks.last!, width: bodyWidth).copyText()
                try expect(rendered.contains("尾字已经收到。"), "流式尾字没有显示")
                message.state = .stopped
                try expect(message.blocks[0] === first, "停止时重建了正文")
                metrics.checks["stream_keeps_unchanged_blocks_and_tail"] = "passed"

                startReplay()
                let deadline = ContinuousClock.now + .seconds(8)
                while (messages.last?.displayedRevision ?? -1) < 2, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(20))
                }
                try expect(messages.last?.state == .streaming, "固定重放没有进入真实输出路径")
                collection.contentOffset.y = min(4300, collection.contentSize.height / 3)
                collection.layoutIfNeeded()
                let reading = captureAnchor()
                await replay?.value
                try expect(messages.last?.markdown == LabFixture.replay && messages.last?.state == .complete, "重放完成时正文不完整")
                try expect(captureAnchor()?.messageID == reading?.messageID && captureAnchor()?.item == reading?.item, "读历史时流式输出把阅读者拉走")
                startReplay()
                let stopDeadline = ContinuousClock.now + .seconds(8)
                while messages.last?.state != .streaming || (messages.last?.displayedRevision ?? -1) < 2 {
                    if ContinuousClock.now >= stopDeadline { throw Failure(message: "停止检查等不到实际输出") }
                    try await Task.sleep(for: .milliseconds(20))
                }
                let stopping = messages.last!
                let received = stopping.markdown
                sendPressed()
                await replay?.value
                try expect(stopping.state == .stopped && stopping.markdown == received && stopping.displayedRevision == stopping.revision, "停止丢失了已经收到的内容")
                metrics.checks["replay_stop_complete_and_history_reading"] = "passed"

                loadScenario("rich")
                await preparation?.value
                let blocks = messages[0].blocks
                let formulas = blocks.flatMap { $0.content.rendered.values }
                try expect(!formulas.isEmpty && formulas.allSatisfy { $0.image != nil }, "数学资源没有完整生成真实公式")
                try expect(LabImages.shared.images["lab-image://landscape"] != nil, "图片没有解码成功")
                guard blocks.count > 3 else { throw Failure(message: "富内容样本不完整") }
                guard let diagram = blocks.first(where: { if case .diagram = $0.kind { return true }; return false }) else {
                    throw Failure(message: "没有关系图内容")
                }
                let diagramView = store.view(for: diagram, width: bodyWidth)
                let diagramDeadline = ContinuousClock.now + .seconds(8)
                while !diagramView.diagramRendered {
                    if ContinuousClock.now >= diagramDeadline { throw Failure(message: "离线关系图没有生成真实 SVG") }
                    try await Task.sleep(for: .milliseconds(20))
                }

                guard let imageIndex = blocks.firstIndex(where: { $0.imageSources.contains("lab-image://landscape") }) else {
                    throw Failure(message: "没有实际图片正文")
                }
                let imageBlock = blocks[imageIndex]
                LabImages.shared.images.removeValue(forKey: "lab-image://landscape")
                store.reset(); imageBlock.width = 0
                _ = store.measure(imageBlock, width: bodyWidth)
                let pendingHeight = imageBlock.height
                collection.reloadData(); collection.layoutIfNeeded()
                collection.scrollToItem(at: IndexPath(item: imageIndex + 2, section: 0), at: .top, animated: false)
                collection.layoutIfNeeded()
                let beforeImage = captureAnchor()
                // Drop the prepared view pool before the real asynchronous
                // decoder returns; the content record must still be updated.
                store.reset()
                collection.reloadData(); collection.layoutIfNeeded()
                let imageDeadline = ContinuousClock.now + .seconds(8)
                while imageBlock.height == pendingHeight || changeScheduled {
                    if ContinuousClock.now >= imageDeadline { throw Failure(message: "图片到达后缓存行高没有更新") }
                    try await Task.sleep(for: .milliseconds(20))
                }
                let afterImage = captureAnchor()
                try expect(beforeImage != nil && afterImage?.messageID == beforeImage?.messageID && afterImage?.item == beforeImage?.item && abs((afterImage?.offset ?? 0) - (beforeImage?.offset ?? 0)) <= 1,
                           "图片到达使正在阅读的正文跳位")
                metrics.checks["image_arrival_preserves_reading_text"] = "passed"

                selection.select(from: .init(blockID: blocks[1].id, character: 3), to: .init(blockID: blocks[2].id, character: 18))
                let selected = selection.text()
                try expect(selected.contains("\n\n") && !selected.isEmpty, "跨段复制没有包含两个段落")
                for index in 0..<44 {
                    let probe = LabMessage(author: "复用检查", markdown: "复用样本 \(index)")
                    _ = await store.prepare(probe, width: bodyWidth)
                }
                try expect(selection.text() == selected, "视图复用后跨段选区丢失")
                metrics.checks["cross_paragraph_copy_survives_reuse"] = "passed"
                guard let card = blocks.first(where: { if case .card = $0.kind { return true }; return false }) else {
                    throw Failure(message: "未找到摘记卡")
                }
                let cardView = store.view(for: card, width: bodyWidth)
                let draftView = cardView.subviews.compactMap { $0 as? UITextView }.first!
                draftView.text = "用户的摘记草稿"
                cardView.textViewDidChange(draftView)
                let foldButton = cardView.subviews.first { $0.accessibilityIdentifier == "toggle-card" } as! UIButton
                foldButton.sendActions(for: .touchUpInside)
                while changeScheduled { await Task.yield() }
                store.reset()
                collection.reloadData(); collection.layoutIfNeeded()
                let restoredCard = store.view(for: card, width: bodyWidth)
                let restoredDraft = restoredCard.subviews.compactMap { $0 as? UITextView }.first!
                try expect(restoredDraft.text == draftView.text && restoredDraft.isHidden && card.collapsed, "摘记草稿或折叠后的显示状态丢失")
                metrics.checks["card_draft_and_fold_persist"] = "passed"

                guard let code = blocks.first(where: { if case let .codeBlock(language, _) = $0.node { return language == "swift" }; return false }) else {
                    throw Failure(message: "没有代码附件")
                }
                let codeView = store.view(for: code, width: bodyWidth)
                guard let codeLabel = codeView.attachmentLabels.first, let scroller = codeView.scrollViews(in: codeView.markdown).first else {
                    throw Failure(message: "代码没有可选择文字和横向滚动控件")
                }
                let highlighted = codeLabel.attributedText.copy() as! NSAttributedString
                codeLabel.selectionRange = NSRange(location: 3, length: 16)
                scroller.contentOffset.x = min(80, max(0, scroller.contentSize.width - scroller.bounds.width))
                try expect(scroller.contentOffset.x > 0, "长代码没有可横向阅读的完整宽度（正文 \(codeLabel.intrinsicContentSize.width)，内容 \(scroller.contentSize.width)，视口 \(scroller.bounds.width)）")
                codeView.saveInteractionState()
                let offset = scroller.contentOffset.x
                store.reset(); CodeHighlighter.current.renderCache.removeAll()
                collection.reloadData(); collection.layoutIfNeeded()
                let restoredCode = store.view(for: code, width: bodyWidth)
                restoredCode.restoreInteractionState()
                try expect(restoredCode.attachmentLabels.first?.selectionRange == NSRange(location: 3, length: 16) && restoredCode.scrollViews(in: restoredCode.markdown).first?.contentOffset.x == offset,
                           "代码附件复用丢失选区或横向位置")
                try expect(restoredCode.attachmentLabels.first?.attributedText.isEqual(to: highlighted) == true && !code.content.highlightMaps.isEmpty,
                           "视图和全局缓存淘汰后没有保留代码高亮")
                metrics.checks["code_highlight_selection_and_scroll_persist"] = "passed"
                metrics.checks["math_image_and_diagram_resources"] = "passed"
                selection.clear()

                loadScenario("long")
                await preparation?.value
                try expect(messages.count == 1 && collection.numberOfSections == 1 && messages[0].markdown == LabFixture.longAnswer,
                           "单条长回答被拆成假消息或截断")
                scrollToLatest()
                let answer = messages[0]
                let tailPath = IndexPath(item: answer.blocks.count, section: 0)
                collection.scrollToItem(at: tailPath, at: .bottom, animated: false)
                collection.layoutIfNeeded()
                let tail = (collection.cellForItem(at: tailPath) as? MessageCell)?.body?.copyText()
                // MarkdownView appends a paragraph terminator; compare every
                // content character without treating that layout newline as text.
                try expect(tail?.trimmingCharacters(in: .newlines) == LabFixture.longAnswer.components(separatedBy: "\n\n").last,
                           "长回答最后一段未真实显示")
                guard let longCode = answer.blocks.first(where: { if case let .codeBlock(_, text) = $0.node { return text.trimmingCharacters(in: .whitespacesAndNewlines) == LabFixture.longCode }; return false }) else {
                    throw Failure(message: "长代码缺失")
                }
                try expect(store.view(for: longCode, width: bodyWidth).copyText().contains(LabFixture.longCode), "长代码正文被截断")
                await withCheckedContinuation { continuation in sampleScroll { continuation.resume() } }
                metrics.checks["single_long_answer_complete_and_revisitable"] = "passed"
                selection.clear()
                status.text = "10 项必要行为检查通过 · 桌面手感仍需单独体验"
            } catch {
                metrics.checks["failure"] = error.localizedDescription
                status.text = "行为检查未通过：\(error.localizedDescription)"
            }
            do {
                _ = try metrics.write(controller: self)
                if CommandLine.arguments.contains("--self-check"), let window = view.window {
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    try image.pngData()?.write(to: LabMetrics.directory.appendingPathComponent("window.png"))
                }
            }
            catch { status.text = "检查记录写入失败：\(error.localizedDescription)" }
            completed?(metrics.checks["failure"] == nil && metrics.checks.count == 10)
        }
    }
}
