import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func cancelStudyAgentRuntimes() async {
        await NativeAgentRuntimeBox.runtime?.cancel()
        await piRuntime.cancel()
    }

    func dispatchStudyAgentRequest(
        _ request: StudyAgentRequest,
        provider selectedProvider: AgentProviderID,
        target: AgentConversationTarget,
        replyMessageID: UUID,
        hostToolHandler: @escaping StudyAgentHostToolHandler
    ) async throws -> StudyAgentReply {
        if NativeAgentBackendSelection.current == .native {
            return try await executeNativeStudyAgentRequest(
                request,
                provider: selectedProvider,
                target: target,
                replyMessageID: replyMessageID,
                hostToolHandler: hostToolHandler
            )
        }
        return try await executePiStudyAgentRequest(
            request,
            provider: selectedProvider,
            target: target,
            replyMessageID: replyMessageID,
            hostToolHandler: hostToolHandler
        )
    }

    private func executePiStudyAgentRequest(
        _ request: StudyAgentRequest,
        provider selectedProvider: AgentProviderID,
        target: AgentConversationTarget,
        replyMessageID: UUID,
        hostToolHandler: @escaping StudyAgentHostToolHandler
    ) async throws -> StudyAgentReply {
        let selectedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = try AgentProviderEndpoint(
            provider: selectedProvider,
            baseURL: agentBaseURL
        )
        if selectedProvider == .azureOpenAI {
            let credentialIsBound = try await piRuntime.managementCatalog()
                .credentials
                .contains {
                    $0.providerId == endpoint.piProviderID
                        && $0.type == .apiKey
                        && $0.boundEndpoint == endpoint.baseURL
                }
            guard credentialIsBound else {
                throw AgentProviderEndpointError.azureCredentialRequiresReentry
            }
        }
        await piRuntime.configure(
            PiAgentProviderConfiguration(
                provider: endpoint.piProviderID,
                model: selectedModel.isEmpty ? nil : selectedModel,
                baseURL: endpoint.baseURL
            )
        )
        try await piRuntime.writeCustomModelsJSONIfNeeded(
            providerID: selectedProvider,
            baseURL: endpoint.baseURL ?? "",
            model: selectedModel
        )
        return try await piRuntime.respond(
            to: request,
            sessionID: target.sessionID,
            workingDirectory: target.workingDirectory,
            hostToolHandler: hostToolHandler,
            sessionTitleHandler: { [weak self] title in
                await self?.applySemanticSessionTitleAndSave(title, to: target.sessionID)
            }
        ) { [weak self] progress in
            await self?.applyAgentProgress(
                progress,
                requestID: request.id,
                replyMessageID: replyMessageID,
                chatID: target.sessionID
            )
        }
    }

    private func executeNativeStudyAgentRequest(
        _ request: StudyAgentRequest,
        provider selectedProvider: AgentProviderID,
        target: AgentConversationTarget,
        replyMessageID: UUID,
        hostToolHandler: @escaping StudyAgentHostToolHandler
    ) async throws -> StudyAgentReply {
        if selectedProvider.kind == .subscription {
            throw NativeLLMFailure(
                code: "unsupported_provider",
                message: ui(
                    "原生引擎第一棒尚未接入订阅登录，请改用 API Key 服务商，或先不设置 WEIBEI_AGENT_BACKEND。",
                    "Native backend baton 1 does not support subscription login yet. Use an API-key provider, or leave WEIBEI_AGENT_BACKEND unset."
                )
            )
        }
        let endpoint = try AgentProviderEndpoint(
            provider: selectedProvider,
            baseURL: agentBaseURL
        )
        guard let baseURL = NativeChatCompletionsRoute.baseURL(
            provider: selectedProvider,
            endpoint: endpoint
        ) else {
            throw NativeLLMFailure(
                code: "unsupported_provider",
                message: ui(
                    "当前服务商还不在原生 OpenAI 兼容族里。",
                    "This provider is not on the native OpenAI-compatible family yet."
                )
            )
        }
        guard let apiKey = try NativeAgentCredentialStore.apiKey(forProviderID: selectedProvider.rawValue) else {
            throw NativeLLMFailure(code: "unauthorized", status: 401, message: "missing API key")
        }
        let selectedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = selectedModel.isEmpty ? "deepseek-chat" : selectedModel
        let adapter = OpenAIChatCompletionsProvider(baseURL: baseURL, apiKey: apiKey)
        let systemPrompt = (try? PiAgentResources.bundled().systemPrompt) ?? "you are webi"
        let liveStores = NativeLiveStores(
            learning: { [weak self] in
                await MainActor.run {
                    self?.makeLearningContext(target: target) ?? .empty
                }
            }
        )
        let runtime = NativeStudyAgentRuntime(
            model: model,
            adapter: adapter,
            ledgerRoot: workspaceDirectory.appendingPathComponent("NativeAgent/Ledgers", isDirectory: true),
            systemPromptText: systemPrompt,
            hostToolHandler: hostToolHandler,
            liveStores: liveStores
        )
        NativeAgentRuntimeBox.runtime = runtime
        defer { NativeAgentRuntimeBox.runtime = nil }
        return try await runtime.respond(
            to: request,
            progress: { [weak self] progress in
                await self?.applyAgentProgress(
                    progress,
                    requestID: request.id,
                    replyMessageID: replyMessageID,
                    chatID: target.sessionID
                )
            }
        )
    }
}

@MainActor
enum NativeAgentRuntimeBox {
    static var runtime: NativeStudyAgentRuntime?
}
