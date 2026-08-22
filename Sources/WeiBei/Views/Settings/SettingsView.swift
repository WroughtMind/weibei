import AppKit
import SwiftUI
import WeiBeiCore

// MARK: - SettingsView
//
// Information architecture (2026-07-26):
//   对话 | 界面 | 快捷键 | 关于
// Settings hold durable preferences only. One-shot actions (import, new note,
// open search, clear fragments) stay in the command palette / workspace.
// Theme lives only on the Interface page (no top-bar or settings-header palette).
// Default landing section is always Chat.

struct SettingsView: View {
    // Visible to `internal` so the Settings sub-views in Views/Settings/*.swift
    // (same-target extensions) can bind to them.
    @EnvironmentObject var store: WorkspaceStore
    @EnvironmentObject private var updateService: WeiBeiUpdateService
    @StateObject var oauthService = PiOAuthService.shared
    @State private var selectedSection: SettingsSection = .agent
    @FocusState var focusedField: Field?
    // Model picker state (AgentModelPicker extension).
    @State var spinAngle: Double = 0
    @State var showManualModelEntry = false
    // Profile inline-rename state (AgentSettingsView extension).
    @State var isRenamingActiveProfile = false
    @State var profileRenameDraft = ""
    @State var apiKeyDraft = ""
    // Profile delete confirmation (AgentSettingsView extension).
    @State var showDeleteProfileConfirmation = false
    // Shortcut rebinding: click a key chip, then press the new chord.
    @State private var recordingShortcutID: AppShortcutID?
    @State private var shortcutRecordMonitor: Any?
    @State private var shortcutStatusMessage: String?
    // In-app feedback sheet.
    @State private var showFeedbackSheet = false
    @State private var showInspirationSourcesSheet = false
    @State private var feedbackTitle = ""
    @State private var feedbackBody = ""
    @State private var feedbackBusy = false
    @State private var feedbackStatus: String?
    // 资料库位置迁移（计划 §4.1）。
    @State private var pendingMigrationDestination: URL?
    @State private var migrationErrorText: String?
    @State private var migrationSuccessText: String?
    @State private var isMigratingLibrary = false
    @AppStorage(NativeAgentBackendSelection.debugDefaultsKey) var debugStudyAgentBackendRaw = ""

    private var buildInfo: WeiBeiAppBuildInfo { .current() }

    var activePiProviderID: String {
        AgentProviderReadiness.activePiProviderID(for: store)
    }

    func piProviderID(for provider: AgentProviderID) -> String {
        AgentProviderReadiness.piProviderID(for: provider, store: store)
    }

