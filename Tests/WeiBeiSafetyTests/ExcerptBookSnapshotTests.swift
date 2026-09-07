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
            SelectionRemarkRecord(selectionText: "横看成岭侧成峰，远近高低各不同。\n不识庐山真面目，只缘身在此山中。", remarkText: "认识事物，也需要换一个观察的位置。", courseID: course.id, source: .document, ownerTitle: "宋代诗歌", itemID: "poetry"),
            SelectionRemarkRecord(selectionText: "人有悲欢离合，月有阴晴圆缺，此事古难全。", remarkText: "从个人的悲欢写到普遍的人生经验。", courseID: course.id, source: .document, ownerTitle: "宋代诗歌", itemID: "poetry"),
            SelectionRemarkRecord(selectionText: "欲穷千里目，更上一层楼。", remarkText: "把视野与所处的位置联系起来读。", courseID: course.id, source: .document, ownerTitle: "唐代诗歌", itemID: "tang"),
            SelectionRemarkRecord(selectionText: "海内存知己，天涯若比邻。", remarkText: "", courseID: course.id, source: .document, ownerTitle: "唐代诗歌", itemID: "tang")
        ]
        let hosting = NSHostingView(rootView: ExcerptBookView(courseID: course.id).environmentObject(store)
            .preferredColorScheme(store.appearanceMode.colorScheme))
        hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 640)
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

        let record = store.selectionRemarkRecords[0]
        store.openSelectionRemarkRecord(record.id.uuidString, anchor: nil)
        let preview = NSHostingView(rootView: FloatingSelectionAgentView(expanded: .constant(true))
            .environmentObject(store).environmentObject(store.interaction).environmentObject(store.paneState)
            .preferredColorScheme(store.appearanceMode.colorScheme))
        preview.frame = NSRect(x: 0, y: 0, width: 380, height: 160)
        let previewWindow = NSWindow(contentRect: preview.frame, styleMask: .borderless, backing: .buffered, defer: false)
        previewWindow.contentView = preview
        preview.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        let previewBitmap = try XCTUnwrap(preview.bitmapImageRepForCachingDisplay(in: preview.bounds))
        preview.cacheDisplay(in: preview.bounds, to: previewBitmap)
        try XCTUnwrap(previewBitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-mark.png")))
        withExtendedLifetime(previewWindow) {}
    }
}
