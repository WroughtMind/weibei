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
        let selection = """
        学习一门新知识时，最难的往往不是记住结论，而是看清结论成立的条件。课堂上我们从一个熟悉的例子出发，先观察现象，再比较不同解释，最后回到原文核对每一步推理。这样做虽然慢一些，却能把零散的信息连成可以复用的理解，也能在遇到新问题时知道该从哪里继续追问。

        如果只摘下最后一句，过程中的犹豫、修正和证据都会消失。保留完整段落，才能判断作者是在陈述事实、提出假设，还是回应前面的反例；也才能分清哪些词是核心概念，哪些只是为了衔接上下文。阅读的价值不只在答案，更在答案怎样从材料中长出来。
        """
        let question = """
        请结合这段选中文字，说明作者为什么强调保留推理过程，并分别概括两段话承担的作用。回答时请先指出第一段如何从学习方法过渡到理解的形成，再解释第二段如何用“只摘下最后一句”的反面情况补强观点，最后用自己的话总结这套阅读方法适合解决什么问题。

        不要只复述原句，也不要把两段拆成互不相关的要点；请明确它们之间的递进关系，并说明完整上下文为什么会影响我们对事实、假设和反例的判断。
        """
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
