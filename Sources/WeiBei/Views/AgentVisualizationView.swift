import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import WeiBeiCore

struct AgentVisualizationLoadState: Equatable {
    private(set) var attempt = 0
    private(set) var failure: String?

    mutating func fail(_ message: String, from failedAttempt: Int) {
        guard failedAttempt == attempt else { return }
        if attempt == 0 {
            attempt = 1
        } else {
            failure = message
        }
    }

    mutating func reload() {
        failure = nil
        attempt += 1
    }
}

struct AgentVisualizationView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let messageID: UUID
    let visualization: AgentVisualization

    @State private var contentHeight: CGFloat = 180
    @State private var loadState = AgentVisualizationLoadState()
    @State private var showsRawData = false
    /// Phase 4：离开可视区域时卸下 WebView，回到时再创建。
    @State private var webViewAttached = true

    var body: some View {
        Group {
            if let runtimeFailure = loadState.failure {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.ui("互动界面暂时无法显示", "The interactive view could not be displayed"))
                        .weiBeiText(11, weight: .semibold)
                    Text(runtimeFailure)
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Button(store.ui("重新加载", "Reload")) {
                            loadState.reload()
                            showsRawData = false
                        }
                        Button(store.ui(showsRawData ? "收起原始数据" : "查看原始数据", showsRawData ? "Hide raw data" : "View raw data")) {
                            showsRawData.toggle()
                        }
                        Button(store.ui("复制错误", "Copy error")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(runtimeFailure, forType: .string)
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                    if showsRawData {
                        ScrollView(.horizontal) {
                            Text(visualization.specJSON)
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 160)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else if webViewAttached {
                AgentVisualizationWebView(
                    visualization: visualization,
                    appearance: store.appearanceMode.isDark ? "dark" : "light",
                    loadAttempt: loadState.attempt,
                    actionStatus: store.isAgentRunningInActiveChat ? "processing" : "ready",
                    actionUnavailableReason: actionUnavailableReason,
                    onHeight: { contentHeight = $0 },
                    onState: { stateJSON in
                        store.saveAgentVisualizationState(
                            messageID: messageID,
                            visualizationID: visualization.id,
                            stateJSON: stateJSON
                        )
                    },
                    onAction: { action, payloadJSON in
                        store.submitAgentVisualizationAction(action, payloadJSON: payloadJSON)
                    },
                    onFailure: handleFailure
                )
                .id(loadState.attempt)
                .frame(height: max(contentHeight, 120))
            } else {
                Color.clear.frame(height: max(contentHeight, 120))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.58), lineWidth: 1)
        }
        .onAppear { webViewAttached = true }
        .onDisappear { webViewAttached = false }
    }

    private var actionUnavailableReason: String? {
        if store.isStoppingAgent {
            return store.ui("正在停止上一条回答，请稍候。", "The previous response is stopping. Please wait.")
        }
        if store.isAskingAgent {
            return store.isAgentRunningInActiveChat
                ? store.ui("这个互动操作正在处理中。", "This interactive action is being processed.")
                : store.ui("另一条对话正在回答，结束后才能继续。", "Another chat is responding. Wait for it to finish.")
        }
        return nil
    }

    private func handleFailure(_ failedAttempt: Int, _ message: String) {
        Task { @MainActor in
            loadState.fail(message, from: failedAttempt)
        }
    }
}

private struct AgentVisualizationWebView: NSViewRepresentable {
    var visualization: AgentVisualization
    var appearance: String
    var loadAttempt: Int
    var actionStatus: String
    var actionUnavailableReason: String?
    var onHeight: (CGFloat) -> Void
    var onState: (String) -> Void
    var onAction: (String, String) -> String?
    var onFailure: (Int, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ConversationWebClippingView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.handlerName)

        let configuration = WeiBeiWebViewConfiguration.make(
            surface: .genui,
            allowingInlineMedia: false,
            nonPersistent: true
        )
        configuration.userContentController = controller
        WeiBeiWebViewConfiguration.installConsoleErrorBridge(on: controller, surface: .genui)

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        view.allowsLinkPreview = false
        context.coordinator.webView = view

