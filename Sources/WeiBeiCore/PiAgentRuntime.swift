import Darwin
import CryptoKit
import Foundation
import Security

public struct PiAgentProviderConfiguration: Equatable, Sendable {
    public var provider: String?
    public var model: String?
    public var apiKey: String?
    public var baseURL: String?
    public var thinkingLevel: String

    public init(
        provider: String? = nil,
        model: String? = nil,
        apiKey: String? = nil,
        baseURL: String? = nil,
        thinkingLevel: String = "medium"
    ) {
        self.provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.thinkingLevel = thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "medium"
            : thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PiAgentResources: Sendable {
    public static let requiredRichAnswerSkillNames = [
        "rich-answer-director",
        "professional-visualization",
        "deep-interaction-components",
        "generative-composition",
    ]
    public static var allRequiredSkillNames: [String] {
        requiredRichAnswerSkillNames
    }

    public var rootURL: URL
    public var extensionURL: URL
    public var pythonArtifactWorkerURL: URL
    public var skillsURL: URL
    public var systemPrompt: String

    public static func bundled() throws -> PiAgentResources {
        let bundleName = "WeiBei_WeiBeiCore.bundle"
        let packagedBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent(bundleName) }
            .flatMap(Bundle.init(url:))
        let legacyBundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent(bundleName))
        let resourceBundle = packagedBundle ?? legacyBundle ?? Bundle.module
        guard let rootURL = resourceBundle.url(forResource: "AgentResources", withExtension: nil) else {
            throw PiAgentRuntimeError.resourcesMissing("AgentResources")
        }
        let extensionURL = rootURL.appendingPathComponent("extension.ts")
        let pythonArtifactWorkerURL = rootURL
            .appendingPathComponent("python", isDirectory: true)
            .appendingPathComponent("rich_answer_worker.py")
        let skillsURL = rootURL.appendingPathComponent("skills", isDirectory: true)
        let systemURL = rootURL.appendingPathComponent("system.md")
        let hasRequiredRichAnswerSkills = requiredRichAnswerSkillNames.allSatisfy { skillName in
            FileManager.default.fileExists(
                atPath: skillsURL
                    .appendingPathComponent("rich-answer", isDirectory: true)
                    .appendingPathComponent(skillName, isDirectory: true)
                    .appendingPathComponent("SKILL.md")
                    .path
            )
        }
        guard FileManager.default.fileExists(atPath: extensionURL.path),
              FileManager.default.fileExists(atPath: pythonArtifactWorkerURL.path),
              hasRequiredRichAnswerSkills,
              let systemPrompt = try? String(contentsOf: systemURL, encoding: .utf8),
              !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PiAgentRuntimeError.resourcesMissing(rootURL.path)
        }
        return PiAgentResources(
            rootURL: rootURL,
            extensionURL: extensionURL,
            pythonArtifactWorkerURL: pythonArtifactWorkerURL,
            skillsURL: skillsURL,
            systemPrompt: systemPrompt
        )
    }
}

public struct PiRuntimeManifest: Decodable, Equatable, Sendable {
    public var schemaVersion: Int
    public var piVersion: String
    public var sourceRepository: String
    public var sourceCommit: String
    public var license: String
    /// `"node"` for official Node + npm package; omitted/legacy for fixture Mach-O stubs.
    public var runtimeKind: String?
    public var npmPackage: String?

    public var usesNodeRuntime: Bool {
        (runtimeKind ?? "").lowercased() == "node"
    }
}

public enum PiBundledRuntime {
    public static let requiredVersion = "0.82.1"
    public static let requiredNpmPackage = "@earendil-works/pi-coding-agent"

    private struct PackageMetadata: Decodable {
        var version: String
    }

    public static func validate(
        executableURL: URL,
        fileManager: FileManager = .default,
        containingAppURL: URL? = nil
    ) throws -> PiRuntimeManifest {
        let executableURL = executableURL.standardizedFileURL
        let binURL = executableURL.deletingLastPathComponent()
        let runtimeURL = binURL.deletingLastPathComponent()
        let manifestURL = runtimeURL.appendingPathComponent("manifest.json")
        let integrityURL = runtimeURL.appendingPathComponent("binary.sha256")
        let packageURL = binURL.appendingPathComponent("package.json")
        let commonRequired = [
            packageURL,
            binURL.appendingPathComponent("theme/dark.json"),
            binURL.appendingPathComponent("theme/light.json"),
            runtimeURL.appendingPathComponent("LICENSE"),
            runtimeURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"),
            manifestURL,
            integrityURL,
        ]
        guard fileManager.isExecutableFile(atPath: executableURL.path),
              commonRequired.allSatisfy({ fileManager.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PiRuntimeManifest.self, from: data),
              let packageData = try? Data(contentsOf: packageURL),
              let package = try? JSONDecoder().decode(PackageMetadata.self, from: packageData),
              let expectedHashRaw = try? String(contentsOf: integrityURL, encoding: .utf8),
              let expectedHash = expectedHashRaw
                .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                .first
                .map({ String($0).lowercased() }),
              manifest.piVersion == requiredVersion,
              package.version == requiredVersion,
              manifest.license == "MIT",
              !manifest.sourceRepository.isEmpty,
              manifest.sourceCommit.count == 40,
              expectedHash.count == 64,
              expectedHash.allSatisfy(\.isHexDigit)
        else {
            throw PiAgentRuntimeError.resourcesMissing(runtimeURL.path)
        }

        if manifest.usesNodeRuntime {
            guard manifest.schemaVersion == 2,
                  (manifest.npmPackage ?? requiredNpmPackage) == requiredNpmPackage
            else {
                throw PiAgentRuntimeError.resourcesMissing(runtimeURL.path)
            }
            let nodeURL = runtimeURL.appendingPathComponent("node/bin/node")
            let agentCLI = runtimeURL.appendingPathComponent(
                "agent/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
            )
            let agentPackageURL = runtimeURL.appendingPathComponent(
                "agent/node_modules/@earendil-works/pi-coding-agent/package.json"
            )
            guard fileManager.isExecutableFile(atPath: nodeURL.path),
                  fileManager.fileExists(atPath: agentCLI.path),
                  fileManager.fileExists(atPath: agentPackageURL.path),
                  let agentPackageData = try? Data(contentsOf: agentPackageURL),
                  let agentPackage = try? JSONDecoder().decode(PackageMetadata.self, from: agentPackageData),
                  agentPackage.version == requiredVersion,
                  (try? sha256(of: nodeURL)) == expectedHash,
                  hasExpectedArchitecture(nodeURL),
                  hasValidCodeSignature(nodeURL)
            else {
                throw PiAgentRuntimeError.resourcesMissing(runtimeURL.path)
            }
        } else {
            // Legacy / self-check fixture: Mach-O `bin/pi` with schemaVersion 1.
            guard manifest.schemaVersion == 1,
                  (try? sha256(of: executableURL)) == expectedHash,
                  hasExpectedArchitecture(executableURL),
                  hasValidCodeSignature(executableURL)
            else {
                throw PiAgentRuntimeError.resourcesMissing(runtimeURL.path)
            }
        }

        let defaultAppURL = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil
        if let appURL = (containingAppURL ?? defaultAppURL)?.standardizedFileURL,
           executableURL.path.hasPrefix(appURL.path + "/"),
           !hasValidCodeSignature(appURL) {
            throw PiAgentRuntimeError.resourcesMissing(appURL.path)
        }
        return manifest
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hasExpectedArchitecture(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 8) else { return false }
        try? handle.close()
        let bytes = Array(data)
        guard bytes.count == 8, Array(bytes[0..<4]) == [0xcf, 0xfa, 0xed, 0xfe] else { return false }
        #if arch(arm64)
        return Array(bytes[4..<8]) == [0x0c, 0x00, 0x00, 0x01]
        #elseif arch(x86_64)
        return Array(bytes[4..<8]) == [0x07, 0x00, 0x00, 0x01]
        #else
        return false
        #endif
    }

    private static func hasValidCodeSignature(_ url: URL) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return false }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSStrictValidate))
        return SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess
    }
}

