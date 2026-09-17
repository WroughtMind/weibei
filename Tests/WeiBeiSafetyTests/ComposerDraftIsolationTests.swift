import XCTest
@testable import WeiBei
import WeiBeiCore

final class ComposerDraftIsolationTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    func testReasoningPreferenceIsRememberedPerModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keys = ["agentReasoningModes", "agentReasoningMappings"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        defer {
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
            try? FileManager.default.removeItem(at: root)
        }
        store.agentProviderID = .openai
        let profile = UUID()
        store.activeAgentProfileID = profile
        store.modelName = "gpt-5.6-sol"
        XCTAssertEqual(store.agentReasoningMode, .flash)
        XCTAssertEqual(store.agentReasoningEffort, "low")
        store.agentReasoningMode = .think
        XCTAssertEqual(store.agentReasoningEffort, "high")
        store.agentReasoningMappings[store.agentReasoningMappingKey(.think)] = "max"
        store.agentReasoningMappings[store.agentReasoningMappingKey(.flash)] = "medium"
        XCTAssertEqual(store.agentReasoningEffort, "max")
        store.agentReasoningMode = .flash
        XCTAssertEqual(store.agentReasoningEffort, "medium")
        store.agentReasoningMode = .think
        store.modelName = "gpt-5.1"
        XCTAssertEqual(store.agentReasoningMode, .flash)
        XCTAssertEqual(store.agentReasoningEffort, "low")
        store.modelName = "gpt-5.6-sol"
        XCTAssertEqual(store.agentReasoningEffort, "max")
        store.activeAgentProfileID = UUID()
        XCTAssertEqual(store.agentReasoningEffort, "low")
        store.activeAgentProfileID = profile
        let reopened = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        reopened.agentProviderID = .openai
        reopened.activeAgentProfileID = profile
        reopened.modelName = "gpt-5.6-sol"
        XCTAssertEqual(reopened.agentReasoningMode, .think)
        XCTAssertEqual(reopened.agentReasoningEffort, "max")
        store.modelName = "gpt-4.1"
        XCTAssertNil(store.agentReasoningEffort)
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

    @MainActor
    func testEmptyChatDraftDoesNotShadowProgrammaticAgentDraft() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiComposerDraftEmpty-\(UUID().uuidString)", isDirectory: true)
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try XCTUnwrap(store.createStudySession(courseID: nil))
        store.appendAgentMessage(AgentMessage(role: .user, text: "第一段", source: nil))
        let second = try XCTUnwrap(store.createStudySession(courseID: nil))
        store.appendAgentMessage(AgentMessage(role: .user, text: "第二段", source: nil))
        XCTAssertTrue(
            store.activateStudySession(
                first.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        )
        XCTAssertTrue(
            store.activateStudySession(
                second.id,
                expectedCourseID: nil,
                expectedScopeNeedsReview: false
            )
        )
        XCTAssertEqual(store.agentDraft, "")
        XCTAssertNil(store.pendingComposerDraft)
        store.agentDraft = "从课程首页继续当前全局 Chat"
        XCTAssertEqual(
            store.pendingComposerDraft ?? store.agentDraft,
            "从课程首页继续当前全局 Chat"
        )
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
