import Foundation

public struct NativeStorePersistReceipt: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case saved, unchanged, pending, rejected, failed
    }
    public var status: Status
    public var accepted: Bool { status == .saved || status == .unchanged || status == .pending }
    public var message: String
    public var memoryUpdate: AgentReplyMemoryUpdate?
    public var profileUpdate: AgentReplyProfileUpdate?
    public var action: AgentReplyAction?

    public init(
        status: Status,
        message: String,
        memoryUpdate: AgentReplyMemoryUpdate? = nil,
        profileUpdate: AgentReplyProfileUpdate? = nil,
        action: AgentReplyAction? = nil
    ) {
        self.status = status
        self.message = message
        self.memoryUpdate = memoryUpdate
        self.profileUpdate = profileUpdate
        self.action = action
    }

    public static func rejected(_ message: String) -> NativeStorePersistReceipt {
        NativeStorePersistReceipt(status: .rejected, message: message)
    }
}
public struct NativeLiveStores: Sendable {
    public var learning: (@Sendable () async -> StudyAgentLearningContext)?
    public var profile: (@Sendable () async -> StudyAgentCourseProfileContext)?
    public var persistLearningUpdate: (@Sendable (StudyAgentLearningUpdate) async -> NativeStorePersistReceipt)?
    public var persistCourseProfileUpdate: (@Sendable (StudyAgentCourseProfileUpdate) async -> NativeStorePersistReceipt)?
    public var performNoteProposal: (@Sendable (StudyAgentNoteProposal) async -> NativeStorePersistReceipt)?
    public var performRelationProposal: (@Sendable (StudyAgentRelationProposal) async -> NativeStorePersistReceipt)?
    public var displayVisualization: (@Sendable (AgentVisualization, [AgentMessageContentBlock]) async -> NativeToolExecutionResult)?
    public var documentsRoot: URL?
    public var skillRegistry: NativeSkillRegistry
    public var startSubagent: (@Sendable (NativeSubagentRequest) async -> NativeSubagentResult)?
    /// 写盘前的用户确认：宿主弹出确认浮层，返回 true 才落盘；false 表示用户取消。
    public var confirmDocumentCreation: (@Sendable (_ title: String, _ summary: String) async -> Bool)?

    public init(
        learning: (@Sendable () async -> StudyAgentLearningContext)? = nil,
        profile: (@Sendable () async -> StudyAgentCourseProfileContext)? = nil,
        persistLearningUpdate: (@Sendable (StudyAgentLearningUpdate) async -> NativeStorePersistReceipt)? = nil,
        persistCourseProfileUpdate: (@Sendable (StudyAgentCourseProfileUpdate) async -> NativeStorePersistReceipt)? = nil,
        performNoteProposal: (@Sendable (StudyAgentNoteProposal) async -> NativeStorePersistReceipt)? = nil,
        performRelationProposal: (@Sendable (StudyAgentRelationProposal) async -> NativeStorePersistReceipt)? = nil,
        displayVisualization: (@Sendable (AgentVisualization, [AgentMessageContentBlock]) async -> NativeToolExecutionResult)? = nil,
        documentsRoot: URL? = nil,
        skillRegistry: NativeSkillRegistry = NativeSkillRegistry(),
        startSubagent: (@Sendable (NativeSubagentRequest) async -> NativeSubagentResult)? = nil,
        confirmDocumentCreation: (@Sendable (_ title: String, _ summary: String) async -> Bool)? = nil
    ) {
        self.learning = learning
        self.profile = profile
        self.persistLearningUpdate = persistLearningUpdate
        self.persistCourseProfileUpdate = persistCourseProfileUpdate
        self.performNoteProposal = performNoteProposal
        self.performRelationProposal = performRelationProposal
        self.displayVisualization = displayVisualization
        self.documentsRoot = documentsRoot
        self.skillRegistry = skillRegistry
        self.startSubagent = startSubagent
        self.confirmDocumentCreation = confirmDocumentCreation
    }

    public static let empty = NativeLiveStores()
}
