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

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
import SwiftUI

private struct ColdComposerFixture: View {
    var account: AgentAccountService
    @FocusState var focused: Bool
    var body: some View {
        ComposerView(agentAccount: account, prompt: "Synthetic question", focused: $focused,
                     fontSize: 14, lineLimit: 1...3, height: 48,
                     sendButtonSize: 24, trailingPadding: 8, sendTrailing: 8,
                     showsReasoningEffort: true, submit: {})
    }
}

extension ComposerReasoningCatalogTests {
    @MainActor
    func testNativeColdComposerStartsCapabilityLookupWithoutOpeningSettings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keys = ["weibei.agentCredentialProfiles.v1", "weibei.agentCredentialActiveProfileID.v1"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
            try? FileManager.default.removeItem(at: root)
        }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        store.setAgentProviderID(.openaiCodex)
        store.updateModelName("synthetic-model")
        var loads = 0
        let account = AgentAccountService(modelCatalogLoader: { _, _ in
            loads += 1
            return .init(ids: ["synthetic-model"], reasoningLevels: ["synthetic-model": ["low", "high"]])
        })
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: ColdComposerFixture(account: account).environmentObject(store))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 130),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        let deadline = Date().addingTimeInterval(5)
        while account.reasoningLevels(provider: .openaiCodex, model: "synthetic-model").isEmpty && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(loads, 1, "Opening the real composer must start the cold capability lookup")
        XCTAssertEqual(account.reasoningLevels(provider: .openaiCodex, model: "synthetic-model"), ["low", "high"])
        XCTAssertEqual(store.modelName, "synthetic-model")
    }
}
#endif
