import Foundation

public actor NativeStudyAgentRuntime: StudyAgentRuntime {
    public var model: String
    public var adapter: NativeLLMAdapter
    public var hostToolHandler: StudyAgentHostToolHandler?
    public var liveStores: NativeLiveStores
    public var ledgerRoot: URL
    public var systemPromptText: String
    public var mode: NativeAgentMode
    public var delegateDepth: Int

    private let registry = NativeToolRegistry()
    private let loop = NativeAgentLoop()
    private var didRegisterTools = false

    public init(
        model: String,
        adapter: NativeLLMAdapter,
        ledgerRoot: URL,
        systemPromptText: String,
        hostToolHandler: StudyAgentHostToolHandler? = nil,
        liveStores: NativeLiveStores = .empty,
        mode: NativeAgentMode = .assistant,
        delegateDepth: Int = 0
    ) {
        self.model = model
        self.adapter = adapter
        self.ledgerRoot = ledgerRoot
        self.systemPromptText = systemPromptText
        self.hostToolHandler = hostToolHandler
        self.liveStores = liveStores
        self.mode = mode
        self.delegateDepth = delegateDepth
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
            skillCatalog: liveStores.skillRegistry.catalogSummary()
        )
        var stores = liveStores
        if stores.startSubagent == nil {
            let adapter = self.adapter
            let model = self.model
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
                hostToolHandler: hostToolHandler,
                systemPrompt: prompt,
                liveStores: stores,
                mode: mode,
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
        var stores = liveStores
        if stores.skillRegistry.packs.isEmpty, let skillRoot {
            stores.skillRegistry = (try? NativeSkillRegistry.load(from: skillRoot)) ?? stores.skillRegistry
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
