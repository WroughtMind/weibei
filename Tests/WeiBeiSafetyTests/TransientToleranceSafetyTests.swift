import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

/// 阶段3 容断与 iCloud 占位符专项验证（计划 §5 阶段3 第5步）。
@MainActor
final class TransientToleranceSafetyTests: XCTestCase {
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

    private func makeStore(base: URL, library: URL) throws -> WorkspaceStore {
        try FileManager.default.createDirectory(at: workspaceDir(base), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: workspaceDir(base),
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)
        return store
    }

    private func workspaceDir(_ base: URL) -> URL {
        base.appendingPathComponent("workspace", isDirectory: true)
    }

    private func reconcile(_ store: WorkspaceStore) throws {
        try store.waitForCourseFileOperation {
            await store.reconcileCourseFilesNow()
        }
    }

    func testPlaceholderLogicalNameParsing() {
        XCTAssertEqual(
            CourseProjectFileWorker.logicalName(forICloudPlaceholderFileName: ".讲义.md.icloud"),
            "讲义.md"
        )
        XCTAssertEqual(
            CourseProjectFileWorker.logicalName(forICloudPlaceholderFileName: ".论文.pdf.icloud"),
            "论文.pdf"
        )
        XCTAssertNil(CourseProjectFileWorker.logicalName(forICloudPlaceholderFileName: "讲义.md"))
        XCTAssertNil(CourseProjectFileWorker.logicalName(forICloudPlaceholderFileName: ".DS_Store"))
        XCTAssertNil(CourseProjectFileWorker.logicalName(forICloudPlaceholderFileName: ".icloud"))
    }

    func testEntryPresenceNeverAbsentWhenPlaceholderExists() throws {
        let base = makeTempRoot("weibei-phase3-presence")
        defer { try? FileManager.default.removeItem(at: base) }
        let dir = base.appendingPathComponent("课程", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logical = dir.appendingPathComponent("讲义.md")
        let placeholder = dir.appendingPathComponent(".讲义.md.icloud")
        try "占位".write(to: placeholder, atomically: true, encoding: .utf8)

        guard case .presentUnmaterialized = CourseProjectFileWorker.entryPresence(at: logical) else {
            return XCTFail("逻辑路径缺席但占位符在，应为 presentUnmaterialized")
        }
        try FileManager.default.removeItem(at: placeholder)
        guard case .absent = CourseProjectFileWorker.entryPresence(at: logical) else {
            return XCTFail("占位符删除后应为 absent")
        }
    }


    func testGrayStateNotEnteredForPlaceholder() throws {
        let base = makeTempRoot("weibei-phase3-gray")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library)
        let courseID = try store.createCourseInLibrary(title: "占位课")

        let realSource = base.appendingPathComponent("讲义.md")
        try "讲义正文".write(to: realSource, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(realSource, courseID: courseID, role: .material)
        let item = imported.item
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))

        // Finder 里实体被驱逐成 iCloud 占位符（内容替换为占位文件形态）。
        try FileManager.default.removeItem(at: backingURL)
        try "占位".write(
            to: backingURL.deletingLastPathComponent()
                .appendingPathComponent("." + backingURL.lastPathComponent + ".icloud"),
            atomically: true, encoding: .utf8
        )

        try reconcile(store)

