import SwiftUI
import WeiBeiCore

// MARK: - 对话服务 card (Settings → 对话)
//
// One decision chain: service → embedded-Pi authentication → embedded-Pi model.

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

            settingsRow(
                title: store.ui("互动界面", "Interactive UI"),
                detail: store.ui(
                    "关闭后只停止新互动界面；Markdown、Mermaid 和已有内容不受影响。",
                    "Disables only new interactive UI. Markdown, Mermaid, and existing content remain available."
                )
            ) {
                settingsSwitch(
                    isOn: Binding(
                        get: { store.agentInteractiveVisualizationsEnabled },
                        set: { store.setAgentInteractiveVisualizationsEnabled($0) }
                    ),
                    accessibilityLabel: store.ui("允许生成互动界面", "Allow interactive UI")
                )
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
                "只删除这组服务与模型选择；内置 Pi 中的登录凭证不受影响。",
                "This only deletes the service and model selection. Credentials in embedded Pi are unchanged."
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
        apiKeyDraft = ""
        store.setAgentProviderID(provider)
        if let firstModel = oauthService.models(providerID: provider.piProviderName).first {
            store.updateModelName(firstModel)
        }
        let authTypes = piAuthTypes(for: provider)
        store.setAgentAuthMethod(
            authTypes.contains(.oauth) && provider.kind == .subscription
                ? .subscription
                : .apiKey
        )
    }

    // MARK: ② Auth

    @ViewBuilder
    private var agentAuthRow: some View {
        if activePiAuthTypes.contains(.oauth), activePiAuthTypes.contains(.apiKey) {
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

    private var agentAPIKeyAuth: some View {
        settingsRow(title: store.ui("密钥", "API Key")) {
            VStack(alignment: .trailing, spacing: 8) {
                SecureField(
                    "",
                    text: $apiKeyDraft,
                    prompt: Text(store.ui("粘贴 API Key", "Paste API key"))
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                .textFieldStyle(.plain)
                .foregroundColor(WeiBeiTheme.ink)
                .focused($focusedField, equals: .apiKey)
                .font(.system(size: 13))
                .weibeiInputSurface(active: focusedField == .apiKey, height: 38)
                .frame(width: SettingsView.controlWidth)
                .onSubmit { saveActiveAPIKey() }

                HStack(spacing: 8) {
                    if oauthService.isConfigured(
                        providerID: store.agentProviderID.piProviderName,
                        type: .apiKey
                    ) {
                        settingsPill(
                            title: store.ui("已保存在内置 Pi", "Stored in embedded Pi"),
                            icon: "checkmark.seal.fill",
                            active: true
                        )
                    }
                    if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(store.ui("保存", "Save")) { saveActiveAPIKey() }
                            .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isLoggingIn))
                    }
                    if !oauthService.isConfigured(
                        providerID: store.agentProviderID.piProviderName,
                        type: .apiKey
                    ) {
                        Button(store.ui("由内置 Pi 配置", "Configure with embedded Pi")) {
                            startGuidedAPIConfiguration()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isLoggingIn))
                    }
                    if oauthService.isConfigured(
                        providerID: store.agentProviderID.piProviderName,
                        type: .apiKey
                    ) {
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
                piManagementPrompt
                if let progress = oauthService.statusMessage, oauthService.isLoggingIn {
                    settingsNote(progress, icon: "arrow.triangle.2.circlepath")
                }
                if let error = oauthService.lastError {
                    settingsNote(error, icon: "exclamationmark.triangle")
                }
            }
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
                piManagementPrompt
                if let progress = oauthService.statusMessage, oauthService.isLoggingIn {
                    settingsNote(progress, icon: "arrow.triangle.2.circlepath")
                }
                if let error = oauthService.lastError {
                    settingsNote(error, icon: "exclamationmark.triangle")
                }
            }
        }
    }

    private var currentOAuthProvider: AgentProviderID? {
        activePiAuthTypes.contains(.oauth) ? store.agentProviderID : nil
    }

    private var activePiAuthTypes: [PiCredentialType] {
        piAuthTypes(for: store.agentProviderID)
    }

    private var activeAgentAuthMethod: AgentAuthMethod {
        if activePiAuthTypes.contains(.oauth), activePiAuthTypes.contains(.apiKey) {
            return store.agentAuthMethod
        }
        return activePiAuthTypes.contains(.oauth) ? .subscription : .apiKey
    }

    private func piAuthTypes(for provider: AgentProviderID) -> [PiCredentialType] {
        if let types = oauthService.catalog?.providers.first(where: {
            $0.id == provider.piProviderName
        })?.authTypes, !types.isEmpty {
            return types
        }
        return provider.kind == .subscription ? [.oauth] : [.apiKey]
    }

    @ViewBuilder
    private var piManagementPrompt: some View {
        if let prompt = oauthService.pendingPrompt {
            settingsNote(prompt.message, icon: "key.horizontal")
            HStack(spacing: 8) {
                if prompt.type == .select {
                    Picker("", selection: $oauthService.promptValue) {
                        ForEach(prompt.options ?? [], id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: SettingsView.controlWidth)
                } else if prompt.type == .secret {
                    SecureField(prompt.placeholder ?? "", text: $oauthService.promptValue)
                        .textFieldStyle(.plain)
                        .weibeiInputSurface(active: true, height: 38)
                        .frame(width: SettingsView.controlWidth)
                        .onSubmit { oauthService.submitPrompt() }
                } else {
                    TextField(prompt.placeholder ?? "", text: $oauthService.promptValue)
                        .textFieldStyle(.plain)
                        .weibeiInputSurface(active: true, height: 38)
                        .frame(width: SettingsView.controlWidth)
                        .onSubmit { oauthService.submitPrompt() }
                }
                Button(store.ui("继续", "Continue")) { oauthService.submitPrompt() }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.promptValue.isEmpty))
            }
        }
    }

    private func saveActiveAPIKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !oauthService.isLoggingIn else { return }
        oauthService.startAPIKeyLogin(
            key,
            provider: store.agentProviderID,
            baseURL: store.agentBaseURL,
            model: store.modelName
        )
    }

    private func startGuidedAPIConfiguration() {
        oauthService.startAPIKeyLogin(
            provider: store.agentProviderID,
            baseURL: store.agentBaseURL,
            model: store.modelName
        )
    }

    private func clearActiveAPICredential() {
        apiKeyDraft = ""
        oauthService.logoutCredential(
            providerID: store.agentProviderID.piProviderName,
            displayName: store.agentProviderID.label(language: store.interfaceLanguage)
        )
    }

    // MARK: Status reminder — only when attention is needed

    /// Quiet by default. Surfaces one short line only when authentication is missing.
    @ViewBuilder
    private var agentStatusReminder: some View {
        if !oauthLinked,
                  activeAgentAuthMethod != .subscription,
                  !oauthService.isConfigured(
                      providerID: store.agentProviderID.piProviderName,
                      type: .apiKey
                  ),
                  apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settingsNote(
                store.ui("尚未配置密钥，对话将无法连接。", "No key configured — chat won't connect."),
                icon: "exclamationmark.triangle"
            )
        }
    }

    private var oauthLinked: Bool {
        guard let provider = currentOAuthProvider else { return false }
        return activeAgentAuthMethod == .subscription && oauthService.isLinked(provider)
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
            TextField(
                "",
                text: Binding(
                    get: { store.modelName },
                    set: { store.updateModelName($0) }
                ),
                prompt: Text(oauthService.models(providerID: store.agentProviderID.piProviderName).first ?? "model-id")
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
