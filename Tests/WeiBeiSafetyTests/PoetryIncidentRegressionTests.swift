import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

/// 8/12 诗歌笔记事故全场景回归（计划 §5 阶段4 第3步）。
///
/// 事故通道：读盘失败 → 降级显示模板 → 用户在模板上继续编辑 →
/// 写回/改名/重启 retry 把模板盖回磁盘，真实正文丢失。
///
/// 新架构不变量（逐通道断言）：
/// 1. 真实正文必不丢——要么仍在磁盘，要么在备份环中可找回；
/// 2. 用户输入必不丢——要么落盘，要么保留为草稿；
/// 3. 降级期间产生的模板形态内容不得静默替换真实正文而无备份。
@MainActor
final class PoetryIncidentRegressionTests: XCTestCase {
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
        return try WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace", isDirectory: true),
            noteBackupRootURL: backupRoot,
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        .configuredForLibrary(at: library)
    }

    /// 真实正文可找回：磁盘仍是真实正文，或备份环里有它。
    private func realBodyRecoverable(
        _ realBody: String,
        at url: URL,
        itemID: String,
        backupRoot: URL
    ) -> Bool {
        if (try? String(contentsOf: url, encoding: .utf8)) == realBody {
            return true
        }
        let backups = (try? NoteBackupRing.list(itemID: itemID, rootURL: backupRoot)) ?? []
        return backups.contains { (try? String(contentsOf: $0.url, encoding: .utf8)) == realBody }
    }

    private func importPoetryNote(
        _ store: WorkspaceStore,
        base: URL,
        courseID: UUID
    ) throws -> (item: StudyItem, url: URL) {
        let source = base.appendingPathComponent("诗歌.md")
        try "# 诗歌\n\n真实正文：山川异域，风月同天。".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let url = try XCTUnwrap(store.resolvedLibraryURL(for: imported.item))
        return (imported.item, url)
    }

    /// 通道一：读盘失败降级显示模板 → 用户在模板上编辑 → 自动写回。
    /// 真实正文必不丢（磁盘或备份环），用户输入必不丢（落盘或草稿）。
    func testIncidentEditWriteBackNeverLosesRealBody() throws {
        let base = makeTempRoot("weibei-poetry-edit")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "诗歌课")
        let (item, url) = try importPoetryNote(store, base: base, courseID: courseID)
        let realBody = try String(contentsOf: url, encoding: .utf8)

        // 模拟降级态：读盘失败已标记，编辑器展示的是模板，用户在其上继续输入。
        store.setNoteFileError("无法读取笔记文件，正文展示已降级为模板", for: item.id)
        let degradedEdit = store.defaultNote(for: item) + "\n用户在降级视图里的补充"
        store.scheduleNotePersistence(degradedEdit, for: item)
        store.flushPendingNotePersistence(for: item.id)
        XCTAssertTrue(store.flushPendingWorkspaceSave())
        let reopened = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace"),
            startsCourseFileMaintenance: false
        )

        XCTAssertTrue(
            realBodyRecoverable(realBody, at: url, itemID: item.id, backupRoot: backupRoot),
            "写回通道：真实正文必须在磁盘或备份环中可找回"
        )
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(
            onDisk == degradedEdit || reopened.notesByItemID[item.id] == degradedEdit,
            "写回通道：用户输入不得丢失"
        )
    }

    /// 通道二：降级态下改名。改名会把内存里的模板形态正文重写进新文件。
    /// 真实正文必不丢（原路径、新路径或备份环）。
    func testIncidentRenameKeepsRealBody() throws {
        let base = makeTempRoot("weibei-poetry-rename")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "诗歌课")
        let (item, url) = try importPoetryNote(store, base: base, courseID: courseID)
        let realBody = try String(contentsOf: url, encoding: .utf8)

        // 模拟降级态：条目为活跃笔记，noteText 是模板形态，且留有未落盘草稿
        // （有草稿时加载成功也不覆盖编辑器，降级现场稳定）。
        store.setNoteFileError("无法读取笔记文件，正文展示已降级为模板", for: item.id)
        let degradedDraft = store.defaultNote(for: item)
        store.notesByItemID[item.id] = degradedDraft
        store.select(itemID: item.id)
        store.noteText = degradedDraft
        let renamedURL = url.deletingLastPathComponent()
            .appendingPathComponent("新标题.md")

        try store.waitForCourseFileOperation {
            await store.renameNotebookNoteInTransaction(itemID: item.id, to: "新标题")
        }

        XCTAssertTrue(
            realBodyRecoverable(realBody, at: url, itemID: item.id, backupRoot: backupRoot)
                || (try? String(contentsOf: renamedURL, encoding: .utf8)) == realBody,
            "改名通道：真实正文必须在原路径、新路径或备份环中可找回"
        )
    }

    /// 通道三：降级态草稿随工作区持久化 → 重启后 retry 写回。
    /// 真实正文必不丢，模板形态草稿不得无备份地覆盖它。
    func testIncidentRestartRetryNeverLosesRealBody() throws {
        let base = makeTempRoot("weibei-poetry-retry")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "诗歌课")
        let (item, url) = try importPoetryNote(store, base: base, courseID: courseID)
        let realBody = try String(contentsOf: url, encoding: .utf8)

        // 模拟重启恢复现场：降级期草稿 + pending 标记，磁盘仍是真实正文。
        let degradedDraft = store.defaultNote(for: item)
        store.notesByItemID[item.id] = degradedDraft
        store.pendingNoteWritesByItemID[item.id] = PendingNoteWriteState()
        store.retryRestoredPendingNoteWrites()
        XCTAssertTrue(store.flushPendingWorkspaceSave())
        let reopened = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace"),
            startsCourseFileMaintenance: false
        )

        XCTAssertTrue(
            realBodyRecoverable(realBody, at: url, itemID: item.id, backupRoot: backupRoot),
            "重启 retry 通道：真实正文必须在磁盘或备份环中可找回"
        )
        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(
            after == realBody || after == degradedDraft
                || reopened.notesByItemID[item.id] == degradedDraft,
            "重启 retry 通道：磁盘要么仍是真实正文，要么是写回的草稿本体，草稿不得无痕迹消失"
        )
    }

    /// 通道四：降级且磁盘暂不可读时改名。闸门重读失败必须拒写；
    /// 无论回滚到原路径还是滞留新路径，真实正文必须完整找回，草稿必须保留。
    func testIncidentRenameWithUnreadableFileRefusesAndKeepsBody() throws {
        let base = makeTempRoot("weibei-poetry-unreadable")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "诗歌课")
        let (item, url) = try importPoetryNote(store, base: base, courseID: courseID)
        let realBody = try String(contentsOf: url, encoding: .utf8)
        let renamedURL = url.deletingLastPathComponent()
            .appendingPathComponent("新标题.md")

        store.setNoteFileError("无法读取笔记文件，正文展示已降级为模板", for: item.id)
        let degradedDraft = store.defaultNote(for: item)
        store.notesByItemID[item.id] = degradedDraft
        store.select(itemID: item.id)
        store.noteText = degradedDraft
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)

        try? store.waitForCourseFileOperation {
            await store.renameNotebookNoteInTransaction(itemID: item.id, to: "新标题")
        }

        // 恢复权限后找回正文：旧路径、新路径任一完整即可。
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: renamedURL.path)
        let oldBody = try? String(contentsOf: url, encoding: .utf8)
        let newBody = try? String(contentsOf: renamedURL, encoding: .utf8)
        let reopened = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace"),
            startsCourseFileMaintenance: false
        )
        XCTAssertTrue(
            oldBody == realBody || newBody == realBody,
            "不可读改名通道：真实正文必须在原路径或新路径完整找回"
        )
        XCTAssertEqual(
            reopened.notesByItemID[item.id]
                ?? reopened.notesByItemID.values.first { $0 == degradedDraft },
            degradedDraft,
            "用户草稿必须保留"
        )
    }
}

private extension WorkspaceStore {
    func configuredForLibrary(at library: URL) throws -> WorkspaceStore {
        try configureCourseLibrary(at: library)
        return self
    }
}
