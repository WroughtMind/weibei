import SwiftUI
import WeiBeiCore

/// Agent 账号与模型目录服务。
/// 目录为内置静态表(模型选择器永远允许手输任意 ID);凭据走 NativeAgentCredentialStore;
/// OpenAI 订阅登录走 NativeOpenAIOAuth 浏览器流程。
@MainActor
final class AgentAccountService: ObservableObject {
    static let shared = AgentAccountService()

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
    @Published private(set) var lastError: String?
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
            lastError = "该服务的订阅登录暂未接入 native 运行时，请改用 API Key。"
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
                self.lastError = error.localizedDescription
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
            lastError = "服务地址无法解析"
            return
        }
        guard !cleaned.isEmpty else {
            lastError = "API Key 不能为空"
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
            lastError = error.localizedDescription
        }
    }

    func logout(_ provider: AgentProviderID) {
        logoutCredential(providerID: provider.credentialProviderID)
    }

    func logoutCredential(providerID: String) {
        do {
            try NativeAgentCredentialStore.defaultStore().remove(provider: providerID)
            reloadCredentialSnapshot()
            NotificationCenter.default.post(
                name: .weiBeiAgentCredentialsDidChange,
                object: nil,
                userInfo: ["provider": providerID]
            )
        } catch {
            lastError = error.localizedDescription
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
