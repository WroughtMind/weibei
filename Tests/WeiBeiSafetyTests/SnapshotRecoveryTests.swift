import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

@MainActor
final class SnapshotRecoveryTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    private func makeTempWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-snapshot-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { [weak self] in
            _ = self
            try? FileManager.default.removeItem(at: root)
        }
        return root
    }

    private func primaryURL(_ dir: URL) -> URL {
        dir.appendingPathComponent("workspace.json")
    }

    /// 与 PersistedWorkspace 解码兼容的最小合法快照；extra 用于集成断言字段。
    private func minimalSnapshotJSON(agentBaseURL: String? = nil) -> Data {
        let extra = agentBaseURL.map { ",\"agentBaseURL\":\"\($0)\"" } ?? ""
        return Data(
            ("{\"importedItems\":[],\"notesByItemID\":{}" + extra + "}").utf8
        )
    }

    func testRotationKeepsThreeGenerationsInOrder() throws {
        let dir = try makeTempWorkspace()
        let primary = primaryURL(dir)
        let fm = FileManager.default

        // 生产时序：先旋转备份链，再写新主档。
        for content in ["A", "B", "C", "D", "E"] {
            WorkspaceSnapshotRecovery.rotateBackups(primary: primary)
            try Data(content.utf8).write(to: primary, options: .atomic)
        }

        let generation = { (n: Int) -> String in
            let url = WorkspaceSnapshotRecovery.backupURL(generation: n, primary: primary)
            return String(data: try! Data(contentsOf: url), encoding: .utf8)!
        }
        XCTAssertEqual(
            String(data: try Data(contentsOf: primary), encoding: .utf8), "E"
        )
        XCTAssertEqual(generation(1), "D")
        XCTAssertEqual(generation(2), "C")
        XCTAssertEqual(generation(3), "B")
        XCTAssertFalse(
            fm.fileExists(
                atPath: WorkspaceSnapshotRecovery.backupURL(generation: 4, primary: primary).path
            )
        )
    }

    func testCorruptPrimaryQuarantinesAndRestoresNewestBackup() throws {
        let dir = try makeTempWorkspace()
        let primary = primaryURL(dir)
        try Data("not json at all".utf8).write(to: primary, options: .atomic)
        let older = WorkspaceSnapshotRecovery.backupURL(generation: 2, primary: primary)
        try minimalSnapshotJSON().write(to: older, options: .atomic)
        let newer = WorkspaceSnapshotRecovery.backupURL(generation: 1, primary: primary)
        try minimalSnapshotJSON().write(to: newer, options: .atomic)

        let result = WorkspaceSnapshotRecovery.bestAvailable(primary: primary)

        guard case .restoredFromBackup = result.notice else {
            return XCTFail("expected restoredFromBackup, got \(String(describing: result.notice))")
        }
        XCTAssertNotNil(result.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("workspace.corrupt-") })
    }

    func testUnrecoverableQuarantinesAndReports() throws {
        let dir = try makeTempWorkspace()
        let primary = primaryURL(dir)
        try Data("still not json".utf8).write(to: primary, options: .atomic)

        let result = WorkspaceSnapshotRecovery.bestAvailable(primary: primary)

        guard case .unrecoverable = result.notice else {
            return XCTFail("expected unrecoverable, got \(String(describing: result.notice))")
        }
        XCTAssertNil(result.data)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("workspace.corrupt-") })
    }

    func testFreshWorkspaceIsNotAnIncident() throws {
        let dir = try makeTempWorkspace()
        let result = WorkspaceSnapshotRecovery.bestAvailable(primary: primaryURL(dir))
        XCTAssertNil(result.data)
        XCTAssertNil(result.notice)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty
        )
    }

    func testStoreLoadsFromBackupWhenPrimaryCorrupt() throws {
        let dir = try makeTempWorkspace()
        try Data("{ broken primary".utf8).write(to: primaryURL(dir), options: .atomic)
        try minimalSnapshotJSON(agentBaseURL: "https://recovery.example")
            .write(
                to: WorkspaceSnapshotRecovery.backupURL(generation: 1, primary: primaryURL(dir)),
                options: .atomic
            )

        let store = WorkspaceStore(
            workspaceDirectory: dir,
            courseRootBookmarkMaker: { _ in nil },
            courseRootBookmarkResolver: { _ in nil }
        )

        XCTAssertEqual(store.agentBaseURL, "https://recovery.example")
        XCTAssertTrue(store.importantOperationError?.contains("备份") == true)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("workspace.corrupt-") })
    }
}
