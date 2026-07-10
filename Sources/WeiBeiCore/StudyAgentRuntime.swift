import Foundation

public enum StudyAgentPurpose: String, Codable, Sendable {
    case conversation
    case quietInsight
}

public enum StudyAgentWorkflow: String, Codable, Sendable {
    case automatic
    case studyCompanion
    case courseWayfinding
    case closeReading
    case noteMaking
    case recallPractice
}

public struct StudyAgentCourseCatalogItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: String
    public var role: String
    public var isCurrentMaterial: Bool
    public var isCurrentNote: Bool
    public var linkedItemIDs: [String]
    public var tags: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: String,
        role: String,
        isCurrentMaterial: Bool = false,
        isCurrentNote: Bool = false,
        linkedItemIDs: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.role = role
        self.isCurrentMaterial = isCurrentMaterial
        self.isCurrentNote = isCurrentNote
        self.linkedItemIDs = linkedItemIDs
        self.tags = tags
    }

    public init(item: StudyAgentCourseItem) {
        self.init(
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            kind: item.kind,
            role: item.role,
            isCurrentMaterial: item.isCurrentMaterial,
            isCurrentNote: item.isCurrentNote,
            linkedItemIDs: item.linkedItemIDs,
            tags: item.tags
        )
    }
}

public struct StudyAgentCourseItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: String
    public var role: String
    public var isCurrentMaterial: Bool
    public var isCurrentNote: Bool
    public var linkedItemIDs: [String]
    public var headings: [String]
    public var tags: [String]
    public var searchText: String
    public var isTruncated: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: String,
        role: String,
        isCurrentMaterial: Bool = false,
        isCurrentNote: Bool = false,
        linkedItemIDs: [String] = [],
        headings: [String] = [],
        tags: [String] = [],
        searchText: String = "",
        isTruncated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.role = role
        self.isCurrentMaterial = isCurrentMaterial
        self.isCurrentNote = isCurrentNote
        self.linkedItemIDs = linkedItemIDs
        self.headings = headings
        self.tags = tags
        self.searchText = searchText
        self.isTruncated = isTruncated
    }
}

public struct StudyAgentCourseRelation: Codable, Equatable, Sendable {
    public var noteItemID: String
    public var sourceItemID: String

    public init(noteItemID: String, sourceItemID: String) {
        self.noteItemID = noteItemID
        self.sourceItemID = sourceItemID
    }
}

public struct StudyAgentCourseContext: Codable, Equatable, Sendable {
    public var title: String
    public var catalog: [StudyAgentCourseCatalogItem]
    public var items: [StudyAgentCourseItem]
    public var relations: [StudyAgentCourseRelation]
    public var isTruncated: Bool

    public init(
        title: String,
        catalog: [StudyAgentCourseCatalogItem] = [],
        items: [StudyAgentCourseItem] = [],
        relations: [StudyAgentCourseRelation] = [],
        isTruncated: Bool = false
    ) {
        self.title = title
        self.catalog = catalog.isEmpty ? items.map(StudyAgentCourseCatalogItem.init(item:)) : catalog
        self.items = items
        self.relations = relations
        self.isTruncated = isTruncated
    }

    public static let empty = StudyAgentCourseContext(title: "Course")
}

public struct StudyAgentSessionSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var phase: String
    public var focusItemIDs: [String]
    public var turnCount: Int

    public init(
        id: String,
        title: String,
        summary: String,
        phase: String,
        focusItemIDs: [String],
        turnCount: Int
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.phase = phase
        self.focusItemIDs = focusItemIDs
        self.turnCount = turnCount
    }
}

public struct StudyAgentLearningContext: Codable, Equatable, Sendable {
    public var memoryRevision: UInt64
    public var lastLocation: StudyLocation?
    public var memories: [LearningMemoryEntry]
    public var session: StudyAgentSessionSnapshot?

    public init(
        memoryRevision: UInt64 = 0,
        lastLocation: StudyLocation? = nil,
        memories: [LearningMemoryEntry] = [],
        session: StudyAgentSessionSnapshot? = nil
    ) {
        self.memoryRevision = memoryRevision
        self.lastLocation = lastLocation
        self.memories = memories
        self.session = session
    }

    public static let empty = StudyAgentLearningContext()
}

