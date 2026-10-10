import XCTest
import Combine
import Sparkle
@testable import WeiBei

final class WeiBeiUpdateServiceTests: XCTestCase {
    func testNotesKeepHeadingsAndEveryLateChange() {
        let details = (1...12).map { "<li>改动\($0)</li>" }.joined()
        let notes = WeiBeiAvailableUpdate.releaseNotesLines(from:
            "<h2>改进</h2><ul>\(details)</ul><h2>已知问题</h2><p>需要重新打开资料</p>")
        XCTAssertEqual(notes.count, 15)
        XCTAssertTrue(WeiBeiAvailableUpdate.isHeading(notes[0]))
        XCTAssertTrue(WeiBeiAvailableUpdate.isHeading(notes[13]))
        XCTAssertEqual(notes.last, "需要重新打开资料")
    }

    @MainActor func testProgressUsesBytesAndHandlesMissingOrChangedLength() {
        let service = WeiBeiUpdateService(startsUpdater: false)
        service.showDownloadDidReceiveData(ofLength: 20)
        XCTAssertNil(service.downloadProgress)
        service.showDownloadDidReceiveExpectedContentLength(100)
        XCTAssertEqual(service.downloadProgress, 0.2)
        service.showDownloadDidReceiveData(ofLength: 30)
        XCTAssertEqual(service.downloadProgress, 0.5)
        service.showDownloadDidReceiveExpectedContentLength(200)
        XCTAssertEqual(service.downloadProgress, 0.25)
        service.showDownloadDidReceiveExpectedContentLength(10)
        XCTAssertNil(service.downloadProgress)
    }

    @MainActor func testReadyWaitsForClickAndSuccessfulSaveBeforeRelaunch() async {
        let update = WeiBeiAvailableUpdate(version: "1.2.3", releaseNotesLines: [],
            informationOnly: false, informationURL: nil)
        let service = WeiBeiUpdateService(startsUpdater: false, availableUpdate: update)
        var saveCalls = 0
        var canSave = false
        service.prepareForInstallation = { saveCalls += 1; return canSave }
        let ready = expectation(description: "Update prepared without restarting")
        let observation = service.$status.sink { if $0 == .ready { ready.fulfill() } }
        let installation = Task { await service.showReadyToInstallAndRelaunch() }
        await fulfillment(of: [ready], timeout: 2)
        XCTAssertEqual(saveCalls, 0)
        XCTAssertFalse(service.isBusy)
        observation.cancel()

        let failed = expectation(description: "Save failure blocks restarting")
        let failureObservation = service.$status.sink { if $0 == .failed { failed.fulfill() } }
        service.installAvailableUpdate()
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(saveCalls, 1)
        XCTAssertNotNil(service.errorDescription)
        XCTAssertEqual(service.availableUpdate, update)
        failureObservation.cancel()

        canSave = true
        service.installAvailableUpdate()
        let choice = await installation.value
        XCTAssertEqual(choice, .install)
        XCTAssertEqual(saveCalls, 2)
        XCTAssertEqual(service.status, .installing)
    }

    @MainActor func testCheckFailureIsNotReportedAsLatestVersion() async {
        let service = WeiBeiUpdateService(startsUpdater: false)
        await service.showUpdateNotFoundWithError(URLError(.notConnectedToInternet))
        XCTAssertEqual(service.status, .failed)
        XCTAssertNotNil(service.errorDescription)
    }
}
