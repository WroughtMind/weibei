import Darwin
import CryptoKit
import Foundation
import Security

public struct PiAgentProviderConfiguration: Equatable, Sendable {
    public var provider: String?
    public var model: String?
    public var apiKey: String?
    public var thinkingLevel: String

    public init(provider: String? = nil, model: String? = nil, apiKey: String? = nil, thinkingLevel: String = "medium") {
        self.provider = provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.thinkingLevel = thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "medium"
            : thinkingLevel.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PiAgentResources: Sendable {
    public static let requiredSkillNames = [
        "weibei-study-companion",
        "weibei-course-wayfinding",
        "weibei-close-reading",
        "weibei-note-making",
        "weibei-recall-practice",
    ]

    public var rootURL: URL
    public var extensionURL: URL
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
        let skillsURL = rootURL.appendingPathComponent("skills", isDirectory: true)
        let systemURL = rootURL.appendingPathComponent("system.md")
        let hasRequiredSkills = requiredSkillNames.allSatisfy { skillName in
            FileManager.default.fileExists(
                atPath: skillsURL.appendingPathComponent(skillName).appendingPathComponent("SKILL.md").path
            )
        }
        guard FileManager.default.fileExists(atPath: extensionURL.path),
              hasRequiredSkills,
              let systemPrompt = try? String(contentsOf: systemURL, encoding: .utf8),
              !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PiAgentRuntimeError.resourcesMissing(rootURL.path)
        }
        return PiAgentResources(
            rootURL: rootURL,
            extensionURL: extensionURL,
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
    public static let requiredVersion = "0.80.2"

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
    private struct PendingCommand {
        var continuation: CheckedContinuation<PiRPCResponse, Error>
        var timeoutTask: Task<Void, Never>
    }

    private struct ActiveRun {
        var id: UUID
        var contextRevision: String
        var memoryRevision: UInt64
        var workflow: StudyAgentWorkflow
        var allowedSourceLabels: Set<String>
        var allowedNoteSourceLabels: Set<String>
        var didReadContext = false
        var answeredBeforeContext = false
        var streamedText = ""
        var proposal: StudyAgentNoteProposal?
        var learningUpdate: StudyAgentLearningUpdate?
        var lastError: String?
        var progress: StudyAgentProgressHandler?
        var continuation: CheckedContinuation<StudyAgentReply, Error>?
        var completed: Result<StudyAgentReply, Error>?
        var watchdogTask: Task<Void, Never>?
    }

    private let executableOverride: URL?
    private let runtimeDirectory: URL
    private var providerConfiguration = PiAgentProviderConfiguration()
    private var process: Process?
    private var inputHandle: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var pendingCommands: [String: PendingCommand] = [:]
    private var activeRun: ActiveRun?
    private var stderrBuffer = ""
    private var startupFailure: PiAgentRuntimeError?
    private var idleShutdownTask: Task<Void, Never>?
    private let traceEnabled = ProcessInfo.processInfo.environment["WEIBEI_PI_TRACE"] == "1"

    public init(executableURL: URL? = nil, runtimeDirectory: URL? = nil) {
        executableOverride = executableURL
        self.runtimeDirectory = runtimeDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("WeiBei/AgentRuntime", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiAgentRuntime", isDirectory: true)
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
        guard activeRun == nil else { throw PiAgentRuntimeError.busy }
        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        try await ensureProcess()

        _ = try await sendCommand(type: "new_session", timeoutSeconds: 3)
        let context = StudyAgentContextEnvelope(request: request)
        try writeContext(context)
        await progress?(.readingContext)

        activeRun = ActiveRun(
            id: request.id,
            contextRevision: request.contextRevision,
            memoryRevision: request.learningContext.memoryRevision,
            workflow: request.resolvedWorkflow,
            allowedSourceLabels: sourceLabels(in: context, includeCourse: true),
            allowedNoteSourceLabels: sourceLabels(in: context, includeCourse: false),
            progress: progress
        )
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
        guard let runID = activeRun?.id else { return }
        await cancelRun(id: runID)
    }

    private func cancelRun(id runID: UUID) async {
        guard activeRun?.id == runID else { return }
        guard process != nil else {
            finishRun(id: runID, with: .failure(PiAgentRuntimeError.cancelled))
            return
        }

        do {
            _ = try await sendCommand(type: "abort", timeoutSeconds: 2)
        } catch {
            shutdownProcess(reason: PiAgentRuntimeError.cancelled)
            return
        }

        if activeRun?.id == runID {
            finishRun(id: runID, with: .failure(PiAgentRuntimeError.cancelled))
        }
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
            let state = try await sendCommand(type: "get_state", timeoutSeconds: 3)
            guard state.dataJSON != nil else {
                throw PiAgentRuntimeError.protocolFailure("get_state returned no data")
            }
            let commands = try await sendCommand(type: "get_commands", timeoutSeconds: 3)
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
            "--tools", "weibei_context,weibei_course_map,weibei_course_search,weibei_learning_memory,weibei_learning_update,weibei_note_proposal",
            "--no-extensions",
            "--extension", resources.extensionURL.path,
            "--no-skills",
            "--skill", resources.skillsURL.path,
            "--no-prompt-templates",
            "--no-themes",
            "--no-context-files",
            "--no-approve",
            "--system-prompt", resources.systemPrompt,
            "--thinking", providerConfiguration.thinkingLevel,
            "--name", "WeiBei",
        ]
        if let provider = providerConfiguration.provider, !provider.isEmpty {
            arguments.append(contentsOf: ["--provider", provider])
        }
        if let model = providerConfiguration.model, !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
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

    private func sourceLabels(in context: StudyAgentContextEnvelope, includeCourse: Bool) -> Set<String> {
        var labels = ["[笔记：\(context.note.title)]"]
        if let material = context.material {
            labels.append("[材料：\(material.title)]")
        }
        if let selection = context.selection {
            labels.append("[选区：\(selection.title)]")
        }
        if includeCourse {
            labels.append(contentsOf: context.course.catalog.map { item in
                item.role == "note" ? "[笔记：\(item.title)]" : "[材料：\(item.title)]"
            })
            labels.append("[学习记录：上次位置]")
            labels.append("[学习记忆：用户状态]")
            labels.append("[会话：当前]")
        }
        return Set(labels)
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
        for key in ["LANG", "LC_ALL"] {
            if let value = hostEnvironment[key], value.count <= 128, !value.contains("\n") {
                environment[key] = value
            }
        }
        if let apiKey = providerConfiguration.apiKey, !apiKey.isEmpty {
            environment["OPENAI_API_KEY"] = apiKey
        }
        return environment
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

        let source = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent", isDirectory: true)

        if source.standardizedFileURL != destination.standardizedFileURL {
            seedLocalPiAuth(from: source, to: destination)
            seedLocalPiSettings(from: source, to: destination)
        }
        return destination
    }

    private func seedLocalPiAuth(from sourceDirectory: URL, to destinationDirectory: URL) {
        let fileManager = FileManager.default
        let destination = destinationDirectory.appendingPathComponent("auth.json")
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        let source = sourceDirectory.appendingPathComponent("auth.json")
        guard let attributes = try? fileManager.attributesOfItem(atPath: source.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue <= 1_048_576,
              let data = try? Data(contentsOf: source),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return }
        do {
            try data.write(to: destination, options: [.atomic])
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            trace("could not seed isolated PI auth: \(error.localizedDescription)")
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
                        await self?.trace("stdout line bytes=\(line.count)")
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
            await run.progress?(.text(run.streamedText))

        case let .assistantError(message):
            guard var run = activeRun else { return }
            run.lastError = sanitizedDiagnostic(message)
            activeRun = run
            refreshRunWatchdog()

        case let .toolStarted(_, name):
            guard let run = activeRun else { return }
            let allowedTools = Set([
                "weibei_context",
                "weibei_course_map",
                "weibei_course_search",
                "weibei_learning_memory",
                "weibei_learning_update",
                "weibei_note_proposal",
            ])
            guard allowedTools.contains(name) else {
                finishRun(
                    id: run.id,
                    with: .failure(PiAgentRuntimeError.agentFailed("PI attempted an unavailable tool: \(name)"))
                )
                return
            }
            refreshRunWatchdog()
            await run.progress?(.usingTool(name))

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
            run.learningUpdate = update
            activeRun = run
            refreshRunWatchdog()

        case let .toolFailed(_, name, message):
            guard var run = activeRun else { return }
            run.lastError = "\(name): \(sanitizedDiagnostic(message))"
            activeRun = run
            refreshRunWatchdog()

        case let .agentEnded(text, stopReason):
            guard let run = activeRun else { return }
            let cleanText = (text.isEmpty ? run.streamedText : text).trimmingCharacters(in: .whitespacesAndNewlines)
            if stopReason == "aborted" {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.cancelled))
            } else if stopReason == "error" {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed(run.lastError ?? "Unknown model error")))
            } else if run.answeredBeforeContext {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed("PI answered before reading the current WeiBei context")))
            } else if !run.didReadContext {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed("PI did not read the current WeiBei context")))
            } else if run.workflow == .noteMaking, run.proposal == nil {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed("PI returned no revision-matched note proposal")))
            } else if run.workflow != .noteMaking,
                      !run.allowedSourceLabels.contains(where: { cleanText.contains($0) }) {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed("PI returned an answer without a current-source label")))
            } else if cleanText.isEmpty, let proposal = run.proposal {
                finishRun(
                    id: run.id,
                    with: .success(
                        StudyAgentReply(
                            text: proposal.markdown,
                            backend: .pi,
                            noteProposal: proposal,
                            learningUpdate: run.learningUpdate
                        )
                    )
                )
            } else if cleanText.isEmpty {
                finishRun(id: run.id, with: .failure(PiAgentRuntimeError.agentFailed(run.lastError ?? "PI returned no readable text")))
            } else {
                finishRun(
                    id: run.id,
                    with: .success(
                        StudyAgentReply(
                            text: cleanText,
                            backend: .pi,
                            noteProposal: run.proposal,
                            learningUpdate: run.learningUpdate
                        )
                    )
                )
            }

        case let .extensionError(message):
            let message = sanitizedDiagnostic(message)
            if let runID = activeRun?.id {
                finishRun(id: runID, with: .failure(PiAgentRuntimeError.agentFailed(message)))
            } else {
                startupFailure = .launchFailed(message)
            }

        case .event:
            refreshRunWatchdog()
        }
    }

    private func finishRun(id: UUID, with result: Result<StudyAgentReply, Error>) {
        guard var run = activeRun, run.id == id, run.completed == nil else { return }
        run.watchdogTask?.cancel()
        run.watchdogTask = nil
        clearContextSnapshot()
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
        run.watchdogTask?.cancel()
        activeRun = nil
        clearContextSnapshot()
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
        let missing = PiAgentResources.requiredSkillNames.filter {
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
        run.watchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300 * 1_000_000_000)
            } catch {
                return
            }
            await self?.runTimedOut(id: runID)
        }
        activeRun = run
    }

    private func runTimedOut(id: UUID) async {
        guard activeRun?.id == id else { return }
        finishRun(id: id, with: .failure(PiAgentRuntimeError.agentFailed("PI produced no events for five minutes")))
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
