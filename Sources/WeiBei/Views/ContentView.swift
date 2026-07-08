import AppKit
import SwiftUI
import WeiBeiCore

struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var focusedPane: PaneFocus?
    @FocusState private var topSearchFocused: Bool
    @SceneStorage("libraryPaneWidth") private var libraryPaneWidthStorage: Double = 292
    @State private var floatingAgentExpanded = false
    @State private var libraryDragStartWidth: CGFloat?
    @State private var windowIsFullScreen = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                UnifiedTopBarView(
                    isImmersiveLayout: isImmersiveLayout,
                    isFullScreen: windowIsFullScreen,
                    searchFocused: $topSearchFocused
                )

                ZStack(alignment: .top) {
                    HStack(spacing: 0) {
                        if store.showLibrary {
                            SidebarView()
                                .frame(width: libraryWidth(in: geometry.size.width))
                                .focused($focusedPane, equals: .library)
                                .transition(WeiBeiTransition.sidePanel)
                                .zIndex(2)

                            libraryResizeHandle(totalWidth: geometry.size.width)
                                .transition(.opacity)
                        }

                        LayoutContentView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WeiBeiTheme.paper)
                    .animation(WeiBeiMotion.layout, value: store.showLibrary)
                    .animation(WeiBeiMotion.layout, value: store.layout)

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
                    }

                }
            }
            .background {
                if showsGlobalFloatingAgent {
                    EscapeKeyBridge {
                        store.dismissFloatingSelectionAgent()
                    }
                }

                if store.showReaderSearch {
                    EscapeKeyBridge {
                        store.hideReaderSearch()
                        topSearchFocused = false
                    }
                }
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
        .animation(WeiBeiMotion.appearance, value: store.appearanceMode)
    }

    private var showsGlobalFloatingAgent: Bool {
        return store.canShowSelectionPromptSurface && SelectionFloatingAgentPlacement.isVisible(
            surface: store.agentSurface,
            hasSelection: store.selectionContext != nil,
            hasAnchor: store.selectionAnchor != nil,
            pinned: store.pinnedFloatingAgent
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
        store.topBarVariant.height
    }

    private func libraryWidth(in totalWidth: CGFloat) -> CGFloat {
        min(libraryMaximumWidth(in: totalWidth), max(libraryMinimumWidth, CGFloat(libraryPaneWidthStorage)))
    }

    private func libraryMaximumWidth(in totalWidth: CGFloat) -> CGFloat {
        max(libraryMinimumWidth, min(430, totalWidth - WeiBeiSplitView.thickness - minimumContentWidthWithLibrary))
    }

    private var libraryMinimumWidth: CGFloat {
        220
    }

    private var minimumContentWidthWithLibrary: CGFloat {
        switch store.layout {
        case .documentAgentNotes, .documentNotesAgent:
            store.showRightPane ? 780 : 560
        case .documentNotesSplit:
            store.showRightPane ? 680 : 560
        case .immersiveConversation, .immersiveWriting:
            720
        case .immersiveReading:
            560
        }
    }

    private func libraryResizeHandle(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: WeiBeiSplitView.thickness)
            .overlay {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.34))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if libraryDragStartWidth == nil {
                            libraryDragStartWidth = libraryWidth(in: totalWidth)
                        }
                        let startWidth = libraryDragStartWidth ?? libraryWidth(in: totalWidth)
                        let nextWidth = startWidth + value.translation.width
                        libraryPaneWidthStorage = Double(min(libraryMaximumWidth(in: totalWidth), max(220, nextWidth)))
                    }
                    .onEnded { _ in
                        libraryDragStartWidth = nil
                    }
            )
            .help(store.ui("拖动调整课程目录宽度", "Drag to resize the course index"))
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

