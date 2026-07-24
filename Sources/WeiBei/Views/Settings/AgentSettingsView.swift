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
        }
        .onAppear {
            // First paint only. Provider / profile switches now drive their own fetch
            // from inside the Store (setAgentProviderID / selectAgentCredentialProfile
            // call scheduleModelListRefresh), so the view no longer needs to fan out
            // three onChange hooks — that triple-trigger was the root of the race (S2).
            requestModelListRefresh()
        }
        .sheet(isPresented: $showManualModelEntry) {
            agentManualModelSheet
        }
    }

    // MARK: ①②③④ — the main card

    private var agentServiceCard: some View {
        settingsGroup(store.ui("对话服务", "Chat Service")) {
            // Profile — top-level container. Selecting one swaps the service/key/model
            // below. Always shown (per feedback: hiding it behind "Advanced" was worse).
            agentProfileRow

            // 服务 (provider). Choosing one derives the auth method from its kind.
            settingsRow(title: store.ui("服务", "Service"), detail: "") {
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

            // 认证 — branch on provider kind.
            agentAuthRow

            // 模型 — dropdown backed by the live catalog.
            settingsRow(title: store.ui("模型", "Model"), detail: "") {
                agentModelPicker()
            }

            // Base URL — flat (no longer hidden behind Advanced); only for providers
            // that need it, or once the user has set one.
            if store.agentProviderID.showsBaseURLField || !store.agentBaseURL.isEmpty {
                settingsRow(title: store.ui("Base URL", "Base URL"), detail: "") {
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

            // Region — only for Bedrock.
            if store.agentProviderID == .amazonBedrock {
                settingsRow(title: store.ui("区域", "Region"), detail: "") {
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

            // Quiet reminder — only when attention is needed.
            agentStatusReminder
        }
    }

    // MARK: Profile row (top-level, with inline rename)

    private var agentProfileRow: some View {
        settingsRow(title: store.ui("配置", "Profile"), detail: "") {
            HStack(spacing: 8) {
                if isRenamingActiveProfile {
                    profileRenameField
                } else {
                    // New / delete live inside the menu (low-frequency actions); only
                    // "重命名" stays as a visible button so the row stays calm.
                    compactMenu(activeProfileName) {
                        ForEach(store.agentCredentialProfiles) { profile in
                            Button(profile.name) {
                                store.selectAgentCredentialProfile(profile.id)
                            }
                        }
                        Divider()
                        Button(store.ui("新建配置", "New Profile")) {
                            store.createAgentCredentialProfile()
                        }
                        if store.agentCredentialProfiles.count > 1 {
                            // Destructive: also wipes the profile's Keychain key, so it
                            // only arms the confirmation dialog rather than deleting
                            // outright (see S3).
                            Button(store.ui("删除当前配置", "Delete Current Profile"), role: .destructive) {
                                showDeleteProfileConfirmation = true
                            }
                        }
                    }
                    Button(store.ui("重命名", "Rename")) {
                        profileRenameDraft = activeProfileName
                        isRenamingActiveProfile = true
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
            }
        }
        .confirmationDialog(
            store.ui("删除配置「\(activeProfileName)」？", "Delete profile \"\(activeProfileName)\"?"),
            isPresented: $showDeleteProfileConfirmation,
            titleVisibility: .visible
        ) {
            Button(store.ui("删除配置及其密钥", "Delete profile and its key"), role: .destructive) {
                store.deleteActiveAgentCredentialProfile()
            }
            Button(store.ui("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(store.ui(
                "将删除该配置及其钥匙串中的密钥，此操作不可恢复。",
                "This deletes the profile and its Keychain key. This cannot be undone."
            ))
        }
    }

    private var profileRenameField: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $profileRenameDraft,
                prompt: Text(store.ui("配置名称", "Profile name"))
                    .font(.system(size: 13))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .foregroundColor(WeiBeiTheme.ink)
            .font(.system(size: 13))
            .weibeiInputSurface(active: true, height: 30)
            .frame(width: 140)
            .onSubmit { commitProfileRename() }
            Button(store.ui("确定", "OK")) { commitProfileRename() }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            Button(store.ui("取消", "Cancel")) {
                isRenamingActiveProfile = false
                profileRenameDraft = ""
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
        }
    }

    private func commitProfileRename() {
        let trimmed = profileRenameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.renameActiveAgentCredentialProfile(trimmed)
        }
        isRenamingActiveProfile = false
        profileRenameDraft = ""
    }

    private var activeProfileName: String {
        store.agentCredentialProfiles.first(where: { $0.id == store.activeAgentProfileID })?.name
            ?? store.ui("默认", "Default")
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
        // No long key-help blurb under the field — console button + status notes
        // cover the rare cases that need guidance.
        settingsRow(title: store.ui("密钥", "API Key")) {
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
                // Persist on any change so the key survives a tab switch or window
                // close without the user pressing Return. This is the implicit-save
                // contract the self-check (L2815) expects: no explicit Save button,
                // but the key is never stranded in memory. Keychain writes are local
                // and cheap; saveOpenAIAPIKey cleans + dedups.
                .onChange(of: store.openAIAPIKey) { _, _ in
                    store.saveOpenAIAPIKey()
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
            title: store.ui("订阅登录", "Subscription Login"),
            detail: ""
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
        // Delegates to the Store's single source of truth (see M4).
        store.activeKeyEnvOverride
    }

    private var oauthLinked: Bool {
        store.agentProviderID.kind == .subscription && !oauthService.linkedProviders.isEmpty
    }

    // MARK: Advanced (collapsed) — removed; Base URL / Region now sit flat in the card
    // and Profile lives at the top. Nothing to disclose.

    private var baseURLPlaceholder: String {
        store.agentProviderID == .azureOpenAI
            ? "https://YOUR.openai.azure.com"
            : "https://api.example.com/v1"
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
