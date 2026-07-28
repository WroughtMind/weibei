import Foundation

/// 配置一轮应用场景验收。
public struct VerificationRunConfiguration: Sendable {
    public let appExecutableURL: URL
    public let workingDirectoryURL: URL
    public let appOwnerName: String
    public let scenarios: [VerificationScenario]
    public let baseEnvironment: [String: String]
    public let windowSize: String?
    public let inspirationID: String?
    public let performVisualInspection: Bool
    public let allowLivePI: Bool
    public let failFast: Bool

    /// 创建验收运行配置。
    public init(
        appExecutableURL: URL,
        workingDirectoryURL: URL,
        appOwnerName: String = "魏碑",
        scenarios: [VerificationScenario],
        baseEnvironment: [String: String] = [:],
        windowSize: String? = nil,
        inspirationID: String? = nil,
        performVisualInspection: Bool = false,
        allowLivePI: Bool = false,
        failFast: Bool = false
    ) {
        self.appExecutableURL = appExecutableURL
        self.workingDirectoryURL = workingDirectoryURL
        self.appOwnerName = appOwnerName
        self.scenarios = scenarios
        self.baseEnvironment = baseEnvironment
        self.windowSize = windowSize
        self.inspirationID = inspirationID
        self.performVisualInspection = performVisualInspection
        self.allowLivePI = allowLivePI
        self.failFast = failFast
    }
}

/// 单个场景的最终状态。
public enum VerificationScenarioStatus: String, Codable, Sendable {
    case passed
    case failed
}

/// 记录单个场景的行为、视觉结果和诊断位置。
public struct VerificationScenarioRunResult: Equatable, Codable, Sendable {
    public let scenarioID: VerificationScenarioID
    public let status: VerificationScenarioStatus
    public let durationSeconds: TimeInterval
    public let artifactDirectory: String
    public let errorCode: String?
    public let errorMessage: String?
    public let visualMetrics: VisualInspectionMetrics?

    /// 创建单场景运行结果。
    public init(
        scenarioID: VerificationScenarioID,
        status: VerificationScenarioStatus,
        durationSeconds: TimeInterval,
        artifactDirectory: String,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        visualMetrics: VisualInspectionMetrics? = nil
    ) {
        self.scenarioID = scenarioID
        self.status = status
        self.durationSeconds = durationSeconds
        self.artifactDirectory = artifactDirectory
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.visualMetrics = visualMetrics
    }
}

/// 一轮完整验收的结构化摘要。
public struct VerificationRunReport: Equatable, Codable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let artifactDirectory: String
    public let results: [VerificationScenarioRunResult]

    /// 创建完整运行报告。
    public init(
        startedAt: Date,
        finishedAt: Date,
        artifactDirectory: String,
        results: [VerificationScenarioRunResult]
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.artifactDirectory = artifactDirectory
        self.results = results
    }

    /// 所有实际运行的场景是否均成功。
    public var succeeded: Bool {
        results.allSatisfy { $0.status == .passed }
    }
}

/// 顺序运行隔离场景，并在普通场景失败后继续收集完整回归结果。
public struct VerificationRunner {
    private let appManager: any VerificationAppManaging
    private let windowWaiter: VerificationWindowWaiter
    private let resultValidator: any VerificationScenarioResultValidating
    private let captureResolver: VerificationCaptureResolver
    private let visualInspector: any VerificationVisualInspecting

    /// 创建可由 CLI 工作流组装的场景运行器。
    public init(
        appManager: any VerificationAppManaging = FoundationVerificationAppManager(),
        windowWaiter: VerificationWindowWaiter = VerificationWindowWaiter(),
        resultValidator: any VerificationScenarioResultValidating = FileVerificationScenarioResultValidator(),
        captureResolver: VerificationCaptureResolver = VerificationCaptureResolver(),
        visualInspector: any VerificationVisualInspecting = AppKitVerificationVisualInspector()
    ) {
        self.appManager = appManager
        self.windowWaiter = windowWaiter
        self.resultValidator = resultValidator
        self.captureResolver = captureResolver
        self.visualInspector = visualInspector
    }

