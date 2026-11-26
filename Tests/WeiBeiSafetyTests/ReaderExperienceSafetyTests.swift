import AppKit
import SwiftUI
import XCTest
@testable import WeiBei
import WeiBeiCore

final class ReaderExperienceSafetyTests: XCTestCase {
    @MainActor
    func testPaperTabHoverSurvivesMovingOntoThePaperAndFoldsAfterLeaving() async throws {
        let hover = ReaderMaterialTabHover()
        hover.update(true, itemID: "first", in: .stack)
        XCTAssertEqual(hover.expandedID, "first")

        hover.update(false, itemID: "first", in: .stack)
        hover.update(true, itemID: "first", in: .unfolded)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(hover.expandedID, "first")

        hover.update(true, itemID: "second", in: .stack)
        hover.update(false, itemID: "first", in: .unfolded)
        hover.update(true, itemID: "first", in: .unfolded)
        XCTAssertEqual(hover.expandedID, "second")

        // At the seam the expanded paper can report entry before the tab reports exit.
        hover.update(true, itemID: "second", in: .unfolded)
        hover.update(false, itemID: "second", in: .stack)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(hover.expandedID, "second")

        hover.update(false, itemID: "second", in: .unfolded)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(hover.expandedID)
    }

    @MainActor
    func testPaperTabHoverStackPresenceAndDismissResetsFanOut() {
        let hover = ReaderMaterialTabHover()
        XCTAssertFalse(hover.isStackHovered)
        hover.updateStackPresence(true)
        XCTAssertTrue(hover.isStackHovered)
        hover.update(true, itemID: "first", in: .stack)
        XCTAssertEqual(hover.expandedID, "first")
        hover.dismiss()
        XCTAssertFalse(hover.isStackHovered)
        XCTAssertNil(hover.expandedID)
    }

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

