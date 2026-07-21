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
    @State private var verificationAfterRequestID = 0

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
                    verificationAfterRequestID: verificationAfterRequestID,
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
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            verificationAfterRequestID &+= 1
        }
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

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        webView.wantsLayer = true
        webView.layer?.masksToBounds = true
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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
        // No per-scroll CALayer mask: bounds observers + mask rebuilds thrash during fling.
        webView.layer?.mask = nil
        webView.isHidden = false
    }

    /// Let the conversation ScrollView own vertical wheel — rich-answer UI is not a nested scroller.
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
           let outer = nearestConversationScrollView() {
            outer.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // While the user is scrolling, don't trap the event inside WKWebView.
        if let event = NSApp.currentEvent, event.type == .scrollWheel,
           abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) {
            return nil
        }
        return super.hitTest(point)
    }

    private func nearestConversationScrollView() -> NSScrollView? {
        var candidate: NSView? = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    private func enforceScrollClipping() {
        // Clip only — never attach boundsDidChange observers (those froze immersive scroll).
        var ancestor = superview
        while let current = ancestor {
            if let clipView = current as? NSClipView {
                clipView.wantsLayer = true
                clipView.layer?.masksToBounds = true
                return
            }
            if let scrollView = current as? NSScrollView {
                scrollView.contentView.wantsLayer = true
                scrollView.contentView.layer?.masksToBounds = true
                return
            }
            ancestor = current.superview
        }
    }

    func refreshViewportClipping() {
        enforceScrollClipping()
        webView.layer?.mask = nil
        webView.isHidden = false
    }
}

