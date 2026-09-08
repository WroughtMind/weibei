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

    func testExcerptsFollowDocumentPositionsInsteadOfCaptureTime() {
        let later = SelectionRemarkRecord(selectionText: "后段", remarkText: "", source: .document, ownerTitle: "文稿",
            documentAnchor: SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: 20, endOffset: 22)))
        var earlier = later
        earlier.id = UUID()
        earlier.documentAnchor = SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: 0, endOffset: 2))
        earlier.createdAt = later.createdAt.addingTimeInterval(10)
        var unlocated = later
        unlocated.id = UUID()
        unlocated.documentAnchor = nil
        XCTAssertEqual([later, unlocated, earlier].sorted(by: SelectionRemarkRecord.inDocumentOrder).map(\.id), [earlier.id, later.id, unlocated.id])
        earlier.documentAnchor = SelectionDocumentAnchor(pdf: PDFSelectionAnchor(pageIndex: 1, lineRects: [SelectionRect(x: 20, y: 500, width: 50, height: 16)]))
        var lower = later
        lower.documentAnchor = SelectionDocumentAnchor(pdf: PDFSelectionAnchor(pageIndex: 1, lineRects: [SelectionRect(x: 20, y: 100, width: 50, height: 16)]))
        var nextPage = unlocated
        nextPage.documentAnchor = SelectionDocumentAnchor(pdf: PDFSelectionAnchor(pageIndex: 2, lineRects: [SelectionRect(x: 20, y: 600, width: 50, height: 16)]))
        XCTAssertEqual([nextPage, lower, earlier].sorted(by: SelectionRemarkRecord.inDocumentOrder).map(\.id), [earlier.id, lower.id, nextPage.id])
    }

    @MainActor
    func testReturningFromBookOpensSourceAndCarriesItsExactAnchor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("source.md")
        try "同一句\n\n第二处同一句".write(to: file, atomically: true, encoding: .utf8)
        let item = StudyItem(id: "source", title: "文稿", subtitle: "", kind: .markdown, urlPath: file.path, isSample: false)
        store.importedItems = [item]
        let record = SelectionRemarkRecord(selectionText: "同一句", remarkText: "批注", source: .document, ownerTitle: item.title, itemID: item.id,
            documentAnchor: SelectionDocumentAnchor(text: SelectionTextAnchor(startOffset: 6, endOffset: 9)))
        store.selectionRemarkRecords = [record]
        store.openExcerptBook(courseID: nil, at: record.id)
        store.openExcerptSource(record)
        XCTAssertFalse(store.excerptBookPresented)
        XCTAssertEqual(store.selectedMaterialItem?.id, item.id)
        let request = try XCTUnwrap(store.excerptRevealRequest)
        XCTAssertEqual(request.recordID, record.id)
        let json = selectionRemarkMarksJSON([record], activeID: record.id, revealRequest: request)
        let marks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(marks.first?["reveal"] as? String, request.id.uuidString)
        XCTAssertEqual((marks.first?["anchor"] as? [String: Int])?["startOffset"], 6)
        XCTAssertEqual(marks.first?["active"] as? Bool, true)
        XCTAssertNil(store.noteEditorCommand, "Returning to a source must not insert anything into a note")
        store.openExcerptSource(record)
        XCTAssertNotEqual(store.excerptRevealRequest?.id, request.id, "Returning again must issue a fresh scroll request")
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
        let focusRequest = store.paneState.focusRequest
        store.openSelectionRemarkRecord(record.id.uuidString, anchor: SelectionPopoverAnchor(x: 300, y: 180))
        XCTAssertEqual(store.selectionContext?.id, record.id)
        XCTAssertEqual(store.selectionAnchor?.y, 180)
        XCTAssertTrue(store.keepFloatingSelectionForAnswer)
        XCTAssertEqual(store.interaction.selectionNoteDraft, "还没写入的批注", "Viewing a saved remark must preserve the unsubmitted draft")
        XCTAssertEqual(store.paneState.focusRequest, focusRequest, "Viewing a remark must not request input focus")
        store.updateSelection("", source: .note)
        XCTAssertEqual(store.selectionContext?.id, record.id, "An unrelated pane losing selection must not dismiss the open remark")
        store.openExcerptBook(courseID: store.excerptCourseID(for: record), at: record.id)
        XCTAssertTrue(store.excerptBookPresented)
        XCTAssertEqual(store.excerptBookTargetRecordID, record.id)
        XCTAssertFalse(store.keepFloatingSelectionForAnswer)
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
