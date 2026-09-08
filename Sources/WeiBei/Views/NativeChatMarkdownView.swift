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
        coordinator.pipeline.invalidate()
        coordinator.view = nil
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        weak var view: NativeChatTextView?
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
        private var pendingAnchor: (location: any NSTextLocation, offset: CGFloat, width: CGFloat)?

        func willResize(to width: CGFloat) {
            guard let anchor = readingAnchor else { return }
            pendingAnchor = (anchor.location, anchor.offset, width)
        }

        func layoutDidChange() {
            guard !pendingLayoutUpdate else { return }
            pendingLayoutUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingLayoutUpdate = false
                guard !self.document.runs.isEmpty, let view = self.view, let container = view.textContainer,
                      let height = view.textLayoutManager?.usageBoundsForTextContainer.maxY else { return }
                if abs(height - self.lastLayoutHeight) > 0.5 {
                    self.lastLayoutHeight = height
                    self.heightCache = (container.size.width, max(1, ceil(height)))
                    view.invalidateIntrinsicContentSize()
                }
                // Restore only after SwiftUI has applied the new height. Earlier coordinates
                // still belong to the previous row frame and move the reader to another paragraph.
                guard abs(view.frame.height - ceil(height)) < 1 else { return }
                self.restoreReadingPosition()
                if self.pendingAnchor == nil { self.rememberReadingPosition() }
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
            guard let anchor = pendingAnchor, let view, abs(view.frame.width - anchor.width) < 0.5,
                  let scroll = view.enclosingScrollView, let manager = view.textLayoutManager else { return }
            manager.ensureLayout(for: NSTextRange(location: anchor.location))
            guard let fragment = manager.textLayoutFragment(for: anchor.location),
                  let line = fragment.textLineFragment(for: anchor.location, isUpstreamAffinity: false) else { return }
            let y = fragment.layoutFragmentFrame.minY + line.typographicBounds.minY
            let clip = scroll.contentView
            let target = view.convert(CGPoint(x: 0, y: y), to: clip).y - anchor.offset
            let rect = CGRect(x: clip.bounds.minX, y: target, width: clip.bounds.width, height: clip.bounds.height)
            let origin = clip.constrainBoundsRect(rect).origin
            if abs(origin.y - clip.bounds.minY) < 0.5 { pendingAnchor = nil; return }
            pendingAnchor = nil
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
            if url.scheme == "weibei-callout", let id = Int(url.absoluteString.dropFirst("weibei-callout:".count)), var input = snapshot {
                if input.toggledCallouts.contains(id) { input.toggledCallouts.remove(id) } else { input.toggledCallouts.insert(id) }
                snapshot = input; pipeline.submit(input)
            } else { onOpenURL(url) }
            return true
        }
        func makeAttachment(_ descriptor: NativeChatAttachmentDescriptor) -> NSTextAttachment {
            weak var changedAttachment: NativeChatTextAttachment?
            let attachment = NativeChatTextAttachment(descriptor: descriptor, fontSize: fontSize, isDark: isDark,
                onOpenURL: { [weak self] in self?.onOpenURL($0) },
                onSizeChange: { [weak self] in self?.attachmentSizeChanged(changedAttachment) }, visualizationView: visualizationView, imageLoader: imageLoader, interfaceLanguage: interfaceLanguage)
            changedAttachment = attachment
            return attachment
        }
        func attributed(_ runs: [NativeChatMarkdownRun]) -> NSAttributedString {
            NativeChatMarkdownAttributed.make(runs: runs, fontSize: fontSize, isDark: isDark, attachment: makeAttachment)
        }
        func apply(_ document: NativeChatMarkdownDocument, edit: NativeChatMarkdownEdit) {
            guard let view, let storage = view.textStorage else { return }
            self.document = document
            heightCache = nil
            guard edit.range.length > 0 || !edit.replacement.isEmpty else { return }
            readingAnchor = nil; pendingAnchor = nil
            applying = true
            defer { applying = false; heightCache = nil }
            let selected = view.selectedRanges.map(\.rangeValue).map(edit.mapSelection)
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
            view.selectedRanges = selected.map { NSValue(range: NSRange(location: min($0.location, storage.length), length: min($0.length, max(0, storage.length - $0.location)))) }
            view.invalidateIntrinsicContentSize()
        }
        func restyle() {
            heightCache = nil
            guard let storage = view?.textStorage, storage.length > 0 else { return }
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
            guard let manager = view?.textLayoutManager, let content = manager.textContentManager else { return }
            if let attachment, let storage = view?.textStorage {
                storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                    guard (value as? NativeChatTextAttachment) === attachment,
                          let start = content.location(content.documentRange.location, offsetBy: range.location),
                          let end = content.location(start, offsetBy: range.length),
                          let textRange = NSTextRange(location: start, end: end) else { return }
                    manager.invalidateLayout(for: textRange)
                }
            }
            view?.needsLayout = true; view?.invalidateIntrinsicContentSize()
        }
        func measuredHeight() -> CGFloat {
            guard let view, let container = view.textContainer,
                  let manager = view.textLayoutManager, let content = manager.textContentManager else { return max(1, fontSize * 1.5) }
            let width = view.frame.width
            guard width > 0 else { return max(1, fontSize * 1.5) }
            // The actual view width is the only width allowed to reflow this document.
            if abs(container.size.width - width) > 0.5 { container.size.width = width }
            if let cached = heightCache, abs(cached.width - width) < 0.5 { return cached.height }
            if let anchor = pendingAnchor { manager.ensureLayout(for: NSTextRange(location: anchor.location)) }
            // Lay out the end paragraph for an extent estimate; the native viewport lays out
            // what is actually visible. Measuring every offscreen paragraph stalls each resize.
            manager.ensureLayout(for: NSTextRange(location: content.documentRange.endLocation))
            var height: CGFloat = 0
            manager.enumerateTextLayoutFragments(from: content.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
                height = fragment.layoutFragmentFrame.maxY; return false
            }
            let measured = max(1, ceil(max(height, manager.usageBoundsForTextContainer.maxY) + view.textContainerInset.height * 2))
            heightCache = (width, measured)
            return measured
        }
    }
}

final class NativeChatTextView: NSTextView {
    var onLayout: (() -> Void)?
    var onWidthChange: ((CGFloat) -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        if abs(newSize.width - frame.width) > 0.5 { onWidthChange?(newSize.width) }
        super.setFrameSize(newSize)
    }

    override func layout() {
        super.layout()
        onLayout?()
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
