import SwiftUI
import WebKit
import WeiBeiCore

fileprivate final class MarkdownImageSchemeHandler: NSObject, WKURLSchemeHandler {
    var markdownBaseURLString = ""
    var attachmentDirectory: URL?

    func update(markdownBaseURLString: String, attachmentDirectory: URL?) {
        self.markdownBaseURLString = markdownBaseURLString
        self.attachmentDirectory = attachmentDirectory
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = fileURL(from: requestURL),
              isAllowed(fileURL) else {
            urlSchemeTask.didFailWithError(NSError(
                domain: "WeiBei.MarkdownImageScheme",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "图片无法读取"]
            ))
            return
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            sendMissingImage(for: requestURL, task: urlSchemeTask)
            return
        }

        let response = URLResponse(
            url: requestURL,
            mimeType: mimeType(for: fileURL),
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func fileURL(from requestURL: URL) -> URL? {
        guard let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "src" })?.value,
              let url = URL(string: value),
              url.isFileURL else {
            return nil
        }
        return url.standardizedFileURL
    }

    private func isAllowed(_ fileURL: URL) -> Bool {
        allowedRoots().contains { root in
            let rootPath = root.standardizedFileURL.path
            let filePath = fileURL.standardizedFileURL.path
            let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
            return filePath == rootPath || filePath.hasPrefix(prefix)
        }
    }

    private func allowedRoots() -> [URL] {
        var roots: [URL] = []
        if let baseURL = URL(string: markdownBaseURLString), baseURL.isFileURL {
            roots.append(baseURL)
        }
        if let attachmentDirectory {
            roots.append(attachmentDirectory)
        }
        return roots
    }

    private func sendMissingImage(for requestURL: URL, task urlSchemeTask: WKURLSchemeTask) {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="156" height="34" viewBox="0 0 156 34">
          <rect width="156" height="34" rx="3" fill="#efe6d8"/>
          <path d="M18 22l5-6 4 4 3-3 6 5" fill="none" stroke="#9f3b2f" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
          <rect x="17" y="11" width="20" height="14" rx="2" fill="none" stroke="#9f3b2f" stroke-width="1.2"/>
          <text x="48" y="22" fill="#6b5148" font-family="-apple-system, BlinkMacSystemFont, 'Songti SC', serif" font-size="13">图片未找到</text>
        </svg>
        """
        let data = Data(svg.utf8)
        let response = URLResponse(
            url: requestURL,
            mimeType: "image/svg+xml",
            expectedContentLength: data.count,
            textEncodingName: "utf-8"
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "svg": return "image/svg+xml"
        default: return MarkdownAttachmentStore.mimeType(forFileExtension: fileURL.pathExtension)
        }
    }
}

final class MarkdownWebView: WKWebView {
    var pasteImageFromClipboard: (() -> Bool)?
    var handleAppShortcut: ((String, NSEvent.ModifierFlags) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v",
           pasteImageFromClipboard?() == true {
            return
        }
        if let key = event.charactersIgnoringModifiers?.lowercased(),
           handleAppShortcut?(key, event.modifierFlags.intersection(Self.shortcutModifierMask)) == true {
            return
        }
        super.keyDown(with: event)
    }

    private static let shortcutModifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
}

struct RichMarkdownEditorView: NSViewRepresentable {
    var documentID = ""
    @Binding var markdown: String
    @Binding var command: NoteEditorCommand?
    var isEditable = true
    var isFocused = false
    var focusRequest = 0
    var markdownBaseURL: URL?
    var attachmentDirectory: URL?
    var searchQuery = ""
    var onSelectionChange: (String, CGPoint?) -> Void
    var onAskAgentWithSelection: (String, CGPoint?) -> Void
    var onWikiLink: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    private static let localImageScheme = "weibeiimage"

    func makeCoordinator() -> Coordinator {
        Coordinator(
            documentID: documentID,
            markdown: $markdown,
            command: $command,
            isEditable: isEditable,
            isFocused: isFocused,
            focusRequest: focusRequest,
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory,
            searchQuery: searchQuery,
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onAskAgentWithSelection,
            onWikiLink: onWikiLink,
            onAppShortcut: onAppShortcut
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        context.coordinator.imageSchemeHandler.update(
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory
        )
        configuration.setURLSchemeHandler(context.coordinator.imageSchemeHandler, forURLScheme: Self.localImageScheme)
        for name in Self.scriptMessageNames {
            controller.add(context.coordinator, name: name)
        }
        controller.addUserScript(WKUserScript(
            source: """
            window.initialMarkdown = \(Self.json(markdown));
            window.weiBeiMarkdownEditable = \(isEditable ? "true" : "false");
            window.weiBeiMarkdownBaseURL = \(Self.json(markdownBaseURL?.absoluteString ?? ""));
            window.weiBeiLocalImageScheme = \(Self.json(Self.localImageScheme));
            (() => {
              const appShortcutKey = (event) => {
                if (/^Digit[0-9]$/.test(event.code)) return event.code.slice(5);
                if (/^Key[A-Z]$/.test(event.code)) return event.code.slice(3).toLowerCase();
                return String(event.key || "").toLowerCase();
              };
              const isWeiBeiShortcut = (key, event) => {
                const command = event.metaKey;
                const option = event.altKey;
                const control = event.ctrlKey;
                const shift = event.shiftKey;
                if (control && option && !command && !shift) {
                  return ["0", "1", "2", "3", "4"].includes(key);
                }
                if (command && option && !control && !shift) {
                  return ["1", "2", "3", "a", "n", "r"].includes(key);
                }
                if (control && command && !option && !shift) {
                  return ["1", "2", "3", "4"].includes(key);
                }
                if (command && shift && !option && !control) {
                  return ["a", "r", "e", "c"].includes(key);
                }
                if (command && !option && !control && !shift) {
                  return ["1", "2", "3", "4", "b", "j", "k", "f"].includes(key);
                }
                return false;
              };
              window.addEventListener("keydown", (event) => {
                const key = appShortcutKey(event);
                if (!isWeiBeiShortcut(key, event)) return;
                event.preventDefault();
                event.stopPropagation();
                window.webkit?.messageHandlers?.appShortcut?.postMessage({
                  key,
                  command: event.metaKey,
                  option: event.altKey,
                  control: event.ctrlKey,
                  shift: event.shiftKey
                });
              }, true);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller

        let view = MarkdownWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.pasteImageFromClipboard = { [weak coordinator = context.coordinator] in
            coordinator?.pasteImageFromClipboard() ?? false
        }
        view.handleAppShortcut = { [weak coordinator = context.coordinator] key, modifiers in
            coordinator?.handleAppShortcut(key: key, modifiers: modifiers) ?? false
        }
        context.coordinator.webView = view
        if let url = Bundle.module.url(forResource: "index", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.loadHTMLString("<p>编辑器资源缺失。</p>", baseURL: nil)
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.markdown = $markdown
        context.coordinator.command = $command
        if context.coordinator.documentID != documentID {
            context.coordinator.documentID = documentID
        }
        context.coordinator.attachmentDirectory = attachmentDirectory
        context.coordinator.imageSchemeHandler.update(
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory
        )
        context.coordinator.searchQuery = searchQuery
        context.coordinator.isFocused = isFocused
        context.coordinator.focusRequest = focusRequest
        context.coordinator.onWikiLink = onWikiLink
        context.coordinator.onAppShortcut = onAppShortcut
        let nextBaseURL = markdownBaseURL?.absoluteString ?? ""
        if context.coordinator.markdownBaseURLString != nextBaseURL {
            context.coordinator.markdownBaseURLString = nextBaseURL
            context.coordinator.setMarkdownBaseURL(nextBaseURL)
        }
        if context.coordinator.isEditable != isEditable {
            context.coordinator.isEditable = isEditable
            context.coordinator.setEditable(isEditable)
        }
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onAskAgentWithSelection = onAskAgentWithSelection

        if context.coordinator.isReady, context.coordinator.webMarkdown != markdown {
            context.coordinator.setMarkdown(markdown)
        }

        if context.coordinator.isReady {
            context.coordinator.applySearch()
            context.coordinator.applyFocus()
        }

        context.coordinator.runPendingCommandIfReady()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        for name in scriptMessageNames {
            view.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    private static let scriptMessageNames = [
        "editorReady",
        "markdownChanged",
        "selectionChanged",
        "askAgentWithSelection",
        "wikiLinkActivated",
        "imageAttachmentRequested",
        "appShortcut"
    ]

    private static func json(_ value: String) -> String {
        let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var markdown: Binding<String>
        var command: Binding<NoteEditorCommand?>
        var documentID: String
        var onSelectionChange: (String, CGPoint?) -> Void
        var onAskAgentWithSelection: (String, CGPoint?) -> Void
        var onWikiLink: (String) -> Void
        var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool
        weak var webView: WKWebView?
        var isReady = false
        var isEditable: Bool
        var isFocused: Bool
        var focusRequest: Int
        var markdownBaseURLString: String
        var attachmentDirectory: URL?
        var searchQuery: String
        var webMarkdown = ""
        var pendingExternalMarkdown: String?
        var lastCommandID: UUID?
        fileprivate let imageSchemeHandler = MarkdownImageSchemeHandler()
        private var lastAppliedSearchQuery = ""
        private var lastAppliedFocusRequest = -1

        init(
            documentID: String,
            markdown: Binding<String>,
            command: Binding<NoteEditorCommand?>,
            isEditable: Bool,
            isFocused: Bool,
            focusRequest: Int,
            markdownBaseURLString: String,
            attachmentDirectory: URL?,
            searchQuery: String,
            onSelectionChange: @escaping (String, CGPoint?) -> Void,
            onAskAgentWithSelection: @escaping (String, CGPoint?) -> Void,
            onWikiLink: @escaping (String) -> Void,
            onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool
        ) {
            self.documentID = documentID
            self.markdown = markdown
            self.command = command
            self.isEditable = isEditable
            self.isFocused = isFocused
            self.focusRequest = focusRequest
            self.markdownBaseURLString = markdownBaseURLString
            self.attachmentDirectory = attachmentDirectory
            self.searchQuery = searchQuery
            self.onSelectionChange = onSelectionChange
            self.onAskAgentWithSelection = onAskAgentWithSelection
            self.onWikiLink = onWikiLink
            self.onAppShortcut = onAppShortcut
        }

        func handleAppShortcut(key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
            onAppShortcut(key, modifiers)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "editorReady":
                isReady = true
                if let text = (message.body as? [String: Any])?["markdown"] as? String {
                    webMarkdown = text
                    if markdown.wrappedValue == text {
                        markdown.wrappedValue = text
                    } else {
                        setMarkdown(markdown.wrappedValue)
                    }
                } else {
                    webMarkdown = markdown.wrappedValue
                }
                applySearch()
                applyFocus()
                runPendingCommandIfReady()
            case "markdownChanged":
                guard let text = (message.body as? [String: Any])?["markdown"] as? String else { return }
                if let pendingExternalMarkdown {
                    guard text == pendingExternalMarkdown else { return }
                    self.pendingExternalMarkdown = nil
                }
                if text == webMarkdown, markdown.wrappedValue != webMarkdown {
                    setMarkdown(markdown.wrappedValue)
                    return
                }
                webMarkdown = text
                markdown.wrappedValue = text
            case "selectionChanged":
                guard let body = message.body as? [String: Any],
                      let text = body["text"] as? String else { return }
                onSelectionChange(text, anchor(from: body["rect"] as? [String: Any]))
            case "askAgentWithSelection":
                guard let body = message.body as? [String: Any] else { return }
                let text = body["text"] as? String ?? ""
                onAskAgentWithSelection(text, anchor(from: body["rect"] as? [String: Any]))
            case "wikiLinkActivated":
                guard let body = message.body as? [String: Any],
                      let title = body["title"] as? String else { return }
                onWikiLink(title)
            case "imageAttachmentRequested":
                guard isEditable,
                      let body = message.body as? [String: Any],
                      let id = body["id"] as? String else { return }
                if let attachment = saveImageAttachment(from: body) {
                    evaluate("""
                    window.WeiBeiEditor?.resolveAttachment(
                      \(Self.json(id)),
                      \(Self.json(attachment.src)),
                      \(Self.json(attachment.alt))
                    )
                    """)
                } else {
                    evaluate("window.WeiBeiEditor?.rejectAttachment(\(Self.json(id)), \"图片无法写入本地附件目录\")")
                }
            case "appShortcut":
                guard let body = message.body as? [String: Any],
                      let key = body["key"] as? String else { return }
                _ = handleAppShortcut(key: key, modifiers: modifiers(from: body))
            default:
                break
            }
        }

        private func modifiers(from body: [String: Any]) -> NSEvent.ModifierFlags {
            var modifiers: NSEvent.ModifierFlags = []
            if body["command"] as? Bool == true {
                modifiers.insert(.command)
            }
            if body["option"] as? Bool == true {
                modifiers.insert(.option)
            }
            if body["control"] as? Bool == true {
                modifiers.insert(.control)
            }
            if body["shift"] as? Bool == true {
                modifiers.insert(.shift)
            }
            return modifiers
        }

        func setMarkdown(_ text: String) {
            pendingExternalMarkdown = text
            webMarkdown = text
            evaluate("window.WeiBeiEditor?.setMarkdown(\(Self.json(text)))")
        }

        func setEditable(_ editable: Bool) {
            evaluate("window.WeiBeiEditor?.setEditable(\(editable ? "true" : "false"))")
        }

        func setMarkdownBaseURL(_ url: String) {
            evaluate("window.WeiBeiEditor?.setMarkdownBaseURL(\(Self.json(url)))")
        }

        func run(_ command: NoteEditorCommand) {
            switch command.kind {
            case .replaceSelection:
                evaluate("window.WeiBeiEditor?.replaceSelection(\(Self.json(command.markdown)))")
            case .applyAgentPatch:
                evaluate("window.WeiBeiEditor?.applyAgentPatch(\(Self.json(command.markdown)))")
            case .insertMarkdown:
                evaluate("window.WeiBeiEditor?.insertMarkdown(\(Self.json(command.markdown)))")
            }
        }

        func runPendingCommandIfReady() {
            guard isReady,
                  let pendingCommand = command.wrappedValue,
                  lastCommandID != pendingCommand.id else { return }
            lastCommandID = pendingCommand.id
            run(pendingCommand)
            DispatchQueue.main.async {
                self.command.wrappedValue = nil
            }
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script)
        }

        func applySearch() {
            let query = ReaderSearch.cleaned(searchQuery)
            guard query != lastAppliedSearchQuery else { return }
            lastAppliedSearchQuery = query
            evaluate("""
            (() => {
              const query = \(Self.json(query));
              const selection = window.getSelection();
              selection?.removeAllRanges();
              if (!query) return false;
              return window.find(query, false, false, true, false, true, false);
            })();
            """)
        }

        func applyFocus() {
            guard isFocused, focusRequest != lastAppliedFocusRequest else { return }
            lastAppliedFocusRequest = focusRequest
            webView?.window?.makeFirstResponder(webView)
            evaluate("document.querySelector('.ProseMirror')?.focus()")
        }

        func pasteImageFromClipboard() -> Bool {
            guard isEditable,
                  let image = NSImage(pasteboard: .general),
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else {
                return false
            }

            let body: [String: Any] = [
                "dataURL": "data:image/png;base64,\(data.base64EncodedString())",
                "name": "pasted-image.png",
                "mime": "image/png"
            ]
            guard let attachment = saveImageAttachment(from: body) else { return false }
            evaluate("window.WeiBeiEditor?.insertMarkdownImage(\(Self.json(MarkdownAttachmentStore.markdownImage(for: attachment))))")
            return true
        }

        private func saveImageAttachment(from body: [String: Any]) -> MarkdownAttachment? {
            guard let attachmentDirectory,
                  let dataURL = body["dataURL"] as? String else { return nil }
            let originalName = (body["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mime = body["mime"] as? String ?? ""
            return try? MarkdownAttachmentStore.save(
                dataURL: dataURL,
                originalName: originalName,
                mime: mime,
                attachmentDirectory: attachmentDirectory,
                markdownBaseURLString: markdownBaseURLString
            )
        }

        private func anchor(from rect: [String: Any]?) -> CGPoint? {
            guard let view = webView,
                  let window = view.window,
                  let contentView = window.contentView,
                  let rect,
                  let x = rect["x"] as? Double,
                  let y = rect["y"] as? Double else {
                return nil
            }
            let localY = view.isFlipped ? y : Double(view.bounds.height) - y
            let localPoint = CGPoint(x: x, y: localY)
            let windowPoint = view.convert(localPoint, to: nil)
            let contentPoint = contentView.convert(windowPoint, from: nil)
            let contentY = SelectionAnchorCoordinate.y(
                Double(contentPoint.y),
                contentHeight: Double(contentView.bounds.height),
                contentViewIsFlipped: contentView.isFlipped
            )
            return CGPoint(x: contentPoint.x, y: contentY)
        }

        private static func json(_ value: String) -> String {
            let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }

    }
}
