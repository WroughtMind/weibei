import SwiftUI
import WeiBeiCore

/// 聊天与设置共用的连接表单。输入保留到连接完成；浏览器取消不会留下空配置。
@MainActor
struct AgentConnectionSetupView: View {
#if WEIBEI_ACCEPTANCE_CHECKS
    private(set) static var checkLastFinishState: [String: String]?
#endif
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var accounts = AgentAccountService.shared
    // 表单的模型名单独立于设置卡片和其他聊天窗口的刷新。
    @StateObject private var modelCatalog = AgentAccountService.connectionDraft()
    @State private var selectedProvider: AgentProviderID?
    @State private var usesAccount = true
    @State private var keyDraft = ""
    @State private var endpointDraft = ""
    @State private var errorText: String?
    @State private var loginAttemptID: UUID?
    @State private var profileID: UUID?
    @State private var pendingProfile: AgentCredentialProfile?
    @State private var isFinishing = false
    @State private var originatingConnectionKey: String?
    @State private var manualModel = ""
    @State private var showsManualModel = false
    let replacementProfileID: UUID?
    let onConnected: () -> Void
    let onCancel: () -> Void

    init(existingProfileID: UUID? = nil, replacementProfileID: UUID? = nil, provider: AgentProviderID? = nil,
         authMethod: AgentAuthMethod = .subscription, baseURL: String = "",
         onConnected: @escaping () -> Void, onCancel: @escaping () -> Void) {
        _profileID = State(initialValue: existingProfileID)
        _selectedProvider = State(initialValue: provider)
        _usesAccount = State(initialValue: authMethod == .subscription)
        _endpointDraft = State(initialValue: baseURL)
        self.replacementProfileID = replacementProfileID ?? existingProfileID
        self.onConnected = onConnected
        self.onCancel = onCancel
    }

    private var providers: [AgentProviderID] {
        let available = AgentProviderID.allCases.filter(accounts.isAvailable)
        return available.filter { accounts.authTypes(for: $0).contains(.oauth) }
            + available.filter { !accounts.authTypes(for: $0).contains(.oauth) }
    }

