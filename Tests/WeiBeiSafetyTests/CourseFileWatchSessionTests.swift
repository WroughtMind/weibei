import Foundation
@testable import WeiBei
import XCTest

#if DEBUG
final class CourseFileWatchSessionTests: XCTestCase {
    func testStopDuringSourceCreationLeavesNoWatcher() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = CourseFileWatchSession(onDebouncedEvent: {})
        defer { session.stop() }
        var reachedRegistration = false
        session.beforeSourceRegistrationForSelfCheck = {
            reachedRegistration = true
            session.stop()
        }

        session.replaceDirectories([directory])

        XCTAssertTrue(reachedRegistration)
        XCTAssertEqual(session.watchedDirectoryCount, 0)
        session.replaceDirectories([directory])
        XCTAssertEqual(session.watchedDirectoryCount, 0)
        session.beforeSourceRegistrationForSelfCheck = nil
    }

    func testPauseDuringSourceCreationCanResumeWatching() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = CourseFileWatchSession(onDebouncedEvent: {})
        defer { session.stop() }
        var reachedRegistration = false
        session.beforeSourceRegistrationForSelfCheck = {
            reachedRegistration = true
            session.pause()
        }

        session.replaceDirectories([directory])

        XCTAssertTrue(reachedRegistration)
        XCTAssertTrue(session.isPaused)
        XCTAssertEqual(session.watchedDirectoryCount, 0)
        session.beforeSourceRegistrationForSelfCheck = nil
        session.resume(watching: [directory])
        XCTAssertFalse(session.isPaused)
        XCTAssertEqual(session.watchedDirectoryCount, 1)
        session.stop()
        XCTAssertEqual(session.watchedDirectoryCount, 0)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiWatchLifecycle-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
#endif
