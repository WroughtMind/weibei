import AppKit
import CoreText
import Litext
import MarkdownView

/// A display surface owns geometry; its document survives row recycling.
@MainActor
public final class CandidateTextView: MarkdownTextView {
    public private(set) var preparedDocument: CandidateDocument?
    public var onHeightChange: (() -> Void)?
    public var onOpenURL: ((URL) -> Void)?
    public var imageLoader: ((String, @escaping (Data?) -> Void) -> Void)?
    public var extensionView: ((CandidateAttachment, CGFloat, @escaping (CGFloat) -> Void) -> NSView?)?
    public private(set) var measurements = 0
    public private(set) var applications = 0
    public private(set) var timings: [LabTiming] = []
    private var embedded: [Int: CandidateInlineView] = [:]
    private var embeddedDescriptors: [Int: CandidateAttachment] = [:]
    private var measuring = false
    private var applying = false
    private var lineIndexDirty = true
    private var readingLines: [(range: NSRange, y: CGFloat)] = []
    private var contentWidth: CGFloat = 640
    private var selectionToRestore: NSRange?
    private var lastMeasured: (width: CGFloat, height: CGFloat)?

    public init() {
        super.init()
        throttleInterval = nil
        linkHandler = { [weak self] payload, _, _ in
            let url: URL?
            switch payload { case let .url(value): url = value; case let .string(value): url = URL(string: value) }
            guard let self, let url else { return }
            if url.scheme == "weibei-callout", let id = Int(url.absoluteString.dropFirst("weibei-callout:".count)) {
                self.preparedDocument?.toggleCallout(id)
            } else { self.onOpenURL?(url) }
        }
    }
    required init?(coder: NSCoder) { nil }

    public func bind(_ document: CandidateDocument) {
        guard self.preparedDocument !== document else { return }
        unbind()
        self.preparedDocument = document
        embedded.removeAll()
        embeddedDescriptors.removeAll()
        reset()
        // Always install the full matching baseline before subscribing to updates.
        if let content = document.content { apply(content, revision: document.displayedRevision, baseline: true) }
        document.onApply = { [weak self, weak document] content, revision in
            guard let self, let document, self.preparedDocument === document else { return }
            self.apply(content, revision: revision)
        }
    }

    public func unbind() {
        if window != nil || textLabelView.selectionRange != nil {
            preparedDocument?.selectedRange = textLabelView.selectionRange
        }
        preparedDocument?.onApply = nil
        preparedDocument = nil
        lastMeasured = nil
    }

    private func apply(_ content: MarkdownContent, revision: Int, baseline: Bool = false) {
        guard let document = preparedDocument else { return }
        let start = ProcessInfo.processInfo.systemUptime
        let selection = baseline ? document.selectedRange : textLabelView.selectionRange
        let oldText = textLabelView.attributedText.string
        applying = true
        lastMeasured = nil
        let changedAttachments = embeddedDescriptors.contains { document.attachments[$0.key] != $0.value }
        for (id, descriptor) in embeddedDescriptors where document.attachments[id] != descriptor {
            embedded[id] = nil; embeddedDescriptors[id] = nil
        }
        if changedAttachments { invalidateInlineDecoration() }
        setContentImmediately(content, theme: document.theme)
        if let selection {
            let newText = textLabelView.attributedText.string
            textLabelView.selectionRange = baseline ? selection : Self.mapSelection(selection, from: oldText, to: newText)
        }
        applying = false
        applications += 1
        lineIndexDirty = true
        onHeightChange?()
        let timing = LabTiming(operation: "main_apply", milliseconds:
            (ProcessInfo.processInfo.systemUptime - start) * 1_000, revision: revision)
        timings.append(timing); document.record(timing)
    }

