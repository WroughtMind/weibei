import AppKit
import Foundation
import XCTest
@testable import WeiBeiDevCore

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

    /// 成功场景删除隔离 workspace，同时报告和 latest 链接持久保留。
    func testArtifactStoreCleansSuccessfulWorkspaceAndUpdatesLatest() throws {
        let root = try makeTemporaryDirectory()
        let store = try VerificationArtifactStore(rootURL: root, runID: "known-run")
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )
        let artifacts = try store.prepareScenario(scenario)
        try Data("temporary".utf8).write(to: artifacts.workspaceURL.appendingPathComponent("state.txt"))

        try store.finishScenario(artifacts, succeeded: true)
        try store.completeRun(reportData: Data("{}".utf8))

        XCTAssertTrue(!FileManager.default.fileExists(atPath: artifacts.workspaceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.runURL.appendingPathComponent("report.json").path))
        XCTAssertTrue(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: root.appendingPathComponent("latest").path
            ) == "known-run"
        )
    }

    /// 失败场景保留完整 workspace 以供复现。
    func testArtifactStoreRetainsFailedWorkspace() throws {
        let root = try makeTemporaryDirectory()
        let store = try VerificationArtifactStore(rootURL: root, runID: "failed-run")
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
        )
        let artifacts = try store.prepareScenario(scenario)
        try Data("diagnostic".utf8).write(to: artifacts.workspaceURL.appendingPathComponent("state.txt"))

        try store.finishScenario(artifacts, succeeded: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: artifacts.workspaceURL.appendingPathComponent("state.txt").path))
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
    private func makeArtifacts() throws -> VerificationScenarioArtifacts {
        let root = try makeTemporaryDirectory()
        let scenario = try XCTUnwrap(
            VerificationScenarioRegistry().scenario(named: "offline-learning-flow")
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

private final class FakeRunningApp: VerificationRunningApp, @unchecked Sendable {
    let processIdentifier: pid_t = 4242
    let isRunning = true
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
        ownerName: String,
        processIdentifier: pid_t,
        minimumSize: CGSize
    ) -> VerificationWindow? {
        VerificationWindow(
            id: 7,
            processIdentifier: processIdentifier,
            ownerName: ownerName,
            bounds: CGRect(origin: .zero, size: minimumSize)
        )
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
