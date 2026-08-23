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

    func testBacklogUsesOneFixedReadableStep() {
        let rig = Rig()
        rig.target = String(repeating: "字", count: 18)
        for _ in 0..<10 { rig.pump.stepOnce() }
        XCTAssertEqual(rig.published.last, rig.target)
        var previous = 0
        for prefix in rig.published {
            let step = prefix.count - previous
            XCTAssertEqual(step, min(AgentStreamingDisplayPump.charactersPerTick, rig.target.count - previous))
            XCTAssertTrue(rig.target.hasPrefix(prefix))
            previous = prefix.count
        }
    }

    func testBacklogSizeDoesNotChangeTheStep() {
        let rig = Rig()
        rig.target = String(repeating: "字", count: 1_000)
        rig.pump.stepOnce()
        XCTAssertEqual(rig.published.first?.count, AgentStreamingDisplayPump.charactersPerTick)
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
        XCTAssertEqual(rig.published[0].count, AgentStreamingDisplayPump.charactersPerTick)
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
        rig.target = "内容继续输出"
        let expectedPrefix = String(
            rig.target.prefix(AgentStreamingDisplayPump.charactersPerTick)
        )
        rig.pump.start()
        XCTAssertTrue(rig.pump.isRunning)
        // start() steps once so the first batch keeps its arrival latency.
        XCTAssertEqual(rig.published, [expectedPrefix])
        rig.pump.stopAndReset()
        XCTAssertFalse(rig.pump.isRunning)
        rig.pump.stepOnce()
        // The prefix was forgotten: publication restarts from scratch.
        XCTAssertEqual(rig.published.last, expectedPrefix)
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

    func testStartWaitsOneTickBeforeItsSecondPublish() async {
        let rig = Rig()
        rig.target = String(repeating: "字", count: 20)
        rig.pump.start()
        let synchronousCount = rig.published.count
        await Task.yield()
        XCTAssertEqual(rig.published.count, synchronousCount)
        let deadline = ContinuousClock.now + .seconds(1)
        while rig.published.count == synchronousCount, ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertGreaterThan(rig.published.count, synchronousCount)
        rig.pump.stopAndReset()
    }

    func testWaitUntilCaughtUpKeepsThePacedPublishes() async {
        let rig = Rig()
        rig.target = String(repeating: "字", count: 10)
        rig.pump.start()
        await rig.pump.waitUntilCaughtUp()
        XCTAssertEqual(rig.published.last, rig.target)
        XCTAssertGreaterThan(rig.published.count, 1)
        rig.pump.stopAndReset()
    }
}
