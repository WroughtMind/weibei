import AppKit
import SwiftUI
import WeiBeiCore

typealias NativeChatVisualizationView = (String, CGFloat, @escaping (CGFloat) -> Void) -> NSView?

@MainActor
enum NativeChatMarkdownAttributed {
    static func make(runs: [NativeChatMarkdownRun], fontSize: CGFloat, isDark: Bool,
                     attachment: (NativeChatAttachmentDescriptor) -> NSTextAttachment) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        for run in runs {
            let s = run.style
            let size = s.heading > 0 ? fontSize * [1.7, 1.45, 1.25, 1.12, 1.05, 1][min(s.heading - 1, 5)] : fontSize
            var font = s.code ? NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: .regular) : NSFont.systemFont(ofSize: size)
            if s.bold || s.heading > 0 { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if s.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = fontSize * 0.3
            paragraph.paragraphSpacing = fontSize * 0.45
            paragraph.headIndent = CGFloat(s.indent) * fontSize * 1.5 + CGFloat(s.quote) * fontSize
            paragraph.firstLineHeadIndent = max(0, paragraph.headIndent - (s.indent > 0 ? fontSize * 1.2 : 0))
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font, .paragraphStyle: paragraph,
                .foregroundColor: s.quote > 0 ? WeiBeiNativePalette.secondaryInk() : WeiBeiNativePalette.ink()
            ]
            if s.callout != nil { attributes[.backgroundColor] = WeiBeiNativePalette.cinnabarSoft() }
            if s.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if s.code { attributes[.backgroundColor] = WeiBeiNativePalette.codePaper() }
            if s.highlight { attributes[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(isDark ? 0.28 : 0.2) }
            if s.footnote { attributes[.foregroundColor] = WeiBeiNativePalette.secondaryInk(); attributes[.toolTip] = run.text }
            if let link = s.link { attributes[.link] = link; attributes[.foregroundColor] = WeiBeiNativePalette.link() }
            if let descriptor = run.attachment { attributes[.attachment] = attachment(descriptor) }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }
}

