import UIKit
import Litext
import MarkdownView
import MarkdownParser

final class BlockView: UIView, UITextViewDelegate {
    let markdown = ImageMarkdownView()
    private let preparedLabel = TextLabelView()
    var label: TextLabelView { preparedLabel.isHidden ? markdown.textLabelView : preparedLabel }
    private lazy var cardTitle = UILabel()
    private lazy var draft = UITextView()
    private lazy var fold = UIButton(type: .system)
    private lazy var save = UIButton(type: .system)
    private var diagram: DiagramView?
    private var workspaceContent: UIView?
    var makeWorkspaceAttachment: ((PreparedBlock, String, @escaping (CGFloat) -> Void) -> UIView)?
    var diagramRendered: Bool { diagram?.renderSucceeded == true }
    func diagramSnapshot() async throws -> UIImage? { try await diagram?.snapshot() }
    private(set) var record: PreparedBlock?
    var onChange: (() -> Void)?
    var onLink: ((URL) -> Void)?
    var onSaveNote: ((String) -> Void)?
    private var geometry: TextLabel.Layout?
    private let selectionOverlay = CAShapeLayer()
    private let attachmentSelectionOverlay = CAShapeLayer()
    private enum SelectionDisplay {
        case body(NSRange)
        case attachment(Int, NSRange)
    }
    private var displayedSelection: SelectionDisplay?
    private var attachmentGeometry: (label: TextLabelView, text: NSAttributedString, layout: TextLabel.Layout)?
    private(set) var isRestoringInteractionState = false
    private var lastWidth: CGFloat = 0
    private var lastHeight: CGFloat = 0
    private var displayedText = ""
    private var displayedWidth: CGFloat = 0
    private let revealMask = CALayer()
    private let settledTextMask = CAShapeLayer()
    private var revealingText: [(range: NSRange, layer: CAShapeLayer, until: CFTimeInterval)] = []
    private var revealCleanup: DispatchWorkItem?
    private lazy var citationTooltips = SourceCitationTooltips(view: self,
        container: { [weak self] in self },
        titles: { [weak self] in self?.record?.citationTitles ?? [:] })

