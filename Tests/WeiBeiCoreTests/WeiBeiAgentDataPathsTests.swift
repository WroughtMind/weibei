import Foundation
import XCTest
@testable import WeiBeiCore

final class WeiBeiAgentDataPathsTests: XCTestCase {
    /**
     * Verifies that application-owned paths remain beneath the supplied container root.
     */
    func testApplicationSupportRootUsesOwnedContainer() {
        let base = URL(fileURLWithPath: "/tmp/managed-container", isDirectory: true)

        let root = WeiBeiAgentDataPaths.applicationSupportRoot(baseDirectory: base)

        XCTAssertEqual(root.path, "/tmp/managed-container/com.changfenhuang.weibei")
    }

    /**
     * Verifies one-time auth migration, private permissions, and destination preservation.
     */
    func testPiAuthMigrationCopiesOnceWithoutOverwritingDestination() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("weibei-agent-paths-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("home/.pi/agent/auth.json")
        let destination = root.appendingPathComponent("app/PiAgent/auth.json")
        try fileManager.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"token":"first"}"#.utf8).write(to: source)

        WeiBeiAgentDataPaths.migratePiAuthIfNeeded(
            source: source,
            destination: destination,
            fileManager: fileManager
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data(#"{"token":"first"}"#.utf8))
        let directoryAttributes = try fileManager.attributesOfItem(atPath: destination.deletingLastPathComponent().path)
        let fileAttributes = try fileManager.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        try Data(#"{"token":"second"}"#.utf8).write(to: source)
        WeiBeiAgentDataPaths.migratePiAuthIfNeeded(
            source: source,
            destination: destination,
            fileManager: fileManager
        )
        XCTAssertEqual(try Data(contentsOf: destination), Data(#"{"token":"first"}"#.utf8))
    }

    /**
     * Verifies that empty and oversized credential inputs cannot enter the private store.
     */
    func testPiAuthMigrationRejectsInvalidInputSizes() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("weibei-agent-path-limits-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.json")
        let destination = root.appendingPathComponent("private/auth.json")

        try Data("{}".utf8).write(to: source)
        WeiBeiAgentDataPaths.migratePiAuthIfNeeded(source: source, destination: destination, fileManager: fileManager)
        XCTAssertFalse(fileManager.fileExists(atPath: destination.path))

        try Data(repeating: 0x41, count: 1_048_577).write(to: source)
        WeiBeiAgentDataPaths.migratePiAuthIfNeeded(source: source, destination: destination, fileManager: fileManager)
        XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
    }
}
