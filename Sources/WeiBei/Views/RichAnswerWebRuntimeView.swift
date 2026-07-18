import AppKit
import SwiftUI
import WebKit
import WeiBeiCore

private struct RichAnswerWebRuntimeEntry {
    let scene: RichAnswerScene
    let program: RichAnswerUIProgram
}

struct RichAnswerWebRuntimeView: View {
    private let entries: [RichAnswerWebRuntimeEntry]
    private let evidenceByID: [String: RichAnswerEvidence]
    private let expandsOverflow: Bool
    private let onRequestExpansion: (() -> Void)?
    private let onOpenEvidence: (RichAnswerEvidence) -> Void
    private let onAction: (String) -> Void
    private let onRuntimeReady: () -> Void

    @State private var contentHeight: CGFloat = 240
    @State private var contentOverflowed = false
    @State private var runtimeError: String?

    init(
        scene: RichAnswerScene,
        program: RichAnswerUIProgram,
        evidenceByID: [String: RichAnswerEvidence],
        expandsOverflow: Bool = false,
        onRequestExpansion: (() -> Void)? = nil,
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
        onAction: @escaping (String) -> Void,
        onRuntimeReady: @escaping () -> Void = {}
    ) {
        entries = [RichAnswerWebRuntimeEntry(scene: scene, program: program)]
        self.evidenceByID = evidenceByID
        self.expandsOverflow = expandsOverflow
        self.onRequestExpansion = onRequestExpansion
        self.onOpenEvidence = onOpenEvidence
        self.onAction = onAction
        self.onRuntimeReady = onRuntimeReady
    }

    init(
        scenes: [RichAnswerScene],
        evidenceByID: [String: RichAnswerEvidence],
        expandsOverflow: Bool = false,
        onRequestExpansion: (() -> Void)? = nil,
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
        onAction: @escaping (String) -> Void,
        onRuntimeReady: @escaping () -> Void = {}
    ) {
        entries = scenes.compactMap { scene in
            scene.program.map { RichAnswerWebRuntimeEntry(scene: scene, program: $0) }
        }
        self.evidenceByID = evidenceByID
        self.expandsOverflow = expandsOverflow
        self.onRequestExpansion = onRequestExpansion
        self.onOpenEvidence = onOpenEvidence
        self.onAction = onAction
        self.onRuntimeReady = onRuntimeReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                RichAnswerWebViewRepresentable(
                    entries: entries,
                    evidenceByID: evidenceByID,
                    heightLimit: heightLimit,
                    contentHeight: $contentHeight,
                    contentOverflowed: $contentOverflowed,
                    runtimeError: $runtimeError,
                    onOpenEvidence: onOpenEvidence,
                    onAction: onAction,
                    onRuntimeReady: onRuntimeReady
                )

                if let runtimeError {
                    Text(runtimeError)
                        .font(.caption)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(WeiBeiTheme.paperRaised.opacity(0.96))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: renderedHeight)
            .clipped()

            if contentOverflowed, !expandsOverflow, let onRequestExpansion {
                Button("展开完整视觉体验") {
                    onRequestExpansion()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            }
        }
        .accessibilityLabel(entries.map(\.scene.title).joined(separator: "；"))
    }

    private var collapsedHeightLimit: CGFloat {
        let requested = entries.reduce(0) { $0 + $1.program.maxHeight }
        return CGFloat(max(160, min(720, requested)))
    }

    private var heightLimit: CGFloat {
        expandsOverflow ? 2_400 : collapsedHeightLimit
    }

    private var renderedHeight: CGFloat {
        min(max(contentHeight, 160), heightLimit)
    }
}

