import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var command: NoteEditorCommand?
    var isFocused = false
    var focusRequest = 0
    var markdownBaseURL: URL?
    var attachmentDirectory: URL?
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var onSelectionChange: (String, CGPoint?) -> Void
    var onWikiLink: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            command: $command,
            isFocused: isFocused,
            focusRequest: focusRequest,
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory,
            appearanceMode: appearanceMode,
            onSelectionChange: onSelectionChange,
            onWikiLink: onWikiLink
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        WeiBeiQuietScrollers.configure(scrollView, hasHorizontalScroller: false)
        scrollView.drawsBackground = false

        let textView = MarkdownSourceTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.string = text
        applyTheme(to: textView)
        textView.delegate = context.coordinator
        textView.openWikiLinkAtCursor = { [weak coordinator = context.coordinator, weak textView] in
            guard let textView else { return false }
            return coordinator?.openWikiLink(in: textView) ?? false
        }
        textView.hasImagesInPasteboard = { [weak coordinator = context.coordinator] pasteboard in
            coordinator?.hasImages(in: pasteboard) ?? false
        }
        textView.insertImagesFromPasteboard = { [weak coordinator = context.coordinator, weak textView] pasteboard in
            guard let textView else { return false }
            return coordinator?.insertImages(from: pasteboard, in: textView) ?? false
        }
        textView.registerForDraggedTypes([.fileURL, .png, .tiff])
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.command = $command
        context.coordinator.markdownBaseURLString = markdownBaseURL?.absoluteString ?? ""
        context.coordinator.attachmentDirectory = attachmentDirectory
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onWikiLink = onWikiLink
        context.coordinator.isFocused = isFocused
        context.coordinator.focusRequest = focusRequest
        context.coordinator.appearanceMode = appearanceMode
        if textView.string != text {
            textView.string = text
        }
        applyTheme(to: textView)
        context.coordinator.applyFocus(in: textView)
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.run(command, in: textView)
            DispatchQueue.main.async {
                self.command = nil
            }
        }
    }

    private func applyTheme(to textView: NSTextView) {
        let baseFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.font = baseFont
        textView.textColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.insertionPointColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.selectedTextAttributes = [
            .backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode),
            .foregroundColor: WeiBeiNativePalette.selectedText(for: appearanceMode)
        ]
        Self.applySourcePresentation(in: textView, appearanceMode: appearanceMode, baseFont: baseFont)
    }

    private static func applySourcePresentation(
        in textView: NSTextView,
        appearanceMode: WeiBeiAppearanceMode,
        baseFont: NSFont
    ) {
        guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let ink = WeiBeiNativePalette.ink(for: appearanceMode)
        let quotePrefixColor = ink.withAlphaComponent(appearanceMode == .inkstone ? 0.30 : 0.36)
        let markerColor = NSColor.clear
        let markerFont = NSFont.monospacedSystemFont(ofSize: 0.1, weight: .regular)
        let quotePrefixRegex = try? NSRegularExpression(pattern: #"(?m)^\s*(?:>\s*)+"#)
        let calloutControlRegex = try? NSRegularExpression(
            pattern: #"(?m)^(\s*(?:>\s*)*)(\\?\[![A-Za-z][A-Za-z0-9_-]*\][+-]?\s*)"#
        )

        textView.undoManager?.disableUndoRegistration()
        textStorage.beginEditing()
        textStorage.addAttributes([
            .font: baseFont,
            .foregroundColor: ink
        ], range: fullRange)

        quotePrefixRegex?.enumerateMatches(in: textView.string, range: fullRange) { match, _, _ in
            guard let range = match?.range, range.location != NSNotFound else { return }
            textStorage.addAttributes([
                .foregroundColor: quotePrefixColor
            ], range: range)
        }

        calloutControlRegex?.enumerateMatches(in: textView.string, range: fullRange) { match, _, _ in
            guard let markerRange = match?.range(at: 2), markerRange.location != NSNotFound else { return }
            textStorage.addAttributes([
                .font: markerFont,
                .foregroundColor: markerColor,
                .baselineOffset: 0
            ], range: markerRange)
        }
        textStorage.endEditing()
        textView.undoManager?.enableUndoRegistration()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var command: Binding<NoteEditorCommand?>
        var isFocused: Bool
        var focusRequest: Int
        var markdownBaseURLString: String
        var attachmentDirectory: URL?
        var onSelectionChange: (String, CGPoint?) -> Void
        var onWikiLink: (String) -> Void
        var appearanceMode: WeiBeiAppearanceMode
        var lastCommandID: UUID?
        private var lastAppliedFocusRequest = -1

        init(
            text: Binding<String>,
            command: Binding<NoteEditorCommand?>,
            isFocused: Bool,
            focusRequest: Int,
            markdownBaseURLString: String,
            attachmentDirectory: URL?,
            appearanceMode: WeiBeiAppearanceMode,
            onSelectionChange: @escaping (String, CGPoint?) -> Void,
            onWikiLink: @escaping (String) -> Void
        ) {
            self.text = text
            self.command = command
            self.isFocused = isFocused
            self.focusRequest = focusRequest
            self.markdownBaseURLString = markdownBaseURLString
            self.attachmentDirectory = attachmentDirectory
            self.onSelectionChange = onSelectionChange
            self.onWikiLink = onWikiLink
            self.appearanceMode = appearanceMode
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            MarkdownSourceEditor.applySourcePresentation(
                in: textView,
                appearanceMode: appearanceMode,
                baseFont: .monospacedSystemFont(ofSize: 15, weight: .regular)
            )
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let stringRange = Range(range, in: textView.string) else {
                onSelectionChange("", nil)
                return
            }
            onSelectionChange(String(textView.string[stringRange]), Self.anchor(for: range, in: textView))
        }

        func run(_ command: NoteEditorCommand, in textView: NSTextView) {
            switch command.kind {
            case .replaceSelection:
                replaceSelection(with: command.markdown, in: textView)
            case .applyAgentPatch:
                applyPatch(command.markdown, in: textView)
            case .insertMarkdown:
                insertMarkdown(command.markdown, in: textView)
            case .scrollToHeading:
                scrollToHeading(command.markdown, in: textView)
            }
        }

        private func scrollToHeading(_ rawIndex: String, in textView: NSTextView) {
            guard let targetIndex = Int(rawIndex), targetIndex >= 0 else { return }
            let pattern = #"(?m)^#{1,4}[\t ]+.+$"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            let matches = regex.matches(in: textView.string, range: fullRange)
            guard matches.indices.contains(targetIndex) else { return }
            textView.scrollRangeToVisible(matches[targetIndex].range)
        }

        private func replaceSelection(with markdown: String, in textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0 else {
                applyPatch(markdown, in: textView)
                return
            }
            insertMarkdown(markdown, in: textView)
        }

        private func insertMarkdown(_ markdown: String, in textView: NSTextView) {
            let range = textView.selectedRange()
            textView.textStorage?.replaceCharacters(in: range, with: markdown)
            let cursor = range.location + (markdown as NSString).length
            textView.setSelectedRange(NSRange(location: cursor, length: 0))
            text.wrappedValue = textView.string
            refreshSourcePresentation(in: textView)
        }

        private func applyPatch(_ markdown: String, in textView: NSTextView) {
            let next = "\(textView.string.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(markdown.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            textView.string = next
            text.wrappedValue = next
            textView.setSelectedRange(NSRange(location: (next as NSString).length, length: 0))
            refreshSourcePresentation(in: textView)
        }

        func applyFocus(in textView: NSTextView) {
            guard isFocused, focusRequest != lastAppliedFocusRequest else { return }
            lastAppliedFocusRequest = focusRequest
            textView.window?.makeFirstResponder(textView)
        }

        func openWikiLink(in textView: NSTextView) -> Bool {
            guard let title = WikiLink.enclosingTitle(in: textView.string, cursor: textView.selectedRange().location) else {
                return false
            }
            onWikiLink(title)
            return true
        }

        func insertImages(from pasteboard: NSPasteboard, in textView: NSTextView) -> Bool {
            let attachments = imageAttachments(from: pasteboard)
            guard !attachments.isEmpty else { return false }
            let markdown = attachments.map { MarkdownAttachmentStore.markdownImage(for: $0) }.joined(separator: "\n\n")
            insertBlockMarkdown(markdown, in: textView)
            return true
        }

        func hasImages(in pasteboard: NSPasteboard) -> Bool {
            imageFileURLs(from: pasteboard).isEmpty == false || NSImage(pasteboard: pasteboard) != nil
        }

        private func imageAttachments(from pasteboard: NSPasteboard) -> [MarkdownAttachment] {
            let urls = imageFileURLs(from: pasteboard)
            if !urls.isEmpty {
                let attachments = urls.compactMap(saveImageFile)
                if !attachments.isEmpty { return attachments }
            }

            guard let image = NSImage(pasteboard: pasteboard),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                return []
            }

            return [saveImageData(data, originalName: "pasted-image.png", mime: "image/png")].compactMap(\.self)
        }

        private func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? [])
                .compactMap { object in
                    if let url = object as? URL { return url }
                    if let url = object as? NSURL { return url as URL }
                    return nil
                }
                .filter { MarkdownAttachmentStore.isSupportedImageExtension($0.pathExtension) }
        }

        private func saveImageFile(_ url: URL) -> MarkdownAttachment? {
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return saveImageData(
                data,
                originalName: url.lastPathComponent,
                mime: MarkdownAttachmentStore.mimeType(forFileExtension: url.pathExtension)
            )
        }

        private func saveImageData(_ data: Data, originalName: String, mime: String) -> MarkdownAttachment? {
            guard let attachmentDirectory else { return nil }
            return try? MarkdownAttachmentStore.save(
                data: data,
                originalName: originalName,
                mime: mime,
                attachmentDirectory: attachmentDirectory,
                markdownBaseURLString: markdownBaseURLString
            )
        }

        private func insertBlockMarkdown(_ markdown: String, in textView: NSTextView) {
            let result = MarkdownBlockInsertion.insert(markdown, into: textView.string, replacing: textView.selectedRange())
            textView.string = result.text
            textView.setSelectedRange(NSRange(location: result.cursor, length: 0))
            text.wrappedValue = result.text
            refreshSourcePresentation(in: textView)
        }

        private func refreshSourcePresentation(in textView: NSTextView) {
            MarkdownSourceEditor.applySourcePresentation(
                in: textView,
                appearanceMode: appearanceMode,
                baseFont: .monospacedSystemFont(ofSize: 15, weight: .regular)
            )
        }

        private static func anchor(for range: NSRange, in textView: NSTextView) -> CGPoint? {
            guard let window = textView.window else { return nil }
            let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard !rect.isEmpty else { return nil }
            let screenPoint = CGPoint(x: rect.midX, y: rect.minY)
            return SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)
        }
    }
}

