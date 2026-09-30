import XCTest
@testable import WeiBei

final class ReaderExperienceSafetyTests: XCTestCase {
    func testPDFPageJumpKeepsBrowseMode() {
        let scroll = PDFPageJumpPlan.resolve(targetPageIndex: 3, pageCount: 10, browseMode: .scroll)
        XCTAssertEqual(scroll.browseMode, .scroll)
        XCTAssertEqual(scroll.pageIndex, 3)
        XCTAssertEqual(scroll.railTargetPageIndex, 3)

        let page = PDFPageJumpPlan.resolve(targetPageIndex: 99, pageCount: 4, browseMode: .page)
        XCTAssertEqual(page.browseMode, .page)
        XCTAssertEqual(page.pageIndex, 3)
        XCTAssertNil(page.railTargetPageIndex)

        let clamped = PDFPageJumpPlan.resolve(targetPageIndex: -2, pageCount: 4, browseMode: .scroll)
        XCTAssertEqual(clamped.browseMode, .scroll)
        XCTAssertEqual(clamped.pageIndex, 0)
    }

    func testTextMaterialFallsBackToGB18030() {
        let lecture = "利率讲义：复利"
        let gb18030 = lecture.data(using: ReaderView.gb18030TextEncoding)
        XCTAssertEqual(gb18030.flatMap(ReaderView.decodeTextMaterial), lecture)

        let utf8 = Data("UTF-8 讲义".utf8)
        XCTAssertEqual(ReaderView.decodeTextMaterial(utf8), "UTF-8 讲义")
    }

    func testCopiedReferenceOmitsSectionLocationID() {
        XCTAssertEqual(
            WorkspaceStore.userFacingReferenceTitle("课件，章节标识：ppt/slides/slide2.xml#p0，章节：第 1 页"),
            "课件，章节：第 1 页"
        )
        XCTAssertEqual(
            WorkspaceStore.userFacingReferenceTitle("Slides, section id: word/document.xml, section: Intro"),
            "Slides, section: Intro"
        )
        XCTAssertEqual(WorkspaceStore.userFacingReferenceTitle("课堂笔记"), "课堂笔记")
    }
}
