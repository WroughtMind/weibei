import AppKit
import WebKit
import XCTest
@testable import WeiBei

final class AgentVisualizationSizingTests: XCTestCase {
    func testGenUILoadFailureRetriesOnlyTheFirstAttempt() {
        var state = AgentVisualizationLoadState()
        state.fail("第一次失败", from: 0)
        XCTAssertEqual(state.attempt, 1)
        XCTAssertNil(state.failure)

        state.fail("第二次失败", from: 1)
        XCTAssertEqual(state.failure, "第二次失败")

        state.reload()
        XCTAssertEqual(state.attempt, 2)
        XCTAssertNil(state.failure)
    }

    @MainActor
    func testGenUIActionRejectsWhenChatWorkspaceCannotBePrepared() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiGenUIAction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("AgentRuntime"))
        let store = WorkspaceStore(workspaceDirectory: root, startsAtBlankEntries: true)

        let rejection = store.submitAgentVisualizationAction("继续解释", payloadJSON: "{}")

        XCTAssertTrue(rejection?.contains("Chat") == true)
        XCTAssertNil(store.agentRequestTask)
    }

    @MainActor
    func testGenUIAnswerButtonExplainsDisabledStateThenShowsQueuedAndProcessing() async throws {
        let messages = WKUserContentController()
        let actionProbe = GenUIActionProbe()
        messages.add(actionProbe, name: "weibeiGenUI")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = messages
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 240), configuration: configuration)
        let loaded = expectation(description: "GenUI runtime loaded")
        let navigationProbe = GenUINavigationProbe { loaded.fulfill() }
        webView.navigationDelegate = navigationProbe
        let entry = try XCTUnwrap(WeiBeiResources.bundle.url(forResource: "genui", withExtension: "html"))
        webView.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent())
        await fulfillment(of: [loaded], timeout: 3)

        let spec = #"{"items":[{"type":"button","label":"继续解释","action":"explain"}]}"#
        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.render({spec: \(spec), actionUnavailableReason: '另一条回答正在处理'})")
        let disabled = try await webView.evaluateJavaScript("document.querySelector('.button').disabled") as? Bool
        let unavailableText = try await webView.evaluateJavaScript("document.querySelector('.genui').textContent") as? String
        XCTAssertEqual(disabled, true)
        XCTAssertTrue(unavailableText?.contains("另一条回答正在处理") == true)

        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.render({spec: \(spec), actionStatus: 'ready'}); document.querySelector('.button').click()")
        let pressedText = try await webView.evaluateJavaScript("document.querySelector('.button').textContent") as? String
        XCTAssertTrue(pressedText?.contains("已按下") == true)
        let acceptedRequestID = try XCTUnwrap(actionProbe.requestIDs.last)
        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.actionResult({requestID: \(acceptedRequestID), accepted: true})")
        let queuedText = try await webView.evaluateJavaScript("document.querySelector('.button').textContent") as? String
        XCTAssertTrue(queuedText?.contains("已排队") == true)

        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.render({spec: \(spec), actionStatus: 'processing'})")
        let processingText = try await webView.evaluateJavaScript("document.querySelector('.button').textContent") as? String
        XCTAssertTrue(processingText?.contains("处理中") == true)

        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.render({spec: \(spec), actionStatus: 'ready'}); document.querySelector('.button').click()")
        let rejectedRequestID = try XCTUnwrap(actionProbe.requestIDs.last)
        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.actionResult({requestID: \(rejectedRequestID), accepted: false, reason: '互动数据过大'})")
        let rejectedDisabled = try await webView.evaluateJavaScript("document.querySelector('.button').disabled") as? Bool
        let rejectedText = try await webView.evaluateJavaScript("document.querySelector('.genui').textContent") as? String
        XCTAssertEqual(rejectedDisabled, false)
        XCTAssertTrue(rejectedText?.contains("互动数据过大") == true)
        withExtendedLifetime(navigationProbe) {}
    }

    @MainActor
    func testGenUIWheelInsideWebContentReachesConversationScroller() {
        let conversationScroller = ConversationScrollProbe()
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 1_200))
        conversationScroller.documentView = documentView

        let visibleHost = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 600))
        documentView.addSubview(visibleHost)
        let container = ConversationWebClippingView(webView: WKWebView())
        container.frame = NSRect(x: 0, y: 0, width: 640, height: 600)
        visibleHost.addSubview(container)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = conversationScroller
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(container.webView.frame, container.bounds)

        let visiblePoint = container.convert(
            CGPoint(x: visibleHost.bounds.midX, y: container.bounds.midY),
            to: nil
        )
        NSApp.sendEvent(ConversationScrollWheelEvent(window: window, location: visiblePoint))

        XCTAssertEqual(conversationScroller.receivedWheelEventCount, 1)

        let clippedPoint = container.convert(
            CGPoint(x: container.bounds.midX, y: container.bounds.midY),
            to: nil
        )
        NSApp.sendEvent(ConversationScrollWheelEvent(window: window, location: clippedPoint))

        XCTAssertEqual(conversationScroller.receivedWheelEventCount, 1)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func testGenUIHeightShrinksWhenACompressedPaneReopens() async throws {
        let messages = WKUserContentController()
        let heightProbe = GenUIHeightProbe()
        messages.add(heightProbe, name: "weibeiGenUI")
        messages.addUserScript(WKUserScript(
            source: "window.requestAnimationFrame = callback => { callback(); return 1; };",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = messages
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 72, height: 180),
            configuration: configuration
        )
        let loaded = expectation(description: "GenUI runtime loaded")
        let navigationProbe = GenUINavigationProbe { loaded.fulfill() }
        webView.navigationDelegate = navigationProbe

        let entry = try XCTUnwrap(
            WeiBeiResources.bundle.url(forResource: "genui", withExtension: "html")
        )
        webView.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent())
        await fulfillment(of: [loaded], timeout: 3)

        let repeatedText = String(repeating: "快速切换后内容仍应完整刷新。", count: 20)
        let spec: [String: Any] = [
            "items": (0..<8).map { _ in
                ["type": "text", "content": repeatedText]
            },
        ]
        let data = try JSONSerialization.data(withJSONObject: ["spec": spec])
        let payload = try XCTUnwrap(String(data: data, encoding: .utf8))
        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.render(\(payload))")

        try await waitForHeight(in: heightProbe, greaterThan: 1_000)
        let compressedHeight = try XCTUnwrap(heightProbe.heights.last)

        // Mirror the SwiftUI host: accept the measured height, then reopen wide.
        let reopenReportIndex = heightProbe.heights.count
        webView.frame.size.height = compressedHeight
        webView.frame.size.width = 640
        webView.layoutSubtreeIfNeeded()

        try await waitForHeight(
            in: heightProbe,
            after: reopenReportIndex,
            lessThan: compressedHeight * 0.75
        )
        XCTAssertLessThan(try XCTUnwrap(heightProbe.heights.last), compressedHeight * 0.75)
        withExtendedLifetime(navigationProbe) {}
    }

    @MainActor
    private func waitForHeight(
        in probe: GenUIHeightProbe,
        after index: Int = 0,
        greaterThan lowerBound: CGFloat? = nil,
        lessThan upperBound: CGFloat? = nil
    ) async throws {
        for _ in 0..<75 {
            if probe.heights.dropFirst(index).contains(where: { height in
                (lowerBound.map { height > $0 } ?? true)
                    && (upperBound.map { height < $0 } ?? true)
            }) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("GenUI did not report a height in the expected range: \(probe.heights)")
    }
}

