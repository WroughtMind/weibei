import Foundation
import WeiBeiCore

@MainActor
final class AgentConversationRun {
    let chatID: UUID?
    var courseID: UUID?
    var selectionThreadID: UUID?
    var baseURL = ""
    var modelName = ""
    var runtime: NativeStudyAgentRuntime?
    let streaming = AgentStreamingState()

    init(chatID: UUID?) { self.chatID = chatID }
    var isAskingAgent: Bool = false
    var isStoppingAgent: Bool = false
    var activeAgentRequestID: UUID? = nil
    var activeAgentReplyMessageID: UUID? = nil
    var latestAgentStreamingText: String = ""
    var lastAgentStreamingPublishNanoseconds: UInt64 = 0
    var agentReplyIDsThatDisplayedStreamingText: Set<UUID> = []
    var agentVisualizationIDsUpdatingHistory: Set<String> = []
    var activeAgentReplyChatID: UUID? = nil
    var agentRequestTask: Task<Void, Never>? = nil
    var agentStopTask: Task<Void, Never>? = nil
    lazy var pump = AgentStreamingDisplayPump(hooks: .init(
        append: { [weak self] text in self?.streaming.text.append(text) },
        replace: { [weak self] text in self?.streaming.text = text },
        didDrain: { [weak self] in
            self?.streaming.finishDisplaying()
            self?.latestAgentStreamingText = ""
        }
    ))
}

enum AgentConversationExecution {
    @TaskLocal static var run: AgentConversationRun?
}

extension WorkspaceStore {
    var agentRun: AgentConversationRun {
        AgentConversationExecution.run ?? activeStudySessionID.flatMap { agentRuns[$0] } ?? idleAgentRun
    }
    var agentStreaming: AgentStreamingState { agentRun.streaming }
    var agentStreamingDisplayPump: AgentStreamingDisplayPump { agentRun.pump }
    var isAskingAgent: Bool {
        get { agentRun.isAskingAgent }
        set { objectWillChange.send(); agentRun.isAskingAgent = newValue }
    }
    var isStoppingAgent: Bool {
        get { agentRun.isStoppingAgent }
        set { objectWillChange.send(); agentRun.isStoppingAgent = newValue }
    }
    var activeAgentRequestID: UUID? {
        get { agentRun.activeAgentRequestID }
        set { agentRun.activeAgentRequestID = newValue }
    }
    var activeAgentReplyMessageID: UUID? {
        get { agentRun.activeAgentReplyMessageID }
        set { agentRun.activeAgentReplyMessageID = newValue }
    }
    var latestAgentStreamingText: String {
        get { agentRun.latestAgentStreamingText }
        set { agentRun.latestAgentStreamingText = newValue }
    }
    var lastAgentStreamingPublishNanoseconds: UInt64 {
        get { agentRun.lastAgentStreamingPublishNanoseconds }
        set { agentRun.lastAgentStreamingPublishNanoseconds = newValue }
    }
    var agentReplyIDsThatDisplayedStreamingText: Set<UUID> {
        get { agentRun.agentReplyIDsThatDisplayedStreamingText }
        set { agentRun.agentReplyIDsThatDisplayedStreamingText = newValue }
    }
    var agentVisualizationIDsUpdatingHistory: Set<String> {
        get { agentRun.agentVisualizationIDsUpdatingHistory }
        set { agentRun.agentVisualizationIDsUpdatingHistory = newValue }
    }
    var activeAgentReplyChatID: UUID? {
        get { agentRun.activeAgentReplyChatID }
        set { agentRun.activeAgentReplyChatID = newValue }
    }
    var agentRequestTask: Task<Void, Never>? {
        get { agentRun.agentRequestTask }
        set { agentRun.agentRequestTask = newValue }
    }
    var agentStopTask: Task<Void, Never>? {
        get { agentRun.agentStopTask }
        set { agentRun.agentStopTask = newValue }
    }
}