public enum PiExecutableLocator {
    public static func locate(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        validator: (URL, FileManager) -> Bool = { candidate, fileManager in
            (try? PiBundledRuntime.validate(executableURL: candidate, fileManager: fileManager)) != nil
        }
    ) -> URL? {
        let candidates = [
            bundleURL.appendingPathComponent("Contents/Resources/PiRuntime/bin/pi"),
            bundleURL.appendingPathComponent("PiRuntime/bin/pi"),
        ]
        return candidates.first { candidate in
            fileManager.isExecutableFile(atPath: candidate.path) && validator(candidate, fileManager)
        }
    }
}

public enum PiAgentRuntimeError: LocalizedError, Equatable, Sendable {
    case unavailable
    case resourcesMissing(String)
    case busy
    case launchFailed(String)
    case commandTimedOut(String)
    case commandRejected(String)
    case protocolFailure(String)
    case agentFailed(String)
    case inFlightFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "魏碑内建的 PI 运行时缺失或损坏，请重新安装应用。"
        case let .resourcesMissing(path):
            return "魏碑的 PI 资源不完整：\(path)"
        case .busy:
            return "PI 正在处理另一项任务"
        case let .launchFailed(message):
            return "PI 启动失败：\(message)"
        case let .commandTimedOut(command):
            return "PI 命令超时：\(command)"
        case let .commandRejected(message):
            return "PI 拒绝命令：\(message)"
        case let .protocolFailure(message):
            return "PI 通信失败：\(message)"
        case let .agentFailed(message):
            return "PI 回答失败：\(message)"
        case let .inFlightFailed(message):
            return "PI 运行中断：\(message)"
        case .cancelled:
            return "PI 请求已取消"
        }
    }

    public var permitsAutomaticFallback: Bool {
        switch self {
        case .unavailable, .resourcesMissing, .busy, .launchFailed, .commandRejected:
            return true
        case let .commandTimedOut(command):
            return command != "prompt" && command != "abort"
        case .protocolFailure:
            return true
        case .agentFailed, .inFlightFailed, .cancelled:
            return false
        }
    }
}