    /// Preserve a selected prefix while a stream appends or closes Markdown syntax.
    public static func mapSelection(_ range: NSRange, from old: String, to new: String) -> NSRange {
        let a = Array(old.utf16), b = Array(new.utf16)
        var prefix = 0
        while prefix < min(a.count, b.count), a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(a.count, b.count) - prefix, a[a.count - suffix - 1] == b[b.count - suffix - 1] { suffix += 1 }
        func map(_ position: Int) -> Int {
            if position <= prefix { return position }
            if position >= a.count - suffix { return max(0, position + b.count - a.count) }
            return min(position, b.count - suffix)
        }
        let start = min(b.count, map(range.location))
        return NSRange(location: start, length: max(0, min(b.count, map(NSMaxRange(range))) - start))
    }

    public func measuredHeight(for width: CGFloat) -> CGFloat {
        let width = max(1, width)
        if let lastMeasured, lastMeasured.width == width { return lastMeasured.height }
        measuring = true
        defer { measuring = false }
        if contentWidth != width {
            contentWidth = width
            for item in embedded.values { item.resize(width: width) }
            if !embedded.isEmpty { textLabelView.reloadTextLayout() }
            lineIndexDirty = true
        }
        let start = ProcessInfo.processInfo.systemUptime
        let height: CGFloat
        if let cached = preparedDocument?.measuredHeights[width] { height = cached }
        else {
            height = max(1, ceil(boundingSize(for: width).height))
            measurements += 1
            preparedDocument?.measuredHeights[width] = height
            let timing = LabTiming(operation: "main_measure", milliseconds:
                (ProcessInfo.processInfo.systemUptime - start) * 1_000, revision: preparedDocument?.displayedRevision ?? 0)
            timings.append(timing); preparedDocument?.record(timing)
        }
        lastMeasured = (width, height)
        return height
    }

    public override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        lineIndexDirty = true
        guard !measuring, !applying else { return }
        lastMeasured = nil
        preparedDocument?.measuredHeights.removeAll(keepingCapacity: true)
        onHeightChange?()
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, window != nil { preparedDocument?.selectedRange = textLabelView.selectionRange }
        super.viewWillMove(toWindow: newWindow)
    }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        trackedScrollView = enclosingScrollView
        if window != nil { selectionToRestore = preparedDocument?.selectedRange; needsLayout = true }
    }

    public override func layout() {
        super.layout()
        if let selectionToRestore {
            textLabelView.selectionRange = selectionToRestore; self.selectionToRestore = nil
        }
        guard lineIndexDirty else { return }
        lineIndexDirty = false
        // Built once per layout change. Scrolling consults this index, not the source.
        readingLines = textLabelView.layoutRuns(matching: .font).map {
            ($0.stringRange, textLabelView.bounds.height - $0.lineRect.maxY)
        }.sorted { $0.y < $1.y }
    }

    public func readingPosition(at point: CGPoint, in view: NSView) -> (index: Int, offset: CGFloat)? {
        let point = textLabelView.convert(point, from: view)
        guard let line = readingLines.last(where: { $0.y <= point.y }) ?? readingLines.first else { return nil }
        return (line.range.location, point.y - line.y)
    }

    public func readingPoint(index: Int, offset: CGFloat, in view: NSView) -> CGPoint? {
        guard let line = readingLines.first(where: { NSLocationInRange(index, $0.range) })
            ?? readingLines.last(where: { $0.range.location <= index }) else { return nil }
        return view.convert(CGPoint(x: 0, y: line.y + offset), from: textLabelView)
    }

    public override func decorate(inlineText text: NSAttributedString, theme: MarkdownTheme) -> NSAttributedString {
        guard let document = preparedDocument else { return text }
        let source = text.string
        let matches = source.matches(of: /\u{F0000}([0-9]+)\u{F0001}/)
        guard !matches.isEmpty else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        for match in matches.reversed() {
            guard let id = Int(match.1), let descriptor = document.attachments[id] else { continue }
            let item: CandidateInlineView
            if let cached = embedded[id] { item = cached }
            else {
                item = CandidateInlineView(descriptor: descriptor, document: document, width: contentWidth,
                    imageLoader: imageLoader, extensionView: extensionView)
                embedded[id] = item
                embeddedDescriptors[id] = descriptor
                item.onResize = { [weak self, weak document] in
                    guard let self, let document, self.preparedDocument === document else { return }
                    self.lastMeasured = nil
                    document.measuredHeights.removeAll(keepingCapacity: true)
                    self.textLabelView.reloadTextLayout()
                    self.onHeightChange?()
                }
            }
            result.replaceCharacters(in: NSRange(match.range, in: source),
                with: item.attachment.attributedString(attributes: [.font: theme.fonts.body]))
        }
        return result
    }
}

