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

    func testRejectedRequestsKeepSearchConfigurationAndOriginalFailure() async throws {
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
                XCTFail("\(adapter.family) 应保留请求失败，不能生成无搜索回答")
            } catch let failure as NativeLLMFailure {
                XCTAssertEqual(failure.status, 400, adapter.family)
                XCTAssertEqual(failure.message, "HTTP 400 \(RejectedSearchProtocol.errorBody)", adapter.family)
                XCTAssertTrue(AgentFailureKind.classify(failure).isRetryable, adapter.family)
            }
            XCTAssertTrue(chunks.isEmpty, adapter.family)
            XCTAssertEqual(RejectedSearchProtocol.requestCount - before, 1,
                           "\(adapter.family) 不能取消搜索后自动发送第二次请求")
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
