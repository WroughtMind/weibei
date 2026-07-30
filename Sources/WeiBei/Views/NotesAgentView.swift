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
        weibeiPaneHeaderChrome(appearanceMode: appearanceMode, compact: false)
    }

    func weibeiPaneHeaderChrome(appearanceMode: WeiBeiAppearanceMode, compact: Bool) -> some View {
        self
            .padding(.horizontal, compact ? 10 : 16)
            .frame(height: compact ? 44 : 54)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.72, materialOpacity: 0.12))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(WeiBeiTheme.glassHighlight.opacity(0.06))
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                // Keep the full fade geometry string for self-check; scale via offset only when compact.
                WeiBeiHeaderHandoffFade(height: 28, opacity: 0.34)
                    .offset(y: compact ? 18 : 28)
                    .scaleEffect(y: compact ? 0.72 : 1, anchor: .top)
            }
            .shadow(color: WeiBeiTheme.ink.opacity(0.012), radius: 7, y: 2)
            .zIndex(1)

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
    /// When the pane is narrow (multi-column), collapse subtitle / latin mark and shrink type.
    var availableWidth: CGFloat = 960
    @ViewBuilder var actions: () -> Actions

    private var isCompactHeader: Bool { availableWidth < 420 }
    private var isTightHeader: Bool { availableWidth < 300 }

    var body: some View {
        let content = HStack(spacing: isCompactHeader ? 6 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(
                        titleUsesEnglishBrand
                            ? WeiBeiTypography.englishBrandFont(size: isCompactHeader ? 15 : 18, weight: .semibold)
                            : .system(size: isCompactHeader ? 15 : 18, weight: .semibold, design: .serif)
                    )
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(2)
                if let latinMark, !isTightHeader {
                    Text(latinMark)
                        .font(WeiBeiTypography.englishBrandFont(size: isCompactHeader ? 8.5 : 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                        .baselineOffset(1)
                        .lineLimit(1)
                        .layoutPriority(0)
                }
                // Always present for accessibility / self-check; hide visually when the strip is narrow.
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .opacity(isCompactHeader ? 0 : 1)
                    .frame(maxWidth: isCompactHeader ? 0 : .infinity, alignment: .leading)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            actions()
                .layoutPriority(3)
        }

        Group {
            if isCompactHeader {
                content
                    .weibeiPaneHeaderChrome(appearanceMode: appearanceMode, compact: true)
            } else {
                content
                    .weibeiPaneHeaderChrome(appearanceMode: appearanceMode)
            }
        }
        .modifier(PaneHeaderReorderModifier(role: reorderRole))
        .accessibilityLabel(Text("\(title). \(subtitle)"))
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
                                .fill(WeiBeiTheme.secondaryInk.opacity(0.42))
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
                            // No withAnimation on drag updates — that was thrashing the whole workspace.
                            if !dragActive {
                                store.beginThreePaneReorder(role)
                                dragActive = true
                            }
                            store.updateThreePaneReorder(role, horizontalDelta: value.translation.width)
                        }
                        .onEnded { value in
                            store.finishThreePaneReorder(role, horizontalDelta: value.translation.width)
                            dragActive = false
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
    /// Cap for immersive grow; nil means fixed compact height.
    var maxHeight: CGFloat? = nil
    var sendButtonSize: CGFloat
    var trailingPadding: CGFloat
    var sendTrailing: CGFloat
    var sendBottom: CGFloat
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 0
    /// Codex-style footer: model chip on the left, send on the right inside the card.
    var showsModelFooter: Bool = false
    var submit: () -> Void

    private var canSend: Bool {
        !store.isStoppingAgent
            && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsControl: Bool {
        store.isAgentRunningInActiveChat || canSend
    }

    private var isWideComposer: Bool { maxHeight != nil || showsModelFooter }

    var body: some View {
        // Compact: fixed short field. Wide: min height, grow with lines up to maxHeight.
        let corner: CGFloat = isWideComposer ? 14 : WeiBeiMetric.controlRadius
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
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
                .padding(.top, verticalPadding)
                .padding(.bottom, showsModelFooter ? 6 : verticalPadding)
                .padding(.trailing, showsModelFooter ? 0 : (showsControl ? trailingPadding : 0))
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, horizontalPadding)

                if showsControl && !showsModelFooter {
                    VStack {
                        Spacer(minLength: 0)
                        HStack {
                            Spacer(minLength: 0)
                            sendButton
                                .padding(.trailing, sendTrailing)
                                .padding(.bottom, sendBottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if showsModelFooter {
                HStack(spacing: 10) {
                    Text(store.modelName.isEmpty ? store.ui("模型", "Model") : store.modelName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if showsControl {
                        sendButton
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 10)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: maxHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: corner)
                .fill(WeiBeiTheme.paperRaised.opacity(focused.wrappedValue ? 0.78 : 0.64))
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay {
            RoundedRectangle(cornerRadius: corner)
                .stroke(
                    focused.wrappedValue ? WeiBeiTheme.link.opacity(0.36) : WeiBeiTheme.hairline.opacity(0.54),
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focused.wrappedValue = true
        }
        .animation(WeiBeiMotion.micro, value: showsControl)
        .accessibilityIdentifier(isWideComposer ? "agent-composer-codex" : "agent-composer-compact")
    }

    private var sendButton: some View {
        Button {
            store.isAgentRunningInActiveChat ? store.cancelAgentRequest() : submit()
        } label: {
            Image(systemName: store.isAgentRunningInActiveChat ? "stop.fill" : "paperplane.fill")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: sendButtonSize, prominence: store.isAgentRunningInActiveChat ? .neutral : .primary))
        .accessibilityLabel(Text(store.isAgentRunningInActiveChat ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send")))
        .help(store.isAgentRunningInActiveChat ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send"))
        .keyboardShortcut(.return, modifiers: [.command])
        .transition(WeiBeiTransition.floating)
        .animation(WeiBeiMotion.micro, value: showsControl)
    }
}

private struct AccessibilityFrameProbe: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        probe.wantsLayer = true
        probe.setAccessibilityElement(true)
        probe.setAccessibilityRole(.group)
        probe.setAccessibilityIdentifier(identifier)
        probe.setAccessibilityLabel("weibei pane frame anchor")
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setAccessibilityIdentifier(identifier)
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
            return WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode.isDark ? 0.44 : 0.62)
        }
        if hovering {
            return WeiBeiTheme.paperRaised.opacity(store.appearanceMode.isDark ? 0.16 : 0.20)
        }
        return Color.clear
    }

    private func noteModeButtonStroke(selected: Bool, hovering: Bool) -> Color {
        if selected {
            return WeiBeiTheme.cinnabar.opacity(store.appearanceMode.isDark ? 0.34 : 0.24)
        }
        if hovering {
            return WeiBeiTheme.hairline.opacity(store.appearanceMode.isDark ? 0.30 : 0.18)
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
                        onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) },
                        onSelectionChange: { text, anchor in
                            store.updateSelection(text, source: .note, anchor: anchor, isEditable: false)
                        }
                    )
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
        let quotePrefixColor = ink.withAlphaComponent(appearanceMode.isDark ? 0.30 : 0.36)
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
    /// Exact point-rounded layout width. Every real 1pt change unfreezes the
    /// existing WebView; the coarser cache bucket is only a first-frame seed.
    var layoutWidthKey: Int = 0
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    var onRenderReady: () -> Void = {}
    var onRenderFailure: () -> Void = {}
    var onSelectionChange: (String, CGPoint?) -> Void = { _, _ in }
    var onContentHeightChange: () -> Void = {}
    private static let compactPreviewLoadingHeight: CGFloat = 44
    private static let compactPreviewMaximumHeight: CGFloat = 20_000

    var onMeasuredHeight: (CGFloat) -> Void = { _ in }
    @State private var command: NoteEditorCommand?
    @State private var contentHeight: CGFloat = Self.compactPreviewLoadingHeight
    @State private var heightFrozen = false
    @State private var lastLayoutWidthKey = 0

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
                let measuredHeight = ceil(height)
                let nextFrameHeight = max(measuredHeight, Self.compactPreviewLoadingHeight)
                // A frozen row ignores same-height/sub-2pt jitter and all
                // shrink reports, but a late image/diagram may still grow it.
                // Width changes explicitly unfreeze below, so their legitimate
                // smaller reflow measurement remains accepted.
                if freezeHeightAfterMeasure,
                   heightFrozen,
                   nextFrameHeight < contentHeight + 2 {
                    return
                }
                // This callback only receives a real JS measurement. Keep its
                // success separate from the 44pt minimum SwiftUI frame so a
                // legitimate short quote/list can reveal and freeze too.
                onMeasuredHeight(measuredHeight)
                // Ignore sub-pixel ResizeObserver jitter once we have a real measure.
                if contentHeight >= Self.compactPreviewLoadingHeight,
                   abs(contentHeight - nextFrameHeight) < 2 {
                    if freezeHeightAfterMeasure {
                        heightFrozen = true
                    }
                    return
                }
                contentHeight = nextFrameHeight
                if freezeHeightAfterMeasure {
                    heightFrozen = true
                }
                onContentHeightChange()
            },
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut,
            onRenderReady: onRenderReady,
            onRenderFailure: onRenderFailure
        )
        .background(compact ? Color.clear : WeiBeiTheme.paper)
        .frame(height: compact && fitsContentHeight ? max(contentHeight, Self.compactPreviewLoadingHeight) : nil)
        .onAppear {
            lastLayoutWidthKey = layoutWidthKey
            if let seed = seedContentHeight, seed.isFinite, seed > 0 {
                contentHeight = max(ceil(seed), Self.compactPreviewLoadingHeight)
            }
            // A 24pt-bucket cache value is only a visual seed. The current
            // point-exact width must still produce its own real measurement.
            heightFrozen = false
        }
        .onChange(of: layoutWidthKey) { _, widthKey in
            guard widthKey != lastLayoutWidthKey else { return }
            lastLayoutWidthKey = widthKey
            // Keep this WKWebView alive; ResizeObserver will report the new
            // height after every real 1pt window / selection-float resize.
            heightFrozen = false
        }
        .onChange(of: markdown) { _, _ in
            guard compact && fitsContentHeight else { return }
            heightFrozen = false
            contentHeight = Self.compactPreviewLoadingHeight
            onContentHeightChange()
        }
    }
}

private struct AgentRailTurn {
    var id: UUID
    var startMessageID: UUID
    var startIndex: Int
    var question: String
    var answer: String
}

/// Standard chat column metrics — one centered axis shared by messages and composer.
/// Compact = three-pane agent strip; wide = immersive conversation (Codex-like full chat).
///
/// Critical: content width must always fit the measured pane. Never invent a floor larger
/// than `availableWidth`, or multi-pane text centers as if the strip were full-window wide.
private enum AgentChatLayoutMetrics {
    static let compactMaxWidth: CGFloat = 560
    /// Immersive conversation: Codex-like centered column that still scales with the window.
    /// Cap keeps line length readable on ultra-wide; floor is handled by usable width.
    static let wideMaxWidth: CGFloat = 920
    static let compactSideGutter: CGFloat = 12
    /// Codex-style: modest side margin; column grows/shrinks with the window.
    static let wideSideGutter: CGFloat = 28
    static let compactComposerHeight: CGFloat = 52
    /// Immersive min height — grows with typed lines; never a giant empty white void.
    static let wideComposerMinHeight: CGFloat = 108
    static let wideComposerMaxHeight: CGFloat = 220
    static let compactFontSize: CGFloat = 14.5
    static let wideFontSize: CGFloat = 16

    static func isWide(layout: WorkspaceLayout) -> Bool {
        // Immersive conversation only — document multi-pane keeps compact strip metrics.
        layout == .immersiveConversation
    }

    static func contentWidth(availableWidth: CGFloat, wide: Bool) -> CGFloat {
        let gutter = (wide ? wideSideGutter : compactSideGutter) * 2
        let usable = max(availableWidth - gutter, 1)
        // Wide: track the window, capped for readability (Codex ~720–920pt column).
        if wide {
            return min(usable, wideMaxWidth)
        }
        return min(usable, compactMaxWidth)
    }

    static func composerHeight(wide: Bool) -> CGFloat {
        // Fixed min for immersive; field grows via TextField lineLimit, capped by max frame.
        wide ? wideComposerMinHeight : compactComposerHeight
    }

    static func composerMaxHeight(wide: Bool) -> CGFloat {
        wide ? wideComposerMaxHeight : compactComposerHeight
    }

    static func composerFontSize(wide: Bool) -> CGFloat {
        wide ? wideFontSize : compactFontSize
    }
}

struct AgentPaneView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var showsPaneHeader = true
    var reorderRole: WorkspacePaneRole? = nil
    @FocusState private var draftFocused: Bool
    @State private var activeAgentRailID: String?
    @State private var agentFollowsLatest = true
    /// Live pane width from a background probe. 0 until first real measurement.
    @State private var measuredPaneWidth: CGFloat = 0

    private let agentBottomAnchorID = "agentConversationBottom"

    private var isImmersiveConversation: Bool {
        store.layout == .immersiveConversation
    }

    private var usesWideChatLayout: Bool {
        AgentChatLayoutMetrics.isWide(layout: store.layout)
    }

    /// Prefer a measured width; for immersive before the first probe, seed wide so we do not flash the three-pane strip size.
    private var agentPaneWidth: CGFloat {
        if measuredPaneWidth > 1 {
            return measuredPaneWidth
        }
        return usesWideChatLayout ? 1100 : 360
    }

    var body: some View {
        // Hang-proof structure:
        // NEVER put GeometryReader as an ancestor of ScrollView+LazyVStack.
        // Sampled freezes were GeometryReaderLayout → ScrollView.sizeThatFits → LazyVStack thrash.
        // Pane width is measured only via background preference (sibling, not parent).
        let wide = AgentChatLayoutMetrics.isWide(layout: store.layout)
        let availableWidth = max(agentPaneWidth, 1)
        let railOnly = ContentRailMetrics.isRailOnly(
            availableWidth: availableWidth,
            allowed: store.layout.allowsRailOnlyPanes
        )
        let showsContentRail = !wide && store.layout.allowsRailOnlyPanes
        let railItems = showsContentRail ? agentRailItems : []
        let contentWidth = AgentChatLayoutMetrics.contentWidth(
            availableWidth: availableWidth,
            wide: wide
        )
        let geometryWidth = availableWidth
        let headerHeight: CGFloat = showsPaneHeader
            ? (availableWidth < 420 ? 44 : 54)
            : 0

        ScrollViewReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    if showsPaneHeader {
                        WeiBeiPaneHeader(
                            title: store.ui("对话", "Chat"),
                            latinMark: store.interfaceLanguage == .chinese ? "CHAT" : nil,
                            subtitle: store.agentConversationSubtitle,
                            appearanceMode: store.appearanceMode,
                            reorderRole: reorderRole,
                            availableWidth: availableWidth
                        ) {
                            sessionMenu
                        }
                    }

                    ScrollView(showsIndicators: true) {
                        // No scrollTargetLayout / scrollPosition / minHeight:viewport /
                        // GeometryReader parent — all thrash sizeThatFits on LazyVStack.
                        LazyVStack(alignment: .leading, spacing: wide ? 22 : 12) {
                            ForEach(store.messages) { message in
                                agentMessageRow(
                                    message: message,
                                    geometryWidth: geometryWidth,
                                    contentWidth: contentWidth,
                                    wide: wide
                                )
                            }
                            if store.isAgentRunningInActiveChat
                                && !store.hasPersistedGeneratingAgentReply
                                && !store.agentStreamingText.isEmpty {
                                agentReadingColumn(
                                    geometryWidth: geometryWidth,
                                    contentWidth: contentWidth,
                                    wideLayout: wide,
                                    alignment: .leading
                                ) {
                                    AgentStreamingResponse(text: store.agentStreamingText)
                                }
                                .id("agent-streaming-response")
                                .transition(WeiBeiTransition.message)
                            }
                            if store.isAgentRunningInActiveChat
                                && !store.hasPersistedGeneratingAgentReply
                                && store.agentStreamingText.isEmpty {
                                agentReadingColumn(
                                    geometryWidth: geometryWidth,
                                    contentWidth: contentWidth,
                                    wideLayout: wide,
                                    alignment: .leading
                                ) {
                                    AgentThinkingIndicator()
                                }
                                .id("agent-thinking")
                                .transition(WeiBeiTransition.message)
                            }
                            if store.messages.isEmpty && !(store.isAgentRunningInActiveChat && store.agentStreamingText.isEmpty) {
                                emptyAgentState
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(WeiBeiTransition.message)
                            }
                            Color.clear
                                .frame(height: agentScrollBottomInset)
                                .id(agentBottomAnchorID)
                        }
                        .padding(.horizontal, wide ? 8 : 10)
                        .padding(.vertical, wide ? 14 : 10)
                        .environment(\.agentChatLayoutWidth, contentWidth)
                        .padding(.top, store.messages.isEmpty ? 22 : 0)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .zIndex(0)

                    agentInputTray(wide: wide, contentWidth: contentWidth)
                        .zIndex(1)
                        .animation(WeiBeiMotion.panel, value: store.layout)
                        .animation(WeiBeiMotion.panel, value: wide)
                }
                .opacity(railOnly ? 0 : 1)
                .allowsHitTesting(!railOnly)

                if showsContentRail {
                    ContentRailView(
                        label: store.ui("对话轨道", "Conversation rail"),
                        items: railItems,
                        activeID: activeAgentRailID ?? railItems.first?.id,
                        appearanceMode: store.appearanceMode,
                        isRailOnly: railOnly,
                        availableWidth: availableWidth,
                        topInset: railOnly ? 0 : headerHeight,
                        bottomInset: railOnly ? 0 : agentRailBottomInset,
                        onActivate: { activateAgentRailItem($0, railOnly: railOnly, proxy: proxy) }
                    )
                    .zIndex(4)
                }
            }
            .onChange(of: store.messages.count) { _, _ in
                if showsContentRail, let lastID = store.messages.last?.id {
                    updateAgentRailPosition(for: lastID)
                }
                scrollAgentToBottom(proxy)
            }
            .onRichAnswerVerificationStage { stage in
                handleRichAnswerVerificationStage(stage, proxy: proxy)
            }
        }
        // Width probe as background sibling — never parent of ScrollView.
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: AgentPaneWidthKey.self,
                    value: geo.size.width
                )
            }
        }
        .onPreferenceChange(AgentPaneWidthKey.self) { width in
            applyMeasuredPaneWidth(width)
        }
        .onChange(of: store.layout) { _, layout in
            // Entering immersive: seed wide so we never flash the last three-pane strip width.
            // Leaving immersive: drop to 0 so the next probe owns the multi-pane strip.
            if layout == .immersiveConversation {
                if measuredPaneWidth < 700 {
                    measuredPaneWidth = max(measuredPaneWidth, 1100)
                }
            } else if measuredPaneWidth > 700 {
                // Drop stale full-window width; real strip measure arrives next frame.
                measuredPaneWidth = 0
            }
        }
        .frame(minHeight: 260)
        .foregroundStyle(WeiBeiTheme.ink)
        // Same opaque paper as notes/reader — clear background lets
        // isMovableByWindowBackground steal header drags as window moves.
        .background(WeiBeiTheme.paper)
        .overlay(alignment: .topLeading) {
            AccessibilityFrameProbe(identifier: "stable-document-slot-agent")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
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
                .allowsHitTesting(false)
            } else {
                // Match notes: floating slip overlay only — no extra clear ZStack.
                ImmersiveHoverTitleView(
                    mark: "CHAT",
                    title: store.agentConversationSubtitle,
                    appearanceMode: store.appearanceMode,
                    actionsAlignedTrailing: true,
                    reorderRole: reorderRole
                ) {
                    agentSessionCatalogMenu
                }
            }
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
            if usesWideChatLayout, measuredPaneWidth < 700 {
                measuredPaneWidth = max(measuredPaneWidth, 1100)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stable-document-slot-agent")
        .accessibilityLabel(Text("agent chat pane"))
    }

    /// Accept real pane measures; ignore transient shrinks while immersive (host re-attach).
    private func applyMeasuredPaneWidth(_ width: CGFloat) {
        guard width > 1 else { return }
        if usesWideChatLayout {
            // PersistentPaneHost re-attach can briefly report the old strip width — do not keep it.
            if width < 520, measuredPaneWidth >= 700 {
                return
            }
        }
        guard abs(measuredPaneWidth - width) > 0.5 else { return }
        measuredPaneWidth = width
    }

    private func agentMessageRow(
        message: AgentMessage,
        geometryWidth: CGFloat,
        contentWidth: CGFloat,
        wide: Bool
    ) -> some View {
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

        // Native text rows: no per-message WKWebView height callbacks that thrash scroll.
        return agentReadingColumn(
            geometryWidth: geometryWidth,
            contentWidth: contentWidth,
            wideLayout: wide,
            canvasWide: needsWideCanvas,
            alignment: isUser ? .trailing : .leading
        ) {
            AgentBubble(message: message)
        }
        .id(message.id)
        .transition(WeiBeiTransition.message)
    }

    /// One centered reading column for messages, streaming, and loading.
    /// `geometryWidth` must be the live measured pane width — a stale full-window value
    /// mis-centers multi-pane text (the PreferenceKey bug we fixed above).
    private func agentReadingColumn<Content: View>(
        geometryWidth: CGFloat,
        contentWidth: CGFloat,
        wideLayout: Bool,
        canvasWide: Bool = false,
        alignment: HorizontalAlignment,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let readingWidth: CGFloat = {
            let paneLimit = max(geometryWidth - (wideLayout ? 32 : 16), 1)
            if wideLayout {
                // Rich-answer canvas can use a slightly wider band inside the same axis.
                let limit = canvasWide ? min(contentWidth + 40, paneLimit) : contentWidth
                return min(min(contentWidth, limit), paneLimit)
            }
            let limit: CGFloat = canvasWide ? 540 : 500
            // contentWidth already fits the strip; never force a design ceiling wider than the pane.
            return min(min(max(contentWidth, 1), limit), paneLimit)
        }()
        let readingLeadingInset = max((geometryWidth - readingWidth) / 2, 0)
        return content()
            .frame(maxWidth: readingWidth, alignment: Alignment(horizontal: alignment, vertical: .center))
            .padding(.leading, readingLeadingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func agentInputTray(wide: Bool, contentWidth: CGFloat) -> some View {
        let minHeight = AgentChatLayoutMetrics.composerHeight(wide: wide)
        let maxHeight = AgentChatLayoutMetrics.composerMaxHeight(wide: wide)
        let fontSize = AgentChatLayoutMetrics.composerFontSize(wide: wide)
        // Codex-like: modest min height, grow with content, leave message area the majority of the pane.
        return VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .clear,
                    WeiBeiTheme.paper.opacity(0.22),
                    WeiBeiTheme.glassTint.opacity(0.40)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: wide ? 16 : 18)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: wide ? 8 : 8) {
                if store.hasSelectionAttachments {
                    AgentSelectionAttachmentPill()
                        .transition(WeiBeiTransition.floating)
                }

                if let notice = store.agentContextScopeNotice {
                    Label(notice, systemImage: "rectangle.on.rectangle.slash")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(wide ? 2 : 3)
                        .accessibilityIdentifier("agent-course-scope-notice")
                }

                AgentComposerField(
                    prompt: agentPrompt,
                    focused: $draftFocused,
                    font: .system(size: fontSize),
                    promptFont: .system(size: fontSize),
                    lineLimit: wide ? 1...10 : 1...6,
                    height: minHeight,
                    maxHeight: maxHeight,
                    sendButtonSize: wide ? 32 : 28,
                    trailingPadding: wide ? 48 : 40,
                    sendTrailing: wide ? 12 : 10,
                    sendBottom: wide ? 10 : 8,
                    horizontalPadding: wide ? 16 : 12,
                    verticalPadding: wide ? 12 : 8,
                    showsModelFooter: wide
                ) {
                    store.submitAgentDraft()
                }
            }
            .font(.system(size: fontSize))
            .frame(width: contentWidth, alignment: .bottom)
            .padding(.top, wide ? 6 : 4)
            .padding(.bottom, wide ? 16 : 12)
            .frame(maxWidth: .infinity)
            .background(WeiBeiTheme.paper)
            .animation(WeiBeiMotion.reveal, value: store.agentDraft)
            .accessibilityIdentifier(wide ? "agent-input-tray-wide" : "agent-input-tray-compact")
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
        AgentChatLayoutMetrics.contentWidth(
            availableWidth: max(agentPaneWidth, 1),
            wide: usesWideChatLayout
        )
    }

    private var agentContentMaxWidth: CGFloat? {
        agentInputMaxWidth
    }

    private var composerFieldHeight: CGFloat {
        AgentChatLayoutMetrics.composerHeight(wide: usesWideChatLayout)
    }

    private var composerFontSize: CGFloat {
        AgentChatLayoutMetrics.composerFontSize(wide: usesWideChatLayout)
    }

    private var agentScrollBottomInset: CGFloat {
        // Fixed inset only — tray GeometryReader preference → LazyVStack height feedback
        // re-entered sizeThatFits every scroll frame and froze the app.
        // Tray already sits outside the ScrollView (VStack), so keep this small;
        // large fixed insets stole message viewport height and made immersive feel tiny.
        hasVisibleRichAnswer
            ? (usesWideChatLayout ? 28 : 20)
            : (usesWideChatLayout ? 16 : 12)
    }

    private var hasVisibleRichAnswer: Bool {
        store.messages.contains { message in
            message.richAnswer?.mode == .rich && message.richAnswer?.scenes.isEmpty == false
        }
    }

    private var agentRailBottomInset: CGFloat {
        usesWideChatLayout ? 120 : 100
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
        store.submitAgentDraft()
    }

    /// Compact catalog for immersive hover tab + pane header.
    private var agentSessionCatalogMenu: some View {
        Menu {
            sessionCatalogContent
        } label: {
            Label {
                Text(store.activeStudySessionScopeTitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            } icon: {
                Image(systemName: "list.bullet.rectangle")
            }
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(Text(store.ui("对话目录", "Conversation catalog")))
        .help(store.ui("按全局或课程切换对话", "Switch Chats by global or course scope"))
    }

    private var sessionMenu: some View {
        Menu {
            sessionCatalogContent
        } label: {
            Image(systemName: "list.bullet.rectangle")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 24))
        .accessibilityLabel(Text(store.ui("学习会话", "Study Sessions")))
        .help(store.ui("按全局或课程新建、切换对话", "Create or switch global and course Chats"))
    }

    @ViewBuilder
    private var sessionCatalogContent: some View {
        if store.activeStudySession?.scopeNeedsReview == false,
           let courseID = store.activeStudySession?.courseID ?? store.activeCourseID,
           let course = store.course(withID: courseID) {
            Button {
                store.createStudySession(courseID: courseID)
            } label: {
                Label(
                    store.ui("新建“\(course.title)”对话", "New \"\(course.title)\" Chat"),
                    systemImage: "plus.bubble"
                )
            }
        }

        Button {
            store.createStudySession(courseID: nil)
        } label: {
            Label(store.ui("新建全局对话", "New Global Chat"), systemImage: "globe")
        }

        Divider()

        if !store.globalStudySessions.isEmpty {
            Section(store.ui("全局", "Global")) {
                ForEach(store.globalStudySessions.prefix(12)) { session in
                    sessionMenuButton(session)
                }
            }
        }

        ForEach(store.courses) { course in
            let sessions = store.studySessions(in: course.id)
            if !sessions.isEmpty {
                Section(course.title) {
                    ForEach(sessions.prefix(12)) { session in
                        sessionMenuButton(session)
                    }
                }
            }
        }

        if !store.unclassifiedStudySessions.isEmpty {
            Section(store.ui("待归类", "Needs Course")) {
                ForEach(store.unclassifiedStudySessions.prefix(12)) { session in
                    Menu(session.title) {
                        Button {
                            store.activateStudySession(
                                session.id,
                                expectedCourseID: nil,
                                expectedScopeNeedsReview: true
                            )
                        } label: {
                            Label(store.ui("打开并查看", "Open and Review"), systemImage: "eye")
                        }

                        Divider()

                        Button {
                            store.classifyStudySession(session.id, as: nil)
                        } label: {
                            Label(store.ui("归为全局对话", "Classify as Global"), systemImage: "globe")
                        }

                        if !store.courses.isEmpty {
                            Section(store.ui("归入课程", "Classify into Course")) {
                                ForEach(store.courses) { course in
                                    Button(course.title) {
                                        store.classifyStudySession(session.id, as: course.id)
                                    }
                                }
                            }
                        }
                    }
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
    }

    @ViewBuilder
    private func sessionMenuButton(_ session: StudySession) -> some View {
        Button {
            store.activateStudySession(
                session.id,
                expectedCourseID: session.courseID,
                expectedScopeNeedsReview: session.scopeNeedsReview == true
            )
        } label: {
            if session.id == store.activeStudySessionID {
                Label(session.title, systemImage: "checkmark")
            } else {
                Text(session.title)
            }
        }
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
              let target = latestRichAnswerVerificationTarget else { return }
        agentFollowsLatest = false
        let capturesMessageBottom = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_RICH_ANSWER_CAPTURE_ANCHOR"] == "bottom"
        DispatchQueue.main.async {
            if capturesMessageBottom {
                proxy.scrollTo(target.messageID, anchor: .bottom)
            } else {
                proxy.scrollTo(target.sceneAnchorID, anchor: .top)
            }
        }
    }

    private var latestRichAnswerVerificationTarget: (messageID: UUID, sceneAnchorID: String)? {
        for message in store.messages.reversed() {
            guard let richAnswer = message.richAnswer,
                  richAnswer.mode == .rich,
                  !richAnswer.scenes.isEmpty else { continue }
            for (index, part) in richAnswer.resolvedParts.enumerated() {
                guard case .scene = part.kind,
                      let sceneID = part.sceneID else { continue }
                return (
                    message.id,
                    "rich-answer-\(message.id.uuidString)-\(sceneID)-\(index)"
                )
            }
        }
        return nil
    }

}

private struct AgentPaneWidthKey: PreferenceKey {
    /// 0 = unmeasured. Must NOT default to 960: reduce used to max with 960 and
    /// multi-pane strips (e.g. 360pt) were forever treated as full-window wide,
    /// so messages/input centered off-canvas and "didn't adapt".
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 1 {
            value = next
        }
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

struct FloatingSelectionAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var expanded: Bool
    var routesToConversation = false
    @State private var dragOffset = CGSize.zero
    @State private var settledOffset = CGSize.zero
    /// User-resizable panel; default matches placement constant (half-width × 2).
    @State private var panelWidth = CGFloat(SelectionFloatingAgentPlacement.expandedHalfWidth * 2)
    @State private var feedMaxHeight: CGFloat = 380
    @State private var resizeOriginWidth: CGFloat = 0
    @State private var resizeOriginFeedHeight: CGFloat = 0
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
        .modifier(SelectionFloatChrome(expanded: showsExpandedBody, pinned: store.pinnedFloatingAgent))
        .scaleEffect(showsExpandedBody ? 1 : 0.985)
        .animation(WeiBeiMotion.panel, value: expanded)
        .animation(WeiBeiMotion.panel, value: store.pinnedFloatingAgent)
        .animation(WeiBeiMotion.panel, value: store.isAgentRunningInActiveChat)
        .offset(x: dragOffset.width + settledOffset.width, y: dragOffset.height + settledOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    withAnimation(WeiBeiMotion.panel) {
                        settledOffset = CGSize(
                            width: settledOffset.width + value.translation.width,
                            height: settledOffset.height + value.translation.height
                        )
                        dragOffset = .zero
                        // Dragging repositions; pin is only set by the pin control.
                    }
                }
        )
        .onChange(of: store.selectionContext) { previous, next in
            guard !store.pinnedFloatingAgent, !store.isAgentRunningInActiveChat else { return }
            let sameContent = previous?.text == next?.text
                && previous?.source == next?.source
                && previous?.ownerTitle == next?.ownerTitle
                && previous?.isEditable == next?.isEditable
            guard !sameContent else { return }
            // Reopen uses SelectionContext.id == thread.id — expand beside the mark.
            let isThreadReopen = next.map { store.activeSelectionAskThreadID == $0.id } ?? false
            if isThreadReopen, store.keepFloatingSelectionForAnswer {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
                return
            }
            // Live reselection → capsule only.
            withAnimation(WeiBeiMotion.panel) {
                expanded = false
                store.keepFloatingSelectionForAnswer = false
                store.activeSelectionAskThreadID = nil
                dragOffset = .zero
                settledOffset = .zero
            }
        }
        .onChange(of: store.keepFloatingSelectionForAnswer) { _, keep in
            if keep {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
            }
        }
        .onChange(of: store.activeSelectionAskThreadID) { _, id in
            if id != nil, store.keepFloatingSelectionForAnswer {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
            }
        }
        .onChange(of: store.isAgentRunningInActiveChat) { _, asking in
            if asking {
                withAnimation(WeiBeiMotion.panel) { expanded = true }
            }
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
            if store.pinnedFloatingAgent || store.isAgentRunningInActiveChat || store.keepFloatingSelectionForAnswer {
                expanded = true
            }
        }
        .onExitCommand {
            closeFloatingAgent()
        }
    }

    private var showsExpandedBody: Bool {
        // Capsule for bare selection; expand for 问 / pin / stream / 红线回访(keepOpen).
        expanded || store.pinnedFloatingAgent || store.isAgentRunningInActiveChat || store.keepFloatingSelectionForAnswer
    }

    private var promptBody: some View {
        HStack(spacing: 0) {
            Button(store.ui("问", "Ask")) {
                openExpandedComposer()
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
        .font(.system(size: 12, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .fixedSize()
    }

    private var promptSeparator: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.78))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 8)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(store.ui("选区对话", "Selection chat"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                if store.pinnedFloatingAgent {
                    Text(store.ui("已固定", "Pinned"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.9))
                }
                Spacer(minLength: 4)
                if store.isConversationSurfaceVisible, store.activeSelectionAskThreadID != nil {
                    Button(store.ui("跳到对话", "Jump to chat")) {
                        if let id = store.activeSelectionAskThreadID {
                            store.openSelectionAskThread(id, jumpToConversation: true)
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
                Button {
                    withAnimation(WeiBeiMotion.micro) { togglePinnedFloatingAgent() }
                } label: {
                    Image(systemName: store.pinnedFloatingAgent ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.pinnedFloatingAgent ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(store.pinnedFloatingAgent
                      ? store.ui("取消固定：选区变化时浮层可收起", "Unpin: float may dismiss when selection changes")
                      : store.ui("固定浮层：选区变化时保持打开", "Pin float: keep open when selection changes"))
                .accessibilityLabel(Text(store.pinnedFloatingAgent ? store.ui("取消固定浮层", "Unpin floating layer") : store.ui("固定浮层", "Pin floating layer")))

                Button {
                    closeFloatingAgent()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(store.ui("关闭", "Close"))
                .accessibilityLabel(Text(store.ui("关闭", "Close")))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.55))
                .frame(height: 1)
                .padding(.horizontal, 12)

            if let selection = store.selectionContext?.text, !selection.isEmpty {
                HStack(spacing: 6) {
                    Text(store.ui("选区", "Selection"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.9))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(WeiBeiTheme.cinnabarSoft.opacity(0.62), in: Capsule())
                    Text(Self.selectionTagLabel(selection))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }

            ScrollView(showsIndicators: false) {
                // Same order as immersive chat: messages → streaming → thinking.
                LazyVStack(alignment: .leading, spacing: 12) {
                    if visibleFloatingMessages.isEmpty && !(store.isAgentRunningInActiveChat && store.agentStreamingText.isEmpty) {
                        Text(store.ui("写下问题后发送，回答会出现在这里。", "Write a question and send — the reply appears here."))
                            .font(.system(size: 12))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(visibleFloatingMessages) { message in
                        if message.completionState == .generating
                            && message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            AgentThinkingIndicator()
                                .id(message.id)
                                .padding(.vertical, 4)
                        } else {
                            floatBubble(
                                messageID: message.id,
                                roleLabel: message.role == .user ? store.ui("你", "You") : "WeiBei",
                                text: floatingText(for: message),
                                isUser: message.role == .user,
                                isError: WorkspaceStore.isAgentFailureMessage(message.text)
                            )
                        }
                    }

                    if store.isAgentRunningInActiveChat
                        && !store.hasPersistedGeneratingAgentReply
                        && !store.agentStreamingText.isEmpty {
                        floatStreamingBubble(text: store.agentStreamingText)
                            .id("selection-float-streaming")
                    }

                    if store.isAgentRunningInActiveChat
                        && !store.hasPersistedGeneratingAgentReply
                        && store.agentStreamingText.isEmpty {
                        AgentThinkingIndicator()
                            .id("selection-float-thinking")
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .environment(\.agentChatLayoutWidth, max(panelWidth - 28, 1))
            }
            .frame(minHeight: floatingFeedHeight, maxHeight: feedMaxHeight)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.45))
                    .frame(height: 1)
                AgentComposerField(
                    prompt: store.ui("问选区或继续追问", "Ask about selection…"),
                    focused: $draftFocused,
                    font: .system(size: 13.5),
                    promptFont: .system(size: 13.5),
                    lineLimit: 1...5,
                    height: 56,
                    sendButtonSize: 26,
                    trailingPadding: 36,
                    sendTrailing: 8,
                    sendBottom: 8,
                    horizontalPadding: 10,
                    verticalPadding: 8
                ) {
                    sendDraft()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .frame(width: panelWidth, alignment: .leading)
        .frame(minWidth: 420)
        .overlay(alignment: .bottomTrailing) {
            floatResizeHandle
        }
        .onAppear {
            draftFocused = true
        }
    }

    private var floatResizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.9))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .padding(6)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeOriginWidth == 0 {
                            resizeOriginWidth = panelWidth
                            resizeOriginFeedHeight = feedMaxHeight
                        }
                        panelWidth = min(max(resizeOriginWidth + value.translation.width, 420), 720)
                        feedMaxHeight = min(max(resizeOriginFeedHeight + value.translation.height, 160), 640)
                    }
                    .onEnded { _ in
                        resizeOriginWidth = 0
                        resizeOriginFeedHeight = 0
                    }
            )
            .help(store.ui("拖拽调整选区对话大小", "Drag to resize selection chat"))
            .accessibilityLabel(Text(store.ui("调整选区对话大小", "Resize selection chat")))
    }

    private func floatBubble(messageID: UUID, roleLabel: String, text: String, isUser: Bool, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isUser {
                Text(roleLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.link.opacity(0.85))
            } else {
                HStack(spacing: 6) {
                    Text("WeiBei")
                        .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                        .foregroundStyle(isError ? WeiBeiTheme.cinnabar : WeiBeiTheme.cinnabar.opacity(0.76))
                    if !isError {
                        Text("PI")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                    }
                }
            }
            if isError {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
            } else {
                // Same markdown path as immersive chat (`AgentMessageMarkdownText`).
                AgentMessageMarkdownText(
                    text: text,
                    rendersRichMarkdown: !isUser,
                    compact: true,
                    usesFinalizedKaTeX: !isUser,
                    messageID: messageID
                )
            }
        }
        .padding(.vertical, 3)
    }

    private func floatStreamingBubble(text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("WeiBei")
                    .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
                Text("PI")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            // Streaming: native text only (no KaTeX WebView mid-stream).
            AgentStreamingMarkdownText(text: text, compact: true)
        }
        .padding(.vertical, 3)
        .accessibilityLabel(Text(store.ui("PI 正在回答", "PI is responding")))
    }

    private static func selectionTagLabel(_ text: String, limit: Int = 18) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)) + "…"
    }

    private var visibleFloatingMessages: [AgentMessage] {
        // Strict isolation: only messages belonging to the active selection-ask thread.
        // Never fall back to the global conversation feed.
        guard let threadID = store.activeSelectionAskThreadID,
              let thread = store.selectionAskThreads.first(where: { $0.id == threadID }) else {
            return []
        }
        let idSet = Set(thread.messageIDs)
        return store.messages.filter { idSet.contains($0.id) }
    }

    private var canPolishNoteSelection: Bool {
        store.selectionContext?.isNoteSelection == true
    }

    private var floatingFeedHeight: CGFloat {
        if store.isAgentRunningInActiveChat { return 160 }
        if visibleFloatingMessages.isEmpty { return 88 }
        switch visibleFloatingMessages.count {
        case 1: return 130
        case 2: return 200
        case 3: return 260
        default: return 320
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
                || message.text.hasPrefix("请解释下面选区")
                || message.text.hasPrefix("请解释当前选区"))
    }

    private func togglePinnedFloatingAgent() {
        let next = !store.pinnedFloatingAgent
        store.pinnedFloatingAgent = next
        if next {
            store.agentSurface = .selectionFloat
            store.keepFloatingSelectionForAnswer = true
        } else {
            // Unpin must not dismiss — keepOpen holds the float without a drag anchor.
            store.keepFloatingSelectionForAnswer = true
            store.agentSurface = .selectionFloat
            expanded = true
        }
    }

    private func openExpandedComposer() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
            store.keepFloatingSelectionForAnswer = true
            // Do not invent a prompt or auto-send — only open a normal composer.
            store.askSelection()
            draftFocused = true
        }
    }

    private func openSourceReference() {
        store.openSelectedSourceReference()
    }

    private func sendDraft() {
        guard !store.isStoppingAgent,
              !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
            store.keepFloatingSelectionForAnswer = true
            if let selection = store.selectionContext {
                store.addSelectionAttachment(selection)
                let thread = store.beginOrReuseSelectionAskThread(for: selection)
                store.activeSelectionAskThreadID = thread.id
            }
        }
        store.submitAgentDraft()
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

