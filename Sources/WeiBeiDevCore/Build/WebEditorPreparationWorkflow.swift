import Foundation

/// Result of preparing the WebEditor resource bundle.
public struct WebEditorPreparationResult: Equatable, Sendable {
    public let node: NodePreparationResult
    public let products: WebEditorBuildProducts

    /// Creates a WebEditor preparation result.
    public init(node: NodePreparationResult, products: WebEditorBuildProducts) {
        self.node = node
        self.products = products
    }
}

/// Installs locked Node.js dependencies and regenerates WebEditor resources.
public struct WebEditorPreparationWorkflow: Sendable {
    private let repository: RepositoryLayout
    private let toolchain: NodeBuildToolchain
    private let processExecutor: any ProcessExecuting
    private let nodePreparation: NodePreparationWorkflow

    /// Creates a WebEditor preparation workflow.
    public init(
        repository: RepositoryLayout,
        toolchain: NodeBuildToolchain,
        processExecutor: any ProcessExecuting,
        stampStore: NodeDependencyStampStore = NodeDependencyStampStore()
    ) {
        self.repository = repository
        self.toolchain = toolchain
        self.processExecutor = processExecutor
        nodePreparation = NodePreparationWorkflow(
            repository: repository,
            toolchain: toolchain,
            processExecutor: processExecutor,
            stampStore: stampStore
        )
    }

    /// Regenerates and validates the browser resources embedded by WeiBei.
    ///
    /// - Returns: Node preparation details and validated product paths.
    public func prepare() async throws -> WebEditorPreparationResult {
        let nodeResult = try await nodePreparation.prepare()
        let buildCommand = ProcessExecutionRequest(
            executableURL: toolchain.npm,
            arguments: ["run", "build:app-resources"],
            workingDirectoryURL: repository.rootDirectory,
            timeout: .seconds(600)
        )
        let buildResult = try await processExecutor.execute(buildCommand)
        guard buildResult.succeeded else {
            throw BuildWorkflowError.commandFailed(
                command: ([buildCommand.executableURL.path] + buildCommand.arguments).joined(separator: " "),
                exitDescription: String(describing: buildResult.termination),
                standardError: (buildResult.standardError?.stringUTF8 ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let products = WebEditorBuildProducts(repository: repository)
        try products.validate()
        return WebEditorPreparationResult(node: nodeResult, products: products)
    }
}