private struct UnifiedTopBarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let isImmersiveLayout: Bool
    let isFullScreen: Bool
    var searchFocused: FocusState<Bool>.Binding
    @State private var appeared = false

    var body: some View {
        HStack(spacing: topBarSpacing) {
            Spacer()
                .frame(width: leftInset)

            leftPrimaryControls

            brandBlock

            if variant != .glyph, shouldShowTopDocumentTitle {
                Rectangle()
                    .fill(dividerColor.opacity(0.72))
                    .frame(width: 1, height: 18)

                Text(store.selectedMaterialItem.map(store.displayTitle) ?? store.ui("未选择资料", "No material selected"))
                    .font(documentTitleFont)
                    .foregroundStyle(primaryText.opacity(0.82))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

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

            if shouldShowAgentAction {
                agentButton
            }

            layoutMenu

            topIconButton("command", help: store.ui("命令面板", "Command palette")) {
                withAnimation(WeiBeiMotion.panel) {
                    store.commandPalettePresented.toggle()
                }
            }

            Spacer()
                .frame(width: 8)
        }
        .foregroundStyle(secondaryText)
        .frame(height: barHeight)
        .background(topBarBackground)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -5)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(topHighlight)
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            WeiBeiHeaderHandoffFade(height: 18, opacity: isImmersiveLayout ? 0.42 : 0.34)
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
        .animation(WeiBeiMotion.layout, value: store.topBarVariant)
    }

    private var variant: TopBarVariant {
        store.topBarVariant
    }

    private var barHeight: CGFloat {
        variant.height
    }

    private var leftInset: CGFloat {
        CGFloat(TopBarLeadingInset.value(isFullScreen: isFullScreen))
    }

    private var topBarSpacing: CGFloat {
        switch variant {
        case .compact, .glyph:
            return 7
        case .reader:
            return 8
        case .balanced:
            return 9
        case .wide:
            return 11
        }
    }

    private var controlHeight: CGFloat {
        switch variant {
        case .compact, .glyph:
            return 28
        case .wide:
            return 28
        default:
            return 26
        }
    }

    private var layoutMenuWidth: CGFloat {
        switch variant {
        case .compact:
            return 104
        case .glyph:
            return 84
        case .wide:
            return 138
        default:
            return 126
        }
    }

    private var layoutMenuTitle: String {
        shortLayoutLabel
    }

    private var shouldShowTopDocumentTitle: Bool {
        store.hasSelectedMaterial && hasReaderScopedTopActions
    }

    private var shouldShowSearchAction: Bool {
        store.hasSelectedMaterial && hasReaderScopedTopActions
    }

    private var shouldShowReferenceAction: Bool {
        store.canCopyReference && hasReaderScopedTopActions
    }

    private var shouldShowAgentAction: Bool {
        switch store.layout {
        case .immersiveConversation, .immersiveWriting:
            return false
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit, .immersiveReading:
            return !hasPrimaryAgentPaneVisible
        }
    }

    private var hasReaderScopedTopActions: Bool {
        switch store.layout {
        case .immersiveConversation, .immersiveWriting:
            return false
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit, .immersiveReading:
            return true
        }
    }

    private var shortLayoutLabel: String {
        switch store.layout {
        case .documentAgentNotes, .documentNotesAgent:
            return store.threePaneOrderLabel(compact: true)
        case .documentNotesSplit:
            return store.ui("文笔对半", "Half Split")
        case .immersiveReading:
            return store.ui("阅读", "Reading")
        case .immersiveConversation:
            return store.ui("对话", "Chat")
        case .immersiveWriting:
            return store.ui("写作", "Writing")
        }
    }

    private var documentTitleFont: Font {
        variant == .reader ? .system(size: 14, weight: .semibold) : .system(size: 13, weight: .medium)
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

    private var dividerColor: Color {
        WeiBeiTheme.hairline
    }

    private var controlFill: Color {
        WeiBeiTheme.paperInset.opacity(variant == .glyph ? 0.30 : 0.38)
    }

    private var topHighlight: Color {
        WeiBeiTheme.glassHighlight.opacity(0.24)
    }

    private var topBarBackground: some View {
        WeiBeiGlassHeaderBackground(
            paperOpacity: backgroundPaperOpacity - (isImmersiveLayout ? 0.06 : 0),
            materialOpacity: backgroundMaterialOpacity + (isImmersiveLayout ? 0.03 : 0)
        )
    }

    private var backgroundPaperOpacity: Double {
        switch variant {
        case .glyph:
            return 0.78
        case .compact:
            return 0.80
        case .reader:
            return 0.84
        case .balanced:
            return 0.82
        case .wide:
            return 0.86
        }
    }

    private var backgroundMaterialOpacity: Double {
        switch variant {
        case .glyph:
            return 0.10
        case .compact:
            return 0.09
        case .reader:
            return 0.08
        case .balanced:
            return 0.09
        case .wide:
            return 0.08
        }
    }

    @ViewBuilder
    private var leftPrimaryControls: some View {
        HStack(spacing: 5) {
            libraryButton

            navigationButtons

            appearanceToggleButton

            settingsMenu
        }
    }

    @ViewBuilder
    private var brandBlock: some View {
        switch variant {
        case .glyph:
            HStack(spacing: 5) {
                Image(systemName: "seal")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(primaryText.opacity(0.82))
                Text(store.brandLatinName)
                    .font(WeiBeiTypography.englishBrandFont(size: 14.2, weight: .semibold))
                    .tracking(0.15)
                    .foregroundStyle(primaryText)
            }
            .frame(width: 78, height: controlHeight, alignment: .leading)
        case .compact:
            Text(store.brandLatinName)
                .font(WeiBeiTypography.englishBrandFont(size: 15.5, weight: .semibold))
                .tracking(0.15)
                .foregroundStyle(primaryText)
                .frame(width: 62, alignment: .leading)
        case .reader:
            VStack(alignment: .leading, spacing: 0) {
                Text(store.brandLatinName)
                    .font(WeiBeiTypography.englishBrandFont(size: 14, weight: .semibold))
                    .tracking(0.15)
                    .foregroundStyle(secondaryText)
                Text(shortLayoutLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tertiaryText)
            }
            .frame(width: 56, alignment: .leading)
        case .balanced, .wide:
            VStack(alignment: .leading, spacing: 0) {
                Text(store.brandLatinName)
                    .font(WeiBeiTypography.englishBrandFont(size: variant == .wide ? 17 : 16, weight: .semibold))
                    .tracking(0.15)
                    .foregroundStyle(primaryText)
                Text(shortLayoutLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tertiaryText)
            }
            .frame(width: variant == .wide ? 96 : 86, alignment: .leading)
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

    @ViewBuilder
    private var libraryButton: some View {
        topIconButton("sidebar.left", help: store.showLibrary ? store.ui("收起课程目录", "Hide course index") : store.ui("打开课程目录", "Show course index"), active: store.showLibrary) {
            withAnimation(WeiBeiMotion.layout) {
                store.toggleLibrary()
            }
        }
    }

    @ViewBuilder
    private var searchButton: some View {
        topIconButton("magnifyingglass", help: store.ui("打开资料内搜索", "Search in material")) {
            toggleReaderSearch()
        }
    }

    @ViewBuilder
    private var agentButton: some View {
        topIconButton("bubble.left.and.text.bubble.right", help: agentButtonHelp) {
            activateAgentEntry()
        }
    }

    @ViewBuilder
    private var appearanceToggleButton: some View {
        topIconButton(store.appearanceMode.toggled.systemImage, help: store.appearanceMode.actionLabel(language: store.interfaceLanguage)) {
            withAnimation(WeiBeiMotion.appearance) {
                store.toggleAppearanceMode()
            }
        }
    }

    @ViewBuilder
    private var settingsMenu: some View {
        Menu {
            Section(store.ui("界面", "Interface")) {
                ForEach(WeiBeiAppearanceMode.allCases) { mode in
                    Button {
                        withAnimation(WeiBeiMotion.appearance) {
                            store.setAppearanceMode(mode)
                        }
                    } label: {
                        Label(mode.label(language: store.interfaceLanguage), systemImage: mode == store.appearanceMode ? "checkmark" : mode.systemImage)
                    }
                }
            }

            Section(store.ui("语言", "Language")) {
                ForEach(WeiBeiInterfaceLanguage.allCases) { language in
                    Button {
                        withAnimation(WeiBeiMotion.appearance) {
                            store.setInterfaceLanguage(language)
                        }
                    } label: {
                        Label(language.settingsLabel, systemImage: language == store.interfaceLanguage ? "checkmark" : "character.book.closed")
                    }
                }
            }

            Section(store.ui("顶部栏", "Top Bar")) {
                ForEach(TopBarVariant.allCases) { candidate in
                    Button {
                        setTopBarVariant(candidate)
                    } label: {
                        Label(candidate.label(language: store.interfaceLanguage), systemImage: candidate == variant ? "checkmark" : candidate.iconName)
                    }
                }
            }

            Section(store.ui("对话形态", "Chat Surface")) {
                ForEach(store.visibleAgentSurfaces) { surface in
                    Button(surface.label(language: store.interfaceLanguage)) {
                        withAnimation(WeiBeiMotion.panel) {
                            store.setAgentSurface(surface)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: variant == .glyph || variant == .compact ? 24 : WeiBeiMetric.iconButton))
        .accessibilityLabel(Text(store.ui("设置", "Settings")))
        .help(store.ui("设置", "Settings"))
    }

    private var hasPrimaryAgentPaneVisible: Bool {
        hasPrimaryAgentPaneAvailable && store.showRightPane
    }

    private var hasPrimaryAgentPaneAvailable: Bool {
        store.layout.hasPrimaryAgentPane
    }

    private var agentButtonHelp: String {
        if hasPrimaryAgentPaneAvailable {
            return store.ui("打开对话区", "Open chat pane")
        }
        if store.selectionContext != nil {
            return store.ui("按当前选区提问", "Ask about current selection")
        }
        return store.hasSelectedMaterial ? store.ui("按当前资料提问", "Ask about current material") : store.ui("按当前笔记提问", "Ask about current note")
    }

    private func activateAgentEntry() {
        if hasPrimaryAgentPaneAvailable {
            withAnimation(WeiBeiMotion.panel) {
                store.revealRightPane(focusing: .agent)
            }
        } else {
            store.askSelection()
        }
    }

    private var layoutMenu: some View {
        Menu {
            ForEach(WorkspaceLayout.allCases) { layout in
                Button {
                    withAnimation(WeiBeiMotion.layout) {
                        store.setLayout(layout)
                    }
                } label: {
                    Label(layout.label(language: store.interfaceLanguage), systemImage: layout == store.layout ? "checkmark" : layout.systemImage)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(layoutMenuTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(secondaryText)
            .padding(.horizontal, 9)
            .frame(width: layoutMenuWidth, height: controlHeight)
            .background(controlFill.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(dividerColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(store.ui("切换布局", "Switch layout")))
        .help(store.ui("切换布局", "Switch layout"))
    }

    private func setTopBarVariant(_ next: TopBarVariant) {
        withAnimation(WeiBeiMotion.layout) {
            store.setTopBarVariant(next)
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
        .buttonStyle(WeiBeiIconButtonStyle(active: active, size: variant == .glyph || variant == .compact ? 24 : WeiBeiMetric.iconButton))
        .accessibilityLabel(Text(help))
        .help(help)
    }
}

private struct LayoutContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @SceneStorage("documentThreePaneFirstSplit") private var firstSplitStorage: Double = 0.34
    @SceneStorage("documentThreePaneSecondSplit") private var secondSplitStorage: Double = 0.67
    @SceneStorage("documentNotesHalfSplit") private var halfSplitStorage: Double = 0.50
    @SceneStorage("conversationFirstSplit") private var conversationFirstSplitStorage: Double = 0.12
    @SceneStorage("conversationSecondSplit") private var conversationSecondSplitStorage: Double = 0.90
    @SceneStorage("conversationLeftSplit") private var conversationLeftSplitStorage: Double = 0.13
    @SceneStorage("writingFirstSplit") private var writingFirstSplitStorage: Double = 0.13
    @SceneStorage("writingSecondSplit") private var writingSecondSplitStorage: Double = 0.90
    @SceneStorage("writingLeftSplit") private var writingLeftSplitStorage: Double = 0.13
    
    var body: some View {
        Group {
            switch store.layout {
            case .documentAgentNotes, .documentNotesAgent:
                if store.showRightPane {
                    let order = store.normalizedThreePaneOrder
                    documentThreePaneView(order: order)
                } else {
                    ReaderPaneView()
                        .transition(WeiBeiTransition.layout)
                }
            case .documentNotesSplit:
                if store.showRightPane {
                    ZStack(alignment: agentAlignment) {
                        ResizableTwoPane(split: halfSplit) {
                            ReaderView()
                        } second: {
                            NotePaneView()
                        }
                        agentOverlay
                    }
                    .transition(WeiBeiTransition.rightPanel)
                } else {
                    ReaderView()
                        .transition(WeiBeiTransition.layout)
                }
            case .immersiveReading:
                ZStack(alignment: .topTrailing) {
                    ReaderView(isImmersive: true)
                    if store.showQuietInsight && store.agentSurface != .hidden {
                        QuietInsightView(compact: true)
                            .padding(.trailing, 28)
                            .padding(.top, 24)
                            .transition(WeiBeiTransition.rightPanel)
                    }
                }
                .overlay(alignment: agentAlignment) {
                    if store.agentSurface != .quietInsight {
                        agentOverlay
                    }
                }
            case .immersiveConversation:
                if store.showRightPane {
                    ResizableThreePane(
                        firstSplit: conversationFirstSplit,
                        secondSplit: conversationSecondSplit,
                        minFirst: 92,
                        minSecond: 520,
                        minThird: 96
                    ) {
                        ContextRailView(title: store.ui("来源", "Sources"), items: conversationSourceRailItems, edge: .trailing)
                            .transition(WeiBeiTransition.rail)
                    } second: {
                        AgentPaneView()
                    } third: {
                        ContextRailView(title: store.ui("写入目标", "Write Targets"), items: conversationTargetRailItems, edge: .leading)
                            .transition(WeiBeiTransition.rail)
                    }
                    .transition(WeiBeiTransition.rightPanel)
                } else {
                    ResizableTwoPane(split: conversationLeftSplit, minFirst: 92, minSecond: 520) {
                        ContextRailView(title: store.ui("来源", "Sources"), items: conversationSourceRailItems, edge: .trailing)
                            .transition(WeiBeiTransition.rail)
                    } second: {
                        AgentPaneView()
                    }
                    .transition(WeiBeiTransition.layout)
                }
            case .immersiveWriting:
                ZStack(alignment: agentAlignment) {
                    if store.showRightPane {
                        ResizableThreePane(
                            firstSplit: writingFirstSplit,
                            secondSplit: writingSecondSplit,
                            minFirst: 96,
                            minSecond: 540,
                            minThird: 104
                        ) {
                            ContextRailView(title: store.ui("文档", "Documents"), items: writingDocumentRailItems, edge: .trailing)
                                .transition(WeiBeiTransition.rail)
                        } second: {
                            NotePaneView()
                        } third: {
                            ContextRailView(title: store.ui("写作辅助", "Writing Aids"), items: writingAssistRailItems, edge: .leading)
                                .transition(WeiBeiTransition.rail)
                        }
                        .transition(WeiBeiTransition.rightPanel)
                    } else {
                        ResizableTwoPane(split: writingLeftSplit, minFirst: 96, minSecond: 540) {
                            ContextRailView(title: store.ui("文档", "Documents"), items: writingDocumentRailItems, edge: .trailing)
                                .transition(WeiBeiTransition.rail)
                        } second: {
                            NotePaneView()
                        }
                        .transition(WeiBeiTransition.layout)
                    }

                    if store.agentSurface != .quietInsight {
                        agentOverlay
                    }
                }
            }
        }
        .transition(WeiBeiTransition.layout)
        .animation(WeiBeiMotion.layout, value: store.layout)
        .animation(WeiBeiMotion.panel, value: store.showRightPane)
        .animation(WeiBeiMotion.panel, value: store.agentSurface)
        .animation(WeiBeiMotion.panel, value: store.showQuietInsight)
    }

    private var firstSplit: Binding<CGFloat> {
        numericBinding($firstSplitStorage)
    }

    private var secondSplit: Binding<CGFloat> {
        numericBinding($secondSplitStorage)
    }

    private var halfSplit: Binding<CGFloat> {
        numericBinding($halfSplitStorage)
    }

    private var conversationFirstSplit: Binding<CGFloat> {
        numericBinding($conversationFirstSplitStorage)
    }

    private var conversationSecondSplit: Binding<CGFloat> {
        numericBinding($conversationSecondSplitStorage)
    }

    private var conversationLeftSplit: Binding<CGFloat> {
        numericBinding($conversationLeftSplitStorage)
    }

    private var writingFirstSplit: Binding<CGFloat> {
        numericBinding($writingFirstSplitStorage)
    }

    private var writingSecondSplit: Binding<CGFloat> {
        numericBinding($writingSecondSplitStorage)
    }

    private var writingLeftSplit: Binding<CGFloat> {
        numericBinding($writingLeftSplitStorage)
    }

    private var normalSidePaneMinimum: CGFloat {
        store.showLibrary ? 220 : 260
    }

    private func minimumWidth(for role: WorkspacePaneRole) -> CGFloat {
        switch role {
        case .reader:
            return 320
        case .agent, .notes:
            return normalSidePaneMinimum
        }
    }

    @ViewBuilder
    private func documentThreePaneView(order: [WorkspacePaneRole]) -> some View {
        GeometryReader { geometry in
            let estimatedFrames = threePaneFrames(order: order, size: geometry.size)
            let frames = store.threePaneReorderFrameList(order: order, fallback: estimatedFrames)
            ZStack {
                ResizableThreePane(
                    firstSplit: firstSplit,
                    secondSplit: secondSplit,
                    minFirst: minimumWidth(for: order[0]),
                    minSecond: minimumWidth(for: order[1]),
                    minThird: minimumWidth(for: order[2])
                ) {
                    reorderablePaneView(for: order[0])
                } second: {
                    reorderablePaneView(for: order[1])
                } third: {
                    reorderablePaneView(for: order[2])
                } onFramesChange: { frames in
                    store.updateThreePaneReorderFrames(order: order, frames: frames)
                }

                threePaneReorderOverlay(order: order, size: geometry.size, frames: frames)
            }
            .background(ThreePaneReorderFrameReporter(order: order, frames: estimatedFrames))
        }
        .transition(WeiBeiTransition.rightPanel)
    }

    @ViewBuilder
    private func reorderablePaneView(for role: WorkspacePaneRole) -> some View {
        let drag = store.threePaneReorderDrag
        paneView(for: role, reorderable: true)
            .opacity(drag?.role == role ? 0.08 : 1)
            .overlay {
                if drag?.targetIndex == store.normalizedThreePaneOrder.firstIndex(of: role), drag?.role != role {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(WeiBeiTheme.cinnabar.opacity(0.22), lineWidth: 1)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(WeiBeiTheme.cinnabarSoft.opacity(0.10))
                        }
                        .padding(8)
                        .transition(WeiBeiTransition.floating)
                }
            }
            .animation(WeiBeiMotion.micro, value: drag)
    }

    @ViewBuilder
    private func paneView(for role: WorkspacePaneRole, reorderable: Bool) -> some View {
        switch role {
        case .reader:
            ReaderPaneView(reorderRole: reorderable ? .reader : nil)
        case .agent:
            AgentPaneView(reorderRole: reorderable ? .agent : nil)
        case .notes:
            NotePaneView(reorderRole: reorderable ? .notes : nil)
        }
    }

    @ViewBuilder
    private func threePaneReorderOverlay(order: [WorkspacePaneRole], size: CGSize, frames: [CGRect]) -> some View {
        if let drag = store.threePaneReorderDrag,
           let sourceIndex = order.firstIndex(of: drag.role) {
            if frames.indices.contains(sourceIndex) {
                let sourceFrame = frames[sourceIndex]
                if let targetIndex = drag.targetIndex, frames.indices.contains(targetIndex) {
                    PaneDropTargetView(role: order[targetIndex])
                        .frame(width: frames[targetIndex].width, height: frames[targetIndex].height)
                        .position(x: frames[targetIndex].midX, y: frames[targetIndex].midY)
                        .transition(WeiBeiTransition.floating)
                }

                paneView(for: drag.role, reorderable: false)
                    .frame(width: sourceFrame.width, height: sourceFrame.height)
                    .clipped()
                    .allowsHitTesting(false)
                    .opacity(0.11)
                    .overlay {
                        Rectangle()
                            .stroke(WeiBeiTheme.cinnabar.opacity(0.22), lineWidth: 1)
                    }
                    .position(
                        x: sourceFrame.midX + clamped(drag.translation, min: -size.width, max: size.width),
                        y: sourceFrame.midY
                    )
                    .transition(WeiBeiTransition.floating)
                    .shadow(color: WeiBeiTheme.ink.opacity(store.appearanceMode == .inkstone ? 0.38 : 0.14), radius: 22, y: 12)
                    .zIndex(8)
            }
        }
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

    private func clamped(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), Swift.max(min, max))
    }

    private struct ThreePaneReorderFrameReporter: View {
        @EnvironmentObject private var store: WorkspaceStore
        let order: [WorkspacePaneRole]
        let frames: [CGRect]

        var body: some View {
            Color.clear
                .onAppear(perform: report)
                .onChange(of: order) { _, _ in report() }
                .onChange(of: frames) { _, _ in report() }
        }

        private func report() {
            store.updateThreePaneReorderFrames(order: order, frames: frames)
        }
    }

    private var conversationSourceRailItems: [ContextRailItem] {
        var items: [ContextRailItem] = []
        if let item = store.selectedMaterialItem {
            items.append(
                ContextRailItem(
                    title: store.displayTitle(for: item),
                    help: store.ui("切回沉浸阅读", "Return to immersive reading"),
                    systemImage: item.kind.systemImage,
                    emphasized: true
                ) {
                    openReader()
                }
            )
        }
        items.append(
            ContextRailItem(title: store.ui("当前笔记", "Current Note"), help: store.ui("切回沉浸写作", "Return to immersive writing"), systemImage: "square.and.pencil") {
                openWriting()
            }
        )
        if store.selectionContext != nil {
            items.append(
                ContextRailItem(title: store.ui("选区", "Selection"), help: store.ui("追问当前选区", "Ask about current selection"), systemImage: "text.cursor") {
                    askCurrentSelection()
                }
            )
        }
        return items
    }

    private var conversationTargetRailItems: [ContextRailItem] {
        var items = [
            ContextRailItem(title: store.ui("当前笔记", "Current Note"), help: store.ui("打开写作区", "Open writing area"), systemImage: "square.and.pencil", emphasized: true) {
                openWriting()
            }
        ]
        if store.selectionContext != nil {
            items.append(
                ContextRailItem(title: store.ui("摘录区", "Excerpt Area"), help: store.ui("把当前选区收进笔记", "Save the current selection to notes"), systemImage: "quote.opening") {
                    appendSelectionAndOpenWriting()
                }
            )
        }
        items.append(
            ContextRailItem(title: store.ui("问题与结论", "Questions & Conclusions"), help: store.ui("整理问题、结论和缺少证据", "Organize questions, conclusions, and missing evidence"), systemImage: "checkmark.circle") {
                prepareAgentDraft(store.ui("请根据\(store.agentPromptScope)，整理出问题、结论和还缺少的证据。", "Use \(store.agentPromptScope) to organize questions, conclusions, and missing evidence."))
            }
        )
        return items
    }

    private var writingDocumentRailItems: [ContextRailItem] {
        var items: [ContextRailItem] = []
        if let item = store.selectedMaterialItem {
            items.append(
                ContextRailItem(
                    title: store.displayTitle(for: item),
                    help: store.ui("切回沉浸阅读", "Return to immersive reading"),
                    systemImage: item.kind.systemImage,
                    emphasized: true
                ) {
                    openReader()
                }
            )
        }
        if store.hasSelectedMaterial || store.selectionContext != nil {
            items.append(
                ContextRailItem(title: store.ui("引用", "Reference"), help: store.ui("复制当前材料或选区引用", "Copy current material or selection reference"), systemImage: "quote.opening") {
                    store.copyCurrentReference()
                }
            )
        }
        return items
    }

    private var writingAssistRailItems: [ContextRailItem] {
        [
            ContextRailItem(title: store.ui("大纲建议", "Outline"), help: store.ui("生成笔记大纲", "Generate a note outline"), systemImage: "list.bullet.rectangle", emphasized: true) {
                prepareAgentDraft(store.ui("请根据\(store.agentPromptScope)，给出一版更清晰的笔记大纲。", "Use \(store.agentPromptScope) to produce a clearer note outline."))
            },
            ContextRailItem(title: store.ui("补来源", "Add Sources"), help: store.ui("检查笔记缺少来源的位置", "Find places where notes need sources"), systemImage: "link") {
                prepareAgentDraft(store.hasSelectedMaterial ? store.ui("请检查当前笔记缺少来源的位置，并建议应该引用当前材料的哪些部分。", "Find where the current note needs sources and suggest which parts of the current material to cite.") : store.ui("请检查当前笔记缺少来源的位置，并标出需要补证据的段落。", "Find where the current note needs sources and mark the paragraphs that need evidence."))
            },
            ContextRailItem(title: store.ui("润色表达", "Polish"), help: store.ui("润色当前笔记", "Polish current note"), systemImage: "text.quote") {
                prepareAgentDraft(store.ui("请整理和润色当前笔记，保留原意，并标出缺少来源的位置。", "Organize and polish the current note, preserve the meaning, and mark where sources are missing."))
            }
        ]
    }

    private func numericBinding(_ storage: Binding<Double>) -> Binding<CGFloat> {
        Binding(
            get: { CGFloat(storage.wrappedValue) },
            set: { storage.wrappedValue = Double($0) }
        )
    }

    private func openReader() {
        withAnimation(WeiBeiMotion.layout) {
            store.setLayout(.immersiveReading)
        }
    }

    private func openWriting() {
        withAnimation(WeiBeiMotion.layout) {
            store.setLayout(.immersiveWriting)
            store.revealRightPane(focusing: .notes)
        }
    }

    private func askCurrentSelection() {
        store.askSelection()
        withAnimation(WeiBeiMotion.layout) {
            store.setLayout(.immersiveConversation)
            store.revealRightPane(focusing: .agent)
        }
    }

    private func appendSelectionAndOpenWriting() {
        store.appendSelectionToNote()
        openWriting()
    }

    private func prepareAgentDraft(_ prompt: String) {
        withAnimation(WeiBeiMotion.layout) {
            store.agentDraft = prompt
            store.setLayout(.immersiveConversation)
            store.revealRightPane(focusing: .agent)
        }
    }

    private var agentAlignment: Alignment {
        switch store.agentSurface {
        case .bottomDrawer:
            .bottom
        case .cornerPanel:
            .bottomTrailing
        case .selectionFloat:
            .center
        case .quietInsight:
            .trailing
        case .hidden:
            .bottom
        }
    }

    @ViewBuilder
    private var agentOverlay: some View {
        switch store.agentSurface {
        case .bottomDrawer:
            AgentDrawerView()
                .padding(18)
                .transition(WeiBeiTransition.drawer)
                .zIndex(4)
        case .cornerPanel:
            CornerAgentView()
                .padding(18)
                .transition(WeiBeiTransition.floating)
                .zIndex(4)
        case .selectionFloat:
            EmptyView()
        case .quietInsight:
            QuietInsightView()
                .padding(.trailing, 28)
                .transition(WeiBeiTransition.rightPanel)
                .zIndex(4)
        case .hidden:
            EmptyView()
        }
    }
}

private struct PaneDropTargetView: View {
    @EnvironmentObject private var store: WorkspaceStore
    var role: WorkspacePaneRole

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode == .inkstone ? 0.16 : 0.12))
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

private struct ResizableTwoPane<First: View, Second: View>: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var split: CGFloat
    var minFirst: CGFloat = 320
    var minSecond: CGFloat = 320
    private let first: First
    private let second: Second

    init(
        split: Binding<CGFloat>,
        minFirst: CGFloat = 320,
        minSecond: CGFloat = 320,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) {
        _split = split
        self.minFirst = minFirst
        self.minSecond = minSecond
        self.first = first()
        self.second = second()
    }

    func makeCoordinator() -> NativeSplitCoordinator {
        NativeSplitCoordinator(kind: .two(split: $split), minimums: [minFirst, minSecond])
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
        context.coordinator.kind = .two(split: $split)
        context.coordinator.minimums = [minFirst, minSecond]
        updateHost(at: 0, in: splitView, with: first)
        updateHost(at: 1, in: splitView, with: second)
        context.coordinator.applyStoredPositionsWhenNeeded(in: splitView)
    }

    private func nativeHost<V: View>(_ view: V) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view.environmentObject(store)))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.defaultLow, for: .horizontal)
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return host
    }

    private func updateHost<V: View>(at index: Int, in splitView: NSSplitView, with view: V) {
        guard splitView.arrangedSubviews.indices.contains(index),
              let host = splitView.arrangedSubviews[index] as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(view.environmentObject(store))
    }
}

private struct ResizableThreePane<First: View, Second: View, Third: View>: NSViewRepresentable {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var firstSplit: CGFloat
    @Binding var secondSplit: CGFloat
    var minFirst: CGFloat = 320
    var minSecond: CGFloat = 260
    var minThird: CGFloat = 260
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
        self.onFramesChange = onFramesChange
        self.first = first()
        self.second = second()
        self.third = third()
    }

    func makeCoordinator() -> NativeSplitCoordinator {
        NativeSplitCoordinator(kind: .three(first: $firstSplit, second: $secondSplit), minimums: [minFirst, minSecond, minThird], onFramesChange: onFramesChange)
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
        context.coordinator.kind = .three(first: $firstSplit, second: $secondSplit)
        context.coordinator.minimums = [minFirst, minSecond, minThird]
        context.coordinator.onFramesChange = onFramesChange
        updateHost(at: 0, in: splitView, with: first)
        updateHost(at: 1, in: splitView, with: second)
        updateHost(at: 2, in: splitView, with: third)
        context.coordinator.applyStoredPositionsWhenNeeded(in: splitView)
    }

    private func nativeHost<V: View>(_ view: V) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(view.environmentObject(store)))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.setContentHuggingPriority(.defaultLow, for: .horizontal)
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return host
    }

    private func updateHost<V: View>(at index: Int, in splitView: NSSplitView, with view: V) {
        guard splitView.arrangedSubviews.indices.contains(index),
              let host = splitView.arrangedSubviews[index] as? NSHostingView<AnyView> else { return }
        host.rootView = AnyView(view.environmentObject(store))
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
        onLayout?(self)
    }

    override func drawDivider(in rect: NSRect) {
        dividerFill.setFill()
        rect.fill()
        let line = NSRect(x: rect.midX - 0.5, y: rect.minY + 14, width: 1, height: max(0, rect.height - 28))
        dividerLine.setFill()
        line.fill()
    }

    private var dividerFill: NSColor {
        if isDarkAppearance {
            return NSColor(calibratedRed: 0.059, green: 0.059, blue: 0.059, alpha: 0.96)
        }
        return NSColor(calibratedRed: 0.955, green: 0.918, blue: 0.835, alpha: 0.96)
    }

    private var dividerLine: NSColor {
        if isDarkAppearance {
            return NSColor(calibratedRed: 0.230, green: 0.200, blue: 0.155, alpha: 0.24)
        }
        return NSColor(calibratedRed: 0.500, green: 0.380, blue: 0.260, alpha: 0.13)
    }

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private final class NativeSplitCoordinator: NSObject, NSSplitViewDelegate {
    enum Kind {
        case two(split: Binding<CGFloat>)
        case three(first: Binding<CGFloat>, second: Binding<CGFloat>)
    }

    var kind: Kind
    var minimums: [CGFloat]
    var onFramesChange: (([CGRect]) -> Void)?
    private var isDragging = false
    private var isApplyingStoredPositions = false
    private var lastAppliedWidth: CGFloat = 0
    private var saveWork: DispatchWorkItem?

    init(kind: Kind, minimums: [CGFloat], onFramesChange: (([CGRect]) -> Void)? = nil) {
        self.kind = kind
        self.minimums = minimums
        self.onFramesChange = onFramesChange
    }

    func install(_ splitView: WeiBeiSplitView) {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.onDragStart = { [weak self] in
            self?.isDragging = true
            self?.saveWork?.cancel()
        }
        splitView.onDragEnd = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.isDragging = false
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

        lastAppliedWidth = splitView.bounds.width
        reportFrames(from: splitView)
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
        lastAppliedWidth = splitView.bounds.width
        reportFrames(from: splitView)
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
