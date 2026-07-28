import Foundation

/// Result of preparing the Rich Answer runtime resources.
public struct RichAnswerPreparationResult: Equatable, Sendable {
    public let node: NodePreparationResult
    public let products: RichAnswerBuildProducts

    /// Creates a Rich Answer preparation result.
    public init(node: NodePreparationResult, products: RichAnswerBuildProducts) {
        self.node = node
        self.products = products
    }
}

/// Installs locked Node.js dependencies and regenerates Rich Answer resources.
public struct RichAnswerPreparationWorkflow: Sendable {
    private let repository: RepositoryLayout
    private let toolchain: NodeBuildToolchain
    private let processExecutor: any ProcessExecuting
    private let nodePreparation: NodePreparationWorkflow

    /// Creates a Rich Answer preparation workflow.
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

    /// Regenerates and validates the Rich Answer resources embedded by WeiBei.
    ///
    /// - Returns: Node preparation details and validated product paths.
    public func prepare() async throws -> RichAnswerPreparationResult {
        let nodeResult = try await nodePreparation.prepare()
        let buildCommand = ProcessExecutionRequest(
            executableURL: toolchain.npm,
            arguments: ["run", "build:rich-answer"],
            workingDirectoryURL: repository.rootDirectory,
            timeout: .seconds(600)
        )
        let buildResult = try await processExecutor.execute(buildCommand)
        guard buildResult.succeeded else {
            throw BuildWorkflowError.commandFailed(
                command: ([buildCommand.executableURL.path] + buildCommand.arguments)
                    .joined(separator: " "),
                exitDescription: String(describing: buildResult.termination),
                standardError: (buildResult.standardError?.stringUTF8 ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        let products = RichAnswerBuildProducts(repository: repository)
        try products.validate()
        return RichAnswerPreparationResult(node: nodeResult, products: products)
    }
}