struct MarkdownPreviewView: View {
    var markdown: String
    var markdownBaseURL: URL?
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    var compact = false
    var fitsContentHeight = true
    /// When true, lock height after the first stable measure so chat LazyVStack
    /// does not thrash on ResizeObserver jitter (hang-proof for agent turns).
    var freezeHeightAfterMeasure = false
    /// Seed from a session cache so recycled rows do not collapse then grow.
    var seedContentHeight: CGFloat? = nil
    /// When this changes (window / panel width bucket), unfreeze and remeasure.
    var layoutWidthBucket: Int = 0
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onSelectionChange: (String, CGPoint?) -> Void = { _, _ in }
    var onContentHeightChange: () -> Void = {}
    private static let compactPreviewLoadingHeight: CGFloat = 44
    private static let compactPreviewMaximumHeight: CGFloat = 20_000

    var onMeasuredHeight: (CGFloat) -> Void = { _ in }
    @State private var command: NoteEditorCommand?
    @State private var contentHeight: CGFloat = Self.compactPreviewLoadingHeight
    @State private var heightFrozen = false
    @State private var lastWidthBucket = 0

    var body: some View {
        RichMarkdownEditorView(
            markdown: .constant(markdown),
            command: $command,
            isEditable: false,
            markdownBaseURL: markdownBaseURL,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage,
            isCompactPreview: compact,
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onSelectionChange,
            onContentHeightChange: { height in
                guard compact && fitsContentHeight else { return }
                guard height.isFinite,
                      height > 0,
                      height <= Self.compactPreviewMaximumHeight else { return }
                if freezeHeightAfterMeasure, heightFrozen { return }
                let next = max(ceil(height), Self.compactPreviewLoadingHeight)
                // Ignore sub-pixel ResizeObserver jitter once we have a real measure.
                if contentHeight >= Self.compactPreviewLoadingHeight,
                   abs(contentHeight - next) < 2 {
                    if freezeHeightAfterMeasure { heightFrozen = true }
                    return
                }
                contentHeight = next
                onMeasuredHeight(next)
                if freezeHeightAfterMeasure, next > Self.compactPreviewLoadingHeight {
                    heightFrozen = true
                }
                onContentHeightChange()
            },
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut
        )
        .background(compact ? Color.clear : WeiBeiTheme.paper)
        .frame(height: compact && fitsContentHeight ? max(contentHeight, Self.compactPreviewLoadingHeight) : nil)
        .onAppear {
            lastWidthBucket = layoutWidthBucket
            if let seed = seedContentHeight, seed > Self.compactPreviewLoadingHeight {
                contentHeight = seed
                if freezeHeightAfterMeasure {
                    heightFrozen = true
                }
            }
        }
        .onChange(of: layoutWidthBucket) { _, bucket in
            guard bucket != lastWidthBucket else { return }
            lastWidthBucket = bucket
            // Window / selection-float resize: allow a fresh measure for the new width.
            heightFrozen = false
            if let seed = seedContentHeight, seed > Self.compactPreviewLoadingHeight {
                contentHeight = seed
            }
        }
        .onChange(of: markdown) { _, _ in
            guard compact && fitsContentHeight else { return }
            heightFrozen = false
            contentHeight = Self.compactPreviewLoadingHeight
            onContentHeightChange()
        }
    }
}

