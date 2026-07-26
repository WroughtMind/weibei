import AppKit
import SwiftUI
import WeiBeiCore

struct ContentView: View {
    /// Intentionally does NOT observe `libraryDrawer` — drawer open must not rebuild this body
    /// (reader / agent / notes live here).
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var focusedPane: PaneFocus?
    @FocusState private var topSearchFocused: Bool
    @State private var floatingAgentExpanded = false
    @State private var windowIsFullScreen = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    UnifiedTopBarView(
                        isImmersiveLayout: isImmersiveLayout,
                        isFullScreen: windowIsFullScreen,
                        searchFocused: $topSearchFocused
                    )

                    ZStack(alignment: .top) {
                        HStack(spacing: 0) {
                            // The course index is a peer workspace column. Its width animation
                            // reflows the persistent panes instead of covering their render layers.
                            CourseLibraryDrawerLayer {
                                store.toggleLibrary()
                            }

                            LayoutContentView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(nsColor: WeiBeiNativePalette.paper(for: store.appearanceMode)))
                                // Only cross-fade immersive ↔ document families. Pane show/hide inside
                                // the document family is owned by AppKit StableDocumentWorkspace animation
                                // — a second SwiftUI layout animation here made toggles feel split/janky.
                                .animation(WeiBeiMotion.layout, value: store.layout.isImmersiveFamily)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if store.commandPalettePresented {
                            CommandPaletteView()
                                .transition(WeiBeiTransition.commandPalette)
                                .zIndex(40)
                        }

                        if showsGlobalFloatingAgent {
                            FloatingSelectionAgentView(
                                expanded: $floatingAgentExpanded,
                                routesToConversation: store.isConversationSurfaceVisible
                            )
                                .position(floatingAgentPosition(in: geometry.size))
                                .transition(WeiBeiTransition.floating)
                                .zIndex(30)
                                .onChange(of: store.keepFloatingSelectionForAnswer) { _, keep in
                                    // Expand only when an intentional keep-open is requested
                                    // (点「问」/回访红线/顶部已问), not on bare selection.
                                    if keep { floatingAgentExpanded = true }
                                }
                                .onChange(of: store.activeSelectionAskThreadID) { _, id in
                                    if id != nil, store.keepFloatingSelectionForAnswer {
                                        floatingAgentExpanded = true
                                    }
                                }
                                .onChange(of: store.selectionContext?.id) { _, _ in
                                    // Live reselection collapses to capsule; reopen-with-keepOpen must stay expanded.
                                    guard !store.pinnedFloatingAgent,
                                          !store.isAskingAgent,
                                          !store.keepFloatingSelectionForAnswer else { return }
                                    floatingAgentExpanded = false
                                }
                        }

                    }
                }
                .allowsHitTesting(!store.courseWorkspacePresented)
                .accessibilityHidden(store.courseWorkspacePresented)

                if store.courseWorkspacePresented {
                    ZStack {
                        WeiBeiTheme.paper
                        CourseWorkspaceView()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.995, anchor: .top)))
                    .zIndex(100)
                }
            }
            .background {
                LibraryAwareEscapeBridge(
                    courseWorkspacePresented: store.courseWorkspacePresented,
                    showReaderSearch: store.showReaderSearch,
                    showsGlobalFloatingAgent: showsGlobalFloatingAgent,
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
        .onChange(of: store.focusedPane) { _, value in
            focusedPane = value
        }
        .onChange(of: store.showReaderSearch) { _, visible in
            topSearchFocused = visible
        }
        .onAppear {
            focusedPane = store.focusedPane
        }
        .animation(WeiBeiMotion.panel, value: store.courseWorkspacePresented)
    }

    private var showsGlobalFloatingAgent: Bool {
        return !store.courseWorkspacePresented
            && store.canShowSelectionPromptSurface && SelectionFloatingAgentPlacement.isVisible(
            surface: store.agentSurface,
            hasSelection: store.selectionContext != nil || store.keepFloatingSelectionForAnswer,
            hasAnchor: store.selectionAnchor != nil,
            pinned: store.pinnedFloatingAgent,
            keepOpen: store.keepFloatingSelectionForAnswer
        )
    }

    private var isImmersiveLayout: Bool {
        [.immersiveReading, .immersiveConversation, .immersiveWriting].contains(store.layout)
    }

    private func floatingAgentPosition(in size: CGSize) -> CGPoint {
        let point = SelectionFloatingAgentPlacement.position(
            anchor: store.selectionAnchor.map { FloatingAgentCoordinate(x: Double($0.x), y: Double($0.y)) },
            canvas: FloatingAgentCoordinate(x: Double(size.width), y: Double(size.height)),
            topInset: Double(topBarHeight),
            surfaceHalfWidth: floatingAgentExpanded
                ? SelectionFloatingAgentPlacement.expandedHalfWidth
                : SelectionFloatingAgentPlacement.compactHalfWidth,
            prefersAnchorCenter: !floatingAgentExpanded
        )
        return CGPoint(x: point.x, y: point.y)
    }

    private var topBarHeight: CGFloat {
        WeiBeiMetric.topBarHeight
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

/// AppKit course drawer layer. Observes only `LibraryDrawerState` (+ store for content).
private struct CourseLibraryDrawerLayer: View {
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    let dismiss: () -> Void

    var body: some View {
        CourseDrawerHost(drawer: libraryDrawer, onDismiss: dismiss)
            .frame(width: libraryDrawer.isOpen ? CourseDrawerContainerView.panelWidth : 0)
            .frame(maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(libraryDrawer.isOpen)
            .accessibilityHidden(!libraryDrawer.isOpen)
            .animation(WeiBeiMotion.panel, value: libraryDrawer.isOpen)
    }
}

/// Escape routing that can observe drawer open without forcing ContentView to do so.
private struct LibraryAwareEscapeBridge: View {
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    let courseWorkspacePresented: Bool
    let showReaderSearch: Bool
    let showsGlobalFloatingAgent: Bool
    let onToggleLibrary: () -> Void
    let onDismissFloatingAgent: () -> Void
    let onHideReaderSearch: () -> Void

    var body: some View {
        Group {
            if !courseWorkspacePresented && libraryDrawer.isOpen {
                EscapeKeyBridge(onEscape: onToggleLibrary)
            } else if !courseWorkspacePresented && !libraryDrawer.isOpen && showsGlobalFloatingAgent {
                EscapeKeyBridge(onEscape: onDismissFloatingAgent)
            } else if !courseWorkspacePresented && !libraryDrawer.isOpen && showReaderSearch {
                EscapeKeyBridge(onEscape: onHideReaderSearch)
            }
        }
    }
}

private struct UnifiedTopBarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var libraryDrawer: LibraryDrawerState
    @Environment(\.openSettings) private var openSettings
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

            if store.showReaderSearch && shouldShowSearchAction {
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
                    .font(.system(size: 12))
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

            if shouldShowSearchAction && !store.showReaderSearch {
                searchButton
            }

            if shouldShowReferenceAction {
                topIconButton("quote.opening", help: store.copyReferenceActionTitle) {
                    store.copyCurrentReference()
                }
            }

            topIconButton("command", help: store.ui("命令面板", "Command palette")) {
                withAnimation(WeiBeiMotion.panel) {
                    store.commandPalettePresented.toggle()
                }
            }

            // Full Settings window (agent keys, appearance, data) — not the old mini menu.
            topIconButton("slider.horizontal.3", help: store.ui("打开设置", "Open Settings")) {
                openSettings()
            }

            Spacer()
                .frame(width: 8)
        }
        .foregroundStyle(secondaryText)
        .frame(height: barHeight)
        .background(topBarBackground)
        .overlay {
            paneToggleCluster
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -5)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(topHighlight)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            WeiBeiHeaderHandoffFade(
                height: 18,
                opacity: isImmersiveLayout ? 0.42 : 0.34,
                appearanceMode: store.appearanceMode
            )
                .offset(y: 18)
            .allowsHitTesting(false)
        }
        .shadow(color: WeiBeiTheme.ink.opacity(0.018), radius: 8, y: 2)
        .onAppear {
            withAnimation(WeiBeiMotion.reveal) {
                appeared = true
            }
        }
        .animation(WeiBeiMotion.panel, value: store.showReaderSearch)
        .animation(WeiBeiMotion.layout, value: isImmersiveLayout)
    }

    private var barHeight: CGFloat {
        WeiBeiMetric.topBarHeight
    }

    private var leftInset: CGFloat {
        CGFloat(TopBarLeadingInset.value(isFullScreen: isFullScreen))
    }

    private var topBarSpacing: CGFloat {
        7
    }

    private var controlHeight: CGFloat {
        28
    }

    private var shouldShowSearchAction: Bool {
        store.hasSelectedMaterial && hasReaderScopedTopActions
    }

    private var shouldShowReferenceAction: Bool {
        store.canCopyReference && hasReaderScopedTopActions
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

    private var topHighlight: Color {
        store.appearanceMode.isDark
            ? WeiBeiTheme.ink.opacity(0.05)
            : WeiBeiTheme.glassHighlight.opacity(0.24)
    }

    private var topBarBackground: some View {
        WeiBeiGlassHeaderBackground(
            paperOpacity: backgroundPaperOpacity - (isImmersiveLayout ? 0.06 : 0),
            materialOpacity: backgroundMaterialOpacity + (isImmersiveLayout ? 0.03 : 0),
            appearanceMode: store.appearanceMode
        )
    }

    private var backgroundPaperOpacity: Double {
        0.80
    }

    private var backgroundMaterialOpacity: Double {
        0.09
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
        }
    }

    private var paneToggleCluster: some View {
        HStack(spacing: max(5, topBarSpacing - 1)) {
            topIconButton(
                "doc.text",
                help: store.isPaneToggleActive(.reader) ? store.ui("隐藏文稿", "Hide document") : store.ui("显示文稿", "Show document"),
                active: store.isPaneToggleActive(.reader)
            ) {
                store.toggleReader()
            }

            topIconButton(
                "bubble.left.and.text.bubble.right",
                help: agentPaneToggleHelp,
                active: store.isPaneToggleActive(.agent)
            ) {
                store.toggleAgent()
            }

            topIconButton(
                "note.text",
                help: store.isPaneToggleActive(.notes) ? store.ui("隐藏笔记", "Hide notes") : store.ui("显示笔记", "Show notes"),
                active: store.isPaneToggleActive(.notes)
            ) {
                store.toggleNotes()
            }
        }
        .padding(.horizontal, 4)
        .frame(height: controlHeight)
        .background {
            Capsule()
                .fill(controlFill.opacity(0.62))
                .overlay {
                    Capsule()
                        .stroke(WeiBeiTheme.glassHighlight.opacity(0.16), lineWidth: 1)
                }
        }
    }

    private var agentPaneToggleHelp: String {
        if store.selectionContext != nil {
            return store.ui("用当前选区打开对话", "Open chat with current selection")
        }
        return store.isPaneToggleActive(.agent) ? store.ui("隐藏对话", "Hide chat") : store.ui("显示对话", "Show chat")
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
            if store.showReaderSearch {
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
            if let targetIndex = drag.targetIndex, frames.indices.contains(targetIndex) {
                PaneDropTargetView(role: visibleOrder[targetIndex])
                    .frame(width: frames[targetIndex].width, height: frames[targetIndex].height)
                    .position(x: frames[targetIndex].midX, y: frames[targetIndex].midY)
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
    @StateObject private var paneHostRegistry = PersistentPaneHostRegistry()
    @SceneStorage("documentThreePaneFirstSplit") private var firstSplitStorage: Double = 0.34
    @SceneStorage("documentThreePaneSecondSplit") private var secondSplitStorage: Double = 0.67
    @SceneStorage("documentNotesHalfSplit") private var halfSplitStorage: Double = 0.50
    
    var body: some View {
        Group {
            switch store.layout {
            case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
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
        .animation(WeiBeiMotion.panel, value: store.agentSurface)
    }

    private var firstSplit: Binding<CGFloat> {
        if Self.isDormantRailPreviewVerification {
            return .constant(0.02)
        }
        return numericBinding($firstSplitStorage)
    }

    private var secondSplit: Binding<CGFloat> {
        if Self.isDormantRailPreviewVerification {
            return .constant(0.55)
        }
        return numericBinding($secondSplitStorage)
    }

    private static var isDormantRailPreviewVerification: Bool {
        let scenario = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_SCENARIO"]
        return scenario == "content-rail-dormant-preview" || scenario == "content-rail-activation-preview"
    }

    private var halfSplit: Binding<CGFloat> {
        if let agentRatio = Self.verificationAgentPaneRatio {
            let order = store.visibleDocumentPaneOrder
            if order.count == 2, let agentIndex = order.firstIndex(of: .agent) {
                return .constant(agentIndex == 0 ? agentRatio : 1 - agentRatio)
            }
        }
        return numericBinding($halfSplitStorage)
    }

    private static var verificationAgentPaneRatio: CGFloat? {
        guard let rawValue = ProcessInfo.processInfo.environment["WEIBEI_VERIFY_AGENT_PANE_RATIO"],
              let ratio = Double(rawValue)
        else {
            return nil
        }
        return CGFloat(min(max(ratio, 0.20), 0.80))
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

    /**
     * 在原生工作区回报真实 frame 前，根据已保存比例估算可见 pane frame。
     */
    private func estimatedDocumentPaneFrames(order: [WorkspacePaneRole], size: CGSize) -> [CGRect] {
        let visibleOrder = Array(order.prefix(3))
        let cumulativeSplits: [CGFloat]
        if visibleOrder.count == 2 {
            cumulativeSplits = [halfSplit.wrappedValue]
        } else {
            cumulativeSplits = [firstSplit.wrappedValue, secondSplit.wrappedValue]
        }
        let widths = PaneLayoutGeometry.paneWidths(
            containerWidth: size.width,
            dividerWidth: PaneLayoutGeometry.dividerWidth,
            cumulativeSplits: cumulativeSplits,
            minimumWidths: visibleOrder.map { _ in ContentRailMetrics.railOnlyWidth }
        )
        return PaneLayoutGeometry.paneFrames(
            size: size,
            dividerWidth: PaneLayoutGeometry.dividerWidth,
            paneWidths: widths
        )
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
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
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
                    .font(.system(size: 12, weight: .semibold))
                Text(role.label(language: store.interfaceLanguage))
                    .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(store.appearanceMode.isDark ? 0.12 : 0.08))
                Text(store.ui("在顶栏点亮一个板块开始", "Light up a pane above to begin"))
                    .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 12, weight: .semibold))
                    Text(role.label(language: store.interfaceLanguage))
                        .font(.system(size: 12, weight: .semibold))
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