public struct StudyAgentRequest: Sendable {
    public var id: UUID
    public var purpose: StudyAgentPurpose
    public var workflow: StudyAgentWorkflow
    public var question: String
    public var materialTitle: String
    public var materialText: String
    public var noteTitle: String
    public var noteText: String
    public var selectionTitle: String?
    public var selectionText: String?
    public var recentMessages: [AgentMessage]
    public var courseContext: StudyAgentCourseContext
    public var learningContext: StudyAgentLearningContext
    public var language: WeiBeiInterfaceLanguage
    public var contextRevision: String

    public init(
        id: UUID = UUID(),
        purpose: StudyAgentPurpose,
        workflow: StudyAgentWorkflow = .automatic,
        question: String,
        materialTitle: String,
        materialText: String,
        noteTitle: String,
        noteText: String,
        selectionTitle: String? = nil,
        selectionText: String? = nil,
        recentMessages: [AgentMessage] = [],
        courseContext: StudyAgentCourseContext = .empty,
        learningContext: StudyAgentLearningContext = .empty,
        language: WeiBeiInterfaceLanguage = .chinese,
        contextRevision: String
    ) {
        self.id = id
        self.purpose = purpose
        self.workflow = workflow
        self.question = question
        self.materialTitle = materialTitle
        self.materialText = materialText
        self.noteTitle = noteTitle
        self.noteText = noteText
        self.selectionTitle = selectionTitle
        self.selectionText = selectionText
        self.recentMessages = recentMessages
        self.courseContext = courseContext
        self.learningContext = learningContext
        self.language = language
        self.contextRevision = contextRevision
    }

    public var resolvedWorkflow: StudyAgentWorkflow {
        guard workflow == .automatic else { return workflow }
        if purpose == .quietInsight { return .closeReading }

        let value = question.lowercased()
        let resumeTerms = ["上次", "继续学", "学到哪", "学习进度", "resume", "last time", "continue learning"]
        if resumeTerms.contains(where: value.contains) { return .studyCompanion }

        let wayfindingTerms = ["关联", "相关", "哪本", "哪份", "哪个文件", "跳转", "去哪里", "先学", "前置", "related", "connect", "which file", "where should", "prerequisite"]
        if wayfindingTerms.contains(where: value.contains) { return .courseWayfinding }

        let recallTerms = ["出题", "测验", "复习题", "自测", "quiz", "test me", "questions"]
        if recallTerms.contains(where: value.contains) { return .recallPractice }

        let noteTerms = ["整理", "写入", "笔记", "润色", "摘录", "要点", "outline", "organize", "note", "rewrite"]
        if noteTerms.contains(where: value.contains) { return .noteMaking }

        return .studyCompanion
    }

}

public struct StudyAgentNoteProposal: Codable, Equatable, Sendable {
    public var markdown: String
    public var evidence: [String]
    public var contextRevision: String

    public init(markdown: String, evidence: [String], contextRevision: String) {
        self.markdown = markdown
        self.evidence = evidence
        self.contextRevision = contextRevision
    }
}

public struct StudyAgentMemoryUpdateEntry: Codable, Equatable, Sendable {
    public var kind: LearningMemoryKind
    public var text: String
    public var evidence: String
    public var origin: LearningMemoryOrigin

    public init(
        kind: LearningMemoryKind,
        text: String,
        evidence: String,
        origin: LearningMemoryOrigin
    ) {
        self.kind = kind
        self.text = text
        self.evidence = evidence
        self.origin = origin
    }
}

public struct StudyAgentLearningUpdate: Codable, Equatable, Sendable {
    public var contextRevision: String
    public var memoryRevision: UInt64
    public var sessionSummary: String?
    public var suggestedPhase: StudyPhase?
    public var suggestedNext: [String]
    public var entries: [StudyAgentMemoryUpdateEntry]

    public init(
        contextRevision: String,
        memoryRevision: UInt64,
        sessionSummary: String? = nil,
        suggestedPhase: StudyPhase? = nil,
        suggestedNext: [String] = [],
        entries: [StudyAgentMemoryUpdateEntry] = []
    ) {
        self.contextRevision = contextRevision
        self.memoryRevision = memoryRevision
        self.sessionSummary = sessionSummary
        self.suggestedPhase = suggestedPhase
        self.suggestedNext = suggestedNext
        self.entries = entries
    }
}

public struct StudyAgentReply: Equatable, Sendable {
    public var text: String
    public var backend: StudyAgentBackend
    public var noteProposal: StudyAgentNoteProposal?
    public var learningUpdate: StudyAgentLearningUpdate?

