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

    func testDirectoryExpansionSkipsDependenciesButAllowsExplicitFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rootMaterial = root.appendingPathComponent("root.md")
        let buildMaterial = root.appendingPathComponent("build/讲义.md")
        let dependencyMaterial = root.appendingPathComponent("node_modules/README.md")
        try writeMaterial(at: rootMaterial)
        try writeMaterial(at: buildMaterial)
        try writeMaterial(at: dependencyMaterial)

        let directoryExpansion = try XCTUnwrap(CourseProjectFileWorker.expandedSupportedFiles(
            from: [root],
            markdownOnly: false
        ))
        XCTAssertEqual(
            directoryExpansion.map(\.standardizedFileURL),
            [buildMaterial, rootMaterial].map(\.standardizedFileURL)
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        )

        let directExpansion = try XCTUnwrap(CourseProjectFileWorker.expandedSupportedFiles(
            from: [dependencyMaterial],
            markdownOnly: false
        ))
        XCTAssertEqual(
            directExpansion.map(\.standardizedFileURL),
            [dependencyMaterial.standardizedFileURL]
        )
    }

    @MainActor
    func testImportLimitIsGlobalDeduplicatedAndMakesNoPartialChanges() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        for index in 0..<300 {
            try writeMaterial(at: first.appendingPathComponent("a-\(index).md"))
        }
        for index in 0..<201 {
            try writeMaterial(at: second.appendingPathComponent("b-\(index).md"))
        }

        XCTAssertEqual(
            try XCTUnwrap(CourseProjectFileWorker.expandedSupportedFiles(
                from: [first, first],
                markdownOnly: false
            )).count,
            300,
            "duplicate selections must count once"
        )
        let exactly500 = try XCTUnwrap(CourseProjectFileWorker.expandedSupportedFiles(
            from: [first] + (0..<200).map { second.appendingPathComponent("b-\($0).md") },
            markdownOnly: false
        ))
        XCTAssertEqual(exactly500.count, 500)
        XCTAssertNil(
            CourseProjectFileWorker.expandedSupportedFiles(
                from: [first, second],
                markdownOnly: false
            )
        )

        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let store = WorkspaceStore(workspaceDirectory: workspace, startsAtBlankEntries: true)
        let sentinel = StudyItem(
            id: "existing-material",
            title: "已有资料",
            subtitle: "existing.txt",
            kind: .text,
            urlPath: nil,
            isSample: false,
            storage: .legacyExternal
        )
        store.importedItems = [sentinel]
        XCTAssertTrue(store.importFiles([first, second]).isEmpty)
        XCTAssertEqual(store.importedItems, [sentinel])
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

    #if DEBUG
    @MainActor
    func testCommonMaterialsBuildOnlyVisibleRowsAtPressureScale() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiContextualPicker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)
        store.importedItems = (0..<2_000).map { index in
            StudyItem(
                id: "contextual-material-\(index)",
                title: "资料 \(index)",
                subtitle: "material-\(index).txt",
                kind: .text,
                urlPath: nil,
                isSample: false,
                storage: .legacyExternal
            )
        }

        ContextualContentPickerDiagnostics.resetForTesting()
        let host = NSHostingView(
            rootView: ContextualContentPicker(
                kind: .material,
                initialLevelForTesting: .common
            )
            .environmentObject(store)
        )
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 600)
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

        let builtRows = ContextualContentPickerDiagnostics.rowBodyCountForTesting
        XCTAssertGreaterThan(builtRows, 0)
        XCTAssertLessThanOrEqual(
            builtRows,
            80,
            "a 600pt viewport must not build all 2,000 contextual rows"
        )
        withExtendedLifetime((window, host, store)) {}
    }
    #endif

    @MainActor
    private func pumpMainRunLoop(for seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
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
