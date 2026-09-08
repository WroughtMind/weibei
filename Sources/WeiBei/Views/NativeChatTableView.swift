import AppKit
import WeiBeiCore

/// Background work shared by an attachment's first presentation and subsequent updates.
/// The attachment keeps only one worker; a newer source replaces its pending input.
enum NativeChatAttachmentPreparation: Sendable {
    case code([NativeChatCodeHighlighter.Token], NSSize, String?)
    case table([[NativeChatMarkdownDocument]], [CGFloat])
    case none

    static func make(_ descriptor: NativeChatAttachmentDescriptor, fontSize: CGFloat,
        language: WeiBeiInterfaceLanguage, codeTokens: [NativeChatCodeHighlighter.Token]?) async -> Self {
        switch descriptor {
        case let .code(source, language):
            let font = NSFont.monospacedSystemFont(ofSize: fontSize - 1, weight: .regular)
            let size = NSAttributedString(string: source, attributes: [.font: font]).size()
            let natural = NSSize(width: ceil(size.width), height: ceil(size.height))
            do {
                let tokens: [NativeChatCodeHighlighter.Token]
                if let codeTokens { tokens = codeTokens }
                else { tokens = try await NativeChatCodeHighlighter.shared.tokens(source, language: language) }
                return .code(tokens, natural, nil)
            } catch { return .code([], natural, error.localizedDescription) }
        case let .table(headers, rows, _):
            let contents = [headers] + rows
            let count = contents.map(\.count).max() ?? 0
            var widths = Array(repeating: CGFloat(96), count: count)
            var memo: [String: (NativeChatMarkdownDocument, CGFloat)] = [:]
            let documents = contents.map { row in
                (0..<count).map { column in
                    let source = column < row.count ? row[column] : ""
                    let prepared: (NativeChatMarkdownDocument, CGFloat)
                    if let value = memo[source] { prepared = value }
                    else {
                        let document = NativeChatMarkdownParser.parse(source, interfaceLanguage: language)
                        let width = NSAttributedString(string: document.text, attributes: [.font: NSFont.systemFont(ofSize: fontSize)]).size().width
                        prepared = (document, width)
                        memo[source] = prepared
                    }
                    widths[column] = min(320, max(widths[column], ceil(prepared.1) + 24))
                    return prepared.0
                }
            }
            return .table(documents, widths)
        default: return .none
        }
    }
}

/// Current attachment data. Views may leave; documents, measured rows and selections stay.
@MainActor
final class NativeChatTableContent {
    @MainActor final class Cell {
        let renderer = NativeChatMarkdownView.Coordinator()
        var height: CGFloat = 0
    }
    let documents: [[NativeChatMarkdownDocument]]
    let columnWidths: [CGFloat]
    let fontSize: CGFloat
    private(set) var rowHeights: [CGFloat]
    private(set) var rowOffsets: [CGFloat] = []
    private(set) var cells: [Int: Cell] = [:]
    var width: CGFloat { columnWidths.reduce(0, +) }
    var height: CGFloat { rowOffsets.last ?? 0 }

    init(documents: [[NativeChatMarkdownDocument]], widths: [CGFloat], fontSize: CGFloat, previous: NativeChatTableContent?) {
        self.documents = documents
        columnWidths = widths
        self.fontSize = fontSize
        rowHeights = documents.map { row in
            max(fontSize * 1.5 + 16, row.enumerated().map { index, document in
                ceil(CGFloat(document.utf16Count) * fontSize * 0.8 / max(1, widths[index] - 24)) * fontSize * 1.5 + 16
            }.max() ?? 0)
        }
        if let previous, previous.fontSize == fontSize, previous.columnWidths == widths {
            for (row, document) in documents.enumerated() where row < previous.documents.count && document == previous.documents[row] {
                rowHeights[row] = previous.rowHeights[row]
                for column in widths.indices {
                    let key = row * widths.count + column
                    cells[key] = previous.cells[key]
                }
            }
        }
        rebuildOffsets()
    }

