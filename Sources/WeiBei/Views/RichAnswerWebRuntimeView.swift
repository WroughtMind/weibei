import AppKit
import SwiftUI
import WebKit
import WeiBeiCore

private struct RichAnswerWebRuntimeEntry {
    let scene: RichAnswerScene
    let kind: Kind

    enum Kind {
        case program(RichAnswerUIProgram)
        case renderPlan(RichAnswerRenderPlan)
    }

    init(scene: RichAnswerScene, program: RichAnswerUIProgram) {
        self.scene = scene
        kind = .program(program)
    }

    init(scene: RichAnswerScene, renderPlan: RichAnswerRenderPlan) {
        self.scene = scene
        kind = .renderPlan(renderPlan)
    }

    var heightBudget: Int {
        switch kind {
        case let .program(program):
            return program.maxHeight
        case let .renderPlan(renderPlan):
            return renderPlan.qualityBudget.maxHeight ?? 420
        }
    }

    var isProgram: Bool {
        if case .program = kind {
            return true
        }
        return false
    }

    var isRenderPlan: Bool {
        if case .renderPlan = kind {
            return true
        }
        return false
    }
}

struct RichAnswerWebRuntimeView: View {
    private let entries: [RichAnswerWebRuntimeEntry]
    private let evidenceByID: [String: RichAnswerEvidence]
    private let expandsOverflow: Bool
    private let onRequestExpansion: (() -> Void)?
    private let onOpenEvidence: (RichAnswerEvidence) -> Void
    private let onAction: (String) -> Void
    private let assetPreview: (String) -> NSImage?
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
        assetPreview: @escaping (String) -> NSImage? = { _ in nil },
        onRuntimeReady: @escaping () -> Void = {}
    ) {
        entries = [RichAnswerWebRuntimeEntry(scene: scene, program: program)]
        self.evidenceByID = evidenceByID
        self.expandsOverflow = expandsOverflow
        self.onRequestExpansion = onRequestExpansion
        self.onOpenEvidence = onOpenEvidence
        self.onAction = onAction
        self.assetPreview = assetPreview
        self.onRuntimeReady = onRuntimeReady
    }

    init(
        scene: RichAnswerScene,
        renderPlan: RichAnswerRenderPlan,
        evidenceByID: [String: RichAnswerEvidence],
        expandsOverflow: Bool = false,
        onRequestExpansion: (() -> Void)? = nil,
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
        onAction: @escaping (String) -> Void,
        assetPreview: @escaping (String) -> NSImage? = { _ in nil },
        onRuntimeReady: @escaping () -> Void = {}
    ) {
        entries = [RichAnswerWebRuntimeEntry(scene: scene, renderPlan: renderPlan)]
        self.evidenceByID = evidenceByID
        self.expandsOverflow = expandsOverflow
        self.onRequestExpansion = onRequestExpansion
        self.onOpenEvidence = onOpenEvidence
        self.onAction = onAction
        self.assetPreview = assetPreview
        self.onRuntimeReady = onRuntimeReady
    }

    init(
        scenes: [RichAnswerScene],
        evidenceByID: [String: RichAnswerEvidence],
        expandsOverflow: Bool = false,
        onRequestExpansion: (() -> Void)? = nil,
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
        onAction: @escaping (String) -> Void,
        assetPreview: @escaping (String) -> NSImage? = { _ in nil },
        onRuntimeReady: @escaping () -> Void = {}
    ) {
        entries = scenes.compactMap { scene in
            if let program = scene.program {
                return RichAnswerWebRuntimeEntry(scene: scene, program: program)
            }
            if let renderPlan = scene.renderPlan {
                return RichAnswerWebRuntimeEntry(scene: scene, renderPlan: renderPlan)
            }
            return nil
        }
        self.evidenceByID = evidenceByID
        self.expandsOverflow = expandsOverflow
        self.onRequestExpansion = onRequestExpansion
        self.onOpenEvidence = onOpenEvidence
        self.onAction = onAction
        self.assetPreview = assetPreview
        self.onRuntimeReady = onRuntimeReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                assetPreview: assetPreview,
                onRuntimeReady: onRuntimeReady
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: runtimeError == nil ? renderedHeight : 0)
            .clipped()
            .accessibilityHidden(runtimeError != nil)

            if runtimeError != nil {
                VStack(alignment: .leading, spacing: 3) {
                    Label("这项富回答无法显示", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .semibold))
                    Text("请继续阅读正文，稍后可重试这项视觉。")
                        .font(.system(size: 10))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)
            }

            if runtimeError == nil, contentOverflowed, !expandsOverflow, let onRequestExpansion {
                Button {
                    onRequestExpansion()
                } label: {
                    Label("放大操作", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
                .help("在更大空间中操作这段富回答")
                .accessibilityIdentifier("rich-answer-expand-visual-experience")
            }
        }
        .accessibilityLabel(entries.map(\.scene.title).joined(separator: "；"))
        .onRichAnswerVerificationStage { stage in
            guard stage == .after else { return }
            verificationAfterRequestID &+= 1
        }
    }

    private var heightLimit: CGFloat {
        5_000
    }

    private var renderedHeight: CGFloat {
        min(max(contentHeight, 160), heightLimit)
    }
}

