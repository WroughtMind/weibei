import Combine
import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

@MainActor
extension XCTestCase {
    func waitForUserOperationRisk(_ center: UserOperationRiskCenter) async throws -> UserOperationRiskCenter.Request {
        if let request = center.pendingRequest { return request }
        let shown = expectation(description: "A concrete risk is presented to the user")
        var captured: UserOperationRiskCenter.Request?
        let observation = center.$pendingRequest.compactMap { $0 }.first().sink {
            captured = $0
            shown.fulfill()
        }
        await fulfillment(of: [shown], timeout: 3)
        withExtendedLifetime(observation) {}
        return try XCTUnwrap(captured)
    }
}

@MainActor
final class UserInitiatedOperationsTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    private func fixture() throws -> (root: URL, store: WorkspaceStore, item: StudyItem, url: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiUserOperation-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let backups = root.appendingPathComponent("unavailable-backups")
        try Data("not a directory".utf8).write(to: backups)
        let store = WorkspaceStore(workspaceDirectory: root.appendingPathComponent("workspace"),
            noteBackupRootURL: backups, startsAtBlankEntries: true, startsCourseFileMaintenance: false)
        let library = root.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "合成课程")
        let source = root.appendingPathComponent("合成笔记.md")
        try "磁盘正文".write(to: source, atomically: true, encoding: .utf8)
        let item = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .note).item
        let url = try XCTUnwrap(store.resolvedLibraryURL(for: item))
        store.activeNotebookItemID = item.id
        store.noteText = "魏碑正文"
        store.setNoteDraft("魏碑正文", for: item.id)
        return (root, store, item, url)
    }

    private func conflict(for itemID: String) -> NoteEditorRecoveryConflict {
        NoteEditorRecoveryConflict(diskMarkdown: "磁盘正文", checkpoint: NoteRecoveryCheckpoint(
            metadata: NoteRecoveryMetadata(documentID: itemID, baseFileDigest: "old",
                checkpointDigest: WorkspaceStore.noteContentDigest(Data("魏碑正文".utf8)),
                revision: 1, updatedAt: Date(), dialectVersion: 1), markdown: "魏碑正文"))
    }

    func testRiskRequestsAreQueuedAndCancellingOneDoesNotCancelAnother() async throws {
        let center = UserOperationRiskCenter()
        let first = Task { await center.confirm(title: "First", message: "First consequence") }
        let firstRequest = try await waitForUserOperationRisk(center)
        let second = Task { await center.confirm(title: "Second", message: "Second consequence") }
        await Task.yield()
        first.cancel()
        let firstChoice = await first.value
        XCTAssertFalse(firstChoice)
        let nextShown = expectation(description: "The second operation keeps its own choice")
        let observation = center.$pendingRequest.compactMap { $0 }
            .first { $0.id != firstRequest.id }.sink { _ in nextShown.fulfill() }
        await fulfillment(of: [nextShown], timeout: 3)
        let next = try XCTUnwrap(center.pendingRequest)
        XCTAssertEqual(next.title, "Second")
        center.respond(to: firstRequest.id, continuing: true)
        XCTAssertEqual(center.pendingRequest?.id, next.id, "A stale action cannot resolve a newer request")
        center.respond(to: next.id, continuing: true)
        let secondChoice = await second.value
        XCTAssertTrue(secondChoice)
        withExtendedLifetime(observation) {}
    }

    func testUnsavedConversationCanBeSentOrKeptAsDraftByChoice() async throws {
        for proceed in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiUnsavedChat-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let store = WorkspaceStore(workspaceDirectory: root,
                workspaceSnapshotWriter: { _, _ in throw CocoaError(.fileWriteOutOfSpace) },
                startsAtBlankEntries: true, startsCourseFileMaintenance: false)
            store.agentProviderID = .openai
            store.modelName = "mock"
            var calls = 0
            store.selfCheckAgentResponder = { _ in
                calls += 1
                return StudyAgentReply(text: "已回答", backend: .native)
            }
            defer { store.selfCheckAgentResponder = nil; store.cancelAllAgentRequests() }
            let session = try XCTUnwrap(store.activeStudySessionID)
            store.saveComposerDraft("问题仍应能发送", for: session)
            store.submitAgentDraft(sessionID: session)
            let operation = try XCTUnwrap(store.agentRuns[session]?.agentRequestTask)
            let risk = try await waitForUserOperationRisk(store.userOperationRisks)
            XCTAssertEqual(calls, 0)
            store.userOperationRisks.respond(to: risk.id, continuing: proceed)
            await operation.value
            XCTAssertEqual(calls, proceed ? 1 : 0)
            XCTAssertNil(store.userOperationRisks.pendingRequest, "One consent must cover the failed pre-dispatch saves")
            if !proceed { XCTAssertEqual(store.composerDraft(for: session), "问题仍应能发送") }
        }
    }

    func testConflictBackupFailureLetsUserContinueOrKeepBothVersions() async throws {
        for proceed in [false, true] {
            let f = try fixture()
            defer { try? FileManager.default.removeItem(at: f.root) }
            f.store.noteEditorRecoveryConflict = conflict(for: f.item.id)
            let operation = Task { await f.store.resolveNoteEditorRecoveryConflict(useDisk: false) }
            let request = try await waitForUserOperationRisk(f.store.userOperationRisks)
            XCTAssertEqual(request.context, .noteConflict)
            XCTAssertEqual(try String(contentsOf: f.url, encoding: .utf8), "磁盘正文")
            f.store.userOperationRisks.respond(to: request.id, continuing: proceed)
            await operation.value
            XCTAssertEqual(try String(contentsOf: f.url, encoding: .utf8), proceed ? "魏碑正文" : "磁盘正文")
            XCTAssertEqual(f.store.noteEditorRecoveryConflict == nil, proceed)
            if !proceed { XCTAssertEqual(f.store.notesByItemID[f.item.id], "魏碑正文") }
            XCTAssertNil(f.store.userOperationRisks.pendingRequest, "Consent must not loop back into the same preflight")
        }
    }

    func testUserCanAdoptDiskTextEvenWhenDiscardedDraftCannotBeBackedUp() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.store.noteEditorRecoveryConflict = conflict(for: f.item.id)
        let operation = Task { await f.store.resolveNoteEditorRecoveryConflict(useDisk: true) }
        let request = try await waitForUserOperationRisk(f.store.userOperationRisks)
        f.store.userOperationRisks.respond(to: request.id, continuing: true)
        await operation.value
        XCTAssertNil(f.store.noteEditorRecoveryConflict)
        XCTAssertNil(f.store.notesByItemID[f.item.id])
        XCTAssertEqual(f.store.noteText, "磁盘正文")
        XCTAssertEqual(try String(contentsOf: f.url, encoding: .utf8), "磁盘正文")
    }

    func testExplicitSaveCompletesAfterBackupRiskIsAccepted() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let operation = Task { await f.store.retryActiveNoteSaveFromUser() }
        let request = try await waitForUserOperationRisk(f.store.userOperationRisks)
        XCTAssertEqual(request.context, .workspace)
        f.store.userOperationRisks.respond(to: request.id, continuing: true)
        await operation.value
        XCTAssertEqual(try String(contentsOf: f.url, encoding: .utf8), "魏碑正文")
        XCTAssertNil(f.store.notesByItemID[f.item.id])
        XCTAssertNil(f.store.noteOperationErrorsByItemID[f.item.id])
    }

    func testRenameRewriteCompletesAfterBackupRiskIsAccepted() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let text = "# \(f.store.displayTitle(for: f.item))\n\n最新编辑"
        f.store.noteText = text
        f.store.setNoteDraft(text, for: f.item.id)
        let operation = Task { await f.store.renameNotebookNoteInTransaction(itemID: f.item.id, to: "新的名字") }
        let request = try await waitForUserOperationRisk(f.store.userOperationRisks)
        f.store.userOperationRisks.respond(to: request.id, continuing: true)
        await operation.value
        let renamed = f.url.deletingLastPathComponent().appendingPathComponent("新的名字.md")
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "# 新的名字\n\n最新编辑")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        XCTAssertNil(f.store.userOperationRisks.pendingRequest)
    }

    func testConfirmedReplacementStillRejectsASymbolicLink() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let outside = f.root.appendingPathComponent("unrelated.md")
        try "其他文件".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: f.url)
        try FileManager.default.createSymbolicLink(at: f.url, withDestinationURL: outside)
        XCTAssertThrowsError(try f.store.writeNotebookMarkdownThroughGate("替换内容", itemID: f.item.id,
            url: f.url, expectedBaseline: nil, overwritingAfterUserChoice: true))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "其他文件")
    }

    func testUserCanSwitchNotesAfterEditorSnapshotFailure() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.store.noteEditingSession.replaceDocument(with: f.item.id)
        _ = f.store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(documentID: f.item.id,
            documentGeneration: f.store.noteEditingSession.documentGeneration, revision: 1, dirty: true))
        let switched = expectation(description: "The original navigation executes after consent")
        f.store.requestNoteSelectionTransition(to: "another-note") { switched.fulfill() }
        let request = try await waitForUserOperationRisk(f.store.userOperationRisks)
        f.store.userOperationRisks.respond(to: request.id, continuing: true)
        await fulfillment(of: [switched], timeout: 3)
        XCTAssertEqual(f.store.notesByItemID[f.item.id], "魏碑正文")
    }

    func testRelaunchSaveFailureRespectsTheUsersChoice() async throws {
        for proceed in [false, true] {
            let f = try fixture()
            defer { try? FileManager.default.removeItem(at: f.root) }
            f.store.noteEditingSession.replaceDocument(with: f.item.id)
            f.store.noteEditingSession.markSaveFailed(documentID: f.item.id)
            let operation = Task { await f.store.prepareForUserRequestedRelaunch() }
            let request = try await waitForUserOperationRisk(f.store.userOperationRisks)
            f.store.userOperationRisks.respond(to: request.id, continuing: proceed)
            let approved = await operation.value
            XCTAssertEqual(approved, proceed)
            XCTAssertEqual(f.store.allowsUnsavedRelaunch, proceed)
        }
    }

    func testAssistantCreatesANewDocumentWithoutSizeOrModePreflight() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiDocument-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let documents = root.appendingPathComponent("NativeAgent/Documents")
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let content = String(repeating: "正文", count: 100_000)
        let arguments = try JSONSerialization.data(withJSONObject: ["title": "文稿", "format": "markdown", "content": content])
        let request = StudyAgentRequest(purpose: .conversation, question: "保存这份文稿", materialTitle: "",
            materialText: "", noteTitle: "", noteText: "", contextRevision: "test")
        let result = try await registry.execute(NativeToolCallRequest(name: "create_document",
            argumentsJSON: String(decoding: arguments, as: UTF8.self), callID: "document"),
            context: NativeToolExecutionContext(request: request, liveStores: NativeLiveStores(documentsRoot: documents)),
            scope: .global)
        let path = try XCTUnwrap(result.details["path"] as? String)
        XCTAssertFalse(result.isError)
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), content)
    }

    func testGenUIToolNormalizesMetadataAndKeepsLargeContent() async throws {
        let registry = NativeToolRegistry()
        await NativeBuiltinTools.registerAll(into: registry, skillRoot: nil)
        let content = String(repeating: "完整的学习内容", count: 60_000)
        let arguments = try JSONSerialization.data(withJSONObject: [
            "id": "课堂对比 图一", "spec": ["type": "text", "content": content],
        ])
        let request = StudyAgentRequest(purpose: .conversation, question: "展示全部内容", materialTitle: "",
            materialText: "", noteTitle: "", noteText: "", contextRevision: "test")
        let result = try await registry.execute(NativeToolCallRequest(name: "render_ui",
            argumentsJSON: String(decoding: arguments, as: UTF8.self), callID: "ui"),
            context: NativeToolExecutionContext(request: request), scope: .global)
        XCTAssertFalse(result.isError)
        let id = try XCTUnwrap(result.details["id"] as? String)
        XCTAssertNotNil(id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression))
        let spec = try XCTUnwrap(result.details["spec"] as? [String: Any])
        let items = try XCTUnwrap(spec["items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["content"] as? String, content)
    }

    func testUnreadableDuplicateComparisonStillImportsASeparateCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WeiBeiComparison-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("file.txt")
        let existing = directory.appendingPathComponent("file.txt")
        try Data("source".utf8).write(to: source)
        try Data("target".utf8).write(to: existing)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: existing.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: existing.path) }
        let imported = try ImportFileCopy.copyPreservingOriginal(from: source, into: directory)
        XCTAssertNotEqual(imported, existing)
        XCTAssertEqual(try Data(contentsOf: imported), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
    }
}
