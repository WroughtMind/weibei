import SwiftUI
import WebKit
import WeiBeiCore
#if targetEnvironment(macCatalyst)
import UIKit
typealias WhiteboardRepresentable = UIViewRepresentable
#else
import AppKit
typealias WhiteboardRepresentable = NSViewRepresentable
#endif

struct WhiteboardCanvasView: WhiteboardRepresentable {
    @ObservedObject var classroom: WhiteboardClassroom
    var isDark: Bool
    func makeCoordinator() -> Coordinator { Coordinator(classroom) }
    private func makeWeb(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let url = WeiBeiResources.bundle.url(forResource: "whiteboard", withExtension: "html", subdirectory: "Editor") {
            configuration.userContentController.addScriptMessageHandler(WhiteboardVoiceResources(directory: url.deletingLastPathComponent()), contentWorld: .page, name: "voiceResource")
        }
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(coordinator, name: "whiteboard")
        configuration.userContentController.addUserScript(.init(source: "window.initialWhiteboardDark = \(isDark);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        coordinator.dark = isDark
        let web = WKWebView(frame: .zero, configuration: configuration)
        coordinator.web = web; web.navigationDelegate = coordinator
        guard let url = WeiBeiResources.bundle.url(forResource: "whiteboard", withExtension: "html", subdirectory: "Editor") else {
            classroom.fail("白板资源缺失，请重新构建应用。"); return web
        }
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return web
    }
    #if targetEnvironment(macCatalyst)
    func makeUIView(context: Context) -> WKWebView { makeWeb(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { context.coordinator.appearance(isDark) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { coordinator.close(view) }
    #else
    func makeNSView(context: Context) -> WKWebView { makeWeb(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.appearance(isDark) }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) { coordinator.close(view) }
    #endif
    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var classroom: WhiteboardClassroom?
        weak var web: WKWebView?
        var dark = false
        init(_ classroom: WhiteboardClassroom) { self.classroom = classroom }
        func appearance(_ value: Bool) {
            guard dark != value else { return }; dark = value
            send("setAppearance", ["dark": value])
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? [String: Any], message.frameInfo.isMainFrame else { return }
            if value["type"] as? String == "ready" {
                classroom?.attachRenderer { [weak self] method, arguments in self?.send(method, arguments) }
            } else if value["type"] as? String == "initialization_failed" {
                classroom?.fail("白板图示资源初始化失败：" + String(describing: value["message"] ?? ""))
            } else { classroom?.receive(value) }
        }
        private func send(_ method: String, _ values: [String: Any]) {
            let statements: [String: String] = [
                "restore": "return await window.WeiBeiWhiteboard.restore(actions, state, requestID)",
                "receive": "return await window.WeiBeiWhiteboard.receive(envelope)",
                "pause": "window.WeiBeiWhiteboard.pause(value)",
                "questionDisplayed": "window.WeiBeiWhiteboard.questionDisplayed(id)",
                "generationWaiting": "window.WeiBeiWhiteboard.generationWaiting(value)",
                "feedback": "window.WeiBeiWhiteboard.feedback(correct)",
                "supplement": "return await window.WeiBeiWhiteboard.supplement(action, replyID)",
                "setAppearance": "return await window.WeiBeiWhiteboard.setAppearance(dark)",
                "speechStarted": "window.WeiBeiWhiteboard.speechStarted(id)",
                "speechBoundary": "window.WeiBeiWhiteboard.speechBoundary(id, text, progress)",
                "speechFinished": "window.WeiBeiWhiteboard.speechFinished(id, error)"
            ]
            guard let code = statements[method], let web else { return }
            var arguments = values
            if method == "speechFinished", arguments["error"] == nil { arguments["error"] = NSNull() }
            Task { @MainActor [weak self] in
                do { _ = try await web.callAsyncJavaScript(code, arguments: arguments, in: nil, contentWorld: .page) }
                catch {
                    let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                    if !detail.contains("课堂已切换") { self?.classroom?.fail("白板执行失败：\(detail)") }
                }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.isFileURL == true ? .allow : .cancel
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [weak self] in
                do {
                    let result = try await webView.callAsyncJavaScript("await window.WeiBeiWhiteboardBoot; return typeof window.WeiBeiWhiteboard === 'object'", arguments: [:], in: nil, contentWorld: .page)
                    if result as? Bool != true { self?.classroom?.fail("白板网页未能初始化，请检查应用资源。") }
                } catch { self?.classroom?.fail("白板网页未能初始化：\(error.localizedDescription)") }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            classroom?.fail("白板加载失败：\(error.localizedDescription)")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            classroom?.fail("白板加载失败：\(error.localizedDescription)")
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            classroom?.fail("白板渲染进程中断。已保存进度，正在恢复。"); webView.reload()
        }
        func close(_ web: WKWebView) { classroom?.close(); web.stopLoading(); web.loadHTMLString("", baseURL: nil); web.configuration.userContentController.removeScriptMessageHandler(forName: "whiteboard") }
    }
}
