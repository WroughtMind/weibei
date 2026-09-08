import AppKit
import WebKit

/// Uses a hidden, isolated window and native text input; never activates the user's desktop.
final class NativeSelectionWritingHarness: NSObject, WKScriptMessageHandler {
    private var done = false
    private var web: WKWebView!
    private var window: NSWindow!

    func run() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(self, name: "editorReady")
        config.userContentController.add(self, name: "nativeInput")
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resources = root.appendingPathComponent("Sources/WeiBei/Resources/Editor")
        let selectionRuntime = try! String(contentsOf: resources.appendingPathComponent("selection-runtime.js"), encoding: .utf8)
        config.userContentController.addUserScript(WKUserScript(source: selectionRuntime + """
        window.initialMarkdown = '';
        window.weiBeiMarkdownEditable = true;
        window.weiBeiEditorCheckMode = true;
        window.selectionEvents = [];
        window.remarkEvents = [];
        window.askEvents = [];
        window.webkit.messageHandlers.selectionChanged = { postMessage: body => window.selectionEvents.push(body) };
        window.webkit.messageHandlers.remarkMark = { postMessage: body => window.remarkEvents.push(body) };
        window.webkit.messageHandlers.selectionAskMark = { postMessage: body => window.askEvents.push(body) };
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 960, height: 720), configuration: config)
        window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = web
        window.makeFirstResponder(web)
        web.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
        let deadline = Date().addingTimeInterval(60)
        while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        expect(done, "native selection/writing check timed out")
        config.userContentController.removeAllScriptMessageHandlers()
        print("Native selection and writing check passed")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "nativeInput", let body = message.body as? [String: Any] {
            if body["operation"] as? String == "checkpoint" { print("native-check: \(body["text"] ?? "")"); fflush(stdout); return }
            if body["operation"] as? String == "click", let x = body["x"] as? Double, let y = body["y"] as? Double {
                let point = NSPoint(x: x, y: web.isFlipped ? y : web.bounds.height - y)
                let location = web.convert(point, to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                    if type == .leftMouseDown { web.mouseDown(with: event) }
                    else { web.mouseUp(with: event) }
                }
                return
            }
            let text = body["text"] as? String ?? ""
            if body["operation"] as? String == "key", let keyCode = body["keyCode"] as? UInt16 {
                let modifiers: NSEvent.ModifierFlags = body["shift"] as? Bool == true ? .shift : []
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: keyCode)!
                web.keyDown(with: event)
                return
            }
            guard let client = web.inputContext?.client else { expect(false, "native text input unavailable"); return }
            let replacement = NSRange(location: NSNotFound, length: 0)
            if body["operation"] as? String == "marked" {
                client.setMarkedText(text, selectedRange: NSRange(location: 0, length: text.utf16.count), replacementRange: replacement)
            } else {
                client.insertText(text, replacementRange: replacement)
            }
            return
        }
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/WebEditor/test/native-selection-writing.js")
        let script = try! String(contentsOf: path, encoding: .utf8)
        web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            if case .failure(let error) = result { expect(false, "native selection/writing check: \(error)") }
            self.done = true
        }
    }
}
