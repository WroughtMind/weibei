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
        if let raw = endpoint.baseURL, let url = URL(string: raw) {
            return url
        }
        switch provider {
        case .deepseek:
            return URL(string: "https://api.deepseek.com/v1")
        case .openai:
            return URL(string: "https://api.openai.com/v1")
        case .openrouter:
            return URL(string: "https://openrouter.ai/api/v1")
        case .moonshotai, .moonshotaiCN:
            return URL(string: "https://api.moonshot.ai/v1")
        default:
            return nil
        }
    }
}
