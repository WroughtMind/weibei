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
        let request = PDFPageRestorationRequest(
            pageIndex: 89,
            requestID: UUID(),
            materialID: "material-a",
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        )

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
        let completed = PDFPageRestorationRequest(
            pageIndex: 89,
            requestID: UUID(),
            materialID: "material-a",
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        )
        let replacement = PDFPageRestorationRequest(
            pageIndex: 12,
            requestID: UUID(),
            materialID: "material-b",
            documentURL: URL(fileURLWithPath: "/tmp/b.pdf")
        )

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

    func testPDFRestorationAbandonsAfterTwoFailedJumpsAndResetsForNewLoad() {
        let requestID = UUID()
        let document = NSObject()
        let firstLoad = PDFDocumentLoadIdentity(
            documentIdentifier: ObjectIdentifier(document),
            generation: 1,
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        )
        var state = PDFPageRestorationAttemptState()

        XCTAssertEqual(state.resolve(
            requestID: requestID,
            loadIdentity: firstLoad,
            currentPageIndex: 0,
            targetPageIndex: 89,
            userInitiated: false
        ), .jump)
        XCTAssertEqual(state.resolve(
            requestID: requestID,
            loadIdentity: firstLoad,
            currentPageIndex: 0,
            targetPageIndex: 89,
            userInitiated: false
        ), .jump)
        XCTAssertEqual(state.resolve(
            requestID: requestID,
            loadIdentity: firstLoad,
            currentPageIndex: 0,
            targetPageIndex: 89,
            userInitiated: false
        ), .abandon)
        XCTAssertEqual(state.attemptCount, 2)
        XCTAssertEqual(PDFPageRestorationEventResolution.resolve(
            activeRequest: nil,
            requestAtEvent: nil,
            reportedPageIndex: 7,
            pageCount: 90
        ), .publish, "失败收口后真实页必须恢复正常发布")

        let reloaded = PDFDocumentLoadIdentity(
            documentIdentifier: ObjectIdentifier(document),
            generation: 2,
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        )
        XCTAssertEqual(state.resolve(
            requestID: requestID,
            loadIdentity: reloaded,
            currentPageIndex: 0,
            targetPageIndex: 89,
            userInitiated: false
        ), .jump)
        XCTAssertEqual(state.attemptCount, 1)
        XCTAssertEqual(state.resolve(
            requestID: requestID,
            loadIdentity: reloaded,
            currentPageIndex: 89,
            targetPageIndex: 89,
            userInitiated: false
        ), .confirm)
    }

    func testPDFRestorationCancelsOnlyForExplicitUserInput() {
        let document = NSObject()
        let load = PDFDocumentLoadIdentity(
            documentIdentifier: ObjectIdentifier(document),
            generation: 1,
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        )
        var state = PDFPageRestorationAttemptState()
        let requestID = UUID()

        XCTAssertEqual(state.resolve(
            requestID: requestID,
            loadIdentity: load,
            currentPageIndex: 0,
            targetPageIndex: 89,
            userInitiated: false
        ), .jump, "程序跳页产生的页变不能伪装成用户取消")
        XCTAssertEqual(state.resolve(
            requestID: requestID,
            loadIdentity: load,
            currentPageIndex: 0,
            targetPageIndex: 89,
            userInitiated: true
        ), .abandon)
    }

    func testPDFRestorationRequestRequiresCurrentMaterialURLAndRequestID() {
        let requestID = UUID()
        let request = PDFPageRestorationRequest(
            pageIndex: 89,
            requestID: requestID,
            materialID: "material-a",
            documentURL: URL(fileURLWithPath: "/tmp/folder/../a.pdf")
        )

        XCTAssertTrue(request.matches(
            materialID: "material-a",
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            requestID: requestID
        ))
        XCTAssertFalse(request.matches(
            materialID: "material-b",
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            requestID: requestID
        ))
        XCTAssertFalse(request.matches(
            materialID: "material-a",
            documentURL: URL(fileURLWithPath: "/tmp/b.pdf"),
            requestID: requestID
        ), "同一资料编号换了文件也不能确认旧请求")
        XCTAssertFalse(request.matches(
            materialID: "material-a",
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf"),
            requestID: UUID()
        ))
    }

    func testPDFPageEventLoadIdentityRejectsOldDocumentOrGeneration() {
        let documentA = NSObject()
        let documentB = NSObject()
        let event = PDFDocumentLoadIdentity(
            documentIdentifier: ObjectIdentifier(documentA),
            generation: 4,
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        )

        XCTAssertEqual(event, PDFDocumentLoadIdentity(
            documentIdentifier: ObjectIdentifier(documentA),
            generation: 4,
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        ))
        XCTAssertNotEqual(event, PDFDocumentLoadIdentity(
            documentIdentifier: ObjectIdentifier(documentB),
            generation: 4,
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        ))
        XCTAssertNotEqual(event, PDFDocumentLoadIdentity(
            documentIdentifier: ObjectIdentifier(documentA),
            generation: 5,
            documentURL: URL(fileURLWithPath: "/tmp/a.pdf")
        ))
        XCTAssertNotEqual(event, PDFDocumentLoadIdentity(
            documentIdentifier: ObjectIdentifier(documentA),
            generation: 4,
            documentURL: URL(fileURLWithPath: "/tmp/b.pdf")
        ))
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
