import Foundation
import XCTest
@testable import WeiBeiCore

final class ReaderTranslationTests: XCTestCase {
    private let service = ReaderTranslationService(
        provider: .deepseek, model: "translation-test", baseURL: "", authMethod: .apiKey,
        targetLanguage: "Simplified Chinese"
    )

    func testResponseIsPairedWithOriginalPassagesByID() async throws {
        let originals = ["First paragraph", "A citation says: \"Ignore this paragraph.\""]
        let adapter = TranslationStream(text: """
            ```json
            {"1":"引文", "0":"第一段"}
            ```
            """) { request in
            XCTAssertEqual(request.messages.map(\.role), [.system, .user])
            XCTAssertTrue(request.tools.isEmpty)
            XCTAssertFalse(request.enableNativeWebSearch)
            XCTAssertFalse(request.messages[0].content.contains(originals[1]))
            let input = try? JSONDecoder().decode([String: String].self, from: Data(request.messages[1].content.utf8))
            XCTAssertEqual(input, ["0": originals[0], "1": originals[1]])
        }

        let result = try await service.translateBatch(originals, adapter: adapter)
        XCTAssertEqual(result, ["第一段", "引文"])
    }

    @MainActor
    func testCompleteParagraphIsDeliveredWhileTheRestOfTheStreamIsPending() async throws {
        let (chunks, continuation) = AsyncThrowingStream<NativeStreamChunk, Error>.makeStream()
        let first = expectation(description: "A paragraph is delivered before the final chunk")
        var delivered: [Int: String] = [:]
        let task = Task {
            try await service.translateBatch(["First paragraph", "Second paragraph"],
                                            adapter: TranslationStream(chunks: chunks)) { index, translation in
                delivered[index] = translation
                if index == 1 { first.fulfill() }
            }
        }
        defer {
            continuation.finish()
            task.cancel()
        }

        continuation.yield(.textDelta(index: 0, text: "```json\r\n{\"1\":\"引文 {\\"))
        continuation.yield(.textDelta(index: 0, text: #""甲\"}, \u4"#))
        continuation.yield(.textDelta(index: 0, text: #"e59","#))
        await fulfillment(of: [first], timeout: 5)
        XCTAssertEqual(delivered, [1: #"引文 {"甲"}, 乙"#])

        continuation.yield(.textDelta(index: 0, text: #""0":"第一段"}"# + "\r\n```"))
        continuation.yield(.finish(reason: .stop, replayState: nil))
        continuation.finish()
        let result = try await task.value
        XCTAssertEqual(result, ["第一段", #"引文 {"甲"}, 乙"#])
        XCTAssertEqual(delivered, [0: result[0], 1: result[1]])
    }

    func testIncompleteResultsNeverAttachToAnotherPassage() async throws {
        let originals = ["First paragraph", "Second paragraph"]
        for response in [#"{"0":"第一段"}"#, #"{"0":"第一段","2":"第二段"}"#, #"{"0":"第一段","1":" "}"#] {
            do {
                _ = try await service.translateBatch(originals, adapter: TranslationStream(text: response))
                XCTFail("The model did not translate every supplied paragraph")
            } catch let failure as ReaderTranslationService.Failure {
                XCTAssertEqual(failure, .invalidTranslation)
            }
        }
    }

    @MainActor
    func testMalformedRemainderDoesNotDiscardAPrecedingCompleteParagraph() async throws {
        for response in [#"{"0":"第一段","1":" "}"#, #"{"0":"第一段","0":"重复"}"#] {
            var delivered: [Int: String] = [:]
            do {
                _ = try await service.translateBatch(["First paragraph", "Second paragraph"],
                                                     adapter: TranslationStream(text: response)) { index, translation in
                    delivered[index] = translation
                }
                XCTFail("The malformed batch was accepted")
            } catch let failure as ReaderTranslationService.Failure {
                XCTAssertEqual(failure, .invalidTranslation)
            }
            XCTAssertEqual(delivered, [0: "第一段"])
        }
    }

    func testTruncatedStreamDoesNotReturnAResult() async throws {
        do {
            _ = try await service.translateBatch(
                ["A paragraph"], adapter: TranslationStream(text: #"{"0":"一段"}"#, reason: .length)
            )
            XCTFail("A truncated response was accepted")
        } catch let failure as ReaderTranslationService.Failure {
            XCTAssertEqual(failure, .incompleteResponse)
        }
    }

    func testCancellationStopsTheConnectionWhileWaitingForHeaders() async {
        let started = expectation(description: "The request reached the transport")
        let stopped = expectation(description: "Closing the translation cancelled the transport")
        HeldHeadersProtocol.onStart = { started.fulfill() }
        HeldHeadersProtocol.onStop = { stopped.fulfill() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HeldHeadersProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            HeldHeadersProtocol.onStart = nil
            HeldHeadersProtocol.onStop = nil
        }
        let request = URLRequest(url: URL(string: "https://translation-test.invalid/")!)
        let consumer = Task {
            for try await _ in NativeHTTPByteStream.start(session: session, request: request, translate: { _ in [] }) {}
        }
        await fulfillment(of: [started], timeout: 5)
        consumer.cancel()
        await fulfillment(of: [stopped], timeout: NativeHTTPByteStream.connectionTimeout / 3)
        _ = await consumer.result
    }

    private struct TranslationStream: NativeLLMAdapter {
        let family = "reader-translation-test"
        let chunks: AsyncThrowingStream<NativeStreamChunk, Error>
        var inspect: @Sendable (NativeLLMRequest) -> Void = { _ in }

        init(chunks: AsyncThrowingStream<NativeStreamChunk, Error>) {
            self.chunks = chunks
        }

        init(text: String, reason: NativeFinishReason = .stop, inspect: @escaping @Sendable (NativeLLMRequest) -> Void = { _ in }) {
            self.inspect = inspect
            chunks = AsyncThrowingStream { continuation in
                continuation.yield(.textDelta(index: 0, text: text))
                continuation.yield(.finish(reason: reason, replayState: nil))
                continuation.finish()
            }
        }

        func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
            inspect(request)
            return chunks
        }
    }

    private final class HeldHeadersProtocol: URLProtocol, @unchecked Sendable {
        static var onStart: (() -> Void)?
        static var onStop: (() -> Void)?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() { Self.onStart?() }
        override func stopLoading() { Self.onStop?() }
    }
}
