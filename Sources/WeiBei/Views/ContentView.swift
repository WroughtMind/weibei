import AppKit
import SwiftUI
import WeiBeiCore

struct ContentView: View {
    /// Intentionally does NOT observe `libraryDrawer` / `paneState` / `interaction` —
    /// those chrome surfaces rebuild dedicated child layers so reader/agent/notes stay put.
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weiBeiTextScale) private var textScale
    @FocusState private var focusedPane: PaneFocus?
    @FocusState private var topSearchFocused: Bool
    @State private var floatingAgentExpanded = false
    @State private var windowIsFullScreen = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                WorkspaceChromeBackdrop(isFullScreen: windowIsFullScreen)

                VStack(spacing: 0) {
                    UnifiedTopBarView(
                        isImmersiveLayout: isImmersiveLayout,
                        isFullScreen: windowIsFullScreen,
                        searchFocused: $topSearchFocused
                    )

                    if store.isCourseLibraryRootVolatile {
                        CourseLibraryVolatilityBanner()
                    }

                    ZStack(alignment: .top) {
                        LayoutContentView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                store.appearanceMode.isGlass
                                    ? Color.clear
                                    : Color(nsColor: WeiBeiNativePalette.paper(for: store.appearanceMode))
                            )
                            // Only cross-fade immersive ↔ document families. Pane show/hide inside
                            // the document family is owned by AppKit StableDocumentWorkspace animation
                            // — a second SwiftUI layout animation here made toggles feel split/janky.
                            .animation(WeiBeiMotion.layout, value: store.layout.isImmersiveFamily)

                        // AppKit drawer: slide starts immediately; sidebar not store-synced while closed.
                        CourseLibraryDrawerLayer(store: store) {
                            store.toggleLibrary()
                        }
                        .zIndex(35)

                        if store.commandPalettePresented {
                            CommandPaletteView()
                                .transition(WeiBeiTransition.commandPalette)
                                .zIndex(40)
                        }

                        // Selection float observes `interaction` only — drag must not rebuild ContentView.
                        GlobalFloatingSelectionLayer(
                            expanded: $floatingAgentExpanded,
                            canvasSize: geometry.size
                        )
                        .zIndex(30)
                    }
                }
                .allowsHitTesting(!store.courseWorkspacePresented)
                .accessibilityHidden(store.courseWorkspacePresented)
                .opacity(
                    store.courseWorkspacePresented && store.appearanceMode.isGlass
                        ? 0
                        : 1
                )

                if store.courseWorkspacePresented {
                    ZStack {
                        Color(nsColor: WeiBeiNativePalette.foregroundWorkspaceSurface(
                            for: store.appearanceMode
                        ))
                        CourseWorkspaceView()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.995, anchor: .top)))
                    .zIndex(100)
                }

                // Single top-level status surface: important errors first, otherwise
                // the transient note status. Sits above the course space so it stays
                // visible wherever the user is; the old notes-pane-local copy is gone.
                if store.importantOperationError != nil || store.transientNoteStatus != nil {
                    WorkspaceStatusBanner()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, WeiBeiMetric.topBarHeight * textScale + 10)
                        .zIndex(120)
                        .transition(WeiBeiTransition.floating)
                }

                if store.courseFileOperationProgress != nil {
                    ImportProgressPill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 16)
                        .padding(.bottom, 16)
                        .zIndex(120)
                        .transition(WeiBeiTransition.floating)
                }
            }
            .animation(WeiBeiMotion.panel, value: store.importantOperationError)
            .animation(WeiBeiMotion.panel, value: store.transientNoteStatus)
            .background {
                LibraryAwareEscapeBridge(
                    courseWorkspacePresented: store.courseWorkspacePresented,
                    onToggleLibrary: { store.toggleLibrary() },
                    onDismissFloatingAgent: { store.dismissFloatingSelectionAgent() },
                    onHideReaderSearch: {
                        store.hideReaderSearch()
                        topSearchFocused = false
                    }
                )
            }
        }
        .background(WindowFullScreenReader(isFullScreen: $windowIsFullScreen))
        .background {
            // Focus / reader-search sync observes paneState so ContentView does not.
            PaneChromeFocusBridge(
                focusedPane: $focusedPane,
                topSearchFocused: $topSearchFocused
            )
        }
        .onAppear {
            focusedPane = store.focusedPane
            guard WeiBeiPerf.isEnabled else { return }
            DispatchQueue.main.async {
                WeiBeiPerf.finishLaunch()
            }
        }
        // Theme animation is owned by `setAppearanceMode` (single transaction).
        // A second root `.animation(value: appearanceMode)` desynced chrome vs paper.
        // showLibrary animation is scoped to the drawer ZStack only (above).
        .animation(WeiBeiMotion.panel, value: store.courseWorkspacePresented)
        .confirmationDialog(
            store.ui(
                "“\(store.runningAgentChatTitle)”仍在回答",
                "“\(store.runningAgentChatTitle)” is still responding"
            ),
            isPresented: Binding(
                get: { store.isAgentSwitchConfirmationPresented },
                set: { if !$0 { store.dismissAgentSwitchConfirmation() } }
            ),
            titleVisibility: .visible
        ) {
            Button(store.ui("停止原回答并发送", "Stop it and send")) {
                store.confirmAgentSwitchAndSend()
            }
            Button(store.ui("取消", "Cancel"), role: .cancel) {
                store.dismissAgentSwitchConfirmation()
            }
        } message: {
            Text(store.ui(
                "不会排队。确认后，魏碑会先保存原 Chat 已生成的正文，再在当前 Chat 提问。",
                "Nothing is queued. WeiBei will preserve the generated text, stop the original reply, then send in the current Chat."
            ))
        }
    }

    private var isImmersiveLayout: Bool {
        [.immersiveReading, .immersiveConversation, .immersiveWriting].contains(store.layout)
    }
}

private struct WindowFullScreenReader: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isFullScreen = $isFullScreen
        context.coordinator.attach(to: view)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator {
        var isFullScreen: Binding<Bool>
        private weak var view: NSView?
        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        func attach(to view: NSView) {
            self.view = view
            DispatchQueue.main.async { [weak self] in
                self?.observeWindowIfReady()
            }
        }

        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            observedWindow = nil
        }

        private func observeWindowIfReady() {
            guard let window = view?.window else { return }
            isFullScreen.wrappedValue = window.styleMask.contains(.fullScreen)
            guard observedWindow !== window else { return }
            stopObserving()
            observedWindow = window
            let names: [NSNotification.Name] = [
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self, weak window] _ in
                    self?.isFullScreen.wrappedValue = window?.styleMask.contains(.fullScreen) == true
                }
            }
        }
    }
}

/// AppKit course drawer layer. Observes only `LibraryDrawerState`; the store reference
/// is passed through without subscribing this chrome layer to the whole workspace.
private struct CourseLibraryDrawerLayer: View {
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    let store: WorkspaceStore
    let dismiss: () -> Void

