import XCTest
import WeiBeiCore

final class NativeAgentRuntimeTests: XCTestCase {
    func testSSEFramingAndToolAssembly() throws {
        var framer = NativeSSEFramer()
        let lines = try framer.append(Data("data: {\"a\":1}\r\ndata: {\"b\":2}\n".utf8))
        XCTAssertEqual(lines, ["{\"a\":1}", "{\"b\":2}"])

        var assembler = NativeToolCallAssembler()
        assembler.apply(.toolCallDelta(index: 0, id: "c1", name: "weibei_course_search", argumentsDelta: "{\"query\":\"利率\"}"))
        let calls = try assembler.completedCalls()
        XCTAssertEqual(calls.first?.name, "weibei_course_search")

        var incomplete = NativeToolCallAssembler()
        incomplete.apply(.toolCallDelta(index: 0, id: "c1", name: "weibei_course_search", argumentsDelta: "{\"query\":"))
        XCTAssertThrowsError(try incomplete.completedCalls())
    }

    func testLedgerRoundTripAndCloser() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-test-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(type: .userMessage, seq: seq, timeMS: time, turn: 1, text: "hi")
        }
        try await ledger.synthesizeCloserIfNeeded()
        let reloaded = try NativeAgentLedger(fileURL: url)
        let events = await reloaded.allEvents()
        XCTAssertEqual(events.last?.type, .closer)
        XCTAssertEqual(await reloaded.deriveMessages().first?.content, "hi")
    }

    func testCredentialPermissionsAndBackup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-cred-test-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
        }
        let store = NativeAgentCredentialStore(fileURL: url)
        try store.upsert(NativeAgentCredentialRecord(provider: "deepseek", apiKey: "sk-test"))
        XCTAssertEqual(try store.posixPermissions(), 0o600)
        try Data("{".utf8).write(to: url, options: .atomic)
        XCTAssertEqual(try store.load()["deepseek"]?.apiKey, "sk-test")
    }

    func testGuardRejectsIncompleteJSONAndForeignRead() async throws {
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: "hello",
            materialTitle: "",
            materialText: "",
            noteTitle: "",
            noteText: "",
            contextRevision: "r1"
        )
        let context = NativeToolExecutionContext(request: request)
        do {
            _ = try await registry.execute(
                NativeToolCallRequest(name: "read", argumentsJSON: "{\"path\":\"/etc/passwd\"}", callID: "1"),
                context: context,
                scope: .global
            )
            XCTFail("foreign read must be denied")
        } catch let failure as NativeLLMFailure {
            XCTAssertEqual(failure.code, "guard_denied")
        }
        do {
            _ = try await registry.execute(
                NativeToolCallRequest(name: "weibei_course_search", argumentsJSON: "{\"query\":\"利率\"", callID: "2"),
                context: context,
                scope: .global
            )
            XCTFail("incomplete JSON must be refused")
        } catch let failure as NativeLLMFailure {
            XCTAssertEqual(failure.code, "incomplete_tool_arguments")
        }
    }

    func testLoopCancelBalancesUnstartedTools() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-cancel-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let adapter = MockLLMAdapter(chunks: [
            .toolCallDelta(index: 0, id: "t1", name: "weibei_course_search", argumentsDelta: "{\"query\":\"利率\"}"),
            .finish(reason: .toolCalls, replayState: nil),
        ])
        let loop = NativeAgentLoop()
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: "利率是什么",
            materialTitle: "",
            materialText: "",
            noteTitle: "",
            noteText: "",
            projectScope: StudyAgentProjectScope(kind: .course, chatID: UUID().uuidString, courseID: UUID().uuidString),
            contextRevision: "r1"
        )
        await loop.cancel()
        do {
            _ = try await loop.run(
                request: request,
                ledger: ledger,
                registry: registry,
                adapter: adapter,
                model: "mock",
                hostToolHandler: nil,
                systemPrompt: "test",
                progress: nil
            )
            XCTFail("cancelled loop should throw")
        } catch {
            let events = await ledger.allEvents()
            XCTAssertEqual(events.last?.type, .turnEnd)
            XCTAssertEqual(events.last?.finishReason, .cancelled)
        }
    }

    func testChatCompletionsTranslation() throws {
        var index = 0
        let chunks = try OpenAIChatCompletionsProvider.translate(
            payload: #"{"choices":[{"delta":{"content":"利率"}}]}"#,
            textIndex: &index
        )
        XCTAssertEqual(chunks.first, .textDelta(index: 0, text: "利率"))
    }
}

private struct MockLLMAdapter: NativeLLMAdapter {
    var family: String { "mock" }
    var chunks: [NativeStreamChunk]

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
