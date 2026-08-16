import CoreGraphics
import XCTest
@testable import WeiBei
import WeiBeiCore

final class PaneSeatMotionTests: XCTestCase {
    private let container = CGRect(x: 0, y: 0, width: 900, height: 600)
    private let rightHalf = CGRect(x: 480, y: 0, width: 420, height: 600)
    private let middle = CGRect(x: 300, y: 0, width: 300, height: 600)

    func testOpenAlwaysUsesThePaneSeat() {
        XCTAssertEqual(
            PaneSeatMotion.openingFrame(for: .reader, target: container),
            CGRect(x: 0, y: 0, width: 0, height: 600)
        )
        XCTAssertEqual(
            PaneSeatMotion.openingFrame(for: .agent, target: middle),
            CGRect(x: 450, y: 0, width: 0, height: 600)
        )
        XCTAssertEqual(
            PaneSeatMotion.openingFrame(for: .notes, target: rightHalf),
            CGRect(x: 900, y: 0, width: 0, height: 600)
        )
    }

    func testNotesOpensFromTheWindowRightEvenAfterReaderIsAlreadyOpen() {
        let start = PaneSeatMotion.openingFrame(for: .notes, target: rightHalf)
        XCTAssertEqual(start.minX, 900)
        XCTAssertEqual(start.width, 0)
        XCTAssertGreaterThan(start.minX, rightHalf.minX)
    }

    func testCloseReturnsToTheSameSeat() {
        XCTAssertEqual(
            PaneSeatMotion.closingFrame(for: .reader, current: container, container: container),
            CGRect(x: 0, y: 0, width: 0, height: 600)
        )
        XCTAssertEqual(
            PaneSeatMotion.closingFrame(for: .agent, current: middle, container: container),
            CGRect(x: 450, y: 0, width: 0, height: 600)
        )
        XCTAssertEqual(
            PaneSeatMotion.closingFrame(for: .notes, current: rightHalf, container: container),
            CGRect(x: 900, y: 0, width: 0, height: 600)
        )
    }

    func testMissingCurrentFrameFallsBackToTheContainerSeat() {
        XCTAssertEqual(
            PaneSeatMotion.closingFrame(for: .notes, current: nil, container: container),
            CGRect(x: 900, y: 0, width: 0, height: 600)
        )
        XCTAssertEqual(
            PaneSeatMotion.closingFrame(for: .agent, current: .zero, container: container),
            CGRect(x: 450, y: 0, width: 0, height: 600)
        )
    }
}
