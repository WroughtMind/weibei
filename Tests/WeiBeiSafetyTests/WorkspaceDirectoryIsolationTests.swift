import Foundation
import XCTest
@testable import WeiBeiCore
@testable import WeiBei

final class WorkspaceDirectoryIsolationTests: XCTestCase {
    func testIsolatedWorkspaceDoesNotDiscoverTheUsersDefaultLibrary() {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let isolated = CourseLibraryLayout.defaultRootURL(workspaceDirectory: workspace.path)
        let normal = CourseLibraryLayout.defaultRootURL(workspaceDirectory: nil)
        XCTAssertEqual(isolated.deletingLastPathComponent().standardizedFileURL, workspace.deletingLastPathComponent().standardizedFileURL)
        XCTAssertFalse(CourseProjectPathPolicy.overlaps(isolated, workspace))
        let candidates = CourseLibraryRootRecovery.candidates(storedPath: nil, defaultRoot: isolated, includePerUserDefault: true)
        XCTAssertEqual(candidates, [isolated.standardizedFileURL])
        XCTAssertFalse(candidates.contains(normal))
        XCTAssertEqual(CourseLibraryLayout.defaultRootURL(workspaceDirectory: " \n"), normal)
    }
}
