import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

@MainActor
final class LibraryRelativeOnlyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testLibraryRelativeProductCut() throws {
        try LibraryRelativeOnlyCheck.run()
    }
}

enum LibraryRelativeOnlyCheck {
    @MainActor
    static func run() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-library-relative-only-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let library = root.appendingPathComponent("资料库", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let store = WorkspaceStore(
            workspaceDirectory: workspace,
            courseRootBookmarkMaker: { Data($0.standardizedFileURL.path.utf8) },
            courseRootBookmarkResolver: { data in
                guard let path = String(data: data, encoding: .utf8) else { return nil }
                return CourseProjectResolvedBookmark(
                    url: URL(fileURLWithPath: path),
                    isStale: false
                )
            },
            courseSecurityScopeStarter: { _ in true },
            courseSecurityScopeStopper: { _ in },
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)

        let commonMaterials = library.appendingPathComponent("通用资料", isDirectory: true)
        let commonNotes = library.appendingPathComponent("通用笔记", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: commonMaterials.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: commonNotes.path))

        let otherLibrary = root.appendingPathComponent("另一资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: otherLibrary, withIntermediateDirectories: true)
        try store.configureCourseLibrary(at: otherLibrary)
        XCTAssertEqual(store.courseLibraryRootURL?.standardizedFileURL, otherLibrary.standardizedFileURL)
        try store.configureCourseLibrary(at: library)

        let courseID = try store.createCourseInLibrary(title: "新概念")
        let courseRoot = try XCTUnwrap(store.courseRootURL(for: courseID))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: courseRoot.appendingPathComponent(".weibei/course.json").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: courseRoot.appendingPathComponent("文稿", isDirectory: true).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: courseRoot.appendingPathComponent("笔记", isDirectory: true).path
            )
        )
        let originalCourseID = courseID

        let renamed = library.appendingPathComponent("新概念英语", isDirectory: true)
        try FileManager.default.moveItem(at: courseRoot, to: renamed)
        store.discoverTopLevelCourseFolders()
        XCTAssertEqual(store.course(withID: originalCourseID)?.title, "新概念英语")
        XCTAssertEqual(store.course(withID: originalCourseID)?.sourceRootRelativePath, "新概念英语")

        let source = outside.appendingPathComponent("讲义.txt")
        let sourceBytes = Data("hello-library\n".utf8)
        try sourceBytes.write(to: source)
        let copiedCommon = try store.copyExternalFileIntoLibrary(source, isNote: false)
        XCTAssertEqual(FileManager.default.contents(atPath: source.path), sourceBytes)
        XCTAssertEqual(copiedCommon.deletingLastPathComponent().lastPathComponent, "通用资料")
        let copiedCourse = try store.copyExternalFileIntoCourse(source, courseID: originalCourseID, isNote: false)
        XCTAssertEqual(FileManager.default.contents(atPath: source.path), sourceBytes)
        XCTAssertEqual(copiedCourse.deletingLastPathComponent().lastPathComponent, "文稿")
        XCTAssertNotEqual(copiedCommon.path, copiedCourse.path)

        let same = try store.copyExternalFileIntoLibrary(source, isNote: false)
        XCTAssertEqual(same.path, copiedCommon.path)
        let other = outside.appendingPathComponent("讲义-2.txt")
        try Data("different-content\n".utf8).write(to: other)
        let colliding = outside.appendingPathComponent("讲义-copy.txt")
        try FileManager.default.copyItem(at: other, to: colliding)
        let renamedSource = outside.appendingPathComponent("讲义.txt")
        try? FileManager.default.removeItem(at: renamedSource)
        try FileManager.default.moveItem(at: colliding, to: renamedSource)
        let second = try store.copyExternalFileIntoLibrary(renamedSource, isNote: false)
        XCTAssertNotEqual(second.lastPathComponent, copiedCommon.lastPathComponent)
        XCTAssertEqual(FileManager.default.contents(atPath: copiedCommon.path), sourceBytes)

        let imported = store.importFiles([copiedCommon], markdownAsNotes: false)
        XCTAssertFalse(imported.isEmpty)
        let itemID = try XCTUnwrap(imported.first?.id)
        let chat = try XCTUnwrap(store.createStudySession(courseID: originalCourseID))
        store.messages = [AgentMessage(role: .user, text: "还在", source: nil)]
        store.syncActiveStudySession(titleSeed: "还在")
        try FileManager.default.removeItem(at: copiedCommon)
        store.refreshRuntimeItemURLs()
        if let index = store.importedItems.firstIndex(where: { $0.id == itemID }) {
            _ = store.forgetGoneImportedItem(at: index)
        }
        XCTAssertNil(store.importedItems.first(where: { $0.id == itemID }))
        XCTAssertTrue(store.studySessions.contains(where: { $0.id == chat.id && !$0.messages.isEmpty }))

        try LibraryInsideOnlyCheck.run(
            in: store,
            workspace: workspace,
            library: library,
            outside: outside
        )

        try FileManager.default.removeItem(at: library)
        let remainingIDs = store.importedItems.map(\.id)
        store.refreshRuntimeItemURLs()
        for index in store.importedItems.indices.reversed() {
            _ = store.forgetGoneImportedItem(at: index)
        }
        XCTAssertEqual(store.importedItems.map(\.id), remainingIDs)

        let encoded = try JSONEncoder().encode(store.importedItems)
        let text = String(data: encoded, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("importedFileLastKnownPath"))
        XCTAssertFalse(text.contains("importedFileBookmarkData"))
        XCTAssertFalse(text.contains("legacyExternal"))
        XCTAssertFalse(text.contains("\"kind\":\"shared\""))
    }
}

