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
        let text: String
        var reason: NativeFinishReason = .stop
        var inspect: @Sendable (NativeLLMRequest) -> Void = { _ in }

        func stream(_ request: NativeLLMRequest) -> AsyncThrowingStream<NativeStreamChunk, Error> {
            inspect(request)
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta(index: 0, text: text))
                continuation.yield(.finish(reason: reason, replayState: nil))
                continuation.finish()
            }
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
