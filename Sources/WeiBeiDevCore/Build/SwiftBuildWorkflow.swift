import Foundation

/// Products directory returned by one configured SwiftPM build.
public struct SwiftBuildResult: Equatable, Sendable {
    public let configuration: SwiftBuildConfiguration
    public let productsDirectory: URL

    /// Creates a SwiftPM build result.
    public init(configuration: SwiftBuildConfiguration, productsDirectory: URL) {
        self.configuration = configuration
        self.productsDirectory = productsDirectory
    }

    /// Resolves a named executable from this build.
    ///
    /// - Parameter name: SwiftPM executable product name.
    /// - Returns: Absolute executable product path.
    public func executable(named name: String) -> URL {
        productsDirectory.appendingPathComponent(name, isDirectory: false)
    }
}

/// Builds the Swift package once and resolves that build's product directory.
public struct SwiftBuildWorkflow: @unchecked Sendable {
    private let repository: RepositoryLayout
    private let toolchain: BuildToolchain
    private let processExecutor: any ProcessExecuting
    private let fileManager: FileManager

    /// Creates a SwiftPM build workflow.
    public init(
        repository: RepositoryLayout,
        toolchain: BuildToolchain,
        processExecutor: any ProcessExecuting,
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.toolchain = toolchain
        self.processExecutor = processExecutor
        self.fileManager = fileManager
    }

    /// Builds one configuration and asks SwiftPM for its product directory.
    ///
    /// `--show-bin-path` is invoked only after the configured build succeeds
    /// and is used for direct execution of the resulting binaries.
    ///
    /// - Parameter configuration: Fixed SwiftPM build configuration.
    /// - Returns: Configuration and normalized product directory.
    public func build(configuration: SwiftBuildConfiguration) async throws -> SwiftBuildResult {
        let buildRequest = ProcessExecutionRequest(
            executableURL: toolchain.swift,
            arguments: ["build", "-c", configuration.rawValue],
            workingDirectoryURL: repository.rootDirectory,
            timeout: .seconds(1_800)
        )
        try await executeSuccessfully(buildRequest)

        let pathRequest = ProcessExecutionRequest(
            executableURL: toolchain.swift,
            arguments: ["build", "-c", configuration.rawValue, "--show-bin-path"],
            workingDirectoryURL: repository.rootDirectory,
            timeout: .seconds(60)
        )
        let pathResult = try await executeSuccessfully(pathRequest)
        let output = pathResult.standardOutput?.stringUTF8
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !output.isEmpty else {
            throw BuildWorkflowError.invalidBuildProductsDirectory(output)
        }
        let productsDirectory = URL(fileURLWithPath: output, isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard productsDirectory.path.hasPrefix("/"),
              fileManager.fileExists(atPath: productsDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw BuildWorkflowError.invalidBuildProductsDirectory(output)
        }
        return SwiftBuildResult(
            configuration: configuration,
            productsDirectory: productsDirectory
        )
    }

    /// Executes a build command and converts nonzero termination into a stable error.
    @discardableResult
    /// Runs one SwiftPM command and normalizes unsuccessful termination.
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
