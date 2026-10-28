#if WEIBEI_RELEASE_COMPATIBILITY_CHECKS
import XCTest

/// Operates the downloaded production bundle without adding hooks to the App.
/// The diagnostic workflow alone enables this suite on an isolated desktop.
final class ReleasedAppCompatibilityUITests: XCTestCase {
    @MainActor
    func testSettingsNotePersistenceAndDocumentPicker() throws {
        continueAfterFailure = false
        let configuration = Bundle(for: Self.self)
        XCTAssertEqual(configuration.object(forInfoDictionaryKey: "WeiBeiCIExternalPromptHandling") as? String, "1")
        let path = try XCTUnwrap(configuration.object(forInfoDictionaryKey: "WeiBeiCheckAppPath") as? String)
        let app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer {
            record(app, "final-state")
            if app.state != .notRunning { app.terminate() }
        }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))

        app.typeKey(",", modifierFlags: .command)
        let closeSettings = app.buttons["settings-panel-close"]
        XCTAssertTrue(closeSettings.waitForExistence(timeout: 15))
        record(app, "settings")
        closeSettings.click()

        app.typeKey("n", modifierFlags: .command)
        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "The new note must mount its editable WebKit body")
        editor.click()
        let marker = "WeiBei compatibility saved note " + UUID().uuidString
        editor.typeText(marker)
        XCTAssertTrue(waitForText(marker, in: app))
        record(app, "edited-note")

        // Exercise the product's normal save-on-Quit path, then reopen the same bundle.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30))
        app.launch()
        XCTAssertTrue(waitForText(marker, in: app), "The typed note must survive Quit and reopen")
        record(app, "restored-note")

        app.typeKey("o", modifierFlags: .command)
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "The native document picker must open")
        record(app, "document-picker")
        cancel.click()
        XCTAssertTrue(waitForText(marker, in: app), "Cancelling the picker must preserve the note")
    }

    @MainActor
    private func waitForText(_ text: String, in app: XCUIApplication) -> Bool {
        let predicate = NSPredicate { _, _ in app.debugDescription.contains(text) }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 30) == .completed
    }

    @MainActor
    private func record(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
#endif
