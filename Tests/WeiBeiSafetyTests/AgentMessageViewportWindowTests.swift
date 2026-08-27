import XCTest
@testable import WeiBei
import WeiBeiCore

final class AgentMessageViewportWindowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AgentChatOffscreenUnloadFlag.resetForTesting()
        AgentFinalizedMarkdownHeightCache.resetForTesting()
    }

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

    func testExplicitUserDefaultsFalseStaysOffAndTrueTurnsOn() {
        AgentChatOffscreenUnloadFlag.resetForTesting()
        UserDefaults.standard.set(false, forKey: AgentChatOffscreenUnloadFlag.defaultsKey)
        XCTAssertFalse(AgentChatOffscreenUnloadFlag.isEnabled)
        UserDefaults.standard.set(true, forKey: AgentChatOffscreenUnloadFlag.defaultsKey)
        XCTAssertTrue(AgentChatOffscreenUnloadFlag.isEnabled)
    }

    func testLongConversationFlagOnPlaceholdersOnlyOffscreenCachedRows() {
        let messages = seededLongConversation(count: 120, prefix: "long")
        let ids = placeholderIDs(enabled: true, messages: messages, viewportMinY: 0)
        XCTAssertGreaterThanOrEqual(messages.count, 100)
        XCTAssertFalse(ids.contains(messages[0].id), "viewport row must stay mounted")
        XCTAssertFalse(ids.contains(messages[3].id), "row still inside the 3-screen keep band")
        XCTAssertTrue(ids.contains(messages[4].id), "first row past the keep band becomes a placeholder")
        XCTAssertTrue(ids.contains(messages[119].id))
        XCTAssertEqual(ids.count, 116)
        XCTAssertTrue(ids.isDisjoint(with: Set(messages.prefix(4).map(\.id))))
    }

    func testLongConversationUnknownHeightsNeverPlaceholder() {
        var messages = seededLongConversation(count: 120, prefix: "nil-height")
        let uncachedFar = [
            AgentMessage(role: .assistant, text: "uncached-far-50", source: nil),
            AgentMessage(role: .assistant, text: "uncached-far-119", source: nil)
        ]
        messages[50] = uncachedFar[0]
        messages[119] = uncachedFar[1]
        let ids = placeholderIDs(enabled: true, messages: messages, viewportMinY: 0)
        XCTAssertTrue(ids.contains(messages[4].id))
        XCTAssertFalse(ids.contains(uncachedFar[0].id), "nil height must never placeholder, even 50 rows down")
        XCTAssertFalse(ids.contains(uncachedFar[1].id), "nil height must never placeholder, even at the far end")
        XCTAssertFalse(ids.contains(messages[0].id))
    }

    func testLongConversationFlagOffYieldsEmptyPlaceholders() {
        let messages = seededLongConversation(count: 120, prefix: "flag-off")
        let ids = placeholderIDs(enabled: false, messages: messages, viewportMinY: 0)
        XCTAssertTrue(ids.isEmpty)
    }

    func testScrollingLongConversationRemountsRowsEnteringKeepBand() {
        let messages = seededLongConversation(count: 120, prefix: "scroll")
        let top = placeholderIDs(enabled: true, messages: messages, viewportMinY: 0)
        // Row 60 on screen: 400pt rows, viewportMinY = 24000. Keep band [22800, 25600].
        let mid = placeholderIDs(enabled: true, messages: messages, viewportMinY: 24_000)
        XCTAssertTrue(top.contains(messages[60].id), "a far row is a placeholder before the viewport arrives")
        XCTAssertFalse(mid.contains(messages[60].id), "the on-screen row remounts")
        XCTAssertFalse(mid.contains(messages[57].id), "rows that just entered the keep band remount")
        XCTAssertFalse(mid.contains(messages[63].id), "rows still inside the lower keep band stay mounted")
        XCTAssertTrue(mid.contains(messages[56].id), "rows that left the keep band become placeholders")
        XCTAssertTrue(mid.contains(messages[64].id))
        XCTAssertTrue(mid.contains(messages[0].id))
        XCTAssertTrue(mid.contains(messages[119].id))
    }

    func testSwitchingLongSessionsDoesNotLeakPlaceholderIDs() {
        let sessionA = seededLongConversation(count: 120, prefix: "session-A")
        let sessionB = seededLongConversation(count: 120, prefix: "session-B")
        XCTAssertNil(
            AgentHistoryRevealPolicy.appendedMessageCount(
                previousMessageIDs: sessionA.map(\.id),
                currentMessageIDs: sessionB.map(\.id)
            ),
            "replacing a long session must not look like an append"
        )

        let idsA = placeholderIDs(enabled: true, messages: sessionA, viewportMinY: 0)
        // After a session switch the pane refolds to the newest page; placeholders
        // are computed only from those visible rows, at the latest-message viewport.
        let visibleB = Array(sessionB.suffix(AgentHistoryRevealPolicy.pageSize))
        let newestPageHeight = CGFloat(visibleB.count - 1) * 400
        let idsB = placeholderIDs(
            enabled: true,
            messages: visibleB,
            viewportMinY: newestPageHeight
        )

        XCTAssertFalse(idsA.isEmpty)
        XCTAssertTrue(idsA.isDisjoint(with: Set(sessionB.map(\.id))))
        XCTAssertTrue(idsB.isDisjoint(with: Set(sessionA.map(\.id))))
        XCTAssertFalse(idsB.contains(visibleB.last!.id), "the on-screen latest row stays mounted")
        XCTAssertTrue(idsB.contains(visibleB[0].id), "the far end of the newest page still unloads")
    }

    func testStreamingTailInLongConversationNeverPlaceholders() {
        var messages = seededLongConversation(count: 119, prefix: "typing")
        let streaming = AgentMessage(
            role: .assistant,
            text: "still-generating",
            source: nil,
            completionState: .generating
        )
        messages.append(streaming)
        let ids = placeholderIDs(enabled: true, messages: messages, viewportMinY: 0)
        XCTAssertFalse(ids.contains(streaming.id), "a generating tail must stay mounted even when far from the viewport")
        XCTAssertTrue(ids.contains(messages[4].id))
        XCTAssertGreaterThanOrEqual(messages.count, 100)
    }

    private func placeholderIDs(
        enabled: Bool,
        messages: [AgentMessage],
        viewportMinY: CGFloat
    ) -> Set<UUID> {
        AgentMessageViewportWindow.placeholderIDs(
            enabled: enabled,
            messages: messages,
            layoutWidth: 720,
            wideTypography: true,
            viewportMinY: viewportMinY,
            viewportHeight: 400,
            spacing: 0
        )
    }

    private func seededLongConversation(count: Int, prefix: String) -> [AgentMessage] {
        (0..<count).map { index in
            seededAssistantMessage(text: "\(prefix)-\(index)", height: 400)
        }
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
