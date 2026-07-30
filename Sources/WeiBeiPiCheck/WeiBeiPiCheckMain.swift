import Darwin
import Foundation
import WeiBeiCore

@main
struct WeiBeiPiCheckMain {
    static func main() async {
        var environment = ProcessInfo.processInfo.environment
        do {
            environment = try RichAnswerEvidenceCommandLine.mergedEnvironment(
                arguments: CommandLine.arguments,
                base: environment
            )
        } catch {
            fputs("pi-rich-answer CLI failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        if CommandLine.arguments.contains("--rich-answer-evidence-help") {
            print(RichAnswerEvidenceCommandLine.helpText)
            return
        }

        do {
            if let mergeConfiguration = try RichAnswerEvidenceMergeConfiguration.from(environment: environment) {
                let result = try RichAnswerEvidenceMerger.merge(configuration: mergeConfiguration)
                let gateReport = try RichAnswerEvidencePackageGateReport.load(
                    reviewPackageURL: result.reviewPackageURL
                )
                print(
                    "pi-rich-answer evidence merge completed: \(result.mergedRunID) inputs=\(result.inputRunIDs.joined(separator: ",")) repetitions=\(result.repetitions.map(String.init).joined(separator: ",")) records=\(result.totalRecords) root=\(result.rootURL.path) reviewPackage=\(result.reviewPackageURL.path)"
                )
                if !gateReport.gateFailures.isEmpty {
                    fputs(
                        "pi-rich-answer evidence gate failed: \(gateReport.metrics); gaps=\(gateReport.gateFailures.joined(separator: " | "))\n",
                        stderr
                    )
                    exit(1)
                }
                print("pi-rich-answer evidence pending user acceptance: \(gateReport.metrics)")
                return
            }
        } catch {
            fputs("pi-rich-answer evidence merge failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        if CommandLine.arguments.contains("--rich-answer-protocol") {
            do {
                try await RichAnswerPythonArtifactSelfCheck.runExecutorChecks()
                try runRichAnswerSemanticGateSelfCheck()
                try runRichAnswerProtocolSelfCheck()
                print("rich-answer-protocol-check completed: invalid protocol rejected; final evidence gates still pending user acceptance")
            } catch {
                fputs("rich-answer-protocol-check failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }

        if CommandLine.arguments.contains("--list-rich-answer-cases") {
            do {
                try RichAnswerLiveCases.assertMatrixMatchesPressureCases()
                for runCase in RichAnswerLiveCases.fullMatrixRuns {
                    switch runCase {
                    case let .invalidProtocol(caseID):
                        print("deterministic\t\(caseID)\t协议")
                    case let .success(checkCase):
                        print("success\t\(checkCase.id)\t\(checkCase.discipline)")
                    case let .textOnly(checkCase):
                        print("text-only\t\(checkCase.id)\t\(checkCase.subject)")
                    case let .degradation(checkCase):
                        print("degradation\t\(checkCase.id)\t\(checkCase.pressureCase.subject)")
                    }
                }
            } catch {
                fputs("pi-rich-answer case list failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }

        if CommandLine.arguments.contains("--rich-answer-evidence-plan") {
            do {
                try RichAnswerLiveCases.assertMatrixMatchesPressureCases()
                let runConfiguration = try RichAnswerEvidenceRunConfiguration(environment: environment)
                let selectedRuns = try selectedRichAnswerRuns(
                    environment: environment,
                    configuration: runConfiguration
                )
                let coverage = RichAnswerLiveCases.matrixCoverage(for: selectedRuns)
                print("pi-rich-answer evidence plan: \(runConfiguration.runDescription)")
                print("sourceHash=\(runConfiguration.sourceHash) matrixHash=\(runConfiguration.matrixHash)")
                print("selected=\(selectedRuns.count) repetitions=\(runConfiguration.repetitions.count) totalAttempts=\(selectedRuns.count * runConfiguration.repetitions.count)")
                print("coverage=\(coverage.isComplete ? "full-matrix" : "partial") \(coverage.summary)")
                for repetition in runConfiguration.repetitions {
                    for (index, runCase) in selectedRuns.enumerated() {
                        print("rep=\(repetition)\t\(index + 1)/\(selectedRuns.count)\t\(runCase.caseKind)\t\(runCase.id)\t\(runCase.subject)")
                    }
                }
            } catch {
                fputs("pi-rich-answer evidence plan failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }

        if CommandLine.arguments.contains("--rich-answer-evidence-revalidate-degradations") {
            do {
                let recordURLs = try richAnswerOfflineRevalidationRecordURLs(
                    from: CommandLine.arguments,
                    after: "--rich-answer-evidence-revalidate-degradations"
                )
                let result = try revalidateRichAnswerDegradationRecords(recordURLs)
                print(
                    "pi-rich-answer offline degradation revalidation completed: automatedPassed=\(result.automatedPassed) reviewRequired=\(result.reviewRequired.count) failed=\(result.failures.count)"
                )
                if !result.failures.isEmpty {
                    fputs(result.failures.joined(separator: "\n") + "\n", stderr)
                    exit(1)
                }
            } catch {
                fputs("pi-rich-answer offline degradation revalidation failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }

        if CommandLine.arguments.contains("--rich-answer-evidence-revalidate-rich") {
            do {
                let recordURLs = try richAnswerOfflineRevalidationRecordURLs(
                    from: CommandLine.arguments,
                    after: "--rich-answer-evidence-revalidate-rich"
                )
                let result = try revalidateRichAnswerSuccessRecords(recordURLs)
                print(
                    "pi-rich-answer offline rich revalidation completed: automatedPassed=\(result.automatedPassed) reviewRequired=\(result.reviewRequired.count) failed=\(result.failures.count)"
                )
                if !result.failures.isEmpty {
                    fputs(result.failures.joined(separator: "\n") + "\n", stderr)
                    exit(1)
                }
            } catch {
                fputs("pi-rich-answer offline rich revalidation failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }

        let liveCheckSetting = environment["WEIBEI_PI_LIVE_CHECK"] ?? "auto"
        let runsEvaluation = environment["WEIBEI_PI_EVAL"] == "1"
        let runsRichAnswerCheck = environment["WEIBEI_PI_RICH_ANSWER_CHECK"] == "1"
        let explicitPath = environment["WEIBEI_PI_EXECUTABLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let executableURL = explicitPath.isEmpty
            ? PiExecutableLocator.locate()
            : URL(fileURLWithPath: explicitPath)
        let containingAppPath = environment["WEIBEI_PI_APP_BUNDLE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let containingAppURL = containingAppPath.isEmpty ? nil : URL(fileURLWithPath: containingAppPath)

        guard let executableURL else {
            fputs("pi-check failed: embedded PI runtime not found\n", stderr)
            exit(1)
        }

        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-pi-check-\(UUID().uuidString)", isDirectory: true)
        let runtime = PiAgentRuntime(executableURL: executableURL, runtimeDirectory: runtimeRoot)

        do {
            let manifest = try PiBundledRuntime.validate(
                executableURL: executableURL,
                containingAppURL: containingAppURL
            )
            let launchedPath = try await runtime.healthCheck()
            let isolatedConfig = runtimeRoot.appendingPathComponent("PiConfig", isDirectory: true)
            guard FileManager.default.fileExists(atPath: isolatedConfig.path) else {
                throw PiCheckError.missingIsolatedConfiguration
            }
            print("pi-check ready: PI \(manifest.piVersion) at \(launchedPath)")

            let isolatedAuth = isolatedConfig.appendingPathComponent("auth.json")
            let hasConfiguredAuth = ((try? isolatedAuth.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 2
            let runsLiveCheck = runsEvaluation
                || liveCheckSetting == "1"
                || (liveCheckSetting != "0" && hasConfiguredAuth)
            var expectedSessionID: UUID?
            if runsLiveCheck {
                expectedSessionID = try await checkNoteMaking(runtime)
            }
            if runsRichAnswerCheck || runsEvaluation {
                try await checkRichAnswer(
                    executableURL: executableURL,
                    environment: environment
                )
            }
            if runsEvaluation {
                try await checkStudyCompanion(runtime)
                try await checkCourseWayfinding(runtime)
                try await checkCloseReading(runtime)
                try await checkRecallPractice(runtime)
                print("pi-eval completed: study-companion, course-wayfinding, close-reading, rich-answer, note-making, recall-practice; rich-answer final status remains pending user acceptance")
            }
            await runtime.shutdown()
            try verifyPersistedSessionStateAfterShutdown(
                runtimeRoot,
                expectedSessionID: expectedSessionID
            )
            try? FileManager.default.removeItem(at: runtimeRoot)
        } catch {
            await runtime.shutdown()
            try? FileManager.default.removeItem(at: runtimeRoot)
            fputs("pi-check failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func checkNoteMaking(_ runtime: PiAgentRuntime) async throws -> UUID {
        let liveRequest = request(
            question: "请把当前选区整理成一个带来源的 Markdown 核心要点，并提交待确认的笔记建议。",
            revision: "pi-check-note"
        )
        let reply = try await runtime.respond(to: liveRequest)
        guard reply.backend == .pi,
              !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let proposal = reply.noteProposal,
              proposal.contextRevision == "pi-check-note",
              !proposal.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !proposal.evidence.isEmpty else {
            throw PiCheckError.invalidLiveReply
        }
        print("pi-live-check passed: proposal=\(proposal.markdown.count) chars evidence=\(proposal.evidence.count)")
        return liveRequest.id
    }

    private static func checkCloseReading(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                question: "只根据当前内容解释为什么利率可称为资金价格，并标明来源。",
                revision: "pi-check-reading"
            )
        )
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              reply.text.contains("资金"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("close-reading")
        }
    }

    private static func checkRichAnswer(
        executableURL: URL,
        environment: [String: String]
    ) async throws {
        try RichAnswerLiveCases.assertMatrixMatchesPressureCases()
        let runConfiguration = try RichAnswerEvidenceRunConfiguration(environment: environment)
        let recorder = try RichAnswerEvidenceRecorder(configuration: runConfiguration)
        var didFinishIndex = false
        defer {
            if !didFinishIndex {
                try? recorder.finishIndex()
            }
        }
        print("pi-rich-answer evidence run: \(runConfiguration.runDescription)")

        let selectedRuns = try selectedRichAnswerRuns(environment: environment, configuration: runConfiguration)
        if runConfiguration.expectsFullMatrixSelection {
            try RichAnswerLiveCases.assertFullMatrixCoverage(
                for: selectedRuns,
                context: "selected rich-answer evidence run"
            )
        }
        var summaries: [String] = []
        var failures: [String] = []
        var recordedAttempts = Set<String>()
        for repetition in runConfiguration.repetitions {
            for (index, runCase) in selectedRuns.enumerated() {
                if runConfiguration.resume,
                   recorder.hasPassingRecord(repetition: repetition, runCase: runCase) {
                    try recorder.recordSkipped(
                        repetition: repetition,
                        sequence: index + 1,
                        total: selectedRuns.count,
                        runCase: runCase
                    )
                    recordedAttempts.insert(recordAttemptKey(repetition: repetition, runCase: runCase))
                    print("pi-rich-answer skipped existing pass: rep=\(repetition) \(runCase.id)")
                    fflush(stdout)
                    continue
                }

                print(
                    "pi-rich-answer running rep=\(repetition) \(index + 1)/\(selectedRuns.count): \(runCase.id)"
                )
                fflush(stdout)
                let startedAt = Date()
                var request: StudyAgentRequest?
                var reply: StudyAgentReply?
                do {
                    let validation: RichAnswerEvidenceValidationSnapshot
                    let summary: String
                    switch runCase {
                    case .invalidProtocol:
                        try runRichAnswerProtocolSelfCheck()
                        validation = .deterministicInvalidProtocolPassed()
                        summary = "\(runCase.id):deterministic-protocol-rejection"
                    case let .success(checkCase):
                        request = richAnswerRequest(checkCase)
                        let liveReply = try await withFreshRichAnswerRuntime(
                            executableURL: executableURL,
                            providerConfiguration: runConfiguration.piProviderConfiguration,
                            expectedSessionID: request!.id
                        ) { runtime in
                            try await runtime.respond(to: request!)
                        }
                        reply = liveReply
                        let presentation = try validateRichAnswer(liveReply, for: checkCase)
                        let elapsedSeconds = Date().timeIntervalSince(startedAt)
                        let elapsedText = String(format: "%.1f", elapsedSeconds)
                        let programCount = presentation.scenes.filter { $0.program != nil }.count
                        let compositionCount = presentation.scenes.filter { $0.ui != nil }.count
                        validation = .passed(
                            kind: "rich",
                            checks: [
                                "backend-pi",
                                "source-bound",
                                "catalog-before-rich-answer",
                                "professional-judgment-contract",
                                "inline-placement",
                                "expression-plan",
                                "renderer-requirement",
                                "thinking-level=\(runConfiguration.thinkingLevel ?? "inherited")",
                                latencyCheck(elapsedSeconds, threshold: 150),
                            ],
                            reply: liveReply
                        )
                        summary = "\(checkCase.id):scenes=\(presentation.scenes.count),t1=\(programCount),t2=\(compositionCount),latency=\(elapsedText)s"
                    case let .textOnly(checkCase):
                        request = richAnswerTextOnlyRequest(checkCase)
                        let liveReply = try await withFreshRichAnswerRuntime(
                            executableURL: executableURL,
                            providerConfiguration: runConfiguration.piProviderConfiguration,
                            expectedSessionID: request!.id
                        ) { runtime in
                            try await runtime.respond(to: request!)
                        }
                        reply = liveReply
                        try validateRichAnswerTextOnly(liveReply, for: checkCase)
                        let elapsedSeconds = Date().timeIntervalSince(startedAt)
                        let elapsedText = String(format: "%.1f", elapsedSeconds)
                        validation = .passed(
                            kind: "text-only",
                            checks: [
                                "backend-pi",
                                "source-bound",
                                "no-rich-answer",
                                "no-ui-catalog",
                                "thinking-level=\(runConfiguration.thinkingLevel ?? "inherited")",
                                latencyCheck(elapsedSeconds, threshold: 60),
                            ],
                            reply: liveReply
                        )
                        summary = "\(checkCase.id):text-only,latency=\(elapsedText)s"
                    case let .degradation(checkCase):
                        request = richAnswerDegradationRequest(checkCase)
                        let liveReply = try await withFreshRichAnswerRuntime(
                            executableURL: executableURL,
                            providerConfiguration: runConfiguration.piProviderConfiguration,
                            expectedSessionID: request!.id
                        ) { runtime in
                            try await runtime.respond(to: request!)
                        }
                        reply = liveReply
                        try validateRichAnswerDegradation(liveReply, for: checkCase)
                        let elapsedSeconds = Date().timeIntervalSince(startedAt)
                        let elapsedText = String(format: "%.1f", elapsedSeconds)
                        validation = .passed(
                            kind: "degradation",
                            checks: [
                                "backend-pi",
                                "context-read",
                                "honest-readable-limitation",
                                "unsafe-rich-answer-blocked",
                                "thinking-level=\(runConfiguration.thinkingLevel ?? "inherited")",
                                latencyCheck(elapsedSeconds, threshold: 90),
                            ],
                            reply: liveReply
                        )
                        summary = "\(checkCase.id):degraded,latency=\(elapsedText)s"
                    }
                    let elapsedSeconds = Date().timeIntervalSince(startedAt)
                    try recorder.recordResult(
                        repetition: repetition,
                        sequence: index + 1,
                        total: selectedRuns.count,
                        runCase: runCase,
                        request: request,
                        reply: reply,
                        startedAt: startedAt,
                        elapsedSeconds: elapsedSeconds,
                        validation: validation,
                        failureReason: nil
                    )
                    recordedAttempts.insert(recordAttemptKey(repetition: repetition, runCase: runCase))
                    summaries.append(summary)
                    print("pi-rich-answer technical record completed: rep=\(repetition) \(runCase.id) final-gates=pending")
                    fflush(stdout)
                } catch {
                    let elapsedSeconds = Date().timeIntervalSince(startedAt)
                    let validation: RichAnswerEvidenceValidationSnapshot
                    if case .invalidProtocol = runCase {
                        validation = .deterministicInvalidProtocolFailed(error)
                    } else {
                        validation = .failed(kind: runCase.caseKind, error: error, reply: reply)
                    }
                    do {
                        try recorder.recordResult(
                            repetition: repetition,
                            sequence: index + 1,
                            total: selectedRuns.count,
                            runCase: runCase,
                            request: request,
                            reply: reply,
                            startedAt: startedAt,
                            elapsedSeconds: elapsedSeconds,
                            validation: validation,
                            failureReason: error.localizedDescription
                        )
                        recordedAttempts.insert(recordAttemptKey(repetition: repetition, runCase: runCase))
                    } catch {
                        failures.append(
                            "rep=\(repetition) \(runCase.id): record write failed after case failure: \(error.localizedDescription)"
                        )
                        print(
                            "pi-rich-answer record failed: rep=\(repetition) \(runCase.id): \(error.localizedDescription)"
                        )
                        fflush(stdout)
                    }
                    failures.append("rep=\(repetition) \(runCase.id): \(error.localizedDescription)")
                    print("pi-rich-answer failed: rep=\(repetition) \(runCase.id): \(error.localizedDescription)")
                    fflush(stdout)
                    if !runConfiguration.continueAfterFailure {
                        throw error
                    }
                }
            }
        }
        let missingRecordedAttempts = missingRecordAttempts(
            repetitions: runConfiguration.repetitions,
            selectedRuns: selectedRuns,
            recordedAttempts: recordedAttempts
        )
        if !missingRecordedAttempts.isEmpty {
            failures.append(
                "record coverage gap: \(missingRecordedAttempts.joined(separator: ","))"
            )
        }
        try recorder.finishIndex()
        didFinishIndex = true
        guard failures.isEmpty else {
            throw PiCheckError.invalidEvaluation(
                "rich-answer evidence run completed with \(failures.count) failure(s): \(failures.joined(separator: " | "))"
            )
        }
        print("pi-rich-answer matrix technical run completed: \(summaries.joined(separator: "; ")); final-gates=pending-screenshots-review-package; status=待用户验收")
    }

    private static func withFreshRichAnswerRuntime<T>(
        executableURL: URL,
        providerConfiguration: PiAgentProviderConfiguration,
        expectedSessionID: UUID,
        operation: (PiAgentRuntime) async throws -> T
    ) async throws -> T {
        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-pi-rich-answer-\(UUID().uuidString)", isDirectory: true)
        let runtime = PiAgentRuntime(
            executableURL: executableURL,
            runtimeDirectory: runtimeRoot
        )
        do {
            await runtime.configure(providerConfiguration)
            _ = try await runtime.healthCheck()
            let result = try await operation(runtime)
            await runtime.shutdown()
            try verifyPersistedSessionStateAfterShutdown(
                runtimeRoot,
                expectedSessionID: expectedSessionID
            )
            try? FileManager.default.removeItem(at: runtimeRoot)
            return result
        } catch {
            await runtime.shutdown()
            try? FileManager.default.removeItem(at: runtimeRoot)
            throw error
        }
    }

    private static func runRichAnswerSemanticGateSelfCheck() throws {
        try assertRichAnswerSemanticGate(
            containsEveryGroup(
                "实际利率约等于名义利率 − 预期通胀率。",
                [["实际利率"], ["名义利率"], ["通货膨胀", "通胀"], ["减"]]
            ),
            "binary-minus-counts-as-subtract"
        )
        try assertRichAnswerSemanticGate(
            containsEveryGroup(
                "顶点式 y = 2(x − 2)²，横向平移由 x − 2 决定。",
                [["x"], ["2"], ["减"]]
            ),
            "variable-minus-number-counts-as-subtract"
        )
        try assertRichAnswerSemanticGate(
            containsEveryGroup(
                "函数 y = x² − 3 的整体下移量是 3。",
                [["x²"], ["3"], ["减"]]
            ),
            "superscript-minus-number-counts-as-subtract"
        )
        try assertRichAnswerSemanticGate(
            containsAny("20% 折现 NPV 约 -3.81。", ["-3.81"]),
            "unary-negative-number-preserved"
        )

        let rcContract = RichAnswerProfessionalJudgmentContracts.contract(
            for: "learning-physics-rc-circuit-transient"
        )
        let rcCorrect = RichAnswerProfessionalJudgmentValidator.validate(
            units: RichAnswerProfessionalJudgmentValidator.claimUnits(
                from: "时间常数 tau 等于 1.0 s；t = tau 时 Vc 约 3.16 V；5 tau 只是接近稳态而非精确到达。"
            ),
            contract: rcContract
        )
        try assertRichAnswerSemanticGate(
            rcCorrect.missingRequiredClaims.isEmpty
                && !rcCorrect.triggeredForbiddenClaims.contains("five-tau-exact"),
            "local-tau-alias-and-negative-boundary"
        )
        let rcWrong = RichAnswerProfessionalJudgmentValidator.validate(
            units: ["5 tau 完全到达稳态"],
            contract: rcContract
        )
        try assertRichAnswerSemanticGate(
            rcWrong.triggeredForbiddenClaims.contains("five-tau-exact"),
            "wrong-local-tau-claim-still-blocked"
        )
        let rcWrongWithTrailingException = RichAnswerProfessionalJudgmentValidator.validate(
            units: ["5 tau 完全到达稳态不是近似"],
            contract: rcContract
        )
        try assertRichAnswerSemanticGate(
            rcWrongWithTrailingException.triggeredForbiddenClaims.contains("five-tau-exact"),
            "trailing-negation-does-not-clear-positive-forbidden-claim"
        )

        let doubleSlitContract = RichAnswerProfessionalJudgmentContracts.contract(
            for: "learning-physics-double-slit-interference"
        )
        let doubleSlitCorrect = RichAnswerProfessionalJudgmentValidator.validate(
            units: RichAnswerProfessionalJudgmentValidator.claimUnits(
                from: "当前亮纹间距约 3 mm。lambda 和 L 增大条纹变疏，缝距 d 增大条纹变密。材料没有给出单缝宽度，只能小角度示意，不能精确画出衍射包络。"
            ),
            contract: doubleSlitContract
        )
        try assertRichAnswerSemanticGate(
            doubleSlitCorrect.missingRequiredClaims.isEmpty
                && doubleSlitCorrect.triggeredForbiddenClaims.isEmpty,
            "local-lambda-d-aliases"
        )

        let titleOnlyPresentation = RichAnswerPresentation(
            mode: .rich,
            narrative: "",
            scenes: [
                RichAnswerScene(
                    id: "title-only",
                    title: "时间常数 tau 等于 1.0 s",
                    family: .quantityAndCoordinates,
                    objects: []
                ),
            ],
            evidenceState: .complete
        )
        let titleOnlyReply = StudyAgentReply(
            text: "",
            backend: .pi,
            richAnswer: titleOnlyPresentation
        )
        let titleOnlyJudgment = RichAnswerProfessionalJudgmentValidator.validate(
            units: professionalJudgmentUnits(reply: titleOnlyReply, presentation: titleOnlyPresentation),
            contract: rcContract
        )
        try assertRichAnswerSemanticGate(
            titleOnlyJudgment.missingRequiredClaims.contains("tau-one-second"),
            "scene-title-alone-does-not-satisfy-claim"
        )

        guard let quantityCase = RichAnswerLiveCases.successes.first(where: {
            $0.id == "learning-math-quadratic-vertex"
        }) else {
            throw PiCheckError.invalidEvaluation("semantic-gate-self-check missing quantity case")
        }
        let weakUI = RichAnswerUIComposition(
            rootID: "root",
            nodes: [
                RichAnswerUINode(id: "root", role: .vstack, children: ["control", "steps", "value"]),
                RichAnswerUINode(id: "control", role: .scrubber, label: "步骤", bindingID: "step"),
                RichAnswerUINode(id: "steps", role: .sequence, datasetID: "states", bindingID: "step"),
                RichAnswerUINode(id: "value", role: .metric, label: "读数", datasetID: "states", bindingID: "step"),
            ],
            datasets: [
                RichAnswerUIDataset(
                    id: "states",
                    rows: [
                        RichAnswerUIDataRow(id: "a", x: 0, y: 0, value: 0, label: "只换成步骤一"),
                        RichAnswerUIDataRow(id: "b", x: 0, y: 0, value: 1, label: "只换成步骤二"),
                    ]
                ),
            ],
            bindings: [
                RichAnswerUIBinding(
                    id: "step",
                    label: "步骤",
                    minimum: 0,
                    maximum: 1,
                    step: 1,
                    initialValue: 0
                ),
            ]
        )
        let weakScene = RichAnswerScene(
            id: "weak",
            title: "弱可视化",
            family: .quantityAndCoordinates,
            objects: [],
            ui: weakUI
        )
        try assertRichAnswerSemanticGate(
            t2SceneIssues(weakScene, for: quantityCase).contains("missing-stateful-nontext-encoding"),
            "sequence-metric-text-reflow-blocked-for-nonprocess"
        )
    }

    private static func assertRichAnswerSemanticGate(
        _ condition: Bool,
        _ name: String
    ) throws {
        guard condition else {
            throw PiCheckError.invalidEvaluation("rich-answer semantic gate self-check failed: \(name)")
        }
    }

    private static func checkStudyCompanion(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                question: "我上次学到哪了？请告诉我位置和下一步。",
                revision: "pi-check-companion"
            )
        )
        guard reply.backend == .pi,
              reply.text.contains("期限结构") || reply.text.contains("第 12 页") || reply.text.contains("第12页"),
              reply.text.contains("[学习记录：上次位置]") else {
            throw PiCheckError.invalidEvaluation("study-companion")
        }
    }

    private static func checkCourseWayfinding(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                question: "利率和通货膨胀在课程里有哪份相关材料？说明关联，并原样给出工具返回的最精确 PDF 页码跳转。",
                revision: "pi-check-wayfinding"
            )
        )
        guard reply.backend == .pi,
              reply.text.contains("通货膨胀补充材料"),
              reply.text.contains("来源：通货膨胀补充材料，第 4 页"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("course-wayfinding")
        }
    }

    private static func checkRecallPractice(_ runtime: PiAgentRuntime) async throws {
        let reply = try await runtime.respond(
            to: request(
                question: "只根据当前内容出 2 道复习题，并给出带来源的答案。",
                revision: "pi-check-recall"
            )
        )
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              reply.text.contains("？") || reply.text.contains("?"),
              containsSourceLabel(reply.text) else {
            throw PiCheckError.invalidEvaluation("recall-practice")
        }
    }

    private static func request(
        question: String,
        revision: String
    ) -> StudyAgentRequest {
        StudyAgentRequest(
            purpose: .conversation,
            question: question,
            materialTitle: "利率课程",
            materialText: "利率是资金使用价格的表达。名义利率以货币单位表示，实际利率扣除了通货膨胀后的购买力变化。在课程的近似计算中：实际利率 = 名义利率 - 通货膨胀率。",
            noteTitle: "课堂笔记",
            noteText: "# 利率\n\n## 待整理",
            selectionTitle: "利率定义",
            selectionText: "利率是资金使用价格的表达。",
            courseContext: StudyAgentCourseContext(
                title: "货币金融学",
                items: [
                    StudyAgentCourseItem(
                        id: "material-rates",
                        title: "利率课程",
                        subtitle: "利率讲义",
                        kind: "html",
                        role: "material",
                        isCurrentMaterial: true,
                        linkedItemIDs: ["note-rates"],
                        headings: ["利率的含义", "名义利率与实际利率"],
                        searchText: "利率是资金使用价格的表达。实际利率会扣除通货膨胀对购买力的影响。在课程的近似计算中：实际利率 = 名义利率 - 通货膨胀率。"
                    ),
                    StudyAgentCourseItem(
                        id: "material-inflation",
                        title: "通货膨胀补充材料",
                        subtitle: "PDF 第 4 章",
                        kind: "pdf",
                        role: "material",
                        headings: ["第 4 页", "购买力与实际利率"],
                        searchText: "通货膨胀会改变货币购买力，区分名义利率与实际利率时需要考虑通货膨胀。"
                    ),
                    StudyAgentCourseItem(
                        id: "note-rates",
                        title: "利率笔记",
                        subtitle: "Markdown",
                        kind: "markdown",
                        role: "note",
                        isCurrentNote: true,
                        linkedItemIDs: ["material-rates"],
                        headings: ["核心要点"],
                        searchText: "名义利率与实际利率的区别还需要复习。"
                    ),
                ],
                relations: [
                    StudyAgentCourseRelation(noteItemID: "note-rates", sourceItemID: "material-rates"),
                ]
            ),
            learningContext: StudyAgentLearningContext(
                memoryRevision: 3,
                lastLocation: StudyLocation(
                    itemID: "material-rates",
                    itemTitle: "利率课程",
                    locationTitle: "期限结构",
                    pageIndex: 11
                ),
                memories: [
                    LearningMemoryEntry(
                        kind: .confusion,
                        text: "还不能稳定区分名义利率与实际利率",
                        evidence: "[用户：本轮] 用户上次明确说这个区别还没掌握",
                        origin: .userStatement
                    ),
                ],
                session: StudyAgentSessionSnapshot(
                    id: "pi-check-session",
                    title: "利率复习",
                    summary: "上次学到期限结构，实际利率与通货膨胀的关系还需要复习。",
                    phase: StudyPhase.recall.rawValue,
                    focusItemIDs: ["material-rates", "note-rates"],
                    turnCount: 6
                )
            ),
            language: .chinese,
            contextRevision: revision
        )
    }

    private static func selectedRichAnswerRuns(
        environment: [String: String],
        configuration: RichAnswerEvidenceRunConfiguration
    ) throws -> [RichAnswerLiveRunCase] {
        _ = environment
        let requestedIDs = configuration.requestedIDs
        let allRuns = RichAnswerLiveCases.fullMatrixRuns
        let allIDs = Set(allRuns.map(\.id))
        let unknownIDs = requestedIDs.subtracting(allIDs)
        guard unknownIDs.isEmpty else {
            throw PiCheckError.invalidEvaluation(
                "unknown rich-answer case ids: \(unknownIDs.sorted().joined(separator: ","))"
            )
        }

        var selected = requestedIDs.isEmpty
            ? allRuns
            : allRuns.filter { requestedIDs.contains($0.id) }
        if !configuration.filters.isEmpty {
            let unknownFilters = configuration.filters.filter { filter in
                !Self.isKnownRichAnswerFilter(filter)
                    && !RichAnswerLiveCases.fullMatrixRuns.contains(where: { runCase in
                        runCase.subject.lowercased().contains(filter)
                    })
            }
            guard unknownFilters.isEmpty else {
                throw PiCheckError.invalidEvaluation(
                    "unknown rich-answer filters: \(unknownFilters.sorted().joined(separator: ","))"
                )
            }
            selected = selected.filter {
                Self.richAnswerRun($0, matchesAny: configuration.filters)
            }
        }
        if let offset = configuration.offset {
            selected = Array(selected.dropFirst(min(offset, selected.count)))
        }
        if let limit = configuration.limit {
            selected = Array(selected.prefix(limit))
        }
        guard !selected.isEmpty else {
            throw PiCheckError.invalidEvaluation("rich-answer case selection is empty")
        }
        return selected
    }

    private static func recordAttemptKey(repetition: Int, runCase: RichAnswerLiveRunCase) -> String {
        "\(repetition):\(runCase.caseKind):\(runCase.id)"
    }

    private static func missingRecordAttempts(
        repetitions: [Int],
        selectedRuns: [RichAnswerLiveRunCase],
        recordedAttempts: Set<String>
    ) -> [String] {
        repetitions.flatMap { repetition in
            selectedRuns.compactMap { runCase in
                let key = recordAttemptKey(repetition: repetition, runCase: runCase)
                return recordedAttempts.contains(key) ? nil : key
            }
        }
    }

    private static func richAnswerOfflineRevalidationRecordURLs(
        from arguments: [String],
        after flag: String
    ) throws -> [URL] {
        guard let flagIndex = arguments.firstIndex(of: flag) else {
            return []
        }
        let paths = arguments.dropFirst(flagIndex + 1).filter { !$0.hasPrefix("--") }
        guard !paths.isEmpty else {
            throw PiCheckError.invalidEvaluation(
                "offline degradation revalidation needs one or more record.json paths"
            )
        }
        return paths.map { URL(fileURLWithPath: String($0)) }
    }

    private static func revalidateRichAnswerSuccessRecords(
        _ recordURLs: [URL]
    ) throws -> RichAnswerOfflineRevalidation {
        let casesByID = Dictionary(uniqueKeysWithValues: RichAnswerLiveCases.successes.map {
            ($0.id, $0)
        })
        let decoder = JSONDecoder()
        var passed = 0
        var reviewRequired: [String] = []
        var failures: [String] = []
        for recordURL in recordURLs {
            do {
                let record = try decoder.decode(
                    RichAnswerOfflineEvidenceRecord.self,
                    from: Data(contentsOf: recordURL)
                )
                guard record.caseSnapshot.caseKind == "rich" else {
                    throw PiCheckError.invalidEvaluation(
                        "\(record.caseSnapshot.id) is \(record.caseSnapshot.caseKind), not rich"
                    )
                }
                guard let checkCase = casesByID[record.caseSnapshot.id] else {
                    throw PiCheckError.invalidEvaluation(
                        "unknown rich case \(record.caseSnapshot.id)"
                    )
                }
                let reply = try record.studyAgentReply()
                let presentation = try validateRichAnswer(reply, for: checkCase)
                let layer: String
                if presentation.scenes.contains(where: { $0.renderPlan != nil }) {
                    layer = "renderPlan"
                } else if presentation.scenes.contains(where: { $0.program != nil }) {
                    layer = "t1"
                } else {
                    layer = "t2"
                }
                let judgment = professionalJudgmentValidation(
                    reply: reply,
                    presentation: presentation,
                    for: checkCase
                )
                let reviewReasons = (
                    judgment.missingRequiredClaims.map { "missing-required:\($0)" }
                        + judgment.missingBoundaryClaims.map { "missing-boundary:\($0)" }
                        + judgment.modelOrHumanReviewNotes.map { "human-review:\($0)" }
                )
                if reviewReasons.isEmpty {
                    passed += 1
                    print("offline-revalidate\tautomated-pass\t\(record.caseSnapshot.id)\t\(layer)\t\(recordURL.path)")
                } else {
                    let review = "offline-revalidate\treview-required\t\(record.caseSnapshot.id)\t\(layer)\t\(reviewReasons.joined(separator: "+"))\t\(recordURL.path)"
                    reviewRequired.append(review)
                    print(review)
                }
            } catch {
                failures.append(
                    "offline-revalidate\tfail\t\(recordURL.path)\t\(error.localizedDescription)"
                )
            }
        }
        return RichAnswerOfflineRevalidation(
            automatedPassed: passed,
            reviewRequired: reviewRequired,
            failures: failures
        )
    }

    private static func revalidateRichAnswerDegradationRecords(
        _ recordURLs: [URL]
    ) throws -> RichAnswerOfflineRevalidation {
        let casesByID = Dictionary(uniqueKeysWithValues: RichAnswerLiveCases.degradations.map {
            ($0.id, $0)
        })
        let decoder = JSONDecoder()
        var passed = 0
        var failures: [String] = []
        for recordURL in recordURLs {
            do {
                let record = try decoder.decode(
                    RichAnswerOfflineEvidenceRecord.self,
                    from: Data(contentsOf: recordURL)
                )
                guard record.caseSnapshot.caseKind == "degradation" else {
                    throw PiCheckError.invalidEvaluation(
                        "\(record.caseSnapshot.id) is \(record.caseSnapshot.caseKind), not degradation"
                    )
                }
                guard let checkCase = casesByID[record.caseSnapshot.id] else {
                    throw PiCheckError.invalidEvaluation(
                        "unknown degradation case \(record.caseSnapshot.id)"
                    )
                }
                let reply = try record.studyAgentReply()
                try validateRichAnswerDegradation(reply, for: checkCase)
                passed += 1
                print("offline-revalidate\tautomated-pass\t\(record.caseSnapshot.id)\t\(recordURL.path)")
            } catch {
                failures.append(
                    "offline-revalidate\tfail\t\(recordURL.path)\t\(error.localizedDescription)"
                )
            }
        }
        return RichAnswerOfflineRevalidation(
            automatedPassed: passed,
            reviewRequired: [],
            failures: failures
        )
    }

    private struct RichAnswerOfflineRevalidation {
        let automatedPassed: Int
        let reviewRequired: [String]
        let failures: [String]
    }

    private struct RichAnswerOfflineEvidenceRecord: Decodable {
        let caseSnapshot: CaseSnapshot
        let modelRawReply: ModelReply?

        struct CaseSnapshot: Decodable {
            let id: String
            let caseKind: String
        }

        struct ModelReply: Decodable {
            let backend: StudyAgentBackend?
            let text: String?
            let richAnswer: RichAnswerPresentation?
            let noteProposal: StudyAgentNoteProposal?
            let toolTrace: [String]?
        }

        func studyAgentReply() throws -> StudyAgentReply {
            guard let modelRawReply else {
                throw PiCheckError.invalidEvaluation(
                    "\(caseSnapshot.id) has no modelRawReply to revalidate"
                )
            }
            guard let backend = modelRawReply.backend else {
                throw PiCheckError.invalidEvaluation(
                    "\(caseSnapshot.id) modelRawReply missing backend"
                )
            }
            guard let text = modelRawReply.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PiCheckError.invalidEvaluation(
                    "\(caseSnapshot.id) modelRawReply missing text"
                )
            }
            return StudyAgentReply(
                text: text,
                backend: backend,
                richAnswer: modelRawReply.richAnswer,
                noteProposal: modelRawReply.noteProposal,
                toolTrace: modelRawReply.toolTrace ?? []
            )
        }
    }

    private static func isKnownRichAnswerFilter(_ filter: String) -> Bool {
        [
            "all",
            "rich",
            "success",
            "text",
            "text-only",
            "degradation",
            "degrade",
            "invalid",
            "invalid-protocol",
            "deterministic",
            "fault",
            "model",
            "t1",
            "t2",
        ].contains(filter)
    }

    private static func richAnswerRun(
        _ runCase: RichAnswerLiveRunCase,
        matchesAny filters: Set<String>
    ) -> Bool {
        let runSubject = runCase.subject.lowercased()
        let runID = runCase.id.lowercased()
        let materialKind = runCase.materialKind?.lowercased()
        let families = Set(runCase.expectedCapabilityFamilies.map { $0.lowercased() })
        return filters.contains("all")
            || filters.contains(runCase.caseKind)
            || filters.contains(runSubject)
            || filters.contains(runID)
            || materialKind.map { filters.contains($0) } == true
            || !families.isDisjoint(with: filters)
            || filters.contains(where: { filter in
                switch filter {
                case "rich", "success":
                    if case .success = runCase { return true }
                    return false
                case "text":
                    if case .textOnly = runCase { return true }
                    return false
                case "degrade":
                    if case .degradation = runCase { return true }
                    return false
                case "invalid", "deterministic":
                    if case .invalidProtocol = runCase { return true }
                    return false
                case "fault":
                    if case .invalidProtocol = runCase { return true }
                    if case .degradation = runCase { return true }
                    return false
                case "model":
                    return runCase.invokesModel
                case "t1":
                    if case let .success(checkCase) = runCase {
                        if case .t1 = checkCase.rendererRequirement { return true }
                    }
                    return false
                case "t2":
                    if case let .success(checkCase) = runCase {
                        if case .t2 = checkCase.rendererRequirement { return true }
                    }
                    return false
                default:
                    return runSubject.contains(filter)
                        || runID.contains(filter)
                        || materialKind?.contains(filter) == true
                        || families.contains(where: { $0.contains(filter) })
                }
            })
    }

    private static func richAnswerRequest(_ checkCase: RichAnswerLiveSuccessCase) -> StudyAgentRequest {
        let materialID = checkCase.materialID
        let noteID = "note-\(checkCase.id)"
        return StudyAgentRequest(
            purpose: .conversation,
            question: "这是自动验收题。回答依赖魏碑提供的当前材料或选区，请实际读取来源；如果无法读取，只说明无法读取来源，不要生成富回答。读取本轮来源后，检索本轮相关生成式 UI 能力，再生成一个紧凑、真正可操作、来源绑定的视觉体验块；本题明确要求 expressionPlan.preferredSurface 和 scene.placement 均为 inline，使它成为正文的自然一部分。请自主比较注册专业渲染计划、成熟深组件程序和受控长尾组合三条表达出口，以本题学习价值选择最合适的路线；不要把组件名、程序源码或 UI JSON 写进正文，不要穷举节点，也不要写成第二篇完整文章。\(checkCase.question)",
            materialTitle: checkCase.materialTitle,
            materialText: checkCase.materialText,
            noteTitle: "\(checkCase.discipline)验收笔记",
            noteText: "# \(checkCase.discipline)\n\n## 待整理",
            selectionTitle: checkCase.selectionTitle,
            selectionText: checkCase.selectionText,
            courseContext: StudyAgentCourseContext(
                title: "富回答真实模型验收",
                items: [
                    StudyAgentCourseItem(
                        id: materialID,
                        title: checkCase.materialTitle,
                        subtitle: checkCase.discipline,
                        kind: checkCase.materialKind,
                        role: "material",
                        isCurrentMaterial: true,
                        linkedItemIDs: [noteID],
                        headings: [checkCase.selectionTitle],
                        searchText: checkCase.materialText
                    ),
                    StudyAgentCourseItem(
                        id: noteID,
                        title: "\(checkCase.discipline)验收笔记",
                        subtitle: "Markdown",
                        kind: "markdown",
                        role: "note",
                        isCurrentNote: true,
                        linkedItemIDs: [materialID],
                        headings: ["待整理"],
                        searchText: checkCase.selectionText
                    ),
                ],
                relations: [
                    StudyAgentCourseRelation(noteItemID: noteID, sourceItemID: materialID),
                ]
            ),
            visualAssets: RichAnswerLiveVerificationAssets.visualAsset(
                for: checkCase.id,
                currentMaterialID: materialID
            ).map { [$0] } ?? [],
            learningContext: StudyAgentLearningContext(
                memoryRevision: 3,
                lastLocation: StudyLocation(
                    itemID: materialID,
                    itemTitle: checkCase.materialTitle,
                    locationTitle: checkCase.selectionTitle,
                    pageIndex: 1
                ),
                memories: [
                    LearningMemoryEntry(
                        kind: .confusion,
                        text: "需要用可交互可视化确认 \(checkCase.discipline) 里的关键关系",
                        evidence: "[用户：本轮] 要求富回答覆盖长尾请求并检查专业门槛",
                        origin: .userStatement
                    ),
                ],
                session: StudyAgentSessionSnapshot(
                    id: "pi-check-rich-answer-\(checkCase.id)",
                    title: "\(checkCase.discipline)富回答验收",
                    summary: "真实 Pi 需要把当前材料转成内联生成式 UI，而不是第二篇回答。",
                    phase: StudyPhase.explore.rawValue,
                    focusItemIDs: [materialID, noteID],
                    turnCount: 1
                )
            ),
            language: .chinese,
            contextRevision: checkCase.revision
        )
    }

    private static func richAnswerDegradationRequest(
        _ checkCase: RichAnswerLiveDegradationCase
    ) -> StudyAgentRequest {
        let materialID = "material-\(checkCase.id)"
        let noteID = "note-\(checkCase.id)"
        let hasMaterial = !checkCase.materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return StudyAgentRequest(
            purpose: .conversation,
            answerFormPolicy: checkCase.allowsPartialRichAnswer ? .partialRichAllowed : .textOnly,
            question: "这是回答失败与诚实降级验收题。答案依赖本题材料，请实际读取魏碑当前上下文和可用来源。不得用常识、示例数据或假执行补齐缺口；来源、安全或协议条件不满足时，保留简短可读正文并诚实说明限制。\(checkCase.question)",
            materialTitle: checkCase.materialTitle,
            materialText: checkCase.materialText,
            materialIsTruncated: checkCase.materialIsTruncated,
            noteTitle: "\(checkCase.pressureCase.subject)验收笔记",
            noteText: checkCase.noteText,
            selectionTitle: checkCase.selectionTitle,
            selectionText: checkCase.selectionText,
            courseContext: StudyAgentCourseContext(
                title: "富回答真实模型失败验收",
                items: [
                    StudyAgentCourseItem(
                        id: materialID,
                        title: checkCase.materialTitle,
                        subtitle: checkCase.pressureCase.subject,
                        kind: checkCase.materialKind,
                        role: "material",
                        isCurrentMaterial: true,
                        linkedItemIDs: [noteID],
                        headings: checkCase.selectionTitle.map { [$0] } ?? [],
                        searchText: checkCase.materialText,
                        isTruncated: checkCase.materialIsTruncated
                    ),
                    StudyAgentCourseItem(
                        id: noteID,
                        title: "\(checkCase.pressureCase.subject)验收笔记",
                        subtitle: "Markdown",
                        kind: "markdown",
                        role: "note",
                        isCurrentNote: true,
                        linkedItemIDs: hasMaterial ? [materialID] : [],
                        headings: [],
                        searchText: checkCase.noteText
                    ),
                ],
                relations: hasMaterial
                    ? [StudyAgentCourseRelation(noteItemID: noteID, sourceItemID: materialID)]
                    : []
            ),
            learningContext: .empty,
            language: .chinese,
            contextRevision: checkCase.revision
        )
    }

    private static func richAnswerTextOnlyRequest(
        _ checkCase: RichAnswerLiveTextOnlyCase
    ) -> StudyAgentRequest {
        let materialID = "material-\(checkCase.id)"
        let noteID = "note-\(checkCase.id)"
        return StudyAgentRequest(
            purpose: .conversation,
            question: "这是回答形态选择验收题。答案依赖本题材料，请实际读取魏碑当前材料或选区，然后自行选择最合适的回答形态；只有交互或可视关系能显著提高理解时才生成富回答，不要为了展示能力硬做 UI。\(checkCase.question)",
            materialTitle: checkCase.materialTitle,
            materialText: checkCase.materialText,
            noteTitle: "\(checkCase.subject)验收笔记",
            noteText: "",
            selectionTitle: checkCase.selectionTitle,
            selectionText: checkCase.selectionText,
            courseContext: StudyAgentCourseContext(
                title: "富回答形态选择验收",
                items: [
                    StudyAgentCourseItem(
                        id: materialID,
                        title: checkCase.materialTitle,
                        subtitle: checkCase.subject,
                        kind: checkCase.materialKind,
                        role: "material",
                        isCurrentMaterial: true,
                        linkedItemIDs: [noteID],
                        headings: [checkCase.selectionTitle],
                        searchText: checkCase.materialText
                    ),
                    StudyAgentCourseItem(
                        id: noteID,
                        title: "\(checkCase.subject)验收笔记",
                        subtitle: "Markdown",
                        kind: "markdown",
                        role: "note",
                        isCurrentNote: true,
                        linkedItemIDs: [materialID],
                        headings: [],
                        searchText: ""
                    ),
                ],
                relations: [
                    StudyAgentCourseRelation(noteItemID: noteID, sourceItemID: materialID),
                ]
            ),
            learningContext: .empty,
            language: .chinese,
            contextRevision: checkCase.revision
        )
    }

    private static func validateRichAnswer(
        _ reply: StudyAgentReply,
        for checkCase: RichAnswerLiveSuccessCase
    ) throws -> RichAnswerPresentation {
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              containsSourceLabel(reply.text),
              containsExpectedSource(reply.text, for: checkCase),
              replyToolTraceShowsCatalogBeforeRichAnswer(reply),
              let presentation = reply.richAnswer,
              presentation.mode == .rich,
              !presentation.scenes.isEmpty,
              presentation.diagnostics.isEmpty,
              presentation.evidenceState == .complete,
              !presentation.evidenceLedger.isEmpty,
              presentation.expressionPlan?.preferredSurface == .inline,
              presentation.expressionPlan?.directManipulation == true,
              presentation.scenes.allSatisfy({ $0.placement == .inline }) else {
            throw richAnswerFailure(reply, checkCase: checkCase)
        }

        let hasValidT1 = presentation.scenes.contains { validT1Scene($0, in: presentation, for: checkCase) }
        let hasValidT2 = presentation.scenes.contains { validT2Scene($0, for: checkCase) }
        let hasValidRenderPlan = presentation.scenes.contains { validRenderPlanScene($0) }
        guard hasValidT1 || hasValidT2 || hasValidRenderPlan else {
            throw richAnswerFailure(reply, checkCase: checkCase)
        }
        return presentation
    }

    private static func validateRichAnswerDegradation(
        _ reply: StudyAgentReply,
        for checkCase: RichAnswerLiveDegradationCase
    ) throws {
        let issues = richAnswerDegradationValidationIssues(reply, for: checkCase)
        guard issues.isEmpty else {
            throw PiCheckError.invalidEvaluation(
                "\(checkCase.id) degradation checks failed: \(issues.joined(separator: ","))"
            )
        }
    }

    private static func richAnswerDegradationValidationIssues(
        _ reply: StudyAgentReply,
        for checkCase: RichAnswerLiveDegradationCase
    ) -> [String] {
        var issues: [String] = []
        issues.append(contentsOf: richAnswerDegradationInvocationIssues(reply, for: checkCase))
        issues.append(contentsOf: richAnswerDegradationReadableLimitationIssues(reply, for: checkCase))
        issues.append(contentsOf: richAnswerDegradationSourceIssues(reply, for: checkCase))
        issues.append(contentsOf: richAnswerDegradationRichSceneIssues(reply, for: checkCase))
        return issues
    }

    private static func richAnswerDegradationInvocationIssues(
        _ reply: StudyAgentReply,
        for checkCase: RichAnswerLiveDegradationCase
    ) -> [String] {
        var issues: [String] = []
        if reply.backend != .pi { issues.append("backend-not-pi") }
        if reply.noteProposal != nil { issues.append("unexpected-note-proposal") }
        if !replyToolTraceContains(reply, token: "weibei_context") {
            issues.append("missing-context-read")
        }
        if !checkCase.allowsPartialRichAnswer {
            if replyToolTraceContains(reply, token: "weibei_ui_catalog") {
                issues.append("text-only-degradation-called-ui-catalog")
            }
            if replyToolTraceContains(reply, token: "host_rejected=text_only_policy") {
                issues.append("text-only-degradation-hit-host-rejection")
            }
            if !textOnlyChoiceHasNoDegradationDisclosure(reply.text) {
                issues.append("text-only-degradation-leaked-rich-answer-failure")
            }
        }
        return issues
    }

    private static func richAnswerDegradationReadableLimitationIssues(
        _ reply: StudyAgentReply,
        for checkCase: RichAnswerLiveDegradationCase
    ) -> [String] {
        var issues: [String] = []
        if reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("empty-degradation-answer")
        }
        let forbiddenClaims = forbiddenPositiveClaims(
            in: reply.text,
            fragments: checkCase.forbiddenTextFragments
        )
        if !forbiddenClaims.isEmpty {
            issues.append("forbidden-positive-claim:\(forbiddenClaims.joined(separator: "+"))")
        }
        if reply.text.contains("```json") || reply.text.contains("weibei.openui.v1") {
            issues.append("protocol-leakage-in-text")
        }
        return issues
    }

    private static func richAnswerDegradationSourceIssues(
        _ reply: StudyAgentReply,
        for checkCase: RichAnswerLiveDegradationCase
    ) -> [String] {
        if checkCase.expectsSourceCitation {
            if !containsSourceLabel(reply.text) {
                return ["missing-visible-source-label"]
            }
            let citesMaterial = reply.text.contains("[材料：\(checkCase.materialTitle)")
            let citesSelection = checkCase.selectionTitle.map {
                reply.text.contains("[选区：\($0)")
            } == true
            if !citesMaterial && !citesSelection {
                return ["missing-expected-source-label"]
            }
        }
        return []
    }

    private static func richAnswerDegradationRichSceneIssues(
        _ reply: StudyAgentReply,
        for checkCase: RichAnswerLiveDegradationCase
    ) -> [String] {
        guard checkCase.allowsPartialRichAnswer || reply.richAnswer == nil else {
            return ["rich-scene-not-allowed"]
        }
        guard let presentation = reply.richAnswer else { return [] }

        var issues: [String] = []
        if presentation.mode != .rich { issues.append("partial-rich-not-rich-mode") }
        if !presentation.diagnostics.isEmpty { issues.append("partial-rich-diagnostics-present") }
        if !replyToolTraceShowsCatalogBeforeRichAnswer(reply) {
            issues.append("partial-rich-missing-catalog-trace")
        }
        if checkCase.materialIsTruncated, presentation.evidenceState != .partial {
            issues.append("truncated-material-rich-not-partial")
        }
        let unsafeProgramFragments = unsafePartialRichProgramFragments(in: presentation)
        if !unsafeProgramFragments.isEmpty {
            issues.append("unsafe-partial-rich-program:\(unsafeProgramFragments.joined(separator: "+"))")
        }
        return issues
    }

    private static func validateRichAnswerTextOnly(
        _ reply: StudyAgentReply,
        for checkCase: RichAnswerLiveTextOnlyCase
    ) throws {
        guard reply.backend == .pi,
              reply.noteProposal == nil,
              reply.richAnswer == nil,
              replyToolTraceContains(reply, token: "weibei_context"),
              !replyToolTraceContains(reply, token: "weibei_ui_catalog"),
              !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              containsSourceLabel(reply.text),
              reply.text.contains("[材料：\(checkCase.materialTitle)")
                || reply.text.contains("[选区：\(checkCase.selectionTitle)"),
              textOnlyChoiceHasNoDegradationDisclosure(reply.text),
              checkCase.forbiddenTextFragments.allSatisfy({ !reply.text.localizedCaseInsensitiveContains($0) }) else {
            throw PiCheckError.invalidEvaluation(
                "\(checkCase.id) should stay a short source-grounded text answer without UI catalog work"
            )
        }
    }

    private static func textOnlyChoiceHasNoDegradationDisclosure(_ text: String) -> Bool {
        let degradationTerms = [
            "富回答没有通过", "富回答未通过", "富回答失败", "没有生成富回答", "未生成富回答",
            "本轮先保留文本解释", "rich answer failed", "rich answer did not pass",
            "could not generate a rich answer", "failed to generate a rich answer",
        ]
        return degradationTerms.allSatisfy { !text.localizedCaseInsensitiveContains($0) }
    }

    private static func validT1Scene(
        _ scene: RichAnswerScene,
        in presentation: RichAnswerPresentation,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> Bool {
        guard let program = scene.program,
              program.version == "weibei.openui.v1",
              program.directManipulation,
              checkCase.forbiddenProgramFragments.allSatisfy({
                  !program.source.localizedCaseInsensitiveContains($0)
              }),
              !scene.evidenceIDs.isEmpty else {
            return false
        }
        return true
    }

    private static func validT2Scene(
        _ scene: RichAnswerScene,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> Bool {
        t2ObjectiveSceneIssues(scene, for: checkCase).isEmpty
    }

    private static func t2ObjectiveSceneIssues(
        _ scene: RichAnswerScene,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> [String] {
        t2SceneIssues(scene, for: checkCase).filter { issue in
            issue == "missing-ui"
                || issue == "missing-direct-control"
                || issue == "missing-stateful-nontext-encoding"
                || issue.hasPrefix("unbound-evidence:")
                || issue.hasPrefix("missing-material-asset:")
        }
    }

    private static func validRenderPlanScene(_ scene: RichAnswerScene) -> Bool {
        guard let plan = scene.renderPlan else { return false }
        let negotiation = RichAnswerRendererRegistry.defaultRegistry().negotiate(plan: plan)
        guard negotiation.status == .accepted else { return false }
        let sceneEvidenceIDs = Set(scene.evidenceIDs)
        return plan.sourceBindings.allSatisfy { sceneEvidenceIDs.contains($0.evidenceID) }
    }

    private static func t2SceneIssues(
        _ scene: RichAnswerScene,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> [String] {
        guard let ui = scene.ui else { return ["missing-ui"] }
        var issues: [String] = []
        let roles = Set(ui.nodes.map(\.role))
        let directRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .select, .probe]
        if roles.isDisjoint(with: directRoles) {
            issues.append("missing-direct-control")
        }
        let visualValueRoles: Set<RichAnswerUIRole> = [
            .axis,
            .line,
            .path,
            .point,
            .area,
            .shape,
            .bar,
            .dotMatrix,
            .vector,
            .region,
            .image,
            .metric,
            .sequence,
            .canvas,
        ]
        let visualRoleCount = roles.intersection(visualValueRoles).count
        if visualRoleCount < 2 {
            issues.append("weak-visual-value:\(visualRoleCount)")
        }
        let expectedFamilies = checkCase.pressureCase.expectedCapabilityFamilies
        let familiesNeedingStatefulNonTextEncoding: Set<RichAnswerCapabilityFamily> = [
            .quantityAndCoordinates,
            .timeAndSpace,
            .relationAndEvidence,
            .imageAndOverlay,
            .comparisonAndEvaluation,
            .calculationAndConstraints,
        ]
        let needsStatefulNonTextEncoding =
            familiesNeedingStatefulNonTextEncoding.contains(scene.family)
            || !expectedFamilies.isDisjoint(with: familiesNeedingStatefulNonTextEncoding)
        if needsStatefulNonTextEncoding,
           !t2HasStateChangingNonTextEncoding(ui) {
            issues.append("missing-stateful-nontext-encoding")
        }
        if needsStatefulNonTextEncoding {
            let textReflowRoles = layoutOnlyT2Roles
                .union(directRoles)
                .union([.metric, .sequence])
            if roles.isSubset(of: textReflowRoles) {
                issues.append("text-reflow-ui")
            }
        }
        let layoutOnlyRoles: Set<RichAnswerUIRole> = [
            .vstack,
            .hstack,
            .zstack,
            .grid,
            .panel,
            .text,
            .label,
            .divider,
            .evidence,
        ]
        if roles.isSubset(of: layoutOnlyRoles.union(directRoles)) {
            issues.append("layout-only-ui")
        }
        let curveFriendlyFamilies: Set<RichAnswerCapabilityFamily> = [
            .quantityAndCoordinates,
            .comparisonAndEvaluation,
            .calculationAndConstraints,
        ]
        let embodiedRoles: Set<RichAnswerUIRole> = [
            .shape,
            .vector,
            .region,
            .image,
            .area,
            .sequence,
            .path,
            .point,
            .bar,
            .dotMatrix,
        ]
        if !checkCase.pressureCase.expectedCapabilityFamilies.isSubset(of: curveFriendlyFamilies),
           roles.isDisjoint(with: embodiedRoles) {
            issues.append("missing-embodied-primitive")
        }

        let boundEvidenceIDs = Set(
            ui.nodes.flatMap(\.evidenceIDs)
                + ui.datasets.flatMap { $0.rows.flatMap(\.evidenceIDs) }
        )
        let semanticCorpus = t2SemanticCorpus(ui)
        let dataRowCount = ui.datasets.reduce(0) { $0 + $1.rows.count }
        let unboundEvidenceIDs = Set(scene.evidenceIDs).subtracting(boundEvidenceIDs)
        if !unboundEvidenceIDs.isEmpty {
            issues.append("unbound-evidence:\(unboundEvidenceIDs.sorted().joined(separator: "+"))")
        }
        let matchedKnowledgeTargetCount = checkCase.knowledgeTargets.filter {
            containsAny(semanticCorpus, $0)
        }.count
        if matchedKnowledgeTargetCount < checkCase.minimumKnowledgeTargetMatches {
            issues.append(
                "knowledge-targets:\(matchedKnowledgeTargetCount)<\(checkCase.minimumKnowledgeTargetMatches)"
            )
        }
        let missingSemanticGroups = checkCase.semanticObligations.enumerated().compactMap { index, group in
            containsAny(semanticCorpus, group) ? nil : String(index + 1)
        }
        if !missingSemanticGroups.isEmpty {
            issues.append("missing-semantic-obligations:\(missingSemanticGroups.joined(separator: "+"))")
        }
        let missingInteractionOutcomes = checkCase.interactionOutcomes.enumerated().compactMap { index, obligation in
            obligation.allSatisfy { containsAny(semanticCorpus, $0) } ? nil : String(index + 1)
        }
        if !missingInteractionOutcomes.isEmpty {
            issues.append("missing-interaction-outcomes:\(missingInteractionOutcomes.joined(separator: "+"))")
        }
        if dataRowCount < checkCase.minimumT2DataRows {
            issues.append("data-rows:\(dataRowCount)<\(checkCase.minimumT2DataRows)")
        }
        if ui.bindings.count < checkCase.minimumT2Bindings {
            issues.append("bindings:\(ui.bindings.count)<\(checkCase.minimumT2Bindings)")
        }
        if checkCase.requiresMaterialAsset {
            if !ui.nodes.contains(where: {
                $0.role == .image && $0.assetID == checkCase.materialID
            }) {
                issues.append("missing-material-asset:\(checkCase.materialID)")
            }
        }
        return issues
    }

    private static var layoutOnlyT2Roles: Set<RichAnswerUIRole> {
        [
            .vstack,
            .hstack,
            .zstack,
            .grid,
            .panel,
            .text,
            .label,
            .divider,
            .evidence,
        ]
    }

    private static func t2HasStateChangingNonTextEncoding(_ ui: RichAnswerUIComposition) -> Bool {
        let controlRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .probe]
        let statefulNonTextRoles: Set<RichAnswerUIRole> = [
            .axis,
            .line,
            .path,
            .point,
            .area,
            .shape,
            .bar,
            .dotMatrix,
            .vector,
            .region,
            .image,
        ]
        let datasetsByID = Dictionary(
            ui.datasets.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return ui.bindings.contains { binding in
            let hasControl = ui.nodes.contains {
                $0.bindingID == binding.id && controlRoles.contains($0.role)
            }
            guard hasControl else { return false }
            return ui.nodes.contains { node in
                guard node.bindingID == binding.id,
                      statefulNonTextRoles.contains(node.role),
                      let datasetID = node.datasetID,
                      let dataset = datasetsByID[datasetID] else {
                    return false
                }
                return t2RowsHaveChangingNumericOutcome(dataset.rows)
            }
        }
    }

    private static func t2RowsHaveChangingNumericOutcome(_ rows: [RichAnswerUIDataRow]) -> Bool {
        guard rows.count >= 2 else { return false }
        let numericSets: [[Double]] = [
            rows.map(\.x),
            rows.map(\.y),
            rows.compactMap(\.x2),
            rows.compactMap(\.y2),
            rows.compactMap(\.value),
            rows.compactMap(\.result),
        ]
        return numericSets.contains { Set($0).count >= 2 }
    }

    private static func richAnswerFailure(
        _ reply: StudyAgentReply,
        checkCase: RichAnswerLiveSuccessCase
    ) -> PiCheckError {
        let presentation = reply.richAnswer
        let families = presentation?.scenes.map(\.family.rawValue).joined(separator: ",") ?? "none"
        let programCount = presentation?.scenes.filter { $0.program != nil }.count ?? 0
        let compositionCount = presentation?.scenes.filter { $0.ui != nil }.count ?? 0
        let renderPlanCount = presentation?.scenes.filter { $0.renderPlan != nil }.count ?? 0
        let diagnostics = presentation?.diagnostics.map(\.code.rawValue).joined(separator: ",") ?? "none"
        let programComponents = presentation?.scenes.compactMap(\.program?.source).flatMap { source in
            Array(t1ComponentNames(in: source)).sorted()
        }.joined(separator: ",") ?? "none"
        let roles = presentation?.scenes.flatMap { scene in
            scene.ui?.nodes.map(\.role.rawValue) ?? []
        }.joined(separator: ",") ?? "none"
        let t2Issues = presentation?.scenes.map { scene in
            let issues = t2SceneIssues(scene, for: checkCase)
            return "\(scene.id):\(issues.isEmpty ? "none" : issues.joined(separator: "+"))"
        }.joined(separator: "|") ?? "missing-presentation"
        let t2Semantics = presentation?.scenes.compactMap { scene -> String? in
            guard let ui = scene.ui else { return nil }
            let corpus = (
                ui.nodes.flatMap { node in
                    [node.label, node.text, node.unit, node.xAxis?.label, node.yAxis?.label]
                        .compactMap { $0 }
                }
                    + ui.datasets.flatMap { dataset in
                        dataset.rows.flatMap { row in
                            [row.label].compactMap { $0 }
                        }
                    }
            ).joined(separator: "/")
            return "\(scene.id):\(corpus.prefix(360))"
        }.joined(separator: "|") ?? "none"
        let placements = presentation?.scenes.map(\.placement.rawValue).joined(separator: ",") ?? "none"
        let hasValidT1 = presentation.map { currentPresentation in
            currentPresentation.scenes.contains {
                validT1Scene($0, in: currentPresentation, for: checkCase)
            }
        } ?? false
        let hasValidT2 = presentation?.scenes.contains { validT2Scene($0, for: checkCase) } ?? false
        let hasValidRenderPlan = presentation?.scenes.contains { validRenderPlanScene($0) } ?? false
        let renderPlans = presentation?.scenes.compactMap { scene in
            scene.renderPlan.map { "\($0.renderer)@\($0.specVersion)" }
        }.joined(separator: ",") ?? "none"
        let renderPlanIssues = presentation?.scenes.compactMap { scene -> String? in
            guard let plan = scene.renderPlan else { return nil }
            let result = RichAnswerRendererRegistry.defaultRegistry().negotiate(plan: plan)
            let issues = result.mismatch?.issues.map { issue in
                [issue.code.rawValue, issue.field].compactMap { $0 }.joined(separator: "@")
            } ?? []
            return "\(scene.id):\(issues.isEmpty ? "none" : issues.joined(separator: "+"))"
        }.joined(separator: "|") ?? "none"
        let professionalJudgment = presentation.map {
            professionalJudgmentValidation(reply: reply, presentation: $0, for: checkCase)
        }
        let preferredRendererMatches: Bool
        switch checkCase.rendererRequirement {
        case .either:
            preferredRendererMatches = hasValidT1 || hasValidT2 || hasValidRenderPlan
        case .t1:
            preferredRendererMatches = hasValidT1 || hasValidRenderPlan
        case .t2:
            preferredRendererMatches = hasValidT2 || hasValidRenderPlan
        }
        let rendererMatches = hasValidT1 || hasValidT2 || hasValidRenderPlan
        let familyMatches = presentation.map { richAnswerFamilyMatches($0, for: checkCase) } ?? false
        let interleaved = presentation.map {
            richAnswerLooksInterleaved(reply.text, presentation: $0)
        } ?? false
        let interleavingIssues = presentation.map {
            richAnswerInterleavingIssues(reply.text, presentation: $0).joined(separator: ",")
        } ?? "missing-presentation"
        let partSummary = presentation?.resolvedParts.map { part in
            switch part.kind {
            case .narrative:
                return "narrative:\(part.text?.count ?? 0)"
            case .scene:
                return "scene:\(part.sceneID ?? "missing")"
            }
        }.joined(separator: ",") ?? "none"
        let replySummary = reply.text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .prefix(420)
        let toolTrace = reply.toolTrace.joined(separator: ",")
        return .invalidEvaluation(
            "\(checkCase.id) backend=\(reply.backend.rawValue) source=\(containsSourceLabel(reply.text)) "
                + "expectedSource=\(containsExpectedSource(reply.text, for: checkCase)) "
                + "professionalFacts=\(presentation.map { professionalFactObligationsSatisfied(reply: reply, presentation: $0, for: checkCase) } ?? false) "
                + "missingFacts=\(presentation.map { missingProfessionalFactObligations(reply: reply, presentation: $0, for: checkCase).joined(separator: "+") } ?? "missing-presentation") "
                + "professionalJudgments=\(professionalJudgment?.passedDeterministicGates ?? false) "
                + "missingRequiredClaims=\(professionalJudgment?.missingRequiredClaims.joined(separator: "+") ?? "missing-presentation") "
                + "triggeredForbiddenClaims=\(professionalJudgment?.triggeredForbiddenClaims.joined(separator: "+") ?? "missing-presentation") "
                + "missingBoundaryClaims=\(professionalJudgment?.missingBoundaryClaims.joined(separator: "+") ?? "missing-presentation") "
                + "reviewRequired=\(professionalJudgment?.modelOrHumanReviewNotes.count ?? 0) "
                + "catalogFirst=\(replyToolTraceShowsCatalogBeforeRichAnswer(reply)) "
                + "presentation=\(presentation != nil) mode=\(presentation?.mode.rawValue ?? "none") "
                + "evidence=\(presentation?.evidenceState.rawValue ?? "none") "
                + "preferred=\(presentation?.expressionPlan?.preferredSurface.rawValue ?? "none") "
                + "direct=\(presentation?.expressionPlan?.directManipulation ?? false) "
                + "placements=\(placements) familyMatch=\(familyMatches) renderer=\(rendererMatches) preferredRenderer=\(preferredRendererMatches) "
                + "validT1=\(hasValidT1) validT2=\(hasValidT2) validRenderPlan=\(hasValidRenderPlan) interleaved=\(interleaved) "
                + "interleavingIssues=\(interleavingIssues) parts=\(partSummary) "
                + "families=\(families) components=\(programComponents) roles=\(roles) "
                + "t1=\(programCount) t2=\(compositionCount) renderPlans=\(renderPlanCount):\(renderPlans) renderPlanIssues=\(renderPlanIssues) t2Issues=\(t2Issues) t2Semantics=\(t2Semantics) diagnostics=\(diagnostics) "
                + "tools=\(toolTrace) reply=\(replySummary)"
        )
    }

    private static func richAnswerFamilyMatches(
        _ presentation: RichAnswerPresentation,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> Bool {
        let expectedFamilies = checkCase.pressureCase.expectedCapabilityFamilies
        if let planFamilies = presentation.expressionPlan?.families,
           !planFamilies.isDisjoint(with: expectedFamilies) {
            return true
        }
        return presentation.scenes.contains {
            richAnswerFamilyMatches(presentation, scene: $0, for: checkCase)
        }
    }

    private static func richAnswerFamilyMatches(
        _ presentation: RichAnswerPresentation,
        scene: RichAnswerScene,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> Bool {
        let expectedFamilies = checkCase.pressureCase.expectedCapabilityFamilies
        if expectedFamilies.contains(scene.family) { return true }
        if let planFamilies = presentation.expressionPlan?.families,
           !planFamilies.isDisjoint(with: expectedFamilies) {
            return true
        }
        if let program = scene.program,
           !inferredT1Families(
               componentNames: t1ComponentNames(in: program.source),
               capabilities: program.capabilities
           ).isDisjoint(with: expectedFamilies) {
            return true
        }
        if let ui = scene.ui,
           !inferredT2Families(ui: ui).isDisjoint(with: expectedFamilies) {
            return true
        }
        return false
    }

    private static func inferredT1Families(
        componentNames: Set<String>,
        capabilities: [String]
    ) -> Set<RichAnswerCapabilityFamily> {
        var families: Set<RichAnswerCapabilityFamily> = []
        let capabilityText = capabilities.joined(separator: " ").lowercased()
        if !componentNames.isDisjoint(with: [
            "FunctionPlot",
            "LinkedDataChart",
            "DistributionBrush",
            "MetricStrip",
            "ParameterReadout",
        ]) || capabilityText.contains("plot") || capabilityText.contains("chart") {
            families.insert(.quantityAndCoordinates)
        }
        if !componentNames.isDisjoint(with: [
            "ProcessStepper",
            "QuadraticMechanism",
            "ExecutionTrack",
            "BalanceExperiment",
            "CausalTrack",
            "LearningStage",
        ]) || capabilityText.contains("step") || capabilityText.contains("state") || capabilityText.contains("track") {
            families.insert(.processAndState)
        }
        if !componentNames.isDisjoint(with: [
            "ArgumentReader",
            "ArgumentUnit",
            "EvidenceSnippet",
            "CausalTrack",
            "DependencyFlow",
            "DependencyNode",
            "ComparisonTable",
        ]) || capabilityText.contains("evidence") || capabilityText.contains("causal") {
            families.insert(.relationAndEvidence)
        }
        if !componentNames.isDisjoint(with: [
            "LayeredSpatialView",
            "SpatialPath",
            "SpatialPoint",
            "SpatialRegion",
            "CausalTrack",
        ]) || capabilityText.contains("spatial") || capabilityText.contains("map") {
            families.insert(.timeAndSpace)
        }
        if !componentNames.isDisjoint(with: ["ImageOverlay", "ObservationLens", "SpatialRegion"]) {
            families.insert(.imageAndOverlay)
        }
        if !componentNames.isDisjoint(with: ["ComparisonTable", "ComparisonRow", "ValuePicker"]) {
            families.insert(.comparisonAndEvaluation)
        }
        if !componentNames.isDisjoint(with: ["BalanceExperiment", "DependencyFlow", "MetricStrip"]) {
            families.insert(.calculationAndConstraints)
        }
        if !componentNames.isDisjoint(with: ["ArgumentReader", "ArgumentUnit"]) {
            families.insert(.textAndAlignment)
        }
        return families
    }

    private static func inferredT2Families(ui: RichAnswerUIComposition) -> Set<RichAnswerCapabilityFamily> {
        let roles = Set(ui.nodes.map(\.role))
        var families: Set<RichAnswerCapabilityFamily> = []
        let controlRoles: Set<RichAnswerUIRole> = [.slider, .toggle, .scrubber, .select, .probe]
        let quantitativeRoles: Set<RichAnswerUIRole> = [.axis, .line, .path, .point, .area, .bar, .dotMatrix, .metric]
        if !roles.isDisjoint(with: quantitativeRoles), !ui.datasets.isEmpty {
            families.insert(.quantityAndCoordinates)
        }
        if !roles.isDisjoint(with: [.sequence, .scrubber, .toggle, .select, .probe]) {
            families.insert(.processAndState)
        }
        if roles.contains(.evidence)
            || (!roles.isDisjoint(with: [.path, .line, .vector, .point]) && roles.contains(.label)) {
            families.insert(.relationAndEvidence)
        }
        if roles.contains(.canvas),
           !roles.isDisjoint(with: [.path, .point, .region, .vector, .shape, .area, .image, .sequence]) {
            families.insert(.timeAndSpace)
        }
        if roles.contains(.image) {
            families.insert(.imageAndOverlay)
        }
        if !roles.isDisjoint(with: [.grid, .hstack, .vstack]),
           !roles.isDisjoint(with: [.metric, .bar, .dotMatrix, .text, .label]) {
            families.insert(.comparisonAndEvaluation)
        }
        if !ui.bindings.isEmpty,
           !roles.isDisjoint(with: controlRoles),
           !roles.isDisjoint(with: [.metric, .axis, .line, .path, .bar, .shape, .area]) {
            families.insert(.calculationAndConstraints)
        }
        if !roles.isDisjoint(with: [.text, .label, .evidence]),
           !roles.isDisjoint(with: controlRoles) {
            families.insert(.textAndAlignment)
        }
        return families
    }

    private static func t1ComponentNames(in source: String) -> Set<String> {
        let pattern = #"\b([A-Z][A-Za-z0-9_]*)\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(regex.matches(in: source, range: range).compactMap { match in
            guard let componentRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[componentRange])
        })
    }

    private static func t2SemanticCorpus(_ ui: RichAnswerUIComposition) -> String {
        (
            ui.nodes.flatMap { node in
                [node.label, node.text, node.unit, node.xAxis?.label, node.yAxis?.label]
                    .compactMap { $0 }
            }
                + ui.datasets.flatMap { dataset in
                    dataset.rows.flatMap { row in
                        [
                            row.label,
                            String(row.x),
                            String(row.y),
                            row.x2.map { String($0) },
                            row.y2.map { String($0) },
                            row.value.map { String($0) },
                            row.result.map { String($0) },
                        ].compactMap { $0 }
                    }
                }
                + ui.bindings.flatMap { binding in
                    [
                        binding.label,
                        binding.unit,
                        String(binding.minimum),
                        String(binding.maximum),
                        String(binding.initialValue),
                    ].compactMap { $0 }
                }
        ).joined(separator: " ")
    }

    private static func professionalFactObligationsSatisfied(
        reply: StudyAgentReply,
        presentation: RichAnswerPresentation,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> Bool {
        missingProfessionalFactObligations(reply: reply, presentation: presentation, for: checkCase).isEmpty
            && professionalJudgmentValidation(
                reply: reply,
                presentation: presentation,
                for: checkCase
            ).triggeredForbiddenClaims.isEmpty
    }

    private static func missingProfessionalFactObligations(
        reply: StudyAgentReply,
        presentation: RichAnswerPresentation,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> [String] {
        let corpus = professionalFactCorpus(reply: reply, presentation: presentation)
        return checkCase.professionalFactObligations.compactMap { obligation in
            obligation.evidenceGroups.allSatisfy { containsAny(corpus, $0) }
                ? nil
                : obligation.id
        }
    }

    private static func professionalFactCorpus(
        reply: StudyAgentReply,
        presentation: RichAnswerPresentation
    ) -> String {
        professionalClaimBearingUnits(reply: reply, presentation: presentation)
            .joined(separator: " ")
    }

    private static func professionalJudgmentValidation(
        reply: StudyAgentReply,
        presentation: RichAnswerPresentation,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> RichAnswerProfessionalJudgmentValidation {
        RichAnswerProfessionalJudgmentValidator.validate(
            units: professionalJudgmentUnits(reply: reply, presentation: presentation),
            contract: checkCase.professionalJudgmentContract
        )
    }

    static func professionalJudgmentUnits(
        reply: StudyAgentReply,
        presentation: RichAnswerPresentation
    ) -> [String] {
        professionalClaimBearingUnits(reply: reply, presentation: presentation)
            .flatMap(RichAnswerProfessionalJudgmentValidator.claimUnits)
    }

    private static func professionalClaimBearingUnits(
        reply: StudyAgentReply,
        presentation: RichAnswerPresentation
    ) -> [String] {
        [
            reply.text,
            presentation.narrative,
            presentation.expressionPlan?.summary,
        ].compactMap { $0 }
            + presentation.scenes.flatMap { scene in
                (scene.program.map { t1ProfessionalClaimUnits($0.source) } ?? [])
                    + (scene.ui.map(t2ProfessionalClaimUnits) ?? [])
            }
    }

    private static func t1ProfessionalClaimUnits(_ source: String) -> [String] {
        let pureEvidenceComponents: Set<String> = ["EvidenceSnippet"]
        return source.components(separatedBy: .newlines).filter { statement in
            guard let componentName = t1DeclaredComponentName(in: statement) else { return true }
            return !pureEvidenceComponents.contains(componentName)
        }
    }

    private static func t1DeclaredComponentName(in statement: String) -> String? {
        let pattern = #"^\s*[A-Za-z_][A-Za-z0-9_]*\s*=\s*([A-Z][A-Za-z0-9_]*)\s*\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(statement.startIndex..<statement.endIndex, in: statement)
        guard let match = regex.firstMatch(in: statement, range: range),
              let componentRange = Range(match.range(at: 1), in: statement) else {
            return nil
        }
        return String(statement[componentRange])
    }

    private static func t2ProfessionalClaimUnits(_ ui: RichAnswerUIComposition) -> [String] {
        let visibleClaimNodes = t2ReachableNonEvidenceNodes(in: ui)
        let visibleDatasetIDs = Set(visibleClaimNodes.compactMap(\.datasetID))
        let visibleBindingIDs = Set(visibleClaimNodes.compactMap(\.bindingID))
        let nodeUnits = visibleClaimNodes.flatMap { node in
            [node.label, node.text, node.unit, node.xAxis?.label, node.yAxis?.label]
                .compactMap { $0 }
        }
        let datasetUnits = ui.datasets
            .filter { visibleDatasetIDs.contains($0.id) }
            .flatMap { dataset in
                dataset.rows.map { row in
                    [
                        row.label,
                        String(row.x),
                        String(row.y),
                        row.x2.map { String($0) },
                        row.y2.map { String($0) },
                        row.value.map { String($0) },
                        row.result.map { String($0) },
                    ].compactMap { $0 }.joined(separator: " ")
                }
            }
        let bindingUnits = ui.bindings
            .filter { visibleBindingIDs.contains($0.id) }
            .map { binding in
                [
                    binding.label,
                    binding.unit,
                    String(binding.minimum),
                    String(binding.maximum),
                    String(binding.initialValue),
                ].compactMap { $0 }.joined(separator: " ")
            }
        return nodeUnits + datasetUnits + bindingUnits
    }

    private static func t2ReachableNonEvidenceNodes(
        in ui: RichAnswerUIComposition
    ) -> [RichAnswerUINode] {
        let nodesByID = Dictionary(
            ui.nodes.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var visited: Set<String> = []
        var visibleClaimNodeIDs: Set<String> = []
        var pendingNodeIDs = [ui.rootID]
        while let nodeID = pendingNodeIDs.popLast() {
            guard visited.insert(nodeID).inserted,
                  let node = nodesByID[nodeID] else {
                continue
            }
            guard node.role != .evidence else { continue }
            visibleClaimNodeIDs.insert(nodeID)
            pendingNodeIDs.append(contentsOf: node.children.reversed())
        }
        return ui.nodes.filter { visibleClaimNodeIDs.contains($0.id) }
    }

    private static func containsExpectedSource(
        _ text: String,
        for checkCase: RichAnswerLiveSuccessCase
    ) -> Bool {
        text.contains("[材料：\(checkCase.materialTitle)")
            || text.contains("[选区：\(checkCase.selectionTitle)")
    }

    private static func containsAny(_ text: String, _ fragments: [String]) -> Bool {
        let normalizedText = normalizedSemanticText(text)
        return fragments.contains {
            normalizedText.contains(normalizedSemanticText($0))
        }
    }

    private static func containsEveryGroup(_ text: String, _ groups: [[String]]) -> Bool {
        groups.allSatisfy { containsAny(text, $0) }
    }

    private static func forbiddenPositiveClaims(
        in text: String,
        fragments: [String]
    ) -> [String] {
        let sentences = text.components(
            separatedBy: CharacterSet(charactersIn: "。！？；\n\r")
        )
        return fragments.filter { fragment in
            sentences.contains { sentence in
                sentence.localizedCaseInsensitiveContains(fragment)
                    && !sentenceNegatesForbiddenClaim(fragment, in: sentence)
            }
        }
    }

    private static func sentenceNegatesForbiddenClaim(
        _ fragment: String,
        in sentence: String
    ) -> Bool {
        guard let range = sentence.range(
            of: fragment,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) else {
            return false
        }
        let before = String(sentence[..<range.lowerBound].suffix(24))
        let after = String(sentence[range.upperBound...].prefix(12))
        let localContext = before + fragment + after
        let localNegationCues = [
            "不能", "无法", "不得", "不要", "不应", "不可以", "不可", "禁止",
            "拒绝", "未", "尚未", "没有", "并非", "不是", "不再",
        ]
        if localNegationCues.contains(where: { before.contains($0) || localContext.contains($0) }) {
            return true
        }
        let explicitSpeechCues = [
            "不能声称", "不得声称", "不要声称", "不应声称", "不可声称",
            "不能说", "不得说", "不要说", "不应说",
        ]
        return explicitSpeechCues.contains { localContext.contains($0) }
    }

    private static func unsafePartialRichProgramFragments(
        in presentation: RichAnswerPresentation
    ) -> [String] {
        let unsafeFragments = ["<svg", "<script", "<iframe", "http://", "https://", "~/", "file://"]
        return Array(Set(presentation.scenes.compactMap(\.program?.source).flatMap { source in
            unsafeFragments.filter { source.localizedCaseInsensitiveContains($0) }
        })).sorted()
    }

    private static func latencyCheck(_ elapsedSeconds: TimeInterval, threshold: TimeInterval) -> String {
        let thresholdText = String(format: "%.0f", threshold)
        if elapsedSeconds <= threshold {
            return "latency<=\(thresholdText)s"
        }
        let elapsedText = String(format: "%.1f", elapsedSeconds)
        return "latency-warning>\(thresholdText)s:\(elapsedText)s"
    }

    private static func normalizedSemanticText(_ text: String) -> String {
        RichAnswerProfessionalJudgmentValidator.normalizedText(text)
    }

    private static func replyToolTraceShowsCatalogBeforeRichAnswer(_ reply: StudyAgentReply) -> Bool {
        let traceEntries = reply.toolTrace
        guard let catalogIndex = traceEntries.firstIndex(where: { $0.contains("weibei_ui_catalog") }) else {
            return false
        }
        let richAnswerTokens = [
            "rich_answer",
            "richAnswer",
            "openui",
            "OpenUI",
            "weibei.openui.v1",
        ]
        guard let richAnswerIndex = traceEntries.firstIndex(where: { entry in
            !entry.contains("weibei_ui_catalog") && containsAny(entry, richAnswerTokens)
        }) else {
            return true
        }
        return catalogIndex <= richAnswerIndex
    }

    private static func replyToolTraceContains(_ reply: StudyAgentReply, token: String) -> Bool {
        reply.toolTrace.contains { $0.contains(token) }
    }

    private static func richAnswerLooksInterleaved(
        _ text: String,
        presentation: RichAnswerPresentation
    ) -> Bool {
        let objectiveIssuePrefixes = [
            "empty-text",
            "code-fence",
            "protocol-in-text",
            "program-in-text",
            "root-in-text",
            "page-heading",
            "scene-first",
            "missing-narrative-part",
            "missing-scene-part",
            "scene-set-mismatch",
        ]
        return richAnswerInterleavingIssues(text, presentation: presentation).allSatisfy { issue in
            !objectiveIssuePrefixes.contains { issue.hasPrefix($0) }
        }
    }

    private static func richAnswerInterleavingIssues(
        _ text: String,
        presentation: RichAnswerPresentation
    ) -> [String] {
        var issues: [String] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { issues.append("empty-text") }
        if trimmed.count > 1_800 { issues.append("text-over-budget:\(trimmed.count)") }
        if trimmed.contains("```") { issues.append("code-fence") }
        if trimmed.contains("weibei.openui.v1") { issues.append("protocol-in-text") }
        if trimmed.contains("OpenUIProgram(") { issues.append("program-in-text") }
        if trimmed.contains("RichAnswerRoot(") { issues.append("root-in-text") }
        let headings = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("#") }
        let pageHeadingCount = headings.filter { $0.hasPrefix("# ") }.count
        if pageHeadingCount > 0 { issues.append("page-heading:\(pageHeadingCount)") }
        if headings.count > 4 || (headings.count > 1 && headings.count * 180 > trimmed.count) {
            issues.append("heading-heavy:\(headings.count)")
        }

        let parts = presentation.resolvedParts
        if parts.first?.kind != .narrative { issues.append("scene-first") }
        if !parts.contains(where: { $0.kind == .narrative }) { issues.append("missing-narrative-part") }
        if !parts.contains(where: { $0.kind == .scene }) { issues.append("missing-scene-part") }
        let renderedSceneIDs = Set(parts.compactMap { part in
            part.kind == .scene ? part.sceneID : nil
        })
        if renderedSceneIDs != Set(presentation.scenes.map(\.id)) {
            issues.append("scene-set-mismatch")
        }
        return issues
    }

    private static func containsSourceLabel(_ text: String) -> Bool {
        text.contains("[选区：")
            || text.contains("[材料：")
            || text.contains("[笔记：")
            || text.contains("[学习记录：")
            || text.contains("[学习记忆：")
    }

    private static func verifyPersistedSessionStateAfterShutdown(
        _ runtimeRoot: URL,
        expectedSessionID: UUID?
    ) throws {
        let fileManager = FileManager.default
        let contextURL = runtimeRoot.appendingPathComponent("context.json")
        guard !fileManager.fileExists(atPath: contextURL.path) else {
            throw PiCheckError.persistedTurnState
        }
        guard let expectedSessionID else { return }
        let sessionDirectory = runtimeRoot
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(
                expectedSessionID.uuidString.lowercased(),
                isDirectory: true
            )
        let sessionFiles = try fileManager.contentsOfDirectory(
            at: sessionDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard sessionFiles.contains(where: { url in
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            ) else {
                return false
            }
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }) else {
            throw PiCheckError.persistedTurnState
        }
    }
}

private extension RichAnswerEvidenceRunConfiguration {
    var expectsFullMatrixSelection: Bool {
        requestedIDs.isEmpty
            && filters.isEmpty
            && offset == nil
            && limit == nil
    }
}

private struct RichAnswerEvidencePackageGateDocument: Decodable {
    let summary: RichAnswerEvidencePackageSummary
}

private struct RichAnswerEvidencePackageGateReport {
    let summary: RichAnswerEvidencePackageSummary
    let packageJSONURL: URL

    var metrics: String {
        [
            "state=\(summary.completionState)",
            "firstRoundRecords=\(summary.firstPassRecordCount)/\(summary.expectedFirstPassRecordCount)",
            "fourRoundRecords=\(summary.threeRoundRecordCount)/\(summary.expectedThreeRoundRecordCount)",
            "trusted=\(summary.threeRoundTrustedInvocationCount)/\(summary.expectedThreeRoundRecordCount)",
            "packageEvidence=\(summary.threeRoundCompleteEvidenceCount)/\(summary.expectedThreeRoundRecordCount)",
            "screenshots=\(summary.threeRoundScreenshotImageCount)/\(summary.expectedThreeRoundScreenshotImageCount)",
            "humanReview=\(summary.reviewCompleteAttemptCount)/\(summary.expectedThreeRoundRecordCount)",
            "experience=\(summary.experiencePassedAttemptCount)/\(summary.expectedThreeRoundRecordCount)",
            "packageJSON=\(packageJSONURL.path)",
        ].joined(separator: " ")
    }

    var gateFailures: [String] {
        var failures: [String] = []
        if summary.completionState != "待用户验收" {
            failures.append("completionState=\(summary.completionState)")
        }
        if summary.uniqueCaseCount != summary.requiredCaseCount {
            failures.append("cases=\(summary.uniqueCaseCount)/\(summary.requiredCaseCount)")
        }
        if summary.firstPassRecordCount != summary.expectedFirstPassRecordCount {
            failures.append("firstRoundRecords=\(summary.firstPassRecordCount)/\(summary.expectedFirstPassRecordCount)")
        }
        if summary.firstPassTrustedInvocationCount != summary.expectedFirstPassRecordCount {
            failures.append("firstRoundTrusted=\(summary.firstPassTrustedInvocationCount)/\(summary.expectedFirstPassRecordCount)")
        }
        if summary.firstPassCompleteEvidenceCount != summary.expectedFirstPassRecordCount {
            failures.append("firstRoundPackageEvidence=\(summary.firstPassCompleteEvidenceCount)/\(summary.expectedFirstPassRecordCount)")
        }
        if summary.threeRoundRecordCount != summary.expectedThreeRoundRecordCount {
            failures.append("fourRoundRecords=\(summary.threeRoundRecordCount)/\(summary.expectedThreeRoundRecordCount)")
        }
        if summary.threeRoundTrustedInvocationCount != summary.expectedThreeRoundRecordCount {
            failures.append("fourRoundTrusted=\(summary.threeRoundTrustedInvocationCount)/\(summary.expectedThreeRoundRecordCount)")
        }
        if summary.threeRoundCompleteEvidenceCount != summary.expectedThreeRoundRecordCount {
            failures.append("fourRoundPackageEvidence=\(summary.threeRoundCompleteEvidenceCount)/\(summary.expectedThreeRoundRecordCount)")
        }
        if summary.threeRoundPassedCount != summary.expectedThreeRoundRecordCount {
            failures.append("fourRoundTechnicalStatus=\(summary.threeRoundPassedCount)/\(summary.expectedThreeRoundRecordCount)")
        }
        if !summary.screenshotMinimumSatisfied || summary.screenshotGapAttemptCount > 0 || summary.screenshotMissingImageCount > 0 {
            failures.append(
                "screenshots=\(summary.threeRoundScreenshotImageCount)/\(summary.expectedThreeRoundScreenshotImageCount), gaps=\(summary.screenshotGapAttemptCount), missingImages=\(summary.screenshotMissingImageCount)"
            )
        }
        if summary.reviewCompleteAttemptCount != summary.expectedThreeRoundRecordCount || summary.reviewGapItemCount > 0 {
            failures.append(
                "humanReview=\(summary.reviewCompleteAttemptCount)/\(summary.expectedThreeRoundRecordCount), gapItems=\(summary.reviewGapItemCount)"
            )
        }
        if summary.experiencePassedAttemptCount != summary.expectedThreeRoundRecordCount {
            failures.append("experience=\(summary.experiencePassedAttemptCount)/\(summary.expectedThreeRoundRecordCount)")
        }
        if !summary.missingFirstPassCaseIDs.isEmpty {
            failures.append("missingFirstRoundCases=\(summary.missingFirstPassCaseIDs.count)")
        }
        if !summary.missingThreeRoundRecordKeys.isEmpty {
            failures.append("missingFourRoundRecords=\(summary.missingThreeRoundRecordKeys.count)")
        }
        if !summary.missingRecordEvidenceKeys.isEmpty {
            failures.append("missingRecordEvidence=\(summary.missingRecordEvidenceKeys.count)")
        }
        if !summary.fixtureOrUntrustedRecordKeys.isEmpty {
            failures.append("fixtureOrUntrustedRecords=\(summary.fixtureOrUntrustedRecordKeys.count)")
        }
        if !summary.baselineMismatchKeys.isEmpty {
            failures.append("baselineMismatches=\(summary.baselineMismatchKeys.count)")
        }
        if !summary.shapeDriftCaseIDs.isEmpty {
            failures.append("shapeDriftCases=\(summary.shapeDriftCaseIDs.count)")
        }
        if !summary.contentDriftCaseIDs.isEmpty {
            failures.append("contentDriftCases=\(summary.contentDriftCaseIDs.count)")
        }
        return failures
    }

    static func load(reviewPackageURL: URL) throws -> Self {
        let packageJSONURL = reviewPackageURL
            .deletingLastPathComponent()
            .appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: packageJSONURL.path) else {
            throw RichAnswerEvidenceError.invalidConfiguration(
                "rich-answer evidence package gate requires package.json at \(packageJSONURL.path)"
            )
        }
        let document = try JSONDecoder().decode(
            RichAnswerEvidencePackageGateDocument.self,
            from: Data(contentsOf: packageJSONURL)
        )
        return Self(summary: document.summary, packageJSONURL: packageJSONURL)
    }
}

private enum PiCheckError: LocalizedError {
    case invalidLiveReply
    case invalidEvaluation(String)
    case missingIsolatedConfiguration
    case persistedTurnState

    var errorDescription: String? {
        switch self {
        case .invalidLiveReply:
            "PI returned no revision-matched note proposal"
        case let .invalidEvaluation(name):
            "PI evaluation failed: \(name)"
        case .missingIsolatedConfiguration:
            "PI did not use an isolated WeiBei configuration directory"
        case .persistedTurnState:
            "PI did not keep only durable per-Chat sessions after shutdown"
        }
    }
}
