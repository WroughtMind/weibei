import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

final class OnboardingCourseTests: XCTestCase {
    func testPreferredLanguageFollowsTheFirstChineseOrEnglishPreference() {
        XCTAssertEqual(WeiBeiInterfaceLanguage.matchingPreferredLanguages(["zh-Hant-TW", "en"]), .chinese)
        XCTAssertEqual(WeiBeiInterfaceLanguage.matchingPreferredLanguages(["en-US", "zh-Hans"]), .english)
        XCTAssertEqual(WeiBeiInterfaceLanguage.matchingPreferredLanguages(["ja-JP"]), .english)
    }

    func testPublicVersionLineOmitsCommitWhileDiagnosticsKeepIt() {
        let info = WeiBeiAppBuildInfo(version: "1.2.3", build: "20260924.0100.00", commit: "abcdef123456", isDirty: true)
        XCTAssertEqual(info.displayLine, "1.2.3 (20260924.0100.00)")
        XCTAssertFalse(info.displayLine.contains("abcdef12"))
        XCTAssertTrue(info.diagnosticLine.contains("abcdef12"))
        XCTAssertTrue(info.diagnosticLine.contains("dirty"))
    }

    func testFeedbackLinkPrefillsTitleAndBodyWithoutALabel() throws {
        let url = try XCTUnwrap(WeiBeiFeedbackLink.prefilled(title: "打不开", body: "步骤\n第二行"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/WroughtMind/weibei/issues/new")
        let items = components.queryItems ?? []
        XCTAssertEqual(items.map(\.name), ["title", "body"])
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "打不开")
        XCTAssertEqual(items.first { $0.name == "body" }?.value, "步骤\n第二行")
    }

    func testCourseCreationErrorsKeepTheRealReasonInBothLanguages() {
        XCTAssertTrue(CourseProjectRootError.rootMustNotExist.userFacingDescription(language: .chinese).contains("已经存在"))
        XCTAssertTrue(CourseProjectRootError.rootMustNotExist.userFacingDescription(language: .english).localizedCaseInsensitiveContains("already exists"))
        XCTAssertTrue(CourseProjectRootError.dangerousRoot.userFacingDescription(language: .chinese).contains("文稿"))
        XCTAssertTrue(CourseProjectRootError.dangerousRoot.userFacingDescription(language: .english).contains("Documents"))
        XCTAssertEqual(
            CourseProjectRootError.rootMustNotExist.errorDescription,
            CourseProjectRootError.rootMustNotExist.userFacingDescription(language: .chinese)
        )
    }

    func testGlobalSearchAvailabilityIgnoresOtherCoursesAndKnownMissingItems() {
        XCTAssertEqual(
            CourseSearchAvailability.decide(
                countedItemIDs: ["current"],
                states: ["current": .ready, "other": .unavailable]
            ),
            .ready
        )
        XCTAssertEqual(
            CourseSearchAvailability.decide(countedItemIDs: [], states: ["missing": .unavailable]),
            .ready
        )
        XCTAssertEqual(
            CourseSearchAvailability.decide(countedItemIDs: ["current"], states: [:]),
            .unavailable
        )
        XCTAssertEqual(
            CourseSearchAvailability.decide(countedItemIDs: ["current"], states: ["current": .indexing]),
            .indexing
        )
    }

    @MainActor
    func testSavedInterfaceLanguageIsNotReplacedByTheSystemPreference() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WorkspaceStore(
            workspaceDirectory: root.appendingPathComponent("Workspace"),
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        store.setInterfaceLanguage(.english)
        let saved = try store.waitForCourseFileOperation { await store.flushPendingWorkspaceSaveAsync() }
        XCTAssertTrue(saved)
        let reopened = WorkspaceStore(
            workspaceDirectory: root.appendingPathComponent("Workspace"),
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )
        XCTAssertEqual(reopened.interfaceLanguage, .english)
    }

    @MainActor
    func testOpeningAReaderSearchSelectsTheFirstMatchOnce() {
        let pane = WorkspacePaneState()
        pane.pendingFirstReaderMatch = true
        pane.adoptReaderSearchResults(
            [ReaderSearchResult(id: 0, pageIndex: 1, preview: "命中")],
            reportedIndex: -1,
            query: "命中",
            materialID: "material"
        )
        XCTAssertEqual(pane.readerSearchResultIndex, 0)
        XCTAssertEqual(pane.readerSearchNavigationRequest, 1)
        XCTAssertFalse(pane.pendingFirstReaderMatch)
        pane.adoptReaderSearchResults(
            [ReaderSearchResult(id: 0, pageIndex: 1, preview: "命中")],
            reportedIndex: -1,
            query: "命中",
            materialID: "material"
        )
        XCTAssertEqual(pane.readerSearchResultIndex, -1)
        XCTAssertEqual(pane.readerSearchNavigationRequest, 1)
    }
}
