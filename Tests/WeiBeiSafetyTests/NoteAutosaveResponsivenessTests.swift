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
