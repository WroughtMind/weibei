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

                // Glass: ONE full-window foreground sheet above the backdrop and
                // below every surface (top bar, panes, course space). Each region
                // gets exactly one wash — per-surface painting stacked twice and
                // made the bar drift from the content below it.
                if store.appearanceMode.isGlass {
                    WeiBeiGlassForegroundSheet(mode: store.appearanceMode)
                }

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

                // Single top-level status surface: important errors first, then
                // persistent save failures, otherwise the transient note status.
                // Sits above the course space so it stays visible wherever the
                // user is; the old notes-pane-local copy is gone.
                if store.importantOperationError != nil
                    || store.workspaceSaveError != nil
                    || store.noteEditorCommandFailureMessage != nil
                    || store.noteSelectionStatusMessage != nil
                    || store.transientNoteStatus != nil {
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
            .animation(WeiBeiMotion.panel, value: store.workspaceSaveError)
            .animation(WeiBeiMotion.panel, value: store.noteEditorCommandFailureMessage)
            .animation(WeiBeiMotion.panel, value: store.noteSelectionStatusMessage)
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
        .weibeiEtchedCapsuleBackground(
            fill: WeiBeiTheme.paperRaised.opacity(0.97),
            stroke: WeiBeiTheme.hairline.opacity(0.6),
            contactShadow: true
        )
        .clipShape(Capsule())
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

    // 持续保存失败（连续 3 次置位）与角落标记同源，这里让它在全 App 可见。
    private var isSaveFailure: Bool {
        !isImportant && store.workspaceSaveError != nil
    }

    private var isNoteSelectionFailure: Bool {
        !isImportant && !isSaveFailure && !isEditorCommandFailure
            && store.canRetryPendingNoteSelection
    }

    private var isEditorCommandFailure: Bool {
        !isImportant && !isSaveFailure && store.noteEditorCommandFailureMessage != nil
    }

    private var isAlert: Bool {
        isImportant || isSaveFailure || isEditorCommandFailure || isNoteSelectionFailure
    }

    private var message: String {
        store.importantOperationError
            ?? store.workspaceSaveError
            ?? store.noteEditorCommandFailureMessage
            ?? store.noteSelectionStatusMessage
            ?? store.transientNoteStatus
            ?? ""
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isAlert ? "exclamationmark.triangle.fill" : "info.circle")
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(isAlert ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
            Text(message)
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if isSaveFailure {
                Button {
                    _ = store.retryWorkspaceSave()
                } label: {
                    Text(store.ui("重试", "Retry"))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("重试保存", "Retry save")))
            } else if isEditorCommandFailure && store.canRetryRejectedNoteEditorCommand {
                Button {
                    store.retryRejectedNoteEditorCommand()
                } label: {
                    Text(store.ui("重试", "Retry"))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("重试应用编辑内容", "Retry applying editor content")))
            } else if isNoteSelectionFailure {
                Button {
                    store.retryPendingNoteSelection()
                } label: {
                    Text(store.ui("重试", "Retry"))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(store.ui("重试保存并切换笔记", "Retry saving and switching notes")))
            } else if isImportant {
                Button {
                    store.dismissImportantOperationError()
                } label: {
                    Image(systemName: "xmark")
                        .weiBeiText(10.5, weight: .semibold)
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
        .background {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: WeiBeiTheme.paperRaised.opacity(0.97),
                stroke: isAlert
                    ? WeiBeiTheme.cinnabar.opacity(0.55)
                    : WeiBeiTheme.hairline.opacity(0.6),
                showsContactShadow: true
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: WeiBeiTheme.ink.opacity(store.appearanceMode.isDark ? 0.3 : 0.1), radius: 12, y: 6)
        .allowsHitTesting(isAlert)
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
    @Environment(\.openWindow) private var openSettingsWindow
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
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                    .textFieldStyle(.plain)
                    .weiBeiText(12)
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

            // Copy-reference is not top-bar chrome: use its configured shortcut, menu, or command palette when needed.

            // Light/dark quick toggle — keeps the active style pair, flips the
            // preference. Command palette stays reachable on ⌘K.
            topIconButton(
                store.appearanceMode.isDark ? "sun.max" : "moon.stars",
                help: store.ui("切换深浅外观", "Toggle Light / Dark")
            ) {
                store.appearancePreference = store.appearanceMode.isDark ? .light : .dark
            }
            .animation(WeiBeiMotion.micro, value: store.appearanceMode.isDark)

            // Full Settings window (agent keys, appearance, data) — not the old mini menu.
            topIconButton("gearshape", help: store.ui("打开设置", "Open Settings")) {
                openSettingsWindow(id: "weibei-settings")
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
        // ⌘, bridge: Commands cannot reach the openWindow environment action,
        // so the menu item posts a notification and the live top bar opens it.
        .onReceive(NotificationCenter.default.publisher(for: .weibeiOpenSettings)) { _ in
            openSettingsWindow(id: "weibei-settings")
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
                // Glass legibility comes from the single full-window sheet at the
                // ZStack root — the bar itself must not paint a second layer.
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
            .weiBeiKeyboardShortcut(store.executableChord(for: .navigateBack))
            .disabled(!store.canNavigateBack)

            topIconButton("arrow.right", help: store.ui("前进", "Forward")) {
                withAnimation(WeiBeiMotion.layout) {
                    store.navigateForwardInWorkspace()
                }
            }
            .weiBeiKeyboardShortcut(store.executableChord(for: .navigateForward))
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
        var text = update.helpText
        if update.releaseNotesLines.count > update.summaryLines.count {
            text += "\n" + store.ui(
                "完整更新说明可在“设置 > 关于”中展开。",
                "Expand the full release notes in Settings > About."
            )
        }
        if case .failed = updateService.status {
            text += "\n" + store.ui("更新失败，点击重试。", "Update failed. Click to retry.")
        }
        return text
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

    // 与 StableDocumentSplitCoordinator.dividerWidth 保持一致,真实布局由那边决定
    private static let estimatedDividerWidth: CGFloat = 10

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
        let divider = Self.estimatedDividerWidth
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
        let divider = Self.estimatedDividerWidth
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

private struct PaneDropTargetView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var role: WorkspacePaneRole

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode.isDark ? 0.16 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
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
                .weibeiEtchedCapsuleBackground(
                    fill: WeiBeiTheme.paperRaised.opacity(0.72),
                    stroke: WeiBeiTheme.hairline.opacity(0.4),
                    contactShadow: true
                )
                .clipShape(Capsule())
                .padding(14)
            }
            .allowsHitTesting(false)
    }
}
