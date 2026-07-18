import AppKit
import PDFKit
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
        .task {
            await store.runVerificationScenarioIfNeeded()
        }
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

struct WeiBeiPaneHeader<Actions: View>: View {
    var title: String
    var latinMark: String? = nil
    var subtitle: String
    var appearanceMode: WeiBeiAppearanceMode
    var reorderRole: WorkspacePaneRole? = nil
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(titleUsesEnglishBrand ? WeiBeiTypography.englishBrandFont(size: 18, weight: .semibold) : .system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(WeiBeiTheme.ink)
                if let latinMark {
                    Text(latinMark)
                        .font(WeiBeiTypography.englishBrandFont(size: 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                        .baselineOffset(1)
                }
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actions()
        }
        .weibeiPaneHeaderChrome(appearanceMode: appearanceMode)
        .modifier(PaneHeaderReorderModifier(role: reorderRole))
    }

    private var titleUsesEnglishBrand: Bool {
        title.unicodeScalars.allSatisfy(\.isASCII)
    }
}

struct PaneHeaderReorderModifier: ViewModifier {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var dragActive = false
    @State private var hovering = false
    @State private var cursorPushed = false

    var role: WorkspacePaneRole?

    func body(content: Content) -> some View {
        if let role {
            content
                .overlay {
                    if dragActive {
                        HStack {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(WeiBeiTheme.cinnabar.opacity(0.62))
                                .frame(width: 2, height: 28)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .transition(WeiBeiTransition.floating)
                    }
                }
                .contentShape(Rectangle())
                .offset(y: hovering || dragActive ? -1 : 0)
                .scaleEffect(dragActive ? 1.01 : hovering ? 1.004 : 1, anchor: .top)
                .textSelection(.disabled)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onChanged { value in
                            guard abs(value.translation.width) > 2 else { return }
                            withAnimation(WeiBeiMotion.micro) {
                                if !dragActive {
                                    store.beginThreePaneReorder(role)
                                }
                                dragActive = true
                            }
                            store.updateThreePaneReorder(role, horizontalDelta: value.translation.width)
                        }
                        .onEnded { value in
                            withAnimation(WeiBeiMotion.layout) {
                                store.finishThreePaneReorder(role, horizontalDelta: value.translation.width)
                            }
                            withAnimation(WeiBeiMotion.micro) {
                                dragActive = false
                            }
                        }
                )
                .onHover { value in
                    withAnimation(WeiBeiMotion.hover) {
                        hovering = value
                    }
                    updateCursor(isHovering: value)
                }
                .onChange(of: store.normalizedThreePaneOrder) { _, _ in
                    if dragActive {
                        withAnimation(WeiBeiMotion.micro) {
                            dragActive = false
                        }
                    }
                }
                .onDisappear {
                    if dragActive {
                        store.cancelThreePaneReorder()
                    }
                    popCursorIfNeeded()
                }
                .animation(WeiBeiMotion.hover, value: hovering)
        } else {
            content
        }
    }

    private func updateCursor(isHovering: Bool) {
        if isHovering, !cursorPushed {
            NSCursor.openHand.push()
            cursorPushed = true
        } else if !isHovering {
            popCursorIfNeeded()
        }
    }

    private func popCursorIfNeeded() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

private struct AgentComposerField: View {
    @EnvironmentObject private var store: WorkspaceStore
    var prompt: String
    var focused: FocusState<Bool>.Binding
    var font: Font
    var promptFont: Font
    var lineLimit: ClosedRange<Int>
    var height: CGFloat
    var sendButtonSize: CGFloat
    var trailingPadding: CGFloat
    var sendTrailing: CGFloat
    var sendBottom: CGFloat
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 0
    var submit: () -> Void

    private var canSend: Bool {
        !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsControl: Bool {
        store.isAskingAgent || canSend
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TextField(
                "",
                text: $store.agentDraft,
                prompt: Text(prompt)
                    .font(promptFont)
                    .foregroundStyle(WeiBeiTheme.placeholderInk),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .font(font)
            .foregroundColor(WeiBeiTheme.ink)
            .focused(focused)
            .onSubmit(submit)
            .padding(.vertical, verticalPadding)
            .padding(.trailing, showsControl ? trailingPadding : 0)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .weibeiInputSurface(active: focused.wrappedValue, height: height, horizontalPadding: horizontalPadding)

            if showsControl {
                Button {
                    store.isAskingAgent ? store.cancelAgentRequest() : submit()
                } label: {
                    Image(systemName: store.isAskingAgent ? "stop.fill" : "paperplane.fill")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: sendButtonSize, prominence: store.isAskingAgent ? .neutral : .primary))
                .accessibilityLabel(Text(store.isAskingAgent ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send")))
                .help(store.isAskingAgent ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send"))
                .keyboardShortcut(.return, modifiers: [.command])
                .padding(.trailing, sendTrailing)
                .padding(.bottom, sendBottom)
                .transition(WeiBeiTransition.floating)
                .animation(WeiBeiMotion.micro, value: showsControl)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focused.wrappedValue = true
        }
        .animation(WeiBeiMotion.micro, value: showsControl)
    }
}

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

private struct NotebookCreationPanel: View {
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
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onSelectionChange: (String, CGPoint?) -> Void = { _, _ in }
    var onContentHeightChange: () -> Void = {}
    @State private var command: NoteEditorCommand?
    @State private var contentHeight: CGFloat = 44

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
                contentHeight = height
                onContentHeightChange()
            },
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut
        )
        .background(compact ? Color.clear : WeiBeiTheme.paper)
        .frame(height: compact && fitsContentHeight ? max(contentHeight, 44) : nil)
    }
}

private struct AgentRailTurn {
    var id: UUID
    var startMessageID: UUID
    var startIndex: Int
    var question: String
    var answer: String
}

struct AgentPaneView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var showsPaneHeader = true
    var reorderRole: WorkspacePaneRole? = nil
    @FocusState private var draftFocused: Bool
    @State private var visibleAgentMessageID: UUID?
    @State private var activeAgentRailID: String?
    @State private var agentFollowsLatest = true
    @State private var agentInputTrayHeight: CGFloat = 108

