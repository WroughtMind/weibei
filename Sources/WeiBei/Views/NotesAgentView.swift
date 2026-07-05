import AppKit
import SwiftUI
import WeiBeiCore

struct NotesAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            NotePaneView()
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.50))
                .frame(height: 1)
            AgentPaneView()
        }
        .weibeiPanel()
    }
}

private extension View {
    func weibeiPaneHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View {
        self
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.72, materialOpacity: 0.12))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(WeiBeiTheme.glassHighlight.opacity(0.06))
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                WeiBeiHeaderHandoffFade(height: 28, opacity: 0.34)
                    .offset(y: 28)
            }
            .shadow(color: WeiBeiTheme.ink.opacity(0.012), radius: 7, y: 2)
            .zIndex(1)
            .animation(WeiBeiMotion.appearance, value: appearanceMode)
    }

    func weibeiFloatingHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View {
        self
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.60, materialOpacity: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) {
                WeiBeiHeaderHandoffFade(height: 10, opacity: 0.22)
                    .offset(y: 10)
            }
            .animation(WeiBeiMotion.appearance, value: appearanceMode)
    }

    func weibeiHeaderAccessoryGroup() -> some View {
        self
            .padding(3)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .opacity(0.05)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(WeiBeiTheme.paperInset.opacity(0.22))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.glassHighlight.opacity(0.18), lineWidth: 1)
                    .padding(0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(0.62), lineWidth: 1)
            }
    }
}

private struct WeiBeiPaneHeader<Actions: View>: View {
    var title: String
    var subtitle: String
    var appearanceMode: WeiBeiAppearanceMode
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(titleUsesEnglishBrand ? WeiBeiTypography.englishBrandFont(size: 18, weight: .semibold) : .system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions()
        }
        .weibeiPaneHeaderChrome(appearanceMode: appearanceMode)
    }

    private var titleUsesEnglishBrand: Bool {
        title.unicodeScalars.allSatisfy(\.isASCII)
    }
}

struct NotePaneView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            WeiBeiPaneHeader(title: store.ui("笔记", "Notes"), subtitle: noteHeaderSubtitle, appearanceMode: store.appearanceMode) {
                noteModeControl
                if !isImmersiveWriting {
                    Button { store.resetNote() } label: {
                        Image(systemName: "doc.badge.plus")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(size: 24))
                    .accessibilityLabel(Text(store.ui("新建独立 Markdown 笔记", "Create standalone Markdown note")))
                    .help(store.ui("新建独立 Markdown 笔记", "Create standalone Markdown note"))
                    if store.canUseSelectedMarkdownAsNotebookNote {
                        Button {
                            store.useSelectedMarkdownAsNotebookNote()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .buttonStyle(WeiBeiIconButtonStyle(size: 24))
                        .accessibilityLabel(Text(store.ui("作为笔记编辑", "Edit as note")))
                        .help(store.ui("把当前 Markdown 文件移到笔记区原地编辑", "Move the current Markdown file into the note editor"))
                    }
                }
            }