    func cell(row: Int, column: Int, attachment: NativeChatTextAttachment) -> Cell {
        let key = row * columnWidths.count + column
        if let cell = cells[key] { return cell }
        let cell = Cell()
        let renderer = cell.renderer
        renderer.managesReadingPosition = false
        renderer.fontSize = fontSize
        renderer.isDark = attachment.isDark
        renderer.interfaceLanguage = attachment.interfaceLanguage
        renderer.onOpenURL = attachment.onOpenURL
        renderer.imageLoader = attachment.imageLoader
        let document = documents[row][column]
        renderer.apply(document, edit: .between(.init(), document))
        let storage = renderer.preparedStorage
        let paragraph = NSMutableParagraphStyle()
        if case let .table(_, _, alignments) = attachment.descriptor, column < alignments.count {
            paragraph.alignment = alignments[column] == "center" ? .center : alignments[column] == "right" ? .right : .left
        }
        storage.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: storage.length))
        if row == 0 { storage.addAttribute(.backgroundColor, value: WeiBeiNativePalette.codePaper(), range: NSRange(location: 0, length: storage.length)) }
        cells[key] = cell
        return cell
    }

    func updateHeights(_ updates: [Int: CGFloat]) -> Bool {
        var changed = false
        for (row, height) in updates where rowHeights.indices.contains(row) && abs(rowHeights[row] - height) > 0.5 {
            rowHeights[row] = ceil(height)
            changed = true
        }
        if changed { rebuildOffsets() }
        return changed
    }
    func restyle(isDark: Bool, language: WeiBeiInterfaceLanguage) {
        for cell in cells.values {
            let renderer = cell.renderer
            let storage = renderer.preparedStorage
            let paragraph = storage.length > 0 ? storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) : nil
            let header = storage.length > 0 && storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil
            renderer.isDark = isDark
            renderer.interfaceLanguage = language
            renderer.restyle()
            let range = NSRange(location: 0, length: storage.length)
            if let paragraph { storage.addAttribute(.paragraphStyle, value: paragraph, range: range) }
            if header { storage.addAttribute(.backgroundColor, value: WeiBeiNativePalette.codePaper(), range: range) }
        }
    }
    private func rebuildOffsets() {
        rowOffsets = [0]
        for height in rowHeights { rowOffsets.append(rowOffsets.last! + height) }
    }
    func row(at y: CGFloat) -> Int {
        var lower = 0, upper = rowHeights.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if rowOffsets[middle + 1] <= y { lower = middle + 1 } else { upper = middle }
        }
        return min(lower, max(0, rowHeights.count - 1))
    }
}

/// Local table virtualization, without an inner vertical scroll position.
@MainActor
final class NativeChatTableView: NSView {
    let attachment: NativeChatTextAttachment
    private var content: NativeChatTableContent?
    private var visibleCells: [Int: NativeChatTextView] = [:]
    private weak var outerClip: NSClipView?
    private weak var horizontalClip: NSClipView?
    private var observers: [NSObjectProtocol] = []
    private var pendingHeights: [Int: CGFloat] = [:]
    private var reportScheduled = false
    override var isFlipped: Bool { true }
    override var visibleRect: NSRect {
        guard let clip = mainConversationClipView else { return super.visibleRect }
        return super.visibleRect.intersection(convert(clip.bounds, from: clip))
    }
    var visibleCellCount: Int { visibleCells.count }

