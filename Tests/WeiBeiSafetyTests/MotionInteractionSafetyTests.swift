import Foundation
import XCTest
@testable import WeiBei

/// Targeted guards for the interaction/motion rework: expansion-request acks,
/// transient status generations, and the latest-first PDF render queue.
final class MotionInteractionSafetyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    private func makeStore() -> WorkspaceStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiMotionChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        return WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
    }

    /// A stale ack must never run a completion; the newest request's completion
    /// runs exactly once, and a replaced request drops its closure silently.
    @MainActor
    func testPaneExpansionAckRunsOnlyLatestCompletionOnce() {
        let store = makeStore()

        var navigated: [String] = []
        var secondRunCount = 0
        store.requestPaneExpansion(.notes) {
            navigated.append("A")
        }
        let firstRequestID = store.paneExpansionRequest!.id
        store.requestPaneExpansion(.notes) {
            navigated.append("B")
            secondRunCount += 1
        }

        // The AppKit layer acks the first (now superseded) request.
        store.completePaneExpansionRequest(firstRequestID)
        XCTAssertEqual(navigated, [], "a superseded request's completion must not run")

        // Ack for the current request runs its closure exactly once.
        let secondRequestID = store.paneExpansionRequest!.id
        store.completePaneExpansionRequest(secondRequestID)
        store.completePaneExpansionRequest(secondRequestID)
        XCTAssertEqual(navigated, ["B"])
        XCTAssertEqual(secondRunCount, 1)
        XCTAssertNil(store.paneExpansionRequest)
    }

    /// Identical transient text is a new identity each time: the second showing
    /// keeps its own full 2.4s window and cannot be cleared by the first task.
    @MainActor
    func testRepeatedTransientStatusKeepsFullSecondWindow() async throws {
        let store = makeStore()
        let message = "已复制"
        store.showTransientNoteStatus(message)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        store.showTransientNoteStatus(message)
        try await Task.sleep(nanoseconds: 1_100_000_000)

        // 2.6s after the FIRST showing (2.4s + margin): the old identity-token
        // implementation would already have cleared the second window.
        XCTAssertEqual(store.transientNoteStatus, message, "the first task must not clear the second showing")

        try await Task.sleep(nanoseconds: 1_600_000_000)
        XCTAssertNil(store.transientNoteStatus, "the second window still expires on its own")
    }

    /// A newer message always wins; its task cannot be cleared by an older one.
    @MainActor
    func testNewerTransientMessageSupersedesOlderTask() async throws {
        let store = makeStore()
        store.showTransientNoteStatus("A")
        try await Task.sleep(nanoseconds: 200_000_000)
        store.showTransientNoteStatus("B")
        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertNil(store.transientNoteStatus, "only the newest generation may clear the slot")
    }

    /// Important errors never auto-dismiss and closing one leaves the transient
    /// channel untouched.
    @MainActor
    func testImportantErrorPersistsUntilDismissed() async throws {
        let store = makeStore()
        store.showTransientNoteStatus("临时提示")
        store.showImportantOperationError("无法写入笔记")

        try await Task.sleep(nanoseconds: 3_000_000_000)
        XCTAssertEqual(store.importantOperationError, "无法写入笔记", "important errors must not auto-expire")
        XCTAssertEqual(store.transientNoteStatus, nil, "the transient status still expires independently")

        store.dismissImportantOperationError()
        XCTAssertNil(store.importantOperationError)
    }

    /// Recovery retracts the banner: when a note's file error clears and the
    /// banner still shows that exact message (with no other item failing on the
    /// same message), the banner is dismissed instead of lingering as a false alarm.
    @MainActor
    func testNoteFileErrorRecoveryRetractsMatchingBanner() {
        let store = makeStore()
        let message = "无法定位笔记文件，正文展示已降级为模板；已暂停自动写回以保护磁盘内容。"
        store.setNoteFileError(message, for: "note-a")
        store.showImportantOperationError(message)

        store.setNoteFileError(nil, for: "note-a")
        XCTAssertNil(store.importantOperationError, "a recovered note error must not leave a stale banner")
    }

    /// The retract only fires for the exact message still on screen: a newer or
    /// different banner is left alone, and another item failing on the same
    /// message keeps the banner up.
    @MainActor
    func testNoteFileErrorRecoveryKeepsUnrelatedOrSharedBanner() {
        let store = makeStore()
        let message = "无法定位笔记文件，正文展示已降级为模板；已暂停自动写回以保护磁盘内容。"

        store.setNoteFileError(message, for: "note-a")
        store.showImportantOperationError("另一条重要错误")
        store.setNoteFileError(nil, for: "note-a")
        XCTAssertEqual(store.importantOperationError, "另一条重要错误", "a different banner must not be dismissed")

        store.setNoteFileError(message, for: "note-a")
        store.setNoteFileError(message, for: "note-b")
        store.showImportantOperationError(message)
        store.setNoteFileError(nil, for: "note-a")
        XCTAssertEqual(store.importantOperationError, message, "note-b still fails on the same message, so the banner stays")
    }

    /// The render-queue admission policy: the executing page finishes, queued
    /// pages are cancelled, so after the blocked page the LATEST page runs next
    /// and the stale middle page never renders.
    func testLatestFirstSerialQueueRunsBlockedThenLatestOnly() {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let started = DispatchSemaphore(value: 0)
        let releaseBlocker = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        var order: [Int] = []
        let orderLock = NSLock()

        let record: (Int) -> Void = { value in
            orderLock.lock()
            order.append(value)
            orderLock.unlock()
        }

        let blocker = BlockOperation {
            record(0)
            started.signal()
            releaseBlocker.wait()
        }
        LatestFirstSerialQueue.enqueue(blocker, on: queue)
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success, "blocked render A must be executing")

        // B then C arrive while A is still rendering.
        LatestFirstSerialQueue.enqueue(BlockOperation { record(1) }, on: queue)
        let stale = queue.operations.first { !$0.isExecuting && !$0.isCancelled }
        XCTAssertNotNil(stale)
        let latest = BlockOperation {
            record(2)
            finished.signal()
        }
        LatestFirstSerialQueue.enqueue(latest, on: queue)

        let staleCancelled = queue.operations.filter { !$0.isExecuting && $0.isCancelled }
        XCTAssertEqual(staleCancelled.count, 1, "the queued-but-unstarted older page must be cancelled")

        releaseBlocker.signal()
        XCTAssertEqual(finished.wait(timeout: .now() + 2), .success, "the latest page must render after the blocked one")
        queue.waitUntilAllOperationsAreFinished()

        XCTAssertEqual(order, [0, 2], "execution order must be blocked-then-latest; the stale middle page never runs")
    }
}
