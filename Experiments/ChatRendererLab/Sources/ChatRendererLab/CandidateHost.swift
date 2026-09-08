import AppKit
import MarkdownView

@MainActor
private final class ReportingMarkdownView: MarkdownTextView {
    var onSizeInvalidated: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeInvalidated?()
    }
}

@MainActor
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Candidate-only stage A host. This is NOT AgentPaneView or a production-list A/B.
@MainActor
final class CandidateHost: NSView {
    let scroll = NSScrollView()
    private let documentView = FlippedDocumentView()
    private let markdown = ReportingMarkdownView()
    var textView: MarkdownTextView { markdown }
    private(set) var timings: [LabTiming] = []
    private(set) var measurementCount = 0
    private(set) var measurementIsValid = true
    private var currentRevision = 0
    private var cachedHeight: (width: CGFloat, height: CGFloat)?
    private var layoutQueued = false
    private var applying = false
    private var needsAnotherLayout = false
    private(set) var contentHeight: CGFloat = 1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = documentView
        addSubview(scroll)
        documentView.addSubview(markdown)
        markdown.throttleInterval = nil
        markdown.trackedScrollView = scroll // selection auto-scroll, NOT viewport virtualization
        // The fixture link never opens a browser or reads files.
        markdown.linkHandler = { _, _, _ in }
        markdown.onSizeInvalidated = { [weak self] in
            guard let self else { return }
            self.cachedHeight = nil
            self.scheduleLayout()
        }
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }

    func present(_ content: MarkdownContent, theme: MarkdownTheme, revision: Int) {
        let start = ProcessInfo.processInfo.systemUptime
        currentRevision = revision
        cachedHeight = nil
        markdown.setContentImmediately(content, theme: theme)
        needsLayout = true
        layoutSubtreeIfNeeded()
        timings.append(.init(operation: "main_apply_and_layout", milliseconds:
            (ProcessInfo.processInfo.systemUptime - start) * 1_000, revision: revision))
    }

    func reset() {
        currentRevision = 0
        cachedHeight = nil
        timings.removeAll()
        measurementCount = 0
        measurementIsValid = true
        markdown.reset()
        scroll.contentView.scroll(to: .zero)
        needsLayout = true
    }

    private func scheduleLayout() {
        if applying { needsAnotherLayout = true; return }
        guard !layoutQueued else { return }
        layoutQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutQueued = false
            self.needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        guard !applying else { return }
        applying = true
        defer {
            applying = false
            if needsAnotherLayout {
                needsAnotherLayout = false
                scheduleLayout()
            }
        }
        scroll.frame = bounds
        let columnWidth = max(1, scroll.contentView.bounds.width)
        let width = max(1, columnWidth - 48)
        let height: CGFloat
        if let cachedHeight, cachedHeight.width == width {
            height = cachedHeight.height
        } else {
            let start = ProcessInfo.processInfo.systemUptime
            let measured = markdown.boundingSize(for: width).height
            measurementIsValid = measured.isFinite && (currentRevision == 0 || measured > 0)
            height = measured.isFinite ? max(1, ceil(measured)) : 1
            measurementCount += 1
            timings.append(.init(operation: "main_measure", milliseconds:
                (ProcessInfo.processInfo.systemUptime - start) * 1_000, revision: currentRevision))
            cachedHeight = (width, height)
        }
        contentHeight = height
        let textFrame = NSRect(x: 24, y: 24, width: width, height: height)
        if markdown.frame != textFrame { markdown.frame = textFrame }
        markdown.needsLayout = true
        markdown.layoutSubtreeIfNeeded()
        let size = NSSize(width: columnWidth, height: max(scroll.contentView.bounds.height, height + 48))
        if documentView.frame.size != size { documentView.setFrameSize(size) }
    }

    func copyAllWithoutPasteboard() -> String {
        markdown.textLabelView.selectAll()
        let value = markdown.textLabelView.selectedPlainText() ?? ""
        markdown.textLabelView.clearSelection()
        return value
    }

    func scrollToBottom() {
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: max(0, documentView.bounds.height - clip.bounds.height)))
        scroll.reflectScrolledClipView(clip)
    }

    func saveViewport(to url: URL) throws {
        layoutSubtreeIfNeeded()
        guard let bitmap = bitmapImageRepForCachingDisplay(in: bounds) else {
            throw LabFailure.message("Could not allocate the viewport bitmap")
        }
        cacheDisplay(in: bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw LabFailure.message("Could not encode the viewport bitmap")
        }
        try data.write(to: url, options: .atomic)
    }
}