private final class RichAnswerWebClippingView: NSView {
    let webView: WKWebView
    var onViewportLayout: ((CGSize) -> Void)?

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
        webView.isHidden = false
        enforceScrollClipping()
        DispatchQueue.main.async { [weak self] in
            self?.enforceScrollClipping()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        webView.isHidden = false
        enforceScrollClipping()
        DispatchQueue.main.async { [weak self] in
            self?.enforceScrollClipping()
        }
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
        onViewportLayout?(bounds.size)
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
    var assetPreview: (String) -> NSImage?
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
            assetPreview: assetPreview,
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
        clippingView.onViewportLayout = { [weak coordinator = context.coordinator] size in
            coordinator?.viewportDidLayout(size)
        }

        guard let entryURL = WeiBeiResources.bundle.url(
            forResource: "rich-answer",
            withExtension: "html"
        ) else {
            runtimeError = "富回答网页运行时资源缺失。"
            NSLog("[WeiBei rich answer] %@", runtimeError ?? "unknown runtime resource error")
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
            assetPreview: assetPreview,
            onRuntimeReady: onRuntimeReady
        )
        context.coordinator.sendEntriesIfReady()
        context.coordinator.handleVerificationAfterRequest(verificationAfterRequestID)
    }

    static func dismantleNSView(_ container: RichAnswerWebClippingView, coordinator: Coordinator) {
        let webView = container.webView
        container.onViewportLayout = nil
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
        private var assetPreview: (String) -> NSImage?
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
        private var payloadPreparationError: String?
        private var viewportSize: CGSize = .zero
        private var pendingViewportResizeNotification = false

        init(
            entries: [RichAnswerWebRuntimeEntry],
            evidenceByID: [String: RichAnswerEvidence],
            heightLimit: CGFloat,
            contentHeight: Binding<CGFloat>,
            contentOverflowed: Binding<Bool>,
            runtimeError: Binding<String?>,
            onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
            onAction: @escaping (String) -> Void,
            assetPreview: @escaping (String) -> NSImage?,
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
            self.assetPreview = assetPreview
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
            assetPreview: @escaping (String) -> NSImage?,
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
            self.assetPreview = assetPreview
            self.onRuntimeReady = onRuntimeReady
        }

        func sendEntriesIfReady() {
            payloadPreparationError = nil
            guard isReady,
                  hasUsableViewport,
                  let webView else { return }
            guard let payloads = runtimePayloads() else {
                if let payloadPreparationError {
                    reportRuntimeError(payloadPreparationError)
                }
                return
            }
            let jsonPayloads = payloads.compactMap(Self.jsonString)
            guard jsonPayloads.count == payloads.count,
                  let fingerprintData = try? JSONSerialization.data(withJSONObject: ["payloads": payloads], options: [.sortedKeys]),
                  let json = String(data: fingerprintData, encoding: .utf8),
                  sentPayloadFingerprint != json else { return }
            sentPayloadFingerprint = json
            runtimeError.wrappedValue = nil
            hasRuntimeHeight = false
            notifiedRuntimeReady = false
            heightUpdateWorkItem?.cancel()
            heightUpdateWorkItem = nil
            sendRuntimePayloads(jsonPayloads, using: webView)
        }

        func viewportDidLayout(_ size: CGSize) {
            let previousSize = viewportSize
            viewportSize = size
            if hasUsableViewport {
                sendEntriesIfReady()
            }
            guard sentPayloadFingerprint != nil,
                  abs(previousSize.width - size.width) >= 1 || abs(previousSize.height - size.height) >= 1 else { return }
            notifyRuntimeViewportChanged()
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
                sendEntriesIfReady()
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
                let diagnostic = body["message"] as? String ?? "富回答程序渲染失败。"
                if body["fatal"] as? Bool == false {
                    NSLog("[WeiBei rich answer] %@", diagnostic)
                } else {
                    reportRuntimeError(diagnostic)
                }
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
            reportRuntimeError("富回答运行时加载失败：\(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            readinessWorkItem?.cancel()
            reportRuntimeError("富回答运行时无法启动：\(error.localizedDescription)")
        }

        func failStartup(_ message: String) {
            readinessWorkItem?.cancel()
            reportRuntimeError(message)
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
                reportRuntimeError("富回答运行时未就绪，已停止等待。")
            }
            readinessWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
        }

        private func scheduleHeightRecovery(attempt: Int = 0) {
            heightRecoveryWorkItem?.cancel()
            guard isReady, hasUsableViewport, attempt < 5, !hasRuntimeHeight else { return }
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
                guard error == nil, Self.verificationInteractionStarted(value) else {
                    scheduleVerificationInteraction(requestID: requestID, attempt: attempt + 1)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    webView.evaluateJavaScript(Self.verificationInteractionResultScript) { value, error in
                        guard error == nil,
                              let receipt = Self.verificationInteractionReceipt(from: value, entries: self.entries),
                              receipt.changed else {
                            self.scheduleVerificationInteraction(requestID: requestID, attempt: attempt + 1)
                            return
                        }
                        RichAnswerVerificationBridge.writeInteractionReceipt(
                            sceneID: receipt.sceneID,
                            sceneTitle: receipt.sceneTitle,
                            target: receipt.target,
                            kind: receipt.kind,
                            before: receipt.before,
                            after: receipt.after,
                            changed: receipt.changed,
                            source: "web-runtime"
                        )
                    }
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
            guard !notifiedRuntimeReady, isReady, hasRuntimeHeight, runtimeError.wrappedValue == nil else { return }
            notifiedRuntimeReady = true
            onRuntimeReady()
        }

        private func reportRuntimeError(_ message: String) {
            NSLog("[WeiBei rich answer] %@", message)
            runtimeError.wrappedValue = message
            contentOverflowed.wrappedValue = false
        }

        private func fallbackContentHeight() -> CGFloat {
            let requested = entries.reduce(0) { $0 + $1.heightBudget }
            guard requested > 0 else { return 220 }
            return min(max(CGFloat(requested) * 0.58, 220), heightLimit)
        }

        private func runtimePayloads() -> [[String: Any]]? {
            guard !entries.isEmpty else { return nil }
            if entries.allSatisfy(\.isProgram) {
                guard let payload = programsPayload(for: entries) else { return nil }
                return [payload]
            }
            if entries.allSatisfy(\.isRenderPlan) {
                var groupBudget = RichAnswerRenderGroupBudgetAccumulator()
                guard let payload = renderPlansPayload(
                    for: entries.enumerated().map { (index: $0.offset, entry: $0.element) },
                    groupBudget: &groupBudget
                ) else { return nil }
                return [payload]
            }
            var groupBudget = RichAnswerRenderGroupBudgetAccumulator()
            let payloads = entries.enumerated().compactMap { index, entry -> [String: Any]? in
                switch entry.kind {
                case .program:
                    return programsPayload(for: [entry])
                case .renderPlan:
                    return renderPlansPayload(
                        for: [(index: index, entry: entry)],
                        groupBudget: &groupBudget
                    )
                }
            }
            guard !payloads.isEmpty else {
                payloadPreparationError = "富回答组没有可发送的合法项目。"
                return nil
            }
            return payloads
        }

        private func programsPayload(for entries: [RichAnswerWebRuntimeEntry]) -> [String: Any]? {
            let programs = entries.compactMap(programPayload)
            guard !programs.isEmpty, programs.count == entries.count else { return nil }
            if programs.count == 1 {
                return [
                    "type": "weibei:setProgram",
                    "program": programs[0],
                    "heightLimit": Int(heightLimit.rounded()),
                ]
            }
            return [
                "type": "weibei:setPrograms",
                "programs": programs,
                "heightLimit": Int(heightLimit.rounded()),
            ]
        }

        private func programPayload(for entry: RichAnswerWebRuntimeEntry) -> [String: Any]? {
            guard case let .program(program) = entry.kind else { return nil }
            let scene = entry.scene
            let evidenceBindings = evidenceBindings(for: scene)
            let evidenceContent = evidenceContent(for: scene)
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

        private struct RenderPlanTransport {
            let sourceIndex: Int
            let entry: RichAnswerWebRuntimeEntry
            let plan: [String: Any]
            let budgetContext: [String: Any]
        }

        private enum RenderPlanTransportResult {
            case ready(RenderPlanTransport)
            case failed(
                diagnostic: String,
                fallbackReason: String,
                fallbackText: String
            )
        }

        private func renderPlansPayload(
            for indexedEntries: [(index: Int, entry: RichAnswerWebRuntimeEntry)],
            groupBudget: inout RichAnswerRenderGroupBudgetAccumulator
        ) -> [String: Any]? {
            var transports: [RenderPlanTransport] = []
            var itemFailures: [[String: Any]] = []
            for indexedEntry in indexedEntries {
                let index = indexedEntry.index
                let entry = indexedEntry.entry
                switch renderPlanTransport(
                    for: entry,
                    sourceIndex: index,
                    groupBudget: &groupBudget
                ) {
                case let .ready(transport):
                    transports.append(transport)
                case let .failed(diagnostic, fallbackReason, fallbackText):
                    NSLog("[WeiBei rich answer] %@", diagnostic)
                    itemFailures.append([
                        "index": index,
                        "programID": entry.scene.id,
                        "title": entry.scene.title,
                        "fallbackReason": fallbackReason,
                        "fallbackText": fallbackText,
                    ])
                }
            }
            guard !transports.isEmpty else {
                return [
                    "type": "weibei:setRenderFailures",
                    "itemFailures": itemFailures,
                    "heightLimit": Int(heightLimit.rounded()),
                ]
            }
            let evidenceItems = indexedEntries.flatMap { indexedEntry in
                evidenceContent(for: indexedEntry.entry.scene)
            }
            if transports.count == 1 {
                return [
                    "type": "weibei:setRenderPlan",
                    "renderPlan": transports[0].plan,
                    "budgetContext": transports[0].budgetContext,
                    "sourceIndex": transports[0].sourceIndex,
                    "itemFailures": itemFailures,
                    "evidenceContent": evidenceItems,
                    "heightLimit": Int(heightLimit.rounded()),
                ]
            }
            return [
                "type": "weibei:setRenderPlans",
                "renderPlans": transports.map(\.plan),
                "budgetContexts": transports.map(\.budgetContext),
                "sourceIndices": transports.map(\.sourceIndex),
                "itemFailures": itemFailures,
                "evidenceContent": evidenceItems,
                "heightLimit": Int(heightLimit.rounded()),
            ]
        }

        private func renderPlanTransport(
            for entry: RichAnswerWebRuntimeEntry,
            sourceIndex: Int,
            groupBudget: inout RichAnswerRenderGroupBudgetAccumulator
        ) -> RenderPlanTransportResult {
            guard case let .renderPlan(renderPlan) = entry.kind else {
                return .failed(
                    diagnostic: "富回答项目不是渲染计划：\(entry.scene.id)",
                    fallbackReason: "这项视觉暂不可用",
                    fallbackText: "请继续阅读正文。"
                )
            }
            guard let logicalPlanData = try? JSONEncoder().encode(renderPlan),
                  var plan = try? JSONSerialization.jsonObject(with: logicalPlanData) as? [String: Any] else {
                return .failed(
                    diagnostic: "渲染计划无法编码：\(entry.scene.id)",
                    fallbackReason: renderPlan.fallback.reason,
                    fallbackText: renderPlan.fallback.text
                )
            }
            var trustedAssetBytes: [Int] = []
            let errors = bridgeLocalImageAssets(
                in: &plan,
                for: entry.scene,
                trustedAssetBytes: &trustedAssetBytes
            )
            if !errors.isEmpty {
                return .failed(
                    diagnostic: errors.joined(separator: "\n"),
                    fallbackReason: renderPlan.fallback.reason,
                    fallbackText: renderPlan.fallback.text
                )
            }
            if let issue = groupBudget.admit(
                logicalPlanBytes: logicalPlanData.count,
                trustedAssetBytes: trustedAssetBytes
            ) {
                return .failed(
                    diagnostic: "\(issue.diagnosticMessage)：\(entry.scene.id)",
                    fallbackReason: renderPlan.fallback.reason,
                    fallbackText: renderPlan.fallback.text
                )
            }
            return .ready(RenderPlanTransport(
                sourceIndex: sourceIndex,
                entry: entry,
                plan: plan,
                budgetContext: [
                    "logicalPlanBytes": logicalPlanData.count,
                    "trustedAssetBytes": trustedAssetBytes,
                ]
            ))
        }

        private func bridgeLocalImageAssets(
            in plan: inout [String: Any],
            for scene: RichAnswerScene,
            trustedAssetBytes: inout [Int]
        ) -> [String] {
            guard let renderer = plan["renderer"] as? String,
                  renderer == "weibei.image.overlay" || renderer == "weibei.spatial.map",
                  var spec = plan["spec"] as? [String: Any] else { return [] }

            let allowedAssetIDs = allowedAssetIDs(for: scene)
            var errors: [String] = []

            if renderer == "weibei.image.overlay" {
                bridgeImageSource(
                    at: ["image"],
                    in: &spec,
                    allowedAssetIDs: allowedAssetIDs,
                    errors: &errors,
                    trustedAssetBytes: &trustedAssetBytes
                )
                bridgeImageSource(
                    at: ["comparison", "image"],
                    in: &spec,
                    allowedAssetIDs: allowedAssetIDs,
                    errors: &errors,
                    trustedAssetBytes: &trustedAssetBytes
                )
            } else {
                bridgeImageSource(
                    at: ["mapAsset"],
                    in: &spec,
                    allowedAssetIDs: allowedAssetIDs,
                    errors: &errors,
                    trustedAssetBytes: &trustedAssetBytes
                )
            }

            plan["spec"] = spec
            return errors
        }

        private func allowedAssetIDs(for scene: RichAnswerScene) -> Set<String> {
            var ids = Set(scene.objects.compactMap(\.assetID))
            ids.formUnion(scene.frames.compactMap(\.assetID))
            for evidenceID in scene.evidenceIDs {
                guard let evidence = evidenceByID[evidenceID] else { continue }
                ids.formUnion(evidence.assetIDs)
            }
            return ids
        }

        private func bridgeImageSource(
            at path: [String],
            in spec: inout [String: Any],
            allowedAssetIDs: Set<String>,
            errors: inout [String],
            trustedAssetBytes: inout [Int]
        ) {
            guard path.count == 1 || path.count == 2 else { return }
            if path.count == 1 {
                guard var source = spec[path[0]] as? [String: Any] else { return }
                bridgeImageSourceObject(
                    &source,
                    path: "spec.\(path[0])",
                    allowedAssetIDs: allowedAssetIDs,
                    errors: &errors,
                    trustedAssetBytes: &trustedAssetBytes
                )
                spec[path[0]] = source
                return
            }

            guard var parent = spec[path[0]] as? [String: Any],
                  var source = parent[path[1]] as? [String: Any] else { return }
            bridgeImageSourceObject(
                &source,
                path: "spec.\(path[0]).\(path[1])",
                allowedAssetIDs: allowedAssetIDs,
                errors: &errors,
                trustedAssetBytes: &trustedAssetBytes
            )
            parent[path[1]] = source
            spec[path[0]] = parent
        }

        private func bridgeImageSourceObject(
            _ source: inout [String: Any],
            path: String,
            allowedAssetIDs: Set<String>,
            errors: inout [String],
            trustedAssetBytes: inout [Int]
        ) {
            guard source["kind"] as? String == "assetRef",
                  let assetID = (source["source"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !assetID.isEmpty,
                  allowedAssetIDs.contains(assetID) else { return }

            guard let image = assetPreview(assetID) else {
                errors.append("\(path) 引用的本地图片资产不可预览：\(assetID)")
                return
            }
            guard let embeddedRaster = Self.embeddedRaster(from: image) else {
                errors.append("\(path) 引用的本地图片资产无法压缩到安全内嵌预算：\(assetID)")
                return
            }

            source["kind"] = "dataUrl"
            source["source"] = "data:image/\(embeddedRaster.mimeSubtype);base64,\(embeddedRaster.data.base64EncodedString())"
            source["width"] = embeddedRaster.width
            source["height"] = embeddedRaster.height
            source["_weibeiHostInjected"] = true
            trustedAssetBytes.append(embeddedRaster.data.count)
        }

        private func evidenceBindings(for scene: RichAnswerScene) -> [[String: String]] {
            scene.evidenceIDs.compactMap { evidenceID -> [String: String]? in
                guard let evidence = evidenceByID[evidenceID] else { return nil }
                return [
                    "id": evidence.id,
                    "sourceID": evidence.sourceLabel,
                    "locator": evidence.sourceLabel,
                ]
            }
        }

        private func evidenceContent(for scene: RichAnswerScene) -> [[String: Any]] {
            scene.evidenceIDs.compactMap { evidenceID -> [String: Any]? in
                guard let evidence = evidenceByID[evidenceID] else { return nil }
                return [
                    "id": evidence.id,
                    "sourceLabel": evidence.sourceLabel,
                    "excerpt": evidence.excerpt,
                    "isTruncated": evidence.isTruncated,
                ]
            }
        }

        private func sendRuntimePayloads(_ jsonPayloads: [String], using webView: WKWebView, index: Int = 0) {
            guard index < jsonPayloads.count else {
                notifyRuntimeViewportChanged()
                scheduleHeightRecovery()
                return
            }
            webView.evaluateJavaScript("window.postMessage(\(jsonPayloads[index]), '*')") { [weak self, weak webView] _, error in
                guard let self else { return }
                if let error {
                    sentPayloadFingerprint = nil
                    reportRuntimeError("富回答内容传递失败：\(error.localizedDescription)")
                    return
                }
                guard let webView else { return }
                sendRuntimePayloads(jsonPayloads, using: webView, index: index + 1)
            }
        }

        private var hasUsableViewport: Bool {
            viewportSize.width >= 24 && viewportSize.height >= 24
        }

        private func notifyRuntimeViewportChanged() {
            guard let webView, !pendingViewportResizeNotification else { return }
            pendingViewportResizeNotification = true
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self else { return }
                pendingViewportResizeNotification = false
                webView?.evaluateJavaScript(Self.viewportResizeScript) { _, _ in }
            }
        }

        private struct EmbeddedRaster {
            let data: Data
            let mimeSubtype: String
            let width: Int
            let height: Int
        }

        private static let embeddedRasterMaxBytes =
            RichAnswerRendererRegistry.formalTrustedAssetMaxBytes

        private static func embeddedRaster(from image: NSImage) -> EmbeddedRaster? {
            var proposedRect = NSRect(origin: .zero, size: image.size)
            guard let sourceImage = image.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            ) else { return nil }

            let sourceWidth = sourceImage.width
            let sourceHeight = sourceImage.height
            let candidateDimensions = [1_800, 1_440, 1_200, 960].reduce(into: [(Int, Int)]()) { result, maxDimension in
                let scale = min(1, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
                let dimensions = (
                    max(1, Int((Double(sourceWidth) * scale).rounded())),
                    max(1, Int((Double(sourceHeight) * scale).rounded()))
                )
                if !result.contains(where: { $0 == dimensions }) {
                    result.append(dimensions)
                }
            }

            for (width, height) in candidateDimensions {
                if let transparentBitmap = rasterizedBitmap(
                    sourceImage,
                    width: width,
                    height: height,
                    background: nil
                ), let pngData = transparentBitmap.representation(using: .png, properties: [:]),
                   pngData.count <= embeddedRasterMaxBytes {
                    return EmbeddedRaster(data: pngData, mimeSubtype: "png", width: width, height: height)
                }

                guard let opaqueBitmap = rasterizedBitmap(
                    sourceImage,
                    width: width,
                    height: height,
                    background: .white
                ) else { continue }
                for compressionFactor in [0.86, 0.76, 0.66] {
                    guard let jpegData = opaqueBitmap.representation(
                        using: .jpeg,
                        properties: [.compressionFactor: compressionFactor]
                    ) else { continue }
                    if jpegData.count <= embeddedRasterMaxBytes {
                        return EmbeddedRaster(data: jpegData, mimeSubtype: "jpeg", width: width, height: height)
                    }
                }
            }

            return nil
        }

        private static func rasterizedBitmap(
            _ sourceImage: CGImage,
            width: Int,
            height: Int,
            background: NSColor?
        ) -> NSBitmapImageRep? {
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            context.cgContext.interpolationQuality = .high
            context.cgContext.clear(bounds)
            if let background {
                context.cgContext.setFillColor(background.cgColor)
                context.cgContext.fill(bounds)
            }
            context.cgContext.draw(sourceImage, in: bounds)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            return bitmap
        }

        private static func jsonString(from payload: [String: Any]) -> String? {
            guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
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

        private static let viewportResizeScript = """
        (() => {
          window.dispatchEvent(new Event("resize"));
          window.requestAnimationFrame(() => window.dispatchEvent(new Event("resize")));
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
          const labelOf = (element) => String(element?.getAttribute("aria-label") || element?.textContent || "").trim();
          const normalizedLabelOf = (element) => labelOf(element).toLowerCase();
          const controlName = (element) => String(element?.getAttribute("data-weibei-control") || "");
          const controlID = (element) => String(element?.getAttribute("data-weibei-control-id") || element?.id || labelOf(element) || "");
          const sceneContainerFor = (element) => element?.closest("[data-weibei-scene-id], [data-scene-id], .generation-answer__program, .generation-answer")
            || document.querySelector("[data-weibei-scene-id], [data-scene-id], .generation-answer__program, .generation-answer");
          const sceneIDFor = (element) => sceneContainerFor(element)?.getAttribute("data-weibei-scene-id")
            || sceneContainerFor(element)?.getAttribute("data-scene-id")
            || element?.getAttribute("data-weibei-scene-id")
            || "";
          const sceneTitleFor = (element) => sceneContainerFor(element)?.getAttribute("aria-label")
            || element?.closest(".generation-answer")?.getAttribute("aria-label")
            || document.querySelector(".generation-answer__program")?.getAttribute("aria-label")
            || document.querySelector(".generation-answer")?.getAttribute("aria-label")
            || document.title
            || "";
          const controlState = (element) => {
            if (!element) return {};
            return {
              control: controlName(element),
              controlID: controlID(element),
              tag: String(element.tagName || "").toLowerCase(),
              role: element.getAttribute("role") || "",
              label: labelOf(element),
              value: "value" in element ? String(element.value) : "",
              checked: "checked" in element ? Boolean(element.checked) : null,
              selected: element.getAttribute("aria-selected") || "",
              state: element.getAttribute("data-weibei-state") || "",
              disabled: Boolean(element.disabled || element.getAttribute("aria-disabled") === "true"),
              className: String(element.className || "")
            };
          };
          const stateSnapshot = () => Array.from(document.querySelectorAll("[data-weibei-control]"))
            .filter((element) => visible(element) || element.getAttribute("aria-selected") === "true")
            .map(controlState);
          const fingerprint = (value) => JSON.stringify(value);
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
          const first = (selectors, predicate = () => true) => {
            for (const selector of selectors) {
              const found = Array.from(document.querySelectorAll(selector)).find((element) => visible(element) && predicate(element));
              if (found) return found;
            }
            return null;
          };
          const byText = (selectors, patterns, rejectPatterns = []) => {
            const candidates = selectors.flatMap((selector) => Array.from(document.querySelectorAll(selector)));
            return candidates.find((element) => {
              if (!visible(element)) return false;
              const label = normalizedLabelOf(element);
              return patterns.some((pattern) => pattern.test(label)) && !rejectPatterns.some((pattern) => pattern.test(label));
            }) || null;
          };
          const advanceRange = (range) => {
            if (!range || !visible(range)) return false;
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
          const inactive = (element) => {
            if (element.disabled || element.getAttribute("aria-disabled") === "true") return false;
            if (element.getAttribute("aria-selected") === "true") return false;
            return !String(element.className || "").split(/\\s+/).some((name) => name === "is-active" || name === "is-selected");
          };
          const dataControl = (names, predicate = inactive) => first(
            names.map((name) => `[data-weibei-control="${name}"]`),
            predicate
          );
          const rangeControl = dataControl([
            "parameter-slider",
            "distribution-span-slider",
            "dependency-input-slider"
          ], (element) => element.matches('input[type="range"]'));
          const distributionInteraction = dataControl(["distribution-canvas"], () => true);
          const executionNext = dataControl(["execution-next"]) || first([
            '[data-action="execution-next"]',
            '[data-testid="execution-next"]',
            '[aria-label*="execution-next" i]',
            'button.execution-next',
            '.execution-controls button:not(:disabled):last-of-type',
            '.ra-execution-controls button:not(:disabled):last-of-type'
          ]) || byText(["button"], [/下一步|next|step/], [/上一步|previous|prev|back/]);
          const processStep = dataControl(["process-step"]) || first([
            '[data-action="process-next"]',
            '[data-testid="process-next"]',
            '.ra-process button:not(.is-active):not(.is-selected)',
            '.process-step button:not(.is-active):not(.is-selected)',
            '[role="listitem"] button:not(.is-active):not(.is-selected)'
          ]) || byText(["button"], [/过程|阶段|step|process/], [/reset|重置|证据|来源/]);
          const argumentUnit = dataControl(["argument-unit"]) || first([
            '.ra-argument-reader__copy button:not(.is-active)',
            '[data-component="ArgumentUnit"]:not(.is-active) button',
            '[data-role="ArgumentUnit"]:not(.is-active) button'
          ]);
          const causalEvent = dataControl(["causal-event"]) || first([
            '.ra-causal-track__rail button:not(.is-active):not(.is-selected)',
            '.policy-river button:not(.is-selected)',
            '[data-component="CausalEvent"]:not(.is-active) button',
            '[data-role="CausalEvent"]:not(.is-active) button'
          ]);
          const valueOption = dataControl(["value-picker-option"]) || first([
            '[role="option"]:not([aria-selected="true"])',
            '.value-picker button:not(.is-active):not(.is-selected)',
            '[data-component="ValuePicker"] button:not(.is-active):not(.is-selected)',
            '[data-role="value-option"]:not(.is-active):not(.is-selected)'
          ]);
          const spatialToggle = dataControl(["spatial-layer-toggle"], () => true) || first([
            '.ra-spatial-view__layers input[type="checkbox"]',
            '[data-component="SpatialToggle"] input[type="checkbox"]',
            '[data-role="spatial-toggle"] input[type="checkbox"]'
          ]);
          const imageOverlayLayer = dataControl(["image-overlay-layer"], (element) => {
            const checkbox = element.querySelector('input[type="checkbox"]');
            return Boolean(checkbox && !checkbox.disabled && !checkbox.checked);
          }) || dataControl(["image-overlay-layer"], () => true);
          const chartProbe = dataControl(["chart-probe"], () => true);
          const functionProbe = dataControl(["function-probe"], () => true);
          const declaredVerificationTarget = first(["[data-weibei-verify-event]"], () => true);
          const scene3DState = dataControl(["scene-3d-state"], (element) => {
            if (element.matches('input[type="range"]')) return true;
            return element.getAttribute("aria-pressed") !== "true";
          });
          const target = declaredVerificationTarget || distributionInteraction || rangeControl || executionNext || processStep || argumentUnit || causalEvent || valueOption || spatialToggle || imageOverlayLayer || scene3DState || functionProbe || chartProbe || first(['input[type="range"]']);
          const beforeState = stateSnapshot();
          const targetBefore = controlState(target);
          window.WeiBeiVerificationInteractionResult = null;
          let acted = false;
          if (target?.matches?.('input[type="range"]')) {
            acted = advanceRange(target);
          } else if (target?.getAttribute?.("data-weibei-verify-event")) {
            acted = target.dispatchEvent(new CustomEvent(target.getAttribute("data-weibei-verify-event"), { bubbles: true }));
          } else if (["chart-probe", "distribution-canvas", "function-probe"].includes(controlName(target))) {
            acted = target.dispatchEvent(new CustomEvent("weibei:verify-interaction", { bubbles: true }));
          } else {
            acted = press(target);
          }
          const finish = () => {
            const afterState = stateSnapshot();
            const targetAfter = controlState(target);
            window.WeiBeiVerificationInteractionResult = {
              ok: acted,
              changed: acted && fingerprint({ target: targetBefore, controls: beforeState }) !== fingerprint({ target: targetAfter, controls: afterState }),
              kind: controlName(target) || (target?.matches?.('input[type="range"]') ? "range" : "press"),
              sceneID: sceneIDFor(target),
              sceneTitle: sceneTitleFor(target),
              target: target ? {
                control: controlName(target),
                id: controlID(target),
                label: labelOf(target),
                tag: String(target.tagName || "").toLowerCase(),
                role: target.getAttribute("role") || ""
              } : {},
              before: {
                target: targetBefore,
                controls: beforeState
              },
              after: {
                target: targetAfter,
                controls: afterState
              }
            };
          };
          window.setTimeout(finish, 180);
          return { started: acted };
        })();
        """

        private static let verificationInteractionResultScript = """
        (() => window.WeiBeiVerificationInteractionResult || null)();
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

        private static func verificationInteractionReceipt(
            from value: Any?,
            entries: [RichAnswerWebRuntimeEntry]
        ) -> (
            sceneID: String,
            sceneTitle: String,
            target: [String: Any],
            kind: String,
            before: Any?,
            after: Any?,
            changed: Bool
        )? {
            guard let dictionary = value as? [String: Any] else { return nil }
            let sceneID = dictionary["sceneID"] as? String ?? ""
            let sceneTitle = dictionary["sceneTitle"] as? String ?? ""
            let titleMatches = entries.filter { $0.scene.title == sceneTitle }
            let entry = entries.first(where: { $0.scene.id == sceneID })
                ?? (titleMatches.count == 1 ? titleMatches[0] : nil)
                ?? (entries.count == 1 ? entries[0] : nil)
            guard let scene = entry?.scene else { return nil }
            let before = dictionary["before"]
            let after = dictionary["after"]
            return (
                sceneID: scene.id,
                sceneTitle: scene.title,
                target: dictionary["target"] as? [String: Any] ?? [:],
                kind: dictionary["kind"] as? String ?? "web-runtime",
                before: before,
                after: after,
                changed: RichAnswerVerificationBridge.changed(before, after)
            )
        }

        private static func verificationInteractionStarted(_ value: Any?) -> Bool {
            guard let dictionary = value as? [String: Any] else { return false }
            return dictionary["started"] as? Bool ?? false
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
