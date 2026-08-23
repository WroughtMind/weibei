import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

/// 阶段 0 行为基线 → 阶段 2「副本先行」落地后转正式（计划 §5 阶段0→阶段2）。
@MainActor
final class FileModelPhase0BaselineTests: XCTestCase {
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

    private func reconcile(_ store: WorkspaceStore) throws {
        try store.waitForCourseFileOperation {
            await store.reconcileCourseFilesNow()
        }
    }

    private func backupContents(
        _ backupRoot: URL,
        itemID: String
    ) throws -> [String] {
        try NoteBackupRing.list(itemID: itemID, rootURL: backupRoot)
            .compactMap { try? String(contentsOf: $0.url, encoding: .utf8) }
    }

    func testExternalDeleteKeepsUnsavedInput() throws {
        let base = makeTempRoot("weibei-phase0-external-delete")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "外删课")
        let source = base.appendingPathComponent("诗歌.md")
        try "原始正文".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item

        let unsavedInput = "用户正在输入、尚未落盘的新内容"
        store.scheduleNotePersistence(unsavedInput, for: item)

        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))
        try FileManager.default.removeItem(at: backingURL)
        try reconcile(store)

        XCTAssertEqual(
            store.displaySubtitle(for: item),
            store.ui("文件不存在", "File missing"),
            "首缺席应进入灰态而不是立即移除"
        )
        XCTAssertNotNil(store.importedItems.first { $0.id == item.id })

        store.fileMissingSinceByItemID[item.id] = Date().addingTimeInterval(-7)
        try reconcile(store)

        let recovered = try backupContents(backupRoot, itemID: item.id)
        XCTAssertTrue(
            recovered.contains(unsavedInput),
            "外部删除后未落盘输入应已存入备份环；实际备份内容：\(recovered)"
        )
    }

    func testUseDiskConflictKeepsUserVersion() throws {
        let base = makeTempRoot("weibei-phase0-conflict-use-disk")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "冲突课")
        let source = base.appendingPathComponent("笔记.md")
        try "磁盘版本".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))

        let userVersion = "用户的本地修改版本"
        let checkpoint = NoteRecoveryCheckpoint(
            metadata: NoteRecoveryMetadata(
                documentID: item.id,
                baseFileDigest: Self.digest(of: "原始正文"),
                checkpointDigest: Self.digest(of: userVersion),
                revision: 3,
                updatedAt: Date(),
                dialectVersion: 1
            ),
            markdown: userVersion
        )
        store.noteEditorRecoveryConflict = NoteEditorRecoveryConflict(
            diskMarkdown: "磁盘版本",
            checkpoint: checkpoint
        )

        try store.waitForCourseFileOperation {
            await store.resolveNoteEditorRecoveryConflict(useDisk: true)
        }

        let recovered = try backupContents(backupRoot, itemID: item.id)
        XCTAssertTrue(
            recovered.contains(userVersion),
            "冲突选「使用磁盘版本」后用户版本应已存入备份环；实际备份内容：\(recovered)"
        )
        XCTAssertNil(store.noteEditorRecoveryConflict)
        XCTAssertEqual(store.noteText, "磁盘版本")
        XCTAssertNotNil(store.transientNoteStatus)

        store.scheduleNotePersistence("采用磁盘后的新编辑", for: item)
        store.flushPendingNotePersistence(for: item.id)
        XCTAssertEqual(try String(contentsOf: backingURL, encoding: .utf8), "采用磁盘后的新编辑")
        XCTAssertNil(store.noteEditorRecoveryConflict)
    }

    func testGoneItemGraysAndReclaims() throws {
        let base = makeTempRoot("weibei-phase2-gray-reclaim")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "灰态课")
        let source = base.appendingPathComponent("讲义.md")
        try "讲义内容".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))

        try FileManager.default.removeItem(at: backingURL)
        try reconcile(store)

        XCTAssertEqual(store.displaySubtitle(for: item), store.ui("文件不存在", "File missing"))
        XCTAssertNotNil(store.importedItems.first { $0.id == item.id }, "灰态期间条目必须保留")
        XCTAssertNotNil(store.fileMissingSinceByItemID[item.id])

        try "讲义内容".write(to: backingURL, atomically: true, encoding: .utf8)
        try reconcile(store)

        let reclaimed = try XCTUnwrap(
            store.importedItems.first { $0.id == item.id },
            "文件重现后应认领回同一 itemID"
        )
        XCTAssertTrue(reclaimed.urlPath?.hasSuffix("讲义.md") == true)
        XCTAssertNil(store.fileMissingSinceByItemID[item.id])
        XCTAssertEqual(store.displaySubtitle(for: reclaimed), reclaimed.subtitle)
    }

    func testGoneItemRemovalBacksUpDraft() throws {
        let base = makeTempRoot("weibei-phase2-removal-backup")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "移除课")
        let source = base.appendingPathComponent("草稿.md")
        try "原稿".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))

        let draft = "未落盘草稿内容"
        store.scheduleNotePersistence(draft, for: item)

        try FileManager.default.removeItem(at: backingURL)
        try reconcile(store)
        store.fileMissingSinceByItemID[item.id] = Date().addingTimeInterval(-7)
        try reconcile(store)

        XCTAssertNil(store.importedItems.first { $0.id == item.id }, "两个周期仍缺席应移除条目")
        let recovered = try backupContents(backupRoot, itemID: item.id)
        XCTAssertTrue(recovered.contains(draft), "移除前草稿应入备份环；实际：\(recovered)")
    }

    private static func digest(of text: String) -> String {
        WorkspaceStore.noteContentDigest(Data(text.utf8))
    }
}
