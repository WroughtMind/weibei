import SwiftUI
import WebKit
import XCTest
@testable import WeiBei

final class RichMarkdownEditorBridgeTests: XCTestCase {
    @MainActor
    func testFinalizedMarkdownBridgeWithoutAnimationFrames() async {
        let loaded = expectation(description: "test WebView loaded")
        let navigationProbe = FinalizedMarkdownNavigationProbe {
            loaded.fulfill()
        }
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = navigationProbe
        webView.loadHTMLString("""
        <!doctype html>
        <body></body>
        <script>
          window.requestAnimationFrame = () => 1;
          window.WeiBeiCompactPreviewHeight = 137;
          window.WeiBeiEditor = {
            finishStreamingMarkdown(markdown) {
              document.body.dataset.finalizedMarkdown = markdown;
              return true;
            }
          };
        </script>
        """, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 3)

        let finalized = expectation(description: "finalized Markdown became ready")
        var finalizedHeight: CGFloat?
        let preview = RichMarkdownEditorView(
            documentID: "finalized-render-check",
            markdown: .constant(""),
            command: .constant(nil),
            onSelectionChange: { _, _ in },
            onAskAgentWithSelection: { _, _ in },
            onFinalizedRenderReady: { height in
                finalizedHeight = height
                finalized.fulfill()
            }
        )
        let coordinator = preview.makeCoordinator()
        coordinator.webView = webView
        let mermaid = "```mermaid\ngraph TD\nA --> B\n```"
        coordinator.finishStreamingMarkdown(mermaid)

        await fulfillment(of: [finalized], timeout: 3)
        XCTAssertEqual(finalizedHeight, 137)

        let markdownRead = expectation(description: "finalized Markdown reached the WebView")
        var finalizedMarkdown: String?
        webView.evaluateJavaScript("document.body.dataset.finalizedMarkdown") { value, error in
            XCTAssertNil(error)
            finalizedMarkdown = value as? String
            markdownRead.fulfill()
        }
        await fulfillment(of: [markdownRead], timeout: 3)
        XCTAssertEqual(finalizedMarkdown, mermaid)

        let failureInstalled = expectation(description: "failed finalizer installed")
        webView.evaluateJavaScript(
            "window.WeiBeiEditor.finishStreamingMarkdown = () => false"
        ) { _, error in
            XCTAssertNil(error)
            failureInstalled.fulfill()
        }
        await fulfillment(of: [failureInstalled], timeout: 3)

        let renderFailed = expectation(description: "failed finalizer rejected")
        var didUnexpectedlyBecomeReady = false
        coordinator.onFinalizedRenderReady = { _ in
            didUnexpectedlyBecomeReady = true
        }
        coordinator.onRenderFailure = {
            renderFailed.fulfill()
        }
        coordinator.finishStreamingMarkdown(mermaid)
        await fulfillment(of: [renderFailed], timeout: 3)
        XCTAssertFalse(didUnexpectedlyBecomeReady)

        let successRestored = expectation(description: "successful finalizer restored")
        webView.evaluateJavaScript(
            "window.WeiBeiEditor.finishStreamingMarkdown = () => true"
        ) { _, error in
            XCTAssertNil(error)
            successRestored.fulfill()
        }
        await fulfillment(of: [successRestored], timeout: 3)

        var staleDocumentBecameReady = false
        coordinator.documentID = "original-document"
        coordinator.onFinalizedRenderReady = { _ in
            staleDocumentBecameReady = true
        }
        coordinator.finishStreamingMarkdown(mermaid)
        coordinator.documentID = "replacement-document"

        let staleCompletionBarrier = expectation(description: "stale completion drained")
        webView.evaluateJavaScript("true") { _, error in
            XCTAssertNil(error)
            staleCompletionBarrier.fulfill()
        }
        await fulfillment(of: [staleCompletionBarrier], timeout: 3)
        await Task.yield()
        XCTAssertFalse(staleDocumentBecameReady)
        withExtendedLifetime(navigationProbe) {}
    }
}

private final class FinalizedMarkdownNavigationProbe: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
