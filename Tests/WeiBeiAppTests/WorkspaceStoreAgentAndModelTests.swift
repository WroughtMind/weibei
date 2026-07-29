import AppKit
import XCTest
@testable import WeiBei
import WeiBeiCore

private actor ModelListFetchGate {
    private var nextRequestIndex = 0
    private var continuations: [Int: CheckedContinuation<[String], Error>] = [:]
    private var pendingModels: [Int: [String]] = [:]

    /**
     * 暂停一次模型列表请求，直到测试按序恢复。
     */
    func fetch() async throws -> [String] {
        let requestIndex = nextRequestIndex
        nextRequestIndex += 1
        if let models = pendingModels.removeValue(forKey: requestIndex) {
            return models
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[requestIndex] = continuation
        }
    }

    /**
     * 恢复指定序号的请求。
     */
    func succeed(request index: Int, models: [String]) -> Bool {
        guard let continuation = continuations.removeValue(forKey: index) else {
            pendingModels[index] = models
            return false
        }
        continuation.resume(returning: models)
        return true
    }
}

private actor AgentRequestRecorder {
    private(set) var request: StudyAgentRequest?

    /**
     * 保存 Store 交付给执行边界的不可变请求。
     */
    func respond(to request: StudyAgentRequest) -> StudyAgentReply {
        self.request = request
        return StudyAgentReply(text: "Recorded answer", backend: .offline)
    }
}

