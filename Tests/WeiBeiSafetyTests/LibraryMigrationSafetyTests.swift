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

    private func makeStore(
        workspace: URL,
        library: URL,
        workspaceSnapshotWriter: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            WorkspaceSnapshotRecovery.rotateBackups(primary: url)
            try data.write(to: url, options: .atomic)
        }
    ) throws -> WorkspaceStore {
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
            workspaceSnapshotWriter: workspaceSnapshotWriter,
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

    func testMigrateLibraryRejectsNestedAndLibraryItself() throws {
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
        // 所选文件夹的「魏碑资料库」子位置已经是另一个资料库时，同样拒绝。
        let withNestedLibrary = base.appendingPathComponent("内含资料库", isDirectory: true)
        let nestedLibrary = withNestedLibrary.appendingPathComponent(
            CourseLibraryLayout.defaultFolderName, isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: nestedLibrary.appendingPathComponent(".weibei", isDirectory: true),
            withIntermediateDirectories: true
        )
        let manifestData = try JSONEncoder().encode(CourseProjectManifest(courseID: UUID()))
        try manifestData.write(
            to: nestedLibrary.appendingPathComponent(".weibei/course.json")
        )
        do {
            _ = try migrate(store, to: withNestedLibrary)
            XCTFail("目标下的魏碑资料库子目录已是资料库时应被拒绝")
        } catch let error as CourseProjectRootError {
            guard case .destinationIsLibrary = error else {
                return XCTFail("期望 destinationIsLibrary，实际 \(error)")
            }
        }

        let courseRoot = try XCTUnwrap(store.courseRootURL(for: courseID))
        XCTAssertEqual(store.courseManifestCourseID(at: courseRoot), courseID)
        XCTAssertEqual(store.courseLibraryRootURL?.standardizedFileURL, library.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: courseRoot.appendingPathComponent(".weibei/course.json").path))
    }

    /// 审查 L2：用户几乎选不到空文件夹。非空、又不是资料库的所选文件夹，
    /// 迁移目标改为「所选文件夹/魏碑资料库」子目录，原有内容一律不动。
    func testMigrateLibraryIntoNonEmptyFolderCreatesWeiBeiSubdirectory() throws {
        let base = makeTempRoot("weibei-migration-nonempty")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(
            workspace: base.appendingPathComponent("workspace", isDirectory: true),
            library: library
        )
        let courseID = try store.createCourseInLibrary(title: "课程乙")

        let nonEmpty = base.appendingPathComponent("非空目录", isDirectory: true)
        try FileManager.default.createDirectory(at: nonEmpty, withIntermediateDirectories: true)
        let bystander = nonEmpty.appendingPathComponent("其他文件.txt")
        try "别人的文件，不许动".write(to: bystander, atomically: true, encoding: .utf8)

        let result = try migrate(store, to: nonEmpty)
        let expectedDestination = nonEmpty.appendingPathComponent(
            CourseLibraryLayout.defaultFolderName, isDirectory: true
        )
        XCTAssertEqual(
            result.destination.standardizedFileURL,
            expectedDestination.standardizedFileURL,
            "非空非库目标应迁入其下的魏碑资料库子目录"
        )
        XCTAssertEqual(
            store.courseLibraryRootURL?.standardizedFileURL,
            expectedDestination.standardizedFileURL
        )
        // 原有内容原样留在所选文件夹里。
        XCTAssertEqual(try String(contentsOf: bystander, encoding: .utf8), "别人的文件，不许动")
        // 课程跟到了新库位置。
        let courseRoot = try XCTUnwrap(store.courseRootURL(for: courseID))
        XCTAssertTrue(courseRoot.path.hasPrefix(expectedDestination.path))
        XCTAssertEqual(store.courseManifestCourseID(at: courseRoot), courseID)
        // 旧库位置已腾空。
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: library.path)) ?? []
        XCTAssertTrue(leftover.isEmpty, "旧库目录残留：\(leftover)")
    }

    /// 审查 L2：只含 `.DS_Store` 的文件夹按「空」处理，直接迁入，不再报非空。
    func testMigrateLibraryTreatsHiddenOnlyFolderAsEmpty() throws {
        let base = makeTempRoot("weibei-migration-dsstore")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(
            workspace: base.appendingPathComponent("workspace", isDirectory: true),
            library: library
        )
        _ = try store.createCourseInLibrary(title: "课程丙")

        let hiddenOnly = base.appendingPathComponent("只有隐藏文件", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenOnly, withIntermediateDirectories: true)
        try Data("junk".utf8).write(to: hiddenOnly.appendingPathComponent(".DS_Store"))

        let result = try migrate(store, to: hiddenOnly)
        XCTAssertEqual(
            result.destination.standardizedFileURL,
            hiddenOnly.standardizedFileURL,
            "只有隐藏文件的文件夹应视为空，直接作为迁移目标"
        )
        XCTAssertEqual(
            store.courseLibraryRootURL?.standardizedFileURL,
            hiddenOnly.standardizedFileURL
        )
    }

    /// 所选文件夹的「魏碑资料库」子目录已有别的可见内容时，仍报非空。
    func testMigrateLibraryRejectsOccupiedNestedSubdirectory() throws {
        let base = makeTempRoot("weibei-migration-occupied-nested")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(
            workspace: base.appendingPathComponent("workspace", isDirectory: true),
            library: library
        )
        _ = try store.createCourseInLibrary(title: "课程丁")

        let selected = base.appendingPathComponent("目标", isDirectory: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        try "占位".write(to: selected.appendingPathComponent("已有内容.txt"), atomically: true, encoding: .utf8)
        let nested = selected.appendingPathComponent(
            CourseLibraryLayout.defaultFolderName, isDirectory: true
        )
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "不许覆盖".write(to: nested.appendingPathComponent("重要文件.md"), atomically: true, encoding: .utf8)

        do {
            _ = try migrate(store, to: selected)
            XCTFail("子目录已有可见内容时应报非空")
        } catch let error as CourseProjectRootError {
            guard case .destinationNotEmpty = error else {
                return XCTFail("期望 destinationNotEmpty，实际 \(error)")
            }
        }
        XCTAssertEqual(
            try String(contentsOf: nested.appendingPathComponent("重要文件.md"), encoding: .utf8),
            "不许覆盖"
        )
        XCTAssertEqual(
            store.courseLibraryRootURL?.standardizedFileURL,
            library.standardizedFileURL,
            "失败后必须仍绑定原库"
        )
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

    func testMigrateLibrarySaveFailureRestoresOriginal() throws {
        struct InjectedFailure: Error {}

        let base = makeTempRoot("weibei-migration-save-failure")
        defer { try? FileManager.default.removeItem(at: base) }
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let destination = base.appendingPathComponent("目标", isDirectory: true)
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        let store = try makeStore(
            workspace: workspace,
            library: library,
            workspaceSnapshotWriter: { data, url in
                let snapshot = try JSONDecoder().decode(PersistedWorkspace.self, from: data)
                if snapshot.courseLibraryRootPath == destination.path {
                    throw InjectedFailure()
                }
                WorkspaceSnapshotRecovery.rotateBackups(primary: url)
                try data.write(to: url, options: .atomic)
            }
        )
        let courseID = try store.createCourseInLibrary(title: "保留课")

        do {
            _ = try migrate(store, to: destination)
            XCTFail("新绑定保存失败时迁移不应返回成功")
        } catch let error as CourseProjectRootError {
            guard case .workspaceSaveFailed = error else {
                return XCTFail("期望 workspaceSaveFailed，实际 \(error)")
            }
        }

        XCTAssertEqual(store.courseLibraryRootURL?.standardizedFileURL, library.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let courseRoot = try XCTUnwrap(store.courseRootURL(for: courseID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: courseRoot.appendingPathComponent(".weibei/course.json").path))
        let reopened = WorkspaceStore(
            workspaceDirectory: workspace,
            courseRootBookmarkResolver: { data in
                String(data: data, encoding: .utf8).map {
                    CourseProjectResolvedBookmark(
                        url: URL(fileURLWithPath: $0),
                        isStale: false
                    )
                }
            },
            courseSecurityScopeStarter: { _ in true },
            courseSecurityScopeStopper: { _ in },
            startsCourseFileMaintenance: false
        )
        XCTAssertEqual(reopened.courseLibraryRootURL?.standardizedFileURL, library.standardizedFileURL)
        let reopenedCourseRoot = try XCTUnwrap(reopened.courseRootURL(for: courseID))
        XCTAssertTrue(FileManager.default.fileExists(atPath: reopenedCourseRoot.appendingPathComponent(".weibei/course.json").path))
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
