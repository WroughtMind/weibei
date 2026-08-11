import SwiftUI
import WebKit
import WeiBeiCore

struct AgentVisualizationView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let messageID: UUID
    let visualization: AgentVisualization

    @State private var contentHeight: CGFloat = 180
    @State private var runtimeFailed = false
    /// Phase 4：离开可视区域时卸下 WebView，回到时再创建。
    @State private var webViewAttached = true

    var body: some View {
        Group {
            if runtimeFailed {
                Text(store.ui("互动界面暂时无法显示", "The interactive view could not be displayed"))
                    .font(.caption)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else if webViewAttached {
                AgentVisualizationWebView(
                    visualization: visualization,
                    appearance: store.appearanceMode.isDark ? "dark" : "light",
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
                    onFailure: { runtimeFailed = true }
                )
                .frame(height: max(contentHeight, 120))
            } else {
                Color.clear.frame(height: max(contentHeight, 120))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(WeiBeiTheme.hairline.opacity(0.58), lineWidth: 1)
        }
        .onAppear { webViewAttached = true }
        .onDisappear { webViewAttached = false }
    }
}

private struct AgentVisualizationWebView: NSViewRepresentable {
    var visualization: AgentVisualization
    var appearance: String
    var onHeight: (CGFloat) -> Void
    var onState: (String) -> Void
    var onAction: (String, String) -> Void
    var onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.handlerName)

        let configuration = WeiBeiWebViewConfiguration.make(
            allowingInlineMedia: false,
            nonPersistent: true
        )
        configuration.userContentController = controller

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
            onFailure()
            return view
        }
        view.loadFileURL(entry, allowingReadAccessTo: entry.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.update(parent: self)
        context.coordinator.renderIfReady()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
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
            guard isReady,
                  let webView,
                  let spec = try? JSONSerialization.jsonObject(
                      with: Data(parent.visualization.specJSON.utf8)
                  ) as? [String: Any] else { return }
            let fingerprint = parent.visualization.specJSON + "|" + parent.appearance
            guard fingerprint != sentFingerprint else { return }

            var payload: [String: Any] = [
                "spec": spec,
                "appearance": parent.appearance,
            ]
            if let stateJSON = parent.visualization.stateJSON,
               let state = try? JSONSerialization.jsonObject(
                   with: Data(stateJSON.utf8),
                   options: .fragmentsAllowed
               ) {
                payload["state"] = state
            }
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else {
                parent.onFailure()
                return
            }
            sentFingerprint = fingerprint
            webView.evaluateJavaScript("window.WeiBeiGenUIHost.render(\(json))") { [weak self] _, error in
                if error != nil {
                    self?.parent.onFailure()
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
                guard let action = body["action"] as? String,
                      let payload = body["payload"],
                      let data = try? JSONSerialization.data(
                          withJSONObject: payload,
                          options: [.sortedKeys]
                      ),
                      data.count <= 65_536,
                      let json = String(data: data, encoding: .utf8) else { return }
                parent.onAction(action, json)
            case "error":
                parent.onFailure()
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
            parent.onFailure()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            parent.onFailure()
        }
    }
}