    var body: some View {
        CourseDrawerHost(
            drawer: libraryDrawer,
            store: store,
            onDismiss: dismiss
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(libraryDrawer.isOpen)
            .accessibilityHidden(!libraryDrawer.isOpen)
    }
}

/// Syncs `@FocusState` from `WorkspacePaneState` without ContentView observing pane chrome.
private struct PaneChromeFocusBridge: View {
    @EnvironmentObject private var paneState: WorkspacePaneState
    var focusedPane: FocusState<PaneFocus?>.Binding
    var topSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: paneState.focusedPane) { _, value in
                focusedPane.wrappedValue = value
            }
            .onChange(of: paneState.showReaderSearch) { _, visible in
                topSearchFocused.wrappedValue = visible
            }
            .onAppear {
                focusedPane.wrappedValue = paneState.focusedPane
                topSearchFocused.wrappedValue = paneState.showReaderSearch
            }
    }
}

/// Selection float layer. Observes `WorkspaceInteractionState` (+ store for chat routing).
private struct GlobalFloatingSelectionLayer: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @Environment(\.weiBeiTextScale) private var textScale
    @Binding var expanded: Bool
    let canvasSize: CGSize

    var body: some View {
        Group {
            if showsGlobalFloatingAgent {
                FloatingSelectionAgentView(
                    expanded: $expanded,
                    routesToConversation: store.isConversationSurfaceVisible
                )
                .position(floatingAgentPosition)
                .transition(WeiBeiTransition.floating)
                .onChange(of: interaction.keepFloatingSelectionForAnswer) { _, keep in
                    // Expand only when an intentional keep-open is requested
                    // (点「问」/回访红线/顶部已问), not on bare selection.
                    if keep { expanded = true }
                }
                .onChange(of: interaction.activeSelectionAskThreadID) { _, id in
                    if id != nil, interaction.keepFloatingSelectionForAnswer {
                        expanded = true
                    }
                }
                .onChange(of: interaction.selectionContext?.id) { _, _ in
                    // Live reselection collapses to capsule; reopen-with-keepOpen must stay expanded.
                    guard !interaction.pinnedFloatingAgent,
                          !store.isAgentRunningInActiveChat,
                          !interaction.keepFloatingSelectionForAnswer else { return }
                    expanded = false
                }
            }
        }
    }

    private var showsGlobalFloatingAgent: Bool {
        // Show the selection capsule in multi-pane as well as immersive reading.
        // When the chat pane is open, the float still appears; "问" routes into the
        // conversation via `routesToConversation` (do not hide the capsule).
        !store.courseWorkspacePresented
            && store.canShowSelectionPromptSurface
            && SelectionFloatingAgentPlacement.isVisible(
                surface: interaction.agentSurface,
                hasSelection: interaction.selectionContext != nil || interaction.keepFloatingSelectionForAnswer,
                hasAnchor: interaction.selectionAnchor != nil,
                pinned: interaction.pinnedFloatingAgent,
                keepOpen: interaction.keepFloatingSelectionForAnswer
            )
    }

    private var floatingAgentPosition: CGPoint {
        let point = SelectionFloatingAgentPlacement.position(
            anchor: interaction.selectionAnchor.map { FloatingAgentCoordinate(x: Double($0.x), y: Double($0.y)) },
            canvas: FloatingAgentCoordinate(x: Double(canvasSize.width), y: Double(canvasSize.height)),
            topInset: Double(WeiBeiMetric.topBarHeight * textScale),
            surfaceHalfWidth: expanded
                ? SelectionFloatingAgentPlacement.expandedHalfWidth
                : (store.selectionContext?.isReplaceableNoteSelection == true
                    ? 144
                    : SelectionFloatingAgentPlacement.compactHalfWidth),
            prefersAnchorCenter: !expanded
        )
        return CGPoint(x: point.x, y: point.y)
    }
}

/// Top-level workspace feedback: important data-operation errors (persistent,
/// user-dismissed) take priority over the auto-expiring transient status.
private struct ImportProgressPill: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        let progress = store.courseFileOperationProgress
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(store.ui(
                "正在导入 \(progress?.completed ?? 0)/\(progress?.total ?? 0)：\(progress?.currentFileName ?? "")",
                "Importing \(progress?.completed ?? 0)/\(progress?.total ?? 0): \(progress?.currentFileName ?? "")"
            ))
            .weiBeiText(12, weight: .medium)
            .foregroundStyle(WeiBeiTheme.ink)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WeiBeiTheme.paperRaised.opacity(0.97))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(WeiBeiTheme.hairline.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.3 : 0.1), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(store.ui("正在导入文件", "Importing files")))
    }
}

private struct WorkspaceStatusBanner: View {
    @EnvironmentObject private var store: WorkspaceStore

    private var isImportant: Bool {
        store.importantOperationError != nil
    }

    private var message: String {
        store.importantOperationError ?? store.transientNoteStatus ?? ""
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isImportant ? "exclamationmark.triangle.fill" : "info.circle")
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(isImportant ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
            Text(message)
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if isImportant {
                Button {
                    store.dismissImportantOperationError()
                } label: {
                    Image(systemName: "xmark")
                        .weiBeiText(10, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("关闭错误提示", "Dismiss error")))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 440, alignment: .leading)
        .background(WeiBeiTheme.paperRaised.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isImportant
                        ? WeiBeiTheme.cinnabar.opacity(0.55)
                        : WeiBeiTheme.hairline.opacity(0.6),
                    lineWidth: 1
                )
        }
        .shadow(color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.3 : 0.1), radius: 12, y: 6)
        .allowsHitTesting(isImportant)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(store.ui("工作区状态提示", "Workspace status")))
    }
}

/// Escape routing that can observe drawer / pane / selection chrome without forcing ContentView to do so.
private struct LibraryAwareEscapeBridge: View {
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    @EnvironmentObject private var paneState: WorkspacePaneState
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @EnvironmentObject private var store: WorkspaceStore
    let courseWorkspacePresented: Bool
    let onToggleLibrary: () -> Void
    let onDismissFloatingAgent: () -> Void
    let onHideReaderSearch: () -> Void

    var body: some View {
        Group {
            if !courseWorkspacePresented && libraryDrawer.isOpen {
                EscapeKeyBridge(onEscape: onToggleLibrary)
            } else if !courseWorkspacePresented && !libraryDrawer.isOpen && showsGlobalFloatingAgent {
                EscapeKeyBridge(onEscape: onDismissFloatingAgent)
            } else if !courseWorkspacePresented && !libraryDrawer.isOpen && paneState.showReaderSearch {
                EscapeKeyBridge(onEscape: onHideReaderSearch)
            }
        }
    }

    private var showsGlobalFloatingAgent: Bool {
        !courseWorkspacePresented
            && store.canShowSelectionPromptSurface
            && SelectionFloatingAgentPlacement.isVisible(
                surface: interaction.agentSurface,
                hasSelection: interaction.selectionContext != nil || interaction.keepFloatingSelectionForAnswer,
                hasAnchor: interaction.selectionAnchor != nil,
                pinned: interaction.pinnedFloatingAgent,
                keepOpen: interaction.keepFloatingSelectionForAnswer
            )
    }
}

