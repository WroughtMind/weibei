import Foundation

public enum NativeAgentBackendSelection {
    public static var current: StudyAgentBackend {
        let raw = ProcessInfo.processInfo.environment["WEIBEI_AGENT_BACKEND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return raw == "native" ? .native : .pi
    }
}

public struct NativeLiveStores: Sendable {
    public var learning: (@Sendable () async -> StudyAgentLearningContext)?
    public var profile: (@Sendable () async -> StudyAgentCourseProfileContext)?

    public init(
        learning: (@Sendable () async -> StudyAgentLearningContext)? = nil,
        profile: (@Sendable () async -> StudyAgentCourseProfileContext)? = nil
    ) {
        self.learning = learning
        self.profile = profile
    }

    public static let empty = NativeLiveStores()
}

public enum NativeChatCompletionsRoute {
    public static func baseURL(
        provider: AgentProviderID,
        endpoint: AgentProviderEndpoint
    ) -> URL? {
        let routed = NativeProviderRouting.route(provider)
        guard routed.family == .openaiChatCompletions else { return nil }
        return NativeProviderRouting.resolvedBaseURL(provider: provider, endpoint: endpoint)
    }
}