    private let agentBottomAnchorID = "agentConversationBottom"

    var body: some View {
        GeometryReader { paneGeometry in
            let railOnly = ContentRailMetrics.isRailOnly(
                availableWidth: paneGeometry.size.width,
                allowed: store.layout.allowsRailOnlyPanes
            )
            let railItems = agentRailItems
            ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        if showsPaneHeader {
                            WeiBeiPaneHeader(
                                title: store.ui("对话", "Chat"),
                                latinMark: store.interfaceLanguage == .chinese ? "CHAT" : nil,
                                subtitle: store.agentConversationSubtitle,
                                appearanceMode: store.appearanceMode,
                                reorderRole: reorderRole
                            ) {
                                sessionMenu
                            }
                        }

                        GeometryReader { geometry in
                            let availableWidth = max(geometry.size.width, 1)
                            let contentWidth = min(max(availableWidth - 36, 320), agentContentMaxWidth ?? 736)

                            ScrollView(showsIndicators: true) {
                                LazyVStack(alignment: .leading, spacing: 12) {
                                    ForEach(store.messages) { message in
                                        agentMessageRow(message: message, geometryWidth: geometry.size.width, contentWidth: contentWidth, proxy: proxy)
                                    }
                                    if store.isAskingAgent && !store.agentStreamingText.isEmpty {
                                        AgentStreamingResponse(text: store.agentStreamingText)
                                            .id("agent-streaming-response")
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
                                    Color.clear
                                        .frame(height: agentScrollBottomInset)
                                        .id(agentBottomAnchorID)
                                }
                                .scrollTargetLayout()
                                .padding(14)
                                .padding(.top, store.messages.isEmpty ? 22 : 0)
                                .frame(width: geometry.size.width, alignment: .topLeading)
                                .frame(minHeight: geometry.size.height, alignment: .topLeading)
                                .animation(WeiBeiMotion.panel, value: store.messages.count)
                            }
                            .scrollPosition(id: $visibleAgentMessageID, anchor: .center)
                        }
                        .clipped()
                        .zIndex(0)

                        agentInputTray
                            .zIndex(1)
                            .background {
                                GeometryReader { trayGeometry in
                                    Color.clear.preference(
                                        key: AgentInputTrayHeightKey.self,
                                        value: trayGeometry.size.height
                                    )
                                }
                            }
                    }
                    .opacity(railOnly ? 0 : 1)
                    .allowsHitTesting(!railOnly)

                    ContentRailView(
                        label: store.ui("对话轨道", "Conversation rail"),
                        items: railItems,
                        activeID: activeAgentRailID ?? railItems.first?.id,
                        appearanceMode: store.appearanceMode,
                        isRailOnly: railOnly,
                        availableWidth: paneGeometry.size.width,
                        topInset: railOnly ? 0 : (showsPaneHeader ? 44 : 34),
                        bottomInset: railOnly ? 0 : agentRailBottomInset,
                        onActivate: { activateAgentRailItem($0, railOnly: railOnly, proxy: proxy) }
                    )
                    .zIndex(4)
                }
                .onChange(of: store.messages.count) { _, _ in
                    scrollAgentToBottom(proxy)
                }
                .onChange(of: visibleAgentMessageID) { _, messageID in
                    updateAgentRailPosition(for: messageID)
                }
                .onPreferenceChange(AgentInputTrayHeightKey.self) { height in
                    guard height > 40 else { return }
                    let nextHeight = min(max(height, 76), 180)
                    guard abs(agentInputTrayHeight - nextHeight) > 0.5 else { return }
                    agentInputTrayHeight = nextHeight
                    scrollAgentToBottom(proxy)
                }
                .onRichAnswerVerificationStage { stage in
                    handleRichAnswerVerificationStage(stage, proxy: proxy)
                }
            }
        }
        .frame(minHeight: 260)
        .foregroundStyle(WeiBeiTheme.ink)
        .background(showsPaneHeader ? WeiBeiTheme.paper : Color.clear)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if showsPaneHeader {
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

                if !showsPaneHeader {
                    ImmersiveHoverTitleView(mark: "CHAT", title: store.agentConversationSubtitle, appearanceMode: store.appearanceMode, reorderRole: reorderRole)
                }
            }
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
        }
    }

    private func agentMessageRow(message: AgentMessage, geometryWidth: CGFloat, contentWidth: CGFloat, proxy: ScrollViewProxy) -> some View {
        let isUser = message.role == .user
        let wideFamilies: Set<RichAnswerCapabilityFamily> = [
            .quantityAndCoordinates,
            .processAndState,
            .timeAndSpace,
            .imageAndOverlay,
            .comparisonAndEvaluation,
        ]
        let needsWideCanvas = message.richAnswer?.scenes.contains {
            wideFamilies.contains($0.family)
        } == true
        let readingLimit: CGFloat = needsWideCanvas ? 620 : 596
        let readingWidth = min(max(contentWidth - 28, 240), readingLimit)
        let readingLeadingInset = max((geometryWidth - readingWidth) / 2, 0)

        return AgentBubble(
            message: message,
            onMarkdownHeightChange: message.id == store.messages.last?.id ? {
                scrollAgentToBottom(proxy)
            } : {}
        )
        .frame(maxWidth: readingWidth, alignment: isUser ? .trailing : .leading)
        .padding(.leading, readingLeadingInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(message.id)
        .transition(WeiBeiTransition.message)
    }

    private var agentRailTurns: [AgentRailTurn] {
        var turns: [AgentRailTurn] = []
        for (index, message) in store.messages.enumerated() {
            switch message.role {
            case .user:
                turns.append(AgentRailTurn(
                    id: message.id,
                    startMessageID: message.id,
                    startIndex: index,
                    question: message.text,
                    answer: ""
                ))
            case .assistant:
                if turns.isEmpty {
                    turns.append(AgentRailTurn(
                        id: message.id,
                        startMessageID: message.id,
                        startIndex: index,
                        question: store.ui("对话回复", "Response"),
                        answer: message.text
                    ))
                } else if turns[turns.count - 1].answer.isEmpty {
                    turns[turns.count - 1].answer = message.text
                } else {
                    turns[turns.count - 1].answer += "\n\n" + message.text
                }
            }
        }
        return turns
    }

    private var agentRailItems: [ContentRailItem] {
        let turns = agentRailTurns
        return turns.enumerated().map { index, turn in
            ContentRailItem(
                id: "chat-turn-\(turn.id.uuidString)",
                position: turns.count > 1 ? CGFloat(index) / CGFloat(turns.count - 1) : 0,
                title: railText(turn.question, fallback: store.ui("第 \(index + 1) 轮对话", "Conversation \(index + 1)")),
                excerpt: railText(turn.answer, fallback: store.ui("等待回复", "Waiting for response")),
                metadata: store.ui("第 \(index + 1) / \(turns.count) 轮", "Turn \(index + 1) / \(turns.count)")
            )
        }
    }

    private func activateAgentRailItem(_ item: ContentRailItem, railOnly: Bool, proxy: ScrollViewProxy) {
        guard let turn = agentRailTurns.first(where: { "chat-turn-\($0.id.uuidString)" == item.id }) else { return }
        activeAgentRailID = item.id
        agentFollowsLatest = false
        let navigate = {
            withAnimation(WeiBeiMotion.panel) {
                proxy.scrollTo(turn.startMessageID, anchor: .center)
            }
        }
        if railOnly {
            store.requestPaneExpansion(.agent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: navigate)
        } else {
            navigate()
        }
    }

    private func updateAgentRailPosition(for messageID: UUID?) {
        guard let messageID,
              let visibleIndex = store.messages.firstIndex(where: { $0.id == messageID }) else { return }
        agentFollowsLatest = messageID == store.messages.last?.id
        if let turn = agentRailTurns.last(where: { $0.startIndex <= visibleIndex }) {
            activeAgentRailID = "chat-turn-\(turn.id.uuidString)"
        }
    }

    private func railText(_ value: String, fallback: String) -> String {
        let collapsed = value
            .replacingOccurrences(of: #"[`*_>#\[\]()]"#, with: "", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.isEmpty ? fallback : String(collapsed.prefix(180))
    }

    private var agentPrompt: String {
        store.agentInputPrompt
    }

    private var agentInputTray: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .clear,
                    WeiBeiTheme.paper.opacity(0.18),
                    WeiBeiTheme.glassTint.opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 22)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                if store.hasSelectionAttachments {
                    AgentSelectionAttachmentPill()
                        .transition(WeiBeiTransition.floating)
                }

                AgentComposerField(
                    prompt: agentPrompt,
                    focused: $draftFocused,
                    font: .system(size: 15),
                    promptFont: .system(size: 15),
                    lineLimit: 1...6,
                    height: 56,
                    sendButtonSize: 30,
                    trailingPadding: 40,
                    sendTrailing: 10,
                    sendBottom: 10,
                    horizontalPadding: 14,
                    verticalPadding: 10
                ) {
                    store.askAgent()
                }
            }
            .font(.system(size: 15))
            .frame(minHeight: 56, alignment: .bottom)
            .frame(maxWidth: agentInputMaxWidth)
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(WeiBeiTheme.paper)
            .animation(WeiBeiMotion.reveal, value: store.agentDraft)
        }
        .background(alignment: .bottom) {
            WeiBeiGlassHeaderBackground(
                paperOpacity: showsPaneHeader ? 0.34 : 0.14,
                materialOpacity: showsPaneHeader ? 0.04 : 0.02
            )
            .mask(
                LinearGradient(
                    colors: [.clear, WeiBeiTheme.ink.opacity(0.42), WeiBeiTheme.ink.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var agentInputMaxWidth: CGFloat? {
        620
    }

    private var agentContentMaxWidth: CGFloat? {
        736
    }

    private var agentScrollBottomInset: CGFloat {
        let baseInset = min(max(agentInputTrayHeight * 0.42, 42), 82)
        return hasVisibleRichAnswer ? max(baseInset, agentInputTrayHeight + 22) : baseInset
    }

    private var hasVisibleRichAnswer: Bool {
        store.messages.contains { message in
            message.richAnswer?.mode == .rich && message.richAnswer?.scenes.isEmpty == false
        }
    }

    private var agentRailBottomInset: CGFloat {
        min(max(agentInputTrayHeight + 10, 88), 190)
    }

    private var emptyAgentState: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: starterChipColumns, alignment: .leading, spacing: 6) {
                if store.canResumePreviousStudy {
                    starterChip(store.ui("继续上次", "Resume"), systemImage: "arrow.uturn.forward", help: store.ui("回顾上次学习位置并继续", "Review the last study location and continue")) {
                        store.resumePreviousStudy()
                        askWith(store.ui("上次学到哪了？请结合学习记忆告诉我当时的位置、还没解决的问题和现在最适合的下一步。", "Where did I stop last time? Use my learning memory to give the location, unresolved questions, and the best next step."))
                    }
                }
                if store.allItems.count > 1 {
                    starterChip(store.ui("关联", "Connections"), systemImage: "point.3.connected.trianglepath.dotted", help: store.ui("查找当前概念在课程里的关联", "Find related course materials and notes")) {
                        askWith(store.ui("请查找当前材料、选区或笔记在整个课程里的知识关联，说清为什么相关，并给出可跳转的来源。", "Find connections between the current material, selection, or note and the rest of the course. Explain each connection and provide jumpable sources."))
                    }
                }
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
        .frame(maxWidth: 420, alignment: .leading)
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
        store.askAgent()
    }

    private var sessionMenu: some View {
        Menu {
            Button {
                store.createStudySession()
            } label: {
                Label(store.ui("新学习会话", "New Study Session"), systemImage: "plus")
            }

            Divider()

            ForEach(store.orderedStudySessions) { session in
                Button {
                    store.activateStudySession(session.id)
                } label: {
                    if session.id == store.activeStudySessionID {
                        Label(session.title, systemImage: "checkmark")
                    } else {
                        Text(session.title)
                    }
                }
            }

            if !store.orderedLearningMemoryEntries.isEmpty {
                Divider()
                Menu {
                    ForEach(Array(store.orderedLearningMemoryEntries.prefix(20))) { memory in
                        if memory.status == .resolved {
                            Button {
                                store.restoreLearningMemory(memory.id)
                            } label: {
                                Label(
                                    "\(store.learningMemoryKindLabel(memory.kind))：\(String(memory.text.prefix(64)))",
                                    systemImage: "arrow.uturn.backward"
                                )
                            }
                        } else if memory.kind == .goal || memory.kind == .confusion || memory.kind == .nextStep {
                            Button {
                                store.resolveLearningMemory(memory.id)
                            } label: {
                                Label(
                                    "\(store.learningMemoryKindLabel(memory.kind))：\(String(memory.text.prefix(64)))",
                                    systemImage: "checkmark.circle"
                                )
                            }
                        } else {
                            Label(
                                "\(store.learningMemoryKindLabel(memory.kind))：\(String(memory.text.prefix(64)))",
                                systemImage: "brain.head.profile"
                            )
                        }
                    }
                } label: {
                    Label(store.ui("学习记忆", "Learning Memory"), systemImage: "brain.head.profile")
                }
            }

            if store.hasCurrentSessionInferredMemory {
                Divider()
                Button(role: .destructive) {
                    store.clearCurrentSessionInferredMemory()
                } label: {
                    Label(store.ui("清除本会话推断记忆", "Clear Inferred Memory"), systemImage: "brain.head.profile")
                }
            }

            if let activeID = store.activeStudySessionID, store.studySessions.count > 1 {
                Button(role: .destructive) {
                    store.deleteStudySession(activeID)
                } label: {
                    Label(store.ui("删除当前会话", "Delete Current Session"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 24))
        .accessibilityLabel(Text(store.ui("学习会话", "Study Sessions")))
        .help(store.ui("新建或切换学习会话", "Create or switch study sessions"))
    }

    private func scrollAgentToBottom(_ proxy: ScrollViewProxy) {
        guard agentFollowsLatest else { return }
        DispatchQueue.main.async {
            withAnimation(WeiBeiMotion.panel) {
                proxy.scrollTo(agentBottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func handleRichAnswerVerificationStage(
        _ stage: RichAnswerVerificationStage,
        proxy: ScrollViewProxy
    ) {
        guard stage == .overview || stage == .before || stage == .after,
              let targetID = latestRichAnswerSceneAnchorID else { return }
        agentFollowsLatest = false
        DispatchQueue.main.async {
            proxy.scrollTo(targetID, anchor: .top)
        }
    }

    private var latestRichAnswerSceneAnchorID: String? {
        for message in store.messages.reversed() {
            guard let richAnswer = message.richAnswer,
                  richAnswer.mode == .rich,
                  !richAnswer.scenes.isEmpty else { continue }
            for (index, part) in richAnswer.resolvedParts.enumerated() {
                guard case .scene = part.kind,
                      let sceneID = part.sceneID else { continue }
                return "rich-answer-\(message.id.uuidString)-\(sceneID)-\(index)"
            }
        }
        return nil
    }

}

private struct AgentInputTrayHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 108

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
            HStack(spacing: 4) {
                // Popover anchor is only the label — keep the clear button outside so the first
                // click is not eaten by hover-popover dismissal.
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 11, weight: .medium))
                    Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments"))
                        .font(.system(size: 12, weight: .medium))
                }
                .contentShape(Rectangle())
                .onHover { value in
                    setPillHovering(value)
                }
                .popover(isPresented: popoverPresented, arrowEdge: .bottom) { popoverContent }

                Button(action: clearAllAttachments) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 18))
                .accessibilityLabel(Text(store.ui("清空已选文本片段", "Clear selected text fragments")))
                .help(store.ui("清空已选文本片段", "Clear selected text fragments"))
            }
            .foregroundStyle(pillHovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .frame(height: 28)
            .background(WeiBeiTheme.paperRaised.opacity(pillHovering ? 0.72 : 0.54))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(pillHovering ? 0.68 : 0.38), lineWidth: 1)
            }
            .accessibilityLabel(Text(store.ui("\(store.selectionAttachments.count) 个已选文本片段", "\(store.selectionAttachments.count) selected text fragments")))
            .help(store.ui("悬停查看选区", "Hover to preview selections"))
        }
    }

    private func clearAllAttachments() {
        closeToken = UUID()
        pillHovering = false
        popoverHovering = false
        store.clearSelectionAttachments()
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
                Button(store.ui("清空", "Clear")) {
                    clearAllAttachments()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .help(store.ui("清空全部选区片段", "Clear all selected fragments"))
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
                    let shouldClose = store.selectionAttachments.count <= 1
                    closeToken = UUID()
                    store.removeSelectionAttachment(id: selection.id)
                    if shouldClose {
                        pillHovering = false
                        popoverHovering = false
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: 20))
                .accessibilityLabel(Text(store.ui("移除片段 \(index + 1)", "Remove fragment \(index + 1)")))
                .help(store.ui("移除这个选区片段", "Remove this selected fragment"))
            }

            Text(selection.text)
                .font(.system(size: 12))
                .lineSpacing(3)
                .lineLimit(5)
                .foregroundStyle(WeiBeiTheme.ink)
                .allowsHitTesting(false)
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

private struct CompactAgentMessagePreviewList: View {
    @EnvironmentObject private var store: WorkspaceStore
    var maxMessages: Int
    var maxHeight: CGFloat

    var body: some View {
        if !messages.isEmpty || store.isAskingAgent {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(messages) { message in
                        CompactAgentMessagePreviewRow(message: message)
                            .transition(WeiBeiTransition.message)
                    }
                    if store.isAskingAgent {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text(store.ui("正在读上下文", "Reading context"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(1)
            }
            .frame(maxHeight: maxHeight)
            .animation(WeiBeiMotion.panel, value: store.messages.count)
        }
    }

    private var messages: [AgentMessage] {
        Array(store.messages.suffix(maxMessages))
    }
}

private struct CompactAgentMessagePreviewRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    var message: AgentMessage
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(speakerTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(speakerColor)
                if let source = message.source {
                    Text(source)
                        .font(.system(size: 10))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text(renderedText)
                .font(.system(size: 12))
                .foregroundStyle(WeiBeiTheme.ink)
                .lineSpacing(2)
                .lineLimit(message.role == .user ? 2 : 5)
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(speakerColor.opacity(hovering ? 0.66 : 0.38))
                .frame(width: 2, height: hovering ? 28 : 20)
                .padding(.leading, 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(hovering ? 0.56 : 0.26), lineWidth: 1)
        }
        .onHover { value in
            withAnimation(WeiBeiMotion.hover) {
                hovering = value
            }
        }
    }

    private var speakerTitle: String {
        message.role == .user ? store.ui("你", "You") : store.appDisplayName
    }

    private var speakerColor: Color {
        message.role == .user ? WeiBeiTheme.link : WeiBeiTheme.cinnabar
    }

    private var displayText: String {
        message.text
            .replacingOccurrences(of: "\n\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var renderedText: AttributedString {
        (try? AttributedString(markdown: displayText)) ?? AttributedString(displayText)
    }

    private var rowBackground: Color {
        if message.role == .user {
            return WeiBeiTheme.paperInset.opacity(hovering ? 0.36 : 0.24)
        }
        return WeiBeiTheme.paperRaised.opacity(hovering ? 0.42 : 0.28)
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

            CompactAgentMessagePreviewList(maxMessages: 2, maxHeight: 168)

            AgentComposerField(
                prompt: drawerPrompt,
                focused: $draftFocused,
                font: .system(size: 13),
                promptFont: .system(size: 13),
                lineLimit: 1...4,
                height: 46,
                sendButtonSize: 34,
                trailingPadding: 44,
                sendTrailing: 6,
                sendBottom: 6
            ) {
                store.askAgent()
            }

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

            CompactAgentMessagePreviewList(maxMessages: 2, maxHeight: 138)

            AgentComposerField(
                prompt: agentPrompt,
                focused: $draftFocused,
                font: .system(size: 13),
                promptFont: .system(size: 13),
                lineLimit: 1...4,
                height: 44,
                sendButtonSize: WeiBeiMetric.iconButton,
                trailingPadding: 38,
                sendTrailing: 5,
                sendBottom: 5
            ) {
                store.askAgent()
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
        .onChange(of: store.selectionContext) { previous, next in
            guard !store.pinnedFloatingAgent else { return }
            // Same content with a new id (or drag ticks) must not re-spring the capsule.
            let sameContent = previous?.text == next?.text
                && previous?.source == next?.source
                && previous?.ownerTitle == next?.ownerTitle
                && previous?.isEditable == next?.isEditable
            guard !sameContent else { return }
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

            AgentComposerField(
                prompt: store.ui("继续追问", "Ask a follow-up"),
                focused: $draftFocused,
                font: .caption,
                promptFont: .caption,
                lineLimit: 1...2,
                height: 34,
                sendButtonSize: 22,
                trailingPadding: 30,
                sendTrailing: 6,
                sendBottom: 6,
                horizontalPadding: 8
            ) {
                sendDraft()
            }
        }
        .padding(10)
        .frame(width: CGFloat(SelectionFloatingAgentPlacement.expandedHalfWidth * 2), alignment: .leading)
        .onAppear {
            draftFocused = true
        }
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
        message.text.contains("## 离线草稿")
            || message.text.contains("## Offline Draft")
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
        store.askAgent()
    }

    private func sendDraft() {
        guard !store.isAskingAgent,
              !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
        }
        store.askAgent()
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

private struct AgentBubble: View {
    @EnvironmentObject private var store: WorkspaceStore
    var message: AgentMessage
    var onMarkdownHeightChange: () -> Void = {}
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
        // Quiet paper chip on the right edge: role is encoded by position + surface,
        // so no "你" label, no accent rail, no messenger chrome.
        VStack(alignment: .trailing, spacing: 5) {
            if let source = message.source {
                Text(source)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.86))
                    .lineLimit(1)
                    .padding(.trailing, 2)
            }

            AgentMessageMarkdownText(
                text: message.text,
                rendersRichMarkdown: false,
                onContentHeightChange: onMarkdownHeightChange
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(userBubbleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(userBubbleStroke, lineWidth: 1)
                    }
                    .shadow(
                        color: WeiBeiTheme.ink.opacity(store.appearanceMode == .inkstone ? 0.0 : (hovering ? 0.055 : 0.035)),
                        radius: hovering ? 5 : 3.5,
                        y: hovering ? 1.5 : 1
                    )
            }
            .frame(maxWidth: 520, alignment: .trailing)
        }
        .weibeiHoverLift(active: hovering, amount: 0.6)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var userBubbleFill: Color {
        // Same paper family as chips/panels: a slightly raised slip of paper, not a tinted chat blob.
        store.appearanceMode == .inkstone
            ? WeiBeiTheme.paperRaised.opacity(hovering ? 0.58 : 0.46)
            : WeiBeiTheme.paperRaised.opacity(hovering ? 1.0 : 0.96)
    }

    private var userBubbleStroke: Color {
        store.appearanceMode == .inkstone
            ? WeiBeiTheme.hairline.opacity(hovering ? 0.58 : 0.42)
            : WeiBeiTheme.hairline.opacity(hovering ? 0.52 : 0.38)
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
                .padding(.leading, hasRenderableRichAnswer ? 0 : 20)
                .padding(.trailing, hasRenderableRichAnswer ? 0 : 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    if !hasRenderableRichAnswer {
                        Capsule()
                            .fill(assistantMarkColor.opacity(hovering ? 1.0 : 0.72))
                            .frame(width: 2, height: hovering ? 34 : 24)
                            .padding(.leading, 4)
                    }
                }
        }
    }

    private var regularMessageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            messageMetadata

            if let richAnswer = message.richAnswer,
               richAnswer.mode == .rich,
               !richAnswer.scenes.isEmpty {
                richAnswerFlow(richAnswer)
            } else {
                AgentMessageMarkdownText(
                    text: message.text,
                    rendersRichMarkdown: true,
                    onContentHeightChange: onMarkdownHeightChange
                )
            }

            if message.id == store.lastUsableAgentAnswerID {
                if let update = store.latestAgentLearningUpdate,
                   !update.entries.isEmpty || !update.resolutions.isEmpty || !update.suggestedNext.isEmpty {
                    learningUpdateContent(update)
                }
                if let proposal = store.latestAgentNoteProposal, !proposal.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.ui("依据", "Evidence"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                        ForEach(Array(proposal.evidence.enumerated()), id: \.offset) { _, evidence in
                            Text("• \(evidence)")
                                .font(.caption)
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                HStack(spacing: 6) {
                    if store.selectionContext != nil {
                        Button(store.ui("摘录", "Excerpt")) {
                            store.appendSelectionToNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    Button(store.agentWriteActionTitle) {
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

    @ViewBuilder
    private func richAnswerFlow(_ presentation: RichAnswerPresentation) -> some View {
        ForEach(Array(presentation.resolvedParts.enumerated()), id: \.offset) { index, part in
            switch part.kind {
            case .narrative:
                if let text = part.text, !text.isEmpty {
                    RichAnswerNarrativeText(text: text)
                        .frame(maxWidth: 588, alignment: .leading)
                }
            case .scene:
                if let sceneID = part.sceneID,
                   let scopedPresentation = scopedRichAnswer(presentation, sceneID: sceneID) {
                    RichAnswerHost(
                        presentation: scopedPresentation,
                        onOpenEvidence: openRichAnswerEvidence,
                        onOpenAsset: openRichAnswerAsset,
                        assetPreview: richAnswerAssetPreview,
                        onAction: submitRichAnswerAction
                    )
                    .id("rich-answer-\(message.id.uuidString)-\(sceneID)-\(index)")
                    .frame(maxWidth: 620, alignment: .leading)
                }
            }
        }
    }

    private func scopedRichAnswer(
        _ presentation: RichAnswerPresentation,
        sceneID: String
    ) -> RichAnswerPresentation? {
        guard let scene = presentation.scenes.first(where: { $0.id == sceneID }) else { return nil }
        var scoped = presentation
        scoped.scenes = [scene]
        scoped.parts = nil
        let evidenceIDs = Set(scene.evidenceIDs)
        scoped.evidenceLedger = presentation.evidenceLedger.filter { evidenceIDs.contains($0.id) }
        return scoped
    }

    private func submitRichAnswerAction(_ prompt: String) {
        guard !store.isAskingAgent else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.agentDraft = trimmed
        store.askAgent()
    }

    private func learningUpdateContent(_ update: StudyAgentLearningUpdate) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(store.ui("本轮记住", "Remembered This Turn"), systemImage: "brain.head.profile")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)

            ForEach(Array(update.entries.prefix(4).enumerated()), id: \.offset) { _, entry in
                Text("\(memoryKindLabel(entry.kind))：\(entry.text)")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(update.resolutions.prefix(4).enumerated()), id: \.offset) { _, resolution in
                let isResolved = store.isLearningMemoryResolved(resolution.memoryID)
                HStack(alignment: .top, spacing: 6) {
                    Text(store.ui("建议结案：\(resolution.text)", "Suggested resolution: \(resolution.text)"))
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button {
                        if isResolved {
                            store.restoreLearningMemoryResolution(resolution)
                        } else {
                            store.confirmLearningMemoryResolution(resolution)
                        }
                    } label: {
                        Image(systemName: isResolved ? "arrow.uturn.backward" : "checkmark.circle")
                    }
                    .buttonStyle(WeiBeiIconButtonStyle(active: isResolved, size: 22))
                    .help(store.ui(isResolved ? "撤销结案" : "确认结案", isResolved ? "Undo resolution" : "Confirm resolution"))
                }
            }

            ForEach(Array(update.suggestedNext.prefix(3).enumerated()), id: \.offset) { _, next in
                Text("→ \(next)")
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.link)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 9)
        .padding(.vertical, 5)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(WeiBeiTheme.cinnabar.opacity(0.34))
                .frame(width: 1)
        }
    }

    private func memoryKindLabel(_ kind: LearningMemoryKind) -> String {
        switch kind {
        case .goal:
            return store.ui("目标", "Goal")
        case .understood:
            return store.ui("已理解", "Understood")
        case .confusion:
            return store.ui("困惑", "Confusion")
        case .nextStep:
            return store.ui("下一步", "Next Step")
        case .preference:
            return store.ui("偏好", "Preference")
        }
    }

    private var messageMetadata: some View {
        HStack(spacing: 6) {
            Text("WeiBei")
                .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
            if let backend = message.backend {
                Text(backendLabel(backend))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
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
    }

    private var credentialNoticeContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.ui("需要设置密钥", "Key Required"))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Text(displayText)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .allowsHitTesting(false)
        }
    }

    private func openRichAnswerEvidence(_ evidence: RichAnswerEvidence) {
        var label = evidence.sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.hasPrefix("["), label.hasSuffix("]"), label.count > 2 {
            label = String(label.dropFirst().dropLast())
        }
        for prefix in ["材料：", "笔记：", "选区："] where label.hasPrefix(prefix) {
            label = String(label.dropFirst(prefix.count))
            break
        }
        guard !label.isEmpty else { return }
        store.openSourceReference("来源：\(label)")
    }

    private func openRichAnswerAsset(_ assetID: String) {
        withAnimation(WeiBeiMotion.panel) {
            store.select(itemID: assetID)
        }
    }

    private func richAnswerAssetPreview(_ assetID: String) -> NSImage? {
        guard let item = store.item(withID: assetID), let url = item.url else { return nil }
        if item.kind == .pdf,
           let page = PDFDocument(url: url)?.page(at: 0) {
            return page.thumbnail(of: NSSize(width: 1200, height: 1500), for: .mediaBox)
        }
        return NSImage(contentsOf: url)
    }

    private var isUser: Bool {
        message.role == .user
    }

    private var hasRenderableRichAnswer: Bool {
        message.richAnswer?.mode == .rich && message.richAnswer?.scenes.isEmpty == false
    }

    private var isCredentialNotice: Bool {
        message.role == .assistant
            && (message.text.hasPrefix("未配置密钥") || message.text.hasPrefix("未配置 OPENAI_API_KEY") || message.text.hasPrefix("No key is configured"))
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
        message.text.contains("## 离线草稿")
            || message.text.contains("## Offline Draft")
    }

    private var assistantMarkColor: Color {
        (isCredentialNotice || isOfflineContextPreview) ? WeiBeiTheme.link.opacity(0.42) : WeiBeiTheme.cinnabar.opacity(0.50)
    }

    private func backendLabel(_ backend: StudyAgentBackend) -> String {
        switch backend {
        case .pi: return "PI"
        case .openAI: return "API"
        case .offline: return store.ui("离线", "Offline")
        }
    }
}

private struct RichAnswerNarrativeText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case let .heading(level):
                    Text(attributed(block.text))
                        .font(.system(size: level <= 2 ? 21 : 17, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                case .paragraph:
                    Text(attributed(block.text))
                        .font(.system(size: 14))
                        .lineSpacing(4)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(WeiBeiTheme.cinnabar)
                        Text(attributed(block.text))
                            .font(.system(size: 14))
                            .lineSpacing(4)
                            .foregroundStyle(WeiBeiTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .quote:
                    Text(attributed(block.text))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(WeiBeiTheme.hairline.opacity(0.72))
                                .frame(width: 1)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            result.append(Block(kind: .paragraph, text: paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                flushParagraph()
                continue
            }
            if isStandaloneSourceReference(line) {
                flushParagraph()
                continue
            }
            let headingMarkers = line.prefix { $0 == "#" }.count
            if headingMarkers > 0, headingMarkers <= 6, line.dropFirst(headingMarkers).first == " " {
                flushParagraph()
                result.append(
                    Block(
                        kind: .heading(level: headingMarkers),
                        text: String(line.dropFirst(headingMarkers)).trimmingCharacters(in: .whitespaces)
                    )
                )
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                result.append(Block(kind: .bullet, text: String(line.dropFirst(2))))
                continue
            }
            if line.hasPrefix("> ") {
                flushParagraph()
                result.append(Block(kind: .quote, text: String(line.dropFirst(2))))
                continue
            }
            paragraphLines.append(line)
        }
        flushParagraph()
        return result
    }

    private func isStandaloneSourceReference(_ line: String) -> Bool {
        guard line.hasPrefix("["), line.hasSuffix("]") else { return false }
        return ["[材料：", "[笔记：", "[选区："].contains { line.hasPrefix($0) }
    }

    private func attributed(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value)) ?? AttributedString(value)
    }

    private struct Block {
        enum Kind {
            case heading(level: Int)
            case paragraph
            case bullet
            case quote
        }

        let kind: Kind
        let text: String
    }
}

private struct AgentMessageMarkdownText: View {
    @EnvironmentObject private var store: WorkspaceStore
    var text: String
    var rendersRichMarkdown: Bool
    var onContentHeightChange: () -> Void = {}

    var body: some View {
        if rendersRichMarkdown {
            MarkdownPreviewView(
                markdown: text,
                markdownBaseURL: store.currentMarkdownBaseURL,
                appearanceMode: store.appearanceMode,
                interfaceLanguage: store.interfaceLanguage,
                compact: true,
                onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
                onSourceReference: { reference in store.openSourceReference(reference) },
                onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) },
                onContentHeightChange: onContentHeightChange
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(renderedText)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(WeiBeiTheme.ink)
                .allowsHitTesting(false)
        }
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
            Text(store.agentActivityText ?? store.ui("正在读取上下文", "Reading context"))
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

private struct AgentStreamingResponse: View {
    @EnvironmentObject private var store: WorkspaceStore
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("WeiBei")
                    .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
                Text("PI")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            AgentMessageMarkdownText(text: text, rendersRichMarkdown: false)
        }
        .padding(.vertical, 10)
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(WeiBeiTheme.cinnabar.opacity(0.42))
                .frame(width: 2, height: 24)
                .padding(.leading, 4)
        }
        .accessibilityLabel(Text(store.ui("PI 正在回答", "PI is responding")))
    }
}
