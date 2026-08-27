import XCTest
@testable import WeiBei
import WeiBeiCore

final class AgentMessageViewportWindowTests: XCTestCase {
    override func tearDown() {
        AgentChatOffscreenUnloadFlag.resetForTesting()
        AgentFinalizedMarkdownHeightCache.resetForTesting()
        super.tearDown()
    }

    func testOffscreenUnloadFlagDefaultsOff() {
        AgentChatOffscreenUnloadFlag.resetForTesting()
        XCTAssertFalse(AgentChatOffscreenUnloadFlag.isEnabled)
        AgentChatOffscreenUnloadFlag.setEnabledForTesting(true)
        XCTAssertTrue(AgentChatOffscreenUnloadFlag.isEnabled)
        AgentChatOffscreenUnloadFlag.setEnabledForTesting(false)
        XCTAssertFalse(AgentChatOffscreenUnloadFlag.isEnabled)
    }

    func testRowsBeyondThreeScreensBecomePlaceholders() {
        // Ten 400pt rows. One screen = 400pt at the top.
        // Keep band = [-1200, 1600]. Rows whose [min,max] stay inside stay mounted.
        let heights: [CGFloat?] = Array(repeating: 400, count: 10)
        let placeholders = AgentMessageViewportWindow.placeholderIndices(
            heights: heights,
            viewportMinY: 0,
            viewportHeight: 400
        )
        XCTAssertEqual(AgentMessageViewportWindow.extraScreens, 3)
        XCTAssertFalse(placeholders.contains(0), "on-screen row stays mounted")
        XCTAssertFalse(placeholders.contains(3), "row at y=1200 still intersects the 3-screen band")
        XCTAssertTrue(placeholders.contains(4), "row at y=1600 is exactly 3 screens below and should placeholder")
        XCTAssertTrue(placeholders.contains(9))
        XCTAssertEqual(placeholders, [4, 5, 6, 7, 8, 9])
    }

    func testRowsNearALowerViewportStayMounted() {
        let heights: [CGFloat?] = Array(repeating: 400, count: 10)
        // Viewport covers the last row (y=3600). Keep band = [2400, 5200].
        let placeholders = AgentMessageViewportWindow.placeholderIndices(
            heights: heights,
            viewportMinY: 3600,
            viewportHeight: 400
        )
        XCTAssertTrue(placeholders.contains(0))
        XCTAssertTrue(placeholders.contains(5), "row at y=2000 is above the 3-screen band")
        XCTAssertFalse(placeholders.contains(6), "row at y=2400 sits on the keep-band edge")
        XCTAssertFalse(placeholders.contains(9), "on-screen last row stays mounted")
    }

    func testMissingCachedHeightIsNeverAPlaceholder() {
        var heights: [CGFloat?] = Array(repeating: 400, count: 10)
        heights[9] = nil
        let placeholders = AgentMessageViewportWindow.placeholderIndices(
            heights: heights,
            viewportMinY: 0,
            viewportHeight: 400
        )
        XCTAssertTrue(placeholders.contains(4))
        XCTAssertFalse(
            placeholders.contains(9),
            "a far row without a cached height must stay mounted to avoid collapse"
        )
    }

    func testZeroViewportDoesNotPlaceholder() {
        let heights: [CGFloat?] = Array(repeating: 400, count: 8)
        let placeholders = AgentMessageViewportWindow.placeholderIndices(
            heights: heights,
            viewportMinY: 0,
            viewportHeight: 0
        )
        XCTAssertTrue(placeholders.isEmpty)
    }

    func testFlagOffReturnsNoPlaceholderIDsEvenWhenRowsAreFar() {
        AgentFinalizedMarkdownHeightCache.resetForTesting()
        let messages = (0..<8).map { index in
            seededAssistantMessage(text: "row-\(index)", height: 400)
        }
        let ids = AgentMessageViewportWindow.placeholderIDs(
            enabled: false,
            messages: messages,
            layoutWidth: 720,
            wideTypography: true,
            viewportMinY: 0,
            viewportHeight: 400
        )
        XCTAssertTrue(ids.isEmpty, "flag off must keep every revealed row mounted")
    }

    func testFlagOnPlaceholdersOnlyCachedFarRows() {
        AgentFinalizedMarkdownHeightCache.resetForTesting()
        var messages: [AgentMessage] = (0..<6).map { index in
            seededAssistantMessage(text: "row-\(index)", height: 400)
        }
        messages.append(AgentMessage(role: .assistant, text: "uncached-far", source: nil))
        let ids = AgentMessageViewportWindow.placeholderIDs(
            enabled: true,
            messages: messages,
            layoutWidth: 720,
            wideTypography: true,
            viewportMinY: 0,
            viewportHeight: 400
        )
        XCTAssertFalse(ids.contains(messages[0].id))
        XCTAssertTrue(ids.contains(messages[4].id))
        XCTAssertFalse(
            ids.contains(messages[6].id),
            "far assistant row without a cache entry must not unload"
        )
    }

    func testUserAndStreamingRowsAreNotUnloadable() {
        let user = AgentMessage(role: .user, text: "问", source: nil)
        let streaming = AgentMessage(
            role: .assistant,
            text: "答",
            source: nil,
            completionState: .generating
        )
        XCTAssertFalse(AgentMessageViewportWindow.canUnload(user))
        XCTAssertFalse(AgentMessageViewportWindow.canUnload(streaming))
        XCTAssertNil(
            AgentMessageViewportWindow.cachedHeight(
                message: user,
                layoutWidth: 720,
                wideTypography: true
            )
        )
    }

    private func seededAssistantMessage(text: String, height: CGFloat) -> AgentMessage {
        let message = AgentMessage(role: .assistant, text: text, source: nil)
        let prepared = AgentChatKaTeXMarkdown.prepare(text)
        AgentFinalizedMarkdownHeightCache.store(
            height,
            for: AgentFinalizedMarkdownHeightCache.cacheKey(
                messageID: message.id,
                text: prepared,
                widthBucket: AgentFinalizedMarkdownHeightCache.widthBucket(720),
                wideTypography: true
            )
        )
        return message
    }
}
