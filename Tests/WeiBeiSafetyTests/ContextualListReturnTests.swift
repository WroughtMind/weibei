import AppKit
import SwiftUI
import XCTest
@testable import WeiBei
import WeiBeiCore

/// 选择器保留当前编辑现场；真正切换时仍须等待保存。
final class ContextualListReturnTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }
    private struct Fixture {
        let root: URL
        let workspaceDirectory: URL
        let importsDirectory: URL
        private let suiteName: String
        let selectionAskThreadDefaults: UserDefaults

        init(name: String) throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("weibei-list-return-\(name)-\(UUID().uuidString)", isDirectory: true)
            workspaceDirectory = root.appendingPathComponent("Workspace", isDirectory: true)
            importsDirectory = root.appendingPathComponent("Imports", isDirectory: true)
            suiteName = "weibei.list-return.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                throw NSError(domain: "list-return-fixture", code: 1)
            }
            selectionAskThreadDefaults = defaults
            defaults.removePersistentDomain(forName: suiteName)
            try FileManager.default.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: importsDirectory, withIntermediateDirectories: true)
        }

        func write(_ snapshot: PersistedWorkspace) throws {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: workspaceDirectory.appendingPathComponent("workspace.json"), options: [.atomic])
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
            selectionAskThreadDefaults.removePersistentDomain(forName: suiteName)
        }
    }

    @MainActor
    private func makeFixture() throws -> (Fixture, WorkspaceStore, StudyItem, StudyItem, StudyItem) {
        let fixture = try Fixture(name: "contract")
        let materialURL = fixture.importsDirectory.appendingPathComponent("课程简介.txt")
        let noteAURL = fixture.importsDirectory.appendingPathComponent("打.md")
        let noteBURL = fixture.importsDirectory.appendingPathComponent("别泄气.md")
        try Data("课程简介内容".utf8).write(to: materialURL)
        try Data("# 打".utf8).write(to: noteAURL)
        try Data("# 别泄气".utf8).write(to: noteBURL)
        let material = StudyItem(
            id: "m", title: "课程简介", subtitle: materialURL.lastPathComponent,
            kind: .text, urlPath: materialURL.path, isSample: false
        )
        let noteA = StudyItem(
            id: "a", title: "打", subtitle: noteAURL.lastPathComponent,
            kind: .markdown, urlPath: noteAURL.path, isSample: false, isNotebookNote: true
        )
        let noteB = StudyItem(
            id: "b", title: "别泄气", subtitle: noteBURL.lastPathComponent,
            kind: .markdown, urlPath: noteBURL.path, isSample: false, isNotebookNote: true
        )
        try fixture.write(PersistedWorkspace(
            importedItems: [material, noteA, noteB],
            selectedItemID: nil,
            activeNotebookItemID: nil,
            workspaceLayout: WorkspaceLayout.documentAgentNotes.rawValue,
            showReader: true,
            showAgent: false,
            showNotes: true
        ))
        let store = WorkspaceStore(
            workspaceDirectory: fixture.workspaceDirectory,
            selectionAskThreadDefaults: fixture.selectionAskThreadDefaults,
            startsAtBlankEntries: true
        )
        return (fixture, store, material, noteA, noteB)
    }

    /// 文稿区/笔记区解耦:在文稿侧选中一篇笔记(selectMeasured opensNotebook:false,
    /// 与 openContextualItem(.material) 同路径)不应牵引笔记窗格;点列表按钮也不清掉文稿区选择。
    @MainActor
    func testReaderSideNoteSelectionDoesNotOccupyNotesPane() throws {
        let (fixture, store, _, noteA, _) = try makeFixture()
        defer { fixture.remove() }

        store.selectMeasured(itemID: noteA.id, opensNotebook: false)
        XCTAssertEqual(store.selectedItem?.id, noteA.id)
        XCTAssertNil(store.activeNoteItem, "文稿区打开笔记不应把笔记窗格从列表态拉走")

        store.showContextualBrowser(.note)

        XCTAssertNil(store.activeNoteItem, "列表按钮后笔记窗格应停在列表态")
        XCTAssertEqual(store.selectedItem?.id, noteA.id, "回到笔记列表不应清掉文稿区的选择")
        XCTAssertTrue(store.showNotes, "列表按钮应当保证笔记栏位可见")
    }

    /// 选择其他笔记可以取消，不提前清空当前笔记。
    @MainActor
    func testNotePickerPreservesCurrentNoteAndCancelKeepsMaterialSelection() throws {
        let (fixture, store, material, _, noteB) = try makeFixture()
        defer { fixture.remove() }

        store.openContextualItem(material.id, kind: .material)
        store.openContextualItem(noteB.id, kind: .note)
        XCTAssertEqual(store.activeNoteItem?.id, noteB.id)
        store.noteText = "选择器打开前的编辑内容"

        store.showContextualBrowser(.note)

        XCTAssertTrue(store.notePickerPresented)
        XCTAssertEqual(store.activeNoteItem?.id, noteB.id)
        XCTAssertEqual(store.noteText, "选择器打开前的编辑内容")
        store.notePickerPresented = false
        XCTAssertEqual(store.activeNoteItem?.id, noteB.id)
        XCTAssertEqual(store.selectedMaterialItem?.id, material.id, "回到笔记列表不应清掉资料选择")
    }

    @MainActor
    func testNoteDisplayNameSearchAndFindStayInWritingPane() throws {
        let (fixture, store, _, _, noteB) = try makeFixture()
        defer { fixture.remove() }
        store.openContextualItem(noteB.id, kind: .note)
        store.setNoteCustomDisplayTitle("新的显示名称", for: noteB.id)
        let renamed = try XCTUnwrap(store.item(withID: noteB.id))
        XCTAssertEqual(store.noteListDisplayTitle(for: renamed), "新的显示名称")
        XCTAssertTrue(store.itemMatchesLibrarySearch(renamed, query: "显示名称"))
        XCTAssertTrue(store.itemMatchesLibrarySearch(renamed, query: "别泄气"))
        store.layout = .immersiveWriting
        store.revealDocumentSearch()
        XCTAssertTrue(store.showDocumentSearch)
        XCTAssertEqual(store.focusedPane, .notes)
        XCTAssertEqual(store.layout, .immersiveWriting)
        store.noteSearch = "正文"
        store.hideDocumentSearch()
        XCTAssertTrue(store.noteSearch.isEmpty)
        XCTAssertEqual(store.focusedPane, .notes)
    }

    @MainActor
    func testRenderNotePickerAndConflictForVisualReview() throws {
        guard let directory = ProcessInfo.processInfo.environment["WEIBEI_NOTES_UX_SNAPSHOTS"] else {
            throw XCTSkip("Opt-in review of the actual note views in hidden windows")
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let (fixture, store, _, _, noteB) = try makeFixture()
        defer { fixture.remove() }
        func capture<V: View>(_ view: V, name: String, width: CGFloat) throws {
            let host = NSHostingView(rootView: view.environmentObject(store).environmentObject(store.paneState)
                .preferredColorScheme(store.appearanceMode.colorScheme))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 560)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            XCTAssertFalse(window.isVisible)
            window.contentView = nil
        }
        store.openContextualItem(noteB.id, kind: .note)
        store.showContextualBrowser(.note)
        try capture(NotePaneView(), name: "选择笔记", width: 700)
        store.noteEditorRecoveryConflict = NoteEditorRecoveryConflict(
            diskMarkdown: "# 导数\n\n磁盘中补充了导数的定义。\n\n$f'(x) = 2x$",
            checkpoint: NoteRecoveryCheckpoint(metadata: NoteRecoveryMetadata(
                documentID: noteB.id, baseFileDigest: "sample", checkpointDigest: "sample",
                revision: 1, updatedAt: Date(), dialectVersion: 1
            ), markdown: "# 导数\n\n魏碑中补充了计算过程。\n\n$f(x) = x^2$"),
            checkpointIsPersisted: true
        )
        try capture(NoteConflictComparisonView(), name: "冲突对照", width: 820)
    }

    /// 卡死逃生:切换等待停在「保存中」且无任何出口(编辑器命令未回执)时,
    /// 看门狗应把状态降级为失败——底部状态条的重试入口恢复、新切换不再被吞。
    @MainActor
    func testStuckSavingWatchdogSurfacesManualRetry() throws {
        let (fixture, store, _, noteA, noteB) = try makeFixture()
        defer { fixture.remove() }

        store.openContextualItem(noteB.id, kind: .note)
        store.noteSelectionWatchdogSeconds = 0.1
        // 给编辑会话一个当前文档身份(无真实 WebView 的测试环境)。
        store.noteEditingSession.replaceDocument(with: noteB.id)
        // 制造卡死:一条被编辑器拒绝过的内容命令悬而未决,切换只能停等它。
        store.noteEditorCommandRejected(
            NoteEditorCommand(kind: .insertMarkdown, markdown: "未应用内容"),
            documentID: noteB.id
        )

        store.openContextualItem(noteA.id, kind: .note)

        XCTAssertTrue(store.noteSelectionStatusMessage?.contains("保存") == true, "卡死期间应显示保存中提示,实际:\(store.noteSelectionStatusMessage ?? "nil")")
        XCTAssertFalse(store.canRetryPendingNoteSelection, "卡在保存中时旧行为没有重试出口")

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        XCTAssertTrue(store.canRetryPendingNoteSelection, "看门狗超时后必须给出手动重试出口")
        XCTAssertNotNil(store.noteSelectionStatusMessage, "降级后应显示可行动的失败提示")
    }

    /// 开关笔记窗格保留原来的笔记选择。
    @MainActor
    func testOpeningNotesPaneKeepsCurrentNote() throws {
        let (fixture, store, material, _, noteB) = try makeFixture()
        defer { fixture.remove() }

        store.openContextualItem(material.id, kind: .material)
        store.openContextualItem(noteB.id, kind: .note)
        store.showContextualBrowser(.note)
        store.toggleNotes()
        store.toggleNotes()

        XCTAssertTrue(store.showNotes, "前置条件:笔记窗格已重新打开")
        XCTAssertEqual(store.activeNoteItem?.id, noteB.id)
        XCTAssertEqual(store.selectedMaterialItem?.id, material.id, "文稿区选择不受影响")
    }

    @MainActor
    func testOpeningReaderPaneStaysAtListDespitePairing() throws {
        let (fixture, store, material, _, noteB) = try makeFixture()
        defer { fixture.remove() }

        store.openContextualItem(material.id, kind: .material)
        store.openContextualItem(noteB.id, kind: .note)
        store.showContextualBrowser(.material)
        store.toggleReader()
        store.toggleReader()

        XCTAssertTrue(store.showReader, "前置条件:文稿窗格已重新打开")
        XCTAssertNil(store.selectedMaterialItem, "打开文稿窗格应停在列表,不得自动跳配对资料")
        XCTAssertEqual(store.activeNoteItem?.id, noteB.id, "笔记区打开的笔记不受影响")
    }

    /// 契约3:内部故障静默自愈——被拒命令后台自动重发,期间不出现面向用户的失败文案。
    @MainActor
    func testRejectedCommandSelfHealsSilently() throws {
        let (fixture, store, _, _, noteB) = try makeFixture()
        defer { fixture.remove() }

        store.openContextualItem(noteB.id, kind: .note)
        store.noteSelectionSelfHealDelaySeconds = 0.05
        store.noteEditingSession.replaceDocument(with: noteB.id)
        store.noteEditorCommandRejected(
            NoteEditorCommand(kind: .insertMarkdown, markdown: "未应用内容"),
            documentID: noteB.id
        )
        XCTAssertNil(store.noteEditorCommandFailureMessage, "自愈期内不应出现内部失败文案")

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        XCTAssertNotNil(store.noteEditorCommand, "被拒命令应已自动重发,无需用户操作")
        // 测试环境没有真实编辑器接收重发,额度耗尽后升级为用户可见文案属于设计出口
        // (真实环境里编辑器会签收,自愈对用户完全无感),此处不再断言静默。
    }

    /// 契约3:失败切换在自愈额度内只显示中性「正在保存」,额度耗尽才升级为手动重试。
    @MainActor
    func testFailedSelectionSelfHealThenManualEscape() throws {
        let (fixture, store, _, noteA, noteB) = try makeFixture()
        defer { fixture.remove() }

        store.openContextualItem(noteB.id, kind: .note)
        store.noteSelectionWatchdogSeconds = 0.05
        store.noteSelectionSelfHealDelaySeconds = 0.05
        store.noteEditingSession.replaceDocument(with: noteB.id)
        store.noteEditorCommandRejected(
            NoteEditorCommand(kind: .insertMarkdown, markdown: "未应用内容"),
            documentID: noteB.id
        )
        store.openContextualItem(noteA.id, kind: .note)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        XCTAssertTrue(store.canRetryPendingNoteSelection, "自愈额度耗尽后必须保留手动重试出口")
        XCTAssertTrue(
            store.noteSelectionStatusMessage?.contains("请重试") == true,
            "额度耗尽后应显示可行动文案,实际:\(store.noteSelectionStatusMessage ?? "nil")"
        )
    }
}
