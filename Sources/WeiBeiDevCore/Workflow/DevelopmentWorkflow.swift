import Darwin
import Foundation

/// Run behavior selected by the command-line adapter.
public enum DevelopmentRunMode: Equatable, Sendable {
    case standard
    case debug
    case logs
    case telemetry
}

/// Scenario selection and failure policy for a verification run.
public struct DevelopmentVerificationOptions: Sendable {
    public let scenario: String?
    public let allScenarios: Bool
    public let includeLivePI: Bool
    public let visual: Bool
    public let failFast: Bool

    /// Creates a verification request after command-line syntax validation.
    public init(
        scenario: String?,
        allScenarios: Bool,
        includeLivePI: Bool,
        visual: Bool,
        failFast: Bool
    ) {
        self.scenario = scenario
        self.allScenarios = allScenarios
        self.includeLivePI = includeLivePI
        self.visual = visual
        self.failFast = failFast
    }
}

/// Stable failures produced while composing the developer workflows.
public enum DevelopmentWorkflowError: Error, LocalizedError, Sendable {
    case commandFailed(tool: String, termination: ProcessTermination, standardError: String)
    case lifecycleBusy(URL)
    case applicationRunning
    case unknownScenario(String)
    case verificationFailed(report: URL, failedScenarios: [String])

    public var errorCode: String {
        switch self {
        case .commandFailed:
            return "command_failed"
        case .lifecycleBusy:
            return "lifecycle_busy"
        case .applicationRunning:
            return "application_running"
        case .unknownScenario:
            return "unknown_scenario"
        case .verificationFailed:
            return "verification_failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(tool, termination, standardError):
            let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(tool) failed: \(termination)"
                : "\(tool) failed: \(termination): \(detail)"
        case let .lifecycleBusy(lockURL):
            return "Another WeiBei run, verify, or package operation owns \(lockURL.path)."
        case .applicationRunning:
            return "魏碑 is running. Quit it before replacing dist/魏碑.app."
        case let .unknownScenario(name):
            return "Unknown verification scenario: \(name)."
        case let .verificationFailed(report, failedScenarios):
            return "Verification failed for \(failedScenarios.joined(separator: ", ")). Report: \(report.path)"
        }
    }
}

/// Cross-process lease shared by run, verify, and package.
public final class DevelopmentLifecycleLease: @unchecked Sendable {
    private let lockURL: URL
    private let descriptor: Int32
    private let stateLock = NSLock()
    private var released = false

    /// Creates a lifecycle lease around an already locked descriptor.
    private init(lockURL: URL, descriptor: Int32) {
        self.lockURL = lockURL
        self.descriptor = descriptor
    }

    deinit {
        release()
    }

    /// Atomically acquires the lifecycle lease.
    public static func acquire(
        at lockURL: URL,
        fileManager: FileManager = .default
    ) throws -> DevelopmentLifecycleLease {
        try fileManager.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: lockURL.path]
            )
        }
        guard systemFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw DevelopmentWorkflowError.lifecycleBusy(lockURL)
        }
        writeOwnerPID(to: descriptor)
        return DevelopmentLifecycleLease(lockURL: lockURL, descriptor: descriptor)
    }

    /// Releases the lifecycle lease exactly once.
    public func release() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !released else {
            return
        }
        _ = systemFlock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        released = true
    }

    /// Stores the current PID for diagnostics without participating in lock ownership.
    private static func writeOwnerPID(to descriptor: Int32) {
        let owner = Data("\(ProcessInfo.processInfo.processIdentifier)\n".utf8)
        guard Darwin.ftruncate(descriptor, 0) == 0,
              Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else {
            return
        }
        owner.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            _ = Darwin.write(descriptor, baseAddress, bytes.count)
        }
    }
}

/// Composes build, runtime, verification, packaging, and process services.
public struct DevelopmentWorkflow {
    public let repository: RepositoryLayout
    private let toolchain: BuildToolchain
    private let processExecutor: any ProcessExecuting
    private let piRuntimePreparer: PiRuntimePreparer
    private let fileManager: FileManager
    private let lifecycleLockURL: URL
    private let temporaryRootURL: URL

    /// Creates a production workflow rooted at an already validated repository.
    public init(
        repository: RepositoryLayout,
        toolchain: BuildToolchain,
        processExecutor: any ProcessExecuting,
        fileManager: FileManager = .default,
        lifecycleLockURL: URL? = nil,
        temporaryRootURL: URL? = nil
    ) {
        self.repository = repository
        self.toolchain = toolchain
        self.processExecutor = processExecutor
        self.fileManager = fileManager
        piRuntimePreparer = PiRuntimePreparer(processExecutor: processExecutor, fileManager: fileManager)
        let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.lifecycleLockURL = lifecycleLockURL
            ?? cacheRoot.appendingPathComponent("WeiBeiDevTool/lifecycle.lock", isDirectory: true)
        self.temporaryRootURL = temporaryRootURL
            ?? fileManager.temporaryDirectory.appendingPathComponent("weibei-dev-tool", isDirectory: true)
    }

