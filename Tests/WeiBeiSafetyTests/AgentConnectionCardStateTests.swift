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
        XCTAssertEqual(state.probingProfileID, profile)
        state.invalidate(profile)
        XCTAssertNil(state.probingProfileID)
        XCTAssertNil(state.marks[profile])
        state.complete(profile, requestID: old, mark: .init(text: "stale success", ok: true))
        XCTAssertNil(state.marks[profile])
        let current = state.begin(profile)
        state.complete(profile, requestID: old, mark: .init(text: "late stale success", ok: true))
        XCTAssertEqual(state.probingProfileID, profile)
        XCTAssertNil(state.marks[profile])
        state.complete(profile, requestID: current, mark: .init(text: "new rejection", ok: false))
        XCTAssertEqual(state.marks[profile]?.ok, false)
        XCTAssertNil(state.probingProfileID)
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
        try store.createAgentConnection(provider: .custom, authMethod: .apiKey,
                                        baseURL: "https://manual-model.example.test/v1")
        XCTAssertTrue(store.saveManualAgentModel("  unlisted/private-deployment  "))
        XCTAssertEqual(store.modelName, "unlisted/private-deployment")
        XCTAssertEqual(store.agentCredentialProfiles.first(where: { $0.id == store.activeAgentProfileID })?.modelName, store.modelName)
        XCTAssertFalse(store.saveManualAgentModel(" \n "))
        XCTAssertEqual(store.modelName, "unlisted/private-deployment")
    }
}

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import SwiftUI

extension AgentConnectionCardStateTests {
    @MainActor
    func testNativeConnectionCardRendersAnExplicitUnlistedModel() async throws {
        let keys = ["weibei.agentCredentialProfiles.v1", "weibei.agentCredentialActiveProfileID.v1"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
            try? FileManager.default.removeItem(at: root)
        }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let profile = AgentCredentialProfile(name: "Synthetic connection", provider: .custom,
            modelName: "private-model/synthetic", baseURL: "https://\(UUID().uuidString.lowercased()).example.test/v1")
        store.agentCredentialProfiles = [profile]
        AgentCredentialProfileStore.saveProfiles([profile])
        store.selectAgentCredentialProfile(profile.id)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: AgentConnectionCardsView().environmentObject(store).padding(20))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 320),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(store.modelName, "private-model/synthetic", "Rendering and an unavailable catalog must preserve the explicit choice")
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/native-fix-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try png.write(to: evidence.appendingPathComponent("connection-settings.png"))
    }
}
#endif

extension AgentConnectionCardStateTests {
    @MainActor
    func testKeySaveReportsFailureWithoutReplacingStoredCredential() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let credentials = NativeAgentCredentialStore(fileURL: root.appendingPathComponent("synthetic.json"))
        let endpoint = try AgentProviderEndpoint(provider: .custom, baseURL: "https://gateway.example.test/v1")
        try credentials.upsert(.init(provider: endpoint.credentialProviderID, apiKey: "synthetic-original", boundEndpoint: endpoint.baseURL))
        let original = try Data(contentsOf: credentials.fileURL)
        let account = AgentAccountService()
        XCTAssertFalse(account.startAPIKeyLogin("synthetic-replacement", provider: .custom, baseURL: "", credentialStore: credentials))
        XCTAssertNotNil(account.lastError)
        XCTAssertEqual(try Data(contentsOf: credentials.fileURL), original)
        XCTAssertFalse(account.startAPIKeyLogin("  ", provider: .custom, baseURL: endpoint.baseURL!, credentialStore: credentials))
        XCTAssertEqual(try Data(contentsOf: credentials.fileURL), original)
        let blocked = root.appendingPathComponent("blocked-parent")
        try Data("synthetic blocker".utf8).write(to: blocked)
        let unavailable = NativeAgentCredentialStore(fileURL: blocked.appendingPathComponent("credential.json"))
        XCTAssertFalse(account.startAPIKeyLogin("synthetic-replacement", provider: .custom, baseURL: endpoint.baseURL!, credentialStore: unavailable))
        XCTAssertNotNil(account.lastError)
        XCTAssertTrue(account.startAPIKeyLogin("synthetic-replacement", provider: .custom, baseURL: endpoint.baseURL!, credentialStore: credentials))
        XCTAssertNil(account.lastError)
        XCTAssertEqual(try credentials.load()[endpoint.credentialProviderID]?.apiKey, "synthetic-replacement")
    }
}
