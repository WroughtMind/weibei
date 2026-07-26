import XCTest
@testable import WeiBeiCore

/// Covers actionable source references emitted by Markdown and Agent answers.
final class SourceReferenceTitleTests: XCTestCase {
    /// Verifies Chinese PDF references convert one-based page labels to zero-based indexes.
    func testParsesChinesePDFReference() {
        let reference = SourceReferenceTitle.parse("> 来源：**Mishkin 教材**，第 3 页")

        XCTAssertEqual(reference.title, "Mishkin 教材")
        XCTAssertEqual(reference.pageIndex, 2)
        XCTAssertNil(reference.sectionTitle)
    }

    /// Verifies all HTML disambiguation fields survive an English reference.
    func testParsesEnglishSectionReference() {
        let reference = SourceReferenceTitle.parse(
            "Source: Repeated Course, item: 2, section id: html-section-d4c3b2a1, section number: 5, section: Interest"
        )

        XCTAssertEqual(reference.title, "Repeated Course")
        XCTAssertNil(reference.pageIndex)
        XCTAssertEqual(reference.sectionTitle, "Interest")
        XCTAssertEqual(reference.sectionLocationID, "html-section-d4c3b2a1")
        XCTAssertEqual(reference.sectionOrdinal, 5)
        XCTAssertEqual(reference.courseItemOrdinal, 2)
    }

    /// Verifies callouts use the final source-bearing line instead of surrounding prose.
    func testUsesFinalSourceLineFromCallout() {
        let reference = SourceReferenceTitle.parse(
            """
            > [!note]
            > 这是一段解释。
            > 来源：课程讲义，第 12 页
            """
        )

        XCTAssertEqual(reference.title, "课程讲义")
        XCTAssertEqual(reference.pageIndex, 11)
    }
}