    /// Max width for long text fields (Base URL, API key) — not for every control.
    static let controlWidth: CGFloat = 260

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
                .overlay(WeiBeiTheme.hairline.opacity(0.55))
            settingsDetail
        }
        .frame(minWidth: 860, minHeight: 610)
        .background {
            WeiBeiThemeBackdrop(mode: store.appearanceMode)
                .ignoresSafeArea()
        }
        .background(SettingsWindowPaper(appearanceMode: store.appearanceMode))
        .foregroundStyle(WeiBeiTheme.ink)
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
        .onAppear {
            // Always land on Chat: highest-frequency durable settings (provider / key / model).
            selectedSection = .agent
            oauthService.refreshCatalog()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weiBeiPiOAuthDidSucceed)) { note in
            guard let raw = note.userInfo?["provider"] as? String,
                  let provider = AgentProviderID(rawValue: raw) else { return }
            store.shutdownAgentRuntime()
            store.setAgentAuthMethod(.subscription)
            store.setAgentProviderID(provider)
            store.recordAgentAuthenticationSuccess(
                provider: provider,
                authMethod: .subscription
            )
            if let firstModel = oauthService.models(providerID: provider.piProviderName).first {
                store.updateModelName(firstModel)
            }
            oauthService.refreshCatalog(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .weiBeiPiCredentialsDidChange)) { note in
            store.shutdownAgentRuntime()
            guard note.userInfo?["provider"] as? String == activePiProviderID else {
                return
            }
            if note.userInfo?["type"] as? String == PiCredentialType.apiKey.rawValue {
                apiKeyDraft = ""
            }
            oauthService.refreshCatalog(force: true)
        }
        .onChange(of: oauthService.catalog) { _, _ in
            let models = oauthService.models(providerID: activePiProviderID)
            let current = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstModel = models.first,
               !models.contains(current),
               current.isEmpty {
                store.updateModelName(firstModel)
            }
        }
    }

    enum Field: Hashable {
        case apiKey
        case model
    }

    private enum SettingsSection: String, CaseIterable, Identifiable {
        // Sidebar order: Interface first; default landing remains Chat (.agent).
        case interface
        case agent
        case shortcuts
        case about

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .interface: return "slider.horizontal.3"
            case .agent: return "text.bubble"
            case .shortcuts: return "command"
            case .about: return "info.circle"
            }
        }

        @MainActor
        func title(_ store: WorkspaceStore) -> String {
            switch self {
            case .interface: return store.ui("界面", "Interface")
            case .agent: return store.ui("对话", "Chat")
            case .shortcuts: return store.ui("快捷键", "Shortcuts")
            case .about: return store.ui("关于", "About")
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.ui("设置", "Settings"))
                .weiBeiBrandFont(language: store.interfaceLanguage, size: 22, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
                .padding(.horizontal, 22)
                .padding(.top, 22)

            VStack(spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    settingsSidebarButton(section)
                }
            }
            .padding(.horizontal, 12)

            Spacer()
        }
        .frame(width: 200)
        .background(WeiBeiTheme.paper)
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            settingsHeader
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedSection {
                    case .agent:
                        agentSettings
                    case .interface:
                        interfaceSettings
                    case .shortcuts:
                        shortcutSettings
                    case .about:
                        aboutSettings
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .id(selectedSection)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
    }

    private var settingsHeader: some View {
        HStack(alignment: .center) {
            Text(selectedSection.title(store))
                .weiBeiBrandFont(language: store.interfaceLanguage, size: 18, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(WeiBeiTheme.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.35))
                .frame(height: 1)
        }
    }

    // MARK: - Interface (language / theme / reading tint / workspace)

    private var interfaceSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsGroup(store.ui("语言", "Language")) {
                settingsRow(title: store.ui("语言", "Language"), showsBottomDivider: false) {
                    compactMenu(store.interfaceLanguage.nativeName) {
                        ForEach(WeiBeiInterfaceLanguage.allCases) { language in
                            Button(language.nativeName) {
                                withAnimation(WeiBeiMotion.appearance) {
                                    store.setInterfaceLanguage(language)
                                }
                            }
                        }
                    }
                }
            }

            // AionUI-style gallery: each card is a miniature workspace, not a flat chip.
            settingsGroup(store.ui("主题", "Theme")) {
                settingsRow(
                    title: store.ui("外观", "Appearance"),
                    detail: store.ui(
                        "跟随系统时，深浅切换自动换到同对主题",
                        "With Match System, appearance switches pick the paired theme"
                    )
                ) {
                    compactMenu(store.appearancePreference.label(ui: store.ui)) {
                        ForEach(WeiBeiAppearancePreference.allCases) { preference in
                            Button(preference.label(ui: store.ui)) {
                                store.appearancePreference = preference
                            }
                        }
                    }
                }

                themePicker
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                if store.appearanceMode.isGlass {
                    settingsRow(
                        title: store.ui("玻璃浓度", "Glass intensity"),
                        detail: store.ui(
                            "无级调节玻璃主题的透明浓度",
                            "Continuously adjust glass translucency"
                        ),
                        showsBottomDivider: false
                    ) {
                        Slider(value: Binding(
                            get: { store.glassIntensity },
                            set: { store.glassIntensity = $0 }
                        ), in: 0...1)
                        .frame(width: 170)
                    }
                }
            }

            settingsGroup(store.ui("动态效果", "Motion")) {
                settingsRow(
                    title: store.ui("动态效果", "Motion"),
                    detail: store.ui(
                        "完整动态效果会覆盖系统的减少动态设置",
                        "Full motion overrides the system reduce-motion switch"
                    ),
                    showsBottomDivider: false
                ) {
                    compactMenu(store.motionPreference.label(language: store.interfaceLanguage)) {
                        ForEach(WeiBeiMotionPreference.allCases) { preference in
                            Button(preference.label(language: store.interfaceLanguage)) {
                                store.setMotionPreference(preference)
                            }
                        }
                    }
                }
            }

            settingsGroup(store.ui("偏好", "Preferences")) {
                settingsRow(
                    title: store.ui("界面文字大小", "Interface Text Size"),
                    detail: store.ui(
                        "调整整个界面的文字大小，笔记正文同步缩放",
                        "Scales text across the interface; note content follows"
                    ),
                    showsBottomDivider: false
                ) {
                    compactMenu(store.interfaceTextScale.label(language: store.interfaceLanguage)) {
                        ForEach(WeiBeiTypography.TextScale.allCases) { scale in
                            Button(
                                "\(scale.label(language: store.interfaceLanguage)) · \(Int((scale.multiplier * 100).rounded()))%"
                            ) {
                                store.setInterfaceTextScale(scale)
                            }
                        }
                    }
                }
                settingsRow(
                    title: store.ui("今日一句", "Today's line"),
                    showsBottomDivider: store.showDailyInspiration
                ) {
                    settingsSwitch(
                        isOn: Binding(
                            get: { store.showDailyInspiration },
                            set: { store.setDailyInspirationEnabled($0) }
                        ),
                        accessibilityLabel: store.ui("显示今日一句", "Show today's line")
                    )
                }

                if store.showDailyInspiration {
                    settingsRow(
                        title: store.ui("以底纹呈现", "As paper watermark"),
                        detail: store.ui(
                            "开:句子化作纸面淡墨,点击换句;关:句子成块展示,悬停看出处。",
                            "On: the line becomes faint ink in the paper. Off: shown as a block with credit on hover."
                        ),
                        showsBottomDivider: false
                    ) {
                        settingsSwitch(
                            isOn: Binding(
                                get: { store.inspirationAsWatermark },
                                set: { store.setInspirationAsWatermark($0) }
                            ),
                            accessibilityLabel: store.ui("今日一句以底纹呈现", "Show today's line as paper watermark")
                        )
                    }
                }
            }

            libraryLocationSettings
        }
    }

    private var libraryLocationSettings: some View {
        settingsGroup(store.ui("资料库", "Library")) {
            settingsRow(
                title: store.ui("资料库位置", "Library location"),
                detail: store.courseLibraryRootPath ?? CourseLibraryLayout.defaultRootURL().path,
                showsBottomDivider: false
            ) {
                Button(store.ui("更改…", "Change…")) {
                    pickMigrationDestination()
                }
                .disabled(isMigratingLibrary)
            }
            if let destination = pendingMigrationDestination {
                migrationConfirmation(destination)
            }
            if isMigratingLibrary {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.linear)
                    Text(store.ui(
                        "正在迁移资料库，请勿操作魏碑…",
                        "Migrating the library. Please do not use WeiBei during the move…"
                    ))
                    .font(SettingsType.detail)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
            if let migrationErrorText {
                Text(migrationErrorText)
                    .font(SettingsType.detail)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
            if let migrationSuccessText {
                Text(migrationSuccessText)
                    .font(SettingsType.detail)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .disabled(isMigratingLibrary)
    }

    @ViewBuilder
    private func migrationConfirmation(_ destination: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.ui(
                "从 \(store.courseLibraryRootPath ?? "—") 迁移到 \(destination.path)",
                "Move from \(store.courseLibraryRootPath ?? "—") to \(destination.path)"
            ))
            .font(SettingsType.detail)
            .foregroundStyle(WeiBeiTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
            if Self.isCloudSyncPath(destination) {
                Text(store.ui(
                    "目标位于 iCloud 或网盘同步目录，可能出现文件未下载或同步冲突。",
                    "The destination is inside an iCloud or cloud-sync folder; files may be evicted or conflict."
                ))
                .font(SettingsType.detail)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(store.ui("开始迁移", "Start Migration")) {
                    confirmMigration(to: destination)
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                Button(store.ui("取消", "Cancel")) {
                    pendingMigrationDestination = nil
                }
                .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .padding(.bottom, 8)
    }

    private func pickMigrationDestination() {
        migrationErrorText = nil
        migrationSuccessText = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = store.ui("选择", "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingMigrationDestination = url.standardizedFileURL
    }

    private func confirmMigration(to destination: URL) {
        pendingMigrationDestination = nil
        isMigratingLibrary = true
        migrationErrorText = nil
        migrationSuccessText = nil
        Task { @MainActor in
            do {
                let result = try await store.migrateLibrary(to: destination)
                migrationSuccessText = store.ui(
                    "已迁移到 \(result.destination.path)",
                    "Moved to \(result.destination.path)"
                )
            } catch CourseProjectRootError.destinationIsLibrary {
                migrationErrorText = store.ui(
                    "所选位置已经是一个魏碑资料库，请在对话中打开它或选择其他空文件夹。",
                    "That location is already a WeiBei library. Open it instead, or choose an empty folder."
                )
            } catch {
                migrationErrorText = error.localizedDescription
            }
            isMigratingLibrary = false
        }
    }

    static func isCloudSyncPath(_ url: URL) -> Bool {
        let path = url.path
        if path.contains("Library/Mobile Documents") || path.contains("com~apple~CloudDocs") {
            return true
        }
        let cloudNames = ["Dropbox", "Google Drive", "OneDrive", "坚果云", "iCloud"]
        return cloudNames.contains { path.contains($0) }
    }

    /// Theme gallery modeled on AionUI `ThemeLayoutPreview` cards:
    /// mini app chrome (top bar + panes) so you can see how the theme feels.
    private var themePicker: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(WeiBeiAppearanceStyle.allCases) { style in
                    stylePreviewCard(style)
                        .frame(width: 226)
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.visible)
    }

    /// 四组风格卡：左浅右深两个实景预览并排；点卡选风格，
    /// 具体浅/深由上方“外观”偏好（跟随系统/浅色/深色）解析，卡上标注当前生效主题。
    private func stylePreviewCard(_ style: WeiBeiAppearanceStyle) -> some View {
        let selected = style == store.appearanceStyle
        return Button {
            store.appearanceStyle = style
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 0) {
                        WeiBeiThemeLayoutPreview(mode: style.lightMode)
                        WeiBeiThemeLayoutPreview(mode: style.darkMode)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                selected
                                    ? WeiBeiTheme.cinnabar.opacity(0.90)
                                    : WeiBeiTheme.hairline.opacity(0.42),
                                lineWidth: selected ? 2 : 1
                            )
                    }

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .weiBeiText(15, weight: .semibold)
                            .foregroundStyle(WeiBeiTheme.cinnabar)
                            .padding(7)
                    }
                }

                Text(style.label(ui: store.ui))
                    .weiBeiText(12, weight: selected ? .semibold : .medium)
                    .foregroundStyle(selected ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
                    .lineLimit(1)

                Text(
                    store.ui("当前生效", "Active") + " · "
                        + store.appearanceMode.label(language: store.interfaceLanguage)
                )
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(style.label(ui: store.ui)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 对话服务设置 — 实现在 Views/Settings/AgentSettingsView.swift 的 extension 中。
    private var agentSettings: some View {
        agentSettingsContent()
    }

    // MARK: - Shortcuts (grouped, click key to rebind)

    private var shortcutSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.ui(
                "点按按键后输入新组合。Esc 取消，右键恢复默认。",
                "Click a key, then press a new chord. Esc cancels; right-click resets."
            ))
            .font(SettingsType.detail)
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .padding(.horizontal, 2)

            if let shortcutStatusMessage, !shortcutStatusMessage.isEmpty {
                Text(shortcutStatusMessage)
                    .font(SettingsType.detail)
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.90))
                    .padding(.horizontal, 2)
            }

            ForEach(AppShortcutGroup.allCases) { group in
                let items = group.shortcuts
                settingsGroup(group.title(language: store.interfaceLanguage)) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, id in
                        settingsRow(
                            title: id.title(language: store.interfaceLanguage),
                            showsBottomDivider: index < items.count - 1
                        ) {
                            shortcutKeyChip(id)
                        }
                    }
                }
            }

            Button(store.ui("全部恢复默认", "Reset All to Defaults")) {
                stopShortcutRecording()
                store.resetAllShortcuts()
                shortcutStatusMessage = store.ui("已恢复全部默认快捷键。", "All shortcuts restored to defaults.")
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
            .padding(.top, 2)
        }
        .onDisappear { stopShortcutRecording() }
    }

    private func shortcutKeyChip(_ id: AppShortcutID) -> some View {
        let recording = recordingShortcutID == id
        let chord = store.chord(for: id)
        return Button {
            beginShortcutRecording(id)
        } label: {
            Text(recording
                 ? store.ui("按下…", "Press…")
                 : chord.display)
                .weiBeiText(12, weight: .semibold, design: .monospaced)
                .foregroundStyle(recording ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    recording
                        ? WeiBeiTheme.cinnabar.opacity(0.10)
                        : WeiBeiTheme.paperInset.opacity(0.45)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            recording ? WeiBeiTheme.cinnabar.opacity(0.55) : WeiBeiTheme.hairline.opacity(0.36),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .help(store.ui("点按后按下新组合；右键恢复默认", "Click then press a new chord; right-click to reset"))
        .contextMenu {
            Button(store.ui("恢复默认", "Reset to Default")) {
                stopShortcutRecording()
                store.resetShortcut(id)
                shortcutStatusMessage = nil
            }
        }
    }

    private func beginShortcutRecording(_ id: AppShortcutID) {
        if recordingShortcutID == id {
            stopShortcutRecording()
            return
        }
        stopShortcutRecording()
        recordingShortcutID = id
        shortcutStatusMessage = nil
        shortcutRecordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels without changing the binding.
            if event.keyCode == 53 {
                DispatchQueue.main.async { stopShortcutRecording() }
                return nil
            }
            guard let chord = AppShortcutChord.from(event: event) else { return event }
            DispatchQueue.main.async {
                applyRecordedShortcut(id, chord: chord)
            }
            return nil
        }
    }

    private func applyRecordedShortcut(_ id: AppShortcutID, chord: AppShortcutChord) {
        defer { stopShortcutRecording() }
        if let conflict = AppShortcutCatalog.conflict(
            for: chord,
            excluding: id,
            overrides: store.customShortcutOverrides
        ) {
            // Still apply, but surface the conflict so the user can fix the other binding.
            store.setShortcut(id, chord: chord)
            shortcutStatusMessage = store.ui(
                "已改绑；与「\(conflict.title(language: store.interfaceLanguage))」冲突，请再改其中一项。",
                "Saved; conflicts with “\(conflict.title(language: store.interfaceLanguage))”. Rebind one of them."
            )
            return
        }
        store.setShortcut(id, chord: chord)
        shortcutStatusMessage = nil
    }

    private func stopShortcutRecording() {
        if let shortcutRecordMonitor {
            NSEvent.removeMonitor(shortcutRecordMonitor)
        }
        shortcutRecordMonitor = nil
        recordingShortcutID = nil
    }

    // MARK: - About

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Version number + check only. No copy control (build/version still go into feedback).
            settingsGroup(store.ui("版本", "Version")) {
                settingsRow(
                    title: buildInfo.displayLine,
                    showsBottomDivider: updateService.availableUpdate != nil
                ) {
                    Button {
                        runUpdateAction()
                    } label: {
                        if updateService.isBusy {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(updateActionLabel)
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: updateService.status != .upToDate))
                    .disabled(updateService.isBusy)
                }

                if let availableUpdate = updateService.availableUpdate {
                    settingsRow(
                        title: store.ui("新版本 \(availableUpdate.version)", "New Version \(availableUpdate.version)"),
                        detail: userFacingUpdateDetail(availableUpdate),
                        showsBottomDivider: false
                    ) {
                        EmptyView()
                    }
                }
            }

            settingsGroup(store.ui("反馈", "Feedback")) {
                settingsRow(
                    title: store.ui("提交反馈", "Send Feedback"),
                    showsBottomDivider: false
                ) {
                    Button(store.ui("写反馈…", "Write…")) {
                        feedbackTitle = ""
                        feedbackBody = ""
                        feedbackStatus = nil
                        showFeedbackSheet = true
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }
            }

            settingsGroup(store.ui("灵感句", "Daily Line")) {
                settingsRow(
                    title: store.ui("来源与权利台账", "Sources & rights ledger"),
                    detail: store.ui(
                        "50 条灵感句的原文出处与版权依据。底纹模式不内联展示署名,以此台账为准。",
                        "Source and rights basis for all 50 daily lines. The watermark mode shows no inline credit; this ledger is authoritative."
                    ),
                    showsBottomDivider: false
                ) {
                    Button(store.ui("查看台账…", "View…")) {
                        showInspirationSourcesSheet = true
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }
            }

            if case let .failed(message) = updateService.status {
                Text(store.ui("更新失败：\(message)", "Update failed: \(message)"))
                    .font(SettingsType.detail)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .padding(.horizontal, 4)
            }

            Text(store.ui(
                "密钥与对话凭证仅保存在本机魏碑数据目录，不上传。",
                "Keys and chat credentials stay in the local WeiBei data folder and are never uploaded."
            ))
            .font(SettingsType.detail)
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .padding(.horizontal, 4)
        }
        .sheet(isPresented: $showFeedbackSheet) {
            feedbackSheet
        }
        .sheet(isPresented: $showInspirationSourcesSheet) {
            inspirationSourcesSheet
        }
    }

    /// Plain-text rendering of the bundled SOURCES.md ledger — the attribution
    /// record for daily lines when the watermark mode shows no inline credit.
    private var inspirationSourcesSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.ui("灵感句来源与权利", "Daily line sources & rights"))
                .weiBeiText(15, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)

            ScrollView {
                Text(inspirationSourcesLedgerText)
                    .weiBeiText(10.5, design: .monospaced)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 260, maxHeight: 420)
            .weibeiEtchedBackground(
                fill: WeiBeiTheme.paperRaised.opacity(0.52),
                stroke: WeiBeiTheme.hairline.opacity(0.3),
                cornerRadius: 8
            )

            Button(store.ui("关闭", "Close")) {
                showInspirationSourcesSheet = false
            }
            .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 620)
    }

    private var inspirationSourcesLedgerText: String {
        let bundle = WeiBeiResources.bundle
        let url = bundle.url(forResource: "SOURCES", withExtension: "md", subdirectory: "Inspiration")
            ?? bundle.url(forResource: "SOURCES", withExtension: "md")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            return store.ui(
                "台账文件缺失。完整台账见仓库 Sources/WeiBei/Resources/Inspiration/SOURCES.md。",
                "Ledger file missing. Full ledger: Sources/WeiBei/Resources/Inspiration/SOURCES.md in the repository."
            )
        }
        return text
    }

    private var updateActionLabel: String {
        if updateService.availableUpdate != nil {
            if case .failed = updateService.status {
                return store.ui("重试安装", "Retry Install")
            }
            return store.ui("下载并安装", "Download and Install")
        }
        switch updateService.status {
        case .upToDate:
            return store.ui("已是最新", "Up to Date")
        case .failed:
            return store.ui("重新检查", "Try Again")
        default:
            return store.ui("检查更新", "Check for Updates")
        }
    }

    private var feedbackSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.ui("提交反馈", "Send Feedback"))
                .weiBeiText(15, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)

            Text(store.ui(
                "描述尽量具体。会自动附上版本与系统信息。",
                "Be specific. Version and system info are attached automatically."
            ))
            .font(SettingsType.detail)
            .foregroundStyle(WeiBeiTheme.secondaryInk)

            TextField(
                "",
                text: $feedbackTitle,
                prompt: Text(store.ui("标题", "Title"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .weiBeiText(13)
            .foregroundColor(WeiBeiTheme.ink)
            .weibeiInputSurface(active: true, height: 34)

            ZStack(alignment: .topLeading) {
                if feedbackBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(store.ui("发生了什么？如何复现？", "What happened? How can we reproduce it?"))
                        .weiBeiText(13)
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $feedbackBody)
                    .weiBeiText(13)
                    .foregroundColor(WeiBeiTheme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140, maxHeight: 200)
                    .padding(6)
            }
            .weibeiEtchedBackground(
                fill: WeiBeiTheme.paperRaised.opacity(0.52),
                stroke: WeiBeiTheme.hairline.opacity(0.3),
                cornerRadius: 8
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
            }

            if let feedbackStatus, !feedbackStatus.isEmpty {
                Text(feedbackStatus)
                    .font(SettingsType.detail)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            HStack {
                Button(store.ui("取消", "Cancel")) {
                    showFeedbackSheet = false
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
                .disabled(feedbackBusy)

                Spacer()

                Button {
                    Task { await submitFeedback() }
                } label: {
                    if feedbackBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(store.ui("提交", "Submit"))
                    }
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                .disabled(feedbackBusy || !canSubmitFeedback)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(WeiBeiTheme.paper)
        .preferredColorScheme(store.appearanceMode.colorScheme)
    }

    private var canSubmitFeedback: Bool {
        !feedbackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !feedbackBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func submitFeedback() async {
        let title = feedbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = feedbackBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return }

        feedbackBusy = true
        feedbackStatus = store.ui("正在提交…", "Submitting…")
        let fullBody = feedbackIssueBody(userBody: body)

        // Prefer `gh` when the machine is already authenticated — truly hands-off.
        if let url = await createIssueWithGitHubCLI(title: title, body: fullBody) {
            feedbackBusy = false
            feedbackStatus = store.ui("已提交。", "Submitted.")
            showFeedbackSheet = false
            NSWorkspace.shared.open(url)
            return
        }

        // Fallback: open a prefilled GitHub new-issue page (one confirm click if logged in).
        openPrefilledGitHubIssue(title: title, body: fullBody)
        feedbackBusy = false
        feedbackStatus = store.ui(
            "已打开提交页，确认后即可发送。",
            "Opened the submit page — confirm there to send."
        )
        // Keep sheet briefly so the status is readable, then close.
        try? await Task.sleep(nanoseconds: 900_000_000)
        showFeedbackSheet = false
    }

    private func feedbackIssueBody(userBody: String) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osLine = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return """
        ### 说明 / Report
        \(userBody)

        ### 环境 / Environment
        - 魏碑 \(buildInfo.version) (\(buildInfo.build))
        - \(osLine)
        """
    }

    private func createIssueWithGitHubCLI(title: String, body: String) async -> URL? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [
                    "gh", "issue", "create",
                    "--repo", "weibei-app/weibei",
                    "--title", title,
                    "--body", body,
                    "--label", "bug",
                ]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: URL(string: text))
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func openPrefilledGitHubIssue(title: String, body: String) {
        var components = URLComponents(string: "https://github.com/weibei-app/weibei/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: "bug"),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func runUpdateAction() {
        if updateService.availableUpdate == nil {
            updateService.checkForUpdates()
        } else {
            updateService.installAvailableUpdate()
        }
    }

    private func userFacingUpdateDetail(_ update: WeiBeiAvailableUpdate) -> String {
        update.summaryLines.isEmpty
            ? store.ui("包含最新改进和修复。", "Includes the latest improvements and fixes.")
            : update.summaryLines.joined(separator: "\n")
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
                    .weiBeiText(13, weight: .semibold)
                    .frame(width: 18)
                Text(section.title(store))
                    .font(SettingsType.rowTitle(active: active))
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
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

    /// Shared Settings group: title + rows on the same paper, no raised card.
    func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                content()
            }
        }
    }

    /// Shared Settings row: title grows, trailing control stays content-sized (right-aligned).
    func settingsRow<Control: View>(
        title: String,
        detail: String = "",
        showsBottomDivider: Bool = true,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
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
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, detail.isEmpty ? 11 : 12)
        .overlay(alignment: .bottom) {
            if showsBottomDivider {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.28))
                    .frame(height: 1)
            }
        }
    }

    /// Shared Settings inline note (icon + secondary text). Only for actionable warnings.
    func settingsNote(_ text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .weiBeiText(12, weight: .semibold)
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
                .weiBeiText(12, weight: .semibold)
            Text(title)
                .font(SettingsType.pill)
                .lineLimit(1)
        }
        .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.tertiaryInk)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(active ? WeiBeiTheme.paperRaised.opacity(0.54) : WeiBeiTheme.paperInset.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(WeiBeiTheme.hairline.opacity(active ? 0.46 : 0.24), lineWidth: 1)
        }
    }

    /// Shared compact dropdown — hugs label width, no forced wide track.
    func compactMenu<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .font(SettingsType.menu)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .weiBeiText(9.5, weight: .bold)
            }
            .foregroundStyle(WeiBeiTheme.ink)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .weibeiEtchedBackground(
                fill: WeiBeiTheme.paperRaised.opacity(0.52),
                stroke: WeiBeiTheme.hairline.opacity(0.3),
                cornerRadius: 8
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
    }

    /// Shared Settings group title label.
    func sectionTitle(_ title: String) -> some View {
        Text(title)
            .weiBeiBrandFont(language: store.interfaceLanguage, size: 12, weight: .semibold)
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
    }
}

// MARK: - Settings type scale

private enum SettingsType {
    static func rowTitle(active: Bool) -> Font {
        .system(size: 13, weight: active ? .semibold : .medium)
    }

    static let control: Font = .system(size: 13, weight: .medium)
    static let detail: Font = .system(size: 12, weight: .regular)
    static let pill: Font = .system(size: 12, weight: .medium)
    static let menu: Font = .system(size: 13, weight: .semibold)
}

/// Paint the Settings window with the same paper as the workspace.
/// Leave the system titlebar in place so traffic lights stay clear of「设置」.
private struct SettingsWindowPaper: NSViewRepresentable {
    var appearanceMode: WeiBeiAppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = !appearanceMode.isGlass
        window.backgroundColor = appearanceMode.isGlass
            ? .clear
            : appearanceMode.windowBackground
        window.appearance = NSAppearance(
            named: appearanceMode.isDark ? .darkAqua : .aqua
        )
        window.contentView?.wantsLayer = appearanceMode.isGlass
        window.contentView?.layer?.backgroundColor = appearanceMode.isGlass ? NSColor.clear.cgColor : nil
    }
}
