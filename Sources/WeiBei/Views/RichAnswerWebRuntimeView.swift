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
        assetPreview: @escaping (String) -> NSImage? = { _ in nil }
    ) {
        entries = [RichAnswerWebRuntimeEntry(scene: scene, program: program)]
        self.evidenceByID = evidenceByID
        self.expandsOverflow = expandsOverflow
        self.onRequestExpansion = onRequestExpansion
        self.onOpenEvidence = onOpenEvidence
        self.onAction = onAction
        self.assetPreview = assetPreview
    }

    init(
        scene: RichAnswerScene,
        renderPlan: RichAnswerRenderPlan,
        evidenceByID: [String: RichAnswerEvidence],
        expandsOverflow: Bool = false,
        onRequestExpansion: (() -> Void)? = nil,
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
        onAction: @escaping (String) -> Void,
        assetPreview: @escaping (String) -> NSImage? = { _ in nil }
    ) {
        entries = [RichAnswerWebRuntimeEntry(scene: scene, renderPlan: renderPlan)]
        self.evidenceByID = evidenceByID
        self.expandsOverflow = expandsOverflow
        self.onRequestExpansion = onRequestExpansion
        self.onOpenEvidence = onOpenEvidence
        self.onAction = onAction
        self.assetPreview = assetPreview
    }

    init(
        scenes: [RichAnswerScene],
        evidenceByID: [String: RichAnswerEvidence],
        expandsOverflow: Bool = false,
        onRequestExpansion: (() -> Void)? = nil,
        onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
        onAction: @escaping (String) -> Void,
        assetPreview: @escaping (String) -> NSImage? = { _ in nil }
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
                onOpenEvidence: onOpenEvidence,
                onAction: onAction,
                assetPreview: assetPreview
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: runtimeError == nil ? renderedHeight : 0)
            .clipped()
            .accessibilityHidden(runtimeError != nil)

            if runtimeError != nil {
                VStack(alignment: .leading, spacing: 3) {
                    Label("这项富回答无法显示", systemImage: "exclamationmark.triangle")
                        .weiBeiText(11, weight: .semibold)
                    Text("请继续阅读正文，稍后可重试这项视觉。")
                        .weiBeiText(10)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                .accessibilityElement(children: .combine)
            }

            if runtimeError == nil, contentOverflowed, !expandsOverflow, let onRequestExpansion {
                Button {
                    onRequestExpansion()
                } label: {
                    Label("放大操作", systemImage: "arrow.up.left.and.arrow.down.right")
                        .weiBeiText(11, weight: .medium)
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
    }

    private var heightLimit: CGFloat {
        5_000
    }

    private var renderedHeight: CGFloat {
        min(max(contentHeight, 160), heightLimit)
    }
}

final class ConversationWebClippingView: NSView {
    let webView: WKWebView
    var onViewportLayout: ((CGSize) -> Void)?
    private var scrollWheelMonitor: Any?

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

    deinit {
        removeScrollWheelMonitor()
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
        updateScrollWheelMonitor()
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

    /// Let the conversation ScrollView own vertical wheel — embedded web UI is not a nested scroller.
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
           let outer = nearestConversationScrollView() {
            outer.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func updateScrollWheelMonitor() {
        guard window != nil else {
            removeScrollWheelMonitor()
            return
        }
        guard scrollWheelMonitor == nil else { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self,
                  event.window === window,
                  abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
                  let contentView = window?.contentView,
                  let hitView = contentView.hitTest(
                      contentView.convert(event.locationInWindow, from: nil)
                  ),
                  hitView === self || hitView.isDescendant(of: self),
                  let outer = nearestConversationScrollView() else {
                return event
            }
            outer.scrollWheel(with: event)
            return nil
        }
    }

    private func removeScrollWheelMonitor() {
        guard let scrollWheelMonitor else { return }
        NSEvent.removeMonitor(scrollWheelMonitor)
        self.scrollWheelMonitor = nil
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
    /// App-wide text tier multiplier; the runtime's CSS consumes it through the
    /// `--weibei-text-scale` variable and re-reports height via ResizeObserver.
    @Environment(\.weiBeiTextScale) private var textScale
    let entries: [RichAnswerWebRuntimeEntry]
    let evidenceByID: [String: RichAnswerEvidence]
    let heightLimit: CGFloat
    @Binding var contentHeight: CGFloat
    @Binding var contentOverflowed: Bool
    @Binding var runtimeError: String?
    var onOpenEvidence: (RichAnswerEvidence) -> Void
    var onAction: (String) -> Void
    var assetPreview: (String) -> NSImage?

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
            assetPreview: assetPreview
        )
    }

    func makeNSView(context: Context) -> ConversationWebClippingView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.messageHandlerName)
        controller.addUserScript(
            WKUserScript(
                source: Self.bootstrapScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        controller.addUserScript(
            WKUserScript(
                source: "document.documentElement.style.setProperty('--weibei-text-scale', '\(textScale)');",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let configuration = WeiBeiWebViewConfiguration.make(
            surface: .richAnswer,
            allowingInlineMedia: false,
            nonPersistent: true
        )
        configuration.userContentController = controller
        WeiBeiWebViewConfiguration.installConsoleErrorBridge(on: controller, surface: .richAnswer)
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
        let clippingView = ConversationWebClippingView(webView: webView)
        context.coordinator.clippingView = clippingView
        clippingView.onViewportLayout = { [weak coordinator = context.coordinator] size in
            coordinator?.viewportDidLayout(size)
        }

        guard let entryURL = WeiBeiResources.bundle.url(
            forResource: "rich-answer",
            withExtension: "html"
        ) else {
            runtimeError = "富回答网页运行时资源缺失。"
            WeiBeiLog.richAnswer.error("rich_answer_runtime_resource_error detail=\(WeiBeiLog.truncated(runtimeError ?? "unknown"), privacy: .public)")
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

    func updateNSView(_ container: ConversationWebClippingView, context: Context) {
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
            textScale: textScale
        )
        context.coordinator.sendEntriesIfReady()
    }

    static func dismantleNSView(_ container: ConversationWebClippingView, coordinator: Coordinator) {
        let webView = container.webView
        container.onViewportLayout = nil
        coordinator.stop()
        // Phase 4：闲置回收——卸下时清空页面，释放 JS 堆。
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
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
        weak var clippingView: ConversationWebClippingView?
        private var entries: [RichAnswerWebRuntimeEntry]
        private var evidenceByID: [String: RichAnswerEvidence]
        private var heightLimit: CGFloat
        private var contentHeight: Binding<CGFloat>
        private var contentOverflowed: Binding<Bool>
        private var runtimeError: Binding<String?>
        private var onOpenEvidence: (RichAnswerEvidence) -> Void
        private var onAction: (String) -> Void
        private var assetPreview: (String) -> NSImage?
        private var isReady = false
        private var notifiedRuntimeReady = false
        private var sentPayloadFingerprint: String?
        private var readinessWorkItem: DispatchWorkItem?
        private var heightRecoveryWorkItem: DispatchWorkItem?
        private var heightUpdateWorkItem: DispatchWorkItem?
        private var hasRuntimeHeight = false
        private var payloadPreparationError: String?
        private var viewportSize: CGSize = .zero
        private var pendingViewportResizeNotification = false
        private var textScale: CGFloat = 1

        init(
            entries: [RichAnswerWebRuntimeEntry],
            evidenceByID: [String: RichAnswerEvidence],
            heightLimit: CGFloat,
            contentHeight: Binding<CGFloat>,
            contentOverflowed: Binding<Bool>,
            runtimeError: Binding<String?>,
            onOpenEvidence: @escaping (RichAnswerEvidence) -> Void,
            onAction: @escaping (String) -> Void,
            assetPreview: @escaping (String) -> NSImage?
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
            textScale: CGFloat
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
            if self.textScale != textScale {
                self.textScale = textScale
                applyTextScale()
            }
        }

        /// Live text-tier sync: the runtime's stylesheet multiplies every font
        /// size by `--weibei-text-scale`; its ResizeObserver re-reports height.
        private func applyTextScale() {
            guard isReady, let webView, textScale > 0 else { return }
            webView.evaluateJavaScript(
                "document.documentElement.style.setProperty('--weibei-text-scale', '\(textScale)')"
            )
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
                applyTextScale()
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
                    WeiBeiLog.richAnswer.error("rich_answer_page_diagnostic detail=\(WeiBeiLog.truncated(diagnostic), privacy: .public)")
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
        }

        private func reportRuntimeError(_ message: String) {
            WeiBeiLog.richAnswer.error("rich_answer_bridge_message detail=\(WeiBeiLog.truncated(message), privacy: .public)")
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
                    WeiBeiLog.richAnswer.error("rich_answer_page_diagnostic detail=\(WeiBeiLog.truncated(diagnostic), privacy: .public)")
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
                // S6-8：单图失败不阻断整份导出/渲染。
                return
            }
            // 先压缩；失败则原样内嵌（可超预算），继续其余资产。
            let embeddedRaster = Self.embeddedRaster(from: image)
                ?? Self.embeddedRasterUncompressed(from: image)
            guard let embeddedRaster else { return }

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

        /// S6-8：压缩失败时的原样 PNG 回退（可超过安全预算）。
        private static func embeddedRasterUncompressed(from image: NSImage) -> EmbeddedRaster? {
            var proposedRect = NSRect(origin: .zero, size: image.size)
            guard let sourceImage = image.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            ) else { return nil }
            let width = max(1, sourceImage.width)
            let height = max(1, sourceImage.height)
            guard let bitmap = rasterizedBitmap(
                sourceImage,
                width: min(width, 2_400),
                height: min(height, 2_400),
                background: nil
            ),
            let pngData = bitmap.representation(using: .png, properties: [:])
            else { return nil }
            return EmbeddedRaster(
                data: pngData,
                mimeSubtype: "png",
                width: bitmap.pixelsWide,
                height: bitmap.pixelsHigh
            )
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
