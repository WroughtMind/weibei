import Foundation
import SwiftUI
import WebKit
import XCTest
@testable import WeiBei
import WeiBeiCore

final class RichMarkdownEditorBridgeTests: XCTestCase {
    @MainActor
    func testContentCommandsBeyondOldLimitAwaitAcknowledgement() async throws {
        let allApplied = expectation(description: "all content commands applied")
        let fixture = await makeCommandBridge { name in
            if name == "allApplied" { allApplied.fulfill() }
        }

        for index in 0..<18 {
            fixture.enqueue(NoteEditorCommand(kind: .insertMarkdown, markdown: "内容\(index)"))
        }
        fixture.start()
        await fulfillment(of: [allApplied], timeout: 3)
        let applied = try await fixture.appliedMarkdown()
        XCTAssertEqual(applied, (0..<18).map { "内容\($0)" })
    }

    @MainActor
    func testRejectedContentKeepsDispatchDocumentAndRetries() async throws {
        var rejectedCommand: NoteEditorCommand?
        var rejectedDocumentID: String?
        let rejected = expectation(description: "rejected content remained recoverable")
        let retried = expectation(description: "rejected content applied after retry")
        let fixture = await makeCommandBridge(onRejected: { documentID, command in
            rejectedDocumentID = documentID
            rejectedCommand = command
            rejected.fulfill()
        }, onProbe: { name in
            if name == "retried" { retried.fulfill() }
        })

        fixture.enqueue(NoteEditorCommand(kind: .replaceSelection, markdown: "保留我"))
        fixture.start()
        await fulfillment(of: [rejected], timeout: 3)
        let recoverable = try XCTUnwrap(rejectedCommand)
        XCTAssertEqual(rejectedDocumentID, "note-a")
        XCTAssertEqual(recoverable.markdown, "保留我")

        try await fixture.allowRejectedContent()
        fixture.enqueue(recoverable)
        await fulfillment(of: [retried], timeout: 3)
        let afterRetry = try await fixture.appliedMarkdown()
        XCTAssertEqual(afterRetry.filter { $0 == "保留我" }.count, 1)
    }

    @MainActor
    private func makeCommandBridge(
        onRejected: @escaping (String, NoteEditorCommand) -> Void = { _, _ in },
        onProbe: @escaping (String) -> Void
    ) async -> EditorCommandBridgeFixture {
        let loaded = expectation(description: "command bridge loaded")
        let fixture = EditorCommandBridgeFixture(
            onLoaded: { loaded.fulfill() },
            onRejected: onRejected,
            onProbe: onProbe
        )
        await fulfillment(of: [loaded], timeout: 3)
        return fixture
    }

    @MainActor
    func testExecutedCommandDoesNotClearNewerCommand() async {
        var command: NoteEditorCommand? = NoteEditorCommand(kind: .selectionCommand, markdown: "bold")
        let editor = RichMarkdownEditorView(
            documentID: "note-a",
            markdown: "alpha",
            command: Binding(get: { command }, set: { command = $0 }),
            editingSession: NoteEditingSession(documentID: "note-a"),
            onSelectionChange: { _, _ in },
            onAskAgentWithSelection: { _, _ in }
        )
        let coordinator = editor.makeCoordinator()
        coordinator.isReady = true
        coordinator.runPendingCommandIfReady()

        let newer = NoteEditorCommand(kind: .selectionCommand, markdown: "italic")
        command = newer
        let settled = expectation(description: "the previous command cleanup ran")
        DispatchQueue.main.async { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 1)

        XCTAssertEqual(command?.id, newer.id)
    }

    @MainActor
    func testV2SnapshotUsesSingleDispatchEntry() async throws {
        let loaded = expectation(description: "test WebView loaded")
        let navigationProbe = FinalizedMarkdownNavigationProbe { loaded.fulfill() }
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = navigationProbe
        webView.loadHTMLString("""
        <!doctype html>
        <body></body>
        <script>
          window.WeiBeiEditor = {
            dispatchCommand(command) {
              document.body.dataset.command = JSON.stringify(command);
              return true;
            }
          };
        </script>
        """, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 3)

        let session = NoteEditingSession(documentID: "note-a", initialRevision: 7)
        let editor = RichMarkdownEditorView(
            documentID: "note-a",
            markdown: "# Note",
            command: .constant(nil),
            editingSession: session,
            onSelectionChange: { _, _ in },
            onAskAgentWithSelection: { _, _ in }
        )
        let coordinator = editor.makeCoordinator()
        coordinator.webView = webView
        coordinator.bindEditingSession()

        XCTAssertTrue(session.requestSnapshot())
        _ = try await webView.evaluateJavaScript("true")
        let rawValue = try await webView.evaluateJavaScript("document.body.dataset.command")
        let raw = try XCTUnwrap(rawValue as? String)
        let command = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
        )
        XCTAssertEqual(command["protocolVersion"] as? Int, 2)
        XCTAssertEqual(command["type"] as? String, "requestSnapshot")
        XCTAssertEqual(command["documentID"] as? String, "note-a")
        XCTAssertEqual(command["documentGeneration"] as? Int, 1)
        XCTAssertEqual(command["minimumRevision"] as? Int, 7)
        XCTAssertNotNil(command["requestID"] as? String)