        guard let entry = WeiBeiResources.bundle.url(
            forResource: "genui",
            withExtension: "html"
        ) else {
            onFailure(loadAttempt, "互动界面运行文件缺失（genui.html missing）")
            return ConversationWebClippingView(webView: view)
        }
        view.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent())
        return ConversationWebClippingView(webView: view)
    }

    func updateNSView(_ container: ConversationWebClippingView, context: Context) {
        context.coordinator.update(parent: self)
        context.coordinator.renderIfReady()
    }

    static func dismantleNSView(_ container: ConversationWebClippingView, coordinator: Coordinator) {
        let view = container.webView
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        view.configuration.userContentController.removeScriptMessageHandler(
            forName: Coordinator.handlerName
        )
        view.navigationDelegate = nil
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let handlerName = "weibeiGenUI"

        weak var webView: WKWebView?
        private var parent: AgentVisualizationWebView
        private var isReady = false
        private var sentFingerprint: String?

        init(parent: AgentVisualizationWebView) {
            self.parent = parent
        }

        func update(parent: AgentVisualizationWebView) {
            self.parent = parent
        }

        func renderIfReady() {
            guard isReady, let webView else { return }
            guard let spec = try? JSONSerialization.jsonObject(
                with: Data(parent.visualization.specJSON.utf8)
            ) as? [String: Any] else {
                parent.onFailure(parent.loadAttempt, "互动图原始数据不是有效的 JSON")
                return
            }
            let fingerprint = [
                parent.visualization.specJSON,
                parent.appearance,
                parent.actionStatus,
                parent.actionUnavailableReason ?? "",
            ].joined(separator: "|")
            guard fingerprint != sentFingerprint else { return }

            var payload: [String: Any] = [
                "spec": spec,
                "appearance": parent.appearance,
                "actionStatus": parent.actionStatus,
            ]
            payload["actionUnavailableReason"] = parent.actionUnavailableReason
            if let stateJSON = parent.visualization.stateJSON,
               let state = try? JSONSerialization.jsonObject(
                   with: Data(stateJSON.utf8),
                   options: .fragmentsAllowed
               ) {
                payload["state"] = state
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else {
                parent.onFailure(parent.loadAttempt, "互动图数据无法编码")
                return
            }
            sentFingerprint = fingerprint
            webView.evaluateJavaScript("window.WeiBeiGenUIHost.render(\(json))") { [weak self] _, error in
                if let error {
                    guard let self else { return }
                    self.parent.onFailure(self.parent.loadAttempt, error.localizedDescription)
                }
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == Self.handlerName,
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                if let webView {
                    WeiBeiQuietScrollers.configureRecursively(
                        in: webView,
                        hasVerticalScroller: false,
                        hasHorizontalScroller: false
                    )
                }
                isReady = true
                sentFingerprint = nil
                renderIfReady()
            case "height":
                guard let value = body["height"] as? NSNumber,
                      value.doubleValue.isFinite else { return }
                parent.onHeight(max(CGFloat(value.doubleValue), 120))
            case "state":
                guard let state = body["state"],
                      let data = try? JSONSerialization.data(
                          withJSONObject: state,
                          options: [.sortedKeys]
                      ),
                      data.count <= 262_144,
                      let json = String(data: data, encoding: .utf8) else { return }
                parent.onState(json)
            case "action":
                guard let requestID = body["requestID"] as? NSNumber else { return }
                let rejection: String?
                if let action = body["action"] as? String,
                   let payload = body["payload"],
                   let data = try? JSONSerialization.data(
                       withJSONObject: payload,
                       options: [.sortedKeys]
                   ),
                   let json = String(data: data, encoding: .utf8) {
                    rejection = parent.onAction(action, json)
                } else {
                    rejection = "互动数据无法读取，未提交回答。"
                }
                var result: [String: Any] = [
                    "requestID": requestID,
                    "accepted": rejection == nil,
                ]
                result["reason"] = rejection
                guard let data = try? JSONSerialization.data(withJSONObject: result),
                      let json = String(data: data, encoding: .utf8) else { return }
                webView?.evaluateJavaScript("window.WeiBeiGenUIHost.actionResult(\(json))")
            case "error":
                parent.onFailure(
                    parent.loadAttempt,
                    body["message"] as? String ?? "互动界面运行错误"
                )
            default:
                break
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let allowed = navigationAction.request.url?.isFileURL == true
                && navigationAction.targetFrame?.isMainFrame != false
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onFailure(parent.loadAttempt, error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onFailure(parent.loadAttempt, error.localizedDescription)
        }
    }
}

struct UnavailableAgentContentBlockView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let type: String
    let rawJSON: String
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.ui("这里原有互动内容，但当前无法读取。原始数据仍已保留。", "Interactive content was here, but it cannot currently be read. Its raw data is still preserved."))
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Text(store.ui("类型：\(type)", "Type: \(type)"))
                .weiBeiText(10)
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            Button(store.ui("导出原始数据", "Export raw data"), action: exportRawData)
                .buttonStyle(WeiBeiTextActionButtonStyle())
            if let exportError {
                Text(exportError)
                    .weiBeiText(10)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WeiBeiTheme.paperInset.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.58), lineWidth: 1)
        }
    }

    private func exportRawData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = store.ui("互动内容原始数据.json", "interactive-content-raw.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(rawJSON.utf8).write(to: url, options: .atomic)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}