    public init(
        text: String,
        backend: StudyAgentBackend,
        noteProposal: StudyAgentNoteProposal? = nil,
        learningUpdate: StudyAgentLearningUpdate? = nil
    ) {
        self.text = text
        self.backend = backend
        self.noteProposal = noteProposal
        self.learningUpdate = learningUpdate
    }
}

public enum StudyAgentProgress: Equatable, Sendable {
    case readingContext
    case usingTool(String)
    case text(String)
}

public typealias StudyAgentProgressHandler = @Sendable (StudyAgentProgress) async -> Void

public protocol StudyAgentRuntime: Sendable {
    func respond(to request: StudyAgentRequest, progress: StudyAgentProgressHandler?) async throws -> StudyAgentReply
    func cancel() async
    func reset() async
}

public extension StudyAgentRuntime {
    func respond(to request: StudyAgentRequest) async throws -> StudyAgentReply {
        try await respond(to: request, progress: nil)
    }
}

public struct OfflineStudyAgentRuntime: StudyAgentRuntime {
    public init() {}

    public func respond(to request: StudyAgentRequest, progress: StudyAgentProgressHandler?) async throws -> StudyAgentReply {
        await progress?(.readingContext)
        let text = AgentOfflinePreview.render(
            AgentOfflinePreviewInput(
                language: request.language,
                question: request.question,
                hasMaterial: !request.materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                materialTitle: request.materialTitle,
                materialText: request.materialText,
                noteTitle: request.noteTitle,
                noteText: request.noteText,
                selectionTitle: request.selectionTitle,
                selectionText: request.selectionText
            )
        )
        return StudyAgentReply(text: text, backend: .offline)
    }

    public func cancel() async {}
    public func reset() async {}
}

public struct StudyAgentContextEnvelope: Codable, Equatable, Sendable {
    public struct Source: Codable, Equatable, Sendable {
        public var title: String
        public var text: String
        public var isTruncated: Bool

        public init(title: String, text: String, isTruncated: Bool = false) {
            self.title = title
            self.text = text
            self.isTruncated = isTruncated
        }
    }

    public struct Message: Codable, Equatable, Sendable {
        public var role: String
        public var text: String
        public var source: String?

        public init(role: String, text: String, source: String?) {
            self.role = role
            self.text = text
            self.source = source
        }
    }

    public var schemaVersion: Int
    public var requestID: String
    public var contextRevision: String
    public var purpose: String
    public var workflow: String
    public var language: String
    public var question: String
    public var material: Source?
    public var note: Source
    public var selection: Source?
    public var recentMessages: [Message]
    public var course: StudyAgentCourseContext
    public var learning: StudyAgentLearningContext

    public init(request: StudyAgentRequest) {
        schemaVersion = 2
        requestID = request.id.uuidString.lowercased()
        contextRevision = request.contextRevision
        purpose = request.purpose.rawValue
        workflow = request.resolvedWorkflow.rawValue
        language = request.language.rawValue
        question = String(request.question.prefix(4_000))

        let materialText = String(request.materialText.prefix(18_000))
        material = materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : Source(
                title: String(request.materialTitle.prefix(300)),
                text: materialText,
                isTruncated: request.materialText.count > materialText.count
            )

        let noteText = String(request.noteText.prefix(6_000))
        note = Source(
            title: String(request.noteTitle.prefix(300)),
            text: noteText,
            isTruncated: request.noteText.count > noteText.count
        )

        let selectedText = String((request.selectionText ?? "").prefix(2_000))
        selection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : Source(
                title: String((request.selectionTitle ?? request.materialTitle).prefix(300)),
                text: selectedText,
                isTruncated: (request.selectionText ?? "").count > selectedText.count
            )

        recentMessages = request.recentMessages.suffix(8).map { message in
            Message(
                role: message.role.rawValue,
                text: String(message.text.prefix(1_200)),
                source: message.source
            )
        }
        let boundedCourse = Self.boundedCourseContext(request.courseContext)
        course = boundedCourse.context
        learning = Self.boundedLearningContext(request.learningContext, itemIDMap: boundedCourse.itemIDMap)
    }

