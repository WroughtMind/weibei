import WebKit

/// 四个 WebKit 面的标记，报错桥用它归类日志。
enum WeiBeiWebSurface: String {
    case reader, editor, richAnswer, genui
}

/// Shared WebKit configuration helpers (performance Phase 4).
///
/// Note: `WKProcessPool` is deprecated on modern macOS and no longer isolates
/// processes. We still centralize configuration so secondary surfaces share
/// consistent JS / media defaults without scattering setup code.
enum WeiBeiWebViewConfiguration {
    static func make(
        surface: WeiBeiWebSurface,
        allowingInlineMedia: Bool = true,
        nonPersistent: Bool = false
    ) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        if nonPersistent {
            configuration.websiteDataStore = .nonPersistent()
        }
        configuration.suppressesIncrementalRendering = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        if allowingInlineMedia {
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.preferences.isElementFullscreenEnabled = true
        }
        configuration.userContentController.add(
            WeiBeiConsoleLogBridge(surface: surface),
            name: "weibeiConsoleError"
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: consoleErrorBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        return configuration
    }

    /// 供整体替换 `userContentController` 的调用方在替换后补注入报错桥，
    /// 保证四个面都覆盖（replace 后的 controller 是全新实例，make() 里的
    /// 注入会被丢弃）。
    static func installConsoleErrorBridge(
        on controller: WKUserContentController,
        surface: WeiBeiWebSurface
    ) {
        controller.add(WeiBeiConsoleLogBridge(surface: surface), name: "weibeiConsoleError")
        controller.addUserScript(
            WKUserScript(
                source: consoleErrorBridgeScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
    }

    /// 网页 console.error / error 事件 / unhandledrejection → Swift 报错桥。
    /// IIFE 包裹；转发前检查 messageHandlers 存在，非 WebKit 环境静默降级；
    /// 不桥 console.log/info/warn（噪音）；JS 侧先截断到 500 字符再 postMessage。
    private static let consoleErrorBridgeScript = """
    (function () {
      var truncate = function (s) {
        s = String(s == null ? "" : s);
        return s.length > 500 ? s.slice(0, 500) + "…" : s;
      };
      var forward = function (kind, detail) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.weibeiConsoleError) {
            window.webkit.messageHandlers.weibeiConsoleError.postMessage({ kind: kind, detail: truncate(detail) });
          }
        } catch (e) {}
      };
      var originalError = console.error;
      console.error = function () {
        try {
          originalError.apply(console, arguments);
          var parts = [];
          for (var i = 0; i < arguments.length; i++) {
            try {
              parts.push(typeof arguments[i] === "string" ? arguments[i] : JSON.stringify(arguments[i]));
            } catch (e) {
              parts.push(String(arguments[i]));
            }
          }
          forward("console", parts.join(" "));
        } catch (e) {}
      };
      window.addEventListener("error", function (event) {
        forward("page", (event.message || "") + " @ " + (event.filename || "") + ":" + (event.lineno || 0));
      });
      window.addEventListener("unhandledrejection", function (event) {
        var reason = event.reason;
        var detail = "";
        try { detail = reason && reason.stack ? reason.stack : String(reason); } catch (e) { detail = String(reason); }
        forward("rejection", detail);
      });
    })();
    """
}
