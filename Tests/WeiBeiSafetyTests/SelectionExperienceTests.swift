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
    func testExcerptBooksPersistByCourseWithoutChangingTheNote() async throws {
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
            let saved = await store.saveSelectionRemark("我的批注")
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
    func testRepeatedPassagesStayIndependentAndRemarkFailureKeepsDraft() async {
        struct CannotWrite: Error {}
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, workspaceSnapshotWriter: { _, _ in throw CannotWrite() }, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.interaction.selectionNoteDraft = "还没写入的批注"
        for start in [0, 20] {
            let selection = SelectionContext(text: "同一句", source: .document, ownerTitle: "一篇文稿", itemID: "same.md", documentAnchor: SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: start, endOffset: start + 3)))
            store.selectionContext = selection
            _ = store.beginOrReuseSelectionAskThread(for: selection)
            let saved = await store.saveSelectionRemark(store.interaction.selectionNoteDraft)
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
