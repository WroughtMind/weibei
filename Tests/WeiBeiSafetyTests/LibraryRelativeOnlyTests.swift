import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

@MainActor
final class LibraryRelativeOnlyTests: XCTestCase {
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

        let imported = store.importFiles([source], markdownAsNotes: false)
        XCTAssertFalse(imported.isEmpty)
        let itemID = try XCTUnwrap(imported.first?.id)
        let chat = try XCTUnwrap(store.createStudySession(courseID: originalCourseID))
        store.messages = [AgentMessage(role: .user, text: "还在", source: nil)]
        store.syncActiveStudySession(titleSeed: "还在")
        _ = chat
        try FileManager.default.removeItem(at: copiedCommon)
        store.refreshRuntimeItemURLs()
        if let index = store.importedItems.firstIndex(where: { $0.id == itemID }) {
            _ = store.forgetGoneImportedItem(at: index)
        }
        XCTAssertNil(store.importedItems.first(where: { $0.id == itemID }))
        XCTAssertTrue(store.studySessions.contains(where: { $0.id == chat.id && !$0.messages.isEmpty }))

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
