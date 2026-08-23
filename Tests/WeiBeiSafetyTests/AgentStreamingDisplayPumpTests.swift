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

    func testBacklogDecaysSmoothlyToTypingPace() {
        let rig = Rig()
        rig.target = String(repeating: "字", count: 10)
        for _ in 0..<10 { rig.pump.stepOnce() }
        XCTAssertEqual(rig.published.last, rig.target)
        // Rate derives from the live deficit: a 10-character backlog starts at
        // 2/tick and decays toward single characters without step-size jumps.
        var previous = 0
        for prefix in rig.published {
            let step = prefix.count - previous
            XCTAssertTrue(step == 1 || step == 2, "unexpected step \(step)")
            XCTAssertTrue(rig.target.hasPrefix(prefix))
            previous = prefix.count
        }
    }

    func testLargerBacklogKeepsBoundedEvenSteps() {
        let rig = Rig()
        rig.target = String(repeating: "字", count: 15)
        for _ in 0..<15 { rig.pump.stepOnce() }
        XCTAssertEqual(rig.published.last, rig.target)
        // Deficit 15 paces at ≤2.5 characters per tick: steps stay within 1…3.
        var previous = 0
        for prefix in rig.published {
            let step = prefix.count - previous
            XCTAssertTrue((1...3).contains(step), "unexpected step \(step)")
            previous = prefix.count
        }
    }

    func testVeryLargeBacklogUsesRaisedButBoundedCatchUpRate() {
        let rig = Rig()
        rig.target = String(repeating: "字", count: 1_000)
        rig.pump.stepOnce()
        XCTAssertEqual(rig.published.first?.count, AgentStreamingDisplayPump.maximumCharsPerTick)
    }

    func testEmptyTargetPublishesNothing() {
        let rig = Rig()
        for _ in 0..<5 { rig.pump.stepOnce() }
        XCTAssertTrue(rig.published.isEmpty)
    }

    func testHiddenChatPausesAndCatchesUpWhenShown() {
        let rig = Rig()
        rig.canPublish = false
        rig.target = String(repeating: "字", count: 30)
        for _ in 0..<3 { rig.pump.stepOnce() }
        XCTAssertTrue(rig.published.isEmpty)
        rig.canPublish = true
        rig.pump.stepOnce()
        XCTAssertEqual(rig.published.count, 1)
        // Deficit 30 paces at 1 + 30/10 = 4 characters per tick: a bulk step.
        XCTAssertEqual(rig.published[0].count, 4)
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
