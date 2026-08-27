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
    public var locationID: String?
    public var locationTitle: String?
    public var pageIndex: Int?
    public var lastStudiedAt: Date
    public var visitCount: Int

    public init(
        itemID: String,
        itemTitle: String,
        locationID: String? = nil,
        locationTitle: String? = nil,
        pageIndex: Int? = nil,
        lastStudiedAt: Date = Date(),
        visitCount: Int = 1
    ) {
        self.itemID = itemID
        self.itemTitle = itemTitle
        self.locationID = locationID
        self.locationTitle = locationTitle
        self.pageIndex = pageIndex
        self.lastStudiedAt = lastStudiedAt
        self.visitCount = visitCount
    }
}

public struct CourseResumePoint: Identifiable, Codable, Hashable, Sendable {
    public var courseID: UUID
    public var materialLocation: StudyLocation?
    public var chatID: UUID?
    public var noteItemID: String?
    public var savedAt: Date

    public var id: UUID { courseID }

    public init(
        courseID: UUID,
        materialLocation: StudyLocation? = nil,
        chatID: UUID? = nil,
        noteItemID: String? = nil,
        savedAt: Date = Date()
    ) {
        self.courseID = courseID
        self.materialLocation = materialLocation
        self.chatID = chatID
        self.noteItemID = noteItemID
        self.savedAt = savedAt
    }
}

public enum LearningMemoryKind: String, Codable, CaseIterable, Hashable, Sendable {
    case goal
    case progress
    case understood
    case confusion
    case nextStep
    case summary
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

public enum LearningMemoryScope: Codable, Hashable, Sendable {
    case global
    case course(UUID)

    public var courseID: UUID? {
        guard case let .course(courseID) = self else { return nil }
        return courseID
    }
}

public enum LearningMemoryRevisionActor: String, Codable, Hashable, Sendable {
    case user
    case agent
    case migration
}

public struct LearningMemoryRevisionRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var revision: UInt64
    public var kind: LearningMemoryKind
    public var text: String
    public var evidence: String
    public var origin: LearningMemoryOrigin
    public var status: LearningMemoryStatus
    public var sessionID: UUID?
    public var messageID: UUID?
    public var resolutionEvidence: String?
    public var actor: LearningMemoryRevisionActor
    public var recordedAt: Date

    public init(
        id: UUID = UUID(),
        revision: UInt64,
        kind: LearningMemoryKind,
        text: String,
        evidence: String,
        origin: LearningMemoryOrigin,
        status: LearningMemoryStatus,
        sessionID: UUID? = nil,
        messageID: UUID? = nil,
        resolutionEvidence: String? = nil,
        actor: LearningMemoryRevisionActor,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.revision = revision
        self.kind = kind
        self.text = text
        self.evidence = evidence
        self.origin = origin
        self.status = status
        self.sessionID = sessionID
        self.messageID = messageID
        self.resolutionEvidence = resolutionEvidence
        self.actor = actor
        self.recordedAt = recordedAt
    }
}

public struct LearningMemoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: LearningMemoryKind
    public var text: String
    public var evidence: String
    public var origin: LearningMemoryOrigin
    public var status: LearningMemoryStatus
    public var sessionID: UUID?
    public var messageID: UUID?
    public var resolvedAt: Date?
    public var resolutionEvidence: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Missing only on legacy snapshots before scoped memory migration.
    public var revisions: [LearningMemoryRevisionRecord]?

    public init(
        id: UUID = UUID(),
        kind: LearningMemoryKind,
        text: String,
        evidence: String,
        origin: LearningMemoryOrigin,
        status: LearningMemoryStatus = .active,
        sessionID: UUID? = nil,
        messageID: UUID? = nil,
        resolvedAt: Date? = nil,
        resolutionEvidence: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revisions: [LearningMemoryRevisionRecord]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.evidence = evidence
        self.origin = origin
        self.status = status
        self.sessionID = sessionID
        self.messageID = messageID
        self.resolvedAt = resolvedAt
        self.resolutionEvidence = resolutionEvidence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revisions = revisions
    }
}

public struct ScopedLearningMemoryState: Codable, Hashable, Sendable {
    public var scope: LearningMemoryScope
    public var revision: UInt64
    public var entries: [LearningMemoryEntry]

