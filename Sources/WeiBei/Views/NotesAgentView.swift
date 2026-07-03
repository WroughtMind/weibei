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

struct NotePaneView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("笔记")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                Spacer()
                noteModeControl
                if !isImmersiveWriting {
                    Button { store.resetNote() } label: {
                        Label("新建", systemImage: "doc.badge.plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    .help("新建当前资料笔记")
                    if store.canUseSelectedMarkdownAsNotebookNote {
                        Button("写回原 Markdown") {
                            store.useSelectedMarkdownAsNotebookNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                        .help("把当前 Markdown 文件作为可原地写作的笔记")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.68, materialOpacity: 0.08))
            .overlay(alignment: .bottom) {
                WeiBeiHeaderHandoffFade(height: 14, opacity: 0.68)
                    .offset(y: 14)
            }
            .zIndex(1)

            if let noteFileError = store.noteFileError {
                Text(noteFileError)
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            noteBody
        }
        .frame(minHeight: 280)
        .weibeiPanel()
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
                    Text(mode.label)
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                        .frame(width: 34, height: 24)
                        .background(selected ? WeiBeiTheme.cinnabarSoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .animation(WeiBeiMotion.micro, value: selected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(WeiBeiTheme.paperInset.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline, lineWidth: 1)
        }
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
                        onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
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
                    onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
                    onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) }
                ) { text, anchor in
                    store.updateSelection(text, source: .note, anchor: anchor, isEditable: false)
                }
            }
        }
        .id(store.noteRenderMode)
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
        onSelectionChange: { text, anchor in
            store.updateSelection(text, source: .note, anchor: anchor)
        }, onAskAgentWithSelection: { text, anchor in
            store.updateSelection(text, source: .note, anchor: anchor)
            store.askSelection()
            Task { await store.askAgent() }
        }, onWikiLink: { title in
            store.openOrCreateWikiNote(title: title)
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
        Text("开始记录当前材料")
            .font(.system(size: 13, weight: .medium, design: .serif))
            .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.72))
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .allowsHitTesting(false)
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
            onSelectionChange: onSelectionChange,
            onWikiLink: onWikiLink
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = MarkdownSourceTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor(red: 0.115, green: 0.095, blue: 0.080, alpha: 1.0)
        textView.backgroundColor = .clear
        textView.string = text
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
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.applyFocus(in: textView)
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.run(command, in: textView)
            DispatchQueue.main.async {
                self.command = nil
            }
        }
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
        var lastCommandID: UUID?
        private var lastAppliedFocusRequest = -1

        init(
            text: Binding<String>,
            command: Binding<NoteEditorCommand?>,
            isFocused: Bool,
            focusRequest: Int,
            markdownBaseURLString: String,
            attachmentDirectory: URL?,
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
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0, let stringRange = Range(range, in: textView.string) else { return }
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
        }

        private func applyPatch(_ markdown: String, in textView: NSTextView) {
            let next = "\(textView.string.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(markdown.trimmingCharacters(in: .whitespacesAndNewlines))\n"
            textView.string = next
            text.wrappedValue = next
            textView.setSelectedRange(NSRange(location: (next as NSString).length, length: 0))
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
        }

        private static func anchor(for range: NSRange, in textView: NSTextView) -> CGPoint? {
            guard let window = textView.window, let contentView = window.contentView else { return nil }
            let rect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard !rect.isEmpty else { return nil }
            let screenPoint = CGPoint(x: rect.midX, y: rect.minY)
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let contentPoint = contentView.convert(windowPoint, from: nil)
            let y = SelectionAnchorCoordinate.y(
                Double(contentPoint.y),
                contentHeight: Double(contentView.bounds.height),
                contentViewIsFlipped: contentView.isFlipped
            )
            return CGPoint(x: contentPoint.x, y: y)
        }
    }
}

struct MarkdownPreviewView: View {
    var markdown: String
    var markdownBaseURL: URL?
    var onWikiLink: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onSelectionChange: (String, CGPoint?) -> Void = { _, _ in }
    @State private var command: NoteEditorCommand?

