import Foundation
import XCTest
@testable import WeiBei
import WeiBeiCore

final class WorkspaceStorePersistenceTests: WorkspaceStoreTestCase {
    /**
     * 验证显式工作区的样例资源不会越界写入用户 Application Support。
     */
    @MainActor
    func testSampleResourcesStayInsideExplicitWorkspace() throws {
        let directory = try makeTemporaryWorkspace()
        let store = makeStore(in: directory)
        let samplePDF = try XCTUnwrap(store.sampleItems.first { $0.kind == .pdf }?.url)

        XCTAssertTrue(samplePDF.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: samplePDF.path))
    }

    /**
     * 验证工作区状态经显式 durability boundary 后可由新 Store 完整恢复。
     */
    @MainActor
    func testWorkspaceSettingsPersistAcrossReload() throws {
        let directory = try makeTemporaryWorkspace()
        let store = makeStore(in: directory)

        store.setDailyInspirationEnabled(false)
        store.setImportedDocumentColorAdaptation(false)
        store.setInterfaceLanguage(.english)
        store.setNoteRenderMode(.source)
        store.showReader = false
        store.showAgent = true
        store.showNotes = false
        XCTAssertTrue(store.flushPendingWorkspaceSave())

        let restored = makeStore(in: directory)
        XCTAssertFalse(restored.showDailyInspiration)
        XCTAssertFalse(restored.adaptImportedDocumentColors)
        XCTAssertEqual(restored.interfaceLanguage, .english)
        XCTAssertEqual(restored.noteRenderMode, .source)
        XCTAssertFalse(restored.showReader)
        XCTAssertTrue(restored.showAgent)
        XCTAssertFalse(restored.showNotes)
    }

    /**
     * 验证旧快照缺失偏好时使用安全默认值，并归一化已移除的瞬态 UI 状态。
     */
    @MainActor
    func testLegacySnapshotDefaultsAndTransientStatesAreNormalized() throws {
        let directory = try makeTemporaryWorkspace()
        let snapshot = PersistedWorkspace(
            selectedItemID: "sample-pdf",
            workspaceLayout: .documentAgentNotes,
            agentSurface: .selectionFloat,
            noteRenderMode: .preview
        )
        try JSONEncoder().encode(snapshot).write(
            to: directory.appendingPathComponent("workspace.json"),
            options: [.atomic]
        )

        let store = makeStore(in: directory)
        XCTAssertTrue(store.showDailyInspiration)
        XCTAssertTrue(store.adaptImportedDocumentColors)
        XCTAssertEqual(store.noteRenderMode, .rich)
        XCTAssertEqual(store.agentSurface, .hidden)
    }

    /**
     * 验证快照写入失败会保持可见错误，并允许同一 Store 重试成功。
     */
    @MainActor
    func testWorkspaceSaveFailureIsVisibleAndRetryable() throws {
        enum WriteFailure: Error {
            case rejected
        }

        let directory = try makeTemporaryWorkspace()
        var rejectsWrites = true
        let profile = AgentCredentialProfile(name: "Test", provider: .openai)
        let store = WorkspaceStore(
            workspaceDirectory: directory,
            workspaceSnapshotWriter: { data, url in
                if rejectsWrites {
                    throw WriteFailure.rejected
                }
                try data.write(to: url, options: [.atomic])
            },
            credentialProfiles: [profile],
            activeCredentialProfileID: profile.id,
            storedAPIKeyResolver: { "" }
        )

        store.setDailyInspirationEnabled(false)
        XCTAssertFalse(store.flushPendingWorkspaceSave())
        XCTAssertNotNil(store.workspaceSaveError)

        rejectsWrites = false
        XCTAssertTrue(store.retryWorkspaceSave())
        XCTAssertTrue(store.flushPendingWorkspaceSave())
        XCTAssertNil(store.workspaceSaveError)
        XCTAssertFalse(makeStore(in: directory).showDailyInspiration)
    }
}
