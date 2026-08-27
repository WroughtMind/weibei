import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

/// 保护 Agent 工作区检索：当前课能命中、默认不跨课、空结果不编造。
@MainActor
final class WorkspaceSearchSafetyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testWorkspaceSearchHitsCurrentCourseIsolatesUnlessCrossLibraryAndStaysEmptyOnMiss() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-search-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = root.appendingPathComponent("资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: root.appendingPathComponent("workspace", isDirectory: true),
            notebookMarkdownWriter: { try WorkspaceStore.writeNotebookMarkdown($0, to: $1) },
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try await store.configureCourseLibraryAsync(at: library)
        let currentCourseID = try await store.createCourseInLibraryAsync(title: "当前课")
        let otherCourseID = try await store.createCourseInLibraryAsync(title: "另一课")
        let currentNote = try await importMarkdown(
            store,
            base: root,
            courseID: currentCourseID,
            fileName: "AlphaCurrentHitToken.md",
            content: "当前课笔记 AlphaCurrentHitToken"
        )
        let otherNote = try await importMarkdown(
            store,
            base: root,
            courseID: otherCourseID,
            fileName: "BetaOtherNoteToken.md",
            content: "另一课笔记 BetaOtherNoteToken"
        )

        let currentHit = await store.searchWorkspaceForAgent(
            query: "AlphaCurrentHitToken",
            limit: 8,
            crossLibrary: false,
            currentCourseID: currentCourseID
        )
        XCTAssertEqual(currentHit.items.count, 1)
        XCTAssertEqual(currentHit.items.first?.item.id, currentNote.id)
        XCTAssertEqual(currentHit.items.first?.courseIDs, [currentCourseID.uuidString.lowercased()])
        XCTAssertEqual(currentHit.items.first?.courseTitles, ["当前课"])
        XCTAssertFalse(currentHit.items.contains { $0.item.id == otherNote.id })

        let isolated = await store.searchWorkspaceForAgent(
            query: "BetaOtherNoteToken",
            limit: 8,
            crossLibrary: false,
            currentCourseID: currentCourseID
        )
        XCTAssertTrue(isolated.items.isEmpty)

        let broadcast = await store.searchWorkspaceForAgent(
            query: "BetaOtherNoteToken",
            limit: 8,
            crossLibrary: true,
            currentCourseID: currentCourseID
        )
        XCTAssertEqual(broadcast.items.count, 1)
        XCTAssertEqual(broadcast.items.first?.item.id, otherNote.id)
        XCTAssertEqual(broadcast.items.first?.courseTitles, ["另一课"])
        XCTAssertEqual(broadcast.items.first?.item.role, "note")

        let blank = await store.searchWorkspaceForAgent(
            query: "   ",
            limit: 8,
            crossLibrary: true,
            currentCourseID: currentCourseID
        )
        XCTAssertTrue(blank.items.isEmpty)
        XCTAssertTrue(blank.webPages.isEmpty)

        let miss = await store.searchWorkspaceForAgent(
            query: "NoSuchWorkspaceTokenZZZ",
            limit: 8,
            crossLibrary: true,
            currentCourseID: currentCourseID
        )
        XCTAssertTrue(miss.items.isEmpty)
        XCTAssertTrue(miss.webPages.isEmpty)
    }

    private func importMarkdown(
        _ store: WorkspaceStore,
        base: URL,
        courseID: UUID,
        fileName: String,
        content: String
    ) async throws -> StudyItem {
        let source = base.appendingPathComponent(fileName)
        try content.write(to: source, atomically: true, encoding: .utf8)
        let imported = try await store.importFileIntoCourse(
            source,
            courseID: courseID,
            role: .note
        )
        return imported.item
    }
}
