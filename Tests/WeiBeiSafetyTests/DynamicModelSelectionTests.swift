import XCTest
@testable import WeiBei
import WeiBeiCore

final class DynamicModelSelectionTests: XCTestCase {
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
}
