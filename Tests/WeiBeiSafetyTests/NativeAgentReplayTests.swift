import XCTest
@testable import WeiBeiCore

final class NativeAgentReplayTests: XCTestCase {
    private let provider = "openai-codex"
    private let family = "openai-codex-responses"

    private func request(_ question: String = "继续") -> StudyAgentRequest {
        StudyAgentRequest(purpose: .conversation, question: question, materialTitle: "", materialText: "",
            noteTitle: "", noteText: "", projectScope: .init(kind: .global, chatID: "replay-test"), contextRevision: "r1")
    }

    private func ledgerURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID().uuidString)/session/ledger.jsonl")
    }

    private func items(_ id: String = "1", text: String = "答案") -> [[String: Any]] {
        [
            ["type": "reasoning", "id": "rs_\(id)", "summary": [], "encrypted_content": "opaque-\(id)"],
            ["type": "web_search_call", "id": "ws_\(id)", "status": "completed",
             "action": ["type": "search", "query": "原始依据", "sources": [["type": "url", "url": "https://example.com/evidence"]]]],
            ["type": "message", "id": "msg_\(id)", "role": "assistant", "phase": "final_answer", "status": "completed",
             "content": [["type": "output_text", "text": text, "annotations": []]]],
        ]
    }

    private func data(_ items: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
    }

    private func completed(_ items: [[String: Any]], text: String = "答案") throws -> [NativeStreamChunk] {
        let event: [String: Any] = ["type": "response.completed", "response": ["status": "completed", "output": items]]
        return [.textDelta(index: 2, text: text)] + (try OpenAIResponsesProvider.translate(
            String(decoding: JSONSerialization.data(withJSONObject: event), as: UTF8.self)))
    }

    private func run(_ ledger: NativeAgentLedger, adapter: ReplayTestAdapter,
                     question: StudyAgentRequest? = nil, provider: String? = "openai-codex", model: String = "luna",
                     registry: NativeToolRegistry = NativeToolRegistry()) async throws {
        _ = try await NativeAgentLoop().run(request: question ?? request(), ledger: ledger, registry: registry,
            adapter: adapter, model: model, providerID: provider, hostToolHandler: nil, systemPrompt: "测试", progress: nil)
    }

    private func input(_ request: NativeLLMRequest) throws -> [[String: Any]] {
        try XCTUnwrap(OpenAIResponsesProvider.payload(for: request)["input"] as? [[String: Any]])
    }

    func testCompletedResponseCapturesAllItemsButIncompleteAndMissingOutputDoNot() throws {
        let expected = try data(items())
        XCTAssertEqual(try completed(items()).last, .finish(reason: .stop, replayState: expected))
        for event in [
            #"{"type":"response.incomplete","response":{"status":"incomplete","output":[{"type":"reasoning","encrypted_content":"partial"}]}}"#,
            #"{"type":"response.completed","response":{"status":"incomplete","output":[{"type":"reasoning","encrypted_content":"partial"}]}}"#,
        ] {
            XCTAssertEqual(try OpenAIResponsesProvider.translate(event).last, .finish(reason: .length, replayState: nil))
        }
        for output in ["", ",\"output\":[]"] {
            XCTAssertEqual(try OpenAIResponsesProvider.translate(
                "{\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"\(output)}}").last,
                .finish(reason: .stop, replayState: nil))
        }
    }

    func testServiceEventSurvivesLedgerReopenAndNextRequestWithoutDuplicateAssistant() async throws {
        let url = ledgerURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let ledger = try NativeAgentLedger(fileURL: url)
        try await run(ledger, adapter: ReplayTestAdapter([try completed(items())]))
        let reopened = try NativeAgentLedger(fileURL: url)
        let adapter = ReplayTestAdapter([try completed(items("2"))])
        try await run(reopened, adapter: adapter, question: request("数字的依据呢？"))
        let sent = try XCTUnwrap(adapter.requests.first)
        let replay = try XCTUnwrap(sent.messages.first { $0.role == .assistant }?.replay)
        XCTAssertEqual(replay, NativeReplayRecord(provider: provider, family: family, model: "luna", items: try data(items())))
        let outgoing = try input(sent)
        let native = outgoing.filter { $0["type"] != nil }
        XCTAssertEqual(try data(native), try data(items()))
        XCTAssertEqual(native.compactMap { $0["type"] as? String }, ["reasoning", "web_search_call", "message"])
        XCTAssertEqual(native.last?["phase"] as? String, "final_answer")
        XCTAssertEqual(outgoing.last?["content"] as? String, "数字的依据呢？")
        XCTAssertFalse(outgoing.contains { $0["role"] as? String == "assistant" && $0["type"] == nil })
        let events = await reopened.allEvents()
        XCTAssertEqual(events.filter { $0.replay != nil }.count, 2)
        for event in events {
            if case let .finish(_, state) = event.chunk { XCTAssertNil(state, "Opaque state is stored once per step") }
        }
        let old = try JSONDecoder().decode(NativeSessionEvent.self,
            from: Data(#"{"type":"assistant/message","seq":1,"timeMS":0,"text":"旧回答","isError":false}"#.utf8))
        XCTAssertNil(old.replay)
    }

    func testToolOnlyStepReplaysNativeCallOnceBeforeItsMatchingResult() async throws {
        let url = ledgerURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await registry.register(.init(name: "read_test", description: "test", schema: NativeJSONSchema(["type": "object"]),
            execute: { _, _ in NativeToolExecutionResult(text: "工具结果") }))
        let toolItems = [items()[0], ["type": "function_call", "id": "fc_1", "call_id": "c1", "name": "read_test", "arguments": "{}"]]
        let adapter = ReplayTestAdapter([
            [.toolCallDelta(index: 1, id: "c1", name: "read_test", argumentsDelta: "{}"),
             .finish(reason: .toolCalls, replayState: try data(toolItems))],
            try completed(items("2")),
        ])
        try await run(ledger, adapter: adapter, registry: registry)
        XCTAssertEqual(adapter.requests.count, 2)
        let outgoing = try input(XCTUnwrap(adapter.requests.last)).filter { $0["type"] != nil }
        XCTAssertEqual(outgoing.compactMap { $0["type"] as? String }, ["reasoning", "function_call", "function_call_output"])
        XCTAssertEqual(outgoing[1]["id"] as? String, "fc_1")
        XCTAssertEqual(outgoing[1]["call_id"] as? String, "c1")
        XCTAssertEqual(outgoing[2]["call_id"] as? String, "c1")
        XCTAssertEqual(outgoing[2]["output"] as? String, "工具结果")
        let events = await ledger.allEvents()
        XCTAssertNotNil(events.first { $0.type == .assistantMessage && $0.step == 1 }?.replay)
    }

    func testProviderAndProtocolBoundariesButSameProviderModelSwitchKeepsReplay() async throws {
        for (nextProvider, nextFamily, nextModel, expected) in [
            ("openai-codex", family, "sol", true),
            ("openai", family, "luna", false),
            ("openai-codex", "openai-chat-completions", "luna", false),
        ] {
            let url = ledgerURL()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
            let ledger = try NativeAgentLedger(fileURL: url)
            try await run(ledger, adapter: ReplayTestAdapter([try completed(items())]))
            let next = ReplayTestAdapter([[.textDelta(index: 0, text: "新回答"), .finish(reason: .stop, replayState: nil)]], family: nextFamily)
            try await run(ledger, adapter: next, provider: nextProvider, model: nextModel)
            let message = try XCTUnwrap(next.requests.first?.messages.first { $0.role == .assistant })
            XCTAssertEqual(message.replay != nil, expected)
            XCTAssertEqual(message.content, "答案", "Provider switches retain visible history")
        }
    }

    func testReplacementRemovesReplacedNativeState() async throws {
        let url = ledgerURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let ledger = try NativeAgentLedger(fileURL: url)
        try await run(ledger, adapter: ReplayTestAdapter([try completed(items("old"))]))
        var replacement = request()
        replacement.reusingLastUserMessage = true
        let adapter = ReplayTestAdapter([try completed(items("new"))])
        try await run(ledger, adapter: adapter, question: replacement)
        XCTAssertFalse(try XCTUnwrap(adapter.requests.first).messages.contains { $0.replay != nil })
        let reopened = try NativeAgentLedger(fileURL: url)
        let native = await reopened.deriveMessages().compactMap(\.replay)
        XCTAssertEqual(native.count, 1)
        XCTAssertEqual(native.first?.items, try data(items("new")))
    }

    func testCompactionOmitsReplayFromSummaryAndRetainsOnlyRecentNativeRecords() async throws {
        let url = ledgerURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let ledger = try NativeAgentLedger(fileURL: url)
        for turn in 1...2 {
            _ = try await ledger.append { NativeSessionEvent(type: .userMessage, seq: $0, timeMS: $1, turn: turn, text: "问题\(turn)") }
            let replay = NativeReplayRecord(provider: provider, family: family, model: "luna", items: try data(items("\(turn)")))
            _ = try await ledger.append { NativeSessionEvent(type: .assistantMessage, seq: $0, timeMS: $1, turn: turn, text: "答案",
                usage: .init(inputTokens: 100_000), replay: replay) }
            try await ledger.closeTurn(turn: turn, reason: .completed)
        }
        let projection = await ledger.deriveProjection()
        let summaryAdapter = ReplayTestAdapter([[.textDelta(index: 0, text: "摘要"), .finish(reason: .stop, replayState: nil)]])
        let prepared = try await NativeContextCompaction.prepareCandidate(
            request: NativeLLMRequest(model: "luna", messages: projection.messages), projection: projection,
            adapter: summaryAdapter, contextWindow: 80_000, turnContext: (999, "当前问题"))
        let candidate = try XCTUnwrap(prepared)
        let summaryRequest = try XCTUnwrap(summaryAdapter.requests.first)
        XCTAssertEqual(summaryRequest.purpose, .compaction)
        XCTAssertFalse(try input(summaryRequest).contains { $0["type"] as? String == "reasoning" })
        XCTAssertEqual(candidate.request.messages.compactMap(\.replay).map(\.items), [try data(items("2"))])
        _ = try await ledger.append { NativeSessionEvent(type: .contextCompaction, seq: $0, timeMS: $1,
            summary: candidate.summary, firstKeptSeq: candidate.firstKeptSeq) }
        let reopened = try NativeAgentLedger(fileURL: url)
        let retained = await reopened.deriveMessages().compactMap(\.replay).map(\.items)
        XCTAssertEqual(retained, [try data(items("2"))])
    }

    func testIncompleteRefusedAndCancelledStreamsNeverPersistReplay() async throws {
        for reason in [NativeFinishReason.length, .refused, .aborted] {
            let url = ledgerURL()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
            let ledger = try NativeAgentLedger(fileURL: url)
            let adapter = ReplayTestAdapter([[.textDelta(index: 0, text: "未完成"), .finish(reason: reason, replayState: try data(items()))]])
            do { try await run(ledger, adapter: adapter); XCTFail("Expected non-completed turn") } catch {}
            let events = await ledger.allEvents()
            XCTAssertFalse(events.contains { $0.replay != nil })
            for event in events { if case let .finish(_, state) = event.chunk { XCTAssertNil(state) } }
        }
        let url = ledgerURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let cancelled = ReplayTestAdapter([[.textDelta(index: 0, text: "流中取消")]], cancelAtEnd: true)
        do { try await run(ledger, adapter: cancelled); XCTFail("Expected cancellation") } catch {}
        let events = await ledger.allEvents()
        XCTAssertEqual(events.last?.finishReason, .cancelled)
        XCTAssertFalse(events.contains { $0.type == .assistantMessage || $0.replay != nil })
    }

    func testNativeReplayUsesTheExistingStateAliasPrivacyBoundary() async throws {
        let memoryID = UUID()
        var question = request()
        question.learningContext = StudyAgentLearningContext(memories: [LearningMemoryEntry(
            id: memoryID, kind: .progress, text: "进度", evidence: "原话", origin: .userStatement,
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1))])
        var original = items(text: "记忆 \(memoryID.uuidString)\n本轮 contextRevision 是 `private-revision`。状态。\n")
        original[2]["content"] = [["type": "output_text", "text": "记忆 \(memoryID.uuidString)\n本轮 contextRevision 是 `private-revision`。状态。\n",
                                    "annotations": [["type": "url_citation", "url": "https://example.com/\(memoryID.uuidString)"]]]]
        original.append(["type": "function_call", "call_id": "c1", "name": "weibei_update_learning_memory",
                         "arguments": "{\"memoryID\":\"\(memoryID.uuidString)\",\"contextRevision\":\"private-revision\",\"memoryRevision\":3}"])
        let replay = NativeReplayRecord(provider: provider, family: family, model: "luna", items: try data(original))
        let url = ledgerURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let ledger = try NativeAgentLedger(fileURL: url)
        _ = try await ledger.append { NativeSessionEvent(type: .assistantMessage, seq: $0, timeMS: $1, replay: replay) }
        let projection = NativeStateAliases(request: question).projectedHistory(await ledger.deriveProjection())
        let projected = try XCTUnwrap(projection.messages.first?.replay)
        let serialized = String(decoding: projected.items, as: UTF8.self)
        XCTAssertFalse(serialized.lowercased().contains(memoryID.uuidString.lowercased()))
        XCTAssertFalse(serialized.contains("private-revision"))
        XCTAssertFalse(serialized.contains("memoryRevision"))
        XCTAssertTrue(serialized.contains("m1"))
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: projected.items) as? [[String: Any]])
        XCTAssertEqual(try data([actual[0]]), try data([original[0]]), "Opaque reasoning is never rewritten")
        let content = try XCTUnwrap(actual[2]["content"] as? [[String: Any]])
        XCTAssertEqual((content[0]["annotations"] as? [Any])?.count, 0)
        let stored = await ledger.deriveMessages().first?.replay
        XCTAssertEqual(stored, replay, "Sanitization changes projection, not persisted source")
    }
}

private final class ReplayTestAdapter: NativeLLMAdapter, @unchecked Sendable {
    let family: String
    private let lock = NSLock()
    private var scripts: [[NativeStreamChunk]]
    private var captured: [NativeLLMRequest] = []
    private let cancelAtEnd: Bool

    init(_ scripts: [[NativeStreamChunk]], family: String = "openai-codex-responses", cancelAtEnd: Bool = false) {
        self.scripts = scripts
        self.family = family
        self.cancelAtEnd = cancelAtEnd
    }

    var requests: [NativeLLMRequest] { lock.withLock { captured } }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        let chunks: [NativeStreamChunk] = lock.withLock {
            captured.append(request)
            return scripts.isEmpty ? [] : scripts.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            if cancelAtEnd { continuation.finish(throwing: CancellationError()) }
            else { continuation.finish() }
        }
    }
}
