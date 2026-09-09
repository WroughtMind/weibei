import UIKit
import MarkdownView
import MarkdownParser
import Litext

extension MarkdownTheme {
    static func weiBei(fontSize: CGFloat, appearance: WeiBeiAppearanceMode) -> Self {
        var theme = Self()
        theme.align(to: fontSize)
        theme.colors.body = WeiBeiNativePalette.ink(for: appearance)
        theme.colors.code = theme.colors.body
        theme.colors.codeBackground = WeiBeiNativePalette.codePaper(for: appearance)
        theme.colors.highlight = WeiBeiNativePalette.cinnabar(for: appearance)
        theme.colors.emphasis = theme.colors.body
        theme.colors.selectionBackground = WeiBeiNativePalette.selectionFill(for: appearance)
        theme.spacings.paragraph = fontSize * 0.75
        theme.spacings.headingBefore = fontSize
        theme.table.headerBackgroundColor = WeiBeiNativePalette.paperInset(for: appearance)
        theme.table.cellBackgroundColor = .clear
        theme.table.stripeCellBackgroundColor = WeiBeiNativePalette.paperRaised(for: appearance).withAlphaComponent(0.35)
        theme.table.borderColor = WeiBeiNativePalette.hairline(for: appearance)
        theme.table.cornerRadius = 6
        return theme
    }
}

@MainActor
final class PreparedBlock {
    let id: String
    let messageID: String
    let node: MarkdownBlockNode
    let content: MarkdownContent
    let kind: Kind
    var width: CGFloat = 0
    var height: CGFloat = 32
    var draft = ""
    var collapsed = false
    var horizontalOffsets: [CGFloat] = []
    var attachmentSelections: [NSRange?] = []
    weak var renderedView: BlockView?
    var preparedText: NSAttributedString?
    var preparedLayout: TextLabel.Layout?
    var imageSources: Set<String> = []
    enum Kind { case markdown, card(String), diagram(String), workspaceAttachment(String) }

    init(id: String, messageID: String, node: MarkdownBlockNode, content: MarkdownContent, fixtureCard: Bool) {
        self.id = id; self.messageID = messageID; self.node = node; self.content = content
        if case let .paragraph(inlines) = node, inlines.count == 1,
           case let .image(source, _) = inlines[0], source.hasPrefix("weibei-visualization:") {
            kind = .workspaceAttachment(String(source.dropFirst("weibei-visualization:".count)).removingPercentEncoding ?? source)
            return
        }
        switch node {
        case let .codeBlock(language, source) where language == "genui" && fixtureCard: kind = .card(source)
        case let .codeBlock(language, source) where language == "mermaid": kind = .diagram(source)
        default: kind = .markdown
        }
    }
}

@MainActor
final class ContentStore {
    var theme: MarkdownTheme = .weiBei(fontSize: 16, appearance: .paper)
    private var views: [String: BlockView] = [:]
    private var recent: [String] = []
    private var generation = 0
    var changed: ((PreparedBlock) -> Void)?
    var interaction: ((BlockView) -> Void)?
    var openLink: ((URL, String) -> Void)?
    var workspaceAttachment: ((PreparedBlock, String, @escaping (CGFloat) -> Void) -> UIView)?
    var images = LabImages.shared
    private(set) var themeRevision = 0
    func setTheme(_ value: MarkdownTheme) -> Bool {
        guard theme != value else { return false }
        theme = value; themeRevision += 1; generation += 1
        return true
    }
    var saveNote: ((String) -> Void)?
    private(set) var parseCount = 0
    private(set) var renderedCount = 0
    private(set) var measureCount = 0
    private(set) var preparationMS: [String: Double] = [:]
    var retainedViewCount: Int { views.count }
    var peakViewCount = 0

