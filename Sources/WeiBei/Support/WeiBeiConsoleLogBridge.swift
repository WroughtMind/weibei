import WebKit
import WeiBeiCore

/// 网页 console.error / error 事件 / unhandledrejection 的统一报错桥。
/// 无状态：只持 surface 一个值类型，不持有任何视图/webview（无保留环）。
/// 严格不记用户正文/课程/笔记内容；网页报错文本例外可记，Swift 侧对
/// detail 再截断一次（防御 JS 侧被绕过）。
final class WeiBeiConsoleLogBridge: NSObject, WKScriptMessageHandler {
    private let surface: WeiBeiWebSurface

    init(surface: WeiBeiWebSurface) {
        self.surface = surface
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "weibeiConsoleError",
              let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else { return }
        let detail = (body["detail"] as? String) ?? ""
        WeiBeiLog.web.error(
            "web_console_error surface=\(self.surface.rawValue, privacy: .public) kind=\(kind, privacy: .public) detail=\(WeiBeiLog.truncated(detail), privacy: .public)"
        )
    }
}
