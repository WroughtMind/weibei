import XCTest
@testable import WeiBeiCore

final class NativeModelUsageTests: XCTestCase {
    func testRuntimeMetersToolsSummaryAndTitleWithoutChangingConversation() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let title = expectation(description: "标题已生成并记账")
        let runtime = NativeStudyAgentRuntime(
            model: "test-model", adapter: UsageFlowAdapter(), providerID: "test-provider",
            ledgerRoot: root.appendingPathComponent("NativeAgent/Ledgers"), systemPromptText: "固定提示",
            sessionTitleHandler: { _ in title.fulfill() }
        )
        let request = StudyAgentRequest(
            purpose: .conversation, question: "继续解释", materialTitle: "", materialText: "",
            noteTitle: "", noteText: "", projectScope: .init(kind: .global, chatID: "test"),
            contextRevision: "revision-to-preserve"
        )
        let reply = try await runtime.respond(to: request)
        await fulfillment(of: [title], timeout: 3)
        XCTAssertEqual(reply.text, "说明完成")
        let folder = root.appendingPathComponent("NativeAgent/Ledgers/test")
        let records = try snapshots(folder.appendingPathComponent("usage.jsonl"))
        let calls = latest(records)
        XCTAssertEqual(calls.count, 4)
        XCTAssertEqual(calls.filter { $0.purpose == .answer }.count, 2)
        XCTAssertEqual(calls.filter { $0.purpose == .compaction }.count, 1)
        XCTAssertEqual(calls.filter { $0.purpose == .title }.count, 1)
        XCTAssertTrue(calls.allSatisfy { $0.state == .completed && $0.usage != nil })
        XCTAssertTrue(calls.allSatisfy { $0.model == "test-model" && $0.provider == "test-provider" })
        XCTAssertTrue(calls.allSatisfy { $0.requestID == request.id && $0.contextWindow == 1_024 })
        let ledger = try NativeAgentLedger(fileURL: folder.appendingPathComponent("ledger.jsonl"))
        let events = await ledger.allEvents()
        XCTAssertEqual(events.filter { $0.type == .userMessage }.count, 1)
        XCTAssertEqual(events.filter { $0.type == .contextCompaction }.count, 1)
        XCTAssertTrue(events.contains { $0.type == .userMessage && $0.text?.contains("继续解释") == true })
        let messages = await ledger.deriveMessages()
        XCTAssertFalse(messages.contains { $0.content == "测试标题" })
        XCTAssertTrue(messages.contains { $0.content.contains("revision-to-preserve") })
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("usage.jsonl").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let child = root.appendingPathComponent("NativeAgent/Ledgers/fork/ledger.jsonl")
        _ = try await ledger.forkPrefix(upToTurn: 1, to: child)
        XCTAssertFalse(FileManager.default.fileExists(atPath: child.deletingLastPathComponent().appendingPathComponent("usage.jsonl").path))
    }

    func testFailuresMissingUsageAndCumulativeSnapshotsStayDistinct() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("NativeAgent/Ledgers/test/usage.jsonl")
        let failedJSON = #"{"type":"response.failed","response":{"usage":{"input_tokens":100,"output_tokens":4,"input_tokens_details":{"cached_tokens":20}},"error":{"code":"server_error","message":"failed"}}}"#
        var providerFailure: NativeLLMFailure?
        do { _ = try OpenAIResponsesProvider.translate(failedJSON); XCTFail("应保留模型失败") }
        catch let error as NativeLLMFailure { providerFailure = error }
        XCTAssertEqual(providerFailure?.usage?.inputTokens, 80)
        let incomplete = try OpenAIResponsesProvider.translate(#"{"type":"response.incomplete","response":{"usage":{"input_tokens":100,"output_tokens":4},"status":"incomplete","output":[{"type":"function_call"}]}}"#)
        XCTAssertTrue(incomplete.contains(.finish(reason: .length, replayState: nil)))
        XCTAssertTrue(incomplete.contains(.usage(.init(inputTokens: 100, outputTokens: 4))))
        let scenarios: [(chunks: [NativeStreamChunk], error: NativeLLMFailure?)] = [
            ([.usage(.init(inputTokens: 100, cacheReadTokens: 900)),
              .usage(.init(inputTokens: 100, outputTokens: 20, cacheReadTokens: 900)),
              .finish(reason: .stop, replayState: nil)], nil),
            ([.finish(reason: .stop, replayState: nil)], nil),
            ([.usage(.init(inputTokens: 50, outputTokens: 3))], providerFailure),
            ([.usage(.init(inputTokens: 10))], .init(code: "cancelled", message: "cancelled")),
            ([], nil),
        ]
        for scenario in scenarios {
            let adapter = NativeMeteredLLMAdapter(
                base: UsageChunksAdapter(chunks: scenario.chunks, error: scenario.error),
                providerID: nil, requestID: UUID(), usageURL: url, contextWindow: nil
            )
            do {
                for try await _ in adapter.stream(.init(model: "mock", messages: [])) {}
                XCTAssertNil(scenario.error)
            } catch { XCTAssertNotNil(scenario.error) }
        }
        let records = try snapshots(url)
        let calls = latest(records)
        XCTAssertEqual(calls.count, 5)
        XCTAssertEqual(calls.filter { $0.state == .completed }.count, 2)
        XCTAssertEqual(calls.filter { $0.state == .failed }.count, 1)
        XCTAssertEqual(calls.filter { $0.state == .cancelled }.count, 1)
        XCTAssertEqual(calls.filter { $0.state == .incomplete }.count, 1)
        XCTAssertEqual(calls.filter { $0.usage == nil }.count, 2)
        XCTAssertEqual(calls.first { $0.state == .failed }?.usage?.inputTokens, 80)
        XCTAssertEqual(calls.first { $0.state == .failed }?.usage?.outputTokens, 4)
        let first = try XCTUnwrap(calls.first { $0.usage?.cacheReadTokens == 900 })
        XCTAssertEqual(first.usage?.inputTokens, 100)
        XCTAssertEqual(first.usage?.outputTokens, 20)
        XCTAssertGreaterThan(records.filter { $0.id == first.id }.count, 2)
    }

    func testConsumerCancellationPersistsAlreadyReceivedUsage() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("NativeAgent/Ledgers/test/usage.jsonl")
        let received = expectation(description: "已收到用量")
        let upstreamStopped = expectation(description: "上游已取消")
        let base = SlowUsageAdapter(stopped: { upstreamStopped.fulfill() })
        let adapter = NativeMeteredLLMAdapter(base: base, providerID: nil, requestID: UUID(), usageURL: url, contextWindow: nil)
        let task = Task {
            for try await chunk in adapter.stream(.init(model: "mock", messages: [])) {
                if case .usage = chunk { received.fulfill() }
            }
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        _ = await task.result
        await fulfillment(of: [upstreamStopped], timeout: 2)
        for _ in 0..<100 {
            if try snapshots(url).last?.state == .cancelled { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(try snapshots(url).last?.state, .cancelled)
        XCTAssertEqual(try snapshots(url).last?.usage?.inputTokens, 123)
    }

    func testUsagePathRejectsSymlinkWithoutWritingOutsideWorkspace() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("NativeAgent/Ledgers/test/usage.jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let other = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: other)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: other)
        let adapter = NativeMeteredLLMAdapter(base: UsageChunksAdapter(chunks: [], error: nil),
            providerID: nil, requestID: UUID(), usageURL: url, contextWindow: nil)
        do {
            for try await _ in adapter.stream(.init(model: "mock", messages: [])) {}
            XCTFail("符号链接必须拒绝")
        } catch {}
        XCTAssertEqual(try String(contentsOf: other), "keep")
    }

    func testCodexCatalogCapacityValidationCachingAndAccountIsolation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageCatalogProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = AgentModelListService(session: session)
        let a = try await service.codexContextWindow(model: "catalog-test", token: "test", accountID: "a")
        let again = try await service.codexContextWindow(model: "catalog-test", token: "test", accountID: "a")
        let b = try await service.codexContextWindow(model: "catalog-test", token: "test", accountID: "b")
        let unknown = try await service.codexContextWindow(model: "catalog-test-copy", token: "test", accountID: "a")
        XCTAssertEqual(a, 95_000)
        XCTAssertEqual(again, a)
        XCTAssertEqual(b, 190_000)
        XCTAssertNil(unknown)
        XCTAssertEqual(UsageCatalogProtocol.count(for: "a"), 1)
        XCTAssertEqual(UsageCatalogProtocol.count(for: "b"), 1)
        let entry: [String: Any] = ["slug": "test", "supported_in_api": true, "visibility": "list"]
        for invalid in [-1, 0, true, "272000", 1.5] as [Any] {
            let models = AgentModelListService.codexModels([entry.merging(["context_window": invalid]) { _, new in new }])
            XCTAssertNil(models.first?.contextWindow)
        }
        for invalid in [0, 101, "95"] as [Any] {
            let models = AgentModelListService.codexModels([entry.merging([
                "context_window": 100_000, "effective_context_window_percent": invalid
            ]) { _, new in new }])
            XCTAssertNil(models.first?.contextWindow)
        }
        XCTAssertNil(NativeProviderRouting.contextWindow(provider: .custom, model: "catalog-test"))
    }

    func testLongMaterialPagingPreservesChineseFormulasAndTables() throws {
        let row = "中文推导 α+β=γ 👩🏽‍🔬\n\n$$\\frac{a}{b}=c$$\n\n| 项 | 值 |\n|---|---|\n| 一 | 2 |\n"
        for budget in [37, 12_000] {
            let material = String(repeating: row, count: budget == 37 ? 2 : 400) + "原文终点"
            var cursor: String?
            var seen = Set<String>()
            var content = ""
            repeat {
                let page = CourseDocumentSearchIndex.readMarkdown(material, location: nil, cursor: cursor, maximumCharacters: budget)
                let text = page.passages.map(\.text).joined()
                XCTAssertLessThanOrEqual(text.count, budget)
                XCTAssertFalse(text.isEmpty)
                content += text
                cursor = page.nextCursor
                if let cursor { XCTAssertTrue(seen.insert(cursor).inserted) }
                if seen.count > material.count { return XCTFail("游标未推进") }
            } while cursor != nil
            XCTAssertEqual(content, material)
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("weibei-usage-\(UUID().uuidString)")
    }

    private func snapshots(_ url: URL) throws -> [NativeModelCallUsage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try Data(contentsOf: url).split(separator: 0x0A).map { try decoder.decode(NativeModelCallUsage.self, from: Data($0)) }
    }

    private func latest(_ records: [NativeModelCallUsage]) -> [NativeModelCallUsage] {
        Array(Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }).values)
    }
}

