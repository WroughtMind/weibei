import AppKit
import Combine
import SwiftUI
import XCTest
@testable import WeiBei
import WeiBeiCore

final class SidebarPerformanceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    @MainActor
    func testGlassDrawerUsesMaterialOnlyWhileOpen() {
        let fixture = makeStore(itemCount: 1)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.store.setAppearanceMode(.glassDark)
        let (drawer, window) = makeDrawer()

        XCTAssertFalse(drawer.glassMaterialVisibleForTesting)
        drawer.apply(isOpen: true, store: fixture.store, animated: false)
        XCTAssertTrue(drawer.glassMaterialVisibleForTesting)
        drawer.apply(isOpen: false, store: fixture.store, animated: false)
        XCTAssertFalse(drawer.glassMaterialVisibleForTesting)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func testClosedDrawerReleasesObservationTreeAndIgnoresUnrelatedState() {
        let fixture = makeStore(itemCount: 540)
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let (drawer, window) = makeDrawer()
        drawer.apply(isOpen: true, store: fixture.store, animated: false)

        guard let model = drawer.sidebarModelForTesting else {
            return XCTFail("opening the drawer must create one sidebar model")
        }
        XCTAssertEqual(drawer.activeSidebarHostCountForTesting, 1)
        let buildsBeforeUnrelatedChanges = model.projectionBuildCountForTesting

        fixture.store.agentDraft = "不应唤醒课程目录"
        fixture.store.showAgent.toggle()
        fixture.store.focusedPane = .agent
        pumpMainRunLoop()

        XCTAssertEqual(
            model.projectionBuildCountForTesting,
            buildsBeforeUnrelatedChanges,
            "chat and pane chrome changes must not rebuild an open course directory"
        )

        drawer.apply(isOpen: false, store: fixture.store, animated: true)
        pumpMainRunLoop(for: 0.30)

        XCTAssertEqual(drawer.activeSidebarHostCountForTesting, 0)
        XCTAssertNil(drawer.sidebarModelForTesting)
        let buildsAfterClose = model.projectionBuildCountForTesting
        fixture.store.selectedItemID = "after-sidebar-close"
        fixture.store.importedItems.append(
            StudyItem(
                id: "after-sidebar-close",
                title: "关闭后资料",
                subtitle: "closed.txt",
                kind: .text,
                urlPath: nil,
                isSample: false
            )
        )
        pumpMainRunLoop()
        XCTAssertNil(model.selectedItemID)
        XCTAssertEqual(model.projectionBuildCountForTesting, buildsAfterClose)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func testRapidReopenIgnoresStaleCloseCompletionThenFinalCloseReleases() {
        let fixture = makeStore(itemCount: 540)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let (drawer, window) = makeDrawer()
        drawer.apply(isOpen: true, store: fixture.store, animated: false)

        let initialModel: CourseSidebarModel
        let initialIdentity: ObjectIdentifier
        guard let model = drawer.sidebarModelForTesting else {
            return XCTFail("opening the drawer must create one sidebar model")
        }
        initialModel = model
        initialIdentity = ObjectIdentifier(model)

        drawer.apply(isOpen: false, store: fixture.store, animated: true)
        drawer.apply(isOpen: true, store: fixture.store, animated: true)
        pumpMainRunLoop(for: 0.30)

        do {
            guard let reopenedModel = drawer.sidebarModelForTesting else {
                return XCTFail("a stale close completion must not unload the reopened drawer")
            }
            XCTAssertEqual(ObjectIdentifier(reopenedModel), initialIdentity)
            XCTAssertEqual(drawer.activeSidebarHostCountForTesting, 1)
        }

        drawer.apply(isOpen: false, store: fixture.store, animated: true)
        pumpMainRunLoop(for: 0.30)

        XCTAssertEqual(drawer.activeSidebarHostCountForTesting, 0)
        XCTAssertNil(drawer.sidebarModelForTesting)
        let buildsAfterClose = initialModel.projectionBuildCountForTesting
        fixture.store.selectedItemID = "after-final-close"
        pumpMainRunLoop()
        XCTAssertNil(initialModel.selectedItemID)
        XCTAssertEqual(initialModel.projectionBuildCountForTesting, buildsAfterClose)
        withExtendedLifetime(window) {}
    }

    func testDrawerOpenPathDoesNotForceSynchronousLayout() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/WeiBei/Views/CourseDrawerHost.swift"),
            encoding: .utf8
        )
        let applyStart = try XCTUnwrap(source.range(of: "    func apply(isOpen open:"))
        let applyEnd = try XCTUnwrap(
            source.range(
                of: "\n    private func applyPaperChrome",
                range: applyStart.upperBound..<source.endIndex
            )
        )
        let applySource = source[applyStart.lowerBound..<applyEnd.lowerBound]

        XCTAssertFalse(
            applySource.contains("layoutSubtreeIfNeeded"),
            "opening the drawer must not synchronously lay out the whole SwiftUI sidebar"
        )
    }

    #if DEBUG
    @MainActor
    func testSidebarListBuildsOnlyVisibleRowsAtPressureScale() {
        let fixture = makeStore(itemCount: 2_000)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let model = CourseSidebarModel(store: fixture.store)

        CourseSidebarDiagnostics.resetForTesting()
        let host = NSHostingView(
            rootView: SidebarView(store: fixture.store, model: model)
        )
        host.frame = NSRect(x: 0, y: 0, width: 292, height: 600)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        pumpMainRunLoop()
        host.layoutSubtreeIfNeeded()
        pumpMainRunLoop()

        let builtRows = CourseSidebarDiagnostics.libraryRowBodyCountForTesting
        XCTAssertGreaterThan(builtRows, 0)
        XCTAssertLessThanOrEqual(
            builtRows,
            80,
            "a 600pt viewport must not build all 2,000 rows"
        )
        withExtendedLifetime((window, host, model)) {}
    }
    #endif

    @MainActor
    func testLibrarySearchFiltersSidebarWithoutInvalidatingWorkspaceStore() {
        let fixture = makeStore(itemCount: 0)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        fixture.store.importedItems = [
            StudyItem(
                id: "sidebar-search-apple",
                title: "苹果材料",
                subtitle: "apple.txt",
                kind: .text,
                urlPath: nil,
                isSample: false
            ),
            StudyItem(
                id: "sidebar-search-banana",
                title: "香蕉材料",
                subtitle: "banana.txt",
                kind: .text,
                urlPath: nil,
                isSample: false
            ),
        ]
        let model = CourseSidebarModel(store: fixture.store)
        XCTAssertEqual(
            model.unassignedMaterials.map(\.item.title),
            ["苹果材料", "香蕉材料"]
        )

        var workspaceChanges = 0
        let workspaceObservation = fixture.store.objectWillChange.sink {
            workspaceChanges += 1
        }
        var drawerChanges = 0
        let drawerObservation = fixture.store.libraryDrawer.objectWillChange.sink {
            drawerChanges += 1
        }
        let buildsBeforeSearch = model.projectionBuildCountForTesting

        model.updateQuery("香蕉")
        pumpMainRunLoop()

        XCTAssertEqual(
            workspaceChanges,
            0,
            "sidebar search must not invalidate the whole workspace"
        )
        XCTAssertEqual(
            drawerChanges,
            0,
            "sidebar search must not invalidate drawer chrome such as the top bar"
        )
        XCTAssertEqual(
            model.unassignedMaterials.map(\.item.title),
            ["香蕉材料"],
            "sidebar search must still rebuild and filter the sidebar projection"
        )
        XCTAssertGreaterThan(
            model.projectionBuildCountForTesting,
            buildsBeforeSearch
        )
        withExtendedLifetime((workspaceObservation, drawerObservation, model)) {}
    }

    @MainActor
    func testFourthActiveNoteTagRemainsSearchableAfterRealLoad() async throws {
        let fixture = makeStore(itemCount: 0)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let note = StudyItem(
            id: "sidebar-four-tag-note",
            title: "四标签笔记",
            subtitle: "four-tags.md",
            kind: .markdown,
            urlPath: nil,
            isSample: false,
            isNotebookNote: true
        )
        fixture.store.importedItems = [note]
        fixture.store.activeNotebookItemID = note.id
        fixture.store.noteText = "#alpha #beta #gamma #zeta"
        let model = CourseSidebarModel(store: fixture.store)

        model.updateQuery("#zeta")
        let request = try XCTUnwrap(model.missingTagRequestsForSearch().first)
        let loadedMeta = await fixture.store.loadSidebarNoteMeta(for: request)
        let meta = try XCTUnwrap(loadedMeta)
        XCTAssertEqual(meta.tags, ["#alpha", "#beta", "#gamma", "#zeta"])

        model.acceptLoadedNoteMeta([(request, meta)])
        try await Task.sleep(nanoseconds: 50_000_000)

        let row = try XCTUnwrap(model.unassignedNotes.first)
        XCTAssertEqual(row.item.id, note.id, "the fourth tag must keep the note searchable")
        XCTAssertEqual(row.tags, meta.tags, "the projection must retain every loaded tag")
    }

    @MainActor
    func testLegacyExternalNoteWithoutStoredIdentityStillLoadsTags() async throws {
        let fixture = makeStore(itemCount: 0)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let noteURL = fixture.root.appendingPathComponent("legacy-note.md")
        try Data("#legacy-tag".utf8).write(to: noteURL)
        let note = StudyItem(
            id: "sidebar-legacy-note",
            title: "旧外部笔记",
            subtitle: noteURL.lastPathComponent,
            kind: .markdown,
            urlPath: noteURL.path,
            isSample: false,
            isNotebookNote: true,
            storage: .common(relativePath: "")
        )
        fixture.store.importedItems = [note]

        let request = fixture.store.sidebarTagRequest(for: note, draftToken: nil)
        let meta = await fixture.store.loadSidebarNoteMeta(for: request)

        XCTAssertEqual(meta?.tags, ["#legacy-tag"])

        let model = CourseSidebarModel(store: fixture.store)
        try Data("#edited-tag".utf8).write(to: noteURL)
        model.stop()

        let reloadedMeta = await fixture.store.loadSidebarNoteMeta(for: request)
        XCTAssertEqual(reloadedMeta?.tags, ["#edited-tag"])
    }

    @MainActor
    func testDraftChangesInvalidateCachedTags() {
        let state = CourseSidebarTagState()
        let note = StudyItem(
            id: "sidebar-draft-cache-note",
            title: "草稿缓存笔记",
            subtitle: "draft.md",
            kind: .markdown,
            urlPath: nil,
            isSample: false,
            isNotebookNote: true
        )
        let request = state.request(
            for: note,
            activeNoteItemID: nil,
            draftToken: nil
        )
        state.cache(CourseSidebarNoteMeta(tags: ["#stale"], resolvedTitle: nil), for: request)

        state.noteDraftChanged(itemID: note.id, exists: true)

        XCTAssertNil(state.cachedMeta(for: request))
    }

    @MainActor
    private func makeStore(itemCount: Int) -> (store: WorkspaceStore, root: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiSidebarPerformance-\(UUID().uuidString)", isDirectory: true)
        let store = WorkspaceStore(
            workspaceDirectory: root,
            startsAtBlankEntries: true
        )
        store.importedItems = (0..<itemCount).map { index in
            StudyItem(
                id: "sidebar-material-\(index)",
                title: "资料 \(index)",
                subtitle: "资料-\(index).txt",
                kind: .text,
                urlPath: nil,
                isSample: false
            )
        }
        return (store, root)
    }

    @MainActor
    private func makeDrawer() -> (drawer: CourseDrawerContainerView, window: NSWindow) {
        let frame = NSRect(x: 0, y: 0, width: 1_200, height: 760)
        let drawer = CourseDrawerContainerView(frame: frame)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = drawer
        return (drawer, window)
    }

    @MainActor
    private func pumpMainRunLoop(for duration: TimeInterval = 0.08) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }
}