        XCTAssertNil(store.fileMissingSinceByItemID[item.id], "占位符在场不得进入灰态")
        XCTAssertNotNil(store.importedItems.first { $0.id == item.id }, "条目必须保留")
        XCTAssertEqual(store.displaySubtitle(for: item), item.subtitle)
    }

    func testStartupDigestMismatchDoesNotUnlinkNotes() throws {
        let base = makeTempRoot("weibei-phase3-unlink")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library)
        let courseID = try store.createCourseInLibrary(title: "断链课")
        let source = base.appendingPathComponent("笔记.md")
        try "原始正文".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))

        // 外部改动：digest 与记录不符。
        try "外部修改后的内容".write(to: backingURL, atomically: true, encoding: .utf8)
        store.refreshRuntimeItemURLs()

        XCTAssertNotNil(
            store.importedItems.first { $0.id == item.id }?.urlPath,
            "笔记 digest 不符不再启动断链，路径必须保留（计划 §5 阶段3）"
        )
    }

    func testStartupDigestMismatchDoesNotUnlinkMaterials() throws {
        let base = makeTempRoot("weibei-material-unlink")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library)
        let courseID = try store.createCourseInLibrary(title: "资料断链课")
        let source = base.appendingPathComponent("讲义.txt")
        try "原始讲义".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        XCTAssertFalse(item.isNotebookNote, "前提：必须走资料路径，不能被当成笔记")
        XCTAssertNotNil(item.contentDigest, "前提：资料须带 digest，才能覆盖旧启动哈希路径")
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))

        try "外部改过的讲义".write(to: backingURL, atomically: true, encoding: .utf8)
        store.refreshRuntimeItemURLs()

        XCTAssertNotNil(
            store.importedItems.first { $0.id == item.id }?.urlPath,
            "资料 digest 不符不得启动断链，路径必须保留（文件即真相）"
        )
    }

    func testReconciliationAdoptsExternalMaterialContentAndRefreshesDigest() throws {
        let base = makeTempRoot("weibei-material-reconcile-digest")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library)
        let courseID = try store.createCourseInLibrary(title: "资料对账课")
        let source = base.appendingPathComponent("讲义.txt")
        try "原始讲义".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        XCTAssertFalse(item.isNotebookNote, "前提：必须走资料路径")
        let originalDigest = try XCTUnwrap(item.contentDigest)
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))

        try "外部改过的讲义，对账应采用".write(to: backingURL, atomically: true, encoding: .utf8)
        store.refreshRuntimeItemURLs()
        try reconcile(store)

        let refreshed = try XCTUnwrap(store.importedItems.first { $0.id == item.id })
        let adopted = try CourseProjectFileWorker.snapshotFile(at: backingURL)
        XCTAssertNotNil(refreshed.urlPath, "对账后资料仍可打开")
        XCTAssertEqual(refreshed.contentDigest, adopted.sha256, "对账须采用外部新内容并刷新 digest")
        XCTAssertNotEqual(refreshed.contentDigest, originalDigest, "外部改动后 digest 必须变化")
    }

    /// 瞬断无横幅（计划 §5 阶段3 第5步）：文件缺席/未物化场景只保留条内状态，
    /// 不再弹重要操作横幅。
    func testTransientUnavailabilityShowsNoBanner() throws {
        let base = makeTempRoot("weibei-phase3-banner")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library)
        let courseID = try store.createCourseInLibrary(title: "横幅课")
        let source = base.appendingPathComponent("笔记.md")
        try "正文".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))
        store.select(itemID: item.id)
        XCTAssertEqual(store.activeNoteItemID, item.id, "前提：条目须为活跃笔记")

        // iCloud 瞬断形态：文件暂时缺席。
        try FileManager.default.removeItem(at: backingURL)
        store.setNoteFileError("无法读取原 Markdown：\(backingURL.lastPathComponent)", for: item.id)

        XCTAssertNil(
            store.importantOperationError,
            "文件缺席属瞬态不可用，不得弹重要操作横幅（条内状态呈现）"
        )
        XCTAssertNotNil(
            store.noteOperationErrorsByItemID[item.id],
            "条内错误状态必须保留，可见性不回退"
        )
    }
}


/// 纯异步扫描用例独立成类：与同步 store 用例隔离，避免 XCTest 混排上下文。
final class TransientToleranceScanTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testScanRecognizesPlaceholderAsMaterialItem() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-phase3-scan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let courseRoot = base.appendingPathComponent("课程", isDirectory: true)
        let docsDir = courseRoot.appendingPathComponent("文稿", isDirectory: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        try "占位".write(to: docsDir.appendingPathComponent(".讲义.md.icloud"), atomically: true, encoding: .utf8)
        try Data("%PDF-1.4\n".utf8).write(
            to: docsDir.appendingPathComponent(".论文.pdf.icloud"), options: [.atomic]
        )
        try FileManager.default.createDirectory(at: docsDir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let snapshot = try await CourseProjectFileWorker().scanCourse(at: courseRoot)

        let paths = snapshot.observations.map(\.relativePath)
        XCTAssertTrue(paths.contains("文稿/讲义.md"), "占位符应还原为逻辑路径；实际：\(paths)")
        XCTAssertTrue(paths.contains("文稿/论文.pdf"))
        XCTAssertFalse(paths.contains { $0.contains(".icloud") }, "不应出现占位符原始名")
        XCTAssertFalse(paths.contains { $0.contains(".git") }, "其他隐藏目录仍应跳过")
    }
}
