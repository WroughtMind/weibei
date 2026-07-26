import Darwin
import Foundation

public actor PiAgentRuntime: StudyAgentRuntime {
    private static let processReadinessTimeoutSeconds: UInt64 = 12
    private static let allowedToolNames = [
        "weibei_context",
        "weibei_course_map",
        "weibei_course_search",
        "weibei_visual_asset",
        "weibei_learning_memory",
        "weibei_learning_update",
        "read",
        "weibei_note_proposal",
        "weibei_ui_catalog",
        "weibei_compute_artifact",
        "weibei_rich_answer",
    ]

    private struct ProgressDelivery: Sendable {
        let continuation: AsyncStream<StudyAgentProgress>.Continuation
        let task: Task<Void, Never>

        init(handler: @escaping StudyAgentProgressHandler) {
            let pair = AsyncStream<StudyAgentProgress>.makeStream(
                bufferingPolicy: .bufferingNewest(32)
            )
            continuation = pair.continuation
            task = Task.detached(priority: .userInitiated) {
                for await event in pair.stream {
                    await handler(event)
                }
            }
        }

        func yield(_ event: StudyAgentProgress) {
            continuation.yield(event)
        }

        func finish() {
            continuation.finish()
            task.cancel()
        }
    }

    private struct PendingCommand {
        var continuation: CheckedContinuation<PiRPCResponse, Error>
        var timeoutTask: Task<Void, Never>
    }

    private struct ActiveRun {
        var id: UUID
        var contextRevision: String
        var memoryRevision: UInt64
        var userQuestion: String
        var workflow: StudyAgentWorkflow
        var answerFormPolicy: StudyAgentAnswerFormPolicy
        var allowsLearningOnlyAnswer: Bool
        var allowsSourceFreeAnswer: Bool
        var allowsSourcelessLimitation: Bool
        var resolvableMemoryIDs: Set<String>
        var allowedSourceLabels: Set<String>
        var allowedAssetIDs: Set<String>
        var persistentAssetIDsByContextID: [String: String]
        var allowedJumpReferences: Set<String>
        var jumpEvidenceLabels: [String: Set<String>]
        var allowedLearningLabels: Set<String> = []
        var lastLocationSourceLabel: String?
        var allowedNoteSourceLabels: Set<String>
        var didReadContext = false
        var answeredBeforeContext = false
        var streamedText = ""
        var proposal: StudyAgentNoteProposal?
        var richAnswer: RichAnswerPresentation?
        var learningUpdate: StudyAgentLearningUpdate?
        var loadedSkills: [StudyAgentLoadedSkill] = []
        var toolTrace: [String] = []
        var lastError: String?
        var progressDelivery: ProgressDelivery?
        var continuation: CheckedContinuation<StudyAgentReply, Error>?
        var completed: Result<StudyAgentReply, Error>?
        var watchdogTask: Task<Void, Never>?
    }

    private let executableOverride: URL?
    private let runtimeDirectory: URL
    private let runInactivityTimeoutNanoseconds: UInt64
    private var providerConfiguration = PiAgentProviderConfiguration()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var pendingCommands: [String: PendingCommand] = [:]
    private var activeRun: ActiveRun?
    private var startingRunID: UUID?
    private var cancelledStartingRunIDs: Set<UUID> = []
    private var stderrBuffer = ""
    private var startupFailure: PiAgentRuntimeError?
    private var idleShutdownTask: Task<Void, Never>?
    private let traceEnabled = ProcessInfo.processInfo.environment["WEIBEI_PI_TRACE"] == "1"

    public init(
        executableURL: URL? = nil,
        runtimeDirectory: URL? = nil,
        // Idle hang detection: 90s without events (was 5 minutes).
        runInactivityTimeoutNanoseconds: UInt64 = 90_000_000_000
    ) {
        executableOverride = executableURL
        self.runtimeDirectory = runtimeDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("WeiBei/AgentRuntime", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiAgentRuntime", isDirectory: true)
        self.runInactivityTimeoutNanoseconds = max(1, runInactivityTimeoutNanoseconds)
    }

    public func configure(_ configuration: PiAgentProviderConfiguration) {
        guard providerConfiguration != configuration else { return }
        providerConfiguration = configuration
        shutdownProcess(reason: PiAgentRuntimeError.cancelled)
    }

    public func healthCheck() async throws -> String {
        try await ensureProcess()
        return process?.executableURL?.path ?? "pi"
    }

    public func respond(to request: StudyAgentRequest, progress: StudyAgentProgressHandler?) async throws -> StudyAgentReply {
        guard activeRun == nil, startingRunID == nil else { throw PiAgentRuntimeError.busy }
        startingRunID = request.id
        defer {
            if startingRunID == request.id {
                startingRunID = nil
            }
            cancelledStartingRunIDs.remove(request.id)
        }
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        try await ensureProcess()
        try requireStartingRun(request.id)

        _ = try await sendCommand(type: "new_session", timeoutSeconds: 3)
        try requireStartingRun(request.id)
        let context = StudyAgentContextEnvelope(request: request)
        try writeContext(context)
        let progressDelivery = progress.map(ProgressDelivery.init(handler:))

        let currentJumpEvidence = currentJumpEvidence(in: context)
        let currentSourceLabels = currentSourceLabels(in: context)
        activeRun = ActiveRun(
            id: request.id,
            contextRevision: request.contextRevision,
            memoryRevision: request.learningContext.memoryRevision,
            userQuestion: request.question,
            workflow: request.resolvedWorkflow,
            answerFormPolicy: request.answerFormPolicy,
            allowsLearningOnlyAnswer: StudyAgentQuestionScope.allowsLearningOnlyAnswer(request.question),
            allowsSourceFreeAnswer: StudyAgentQuestionScope.allowsSourceFreeAnswer(request.question),
            allowsSourcelessLimitation: currentSourceLabels.isEmpty,
            resolvableMemoryIDs: Set(request.learningContext.memories.compactMap { memory in
                guard memory.status == .active,
                      memory.kind == .goal || memory.kind == .confusion || memory.kind == .nextStep else {
                    return nil
                }
                return memory.id.uuidString.lowercased()
            }),
            allowedSourceLabels: currentSourceLabels,
            allowedAssetIDs: currentAssetIDs(in: context),
            persistentAssetIDsByContextID: persistentAssetIDsByContextID(
                request: request,
                context: context
            ),
            allowedJumpReferences: Set(currentJumpEvidence.keys),
            jumpEvidenceLabels: currentJumpEvidence,
            lastLocationSourceLabel: context.learning.lastLocation.map { "[材料：\($0.itemTitle)]" },
            allowedNoteSourceLabels: currentSourceLabels,
            progressDelivery: progressDelivery
        )
        progressDelivery?.yield(.readingContext)
        startingRunID = nil
        refreshRunWatchdog()
        do {
            _ = try await sendCommand(
                type: "prompt",
                fields: ["message": piPrompt(for: request)],
                timeoutSeconds: 3
            )
        } catch {
            let failure = promptSubmissionFailure(from: error)
            discardRun(id: request.id)
            shutdownProcess(reason: failure)
            throw failure
        }

        return try await waitForRun(id: request.id)
    }

    public func cancel() async {
        if let runID = activeRun?.id {
            await cancelRun(id: runID)
            return
        }
        guard let runID = startingRunID else { return }
        cancelledStartingRunIDs.insert(runID)
        startingRunID = nil
        shutdownProcess(reason: PiAgentRuntimeError.cancelled)
    }

    private func requireStartingRun(_ runID: UUID) throws {
        guard startingRunID == runID, !cancelledStartingRunIDs.contains(runID) else {
            throw PiAgentRuntimeError.cancelled
        }
    }

    private func cancelRun(id runID: UUID) async {
        guard activeRun?.id == runID else { return }
        finishRun(id: runID, with: .failure(PiAgentRuntimeError.cancelled))
        shutdownProcess(reason: PiAgentRuntimeError.cancelled)
    }

    public func reset() async {
        await cancel()
    }

    public func shutdown() async {
        let runningProcess = process
        shutdownProcess(reason: PiAgentRuntimeError.cancelled)
        await forceStopIfNeeded(runningProcess, graceNanoseconds: 750_000_000)
    }

    private func ensureProcess() async throws {
        if let process, process.isRunning { return }

        let executableURL = executableOverride ?? PiExecutableLocator.locate()
        guard let executableURL else { throw PiAgentRuntimeError.unavailable }
        _ = try PiBundledRuntime.validate(executableURL: executableURL)
        let resources = try PiAgentResources.bundled()
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeDirectory.path)
        let piConfigurationURL = try preparePiConfigurationDirectory()
        let piSessionURL = runtimeDirectory.appendingPathComponent("Sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: piSessionURL, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: piSessionURL.path)

        let contextURL = runtimeDirectory.appendingPathComponent("context.json")
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.currentDirectoryURL = runtimeDirectory
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.arguments = launchArguments(resources: resources)
        process.environment = launchEnvironment(
            executableURL: executableURL,
            contextURL: contextURL,
            piConfigurationURL: piConfigurationURL
        )
        process.terminationHandler = { [weak self] terminated in
            Task { await self?.processDidTerminate(pid: terminated.processIdentifier, status: terminated.terminationStatus) }
        }

        stderrBuffer = ""
        startupFailure = nil
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting

        do {
            try process.run()
            trace("launched pid=\(process.processIdentifier) executable=\(executableURL.path)")
        } catch {
            self.process = nil
            inputHandle = nil
            throw PiAgentRuntimeError.launchFailed(error.localizedDescription)
        }

        stdoutTask = readStdout(outputPipe.fileHandleForReading)
        stderrTask = readStderr(errorPipe.fileHandleForReading)

        do {
            let state = try await sendCommand(
                type: "get_state",
                timeoutSeconds: Self.processReadinessTimeoutSeconds
            )
            guard state.dataJSON != nil else {
                throw PiAgentRuntimeError.protocolFailure("get_state returned no data")
            }
            let commands = try await sendCommand(
                type: "get_commands",
                timeoutSeconds: Self.processReadinessTimeoutSeconds
            )
            try verifyRequiredSkills(in: commands)
            if let startupFailure { throw startupFailure }
        } catch {
            shutdownProcess(reason: error)
            throw error
        }
    }

    private func launchArguments(resources: PiAgentResources) -> [String] {
        var arguments = [
            "--mode", "rpc",
            "--offline",
            "--no-session",
            "--no-builtin-tools",
            "--tools", Self.allowedToolNames.joined(separator: ","),
            "--no-extensions",
            "--extension", resources.extensionURL.path,
            "--no-skills",
            "--skill", resources.skillsURL.path,
            "--no-prompt-templates",
            "--no-themes",
            "--no-context-files",
            "--no-approve",
            "--system-prompt", resources.systemPrompt,
            "--name", "WeiBei",
        ]
        if let provider = providerConfiguration.provider, !provider.isEmpty {
            arguments.append(contentsOf: ["--provider", provider])
        }
        if let model = providerConfiguration.model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        if !providerConfiguration.thinkingLevel.isEmpty {
            arguments.append(contentsOf: ["--thinking", providerConfiguration.thinkingLevel])
        }
        return arguments
    }

    private func piPrompt(for request: StudyAgentRequest) -> String {
        let skillName: String
        switch request.resolvedWorkflow {
        case .automatic, .studyCompanion:
            skillName = "weibei-study-companion"
        case .courseWayfinding:
            skillName = "weibei-course-wayfinding"
        case .closeReading:
            skillName = "weibei-close-reading"
        case .noteMaking:
            skillName = "weibei-note-making"
        case .recallPractice:
            skillName = "weibei-recall-practice"
        }
        return "/skill:\(skillName) \(request.question)"
    }

    private func currentSourceLabels(in context: StudyAgentContextEnvelope) -> Set<String> {
        var labels: [String] = []
        if !context.note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            labels.append("[笔记：\(context.note.title)]")
        }
        if let material = context.material,
           !material.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            labels.append("[材料：\(material.title)]")
        }
        if let selection = context.selection,
           !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            labels.append("[选区：\(selection.title)]")
        }
        return Set(labels)
    }

    private func currentAssetIDs(in context: StudyAgentContextEnvelope) -> Set<String> {
        Set(context.course.catalog.lazy.filter(\.isCurrentMaterial).map(\.id))
    }

    private func persistentAssetIDsByContextID(
        request: StudyAgentRequest,
        context: StudyAgentContextEnvelope
    ) -> [String: String] {
        let persistentCatalog = request.courseContext.catalog.prefix(context.course.catalog.count)
        return Dictionary(uniqueKeysWithValues: zip(context.course.catalog, persistentCatalog).map { contextItem, persistentItem in
            (contextItem.id, persistentItem.id)
        })
    }

    private func currentJumpEvidence(in context: StudyAgentContextEnvelope) -> [String: Set<String>] {
        var evidence: [String: Set<String>] = [:]
        func add(_ rawReference: String, label: String) {
            guard let reference = canonicalJumpReference(rawReference) else { return }
            evidence[reference, default: []].insert(label)
        }
        if !context.note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("来源：\(context.note.title)", label: "[笔记：\(context.note.title)]")
        }
        if let material = context.material,
           !material.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("来源：\(material.title)", label: "[材料：\(material.title)]")
        }
        if let selection = context.selection,
           !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("来源：\(selection.title)", label: "[选区：\(selection.title)]")
        }
        return evidence
    }

    private func registerJumpEvidence(
        _ jumpEvidence: [String: String],
        in run: inout ActiveRun
    ) {
        for (rawReference, label) in jumpEvidence {
            guard let reference = canonicalJumpReference(rawReference) else { continue }
            run.allowedJumpReferences.insert(reference)
            run.jumpEvidenceLabels[reference, default: []].insert(label)
        }
    }

    private func citedContentLabels(in text: String) -> Set<String> {
        labels(in: text, pattern: #"\[(?:材料|笔记|选区)：[^\]\n]{1,300}\]"#)
    }

    private func citedLearningLabels(in text: String) -> Set<String> {
        Set(["[学习记录：上次位置]", "[学习记忆：用户状态]", "[学习记忆：无记录]", "[会话：当前]"])
            .filter { text.contains($0) }
    }

    private func citedJumpReferences(in text: String) -> Set<String> {
        Set(text.components(separatedBy: .newlines).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix(">") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard line.contains("来源：") || line.localizedCaseInsensitiveContains("source:") else {
                return nil
            }
            guard isDedicatedJumpLine(line) else { return nil }
            return canonicalJumpReference(line)
        })
    }

    private func isDedicatedJumpLine(_ line: String) -> Bool {
        line.range(
            of: #"^\s*(?:[-*+>→]\s*)?(?:(?:(?:可点击)?(?:来源|跳转)\s*[:：]?|(?:clickable\s+)?(?:source|jump)\s*:?)\s*)?[`*_]*(?:来源：|source:)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func canonicalJumpReference(_ raw: String) -> String? {
        let reference = SourceReferenceTitle.parse(raw)
        let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              !title.hasPrefix("["),
              !title.contains("来源："),
              !title.localizedCaseInsensitiveContains("source:") else { return nil }
        var result = "来源：\(title)"
        if let ordinal = reference.courseItemOrdinal {
            result += "，条目：\(ordinal)"
        }
        if let pageIndex = reference.pageIndex {
            result += "，第 \(pageIndex + 1) 页"
        }
        if let sectionLocationID = reference.sectionLocationID {
            result += "，章节标识：\(sectionLocationID)"
        }
        if let sectionOrdinal = reference.sectionOrdinal {
            result += "，章节序号：\(sectionOrdinal)"
        }
        if let sectionTitle = reference.sectionTitle {
            result += "，章节：\(sectionTitle)"
        }
        return result
    }

    private func labels(in text: String, pattern: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        })
    }

    private func answerValidationError(text: String, run: ActiveRun) -> String? {
        let contentLabels = citedContentLabels(in: text)
        let learningLabels = citedLearningLabels(in: text)
        if contentLabels.isEmpty,
           run.allowsSourcelessLimitation,
           !run.allowsSourceFreeAnswer,
           !run.allowsLearningOnlyAnswer {
            guard run.richAnswer == nil else {
                return "PI returned a rich answer without any readable current-turn source"
            }
            guard learningLabels.isEmpty else {
                return "PI cited learning memory instead of explaining the missing current-turn source"
            }
            guard StudyAgentSourceLimitation.isHonest(text) else {
                return "PI returned an uncited answer without clearly explaining the missing source evidence"
            }
            return nil
        }
        if let validationError = PiAnswerEvidenceRequirement.validationError(
            contentLabels: contentLabels,
            learningLabels: learningLabels,
            allowsLearningOnlyAnswer: run.allowsLearningOnlyAnswer,
            allowsSourceFreeAnswer: run.allowsSourceFreeAnswer
        ) {
            return validationError
        }
        guard contentLabels.isSubset(of: run.allowedSourceLabels) else {
            return "PI cited a source that was not read in the current turn"
        }
        let jumpReferences = citedJumpReferences(in: text)
        let unverifiedJumpReferences = jumpReferences.subtracting(run.allowedJumpReferences)
        guard unverifiedJumpReferences.isEmpty else {
            return "PI suggested a jump location that was not returned by a current-turn tool: \(unverifiedJumpReferences.sorted().joined(separator: ", "))"
        }
        let citedEvidenceLabels = contentLabels.union(learningLabels)
        let mismatchedJumpReferences = jumpReferences.filter { reference in
            guard let requiredLabels = run.jumpEvidenceLabels[reference], !requiredLabels.isEmpty else {
                return true
            }
            return requiredLabels.isDisjoint(with: citedEvidenceLabels)
        }
        guard mismatchedJumpReferences.isEmpty else {
            return "PI suggested a jump that does not match its cited evidence: \(mismatchedJumpReferences.sorted().joined(separator: ", "))"
        }
        guard learningLabels.isSubset(of: run.allowedLearningLabels) else {
            return "PI cited learning memory before reading it"
        }
        return nil
    }

    private func learningUpdateValidationError(
        _ update: StudyAgentLearningUpdate,
        run: ActiveRun
    ) -> String? {
        guard !run.allowedLearningLabels.isEmpty else {
            return "PI proposed a learning-memory update before reading learning memory"
        }
        for entry in update.entries {
            let evidenceIsCurrentTurn = entry.evidence.hasPrefix("[用户：本轮]")
                || entry.evidence.hasPrefix("[会话：当前]")
            if evidenceIsCurrentTurn,
               !currentTurnEvidenceMatches(entry.evidence, question: run.userQuestion) {
                return "PI proposed learning memory without quoting the current user turn"
            }
            let evidenceIsReadSource = run.allowedSourceLabels.contains {
                entry.evidence.hasPrefix($0)
            }
            guard evidenceIsCurrentTurn || evidenceIsReadSource else {
                return "PI proposed learning memory with evidence that was not read"
            }
            if entry.origin == .userStatement,
               !entry.evidence.hasPrefix("[用户：本轮]") {
                return "PI marked a memory as a user statement without direct user evidence"
            }
        }
        guard update.resolutions.allSatisfy({ resolution in
            run.resolvableMemoryIDs.contains(resolution.memoryID.lowercased())
                && resolutionEvidenceMatches(resolution.evidence, question: run.userQuestion)
        }) else {
            return "PI resolved learning memory without current-turn evidence"
        }
        return nil
    }

    private func currentTurnEvidenceMatches(_ evidence: String, question: String) -> Bool {
        StudyAgentCurrentTurnEvidence.matches(evidence, question: question)
    }

    private func resolutionEvidenceMatches(_ evidence: String, question: String) -> Bool {
        StudyAgentResolutionEvidence.matches(evidence, question: question)
    }

    private func launchEnvironment(
        executableURL: URL,
        contextURL: URL,
        piConfigurationURL: URL
    ) -> [String: String] {
        let executableDirectory = executableURL.deletingLastPathComponent().path
        var environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "\(executableDirectory):/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": FileManager.default.temporaryDirectory.path,
            "PI_TELEMETRY": "0",
            "PI_OFFLINE": "1",
            "PI_SKIP_VERSION_CHECK": "1",
            "PI_ZH_AUTO_UPDATE": "0",
            "PI_PACKAGE_DIR": executableDirectory,
            "PI_CODING_AGENT_DIR": piConfigurationURL.path,
            "PI_CODING_AGENT_SESSION_DIR": runtimeDirectory.appendingPathComponent("Sessions", isDirectory: true).path,
            "WEIBEI_AGENT_CONTEXT_FILE": contextURL.path,
            "WEIBEI_AGENT_RUNTIME": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "NO_COLOR": "1",
            "TERM": "dumb",
        ]
        let hostEnvironment = ProcessInfo.processInfo.environment
        for key in [
            "LANG", "LC_ALL",
            // Cloud / multi-part provider credentials from the host shell.
            "AWS_PROFILE", "AWS_REGION", "AWS_DEFAULT_REGION",
            "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
            "AWS_BEARER_TOKEN_BEDROCK", "AWS_ENDPOINT_URL_BEDROCK_RUNTIME",
            "GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT", "GOOGLE_CLOUD_LOCATION",
            "GOOGLE_APPLICATION_CREDENTIALS",
            "CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE_GATEWAY_ID", "CLOUDFLARE_API_KEY",
            "AZURE_OPENAI_BASE_URL", "AZURE_OPENAI_RESOURCE_NAME",
            "AZURE_OPENAI_API_VERSION", "AZURE_OPENAI_DEPLOYMENT_NAME_MAP",
        ] {
            if let value = hostEnvironment[key], !value.isEmpty, value.count <= 2048, !value.contains("\n") {
                environment[key] = value
            }
        }
        if let apiKey = providerConfiguration.apiKey, !apiKey.isEmpty {
            // Inject into the provider's canonical env var (Pi resolution order).
            if let providerID = providerConfiguration.provider.flatMap(AgentProviderID.init(rawValue:)) {
                environment[providerID.environmentAPIKeyName] = apiKey
            } else if let provider = providerConfiguration.provider?.lowercased() {
                // Fallback map for ids that may not be in the enum yet.
                let envName = Self.legacyEnvName(forPiProvider: provider) ?? "OPENAI_API_KEY"
                environment[envName] = apiKey
            } else {
                environment["OPENAI_API_KEY"] = apiKey
            }
            // Many OpenAI-compatible stacks still read OPENAI_API_KEY.
            if environment["OPENAI_API_KEY"] == nil {
                environment["OPENAI_API_KEY"] = apiKey
            }
        }
        // Base URL: Azure uses dedicated env; OpenAI-compatible stacks still get models.json.
        if let base = providerConfiguration.baseURL, !base.isEmpty {
            let provider = providerConfiguration.provider?.lowercased() ?? ""
            if provider == "azure-openai-responses" {
                environment["AZURE_OPENAI_BASE_URL"] = base
            }
        }
        return environment
    }

    private static func legacyEnvName(forPiProvider provider: String) -> String? {
        switch provider {
        case "openai", "openai-codex": return "OPENAI_API_KEY"
        case "anthropic": return "ANTHROPIC_API_KEY"
        case "google": return "GEMINI_API_KEY"
        case "openrouter": return "OPENROUTER_API_KEY"
        case "github-copilot": return "COPILOT_GITHUB_TOKEN"
        case "xai": return "XAI_API_KEY"
        case "deepseek": return "DEEPSEEK_API_KEY"
        case "groq": return "GROQ_API_KEY"
        case "mistral": return "MISTRAL_API_KEY"
        case "together": return "TOGETHER_API_KEY"
        case "fireworks": return "FIREWORKS_API_KEY"
        case "huggingface": return "HF_TOKEN"
        case "moonshotai", "moonshotai-cn": return "MOONSHOT_API_KEY"
        case "kimi-coding": return "KIMI_API_KEY"
        case "minimax": return "MINIMAX_API_KEY"
        case "minimax-cn": return "MINIMAX_CN_API_KEY"
        default: return nil
        }
    }

    /// Inject a custom / local OpenAI-compatible provider into PI_CODING_AGENT_DIR/models.json.
    /// Built-in Pi providers (including Azure) use auth + env vars instead.
    public func writeCustomModelsJSONIfNeeded(
        providerID: AgentProviderID,
        baseURL: String,
        model: String
    ) async {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard providerID == .custom || providerID == .llamaCpp else {
            return
        }
        guard !trimmedBase.isEmpty else { return }
        do {
            let destination = try preparePiConfigurationDirectory()
            let modelsURL = destination.appendingPathComponent("models.json")
            let providerKey = providerID.piProviderName
            let modelID = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? providerID.defaultModelHint
                : model.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload: [String: Any] = [
                "providers": [
                    providerKey: [
                        "baseUrl": trimmedBase,
                        "api": "openai-completions",
                        "models": [
                            [
                                "id": modelID,
                                "name": modelID,
                            ],
                        ],
                    ],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: modelsURL, options: .atomic)
            trace("wrote custom models.json provider=\(providerKey) baseUrl=\(trimmedBase)")
        } catch {
            trace("failed to write models.json: \(error.localizedDescription)")
        }
    }

    private func promptSubmissionFailure(from error: Error) -> PiAgentRuntimeError {
        if error is CancellationError || Task.isCancelled {
            return .cancelled
        }
        guard let runtimeError = error as? PiAgentRuntimeError else {
            return .inFlightFailed(error.localizedDescription)
        }
        switch runtimeError {
        case .cancelled, .commandRejected:
            return runtimeError
        default:
            return .inFlightFailed(runtimeError.localizedDescription)
        }
    }

    private func preparePiConfigurationDirectory() throws -> URL {
        let fileManager = FileManager.default
        let destination = runtimeDirectory.appendingPathComponent("PiConfig", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path)

        // WeiBei-owned Pi agent dir only — do not read/write terminal `~/.pi/agent` each launch.
        try WeiBeiAgentDataPaths.ensurePiAgentDirectory()
        WeiBeiAgentDataPaths.migrateHomePiAuthIfNeeded()
        let source = WeiBeiAgentDataPaths.piAgentDirectory

        if source.standardizedFileURL != destination.standardizedFileURL {
            syncLocalPiAuth(from: source, to: destination)
            seedLocalPiSettings(from: source, to: destination)
        }
        return destination
    }

    private func syncLocalPiAuth(from sourceDirectory: URL, to destinationDirectory: URL) {
        let fileManager = FileManager.default
        let destination = destinationDirectory.appendingPathComponent("auth.json")
        let source = sourceDirectory.appendingPathComponent("auth.json")
        guard let attributes = try? fileManager.attributesOfItem(atPath: source.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= 1_048_576,
              let sourceData = try? Data(contentsOf: source),
              let sourceObject = try? JSONSerialization.jsonObject(with: sourceData) as? [String: Any]
        else { return }

        // Prefer WeiBei-owned auth; keep any destination-only keys for this workspace runtime.
        var merged = sourceObject
        if let existingData = try? Data(contentsOf: destination),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            for (key, value) in existing where merged[key] == nil {
                merged[key] = value
            }
            // WeiBei store wins for OAuth providers (subscription login from Settings).
            for (key, value) in sourceObject {
                if let entry = value as? [String: Any], entry["type"] as? String == "oauth" {
                    merged[key] = value
                }
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination, options: [.atomic])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            trace("could not seed isolated PI auth: \(error.localizedDescription)")
        }
    }

    private func piAuthDataContainsCredential(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !root.isEmpty else {
            return false
        }
        let credentialKeys = ["access", "refresh", "key", "apiKey", "token"]
        return root.values.contains { value in
            guard let credential = value as? [String: Any] else { return false }
            return credentialKeys.contains { key in
                guard let candidate = credential[key] as? String else { return false }
                return !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private func seedLocalPiSettings(from sourceDirectory: URL, to destinationDirectory: URL) {
        let source = sourceDirectory.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: source),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let allowedKeys = ["defaultProvider", "defaultModel", "defaultThinkingLevel"]
        let settings = allowedKeys.reduce(into: [String: Any]()) { result, key in
            if let value = object[key] as? String {
                result[key] = value
            }
        }
        guard JSONSerialization.isValidJSONObject(settings),
              let sanitized = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]) else { return }
        let destination = destinationDirectory.appendingPathComponent("settings.json")
        do {
            try sanitized.write(to: destination, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            trace("could not seed isolated PI settings: \(error.localizedDescription)")
        }
    }

    private func writeContext(_ context: StudyAgentContextEnvelope) throws {
        let data = try JSONEncoder().encode(context)
        let url = runtimeDirectory.appendingPathComponent("context.json")
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func sendCommand(
        type: String,
        fields: [String: Any] = [:],
        timeoutSeconds: UInt64
    ) async throws -> PiRPCResponse {
        guard let inputHandle, process?.isRunning == true else {
            throw PiAgentRuntimeError.unavailable
        }

        let id = UUID().uuidString.lowercased()
        var object = fields
        object["id"] = id
        object["type"] = type
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        trace("send type=\(type) id=\(id)")

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    } catch {
                        return
                    }
                    await self?.timeoutCommand(id: id, command: type)
                }
                pendingCommands[id] = PendingCommand(continuation: continuation, timeoutTask: timeoutTask)
                do {
                    try inputHandle.write(contentsOf: data)
                } catch {
                    if let pending = pendingCommands.removeValue(forKey: id) {
                        pending.timeoutTask.cancel()
                        pending.continuation.resume(throwing: PiAgentRuntimeError.protocolFailure(error.localizedDescription))
                    }
                }
            }
        }, onCancel: {
            Task { await self.cancelPendingCommand(id: id) }
        })
    }

    private func timeoutCommand(id: String, command: String) {
        guard let pending = pendingCommands.removeValue(forKey: id) else { return }
        trace("timeout type=\(command) id=\(id)")
        pending.continuation.resume(throwing: PiAgentRuntimeError.commandTimedOut(command))
    }

    private func cancelPendingCommand(id: String) {
        guard let pending = pendingCommands.removeValue(forKey: id) else { return }
        pending.timeoutTask.cancel()
        pending.continuation.resume(throwing: PiAgentRuntimeError.cancelled)
    }

    private func waitForRun(id: UUID) async throws -> StudyAgentReply {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard var run = activeRun, run.id == id else {
                    continuation.resume(throwing: PiAgentRuntimeError.cancelled)
                    return
                }
                if let completed = run.completed {
                    activeRun = nil
                    scheduleIdleShutdown()
                    continuation.resume(with: completed)
                } else {
                    run.continuation = continuation
                    activeRun = run
                }
            }
        }, onCancel: {
            Task { await self.cancelRun(id: id) }
        })
    }

    private func readStdout(_ handle: FileHandle) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.trace("stdout reader started")
            var framer = PiJSONLFramer()
            do {
                while !Task.isCancelled {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    let lines = try framer.append(data)
                    for line in lines {
                        await self?.receiveStdoutLine(line)
                    }
                }
                _ = try framer.finish()
            } catch {
                await self?.transportFailed(error)
            }
        }
    }

    private func readStderr(_ handle: FileHandle) -> Task<Void, Never> {
        Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                await self?.appendStderr(data)
            }
        }
    }

    private func receiveStdoutLine(_ line: Data) async {
        let message: PiRPCIncomingMessage
        do {
            message = try PiRPCMessageDecoder.decode(line)
        } catch {
            transportFailed(error)
            return
        }

        switch message {
        case let .response(response):
            guard let id = response.id, let pending = pendingCommands.removeValue(forKey: id) else {
                if response.command == "parse" {
                    transportFailed(PiAgentRuntimeError.protocolFailure(response.error ?? "PI parse error"))
                }
                return
            }
            pending.timeoutTask.cancel()
            if response.success {
                pending.continuation.resume(returning: response)
            } else {
                pending.continuation.resume(
                    throwing: PiAgentRuntimeError.commandRejected(
                        sanitizedDiagnostic(response.error ?? response.command)
                    )
                )
            }

        case let .textDelta(delta):
            guard var run = activeRun else { return }
            guard run.didReadContext else {
                run.answeredBeforeContext = true
                run.lastError = "PI answered before reading the current WeiBei context"
                activeRun = run
                return
            }
            run.streamedText += delta
            activeRun = run
            refreshRunWatchdog()
            run.progressDelivery?.yield(.text(run.streamedText))

        case .runActivity:
            refreshRunWatchdog()

        case let .assistantError(message):
            guard var run = activeRun else { return }
            run.lastError = sanitizedDiagnostic(message)
            activeRun = run
            refreshRunWatchdog()

        case let .toolStarted(_, name):
            guard var run = activeRun else { return }
            trace("tool started name=\(name)")
            run.toolTrace.append(name)
            activeRun = run
            guard Set(Self.allowedToolNames).contains(name) else {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI attempted an unavailable tool: \(name)"))
                )
                return
            }
            refreshRunWatchdog()
            run.progressDelivery?.yield(.usingTool(name))

        case let .contextRead(_, contextRevision):
            guard var run = activeRun else { return }
            guard contextRevision == run.contextRevision else {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI read a stale WeiBei context"))
                )
                return
            }
            run.didReadContext = true
            activeRun = run
            trace("context read revision matched")
            refreshRunWatchdog()

        case let .courseSourcesRead(_, contextRevision, labels, assetIDs, jumpEvidence):
            guard var run = activeRun, contextRevision == run.contextRevision else { return }
            run.allowedSourceLabels.formUnion(labels)
            run.allowedNoteSourceLabels.formUnion(labels)
            run.allowedAssetIDs.formUnion(assetIDs)
            run.allowsSourcelessLimitation = run.allowedSourceLabels.isEmpty
            registerJumpEvidence(jumpEvidence, in: &run)
            activeRun = run
            refreshRunWatchdog()

        case let .visualAssetRead(_, contextRevision, assetID, sha256, byteCount):
            guard var run = activeRun,
                  contextRevision == run.contextRevision,
                  run.allowedAssetIDs.contains(assetID) else { return }
            run.toolTrace.append(
                "weibei_visual_asset:asset=\(assetID) sha256=\(sha256.prefix(12)) bytes=\(byteCount)"
            )
            activeRun = run
            refreshRunWatchdog()

        case let .learningMemoryRead(_, contextRevision, memoryRevision, labels, jumpEvidence):
            guard var run = activeRun,
                  contextRevision == run.contextRevision,
                  memoryRevision == run.memoryRevision else { return }
            run.allowedLearningLabels = Set(labels)
            registerJumpEvidence(jumpEvidence, in: &run)
            if labels.contains("[学习记录：上次位置]"),
               let lastLocationSourceLabel = run.lastLocationSourceLabel {
                run.allowedSourceLabels.insert(lastLocationSourceLabel)
                run.allowsSourcelessLimitation = false
            }
            activeRun = run
            refreshRunWatchdog()

        case let .skillsLoaded(_, contextRevision, skills):
            guard var run = activeRun,
                  contextRevision == run.contextRevision,
                  skills.allSatisfy({ $0.loadedAtContextRevision == run.contextRevision }) else { return }
            for skill in skills {
                if let index = run.loadedSkills.firstIndex(where: { $0.id == skill.id }) {
                    run.loadedSkills[index] = skill
                } else {
                    run.loadedSkills.append(skill)
                }
                run.toolTrace.append(
                    "skill-read:\(skill.id)@\(skill.version)#\(skill.sha256.prefix(12))"
                )
            }
            activeRun = run
            refreshRunWatchdog()

        case let .artifactComputed(
            _,
            contextRevision,
            requestID,
            operation,
            workerVersion,
            requestSHA256,
            outputSHA256,
            artifactSHA256s,
            durationMS
        ):
            guard var run = activeRun, contextRevision == run.contextRevision else { return }
            let artifacts = artifactSHA256s
                .map { String($0.prefix(12)) }
                .joined(separator: "+")
            run.toolTrace.append(
                "weibei_compute_artifact:request=\(requestID) operation=\(operation) worker=\(workerVersion) requestSHA=\(requestSHA256.prefix(12)) outputSHA=\(outputSHA256.prefix(12)) artifacts=\(artifacts) durationMS=\(durationMS)"
            )
            activeRun = run
            refreshRunWatchdog()

        case let .richAnswer(_, data):
            guard var run = activeRun else { return }
            trace("rich answer received bytes=\(data.count)")
            guard run.workflow != .noteMaking else {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI proposed a rich answer inside the note-making workflow"))
                )
                return
            }
            if run.answerFormPolicy == .textOnly {
                trace("rich answer rejected by text-only answer-form policy")
                run.toolTrace.append("weibei_rich_answer:host_rejected=text_only_policy")
                run.lastError = "PI 尝试在纯文本回合生成富回答"
                run.richAnswer = nil
                activeRun = run
                refreshRunWatchdog()
                return
            }
            let presentation = RichAnswerEngine.prepare(
                data: data,
                fallbackText: run.streamedText,
                environment: RichAnswerEnvironment(
                    contextRevision: run.contextRevision,
                    allowedSourceLabels: run.allowedSourceLabels,
                    allowedAssetIDs: run.allowedAssetIDs
                )
            ).resolvingAssetIDs(using: run.persistentAssetIDsByContextID)
            if presentation.mode == .rich {
                run.richAnswer = presentation
            } else {
                let rejectionDetails = presentation.diagnostics.map {
                    "\($0.code.rawValue):\($0.message)"
                }.joined(separator: " | ")
                trace("rich answer rejected diagnostics=\(rejectionDetails)")
                run.toolTrace.append(
                    "weibei_rich_answer:host_rejected=\(sanitizedDiagnostic(rejectionDetails).prefix(600))"
                )
                run.lastError = "PI 返回的可视化结果未通过本地安全与来源校验"
                run.richAnswer = nil
            }
            activeRun = run
            refreshRunWatchdog()

        case let .noteProposal(_, proposal):
            guard var run = activeRun else { return }
            guard run.workflow == .noteMaking else {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI proposed a note outside the note-making workflow"))
                )
                return
            }
            guard proposal.contextRevision == run.contextRevision else {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI proposed a note for a stale context"))
                )
                return
            }
            guard !proposal.evidence.isEmpty,
                  proposal.evidence.allSatisfy({ evidence in
                      run.allowedNoteSourceLabels.contains(where: { evidence.hasPrefix($0) })
                  }) else {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI returned a note proposal without current-source evidence"))
                )
                return
            }
            run.proposal = proposal
            activeRun = run
            refreshRunWatchdog()

        case let .learningUpdate(_, update):
            guard var run = activeRun else { return }
            guard update.contextRevision == run.contextRevision,
                  update.memoryRevision == run.memoryRevision else {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI proposed a stale learning-memory update"))
                )
                return
            }
            if let validationError = learningUpdateValidationError(update, run: run) {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed(validationError))
                )
                return
            }
            run.learningUpdate = update
            activeRun = run
            refreshRunWatchdog()

        case let .toolFailed(_, name, message):
            guard var run = activeRun else { return }
            trace("tool failed name=\(name) message=\(sanitizedDiagnostic(message))")
            if name == "weibei_rich_answer",
               let faultTrace = richAnswerFaultTrace(message) {
                run.toolTrace.append(faultTrace)
            }
            run.lastError = name == "weibei_rich_answer"
                ? "PI 模型未完成本轮回答"
                : "\(name): \(boundedDiagnostic(message))"
            activeRun = run
            refreshRunWatchdog()

        case let .agentEnded(text, stopReason, modelError, provider, model):
            guard let run = activeRun else { return }
            var replyTrace = run.toolTrace
            if let provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
                replyTrace.append("provider=\(provider)")
            }
            if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                replyTrace.append("model=\(model)")
            }
            let modelClosureText = (text.isEmpty ? run.streamedText : text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let richNarrative = run.richAnswer?.narrative
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let finalText: String
            if let richNarrative, !richNarrative.isEmpty {
                finalText = richNarrative
            } else {
                finalText = modelClosureText
            }
            trace(
                "agent ended stop=\(stopReason ?? "unknown") closureChars=\(modelClosureText.count) "
                    + "finalChars=\(finalText.count) rich=\(run.richAnswer?.mode == .rich)"
            )
            let replyCandidate = StudyAgentReply(
                text: finalText,
                backend: .pi,
                richAnswer: run.richAnswer,
                noteProposal: run.proposal,
                learningUpdate: run.learningUpdate,
                loadedSkills: run.loadedSkills,
                toolTrace: replyTrace
            )
            if stopReason == "aborted" {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.cancelled))
            } else if stopReason == "error" {
                let detail = modelError.map(userFacingFailureDetail)
                    ?? run.lastError
                    ?? "PI 模型请求失败，但运行时没有返回错误详情"
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed(detail)))
            } else if run.answeredBeforeContext {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed("PI answered before reading the current WeiBei context")))
            } else if !run.didReadContext {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed("PI did not read the current WeiBei context")))
            } else if run.workflow == .noteMaking, run.proposal == nil {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed("PI returned no revision-matched note proposal")))
            } else if run.workflow != .noteMaking,
                      let validationError = answerValidationError(text: finalText, run: run) {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRejectedReplyError(reason: validationError, reply: replyCandidate))
                )
            } else if finalText.isEmpty, let proposal = run.proposal {
                finishRun(
                    id: run.id,
                    with: .success(
                        StudyAgentReply(
                            text: proposal.markdown,
                            backend: .pi,
                            richAnswer: run.richAnswer,
                            noteProposal: proposal,
                            learningUpdate: run.learningUpdate,
                            loadedSkills: run.loadedSkills,
                            toolTrace: replyTrace
                        )
                    )
                )
            } else if finalText.isEmpty {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed(run.lastError ?? "PI returned no readable text")))
            } else {
                finishRun(
                    id: run.id,
                    with: .success(
                        replyCandidate
                    )
                )
            }

        case let .extensionError(message):
            let message = userFacingFailureDetail(message)
            if let runID = activeRun?.id {
                finishRun(id: runID, with: .failure(PiAgentRuntimeError.agentFailed(message)))
            } else {
                startupFailure = .launchFailed(message)
            }

        case .event:
            break
        }
    }

    private func finishRun(id: UUID, with result: Result<StudyAgentReply, Error>) {
        guard var run = activeRun, run.id == id, run.completed == nil else { return }
        run.watchdogTask?.cancel()
        run.watchdogTask = nil
        run.progressDelivery?.finish()
        if let continuation = run.continuation {
            activeRun = nil
            continuation.resume(with: result)
            scheduleIdleShutdown()
        } else {
            run.completed = result
            activeRun = run
        }
    }

    private func richAnswerFaultTrace(_ message: String) -> String? {
        guard message.contains("weibei.rich_answer.repair_fault"),
              let start = message.firstIndex(of: "{") else {
            return nil
        }
        let json = String(message[start...])
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "weibei.rich_answer.repair_fault",
              let code = object["code"] as? String else {
            return "weibei_rich_answer:repair_fault=unparsed"
        }
        let path = (object["jsonPath"] as? String) ?? "$"
        let remainingAttempts = (object["remainingAttempts"] as? NSNumber)?.intValue ?? -1
        let reason = sanitizedDiagnostic((object["message"] as? String) ?? "unknown")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let hint = sanitizedDiagnostic((object["humanFixHint"] as? String) ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return "weibei_rich_answer:repair_fault=\(code):path=\(path):remaining=\(remainingAttempts):reason=\(reason.prefix(240)):hint=\(hint.prefix(240))"
    }

    private func discardRun(id: UUID) {
        guard let run = activeRun, run.id == id else { return }
        run.watchdogTask?.cancel()
        run.progressDelivery?.finish()
        activeRun = nil
        scheduleIdleShutdown()
    }

    private func clearContextSnapshot() {
        let url = runtimeDirectory.appendingPathComponent("context.json")
        try? FileManager.default.removeItem(at: url)
    }

    private func verifyRequiredSkills(in response: PiRPCResponse) throws {
        guard let data = response.dataJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commands = object["commands"] as? [[String: Any]] else {
            throw PiAgentRuntimeError.protocolFailure("get_commands returned no command list")
        }
        let commandNames = Set(commands.compactMap { $0["name"] as? String })
        let missing = PiAgentResources.allRequiredSkillNames.filter {
            !commandNames.contains("skill:\($0)")
        }
        guard missing.isEmpty else {
            throw PiAgentRuntimeError.resourcesMissing("Missing PI skills: \(missing.joined(separator: ", "))")
        }
    }

    private func refreshRunWatchdog() {
        guard var run = activeRun else { return }
        run.watchdogTask?.cancel()
        let runID = run.id
        let inactivityTimeoutNanoseconds = runInactivityTimeoutNanoseconds
        run.watchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: inactivityTimeoutNanoseconds)
            } catch {
                return
            }
            await self?.runTimedOut(id: runID)
        }
        activeRun = run
    }

    private func runTimedOut(id: UUID) async {
        guard activeRun?.id == id else { return }
        finishRun(id: id, with: .failure(PiAgentRuntimeError.commandTimedOut("prompt")))
        do {
            _ = try await sendCommand(type: "abort", timeoutSeconds: 2)
        } catch {
            shutdownProcess(reason: error)
        }
    }

    private func scheduleIdleShutdown() {
        idleShutdownTask?.cancel()
        idleShutdownTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            } catch {
                return
            }
            await self?.shutdownIfIdle()
        }
    }

    private func shutdownIfIdle() {
        guard activeRun == nil else { return }
        shutdownProcess(reason: PiAgentRuntimeError.cancelled)
    }

    private func appendStderr(_ data: Data) {
        let text = sanitizedDiagnostic(String(decoding: data, as: UTF8.self))
        stderrBuffer += text
        trace("stderr bytes=\(data.count)")
        if stderrBuffer.count > 16_384 {
            stderrBuffer = String(stderrBuffer.suffix(16_384))
        }
    }

    private func transportFailed(_ error: Error) {
        shutdownProcess(reason: PiAgentRuntimeError.protocolFailure(error.localizedDescription))
    }

    private func processDidTerminate(pid: Int32, status: Int32) {
        guard process?.processIdentifier == pid else { return }
        let detail = stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = detail.isEmpty ? "exit status \(status)" : String(detail.suffix(2_048))
        shutdownProcess(reason: PiAgentRuntimeError.launchFailed(message))
    }

    private func sanitizedDiagnostic(_ value: String) -> String {
        PiAgentDiagnosticSanitizer.sanitize(value, secret: providerConfiguration.apiKey)
    }

    private func boundedDiagnostic(_ value: String, limit: Int = 1_024) -> String {
        String(sanitizedDiagnostic(value).prefix(limit))
    }

    private func userFacingFailureDetail(_ value: String) -> String {
        let sanitized = sanitizedDiagnostic(value)
        if sanitized.contains("weibei.rich_answer.repair_fault")
            || sanitized.contains("repair_fault")
            || sanitized.contains("RichAnswerUI")
            || sanitized.contains("payload") {
            return "PI 模型未完成本轮回答"
        }
        return String(sanitized.prefix(1_024))
    }

    private func shutdownProcess(reason: Error) {
        trace("shutdown: \(reason.localizedDescription)")
        clearContextSnapshot()
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        let runningProcess = process
        process = nil
        try? inputHandle?.close()
        inputHandle = nil
        if let processToStop = runningProcess, processToStop.isRunning {
            processToStop.terminate()
            Task.detached(priority: .utility) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if processToStop.isRunning {
                    Darwin.kill(processToStop.processIdentifier, SIGKILL)
                }
            }
        }

        for pending in pendingCommands.values {
            pending.timeoutTask.cancel()
            pending.continuation.resume(throwing: reason)
        }
        pendingCommands.removeAll()

        if let runID = activeRun?.id {
            let activeReason: Error
            if reason is CancellationError || (reason as? PiAgentRuntimeError) == .cancelled {
                activeReason = PiAgentRuntimeError.cancelled
            } else if let error = reason as? PiAgentRuntimeError,
                      case .inFlightFailed = error {
                activeReason = error
            } else {
                activeReason = PiAgentRuntimeError.inFlightFailed(reason.localizedDescription)
            }
            finishRun(id: runID, with: .failure(activeReason))
        }
    }

    private func forceStopIfNeeded(_ process: Process?, graceNanoseconds: UInt64) async {
        guard let process, process.isRunning else { return }
        let interval = UInt64(50_000_000)
        var waited: UInt64 = 0
        while process.isRunning, waited < graceNanoseconds {
            try? await Task.sleep(nanoseconds: interval)
            waited += interval
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    private func trace(_ message: String) {
        guard traceEnabled else { return }
        FileHandle.standardError.write(Data("[WeiBei PI] \(sanitizedDiagnostic(message))\n".utf8))
    }
}
