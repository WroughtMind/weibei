import AppKit
import Combine
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WeiBeiCore

/// Agent provider, model discovery, credential profile, and appearance settings behavior.
extension WorkspaceStore {
    func setAgentProviderID(_ provider: AgentProviderID) {
        guard agentProviderID != provider else { return }
        let previousDefault = agentProviderID.defaultModelHint
        agentProviderID = provider
        // Prefer profile-scoped key; fall back to the provider-scoped app data file.
        let profileKey = AgentCredentialProfileStore.loadAPIKey(profileID: activeAgentProfileID)
        openAIAPIKey = profileKey.isEmpty
            ? OpenAIAPIKeyStore.load(provider: provider.piProviderName)
            : profileKey
        // Switch model when empty or still on the previous provider's default hint.
        let trimmedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty || trimmedModel == previousDefault {
            modelName = provider.defaultModelHint
        }
        openAIKeyStatus = nil
        // Drop the old provider's catalog so the dropdown never briefly shows the
        // previous provider's models; the Store re-fetches right after (see S2).
        availableModels = []
        modelListStatus = .idle
        touchActiveAgentProfileMetadata()
        save()
        scheduleModelListRefresh()
    }

    func updateAgentBaseURL(_ value: String) {
        agentBaseURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
        touchActiveAgentProfileMetadata()
        save()
    }

    func updateModelName(_ value: String) {
        modelName = value
        touchActiveAgentProfileMetadata()
        save()
    }

    /// Assemble the concrete listing strategy for the active provider, combining the
    /// provider's protocol with the runtime base URL / Bedrock region.
    func resolvedModelListStrategy() -> ModelListStrategy? {
        switch agentProviderID.modelListProtocol {
        case .openAICompatible:
            let base = agentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = base.isEmpty ? (agentProviderID.defaultListBaseURL ?? "") : base
            guard !resolved.isEmpty else { return nil }
            return .openAICompatible(base: resolved)
        case .anthropic:
            return .anthropic
        case .gemini:
            return .gemini
        case .openRouterPublic:
            return .openRouterPublic
        case .azureOpenAI:
            let base = agentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty else { return nil }
            return .azureOpenAI(base: base)
        case .bedrock:
            return .bedrock(region: bedrockRegion)
        case .gitHubModels:
            return .gitHubModels
        case .codexSubscription:
            // Need the OAuth token + account id from WeiBei's Pi auth file. If absent
            // (not signed in), return nil — the caller falls back to the built-in catalog.
            guard let credential = codexSubscriptionCredential() else { return nil }
            return .codexSubscription(token: credential.token, accountID: credential.accountID)
        case .unsupported:
            return nil
        }
    }

    /// Read the openai-codex OAuth token + accountId stored by pi-oauth-login.mjs.
    func codexSubscriptionCredential() -> (token: String, accountID: String)? {
        WeiBeiAgentDataPaths.migrateHomePiAuthIfNeeded()
        let url = WeiBeiAgentDataPaths.piAuthJSON
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root["openai-codex"] as? [String: Any] else { return nil }
        let token = (entry["access"] as? String) ?? ""
        let accountID = (entry["accountId"] as? String) ?? ""
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (token, accountID)
    }

    /// Whether the active provider can enumerate models at all (vs. built-in only).
    var supportsRemoteModelList: Bool {
        agentProviderID.modelListProtocol != .unsupported
    }

    /// Fetch the model catalog for the active provider. Updates `availableModels` /
    /// `modelListStatus` on the main actor. Safe to call repeatedly; debounced by the UI.
    ///
    /// Codex subscription tries the live `codex/models` endpoint first, then falls back
    /// to the built-in catalog on any failure (best-effort listing, per upstream behavior).
    /// Fetch the model catalog for the active provider. Updates `availableModels` /
    /// `modelListStatus` on the main actor.
    ///
    /// Race-safe via `modelFetchGeneration`: each call stamps a generation, and a
    /// late-resolving fetch whose generation no longer matches is discarded so rapid
    /// provider/profile switches can't paint the wrong catalog (see S2).
    ///
    /// Cancellation of an in-flight **scheduled** fetch is owned by
    /// `scheduleModelListRefresh()` only. This method must NOT cancel `modelFetchTask`:
    /// the scheduler stores the Task that awaits `refreshModelList()`, so cancelling
    /// here would cancel ourselves mid-flight, trip `Task.isCancelled` after the
    /// network returns, discard a successful catalog, and leave `modelListStatus`
    /// stuck on `.loading` (OpenAI Codex subscription looked permanently broken).
    func refreshModelList() async {
        // No strategy (unsupported provider, or Codex subscription not signed in):
        // surface the built-in catalog immediately. These are synchronous resolutions
        // — stamp them with the current generation so an in-flight async fetch that
        // resolves later is still discarded.
        modelFetchGeneration &+= 1
        let myGen = modelFetchGeneration

        guard let strategy = resolvedModelListStrategy() else {
            guard myGen == modelFetchGeneration else { return }
            availableModels = fallbackModelCatalog
            modelListStatus = .builtin
            return
        }
        // Codex subscription doesn't use an API key — it carries its own OAuth token in
        // the strategy. OpenRouter public catalog needs no credential either.
        let needsAPIKey: Bool
        if case .codexSubscription = strategy { needsAPIKey = false }
        else if strategy == .openRouterPublic { needsAPIKey = false }
        else { needsAPIKey = true }

        if needsAPIKey, resolvedAPIKey() == nil {
            guard myGen == modelFetchGeneration else { return }
            availableModels = fallbackModelCatalog
            modelListStatus = .failed(ui("未配置密钥，无法列出模型。", "No API key configured; cannot list models."))
            return
        }
        let apiKey = resolvedAPIKey()?.key ?? ""
        guard myGen == modelFetchGeneration else { return }
        modelListStatus = .loading
        do {
            let models = try await AgentModelListService.shared.fetchModels(strategy: strategy, apiKey: apiKey)
            // Discard if a newer request superseded this one, or this scheduled task
            // was cancelled by a later scheduleModelListRefresh().
            guard myGen == modelFetchGeneration, !Task.isCancelled else { return }
            availableModels = models.isEmpty ? fallbackModelCatalog : models
            modelListStatus = .loaded
        } catch {
            guard myGen == modelFetchGeneration, !Task.isCancelled else { return }
            availableModels = fallbackModelCatalog
            modelListStatus = (agentProviderID == .openaiCodex) ? .builtin : .failed(error.localizedDescription)
        }
    }

