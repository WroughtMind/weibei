import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

/// 阶段1 写闸门专项验证（计划 §5 阶段1 第4步）。
@MainActor
final class WriteGateSafetyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    private func makeTempRoot(_ name: String) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeStore(
        base: URL,
        library: URL,
        backupRoot: URL,
        notebookWriter: ((String, URL) throws -> Void)? = nil
    ) throws -> WorkspaceStore {
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace", isDirectory: true),
            notebookMarkdownWriter: notebookWriter ?? {
                try WorkspaceStore.writeNotebookMarkdown($0, to: $1)
            },
            noteBackupRootURL: backupRoot,
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)
        return store
    }

    private func importNote(
        _ store: WorkspaceStore,
        base: URL,
        courseID: UUID,
        content: String,
        fileName: String? = nil
    ) throws -> (item: StudyItem, url: URL) {
        let source = base.appendingPathComponent("\(fileName ?? "笔记-\(UUID().uuidString)").md")
        try content.write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(
            source, courseID: courseID, role: .material
        )
        let url = try XCTUnwrap(store.resolvedLibraryURL(for: imported.item))
        return (imported.item, url)
    }

    private static func digest(of text: String) -> String {
        WorkspaceStore.noteContentDigest(Data(text.utf8))
    }

    private func conflict(
        itemID: String,
        disk: String,
        pending: String
    ) -> NoteEditorRecoveryConflict {
        NoteEditorRecoveryConflict(
            diskMarkdown: disk,
            checkpoint: NoteRecoveryCheckpoint(
                metadata: NoteRecoveryMetadata(
                    documentID: itemID,
                    baseFileDigest: Self.digest(of: "旧基线"),
                    checkpointDigest: Self.digest(of: pending),
                    revision: 1,
                    updatedAt: Date(),
                    dialectVersion: 1
                ),
                markdown: pending
            )
        )
    }

    func testGateRefusesWriteWithoutBaseline() throws {
        let base = makeTempRoot("weibei-gate-no-baseline")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "原始内容")

        XCTAssertThrowsError(
            try store.writeNotebookMarkdownThroughGate(
                "新内容", itemID: item.id, url: url, expectedBaseline: nil
            )
        ) { error in
            guard case NoteWriteGateError.writeRefusedKeepContent = error else {
                return XCTFail("期望 writeRefusedKeepContent，实际 \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "原始内容")
    }

    func testGateRefusesWhenRereadFails() throws {
        let base = makeTempRoot("weibei-gate-unreadable")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "原始内容")

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        XCTAssertThrowsError(
            try store.writeNotebookMarkdownThroughGate(
                "新内容", itemID: item.id, url: url, expectedBaseline: Self.digest(of: "任意")
            )
        ) { error in
            guard case NoteWriteGateError.writeRefusedKeepContent = error else {
                return XCTFail("期望 writeRefusedKeepContent，实际 \(error)")
            }
        }
        XCTAssertEqual(store.noteBackingContentDigestsByItemID[item.id] ?? "", "")
    }

    func testTwoExternalConflictsKeepBothDrafts() throws {
        let base = makeTempRoot("weibei-gate-multiple-conflicts")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "双冲突课")
        let noteA = try importNote(
            store,
            base: base,
            courseID: courseID,
            content: "甲基线",
            fileName: "甲"
        )
        let noteB = try importNote(
            store,
            base: base,
            courseID: courseID,
            content: "乙基线",
            fileName: "乙"
        )
        let cases = [
            (noteA, "甲基线", "甲外部修改", "甲待写正文"),
            (noteB, "乙基线", "乙外部修改", "乙待写正文"),
        ]
        store.noteEditingSession.replaceDocument(with: "当前未冲突笔记")
        for (note, baseline, external, pending) in cases {
            store.noteBackingContentDigestsByItemID[note.item.id] = Self.digest(of: baseline)
            try external.write(to: note.url, atomically: true, encoding: .utf8)
            store.scheduleNotePersistence(pending, for: note.item)
            store.flushPendingNotePersistence(for: note.item.id)
        }
        XCTAssertEqual(store.noteEditingSession.documentID, "当前未冲突笔记")
        XCTAssertEqual(store.noteEditingSession.saveStatus, .idle)

        for (note, _, _, pending) in cases {
            XCTAssertEqual(
                store.pendingPortableNoteDraftForSelfCheck(itemID: note.item.id),
                pending
            )
            store.activeNotebookItemID = note.item.id
            XCTAssertEqual(store.noteEditorRecoveryConflict?.checkpoint.markdown, pending)
        }
    }

    func testPersistNoteWritesWhenBaselineMatches() throws {
        let base = makeTempRoot("weibei-gate-normal-write")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "第一版")

        store.scheduleNotePersistence("第二版", for: item)
        store.flushPendingNotePersistence(for: item.id)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "第二版")
        XCTAssertEqual(store.noteBackingContentDigestsByItemID[item.id], Self.digest(of: "第二版"))
        XCTAssertEqual(store.lastSelfWrittenNoteDigestsByItemID[item.id], Self.digest(of: "第二版"))
    }

    func testRenameRewriteRoutesThroughGate() throws {
        let base = makeTempRoot("weibei-gate-rename")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(
            store,
            base: base,
            courseID: courseID,
            content: "# 旧标题\n正文",
            fileName: "旧标题"
        )

        try store.waitForCourseFileOperation {
            await store.renameNotebookNoteInTransaction(itemID: item.id, to: "新标题")
        }
        let documentsDir = url.deletingLastPathComponent()
        let renamedURL = documentsDir.appendingPathComponent("新标题.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: renamedURL, encoding: .utf8)
        XCTAssertTrue(content.contains("# 新标题"), "改名后正文抬头应更新：\(content)")
        XCTAssertTrue(content.contains("正文"))
    }

    func testRetryRestoredPendingWritesRoutesThroughGate() throws {
        let base = makeTempRoot("weibei-gate-retry")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "磁盘现况")

        store.notesByItemID[item.id] = "重启前未写完的草稿"
        store.pendingNoteWritesByItemID[item.id] = PendingNoteWriteState()
        store.retryRestoredPendingNoteWrites()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "重启前未写完的草稿")
    }

    func testWriteVerificationFailureKeepsDraftDirtyAndVisible() throws {
        let base = makeTempRoot("weibei-gate-writer-failure")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace", isDirectory: true),
            notebookMarkdownWriter: { _, url in
                try "半截".write(to: url, atomically: true, encoding: .utf8)
            },
            noteBackupRootURL: backupRoot,
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let source = base.appendingPathComponent("笔记.md")
        try "第一版".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let url = try XCTUnwrap(store.resolvedLibraryURL(for: item))
        store.noteEditingSession.replaceDocument(with: item.id)
        store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
            documentID: item.id,
            documentGeneration: store.noteEditingSession.documentGeneration,
            revision: 1,
            dirty: true
        ))

        store.scheduleNotePersistence("第二版", for: item)
        store.flushPendingNotePersistence(for: item.id)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "半截")
        XCTAssertEqual(
            store.pendingPortableNoteDraftForSelfCheck(itemID: item.id),
            "第二版"
        )
        XCTAssertTrue(store.noteEditingSession.dirty)
        XCTAssertEqual(store.noteEditingSession.saveStatus, .failed)
        XCTAssertEqual(store.noteBackingContentDigestsByItemID[item.id], Self.digest(of: "第一版"))
        XCTAssertNil(store.lastSelfWrittenNoteDigestsByItemID[item.id])
        let message = try XCTUnwrap(store.importantOperationError)
        XCTAssertTrue(message.contains(url.lastPathComponent))
        XCTAssertTrue(message.contains("已保存在魏碑中"))
        XCTAssertTrue(message.contains("重试"))
    }

    func testRestoreWeiBeiContentWritesCheckpointAndClearsConflict() async throws {
        let base = makeTempRoot("weibei-restore-conflict")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try makeStore(
            base: base,
            library: base.appendingPathComponent("资料库"),
            backupRoot: base.appendingPathComponent("backups")
        )
        let courseID = try store.createCourseInLibrary(title: "恢复课")
        let note = try importNote(
            store, base: base, courseID: courseID, content: "磁盘版本"
        )
        store.activeNotebookItemID = note.item.id
        store.noteEditorRecoveryConflict = conflict(
            itemID: note.item.id,
            disk: "磁盘版本",
            pending: "魏碑待写正文"
        )

        await store.resolveNoteEditorRecoveryConflict(useDisk: false)

        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "魏碑待写正文")
        XCTAssertNil(store.noteEditorRecoveryConflict)
    }

    func testRestoreWeiBeiContentFailureKeepsDraftAndConflict() async throws {
        struct InjectedWriteFailure: Error {}
        let base = makeTempRoot("weibei-restore-conflict-failure")
        defer { try? FileManager.default.removeItem(at: base) }
        let store = try makeStore(
            base: base,
            library: base.appendingPathComponent("资料库"),
            backupRoot: base.appendingPathComponent("backups"),
            notebookWriter: { _, _ in throw InjectedWriteFailure() }
        )
        let courseID = try store.createCourseInLibrary(title: "恢复失败课")
        let note = try importNote(
            store, base: base, courseID: courseID, content: "磁盘版本"
        )
        store.activeNotebookItemID = note.item.id
        store.noteEditorRecoveryConflict = conflict(
            itemID: note.item.id,
            disk: "磁盘版本",
            pending: "仍须保留的正文"
        )

        await store.resolveNoteEditorRecoveryConflict(useDisk: false)

        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "磁盘版本")
        XCTAssertEqual(store.notesByItemID[note.item.id], "仍须保留的正文")
        XCTAssertNotNil(store.noteEditorRecoveryConflict)
    }

}
