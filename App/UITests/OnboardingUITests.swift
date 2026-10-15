import XCTest

/// Drives the separately built acceptance App through Xcode's public UI testing
/// service. Product assertions stay in CatalystBusinessCheck, beside the real
/// store, files and credentials; this runner only queries, clicks and types.
final class OnboardingUITests: XCTestCase {
    private struct DriverFailure: LocalizedError {
        let errorDescription: String?
    }

    @MainActor
    func testFirstUseInTheActualApp() async throws {
        continueAfterFailure = false
        let configuration = Bundle(for: Self.self)
        let appPath = try XCTUnwrap(configuration.object(forInfoDictionaryKey: "WeiBeiCheckAppPath") as? String)
        XCTAssertFalse(appPath.isEmpty)
        // Xcode sandboxes its UI runner. Use the runner's own temporary folder,
        // rather than asking it to write into the acceptance App's data folder.
        let channel = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiOnboardingUI-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: channel, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: channel) }
        let requestURL = channel.appendingPathComponent("onboarding-ui-request.json")
        let responseURL = channel.appendingPathComponent("onboarding-ui-response.json")

        let app = XCUIApplication(url: URL(fileURLWithPath: appPath))
        app.launchArguments = ["--exit-after-check"]
        app.launchEnvironment["WEIBEI_ONBOARDING_UI_DIRECTORY"] = channel.path
        app.launch()
        defer { if app.state != .notRunning { app.terminate() } }
        let deadline = Date().addingTimeInterval(360) // Same bound as the existing CI app launch.
        var handled: String?
        while app.state != .notRunning, Date() < deadline {
            guard let data = try? Data(contentsOf: requestURL),
                  let request = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  let token = request["token"], token != handled,
                  let action = request["action"], let id = request["id"] else {
                // Application state updates arrive asynchronously. Yield the
                // main actor so a completed App cannot remain cached as running.
                try await Task.sleep(for: .milliseconds(50))
                continue
            }
            handled = token
            let matches = app.descendants(matching: .any).matching(identifier: id)
            let element = matches.firstMatch
            var response: [String: Any] = ["token": token]
            switch action {
            case "query":
                if element.exists {
                    // Secure/text field contents must never enter diagnostics.
                    let text = element.elementType == .staticText ? element.value as? String : nil
                    response["element"] = ["id": id, "label": text ?? element.label,
                                           "enabled": String(element.isEnabled),
                                           "hittable": String(element.isHittable),
                                           "frame": String(describing: element.frame),
                                           "matches": String(matches.count)]
                }
            case "press", "fill":
                guard element.exists, element.isEnabled, element.isHittable else {
                    let screenshot = XCTAttachment(screenshot: app.screenshot())
                    screenshot.name = "Unreachable control: " + id
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                    let frame = element.exists ? String(describing: element.frame) : "missing"
                    throw DriverFailure(errorDescription: "Unreachable mounted control: \(id), frame=\(frame), matches=\(matches.count)")
                }
                element.click()
                if action == "fill" {
                    let value = try XCTUnwrap(request["value"])
                    element.typeKey("a", modifierFlags: .command)
                    element.typeText(value)
                }
            default:
                throw DriverFailure(errorDescription: "Unknown UI operation: \(action)")
            }
            try JSONSerialization.data(withJSONObject: response).write(to: responseURL, options: .atomic)
        }
        XCTAssertEqual(app.state, .notRunning, "The acceptance App did not finish its checks")
    }
}
