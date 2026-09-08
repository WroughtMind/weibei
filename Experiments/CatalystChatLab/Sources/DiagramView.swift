import UIKit
import WebKit

final class DiagramView: UIView, WKNavigationDelegate {
    private var web: WKWebView!
    private var source = ""
    private var generation = 0
    private var ready = false
    private(set) var measuredHeight: CGFloat = 200
    var heightChanged: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(DiagramSizeHandler(self), name: "size")
        web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = true
        web.accessibilityLabel = "可横向阅读的关系图"
        addSubview(web)
        guard let url = Bundle.main.url(forResource: "diagram", withExtension: "html", subdirectory: "Web") else {
            preconditionFailure("Bundled diagram runtime is missing")
        }
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() { super.layoutSubviews(); web.frame = bounds }
    func display(_ value: String) {
        guard value != source else { return }
        source = value
        generation += 1
        render()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render() }
    private func render() {
        guard ready else { return }
        Task {
            do {
                _ = try await web.callAsyncJavaScript("await renderDiagram(source, generation)", arguments: ["source": source, "generation": generation],
                                                     in: nil, contentWorld: .page)
            } catch { web.accessibilityLabel = "关系图渲染失败：" + error.localizedDescription }
        }
    }
    fileprivate func receive(_ body: Any) {
        guard let result = body as? [String: Any], result["generation"] as? Int == generation,
              let height = result["height"] as? Double, height.isFinite, height > 0 else { return }
        if abs(measuredHeight - height) > 1 { measuredHeight = height; heightChanged?() }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.isFileURL == true ? .allow : .cancel
    }
}

private final class DiagramSizeHandler: NSObject, WKScriptMessageHandler {
    weak var view: DiagramView?
    init(_ view: DiagramView) { self.view = view }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        view?.receive(message.body)
    }
}
