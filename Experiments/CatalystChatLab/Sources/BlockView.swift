import UIKit
import Litext
import MarkdownView
import MarkdownParser

final class BlockView: UIView, UITextViewDelegate {
    let markdown = ImageMarkdownView()
    private let preparedLabel = TextLabelView()
    var label: TextLabelView { preparedLabel.isHidden ? markdown.textLabelView : preparedLabel }
    private let cardTitle = UILabel()
    private let draft = UITextView()
    private let fold = UIButton(type: .system)
    private let save = UIButton(type: .system)
    private var diagram: DiagramView?
    private(set) var record: PreparedBlock?
    var onChange: (() -> Void)?
    var onLink: ((URL) -> Void)?
    var onSaveNote: ((String) -> Void)?
    private var geometry: TextLabel.Layout?
    private let selectionOverlay = CAShapeLayer()
    private var lastWidth: CGFloat = 0
    private var lastHeight: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        for child in [markdown, preparedLabel, cardTitle, draft, fold, save] { addSubview(child) }
        preparedLabel.isSelectable = true
        markdown.throttleInterval = nil
        markdown.linkHandler = { [weak self] payload, _, _ in
            switch payload {
            case let .url(url): self?.onLink?(url)
            case let .string(value): if let url = URL(string: value) { self?.onLink?(url) }
            }
        }
        cardTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        cardTitle.numberOfLines = 2
        draft.font = .systemFont(ofSize: 16)
        draft.backgroundColor = .secondarySystemBackground
        draft.delegate = self
        draft.accessibilityLabel = "摘记卡草稿"
        fold.setTitle("收起", for: .normal)
        fold.accessibilityIdentifier = "toggle-card"
        fold.addTarget(self, action: #selector(toggleCard), for: .touchUpInside)
        save.setTitle("收录到实验笔记", for: .normal)
        save.addTarget(self, action: #selector(saveCard), for: .touchUpInside)
        selectionOverlay.fillColor = UIColor.systemOrange.withAlphaComponent(0.23).cgColor
        selectionOverlay.zPosition = 20
        selectionOverlay.actions = ["path": NSNull()]
        layer.addSublayer(selectionOverlay)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ block: PreparedBlock, theme: MarkdownTheme) {
        saveInteractionState()
        onChange = nil
        record = block
        geometry = nil
        lastWidth = 0
        selectionOverlay.path = nil
        for child in subviews { child.isHidden = true }
        switch block.kind {
        case .markdown:
            if block.preparedText == nil {
                markdown.setContentImmediately(block.content, theme: theme)
                let text = markdown.textLabelView.attributedText
                var portable = true
                // These upstream blocks own context views or a view-bound rule.
                func ownsContext(_ node: MarkdownBlockNode) -> Bool {
                    switch node {
                    case .blockquote, .thematicBreak, .codeBlock, .table: return true
                    default: return node.children.contains(where: ownsContext)
                    }
                }
                portable = !ownsContext(block.node)
                text.enumerateAttribute(.litextAttachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                    if let attachment = value as? TextLabel.Attachment, attachment.view != nil { portable = false }
                }
                if portable {
                    block.preparedText = text
                    block.preparedLayout = TextLabel.Layout(attributedString: text)
                }
            }
            if let text = block.preparedText {
                preparedLabel.attributedText = text
                preparedLabel.selectionBackgroundColor = theme.colors.selectionBackground
                preparedLabel.isHidden = false
            } else { markdown.isHidden = false }
        case let .card(source):
            for child in [cardTitle, draft, fold, save] { child.isHidden = false }
            draft.isHidden = block.collapsed; save.isHidden = block.collapsed
            fold.setTitle(block.collapsed ? "展开" : "收起", for: .normal)
            struct Card: Decodable { let title: String; let prompt: String }
            do {
                let card = try JSONDecoder().decode(Card.self, from: Data(source.utf8))
                cardTitle.text = card.title + " · " + card.prompt
                draft.text = block.draft
                save.isEnabled = true
            } catch {
                cardTitle.text = "摘记卡内容无效：\(error.localizedDescription)"
                draft.text = source
                save.isEnabled = false
            }
        case let .diagram(source):
            if diagram == nil {
                let view = DiagramView()
                view.heightChanged = { [weak self] in self?.onChange?() }
                diagram = view
                addSubview(view)
            }
            diagram?.isHidden = false
            diagram?.display(source)
        }
        accessibilityIdentifier = block.id
    }

    func measure(width: CGFloat) -> CGFloat {
        guard let record else { return 1 }
        if lastWidth != width { geometry = nil }
        lastWidth = width
        switch record.kind {
        case .markdown:
            if let layout = record.preparedLayout {
                lastHeight = max(24, ceil(layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
                layout.containerSize = CGSize(width: width, height: lastHeight)
                installSize(width: width, height: lastHeight)
                return lastHeight
            }
            markdown.contentWidth = width
            lastHeight = max(24, ceil(markdown.boundingSize(for: width).height))
            markdown.frame = CGRect(x: 0, y: 0, width: width, height: lastHeight)
            markdown.layoutIfNeeded()
        case .card:
            lastHeight = record.collapsed ? 48 : 204
            draft.isHidden = record.collapsed; save.isHidden = record.collapsed
            fold.setTitle(record.collapsed ? "展开" : "收起", for: .normal)
        case .diagram:
            lastHeight = max(180, diagram?.measuredHeight ?? 200)
        }
        frame.size = CGSize(width: width, height: lastHeight)
        setNeedsLayout()
        return lastHeight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let record else { return }
        if bounds.width != lastWidth { geometry = nil; lastWidth = bounds.width }
        switch record.kind {
        case .markdown:
            if preparedLabel.isHidden { markdown.frame = bounds }
            else { preparedLabel.frame = bounds; preparedLabel.preferredMaxLayoutWidth = bounds.width }
        case .card:
            cardTitle.frame = CGRect(x: 12, y: 8, width: bounds.width - 84, height: 34)
            fold.frame = CGRect(x: bounds.width - 64, y: 8, width: 52, height: 32)
            draft.frame = CGRect(x: 12, y: 48, width: bounds.width - 24, height: 104)
            save.frame = CGRect(x: 12, y: 162, width: 160, height: 32)
        case .diagram: diagram?.frame = bounds
        }
    }

    func installSize(width: CGFloat, height: CGFloat) {
        lastWidth = width; lastHeight = height
        frame.size = CGSize(width: width, height: height)
        if preparedLabel.isHidden {
            markdown.contentWidth = width
            markdown.frame = bounds
            markdown.layoutIfNeeded()
        } else {
            preparedLabel.frame = bounds
            preparedLabel.preferredMaxLayoutWidth = width
            preparedLabel.layoutIfNeeded()
        }
        setNeedsLayout()
    }

    @objc private func toggleCard() {
        guard let record else { return }
        record.collapsed.toggle()
        onChange?()
    }
    @objc private func saveCard() { if let text = record?.draft, !text.isEmpty { onSaveNote?(text) } }
    func textViewDidChange(_ textView: UITextView) { record?.draft = textView.text }

    func saveInteractionState() {
        guard let record, case .markdown = record.kind, preparedLabel.isHidden else { return }
        record.horizontalOffsets = scrollViews(in: markdown).map { $0.contentOffset.x }
        record.attachmentSelections = attachmentLabels.map(\.selectionRange)
    }
    func restoreInteractionState() {
        guard let record else { return }
        markdown.layoutIfNeeded()
        for (view, offset) in zip(scrollViews(in: markdown), record.horizontalOffsets) {
            view.contentOffset.x = offset
        }
        for (label, range) in zip(attachmentLabels, record.attachmentSelections) { label.selectionRange = range }
    }
    var attachmentLabels: [TextLabelView] {
        func labels(in view: UIView) -> [TextLabelView] {
            view.subviews.flatMap { child in
                let own = (child as? TextLabelView).map { $0 === markdown.textLabelView ? [] : [$0] } ?? []
                return own + labels(in: child)
            }
        }
        return labels(in: markdown)
    }
    func scrollViews(in view: UIView) -> [UIScrollView] {
        view.subviews.flatMap { child in
            if let scroll = child as? UIScrollView { return [scroll] }
            return scrollViews(in: child)
        }
    }

    // Geometry is needed only for a user selection or a layout-changing reading
    // anchor. Ordinary scrolling reads the collection's prepared heights.
    private func textGeometry() -> TextLabel.Layout {
        if let layout = record?.preparedLayout {
            layout.containerSize = bounds.size
            return layout
        }
        if let geometry { return geometry }
        let layout = TextLabel.Layout(attributedString: label.attributedText)
        layout.containerSize = label.bounds.size
        geometry = layout
        return layout
    }
    func character(at point: CGPoint) -> Int {
        textGeometry().nearestTextIndex(at: CGPoint(x: point.x, y: bounds.height - point.y)) ?? 0
    }
    func rect(for character: Int) -> CGRect? {
        let length = label.attributedText.length
        guard length > 0, let rect = textGeometry().rects(for: NSRange(location: min(character, length - 1), length: 1)).first else { return nil }
        return CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }
    func displaySelection(_ range: NSRange?) {
        let path = CGMutablePath()
        if let range, range.length > 0 {
            for rect in textGeometry().rects(for: range) {
                path.addRect(CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height))
            }
        }
        selectionOverlay.path = path
    }
    func copyText(range: NSRange? = nil) -> String {
        guard let record else { return "" }
        switch record.kind {
        case .markdown:
            let label = self.label
            let old = label.selectionRange
            let delegate = label.delegate
            label.delegate = nil
            defer { label.selectionRange = old; label.delegate = delegate }
            label.selectionRange = range ?? NSRange(location: 0, length: label.attributedText.length)
            let text = label.selectedPlainText() ?? ""
            return text
        case let .card(source): return record.draft.isEmpty ? source : record.draft
        case let .diagram(source): return source
        }
    }
}
