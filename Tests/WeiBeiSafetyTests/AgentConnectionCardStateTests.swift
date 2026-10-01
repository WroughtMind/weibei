import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class AgentConnectionCardStateTests: XCTestCase {
    @MainActor
    func testCustomCredentialStatusResolvesExactEndpointAndRejectsOtherGateway() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = NativeAgentCredentialStore(fileURL: root.appendingPathComponent("synthetic.json"))
        for provider in [AgentProviderID.custom, .llamaCpp] {
            let endpoint = try AgentProviderEndpoint(provider: provider, baseURL: "https://gateway-a.example.test/v1")
            try credentials.upsert(.init(provider: endpoint.credentialProviderID, apiKey: "synthetic-key", boundEndpoint: endpoint.baseURL))
            XCTAssertEqual(AgentAccountService.connectionAPIKey(provider: provider, baseURL: " HTTPS://gateway-a.example.test:443/v1/ ", credentialStore: credentials), "synthetic-key")
            XCTAssertNil(AgentAccountService.connectionAPIKey(provider: provider, baseURL: "https://gateway-b.example.test/v1", credentialStore: credentials))
            XCTAssertNil(AgentAccountService.connectionAPIKey(provider: provider, baseURL: "", credentialStore: credentials))
        }
    }

    func testReplacingCredentialClearsSuccessAndRejectsLateOldProbe() {
        var state = AgentConnectionProbeState()
        let profile = UUID()
        let initial = state.begin(profile)
        state.complete(profile, requestID: initial, mark: .init(text: "synthetic success", ok: true))
        XCTAssertEqual(state.marks[profile]?.ok, true)
        let old = state.begin(profile)
        state.invalidate(profile)
        XCTAssertNil(state.marks[profile])
        state.complete(profile, requestID: old, mark: .init(text: "stale success", ok: true))
        XCTAssertNil(state.marks[profile])
        let current = state.begin(profile)
        state.complete(profile, requestID: current, mark: .init(text: "new rejection", ok: false))
        XCTAssertEqual(state.marks[profile]?.ok, false)
        state.invalidateAll()
        XCTAssertTrue(state.marks.isEmpty)
    }

    @MainActor
    func testManualModelAcceptsUnlistedIDAndPreservesChoiceForBlankInput() throws {
        let keys = ["weibei.agentCredentialProfiles.v1", "weibei.agentCredentialActiveProfileID.v1"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
            try? FileManager.default.removeItem(at: root)
        }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        XCTAssertTrue(store.saveManualAgentModel("  unlisted/private-deployment  "))
        XCTAssertEqual(store.modelName, "unlisted/private-deployment")
        XCTAssertEqual(store.agentCredentialProfiles.first(where: { $0.id == store.activeAgentProfileID })?.modelName, store.modelName)
        XCTAssertFalse(store.saveManualAgentModel(" \n "))
        XCTAssertEqual(store.modelName, "unlisted/private-deployment")
    }
}
