import XCTest
@testable import WeiBei

@MainActor
final class AgentStreamingDisplayPumpTests: XCTestCase {
    @MainActor
    private final class Rig {
        var target = ""
        var canPublish = true
        private(set) var published: [String] = []
        lazy var pump = AgentStreamingDisplayPump(hooks: .init(
            targetText: { [weak self] in self?.target ?? "" },
            publish: { [weak self] in self?.published.append($0) },
            canPublish: { [weak self] in self?.canPublish ?? false }
        ))
    }

    func testSteadyStateAdvancesOneCharacterPerTick() {
        let rig = Rig()
        rig.target = "你"
        rig.pump.stepOnce()
        rig.target = "你好"
        rig.pump.stepOnce()
        rig.pump.stepOnce()
        XCTAssertEqual(rig.published, ["你", "你好"])
    }

    func testBacklogCatchesUpGeometricallyWithoutExceedingTarget() {
        let rig = Rig()
        rig.target = String(repeating: "字", count: 10)
        for _ in 0..<10 { rig.pump.stepOnce() }
        XCTAssertEqual(rig.published.last, rig.target)
        // Deficits 10→7→5→4→3→2→1→0 advance 3,2,1,1,1,1,1: seven publications.
        XCTAssertEqual(rig.published.count, 7)
        var longest = 0
        for prefix in rig.published {
            XCTAssertLessThanOrEqual(longest, prefix.count)
            XCTAssertTrue(rig.target.hasPrefix(prefix))
            longest = prefix.count
        }
    }

    func testEmptyTargetPublishesNothing() {
        let rig = Rig()
        for _ in 0..<5 { rig.pump.stepOnce() }
        XCTAssertTrue(rig.published.isEmpty)
    }

    func testHiddenChatPausesAndCatchesUpWhenShown() {
        let rig = Rig()
        rig.canPublish = false
        rig.target = "一二三四五六七八"
        for _ in 0..<3 { rig.pump.stepOnce() }
        XCTAssertTrue(rig.published.isEmpty)
        rig.canPublish = true
        rig.pump.stepOnce()
        XCTAssertEqual(rig.published.count, 1)
        // Deficit 8 exceeds the runway, so the first visible tick is a bulk step.
        XCTAssertGreaterThan(rig.published[0].count, 1)
        XCTAssertTrue(rig.target.hasPrefix(rig.published[0]))
    }

    func testNonPrefixTargetSnapsToFullText() {
        let rig = Rig()
        rig.target = "AAAAAAAAAA"
        rig.pump.stepOnce()
        rig.target = "BBBB"
        rig.pump.stepOnce()
        XCTAssertEqual(rig.published.last, "BBBB")
    }

    func testStopAndResetDropsLoopAndForgetsPrefix() {
        let rig = Rig()
        rig.target = "内容"
        rig.pump.start()
        XCTAssertTrue(rig.pump.isRunning)
        // start() steps once so the first character keeps its arrival latency.
        XCTAssertEqual(rig.published, ["内"])
        rig.pump.stopAndReset()
        XCTAssertFalse(rig.pump.isRunning)
        rig.pump.stepOnce()
        // The prefix was forgotten: publication restarts from scratch.
        XCTAssertEqual(rig.published.last, "内")
        XCTAssertEqual(rig.published.count, 2)
    }

    func testRunLoopPublishesMonotonicPrefixesOverTime() async {
        let rig = Rig()
        rig.target = "逐字流式输出测试"
        rig.pump.start()
        try? await Task.sleep(nanoseconds: 500_000_000)
        rig.pump.stopAndReset()
        XCTAssertFalse(rig.published.isEmpty)
        XCTAssertEqual(rig.published.last, rig.target)
        var longest = 0
        for prefix in rig.published {
            XCTAssertLessThanOrEqual(longest, prefix.count)
            longest = prefix.count
        }
    }
}