        coordinator.unbindEditingSession()
        withExtendedLifetime(navigationProbe) {}
    }

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
            markdown: "",
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

@MainActor
private final class EditorCommandBridgeFixture {
    private final class CommandBox {
        var value: NoteEditorCommand?
    }

    private let commandBox: CommandBox
    private let completionProbe: EditorCommandQueueProbe
    private let navigationProbe: FinalizedMarkdownNavigationProbe
    private let coordinator: RichMarkdownEditorView.Coordinator
    private let webView: WKWebView

    init(
        onLoaded: @escaping () -> Void,
        onRejected: @escaping (String, NoteEditorCommand) -> Void,
        onProbe: @escaping (String) -> Void
    ) {
        let commandBox = CommandBox()
        self.commandBox = commandBox
        let editor = RichMarkdownEditorView(
            documentID: "note-a",
            markdown: "",
            command: Binding(
                get: { commandBox.value },
                set: { commandBox.value = $0 }
            ),
            editingSession: NoteEditingSession(documentID: "note-a"),
            onSelectionChange: { _, _ in },
            onAskAgentWithSelection: { _, _ in },
            onCommandRejected: onRejected
        )
        let coordinator = editor.makeCoordinator()
        self.coordinator = coordinator
        let completionProbe = EditorCommandQueueProbe(receive: onProbe)
        self.completionProbe = completionProbe
        let navigationProbe = FinalizedMarkdownNavigationProbe(onFinish: onLoaded)
        self.navigationProbe = navigationProbe

        let controller = WKUserContentController()
        controller.add(coordinator, name: "commandApplied")
        controller.add(coordinator, name: "commandRejected")
        controller.add(completionProbe, name: "queueProbe")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        webView.navigationDelegate = navigationProbe
        webView.loadHTMLString(Self.page, baseURL: nil)
        coordinator.webView = webView
    }

    func enqueue(_ command: NoteEditorCommand) {
        commandBox.value = command
        coordinator.runPendingCommandIfReady()
    }

    func start() {
        coordinator.isReady = true
        coordinator.runPendingCommandIfReady()
    }

    func allowRejectedContent() async throws {
        _ = try await webView.evaluateJavaScript(
            "window.WeiBeiEditor.allowRejectedContent()"
        )
    }

    func appliedMarkdown() async throws -> [String] {
        let value = try await webView.evaluateJavaScript(
            "window.WeiBeiEditor.appliedMarkdown()"
        )
        return try XCTUnwrap(value as? [String])
    }

    private static let page = """
    <!doctype html>
    <body></body>
    <script>
      const appliedIDs = new Set();
      const appliedMarkdown = [];
      let rejectedMarkdown = "保留我";
      const replyApplied = command => {
        window.webkit.messageHandlers.commandApplied.postMessage({
          protocolVersion: 2,
          commandID: command.commandID,
          documentID: "note-a",
          documentGeneration: 1,
          revision: 0
        });
      };
      window.WeiBeiEditor = {
        dispatchCommand(command) {
          const markdown = command.payload.markdown;
          if (markdown === rejectedMarkdown) return false;
          if (!appliedIDs.has(command.commandID)) {
            appliedIDs.add(command.commandID);
            appliedMarkdown.push(markdown);
          }
          replyApplied(command);
          if (appliedMarkdown.length === 18) {
            window.webkit.messageHandlers.queueProbe.postMessage("allApplied");
          } else if (markdown === "保留我") {
            window.webkit.messageHandlers.queueProbe.postMessage("retried");
          }
          return true;
        },
        allowRejectedContent() { rejectedMarkdown = null; return true; },
        appliedMarkdown() { return appliedMarkdown; }
      };
    </script>
    """
}

private final class EditorCommandQueueProbe: NSObject, WKScriptMessageHandler {
    private let receive: (String) -> Void

    init(receive: @escaping (String) -> Void) {
        self.receive = receive
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if let name = message.body as? String {
            receive(name)
        }
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
