import XCTest

/// Drives the separately built acceptance App through Xcode's public UI testing
/// service. Product assertions stay in CatalystBusinessCheck, beside the real
/// store, files and credentials; this runner only queries, clicks and types.
final class OnboardingUITests: XCTestCase {
    @MainActor
    func testFirstUseInTheActualApp() throws {
        continueAfterFailure = false
        let configuration = Bundle(for: Self.self)
        let appPath = try XCTUnwrap(configuration.object(forInfoDictionaryKey: "WeiBeiCheckAppPath") as? String)
        let supportPath = try XCTUnwrap(configuration.object(forInfoDictionaryKey: "WeiBeiCheckSupportPath") as? String)
        XCTAssertFalse(appPath.isEmpty)
        XCTAssertFalse(supportPath.isEmpty)
        let results = URL(fileURLWithPath: supportPath).appendingPathComponent("Results")
        let requestURL = results.appendingPathComponent("onboarding-ui-request.json")
        let responseURL = results.appendingPathComponent("onboarding-ui-response.json")
        for url in [requestURL, responseURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let app = XCUIApplication(url: URL(fileURLWithPath: appPath))
        app.launchArguments = ["--exit-after-check"]
        app.launch()
        defer { if app.state != .notRunning { app.terminate() } }
        let deadline = Date().addingTimeInterval(360) // Same bound as the existing CI app launch.
        var handled: String?
        while app.state != .notRunning, Date() < deadline {
            guard let data = try? Data(contentsOf: requestURL),
                  let request = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  let token = request["token"], token != handled,
                  let action = request["action"], let id = request["id"] else {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            handled = token
            let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
            var response: [String: Any] = ["token": token]
            switch action {
            case "query":
                if element.exists {
                    // Secure/text field contents must never enter diagnostics.
                    let text = element.elementType == .staticText ? element.value as? String : nil
                    response["element"] = ["id": id, "label": text ?? element.label,
                                           "enabled": String(element.isEnabled),
                                           "hittable": String(element.isHittable)]
                }
            case "press", "fill":
                XCTAssertTrue(element.exists, "Missing mounted control: \(id)")
                XCTAssertTrue(element.isEnabled, "Disabled mounted control: \(id)")
                XCTAssertTrue(element.isHittable, "Unreachable mounted control: \(id)")
                element.click()
                if action == "fill" {
                    let value = try XCTUnwrap(request["value"])
                    element.typeKey("a", modifierFlags: .command)
                    element.typeText(value)
                }
            default:
                XCTFail("Unknown UI operation: \(action)")
            }
            try JSONSerialization.data(withJSONObject: response).write(to: responseURL, options: .atomic)
        }
        XCTAssertEqual(app.state, .notRunning, "The acceptance App did not finish its checks")
    }
}
