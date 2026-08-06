import Darwin
import XCTest
@testable import WeiBei

final class WorkspaceSafetyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testImportedFileIdentitySafety() async throws {
        try await MainActor.run {
            try ImportedIdentitySelfCheck.run()
        }
    }

    func testCourseProjectDataSafety() async throws {
        try await MainActor.run {
            try CourseProjectRootSelfCheck.run()
        }
    }

    func testBackgroundWorkspacePersistence() async throws {
        try await MainActor.run {
            try CourseProjectRootSelfCheck.runBackgroundWorkspacePersistenceOnly()
        }
    }
}
