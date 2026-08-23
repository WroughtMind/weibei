import SwiftUI
import WeiBeiCore
import os

/// Agent 账号与模型目录服务。
/// 目录为内置静态表(模型选择器永远允许手输任意 ID);凭据走 NativeAgentCredentialStore;
/// OpenAI 订阅登录走 NativeOpenAIOAuth 浏览器流程。
@MainActor
final class AgentAccountService: ObservableObject {
    static let shared = AgentAccountService()
    private static let logger = Logger(subsystem: WeiBeiLog.subsystem, category: "agentAccount")

    struct LocalizedMessage: Equatable, Sendable {
        var chinese: String
        var english: String
    }

    struct CredentialInfo: Equatable, Sendable {
        var providerId: String
        var type: AgentCredentialType
        var boundEndpoint: String? = nil
    }

    struct CatalogInfo: Equatable, Sendable {
        var credentials: [CredentialInfo] = []
    }

    @Published private(set) var catalog: CatalogInfo?
    @Published private(set) var isLoggingIn = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: LocalizedMessage?
    private var loginTask: Task<Void, Never>?

    private init() {
        reloadCredentialSnapshot()
    }

    func refreshCatalog() {
        reloadCredentialSnapshot()
    }

    /// 模型建议列表来自 native 路由表的默认模型;完整列表靠选择器的手动输入。
    func models(provider: AgentProviderID) -> [String] {
        let model = NativeProviderRouting.route(provider).defaultModel
        return model.isEmpty ? [] : [model]
    }

    func isAvailable(_ provider: AgentProviderID) -> Bool {
        let route = NativeProviderRouting.route(provider)
        guard route.family != .unsupported else { return false }
        return route.auth != .oauth || provider == .openaiCodex
    }

    func authTypes(for provider: AgentProviderID) -> [AgentCredentialType] {
        guard isAvailable(provider) else { return [] }
        return provider == .openaiCodex ? [.oauth] : [.apiKey]
    }

    func isConfigured(providerID: String, type: AgentCredentialType? = nil) -> Bool {
        guard let records = try? NativeAgentCredentialStore.defaultStore().load(),
              let record = records[providerID] else { return false }
        switch type {
        case .apiKey:
            return record.apiKey?.isEmpty == false
        case .oauth:
            return record.accessToken?.isEmpty == false
        case nil:
            return record.apiKey?.isEmpty == false || record.accessToken?.isEmpty == false
        }
    }

    func isLinked(_ provider: AgentProviderID) -> Bool {
        isConfigured(providerID: provider.credentialProviderID, type: .oauth)
    }

