import AppKit
import Foundation
import WebKit
import WeiBeiCore

@MainActor
private final class RichAnswerWebRuntimeHarness: NSObject, WKScriptMessageHandler {
    private let webView: WKWebView
    private var messages: [[String: Any]] = []
    private var failure: String?

    override init() {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: "window.__WEIBEI_EMBEDDED__ = true;",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 420, height: 760), configuration: configuration)
        super.init()
        controller.add(self, name: "weibeiRichAnswer")
    }

    func run(repositoryURL: URL) {
        let entryURL = repositoryURL.appendingPathComponent("Sources/WeiBei/Resources/rich-answer.html")
        webView.loadFileURL(entryURL, allowingReadAccessTo: entryURL.deletingLastPathComponent())
        expect(wait(until: { self.hasMessage("weibei:ready") }, timeout: 15), "the built rich-answer runtime sends its ready handshake")

        guard let payload = payloadJSON() else {
            expect(false, "the rich-answer runtime probe payload can be encoded")
            return
        }
        evaluate("window.postMessage(\(payload), '*')")
        expect(wait(until: { self.hasMessage("weibei:height") }, timeout: 15), "the built rich-answer runtime reports its measured height")
        expect(waitForJavaScript("document.querySelectorAll('.generation-answer__program').length === 2 && document.querySelectorAll('.ra-root').length === 2", timeout: 15), "multiple generated scenes render inside one WebKit runtime")
        let plottedCurveCondition = """
        (() => {
          const canvas = document.querySelector('.ra-plot canvas');
          if (!(canvas instanceof HTMLCanvasElement) || canvas.width === 0 || canvas.height === 0) return false;
          const context = canvas.getContext('2d');
          if (!context) return false;
          const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
          let curvePixels = 0;
          for (let index = 0; index < pixels.length; index += 4) {
            const red = pixels[index];
            const green = pixels[index + 1];
            const blue = pixels[index + 2];
            const alpha = pixels[index + 3];
            if (alpha > 180 && red >= 125 && red <= 165 && green >= 45 && green <= 85 && blue >= 30 && blue <= 70) {
              curvePixels += 1;
              if (curvePixels > 80) return true;
            }
          }
          return false;
        })()
        """
        expect(waitForJavaScript(plottedCurveCondition, timeout: 15), "embedded WebKit draws the actual function curve instead of only an empty coordinate grid")

        let metricsScript = """
        JSON.stringify((() => {
          const status = document.querySelector('.generation-answer__status');
          return {
            embedded: document.documentElement.classList.contains('weibei-embedded'),
            proofbars: document.querySelectorAll('.generation-proofbar').length,
            sourceInspectors: document.querySelectorAll('.generation-source').length,
            rootHeaders: document.querySelectorAll('.ra-root__header').length,
            programCount: document.querySelectorAll('.generation-answer__program').length,
            statusDisplay: status ? getComputedStyle(status).display : 'missing',
            bodyOverflow: getComputedStyle(document.body).overflow,
            bodyBackground: getComputedStyle(document.body).backgroundColor,
            horizontalOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
          };
        })())
        """
        guard let metricsJSON = evaluate(metricsScript) as? String,
              let metricsData = metricsJSON.data(using: .utf8),
              let metrics = try? JSONSerialization.jsonObject(with: metricsData) as? [String: Any] else {
            expect(false, "the runtime exposes inspectable embedded-mode metrics")
            return
        }
        expect(metrics["embedded"] as? Bool == true
            && metrics["proofbars"] as? Int == 0
            && metrics["sourceInspectors"] as? Int == 0
            && metrics["rootHeaders"] as? Int == 0
            && metrics["programCount"] as? Int == 2
            && metrics["statusDisplay"] as? String == "none"
            && metrics["bodyOverflow"] as? String == "hidden"
            && metrics["bodyBackground"] as? String == "rgba(0, 0, 0, 0)"
            && (metrics["horizontalOverflow"] as? NSNumber)?.doubleValue ?? 1 <= 1,
            "embedded WebKit rendering is transparent, narrow-safe, and omits the webpage toolbar, source inspector, status strip, and duplicate root headers")

        guard let heightMessage = messages.last(where: { $0["type"] as? String == "weibei:height" }),
              let measuredHeight = (heightMessage["height"] as? NSNumber)?.doubleValue else {
            expect(false, "the runtime height report contains a measured value")
            return
        }
        expect(measuredHeight > 160 && heightMessage["overflowed"] as? Bool == true, "the runtime reports real overflow instead of silently capping and clipping its content")

        evaluate("""
        (() => {
          const slider = document.querySelector('input[type="range"]');
          if (slider) {
            const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
            if (setter) setter.call(slider, '2');
            else slider.value = '2';
            slider.dispatchEvent(new Event('input', { bubbles: true }));
            slider.dispatchEvent(new Event('change', { bubbles: true }));
          }
          document.querySelector('.ra-followup')?.click();
          document.querySelector('.ra-evidence')?.click();
        })()
        """)
        let interactionsReturned = wait(until: {
            self.hasMessage("weibei:state")
                && self.hasMessage("weibei:action")
                && self.hasMessage("weibei:evidence")
        }, timeout: 8)
        let observedTypes = Set(messages.compactMap { $0["type"] as? String }).sorted().joined(separator: ", ")
        expect(interactionsReturned, "slider state, follow-up action, and evidence jump return through the real WebKit bridge; observed: \(observedTypes)")

        if let failure {
            expect(false, failure)
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "weibeiRichAnswer")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            failure = "the rich-answer runtime emitted a non-object bridge message"
            return
        }
        messages.append(body)
    }

    private func hasMessage(_ type: String) -> Bool {
        messages.contains { $0["type"] as? String == type }
    }

    private func wait(until condition: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    private func waitForJavaScript(_ condition: String, timeout: TimeInterval) -> Bool {
        wait(until: { self.evaluate(condition) as? Bool == true }, timeout: timeout)
    }

    @discardableResult
    private func evaluate(_ script: String) -> Any? {
        var result: Any?
        var isDone = false
        webView.evaluateJavaScript(script) { value, error in
            if let error {
                self.failure = "rich-answer runtime JavaScript failed: \(error.localizedDescription)"
            }
            result = value
            isDone = true
        }
        _ = wait(until: { isDone }, timeout: 5)
        return result
    }

    private func payloadJSON() -> String? {
        func program(
            id: String,
            source: String,
            graphics: String = "dom",
            evidenceBindings: [[String: String]] = [],
            evidenceContent: [[String: Any]] = []
        ) -> [String: Any] {
            [
                "version": "weibei.openui.v1",
                "id": id,
                "title": "运行时探针 \(id)",
                "question": "验证回答流内生成式体验",
                "mode": "declarative",
                "source": source,
                "capabilities": ["runtime-probe"],
                "evidenceBindings": evidenceBindings,
                "evidenceContent": evidenceContent,
                "budget": [
                    "maxHeight": 500,
                    "maxNodes": 48,
                    "maxSeries": 8,
                    "graphics": graphics,
                ],
            ]
        }

        let firstSource = """
        $a = 1
        root = RichAnswerRoot("探针", "不应显示的标题", "不应显示的摘要", "flow", [visual, sourceStage])
        visual = LearningStage("visual", "局部操作", [slider, plot, note1, note2, followup])
        sourceStage = LearningStage("evidence", "", [evidence])
        slider = ParameterSlider("a", "参数 a", $a, -3, 3, 0.5, "拖动后通过桥接上报状态。")
        plot = FunctionPlot("y = ax²", "quadratic", "a", $a, [], -3, 3, 240)
        note1 = NarrativeBlock("观察一", "这是局部状态解释，不是第二篇回答。", "neutral")
        note2 = NarrativeBlock("观察二", "多视觉与多控件仍可在同一个体验块中组合。", "mechanism")
        followup = FollowUpAction("继续验证", "继续验证富回答")
        evidence = EvidenceSnippet("probe-evidence", "探针段落", "不显示的证据原文", "只承担回原文。")
        """
        let secondSource = """
        root = RichAnswerRoot("探针", "另一个不应显示的标题", "另一个不应显示的摘要", "flow", [stage])
        stage = LearningStage("visual", "第二个局部场景", [note1, note2, note3])
        note1 = NarrativeBlock("状态一", "同一 WebKit 运行时承载多个独立场景。", "neutral")
        note2 = NarrativeBlock("状态二", "场景之间保留视觉区分但不形成网页。", "mechanism")
        note3 = NarrativeBlock("状态三", "窄栏中由组件自己重排。", "diagnosis")
        """
        let payload: [String: Any] = [
            "type": "weibei:setPrograms",
            "heightLimit": 160,
            "programs": [
                program(
                    id: "runtime-probe-a",
                    source: firstSource,
                    graphics: "canvas",
                    evidenceBindings: [["id": "probe-evidence", "sourceID": "current-document", "locator": "探针段落"]],
                    evidenceContent: [["id": "probe-evidence", "sourceLabel": "探针材料", "excerpt": "真实证据由宿主注入。", "isTruncated": false]]
                ),
                program(id: "runtime-probe-b", source: secondSource),
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/**
 * 验证富回答嵌入契约与可选的真实 WebKit 运行时。
 */
enum RichAnswerEmbeddingSelfChecks {
    /**
     * 执行富回答嵌入自检。
     */
    @MainActor
    static func run(repositoryURL: URL) {
        if ProcessInfo.processInfo.environment["WEIBEI_RICH_ANSWER_WEB_CHECK"] == "1" {
            RichAnswerWebRuntimeHarness().run(repositoryURL: repositoryURL)
        }
    }
}
