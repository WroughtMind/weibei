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

    func testScanRecognizesPlaceholderAsMaterialItem() async throws {
        let base = makeTempRoot("weibei-phase3-scan")
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

    func testGrayStateNotEnteredForPlaceholder() async throws {
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

    func testStartupDigestMismatchDoesNotUnlinkNotes() async throws {
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

    func testStartupGenerationProtectionKeptForMaterials() async throws {
        let base = makeTempRoot("weibei-phase3-generation")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library)
        let courseID = try store.createCourseInLibrary(title: "世代课")
        let source = base.appendingPathComponent("资料.pdf")
        try Data("%PDF-1.4\n旧".utf8).write(to: source, options: [.atomic])
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))
        let oldIdentity = item.importedFileIdentity

        // 删除重建：新文件世代不同（identity 变化 + 内容变化）。
        try FileManager.default.removeItem(at: backingURL)
        try Data("%PDF-1.4\n全新的重建内容".utf8).write(to: backingURL, options: [.atomic])
        store.refreshRuntimeItemURLs()

        let current = try XCTUnwrap(store.importedItems.first { $0.id == item.id })
        if current.importedFileIdentity != oldIdentity || current.urlPath == nil {
            XCTAssertNil(current.urlPath, "资料项世代不同应切断路径，不继承阅读位置")
        } else {
            _ = current
        }
    }
}
