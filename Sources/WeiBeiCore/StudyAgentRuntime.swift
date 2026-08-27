import Foundation

public enum StudyAgentPurpose: String, Codable, Sendable {
    case conversation
}

public enum StudyAgentAnswerFormPolicy: String, Codable, Equatable, Sendable {
    case automatic
    case textOnly
    case partialRichAllowed
}

public enum StudyAgentCurrentTurnEvidence {
    public static func matches(_ evidence: String, question: String) -> Bool {
        guard let statement = statement(in: evidence), statement.count >= 2 else { return false }
        var searchStart = question.startIndex
        while searchStart < question.endIndex,
              let range = question.range(of: statement, range: searchStart..<question.endIndex) {
            if hasClauseBoundaries(range, in: question) { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func hasClauseBoundaries(_ range: Range<String.Index>, in question: String) -> Bool {
        let startsAtBoundary = range.lowerBound == question.startIndex
            || question[question.index(before: range.lowerBound)].isWhitespace
            || question[question.index(before: range.lowerBound)].isPunctuation
        let endsAtBoundary = range.upperBound == question.endIndex
            || question[range.upperBound].isWhitespace
            || question[range.upperBound].isPunctuation
        return startsAtBoundary && endsAtBoundary
    }

    private static func statement(in evidence: String) -> String? {
        let prefixes = ["[用户：本轮]", "[会话：当前]"]
        guard let prefix = prefixes.first(where: { evidence.hasPrefix($0) }) else { return nil }
        let quoteCharacters = CharacterSet(charactersIn: "\"'“”‘’")
        let value = String(evidence.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: quoteCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

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
    public var indexedPageCount: Int?
    public var totalPageCount: Int?
    public var uncoveredPageNumbers: [Int]?
    public var failedPageNumbers: [Int]?
    public var failedPageReasons: [Int: String]?

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
        isTruncated: Bool = false,
        indexedPageCount: Int? = nil,
        totalPageCount: Int? = nil,
        uncoveredPageNumbers: [Int]? = nil,
        failedPageNumbers: [Int]? = nil,
        failedPageReasons: [Int: String]? = nil
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
        self.indexedPageCount = indexedPageCount
        self.totalPageCount = totalPageCount
        self.uncoveredPageNumbers = uncoveredPageNumbers
        self.failedPageNumbers = failedPageNumbers
        self.failedPageReasons = failedPageReasons
    }
}

public struct StudyAgentCourseRelation: Codable, Equatable, Hashable, Sendable {
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

public enum StudyAgentScopeKind: String, Codable, Equatable, Sendable {
    // This controls temporary project-file access, not Chat identity.
    case course
    case global
}

public struct StudyAgentFileIdentity: Codable, Equatable, Sendable {
    public var volumeID: String
    public var fileID: String
    public var birthTimeSeconds: String
    public var birthTimeNanoseconds: String

    public init(_ identity: ImportedFileIdentity) {
        volumeID = String(identity.volumeID)
        fileID = String(identity.fileID)
        birthTimeSeconds = String(identity.birthTimeSeconds)
        birthTimeNanoseconds = String(identity.birthTimeNanoseconds)
    }
}

public struct StudyAgentProjectItem: Codable, Equatable, Sendable {
    public var itemID: String
    public var title: String
    public var kind: String
    public var role: String
    public var relativePath: String
    public var resolvedPath: String
    public var entryIdentity: StudyAgentFileIdentity?
    public var targetIdentity: StudyAgentFileIdentity?
    public var isShared: Bool
    public var courseIDs: [String]
    public var courseTitles: [String]
    public var sourceRevision: String?

    public init(
        itemID: String,
        title: String,
        kind: String,
        role: String,
        relativePath: String,
        resolvedPath: String,
        entryIdentity: StudyAgentFileIdentity?,
        targetIdentity: StudyAgentFileIdentity?,
        isShared: Bool,
        courseIDs: [String] = [],
        courseTitles: [String] = [],
        sourceRevision: String? = nil
    ) {
        self.itemID = itemID
        self.title = title
        self.kind = kind
        self.role = role
        self.relativePath = relativePath
        self.resolvedPath = resolvedPath
        self.entryIdentity = entryIdentity
        self.targetIdentity = targetIdentity
        self.isShared = isShared
        self.courseIDs = courseIDs
        self.courseTitles = courseTitles
        self.sourceRevision = sourceRevision
    }
}

public struct StudyAgentProjectScope: Codable, Equatable, Sendable {
    public var kind: StudyAgentScopeKind
    public var chatID: String
    public var courseID: String?
    public var courseTitle: String?
    public var rootPath: String?
    public var rootIdentity: StudyAgentFileIdentity?
    public var items: [StudyAgentProjectItem]
    public var isTruncated: Bool

    public init(
        kind: StudyAgentScopeKind,
        chatID: String,
        courseID: String? = nil,
        courseTitle: String? = nil,
        rootPath: String? = nil,
        rootIdentity: StudyAgentFileIdentity? = nil,
        items: [StudyAgentProjectItem] = [],
        isTruncated: Bool = false
    ) {
        self.kind = kind
        self.chatID = chatID
        self.courseID = courseID
        self.courseTitle = courseTitle
        self.rootPath = rootPath
        self.rootIdentity = rootIdentity
        self.items = items
        self.isTruncated = isTruncated
    }

    public static let empty = StudyAgentProjectScope(kind: .global, chatID: "")
}

public struct StudyAgentFocus: Codable, Equatable, Sendable {
    public var chatID: String
    public var courseID: String?
    public var materialItemID: String?
    public var materialTitle: String?
    public var pageIndex: Int?
    public var sectionTitle: String?
    public var sectionLocationID: String?
    public var sectionOrdinal: Int?
    public var selectionText: String?
    public var actionSource: String

    public init(
        chatID: String,
        courseID: String?,
        materialItemID: String?,
        materialTitle: String?,
        pageIndex: Int?,
        sectionTitle: String?,
        sectionLocationID: String?,
        sectionOrdinal: Int?,
        selectionText: String?,
        actionSource: String
    ) {
        self.chatID = chatID
        self.courseID = courseID
        self.materialItemID = materialItemID
        self.materialTitle = materialTitle
        self.pageIndex = pageIndex
        self.sectionTitle = sectionTitle
        self.sectionLocationID = sectionLocationID
        self.sectionOrdinal = sectionOrdinal
        self.selectionText = selectionText
        self.actionSource = actionSource
    }
}

public enum StudyAgentHostToolRequest: Equatable, Sendable {
    case courseMap(itemID: String?, offset: Int, limit: Int)
    case courseSearch(query: String, limit: Int)
    case workspaceSearch(query: String, limit: Int, crossLibrary: Bool)
    case courseRead(
        itemID: String,
        query: String,
        location: String?,
        cursor: String?,
        maximumCharacters: Int
    )
    case retryFailedPDFPages(itemID: String)
    case webOpen(url: String, maximumCharacters: Int)
}

public struct StudyAgentWebPage: Codable, Equatable, Sendable {
    public var url: String
    public var title: String
    public var text: String
    public var isTruncated: Bool
    public var links: [String]

    public init(
        url: String,
        title: String,
        text: String,
        isTruncated: Bool,
        links: [String] = []
    ) {
        self.url = url
        self.title = title
        self.text = text
        self.isTruncated = isTruncated
        self.links = links
    }
}

public struct StudyAgentHostToolItem: Codable, Equatable, Sendable {
    public var item: StudyAgentCourseItem
    public var relativePath: String?
    public var courseIDs: [String]
    public var courseTitles: [String]
    public var sourceRevision: String?

    public init(
        item: StudyAgentCourseItem,
        relativePath: String? = nil,
        courseIDs: [String] = [],
        courseTitles: [String] = [],
        sourceRevision: String? = nil
    ) {
        self.item = item
        self.relativePath = relativePath
        self.courseIDs = courseIDs
        self.courseTitles = courseTitles
        self.sourceRevision = sourceRevision
    }
}

public struct StudyAgentHostToolResult: Codable, Equatable, Sendable {
    public var query: String
    public var items: [StudyAgentHostToolItem]
    public var webPages: [StudyAgentWebPage]
    public var total: Int?
    public var nextCursor: String?
    public var sourceRevision: String?

    public init(
        query: String,
        items: [StudyAgentHostToolItem],
        webPages: [StudyAgentWebPage] = [],
        total: Int? = nil,
        nextCursor: String? = nil,
        sourceRevision: String? = nil
    ) {
        self.query = query
        self.items = items
        self.webPages = webPages
        self.total = total
        self.nextCursor = nextCursor
        self.sourceRevision = sourceRevision
    }
}

public typealias StudyAgentHostToolHandler = @Sendable (
    StudyAgentHostToolRequest
) async throws -> StudyAgentHostToolResult

public struct StudyAgentVisualAsset: Codable, Equatable, Sendable {
    public var id: String
    public var filePath: String
    public var mediaType: String

    public init(id: String, filePath: String, mediaType: String) {
        self.id = id
        self.filePath = filePath
        self.mediaType = mediaType
    }
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

public struct StudyAgentCourseProfileSource: Codable, Equatable, Sendable {
    public var itemID: String
    public var role: String
    public var location: String?
    public var sourceRevision: String

    public init(
        itemID: String,
        role: String,
        location: String? = nil,
        sourceRevision: String
    ) {
        self.itemID = itemID
        self.role = role
        self.location = location
        self.sourceRevision = sourceRevision
    }
}

public struct StudyAgentCourseProfileEntry: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var text: String
    public var sources: [StudyAgentCourseProfileSource]

    public init(
        id: String,
        kind: String,
        text: String,
        sources: [StudyAgentCourseProfileSource]
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.sources = sources
    }
}

public struct StudyAgentCourseProfileContext: Codable, Equatable, Sendable {
    public var revision: UInt64
    public var overview: String
    public var entries: [StudyAgentCourseProfileEntry]

    public init(
        revision: UInt64 = 0,
        overview: String = "",
        entries: [StudyAgentCourseProfileEntry] = []
    ) {
        self.revision = revision
        self.overview = overview
        self.entries = entries
    }

    public static let empty = StudyAgentCourseProfileContext()
}

public struct StudyAgentRequest: Sendable {
    public var id: UUID
    public var purpose: StudyAgentPurpose
    public var answerFormPolicy: StudyAgentAnswerFormPolicy
    public var question: String
    public var materialTitle: String
    public var materialText: String
    public var materialIsTruncated: Bool
    public var noteTitle: String
    public var noteText: String
    public var selectionTitle: String?
    public var selectionText: String?
    public var selectionSources: [AgentReplySource]
    public var courseContext: StudyAgentCourseContext
    public var projectScope: StudyAgentProjectScope
    public var focus: StudyAgentFocus?
    public var visualAssets: [StudyAgentVisualAsset]
    public var learningContext: StudyAgentLearningContext
    public var courseProfile: StudyAgentCourseProfileContext
    public var language: WeiBeiInterfaceLanguage
    public var contextRevision: String
    /// Notes the user already confirmed in this Chat. Native must treat these as persisted.
    public var confirmedNotes: [StudyAgentPersistedNoteRef]

    public init(
        id: UUID = UUID(),
        purpose: StudyAgentPurpose,
        answerFormPolicy: StudyAgentAnswerFormPolicy = .automatic,
        question: String,
        materialTitle: String,
        materialText: String,
        materialIsTruncated: Bool = false,
        noteTitle: String,
        noteText: String,
        selectionTitle: String? = nil,
        selectionText: String? = nil,
        selectionSources: [AgentReplySource] = [],
        courseContext: StudyAgentCourseContext = .empty,
        projectScope: StudyAgentProjectScope = .empty,
        focus: StudyAgentFocus? = nil,
        visualAssets: [StudyAgentVisualAsset] = [],
        learningContext: StudyAgentLearningContext = .empty,
        courseProfile: StudyAgentCourseProfileContext = .empty,
        language: WeiBeiInterfaceLanguage = .chinese,
        contextRevision: String,
        confirmedNotes: [StudyAgentPersistedNoteRef] = []
    ) {
        self.id = id
        self.purpose = purpose
        self.answerFormPolicy = answerFormPolicy
        self.question = question
        self.materialTitle = materialTitle
        self.materialText = materialText
        self.materialIsTruncated = materialIsTruncated
        self.noteTitle = noteTitle
        self.noteText = noteText
        self.selectionTitle = selectionTitle
        self.selectionText = selectionText
        self.selectionSources = selectionSources
        self.courseContext = courseContext
        self.projectScope = projectScope
        self.focus = focus
        self.visualAssets = visualAssets
        self.learningContext = learningContext
        self.courseProfile = courseProfile
        self.language = language
        self.contextRevision = contextRevision
        self.confirmedNotes = confirmedNotes
    }

}

public struct StudyAgentPersistedNoteRef: Sendable, Equatable {
    public var itemID: String
    public var title: String

    public init(itemID: String, title: String) {
        self.itemID = itemID
        self.title = title
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

public struct StudyAgentRelationProposal: Codable, Equatable, Sendable {
    public var noteItemID: String
    public var sourceItemID: String
    public var contextRevision: String

    public init(noteItemID: String, sourceItemID: String, contextRevision: String) {
        self.noteItemID = noteItemID
        self.sourceItemID = sourceItemID
        self.contextRevision = contextRevision
    }
}

public struct StudyAgentMemoryUpdateEntry: Codable, Equatable, Sendable {
    /// Missing only when Agent is proposing a new memory. Existing memories must
    /// be updated through the stable id returned by the current scope read.
    public var memoryID: String?
    public var kind: LearningMemoryKind
    public var text: String
    public var evidence: String
    public var origin: LearningMemoryOrigin

    public init(
        memoryID: String? = nil,
        kind: LearningMemoryKind,
        text: String,
        evidence: String,
        origin: LearningMemoryOrigin
    ) {
        self.memoryID = memoryID
        self.kind = kind
        self.text = text
        self.evidence = evidence
        self.origin = origin
    }
}

public struct StudyAgentMemoryResolution: Codable, Equatable, Sendable {
    public var memoryID: String
    public var text: String
    public var evidence: String

    public init(memoryID: String, text: String, evidence: String) {
        self.memoryID = memoryID
        self.text = text
        self.evidence = evidence
    }
}

public struct StudyAgentLearningUpdate: Codable, Equatable, Sendable {
    public var contextRevision: String
    public var memoryRevision: UInt64
    public var sessionSummary: String?
    public var suggestedPhase: StudyPhase?
    public var suggestedNext: [String]
    public var entries: [StudyAgentMemoryUpdateEntry]
    public var resolutions: [StudyAgentMemoryResolution]

    public init(
        contextRevision: String,
        memoryRevision: UInt64,
        sessionSummary: String? = nil,
        suggestedPhase: StudyPhase? = nil,
        suggestedNext: [String] = [],
        entries: [StudyAgentMemoryUpdateEntry] = [],
        resolutions: [StudyAgentMemoryResolution] = []
    ) {
        self.contextRevision = contextRevision
        self.memoryRevision = memoryRevision
        self.sessionSummary = sessionSummary
        self.suggestedPhase = suggestedPhase
        self.suggestedNext = suggestedNext
        self.entries = entries
        self.resolutions = resolutions
    }
}

public struct StudyAgentCourseProfileUpdateEntry: Codable, Equatable, Sendable {
    public var entryID: String?
    public var kind: CourseKnowledgeProfileEntryKind
    public var text: String
    public var sources: [StudyAgentCourseProfileSource]

    public init(
        entryID: String? = nil,
        kind: CourseKnowledgeProfileEntryKind,
        text: String,
        sources: [StudyAgentCourseProfileSource]
    ) {
        self.entryID = entryID
        self.kind = kind
        self.text = text
        self.sources = sources
    }
}

public struct StudyAgentCourseProfileUpdate: Codable, Equatable, Sendable {
    public var contextRevision: String
    public var profileRevision: UInt64
    public var checkpoint: String
    public var entries: [StudyAgentCourseProfileUpdateEntry]
    public var removedEntryIDs: [String]

    public init(
        contextRevision: String,
        profileRevision: UInt64,
        checkpoint: String,
        entries: [StudyAgentCourseProfileUpdateEntry],
        removedEntryIDs: [String] = []
    ) {
        self.contextRevision = contextRevision
        self.profileRevision = profileRevision
        self.checkpoint = checkpoint
        self.entries = entries
        self.removedEntryIDs = removedEntryIDs
    }

    public var allowsEntriesWithoutSources: Bool {
        checkpoint == "userRequested" || entries.contains { $0.text.hasPrefix("用户自述：") }
    }
}

public struct StudyAgentLoadedSkill: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var sha256: String
    public var byteCount: Int
    public var relativePath: String
    public var loadedAtContextRevision: String

    public init(
        id: String,
        name: String,
        version: String,
        sha256: String,
        byteCount: Int,
        relativePath: String,
        loadedAtContextRevision: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.sha256 = sha256
        self.byteCount = byteCount
        self.relativePath = relativePath
        self.loadedAtContextRevision = loadedAtContextRevision
    }
}

public struct StudyAgentReply: Equatable, Sendable {
    public var text: String
    public var contentBlocks: [AgentMessageContentBlock]
    public var backend: StudyAgentBackend
    public var sources: [AgentReplySource]
    public var noteProposal: StudyAgentNoteProposal?
    public var relationProposal: StudyAgentRelationProposal?
    public var learningUpdate: StudyAgentLearningUpdate?
    public var courseProfileUpdate: StudyAgentCourseProfileUpdate?
    public var appliedMemoryUpdate: AgentReplyMemoryUpdate?
    public var appliedProfileUpdate: AgentReplyProfileUpdate?
    public var loadedSkills: [StudyAgentLoadedSkill]
    public var readItemIDs: [String]
    public var toolTrace: [String]

    public init(
        text: String,
        contentBlocks: [AgentMessageContentBlock] = [],
        backend: StudyAgentBackend,
        sources: [AgentReplySource] = [],
        noteProposal: StudyAgentNoteProposal? = nil,
        relationProposal: StudyAgentRelationProposal? = nil,
        learningUpdate: StudyAgentLearningUpdate? = nil,
        courseProfileUpdate: StudyAgentCourseProfileUpdate? = nil,
        appliedMemoryUpdate: AgentReplyMemoryUpdate? = nil,
        appliedProfileUpdate: AgentReplyProfileUpdate? = nil,
        loadedSkills: [StudyAgentLoadedSkill] = [],
        readItemIDs: [String] = [],
        toolTrace: [String] = []
    ) {
        self.text = text
        self.contentBlocks = contentBlocks
        self.backend = backend
        self.sources = sources
        self.noteProposal = noteProposal
        self.relationProposal = relationProposal
        self.learningUpdate = learningUpdate
        self.courseProfileUpdate = courseProfileUpdate
        self.appliedMemoryUpdate = appliedMemoryUpdate
        self.appliedProfileUpdate = appliedProfileUpdate
        self.loadedSkills = loadedSkills
        self.readItemIDs = readItemIDs
        self.toolTrace = toolTrace
    }
}

public enum StudyAgentProgress: Equatable, Sendable {
    case preparing
    /// Tool name plus an optional human-readable argument excerpt
    /// (search query, file title…) surfaced in the chat status line.
    case usingTool(String, String?)
    case text(String, [AgentMessageContentBlock])
    case visualization(AgentVisualization, [AgentMessageContentBlock])
}

public typealias StudyAgentProgressHandler = @Sendable (StudyAgentProgress) async -> Void
public typealias StudyAgentSessionTitleHandler = @Sendable (String) async -> Void

/// User-facing classification for Agent request failures.
public enum AgentFailureKind: String, Codable, Equatable, Sendable {
    case offline
    case unauthorized
    case rateLimited
    case serverError
    case timedOut
    case cancelled
    case generic

    public func title(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .offline:
            return language.text("网络不可用", "Network unavailable")
        case .unauthorized:
            return language.text("认证已失效", "Authentication expired")
        case .rateLimited:
            return language.text("请求过于频繁", "Rate limited")
        case .serverError:
            return language.text("模型服务暂时不可用", "Model service temporarily unavailable")
        case .timedOut:
            return language.text("请求超时", "Request timed out")
        case .cancelled:
            return language.text("已取消", "Cancelled")
        case .generic:
            return language.text("请求失败", "Request failed")
        }
    }

    public func guidance(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .offline:
            return language.text("请检查本机网络后重试。", "Check your network connection, then retry.")
        case .unauthorized:
            return language.text(
                "请到设置中重新登录，或重新保存 API Key。",
                "Sign in again in Settings, or save the API key again."
            )
        case .rateLimited:
            return language.text("请稍后再试，或更换模型/提供商。", "Wait a moment, or switch model/provider.")
        case .serverError:
            return language.text("服务端异常，请稍后重试。", "The server had an error. Try again shortly.")
        case .timedOut:
            return language.text("可以缩短问题或稍后重试。", "Try a shorter question, or retry later.")
        case .cancelled:
            return language.text("本次请求已取消。", "This request was cancelled.")
        case .generic:
            return language.text("可直接重试。", "You can retry.")
        }
    }

    public var isRetryable: Bool {
        true
    }

    public static func classify(_ error: Error) -> AgentFailureKind {
        if let failure = error as? NativeLLMFailure {
            return failure.asAgentFailureKind
        }
        if error is CancellationError {
            return .cancelled
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return .offline
            case NSURLErrorTimedOut:
                return .timedOut
            case NSURLErrorUserCancelledAuthentication, NSURLErrorCancelled:
                return .cancelled
            default:
                break
            }
        }
        if ns.domain == "WeiBei.OpenAI" || ns.domain == "WeiBei.NativeAgent" {
            switch ns.code {
            case 401, 403:
                return .unauthorized
            case 429:
                return .rateLimited
            case 408, 504:
                return .timedOut
            case 500, 502, 503:
                return .serverError
            default:
                if (500...599).contains(ns.code) { return .serverError }
            }
        }
        return classifyMessage(error.localizedDescription)
    }

    private static func classifyMessage(_ message: String) -> AgentFailureKind {
        let lower = message.lowercased()
        if lower.contains("cancel") || message.contains("取消") {
            return .cancelled
        }
        if lower.contains("timeout") || lower.contains("timed out") || message.contains("超时") {
            return .timedOut
        }
        if lower.contains("401") || lower.contains("403") || lower.contains("unauthorized") || lower.contains("invalid api key") || message.contains("未授权") || message.contains("密钥") || message.contains("认证已失效") || message.contains("重新登录") {
            return .unauthorized
        }
        if lower.contains("429") || lower.contains("rate limit") || message.contains("过于频繁") {
            return .rateLimited
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("internet") || message.contains("网络") {
            return .offline
        }
        if lower.contains("500") || lower.contains("502") || lower.contains("503") || lower.contains("server") {
            return .serverError
        }
        return .generic
    }

    /// Build a bilingual failure bubble body. Includes a stable marker for UI detection.
    public func userMessage(
        language: WeiBeiInterfaceLanguage,
        userFacingDetail: String?,
        draftPreserved: Bool = false
    ) -> String {
        let titleText = title(language: language)
        // Avoid "请求失败：请求失败" when the kind title is already "请求失败".
        let header: String
        switch self {
        case .generic:
            header = titleText
        default:
            header = language.text("请求失败：\(titleText)", "Request failed: \(titleText)")
        }
        var lines = [header, guidance(language: language)]
        if let detail = userFacingDetail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !detail.isEmpty {
            let clipped = detail.count > 280 ? String(detail.prefix(280)) + "…" : detail
            lines.append(language.text("详情：\(clipped)", "Detail: \(clipped)"))
        }
        if draftPreserved {
            lines.append(language.text("问题已保留在输入框。", "The question remains in the composer."))
        }
        return lines.joined(separator: "\n")
    }
}

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
