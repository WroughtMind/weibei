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
        let autoFillMonitor = addUIInterruptionMonitor(withDescription: "Password AutoFill") { _ in
            // The window can arrive after the immediate post-click check below.
            let autoFill = app.windows["SafariPlatformSupportAutoCompleteWindow"]
            guard autoFill.exists else { return false }
            autoFill.typeKey(.escape, modifierFlags: [])
            return !autoFill.exists
        }
        defer { removeUIInterruptionMonitor(autoFillMonitor) }
        app.launchArguments = ["--exit-after-check"]
        app.launchEnvironment["WEIBEI_ONBOARDING_UI_DIRECTORY"] = channel.path
        app.launch()
        defer { if app.state != .notRunning { app.terminate() } }
        let deadline = Date().addingTimeInterval(360) // Same bound as the existing CI app launch.
        var handled: String?
        var recordedUnreachable = Set<String>()
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
            case "query", "ready":
                // One snapshot keeps observation atomic when a banner or form
                // disappears between requests. Live attribute reads can fail
                // after an earlier `exists` returned true.
                let root = try app.snapshot()
                let snapshots = matchingSnapshots(in: root, identifier: id)
                if let snapshot = snapshots.first {
                    // Secure/text field contents must never enter diagnostics.
                    let text = snapshot.elementType == .staticText ? snapshot.value as? String : nil
                    var state = ["id": id, "label": text ?? snapshot.label,
                                 "enabled": String(snapshot.isEnabled),
                                 "frame": String(describing: snapshot.frame),
                                 "matches": String(snapshots.count)]
                    if action == "ready" {
                        let hittable = element.isHittable
                        state["hittable"] = String(hittable)
                        state["ancestor_path"] = ancestorPath(in: root, identifier: id)?.joined(separator: "\n") ?? ""
                        if !hittable {
                            let center = CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY)
                            state["overlapping_controls"] = identifiedControls(in: root, containing: center).joined(separator: "\n")
                        }
                        if !hittable, recordedUnreachable.insert(id).inserted {
                            let screenshot = XCTAttachment(screenshot: app.screenshot())
                            screenshot.name = "Waiting for control: " + id
                            screenshot.lifetime = .keepAlways
                            add(screenshot)
                        }
                    }
                    response["element"] = state
                } else {
                    response["visible_controls"] = identifiedControls(in: root).joined(separator: "\n")
                }
            case "press-coordinate-diagnostic":
                guard element.exists, element.isEnabled, !element.frame.isEmpty else {
                    throw DriverFailure(errorDescription: "Coordinate baseline has no mounted target: " + id)
                }
                // Diagnostic only: measure real pointer delivery independently
                // of accessibility hit testing. The App still fails that gate.
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            case "press", "fill", "hover":
                guard element.exists, element.isEnabled, element.isHittable else {
                    let screenshot = XCTAttachment(screenshot: app.screenshot())
                    screenshot.name = "Unreachable control: " + id
                    screenshot.lifetime = .keepAlways
                    add(screenshot)
                    let frame = element.exists ? String(describing: element.frame) : "missing"
                    throw DriverFailure(errorDescription: "Unreachable mounted control: \(id), frame=\(frame), matches=\(matches.count)")
                }
                if action == "hover" { element.hover() }
                else { element.click() }
                if action == "fill" {
                    let value = try XCTUnwrap(request["value"])
                    // A secure field may open the system Password AutoFill window.
                    // Dismiss that window directly before typing, so XCTest's
                    // interruption handling cannot invalidate the target field.
                    let autoFill = app.windows["SafariPlatformSupportAutoCompleteWindow"]
                    if autoFill.exists {
                        autoFill.typeKey(.escape, modifierFlags: [])
                        XCTAssertFalse(autoFill.exists, "Password AutoFill stayed open before text entry")
                    }
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

    @MainActor
    private func matchingSnapshots(in root: any XCUIElementSnapshot, identifier: String) -> [any XCUIElementSnapshot] {
        (root.identifier == identifier ? [root] : [])
            + root.children.flatMap { matchingSnapshots(in: $0, identifier: identifier) }
    }

    @MainActor
    private func ancestorPath(in root: any XCUIElementSnapshot, identifier: String) -> [String]? {
        let entry = "\(root.identifier): \(root.elementType) \(root.frame)"
        if root.identifier == identifier { return [entry] }
        for child in root.children {
            if let path = ancestorPath(in: child, identifier: identifier) { return [entry] + path }
        }
        return nil
    }

    @MainActor
    private func identifiedControls(in root: any XCUIElementSnapshot, containing point: CGPoint? = nil) -> [String] {
        // Keep only control identifiers and geometry, never labels or field values.
        (root.identifier.isEmpty || point.map({ !root.frame.contains($0) }) == true
            ? [] : ["\(root.identifier): \(root.elementType) \(root.frame)"])
            + root.children.flatMap { identifiedControls(in: $0, containing: point) }
    }
}
