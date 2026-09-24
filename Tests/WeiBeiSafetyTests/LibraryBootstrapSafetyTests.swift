import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

/// 资料库不被静默改绑（审查 L1/L10）：
/// - 已配置的原库暂时连不上时，启动/导入都不得新建默认库、不得改写
///   path/identity/bookmark；
/// - 原库恢复后按既有重连流程接回；
/// - 全新安装（从未配置）仍会自动建默认库，且默认库在主目录而非
///   iCloud 常接管的「文稿」。
@MainActor
final class LibraryBootstrapSafetyTests: XCTestCase {
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

    /// 让 `CourseLibraryLayout.defaultRootURL()` 落在测试沙盒里：
    /// bootstrap 直接读该环境变量，测试必须绝不触碰真实主目录。
    private func withIsolatedWorkspaceOverride<T>(
        _ override: URL,
        _ body: () throws -> T
    ) rethrows -> T {
        let previous = ProcessInfo.processInfo.environment["WEIBEI_WORKSPACE_DIR"] ?? ""
        setenv("WEIBEI_WORKSPACE_DIR", override.path, 1)
        defer {
            if previous.isEmpty {
                unsetenv("WEIBEI_WORKSPACE_DIR")
            } else {
                setenv("WEIBEI_WORKSPACE_DIR", previous, 1)
            }
        }
        return try body()
    }

    private func makeStore(
        workspace: URL,
        bookmarkResolver: @escaping (Data) -> CourseProjectResolvedBookmark? = LibraryBootstrapSafetyTests.resolvePathBookmark
    ) throws -> WorkspaceStore {
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return WorkspaceStore(
            workspaceDirectory: workspace,
            courseRootBookmarkMaker: { Data($0.standardizedFileURL.path.utf8) },
            courseRootBookmarkResolver: bookmarkResolver,
            courseSecurityScopeStarter: { _ in true },
            courseSecurityScopeStopper: { _ in },
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
    }

    /// 与真实书签行为对齐的解析器：目标还在就能解析，拔盘/改名后解析失败。
    private nonisolated static func resolvePathBookmark(_ data: Data) -> CourseProjectResolvedBookmark? {
        guard let path = String(data: data, encoding: .utf8),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return CourseProjectResolvedBookmark(
            url: URL(fileURLWithPath: path),
            isStale: false
        )
    }

    func testDefaultLibraryRootLivesInHomeDirectoryNotDocuments() {
        let root = CourseLibraryLayout.defaultRootURL(workspaceDirectory: nil)
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(
            root.standardizedFileURL,
            home.appendingPathComponent(CourseLibraryLayout.defaultFolderName, isDirectory: true)
                .standardizedFileURL,
            "默认资料库应位于主目录下"
        )
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        XCTAssertFalse(
            root.standardizedFileURL.path.hasPrefix(documents.standardizedFileURL.path + "/"),
            "默认资料库不能再放进 iCloud 常接管的「文稿」目录：\(root.path)"
        )
    }

    func testFreshInstallStillBootstrapsDefaultLibraryAutomatically() throws {
        let base = makeTempRoot("weibei-fresh-install")
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        let isolatedDefaultRoot = CourseLibraryLayout.defaultRootURL(
            workspaceDirectory: workspace.path
        )

        let store = try withIsolatedWorkspaceOverride(workspace) {
            try makeStore(workspace: workspace)
        }
        XCTAssertNil(store.courseLibraryRootPath, "测试起点必须是从未配置过资料库")
        XCTAssertNil(store.courseLibraryRootURL)

        withIsolatedWorkspaceOverride(workspace) {
            store.bootstrapDefaultLibraryIfNeeded()
        }

        XCTAssertEqual(
            store.courseLibraryRootURL?.standardizedFileURL,
            isolatedDefaultRoot.standardizedFileURL,
            "全新安装必须仍然自动建立并绑定默认资料库"
        )
        for directoryName in [
            CourseLibraryLayout.commonMaterialsDirectoryName,
            CourseLibraryLayout.commonNotesDirectoryName,
        ] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: isolatedDefaultRoot.appendingPathComponent(directoryName, isDirectory: true).path
                ),
                "默认库缺少 \(directoryName)"
            )
        }
    }

    func testTemporarilyMissingLibraryIsNotReboundAndReconnectsWhenBack() throws {
        let base = makeTempRoot("weibei-missing-library")
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("workspace", isDirectory: true)
        let library = base.appendingPathComponent("外置盘资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let hiddenElsewhere = base.appendingPathComponent("藏起来的资料库", isDirectory: true)

        // 第一次安装：绑定资料库并落盘。
        let store = try makeStore(workspace: workspace)
        try store.configureCourseLibrary(at: library)
        let configuredPath = store.courseLibraryRootPath
        let configuredIdentity = store.courseLibraryRootIdentity
        let configuredBookmark = store.courseLibraryRootBookmarkData
        XCTAssertEqual(configuredPath, library.standardizedFileURL.path)

        // 原库暂时消失（外置盘拔掉 / 目录改名）：书签解析失败、路径也不在场。
        try FileManager.default.moveItem(at: library, to: hiddenElsewhere)
        let isolatedDefaultRoot = CourseLibraryLayout.defaultRootURL(
            workspaceDirectory: workspace.path
        )
        let reopened = try withIsolatedWorkspaceOverride(workspace) {
            try makeStore(workspace: workspace)
        }
        XCTAssertNil(reopened.courseLibraryRootURL, "原库连不上时不应绑定任何库")
        XCTAssertNotNil(
            reopened.courseLibraryUnavailableReason,
            "原库连不上时必须呈现「不可用」而不是装作没有资料库"
        )

        // 导入入口同样不得借机新建默认库或改绑。
        let source = base.appendingPathComponent("讲义.md")
        try "正文".write(to: source, atomically: true, encoding: .utf8)
        let imported = withIsolatedWorkspaceOverride(workspace) {
            importFilesAndWait(reopened, [source])
        }
        XCTAssertTrue(imported.isEmpty, "库不可用时导入应失败而不是写进别的库")
        XCTAssertEqual(reopened.courseLibraryRootPath, configuredPath, "原库路径被改写")
        XCTAssertEqual(reopened.courseLibraryRootIdentity, configuredIdentity, "原库身份被改写")
        XCTAssertEqual(reopened.courseLibraryRootBookmarkData, configuredBookmark, "原库书签被改写")
        XCTAssertNil(reopened.courseLibraryRootURL)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: isolatedDefaultRoot.path),
            "原库暂时不可用时不得静默新建默认库"
        )
        XCTAssertNotNil(reopened.importantOperationError, "导入失败必须如实可见")

        // 原库恢复：走既有重连流程接回，不需要重新选库。
        try FileManager.default.moveItem(at: hiddenElsewhere, to: library)
        let reconnected = reopened.restoreCourseProjectRoots()
        XCTAssertTrue(reconnected, "原库回来后应能自动重连")
        XCTAssertEqual(
            reopened.courseLibraryRootURL?.standardizedFileURL,
            library.standardizedFileURL
        )
        XCTAssertNil(reopened.courseLibraryUnavailableReason)
    }
}
