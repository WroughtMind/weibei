import Foundation

public enum StudyAgentPurpose: String, Codable, Sendable {
    case conversation
    case quietInsight
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

public enum StudyAgentScopeKind: String, Codable, Equatable, Sendable {
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
        courseTitles: [String] = []
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
    case courseSearch(query: String, limit: Int)
    case courseRead(itemID: String, query: String, location: String?, limit: Int)
}

public struct StudyAgentHostToolItem: Codable, Equatable, Sendable {
    public var item: StudyAgentCourseItem
    public var relativePath: String?
    public var courseIDs: [String]
    public var courseTitles: [String]

    public init(
        item: StudyAgentCourseItem,
        relativePath: String? = nil,
        courseIDs: [String] = [],
        courseTitles: [String] = []
    ) {
        self.item = item
        self.relativePath = relativePath
        self.courseIDs = courseIDs
        self.courseTitles = courseTitles
    }
}

public struct StudyAgentHostToolResult: Codable, Equatable, Sendable {
    public var query: String
    public var items: [StudyAgentHostToolItem]

    public init(query: String, items: [StudyAgentHostToolItem]) {
        self.query = query
        self.items = items
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
    public var recentMessages: [AgentMessage]
    public var courseContext: StudyAgentCourseContext
    public var projectScope: StudyAgentProjectScope
    public var focus: StudyAgentFocus?
    public var visualAssets: [StudyAgentVisualAsset]
    public var learningContext: StudyAgentLearningContext
    public var language: WeiBeiInterfaceLanguage
    public var contextRevision: String

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
        recentMessages: [AgentMessage] = [],
        courseContext: StudyAgentCourseContext = .empty,
        projectScope: StudyAgentProjectScope = .empty,
        focus: StudyAgentFocus? = nil,
        visualAssets: [StudyAgentVisualAsset] = [],
        learningContext: StudyAgentLearningContext = .empty,
        language: WeiBeiInterfaceLanguage = .chinese,
        contextRevision: String
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
        self.recentMessages = recentMessages
        self.courseContext = courseContext
        self.projectScope = projectScope
        self.focus = focus
        self.visualAssets = visualAssets
        self.learningContext = learningContext
        self.language = language
        self.contextRevision = contextRevision
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
    public var backend: StudyAgentBackend
    public var richAnswer: RichAnswerPresentation?
    public var sources: [AgentReplySource]
    public var noteProposal: StudyAgentNoteProposal?
    public var learningUpdate: StudyAgentLearningUpdate?
    public var loadedSkills: [StudyAgentLoadedSkill]
    public var toolTrace: [String]

    public init(
        text: String,
        backend: StudyAgentBackend,
        richAnswer: RichAnswerPresentation? = nil,
        sources: [AgentReplySource] = [],
        noteProposal: StudyAgentNoteProposal? = nil,
        learningUpdate: StudyAgentLearningUpdate? = nil,
        loadedSkills: [StudyAgentLoadedSkill] = [],
        toolTrace: [String] = []
    ) {
        self.text = text
        self.backend = backend
        self.richAnswer = richAnswer
        self.sources = sources
        self.noteProposal = noteProposal
        self.learningUpdate = learningUpdate
        self.loadedSkills = loadedSkills
        self.toolTrace = toolTrace
    }
}

public enum StudyAgentProgress: Equatable, Sendable {
    case preparing
    case usingTool(String)
    case text(String)
}

public typealias StudyAgentProgressHandler = @Sendable (StudyAgentProgress) async -> Void

/// User-facing classification for agent request failures (Pi + OpenAI + offline).
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
            return language.text("密钥无效或未授权", "Invalid or unauthorized key")
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
            return language.text("请在设置中核对密钥与提供商。", "Check the API key and provider in Settings.")
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
        if error is CancellationError {
            return .cancelled
        }
        if let pi = error as? PiAgentRuntimeError {
            switch pi {
            case .cancelled:
                return .cancelled
            case .commandTimedOut:
                return .timedOut
            case let .agentFailed(message):
                return classifyMessage(message)
            case let .inFlightFailed(message):
                return classifyMessage(message)
            case let .protocolFailure(message):
                return classifyMessage(message)
            case .unavailable, .resourcesMissing, .busy, .launchFailed, .commandRejected:
                return .generic
            }
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
        if ns.domain == "WeiBei.OpenAI" {
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
        if lower.contains("401") || lower.contains("403") || lower.contains("unauthorized") || lower.contains("invalid api key") || message.contains("未授权") || message.contains("密钥") {
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
        detail: String?,
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
        if let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
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

public struct OfflineStudyAgentRuntime: StudyAgentRuntime {
    public init() {}

    public func respond(to request: StudyAgentRequest, progress: StudyAgentProgressHandler?) async throws -> StudyAgentReply {
        await progress?(.preparing)
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
    public var answerFormPolicy: String
    public var language: String
    public var question: String
    public var material: Source?
    public var note: Source
    public var selection: Source?
    public var recentMessages: [Message]
    public var course: StudyAgentCourseContext
    public var project: StudyAgentProjectScope
    public var focus: StudyAgentFocus?
    public var visualAssets: [StudyAgentVisualAsset]
    public var learning: StudyAgentLearningContext

    public init(request: StudyAgentRequest) {
        schemaVersion = 2
        requestID = request.id.uuidString.lowercased()
        contextRevision = request.contextRevision
        purpose = request.purpose.rawValue
        answerFormPolicy = request.answerFormPolicy.rawValue
        language = request.language.rawValue
        question = String(request.question.prefix(4_000))

        let materialText = String(request.materialText.prefix(18_000))
        material = materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : Source(
                title: String(request.materialTitle.prefix(300)),
                text: materialText,
                isTruncated: request.materialIsTruncated || request.materialText.count > materialText.count
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

        recentMessages = request.recentMessages.suffix(20).map { message in
            Message(
                role: message.role.rawValue,
                text: String(message.text.prefix(1_200)),
                source: message.source
            )
        }
        let boundedCourse = Self.boundedCourseContext(request.courseContext)
        course = boundedCourse.context
        project = Self.boundedProjectScope(
            request.projectScope,
            itemIDMap: boundedCourse.itemIDMap
        )
        focus = request.focus.map { focus in
            StudyAgentFocus(
                chatID: String(focus.chatID.prefix(128)),
                courseID: focus.courseID.map { String($0.prefix(128)) },
                materialItemID: focus.materialItemID.flatMap { boundedCourse.itemIDMap[$0] },
                materialTitle: focus.materialTitle.map { String($0.prefix(300)) },
                pageIndex: focus.pageIndex,
                sectionTitle: focus.sectionTitle.map { String($0.prefix(300)) },
                sectionLocationID: focus.sectionLocationID.map { String($0.prefix(300)) },
                sectionOrdinal: focus.sectionOrdinal,
                selectionText: focus.selectionText.map { String($0.prefix(2_000)) },
                actionSource: String(focus.actionSource.prefix(64))
            )
        }
        let currentMaterialIDs = Set(course.catalog.lazy.filter(\.isCurrentMaterial).map(\.id))
        visualAssets = request.visualAssets.prefix(4).compactMap { asset in
            guard let boundedID = boundedCourse.itemIDMap[asset.id],
                  currentMaterialIDs.contains(boundedID),
                  asset.filePath.utf8.count <= 4_096,
                  !asset.filePath.contains("\0"),
                  !asset.filePath.contains("\n"),
                  !asset.filePath.contains("\r"),
                  ["image/jpeg", "image/png", "image/webp"].contains(asset.mediaType) else {
                return nil
            }
            return StudyAgentVisualAsset(
                id: boundedID,
                filePath: asset.filePath,
                mediaType: asset.mediaType
            )
        }
        learning = Self.boundedLearningContext(request.learningContext, itemIDMap: boundedCourse.itemIDMap)
    }

    private static func boundedProjectScope(
        _ scope: StudyAgentProjectScope,
        itemIDMap: [String: String]
    ) -> StudyAgentProjectScope {
        let maximumItems = 500
        let items = scope.items.prefix(maximumItems).compactMap { item -> StudyAgentProjectItem? in
            guard let itemID = itemIDMap[item.itemID] else { return nil }
            return StudyAgentProjectItem(
                itemID: itemID,
                title: String(item.title.prefix(300)),
                kind: String(item.kind.prefix(64)),
                role: String(item.role.prefix(64)),
                relativePath: String(item.relativePath.prefix(4_096)),
                resolvedPath: String(item.resolvedPath.prefix(4_096)),
                entryIdentity: item.entryIdentity,
                targetIdentity: item.targetIdentity,
                isShared: item.isShared,
                courseIDs: item.courseIDs.prefix(32).map { String($0.prefix(128)) },
                courseTitles: item.courseTitles.prefix(32).map { String($0.prefix(300)) }
            )
        }
        return StudyAgentProjectScope(
            kind: scope.kind,
            chatID: String(scope.chatID.prefix(128)),
            courseID: scope.courseID.map { String($0.prefix(128)) },
            courseTitle: scope.courseTitle.map { String($0.prefix(300)) },
            rootPath: scope.rootPath.map { String($0.prefix(4_096)) },
            rootIdentity: scope.rootIdentity,
            items: items,
            isTruncated: scope.isTruncated || scope.items.count > items.count
        )
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
                    resolvedAt: memory.resolvedAt,
                    resolutionEvidence: memory.resolutionEvidence.map { String($0.prefix(400)) },
                    createdAt: memory.createdAt,
                    updatedAt: memory.updatedAt
                )
        }
        let location = context.lastLocation.flatMap { location -> StudyLocation? in
            guard let itemID = itemIDMap[location.itemID] else { return nil }
            return StudyLocation(
                itemID: itemID,
                itemTitle: String(location.itemTitle.prefix(300)),
                locationID: location.locationID.map { String($0.prefix(500)) },
                locationTitle: location.locationTitle.map { String($0.prefix(300)) },
                pageIndex: location.pageIndex.map { max($0, 0) + 1 },
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