public enum PiAgentDiagnosticSanitizer {
    public static func sanitize(_ value: String, secret: String? = nil) -> String {
        var result = value
        if let secret, !secret.isEmpty {
            result = result.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        let redactions = [
            (#"(?i)bearer\s+[A-Za-z0-9._~+/=-]{8,}"#, "Bearer [REDACTED]"),
            (#"\bsk-[A-Za-z0-9_-]{8,}\b"#, "[REDACTED]"),
            (#"(?i)([\"']?(?:authorization|api[_-]?key|access[_-]?token|secret)[\"']?\s*[:=]\s*[\"']?)([^\s\"',;}]+)"#, "$1[REDACTED]"),
        ]
        for (pattern, replacement) in redactions {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: replacement
            )
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(2_048))
    }
}

public actor PiAgentRuntime: StudyAgentRuntime {
    private static let processReadinessTimeoutSeconds: UInt64 = 12
    private static let sharedToolNames = [
        "weibei_context",
        "weibei_course_map",
        "weibei_course_search",
        "weibei_course_read",
        "weibei_visual_asset",
        "weibei_learning_memory",
        "weibei_learning_update",
        // Global Chat keeps read only for registered Skills; project paths remain unavailable.
        "read",
        "weibei_note_proposal",
        "weibei_relation_proposal",
        "weibei_ui_catalog",
        "weibei_compute_artifact",
        "weibei_rich_answer",
    ]
    private static let courseProjectToolNames = ["ls", "find", "grep"]
    private static let hostToolNames: Set<String> = [
        "weibei_course_search",
        "weibei_course_read",
        "grep",
    ]

    private static func allowedToolNames(
        for scope: StudyAgentScopeKind
    ) -> [String] {
        sharedToolNames + (scope == .course ? courseProjectToolNames : [])
    }

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

    private struct HostToolResponseEnvelope: Encodable {
        var schemaVersion = 1
        var requestID: String
        var contextRevision: String
        var toolCallID: String
        var toolName: String
        var success: Bool
        var payload: StudyAgentHostToolResult?
        var error: String?
    }

    private struct ProcessBinding: Equatable {
        var sessionID: UUID
        var workingDirectory: URL
        var sessionDirectory: URL
        var scope: StudyAgentScopeKind
    }

    private struct PiSessionState {
        var messageCount: Int
    }

    private struct PiSessionStateFailure: Error {
        var message: String
        var repairsEmptySession: Bool
    }

    private struct ActiveRun {
        var id: UUID
        var contextRevision: String
        var memoryRevision: UInt64
        var userQuestion: String
        var answerFormPolicy: StudyAgentAnswerFormPolicy
        var updatableMemoryIDs: Set<String>
        var resolvableMemoryIDs: Set<String>
        var allowedSourceLabels: Set<String>
        var allowedAssetIDs: Set<String>
        var verifiedAssetBytesByContextID: [String: Int] = [:]
        var persistentAssetIDsByContextID: [String: String]
        var allowedJumpReferences: Set<String>
        var jumpEvidenceLabels: [String: Set<String>]
        var allowedLearningLabels: Set<String> = []
        var lastLocationSourceLabel: String?
        var allowedNoteSourceLabels: Set<String>
        var contextSources: [AgentReplySource]
        var sources: [AgentReplySource] = []
        var streamedText = ""
        var proposal: StudyAgentNoteProposal?
        var relationProposal: StudyAgentRelationProposal?
        var richAnswer: RichAnswerPresentation?
        var safeRichAnswerNarrative: String?
        var learningUpdate: StudyAgentLearningUpdate?
        var loadedSkills: [StudyAgentLoadedSkill] = []
        var toolTrace: [String] = []
        var allowedToolNames: Set<String>
        var allowsRelationProposal: Bool
        var courseCatalogRolesByContextID: [String: String]
        var existingCourseRelations: Set<StudyAgentCourseRelation>
        var hostToolHandler: StudyAgentHostToolHandler?
        var hostToolCallIDs: Set<String> = []
        var nextDynamicAssetOrdinal: Int
        var lastError: String?
        var progressDelivery: ProgressDelivery?
        var continuation: CheckedContinuation<StudyAgentReply, Error>?
        var completed: Result<StudyAgentReply, Error>?
        var watchdogTask: Task<Void, Never>?
    }

    private let executableOverride: URL?
    private let runtimeDirectory: URL
    private let fallbackSessionID = UUID()
    private let runInactivityTimeoutNanoseconds: UInt64
    private var providerConfiguration = PiAgentProviderConfiguration()
    private var process: Process?
    private var processBinding: ProcessBinding?
    private var inputHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var processGeneration: UInt64 = 0
    private var pendingCommands: [String: PendingCommand] = [:]
    private var activeRun: ActiveRun?
    private var hostToolTasks: [String: Task<Void, Never>] = [:]
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
        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true
        )
        _ = try await ensureProcess(
            binding: try makeProcessBinding(
                sessionID: fallbackSessionID,
                workingDirectory: runtimeDirectory,
                scope: .global
            )
        )
        return process?.executableURL?.path ?? "pi"
    }

    public func respond(to request: StudyAgentRequest, progress: StudyAgentProgressHandler?) async throws -> StudyAgentReply {
        try await respond(
            to: request,
            sessionID: request.id,
            workingDirectory: runtimeDirectory,
            progress: progress
        )
    }

    public func respond(
        to request: StudyAgentRequest,
        sessionID: UUID,
        workingDirectory: URL,
        hostToolHandler: StudyAgentHostToolHandler? = nil,
        progress: StudyAgentProgressHandler?
    ) async throws -> StudyAgentReply {
        var request = request
        if request.projectScope.chatID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            request.projectScope.chatID = sessionID.uuidString.lowercased()
        }
        if request.focus?.chatID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == true {
            request.focus?.chatID = request.projectScope.chatID
        }
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
        let binding = try makeProcessBinding(
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            scope: request.projectScope.kind
        )
        var startupState: PiSessionState?
        var needsHistoryRecovery = false
        let hadStoredSession = sessionDirectoryHasContents(binding.sessionDirectory)
        do {
            startupState = try await ensureProcess(binding: binding)
        } catch let failure as PiSessionStateFailure {
            guard failure.repairsEmptySession || hadStoredSession else {
                throw PiAgentRuntimeError.protocolFailure(failure.message)
            }
            try await resetSession(binding: binding)
            needsHistoryRecovery = true
            do {
                startupState = try await ensureProcess(binding: binding)
            } catch let secondFailure as PiSessionStateFailure {
                throw PiAgentRuntimeError.protocolFailure(secondFailure.message)
            }
            guard startupState?.messageCount == 0 else {
                throw PiAgentRuntimeError.protocolFailure(
                    "rebuilt PI session did not start empty"
                )
            }
        }
        if startupState?.messageCount == 0, !request.recentMessages.isEmpty {
            needsHistoryRecovery = true
        }
        try requireStartingRun(request.id)

        var contextRequest = request
        if !needsHistoryRecovery {
            contextRequest.recentMessages = []
        }
        let context = StudyAgentContextEnvelope(request: contextRequest)
        try writeContext(context)
        try prepareHostToolResponseDirectory(for: request.id)
        let progressDelivery = progress.map(ProgressDelivery.init(handler:))

        let currentJumpEvidence = currentJumpEvidence(in: context)
        let currentSourceLabels = currentSourceLabels(in: context)
        activeRun = ActiveRun(
            id: request.id,
            contextRevision: request.contextRevision,
            memoryRevision: request.learningContext.memoryRevision,
            userQuestion: request.question,
            answerFormPolicy: request.answerFormPolicy,
            updatableMemoryIDs: Set(request.learningContext.memories.compactMap { memory in
                guard memory.status == .active else { return nil }
                return memory.id.uuidString.lowercased()
            }),
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
            contextSources: currentReplySources(request: request, context: context),
            allowedToolNames: Set(Self.allowedToolNames(for: binding.scope)),
            allowsRelationProposal: binding.scope == .course,
            courseCatalogRolesByContextID: context.course.catalog.reduce(into: [:]) {
                $0[$1.id] = $1.role
            },
            existingCourseRelations: Set(context.course.relations),
            hostToolHandler: hostToolHandler,
            nextDynamicAssetOrdinal: context.course.catalog.count + 1,
            progressDelivery: progressDelivery
        )
        progressDelivery?.yield(.preparing)
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

        let reply = try await waitForRun(id: request.id)
        // PI emits agent_end before every post-turn hook is guaranteed to be flushed.
        // An ordered state read gives those hooks a chance to finish before the
        // process boundary prevents late events from entering the next turn.
        _ = try? await readSessionState(binding: binding)
        let completedProcess = process
        shutdownProcess(reason: PiAgentRuntimeError.cancelled)
        await forceStopIfNeeded(completedProcess, graceNanoseconds: 750_000_000)
        return reply
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

    public func deleteSession(_ sessionID: UUID) async throws {
        if processBinding?.sessionID == sessionID,
           let runningProcess = process,
           runningProcess.isRunning {
            shutdownProcess(reason: PiAgentRuntimeError.cancelled)
            await forceStopIfNeeded(runningProcess, graceNanoseconds: 750_000_000)
        }
        try removeSessionDirectory(sessionDirectory(for: sessionID))
    }

    private func makeProcessBinding(
        sessionID: UUID,
        workingDirectory: URL,
        scope: StudyAgentScopeKind
    ) throws -> ProcessBinding {
        let resolvedWorkingDirectory = workingDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: resolvedWorkingDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw PiAgentRuntimeError.launchFailed(
                "工作目录当前不可用：\(resolvedWorkingDirectory.path)"
            )
        }
        let sessionDirectory = sessionDirectory(for: sessionID)
        return ProcessBinding(
            sessionID: sessionID,
            workingDirectory: resolvedWorkingDirectory,
            sessionDirectory: sessionDirectory,
            scope: scope
        )
    }

