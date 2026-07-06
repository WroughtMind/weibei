import AppKit
import SwiftUI
import WeiBeiCore

@MainActor private let sharedWorkspaceStore = WorkspaceStore()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        WeiBeiTypography.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        if shouldActivateOnLaunch {
            NSApp.activate(ignoringOtherApps: true)
        }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            sharedWorkspaceStore.handleAppShortcut(event) ? nil : event
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if shouldActivateOnLaunch {
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }

    private var shouldActivateOnLaunch: Bool {
        ProcessInfo.processInfo.environment["WEIBEI_SUPPRESS_ACTIVATION"] != "1"
    }
}

@main
struct WeiBeiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = sharedWorkspaceStore

    init() {
        WeiBeiTypography.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("魏碑", id: "main") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.appearanceMode.colorScheme)
                .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
                .background(WindowChromeConfigurator(appearanceMode: store.appearanceMode))
                .onOpenURL { url in
                    store.importFiles([url])
                }
                .onAppear {
                    Task { await store.runVerificationScenarioIfNeeded() }
                }
                .frame(minWidth: 1120, minHeight: 720)
                .ignoresSafeArea(.container, edges: .top)
        }
        .defaultSize(width: 1240, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu(store.appDisplayName) {
                Button(store.ui("打开资料", "Open Material")) { store.importFilesFromPanel() }
                    .keyboardShortcut("o")

                Button(store.ui("新建空白笔记", "New Blank Note")) { animateLayout { store.promptCreateBlankNotebookNote() } }
                    .keyboardShortcut("n")
                if store.hasSelectedMaterial {
                    Button(store.ui("从当前资料开笔记", "Note from Current Material")) {
                        animateLayout { store.promptCreateNotebookNoteFromCurrentMaterial() }
                    }
                }

                Divider()

                Button(store.ui("聚焦课程目录", "Focus Course Index")) { animateLayout { store.focus(.library) } }
                    .keyboardShortcut("1")
                Button(store.ui("聚焦阅读", "Focus Reader")) { animateLayout { store.focus(.reader) } }
                    .keyboardShortcut("2")
                Button(store.ui("聚焦笔记", "Focus Notes")) { animateLayout { store.focus(.notes) } }
                    .keyboardShortcut("3")
                Button(store.ui("聚焦对话", "Focus Chat")) { animateLayout { store.focus(.agent) } }
                    .keyboardShortcut("4")

                Divider()

                Button(store.ui("上一份资料", "Previous Material")) { animateLayout { store.selectAdjacentItem(step: -1) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button(store.ui("下一份资料", "Next Material")) { animateLayout { store.selectAdjacentItem(step: 1) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Divider()

                Button(store.showLibrary ? store.ui("收起课程目录", "Hide Course Index") : store.ui("打开课程目录", "Show Course Index")) {
                    animateLayout {
                        store.toggleLibrary()
                    }
                }
                    .keyboardShortcut("b")
                if store.layout.hasCollapsibleRightPane {
                    Button(store.showRightPane ? store.ui("收起辅助栏", "Hide Assistant Pane") : store.ui("展开辅助栏", "Show Assistant Pane")) {
                        animateLayout {
                            store.toggleRightPane()
                        }
                    }
                    .keyboardShortcut("j")
                }

                Divider()

                Button(WorkspaceLayout.documentAgentNotes.label(language: store.interfaceLanguage)) { setLayout(.documentAgentNotes) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button(WorkspaceLayout.documentNotesAgent.label(language: store.interfaceLanguage)) { setLayout(.documentNotesAgent) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button(WorkspaceLayout.documentNotesSplit.label(language: store.interfaceLanguage)) { setLayout(.documentNotesSplit) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button(WorkspaceLayout.immersiveReading.label(language: store.interfaceLanguage)) { setLayout(.immersiveReading) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button(WorkspaceLayout.immersiveConversation.label(language: store.interfaceLanguage)) { setLayout(.immersiveConversation) }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                Button(WorkspaceLayout.immersiveWriting.label(language: store.interfaceLanguage)) { setLayout(.immersiveWriting) }
                    .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button(store.appearanceMode.actionLabel(language: store.interfaceLanguage)) {
                    animateAppearance {
                        store.toggleAppearanceMode()
                    }
                }
                    .keyboardShortcut("t", modifiers: [.command, .option])

                Divider()

                Button(AgentSurface.bottomDrawer.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.bottomDrawer) }
                    .keyboardShortcut("1", modifiers: [.control, .option])
                Button(AgentSurface.cornerPanel.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.cornerPanel) }
                    .keyboardShortcut("2", modifiers: [.control, .option])
                if store.canUseSelectionAgentSurface {
                    Button(AgentSurface.selectionFloat.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.selectionFloat) }
                        .keyboardShortcut("3", modifiers: [.control, .option])
                }
                Button(AgentSurface.quietInsight.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.quietInsight) }
                    .keyboardShortcut("4", modifiers: [.control, .option])
                Button(AgentSurface.hidden.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.hidden) }
                    .keyboardShortcut("0", modifiers: [.control, .option])

                Divider()

                Button(store.ui("笔记原地写作", "Live Markdown Writing")) { setNoteRenderMode(.rich) }
                    .keyboardShortcut("1", modifiers: [.control, .command])
                Button(store.ui("笔记源码对照", "Source Compare")) { setNoteRenderMode(.split) }
                    .keyboardShortcut("2", modifiers: [.control, .command])
                Button(store.ui("笔记源码", "Note Source")) { setNoteRenderMode(.source) }
                    .keyboardShortcut("3", modifiers: [.control, .command])
                Button(store.ui("笔记预览", "Note Preview")) { setNoteRenderMode(.preview) }
                    .keyboardShortcut("4", modifiers: [.control, .command])

                if store.canApplyAgentAnswer {
                    Divider()

                    Button(store.ui("写入回答到笔记", "Write Answer to Note")) { animatePanel { store.applyLastAgentAnswerToNote() } }
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                    if store.canReplaceNoteSelection {
                        Button(store.ui("替换笔记选区", "Replace Note Selection")) { animatePanel { store.replaceSelectionWithLastAgentAnswer() } }
                            .keyboardShortcut("r", modifiers: [.command, .shift])
                    }
                    Button(store.ui("追加整理建议", "Append Organization Suggestion")) { animatePanel { store.applyAgentPatchToEditor() } }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                }

                Divider()

                Button(store.ui("命令面板", "Command Palette")) {
                    animatePanel {
                        store.commandPalettePresented.toggle()
                    }
                }
                    .keyboardShortcut("k")

                Divider()

                if store.canCopyReference {
                    Button(store.copyReferenceActionTitle) { store.copyCurrentReference() }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                if store.hasSelectedMaterial {
                    Button(store.ui("打开资料内搜索", "Search in Material")) {
                        animatePanel {
                            store.revealReaderSearch()
                        }
                    }
                    .keyboardShortcut("f")
                }
                if !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(store.sendAgentActionTitle) { Task { await store.askAgent() } }
                        .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }

    private func animateLayout(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.layout) {
            action()
        }
    }

    private func animatePanel(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.panel) {
            action()
        }
    }

    private func animateAppearance(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.appearance) {
            action()
        }
    }

    private func setLayout(_ layout: WorkspaceLayout) {
        animateLayout {
            store.setLayout(layout)
        }
    }

    private func setAgentSurface(_ surface: AgentSurface) {
        animatePanel {
            store.setAgentSurface(surface)
        }
    }

    private func setNoteRenderMode(_ mode: NoteRenderMode) {
        animatePanel {
            store.setNoteRenderMode(mode)
        }
    }
}

private struct WeiBeiAppearanceTransition: ViewModifier {
    var mode: WeiBeiAppearanceMode
    @State private var washOpacity = 0.0
    @State private var washColor = Color.clear

    func body(content: Content) -> some View {
        content
            .animation(WeiBeiMotion.appearance, value: mode)
            .overlay {
                washColor
                    .opacity(washOpacity)
                    .allowsHitTesting(false)
            }
            .onChange(of: mode) { oldMode, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    washColor = Color(nsColor: oldMode.windowBackground)
                    washOpacity = 0.36
                }
                DispatchQueue.main.async {
                    withAnimation(WeiBeiMotion.appearance) {
                        washOpacity = 0
                    }
                }
            }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    var appearanceMode: WeiBeiAppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(view.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = true
        window.backgroundColor = appearanceMode.windowBackground
        window.isMovableByWindowBackground = true
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedSection: SettingsSection = .overview
    @FocusState private var focusedField: Field?

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
                .overlay(WeiBeiTheme.hairline.opacity(0.55))
            settingsDetail
        }
        .frame(width: 860, height: 610)
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
        .onAppear {
            selectedSection = .overview
        }
    }

    private enum Field: Hashable {
        case apiKey
        case model
    }

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case overview
        case appearance
        case reading
        case writing
        case agent
        case data
        case shortcuts

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "seal"
            case .appearance: return "slider.horizontal.3"
            case .reading: return "book.pages"
            case .writing: return "square.and.pencil"
            case .agent: return "text.bubble"
            case .data: return "folder"
            case .shortcuts: return "command"
            }
        }

        var code: String {
            switch self {
            case .overview: return "HOME"
            case .appearance: return "LOOK"
            case .reading: return "READ"
            case .writing: return "NOTE"
            case .agent: return "CHAT"
            case .data: return "DATA"
            case .shortcuts: return "KEYS"
            }
        }

        @MainActor
        func title(_ store: WorkspaceStore) -> String {
            switch self {
            case .overview: return store.ui("总览", "Overview")
            case .appearance: return store.ui("外观", "Appearance")
            case .reading: return store.ui("阅读", "Reading")
            case .writing: return store.ui("写作", "Writing")
            case .agent: return store.ui("对话", "Chat")
            case .data: return store.ui("资料与数据", "Library & Data")
            case .shortcuts: return store.ui("快捷键", "Shortcuts")
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.ui("设置", "Settings"))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 28, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.brandLatinName)
                        .font(WeiBeiTypography.englishBrandFont(size: 18, weight: .semibold))
                    Text("SETTINGS")
                        .font(WeiBeiTypography.englishBrandFont(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.82))
                }
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.90))
                Text(store.ui("管理魏碑的界面、写作、对话和本地资料。", "Manage WeiBei interface, writing, chat, and local library."))
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)

            VStack(spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    settingsSidebarButton(section)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                settingsPill(
                    title: store.interfaceLanguage.settingsLabel,
                    icon: "character.book.closed",
                    active: false
                )
                settingsPill(
                    title: store.appearanceMode.label(language: store.interfaceLanguage),
                    icon: store.appearanceMode.systemImage,
                    active: false
                )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .frame(width: 218)
        .background {
            ZStack(alignment: .top) {
                WeiBeiTheme.paperInset.opacity(store.appearanceMode == .inkstone ? 0.62 : 0.80)
                LinearGradient(
                    colors: [
                        WeiBeiTheme.glassHighlight.opacity(store.appearanceMode == .inkstone ? 0.09 : 0.20),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
            }
        }
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            settingsHeader
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedSection {
                    case .overview:
                        overviewSettings
                    case .appearance:
                        appearanceSettings
                    case .reading:
                        readingSettings
                    case .writing:
                        writingSettings
                    case .agent:
                        agentSettings
                    case .data:
                        dataSettings
                    case .shortcuts:
                        shortcutSettings
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 34)
                .animation(WeiBeiMotion.panel, value: selectedSection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
    }

    private var settingsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSection.title(store))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 24, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(sectionSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            Spacer()
            settingsAppearanceToggleButton
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background {
            ZStack(alignment: .bottom) {
                WeiBeiGlassHeaderBackground(paperOpacity: 0.66, materialOpacity: 0.10)
                WeiBeiHeaderHandoffFade(height: 12, opacity: 0.22)
            }
        }
    }

    private var settingsAppearanceToggleButton: some View {
        Button {
            withAnimation(WeiBeiMotion.appearance) {
                store.toggleAppearanceMode()
            }
        } label: {
            Image(systemName: store.appearanceMode.toggled.systemImage)
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 30))
        .accessibilityLabel(Text(store.appearanceMode.actionLabel(language: store.interfaceLanguage)))
        .help(store.appearanceMode.actionLabel(language: store.interfaceLanguage))
    }

    private var sectionSubtitle: String {
        switch selectedSection {
        case .overview:
            return store.ui("先看当前状态，再进入具体设置。", "Start with the current state, then drill into details.")
        case .appearance:
            return store.ui("统一控制语言、主题、顶部栏和工作区布局。", "Control language, theme, top bar, and workspace layout.")
        case .reading:
            return store.ui("阅读设置只放当前已经接入真实行为的开关。", "Reading settings only expose behavior that is already wired.")
        case .writing:
            return store.ui("设置 Markdown 写作形态和笔记默认视图。", "Set Markdown writing behavior and the default note view.")
        case .agent:
            return store.ui("管理对话、上下文、密钥和默认入口。", "Manage chat, context, API key, and the default entry.")
        case .data:
            return store.ui("管理资料导入、笔记和本地数据入口。", "Manage material import, notes, and local data entry points.")
        case .shortcuts:
            return store.ui("查看当前全键盘交互入口。", "Review the current keyboard workflow.")
        }
    }

    private var overviewSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("当前工作台", "Current Workspace")) {
                settingsRow(
                    title: store.ui("资料", "Material"),
                    detail: store.selectedMaterialItem.map(store.displayTitle) ?? store.ui("还没有打开资料。", "No material is open.")
                ) {
                    settingsPill(
                        title: store.selectedMaterialItem?.kind.label(language: store.interfaceLanguage) ?? store.ui("无", "None"),
                        icon: store.selectedMaterialItem?.kind.systemImage ?? "tray",
                        active: store.selectedMaterialItem != nil
                    )
                }

                settingsRow(
                    title: store.ui("笔记", "Note"),
                    detail: store.selectedItem.map(store.displayTitle) ?? store.ui("当前是新笔记。", "The current note is new.")
                ) {
                    settingsPill(title: store.noteRenderMode.label(language: store.interfaceLanguage), icon: "square.and.pencil", active: true)
                }

                settingsRow(
                    title: store.ui("对话上下文", "Chat Context"),
                    detail: store.hasSelectionAttachments ? store.ui("已选文本片段会作为对话上下文。", "Selected fragments will be used as chat context.") : store.ui("未附加选区，将读取当前资料和笔记。", "No selection is attached; the current material and note will be used.")
                ) {
                    settingsPill(
                        title: store.hasSelectionAttachments ? store.ui("\(store.selectionAttachments.count) 个片段", "\(store.selectionAttachments.count) fragments") : store.ui("默认上下文", "Default"),
                        icon: "text.bubble",
                        active: store.hasSelectionAttachments
                    )
                }
            }

            settingsGroup(store.ui("快速进入", "Jump To")) {
                settingsRouteRow(
                    title: store.ui("外观与语言", "Appearance & Language"),
                    detail: store.ui("字体、明暗模式、顶部栏、布局。", "Fonts, theme mode, top bar, and layout."),
                    target: .appearance
                )
                settingsRouteRow(
                    title: store.ui("对话设置", "Chat Settings"),
                    detail: store.ui("密钥、模型、显示形态和选区上下文。", "Key, model, surface, and selection context."),
                    target: .agent
                )
                settingsRouteRow(
                    title: store.ui("资料与笔记", "Library & Notes"),
                    detail: store.ui("导入资料、当前资料、当前笔记。", "Import, current material, and current note."),
                    target: .data
                )
            }
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("语言", "Language")) {
                settingsRow(
                    title: store.ui("界面语言", "Interface Language"),
                    detail: store.ui("切换后菜单、按钮、状态提示和内置样例标题会同步更新。", "Menus, buttons, status hints, and built-in sample titles update together.")
                ) {
                    segmented(WeiBeiInterfaceLanguage.allCases, active: store.interfaceLanguage) { language in
                        language.settingsLabel
                    } action: { language in
                        withAnimation(WeiBeiMotion.appearance) {
                            store.setInterfaceLanguage(language)
                        }
                    }
                }
            }

            settingsGroup(store.ui("外观", "Appearance")) {
                settingsRow(
                    title: store.ui("明暗模式", "Theme Mode"),
                    detail: store.ui("亮色偏宣纸，暗色偏墨石；切换时保留柔和过渡。", "Light mode leans warm paper; dark mode leans inkstone, with a soft transition.")
                ) {
                    segmented(WeiBeiAppearanceMode.allCases, active: store.appearanceMode) { mode in
                        mode.label(language: store.interfaceLanguage)
                    } action: { mode in
                        withAnimation(WeiBeiMotion.appearance) {
                            store.setAppearanceMode(mode)
                        }
                    }
                }

                settingsRow(
                    title: store.ui("顶部栏样式", "Top Bar Style"),
                    detail: store.ui("这些方案会直接影响主窗口顶部栏，不做未接入的假预览。", "These variants directly change the main window top bar; no fake previews.")
                ) {
                    compactMenu(store.topBarVariant.label(language: store.interfaceLanguage)) {
                        ForEach(TopBarVariant.allCases) { variant in
                            Button(variant.label(language: store.interfaceLanguage)) {
                                withAnimation(WeiBeiMotion.appearance) {
                                    store.setTopBarVariant(variant)
                                }
                            }
                        }
                    }
                }
            }

            settingsGroup(store.ui("工作区", "Workspace")) {
                settingsRow(
                    title: store.ui("当前布局", "Current Layout"),
                    detail: store.ui("设置会立即作用到主窗口，方便检查真实效果。", "Changes apply to the main window immediately for real inspection.")
                ) {
                    compactMenu(store.layout.label(language: store.interfaceLanguage)) {
                        ForEach(WorkspaceLayout.allCases) { layout in
                            Button(layout.label(language: store.interfaceLanguage)) {
                                withAnimation(WeiBeiMotion.layout) {
                                    store.setLayout(layout)
                                }
                            }
                        }
                    }
                }

                settingsRow(
                    title: store.ui("课程目录", "Course Index"),
                    detail: store.ui("沉浸模式也保留课程目录入口，便于随时换材料。", "Immersive modes keep the course index entry so you can switch material anytime.")
                ) {
                    Button(store.showLibrary ? store.ui("收起", "Hide") : store.ui("打开", "Show")) {
                        withAnimation(WeiBeiMotion.layout) {
                            store.toggleLibrary()
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: store.showLibrary))
                }
            }
        }
    }

    private var readingSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("阅读入口", "Reader Entry")) {
                settingsRow(
                    title: store.ui("资料内搜索", "Search in Material"),
                    detail: store.ui("打开当前材料搜索框；没有资料时不会显示无效入口。", "Opens search for the current material; unavailable entries stay hidden.")
                ) {
                    if store.hasSelectedMaterial {
                        Button(store.ui("打开搜索", "Open Search")) {
                            withAnimation(WeiBeiMotion.panel) {
                                store.revealReaderSearch()
                            }
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: store.showReaderSearch))
                    } else {
                        Text(store.ui("未选择资料", "No material selected"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                }

                settingsRow(
                    title: store.ui("当前阅读位置", "Current Reader Position"),
                    detail: store.currentReferenceTitle
                ) {
                    Text(store.hasSelectedMaterial ? store.ui("可引用", "Reference ready") : store.ui("等待资料", "Waiting"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(store.hasSelectedMaterial ? WeiBeiTheme.link : WeiBeiTheme.tertiaryInk)
                }
            }

            settingsGroup(store.ui("选区", "Selection")) {
                settingsRow(
                    title: store.ui("选区入口", "Selection Entry"),
                    detail: store.ui("当前选区会进入对话补丁组件；正文输入框保持干净。", "Selections attach as context chips so the composer stays clean.")
                ) {
                    settingsPill(
                        title: store.hasSelectionAttachments ? store.ui("\(store.selectionAttachments.count) 个片段", "\(store.selectionAttachments.count) fragments") : store.ui("无片段", "None"),
                        icon: "text.bubble",
                        active: store.hasSelectionAttachments
                    )
                }

                settingsRow(
                    title: store.ui("页边洞察", "Margin Insight"),
                    detail: store.ui("把对话能力作为低干扰阅读线索，而不是大弹窗。", "Uses low-distraction reading clues instead of large popovers.")
                ) {
                    Button(AgentSurface.quietInsight.label(language: store.interfaceLanguage)) {
                        withAnimation(WeiBeiMotion.panel) {
                            store.setAgentSurface(.quietInsight)
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: store.agentSurface == .quietInsight))
                }
            }
        }
    }

    private var writingSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("Markdown", "Markdown")) {
                settingsRow(
                    title: store.ui("笔记模式", "Note Mode"),
                    detail: store.ui("主模式是原地 Markdown 写作，源码和预览作为辅助。", "Live Markdown writing is primary; source and preview stay available as aids.")
                ) {
                    segmented(NoteRenderMode.allCases, active: store.noteRenderMode) { mode in
                        mode.label(language: store.interfaceLanguage)
                    } action: { mode in
                        withAnimation(WeiBeiMotion.panel) {
                            store.setNoteRenderMode(mode)
                        }
                    }
                }

                settingsRow(
                    title: store.ui("新建笔记", "New Note"),
                    detail: store.ui("空白笔记和资料笔记分开创建，避免误改当前材料或当前笔记。", "Create blank notes and material-based notes separately to avoid changing the current material or note by accident.")
                ) {
                    HStack(spacing: 8) {
                        Button(store.ui("空白", "Blank")) {
                            withAnimation(WeiBeiMotion.panel) {
                                store.promptCreateBlankNotebookNote()
                            }
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())

                        if store.hasSelectedMaterial {
                            Button(store.ui("当前资料", "Current Material")) {
                                withAnimation(WeiBeiMotion.panel) {
                                    store.promptCreateNotebookNoteFromCurrentMaterial()
                                }
                            }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                    }
                }

                if store.canUseSelectedMarkdownAsNotebookNote {
                    settingsRow(
                        title: store.ui("Markdown 资料", "Markdown Material"),
                        detail: store.ui("把当前 Markdown 文件移到笔记区原地编辑。", "Move the current Markdown file into the note editor.")
                    ) {
                        Button(store.ui("作为笔记编辑", "Edit as Note")) {
                            store.useSelectedMarkdownAsNotebookNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                }
            }

            settingsGroup(store.ui("编辑器外观", "Editor Appearance")) {
                settingsRow(
                    title: store.ui("编辑器主题", "Editor Theme"),
                    detail: store.ui("当前跟随魏碑全局外观，覆盖背景、正文、标题、代码、公式、Callout 和选区。", "Currently follows WeiBei appearance across background, text, headings, code, math, callouts, and selection.")
                ) {
                    settingsPill(title: store.appearanceMode.label(language: store.interfaceLanguage), icon: store.appearanceMode.systemImage, active: true)
                }
            }
        }
    }

    private var agentSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("密钥与模型", "Key & Model")) {
                settingsRow(
                    title: store.ui("对话密钥", "Chat API Key"),
                    detail: store.openAIKeyHelpText
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        SecureField(
                            "",
                            text: $store.openAIAPIKey,
                            prompt: Text(store.ui("对话密钥", "Chat API key"))
                                .font(.system(size: 13))
                                .foregroundStyle(WeiBeiTheme.placeholderInk)
                        )
                        .textFieldStyle(.plain)
                        .foregroundColor(WeiBeiTheme.ink)
                        .focused($focusedField, equals: .apiKey)
                        .font(.system(size: 13))
                        .weibeiInputSurface(active: focusedField == .apiKey, height: 38)
                        .frame(width: 250)

                        HStack(spacing: 8) {
                            Button(store.ui("保存", "Save")) { store.saveOpenAIAPIKey() }
                                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                            Button(store.ui("清除", "Clear")) { store.clearOpenAIAPIKey() }
                                .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                    }
                }

                if let status = store.openAIKeyStatus {
                    settingsNote(status, icon: "checkmark.seal")
                }

                settingsRow(
                    title: store.ui("模型", "Model"),
                    detail: store.ui("本机环境里的模型设置会覆盖这里。", "The model configured in your local environment overrides this field.")
                ) {
                    TextField(
                        "",
                        text: Binding(
                            get: { store.modelName },
                            set: { store.updateModelName($0) }
                        ),
                        prompt: Text(store.ui("模型", "Model"))
                            .font(.system(size: 13))
                            .foregroundStyle(WeiBeiTheme.placeholderInk)
                    )
                    .textFieldStyle(.plain)
                    .foregroundColor(WeiBeiTheme.ink)
                    .focused($focusedField, equals: .model)
                    .font(.system(size: 13))
                    .weibeiInputSurface(active: focusedField == .model, height: 38)
                    .frame(width: 250)
                }
            }

            settingsGroup(store.ui("对话形态", "Chat Surface")) {
                settingsRow(
                    title: store.ui("默认显示", "Default Surface"),
                    detail: store.ui("完整对话区保留，小选区浮层只作为临时入口。", "The full chat area stays; the selection layer is only a temporary entry.")
                ) {
                    compactMenu(store.agentSurface.label(language: store.interfaceLanguage)) {
                        ForEach(AgentSurface.allCases) { surface in
                            if surface != .selectionFloat || store.canUseSelectionAgentSurface {
                                Button(surface.label(language: store.interfaceLanguage)) {
                                    withAnimation(WeiBeiMotion.panel) {
                                        store.setAgentSurface(surface)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var shortcutSettings: some View {
        settingsGroup(store.ui("当前快捷键", "Current Shortcuts")) {
            ForEach(shortcutRows, id: \.0) { title, shortcut, detail in
                settingsRow(title: title, detail: detail) {
                    Text(shortcut)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(WeiBeiTheme.paperRaised.opacity(0.52))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
                        }
                }
            }
        }
    }

    private var shortcutRows: [(String, String, String)] {
        [
            (store.ui("命令面板", "Command Palette"), "⌘K", store.ui("搜索并执行魏碑动作。", "Search and run WeiBei actions.")),
            (store.ui("课程目录", "Course Index"), "⌘B", store.ui("打开或收起课程目录。", "Show or hide the course index.")),
            (store.ui("资料内搜索", "Search in Material"), "⌘F", store.ui("搜索当前打开的资料。", "Search the current material.")),
            (store.ui("聚焦阅读", "Focus Reader"), "⌘2", store.ui("把键盘焦点交给阅读区。", "Move keyboard focus to the reader.")),
            (store.ui("聚焦笔记", "Focus Notes"), "⌘3", store.ui("把键盘焦点交给笔记区。", "Move keyboard focus to notes.")),
            (store.ui("聚焦对话", "Focus Chat"), "⌘4", store.ui("把键盘焦点交给对话区。", "Move keyboard focus to chat.")),
            (store.ui("明暗切换", "Toggle Theme"), "⌥⌘T", store.ui("在纸面和墨石之间切换。", "Switch between paper and inkstone."))
        ]
    }

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("课程目录", "Course Index")) {
                settingsRow(
                    title: store.ui("导入资料", "Import Material"),
                    detail: store.ui("导入 HTML、PDF、Markdown 或文本文件。", "Import HTML, PDF, Markdown, or text files.")
                ) {
                    Button(store.ui("导入", "Import")) {
                        store.importFilesFromPanel()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }

                settingsRow(
                    title: store.ui("当前资料", "Current Material"),
                    detail: store.selectedMaterialItem.map(store.displayTitle) ?? store.ui("未选择资料", "No material selected")
                ) {
                    settingsPill(
                        title: store.selectedMaterialItem?.kind.label(language: store.interfaceLanguage) ?? store.ui("无", "None"),
                        icon: store.selectedMaterialItem?.kind.systemImage ?? "tray",
                        active: store.selectedMaterialItem != nil
                    )
                }
            }

            settingsGroup(store.ui("笔记", "Notes")) {
                settingsRow(
                    title: store.ui("当前笔记", "Current Note"),
                    detail: store.selectedItem.map(store.displayTitle) ?? store.ui("新笔记", "New Note")
                ) {
                    settingsPill(title: store.noteRenderMode.label(language: store.interfaceLanguage), icon: "square.and.pencil", active: true)
                }

                settingsRow(
                    title: store.ui("选区上下文", "Selection Context"),
                    detail: store.ui("已选文本片段只作为上下文传给对话，不塞进输入框正文。", "Selected fragments are passed as context, not inserted into the composer text.")
                ) {
                    if store.hasSelectionAttachments {
                        Button(store.ui("清空片段", "Clear Fragments")) {
                            store.clearSelectionAttachments()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    } else {
                        Text(store.ui("无片段", "None"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                }
            }
        }
    }

    private func settingsRouteRow(title: String, detail: String, target: SettingsSection) -> some View {
        settingsRow(title: title, detail: detail) {
            Button {
                withAnimation(WeiBeiMotion.panel) {
                    selectedSection = target
                }
            } label: {
                HStack(spacing: 7) {
                    Text(target.code)
                        .font(WeiBeiTypography.englishBrandFont(size: 9, weight: .semibold))
                        .tracking(0.9)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
        }
    }

    private func settingsSidebarButton(_ section: SettingsSection) -> some View {
        let active = selectedSection == section
        return Button {
            withAnimation(WeiBeiMotion.panel) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(section.title(store))
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                Spacer()
                Text(section.code)
                    .font(WeiBeiTypography.englishBrandFont(size: 8.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(active ? WeiBeiTheme.cinnabar.opacity(0.82) : WeiBeiTheme.tertiaryInk.opacity(0.72))
            }
            .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(active ? WeiBeiTheme.paperRaised.opacity(0.62) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(active ? WeiBeiTheme.cinnabar.opacity(0.82) : .clear)
                    .frame(width: 2, height: 16)
                    .padding(.leading, 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(section.title(store)))
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(WeiBeiTheme.paperRaised.opacity(store.appearanceMode == .inkstone ? 0.20 : 0.36))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
            }
        }
    }

    private func settingsRow<Control: View>(title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(detail)
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 18)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.28))
                .frame(height: 1)
                .padding(.leading, 14)
        }
    }

    private func settingsNote(_ text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.link)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsPill(title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.tertiaryInk)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(active ? WeiBeiTheme.paperRaised.opacity(0.54) : WeiBeiTheme.paperInset.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(active ? 0.46 : 0.24), lineWidth: 1)
        }
    }

    private func segmented<Item: Identifiable & Hashable>(
        _ items: [Item],
        active: Item,
        label: @escaping (Item) -> String,
        action: @escaping (Item) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            ForEach(items) { item in
                Button(label(item)) {
                    action(item)
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: item == active))
            }
        }
    }

    private func compactMenu<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(WeiBeiTheme.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(WeiBeiTheme.paperRaised.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 12, weight: .semibold))
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
    }
}