    private var provider: AgentProviderID? { selectedProvider ?? providers.first }
    private var authTypes: [AgentCredentialType] { provider.map(accounts.authTypes) ?? [] }
    private var subscription: Bool {
        authTypes.contains(.oauth) && (!authTypes.contains(.apiKey) || usesAccount)
    }
    private var ownsLogin: Bool {
        loginAttemptID != nil && accounts.loginTargetProfileID == loginAttemptID
    }
    private var profile: AgentCredentialProfile? {
        pendingProfile ?? store.agentCredentialProfiles.first { $0.id == profileID }
    }
    private var activeConnectionKey: String {
        store.activeAgentProfileID.uuidString + store.agentProviderID.rawValue
            + store.agentAuthMethod.rawValue + store.agentBaseURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(store.ui("连接模型服务", "Connect a Model Service"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.ui("收起连接", "Close connection setup"))
                .accessibilityIdentifier("connection-setup-close")
            }

            if let profile {
                modelChoice(profile)
            } else {
                credentials
            }
        }
        .autocorrectionDisabled(true)
#if os(iOS)
        .textInputAutocapitalization(.never)
#endif
        .foregroundStyle(WeiBeiTheme.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WeiBeiTheme.hairline.opacity(0.42)))
        .onAppear {
            if originatingConnectionKey == nil { originatingConnectionKey = activeConnectionKey }
            if let profile { refreshModels(profile) }
        }
        .onDisappear { if ownsLogin { accounts.cancelLogin() } }
        .onChange(of: activeConnectionKey) { _, _ in
            if !isFinishing { cancel() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agent-connection-setup")
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 12) {
            select(provider?.label(language: store.interfaceLanguage) ?? "—") {
                ForEach(providers, id: \.self) { item in
                    Button(item.label(language: store.interfaceLanguage)) {
                        selectedProvider = item
                        keyDraft = ""
                        endpointDraft = ""
                        errorText = nil
                        loginAttemptID = nil
                        usesAccount = true
                    }
                }
            }
            .disabled(accounts.isLoggingIn)
            .accessibilityIdentifier("connection-setup-provider")

            if authTypes.contains(.oauth), authTypes.contains(.apiKey) {
                select(subscription ? store.ui("账号登录", "Account sign-in") : store.ui("API 密钥", "API key")) {
                    Button(store.ui("账号登录", "Account sign-in")) { usesAccount = true }
                    Button(store.ui("API 密钥", "API key")) { usesAccount = false }
                }
                .disabled(accounts.isLoggingIn)
            }
            if !subscription {
                SecureField(store.ui("粘贴 API Key", "Paste API key"), text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("connection-setup-key")
                    .onSubmit(connect)
            }
            if provider?.showsBaseURLField == true {
                TextField(store.ui("服务地址", "Service URL"), text: $endpointDraft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(accounts.isLoggingIn)
                    .accessibilityIdentifier("connection-setup-endpoint")
            }

            if let errorText {
                failureText(errorText)
            } else if loginAttemptID != nil, !accounts.isLoggingIn, let error = accounts.lastError {
                failureText(store.ui(error.chinese, error.english))
            }
            if ownsLogin {
                if let progress = accounts.statusMessage {
                    Text(store.ui(progress.chinese, progress.english))
                        .weiBeiText(11.5).foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                if let code = accounts.authorizationCode {
                    Text(code).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
                }
                if let url = accounts.authorizationURL {
                    Link(store.ui("打开授权页", "Open authorization page"), destination: url)
                }
            }
            HStack {
                Spacer()
                if ownsLogin {
                    Button(store.ui("取消登录", "Cancel sign-in")) { accounts.cancelLogin() }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    ProgressView().controlSize(.small)
                } else {
                    Button(subscription ? store.ui("浏览器登录", "Sign in with browser") : store.ui("连接", "Connect"), action: connect)
                        .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                        .disabled(accounts.isLoggingIn || (!subscription && keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityIdentifier("connection-setup-connect")
                }
            }
        }
    }

    private func modelChoice(_ profile: AgentCredentialProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.ui("选择模型后继续当前对话。", "Choose a model to continue your conversation."))
                .weiBeiText(12).foregroundStyle(WeiBeiTheme.secondaryInk)
            if modelCatalog.isRefreshingModels {
                ProgressView(store.ui("正在获取模型…", "Loading models…")).controlSize(.small)
            }
            let models = modelCatalog.models(provider: profile.provider)
            if !models.isEmpty {
                select(store.ui("选择模型…", "Choose a model…")) {
                    ForEach(models, id: \.self) { model in
                        Button(model) { finish(profile, model: model) }
                    }
                }
                .accessibilityIdentifier("connection-setup-model")
            }
            if let message = modelListMessage {
                Text(message)
                    .weiBeiText(11.5).foregroundStyle(WeiBeiTheme.secondaryInk)
                    .accessibilityIdentifier("connection-setup-model-message")
            }
            if let errorText { failureText(errorText) }
            if showsManualModel {
                HStack {
                    TextField(store.ui("模型 ID", "Model ID"), text: $manualModel)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("connection-setup-manual-model")
                        .onSubmit { finish(profile, model: manualModel) }
                    Button(store.ui("使用", "Use")) { finish(profile, model: manualModel) }
                        .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                        .disabled(manualModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("connection-setup-use-model")
                }
            }
            HStack {
                Button(store.ui("刷新名单", "Refresh models")) { refreshModels(profile) }
                    .disabled(modelCatalog.isRefreshingModels)
                if !showsManualModel {
                    Button(store.ui("手动输入模型 ID", "Enter model ID")) { showsManualModel = true }
                        .accessibilityIdentifier("connection-setup-enter-model")
                }
                Spacer()
                Button(store.ui("更改连接", "Change connection")) {
                    selectedProvider = profile.provider
                    usesAccount = profile.authMethod == .subscription
                    endpointDraft = profile.baseURL
                    profileID = nil
                    pendingProfile = nil
                    loginAttemptID = nil
                    manualModel = ""
                    showsManualModel = false
                    errorText = nil
                }
                .accessibilityIdentifier("connection-setup-change")
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
            .weiBeiText(11.5)
        }
    }

    private var modelListMessage: String? {
        switch modelCatalog.modelListFailure {
        case .rejected, .missingCredential:
            return store.ui("服务商未接受这组凭据，请更改连接后重试。", "The provider did not accept these credentials. Change the connection and retry.")
        case .signInExpired:
            return store.ui("登录已失效，请更改连接并重新登录。", "Your sign-in has expired. Change the connection and sign in again.")
        case .missingBaseURL:
            return store.ui("服务地址不完整，请更改连接后重试。", "The service URL is incomplete. Change the connection and retry.")
        default:
            return modelCatalog.modelListMessage.map { store.ui($0.chinese, $0.english) }
        }
    }

    private func failureText(_ text: String) -> some View {
        Text(text).weiBeiText(11.5).foregroundStyle(WeiBeiTheme.cinnabar)
            .accessibilityIdentifier("connection-setup-error")
    }

    private func select<MenuContent: View>(_ title: String, @ViewBuilder content: () -> MenuContent) -> some View {
        Menu(content: content) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(WeiBeiTheme.paper))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WeiBeiTheme.hairline.opacity(0.85)))
        }.buttonStyle(.plain)
    }

    private func connect() {
        guard let provider, !accounts.isLoggingIn else { return }
        let endpoint: AgentProviderEndpoint
        do {
            endpoint = try AgentProviderEndpoint(provider: provider, baseURL: endpointDraft)
        } catch {
            errorText = store.ui("请填写有效的服务地址。连接尚未保存。", "Enter a valid service URL. The connection has not been saved.")
            return
        }
        errorText = nil
        let id = UUID()
        if subscription {
            let credentialStore: NativeAgentCredentialStore
            do { credentialStore = try modelCatalog.connectionCredentialStore() }
            catch {
                errorText = store.ui("无法暂存登录信息，请重试。", "Could not prepare sign-in storage. Please retry.")
                return
            }
            let loginConnectionKey = activeConnectionKey
            loginAttemptID = id
            accounts.startLogin(provider, language: store.interfaceLanguage, targetProfileID: id, credentialStore: credentialStore) { completedProvider, completedID in
                guard activeConnectionKey == loginConnectionKey, loginAttemptID == completedID else { return }
                prepareModelChoice(id: completedID, provider: completedProvider, authMethod: .subscription, endpoint: endpoint)
            }
        } else if modelCatalog.startAPIKeyLogin(keyDraft, provider: provider, baseURL: endpoint.baseURL ?? "") {
            prepareModelChoice(id: id, provider: provider, authMethod: .apiKey, endpoint: endpoint)
        } else if let error = modelCatalog.lastError {
            errorText = store.ui(error.chinese, error.english)
        }
    }

    private func prepareModelChoice(id: UUID, provider: AgentProviderID, authMethod: AgentAuthMethod, endpoint: AgentProviderEndpoint) {
        let existing = store.agentCredentialProfiles.first {
            $0.id == replacementProfileID && $0.provider == provider
                && (try? AgentProviderEndpoint(provider: $0.provider, baseURL: $0.baseURL)) == endpoint
        }
        let profile = AgentCredentialProfile(id: existing?.id ?? id, name: existing?.name ?? "", provider: provider,
                                             authMethod: authMethod, baseURL: endpoint.baseURL ?? "")
        pendingProfile = profile
        refreshModels(profile)
    }

    private func refreshModels(_ profile: AgentCredentialProfile) {
        do {
            // 仅换模型时沿真实凭据查询和续期，不复制或提交旧凭据快照。
            let savedCredentials = try pendingProfile == nil ? NativeAgentCredentialStore.defaultStore() : nil
            modelCatalog.refreshModels(provider: profile.provider, baseURL: profile.baseURL,
                                       authMethod: profile.authMethod, credentialStore: savedCredentials)
        } catch {
            errorText = store.ui("无法读取这组凭据，请更改连接后重试。", "Could not read these credentials. Change the connection and retry.")
        }
    }

    private func finish(_ profile: AgentCredentialProfile, model: String) {
        let cleaned = model.trimmingCharacters(in: .whitespacesAndNewlines)
#if WEIBEI_ACCEPTANCE_CHECKS
        Self.checkLastFinishState = [
            "phase": "action_received", "has_model": String(!cleaned.isEmpty),
            "already_finishing": String(isFinishing),
            "connection_unchanged": String(originatingConnectionKey == activeConnectionKey),
            "pending_profile": String(pendingProfile != nil),
            "profile_registered": String(store.agentCredentialProfiles.contains { $0.id == profile.id })
        ]
#endif
        guard !cleaned.isEmpty, !isFinishing else { return }
        guard originatingConnectionKey == activeConnectionKey else { cancel(); return }
        isFinishing = true
        if pendingProfile == nil {
            guard store.agentCredentialProfiles.contains(where: { $0.id == profile.id }) else {
                isFinishing = false
                return
            }
            store.selectAgentCredentialProfile(profile.id)
            store.updateModelName(cleaned)
            onConnected()
#if WEIBEI_ACCEPTANCE_CHECKS
            Self.checkLastFinishState?["phase"] = "on_connected_called"
#endif
            return
        }
        let credentialProviderID: String
        do {
            // 模型确认与凭据提交是同一步；失败或收起表单都保留原连接。
            credentialProviderID = try modelCatalog.commitCredential(for: profile)
#if WEIBEI_ACCEPTANCE_CHECKS
            Self.checkLastFinishState?["phase"] = "credential_committed"
#endif
            if !store.agentCredentialProfiles.contains(where: { $0.id == profile.id }) {
                try store.createAgentConnection(id: profile.id, provider: profile.provider,
                                                authMethod: profile.authMethod, baseURL: profile.baseURL)
            }
        } catch {
#if WEIBEI_ACCEPTANCE_CHECKS
            Self.checkLastFinishState?["phase"] = "save_failed"
#endif
            isFinishing = false
            errorText = store.ui("连接未保存，请重试。输入的内容仍保留。", "The connection was not saved. Please retry; your input is still here.")
            return
        }
        store.selectAgentCredentialProfile(profile.id)
        store.setAgentAuthMethod(profile.authMethod)
        store.updateModelName(cleaned)
#if WEIBEI_ACCEPTANCE_CHECKS
        Self.checkLastFinishState?["phase"] = "model_saved"
#endif
        // Publish only after the profile exists, so a new custom endpoint is known.
        if profile.authMethod == .subscription {
            store.completeAgentSubscriptionLogin(provider: profile.provider, profileID: profile.id)
        } else {
            NotificationCenter.default.post(name: .weiBeiAgentCredentialsDidChange, object: nil,
                userInfo: ["provider": credentialProviderID, "type": AgentCredentialType.apiKey.rawValue])
        }
        onConnected()
#if WEIBEI_ACCEPTANCE_CHECKS
        Self.checkLastFinishState?["phase"] = "on_connected_called"
#endif
    }

    private func cancel() {
        if ownsLogin { accounts.cancelLogin() }
        onCancel()
    }
}
