import CoreGraphics
import XCTest
@testable import WeiBei
import WeiBeiCore

final class EmptyBoardPaneEntranceTests: XCTestCase {
    private let target = CGRect(x: 0, y: 0, width: 900, height: 600)

    func testEmptyBoardOpensEachPaneFromItsSeat() {
        let reader = EmptyBoardPaneEntrance.openingFrame(
            for: .reader, target: target, fromEmptyBoard: true
        )
        let agent = EmptyBoardPaneEntrance.openingFrame(
            for: .agent, target: target, fromEmptyBoard: true
        )
        let notes = EmptyBoardPaneEntrance.openingFrame(
            for: .notes, target: target, fromEmptyBoard: true
        )

        XCTAssertEqual(reader, CGRect(x: 0, y: 0, width: 0, height: 600))
        XCTAssertEqual(agent, CGRect(x: 450, y: 0, width: 0, height: 600))
        XCTAssertEqual(notes, CGRect(x: 900, y: 0, width: 0, height: 600))
    }

    func testLaterInsertStillGrowsFromTargetLeadingEdge() {
        let notesTarget = CGRect(x: 480, y: 0, width: 420, height: 600)
        let start = EmptyBoardPaneEntrance.openingFrame(
            for: .notes, target: notesTarget, fromEmptyBoard: false
        )
        XCTAssertEqual(start, CGRect(x: 480, y: 0, width: 0, height: 600))
    }
}
