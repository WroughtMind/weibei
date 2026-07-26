import CoreGraphics
import Foundation

public struct ImportedFileIdentity: Codable, Hashable, Sendable {
    public var volumeID: UInt64
    public var fileID: UInt64
    public var birthTimeSeconds: Int64
    public var birthTimeNanoseconds: Int64

    public init(
        volumeID: UInt64,
        fileID: UInt64,
        birthTimeSeconds: Int64,
        birthTimeNanoseconds: Int64
    ) {
        self.volumeID = volumeID
        self.fileID = fileID
        self.birthTimeSeconds = birthTimeSeconds
        self.birthTimeNanoseconds = birthTimeNanoseconds
    }
}

public struct StudyItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: StudyItemKind
    public var urlPath: String?
    public var importedFileIdentity: ImportedFileIdentity?
    public var importedFileBookmarkData: Data?
    public var importedFileLastKnownPath: String?
    public var isSample: Bool
    public var isNotebookNote: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: StudyItemKind,
        urlPath: String?,
        importedFileIdentity: ImportedFileIdentity? = nil,
        importedFileBookmarkData: Data? = nil,
        importedFileLastKnownPath: String? = nil,
        isSample: Bool,
        isNotebookNote: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.urlPath = urlPath
        self.importedFileIdentity = importedFileIdentity
        self.importedFileBookmarkData = importedFileBookmarkData
        self.importedFileLastKnownPath = importedFileLastKnownPath ?? urlPath
        self.isSample = isSample
        self.isNotebookNote = isNotebookNote
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case kind
        case urlPath
        case importedFileIdentity
        case importedFileBookmarkData
        case importedFileLastKnownPath
        case isSample
        case isNotebookNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        kind = try container.decode(StudyItemKind.self, forKey: .kind)
        urlPath = try container.decodeIfPresent(String.self, forKey: .urlPath)
        importedFileIdentity = try container.decodeIfPresent(ImportedFileIdentity.self, forKey: .importedFileIdentity)
        importedFileBookmarkData = try container.decodeIfPresent(Data.self, forKey: .importedFileBookmarkData)
        importedFileLastKnownPath = try container.decodeIfPresent(String.self, forKey: .importedFileLastKnownPath) ?? urlPath
        isSample = try container.decode(Bool.self, forKey: .isSample)
        isNotebookNote = try container.decodeIfPresent(Bool.self, forKey: .isNotebookNote) ?? false
    }

    public var url: URL? {
        urlPath.map { URL(fileURLWithPath: $0) }
    }

    public var isImportedMarkdownFile: Bool {
        !isSample && kind == .markdown && url != nil
    }

    public var editsBackingMarkdownFile: Bool {
        !isSample && kind == .markdown && isNotebookNote
    }

    public var canBecomeNotebookNote: Bool {
        isImportedMarkdownFile && !isNotebookNote
    }
}

public enum AgentRole: String, Codable, Sendable {
    case user
    case assistant
}

public enum StudyAgentBackend: String, Codable, Hashable, Sendable {
    case pi
    case openAI
    case offline
}

public struct AgentMessage: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var role: AgentRole
    public var text: String
    public var source: String?
    public var backend: StudyAgentBackend?
    public var richAnswer: RichAnswerPresentation?
    public var toolTrace: [String]
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        role: AgentRole,
        text: String,
        source: String?,
        backend: StudyAgentBackend? = nil,
        richAnswer: RichAnswerPresentation? = nil,
        toolTrace: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.source = source
        self.backend = backend
        self.richAnswer = richAnswer
        self.toolTrace = toolTrace
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case source
        case backend
        case richAnswer
        case toolTrace
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(AgentRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        backend = try container.decodeIfPresent(StudyAgentBackend.self, forKey: .backend)
        richAnswer = try? container.decodeIfPresent(RichAnswerPresentation.self, forKey: .richAnswer)
        toolTrace = try container.decodeIfPresent([String].self, forKey: .toolTrace) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(backend, forKey: .backend)
        try container.encodeIfPresent(richAnswer, forKey: .richAnswer)
        if !toolTrace.isEmpty {
            try container.encode(toolTrace, forKey: .toolTrace)
        }
        try container.encode(createdAt, forKey: .createdAt)
    }

    public var isUsableAgentAnswer: Bool {
        role == .assistant
            && !text.hasPrefix("未配置密钥")
            && !text.hasPrefix("未配置 OPENAI_API_KEY")
            && !text.hasPrefix("No key is configured")
            && !text.hasPrefix("请求失败")
            && !text.hasPrefix("Agent 请求失败：")
            && !text.hasPrefix("Request failed")
    }
}

public struct PendingNoteWriteState: Codable, Hashable, Sendable {
    public var baselineContentDigest: String?

    public init(baselineContentDigest: String?) {
        self.baselineContentDigest = baselineContentDigest
    }
}