    var body: some View {
        RichMarkdownEditorView(
            markdown: .constant(markdown),
            command: $command,
            isEditable: false,
            markdownBaseURL: markdownBaseURL,
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onSelectionChange,
            onWikiLink: onWikiLink,
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
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("对话")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                    Text(store.selectedItem?.title ?? "无上下文")
                        .font(.caption2)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer()

                agentToolButton("整理", help: "整理笔记", systemImage: "list.bullet.rectangle") {
                    store.askToOrganizeNote()
                }

                if store.canApplyAgentAnswer {
                    agentToolButton("写入", help: "写入笔记", systemImage: "square.and.arrow.down") {
                        store.applyLastAgentAnswerToNote()
                    }
                }

                if store.canReplaceNoteSelection {
                    agentToolButton("替换", help: "替换笔记选区", systemImage: "arrow.left.arrow.right") {
                        store.replaceSelectionWithLastAgentAnswer()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.68, materialOpacity: 0.08))
            .overlay(alignment: .bottom) {
                WeiBeiHeaderHandoffFade(height: 14, opacity: 0.68)
                    .offset(y: 14)
            }
            .zIndex(1)

            ScrollViewReader { proxy in
                ScrollView {
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
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 28)
                                .transition(WeiBeiTransition.message)
                        }
                    }
                    .padding(14)
                    .animation(WeiBeiMotion.panel, value: store.messages.count)
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
        .environment(\.colorScheme, .light)
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

            HStack(alignment: .bottom, spacing: 8) {
                TextField(
                    "",
                    text: $store.agentDraft,
                    prompt: Text("问当前材料").foregroundStyle(WeiBeiTheme.tertiaryInk),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .foregroundStyle(WeiBeiTheme.ink)
                .focused($draftFocused)
                .weibeiInputSurface(active: draftFocused, height: 34)
                .onSubmit {
                    Task { await store.askAgent() }
                }

                if canSendDraft || store.isAskingAgent {
                    Button { Task { await store.askAgent() } } label: {
                        Image(systemName: store.isAskingAgent ? "hourglass" : "paperplane.fill")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(active: canSendDraft, size: 28))
                    .disabled(store.isAskingAgent)
                    .accessibilityLabel(Text(store.isAskingAgent ? "等待 Agent" : "发送"))
                    .help(store.isAskingAgent ? "等待 Agent" : "发送")
                    .keyboardShortcut(.return, modifiers: [.command])
                    .transition(WeiBeiTransition.floating)
                    .animation(WeiBeiMotion.micro, value: canSendDraft)
                }
            }
            .font(.system(size: 14))
            .frame(maxWidth: agentInputMaxWidth)
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(WeiBeiTheme.paperRaised.opacity(0.58))
                RoundedRectangle(cornerRadius: 9)
                    .fill(.ultraThinMaterial)
                    .opacity(0.08)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(draftFocused ? WeiBeiTheme.link.opacity(0.28) : WeiBeiTheme.hairline.opacity(0.62), lineWidth: 1)
            }
            .shadow(color: WeiBeiTheme.ink.opacity(0.035), radius: 6, y: 2)
            .padding(.horizontal, 12)
            .padding(.top, 1)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .bottom) {
            WeiBeiGlassHeaderBackground(
                paperOpacity: store.layout == .immersiveConversation ? 0.50 : 0.56,
                materialOpacity: store.layout == .immersiveConversation ? 0.06 : 0.05
            )
            .mask(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.72), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var agentInputMaxWidth: CGFloat? {
        store.layout == .immersiveConversation ? 680 : nil
    }

    private var noteContextTitle: String {
        let firstLine = store.noteText
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "#* ").union(.whitespacesAndNewlines)) ?? ""
        return firstLine.isEmpty ? "当前笔记" : firstLine
    }

    private var emptyAgentState: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("当前上下文")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.selectedItem?.title ?? "未选择材料")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                contextLine("材料", store.selectedItem?.title ?? "未选择")
                contextLine("笔记", noteContextTitle)
                contextLine("选区", store.selectionContext == nil ? "未选择" : "已选中")
            }

            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.42))
                .frame(height: 1)

            HStack(spacing: 8) {
                starterChip("梳理材料", systemImage: "text.alignleft") {
                    askWith("请基于当前材料提炼核心概念、关键公式和需要回看出处的位置。")
                }
                starterChip("整理笔记", systemImage: "list.bullet.rectangle") {
                    store.askToOrganizeNote()
                }
                starterChip("出复习题", systemImage: "questionmark.square") {
                    askWith("请根据当前材料和笔记生成 5 个复习问题，并标出每题依据。")
                }
            }
        }
        .padding(.leading, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 520, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(WeiBeiTheme.cinnabar.opacity(0.34))
                .frame(width: 2)
        }
    }

    private func contextLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(1)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func starterChip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        AgentStarterChip(title: title, systemImage: systemImage, action: action)
    }

    private func askWith(_ prompt: String) {
        withAnimation(WeiBeiMotion.panel) {
            store.agentDraft = prompt
        }
        Task { await store.askAgent() }
    }

    private func agentToolButton(_ title: String, help: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(WeiBeiTextActionButtonStyle())
        .accessibilityLabel(Text(help))
        .help(help)
    }
}

