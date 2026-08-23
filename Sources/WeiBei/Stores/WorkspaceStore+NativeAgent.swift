import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func submitAgentVisualizationAction(_ action: String, payloadJSON: String) -> String? {
        let action = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            return ui("这个按钮没有可执行的回答操作。", "This button has no executable response action.")
        }
        guard action.count <= 200 else {
            return ui("这个互动操作名称过长，未提交回答。", "This interactive action name is too long, so nothing was submitted.")
        }
        guard payloadJSON.utf8.count <= 65_536 else {
            return ui("互动数据过大，无法提交回答。", "The interactive data is too large to submit.")
        }
        guard (try? JSONSerialization.jsonObject(
            with: Data(payloadJSON.utf8),
            options: .fragmentsAllowed
        )) != nil else {
            return ui("互动数据无法读取，未提交回答。", "The interactive data could not be read, so nothing was submitted.")
        }
        guard agentRequestTask == nil, !isAskingAgent, !isStoppingAgent else {
            return isAgentRunningInActiveChat
                ? ui("这个互动操作正在处理中。", "This interactive action is being processed.")
                : ui("另一条回答正在处理，请稍候。", "Another response is being processed. Please wait.")
        }
        return askAgent(
            replayingSelections: [],
            visibleQuestionOverride: ui(
                "互动操作：\(action)",
                "Interactive action: \(action)"
            ),
            questionOverride: ui(
                "我在互动界面中执行了「\(action)」。当前界面数据：\(payloadJSON)",
                "I used “\(action)” in the interactive view. Current view data: \(payloadJSON)"
            )
        )
    }

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
        let endpoint = try AgentProviderEndpoint(
            provider: selectedProvider,
            baseURL: agentBaseURL
        )
        let selectedModel = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let routedModel = NativeProviderRouting.route(selectedProvider).defaultModel
        let model = selectedModel.isEmpty
            ? (routedModel.isEmpty ? "deepseek-chat" : routedModel)
            : selectedModel
        let adapter = try await NativeLLMAdapterFactory.make(
            provider: selectedProvider,
            model: model,
            endpoint: endpoint
        )
        let systemPrompt = (try? PiAgentResources.bundled().systemPrompt) ?? "you are webi"
        let skillRoot = try? PiAgentResources.bundled().skillsURL
        let liveStores = NativeLiveStores(
            learning: { [weak self] in
                await MainActor.run {
                    self?.makeLearningContext(target: target) ?? .empty
                }
            },
            profile: { [weak self] in
                await MainActor.run {
                    self?.refreshCourseProfileContext(target: target) ?? .empty
                }
            },
            persistLearningUpdate: { [weak self] update in
                await MainActor.run {
                    guard let self else {
                        return NativeStorePersistReceipt.rejected("工作区已关闭")
                    }
                    return self.persistNativeLearningUpdate(
                        update,
                        expectedContextRevision: request.contextRevision,
                        expectedUserQuestion: request.question,
                        target: target,
                        messageID: replyMessageID
                    )
                }
            },
            persistCourseProfileUpdate: { [weak self] update in
                await MainActor.run {
                    guard let self else {
                        return NativeStorePersistReceipt.rejected("工作区已关闭")
                    }
                    return self.persistNativeCourseProfileUpdate(
                        update,
                        expectedContextRevision: request.contextRevision,
                        target: target
                    )
                }
            },
            documentsRoot: workspaceDirectory.appendingPathComponent("NativeAgent/Documents", isDirectory: true),
            skillRegistry: skillRoot.flatMap { try? NativeSkillRegistry.load(from: $0) } ?? NativeSkillRegistry()
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
