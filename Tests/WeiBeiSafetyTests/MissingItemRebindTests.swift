import Darwin
import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class MissingItemRebindTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    func testRebindUpdatesSameItemAndSurvivesReload() async throws {
        let fixture = try Fixture(name: "rebind-success")
        defer { fixture.remove() }

        let original = fixture.root.appendingPathComponent("old.md")
        let replacement = fixture.root.appendingPathComponent("new.md")
        try Data("# old\n".utf8).write(to: original)
        try Data("# old\n".utf8).write(to: replacement)
        let identity = try XCTUnwrap(statIdentity(original))
        let itemID = "imported:rebind-success"
        try fixture.write(
            PersistedWorkspace(
                importedItems: [
                    StudyItem(
                        id: itemID,
                        title: "old",
                        subtitle: "old.md",
                        kind: .markdown,
                        urlPath: nil,
                        importedFileIdentity: identity,
                        importedFileLastKnownPath: original.path,
                        isSample: false,
                        isNotebookNote: true
                    ),
                ],
                notesByItemID: [itemID: "# old\n"],
                activeNotebookItemID: itemID
            )
        )
        try FileManager.default.removeItem(at: original)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        let item = try XCTUnwrap(store.importedItems.first(where: { $0.id == itemID }))
        XCTAssertTrue(store.isImportedSourceMissing(item))

        try await store.rebindMissingImportedItem(id: itemID, to: replacement)
        let rebound = try XCTUnwrap(store.importedItems.first(where: { $0.id == itemID }))
        XCTAssertEqual(store.importedItems.filter { $0.id == itemID }.count, 1)
        XCTAssertEqual(rebound.urlPath, replacement.path)
        XCTAssertEqual(rebound.importedFileLastKnownPath, replacement.path)
        XCTAssertNotNil(rebound.importedFileIdentity)
        XCTAssertNotNil(rebound.importedFileBookmarkData)
        XCTAssertFalse(store.isImportedSourceMissing(rebound))

        let reloaded = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        let persisted = try XCTUnwrap(reloaded.importedItems.first(where: { $0.id == itemID }))
        XCTAssertEqual(reloaded.importedItems.filter { $0.id == itemID }.count, 1)
        XCTAssertEqual(persisted.urlPath, replacement.path)
        XCTAssertFalse(reloaded.isImportedSourceMissing(persisted))
    }

    @MainActor
    func testFailedSaveLeavesMissingItemUnchanged() async throws {
        let fixture = try Fixture(name: "rebind-save-fail")
        defer { fixture.remove() }

        let original = fixture.root.appendingPathComponent("old.md")
        let replacement = fixture.root.appendingPathComponent("new.md")
        try Data("# old\n".utf8).write(to: original)
        try Data("# old\n".utf8).write(to: replacement)
        let identity = try XCTUnwrap(statIdentity(original))
        let itemID = "imported:rebind-save-fail"
        try fixture.write(
            PersistedWorkspace(
                importedItems: [
                    StudyItem(
                        id: itemID,
                        title: "old",
                        subtitle: "old.md",
                        kind: .markdown,
                        urlPath: nil,
                        importedFileIdentity: identity,
                        importedFileLastKnownPath: original.path,
                        isSample: false,
                        isNotebookNote: true
                    ),
                ],
                notesByItemID: [itemID: "# old\n"]
            )
        )
        try FileManager.default.removeItem(at: original)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            workspaceSnapshotWriter: { _, _ in
                throw NSError(
                    domain: "WeiBei.MissingItemRebindTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "forced save failure"]
                )
            },
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        let before = try XCTUnwrap(store.importedItems.first(where: { $0.id == itemID }))
        do {
            try await store.rebindMissingImportedItem(id: itemID, to: replacement)
            XCTFail("rebind should fail when workspace save fails")
        } catch MissingItemRebindError.workspaceSaveFailed {
            let after = try XCTUnwrap(store.importedItems.first(where: { $0.id == itemID }))
            XCTAssertEqual(after, before)
            XCTAssertNil(after.urlPath)
            XCTAssertEqual(after.importedFileLastKnownPath, original.path)
            XCTAssertTrue(store.isImportedSourceMissing(after))
        }
    }

    private func statIdentity(_ url: URL) -> ImportedFileIdentity? {
        var fileStat = Darwin.stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return Darwin.lstat(path, &fileStat) == 0
        }) else { return nil }
        return ImportedFileIdentity(
            volumeID: UInt64(fileStat.st_dev),
            fileID: UInt64(fileStat.st_ino),
            birthTimeSeconds: Int64(fileStat.st_birthtimespec.tv_sec),
            birthTimeNanoseconds: Int64(fileStat.st_birthtimespec.tv_nsec)
        )
    }

    private struct Fixture {
        let root: URL
        let workspaceDirectory: URL

        init(name: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "weibei-missing-rebind-\(name)-\(UUID().uuidString)",
                    isDirectory: true
                )
            workspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workspaceDirectory,
                withIntermediateDirectories: true
            )
        }

        func write(_ snapshot: PersistedWorkspace) throws {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(
                to: workspaceDirectory.appendingPathComponent("workspace.json"),
                options: [.atomic]
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
