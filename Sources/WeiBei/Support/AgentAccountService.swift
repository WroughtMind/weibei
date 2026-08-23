import SwiftUI
import WeiBeiCore

/// Agent 账号与模型目录服务(2026-08 Pi 退役后的 native 实现)。
/// 接管原 PiOAuthService 的全部 UI 职责,方法签名保持同形以最小化视图改动:
/// 目录为内置静态表(模型选择器永远允许手输任意 ID);凭据走 NativeAgentCredentialStore;
/// OpenAI 订阅登录走 NativeOpenAIOAuth 浏览器流程。首次启动会把旧的 Pi 凭据
/// 一次性迁移到 native 存储,已登录账号无需重新登录。
@MainActor
final class AgentAccountService: ObservableObject {
    static let shared = AgentAccountService()

    struct ProviderInfo: Equatable, Sendable {
        var id: String
        var name: String
        var authTypes: [AgentCredentialType] = []
    }

    struct CredentialInfo: Equatable, Sendable {
        var providerId: String
        var type: AgentCredentialType
        var boundEndpoint: String? = nil
    }

    struct CatalogInfo: Equatable, Sendable {
        var providers: [ProviderInfo] = []
        var credentials: [CredentialInfo] = []
    }

    @Published private(set) var catalog: CatalogInfo?
    @Published private(set) var isRefreshingCatalog = false
    @Published private(set) var catalogError: String?
    @Published private(set) var isLoggingIn = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?
    /// native 登录流程没有中途交互提示;保留属性以兼容原 UI 的动画条件。
    @Published private(set) var pendingPrompt: String?

    private var loginTask: Task<Void, Never>?

    private init() {
        migratePiCredentialsIfNeeded()
        reloadCredentialSnapshot()
    }

    /// 静态目录无需刷新;保留方法以兼容原 UI 调用点。
    func refreshCatalog(force: Bool = false) {
        reloadCredentialSnapshot()
    }

    /// 模型建议列表来自 native 路由表的默认模型;完整列表靠选择器的手动输入。
    func models(providerID: String) -> [String] {
        guard let provider = AgentProviderID(rawValue: providerID) else { return [] }
        let model = NativeProviderRouting.route(provider).defaultModel
        return model.isEmpty ? [] : [model]
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
        isConfigured(providerID: provider.piProviderName, type: .oauth)
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
                NotificationCenter.default.post(name: .weiBeiPiOAuthDidSucceed, object: nil, userInfo: ["provider": record.provider])
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
        _ key: String = "",
        provider: AgentProviderID,
        baseURL: String = "",
        model: String = ""
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
                provider: endpoint.piProviderID,
                apiKey: cleaned,
                accessToken: nil,
                refreshToken: nil,
                expiresAt: nil,
                accountID: nil
            ))
            lastError = nil
            reloadCredentialSnapshot()
            NotificationCenter.default.post(name: .weiBeiPiCredentialsDidChange, object: nil, userInfo: ["type": AgentCredentialType.apiKey.rawValue])
        } catch {
            lastError = error.localizedDescription
        }
    }

    func logout(_ provider: AgentProviderID) {
        logoutCredential(providerID: provider.piProviderName)
    }

    func logoutCredential(providerID: String, displayName: String? = nil) {
        do {
            try NativeAgentCredentialStore.defaultStore().remove(provider: providerID)
            reloadCredentialSnapshot()
            NotificationCenter.default.post(name: .weiBeiPiCredentialsDidChange, object: nil)
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
                boundEndpoint: nil
            )
        }
        .sorted { $0.providerId < $1.providerId })
    }

    /// 旧 Pi 凭据(PiAgent/auth.json)一次性迁移到 native 存储;原文件保留不动。
    private func migratePiCredentialsIfNeeded() {
        guard let source = try? WeiBeiAgentDataPaths.ensurePiAgentDirectory() else { return }
        let authURL = source.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: source),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
        guard let store = try? NativeAgentCredentialStore.defaultStore() else { return }
        guard var records = try? store.load() else { return }
        for (provider, entry) in object where records[provider] == nil {
            if let access = entry["access"] as? String, !access.isEmpty {
                let expires = entry["expires"] as? TimeInterval
                records[provider] = NativeAgentCredentialRecord(
                    provider: provider,
                    apiKey: entry["key"] as? String,
                    accessToken: access,
                    refreshToken: entry["refresh"] as? String,
                    expiresAt: expires.map { Date(timeIntervalSince1970: $0) },
                    accountID: entry["accountId"] as? String
                )
            } else if let key = entry["key"] as? String, !key.isEmpty {
                records[provider] = NativeAgentCredentialRecord(
                    provider: provider,
                    apiKey: key,
                    accessToken: nil,
                    refreshToken: nil,
                    expiresAt: nil,
                    accountID: nil
                )
            }
        }
        try? store.save(records)
    }
}

/// native 时代的凭据类型;rawValue 与旧 pi 通知的 userInfo 值保持一致。
enum AgentCredentialType: String, Codable, Sendable {
    case apiKey = "api_key"
    case oauth
}

extension Notification.Name {
    static let weiBeiPiOAuthDidSucceed = Notification.Name("weiBeiPiOAuthDidSucceed")
    static let weiBeiPiCredentialsDidChange = Notification.Name("weiBeiPiCredentialsDidChange")
}
