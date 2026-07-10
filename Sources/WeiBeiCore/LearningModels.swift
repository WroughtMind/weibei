import Foundation

public struct NoteSourceLink: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var noteItemID: String
    public var sourceItemID: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        noteItemID: String,
        sourceItemID: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.noteItemID = noteItemID
        self.sourceItemID = sourceItemID
        self.createdAt = createdAt
    }
}

public struct StudyLocation: Codable, Hashable, Sendable {
    public var itemID: String
    public var itemTitle: String
    public var locationTitle: String?
    public var pageIndex: Int?
    public var lastStudiedAt: Date
    public var visitCount: Int

    public init(
        itemID: String,
        itemTitle: String,
        locationTitle: String? = nil,
        pageIndex: Int? = nil,
        lastStudiedAt: Date = Date(),
        visitCount: Int = 1
    ) {
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.locationTitle = locationTitle
        self.pageIndex = pageIndex
        self.lastStudiedAt = lastStudiedAt
        self.visitCount = visitCount
    }
}

public enum LearningMemoryKind: String, Codable, CaseIterable, Hashable, Sendable {
    case goal
    case understood
    case confusion
    case nextStep
    case preference
}

public enum LearningMemoryOrigin: String, Codable, Hashable, Sendable {
    case userStatement
    case agentInference
    case observed
}

public enum LearningMemoryStatus: String, Codable, Hashable, Sendable {
    case active
    case resolved
}

public struct LearningMemoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: LearningMemoryKind
    public var text: String
    public var evidence: String
    public var origin: LearningMemoryOrigin
    public var status: LearningMemoryStatus
    public var sessionID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: LearningMemoryKind,
        text: String,
        evidence: String,
        origin: LearningMemoryOrigin,
        status: LearningMemoryStatus = .active,
        sessionID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.evidence = evidence
        self.origin = origin
        self.status = status
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum StudyPhase: String, Codable, CaseIterable, Hashable, Sendable {
    case orient
    case explore
    case closeRead
    case note
    case recall
    case consolidate
    case plan
}

public struct StudyFlowState: Codable, Hashable, Sendable {
    public var phase: StudyPhase
    public var pinnedByUser: Bool
    public var suggestedNext: [String]

    public init(
        phase: StudyPhase = .orient,
        pinnedByUser: Bool = false,
        suggestedNext: [String] = []
    ) {
        self.phase = phase
        self.pinnedByUser = pinnedByUser
        self.suggestedNext = suggestedNext
    }
}

public struct StudySession: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var messages: [AgentMessage]
    public var summary: String
    public var focusItemIDs: [String]
    public var flow: StudyFlowState
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        messages: [AgentMessage] = [],
        summary: String = "",
        focusItemIDs: [String] = [],
        flow: StudyFlowState = StudyFlowState(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.summary = summary
        self.focusItemIDs = focusItemIDs
        self.flow = flow
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