struct NativeChatMarkdownView: NSViewRepresentable {
    var markdown: String
    var messageID: UUID? = nil
    var fontSize: CGFloat
    var isDark: Bool
    var appearanceKey: String = ""
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    var placeholderHeight: CGFloat = 1
    var onOpenURL: (URL) -> Void
    var visualizationView: NativeChatVisualizationView? = nil
    var imageLoader: ((String, @escaping (Data?) -> Void) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NativeChatTextView {
        let view = NativeChatTextView(usingTextLayoutManager: true)
        view.isEditable = false; view.isSelectable = true
        view.drawsBackground = false
        // Keep TextKit's viewport inside this answer, including while it is offscreen.
        view.clipsToBounds = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        // SwiftUI assigns the height returned by sizeThatFits; TextKit must not resize it again.
        view.isVerticallyResizable = false
        view.autoresizingMask = []
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator
        context.coordinator.view = view
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.layoutDidChange() }
        view.onWidthChange = { [weak coordinator = context.coordinator] width in coordinator?.willResize(to: width) }
        view.onUserScroll = { [weak coordinator = context.coordinator] in coordinator?.userWillScroll() }
        context.coordinator.pipeline.onApply = { [weak coordinator = context.coordinator] document, edit in coordinator?.apply(document, edit: edit) }
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: NativeChatTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onOpenURL = onOpenURL
        coordinator.visualizationView = visualizationView
        coordinator.imageLoader = imageLoader
        let restyle = coordinator.fontSize != fontSize || coordinator.isDark != isDark || coordinator.appearanceKey != appearanceKey || coordinator.interfaceLanguage != interfaceLanguage
        coordinator.fontSize = fontSize; coordinator.isDark = isDark; coordinator.appearanceKey = appearanceKey; coordinator.interfaceLanguage = interfaceLanguage
        view.linkTextAttributes = [.foregroundColor: WeiBeiNativePalette.link()]
        view.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if restyle { coordinator.restyle() }
        coordinator.submit(markdown: markdown, messageID: messageID)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeChatTextView, context: Context) -> CGSize? {
        // An infinite proposal asks for flexibility; it must not resize the live text container.
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        // SwiftUI also probes unused finite widths. Reflow only at the assigned view
        // width; layoutDidChange requests another sizing pass after an actual resize.
        let height = context.coordinator.document.runs.isEmpty
            ? placeholderHeight : context.coordinator.measuredHeight()
        return CGSize(width: width, height: max(1, height))
    }
    static func dismantleNSView(_ nsView: NativeChatTextView, coordinator: Coordinator) {
        nsView.onLayout = nil
        nsView.onWidthChange = nil
        nsView.onUserScroll = nil
        coordinator.pipeline.invalidate()
        coordinator.view = nil
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        // The attributed document outlives a reusable view. Binding installs a complete
        // storage, so a delta is never applied to a different message's NSTextStorage.
        let preparedStorage = NSTextStorage()
        private lazy var preparedContent: NSTextContentStorage = {
            let content = NSTextContentStorage()
            content.textStorage = preparedStorage
            return content
        }()
        private var extentObservation: NSKeyValueObservation?
        private weak var observedScroll: NSScrollView?
        private var scrollObserver: NSObjectProtocol?
        var savedSelection: [NSValue] = [NSValue(range: NSRange(location: 0, length: 0))]
        weak var view: NativeChatTextView? {
            willSet {
                extentObservation = nil
                readingAnchor = nil; resizeAnchor = nil
                if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
                scrollObserver = nil; observedScroll = nil
                if let view, view !== newValue {
                    savedSelection = view.selectedRanges
                    view.textLayoutManager?.replace(NSTextContentStorage())
                }
            }
            didSet {
                guard let view else { return }
                view.textLayoutManager?.replace(preparedContent)
                view.selectedRanges = savedSelection
                extentObservation = view.textLayoutManager?.observe(\.usageBoundsForTextContainer, options: [.initial, .new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.layoutDidChange() }
                }
            }
        }
        var managesReadingPosition = true
        var onHeightChange: ((CGFloat) -> Void)?
        var onViewportLayout: (() -> Void)?
        var onWillChange: ((NativeChatMarkdownEdit?) -> Void)?
        var onDocumentChange: (() -> Void)?
        var onCalloutToggle: ((Int) -> Void)?
        let pipeline = NativeChatMarkdownPipeline()
        var document = NativeChatMarkdownDocument()
        var fontSize: CGFloat = 15
        var isDark = false
        var appearanceKey = ""
        var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
        var onOpenURL: (URL) -> Void = { _ in }
        var visualizationView: NativeChatVisualizationView?
        var imageLoader: ((String, @escaping (Data?) -> Void) -> Void)?
        private var applying = false
        private var heightCache: (width: CGFloat, height: CGFloat)?
        private var snapshot: NativeChatMarkdownPipeline.Snapshot?
        private var pendingLayoutUpdate = false
        private var lastLayoutHeight: CGFloat = 0
        private var readingAnchor: (location: any NSTextLocation, offset: CGFloat, width: CGFloat)?
        // Kept through TextKit estimate corrections; an actual user scroll ends it.
        private var resizeAnchor: (location: any NSTextLocation, offset: CGFloat, width: CGFloat)?
        private var estimatedCharacters = 0
        private var estimatedParagraphs = 0

        func willResize(to width: CGFloat) {
            guard managesReadingPosition else { return }
            if let anchor = resizeAnchor {
                resizeAnchor = (anchor.location, anchor.offset, width)
                return
            }
            // Capture the currently displayed line before NSTextView changes its width.
            // An earlier layout callback may predate a scroll or an attachment correction.
            if resizeAnchor == nil { rememberReadingPosition() }
            guard let anchor = readingAnchor else { return }
            resizeAnchor = (anchor.location, anchor.offset, width)
        }

        func userWillScroll() {
            resizeAnchor = nil
            readingAnchor = nil
        }

        deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }

