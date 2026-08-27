import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

@MainActor
final class SessionMessageExternalizationTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    override func tearDown() {
        StudySessionMessageExternalizationTesting.reset()
        super.tearDown()
    }

    /// 旧工作区里的聊天搬家后一条不少，主账本不再夹带正文，并留下搬家前备份。
    func testLegacyEmbeddedMessagesMigrateWithoutLossAndLeaveBackup() throws {
        let root = try makeTempWorkspace()
        let sessionA = makeSession(
            title: "课程答疑",
            texts: ["什么是魏碑", "北朝刻石书体"]
        )
        let sessionB = makeSession(
            title: "读书笔记",
            texts: ["第一段", "第二段", "第三段"]
        )
        try writeLegacyWorkspace(
            at: root,
            sessions: [sessionA, sessionB],
            activeID: sessionA.id
        )

        let store = WorkspaceStore(
            workspaceDirectory: root,
            startsCourseFileMaintenance: false
        )
        XCTAssertTrue(store.flushPendingWorkspaceSave())

        XCTAssertEqual(store.studySessions.count, 2)
        XCTAssertTrue(
            store.activateStudySession(
                sessionA.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        )
        XCTAssertEqual(
            store.studySessions.first { $0.id == sessionA.id }?.messages.map(\.text),
            sessionA.messages.map(\.text)
        )
        XCTAssertTrue(
            store.activateStudySession(
                sessionB.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        )
        XCTAssertEqual(
            store.studySessions.first { $0.id == sessionB.id }?.messages.map(\.text),
            sessionB.messages.map(\.text)
        )

        let snapshot = try readSnapshot(in: root)
        XCTAssertEqual(snapshot.studySessions?.count, 2)
        XCTAssertTrue(
            snapshot.studySessions?.allSatisfy { $0.messages.isEmpty } == true
        )
        XCTAssertEqual(
            snapshot.studySessions?.first { $0.id == sessionA.id }?.messageCount,
            sessionA.messages.count
        )
        XCTAssertEqual(
            snapshot.studySessions?.first { $0.id == sessionB.id }?.messageCount,
            sessionB.messages.count
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: StudySessionMessageFile.backupURL(in: root).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: StudySessionMessageFile.fileURL(
                    sessionID: sessionA.id,
                    in: root
                ).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: StudySessionMessageFile.fileURL(
                    sessionID: sessionB.id,
                    in: root
                ).path
            )
        )
    }

    /// 已经搬过家的工作区再打开不会重搬，也不会覆盖上一份备份。
    func testSecondLaunchDoesNotRewriteBackupOrRemigrate() throws {
        let root = try makeTempWorkspace()
        let sessionA = makeSession(title: "甲", texts: ["问甲", "答甲"])
        let sessionB = makeSession(title: "乙", texts: ["问乙"])
        try writeLegacyWorkspace(
            at: root,
            sessions: [sessionA, sessionB],
            activeID: sessionA.id
        )
        let first = WorkspaceStore(
            workspaceDirectory: root,
            startsCourseFileMaintenance: false
        )
        XCTAssertTrue(first.flushPendingWorkspaceSave())
        let backupURL = StudySessionMessageFile.backupURL(in: root)
        let backupBytes = try Data(contentsOf: backupURL)
        let backupModified = try modificationDate(at: backupURL)

        let second = WorkspaceStore(
            workspaceDirectory: root,
            startsCourseFileMaintenance: false
        )
        XCTAssertTrue(second.flushPendingWorkspaceSave())
        XCTAssertNil(second.workspaceSaveFailure)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBytes)
        XCTAssertEqual(try modificationDate(at: backupURL), backupModified)
        XCTAssertTrue(
            try readSnapshot(in: root).studySessions?
                .allSatisfy { $0.messages.isEmpty } == true
        )
    }

    /// 搬家校验对不上时用旧账本启动，聊天正文仍留在 workspace.json 里。
    func testFailedMigrationRollsBackEmbeddedMessages() throws {
        let root = try makeTempWorkspace()
        let sessionA = makeSession(title: "甲", texts: ["不可丢失"])
        let sessionB = makeSession(title: "乙", texts: ["同样保留"])
        try writeLegacyWorkspace(
            at: root,
            sessions: [sessionA, sessionB],
            activeID: sessionA.id
        )
        StudySessionMessageExternalizationTesting.corruptSessionIDAfterMigrationWrite =
            sessionA.id

        let store = WorkspaceStore(
            workspaceDirectory: root,
            startsCourseFileMaintenance: false
        )
        XCTAssertEqual(
            store.workspaceSaveFailure?.kind,
            .sessionMessageExternalizationFailed
        )
        XCTAssertEqual(store.lastPersistState, .failed)
        XCTAssertEqual(
            store.studySessions.first { $0.id == sessionA.id }?.messages.map(\.text),
            ["不可丢失"]
        )
        XCTAssertEqual(
            store.studySessions.first { $0.id == sessionB.id }?.messages.map(\.text),
            ["同样保留"]
        )
        let snapshot = try readSnapshot(in: root)
        XCTAssertEqual(
            snapshot.studySessions?.first { $0.id == sessionA.id }?.messages.map(\.text),
            ["不可丢失"]
        )
        XCTAssertTrue(snapshot.hasEmbeddedStudySessionMessages)
    }

    /// 单个会话文件坏了只影响那一通聊天，其它聊天仍完整，App 能打开。
    func testCorruptSessionFileDoesNotBlockLaunchOrOtherSessions() throws {
        let root = try makeTempWorkspace()
        let sessionA = makeSession(title: "甲", texts: ["甲的问题", "甲的回答"])
        let sessionB = makeSession(title: "乙", texts: ["乙还在"])
        try writeLegacyWorkspace(
            at: root,
            sessions: [sessionA, sessionB],
            activeID: sessionB.id
        )
        let first = WorkspaceStore(
            workspaceDirectory: root,
            startsCourseFileMaintenance: false
        )
        XCTAssertTrue(first.flushPendingWorkspaceSave())

        try Data("{".utf8).write(
            to: StudySessionMessageFile.fileURL(sessionID: sessionA.id, in: root),
            options: .atomic
        )

        let reopened = WorkspaceStore(
            workspaceDirectory: root,
            startsCourseFileMaintenance: false
        )
        XCTAssertEqual(reopened.studySessions.count, 2)
        XCTAssertTrue(
            reopened.historicalStudySessions.contains { $0.id == sessionA.id }
        )
        XCTAssertTrue(
            reopened.activateStudySession(
                sessionB.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        )
        XCTAssertEqual(
            reopened.studySessions.first { $0.id == sessionB.id }?.messages.map(\.text),
            ["乙还在"]
        )
        XCTAssertTrue(
            reopened.activateStudySession(
                sessionA.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        )
        XCTAssertEqual(
            reopened.studySessions.first { $0.id == sessionA.id }?.messages.map(\.text),
            ["甲的问题", "甲的回答"]
        )
    }

    /// 改一通聊天再保存，只动那一个会话文件，其它聊天文件保持原样。
    func testSavingOneSessionLeavesOtherSessionFilesUnchanged() throws {
        let root = try makeTempWorkspace()
        let sessionA = makeSession(title: "甲", texts: ["原问"])
        let sessionB = makeSession(title: "乙", texts: ["旁路"])
        try writeLegacyWorkspace(
            at: root,
            sessions: [sessionA, sessionB],
            activeID: sessionA.id
        )
        let store = WorkspaceStore(
            workspaceDirectory: root,
            startsCourseFileMaintenance: false
        )
        XCTAssertTrue(store.flushPendingWorkspaceSave())
        let fileA = StudySessionMessageFile.fileURL(sessionID: sessionA.id, in: root)
        let fileB = StudySessionMessageFile.fileURL(sessionID: sessionB.id, in: root)
        let bytesB = try Data(contentsOf: fileB)

        XCTAssertTrue(
            store.activateStudySession(
                sessionA.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        )
        store.appendAgentMessage(
            AgentMessage(role: .user, text: "追加一句", source: nil)
        )
        XCTAssertTrue(store.flushPendingWorkspaceSave())

        XCTAssertEqual(try Data(contentsOf: fileB), bytesB)
        let updatedA = try StudySessionMessageFile.decoder()
            .decode(
                PersistedStudySessionMessages.self,
                from: Data(contentsOf: fileA)
            )
        XCTAssertEqual(updatedA.messages.map(\.text), ["原问", "追加一句"])
        XCTAssertTrue(
            try readSnapshot(in: root).studySessions?
                .allSatisfy { $0.messages.isEmpty } == true
        )
    }

    private func makeTempWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "weibei-session-ext-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func makeSession(title: String, texts: [String]) -> StudySession {
        StudySession(
            title: title,
            messages: texts.map { AgentMessage(role: .user, text: $0, source: nil) }
        )
    }

    private func writeLegacyWorkspace(
        at root: URL,
        sessions: [StudySession],
        activeID: UUID
    ) throws {
        let snapshot = PersistedWorkspace(
            importedItems: [],
            notesByItemID: [:],
            studySessions: sessions,
            activeStudySessionID: activeID
        )
        try JSONEncoder().encode(snapshot).write(
            to: root.appendingPathComponent("workspace.json"),
            options: [.atomic]
        )
    }

    private func readSnapshot(in root: URL) throws -> PersistedWorkspace {
        try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: Data(
                contentsOf: root.appendingPathComponent("workspace.json")
            )
        )
    }

    private func modificationDate(at url: URL) throws -> Date {
        try url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
            ?? {
                throw NSError(
                    domain: "SessionMessageExternalizationTests",
                    code: 1
                )
            }()
    }
}
