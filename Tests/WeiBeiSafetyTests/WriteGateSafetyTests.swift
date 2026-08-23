import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

private final class CompetingNoteFilePresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let markdown: String

    init(url: URL, markdown: String) {
        presentedItemURL = url
        self.markdown = markdown
    }

    func relinquishPresentedItem(toWriter writer: @escaping ((() -> Void)?) -> Void) {
        if let presentedItemURL {
            try? markdown.write(to: presentedItemURL, atomically: true, encoding: .utf8)
        }
        writer(nil)
    }
}

/// 阶段1 写闸门专项验证（计划 §5 阶段1 第4步）。
@MainActor
final class WriteGateSafetyTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    private func makeTempRoot(_ name: String) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeStore(
        base: URL,
        library: URL,
        backupRoot: URL
    ) throws -> WorkspaceStore {
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace", isDirectory: true),
            noteBackupRootURL: backupRoot,
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)
        return store
    }

    private func importNote(
        _ store: WorkspaceStore,
        base: URL,
        courseID: UUID,
        content: String,
        fileName: String? = nil
    ) throws -> (item: StudyItem, url: URL) {
        let source = base.appendingPathComponent("\(fileName ?? "笔记-\(UUID().uuidString)").md")
        try content.write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(
            source, courseID: courseID, role: .material
        )
        let url = try XCTUnwrap(store.resolvedLibraryURL(for: imported.item))
        return (imported.item, url)
    }

    private static func digest(of text: String) -> String {
        WorkspaceStore.noteContentDigest(Data(text.utf8))
    }

    func testGateRefusesWriteWithoutBaseline() throws {
        let base = makeTempRoot("weibei-gate-no-baseline")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "原始内容")

        XCTAssertThrowsError(
            try store.writeNotebookMarkdownThroughGate(
                "新内容", itemID: item.id, url: url, expectedBaseline: nil
            )
        ) { error in
            guard case NoteWriteGateError.writeRefusedKeepContent = error else {
                return XCTFail("期望 writeRefusedKeepContent，实际 \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "原始内容")
    }

    func testGateRefusesWhenRereadFails() throws {
        let base = makeTempRoot("weibei-gate-unreadable")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "原始内容")

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        XCTAssertThrowsError(
            try store.writeNotebookMarkdownThroughGate(
                "新内容", itemID: item.id, url: url, expectedBaseline: Self.digest(of: "任意")
            )
        ) { error in
            guard case NoteWriteGateError.writeRefusedKeepContent = error else {
                return XCTFail("期望 writeRefusedKeepContent，实际 \(error)")
            }
        }
        XCTAssertEqual(store.noteBackingContentDigestsByItemID[item.id] ?? "", "")
    }

    func testTwoExternalConflictsKeepBothDraftsAndCurrentSession() throws {
        let base = makeTempRoot("weibei-gate-multiple-conflicts")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "双冲突课")
        let noteA = try importNote(
            store,
            base: base,
            courseID: courseID,
            content: "甲基线",
            fileName: "甲"
        )
        let noteB = try importNote(
            store,
            base: base,
            courseID: courseID,
            content: "乙基线",
            fileName: "乙"
        )
        store.noteBackingContentDigestsByItemID[noteA.item.id] = Self.digest(of: "甲基线")
        store.noteBackingContentDigestsByItemID[noteB.item.id] = Self.digest(of: "乙基线")
        try "甲外部修改".write(to: noteA.url, atomically: true, encoding: .utf8)
        try "乙外部修改".write(to: noteB.url, atomically: true, encoding: .utf8)

        store.activeNotebookItemID = noteB.item.id
        store.noteEditingSession.replaceDocument(
            with: noteB.item.id,
            initialRevision: 6
        )
        store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
            documentID: noteB.item.id,
            documentGeneration: store.noteEditingSession.documentGeneration,
            revision: 7,
            dirty: true
        ))
        let currentGeneration = store.noteEditingSession.documentGeneration

        store.scheduleNotePersistence("甲待写正文", for: noteA.item)
        store.flushPendingNotePersistence(for: noteA.item.id)

        let recovered = try NoteBackupRing.list(
            itemID: noteA.item.id,
            rootURL: backupRoot
        ).compactMap { try? String(contentsOf: $0.url, encoding: .utf8) }
        XCTAssertTrue(recovered.contains("甲待写正文"))
        XCTAssertEqual(store.noteEditingSession.documentID, noteB.item.id)
        XCTAssertEqual(store.noteEditingSession.documentGeneration, currentGeneration)
        XCTAssertTrue(store.noteEditingSession.dirty)
        XCTAssertEqual(store.noteEditingSession.saveStatus, .saving)
        XCTAssertNil(store.noteEditorRecoveryConflict)

        store.scheduleNotePersistence("乙待写正文", for: noteB.item)
        store.flushPendingNotePersistence(for: noteB.item.id)

        XCTAssertEqual(store.noteEditorRecoveryConflict?.id, noteB.item.id)
        XCTAssertEqual(
            store.pendingPortableNoteDraftForSelfCheck(itemID: noteB.item.id),
            "乙待写正文"
        )
        XCTAssertEqual(store.noteEditingSession.saveStatus, .externallyModified)

        store.activeNotebookItemID = noteA.item.id
        store.noteText = "甲待写正文"
        store.noteEditingSession.replaceDocument(
            with: noteA.item.id,
            initialRevision: 7
        )
        store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
            documentID: noteA.item.id,
            documentGeneration: store.noteEditingSession.documentGeneration,
            revision: 8,
            dirty: true
        ))
        XCTAssertEqual(store.noteEditorRecoveryConflict?.id, noteA.item.id)
        try store.waitForCourseFileOperation {
            await store.resolveNoteEditorRecoveryConflict(useDisk: true)
        }

        XCTAssertEqual(store.noteText, "甲外部修改")
        XCTAssertEqual(
            store.pendingPortableNoteDraftForSelfCheck(itemID: noteA.item.id),
            "甲待写正文"
        )
        XCTAssertEqual(store.noteEditorRecoveryConflict?.id, noteA.item.id)
        XCTAssertTrue(store.noteEditingSession.dirty)
        XCTAssertEqual(store.noteEditingSession.saveStatus, .externallyModified)
        store.scheduleNotePersistence("甲待写正文", for: noteA.item)
        store.flushPendingNotePersistence(for: noteA.item.id)
        XCTAssertEqual(
            try String(contentsOf: noteA.url, encoding: .utf8),
            "甲外部修改"
        )

        store.activeNotebookItemID = noteB.item.id
        XCTAssertEqual(store.noteEditorRecoveryConflict?.id, noteB.item.id)
        XCTAssertEqual(
            store.pendingPortableNoteDraftForSelfCheck(itemID: noteB.item.id),
            "乙待写正文"
        )
    }

    func testGatePreservesPendingContentAndDirtySessionOnMismatch() throws {
        let base = makeTempRoot("weibei-gate-mismatch")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "基线内容")
        store.noteBackingContentDigestsByItemID[item.id] = Self.digest(of: "基线内容")

        let presenter = CompetingNoteFilePresenter(url: url, markdown: "外部修改")
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        let pendingInput = "用户未落盘的编辑"
        store.noteEditingSession.replaceDocument(with: item.id)
        store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
            documentID: item.id,
            documentGeneration: store.noteEditingSession.documentGeneration,
            revision: 1,
            dirty: true
        ))
        store.scheduleNotePersistence(pendingInput, for: item)
        store.flushPendingNotePersistence(for: item.id)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "外部修改")
        XCTAssertEqual(store.loadedCourseNoteTextByItemID[item.id], "外部修改")
        XCTAssertEqual(store.notesByItemID[item.id], pendingInput)
        XCTAssertTrue(store.noteEditingSession.dirty)
        XCTAssertEqual(store.noteEditingSession.saveStatus, .externallyModified)
        XCTAssertEqual(store.noteEditorRecoveryConflict?.diskMarkdown, "外部修改")
        XCTAssertEqual(store.noteEditorRecoveryConflict?.checkpoint.markdown, pendingInput)
        let recovered = try NoteBackupRing.list(itemID: item.id, rootURL: backupRoot).compactMap { entry in
            try? String(contentsOf: entry.url, encoding: .utf8)
        }
        XCTAssertTrue(recovered.contains(pendingInput))
    }

    func testPersistNoteWritesWhenBaselineMatches() throws {
        let base = makeTempRoot("weibei-gate-normal-write")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "第一版")

        store.scheduleNotePersistence("第二版", for: item)
        store.flushPendingNotePersistence(for: item.id)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "第二版")
        XCTAssertEqual(store.noteBackingContentDigestsByItemID[item.id], Self.digest(of: "第二版"))
        XCTAssertEqual(store.lastSelfWrittenNoteDigestsByItemID[item.id], Self.digest(of: "第二版"))
    }

    func testRenameRewriteRoutesThroughGate() throws {
        let base = makeTempRoot("weibei-gate-rename")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(
            store,
            base: base,
            courseID: courseID,
            content: "# 旧标题\n正文",
            fileName: "旧标题"
        )

        try store.waitForCourseFileOperation {
            await store.renameNotebookNoteInTransaction(itemID: item.id, to: "新标题")
        }
        let documentsDir = url.deletingLastPathComponent()
        let renamedURL = documentsDir.appendingPathComponent("新标题.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: renamedURL, encoding: .utf8)
        XCTAssertTrue(content.contains("# 新标题"), "改名后正文抬头应更新：\(content)")
        XCTAssertTrue(content.contains("正文"))
    }

    func testRetryRestoredPendingWritesRoutesThroughGate() throws {
        let base = makeTempRoot("weibei-gate-retry")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        let store = try makeStore(base: base, library: library, backupRoot: backupRoot)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let (item, url) = try importNote(store, base: base, courseID: courseID, content: "磁盘现况")

        store.notesByItemID[item.id] = "重启前未写完的草稿"
        store.pendingNoteWritesByItemID[item.id] = PendingNoteWriteState()
        store.retryRestoredPendingNoteWrites()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "重启前未写完的草稿")
    }

    func testWriteVerificationFailureKeepsDraftDirtyAndVisible() throws {
        let base = makeTempRoot("weibei-gate-writer-failure")
        defer { try? FileManager.default.removeItem(at: base) }
        let backupRoot = base.appendingPathComponent("backups", isDirectory: true)
        let library = base.appendingPathComponent("资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: base.appendingPathComponent("workspace", isDirectory: true),
            notebookMarkdownWriter: { _, url in
                try "半截".write(to: url, atomically: true, encoding: .utf8)
            },
            noteBackupRootURL: backupRoot,
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)
        let courseID = try store.createCourseInLibrary(title: "闸门课")
        let source = base.appendingPathComponent("笔记.md")
        try "第一版".write(to: source, atomically: true, encoding: .utf8)
        let imported = try store.importFileIntoCourseForSelfCheck(source, courseID: courseID, role: .material)
        let item = imported.item
        let url = try XCTUnwrap(store.resolvedLibraryURL(for: item))
        store.noteEditingSession.replaceDocument(with: item.id)
        store.noteEditingSession.receive(NoteEditorDirtyChangedEvent(
            documentID: item.id,
            documentGeneration: store.noteEditingSession.documentGeneration,
            revision: 1,
            dirty: true
        ))

        store.scheduleNotePersistence("第二版", for: item)
        store.flushPendingNotePersistence(for: item.id)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "半截")
        XCTAssertEqual(
            store.pendingPortableNoteDraftForSelfCheck(itemID: item.id),
            "第二版"
        )
        XCTAssertTrue(store.noteEditingSession.dirty)
        XCTAssertEqual(store.noteEditingSession.saveStatus, .failed)
        XCTAssertNotNil(store.importantOperationError)
    }

}