private final class RichAnswerWebClippingView: NSView {
    let webView: WKWebView
    private weak var viewportClipView: NSClipView?
    private var viewportObservers: [NSObjectProtocol] = []
    private var pendingClipPath: String?
    private var appliedClipPath: String?
    private var clipUpdateScheduled = false

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        viewportObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        enforceScrollClipping()
        DispatchQueue.main.async { [weak self] in
            self?.enforceScrollClipping()
        }
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
        enforceScrollClipping()
        updateViewportMask()
    }

    private func enforceScrollClipping() {
        var ancestor = superview
        while let current = ancestor {
            if let clipView = current as? NSClipView {
                clipView.wantsLayer = true
                clipView.layer?.masksToBounds = true
                observeViewport(clipView)
                return
            }
            if let scrollView = current as? NSScrollView {
                scrollView.contentView.wantsLayer = true
                scrollView.contentView.layer?.masksToBounds = true
                observeViewport(scrollView.contentView)
                return
            }
            ancestor = current.superview
        }
    }

    private func observeViewport(_ clipView: NSClipView) {
        guard viewportClipView !== clipView else {
            updateViewportMask()
            return
        }
        viewportObservers.forEach(NotificationCenter.default.removeObserver)
        viewportObservers.removeAll()
        viewportClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        viewportObservers.append(
            center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.updateViewportMask()
            }
        )
        viewportObservers.append(
            center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.updateViewportMask()
            }
        )
        updateViewportMask()
    }

    private func updateViewportMask() {
        guard let clipView = viewportClipView,
              window != nil,
              window === clipView.window,
              bounds.width > 1,
              bounds.height > 1 else { return }
        layer?.mask = nil
        let viewportInWindow = clipView.convert(clipView.bounds, to: nil)
        let viewportRect = convert(viewportInWindow, from: nil)
        let visibleRect = bounds.intersection(viewportRect)
        guard !visibleRect.isNull, !visibleRect.isEmpty else {
            webView.isHidden = true
            return
        }
        webView.isHidden = false
        let top = max(0, bounds.height - visibleRect.maxY)
        let right = max(0, bounds.width - visibleRect.maxX)
        let bottom = max(0, visibleRect.minY)
        let left = max(0, visibleRect.minX)
        let clipPath: String
        if max(top, right, bottom, left) < 0.5 {
            clipPath = "none"
        } else {
            clipPath = "inset(\(top)px \(right)px \(bottom)px \(left)px)"
        }
        scheduleClipPath(clipPath)
    }

    func refreshViewportClipping() {
        appliedClipPath = nil
        updateViewportMask()
    }

    private func scheduleClipPath(_ clipPath: String) {
        pendingClipPath = clipPath
        guard !clipUpdateScheduled else { return }
        clipUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            clipUpdateScheduled = false
            guard let clipPath = pendingClipPath else { return }
            pendingClipPath = nil
            guard appliedClipPath != clipPath else { return }
            appliedClipPath = clipPath
            let script = "document.documentElement.style.clipPath = '\(clipPath)'; document.documentElement.style.webkitClipPath = '\(clipPath)';"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if error != nil {
                    self?.appliedClipPath = nil
                }
            }
        }
    }
}