/// Window paper sits behind the top bar so empty-board glow and open-pane
/// paper continue through the chrome instead of becoming a second strip.
private struct WorkspaceChromeBackdrop: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var paneState: WorkspacePaneState
    let isFullScreen: Bool

    var body: some View {
        let empty = !paneState.showReader && !paneState.showAgent && !paneState.showNotes
        ZStack {
            WeiBeiThemeBackdrop(
                mode: store.appearanceMode,
                isFullScreen: isFullScreen
            )
            if empty {
                EmptyWorkspacePaperField(mode: store.appearanceMode, compact: false)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct UnifiedTopBarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var updateService: WeiBeiUpdateService
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    @EnvironmentObject private var paneState: WorkspacePaneState
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.weiBeiTextScale) private var textScale
    let isImmersiveLayout: Bool
    let isFullScreen: Bool
    var searchFocused: FocusState<Bool>.Binding
    @State private var appeared = false

    var body: some View {
        HStack(spacing: topBarSpacing) {
            Spacer()
                .frame(width: leftInset)

            leftPrimaryControls

            Spacer(minLength: 0)

            if paneState.showReaderSearch && shouldShowSearchAction {
                TextField(
                    "",
                    text: $store.readerSearch,
                    prompt: Text(store.ui("资料内搜索", "Search in material"))
                        .font(.system(size: 12))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                    .textFieldStyle(.plain)
                    .focused(searchFocused)
                    .foregroundColor(WeiBeiTheme.ink)
                    .foregroundStyle(WeiBeiTheme.ink)
                    .tint(WeiBeiTheme.link)
                    .weiBeiText(12)
                    .weibeiInputSurface(active: searchFocused.wrappedValue, height: controlHeight)
                    .frame(width: 220)
                .onExitCommand {
                    withAnimation(WeiBeiMotion.panel) {
                        store.hideReaderSearch()
                        searchFocused.wrappedValue = false
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if shouldShowSearchAction && !paneState.showReaderSearch {
                searchButton
            }

            // Copy-reference is not top-bar chrome: use ⌘⇧C, menu, or command palette when needed.

            topIconButton("command", help: store.ui("命令面板", "Command palette")) {
                store.commandPalettePresented.toggle()
            }

            // Theme lives only in Settings → Appearance (and ⌥⌘T). Top bar stays task chrome.
            // Full Settings window (agent keys, appearance, data) — not the old mini menu.
            topIconButton("slider.horizontal.3", help: store.ui("打开设置", "Open Settings")) {
                openSettings()
            }

            Spacer()
                .frame(width: 8)
        }
        .foregroundStyle(secondaryText)
        .offset(y: isFullScreen ? 0 : -2)
        .frame(height: barHeight)
        .background(topBarBackground)
        .overlay {
            paneToggleCluster
                .offset(y: isFullScreen ? 0 : -2)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -5)
        .onAppear {
            withAnimation(WeiBeiMotion.reveal) {
                appeared = true
            }
        }
        .animation(WeiBeiMotion.panel, value: paneState.showReaderSearch)
        .animation(WeiBeiMotion.layout, value: isImmersiveLayout)
        // Pane toggle active states live on paneState — keep this chrome reactive without ContentView.
        .animation(WeiBeiMotion.panel, value: paneState.showReader)
        .animation(WeiBeiMotion.panel, value: paneState.showAgent)
        .animation(WeiBeiMotion.panel, value: paneState.showNotes)
    }

    private var barHeight: CGFloat {
        WeiBeiMetric.topBarHeight * textScale
    }

    private var leftInset: CGFloat {
        CGFloat(TopBarLeadingInset.value(isFullScreen: isFullScreen))
    }

    private var topBarSpacing: CGFloat {
        7
    }

    private var controlHeight: CGFloat {
        28 * textScale
    }

    private var shouldShowSearchAction: Bool {
        store.hasSelectedMaterial && hasReaderScopedTopActions
    }

    private var hasReaderScopedTopActions: Bool {
        store.isPaneToggleActive(.reader)
    }

    private var primaryText: Color {
        WeiBeiTheme.ink
    }

    private var secondaryText: Color {
        WeiBeiTheme.secondaryInk
    }

    private var tertiaryText: Color {
        WeiBeiTheme.tertiaryInk
    }

    private var controlFill: Color {
        WeiBeiTheme.paperInset.opacity(0.38)
    }

    private var topBarBackground: some View {
        let empty = !paneState.showReader && !paneState.showAgent && !paneState.showNotes
        // Empty board keeps the glow visible through the bar. Open panes paint
        // the same theme surface as the workspace so the system titlebar cannot
        // leave a second strip above NOTE / READ / CHAT.
        return Group {
            if empty || store.appearanceMode.isGlass {
                Color.clear
            } else {
                Color(nsColor: WeiBeiNativePalette.paper(for: store.appearanceMode))
            }
        }
    }

    @ViewBuilder
    private var leftPrimaryControls: some View {
        HStack(spacing: 5) {
            libraryButton

            navigationButtons
        }
    }

    @ViewBuilder
    private var navigationButtons: some View {
        HStack(spacing: 3) {
            topIconButton("arrow.left", help: store.ui("后退", "Back")) {
                withAnimation(WeiBeiMotion.layout) {
                    store.navigateBackInWorkspace()
                }
            }
            .keyboardShortcut("[", modifiers: [.command])
            .disabled(!store.canNavigateBack)

            topIconButton("arrow.right", help: store.ui("前进", "Forward")) {
                withAnimation(WeiBeiMotion.layout) {
                    store.navigateForwardInWorkspace()
                }
            }
            .keyboardShortcut("]", modifiers: [.command])
            .disabled(!store.canNavigateForward)

            if updateService.showsToolbarControl, let update = updateService.availableUpdate {
                Button {
                    updateService.installAvailableUpdate()
                } label: {
                    if updateService.isBusy {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.down")
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(WeiBeiIconButtonStyle(active: true, size: 24))
                .disabled(updateService.isBusy)
                .accessibilityLabel(Text(store.ui("下载并安装魏碑更新", "Download and install the WeiBei update")))
                .help(updateHelpText(update))
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(WeiBeiMotion.panel, value: updateService.showsToolbarControl)
    }

    private func updateHelpText(_ update: WeiBeiAvailableUpdate) -> String {
        guard case let .failed(message) = updateService.status else {
            return update.helpText
        }
        return update.helpText + "\n" + store.ui("更新失败，点击重试：\(message)", "Update failed. Click to retry: \(message)")
    }

    private var paneToggleCluster: some View {
        WeiBeiSegmentedControl(segments: [
            WeiBeiSegmentedControl.Segment(
                id: "reader",
                systemImage: "doc.text",
                help: store.isPaneToggleActive(.reader) ? store.ui("隐藏文稿", "Hide document") : store.ui("显示文稿", "Show document"),
                isSelected: store.isPaneToggleActive(.reader),
                action: store.toggleReader
            ),
            WeiBeiSegmentedControl.Segment(
                id: "agent",
                systemImage: "bubble.left.and.text.bubble.right",
                help: agentPaneToggleHelp,
                isSelected: store.isPaneToggleActive(.agent),
                action: store.toggleAgent
            ),
            WeiBeiSegmentedControl.Segment(
                id: "notes",
                systemImage: "note.text",
                help: store.isPaneToggleActive(.notes) ? store.ui("隐藏笔记", "Hide notes") : store.ui("显示笔记", "Show notes"),
                isSelected: store.isPaneToggleActive(.notes),
                action: store.toggleNotes
            ),
        ])
    }

    private var agentPaneToggleHelp: String {
        if store.isPaneToggleActive(.agent) {
            return store.ui("隐藏对话", "Hide chat")
        }
        if interaction.selectionContext != nil {
            return store.ui("用当前选区打开对话", "Open chat with current selection")
        }
        return store.ui("显示对话", "Show chat")
    }

    @ViewBuilder
    private var libraryButton: some View {
        topIconButton(
            "sidebar.left",
            help: libraryDrawer.isOpen ? store.ui("收起课程抽屉", "Hide course drawer") : store.ui("打开课程抽屉", "Show course drawer"),
            active: libraryDrawer.isOpen
        ) {
            store.toggleLibrary()
        }
    }

    @ViewBuilder
    private var searchButton: some View {
        topIconButton("magnifyingglass", help: store.ui("打开资料内搜索", "Search in material")) {
            toggleReaderSearch()
        }
    }

    private func toggleReaderSearch() {
        withAnimation(WeiBeiMotion.panel) {
            if paneState.showReaderSearch {
                store.hideReaderSearch()
                searchFocused.wrappedValue = false
            } else {
                store.revealReaderSearch()
                searchFocused.wrappedValue = true
            }
        }
    }

    private func topIconButton(_ systemName: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .contentShape(Rectangle())
        }
        .buttonStyle(WeiBeiIconButtonStyle(active: active, size: 24))
        .accessibilityLabel(Text(help))
        .help(help)
    }
}

/// Observes only `ThreePaneReorderState` for live drag chrome + dimming.
private struct ThreePaneWorkspaceChrome: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var paneReorder: ThreePaneReorderState
    @Binding var firstSplit: CGFloat
    @Binding var secondSplit: CGFloat
    @Binding var halfSplit: CGFloat
    let registry: PersistentPaneHostRegistry
    let normalizedOrder: [WorkspacePaneRole]
    let visibleOrder: [WorkspacePaneRole]
    let expansionRequest: PaneExpansionRequest?
    let frames: [CGRect]
    let canvasSize: CGSize
    let onFramesChange: ([WorkspacePaneRole], [CGRect]) -> Void
    let onExpansionRequestHandled: (UUID) -> Void

    var body: some View {
        ZStack {
            StableDocumentWorkspace(
                firstSplit: $firstSplit,
                secondSplit: $secondSplit,
                halfSplit: $halfSplit,
                registry: registry,
                normalizedOrder: normalizedOrder,
                visibleOrder: visibleOrder,
                draggedRole: paneReorder.drag?.role,
                expansionRequest: expansionRequest,
                appearanceMode: store.appearanceMode,
                onFramesChange: onFramesChange,
                onExpansionRequestHandled: onExpansionRequestHandled
            )

            threePaneReorderOverlay
        }
    }

    @ViewBuilder
    private var threePaneReorderOverlay: some View {
        if let drag = paneReorder.drag,
           let sourceIndex = visibleOrder.firstIndex(of: drag.role),
           frames.indices.contains(sourceIndex) {
            let sourceFrame = frames[sourceIndex]
            // drag.targetIndex indexes the complete three-pane order (submission space).
            // Translate it through the role before reading the visible-frame array —
            // indexing frames directly misplaces the highlight once a pane is hidden.
            if let targetIndex = drag.targetIndex,
               let visibleTargetIndex = ThreePaneReorderTargeting.visibleHighlightIndex(
                   completeOrderIndex: targetIndex,
                   completeOrder: normalizedOrder,
                   visibleOrder: visibleOrder
               ),
               frames.indices.contains(visibleTargetIndex) {
                PaneDropTargetView(role: visibleOrder[visibleTargetIndex])
                    .frame(width: frames[visibleTargetIndex].width, height: frames[visibleTargetIndex].height)
                    .position(x: frames[visibleTargetIndex].midX, y: frames[visibleTargetIndex].midY)
            }

            PaneReorderPreviewView(role: drag.role)
                .frame(width: sourceFrame.width, height: sourceFrame.height)
                .clipped()
                .allowsHitTesting(false)
                .opacity(0.11)
                .overlay {
                    Rectangle()
                        .stroke(WeiBeiTheme.cinnabar.opacity(0.22), lineWidth: 1)
                }
                .position(
                    x: sourceFrame.midX + min(max(drag.translation, -canvasSize.width), canvasSize.width),
                    y: sourceFrame.midY
                )
                .shadow(
                    color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.38 : 0.14),
                    radius: 22,
                    y: 12
                )
                .zIndex(8)
        }
    }
}

private struct LayoutContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    /// Pane visibility lives here so document-family show/hide rebuilds order without store thrash.
    @EnvironmentObject private var paneState: WorkspacePaneState
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    @StateObject private var paneHostRegistry = PersistentPaneHostRegistry()
    @SceneStorage("documentThreePaneFirstSplit") private var firstSplitStorage: Double = 0.34
    @SceneStorage("documentThreePaneSecondSplit") private var secondSplitStorage: Double = 0.67
    @SceneStorage("documentNotesHalfSplit") private var halfSplitStorage: Double = 0.50
    
    var body: some View {
        Group {
            switch store.layout {
            case .documentAgentNotes, .documentNotesAgent:
                documentPaneLayoutView()
            case .immersiveReading:
                PersistentPaneHost(role: .reader, registry: paneHostRegistry)
            case .immersiveConversation:
                PersistentPaneHost(role: .agent, registry: paneHostRegistry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(WeiBeiTransition.layout)
            case .immersiveWriting:
                PersistentPaneHost(role: .notes, registry: paneHostRegistry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .transition(WeiBeiTransition.layout)
        // Document-internal pane toggles must not re-trigger SwiftUI layout animation.
        .animation(WeiBeiMotion.layout, value: store.layout.isImmersiveFamily)
        .animation(WeiBeiMotion.panel, value: interaction.agentSurface)
        // Touch pane flags so SwiftUI rebuilds visibleOrder when only paneState publishes.
        .animation(nil, value: paneState.showReader)
        .animation(nil, value: paneState.showAgent)
        .animation(nil, value: paneState.showNotes)
    }

    private var firstSplit: Binding<CGFloat> {
        return numericBinding($firstSplitStorage)
    }

    private var secondSplit: Binding<CGFloat> {
        return numericBinding($secondSplitStorage)
    }

    private var halfSplit: Binding<CGFloat> {
        return numericBinding($halfSplitStorage)
    }

    @ViewBuilder
    private func documentPaneLayoutView() -> some View {
        let order = store.visibleDocumentPaneOrder
        GeometryReader { geometry in
            let fallbackFrames = estimatedDocumentPaneFrames(order: order, size: geometry.size)
            let frames = store.threePaneReorderFrameList(order: order, fallback: fallbackFrames)
            ZStack {
                // Drag chrome observes ThreePaneReorderState separately so live drag
                // does not rebuild this workspace through WorkspaceStore.
                ThreePaneWorkspaceChrome(
                    firstSplit: firstSplit,
                    secondSplit: secondSplit,
                    halfSplit: halfSplit,
                    registry: paneHostRegistry,
                    normalizedOrder: store.normalizedThreePaneOrder,
                    visibleOrder: order,
                    expansionRequest: store.paneExpansionRequest,
                    frames: frames,
                    canvasSize: geometry.size,
                    onFramesChange: { reportedOrder, frames in
                        store.updateThreePaneReorderFrames(order: reportedOrder, frames: frames)
                    },
                    onExpansionRequestHandled: { requestID in
                        store.completePaneExpansionRequest(requestID)
                    }
                )
            }
        }
    }

    private func estimatedDocumentPaneFrames(order: [WorkspacePaneRole], size: CGSize) -> [CGRect] {
        switch order.count {
        case 0:
            return []
        case 1:
            return [CGRect(origin: .zero, size: size)]
        case 2:
            return twoPaneFrames(order: order, size: size)
        default:
            return threePaneFrames(order: Array(order.prefix(3)), size: size)
        }
    }

    private func minimumWidth(for _: WorkspacePaneRole) -> CGFloat {
        ContentRailMetrics.railOnlyWidth
    }

    private func threePaneFrames(order: [WorkspacePaneRole], size: CGSize) -> [CGRect] {
        let divider = WeiBeiSplitView.thickness
        let usable = max(size.width - 2 * divider, 1)
        let firstMinimum = minimumWidth(for: order[0])
        let secondMinimum = minimumWidth(for: order[1])
        let thirdMinimum = minimumWidth(for: order[2])
        let firstWidth = clamped(firstSplit.wrappedValue * usable, min: firstMinimum, max: usable - secondMinimum - thirdMinimum)
        let secondWidth = clamped((secondSplit.wrappedValue - firstSplit.wrappedValue) * usable, min: secondMinimum, max: usable - firstWidth - thirdMinimum)
        let thirdWidth = max(thirdMinimum, usable - firstWidth - secondWidth)
        let height = max(size.height, 1)
        return [
            CGRect(x: 0, y: 0, width: firstWidth, height: height),
            CGRect(x: firstWidth + divider, y: 0, width: secondWidth, height: height),
            CGRect(x: firstWidth + divider + secondWidth + divider, y: 0, width: thirdWidth, height: height)
        ]
    }

    private func twoPaneFrames(order: [WorkspacePaneRole], size: CGSize) -> [CGRect] {
        let divider = WeiBeiSplitView.thickness
        let usable = max(size.width - divider, 1)
        let firstMinimum = minimumWidth(for: order[0])
        let secondMinimum = minimumWidth(for: order[1])
        let firstWidth = clamped(halfSplit.wrappedValue * usable, min: firstMinimum, max: usable - secondMinimum)
        let secondWidth = max(secondMinimum, usable - firstWidth)
        let height = max(size.height, 1)
        return [
            CGRect(x: 0, y: 0, width: firstWidth, height: height),
            CGRect(x: firstWidth + divider, y: 0, width: secondWidth, height: height)
        ]
    }

    private func clamped(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), Swift.max(min, max))
    }

    private func numericBinding(_ storage: Binding<Double>) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(storage.wrappedValue) },
            set: { storage.wrappedValue = Double($0) }
        )
    }

}

struct OwnerToken: Equatable {
    let role: WorkspacePaneRole
    let generation: Int
}

final class PersistentPaneHostRegistry: ObservableObject {
    private var hosts: [WorkspacePaneRole: NSHostingView<AnyView>] = [:]
    private var latestOwnerGeneration: [WorkspacePaneRole: Int] = [:]
    private var activeOwners: [WorkspacePaneRole: OwnerToken] = [:]
    private var nextOwnerGeneration = 0

    func registerOwner(for role: WorkspacePaneRole) -> OwnerToken {
        nextOwnerGeneration += 1
        let owner = OwnerToken(role: role, generation: nextOwnerGeneration)
        latestOwnerGeneration[role] = owner.generation
        return owner
    }

    func attach(_ role: WorkspacePaneRole, to container: NSView, store: WorkspaceStore, owner: OwnerToken) {
        guard owner.role == role else { return }
        guard latestOwnerGeneration[role] == owner.generation else { return }
        let host = host(for: role, store: store)
        activeOwners[role] = owner
        guard host.superview !== container else {
            host.frame = container.bounds
            return
        }

        host.removeFromSuperview()
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
    }

    func detach(_ role: WorkspacePaneRole, from container: NSView, owner: OwnerToken) {
        guard let host = hosts[role] else { return }
        guard activeOwners[role] == owner, host.superview === container else { return }
        host.removeFromSuperview()
        activeOwners[role] = nil
    }

    private func host(for role: WorkspacePaneRole, store: WorkspaceStore) -> NSHostingView<AnyView> {
        if let host = hosts[role] {
            return host
        }

        let root = PersistentPaneRoot(role: role)
            .environmentObject(store)
            .environmentObject(store.paneState)
            .environmentObject(store.interaction)
            .environmentObject(store.threePaneReorder)
            .environmentObject(store.libraryDrawer)
        // Same rule as StableDocumentDividerView / ContentRail: pane content must not
        // initiate isMovableByWindowBackground. Reader/notes often hide this via nested
        // AppKit (PDFView/NSTextView); agent chat is mostly SwiftUI so it needs the host flag.
        let host = PaneContentHostingView(rootView: AnyView(root))
        host.identifier = NSUserInterfaceItemIdentifier("persistent-pane-\(role.rawValue)")
        host.autoresizingMask = [.width, .height]
        hosts[role] = host
        return host
    }
}

/// NSHostingView that keeps pane drags (header reorder, scroll, text) from moving the window.
private final class PaneContentHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { false }
}

final class PersistentPaneContainerView: NSView {
    var onWindowChange: ((PersistentPaneContainerView) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(self)
    }
}

struct PersistentPaneHost: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    let role: WorkspacePaneRole
    let registry: PersistentPaneHostRegistry

    func makeCoordinator() -> Coordinator {
        Coordinator(role: role, registry: registry)
    }

    func makeNSView(context: Context) -> PersistentPaneContainerView {
        let container = PersistentPaneContainerView()
        container.isHidden = store.courseWorkspacePresented
        container.onWindowChange = { [weak coordinator = context.coordinator] container in
            coordinator?.windowChanged(container)
        }
        context.coordinator.update(role: role, registry: registry, store: store, container: container)
        return container
    }

    func updateNSView(_ container: PersistentPaneContainerView, context: Context) {
        container.isHidden = store.courseWorkspacePresented
        context.coordinator.update(role: role, registry: registry, store: store, container: container)
    }

    static func dismantleNSView(_ container: PersistentPaneContainerView, coordinator: Coordinator) {
        container.onWindowChange = nil
        coordinator.detach(from: container)
    }

    final class Coordinator {
        private var role: WorkspacePaneRole
        private var registry: PersistentPaneHostRegistry
        private var owner: OwnerToken?
        private weak var store: WorkspaceStore?

        init(role: WorkspacePaneRole, registry: PersistentPaneHostRegistry) {
            self.role = role
            self.registry = registry
        }

        func update(role: WorkspacePaneRole, registry: PersistentPaneHostRegistry, store: WorkspaceStore, container: PersistentPaneContainerView) {
            if self.role != role || self.registry !== registry {
                detach(from: container)
                self.role = role
                self.registry = registry
            }
            self.store = store
            attachIfVisible(to: container)
        }

        func windowChanged(_ container: PersistentPaneContainerView) {
            guard container.window != nil else {
                detach(from: container)
                return
            }
            owner = nil
            attachIfVisible(to: container)
        }

        private func attachIfVisible(to container: PersistentPaneContainerView) {
            guard container.window != nil else { return }
            guard let store else { return }
            if owner == nil {
                owner = registry.registerOwner(for: role)
            }
            guard let owner else { return }
            registry.attach(role, to: container, store: store, owner: owner)
        }

        func detach(from container: NSView) {
            guard let owner else { return }
            registry.detach(role, from: container, owner: owner)
            self.owner = nil
        }
    }
}

private struct PersistentPaneRoot: View {
    @EnvironmentObject private var store: WorkspaceStore
    let role: WorkspacePaneRole

    @ViewBuilder
    var body: some View {
        switch role {
        case .reader:
            ReaderView(
                isImmersive: store.layout == .immersiveReading,
                showsFloatingTitle: true,
                floatingTitleReorderRole: reorderRole
            )
            .frame(minHeight: 280)
            .foregroundStyle(WeiBeiTheme.ink)
            .background(WeiBeiTheme.paper)
        case .agent:
            AgentPaneView(showsPaneHeader: false, reorderRole: reorderRole)
        case .notes:
            NotePaneView(showsPaneHeader: false, reorderRole: reorderRole)
        }
    }

    private var reorderRole: WorkspacePaneRole? {
        guard store.visibleDocumentPaneOrder.count > 1 else { return nil }
        switch store.layout {
        case .documentAgentNotes, .documentNotesAgent:
            return role
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return nil
        }
    }
}

private struct PaneReorderPreviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let role: WorkspacePaneRole

    var body: some View {
        ZStack(alignment: .topLeading) {
            WeiBeiTheme.paper
            HStack(spacing: 7) {
                Image(systemName: role.systemImage)
                    .weiBeiText(12, weight: .semibold)
                Text(role.label(language: store.interfaceLanguage))
                    .weiBeiText(12, weight: .semibold)
            }
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 34)
        }
    }
}

