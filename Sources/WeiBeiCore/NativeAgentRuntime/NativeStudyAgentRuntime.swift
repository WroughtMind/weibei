import Foundation

public actor NativeStudyAgentRuntime: StudyAgentRuntime {
    public var model: String
    public var adapter: NativeLLMAdapter
    public var contextWindow: Int?
    public var hostToolHandler: StudyAgentHostToolHandler?
    public var liveStores: NativeLiveStores
    public var ledgerRoot: URL
    public var systemPromptText: String
    public var mode: NativeAgentMode
    public var delegateDepth: Int
    public var sessionTitleHandler: StudyAgentSessionTitleHandler?

    private let registry = NativeToolRegistry()
    private let loop = NativeAgentLoop()
    private var didRegisterTools = false

    public init(
        model: String,
        adapter: NativeLLMAdapter,
        contextWindow: Int? = nil,
        ledgerRoot: URL,
        systemPromptText: String,
        hostToolHandler: StudyAgentHostToolHandler? = nil,
        liveStores: NativeLiveStores = .empty,
        mode: NativeAgentMode = .assistant,
        delegateDepth: Int = 0,
        sessionTitleHandler: StudyAgentSessionTitleHandler? = nil
    ) {
        self.model = model
        self.adapter = adapter
        self.contextWindow = contextWindow
        self.ledgerRoot = ledgerRoot
        self.systemPromptText = systemPromptText
        self.hostToolHandler = hostToolHandler
        self.liveStores = liveStores
        self.mode = mode
        self.delegateDepth = delegateDepth
        self.sessionTitleHandler = sessionTitleHandler
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
        let scope = NativeToolScope.session(request.id.uuidString)
        if mode == .assistant {
            await registry.hide("create_document", scope: scope)
            await registry.hide("delegate", scope: scope)
        }
        if delegateDepth >= NativeSubagentRunner.maximumDepth {
            await registry.hide("delegate", scope: scope)
        }
        let tools = await registry.resolved(scope: scope)
        let prompt = NativePromptAssembler.webiSystemPrompt(
            bundledText: systemPromptText,
            tools: tools,
            skillCatalog: liveStores.skillRegistry.catalogSummary(),
            contextRevision: request.contextRevision,
            confirmedNotes: request.confirmedNotes
        )
        var stores = liveStores
        if stores.startSubagent == nil {
            let adapter = self.adapter
            let model = self.model
            let contextWindow = self.contextWindow
            let systemPromptText = self.systemPromptText
            let ledgerRoot = self.ledgerRoot
            let hostToolHandler = self.hostToolHandler
            let depth = delegateDepth
            let baseStores = liveStores
            stores.startSubagent = { request in
                var next = request
                next.depth = max(request.depth, depth + 1)
                return await NativeSubagentRunner.start(
                    next,
                    adapter: adapter,
                    model: model,
                    contextWindow: contextWindow,
                    systemPrompt: systemPromptText,
                    ledgerRoot: ledgerRoot,
                    hostToolHandler: hostToolHandler,
                    liveStores: baseStores
                )
            }
        }
        await loop.reset()
        do {
            let result = try await loop.run(
                request: request,
                ledger: ledger,
                registry: registry,
                adapter: adapter,
                model: model,
                contextWindow: contextWindow,
                hostToolHandler: hostToolHandler,
                systemPrompt: prompt,
                liveStores: stores,
                mode: mode,
                progress: progress
            )
            await scheduleSessionTitleIfNeeded(
                question: request.question,
                answer: result.text,
                ledger: ledger
            )
            return StudyAgentReply(
                text: result.text,
                contentBlocks: result.contentBlocks,
                backend: .native,
                sources: result.sources,
                noteProposal: result.noteProposal,
                relationProposal: result.relationProposal,
                learningUpdate: result.learningUpdate,
                courseProfileUpdate: result.courseProfileUpdate,
                appliedMemoryUpdate: result.appliedMemoryUpdate,
                appliedProfileUpdate: result.appliedProfileUpdate,
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

    private func scheduleSessionTitleIfNeeded(
        question: String,
        answer: String,
        ledger: NativeAgentLedger
    ) async {
        guard mode == .assistant, let handler = sessionTitleHandler else { return }
        let completedTurnCount = (await ledger.allEvents()).filter {
            $0.type == .turnEnd && $0.finishReason == .completed
        }.count
        guard NativeSessionTitle.shouldPropose(completedTurnCount: completedTurnCount) else { return }
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else { return }
        let adapter = self.adapter
        let model = self.model
        Task.detached(priority: .utility) {
            guard let title = await NativeSessionTitle.generate(
                adapter: adapter,
                model: model,
                question: question,
                answer: trimmedAnswer
            ) else { return }
            await handler(title)
        }
    }

    private func ensureTools() async throws {
        guard !didRegisterTools else { return }
        let skillRoot = try AgentResources.bundled().skillsURL
        var stores = liveStores
        if stores.skillRegistry.packs.isEmpty {
            stores.skillRegistry = try NativeSkillRegistry.load(from: skillRoot)
            liveStores = stores
        }
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