    override init(frame: CGRect) {
        super.init(frame: frame)
        _ = citationTooltips
        for child in [markdown, preparedLabel] { addSubview(child) }
        preparedLabel.isSelectable = true
        preparedLabel.delegate = markdown
        markdown.throttleInterval = nil
        markdown.linkHandler = { [weak self] payload, _, _ in
            switch payload {
            case let .url(url): self?.onLink?(url)
            case let .string(value): if let url = URL(string: value) { self?.onLink?(url) }
            }
        }
        selectionOverlay.fillColor = UIColor.systemOrange.withAlphaComponent(0.23).cgColor
        selectionOverlay.zPosition = 20
        selectionOverlay.actions = ["path": NSNull()]
        layer.addSublayer(selectionOverlay)
        attachmentSelectionOverlay.zPosition = 20
        attachmentSelectionOverlay.actions = ["path": NSNull()]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func installCardControls() {
        guard cardTitle.superview == nil else { return }
        for child in [cardTitle, draft, fold, save] { addSubview(child) }
        cardTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        cardTitle.numberOfLines = 2
        draft.font = .systemFont(ofSize: 16)
        draft.backgroundColor = .secondarySystemBackground
        draft.delegate = self
        draft.accessibilityLabel = CatalystInterfaceCopy.text("摘抄草稿", "Excerpt draft")
        fold.accessibilityIdentifier = "toggle-card"
        fold.addTarget(self, action: #selector(toggleCard), for: .touchUpInside)
        save.setTitle(CatalystInterfaceCopy.text("放入笔记", "Add to note"), for: .normal)
        save.addTarget(self, action: #selector(saveCard), for: .touchUpInside)
    }

    func configure(_ block: PreparedBlock, theme: MarkdownTheme) {
        saveInteractionState()
        onChange = nil
        record = block
        markdown.containsImages = !block.imageSources.isEmpty
        workspaceContent?.removeFromSuperview(); workspaceContent = nil
        geometry = nil
        attachmentGeometry = nil
        lastWidth = 0
        displayedSelection = nil
        selectionOverlay.path = nil
        attachmentSelectionOverlay.removeFromSuperlayer()
        selectionOverlay.fillColor = theme.colors.selectionBackground?.cgColor
        attachmentSelectionOverlay.fillColor = theme.colors.selectionBackground?.cgColor
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
                preparedLabel.selectionBackgroundColor = .clear
                preparedLabel.isHidden = false
            } else { markdown.isHidden = false }
        case let .workspaceAttachment(identifier):
            let content = makeWorkspaceAttachment?(block, identifier) { [weak self, weak block] height in
                guard let self, let block, self.record === block,
                      height.isFinite, height > 0, abs(block.height - height) > 0.5 else { return }
                block.height = height
                self.onChange?()
            }
            if let content { workspaceContent = content; addSubview(content) }
        case let .card(source):
            installCardControls()
            for child in [cardTitle, draft, fold, save] { child.isHidden = false }
            draft.isHidden = block.collapsed; save.isHidden = block.collapsed
            fold.setTitle(block.collapsed ? CatalystInterfaceCopy.text("展开", "Expand") : CatalystInterfaceCopy.text("收起", "Collapse"), for: .normal)
            struct Card: Decodable { let title: String; let prompt: String }
            do {
                let card = try JSONDecoder().decode(Card.self, from: Data(source.utf8))
                cardTitle.text = card.title + " · " + card.prompt
                draft.text = block.draft
                save.isEnabled = true
            } catch {
                cardTitle.text = CatalystInterfaceCopy.text("摘抄内容无效：", "Excerpt content is invalid: ") + error.localizedDescription
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

    /// Fade only newly appended glyphs. Settled text is never redrawn with a lower opacity.
    func revealAppendedText(animated: Bool) {
        // Paragraph terminators belong to the renderer, not the growing text.
        // Keeping them in the prefix makes every append look like a replacement.
        let current = label.attributedText.string.replacingOccurrences(of: "[\\r\\n]+$", with: "", options: .regularExpression)
        let previous = displayedText
        defer { displayedText = current; displayedWidth = bounds.width }
        guard animated, !preparedLabel.isHidden else { finishTextReveal(); return }
        guard current != previous else { return }
        guard current.hasPrefix(previous), displayedWidth == 0 || displayedWidth == bounds.width else {
            finishTextReveal(); return
        }
        let range = NSRange(location: previous.utf16.count, length: current.utf16.count - previous.utf16.count)
        guard range.length > 0 else { return }
        let now = CACurrentMediaTime()
        revealingText.removeAll { $0.until <= now }
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.black.cgColor
        revealingText.append((range, layer, now + 0.32))
        let settled = CGMutablePath()
        settled.addRect(preparedLabel.bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        revealMask.frame = preparedLabel.bounds
        settledTextMask.frame = preparedLabel.bounds
        settledTextMask.fillColor = UIColor.black.cgColor
        settledTextMask.fillRule = .evenOdd
        for item in revealingText {
            let path = CGMutablePath()
            for rect in textGeometry().rects(for: item.range) {
                let glyphs = CGRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
                path.addRect(glyphs)
                settled.addRect(glyphs)
            }
            item.layer.frame = preparedLabel.bounds
            item.layer.path = path
        }
        settledTextMask.path = settled
        revealMask.sublayers = [settledTextMask] + revealingText.map(\.layer)
        preparedLabel.layer.mask = revealMask
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.32
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "stream-reveal")
        revealCleanup?.cancel()
        let cleanup = DispatchWorkItem { [weak self] in self?.finishTextReveal() }
        revealCleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: cleanup)
    }

    private func finishTextReveal() {
        revealCleanup?.cancel(); revealCleanup = nil
        revealingText.removeAll()
        preparedLabel.layer.mask = nil
        revealMask.sublayers = nil
    }

    func measure(width: CGFloat) -> CGFloat {
        guard let record else { return 1 }
        if lastWidth != width { geometry = nil }
        lastWidth = width
        switch record.kind {
        case .markdown:
            if record.preparedLayout != nil, !preparedLabel.isHidden {
                // Measure through the label's own layout: Litext keeps that measurement
                // and adopts it when the view is laid out at the same width, so the
                // paragraph is typeset once per width instead of once for the height
                // and again for drawing.
                preparedLabel.preferredMaxLayoutWidth = width
                lastHeight = max(24, ceil(preparedLabel.intrinsicContentSize.height))
                installSize(width: width, height: lastHeight)
                return lastHeight
            }
            if let layout = record.preparedLayout {
                lastHeight = max(24, ceil(layout.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
                installSize(width: width, height: lastHeight)
                return lastHeight
            }
            markdown.contentWidth = width
            lastHeight = max(24, ceil(markdown.boundingSize(for: width).height))
            markdown.frame = CGRect(x: 0, y: 0, width: width, height: lastHeight)
            markdown.layoutIfNeeded()
        case .workspaceAttachment:
            lastHeight = max(1, record.height)
        case .card:
            lastHeight = record.collapsed ? 48 : 204
            draft.isHidden = record.collapsed; save.isHidden = record.collapsed
            fold.setTitle(record.collapsed ? CatalystInterfaceCopy.text("展开", "Expand") : CatalystInterfaceCopy.text("收起", "Collapse"), for: .normal)
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
        if displayedWidth != 0, displayedWidth != bounds.width { finishTextReveal() }
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
        case .workspaceAttachment: workspaceContent?.frame = bounds
        }
        if displayedSelection != nil {
            label.layoutIfNeeded()
            markdown.layoutIfNeeded()
            updateSelectionOverlay()
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
        // An old cell can detach after a replacement view has restored this block.
        // Only its current view may write interaction state back to the record.
        guard let record, record.renderedView === self, case .markdown = record.kind, preparedLabel.isHidden else { return }
        record.horizontalOffsets = scrollViews(in: markdown).map { $0.contentOffset.x }
        record.attachmentSelections = attachmentLabels.map(\.selectionRange)
    }
    func restoreInteractionState() {
        guard let record else { return }
        isRestoringInteractionState = true
        defer { isRestoringInteractionState = false }
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
        displayedSelection = range.flatMap { $0.length > 0 ? .body($0) : nil }
        updateSelectionOverlay()
    }
    func displayAttachmentSelection(at index: Int, range: NSRange) {
        displayedSelection = .attachment(index, range)
        updateSelectionOverlay()
    }
    private func selectedLabelAndRange() -> (TextLabelView, NSRange)? {
        guard let displayedSelection else { return nil }
        switch displayedSelection {
        case let .body(range): return (label, range)
        case let .attachment(index, range):
            let labels = attachmentLabels
            guard labels.indices.contains(index) else { return nil }
            return (labels[index], range)
        }
    }
    private func selectionGeometry(for selectedLabel: TextLabelView) -> TextLabel.Layout {
        if selectedLabel === label { return textGeometry() }
        if attachmentGeometry?.label !== selectedLabel
            || attachmentGeometry?.text.isEqual(to: selectedLabel.attributedText) != true {
            attachmentGeometry = (selectedLabel, selectedLabel.attributedText,
                                  TextLabel.Layout(attributedString: selectedLabel.attributedText))
        }
        attachmentGeometry!.layout.containerSize = selectedLabel.bounds.size
        return attachmentGeometry!.layout
    }
    private func selectionRects(in selectedLabel: TextLabelView, range: NSRange) -> [CGRect] {
        let length = selectedLabel.attributedText.length
        guard range.location >= 0, range.location < length, range.length > 0 else { return [] }
        let safeRange = NSRange(location: range.location, length: min(range.length, length - range.location))
        return selectionGeometry(for: selectedLabel).rects(for: safeRange).map {
            CGRect(x: $0.minX, y: selectedLabel.bounds.height - $0.maxY, width: $0.width, height: $0.height)
        }
    }
    var displayedSelectionRects: [CGRect] {
        guard let (selectedLabel, range) = selectedLabelAndRange() else { return [] }
        var clip = bounds
        var ancestor = selectedLabel.superview
        while let view = ancestor, view !== self {
            if view.clipsToBounds { clip = clip.intersection(view.convert(view.bounds, to: self)) }
            ancestor = view.superview
        }
        return selectionRects(in: selectedLabel, range: range).compactMap {
            let visible = selectedLabel.convert($0, to: self).intersection(clip)
            return visible.isEmpty || visible.isNull ? nil : visible
        }
    }
    private func updateSelectionOverlay() {
        selectionOverlay.path = nil
        attachmentSelectionOverlay.path = nil
        attachmentSelectionOverlay.removeFromSuperlayer()
        guard let (selectedLabel, range) = selectedLabelAndRange() else { return }
        finishTextReveal()
        let rects = selectionRects(in: selectedLabel, range: range)
        let path = CGMutablePath()
        for rect in rects { path.addRect(rect) }
        if selectedLabel === label {
            let bodyPath = CGMutablePath()
            for rect in rects { bodyPath.addRect(selectedLabel.convert(rect, to: self)) }
            selectionOverlay.path = bodyPath
        } else {
            // An attachment highlight lives with its label so horizontal scrolling
            // moves and clips it with the code, instead of leaving a mark over the pane.
            attachmentSelectionOverlay.path = path
            selectedLabel.layer.addSublayer(attachmentSelectionOverlay)
        }
    }
    static func plainText(in label: TextLabelView, range: NSRange? = nil) -> String {
        let length = label.attributedText.length
        let requested = range ?? NSRange(location: 0, length: length)
        guard requested.location >= 0, requested.location <= length, requested.length > 0 else { return "" }
        let safeRange = NSRange(location: requested.location, length: min(requested.length, length - requested.location))
        let result = NSMutableAttributedString(attributedString: label.attributedText.attributedSubstring(from: safeRange))
        result.enumerateAttribute(.litextAttachment, in: NSRange(location: 0, length: result.length), options: .reverse) { value, range, _ in
            if let attachment = value as? TextLabel.Attachment {
                result.replaceCharacters(in: range, with: attachment.attributedStringRepresentation())
            }
        }
        return result.string
    }
    func copyText(range: NSRange? = nil) -> String {
        guard let record else { return "" }
        switch record.kind {
        case .markdown:
            return Self.plainText(in: label, range: range)
        case let .card(source): return record.draft.isEmpty ? source : record.draft
        case let .diagram(source): return source
        case let .workspaceAttachment(identifier): return identifier.hasPrefix("activity/") ? "" : CatalystInterfaceCopy.text("[互动内容]", "[interactive content]")
        }
    }
}