    /// Installs locked Node dependencies and regenerates WebEditor resources.
    public func prepareWebEditor() async throws -> WebEditorPreparationResult {
        try await WebEditorPreparationWorkflow(
            repository: repository,
            toolchain: NodeBuildToolchain(node: toolchain.node, npm: toolchain.npm),
            processExecutor: processExecutor
        ).prepare()
    }

    /// Installs locked Node dependencies and regenerates Rich Answer resources.
    public func prepareRichAnswer() async throws -> RichAnswerPreparationResult {
        try await RichAnswerPreparationWorkflow(
            repository: repository,
            toolchain: NodeBuildToolchain(node: toolchain.node, npm: toolchain.npm),
            processExecutor: processExecutor
        ).prepare()
    }

    /// Downloads or reuses the manifest-pinned PI runtime and validates it.
    public func preparePiRuntime() async throws -> PreparedPiRuntime {
        try await piRuntimePreparer.prepare(
            configuration: PiRuntimePreparationConfiguration(repositoryRoot: repository.rootDirectory)
        )
    }

    /// Prepares all generated application resources and the PI runtime.
    ///
    /// `prepareWebEditor` invokes `build:app-resources`, which builds the editor,
    /// OAuth helper, and Rich Answer runtime from the locked TypeScript toolchain.
    public func prepareAll() async throws -> PreparedPiRuntime {
        _ = try await prepareWebEditor()
        return try await preparePiRuntime()
    }

    /// Runs the debug build, Swift package tests, and product verifiers.
    public func check() async throws -> CheckWorkflowResult {
        let runtime = try await preparePiRuntime()
        return try await CheckWorkflow(
            repository: repository,
            toolchain: toolchain,
            processExecutor: processExecutor,
            fileManager: fileManager
        ).run(piExecutable: runtime.executableURL)
    }