struct EmptyWorkspaceView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        ZStack {
            WeiBeiTheme.paper
            VStack(spacing: 14) {
                Image(systemName: "seal")
                    .weiBeiText(34, weight: .regular)
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(store.appearanceMode.isDark ? 0.12 : 0.08))
                Text(store.ui("在顶栏点亮一个板块开始", "Light up a pane above to begin"))
                    .weiBeiText(13, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .padding(.bottom, 18)
        }
    }
}

private struct PaneDropTargetView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var role: WorkspacePaneRole

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode.isDark ? 0.16 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(WeiBeiTheme.cinnabar.opacity(0.30), lineWidth: 1)
                    .padding(8)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 7) {
                    Image(systemName: role.systemImage)
                        .weiBeiText(12, weight: .semibold)
                    Text(role.label(language: store.interfaceLanguage))
                        .weiBeiText(12, weight: .semibold)
                }
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(WeiBeiTheme.paperRaised.opacity(0.72), in: Capsule())
                .padding(14)
            }
            .allowsHitTesting(false)
    }
}

private struct ResizableTwoPane<First: View, Second: View>: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var split: CGFloat
    var minFirst: CGFloat = 320
    var minSecond: CGFloat = 320
    var roles: [WorkspacePaneRole] = []
    var allowRailSnapping = false
    private let first: First
    private let second: Second

    init(
        split: Binding<CGFloat>,
        minFirst: CGFloat = 320,
        minSecond: CGFloat = 320,
        roles: [WorkspacePaneRole] = [],
        allowRailSnapping: Bool = false,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        _split = split
        self.minFirst = minFirst
        self.minSecond = minSecond
        self.roles = roles
        self.allowRailSnapping = allowRailSnapping
        self.first = first()
        self.second = second()
    }

    func makeCoordinator() -> NativeSplitCoordinator {
        NativeSplitCoordinator(
            kind: .two(split: $split),
            minimums: [minFirst, minSecond],
            roles: roles,
            allowRailSnapping: allowRailSnapping
        )
    }

    func makeNSView(context: Context) -> WeiBeiSplitView {
        let splitView = WeiBeiSplitView()
        context.coordinator.install(splitView)
        splitView.addArrangedSubview(nativeHost(first))
        splitView.addArrangedSubview(nativeHost(second))
        context.coordinator.applyStoredPositions(in: splitView)
        return splitView
    }

    func updateNSView(_ splitView: WeiBeiSplitView, context: Context) {
        context.coordinator.captureReadableWidths(in: splitView)
        context.coordinator.kind = .two(split: $split)
        context.coordinator.minimums = [minFirst, minSecond]
        context.coordinator.roles = roles
        context.coordinator.allowRailSnapping = allowRailSnapping
        context.coordinator.onExpansionRequestHandled = { requestID in
            store.completePaneExpansionRequest(requestID)
        }
        updateHost(at: 0, in: splitView, with: first)
        updateHost(at: 1, in: splitView, with: second)
        context.coordinator.applyStoredPositionsWhenNeeded(in: splitView)
        context.coordinator.handleExpansionRequest(store.paneExpansionRequest, in: splitView)
    }

    private func nativeHost<V: View>(_ view: V) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view.weiBeiMotionScoped().environmentObject(store)))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.defaultLow, for: .horizontal)
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return host
    }

    private func updateHost<V: View>(at index: Int, in splitView: NSSplitView, with view: V) {
        guard splitView.arrangedSubviews.indices.contains(index),
              let host = splitView.arrangedSubviews[index] as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(view.weiBeiMotionScoped().environmentObject(store))
    }
}

