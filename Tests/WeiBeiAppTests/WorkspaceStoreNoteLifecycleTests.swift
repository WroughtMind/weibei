import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class WorkspaceStoreNoteLifecycleTests: WorkspaceStoreTestCase {
    /**
     * 验证切换阅读材料不会把正在写作的笔记从笔记栏解绑。
     */
    @MainActor
    func testSelectingAnotherMaterialKeepsActiveNotebookAttached() throws {
        let directory = try makeTemporaryWorkspace()
        let noteURL = try writeFile(named: "attached.md", contents: "# Attached\n", in: directory)
        let store = makeStore(in: directory)
        _ = store.importFiles([noteURL], markdownAsNotes: true)
        let note = try XCTUnwrap(store.importedItems.first { $0.urlPath == noteURL.path })
        let otherMaterialID = try XCTUnwrap(store.sampleItems.dropFirst().first?.id)

        store.select(itemID: note.id)
        store.updateNote("# In progress\n")
        store.select(itemID: otherMaterialID)

        XCTAssertEqual(store.selectedItemID, otherMaterialID)
        XCTAssertEqual(store.activeNotebookItemID, note.id)
        XCTAssertEqual(store.noteText, "# In progress\n")
    }

    /**
     * 验证 Markdown 笔记编辑会写回真实文件并在重载后恢复。
     */
    @MainActor
    func testMarkdownNotebookEditPersistsToFileAndReloads() throws {
        let directory = try makeTemporaryWorkspace()
        let noteURL = try writeFile(named: "notes.md", contents: "# Original\n", in: directory)
        let store = makeStore(in: directory)
        let imported = store.importFiles([noteURL], markdownAsNotes: true)
        let note = try XCTUnwrap(store.importedItems.first { $0.urlPath == noteURL.path })
        XCTAssertTrue(imported.isEmpty)

        store.select(itemID: note.id)
        store.updateNote("# Updated\n\nBody")
        store.flushPendingNotePersistence()

        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "# Updated\n\nBody")
        let restored = makeStore(in: directory)
        restored.select(itemID: note.id)
        XCTAssertEqual(restored.noteText, "# Updated\n\nBody")
    }

    /**
     * 验证外部文件变化与应用草稿冲突时不会覆盖任一份内容。
     */
    @MainActor
    func testExternalMarkdownConflictPreservesDiskAndDraft() throws {
        let directory = try makeTemporaryWorkspace()
        let noteURL = try writeFile(named: "conflict.md", contents: "# Baseline\n", in: directory)
        let store = makeStore(in: directory)
        _ = store.importFiles([noteURL], markdownAsNotes: true)
        let note = try XCTUnwrap(store.importedItems.first { $0.urlPath == noteURL.path })
        store.select(itemID: note.id)

        try "# External edit\n".write(to: noteURL, atomically: true, encoding: .utf8)
        store.updateNote("# WeiBei draft\n")
        store.flushPendingNotePersistence()

        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), "# External edit\n")
        XCTAssertNotNil(store.noteFileError)

        let restored = makeStore(in: directory)
        restored.select(itemID: note.id)
        XCTAssertEqual(restored.noteText, "# WeiBei draft\n")
        XCTAssertNotNil(restored.noteFileError)
    }

    /**
     * 验证旧编辑器迟到的 flush 只写目标笔记，不污染当前活动笔记。
     */
    @MainActor
    func testLateInactiveDraftDoesNotMutateActiveNotebook() throws {
        let directory = try makeTemporaryWorkspace()
        let firstURL = try writeFile(named: "first.md", contents: "# First\n", in: directory)
        let secondURL = try writeFile(named: "second.md", contents: "# Second\n", in: directory)
        let store = makeStore(in: directory)
        _ = store.importFiles([firstURL, secondURL], markdownAsNotes: true)
        let first = try XCTUnwrap(store.importedItems.first { $0.urlPath == firstURL.path })
        let second = try XCTUnwrap(store.importedItems.first { $0.urlPath == secondURL.path })

        store.select(itemID: first.id)
        store.select(itemID: second.id)
        let activeText = store.noteText
        store.updateNote("# Late first draft\n", for: first.id)
        XCTAssertEqual(store.activeNotebookItemID, second.id)
        XCTAssertEqual(store.noteText, activeText)

        store.flushPendingNotePersistence()
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "# Late first draft\n")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "# Second\n")
    }
}