        func layoutDidChange() {
            if managesReadingPosition, let scroll = view?.enclosingScrollView, scroll !== observedScroll {
                if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
                observedScroll = scroll
                scrollObserver = NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification,
                    object: scroll, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.userWillScroll() } }
            }
            guard !pendingLayoutUpdate else { return }
            pendingLayoutUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingLayoutUpdate = false
                guard !self.document.runs.isEmpty, let view = self.view, let container = view.textContainer,
                      let height = view.textLayoutManager?.usageBoundsForTextContainer.maxY,
                      height.isFinite, height > 0 else { return }
                if abs(height - self.lastLayoutHeight) > 0.5 || self.heightCache?.width != container.size.width {
                    self.lastLayoutHeight = height
                    self.heightCache = (container.size.width, max(1, ceil(height)))
                    view.invalidateIntrinsicContentSize()
                    self.onHeightChange?(max(1, ceil(height)))
                }
                self.onViewportLayout?()
                guard self.managesReadingPosition else { return }
                // Restore only after SwiftUI has applied the new height. Earlier coordinates
                // still belong to the previous row frame and move the reader to another paragraph.
                guard abs(view.frame.height - ceil(height)) < 1 else { return }
                self.restoreReadingPosition()
                if self.resizeAnchor == nil { self.rememberReadingPosition() }
            }
        }

        private func rememberReadingPosition() {
            guard let view, view.visibleRect.minY > 0,
                  let clip = view.enclosingScrollView?.contentView,
                  let manager = view.textLayoutManager, let content = manager.textContentManager,
                  let fragment = manager.textLayoutFragment(for: CGPoint(x: 1, y: view.visibleRect.minY + 1)),
                  let line = fragment.textLineFragment(forVerticalOffset: view.visibleRect.minY + 1 - fragment.layoutFragmentFrame.minY, requiresExactMatch: false),
                  let location = content.location(fragment.textElement?.elementRange?.location ?? fragment.rangeInElement.location, offsetBy: line.characterRange.location)
            else { readingAnchor = nil; return }
            let y = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
            // Keep the same character through successive reflows, even when it is no longer
            // the first character on its line. Otherwise each width step drifts backwards.
            let end = content.location(location, offsetBy: line.characterRange.length)
            let retained = readingAnchor?.location
            let anchor = retained.flatMap { previous in
                previous.compare(location) != .orderedAscending && end.map { previous.compare($0) == .orderedAscending } == true ? previous : nil
            } ?? location
            readingAnchor = (anchor, view.convert(CGPoint(x: 0, y: y), to: clip).y - clip.bounds.minY, view.frame.width)
        }

        private func restoreReadingPosition() {
            guard let anchor = resizeAnchor, let view, abs(view.frame.width - anchor.width) < 0.5,
                  let scroll = view.enclosingScrollView, let manager = view.textLayoutManager else { return }
            manager.ensureLayout(for: NSTextRange(location: anchor.location))
            guard let fragment = manager.textLayoutFragment(for: anchor.location),
                  let line = fragment.textLineFragment(for: anchor.location, isUpstreamAffinity: false) else { return }
            let y = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
            let clip = scroll.contentView
            let target = view.convert(CGPoint(x: 0, y: y), to: clip).y - anchor.offset
            let rect = CGRect(x: clip.bounds.minX, y: target, width: clip.bounds.width, height: clip.bounds.height)
            let origin = clip.constrainBoundsRect(rect).origin
            if abs(origin.y - clip.bounds.minY) < 0.5 { return }
            clip.scroll(to: origin)
            scroll.reflectScrolledClipView(clip)

        }

        func submit(markdown: String, messageID: UUID?) {
            let toggles = snapshot?.messageID == messageID ? snapshot?.toggledCallouts ?? [] : []
            let input = NativeChatMarkdownPipeline.Snapshot(markdown: markdown, messageID: messageID, toggledCallouts: toggles, interfaceLanguage: interfaceLanguage)
            snapshot = input; pipeline.submit(input)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            if url.scheme == "weibei-callout", let id = Int(url.absoluteString.dropFirst("weibei-callout:".count)) {
                if let onCalloutToggle { onCalloutToggle(id); return true }
                guard var input = snapshot else { return true }
                if input.toggledCallouts.contains(id) { input.toggledCallouts.remove(id) } else { input.toggledCallouts.insert(id) }
                snapshot = input; pipeline.submit(input)
            } else { onOpenURL(url) }
            return true
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let text = notification.object as? NativeChatTextView, text === view else { return }
            savedSelection = text.selectedRanges
        }
        func makeAttachment(_ descriptor: NativeChatAttachmentDescriptor) -> NSTextAttachment {
            weak var changedAttachment: NativeChatTextAttachment?
            let attachment = NativeChatTextAttachment(descriptor: descriptor, fontSize: fontSize, isDark: isDark,
                onOpenURL: { [weak self] in self?.onOpenURL($0) },
                onSizeChange: { [weak self] in self?.attachmentSizeChanged(changedAttachment) },
                onWillResize: { [weak self] in self?.onWillChange?(nil) },
                visualizationView: visualizationView, imageLoader: imageLoader, interfaceLanguage: interfaceLanguage)
            changedAttachment = attachment
            return attachment
        }
        func attributed(_ runs: [NativeChatMarkdownRun]) -> NSAttributedString {
            NativeChatMarkdownAttributed.make(runs: runs, fontSize: fontSize, isDark: isDark, attachment: makeAttachment)
        }
        func apply(_ document: NativeChatMarkdownDocument, edit: NativeChatMarkdownEdit) {
            let storage = preparedStorage
            onWillChange?(edit)
            self.document = document
            estimatedCharacters = document.utf16Count
            estimatedParagraphs = document.runs.reduce(0) { $0 + $1.text.utf16.filter { $0 == 10 }.count }
            heightCache = nil
            guard edit.range.length > 0 || !edit.replacement.isEmpty else { return }
            readingAnchor = nil; resizeAnchor = nil
            applying = true
            defer { applying = false; heightCache = nil }
            let selected = (view?.selectedRanges ?? savedSelection).map(\.rangeValue).map(edit.mapSelection)
            // Reuse unchanged attachments inside an otherwise changed span as well.
            var reusable: [NativeChatTextAttachment] = []
            storage.enumerateAttribute(.attachment, in: edit.range) { value, _, _ in
                if let item = value as? NativeChatTextAttachment { reusable.append(item) }
            }
            let replacement = NativeChatMarkdownAttributed.make(runs: edit.replacement, fontSize: fontSize, isDark: isDark) { descriptor in
                if let index = reusable.firstIndex(where: { $0.descriptor == descriptor }) ?? reusable.firstIndex(where: { $0.descriptor.sameKind(as: descriptor) }) {
                    let item = reusable.remove(at: index)
                    item.update(descriptor: descriptor, fontSize: self.fontSize, isDark: self.isDark, interfaceLanguage: self.interfaceLanguage)
                    return item
                }
                return self.makeAttachment(descriptor)
            }
            storage.beginEditing(); storage.replaceCharacters(in: edit.range, with: replacement); storage.endEditing()
            savedSelection = selected.map { NSValue(range: NSRange(location: min($0.location, storage.length), length: min($0.length, max(0, storage.length - $0.location)))) }
            view?.selectedRanges = savedSelection
            view?.needsLayout = true
            view?.invalidateIntrinsicContentSize()
            onDocumentChange?()
        }
        func restyle() {
            heightCache = nil
            let storage = preparedStorage
            guard storage.length > 0 else { return }
            onWillChange?(nil)
            applying = true
            defer { applying = false; heightCache = nil; view?.invalidateIntrinsicContentSize() }
            var location = 0
            storage.beginEditing()
            for run in document.runs {
                let range = NSRange(location: location, length: run.utf16Count)
                var attributes = attributed([NativeChatMarkdownRun(text: run.text, style: run.style)]).attributes(at: 0, effectiveRange: nil)
                if let attachment = storage.attribute(.attachment, at: location, effectiveRange: nil) as? NativeChatTextAttachment {
                    attachment.update(descriptor: attachment.descriptor, fontSize: fontSize, isDark: isDark, interfaceLanguage: interfaceLanguage)
                    attributes[.attachment] = attachment
                }
                storage.setAttributes(attributes, range: range); location += range.length
            }
            storage.endEditing()
        }
        func attachmentSizeChanged(_ attachment: NativeChatTextAttachment?) {
            heightCache = nil
            guard !applying else { return }
            onWillChange?(nil)
            if let attachment {
                let storage = preparedStorage
                storage.beginEditing()
                storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                    guard (value as? NativeChatTextAttachment) === attachment else { return }
                    // The attachment's metrics changed, even though its identity did not.
                    // Notify the backing store so TextKit updates both paragraph layout
                    // and the estimated document extent in the same editing transaction.
                    storage.edited(.editedAttributes, range: range, changeInLength: 0)
                }
                storage.endEditing()
            }
            view?.needsLayout = true; view?.invalidateIntrinsicContentSize()
        }
        func measuredHeight() -> CGFloat {
            guard let view, let container = view.textContainer,
                  let manager = view.textLayoutManager else { return max(1, fontSize * 1.5) }
            let width = view.frame.width
            guard width > 0 else { return max(1, fontSize * 1.5) }
            // The actual view width is the only width allowed to reflow this document.
            if abs(container.size.width - width) > 0.5 { container.size.width = width }
            if let cached = heightCache, cached.height > 1, abs(cached.width - width) < 0.5 { return cached.height }
            // TextKit owns viewport layout and may revise this extent. No document-end
            // probe is needed for ordinary sizing, scrolling, or a width change.
            let used = manager.usageBoundsForTextContainer.maxY
            // An unvisited SwiftUI-hosted body still needs a nonzero frame to enter
            // TextKit's viewport. This is a local estimate, replaced by actual layout.
            if manager.textViewportLayoutController.viewportRange == nil || used <= 1 {
                return max(fontSize * 1.5, ceil(CGFloat(estimatedCharacters) * fontSize * 0.75 / width
                    + CGFloat(estimatedParagraphs)) * fontSize * 1.6)
            }
            let measured = max(1, ceil(used + view.textContainerInset.height * 2))
            heightCache = (width, measured)
            return measured
        }
    }
}

