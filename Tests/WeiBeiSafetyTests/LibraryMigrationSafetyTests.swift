import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

@MainActor
final class LibraryMigrationSafetyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    private func makeStore(workspace: URL, library: URL) throws -> WorkspaceStore {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: workspace,
            courseRootBookmarkMaker: { Data($0.standardizedFileURL.path.utf8) },
            courseRootBookmarkResolver: { data in
                guard let path = String(data: data, encoding: .utf8) else { return nil }
                return CourseProjectResolvedBookmark(
                    url: URL(fileURLWithPath: path),
                    isStale: false
                )
            },
            courseSecurityScopeStarter: { _ in true },
            courseSecurityScopeStopper: { _ in },
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)
        return store
    }

    private func makeTempRoot(_ name: String) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func migrate(_ store: WorkspaceStore, to destination: URL) throws -> WorkspaceStore.LibraryMigrationResult {
        try store.waitForCourseFileOperation {
            try await store.migrateLibrary(to: destination)
        }
    }

    private func reconcile(_ store: WorkspaceStore) throws {
        try store.waitForCourseFileOperation {
            await store.reconcileCourseFilesNow()
        }
    }

    func testMigrateLibraryMovesTreeAndRebinds() throws {
        let base = makeTempRoot("weibei-migration-move")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("旧资料库", isDirectory: true)
        let destination = base.appendingPathComponent("新资料库", isDirectory: true)
        let store = try makeStore(
            workspace: base.appendingPathComponent("workspace", isDirectory: true),
            library: library
        )
        let courseID = try store.createCourseInLibrary(title: "迁移课")
        let noteSource = base.appendingPathComponent("第一讲.md")
        try "第一讲正文".write(to: noteSource, atomically: true, encoding: .utf8)
        _ = try store.importFileIntoCourseForSelfCheck(noteSource, courseID: courseID, role: .material)

        let result = try migrate(store, to: destination)

        XCTAssertEqual(result.destination.standardizedFileURL, destination.standardizedFileURL)
        let leftoverEntries = (try? FileManager.default.contentsOfDirectory(atPath: library.path)) ?? []
        XCTAssertTrue(
            leftoverEntries.isEmpty,
            "旧资料库目录残留：\(leftoverEntries)，当前绑定=\(store.courseLibraryRootPath ?? "nil")"
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("迁移课/.weibei/course.json").path
        ))
        XCTAssertEqual(store.courseLibraryRootURL?.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertEqual(store.courseLibraryRootPath, destination.standardizedFileURL.path)
        let movedCourseRoot = try XCTUnwrap(store.courseRootURL(for: courseID))
        XCTAssertTrue(movedCourseRoot.path.hasPrefix(destination.path))
        XCTAssertEqual(store.courseManifestCourseID(at: movedCourseRoot), courseID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedCourseRoot.appendingPathComponent(".weibei/course.json").path))
        let migratedItem = try XCTUnwrap(store.importedItems.first { item in
            if case .courseOwned = item.storage { return true }
            return false
        })
        let itemURL = try XCTUnwrap(store.resolvedLibraryURL(for: migratedItem))
        XCTAssertTrue(itemURL.path.hasPrefix(destination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: itemURL.path))
        XCTAssertEqual(try String(contentsOf: itemURL, encoding: .utf8), "第一讲正文")
    }

    func testMigrateLibraryRejectsNestedAndNonEmpty() throws {
        let base = makeTempRoot("weibei-migration-reject")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(
            workspace: base.appendingPathComponent("workspace", isDirectory: true),
            library: library
        )
        let courseID = try store.createCourseInLibrary(title: "课程甲")

        let nested = library.appendingPathComponent("嵌套目标", isDirectory: true)
        do {
            _ = try migrate(store, to: nested)
            XCTFail("嵌套目标应被拒绝")
        } catch let error as CourseProjectRootError {
            guard case .destinationInsideLibrary = error else {
                return XCTFail("期望 destinationInsideLibrary，实际 \(error)")
            }
        }
        do {
            _ = try migrate(store, to: library)
            XCTFail("库自身应被拒绝")
        } catch let error as CourseProjectRootError {
            guard case .destinationIsLibrary = error else {
                return XCTFail("期望 destinationIsLibrary，实际 \(error)")
            }
        }

        let nonEmpty = base.appendingPathComponent("非空目录", isDirectory: true)
        try FileManager.default.createDirectory(at: nonEmpty, withIntermediateDirectories: true)
        try "占位".write(to: nonEmpty.appendingPathComponent("其他文件.txt"), atomically: true, encoding: .utf8)
        do {
            _ = try migrate(store, to: nonEmpty)
            XCTFail("非空目标应被拒绝")
        } catch let error as CourseProjectRootError {
            guard case .destinationNotEmpty = error else {
                return XCTFail("期望 destinationNotEmpty，实际 \(error)")
            }
        }

        let courseRoot = try XCTUnwrap(store.courseRootURL(for: courseID))
        XCTAssertEqual(store.courseManifestCourseID(at: courseRoot), courseID)
        XCTAssertEqual(store.courseLibraryRootURL?.standardizedFileURL, library.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: courseRoot.appendingPathComponent(".weibei/course.json").path))
    }

    func testMigrateLibraryAdoptsExistingLibrary() throws {
        let base = makeTempRoot("weibei-migration-adopt")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("原资料库", isDirectory: true)
        let store = try makeStore(
            workspace: base.appendingPathComponent("workspace", isDirectory: true),
            library: library
        )
        let existingLibrary = base.appendingPathComponent("已有资料库", isDirectory: true)
        try FileManager.default.createDirectory(
            at: existingLibrary.appendingPathComponent(".weibei", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manifest = CourseProjectManifest(courseID: UUID())
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: existingLibrary.appendingPathComponent(".weibei/course.json"))

        do {
            _ = try migrate(store, to: existingLibrary)
            XCTFail("合法库目标应改走认领而非迁移")
        } catch let error as CourseProjectRootError {
            guard case .destinationIsLibrary = error else {
                return XCTFail("期望 destinationIsLibrary，实际 \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: existingLibrary.appendingPathComponent(".weibei/course.json").path
        ))
        try store.configureCourseLibrary(at: existingLibrary)
        XCTAssertEqual(store.courseLibraryRootURL?.standardizedFileURL, existingLibrary.standardizedFileURL)
    }

    func testMigrateLibraryFailureKeepsOriginal() throws {
        let base = makeTempRoot("weibei-migration-failure")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: base.path)
            try? FileManager.default.removeItem(at: base)
        }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(
            workspace: base.appendingPathComponent("workspace", isDirectory: true),
            library: library
        )
        let courseID = try store.createCourseInLibrary(title: "保留课")
        let lockedParent = base.appendingPathComponent("只读父目录", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedParent, withIntermediateDirectories: true)
        let destination = lockedParent.appendingPathComponent("目标", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedParent.path)

        do {
            _ = try migrate(store, to: destination)
            XCTFail("只读目标应导致迁移失败")
        } catch let error as CourseProjectRootError {
            guard case .migrationFailed = error else {
                return XCTFail("期望 migrationFailed，实际 \(error)")
            }
        }
        XCTAssertFalse(store.libraryMigrationInFlight)
        let courseRoot = try XCTUnwrap(store.courseRootURL(for: courseID))
        XCTAssertEqual(store.courseManifestCourseID(at: courseRoot), courseID)
        XCTAssertEqual(store.courseLibraryRootURL?.standardizedFileURL, library.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: courseRoot.appendingPathComponent(".weibei/course.json").path))
    }

    func testMigrateLibrarySuspendsAndResumesServices() throws {
        let base = makeTempRoot("weibei-migration-suspend")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(
            workspace: base.appendingPathComponent("workspace", isDirectory: true),
            library: library
        )
        let courseID = try store.createCourseInLibrary(title: "挂起课")
        let source = base.appendingPathComponent("笔记.md")
        try "原始内容".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let backingURL = try XCTUnwrap(store.resolvedLibraryURL(for: item))

        let commonNotes = library.appendingPathComponent("通用笔记", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: commonNotes.path))

        store.libraryMigrationInFlight = true
        store.scheduleNotePersistence("迁移期间的新内容", for: item)
        store.flushPendingNotePersistence(for: item.id)
        XCTAssertEqual(try String(contentsOf: backingURL, encoding: .utf8), "原始内容")
        try? FileManager.default.removeItem(at: commonNotes)
        try reconcile(store)
        XCTAssertFalse(FileManager.default.fileExists(atPath: commonNotes.path))

        store.libraryMigrationInFlight = false
        store.flushPendingNotePersistence(for: item.id)
        XCTAssertEqual(try String(contentsOf: backingURL, encoding: .utf8), "迁移期间的新内容")
        try reconcile(store)
        XCTAssertTrue(FileManager.default.fileExists(atPath: commonNotes.path))
    }
}
