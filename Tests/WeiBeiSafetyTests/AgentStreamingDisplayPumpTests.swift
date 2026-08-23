import XCTest
@testable import WeiBei

@MainActor
final class AgentStreamingDisplayPumpTests: XCTestCase {
    @MainActor
    private final class Rig {
        private(set) var displayed = ""
        private(set) var chunks: [String] = []
        private(set) var replacements: [String] = []
        private(set) var drainCount = 0

        lazy var pump = AgentStreamingDisplayPump(hooks: .init(
            append: { [weak self] chunk in
                self?.displayed.append(chunk)
                self?.chunks.append(chunk)
            },
            replace: { [weak self] text in
                self?.displayed = text
                self?.replacements.append(text)
            },
            didDrain: { [weak self] in self?.drainCount += 1 }
        ))
    }

    func testFixedQueueConsumesAtMostFourCharactersPerTick() {
        let rig = Rig()
        let target = String(repeating: "字", count: 18)
        rig.pump.enqueue(cumulativeText: target)
        while rig.pump.pendingCharacterCount > 0 { rig.pump.stepOnce() }

        XCTAssertEqual(rig.displayed, target)
        XCTAssertEqual(rig.chunks.map(\.count), [4, 4, 4, 4, 2])
        XCTAssertEqual(AgentStreamingDisplayPump.tickNanoseconds, 33_000_000)
    }

    func testTenThousandCharacterBacklogUsesOnlyTwoGentleSpeeds() {
        let rig = Rig()
        let target = String(repeating: "长", count: 10_000)
        rig.pump.enqueue(cumulativeText: target)
        while rig.pump.pendingCharacterCount > 0 { rig.pump.stepOnce() }

        XCTAssertEqual(rig.displayed, target)
        XCTAssertEqual(rig.chunks.first?.count, AgentStreamingDisplayPump.catchUpCharactersPerTick)
        guard let firstNormalIndex = rig.chunks.firstIndex(where: {
            $0.count == AgentStreamingDisplayPump.charactersPerTick
        }) else {
            XCTFail("catch-up mode never returned to the normal speed")
            return
        }
        XCTAssertFalse(rig.chunks.dropFirst(firstNormalIndex).contains {
            $0.count == AgentStreamingDisplayPump.catchUpCharactersPerTick
        })
        XCTAssertTrue(rig.chunks.dropLast().allSatisfy {
            $0.count == AgentStreamingDisplayPump.charactersPerTick
                || $0.count == AgentStreamingDisplayPump.catchUpCharactersPerTick
        })
        XCTAssertEqual(AgentStreamingDisplayPump.catchUpBacklogThreshold, 120)
        XCTAssertEqual(AgentStreamingDisplayPump.normalBacklogThreshold, 40)
    }

    func testCumulativeSnapshotsEnqueueOnlyTheirNewSuffix() {
        let rig = Rig()
        rig.pump.enqueue(cumulativeText: "你好")
        rig.pump.stepOnce()
        rig.pump.enqueue(cumulativeText: "你好世界")
        rig.pump.stepOnce()

        XCTAssertEqual(rig.displayed, "你好世界")
        XCTAssertEqual(rig.chunks, ["你好", "世界"])
    }

    func testInitialAndRefillBothWaitForBuffer() async {
        let rig = Rig()
        rig.pump.enqueue(cumulativeText: "甲乙丙丁")
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(rig.chunks.isEmpty)
        await waitUntil { rig.chunks.count == 1 }

        rig.pump.enqueue(cumulativeText: "甲乙丙丁戊己庚辛")
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(rig.chunks.count, 1)
        await waitUntil { rig.chunks.count == 2 }
        XCTAssertEqual(AgentStreamingDisplayPump.bufferNanoseconds, 80_000_000)
    }

    func testSwiftCharactersAreNeverSplit() {
        let rig = Rig()
        let text = "👨‍👩‍👧‍👦e\u{301}中文"
        rig.pump.enqueue(cumulativeText: text)
        rig.pump.stepOnce()

        XCTAssertEqual(text.count, 4)
        XCTAssertEqual(rig.chunks, [text])
    }

    func testDataCompletionReturnsBeforeVisualQueueDrains() {
        let rig = Rig()
        let text = String(repeating: "尾", count: 12)
        rig.pump.finish(cumulativeText: text)

        XCTAssertEqual(rig.drainCount, 0)
        XCTAssertEqual(rig.pump.pendingCharacterCount, 12)
        while rig.pump.pendingCharacterCount > 0 { rig.pump.stepOnce() }
        XCTAssertEqual(rig.displayed, text)
        XCTAssertEqual(rig.drainCount, 1)
    }

    func testProviderRewriteLandsOneAuthoritativeSnapshot() {
        let rig = Rig()
        rig.pump.enqueue(cumulativeText: "旧内容")
        rig.pump.stepOnce()
        rig.pump.enqueue(cumulativeText: "新内容")

        XCTAssertEqual(rig.displayed, "新内容")
        XCTAssertEqual(rig.replacements, ["新内容"])
        XCTAssertEqual(rig.pump.pendingCharacterCount, 0)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }
}