    @MainActor
    func testCaptureReaderPaperTabsVisualReview() throws {
        guard let directory = ProcessInfo.processInfo.environment["WEIBEI_READER_TAB_SNAPSHOTS"] else {
            throw XCTSkip("Opt-in visual review of the redesigned READ paper tabs")
        }
        NSApplication.shared.setActivationPolicy(.prohibited)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let doc1 = StudyItem(id: "doc-linalg", title: "Linear Algebra Done Right (4th ed.)", subtitle: "高等代数 · PDF", kind: .pdf, urlPath: nil, isSample: false)
        let doc2 = StudyItem(id: "doc-short", title: "1.pdf", subtitle: "高等代数 · PDF", kind: .pdf, urlPath: nil, isSample: false)
        let doc3 = StudyItem(id: "doc-svd", title: "第二章：奇异值分解讲义", subtitle: "高等代数 · Markdown", kind: .markdown, urlPath: nil, isSample: false)
        let doc4 = StudyItem(id: "doc-slides", title: "Week 06 · Fourier Slides", subtitle: "信号分析 · PPT", kind: .pptx, urlPath: nil, isSample: false)
        store.importedItems = [doc1, doc2, doc3, doc4]

        store.openContextualItem(doc1.id, kind: .material)
        store.updateReaderPageIndex(141)
        store.openContextualItem(doc2.id, kind: .material)
        store.updateReaderPageIndex(0)
        store.openContextualItem(doc3.id, kind: .material)
        store.updateReaderHTMLLocation(id: "sec-2-3", title: "§2.3 Eckart–Young，章节标识：sec-2-3", reason: "scroll")
        store.openContextualItem(doc4.id, kind: .material)
        store.updateReaderHTMLLocation(id: "slide-18", title: "第 18 / 32 页，章节标识：slide-18", reason: "scroll")
        store.selectReaderTab(doc1.id)

        struct TwoPanePreviewFixture: View {
            @ObservedObject var store: WorkspaceStore
            let hover: ReaderMaterialTabHover
            let readWidth: CGFloat
            let totalWidth: CGFloat
            let pinReadBar: Bool

            var body: some View {
                let paper = Color(weiBeiNativeColor: WeiBeiNativePalette.paper(for: store.appearanceMode))
                let ink = Color(weiBeiNativeColor: WeiBeiNativePalette.ink(for: store.appearanceMode))
                let secondary = Color(weiBeiNativeColor: WeiBeiNativePalette.secondaryInk(for: store.appearanceMode))
                let tertiary = Color(weiBeiNativeColor: WeiBeiNativePalette.tertiaryInk(for: store.appearanceMode))
                let accent = Color(weiBeiNativeColor: WeiBeiNativePalette.accent(for: store.appearanceMode))

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("READ PANE · \(store.selectedMaterialItem?.kind.label(language: .chinese) ?? "")")
                            .weiBeiText(10, weight: .semibold)
                            .foregroundStyle(tertiary)
                        Text(store.selectedMaterialItem?.id == "doc-short"
                            ? "极短标题对照：1.pdf（验证小便签纹丝不动）"
                            : "7.14 The Real Spectral Theorem")
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                        Rectangle()
                            .fill(accent.opacity(0.55))
                            .frame(width: 48, height: 1)
                        Text("Suppose V is a finite-dimensional real inner product space and T is a self-adjoint operator on V. Then V has an orthonormal basis consisting of eigenvectors of T.")
                            .weiBeiText(13)
                            .lineSpacing(5)
                            .foregroundStyle(secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 28)
                    .frame(width: readWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(paper)
                    .overlay(alignment: .top) {
                        ImmersiveHoverTitleView(
                            mark: "READ",
                            title: store.currentReferenceTitle,
                            appearanceMode: store.appearanceMode,
                            isPinned: pinReadBar,
                            readerTabHover: hover
                        ) {
                            HStack(spacing: 8) {
                                ContextualContentListButton(kind: .material)
                                Text("已问 · 2")
                                    .weiBeiText(11, weight: .semibold)
                                    .foregroundStyle(accent.opacity(0.9))
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(Color(weiBeiNativeColor: WeiBeiNativePalette.accentSoft(for: store.appearanceMode)), in: Capsule())
                                Image(systemName: "eyeglasses")
                                    .weiBeiText(12)
                                    .foregroundStyle(secondary)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .padding(.horizontal, 8)
                    }

                    Rectangle()
                        .fill(Color(weiBeiNativeColor: WeiBeiNativePalette.hairline(for: store.appearanceMode)))
                        .frame(width: 1)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("NOTE PANE · 顶部基准对照")
                            .weiBeiText(10, weight: .semibold)
                            .foregroundStyle(tertiary)
                        Text("谱定理的几何直觉与正交投影分解")
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundStyle(ink)
                        Rectangle()
                            .fill(accent.opacity(0.55))
                            .frame(width: 48, height: 1)
                        Text("左右两栏正文第一行保持在同一水平基线上，不切掉 29pt 空白带；悬停小便签时原地舒展并向下融通。")
                            .weiBeiText(13)
                            .lineSpacing(5)
                            .foregroundStyle(secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .frame(width: max(180, totalWidth - readWidth - 1), alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(paper)
                }
                .frame(width: totalWidth, height: 260)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(weiBeiNativeColor: WeiBeiNativePalette.hairline(for: store.appearanceMode)))
                        .frame(height: 1)
                }
                .environmentObject(store)
                .environment(\.weiBeiTextScale, 1.0)
                .preferredColorScheme(store.appearanceMode.colorScheme)
            }
        }

        func capture(
            name: String,
            mode: WeiBeiAppearanceMode,
            selectedID: String,
            hoveredID: String?,
            pinReadBar: Bool,
            readWidth: CGFloat,
            totalWidth: CGFloat
        ) throws {
            WeiBeiThemeRuntime.mode = mode
            store.appearanceMode = mode
            store.selectReaderTab(selectedID)
            let hover = ReaderMaterialTabHover()
            if let hoveredID {
                hover.updateStackPresence(true)
                hover.update(true, itemID: hoveredID, in: .stack)
            }

            let rootView = TwoPanePreviewFixture(
                store: store,
                hover: hover,
                readWidth: readWidth,
                totalWidth: totalWidth,
                pinReadBar: pinReadBar
            )
            let host = NSHostingView(rootView: rootView)
            host.frame = NSRect(x: 0, y: 0, width: totalWidth, height: 260)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let outURL = URL(fileURLWithPath: directory).appendingPathComponent(name + ".png")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: outURL)
            XCTAssertFalse(window.isVisible)
            window.contentView = nil
        }

        try capture(
            name: "read-tabs-v2-01-resting-clean",
            mode: .paper,
            selectedID: doc1.id,
            hoveredID: nil,
            pinReadBar: false,
            readWidth: 540,
            totalWidth: 860
        )
        try capture(
            name: "read-tabs-v2-02-revealed-folded-paper",
            mode: .paper,
            selectedID: doc1.id,
            hoveredID: nil,
            pinReadBar: true,
            readWidth: 540,
            totalWidth: 860
        )
        try capture(
            name: "read-tabs-v2-03-hover-unfolded-paper",
            mode: .paper,
            selectedID: doc1.id,
            hoveredID: doc3.id,
            pinReadBar: true,
            readWidth: 540,
            totalWidth: 860
        )
        try capture(
            name: "read-tabs-v2-04-hover-unfolded-inkstone",
            mode: .inkstone,
            selectedID: doc1.id,
            hoveredID: doc3.id,
            pinReadBar: true,
            readWidth: 540,
            totalWidth: 860
        )
    }
}
