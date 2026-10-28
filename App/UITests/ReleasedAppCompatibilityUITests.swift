#if WEIBEI_RELEASE_COMPATIBILITY_CHECKS
import XCTest

/// Operates the downloaded production bundle without adding hooks to the App.
/// The diagnostic workflow alone enables this suite on an isolated desktop.
final class ReleasedAppCompatibilityUITests: XCTestCase {
    @MainActor
    func testSettingsPointerAndKeyboard() throws {
        let app = try launch()
        defer {
            record(app, "final-state")
            if app.state != .notRunning { app.terminate() }
        }
        let settings = app.buttons["Open Settings"].firstMatch
        guard settings.waitForExistence(timeout: 15) else { XCTFail("Missing settings toolbar button"); return }
        settings.click()
        let closeSettings = app.buttons["settings-panel-close"].firstMatch
        guard closeSettings.waitForExistence(timeout: 15) else { XCTFail("Settings did not open after a pointer click"); return }
        record(app, "settings")
        closeSettings.click()
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(closeSettings.waitForExistence(timeout: 15), "Settings keyboard shortcut must work after pointer interaction")
    }

    @MainActor
    func testNotePersistenceAndDocumentPicker() throws {
        let app = try launch()
        defer {
            record(app, "final-note-state")
            if app.state != .notRunning { app.terminate() }
        }
        // A duplicate shortcut can discard a whole menu group on macOS 15.
        for title in ["New Blank Note", "Open Document", "Workspace", "Copy Current Reference"] {
            XCTAssertTrue(app.menuItems[title].firstMatch.exists, "Missing workspace menu: \(title)")
        }
        let composer = app.textViews["agent-composer-compact"]
        if composer.exists { composer.click() }
        app.typeKey("n", modifierFlags: .command)
        let editor = app.webViews.textViews.firstMatch
        guard editor.waitForExistence(timeout: 30) else { XCTFail("The new note must mount its editable WebKit body"); return }
        // Xcode 15's direct WebKit element click can stall while searching for
        // interrupting elements. Click its visible location on the real window.
        let window = app.windows.matching(identifier: "SceneWindow").firstMatch
        let editorFrame = editor.frame
        let windowFrame = window.frame
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: editorFrame.midX - windowFrame.minX,
            dy: editorFrame.midY - windowFrame.minY
        )).click()
        let marker = "WeiBei compatibility saved note " + UUID().uuidString
        app.typeText(marker)
        XCTAssertTrue(waitForText(marker, in: app))
        record(app, "edited-note")

        // Exercise the product's normal save-on-Quit path, then reopen the same bundle.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 30))
        app.launch()
        XCTAssertTrue(waitForText(marker, in: app), "The typed note must survive Quit and reopen")
        record(app, "restored-note")

        app.typeKey("o", modifierFlags: .command)
        // macOS 14 also exposes a Touch Bar Cancel button, which cannot be clicked.
        let cancel = app.sheets["open-panel"].buttons["CancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "The native document picker must open")
        record(app, "document-picker")
        cancel.click()
        XCTAssertTrue(waitForText(marker, in: app), "Cancelling the picker must preserve the note")
    }

    @MainActor
    private func launch() throws -> XCUIApplication {
        continueAfterFailure = true
        let configuration = Bundle(for: Self.self)
        XCTAssertEqual(configuration.object(forInfoDictionaryKey: "WeiBeiCIExternalPromptHandling") as? String, "1")
        let path = try XCTUnwrap(configuration.object(forInfoDictionaryKey: "WeiBeiCheckAppPath") as? String)
        let app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        record(app, "launched")
        return app
    }

    @MainActor
    private func waitForText(_ text: String, in app: XCUIApplication) -> Bool {
        let editor = app.webViews.textViews.firstMatch
        let predicate = NSPredicate { _, _ in
            editor.exists && (editor.value as? String)?.contains(text) == true
        }
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
