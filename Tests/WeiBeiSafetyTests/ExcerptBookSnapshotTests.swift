import AppKit
import SwiftUI
import XCTest
@testable import WeiBei
import WeiBeiCore

final class ExcerptBookSnapshotTests: XCTestCase {
    /// Opt-in visual acceptance of the actual SwiftUI book, using public sample prose.
    @MainActor
    func testRenderExcerptBookForVisualReview() throws {
        guard let path = ProcessInfo.processInfo.environment["WEIBEI_EXCERPT_SNAPSHOT"] else {
            throw XCTSkip("Run with WEIBEI_EXCERPT_SNAPSHOT to capture the book for visual review")
        }
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let course = Course(title: "中国文学史")
        store.courses = [course]
        store.selectionRemarkRecords = [
            SelectionRemarkRecord(selectionText: "横看成岭侧成峰，远近高低各不同。\n不识庐山真面目，只缘身在此山中。", remarkText: "同一座山，从不同位置望去便有不同的形貌。认识事物，也需要换一个观察的位置。", courseID: course.id, source: .document, ownerTitle: "宋代诗歌 · 题西林壁", itemID: "poetry"),
            SelectionRemarkRecord(selectionText: "欲穷千里目，更上一层楼。", remarkText: "把视野与所处的位置联系起来读。", courseID: course.id, source: .document, ownerTitle: "唐代诗歌 · 登鹳雀楼", itemID: "tang")
        ]
        let hosting = NSHostingView(rootView: ExcerptBookView(courseID: course.id).environmentObject(store))
        hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 620)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(bitmap.pixelsWide, 600)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 600)
        withExtendedLifetime(window) {}
    }
}