            if let noteFileError = store.noteFileError {
                Text(noteFileError)
                    .font(.caption)
                    .foregroundStyle(noteFileStatusColor(for: noteFileError))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            noteBody
        }
        .frame(minHeight: 280)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(WeiBeiTheme.paper)
    }

    private var noteModeControl: some View {
        HStack(spacing: 2) {
            ForEach(NoteRenderMode.allCases) { mode in
                let selected = store.noteRenderMode == mode
                Button {
                    withAnimation(WeiBeiMotion.layout) {
                        store.setNoteRenderMode(mode)
                    }
                } label: {
                    Text(mode.label(language: store.interfaceLanguage))
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                        .frame(width: 38, height: 24)
                        .background(selected ? WeiBeiTheme.cinnabarSoft.opacity(0.86) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .animation(WeiBeiMotion.micro, value: selected)
                }
                .buttonStyle(.plain)
            }
        }
        .weibeiHeaderAccessoryGroup()
    }

    private var noteHeaderSubtitle: String {
        store.selectedItem?.isNotebookNote == true
            ? (store.selectedItem.map(store.displayTitle) ?? store.ui("当前笔记", "Current note"))
            : store.agentNoteTitle
    }

    private func noteFileStatusColor(for message: String) -> Color {
        message.hasPrefix("无法") || message.hasPrefix("Could not") ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk
    }

    private var isImmersiveWriting: Bool {
        store.layout == .immersiveWriting
    }

    @ViewBuilder
    private var noteBody: some View {
        Group {
            switch store.noteRenderMode {
            case .rich:
                richEditor
            case .split:
                HSplitView {
                    noteEditor
                        .frame(minWidth: 220)
                    MarkdownPreviewView(
                        markdown: store.noteText,
                        markdownBaseURL: store.currentMarkdownBaseURL,
                        appearanceMode: store.appearanceMode,
                        interfaceLanguage: store.interfaceLanguage,
                        onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
                        onSourceReference: { reference in store.openSourceReference(reference) },
                        onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) }
                    ) { text, anchor in
                        store.updateSelection(text, source: .note, anchor: anchor, isEditable: false)
                    }
                        .frame(minWidth: 220)
                }
            case .source:
                noteEditor
            case .preview:
                MarkdownPreviewView(
                    markdown: store.noteText,
                    markdownBaseURL: store.currentMarkdownBaseURL,
                    appearanceMode: store.appearanceMode,
                    interfaceLanguage: store.interfaceLanguage,
                    onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
                    onSourceReference: { reference in store.openSourceReference(reference) },
                    onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) }
                ) { text, anchor in
                    store.updateSelection(text, source: .note, anchor: anchor, isEditable: false)
                }
            }
        }
        .transition(WeiBeiTransition.layout)
        .animation(WeiBeiMotion.layout, value: store.noteRenderMode)
        .overlay(alignment: .topLeading) {
            if noteIsEmpty {
                emptyNoteHint
                    .transition(WeiBeiTransition.message)
            }
        }
    }

    private var richEditor: some View {
        let itemID = store.selectedItemID
        return RichMarkdownEditorView(documentID: itemID ?? "", markdown: Binding(get: {
            store.noteText
        }, set: { value in
            store.updateNote(value, for: itemID)
        }), command: Binding(get: {
            store.noteEditorCommand
        }, set: { value in
            store.noteEditorCommand = value
        }),
        isEditable: true,
        isFocused: store.focusedPane == .notes,
        focusRequest: store.focusRequest,
        markdownBaseURL: store.currentMarkdownBaseURL,
        attachmentDirectory: store.currentAttachmentDirectory,
        appearanceMode: store.appearanceMode,
        interfaceLanguage: store.interfaceLanguage,
        onSelectionChange: { text, anchor in
            store.updateSelection(text, source: .note, anchor: anchor)
        }, onAskAgentWithSelection: { text, anchor in
            store.updateSelection(text, source: .note, anchor: anchor)
            store.askSelection()
        }, onWikiLink: { title in
            store.openOrCreateWikiNote(title: title)
        }, onSourceReference: { reference in
            store.openSourceReference(reference)
        }, onAppShortcut: { key, modifiers in
            store.handleAppShortcut(key: key, modifiers: modifiers)
        })
        .background(WeiBeiTheme.paper)
    }

    private var noteEditor: some View {
        MarkdownSourceEditor(text: Binding(get: {
            store.noteText
        }, set: { value in
            store.updateNote(value)
        }), command: Binding(get: {
            store.noteEditorCommand
        }, set: { value in
            store.noteEditorCommand = value
        }),
        isFocused: store.focusedPane == .notes,
        focusRequest: store.focusRequest,
        markdownBaseURL: store.currentMarkdownBaseURL,
        attachmentDirectory: store.currentAttachmentDirectory,
        appearanceMode: store.appearanceMode,
        onSelectionChange: { text, anchor in
            store.updateSelection(text, source: .note, anchor: anchor)
        }, onWikiLink: { title in
            store.openOrCreateWikiNote(title: title)
        })
        .background(WeiBeiTheme.paper)
    }

    private var noteIsEmpty: Bool {
        store.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyNoteHint: some View {
        Text(emptyNoteHintText)
            .font(.system(size: 13, weight: .medium, design: .serif))
            .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.72))
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .allowsHitTesting(false)
    }

    private var emptyNoteHintText: String {
        store.hasSelectedMaterial ? store.ui("开始记录当前材料", "Start taking notes on this material") : store.ui("开始记录当前笔记", "Start writing this note")
    }
}

final class MarkdownSourceTextView: NSTextView {
    var openWikiLinkAtCursor: (() -> Bool)?
    var hasImagesInPasteboard: ((NSPasteboard) -> Bool)?
    var insertImagesFromPasteboard: ((NSPasteboard) -> Bool)?

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        Array(Set(super.readablePasteboardTypes + [.tiff, .png, .fileURL]))
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "\r",
           openWikiLinkAtCursor?() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func paste(_ sender: Any?) {
        if insertImagesFromPasteboard?(NSPasteboard.general) == true {
            return
        }
        super.paste(sender)
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if insertImagesFromPasteboard?(pasteboard) == true {
            return true
        }
        return super.readSelection(from: pasteboard, type: type)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasImagesInPasteboard?(sender.draggingPasteboard) == true ? .copy : super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        insertImagesFromPasteboard?(sender.draggingPasteboard) == true || super.performDragOperation(sender)
    }
}

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
            }
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
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onSelectionChange: (String, CGPoint?) -> Void = { _, _ in }
    @State private var command: NoteEditorCommand?

    var body: some View {
        RichMarkdownEditorView(
            markdown: .constant(markdown),
            command: $command,
            isEditable: false,
            markdownBaseURL: markdownBaseURL,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage,
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onSelectionChange,
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut
        )
        .background(WeiBeiTheme.paper)
    }
}

