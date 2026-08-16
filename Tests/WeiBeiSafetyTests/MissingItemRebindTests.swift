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
    func testGoneIndependentFileDropsRegistrationAndLeavesOtherFiles() throws {
        let fixture = try Fixture(name: "gone-independent")
        defer { fixture.remove() }

        let original = fixture.root.appendingPathComponent("old.md")
        let neighbor = fixture.root.appendingPathComponent("keep.md")
        try Data("# old\n".utf8).write(to: original)
        try Data("# keep\n".utf8).write(to: neighbor)
        let identity = try XCTUnwrap(statIdentity(original))
        let itemID = "imported:gone-independent"
        try fixture.write(
            PersistedWorkspace(
                importedItems: [
                    StudyItem(
                        id: itemID,
                        title: "old",
                        subtitle: "old.md",
                        kind: .markdown,
                        urlPath: original.path,
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
        XCTAssertNil(store.importedItems.first(where: { $0.id == itemID }))
        XCTAssertEqual(try Data(contentsOf: neighbor), Data("# keep\n".utf8))

        let reloaded = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        XCTAssertNil(reloaded.importedItems.first(where: { $0.id == itemID }))
        XCTAssertEqual(try Data(contentsOf: neighbor), Data("# keep\n".utf8))
    }

    @MainActor
    func testGoneCourseOwnedFileStaysWhenCourseFolderIsUnavailable() throws {
        let fixture = try Fixture(name: "gone-owned-no-root")
        defer { fixture.remove() }

        let original = fixture.root.appendingPathComponent("owned.md")
        try Data("# owned\n".utf8).write(to: original)
        let identity = try XCTUnwrap(statIdentity(original))
        let courseID = UUID()
        let itemID = "imported:gone-owned-no-root"
        try fixture.write(
            PersistedWorkspace(
                importedItems: [
                    StudyItem(
                        id: itemID,
                        title: "owned",
                        subtitle: "owned.md",
                        kind: .markdown,
                        urlPath: original.path,
                        importedFileIdentity: identity,
                        importedFileLastKnownPath: original.path,
                        isSample: false,
                        isNotebookNote: true,
                        storage: .courseOwned(ownerCourseID: courseID)
                    ),
                ],
                courses: [
                    Course(
                        id: courseID,
                        title: "丢失文件夹的课",
                        sourceRootRelativePath: "已经不在的课程文件夹"
                    ),
                ],
                notesByItemID: [itemID: "# owned\n"]
            )
        )
        try FileManager.default.removeItem(at: original)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        XCTAssertNotNil(store.importedItems.first(where: { $0.id == itemID }))
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
                    "weibei-gone-file-\(name)-\(UUID().uuidString)",
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
