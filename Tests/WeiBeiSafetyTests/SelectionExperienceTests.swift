import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class SelectionExperienceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    func testExcerptBooksPersistByCourseWithoutChangingTheNote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let firstCourse = UUID(), secondCourse = UUID()
        let anchor = SelectionDocumentAnchor(pdf: PDFSelectionAnchor(pageIndex: 0, lineRects: [SelectionRect(x: 20, y: 60, width: 80, height: 16)]))
        store.noteText = "我正在写的笔记"
        for (course, item) in [(firstCourse, "a.pdf"), (firstCourse, "b.pdf"), (secondCourse, "c.pdf")] {
            store.activeCourseID = course
            store.selectionContext = SelectionContext(text: "相同原文", source: .document, ownerTitle: item, itemID: item, documentAnchor: anchor)
            _ = store.beginOrReuseSelectionAskThread(for: store.selectionContext!)
            let saved = saveRemark("我的批注", in: store)
            XCTAssertTrue(saved)
        }
        XCTAssertEqual(store.selectionAskThreads.count, 3, "Same PDF coordinates in different documents must not share a question")
        XCTAssertEqual(store.excerpts(in: firstCourse).map(\.itemID), ["a.pdf", "b.pdf"])
        XCTAssertEqual(store.excerpts(in: secondCourse).map(\.itemID), ["c.pdf"])
        XCTAssertEqual(store.noteText, "我正在写的笔记")
        XCTAssertNil(store.noteEditorCommand)
        XCTAssertEqual(store.selectionRemarkRecords(forItemID: "c.pdf").count, 1)
        let reopened = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        XCTAssertEqual(reopened.excerpts(in: firstCourse), store.excerpts(in: firstCourse))
        XCTAssertEqual(reopened.excerpts(in: secondCourse), store.excerpts(in: secondCourse))
    }

    @MainActor
    func testAskKeepsThePassageAndFloatingInputInEveryReadingLayout() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        for layout in [WorkspaceLayout.immersiveReading, .documentAgentNotes] {
            store.layout = layout
            store.showAgent = true
            let anchor = SelectionPopoverAnchor(x: 320, y: 210)
            store.updateSelection("原处提问", source: .document, anchor: anchor)
            store.askSelection()
            XCTAssertEqual(store.layout, layout)
            XCTAssertEqual(store.agentSurface, .selectionFloat)
            XCTAssertEqual(store.selectionAnchor, anchor)
            XCTAssertTrue(store.keepFloatingSelectionForAnswer)
        }
    }

    @MainActor
    func testPendingRemarkKeepsTheSubmittedPassageWhenSelectionChanges() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let courseID = UUID()
        let submitted = SelectionContext(text: "提交时的文段", source: .document, ownerTitle: "文稿 A", itemID: "a")
        let newer = SelectionContext(text: "随后选中的文段", source: .document, ownerTitle: "文稿 B", itemID: "b")
        store.selectionContext = newer
        store.activeCourseID = UUID()
        let completed = expectation(description: "submitted excerpt saved")
        Task { @MainActor in
            let saved = await store.saveSelectionRemark("批注", for: submitted, courseID: courseID)
            XCTAssertTrue(saved)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(store.excerpts(in: courseID).first?.itemID, "a")
        XCTAssertEqual(store.selectionContext?.id, newer.id)
    }

    @MainActor
    func testRepeatedPassagesStayIndependentAndRemarkFailureKeepsDraft() {
        struct CannotWrite: Error {}
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, workspaceSnapshotWriter: { _, _ in throw CannotWrite() }, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.interaction.selectionNoteDraft = "还没写入的批注"
        for start in [0, 20] {
            let selection = SelectionContext(text: "同一句", source: .document, ownerTitle: "一篇文稿", itemID: "same.md", documentAnchor: SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: start, endOffset: start + 3)))
            store.selectionContext = selection
            _ = store.beginOrReuseSelectionAskThread(for: selection)
            let saved = saveRemark(store.interaction.selectionNoteDraft, in: store)
            XCTAssertFalse(saved)
        }
        XCTAssertEqual(store.selectionAskThreads.count, 2)
        XCTAssertEqual(store.selectionRemarkRecords.count, 2)
        XCTAssertEqual(store.interaction.selectionNoteDraft, "还没写入的批注")
        XCTAssertNil(store.noteEditorCommand)
        let record = store.selectionRemarkRecords[0]
        store.openSelectionRemarkRecord(record.id.uuidString, anchor: SelectionPopoverAnchor(x: 300, y: 180))
        XCTAssertEqual(store.selectionContext?.id, record.id)
        XCTAssertEqual(store.selectionAnchor?.y, 180)
        XCTAssertTrue(store.keepFloatingSelectionForAnswer)
        store.updateSelection("", source: .note)
        XCTAssertEqual(store.selectionContext?.id, record.id, "An unrelated pane losing selection must not dismiss the open remark")
    }
}

@MainActor
extension XCTestCase {
    // WorkspaceStore has synchronous startup file operations; construct it outside an async task.
    func saveRemark(_ text: String, in store: WorkspaceStore) -> Bool {
        guard let selection = store.selectionContext else { return false }
        let courseID = store.activeCourseID
        let completed = expectation(description: "remark persistence completed")
        var saved = false
        Task { @MainActor in
            saved = await store.saveSelectionRemark(text, for: selection, courseID: courseID)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)
        return saved
    }
}
