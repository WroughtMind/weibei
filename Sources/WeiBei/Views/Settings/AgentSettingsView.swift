import SwiftUI
import WeiBeiCore

// MARK: - 对话服务 card (Settings → 对话)
//
// One decision chain: service → authentication → model.

extension SettingsView {
    /// Entry point — used by `agentSettings` in WeiBeiApp.swift.
    @ViewBuilder
    func agentSettingsContent() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            agentServiceCard
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
                        ForEach(AgentProviderID.subscriptionProviders.filter(oauthService.isAvailable)) { provider in
                            Button(provider.label(language: store.interfaceLanguage)) {
                                applyProvider(provider)
                            }
                        }
                    }
                    Section(AgentProviderKind.apiKey.label(language: store.interfaceLanguage)) {
                        ForEach(AgentProviderID.apiKeyProviders.filter(oauthService.isAvailable)) { provider in
                            Button(provider.label(language: store.interfaceLanguage)) {
                                applyProvider(provider)
                            }
                        }
                    }
                    Section(AgentProviderKind.localOrCustom.label(language: store.interfaceLanguage)) {
                        ForEach(AgentProviderID.localOrCustomProviders.filter(oauthService.isAvailable)) { provider in
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
                            .foregroundStyle(WeiBeiTheme.placeholderInk)
                    )
                    .textFieldStyle(.plain)
                    .weiBeiText(13)
                    .foregroundColor(WeiBeiTheme.ink)
                    .weiBeiText(13)
                    .weibeiInputSurface(active: false, height: 38)
                    .frame(width: SettingsView.controlWidth)
                }
            }

            // Quiet reminder — only when attention is needed.
            agentStatusReminder
        }
    }

    // MARK: Profile row (top-level, with inline rename)

    private var agentProfileRow: some View {
        settingsRow(title: store.ui("配置", "Profile"), detail: "") {
            if isRenamingActiveProfile {
                profileRenameField
            } else {
                // New / rename / delete all live in the menu — low-frequency, keeps the row calm.
                compactMenu(activeProfileName) {
                    ForEach(store.agentCredentialProfiles) { profile in
                        Button(profile.name) {
                            apiKeyDraft = ""
                            store.selectAgentCredentialProfile(profile.id)
                        }
                    }
                    Divider()
                    Button(store.ui("新建配置", "New Profile")) {
                        store.createAgentCredentialProfile()
                    }
                    Button(store.ui("重命名", "Rename")) {
                        profileRenameDraft = activeProfileName
                        isRenamingActiveProfile = true
                    }
                    if store.agentCredentialProfiles.count > 1 {
                        Button(store.ui("删除当前配置", "Delete Current Profile"), role: .destructive) {
                            showDeleteProfileConfirmation = true
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            store.ui("删除配置「\(activeProfileName)」？", "Delete profile \"\(activeProfileName)\"?"),
            isPresented: $showDeleteProfileConfirmation,
            titleVisibility: .visible
        ) {
            Button(store.ui("删除配置", "Delete profile"), role: .destructive) {
                store.deleteActiveAgentCredentialProfile()
            }
            Button(store.ui("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(store.ui(
                "只删除这组服务与模型选择；魏碑保存的登录信息不受影响。",
                "This only deletes the service and model selection. Sign-in information saved by WeiBei is unchanged."
            ))
        }
    }

    private var profileRenameField: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $profileRenameDraft,
                prompt: Text(store.ui("配置名称", "Profile name"))
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .weiBeiText(13)
            .foregroundColor(WeiBeiTheme.ink)
            .weiBeiText(13)
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
        apiKeyDraft = ""
        store.setAgentProviderID(provider)
        if let firstModel = oauthService.models(provider: provider).first {
            store.updateModelName(firstModel)
        }
        let authTypes = authTypes(for: provider)
        store.setAgentAuthMethod(
            authTypes.contains(.oauth) && provider.kind == .subscription
                ? .subscription
                : .apiKey
        )
    }

    // MARK: ② Auth

    @ViewBuilder
    private var agentAuthRow: some View {
        if activeAuthTypes.contains(.oauth), activeAuthTypes.contains(.apiKey) {
            settingsRow(title: store.ui("认证方式", "Authentication"), detail: "") {
                compactMenu(activeAgentAuthMethod.label(language: store.interfaceLanguage)) {
                    Button(AgentAuthMethod.subscription.label(language: store.interfaceLanguage)) {
                        store.setAgentAuthMethod(.subscription)
                    }
                    Button(AgentAuthMethod.apiKey.label(language: store.interfaceLanguage)) {
                        store.setAgentAuthMethod(.apiKey)
                    }
                }
            }
        }
        switch activeAgentAuthMethod {
        case .subscription:
            agentSubscriptionAuth
        case .apiKey:
            agentAPIKeyAuth
        }
    }

    @ViewBuilder
    private var agentAPIKeyAuth: some View {
        if oauthService.isAvailable(store.agentProviderID) {
            agentSimpleAPIKeyAuth
        } else {
            settingsRow(title: store.ui("认证", "Authentication")) {
                settingsNote(
                    store.ui("该服务尚未接入原生运行时。", "This service is not available in the native runtime yet."),
                    icon: "exclamationmark.triangle"
                )
            }
        }
    }

    private var agentSimpleAPIKeyAuth: some View {
        settingsRow(title: store.ui("密钥", "API Key")) {
            let hasStoredCredential = oauthService.isConfigured(
                providerID: activeCredentialProviderID,
                type: .apiKey
            )
            VStack(alignment: .trailing, spacing: 8) {
                SecureField(
                    "",
                    text: $apiKeyDraft,
                    prompt: Text(store.ui("粘贴 API Key", "Paste API key"))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                .textFieldStyle(.plain)
                .weiBeiText(13)
                .foregroundColor(WeiBeiTheme.ink)
                .focused($focusedField, equals: .apiKey)
                .weiBeiText(13)
                .weibeiInputSurface(active: focusedField == .apiKey, height: 38)
                .frame(width: SettingsView.controlWidth)
                .onSubmit { saveActiveAPIKey() }

                HStack(spacing: 8) {
                    if activeAPICredentialIsConfigured {
                        settingsPill(
                            title: store.ui("已保存", "Saved"),
                            icon: "checkmark.seal.fill",
                            active: true
                        )
                    }
                    if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(store.ui("保存", "Save")) { saveActiveAPIKey() }
                            .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isLoggingIn))
                    }
                    if hasStoredCredential {
                        Button(store.ui("清除", "Clear")) { clearActiveAPICredential() }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                    if AgentProviderConsoleLinks.loginURL(for: store.agentProviderID) != nil
                        || AgentProviderConsoleLinks.accountURL(for: store.agentProviderID) != nil {
                        Button(store.ui("打开控制台", "Open Console")) {
                            store.openAgentProviderConsole(login: false)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                if let progress = oauthService.statusMessage,
                    oauthService.isLoggingIn {
                    settingsNote(progress, icon: "arrow.triangle.2.circlepath")
                }
                if let error = oauthService.lastError {
                    settingsNote(
                        store.ui(error.chinese, error.english),
                        icon: "exclamationmark.triangle"
                    )
                }
            }
            .animation(WeiBeiMotion.reveal, value: oauthService.isLoggingIn)
        }
    }

    private var agentSubscriptionAuth: some View {
        settingsRow(
            title: store.ui("订阅登录", "Subscription Login"),
            detail: ""
        ) {
            VStack(alignment: .trailing, spacing: 8) {
                let provider = currentOAuthProvider
                HStack(spacing: 8) {
                    if let provider {
                        let requiresLogin = store.agentAuthenticationStatus.requiresLogin(for: provider)
                        if oauthService.isLinked(provider) || requiresLogin {
                            settingsPill(
                                title: requiresLogin
                                    ? store.ui("需要重新登录", "Sign in again")
                                    : store.ui("已连接", "Linked"),
                                icon: requiresLogin
                                    ? "exclamationmark.triangle.fill"
                                    : "checkmark.seal.fill",
                                active: !requiresLogin
                            )
                        }
                        Button {
                            guard !oauthService.isLoggingIn else { return }
                            oauthService.startLogin(provider)
                        } label: {
                            Text(
                                oauthService.isLoggingIn
                                    ? store.ui("登录中…", "Signing in…")
                                    : oauthService.isLinked(provider)
                                        ? store.ui("重新登录", "Sign in again")
                                        : store.ui("OAuth 登录", "OAuth sign in")
                            )
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isLoggingIn))
                        if oauthService.isLinked(provider) {
                            Button(store.ui("断开", "Disconnect")) {
                                oauthService.logout(provider)
                            }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                    }
                    if oauthService.isLoggingIn {
                        Button(store.ui("取消", "Cancel")) { oauthService.cancelLogin() }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                    }
                }
                if let progress = oauthService.statusMessage,
                    oauthService.isLoggingIn {
                    settingsNote(progress, icon: "arrow.triangle.2.circlepath")
                }
                if let error = oauthService.lastError {
                    settingsNote(
                        store.ui(error.chinese, error.english),
                        icon: "exclamationmark.triangle"
                    )
                }
            }
            .animation(WeiBeiMotion.reveal, value: oauthService.isLoggingIn)
        }
    }

    private var currentOAuthProvider: AgentProviderID? {
        activeAuthTypes.contains(.oauth) ? store.agentProviderID : nil
    }

    private var activeAuthTypes: [AgentCredentialType] {
        authTypes(for: store.agentProviderID)
    }

    private var activeAgentAuthMethod: AgentAuthMethod {
        AgentProviderReadiness.effectiveAuthMethod(for: store)
    }

    private func authTypes(for provider: AgentProviderID) -> [AgentCredentialType] {
        AgentProviderReadiness.authTypes(for: provider)
    }

    /// The runtime's step question, styled like a quiet right-aligned field label —
    /// not a warning note — above a control that matches the rest of the card.
    private func saveActiveAPIKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !oauthService.isLoggingIn else { return }
        oauthService.startAPIKeyLogin(
            key,
            provider: store.agentProviderID,
            baseURL: store.agentBaseURL
        )
    }

    private func clearActiveAPICredential() {
        apiKeyDraft = ""
        oauthService.logoutCredential(providerID: activeCredentialProviderID)
    }

    // MARK: Status reminder — only when attention is needed

    /// Quiet by default. Surfaces one short line only when authentication is missing,
    /// and stays hidden while a configuration flow is already in progress.
    @ViewBuilder
    private var agentStatusReminder: some View {
        if !oauthLinked,
                  activeAgentAuthMethod != .subscription,
                  !activeAPICredentialIsConfigured,
                  apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !oauthService.isLoggingIn {
            if hasStaleAzureCredential {
                settingsNote(
                    store.ui(
                        "Azure 服务地址已变更，或旧密钥尚未绑定地址。为避免把旧密钥发给新地址，请确认当前地址后重新输入一次密钥。",
                        "The Azure endpoint changed, or the stored key predates endpoint binding. Confirm the current endpoint and enter the key again."
                    ),
                    icon: "exclamationmark.triangle"
                )
            } else if hasLegacyEndpointCredential {
                settingsNote(
                    store.ui(
                        "检测到旧版通用密钥。为避免把它发给错误服务，魏碑不会自动搬移；请为当前地址重新输入一次密钥。",
                        "A legacy shared key was found. WeiBei will not move it to a new endpoint automatically; enter the key once for this address."
                    ),
                    icon: "exclamationmark.triangle"
                )
            } else if !oauthService.isAvailable(store.agentProviderID) {
                settingsNote(
                    store.ui("该服务尚未接入原生运行时。", "This service is not available in the native runtime yet."),
                    icon: "exclamationmark.triangle"
                )
            } else {
                settingsNote(
                    store.ui("尚未配置密钥，对话将无法连接。", "No key configured — chat won't connect."),
                    icon: "exclamationmark.triangle"
                )
            }
        }
    }

    private var hasLegacyEndpointCredential: Bool {
        guard store.agentProviderID == .custom || store.agentProviderID == .llamaCpp else {
            return false
        }
        return oauthService.isConfigured(
            providerID: store.agentProviderID.credentialProviderID,
            type: .apiKey
        )
    }

    private var activeAPICredentialIsConfigured: Bool {
        AgentProviderReadiness.hasActiveAPICredential(for: store)
    }

    private var hasStaleAzureCredential: Bool {
        store.agentProviderID == .azureOpenAI
            && oauthService.isConfigured(
                providerID: AgentProviderID.azureOpenAI.credentialProviderID,
                type: .apiKey
            )
            && !activeAPICredentialIsConfigured
    }

    private var oauthLinked: Bool {
        AgentProviderReadiness.isSubscriptionLinked(for: store)
    }

    // MARK: Advanced (collapsed) — removed; Base URL sits flat in the card and
    // Profile lives at the top. Nothing to disclose.

    private var baseURLPlaceholder: String {
        store.agentProviderID == .azureOpenAI
            ? "https://YOUR.openai.azure.com"
            : "https://api.example.com/v1"
    }

    // MARK: Manual model entry sheet

    private var agentManualModelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.ui("手动输入模型 ID", "Enter model id"))
                .weiBeiText(15, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
            TextField(
                "",
                text: Binding(
                    get: { store.modelName },
                    set: { store.updateModelName($0) }
                ),
                prompt: Text(oauthService.models(provider: store.agentProviderID).first ?? "model-id")
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .weiBeiText(13)
            .foregroundColor(WeiBeiTheme.ink)
            .weiBeiText(13)
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