private struct UsageChunksAdapter: NativeLLMAdapter {
    let family = "mock"
    var chunks: [NativeStreamChunk]
    var error: NativeLLMFailure?
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish(throwing: error)
        }
    }
}

private final class UsageFlowAdapter: NativeLLMAdapter, @unchecked Sendable {
    let family = "mock"
    let contextWindow: Int? = 1_024
    private let lock = NSLock()
    private var answered = false
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        lock.lock()
        defer { lock.unlock() }
        var chunks: [NativeStreamChunk]
        switch request.purpose {
        case .title: chunks = [.textDelta(index: 0, text: "测试标题")]
        case .compaction: chunks = [.textDelta(index: 0, text: "保留当前问题和已读资料")]
        case .answer:
            if !answered {
                answered = true
                return UsageChunksAdapter(chunks: [
                    .toolCallDelta(index: 0, id: "memory", name: "weibei_read_learning_memory", argumentsDelta: "{}"),
                    .usage(.init(inputTokens: 1_000)), .finish(reason: .toolCalls, replayState: nil)
                ], error: nil).stream(request)
            }
            chunks = [.textDelta(index: 0, text: "说明完成")]
        }
        chunks += [.usage(.init(inputTokens: 100, outputTokens: 8, cacheReadTokens: 0)), .finish(reason: .stop, replayState: nil)]
        return UsageChunksAdapter(chunks: chunks, error: nil).stream(request)
    }
}

private struct SlowUsageAdapter: NativeLLMAdapter {
    let family = "mock"
    var stopped: @Sendable () -> Void
    func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.usage(.init(inputTokens: 123)))
            continuation.onTermination = { @Sendable _ in stopped() }
        }
    }
}

private final class UsageCatalogProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]
    static func count(for account: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[account] ?? 0
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let account = request.value(forHTTPHeaderField: "ChatGPT-Account-ID") ?? ""
        Self.lock.lock()
        Self.counts[account, default: 0] += 1
        Self.lock.unlock()
        let body = "{\"models\":[{\"slug\":\"catalog-test\",\"supported_in_api\":true,\"visibility\":\"list\",\"context_window\":\(account == "a" ? 100_000 : 200_000),\"effective_context_window_percent\":95}]}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
