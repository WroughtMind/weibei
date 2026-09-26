import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

final class WorkspaceStoreInitializationContractTests: XCTestCase {
    private var restoredStore: WorkspaceStore?
    private var restoredCourseID: UUID?
    private var expectedCourseRoot: URL?
    private var fixtureRoot: URL?

    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        precondition(Thread.isMainThread)
        let fixture = try MainActor.assumeIsolated {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("workspace-init-contract-\(UUID().uuidString)")
            let workspace = root.appendingPathComponent("workspace", isDirectory: true)
            let library = root.appendingPathComponent("资料库", isDirectory: true)
            try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
            var securityScopeStarts = 0

            @MainActor func makeStore() -> WorkspaceStore {
                WorkspaceStore(
                    workspaceDirectory: workspace,
                    courseRootBookmarkMaker: {
                        Data($0.standardizedFileURL.path.utf8)
                    },
                    courseRootBookmarkResolver: { data in
                        guard let path = String(data: data, encoding: .utf8),
                              FileManager.default.fileExists(atPath: path) else {
                            return nil
                        }
                        return CourseProjectResolvedBookmark(
                            url: URL(fileURLWithPath: path),
                            isStale: false
                        )
                    },
                    courseSecurityScopeStarter: { _ in
                        securityScopeStarts += 1
                        return true
                    },
                    courseSecurityScopeStopper: { _ in },
                    startsAtBlankEntries: true,
                    startsCourseFileMaintenance: false
                )
            }

            let original = makeStore()
            try original.configureCourseLibrary(at: library)
            let courseID = try original.createCourseInLibrary(title: "工作区旧标题")
            let courseRoot = try XCTUnwrap(original.courseRootURL(for: courseID))
            try original.forcePersistPortableCourseStatesForSelfCheck(
                courseIDs: [courseID]
            )
            XCTAssertTrue(original.flushPendingWorkspaceSave())

            let stateURL = courseRoot
                .appendingPathComponent(".weibei", isDirectory: true)
                .appendingPathComponent("course-state.json")
            var portableState = try JSONDecoder().decode(
                CoursePortableState.self,
                from: Data(contentsOf: stateURL)
            )
            portableState.metadata.title = "从课程状态恢复的标题"
            portableState.revision &+= 1
            portableState.savedAt = Date()
            try JSONEncoder().encode(portableState).write(to: stateURL, options: .atomic)

            let restored = makeStore()
            XCTAssertGreaterThanOrEqual(securityScopeStarts, 2)
            return (restored, courseID, courseRoot, root)
        }
        restoredStore = fixture.0
        restoredCourseID = fixture.1
        expectedCourseRoot = fixture.2
        fixtureRoot = fixture.3
    }

    override func tearDownWithError() throws {
        restoredStore = nil
        restoredCourseID = nil
        expectedCourseRoot = nil
        let root = fixtureRoot
        fixtureRoot = nil
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    @MainActor
    func testAsyncMainActorTestReceivesFullyRestoredCourseFixture() async throws {
        await Task.yield()
        let store = try XCTUnwrap(restoredStore)
        let courseID = try XCTUnwrap(restoredCourseID)
        XCTAssertEqual(
            store.courseRootURL(for: courseID)?.standardizedFileURL,
            try XCTUnwrap(expectedCourseRoot).standardizedFileURL
        )
        XCTAssertEqual(
            store.course(withID: courseID)?.title,
            "从课程状态恢复的标题"
        )
        XCTAssertNil(store.courseRootUnavailableReason(for: courseID))
        XCTAssertNil(store.importantOperationError)
    }
}
