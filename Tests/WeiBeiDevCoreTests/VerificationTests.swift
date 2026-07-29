import AppKit
import Foundation
import XCTest
@testable import WeiBeiDevCore
import WeiBeiCore

final class VerificationTests: XCTestCase {
    /// Rejects run identifiers that could resolve to the artifact root or its parent.
    func testArtifactStoreRejectsTraversalComponents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VerificationArtifacts-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for runID in ["", ".", ".."] {
            XCTAssertThrowsError(try VerificationArtifactStore(rootURL: root, runID: runID)) { error in
                XCTAssertEqual((error as? VerificationError)?.code, "artifact_run_id_invalid")
            }
        }
    }

    private var temporaryDirectories: [URL] = []

    /// 清理此套件实例创建的全部验收临时目录。
    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    /// 裸 verify 严格恢复为旧入口的单一离线学习场景。
    func testRegistryContainsSingleDefaultOfflineScenario() {
        let registry = VerificationScenarioRegistry()

        XCTAssertEqual(registry.defaultScenarios.map(\.id), [.offlineLearningFlow])
        XCTAssertTrue(registry.defaultScenarios.allSatisfy { !$0.requirements.requiresOnlinePI })
    }

    /// 显式全部场景仍包含所有离线行为、视觉和 Rich Answer 场景。
    func testRegistryAllScenariosContainsEveryOfflineScenario() {
        let registry = VerificationScenarioRegistry()
        let selected = registry.allScenarios(includeLivePI: false)

        let expectedOfflineIDs: Set<VerificationScenarioID> = [
            .offlineLearningFlow,
            .immersiveConversationFlow,
            .emptyWorkspaceInspirationOff,
            .emptyWorkspaceOpenDoc,
            .emptyWorkspaceOpenChat,
            .emptyWorkspaceOpenNotes,
            .linkedSourcesFlow,
            .courseWorkspaceOverviewFlow,
            .courseWorkspaceWorkflowFlow,
            .paneToggleContinuityFlow,
            .paneLayoutStabilityFlow,
            .paneReorderWidthFlow,
            .readerScrollPersistenceFlow,
            .emptyWorkspaceLightWide,
            .emptyWorkspaceLightNarrow,
            .emptyWorkspaceDarkWide,
            .emptyWorkspaceDarkNarrow,
            .emptyWorkspaceCalligraphyLight,
            .emptyWorkspaceCalligraphyDark,
            .notebookCreationFlow,
            .pureWritingFlow,
            .contentRailDormantPreview,
            .contentRailActivationPreview,
            .loadingIndicatorSamples,
            .richAnswerPreview,
            .richAnswerGallery,
            .richAnswerOpenUI,
            .richAnswerOpenUIExtended,
            .richAnswerOpenUIExtendedInline,
            .richAnswerText,
            .richAnswerQuantity,
            .richAnswerProcess,
            .richAnswerRelation,
            .richAnswerTimeline,
            .richAnswerSpace,
            .richAnswerImage,
            .richAnswerComparison,
            .richAnswerCalculation,
            .richAnswerPendulum,
            .richAnswerSequence,
        ]

        XCTAssertEqual(Set(selected.map(\.id)), expectedOfflineIDs)
        XCTAssertFalse(selected.contains { $0.requirements.requiresOnlinePI })
        XCTAssertEqual(
            Set(registry.allScenarios(includeLivePI: true).map(\.id)),
            expectedOfflineIDs.union([.piLearningFlow, .piCourseMemoryFlow])
        )
    }

    /// Rich Answer 场景完整注册为显式、非默认的视觉验收场景。
    func testRegistryContainsSixteenNonDefaultRichAnswerScenarios() throws {
        let registry = VerificationScenarioRegistry()
        let declaredIDs = VerificationScenarioRegistry.richAnswerScenarioIDs
        let registeredIDs = Set(
            registry.scenarios
                .map(\.id)
                .filter { $0.rawValue.hasPrefix("rich-answer-") }
        )
        let scenarios = try declaredIDs.map { id in
            try XCTUnwrap(registry.scenario(named: id.rawValue))
        }

        XCTAssertEqual(registeredIDs, declaredIDs)
        XCTAssertEqual(scenarios.count, 16)
        XCTAssertTrue(scenarios.allSatisfy(\.requirements.requiresVisualInspection))
        XCTAssertTrue(scenarios.allSatisfy { $0.resultContract == .visualOnly })
        XCTAssertTrue(scenarios.allSatisfy { !$0.isDefault })
    }

    /// 注册表将在线 PI 和视觉要求作为类型化元数据暴露。
    func testRegistryDistinguishesOnlineAndVisualScenarios() throws {
        let registry = VerificationScenarioRegistry()

        let online = try XCTUnwrap(registry.scenario(named: "pi-learning-flow"))
        let visual = try XCTUnwrap(registry.scenario(named: "empty-workspace-dark-wide"))

        XCTAssertTrue(online.requirements.requiresOnlinePI)
        XCTAssertTrue(!online.isDefault)
        XCTAssertTrue(visual.requirements.requiresVisualInspection)
        XCTAssertTrue(visual.resultContract == .visualOnly)
        XCTAssertTrue(!registry.allScenarios(includeLivePI: false).contains(online))
    }

    /// 成功场景只保留协议文件与声明证据，并删除完整 workspace 和诊断产物。
    func testArtifactStoreCleansSuccessfulWorkspaceAndUpdatesLatest() throws {
        let root = try makeTemporaryDirectory()
        let store = try VerificationArtifactStore(rootURL: root, runID: "known-run")
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )
        let artifacts = try store.prepareScenario(scenario)
        let reportURL = artifacts.workspaceURL.appendingPathComponent("report.json")
        try Data("{}".utf8).write(to: reportURL)
        try Data("readiness".utf8).write(to: artifacts.windowReadyURL)
        try Data("completion".utf8).write(to: artifacts.completionURL)
        try Data("validation".utf8).write(to: artifacts.validationURL)
        try Data("stdout".utf8).write(to: artifacts.stdoutURL)
        try Data("stderr".utf8).write(to: artifacts.stderrURL)
        try Data("capture".utf8).write(to: artifacts.captureURL)

        try store.finishScenario(
            artifacts,
            succeeded: true,
            retainedEvidence: ["workspace/report.json"]
        )
        try store.completeRun(reportData: Data("{}".utf8))

        XCTAssertTrue(!FileManager.default.fileExists(atPath: artifacts.workspaceURL.path))
        XCTAssertTrue(!FileManager.default.fileExists(atPath: artifacts.stdoutURL.path))
        XCTAssertTrue(!FileManager.default.fileExists(atPath: artifacts.stderrURL.path))
        XCTAssertTrue(!FileManager.default.fileExists(atPath: artifacts.captureURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.windowReadyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.completionURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.validationURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: artifacts.evidenceDirectoryURL.appendingPathComponent("workspace/report.json").path
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.runURL.appendingPathComponent("report.json").path))
        XCTAssertTrue(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: root.appendingPathComponent("latest").path
            ) == "known-run"
        )
    }

    /// 失败场景保留 workspace、日志、截图和协议文件以供复现。
    func testArtifactStoreRetainsFailedWorkspace() throws {
        let root = try makeTemporaryDirectory()
        let store = try VerificationArtifactStore(rootURL: root, runID: "failed-run")
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )
        let artifacts = try store.prepareScenario(scenario)
        try Data("diagnostic".utf8).write(to: artifacts.workspaceURL.appendingPathComponent("state.txt"))
        try Data("stdout".utf8).write(to: artifacts.stdoutURL)
        try Data("stderr".utf8).write(to: artifacts.stderrURL)
        try Data("capture".utf8).write(to: artifacts.captureURL)
        try Data("readiness".utf8).write(to: artifacts.windowReadyURL)

        try store.finishScenario(artifacts, succeeded: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.workspaceURL.appendingPathComponent("state.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.stdoutURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.stderrURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.captureURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.windowReadyURL.path))
    }

    /// AppKit 像素检查接受非黑且不透明的窗口图片。
    func testVisualInspectorAcceptsVisibleImage() throws {
        let directory = try makeTemporaryDirectory()
        let imageURL = directory.appendingPathComponent("visible.png")
        try writeSolidImage(brightness: 1, to: imageURL)

        let metrics = try AppKitVerificationVisualInspector().inspect(imageAt: imageURL)

        XCTAssertTrue(abs(metrics.nonBlackRatio - 1) <= 0.0001)
        XCTAssertTrue(abs(metrics.blackRatio) <= 0.0001)
        XCTAssertTrue(abs(metrics.transparentRatio) <= 0.0001)
    }

    /// AppKit 像素检查拒绝旧脚本定义的大面积黑块。
    func testVisualInspectorRejectsBlackImage() throws {
        let directory = try makeTemporaryDirectory()
        let imageURL = directory.appendingPathComponent("black.png")
        try writeSolidImage(brightness: 0, to: imageURL)

        do {
            _ = try AppKitVerificationVisualInspector().inspect(imageAt: imageURL)
            XCTFail("Expected visual inspection to fail.")
        } catch {
            XCTAssertTrue((error as? VerificationError)?.code == "visual_content_invalid")
        }
    }

    /// readiness 缺失时返回稳定超时错误，不通过重启应用兜底。
    func testWindowReadinessMissingUsesStableTimeout() throws {
        let root = try makeTemporaryDirectory()
        let waiter = VerificationWindowWaiter(
            locator: FakeWindowLocator(),
            waiter: ImmediateWaiter(),
            pollingIntervalSeconds: 1
        )

        XCTAssertThrowsError(
            try waiter.waitForReadiness(
                at: root.appendingPathComponent("window-ready.json"),
                artifactRoot: root,
                app: FakeRunningApp(),
                timeoutSeconds: 2
            )
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "window_ready_timeout")
        }
    }

    /// readiness 延迟出现时在同一次启动内继续，不重启应用。
    func testWindowReadinessMayAppearAfterPollingStarts() throws {
        let root = try makeTemporaryDirectory()
        let readinessURL = root.appendingPathComponent("window-ready.json")
        let waiter = ReadinessPublishingWaiter(root: root, readinessURL: readinessURL)

        let readiness = try VerificationWindowWaiter(
            locator: FakeWindowLocator(),
            waiter: waiter,
            pollingIntervalSeconds: 1
        ).waitForReadiness(
            at: readinessURL,
            artifactRoot: root,
            app: FakeRunningApp(),
            timeoutSeconds: 2
        )

        XCTAssertEqual(readiness.processIdentifier, 4242)
        XCTAssertEqual(waiter.publishCount, 1)
    }

    /// 应用在 readiness 前退出时立即报告 app_exited_early。
    func testWindowReadinessDetectsEarlyExit() throws {
        let root = try makeTemporaryDirectory()

        XCTAssertThrowsError(
            try VerificationWindowWaiter(waiter: ImmediateWaiter()).waitForReadiness(
                at: root.appendingPathComponent("window-ready.json"),
                artifactRoot: root,
                app: FakeRunningApp(isRunning: false)
            )
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "app_exited_early")
        }
    }

    /// owner name 不参与成功判定，PID 与 window number 正确即可。
    func testWindowVerificationIgnoresLocalizedOwnerName() throws {
        let readiness = VerificationWindowReadyEnvelope(
            processIdentifier: 4242,
            windowNumber: 7,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        let window = try VerificationWindowWaiter(
            locator: FakeWindowLocator(),
            waiter: ImmediateWaiter()
        ).waitForWindow(readiness: readiness, app: FakeRunningApp(), timeoutSeconds: 1)

        XCTAssertEqual(window.ownerName, "Different localized owner")
        XCTAssertEqual(window.id, 7)
    }

    /// readiness 的 PID 必须与 Runner 实际启动的 PID 一致。
    func testWindowReadinessRejectsWrongProcessIdentifier() throws {
        let root = try makeTemporaryDirectory()
        let readinessURL = root.appendingPathComponent("window-ready.json")
        try VerificationContractIO.publish(
            VerificationWindowReadyEnvelope(
                processIdentifier: 9999,
                windowNumber: 7,
                bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
            ),
            to: readinessURL,
            within: root
        )

        XCTAssertThrowsError(
            try VerificationWindowWaiter(
                locator: FakeWindowLocator(),
                waiter: ImmediateWaiter()
            ).waitForReadiness(
                at: readinessURL,
                artifactRoot: root,
                app: FakeRunningApp(),
                timeoutSeconds: 1
            )
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "window_ready_timeout")
        }
    }

    /// CoreGraphics 找不到 readiness 声明的窗口号时返回稳定可见性错误。
    func testWindowVerificationRejectsUnknownWindowNumber() {
        let readiness = VerificationWindowReadyEnvelope(
            processIdentifier: 4242,
            windowNumber: 404,
            bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
        )

        XCTAssertThrowsError(
            try VerificationWindowWaiter(
                locator: MissingWindowLocator(),
                waiter: ImmediateWaiter(),
                pollingIntervalSeconds: 1
            ).waitForWindow(readiness: readiness, app: FakeRunningApp(), timeoutSeconds: 1)
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "window_visibility_timeout")
        }
    }

    /// CoreGraphics 字典必须同时声明 layer 0 和 onscreen。
    func testWindowDictionaryRejectsWrongLayerAndHiddenWindow() {
        let bounds: [String: Any] = [
            "X": 0,
            "Y": 0,
            "Width": 800,
            "Height": 600,
        ]
        let base: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: 4242),
            kCGWindowNumber as String: NSNumber(value: 7),
            kCGWindowBounds as String: bounds,
        ]
        var hidden = base
        hidden[kCGWindowLayer as String] = NSNumber(value: 0)
        hidden[kCGWindowIsOnscreen as String] = NSNumber(value: false)
        var wrongLayer = base
        wrongLayer[kCGWindowLayer as String] = NSNumber(value: 1)
        wrongLayer[kCGWindowIsOnscreen as String] = NSNumber(value: true)

        XCTAssertNil(CoreGraphicsVerificationWindowLocator.window(from: hidden))
        XCTAssertNil(CoreGraphicsVerificationWindowLocator.window(from: wrongLayer))
    }

    /// readiness 中过小 bounds 不能绕过真实窗口尺寸约束。
    func testWindowVerificationRejectsInvalidBounds() {
        let readiness = VerificationWindowReadyEnvelope(
            processIdentifier: 4242,
            windowNumber: 7,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 100)
        )

        XCTAssertThrowsError(
            try VerificationWindowWaiter(
                locator: FakeWindowLocator(),
                waiter: ImmediateWaiter()
            ).waitForWindow(readiness: readiness, app: FakeRunningApp(), timeoutSeconds: 1)
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "window_visibility_timeout")
        }
    }

    /// completion 缺失时先超时，不能提前进入 evidence 校验。
    func testCompletionMissingUsesStableTimeout() throws {
        let artifacts = try makeArtifacts()
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )

        XCTAssertThrowsError(
            try VerificationRunner().waitForCompletion(
                scenario: scenario,
                artifacts: artifacts,
                app: FakeRunningApp(),
                waiter: ImmediateWaiter(),
                pollingIntervalSeconds: scenario.timeoutSeconds
            )
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "scenario_completion_timeout")
        }
    }

    /// completion schema 和场景 ID 任一不匹配都使用稳定协议错误。
    func testCompletionRejectsSchemaAndScenarioMismatch() throws {
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )
        for completion in [
            VerificationScenarioCompletionEnvelope(
                schemaVersion: 999,
                scenarioID: scenario.id.rawValue,
                status: .passed,
                evidence: []
            ),
            VerificationScenarioCompletionEnvelope(
                scenarioID: "linked-sources-flow",
                status: .passed,
                evidence: []
            ),
        ] {
            let artifacts = try makeArtifacts()
            try VerificationContractIO.publish(
                completion,
                to: artifacts.completionURL,
                within: artifacts.directoryURL
            )

            XCTAssertThrowsError(
                try VerificationRunner().waitForCompletion(
                    scenario: scenario,
                    artifacts: artifacts,
                    app: FakeRunningApp(),
                    waiter: ImmediateWaiter()
                )
            ) { error in
                XCTAssertEqual((error as? VerificationError)?.code, "scenario_completion_invalid")
            }
        }
    }

    /// 应用显式声明失败时 Runner 保留应用给出的稳定原因。
    func testCompletionPropagatesDeclaredFailure() throws {
        let artifacts = try makeArtifacts()
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )
        try VerificationContractIO.publish(
            VerificationScenarioCompletionEnvelope(
                scenarioID: scenario.id.rawValue,
                status: .failed,
                evidence: [],
                errorMessage: "fixture declared failure"
            ),
            to: artifacts.completionURL,
            within: artifacts.directoryURL
        )

        XCTAssertThrowsError(
            try VerificationRunner().waitForCompletion(
                scenario: scenario,
                artifacts: artifacts,
                app: FakeRunningApp(),
                waiter: ImmediateWaiter()
            )
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "scenario_declared_failed")
            XCTAssertEqual((error as? VerificationError)?.message, "fixture declared failure")
        }
    }

    /// completion 声明的 evidence 不存在时不能进入成功清理。
    func testDeclaredEvidenceMustExist() throws {
        let artifacts = try makeArtifacts()
        let completion = VerificationScenarioCompletionEnvelope(
            scenarioID: "offline-learning-flow",
            status: .passed,
            evidence: ["workspace/missing.json"]
        )

        XCTAssertThrowsError(
            try VerificationRunner().validateDeclaredEvidence(completion, artifacts: artifacts)
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "scenario_evidence_missing")
        }
    }

    /// 文件验证器检查离线学习场景真正写入了可确认的整理建议。
    func testFileValidatorChecksOfflineLearningContract() throws {
        let artifacts = try makeArtifacts()
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )
        let workspace = """
        {
          "notesByItemID":{"sample":"## 整理建议\\n把可确认依据写入笔记"},
          "studySessions":[{"messages":[{"text":"## 离线草稿\\n## 可确认"}]}]
        }
        """
        try Data(workspace.utf8).write(to: artifacts.workspaceURL.appendingPathComponent("workspace.json"))

        try FileVerificationScenarioResultValidator(
            waiter: ImmediateWaiter(),
            pollingIntervalSeconds: 10
        ).validate(scenario: scenario, artifacts: artifacts)
    }

    /// linked-sources 使用共享 Codable 报告，不再搜索 JSON 字符串。
    func testFileValidatorChecksTypedLinkedSourcesReport() throws {
        let artifacts = try makeArtifacts()
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "linked-sources-flow")
        )
        let report = LinkedSourcesVerificationReport(
            importedNotebookID: "imported:notebook",
            sourceItemIDs: ["sample-pdf", "sample-html"],
            selectedItemID: "sample-pdf",
            linkedSourcesPresented: true,
            showLibrary: false,
            noteRenderMode: "source"
        )
        try JSONEncoder().encode(report).write(
            to: artifacts.workspaceURL.appendingPathComponent("linked-sources-report.json")
        )

        XCTAssertNoThrow(
            try FileVerificationScenarioResultValidator(
                waiter: ImmediateWaiter(),
                pollingIntervalSeconds: 10
            ).validate(scenario: scenario, artifacts: artifacts)
        )
    }

    /// pane summary 的 role identity 必须准确包含 reader、agent 和 notes。
    func testFileValidatorRejectsIncompletePaneIdentityDictionary() throws {
        let artifacts = try makeArtifacts()
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "pane-reorder-width-flow")
        )
        let report = PaneReorderWidthVerificationReport(
            passed: true,
            baselineOrder: ["reader", "agent", "notes"],
            reorderedOrder: ["agent", "notes", "reader"],
            persistedOrder: ["agent", "notes", "reader"],
            expansionConsumed: true,
            nativeLifecycleStable: true,
            expandedAgentWidth: 400,
            reorderedAgentWidth: 400,
            restoredAgentWidth: 400,
            minimumReadableWidth: 320,
            widthTolerance: 48,
            notePreserved: true,
            agentDraftPreserved: true,
            conversationPreserved: true,
            studyLocationChanged: false,
            agentRevisionDelta: 0
        )
        let traceDirectory = artifacts.workspaceURL.appendingPathComponent("pane-trace")
        try FileManager.default.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(report).write(
            to: artifacts.workspaceURL.appendingPathComponent("pane-reorder-width-report.json")
        )
        let identity = PaneContinuityRoleIdentity(
            hostID: "host",
            parentID: "parent",
            contentHostID: "content",
            contentParentID: "content-parent"
        )
        let summary = PaneContinuitySummary(
            recorderID: "recorder",
            samples: 4,
            transitions: 4,
            ownershipFailures: 0,
            blankVisibleFailures: 0,
            identityFailures: 0,
            roleIdentities: ["reader": identity, "agent": identity]
        )
        try JSONEncoder().encode(summary).write(to: traceDirectory.appendingPathComponent("summary.json"))

        XCTAssertThrowsError(
            try FileVerificationScenarioResultValidator(
                waiter: ImmediateWaiter(),
                pollingIntervalSeconds: 10
            ).validate(scenario: scenario, artifacts: artifacts)
        ) { error in
            XCTAssertEqual((error as? VerificationError)?.code, "scenario_evidence_failed")
        }
    }

    /// pane summary 的 transition、ownership、blank slot 和 identity 失败均不可被 passed 报告绕过。
    func testFileValidatorRejectsPaneSummaryFailures() throws {
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "pane-reorder-width-flow")
        )
        let identity = PaneContinuityRoleIdentity(
            hostID: "host",
            parentID: "parent",
            contentHostID: "content",
            contentParentID: "content-parent"
        )
        let failures = [
            PaneContinuitySummary(
                recorderID: "recorder",
                samples: 4,
                transitions: 3,
                ownershipFailures: 0,
                blankVisibleFailures: 0,
                identityFailures: 0,
                roleIdentities: ["reader": identity, "agent": identity, "notes": identity]
            ),
            PaneContinuitySummary(
                recorderID: "recorder",
                samples: 4,
                transitions: 4,
                ownershipFailures: 1,
                blankVisibleFailures: 0,
                identityFailures: 0,
                roleIdentities: ["reader": identity, "agent": identity, "notes": identity]
            ),
            PaneContinuitySummary(
                recorderID: "recorder",
                samples: 4,
                transitions: 4,
                ownershipFailures: 0,
                blankVisibleFailures: 1,
                identityFailures: 0,
                roleIdentities: ["reader": identity, "agent": identity, "notes": identity]
            ),
            PaneContinuitySummary(
                recorderID: "recorder",
                samples: 4,
                transitions: 4,
                ownershipFailures: 0,
                blankVisibleFailures: 0,
                identityFailures: 1,
                roleIdentities: ["reader": identity, "agent": identity, "notes": identity]
            ),
        ]

        for summary in failures {
            let artifacts = try makeArtifacts(scenarioNamed: scenario.id.rawValue)
            let traceDirectory = artifacts.workspaceURL.appendingPathComponent("pane-trace")
            try FileManager.default.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
            let report = PaneReorderWidthVerificationReport(
                passed: true,
                baselineOrder: ["reader", "agent", "notes"],
                reorderedOrder: ["agent", "notes", "reader"],
                persistedOrder: ["agent", "notes", "reader"],
                expansionConsumed: true,
                nativeLifecycleStable: true,
                expandedAgentWidth: 400,
                reorderedAgentWidth: 400,
                restoredAgentWidth: 400,
                minimumReadableWidth: 320,
                widthTolerance: 48,
                notePreserved: true,
                agentDraftPreserved: true,
                conversationPreserved: true,
                studyLocationChanged: false,
                agentRevisionDelta: 0
            )
            try JSONEncoder().encode(report).write(
                to: artifacts.workspaceURL.appendingPathComponent("pane-reorder-width-report.json")
            )
            try JSONEncoder().encode(summary).write(
                to: traceDirectory.appendingPathComponent("summary.json")
            )

            XCTAssertThrowsError(
                try FileVerificationScenarioResultValidator().validate(
                    scenario: scenario,
                    artifacts: artifacts
                )
            ) { error in
                XCTAssertEqual((error as? VerificationError)?.code, "scenario_evidence_failed")
            }
        }
    }

    /// pane layout trace 的 transition 是 JSON 数字，数值分组应接受完整 fixture。
    func testPaneLayoutValidatorAcceptsNumericTransitions() throws {
        let artifacts = try makeArtifacts(scenarioNamed: "pane-layout-stability-flow")
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "pane-layout-stability-flow")
        )
        let traceDirectory = artifacts.workspaceURL.appendingPathComponent("pane-trace")
        try FileManager.default.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
        let identity = PaneContinuityRoleIdentity(
            hostID: "host",
            parentID: "parent",
            contentHostID: "content",
            contentParentID: "content-parent"
        )
        let summary = PaneContinuitySummary(
            recorderID: "recorder",
            samples: 120,
            transitions: 8,
            ownershipFailures: 0,
            blankVisibleFailures: 0,
            identityFailures: 0,
            roleIdentities: ["reader": identity, "agent": identity, "notes": identity]
        )
        let report = PaneLayoutStabilityVerificationReport(
            passed: true,
            transitions: 8,
            readerVisible: true,
            agentVisible: false,
            notesVisible: true,
            notePreserved: true,
            agentDraftPreserved: true,
            conversationPreserved: true,
            paneOrderPreserved: true,
            agentRevisionDelta: 0,
            studyLocationChanged: false,
            htmlLocationCalls: 0,
            webReaderMakeCount: 0,
            webReaderDismantleCount: 0,
            noteEditorMakeCount: 0,
            noteEditorDismantleCount: 0
        )
        try JSONEncoder().encode(summary).write(to: traceDirectory.appendingPathComponent("summary.json"))
        try JSONEncoder().encode(report).write(
            to: artifacts.workspaceURL.appendingPathComponent("pane-layout-stability-report.json")
        )
        let roles = ["reader", "agent", "notes"].map { role in
            [
                "role": role,
                "hostID": "host",
                "parentID": "parent",
                "contentHostID": "content",
                "contentParentID": "content-parent",
            ]
        }
        for transition in 1...8 {
            for frame in 1...15 {
                let payload: [String: Any] = [
                    "recorderID": "recorder",
                    "transition": transition,
                    "stableOwnership": true,
                    "noBlankVisibleSlots": true,
                    "roles": roles,
                ]
                let data = try JSONSerialization.data(withJSONObject: payload)
                try data.write(
                    to: traceDirectory.appendingPathComponent(
                        "container-recorder-transition-\(transition)-frame-\(frame).json"
                    )
                )
            }
        }

        XCTAssertNoThrow(
            try FileVerificationScenarioResultValidator().validate(
                scenario: scenario,
                artifacts: artifacts
            )
        )
    }

    /// 默认运行在单场景失败后继续，并为失败保留 workspace。
    func testRunnerContinuesAfterScenarioFailure() async throws {
        let fixture = try makeRunnerFixture(failingIDs: [.offlineLearningFlow])
        let registry = VerificationScenarioRegistry()
        let scenarios = [
            try XCTUnwrap(registry.scenario(named: "offline-learning-flow")),
            try XCTUnwrap(registry.scenario(named: "linked-sources-flow"))
        ]

        let report = try await fixture.runner.run(
            configuration: VerificationRunConfiguration(
                appExecutableURL: fixture.executableURL,
                workingDirectoryURL: fixture.root,
                scenarios: scenarios
            ),
            artifactStore: fixture.store
        )

        XCTAssertTrue(report.results.map(\.status) == [.failed, .passed])
        XCTAssertTrue(fixture.appManager.launchCount == 2)
        XCTAssertTrue(fixture.appManager.stopCount == 2)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.store.runURL
                    .appendingPathComponent("offline-learning-flow/workspace/failure.txt")
                    .path
            )
        )
        XCTAssertTrue(
            !FileManager.default.fileExists(
                atPath: fixture.store.runURL
                    .appendingPathComponent("linked-sources-flow/workspace")
                    .path
            )
        )
    }

    /// fail-fast 由上层配置后在首个场景失败时停止。
    func testRunnerHonorsFailFast() async throws {
        let fixture = try makeRunnerFixture(failingIDs: [.offlineLearningFlow])
        let registry = VerificationScenarioRegistry()
        let scenarios = [
            try XCTUnwrap(registry.scenario(named: "offline-learning-flow")),
            try XCTUnwrap(registry.scenario(named: "linked-sources-flow"))
        ]

        let report = try await fixture.runner.run(
            configuration: VerificationRunConfiguration(
                appExecutableURL: fixture.executableURL,
                workingDirectoryURL: fixture.root,
                scenarios: scenarios,
                failFast: true
            ),
            artifactStore: fixture.store
        )

        XCTAssertTrue(report.results.count == 1)
        XCTAssertTrue(fixture.appManager.launchCount == 1)
    }

    /// 应用启动失败属于全局前置错误，不会伪装成可继续的场景失败。
    func testRunnerStopsOnGlobalLaunchFailure() async throws {
        let root = try makeTemporaryDirectory()
        let executable = try makeExecutable(in: root)
        let manager = FakeAppManager(launchError: VerificationError(code: "app_launch_failed", message: "boom"))
        let runner = VerificationRunner(
            appManager: manager,
            windowWaiter: VerificationWindowWaiter(locator: FakeWindowLocator()),
            resultValidator: FakeResultValidator(),
            captureResolver: VerificationCaptureResolver(capturer: FakeWindowCapturer(), waiter: ImmediateWaiter()),
            visualInspector: FakeVisualInspector()
        )
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )

        do {
            _ = try await runner.run(
                configuration: VerificationRunConfiguration(
                    appExecutableURL: executable,
                    workingDirectoryURL: root,
                    scenarios: [scenario]
                ),
                artifactStore: try VerificationArtifactStore(rootURL: root.appendingPathComponent("artifacts"))
            )
            XCTFail("Expected app launch to fail.")
        } catch {
            XCTAssertTrue((error as? VerificationError)?.code == "app_launch_failed")
        }
        XCTAssertTrue(manager.launchCount == 1)
    }

    /// 未显式允许时，在线场景在启动任何应用前失败。
    func testRunnerRejectsOnlineScenarioWithoutPermission() async throws {
        let fixture = try makeRunnerFixture()
        let online = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "pi-learning-flow")
        )

        do {
            _ = try await fixture.runner.run(
                configuration: VerificationRunConfiguration(
                    appExecutableURL: fixture.executableURL,
                    workingDirectoryURL: fixture.root,
                    scenarios: [online]
                ),
                artifactStore: fixture.store
            )
            XCTFail("Expected online scenario permission validation to fail.")
        } catch {
            XCTAssertTrue((error as? VerificationError)?.code == "live_pi_not_allowed")
        }
        XCTAssertTrue(fixture.appManager.launchCount == 0)
    }

    /// 创建使用 fake 副作用边界的场景运行器 fixture。
    private func makeRunnerFixture(failingIDs: Set<VerificationScenarioID> = []) throws -> RunnerFixture {
        let root = try makeTemporaryDirectory()
        let executable = try makeExecutable(in: root)
        let manager = FakeAppManager()
        let runner = VerificationRunner(
            appManager: manager,
            windowWaiter: VerificationWindowWaiter(locator: FakeWindowLocator(), waiter: ImmediateWaiter()),
            resultValidator: FakeResultValidator(failingIDs: failingIDs),
            captureResolver: VerificationCaptureResolver(capturer: FakeWindowCapturer(), waiter: ImmediateWaiter()),
            visualInspector: FakeVisualInspector()
        )
        return RunnerFixture(
            root: root,
            executableURL: executable,
            store: try VerificationArtifactStore(rootURL: root.appendingPathComponent("artifacts")),
            appManager: manager,
            runner: runner
        )
    }

    /// 创建可供验收运行器启动检查使用的空可执行文件。
    private func makeExecutable(in directory: URL) throws -> URL {
        let executable = directory.appendingPathComponent("WeiBei")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: executable.path
        )
        return executable
    }

    /// 创建离线学习场景的隔离 artifacts。
    private func makeArtifacts(
        scenarioNamed name: String = "offline-learning-flow"
    ) throws -> VerificationScenarioArtifacts {
        let root = try makeTemporaryDirectory()
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: name)
        )
        return try VerificationArtifactStore(rootURL: root).prepareScenario(scenario)
    }

    /// 写入使用显式 Device RGB 色彩空间的纯色 PNG fixture。
    private func writeSolidImage(brightness: CGFloat, to url: URL) throws {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: 20,
                height: 20,
                bitsPerComponent: 8,
                bytesPerRow: 80,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(red: brightness, green: brightness, blue: brightness, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let image = try XCTUnwrap(context.makeImage())
        let bitmap = NSBitmapImageRep(cgImage: image)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    /// 创建并登记一个将在套件释放时清理的临时目录。
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "weibei-verification-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

private struct RunnerFixture {
    let root: URL
    let executableURL: URL
    let store: VerificationArtifactStore
    let appManager: FakeAppManager
    let runner: VerificationRunner
}

private struct ImmediateWaiter: VerificationWaiting {
    /// Avoids real sleeps in deterministic tests.
    func wait(seconds: TimeInterval) {}
}

private final class ReadinessPublishingWaiter: VerificationWaiting, @unchecked Sendable {
    private let root: URL
    private let readinessURL: URL
    private(set) var publishCount = 0

    /// 创建会在首次轮询时发布 readiness 的确定性 waiter。
    init(root: URL, readinessURL: URL) {
        self.root = root
        self.readinessURL = readinessURL
    }

    /// 首次等待时模拟应用稍后原子发布 readiness。
    func wait(seconds: TimeInterval) {
        guard publishCount == 0 else { return }
        publishCount += 1
        try! VerificationContractIO.publish(
            VerificationWindowReadyEnvelope(
                processIdentifier: 4242,
                windowNumber: 7,
                bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
            ),
            to: readinessURL,
            within: root
        )
    }
}

private final class FakeRunningApp: VerificationRunningApp, @unchecked Sendable {
    let processIdentifier: pid_t = 4242
    let isRunning: Bool

    /// 创建可模拟提前退出的运行句柄。
    init(isRunning: Bool = true) {
        self.isRunning = isRunning
    }
}

private final class FakeAppManager: VerificationAppManaging, @unchecked Sendable {
    private(set) var launchCount = 0
    private(set) var stopCount = 0
    private let launchError: VerificationError?

    /// 创建可选择注入全局启动失败的应用管理器。
    init(launchError: VerificationError? = nil) {
        self.launchError = launchError
    }

    /// Records launches or throws the configured global error.
    func launch(configuration: VerificationAppLaunchConfiguration) throws -> any VerificationRunningApp {
        launchCount += 1
        if let launchError {
            throw launchError
        }
        let environment = configuration.environment
        if let artifactPath = environment["WEIBEI_VERIFY_ARTIFACT_DIR"],
           let readinessPath = environment["WEIBEI_VERIFY_WINDOW_READY_PATH"] {
            try VerificationContractIO.publish(
                VerificationWindowReadyEnvelope(
                    processIdentifier: 4242,
                    windowNumber: 7,
                    bounds: CGRect(x: 0, y: 0, width: 800, height: 600)
                ),
                to: URL(fileURLWithPath: readinessPath),
                within: URL(fileURLWithPath: artifactPath, isDirectory: true)
            )
        }
        if let artifactPath = environment["WEIBEI_VERIFY_ARTIFACT_DIR"],
           let completionPath = environment["WEIBEI_VERIFY_COMPLETION_PATH"],
           let scenarioID = environment["WEIBEI_VERIFY_SCENARIO"],
           VerificationScenarioRegistry().scenario(named: scenarioID)?.usesCompletionProtocol == true {
            try VerificationContractIO.publish(
                VerificationScenarioCompletionEnvelope(
                    scenarioID: scenarioID,
                    status: .passed,
                    evidence: []
                ),
                to: URL(fileURLWithPath: completionPath),
                within: URL(fileURLWithPath: artifactPath, isDirectory: true)
            )
        }
        return FakeRunningApp()
    }

    /// Records cleanup of each owned process.
    func stop(_ app: any VerificationRunningApp) {
        stopCount += 1
    }
}

private struct FakeWindowLocator: VerificationWindowLocating {
    /// Returns a window belonging to the requested PID.
    func findWindow(
        windowID: CGWindowID,
        processIdentifier: pid_t,
        minimumSize: CGSize
    ) -> VerificationWindow? {
        VerificationWindow(
            id: windowID,
            processIdentifier: processIdentifier,
            ownerName: "Different localized owner",
            bounds: CGRect(origin: .zero, size: minimumSize)
        )
    }
}

private struct MissingWindowLocator: VerificationWindowLocating {
    /// 模拟 readiness 声明的窗口号不在 CoreGraphics 列表中。
    func findWindow(
        windowID: CGWindowID,
        processIdentifier: pid_t,
        minimumSize: CGSize
    ) -> VerificationWindow? {
        nil
    }
}

private struct FakeResultValidator: VerificationScenarioResultValidating {
    let failingIDs: Set<VerificationScenarioID>

    /// 创建仅对指定场景注入失败的结果验证器。
    init(failingIDs: Set<VerificationScenarioID> = []) {
        self.failingIDs = failingIDs
    }

    /// Writes a diagnostic marker before reproducing configured scenario failures.
    func validate(
        scenario: VerificationScenario,
        artifacts: VerificationScenarioArtifacts
    ) throws {
        if failingIDs.contains(scenario.id) {
            try Data("failure".utf8).write(to: artifacts.workspaceURL.appendingPathComponent("failure.txt"))
            throw VerificationError(code: "fixture_failure", message: scenario.id.rawValue)
        }
    }
}

private struct FakeWindowCapturer: VerificationWindowCapturing {
    /// Writes a non-empty placeholder capture.
    func capture(window: VerificationWindow, to outputURL: URL) async throws {
        try Data("capture".utf8).write(to: outputURL)
    }
}

private struct FakeVisualInspector: VerificationVisualInspecting {
    /// Returns passing fixture metrics.
    func inspect(imageAt imageURL: URL) throws -> VisualInspectionMetrics {
        VisualInspectionMetrics(
            sampledPixelCount: 1,
            nonBlackRatio: 1,
            blackRatio: 0,
            transparentRatio: 0
        )
    }
}
