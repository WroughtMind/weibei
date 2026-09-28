import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

@MainActor
final class ConfirmedFileImportTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    func testCancelBeforeConfirmationWritesNothing() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.outside.appendingPathComponent("讲义.txt")
        try Data("source".utf8).write(to: source)

        fixture.store.prepareConfirmedFileImport([source])
        waitForStage(.reviewing, in: fixture.store)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.library
                .appendingPathComponent("通用资料/讲义.txt")
                .path
        ))
        fixture.store.dismissConfirmedFileImport()
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.library
                .appendingPathComponent("通用资料/讲义.txt")
                .path
        ))
    }

    func testPartialFailureKeepsSuccessAndRetriesOnlyFailure() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = fixture.outside.appendingPathComponent("一.txt")
        let second = fixture.outside.appendingPathComponent("二.txt")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        fixture.store.prepareConfirmedFileImport([first, second])
        waitForStage(.reviewing, in: fixture.store)
        try FileManager.default.removeItem(at: second)
        fixture.store.confirmFileImport()
        waitForStage(.finished, in: fixture.store)

        var batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(batch.importedItems.map(\.subtitle), ["一.txt"])
        XCTAssertEqual(batch.failures.map(\.sourceURL.lastPathComponent), ["二.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.library.appendingPathComponent("通用资料/一.txt").path
        ))

        try Data("two".utf8).write(to: second)
        fixture.store.retryFailedConfirmedFileImport()
        waitForStage(.reviewing, in: fixture.store)
        XCTAssertEqual(fixture.store.confirmedFileImport?.sourceURLs, [second])
        fixture.store.confirmFileImport()
        waitForStage(.finished, in: fixture.store)

        batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(Set(batch.importedItems.map(\.subtitle)), Set(["一.txt", "二.txt"]))
        XCTAssertTrue(batch.failures.isEmpty)
        XCTAssertEqual(
            try String(contentsOf: fixture.library.appendingPathComponent("通用资料/一.txt")),
            "one"
        )
    }

    func testStopBeforeNextTaskLeavesSourcesUntouched() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = fixture.outside.appendingPathComponent("一.txt")
        let second = fixture.outside.appendingPathComponent("二.txt")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        fixture.store.prepareConfirmedFileImport([first, second])
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        fixture.store.stopConfirmedFileImport()
        waitForStage(.finished, in: fixture.store)

        let batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertTrue(batch.stopped)
        XCTAssertTrue(batch.importedItems.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.library.appendingPathComponent("通用资料/一.txt").path
        ))
    }

    func testDockFilesJoinOneCommonBatchBeforeConfirmation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = fixture.outside.appendingPathComponent("一.txt")
        let second = fixture.outside.appendingPathComponent("二.txt")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)

        fixture.store.receiveExternalFileForConfirmedImport(first)
        fixture.store.receiveExternalFileForConfirmedImport(second)
        waitForStage(.reviewing, in: fixture.store)

        let batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertNil(batch.courseID)
        XCTAssertEqual(Set(batch.sourceURLs), Set([first, second]))
        XCTAssertEqual(batch.candidates.count, 2)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            atPath: fixture.library.appendingPathComponent("通用资料").path
        ).isEmpty)
    }

    func testDockFileOpenedDuringImportWaitsForNextBatch() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let current = fixture.outside.appendingPathComponent("当前.txt")
        let waiting = fixture.outside.appendingPathComponent("稍后.txt")
        try Data("current".utf8).write(to: current)
        try Data("waiting".utf8).write(to: waiting)

        fixture.store.prepareConfirmedFileImport([current])
        waitForStage(.reviewing, in: fixture.store)
        var batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        batch.stage = .importing
        fixture.store.confirmedFileImport = batch

        fixture.store.receiveExternalFileForConfirmedImport(waiting)

        batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(batch.sourceURLs, [current])
        XCTAssertEqual(batch.pendingSourceURLs, [waiting])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.library.appendingPathComponent("通用资料/稍后.txt").path
        ))

        batch.stage = .finished
        fixture.store.confirmedFileImport = batch
        fixture.store.continuePendingConfirmedFileImport()
        waitForStage(.reviewing, in: fixture.store)
        XCTAssertEqual(fixture.store.confirmedFileImport?.sourceURLs, [waiting])
    }

    func testInitialCourseFilesWaitForUnifiedConfirmation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.outside.appendingPathComponent("课程讲义.pdf")
        try Data("pdf".utf8).write(to: source)
        let courseID = try fixture.store.createCourseInLibrary(title: "确认课")
        let courseRoot = try XCTUnwrap(fixture.store.courseRootURL(for: courseID))

        fixture.store.prepareInitialCourseImportAfterEntryDismissal([source], courseID: courseID)
        waitForStage(.reviewing, in: fixture.store)

        XCTAssertEqual(fixture.store.confirmedFileImport?.courseID, courseID)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: courseRoot.appendingPathComponent("文稿/课程讲义.pdf").path
        ))
    }

    func testCollisionPlanUsesCopyKernelWithoutWriting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-confirmed-collision-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = sourceDirectory.appendingPathComponent("同名.txt")
        let existing = destination.appendingPathComponent("同名.txt")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: existing)

        XCTAssertEqual(
            try ImportFileCopy.collision(from: source, into: destination),
            .conflict(suggestedFileName: "同名 2.txt")
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["同名.txt"])
        try Data("old".utf8).write(to: source)
        XCTAssertEqual(try ImportFileCopy.collision(from: source, into: destination), .duplicate)
    }

    func testSameNameInsideBatchIsShownAsConflictBeforeConfirmation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-confirmed-batch-collision-\(UUID().uuidString)", isDirectory: true)
        let firstDirectory = root.appendingPathComponent("a", isDirectory: true)
        let secondDirectory = root.appendingPathComponent("b", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [firstDirectory, secondDirectory, destination] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let first = firstDirectory.appendingPathComponent("同名.txt")
        let second = secondDirectory.appendingPathComponent("同名.txt")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let plan = WorkspaceStore.makeConfirmedFileImportPlan(
            urls: [first, second],
            destination: destination,
            markdownOnly: false
        )

        XCTAssertEqual(plan.candidates.count, 2)
        XCTAssertEqual(plan.candidates[0].disposition, .ready)
        XCTAssertEqual(plan.candidates[1].disposition, .conflict(suggestedFileName: "同名 2.txt"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    func testSameNameAndContentInsideBatchSkipsSecondCopy() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstDirectory = fixture.outside.appendingPathComponent("a", isDirectory: true)
        let secondDirectory = fixture.outside.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let first = firstDirectory.appendingPathComponent("同名.txt")
        let second = secondDirectory.appendingPathComponent("同名.txt")
        try Data("same".utf8).write(to: first)
        try Data("same".utf8).write(to: second)

        fixture.store.prepareConfirmedFileImport([first, second])
        waitForStage(.reviewing, in: fixture.store)
        XCTAssertEqual(
            fixture.store.confirmedFileImport?.candidates.map(\.disposition),
            [.ready, .duplicate]
        )

        fixture.store.confirmFileImport()
        waitForStage(.finished, in: fixture.store)
        let batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(batch.importedItems.count, 1)
        XCTAssertEqual(batch.skippedCount, 1)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.library.appendingPathComponent("通用资料").path
            ),
            ["同名.txt"]
        )
    }

    func testMixedFolderListsRecursiveUnsupportedFilesWithoutFollowingSymlinks() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let folder = fixture.outside.appendingPathComponent("资料包", isDirectory: true)
        let nested = folder.appendingPathComponent("附件", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: folder.appendingPathComponent("讲义.pdf"))
        try Data("zip".utf8).write(to: nested.appendingPathComponent("原件.zip"))
        let outsideSecret = fixture.root.appendingPathComponent("边界外.zip")
        try Data("secret".utf8).write(to: outsideSecret)
        try FileManager.default.createSymbolicLink(
            at: nested.appendingPathComponent("边界外.zip"),
            withDestinationURL: outsideSecret
        )

        fixture.store.prepareConfirmedFileImport([folder])
        waitForStage(.reviewing, in: fixture.store)

        let batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(batch.candidates.map { $0.sourceURL.lastPathComponent }, ["讲义.pdf"])
        XCTAssertEqual(batch.unsupportedNames, ["资料包/附件/原件.zip"])
        XCTAssertEqual(batch.skippedCount, 1)
    }

    private func waitForStage(
        _ stage: ConfirmedFileImportStage,
        in store: WorkspaceStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(10)
        while store.confirmedFileImport?.stage != stage, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(store.confirmedFileImport?.stage, stage, file: file, line: line)
    }

    private func makeFixture() throws -> (
        root: URL,
        library: URL,
        outside: URL,
        store: WorkspaceStore
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-confirmed-import-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let library = root.appendingPathComponent("library", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let store = WorkspaceStore(
            workspaceDirectory: workspace,
            courseRootBookmarkMaker: { Data($0.standardizedFileURL.path.utf8) },
            courseRootBookmarkResolver: { data in
                guard let path = String(data: data, encoding: .utf8) else { return nil }
                return CourseProjectResolvedBookmark(
                    url: URL(fileURLWithPath: path),
                    isStale: false
                )
            },
            courseSecurityScopeStarter: { _ in true },
            courseSecurityScopeStopper: { _ in },
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        try store.configureCourseLibrary(at: library)
        return (root, library, outside, store)
    }
}