enum LibraryInsideOnlyCheck {
    @MainActor
    static func run(
        in store: WorkspaceStore,
        workspace: URL,
        library: URL,
        outside: URL
    ) throws {
        let entrySource = try String(
            contentsOfFile: "Sources/WeiBei/Views/CourseHubView.swift",
            encoding: .utf8
        )
        XCTAssertFalse(entrySource.contains("纳入已有文件夹"))
        XCTAssertFalse(entrySource.contains("Add existing folder"))

        let outsideCourse = outside.appendingPathComponent("库外课", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideCourse, withIntermediateDirectories: true)
        do {
            _ = try store.adoptCourseFolder(at: outsideCourse, title: "库外课")
            XCTFail("资料库外课程仍被原地纳入")
        } catch CourseProjectRootError.rootOutsideLibrary {
        }

        let createdID = try store.createCourseInLibrary(title: "库内新建")
        let createdRoot = try XCTUnwrap(store.courseRootURL(for: createdID))
        XCTAssertTrue(CourseProjectPathPolicy.contains(library, createdRoot, includingRoot: false))
        XCTAssertNil(store.course(withID: createdID)?.sourceRootPath)
        XCTAssertNil(store.course(withID: createdID)?.sourceRootBookmarkData)

        let traversal = StudyItem(
            id: "imported:traversal",
            title: "越界",
            subtitle: "secret.txt",
            kind: .text,
            urlPath: nil,
            isSample: false,
            storage: .common(relativePath: "../secret.txt")
        )
        XCTAssertNil(store.resolvedLibraryURL(for: traversal))

        let escaped = outside.appendingPathComponent("escaped.txt")
        try Data("outside\n".utf8).write(to: escaped)
        let escapeLink = library
            .appendingPathComponent("通用资料", isDirectory: true)
            .appendingPathComponent("escape.txt")
        try FileManager.default.createDirectory(
            at: escapeLink.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: escapeLink,
            withDestinationURL: escaped
        )
        let escapeItem = StudyItem(
            id: "imported:escape",
            title: "外链",
            subtitle: "escape.txt",
            kind: .text,
            urlPath: nil,
            isSample: false,
            storage: .common(relativePath: "通用资料/escape.txt")
        )
        XCTAssertNil(store.resolvedLibraryURL(for: escapeItem))

        let sharedBytes = Data("shared-in-library\n".utf8)
        let commonURL = try store.copyExternalFileIntoLibrary(
            {
                let source = outside.appendingPathComponent("共享讲义.txt")
                try sharedBytes.write(to: source)
                return source
            }(),
            isNote: false
        )
        let courseA = try store.createCourseInLibrary(title: "共享甲")
        let courseB = try store.createCourseInLibrary(title: "共享乙")
        let imported = store.importFiles([commonURL], markdownAsNotes: false)
        let sharedItem = try XCTUnwrap(imported.first)
        try store.shareCourseOwnedItemForSelfCheck(itemID: sharedItem.id, withCourseID: courseA)
        try store.shareCourseOwnedItemForSelfCheck(itemID: sharedItem.id, withCourseID: courseB)
        XCTAssertEqual(Set(store.courseIDs(for: sharedItem.id)), Set([courseA, courseB]))

        let courseARoot = try XCTUnwrap(store.courseRootURL(for: courseA))
        let link = courseARoot
            .appendingPathComponent("文稿", isDirectory: true)
            .appendingPathComponent(commonURL.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: link.path))
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        let resolvedLink = URL(fileURLWithPath: destination, relativeTo: link.deletingLastPathComponent())
            .standardizedFileURL
        XCTAssertTrue(CourseProjectPathPolicy.contains(library, resolvedLink, includingRoot: false))

        let linkedItem = store.importedItems.first { $0.id == sharedItem.id }
        XCTAssertNotNil(linkedItem.flatMap { store.resolvedLibraryURL(for: $0) })

        XCTAssertTrue(store.flushPendingWorkspaceSave())
        let snapshot = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: try Data(
                contentsOf: workspace.appendingPathComponent("workspace.json")
            )
        )
        let snapshotText = String(
            data: try JSONEncoder().encode(snapshot),
            encoding: .utf8
        ) ?? ""
        XCTAssertFalse(snapshotText.contains("urlPath"))
        XCTAssertFalse(snapshotText.contains("importedFileLastKnownPath"))
        XCTAssertFalse(snapshotText.contains("importedFileBookmarkData"))
        XCTAssertFalse(snapshotText.contains("sourceRootPath"))
        XCTAssertFalse(snapshotText.contains("sourceRootBookmarkData"))
        XCTAssertTrue(
            snapshot.courses?.allSatisfy {
                $0.sourceRootPath == nil && $0.sourceRootBookmarkData == nil
            } == true
        )

        let originalTitle = try XCTUnwrap(store.course(withID: courseA)?.title)
        let renamed = library.appendingPathComponent("共享甲改名", isDirectory: true)
        try FileManager.default.moveItem(at: courseARoot, to: renamed)
        store.discoverTopLevelCourseFolders()
        XCTAssertEqual(store.course(withID: courseA)?.title, "共享甲改名")
        XCTAssertEqual(store.course(withID: courseA)?.id, courseA)
        _ = originalTitle
    }
}