private struct AgentStarterChip: View {
    var title: String
    var systemImage: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
        .background(WeiBeiTheme.paperInset.opacity(hovering ? 0.32 : 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(hovering ? WeiBeiTheme.hairline.opacity(0.92) : WeiBeiTheme.hairline.opacity(0.68), lineWidth: 1)
        }
        .offset(y: hovering ? -1 : 0)
        .onHover { value in
            withAnimation(WeiBeiMotion.hover) {
                hovering = value
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
                Text("对话")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                Spacer()
                Text("⌘↩")
                    .font(.caption.monospaced())
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            HStack(spacing: 8) {
                TextField(
                    "问当前选区或当前材料",
                    text: $store.agentDraft,
                    prompt: Text("问当前选区或当前材料").foregroundStyle(WeiBeiTheme.tertiaryInk)
                )
                    .textFieldStyle(.plain)
                    .focused($draftFocused)
                    .font(.system(size: 13))
                    .weibeiInputSurface(active: draftFocused)
                if canSend {
                    Button { Task { await store.askAgent() } } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(active: true))
                    .accessibilityLabel(Text("发送"))
                    .help("发送")
                    .transition(WeiBeiTransition.floating)
                }
            }
            .animation(WeiBeiMotion.micro, value: canSend)

            HStack(spacing: 8) {
                Label("来源", systemImage: "link")
                Text(store.selectedItem?.title ?? "当前材料")
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
        !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct CornerAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Agent")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                Spacer()
                Button { store.setAgentSurface(.hidden) } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(WeiBeiIconButtonStyle())
                .accessibilityLabel(Text("收起右下角 Agent"))
                .help("收起右下角 Agent")
            }

            Text(store.selectedItem?.title ?? "当前材料")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(WeiBeiTheme.secondaryInk)

            HStack(spacing: 8) {
                TextField(
                    "问当前材料",
                    text: $store.agentDraft,
                    prompt: Text("问当前材料").foregroundStyle(WeiBeiTheme.tertiaryInk)
                )
                    .textFieldStyle(.plain)
                    .focused($draftFocused)
                    .font(.system(size: 13))
                    .weibeiInputSurface(active: draftFocused, height: 32)

                if canSend {
                    Button {
                        Task { await store.askAgent() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(active: true))
                    .accessibilityLabel(Text("发送"))
                    .help("发送")
                    .transition(WeiBeiTransition.floating)
                }
            }
            .animation(WeiBeiMotion.micro, value: canSend)

            HStack {
                Button("整理笔记") {
                    store.askToOrganizeNote()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                if store.canApplyAgentAnswer {
                    Button("写入笔记") {
                        store.applyLastAgentAnswerToNote()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
                if store.canReplaceNoteSelection {
                    Button("替换笔记选区") {
                        store.replaceSelectionWithLastAgentAnswer()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
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
        !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct FloatingSelectionAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var expanded: Bool
    @State private var dragOffset = CGSize.zero
    @State private var settledOffset = CGSize.zero
    @FocusState private var draftFocused: Bool
    @Namespace private var floatingNamespace

    var body: some View {
        Group {
            if expanded {
                expandedBody
            } else {
                promptBody
            }
        }
        .matchedGeometryEffect(id: "selection-agent-surface", in: floatingNamespace)
        .transition(WeiBeiTransition.floating)
        .weibeiFloatingPanel(cornerRadius: 7)
        .scaleEffect(expanded ? 1 : 0.985)
        .animation(WeiBeiMotion.panel, value: expanded)
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

    private var promptBody: some View {
        HStack(spacing: 0) {
            Button("问 Agent") {
                explainSelection()
            }
            .foregroundStyle(WeiBeiTheme.link)

            if store.selectionContext != nil {
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 8)

                Button("摘录") {
                    store.appendSelectionToNote()
                    closeFloatingAgent()
                }
            }

            Button {
                closeFloatingAgent()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .padding(.leading, 8)
            }
            .accessibilityLabel(Text("收起选区 Agent"))
            .help("收起")
        }
        .font(.caption.weight(.medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .fixedSize()
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                actionButton("解释") { explainSelection() }
                if store.selectionContext != nil {
                    actionButton("摘录") {
                        store.appendSelectionToNote()
                        closeFloatingAgent()
                    }
                }
                actionButton("润色") { polishNote() }
                if store.canReplaceNoteSelection {
                    actionButton("替换") {
                        store.replaceSelectionWithLastAgentAnswer()
                        closeFloatingAgent()
                    }
                }
                Spacer(minLength: 0)
                iconButton(
                    store.pinnedFloatingAgent ? "pin.fill" : "pin",
                    help: store.pinnedFloatingAgent ? "取消固定浮层" : "固定浮层"
                ) {
                    withAnimation(WeiBeiMotion.micro) {
                        store.pinnedFloatingAgent.toggle()
                    }
                }
                iconButton("xmark", help: "收起选区 Agent") {
                    closeFloatingAgent()
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let selection = store.selectionContext?.text {
                        Text(selection)
                            .font(.caption2)
                            .lineLimit(2)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if store.isAskingAgent {
                        Text("正在读选区...")
                            .font(.caption2)
                            .foregroundStyle(WeiBeiTheme.cinnabar)
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
                    prompt: Text("继续追问").foregroundStyle(WeiBeiTheme.tertiaryInk)
                )
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.ink)
                    .focused($draftFocused)
                    .onSubmit { sendDraft() }

                if canSendDraft {
                    Button {
                        sendDraft()
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(active: true, size: 22))
                    .accessibilityLabel(Text("发送"))
                    .help("发送")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .weibeiInputSurface(active: draftFocused)
        }
        .padding(10)
        .frame(width: 312, alignment: .leading)
        .onAppear {
            draftFocused = true
        }
    }

    private var canSendDraft: Bool {
        !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            return "未配置密钥。设置后会结合材料、选区和笔记作答。"
        }
        return message.text
    }

    private func floatingColor(for message: AgentMessage) -> Color {
        if message.role == .user || message.text.hasPrefix("Agent 请求失败：") {
            return WeiBeiTheme.cinnabar
        }
        if isCredentialNotice(message) {
            return WeiBeiTheme.secondaryInk
        }
        return WeiBeiTheme.ink
    }

    private func isCredentialNotice(_ message: AgentMessage) -> Bool {
        message.role == .assistant && message.text.hasPrefix("未配置 OPENAI_API_KEY")
    }

    private func isGeneratedSelectionPrompt(_ message: AgentMessage) -> Bool {
        message.role == .user
            && (message.text.hasPrefix("请解释下面选区")
                || message.text.hasPrefix("请解释我刚才选中的内容"))
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(WeiBeiTextActionButtonStyle())
            .accessibilityLabel(Text(title))
            .help(title)
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
            expanded = true
            store.askSelection()
        }
        Task { await store.askAgent() }
    }

    private func polishNote() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
            store.agentDraft = "请整理和润色当前笔记，保留原意，并标出缺少来源的位置。"
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

    var body: some View {
        if compact {
            compactBody
        } else {
            panelBody
        }
    }

    private var compactBody: some View {
        HStack(alignment: .top, spacing: 9) {
            Capsule()
                .fill(WeiBeiTheme.cinnabar.opacity(0.48))
                .frame(width: 2, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.quietInsightTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                Text(store.quietInsight.body)
                    .font(.system(size: 12, weight: .regular))
                    .lineLimit(2)
                    .lineSpacing(2)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.quietInsightSourceLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if !store.quietInsight.noteBlock.isEmpty {
                    iconButton("text.badge.plus", help: "收进摘录") {
                        withAnimation(WeiBeiMotion.panel) {
                            store.acceptQuietInsight()
                        }
                    }
                }

                iconButton("bubble.left", help: "追问") {
                    withAnimation(WeiBeiMotion.panel) {
                        store.askQuietInsight()
                    }
                }

                iconButton("xmark", help: "忽略") {
                    withAnimation(WeiBeiMotion.panel) {
                        store.showQuietInsight = false
                    }
                }
            }
            .opacity(compactHovering ? 1 : 0.38)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(width: 238)
        .background(compactBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                compactHovering = hovering
            }
        }
    }

    private var compactBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(WeiBeiTheme.paper.opacity(compactHovering ? 0.74 : 0.34))
            RoundedRectangle(cornerRadius: 5)
                .fill(.ultraThinMaterial)
                .opacity(compactHovering ? 0.055 : 0.018)
            RoundedRectangle(cornerRadius: 5)
                .stroke(WeiBeiTheme.hairline.opacity(compactHovering ? 0.58 : 0), lineWidth: 1)
        }
    }

    private var panelBody: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(WeiBeiTheme.cinnabar.opacity(0.48))
                .frame(width: 2, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.quietInsightTitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    Spacer(minLength: 6)
                    Button {
                        withAnimation(WeiBeiMotion.panel) {
                            store.showQuietInsight = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .accessibilityLabel(Text("忽略阅读线索"))
                    .help("忽略阅读线索")
                }

                Text(store.quietInsight.body)
                    .font(.system(size: 12.5, weight: .regular))
                    .lineLimit(5)
                    .lineSpacing(2.5)
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(store.quietInsightSourceLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)

                HStack(spacing: 10) {
                    if !store.quietInsight.noteBlock.isEmpty {
                        Button("收进摘录") {
                            withAnimation(WeiBeiMotion.panel) {
                                store.acceptQuietInsight()
                            }
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                    Button("追问") {
                        withAnimation(WeiBeiMotion.panel) {
                            store.askQuietInsight()
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    Button("忽略") {
                        withAnimation(WeiBeiMotion.panel) {
                            store.showQuietInsight = false
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(width: 264)
        .weibeiAnnotationPanel(cornerRadius: 6)
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
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
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
        .background {
            LinearGradient(
                colors: [
                    WeiBeiTheme.paperRaised.opacity(0.40),
                    WeiBeiTheme.paper.opacity(0.42),
                    WeiBeiTheme.paper.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: separatorAlignment) {
            LinearGradient(
                colors: [
                    .clear,
                    WeiBeiTheme.hairline.opacity(0.48),
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
        HStack(alignment: .top) {
            if isUser {
                Spacer(minLength: 38)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(isUser ? "你" : "魏碑")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isUser ? WeiBeiTheme.link : WeiBeiTheme.cinnabar)
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

                Text(message.text)
                    .textSelection(.enabled)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(WeiBeiTheme.ink)

                if message.id == store.lastUsableAgentAnswerID {
                    HStack(spacing: 6) {
                        if store.selectionContext != nil {
                            Button("摘录") {
                                store.appendSelectionToNote()
                            }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                        Button("写入笔记") {
                            store.applyLastAgentAnswerToNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                        if store.canReplaceNoteSelection {
                            Button("替换") {
                                store.replaceSelectionWithLastAgentAnswer()
                            }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: 560, alignment: .leading)
            .background(bubbleFill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(bubbleStroke, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if !isUser {
                    Capsule()
                        .fill(WeiBeiTheme.cinnabar.opacity(0.50))
                        .frame(width: 3, height: 28)
                        .padding(.leading, 2)
                }
            }
            .weibeiHoverLift(active: hovering, amount: 1)

            if !isUser {
                Spacer(minLength: 38)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                self.hovering = hovering
            }
        }
        .animation(WeiBeiMotion.panel, value: message.id)
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var bubbleFill: Color {
        isUser ? WeiBeiTheme.cinnabarSoft : WeiBeiTheme.paperRaised.opacity(0.54)
    }

    private var bubbleStroke: Color {
        isUser ? WeiBeiTheme.cinnabar.opacity(0.10) : WeiBeiTheme.hairline
    }
}

private struct AgentThinkingIndicator: View {
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
            Text("正在读取上下文")
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