    private func ensureProcess(binding: ProcessBinding) async throws -> PiSessionState? {
        if let process, process.isRunning, processBinding == binding {
            return try await readSessionState(binding: binding)
        }
        if let runningProcess = process, runningProcess.isRunning {
            shutdownProcess(reason: PiAgentRuntimeError.cancelled)
            await forceStopIfNeeded(runningProcess, graceNanoseconds: 750_000_000)
        }

        let executableURL = executableOverride ?? PiExecutableLocator.locate()
        guard let executableURL else { throw PiAgentRuntimeError.unavailable }
        _ = try PiBundledRuntime.validate(executableURL: executableURL)
        let resources = try PiAgentResources.bundled()
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeDirectory.path)
        let piConfigurationURL = try preparePiConfigurationDirectory()
        try FileManager.default.createDirectory(
            at: binding.sessionDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: binding.sessionDirectory.path
        )

        let contextURL = runtimeDirectory.appendingPathComponent("context.json")
        let process = Process()
        processGeneration &+= 1
        let generation = processGeneration
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        let launch = Self.resolveLaunch(executableURL: executableURL)
        process.executableURL = launch.executableURL
        process.currentDirectoryURL = binding.workingDirectory
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.arguments = launch.argumentPrefix + launchArguments(resources: resources, binding: binding)
        process.environment = launchEnvironment(
            executableURL: executableURL,
            packageDirectoryURL: launch.packageDirectoryURL,
            contextURL: contextURL,
            piConfigurationURL: piConfigurationURL,
            sessionDirectory: binding.sessionDirectory
        )
        process.terminationHandler = { [weak self] terminated in
            Task {
                await self?.processDidTerminate(
                    pid: terminated.processIdentifier,
                    status: terminated.terminationStatus,
                    generation: generation
                )
            }
        }

        stderrBuffer = ""
        startupFailure = nil
        self.process = process
        processBinding = binding
        inputHandle = inputPipe.fileHandleForWriting

        do {
            try process.run()
            trace("launched pid=\(process.processIdentifier) executable=\(executableURL.path)")
        } catch {
            self.process = nil
            processBinding = nil
            inputHandle = nil
            throw PiAgentRuntimeError.launchFailed(error.localizedDescription)
        }

        stdoutTask = readStdout(outputPipe.fileHandleForReading, generation: generation)
        stderrTask = readStderr(errorPipe.fileHandleForReading, generation: generation)