    public init(
        scope: LearningMemoryScope,
        revision: UInt64 = 0,
        entries: [LearningMemoryEntry] = []
    ) {
        self.scope = scope
        self.revision = revision
        self.entries = entries
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
    public var titleSetByUser: Bool
    public var messages: [AgentMessage]
    public var summary: String
    /// Courses this Chat has actually used. Chat itself remains global.
    public var relatedCourseIDs: [UUID]
    public var focusItemIDs: [String]
    /// Preferred material for grouping (scheme A). Optional for older workspaces.
    public var materialItemID: String?
    public var flow: StudyFlowState
    public var createdAt: Date
    public var updatedAt: Date
    /// Count of chat messages when the body lives in the per-session file.
    /// The main snapshot stores this instead of embedding `messages`.
    public var messageCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        titleSetByUser: Bool = false,
        messages: [AgentMessage] = [],
        summary: String = "",
        courseID: UUID? = nil,
        scopeNeedsReview: Bool = false,
        relatedCourseIDs: [UUID]? = nil,
        focusItemIDs: [String] = [],
        materialItemID: String? = nil,
        flow: StudyFlowState = StudyFlowState(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messageCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.titleSetByUser = titleSetByUser
        self.messages = messages
        self.summary = summary
        self.relatedCourseIDs = Self.normalizedCourseIDs(
            relatedCourseIDs ?? [courseID].compactMap { $0 }
        )
        self.focusItemIDs = focusItemIDs
        self.materialItemID = materialItemID
        self.flow = flow
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount ?? messages.count
    }

    /// True when this chat has history, including sessions whose messages
    /// are not loaded yet and only have a persisted count.
    public var hasChatHistory: Bool {
        !messages.isEmpty || messageCount > 0
    }

    /// List/hub count: loaded body wins, otherwise the persisted count.
    public var displayedMessageCount: Int {
        messages.isEmpty ? messageCount : messages.count
    }

    public var groupingMaterialItemID: String? {
        materialItemID ?? focusItemIDs.first
    }

    // Compatibility while call sites move from fixed Chat scope to associations.
    public var courseID: UUID? {
        get { relatedCourseIDs.count == 1 ? relatedCourseIDs.first : nil }
        set { relatedCourseIDs = [newValue].compactMap { $0 } }
    }

    public var scopeNeedsReview: Bool? {
        get { false }
        set { }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case titleSetByUser
        case messages
        case summary
        case relatedCourseIDs
        case courseID
        case scopeNeedsReview
        case focusItemIDs
        case materialItemID
        case flow
        case createdAt
        case updatedAt
        case messageCount
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        titleSetByUser = try values.decodeIfPresent(Bool.self, forKey: .titleSetByUser) ?? false
        messages = try values.decodeIfPresent([AgentMessage].self, forKey: .messages) ?? []
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        let current = try values.decodeIfPresent([UUID].self, forKey: .relatedCourseIDs)
        let legacy = try values.decodeIfPresent(UUID.self, forKey: .courseID)
        relatedCourseIDs = Self.normalizedCourseIDs(current ?? [legacy].compactMap { $0 })
        focusItemIDs = try values.decodeIfPresent([String].self, forKey: .focusItemIDs) ?? []
        materialItemID = try values.decodeIfPresent(String.self, forKey: .materialItemID)
        flow = try values.decodeIfPresent(StudyFlowState.self, forKey: .flow) ?? StudyFlowState()
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        messageCount = try values.decodeIfPresent(Int.self, forKey: .messageCount)
            ?? messages.count
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(titleSetByUser, forKey: .titleSetByUser)
        try values.encode(messages, forKey: .messages)
        try values.encode(summary, forKey: .summary)
        try values.encode(relatedCourseIDs, forKey: .relatedCourseIDs)
        try values.encode(focusItemIDs, forKey: .focusItemIDs)
        try values.encodeIfPresent(materialItemID, forKey: .materialItemID)
        try values.encode(flow, forKey: .flow)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(
            messages.isEmpty ? messageCount : messages.count,
            forKey: .messageCount
        )
    }

    private static func normalizedCourseIDs(_ courseIDs: [UUID]) -> [UUID] {
        Array(Set(courseIDs)).sorted { $0.uuidString < $1.uuidString }
    }
}
