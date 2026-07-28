import Foundation
import WeiBeiDevCore

/// Production adapter that maps CLI requests onto the testable core workflow.
public struct ProductionWorkflowProvider: WorkflowProviding {
    private let currentDirectoryURL: URL
    private let environment: [String: String]

    /// Creates an adapter using the process working directory and environment.
    public init(
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.currentDirectoryURL = currentDirectoryURL
        self.environment = environment
    }

    /// Locates the repository, creates production dependencies, and executes one request.
    public func execute(_ request: DevToolCommandRequest) async throws -> DevToolWorkflowResult {
        do {
            let repository = try RepositoryLayout.locate(currentDirectory: currentDirectoryURL)
            let processExecutor = FoundationProcessExecutor()
            if request == .prepare(.piRuntime) {
                let runtime = try await PiRuntimePreparer(
                    processExecutor: processExecutor
                ).prepare(
                    configuration: PiRuntimePreparationConfiguration(
                        repositoryRoot: repository.rootDirectory
                    )
                )
                return runtimeResult(runtime)
            }
            if request == .prepare(.webEditor) {
                let nodeToolchain = try NodeBuildToolchain.resolve(environment: environment)
                let result = try await WebEditorPreparationWorkflow(
                    repository: repository,
                    toolchain: nodeToolchain,
                    processExecutor: processExecutor
                ).prepare()
                return DevToolWorkflowResult(
                    summary: "WebEditor resources are ready.",
                    details: [
                        "editor": result.products.editorJavaScript.path,
                        "node": result.node.version.description,
                    ],
                    primaryPath: result.products.editorJavaScript.path
                )
            }
            if request == .prepare(.richAnswer) {
                let nodeToolchain = try NodeBuildToolchain.resolve(environment: environment)
                let result = try await RichAnswerPreparationWorkflow(
                    repository: repository,
                    toolchain: nodeToolchain,
                    processExecutor: processExecutor
                ).prepare()
                return DevToolWorkflowResult(
                    summary: "Rich Answer resources are ready.",
                    details: [
                        "html": result.products.html.path,
                        "node": result.node.version.description,
                        "runtime": result.products.javaScript.path,
                        "stylesheet": result.products.stylesheet.path,
                    ],
                    primaryPath: result.products.html.path
                )
            }
            let toolchain = try BuildToolchain.resolve(environment: environment)
            let workflow = DevelopmentWorkflow(
                repository: repository,
                toolchain: toolchain,
                processExecutor: processExecutor
            )

            switch request {
            case let .prepare(target):
                switch target {
                case .webEditor:
                    let result = try await workflow.prepareWebEditor()
                    return DevToolWorkflowResult(
                        summary: "WebEditor resources are ready.",
                        details: [
                            "editor": result.products.editorJavaScript.path,
                            "node": result.node.version.description,
                        ],
                        primaryPath: result.products.editorJavaScript.path
                    )
                case .richAnswer:
                    let result = try await workflow.prepareRichAnswer()
                    return DevToolWorkflowResult(
                        summary: "Rich Answer resources are ready.",
                        details: [
                            "html": result.products.html.path,
                            "node": result.node.version.description,
                            "runtime": result.products.javaScript.path,
                            "stylesheet": result.products.stylesheet.path,
                        ],
                        primaryPath: result.products.html.path
                    )
                case .piRuntime:
                    let runtime = try await workflow.preparePiRuntime()
                    return runtimeResult(runtime)
                case .all:
                    let runtime = try await workflow.prepareAll()
                    return DevToolWorkflowResult(
                        summary: "All development dependencies are ready.",
                        details: [
                            "piRuntime": runtime.directoryURL.path,
                            "piVersion": runtime.manifest.piVersion,
                        ],
                        primaryPath: runtime.directoryURL.path
                    )
                }
            case .check:
                let result = try await workflow.check()
                return DevToolWorkflowResult(
                    summary: "Swift build, tests, and product checks passed.",
                    details: [
                        "configuration": result.swiftBuild.configuration.rawValue,
                        "products": result.swiftBuild.productsDirectory.path,
                        "verifiers": result.verifiedExecutables.joined(separator: ","),
                    ],
                    primaryPath: result.swiftBuild.productsDirectory.path
                )
            case let .run(mode):
                let coreMode: DevelopmentRunMode
                switch mode {
                case .standard:
                    coreMode = .standard
                case .debug:
                    coreMode = .debug
                case .logs:
                    coreMode = .logs
                case .telemetry:
                    coreMode = .telemetry
                }
                let app = try await workflow.run(mode: coreMode)
                return DevToolWorkflowResult(
                    summary: "WeiBei run workflow completed.",
                    details: ["app": app.path, "mode": mode.rawValue],
                    primaryPath: app.path
                )
            case let .verify(options):
                let report = try await workflow.verify(
                    options: DevelopmentVerificationOptions(
                        scenario: options.scenario,
                        allScenarios: options.runsAllScenarios,
                        includeLivePI: options.includesLivePi,
                        visual: options.performsVisualChecks,
                        failFast: options.failsFast
                    )
                )
                return DevToolWorkflowResult(
                    summary: "Verification passed.",
                    details: [
                        "artifacts": report.artifactDirectory,
                        "scenarios": report.results.map(\.scenarioID.rawValue).joined(separator: ","),
                    ],
                    primaryPath: report.artifactDirectory
                )
            case .package:
                let result = try await workflow.package()
                return DevToolWorkflowResult(
                    summary: "dist/魏碑.app was published transactionally.",
                    details: [
                        "app": result.appBundle.path,
                        "build": String(result.metadata.buildNumber),
                        "commit": result.metadata.gitCommit,
                        "dirty": String(result.metadata.sourceDirty),
                        "uuid": result.executableUUID,
                        "version": result.metadata.version,
                    ],
                    primaryPath: result.appBundle.path
                )
            }
        } catch {
            throw Self.coded(error)
        }
    }

    /// Renders a prepared runtime with stable machine-readable details.
    private func runtimeResult(_ runtime: PreparedPiRuntime) -> DevToolWorkflowResult {
        DevToolWorkflowResult(
            summary: "PI runtime is ready.",
            details: [
                "architecture": runtime.architecture.rawValue,
                "executable": runtime.executableURL.path,
                "runtime": runtime.directoryURL.path,
                "version": runtime.manifest.piVersion,
            ],
            primaryPath: runtime.directoryURL.path
        )
    }

    /// Maps core-domain failures to the CLI's stable error-code contract.
    private static func coded(_ error: Error) -> DevToolExecutionError {
        if let error = error as? RepositoryLayoutError {
            return DevToolExecutionError(
                errorCode: error.errorCode,
                errorMessage: error.localizedDescription
            )
        }
        if let error = error as? BuildWorkflowError {
            return DevToolExecutionError(
                errorCode: error.errorCode,
                errorMessage: error.localizedDescription
            )
        }
        if let error = error as? PiRuntimePreparationError {
            return DevToolExecutionError(
                errorCode: error.code,
                errorMessage: error.localizedDescription
            )
        }
        if let error = error as? AppPackagingError {
            return DevToolExecutionError(
                errorCode: error.errorCode,
                errorMessage: error.localizedDescription
            )
        }
        if let error = error as? VerificationError {
            return DevToolExecutionError(
                errorCode: error.code,
                errorMessage: error.message
            )
        }
        if let error = error as? DevelopmentWorkflowError {
            return DevToolExecutionError(
                errorCode: error.errorCode,
                errorMessage: error.localizedDescription
            )
        }
        return DevToolExecutionError(
            errorCode: "execution_failed",
            errorMessage: error.localizedDescription
        )
    }
}