private struct RichAnswerWebViewRepresentable: NSViewRepresentable {
    let entries: [RichAnswerWebRuntimeEntry]
    let evidenceByID: [String: RichAnswerEvidence]
    let heightLimit: CGFloat
    @Binding var contentHeight: CGFloat
    @Binding var contentOverflowed: Bool
    @Binding var runtimeError: String?
    let verificationAfterRequestID: Int
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
        context.coordinator.handleVerificationAfterRequest(verificationAfterRequestID)
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
        private var verificationWorkItem: DispatchWorkItem?
        private var handledVerificationAfterRequestID = 0
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
            verificationWorkItem?.cancel()
            verificationWorkItem = nil
        }

        func handleVerificationAfterRequest(_ requestID: Int) {
            guard RichAnswerVerificationBridge.isEnabled,
                  requestID > 0,
                  requestID != handledVerificationAfterRequestID else { return }
            handledVerificationAfterRequestID = requestID
            scheduleVerificationInteraction(requestID: requestID)
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

        private func scheduleVerificationInteraction(requestID: Int, attempt: Int = 0) {
            verificationWorkItem?.cancel()
            guard RichAnswerVerificationBridge.isEnabled, attempt < 5 else { return }
            let delay: TimeInterval = attempt == 0 ? 0.08 : min(0.16 * Double(attempt + 1), 0.72)
            let workItem = DispatchWorkItem { [weak self] in
                self?.performVerificationInteraction(requestID: requestID, attempt: attempt)
            }
            verificationWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func performVerificationInteraction(requestID: Int, attempt: Int) {
            guard RichAnswerVerificationBridge.isEnabled else { return }
            guard isReady,
                  hasRuntimeHeight,
                  sentPayloadFingerprint != nil,
                  let webView else {
                scheduleVerificationInteraction(requestID: requestID, attempt: attempt + 1)
                return
            }
            webView.evaluateJavaScript(Self.verificationInteractionScript) { [weak self] value, error in
                guard let self else { return }
                if error != nil || !Self.verificationInteractionSucceeded(value) {
                    scheduleVerificationInteraction(requestID: requestID, attempt: attempt + 1)
                }
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

        private static let verificationInteractionScript = """
        (() => {
          const visible = (element) => {
            if (!element || element.disabled) return false;
            const style = window.getComputedStyle(element);
            if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
            const rect = element.getBoundingClientRect();
            return rect.width > 1 && rect.height > 1 && rect.bottom > 0 && rect.right > 0 && rect.top < window.innerHeight && rect.left < window.innerWidth;
          };
          const labelOf = (element) => String(element?.textContent || element?.getAttribute("aria-label") || "").trim().toLowerCase();
          const dispatchPointer = (element, type) => {
            const eventInit = { bubbles: true, pointerId: 1, pointerType: "mouse", isPrimary: true };
            const event = typeof PointerEvent === "function" ? new PointerEvent(type, eventInit) : new MouseEvent(type === "pointerdown" ? "mousedown" : "mouseup", { bubbles: true });
            element.dispatchEvent(event);
          };
          const press = (element) => {
            if (!visible(element)) return false;
            element.scrollIntoView({ block: "center", inline: "nearest" });
            dispatchPointer(element, "pointerdown");
            dispatchPointer(element, "pointerup");
            element.click();
            return true;
          };
          const first = (selectors) => {
            for (const selector of selectors) {
              const found = Array.from(document.querySelectorAll(selector)).find(visible);
              if (found) return found;
            }
            return null;
          };
          const byText = (selectors, patterns, rejectPatterns = []) => {
            const candidates = selectors.flatMap((selector) => Array.from(document.querySelectorAll(selector)));
            return candidates.find((element) => {
              if (!visible(element)) return false;
              const label = labelOf(element);
              return patterns.some((pattern) => pattern.test(label)) && !rejectPatterns.some((pattern) => pattern.test(label));
            }) || null;
          };
          const advanceRange = () => {
            const range = Array.from(document.querySelectorAll('input[type="range"]')).find(visible);
            if (!range) return false;
            const minimum = Number(range.min || 0);
            const maximum = Number(range.max || 100);
            const step = Number(range.step || ((maximum - minimum) / 8));
            const current = Number(range.value || minimum);
            if (!Number.isFinite(minimum) || !Number.isFinite(maximum) || minimum >= maximum) return false;
            const safeStep = Number.isFinite(step) && step > 0 ? step : (maximum - minimum) / 8;
            const next = current + Math.max(safeStep, (maximum - minimum) * 0.28);
            range.value = String(next <= maximum ? next : minimum + (maximum - minimum) * 0.35);
            range.dispatchEvent(new Event("input", { bubbles: true }));
            range.dispatchEvent(new Event("change", { bubbles: true }));
            return true;
          };
          const executionNext = first([
            '[data-action="execution-next"]',
            '[data-testid="execution-next"]',
            '[aria-label*="execution-next" i]',
            'button.execution-next',
            '.execution-controls button:not(:disabled):last-of-type',
            '.ra-execution-controls button:not(:disabled):last-of-type'
          ]) || byText(["button"], [/下一步|next|step/], [/上一步|previous|prev|back/]);
          if (press(executionNext)) return true;
          const processStep = first([
            '[data-action="process-next"]',
            '[data-testid="process-next"]',
            '.ra-process button:not(.is-active):not(.is-selected)',
            '.process-step button:not(.is-active):not(.is-selected)',
            '[role="listitem"] button:not(.is-active):not(.is-selected)'
          ]) || byText(["button"], [/过程|阶段|step|process/], [/reset|重置|证据|来源/]);
          if (press(processStep)) return true;
          const argumentUnit = first([
            '.ra-argument-reader__copy button:not(.is-active)',
            '[data-component="ArgumentUnit"]:not(.is-active) button',
            '[data-role="ArgumentUnit"]:not(.is-active) button'
          ]);
          if (press(argumentUnit)) return true;
          const causalEvent = first([
            '.ra-causal-track__rail button:not(.is-active):not(.is-selected)',
            '.policy-river button:not(.is-selected)',
            '[data-component="CausalEvent"]:not(.is-active) button',
            '[data-role="CausalEvent"]:not(.is-active) button'
          ]);
          if (press(causalEvent)) return true;
          const valueOption = first([
            '[role="option"]:not([aria-selected="true"])',
            '.value-picker button:not(.is-active):not(.is-selected)',
            '[data-component="ValuePicker"] button:not(.is-active):not(.is-selected)',
            '[data-role="value-option"]:not(.is-active):not(.is-selected)'
          ]);
          if (press(valueOption)) return true;
          const spatialToggle = first([
            '.ra-spatial-view__layers input[type="checkbox"]',
            '[data-component="SpatialToggle"] input[type="checkbox"]',
            '[data-role="spatial-toggle"] input[type="checkbox"]'
          ]);
          if (press(spatialToggle)) return true;
          return advanceRange();
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

        private static func verificationInteractionSucceeded(_ value: Any?) -> Bool {
            if let number = value as? NSNumber {
                return number.boolValue
            }
            if let value = value as? Bool {
                return value
            }
            return false
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
