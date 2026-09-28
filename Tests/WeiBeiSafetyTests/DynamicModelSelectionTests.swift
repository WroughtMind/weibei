import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class DynamicModelSelectionTests: XCTestCase {
    private final class ModelListProtocol: URLProtocol {
        static var response: (status: Int, json: [String: Any])?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let response = Self.response else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self,
                didLoad: try! JSONSerialization.data(withJSONObject: response.json)
            )
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @MainActor
    func testCatalogNeverAddsDefaultsAndSendingRequiresExplicitModel() throws {
        XCTAssertEqual(
            AgentAccountService.catalogEntries(
                ["server-model"],
                loadedFor: .openai,
                provider: .openai
            ),
            ["server-model"]
        )
        XCTAssertEqual(
            AgentAccountService.catalogEntries(
                ["other-provider-model"],
                loadedFor: .anthropic,
                provider: .openai
            ),
            []
        )
        XCTAssertEqual(
            AgentAccountService.catalogEntries(
                ["", "  ", "  server-model  "],
                loadedFor: .openai,
                provider: .openai
            ),
            ["server-model"]
        )
        XCTAssertThrowsError(
            try WorkspaceStore.explicitAgentModel("  \n", language: .chinese)
        )
        XCTAssertEqual(
            try WorkspaceStore.explicitAgentModel("  chosen-model  ", language: .chinese),
            "chosen-model"
        )
    }

    @MainActor
    func testEmptyModelBlocksBeforeHistoryAndPreservesDraft() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiEmptyModelTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(
            workspaceDirectory: root,
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        let session = try XCTUnwrap(store.createStudySession(courseID: nil))
        store.modelName = "  "
        store.saveComposerDraft("保留这段未发送的问题", for: session.id)

        store.submitAgentDraft(sessionID: session.id)

        XCTAssertEqual(store.composerDraft(for: session.id), "保留这段未发送的问题")
        XCTAssertTrue(store.conversationMessages(in: session.id).isEmpty)
        XCTAssertNil(store.agentRuns[session.id]?.agentRequestTask)
        XCTAssertNotNil(store.importantOperationError)
    }

    func testQueryableProvidersAcceptSuccessfulEmptyCatalogButRejectMissingArray() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelListProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = AgentModelListService(session: session)
        defer {
            ModelListProtocol.response = nil
            session.invalidateAndCancel()
        }

        ModelListProtocol.response = (200, ["data": []])
        let openAIModels = try await service.fetchModels(
            strategy: .openAICompatible(base: "https://models.example.test"),
            apiKey: "test-key"
        )
        XCTAssertTrue(openAIModels.isEmpty)

        ModelListProtocol.response = (200, ["publisherModels": []])
        let publisherModels = try await service.fetchModels(
            strategy: .googlePublisherModels(base: "https://publisher.example.test"),
            apiKey: "test-key"
        )
        XCTAssertTrue(publisherModels.isEmpty)

        ModelListProtocol.response = (200, ["models": []])
        let codexModels = try await service.fetchModels(
            strategy: .codexSubscription(token: "test-token", accountID: "test-account"),
            apiKey: ""
        )
        XCTAssertTrue(codexModels.isEmpty)

        ModelListProtocol.response = (200, [:])
        do {
            _ = try await service.fetchModels(
                strategy: .openAICompatible(base: "https://models.example.test"),
                apiKey: "test-key"
            )
            XCTFail("缺少模型数组必须继续显示为获取失败")
        } catch let error as ModelListError {
            XCTAssertEqual(error, .decoding("missing data array"))
        }
    }

    @MainActor
    func testSuccessfulEmptyCatalogShowsRetryableEmptyState() {
        let empty = AgentAccountService.successfulModelListState([])
        XCTAssertNotNil(empty.message)
        XCTAssertTrue(empty.canRetry)

        let populated = AgentAccountService.successfulModelListState(["catalyst-second-check"])
        XCTAssertNil(populated.message)
        XCTAssertFalse(populated.canRetry)
    }
}
