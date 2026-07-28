import Foundation
import WeiBeiCore

/**
 * 验证应用入口、设置界面、模型目录与服务商元数据契约。
 */
enum SettingsSelfChecks {
    /**
     * 执行该领域的自检。
     */
    @MainActor
    static func run(repositoryURL: URL) throws {
        let workspaceStoreSource = SelfCheckSupport.source("Sources/WeiBei/Stores/WorkspaceStore.swift", repositoryURL: repositoryURL)
        let commandPaletteSource = SelfCheckSupport.source("Sources/WeiBei/Views/CommandPaletteView.swift", repositoryURL: repositoryURL)
        let settingsViewsSourceEarly = SelfCheckSupport.joinedSources(
            in: "Sources/WeiBei/Views/Settings",
            pathExtension: "swift",
            repositoryURL: repositoryURL
        )

        let modelListServiceSource = SelfCheckSupport.source("Sources/WeiBeiCore/AgentModelListService.swift", repositoryURL: repositoryURL)
        let workspaceModelsSource = SelfCheckSupport.source("Sources/WeiBeiCore/WorkspaceModels.swift", repositoryURL: repositoryURL)
        let appSourceURL = repositoryURL
            .appendingPathComponent("Sources/WeiBei/App/WeiBeiApp.swift")
        let appSource = (try? String(contentsOf: appSourceURL, encoding: .utf8)) ?? ""
        // Rebind full settings union (app entrypoint + Views/Settings/*) for later assertions.
        let agentSettingsSource = appSource + "\n" + settingsViewsSourceEarly
        expect(appSource.contains("private var shouldActivateOnLaunch: Bool")
            && appSource.contains("WEIBEI_SUPPRESS_ACTIVATION")
            && appSource.contains("Task { await store.runVerificationScenarioIfNeeded() }")
            && appSource.contains("if shouldActivateOnLaunch {\n            NSApp.activate(ignoringOtherApps: true)\n        }"), "app activation is skipped during non-invasive verification launches")
        expect(appSource.contains("applyVerificationWindowSize(to: window)")
            && appSource.contains("environment[\"WEIBEI_SUPPRESS_ACTIVATION\"] == \"1\"")
            && appSource.contains("environment[\"WEIBEI_VERIFY_WINDOW_SIZE\"]")
            && appSource.contains("window.setContentSize(target)")
            && appSource.contains("window.center()"), "verification-only window sizing supports real wide and narrow screenshots without changing normal launch behavior")
        expect(appSource.contains("window.isOpaque = true"), "main window declares opaque paper backing for stable capture")
        expect(appSource.contains("environment[\"WEIBEI_VERIFY_CAPTURE_PATH\"]")
            && appSource.contains("bitmapImageRepForCachingDisplay")
            && appSource.contains("cacheDisplay(in: bounds, to: bitmap)")
            && appSource.contains("visibleWebViews(in: contentView)")
            && appSource.contains("private static func visibleRect(")
            && appSource.contains(".intersection(contentView.bounds)")
            && appSource.contains("view.convert(view.bounds, to: contentView)")
            && appSource.contains("configuration.rect = rect")
            && appSource.contains("webView.takeSnapshot(with: configuration)")
            && appSource.contains("overlay.image.draw(in: overlay.rect, from: .zero, operation: .sourceOver, fraction: 1)")
            && !appSource.contains("operation: .copy"), "isolated verification capture preserves the opaque window underneath transparent WebView snapshots")
        expect(appSource.contains("let scenario = environment[\"WEIBEI_VERIFY_SCENARIO\"] ?? \"\"")
            && appSource.contains("\"course-workspace-overview-flow\"")
            && appSource.contains("\"course-workspace-workflow-flow\""), "course workspace verification scenarios opt into completion-aware capture")
        expect(appSource.contains("remainingAttempts: scenario == \"pane-toggle-continuity-flow\" ? 1_800 : 600")
            && appSource.contains("waitForVerificationCompletion")
            && appSource.contains("stages.split(separator: \"\\n\").contains(\"completed\")")
            && appSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 1.5)"), "isolated verification capture waits for an explicit completion marker and settled rendering")
        expect(appSource.contains("sharedWorkspaceStore"), "main window and settings share one workspace store")
        expect(!appSource.contains("launchProbe"), "app launch path has no temporary probe logging")
        expect(appSource.contains("WeiBeiAppearanceTransition")
            && appSource.contains(".modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))")
            && !appSource.contains(".animation(WeiBeiMotion.appearance, value: mode)")
            // SettingsView migrated to its own file (Sources/WeiBei/Views/Settings/
            // SettingsView.swift), so the modifier now appears once in WeiBeiApp.swift
            // (the main window) and once in the settings views union. Count across the
            // union, not just appSource — see L1 in the settings diagnosis report.
            && agentSettingsSource.components(separatedBy: ".modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))").count >= 3
            && appSource.contains("private func animateAppearance(_ action: () -> Void)")
            && appSource.contains("animateAppearance {\n                        store.toggleAppearanceMode()")
            && workspaceStoreSource.contains("Transaction(animation: WeiBeiMotion.appearance)")
            // setAppearanceMode call now lives in SettingsView.swift (migrated out with
            // the settings UI). Scan the union — see L1.
            && agentSettingsSource.contains("store.setAppearanceMode(mode)")
            && appSource.contains("@State private var washColor = Color.clear")
            && appSource.contains("washColor = Color(nsColor: oldMode.windowBackground)")
            && appSource.contains("washOpacity = 0.16")
            && appSource.contains("crossFamily")
            && appSource.contains("transaction.disablesAnimations = true")
            && appSource.contains("withAnimation(WeiBeiMotion.appearance) {\n                    washOpacity = 0\n                }"), "appearance mode changes stage a wash only across light/dark families, not same-family swaps")
        expect(appSource.contains("addLocalMonitorForEvents(matching: .keyDown)") && appSource.contains("removeMonitor(shortcutMonitor)"), "app-level shortcuts survive focused web editor")
        expect(appSource.contains("var reopenMainWindow: (() -> Void)?")
            && appSource.contains("applicationShouldHandleReopen")
            && appSource.contains("if !flag")
            && appSource.contains("window.deminiaturize(nil)")
            && appSource.contains("window.makeKeyAndOrderFront(nil)")
            && appSource.contains("reopenMainWindow?()")
            && appSource.contains("MainWindowReopenBridge(appDelegate: appDelegate)")
            && appSource.contains("@Environment(\\.openWindow) private var openWindow")
            && appSource.contains("openWindow(id: \"main\")")
            && appSource.contains("return false")
            && !appSource.contains("return flag"), "reopen restores a hidden/minimized window or opens the main SwiftUI window instead of leaving a zero-window process")
        expect(!agentSettingsSource.contains("Form {")
            // Settings IA (2026-07-26): 对话 | 界面 | 快捷键 | 关于.
            // Preferences only; one-shot actions live in command palette / workspace.
            // Theme only on Interface page as paper swatches. Default section is always .agent.
            && agentSettingsSource.contains("@State private var selectedSection: SettingsSection = .agent")
            && agentSettingsSource.contains("private enum SettingsSection: String, CaseIterable, Identifiable")
            && !agentSettingsSource.contains("case overview")
            && !agentSettingsSource.contains("case appearance")
            && !agentSettingsSource.contains("case reading")
            && !agentSettingsSource.contains("case writing")
            && !agentSettingsSource.contains("case data")
            && agentSettingsSource.contains("case agent")
            && agentSettingsSource.contains("case interface")
            && agentSettingsSource.contains("case shortcuts")
            && agentSettingsSource.contains("case about")
            && agentSettingsSource.contains("aboutSettings")
            && agentSettingsSource.contains("interfaceSettings")
            && agentSettingsSource.contains("WeiBeiUpdateChecker.check")
            && agentSettingsSource.contains("runUpdateCheck")
            && agentSettingsSource.contains("settingsSidebar")
            && agentSettingsSource.contains("settingsDetail")
            && !agentSettingsSource.contains("overviewSettings")
            && !agentSettingsSource.contains("appearanceSettings")
            && !agentSettingsSource.contains("readingSettings")
            && !agentSettingsSource.contains("writingSettings")
            && !agentSettingsSource.contains("dataSettings")
            && agentSettingsSource.contains("agentSettings")
            && agentSettingsSource.contains("Text(store.ui(\"设置\", \"Settings\"))")
            && !agentSettingsSource.contains("Text(\"SETTINGS\")")
            && !agentSettingsSource.contains("case .overview: return \"HOME\"")
            && !agentSettingsSource.contains("case .appearance: return \"LOOK\"")
            && !agentSettingsSource.contains("case .agent: return \"CHAT\"")
            && !agentSettingsSource.contains("var code: String")
            && agentSettingsSource.contains("case .agent: return store.ui(\"对话\", \"Chat\")")
            && agentSettingsSource.contains("case .interface: return store.ui(\"界面\", \"Interface\")")
            && agentSettingsSource.contains(".frame(minWidth: 860, minHeight: 610)")
            && !agentSettingsSource.contains(".frame(width: 860, height: 610)")
            && agentSettingsSource.contains("settingsGroup(store.ui(\"对话服务\", \"Chat Service\")")
            && agentSettingsSource.contains("ForEach(AgentProviderID.subscriptionProviders)")
            && agentSettingsSource.contains("ForEach(AgentProviderID.apiKeyProviders)")
            && agentSettingsSource.contains("ForEach(AgentProviderID.localOrCustomProviders)")
            && agentSettingsSource.contains("store.setAgentProviderID(provider)")
            && agentSettingsSource.contains("store.updateAgentBaseURL")
            && agentSettingsSource.contains("openAgentProviderConsole")
            && agentSettingsSource.contains("AgentProviderID.subscriptionProviders")
            && agentSettingsSource.contains("agentModelPicker()")
            && !agentSettingsSource.contains("settingsGroup(store.ui(\"对话形态\", \"Chat Surface\")")
            && !agentSettingsSource.contains("页边洞察")
            && !agentSettingsSource.contains("Agent 上下文")
            && !agentSettingsSource.contains("Agent 与 API")
            && !agentSettingsSource.contains("title: store.ui(\"对话与 API\"")
            && !agentSettingsSource.contains("settingsGroup(store.ui(\"API\"")
            && !agentSettingsSource.contains("把 Agent 作为")
            && agentSettingsSource.contains("prompt: Text(store.ui(\"粘贴 API Key\"")
            && !agentSettingsSource.contains("Button(store.ui(\"保存到当前配置\"")
            && !agentSettingsSource.contains("Button(store.ui(\"保存\", \"Save\")")
            && agentSettingsSource.contains("onChange(of: store.openAIAPIKey)")
            && agentSettingsSource.contains("AgentAuthMethod")
            && agentSettingsSource.contains("createAgentCredentialProfile")
            && agentSettingsSource.contains("openAgentProviderConsole")
            && !agentSettingsSource.contains("prompt: Text(\"OpenAI 密钥\")")
            && agentSettingsSource.contains("store.saveOpenAIAPIKey()")
            && agentSettingsSource.contains(".onSubmit { store.saveOpenAIAPIKey() }")
            && agentSettingsSource.contains("SecureField(")
            && agentSettingsSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
            && agentSettingsSource.contains(".foregroundColor(WeiBeiTheme.ink)")
            && agentSettingsSource.contains(".weibeiInputSurface(active: focusedField == .apiKey, height: 38)")
            // Theme: Interface page layout-preview cards only — no header palette, no sidebar jump pills.
            && agentSettingsSource.contains("private var themePicker")
            && agentSettingsSource.contains("WeiBeiAppearanceMode.allCases")
            && agentSettingsSource.contains("WeiBeiThemeLayoutPreview(mode:")
            && !agentSettingsSource.contains("settingsAppearanceToggleButton")
            && !agentSettingsSource.contains("AppearanceThemePaletteButton()")
            // One-shot actions must not reappear in Views/Settings/* (menus/workspace may still call them).
            && !settingsViewsSourceEarly.contains("importFilesFromPanel")
            && !settingsViewsSourceEarly.contains("promptCreateBlankNotebookNote")
            && !settingsViewsSourceEarly.contains("revealReaderSearch")
            && !settingsViewsSourceEarly.contains("clearSelectionAttachments")
            && !agentSettingsSource.contains("Image(systemName: store.appearanceMode.systemImage)")
            && !agentSettingsSource.contains("WeiBeiIconButtonStyle(active: store.appearanceMode == .inkstone")
            && !agentSettingsSource.contains("TopBarVariant")
            && !agentSettingsSource.contains("setTopBarVariant")
            && !agentSettingsSource.contains("顶部栏样式"), "settings center uses 4 sections (Chat/Interface/Shortcuts/About), durable prefs only, theme name segments on Interface")
        // Model list is discovered live per-provider (OpenAI-compatible / Anthropic / Gemini /
        // Azure / Bedrock / GitHub Models / OpenRouter), with a built-in fallback for providers
        // whose listing is unavailable or untrustworthy (e.g. Codex subscription).
        expect(modelListServiceSource.contains("enum ModelListStrategy")
            && modelListServiceSource.contains("case openAICompatible")
            && modelListServiceSource.contains("case anthropic")
            && modelListServiceSource.contains("case gemini")
            && modelListServiceSource.contains("case azureOpenAI")
            && modelListServiceSource.contains("case bedrock")
            && modelListServiceSource.contains("case gitHubModels")
            && modelListServiceSource.contains("case openRouterPublic")
            && modelListServiceSource.contains("case codexSubscription(token: String, accountID: String)")
            && modelListServiceSource.contains("chatgpt.com/backend-api/codex/models")
            && modelListServiceSource.contains("ChatGPT-Account-ID")
            && modelListServiceSource.contains("func fetchModels(strategy:")
            && modelListServiceSource.contains("x-api-key")
            && modelListServiceSource.contains("anthropic-version")
            && modelListServiceSource.contains("foundation-models")
            && workspaceModelsSource.contains("var modelListProtocol: ModelListProtocol")
            && workspaceModelsSource.contains("var recommendedModels: [String]")
            && workspaceModelsSource.contains("var defaultListBaseURL: String?")
            && workspaceStoreSource.contains("var availableModels: [String]")
            && workspaceStoreSource.contains("var modelListStatus: ModelListStatus")
            && workspaceStoreSource.contains("func resolvedModelListStrategy()")
            && workspaceStoreSource.contains("func refreshModelList()")
            && workspaceStoreSource.contains("AgentModelListService.shared.fetchModels")
            && agentSettingsSource.contains("agentModelPicker()")
            && agentSettingsSource.contains("requestModelListRefresh()"), "chat service enumerates models live per provider with a built-in fallback and surfaces them in a dropdown")
        // Regression: refreshModelList must not cancel modelFetchTask at entry. The scheduler
        // stores the Task that awaits refreshModelList; cancelling there self-cancels the
        // in-flight fetch, discards a successful Codex catalog, and leaves status .loading.
        // Exactly one cancel site remains, inside scheduleModelListRefresh.
        expect(workspaceStoreSource.contains("func scheduleModelListRefresh()")
            && workspaceStoreSource.components(separatedBy: "modelFetchTask?.cancel()").count == 2
            && workspaceStoreSource.contains("must NOT cancel `modelFetchTask`")
            && !workspaceStoreSource.contains("func refreshModelList() async {\n        modelFetchTask?.cancel()"),
            "model-list race guard cancels only from scheduleModelListRefresh, never self-cancels refreshModelList")
        // L5: provider console links + key-help live in one metadata table (behavior locked).
        let credentialProfilesSource = SelfCheckSupport.source("Sources/WeiBeiCore/AgentCredentialProfiles.swift", repositoryURL: repositoryURL)
        expect(credentialProfilesSource.contains("public struct Metadata: Sendable, Equatable")
            && credentialProfilesSource.contains("public enum KeyHelp: Sendable, Equatable")
            && credentialProfilesSource.contains("public static func metadata(for provider: AgentProviderID) -> Metadata")
            && credentialProfilesSource.contains("public static func loginURL(for provider: AgentProviderID) -> URL?")
            && credentialProfilesSource.contains("public static func accountURL(for provider: AgentProviderID) -> URL?")
            && credentialProfilesSource.contains("public static func keyHelp(language: WeiBeiInterfaceLanguage, provider: AgentProviderID) -> String"),
            "provider console metadata is table-driven behind the existing AgentProviderConsoleLinks API")
        // Runtime golden values — keep the pre-L5 URLs/help strings from drifting.
        for provider in AgentProviderID.allCases {
            _ = AgentProviderConsoleLinks.loginURL(for: provider)
            _ = AgentProviderConsoleLinks.accountURL(for: provider)
            _ = AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: provider)
            _ = AgentProviderConsoleLinks.keyHelp(language: .english, provider: provider)
            _ = AgentProviderConsoleLinks.metadata(for: provider)
        }
        expect(AgentProviderConsoleLinks.loginURL(for: .openai)?.absoluteString == "https://platform.openai.com/api-keys"
            && AgentProviderConsoleLinks.accountURL(for: .openai)?.absoluteString == "https://platform.openai.com/"
            && AgentProviderConsoleLinks.loginURL(for: .openaiCodex)?.absoluteString == "https://platform.openai.com/api-keys"
            && AgentProviderConsoleLinks.accountURL(for: .openaiCodex)?.absoluteString == "https://chatgpt.com/"
            && AgentProviderConsoleLinks.loginURL(for: .anthropic)?.absoluteString == "https://console.anthropic.com/settings/keys"
            && AgentProviderConsoleLinks.accountURL(for: .anthropic)?.absoluteString == "https://claude.ai/"
            && AgentProviderConsoleLinks.loginURL(for: .githubCopilot)?.absoluteString == "https://github.com/settings/copilot"
            && AgentProviderConsoleLinks.accountURL(for: .githubCopilot)?.absoluteString == "https://github.com/login"
            && AgentProviderConsoleLinks.loginURL(for: .xai)?.absoluteString == "https://console.x.ai/"
            && AgentProviderConsoleLinks.accountURL(for: .xai)?.absoluteString == "https://x.ai/"
            && AgentProviderConsoleLinks.loginURL(for: .deepseek)?.absoluteString == "https://platform.deepseek.com/api_keys"
            && AgentProviderConsoleLinks.loginURL(for: .openrouter)?.absoluteString == "https://openrouter.ai/keys"
            && AgentProviderConsoleLinks.loginURL(for: .custom) == nil
            && AgentProviderConsoleLinks.loginURL(for: .llamaCpp) == nil
            && AgentProviderConsoleLinks.loginURL(for: .xiaomi) == nil
            && AgentProviderConsoleLinks.accountURL(for: .deepseek)?.absoluteString == "https://platform.deepseek.com/api_keys",
            "provider console login/account URLs match the pre-L5 golden set")
        expect(AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .openaiCodex).contains("订阅 OAuth")
            && AgentProviderConsoleLinks.keyHelp(language: .english, provider: .openaiCodex).contains("Subscription OAuth")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .anthropic).contains("ANTHROPIC_API_KEY")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .azureOpenAI).contains("AZURE_OPENAI_BASE_URL")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .amazonBedrock).contains("AWS_BEARER_TOKEN_BEDROCK")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .custom).contains("OpenAI 兼容")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .llamaCpp).contains("llama.cpp")
            && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .openai).contains("OPENAI_API_KEY")
            && AgentProviderConsoleLinks.metadata(for: .openai).help == .genericEnv
            && AgentProviderConsoleLinks.metadata(for: .openaiCodex).help == .openaiCodex
            && AgentProviderConsoleLinks.metadata(for: .cloudflareAIGateway).help == .cloudflareAIGateway
            && AgentProviderConsoleLinks.metadata(for: .cloudflareWorkersAI).help == .cloudflareWorkersAI,
            "provider key-help copy matches the pre-L5 golden set for special and generic cases")
        expect(agentSettingsSource.contains(".contentShape(Rectangle())")
            && agentSettingsSource.contains("func settingsSwitch(isOn: Binding<Bool>, accessibilityLabel: String)")
            // Sidebar is a pure section list — no language/theme jump pills at the bottom.
            && !agentSettingsSource.contains("icon: \"character.book.closed\"")
            && !agentSettingsSource.contains("前往外观设置")
            && !agentSettingsSource.contains("管理魏碑的界面、写作、对话和本地资料")
            && !agentSettingsSource.contains("private var sectionSubtitle")
            && !agentSettingsSource.contains("布局说明")
            && !agentSettingsSource.contains("当前阅读位置")
            && !agentSettingsSource.contains("选区入口")
            && !agentSettingsSource.contains("编辑器主题")
            && !agentSettingsSource.contains("title: store.ui(\"当前资料\""), "settings sidebar is a pure section list; rows are decluttered; hit area is full-width")
        expect(agentSettingsSource.contains("title: store.ui(\"每日灵感\", \"Daily Inspiration\")")
            && agentSettingsSource.contains("get: { store.showDailyInspiration }")
            && agentSettingsSource.contains("set: { store.setDailyInspirationEnabled($0) }")
            && agentSettingsSource.contains("settingsSwitch(")
            && agentSettingsSource.contains("accessibilityLabel: store.ui(\"显示每日灵感\", \"Show Daily Inspiration\")")
            && agentSettingsSource.contains(".tint(WeiBeiTheme.cinnabar)")
            && agentSettingsSource.contains("interfaceSettings"), "settings toggles daily inspiration on Interface with a cinnabar switch (no filler detail copy)")
        expect(!agentSettingsSource.contains("title: store.ui(\"笔记模式\", \"Note Mode\")")
            && !agentSettingsSource.contains("segmented(NoteRenderMode.visibleCases")
            && agentSettingsSource.contains("title: store.ui(\"文稿随主题调色\", \"Match documents to theme\")")
            && agentSettingsSource.contains("title: store.ui(\"语言\", \"Language\")")
            && agentSettingsSource.contains("compactMenu(store.interfaceLanguage.nativeName)")
            && agentSettingsSource.contains("private var themePicker")
            && agentSettingsSource.contains("WeiBeiThemeLayoutPreview(mode:")
            && agentSettingsSource.contains("showFeedbackSheet")
            && agentSettingsSource.contains("submitFeedback")
            && agentSettingsSource.contains("openPrefilledGitHubIssue")
            && agentSettingsSource.contains("github.com/weibei-app/weibei/issues/new")
            && agentSettingsSource.contains("beginShortcutRecording")
            && agentSettingsSource.contains("AppShortcutID")
            && !agentSettingsSource.contains("lock.shield")
            && !agentSettingsSource.contains("copyUserFacingVersionInfo")
            && !agentSettingsSource.contains("笔记预览")
            && !agentSettingsSource.contains("Note Preview")
            && !agentSettingsSource.contains("setNoteRenderMode(.preview)")
            && !commandPaletteSource.contains("笔记预览")
            && !commandPaletteSource.contains("Note Preview")
            && !commandPaletteSource.contains("setNoteRenderMode(.preview)"), "settings: language menu, AionUI-style theme layout cards, editable shortcuts, in-app feedback")
    }
}
