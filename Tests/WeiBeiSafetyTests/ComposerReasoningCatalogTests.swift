import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class ComposerReasoningCatalogTests: XCTestCase {
    @MainActor
    func testColdComposerPublishesCodexCapabilitiesWithoutSettingsOrRepeatedReset() async throws {
        var loads = 0
        let account = AgentAccountService(modelCatalogLoader: { provider, _ in
            XCTAssertEqual(provider, .openaiCodex)
            loads += 1
            await Task.yield()
            return .init(ids: ["synthetic-model"], reasoningLevels: ["synthetic-model": ["low", "high"]])
        })
        XCTAssertTrue(account.reasoningLevels(provider: .openaiCodex, model: "synthetic-model").isEmpty)
        account.refreshReasoningCatalogIfNeeded(provider: .openaiCodex, baseURL: "")
        account.refreshReasoningCatalogIfNeeded(provider: .openaiCodex, baseURL: "")
        for _ in 0..<100 where account.isRefreshingModels { await Task.yield() }
        XCTAssertFalse(account.isRefreshingModels)
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(account.reasoningLevels(provider: .openaiCodex, model: "synthetic-model"), ["low", "high"])
        account.refreshReasoningCatalogIfNeeded(provider: .openaiCodex, baseURL: "")
        XCTAssertEqual(loads, 1)
        XCTAssertEqual(account.models(provider: .openaiCodex), ["synthetic-model"])
        XCTAssertTrue(account.reasoningLevels(provider: .openai, model: "synthetic-model").isEmpty)
    }

    @MainActor
    func testColdCapabilityLookupDoesNotQueryOtherProvidersOrChooseAModel() async throws {
        var loads = 0
        let account = AgentAccountService(modelCatalogLoader: { _, _ in
            loads += 1
            return .init(ids: ["server-first"], reasoningLevels: [:])
        })
        account.refreshReasoningCatalogIfNeeded(provider: .custom, baseURL: "https://synthetic.example.test")
        await Task.yield()
        XCTAssertEqual(loads, 0)
        XCTAssertFalse(account.isRefreshingModels)
        XCTAssertTrue(account.models(provider: .custom).isEmpty)
    }
}
