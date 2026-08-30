import XCTest
@testable import WeiBeiCore

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

    func testLoopContinuesLedgerWithNextTurn() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-multi-turn-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(type: .turnStart, seq: seq, timeMS: time, turn: 1)
        }
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(type: .userMessage, seq: seq, timeMS: time, turn: 1, text: "第一问")
        }
        _ = try await ledger.append { seq, time in
            NativeSessionEvent(type: .assistantMessage, seq: seq, timeMS: time, turn: 1, text: "第一答")
        }
        try await ledger.closeTurn(turn: 1, reason: .completed)
        let previousSeq = (await ledger.allEvents()).last!.seq

        _ = try await NativeAgentLoop().run(
            request: StudyAgentRequest(
                purpose: .conversation,
                question: "第二问",
                materialTitle: "",
                materialText: "",
                noteTitle: "",
                noteText: "",
                contextRevision: "r2"
            ),
            ledger: ledger,
            registry: NativeToolRegistry(),
            adapter: MockLLMAdapter(chunks: [
                .textDelta(index: 0, text: "第二答"),
                .finish(reason: .stop, replayState: nil),
            ]),
            model: "mock",
            hostToolHandler: nil,
            systemPrompt: "test",
            progress: nil
        )

        let reloaded = try NativeAgentLedger(fileURL: url)
        let events = await reloaded.allEvents()
        let messages = await reloaded.deriveMessages()
        XCTAssertTrue(events.filter { $0.seq > previousSeq }.allSatisfy { $0.turn == 2 })
        XCTAssertEqual(messages, [
            NativeModelMessage(role: .user, content: "第一问"),
            NativeModelMessage(role: .assistant, content: "第一答"),
            NativeModelMessage(role: .user, content: "第二问"),
            NativeModelMessage(role: .assistant, content: "第二答"),
        ])
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

    func testRegistryRejectsIncompleteJSON() async throws {
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
                NativeToolCallRequest(name: "weibei_course_search", argumentsJSON: "{\"query\":\"利率\"", callID: "2"),
                context: context,
                scope: .global
            )
            XCTFail("incomplete JSON must be refused")
        } catch let failure as NativeLLMFailure {
            XCTAssertEqual(failure.code, "incomplete_tool_arguments")
        }
    }

    func testMalformedToolArgumentsDoNotBlockValidSiblingOrCompletion() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-mixed-tools-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await registry.register(
            NativeToolDefinition(
                name: "test_tool",
                description: "test",
                schema: NativeJSONSchema(["type": "object"]),
                execute: { _, _ in
                    return NativeToolExecutionResult(text: "ok")
                }
            )
        )

        let result = try await NativeAgentLoop().run(
            request: testRequest(),
            ledger: ledger,
            registry: registry,
            adapter: ToolRecoveryMockLLMAdapter(toolChunks: [
                .toolCallDelta(index: 0, id: "bad", name: "test_tool", argumentsDelta: "{\"value\":"),
                .toolCallDelta(index: 1, id: "good", name: "test_tool", argumentsDelta: "{}"),
            ], expectedToolResults: 2),
            model: "mock",
            hostToolHandler: nil,
            systemPrompt: "test",
            progress: nil
        )

        let events = await ledger.allEvents()
        let toolResults = events.filter { $0.type == .toolResult }
        XCTAssertEqual(result.text, "完成")
        XCTAssertEqual(events.filter { $0.type == .toolCall }.map(\.toolCallID), ["bad", "good"])
        XCTAssertEqual(toolResults.map(\.toolCallID), ["bad", "good"])
        XCTAssertEqual(toolResults.map(\.isError), [true, false])
        XCTAssertEqual(toolResults.last?.text, "ok")
        XCTAssertEqual(events.last?.finishReason, .completed)
    }

    func testThrownToolErrorBecomesResultAndLoopCompletes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-tool-error-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await registry.register(
            NativeToolDefinition(
                name: "failing_tool",
                description: "test",
                schema: NativeJSONSchema(["type": "object"]),
                execute: { _, _ in
                    throw NativeLLMFailure(code: "tool_failed", message: "主动失败")
                }
            )
        )

        let result = try await NativeAgentLoop().run(
            request: testRequest(),
            ledger: ledger,
            registry: registry,
            adapter: ToolRecoveryMockLLMAdapter(toolChunks: [
                .toolCallDelta(index: 0, id: "failed", name: "failing_tool", argumentsDelta: "{}"),
            ], expectedToolResults: 1),
            model: "mock",
            hostToolHandler: nil,
            systemPrompt: "test",
            progress: nil
        )

        let events = await ledger.allEvents()
        let toolResult = events.first { $0.type == .toolResult }
        XCTAssertEqual(result.text, "完成")
        XCTAssertEqual(toolResult?.toolCallID, "failed")
        XCTAssertEqual(toolResult?.text, "主动失败")
        XCTAssertEqual(toolResult?.isError, true)
        XCTAssertEqual(events.last?.finishReason, .completed)
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

    func testLoopContinuesWhileTheModelStillRequestsTools() async throws {
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
        XCTAssertEqual(events.last?.type, .turnEnd)
        XCTAssertEqual(events.last?.finishReason, .completed)
    }

    func testVisualizationKeepsTextBlocksInEventOrder() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-visual-order-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let progress = AgentProgressRecorder()

        let result = try await NativeAgentLoop().run(
            request: testRequest(),
            ledger: NativeAgentLedger(fileURL: url),
            registry: registry,
            adapter: VisualizationOrderAdapter(),
            model: "mock",
            hostToolHandler: nil,
            systemPrompt: "test",
            progress: { event in await progress.record(event) }
        )

        XCTAssertEqual(result.text, "前后")
        XCTAssertEqual(result.contentBlocks.count, 3)
        if case let .text(text) = result.contentBlocks[0] {
            XCTAssertEqual(text, "前")
        } else {
            XCTFail("first block must be text")
        }
        if case .visualization = result.contentBlocks[1] {} else {
            XCTFail("second block must be visualization")
        }
        if case let .text(text) = result.contentBlocks[2] {
            XCTAssertEqual(text, "后")
        } else {
            XCTFail("third block must be text")
        }

        let events = await progress.events
        let blockSnapshots = events.compactMap { event -> [AgentMessageContentBlock]? in
            switch event {
            case let .text(_, blocks), let .visualization(_, blocks): return blocks
            default: return nil
            }
        }
        XCTAssertEqual(blockSnapshots.map(\.count), [1, 2, 3])
        XCTAssertEqual(blockSnapshots.last, result.contentBlocks)
    }

    func testLoopSendsFullSelectionAndQuestionToModel() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-context-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let selectionSentence = "保留完整段落，才能看清作者如何用事实、假设和反例推进论证。"
        let questionSentence = "请结合选中文字说明上下文如何影响判断，并指出论证、转折与证据之间的关系。"
        let selection = String(repeating: selectionSentence, count: 96)
        let question = String(repeating: questionSentence, count: 128)
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

    func testSearchedURLRemainsAvailableForCurrentRun() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-web-once-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let opened = WebOpenRecorder()
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
                guard case let .webOpen(url, _) = request else {
                    return StudyAgentHostToolResult(query: "", items: [])
                }
                await opened.record(url)
                return StudyAgentHostToolResult(query: "", items: [])
            },
            systemPrompt: "test",
            progress: nil
        )
        let openedURLs = await opened.urls
        XCTAssertEqual(openedURLs, ["https://example.com/fresh", "https://example.com/fresh"])
    }

    func testOpenedPageHrefBecomesAvailableForCurrentRun() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-web-link-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let opened = WebOpenRecorder()
        _ = try await NativeAgentLoop().run(
            request: StudyAgentRequest(
                purpose: .conversation,
                question: "搜索后沿页面链接核对",
                materialTitle: "",
                materialText: "",
                noteTitle: "",
                noteText: "",
                contextRevision: "r1"
            ),
            ledger: ledger,
            registry: registry,
            adapter: LinkedWebURLAdapter(),
            model: "mock",
            hostToolHandler: { request in
                guard case let .webOpen(url, _) = request else {
                    return StudyAgentHostToolResult(query: "", items: [])
                }
                await opened.record(url)
                let links = url == "https://example.com/source"
                    ? WeiBeiWebResearchClient.linkedHTTPSURLs(
                        in: #"""
                        <!-- <a href="/fake-comment">伪链接</a> -->
                        <script>const fake = '<a href="/fake-script">伪链接</a>';</script>
                        <style>.fake { content: '<a href="/fake-style">伪链接</a>'; }</style>
                        <a href="/evidence?from=page">证据</a>
                        """#,
                        relativeTo: URL(string: url)!
                    )
                    : []
                return StudyAgentHostToolResult(
                    query: url,
                    items: [],
                    webPages: [
                        StudyAgentWebPage(
                            url: url,
                            title: "页面",
                            text: "正文",
                            isTruncated: false,
                            links: links
                        ),
                    ]
                )
            },
            systemPrompt: "test",
            progress: nil
        )
        let openedURLs = await opened.urls
        XCTAssertEqual(openedURLs, [
            "https://example.com/source",
            "https://example.com/evidence?from=page",
        ])
    }

    func testChatCompletionsTranslation() throws {
        var index = 0
        let chunks = try OpenAIChatCompletionsProvider.translate(
            payload: #"{"choices":[{"delta":{"content":"利率"}}]}"#,
            textIndex: &index
        )
        XCTAssertEqual(chunks.first, .textDelta(index: 0, text: "利率"))
    }

    func testSkillRegistryLoadsVisualizeAndSocratic() throws {
        let root = try AgentResources.bundled().skillsURL
        let registry = try NativeSkillRegistry.load(from: root)
        XCTAssertNotNil(registry.pack(named: "visualize"))
        XCTAssertNotNil(registry.pack(named: "socratic-questioning"))
        XCTAssertTrue(registry.catalogSummary().contains("socratic-questioning"))
    }

    func testProviderRoutingCoversCatalog() {
        XCTAssertEqual(NativeProviderRouting.route(.deepseek).family, .openaiResponses)
        XCTAssertEqual(NativeProviderRouting.route(.deepseek).webSearch, .responsesTool)
        XCTAssertEqual(NativeProviderRouting.route(.anthropic).webSearch, .anthropicTool)
        XCTAssertEqual(NativeProviderRouting.route(.google).webSearch, .googleGrounding)
        XCTAssertEqual(NativeProviderRouting.route(.xai).family, .openaiResponses)
        XCTAssertEqual(NativeProviderRouting.route(.google).family, .googleGenerativeAI)
        XCTAssertEqual(NativeProviderRouting.route(.amazonBedrock).family, .openaiChatCompletions)
        XCTAssertEqual(NativeProviderRouting.route(.googleVertex).family, .googleGenerativeAI)
        XCTAssertEqual(NativeProviderRouting.route(.githubCopilot).family, .openaiChatCompletions)
        XCTAssertEqual(NativeProviderRouting.route(.githubCopilot).auth, .apiKey)
        XCTAssertEqual(NativeProviderRouting.route(.radius).auth, .apiKey)
        XCTAssertEqual(NativeProviderRouting.route(.azureOpenAI).family, .openaiResponses)
        XCTAssertEqual(NativeProviderRouting.route(.cloudflareAIGateway).family, .openaiChatCompletions)
        XCTAssertEqual(NativeProviderRouting.route(.cloudflareWorkersAI).family, .openaiChatCompletions)
        XCTAssertTrue(NativeProviderRouting.uncoveredProviders.isEmpty)
        XCTAssertEqual(AgentProviderID.githubCopilot.kind, .apiKey)
        XCTAssertEqual(AgentProviderID.radius.kind, .apiKey)
        XCTAssertEqual(AgentProviderID.subscriptionProviders, [.openaiCodex])
        let azureRoot = NativeProviderRouting.azureResponsesRoot(
            URL(string: "https://example.openai.azure.com")!
        )
        XCTAssertEqual(azureRoot.absoluteString, "https://example.openai.azure.com/openai/v1")
        let azureRequest = OpenAIResponsesProvider(
            baseURL: azureRoot,
            accessToken: "azure-key",
            usesAzureAPIKey: true,
            webSearchSupported: false
        ).makeURLRequest(NativeLLMRequest(model: "gpt-4.1", messages: []))
        XCTAssertEqual(azureRequest.value(forHTTPHeaderField: "api-key"), "azure-key")
        XCTAssertNil(azureRequest.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(azureRequest.url?.lastPathComponent, "responses")
    }

    func testWorkspaceSearchToolDefaultsToCurrentCourseAndReportsEmptyHits() async throws {
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let recorder = WorkspaceSearchRecorder()
        let result = try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_search_workspace",
                argumentsJSON: "{\"query\":\"利率\"}",
                callID: "w1"
            ),
            context: NativeToolExecutionContext(
                request: StudyAgentRequest(
                    purpose: .conversation,
                    question: "我笔记里写过利率吗",
                    materialTitle: "",
                    materialText: "",
                    noteTitle: "",
                    noteText: "",
                    contextRevision: "ws-default"
                ),
                hostToolHandler: { request in
                    await recorder.record(request)
                    return StudyAgentHostToolResult(query: "利率", items: [])
                }
            ),
            scope: .global
        )
        let decoded = try JSONDecoder().decode(
            StudyAgentHostToolResult.self,
            from: Data(result.text.utf8)
        )
        XCTAssertTrue(decoded.items.isEmpty)
        XCTAssertEqual(decoded.webPages.count, 0)
        let captured = await recorder.request
        guard case let .workspaceSearch(query, _, crossLibrary) = captured else {
            return XCTFail("expected workspaceSearch")
        }
        XCTAssertEqual(query, "利率")
        XCTAssertFalse(crossLibrary)
    }

    func testWorkspaceSearchToolCrossLibraryParameter() async throws {
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let recorder = WorkspaceSearchRecorder()
        _ = try await registry.execute(
            NativeToolCallRequest(
                name: "weibei_search_workspace",
                argumentsJSON: "{\"query\":\"利率\",\"crossLibrary\":true}",
                callID: "w2"
            ),
            context: NativeToolExecutionContext(
                request: StudyAgentRequest(
                    purpose: .conversation,
                    question: "我所有笔记里写过利率吗",
                    materialTitle: "",
                    materialText: "",
                    noteTitle: "",
                    noteText: "",
                    contextRevision: "ws-cross"
                ),
                hostToolHandler: { request in
                    await recorder.record(request)
                    return StudyAgentHostToolResult(query: "利率", items: [])
                }
            ),
            scope: .global
        )
        let captured = await recorder.request
        guard case let .workspaceSearch(_, _, crossLibrary) = captured else {
            return XCTFail("expected workspaceSearch")
        }
        XCTAssertTrue(crossLibrary)
    }

    func testSessionTitleNormalizationRejectsGenericAndStripsDecorations() {
        XCTAssertEqual(NativeSessionTitle.normalizedTitle("  利率变化机制。"), "利率变化机制")
        XCTAssertEqual(NativeSessionTitle.normalizedTitle("# 标题：利率变化机制"), "利率变化机制")
        XCTAssertNil(NativeSessionTitle.normalizedTitle("新对话"))
        XCTAssertNil(NativeSessionTitle.normalizedTitle("New Chat"))
        XCTAssertTrue(NativeSessionTitle.shouldPropose(completedTurnCount: 1))
        XCTAssertFalse(NativeSessionTitle.shouldPropose(completedTurnCount: 0))
        XCTAssertFalse(NativeSessionTitle.shouldPropose(completedTurnCount: 2))
    }

    func testSessionTitleGenerateUsesFirstTurnWithoutTools() async {
        let capture = RequestCapture()
        let title = await NativeSessionTitle.generate(
            adapter: MockLLMAdapter(
                chunks: [
                    .textDelta(index: 0, text: "利率变化机制"),
                    .finish(reason: .stop, replayState: nil),
                ],
                inspect: { capture.request = $0 }
            ),
            model: "mock",
            question: "请帮我解释利率为什么变化",
            answer: "利率是资金的价格。"
        )
        XCTAssertEqual(title, "利率变化机制")
        XCTAssertEqual(capture.request?.maxTokens, NativeSessionTitle.maxTokens)
        XCTAssertTrue(capture.request?.tools.isEmpty == true)
        XCTAssertEqual(capture.request?.messages.first?.content, NativeSessionTitle.systemPrompt)
        XCTAssertTrue(capture.request?.messages.last?.content.contains("请帮我解释利率为什么变化") == true)
    }

    func testSessionTitleGenerateTimesOutWithoutThrowing() async {
        let started = Date()
        let title = await NativeSessionTitle.generate(
            adapter: HangingLLMAdapter(),
            model: "mock",
            question: "问",
            answer: "答",
            timeoutNanoseconds: 40_000_000
        )
        XCTAssertNil(title)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    func testNativeRuntimeDeliversSemanticTitleOnceOnFirstCompletedTurn() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-title-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let box = TitleCapture()
        let adapter = FirstTurnTitleAdapter()
        let chatID = UUID().uuidString.lowercased()
        let runtime = NativeStudyAgentRuntime(
            model: "mock",
            adapter: adapter,
            ledgerRoot: root,
            systemPromptText: "you are webi",
            sessionTitleHandler: { title in
                box.add(title)
            }
        )
        let first = try await runtime.respond(
            to: StudyAgentRequest(
                purpose: .conversation,
                question: "请帮我解释利率为什么变化",
                materialTitle: "",
                materialText: "",
                noteTitle: "",
                noteText: "",
                projectScope: StudyAgentProjectScope(kind: .global, chatID: chatID),
                contextRevision: "r1"
            )
        )
        XCTAssertEqual(first.text, "第一答")
        let title = await box.wait(timeout: 2)
        XCTAssertEqual(title, "利率变化机制")
        XCTAssertEqual(adapter.titleRequestCount, 1)

        _ = try await runtime.respond(
            to: StudyAgentRequest(
                purpose: .conversation,
                question: "再举个例子",
                materialTitle: "",
                materialText: "",
                noteTitle: "",
                noteText: "",
                projectScope: StudyAgentProjectScope(kind: .global, chatID: chatID),
                contextRevision: "r2"
            )
        )
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(box.count, 1)
        XCTAssertEqual(adapter.titleRequestCount, 1)
    }

    func testVisualAssetMagicRejectsMismatchedBytes() {
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertTrue(NativeVisualAssetMagic.matches(png, mediaType: "image/png"))
        XCTAssertFalse(NativeVisualAssetMagic.matches(png, mediaType: "image/jpeg"))
        XCTAssertTrue(NativeVisualAssetMagic.matches(Data([0xFF, 0xD8, 0xFF, 0x01]), mediaType: "image/jpeg"))
        var webp = Data("RIFF".utf8)
        webp.append(contentsOf: [0, 0, 0, 0])
        webp.append(contentsOf: Data("WEBP".utf8))
        XCTAssertTrue(NativeVisualAssetMagic.matches(webp, mediaType: "image/webp"))
    }

    func testTurnLocationStaysOffTheLedger() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-location-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let capture = RequestCapture()
        _ = try await NativeAgentLoop().run(
            request: StudyAgentRequest(
                purpose: .conversation,
                question: "这段什么意思",
                materialTitle: "利率讲义",
                materialText: "",
                noteTitle: "",
                noteText: "",
                focus: StudyAgentFocus(
                    chatID: "chat",
                    courseID: nil,
                    materialItemID: "material-rates",
                    materialTitle: "利率讲义",
                    pageIndex: 11,
                    sectionTitle: "单利",
                    sectionLocationID: nil,
                    sectionOrdinal: nil,
                    selectionText: nil,
                    actionSource: "reader"
                ),
                contextRevision: "r1"
            ),
            ledger: ledger,
            registry: NativeToolRegistry(),
            adapter: MockLLMAdapter(
                chunks: [
                    .textDelta(index: 0, text: "在讲单利。"),
                    .finish(reason: .stop, replayState: nil),
                ],
                inspect: { capture.request = $0 }
            ),
            model: "mock",
            hostToolHandler: nil,
            systemPrompt: "test",
            progress: nil
        )
        let outgoing = capture.request?.messages.last { $0.role == .user }?.content ?? ""
        XCTAssertTrue(outgoing.contains("利率讲义"))
        XCTAssertTrue(outgoing.contains("这段什么意思"))
        XCTAssertEqual(NativeTurnLocation.displayPage(11), 12)
        XCTAssertTrue(outgoing.contains("12"))
        let logged = await ledger.deriveMessages().last { $0.role == .user }?.content ?? ""
        XCTAssertEqual(logged, "这段什么意思")
        XCTAssertFalse(logged.contains("12"))
    }

    func testVisualAssetPutsPixelsOnToolResult() async throws {
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 3])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("native-asset-\(UUID().uuidString).png")
        try png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("native-visual-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let ledger = try NativeAgentLedger(fileURL: url)
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let adapter = VisualAssetLoopAdapter()
        _ = try await NativeAgentLoop().run(
            request: StudyAgentRequest(
                purpose: .conversation,
                question: "图里有什么",
                materialTitle: "示意图",
                materialText: "",
                noteTitle: "",
                noteText: "",
                visualAssets: [
                    StudyAgentVisualAsset(id: "asset-1", filePath: file.path, mediaType: "image/png"),
                ],
                contextRevision: "r1"
            ),
            ledger: ledger,
            registry: registry,
            adapter: adapter,
            model: "mock",
            hostToolHandler: nil,
            systemPrompt: "test",
            progress: nil
        )
        let toolMessage = adapter.followUp?.messages.first { $0.role == .tool }
        XCTAssertEqual(toolMessage?.images.count, 1)
        XCTAssertEqual(toolMessage?.images.first?.mediaType, "image/png")
        XCTAssertEqual(toolMessage?.images.first?.data.prefix(8), png.prefix(8))
        let events = await ledger.allEvents()
        XCTAssertEqual(events.first { $0.type == .toolResult }?.imageMediaType, "image/png")
        XCTAssertFalse(events.first { $0.type == .toolResult }?.imageBase64?.isEmpty ?? true)

        let followUp = adapter.followUp ?? NativeLLMRequest(model: "mock", messages: [])
        let anthropic = AnthropicMessagesProvider.payload(for: followUp)
        let anthropicMessages = anthropic["messages"] as? [[String: Any]] ?? []
        let toolResult = (anthropicMessages.last?["content"] as? [[String: Any]])?.first
        let toolContent = toolResult?["content"] as? [[String: Any]]
        XCTAssertTrue(toolContent?.contains { $0["type"] as? String == "image" } == true)

        let output = OpenAIResponsesProvider.assembleInput(followUp.messages).input
        let toolOutput = output.last?["output"] as? [[String: Any]]
        XCTAssertTrue(toolOutput?.contains { $0["type"] as? String == "input_image" } == true)

        let gemini = GoogleGenerativeAIProvider.payload(for: followUp)
        let contents = gemini["contents"] as? [[String: Any]] ?? []
        let lastParts = contents.last?["parts"] as? [[String: Any]] ?? []
        XCTAssertTrue(lastParts.contains { $0["inline_data"] != nil })

        let chatParts = OpenAIChatCompletionsProvider.imageParts(toolMessage?.images ?? [], caption: "")
        XCTAssertEqual(chatParts.first?["type"] as? String, "image_url")
    }

    func testLiveModelListURLAndIDParsing() throws {
        XCTAssertEqual(
            try AgentModelListService.resolvedModelsURL(base: "https://api.deepseek.com").absoluteString,
            "https://api.deepseek.com/v1/models"
        )
        XCTAssertEqual(
            try AgentModelListService.resolvedModelsURL(base: "https://api.groq.com/openai/v1").absoluteString,
            "https://api.groq.com/openai/v1/models"
        )
        XCTAssertEqual(
            AgentModelListService.coerceModelIDs(
                [["id": "models/gemini-2.5-flash"]],
                stripPrefix: "models/"
            ),
            ["gemini-2.5-flash"]
        )
        XCTAssertEqual(
            NativeProviderRouting.modelListStrategy(
                provider: .deepseek,
                baseURL: NativeProviderRouting.route(.deepseek).baseURL
            ),
            .openAICompatible(base: "https://api.deepseek.com")
        )
        XCTAssertEqual(
            NativeProviderRouting.modelListStrategy(
                provider: .githubCopilot,
                baseURL: NativeProviderRouting.route(.githubCopilot).baseURL
            ),
            .githubCopilot
        )
        XCTAssertEqual(
            NativeProviderRouting.modelListStrategy(
                provider: .radius,
                baseURL: NativeProviderRouting.route(.radius).baseURL
            ),
            .openAICompatible(base: "https://radius.pi.dev")
        )
        XCTAssertEqual(
            NativeProviderRouting.modelListStrategy(
                provider: .amazonBedrock,
                baseURL: NativeProviderRouting.route(.amazonBedrock).baseURL
            ),
            .openAICompatible(base: "https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1")
        )
        XCTAssertEqual(
            AgentModelListService.publisherModelIDs(
                [["name": "publishers/google/models/gemini-2.5-flash"]]
            ),
            ["gemini-2.5-flash"]
        )
    }

    func testCopilotSessionUsesProxyHostAndRequiredHeaders() throws {
        let fallback = NativeCopilotSession.resolved(githubToken: "gho_user", exchangeJSON: nil)
        XCTAssertEqual(fallback.token, "gho_user")
        XCTAssertEqual(fallback.baseURL, NativeCopilotSession.individualBaseURL)

        let viaProxy = NativeCopilotSession.resolved(
            githubToken: "gho_user",
            exchangeJSON: ["token": "tid=session", "proxy-ep": "copilot.example.internal"]
        )
        XCTAssertEqual(viaProxy.token, "tid=session")
        XCTAssertEqual(viaProxy.baseURL.host, "copilot.example.internal")

        let viaEndpoints = NativeCopilotSession.resolved(
            githubToken: "gho_user",
            exchangeJSON: [
                "token": "tid=session",
                "endpoints": ["api": "https://api.githubcopilot.com"],
            ]
        )
        XCTAssertEqual(viaEndpoints.baseURL.host, "api.githubcopilot.com")

        let request = try OpenAIChatCompletionsProvider(
            baseURL: NativeCopilotSession.individualBaseURL,
            apiKey: "gho_user",
            extraHeaders: NativeCopilotSession.requestHeaders
        ).makeURLRequest(NativeLLMRequest(model: "gpt-4.1", messages: []))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gho_user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Copilot-Integration-Id"), "vscode-chat")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Editor-Version"), "vscode/1.107.0")
        XCTAssertEqual(request.url?.host, "api.individual.githubcopilot.com")
        XCTAssertEqual(request.url?.lastPathComponent, "completions")

        let vertexRoot = URL(
            string: "https://us-central1-aiplatform.googleapis.com/v1/projects/p/locations/us-central1/publishers/google"
        )!
        let vertex = GoogleGenerativeAIProvider(
            apiKey: "vertex-key",
            rootURL: vertexRoot
        ).makeURLRequest(NativeLLMRequest(model: "gemini-2.5-flash", messages: []))
        XCTAssertEqual(vertex.value(forHTTPHeaderField: "x-goog-api-key"), "vertex-key")
        XCTAssertEqual(
            vertex.url?.path.contains("/publishers/google/models/gemini-2.5-flash:streamGenerateContent"),
            true
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

private struct VisualizationOrderAdapter: NativeLLMAdapter {
    let family = "mock"

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        let hasVisualization = request.messages.contains { $0.role == .tool }
        return AsyncThrowingStream { continuation in
            if hasVisualization {
                continuation.yield(.textDelta(index: 0, text: "后"))
                continuation.yield(.finish(reason: .stop, replayState: nil))
            } else {
                continuation.yield(.textDelta(index: 0, text: "前"))
                continuation.yield(.toolCallDelta(
                    index: 1,
                    id: "visual-1",
                    name: "weibei_visualize",
                    argumentsDelta: #"{"id":"lesson-map","spec":{"items":[{"type":"text","content":"图"}]}}"#
                ))
                continuation.yield(.finish(reason: .toolCalls, replayState: nil))
            }
            continuation.finish()
        }
    }
}

private actor AgentProgressRecorder {
    private(set) var events: [StudyAgentProgress] = []

    func record(_ event: StudyAgentProgress) {
        events.append(event)
    }
}

private final class VisualAssetLoopAdapter: NativeLLMAdapter, @unchecked Sendable {
    var family: String { "mock" }
    private let lock = NSLock()
    private(set) var followUp: NativeLLMRequest?

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        let hasTool = request.messages.contains { $0.role == .tool }
        if hasTool {
            lock.lock()
            followUp = request
            lock.unlock()
        }
        return AsyncThrowingStream { continuation in
            if hasTool {
                continuation.yield(.textDelta(index: 0, text: "图里没有可读文字。"))
                continuation.yield(.finish(reason: .stop, replayState: nil))
            } else {
                continuation.yield(.toolCallDelta(
                    index: 0,
                    id: "a1",
                    name: "weibei_visual_asset",
                    argumentsDelta: "{\"assetID\":\"asset-1\"}"
                ))
                continuation.yield(.finish(reason: .toolCalls, replayState: nil))
            }
            continuation.finish()
        }
    }
}

private struct ToolRecoveryMockLLMAdapter: NativeLLMAdapter {
    var family: String { "mock" }
    let toolChunks: [NativeStreamChunk]
    let expectedToolResults: Int

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        let toolResultCount = request.messages.filter { $0.role == .tool }.count
        return AsyncThrowingStream { continuation in
            if toolResultCount == 0 {
                toolChunks.forEach { continuation.yield($0) }
                continuation.yield(.finish(reason: .toolCalls, replayState: nil))
            } else if toolResultCount == expectedToolResults {
                continuation.yield(.textDelta(index: 0, text: "完成"))
                continuation.yield(.finish(reason: .stop, replayState: nil))
            } else {
                continuation.finish(throwing: NativeLLMFailure(code: "test_failure", message: "工具调用与结果未配平"))
                return
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
            chunks.forEach { continuation.yield($0) }
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

private final class LinkedWebURLAdapter: NativeLLMAdapter, @unchecked Sendable {
    let family = "responses-mock"
    private let lock = NSLock()
    private var step = 0

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        lock.lock()
        step += 1
        let currentStep = step
        lock.unlock()
        let url = currentStep == 1
            ? "https://example.com/source"
            : currentStep == 2
                ? "https://example.com/fake-script"
                : "https://example.com/evidence?from=page"
        let call = NativeStreamChunk.toolCallDelta(
            index: 0,
            id: "linked-open-\(currentStep)",
            name: "weibei_web_open",
            argumentsDelta: #"{"url":"\#(url)"}"#
        )
        let chunks: [NativeStreamChunk] = currentStep == 1
            ? [.webSearchSource(url: url), call, .finish(reason: .toolCalls, replayState: nil)]
            : currentStep <= 3
                ? [call, .finish(reason: .toolCalls, replayState: nil)]
                : [.textDelta(index: 0, text: "完成"), .finish(reason: .stop, replayState: nil)]
        return AsyncThrowingStream { continuation in
            chunks.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

private actor WebOpenRecorder {
    private(set) var urls: [String] = []

    func record(_ url: String) {
        urls.append(url)
    }
}

private actor WorkspaceSearchRecorder {
    private(set) var request: StudyAgentHostToolRequest?

    func record(_ request: StudyAgentHostToolRequest) {
        self.request = request
    }
}

private func testRequest() -> StudyAgentRequest {
    StudyAgentRequest(
        purpose: .conversation,
        question: "测试工具恢复",
        materialTitle: "",
        materialText: "",
        noteTitle: "",
        noteText: "",
        contextRevision: "r1"
    )
}

private final class RequestCapture: @unchecked Sendable {
    var request: NativeLLMRequest?
}

private final class TitleCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var titles: [String] = []

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return titles.count
    }

    func add(_ title: String) {
        lock.lock()
        titles.append(title)
        lock.unlock()
    }

    func snapshot() -> String? {
        lock.lock(); defer { lock.unlock() }
        return titles.last
    }

    func wait(timeout: TimeInterval) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let last = snapshot() { return last }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }
}

private struct HangingLLMAdapter: NativeLLMAdapter {
    var family: String { "mock" }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class FirstTurnTitleAdapter: NativeLLMAdapter, @unchecked Sendable {
    let family = "mock"
    private let lock = NSLock()
    private(set) var titleRequestCount = 0

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        let isTitle = request.messages.contains {
            $0.role == .system && $0.content == NativeSessionTitle.systemPrompt
        }
        if isTitle {
            lock.lock()
            titleRequestCount += 1
            lock.unlock()
        }
        let text: String
        if isTitle {
            text = "利率变化机制"
        } else if request.messages.contains(where: { $0.role == .user && $0.content.contains("再举个例子") }) {
            text = "第二答"
        } else {
            text = "第一答"
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(index: 0, text: text))
            continuation.yield(.finish(reason: .stop, replayState: nil))
            continuation.finish()
        }
    }
}