final class NativeChatTextView: NSTextView {
    var onLayout: (() -> Void)?
    var onWidthChange: ((CGFloat) -> Void)?
    var onUserScroll: (() -> Void)?
    weak var conversationClipView: NSClipView?

    override var visibleRect: NSRect {
        guard let clip = conversationClipView else { return super.visibleRect }
        return super.visibleRect.intersection(convert(clip.bounds, from: clip))
    }

    override func setFrameSize(_ newSize: NSSize) {
        if abs(newSize.width - frame.width) > 0.5 { onWidthChange?(newSize.width) }
        super.setFrameSize(newSize)
    }

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // View-backed attachments can finalize their viewport extent during drawing.
        onLayout?()
    }

    override func scrollWheel(with event: NSEvent) {
        onUserScroll?()
        super.scrollWheel(with: event)
    }

    override func copy(_ sender: Any?) {
        _ = writeSelection(to: .general, type: .string)
    }
    override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .string else { return super.writeSelection(to: pasteboard, type: type) }
        guard let storage = textStorage else { return false }
        var parts: [String] = []
        for selection in selectedRanges {
            let range = selection.rangeValue
            let result = NSMutableString(string: "")
            storage.enumerateAttributes(in: range) { attributes, subrange, _ in
                if let attachment = attributes[.attachment] as? NativeChatTextAttachment { result.append(attachment.readableText) }
                else { result.append((storage.string as NSString).substring(with: subrange)) }
            }
            parts.append(result as String)
        }
        pasteboard.clearContents()
        return pasteboard.setString(parts.joined(separator: "\n"), forType: .string)
    }
}
