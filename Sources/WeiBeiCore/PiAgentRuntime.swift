import Darwin
import CryptoKit
import Foundation
import Security

public struct PiAgentProviderConfiguration: Equatable, Sendable {
    public var provider: String?
    public var model: String?
    public var baseURL: String?
    public var thinkingLevel: String

    public init(
        provider: String? = nil,
        model: String? = nil,
        baseURL: String? = nil,
        thinkingLevel: String = "medium"
    ) {
        self.provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.thinkingLevel = thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "medium"
            : thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PiAgentResources: Sendable {
    public static let allRequiredSkillNames = ["visualize"]

    public var rootURL: URL
    public var extensionURL: URL
    public var managementExtensionURL: URL
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
        let managementExtensionURL = rootURL.appendingPathComponent("management-extension.ts")
        let skillsURL = rootURL.appendingPathComponent("skills", isDirectory: true)
        let systemURL = rootURL.appendingPathComponent("system.md")
        let hasRequiredSkills = allRequiredSkillNames.allSatisfy { skillName in
            FileManager.default.fileExists(
                atPath: skillsURL
                    .appendingPathComponent(skillName, isDirectory: true)
                    .appendingPathComponent("SKILL.md")
                    .path
            )
        }
        guard FileManager.default.fileExists(atPath: extensionURL.path),
              FileManager.default.fileExists(atPath: managementExtensionURL.path),
              hasRequiredSkills,
              let systemPrompt = try? String(contentsOf: systemURL, encoding: .utf8),
              !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PiAgentRuntimeError.resourcesMissing(rootURL.path)
        }
        return PiAgentResources(
            rootURL: rootURL,
            extensionURL: extensionURL,
            managementExtensionURL: managementExtensionURL,
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
}

public enum PiBundledRuntime {
    public static let requiredVersion = "0.82.1"

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
        let requiredFiles = [
            executableURL,
            packageURL,
            binURL.appendingPathComponent("theme/dark.json"),
            binURL.appendingPathComponent("theme/light.json"),
            runtimeURL.appendingPathComponent("LICENSE"),
            runtimeURL.appendingPathComponent("THIRD_PARTY_NOTICES.md"),
            manifestURL,
            integrityURL,
        ]
        guard fileManager.isExecutableFile(atPath: executableURL.path),
              requiredFiles.dropFirst().allSatisfy({ fileManager.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PiRuntimeManifest.self, from: data),
              let packageData = try? Data(contentsOf: packageURL),
              let package = try? JSONDecoder().decode(PackageMetadata.self, from: packageData),
              let expectedHash = try? String(contentsOf: integrityURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              manifest.schemaVersion == 1,
              manifest.piVersion == requiredVersion,
              package.version == requiredVersion,
              manifest.license == "MIT",
              !manifest.sourceRepository.isEmpty,
              manifest.sourceCommit.count == 40,
              expectedHash.count == 64,
              expectedHash.allSatisfy({ $0.isHexDigit }),
              (try? sha256(of: executableURL)) == expectedHash,
              hasExpectedArchitecture(executableURL),
              hasValidCodeSignature(executableURL) else {
            throw PiAgentRuntimeError.resourcesMissing(runtimeURL.path)
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

}

public enum PiAgentDiagnosticSanitizer {
    public static func sanitize(_ value: String) -> String {
        var result = value
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
    /// Best-effort excerpt of the most user-meaningful string argument, for the
    /// chat status line ("正在搜索：泰勒展开"). Never fails a run.
    static func toolActivityDetail(argumentsJSON: Data?) -> String? {
        guard let data = argumentsJSON,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        for key in ["query", "q", "keyword", "title", "path", "file", "file_path", "pattern", "section", "note", "topic", "name"] {
            guard let value = object[key] as? String else { continue }
            var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("/") {
                trimmed = (trimmed as NSString).lastPathComponent
            }
            guard !trimmed.isEmpty else { continue }
            return trimmed.count > 42 ? String(trimmed.prefix(42)) + "…" : trimmed
        }
        return nil
    }

    private static let processReadinessTimeoutSeconds: UInt64 = 12
    private static let sharedToolNames = [
        "weibei_course_map",
        "weibei_course_search",
        "weibei_course_read",
        "weibei_web_open",
        "weibei_visual_asset",
        "weibei_learning_memory",
        "weibei_learning_update",
        "weibei_course_profile_update",
        "weibei_visualize",
        // `read` is limited by the extension to bundled Skills.
        "read",
        "weibei_note_proposal",
        "weibei_relation_proposal",
    ]
    private static let hostToolNames: Set<String> = [
        "weibei_course_map",
        "weibei_course_search",
        "weibei_course_read",
        "weibei_web_open",
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
        }

        func waitUntilFinished() async {
            await task.value
        }

        func cancel() {
            continuation.finish()
            task.cancel()
        }
    }

    private struct PendingCommand {
        var continuation: CheckedContinuation<PiRPCResponse, Error>
        var timeoutTask: Task<Void, Never>
    }

    private struct PendingManagement {
        var interaction: PiManagementInteraction
        var promptTasks: [String: Task<Void, Never>] = [:]
        var continuation: CheckedContinuation<PiManagementEnvelope, Error>?
        var completed: Result<PiManagementEnvelope, Error>?
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
    }

    private struct DirectoryIdentity: Equatable {
        var device: dev_t
        var fileID: ino_t
    }

    private struct PiSessionState {
        var messageCount: Int
    }

    private struct PiSessionStateFailure: Error {
        var message: String
    }

    private struct ActiveRun {
        var id: UUID
        var contextRevision: String
        var memoryRevision: UInt64
        var courseProfileRevision: UInt64
        var userQuestion: String
        var updatableMemoryIDs: Set<String>
        var resolvableMemoryIDs: Set<String>
        var allowedSourceLabels: Set<String>
        var allowedAssetIDs: Set<String>
        var verifiedAssetBytesByContextID: [String: Int] = [:]
        var readCourseSourceRevisionsByContextID: [String: String] = [:]
        var readPersistentItemIDs: Set<String> = []
        var persistentAssetIDsByContextID: [String: String]
        var allowedJumpReferences: Set<String>
        var jumpEvidenceLabels: [String: Set<String>]
        var allowedLearningLabels: Set<String> = []
        var lastLocationSourceLabel: String?
        var allowedNoteSourceLabels: Set<String>
        var contextSources: [AgentReplySource]
        var sources: [AgentReplySource] = []
        var streamedText = ""
        var contentBlocks: [AgentMessageContentBlock] = []
        var proposal: StudyAgentNoteProposal?
        var relationProposal: StudyAgentRelationProposal?
        var learningUpdate: StudyAgentLearningUpdate?
        var courseProfileUpdate: StudyAgentCourseProfileUpdate?
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
    private let persistentPiConfigurationDirectory: URL
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
    private var pendingManagement: PendingManagement?
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
        persistentPiConfigurationDirectory: URL? = nil,
        // Idle hang detection: 90s without events (was 5 minutes).
        runInactivityTimeoutNanoseconds: UInt64 = 90_000_000_000
    ) {
        executableOverride = executableURL
        let resolvedRuntimeDirectory = runtimeDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("WeiBei/AgentRuntime", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiAgentRuntime", isDirectory: true)
        self.runtimeDirectory = resolvedRuntimeDirectory
        self.persistentPiConfigurationDirectory = persistentPiConfigurationDirectory
            ?? (executableURL == nil
                ? WeiBeiAgentDataPaths.piAgentDirectory
                : resolvedRuntimeDirectory.appendingPathComponent("PiAgent", isDirectory: true))
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
                workingDirectory: runtimeDirectory
            )
        )
        return process?.executableURL?.path ?? "pi"
    }

    public func managementCatalog(refresh: Bool = false) async throws -> PiManagementCatalog {
        let envelope = try await performManagement(
            PiManagementRequest(action: .catalog, refresh: refresh),
            interaction: .nonInteractive
        )
        guard envelope.action == .catalog, let catalog = envelope.catalog else {
            throw PiAgentRuntimeError.protocolFailure("PI returned an invalid management catalog")
        }
        return catalog
    }

    public func login(
        providerID: String,
        type: PiCredentialType,
        interaction: PiManagementInteraction
    ) async throws -> PiManagementCredentialInfo {
        let envelope = try await performManagement(
            PiManagementRequest(
                action: .login,
                providerId: providerID,
                authType: type
            ),
            interaction: interaction
        )
        guard envelope.action == .login,
              let credential = envelope.credential,
              credential.providerId == providerID,
              credential.type == type else {
            throw PiAgentRuntimeError.protocolFailure("PI returned an invalid login result")
        }
        return credential
    }

    public func logout(providerID: String) async throws {
        let envelope = try await performManagement(
            PiManagementRequest(action: .logout, providerId: providerID),
            interaction: .nonInteractive
        )
        guard envelope.action == .logout, envelope.providerId == providerID else {
            throw PiAgentRuntimeError.protocolFailure("PI returned an invalid logout result")
        }
    }

    private func performManagement(
        _ request: PiManagementRequest,
        interaction: PiManagementInteraction
    ) async throws -> PiManagementEnvelope {
        guard activeRun == nil, startingRunID == nil, pendingManagement == nil else {
            throw PiAgentRuntimeError.busy
        }
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        try FileManager.default.createDirectory(
            at: runtimeDirectory,
            withIntermediateDirectories: true
        )
        _ = try await ensureProcess(
            binding: try makeProcessBinding(
                sessionID: fallbackSessionID,
                workingDirectory: runtimeDirectory
            )
        )
        let command = try PiManagementCodec.command(for: request)
        pendingManagement = PendingManagement(interaction: interaction)

        return try await withTaskCancellationHandler(operation: {
            do {
                _ = try await sendCommand(
                    type: "prompt",
                    fields: ["message": command],
                    timeoutSeconds: 3_600
                )
                let envelope = try await waitForManagement()
                let completedProcess = process
                shutdownProcess(reason: PiAgentRuntimeError.cancelled)
                await forceStopIfNeeded(completedProcess, graceNanoseconds: 750_000_000)
                return envelope
            } catch {
                let runningProcess = process
                shutdownProcess(reason: error)
                await forceStopIfNeeded(runningProcess, graceNanoseconds: 750_000_000)
                throw error
            }
        }, onCancel: {
            Task { await self.cancelManagement() }
        })
    }

    public func respond(to request: StudyAgentRequest, progress: StudyAgentProgressHandler?) async throws -> StudyAgentReply {
        let declaredChatID = request.projectScope.chatID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let focusedChatID = request.focus?.chatID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionID = UUID(uuidString: declaredChatID)
            ?? focusedChatID.flatMap(UUID.init(uuidString:))
            ?? request.id
        return try await respond(
            to: request,
            sessionID: sessionID,
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
        if let provider = providerConfiguration.provider,
           !provider.isEmpty,
           providerConfiguration.model?.isEmpty != false {
            throw PiAgentRuntimeError.commandRejected(
                request.language.text(
                    "请先在设置中选择模型。",
                    "Choose a model in Settings before sending."
                )
            )
        }
        var request = request
        let expectedChatID = sessionID.uuidString.lowercased()
        let projectChatID = request.projectScope.chatID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard projectChatID.isEmpty
                || UUID(uuidString: projectChatID)?.uuidString.lowercased() == expectedChatID else {
            throw PiAgentRuntimeError.protocolFailure(
                "request Chat identity did not match the PI session"
            )
        }
        request.projectScope.chatID = expectedChatID
        if let focusChatID = request.focus?.chatID
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !focusChatID.isEmpty,
           UUID(uuidString: focusChatID)?.uuidString.lowercased() != expectedChatID {
            throw PiAgentRuntimeError.protocolFailure(
                "request focus did not match the PI session"
            )
        }
        request.focus?.chatID = expectedChatID
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
            workingDirectory: workingDirectory
        )
        do {
            _ = try await ensureProcess(binding: binding)
        } catch let failure as PiSessionStateFailure {
            throw PiAgentRuntimeError.protocolFailure(failure.message)
        }
        try requireStartingRun(request.id)

        let context = StudyAgentContextEnvelope(request: request)
        try writeContext(context)
        try prepareHostToolResponseDirectory(for: request.id)
        let progressDelivery = progress.map(ProgressDelivery.init(handler:))

        let currentJumpEvidence = currentJumpEvidence(in: context)
        let currentSourceLabels = currentSourceLabels(request: request, context: context)
        let persistentAssetIDsByContextID = persistentAssetIDsByContextID(
            request: request,
            context: context
        )
        activeRun = ActiveRun(
            id: request.id,
            contextRevision: request.contextRevision,
            memoryRevision: request.learningContext.memoryRevision,
            courseProfileRevision: request.courseProfile.revision,
            userQuestion: request.question,
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
            persistentAssetIDsByContextID: persistentAssetIDsByContextID,
            allowedJumpReferences: Set(currentJumpEvidence.keys),
            jumpEvidenceLabels: currentJumpEvidence,
            lastLocationSourceLabel: context.learning.lastLocation.map { "[材料：\($0.itemTitle)]" },
            allowedNoteSourceLabels: currentSourceLabels,
            contextSources: request.selectionSources,
            allowedToolNames: Set(Self.sharedToolNames).subtracting(
                request.interactiveVisualizationsEnabled ? [] : ["weibei_visualize"]
            ),
            allowsRelationProposal: request.projectScope.courseID?.isEmpty == false,
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
                fields: [
                    "message": piPrompt(
                        for: request,
                        persistentAssetIDsByContextID: persistentAssetIDsByContextID
                    ),
                ],
                timeoutSeconds: 3
            )
        } catch {
            let failure = promptSubmissionFailure(from: error)
            discardRun(id: request.id)
            shutdownProcess(reason: failure)
            throw failure
        }

        let reply = try await waitForRun(id: request.id)
        await withTaskCancellationHandler {
            await progressDelivery?.waitUntilFinished()
        } onCancel: {
            progressDelivery?.cancel()
        }
        try Task.checkCancellation()
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
        workingDirectory: URL
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
            sessionDirectory: sessionDirectory
        )
    }

    private func ensureProcess(binding: ProcessBinding) async throws -> PiSessionState {
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
        try prepareSessionDirectory(binding.sessionDirectory)

        let contextURL = runtimeDirectory.appendingPathComponent("context.json")
        let process = Process()
        processGeneration &+= 1
        let generation = processGeneration
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executableURL
        process.currentDirectoryURL = binding.workingDirectory
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.arguments = launchArguments(resources: resources, binding: binding)
        process.environment = launchEnvironment(
            executableURL: executableURL,
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
                message: "could not read the requested Chat session: \(error.localizedDescription)"
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
                message: "get_state did not match the requested Chat session"
            )
        }
        let reportedSessionDirectory = URL(fileURLWithPath: sessionFile)
            .deletingLastPathComponent()
        let reportedIdentity = Self.directoryIdentity(at: reportedSessionDirectory)
        let requestedIdentity = Self.directoryIdentity(at: binding.sessionDirectory)
        guard let requestedIdentity, reportedIdentity == requestedIdentity else {
            throw PiSessionStateFailure(
                message: "get_state returned a session outside the requested Chat directory"
            )
        }
        return PiSessionState(messageCount: messageCount)
    }

    private func sessionDirectory(for sessionID: UUID) -> URL {
        sessionsRoot
            .appendingPathComponent(sessionID.uuidString.lowercased(), isDirectory: true)
    }

    private var sessionsRoot: URL {
        runtimeDirectory.appendingPathComponent("Sessions", isDirectory: true)
    }

    private static func canonicalFileURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func directoryIdentity(at url: URL) -> DirectoryIdentity? {
        let canonicalURL = canonicalFileURL(url)
        var fileStat = Darwin.stat()
        guard canonicalURL.withUnsafeFileSystemRepresentation({ path in
            path.map { Darwin.lstat($0, &fileStat) == 0 } ?? false
        }),
        (fileStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            return nil
        }
        return DirectoryIdentity(device: fileStat.st_dev, fileID: fileStat.st_ino)
    }

    private func checkedSessionsRoot(createIfMissing: Bool) throws -> DirectoryIdentity? {
        let fileManager = FileManager.default
        var rootStat = Darwin.stat()
        var rootExists = sessionsRoot.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.lstat($0, &rootStat) == 0 } ?? false
        }
        if !rootExists {
            guard errno == ENOENT else {
                throw PiAgentRuntimeError.protocolFailure(
                    "could not inspect the PI session directory"
                )
            }
            guard createIfMissing else { return nil }
            try fileManager.createDirectory(
                at: sessionsRoot,
                withIntermediateDirectories: false
            )
            rootExists = sessionsRoot.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.lstat($0, &rootStat) == 0 } ?? false
            }
        }
        guard rootExists,
              (rootStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              Self.canonicalFileURL(sessionsRoot).deletingLastPathComponent()
                == Self.canonicalFileURL(runtimeDirectory) else {
            throw PiAgentRuntimeError.protocolFailure(
                "PI session storage is not a safe local directory"
            )
        }
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: sessionsRoot.path
        )
        return DirectoryIdentity(device: rootStat.st_dev, fileID: rootStat.st_ino)
    }

    private func requireSessionsRootIdentity(_ identity: DirectoryIdentity) throws {
        var rootStat = Darwin.stat()
        guard sessionsRoot.withUnsafeFileSystemRepresentation({ path in
            path.map { Darwin.lstat($0, &rootStat) == 0 } ?? false
        }),
        (rootStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
        DirectoryIdentity(device: rootStat.st_dev, fileID: rootStat.st_ino) == identity else {
            throw PiAgentRuntimeError.protocolFailure(
                "PI session storage changed during access"
            )
        }
    }

    private func prepareSessionDirectory(_ sessionDirectory: URL) throws {
        guard sessionDirectory.deletingLastPathComponent().standardizedFileURL
                == sessionsRoot.standardizedFileURL,
              let rootIdentity = try checkedSessionsRoot(createIfMissing: true) else {
            throw PiAgentRuntimeError.protocolFailure(
                "refused to prepare a session outside WeiBei AgentRuntime"
            )
        }
        var sessionStat = Darwin.stat()
        let sessionExists = sessionDirectory.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.lstat($0, &sessionStat) == 0 } ?? false
        }
        if sessionExists {
            guard (sessionStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw PiAgentRuntimeError.protocolFailure(
                    "PI Chat session storage is not a local directory"
                )
            }
        } else {
            guard errno == ENOENT else {
                throw PiAgentRuntimeError.protocolFailure(
                    "could not inspect the PI Chat session directory"
                )
            }
            try FileManager.default.createDirectory(
                at: sessionDirectory,
                withIntermediateDirectories: false
            )
            guard sessionDirectory.withUnsafeFileSystemRepresentation({ path in
                path.map { Darwin.lstat($0, &sessionStat) == 0 } ?? false
            }),
            (sessionStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw PiAgentRuntimeError.protocolFailure(
                    "PI Chat session directory identity changed after creation"
                )
            }
        }
        try requireSessionsRootIdentity(rootIdentity)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: sessionDirectory.path
        )
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

    private func removeSessionDirectory(_ sessionDirectory: URL) throws {
        guard sessionDirectory.deletingLastPathComponent().standardizedFileURL
                == sessionsRoot.standardizedFileURL else {
            throw PiAgentRuntimeError.protocolFailure(
                "refused to remove a session outside WeiBei AgentRuntime"
            )
        }
        guard let rootIdentity = try checkedSessionsRoot(createIfMissing: false) else {
            return
        }
        var sessionStat = Darwin.stat()
        let sessionExists = sessionDirectory.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.lstat($0, &sessionStat) == 0 } ?? false
        }
        guard sessionExists else {
            guard errno == ENOENT else {
                throw PiAgentRuntimeError.protocolFailure(
                    "could not inspect the PI Chat session directory"
                )
            }
            return
        }
        guard (sessionStat.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw PiAgentRuntimeError.protocolFailure(
                "refused to remove an invalid PI Chat session directory"
            )
        }
        try requireSessionsRootIdentity(rootIdentity)
        try FileManager.default.removeItem(at: sessionDirectory)
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
            "--tools", Self.sharedToolNames.joined(separator: ","),
            "--no-extensions",
            "--extension", resources.extensionURL.path,
            "--extension", resources.managementExtensionURL.path,
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

    private func piPrompt(
        for request: StudyAgentRequest,
        persistentAssetIDsByContextID: [String: String]
    ) -> String {
        guard let selection = request.selectionText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selection.isEmpty else {
            return request.question
        }

        let title = request.selectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectionTitle = title.flatMap { $0.isEmpty ? nil : $0 }
            ?? request.language.text("当前选区", "Current selection")
        let separator = request.language.text("；", "; ")
        let contextItemIDsByPersistentID = Dictionary(
            uniqueKeysWithValues: persistentAssetIDsByContextID.map { ($0.value, $0.key) }
        )
        let sources = request.selectionSources.map { source in
            var parts = [source.label]
            if let itemID = source.itemID,
               let contextItemID = contextItemIDsByPersistentID[itemID] {
                parts.append(
                    request.language.text(
                        "条目 ID：\(contextItemID)",
                        "Item ID: \(contextItemID)"
                    )
                )
            }
            if let position = source.positionLabel(language: request.language) {
                parts.append(position)
            }
            return parts.joined(separator: separator)
        }
        let sourceLines = sources.isEmpty ? "[选区：\(selectionTitle)]" : sources.joined(separator: "\n")

        return request.language.text(
            "[选中文字：\(selectionTitle)]\n\(selection)\n\n[来源]\n\(sourceLines)\n\n[问题]\n\(request.question)",
            "[Selected text: \(selectionTitle)]\n\(selection)\n\n[Sources]\n\(sourceLines)\n\n[Question]\n\(request.question)"
        )
    }

    private func currentSourceLabels(
        request: StudyAgentRequest,
        context: StudyAgentContextEnvelope
    ) -> Set<String> {
        var labels = Set(request.selectionSources.map(\.label))
        if let selection = context.selection,
           !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            labels.insert("[选区：\(selection.title)]")
        }
        return labels
    }

    private func currentAssetIDs(in context: StudyAgentContextEnvelope) -> Set<String> {
        Set(context.course.catalog.lazy.filter(\.isCurrentMaterial).map(\.id))
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
        func integer(
            _ key: String,
            defaultValue: Int,
            range: ClosedRange<Int>
        ) throws -> Int {
            guard let raw = arguments[key] else { return defaultValue }
            guard !(raw is Bool), let number = raw as? NSNumber else {
                throw PiAgentRuntimeError.protocolFailure("课程工具 \(key) 类型无效")
            }
            let value = number.intValue
            guard number.doubleValue == Double(value), range.contains(value) else {
                throw PiAgentRuntimeError.protocolFailure("课程工具 \(key) 超出边界")
            }
            return value
        }
        func limit(maximum: Int, defaultValue: Int = 5) throws -> Int {
            try integer("limit", defaultValue: min(defaultValue, maximum), range: 1...maximum)
        }
        func maximumCharacters() throws -> Int {
            guard let raw = arguments["maximumCharacters"] else { return 6_000 }
            guard !(raw is Bool), let number = raw as? NSNumber else {
                throw PiAgentRuntimeError.protocolFailure(
                    "课程工具 maximumCharacters 类型无效"
                )
            }
            let value = number.intValue
            guard number.doubleValue == Double(value),
                  (1_000...12_000).contains(value) else {
                throw PiAgentRuntimeError.protocolFailure(
                    "课程工具 maximumCharacters 超出边界"
                )
            }
            return value
        }
        func webMaximumCharacters() throws -> Int {
            guard let raw = arguments["maximumCharacters"] else { return 12_000 }
            guard !(raw is Bool), let number = raw as? NSNumber else {
                throw PiAgentRuntimeError.protocolFailure(
                    "网页工具 maximumCharacters 类型无效"
                )
            }
            let value = number.intValue
            guard number.doubleValue == Double(value),
                  (1_000...20_000).contains(value) else {
                throw PiAgentRuntimeError.protocolFailure(
                    "网页工具 maximumCharacters 超出边界"
                )
            }
            return value
        }

        switch name {
        case "weibei_course_map":
            let contextItemID = try string("itemID", required: false, maximum: 256)
            let persistentItemID: String?
            if let contextItemID {
                guard let mapped = run.persistentAssetIDsByContextID[contextItemID] else {
                    throw PiAgentRuntimeError.protocolFailure("课程工具资料 ID 不属于本轮上下文")
                }
                persistentItemID = mapped
            } else {
                persistentItemID = nil
            }
            return .courseMap(
                itemID: persistentItemID,
                offset: try integer("offset", defaultValue: 0, range: 0...100_000),
                limit: try limit(maximum: 40, defaultValue: 40)
            )
        case "weibei_course_search":
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
                cursor: try string("cursor", required: false, maximum: 1_024),
                maximumCharacters: try maximumCharacters()
            )
        case "weibei_web_open":
            let url = try string("url", required: true, maximum: 2_048) ?? ""
            guard WeiBeiWebResearchURLPolicy.isExplicitlyProvided(
                url,
                in: run.userQuestion
            ) else {
                throw PiAgentRuntimeError.protocolFailure(
                    "网页工具只能读取用户本轮明确提供的地址"
                )
            }
            return .webOpen(
                url: url,
                maximumCharacters: try webMaximumCharacters()
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
            if name == "weibei_web_open" {
                return StudyAgentHostToolResult(
                    query: String(result.query.prefix(2_048)),
                    items: [],
                    webPages: result.webPages.prefix(1).compactMap { page in
                        guard let components = URLComponents(string: page.url),
                              components.scheme?.lowercased() == "https",
                              components.host?.isEmpty == false else {
                            return nil
                        }
                        return StudyAgentWebPage(
                            url: String(page.url.prefix(2_048)),
                            title: String(page.title.prefix(300)),
                            text: String(page.text.prefix(20_000)),
                            isTruncated: page.isTruncated || page.text.count > 20_000
                        )
                    }
                )
            }
            let maximumItems = name == "weibei_course_map" ? 40 : 8
            return StudyAgentHostToolResult(
                query: String(result.query.prefix(500)),
                items: result.items.prefix(maximumItems).map { hostItem in
                    var item = hostItem.item
                    item.id = contextAssetID(for: item.id, run: &run)
                    run.courseCatalogRolesByContextID[item.id] = item.role
                    item.linkedItemIDs = item.linkedItemIDs.prefix(24).map {
                        contextAssetID(for: $0, run: &run)
                    }
                    return StudyAgentHostToolItem(
                        item: item,
                        relativePath: hostItem.relativePath.map { String($0.prefix(4_096)) },
                        courseIDs: hostItem.courseIDs.prefix(32).map { String($0.prefix(128)) },
                        courseTitles: hostItem.courseTitles.prefix(32).map { String($0.prefix(300)) },
                        sourceRevision: hostItem.sourceRevision.map { String($0.prefix(500)) }
                    )
                },
                total: result.total,
                nextCursor: result.nextCursor.map { String($0.prefix(1_024)) },
                sourceRevision: result.sourceRevision.map { String($0.prefix(500)) }
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

    private func launchEnvironment(
        executableURL: URL,
        contextURL: URL,
        piConfigurationURL: URL,
        sessionDirectory: URL
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
            "PI_CODING_AGENT_SESSION_DIR": sessionDirectory.path,
            "WEIBEI_PI_AUTH_PATH": piConfigurationURL
                .appendingPathComponent("auth.json").path,
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
        ] {
            if let value = hostEnvironment[key], !value.isEmpty, value.count <= 2048, !value.contains("\n") {
                environment[key] = value
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

    /// Inject a custom / local OpenAI-compatible provider into PI_CODING_AGENT_DIR/models.json.
    /// Built-in Pi providers (including Azure) use auth + env vars instead.
    public func writeCustomModelsJSONIfNeeded(
        providerID: AgentProviderID,
        baseURL: String,
        model: String
    ) async throws {
        guard providerID == .custom || providerID == .llamaCpp else {
            return
        }
        let endpoint = try AgentProviderEndpoint(provider: providerID, baseURL: baseURL)
        guard let normalizedBaseURL = endpoint.baseURL else {
            throw AgentProviderEndpointError.missing
        }
        let piConfigurationURL = try preparePiConfigurationDirectory()
        let modelsURL = piConfigurationURL.appendingPathComponent("models.json")
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = selectedModel.isEmpty
            ? (providerID == .llamaCpp ? "local-model" : "model-id")
            : selectedModel
        let payload: [String: Any] = [
            "providers": [
                endpoint.piProviderID: [
                    "baseUrl": normalizedBaseURL,
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
        guard (try? Data(contentsOf: modelsURL)) != data else { return }
        try data.write(to: modelsURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: modelsURL.path)
        trace("wrote custom models.json provider=\(endpoint.piProviderID)")
        // Pi reads models.json at process creation; force the next login/respond
        // to bind the endpoint-specific provider instead of a stale catalog.
        shutdownProcess(reason: PiAgentRuntimeError.cancelled)
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
        try fileManager.createDirectory(
            at: persistentPiConfigurationDirectory,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: persistentPiConfigurationDirectory.path
        )
        let remoteCatalogCacheURL = persistentPiConfigurationDirectory
            .appendingPathComponent("models-store.json")
        if fileManager.fileExists(atPath: remoteCatalogCacheURL.path) {
            try fileManager.removeItem(at: remoteCatalogCacheURL)
        }
        return persistentPiConfigurationDirectory
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
        guard inputHandle != nil, process?.isRunning == true else {
            throw PiAgentRuntimeError.unavailable
        }

        let id = UUID().uuidString.lowercased()
        var object = fields
        object["id"] = id
        object["type"] = type
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
                    try writeRPCObject(object)
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

    private func writeRPCObject(_ object: [String: Any]) throws {
        guard let inputHandle, process?.isRunning == true else {
            throw PiAgentRuntimeError.unavailable
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
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

    private func waitForManagement() async throws -> PiManagementEnvelope {
        try await withCheckedThrowingContinuation { continuation in
            guard var management = pendingManagement else {
                continuation.resume(throwing: PiAgentRuntimeError.cancelled)
                return
            }
            if let completed = management.completed {
                pendingManagement = nil
                continuation.resume(with: completed)
            } else {
                management.continuation = continuation
                pendingManagement = management
            }
        }
    }

    private func finishManagement(with result: Result<PiManagementEnvelope, Error>) {
        guard var management = pendingManagement else { return }
        guard management.completed == nil else { return }
        management.promptTasks.values.forEach { $0.cancel() }
        management.promptTasks.removeAll()
        if let continuation = management.continuation {
            pendingManagement = nil
            continuation.resume(with: result)
        } else {
            management.completed = result
            pendingManagement = management
        }
    }

    private func cancelManagement() {
        guard pendingManagement != nil else { return }
        finishManagement(with: .failure(PiAgentRuntimeError.cancelled))
        shutdownProcess(reason: PiAgentRuntimeError.cancelled)
    }

    private func handleExtensionUIRequest(_ request: PiRPCExtensionUIRequest) async {
        guard let management = pendingManagement else { return }
        if request.method == "notify", let message = request.message {
            do {
                guard let envelope = try PiManagementCodec.envelope(from: message) else { return }
                switch envelope.kind {
                case "event":
                    if let event = envelope.event {
                        await management.interaction.notify(event)
                    }
                case "result":
                    finishManagement(with: .success(envelope))
                case "error":
                    finishManagement(
                        with: .failure(
                            PiAgentRuntimeError.agentFailed(
                                sanitizedDiagnostic(envelope.message ?? "PI management failed")
                            )
                        )
                    )
                default:
                    break
                }
            } catch {
                finishManagement(with: .failure(error))
            }
            return
        }

        guard ["input", "select"].contains(request.method),
              let title = request.title else { return }
        do {
            let prompt = try PiManagementCodec.prompt(from: title)
            guard (request.method == "select") == (prompt.type == .select) else {
                throw PiAgentRuntimeError.protocolFailure("PI management prompt method did not match")
            }
            if prompt.type == .select,
               request.options != (prompt.options?.map(\.label) ?? []) {
                throw PiAgentRuntimeError.protocolFailure("PI management prompt options did not match")
            }
            let interaction = management.interaction
            let task = Task { [weak self] in
                do {
                    let value = try await interaction.prompt(prompt)
                    let rpcValue: String
                    if prompt.type == .select {
                        rpcValue = prompt.options?.first(where: { $0.id == value })?.label ?? value
                    } else {
                        rpcValue = value
                    }
                    try await self?.sendExtensionUIResponse(id: request.id, value: rpcValue)
                } catch {
                    try? await self?.sendExtensionUICancellation(id: request.id)
                    await self?.finishManagement(with: .failure(error))
                }
            }
            var updated = management
            updated.promptTasks[request.id] = task
            pendingManagement = updated
        } catch {
            finishManagement(with: .failure(error))
        }
    }

    private func sendExtensionUIResponse(id: String, value: String) throws {
        guard value.utf8.count <= 1_048_576 else {
            throw PiAgentRuntimeError.protocolFailure("PI management input exceeded the size limit")
        }
        try writeRPCObject([
            "type": "extension_ui_response",
            "id": id,
            "value": value,
        ])
        pendingManagement?.promptTasks.removeValue(forKey: id)
    }

    private func sendExtensionUICancellation(id: String) throws {
        try writeRPCObject([
            "type": "extension_ui_response",
            "id": id,
            "cancelled": true,
        ])
        pendingManagement?.promptTasks.removeValue(forKey: id)
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
            if case let .text(existing)? = run.contentBlocks.last {
                run.contentBlocks[run.contentBlocks.count - 1] = .text(existing + delta)
            } else if !delta.isEmpty {
                run.contentBlocks.append(.text(delta))
            }
            activeRun = run
            refreshRunWatchdog()
            run.progressDelivery?.yield(.text(run.streamedText, run.contentBlocks))

        case .runActivity:
            refreshRunWatchdog()

        case let .assistantError(message):
            guard var run = activeRun else { return }
            run.lastError = sanitizedDiagnostic(message)
            activeRun = run
            refreshRunWatchdog()

        case let .extensionUIRequest(request):
            await handleExtensionUIRequest(request)

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
            run.progressDelivery?.yield(.usingTool(name, Self.toolActivityDetail(argumentsJSON: argumentsJSON)))

        case let .courseSourcesRead(
            _,
            toolName,
            contextRevision,
            labels,
            assetIDs,
            sourceRevisions,
            jumpEvidence,
            sources
        ):
            guard var run = activeRun, contextRevision == run.contextRevision else { return }
            run.allowedSourceLabels.formUnion(labels)
            run.allowedNoteSourceLabels.formUnion(labels)
            run.allowedAssetIDs.formUnion(assetIDs)
            run.readCourseSourceRevisionsByContextID.merge(
                sourceRevisions,
                uniquingKeysWith: { _, latest in latest }
            )
            if toolName == "weibei_course_read" {
                for assetID in assetIDs {
                    if let itemID = run.persistentAssetIDsByContextID[assetID] {
                        run.readPersistentItemIDs.insert(itemID)
                    }
                }
            }
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

        case .artifactComputed, .richAnswer:
            break

        case let .visualization(_, fragment):
            guard var run = activeRun else { return }
            if let index = run.contentBlocks.firstIndex(where: { block in
                if case let .visualization(existing) = block {
                    return existing.id == fragment.id
                }
                return false
            }) {
                run.contentBlocks[index] = .visualization(fragment)
            } else {
                run.contentBlocks.append(.visualization(fragment))
            }
            activeRun = run
            refreshRunWatchdog()
            run.progressDelivery?.yield(.visualization(fragment, run.contentBlocks))

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

        case let .courseProfileUpdate(_, update):
            guard var run = activeRun,
                  run.courseProfileUpdate == nil,
                  update.contextRevision == run.contextRevision,
                  update.profileRevision == run.courseProfileRevision,
                  [
                      "sectionCompleted",
                      "topicCompleted",
                      "crossSourceConnection",
                      "beforeContextSwitch",
                  ].contains(update.checkpoint),
                  !update.entries.isEmpty || !update.removedEntryIDs.isEmpty,
                  update.entries.count <= 12,
                  update.removedEntryIDs.count <= 12 else { return }
            var mappedEntries: [StudyAgentCourseProfileUpdateEntry] = []
            for entry in update.entries {
                guard !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      entry.text.count <= 1_200,
                      !entry.sources.isEmpty,
                      entry.sources.count <= 8 else { return }
                var mappedSources: [StudyAgentCourseProfileSource] = []
                for source in entry.sources {
                    guard let persistentID = run.persistentAssetIDsByContextID[source.itemID],
                          run.courseCatalogRolesByContextID[source.itemID] == source.role,
                          run.readCourseSourceRevisionsByContextID[source.itemID]
                            == source.sourceRevision else { return }
                    mappedSources.append(
                        StudyAgentCourseProfileSource(
                            itemID: persistentID,
                            role: source.role,
                            location: source.location,
                            sourceRevision: source.sourceRevision
                        )
                    )
                }
                mappedEntries.append(
                    StudyAgentCourseProfileUpdateEntry(
                        entryID: entry.entryID,
                        kind: entry.kind,
                        text: entry.text,
                        sources: mappedSources
                    )
                )
            }
            run.courseProfileUpdate = StudyAgentCourseProfileUpdate(
                contextRevision: update.contextRevision,
                profileRevision: update.profileRevision,
                checkpoint: update.checkpoint,
                entries: mappedEntries,
                removedEntryIDs: update.removedEntryIDs
            )
            activeRun = run
            refreshRunWatchdog()

        case let .toolFailed(_, name, message):
            guard var run = activeRun else { return }
            trace("tool failed name=\(name) message=\(sanitizedDiagnostic(message))")
            run.lastError = "\(name): \(boundedDiagnostic(message))"
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
            let hasVisualization = run.contentBlocks.contains { block in
                if case .visualization = block { return true }
                return false
            }
            var finalContentBlocks = hasVisualization ? run.contentBlocks : []
            let orderedText: String
            if !hasVisualization {
                orderedText = modelClosureText
            } else if run.streamedText.isEmpty {
                orderedText = modelClosureText
                if !modelClosureText.isEmpty {
                    finalContentBlocks.append(.text(modelClosureText))
                }
            } else if text.isEmpty || text == run.streamedText {
                orderedText = run.streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if text.hasPrefix(run.streamedText) {
                let tail = String(text.dropFirst(run.streamedText.count))
                if !tail.isEmpty {
                    if case let .text(existing)? = finalContentBlocks.last {
                        finalContentBlocks[finalContentBlocks.count - 1] = .text(existing + tail)
                    } else {
                        finalContentBlocks.append(.text(tail))
                    }
                }
                orderedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                orderedText = run.streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let finalText = orderedText
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
                    + "finalChars=\(finalText.count)"
            )
            let replyCandidate = StudyAgentReply(
                text: finalText,
                contentBlocks: finalContentBlocks,
                backend: .pi,
                richAnswer: nil,
                sources: run.sources,
                noteProposal: run.proposal,
                relationProposal: run.relationProposal,
                learningUpdate: run.learningUpdate,
                courseProfileUpdate: run.courseProfileUpdate,
                loadedSkills: run.loadedSkills,
                readItemIDs: run.readPersistentItemIDs.sorted(),
                toolTrace: replyTrace
            )
            if stopReason == "aborted" {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.cancelled))
            } else if stopReason == "error" {
                let detail = modelError.map { boundedDiagnostic($0) }
                    ?? run.lastError
                    ?? "PI 模型请求失败，但运行时没有返回错误详情"
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed(detail)))
            } else if finalText.isEmpty && !hasVisualization {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed(run.lastError ?? "PI returned no readable text")))
            } else {
                finishRun(id: run.id, with: .success(replyCandidate))
            }

        case let .extensionError(message):
            let message = boundedDiagnostic(message)
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
        switch result {
        case let .success(reply):
            if !run.streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                run.progressDelivery?.yield(.text(reply.text, reply.contentBlocks))
            }
            run.progressDelivery?.finish()
        case .failure:
            run.progressDelivery?.cancel()
        }
        completeRun(run, with: result)
    }

    private func completeRun(
        _ run: ActiveRun,
        with result: Result<StudyAgentReply, Error>
    ) {
        var run = run
        if let continuation = run.continuation {
            activeRun = nil
            continuation.resume(with: result)
            scheduleIdleShutdown()
        } else {
            run.completed = result
            activeRun = run
        }
    }

    private func discardRun(id: UUID) {
        guard let run = activeRun, run.id == id else { return }
        finishHostToolRun(requestID: id)
        run.watchdogTask?.cancel()
        run.progressDelivery?.cancel()
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
        PiAgentDiagnosticSanitizer.sanitize(value)
    }

    private func boundedDiagnostic(_ value: String, limit: Int = 1_024) -> String {
        String(sanitizedDiagnostic(value).prefix(limit))
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

        if let management = pendingManagement {
            let managementReason: Error = (reason as? PiAgentRuntimeError) == .cancelled
                ? PiAgentRuntimeError.cancelled
                : PiAgentRuntimeError.inFlightFailed(reason.localizedDescription)
            management.promptTasks.values.forEach { $0.cancel() }
            pendingManagement = nil
            management.continuation?.resume(throwing: managementReason)
        }

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
