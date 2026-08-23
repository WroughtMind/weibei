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
        let messages = await reloaded.deriveMessages()
        XCTAssertEqual(events.last?.type, .closer)
        XCTAssertEqual(messages.first?.content, "hi")
    }

    func testCredentialPermissionsAndBackup() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-cred-test-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
        }
        let store = NativeAgentCredentialStore(fileURL: url)
        try store.upsert(NativeAgentCredentialRecord(provider: "deepseek", apiKey: "sk-test"))
        try store.upsert(NativeAgentCredentialRecord(provider: "deepseek", apiKey: "sk-test"))
        XCTAssertEqual(try store.posixPermissions(), 0o600)
        try Data("{".utf8).write(to: url, options: .atomic)
        XCTAssertEqual(try store.load()["deepseek"]?.apiKey, "sk-test")
    }

    func testLogoutScrubsBackupLeftover() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-logout-\(UUID().uuidString).json")
        let backup = url.appendingPathExtension("bak")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: backup)
        }
        let store = NativeAgentCredentialStore(fileURL: url)
        try store.upsert(NativeAgentCredentialRecord(provider: "openai-codex", accessToken: "tok", refreshToken: "ref"))
        try store.upsert(NativeAgentCredentialRecord(provider: "openai-codex", accessToken: "tok-2", refreshToken: "ref-2"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        try await NativeOpenAIOAuth.logout(from: store)
        XCTAssertFalse(try NativeOpenAIOAuth.leftoverCredentialExists(in: store))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
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

    func testLoopContinuesPastTwelveToolSteps() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-long-tool-run-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let adapter = LongToolRunMockLLMAdapter(toolStepCount: 13)
        let loop = NativeAgentLoop()
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: "继续查利率",
            materialTitle: "",
            materialText: "",
            noteTitle: "",
            noteText: "",
            contextRevision: "r1"
        )

        let result = try await loop.run(
            request: request,
            ledger: ledger,
            registry: registry,
            adapter: adapter,
            model: "mock",
            hostToolHandler: nil,
            systemPrompt: "test",
            progress: nil
        )

        let events = await ledger.allEvents()
        XCTAssertEqual(result.text, "完成")
        XCTAssertEqual(events.filter { $0.type == .stepStart }.count, 14)
        XCTAssertEqual(events.filter { $0.type == .toolResult }.count, 13)
        XCTAssertEqual(events.last?.type, .turnEnd)
        XCTAssertEqual(events.last?.finishReason, .completed)
    }

    func testLoopSendsFullSelectionAndQuestionToModel() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-context-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let legacySelectionLimit = 2_000
        let legacyQuestionLimit = 4_000
        let selectionSentence = "保留完整段落，才能看清作者如何用事实、假设和反例推进论证。"
        let questionSentence = "请结合选中文字说明上下文如何影响判断，并指出论证、转折与证据之间的关系。"
        let selection = String(repeating: selectionSentence, count: legacySelectionLimit / selectionSentence.count + 1)
        let question = String(repeating: questionSentence, count: legacyQuestionLimit / questionSentence.count + 1)
        XCTAssertGreaterThan(selection.count, legacySelectionLimit)
        XCTAssertGreaterThan(question.count, legacyQuestionLimit)
        let expectedUserMessage = """
        [选中文字：课堂阅读节选]
        \(selection)

        [问题]
        \(question)
        """
        let adapter = MockLLMAdapter(
            chunks: [.finish(reason: .stop, replayState: nil)],
            inspect: { request in
                let firstUserMessage = request.messages.first { $0.role == .user }?.content
                XCTAssertEqual(firstUserMessage, expectedUserMessage)
            }
        )
        let request = StudyAgentRequest(
            purpose: .conversation,
            question: question,
            materialTitle: "",
            materialText: "",
            noteTitle: "",
            noteText: "",
            selectionTitle: "课堂阅读节选",
            selectionText: selection,
            contextRevision: "r1"
        )
        _ = try await NativeAgentLoop().run(
            request: request,
            ledger: NativeAgentLedger(fileURL: url),
            registry: NativeToolRegistry(),
            adapter: adapter,
            model: "mock",
            hostToolHandler: nil,
            systemPrompt: "test",
            progress: nil
        )
    }

    func testSearchedURLRemainsAuthorizedForCurrentRun() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-web-once-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let opened = WebOpenCounter()
        _ = try await NativeAgentLoop().run(
            request: StudyAgentRequest(
                purpose: .conversation,
                question: "搜索后打开结果",
                materialTitle: "",
                materialText: "",
                noteTitle: "",
                noteText: "",
                contextRevision: "r1"
            ),
            ledger: ledger,
            registry: registry,
            adapter: SearchedWebURLAdapter(),
            model: "mock",
            hostToolHandler: { request in
                guard case .webOpen = request else {
                    return StudyAgentHostToolResult(query: "", items: [])
                }
                await opened.increment()
                return StudyAgentHostToolResult(query: "", items: [])
            },
            systemPrompt: "test",
            progress: nil
        )
        let openCount = await opened.value
        XCTAssertEqual(openCount, 2)
    }

    func testChatCompletionsTranslation() throws {
        var index = 0
        let chunks = try OpenAIChatCompletionsProvider.translate(
            payload: #"{"choices":[{"delta":{"content":"利率"}}]}"#,
            textIndex: &index
        )
        XCTAssertEqual(chunks.first, .textDelta(index: 0, text: "利率"))
    }

    func testResponsesAndOAuthHelpers() throws {
        let pkce = NativeOpenAIOAuth.makePKCE(entropy: Data(repeating: 3, count: 64))
        XCTAssertNotEqual(pkce.verifier, pkce.challenge)
        let url = NativeOpenAIOAuth.authorizeURL(
            redirectURI: "http://localhost:1455/auth/callback",
            pkce: pkce,
            state: "st"
        )
        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertTrue(url.query?.contains("code_challenge=") == true)
        XCTAssertEqual(
            NativeOpenAIOAuth.parseCallbackCode(
                fromHTTP: "GET /auth/callback?code=abc&state=st HTTP/1.1\r\n",
                expectedState: "st"
            ),
            "abc"
        )
        let tools = [
            NativeToolDefinition(
                name: "weibei_course_map",
                description: "map",
                permission: .read,
                schema: NativeJSONSchema(["type": "object"]),
                execute: { _, _ in NativeToolExecutionResult(text: "") }
            ),
        ]
        let payload = OpenAIResponsesProvider.payload(
            for: NativeLLMRequest(model: "gpt-5.6-luna", messages: [
                NativeModelMessage(role: .user, content: "q"),
            ], tools: tools)
        )
        let encodedTools = payload["tools"] as? [[String: Any]] ?? []
        XCTAssertTrue(encodedTools.contains { $0["type"] as? String == "web_search" })
        let text = try OpenAIResponsesProvider.translate(
            #"{"type":"response.output_text.delta","output_index":0,"delta":"hi"}"#
        )
        XCTAssertEqual(text.first, .textDelta(index: 0, text: "hi"))
        let anthropic = try AnthropicMessagesProvider.translate(
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"ok"}}"#
        )
        XCTAssertEqual(anthropic.first, .textDelta(index: 0, text: "ok"))
        let gemini = try GoogleGenerativeAIProvider.translate(
            #"{"candidates":[{"content":{"parts":[{"text":"4"}]},"finishReason":"STOP"}]}"#
        )
        XCTAssertTrue(gemini.contains(.textDelta(index: 0, text: "4")))
    }

    func testSkillRegistryLoadsVisualizeAndSocratic() throws {
        let root = try AgentResources.bundled().skillsURL
        let registry = try NativeSkillRegistry.load(from: root)
        XCTAssertNotNil(registry.pack(named: "visualize"))
        XCTAssertNotNil(registry.pack(named: "socratic-questioning"))
        XCTAssertTrue(registry.catalogSummary().contains("socratic-questioning"))
    }

    func testProviderRoutingCoversCatalog() {
        XCTAssertEqual(AgentProviderID.allCases.count, 40)
        XCTAssertEqual(NativeProviderRouting.route(.deepseek).family, .openaiChatCompletions)
        XCTAssertEqual(NativeProviderRouting.route(.xai).family, .openaiResponses)
        XCTAssertEqual(NativeProviderRouting.route(.google).family, .googleGenerativeAI)
        XCTAssertEqual(NativeProviderRouting.route(.amazonBedrock).family, .unsupported)
        XCTAssertEqual(
            Set(NativeProviderRouting.uncoveredProviders),
            [.azureOpenAI, .googleVertex, .amazonBedrock, .cloudflareAIGateway, .cloudflareWorkersAI]
        )
    }
}