private struct ResizableThreePane<First: View, Second: View, Third: View>: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var firstSplit: CGFloat
    @Binding var secondSplit: CGFloat
    var minFirst: CGFloat = 320
    var minSecond: CGFloat = 260
    var minThird: CGFloat = 260
    var roles: [WorkspacePaneRole] = []
    var allowRailSnapping = false
    var onFramesChange: (([CGRect]) -> Void)? = nil
    private let first: First
    private let second: Second
    private let third: Third

    init(
        firstSplit: Binding<CGFloat>,
        secondSplit: Binding<CGFloat>,
        minFirst: CGFloat = 320,
        minSecond: CGFloat = 260,
        minThird: CGFloat = 260,
        roles: [WorkspacePaneRole] = [],
        allowRailSnapping: Bool = false,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second,
        @ViewBuilder third: () -> Third,
        onFramesChange: (([CGRect]) -> Void)? = nil
    ) {
        _firstSplit = firstSplit
        _secondSplit = secondSplit
        self.minFirst = minFirst
        self.minSecond = minSecond
        self.minThird = minThird
        self.roles = roles
        self.allowRailSnapping = allowRailSnapping
        self.onFramesChange = onFramesChange
        self.first = first()
        self.second = second()
        self.third = third()
    }

    func makeCoordinator() -> NativeSplitCoordinator {
        NativeSplitCoordinator(
            kind: .three(first: $firstSplit, second: $secondSplit),
            minimums: [minFirst, minSecond, minThird],
            roles: roles,
            allowRailSnapping: allowRailSnapping,
            onFramesChange: onFramesChange
        )
    }

    func makeNSView(context: Context) -> WeiBeiSplitView {
        let splitView = WeiBeiSplitView()
        context.coordinator.install(splitView)
        splitView.addArrangedSubview(nativeHost(first))
        splitView.addArrangedSubview(nativeHost(second))
        splitView.addArrangedSubview(nativeHost(third))
        context.coordinator.applyStoredPositions(in: splitView)
        return splitView
    }

    func updateNSView(_ splitView: WeiBeiSplitView, context: Context) {
        context.coordinator.captureReadableWidths(in: splitView)
        context.coordinator.kind = .three(first: $firstSplit, second: $secondSplit)
        context.coordinator.minimums = [minFirst, minSecond, minThird]
        context.coordinator.roles = roles
        context.coordinator.allowRailSnapping = allowRailSnapping
        context.coordinator.onFramesChange = onFramesChange
        context.coordinator.onExpansionRequestHandled = { requestID in
            store.completePaneExpansionRequest(requestID)
        }
        updateHost(at: 0, in: splitView, with: first)
        updateHost(at: 1, in: splitView, with: second)
        updateHost(at: 2, in: splitView, with: third)
        context.coordinator.applyStoredPositionsWhenNeeded(in: splitView)
        context.coordinator.handleExpansionRequest(store.paneExpansionRequest, in: splitView)
    }

    private func nativeHost<V: View>(_ view: V) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view.weiBeiMotionScoped().environmentObject(store)))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.defaultLow, for: .horizontal)
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return host
    }

    private func updateHost<V: View>(at index: Int, in splitView: NSSplitView, with view: V) {
        guard splitView.arrangedSubviews.indices.contains(index),
              let host = splitView.arrangedSubviews[index] as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(view.weiBeiMotionScoped().environmentObject(store))
    }
}

