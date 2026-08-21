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
            queue.requestBootSlot(id: id, isInViewport: nil)
        }
        // Unprobed rows wait one admission tick so viewport probes can rank them.
        XCTAssertTrue(queue.admittedIDs.isEmpty)
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(ids[0]))
        XCTAssertTrue(queue.isAdmitted(ids[1]))
        XCTAssertFalse(queue.isAdmitted(ids[2]))
        XCTAssertFalse(queue.isAdmitted(ids[3]))
        XCTAssertEqual(queue.admittedIDs.count, 2)

        queue.release(ids[0])
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(ids[2]), "releasing a settled slot admits the next pending row")
        XCTAssertFalse(queue.isAdmitted(ids[3]))
        XCTAssertEqual(queue.admittedIDs.count, 2)

        queue.release(ids[1])
        queue.release(ids[2])
        queue.release(ids[3])
        XCTAssertTrue(queue.admittedIDs.isEmpty)
    }

    func testVisibleRowsAreAdmittedImmediatelyAndOutrankOthers() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let offscreen = makeIDs(3)
        let visible = UUID()
        for id in offscreen {
            queue.requestBootSlot(id: id, isInViewport: false)
        }
        // Offscreen rows are deferred to the admission tick.
        XCTAssertFalse(queue.isAdmitted(offscreen[0]))

        queue.requestBootSlot(id: visible, isInViewport: true)
        XCTAssertTrue(
            queue.isAdmitted(visible),
            "a visible row bypasses the deferral and takes a free slot immediately"
        )

        queue.release(visible)
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(offscreen[0]), "offscreen rows resume in request order after the tick")
        queue.release(offscreen[0])
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(offscreen[1]))
        queue.release(offscreen[1])
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(offscreen[2]))
    }

    func testProbePromotesPendingRowWithoutLosingAdmittedSlot() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 2, slotTimeout: 12)
        let ids = makeIDs(4)
        for id in ids {
            queue.requestBootSlot(id: id, isInViewport: false)
        }
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(ids[0]))
        XCTAssertTrue(queue.isAdmitted(ids[1]))

        // The probe reports ids[3] as on-screen; it must jump past ids[2].
        queue.requestBootSlot(id: ids[3], isInViewport: true)
        queue.release(ids[0])
        XCTAssertTrue(queue.isAdmitted(ids[3]))
        XCTAssertFalse(queue.isAdmitted(ids[2]))

        // Re-requesting an admitted row neither drops its slot nor double-admits.
        queue.requestBootSlot(id: ids[3], isInViewport: false)
        XCTAssertTrue(queue.isAdmitted(ids[3]))
        XCTAssertEqual(queue.admittedIDs.count, 2)
    }

    func testUnprobedRowsOutrankOffscreenRowsAfterTick() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let offscreen = UUID()
        let unprobed = UUID()
        queue.requestBootSlot(id: offscreen, isInViewport: false)
        queue.requestBootSlot(id: unprobed, isInViewport: nil)
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(unprobed), "unprobed ranks above a known-offscreen row")

        queue.release(unprobed)
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(offscreen))
    }

    func testRequestIsIdempotentWhilePending() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let busy = UUID()
        let pendingID = UUID()
        queue.requestBootSlot(id: busy, isInViewport: true)
        queue.requestBootSlot(id: pendingID, isInViewport: true)
        queue.requestBootSlot(id: pendingID, isInViewport: true)

        queue.release(busy)
        XCTAssertTrue(queue.isAdmitted(pendingID))
        XCTAssertEqual(queue.admittedIDs.count, 1)
    }

    func testReclaimOverdueSlotsFreesStuckAdmission() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let stuck = UUID()
        let next = UUID()
        queue.requestBootSlot(id: stuck, isInViewport: true)
        queue.requestBootSlot(id: next, isInViewport: false)

        let start = Date()
        queue.reclaimOverdueSlots(asOf: start.addingTimeInterval(5))
        XCTAssertTrue(queue.isAdmitted(stuck), "a slot younger than the timeout is untouched")

        queue.reclaimOverdueSlots(asOf: start.addingTimeInterval(13))
        XCTAssertFalse(queue.isAdmitted(stuck), "an overdue slot is reclaimed")
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(next), "the reclaimed slot is handed to the next row")
    }

    func testReleaseUnknownIDIsSafe() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 1, slotTimeout: 12)
        let unknown = UUID()
        queue.release(unknown)
        XCTAssertTrue(queue.admittedIDs.isEmpty)

        let id = UUID()
        queue.requestBootSlot(id: id, isInViewport: false)
        queue.admitPendingRowsForTesting()
        queue.release(unknown)
        XCTAssertTrue(queue.isAdmitted(id), "releasing an unknown id never disturbs live slots")

        // Releasing a pending request cancels it without admitting anything else.
        let pendingID = UUID()
        queue.requestBootSlot(id: pendingID, isInViewport: false)
        queue.release(id)
        queue.admitPendingRowsForTesting()
        XCTAssertTrue(queue.isAdmitted(pendingID))
        queue.release(pendingID)
        XCTAssertTrue(queue.admittedIDs.isEmpty)
    }

    func testConcurrencyLimitClampsToAtLeastOne() {
        let queue = AgentChatMarkdownBootQueue(concurrentBootLimit: 0, slotTimeout: 12)
        let ids = makeIDs(2)
        queue.requestBootSlot(id: ids[0], isInViewport: true)
        queue.requestBootSlot(id: ids[1], isInViewport: true)
        XCTAssertTrue(queue.isAdmitted(ids[0]))
        XCTAssertFalse(queue.isAdmitted(ids[1]))
    }
}
