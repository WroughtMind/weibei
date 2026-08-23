import AppKit
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
    func testManualSessionTitlePersistsAndSurvivesFirstQuestionNaming() throws {
        let firstQuestion = AgentMessage(
            role: .user,
            text: "请帮我解释利率为什么变化",
            source: nil
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiSessionTitle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        let session = store.createStudySession(courseID: nil)!
        XCTAssertTrue(store.renameStudySession(session.id, title: "我的利率课"))
        XCTAssertTrue(store.flushPendingWorkspaceSave())

        let reopened = WorkspaceStore(workspaceDirectory: root)
        XCTAssertTrue(reopened.activateStudySession(
            session.id,
            expectedCourseID: nil,
            expectedScopeNeedsReview: false
        ))
        reopened.messages = [firstQuestion]
        reopened.syncActiveStudySession(titleSeed: firstQuestion.text)
        let reopenedSession = try XCTUnwrap(reopened.activeStudySession)
        XCTAssertEqual(reopenedSession.title, "我的利率课")
        XCTAssertTrue(reopenedSession.titleSetByUser)
    }

    func testShortcutCatalogOwnsAppChordsWithoutClaimingStandardEditorChords() {
        let retiredOverrides: [AppShortcutID: AppShortcutChord] = [
            .courseIndex: AppShortcutChord(key: "b", modifiers: .command),
            .searchInMaterial: AppShortcutChord(key: "f", modifiers: .command),
        ]
        XCTAssertNil(AppShortcutCatalog.action(
            matching: AppShortcutChord(key: "b", modifiers: .command),
            overrides: retiredOverrides
        ))
        XCTAssertNil(AppShortcutCatalog.action(
            matching: AppShortcutChord(key: "f", modifiers: .command),
            overrides: retiredOverrides
        ))
        XCTAssertEqual(AppShortcutCatalog.action(
            matching: AppShortcutChord(key: "b", modifiers: [.command, .option]),
            overrides: retiredOverrides
        ), .courseIndex)
        XCTAssertEqual(AppShortcutCatalog.action(
            matching: AppShortcutChord(key: "f", modifiers: [.command, .option]),
            overrides: retiredOverrides
        ), .searchInMaterial)

        let centralizedDefaults: [AppShortcutID] = [
            .previousMaterial, .nextMaterial, .toggleRightPane, .threePaneWorkspace,
            .swapThreePaneSecondaryPanes, .applyAgentAnswerToNote, .replaceNoteSelection,
            .applyAgentPatchToEditor, .copyCurrentReference, .submitAgentDraft,
        ]
        for id in centralizedDefaults {
            XCTAssertEqual(
                AppShortcutCatalog.action(matching: id.defaultChord, overrides: [:]),
                id
            )
        }
        XCTAssertEqual(
            AppShortcutCatalog.conflict(
                for: AppShortcutID.threePaneWorkspace.defaultChord,
                excluding: .courseIndex,
                overrides: [:]
            ),
            .threePaneWorkspace
        )
    }

    func testConflictingStoredShortcutIsPreservedAndReported() throws {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: AppShortcutCatalog.defaultsKey)
        defer {
            if let original {
                defaults.set(original, forKey: AppShortcutCatalog.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppShortcutCatalog.defaultsKey)
            }
        }
        let conflictingStoredOverrides = [
            AppShortcutID.courseIndex.rawValue: AppShortcutID.threePaneWorkspace.defaultChord,
        ]
        defaults.set(
            try JSONEncoder().encode(conflictingStoredOverrides),
            forKey: AppShortcutCatalog.defaultsKey
        )
        let loaded = AppShortcutCatalog.loadOverrides()
        XCTAssertEqual(loaded[.courseIndex], AppShortcutID.threePaneWorkspace.defaultChord)
        XCTAssertEqual(
            AppShortcutCatalog.conflict(
                for: AppShortcutID.threePaneWorkspace.defaultChord,
                excluding: .courseIndex,
                overrides: loaded
            ),
            .threePaneWorkspace
        )
        XCTAssertNil(AppShortcutCatalog.action(
            matching: AppShortcutID.threePaneWorkspace.defaultChord,
            overrides: loaded
        ))
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