    func prepare(_ message: LabMessage, width: CGFloat) async -> Bool {
        let started = CACurrentMediaTime()
        let generation = self.generation
        let revision = message.revision
        let text = message.markdown
        // ponytail: full source parsing preserves late reference definitions;
        // unchanged parsed blocks keep their content and layout. Use parser-owned
        // incremental invalidation only if this measured cost dominates.
        let parsed: MarkdownParser.ParseResult
        if message.parsedRevision == revision, let cached = message.parsed { parsed = cached }
        else {
            parsed = await Task.detached(priority: .userInitiated) { MarkdownParser().parse(text) }.value
            guard generation == self.generation, revision == message.revision else { return false }
            message.parsed = parsed; message.parsedRevision = revision
            parseCount += 1
        }
        let parsedAt = CACurrentMediaTime()
        preparationMS["parse_elapsed", default: 0] += (parsedAt - started) * 1000
        let preservesRendering = message.preparedTheme == themeRevision
        let rendered = parsed.renderedContent(theme: theme)
        message.blocks = parsed.document.enumerated().map { index, node in
            if preservesRendering, index < message.blocks.count, message.blocks[index].node == node {
                return message.blocks[index]
            }
            var imageSources: Set<String> = []
            let isCallout: Bool
            if case .blockquote = node { isCallout = true } else { isCallout = false }
            let transformed = [node].rewrite { (inline: MarkdownInlineNode) -> [MarkdownInlineNode] in
                if case let .image(source, _) = inline {
                    imageSources.insert(source)
                    return [.text("\u{E000}IMAGE:" + source + "\u{E001}")]
                }
                if isCallout, case let .text(value) = inline, value.hasPrefix("[!NOTE]") {
                    return [.strong(children: [.text("提示")]), .text(String(value.dropFirst(7)))]
                }
                return [inline]
            }
            var highlights: [Int: CodeHighlighter.HighlightMap] = [:]
            @MainActor func prepareCode(_ node: MarkdownBlockNode) {
                if case let .codeBlock(language, source) = node, language != "genui", language != "mermaid" {
                    let key = CodeHighlighter.current.key(for: source, language: language)
                    highlights[key] = CodeHighlighter.current.highlight(key: key, content: source, language: language, theme: theme)
                }
                node.children.forEach(prepareCode)
            }
            // Retain the public upstream highlighter's result with the block;
            // eviction of its global cache must not re-highlight old history.
            prepareCode(node)
            let content = MarkdownContent(blocks: transformed, rendered: rendered, highlightMaps: highlights)
            let block = PreparedBlock(id: "\(message.id)/\(index)", messageID: message.id, node: node, content: content, fixtureCard: message.original == nil)
            block.imageSources = imageSources
            if index < message.blocks.count {
                views[message.blocks[index].id]?.saveInteractionState()
                block.draft = message.blocks[index].draft
                block.collapsed = message.blocks[index].collapsed
                block.horizontalOffsets = message.blocks[index].horizontalOffsets
                block.attachmentSelections = message.blocks[index].attachmentSelections
            }
            return block
        }
        let renderedAt = CACurrentMediaTime()
        preparationMS["render_and_highlight", default: 0] += (renderedAt - parsedAt) * 1000
        for block in message.blocks {
            if block.width != width { _ = measure(block, width: width) }
        }
        preparationMS["measure", default: 0] += (CACurrentMediaTime() - renderedAt) * 1000
        message.preparedTheme = themeRevision
        message.displayedRevision = revision
        return true
    }

    func view(for block: PreparedBlock, width: CGFloat) -> BlockView {
        let body = views[block.id] ?? BlockView()
        views[block.id] = body
        block.renderedView = body
        let changed = body.record !== block
        body.markdown.images = images
        body.makeWorkspaceAttachment = workspaceAttachment
        if changed {
            body.configure(block, theme: theme)
            renderedCount += 1
        }
        body.onChange = { [weak self, weak block] in
            guard let self, let block else { return }
            self.changed?(block)
        }
        body.onLink = { [weak self] in self?.openLink?($0, block.messageID) }
        body.onSaveNote = { [weak self] in self?.saveNote?($0) }
        if block.width != width {
            block.height = body.measure(width: width)
            block.width = width
            measureCount += 1
        } else if changed {
            body.installSize(width: width, height: block.height)
        }
        recent.removeAll { $0 == block.id }; recent.append(block.id)
        // Keep detached views bounded; parsed content and sizes are independent.
        while recent.count > 36, let index = recent.firstIndex(where: { $0 != block.id && views[$0]?.superview == nil }) {
            let id = recent.remove(at: index)
            views[id]?.saveInteractionState()
            views[id] = nil
        }
        peakViewCount = max(peakViewCount, views.count)
        if case .markdown = block.kind { interaction?(body) }
        return body
    }

    @discardableResult
    func measure(_ block: PreparedBlock, width: CGFloat) -> CGFloat {
        if block.width == width { return block.height }
        if let layout = block.preparedLayout {
            block.height = max(24, ceil(layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
            block.width = width
            layout.containerSize = CGSize(width: width, height: block.height)
            measureCount += 1
            return block.height
        }
        _ = view(for: block, width: width)
        return block.height
    }

    func reset() {
        generation += 1
        for view in views.values {
            view.saveInteractionState()
            if view.record?.renderedView === view { view.record?.renderedView = nil }
        }
        views.removeAll(); recent.removeAll()
    }
}