struct AgentPaneView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            WeiBeiPaneHeader(title: store.ui("对话", "Chat"), subtitle: store.selectedItem.map(store.displayTitle) ?? store.ui("无上下文", "No context"), appearanceMode: store.appearanceMode) {
                if hasAgentHeaderActions {
                    HStack(spacing: 2) {
                        if !store.messages.isEmpty {
                            agentToolButton(store.ui("整理", "Organize"), help: store.ui("整理笔记", "Organize note"), systemImage: "list.bullet.rectangle") {
                                store.askToOrganizeNote()
                            }
                        }

                        if store.canApplyAgentAnswer {
                            agentToolButton(store.ui("写入回答", "Write Answer"), help: store.ui("写入回答到笔记", "Write answer to note"), systemImage: "square.and.arrow.down") {
                                store.applyLastAgentAnswerToNote()
                            }
                        }

                        if store.canReplaceNoteSelection {
                            agentToolButton(store.ui("替换", "Replace"), help: store.ui("替换笔记选区", "Replace note selection"), systemImage: "arrow.left.arrow.right") {
                                store.replaceSelectionWithLastAgentAnswer()
                            }
                        }
                    }
                    .weibeiHeaderAccessoryGroup()
                    .transition(WeiBeiTransition.floating)
                }
            }

            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(store.messages) { message in
                                AgentBubble(message: message)
                                    .id(message.id)
                                    .transition(WeiBeiTransition.message)
                            }
                            if store.isAskingAgent {
                                AgentThinkingIndicator()
                                    .id("agent-thinking")
                                    .transition(WeiBeiTransition.message)
                            }
                            if store.messages.isEmpty {
                                emptyAgentState
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(WeiBeiTransition.message)
                            }
                        }
                        .padding(14)
                        .padding(.top, store.messages.isEmpty ? 22 : 0)
                        .frame(
                            minHeight: geometry.size.height,
                            alignment: .topLeading
                        )
                        .animation(WeiBeiMotion.panel, value: store.messages.count)
                    }
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            agentInputTray
        }
        .frame(minHeight: 260)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(WeiBeiTheme.paper)
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [
                    WeiBeiTheme.glassHighlight.opacity(0.18),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 10)
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
        }
    }

    private var canSendDraft: Bool {
        !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAgentHeaderActions: Bool {
        !store.messages.isEmpty || store.canApplyAgentAnswer || store.canReplaceNoteSelection
    }

    private var agentPrompt: String {
        store.agentInputPrompt
    }

    private var agentInputTray: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .clear,
                    WeiBeiTheme.paper.opacity(0.34),
                    WeiBeiTheme.glassTint.opacity(0.66)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                if store.hasSelectionAttachments {
                    AgentSelectionAttachmentPill()
                        .transition(WeiBeiTransition.floating)
                }

                ZStack(alignment: .bottomTrailing) {
                    TextField(
                        "",
                        text: $store.agentDraft,
                        prompt: Text(agentPrompt)
                            .font(.system(size: 15))
                            .foregroundStyle(WeiBeiTheme.placeholderInk),
                        axis: .vertical
                    )
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(WeiBeiTheme.ink)
                        .focused($draftFocused)
                        .onSubmit {
                            Task { await store.askAgent() }
                        }
                        .padding(.vertical, 10)
                        .padding(.trailing, canSendDraft ? 40 : 0)
                        .frame(maxWidth: .infinity, alignment: .bottomLeading)
                        .weibeiInputSurface(active: draftFocused, height: 56, horizontalPadding: 14)

                    if canSendDraft {
                        Button { Task { await store.askAgent() } } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .buttonStyle(WeiBeiIconButtonStyle(size: 30, prominence: .primary))
                        .accessibilityLabel(Text(store.ui("发送", "Send")))
                        .help(store.ui("发送", "Send"))
                        .keyboardShortcut(.return, modifiers: [.command])
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                        .transition(WeiBeiTransition.floating)
                        .animation(WeiBeiMotion.micro, value: canSendDraft)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    draftFocused = true
                }
            }
            .font(.system(size: 15))
            .frame(minHeight: 56, alignment: .bottom)
            .frame(maxWidth: agentInputMaxWidth)
            .padding(.horizontal, 18)
            .padding(.top, 7)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .animation(WeiBeiMotion.reveal, value: store.agentDraft)
        }
        .background(alignment: .bottom) {
            WeiBeiGlassHeaderBackground(
                paperOpacity: store.layout == .immersiveConversation ? 0.50 : 0.56,
                materialOpacity: store.layout == .immersiveConversation ? 0.06 : 0.05
            )
            .mask(
                LinearGradient(
                    colors: [.clear, WeiBeiTheme.ink.opacity(0.72), WeiBeiTheme.ink],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var agentInputMaxWidth: CGFloat? {
        store.layout == .immersiveConversation ? 680 : nil
    }

    private var emptyAgentState: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: starterChipColumns, alignment: .leading, spacing: 6) {
                if store.hasSelectedMaterial {
                    starterChip(store.ui("梳理", "Outline"), systemImage: "text.alignleft", help: store.ui("梳理当前材料", "Outline current material")) {
                        askWith(store.ui("请基于当前材料提炼核心概念、关键公式和需要回看出处的位置。", "Extract the core concepts, key formulas, and places that need source review from the current material."))
                    }
                }
                starterChip(store.ui("整理", "Organize"), systemImage: "list.bullet.rectangle", help: store.ui("整理当前笔记", "Organize current note")) {
                    store.askToOrganizeNote()
                }
                if store.hasSelectedMaterial {
                    starterChip(store.ui("出题", "Quiz"), systemImage: "questionmark.square", help: store.ui("生成复习题", "Generate review questions")) {
                        askWith(store.ui("请根据当前材料和笔记生成 5 个复习问题，并标出每题依据。", "Generate 5 review questions from the current material and note, and cite the evidence for each question."))
                    }
                }
            }
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    private func starterChip(_ title: String, systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        AgentStarterChip(title: title, systemImage: systemImage, help: help, action: action)
    }

    private var starterChipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 56), spacing: 6, alignment: .leading)]
    }

    private func askWith(_ prompt: String) {
        withAnimation(WeiBeiMotion.panel) {
            store.agentDraft = prompt
        }
        Task { await store.askAgent() }
    }

    private func agentToolButton(_ title: String, help: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 24))
        .accessibilityLabel(Text(help))
        .help(help)
    }
}

private struct AgentStarterChip: View {
    var title: String
    var systemImage: String
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11.5, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
        .background(WeiBeiTheme.paperInset.opacity(hovering ? 0.18 : 0.0))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(hovering ? WeiBeiTheme.hairline.opacity(0.56) : WeiBeiTheme.hairline.opacity(0.0), lineWidth: 1)
        }
        .offset(y: hovering ? -1 : 0)
        .accessibilityLabel(Text(help))
        .help(help)
        .onHover { value in
            withAnimation(WeiBeiMotion.hover) {
                hovering = value
            }
        }
    }
}

