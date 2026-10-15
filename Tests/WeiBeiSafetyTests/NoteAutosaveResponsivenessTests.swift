import Foundation
import WeiBeiCore
import XCTest
@testable import WeiBei

@MainActor
final class NoteAutosaveResponsivenessTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    private func fixture(
        notebookWriter: @escaping (String, URL) throws -> Void = {
            try WorkspaceStore.writeNotebookMarkdown($0, to: $1)
        },
        workspaceWriter: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: [.atomic])
        }
    ) throws -> (root: URL, store: WorkspaceStore, item: StudyItem, url: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-autosave-\(UUID().uuidString)", isDirectory: true)
        let library = root.appendingPathComponent("资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: root.appendingPathComponent("workspace", isDirectory: true),
            notebookMarkdownWriter: notebookWriter,
            noteBackupRootURL: root.appendingPathComponent("backups", isDirectory: true),
            workspaceSnapshotWriter: workspaceWriter,
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "自动保存课")
        let source = root.appendingPathComponent("笔记.md")
        try "磁盘基线".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .note)
        let url = try XCTUnwrap(store.resolvedLibraryURL(for: imported.item))
        store.activeNotebookItemID = imported.item.id
        store.noteEditingSession.replaceDocument(with: imported.item.id)
        store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
            documentID: imported.item.id,
            documentGeneration: store.noteEditingSession.documentGeneration,
            revision: 1,
            dirty: true
        ))
        XCTAssertTrue(store.flushPendingWorkspaceSave())
        return (root, store, imported.item, url)
    }

    private func waitForAutosave(
        _ store: WorkspaceStore,
        until completed: @escaping @MainActor () -> Bool
    ) throws {
        // Setup runs at the existing synchronous test boundary; the actual
        // delayed autosave and this heartbeat run as independent MainActor tasks.
        let autosaves = Array(store.pendingNotePersistenceTasks.values)
        try store.waitForCourseFileOperation {
            var heartbeatRan = false
            Task { @MainActor in heartbeatRan = true }
            let deadline = Date().addingTimeInterval(3)
            while !completed(), Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(heartbeatRan, "自动保存不应阻塞下一次主线程任务")
            XCTAssertTrue(completed(), "自动保存应取得收据，而不是进入同步等待超时")
            for autosave in autosaves { await autosave.value }
            let persisted = await store.flushPendingWorkspaceSaveAsync()
            XCTAssertTrue(persisted)
        }
    }

    func testDelayedAutosaveRetainsExternalConflictWithoutBlockingMainActor() throws {
        let note = try fixture()
        defer { try? FileManager.default.removeItem(at: note.root) }
        try "外部修改".write(to: note.url, atomically: true, encoding: .utf8)

        note.store.scheduleNotePersistence("应用内待写正文", for: note.item)
        try waitForAutosave(note.store) {
            note.store.noteEditorRecoveryConflict?.checkpointIsPersisted == true
        }

        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "外部修改")
        XCTAssertEqual(note.store.notesByItemID[note.item.id], "应用内待写正文")
        XCTAssertTrue(note.store.noteEditingSession.dirty)
        XCTAssertEqual(note.store.noteEditingSession.saveStatus, .externallyModified)
        try note.store.waitForCourseFileOperation {
            let saved = try await note.store.noteRecoveryStore.load(documentID: note.item.id)
            XCTAssertEqual(saved?.markdown, "应用内待写正文")
            XCTAssertEqual(saved?.metadata.revision, 1)
        }
    }

    func testDelayedAutosaveWriteFailureKeepsDraftDirtyAndDurable() throws {
        let note = try fixture(notebookWriter: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        defer { try? FileManager.default.removeItem(at: note.root) }

        note.store.scheduleNotePersistence("失败后仍要保留的正文", for: note.item)
        try waitForAutosave(note.store) {
            note.store.importantOperationNotice == .noteWriteSafetyHold(fileName: note.url.lastPathComponent)
        }

        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "磁盘基线")
        XCTAssertEqual(note.store.notesByItemID[note.item.id], "失败后仍要保留的正文")
        XCTAssertTrue(note.store.noteEditingSession.dirty)
        XCTAssertEqual(note.store.noteEditingSession.saveStatus, .failed)
        let persisted = try JSONDecoder().decode(
            PersistedWorkspace.self,
            from: Data(contentsOf: note.store.storageURL)
        )
        XCTAssertEqual(persisted.notesByItemID[note.item.id], "失败后仍要保留的正文")
    }

    func testEarlierAutosaveFailureDoesNotReturnAfterNewerSuccessfulSave() throws {
        try assertEarlierAutosaveFailureDoesNotReturn(retryRevision: 2, retryMarkdown: "第二版已成功保存的正文")
    }

    /// Exercise the same request/receive callback as RichMarkdownEditorView,
    /// from a MainActor task where a synchronous run-loop bridge cannot progress.
    private func bindEditorSnapshot(
        in store: WorkspaceStore,
        markdown: String,
        onDelivered: @escaping @MainActor () -> Void = {}
    ) -> UUID {
        store.noteEditingSession.bindSnapshotRequestHandler { request in
            Task { @MainActor in
                let started = Date()
                XCTAssertTrue(store.noteEditingSession.receive(NoteEditorSnapshotReadyEvent(
                    requestID: request.requestID ?? request.commandID,
                    documentID: request.documentID,
                    documentGeneration: request.documentGeneration,
                    revision: request.minimumRevision ?? 0,
                    markdown: markdown
                )))
                XCTAssertLessThan(Date().timeIntervalSince(started), 2,
                                  "编辑器快照回调不能同步等待另一个主线程保存任务")
                onDelivered()
            }
        }
    }

    func testEditorSnapshotConflictReturnsPromptlyAndRetainsBothVersions() throws {
        let note = try fixture()
        defer { try? FileManager.default.removeItem(at: note.root) }
        try "外部修改".write(to: note.url, atomically: true, encoding: .utf8)
        let token = bindEditorSnapshot(in: note.store, markdown: "编辑器里的新正文")
        defer { note.store.noteEditingSession.unbindSnapshotRequestHandler(token) }

        try note.store.waitForCourseFileOperation {
            let captured = await note.store.freshActiveNoteEditorSnapshot()
            XCTAssertTrue(captured)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "外部修改")
            XCTAssertEqual(note.store.notesByItemID[note.item.id], "编辑器里的新正文")
            XCTAssertTrue(note.store.noteEditingSession.dirty)
            XCTAssertEqual(note.store.noteEditingSession.saveStatus, .externallyModified)
            XCTAssertTrue(note.store.noteEditorRecoveryConflict?.checkpointIsPersisted == true)
            let recovered = try await note.store.noteRecoveryStore.load(documentID: note.item.id)
            XCTAssertEqual(recovered?.markdown, "编辑器里的新正文")
        }
    }

    func testEditorSnapshotFailureKeepsUIResponsiveAndLifecycleWaitsForDurability() throws {
        let gate = AutosaveWorkspaceWriterGate()
        let note = try fixture(
            notebookWriter: { _, _ in throw CocoaError(.fileWriteNoPermission) },
            workspaceWriter: { data, url in try gate.write(data, to: url) }
        )
        defer { gate.release(); try? FileManager.default.removeItem(at: note.root) }
        var callbackReturned = false
        let token = bindEditorSnapshot(in: note.store, markdown: "写入失败也不能丢的正文") {
            callbackReturned = true
        }
        defer { note.store.noteEditingSession.unbindSnapshotRequestHandler(token) }
        gate.arm()

        try note.store.waitForCourseFileOperation {
            var lifecycleFinished = false
            let lifecycle = Task { @MainActor in
                let captured = await note.store.freshActiveNoteEditorSnapshot()
                lifecycleFinished = true
                return captured
            }
            let deadline = Date().addingTimeInterval(3)
            while !(gate.entered && callbackReturned), Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(callbackReturned)
            XCTAssertTrue(gate.entered)
            XCTAssertFalse(lifecycleFinished, "退出等操作必须等到失败草稿的持久化完成")
            // The independent recovery checkpoint must remain available even
            // while the workspace write is deliberately blocked.
            var recovered = try await note.store.noteRecoveryStore.load(documentID: note.item.id)
            while recovered?.markdown != "写入失败也不能丢的正文", Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
                recovered = try await note.store.noteRecoveryStore.load(documentID: note.item.id)
            }
            XCTAssertEqual(recovered?.markdown, "写入失败也不能丢的正文")
            gate.release()
            let captured = await lifecycle.value
            XCTAssertTrue(captured)
            XCTAssertTrue(note.store.noteEditingSession.dirty)
            XCTAssertEqual(note.store.noteEditingSession.saveStatus, .failed)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "磁盘基线")
            let persisted = try JSONDecoder().decode(PersistedWorkspace.self,
                from: Data(contentsOf: note.store.storageURL))
            XCTAssertEqual(persisted.notesByItemID[note.item.id], "写入失败也不能丢的正文")
        }
    }

    func testFreshEditorSnapshotWaitsForSuccessfulMarkdownWrite() throws {
        let note = try fixture()
        defer { try? FileManager.default.removeItem(at: note.root) }
        let token = bindEditorSnapshot(in: note.store, markdown: "退出前的最后编辑")
        defer { note.store.noteEditingSession.unbindSnapshotRequestHandler(token) }

        try note.store.waitForCourseFileOperation {
            let captured = await note.store.freshActiveNoteEditorSnapshot()
            XCTAssertTrue(captured)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "退出前的最后编辑")
            XCTAssertFalse(note.store.noteEditingSession.dirty)
            XCTAssertEqual(note.store.noteEditingSession.saveStatus, .writtenToFile)
        }
    }

    func testNoteSelectionContinuesAfterFirstSnapshotIsSaved() throws {
        let note = try fixture()
        defer { try? FileManager.default.removeItem(at: note.root) }
        var snapshotsDelivered = 0
        var applied = false
        let token = bindEditorSnapshot(in: note.store, markdown: "切换前的最后编辑") {
            snapshotsDelivered += 1
            XCTAssertFalse(note.store.canRetryPendingNoteSelection,
                           "保存尚在进行时不能把第一次切换误判为失败")
        }
        defer { note.store.noteEditingSession.unbindSnapshotRequestHandler(token) }

        try note.store.waitForCourseFileOperation {
            note.store.requestNoteSelectionTransition(to: "next-note") { applied = true }
            let deadline = Date().addingTimeInterval(3)
            while !applied && !note.store.canRetryPendingNoteSelection, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            await note.store.waitForNoteEditorSnapshotPersistence(documentID: note.item.id)
            XCTAssertTrue(applied, "首份快照保存完成就应继续切换，无需定时重试")
            XCTAssertEqual(snapshotsDelivered, 1)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "切换前的最后编辑")
            XCTAssertFalse(note.store.noteEditingSession.dirty)
        }
    }

    func testNoteSelectionStaysOnCurrentNoteWhenSnapshotWriteFails() throws {
        let note = try fixture(notebookWriter: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        defer { try? FileManager.default.removeItem(at: note.root) }
        var applied = false
        let token = bindEditorSnapshot(in: note.store, markdown: "切换失败也要保留的正文") {
            XCTAssertFalse(note.store.canRetryPendingNoteSelection,
                           "应等真实保存结果，不能提前判失败")
        }
        defer { note.store.noteEditingSession.unbindSnapshotRequestHandler(token) }

        try note.store.waitForCourseFileOperation {
            note.store.requestNoteSelectionTransition(to: "next-note") { applied = true }
            let deadline = Date().addingTimeInterval(3)
            while !note.store.canRetryPendingNoteSelection, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            await note.store.waitForNoteEditorSnapshotPersistence(documentID: note.item.id)
            XCTAssertFalse(applied)
            XCTAssertTrue(note.store.canRetryPendingNoteSelection)
            XCTAssertEqual(note.store.noteEditingSession.documentID, note.item.id)
            XCTAssertEqual(note.store.noteEditingSession.saveStatus, .failed)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "磁盘基线")
            let persisted = try JSONDecoder().decode(PersistedWorkspace.self,
                from: Data(contentsOf: note.store.storageURL))
            XCTAssertEqual(persisted.notesByItemID[note.item.id], "切换失败也要保留的正文")
        }
    }

    func testEarlierAutosaveFailureDoesNotReturnAfterSameRevisionRetry() throws {
        try assertEarlierAutosaveFailureDoesNotReturn(retryRevision: 1, retryMarkdown: "第一版保存失败的正文")
    }

    func testOlderRecoveryFailureDoesNotMarkNewerSavedSnapshotFailed() throws {
        try assertOlderRecoveryFailureDoesNotReturn(switchDocument: false)
    }

    func testOlderRecoveryFailureDoesNotReturnAfterSwitchingDocuments() throws {
        try assertOlderRecoveryFailureDoesNotReturn(switchDocument: true)
    }

    private func assertOlderRecoveryFailureDoesNotReturn(switchDocument: Bool) throws {
        let note = try fixture()
        defer { try? FileManager.default.removeItem(at: note.root) }
        let otherSource = note.root.appendingPathComponent("另一份笔记.md")
        try "另一份磁盘基线".write(to: otherSource, atomically: true, encoding: .utf8)
        let other = try note.store.importFileIntoCourseForSelfCheck(otherSource,
            courseID: XCTUnwrap(note.item.storage.ownerCourseID), role: .note).item
        let recoveryDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WeiBei/Recovery/Notes", isDirectory: true)
            .appendingPathComponent(NoteRecoveryStore.directoryName(for: note.item.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryDirectory.path))
        guard !FileManager.default.fileExists(atPath: recoveryDirectory.path) else { return }
        try FileManager.default.createDirectory(at: recoveryDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test-only recovery write blocker".utf8).write(to: recoveryDirectory)
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: recoveryDirectory.path)
            try? FileManager.default.removeItem(at: recoveryDirectory)
        }
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: recoveryDirectory.path)

        // Queue both snapshots before their asynchronous persistence can run.
        // Only this new test document's recovery path is blocked.
        var recoveries: [Task<Void, Never>] = []
        for revision in UInt64(1)...2 {
            note.store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
                documentID: note.item.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: revision,
                dirty: true
            ))
            recoveries.append(note.store.acceptNoteEditorSnapshot(NoteEditorSnapshotReadyEvent(
                requestID: "recovery-write-\(revision)",
                documentID: note.item.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: revision,
                markdown: "已写入的第\(revision)版正文"
            )))
        }
        if switchDocument {
            note.store.activeNotebookItemID = other.id
            note.store.noteEditingSession.replaceDocument(with: other.id)
            note.store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
                documentID: other.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: 1, dirty: true
            ))
            recoveries.append(note.store.acceptNoteEditorSnapshot(NoteEditorSnapshotReadyEvent(
                requestID: "other-document-recovery", documentID: other.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: 1, markdown: "另一份笔记的新正文"
            )))
        }
        try note.store.waitForCourseFileOperation {
            for recovery in recoveries { await recovery.value }
        }
        XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "已写入的第2版正文")
        XCTAssertEqual(note.store.noteEditingSession.saveStatus, .writtenToFile)
        XCTAssertFalse(note.store.noteEditingSession.dirty)
        XCTAssertNil(note.store.noteOperationErrorsByItemID[note.item.id])
        XCTAssertNil(note.store.importantOperationError)
    }

    private func assertEarlierAutosaveFailureDoesNotReturn(retryRevision: UInt64, retryMarkdown: String) throws {
        let gate = AutosaveWorkspaceWriterGate()
        var shouldFailNoteWrite = false
        let note = try fixture(notebookWriter: { markdown, url in
            if shouldFailNoteWrite { throw CocoaError(.fileWriteNoPermission) }
            try WorkspaceStore.writeNotebookMarkdown(markdown, to: url)
        }, workspaceWriter: { data, url in try gate.write(data, to: url) })
        defer {
            gate.release()
            try? FileManager.default.removeItem(at: note.root)
        }
        shouldFailNoteWrite = true
        gate.arm()
        note.store.scheduleNotePersistence("第一版保存失败的正文", for: note.item)

        try note.store.waitForCourseFileOperation {
            let failedSave = Task { @MainActor in
                await note.store.flushPendingNotePersistenceAsync(for: note.item.id)
            }
            let deadline = Date().addingTimeInterval(3)
            while !gate.entered, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(gate.entered, "旧失败已进入草稿持久化等待，主线程仍可接收新编辑")
            guard gate.entered else { gate.release(); await failedSave.value; return }
            XCTAssertEqual(note.store.noteEditingSession.saveStatus, .failed)

            shouldFailNoteWrite = false
            note.store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
                documentID: note.item.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: retryRevision,
                dirty: true
            ))
            let retry = note.store.acceptNoteEditorSnapshot(NoteEditorSnapshotReadyEvent(
                requestID: "successful-retry-while-old-failure-awaits",
                documentID: note.item.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: retryRevision,
                markdown: retryMarkdown
            ))
            await retry.value
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), retryMarkdown)
            XCTAssertEqual(note.store.noteEditingSession.saveStatus, .writtenToFile)
            XCTAssertFalse(note.store.noteEditingSession.dirty)
            XCTAssertNil(note.store.importantOperationNotice)

            gate.release()
            await failedSave.value
            let persisted = await note.store.flushPendingWorkspaceSaveAsync()
            XCTAssertTrue(persisted)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), retryMarkdown)
            XCTAssertEqual(note.store.noteEditingSession.saveStatus, .writtenToFile)
            XCTAssertFalse(note.store.noteEditingSession.dirty)
            XCTAssertNil(note.store.importantOperationNotice, "较新的正文已保存成功，旧失败不能随后重新弹出保存失败横幅")
            XCTAssertNil(note.store.importantOperationError)
            XCTAssertNil(note.store.noteOperationErrorsByItemID[note.item.id])
        }
    }

    func testRecoveryAwaitDoesNotReloadOlderCheckpointOverNewerSavedText() throws {
        let gate = AutosaveWorkspaceWriterGate()
        var shouldFailNoteWrite = false
        let note = try fixture(notebookWriter: { markdown, url in
            if shouldFailNoteWrite { throw CocoaError(.fileWriteNoPermission) }
            try WorkspaceStore.writeNotebookMarkdown(markdown, to: url)
        }, workspaceWriter: { data, url in try gate.write(data, to: url) })
        defer {
            gate.release()
            try? FileManager.default.removeItem(at: note.root)
        }
        note.store.noteEditingSession.replaceDocument(with: note.item.id)
        shouldFailNoteWrite = true
        try note.store.waitForCourseFileOperation {
            _ = try await note.store.noteRecoveryStore.store(
                documentID: note.item.id,
                baseFileDigest: WorkspaceStore.noteContentDigest(Data("磁盘基线".utf8)),
                revision: 3,
                markdown: "恢复点里的旧正文"
            )
            gate.arm()
            let recovery = Task { @MainActor in
                await note.store.reconcileActiveNoteEditorWithBackingFile()
            }
            let deadline = Date().addingTimeInterval(3)
            while !gate.entered, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(gate.entered, "恢复写入失败正在等待草稿收据")
            guard gate.entered else { gate.release(); await recovery.value; return }

            shouldFailNoteWrite = false
            note.store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
                documentID: note.item.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: 4,
                dirty: true
            ))
            let newerSave = note.store.acceptNoteEditorSnapshot(NoteEditorSnapshotReadyEvent(
                requestID: "new-edit-during-checkpoint-restore",
                documentID: note.item.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: 4,
                markdown: "恢复等待期间继续写的新正文"
            ))
            await newerSave.value
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "恢复等待期间继续写的新正文")
            gate.release()
            await recovery.value
            XCTAssertNotEqual(note.store.noteEditorCommand?.markdown, "恢复点里的旧正文",
                              "旧恢复操作不能命令编辑器重新载入已过期的正文")
            XCTAssertEqual(note.store.noteText, "恢复等待期间继续写的新正文")
            XCTAssertEqual(note.store.noteEditingSession.saveStatus, .writtenToFile)
            XCTAssertFalse(note.store.noteEditingSession.dirty)
            let persisted = await note.store.flushPendingWorkspaceSaveAsync()
            XCTAssertTrue(persisted)
        }
    }

    func testNewerSnapshotSurvivesConflictSaveAwait() throws {
        let gate = AutosaveWorkspaceWriterGate()
        let note = try fixture(workspaceWriter: { data, url in try gate.write(data, to: url) })
        defer {
            gate.release()
            try? FileManager.default.removeItem(at: note.root)
        }
        try "外部修改".write(to: note.url, atomically: true, encoding: .utf8)
        gate.arm()
        note.store.scheduleNotePersistence("第一版草稿", for: note.item)

        try note.store.waitForCourseFileOperation {
            let save = Task { @MainActor in
                await note.store.flushPendingNotePersistenceAsync(for: note.item.id)
            }
            let deadline = Date().addingTimeInterval(3)
            while !gate.entered, Date() < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(gate.entered, "工作台写盘应已开始，允许同时接收更晚的编辑")
            guard gate.entered else { gate.release(); await save.value; return }

            note.store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
                documentID: note.item.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: 2,
                dirty: true
            ))
            note.store.acceptNoteEditorSnapshot(NoteEditorSnapshotReadyEvent(
                requestID: "newer-conflict-snapshot",
                documentID: note.item.id,
                documentGeneration: note.store.noteEditingSession.documentGeneration,
                revision: 2,
                markdown: "保存等待期间继续写的新正文"
            ))
            // Ensure the newer checkpoint really reached disk while the older
            // workspace receipt is blocked, then let the original save resume.
            var newest = try await note.store.noteRecoveryStore.load(documentID: note.item.id)
            let checkpointDeadline = Date().addingTimeInterval(3)
            while newest?.metadata.revision != 2, Date() < checkpointDeadline {
                try await Task.sleep(for: .milliseconds(10))
                newest = try await note.store.noteRecoveryStore.load(documentID: note.item.id)
            }
            XCTAssertEqual(newest?.metadata.revision, 2)
            gate.release()
            await save.value
            let persisted = await note.store.flushPendingWorkspaceSaveAsync()
            XCTAssertTrue(persisted)

            let saved = try await note.store.noteRecoveryStore.load(documentID: note.item.id)
            XCTAssertEqual(saved?.markdown, "保存等待期间继续写的新正文")
            XCTAssertEqual(saved?.metadata.revision, 2)
            XCTAssertEqual(note.store.noteEditorRecoveryConflict?.checkpoint.markdown, saved?.markdown)
            XCTAssertEqual(note.store.notesByItemID[note.item.id], saved?.markdown)
            XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "外部修改")
            XCTAssertTrue(note.store.noteEditingSession.dirty)
        }
    }
}

private final class AutosaveWorkspaceWriterGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var blocksNextWrite = false
    private var didEnter = false

    var entered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didEnter
    }

    func arm() {
        lock.lock()
        blocksNextWrite = true
        didEnter = false
        lock.unlock()
    }

    func release() { releaseSignal.signal() }

    func write(_ data: Data, to url: URL) throws {
        lock.lock()
        let shouldBlock = blocksNextWrite
        blocksNextWrite = false
        if shouldBlock { didEnter = true }
        lock.unlock()
        if shouldBlock {
            guard releaseSignal.wait(timeout: .now() + 10) == .success else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try data.write(to: url, options: [.atomic])
    }
}