    /// Builds, packages to an isolated location, and launches WeiBei.
    public func run(mode: DevelopmentRunMode) async throws -> URL {
        let lease = try DevelopmentLifecycleLease.acquire(at: lifecycleLockURL, fileManager: fileManager)
        defer { lease.release() }

        let killResult = try await processExecutor.execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/pkill"),
                arguments: ["-x", "WeiBei"],
                standardOutput: .discard,
                standardError: .discard,
                timeout: .seconds(15)
            )
        )
        guard killResult.succeeded || killResult.exitCode == 1 else {
            throw DevelopmentWorkflowError.commandFailed(
                tool: "pkill -x WeiBei",
                termination: killResult.termination,
                standardError: killResult.standardError?.stringUTF8 ?? ""
            )
        }

        let configuration: SwiftBuildConfiguration = mode == .debug ? .debug : .release
        let appBundle = try await buildPackagedApp(
            configuration: configuration,
            distributionDirectory: temporaryRootURL.appendingPathComponent("run", isDirectory: true)
        ).appBundle

        switch mode {
        case .standard:
            try await executeSuccessfully(
                executable: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: [appBundle.path],
                tool: "open"
            )
        case .debug:
            try await executeSuccessfully(
                executable: try resolveExecutable(named: "lldb"),
                arguments: ["--", appBundle.appendingPathComponent("Contents/MacOS/WeiBei").path],
                tool: "lldb",
                inheritIO: true
            )
        case .logs:
            try await executeSuccessfully(
                executable: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: [appBundle.path],
                tool: "open"
            )
            try await executeSuccessfully(
                executable: URL(fileURLWithPath: "/usr/bin/log"),
                arguments: ["stream", "--info", "--style", "compact", "--predicate", "process == \"WeiBei\""],
                tool: "log stream",
                inheritIO: true
            )
        case .telemetry:
            try await executeSuccessfully(
                executable: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: [appBundle.path],
                tool: "open"
            )
            try await executeSuccessfully(
                executable: URL(fileURLWithPath: "/usr/bin/log"),
                arguments: ["stream", "--info", "--style", "compact", "--predicate", "subsystem == \"com.changfenhuang.weibei\""],
                tool: "log stream",
                inheritIO: true
            )
        }
        return appBundle
    }

    /// Packages a release app in isolation and runs selected real-window scenarios.
    public func verify(options: DevelopmentVerificationOptions) async throws -> VerificationRunReport {
        let lease = try DevelopmentLifecycleLease.acquire(at: lifecycleLockURL, fileManager: fileManager)
        defer { lease.release() }

        let appBundle = try await buildPackagedApp(
            configuration: .release,
            distributionDirectory: temporaryRootURL.appendingPathComponent("verify", isDirectory: true)
        ).appBundle
        let registry = VerificationScenarioRegistry()
        let scenarios: [VerificationScenario]
        if let scenarioName = options.scenario {
            guard let scenario = registry.scenario(named: scenarioName) else {
                throw DevelopmentWorkflowError.unknownScenario(scenarioName)
            }
            scenarios = [scenario]
        } else if options.allScenarios {
            scenarios = registry.allScenarios(includeLivePI: options.includeLivePI)
        } else {
            scenarios = registry.defaultScenarios
        }

        let artifactsRoot = repository.rootDirectory
            .appendingPathComponent(".build/weibei-dev-tool/verification", isDirectory: true)
        let artifactStore = try VerificationArtifactStore(rootURL: artifactsRoot)
        let report = try await VerificationRunner().run(
            configuration: VerificationRunConfiguration(
                appExecutableURL: appBundle.appendingPathComponent("Contents/MacOS/WeiBei"),
                workingDirectoryURL: repository.rootDirectory,
                scenarios: scenarios,
                performVisualInspection: options.visual,
                allowLivePI: options.includeLivePI,
                failFast: options.failFast
            ),
            artifactStore: artifactStore
        )
        guard report.succeeded else {
            throw DevelopmentWorkflowError.verificationFailed(
                report: artifactStore.runURL.appendingPathComponent("report.json"),
                failedScenarios: report.results
                    .filter { $0.status == .failed }
                    .map(\.scenarioID.rawValue)
            )
        }
        return report
    }

    /// Transactionally publishes a release app to `dist/魏碑.app`.
    public func package() async throws -> AppBundlePackageResult {
        let lease = try DevelopmentLifecycleLease.acquire(at: lifecycleLockURL, fileManager: fileManager)
        defer { lease.release() }

        let running = try await processExecutor.execute(
            ProcessExecutionRequest(
                executableURL: URL(fileURLWithPath: "/usr/bin/pgrep"),
                arguments: ["-x", "WeiBei"],
                standardOutput: .discard,
                standardError: .discard,
                timeout: .seconds(15)
            )
        )
        if running.succeeded {
            throw DevelopmentWorkflowError.applicationRunning
        }
        guard running.exitCode == 1 else {
            throw DevelopmentWorkflowError.commandFailed(
                tool: "pgrep -x WeiBei",
                termination: running.termination,
                standardError: running.standardError?.stringUTF8 ?? ""
            )
        }

        return try await buildPackagedApp(
            configuration: .release,
            distributionDirectory: repository.rootDirectory.appendingPathComponent("dist", isDirectory: true)
        )
    }

    /// Prepares inputs, builds once, and packages into the requested destination.
    private func buildPackagedApp(
        configuration: SwiftBuildConfiguration,
        distributionDirectory: URL
    ) async throws -> AppBundlePackageResult {
        _ = try await prepareWebEditor()
        let runtime = try await preparePiRuntime()
        let build = try await SwiftBuildWorkflow(
            repository: repository,
            toolchain: toolchain,
            processExecutor: processExecutor,
            fileManager: fileManager
        ).build(configuration: configuration)
        let metadata = try await GitBuildMetadataResolver(
            processExecutor: processExecutor,
            fileManager: fileManager
        ).resolve(repositoryRoot: repository.rootDirectory)
        let stagingRoot = temporaryRootURL.appendingPathComponent(
            "staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let request = AppBundlePackageRequest(
            repositoryRoot: repository.rootDirectory,
            buildProductsDirectory: build.productsDirectory,
            piRuntimeDirectory: runtime.directoryURL,
            stagingRoot: stagingRoot,
            distributionDirectory: distributionDirectory
        )
        return try await AppBundlePackager().package(
            request: request,
            metadata: metadata,
            validator: SystemAppBundleValidator(processExecutor: processExecutor, fileManager: fileManager)
        )
    }

    /// Runs one launch-side tool and converts termination into a stable workflow error.
    private func executeSuccessfully(
        executable: URL,
        arguments: [String],
        tool: String,
        inheritIO: Bool = false
    ) async throws {
        let output: ProcessOutputDestination = inheritIO ? .inherit : .capture(limit: 1_048_576)
        let result = try await processExecutor.execute(
            ProcessExecutionRequest(
                executableURL: executable,
                arguments: arguments,
                workingDirectoryURL: repository.rootDirectory,
                standardInput: inheritIO ? .inherit : .null,
                standardOutput: output,
                standardError: output
            )
        )
        guard result.succeeded else {
            throw DevelopmentWorkflowError.commandFailed(
                tool: tool,
                termination: result.termination,
                standardError: result.standardError?.stringUTF8 ?? ""
            )
        }
    }

    /// Resolves an interactive developer tool directly from PATH.
    private func resolveExecutable(named name: String) throws -> URL {
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: false) {
            let candidate = URL(
                fileURLWithPath: directory.isEmpty ? "." : String(directory),
                isDirectory: true
            ).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate.standardizedFileURL
            }
        }
        throw BuildWorkflowError.missingExecutable(name)
    }
}
