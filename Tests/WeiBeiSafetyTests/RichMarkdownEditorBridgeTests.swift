import SwiftUI
import WebKit
import XCTest
@testable import WeiBei

final class RichMarkdownEditorBridgeTests: XCTestCase {
    @MainActor
    func testFinalizedMarkdownBridgeWithoutAnimationFrames() async throws {
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

        let finalizedMarkdown = try await webView.evaluateJavaScript(
            "document.body.dataset.finalizedMarkdown"
        ) as? String
        XCTAssertEqual(finalizedMarkdown, mermaid)

        _ = try await webView.evaluateJavaScript("""
        (() => {
          window.WeiBeiEditor.finishStreamingMarkdown = () => false;
          return true;
        })()
        """)

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

        _ = try await webView.evaluateJavaScript("""
        (() => {
          window.WeiBeiEditor.finishStreamingMarkdown = () => true;
          return true;
        })()
        """)

        var staleDocumentBecameReady = false
        coordinator.documentID = "original-document"
        coordinator.onFinalizedRenderReady = { _ in
            staleDocumentBecameReady = true
        }
        coordinator.finishStreamingMarkdown(mermaid)
        coordinator.documentID = "replacement-document"

        _ = try await webView.evaluateJavaScript("true")
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
