import CoreGraphics
import XCTest
@testable import WeiBei

final class NativeMarkdownMeasurementTests: XCTestCase {
    func testLayoutProbesDoNotRetypesetTheAnswerAtZeroOrInfiniteWidth() {
        var measurement = NativeMarkdownMeasurement()
        var measuredWidths: [CGFloat] = []
        func measure(_ width: CGFloat) -> CGFloat {
            measuredWidths.append(width)
            return 240
        }
        XCTAssertEqual(measurement.sizeThatFits(proposedWidth: 0, viewWidth: 320, measure: measure), .zero)
        XCTAssertTrue(measuredWidths.isEmpty)
        XCTAssertEqual(measurement.sizeThatFits(proposedWidth: 320, viewWidth: 320, measure: measure), CGSize(width: 320, height: 240))
        for _ in 0..<30 {
            XCTAssertEqual(measurement.sizeThatFits(proposedWidth: .infinity, viewWidth: 300, measure: measure), CGSize(width: 320, height: 240))
            XCTAssertEqual(measurement.sizeThatFits(proposedWidth: nil, viewWidth: 300, measure: measure), CGSize(width: 320, height: 240))
        }
        XCTAssertEqual(measuredWidths, [320])
        XCTAssertEqual(measurement.sizeThatFits(proposedWidth: 280, viewWidth: 320, measure: measure), CGSize(width: 280, height: 240))
        XCTAssertEqual(measuredWidths, [320, 280])
    }

    func testUnplacedAnswerWaitsForARealWidth() {
        var measurement = NativeMarkdownMeasurement()
        var measured = false
        for width: CGFloat? in [nil, .infinity] {
            XCTAssertNil(measurement.sizeThatFits(proposedWidth: width, viewWidth: 0) { _ in
                measured = true
                return 20
            })
        }
        XCTAssertFalse(measured)
    }

    func testNewTextAndFontInvalidateTheHeightWithoutLosingTheAssignedWidth() {
        var measurement = NativeMarkdownMeasurement()
        XCTAssertEqual(measurement.sizeThatFits(proposedWidth: 320, viewWidth: 320) { _ in 240 }?.height, 240)
        measurement.invalidate()
        XCTAssertEqual(measurement.sizeThatFits(proposedWidth: nil, viewWidth: 300) { _ in 480 }, CGSize(width: 320, height: 480))
    }
}
