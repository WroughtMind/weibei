import Foundation
import XCTest
@testable import WeiBeiCore

final class WebResearchProgressTests: XCTestCase {
    func testLongPublicURLIsNotRejectedByAnArbitraryCharacterLimit() throws {
        let raw = "https://8.8.8.8/article?query=" + String(repeating: "x", count: 4_096)
        let validated = try WeiBeiWebResearchURLPolicy.validatedPublicHTTPSURL(raw)
        XCTAssertEqual(validated.absoluteString, raw)
        XCTAssertTrue(WeiBeiWebResearchURLPolicy.isAvailableInCurrentRun(raw, in: "", currentRunSourceURLs: [raw]))
    }

    func testLargeNormalWebPageStillReturnsItsBody() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgressWebProtocol.self]
        let page = try await WeiBeiWebResearchClient.open("https://8.8.8.8/large",
            maximumCharacters: 10_000, configuration: configuration)
        XCTAssertTrue(page.text.contains("大网页中仍需读取的正文"))
        XCTAssertFalse(page.isTruncated)
    }

    func testLegitimateRedirectChainLongerThanFiveHopsCompletes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgressWebProtocol.self]
        let page = try await WeiBeiWebResearchClient.open("https://8.8.8.8/redirect/0",
            maximumCharacters: 10_000, configuration: configuration)
        XCTAssertTrue(page.text.contains("重定向完成后的正文"))
        XCTAssertEqual(URL(string: page.url)?.lastPathComponent, "7")
    }
}

private final class ProgressWebProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "8.8.8.8" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path.hasPrefix("/redirect/"), let hop = Int(url.lastPathComponent), hop < 7 {
            let next = url.deletingLastPathComponent().appendingPathComponent(String(hop + 1))
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil,
                headerFields: ["Location": next.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: next), redirectResponse: response)
            return
        }
        let html = url.path == "/large"
            ? "<html><head><script>" + String(repeating: " ", count: 1_100_000)
                + "</script></head><body><main><p>大网页中仍需读取的正文</p></main></body></html>"
            : "<html><body><main><p>重定向完成后的正文</p></main></body></html>"
        let data = Data(html.utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "text/html; charset=utf-8", "Content-Length": String(data.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