private struct AgentSelectionAttachmentPill: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var pillHovering = false
    @State private var popoverHovering = false
    @State private var closeToken = UUID()

    var body: some View {
        if store.hasSelectionAttachments {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .medium))
                Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(pillHovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(WeiBeiTheme.paperRaised.opacity(pillHovering ? 0.72 : 0.54))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(pillHovering ? 0.68 : 0.38), lineWidth: 1)
            }
            .popover(isPresented: popoverPresented, arrowEdge: .bottom) { popoverContent }
            .onHover { value in
                setPillHovering(value)
            }
            .accessibilityLabel(Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments")))
            .help(store.ui("悬停查看选区", "Hover to preview selections"))
        }
    }

    private var popoverPresented: Binding<Bool> {
        Binding(
            get: { pillHovering || popoverHovering },
            set: { presented in
                if !presented {
                    pillHovering = false
                    popoverHovering = false
                }
            }
        )
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer()
                Text(store.ui("发问时会作为上下文", "Used as context when asking"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(store.selectionAttachments.enumerated()), id: \.element.id) { index, selection in
                        selectionAttachmentRow(index: index, selection: selection)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(WeiBeiTheme.paperRaised)
        .onHover { value in
            setPopoverHovering(value)
        }
    }

    private func selectionAttachmentRow(index: Int, selection: SelectionContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(store.ui("片段 \(index + 1)", "Fragment \(index + 1)"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(selection.ownerTitle)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Spacer(minLength: 8)
                Button {
                    let shouldClose = store.selectionAttachments.count == 1
                    store.removeSelectionAttachment(id: selection.id)
                    if shouldClose {
                        pillHovering = false
                        popoverHovering = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .accessibilityLabel(Text(store.ui("移除片段 \(index + 1)", "Remove fragment \(index + 1)")))
                .help(store.ui("移除这个选区片段", "Remove this selected fragment"))
            }

            Text(selection.text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .lineLimit(5)
                .foregroundStyle(WeiBeiTheme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 1)
        }
        .padding(9)
        .background(WeiBeiTheme.paperInset.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(0.36), lineWidth: 1)
        }
    }

    private func setPillHovering(_ value: Bool) {
        if value {
            closeToken = UUID()
            withAnimation(WeiBeiMotion.hover) {
                pillHovering = true
            }
        } else {
            schedulePopoverClose()
        }
    }

    private func setPopoverHovering(_ value: Bool) {
        if value {
            closeToken = UUID()
            popoverHovering = true
        } else {
            popoverHovering = false
            schedulePopoverClose()
        }
    }

    private func schedulePopoverClose() {
        let token = UUID()
        closeToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard closeToken == token, !popoverHovering else { return }
            withAnimation(WeiBeiMotion.hover) {
                pillHovering = false
                popoverHovering = false
            }
        }
    }
}

struct AgentDrawerView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.ui("对话", "Chat"))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 14, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer()
                Text("⌘↩")
                    .font(.caption.monospaced())
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .weibeiFloatingHeaderChrome(appearanceMode: store.appearanceMode)

            if store.hasSelectionAttachments {
                AgentSelectionAttachmentPill()
                    .transition(WeiBeiTransition.floating)
            }

            ZStack(alignment: .bottomTrailing) {
                TextField(
                    "",
                    text: $store.agentDraft,
                    prompt: Text(drawerPrompt)
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.placeholderInk),
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($draftFocused)
                    .foregroundColor(WeiBeiTheme.ink)
                    .onSubmit {
                        Task { await store.askAgent() }
                    }
                .font(.system(size: 13))
                .padding(.trailing, canSend ? 44 : 0)
                .weibeiInputSurface(active: draftFocused, height: 46)
                if canSend {
                    Button { Task { await store.askAgent() } } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(size: 34, prominence: .primary))
                    .accessibilityLabel(Text(store.ui("发送", "Send")))
                    .help(store.ui("发送", "Send"))
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                    .transition(WeiBeiTransition.floating)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                draftFocused = true
            }
            .animation(WeiBeiMotion.micro, value: canSend)

            HStack(spacing: 8) {
                Label(store.hasSelectedMaterial ? store.ui("来源", "Source") : store.ui("笔记", "Note"), systemImage: store.hasSelectedMaterial ? "link" : "square.and.pencil")
                Text(store.selectedMaterialItem.map(store.displayTitle) ?? store.ui("当前笔记", "Current note"))
                    .lineLimit(1)
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
        .padding(14)
        .frame(width: 440)
        .weibeiFloatingPanel(shadowOpacity: 0.12)
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
        }
    }

    private var canSend: Bool {
        !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var drawerPrompt: String {
        store.agentInputPrompt
    }
}

