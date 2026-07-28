import Foundation

/// Summary of the complete Swift/macOS repository check.
public struct CheckWorkflowResult: Equatable, Sendable {
    public let webEditor: WebEditorPreparationResult
    public let swiftBuild: SwiftBuildResult
    public let verifiedExecutables: [String]

    /// Creates a check workflow summary.
    public init(
        webEditor: WebEditorPreparationResult,
        swiftBuild: SwiftBuildResult,
        verifiedExecutables: [String]
    ) {
        self.webEditor = webEditor
        self.swiftBuild = swiftBuild
        self.verifiedExecutables = verifiedExecutables
    }
}

/// Runs the debug Swift checks against products from one configured build.
public struct CheckWorkflow: @unchecked Sendable {
    private let repository: RepositoryLayout
    private let toolchain: BuildToolchain
    private let processExecutor: any ProcessExecuting
    private let fileManager: FileManager
    private let webEditorPreparation: WebEditorPreparationWorkflow
    private let swiftBuild: SwiftBuildWorkflow

    /// Creates the repository check workflow.
    public init(
        repository: RepositoryLayout,
        toolchain: BuildToolchain,
        processExecutor: any ProcessExecuting,
        fileManager: FileManager = .default,
        stampStore: NodeDependencyStampStore = NodeDependencyStampStore()
    ) {
        self.repository = repository
        self.toolchain = toolchain
        self.processExecutor = processExecutor
        self.fileManager = fileManager
        webEditorPreparation = WebEditorPreparationWorkflow(
            repository: repository,
            toolchain: NodeBuildToolchain(node: toolchain.node, npm: toolchain.npm),
            processExecutor: processExecutor,
            stampStore: stampStore
        )
        swiftBuild = SwiftBuildWorkflow(
            repository: repository,
            toolchain: toolchain,
            processExecutor: processExecutor,
            fileManager: fileManager
        )
    }

    /// Runs the Swift package tests and existing product verifiers from one debug build.
    ///
    /// The PI runtime is prepared by the runtime workflow before calling this
    /// method and is passed explicitly to all checks that consume it.
    ///
    /// - Parameter piExecutable: Executable from the validated PI runtime cache.
    /// - Returns: Build products and verifier names completed successfully.
    public func run(piExecutable: URL) async throws -> CheckWorkflowResult {
        guard fileManager.isExecutableFile(atPath: piExecutable.path) else {
            throw BuildWorkflowError.missingBuildProduct(piExecutable)
        }

        let editorResult = try await webEditorPreparation.prepare()
        let buildResult = try await swiftBuild.build(configuration: .debug)

        let testRequest = ProcessExecutionRequest(
            executableURL: toolchain.swift,
            arguments: ["test", "-c", SwiftBuildConfiguration.debug.rawValue],
            workingDirectoryURL: repository.rootDirectory,
            timeout: .seconds(1_800)
        )
        try await executeSuccessfully(testRequest)

        let verifiers: [(name: String, arguments: [String], environment: [String: String])] = [
            (
                name: "WeiBeiSelfCheck",
                arguments: [],
                environment: ["WEIBEI_PI_EXECUTABLE": piExecutable.path]
            ),
            (
                name: "WeiBei",
                arguments: ["--self-check-imported-identity"],
                environment: [
                    "WEIBEI_PI_EXECUTABLE": piExecutable.path,
                    "WEIBEI_SUPPRESS_ACTIVATION": "1",
                ]
            ),
            (
                name: "WeiBeiWebEditorCheck",
                arguments: [],
                environment: [:]
            ),
            (
                name: "WeiBeiPiCheck",
                arguments: [],
                environment: [
                    "WEIBEI_PI_EXECUTABLE": piExecutable.path,
                    "WEIBEI_PI_LIVE_CHECK": "0",
                ]
            ),
        ]

        for verifier in verifiers {
            let executable = buildResult.executable(named: verifier.name)
            guard fileManager.isExecutableFile(atPath: executable.path) else {
                throw BuildWorkflowError.missingBuildProduct(executable)
            }
            let request = ProcessExecutionRequest(
                executableURL: executable,
                arguments: verifier.arguments,
                workingDirectoryURL: repository.rootDirectory,
                environment: .inheritAndOverride(verifier.environment),
                timeout: .seconds(600)
            )
            try await executeSuccessfully(request)
        }

        return CheckWorkflowResult(
            webEditor: editorResult,
            swiftBuild: buildResult,
            verifiedExecutables: verifiers.map(\.name)
        )
    }

    /// Executes a check process and converts nonzero termination into a stable error.
    @discardableResult
    /// Runs one verifier and normalizes a nonzero termination into a stable build error.
    private func executeSuccessfully(
        _ request: ProcessExecutionRequest
    ) async throws -> ProcessExecutionResult {
        let result = try await processExecutor.execute(request)
        guard result.succeeded else {
            throw BuildWorkflowError.commandFailed(
                command: ([request.executableURL.path] + request.arguments).joined(separator: " "),
                exitDescription: String(describing: result.termination),
                standardError: (result.standardError?.stringUTF8 ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result
    }
}
