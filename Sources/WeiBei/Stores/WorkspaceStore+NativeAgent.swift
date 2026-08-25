import Foundation
import WeiBeiCore

/// 互动操作被拒的类型化身份:测试按 case 断言;message 只负责展示。
/// agentRefused 的载荷是 askAgent 现场生成的完整说明文案。
enum AgentVisualizationActionRejection: Equatable {
    case emptyAction
    case actionNameTooLong
    case payloadTooLarge
    case payloadUnreadable
    case agentBusy(activeChat: Bool)
    case agentRefused(String)

    func message(_ ui: (String, String) -> String) -> String {
        switch self {
        case .emptyAction:
            return ui("这个按钮没有可执行的回答操作。", "This button has no executable response action.")
        case .actionNameTooLong:
            return ui("这个互动操作名称过长，未提交回答。", "This interactive action name is too long, so nothing was submitted.")
        case .payloadTooLarge:
            return ui("互动数据过大，无法提交回答。", "The interactive data is too large to submit.")
        case .payloadUnreadable:
            return ui("互动数据无法读取，未提交回答。", "The interactive data could not be read, so nothing was submitted.")
        case .agentBusy(activeChat: true):
            return ui("这个互动操作正在处理中。", "This interactive action is being processed.")
        case .agentBusy(activeChat: false):
            return ui("另一条回答正在处理，请稍候。", "Another response is being processed. Please wait.")
        case .agentRefused(let detail):
            return detail
        }
    }
}

@MainActor
extension WorkspaceStore {
    func submitAgentVisualizationAction(_ action: String, payloadJSON: String) -> AgentVisualizationActionRejection? {
        let action = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            return .emptyAction
        }
        guard action.count <= 200 else {
            return .actionNameTooLong
        }
        guard payloadJSON.utf8.count <= 65_536 else {
            return .payloadTooLarge
        }
        guard (try? JSONSerialization.jsonObject(
            with: Data(payloadJSON.utf8),
            options: .fragmentsAllowed
        )) != nil else {
            return .payloadUnreadable
        }
        guard agentRequestTask == nil, !isAskingAgent, !isStoppingAgent else {
            return .agentBusy(activeChat: isAgentRunningInActiveChat)
        }
        guard let refusal = askAgent(
            replayingSelections: [],
            visibleQuestionOverride: ui(
                "互动操作：\(action)",
                "Interactive action: \(action)"
            ),
            questionOverride: ui(
                "我在互动界面中执行了「\(action)」。当前界面数据：\(payloadJSON)",
                "I used “\(action)” in the interactive view. Current view data: \(payloadJSON)"
            )
        ) else { return nil }
        return .agentRefused(refusal)
    }

    var canCopyReference: Bool {
        hasSelectionAttachments || selectionContext != nil || hasSelectedMaterial || activeNoteItem?.isNotebookNote == true
    }

    var copyReferenceActionTitle: String {
        if hasSelectionAttachments || selectionContext != nil { return ui("复制选区引用", "Copy selection reference") }
        if hasSelectedMaterial { return ui("复制资料引用", "Copy material reference") }
        return ui("复制笔记引用", "Copy note reference")
    }

    var sendAgentActionTitle: String {
        isAgentRunningInActiveChat
            ? ui("停止回答", "Stop response")
            : ui("发送问题", "Send question")
    }

    var isAgentRunningInActiveChat: Bool {
        isAskingAgent && activeAgentReplyChatID == activeStudySessionID
    }

    var runningAgentChatTitle: String {
        guard let chatID = activeAgentReplyChatID,
              let session = studySessions.first(where: { $0.id == chatID }) else {
            return ui("另一条 Chat", "another Chat")
        }
        return session.title
    }

    var hasPersistedGeneratingAgentReply: Bool {
        messages.contains { $0.role == .assistant && $0.origin?.requestID == activeAgentRequestID }
    }

    func agentDisplayText(for message: AgentMessage) -> String {
        guard message.id == activeAgentReplyMessageID,
              message.completionState == .generating else {
            return message.text
        }
        return latestAgentStreamingText
    }

    func agentReplyDisplayedStreamingText(_ message: AgentMessage) -> Bool {
        agentReplyIDsThatDisplayedStreamingText.contains(message.id)
    }

    var isAgentStreamingSurfaceVisible: Bool {
        hasPrimaryConversationPaneVisible || agentSurface == .selectionFloat
    }

    func finishAgentStreamingDisplay() {
        StreamFinalizeProbe.log("STORE finishAgentStreamingDisplay (pump drained -> isStreaming flips false)")
        agentStreaming.finishDisplaying()
        latestAgentStreamingText = ""
    }

    func settleAgentStreamingDisplayImmediately() {
        guard agentStreaming.displayingMessageID != nil else { return }
        agentStreamingDisplayPump.settleImmediately(
            cumulativeText: latestAgentStreamingText
        )
    }

    func landAgentStreamingDisplayImmediately() {
        guard agentStreaming.displayingMessageID != nil else { return }
        agentStreamingDisplayPump.replaceImmediately(
            cumulativeText: latestAgentStreamingText
        )
    }

    func setAgentStreamingReduceMotion(_ enabled: Bool) {
        agentStreamingUsesReducedMotion = enabled
        guard enabled, agentStreaming.displayingMessageID != nil else { return }
        agentStreamingDisplayPump.replaceImmediately(
            cumulativeText: latestAgentStreamingText
        )
    }

    func landAgentStreamingDisplayIfHidden() {
        guard !isAgentStreamingSurfaceVisible else { return }
        landAgentStreamingDisplayImmediately()
    }

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
                guard let self else {
                    return NativeStorePersistReceipt.rejected("工作区已关闭")
                }
                return await self.persistNativeLearningUpdate(
                    update,
                    expectedContextRevision: request.contextRevision,
                    expectedUserQuestion: request.question,
                    target: target,
                    messageID: replyMessageID
                )
            },
            persistCourseProfileUpdate: { [weak self] update in
                guard let self else {
                    return NativeStorePersistReceipt.rejected("工作区已关闭")
                }
                return await self.persistNativeCourseProfileUpdate(
                    update,
                    expectedContextRevision: request.contextRevision,
                    target: target
                )
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
    static func agentFailureMessage(
        for error: Error,
        kind: AgentFailureKind,
        language: WeiBeiInterfaceLanguage
    ) -> String {
        if error is NativeAgentResourcesError {
            return language.text(
                NativeAgentResourcesError.agentComponentsIncompleteMessage,
                "Agent components are incomplete, so the Agent cannot start. Repair or reinstall WeiBei."
            )
        }
        return kind.userMessage(
            language: language,
            userFacingDetail: userFacingAgentFailureDetail(for: error),
            draftPreserved: true
        )
    }
}

@MainActor
enum NativeAgentRuntimeBox {
    static var runtime: NativeStudyAgentRuntime?
}