/// Paper float chrome: quieter radius; cinnabar edge only when pinned.
private struct SelectionFloatChrome: ViewModifier {
    var expanded: Bool
    var pinned: Bool

    func body(content: Content) -> some View {
        content
            .foregroundColor(WeiBeiTheme.ink)
            .background {
                RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous)
                    .fill(WeiBeiTheme.paperRaised.opacity(0.98))
            }
            .clipShape(RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous)
                    .strokeBorder(
                        pinned ? WeiBeiTheme.cinnabar.opacity(0.34) : WeiBeiTheme.hairline.opacity(0.65),
                        lineWidth: 1
                    )
            }
            .shadow(color: WeiBeiTheme.ink.opacity(pinned ? 0.1 : 0.06), radius: pinned ? 12 : 8, y: pinned ? 4 : 3)
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
    }

    @ViewBuilder
    private var userTurn: some View {
        // Quiet paper chip on the right edge: role is encoded by position + surface,
        // so no "你" label, no accent rail, no messenger chrome.
        // Long material/section source strings are intentionally not shown — they clutter
        // the turn without helping the learner (navigation lives in tags / reader).
        VStack(alignment: .trailing, spacing: 4) {
            AgentMessageMarkdownText(
                text: message.text,
                rendersRichMarkdown: false
            )
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(userBubbleFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(userBubbleStroke, lineWidth: 1)
                    }
                    .shadow(
                        color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.0 : (hovering ? 0.06 : 0.04)),
                        radius: hovering ? 6 : 4,
                        y: hovering ? 2 : 1.2
                    )
            }
            .frame(maxWidth: 520, alignment: .trailing)
        }
        .weibeiHoverLift(active: hovering, amount: 0.6)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var userBubbleFill: Color {
        // Same paper family as chips/panels: a slightly raised slip of paper, not a tinted chat blob.
        store.appearanceMode.isDark
            ? WeiBeiTheme.paperRaised.opacity(hovering ? 0.58 : 0.46)
            : WeiBeiTheme.paperRaised.opacity(hovering ? 1.0 : 0.96)
    }

    private var userBubbleStroke: Color {
        store.appearanceMode.isDark
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
                // Assistant messages no longer carry a cinnabar leading mark;
                // only credential notices keep a link-blue affordance.
        }
    }

    private var regularMessageContent: some View {
        let citationParse = AgentCitationParser.parse(message.text)
        let availableSources = message.sources.filter {
            store.canOpenAgentReplySource($0)
        }
        let legacyCitations = citationParse.citations.filter { citation in
            switch citation.kind {
            case .material, .note, .selection:
                return message.sources.isEmpty
            case .learningRecord, .learningMemory, .session:
                return true
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            messageMetadata

            if message.completionState == .generating {
                if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AgentThinkingIndicator()
                } else {
                    AgentStreamingResponse(text: message.text)
                }
            } else if let richAnswer = message.richAnswer,
               richAnswer.mode == .rich,
               !richAnswer.scenes.isEmpty {
                richAnswerFlow(richAnswer)
                if !availableSources.isEmpty {
                    AgentReplySourceTagRow(sources: availableSources) { source in
                        activateSource(source)
                    }
                }
            } else if !availableSources.isEmpty {
                AgentReplySourceTextFlow(
                    text: message.text,
                    sources: availableSources,
                    isFailureMessage: isFailureMessage,
                    messageID: message.id
                ) { source in
                    activateSource(source)
                }
            } else {
                // Hang-proof agent chat: finalized turns use KaTeX with frozen height;
                // failures stay native text (no WebView). Never height→scroll.
                AgentMessageMarkdownText(
                    text: citationParse.displayText,
                    rendersRichMarkdown: true,
                    usesFinalizedKaTeX: !isFailureMessage,
                    messageID: message.id
                )
            }

            if !legacyCitations.isEmpty {
                AgentCitationTagRow(citations: legacyCitations) { citation in
                    activateCitation(citation)
                }
            }

            if message.completionState == .interrupted && !isFailureMessage {
                HStack(spacing: 6) {
                    Text(store.ui("回答已中断，已保留现有内容", "Response interrupted; existing content was kept"))
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                    if store.canRetryAgentRequest(
                        question: message.retryQuestion,
                        failureKind: message.failureKind
                    ), let question = message.retryQuestion {
                        Button(store.ui("重试", "Retry")) {
                            store.retryAgentRequest(question)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                }
                .padding(.top, 2)
            } else if isFailureMessage {
                HStack(spacing: 6) {
                    if store.canRetryAgentRequest(
                        question: message.retryQuestion,
                        failureKind: message.failureKind
                    ), let question = message.retryQuestion {
                        Button(store.ui("重试", "Retry")) {
                            store.retryAgentRequest(question)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                    if let question = message.retryQuestion, !question.isEmpty {
                        Button(store.ui("回填问题", "Restore question")) {
                            store.agentDraft = question
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                .padding(.top, 2)
            } else if message.id == store.lastUsableAgentAnswerID {
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

    private func activateSource(_ source: AgentReplySource) {
        withAnimation(WeiBeiMotion.panel) {
            _ = store.openAgentReplySource(source)
        }
    }

    @ViewBuilder
    private func richAnswerFlow(_ presentation: RichAnswerPresentation) -> some View {
        ForEach(Array(presentation.resolvedParts.enumerated()), id: \.offset) { index, part in
            switch part.kind {
            case .narrative:
                if let text = part.text, !text.isEmpty {
                    RichAnswerNarrativeText(
                        text: AgentCitationParser.parse(text).displayText
                    )
                        .frame(
                            maxWidth: AgentChatLayoutMetrics.isWide(layout: store.layout)
                                ? AgentChatLayoutMetrics.wideMaxWidth
                                : AgentChatLayoutMetrics.compactMaxWidth,
                            alignment: .leading
                        )
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
                    .frame(
                        maxWidth: AgentChatLayoutMetrics.isWide(layout: store.layout)
                            ? AgentChatLayoutMetrics.wideMaxWidth
                            : AgentChatLayoutMetrics.compactMaxWidth,
                        alignment: .leading
                    )
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
        guard !store.isStoppingAgent else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.agentDraft = trimmed
        store.submitAgentDraft()
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
                .fill(WeiBeiTheme.hairline.opacity(0.72))
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
            // Do not render message.source here — long "课程 HTML，章节标识…" strings
            // add noise; materials / learning context use citation tags instead.
            Spacer(minLength: 0)
        }
    }

    private func activateCitation(_ citation: AgentCitation) {
        switch citation.kind {
        case .material:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "material", value: citation.value)
            }
        case .note:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "note", value: citation.value)
            }
        case .selection:
            withAnimation(WeiBeiMotion.panel) {
                _ = store.openAgentCitation(kind: "selection", value: citation.value)
            }
        case .learningRecord:
            withAnimation(WeiBeiMotion.panel) {
                store.resumePreviousStudy()
            }
        case .learningMemory:
            withAnimation(WeiBeiMotion.panel) {
                store.presentCourseWorkspace(.sessions)
            }
        case .session:
            break
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
        if let source = message.sources.first(where: {
            $0.label == evidence.sourceLabel
                && store.canOpenAgentReplySource($0)
        }) {
            _ = store.openAgentReplySource(source)
            return
        }
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

    private var isFailureMessage: Bool {
        message.role == .assistant && WorkspaceStore.isAgentFailureMessage(message.text)
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
        let displayValue = RichAnswerDisplayText.normalizedInlineMath(value)
        return (try? AttributedString(markdown: displayValue)) ?? AttributedString(displayValue)
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

// MARK: - Agent citation tags (materials / learning / selection)

/// Bracket citations Pi emits in answers, e.g. `[材料：…]`, `[学习记录：上次位置]`.
private enum AgentCitationKind: String, Equatable {
    case material
    case note
    case selection
    case learningRecord
    case learningMemory
    case session

    var systemImage: String {
        switch self {
        case .material: return "doc.text"
        case .note: return "note.text"
        case .selection: return "text.quote"
        case .learningRecord: return "bookmark"
        case .learningMemory: return "brain.head.profile"
        case .session: return "bubble.left.and.bubble.right"
        }
    }

    func shortLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .material: return language.text("材料", "Material")
        case .note: return language.text("笔记", "Note")
        case .selection: return language.text("选区", "Selection")
        case .learningRecord: return language.text("学习记录", "Study record")
        case .learningMemory: return language.text("学习记忆", "Memory")
        case .session: return language.text("会话", "Session")
        }
    }
}

private struct AgentCitation: Identifiable, Equatable {
    let id: String
    let kind: AgentCitationKind
    let raw: String
    let value: String

    var displayTitle: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.rawValue : trimmed
    }
}

private enum AgentCitationParser {
    /// Matches `[材料：…]` / `[学习记录：上次位置]` style Pi citation labels.
    private static let pattern = #"\[(材料|笔记|选区|学习记录|学习记忆|会话)[：:]\s*([^\]\n]{1,300})\]"#

    static func parse(_ text: String) -> (displayText: String, citations: [AgentCitation]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var citations: [AgentCitation] = []
        var seen = Set<String>()
        regex.enumerateMatches(in: text, options: [], range: nsRange) { match, _, _ in
            guard let match,
                  let fullRange = Range(match.range, in: text),
                  let kindRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else { return }
            let kindToken = String(text[kindRange])
            let value = String(text[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = String(text[fullRange])
            guard let kind = kind(from: kindToken) else { return }
            let key = "\(kind.rawValue)|\(value)"
            guard seen.insert(key).inserted else { return }
            citations.append(
                AgentCitation(
                    id: key,
                    kind: kind,
                    raw: raw,
                    value: value
                )
            )
        }
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: nsRange, withTemplate: "")
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? text : cleaned, citations)
    }

    private static func kind(from token: String) -> AgentCitationKind? {
        switch token {
        case "材料": return .material
        case "笔记": return .note
        case "选区": return .selection
        case "学习记录": return .learningRecord
        case "学习记忆": return .learningMemory
        case "会话": return .session
        default: return nil
        }
    }
}

private struct AgentReplySourceTagRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let sources: [AgentReplySource]
    var onActivate: (AgentReplySource) -> Void
    @State private var showsMore = false

    var body: some View {
        HStack(spacing: 6) {
            if let first = sources.first {
                AgentReplySourceTag(source: first) {
                    onActivate(first)
                }
            }
            if sources.count > 1 {
                Button("+\(sources.count - 1)") {
                    showsMore.toggle()
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    WeiBeiTheme.paperInset.opacity(0.48),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
                }
                .buttonStyle(.plain)
                .help(store.ui("查看另外 \(sources.count - 1) 个来源", "View \(sources.count - 1) more sources"))
                .popover(isPresented: $showsMore, arrowEdge: .bottom) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(sources.dropFirst())) { source in
                                Button {
                                    showsMore = false
                                    onActivate(source)
                                } label: {
                                    AgentReplySourceDetail(source: source)
                                }
                                .buttonStyle(.plain)
                                if source.id != sources.last?.id {
                                    Rectangle()
                                        .fill(WeiBeiTheme.hairline.opacity(0.42))
                                        .frame(height: 1)
                                }
                            }
                        }
                    }
                    .frame(width: 340, height: min(CGFloat(sources.count - 1) * 86, 360))
                    .padding(.vertical, 6)
                }
                .accessibilityLabel(
                    Text(store.ui("展开另外 \(sources.count - 1) 个来源", "Expand \(sources.count - 1) more sources"))
                )
            }
        }
        .padding(.top, 2)
    }
}

private struct AgentReplySourceTextFlow: View {
    let text: String
    let sources: [AgentReplySource]
    let isFailureMessage: Bool
    let messageID: UUID
    var onActivate: (AgentReplySource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if !part.text.isEmpty {
                    AgentMessageMarkdownText(
                        text: part.text,
                        rendersRichMarkdown: true,
                        usesFinalizedKaTeX: !isFailureMessage,
                        messageID: index == 0 ? messageID : nil
                    )
                }
                if !part.sources.isEmpty {
                    AgentReplySourceTagRow(sources: part.sources, onActivate: onActivate)
                }
            }
        }
    }

    private var parts: [(text: String, sources: [AgentReplySource])] {
        var result: [(text: String, sources: [AgentReplySource])] = []
        var remaining = text[...]

        while let match = earliestSource(in: remaining) {
            let preceding = String(remaining[..<match.range.lowerBound])
            var matchedSources = [match.source]
            remaining = remaining[match.range.upperBound...]

            while let next = earliestSource(in: remaining),
                  remaining[..<next.range.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
                matchedSources.append(next.source)
                remaining = remaining[next.range.upperBound...]
            }
            result.append((
                AgentCitationParser.parse(preceding).displayText,
                matchedSources
            ))
        }

        let tail = AgentCitationParser.parse(String(remaining)).displayText
        if !tail.isEmpty || result.isEmpty {
            result.append((tail, []))
        }
        return result
    }

    private func earliestSource(
        in text: Substring
    ) -> (source: AgentReplySource, range: Range<Substring.Index>)? {
        sources.compactMap { source in
            text.range(of: source.label).map { (source, $0) }
        }
        .min { $0.1.lowerBound < $1.1.lowerBound }
    }
}

private struct AgentReplySourceTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    let source: AgentReplySource
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: source.kind.sourceSystemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(hovering ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                WeiBeiTheme.paperInset.opacity(hovering ? 0.58 : 0.40),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        hovering
                            ? WeiBeiTheme.cinnabar.opacity(0.28)
                            : WeiBeiTheme.hairline.opacity(0.40),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .help(detailText)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) {
                self.hovering = hovering
            }
        }
        .accessibilityLabel(Text(store.ui("打开原文：\(label)", "Open source: \(label)")))
    }

    private var label: String {
        let title = source.title.count > 18
            ? String(source.title.prefix(16)) + "…"
            : source.title
        guard let position = source.positionLabel(language: store.interfaceLanguage) else {
            return title
        }
        return "\(title) · \(position)"
    }

    private var detailText: String {
        [
            source.title,
            source.positionLabel(language: store.interfaceLanguage),
            source.excerpt.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: "\n")
    }
}