struct CornerAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(store.ui("对话", "Chat"))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 15, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer()
                Button { store.setAgentSurface(.hidden) } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(WeiBeiIconButtonStyle())
                .accessibilityLabel(Text(store.ui("收起对话浮窗", "Hide chat popover")))
                .help(store.ui("收起对话浮窗", "Hide chat popover"))
            }
            .weibeiFloatingHeaderChrome(appearanceMode: store.appearanceMode)

            Text(store.selectedMaterialItem.map(store.displayTitle) ?? store.ui("当前笔记", "Current note"))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(WeiBeiTheme.secondaryInk)

            if store.hasSelectionAttachments {
                AgentSelectionAttachmentPill()
                    .transition(WeiBeiTransition.floating)
            }

            ZStack(alignment: .bottomTrailing) {
                TextField(
                    "",
                    text: $store.agentDraft,
                    prompt: Text(agentPrompt)
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.placeholderInk),
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .fixedSize(horizontal: false, vertical: true)
                    .focused($draftFocused)
                    .foregroundColor(WeiBeiTheme.ink)
                    .onSubmit {
                        Task { await store.askAgent() }
                    }
                .font(.system(size: 13))
                .padding(.trailing, canSend ? 38 : 0)
                .weibeiInputSurface(active: draftFocused, height: 44)

                if canSend {
                    Button {
                        Task { await store.askAgent() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(prominence: .primary))
                    .accessibilityLabel(Text(store.ui("发送", "Send")))
                    .help(store.ui("发送", "Send"))
                    .padding(.trailing, 5)
                    .padding(.bottom, 5)
                    .transition(WeiBeiTransition.floating)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                draftFocused = true
            }
            .animation(WeiBeiMotion.micro, value: canSend)

        }
        .padding(12)
        .frame(width: 308)
        .weibeiFloatingPanel()
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
        }
    }

    private var canSend: Bool {
        !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var agentPrompt: String {
        store.agentInputPrompt
    }
}

struct FloatingSelectionAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var expanded: Bool
    var routesToConversation = false
    @State private var dragOffset = CGSize.zero
    @State private var settledOffset = CGSize.zero
    @FocusState private var draftFocused: Bool
    @Namespace private var floatingNamespace

    var body: some View {
        Group {
            if showsExpandedBody {
                expandedBody
            } else {
                promptBody
            }
        }
        .matchedGeometryEffect(id: "selection-agent-surface", in: floatingNamespace)
        .transition(WeiBeiTransition.floating)
        .weibeiFloatingPanel(cornerRadius: 7)
        .scaleEffect(showsExpandedBody ? 1 : 0.985)
        .animation(WeiBeiMotion.panel, value: expanded)
        .animation(WeiBeiMotion.panel, value: routesToConversation)
        .offset(dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = CGSize(
                        width: settledOffset.width + value.translation.width,
                        height: settledOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    withAnimation(WeiBeiMotion.panel) {
                        settledOffset = dragOffset
                        store.pinnedFloatingAgent = true
                    }
                }
        )
        .onChange(of: store.selectionContext) { _, _ in
            guard !store.pinnedFloatingAgent else { return }
            withAnimation(WeiBeiMotion.panel) {
                expanded = false
                dragOffset = .zero
                settledOffset = .zero
            }
        }
        .onChange(of: routesToConversation) { _, routesToConversation in
            guard routesToConversation else { return }
            withAnimation(WeiBeiMotion.panel) {
                expanded = false
                dragOffset = .zero
                settledOffset = .zero
            }
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
        }
        .onExitCommand {
            closeFloatingAgent()
        }
    }

    private var showsExpandedBody: Bool {
        expanded && !routesToConversation
    }

    private var promptBody: some View {
        HStack(spacing: 0) {
            Button(store.ui("问", "Ask")) {
                explainSelection()
            }
            .foregroundStyle(WeiBeiTheme.link)
            .accessibilityLabel(Text(store.ui("问当前选区", "Ask current selection")))
            .help(store.ui("问当前选区", "Ask current selection"))

            if store.canOpenSelectedSourceReference {
                promptSeparator

                Button(store.ui("来源", "Source")) {
                    openSourceReference()
                }
            }

            if store.selectionContext != nil {
                promptSeparator

                Button(store.ui("摘录", "Excerpt")) {
                    store.appendSelectionToNote()
                    closeFloatingAgent()
                }
            }
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .fixedSize()
    }

    private var promptSeparator: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.78))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 8)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                actionButton(store.ui("解释", "Explain")) { explainSelection() }
                if store.canOpenSelectedSourceReference {
                    actionButton(store.ui("来源", "Source")) { openSourceReference() }
                }
                if store.selectionContext != nil {
                    actionButton(store.ui("摘录", "Excerpt")) {
                        store.appendSelectionToNote()
                        closeFloatingAgent()
                    }
                }
                if canPolishNoteSelection {
                    actionButton(store.ui("润色", "Polish")) { polishNote() }
                }
                if store.canReplaceNoteSelection {
                    actionButton(store.ui("替换", "Replace")) {
                        store.replaceSelectionWithLastAgentAnswer()
                        closeFloatingAgent()
                    }
                }
                Spacer(minLength: 0)
                iconButton(
                    store.pinnedFloatingAgent ? "pin.fill" : "pin",
                    help: store.pinnedFloatingAgent ? store.ui("取消固定浮层", "Unpin floating layer") : store.ui("固定浮层", "Pin floating layer")
                ) {
                    withAnimation(WeiBeiMotion.micro) {
                        togglePinnedFloatingAgent()
                    }
                }
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let selection = store.selectionContext?.text {
                        Text(selection)
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if store.isAskingAgent {
                        Text(store.ui("正在读选区...", "Reading selection..."))
                            .font(.caption2)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                    }

                    ForEach(visibleFloatingMessages) { message in
                        Text(floatingText(for: message))
                            .font(.caption2)
                            .foregroundStyle(floatingColor(for: message))
                            .lineLimit(message.role == .user ? 3 : nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: floatingFeedHeight)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                TextField(
                    "",
                    text: $store.agentDraft,
                    prompt: Text(store.ui("继续追问", "Ask a follow-up"))
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                    .textFieldStyle(.plain)
                    .foregroundColor(WeiBeiTheme.ink)
                    .focused($draftFocused)
                    .onSubmit { sendDraft() }
                    .font(.caption)

                if canSendDraft {
                    Button {
                        sendDraft()
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(size: 22, prominence: .primary))
                    .accessibilityLabel(Text(store.ui("发送", "Send")))
                    .help(store.ui("发送", "Send"))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 34)
            .weibeiInputSurface(active: draftFocused, height: 34)
        }
        .padding(10)
        .frame(width: CGFloat(SelectionFloatingAgentPlacement.expandedHalfWidth * 2), alignment: .leading)
        .onAppear {
            draftFocused = true
        }
    }

    private var canSendDraft: Bool {
        !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleFloatingMessages: [AgentMessage] {
        var result: [AgentMessage] = []
        var includedCredentialNotice = false

        for message in store.messages.suffix(6).reversed() {
            if isGeneratedSelectionPrompt(message) {
                continue
            }
            if isCredentialNotice(message) {
                guard !includedCredentialNotice else { continue }
                includedCredentialNotice = true
            }

            result.append(message)
            if result.count == 3 { break }
        }

        return result.reversed()
    }

    private var canPolishNoteSelection: Bool {
        store.selectionContext?.isNoteSelection == true
    }

    private var floatingFeedHeight: CGFloat {
        if visibleFloatingMessages.isEmpty && !store.isAskingAgent { return 42 }
        switch visibleFloatingMessages.count {
        case 0:
            return 56
        case 1:
            return 96
        case 2:
            return 150
        default:
            return 220
        }
    }

    private func floatingText(for message: AgentMessage) -> String {
        if isCredentialNotice(message) {
            if isOfflineContextPreview(message) {
                return message.text
            }
            return store.ui("未配置密钥。设置后会结合\(store.agentPromptScope)和已选文本片段作答。", "No key is configured. After setup, answers will use \(store.agentPromptScope) and selected text fragments.")
        }
        return message.text
    }

    private func floatingColor(for message: AgentMessage) -> Color {
        if message.text.hasPrefix("请求失败：") || message.text.hasPrefix("Agent 请求失败：") || message.text.hasPrefix("Request failed:") {
            return WeiBeiTheme.cinnabar
        }
        if message.role == .user {
            return WeiBeiTheme.link
        }
        if isCredentialNotice(message) {
            return WeiBeiTheme.secondaryInk
        }
        return WeiBeiTheme.ink
    }

    private func isCredentialNotice(_ message: AgentMessage) -> Bool {
        message.role == .assistant
            && (message.text.hasPrefix("未配置密钥") || message.text.hasPrefix("未配置 OPENAI_API_KEY") || message.text.hasPrefix("No key is configured"))
    }

    private func isOfflineContextPreview(_ message: AgentMessage) -> Bool {
        message.text.contains("这次提问已经进入对话")
            || message.text.contains("question was still sent into the chat")
    }

    private func isGeneratedSelectionPrompt(_ message: AgentMessage) -> Bool {
        message.role == .user
            && (message.text.hasPrefix("请解释当前已选文本片段")
                || message.text.hasPrefix("请解释下面选区"))
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(WeiBeiTextActionButtonStyle())
            .accessibilityLabel(Text(title))
            .help(title)
    }

    private func togglePinnedFloatingAgent() {
        if store.pinnedFloatingAgent {
            dragOffset = .zero
            settledOffset = .zero
        }
        store.pinnedFloatingAgent.toggle()
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 22))
        .accessibilityLabel(Text(help))
        .help(help)
    }

    private func explainSelection() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = !routesToConversation
            if routesToConversation {
                dragOffset = .zero
                settledOffset = .zero
            }
            store.askSelection()
        }
    }

    private func openSourceReference() {
        store.openSelectedSourceReference()
        closeFloatingAgent()
    }

    private func polishNote() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
            store.agentDraft = store.ui("请整理和润色当前笔记，保留原意，并标出缺少来源的位置。", "Organize and polish the current note, preserve the meaning, and mark where sources are missing.")
        }
        Task { await store.askAgent() }
    }

    private func sendDraft() {
        guard canSendDraft else { return }
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
        }
        Task { await store.askAgent() }
    }

    private func closeFloatingAgent() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = false
            dragOffset = .zero
            settledOffset = .zero
            store.dismissFloatingSelectionAgent()
        }
    }
}

