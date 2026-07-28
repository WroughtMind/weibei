import Foundation
import XCTest
@testable import WeiBeiDevCore

final class RepositoryLayoutTests: XCTestCase {
    /// Accepts a directory only when all repository root markers are present.
    func testLocateAcceptsRepositoryRoot() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("Package.swift"))
        try Data().write(to: root.appendingPathComponent("VERSION"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources/WeiBei"),
            withIntermediateDirectories: true
        )

        let layout = try RepositoryLayout.locate(currentDirectory: root)

        XCTAssertEqual(layout.rootDirectory, root.resolvingSymlinksInPath())
        XCTAssertEqual(layout.packageLock.lastPathComponent, "package-lock.json")
    }

    /// Rejects a subdirectory instead of walking upward to discover the root.
    func testLocateRejectsRepositorySubdirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("Package.swift"))
        try Data().write(to: root.appendingPathComponent("VERSION"))
        let sourceDirectory = root.appendingPathComponent("Sources/WeiBei")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        XCTAssertThrowsError(try RepositoryLayout.locate(currentDirectory: sourceDirectory)) { error in
            XCTAssertEqual((error as? RepositoryLayoutError)?.errorCode, "repository_root_required")
        }
    }

    /// Creates a disposable directory owned by the current test.
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-repository-layout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
