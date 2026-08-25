import AppKit
import WebKit
import XCTest
@testable import WeiBei

final class AgentVisualizationSizingTests: XCTestCase {
    func testGenUILoadFailureRetriesOnceThenWaitsForUserReload() {
        var state = AgentVisualizationLoadState()
        let firstAttempt = state.attempt

        state.fail("首次失败", from: firstAttempt)
        XCTAssertNil(state.failure)

        let retriedAttempt = state.attempt
        state.fail("再次失败", from: retriedAttempt)
        XCTAssertEqual(state.failure, "再次失败")

        state.reload()
        XCTAssertNil(state.failure)
        XCTAssertGreaterThan(state.attempt, retriedAttempt)
    }

    @MainActor
    func testGenUIActionRoundTripShowsRejection() async throws {
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
        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.render({spec: \(spec), actionStatus: 'ready'}); document.querySelector('.button').click()")
        let requestID = try XCTUnwrap(actionProbe.requestID)
        XCTAssertEqual(actionProbe.action, "explain")
        let rejection = "当前无法提交这条回答。"
        let resultData = try JSONSerialization.data(withJSONObject: [
            "requestID": requestID,
            "accepted": false,
            "reason": rejection,
        ])
        let resultJSON = try XCTUnwrap(String(data: resultData, encoding: .utf8))
        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.actionResult(\(resultJSON))")
        let rejectedDisabled = try await webView.evaluateJavaScript("document.querySelector('.button').disabled") as? Bool
        let rejectedText = try await webView.evaluateJavaScript("document.querySelector('.genui').textContent") as? String
        XCTAssertEqual(rejectedDisabled, false)
        XCTAssertTrue(rejectedText?.contains(rejection) == true)
        withExtendedLifetime(navigationProbe) {}
    }