struct QuietInsightView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var compact = false
    @State private var compactHovering = false
    @State private var panelHovering = false

    var body: some View {
        if compact {
            compactBody
        } else {
            panelBody
        }
    }

    private var compactBody: some View {
        HStack(alignment: .top, spacing: 9) {
            Rectangle()
                .fill(WeiBeiTheme.cinnabar.opacity(compactHovering ? 0.52 : 0.32))
                .frame(width: 2)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.quietInsight.body)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(3)
                    .lineSpacing(2)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.quietInsightSourceLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }

            Spacer(minLength: 4)

            if compactHovering {
                HStack(spacing: 4) {
                    if !store.quietInsight.noteBlock.isEmpty {
                        iconButton("text.badge.plus", help: store.ui("收进摘录", "Save to excerpts")) {
                            withAnimation(WeiBeiMotion.panel) {
                                store.acceptQuietInsight()
                            }
                        }
                    }

                    iconButton("bubble.left", help: store.ui("追问", "Ask follow-up")) {
                        withAnimation(WeiBeiMotion.panel) {
                            store.askQuietInsight()
                        }
                    }

                    iconButton("xmark", help: store.ui("忽略", "Dismiss")) {
                        withAnimation(WeiBeiMotion.panel) {
                            store.showQuietInsight = false
                        }
                    }
                }
                .transition(WeiBeiTransition.floating)
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, compactHovering ? 6 : 2)
        .padding(.vertical, 5)
        .frame(width: compactHovering ? 244 : 216, alignment: .leading)
        .background(WeiBeiTheme.paperRaised.opacity(compactHovering ? 0.42 : 0.0))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(compactHovering ? 0.40 : 0.0))
                .frame(height: 1)
        }
        .offset(x: compactHovering ? 2 : 0)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                compactHovering = hovering
            }
        }
    }

    private var panelBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(WeiBeiTheme.cinnabar.opacity(0.48))
                .frame(width: 2, height: 58)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.quietInsightTitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    Spacer(minLength: 6)
                    if panelHovering {
                        HStack(spacing: 4) {
                            if !store.quietInsight.noteBlock.isEmpty {
                                iconButton("text.badge.plus", help: store.ui("收进摘录", "Save to excerpts")) {
                                    withAnimation(WeiBeiMotion.panel) {
                                        store.acceptQuietInsight()
                                    }
                                }
                            }
                            iconButton("bubble.left", help: store.ui("追问", "Ask follow-up")) {
                                withAnimation(WeiBeiMotion.panel) {
                                    store.askQuietInsight()
                                }
                            }
                            iconButton("xmark", help: store.ui("忽略阅读线索", "Dismiss reading clue")) {
                                withAnimation(WeiBeiMotion.panel) {
                                    store.showQuietInsight = false
                                }
                            }
                        }
                        .transition(WeiBeiTransition.floating)
                    }
                }

                Text(store.quietInsight.body)
                    .font(.system(size: 12.5, weight: .regular))
                    .lineLimit(5)
                    .lineSpacing(2.5)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.quietInsightSourceLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 264)
        .weibeiAnnotationPanel(cornerRadius: 6)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                panelHovering = hovering
            }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 22))
        .accessibilityLabel(Text(help))
        .help(help)
    }
}

