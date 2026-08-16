import AppKit
import PDFKit
import XCTest
@testable import WeiBei

final class PDFReaderOpenSafetyTests: XCTestCase {
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

    @MainActor
    func testDisabledAccessibilityTreeStillExposesProgrammaticSelection() {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        let view = PDFView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        PDFReaderOpenSafety.disableAccessibilityTree(on: view)
        view.document = document
        PDFReaderOpenSafety.disableAccessibilityTree(on: view)
        guard let page = document.page(at: 0),
              let selection = page.selection(for: page.bounds(for: .mediaBox)) else {
            XCTFail("expected a page selection")
            return
        }
        view.setCurrentSelection(selection, animate: false)
        XCTAssertNotNil(view.currentSelection)
        XCTAssertFalse(view.isAccessibilityElement())
        XCTAssertNil(view.accessibilityChildren())
    }
}
