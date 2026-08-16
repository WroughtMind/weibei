import AppKit
import XCTest
@testable import WeiBei

final class HoverPassThroughRegionTests: XCTestCase {
    @MainActor
    func testHoverProbeDoesNotClaimClicks() {
        let view = HoverPassThroughTrackingView(onHoverChange: { _ in })
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 36)

        XCTAssertNil(view.hitTest(NSPoint(x: 620, y: 18)), "top-right HTML theme buttons sit under this probe")
        XCTAssertNil(view.hitTest(NSPoint(x: 12, y: 8)))
        XCTAssertNil(view.hitTest(NSPoint(x: 320, y: 35)))
    }
}