@MainActor
private final class CandidateInlineView: NSView, TextLabel.AttachmentRepresentable {
    private weak var currentAttachment: TextLabel.Attachment?
    var attachment: TextLabel.Attachment {
        if let currentAttachment { return currentAttachment }
        let value = TextLabel.Attachment()
        value.view = self
        value.size = frame.size
        currentAttachment = value
        return value
    }
    let descriptor: CandidateAttachment
    var onResize: (() -> Void)?
    private var naturalSize = NSSize(width: 640, height: 160)
    private var external: NSView?
    private let caption = NSTextField(wrappingLabelWithString: "")
    private let picture = NSImageView()
    override var isFlipped: Bool { true }

    init(descriptor: CandidateAttachment, document: CandidateDocument, width: CGFloat,
         imageLoader: ((String, @escaping (Data?) -> Void) -> Void)?,
         extensionView: ((CandidateAttachment, CGFloat, @escaping (CGFloat) -> Void) -> NSView?)?) {
        self.descriptor = descriptor
        super.init(frame: .zero)
        switch descriptor {
        case let .image(source, alt):
            caption.stringValue = alt
            caption.textColor = .secondaryLabelColor
            caption.font = .systemFont(ofSize: 11)
            picture.imageScaling = .scaleProportionallyUpOrDown
            addSubview(picture); addSubview(caption)
            if let image = document.images[source] { install(image) }
            else {
                imageLoader?(source) { [weak self, weak document] data in
                    guard let self, let document else { return }
                    if let data, let image = NSImage(data: data) {
                        document.images[source] = image
                        self.install(image)
                    } else {
                        self.caption.stringValue = "图片无法载入：\(alt)"
                    }
                }
            }
        default:
            external = extensionView?(descriptor, width) { [weak self] height in
                guard let self, height.isFinite, height > 0, abs(self.naturalSize.height - height) > 0.5 else { return }
                self.naturalSize.height = height
                self.resize(width: max(1, self.frame.width))
                self.onResize?()
            }
            if let external { addSubview(external) }
            else { caption.stringValue = "图示未能载入"; addSubview(caption) }
        }
        resize(width: width)
    }
    required init?(coder: NSCoder) { nil }

    private func install(_ image: NSImage) {
        picture.image = image
        naturalSize = image.size
        resize(width: max(1, frame.width))
        onResize?()
    }

    func resize(width: CGFloat) {
        let height: CGFloat
        if case .image = descriptor {
            height = min(1, width / max(1, naturalSize.width)) * naturalSize.height + 24
        } else { height = naturalSize.height }
        let size = NSSize(width: width, height: max(24, height))
        currentAttachment?.size = size
        setFrameSize(size)
        external?.setFrameSize(size)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        picture.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(1, bounds.height - 24))
        caption.frame = NSRect(x: 0, y: max(0, bounds.height - 22), width: bounds.width, height: 22)
        external?.frame = bounds
    }
    func attributedStringRepresentation() -> NSAttributedString {
        switch descriptor {
        case let .image(source, alt): return .init(string: "![\(alt)](\(source))")
        case let .mermaid(source): return .init(string: source)
        case let .visualization(id): return .init(string: "图示：\(id)")
        }
    }
}