struct ContextRailItem: Identifiable {
    var title: String
    var help: String?
    var systemImage: String?
    var emphasized = false
    var action: (() -> Void)?

    var id: String {
        title
    }
}

struct ContextRailView: View {
    var title: String
    var items: [ContextRailItem]
    var edge: HorizontalEdge = .trailing
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.80))
                    .frame(width: 12, height: 1)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .padding(.horizontal, 4)

            ForEach(items) { item in
                ContextRailLine(item: item, inwardOffset: inwardOffset)
                    .transition(WeiBeiTransition.message)
            }

            Spacer()
        }
        .padding(.top, 17)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(railBackground)
        .overlay(alignment: separatorAlignment) {
            LinearGradient(
                colors: [
                    .clear,
                    WeiBeiTheme.hairline.opacity(0.34),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1)
        }
        .overlay(alignment: highlightAlignment) {
            LinearGradient(
                colors: [
                    WeiBeiTheme.glassHighlight.opacity(0.22),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(WeiBeiMotion.reveal) {
                appeared = true
            }
        }
    }

    private var inwardOffset: CGFloat {
        edge == .leading ? -3 : 3
    }

    private var railBackground: some View {
        ZStack(alignment: highlightAlignment) {
            WeiBeiTheme.paperRaised.opacity(0.10)
            LinearGradient(
                colors: [
                    WeiBeiTheme.paperRaised.opacity(0.26),
                    WeiBeiTheme.paper.opacity(0.08),
                    .clear
                ],
                startPoint: edge == .leading ? .leading : .trailing,
                endPoint: edge == .leading ? .trailing : .leading
            )
            .frame(width: 22)
            LinearGradient(
                colors: [
                    WeiBeiTheme.glassHighlight.opacity(0.12),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1)
        }
    }

    private var separatorAlignment: Alignment {
        edge == .leading ? .leading : .trailing
    }

    private var highlightAlignment: Alignment {
        edge == .leading ? .trailing : .leading
    }
}

private struct ContextRailLine: View {
    var item: ContextRailItem
    var inwardOffset: CGFloat
    @State private var hovering = false

    var body: some View {
        if let action = item.action {
            Button(action: action) {
                lineContent
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(item.help ?? item.title)
            .accessibilityLabel(Text(item.help ?? item.title))
            .onHover { hovering in
                setHovering(hovering)
            }
            .animation(WeiBeiMotion.micro, value: item.emphasized)
        } else {
            lineContent
                .onHover { hovering in
                    setHovering(hovering)
                }
                .animation(WeiBeiMotion.micro, value: item.emphasized)
        }
    }

    private var lineContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Capsule()
                .fill(railMarkColor)
                .frame(width: 2, height: hovering || item.emphasized ? 15 : 10)
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(iconColor)
            }
            Text(item.title)
                .lineLimit(2)
        }
        .font(.system(size: 12, weight: item.emphasized ? .semibold : .medium))
        .foregroundStyle(item.emphasized || hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .frame(minHeight: 24, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperInset.opacity(hovering ? 0.16 : item.emphasized ? 0.06 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .offset(x: hovering ? inwardOffset : 0)
    }

    private var railMarkColor: Color {
        if item.emphasized { return WeiBeiTheme.cinnabar.opacity(hovering ? 0.54 : 0.38) }
        if hovering { return WeiBeiTheme.cinnabar.opacity(0.28) }
        return WeiBeiTheme.hairline.opacity(0.90)
    }

    private var iconColor: Color {
        if item.emphasized || hovering { return WeiBeiTheme.cinnabar.opacity(0.74) }
        return WeiBeiTheme.tertiaryInk
    }

    private func setHovering(_ hovering: Bool) {
        withAnimation(WeiBeiMotion.hover) {
            self.hovering = hovering
        }
    }
}

private struct AgentBubble: View {
    @EnvironmentObject private var store: WorkspaceStore
    var message: AgentMessage
    @State private var hovering = false

    var body: some View {
        Group {
            if isUser {
                userTurn
            } else {
                assistantTurn
            }
        }
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                self.hovering = hovering
            }
        }
        .animation(WeiBeiMotion.panel, value: message.id)
    }

    @ViewBuilder
    private var userTurn: some View {
        HStack(alignment: .top) {
            Spacer(minLength: 42)

            regularMessageContent
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 520, alignment: .leading)
                .background(WeiBeiTheme.paperInset.opacity(hovering ? 0.32 : 0.24))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(WeiBeiTheme.hairline.opacity(hovering ? 0.92 : 0.42), lineWidth: 1)
                }
                .weibeiHoverLift(active: hovering, amount: 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var assistantTurn: some View {
        if isCredentialNotice {
            credentialNoticeContent
                .padding(.vertical, 8)
                .padding(.leading, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(WeiBeiTheme.link.opacity(hovering ? 0.50 : 0.34))
                        .frame(width: 2, height: 30)
                }
        } else {
            regularMessageContent
                .padding(.vertical, 10)
                .padding(.leading, 20)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WeiBeiTheme.paperRaised.opacity(hovering ? 0.14 : 0.0))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(assistantMarkColor.opacity(hovering ? 1.0 : 0.72))
                        .frame(width: 2, height: hovering ? 34 : 24)
                        .padding(.leading, 4)
                }
        }
    }

    private var regularMessageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(speakerTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(speakerColor)
                if let source = message.source {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(WeiBeiTheme.paperInset.opacity(0.24))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Spacer(minLength: 0)
            }

            AgentMessageMarkdownText(text: message.text)

            if message.id == store.lastUsableAgentAnswerID {
                HStack(spacing: 6) {
                    if store.selectionContext != nil {
                        Button(store.ui("摘录", "Excerpt")) {
                            store.appendSelectionToNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    Button(store.ui("写入回答", "Write Answer")) {
                        store.applyLastAgentAnswerToNote()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    if store.canReplaceNoteSelection {
                        Button(store.ui("替换", "Replace")) {
                            store.replaceSelectionWithLastAgentAnswer()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var credentialNoticeContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.ui("需要设置密钥", "Key Required"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Text(displayText)
                .textSelection(.enabled)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var isCredentialNotice: Bool {
        message.role == .assistant
            && (message.text.hasPrefix("未配置密钥") || message.text.hasPrefix("未配置 OPENAI_API_KEY") || message.text.hasPrefix("No key is configured"))
    }

    private var speakerTitle: String {
        if isUser { return store.ui("你", "You") }
        return isCredentialNotice ? store.ui("需要设置密钥", "Key Required") : store.appDisplayName
    }

    private var speakerColor: Color {
        if isUser { return WeiBeiTheme.link }
        return isCredentialNotice ? WeiBeiTheme.secondaryInk : WeiBeiTheme.cinnabar
    }

    private var displayText: String {
        guard isCredentialNotice else { return message.text }
        if isOfflineContextPreview {
            return message.text
        }
        let scope = store.hasSelectionAttachments ? store.ui("\(store.agentPromptScope)、已选文本片段", "\(store.agentPromptScope) and selected text fragments") : store.agentPromptScope
        return store.ui("设置后会结合\(scope)作答；未配置时不会编造内容。", "After setup, answers will use \(scope). Without a key, WeiBei will not invent content.")
    }

    private var isOfflineContextPreview: Bool {
        message.text.contains("这次提问已经进入对话")
            || message.text.contains("question was still sent into the chat")
    }

    private var bubblePadding: EdgeInsets {
        isCredentialNotice
            ? EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 12)
            : EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    }

    private var bubbleMaxWidth: CGFloat {
        isCredentialNotice ? 360 : 560
    }

    private var assistantMarkColor: Color {
        isCredentialNotice ? WeiBeiTheme.link.opacity(0.42) : WeiBeiTheme.cinnabar.opacity(0.50)
    }

    private var bubbleFill: Color {
        if isUser { return WeiBeiTheme.cinnabarSoft }
        return WeiBeiTheme.paperRaised.opacity(isCredentialNotice ? 0.34 : 0.72)
    }

    private var bubbleStroke: Color {
        isUser ? WeiBeiTheme.cinnabar.opacity(0.10) : WeiBeiTheme.hairline.opacity(isCredentialNotice ? 0.50 : 1)
    }
}

private struct AgentMessageMarkdownText: View {
    var text: String

    var body: some View {
        Text(renderedText)
            .textSelection(.enabled)
            .font(.system(size: 14))
            .lineSpacing(4)
            .foregroundStyle(WeiBeiTheme.ink)
    }

    private var renderedText: AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private struct AgentThinkingIndicator: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(WeiBeiTheme.cinnabar.opacity(0.46))
                        .frame(width: 5, height: 5)
                        .scaleEffect(pulse ? 1.0 : 0.72)
                        .opacity(pulse ? 0.84 : 0.34)
                        .animation(
                            .easeInOut(duration: 0.72)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12),
                            value: pulse
                        )
                }
            }
            Text(store.ui("正在读取上下文", "Reading context"))
                .font(.caption)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(WeiBeiTheme.paperRaised.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline, lineWidth: 1)
        }
        .onAppear {
            pulse = true
        }
    }
}
