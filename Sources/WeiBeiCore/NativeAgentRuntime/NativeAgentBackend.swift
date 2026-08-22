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

public struct NativeStorePersistReceipt: Sendable {
    public var accepted: Bool
    public var message: String
    public var memoryUpdate: AgentReplyMemoryUpdate?
    public var profileUpdate: AgentReplyProfileUpdate?

    public init(
        accepted: Bool,
        message: String,
        memoryUpdate: AgentReplyMemoryUpdate? = nil,
        profileUpdate: AgentReplyProfileUpdate? = nil
    ) {
        self.accepted = accepted
        self.message = message
        self.memoryUpdate = memoryUpdate
        self.profileUpdate = profileUpdate
    }

    public static func rejected(_ message: String) -> NativeStorePersistReceipt {
        NativeStorePersistReceipt(accepted: false, message: message)
    }
}

public struct NativeLiveStores: Sendable {
    public var learning: (@Sendable () async -> StudyAgentLearningContext)?
    public var profile: (@Sendable () async -> StudyAgentCourseProfileContext)?
    public var persistLearningUpdate: (@Sendable (StudyAgentLearningUpdate) async -> NativeStorePersistReceipt)?
    public var persistCourseProfileUpdate: (@Sendable (StudyAgentCourseProfileUpdate) async -> NativeStorePersistReceipt)?
    public var documentsRoot: URL?
    public var skillRegistry: NativeSkillRegistry
    public var startSubagent: (@Sendable (NativeSubagentRequest) async -> NativeSubagentResult)?

    public init(
        learning: (@Sendable () async -> StudyAgentLearningContext)? = nil,
        profile: (@Sendable () async -> StudyAgentCourseProfileContext)? = nil,
        persistLearningUpdate: (@Sendable (StudyAgentLearningUpdate) async -> NativeStorePersistReceipt)? = nil,
        persistCourseProfileUpdate: (@Sendable (StudyAgentCourseProfileUpdate) async -> NativeStorePersistReceipt)? = nil,
        documentsRoot: URL? = nil,
        skillRegistry: NativeSkillRegistry = NativeSkillRegistry(),
        startSubagent: (@Sendable (NativeSubagentRequest) async -> NativeSubagentResult)? = nil
    ) {
        self.learning = learning
        self.profile = profile
        self.persistLearningUpdate = persistLearningUpdate
        self.persistCourseProfileUpdate = persistCourseProfileUpdate
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
