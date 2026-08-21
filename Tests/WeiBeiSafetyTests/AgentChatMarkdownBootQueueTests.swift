import XCTest
import WeiBeiCore

@MainActor
final class AgentChatMarkdownBootQueueTests: XCTestCase {

    private func makeIDs(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    func testAdmitsUpToConcurrencyLimitInRequestOrder() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 2, slotTimeout: 12)
        let ids = makeIDs(4)
        for id in ids {
            queue.requestBootSlot(id: id, visible: false)
        }
        XCTAssertTrue(queue.isAdmitted(ids[0]))
        XCTAssertTrue(queue.isAdmitted(ids[1]))
        XCTAssertFalse(queue.isAdmitted(ids[2]))
        XCTAssertFalse(queue.isAdmitted(ids[3]))
        XCTAssertEqual(queue.admittedIDs.count, 2)

        queue.release(ids[0])
        XCTAssertTrue(queue.isAdmitted(ids[2]), "releasing a settled slot admits the next pending row")
        XCTAssertFalse(queue.isAdmitted(ids[3]))
        XCTAssertEqual(queue.admittedIDs.count, 2)

        queue.release(ids[1])
        queue.release(ids[2])
        queue.release(ids[3])
        XCTAssertTrue(queue.admittedIDs.isEmpty)
    }

    func testVisibleRowsOutrankOffscreenRows() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let offscreen = makeIDs(3)
        let visible = UUID()
        for id in offscreen {
            queue.requestBootSlot(id: id, visible: false)
        }
        XCTAssertTrue(queue.isAdmitted(offscreen[0]))

        queue.requestBootSlot(id: visible, visible: true)
        XCTAssertFalse(queue.isAdmitted(visible), "the busy slot is not preempted")

        queue.release(offscreen[0])
        XCTAssertTrue(queue.isAdmitted(visible), "a visible row takes the next slot over older offscreen rows")

        queue.release(visible)
        XCTAssertTrue(queue.isAdmitted(offscreen[1]), "offscreen rows resume in request order")
        queue.release(offscreen[1])
        XCTAssertTrue(queue.isAdmitted(offscreen[2]))
    }

    func testVisibilityChangePromotesPendingRowWithoutLosingSlot() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 2, slotTimeout: 12)
        let ids = makeIDs(4)
        for id in ids {
            queue.requestBootSlot(id: id, visible: false)
        }
        XCTAssertTrue(queue.isAdmitted(ids[0]))
        XCTAssertTrue(queue.isAdmitted(ids[1]))

        // The probe reports ids[3] as on-screen; it must jump past ids[2].
        queue.requestBootSlot(id: ids[3], visible: true)
        queue.release(ids[0])
        XCTAssertTrue(queue.isAdmitted(ids[3]))
        XCTAssertFalse(queue.isAdmitted(ids[2]))

        // Re-requesting an admitted row neither drops its slot nor double-admits.
        queue.requestBootSlot(id: ids[3], visible: false)
        XCTAssertTrue(queue.isAdmitted(ids[3]))
        XCTAssertEqual(queue.admittedIDs.count, 2)
    }

    func testRequestIsIdempotentWhilePending() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let busy = UUID()
        let pendingID = UUID()
        queue.requestBootSlot(id: busy, visible: false)
        queue.requestBootSlot(id: pendingID, visible: true)
        queue.requestBootSlot(id: pendingID, visible: true)

        queue.release(busy)
        XCTAssertTrue(queue.isAdmitted(pendingID))
        XCTAssertEqual(queue.admittedIDs.count, 1)
    }

    func testReclaimOverdueSlotsFreesStuckAdmission() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let stuck = UUID()
        let next = UUID()
        queue.requestBootSlot(id: stuck, visible: true)
        queue.requestBootSlot(id: next, visible: false)

        let start = Date()
        queue.reclaimOverdueSlots(asOf: start.addingTimeInterval(5))
        XCTAssertTrue(queue.isAdmitted(stuck), "a slot younger than the timeout is untouched")

        queue.reclaimOverdueSlots(asOf: start.addingTimeInterval(13))
        XCTAssertFalse(queue.isAdmitted(stuck), "an overdue slot is reclaimed")
        XCTAssertTrue(queue.isAdmitted(next), "the reclaimed slot is handed to the next row")
    }

    func testReleaseUnknownIDIsSafe() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let unknown = UUID()
        queue.release(unknown)
        XCTAssertTrue(queue.admittedIDs.isEmpty)

        let id = UUID()
        queue.requestBootSlot(id: id, visible: false)
        queue.release(unknown)
        XCTAssertTrue(queue.isAdmitted(id), "releasing an unknown id never disturbs live slots")

        // Releasing a pending request cancels it without admitting anything else.
        let pendingID = UUID()
        queue.requestBootSlot(id: pendingID, visible: false)
        queue.release(id)
        XCTAssertTrue(queue.isAdmitted(pendingID))
        queue.release(pendingID)
        XCTAssertTrue(queue.admittedIDs.isEmpty)
    }

    func testConcurrencyLimitClampsToAtLeastOne() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 0, slotTimeout: 12)
        let ids = makeIDs(2)
        queue.requestBootSlot(id: ids[0], visible: false)
        queue.requestBootSlot(id: ids[1], visible: false)
        XCTAssertTrue(queue.isAdmitted(ids[0]))
        XCTAssertFalse(queue.isAdmitted(ids[1]))
    }
}
