import Combine
import Darwin
import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class WorkspaceSafetyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    func testImportedFileIdentitySafety() throws {
        try ImportedIdentitySelfCheck.run()
    }

    @MainActor
    func testCourseProjectDataSafety() throws {
        try CourseProjectRootSelfCheck.run()
    }

    @MainActor
    func testBackgroundWorkspacePersistence() throws {
        try CourseProjectRootSelfCheck.runBackgroundWorkspacePersistenceOnly()
    }

    @MainActor
    func testSharedConversionRejectsConcurrentPortableState() throws {
        try CourseProjectRootSelfCheck.runSharedConversionConflictOnly()
    }

    @MainActor
    func testAgentStreamingStateDoesNotInvalidateWorkspaceStore() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiStreamingState-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        var workspaceChanges = 0
        var streamingChanges = 0
        let workspaceObservation = store.objectWillChange.sink { workspaceChanges += 1 }
        let streamingObservation = store.agentStreaming.objectWillChange.sink { streamingChanges += 1 }

        store.agentStreaming.text = "第一段"
        store.agentStreaming.activityText = "正在组织回答"

        XCTAssertEqual(workspaceChanges, 0)
        XCTAssertEqual(streamingChanges, 2)
        withExtendedLifetime((workspaceObservation, streamingObservation)) {}
    }

    @MainActor
    func testSemanticSessionTitleOnlyReplacesFirstTurnFallback() {
        let firstQuestion = AgentMessage(
            role: .user,
            text: "请帮我解释利率为什么变化"
        )
        let secondQuestion = AgentMessage(role: .user, text: "再举个例子")

        XCTAssertEqual(
            WorkspaceStore.semanticSessionTitle(
                from: "利率变化机制",
                replacing: firstQuestion.text,
                messages: [firstQuestion]
            ),
            "利率变化机制"
        )
        XCTAssertNil(
            WorkspaceStore.semanticSessionTitle(
                from: "利率变化机制",
                replacing: "用户手动命名",
                messages: [firstQuestion]
            )
        )
        XCTAssertNil(
            WorkspaceStore.semanticSessionTitle(
                from: "利率变化机制",
                replacing: firstQuestion.text,
                messages: [firstQuestion, secondQuestion]
            )
        )
        XCTAssertNil(
            WorkspaceStore.semanticSessionTitle(
                from: "WeiBei",
                replacing: firstQuestion.text,
                messages: [firstQuestion]
            )
        )
    }

    @MainActor
    func testPaneAndInteractionStateDoNotInvalidateWorkspaceStore() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiPaneState-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        var workspaceChanges = 0
        var paneChanges = 0
        var interactionChanges = 0
        let workspaceObservation = store.objectWillChange.sink { workspaceChanges += 1 }
        let paneObservation = store.paneState.objectWillChange.sink { paneChanges += 1 }
        let interactionObservation = store.interaction.objectWillChange.sink { interactionChanges += 1 }

        store.showReader = false
        store.showAgent = false
        store.showNotes = true
        store.showRightPane = true
        store.focusedPane = .agent
        store.focusRequest += 1
        store.showReaderSearch = true

        store.selectionContext = SelectionContext(
            text: "选区",
            source: .document,
            ownerTitle: "资料"
        )
        store.pinnedFloatingAgent = true
        store.keepFloatingSelectionForAnswer = true
        store.agentSurface = .selectionFloat
        store.selectionAnchor = CGPoint(x: 12, y: 24)

        XCTAssertEqual(workspaceChanges, 0, "pane/interaction chrome must not forward to WorkspaceStore")
        XCTAssertGreaterThan(paneChanges, 0)
        XCTAssertGreaterThan(interactionChanges, 0)
        // showRightPane batches notes+agent into one publish (not two).
        let beforeRight = paneChanges
        store.showRightPane = false
        XCTAssertEqual(paneChanges, beforeRight + 1)
        withExtendedLifetime((workspaceObservation, paneObservation, interactionObservation)) {}
    }
}
