import XCTest
@testable import WeiBei
import WeiBeiCore

final class ComposerDraftIsolationTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    func testUnsentComposerDraftSurvivesSwitchingChats() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiComposerDraft-\(UUID().uuidString)", isDirectory: true)
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try XCTUnwrap(store.createStudySession(courseID: nil))
        store.appendAgentMessage(AgentMessage(role: .user, text: "占位", source: nil))
        store.pendingComposerDraft = "还没发出去的问题"

        let second = try XCTUnwrap(store.createStudySession(courseID: nil))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(store.agentDraft, "")

        XCTAssertTrue(
            store.activateStudySession(
                first.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        )
        XCTAssertEqual(store.agentDraft, "还没发出去的问题")
        XCTAssertEqual(store.pendingComposerDraft, "还没发出去的问题")
    }

    func testFinalizedMarkdownHeightCacheEvictsLeastRecentlyUsed() {
        AgentFinalizedMarkdownHeightCache.resetForTesting()
        defer { AgentFinalizedMarkdownHeightCache.resetForTesting() }

        for index in 0..<(AgentFinalizedMarkdownHeightCache.capacity + 8) {
            AgentFinalizedMarkdownHeightCache.store(
                CGFloat(40 + index),
                for: "key-\(index)"
            )
        }
        XCTAssertEqual(
            AgentFinalizedMarkdownHeightCache.storedKeyCountForTesting,
            AgentFinalizedMarkdownHeightCache.capacity
        )
        XCTAssertNil(AgentFinalizedMarkdownHeightCache.height(for: "key-0"))
        XCTAssertNotNil(
            AgentFinalizedMarkdownHeightCache.height(
                for: "key-\(AgentFinalizedMarkdownHeightCache.capacity + 7)"
            )
        )
    }
}
