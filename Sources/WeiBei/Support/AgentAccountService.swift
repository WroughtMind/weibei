#if targetEnvironment(macCatalyst)
import UIKit
#endif
import SwiftUI
import WeiBeiCore
import os

/// Agent 账号与模型目录服务。
/// 目录为服务商实时名单（失败时回退默认 ID；选择器永远允许手输任意 ID）；凭据走 NativeAgentCredentialStore；
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

    struct SuccessfulModelListState: Equatable, Sendable {
        var message: LocalizedMessage?
        var canRetry: Bool
    }

    @Published private(set) var catalog: CatalogInfo?
    @Published private(set) var isLoggingIn = false
    @Published private(set) var statusMessage: LocalizedMessage?
    @Published private(set) var lastError: LocalizedMessage?
    @Published private(set) var liveModelIDs: [String] = []
    @Published private(set) var liveReasoningLevels: [String: [String]] = [:]
    /// 最近一次名单请求的失败。成功或换服务时清掉。默认模型仍可选手输，但界面不能把失败说成刚刚同步。
    @Published private(set) var modelListFailure: ModelListFailure?
    @Published private(set) var isRefreshingModels = false
    @Published private(set) var modelListMessage: LocalizedMessage?
    @Published private(set) var modelListCanRetry = false
    private var liveModelsProvider: AgentProviderID?

    enum ModelListFailure: Error, Equatable {
        case missingCredential
        case missingBaseURL
        case rejected
        case signInExpired
        case http(Int)
        case offline
        case unreadable
        case superseded
    }
    private var loginTask: Task<Void, Never>?
    private var loginID: UUID?
    @Published private(set) var loginTargetProfileID: UUID?
    @Published private(set) var authorizationCode: String?
    @Published private(set) var authorizationURL: URL?
    private var modelListTask: Task<Void, Never>?
    private var modelRequestProvider: AgentProviderID?
    private var modelRequestBaseURL = ""
    private var modelRequestAuthMethod: AgentAuthMethod?
    private var modelRequestGeneration = 0

    struct ModelCatalog {
        var ids: [String]
        var reasoningLevels: [String: [String]]
    }
    private let modelCatalogLoader: ((AgentProviderID, String) async throws -> ModelCatalog)?

    init(modelCatalogLoader: ((AgentProviderID, String) async throws -> ModelCatalog)? = nil) {
        self.modelCatalogLoader = modelCatalogLoader
        reloadCredentialSnapshot()
    }


    /// The same endpoint-scoped lookup used when sending; cards must not inspect another gateway's key.
    static func connectionAPIKey(provider: AgentProviderID, baseURL: String,
                                 credentialStore: NativeAgentCredentialStore) -> String? {
        guard let endpoint = try? AgentProviderEndpoint(provider: provider, baseURL: baseURL),
              let records = try? credentialStore.load(),
              let record = records[endpoint.credentialProviderID] else { return nil }
        return try? record.apiKey(for: provider, endpoint: endpoint)
    }

    func connectionAPIKey(provider: AgentProviderID, baseURL: String) -> String? {
        guard let credentialStore = try? NativeAgentCredentialStore.defaultStore() else { return nil }
        return Self.connectionAPIKey(provider: provider, baseURL: baseURL, credentialStore: credentialStore)
    }

    func refreshCatalog() {
        reloadCredentialSnapshot()
    }

    /// 打开设置或更换服务/密钥后，向服务商拉取可用模型。和测活走同一次鉴权请求。
    func refreshModels(provider: AgentProviderID, baseURL: String, authMethod: AgentAuthMethod) {
        let generation = beginModelRequest(for: provider, baseURL: baseURL, authMethod: authMethod)
        liveReasoningLevels = [:]
        modelListFailure = nil
        modelListTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.fetchLiveModels(
                provider: provider,
                baseURL: baseURL,
                authMethod: authMethod,
                generation: generation
            )
            self.publish(result, generation: generation)
        }
    }

    /// 和刷新名单同一次请求。后发起的那次作废先发起的，避免两路同时改名单。
    func probeConnection(
        provider: AgentProviderID,
        baseURL: String,
        authMethod: AgentAuthMethod
    ) async -> Result<Int, ModelListFailure> {
        let generation = beginModelRequest(for: provider, baseURL: baseURL, authMethod: authMethod)
        modelListFailure = nil
        let result = await fetchLiveModels(
            provider: provider,
            baseURL: baseURL,
            authMethod: authMethod,
            generation: generation
        )
        publish(result, generation: generation)
        return result
    }

    private func beginModelRequest(
        for provider: AgentProviderID,
        baseURL: String,
        authMethod: AgentAuthMethod
    ) -> Int {
        modelRequestProvider = provider
        modelRequestBaseURL = baseURL
        modelRequestAuthMethod = authMethod
        modelListTask?.cancel()
        modelRequestGeneration += 1
        isRefreshingModels = true
        modelListMessage = nil
        modelListCanRetry = false
        liveModelIDs = []
        if liveModelsProvider != provider {
            liveModelIDs = []
            liveModelsProvider = nil
            liveReasoningLevels = [:]
        }
        return modelRequestGeneration
    }

    private func publish(_ result: Result<Int, ModelListFailure>, generation: Int) {
        guard generation == modelRequestGeneration else { return }
        isRefreshingModels = false
        switch result {
        case .success:
            modelListFailure = nil
            let state = Self.successfulModelListState(liveModelIDs)
            modelListMessage = state.message
            modelListCanRetry = state.canRetry
        case .failure(let failure):
            guard failure != .superseded else { return }
            modelListFailure = failure
            modelListCanRetry = true
            modelListMessage = LocalizedMessage(chinese: "模型名单获取失败，当前选择没有改变。请重试，或手动输入模型 ID。",
                                               english: "Could not load the model list. Your selection is unchanged. Try again, or enter a model ID manually.")
        }
    }

    /// 冷启动的输入框也需要实时推理能力，不要求先打开设置。
    /// 多个输入框同时出现时复用当前查询，不清空已加载的能力。
    func refreshReasoningCatalogIfNeeded(
        provider: AgentProviderID,
        baseURL: String,
        authMethod: AgentAuthMethod
    ) {
        guard provider == .openaiCodex else { return }
        let sameRequest = modelRequestProvider == provider
            && modelRequestBaseURL == baseURL
            && modelRequestAuthMethod == authMethod
        if isRefreshingModels && sameRequest { return }
        guard !hasLoadedModels(provider: provider) else { return }
        refreshModels(provider: provider, baseURL: baseURL, authMethod: authMethod)
    }

    /// 只返回当前服务商端点实际拉取到的名单；手输任意 ID 仍然有效。
    func models(provider: AgentProviderID) -> [String] {
        Self.catalogEntries(liveModelIDs, loadedFor: liveModelsProvider, provider: provider)
    }

    static func catalogEntries(
        _ ids: [String],
        loadedFor: AgentProviderID?,
        provider: AgentProviderID
    ) -> [String] {
        guard loadedFor == provider else { return [] }
        return ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func successfulModelListState(_ modelIDs: [String]) -> SuccessfulModelListState {
        guard modelIDs.isEmpty else {
            return SuccessfulModelListState(message: nil, canRetry: false)
        }
        return SuccessfulModelListState(
            message: LocalizedMessage(
                chinese: "服务返回的模型名单为空，当前选择没有改变。请刷新重试，或手动输入模型 ID。",
                english: "The service returned an empty model list. Your selection is unchanged. Refresh to try again, or enter a model ID manually."
            ),
            canRetry: true
        )
    }

    func hasLoadedModels(provider: AgentProviderID) -> Bool {
        liveModelsProvider == provider
            && !isRefreshingModels
            && modelListMessage == nil
    }

    func reasoningLevels(provider: AgentProviderID, model: String) -> [String] {
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .openaiCodex {
            return liveModelsProvider == provider ? liveReasoningLevels[id] ?? [] : []
        }
        return AgentReasoningEffort.levels(provider: provider, model: id)
    }

    func reasoningLevelsForRequest(provider: AgentProviderID, model: String) async throws -> [String] {
        guard provider == .openaiCodex else {
            return AgentReasoningEffort.levels(provider: provider, model: model)
        }
        let record = try await NativeOpenAIOAuth.ensureFreshAccessToken()
        let levels = try await AgentModelListService.shared.codexReasoningLevels(
            token: record.accessToken ?? "", accountID: record.accountID ?? ""
        )
        return levels[model] ?? []
    }

    func isAvailable(_ provider: AgentProviderID) -> Bool {
        let route = NativeProviderRouting.route(provider)
        guard route.family != .unsupported else { return false }
        return route.auth != .oauth || provider == .openaiCodex
    }

    func authTypes(for provider: AgentProviderID) -> [AgentCredentialType] {
        guard isAvailable(provider) else { return [] }
        return provider == .openaiCodex ? [.oauth] : NativeProviderOAuth.supports(provider) ? [.oauth, .apiKey] : [.apiKey]
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

    func startLogin(
        _ provider: AgentProviderID,
        language: WeiBeiInterfaceLanguage,
        targetProfileID: UUID
    ) {
        guard NativeProviderOAuth.supports(provider) else {
            lastError = LocalizedMessage(
                chinese: "该服务暂不支持订阅登录。当前连接未更改；请改用 API Key。",
                english: "Subscription sign-in is not supported for this service. The current connection is unchanged; use an API key instead."
            )
            return
        }
        guard !isLoggingIn else { return }
        let attempt = UUID()
        loginID = attempt
        loginTargetProfileID = targetProfileID
        authorizationCode = nil
        authorizationURL = nil
        isLoggingIn = true
        statusMessage = LocalizedMessage(
            chinese: "正在打开浏览器完成登录…",
            english: "Opening your browser to finish signing in…"
        )
        lastError = nil
        loginTask = Task { [weak self] in
            guard let self else { return }
            do {
                let store = try NativeAgentCredentialStore.defaultStore()
                let record = try await NativeProviderOAuth.login(
                    provider: provider,
                    store: store,
                    language: language,
                    openURL: { url in
#if targetEnvironment(macCatalyst)
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#else
                        NSWorkspace.shared.open(url)
#endif
                    },
                    deviceCode: { code, url in
                        guard self.loginID == attempt else { return }
                        self.authorizationCode = code
                        self.authorizationURL = url
                        self.statusMessage = LocalizedMessage(chinese: "请在服务商页面确认设备码，完成授权。", english: "Confirm the device code on the provider page to authorize WeiBei.")
                    }
                )
                guard self.loginID == attempt else { return }
                self.authorizationCode = nil
                self.authorizationURL = nil
                self.isLoggingIn = false
                self.statusMessage = nil
                self.reloadCredentialSnapshot()
                NotificationCenter.default.post(
                    name: .weiBeiAgentOAuthDidSucceed,
                    object: nil,
                    userInfo: ["provider": record.provider, "profileID": targetProfileID]
                )
                self.loginID = nil
                self.loginTargetProfileID = nil
            } catch is CancellationError {
                guard self.loginID == attempt else { return }
                self.authorizationCode = nil
                self.authorizationURL = nil
                self.isLoggingIn = false
                self.statusMessage = nil
                self.loginID = nil
                self.loginTargetProfileID = nil
            } catch {
                guard self.loginID == attempt else { return }
                self.authorizationCode = nil
                self.authorizationURL = nil
                self.isLoggingIn = false
                self.statusMessage = nil
                self.loginID = nil
                self.loginTargetProfileID = nil
                self.logFailure("agent_login_failed", providerID: provider.credentialProviderID, error: error)
                self.lastError = self.authorizationFailureMessage(error, providerID: provider.credentialProviderID)
            }
        }
    }

    @discardableResult
    func startAPIKeyLogin(
        _ key: String,
        provider: AgentProviderID,
        baseURL: String = "",
        credentialStore: NativeAgentCredentialStore? = nil
    ) -> Bool {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoggingIn else { return false }
        guard let endpoint = try? AgentProviderEndpoint(provider: provider, baseURL: baseURL) else {
            lastError = LocalizedMessage(
                chinese: "密钥未保存：服务地址无效。现有凭据未更改；请检查地址后重试。",
                english: "The key was not saved because the service address is invalid. Existing credentials are unchanged; check the address and try again."
            )
            return false
        }
        guard !cleaned.isEmpty else {
            lastError = LocalizedMessage(
                chinese: "密钥未保存：API Key 不能为空。现有凭据未更改；请输入后重试。",
                english: "The key was not saved because the API key is empty. Existing credentials are unchanged; enter a key and try again."
            )
            return false
        }
        do {
            let store = try credentialStore ?? NativeAgentCredentialStore.defaultStore()
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
            reloadCredentialSnapshot(from: store)
            NotificationCenter.default.post(
                name: .weiBeiAgentCredentialsDidChange,
                object: nil,
                userInfo: [
                    "provider": endpoint.credentialProviderID,
                    "type": AgentCredentialType.apiKey.rawValue,
                ]
            )
            return true
        } catch {
            logFailure("agent_api_key_save_failed", providerID: endpoint.credentialProviderID, error: error)
            lastError = apiKeySaveFailureMessage(providerID: endpoint.credentialProviderID)
            return false
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
        loginID = nil
        loginTargetProfileID = nil
        authorizationCode = nil
        authorizationURL = nil
        isLoggingIn = false
        statusMessage = nil
    }

    private func reloadCredentialSnapshot(from suppliedStore: NativeAgentCredentialStore? = nil) {
        guard let store = try? suppliedStore ?? NativeAgentCredentialStore.defaultStore(),
              let records = try? store.load() else { return }
        catalog = CatalogInfo(credentials: records.values.map { record in
            CredentialInfo(
                providerId: record.provider,
                type: record.apiKey?.isEmpty == false ? .apiKey : .oauth,
                boundEndpoint: record.boundEndpoint
            )
        }
        .sorted { $0.providerId < $1.providerId })
    }

    private func fetchLiveModels(
        provider: AgentProviderID,
        baseURL: String,
        authMethod: AgentAuthMethod,
        generation: Int
    ) async -> Result<Int, ModelListFailure> {
        if let modelCatalogLoader {
            do {
                let catalog = try await modelCatalogLoader(provider, baseURL)
                guard generation == modelRequestGeneration, !Task.isCancelled else { return .failure(.superseded) }
                liveReasoningLevels = catalog.reasoningLevels
                liveModelIDs = Self.catalogEntries(catalog.ids, loadedFor: provider, provider: provider)
                liveModelsProvider = provider
                return .success(liveModelIDs.count)
            } catch {
                guard generation == modelRequestGeneration, !Task.isCancelled else { return .failure(.superseded) }
                return .failure(Self.modelListFailure(from: error))
            }
        }
        let endpoint = try? AgentProviderEndpoint(provider: provider, baseURL: baseURL)
        let resolved = endpoint.flatMap {
            NativeProviderRouting.resolvedBaseURL(provider: provider, endpoint: $0)
        } ?? NativeProviderRouting.route(provider).baseURL
        let records = (try? NativeAgentCredentialStore.defaultStore().load()) ?? [:]
        let record = records[endpoint?.credentialProviderID ?? provider.credentialProviderID]
        let hasCredential = record?.apiKey?.isEmpty == false || record?.accessToken?.isEmpty == false
        let strategy = NativeProviderRouting.modelListStrategy(
            provider: provider,
            baseURL: resolved,
            accessToken: record?.accessToken,
            accountID: record?.accountID
        )
        guard let strategy else {
            guard generation == modelRequestGeneration else { return .failure(.superseded) }
            liveModelIDs = []
            liveModelsProvider = provider
            return .failure(hasCredential ? .missingBaseURL : .missingCredential)
        }
        do {
            let ids: [String]
            var reasoningLevels: [String: [String]] = [:]
            if provider == .openaiCodex {
                let fresh = try await NativeOpenAIOAuth.ensureFreshAccessToken()
                let token = fresh.accessToken ?? ""
                let accountID = fresh.accountID ?? ""
                let service = AgentModelListService.shared
                let codex = ModelListStrategy.codexSubscription(token: token, accountID: accountID)
                ids = try await service.probe(strategy: codex, apiKey: "")
                reasoningLevels = try await service.codexReasoningLevels(token: token, accountID: accountID)
            } else {
                guard let endpoint else { throw ModelListError.missingBaseURL }
                let key = try await NativeLLMAdapterFactory.resolveCredential(
                    provider: provider,
                    endpoint: endpoint,
                    authMethod: authMethod
                ) ?? ""
                let modelService = NativeProviderOAuth.supports(provider)
                    ? AgentModelListService(session: NativeProviderOAuth.networkSession) : .shared
                ids = try await modelService.probe(strategy: strategy, apiKey: key)
            }
            guard generation == modelRequestGeneration, !Task.isCancelled else { return .failure(.superseded) }
            modelListFailure = nil
            liveReasoningLevels = reasoningLevels
            liveModelIDs = ids
            liveModelsProvider = provider
            return .success(ids.count)
        } catch {
            guard generation == modelRequestGeneration, !Task.isCancelled else { return .failure(.superseded) }
            if liveModelsProvider != provider {
                liveModelIDs = []
            }
            liveModelsProvider = provider
            return .failure(Self.modelListFailure(from: error))
        }
    }

    private static func modelListFailure(from error: Error) -> ModelListFailure {
        if error is CancellationError { return .superseded }
        if let failure = error as? NativeLLMFailure {
            if failure.code == "oauth_timeout" { return .signInExpired }
            if failure.code == "unauthorized" || failure.status == 401 || failure.status == 403 {
                return .rejected
            }
            if let status = failure.status { return .http(status) }
            return .signInExpired
        }
        if error is URLError { return .offline }
        guard let error = error as? ModelListError else { return .unreadable }
        switch error {
        case .missingCredential: return .missingCredential
        case .missingBaseURL: return .missingBaseURL
        case .http(let status, _) where status == 401 || status == 403: return .rejected
        case .http(let status, _): return .http(status)
        case .transport(let message) where message == "cancelled": return .superseded
        case .transport: return .offline
        case .decoding: return .unreadable
        }
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

    private func authorizationFailureMessage(_ error: Error, providerID: String) -> LocalizedMessage {
        if let failure = error as? NativeLLMFailure {
            if failure.code == "oauth_timeout" {
                return LocalizedMessage(chinese: "授权已过期，请重新登录。原有连接未更改。", english: "Authorization expired. Sign in again. Your previous connection is unchanged.")
            }
            if failure.status == 402 || failure.status == 403 {
                return LocalizedMessage(chinese: "服务商未允许此账号访问模型。请检查订阅、余额或账号权限后重试；新凭据未保存。", english: "The provider did not permit model access. Check your plan, balance, or permissions, then retry. New credentials were not saved.")
            }
            if failure.status == 429 {
                return LocalizedMessage(chinese: "服务商请求过于频繁，请稍后重试；新凭据未保存。", english: "The provider rate limit was reached. Try again later. New credentials were not saved.")
            }
        }
        return loginFailureMessage(providerID: providerID)
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
