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
        let secondCurrentNote = try await importMarkdown(
            store,
            base: root,
            courseID: currentCourseID,
            fileName: "AlphaCurrentHitTokenTwo.md",
            content: "当前课第二份笔记 AlphaCurrentHitToken"
        )
        let otherNote = try await importMarkdown(
            store,
            base: root,
            courseID: otherCourseID,
            fileName: "BetaOtherNoteToken.md",
            content: (0..<92).map { "# 第 \($0 + 1) 节\n\n正文\n" }.joined(separator: "\n") + "\nBetaOtherNoteToken"
        )

        let handler = try store.agentHostToolHandlerForSelfCheck(courseID: currentCourseID)
        let currentHit = try await handler(.workspaceSearch(
            query: "AlphaCurrentHitToken",
            scope: .course,
            scopeID: currentCourseID.uuidString.lowercased(),
            cursor: nil,
            limit: 1
        ))
        XCTAssertEqual(currentHit.items.count, 1)
        XCTAssertEqual(currentHit.items.first?.item.id, currentNote.id)
        XCTAssertEqual(currentHit.total, 2)
        XCTAssertEqual(currentHit.nextCursor, "1")
        XCTAssertEqual(currentHit.items.first?.courseIDs, [currentCourseID.uuidString.lowercased()])
        XCTAssertEqual(currentHit.items.first?.courseTitles, ["当前课"])
        XCTAssertFalse(currentHit.items.contains { $0.item.id == otherNote.id })
        XCTAssertNotEqual(currentHit.items.first?.item.id, secondCurrentNote.id)

        let nextCurrentHit = try await handler(.workspaceSearch(
            query: "AlphaCurrentHitToken",
            scope: .course,
            scopeID: currentCourseID.uuidString.lowercased(),
            cursor: "1",
            limit: 1
        ))
        XCTAssertEqual(nextCurrentHit.items.first?.item.id, secondCurrentNote.id)
        XCTAssertEqual(nextCurrentHit.total, 2)
        XCTAssertNil(nextCurrentHit.nextCursor)

        let isolated = try await handler(.workspaceSearch(
            query: "BetaOtherNoteToken",
            scope: .course,
            scopeID: currentCourseID.uuidString.lowercased(),
            cursor: nil,
            limit: 8
        ))
        XCTAssertTrue(isolated.items.isEmpty)

        let broadcast = try await handler(.workspaceSearch(
            query: "BetaOtherNoteToken",
            scope: .library,
            scopeID: nil,
            cursor: nil,
            limit: 8
        ))
        XCTAssertEqual(broadcast.items.count, 1)
        XCTAssertEqual(broadcast.items.first?.item.id, otherNote.id)
        XCTAssertEqual(broadcast.items.first?.courseTitles, ["另一课"])
        XCTAssertEqual(broadcast.items.first?.item.role, "note")

        let blank = try await handler(.workspaceSearch(
            query: "   ",
            scope: .library,
            scopeID: nil,
            cursor: nil,
            limit: 8
        ))
        XCTAssertTrue(blank.items.isEmpty)
        XCTAssertTrue(blank.webPages.isEmpty)

        let miss = try await handler(.workspaceSearch(
            query: "NoSuchWorkspaceTokenZZZ",
            scope: .library,
            scopeID: nil,
            cursor: nil,
            limit: 8
        ))
        XCTAssertTrue(miss.items.isEmpty)
        XCTAssertTrue(miss.webPages.isEmpty)

        let map = try await handler(.courseMap(scope: .material, scopeID: otherNote.id, name: nil, cursor: "80", limit: 20))
        let position = try XCTUnwrap(map.items.last?.source?.sectionLocationID)
        let read = try await handler(.courseRead(itemID: otherNote.id, page: nil, location: position, cursor: nil, maximumCharacters: 37))
        var citation = try XCTUnwrap(read.items.first?.source)
        citation.label = "[笔记：r1.1]"
        XCTAssertEqual(position, "markdown-heading-91")
        XCTAssertTrue(citation.excerpt.contains("BetaOtherNoteToken"))
        let chat = try XCTUnwrap(store.createStudySession(courseID: nil))
        store.appendAgentMessage(AgentMessage(role: .assistant, text: "末节" + citation.label, source: nil, sources: [citation]))
        XCTAssertTrue(store.openAgentReplySource(citation))
        XCTAssertEqual(store.noteEditorCommand?.markdown, "91")
        XCTAssertEqual(store.noteEditorCommand?.value, otherNote.id)
        let saved = await store.persistWorkspaceNow()
        XCTAssertTrue(saved)
        let reopened = WorkspaceStore(workspaceDirectory: root.appendingPathComponent("workspace"), startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let reopenedCitation = try XCTUnwrap(reopened.studySessions.first { $0.id == chat.id }?.messages.last?.sources.first)
        XCTAssertTrue(reopened.openAgentReplySource(reopenedCitation))
        XCTAssertEqual(reopened.noteEditorCommand?.markdown, "91")
        XCTAssertEqual(reopened.noteEditorCommand?.value, otherNote.id)

        // 同一个工具会话应读到外部修改；有未保存编辑时使用当前草稿。
        let diskText = "# 外部修改\nFreshDiskSourceToken"
        let noteURL = try XCTUnwrap(currentNote.url)
        try diskText.write(to: noteURL, atomically: true, encoding: .utf8)
        let fresh = try await handler(.courseRead(itemID: currentNote.id, page: nil, location: nil,
                                                  cursor: nil, maximumCharacters: 100))
        XCTAssertEqual(fresh.items.compactMap { $0.source?.excerpt }.joined(), diskText)
        let draftText = "# 未保存编辑\nCurrentDraftSourceToken"
        store.scheduleNotePersistence(draftText, for: currentNote)
        store.pendingNotePersistenceTasks.removeValue(forKey: currentNote.id)?.cancel()
        let draft = try await handler(.courseRead(itemID: currentNote.id, page: nil, location: nil,
                                                  cursor: nil, maximumCharacters: 100))
        XCTAssertEqual(draft.items.compactMap { $0.source?.excerpt }.joined(), draftText)

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
