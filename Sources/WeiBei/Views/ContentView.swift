import AppKit
import SwiftUI
import WeiBeiCore

struct ContentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var focusedPane: PaneFocus?
    @FocusState private var topSearchFocused: Bool
    @SceneStorage("libraryPaneWidth") private var libraryPaneWidthStorage: Double = 292
    @AppStorage("topBarVariant") private var topBarVariantRaw = TopBarVariant.balanced.rawValue
    @State private var floatingAgentExpanded = false
    @State private var libraryDragStartWidth: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                UnifiedTopBarView(
                    isImmersiveLayout: isImmersiveLayout,
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
                        FloatingSelectionAgentView(expanded: $floatingAgentExpanded)
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
        SelectionFloatingAgentPlacement.isVisible(
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
        (TopBarVariant(rawValue: topBarVariantRaw) ?? .balanced).height
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
            .help("拖动调整资料库宽度")
    }

}

private struct UnifiedTopBarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let isImmersiveLayout: Bool
    var searchFocused: FocusState<Bool>.Binding
    @State private var appeared = false
    @AppStorage("topBarVariant") private var topBarVariantRaw = TopBarVariant.balanced.rawValue

    var body: some View {
        HStack(spacing: topBarSpacing) {
            Spacer()
                .frame(width: leftInset)

            Button {
                withAnimation(WeiBeiMotion.layout) {
                    store.toggleLibrary()
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(WeiBeiIconButtonStyle(active: store.showLibrary))
            .accessibilityLabel(Text(store.showLibrary ? "收起资料库" : "打开资料库"))
            .help(store.showLibrary ? "收起资料库" : "打开资料库")

            brandBlock

            if variant != .glyph, shouldShowTopDocumentTitle {
                Rectangle()
                    .fill(dividerColor.opacity(0.72))
                    .frame(width: 1, height: 18)

                Text(store.selectedMaterialItem?.title ?? "未选择资料")
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
                    prompt: Text("资料内搜索")
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

            appearanceButton

            layoutMenu

            moreMenu

            topIconButton("command", help: "命令面板") {
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
        .animation(WeiBeiMotion.layout, value: topBarVariantRaw)
    }

    private var variant: TopBarVariant {
        TopBarVariant(rawValue: topBarVariantRaw) ?? .balanced
    }

    private var barHeight: CGFloat {
        variant.height
    }

    private var leftInset: CGFloat {
        switch variant {
        case .compact, .glyph:
            return 54
        case .reader:
            return 60
        case .balanced:
            return 64
        case .wide:
            return 70
        }
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
        variant == .glyph || variant == .compact ? shortLayoutLabel : store.layout.label
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
        case .documentAgentNotes:
            return "对话中栏"
        case .documentNotesAgent:
            return "对话右栏"
        case .documentNotesSplit:
            return "文笔对半"
        case .immersiveReading:
            return "阅读"
        case .immersiveConversation:
            return "对话"
        case .immersiveWriting:
            return "写作"
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
    private var brandBlock: some View {
        switch variant {
        case .glyph:
            Image(systemName: "seal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primaryText)
                .frame(width: 28, height: controlHeight)
        case .compact:
            Text("魏碑")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(primaryText)
                .frame(width: 42, alignment: .leading)
        case .reader:
            VStack(alignment: .leading, spacing: 0) {
                Text("魏碑")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(secondaryText)
                Text(shortLayoutLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(tertiaryText)
            }
            .frame(width: 48, alignment: .leading)
        case .balanced, .wide:
            VStack(alignment: .leading, spacing: 0) {
                Text("魏碑")
                    .font(.system(size: variant == .wide ? 15 : 14, weight: .semibold, design: .serif))
                    .foregroundStyle(primaryText)
                Text(store.layout.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(tertiaryText)
            }
            .frame(width: variant == .wide ? 92 : 82, alignment: .leading)
        }
    }

    @ViewBuilder
    private var searchButton: some View {
        topIconButton("magnifyingglass", help: "打开资料内搜索") {
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
    private var appearanceButton: some View {
        topIconButton(
            store.appearanceMode.systemImage,
            help: store.appearanceMode.actionLabel,
            active: store.appearanceMode == .inkstone
        ) {
            withAnimation(WeiBeiMotion.appearance) {
                store.toggleAppearanceMode()
            }
        }
    }

    private var hasPrimaryAgentPaneVisible: Bool {
        hasPrimaryAgentPaneAvailable && store.showRightPane
    }

    private var hasPrimaryAgentPaneAvailable: Bool {
        store.layout.hasPrimaryAgentPane
    }

    private var agentButtonHelp: String {
        if hasPrimaryAgentPaneAvailable {
            return "打开对话区"
        }
        if store.selectionContext != nil {
            return "按当前选区提问"
        }
        return store.hasSelectedMaterial ? "按当前资料提问" : "按当前笔记提问"
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
                    Label(layout.label, systemImage: layout == store.layout ? "checkmark" : layout.systemImage)
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
        .accessibilityLabel(Text("切换布局"))
        .help("切换布局")
    }

    private var moreMenu: some View {
        Menu {
            Section("顶部栏") {
                ForEach(TopBarVariant.allCases) { candidate in
                    Button {
                        setTopBarVariant(candidate)
                    } label: {
                        Label(candidate.label, systemImage: candidate == variant ? "checkmark" : candidate.iconName)
                    }
                }
            }

            Section("界面") {
                ForEach(WeiBeiAppearanceMode.allCases) { mode in
                    Button {
                        withAnimation(WeiBeiMotion.appearance) {
                            store.setAppearanceMode(mode)
                        }
                    } label: {
                        Label(mode.label, systemImage: mode == store.appearanceMode ? "checkmark" : mode.systemImage)
                    }
                }
            }

            Section("对话入口") {
                ForEach(store.visibleAgentSurfaces) { surface in
                    Button(surface.label) {
                        withAnimation(WeiBeiMotion.panel) {
                            store.setAgentSurface(surface)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .buttonStyle(WeiBeiIconButtonStyle())
        .accessibilityLabel(Text("更多设置"))
        .help("更多设置")
    }

    private func setTopBarVariant(_ next: TopBarVariant) {
        withAnimation(WeiBeiMotion.layout) {
            topBarVariantRaw = next.rawValue
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
            case .documentAgentNotes:
                if store.showRightPane {
                    ResizableThreePane(
                        firstSplit: firstSplit,
                        secondSplit: secondSplit,
                        minFirst: 320,
                        minSecond: normalSidePaneMinimum,
                        minThird: normalSidePaneMinimum
                    ) {
                        ReaderView()
                    } second: {
                        AgentPaneView()
                    } third: {
                        NotePaneView()
                    }
                    .transition(WeiBeiTransition.rightPanel)
                } else {
                    ReaderView()
                        .transition(WeiBeiTransition.layout)
                }
            case .documentNotesAgent:
                if store.showRightPane {
                    ResizableThreePane(
                        firstSplit: firstSplit,
                        secondSplit: secondSplit,
                        minFirst: 320,
                        minSecond: normalSidePaneMinimum,
                        minThird: normalSidePaneMinimum
                    ) {
                        ReaderView()
                    } second: {
                        NotePaneView()
                    } third: {
                        AgentPaneView()
                    }
                    .transition(WeiBeiTransition.rightPanel)
                } else {
                    ReaderView()
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
                ZStack(alignment: .bottomTrailing) {
                    ReaderView(isImmersive: true)
                    if store.showQuietInsight && store.agentSurface != .hidden {
                        QuietInsightView(compact: true)
                            .padding(.trailing, 28)
                            .padding(.bottom, 28)
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
                        ContextRailView(title: "来源", items: conversationSourceRailItems, edge: .trailing)
                            .transition(WeiBeiTransition.rail)
                    } second: {
                        AgentPaneView()
                    } third: {
                        ContextRailView(title: "写入目标", items: conversationTargetRailItems, edge: .leading)
                            .transition(WeiBeiTransition.rail)
                    }
                    .transition(WeiBeiTransition.rightPanel)
                } else {
                    ResizableTwoPane(split: conversationLeftSplit, minFirst: 92, minSecond: 520) {
                        ContextRailView(title: "来源", items: conversationSourceRailItems, edge: .trailing)
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
                            ContextRailView(title: "文档", items: writingDocumentRailItems, edge: .trailing)
                                .transition(WeiBeiTransition.rail)
                        } second: {
                            NotePaneView()
                        } third: {
                            ContextRailView(title: "写作辅助", items: writingAssistRailItems, edge: .leading)
                                .transition(WeiBeiTransition.rail)
                        }
                        .transition(WeiBeiTransition.rightPanel)
                    } else {
                        ResizableTwoPane(split: writingLeftSplit, minFirst: 96, minSecond: 540) {
                            ContextRailView(title: "文档", items: writingDocumentRailItems, edge: .trailing)
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

    private var conversationSourceRailItems: [ContextRailItem] {
        var items: [ContextRailItem] = []
        if let item = store.selectedMaterialItem {
            items.append(
                ContextRailItem(
                    title: item.title,
                    help: "切回沉浸阅读",
                    systemImage: item.kind.systemImage,
                    emphasized: true
                ) {
                    openReader()
                }
            )
        }
        items.append(
            ContextRailItem(title: "当前笔记", help: "切回沉浸写作", systemImage: "square.and.pencil") {
                openWriting()
            }
        )
        if store.selectionContext != nil {
            items.append(
                ContextRailItem(title: "选区", help: "追问当前选区", systemImage: "text.cursor") {
                    askCurrentSelection()
                }
            )
        }
        items.append(
            ContextRailItem(title: "资料库", help: "打开资料库选择资料", systemImage: "sidebar.left") {
                openLibrary()
            }
        )
        return items
    }

    private var conversationTargetRailItems: [ContextRailItem] {
        var items = [
            ContextRailItem(title: "当前笔记", help: "打开写作区", systemImage: "square.and.pencil", emphasized: true) {
                openWriting()
            }
        ]
        if store.selectionContext != nil {
            items.append(
                ContextRailItem(title: "摘录区", help: "把当前选区收进笔记", systemImage: "quote.opening") {
                    appendSelectionAndOpenWriting()
                }
            )
        }
        items.append(
            ContextRailItem(title: "问题与结论", help: "整理问题、结论和缺少证据", systemImage: "checkmark.circle") {
                prepareAgentDraft("请根据\(store.agentPromptScope)，整理出问题、结论和还缺少的证据。")
            }
        )
        return items
    }

    private var writingDocumentRailItems: [ContextRailItem] {
        var items: [ContextRailItem] = []
        if let item = store.selectedMaterialItem {
            items.append(
                ContextRailItem(
                    title: item.title,
                    help: "切回沉浸阅读",
                    systemImage: item.kind.systemImage,
                    emphasized: true
                ) {
                    openReader()
                }
            )
        }
        if store.hasSelectedMaterial || store.selectionContext != nil {
            items.append(
                ContextRailItem(title: "引用", help: "复制当前材料或选区引用", systemImage: "quote.opening") {
                    store.copyCurrentReference()
                }
            )
        }
        items.append(
            ContextRailItem(title: "资料库", help: "打开资料库选择资料", systemImage: "sidebar.left", emphasized: items.isEmpty) {
                openLibrary()
            }
        )
        return items
    }

    private var writingAssistRailItems: [ContextRailItem] {
        [
            ContextRailItem(title: "大纲建议", help: "生成笔记大纲", systemImage: "list.bullet.rectangle", emphasized: true) {
                prepareAgentDraft("请根据\(store.agentPromptScope)，给出一版更清晰的笔记大纲。")
            },
            ContextRailItem(title: "补来源", help: "检查笔记缺少来源的位置", systemImage: "link") {
                prepareAgentDraft(store.hasSelectedMaterial ? "请检查当前笔记缺少来源的位置，并建议应该引用当前材料的哪些部分。" : "请检查当前笔记缺少来源的位置，并标出需要补证据的段落。")
            },
            ContextRailItem(title: "润色表达", help: "润色当前笔记", systemImage: "text.quote") {
                prepareAgentDraft("请整理和润色当前笔记，保留原意，并标出缺少来源的位置。")
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

    private func openLibrary() {
        withAnimation(WeiBeiMotion.layout) {
            store.revealLibrary()
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
        @ViewBuilder third: () -> Third
    ) {
        _firstSplit = firstSplit
        _secondSplit = secondSplit
        self.minFirst = minFirst
        self.minSecond = minSecond
        self.minThird = minThird
        self.first = first()
        self.second = second()
        self.third = third()
    }

    func makeCoordinator() -> NativeSplitCoordinator {
        NativeSplitCoordinator(kind: .three(first: $firstSplit, second: $secondSplit), minimums: [minFirst, minSecond, minThird])
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
    private var isDragging = false
    private var isApplyingStoredPositions = false
    private var lastAppliedWidth: CGFloat = 0
    private var saveWork: DispatchWorkItem?

    init(kind: Kind, minimums: [CGFloat]) {
        self.kind = kind
        self.minimums = minimums
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
        }
        splitView.onLayout = { [weak self] splitView in
            self?.applyStoredPositionsWhenNeeded(in: splitView)
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
