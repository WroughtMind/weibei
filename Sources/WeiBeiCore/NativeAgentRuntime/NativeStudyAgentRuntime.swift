import Foundation

public actor NativeStudyAgentRuntime: StudyAgentRuntime {
    public var model: String
    public var adapter: NativeLLMAdapter
    public var hostToolHandler: StudyAgentHostToolHandler?
    public var ledgerRoot: URL
    public var systemPromptText: String

    private let registry = NativeToolRegistry()
    private let loop = NativeAgentLoop()
    private var didRegisterTools = false

    public init(
        model: String,
        adapter: NativeLLMAdapter,
        ledgerRoot: URL,
        systemPromptText: String,
        hostToolHandler: StudyAgentHostToolHandler? = nil
    ) {
        self.model = model
        self.adapter = adapter
        self.ledgerRoot = ledgerRoot
        self.systemPromptText = systemPromptText
        self.hostToolHandler = hostToolHandler
    }

    public func respond(
        to request: StudyAgentRequest,
        progress: StudyAgentProgressHandler?
    ) async throws -> StudyAgentReply {
        try await ensureTools()
        let sessionID = request.projectScope.chatID.isEmpty
            ? request.id.uuidString.lowercased()
            : request.projectScope.chatID.lowercased()
        let ledgerURL = ledgerRoot
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("ledger.jsonl")
        let ledger = try NativeAgentLedger(fileURL: ledgerURL)
        try await ledger.synthesizeCloserIfNeeded()
        let tools = await registry.resolved(scope: .session(request.id.uuidString))
        let prompt = NativePromptAssembler.webiSystemPrompt(bundledText: systemPromptText, tools: tools)
        await loop.reset()
        do {
            let result = try await loop.run(
                request: request,
                ledger: ledger,
                registry: registry,
                adapter: adapter,
                model: model,
                hostToolHandler: hostToolHandler,
                systemPrompt: prompt,
                progress: progress
            )
            return StudyAgentReply(
                text: result.text,
                backend: .native,
                richAnswer: result.richAnswer,
                noteProposal: result.noteProposal,
                relationProposal: result.relationProposal,
                learningUpdate: result.learningUpdate,
                courseProfileUpdate: result.courseProfileUpdate,
                loadedSkills: result.loadedSkills,
                readItemIDs: result.readItemIDs,
                toolTrace: result.toolTrace
            )
        } catch let failure as NativeLLMFailure {
            throw mapped(failure)
        }
    }

    public func cancel() async {
        await loop.cancel()
    }

    public func reset() async {
        await loop.reset()
    }

    private func ensureTools() async throws {
        guard !didRegisterTools else { return }
        let skillRoot = try? PiAgentResources.bundled().skillsURL
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: skillRoot)
        didRegisterTools = true
    }

    private func mapped(_ failure: NativeLLMFailure) -> Error {
        let kind = failure.asAgentFailureKind
        return NSError(
            domain: "WeiBei.NativeAgent",
            code: failure.status ?? 0,
            userInfo: [NSLocalizedDescriptionKey: kind.userMessage(language: .chinese, userFacingDetail: failure.message)]
        )
    }
}
