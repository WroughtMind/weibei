import AppKit
import Foundation
import WeiBeiCore

@MainActor
final class PiOAuthService: ObservableObject {
    static let shared = PiOAuthService()

    @Published private(set) var isLoggingIn = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastError: String?
    @Published private(set) var catalog: PiManagementCatalog?
    @Published private(set) var isRefreshingCatalog = false
    @Published private(set) var catalogError: String?
    @Published private(set) var pendingPrompt: PiManagementPrompt?
    @Published var promptValue = ""

    private let runtime: PiAgentRuntime
    private var operationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var promptContinuation: CheckedContinuation<String, Error>?
    private var suppliedAPIKey: String?
    private var customProviderSetup: (provider: AgentProviderID, baseURL: String, model: String)?

    init(runtime: PiAgentRuntime? = nil) {
        self.runtime = runtime ?? PiAgentRuntime(
            runtimeDirectory: WeiBeiAgentDataPaths.applicationSupportRoot
                .appendingPathComponent("PiManagementRuntime", isDirectory: true),
            persistentPiConfigurationDirectory: WeiBeiAgentDataPaths.piAuthJSON.deletingLastPathComponent()
        )
    }

    func refreshCatalog(force: Bool = false) {
        guard !isLoggingIn else { return }
        let previousRefresh = refreshTask
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if let previousRefresh { _ = await previousRefresh.result }
            isRefreshingCatalog = true
            defer { isRefreshingCatalog = false }
            catalogError = nil
            do {
                let loaded = try await runtime.managementCatalog(refresh: force)
                guard !Task.isCancelled else { return }
                catalog = loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                catalogError = error.localizedDescription
            }
        }
    }

    func models(providerID: String) -> [String] {
        catalog?.models
            .filter { $0.providerId == providerID }
            .map(\.id) ?? []
    }

    func isConfigured(providerID: String, type: PiCredentialType? = nil) -> Bool {
        if catalog?.credentials.contains(where: {
            $0.providerId == providerID && (type == nil || $0.type == type)
        }) == true {
            return true
        }
        guard type == nil || type == .apiKey else { return false }
        return catalog?.providers.first(where: { $0.id == providerID })?.configured ?? false
    }

    static func readLinkedOAuthProviders(from url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return object.compactMap { key, value in
            guard let dict = value as? [String: Any],
                  (dict["type"] as? String) == "oauth",
                  dict["access"] != nil || dict["refresh"] != nil else { return nil }
            return key
        }.sorted()
    }

    func isLinked(_ provider: AgentProviderID) -> Bool {
        isConfigured(providerID: provider.piProviderName, type: .oauth)
    }

    func startLogin(_ provider: AgentProviderID) {
        startCredentialLogin(
            providerID: provider.piProviderName,
            type: .oauth,
            displayName: provider.label(language: .chinese),
            successNotification: .weiBeiPiOAuthDidSucceed
        )
    }

    func startAPIKeyLogin(
        _ key: String = "",
        provider: AgentProviderID,
        baseURL: String = "",
        model: String = ""
    ) {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLoggingIn else { return }
        suppliedAPIKey = cleaned.isEmpty ? nil : cleaned
        if provider == .custom || provider == .llamaCpp {
            customProviderSetup = (provider, baseURL, model)
        }
        startCredentialLogin(
            providerID: provider.piProviderName,
            type: .apiKey,
            displayName: provider.label(language: .chinese),
            successNotification: .weiBeiPiCredentialsDidChange
        )
    }

    private func startCredentialLogin(
        providerID: String,
        type: PiCredentialType,
        displayName: String,
        successNotification: Notification.Name
    ) {
        guard !isLoggingIn else { return }
        lastError = nil
        statusMessage = "正在启动内置 Pi 登录…"
        isLoggingIn = true
        _ = try? WeiBeiAgentDataPaths.ensurePiAgentDirectory()
        let previousRefresh = refreshTask
        previousRefresh?.cancel()
        refreshTask = nil
        operationTask = Task { [weak self] in
            guard let self else { return }
            if let previousRefresh { _ = await previousRefresh.result }
            do {
                if let setup = customProviderSetup {
                    await runtime.writeCustomModelsJSONIfNeeded(
                        providerID: setup.provider,
                        baseURL: setup.baseURL,
                        model: setup.model
                    )
                    customProviderSetup = nil
                }
                let credential = try await runtime.login(
                    providerID: providerID,
                    type: type,
                    interaction: PiManagementInteraction(
                        prompt: { [weak self] prompt in
                            guard let self else { throw PiAgentRuntimeError.cancelled }
                            return try await self.requestInput(for: prompt)
                        },
                        notify: { [weak self] notice in
                            await self?.handle(notice)
                        }
                    )
                )
                guard !Task.isCancelled else { throw PiAgentRuntimeError.cancelled }
                updateCatalogCredential(credential)
                statusMessage = "已连接：\(displayName)"
                lastError = nil
                finishOperation()
                NotificationCenter.default.post(
                    name: successNotification,
                    object: nil,
                    userInfo: ["provider": providerID, "type": type.rawValue]
                )
            } catch {
                finishOperation(error: error)
            }
        }
    }

    func logout(_ provider: AgentProviderID) {
        logoutCredential(
            providerID: provider.piProviderName,
            displayName: provider.label(language: .chinese)
        )
    }

    func logoutCredential(providerID: String, displayName: String? = nil) {
        guard !isLoggingIn else { return }
        lastError = nil
        statusMessage = "正在断开内置 Pi 凭证…"
        isLoggingIn = true
        let previousRefresh = refreshTask
        previousRefresh?.cancel()
        refreshTask = nil
        operationTask = Task { [weak self] in
            guard let self else { return }
            if let previousRefresh { _ = await previousRefresh.result }
            do {
                try await runtime.logout(providerID: providerID)
                removeCatalogCredential(providerID: providerID)
                statusMessage = "已断开：\(displayName ?? providerID)"
                finishOperation()
                NotificationCenter.default.post(
                    name: .weiBeiPiCredentialsDidChange,
                    object: nil,
                    userInfo: ["provider": providerID]
                )
            } catch {
                finishOperation(error: error)
            }
        }
    }

    func cancelLogin() {
        operationTask?.cancel()
        cancelPendingPrompt()
        Task { await runtime.shutdown() }
        finishOperation(error: PiAgentRuntimeError.cancelled)
    }

    func submitPrompt(_ value: String? = nil) {
        guard let continuation = promptContinuation else { return }
        let submitted = (value ?? promptValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty else { return }
        promptContinuation = nil
        pendingPrompt = nil
        promptValue = ""
        continuation.resume(returning: submitted)
    }

    private func requestInput(for prompt: PiManagementPrompt) async throws -> String {
        if prompt.type == .secret, let suppliedAPIKey {
            self.suppliedAPIKey = nil
            return suppliedAPIKey
        }
        guard promptContinuation == nil else { throw PiAgentRuntimeError.busy }
        pendingPrompt = prompt
        promptValue = prompt.type == .select ? (prompt.options?.first?.id ?? "") : ""
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                promptContinuation = continuation
            }
        }, onCancel: {
            Task { @MainActor [weak self] in self?.cancelPendingPrompt() }
        })
    }

    private func cancelPendingPrompt() {
        let continuation = promptContinuation
        promptContinuation = nil
        pendingPrompt = nil
        promptValue = ""
        continuation?.resume(throwing: PiAgentRuntimeError.cancelled)
    }

    private func handle(_ notice: PiManagementNotice) {
        switch notice.type {
        case .authURL:
            if let raw = notice.url, let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
            }
            statusMessage = notice.instructions ?? "浏览器已打开；完成登录后回到魏碑。"
        case .deviceCode:
            if let raw = notice.verificationUri, let url = URL(string: raw) {
                NSWorkspace.shared.open(url)
            }
            statusMessage = [notice.message, notice.userCode.map { "设备码：\($0)" }]
                .compactMap { $0 }
                .joined(separator: " ")
        case .progress, .info:
            statusMessage = notice.message ?? statusMessage
        }
    }

    private func updateCatalogCredential(_ credential: PiManagementCredentialInfo) {
        guard var catalog else { return }
        catalog.credentials.removeAll { $0.providerId == credential.providerId }
        catalog.credentials.append(credential)
        if let index = catalog.providers.firstIndex(where: { $0.id == credential.providerId }) {
            catalog.providers[index].configured = true
            catalog.providers[index].authSource = "stored"
        }
        self.catalog = catalog
    }

    private func removeCatalogCredential(providerID: String) {
        guard var catalog else { return }
        catalog.credentials.removeAll { $0.providerId == providerID }
        if let index = catalog.providers.firstIndex(where: { $0.id == providerID }) {
            catalog.providers[index].configured = false
            catalog.providers[index].authSource = nil
        }
        self.catalog = catalog
    }

    private func finishOperation(error: Error? = nil) {
        operationTask = nil
        isLoggingIn = false
        suppliedAPIKey = nil
        customProviderSetup = nil
        cancelPendingPrompt()
        if let error {
            if error is CancellationError || (error as? PiAgentRuntimeError) == .cancelled {
                statusMessage = "已取消"
            } else {
                lastError = error.localizedDescription
                statusMessage = nil
            }
        }
    }
}

extension Notification.Name {
    static let weiBeiPiOAuthDidSucceed = Notification.Name("weiBeiPiOAuthDidSucceed")
    static let weiBeiPiCredentialsDidChange = Notification.Name("weiBeiPiCredentialsDidChange")
}
