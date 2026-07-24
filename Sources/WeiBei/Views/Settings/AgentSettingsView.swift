import SwiftUI
import WeiBeiCore

// MARK: - 对话服务 card (Settings → 对话)
//
// Replaces the legacy four parallel cards (连接配置 / 接入方式 / 提供商与模型 / 对话入口) with
// one linear decision chain: 服务 → 认证 → 模型 → 状态. The auth method is now derived
// from the provider kind (no separate toggle), OAuth collapses to a single login button,
// and the model field becomes a dropdown fed by `AgentModelListService`. Advanced options
// (Base URL, Bedrock region, multiple profiles) live in a collapsed disclosure group.
//
// This view is an extension of `SettingsView` so it can reuse the shared Settings row /
// group / pill / menu primitives defined in WeiBeiApp.swift.

extension SettingsView {
    /// Entry point — used by `agentSettings` in WeiBeiApp.swift.
    @ViewBuilder
    func agentSettingsContent() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            agentServiceCard
            agentAdvancedSection
            agentEntryCard
        }
        .onAppear {
            requestModelListRefresh()
        }
        .onChange(of: store.agentProviderID) { _, _ in
            requestModelListRefresh()
        }
        .sheet(isPresented: $showManualModelEntry) {
            agentManualModelSheet
        }
    }

    // MARK: ①②③④ — the main card

    private var agentServiceCard: some View {
        settingsGroup(store.ui("对话服务", "Chat Service")) {
            // ① 服务 (provider). Choosing one derives the auth method from its kind,
            // eliminating the old redundant "接入方式" toggle.
            settingsRow(
                title: store.ui("① 服务", "① Service"),
                detail: store.ui("选择对话所用的提供商。", "Pick the provider for chat.")
            ) {
                compactMenu(store.agentProviderID.label(language: store.interfaceLanguage)) {
                    Section(AgentProviderKind.subscription.label(language: store.interfaceLanguage)) {
                        ForEach(AgentProviderID.subscriptionProviders) { provider in
                            Button(provider.label(language: store.interfaceLanguage)) {
                                applyProvider(provider)
                            }
                        }
                    }
                    Section(AgentProviderKind.apiKey.label(language: store.interfaceLanguage)) {
                        ForEach(AgentProviderID.apiKeyProviders) { provider in
                            Button(provider.label(language: store.interfaceLanguage)) {
                                applyProvider(provider)
                            }
                        }
                    }
                    Section(AgentProviderKind.localOrCustom.label(language: store.interfaceLanguage)) {
                        ForEach(AgentProviderID.localOrCustomProviders) { provider in
                            Button(provider.label(language: store.interfaceLanguage)) {
                                applyProvider(provider)
                            }
                        }
                    }
                }
            }

            // ② 认证 — branch on provider kind.
            agentAuthRow

            // ③ 模型 — dropdown backed by the live catalog. No detail line: the picker
            // itself communicates listing state, so a second line of help text is noise.
            settingsRow(
                title: store.ui("③ 模型", "③ Model"),
                detail: ""
            ) {
                agentModelPicker()
            }

            // Status reminder — only shown when something needs attention (no key,
            // or an env-var override is silently taking effect). Stays quiet otherwise.
            agentStatusReminder
        }
    }

    private func applyProvider(_ provider: AgentProviderID) {
        store.setAgentProviderID(provider)
        // Derive auth method from kind (replaces the separate "接入方式" card state).
        store.setAgentAuthMethod(provider.kind == .subscription ? .subscription : .apiKey)
    }

    // MARK: ② Auth

    @ViewBuilder
    private var agentAuthRow: some View {
        switch store.agentProviderID.kind {
        case .subscription:
            agentSubscriptionAuth
        case .apiKey, .localOrCustom:
            agentAPIKeyAuth
        }
    }

    private var agentAPIKeyAuth: some View {
        settingsRow(
            title: store.ui("② 密钥", "② API Key"),
            detail: AgentProviderConsoleLinks.keyHelp(language: store.interfaceLanguage, provider: store.agentProviderID)
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                SecureField(
                    "",
                    text: $store.openAIAPIKey,
                    prompt: Text(store.ui("粘贴 API Key", "Paste API key"))
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                .textFieldStyle(.plain)
                .foregroundColor(WeiBeiTheme.ink)
                .focused($focusedField, equals: .apiKey)
                .font(.system(size: 13))
                .weibeiInputSurface(active: focusedField == .apiKey, height: 38)
                .frame(width: 250)
                .onSubmit { store.saveOpenAIAPIKey() }
                .onChange(of: focusedField) { _, field in
                    if field != .apiKey { store.saveOpenAIAPIKey() }
                }

                HStack(spacing: 8) {
                    if !store.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        settingsPill(title: store.ui("已配置", "Configured"), icon: "checkmark.seal.fill", active: true)
                    }
                    Button(store.ui("清除", "Clear")) { store.clearOpenAIAPIKey() }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    if AgentProviderConsoleLinks.loginURL(for: store.agentProviderID) != nil
                        || AgentProviderConsoleLinks.accountURL(for: store.agentProviderID) != nil {
                        Button(store.ui("打开控制台", "Open Console")) {
                            store.openAgentProviderConsole(login: false)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
            }
        }
    }

    // OAuth collapsed to a single button for the *current* subscription provider,
    // instead of three side-by-side providers.
    private var agentSubscriptionAuth: some View {
        settingsRow(
            title: store.ui("② 订阅登录", "② Subscription Login"),
            detail: store.ui("浏览器登录后自动使用。", "Auto-used after browser sign-in.")
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                let provider = currentSubscriptionProvider
                HStack(spacing: 8) {
                    if let provider, oauthService.isLinked(provider) {
                        settingsPill(title: store.ui("已连接", "Linked"), icon: "checkmark.seal.fill", active: true)
                    }
                    if let provider, provider.supportsInAppOAuth {
                        Button {
                            guard !oauthService.isLoggingIn else { return }
                            oauthService.startLogin(provider)
                        } label: {
                            Text(
                                oauthService.isLoggingIn
                                    ? store.ui("登录中…", "Signing in…")
                                    : store.ui("OAuth 登录", "OAuth sign in")
                            )
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isLoggingIn))
                    } else {
                        // Copilot: in-app OAuth unsupported; show guidance.
                        Button(store.ui("查看登录说明", "Show login help")) {
                            store.openAIKeyStatus = currentSubscriptionHelpText
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    if oauthService.isLoggingIn {
                        Button(store.ui("取消", "Cancel")) { oauthService.cancelLogin() }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                if let progress = oauthService.statusMessage {
                    settingsNote(progress, icon: "arrow.triangle.2.circlepath")
                }
                if let error = oauthService.lastError {
                    settingsNote(error, icon: "exclamationmark.triangle")
                }
            }
        }
    }

    private var currentSubscriptionProvider: PiSubscriptionProvider? {
        PiSubscriptionProvider(rawValue: store.agentProviderID.rawValue)
    }

    private var currentSubscriptionHelpText: String {
        currentSubscriptionProvider?.detail(language: store.interfaceLanguage)
            ?? store.ui("请在终端运行 pi 后执行对应 /login。", "Run pi in a terminal, then the matching /login.")
    }

    // MARK: Status reminder — only when attention is needed

    /// Quiet by default. Surfaces one short line only when something needs the user's
    /// attention: the key is missing, or an env-var override is silently in effect (so
    /// the field they're editing wouldn't actually take). Replaces the old 5-pill bar
    /// that piled every status into a noisy row.
    @ViewBuilder
    private var agentStatusReminder: some View {
        if !envKeyOverride.isEmpty {
            settingsNote(
                store.ui("由环境变量 \(envKeyOverride) 生效，此处填写不会覆盖。", "Env \(envKeyOverride) is active; this field won't override it."),
                icon: "lock.fill"
            )
        } else if !oauthLinked,
                  store.agentProviderID.kind != .subscription,
                  store.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settingsNote(
                store.ui("尚未配置密钥，对话将无法连接。", "No key configured — chat won't connect."),
                icon: "exclamationmark.triangle"
            )
        }
    }

    private var envKeyOverride: String {
        let envName = store.agentProviderID.environmentAPIKeyName
        if !(ProcessInfo.processInfo.environment[envName] ?? "").isEmpty { return envName }
        if store.agentProviderID != .openai,
           !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty {
            return "OPENAI_API_KEY"
        }
        return ""
    }

    private var oauthLinked: Bool {
        store.agentProviderID.kind == .subscription && !oauthService.linkedProviders.isEmpty
    }

    // MARK: Advanced (collapsed)

    private var agentAdvancedSection: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(spacing: 0) {
                // Base URL — shown for custom / llama.cpp / azure, or if the user set one.
                if store.agentProviderID.showsBaseURLField || !store.agentBaseURL.isEmpty {
                    settingsRow(
                        title: store.ui("Base URL", "Base URL"),
                        detail: store.ui(
                            "自定义 / llama.cpp 写入 Pi models.json；Azure 填资源 endpoint。",
                            "Custom / llama.cpp write Pi models.json; Azure uses the resource endpoint."
                        )
                    ) {
                        TextField(
                            "",
                            text: Binding(
                                get: { store.agentBaseURL },
                                set: { store.updateAgentBaseURL($0) }
                            ),
                            prompt: Text(baseURLPlaceholder)
                                .font(.system(size: 13))
                                .foregroundStyle(WeiBeiTheme.placeholderInk)
                        )
                        .textFieldStyle(.plain)
                        .foregroundColor(WeiBeiTheme.ink)
                        .font(.system(size: 13))
                        .weibeiInputSurface(active: false, height: 38)
                        .frame(width: 280)
                    }
                }

                // Bedrock region — only for Amazon Bedrock.
                if store.agentProviderID == .amazonBedrock {
                    settingsRow(
                        title: store.ui("区域", "Region"),
                        detail: store.ui("Bedrock 列出模型所需的 AWS 区域。", "AWS region for Bedrock model listing.")
                    ) {
                        TextField(
                            "",
                            text: Binding(
                                get: { store.bedrockRegion },
                                set: {
                                    store.bedrockRegion = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                    requestModelListRefresh()
                                }
                            ),
                            prompt: Text("us-east-1").font(.system(size: 13)).foregroundStyle(WeiBeiTheme.placeholderInk)
                        )
                        .textFieldStyle(.plain)
                        .foregroundColor(WeiBeiTheme.ink)
                        .font(.system(size: 13))
                        .weibeiInputSurface(active: false, height: 38)
                        .frame(width: 180)
                    }
                }

                // Multiple profiles — only surfaces controls when there is >1.
                settingsRow(
                    title: store.ui("配置", "Profile"),
                    detail: store.ui("可保存多套提供商与密钥，随时切换。", "Save multiple provider + key sets and switch anytime.")
                ) {
                    HStack(spacing: 8) {
                        compactMenu(
                            store.agentCredentialProfiles.first(where: { $0.id == store.activeAgentProfileID })?.name
                                ?? store.ui("默认", "Default")
                        ) {
                            ForEach(store.agentCredentialProfiles) { profile in
                                Button(profile.name) {
                                    store.selectAgentCredentialProfile(profile.id)
                                }
                            }
                        }
                        Button(store.ui("新建", "New")) {
                            store.createAgentCredentialProfile()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                        if store.agentCredentialProfiles.count > 1 {
                            Button(store.ui("删除", "Delete")) {
                                store.deleteActiveAgentCredentialProfile()
                            }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                    }
                }
            }
        } label: {
            sectionTitle(store.ui("高级（Base URL / 区域 / 多配置）", "Advanced (Base URL / Region / Profiles)"))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(WeiBeiTheme.paperRaised.opacity(store.appearanceMode == .inkstone ? 0.16 : 0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(WeiBeiTheme.hairline.opacity(0.34), lineWidth: 1)
        }
    }

    private var baseURLPlaceholder: String {
        store.agentProviderID == .azureOpenAI
            ? "https://YOUR.openai.azure.com"
            : "https://api.example.com/v1"
    }

    // MARK: Entry card (kept as-is, read-only surface pill)

    private var agentEntryCard: some View {
        settingsGroup(store.ui("对话入口", "Chat Entry")) {
            settingsRow(
                title: store.ui("入口说明", "Entry Notes"),
                detail: store.ui("完整对话在主栏与沉浸对话；选区轻提示可 ⌃⌥0 隐藏。", "Full chat lives in the agent pane and immersive conversation; hide selection prompt with ⌃⌥0.")
            ) {
                settingsPill(
                    title: store.agentSurface.label(language: store.interfaceLanguage),
                    icon: "bubble.left.and.bubble.right",
                    active: store.agentSurface == .selectionFloat
                )
            }
        }
    }

    // MARK: Manual model entry sheet

    private var agentManualModelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.ui("手动输入模型 ID", "Enter model id"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
            TextField(
                "",
                text: Binding(
                    get: { store.modelName },
                    set: { store.updateModelName($0) }
                ),
                prompt: Text(store.agentProviderID.defaultModelHint)
                    .font(.system(size: 13))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .foregroundColor(WeiBeiTheme.ink)
            .font(.system(size: 13))
            .weibeiInputSurface(active: true, height: 38)
            HStack {
                Spacer()
                Button(store.ui("完成", "Done")) { showManualModelEntry = false }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(WeiBeiTheme.paper)
    }
}