private final class WeiBeiSplitView: NSSplitView {
    static let thickness: CGFloat = 10
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onLayout: ((WeiBeiSplitView) -> Void)?

    override var dividerThickness: CGFloat { Self.thickness }

    override func mouseDown(with event: NSEvent) {
        onDragStart?()
        super.mouseDown(with: event)
        onDragEnd?()
    }

    override func layout() {
        super.layout()
        // Divider geometry changed — refresh bidirectional resize cursors.
        window?.invalidateCursorRects(for: self)
        onLayout?(self)
    }

    override func resetCursorRects() {
        // Custom thickness + drawDivider can drop NSSplitView's default cursor rects.
        let count = arrangedSubviews.count
        guard count >= 2 else { return }
        var x: CGFloat = 0
        for index in 0..<(count - 1) {
            x += arrangedSubviews[index].frame.width
            let rect = NSRect(x: x, y: 0, width: dividerThickness, height: bounds.height)
            addCursorRect(rect, cursor: .resizeLeftRight)
            x += dividerThickness
        }
    }

    override func drawDivider(in rect: NSRect) {
        dividerFill.setFill()
        rect.fill()
        let line = NSRect(x: rect.midX - 0.5, y: rect.minY + 14, width: 1, height: max(0, rect.height - 28))
        dividerLine.setFill()
        line.fill()
    }