    init(attachment: NativeChatTextAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func refresh() {
        if content !== attachment.tableContent {
            detachCells()
            content = attachment.tableContent
        }
        needsLayout = true
    }
    private func detachCells() {
        for (key, view) in visibleCells {
            content?.cells[key]?.renderer.view = nil
            view.onLayout = nil
            view.removeFromSuperview()
        }
        visibleCells.removeAll()
    }
    override func layout() {
        super.layout()
        let clip = mainConversationClipView
        let inner = enclosingScrollView?.contentView
        if clip !== outerClip || inner !== horizontalClip {
            observers.forEach(NotificationCenter.default.removeObserver)
            outerClip = clip
            horizontalClip = inner
            observers = [clip, inner === clip ? nil : inner].compactMap { $0 }.map { clip in
                clip.postsBoundsChangedNotifications = true
                return NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.needsLayout = true } }
            }
        }
        guard let content, !content.rowHeights.isEmpty, !content.columnWidths.isEmpty else { detachCells(); return }
        let visible = visibleRect
        guard !visible.isEmpty else { detachCells(); return }
        let first = content.row(at: max(0, visible.minY))
        let last = content.row(at: visible.maxY)
        var frames: [Int: NSRect] = [:]
        for row in first...last {
            var x: CGFloat = 0
            for column in content.columnWidths.indices {
                let width = content.columnWidths[column]
                defer { x += width }
                guard x < visible.maxX && x + width > visible.minX else { continue }
                frames[row * content.columnWidths.count + column] = NSRect(x: x + 12,
                    y: content.rowOffsets[row] + 8, width: max(1, width - 24), height: max(1, content.rowHeights[row] - 16))
            }
        }
        // Reuse cells leaving this viewport before creating cells entering it.
        // Only this pass's spare views survive; offscreen tables keep data, not heavy views.
        var reusable: [NativeChatTextView] = []
        for key in Array(visibleCells.keys) where frames[key] == nil {
            content.cells[key]?.renderer.view = nil
            if let text = visibleCells.removeValue(forKey: key) {
                text.onLayout = nil
                text.delegate = nil
                text.removeFromSuperview()
                reusable.append(text)
            }
        }
        for (key, frame) in frames {
            let row = key / content.columnWidths.count
            let column = key % content.columnWidths.count
            let text: NativeChatTextView
            if let existing = visibleCells[key] { text = existing }
            else {
                let cell = content.cell(row: row, column: column, attachment: attachment)
                if let recycled = reusable.popLast() { text = recycled }
                else {
                    text = NativeChatTextView(usingTextLayoutManager: true)
                    text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
                    text.clipsToBounds = true
                    text.isVerticallyResizable = false
                    text.textContainerInset = .zero
                    text.textContainer?.lineFragmentPadding = 0
                    text.textContainer?.widthTracksTextView = true
                }
                cell.renderer.view = text
                text.delegate = cell.renderer
                text.onLayout = { [weak self, weak cell, weak content] in
                    guard let self, let cell, let content, self.content === content else { return }
                    cell.renderer.layoutDidChange()
                    self.report(row: row, content: content)
                }
                visibleCells[key] = text
                addSubview(text)
            }
            text.conversationClipView = clip
            text.frame = frame
        }
    }

    private func report(row: Int, content: NativeChatTableContent) {
        var height = content.fontSize * 1.5 + 16
        for column in content.columnWidths.indices {
            let key = row * content.columnWidths.count + column
            guard let cell = content.cells[key] else { height = max(height, content.rowHeights[row]); continue }
            if let used = cell.renderer.view?.textLayoutManager?.usageBoundsForTextContainer.height, used > 0 { cell.height = used }
            height = max(height, cell.height + 16)
        }
        guard abs(height - (pendingHeights[row] ?? content.rowHeights[row])) > 0.5 else { return }
        pendingHeights[row] = height
        guard !reportScheduled else { return }
        reportScheduled = true
        DispatchQueue.main.async { [weak self, weak content] in
            guard let self else { return }
            self.reportScheduled = false
            let updates = self.pendingHeights
            self.pendingHeights.removeAll()
            guard let content, self.content === content else { return }
            self.attachment.onWillResize()
            guard content.updateHeights(updates) else { return }
            self.needsLayout = true
            self.attachment.changed()
        }
    }
}
