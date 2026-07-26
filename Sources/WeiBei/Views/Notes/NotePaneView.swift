import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct NotePaneView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var hoveredNoteMode: NoteRenderMode?
    /// Local typing buffer so each keystroke does not republish WorkspaceStore.noteText to the whole tree.
    @State private var draftNoteText = ""
    @State private var draftNoteItemID: String?
    @State private var isApplyingExternalNote = false
    @State private var noteDraftFlushTask: Task<Void, Never>?
    @State private var activeNoteRailID: String?
    var showsPaneHeader = true
    var reorderRole: WorkspacePaneRole? = nil

    private let noteDraftFlushDelayNanoseconds: UInt64 = 220_000_000

    private static var showsLinkedSourcesVerificationOverlay: Bool {
        ProcessInfo.processInfo.environment["WEIBEI_VERIFY_SCENARIO"] == "linked-sources-flow"
            && ProcessInfo.processInfo.environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1"
    }

    var body: some View {
        GeometryReader { geometry in
            let railOnly = ContentRailMetrics.isRailOnly(
                availableWidth: geometry.size.width,
                allowed: store.layout.allowsRailOnlyPanes
            )
            let railItems = noteRailItems
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    if showsPaneHeader {
                        noteHeader
                    }

                    if let noteFileError = store.noteFileError {
                        Text(noteFileError)
                            .font(.caption)
                            .foregroundStyle(noteFileStatusColor(for: noteFileError))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                    } else if let transientNoteStatus = store.transientNoteStatus {
                        Text(transientNoteStatus)
                            .font(.caption)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }

                    noteBody
                }
                .opacity(railOnly ? 0 : 1)
                .allowsHitTesting(!railOnly)

                if store.layout != .immersiveWriting {
                    ContentRailView(
                        label: store.ui("文稿目录", "Draft outline"),
                        items: railItems,
                        activeID: activeNoteRailID ?? railItems.first?.id,
                        appearanceMode: store.appearanceMode,
                        isRailOnly: railOnly,
                        availableWidth: geometry.size.width,
                        topInset: railOnly ? 0 : (showsPaneHeader ? 44 : 34),
                        onActivate: { activateNoteRailItem($0, railOnly: railOnly) }
                    )
                    .zIndex(4)
                }
            }
        }
        .frame(minHeight: 280)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(WeiBeiTheme.paper)
        .overlay(alignment: .topLeading) {
            AccessibilityFrameProbe(identifier: "stable-document-slot-reader")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if !showsPaneHeader {
                immersiveNoteHeader
            }
        }
        .overlay(alignment: .topTrailing) {
            if Self.showsLinkedSourcesVerificationOverlay {
                LinkedSourcesPopover(dismiss: {})
                    .environmentObject(store)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: WeiBeiTheme.ink.opacity(0.16), radius: 22, y: 10)
                    .padding(.top, 48)
                    .padding(.trailing, 24)
                    .allowsHitTesting(false)
            }
        }
        .animation(WeiBeiMotion.panel, value: store.notebookCreationDraft?.id)
        .onAppear {
            pullExternalNoteText()
        }
        .onDisappear {
            flushNoteDraft(immediate: true)
        }
        .onChange(of: store.activeNoteItemID) { previousID, _ in
            if let previousID, previousID == draftNoteItemID {
                flushNoteDraft(for: previousID, immediate: true)
            }
            pullExternalNoteText()
        }
        .onChange(of: store.noteText) { _, newValue in
            guard !isApplyingExternalNote else { return }
            // External writers (agent insert, wiki open, import) win over a stale draft.
            if newValue != draftNoteText {
                noteDraftFlushTask?.cancel()
                noteDraftFlushTask = nil
                draftNoteText = newValue
                draftNoteItemID = store.activeNoteItemID
                store.clearStagedNoteDraft(for: draftNoteItemID)
            }
        }
        .onChange(of: store.focusedPane) { _, pane in
            if pane != .notes {
                flushNoteDraft(immediate: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stable-document-slot-reader")
        .accessibilityLabel(Text("notes reader pane"))
    }

    @ViewBuilder
    private var noteHeader: some View {
        if let draft = store.notebookCreationDraft {
            notebookCreationPanel(draft: draft)
            .weibeiPaneHeaderChrome(appearanceMode: store.appearanceMode)
            .modifier(PaneHeaderReorderModifier(role: reorderRole))
            .transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        } else {
            WeiBeiPaneHeader(
                title: store.ui("笔记", "Notes"),
                latinMark: store.interfaceLanguage == .chinese ? "NOTES" : nil,
                subtitle: noteHeaderSubtitle,
                appearanceMode: store.appearanceMode,
                reorderRole: reorderRole
            ) {
                LinkedSourcesControl()
                writingAssistControl
                noteModeControl
                newNoteControl
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        }
    }

    private var immersiveNoteHeader: some View {
        ZStack(alignment: .top) {
            ImmersiveHoverTitleView(
                mark: "NOTES",
                title: noteHeaderSubtitle,
                appearanceMode: store.appearanceMode,
                isPinned: store.notebookCreationDraft != nil || store.linkedSourcesPresented,
                actionsAlignedTrailing: true,
                reorderRole: reorderRole
            ) {
                LinkedSourcesControl()
                writingAssistControl
                noteModeControl
                newNoteControl
            }

            if let draft = store.notebookCreationDraft {
                notebookCreationPanel(draft: draft)
                    .padding(.horizontal, 10)
                    .frame(width: 420, height: 34)
                    .padding(.top, 42)
                    .transition(WeiBeiTransition.floating)
            }
        }
    }

    private func notebookCreationPanel(draft: NotebookCreationDraft) -> some View {
        NotebookCreationPanel(
            draft: draft,
            title: Binding(
                get: { store.notebookCreationDraft?.title ?? "" },
                set: { store.notebookCreationDraft?.title = $0 }
            ),
            confirm: {
                withAnimation(WeiBeiMotion.panel) {
                    store.confirmNotebookNoteCreation()
                }
            },
            cancel: {
                withAnimation(WeiBeiMotion.panel) {
                    store.cancelNotebookNoteCreation()
                }
            }
        )
    }

    private var writingAssistControl: some View {
        Menu {
            Button {
                prepareWritingAssist(store.ui(
                    "请根据\(store.agentPromptScope)，给出一版更清晰的笔记大纲。",
                    "Use \(store.agentPromptScope) to produce a clearer note outline."
                ))
            } label: {
                Label(store.ui("大纲建议", "Outline"), systemImage: "list.bullet.rectangle")
            }
            Button {
                prepareWritingAssist(store.hasSelectedMaterial
                    ? store.ui(
                        "请检查当前笔记缺少来源的位置，并建议应该引用当前资料的哪些部分。",
                        "Find where the current note needs sources and suggest which parts of the current material to cite."
                    )
                    : store.ui(
                        "请检查当前笔记缺少来源的位置，并标出需要补证据的段落。",
                        "Find where the current note needs sources and mark the paragraphs that need evidence."
                    ))
            } label: {
                Label(store.ui("补来源", "Add Sources"), systemImage: "link")
            }
            Button {
                prepareWritingAssist(store.ui(
                    "请整理和润色当前笔记，保留原意，并标出缺少来源的位置。",
                    "Organize and polish the current note, preserve the meaning, and mark where sources are missing."
                ))
            } label: {
                Label(store.ui("润色表达", "Polish"), systemImage: "text.quote")
            }
        } label: {
            Label(store.ui("整理", "Refine"), systemImage: "text.badge.checkmark")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(WeiBeiTheme.secondaryInk)
        .accessibilityLabel(Text(store.ui("整理当前笔记", "Refine current note")))
        .help(store.ui("按需生成大纲、补来源或润色表达", "Create an outline, add sources, or polish on demand"))
    }

    private func prepareWritingAssist(_ prompt: String) {
        flushNoteDraft(immediate: true)
        withAnimation(WeiBeiMotion.layout) {
            store.agentDraft = prompt
            store.setLayout(.immersiveConversation)
            store.revealRightPane(focusing: .agent)
        }
    }

    @ViewBuilder
    private var newNoteControl: some View {
        if store.hasSelectedMaterial {
            Menu {
                Button(store.ui("空白课程笔记", "Blank Course Note")) {
                    withAnimation(WeiBeiMotion.panel) {
                        store.promptCreateBlankNotebookNote()
                    }
                }
                Button(store.ui("当前资料笔记", "Current Material Note")) {
                    withAnimation(WeiBeiMotion.panel) {
                        store.promptCreateNotebookNoteFromCurrentMaterial()
                    }
                }
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 24))
            .accessibilityLabel(Text(store.ui("新建课程笔记", "New Course Note")))
            .help(store.ui("新建空白笔记或当前资料笔记", "Create a blank note or a note for the current material"))
        } else {
            Button {
                withAnimation(WeiBeiMotion.panel) {
                    store.promptCreateBlankNotebookNote()
                }
            } label: {
                Image(systemName: "doc.badge.plus")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 24))
            .accessibilityLabel(Text(store.ui("新建空白课程笔记", "New Blank Course Note")))
            .help(store.ui("新建空白课程笔记", "Create a blank course note"))
        }
    }

    private var noteModeControl: some View {
        HStack(spacing: 3) {
            ForEach(NoteRenderMode.visibleCases) { mode in
                noteModeButton(for: mode)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 28)
        .weibeiHeaderAccessoryGroup()
        .animation(WeiBeiMotion.appearance, value: store.appearanceMode)
    }

    private func noteModeButton(for mode: NoteRenderMode) -> some View {
        let selected = store.noteRenderMode.visibleMode == mode
        let label = mode.label(language: store.interfaceLanguage)
        return Button {
            withAnimation(WeiBeiMotion.layout) {
                store.setNoteRenderMode(mode)
            }
        } label: {
            noteModeButtonLabel(mode: mode, selected: selected, hovering: hoveredNoteMode == mode)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                hoveredNoteMode = hovering ? mode : (hoveredNoteMode == mode ? nil : hoveredNoteMode)
            }
        }
        .accessibilityLabel(Text(label))
        .help(label)
    }

    private func noteModeButtonLabel(mode: NoteRenderMode, selected: Bool, hovering: Bool) -> some View {
        let foreground = selected ? WeiBeiTheme.cinnabar : hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk
        return Image(systemName: noteModeIcon(for: mode))
            .font(.system(size: 11.6, weight: selected ? .semibold : .medium))
            .frame(width: 28, height: 24)
            .foregroundStyle(foreground)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(noteModeButtonFill(selected: selected, hovering: hovering))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(noteModeButtonStroke(selected: selected, hovering: hovering), lineWidth: selected ? 0.7 : 0.45)
            }
            .scaleEffect(hovering && !selected ? 1.012 : 1)
            .contentShape(Rectangle())
            .animation(WeiBeiMotion.micro, value: selected)
            .animation(WeiBeiMotion.hover, value: hovering)
    }

    private func noteModeIcon(for mode: NoteRenderMode) -> String {
        switch mode {
        case .rich:
            return "square.and.pencil"
        case .split:
            return "rectangle.split.2x1"
        case .source:
            return "chevron.left.forwardslash.chevron.right"
        case .preview:
            return "eye"
        }
    }

    private func noteModeButtonFill(selected: Bool, hovering: Bool) -> Color {
        if selected {
            return WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode == .inkstone ? 0.44 : 0.62)
        }
        if hovering {
            return WeiBeiTheme.paperRaised.opacity(store.appearanceMode == .inkstone ? 0.16 : 0.20)
        }
        return Color.clear
    }

    private func noteModeButtonStroke(selected: Bool, hovering: Bool) -> Color {
        if selected {
            return WeiBeiTheme.cinnabar.opacity(store.appearanceMode == .inkstone ? 0.34 : 0.24)
        }
        if hovering {
            return WeiBeiTheme.hairline.opacity(store.appearanceMode == .inkstone ? 0.30 : 0.18)
        }
        return Color.clear
    }

    private var noteHeaderSubtitle: String {
        store.agentNoteTitle
    }

    private func noteFileStatusColor(for message: String) -> Color {
        message.hasPrefix("无法") || message.hasPrefix("Could not") ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk
    }

    @ViewBuilder
    private var noteBody: some View {
        Group {
            switch store.noteRenderMode.visibleMode {
            case .rich:
                richEditor
            case .split:
                HSplitView {
                    noteEditor
                        .frame(minWidth: 220)
                    MarkdownPreviewView(
                        markdown: draftNoteText,
                        markdownBaseURL: store.currentMarkdownBaseURL,
                        appearanceMode: store.appearanceMode,
                        interfaceLanguage: store.interfaceLanguage,
                        compact: true,
                        fitsContentHeight: false,
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
                richEditor
            }
        }
        .transition(WeiBeiTransition.layout)
        .animation(WeiBeiMotion.layout, value: store.noteRenderMode.visibleMode)
        .overlay(alignment: .topLeading) {
            if noteIsEmpty {
                emptyNoteHint
                    .transition(WeiBeiTransition.message)
            }
        }
    }

    private var noteMarkdownBinding: Binding<String> {
        Binding(
            get: { draftNoteText },
            set: { value in
                guard value != draftNoteText else { return }
                draftNoteText = value
                draftNoteItemID = store.activeNoteItemID
                store.stageNoteDraft(value, for: draftNoteItemID)
                scheduleNoteDraftFlush()
            }
        )
    }

    private var noteRailItems: [ContentRailItem] {
        let lines = draftNoteText.components(separatedBy: .newlines)
        let headings = lines.enumerated().compactMap { offset, line -> (line: Int, level: Int, title: String)? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let level = trimmed.prefix { $0 == "#" }.count
            guard (1...4).contains(level) else { return nil }
            let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: level)
            guard markerEnd < trimmed.endIndex, trimmed[markerEnd].isWhitespace else { return nil }
            let title = trimmed[markerEnd...].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return nil }
            return (offset, level, title)
        }

        return headings.enumerated().map { index, heading in
            let nextLine = index + 1 < headings.count ? headings[index + 1].line : lines.count
            let excerpt = lines[(heading.line + 1)..<max(heading.line + 1, nextLine)]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let position = lines.count > 1 ? CGFloat(heading.line) / CGFloat(lines.count - 1) : 0
            return ContentRailItem(
                id: "note-heading-\(index)",
                position: position,
                level: heading.level - 1,
                title: heading.title,
                excerpt: railPreviewText(excerpt),
                metadata: store.ui("第 \(index + 1) / \(headings.count) 节 · H\(heading.level)", "Section \(index + 1) / \(headings.count) · H\(heading.level)")
            )
        }
    }

    private func activateNoteRailItem(_ item: ContentRailItem, railOnly: Bool) {
        guard let index = Int(item.id.replacingOccurrences(of: "note-heading-", with: "")) else { return }
        activeNoteRailID = item.id
        let navigate = {
            store.noteEditorCommand = NoteEditorCommand(kind: .scrollToHeading, markdown: String(index))
        }
        if railOnly {
            store.requestPaneExpansion(.notes)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: navigate)
        } else {
            navigate()
        }
    }

    private func railPreviewText(_ value: String) -> String {
        let collapsed = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(180))
    }

    private var richEditor: some View {
        let itemID = store.activeNoteItemID
        return RichMarkdownEditorView(documentID: itemID ?? "", markdown: noteMarkdownBinding, command: Binding(get: {
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
            flushNoteDraft(immediate: true)
            store.updateSelection(text, source: .note, anchor: anchor)
            store.askSelection()
        }, onActiveHeadingChange: { index in
            activeNoteRailID = index.map { "note-heading-\($0)" }
        }, onWikiLink: { title in
            flushNoteDraft(immediate: true)
            store.openOrCreateWikiNote(title: title)
        }, onSourceReference: { reference in
            flushNoteDraft(immediate: true)
            store.openSourceReference(reference)
        }, onAppShortcut: { key, modifiers in
            if modifiers.contains(.command) {
                flushNoteDraft(immediate: true)
            }
            return store.handleAppShortcut(key: key, modifiers: modifiers)
        })
        .background(WeiBeiTheme.paper)
    }

    private var noteEditor: some View {
        MarkdownSourceEditor(text: noteMarkdownBinding, command: Binding(get: {
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
            flushNoteDraft(immediate: true)
            store.openOrCreateWikiNote(title: title)
        })
        .background(WeiBeiTheme.paper)
    }

    private var noteIsEmpty: Bool {
        draftNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pullExternalNoteText() {
        isApplyingExternalNote = true
        draftNoteItemID = store.activeNoteItemID
        draftNoteText = store.noteText
        store.clearStagedNoteDraft(for: draftNoteItemID)
        isApplyingExternalNote = false
    }

    private func scheduleNoteDraftFlush() {
        noteDraftFlushTask?.cancel()
        let itemID = draftNoteItemID ?? store.activeNoteItemID
        let snapshot = draftNoteText
        noteDraftFlushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: noteDraftFlushDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard draftNoteText == snapshot else { return }
            flushNoteDraft(for: itemID, immediate: true)
        }
    }

    private func flushNoteDraft(immediate: Bool = false) {
        flushNoteDraft(for: draftNoteItemID ?? store.activeNoteItemID, immediate: immediate)
    }

    private func flushNoteDraft(for itemID: String?, immediate: Bool) {
        noteDraftFlushTask?.cancel()
        noteDraftFlushTask = nil
        guard let itemID else { return }
        let value = (itemID == draftNoteItemID) ? draftNoteText : draftNoteText
        defer { store.clearStagedNoteDraft(for: itemID, matching: value) }
        if itemID == store.activeNoteItemID {
            if store.noteText == value { return }
            isApplyingExternalNote = true
            store.updateNote(value, for: itemID)
            isApplyingExternalNote = false
            return
        }
        // Inactive flush after note switch.
        store.updateNote(value, for: itemID)
        _ = immediate
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

struct NotebookCreationPanel: View {
    @EnvironmentObject private var store: WorkspaceStore
    var draft: NotebookCreationDraft
    @Binding var title: String
    var confirm: () -> Void
    var cancel: () -> Void
    @FocusState private var focused: Bool
    @State private var hoveredConfirm = false
    @State private var hoveredCancel = false

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 9) {
            Text(draft.kind == .blank ? store.ui("新建笔记", "New Note") : store.ui("资料笔记", "Material Note"))
                .font(.system(size: 12.5, weight: .semibold, design: .serif))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.86))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            TextField(
                "",
                text: $title,
                prompt: Text(store.ui("笔记名", "Note title"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14.5, weight: .medium))
            .foregroundColor(WeiBeiTheme.ink)
            .focused($focused)
            .onSubmit(confirm)
            .frame(maxWidth: .infinity)
            .frame(height: 24)

            Button(action: confirm) {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(confirmColor)
            .frame(width: 28, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(confirmBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(confirmBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(hoveredConfirm && canCreate ? 1.04 : 1)
            .opacity(canCreate ? 1 : 0.42)
            .disabled(!canCreate)
            .keyboardShortcut(.defaultAction)
            .onHover { hovering in
                withAnimation(WeiBeiMotion.hover) {
                    hoveredConfirm = hovering
                }
            }
            .accessibilityLabel(Text(store.ui("创建笔记", "Create Note")))
            .help(store.ui("创建笔记", "Create Note"))

            Button(action: cancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(cancelColor)
            .frame(width: 28, height: 26)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(cancelBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(cancelBorder, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(hoveredCancel ? 1.04 : 1)
            .onHover { hovering in
                withAnimation(WeiBeiMotion.hover) {
                    hoveredCancel = hovering
                }
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(Text(store.ui("取消", "Cancel")))
            .help(store.ui("取消新建笔记", "Cancel note creation"))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(WeiBeiTheme.paperInset.opacity(0.24))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(0.34), lineWidth: 1)
        }
        .onExitCommand(perform: cancel)
        .onAppear {
            focused = true
        }
    }

    private var confirmColor: Color {
        guard canCreate else { return WeiBeiTheme.tertiaryInk }
        return hoveredConfirm ? WeiBeiTheme.onCinnabar : WeiBeiTheme.secondaryInk
    }

    private var confirmBackground: Color {
        guard canCreate, hoveredConfirm else { return Color.clear }
        return WeiBeiTheme.cinnabar.opacity(0.88)
    }

    private var confirmBorder: Color {
        guard canCreate, hoveredConfirm else { return Color.clear }
        return WeiBeiTheme.cinnabar.opacity(0.48)
    }

    private var cancelColor: Color {
        hoveredCancel ? WeiBeiTheme.cinnabar.opacity(0.72) : WeiBeiTheme.secondaryInk
    }

    private var cancelBackground: Color {
        hoveredCancel ? WeiBeiTheme.cinnabarSoft.opacity(0.68) : Color.clear
    }

    private var cancelBorder: Color {
        hoveredCancel ? WeiBeiTheme.cinnabar.opacity(0.22) : Color.clear
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