    private var dividerFill: NSColor {
        // Follow the product theme (纸面/宣纸/墨石/石碑), not system aqua/darkAqua alone.
        WeiBeiNativePalette.dividerFill()
    }

    private var dividerLine: NSColor {
        WeiBeiNativePalette.dividerLine()
    }
}

private final class NativeSplitCoordinator: NSObject, NSSplitViewDelegate {
    enum Kind {
        case two(split: Binding<CGFloat>)
        case three(first: Binding<CGFloat>, second: Binding<CGFloat>)
    }

    var kind: Kind
    var minimums: [CGFloat]
    var roles: [WorkspacePaneRole]
    var allowRailSnapping: Bool
    var onFramesChange: (([CGRect]) -> Void)?
    var onExpansionRequestHandled: ((UUID) -> Void)?
    private var isDragging = false
    private var isApplyingStoredPositions = false
    private var lastAppliedWidth: CGFloat = 0
    private var saveWork: DispatchWorkItem?
    private var recentReadableWidths: [WorkspacePaneRole: CGFloat] = [:]
    private var handledExpansionRequestID: UUID?

    private let railWidth = ContentRailMetrics.railOnlyWidth
    private let railSnapThreshold = ContentRailMetrics.snapThreshold
    private let readableWidthThreshold = ContentRailMetrics.readableWidth
    private let defaultReadableWidth = ContentRailMetrics.defaultReadableWidth

    init(
        kind: Kind,
        minimums: [CGFloat],
        roles: [WorkspacePaneRole] = [],
        allowRailSnapping: Bool = false,
        onFramesChange: (([CGRect]) -> Void)? = nil
    ) {
        self.kind = kind
        self.minimums = minimums
        self.roles = roles
        self.allowRailSnapping = allowRailSnapping
        self.onFramesChange = onFramesChange
    }

