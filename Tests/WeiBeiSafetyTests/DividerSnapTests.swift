import Foundation
import WeiBeiCore
import XCTest

final class DividerSnapTests: XCTestCase {
    func testSnapPreservesPrecisionAndUnaffectedPane() {
        for ratio: CGFloat in [0.25, 0.5, 0.75] {
            let left = 1200 * ratio
            XCTAssertEqual(ContentRailPolicy.dividerWidths([left + 8, 1200 - left - 8, 310], divider: 0), [left, 1200 - left, 310])
            XCTAssertEqual(ContentRailPolicy.dividerWidths([310, left - 8, 1200 - left + 8], divider: 1), [310, left, 1200 - left])
        }
        XCTAssertEqual(ContentRailPolicy.dividerWidths([480, 520], divider: 0), [480, 520])
        XCTAssertEqual(ContentRailPolicy.dividerWidths([492, 508], divider: 0, skipSnap: true), [492, 508])
        XCTAssertEqual(ContentRailPolicy.dividerWidths([198, 602], divider: 0), [198, 602])
        XCTAssertEqual(ContentRailPolicy.dividerWidths([28, 392, 780], divider: 1, equalize: true), [28, 586, 586])
        XCTAssertEqual(ContentRailPolicy.dividerWidths([35, 465, 28], divider: 0), [28, 472, 28])
        XCTAssertEqual(ContentRailPolicy.dividerWidths([35, 465], divider: 0, skipSnap: true), [35, 465])
        XCTAssertEqual(ContentRailPolicy.dividerWidths([300, 300], divider: -1), [300, 300])
        XCTAssertEqual(ContentRailPolicy.dividerWidths([300], divider: 0), [300])
    }
}