    /// 执行场景；应用无法启动等全局前置错误会抛出，场景断言错误会汇总到报告。
    public func run(
        configuration: VerificationRunConfiguration,
        artifactStore: VerificationArtifactStore
    ) async throws -> VerificationRunReport {
        try validateGlobalPreconditions(configuration)
        let startedAt = Date()
        var results: [VerificationScenarioRunResult] = []

        for scenario in configuration.scenarios {
            let artifacts = try artifactStore.prepareScenario(scenario)
            let scenarioStartedAt = Date()
            let environment = scenarioEnvironment(
                scenario: scenario,
                artifacts: artifacts,
                configuration: configuration
            )
            let app = try appManager.launch(
                configuration: VerificationAppLaunchConfiguration(
                    executableURL: configuration.appExecutableURL,
                    workingDirectoryURL: configuration.workingDirectoryURL,
                    environment: environment,
                    stdoutURL: artifacts.stdoutURL,
                    stderrURL: artifacts.stderrURL
                )
            )

            var scenarioError: VerificationError?
            var visualMetrics: VisualInspectionMetrics?
            do {
                let window = try windowWaiter.waitForWindow(
                    ownerName: configuration.appOwnerName,
                    processIdentifier: app.processIdentifier,
                    timeoutSeconds: 6
                )
                try resultValidator.validate(scenario: scenario, artifacts: artifacts)
                if configuration.performVisualInspection || scenario.requirements.requiresVisualInspection {
                    let captureURL = try await captureResolver.resolve(
                        appOwnedCaptureURL: artifacts.captureURL,
                        window: window
                    )
                    visualMetrics = try visualInspector.inspect(imageAt: captureURL)
                }
            } catch let error as VerificationError {
                scenarioError = error
            } catch {
                scenarioError = VerificationError(code: "scenario_failed", message: error.localizedDescription)
            }
            appManager.stop(app)

            let succeeded = scenarioError == nil
            try artifactStore.finishScenario(artifacts, succeeded: succeeded)
            results.append(
                VerificationScenarioRunResult(
                    scenarioID: scenario.id,
                    status: succeeded ? .passed : .failed,
                    durationSeconds: Date().timeIntervalSince(scenarioStartedAt),
                    artifactDirectory: artifacts.directoryURL.path,
                    errorCode: scenarioError?.code,
                    errorMessage: scenarioError?.message,
                    visualMetrics: visualMetrics
                )
            )
            if !succeeded, configuration.failFast {
                break
            }
        }

        let report = VerificationRunReport(
            startedAt: startedAt,
            finishedAt: Date(),
            artifactDirectory: artifactStore.runURL.path,
            results: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try artifactStore.completeRun(reportData: encoder.encode(report))
        return report
    }

    /// Rejects missing app binaries and online scenarios without explicit permission.
    private func validateGlobalPreconditions(_ configuration: VerificationRunConfiguration) throws {
        guard FileManager.default.isExecutableFile(atPath: configuration.appExecutableURL.path) else {
            throw VerificationError(
                code: "app_not_executable",
                message: "Verification app is missing or not executable: \(configuration.appExecutableURL.path)"
            )
        }
        if !configuration.allowLivePI,
           let onlineScenario = configuration.scenarios.first(where: \.requirements.requiresOnlinePI) {
            throw VerificationError(
                code: "live_pi_not_allowed",
                message: "Scenario \(onlineScenario.id.rawValue) requires explicit live PI permission."
            )
        }
    }

    /// Builds the isolated environment understood by the product verification hooks.
    private func scenarioEnvironment(
        scenario: VerificationScenario,
        artifacts: VerificationScenarioArtifacts,
        configuration: VerificationRunConfiguration
    ) -> [String: String] {
        var environment = configuration.baseEnvironment
        environment["WEIBEI_SUPPRESS_ACTIVATION"] = "1"
        environment["WEIBEI_FORCE_OFFLINE_AGENT"] = scenario.requirements.requiresOnlinePI ? "0" : "1"
        environment["WEIBEI_WORKSPACE_DIR"] = artifacts.workspaceURL.path
        environment["WEIBEI_VERIFY_SCENARIO"] = scenario.id.rawValue
        environment["WEIBEI_VERIFY_WINDOW_SIZE"] = configuration.windowSize ?? ""
        environment["WEIBEI_VERIFY_INSPIRATION_ID"] = configuration.inspirationID ?? ""
        environment["WEIBEI_VERIFY_CAPTURE_PATH"] = artifacts.captureURL.path

        let tracesPanes = [
            VerificationScenarioID.paneLayoutStabilityFlow,
            .paneToggleContinuityFlow,
            .paneReorderWidthFlow
        ].contains(scenario.id)
        environment["WEIBEI_VERIFY_PANE_TRACE_DIR"] = tracesPanes
            ? artifacts.workspaceURL.appendingPathComponent("pane-trace").path
            : ""
        environment["WEIBEI_VERIFY_PANE_TRACE_SAMPLES"] = scenario.id == .paneLayoutStabilityFlow ? "1" : "0"
        if scenario.requirements.requiresOnlinePI {
            environment["WEIBEI_PI_PROVIDER"] = "openai-codex"
            environment["WEIBEI_PI_MODEL"] = "gpt-5.5"
        }
        return environment
    }
}