    func install(_ splitView: WeiBeiSplitView) {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.onDragStart = { [weak self, weak splitView] in
            guard let self else { return }
            if let splitView {
                self.captureReadableWidths(in: splitView)
            }
            self.isDragging = true
            self.saveWork?.cancel()
        }
        splitView.onDragEnd = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.isDragging = false
            if self.allowRailSnapping {
                self.snapRailWidthsIfNeeded(in: splitView)
            }
            self.saveRatios(from: splitView)
            self.reportFrames(from: splitView)
        }
        splitView.onLayout = { [weak self] splitView in
            guard let self else { return }
            self.applyStoredPositionsWhenNeeded(in: splitView)
            if !self.isDragging {
                self.reportFrames(from: splitView)
            }
        }
    }

    func applyStoredPositionsWhenNeeded(in splitView: NSSplitView) {
        DispatchQueue.main.async { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            guard !self.isDragging, abs(splitView.bounds.width - self.lastAppliedWidth) > 0.5 else { return }
            self.applyStoredPositions(in: splitView)
        }
    }

    func applyStoredPositions(in splitView: NSSplitView) {
        let count = splitView.arrangedSubviews.count
        guard count >= 2, splitView.bounds.width > 0 else { return }
        let usable = max(splitView.bounds.width - CGFloat(count - 1) * splitView.dividerThickness, 1)

        isApplyingStoredPositions = true
        defer { isApplyingStoredPositions = false }

        switch kind {
        case .two(let split):
            let firstWidth = clamped(split.wrappedValue * usable, min: minimums[safe: 0] ?? 0, max: usable - (minimums[safe: 1] ?? 0))
            splitView.setPosition(firstWidth, ofDividerAt: 0)
        case .three(let first, let second):
            let firstMinimum = minimums[safe: 0] ?? 0
            let secondMinimum = minimums[safe: 1] ?? 0
            let thirdMinimum = minimums[safe: 2] ?? 0
            let firstWidth = clamped(first.wrappedValue * usable, min: firstMinimum, max: usable - secondMinimum - thirdMinimum)
            splitView.setPosition(firstWidth, ofDividerAt: 0)
            let actualFirstWidth = splitView.arrangedSubviews[safe: 0]?.frame.width ?? firstWidth
            let secondWidth = clamped((second.wrappedValue - first.wrappedValue) * usable, min: secondMinimum, max: usable - actualFirstWidth - thirdMinimum)
            splitView.setPosition(actualFirstWidth + splitView.dividerThickness + secondWidth, ofDividerAt: 1)
        }

        if allowRailSnapping {
            snapRailWidthsIfNeeded(in: splitView)
        }

        saveRatios(from: splitView)
    }

    func captureReadableWidths(in splitView: NSSplitView) {
        guard allowRailSnapping, roles.count == splitView.arrangedSubviews.count else { return }
        for (role, view) in zip(roles, splitView.arrangedSubviews) where view.frame.width >= readableWidthThreshold {
            recentReadableWidths[role] = view.frame.width
        }
    }

    func handleExpansionRequest(_ request: PaneExpansionRequest?, in splitView: NSSplitView) {
        guard allowRailSnapping,
              let request,
              request.id != handledExpansionRequestID,
              roles.count == splitView.arrangedSubviews.count,
              let requestedIndex = roles.firstIndex(of: request.role) else { return }

        handledExpansionRequestID = request.id
        expandPane(at: requestedIndex, role: request.role, in: splitView)
        snapRailWidthsIfNeeded(in: splitView)
        saveRatios(from: splitView)
        splitView.needsLayout = true
        splitView.layoutSubtreeIfNeeded()

        DispatchQueue.main.async { [weak self] in
            self?.onExpansionRequestHandled?(request.id)
        }
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView else { return }
        guard !isDragging, !isApplyingStoredPositions else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.saveRatios(from: splitView)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex > 0 else { return minimums[safe: 0] ?? proposedMinimumPosition }
        let previous = splitView.arrangedSubviews.prefix(dividerIndex).reduce(CGFloat(0)) { $0 + $1.frame.width }
        return previous + CGFloat(dividerIndex) * splitView.dividerThickness + (minimums[safe: dividerIndex] ?? 0)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let trailingMinimum = minimums.dropFirst(dividerIndex + 1).reduce(CGFloat(0), +)
        let trailingDividers = CGFloat(max(0, splitView.arrangedSubviews.count - dividerIndex - 2)) * splitView.dividerThickness
        return splitView.bounds.width - splitView.dividerThickness - trailingMinimum - trailingDividers
    }

    private func saveRatios(from splitView: NSSplitView) {
        let count = splitView.arrangedSubviews.count
        guard count >= 2 else { return }
        let usable = max(splitView.bounds.width - CGFloat(count - 1) * splitView.dividerThickness, 1)
        let widths = splitView.arrangedSubviews.map(\.frame.width)

        switch kind {
        case .two(let split):
            split.wrappedValue = clamped(widths[0] / usable, min: 0, max: 1)
        case .three(let first, let second):
            first.wrappedValue = clamped(widths[0] / usable, min: 0, max: 1)
            second.wrappedValue = clamped((widths[0] + widths[1]) / usable, min: 0, max: 1)
        }
        captureReadableWidths(in: splitView)
        lastAppliedWidth = splitView.bounds.width
        reportFrames(from: splitView)
    }

    private func snapRailWidthsIfNeeded(in splitView: NSSplitView) {
        let widths = splitView.arrangedSubviews.map(\.frame.width)
        guard widths.count >= 2 else { return }

        let snapIndices = widths.indices.filter { widths[$0] <= railSnapThreshold }
        guard snapIndices.contains(where: { abs(widths[$0] - railWidth) > 0.5 }) else { return }

        var targetWidths = widths
        for index in snapIndices {
            targetWidths[index] = railWidth
        }

        let readableIndices = widths.indices.filter { !snapIndices.contains($0) }
        let fallbackRecipient = widths.indices.max { widths[$0] < widths[$1] }
        for index in snapIndices {
            let releasedWidth = widths[index] - railWidth
            guard releasedWidth > 0.5 else { continue }
            let recipient = readableIndices.min { lhs, rhs in
                let lhsDistance = abs(lhs - index)
                let rhsDistance = abs(rhs - index)
                if lhsDistance == rhsDistance {
                    return widths[lhs] > widths[rhs]
                }
                return lhsDistance < rhsDistance
            } ?? fallbackRecipient
            if let recipient {
                targetWidths[recipient] += releasedWidth
            }
        }

        applyPaneWidths(targetWidths, in: splitView)
    }

    private func expandPane(at requestedIndex: Int, role: WorkspacePaneRole, in splitView: NSSplitView) {
        let widths = splitView.arrangedSubviews.map(\.frame.width)
        guard widths.indices.contains(requestedIndex) else { return }
        let usable = max(
            splitView.bounds.width - CGFloat(widths.count - 1) * splitView.dividerThickness,
            1
        )
        let otherIndices = widths.indices.filter { $0 != requestedIndex }
        let otherMinimumTotal = otherIndices.reduce(CGFloat(0)) { partial, index in
            partial + (minimums[safe: index] ?? railWidth)
        }
        let requestedMinimum = minimums[safe: requestedIndex] ?? railWidth
        let desiredWidth = ContentRailPolicy.expansionWidth(recentWidth: recentReadableWidths[role])
        let requestedWidth = clamped(
            desiredWidth,
            min: requestedMinimum,
            max: max(requestedMinimum, usable - otherMinimumTotal)
        )

        var targetWidths = Array(repeating: CGFloat(0), count: widths.count)
        targetWidths[requestedIndex] = requestedWidth
        let remainingWidth = max(0, usable - requestedWidth)
        let extraAvailable = max(0, remainingWidth - otherMinimumTotal)
        let currentExtras = otherIndices.map { index in
            max(0, widths[index] - (minimums[safe: index] ?? railWidth))
        }
        let currentExtraTotal = currentExtras.reduce(0, +)

        for (offset, index) in otherIndices.enumerated() {
            let minimum = minimums[safe: index] ?? railWidth
            let share: CGFloat
            if currentExtraTotal > 0.5 {
                share = extraAvailable * currentExtras[offset] / currentExtraTotal
            } else {
                share = extraAvailable / CGFloat(max(otherIndices.count, 1))
            }
            targetWidths[index] = minimum + share
        }

        if let correctionIndex = otherIndices.last {
            targetWidths[correctionIndex] += usable - targetWidths.reduce(0, +)
        }
        applyPaneWidths(targetWidths, in: splitView)
    }

    private func applyPaneWidths(_ widths: [CGFloat], in splitView: NSSplitView) {
        guard widths.count == splitView.arrangedSubviews.count, widths.count >= 2 else { return }
        var leadingWidth: CGFloat = 0
        for dividerIndex in 0..<(widths.count - 1) {
            leadingWidth += widths[dividerIndex]
            splitView.setPosition(
                leadingWidth + CGFloat(dividerIndex) * splitView.dividerThickness,
                ofDividerAt: dividerIndex
            )
        }
    }

    private func reportFrames(from splitView: NSSplitView) {
        guard onFramesChange != nil, splitView.arrangedSubviews.count > 0 else { return }
        let frames = splitView.arrangedSubviews.map(\.frame)
        DispatchQueue.main.async { [weak self] in
            self?.onFramesChange?(frames)
        }
    }

    private func clamped(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), Swift.max(min, max))
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
