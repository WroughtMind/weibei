import Darwin
import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class GoneImportedItemTests: XCTestCase {
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
    func testUnreadableExistingFileKeepsRegistrationDraftAndRelations() throws {
        let fixture = try Fixture(name: "unreadable-keeps")
        defer {
            if let path = fixture.protectedFilePath {
                _ = chmod(path, 0o644)
            }
            fixture.remove()
        }

        let original = fixture.root.appendingPathComponent("locked.md")
        let draft = "# locked\n\nkeep this draft"
        try Data(draft.utf8).write(to: original)
        let identity = try XCTUnwrap(statIdentity(original))
        let itemID = "imported:unreadable-keeps"
        let sourceID = "imported:unreadable-source"
        try fixture.write(
            PersistedWorkspace(
                importedItems: [
                    StudyItem(
                        id: sourceID,
                        title: "source",
                        subtitle: "source.txt",
                        kind: .text,
                        urlPath: fixture.root.appendingPathComponent("source.txt").path,
                        isSample: false
                    ),
                    StudyItem(
                        id: itemID,
                        title: "locked",
                        subtitle: "locked.md",
                        kind: .markdown,
                        urlPath: original.path,
                        importedFileIdentity: identity,
                        importedFileLastKnownPath: original.path,
                        isSample: false,
                        isNotebookNote: true
                    ),
                ],
                notesByItemID: [itemID: draft],
                activeNotebookItemID: itemID,
                noteSourceLinks: [
                    NoteSourceLink(noteItemID: itemID, sourceItemID: sourceID),
                ],
                noteSourceLinksMigrationVersion: 1
            )
        )
        fixture.protectedFilePath = original.path
        XCTAssertEqual(chmod(original.path, 0o000), 0)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        let kept = try XCTUnwrap(store.importedItems.first(where: { $0.id == itemID }))
        XCTAssertEqual(store.importedItems.first(where: { $0.id == sourceID })?.id, sourceID)
        XCTAssertTrue(
            store.noteSourceLinks.contains {
                $0.noteItemID == itemID && $0.sourceItemID == sourceID
            }
        )
        XCTAssertEqual(store.notesByItemID[itemID], draft)
        XCTAssertFalse(kept.isSample)
    }

    @MainActor
    func testMissingParentDirectoryKeepsLegacyRegistration() throws {
        let fixture = try Fixture(name: "missing-parent")
        defer { fixture.remove() }

        let parent = fixture.root.appendingPathComponent("vanished", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let original = parent.appendingPathComponent("note.md")
        try Data("# note\n".utf8).write(to: original)
        let identity = try XCTUnwrap(statIdentity(original))
        let itemID = "imported:missing-parent"
        try fixture.write(
            PersistedWorkspace(
                importedItems: [
                    StudyItem(
                        id: itemID,
                        title: "note",
                        subtitle: "note.md",
                        kind: .markdown,
                        urlPath: original.path,
                        importedFileIdentity: identity,
                        importedFileLastKnownPath: original.path,
                        isSample: false,
                        isNotebookNote: true
                    ),
                ],
                notesByItemID: [itemID: "# note\n"]
            )
        )
        try FileManager.default.removeItem(at: parent)

        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            startsAtBlankEntries: false,
            startsCourseFileMaintenance: false
        )
        XCTAssertNotNil(store.importedItems.first(where: { $0.id == itemID }))
    }

    @MainActor
    func testSampleItemIsNeverForgotten() throws {
        XCTAssertFalse(
            ImportedFileRecovery.shouldForgetGoneSource(
                file: .absent,
                parent: .present,
                isSample: true
            )
        )
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
                notesByItemID: [itemID: "# owned\n"],
                courses: [
                    Course(
                        id: courseID,
                        title: "丢失文件夹的课",
                        sourceRootRelativePath: "已经不在的课程文件夹"
                    ),
                ]
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
        var protectedFilePath: String?

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
