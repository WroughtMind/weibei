import AppKit
import SwiftUI
import XCTest
@testable import WeiBei
import WeiBeiCore

final class ContextualContentPerformanceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    /// 开关面板和聊天更新不重排资料目录；资料变化后排序和完整条目立即更新。
    @MainActor
    func testPickerDirectoryIgnoresPaneAndChatChangesButTracksFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsCourseFileMaintenance: false)
        store.importedItems = ["B", "A"].map {
            StudyItem(id: $0, title: $0, subtitle: "", kind: .text, urlPath: nil, isSample: false)
        }
        let picker = ContextualContentPickerModel(store: store, kind: .material)
        XCTAssertEqual(picker.groups.last?.items.map(\.id), ["A", "B"])
        let builds = picker.projectionBuildCountForTesting
        store.toggleReader()
        store.toggleNotes()
        store.agentDraft = "只改变输入框"
        store.messages.append(AgentMessage(role: .assistant, text: "生成中的正文", source: nil))
        XCTAssertEqual(picker.projectionBuildCountForTesting, builds)

        store.importedItems[0].title = "0"
        XCTAssertEqual(picker.groups.last?.items.map(\.id), ["B", "A"])
        store.importedItems.removeLast()
        XCTAssertEqual(picker.groups.last?.items.map(\.id), ["B"])
    }

    /// 选择页沿用后台读取的正文标题；文件修订后不复用旧标题，回看同一版复用结果。
    @MainActor
    func testPickerTitleUsesSharedPreparedMetadataAndInvalidatesOnFileChange() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("note.md")
        try Data("# 正文标题\n\n笔记内容".utf8).write(to: url)
        let store = WorkspaceStore(workspaceDirectory: root, startsCourseFileMaintenance: false)
        let note = StudyItem(id: "note", title: "note.md", subtitle: "", kind: .markdown,
                             urlPath: url.path, isSample: false, isNotebookNote: true)
        store.importedItems = [note]
        let request = store.sidebarTagRequest(for: note, draftToken: nil)
        XCTAssertNil(store.cachedSidebarNoteMeta(for: request))
        let prepared = try store.waitForCourseFileOperation { await store.loadSidebarNoteMeta(for: request) }
        XCTAssertEqual(prepared?.resolvedTitle, "正文标题")
        XCTAssertEqual(store.cachedSidebarNoteMeta(for: request), prepared)

        try Data("# 新标题\n\n笔记内容".utf8).write(to: url)
        store.importedItems[0].contentRevision &+= 1
        let next = store.sidebarTagRequest(for: store.importedItems[0], draftToken: nil)
        XCTAssertNil(store.cachedSidebarNoteMeta(for: next))
        let stale = try store.waitForCourseFileOperation { await store.loadSidebarNoteMeta(for: request) }
        XCTAssertNil(stale)
        let updated = try store.waitForCourseFileOperation { await store.loadSidebarNoteMeta(for: next) }
        XCTAssertEqual(updated?.resolvedTitle, "新标题")
        XCTAssertEqual(store.cachedSidebarNoteMeta(for: next), updated)
    }

    /// 打开选择页和改变窗口宽度只准备可见笔记标题，不一次读取整个目录。
    @MainActor
    func testPickerOnlyPreparesVisibleTitlesAndReusesThemDuringResize() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("note.md")
        try Data("# 笔记标题\n正文".utf8).write(to: url)
        let store = WorkspaceStore(workspaceDirectory: root, startsCourseFileMaintenance: false)
        store.importedItems = (0..<120).map { index in
            StudyItem(id: "note-\(index)", title: "笔记 \(index)", subtitle: "", kind: .markdown,
                      urlPath: url.path, isSample: false, isNotebookNote: true)
        }
        let frame = NSRect(x: 0, y: 0, width: 600, height: 360)
        let host = NSHostingView(rootView: ContextualContentPicker(kind: .note).environmentObject(store))
        host.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        let firstRequest = store.sidebarTagRequest(for: store.importedItems[0], draftToken: nil)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { store.cachedSidebarNoteMeta(for: firstRequest) != nil }
        }, object: nil)
        wait(for: [loaded], timeout: 5)
        let initialReads = store.courseSidebarTags.metadataReadCountForTesting
        XCTAssertGreaterThan(initialReads, 0)
        XCTAssertLessThan(initialReads, store.importedItems.count)

        let sidebar = CourseSidebarModel(store: store)
        sidebar.stop()
        XCTAssertNotNil(store.cachedSidebarNoteMeta(for: firstRequest),
                        "closing the sidebar must not discard titles used by the picker")

        host.frame.size.width = 520
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertLessThan(store.courseSidebarTags.metadataReadCountForTesting, store.importedItems.count)
        XCTAssertEqual(store.cachedSidebarNoteMeta(for: firstRequest)?.resolvedTitle, "笔记标题")

        func findScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScrollView(in: $0) }.first
        }
        let scroll = try XCTUnwrap(findScrollView(in: host))
        let document = try XCTUnwrap(scroll.documentView)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        host.layoutSubtreeIfNeeded()
        let lastRequest = store.sidebarTagRequest(for: try XCTUnwrap(store.importedItems.last), draftToken: nil)
        let tailLoaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { store.cachedSidebarNoteMeta(for: lastRequest) != nil }
        }, object: nil)
        wait(for: [tailLoaded], timeout: 5)
        XCTAssertEqual(store.cachedSidebarNoteMeta(for: lastRequest)?.resolvedTitle, "笔记标题")
        withExtendedLifetime(window) {}
    }

    func testDirectoryExpansionSkipsDependenciesButAllowsExplicitFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rootMaterial = root.appendingPathComponent("root.md")
        let buildMaterial = root.appendingPathComponent("build/讲义.md")
        let dependencyMaterial = root.appendingPathComponent("node_modules/README.md")
        try writeMaterial(at: rootMaterial)
        try writeMaterial(at: buildMaterial)
        try writeMaterial(at: dependencyMaterial)

        let directoryExpansion = CourseProjectFileWorker.expandedSupportedFiles(
            from: [root],
            markdownOnly: false
        )
        XCTAssertEqual(
            directoryExpansion.map(\.standardizedFileURL),
            [buildMaterial, rootMaterial].map(\.standardizedFileURL)
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        )

        let directExpansion = CourseProjectFileWorker.expandedSupportedFiles(
            from: [dependencyMaterial],
            markdownOnly: false
        )
        XCTAssertEqual(
            directExpansion.map(\.standardizedFileURL),
            [dependencyMaterial.standardizedFileURL]
        )
    }

    func testCourseScanIgnoresNewDependenciesAndPreservesRegisteredPaths() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let ordinary = root.appendingPathComponent("资料/讲义.md")
        let dependency = root.appendingPathComponent("node_modules/pkg/README.md")
        try writeMaterial(at: ordinary)
        try writeMaterial(at: dependency)

        let snapshot = try await CourseProjectFileWorker().scanCourse(at: root)

        XCTAssertEqual(snapshot.observations.map(\.relativePath), ["资料/讲义.md"])
        XCTAssertTrue(snapshot.preservesExistingRecord(at: "node_modules/pkg/README.md"))
        XCTAssertFalse(snapshot.preservesExistingRecord(at: "资料/缺失.md"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiImportExpansion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeMaterial(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("material".utf8).write(to: url)
    }
}
