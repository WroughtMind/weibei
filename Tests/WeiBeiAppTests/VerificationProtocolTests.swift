import Foundation
import XCTest
@testable import WeiBei
@testable import WeiBeiCore

final class VerificationProtocolTests: XCTestCase {
    /// readiness 使用原子 Codable 文件发布，并可从相同 artifact 根读取。
    func testWindowReadinessPublishesAtomically() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("window-ready.json")
        let readiness = VerificationWindowReadyEnvelope(
            processIdentifier: 42,
            windowNumber: 7,
            bounds: CGRect(x: 10, y: 20, width: 800, height: 600),
            timestamp: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try VerificationContractIO.publish(readiness, to: url, within: root)
        let decoded = try VerificationContractIO.decode(
            VerificationWindowReadyEnvelope.self,
            from: url,
            within: root
        )

        XCTAssertEqual(decoded, readiness)
        XCTAssertNoThrow(try decoded.validate())
    }

    /// 协议文件不能逃逸 Runner 提供的 artifact 根。
    func testProtocolPublishingRejectsPathTraversal() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let escaped = root.deletingLastPathComponent().appendingPathComponent("escaped.json")

        XCTAssertThrowsError(
            try VerificationContractIO.publish(
                VerificationScenarioCompletionEnvelope(
                    scenarioID: "offline-learning-flow",
                    status: .passed,
                    evidence: []
                ),
                to: escaped,
                within: root
            )
        )
    }

    /// completion 拒绝绝对路径和父目录 evidence。
    func testCompletionRejectsUnsafeEvidencePaths() {
        for path in ["/tmp/evidence.json", "../evidence.json", "workspace/../../evidence.json"] {
            let completion = VerificationScenarioCompletionEnvelope(
                scenarioID: "offline-learning-flow",
                status: .passed,
                evidence: [path]
            )
            XCTAssertThrowsError(try completion.validate(expectedScenarioID: "offline-learning-flow"))
        }
    }

    /// evidence 必须先稳定落盘，随后才能原子发布 completion 屏障。
    func testCompletionPublishesAfterDeclaredEvidence() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let evidenceURL = root.appendingPathComponent("workspace/report.json")
        try FileManager.default.createDirectory(
            at: evidenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: evidenceURL, options: .atomic)
        let completionURL = root.appendingPathComponent("scenario-complete.json")

        try VerificationContractIO.publish(
            VerificationScenarioCompletionEnvelope(
                scenarioID: "linked-sources-flow",
                status: .passed,
                evidence: ["workspace/report.json"]
            ),
            to: completionURL,
            within: root
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: evidenceURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completionURL.path))
    }

    /// 协议 IO 写入失败必须向调用方传播，不能被 try? 吞掉。
    func testProtocolWriteFailurePropagates() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(
            try VerificationContractIO.publish(
                VerificationScenarioCompletionEnvelope(
                    scenarioID: "offline-learning-flow",
                    status: .passed,
                    evidence: []
                ),
                to: root,
                within: root
            )
        )
    }

    /// pane recorder 的 finish 只发布一次稳定 summary。
    @MainActor
    func testPaneRecorderFinishPublishesSummaryOnce() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = PaneContinuityRecorder(directory: root, writesIndividualSamples: true)

        try await recorder.finish()
        let summaryURL = root.appendingPathComponent("summary.json")
        let firstData = try Data(contentsOf: summaryURL)
        try await recorder.finish()

        XCTAssertEqual(try Data(contentsOf: summaryURL), firstData)
        let summary = try JSONDecoder().decode(PaneContinuitySummary.self, from: firstData)
        XCTAssertEqual(summary.samples, 0)
        XCTAssertEqual(summary.transitions, 0)
    }

    /// pane recorder 初始化目录失败后由 finish 显式传播错误。
    @MainActor
    func testPaneRecorderPropagatesSetupFailure() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let regularFile = root.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: regularFile)
        let recorder = PaneContinuityRecorder(
            directory: regularFile.appendingPathComponent("trace"),
            writesIndividualSamples: true
        )

        do {
            try await recorder.finish()
            XCTFail("Expected recorder setup failure.")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: regularFile.appendingPathComponent("trace/summary.json").path))
        }
    }

    /// linked-sources 和三个 pane 报告保持确定的 Codable 结构。
    func testTypedReportsRoundTrip() throws {
        let linked = LinkedSourcesVerificationReport(
            importedNotebookID: "imported:note",
            sourceItemIDs: ["sample-html", "sample-pdf"],
            selectedItemID: "sample-pdf",
            linkedSourcesPresented: true,
            showLibrary: false,
            noteRenderMode: "source"
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                LinkedSourcesVerificationReport.self,
                from: JSONEncoder().encode(linked)
            ),
            linked
        )

        let toggleCase = PaneToggleContinuityCaseReport(
            name: "sample-html-agent-off",
            passed: true,
            agentRevisionDelta: 0,
            studyLocationChanged: false,
            htmlLocationCalls: 0,
            htmlLocationCommits: 0,
            htmlLocationReasons: [:],
            webReaderMakeCount: 0,
            webReaderDismantleCount: 0,
            pdfReaderMakeCount: 0,
            pdfReaderDismantleCount: 0,
            noteEditorMakeCount: 0,
            noteEditorDismantleCount: 0,
            notePreserved: true,
            conversationPreserved: true,
            paneOrderPreserved: true
        )
        let toggle = PaneToggleContinuityVerificationReport(
            passed: true,
            caseCount: 1,
            notesCyclesPerCase: 20,
            readerCyclesPerCase: 20,
            cases: [toggleCase]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                PaneToggleContinuityVerificationReport.self,
                from: JSONEncoder().encode(toggle)
            ),
            toggle
        )

        let layout = PaneLayoutStabilityVerificationReport(
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
        XCTAssertEqual(
            try JSONDecoder().decode(
                PaneLayoutStabilityVerificationReport.self,
                from: JSONEncoder().encode(layout)
            ),
            layout
        )

        let reorder = PaneReorderWidthVerificationReport(
            passed: false,
            baselineOrder: ["reader", "agent", "notes"],
            reorderedOrder: ["agent", "notes", "reader"],
            persistedOrder: ["agent", "notes", "reader"],
            expansionConsumed: true,
            nativeLifecycleStable: false,
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
        XCTAssertEqual(
            try JSONDecoder().decode(
                PaneReorderWidthVerificationReport.self,
                from: JSONEncoder().encode(reorder)
            ),
            reorder
        )
    }

    /// 创建协议测试专用目录。
    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "weibei-verification-protocol-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
