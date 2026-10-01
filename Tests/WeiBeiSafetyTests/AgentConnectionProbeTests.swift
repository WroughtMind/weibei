import Foundation
import XCTest
@testable import WeiBeiCore

final class AgentConnectionProbeTests: XCTestCase {
    private final class MockProtocol: URLProtocol {
        static var status = 200
        static var requests = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.requests += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            let body = #"{"models":[{"slug":"synthetic-model","supported_in_api":true,"visibility":"list","supported_reasoning_levels":[{"effort":"low"},{"effort":"high"}]}]}"#
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    func testCodexProbeRechecksAuthenticationDespiteWarmCatalog() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = AgentModelListService(session: session)
        let strategy = ModelListStrategy.codexSubscription(token: "synthetic-token", accountID: "synthetic-account")
        MockProtocol.status = 200
        MockProtocol.requests = 0
        let models = try await service.fetchModels(strategy: strategy, apiKey: "")
        XCTAssertEqual(models, ["synthetic-model"])
        MockProtocol.status = 401
        do {
            _ = try await service.probe(strategy: strategy, apiKey: "")
            XCTFail("A warm catalog must not certify a rejected credential")
        } catch let error as ModelListError {
            guard case .http(let status, _) = error else { return XCTFail("Expected authentication failure, got \(error)") }
            XCTAssertEqual(status, 401)
        }
        XCTAssertEqual(MockProtocol.requests, 2)
    }
}