private struct RichAnswerWebViewRepresentable: NSViewRepresentable {
    let entries: [RichAnswerWebRuntimeEntry]
    let evidenceByID: [String: RichAnswerEvidence]
    let heightLimit: CGFloat
    @Binding var contentHeight: CGFloat
    @Binding var contentOverflowed: Bool
    @Binding var runtimeError: String?
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onAction: (String) -> Void
    var onRuntimeReady: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            entries: entries,
            evidenceByID: evidenceByID,
            heightLimit: heightLimit,
            contentHeight: $contentHeight,
            contentOverflowed: $contentOverflowed,
            runtimeError: $runtimeError,
            onOpenEvidence: onOpenEvidence,
            onAction: onAction,
            onRuntimeReady: onRuntimeReady
        )
    }

    func makeNSView(context: Context) -> RichAnswerWebClippingView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.messageHandlerName)
        controller.addUserScript(
            WKUserScript(
                source: Self.bootstrapScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.allowsAirPlayForMediaPlayback = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.layer?.masksToBounds = true
        webView.allowsLinkPreview = false
        context.coordinator.webView = webView
        let clippingView = RichAnswerWebClippingView(webView: webView)
        context.coordinator.clippingView = clippingView

        guard let entryURL = WeiBeiResources.bundle.url(
            forResource: "rich-answer",
            withExtension: "html"
        ) else {
            runtimeError = "富回答网页运行时资源缺失。"
            return clippingView
        }

        RichAnswerWebNetworkGuard.install(in: controller) { result in
            switch result {
            case .success:
                webView.loadFileURL(entryURL, allowingReadAccessTo: entryURL.deletingLastPathComponent())
            case let .failure(error):
                context.coordinator.failStartup("富回答网络隔离无法启动：\(error.localizedDescription)")
            }
        }
        return clippingView
    }

    func updateNSView(_ container: RichAnswerWebClippingView, context: Context) {
        context.coordinator.update(
            entries: entries,
            evidenceByID: evidenceByID,
            heightLimit: heightLimit,
            contentHeight: $contentHeight,
            contentOverflowed: $contentOverflowed,
            runtimeError: $runtimeError,
            onOpenEvidence: onOpenEvidence,
            onAction: onAction,
            onRuntimeReady: onRuntimeReady
        )
        context.coordinator.sendProgramsIfReady()
    }

    static func dismantleNSView(_ container: RichAnswerWebClippingView, coordinator: Coordinator) {
        let webView = container.webView
        coordinator.stop()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.messageHandlerName
        )
        webView.navigationDelegate = nil
    }

    private static let bootstrapScript = """
    (() => {
      window.__WEIBEI_EMBEDDED__ = true;
      const blocked = () => Promise.reject(new Error("WeiBei rich-answer runtime is local-only"));
      window.fetch = blocked;
      window.open = () => null;
      window.WebSocket = class {
        constructor() { throw new Error("WeiBei rich-answer runtime is local-only"); }
      };
      if (window.XMLHttpRequest) {
        window.XMLHttpRequest.prototype.open = function () {
          throw new Error("WeiBei rich-answer runtime is local-only");
        };
      }
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let messageHandlerName = "weibeiRichAnswer"

        weak var webView: WKWebView?
        weak var clippingView: RichAnswerWebClippingView?
        private var entries: [RichAnswerWebRuntimeEntry]
        private var evidenceByID: [String: RichAnswerEvidence]
        private var heightLimit: CGFloat
        private var contentHeight: Binding<CGFloat>
        private var contentOverflowed: Binding<Bool>
        private var runtimeError: Binding<String?>
        private var onOpenEvidence: (RichAnswerEvidence) -> Void
        private var onAction: (String) -> Void
        private var onRuntimeReady: () -> Void
        private var isReady = false
        private var notifiedRuntimeReady = false
        private var sentPayloadFingerprint: String?
        private var readinessWorkItem: DispatchWorkItem?
        private var heightRecoveryWorkItem: DispatchWorkItem?
        private var heightUpdateWorkItem: DispatchWorkItem?
        private var hasRuntimeHeight = false

        init(
            entries: [RichAnswerWebRuntimeEntry],
            evidenceByID: [String: RichAnswerEvidence],
            heightLimit: CGFloat,
            contentHeight: Binding<CGFloat>,
            contentOverflowed: Binding<Bool>,
            runtimeError: Binding<String?>,
            onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
            onAction: @escaping (String) -> Void,
            onRuntimeReady: @escaping () -> Void
        ) {
            self.entries = entries
            self.evidenceByID = evidenceByID
            self.heightLimit = heightLimit
            self.contentHeight = contentHeight
            self.contentOverflowed = contentOverflowed
            self.runtimeError = runtimeError
            self.onOpenEvidence = onOpenEvidence
            self.onAction = onAction
            self.onRuntimeReady = onRuntimeReady
        }

        func update(
            entries: [RichAnswerWebRuntimeEntry],
            evidenceByID: [String: RichAnswerEvidence],
            heightLimit: CGFloat,
            contentHeight: Binding<CGFloat>,
            contentOverflowed: Binding<Bool>,
            runtimeError: Binding<String?>,
            onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
            onAction: @escaping (String) -> Void,
            onRuntimeReady: @escaping () -> Void
        ) {
            self.entries = entries
            self.evidenceByID = evidenceByID
            self.heightLimit = heightLimit
            self.contentHeight = contentHeight
            self.contentOverflowed = contentOverflowed
            self.runtimeError = runtimeError
            self.onOpenEvidence = onOpenEvidence
            self.onAction = onAction
            self.onRuntimeReady = onRuntimeReady
        }

        func sendProgramsIfReady() {
            guard isReady,
                  let webView,
                  let payload = programsPayload(),
                  let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8),
                  sentPayloadFingerprint != json else { return }
            sentPayloadFingerprint = json
            runtimeError.wrappedValue = nil
            hasRuntimeHeight = false
            notifiedRuntimeReady = false
            heightUpdateWorkItem?.cancel()
            heightUpdateWorkItem = nil
            webView.evaluateJavaScript("window.postMessage(\(json), '*')") { [weak self] _, error in
                if let error {
                    self?.sentPayloadFingerprint = nil
                    self?.runtimeError.wrappedValue = "富回答程序传递失败：\(error.localizedDescription)"
                } else {
                    self?.scheduleHeightRecovery()
                }
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.messageHandlerName,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "weibei:ready":
                isReady = true
                readinessWorkItem?.cancel()
                readinessWorkItem = nil
                sendProgramsIfReady()
            case "weibei:height":
                guard let height = (body["height"] as? NSNumber)?.doubleValue else { return }
                let measuredHeight = min(max(CGFloat(height), 160), 5_000)
                let reportedOverflow = body["overflowed"] as? Bool ?? false
                hasRuntimeHeight = true
                heightRecoveryWorkItem?.cancel()
                heightRecoveryWorkItem = nil
                scheduleRuntimeHeightUpdate(
                    measuredHeight: measuredHeight,
                    reportedOverflow: reportedOverflow
                )
            case "weibei:evidence":
                guard let evidenceID = body["evidenceID"] as? String,
                      let evidence = evidenceByID[evidenceID] else { return }
                onOpenEvidence(evidence)
            case "weibei:action":
                guard let action = body["action"] as? [String: Any],
                      let message = action["humanFriendlyMessage"] as? String,
                      !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                onAction(message)
            case "weibei:error":
                runtimeError.wrappedValue = body["message"] as? String ?? "富回答程序渲染失败。"
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  url.isFileURL,
                  navigationAction.targetFrame?.isMainFrame != false else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.wantsLayer = true
            webView.layer?.backgroundColor = NSColor.clear.cgColor
            webView.layer?.masksToBounds = true
            webView.needsDisplay = true
            clippingView?.refreshViewportClipping()
            scheduleReadinessTimeout()
            scheduleHeightRecovery()
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            readinessWorkItem?.cancel()
            runtimeError.wrappedValue = "富回答运行时加载失败：\(error.localizedDescription)"
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            readinessWorkItem?.cancel()
            runtimeError.wrappedValue = "富回答运行时无法启动：\(error.localizedDescription)"
        }

        func failStartup(_ message: String) {
            readinessWorkItem?.cancel()
            runtimeError.wrappedValue = message
        }

        func stop() {
            readinessWorkItem?.cancel()
            readinessWorkItem = nil
            heightRecoveryWorkItem?.cancel()
            heightRecoveryWorkItem = nil
            heightUpdateWorkItem?.cancel()
            heightUpdateWorkItem = nil
        }

        private func scheduleReadinessTimeout() {
            readinessWorkItem?.cancel()
            guard !isReady else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, !isReady else { return }
                runtimeError.wrappedValue = "富回答运行时未就绪，已停止等待。"
                contentHeight.wrappedValue = fallbackContentHeight()
            }
            readinessWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
        }

        private func scheduleHeightRecovery(attempt: Int = 0) {
            heightRecoveryWorkItem?.cancel()
            guard isReady, attempt < 5, !hasRuntimeHeight else { return }
            let delay: TimeInterval = attempt == 0 ? 0.12 : min(0.24 * Double(attempt + 1), 1.2)
            let workItem = DispatchWorkItem { [weak self] in
                self?.recoverHeight(attempt: attempt)
            }
            heightRecoveryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func recoverHeight(attempt: Int) {
            guard !hasRuntimeHeight, let webView else { return }
            webView.evaluateJavaScript(Self.heightRecoveryScript) { [weak self] value, _ in
                guard let self, !hasRuntimeHeight else { return }
                let measured = Self.heightValue(from: value)
                let fallbackHeight = self.fallbackContentHeight()
                let nextHeight = measured.map { min(max($0, fallbackHeight), 5_000) } ?? fallbackHeight
                if measured != nil {
                    hasRuntimeHeight = true
                    scheduleRuntimeHeightUpdate(
                        measuredHeight: nextHeight,
                        reportedOverflow: nextHeight > heightLimit + 1
                    )
                } else {
                    contentHeight.wrappedValue = nextHeight
                    contentOverflowed.wrappedValue = nextHeight > heightLimit + 1
                }
                scheduleHeightRecovery(attempt: attempt + 1)
            }
        }

        private func scheduleRuntimeHeightUpdate(measuredHeight: CGFloat, reportedOverflow: Bool) {
            let nextHeight = min(max(measuredHeight, 160), 5_000)
            let nextOverflow = reportedOverflow || nextHeight > heightLimit + 1
            let currentHeight = contentHeight.wrappedValue
            let currentOverflow = contentOverflowed.wrappedValue
            let heightDelta = abs(currentHeight - nextHeight)
            guard heightDelta >= 2 || currentOverflow != nextOverflow else {
                notifyRuntimeReadyIfNeeded()
                return
            }

            heightUpdateWorkItem?.cancel()
            let apply = { [weak self] in
                guard let self else { return }
                heightUpdateWorkItem = nil
                contentHeight.wrappedValue = nextHeight
                contentOverflowed.wrappedValue = nextOverflow
                notifyRuntimeReadyIfNeeded()
            }
            guard notifiedRuntimeReady, heightDelta < 24 else {
                apply()
                return
            }

            let workItem = DispatchWorkItem(block: apply)
            heightUpdateWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
        }

        private func notifyRuntimeReadyIfNeeded() {
            guard !notifiedRuntimeReady, isReady, hasRuntimeHeight else { return }
            notifiedRuntimeReady = true
            onRuntimeReady()
        }

        private func fallbackContentHeight() -> CGFloat {
            let requested = entries.reduce(0) { $0 + $1.program.maxHeight }
            guard requested > 0 else { return 220 }
            return min(max(CGFloat(requested) * 0.58, 220), heightLimit)
        }

        private func programsPayload() -> [String: Any]? {
            let programs = entries.compactMap(programPayload)
            guard !programs.isEmpty, programs.count == entries.count else { return nil }
            return [
                "type": "weibei:setPrograms",
                "programs": programs,
                "heightLimit": Int(heightLimit.rounded()),
            ]
        }

        private func programPayload(for entry: RichAnswerWebRuntimeEntry) -> [String: Any]? {
            let scene = entry.scene
            let program = entry.program
            let evidenceBindings = scene.evidenceIDs.compactMap { evidenceID -> [String: String]? in
                guard let evidence = evidenceByID[evidenceID] else { return nil }
                return [
                    "id": evidence.id,
                    "sourceID": evidence.sourceLabel,
                    "locator": evidence.sourceLabel,
                ]
            }
            let evidenceContent = scene.evidenceIDs.compactMap { evidenceID -> [String: Any]? in
                guard let evidence = evidenceByID[evidenceID] else { return nil }
                return [
                    "id": evidence.id,
                    "sourceLabel": evidence.sourceLabel,
                    "excerpt": evidence.excerpt,
                    "isTruncated": evidence.isTruncated,
                ]
            }
            return [
                "version": program.version,
                "id": scene.id,
                "title": scene.title,
                "question": scene.title,
                "mode": "declarative",
                "source": program.source,
                "capabilities": program.capabilities,
                "evidenceBindings": evidenceBindings,
                "evidenceContent": evidenceContent,
                "budget": [
                    "maxHeight": program.maxHeight,
                    "maxNodes": 48,
                    "maxSeries": 8,
                    "graphics": program.graphics.rawValue,
                ],
            ]
        }

        private static let heightRecoveryScript = """
        (() => {
          const root = document.documentElement;
          const body = document.body;
          const values = [
            root && root.scrollHeight,
            root && root.offsetHeight,
            root && root.clientHeight,
            body && body.scrollHeight,
            body && body.offsetHeight,
            body && body.clientHeight,
            root && root.getBoundingClientRect && root.getBoundingClientRect().height,
            body && body.getBoundingClientRect && body.getBoundingClientRect().height
          ].filter((value) => Number.isFinite(value) && value > 0);
          return values.length ? Math.max(...values) : 0;
        })();
        """

        private static func heightValue(from value: Any?) -> CGFloat? {
            if let number = value as? NSNumber {
                return CGFloat(number.doubleValue)
            }
            if let double = value as? Double {
                return CGFloat(double)
            }
            if let value = value as? CGFloat {
                return value
            }
            return nil
        }
    }
}

private enum RichAnswerWebNetworkGuard {
    private static let identifier = "com.changfenhuang.weibei.rich-answer.block-network.v1"
    private static let rules = """
    [
      {"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"^wss?://.*"},"action":{"type":"block"}}
    ]
    """

    static func install(
        in controller: WKUserContentController,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: rules
        ) { ruleList, error in
            DispatchQueue.main.async {
                if let ruleList {
                    controller.add(ruleList)
                    completion(.success(()))
                    return
                }
                completion(
                    .failure(
                        error ?? NSError(
                            domain: "WeiBei.RichAnswerWebNetworkGuard",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "content rule list unavailable"]
                        )
                    )
                )
            }
        }
    }
}
