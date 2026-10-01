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
    @MainActor
    func testEmptyProbePublishesRetryableCatalogRatherThanAuthenticationFailure() async throws {
        let account = AgentAccountService(modelCatalogLoader: { _, _ in
            .init(ids: [], reasoningLevels: [:])
        })
        let result = await account.probeConnection(provider: .openaiCodex, baseURL: "")
        XCTAssertEqual(result, .success(0))
        XCTAssertNil(account.modelListFailure)
        XCTAssertNotNil(account.modelListMessage)
        XCTAssertTrue(account.modelListCanRetry)
        XCTAssertFalse(account.isRefreshingModels)
    }

    @MainActor
    func testOlderCatalogRequestCannotReplaceNewerConnectionCatalog() async throws {
        var pending: [CheckedContinuation<AgentAccountService.ModelCatalog, Error>] = []
        let account = AgentAccountService(modelCatalogLoader: { _, _ in
            try await withCheckedThrowingContinuation { pending.append($0) }
        })
        let old = Task { await account.probeConnection(provider: .openai, baseURL: "") }
        let firstDeadline = Date().addingTimeInterval(5)
        while pending.count < 1 && Date() < firstDeadline { await Task.yield() }
        guard pending.count == 1 else { old.cancel(); return XCTFail("First synthetic catalog request did not start") }
        let current = Task { await account.probeConnection(provider: .anthropic, baseURL: "") }
        let secondDeadline = Date().addingTimeInterval(5)
        while pending.count < 2 && Date() < secondDeadline { await Task.yield() }
        guard pending.count == 2 else {
            old.cancel(); current.cancel()
            pending[0].resume(throwing: CancellationError())
            return XCTFail("Second synthetic catalog request did not start")
        }
        pending[1].resume(returning: .init(ids: ["newer-model"], reasoningLevels: [:]))
        let currentResult = await current.value
        XCTAssertEqual(currentResult, .success(1))
        pending[0].resume(returning: .init(ids: ["obsolete-model"], reasoningLevels: [:]))
        let oldResult = await old.value
        XCTAssertEqual(oldResult, .failure(.superseded))
        XCTAssertEqual(account.models(provider: .anthropic), ["newer-model"])
        XCTAssertTrue(account.models(provider: .openai).isEmpty)
    }

    @MainActor
    func testSwitchingToColdCodexSupersedesAnotherProvidersPendingCatalog() async throws {
        var pending: [CheckedContinuation<AgentAccountService.ModelCatalog, Error>] = []
        let account = AgentAccountService(modelCatalogLoader: { _, _ in
            try await withCheckedThrowingContinuation { pending.append($0) }
        })
        account.refreshModels(provider: .openai, baseURL: "")
        let firstDeadline = Date().addingTimeInterval(5)
        while pending.count < 1 && Date() < firstDeadline { await Task.yield() }
        guard pending.count == 1 else { return XCTFail("First synthetic request did not start") }
        account.refreshReasoningCatalogIfNeeded(provider: .openaiCodex, baseURL: "")
        let secondDeadline = Date().addingTimeInterval(5)
        while pending.count < 2 && Date() < secondDeadline { await Task.yield() }
        guard pending.count == 2 else {
            pending[0].resume(throwing: CancellationError())
            return XCTFail("The cold Codex lookup was incorrectly blocked by another provider")
        }
        pending[1].resume(returning: .init(ids: ["codex-model"], reasoningLevels: ["codex-model": ["low", "high"]]))
        let publishDeadline = Date().addingTimeInterval(5)
        while account.isRefreshingModels && Date() < publishDeadline { await Task.yield() }
        XCTAssertFalse(account.isRefreshingModels)
        pending[0].resume(returning: .init(ids: ["obsolete-openai-model"], reasoningLevels: [:]))
        await Task.yield()
        XCTAssertEqual(account.models(provider: .openaiCodex), ["codex-model"])
        XCTAssertEqual(account.reasoningLevels(provider: .openaiCodex, model: "codex-model"), ["low", "high"])
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
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let evidence = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/native-fix-evidence", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try png.write(to: evidence.appendingPathComponent("cold-codex-composer.png"))
    }
}
#endif
