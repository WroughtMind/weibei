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

        let batch = try XCTUnwrap(fixture.store.confirmedFileImport)
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
        waitForImportIdle(in: fixture.store)

        XCTAssertNil(fixture.store.confirmedFileImport)
        XCTAssertEqual(
            Set(fixture.store.importedItems.map(\.subtitle)),
            Set(["一.txt", "二.txt"])
        )
        XCTAssertEqual(fixture.store.recentlyImportedItemIDs.count, 2)
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
        let baseline = fixture.outside.appendingPathComponent("当前阅读.txt")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)
        try Data("baseline".utf8).write(to: baseline)

        fixture.store.prepareConfirmedFileImport([baseline])
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)
        let selectedID = try XCTUnwrap(fixture.store.selectedMaterialItem?.id)
        fixture.store.readerPageIndex = 9
        fixture.store.readerLocationID = "停止前位置"

        fixture.store.prepareConfirmedFileImport([first, second])
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        fixture.store.stopConfirmedFileImport()
        waitForImportIdle(in: fixture.store)

        XCTAssertNil(fixture.store.confirmedFileImport)
        XCTAssertEqual(fixture.store.importedItems.map(\.subtitle), ["当前阅读.txt"])
        XCTAssertEqual(fixture.store.selectedMaterialItem?.id, selectedID)
        XCTAssertEqual(fixture.store.readerPageIndex, 9)
        XCTAssertEqual(fixture.store.readerLocationID, "停止前位置")
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("导入已停止") == true)
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("2 份未导入") == true)
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

    func testCommonMarkdownStaysMaterialAfterConfirmationOpenAndMaintenance() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.outside.appendingPathComponent("阅读材料.md")
        try Data("# 阅读材料\n\n正文".utf8).write(to: source)

        fixture.store.prepareConfirmedFileImport([source])
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)

        let imported = try XCTUnwrap(
            fixture.store.importedItems.first { $0.subtitle == "阅读材料.md" }
        )
        XCTAssertEqual(imported.kind, .markdown)
        XCTAssertFalse(imported.isNotebookNote)
        XCTAssertTrue(imported.isCourseMaterial)
        XCTAssertEqual(
            imported.storage,
            .common(relativePath: "通用资料/阅读材料.md")
        )

        XCTAssertEqual(fixture.store.selectedMaterialItem?.id, imported.id)
        XCTAssertNotEqual(fixture.store.activeNoteItemID, imported.id)

        try fixture.store.waitForCourseFileOperation {
            await fixture.store.reconcileCourseFilesNow()
        }
        let maintained = try XCTUnwrap(
            fixture.store.importedItems.first { $0.id == imported.id }
        )
        XCTAssertFalse(maintained.isNotebookNote)
        XCTAssertTrue(maintained.isCourseMaterial)
        XCTAssertEqual(fixture.store.selectedMaterialItem?.id, imported.id)
    }

    func testSingleNoteSuccessOpensNoteWithoutResultModal() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.outside.appendingPathComponent("课堂笔记.md")
        try Data("# 课堂笔记\n\n正文".utf8).write(to: source)

        fixture.store.prepareConfirmedFileImport([source], asNotes: true)
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)

        let imported = try XCTUnwrap(
            fixture.store.importedItems.first { $0.subtitle == "课堂笔记.md" }
        )
        XCTAssertNil(fixture.store.confirmedFileImport)
        XCTAssertTrue(imported.isNotebookNote)
        XCTAssertFalse(imported.isCourseMaterial)
        XCTAssertEqual(imported.storage, .common(relativePath: "通用笔记/课堂笔记.md"))
        XCTAssertEqual(fixture.store.activeNoteItemID, imported.id)
        XCTAssertNil(fixture.store.transientNoteStatus)
    }

    func testAllDuplicateImportPreservesReadingSelectionAndExplainsNoChange() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let existingSource = fixture.outside.appendingPathComponent("已存在资料.txt")
        let currentSource = fixture.outside.appendingPathComponent("当前阅读资料.txt")
        try Data("same".utf8).write(to: existingSource)
        try Data("current".utf8).write(to: currentSource)

        fixture.store.prepareConfirmedFileImport([existingSource])
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)

        fixture.store.prepareConfirmedFileImport([currentSource])
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)
        let selectedID = try XCTUnwrap(fixture.store.selectedMaterialItem?.id)
        fixture.store.readerPageIndex = 7
        fixture.store.readerLocationID = "保持这里"

        fixture.store.prepareConfirmedFileImport([existingSource])
        waitForStage(.reviewing, in: fixture.store)
        XCTAssertEqual(fixture.store.confirmedFileImport?.candidates.map(\.disposition), [.duplicate])
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)

        XCTAssertEqual(fixture.store.selectedMaterialItem?.id, selectedID)
        XCTAssertEqual(fixture.store.selectedMaterialItem?.subtitle, "当前阅读资料.txt")
        XCTAssertEqual(fixture.store.readerPageIndex, 7)
        XCTAssertEqual(fixture.store.readerLocationID, "保持这里")
        XCTAssertEqual(fixture.store.importedItems.filter { $0.subtitle == "已存在资料.txt" }.count, 1)
        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(
                atPath: fixture.library.appendingPathComponent("通用资料").path
            )),
            Set(["已存在资料.txt", "当前阅读资料.txt"])
        )
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("已存在") == true)
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("未重复导入") == true)
    }

    func testMixedSuccessAndUnsupportedAutoOpensAndExplainsUnsupportedFile() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let supported = fixture.outside.appendingPathComponent("可读.txt")
        let unsupported = fixture.outside.appendingPathComponent("原件.zip")
        try Data("text".utf8).write(to: supported)
        try Data("zip".utf8).write(to: unsupported)

        fixture.store.prepareConfirmedFileImport([supported, unsupported])
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)

        let imported = try XCTUnwrap(
            fixture.store.importedItems.first { $0.subtitle == "可读.txt" }
        )
        XCTAssertEqual(fixture.store.selectedMaterialItem?.id, imported.id)
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("1 个格式不支持") == true)
        XCTAssertFalse(fixture.store.transientNoteStatus?.contains("已导入") == true)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.library.appendingPathComponent("通用资料/原件.zip").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unsupported.path))
    }

    func testUnsupportedOnlySelectionClosesWithoutWritingOrChangingReadingSelection() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let baseline = fixture.outside.appendingPathComponent("当前资料.txt")
        let unsupported = fixture.outside.appendingPathComponent("原件.zip")
        try Data("baseline".utf8).write(to: baseline)
        try Data("zip".utf8).write(to: unsupported)

        fixture.store.prepareConfirmedFileImport([baseline])
        waitForStage(.reviewing, in: fixture.store)
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)
        let selectedID = try XCTUnwrap(fixture.store.selectedMaterialItem?.id)

        fixture.store.prepareConfirmedFileImport([unsupported])
        waitForImportIdle(in: fixture.store)

        XCTAssertEqual(fixture.store.selectedMaterialItem?.id, selectedID)
        XCTAssertEqual(fixture.store.importedItems.count, 1)
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("没有可导入的文件") == true)
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("1 个格式不支持") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unsupported.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.library.appendingPathComponent("通用资料/原件.zip").path
        ))
    }

    func testEmptyFolderClosesWithLightFeedbackAndNoWrite() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let emptyFolder = fixture.outside.appendingPathComponent("空资料夹", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)

        fixture.store.prepareConfirmedFileImport([emptyFolder])
        waitForImportIdle(in: fixture.store)

        XCTAssertTrue(fixture.store.importedItems.isEmpty)
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("没有可导入的文件") == true)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(
            atPath: fixture.library.appendingPathComponent("通用资料").path
        ).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: emptyFolder.path).isEmpty)
    }

    func testUnavailableDestinationKeepsReviewErrorEvenWithNoCandidates() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.outside.appendingPathComponent("无法导入.txt")
        try Data("source".utf8).write(to: source)
        fixture.store.courseLibraryRootURL = nil

        fixture.store.prepareConfirmedFileImport([source])

        let batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(batch.stage, .reviewing)
        XCTAssertNotNil(batch.destinationError)
        XCTAssertTrue(batch.candidates.isEmpty)
        XCTAssertNil(fixture.store.transientNoteStatus)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.library.appendingPathComponent("通用资料/无法导入.txt").path
        ))
    }

    func testMissingSourceStaysVisibleAsRetryableFailure() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let missing = fixture.outside.appendingPathComponent("已移走.txt")

        fixture.store.prepareConfirmedFileImport([missing])
        waitForStage(.finished, in: fixture.store)

        var batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertTrue(batch.candidates.isEmpty)
        XCTAssertEqual(batch.failures.map(\.sourceURL), [missing])
        XCTAssertTrue(batch.failures.first?.message.contains("无法访问") == true)
        XCTAssertNil(fixture.store.transientNoteStatus)

        fixture.store.retryFailedConfirmedFileImport()
        waitForStage(.finished, in: fixture.store)

        batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(batch.failures.map(\.sourceURL), [missing])
        XCTAssertNil(fixture.store.transientNoteStatus)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.library.appendingPathComponent("通用资料/已移走.txt").path
        ))
    }

    func testUnreadableFileIsOnlyAVisibleFailureAndNeverACandidate() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unreadable = fixture.outside.appendingPathComponent("暂不可读.txt")
        try Data("source".utf8).write(to: unreadable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: unreadable.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: unreadable.path
            )
        }

        let plan = WorkspaceStore.makeConfirmedFileImportPlan(
            urls: [unreadable],
            destination: fixture.library.appendingPathComponent("通用资料", isDirectory: true),
            markdownOnly: false
        )

        XCTAssertTrue(plan.candidates.isEmpty)
        XCTAssertEqual(plan.unavailableSourceURLs, [unreadable.standardizedFileURL])
        XCTAssertTrue(plan.unsupportedNames.isEmpty)
    }

    func testNestedEnumerationFailureRetriesOnlyFailedSubtreeWithoutDuplicatePollution() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let folder = fixture.outside.appendingPathComponent("混合资料", isDirectory: true)
        let locked = folder.appendingPathComponent("暂不可读", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let readable = folder.appendingPathComponent("可读.txt")
        try Data("readable".utf8).write(to: readable)
        try Data("locked".utf8).write(to: locked.appendingPathComponent("内部.txt"))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0],
            ofItemAtPath: locked.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: locked.path
            )
        }

        fixture.store.prepareConfirmedFileImport([folder])
        waitForStage(.reviewing, in: fixture.store)
        XCTAssertEqual(
            fixture.store.confirmedFileImport?.candidates.map(\.sourceURL),
            [readable.standardizedFileURL]
        )
        XCTAssertEqual(
            fixture.store.confirmedFileImport?.failures.map(\.sourceURL),
            [locked.standardizedFileURL]
        )
        fixture.store.confirmFileImport()
        waitForStage(.finished, in: fixture.store)

        var batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(batch.importedItems.map(\.subtitle), ["可读.txt"])
        XCTAssertEqual(batch.failures.map(\.sourceURL), [locked.standardizedFileURL])
        XCTAssertEqual(batch.duplicateCount, 0)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: locked.path
        )
        fixture.store.retryFailedConfirmedFileImport()
        waitForStage(.reviewing, in: fixture.store)
        batch = try XCTUnwrap(fixture.store.confirmedFileImport)
        XCTAssertEqual(batch.candidates.map(\.sourceURL), [
            locked.appendingPathComponent("内部.txt").standardizedFileURL,
        ])
        XCTAssertEqual(batch.duplicateCount, 0)
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)

        XCTAssertEqual(
            Set(fixture.store.importedItems.map(\.subtitle)),
            Set(["可读.txt", "内部.txt"])
        )
        XCTAssertNil(fixture.store.transientNoteStatus)
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

    func testPendingBatchCannotSilentlyDiscardFailures() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let failed = fixture.outside.appendingPathComponent("失败.txt")
        let waiting = fixture.outside.appendingPathComponent("稍后.txt")
        try Data("failed".utf8).write(to: failed)
        try Data("waiting".utf8).write(to: waiting)
        let failure = ConfirmedFileImportFailure(sourceURL: failed, message: "失败")
        fixture.store.confirmedFileImport = ConfirmedFileImportBatch(
            id: UUID(),
            sourceURLs: [failed],
            sourceFolderNames: [],
            courseID: nil,
            importsMarkdownAsNotes: false,
            stage: .finished,
            failures: [failure],
            pendingSourceURLs: [waiting]
        )

        fixture.store.continuePendingConfirmedFileImport()
        XCTAssertEqual(fixture.store.confirmedFileImport?.failures, [failure])
        XCTAssertEqual(fixture.store.confirmedFileImport?.pendingSourceURLs, [waiting])

        fixture.store.retryFailedConfirmedFileImport()
        waitForStage(.reviewing, in: fixture.store)
        XCTAssertEqual(fixture.store.confirmedFileImport?.sourceURLs, [failed])
        XCTAssertEqual(fixture.store.confirmedFileImport?.pendingSourceURLs, [waiting])
    }

    func testPendingBatchContinuesAfterExplicitlyAbandoningFailures() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let failed = fixture.outside.appendingPathComponent("失败.txt")
        let waiting = fixture.outside.appendingPathComponent("稍后.txt")
        try Data("failed".utf8).write(to: failed)
        try Data("waiting".utf8).write(to: waiting)
        fixture.store.confirmedFileImport = ConfirmedFileImportBatch(
            id: UUID(),
            sourceURLs: [failed],
            sourceFolderNames: [],
            courseID: nil,
            importsMarkdownAsNotes: false,
            stage: .finished,
            failures: [ConfirmedFileImportFailure(sourceURL: failed, message: "失败")],
            pendingSourceURLs: [waiting]
        )

        fixture.store.continuePendingConfirmedFileImport(abandoningFailures: true)
        waitForStage(.reviewing, in: fixture.store)
        XCTAssertEqual(fixture.store.confirmedFileImport?.sourceURLs, [waiting])
        XCTAssertTrue(fixture.store.confirmedFileImport?.failures.isEmpty == true)
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

    func testMarkdownOnlyPlanKeepsUnsupportedFilenameUnlocalized() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let unsupported = fixture.outside.appendingPathComponent("讲义.pdf")
        try Data("pdf".utf8).write(to: unsupported)

        let plan = WorkspaceStore.makeConfirmedFileImportPlan(
            urls: [unsupported],
            destination: fixture.library.appendingPathComponent("通用笔记", isDirectory: true),
            markdownOnly: true
        )

        XCTAssertTrue(plan.candidates.isEmpty)
        XCTAssertEqual(plan.unsupportedNames, ["讲义.pdf"])
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
        waitForImportIdle(in: fixture.store)
        XCTAssertNil(fixture.store.confirmedFileImport)
        XCTAssertEqual(fixture.store.importedItems.filter { $0.subtitle == "同名.txt" }.count, 1)
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("1 个已存在") == true)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: fixture.library.appendingPathComponent("通用资料").path
            ),
            ["同名.txt"]
        )
    }

    func testSameNameCollisionGroupComparesEveryEarlierContent() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let directories = ["a", "b", "c"].map {
            fixture.outside.appendingPathComponent($0, isDirectory: true)
        }
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let files = directories.map { $0.appendingPathComponent("同名.txt") }
        try Data("A".utf8).write(to: files[0])
        try Data("B".utf8).write(to: files[1])
        try Data("B".utf8).write(to: files[2])

        fixture.store.prepareConfirmedFileImport(files)
        waitForStage(.reviewing, in: fixture.store)

        XCTAssertEqual(
            fixture.store.confirmedFileImport?.candidates.map(\.disposition),
            [.ready, .conflict(suggestedFileName: "同名 2.txt"), .duplicate]
        )
        fixture.store.confirmFileImport()
        waitForImportIdle(in: fixture.store)
        XCTAssertNil(fixture.store.confirmedFileImport)
        XCTAssertEqual(fixture.store.recentlyImportedItemIDs.count, 2)
        XCTAssertTrue(fixture.store.transientNoteStatus?.contains("1 个已存在") == true)
        XCTAssertEqual(
            try Set(FileManager.default.contentsOfDirectory(
                atPath: fixture.library.appendingPathComponent("通用资料").path
            )),
            Set(["同名.txt", "同名 2.txt"])
        )
    }

    func testSameNameHTMLUsesNormalizedImportedContentsForDuplicates() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let directories = ["a", "b"].map {
            fixture.outside.appendingPathComponent($0, isDirectory: true)
        }
        for directory in directories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let first = directories[0].appendingPathComponent("同名.html")
        let second = directories[1].appendingPathComponent("同名.html")
        try Data("<html><body><img src=\"甲.png\"></body></html>".utf8).write(to: first)
        try Data("<html><body><img src=\"乙.png\"></body></html>".utf8).write(to: second)
        let image = Data([0x89, 0x50, 0x4e, 0x47])
        try image.write(to: directories[0].appendingPathComponent("甲.png"))
        try image.write(to: directories[1].appendingPathComponent("乙.png"))
        XCTAssertNotEqual(try Data(contentsOf: first), try Data(contentsOf: second))

        let plan = WorkspaceStore.makeConfirmedFileImportPlan(
            urls: [first, second],
            destination: fixture.library.appendingPathComponent("通用资料", isDirectory: true),
            markdownOnly: false
        )

        XCTAssertEqual(plan.candidates.map(\.disposition), [.ready, .duplicate])
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

    func testSelectedRootDirectorySymlinkIsNotTraversed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let outsideDirectory = fixture.root.appendingPathComponent("边界外目录", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try Data("outside".utf8).write(to: outsideDirectory.appendingPathComponent("边界外.pdf"))
        let linkedRoot = fixture.outside.appendingPathComponent("链接资料包", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: outsideDirectory
        )

        let expansion = CourseProjectFileWorker.expandedImportSelection(
            from: [linkedRoot],
            markdownOnly: false
        )

        XCTAssertTrue(expansion.supported.isEmpty)
        XCTAssertTrue(expansion.unsupportedNames.isEmpty)
        XCTAssertTrue(expansion.unavailableSourceURLs.isEmpty)
    }

    func testNestedDirectorySymlinkIsNotTraversed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let selectedRoot = fixture.outside.appendingPathComponent("资料包", isDirectory: true)
        let outsideDirectory = fixture.root.appendingPathComponent("边界外目录", isDirectory: true)
        try FileManager.default.createDirectory(at: selectedRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        let safe = selectedRoot.appendingPathComponent("安全.pdf")
        try Data("safe".utf8).write(to: safe)
        try Data("outside".utf8).write(to: outsideDirectory.appendingPathComponent("边界外.pdf"))
        try FileManager.default.createSymbolicLink(
            at: selectedRoot.appendingPathComponent("链接目录", isDirectory: true),
            withDestinationURL: outsideDirectory
        )

        let expansion = CourseProjectFileWorker.expandedImportSelection(
            from: [selectedRoot],
            markdownOnly: false
        )

        XCTAssertEqual(expansion.supported, [safe.standardizedFileURL])
        XCTAssertTrue(expansion.unsupportedNames.isEmpty)
        XCTAssertTrue(expansion.unavailableSourceURLs.isEmpty)
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

    private func waitForImportIdle(
        in store: WorkspaceStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(10)
        while (store.confirmedFileImport != nil || store.confirmedFileImportTask != nil),
              Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertNil(store.confirmedFileImport, file: file, line: line)
        XCTAssertNil(store.confirmedFileImportTask, file: file, line: line)
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