private struct AgentReplySourceDetail: View {
    @EnvironmentObject private var store: WorkspaceStore
    let source: AgentReplySource

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: source.kind.sourceSystemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.82))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(source.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .lineLimit(1)
                    if let position = source.positionLabel(language: store.interfaceLanguage) {
                        Text(position)
                            .font(.system(size: 10.5))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Text(source.excerpt)
                    .font(.system(size: 11.5))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private extension AgentReplySourceKind {
    var sourceSystemImage: String {
        switch self {
        case .material: return "doc.text"
        case .note: return "note.text"
        case .selection: return "text.quote"
        }
    }
}

private struct AgentCitationTagRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citations: [AgentCitation]
    var onActivate: (AgentCitation) -> Void

    var body: some View {
        // Wrapping HStack via LazyVGrid-like flow using flexible chips.
        FlexibleCitationWrap(citations: citations, onActivate: onActivate)
    }
}

/// Simple left-to-right wrap without GeometryReader thrash on the chat LazyVStack.
private struct FlexibleCitationWrap: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citations: [AgentCitation]
    var onActivate: (AgentCitation) -> Void

    var body: some View {
        // Single horizontal wrap via ViewThatFits-style chunking is heavy; use a
        // multi-line HStack of lines built greedily at layout time via Preference-free
        // fixed wrapping: put chips in a wrapping layout using `HStack` + multiple rows
        // computed by character budget.
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(chunkedRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { citation in
                        AgentCitationTag(citation: citation) {
                            onActivate(citation)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private var chunkedRows: [[AgentCitation]] {
        var rows: [[AgentCitation]] = []
        var current: [AgentCitation] = []
        var budget: CGFloat = 0
        let rowBudget: CGFloat = 52 // approx character units per row
        for citation in citations {
            let cost = CGFloat(min(citation.displayTitle.count + 6, 28))
            if !current.isEmpty, budget + cost > rowBudget {
                rows.append(current)
                current = []
                budget = 0
            }
            current.append(citation)
            budget += cost
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

private struct AgentCitationTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    let citation: AgentCitation
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: citation.kind.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(chipLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            withAnimation(WeiBeiMotion.hover) { self.hovering = hovering }
        }
        .accessibilityLabel(Text(helpText))
    }

    private var chipLabel: String {
        let kindLabel = citation.kind.shortLabel(language: store.interfaceLanguage)
        switch citation.kind {
        case .learningRecord, .learningMemory, .session:
            // Value is already a short kind phrase ("上次位置").
            return "\(kindLabel) · \(citation.displayTitle)"
        case .material, .note, .selection:
            let short = citation.displayTitle.count > 18
                ? String(citation.displayTitle.prefix(16)) + "…"
                : citation.displayTitle
            return "\(kindLabel) · \(short)"
        }
    }

    private var helpText: String {
        switch citation.kind {
        case .material:
            return store.ui("打开材料：\(citation.displayTitle)", "Open material: \(citation.displayTitle)")
        case .note:
            return store.ui("打开笔记：\(citation.displayTitle)", "Open note: \(citation.displayTitle)")
        case .selection:
            return store.ui("查看选区：\(citation.displayTitle)", "Open selection: \(citation.displayTitle)")
        case .learningRecord:
            return store.ui("回到上次学习位置", "Resume last study location")
        case .learningMemory:
            return store.ui("查看学习记忆", "Open study memory")
        case .session:
            return store.ui("当前会话", "Current session")
        }
    }

    private var foreground: Color {
        switch citation.kind {
        case .material:
            return hovering ? WeiBeiTheme.moss : WeiBeiTheme.moss.opacity(0.92)
        case .note:
            return hovering ? WeiBeiTheme.link : WeiBeiTheme.link.opacity(0.90)
        case .selection:
            return hovering ? WeiBeiTheme.cinnabar : WeiBeiTheme.cinnabar.opacity(0.88)
        case .learningRecord:
            return hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk
        case .learningMemory:
            return hovering ? WeiBeiTheme.secondaryInk : WeiBeiTheme.tertiaryInk
        case .session:
            return WeiBeiTheme.tertiaryInk
        }
    }

    private var background: Color {
        switch citation.kind {
        case .material:
            return WeiBeiTheme.moss.opacity(hovering ? 0.14 : 0.09)
        case .note:
            return WeiBeiTheme.link.opacity(hovering ? 0.12 : 0.07)
        case .selection:
            return WeiBeiTheme.cinnabarSoft.opacity(hovering ? 0.55 : 0.38)
        case .learningRecord:
            return WeiBeiTheme.paperInset.opacity(hovering ? 0.55 : 0.38)
        case .learningMemory:
            return WeiBeiTheme.paperInset.opacity(hovering ? 0.42 : 0.28)
        case .session:
            return WeiBeiTheme.paperInset.opacity(0.22)
        }
    }

    private var border: Color {
        switch citation.kind {
        case .material:
            return WeiBeiTheme.moss.opacity(hovering ? 0.34 : 0.20)
        case .note:
            return WeiBeiTheme.link.opacity(hovering ? 0.32 : 0.18)
        case .selection:
            return WeiBeiTheme.cinnabar.opacity(hovering ? 0.36 : 0.22)
        case .learningRecord, .learningMemory, .session:
            return WeiBeiTheme.hairline.opacity(hovering ? 0.55 : 0.36)
        }
    }
}

/// Session-scoped first-frame height seeds for finalized agent Markdown rows.
/// The bucket never proves measurement success at the current exact width.
private enum AgentFinalizedMarkdownHeightCache {
    private static let lock = NSLock()
    private static var values: [String: CGFloat] = [:]

    static func height(for key: String) -> CGFloat? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    static func store(_ height: CGFloat, for key: String) {
        // Called only from a real WebKit contentHeightChanged event. Store the
        // raw measured value, including legitimate <=44pt short block content;
        // the synthetic 44pt SwiftUI loading frame never reaches this method.
        guard height.isFinite, height > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        if let existing = values[key], abs(existing - height) < 2 { return }
        values[key] = height
    }

    static func cacheKey(messageID: UUID?, text: String, widthBucket: Int) -> String {
        let id = messageID?.uuidString ?? "anon"
        let prefix = text.prefix(64)
        return "\(id):\(text.count):\(prefix):w\(widthBucket)"
    }

    static func widthBucket(_ width: CGFloat) -> Int {
        max(Int((width / 24.0).rounded(.down)) * 24, 0)
    }
}

private struct AgentChatLayoutWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private extension EnvironmentValues {
    var agentChatLayoutWidth: CGFloat {
        get { self[AgentChatLayoutWidthKey.self] }
        set { self[AgentChatLayoutWidthKey.self] = newValue }
    }
}

/// Agent chat markdown — shared by immersive conversation and selection float.
/// - Finalized assistant turns: full `MarkdownPreviewView` with width-aware frozen height.
/// - Streaming, user turns, failures, and renderer fallback: native `AttributedString`.
private struct AgentMessageMarkdownText: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.agentChatLayoutWidth) private var layoutWidth
    var text: String
    var rendersRichMarkdown: Bool
    /// Selection-float / narrow surfaces: smaller type, still fills available width.
    var compact: Bool = false
    /// Completed assistant turns only — never streaming, user, or failure bubbles.
    var usesFinalizedKaTeX: Bool = false
    var messageID: UUID? = nil
    @State private var finalizedRendererReady = false
    @State private var finalizedRendererFailed = false

    private var finalizedMarkdown: String {
        AgentChatKaTeXMarkdown.prepare(text)
    }

    /// Coarse cache bucket only; exactLayoutWidthKey below controls remeasurement.
    private var layoutWidthBucket: Int {
        AgentFinalizedMarkdownHeightCache.widthBucket(layoutWidth)
    }

    private var exactLayoutWidthKey: Int {
        max(Int(layoutWidth.rounded()), 0)
    }

    private var shouldUseFinalizedMarkdown: Bool {
        usesFinalizedKaTeX && rendersRichMarkdown
            && AgentChatKaTeXMarkdown.requiresWebRenderer(finalizedMarkdown)
    }

    var body: some View {
        Group {
            if shouldUseFinalizedMarkdown {
                finalizedMarkdownBody
            } else {
                nativeBody
            }
        }
        .modifier(AgentMessageTextWidthModifier(fillsReadingColumn: rendersRichMarkdown || compact))
        .onChange(of: finalizedMarkdown) { _, _ in
            finalizedRendererReady = false
            finalizedRendererFailed = false
        }
    }

    private var cacheKey: String {
        AgentFinalizedMarkdownHeightCache.cacheKey(
            messageID: messageID,
            text: finalizedMarkdown,
            widthBucket: layoutWidthBucket
        )
    }

    private var cachedFinalizedHeight: CGFloat? {
        AgentFinalizedMarkdownHeightCache.height(for: cacheKey)
    }

    @ViewBuilder
    private var finalizedMarkdownBody: some View {
        // The mature Markdown renderer handles paragraphs, headings, lists, tables,
        // fenced code and KaTeX through one path. Native text stays visible until
        // the first valid measurement and returns immediately if WebKit fails.
        // Height freezes only after a real measure at the current exact width.
        // The 24pt-bucket cache supplies a first-frame seed, never readiness.
        // NEVER wire onContentHeightChange to scrollAgentToBottom.
        ZStack(alignment: .topLeading) {
            if !finalizedRendererReady {
                nativeBody
                    .background(WeiBeiTheme.paper)
                    .zIndex(1)
            }
            if !finalizedRendererFailed {
                MarkdownPreviewView(
                    markdown: finalizedMarkdown,
                    markdownBaseURL: store.currentMarkdownBaseURL,
                    appearanceMode: store.appearanceMode,
                    interfaceLanguage: store.interfaceLanguage,
                    compact: true,
                    fitsContentHeight: true,
                    freezeHeightAfterMeasure: true,
                    seedContentHeight: cachedFinalizedHeight,
                    layoutWidthKey: exactLayoutWidthKey,
                    onWikiLink: { title in store.openOrCreateWikiNote(title: title) },
                    onSourceReference: { reference in store.openSourceReference(reference) },
                    onAppShortcut: { key, modifiers in store.handleAppShortcut(key: key, modifiers: modifiers) },
                    onRenderReady: {
                        finalizedRendererFailed = false
                    },
                    onRenderFailure: {
                        finalizedRendererReady = false
                        finalizedRendererFailed = true
                    },
                    onMeasuredHeight: { height in
                        AgentFinalizedMarkdownHeightCache.store(height, for: cacheKey)
                        finalizedRendererReady = true
                    }
                )
                .allowsHitTesting(finalizedRendererReady)
                .accessibilityHidden(!finalizedRendererReady)
                .zIndex(0)
            }
        }
    }

    private var nativeBody: some View {
        Text(renderedText)
            .font(.system(size: compact ? 13.2 : (rendersRichMarkdown ? 15 : 14.5)))
            .lineSpacing(compact ? 4.2 : (rendersRichMarkdown ? 5.5 : 4.5))
            .foregroundStyle(WeiBeiTheme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            // Selectable chat text — wheel still reaches ScrollView via Text's default handling.
            .textSelection(.enabled)
    }

    private var renderedText: AttributedString {
        // Streaming / no-math path: Unicode math readability without WKWebView.
        let display = RichAnswerDisplayText.normalizedInlineMath(text)
        return (try? AttributedString(markdown: display)) ?? AttributedString(display)
    }
}

private struct AgentMessageTextWidthModifier: ViewModifier {
    let fillsReadingColumn: Bool

    func body(content: Content) -> some View {
        if fillsReadingColumn {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Hug text width (wraps within the bubble's maxWidth: 520), not a full-width bar.
            content
        }
    }
}

/// Product loading motion — 「行文进行中 V3」.
/// Driven solely by `store.agentActivityText` (no demo status carousel).
///
/// Hang-proof: motion runs in a fixed-size `NSView` + `CADisplayLink` that only
/// `setNeedsDisplay()`. It never enters SwiftUI `TimelineView`, so parent
/// `ScrollView` / `LazyVStack` do not re-run `sizeThatFits` every frame
/// (that thrash was freezing the app after a couple of scrolls).
///
/// Geometry: cinnabar orbit keeps equal padding on all four sides of the status text.
///
/// Model (view coords, flipped):
/// ```
/// ┌──────── path (stroke centerline) ────────┐
/// │  pad                                     │
/// │     ┌──── glyph / line box ────┐         │
/// │ pad │  加载词                  │ pad     │
/// │     └──────────────────────────┘         │
/// │  pad                                     │
/// └──────────────────────────────────────────┘
/// ```
/// `orbitPadding` is the clear gap from the line-box edge to the stroke *centerline*
/// on every side. Half the stroke width sits outside that centerline, so the view
/// grows by `lineWidth` total to avoid clipping.
private struct AgentThinkingIndicator: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cachedText = ""
    @State private var cachedTextWidth: CGFloat = 1
    @State private var motionEpoch = Date()

    private static let statusFontSize: CGFloat = 12
    /// Clear gap from line-box edge → stroke centerline (all four sides).
    private static let orbitPadding: CGFloat = 5.5
    private static let lineWidth: CGFloat = 1.25
    /// Line box height matches the font’s typographic bounds so top/bottom pad stay equal.
    private static var textLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: statusFontSize, weight: .medium)
        return max(1, ceil(font.ascender - font.descender))
    }
    /// Outer view size = line box + equal pad on both sides + half stroke outside the path.
    private static var pathOuterInset: CGFloat { orbitPadding + lineWidth / 2 }
    private static var pathHeight: CGFloat { textLineHeight + pathOuterInset * 2 }

    private var statusText: String {
        store.agentActivityText ?? store.ui("正在思考", "Thinking")
    }

    var body: some View {
        let text = cachedText.isEmpty ? statusText : cachedText
        let textWidth = max(1, cachedTextWidth)
        let orbitWidth = textWidth + Self.pathOuterInset * 2
        let pathHeight = Self.pathHeight

        Group {
            if reduceMotion {
                Text(text)
                    .font(.system(size: Self.statusFontSize, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.ink.opacity(0.93))
                    .lineLimit(1)
                    .frame(width: textWidth, height: Self.textLineHeight, alignment: .leading)
                    .padding(Self.pathOuterInset)
            } else {
                // AppKit host: fixed intrinsic size; ticks only repaint the NSView.
                AgentThinkingOrbitHost(
                    text: text,
                    textWidth: textWidth,
                    orbitWidth: orbitWidth,
                    pathHeight: pathHeight,
                    orbitPadding: Self.orbitPadding,
                    textLineHeight: Self.textLineHeight,
                    lineWidth: Self.lineWidth,
                    motionEpoch: motionEpoch,
                    appearanceMode: store.appearanceMode
                )
                .frame(width: orbitWidth, height: pathHeight, alignment: .leading)
                .allowsHitTesting(false)
            }
        }
        .frame(width: orbitWidth, height: pathHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear {
            refreshCache(for: statusText)
            motionEpoch = Date()
        }
        .onChange(of: statusText) { _, newText in
            // Interrupt mid-orbit immediately; restart first bottom proofreading pass.
            refreshCache(for: newText)
            motionEpoch = Date()
        }
    }

    private func refreshCache(for text: String) {
        cachedText = text
        cachedTextWidth = Self.measuredWidth(for: text)
    }

    private static func measuredWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: statusFontSize, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return max(1, ceil(size.width))
    }
}

/// Bridges V3 orbit motion into AppKit so SwiftUI layout never sees per-frame updates.
private struct AgentThinkingOrbitHost: NSViewRepresentable {
    let text: String
    let textWidth: CGFloat
    let orbitWidth: CGFloat
    let pathHeight: CGFloat
    let orbitPadding: CGFloat
    let textLineHeight: CGFloat
    let lineWidth: CGFloat
    let motionEpoch: Date
    let appearanceMode: WeiBeiAppearanceMode

    func makeNSView(context: Context) -> AgentThinkingOrbitNSView {
        let view = AgentThinkingOrbitNSView()
        view.wantsLayer = true
        view.apply(
            text: text,
            textWidth: textWidth,
            orbitWidth: orbitWidth,
            pathHeight: pathHeight,
            orbitPadding: orbitPadding,
            textLineHeight: textLineHeight,
            lineWidth: lineWidth,
            motionEpoch: motionEpoch,
            appearanceMode: appearanceMode
        )
        return view
    }

    func updateNSView(_ nsView: AgentThinkingOrbitNSView, context: Context) {
        nsView.apply(
            text: text,
            textWidth: textWidth,
            orbitWidth: orbitWidth,
            pathHeight: pathHeight,
            orbitPadding: orbitPadding,
            textLineHeight: textLineHeight,
            lineWidth: lineWidth,
            motionEpoch: motionEpoch,
            appearanceMode: appearanceMode
        )
    }
}

/// Fixed-size AppKit painter for 「行文进行中 V3」: reveal + first-pass underline + TextOrbitSegment.
/// Text sits in a line box; orbit stroke centerline keeps equal `orbitPadding` on all four sides.
final class AgentThinkingOrbitNSView: NSView {
    private static let statusFontSize: CGFloat = 12
    private static let segmentLength: CGFloat = 10
    private static let firstPassDuration: TimeInterval = 0.88
    private static let orbitDuration: TimeInterval = 2.25

    private var statusText = ""
    private var textWidth: CGFloat = 1
    private var orbitWidth: CGFloat = 1
    private var pathHeight: CGFloat = 26
    private var orbitPadding: CGFloat = 5.5
    private var textLineHeight: CGFloat = 15
    private var lineWidth: CGFloat = 1.25
    private var motionEpoch = Date()
    private var appearanceMode: WeiBeiAppearanceMode = .paper
    private var displayLink: CADisplayLink?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: orbitWidth, height: pathHeight)
    }

    deinit {
        stopDisplayLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    func apply(
        text: String,
        textWidth: CGFloat,
        orbitWidth: CGFloat,
        pathHeight: CGFloat,
        orbitPadding: CGFloat,
        textLineHeight: CGFloat,
        lineWidth: CGFloat,
        motionEpoch: Date,
        appearanceMode: WeiBeiAppearanceMode
    ) {
        let sizeChanged = abs(self.orbitWidth - orbitWidth) > 0.5
            || abs(self.pathHeight - pathHeight) > 0.5
        statusText = text
        self.textWidth = max(1, textWidth)
        self.orbitWidth = max(1, orbitWidth)
        self.pathHeight = max(1, pathHeight)
        self.orbitPadding = max(1, orbitPadding)
        self.textLineHeight = max(1, textLineHeight)
        self.lineWidth = max(0.5, lineWidth)
        self.motionEpoch = motionEpoch
        self.appearanceMode = appearanceMode
        if sizeChanged {
            invalidateIntrinsicContentSize()
        }
        // Paint only — do not call setNeedsLayout / invalidate parent SwiftUI layout.
        needsDisplay = true
        if window != nil {
            startDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(handleDisplayTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayTick() {
        // Local repaint only. Never touch SwiftUI state from here.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = CGRect(x: 0, y: 0, width: orbitWidth, height: pathHeight)
        context.clear(bounds)

        let elapsed = max(0, Date().timeIntervalSince(motionEpoch))
        let reveal = TextOrbitSegment.revealProgress(at: elapsed)
        let firstPass = elapsed < Self.firstPassDuration
        let cursorProgress = firstPass ? reveal : 1
        let cursorOpacity = firstPass
            ? TextOrbitSegment.smootherStep(TextOrbitSegment.clamp(reveal / 0.14))
                * (1 - TextOrbitSegment.smootherStep(TextOrbitSegment.clamp((elapsed - 0.82) / 0.16)))
            : 0
        let orbitOpacity = firstPass
            ? TextOrbitSegment.smootherStep(TextOrbitSegment.clamp((elapsed - 0.82) / 0.18))
            : 1
        let orbitProgress = TextOrbitSegment.orbitProgress(at: elapsed)

        let ink = WeiBeiNativePalette.ink(for: appearanceMode).withAlphaComponent(0.93)
        let dim = WeiBeiNativePalette.tertiaryInk(for: appearanceMode).withAlphaComponent(0.70)
        let cinnabar = WeiBeiNativePalette.cinnabar(for: appearanceMode).withAlphaComponent(0.82)

        let font = NSFont.systemFont(ofSize: Self.statusFontSize, weight: .medium)
        // Line box inset so every side has the same gap to the stroke centerline.
        // view edge → stroke center = lineWidth/2
        // stroke center → line box edge = orbitPadding
        let contentOrigin = orbitPadding + lineWidth / 2
        let textRect = CGRect(
            x: contentOrigin,
            y: contentOrigin,
            width: textWidth,
            height: textLineHeight
        )
        // draw(in:) top-aligns in the flipped line box. Line-box height == ascender−descender,
        // so ink fills the box and all four sides keep the same gap to the stroke centerline.
        // Do not add capHeight/descender fudge — that broke equal top/bottom padding.
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        let dimAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dim,
            .paragraphStyle: paragraph
        ]
        (statusText as NSString).draw(in: textRect, withAttributes: dimAttributes)

        if reveal > 0.001 {
            context.saveGState()
            context.clip(
                to: CGRect(
                    x: textRect.minX,
                    y: 0,
                    width: textWidth * CGFloat(reveal),
                    height: pathHeight
                )
            )
            let inkAttributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: ink,
                .paragraphStyle: paragraph
            ]
            (statusText as NSString).draw(in: textRect, withAttributes: inkAttributes)
            context.restoreGState()
        }

        // First-pass proofread line: center of the bottom equal-padding band.
        if cursorOpacity > 0.01 {
            let bottomBandCenterY = textRect.maxY + orbitPadding / 2
            let x = textRect.minX + max(0, (textWidth - Self.segmentLength) * CGFloat(cursorProgress))
            let y = bottomBandCenterY - lineWidth / 2
            let segment = CGRect(x: x, y: y, width: Self.segmentLength, height: lineWidth)
            context.saveGState()
            context.setAlpha(CGFloat(cursorOpacity))
            context.setFillColor(cinnabar.cgColor)
            let path = CGPath(
                roundedRect: segment,
                cornerWidth: lineWidth / 2,
                cornerHeight: lineWidth / 2,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }

        // Orbit stroke centerline: equal orbitPadding from the line box on all four sides.
        if orbitOpacity > 0.01 {
            context.saveGState()
            context.setAlpha(CGFloat(orbitOpacity))
            TextOrbitSegment.stroke(
                progress: orbitProgress,
                width: orbitWidth,
                height: pathHeight,
                segmentLength: Self.segmentLength,
                lineWidth: lineWidth,
                color: cinnabar,
                in: context
            )
            context.restoreGState()
        }
    }
}

/// Short cinnabar segment orbiting a measured text box (V3 path geometry).
/// Pure geometry/paint helper — not a SwiftUI View — so it cannot thrash ScrollView layout.
enum TextOrbitSegment {
    static let firstPassDuration: TimeInterval = 0.88
    static let orbitDuration: TimeInterval = 2.25

    static func revealProgress(at elapsed: TimeInterval) -> Double {
        let raw = clamp((elapsed - 0.10) / 0.78)
        return 1 - pow(1 - raw, 3.2)
    }

    static func orbitProgress(at elapsed: TimeInterval) -> Double {
        guard elapsed >= firstPassDuration else { return 0 }
        let t = (elapsed - firstPassDuration) / orbitDuration
        let remainder = t.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func smootherStep(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    static func stroke(
        progress: Double,
        width: CGFloat,
        height: CGFloat,
        segmentLength: CGFloat,
        lineWidth: CGFloat,
        color: NSColor,
        in context: CGContext
    ) {
        let normalized = CGFloat(((progress.truncatingRemainder(dividingBy: 1)) + 1).truncatingRemainder(dividingBy: 1))
        let perimeter = TextOrbitPath.estimatedPerimeter(width: width, height: height, lineWidth: lineWidth)
        let fraction = min(0.08, segmentLength / max(1, perimeter))
        let end = normalized + fraction
        let fullPath = TextOrbitPath.cgPath(width: width, height: height, lineWidth: lineWidth)

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if end <= 1 {
            strokeTrimmed(fullPath, from: normalized, to: end, in: context)
        } else {
            strokeTrimmed(fullPath, from: normalized, to: 1, in: context)
            strokeTrimmed(fullPath, from: 0, to: end - 1, in: context)
        }
    }

    private static func strokeTrimmed(_ path: CGPath, from start: CGFloat, to end: CGFloat, in context: CGContext) {
        guard end > start else { return }
        let trimmed = path.trimmedPath(from: start, to: end)
        context.addPath(trimmed)
        context.strokePath()
    }
}

/// V3 orbit geometry: rounded rectangle starting bottom-right, clockwise.
/// Path centerline sits `lineWidth/2` inside the view so the stroke is fully visible
/// and the clear gap to the text line box is equal on all four sides.
enum TextOrbitPath {
    /// Matches AgentThinkingOrbitNSView lineWidth default; stroke() passes the live width via inset.
    static let defaultLineWidth: CGFloat = 1.25

    static func estimatedPerimeter(width: CGFloat, height: CGFloat, lineWidth: CGFloat = defaultLineWidth) -> CGFloat {
        let inset = lineWidth / 2
        let radius: CGFloat = 3
        let w = max(1, width - inset * 2)
        let h = max(1, height - inset * 2)
        return max(1, 2 * (w + h) - 8 * radius + 2 * .pi * radius)
    }

    static func cgPath(width: CGFloat, height: CGFloat, lineWidth: CGFloat = defaultLineWidth) -> CGPath {
        // Stroke centerline inset = half line width → equal visual margins when text box
        // is placed at (pad + lineWidth/2) with the same pad on every side.
        let inset = lineWidth / 2
        let radius: CGFloat = 3
        let minX = inset
        let maxX = width - inset
        let minY = inset
        let maxY = height - inset

        let path = CGMutablePath()
        path.move(to: CGPoint(x: maxX - radius, y: maxY))
        path.addQuadCurve(to: CGPoint(x: maxX, y: maxY - radius), control: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: maxX, y: minY + radius))
        path.addQuadCurve(to: CGPoint(x: maxX - radius, y: minY), control: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: minX + radius, y: minY))
        path.addQuadCurve(to: CGPoint(x: minX, y: minY + radius), control: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX, y: maxY - radius))
        path.addQuadCurve(to: CGPoint(x: minX + radius, y: maxY), control: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: maxX - radius, y: maxY))
        path.closeSubpath()
        return path
    }
}

private extension CGPath {
    /// Approximate trim for a closed path by walking the flattened polyline.
    func trimmedPath(from start: CGFloat, to end: CGFloat) -> CGPath {
        let points = flattenedPoints()
        guard points.count >= 2 else { return self }

        var lengths: [CGFloat] = [0]
        var total: CGFloat = 0
        for index in 1..<points.count {
            total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
            lengths.append(total)
        }
        guard total > 0 else { return self }

        let startDistance = max(0, min(1, start)) * total
        let endDistance = max(0, min(1, end)) * total
        guard endDistance > startDistance else { return CGMutablePath() }

        let result = CGMutablePath()
        var started = false
        for index in 1..<points.count {
            let segmentStart = lengths[index - 1]
            let segmentEnd = lengths[index]
            if segmentEnd < startDistance { continue }
            if segmentStart > endDistance { break }

            let fromT = segmentEnd == segmentStart
                ? 0
                : max(0, (startDistance - segmentStart) / (segmentEnd - segmentStart))
            let toT = segmentEnd == segmentStart
                ? 1
                : min(1, (endDistance - segmentStart) / (segmentEnd - segmentStart))
            let p0 = points[index - 1]
            let p1 = points[index]
            let fromPoint = CGPoint(
                x: p0.x + (p1.x - p0.x) * fromT,
                y: p0.y + (p1.y - p0.y) * fromT
            )
            let toPoint = CGPoint(
                x: p0.x + (p1.x - p0.x) * toT,
                y: p0.y + (p1.y - p0.y) * toT
            )
            if !started {
                result.move(to: fromPoint)
                started = true
            }
            result.addLine(to: toPoint)
        }
        return result
    }

    func flattenedPoints() -> [CGPoint] {
        var points: [CGPoint] = []
        applyWithBlock { elementPointer in
            Self.appendFlattened(element: elementPointer.pointee, into: &points)
        }
        return points
    }

    private static func appendFlattened(element: CGPathElement, into points: inout [CGPoint]) {
        switch element.type {
        case .moveToPoint:
            points.append(element.points[0])
        case .addLineToPoint:
            points.append(element.points[0])
        case .addQuadCurveToPoint:
            appendQuad(
                from: points.last ?? element.points[1],
                control: element.points[0],
                to: element.points[1],
                into: &points
            )
        case .addCurveToPoint:
            appendCubic(
                from: points.last ?? element.points[2],
                c1: element.points[0],
                c2: element.points[1],
                to: element.points[2],
                into: &points
            )
        case .closeSubpath:
            if let first = points.first {
                points.append(first)
            }
        @unknown default:
            break
        }
    }

    private static func appendQuad(
        from start: CGPoint,
        control: CGPoint,
        to end: CGPoint,
        into points: inout [CGPoint]
    ) {
        for step in 1...8 {
            let t = CGFloat(step) / 8
            let mt = 1 - t
            let x = mt * mt * start.x + 2 * mt * t * control.x + t * t * end.x
            let y = mt * mt * start.y + 2 * mt * t * control.y + t * t * end.y
            points.append(CGPoint(x: x, y: y))
        }
    }

    private static func appendCubic(
        from start: CGPoint,
        c1: CGPoint,
        c2: CGPoint,
        to end: CGPoint,
        into points: inout [CGPoint]
    ) {
        for step in 1...8 {
            let t = CGFloat(step) / 8
            let mt = 1 - t
            let x = mt * mt * mt * start.x
                + 3 * mt * mt * t * c1.x
                + 3 * mt * t * t * c2.x
                + t * t * t * end.x
            let y = mt * mt * mt * start.y
                + 3 * mt * mt * t * c1.y
                + 3 * mt * t * t * c2.y
                + t * t * t * end.y
            points.append(CGPoint(x: x, y: y))
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
            // Streaming stays native + throttled — KaTeX only after the turn finalizes.
            AgentStreamingMarkdownText(text: text, compact: false)
        }
        .padding(.vertical, 10)
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text(store.ui("PI 正在回答", "PI is responding")))
    }
}

/// Throttled native markdown for in-flight tokens (avoids per-token AttributedString thrash).
private struct AgentStreamingMarkdownText: View {
    var text: String
    var compact: Bool = false
    @State private var displayedText = ""
    @State private var flushTask: Task<Void, Never>?

    var body: some View {
        AgentMessageMarkdownText(
            text: displayedText.isEmpty ? text : displayedText,
            rendersRichMarkdown: true,
            compact: compact,
            usesFinalizedKaTeX: false
        )
        .onAppear {
            displayedText = text
        }
        .onChange(of: text) { _, newValue in
            flushTask?.cancel()
            flushTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                guard !Task.isCancelled else { return }
                displayedText = newValue
            }
        }
        .onDisappear {
            flushTask?.cancel()
        }
    }
}