    @MainActor
    func testGenUIActionRejectsWhenChatWorkspaceCannotBePrepared() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeiBeiGenUIAction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appendingPathComponent("AgentRuntime"))
        let store = WorkspaceStore(
            workspaceDirectory: root,
            startsAtBlankEntries: true,
            startsCourseFileMaintenance: false
        )

        let rejection = store.submitAgentVisualizationAction(
            "继续解释",
            payloadJSON: "{}"
        )

        guard case .agentRefused = rejection else {
            XCTFail("expected an askAgent refusal, got \(String(describing: rejection))")
            return
        }
        XCTAssertNil(store.agentRequestTask)
    }

    @MainActor
    func testGenUIRejectsOverlongActionNameWithoutChangingIt() {
        let store = WorkspaceStore(
            workspaceDirectory: FileManager.default.temporaryDirectory,
            startsAtBlankEntries: true
        )
        let action = String(repeating: "动作", count: 101)
        let rejection = store.submitAgentVisualizationAction(action, payloadJSON: "{}")
        XCTAssertEqual(rejection, .actionNameTooLong)
    }

    @MainActor
    func testGenUIKeepsFullFormInputAfterRedraw() async throws {
        let (webView, navigationProbe) = try await loadGenUI()
        let input = String(repeating: "这是需要完整保留的课堂问题，包括背景、推理和引用。", count: 300)
            + "问题末尾"
        let encodedInput = try XCTUnwrap(
            String(data: JSONEncoder().encode(input), encoding: .utf8)
        )
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const spec = {items:[{type:'textarea', id:'answer'}]};
          window.WeiBeiGenUIHost.render({spec});
          const control = document.querySelector('textarea');
          control.value = \(encodedInput);
          control.dispatchEvent(new Event('input'));
          window.WeiBeiGenUIHost.render({spec, state: window.WeiBeiGenUIHost.snapshot()});
          return document.querySelector('textarea').value;
        })()
        """) as? String

        XCTAssertEqual(result, input)
        withExtendedLifetime(navigationProbe) {}
    }

    @MainActor
    func testGenUICopyWritesFullText() async throws {
        let (webView, navigationProbe) = try await loadGenUI()
        let text = String(repeating: "需要完整复制的学习内容。", count: 1_000) + "复制末尾"
        let data = try JSONSerialization.data(withJSONObject: [
            "spec": ["items": [["type": "copy", "text": text]]],
        ])
        let payload = try XCTUnwrap(String(data: data, encoding: .utf8))
        let result = try await webView.evaluateJavaScript("""
        (() => {
          Object.defineProperty(navigator, 'clipboard', {
            configurable: true,
            value: {writeText: text => { window.copiedText = text; return Promise.resolve(); }}
          });
          window.WeiBeiGenUIHost.render(\(payload));
          document.querySelector('.button').click();
          return window.copiedText;
        })()
        """) as? String

        XCTAssertEqual(result, text)
        withExtendedLifetime(navigationProbe) {}
    }

    @MainActor
    func testGenUIKeepsFullTextAndRevealsWholeTable() async throws {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 240),
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

        let tailMarker = "正文末尾仍然可见"
        let content = String(repeating: "正文", count: 10_000) + tailMarker
        let columns = (0..<13).map { "第 \($0) 列" }
        let rows = (0..<120).map { row in columns.map { "第 \(row) 行 · \($0)" } }
        let data = try JSONSerialization.data(withJSONObject: [
            "spec": [
                "items": [[
                    "type": "text",
                    "content": content,
                ], [
                    "type": "table",
                    "columns": columns,
                    "rows": rows,
                ]],
            ],
        ])
        let payload = try XCTUnwrap(String(data: data, encoding: .utf8))
        _ = try await webView.evaluateJavaScript("window.WeiBeiGenUIHost.render(\(payload))")
        let visibleText = try await webView.evaluateJavaScript("document.querySelector('.text').textContent") as? String
        let totalRows = rows.count
        let initialRows = try await webView.evaluateJavaScript("document.querySelectorAll('tbody tr').length") as? Int
        let progress = try await webView.evaluateJavaScript("document.querySelector('.data-progress').textContent") as? String
        _ = try await webView.evaluateJavaScript("while (!document.querySelector('.table-wrap > .data-progress button').hidden) document.querySelector('.table-wrap > .data-progress button').click()")
        let revealedRows = try await webView.evaluateJavaScript("document.querySelectorAll('tbody tr').length") as? Int
        let revealedColumns = try await webView.evaluateJavaScript("document.querySelectorAll('thead th').length") as? Int

        XCTAssertTrue(visibleText?.contains(tailMarker) == true)
        XCTAssertNotNil(initialRows)
        XCTAssertLessThan(initialRows ?? totalRows, totalRows)
        XCTAssertTrue(progress?.range(of: #"\d+/\d+"#, options: .regularExpression) != nil)
        XCTAssertEqual(revealedRows, totalRows)
        XCTAssertEqual(revealedColumns, columns.count)

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

    @MainActor
    private func loadGenUI() async throws -> (WKWebView, GenUINavigationProbe) {
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 240),
            configuration: WKWebViewConfiguration()
        )
        let loaded = expectation(description: "GenUI runtime loaded")
        let navigationProbe = GenUINavigationProbe { loaded.fulfill() }
        webView.navigationDelegate = navigationProbe
        let entry = try XCTUnwrap(
            WeiBeiResources.bundle.url(forResource: "genui", withExtension: "html")
        )
        webView.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent())
        await fulfillment(of: [loaded], timeout: 3)
        return (webView, navigationProbe)
    }
}

private final class GenUIActionProbe: NSObject, WKScriptMessageHandler {
    private(set) var requestID: Int?
    private(set) var action: String?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              body["type"] as? String == "action",
              let requestID = body["requestID"] as? NSNumber,
              let action = body["action"] as? String else { return }
        self.requestID = requestID.intValue
        self.action = action
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
