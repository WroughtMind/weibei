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
    func testFirstWorkspaceSaveFailureIsVisible() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiWorkspaceFailure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(
            workspaceDirectory: root,
            workspaceSnapshotWriter: { _, _ in
                throw NSError(
                    domain: "底层写盘原因",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "/private/secret 写失败"]
                )
            },
            startsAtBlankEntries: true
        )
        store.noteText = "尚未写入的正文"

        XCTAssertFalse(store.flushPendingWorkspaceSave())
        XCTAssertEqual(store.noteText, "尚未写入的正文")
        let message = try XCTUnwrap(store.workspaceSaveError)
        XCTAssertTrue(message.contains("未写内容已保存在魏碑中"))
        XCTAssertTrue(message.contains("重试"))
        XCTAssertFalse(message.contains("/private/secret"))
    }

    @MainActor
    func testSharedConversionRejectsConcurrentPortableState() throws {
        try CourseProjectRootSelfCheck.runSharedConversionConflictOnly()
    }

    @MainActor
    func testSharedRemovalCleanupFailureIsTruthful() throws {
        try CourseProjectRootSelfCheck.runSharedRemovalCleanupFailureOnly()
    }

    @MainActor
    func testAgentSelectionPreservesFullText() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiFullSelection-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        store.interfaceLanguage = .chinese
        let selection = String(
            repeating: "作者先交代事实，再比较两种解释，并用反例说明结论成立的边界。",
            count: 120
        )

        store.updateSelection(selection, source: .document, ownerTitle: "课堂原文")

        XCTAssertEqual(store.selectionContext?.text, selection)
        XCTAssertEqual(
            store.agentSelectionText,
            """
            片段 1（来源：课堂原文）：
            \(selection)
            """
        )
    }

    @MainActor
    func testAgentSelectionKeepsIndependentFragments() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiSelectionFragments-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        store.interfaceLanguage = .chinese
        let selections = (1...12).map { index in
            SelectionContext(
                text: "课堂摘录 \(index)",
                source: .document,
                ownerTitle: "资料 \(index)"
            )
        }

        selections.forEach { store.addSelectionAttachment($0) }

        let expected = selections.enumerated().map { index, selection in
            """
            片段 \(index + 1)（来源：\(selection.ownerTitle)）：
            \(selection.text)
            """
        }.joined(separator: "\n\n")
        XCTAssertEqual(store.agentSelectionText, expected)
    }

    @MainActor
    func testSelectionRemarkHistoryKeepsOlderRecordsAndPersistsThem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiSelectionRemarks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        let existing = (0..<200).map { index in
            SelectionRemarkRecord(
                selectionText: "旧札记原文 \(index)",
                remarkText: "旧札记 \(index)",
                source: .document,
                ownerTitle: "课堂资料"
            )
        }
        store.selectionRemarkRecords = existing
        store.selectionContext = SelectionContext(
            text: "新札记原文",
            source: .document,
            ownerTitle: "课堂资料"
        )

        store.saveSelectionRemark("新札记")

        XCTAssertEqual(store.selectionRemarkRecords.count, 201)
        XCTAssertEqual(store.selectionRemarkRecords.last?.id, existing.last?.id)
        XCTAssertTrue(selectionRemarkMarksJSON(store.selectionRemarkRecords).contains(existing.last!.id.uuidString))
        XCTAssertTrue(store.flushPendingWorkspaceSave())
        let reopened = WorkspaceStore(workspaceDirectory: root, startsCourseFileMaintenance: false)
        XCTAssertEqual(reopened.selectionRemarkRecords.map(\.id), store.selectionRemarkRecords.map(\.id))
    }

    @MainActor
    func testSelectionAskHistoryKeepsOlderThreads() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiSelectionAsks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        let existing = (0..<80).map { index in
            SelectionAskThread(
                selectionText: "旧问题选区 \(index)",
                source: .document,
                ownerTitle: "课堂资料"
            )
        }
        store.selectionAskThreads = existing

        _ = store.beginOrReuseSelectionAskThread(for: SelectionContext(
            text: "新问题选区",
            source: .document,
            ownerTitle: "课堂资料"
        ))

        XCTAssertEqual(store.selectionAskThreads.count, 81)
        XCTAssertEqual(store.selectionAskThreads.last?.id, existing.last?.id)
    }

    @MainActor
    func testLearningContextIncludesEverySavedMemory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiLearningContext-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let courseID = UUID()
        let memories = (0...200).map { index in
            LearningMemoryEntry(
                kind: .summary,
                text: "学习记忆 \(index)",
                evidence: "[用户：历史] 学习记忆 \(index)",
                origin: .userStatement
            )
        }
        let snapshot = PersistedWorkspace(
            courses: [Course(id: courseID, title: "课程")],
            learningMemoryStates: [
                ScopedLearningMemoryState(scope: .course(courseID), revision: 1, entries: memories),
            ],
            learningMemoryScopeMigrationVersion: 1
        )
        try JSONEncoder().encode(snapshot).write(
            to: root.appendingPathComponent("workspace.json"),
            options: .atomic
        )
        let store = WorkspaceStore(workspaceDirectory: root, startsCourseFileMaintenance: false)
        let context = store.makeLearningContext(target: WorkspaceStore.AgentConversationTarget(
            sessionID: UUID(),
            workingDirectory: root,
            courseID: courseID
        ))

        XCTAssertEqual(context.memories.count, memories.count)
        XCTAssertEqual(Set(context.memories.map(\.id)), Set(memories.map(\.id)))
    }

    @MainActor
    func testCourseProfileKeepsFullTextBeyondPreviousEntryBoundary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiCourseProfile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let courseID = UUID()
        let existing = (0..<200).map { index in
            CourseKnowledgeProfileEntry(
                kind: .concept,
                text: "用户自述：已有认识 \(index)",
                sources: []
            )
        }
        let snapshot = PersistedWorkspace(
            courses: [Course(id: courseID, title: "课程")],
            courseKnowledgeProfiles: [
                CourseKnowledgeProfile(courseID: courseID, revision: 4, entries: existing),
            ]
        )
        try JSONEncoder().encode(snapshot).write(
            to: root.appendingPathComponent("workspace.json"),
            options: .atomic
        )
        let store = WorkspaceStore(workspaceDirectory: root, startsCourseFileMaintenance: false)
        let fullText = "用户自述：" + String(repeating: "这段课程认识需要完整保存。", count: 100)
        let receipt = store.persistNativeCourseProfileUpdate(
            StudyAgentCourseProfileUpdate(
                contextRevision: "course-profile-full-text",
                profileRevision: 4,
                checkpoint: "userRequested",
                entries: [
                    StudyAgentCourseProfileUpdateEntry(
                        kind: .concept,
                        text: fullText,
                        sources: []
                    ),
                ]
            ),
            expectedContextRevision: "course-profile-full-text",
            target: WorkspaceStore.AgentConversationTarget(
                sessionID: UUID(),
                workingDirectory: root,
                courseID: courseID
            )
        )

        XCTAssertTrue(receipt.accepted)
        XCTAssertEqual(store.courseKnowledgeProfiles.first?.entries.count, 201)
        XCTAssertEqual(store.courseKnowledgeProfiles.first?.entries.last?.text, fullText)
    }

    @MainActor
    func testLearningUpdateKeepsFullSessionSummaryAndNextSteps() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiSessionSummary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessionID = UUID()
        let courseID = UUID()
        let snapshot = PersistedWorkspace(
            courses: [Course(id: courseID, title: "课程")],
            learningMemoryStates: [ScopedLearningMemoryState(scope: .course(courseID))],
            learningMemoryScopeMigrationVersion: 1,
            studySessions: [StudySession(id: sessionID, title: "学习会话", courseID: courseID)],
            studySessionScopeMigrationVersion: 1,
            activeStudySessionID: sessionID
        )
        try JSONEncoder().encode(snapshot).write(
            to: root.appendingPathComponent("workspace.json"),
            options: .atomic
        )
        let store = WorkspaceStore(workspaceDirectory: root, startsCourseFileMaintenance: false)
        let target = WorkspaceStore.AgentConversationTarget(
            sessionID: sessionID,
            workingDirectory: root,
            courseID: courseID
        )
        let memoryRevision = store.makeLearningContext(target: target).memoryRevision
        let summary = String(repeating: "完整会话摘要。", count: 400)
        let next = (1...5).map { "完整下一步 \($0) " + String(repeating: "内容", count: 180) }
        let receipt = store.persistNativeLearningUpdate(
            StudyAgentLearningUpdate(
                contextRevision: "session-summary-full-text",
                memoryRevision: memoryRevision,
                sessionSummary: summary,
                suggestedNext: next,
                entries: [
                    StudyAgentMemoryUpdateEntry(
                        kind: .progress,
                        text: "用户要求记录当前进度",
                        evidence: "[用户：本轮] 请记录当前进度",
                        origin: .userStatement
                    ),
                ]
            ),
            expectedContextRevision: "session-summary-full-text",
            expectedUserQuestion: "请记录当前进度",
            target: target,
            messageID: UUID()
        )

        XCTAssertTrue(receipt.accepted)
        XCTAssertEqual(store.studySessions.first?.summary, summary)
        XCTAssertEqual(store.studySessions.first?.flow.suggestedNext, next)
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
    func testManualSessionTitlePersistsAndSurvivesFirstQuestionNaming() async throws {
        let firstQuestion = AgentMessage(
            role: .user,
            text: "请帮我解释利率为什么变化",
            source: nil
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiSessionTitle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        let session = try XCTUnwrap(store.createStudySession(courseID: nil))
        store.messages = [firstQuestion]
        store.syncActiveStudySession(titleSeed: firstQuestion.text)
        XCTAssertTrue(store.renameStudySession(session.id, title: "我的利率课"))
        let saved = await store.flushPendingWorkspaceSaveAsync()
        XCTAssertTrue(saved)

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

    func testStandardTextEditingShortcutsAreNotAppActions() {
        for key in ["b", "f"] {
            XCTAssertNil(AppShortcutCatalog.action(
                matching: AppShortcutChord(key: key, modifiers: .command),
                overrides: [:]
            ))
        }
    }

    func testStoredShortcutConflictIsPreservedAndNotExecutable() throws {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: AppShortcutCatalog.defaultsKey)
        defer {
            if let original {
                defaults.set(original, forKey: AppShortcutCatalog.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppShortcutCatalog.defaultsKey)
            }
        }
        let conflict = AppShortcutID.threePaneWorkspace.defaultChord
        defaults.set(
            try JSONEncoder().encode([AppShortcutID.courseIndex.rawValue: conflict]),
            forKey: AppShortcutCatalog.defaultsKey
        )

        let loaded = AppShortcutCatalog.loadOverrides()
        XCTAssertEqual(loaded[.courseIndex], conflict)
        XCTAssertNil(AppShortcutCatalog.action(matching: conflict, overrides: loaded))
        XCTAssertNil(AppShortcutCatalog.executableChord(for: .courseIndex, overrides: loaded))
        XCTAssertNil(AppShortcutCatalog.executableChord(for: .threePaneWorkspace, overrides: loaded))
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
