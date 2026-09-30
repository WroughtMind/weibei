import XCTest
@testable import WeiBeiCore

final class NativeProviderSearchFailureTests: XCTestCase {
    func testRejectedRequestIsNotReportedAsTemporaryServiceFailure() {
        let failure = NativeHTTPByteStream.httpFailure(400, body: RejectedSearchProtocol.errorBody)
        XCTAssertEqual(AgentFailureKind.classify(failure), .requestRejected)
        XCTAssertEqual(AgentFailureKind.classify(NSError(domain: "WeiBei.NativeAgent", code: 400)), .requestRejected)
        XCTAssertEqual(NativeLLMFailure(code: "invalid_request", message: "invalid parameter").asAgentFailureKind, .requestRejected)
        for (status, expected) in [(401, AgentFailureKind.unauthorized), (403, .unauthorized),
                                   (429, .rateLimited), (408, .timedOut), (504, .timedOut),
                                   (500, .serverError), (502, .serverError), (503, .serverError)] {
            XCTAssertEqual(AgentFailureKind.classify(NativeHTTPByteStream.httpFailure(status, body: "error")), expected)
        }
    }

    func testProvidersLeaveRecoveryToTheAgentLoop() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectedSearchProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let root = URL(string: "https://search-failure.invalid/\(UUID().uuidString)")!
        var adapters: [any NativeLLMAdapter] = [
            OpenAIResponsesProvider(baseURL: root, accessToken: "test", session: session),
            AnthropicMessagesProvider(apiKey: "test", apiURL: root.appendingPathComponent("messages"),
                                      webSearchTool: true, session: session),
            GoogleGenerativeAIProvider(apiKey: "test", rootURL: root,
                                       groundingSearch: true, session: session),
        ]
        for style in [ChatWebSearchStyle.zai, .xiaomi, .qwen, .openrouter, .kimi] {
            adapters.append(OpenAIChatCompletionsProvider(
                baseURL: root.appendingPathComponent(style.rawValue), apiKey: "test",
                webSearchStyle: style, session: session
            ))
        }
        let request = NativeLLMRequest(
            model: "test", messages: [.init(role: .user, content: "查询公开资料")],
            enableNativeWebSearch: true
        )
        for adapter in adapters {
            let before = RejectedSearchProtocol.requestCount
            var chunks: [NativeStreamChunk] = []
            do {
                for try await chunk in adapter.stream(request) { chunks.append(chunk) }
                XCTFail("\(adapter.family) 应由 Agent 循环处理降级并告知能力变化")
            } catch let failure as NativeLLMFailure {
                XCTAssertEqual(failure.status, 400, adapter.family)
                XCTAssertEqual(failure.message, "HTTP 400 \(RejectedSearchProtocol.errorBody)", adapter.family)
                XCTAssertTrue(AgentFailureKind.classify(failure).isRetryable, adapter.family)
            }
            XCTAssertTrue(chunks.isEmpty, adapter.family)
            XCTAssertEqual(RejectedSearchProtocol.requestCount - before, 1,
                           "\(adapter.family) 传输层不能自行取消搜索")
        }
    }

    func testOnlyExplicitSearchRejectionAllowsDegradation() throws {
        // Reported service response: https://github.com/openai/codex/issues/10071
        let cases: [(String, Bool)] = [
            ("Tool 'web_search_preview' is not supported with this model.", true),
            ("web search is not supported", true),
            ("Unsupported tool type: web_search", true),
            ("google_search is not supported", true),
            ("Invalid request", false),
            ("Tool 'file_search' is not supported. Supported tools: web_search", false),
            ("Tool choice is not supported with web_search", false),
            ("Unsupported web_search filter: domains", false),
            ("Invalid parameter. Input contained: web search is not supported", false),
            ("maximum context length exceeded while using web_search", false),
        ]
        for (message, shouldDegrade) in cases {
            let body = String(decoding: try JSONSerialization.data(withJSONObject: [
                "error": ["message": message],
            ]), as: UTF8.self)
            XCTAssertEqual(NativeHTTPByteStream.httpFailure(400, body: body).code == "web_search_unsupported",
                           shouldDegrade, message)
            for status in [401, 403, 429, 500] {
                XCTAssertNotEqual(NativeHTTPByteStream.httpFailure(status, body: body).code, "web_search_unsupported")
            }
        }
        XCTAssertEqual(NativeHTTPByteStream.httpFailure(400, body: "web search is not supported").code, "invalid_request")
    }

    func testSearchRejectionContinuesWithoutLosingLocalToolsOrMisstatingCapabilities() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("search-recovery-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let ledger = try NativeAgentLedger(fileURL: file)
        let registry = NativeToolRegistry()
        let courseMap = NativeToolDefinition(name: "weibei_course_map", description: "map",
            schema: NativeJSONSchema(["type": "object"]), execute: { _, _ in .init(text: "本地资料") })
        await registry.register(courseMap)
        let adapter = SearchRecoveryAdapter([
            ([], NativeHTTPByteStream.httpFailure(400, body: RejectedSearchProtocol.errorBody)),
            ([.toolCallDelta(index: 0, id: "local", name: courseMap.name, argumentsDelta: "{}"),
              .finish(reason: .toolCalls, replayState: nil)], nil),
            ([.textDelta(index: 0, text: "继续回答"), .finish(reason: .stop, replayState: nil)], nil),
            ([.textDelta(index: 0, text: "下一轮"), .finish(reason: .stop, replayState: nil)], nil),
        ])
        actor Capture {
            var activities: [AgentToolActivity] = []
            func append(_ progress: StudyAgentProgress) {
                if case let .toolActivity(activity) = progress { activities.append(activity) }
            }
        }
        let capture = Capture()
        let question = StudyAgentRequest(purpose: .conversation, question: "查阅公开资料",
            materialTitle: "", materialText: "", noteTitle: "", noteText: "", contextRevision: "r1")
        let prompt = NativePromptAssembler.webiSystemPrompt(bundledText: "测试", webSearchAvailable: true)
        let loop = NativeAgentLoop()
        let result = try await loop.run(request: question, ledger: ledger, registry: registry, adapter: adapter,
            model: "test", hostToolHandler: nil, systemPrompt: prompt, progress: { await capture.append($0) })
        XCTAssertEqual(result.text, "继续回答")
        XCTAssertEqual(adapter.requests.map(\.enableNativeWebSearch), [true, false, false])
        for sent in adapter.requests.dropFirst() {
            XCTAssertEqual(sent.tools.map(\.name), [courseMap.name])
            XCTAssertEqual(sent.reasoningEffort, question.reasoningEffort)
            XCTAssertEqual(sent.model, "test")
            XCTAssertFalse(sent.messages[0].content.contains(NativePromptAssembler.webSearchCapability(available: true)))
            XCTAssertTrue(sent.messages[0].content.contains(NativePromptAssembler.webSearchUnavailable))
        }
        let activities = await capture.activities
        let notice = try XCTUnwrap(activities.first { $0.state == .failed })
        XCTAssertFalse(notice.detail?.isEmpty ?? true)
        XCTAssertFalse(notice.resultSummary?.isEmpty ?? true)
        let events = await ledger.allEvents()
        XCTAssertTrue(events.contains { $0.chunk == .serverToolActivity(notice) })
        XCTAssertEqual(events.filter { $0.type == .toolResult }.count, 1)
        XCTAssertEqual(events.last?.finishReason, .completed)

        // A single explicit switch must disable provider search even when course tools remain.
        let disabled = try XCTUnwrap(adapter.requests.last)
        let responses = OpenAIResponsesProvider.payload(for: disabled)
        XCTAssertEqual((responses["tools"] as? [[String: Any]])?.count, 1)
        XCTAssertFalse((responses["include"] as? [String] ?? []).contains("web_search_call.action.sources"))
        let anthropic = AnthropicMessagesProvider.payload(for: disabled, webSearchTool: true)
        XCTAssertEqual((anthropic["tools"] as? [[String: Any]])?.count, 1)
        let google = GoogleGenerativeAIProvider.payload(for: disabled, groundingSearch: true)
        XCTAssertEqual((google["tools"] as? [[String: Any]])?.count, 1)
        for style in [ChatWebSearchStyle.zai, .xiaomi, .qwen, .openrouter, .kimi] {
            let encoded = try OpenAIChatCompletionsProvider(apiKey: "test", webSearchStyle: style).makeURLRequest(disabled)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(encoded.httpBody)) as? [String: Any])
            XCTAssertEqual((body["tools"] as? [[String: Any]])?.count, 1, style.rawValue)
            XCTAssertNil(body["enable_search"], style.rawValue)
            XCTAssertNil(body["plugins"], style.rawValue)
        }
        _ = try await loop.run(request: question, ledger: ledger, registry: registry, adapter: adapter,
            model: "test", hostToolHandler: nil, systemPrompt: prompt, progress: nil)
        XCTAssertEqual(adapter.requests.last?.enableNativeWebSearch, true)
        XCTAssertEqual(adapter.requests.last?.messages.first?.content, prompt)
    }

    func testRecoveryStopsAfterOneDegradationAndDoesNotReplayPartialOutput() async throws {
        let rejection = NativeHTTPByteStream.httpFailure(400, body: RejectedSearchProtocol.errorBody)
        for (chunks, failure, expectedCalls) in [
            ([], NativeHTTPByteStream.httpFailure(400, body: "invalid request"), 1),
            ([NativeStreamChunk.textDelta(index: 0, text: "已经输出")], rejection, 1),
            ([], rejection, 2),
        ] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("search-stop-\(UUID().uuidString).jsonl")
            defer { try? FileManager.default.removeItem(at: file) }
            let ledger = try NativeAgentLedger(fileURL: file)
            let registry = NativeToolRegistry()
            await registry.register(.init(name: "weibei_course_map", description: "map",
                schema: NativeJSONSchema(["type": "object"]), execute: { _, _ in .init(text: "") }))
            let adapter = SearchRecoveryAdapter([(chunks, failure), ([], failure)])
            do {
                _ = try await NativeAgentLoop().run(
                    request: .init(purpose: .conversation, question: "查资料", materialTitle: "", materialText: "",
                                   noteTitle: "", noteText: "", contextRevision: "r1"),
                    ledger: ledger, registry: registry, adapter: adapter, model: "test", hostToolHandler: nil,
                    systemPrompt: "测试", progress: nil)
                XCTFail("Unrecoverable rejection must remain a failure")
            } catch let actual as NativeLLMFailure {
                XCTAssertEqual(actual, failure)
            }
            XCTAssertEqual(adapter.requests.count, expectedCalls)
        }
    }
}

private final class SearchRecoveryAdapter: NativeLLMAdapter, @unchecked Sendable {
    let family = "search-recovery-test"
    private let lock = NSLock()
    private var script: [(chunks: [NativeStreamChunk], failure: NativeLLMFailure?)]
    private var captured: [NativeLLMRequest] = []
    var requests: [NativeLLMRequest] { lock.lock(); defer { lock.unlock() }; return captured }

    init(_ script: [([NativeStreamChunk], NativeLLMFailure?)]) { self.script = script }

    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        lock.lock()
        captured.append(request)
        let next = script.isEmpty ? (chunks: [], failure: NativeLLMFailure(code: "unexpected_call", message: "unexpected call")) : script.removeFirst()
        lock.unlock()
        return AsyncThrowingStream {
            for chunk in next.chunks { $0.yield(chunk) }
            $0.finish(throwing: next.failure)
        }
    }
}

private final class RejectedSearchProtocol: URLProtocol {
    static let errorBody = #"{"error":{"code":"unsupported_tool","message":"web search is not supported"}}"#
    private static let lock = NSLock()
    private static var count = 0

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.errorBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