    /// Fire-and-forget entry point for the Store's own state transitions
    /// (`setAgentProviderID`, `selectAgentCredentialProfile`). Makes the Store the
    /// single originator of model-list fetches instead of relying on UI onChange
    /// hooks that fired from three separate places (see S2).
    ///
    /// Cancels any previous scheduled fetch before starting a new one. Do not move
    /// that cancel into `refreshModelList` — see the self-cancel note there.
    func scheduleModelListRefresh() {
        modelFetchTask?.cancel()
        modelFetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Yield once so the calling mutation (provider/profile/modelName swap)
            // has fully settled before we read state inside refreshModelList.
            await Task.yield()
            guard !Task.isCancelled else { return }
            await self.refreshModelList()
        }
    }

    /// Built-in fallback shown before the first successful fetch, or when listing fails.
    var fallbackModelCatalog: [String] {
        agentProviderID == .openaiCodex
            ? AgentModelListService.codexSubscriptionModels
            : agentProviderID.recommendedModels
    }


    func toggleAppearanceMode() {
        setAppearanceMode(appearanceMode.toggled)
    }

    /**
     * 切换应用主题，并在发布 SwiftUI 状态前同步原生控件使用的主题运行时。
     */
    func setAppearanceMode(_ mode: WeiBeiAppearanceMode) {
        guard appearanceMode != mode else {
            WeiBeiThemeRuntime.mode = mode
            return
        }
        WeiBeiThemeRuntime.mode = mode
        let transaction = Transaction(animation: WeiBeiMotion.appearance)
        withTransaction(transaction) {
            appearanceMode = mode
        }
        NotificationCenter.default.post(name: WeiBeiThemeRuntime.didChangeNotification, object: mode)
        save()
    }

    func setDailyInspirationEnabled(_ enabled: Bool) {
        guard showDailyInspiration != enabled else { return }
        showDailyInspiration = enabled
        save()
    }

    func toggleImportedDocumentColorAdaptation() {
        setImportedDocumentColorAdaptation(!adaptImportedDocumentColors)
    }

    func setImportedDocumentColorAdaptation(_ enabled: Bool) {
        guard adaptImportedDocumentColors != enabled else { return }
        adaptImportedDocumentColors = enabled
        save()
    }

    func setInterfaceLanguage(_ language: WeiBeiInterfaceLanguage) {
        guard interfaceLanguage != language else { return }
        interfaceLanguage = language
        floatingSelectionPrompt = ui("当前选区", "Current selection")
        _ = refreshStudyLocationReferenceTitles()
        save()
    }

    func saveOpenAIAPIKey() {
        do {
            let cleanedKey = OpenAIAPIKeyStore.cleaned(openAIAPIKey)
            // Keep legacy per-provider key for compatibility with older paths.
            try OpenAIAPIKeyStore.save(cleanedKey, provider: agentProviderID.piProviderName)
            try AgentCredentialProfileStore.saveAPIKey(cleanedKey, profileID: activeAgentProfileID)
            openAIAPIKey = cleanedKey
            touchActiveAgentProfileMetadata()
            openAIKeyStatus = cleanedKey.isEmpty
                ? ui("已清除密钥。", "Key cleared.")
                : ui("密钥已保存到当前配置。", "Key saved to the current profile.")
        } catch {
            openAIKeyStatus = ui("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)")
        }
    }

    func clearOpenAIAPIKey() {
        openAIAPIKey = ""
        saveOpenAIAPIKey()
    }

    func setAgentAuthMethod(_ method: AgentAuthMethod) {
        guard agentAuthMethod != method else { return }
        agentAuthMethod = method
        touchActiveAgentProfileMetadata()
    }

    func selectAgentCredentialProfile(_ id: UUID) {
        guard let profile = agentCredentialProfiles.first(where: { $0.id == id }) else { return }
        activeAgentProfileID = id
        AgentCredentialProfileStore.setActiveProfileID(id)
        agentProviderID = profile.provider
        agentAuthMethod = profile.authMethod
        modelName = profile.modelName
        agentBaseURL = profile.baseURL
        openAIAPIKey = AgentCredentialProfileStore.loadAPIKey(profileID: id)
        if openAIAPIKey.isEmpty {
            openAIAPIKey = OpenAIAPIKeyStore.load(provider: profile.provider.piProviderName)
        }
        openAIKeyStatus = nil
        // Clear the stale model list from the previous profile, then kick off a fresh
        // fetch from the Store itself (single originator — see S2). Previously this
        // only cleared and relied on the UI's onChange hooks to refetch, which raced
        // when several hooks fired at once.
        availableModels = []
        modelListStatus = .idle
        save()
        scheduleModelListRefresh()
    }

    @discardableResult
    func createAgentCredentialProfile(name: String? = nil) -> UUID {
        let cleanedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profile = AgentCredentialProfile(
            name: cleanedName.isEmpty
                ? ui("配置 \(agentCredentialProfiles.count + 1)", "Profile \(agentCredentialProfiles.count + 1)")
                : cleanedName,
            provider: agentProviderID,
            authMethod: agentAuthMethod,
            modelName: modelName,
            baseURL: agentBaseURL
        )
        agentCredentialProfiles.append(profile)
        AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
        // Seed the new profile's app-owned credential file from the current key.
        if !openAIAPIKey.isEmpty {
            try? AgentCredentialProfileStore.saveAPIKey(openAIAPIKey, profileID: profile.id)
        }
        selectAgentCredentialProfile(profile.id)
        return profile.id
    }

    func renameActiveAgentCredentialProfile(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        guard let index = agentCredentialProfiles.firstIndex(where: { $0.id == activeAgentProfileID }) else { return }
        agentCredentialProfiles[index].name = cleaned
        agentCredentialProfiles[index].updatedAt = Date()
        AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
    }

    func deleteActiveAgentCredentialProfile() {
        guard agentCredentialProfiles.count > 1,
              let index = agentCredentialProfiles.firstIndex(where: { $0.id == activeAgentProfileID }) else { return }
        let removed = agentCredentialProfiles.remove(at: index)
        try? AgentCredentialProfileStore.deleteAPIKey(profileID: removed.id)
        AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
        if let next = agentCredentialProfiles.first {
            selectAgentCredentialProfile(next.id)
        }
    }

    func openAgentProviderConsole(login: Bool) {
        let url = login
            ? AgentProviderConsoleLinks.accountURL(for: agentProviderID)
                ?? AgentProviderConsoleLinks.loginURL(for: agentProviderID)
            : AgentProviderConsoleLinks.loginURL(for: agentProviderID)
        guard let url else {
            openAIKeyStatus = ui(
                "自定义提供商请在本页填写 Base URL 与密钥。",
                "For a custom provider, enter Base URL and API key on this page."
            )
            return
        }
        NSWorkspace.shared.open(url)
        openAIKeyStatus = ui(
            "已在浏览器打开提供商页面。登录后创建密钥并粘贴回来。",
            "Opened the provider page in your browser. Sign in, create a key, then paste it here."
        )
    }

    func touchActiveAgentProfileMetadata() {
        guard let index = agentCredentialProfiles.firstIndex(where: { $0.id == activeAgentProfileID }) else {
            bootstrapAgentCredentialProfilesIfNeeded()
            return
        }
        agentCredentialProfiles[index].provider = agentProviderID
        agentCredentialProfiles[index].authMethod = agentAuthMethod
        agentCredentialProfiles[index].modelName = modelName
        agentCredentialProfiles[index].baseURL = agentBaseURL
        agentCredentialProfiles[index].updatedAt = Date()
        AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
        AgentCredentialProfileStore.setActiveProfileID(activeAgentProfileID)
    }

    func bootstrapAgentCredentialProfilesIfNeeded() {
        if agentCredentialProfiles.isEmpty {
            let seeded = AgentCredentialProfile(
                name: ui("默认", "Default"),
                provider: agentProviderID,
                authMethod: agentAuthMethod,
                modelName: modelName,
                baseURL: agentBaseURL
            )
            agentCredentialProfiles = [seeded]
            activeAgentProfileID = seeded.id
            AgentCredentialProfileStore.saveProfiles(agentCredentialProfiles)
            AgentCredentialProfileStore.setActiveProfileID(seeded.id)
            if !openAIAPIKey.isEmpty {
                try? AgentCredentialProfileStore.saveAPIKey(openAIAPIKey, profileID: seeded.id)
            }
        }
    }

}