private final class GenUIActionProbe: NSObject, WKScriptMessageHandler {
    private(set) var requestIDs: [Int] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              body["type"] as? String == "action",
              let requestID = body["requestID"] as? NSNumber else { return }
        requestIDs.append(requestID.intValue)
    }
}

private final class ConversationScrollWheelEvent: NSEvent {
    private weak var eventWindow: NSWindow?
    private let eventLocation: NSPoint

    init(window: NSWindow, location: NSPoint) {
        eventWindow = window
        eventLocation = location
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var type: NSEvent.EventType { .scrollWheel }
    override weak var window: NSWindow? { eventWindow }
    override var locationInWindow: NSPoint { eventLocation }
    override var scrollingDeltaX: CGFloat { 0 }
    override var scrollingDeltaY: CGFloat { 24 }
}

private final class ConversationScrollProbe: NSScrollView {
    private(set) var receivedWheelEventCount = 0

    override func scrollWheel(with event: NSEvent) {
        receivedWheelEventCount += 1
    }
}

private final class GenUIHeightProbe: NSObject, WKScriptMessageHandler {
    private(set) var heights: [CGFloat] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              body["type"] as? String == "height",
              let number = body["height"] as? NSNumber else { return }
        heights.append(CGFloat(number.doubleValue))
    }
}

private final class GenUINavigationProbe: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
