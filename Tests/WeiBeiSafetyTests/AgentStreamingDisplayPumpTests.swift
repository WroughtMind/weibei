import XCTest
import SwiftUI
@testable import WeiBei
import WeiBeiCore

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

    func testInitialAndRefillBothBufferBeforePublishing() async {
        let rig = Rig()
        rig.pump.enqueue(cumulativeText: "甲乙丙丁")
        XCTAssertTrue(rig.chunks.isEmpty)
        await waitUntil { rig.chunks.count == 1 }

        rig.pump.enqueue(cumulativeText: "甲乙丙丁戊己庚辛")
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

    func testCompletedReplyKeepsItsVisiblePrefixUntilTheDisplayQueueDrains() {
        let run = AgentConversationRun(chatID: UUID())
        let message = AgentMessage(role: .assistant, text: "一二三四五六七八九十", source: nil)
        run.streaming.begin(messageID: message.id, chatID: run.chatID!)
        run.pump.enqueue(cumulativeText: message.text)
        run.pump.stepOnce()
        run.pump.finish(cumulativeText: message.text)
        XCTAssertEqual(run.streaming.applyingDisplayText(to: message).text, "一二三四")
        XCTAssertEqual(message.text, "一二三四五六七八九十")
        XCTAssertEqual(message.completionState, .completed)
        XCTAssertEqual(run.streaming.applyingDisplayText(to: message).completionState, .generating)
        while run.pump.pendingCharacterCount > 0 { run.pump.stepOnce() }
        XCTAssertEqual(run.streaming.applyingDisplayText(to: message).text, message.text)
        XCTAssertFalse(run.streaming.isDisplaying(message.id))
    }

    func testToolGroupsFollowTextBoundariesWithoutRevealingFutureActivity() throws {
        let text = "先👨‍👩‍👧‍👦查后答"
        let activities = [
            AgentToolActivity(id: "1", name: "search", state: .completed, textOffset: 2),
            AgentToolActivity(id: "2", name: "read", state: .completed, textOffset: 2),
            AgentToolActivity(id: "3", name: "read", state: .running, textOffset: 4)
        ]
        let early = AgentNativeMessageContent.markdown(text: String(text.prefix(1)), blocks: [], activities: activities)
        XCTAssertEqual(early, "先")
        let output = AgentNativeMessageContent.markdown(text: text, blocks: [], activities: activities)
        XCTAssertEqual(output, "先👨‍👩‍👧‍👦\n\n![图示](weibei-visualization:activity/2)\n\n查后\n\n![图示](weibei-visualization:activity/4)\n\n答")
        let start = activities[0]
        let completed = start.merging(.init(id: "1", name: "search", state: .completed, textOffset: 5))
        XCTAssertEqual(completed.textOffset, 2)
        XCTAssertEqual(try JSONDecoder().decode(AgentToolActivity.self, from: JSONEncoder().encode(completed)), completed)
    }

    func testActivityInterleavesWithRichContentAndRespectsVisiblePrefix() {
        let blocks: [AgentMessageContentBlock] = [.text("先查"), .unavailable(type: "example", rawJSON: "{}"), .text("后答")]
        let activities = [AgentToolActivity(id: "1", name: "read", state: .completed, textOffset: 2)]
        let early = AgentNativeMessageContent.markdown(text: "先", blocks: blocks, activities: activities)
        XCTAssertEqual(early, "先")
        let output = AgentNativeMessageContent.markdown(text: "先查后答", blocks: blocks, activities: activities)
        XCTAssertEqual(output, "先查\n\n![图示](weibei-visualization:activity/2)\n\n\n\n![图示](weibei-visualization:unavailable-1)\n\n后答")
    }

    func testActivityDisclosureUsesCompactNativeLayout() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = WorkspaceStore(workspaceDirectory: folder, selectionAskThreadDefaults: defaults,
                                   startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        var message = AgentMessage(role: .assistant, text: "回答", source: nil)
        message.toolActivities = [
            .init(id: "search", name: "$web_search", state: .completed,
                  detail: String(repeating: "很长的搜索查询 ", count: 20),
                  sourceURLs: (1...44).map { "https://example.com/article/\($0)" }),
            .init(id: "read", name: "weibei_course_read", state: .completed, detail: "课程讲义，第 8 页")
        ]
        var heights: [CGFloat] = []
        for expanded in [false, true] {
            let renderer = ImageRenderer(content: AgentToolActivityGroup(message: message, autoOpen: expanded)
                .environmentObject(store).frame(width: 640).padding(24).background(WeiBeiTheme.paper))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            heights.append(image.size.height)
            if let directory = ProcessInfo.processInfo.environment["WEIBEI_ACTIVITY_PREVIEW_DIR"] {
                let url = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                    url.appendingPathComponent(expanded ? "expanded.png" : "collapsed.png"))
            }
        }
        XCTAssertGreaterThan(heights[1], heights[0])
        XCTAssertLessThan(heights[1], 150, "Opening a group must not lay out query details or 44 sources")
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }
}
