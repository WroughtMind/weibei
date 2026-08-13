import AppKit
import WebKit
import XCTest
@testable import WeiBei

final class AgentVisualizationSizingTests: XCTestCase {
    @MainActor
    func testGenUIVerticalWheelReachesConversationScroller() throws {
        let conversationScroller = ConversationScrollProbe()
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 1_200))
        conversationScroller.documentView = documentView

        let container = ConversationWebClippingView(webView: WKWebView())
        container.frame = NSRect(x: 0, y: 0, width: 640, height: 600)
        documentView.addSubview(container)

        let cgEvent = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: 24,
            wheel2: 0,
            wheel3: 0
        ))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))

        container.scrollWheel(with: event)

        XCTAssertEqual(conversationScroller.receivedWheelEventCount, 1)
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
