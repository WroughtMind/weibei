import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

/// PR-1 对话安全回归：提交与停止分离（A1）、草稿不被旧问题覆盖（A2）、
/// 重新生成失败保留原回答（A3）、空回复保留中断消息（A6）。
/// 全部用假 provider（`selfCheckAgentResponder`），不触网。
final class ConversationSafetyTests: XCTestCase {
    private var storeFixture: (store: WorkspaceStore, sessionID: UUID, root: URL)?

    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        precondition(Thread.isMainThread)
        storeFixture = try MainActor.assumeIsolated {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let store = WorkspaceStore(
                workspaceDirectory: root,
                startsAtBlankEntries: true,
                startsCourseFileMaintenance: false
            )
            let session = try XCTUnwrap(store.createStudySession(courseID: nil))
            return (store, session.id, root)
        }
    }

    override func tearDownWithError() throws {
        let root = storeFixture?.root
        storeFixture = nil
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        try super.tearDownWithError()
    }

    /// 手动放行的闸门：让假回答停在指定位置，测试再决定放行或抛错。
    private final class ReplyGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false

        func wait() async {
            lock.lock()
            if opened { lock.unlock(); return }
            lock.unlock()
            await withCheckedContinuation { continuation in
                self.lock.lock()
                if self.opened {
                    self.lock.unlock()
                    continuation.resume()
                } else {
                    self.continuation = continuation
                    self.lock.unlock()
                }
            }
        }

        func open() {
            lock.lock()
            opened = true
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume()
        }
    }

    @MainActor
    private func makeStore() throws -> (store: WorkspaceStore, sessionID: UUID, cleanup: () -> Void) {
        let fixture = try XCTUnwrap(storeFixture)
        return (fixture.store, fixture.sessionID, {})
    }

    /// A1: 回答生成中再次提交不得取消正在进行的回答。
    @MainActor
    func testSubmittingWhileRunningDoesNotCancel() async throws {
        let (store, id, cleanup) = try makeStore()
        defer { cleanup() }
        let gate = ReplyGate()
        store.selfCheckAgentResponder = { _ in
            await gate.wait()
            return StudyAgentReply(text: "第一问的回答", backend: .native)
        }
        store.saveComposerDraft("第一问", for: id)
        store.submitAgentDraft(sessionID: id)
        try await waitUntil { store.conversationMessages(in: id).contains { $0.role == .user } }
        let runningTask = store.agentRuns[id]?.agentRequestTask
        XCTAssertNotNil(runningTask, "提交后应处于回答状态")

        // 模拟用户在回答期间按回车/⌘↩ 又提交一次。
        store.saveComposerDraft("第二问", for: id)
        store.submitAgentDraft(sessionID: id)

        XCTAssertTrue(store.isAgentRunning(in: id), "运行中提交不能把回答取消")
        XCTAssertEqual(
            store.conversationMessages(in: id).filter { $0.role == .user }.count,
            1,
            "运行中的提交不应追加新的用户消息"
        )

        gate.open()
        await store.agentRuns[id]?.agentRequestTask?.value
        let messages = store.conversationMessages(in: id)
        XCTAssertEqual(messages.last?.text, "第一问的回答")
        XCTAssertEqual(messages.last?.completionState, .completed)
    }

    /// A2: 失败时输入框里已写的新草稿保持不变。
    @MainActor
    func testFailureKeepsNonEmptyComposerDraft() async throws {
        let (store, id, cleanup) = try makeStore()
        defer { cleanup() }
        let gate = ReplyGate()
        store.selfCheckAgentResponder = { _ in
            await gate.wait()
            throw URLError(.notConnectedToInternet)
        }
        store.saveComposerDraft("会失败的问题", for: id)
        store.submitAgentDraft(sessionID: id)
        try await waitUntil { store.composerDraft(for: id).isEmpty }

        // 用户在等待回答期间开始写新内容。
        store.saveComposerDraft("用户正在写的新草稿", for: id)
        gate.open()
        await store.agentRuns[id]?.agentRequestTask?.value

        XCTAssertEqual(store.composerDraft(for: id), "用户正在写的新草稿", "失败不得覆盖非空草稿")
        XCTAssertEqual(store.agentDraft, "用户正在写的新草稿")
        XCTAssertEqual(store.conversationMessages(in: id).last?.completionState, .interrupted)
    }

    /// A2: 失败时输入框为空才回填上一问，保证问题不丢。
    @MainActor
    func testFailureRestoresQuestionOnlyWhenComposerEmpty() async throws {
        let (store, id, cleanup) = try makeStore()
        defer { cleanup() }
        store.selfCheckAgentResponder = { _ in
            throw URLError(.notConnectedToInternet)
        }
        store.saveComposerDraft("要找回的问题", for: id)
        store.submitAgentDraft(sessionID: id)
        await store.agentRuns[id]?.agentRequestTask?.value

        // 发送后草稿被清空；失败且回答一个字都没收到时，上一问自动回到输入框。
        XCTAssertEqual(store.composerDraft(for: id), "要找回的问题")
        XCTAssertEqual(store.agentDraft, "要找回的问题")
        XCTAssertEqual(store.lastFailedAgentQuestion, "要找回的问题")
        XCTAssertEqual(store.conversationMessages(in: id).last?.completionState, .interrupted)
    }

    /// A2: 用户主动停止后不回填旧问题。
    @MainActor
    func testUserStopDoesNotRestoreQuestionIntoComposer() async throws {
        let (store, id, cleanup) = try makeStore()
        defer { cleanup() }
        let gate = ReplyGate()
        store.selfCheckAgentResponder = { _ in
            await gate.wait()
            return StudyAgentReply(text: "不会写完的回答", backend: .native)
        }
        store.saveComposerDraft("主动停止的问题", for: id)
        store.submitAgentDraft(sessionID: id)
        try await waitUntil {
            store.isAgentRunning(in: id)
                && store.composerDraft(for: id).isEmpty
                && store.conversationMessages(in: id).contains { $0.completionState == .generating }
        }

        // 停止按钮路径：只停止，不回填。
        store.cancelAgentRequest(in: id)
        gate.open()
        await store.waitForAgentRequestsToStop()

        XCTAssertFalse(store.isAgentRunning(in: id))
        XCTAssertTrue(
            store.composerDraft(for: id).isEmpty,
            "用户主动停止不得把旧问题写回输入框"
        )
        XCTAssertEqual(store.conversationMessages(in: id).last?.completionState, .interrupted)
    }

    /// A3: 重新生成失败且一个字都没收到时，原回答内容保持不变并标出可重试的中断状态。
    @MainActor
    func testRegenerateFailureKeepsPreviousReply() async throws {
        let (store, id, cleanup) = try makeStore()
        defer { cleanup() }
        store.selfCheckAgentResponder = { _ in
            StudyAgentReply(text: "原回答正文：这一段必须保住。", backend: .native)
        }
        store.saveComposerDraft("原始问题", for: id)
        store.submitAgentDraft(sessionID: id)
        await store.agentRuns[id]?.agentRequestTask?.value
        XCTAssertEqual(store.conversationMessages(in: id).last?.text, "原回答正文：这一段必须保住。")
        XCTAssertNotNil(store.lastRegeneratableAgentReplyID, "完成的回答应可重新生成")

        // 重新生成，这次失败。
        store.selfCheckAgentResponder = { _ in
            throw URLError(.timedOut)
        }
        store.regenerateLastAssistantReply()
        await store.agentRuns[id]?.agentRequestTask?.value

        let reply = try XCTUnwrap(store.conversationMessages(in: id).last)
        XCTAssertEqual(reply.role, .assistant)
        XCTAssertEqual(reply.text, "原回答正文：这一段必须保住。", "重新生成失败不得清空原回答")
        XCTAssertEqual(reply.completionState, .interrupted, "失败后应标出中断状态")
        XCTAssertEqual(reply.failureKind, .timedOut)
        XCTAssertEqual(reply.retryQuestion, "原始问题")
    }

    /// A3: 重新生成被用户停止且零输出时，原回答内容保持不变。
    @MainActor
    func testRegenerateStopWithZeroOutputKeepsPreviousReply() async throws {
        let (store, id, cleanup) = try makeStore()
        defer { cleanup() }
        store.selfCheckAgentResponder = { _ in
            StudyAgentReply(text: "旧回答：停止也不能删。", backend: .native)
        }
        store.saveComposerDraft("原始问题", for: id)
        store.submitAgentDraft(sessionID: id)
        await store.agentRuns[id]?.agentRequestTask?.value

        let gate = ReplyGate()
        store.selfCheckAgentResponder = { _ in
            await gate.wait()
            return StudyAgentReply(text: "新回答", backend: .native)
        }
        store.regenerateLastAssistantReply()
        try await waitUntil {
            store.isAgentRunning(in: id)
                && store.conversationMessages(in: id).last?.completionState == .generating
                && store.conversationMessages(in: id).last?.text == "旧回答：停止也不能删。"
        }
        store.cancelAgentRequest(in: id)
        gate.open()
        await store.waitForAgentRequestsToStop()

        let reply = try XCTUnwrap(store.conversationMessages(in: id).last)
        XCTAssertEqual(reply.text, "旧回答：停止也不能删。", "零输出的停止不得清空原回答")
        XCTAssertEqual(reply.completionState, .interrupted)
    }

    /// A6: 模型返回空内容时整条回复不再被删，保留带重试入口的中断状态消息。
    @MainActor
    func testEmptyReplyKeepsInterruptedMessage() async throws {
        let (store, id, cleanup) = try makeStore()
        defer { cleanup() }
        store.selfCheckAgentResponder = { _ in
            StudyAgentReply(text: "", backend: .native)
        }
        store.saveComposerDraft("会得到空回答的问题", for: id)
        store.submitAgentDraft(sessionID: id)
        await store.agentRuns[id]?.agentRequestTask?.value

        let messages = store.conversationMessages(in: id)
        XCTAssertEqual(messages.count, 2, "空回复不得删除回答消息")
        let reply = try XCTUnwrap(messages.last)
        XCTAssertEqual(reply.role, .assistant)
        XCTAssertEqual(reply.completionState, .interrupted, "空回复应标记中断状态")
        XCTAssertEqual(reply.failureKind, .emptyReply)
        XCTAssertEqual(reply.retryQuestion, "会得到空回答的问题")
        XCTAssertTrue(
            store.canRetryAgentRequest(question: reply.retryQuestion, failureKind: reply.failureKind, sessionID: id),
            "空回复后应能重试"
        )
    }

    /// A6: 重新生成收到空回复时恢复原回答，而不是留下空消息。
    @MainActor
    func testEmptyReplyAfterRegenerateRestoresPreviousReply() async throws {
        let (store, id, cleanup) = try makeStore()
        defer { cleanup() }
        store.selfCheckAgentResponder = { _ in
            StudyAgentReply(text: "重新生成前的原回答。", backend: .native)
        }
        store.saveComposerDraft("原始问题", for: id)
        store.submitAgentDraft(sessionID: id)
        await store.agentRuns[id]?.agentRequestTask?.value

        store.selfCheckAgentResponder = { _ in
            StudyAgentReply(text: "", backend: .native)
        }
        store.regenerateLastAssistantReply()
        await store.agentRuns[id]?.agentRequestTask?.value

        let messages = store.conversationMessages(in: id)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?.text, "重新生成前的原回答。", "重新生成的空回复应恢复原回答")
        XCTAssertEqual(messages.last?.completionState, .interrupted)
        XCTAssertEqual(messages.last?.failureKind, .emptyReply)
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 60,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(Int64(timeout))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "等待条件超时")
    }
}
