import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore
import XCTest
@testable import WeiBei

final class PDFReaderOpenSafetyTests: XCTestCase {
    @MainActor
    func testCrossPageSelectionRetainsBothPagesAndRemarkGeometryRefreshes() throws {
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        text.string = "A complete selected passage on this page."
        let document = try XCTUnwrap(PDFDocument(data: text.dataWithPDF(inside: text.bounds)))
        let first = try XCTUnwrap(document.page(at: 0))
        document.insert(try XCTUnwrap(first.copy() as? PDFPage), at: 1)
        let selection = try XCTUnwrap(document.selectionForEntireDocument)
        let anchor = PDFReaderRepresentable.Coordinator.lineAnchor(for: selection, in: document, pageIndex: 0)
        XCTAssertEqual(Set(anchor.rectsByPage.keys), [0, 1])
        var activatedAsk: String?
        let coordinator = PDFReaderRepresentable.Coordinator(
            pageIndex: .constant(0), pageCount: .constant(2), onUserPageChange: { _ in },
            onSelectableTextChange: { _ in }, onSelectionChange: { _, _, _, _ in }, onAskUnderlineActivate: { id, _ in activatedAsk = id }
        )
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        view.document = document
        view.layoutDocumentView()
        coordinator.applyAskUnderlines([(id: "ask", text: selection.string ?? "", anchor: SelectionDocumentAnchor(pdf: anchor))], in: view)
        XCTAssertFalse(first.annotations.isEmpty)
        XCTAssertFalse(document.page(at: 1)!.annotations.isEmpty)
        let line = try XCTUnwrap(anchor.lineRects.first).cgRect
        XCTAssertTrue(coordinator.handleSelectionMarkClick(at: view.convert(CGPoint(x: line.midX, y: line.midY), from: first), in: view))
        XCTAssertEqual(activatedAsk, "ask", "A remark miss must still allow opening a question underline")
        coordinator.applyRemarkMarks([(id: "remark", anchor: SelectionDocumentAnchor(pdf: anchor), text: "")], in: view)
        XCTAssertEqual(coordinator.remarkHits.count, 1)
        XCTAssertEqual(coordinator.remarkHits[0].pageIndex, 1)
        let original = coordinator.remarkHits[0].hitBounds
        let moved = PDFSelectionAnchor(pageIndex: 1, lineRects: [SelectionRect(x: 50, y: 150, width: 120, height: 15)])
        coordinator.applyRemarkMarks([(id: "remark", anchor: SelectionDocumentAnchor(pdf: moved), text: "")], in: view)
        XCTAssertNotEqual(coordinator.remarkHits[0].hitBounds, original)
        let recordID = UUID()
        coordinator.applyRemarkMarks([(id: recordID.uuidString, anchor: SelectionDocumentAnchor(pdf: moved), text: "")], in: view)
        coordinator.setActiveRemark(recordID.uuidString, in: view)
        coordinator.handleRemarkMarkHover(at: .zero, in: view)
        XCTAssertTrue(document.page(at: 1)!.annotations.contains { $0.userName == PDFReaderRepresentable.Coordinator.remarkMarkHoverMarker }, "The active passage must stay highlighted while reading its remark")
        let request = ExcerptRevealRequest(recordID: recordID)
        coordinator.revealRemark(request, in: view)
        XCTAssertTrue(view.currentPage === document.page(at: 1))
        view.go(to: first)
        coordinator.revealRemark(request, in: view)
        XCTAssertTrue(view.currentPage === first, "Refreshing the same reveal must not take over scrolling")
    }

    func testNativeTextScanDoesNotRequireMainThread() {
        let document = PDFDocument()
        for _ in 0..<8 {
            document.insert(PDFPage(), at: document.pageCount)
        }
        let indexes = PDFReaderOpenSafety.nativeTextPageIndexes(in: document)
        XCTAssertTrue(indexes.isEmpty)
        XCTAssertEqual(
            PDFReaderOpenSafety.ocrCandidatePageIndexes(in: document).count,
            8
        )
    }

    @MainActor
    func testReaderPDFViewDoesNotExposeAccessibilityChildren() {
        let view = PDFView()
        PDFReaderOpenSafety.disableAccessibilityTree(on: view)
        XCTAssertFalse(view.isAccessibilityElement())
        XCTAssertNil(view.accessibilityChildren())
    }

    func testPageHasNativeTextMatchesExtractedString() {
        let blank = PDFPage()
        XCTAssertFalse(PDFReaderOpenSafety.pageHasNativeText(blank))
    }
}
