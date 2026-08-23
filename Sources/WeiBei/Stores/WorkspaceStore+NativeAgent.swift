import Foundation
import WeiBeiCore

@MainActor
extension WorkspaceStore {
    func cancelStudyAgentRuntimes() async {
        await NativeAgentRuntimeBox.runtime?.cancel()
    }

    func dispatchStudyAgentRequest(
        _ request: StudyAgentRequest,
        provider selectedProvider: AgentProviderID,
        target: AgentConversationTarget,
        replyMessageID: UUID,
        hostToolHandler: @escaping StudyAgentHostToolHandler
    ) async throws -> StudyAgentReply {
        try await executeNativeStudyAgentRequest(
            request,
            provider: selectedProvider,
            target: target,
            replyMessageID: replyMessageID,
            hostToolHandler: hostToolHandler
        )
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
        let resources = try AgentResources.bundled()
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
            skillRegistry: try NativeSkillRegistry.load(from: resources.skillsURL)
        )
        let runtime = NativeStudyAgentRuntime(
            model: model,
            adapter: adapter,
            ledgerRoot: workspaceDirectory.appendingPathComponent("NativeAgent/Ledgers", isDirectory: true),
            systemPromptText: resources.systemPrompt,
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
