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
    // destructive — it also wipes the profile's stored API key — so it needs a
    // confirmation gate (see S3).
    @State var showDeleteProfileConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
                .overlay(WeiBeiTheme.hairline.opacity(0.55))
            settingsDetail
        }
        // L4: fixed size was too tight once the chat card grew; keep a stable
        // default floor but allow vertical stretch (and modest horizontal).
        .frame(minWidth: 860, minHeight: 610)
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
            Text(store.ui("设置", "Settings"))
                .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 28, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
                .padding(.horizontal, 22)
                .padding(.top, 24)

            VStack(spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    settingsSidebarButton(section)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Glanceable current language / theme — tappable so they jump to Appearance.
            VStack(alignment: .leading, spacing: 9) {
                Button {
                    withAnimation(WeiBeiMotion.panel) { selectedSection = .appearance }
                } label: {
                    settingsPill(
                        title: store.interfaceLanguage.settingsLabel,
                        icon: "character.book.closed",
                        active: false
                    )
                }
                .buttonStyle(.plain)
                .help(store.ui("前往外观设置", "Go to Appearance"))

                Button {
                    withAnimation(WeiBeiMotion.panel) { selectedSection = .appearance }
                } label: {
                    settingsPill(
                        title: store.appearanceMode.label(language: store.interfaceLanguage),
                        icon: store.appearanceMode.systemImage,
                        active: false
                    )
                }
                .buttonStyle(.plain)
                .help(store.ui("前往外观设置", "Go to Appearance"))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .frame(width: 218)
        .background {
            ZStack(alignment: .top) {
                WeiBeiTheme.paperInset.opacity(store.appearanceMode.isDark ? 0.62 : 0.80)
                LinearGradient(
                    colors: [
                        WeiBeiTheme.glassHighlight.opacity(store.appearanceMode.isDark ? 0.09 : 0.20),
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
        HStack(alignment: .center) {
            Text(selectedSection.title(store))
                .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 24, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
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
        // Same paper-swatch palette as the main top bar.
        AppearanceThemePaletteButton()
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("语言", "Language")) {
                settingsRow(title: store.ui("界面语言", "Interface Language")) {
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
                settingsRow(title: store.ui("主题", "Theme")) {
                    // Four themes — 2×2 chips. Top bar menu is the fast path; this is the full chooser.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .trailing, spacing: 6) {
                        ForEach(WeiBeiAppearanceMode.allCases) { mode in
                            Button {
                                store.setAppearanceMode(mode)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.systemImage)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(mode.label(language: store.interfaceLanguage))
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(mode == store.appearanceMode ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(mode == store.appearanceMode
                                              ? WeiBeiTheme.paperRaised.opacity(0.72)
                                              : WeiBeiTheme.paperInset.opacity(0.40))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(
                                            mode == store.appearanceMode
                                                ? WeiBeiTheme.cinnabar.opacity(0.55)
                                                : WeiBeiTheme.hairline.opacity(0.36),
                                            lineWidth: 1
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                            .help(mode.detail(language: store.interfaceLanguage))
                        }
                    }
                    .frame(width: 280)
                }
            }

            settingsGroup(store.ui("工作区", "Workspace")) {
                settingsRow(title: store.ui("每日灵感", "Daily Inspiration")) {
                    settingsSwitch(
                        isOn: Binding(
                            get: { store.showDailyInspiration },
                            set: { store.setDailyInspirationEnabled($0) }
                        ),
                        accessibilityLabel: store.ui("显示每日灵感", "Show Daily Inspiration")
                    )
                }
            }
        }
    }

    private var readingSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("导入文稿", "Imported Documents")) {
                settingsRow(title: store.ui("导入文稿适配", "Adapt Imported Documents")) {
                    settingsSwitch(
                        isOn: Binding(
                            get: { store.adaptImportedDocumentColors },
                            set: { store.setImportedDocumentColorAdaptation($0) }
                        ),
                        accessibilityLabel: store.ui("导入文稿适配", "Adapt Imported Documents")
                    )
                }
            }

            settingsGroup(store.ui("阅读入口", "Reader Entry")) {
                settingsRow(title: store.ui("资料内搜索", "Search in Material")) {
                    if store.hasSelectedMaterial {
                        Button(store.ui("打开搜索", "Open Search")) {
                            withAnimation(WeiBeiMotion.panel) {
                                store.revealReaderSearch()
                            }
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: store.showReaderSearch))
                    } else {
                        Text(store.ui("未选择资料", "No material selected"))
                            .font(SettingsType.control)
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                }
            }
        }
    }

    private var writingSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("Markdown", "Markdown")) {
                settingsRow(title: store.ui("笔记模式", "Note Mode")) {
                    segmented(NoteRenderMode.visibleCases, active: store.noteRenderMode.visibleMode) { mode in
                        mode.label(language: store.interfaceLanguage)
                    } action: { mode in
                        withAnimation(WeiBeiMotion.panel) {
                            store.setNoteRenderMode(mode)
                        }
                    }
                }

                settingsRow(title: store.ui("新建笔记", "New Note")) {
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
                    settingsRow(title: store.ui("Markdown 资料", "Markdown Material")) {
                        Button(store.ui("作为笔记编辑", "Edit as Note")) {
                            store.useSelectedMarkdownAsNotebookNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
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
            ForEach(shortcutRows, id: \.0) { title, shortcut in
                settingsRow(title: title) {
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

    private var shortcutRows: [(String, String)] {
        [
            (store.ui("命令面板", "Command Palette"), "⌘K"),
            (store.ui("课程目录", "Course Index"), "⌘B"),
            (store.ui("资料内搜索", "Search in Material"), "⌘F"),
            (store.ui("聚焦课程目录", "Focus Course Index"), "⌘1"),
            (store.ui("聚焦阅读", "Focus Reader"), "⌘2"),
            (store.ui("聚焦笔记", "Focus Notes"), "⌘3"),
            (store.ui("聚焦对话", "Focus Chat"), "⌘4"),
            (store.ui("沉浸阅读", "Immersive Reading"), "⌥⌘R"),
            (store.ui("沉浸对话", "Immersive Chat"), "⌥⌘A"),
            (store.ui("沉浸写作", "Immersive Writing"), "⌥⌘N"),
            (store.ui("选区轻提示", "Selection Prompt"), "⌃⌥3"),
            (store.ui("隐藏对话浮层", "Hide Chat Overlay"), "⌃⌥0"),
            (store.ui("切换外观主题", "Switch Appearance Theme"), "⌥⌘T"),
            (store.ui("后退", "Back"), "⌘["),
            (store.ui("前进", "Forward"), "⌘]"),
        ]
    }

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("课程资料", "Course Materials")) {
                settingsRow(title: store.ui("导入资料", "Import Material")) {
                    Button(store.ui("导入", "Import")) {
                        store.importFilesFromPanel()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }
            }

            settingsGroup(store.ui("笔记", "Notes")) {
                settingsRow(title: store.ui("选区上下文", "Selection Context")) {
                    if store.hasSelectionAttachments {
                        Button(store.ui("清空片段", "Clear Fragments")) {
                            store.clearSelectionAttachments()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    } else {
                        Text(store.ui("无片段", "None"))
                            .font(SettingsType.control)
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                }
            }
        }
    }

    private func settingsSidebarButton(_ section: SettingsSection) -> some View {
        let active = selectedSection == section
        return Button {
            withAnimation(WeiBeiMotion.panel) {
                selectedSection = section
            }
        } label: {
            // Full-row hit target: contentShape + maxWidth so padding/background count.
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(section.title(store))
                    .font(SettingsType.rowTitle(active: active))
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
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

    /// Shared switch used across Settings — always cinnabar, never system blue.
    func settingsSwitch(isOn: Binding<Bool>, accessibilityLabel: String) -> some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(WeiBeiTheme.cinnabar)
            .accessibilityLabel(Text(accessibilityLabel))
    }

    /// Shared Settings card primitive (also used by `AgentSettingsView` extension).
    func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let cardFill = WeiBeiTheme.paperRaised.opacity(store.appearanceMode.isDark ? 0.20 : 0.36)
        return VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
            }
            // L3: each settingsRow draws a bottom hairline. Paint the card fill over
            // the final pixel so the last row does not leave a floating divider on
            // the card edge (without requiring every call site to pass isLast).
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(cardFill)
                    .frame(height: 1)
                    .padding(.horizontal, 1)
            }
        }
    }

    /// Shared Settings row primitive (title + optional detail + trailing control).
    ///
    /// Prefer title-only rows. Pass `detail` only when the control itself cannot
    /// convey a critical constraint (e.g. env-var override is handled by notes).
    /// `showsBottomDivider` defaults to true — the group covers the last hairline (L3).
    func settingsRow<Control: View>(
        title: String,
        detail: String = "",
        showsBottomDivider: Bool = true,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsType.rowTitle(active: true))
                    .foregroundStyle(WeiBeiTheme.ink)
                if !detail.isEmpty {
                    Text(detail)
                        .font(SettingsType.detail)
                        .lineSpacing(2)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 18)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, detail.isEmpty ? 11 : 12)
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.28))
                    .frame(height: 1)
                    .padding(.leading, 14)
            }
        }
    }

    /// Shared Settings inline note (icon + secondary text). Only for actionable warnings.
    func settingsNote(_ text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.90))
            Text(text)
                .font(SettingsType.detail)
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
                .font(SettingsType.pill)
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
                    .font(SettingsType.menu)
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

// MARK: - Settings type scale
//
// One shared scale so row titles / controls / notes / pills stay visually unified.
// Display titles (page / section) still use WeiBeiTypography.brandFont.

private enum SettingsType {
    static func rowTitle(active: Bool) -> Font {
        .system(size: 13, weight: active ? .semibold : .medium)
    }

    static let control: Font = .system(size: 13, weight: .medium)
    static let detail: Font = .system(size: 12, weight: .regular)
    static let pill: Font = .system(size: 12, weight: .medium)
    static let menu: Font = .system(size: 13, weight: .semibold)
}