        do {
            let sessionState = try await readSessionState(binding: binding)
            let commands = try await sendCommand(
                type: "get_commands",
                timeoutSeconds: Self.processReadinessTimeoutSeconds
            )
            try verifyRequiredSkills(in: commands)
            if let startupFailure { throw startupFailure }
            return sessionState
        } catch {
            shutdownProcess(reason: error)
            throw error
        }
    }

    private func readSessionState(binding: ProcessBinding) async throws -> PiSessionState {
        let state: PiRPCResponse
        do {
            state = try await sendCommand(
                type: "get_state",
                timeoutSeconds: Self.processReadinessTimeoutSeconds
            )
        } catch {
            throw PiSessionStateFailure(
                message: "could not read the requested Chat session: \(error.localizedDescription)",
                repairsEmptySession: false
            )
        }
        return try validatedSessionState(state, binding: binding)
    }

    private func validatedSessionState(
        _ response: PiRPCResponse,
        binding: ProcessBinding
    ) throws -> PiSessionState {
        guard let data = response.dataJSON,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["sessionId"] as? String,
              sessionID.lowercased() == binding.sessionID.uuidString.lowercased(),
              let messageCount = (object["messageCount"] as? NSNumber)?.intValue,
              messageCount >= 0,
              let sessionFile = object["sessionFile"] as? String else {
            throw PiSessionStateFailure(
                message: "get_state did not match the requested Chat session",
                repairsEmptySession: true
            )
        }
        let sessionFileURL = URL(fileURLWithPath: sessionFile).standardizedFileURL
        guard sessionFileURL.deletingLastPathComponent().path
                == binding.sessionDirectory.standardizedFileURL.path else {
            throw PiSessionStateFailure(
                message: "get_state returned a session outside the requested Chat directory",
                repairsEmptySession: true
            )
        }
        return PiSessionState(messageCount: messageCount)
    }

    private func resetSession(binding: ProcessBinding) async throws {
        if let runningProcess = process, runningProcess.isRunning {
            shutdownProcess(reason: PiAgentRuntimeError.cancelled)
            await forceStopIfNeeded(runningProcess, graceNanoseconds: 750_000_000)
        }
        try removeSessionDirectory(binding.sessionDirectory)
    }

    private func sessionDirectory(for sessionID: UUID) -> URL {
        runtimeDirectory
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    }

    private var hostToolResponseRoot: URL {
        runtimeDirectory.appendingPathComponent("ToolResponses", isDirectory: true)
    }

    private func hostToolResponseDirectory(for requestID: UUID) -> URL {
        hostToolResponseRoot.appendingPathComponent(
            requestID.uuidString.lowercased(),
            isDirectory: true
        )
    }

    private func prepareHostToolResponseDirectory(for requestID: UUID) throws {
        let fileManager = FileManager.default
        var rootStat = Darwin.stat()
        let rootExists = hostToolResponseRoot.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.lstat($0, &rootStat) == 0 } ?? false
        }
        if rootExists {
            guard (rootStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw PiAgentRuntimeError.protocolFailure(
                    "课程工具响应目录不是安全的本地目录"
                )
            }
        } else {
            guard errno == ENOENT else {
                throw PiAgentRuntimeError.protocolFailure(
                    "无法检查课程工具响应目录"
                )
            }
            try fileManager.createDirectory(
                at: hostToolResponseRoot,
                withIntermediateDirectories: false
            )
            guard hostToolResponseRoot.withUnsafeFileSystemRepresentation({ path in
                path.map { Darwin.lstat($0, &rootStat) == 0 } ?? false
            }),
            (rootStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw PiAgentRuntimeError.protocolFailure(
                    "课程工具响应目录创建后身份异常"
                )
            }
        }
        let canonicalRuntimeDirectory = runtimeDirectory
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let canonicalResponseRoot = hostToolResponseRoot
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard canonicalResponseRoot.deletingLastPathComponent()
                == canonicalRuntimeDirectory else {
            throw PiAgentRuntimeError.protocolFailure(
                "课程工具响应目录离开了运行时目录"
            )
        }
        let rootDevice = rootStat.st_dev
        let rootFileID = rootStat.st_ino
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: hostToolResponseRoot.path
        )
        let staleDirectories = try fileManager.contentsOfDirectory(
            at: hostToolResponseRoot,
            includingPropertiesForKeys: nil
        )
        for staleDirectory in staleDirectories
        where UUID(uuidString: staleDirectory.lastPathComponent) != nil {
            var currentRootStat = Darwin.stat()
            guard staleDirectory.deletingLastPathComponent().standardizedFileURL
                    == hostToolResponseRoot.standardizedFileURL,
                  hostToolResponseRoot.withUnsafeFileSystemRepresentation({ path in
                      path.map { Darwin.lstat($0, &currentRootStat) == 0 } ?? false
                  }),
                  currentRootStat.st_dev == rootDevice,
                  currentRootStat.st_ino == rootFileID,
                  (currentRootStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw PiAgentRuntimeError.protocolFailure(
                    "课程工具响应目录在清理期间发生了变化"
                )
            }
            try fileManager.removeItem(at: staleDirectory)
        }
        let directory = hostToolResponseDirectory(for: requestID)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    private func removeHostToolResponseDirectory(for requestID: UUID) {
        let directory = hostToolResponseDirectory(for: requestID)
        guard directory.deletingLastPathComponent().standardizedFileURL
                == hostToolResponseRoot.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func sessionDirectoryHasContents(_ sessionDirectory: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sessionDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return false
        }
        return !contents.isEmpty
    }

    private func removeSessionDirectory(_ sessionDirectory: URL) throws {
        let sessionsRoot = runtimeDirectory
            .appendingPathComponent("Sessions", isDirectory: true)
            .standardizedFileURL
        guard sessionDirectory.standardizedFileURL
                .deletingLastPathComponent().path == sessionsRoot.path else {
            throw PiAgentRuntimeError.protocolFailure(
                "refused to rebuild a session outside WeiBei AgentRuntime"
            )
        }
        if FileManager.default.fileExists(atPath: sessionDirectory.path) {
            try FileManager.default.removeItem(at: sessionDirectory)
        }
    }

    private func launchArguments(
        resources: PiAgentResources,
        binding: ProcessBinding
    ) -> [String] {
        var arguments = [
            "--mode", "rpc",
            "--offline",
            "--session-id", binding.sessionID.uuidString.lowercased(),
            "--session-dir", binding.sessionDirectory.path,
            "--no-builtin-tools",
            "--tools", Self.allowedToolNames(for: binding.scope).joined(separator: ","),
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
        request.question
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

    private func currentReplySources(
        request: StudyAgentRequest,
        context: StudyAgentContextEnvelope
    ) -> [AgentReplySource] {
        var sources: [AgentReplySource] = []
        func append(
            itemID: String?,
            kind: AgentReplySourceKind,
            title: String,
            label: String,
            text: String
        ) {
            let excerpt = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !excerpt.isEmpty else { return }
            let parsed = SourceReferenceTitle.parse(title)
            sources.append(
                AgentReplySource(
                    itemID: itemID,
                    kind: kind,
                    title: parsed.title,
                    label: label,
                    excerpt: String(excerpt.prefix(400)),
                    pageIndex: parsed.pageIndex,
                    sectionTitle: parsed.sectionTitle,
                    sectionLocationID: parsed.sectionLocationID,
                    sectionOrdinal: parsed.sectionOrdinal,
                    courseItemOrdinal: parsed.courseItemOrdinal
                )
            )
        }

        let materialID = context.course.catalog.first(where: \.isCurrentMaterial)?.id
        if let material = context.material {
            append(
                itemID: materialID,
                kind: .material,
                title: material.title,
                label: "[材料：\(material.title)]",
                text: material.text
            )
        }
        let noteID = context.course.catalog.first(where: \.isCurrentNote)?.id
        append(
            itemID: noteID,
            kind: .note,
            title: context.note.title,
            label: "[笔记：\(context.note.title)]",
            text: context.note.text
        )
        sources.append(contentsOf: request.selectionSources)
        return sources
    }

    private func appendSources(_ sources: [AgentReplySource], to run: inout ActiveRun) {
        for candidate in sources {
            var source = candidate
            if let itemID = source.itemID,
               let persistentID = run.persistentAssetIDsByContextID[itemID] {
                source.itemID = persistentID
            }
            let isDuplicate = run.sources.contains {
                $0.itemID == source.itemID
                    && $0.kind == source.kind
                    && $0.pageIndex == source.pageIndex
                    && $0.sectionLocationID == source.sectionLocationID
                    && $0.sectionOrdinal == source.sectionOrdinal
                    && $0.label == source.label
            }
            if !isDuplicate {
                run.sources.append(source)
            }
        }
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

    private func learningUpdateValidationError(
        _ update: StudyAgentLearningUpdate,
        run: ActiveRun
    ) -> String? {
        guard !run.allowedLearningLabels.isEmpty else {
            return "PI proposed a learning-memory update before reading learning memory"
        }
        let targetMemoryIDs = update.entries.compactMap {
            $0.memoryID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard Set(targetMemoryIDs).count == targetMemoryIDs.count else {
            return "PI proposed duplicate learning-memory update targets"
        }
        guard targetMemoryIDs.allSatisfy(run.updatableMemoryIDs.contains) else {
            return "PI proposed a learning-memory update outside the current active scope"
        }
        for entry in update.entries {
            let evidenceIsCurrentTurn = entry.evidence.hasPrefix("[用户：本轮]")
                || entry.evidence.hasPrefix("[会话：当前]")
            if evidenceIsCurrentTurn,
               !StudyAgentCurrentTurnEvidence.matches(
                   entry.evidence,
                   question: run.userQuestion
               ) {
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
        let resolutionMemoryIDs = update.resolutions.map {
            $0.memoryID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        guard Set(resolutionMemoryIDs).count == resolutionMemoryIDs.count else {
            return "PI proposed duplicate learning-memory resolutions"
        }
        guard zip(update.resolutions, resolutionMemoryIDs).allSatisfy({ resolution, memoryID in
            run.resolvableMemoryIDs.contains(memoryID)
                && StudyAgentCurrentTurnEvidence.matches(
                    resolution.evidence,
                    question: run.userQuestion
                )
        }) else {
            return "PI resolved learning memory without current-turn evidence"
        }
        return nil
    }

    private func relationProposalValidationError(
        _ proposal: StudyAgentRelationProposal,
        run: ActiveRun
    ) -> String? {
        guard run.allowsRelationProposal else {
            return "PI proposed a relation outside a course Chat"
        }
        guard proposal.contextRevision == run.contextRevision else {
            return "PI proposed a relation for a stale context"
        }
        guard run.courseCatalogRolesByContextID[proposal.noteItemID] == "note",
              run.courseCatalogRolesByContextID[proposal.sourceItemID] == "material" else {
            return "PI proposed relation targets outside the current course catalog roles"
        }
        guard proposal.noteItemID != proposal.sourceItemID else {
            return "PI proposed a relation with identical targets"
        }
        guard !run.existingCourseRelations.contains(
            StudyAgentCourseRelation(
                noteItemID: proposal.noteItemID,
                sourceItemID: proposal.sourceItemID
            )
        ) else {
            return "PI proposed a relation that already exists"
        }
        guard run.relationProposal == nil else {
            return "PI proposed more than one relation in a reply"
        }
        guard run.persistentAssetIDsByContextID[proposal.noteItemID] != nil,
              run.persistentAssetIDsByContextID[proposal.sourceItemID] != nil else {
            return "PI proposed relation targets without persistent course identities"
        }
        return nil
    }

    private func recordRejectedAction(
        _ name: String,
        reason: String,
        run: inout ActiveRun
    ) {
        let diagnostic = sanitizedDiagnostic(reason)
        trace("discarded action name=\(name) reason=\(diagnostic)")
        run.toolTrace.append("\(name):host_rejected=\(diagnostic.prefix(600))")
        run.lastError = diagnostic
    }

    private func startHostToolCall(
        id: String,
        name: String,
        argumentsJSON: Data?
    ) {
        guard var run = activeRun,
              !id.isEmpty,
              id.utf8.count <= 256,
              !id.contains("\0"),
              !run.hostToolCallIDs.contains(id) else { return }
        run.hostToolCallIDs.insert(id)
        activeRun = run
        let request: StudyAgentHostToolRequest
        do {
            request = try hostToolRequest(
                name: name,
                argumentsJSON: argumentsJSON,
                run: run
            )
        } catch {
            writeHostToolResponse(
                requestID: run.id,
                contextRevision: run.contextRevision,
                toolCallID: id,
                toolName: name,
                payload: nil,
                error: error.localizedDescription
            )
            return
        }
        guard let handler = run.hostToolHandler else {
            writeHostToolResponse(
                requestID: run.id,
                contextRevision: run.contextRevision,
                toolCallID: id,
                toolName: name,
                payload: nil,
                error: "当前 Chat 没有可用的课程查询宿主"
            )
            return
        }

        let generation = processGeneration
        let runID = run.id
        let contextRevision = run.contextRevision
        let task = Task { [weak self] in
            do {
                let result = try await handler(request)
                await self?.completeHostToolCall(
                    id: id,
                    name: name,
                    runID: runID,
                    contextRevision: contextRevision,
                    generation: generation,
                    result: result,
                    error: nil
                )
            } catch {
                await self?.completeHostToolCall(
                    id: id,
                    name: name,
                    runID: runID,
                    contextRevision: contextRevision,
                    generation: generation,
                    result: nil,
                    error: error.localizedDescription
                )
            }
        }
        hostToolTasks[id] = task
    }

    private func hostToolRequest(
        name: String,
        argumentsJSON: Data?,
        run: ActiveRun
    ) throws -> StudyAgentHostToolRequest {
        guard let argumentsJSON,
              let arguments = try JSONSerialization.jsonObject(with: argumentsJSON)
                as? [String: Any] else {
            throw PiAgentRuntimeError.protocolFailure("课程工具参数不是 JSON 对象")
        }
        func string(
            _ key: String,
            required: Bool,
            maximum: Int
        ) throws -> String? {
            guard let raw = arguments[key] else {
                if required {
                    throw PiAgentRuntimeError.protocolFailure("课程工具缺少参数 \(key)")
                }
                return nil
            }
            guard let value = raw as? String else {
                throw PiAgentRuntimeError.protocolFailure("课程工具参数 \(key) 类型无效")
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.utf8.count <= maximum, !trimmed.contains("\0") else {
                throw PiAgentRuntimeError.protocolFailure("课程工具参数 \(key) 超出边界")
            }
            if required && trimmed.isEmpty {
                throw PiAgentRuntimeError.protocolFailure("课程工具参数 \(key) 不能为空")
            }
            return trimmed
        }
        func limit(maximum: Int) throws -> Int {
            guard let raw = arguments["limit"] else { return min(5, maximum) }
            guard !(raw is Bool), let number = raw as? NSNumber else {
                throw PiAgentRuntimeError.protocolFailure("课程工具 limit 类型无效")
            }
            let value = number.intValue
            guard number.doubleValue == Double(value), (1...maximum).contains(value) else {
                throw PiAgentRuntimeError.protocolFailure("课程工具 limit 超出边界")
            }
            return value
        }

        switch name {
        case "weibei_course_search", "grep":
            return .courseSearch(
                query: try string("query", required: true, maximum: 500) ?? "",
                limit: try limit(maximum: 8)
            )
        case "weibei_course_read":
            guard let contextItemID = try string(
                "itemID",
                required: true,
                maximum: 256
            ), let persistentItemID = run.persistentAssetIDsByContextID[contextItemID] else {
                throw PiAgentRuntimeError.protocolFailure("课程工具资料 ID 不属于本轮上下文")
            }
            return .courseRead(
                itemID: persistentItemID,
                query: try string("query", required: false, maximum: 500) ?? "",
                location: try string("location", required: false, maximum: 300),
                limit: try limit(maximum: 8)
            )
        default:
            throw PiAgentRuntimeError.protocolFailure("不支持的课程宿主工具 \(name)")
        }
    }

    private func completeHostToolCall(
        id: String,
        name: String,
        runID: UUID,
        contextRevision: String,
        generation: UInt64,
        result: StudyAgentHostToolResult?,
        error: String?
    ) {
        defer { hostToolTasks.removeValue(forKey: id) }
        guard generation == processGeneration,
              var run = activeRun,
              run.id == runID,
              run.contextRevision == contextRevision,
              run.completed == nil,
              run.hostToolCallIDs.contains(id) else { return }
        let mappedResult = result.map { result in
            StudyAgentHostToolResult(
                query: String(result.query.prefix(500)),
                items: result.items.prefix(8).map { hostItem in
                    var item = hostItem.item
                    item.id = contextAssetID(for: item.id, run: &run)
                    item.linkedItemIDs = item.linkedItemIDs.prefix(24).map {
                        contextAssetID(for: $0, run: &run)
                    }
                    return StudyAgentHostToolItem(
                        item: item,
                        relativePath: hostItem.relativePath.map { String($0.prefix(4_096)) },
                        courseIDs: hostItem.courseIDs.prefix(32).map { String($0.prefix(128)) },
                        courseTitles: hostItem.courseTitles.prefix(32).map { String($0.prefix(300)) }
                    )
                }
            )
        }
        activeRun = run
        writeHostToolResponse(
            requestID: runID,
            contextRevision: contextRevision,
            toolCallID: id,
            toolName: name,
            payload: mappedResult,
            error: error
        )
    }

    private func contextAssetID(
        for persistentID: String,
        run: inout ActiveRun
    ) -> String {
        if let existing = run.persistentAssetIDsByContextID.first(where: {
            $0.value == persistentID
        })?.key {
            return existing
        }
        var candidate: String
        repeat {
            candidate = "course-item-\(run.nextDynamicAssetOrdinal)"
            run.nextDynamicAssetOrdinal += 1
        } while run.persistentAssetIDsByContextID[candidate] != nil
        run.persistentAssetIDsByContextID[candidate] = persistentID
        return candidate
    }

    private func writeHostToolResponse(
        requestID: UUID,
        contextRevision: String,
        toolCallID: String,
        toolName: String,
        payload: StudyAgentHostToolResult?,
        error: String?
    ) {
        let envelope = HostToolResponseEnvelope(
            requestID: requestID.uuidString.lowercased(),
            contextRevision: contextRevision,
            toolCallID: toolCallID,
            toolName: toolName,
            success: payload != nil && error == nil,
            payload: payload,
            error: error.map { boundedDiagnostic($0, limit: 1_000) }
        )
        do {
            var data = try JSONEncoder().encode(envelope)
            if data.count > 256_000 {
                data = try JSONEncoder().encode(
                    HostToolResponseEnvelope(
                        requestID: requestID.uuidString.lowercased(),
                        contextRevision: contextRevision,
                        toolCallID: toolCallID,
                        toolName: toolName,
                        success: false,
                        payload: nil,
                        error: "课程工具返回内容超过上限"
                    )
                )
            }
            let digest = SHA256.hash(data: Data(toolCallID.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            let destination = hostToolResponseDirectory(for: requestID)
                .appendingPathComponent("\(digest).json")
            try data.write(to: destination, options: [.atomic])
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        } catch {
            trace("could not write host tool response: \(error.localizedDescription)")
        }
    }

    private struct ResolvedLaunch {
        var executableURL: URL
        var argumentPrefix: [String]
        var packageDirectoryURL: URL
    }

    /// Node layout launches `node …/dist/cli.js …`; legacy Mach-O launches `bin/pi` directly.
    private static func resolveLaunch(executableURL: URL) -> ResolvedLaunch {
        let binURL = executableURL.deletingLastPathComponent()
        let runtimeURL = binURL.deletingLastPathComponent()
        let nodeURL = runtimeURL.appendingPathComponent("node/bin/node")
        let cliURL = runtimeURL.appendingPathComponent(
            "agent/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
        )
        let packageURL = runtimeURL.appendingPathComponent(
            "agent/node_modules/@earendil-works/pi-coding-agent"
        )
        let fileManager = FileManager.default
        if fileManager.isExecutableFile(atPath: nodeURL.path),
           fileManager.fileExists(atPath: cliURL.path) {
            return ResolvedLaunch(
                executableURL: nodeURL,
                argumentPrefix: [cliURL.path],
                packageDirectoryURL: packageURL
            )
        }
        return ResolvedLaunch(
            executableURL: executableURL,
            argumentPrefix: [],
            packageDirectoryURL: binURL
        )
    }

    private func launchEnvironment(
        executableURL: URL,
        packageDirectoryURL: URL,
        contextURL: URL,
        piConfigurationURL: URL,
        sessionDirectory: URL
    ) -> [String: String] {
        let executableDirectory = executableURL.deletingLastPathComponent().path
        let packageDirectory = packageDirectoryURL.path
        var environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "\(executableDirectory):/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": FileManager.default.temporaryDirectory.path,
            "PI_TELEMETRY": "0",
            "PI_OFFLINE": "1",
            "PI_SKIP_VERSION_CHECK": "1",
            "PI_ZH_AUTO_UPDATE": "0",
            "PI_PACKAGE_DIR": packageDirectory,
            "PI_CODING_AGENT_DIR": piConfigurationURL.path,
            "PI_CODING_AGENT_SESSION_DIR": sessionDirectory.path,
            "WEIBEI_AGENT_CONTEXT_FILE": contextURL.path,
            "WEIBEI_AGENT_TOOL_RESPONSE_DIR": hostToolResponseRoot.path,
            "WEIBEI_AGENT_RUNTIME": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "NO_COLOR": "1",
            "TERM": "dumb",
        ]
        let hostEnvironment = ProcessInfo.processInfo.environment
        for key in [
            "LANG", "LC_ALL",
            // Respect the user's standard network route without inheriting the
            // rest of the host process environment.
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
            "http_proxy", "https_proxy", "all_proxy", "no_proxy",
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

    private func readStdout(
        _ handle: FileHandle,
        generation: UInt64
    ) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.trace("stdout reader started")
            var framer = PiJSONLFramer()
            do {
                while !Task.isCancelled {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    let lines = try framer.append(data)
                    for line in lines {
                        await self?.receiveStdoutLine(line, generation: generation)
                    }
                }
                _ = try framer.finish()
            } catch {
                await self?.transportFailed(error, generation: generation)
            }
        }
    }

    private func readStderr(
        _ handle: FileHandle,
        generation: UInt64
    ) -> Task<Void, Never> {
        Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                await self?.appendStderr(data, generation: generation)
            }
        }
    }

    private func receiveStdoutLine(_ line: Data, generation: UInt64) async {
        guard generation == processGeneration else { return }
        let message: PiRPCIncomingMessage
        do {
            message = try PiRPCMessageDecoder.decode(line)
        } catch {
            transportFailed(error, generation: generation)
            return
        }

        switch message {
        case let .response(response):
            guard let id = response.id, let pending = pendingCommands.removeValue(forKey: id) else {
                if response.command == "parse" {
                    transportFailed(
                        PiAgentRuntimeError.protocolFailure(response.error ?? "PI parse error"),
                        generation: generation
                    )
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

        case let .toolStarted(id, name, argumentsJSON):
            guard var run = activeRun else { return }
            trace("tool started name=\(name)")
            run.toolTrace.append(name)
            guard run.allowedToolNames.contains(name) else {
                activeRun = run
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI attempted an unavailable tool: \(name)"))
                )
                return
            }
            activeRun = run
            if Self.hostToolNames.contains(name) {
                startHostToolCall(
                    id: id,
                    name: name,
                    argumentsJSON: argumentsJSON
                )
            }
            refreshRunWatchdog()
            run.progressDelivery?.yield(.usingTool(name))

        case let .contextRead(_, contextRevision):
            guard var run = activeRun else { return }
            guard contextRevision == run.contextRevision else {
                recordRejectedAction(
                    "weibei_context",
                    reason: "PI read a stale WeiBei context",
                    run: &run
                )
                activeRun = run
                refreshRunWatchdog()
                return
            }
            activeRun = run
            trace("context read revision matched")
            refreshRunWatchdog()

        case let .courseSourcesRead(_, contextRevision, labels, assetIDs, jumpEvidence, sources):
            guard var run = activeRun, contextRevision == run.contextRevision else { return }
            run.allowedSourceLabels.formUnion(labels)
            run.allowedNoteSourceLabels.formUnion(labels)
            run.allowedAssetIDs.formUnion(assetIDs)
            registerJumpEvidence(jumpEvidence, in: &run)
            run.contextSources.append(contentsOf: sources)
            activeRun = run
            refreshRunWatchdog()

        case let .visualAssetRead(_, contextRevision, assetID, sha256, byteCount):
            guard var run = activeRun,
                  contextRevision == run.contextRevision,
                  run.allowedAssetIDs.contains(assetID),
                  byteCount >= 0,
                  sha256.count == 64,
                  sha256.allSatisfy(\.isHexDigit) else { return }
            run.verifiedAssetBytesByContextID[assetID] = byteCount
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
                    allowedAssetIDs: run.allowedAssetIDs,
                    verifiedAssetBytes: run.verifiedAssetBytesByContextID
                )
            ).resolvingAssetIDs(using: run.persistentAssetIDsByContextID)
            let safeNarrative = presentation.narrative
                .trimmingCharacters(in: .whitespacesAndNewlines)
            run.safeRichAnswerNarrative = safeNarrative.isEmpty ? nil : safeNarrative
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
            guard proposal.contextRevision == run.contextRevision else {
                recordRejectedAction(
                    "weibei_note_proposal",
                    reason: "PI proposed a note for a stale context",
                    run: &run
                )
                activeRun = run
                refreshRunWatchdog()
                return
            }
            guard !proposal.evidence.isEmpty,
                  proposal.evidence.allSatisfy({ evidence in
                      run.allowedNoteSourceLabels.contains(where: { evidence.hasPrefix($0) })
                  }) else {
                recordRejectedAction(
                    "weibei_note_proposal",
                    reason: "PI returned a note proposal without current-source evidence",
                    run: &run
                )
                activeRun = run
                refreshRunWatchdog()
                return
            }
            run.proposal = proposal
            activeRun = run
            refreshRunWatchdog()

        case let .relationProposal(_, proposal):
            guard var run = activeRun else { return }
            if let validationError = relationProposalValidationError(proposal, run: run) {
                recordRejectedAction(
                    "weibei_relation_proposal",
                    reason: validationError,
                    run: &run
                )
                activeRun = run
                refreshRunWatchdog()
                return
            }
            run.relationProposal = StudyAgentRelationProposal(
                noteItemID: run.persistentAssetIDsByContextID[proposal.noteItemID]!,
                sourceItemID: run.persistentAssetIDsByContextID[proposal.sourceItemID]!,
                contextRevision: proposal.contextRevision
            )
            activeRun = run
            refreshRunWatchdog()

        case let .learningUpdate(_, update):
            guard var run = activeRun else { return }
            guard update.contextRevision == run.contextRevision,
                  update.memoryRevision == run.memoryRevision else {
                recordRejectedAction(
                    "weibei_learning_update",
                    reason: "PI proposed a stale learning-memory update",
                    run: &run
                )
                activeRun = run
                refreshRunWatchdog()
                return
            }
            if let validationError = learningUpdateValidationError(update, run: run) {
                recordRejectedAction(
                    "weibei_learning_update",
                    reason: validationError,
                    run: &run
                )
                activeRun = run
                refreshRunWatchdog()
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
            guard var run = activeRun else { return }
            var replyTrace = run.toolTrace
            if let provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
                replyTrace.append("provider=\(provider)")
            }
            if let model = model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
                replyTrace.append("model=\(model)")
            }
            let modelClosureText = (text.isEmpty ? run.streamedText : text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let richNarrative = run.safeRichAnswerNarrative
            let finalText: String
            if let richNarrative, !richNarrative.isEmpty {
                finalText = richNarrative
            } else {
                finalText = modelClosureText
            }
            let citesCurrentSelection = run.allowedSourceLabels.contains {
                $0.hasPrefix("[选区：") && finalText.contains($0)
            }
            appendSources(
                run.contextSources.filter {
                    finalText.contains($0.label)
                        || ($0.kind == .selection && citesCurrentSelection)
                },
                to: &run
            )
            trace(
                "agent ended stop=\(stopReason ?? "unknown") closureChars=\(modelClosureText.count) "
                    + "finalChars=\(finalText.count) rich=\(run.richAnswer?.mode == .rich)"
            )
            let replyCandidate = StudyAgentReply(
                text: finalText,
                backend: .pi,
                richAnswer: run.richAnswer,
                sources: run.sources,
                noteProposal: run.proposal,
                relationProposal: run.relationProposal,
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
        finishHostToolRun(requestID: id)
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
        finishHostToolRun(requestID: id)
        run.watchdogTask?.cancel()
        run.progressDelivery?.finish()
        activeRun = nil
        scheduleIdleShutdown()
    }

    private func finishHostToolRun(requestID: UUID) {
        hostToolTasks.values.forEach { $0.cancel() }
        hostToolTasks.removeAll()
        removeHostToolResponseDirectory(for: requestID)
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

    private func appendStderr(_ data: Data, generation: UInt64) {
        guard generation == processGeneration else { return }
        let text = sanitizedDiagnostic(String(decoding: data, as: UTF8.self))
        stderrBuffer += text
        trace("stderr bytes=\(data.count)")
        if stderrBuffer.count > 16_384 {
            stderrBuffer = String(stderrBuffer.suffix(16_384))
        }
    }

    private func transportFailed(_ error: Error, generation: UInt64) {
        guard generation == processGeneration else { return }
        shutdownProcess(reason: PiAgentRuntimeError.protocolFailure(error.localizedDescription))
    }

    private func processDidTerminate(pid: Int32, status: Int32, generation: UInt64) {
        guard generation == processGeneration,
              process?.processIdentifier == pid else { return }
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
        processGeneration &+= 1
        clearContextSnapshot()
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        let runningProcess = process
        process = nil
        processBinding = nil
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
