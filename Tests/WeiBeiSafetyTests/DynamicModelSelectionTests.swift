import Foundation
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
}
