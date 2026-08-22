import Foundation

public enum NativeAgentBackendSelection {
    public static let debugDefaultsKey = "weibei.debug.studyAgentBackend"

    public static var current: StudyAgentBackend {
        if let env = environmentValue {
            return env
        }
        return persistedDebugBackend ?? .pi
    }

    public static var persistedDebugBackend: StudyAgentBackend? {
        get {
            switch UserDefaults.standard.string(forKey: debugDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() {
            case "native":
                return .native
            case "pi":
                return .pi
            default:
                return nil
            }
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: debugDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: debugDefaultsKey)
            }
        }
    }

    private static var environmentValue: StudyAgentBackend? {
        let raw = ProcessInfo.processInfo.environment["WEIBEI_AGENT_BACKEND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if raw.isEmpty { return nil }
        return raw == "native" ? .native : .pi
    }
}

public struct NativeLiveStores: Sendable {
    public var learning: (@Sendable () async -> StudyAgentLearningContext)?
    public var profile: (@Sendable () async -> StudyAgentCourseProfileContext)?
    public var documentsRoot: URL?
    public var skillRegistry: NativeSkillRegistry
    public var startSubagent: (@Sendable (NativeSubagentRequest) async -> NativeSubagentResult)?

    public init(
        learning: (@Sendable () async -> StudyAgentLearningContext)? = nil,
        profile: (@Sendable () async -> StudyAgentCourseProfileContext)? = nil,
        documentsRoot: URL? = nil,
        skillRegistry: NativeSkillRegistry = NativeSkillRegistry(),
        startSubagent: (@Sendable (NativeSubagentRequest) async -> NativeSubagentResult)? = nil
    ) {
        self.learning = learning
        self.profile = profile
        self.documentsRoot = documentsRoot
        self.skillRegistry = skillRegistry
        self.startSubagent = startSubagent
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
