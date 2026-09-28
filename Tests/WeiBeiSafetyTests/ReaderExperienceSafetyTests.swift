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

    func testPDFRestorationConfirmsOnlyMatchingRequestAtTargetPage() {
        let request = PDFPageRestorationRequest(pageIndex: 89, requestID: UUID())

        XCTAssertEqual(
            PDFPageRestorationEventResolution.resolve(
                activeRequest: request,
                requestAtEvent: request,
                reportedPageIndex: 0,
                pageCount: 90
            ),
            .retry
        )
        XCTAssertEqual(
            PDFPageRestorationEventResolution.resolve(
                activeRequest: request,
                requestAtEvent: request,
                reportedPageIndex: 89,
                pageCount: 90
            ),
            .confirm
        )
    }

    func testPDFRestorationIgnoresDelayedOrReplacedRequestEvents() {
        let completed = PDFPageRestorationRequest(pageIndex: 89, requestID: UUID())
        let replacement = PDFPageRestorationRequest(pageIndex: 12, requestID: UUID())

        XCTAssertEqual(
            PDFPageRestorationEventResolution.resolve(
                activeRequest: nil,
                requestAtEvent: completed,
                reportedPageIndex: 0,
                pageCount: 90
            ),
            .ignore,
            "确认后才送达的第 1 页回报不能覆盖已恢复页"
        )
        XCTAssertEqual(
            PDFPageRestorationEventResolution.resolve(
                activeRequest: replacement,
                requestAtEvent: completed,
                reportedPageIndex: 89,
                pageCount: 90
            ),
            .ignore,
            "旧请求回报不能确认或覆盖新请求"
        )
    }

    func testPDFPageChangePublishesRealScrollAfterRestorationCompletes() {
        XCTAssertEqual(
            PDFPageRestorationEventResolution.resolve(
                activeRequest: nil,
                requestAtEvent: nil,
                reportedPageIndex: 35,
                pageCount: 90
            ),
            .publish
        )
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
