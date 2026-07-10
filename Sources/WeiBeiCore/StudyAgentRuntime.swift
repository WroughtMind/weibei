import Foundation

public enum StudyAgentPurpose: String, Codable, Sendable {
    case conversation
    case quietInsight
}

public enum StudyAgentWorkflow: String, Codable, Sendable {
    case automatic
    case closeReading
    case noteMaking
    case recallPractice
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
        self.language = language
        self.contextRevision = contextRevision
    }

    public var resolvedWorkflow: StudyAgentWorkflow {
        guard workflow == .automatic else { return workflow }
        if purpose == .quietInsight { return .closeReading }

        let value = question.lowercased()
        let recallTerms = ["出题", "测验", "复习题", "自测", "quiz", "test me", "questions"]
        if recallTerms.contains(where: value.contains) { return .recallPractice }

        let noteTerms = ["整理", "写入", "笔记", "润色", "摘录", "要点", "outline", "organize", "note", "rewrite"]
        if noteTerms.contains(where: value.contains) { return .noteMaking }

        return .closeReading
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

public struct StudyAgentReply: Equatable, Sendable {
    public var text: String
    public var backend: StudyAgentBackend
    public var noteProposal: StudyAgentNoteProposal?

    public init(text: String, backend: StudyAgentBackend, noteProposal: StudyAgentNoteProposal? = nil) {
        self.text = text
        self.backend = backend
        self.noteProposal = noteProposal
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

    public init(request: StudyAgentRequest) {
        schemaVersion = 1
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
    }
}