private actor AgentRequestGate {
    private(set) var request: StudyAgentRequest?
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var replyContinuation: CheckedContinuation<StudyAgentReply, Never>?
    private var pendingReply: StudyAgentReply?

    /**
     * 暂停 Agent 执行边界，直到测试完成在途状态变更。
     */
    func execute(_ request: StudyAgentRequest) async -> StudyAgentReply {
        self.request = request
        startedContinuation?.resume()
        startedContinuation = nil
        if let pendingReply {
            self.pendingReply = nil
            return pendingReply
        }
        return await withCheckedContinuation { continuation in
            replyContinuation = continuation
        }
    }

    /**
     * 等待请求实际进入执行边界，避免用固定时间猜测后台索引何时结束。
     */
    func waitUntilStarted() async {
        guard request == nil else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    /**
     * 恢复被暂停的请求。
     */
    func succeed(with reply: StudyAgentReply) -> Bool {
        guard let continuation = replyContinuation else {
            pendingReply = reply
            return false
        }
        self.replyContinuation = nil
        continuation.resume(returning: reply)
        return true
    }
}

private enum ModelListTestFailure: Error {
    case unavailable
}

final class WorkspaceStoreAgentAndModelTests: WorkspaceStoreTestCase {
    /**
     * 验证取消动作清空请求的所有可见流式状态且不依赖真实网络。
     */
    @MainActor
    func testCancelAgentRequestClearsVisibleStreamingState() throws {
        let store = makeStore(in: try makeTemporaryWorkspace())
        store.isAskingAgent = true
        store.agentStreamingText = "partial"
        store.agentActivityText = "thinking"

        XCTAssertTrue(store.handleAppShortcut(key: "return", modifiers: [.command]))
        XCTAssertFalse(store.isAskingAgent)
        XCTAssertEqual(store.agentStreamingText, "")
        XCTAssertNil(store.agentActivityText)
        XCTAssertEqual(store.lastAgentFailureKind, .cancelled)
    }

    /**
     * 验证模型、服务商和标准化后的 Base URL 无需联网即可持久化。
     */
    @MainActor
    func testModelAndProviderSettingsPersistWithoutNetworkFetch() throws {
        let directory = try makeTemporaryWorkspace()
        let store = makeStore(in: directory)
        store.modelName = "custom-model"
        store.agentProviderID = .openai
        store.agentBaseURL = "https://example.invalid/v1"
        XCTAssertTrue(store.flushPendingWorkspaceSave())

        let restored = makeStore(in: directory)
        XCTAssertEqual(restored.modelName, "custom-model")
        XCTAssertEqual(restored.agentProviderID, .openai)
        XCTAssertEqual(restored.agentBaseURL, "https://example.invalid/v1")
    }

    /**
     * 验证后发模型列表请求胜出，迟到的旧请求不会覆盖新目录。
     */
    @MainActor
    func testLatestModelListRequestWinsWithoutTimingDelays() async throws {
        let gate = ModelListFetchGate()
        let firstStarted = expectation(description: "first model fetch started")
        let secondStarted = expectation(description: "second model fetch started")
        var fetchInvocation = 0
        let store = makeStore(
            in: try makeTemporaryWorkspace(),
            modelListFetcher: { _, _ in
                if fetchInvocation == 0 {
                    firstStarted.fulfill()
                } else {
                    secondStarted.fulfill()
                }
                fetchInvocation += 1
                return try await gate.fetch()
            }
        )
        store.agentProviderID = .openrouter

        let firstTask = Task { await store.refreshModelList() }
        await fulfillment(of: [firstStarted], timeout: 5)
        let secondTask = Task { await store.refreshModelList() }
        await fulfillment(of: [secondStarted], timeout: 5)

        let resumedSecond = await gate.succeed(request: 1, models: ["new-model"])
        let resumedFirst = await gate.succeed(request: 0, models: ["stale-model"])
        XCTAssertTrue(resumedSecond)
        XCTAssertTrue(resumedFirst)
        await secondTask.value
        await firstTask.value

        XCTAssertEqual(store.availableModels, ["new-model"])
        XCTAssertEqual(store.modelListStatus, .loaded)
    }

    /**
     * 验证远端列举失败时展示内置目录和明确失败状态。
     */
    @MainActor
    func testModelListFailureUsesProviderFallbackAndFailedStatus() async throws {
        var fetchCount = 0
        let store = makeStore(
            in: try makeTemporaryWorkspace(),
            modelListFetcher: { _, _ in
                fetchCount += 1
                throw ModelListTestFailure.unavailable
            }
        )
        store.agentProviderID = .openrouter

        await store.refreshModelList()

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(store.availableModels, AgentProviderID.openrouter.recommendedModels)
        guard case let .failed(message) = store.modelListStatus else {
            return XCTFail("Expected a failed model-list status")
        }
        XCTAssertFalse(message.isEmpty)
    }

    /**
     * 验证不支持远端列举的服务商直接使用内置目录且不调用 fetcher。
     */
    @MainActor
    func testUnsupportedModelListUsesBuiltinCatalogWithoutFetching() async throws {
        var fetchCount = 0
        let store = makeStore(
            in: try makeTemporaryWorkspace(),
            modelListFetcher: { _, _ in
                fetchCount += 1
                return ["unexpected"]
            }
        )
        store.agentProviderID = .custom

        await store.refreshModelList()

        XCTAssertEqual(fetchCount, 0)
        XCTAssertEqual(store.availableModels, AgentProviderID.custom.recommendedModels)
        XCTAssertEqual(store.modelListStatus, .builtin)
    }

    /**
     * 验证请求版本策略同时拒绝过期工作区和过期学习记忆。
     */
    func testAgentRequestRevisionRequiresBothDimensionsToMatch() {
        let revision = AgentRequestRevisionSnapshot(workspace: 4, memory: 9)
        XCTAssertTrue(revision.isCurrent(workspace: 4, memory: 9))
        XCTAssertFalse(revision.isCurrent(workspace: 5, memory: 9))
        XCTAssertFalse(revision.isCurrent(workspace: 4, memory: 10))
    }

    /**
     * 验证 WorkspaceStore 在执行前冻结问题、笔记、选区和版本并交给可替换执行边界。
     */
    @MainActor
    func testAgentRequestUsesFrozenWorkspaceSnapshot() async throws {
        let recorder = AgentRequestRecorder()
        let store = makeStore(
            in: try makeTemporaryWorkspace(),
            agentRequestExecutor: { request in
                await recorder.respond(to: request)
            }
        )
        store.updateNote("# Snapshot note\n")
        store.updateSelection(
            "selected evidence",
            source: .document,
            ownerTitle: "Reader",
            isEditable: false
        )
        store.agentDraft = "  Explain this  "

        await store.askAgentAndWait()

        let request = await recorder.request
        XCTAssertEqual(request?.question, "Explain this")
        XCTAssertEqual(request?.noteText, "# Snapshot note\n")
        XCTAssertEqual(request?.selectionText, "片段 1（来源：Reader）：\nselected evidence")
        XCTAssertTrue(request?.contextRevision.hasSuffix(request?.id.uuidString.lowercased() ?? "missing") == true)
        XCTAssertEqual(store.messages.last?.text, "Recorded answer")
        XCTAssertFalse(store.isAskingAgent)
    }

    /**
     * 验证请求在途时工作区上下文变化会拒绝迟到的 Agent 回复。
     */
    @MainActor
    func testAgentRequestDiscardsReplyAfterWorkspaceRevisionChanges() async throws {
        let gate = AgentRequestGate()
        let store = makeStore(
            in: try makeTemporaryWorkspace(),
            agentRequestExecutor: { request in
                return await gate.execute(request)
            }
        )
        store.agentDraft = "Explain the current material"
        let requestTask = Task { await store.askAgentAndWait() }
        await gate.waitUntilStarted()

        store.updateSelection(
            "new evidence",
            source: .document,
            ownerTitle: "Reader",
            isEditable: false
        )
        let resumedRequest = await gate.succeed(with: StudyAgentReply(text: "Stale answer", backend: .offline))
        XCTAssertTrue(resumedRequest)
        await requestTask.value

        XCTAssertFalse(store.messages.contains { $0.role == .assistant && $0.text == "Stale answer" })
        XCTAssertNil(store.latestAgentNoteProposal)
    }

    /**
     * 验证请求在途时学习记忆版本变化会拒绝迟到的 Agent 回复。
     */
    @MainActor
    func testAgentRequestDiscardsReplyAfterMemoryRevisionChanges() async throws {
        let directory = try makeTemporaryWorkspace()
        let memory = LearningMemoryEntry(
            kind: .confusion,
            text: "Unresolved concept",
            evidence: "[用户：本轮]I do not understand",
            origin: .userStatement
        )
        let snapshot = PersistedWorkspace(
            learningMemoryEntries: [memory],
            learningMemoryRevision: 4
        )
        try JSONEncoder().encode(snapshot).write(
            to: directory.appendingPathComponent("workspace.json"),
            options: [.atomic]
        )
        let gate = AgentRequestGate()
        let store = makeStore(
            in: directory,
            agentRequestExecutor: { request in
                return await gate.execute(request)
            }
        )
        store.agentDraft = "Explain the current material"
        let requestTask = Task { await store.askAgentAndWait() }
        await gate.waitUntilStarted()

        store.resolveLearningMemory(memory.id)
        let resumedRequest = await gate.succeed(with: StudyAgentReply(text: "Stale answer", backend: .offline))
        XCTAssertTrue(resumedRequest)
        await requestTask.value

        XCTAssertFalse(store.messages.contains { $0.role == .assistant && $0.text == "Stale answer" })
        XCTAssertNil(store.latestAgentNoteProposal)
    }
}
