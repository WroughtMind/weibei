import SwiftUI
import WeiBeiCore

// MARK: - SettingsView
//
// Migrated out of WeiBeiApp.swift (see L1 in the settings diagnosis report):
// SettingsView is a large, self-contained surface with its own sidebar,
// detail switch, and shared primitives (settingsGroup / settingsRow /
// settingsPill / settingsNote / compactMenu / segmented / sectionTitle).
// Keeping it in the shared-core WeiBeiApp.swift meant every small settings
// change had to go through the shared-file occupancy process, which was the
// structural reason the prior 7 settings commits serialized instead of
// parallelizing. It now lives here; AgentSettingsView.swift /
// AgentModelPicker.swift remain `extension SettingsView` and are unaffected.

struct SettingsView: View {
    // Visible to `internal` so the Settings sub-views in Views/Settings/*.swift
    // (same-target extensions) can bind to them.
    @EnvironmentObject var store: WorkspaceStore
    @StateObject var oauthService = PiOAuthService.shared
    @State private var selectedSection: SettingsSection = .agent
    @FocusState var focusedField: Field?
    // Model picker state (AgentModelPicker extension).
    @State var spinAngle: Double = 0
    @State var showManualModelEntry = false
    // Profile inline-rename state (AgentSettingsView extension).
    @State var isRenamingActiveProfile = false
    @State var profileRenameDraft = ""
    // Profile delete confirmation (AgentSettingsView extension). The action is
    // destructive — it also wipes the profile's Keychain key — so it needs a
    // confirmation gate (see S3).
    @State var showDeleteProfileConfirmation = false

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
            // Overview tab removed (M1) — default to the Chat section, where the
            // highest-frequency settings (provider/key/model) live.
            selectedSection = .agent
            oauthService.refreshLinkedStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weiBeiPiOAuthDidSucceed)) { note in
            guard let raw = note.userInfo?["provider"] as? String,
                  let subscription = PiSubscriptionProvider(rawValue: raw) else { return }
            // After OAuth, point chat at the subscription provider + default model.
            store.setAgentAuthMethod(.subscription)
            store.setAgentProviderID(subscription.agentProviderID)
            store.updateModelName(subscription.defaultModel)
            if raw == "openai-codex" {
                // Pi expects provider id openai-codex for ChatGPT subscription tokens.
                store.updateModelName(subscription.defaultModel)
            }
            store.openAIKeyStatus = store.ui(
                "订阅已连接：\(subscription.label(language: store.interfaceLanguage))",
                "Subscription linked: \(subscription.label(language: store.interfaceLanguage))"
            )
        }
    }

    enum Field: Hashable {
        case apiKey
        case model
    }

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case appearance
        case reading
        case writing
        case agent
        case data
        case shortcuts

        var id: String { rawValue }

        var icon: String {
            switch self {
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
            // No whole-scroll animation on section change — that was thrashing settings UI.
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedSection {
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
            }
            .id(selectedSection)
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
        case .appearance:
            return store.ui("统一控制语言与主题。", "Control language and theme.")
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
            }

            settingsGroup(store.ui("工作区", "Workspace")) {
                settingsRow(
                    title: store.ui("布局说明", "Layout Notes"),
                    detail: store.ui("栏位用顶栏显隐与拖拽重排；沉浸阅读/对话/写作用 ⌥⌘R / ⌥⌘A / ⌥⌘N。设置页不再切换布局预设。", "Use top-bar pane toggles and drag-reorder for columns; immersive reading/chat/writing use ⌥⌘R / ⌥⌘A / ⌥⌘N. Settings no longer switches layout presets.")
                ) {
                    settingsPill(
                        title: store.layout.label(language: store.interfaceLanguage),
                        icon: "rectangle.split.3x1",
                        active: false
                    )
                }

                settingsRow(
                    title: store.ui("每日灵感", "Daily Inspiration"),
                    detail: store.ui("只控制空工作区里的出处内容；文稿、对话和笔记入口始终保留。", "Controls sourced material on the empty workspace only; document, chat, and notes entries always remain.")
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.showDailyInspiration },
                            set: { store.setDailyInspirationEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(WeiBeiTheme.cinnabar)
                    .accessibilityLabel(Text(store.ui("显示每日灵感", "Show Daily Inspiration")))
                }
            }
        }
    }

    private var readingSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("导入文稿", "Imported Documents")) {
                settingsRow(
                    title: store.ui("导入文稿适配", "Adapt Imported Documents"),
                    detail: store.ui("让 PDF/HTML 跟随魏碑纸面与墨石阅读环境。", "Let PDF/HTML follow WeiBei paper and inkstone reading.")
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.adaptImportedDocumentColors },
                            set: { store.setImportedDocumentColorAdaptation($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(Text(store.ui("导入文稿适配", "Adapt Imported Documents")))
                }
            }

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

            }
        }
    }

    private var writingSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("Markdown", "Markdown")) {
                settingsRow(
                    title: store.ui("笔记模式", "Note Mode"),
                    detail: store.ui("主模式是原地 Markdown 写作，源码只作为辅助检查。", "Live Markdown writing is primary; source is only for checking.")
                ) {
                    segmented(NoteRenderMode.visibleCases, active: store.noteRenderMode.visibleMode) { mode in
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

    /// 对话服务设置 — 实现在 Views/Settings/AgentSettingsView.swift 的 extension 中。
    /// 历史上这里是四个并列卡片（连接配置 / 接入方式 / 提供商与模型 / 对话入口），
    /// 现已重构为单条线性决策链（服务 → 认证 → 模型 → 状态），并把模型字段升级为
    /// 登录后实时拉取的下拉（见 AgentModelPicker.swift）。
    private var agentSettings: some View {
        agentSettingsContent()
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
            (store.ui("聚焦课程目录", "Focus Course Index"), "⌘1", store.ui("把键盘焦点交给课程目录。", "Move keyboard focus to the course index.")),
            (store.ui("聚焦阅读", "Focus Reader"), "⌘2", store.ui("把键盘焦点交给阅读区。", "Move keyboard focus to the reader.")),
            (store.ui("聚焦笔记", "Focus Notes"), "⌘3", store.ui("把键盘焦点交给笔记区。", "Move keyboard focus to notes.")),
            (store.ui("聚焦对话", "Focus Chat"), "⌘4", store.ui("把键盘焦点交给对话区。", "Move keyboard focus to chat.")),
            (store.ui("沉浸阅读", "Immersive Reading"), "⌥⌘R", store.ui("进入沉浸阅读布局。", "Enter immersive reading layout.")),
            (store.ui("沉浸对话", "Immersive Chat"), "⌥⌘A", store.ui("进入沉浸对话布局。", "Enter immersive conversation layout.")),
            (store.ui("沉浸写作", "Immersive Writing"), "⌥⌘N", store.ui("进入沉浸写作布局。", "Enter immersive writing layout.")),
            (store.ui("选区轻提示", "Selection Prompt"), "⌃⌥3", store.ui("在有选区时打开选区浮层。", "Open the selection float when a selection exists.")),
            (store.ui("隐藏对话浮层", "Hide Chat Overlay"), "⌃⌥0", store.ui("隐藏选区轻提示。", "Hide the selection prompt.")),
            (store.ui("明暗切换", "Toggle Theme"), "⌥⌘T", store.ui("在纸面和墨石之间切换。", "Switch between paper and inkstone.")),
            (store.ui("后退", "Back"), "⌘[", store.ui("回到上一个工作区位置。", "Go back in workspace history.")),
            (store.ui("前进", "Forward"), "⌘]", store.ui("前进到下一个工作区位置。", "Go forward in workspace history.")),
        ]
    }

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("课程资料", "Course Materials")) {
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

    /// Shared Settings card primitive (also used by `AgentSettingsView` extension).
    func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    /// Shared Settings row primitive (title + detail + trailing control).
    func settingsRow<Control: View>(title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .lineSpacing(2)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    /// Shared Settings inline note (icon + secondary text).
    func settingsNote(_ text: String, icon: String) -> some View {
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

    /// Shared Settings pill (icon + label chip).
    func settingsPill(title: String, icon: String, active: Bool) -> some View {
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

    /// Shared compact dropdown menu used across Settings.
    func compactMenu<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    /// Shared Settings group title label.
    func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 12, weight: .semibold))
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
    }
}
