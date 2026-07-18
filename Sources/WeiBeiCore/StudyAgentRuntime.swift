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

public enum StudyAgentQuestionScope {
    public static func allowsLearningOnlyAnswer(_ question: String) -> Bool {
        var remainder = question.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
        }.map(String.init).joined()
        let statePhrases = [
            "你记得我的学习情况吗", "你记得我学到哪吗", "我上次学习到哪了", "我上次学习到哪",
            "我上次学到哪了", "我上次学到哪", "上次学习到哪了", "上次学习到哪",
            "上次学到哪了", "上次学到哪", "我的学习进度", "学习进度", "我的学习目标", "学习目标",
            "我的目标", "我的学习困惑", "学习困惑", "我的困惑", "接下来学什么",
            "接下来做什么", "下一步学什么", "下一步做什么", "下一步", "你记得我吗",
            "wheredidistoplasttime", "whereididstoplasttime", "learningprogress", "mygoal", "mylearninggoal",
            "myconfusion", "whatnext", "doyourememberme",
        ]
        var matchedStatePhrase = false
        for phrase in statePhrases where remainder.contains(phrase) {
            remainder = remainder.replacingOccurrences(of: phrase, with: "")
            matchedStatePhrase = true
        }
        guard matchedStatePhrase else { return false }
        let benignWords = [
            "请告诉我一下", "请告诉我", "告诉我一下", "告诉我", "我", "的", "是", "什么",
            "有哪些", "请", "一下", "了", "吗", "呢", "和", "以及", "位置", "在哪", "哪里",
            "当前", "现在", "想", "要", "please", "tellme", "the", "and", "location",
            "current", "now", "what", "is", "are", "my", "i", "did", "lasttime",
        ]
        for word in benignWords {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        return remainder.isEmpty
    }
}

public enum StudyAgentRichAnswerRequest {
    public static func isExplicit(_ question: String) -> Bool {
        let normalized = question.lowercased()
        let choiceTerms = [
            "自行选择最合适的回答形态", "自行选择回答形态", "选择最合适的回答形态",
            "只有交互或可视关系", "不要为了展示能力硬做", "无需富回答", "不需要富回答", "不要富回答",
            "choose the best answer format", "choose the most suitable answer format",
            "only generate a rich answer when", "do not force a rich answer", "no rich answer needed",
        ]
        guard !choiceTerms.contains(where: normalized.contains) else { return false }

        let requestTerms = [
            "用富回答", "用可调的富回答", "给我富回答", "生成富回答", "做成富回答", "以富回答", "富回答形式",
            "做成可调", "给个可调", "做成可交互", "给个可交互", "做个交互", "做个互动",
            "用图示", "画个函数图", "画出函数图", "做个关系图", "做个时间线", "时间线展示",
            "做个图像叠层", "做个模拟", "做个实验", "实验演示", "演示这个实验",
            "use a rich answer", "give me a rich answer", "generate a rich answer", "rich answer format",
            "make it interactive", "show an interactive", "interactive timeline", "with a diagram", "draw a function graph", "show a relationship graph",
            "show a timeline", "show an image overlay", "run a simulation", "show an experiment",
            "run an experiment",
        ]
        return requestTerms.contains(where: normalized.contains)
    }
}

public enum StudyAgentResolutionEvidence {
    public static func matches(_ evidence: String, question: String) -> Bool {
        guard StudyAgentCurrentTurnEvidence.matches(evidence, question: question),
              let statement = statement(in: evidence) else { return false }
        let value = statement.lowercased()
        let unresolvedTerms = [
            "不懂", "不理解", "不会", "没懂", "仍然困惑", "还是困惑", "不知道", "不能区分", "不能够",
            "还不能", "尚不能", "无法", "没法", "尚未", "还没", "并不", "不太", "不确定",
            "不正确", "并非正确", "答错", "错误", "不对",
            "don't understand", "do not understand", "can't", "cannot", "still confused", "not sure",
            "not able", "unable", "not yet", "have not", "haven't", "incorrect", "not correct", "wrong answer", "is wrong",
        ]
        guard !unresolvedTerms.contains(where: value.contains) else { return false }
        let questionTerms = ["什么", "为什么", "怎么", "为何", "吗", "？", "?", "what", "why", "how"]
        guard !questionTerms.contains(where: value.contains) else { return false }
        let masteryTerms = [
            "懂了", "明白了", "会了", "掌握了", "可以区分", "能够区分", "能解释", "答对", "正确",
            "解决了", "不再困惑", "understand now", "got it", "can distinguish", "can explain", "correct",
        ]
        if masteryTerms.contains(where: value.contains) { return true }
        let answerMarkers = [
            "是", "指", "因为", "所以", "而", "但是", "扣除", "等于", "相比", "表示", "反映", "意味着", "即", "=",
            " is ", " means", "because", "therefore", "while", "equals", "represents", "reflects", "differs",
        ]
        guard answerMarkers.contains(where: value.contains) else { return false }
        let meaningfulCount = statement.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        return meaningfulCount >= 12
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

public enum StudyAgentCurrentTurnEvidence {
    public static func matches(_ evidence: String, question: String) -> Bool {
        guard let statement = statement(in: evidence), statement.count >= 2 else { return false }
        if statement.count < 4 {
            return normalized(statement) == normalized(question)
        }
        var searchStart = question.startIndex
        while searchStart < question.endIndex,
              let range = question.range(of: statement, range: searchStart..<question.endIndex) {
            if hasClauseBoundaries(range, in: question),
               !omitsLeadingNegation(range, in: question) {
                return true
            }
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

    private static func omitsLeadingNegation(
        _ range: Range<String.Index>,
        in question: String
    ) -> Bool {
        guard range.lowerBound > question.startIndex else { return false }
        let prefix = String(question[..<range.lowerBound]).lowercased()
        let immediate = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["不", "没", "未", "无", "别", "勿"].contains(where: immediate.hasSuffix) {
            return true
        }
        let clause = prefix
            .components(separatedBy: CharacterSet(charactersIn: "，,。！？；;:：.!?"))
            .last ?? prefix
        let negativePhrases = [
            "不想", "不喜欢", "不太", "不能", "不会", "不要", "不愿", "没有", "没法", "尚未", "还没", "并不", "并非",
            " not ", " never ", " no ", " without ", "cannot", "can't", "don't", "doesn't", "didn't",
        ]
        let paddedClause = " \(clause) "
        return negativePhrases.contains(where: paddedClause.contains)
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

    private static func normalized(_ text: String) -> String {
        text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.map(String.init).joined()
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
    public var materialIsTruncated: Bool
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
        materialIsTruncated: Bool = false,
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
        self.materialIsTruncated = materialIsTruncated
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

public struct StudyAgentReply: Equatable, Sendable {
    public var text: String
    public var backend: StudyAgentBackend
    public var richAnswer: RichAnswerPresentation?
    public var noteProposal: StudyAgentNoteProposal?
    public var learningUpdate: StudyAgentLearningUpdate?
    public var toolTrace: [String]

    public init(
        text: String,
        backend: StudyAgentBackend,
        richAnswer: RichAnswerPresentation? = nil,
        noteProposal: StudyAgentNoteProposal? = nil,
        learningUpdate: StudyAgentLearningUpdate? = nil,
        toolTrace: [String] = []
    ) {
        self.text = text
        self.backend = backend
        self.richAnswer = richAnswer
        self.noteProposal = noteProposal
        self.learningUpdate = learningUpdate
        self.toolTrace = toolTrace
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
