import SwiftUI
import UniformTypeIdentifiers
import WebKit
import WeiBeiCore

fileprivate final class MarkdownImageSchemeHandler: NSObject, WKURLSchemeHandler {
    var markdownBaseURLString = ""
    var attachmentDirectory: URL?
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese

    func update(markdownBaseURLString: String, attachmentDirectory: URL?, appearanceMode: WeiBeiAppearanceMode, interfaceLanguage: WeiBeiInterfaceLanguage) {
        self.markdownBaseURLString = markdownBaseURLString
        self.attachmentDirectory = attachmentDirectory
        self.appearanceMode = appearanceMode
        self.interfaceLanguage = interfaceLanguage
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = fileURL(from: requestURL),
              isAllowed(fileURL) else {
            urlSchemeTask.didFailWithError(NSError(
                domain: "WeiBei.MarkdownImageScheme",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: interfaceLanguage.text("图片无法读取", "Image could not be read")]
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
        let colors = missingImageColors
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="156" height="34" viewBox="0 0 156 34">
          <rect width="156" height="34" rx="3" fill="\(colors.background)"/>
          <path d="M18 22l5-6 4 4 3-3 6 5" fill="none" stroke="\(colors.accent)" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
          <rect x="17" y="11" width="20" height="14" rx="2" fill="none" stroke="\(colors.accent)" stroke-width="1.2"/>
          <text x="48" y="22" fill="\(colors.text)" font-family="-apple-system, BlinkMacSystemFont, 'Songti SC', serif" font-size="13">\(interfaceLanguage.text("图片未找到", "Image missing"))</text>
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

    private var missingImageColors: (background: String, accent: String, text: String) {
        switch appearanceMode {
        case .paper:
            return ("#efe6d8", "#9f3b2f", "#6b5148")
        case .xuan:
            return ("#f2eee6", "#9a3a2e", "#5f5a52")
        case .inkstone:
            return ("#151515", "#a6362b", "#d7cbb0")
        case .stele:
            return ("#1e2228", "#b04034", "#d2d6dc")
        }
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
    var passesVerticalScrollToSuperview = false {
        didSet { updateScrollWheelMonitor() }
    }
    private var scrollWheelMonitor: Any?

    deinit {
        removeScrollWheelMonitor()
    }

    /// Compact agent previews must not steal keyboard focus from the composer.
    override var acceptsFirstResponder: Bool {
        passesVerticalScrollToSuperview ? false : super.acceptsFirstResponder
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScrollWheelMonitor()
    }

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

    override func scrollWheel(with event: NSEvent) {
        guard passesVerticalScrollToSuperview,
              abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
            super.scrollWheel(with: event)
            return
        }

        if !forwardVerticalScroll(event) {
            super.scrollWheel(with: event)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passesVerticalScrollToSuperview, NSApp.currentEvent?.type == .scrollWheel {
            return nil
        }
        return super.hitTest(point)
    }

    private func nearestSuperviewScrollView() -> NSScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    private func updateScrollWheelMonitor() {
        guard passesVerticalScrollToSuperview, window != nil else {
            removeScrollWheelMonitor()
            return
        }
        guard scrollWheelMonitor == nil else { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.shouldForwardVerticalScroll(event) else {
                return event
            }
            return self.forwardVerticalScroll(event) ? nil : event
        }
    }

    private func removeScrollWheelMonitor() {
        if let scrollWheelMonitor {
            NSEvent.removeMonitor(scrollWheelMonitor)
            self.scrollWheelMonitor = nil
        }
    }

    private func shouldForwardVerticalScroll(_ event: NSEvent) -> Bool {
        guard passesVerticalScrollToSuperview,
              event.window === window,
              abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else {
            return false
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        return bounds.contains(localPoint)
    }

    @discardableResult
    private func forwardVerticalScroll(_ event: NSEvent) -> Bool {
        guard let outerScrollView = nearestSuperviewScrollView() else { return false }
        outerScrollView.scrollWheel(with: event)
        return true
    }

    @discardableResult
    func scrollOuterSuperview(deltaY: CGFloat) -> Bool {
        guard passesVerticalScrollToSuperview,
              let outerScrollView = nearestSuperviewScrollView(),
              let documentView = outerScrollView.documentView else { return false }
        let clipView = outerScrollView.contentView
        let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
        let direction: CGFloat = documentView.isFlipped ? 1 : -1
        let nextY = min(max(clipView.bounds.origin.y + deltaY * direction, 0), maxY)
        guard abs(nextY - clipView.bounds.origin.y) > 0.01 else { return false }
        clipView.scroll(to: CGPoint(x: clipView.bounds.origin.x, y: nextY))
        outerScrollView.reflectScrolledClipView(clipView)
        return true
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
    var appearanceMode: WeiBeiAppearanceMode = .paper
    var interfaceLanguage: WeiBeiInterfaceLanguage = .chinese
    var isCompactPreview = false
    var onSelectionChange: (String, CGPoint?) -> Void
    var onAskAgentWithSelection: (String, CGPoint?) -> Void
    var onContentHeightChange: (CGFloat) -> Void = { _ in }
    var onActiveHeadingChange: (Int?) -> Void = { _ in }
    var onWikiLink: (String) -> Void = { _ in }
    var onSourceReference: (String) -> Void = { _ in }
    var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool = { _, _ in false }
    /// JSON array of `{id,text}` for selection-ask underline marks (read-only surfaces).
    var selectionAskMarks: String = "[]"
    var onSelectionAskMark: (String) -> Void = { _ in }
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
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage,
            selectionAskMarks: selectionAskMarks,
            onContentHeightChange: onContentHeightChange,
            onActiveHeadingChange: onActiveHeadingChange,
            onSelectionChange: onSelectionChange,
            onAskAgentWithSelection: onAskAgentWithSelection,
            onWikiLink: onWikiLink,
            onSourceReference: onSourceReference,
            onAppShortcut: onAppShortcut,
            onSelectionAskMark: onSelectionAskMark
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        context.coordinator.imageSchemeHandler.update(
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage
        )
        configuration.setURLSchemeHandler(context.coordinator.imageSchemeHandler, forURLScheme: Self.localImageScheme)
        for name in Self.scriptMessageNames {
            controller.add(context.coordinator, name: name)
        }
        controller.addUserScript(WKUserScript(
            source: """
            window.initialMarkdown = \(Self.json(markdown));
            window.weiBeiDocumentID = \(Self.json(documentID));
            window.weiBeiMarkdownEditable = \(isEditable ? "true" : "false");
            window.weiBeiMarkdownBaseURL = \(Self.json(markdownBaseURL?.absoluteString ?? ""));
            window.weiBeiLocalImageScheme = \(Self.json(Self.localImageScheme));
            window.weiBeiTheme = \(Self.json(appearanceMode.webThemeName));
            window.weiBeiInterfaceLanguage = \(Self.json(interfaceLanguage.rawValue));
            window.weiBeiMarkdownCompactPreview = \(isCompactPreview ? "true" : "false");
            document.documentElement.dataset.weibeiTheme = window.weiBeiTheme;
            document.documentElement.dataset.weibeiLanguage = window.weiBeiInterfaceLanguage;
            document.documentElement.dataset.weibeiCompactPreview = window.weiBeiMarkdownCompactPreview ? "true" : "false";
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
                  return ["1", "2", "3", "a", "n", "r", "t"].includes(key);
                }
                if (control && command && !option && !shift) {
                  return ["1", "2", "3", "4"].includes(key);
                }
                if (command && shift && !option && !control) {
                  return ["a", "r", "e", "c"].includes(key);
                }
                if (command && !option && !control && !shift) {
                  return ["1", "2", "3", "4", "[", "]", "b", "j", "k", "f"].includes(key);
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
              if (window.weiBeiMarkdownCompactPreview) {
                window.addEventListener("wheel", (event) => {
                  if (Math.abs(event.deltaY) < Math.abs(event.deltaX)) return;
                  event.preventDefault();
                  window.webkit?.messageHandlers?.compactPreviewWheel?.postMessage({
                    documentID: window.weiBeiDocumentID || "",
                    deltaY: event.deltaY
                  });
                }, { capture: true, passive: false });
              }
            })();
            """ + Self.selectionAskMarksBootstrapScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController = controller

        let view = MarkdownWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.passesVerticalScrollToSuperview = isCompactPreview
        Self.applyWebAppearance(to: view, appearanceMode: appearanceMode)
        view.pasteImageFromClipboard = { [weak coordinator = context.coordinator] in
            coordinator?.pasteImageFromClipboard() ?? false
        }
        view.handleAppShortcut = { [weak coordinator = context.coordinator] key, modifiers in
            coordinator?.handleAppShortcut(key: key, modifiers: modifiers) ?? false
        }
        context.coordinator.webView = view
        if let url = WeiBeiResources.bundle.url(forResource: "index", withExtension: "html") {
            let editorDirectory = url.deletingLastPathComponent()
            view.loadFileURL(url, allowingReadAccessTo: editorDirectory.deletingLastPathComponent())
        } else {
            view.loadHTMLString("<p>\(interfaceLanguage.text("编辑器资源缺失。", "Editor resources are missing."))</p>", baseURL: nil)
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        (view as? MarkdownWebView)?.passesVerticalScrollToSuperview = isCompactPreview
        Self.applyWebAppearance(to: view, appearanceMode: appearanceMode)
        context.coordinator.markdown = $markdown
        context.coordinator.command = $command
        if context.coordinator.documentID != documentID {
            context.coordinator.transition(toDocumentID: documentID)
        }
        context.coordinator.attachmentDirectory = attachmentDirectory
        context.coordinator.imageSchemeHandler.update(
            markdownBaseURLString: markdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: attachmentDirectory,
            appearanceMode: appearanceMode,
            interfaceLanguage: interfaceLanguage
        )
        context.coordinator.searchQuery = searchQuery
        if context.coordinator.appearanceMode != appearanceMode {
            context.coordinator.appearanceMode = appearanceMode
            if context.coordinator.isReady {
                context.coordinator.setTheme(appearanceMode)
            }
        }
        if context.coordinator.interfaceLanguage != interfaceLanguage {
            context.coordinator.interfaceLanguage = interfaceLanguage
            if context.coordinator.isReady {
                context.coordinator.setInterfaceLanguage(interfaceLanguage)
            }
        }
        context.coordinator.isFocused = isFocused
        context.coordinator.focusRequest = focusRequest
        context.coordinator.onWikiLink = onWikiLink
        context.coordinator.onSourceReference = onSourceReference
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
        context.coordinator.onContentHeightChange = onContentHeightChange
        context.coordinator.onActiveHeadingChange = onActiveHeadingChange
        context.coordinator.onSelectionAskMark = onSelectionAskMark
        context.coordinator.selectionAskMarks = selectionAskMarks

        if context.coordinator.isReady, context.coordinator.webMarkdown != markdown {
            context.coordinator.setMarkdown(markdown)
        }

        if context.coordinator.isReady {
            context.coordinator.applySearch()
            context.coordinator.applyFocus()
            context.coordinator.applySelectionAskMarks()
        }

        context.coordinator.runPendingCommandIfReady()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.invalidateDocumentRequests()
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
        "sourceReferenceActivated",
        "imageAttachmentRequested",
        "imagePickerRequested",
        "contentHeightChanged",
        "activeHeadingChanged",
        "compactPreviewWheel",
        "appShortcut",
        "selectionAskMark"
    ]

    /// CSS + apply helper for cinnabar underlines on asked selections (read-only markdown).
    private static let selectionAskMarksBootstrapScript = """
    (() => {
      if (window.WeiBeiSelectionAskMarks) return;
      const style = document.createElement("style");
      style.textContent = `
        .weibei-selection-ask-mark {
          text-decoration-line: underline;
          text-decoration-color: rgba(145, 38, 27, 0.72);
          text-decoration-thickness: 1.5px;
          text-underline-offset: 3px;
          cursor: pointer;
          border-radius: 2px;
          transition: background-color 120ms ease;
        }
        .weibei-selection-ask-mark:hover {
          background-color: rgba(145, 38, 27, 0.12);
        }
        [data-weibei-theme="inkstone"] .weibei-selection-ask-mark {
          text-decoration-color: rgba(200, 120, 100, 0.85);
        }
        [data-weibei-theme="inkstone"] .weibei-selection-ask-mark:hover {
          background-color: rgba(200, 120, 100, 0.16);
        }
      `;
      document.documentElement.appendChild(style);
      window.WeiBeiSelectionAskMarks = {
        apply: function(marks) {
          try {
            const root = document.querySelector(".ProseMirror") || document.body;
            root.querySelectorAll(".weibei-selection-ask-mark").forEach((el) => {
              const parent = el.parentNode;
              if (!parent) return;
              while (el.firstChild) parent.insertBefore(el.firstChild, el);
              parent.removeChild(el);
              parent.normalize();
            });
            if (window.weiBeiMarkdownEditable) return;
            const list = Array.isArray(marks) ? marks : [];
            list.forEach((mark) => {
              const needle = String(mark.text || "").trim();
              const id = String(mark.id || "");
              if (!needle || !id || needle.length < 4) return;
              const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
                acceptNode: function(node) {
                  if (!node.parentElement) return NodeFilter.FILTER_REJECT;
                  if (node.parentElement.closest(".weibei-selection-ask-mark, script, style")) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return node.nodeValue && node.nodeValue.indexOf(needle) >= 0
                    ? NodeFilter.FILTER_ACCEPT
                    : NodeFilter.FILTER_SKIP;
                }
              });
              const hits = [];
              while (walker.nextNode()) hits.push(walker.currentNode);
              hits.slice(0, 3).forEach((textNode) => {
                const value = textNode.nodeValue || "";
                const idx = value.indexOf(needle);
                if (idx < 0) return;
                const range = document.createRange();
                range.setStart(textNode, idx);
                range.setEnd(textNode, idx + needle.length);
                const span = document.createElement("span");
                span.className = "weibei-selection-ask-mark";
                span.dataset.threadId = id;
                span.title = "打开当时的选区问答";
                try { range.surroundContents(span); } catch (e) {}
              });
            });
            root.querySelectorAll(".weibei-selection-ask-mark").forEach((el) => {
              el.onclick = function(ev) {
                ev.preventDefault();
                ev.stopPropagation();
                const threadId = el.dataset.threadId || "";
                if (window.webkit?.messageHandlers?.selectionAskMark) {
                  window.webkit.messageHandlers.selectionAskMark.postMessage({
                    threadId,
                    text: el.textContent || "",
                    documentID: window.weiBeiDocumentID || ""
                  });
                }
              };
            });
          } catch (e) {}
        }
      };
    })();
    """

    private static func applyWebAppearance(to view: WKWebView, appearanceMode: WeiBeiAppearanceMode) {
        view.underPageBackgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)
        view.appearance = NSAppearance(named: appearanceMode.isDark ? .darkAqua : .aqua)
    }

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
        var onContentHeightChange: (CGFloat) -> Void
        var onActiveHeadingChange: (Int?) -> Void
        var onWikiLink: (String) -> Void
        var onSourceReference: (String) -> Void
        var onAppShortcut: (String, NSEvent.ModifierFlags) -> Bool
        var onSelectionAskMark: (String) -> Void
        var selectionAskMarks: String
        weak var webView: WKWebView?
        var isReady = false
        var isEditable: Bool
        var isFocused: Bool
        var focusRequest: Int
        var markdownBaseURLString: String
        var attachmentDirectory: URL?
        var searchQuery: String
        var appearanceMode: WeiBeiAppearanceMode
        var interfaceLanguage: WeiBeiInterfaceLanguage
        var webMarkdown = ""
        var pendingExternalMarkdown: String?
        var lastCommandID: UUID?
        fileprivate let imageSchemeHandler = MarkdownImageSchemeHandler()
        private var lastAppliedSearchQuery = ""
        private var lastAppliedFocusRequest = -1
        private var lastAppliedSelectionAskMarks = ""
        private var documentRevision: UInt64 = 0
        private var acceptsDocumentRequests = true

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
            appearanceMode: WeiBeiAppearanceMode,
            interfaceLanguage: WeiBeiInterfaceLanguage,
            selectionAskMarks: String,
            onContentHeightChange: @escaping (CGFloat) -> Void,
            onActiveHeadingChange: @escaping (Int?) -> Void,
            onSelectionChange: @escaping (String, CGPoint?) -> Void,
            onAskAgentWithSelection: @escaping (String, CGPoint?) -> Void,
            onWikiLink: @escaping (String) -> Void,
            onSourceReference: @escaping (String) -> Void,
            onAppShortcut: @escaping (String, NSEvent.ModifierFlags) -> Bool,
            onSelectionAskMark: @escaping (String) -> Void
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
            self.appearanceMode = appearanceMode
            self.interfaceLanguage = interfaceLanguage
            self.selectionAskMarks = selectionAskMarks
            self.onContentHeightChange = onContentHeightChange
            self.onActiveHeadingChange = onActiveHeadingChange
            self.onSelectionChange = onSelectionChange
            self.onAskAgentWithSelection = onAskAgentWithSelection
            self.onWikiLink = onWikiLink
            self.onSourceReference = onSourceReference
            self.onAppShortcut = onAppShortcut
            self.onSelectionAskMark = onSelectionAskMark
        }

        func handleAppShortcut(key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
            onAppShortcut(key, modifiers)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // The SwiftUI document can change while the WebView is still booting.
            // Its one ready callback still belongs to this WebView and must be
            // accepted so we can push the latest document into it. Every later
            // callback remains scoped to the current document identity.
            if message.name != "editorReady" {
                guard messageMatchesDocument(message.body) else { return }
            }
            switch message.name {
            case "editorReady":
                isReady = true
                setDocumentID(documentID)
                setMarkdownBaseURL(markdownBaseURLString)
                setEditable(isEditable)
                setInterfaceLanguage(interfaceLanguage)
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
                setTheme(appearanceMode)
                applyFocus()
                applySelectionAskMarks(force: true)
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
                applySelectionAskMarks(force: true)
            case "selectionChanged":
                guard let body = message.body as? [String: Any],
                      let text = body["text"] as? String else { return }
                onSelectionChange(text, anchor(from: body["rect"] as? [String: Any]))
            case "askAgentWithSelection":
                guard let body = message.body as? [String: Any] else { return }
                let text = body["text"] as? String ?? ""
                onAskAgentWithSelection(text, anchor(from: body["rect"] as? [String: Any]))
            case "selectionAskMark":
                guard let body = message.body as? [String: Any],
                      let threadID = body["threadId"] as? String,
                      !threadID.isEmpty else { return }
                onSelectionAskMark(threadID)
            case "wikiLinkActivated":
                guard let body = message.body as? [String: Any],
                      let title = body["title"] as? String else { return }
                onWikiLink(title)
            case "sourceReferenceActivated":
                guard let body = message.body as? [String: Any],
                      let reference = body["reference"] as? String else { return }
                onSourceReference(reference)
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
                    evaluate("window.WeiBeiEditor?.rejectAttachment(\(Self.json(id)), \(Self.json(interfaceLanguage.text("图片无法写入本地附件目录", "Image could not be written to the local attachments folder")))")
                }
            case "imagePickerRequested":
                guard isEditable,
                      let body = message.body as? [String: Any],
                      let id = body["id"] as? String else { return }
                presentImagePicker(requestID: id, documentID: documentID)
            case "appShortcut":
                guard let body = message.body as? [String: Any],
                      let key = body["key"] as? String else { return }
                _ = handleAppShortcut(key: key, modifiers: modifiers(from: body))
            case "contentHeightChanged":
                guard let body = message.body as? [String: Any],
                      let height = body["height"] as? Double else { return }
                onContentHeightChange(CGFloat(height))
            case "activeHeadingChanged":
                guard let body = message.body as? [String: Any] else { return }
                onActiveHeadingChange((body["index"] as? NSNumber)?.intValue)
            case "compactPreviewWheel":
                guard let body = message.body as? [String: Any],
                      let deltaY = body["deltaY"] as? Double else { return }
                (webView as? MarkdownWebView)?.scrollOuterSuperview(deltaY: CGFloat(deltaY))
            default:
                break
            }
        }

        private func messageMatchesDocument(_ body: Any) -> Bool {
            guard let body = body as? [String: Any],
                  let messageDocumentID = body["documentID"] as? String else {
                return documentID.isEmpty
            }
            return messageDocumentID == documentID
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

        func setDocumentID(_ id: String) {
            evaluate("window.WeiBeiEditor?.setDocumentID(\(Self.json(id)))")
        }

        /**
         * Advances the document generation before notifying the WebEditor.
         *
         * @param id - Newly active document identity
         */
        func transition(toDocumentID id: String) {
            guard documentID != id else { return }
            documentID = id
            documentRevision &+= 1
            setDocumentID(id)
        }

        /**
         * Invalidates asynchronous document work when the native editor is dismantled.
         */
        func invalidateDocumentRequests() {
            acceptsDocumentRequests = false
            documentRevision &+= 1
        }

        func setMarkdownBaseURL(_ url: String) {
            evaluate("window.WeiBeiEditor?.setMarkdownBaseURL(\(Self.json(url)))")
        }

        func setTheme(_ mode: WeiBeiAppearanceMode) {
            evaluate("window.WeiBeiEditor?.setTheme(\(Self.json(mode.webThemeName)))")
        }

        func setInterfaceLanguage(_ language: WeiBeiInterfaceLanguage) {
            evaluate("window.WeiBeiEditor?.setInterfaceLanguage(\(Self.json(language.rawValue)))")
        }

        func run(_ command: NoteEditorCommand) {
            switch command.kind {
            case .replaceSelection:
                evaluate("window.WeiBeiEditor?.replaceSelection(\(Self.json(command.markdown)))")
            case .applyAgentPatch:
                evaluate("window.WeiBeiEditor?.applyAgentPatch(\(Self.json(command.markdown)))")
            case .insertMarkdown:
                evaluate("window.WeiBeiEditor?.insertMarkdown(\(Self.json(command.markdown)))")
            case .scrollToHeading:
                evaluate("window.WeiBeiEditor?.scrollToHeading(\(Self.json(command.markdown)))")
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
              window.webkit?.messageHandlers?.selectionChanged?.postMessage({
                text: "",
                rect: null,
                documentID: window.weiBeiDocumentID || ""
              });
              if (!query) return false;
              window.weiBeiSuppressSelectionReport = true;
              const found = window.find(query, false, false, true, false, true, false);
              window.setTimeout(() => { window.weiBeiSuppressSelectionReport = false; }, 80);
              return found;
            })();
            """)
        }

        func applyFocus() {
            guard isFocused, focusRequest != lastAppliedFocusRequest else { return }
            lastAppliedFocusRequest = focusRequest
            webView?.window?.makeFirstResponder(webView)
            evaluate("document.querySelector('.ProseMirror')?.focus()")
        }

        func applySelectionAskMarks(force: Bool = false) {
            guard isReady, !isEditable else { return }
            guard force || selectionAskMarks != lastAppliedSelectionAskMarks else { return }
            lastAppliedSelectionAskMarks = selectionAskMarks
            // Delay so Milkdown finishes painting before we wrap text nodes.
            let marks = selectionAskMarks
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self, self.isReady, !self.isEditable else { return }
                self.evaluate("window.WeiBeiSelectionAskMarks && window.WeiBeiSelectionAskMarks.apply(\(marks));")
            }
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

        /**
         * Presents the native single-image picker for a slash image command.
         *
         * @param requestID - JavaScript request identifier
         * @param documentID - Document identity captured when the command was issued
         */
        private func presentImagePicker(requestID: String, documentID requestedDocumentID: String) {
            let requestedDocumentRevision = documentRevision
            guard let window = webView?.window else {
                evaluate("""
                window.WeiBeiEditor?.rejectImagePicker(
                  \(Self.json(requestID)),
                  \(Self.json(interfaceLanguage.text("无法打开图片选择器", "Image picker could not be opened")))
                )
                """)
                return
            }
            let panel = NSOpenPanel()
            panel.title = interfaceLanguage.text("插入图片", "Insert Image")
            panel.prompt = interfaceLanguage.text("插入", "Insert")
            panel.message = interfaceLanguage.text("选择一张图片收纳到当前笔记附件目录", "Choose one image to save in the current note attachments folder")
            panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .tiff, .heic]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                guard self.acceptsDocumentRequests,
                      self.documentID == requestedDocumentID,
                      self.documentRevision == requestedDocumentRevision else {
                    self.evaluate("window.WeiBeiEditor?.discardImagePicker(\(Self.json(requestID)))")
                    return
                }
                guard response == .OK else {
                    self.evaluate("window.WeiBeiEditor?.cancelImagePicker(\(Self.json(requestID)))")
                    return
                }
                guard let fileURL = panel.url,
                      let attachmentDirectory = self.attachmentDirectory else {
                    self.evaluate("""
                    window.WeiBeiEditor?.rejectImagePicker(
                      \(Self.json(requestID)),
                      \(Self.json(self.interfaceLanguage.text("图片无法写入本地附件目录", "Image could not be written to the local attachments folder")))
                    )
                    """)
                    return
                }

                let markdownBaseURLString = self.markdownBaseURLString
                let failureMessage = self.interfaceLanguage.text(
                    "图片读取或写入失败，请检查文件与附件目录权限",
                    "Image could not be read or saved. Check the file and attachments folder permissions."
                )
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result {
                        try Self.saveImageAttachment(
                            fromFileURL: fileURL,
                            attachmentDirectory: attachmentDirectory,
                            markdownBaseURLString: markdownBaseURLString
                        )
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else {
                            if case let .success(attachment) = result {
                                let savedFileURL = attachmentDirectory.appendingPathComponent(
                                    URL(fileURLWithPath: attachment.src).lastPathComponent
                                )
                                try? FileManager.default.removeItem(at: savedFileURL)
                            }
                            return
                        }
                        guard self.acceptsDocumentRequests,
                              self.documentID == requestedDocumentID,
                              self.documentRevision == requestedDocumentRevision else {
                            if case let .success(attachment) = result {
                                let savedFileURL = attachmentDirectory.appendingPathComponent(
                                    URL(fileURLWithPath: attachment.src).lastPathComponent
                                )
                                try? FileManager.default.removeItem(at: savedFileURL)
                            }
                            self.evaluate("window.WeiBeiEditor?.discardImagePicker(\(Self.json(requestID)))")
                            return
                        }
                        switch result {
                        case let .success(attachment):
                            self.evaluate("""
                            window.WeiBeiEditor?.resolveImagePicker(
                              \(Self.json(requestID)),
                              \(Self.json(attachment.src)),
                              \(Self.json(attachment.alt))
                            )
                            """)
                        case .failure:
                            self.evaluate("""
                            window.WeiBeiEditor?.rejectImagePicker(
                              \(Self.json(requestID)),
                              \(Self.json(failureMessage))
                            )
                            """)
                        }
                    }
                }
            }
        }

        /**
         * Reads and saves a file chosen by the native picker.
         *
         * @param fileURL - User-selected image URL
         * @param attachmentDirectory - Destination directory captured for the requesting document
         * @param markdownBaseURLString - Markdown base URL captured for the requesting document
         * @returns Saved attachment metadata
         */
        private static func saveImageAttachment(
            fromFileURL fileURL: URL,
            attachmentDirectory: URL,
            markdownBaseURLString: String
        ) throws -> MarkdownAttachment {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            return try MarkdownAttachmentStore.save(
                data: data,
                originalName: fileURL.lastPathComponent,
                mime: MarkdownAttachmentStore.mimeType(forFileExtension: fileURL.pathExtension),
                attachmentDirectory: attachmentDirectory,
                markdownBaseURLString: markdownBaseURLString
            )
        }

        private func anchor(from rect: [String: Any]?) -> CGPoint? {
            guard let view = webView,
                  let rect,
                  let x = rect["x"] as? Double,
                  let y = rect["y"] as? Double else {
                return nil
            }
            return SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)
        }

        private static func json(_ value: String) -> String {
            let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }

    }
}
