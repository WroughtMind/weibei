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
        backupRoot: URL
    ) throws -> WorkspaceStore {
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace", isDirectory: true),
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
        content: String
    ) throws -> (item: StudyItem, url: URL) {
        let source = base.appendingPathComponent("笔记-\(UUID().uuidString).md")
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
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: "")
            try? FileManager.default.removeItem(at: base)
        }
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

    func testGateBacksUpPendingContentAndAdoptsDiskOnMismatch() throws {
        let base = makeTempRoot("weibei-gate-mismatch")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "基线内容")
        store.noteBackingContentDigestsByItemID[item.id] = Self.digest(of: "基线内容")

        try "外部修改".write(to: url, atomically: true, encoding: .utf8)

        let pendingInput = "用户未落盘的编辑"
        store.scheduleNotePersistence(pendingInput, for: item)
        store.flushPendingNotePersistence(for: item.id)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "外部修改")
        XCTAssertEqual(store.loadedCourseNoteTextByItemID[item.id], "外部修改")
        let backups = try NoteBackupRing.list(itemID: item.id, rootURL: backupRoot)
        let recovered = backups.compactMap { entry in
            try? String(contentsOf: entry.url, encoding: .utf8)
        }
        XCTAssertTrue(recovered.contains(pendingInput), "待写内容应先入备份环；实际：\(recovered)")
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
        let (item, _) = try importNote(store, base: base, courseID: courseID, content: "# 旧标题\n正文")

        try store.waitForCourseFileOperation {
            await store.renameNotebookNoteInTransaction(itemID: item.id, to: "新标题")
        }
        let documentsDir = try XCTUnwrap(url.deletingLastPathComponent())
        let renamedURL = documentsDir.appendingPathComponent("新标题.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: renamedURL, encoding: .utf8)
        XCTAssertTrue(content.contains("# 新标题"), "改名后正文抬头应更新：\(content)")
        XCTAssertTrue(content.contains("正文"))
    }

    func testRepairRestoreDraftRoutesThroughGate() throws {
        let base = makeTempRoot("weibei-gate-repair")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "# 标题\n真实草稿")

        store.notesByItemID[item.id] = "磁盘上没有的草稿内容"

        store.repairDivergedNotebookNotesIfNeeded()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "磁盘上没有的草稿内容")
        XCTAssertEqual(store.notesByItemID[item.id], nil)
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
        store.pendingNoteWritesByItemID[item.id] = PendingNoteWriteState(baselineContentDigest: nil)
        store.retryRestoredPendingNoteWrites()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "重启前未写完的草稿")
    }

    func testWriterFailureKeepsDraftAndSkipsDigestRefresh() throws {
        let base = makeTempRoot("weibei-gate-writer-failure")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        struct ExplodingWriterError: Error {}
        let store = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace", isDirectory: true),
            notebookMarkdownWriter: { markdown, url in
                try "半截".write(to: url, atomically: true, encoding: .utf8)
                throw ExplodingWriterError()
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

        store.scheduleNotePersistence("第二版", for: item)
        store.flushPendingNotePersistence(for: item.id)

        XCTAssertEqual(store.notesByItemID[item.id], "第二版")
        XCTAssertNil(store.lastSelfWrittenNoteDigestsByItemID[item.id])
    }
}