    func startLogin(_ provider: AgentProviderID) {
        guard provider == .openaiCodex else {
            lastError = LocalizedMessage(
                chinese: "该服务暂不支持订阅登录。当前连接未更改；请改用 API Key。",
                english: "Subscription sign-in is not supported for this service. The current connection is unchanged; use an API key instead."
            )
            return
        }
        guard !isLoggingIn else { return }
        isLoggingIn = true
        statusMessage = "正在打开浏览器完成登录…"
        lastError = nil
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let store = try NativeAgentCredentialStore.defaultStore()
                let record = try await NativeOpenAIOAuth.loginWithBrowser(
                    store: store,
                    openURL: { url in NSWorkspace.shared.open(url) }
                )
                self.isLoggingIn = false
                self.statusMessage = nil
                self.reloadCredentialSnapshot()
                NotificationCenter.default.post(name: .weiBeiAgentOAuthDidSucceed, object: nil, userInfo: ["provider": record.provider])
            } catch is CancellationError {
                self.isLoggingIn = false
                self.statusMessage = nil
            } catch {
                self.isLoggingIn = false
                self.statusMessage = nil
                self.logFailure("agent_login_failed", providerID: provider.credentialProviderID, error: error)
                self.lastError = self.loginFailureMessage(providerID: provider.credentialProviderID)
            }
        }
    }

    func startAPIKeyLogin(
        _ key: String,
        provider: AgentProviderID,
        baseURL: String = ""
    ) {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoggingIn else { return }
        guard let endpoint = try? AgentProviderEndpoint(provider: provider, baseURL: baseURL) else {
            lastError = LocalizedMessage(
                chinese: "密钥未保存：服务地址无效。现有凭据未更改；请检查地址后重试。",
                english: "The key was not saved because the service address is invalid. Existing credentials are unchanged; check the address and try again."
            )
            return
        }
        guard !cleaned.isEmpty else {
            lastError = LocalizedMessage(
                chinese: "密钥未保存：API Key 不能为空。现有凭据未更改；请输入后重试。",
                english: "The key was not saved because the API key is empty. Existing credentials are unchanged; enter a key and try again."
            )
            return
        }
        do {
            let store = try NativeAgentCredentialStore.defaultStore()
            try store.upsert(NativeAgentCredentialRecord(
                provider: endpoint.credentialProviderID,
                apiKey: cleaned,
                accessToken: nil,
                refreshToken: nil,
                expiresAt: nil,
                accountID: nil,
                boundEndpoint: endpoint.baseURL
            ))
            lastError = nil
            reloadCredentialSnapshot()
            NotificationCenter.default.post(
                name: .weiBeiAgentCredentialsDidChange,
                object: nil,
                userInfo: [
                    "provider": endpoint.credentialProviderID,
                    "type": AgentCredentialType.apiKey.rawValue,
                ]
            )
        } catch {
            logFailure("agent_api_key_save_failed", providerID: endpoint.credentialProviderID, error: error)
            lastError = apiKeySaveFailureMessage(providerID: endpoint.credentialProviderID)
        }
    }

    func logout(_ provider: AgentProviderID) {
        logoutCredential(providerID: provider.credentialProviderID)
    }

    func logoutCredential(providerID: String) {
        do {
            try NativeAgentCredentialStore.defaultStore().remove(provider: providerID)
            lastError = nil
            reloadCredentialSnapshot()
            NotificationCenter.default.post(
                name: .weiBeiAgentCredentialsDidChange,
                object: nil,
                userInfo: ["provider": providerID]
            )
        } catch {
            reloadCredentialSnapshot()
            logFailure("agent_disconnect_failed", providerID: providerID, error: error)
            lastError = disconnectFailureMessage(providerID: providerID)
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
        isLoggingIn = false
        statusMessage = nil
    }

    private func reloadCredentialSnapshot() {
        guard let records = try? NativeAgentCredentialStore.defaultStore().load() else { return }
        catalog = CatalogInfo(credentials: records.values.map { record in
            CredentialInfo(
                providerId: record.provider,
                type: record.apiKey?.isEmpty == false ? .apiKey : .oauth,
                boundEndpoint: record.boundEndpoint
            )
        }
        .sorted { $0.providerId < $1.providerId })
    }

    private func credentialAvailability(providerID: String, type: AgentCredentialType? = nil) -> Bool? {
        guard let records = try? NativeAgentCredentialStore.defaultStore().load() else { return nil }
        guard let record = records[providerID] else { return false }
        switch type {
        case .apiKey:
            return record.apiKey?.isEmpty == false
        case .oauth:
            return record.accessToken?.isEmpty == false
        case nil:
            return record.apiKey?.isEmpty == false || record.accessToken?.isEmpty == false
        }
    }

    private func loginFailureMessage(providerID: String) -> LocalizedMessage {
        switch credentialAvailability(providerID: providerID, type: .oauth) {
        case true:
            return LocalizedMessage(
                chinese: "登录未完成。当前连接仍保留；请重试。",
                english: "Sign-in did not finish. The current connection is still available; try again."
            )
        case false:
            return LocalizedMessage(
                chinese: "登录未完成，尚未建立连接。请重试。",
                english: "Sign-in did not finish and no connection was established. Try again."
            )
        case nil:
            return LocalizedMessage(
                chinese: "登录未完成，当前连接状态无法确认。请重新打开设置后重试。",
                english: "Sign-in did not finish, and the current connection could not be confirmed. Reopen Settings and try again."
            )
        }
    }

    private func apiKeySaveFailureMessage(providerID: String) -> LocalizedMessage {
        switch credentialAvailability(providerID: providerID, type: .apiKey) {
        case true:
            return LocalizedMessage(
                chinese: "密钥保存未完成。现有凭据仍保留；请重试。",
                english: "The key was not fully saved. Existing credentials are still available; try again."
            )
        case false:
            return LocalizedMessage(
                chinese: "密钥保存未完成，当前没有可用凭据。请重试。",
                english: "The key was not fully saved, and no usable credentials are available. Try again."
            )
        case nil:
            return LocalizedMessage(
                chinese: "密钥保存未完成，当前凭据状态无法确认。请重新打开设置后重试。",
                english: "The key was not fully saved, and the current credential status could not be confirmed. Reopen Settings and try again."
            )
        }
    }

    private func disconnectFailureMessage(providerID: String) -> LocalizedMessage {
        switch credentialAvailability(providerID: providerID) {
        case true:
            return LocalizedMessage(
                chinese: "未能断开连接。当前凭据仍保留；请重试。",
                english: "Could not disconnect. The current credentials are still available; try again."
            )
        case false:
            return LocalizedMessage(
                chinese: "当前连接已断开，但凭据清理未全部完成。请重试。",
                english: "The current connection is disconnected, but credential cleanup did not fully finish. Try again."
            )
        case nil:
            return LocalizedMessage(
                chinese: "断开连接未完成，当前凭据状态无法确认。请重新打开设置后重试。",
                english: "Disconnect did not finish, and the current credential status could not be confirmed. Reopen Settings and try again."
            )
        }
    }

    private func logFailure(_ code: String, providerID: String, error: Error) {
        Self.logger.error(
            "code=\(code, privacy: .public) provider=\(providerID, privacy: .private) underlying=\(WeiBeiLog.code(error), privacy: .public) detail=\(WeiBeiLog.truncated(error.localizedDescription), privacy: .private)"
        )
    }

}

/// Native Agent 凭据类型。
enum AgentCredentialType: String, Codable, Sendable {
    case apiKey = "api_key"
    case oauth
}

extension Notification.Name {
    static let weiBeiAgentOAuthDidSucceed = Notification.Name("weiBeiAgentOAuthDidSucceed")
    static let weiBeiAgentCredentialsDidChange = Notification.Name("weiBeiAgentCredentialsDidChange")
}
