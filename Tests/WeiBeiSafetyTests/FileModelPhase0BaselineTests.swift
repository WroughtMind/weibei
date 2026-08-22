import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

/// 阶段 0 行为基线冻结（计划 §5 阶段 0）。
/// 两个用例描述阶段 2「副本先行」落地后的目标行为；当前实现尚未满足，
/// 用 XCTExpectFailure 标注为预期失败，不进 CI 门槛，阶段 2 转正式。
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

    func testExternalDeleteKeepsUnsavedInput() throws {
        XCTExpectFailure("阶段2副本先行落地后转正式（计划 §5 阶段0→阶段2）")
        try runExternalDeleteScenario()
    }

    private func runExternalDeleteScenario() throws {
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
        try store.waitForCourseFileOperation {
            await store.reconcileCourseFilesNow()
        }

        let backups = try NoteBackupRing.list(itemID: item.id, rootURL: backupRoot)
        let recovered = backups.compactMap { entry in
            try? String(contentsOf: entry.url, encoding: .utf8)
        }
        XCTAssertTrue(
            recovered.contains(unsavedInput),
            "外部删除后未落盘输入应已存入备份环；实际备份内容：\(recovered)"
        )
    }

    func testUseDiskConflictKeepsUserVersion() throws {
        XCTExpectFailure("阶段2冲突条备份落地后转正式（计划 §5 阶段0→阶段2）")
        try runUseDiskConflictScenario()
    }

    private func runUseDiskConflictScenario() throws {
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

        XCTAssertEqual(store.noteText, "磁盘版本")

        let backups = try NoteBackupRing.list(itemID: item.id, rootURL: backupRoot)
        let recovered = backups.compactMap { entry in
            try? String(contentsOf: entry.url, encoding: .utf8)
        }
        XCTAssertTrue(
            recovered.contains(userVersion),
            "冲突选「使用磁盘版本」后用户版本应已存入备份环；实际备份内容：\(recovered)"
        )
    }

    private static func digest(of text: String) -> String {
        let data = Data(text.utf8)
        return WorkspaceStore.noteContentDigest(data)
    }
}