private struct MockLLMAdapter: NativeLLMAdapter {
    var family: String { "mock" }
    var chunks: [NativeStreamChunk]
    var inspect: @Sendable (NativeLLMRequest) -> Void = { _ in }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        inspect(request)
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private struct LongToolRunMockLLMAdapter: NativeLLMAdapter {
    var family: String { "mock" }
    let toolStepCount: Int

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        let completedToolSteps = request.messages.filter { $0.role == .tool }.count
        let chunks: [NativeStreamChunk] = if completedToolSteps < toolStepCount {
            [
                .toolCallDelta(
                    index: 0,
                    id: "t\(completedToolSteps + 1)",
                    name: "weibei_course_search",
                    argumentsDelta: "{\"query\":\"利率\"}"
                ),
                .finish(reason: .toolCalls, replayState: nil),
            ]
        } else {
            [
                .textDelta(index: 0, text: "完成"),
                .finish(reason: .stop, replayState: nil),
            ]
        }
        return AsyncThrowingStream { continuation in
            chunks.forEach(continuation.yield)
            continuation.finish()
        }
    }
}

private final class SearchedWebURLAdapter: NativeLLMAdapter, @unchecked Sendable {
    let family = "responses-mock"
    private let lock = NSLock()
    private var step = 0

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        lock.lock()
        step += 1
        let currentStep = step
        lock.unlock()
        let url = "https://example.com/fresh"
        let call = NativeStreamChunk.toolCallDelta(
            index: 0,
            id: "open-\(currentStep)",
            name: "weibei_web_open",
            argumentsDelta: #"{"url":"https://example.com/fresh"}"#
        )
        let chunks: [NativeStreamChunk] = currentStep == 1
            ? [.webSearchSource(url: url), call, .finish(reason: .toolCalls, replayState: nil)]
            : currentStep == 2
                ? [call, .finish(reason: .toolCalls, replayState: nil)]
                : [.textDelta(index: 0, text: "完成"), .finish(reason: .stop, replayState: nil)]
        return AsyncThrowingStream { continuation in
            chunks.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

private actor WebOpenCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
