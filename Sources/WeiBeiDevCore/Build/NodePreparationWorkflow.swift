import Foundation

/// Result of ensuring locked Node.js dependencies are installed.
public struct NodePreparationResult: Equatable, Sendable {
    public let version: NodeVersion
    public let installedDependencies: Bool

    /// Creates the result of a Node.js dependency preparation.
    public init(version: NodeVersion, installedDependencies: Bool) {
        self.version = version
        self.installedDependencies = installedDependencies
    }
}

/// Validates Node.js and installs locked npm dependencies when inputs change.
public struct NodePreparationWorkflow: Sendable {
    private let repository: RepositoryLayout
    private let toolchain: NodeBuildToolchain
    private let processExecutor: any ProcessExecuting
    private let stampStore: NodeDependencyStampStore

    /// Creates a Node.js dependency preparation workflow.
    public init(
        repository: RepositoryLayout,
        toolchain: NodeBuildToolchain,
        processExecutor: any ProcessExecuting,
        stampStore: NodeDependencyStampStore = NodeDependencyStampStore()
    ) {
        self.repository = repository
        self.toolchain = toolchain
        self.processExecutor = processExecutor
        self.stampStore = stampStore
    }

    /// Ensures the repository has dependencies installed for Node.js 22 or later.
    ///
    /// `npm ci` runs only when the lockfile digest or complete Node.js version
    /// differs from the recorded installation inputs.
    ///
    /// - Returns: Active Node.js version and whether installation occurred.
    public func prepare() async throws -> NodePreparationResult {
        guard FileManager.default.fileExists(atPath: repository.packageJSON.path) else {
            throw BuildWorkflowError.missingRequiredFile(repository.packageJSON)
        }
        guard FileManager.default.fileExists(atPath: repository.packageLock.path) else {
            throw BuildWorkflowError.missingRequiredFile(repository.packageLock)
        }

        let versionCommand = ProcessExecutionRequest(
            executableURL: toolchain.node,
            arguments: ["--version"],
            workingDirectoryURL: repository.rootDirectory,
            timeout: .seconds(30)
        )
        let versionResult = try await processExecutor.execute(versionCommand)
        try requireSuccess(versionResult, request: versionCommand)
        let version = try NodeVersion.parse(versionResult.standardOutput?.stringUTF8 ?? "")
        try version.requireSupportedMajor()
        let expectedStamp = try stampStore.expectedStamp(
            nodeVersion: version,
            packageLock: repository.packageLock
        )

        guard stampStore.needsInstallation(
            expectedStamp: expectedStamp,
            stampURL: repository.nodePreparationStamp
        ) else {
            return NodePreparationResult(version: version, installedDependencies: false)
        }

        let installCommand = ProcessExecutionRequest(
            executableURL: toolchain.npm,
            arguments: ["ci"],
            workingDirectoryURL: repository.rootDirectory,
            timeout: .seconds(1_800)
        )
        let installResult = try await processExecutor.execute(installCommand)
        try requireSuccess(installResult, request: installCommand)
        try stampStore.write(expectedStamp, to: repository.nodePreparationStamp)
        return NodePreparationResult(version: version, installedDependencies: true)
    }

    /// Converts an unsuccessful process result into a stable build error.
    private func requireSuccess(
        _ result: ProcessExecutionResult,
        request: ProcessExecutionRequest
    ) throws {
        guard result.succeeded else {
            throw BuildWorkflowError.commandFailed(
                command: ([request.executableURL.path] + request.arguments).joined(separator: " "),
                exitDescription: String(describing: result.termination),
                standardError: (result.standardError?.stringUTF8 ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
