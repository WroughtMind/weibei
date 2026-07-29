import Foundation
import WeiBeiCore

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

/// Runner 对外报告的单场景结果状态。
public enum VerificationRunStatus: String, Codable, Sendable {
    case passed
    case failed
}

/// 记录单个场景的行为、视觉结果和诊断位置。
public struct VerificationScenarioRunResult: Equatable, Codable, Sendable {
    public let scenarioID: VerificationScenarioID
    public let status: VerificationRunStatus
    public let durationSeconds: TimeInterval
    public let artifactDirectory: String
    public let errorCode: String?
    public let errorMessage: String?
    public let visualMetrics: VisualInspectionMetrics?

    /// 创建单场景运行结果。
    public init(
        scenarioID: VerificationScenarioID,
        status: VerificationRunStatus,
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
            var completion: VerificationScenarioCompletionEnvelope?
            do {
                let readiness = try windowWaiter.waitForReadiness(
                    at: artifacts.windowReadyURL,
                    artifactRoot: artifacts.directoryURL,
                    app: app
                )
                let window = try windowWaiter.waitForWindow(
                    readiness: readiness,
                    app: app
                )
                if scenario.usesCompletionProtocol {
                    completion = try waitForCompletion(
                        scenario: scenario,
                        artifacts: artifacts,
                        app: app
                    )
                }
                try resultValidator.validate(scenario: scenario, artifacts: artifacts)
                if let completion {
                    try validateDeclaredEvidence(completion, artifacts: artifacts)
                }
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

            if let currentError = scenarioError {
                let stderrTail = diagnosticTail(at: artifacts.stderrURL)
                if !stderrTail.isEmpty {
                    let message = "\(currentError.message)\nstderr tail:\n\(stderrTail)"
                    scenarioError = VerificationError(code: currentError.code, message: message)
                }
            }
            var succeeded = scenarioError == nil
            do {
                let validation = VerificationValidationEnvelope(
                    scenarioID: scenario.id.rawValue,
                    status: succeeded ? .passed : .failed,
                    validatedEvidence: completion?.evidence ?? []
                )
                try VerificationContractIO.publish(
                    validation,
                    to: artifacts.validationURL,
                    within: artifacts.directoryURL
                )
            } catch {
                succeeded = false
                scenarioError = VerificationError(code: "scenario_evidence_invalid", message: error.localizedDescription)
            }
            try artifactStore.finishScenario(
                artifacts,
                succeeded: succeeded,
                retainedEvidence: completion?.evidence ?? []
            )
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
        environment["WEIBEI_SUPPRESS_ACTIVATION"] = "0"
        environment["WEIBEI_FORCE_IMMEDIATE_SAVE"] = "1"
        environment["WEIBEI_FORCE_OFFLINE_AGENT"] = scenario.requirements.requiresOnlinePI ? "0" : "1"
        environment["WEIBEI_WORKSPACE_DIR"] = artifacts.workspaceURL.path
        environment["WEIBEI_VERIFY_SCENARIO"] = scenario.id.rawValue
        environment["WEIBEI_VERIFY_WINDOW_SIZE"] = configuration.windowSize ?? ""
        environment["WEIBEI_VERIFY_INSPIRATION_ID"] = configuration.inspirationID ?? ""
        environment["WEIBEI_VERIFY_CAPTURE_PATH"] = artifacts.captureURL.path
        environment["WEIBEI_VERIFY_ARTIFACT_DIR"] = artifacts.directoryURL.path
        environment["WEIBEI_VERIFY_WINDOW_READY_PATH"] = artifacts.windowReadyURL.path
        environment["WEIBEI_VERIFY_COMPLETION_PATH"] = artifacts.completionURL.path
        environment["WEIBEI_VERIFY_EVIDENCE_DIR"] = artifacts.evidenceDirectoryURL.path

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

    /// 等待应用在全部证据落盘后原子发布 completion。
    package func waitForCompletion(
        scenario: VerificationScenario,
        artifacts: VerificationScenarioArtifacts,
        app: any VerificationRunningApp,
        waiter: any VerificationWaiting = SystemVerificationWaiter(),
        pollingIntervalSeconds: TimeInterval = 0.2
    ) throws -> VerificationScenarioCompletionEnvelope {
        let attempts = max(1, Int(ceil(scenario.timeoutSeconds / pollingIntervalSeconds)))
        for attempt in 0..<attempts {
            guard app.isRunning else {
                throw VerificationError(code: "app_exited_early", message: "Verification app exited before scenario completion.")
            }
            if FileManager.default.fileExists(atPath: artifacts.completionURL.path) {
                let completion: VerificationScenarioCompletionEnvelope
                do {
                    completion = try VerificationContractIO.decode(
                        VerificationScenarioCompletionEnvelope.self,
                        from: artifacts.completionURL,
                        within: artifacts.directoryURL
                    )
                    try completion.validate(expectedScenarioID: scenario.id.rawValue)
                } catch {
                    throw VerificationError(code: "scenario_completion_invalid", message: error.localizedDescription)
                }
                guard completion.status == .passed else {
                    throw VerificationError(
                        code: "scenario_declared_failed",
                        message: completion.errorMessage ?? "Application declared scenario failure."
                    )
                }
                return completion
            }
            if attempt + 1 < attempts {
                waiter.wait(seconds: pollingIntervalSeconds)
            }
        }
        throw VerificationError(
            code: "scenario_completion_timeout",
            message: "Scenario \(scenario.id.rawValue) did not publish completion within \(Int(scenario.timeoutSeconds)) seconds."
        )
    }

    /// completion 只是提交屏障；Runner 仍独立确认每个声明文件存在且位于 artifact 根内。
    package func validateDeclaredEvidence(
        _ completion: VerificationScenarioCompletionEnvelope,
        artifacts: VerificationScenarioArtifacts
    ) throws {
        for relativePath in completion.evidence {
            let candidate = artifacts.directoryURL.appendingPathComponent(relativePath)
            do {
                _ = try VerificationContractIO.validatedURL(candidate, within: artifacts.directoryURL)
            } catch {
                throw VerificationError(code: "scenario_evidence_invalid", message: error.localizedDescription)
            }
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                throw VerificationError(
                    code: "scenario_evidence_missing",
                    message: "Scenario evidence is missing: \(relativePath)"
                )
            }
        }
    }

    /// 返回有限 stderr 尾部，避免协议错误丢失应用侧原因。
    private func diagnosticTail(at url: URL, limit: Int = 4_096) -> String {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return ""
        }
        return String(decoding: data.suffix(limit), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