public struct PersistedWorkspace: Codable {
    public var importedItems: [StudyItem]
    public var notesByItemID: [String: String]
    public var pendingNoteWritesByItemID: [String: PendingNoteWriteState]?
    public var noteBackingContentDigestsByItemID: [String: String]?
    public var selectedItemID: String?
    public var activeNotebookItemID: String?
    public var courses: [Course]?
    public var courseItemMemberships: [CourseItemMembership]?
    public var activeCourseID: UUID?
    public var noteSourceLinks: [NoteSourceLink]?
    public var noteSourceLinksMigrationVersion: Int?
    public var studyLocationsByItemID: [String: StudyLocation]?
    public var learningMemoryEntries: [LearningMemoryEntry]?
    public var learningMemoryRevision: UInt64?
    public var studySessions: [StudySession]?
    public var activeStudySessionID: UUID?
    public var modelName: String?
    public var agentProviderID: String?
    public var agentBaseURL: String?
    public var workspaceLayout: WorkspaceLayout?
    public var threePaneOrder: [WorkspacePaneRole]?
    public var agentSurface: AgentSurface?
    public var noteRenderMode: NoteRenderMode?
    public var showLibrary: Bool?
    public var showReader: Bool?
    public var showAgent: Bool?
    public var showNotes: Bool?
    public var showRightPane: Bool?
    public var showDailyInspiration: Bool?
    public var appearanceModeRaw: String?
    public var adaptImportedDocumentColors: Bool?
    public var interfaceLanguageRaw: String?

    public init(
        importedItems: [StudyItem] = [],
        notesByItemID: [String: String] = [:],
        pendingNoteWritesByItemID: [String: PendingNoteWriteState]? = nil,
        noteBackingContentDigestsByItemID: [String: String]? = nil,
        selectedItemID: String? = nil,
        activeNotebookItemID: String? = nil,
        courses: [Course]? = nil,
        courseItemMemberships: [CourseItemMembership]? = nil,
        activeCourseID: UUID? = nil,
        noteSourceLinks: [NoteSourceLink]? = nil,
        noteSourceLinksMigrationVersion: Int? = nil,
        studyLocationsByItemID: [String: StudyLocation]? = nil,
        learningMemoryEntries: [LearningMemoryEntry]? = nil,
        learningMemoryRevision: UInt64? = nil,
        studySessions: [StudySession]? = nil,
        activeStudySessionID: UUID? = nil,
        modelName: String? = nil,
        agentProviderID: String? = nil,
        agentBaseURL: String? = nil,
        workspaceLayout: WorkspaceLayout? = nil,
        threePaneOrder: [WorkspacePaneRole]? = nil,
        agentSurface: AgentSurface? = nil,
        noteRenderMode: NoteRenderMode? = nil,
        showLibrary: Bool? = nil,
        showReader: Bool? = nil,
        showAgent: Bool? = nil,
        showNotes: Bool? = nil,
        showRightPane: Bool? = nil,
        showDailyInspiration: Bool? = nil,
        appearanceModeRaw: String? = nil,
        adaptImportedDocumentColors: Bool? = nil,
        interfaceLanguageRaw: String? = nil
    ) {
        self.importedItems = importedItems
        self.notesByItemID = notesByItemID
        self.pendingNoteWritesByItemID = pendingNoteWritesByItemID
        self.noteBackingContentDigestsByItemID = noteBackingContentDigestsByItemID
        self.selectedItemID = selectedItemID
        self.activeNotebookItemID = activeNotebookItemID
        self.courses = courses
        self.courseItemMemberships = courseItemMemberships
        self.activeCourseID = activeCourseID
        self.noteSourceLinks = noteSourceLinks
        self.noteSourceLinksMigrationVersion = noteSourceLinksMigrationVersion
        self.studyLocationsByItemID = studyLocationsByItemID
        self.learningMemoryEntries = learningMemoryEntries
        self.learningMemoryRevision = learningMemoryRevision
        self.studySessions = studySessions
        self.activeStudySessionID = activeStudySessionID
        self.modelName = modelName
        self.agentProviderID = agentProviderID
        self.agentBaseURL = agentBaseURL
        self.workspaceLayout = workspaceLayout
        self.threePaneOrder = threePaneOrder
        self.agentSurface = agentSurface
        self.noteRenderMode = noteRenderMode
        self.showLibrary = showLibrary
        self.showReader = showReader
        self.showAgent = showAgent
        self.showNotes = showNotes
        self.showRightPane = showRightPane
        self.showDailyInspiration = showDailyInspiration
        self.appearanceModeRaw = appearanceModeRaw
        self.adaptImportedDocumentColors = adaptImportedDocumentColors
        self.interfaceLanguageRaw = interfaceLanguageRaw
    }
}
