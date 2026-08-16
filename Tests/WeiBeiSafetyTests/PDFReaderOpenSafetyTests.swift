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
}