    private static func boundedCourseContext(
        _ context: StudyAgentCourseContext
    ) -> (context: StudyAgentCourseContext, itemIDMap: [String: String]) {
        let maximumCatalogItems = 500
        let maximumItems = 80
        let sourceCatalog = Array(context.catalog.prefix(maximumCatalogItems))
        var itemIDMap: [String: String] = [:]
        for (index, item) in sourceCatalog.enumerated() where itemIDMap[item.id] == nil {
            itemIDMap[item.id] = "course-item-\(index + 1)"
        }
        let catalog = sourceCatalog.compactMap { item -> StudyAgentCourseCatalogItem? in
            guard let itemID = itemIDMap[item.id] else { return nil }
            return StudyAgentCourseCatalogItem(
                id: itemID,
                title: String(item.title.prefix(300)),
                subtitle: String(item.subtitle.prefix(300)),
                kind: String(item.kind.prefix(64)),
                role: String(item.role.prefix(64)),
                isCurrentMaterial: item.isCurrentMaterial,
                isCurrentNote: item.isCurrentNote,
                linkedItemIDs: item.linkedItemIDs.prefix(24).compactMap { itemIDMap[$0] },
                tags: item.tags.prefix(16).map { String($0.prefix(64)) }
            )
        }
        let items = context.items.prefix(maximumItems).compactMap { item -> StudyAgentCourseItem? in
            guard let itemID = itemIDMap[item.id] else { return nil }
            let searchText = String(item.searchText.prefix(2_400))
            return StudyAgentCourseItem(
                id: itemID,
                title: String(item.title.prefix(300)),
                subtitle: String(item.subtitle.prefix(300)),
                kind: String(item.kind.prefix(64)),
                role: String(item.role.prefix(64)),
                isCurrentMaterial: item.isCurrentMaterial,
                isCurrentNote: item.isCurrentNote,
                linkedItemIDs: item.linkedItemIDs.prefix(24).compactMap { itemIDMap[$0] },
                headings: item.headings.prefix(12).map { String($0.prefix(200)) },
                tags: item.tags.prefix(16).map { String($0.prefix(64)) },
                searchText: searchText,
                isTruncated: item.isTruncated || item.searchText.count > searchText.count
            )
        }
        let relations = context.relations
            .prefix(500)
            .compactMap { relation -> StudyAgentCourseRelation? in
                guard let noteItemID = itemIDMap[relation.noteItemID],
                      let sourceItemID = itemIDMap[relation.sourceItemID] else { return nil }
                return StudyAgentCourseRelation(noteItemID: noteItemID, sourceItemID: sourceItemID)
            }
        return (
            StudyAgentCourseContext(
                title: String(context.title.prefix(300)),
                catalog: catalog,
                items: items,
                relations: relations,
                isTruncated: context.isTruncated
                    || context.catalog.count > catalog.count
                    || context.items.count > items.count
                    || context.relations.count > relations.count
            ),
            itemIDMap
        )
    }

    private static func boundedLearningContext(
        _ context: StudyAgentLearningContext,
        itemIDMap: [String: String]
    ) -> StudyAgentLearningContext {
        let memories = context.memories
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(48)
            .map { memory in
                LearningMemoryEntry(
                    id: memory.id,
                    kind: memory.kind,
                    text: String(memory.text.prefix(500)),
                    evidence: String(memory.evidence.prefix(400)),
                    origin: memory.origin,
                    status: memory.status,
                    sessionID: memory.sessionID,
                    createdAt: memory.createdAt,
                    updatedAt: memory.updatedAt
                )
        }
        let location = context.lastLocation.flatMap { location -> StudyLocation? in
            guard let itemID = itemIDMap[location.itemID] else { return nil }
            return StudyLocation(
                itemID: itemID,
                itemTitle: String(location.itemTitle.prefix(300)),
                locationTitle: location.locationTitle.map { String($0.prefix(300)) },
                pageIndex: location.pageIndex,
                lastStudiedAt: location.lastStudiedAt,
                visitCount: location.visitCount
            )
        }
        let session = context.session.map { session in
            StudyAgentSessionSnapshot(
                id: String(session.id.prefix(256)),
                title: String(session.title.prefix(300)),
                summary: String(session.summary.prefix(2_000)),
                phase: String(session.phase.prefix(64)),
                focusItemIDs: session.focusItemIDs.prefix(24).compactMap { itemIDMap[$0] },
                turnCount: session.turnCount
            )
        }
        return StudyAgentLearningContext(
            memoryRevision: context.memoryRevision,
            lastLocation: location,
            memories: memories,
            session: session
        )
    }
}
