import AppKit
import CoreText
import Foundation
import PDFKit
import Security
import WebKit
import WeiBeiCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("self-check failed: \(message)\n", stderr)
        exit(1)
    }
}

@MainActor
final class RichAnswerWebRuntimeHarness: NSObject, WKScriptMessageHandler {
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

@MainActor
func runRichAnswerEmbeddingSelfChecks() {
    let repositoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    func source(_ path: String) -> String {
        (try? String(contentsOf: repositoryURL.appendingPathComponent(path), encoding: .utf8)) ?? ""
    }

    let notesAgentSource = source("Sources/WeiBei/Views/NotesAgentView.swift")
    let richAnswerHostSource = source("Sources/WeiBei/Views/RichAnswerHost.swift")
    let richAnswerWebRuntimeSource = source("Sources/WeiBei/Views/RichAnswerWebRuntimeView.swift")
    let richAnswerWorkbenchSource = source("Prototypes/RichAnswerWebRuntime/src/generative/generative-workbench.tsx")
    let richAnswerLibrarySource = source("Prototypes/RichAnswerWebRuntime/src/generative/library.tsx")
    let richAnswerReferenceProgramsSource = source("Prototypes/RichAnswerWebRuntime/src/generative/programs.ts")
    let richAnswerPressureCatalogSource = source("Prototypes/RichAnswerWebRuntime/src/catalog.tsx")
    let richAnswerExtendedComponentsSource = source("Prototypes/RichAnswerWebRuntime/src/generative/extended-knowledge-components.tsx")
    let richAnswerRuntimeCSS = source("Sources/WeiBei/Resources/rich-answer-runtime.css")
    let richAnswerSystemPrompt = source("Sources/WeiBeiCore/AgentResources/system.md")
    let richAnswerExtensionSource = source("Sources/WeiBeiCore/AgentResources/extension.ts")
    let richAnswerEngineSource = source("Sources/WeiBeiCore/RichAnswerEngine.swift")
    let richAnswerFixtureSource = source("Sources/WeiBei/Support/RichAnswerVerificationFixture.swift")
    let richAnswerTurnSource: String = {
        guard let start = notesAgentSource.range(of: "private var regularMessageContent: some View")?.lowerBound,
              let end = notesAgentSource.range(of: "private var messageMetadata: some View", range: start..<notesAgentSource.endIndex)?.lowerBound else {
            return ""
        }
        return String(notesAgentSource[start..<end])
    }()
    expect(richAnswerTurnSource.contains("richAnswerFlow(richAnswer)")
        && richAnswerTurnSource.contains("ForEach(Array(presentation.resolvedParts.enumerated())")
        && richAnswerTurnSource.contains("case .narrative:")
        && richAnswerTurnSource.contains("RichAnswerNarrativeText(text: text)")
        && richAnswerTurnSource.contains("case .scene:")
        && richAnswerTurnSource.contains("scopedRichAnswer(presentation, sceneID: sceneID)")
        && richAnswerTurnSource.contains("RichAnswerHost("), "rich answers render an inspectable narrative-scene sequence instead of always appending a mini-site after the text")
    expect(!richAnswerHostSource.contains("部分内容因证据或宿主能力不足已自动收敛")
        && richAnswerEngineSource.contains(#"\\hat\s*\{([^{}]+)\}"#)
        && richAnswerEngineSource.contains(#"\\bar\s*\{([^{}]+)\}"#)
        && notesAgentSource.contains("AgentChatKaTeXMarkdown.prepare(text)")
        && notesAgentSource.contains("RichAnswerDisplayText.normalizedInlineMath(value)"), "rich answers keep renderer diagnostics in evidence while presenting common formulas as readable user-facing text")
    expect(richAnswerLibrarySource.contains("stages: z.array(LearningStage.ref).min(1).max(8)")
        && richAnswerLibrarySource.contains("FunctionPlot")
        && richAnswerLibrarySource.contains("LinkedDataChart")
        && richAnswerLibrarySource.contains("ProcessStepper")
        && richAnswerLibrarySource.contains("ArgumentReader")
        && richAnswerLibrarySource.contains("CausalTrack")
        && richAnswerLibrarySource.contains("TwoPointLineLab")
        && richAnswerLibrarySource.contains("BalanceExperiment")
        && richAnswerWorkbenchSource.contains("onStateUpdate={handleStateUpdate}")
        && richAnswerWorkbenchSource.contains("onAction={handleAction}")
        && richAnswerHostSource.contains("RichAnswerWebRuntimeView(\n                scenes: scenes")
        && richAnswerHostSource.contains("private func rendersInlineFlow(_ scenes: [RichAnswerScene]) -> Bool"), "the in-flow generative experience can compose multiple stages, scenes, visuals, and interactions inside one shared runtime instead of collapsing to one textbook illustration")
    expect(richAnswerHostSource.contains("onRuntimeReady: {")
        && richAnswerHostSource.contains("readySceneIDs.formUnion(scenes.map(\\.id))")
        && richAnswerHostSource.contains("onSceneReady: {")
        && richAnswerHostSource.contains("readySceneIDs.insert(scene.id)")
        && richAnswerHostSource.contains("readySceneIDs.isSuperset(of: Set(sceneIDs))")
        && richAnswerHostSource.contains("rendererIsReady(updatedSceneIDs)")
        && richAnswerHostSource.contains("presentation.scenes.allSatisfy(\\.usesWebRuntime)")
        && richAnswerHostSource.contains("holdPrematureVerificationMarkerIfNeeded()")
        && richAnswerHostSource.contains("restoreDeferredVerificationMarkerIfNeeded(in: baseURL)")
        && richAnswerHostSource.contains("rich-answer-renderer-ready.txt"),
        "real rich-answer replay markers are gated until the host window has size and every rich scene renderer reports ready")
    expect(richAnswerWebRuntimeSource.contains("onRuntimeReady")
        && richAnswerWebRuntimeSource.contains("hasRuntimeHeight = true")
        && richAnswerWebRuntimeSource.contains("notifyRuntimeReadyIfNeeded()"),
        "Web rich-answer runtime readiness is based on the real ready handshake plus measured height, not a fixed delay")
    expect(notesAgentSource.contains("await store.runVerificationScenarioIfNeeded()")
        && notesAgentSource.contains("hasVisibleRichAnswer")
        && notesAgentSource.contains("agentScrollBottomInset")
        && notesAgentSource.contains("// Fixed inset only"),
        "agent host mounts verification scenarios from the real pane and reserves fixed bottom scroll inset for rich answers without tray preference thrash")
    func capturedNames(in text: String, pattern: String) -> Set<String> {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(expression.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        })
    }
    func slice(_ text: String, from start: String, through end: String) -> String {
        guard let lower = text.range(of: start)?.lowerBound,
              let upper = text.range(of: end, range: lower..<text.endIndex)?.upperBound else { return "" }
        return String(text[lower..<upper])
    }
    let extensionCatalog = slice(
        richAnswerExtensionSource,
        from: "const OPENUI_COMPONENT_SIGNATURES = {",
        through: "} as const;"
    )
    let libraryCatalog = slice(
        richAnswerLibrarySource,
        from: "components: [",
        through: "componentGroups: ["
    )
    let swiftCatalog = slice(
        richAnswerEngineSource,
        from: "let allowedComponents: Set<String> = [",
        through: "]"
    )
    let extensionComponentNames = capturedNames(
        in: extensionCatalog,
        pattern: #"(?m)^\s{2}([A-Za-z][A-Za-z0-9]*):\s*"#
    )
    let libraryComponentNames = capturedNames(
        in: libraryCatalog,
        pattern: #"(?m)^\s{4}([A-Za-z][A-Za-z0-9]*),\s*$"#
    )
    let swiftComponentNames = capturedNames(
        in: swiftCatalog,
        pattern: #"\"([A-Za-z][A-Za-z0-9]*)\""#
    )
    expect(!extensionComponentNames.isEmpty
        && extensionComponentNames == libraryComponentNames
        && extensionComponentNames == swiftComponentNames, "the model catalog, Web renderer, and native safety validator expose the same open-ended T1 component vocabulary")
    expect(richAnswerExtensionSource.contains("const RICH_ANSWER_CATALOG_TOOL = \"weibei_ui_catalog\"")
        && richAnswerExtensionSource.contains("const VISUAL_ASSET_TOOL = \"weibei_visual_asset\"")
        && richAnswerExtensionSource.contains("visualInspection:")
        && richAnswerExtensionSource.contains("visualAssetMagicMatches(")
        && richAnswerExtensionSource.contains("const OPENUI_COMPONENT_GROUPS = {")
        && richAnswerExtensionSource.contains("selectedOpenUIComponentGroups(")
        && richAnswerExtensionSource.contains("openUIComponentConstraintGuidance(")
        && richAnswerExtensionSource.contains("参数约束：")
        && richAnswerExtensionSource.contains("const structuralErrors: string[] = []")
        && richAnswerExtensionSource.contains("const semanticErrors: string[] = []")
        && richAnswerExtensionSource.contains("const validationIssues: string[] = []")
        && richAnswerExtensionSource.contains("程序为空或超出 10,000 字符 / 48 条声明预算")
        && richAnswerExtensionSource.contains("并控制在 8 项以内")
        && richAnswerExtensionSource.contains("richAnswerCatalogSelection")
        && richAnswerExtensionSource.contains("组件 ${declaration.component} 不在本轮目录选择中")
        && richAnswerSystemPrompt.contains("先由 Agent 判断是否需要富回答")
        && richAnswerSystemPrompt.contains("`routeRecommendation` 只是")
        && richAnswerSystemPrompt.contains("不要依赖旧回合或完整组件库记忆"), "Pi retrieves a relevant component subset before generation instead of carrying the entire growing catalog in every rich-answer prompt")
    expect(richAnswerExtendedComponentsSource.contains("name: \"LayeredSpatialView\"")
        && richAnswerExtendedComponentsSource.contains("name: \"DistributionBrush\"")
        && richAnswerExtendedComponentsSource.contains("name: \"DependencyFlow\"")
        && richAnswerExtensionSource.contains("LayeredSpatialView(visibilityStateName")
        && richAnswerExtensionSource.contains("DistributionBrush(centerStateName")
        && richAnswerExtensionSource.contains("DependencyFlow(valuesStateName"), "cross-disciplinary spatial, distribution, and dependency experiences are generatable components rather than fixed demo pages")
    let retainedReferenceProgramIDs = [
        "quadratic-experiment",
        "quadratic-compare",
        "quadratic-reasoning",
        "line-composition",
        "equilibrium-composition",
        "argument-composition",
        "sampling-composition",
        "cashflow-composition",
        "policy-composition",
        "code-composition",
    ]
    let retainedPressureSceneKeys = [
        "math-line",
        "physics-force",
        "chem-equilibrium",
        "biology-meiosis",
        "text-argument",
        "history-causality",
        "geography-map",
        "art-observation",
        "statistics-sampling",
        "finance-cashflow",
        "economics-policy",
        "code-sort",
    ]
    let retainedLikedReferenceProgramIDs = [
        "二次函数图解": "quadratic-experiment",
        "两点决定直线": "line-composition",
        "动态平衡": "equilibrium-composition",
        "论证剖面": "argument-composition",
        "抽样分布": "sampling-composition",
        "现金流传导": "cashflow-composition",
        "政策证据链": "policy-composition",
        "算法执行轨道": "code-composition",
    ]
    let retainedLikedPressureSceneKeys = [
        "空间图层": "geography-map",
        "图像观察镜": "art-observation",
    ]
    expect(retainedReferenceProgramIDs.allSatisfy { richAnswerReferenceProgramsSource.contains("id: \"\($0)\"") }
        && retainedPressureSceneKeys.allSatisfy { richAnswerPressureCatalogSource.contains("key: \"\($0)\"") }
        && retainedLikedReferenceProgramIDs.values.allSatisfy { richAnswerReferenceProgramsSource.contains("id: \"\($0)\"") }
        && retainedLikedPressureSceneKeys.values.allSatisfy { richAnswerPressureCatalogSource.contains("key: \"\($0)\"") }, "the named high-quality interaction references and cross-disciplinary pressure scenes remain available as regression evidence without becoming a finite capability boundary")
    expect(richAnswerWorkbenchSource.contains("document.documentElement.classList.toggle(\"weibei-embedded\", embedded)")
        && richAnswerWorkbenchSource.contains("{!embedded && program ? (\n        <header className=\"generation-proofbar\">")
        && richAnswerWorkbenchSource.contains("{!embedded && program ? (\n        <details className=\"generation-source\">")
        && richAnswerRuntimeCSS.contains(".generation-page.is-embedded{width:100%;padding:0}")
        && richAnswerRuntimeCSS.contains("html.weibei-embedded,html.weibei-embedded body,html.weibei-embedded #root{min-width:0;min-height:0;background:transparent!important}")
        && richAnswerRuntimeCSS.contains(".generation-page.is-embedded .generation-answer{display:grid;gap:14px;overflow:visible;background:transparent;box-shadow:none}")
        && richAnswerRuntimeCSS.contains(".generation-page.is-embedded .generation-answer__status{display:none}"), "embedded generative UI is transparent and omits the prototype toolbar, source inspector, status strip, and default webpage shell")
    expect(richAnswerRuntimeCSS.contains(".weibei-embedded .ra-root__header{display:none}"), "embedded generative UI hides its root eyebrow, title, and summary so it does not start a second answer")
    let richAnswerPresentationContentSource: String = {
        guard let start = richAnswerHostSource.range(of: "private func presentationContent(maxWidth: CGFloat, expandsOverflow: Bool)")?.lowerBound,
              let end = richAnswerHostSource.range(of: "private var focusLauncher: some View", range: start..<richAnswerHostSource.endIndex)?.lowerBound else {
            return ""
        }
        return String(richAnswerHostSource[start..<end])
    }()
    expect(!richAnswerPresentationContentSource.contains("presentation.expressionPlan?.summary")
        && !richAnswerPresentationContentSource.contains("Text(summary)"), "the native host does not repeat the expression-plan summary above an embedded generated experience")
    expect(richAnswerSystemPrompt.contains("生成式 UI 是 Agent 回答流中的生成式视觉体验块")
        && richAnswerSystemPrompt.contains("它可以按问题需要组合多个视觉、控件、读数、局部解释和实验步骤")
        && richAnswerSystemPrompt.contains("不是第二篇回答、独立小网页或完整网页外壳")
        && richAnswerSystemPrompt.contains("禁止在体验块中重复 Agent 正文的整套标题、摘要、结论"), "the rich-answer contract allows a composable visual experience without repeating the narrative title, summary, or conclusion")
    expect(richAnswerExtensionSource.contains("const richAnswerT1SceneSchema")
        && richAnswerExtensionSource.contains("program: richAnswerUIProgramSchema")
        && richAnswerExtensionSource.contains("const richAnswerT2SceneSchema")
        && richAnswerExtensionSource.contains("ui: richAnswerUICompositionSchema")
        && richAnswerExtensionSource.contains("场景从输入层三选一")
        && richAnswerExtensionSource.contains("validateRichAnswerUI(scene, allowedEvidenceIDs, allowedAssetIDs)")
        && richAnswerSystemPrompt.contains("`renderPlan` 用注册专业渲染器的高层规格")
        && richAnswerSystemPrompt.contains("三者不能同时提交"), "the Agent chooses exactly one open rich-answer route instead of falling back merely because no specialized component exists")
    expect(richAnswerExtensionSource.contains("validateRichAnswerNarrativeFlow")
        && richAnswerExtensionSource.contains("narrative 没有就近标注已使用的真实来源")
        && richAnswerSystemPrompt.contains("`narrative` 就是本次富回答最终显示的完整正文"), "rich answers validate their final inline narrative and real source labels instead of trusting a separate model afterword")
    expect(richAnswerFixtureSource.contains("case pendulum = \"rich-answer-pendulum\"")
        && richAnswerFixtureSource.contains("id: \"pendulum-primitives\"")
        && richAnswerFixtureSource.contains("role: .path")
        && richAnswerFixtureSource.contains("role: .probe")
        && richAnswerFixtureSource.contains("placement: .inline"), "the acceptance gallery includes an inline pendulum scene composed from generic primitives without a specialized pendulum component")
    expect(richAnswerFixtureSource.contains("case sequence = \"rich-answer-sequence\"")
        && richAnswerFixtureSource.contains("id: \"argument-sequence\"")
        && richAnswerFixtureSource.contains("role: .sequence")
        && richAnswerFixtureSource.contains("bindingID: \"sequence-step\"")
        && richAnswerFixtureSource.contains("不是固定模板清单"), "the open acceptance gallery grows beyond a fixed scenario count and exercises the generic semantic sequence primitive")
    expect(richAnswerFixtureSource.contains("extendedOpenUIProgramScenario = \"rich-answer-openui-extended\"")
        && richAnswerFixtureSource.contains("inlineExtendedOpenUIProgramScenario = \"rich-answer-openui-extended-inline\"")
        && richAnswerFixtureSource.contains("id: \"openui-spatial-layers\"")
        && richAnswerFixtureSource.contains("id: \"openui-distribution-brush\"")
        && richAnswerFixtureSource.contains("id: \"openui-dependency-flow\"")
        && richAnswerFixtureSource.contains("<!-- weibei-scene:openui-spatial-layers -->")
        && richAnswerFixtureSource.contains("<!-- weibei-scene:openui-distribution-brush -->")
        && richAnswerFixtureSource.contains("<!-- weibei-scene:openui-dependency-flow -->"), "the real Agent fixture interleaves three different generative deep components inside one sourced answer")
    let onePeriodCashFlowPresentValue = 100 * 1.08 * 0.18 / 1.11
    expect(abs(onePeriodCashFlowPresentValue - 17.5135) < 0.001
        && richAnswerFixtureSource.contains("一期自由现金流现值 = 基准收入 × 收入增长倍数 × 现金流率 ÷ 折现倍数")
        && richAnswerFixtureSource.contains("DependencyNode(\"present-value\", \"一期现金流现值\", 3, \"ratio\""), "the finance dependency reference uses a professionally meaningful cash-flow present-value chain instead of decorative arithmetic")
    if ProcessInfo.processInfo.environment["WEIBEI_RICH_ANSWER_WEB_CHECK"] == "1" {
        RichAnswerWebRuntimeHarness().run(repositoryURL: repositoryURL)
    }
}

/**
 * 运行默认的完整自检集合。
 */
@MainActor
func runWeiBeiSelfChecks() async throws {
try runPiAgentSelfChecks()

expect(EmptyWorkspaceDayPeriod(hour: 5) == .morning
    && EmptyWorkspaceDayPeriod(hour: 10) == .morning
    && EmptyWorkspaceDayPeriod(hour: 11) == .midday
    && EmptyWorkspaceDayPeriod(hour: 16) == .midday
    && EmptyWorkspaceDayPeriod(hour: 17) == .evening
    && EmptyWorkspaceDayPeriod(hour: 22) == .evening
    && EmptyWorkspaceDayPeriod(hour: 23) == .lateNight
    && EmptyWorkspaceDayPeriod(hour: 4) == .lateNight, "empty workspace greeting follows morning, midday, evening, and late-night boundaries")
expect(EmptyWorkspaceDayPeriod.morning.greeting(language: .chinese).contains("早安")
    && EmptyWorkspaceDayPeriod.midday.greeting(language: .chinese).contains("午安")
    && EmptyWorkspaceDayPeriod.evening.greeting(language: .chinese).contains("晚安")
    && EmptyWorkspaceDayPeriod.lateNight.greeting(language: .chinese).contains("夜深")
    && !EmptyWorkspaceDayPeriod.morning.greeting(language: .english).isEmpty, "empty workspace greetings stay localized and non-empty")

let inspirationItems = EmptyWorkspaceInspirationCatalog.items
expect(inspirationItems.count >= 6
    && EmptyWorkspaceInspirationCatalog.validationErrors.isEmpty
    && inspirationItems.contains(where: { if case .calligraphy = $0.presentation { return true }; return false })
    && inspirationItems.contains(where: { $0.presentation == .quotation })
    && inspirationItems.contains(where: { $0.presentation == .formula }), "daily inspiration catalog contains validated calligraphy, original-language quotation, and formulas")
expect(inspirationItems.allSatisfy { item in
    !item.text.isEmpty
        && !item.credit.isEmpty
        && item.sourceURL?.scheme == "https"
        && !item.rightsLabel.isEmpty
        && item.rightsURL?.scheme == "https"
}, "every daily inspiration keeps text, author/work credit, a reliable source, and rights metadata")
var inspirationCalendar = Calendar(identifier: .gregorian)
inspirationCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let inspirationDayOne = inspirationCalendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))!
let inspirationDayTwo = inspirationCalendar.date(byAdding: .day, value: 1, to: inspirationDayOne)!
expect(EmptyWorkspaceInspirationCatalog.item(for: inspirationDayOne, calendar: inspirationCalendar).id
    != EmptyWorkspaceInspirationCatalog.item(for: inspirationDayTwo, calendar: inspirationCalendar).id, "daily inspiration rotates deterministically from one local day to the next")

let offlineChinesePreview = AgentOfflinePreview.render(
    AgentOfflinePreviewInput(
        language: .chinese,
        question: "解释利率为什么是资金价格",
        hasMaterial: true,
        materialTitle: "Mishkin 教材样例",
        materialText: "利率是资金使用价格的表达。金融市场通过利率配置资源。",
        noteTitle: "货币金融学课程 HTML",
        noteText: "## 摘录\n来源：Mishkin 教材样例",
        selectionTitle: "已选文本片段",
        selectionText: "利率是资金使用价格的表达。"
    )
)
expect(offlineChinesePreview.contains("## 离线草稿")
    && !offlineChinesePreview.hasPrefix("未配置密钥")
    && offlineChinesePreview.contains("未配置密钥；这里只整理当前可见内容")
    && offlineChinesePreview.contains("**问题**：解释利率为什么是资金价格")
    && offlineChinesePreview.contains("**上下文**：资料：Mishkin 教材样例 · 笔记：货币金融学课程 HTML · 选区：已选文本片段")
    && offlineChinesePreview.contains("## 可确认")
    && offlineChinesePreview.contains("- 选区依据：利率是资金使用价格的表达。")
    && offlineChinesePreview.contains("- 资料依据：利率是资金使用价格的表达。金融市场通过利率配置资源。")
    && offlineChinesePreview.contains("- 笔记线索：## 摘录 来源：Mishkin 教材样例")
    && offlineChinesePreview.contains("## 建议写入")
    && offlineChinesePreview.contains("- 把可确认依据写入笔记，并保留来源。")
    && !offlineChinesePreview.contains("| 上下文 | 内容 |")
    && !offlineChinesePreview.contains("> 资料摘录："), "offline agent draft stays compact, source-grounded, and note-ready without API key")

let offlineEnglishPreview = AgentOfflinePreview.render(
    AgentOfflinePreviewInput(
        language: .english,
        question: "Explain the selected sentence",
        hasMaterial: false,
        materialTitle: "No document",
        materialText: "",
        noteTitle: "Current note",
        noteText: "",
        selectionTitle: nil,
        selectionText: nil
    )
)
expect(offlineEnglishPreview.contains("## Offline Draft")
    && !offlineEnglishPreview.hasPrefix("No key is configured")
    && offlineEnglishPreview.contains("No key is configured; this only organizes visible context")
    && offlineEnglishPreview.contains("**Question**: Explain the selected sentence")
    && offlineEnglishPreview.contains("**Context**: Material: None · Note: Current note · Selection: None")
    && offlineEnglishPreview.contains("## Confirmed")
    && offlineEnglishPreview.contains("- Note state: the current note is empty.")
    && offlineEnglishPreview.contains("## Suggested Note")
    && offlineEnglishPreview.contains("- Write the confirmed evidence into the note and keep the source attached.")
    && !offlineEnglishPreview.contains("| Context | Content |")
    && !offlineEnglishPreview.contains("> Note excerpt:"), "offline agent draft renders compact English empty-context state as Markdown")
expect(AgentOfflinePreview.preview("A\nB\tC", limit: 20) == "A B C", "offline agent preview normalizes whitespace")
let offlineSuggestedNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: offlineChinesePreview, language: .chinese) ?? ""
expect(offlineSuggestedNoteBlock.contains("## 整理建议")
    && offlineSuggestedNoteBlock.contains("把可确认依据写入笔记，并保留来源。")
    && !offlineSuggestedNoteBlock.contains("## 离线草稿")
    && !offlineSuggestedNoteBlock.contains("## 可确认")
    && !offlineSuggestedNoteBlock.contains("**上下文**"), "writing an offline answer into notes keeps only the note-ready suggestion section")
let normalAgentNoteBlock = AgentOfflinePreview.suggestedNoteBlock(from: "## 正式解释\n利率是资金价格。", language: .chinese)
expect(normalAgentNoteBlock == nil, "non-offline markdown answers are not rewritten by the offline-note extractor")

let offlineTurnMessages = AgentOfflineTurn.messages(
    question: "解释当前材料",
    sourceTitle: "Mishkin 教材样例",
    input: AgentOfflinePreviewInput(
        language: .chinese,
        question: "解释当前材料",
        hasMaterial: true,
        materialTitle: "Mishkin 教材样例",
        materialText: "利率是资金使用价格的表达。",
        noteTitle: "货币金融学课程 HTML",
        noteText: "## 摘录",
        selectionTitle: nil,
        selectionText: nil
    )
)
expect(offlineTurnMessages.count == 2
    && offlineTurnMessages[0].role == .user
    && offlineTurnMessages[0].text == "解释当前材料"
    && offlineTurnMessages[0].source == "Mishkin 教材样例"
    && offlineTurnMessages[1].role == .assistant
    && offlineTurnMessages[1].text.contains("## 离线草稿")
    && offlineTurnMessages[1].text.contains("未配置密钥；这里只整理当前可见内容")
    && offlineTurnMessages[1].source == "Mishkin 教材样例"
    && offlineTurnMessages[1].isUsableAgentAnswer, "offline agent turn appends a visible user turn and writable local draft without an API key")

let fontDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Fonts")
let displayFontURL = fontDirectoryURL.appendingPathComponent("WeiBeiStele.ttf")
let monoFontURL = fontDirectoryURL.appendingPathComponent("WeiBeiSteleMono.ttf")
CTFontManagerRegisterFontsForURL(displayFontURL as CFURL, .process, nil)
CTFontManagerRegisterFontsForURL(monoFontURL as CFURL, .process, nil)
expect(NSFont(name: "WeiBeiStele-Regular", size: 18) != nil
    && NSFont(name: "WeiBeiSteleMono-Regular", size: 13) != nil, "bundled WeiBei English fonts register under their PostScript names")
let emptyWorkspaceEntryFont = CTFontCreateWithName("WeiBeiStele-Regular" as CFString, 22, nil)
let emptyWorkspaceEntryCharacters = Array("DOCCHATNOTES".utf16)
var emptyWorkspaceEntryGlyphs = Array(repeating: CGGlyph(), count: emptyWorkspaceEntryCharacters.count)
expect(emptyWorkspaceEntryCharacters.withUnsafeBufferPointer { characters in
    emptyWorkspaceEntryGlyphs.withUnsafeMutableBufferPointer { glyphs in
        CTFontGetGlyphsForCharacters(emptyWorkspaceEntryFont, characters.baseAddress!, glyphs.baseAddress!, characters.count)
    }
} && emptyWorkspaceEntryGlyphs.allSatisfy { $0 != 0 }, "WeiBeiStele keeps every glyph required by the DOC, CHAT, and NOTES work entries")

func inspectCalligraphyAsset(_ url: URL) throws -> (width: Int, height: Int, visible: Int, transparent: Int, opaqueWhite: Int, outerInk: Int) {
    let data = try Data(contentsOf: url)
    guard let bitmap = NSBitmapImageRep(data: data) else {
        throw NSError(domain: "WeiBeiSelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unreadable calligraphy PNG: \(url.path)"])
    }
    var visible = 0
    var transparent = 0
    var opaqueWhite = 0
    var outerInk = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.alphaComponent > 0.05 {
                visible += 1
                if x < 2 || y < 2 || x >= bitmap.pixelsWide - 2 || y >= bitmap.pixelsHigh - 2 {
                    outerInk += 1
                }
            } else {
                transparent += 1
            }
            if color.alphaComponent > 0.95
                && color.redComponent > 0.95
                && color.greenComponent > 0.95
                && color.blueComponent > 0.95 {
                opaqueWhite += 1
            }
        }
    }
    return (bitmap.pixelsWide, bitmap.pixelsHigh, visible, transparent, opaqueWhite, outerInk)
}

let calligraphyDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Inspiration/Calligraphy", isDirectory: true)
let clearBreezeStats = try inspectCalligraphyAsset(calligraphyDirectoryURL.appendingPathComponent("lanting-clear-breeze.png"))
let universeStats = try inspectCalligraphyAsset(calligraphyDirectoryURL.appendingPathComponent("lanting-universe.png"))
expect(clearBreezeStats.width == 856 && clearBreezeStats.height == 132
    && universeStats.width == 624 && universeStats.height == 132
    && clearBreezeStats.visible > 1_000 && universeStats.visible > 1_000
    && clearBreezeStats.transparent > clearBreezeStats.visible
    && universeStats.transparent > universeStats.visible
    && clearBreezeStats.opaqueWhite == 0 && universeStats.opaqueWhite == 0
    && clearBreezeStats.outerInk == 0 && universeStats.outerInk == 0, "bundled Lanting calligraphy masks are transparent, uncropped, and free of hard white backgrounds")

let inspirationSourcesURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Inspiration/SOURCES.md")
let inspirationSources = (try? String(contentsOf: inspirationSourcesURL, encoding: .utf8)) ?? ""
expect(inspirationSources.contains("a133647a8695cd06d0f5c6215d66e0b8b8d93d56")
    && inspirationSources.contains("b30c54279d2e0b5c7b8221369962ba3a3c0e16b264808332da38cb1b8e63d936")
    && inspirationSources.contains("a915d1e460c68a0634c2cfaad90f802fda04ea8c25227632cd4812c51647df22")
    && inspirationSources.contains("1c7965b6447392a874ed75adb1ce5703f26b562b8fc5fd6f380d1fdde0621379")
    && inspirationSources.contains("Public Domain Mark 1.0")
    && inspirationSources.contains("故00002597")
    && inspirationSources.contains("were rejected")
    && inspirationSources.contains("No NC, ND")
    && inspirationSources.contains("No generative fill, vector tracing, or font substitution"), "inspiration resource documentation preserves source hashes, public-domain status, provenance, exclusions, and transformation limits")

let runScriptURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("script/build_and_run.sh")
let runScript = (try? String(contentsOf: runScriptURL, encoding: .utf8)) ?? ""
expect(runScript.contains("BUILD_CONFIGURATION=\"release\"")
    && runScript.contains("BUILD_CONFIGURATION=\"debug\"")
    && runScript.contains("swift build -c \"$BUILD_CONFIGURATION\"")
    && runScript.contains("swift build -c \"$BUILD_CONFIGURATION\" --show-bin-path")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBeiSelfCheck")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBei --self-check-imported-identity")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBeiWebEditorCheck")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBeiPiCheck"), "user-facing app builds are optimized while check and debugger modes remain debuggable")
expect(runScript.contains("'\"activeNotebookItemID\":\"imported:'")
    && runScript.contains("&& ! /usr/bin/grep -q '\"activeNotebookItemID\":\"file:'"), "linked-source verification requires stable notebook identity and rejects a legacy path identity")
expect(runScript.contains("${PRODUCT_NAME}_WeiBeiCore.bundle")
    && runScript.contains("for resource_bundle in \"${RESOURCE_BUNDLES[@]}\"")
    && runScript.contains("cp -R \"$resource_bundle\" \"$APP_RESOURCES/\"")
    && !runScript.contains("cp -R \"$resource_bundle\" \"$APP_BUNDLE/\""), "packaging places both Swift resource bundles once in the signed app Resources directory")
expect(runScript.contains("prepare_pi_runtime.sh")
    && runScript.contains("PiRuntime/bin/pi")
    && runScript.contains("binary.sha256")
    && runScript.contains("pi_reports_expected_version")
    && runScript.contains("for attempt in {1..10}")
    && runScript.contains("codesign --force --sign - --timestamp=none \"$PACKAGED_PI\"")
    && runScript.contains("cmp -s \"$BUILD_BINARY\" \"$APP_BINARY\"")
    && runScript.contains("PACKAGED_UUID=")
    && runScript.contains("signed app binary UUID does not match the current Swift build")
    && runScript.contains("codesign --verify --deep --strict \"$APP_BUNDLE\""), "packaging embeds and integrity-checks the signed PI runtime inside the app")
expect(runScript.contains("PDF_TEXT_WORKER_NAME=\"WeiBeiPDFTextWorker\"")
    && runScript.contains("cp \"$BUILD_PDF_TEXT_WORKER\" \"$PDF_TEXT_WORKER\"")
    && runScript.contains("cmp -s \"$BUILD_PDF_TEXT_WORKER\" \"$PDF_TEXT_WORKER\"")
    && runScript.contains("codesign --force --sign - --timestamp=none \"$PDF_TEXT_WORKER\"")
    && runScript.contains("WEIBEI_PDF_WORKER_VERIFY=1 \"$PDF_TEXT_WORKER\" --verification-probe normal"), "packaging embeds, signs, and executes the bounded PDF text worker")
expect(runScript.contains("kCGWindowOwnerName") && runScript.contains("\"$APP_DISPLAY_NAME\""), "run script verifies the visible app window by owner name")
expect(runScript.contains("let isOnscreen = window[kCGWindowIsOnscreen as String] as? NSNumber") && runScript.contains("let visibleEnough = isOnscreen == nil || isOnscreen?.intValue != 0"), "run script tolerates missing onscreen metadata when the window is otherwise capturable")
expect(!runScript.contains("pid=\"$(pgrep -x \"$PRODUCT_NAME\""), "run script window verification does not depend on pgrep")
expect(runScript.contains("visual_verify_window") && runScript.contains("--visual-verify") && runScript.contains("visual_non_black_ratio") && runScript.contains("visual_black_ratio") && runScript.contains("visual_transparent_ratio") && runScript.contains("color.alphaComponent < 0.05") && runScript.contains("blackRatio > 0.12") && runScript.contains("transparentRatio > 0.005") && runScript.contains("nonBlackRatio < 0.02"), "run script rejects empty, fully transparent, and black rendering blocks without rejecting translucent titlebar material")
expect(runScript.contains("weibei-visual-verify-latest.png") && runScript.contains("cp \"$capture_path\" \"$latest_capture_path\""), "visual verification leaves one latest screenshot path for review")
expect(runScript.contains("weibei-visual-verify-$VERIFY_SCENARIO.png")
    && runScript.contains("visual_capture_path=$scenario_capture_path"), "visual verification preserves a separate screenshot for every empty-workspace theme and width scenario")
expect(runScript.contains("WEIBEI_VERIFY_CAPTURE_PATH")
    && runScript.contains("[[ -s \"$VERIFY_CAPTURE_PATH\" ]] && break")
    && runScript.contains("app-owned capture and macOS window capture failed")
    && runScript.contains("Grant Screen Recording permission"), "visual verification prefers an app-owned capture and reports when both capture paths fail")
expect(runScript.contains("open_app()")
    && runScript.contains("/usr/bin/open \"$APP_BUNDLE\"")
    && !runScript.contains("open -n \"$APP_BUNDLE\"")
    && runScript.contains("codesign --verify --deep --strict \"$APP_BUNDLE\""), "regular run opens the staged signed WeiBei without forcing a second app instance")
expect(runScript.contains("RUN_VISUAL_VERIFY=false")
    && runScript.contains("if [[ \"${2:-}\" == \"--visual-verify\"")
    && runScript.contains("finish_verify_window()")
    && runScript.contains("if [[ \"$RUN_VISUAL_VERIFY\" == true ]]; then\n    visual_verify_window")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBeiWebEditorCheck")
    && runScript.contains("swift run -c \"$BUILD_CONFIGURATION\" WeiBeiPiCheck"), "run script verify mode includes Web editor and PI checks and honors --verify --visual-verify")
expect(runScript.contains("open_app_for_verify()")
    && runScript.contains("VERIFY_DATA_DIR=\"$DIST_DIR/Data\"")
    && runScript.contains("VERIFY_SCENARIO=\"${WEIBEI_VERIFY_SCENARIO:-offline-learning-flow}\"")
    && runScript.contains("VERIFY_WINDOW_SIZE=\"${WEIBEI_VERIFY_WINDOW_SIZE:-}\"")
    && runScript.contains("VERIFY_INSPIRATION_ID=\"${WEIBEI_VERIFY_INSPIRATION_ID:-}\"")
    && runScript.contains("rm -rf \"$VERIFY_DATA_DIR\"")
    && runScript.contains("local agent_environment=(WEIBEI_FORCE_OFFLINE_AGENT=1)")
    && runScript.contains("if [[ \"$VERIFY_SCENARIO\" == \"pi-learning-flow\" || \"$VERIFY_SCENARIO\" == \"pi-course-memory-flow\" ]]")
    && runScript.contains("/usr/bin/env \\")
    && runScript.contains("WEIBEI_SUPPRESS_ACTIVATION=1 \\")
    && runScript.contains("\"WEIBEI_WORKSPACE_DIR=$VERIFY_DATA_DIR\"")
    && runScript.contains("\"WEIBEI_VERIFY_SCENARIO=$VERIFY_SCENARIO\"")
    && runScript.contains("\"WEIBEI_VERIFY_WINDOW_SIZE=$VERIFY_WINDOW_SIZE\"")
    && runScript.contains("\"$APP_BINARY\" >\"$VERIFY_STDOUT\" 2>\"$VERIFY_STDERR\" &")
    && runScript.contains("VERIFY_PID=\"$!\"")
    && runScript.contains("if [[ -n \"$VERIFY_SCENARIO\" ]]; then\n    for _ in {1..50}; do")
    && runScript.contains("--verify|verify)\n    run_verifiers\n    open_app_for_verify")
    && runScript.contains("--visual-verify|visual-verify)\n    run_verifiers\n    open_app_for_verify"), "verify modes launch the app in the background with an isolated offline or PI-backed learning-flow workspace")
expect(runScript.contains("verify_learning_flow_persistence()")
    && runScript.contains("workspace.json")
    && runScript.contains("## 整理建议")
    && runScript.contains("把可确认依据写入笔记")
    && runScript.contains("! /usr/bin/grep -q \"## 离线草稿\"")
    && runScript.contains("! /usr/bin/grep -q \"## 可确认\""), "verify mode checks that the offline learning flow persists only the note-ready agent suggestion into the note workspace")
expect(runScript.contains("pi-agent-verified.txt")
    && runScript.contains("packaged PI did not complete the in-app learning flow")
    && workspaceStoreSource.contains("scenario == \"pi-learning-flow\", messages.last?.backend == .pi"), "verify mode can prove the packaged app itself completed a real PI-backed learning flow")
expect(runScript.contains("pi-course-memory-verified.txt")
    && runScript.contains("packaged PI did not persist the course-memory learning flow")
    && runScript.contains("'\"learningMemoryEntries\"'")
    && runScript.contains("'\"studyLocationsByItemID\"'")
    && runScript.contains("'\"studySessions\"'")
    && workspaceStoreSource.contains("scenario == \"pi-course-memory-flow\"")
    && workspaceStoreSource.contains("latestAgentLearningUpdate?.entries.contains { $0.kind == .confusion }")
    && workspaceStoreSource.contains("pi-course-memory-verified.txt"), "verify mode proves the packaged PI can resume, navigate across course files, and persist a user-stated confusion")
expect(workspaceStoreSource.contains("RichAnswerVerificationFixture.supports(scenario)")
    && workspaceStoreSource.contains("configureRichAnswerPreviewVerification(scenario: scenario)")
    && workspaceStoreSource.contains("scenario == RichAnswerVerificationFixture.inlineExtendedOpenUIProgramScenario")
    && workspaceStoreSource.contains("layout = verifiesInlinePane ? .documentAgentNotes : .immersiveConversation")
    && workspaceStoreSource.contains("RichAnswerVerificationFixture.presentation(for: scenario)"), "verification mode can open isolated native rich-answer references, the unified gallery, and a non-immersive split-pane case for real-window review")
expect(runScript.contains("verify_empty_workspace_state()")
    && runScript.contains("empty-workspace-open-doc")
    && runScript.contains("empty-workspace-open-chat")
    && runScript.contains("empty-workspace-open-notes")
    && runScript.contains("\\\"showReader\\\":$expected_reader")
    && runScript.contains("\\\"showAgent\\\":$expected_agent")
    && runScript.contains("\\\"showNotes\\\":$expected_notes")
    && runScript.contains("\\\"showDailyInspiration\\\":$expected_inspiration")
    && runScript.contains("Empty workspace entry state marker"), "verify mode proves each empty-workspace entry opens the requested pane while preserving existing note state")
expect(runScript.contains("VERIFY_MODE=true")
    && runScript.contains("DIST_DIR=\"${TMPDIR:-/tmp}/weibei-verify-$UID-$$\"")
    && runScript.contains("elif [[ \"$VERIFY_MODE\" == true ]]; then\n  :")
    && runScript.contains("VERIFY_PID")
    && !runScript.contains("pgrep -nx \"$PRODUCT_NAME\"")
    && runScript.contains("kill -0 \"$VERIFY_PID\"")
    && runScript.contains("\"$APP_BINARY\" >\"$VERIFY_STDOUT\" 2>\"$VERIFY_STDERR\" &")
    && runScript.contains("trap cleanup_verify_app EXIT")
    && runScript.contains("kCGWindowOwnerPID"), "verify modes use an isolated temporary app and PID-scoped window checks instead of killing the user's active WeiBei window")
expect(runScript.contains("PACKAGE_ONLY=false")
    && runScript.contains("MODE=\"package\"")
    && runScript.contains("package blocked: $APP_DISPLAY_NAME is running")
    && runScript.contains("exit 6")
    && runScript.contains("package)\n    ;;")
    && runScript.contains("usage: $0 [run|check|package|--debug"), "run script package mode updates dist without killing or opening the app")
expect(runScript.contains("CHECK_ONLY=false")
    && runScript.contains("MODE=\"check\"")
    && runScript.contains("if [[ \"$CHECK_ONLY\" == true ]]; then")
    && runScript.contains("if [[ \"$CHECK_ONLY\" != true ]]; then")
    && runScript.contains("check)\n    run_verifiers")
    && runScript.contains("usage: $0 [run|check|package|--debug"), "run script check mode runs build checks without killing, packaging, or opening the app")
let editorIndexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
let editorIndexSource = (try? String(contentsOf: editorIndexURL, encoding: .utf8)) ?? ""
expect(!editorIndexSource.contains("WeiBeiStele")
    && !editorIndexSource.contains("--font-brand-latin")
    && !editorIndexSource.contains("font-family: var(--font-brand-latin)")
    && editorIndexSource.contains(".ProseMirror h1,\n    .ProseMirror h2,\n    .ProseMirror h3")
    && editorIndexSource.contains("letter-spacing: 0;"), "Web Markdown editor does not apply bundled WeiBei display fonts inside Markdown file content")
expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout::before { content: attr(data-callout-title); }")
    && !editorIndexSource.contains("content: \"札记\"")
    && !editorIndexSource.contains("content: \"提示\"")
    && !editorIndexSource.contains("content: \"重点\"")
    && !editorIndexSource.contains("content: \"风险\""), "Markdown callout labels come from data-callout-title instead of hardcoded Chinese CSS")
expect(
    editorIndexSource.contains(".ProseMirror span[data-type=\"math_inline\"],")
        && editorIndexSource.contains(".ProseMirror span[data-type=\"math-inline\"],")
        && editorIndexSource.contains(".ProseMirror div[data-type=\"math-block\"],")
        && editorIndexSource.contains(".ProseMirror .math-inline")
        && editorIndexSource.contains(".ProseMirror .math-block"),
    "math styling hides raw source for common Milkdown math node attribute and class shapes"
)
expect(
    editorIndexSource.contains(".ProseMirror .math-inline {\n      color: transparent")
        && editorIndexSource.contains("font-size: 0;")
        && editorIndexSource.contains("font-size: 1rem;")
        && editorIndexSource.contains(".ProseMirror .katex-error {\n      color: var(--cinnabar)"),
    "math styling collapses raw source while keeping KaTeX and errors readable"
)
expect(editorIndexSource.contains("color: rgba(58, 46, 38, .56)") && !editorIndexSource.contains("color: rgba(58, 46, 38, .36)"), "editable markdown markers stay readable on paper")
expect(editorIndexSource.contains(".frontmatter-title {\n      color: var(--muted)") && editorIndexSource.contains("li[data-item-type=\"task\"][data-checked=\"true\"] {\n      color: var(--muted)"), "small frontmatter and completed task text avoid faint low-contrast ink")
if let frontmatterStart = editorIndexSource.range(of: ":root[data-weibei-theme=\"inkstone\"] #frontmatter-panel")?.lowerBound,
   let frontmatterEnd = editorIndexSource[frontmatterStart...].range(of: "\n\n    .ProseMirror")?.lowerBound {
    let darkFrontmatterSource = String(editorIndexSource[frontmatterStart..<frontmatterEnd])
    expect(darkFrontmatterSource.contains("background: var(--paper-raised);")
        && darkFrontmatterSource.contains("border-color: var(--line);")
        && darkFrontmatterSource.contains("border-left-color: var(--cinnabar-line);")
        && !darkFrontmatterSource.contains("rgba(28, 28, 28")
        && !darkFrontmatterSource.contains("border-color: #2d2d2d"), "dark frontmatter panel uses shared theme variables instead of hardcoded ink blocks")
} else {
    expect(false, "dark frontmatter panel style is readable")
}
expect(editorIndexSource.contains(".weibei-source-reference") && editorIndexSource.contains("border-bottom: 1px dotted"), "source references have readable link styling")
expect(editorIndexSource.contains("scrollbar-width: thin")
    && editorIndexSource.contains("scrollbar-color: transparent transparent")
    && editorIndexSource.contains("#editor::-webkit-scrollbar {\n      width: 6px;")
    && editorIndexSource.contains("#editor.weibei-scroll-active::-webkit-scrollbar-thumb")
    && editorIndexSource.contains(".ProseMirror pre::-webkit-scrollbar-thumb")
    && editorIndexSource.contains("width: 5px;")
    && editorIndexSource.contains("background: transparent;")
    && editorIndexSource.contains(".ProseMirror pre.weibei-scroll-active::-webkit-scrollbar-thumb")
    && editorIndexSource.contains("background: rgba(92, 70, 46, .16)"), "web editor root and internal code/math scrollbars fade in while active instead of disappearing completely")
expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout[data-callout-title=\"阅读线索\"]")
    && editorIndexSource.contains("background: rgba(251, 245, 234, .18);")
    && editorIndexSource.contains("box-shadow: none;")
    && editorIndexSource.contains("border-left-color: rgba(145, 38, 28, .28);"), "reading-line callouts render as light margin notes instead of heavy cards")
expect(editorIndexSource.contains(":root[data-weibei-theme=\"inkstone\"] .ProseMirror blockquote.weibei-callout[data-callout-title=\"阅读线索\"]")
    && editorIndexSource.contains("background: rgba(166, 54, 43, .055);")
    && editorIndexSource.contains("border-left-color: rgba(166, 54, 43, .38);"), "reading-line callouts use a dark-theme wash instead of a stray pale paper block")
expect(editorIndexSource.contains(".ProseMirror blockquote.weibei-callout .weibei-callout-marker")
    && editorIndexSource.contains("display: inline-block !important;")
    && editorIndexSource.contains("opacity: 0 !important;")
    && editorIndexSource.contains("visibility: hidden !important;")
    && editorIndexSource.contains("width: 0 !important;")
    && editorIndexSource.contains("max-width: 0 !important;")
    && editorIndexSource.contains("overflow: hidden !important;"), "Obsidian callout source markers collapse inside rendered callouts")
expect(editorIndexSource.contains("body[data-editable=\"true\"] .ProseMirror blockquote.weibei-callout.weibei-callout-has-heading::before")
    && editorIndexSource.contains("body[data-editable=\"false\"] .ProseMirror blockquote.weibei-callout .weibei-callout-heading {\n      display: none;"), "callout headings stay editable while read-only callouts show the rendered title instead of leaking the raw [!type] source line")
expect(editorIndexSource.contains(".ProseMirror::selection,\n    .ProseMirror ::selection")
    && editorIndexSource.contains("background: var(--selection);"), "web editor selection highlight covers both root and nested ProseMirror text")
expect(editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] #editor")
    && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] .milkdown")
    && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"] .ProseMirror")
    && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"][data-weibei-theme=\"inkstone\"] body")
    && editorIndexSource.contains(":root[data-weibei-compact-preview=\"true\"][data-weibei-theme=\"inkstone\"] #editor")
    && editorIndexSource.contains("min-height: 0;"), "web markdown renderer has a compact preview mode for inline agent answers without dark theme background blocks")
let webEditorSourceDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/WebEditor/src")
let webEditorSourceURLs = ((FileManager.default.enumerator(
    at: webEditorSourceDirectoryURL,
    includingPropertiesForKeys: nil
)?.allObjects as? [URL]) ?? [])
    .filter { $0.pathExtension == "js" }
    .sorted { $0.path < $1.path }
let webEditorSource = webEditorSourceURLs
    .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    .joined(separator: "\n")
let editorScriptSource = webEditorSource
let webEditorRelativeSourcePaths = Set(webEditorSourceURLs.map {
    $0.path.replacingOccurrences(of: webEditorSourceDirectoryURL.path + "/", with: "")
})
expect(Set([
    "api.js",
    "core/bridge.js",
    "core/i18n.js",
    "core/theme.js",
    "editor.js",
    "features/code-rendering.js",
    "features/decorations.js",
    "features/images.js",
    "features/input-behaviors.js",
    "features/preview.js",
    "features/selection.js",
    "features/slash/commands.js",
    "features/slash/menu.js",
    "markdown/normalize.js",
    "markdown/obsidian.js",
]).isSubset(of: webEditorRelativeSourcePaths), "web editor behavior is split into explicit core, markdown, feature, slash, and public API modules")
expect(editorScriptSource.contains("installQuietScrollIndicators")
    && editorScriptSource.contains("const quietScrollableSelector = '#editor, .ProseMirror pre")
    && editorScriptSource.contains("weibei-scroll-active")
    && editorScriptSource.contains("window.setTimeout(() =>")
    && editorScriptSource.contains("}, 850)"), "web editor removes internal scroll indicator state after a short idle delay")
expect(editorScriptSource.contains("document.addEventListener('pointerdown', () =>")
    && editorScriptSource.contains("post('selectionChanged', { text: '', rect: null });"), "web editor clears stale selection context as soon as the user starts a new click or drag")
expect(editorScriptSource.contains("import { liftListItem } from '@milkdown/kit/prose/schema-list';")
    && editorScriptSource.contains("const emptyListItemTypeAtSelection = (state) =>")
    && editorScriptSource.contains("const exitEmptyListItem = (view) =>")
    && editorScriptSource.contains("handleKeyDown(view, event)")
    && editorScriptSource.contains("event.key === 'Enter'")
    && editorScriptSource.contains("&& exitEmptyListItem(view)")
    && editorScriptSource.contains("event.preventDefault();")
    && editorScriptSource.contains("pressKeyForCheck")
    && editorScriptSource.contains("selection.checkAPI()"), "web editor exits an empty Markdown list item on a second Enter instead of looping bullets")
expect(editorScriptSource.contains("const isCompactPreview = window.weiBeiMarkdownCompactPreview === true")
    && editorScriptSource.contains("post('contentHeightChanged', { height })")
    && editorScriptSource.contains("new ResizeObserver(reportContentHeight)")
    && editorScriptSource.contains("installContentHeightObserver()"), "web editor reports compact markdown preview height back to Swift")
if let mermaidStart = editorIndexSource.range(of: ":root[data-weibei-theme=\"inkstone\"] .weibei-mermaid-render")?.lowerBound,
   let mermaidEnd = editorIndexSource[mermaidStart...].range(of: "\n    .weibei-mermaid-render svg")?.lowerBound {
    let darkMermaidSource = String(editorIndexSource[mermaidStart..<mermaidEnd])
    expect(darkMermaidSource.contains("background: var(--paper-raised);")
        && darkMermaidSource.contains("border-color: var(--line);")
        && !darkMermaidSource.contains("background: #151515;")
        && !darkMermaidSource.contains("border-color: #2d2d2d;"), "dark Mermaid render boxes use shared theme variables instead of hardcoded ink blocks")
} else {
    expect(false, "dark Mermaid render style is readable")
}
let documentTextExtractorURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Services/DocumentTextExtractor.swift")
let documentTextExtractorSource = (try? String(contentsOf: documentTextExtractorURL, encoding: .utf8)) ?? ""
expect(documentTextExtractorSource.contains("private static var pdfTextCache")
    && documentTextExtractorSource.contains("private static var fileTextCache")
    && documentTextExtractorSource.contains("private static let cacheLock = NSLock()")
    && documentTextExtractorSource.contains("return pdfText(url: url)")
    && documentTextExtractorSource.contains("PDFOCRTextExtractor.text(from: document, maxPages: 12)")
    && documentTextExtractorSource.contains("store(text, for: cacheKey, cache: .pdf)")
    && documentTextExtractorSource.contains("maximumPDFCacheBytes")
    && documentTextExtractorSource.contains("maximumFileCacheBytes")
    && documentTextExtractorSource.contains("maximumActiveFileBytes = 4 * 1_024 * 1_024")
    && documentTextExtractorSource.contains("maximumActivePDFPages = 12")
    && documentTextExtractorSource.contains("maximumActivePDFCharacters = 64_000")
    && documentTextExtractorSource.contains("maximumActivePDFTextSeconds: TimeInterval = 2")
    && documentTextExtractorSource.contains("BoundedPDFTextExtractor.pages")
    && documentTextExtractorSource.contains("static func cachedText(for item: StudyItem)")
    && !documentTextExtractorSource.contains("page.string")
    && documentTextExtractorSource.contains("handle.read(upToCount: maximumActiveFileBytes)")
    && documentTextExtractorSource.contains("totalBytes > byteLimit"), "active-material extraction uses byte-bounded thread-safe caches while the persistent course index owns full-library search")
let courseDocumentIndexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBeiCore/CourseDocumentSearchIndex.swift")
let courseDocumentIndexSource = (try? String(contentsOf: courseDocumentIndexURL, encoding: .utf8)) ?? ""
let pdfTextWorkerURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBeiPDFTextWorker/main.swift")
let pdfTextWorkerSource = (try? String(contentsOf: pdfTextWorkerURL, encoding: .utf8)) ?? ""
let boundedPDFTextExtractorURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBeiCore/BoundedPDFTextExtractor.swift")
let boundedPDFTextExtractorSource = (try? String(contentsOf: boundedPDFTextExtractorURL, encoding: .utf8)) ?? ""
expect(courseDocumentIndexSource.contains("CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5")
    && courseDocumentIndexSource.contains("private let indexingQueue")
    && courseDocumentIndexSource.contains("private let metadataQueue")
    && courseDocumentIndexSource.contains("metadataQueue.async { [weak self] in")
    && courseDocumentIndexSource.contains("let resolvedURL = url.resolvingSymlinksInPath()")
    && courseDocumentIndexSource.contains("resolvedURL.resourceValues")
    && courseDocumentIndexSource.contains("return \"v5#\\(item.kind.rawValue)#\\(metadata.modified)#\\(metadata.size)\"")
    && courseDocumentIndexSource.contains("let metadata = fileMetadata(for: url)")
    && courseDocumentIndexSource.contains("private let ocrQueue")
    && courseDocumentIndexSource.contains("indexPDFTextLayer")
    && courseDocumentIndexSource.contains("finishPDFOCR")
    && courseDocumentIndexSource.contains("PDFOCRTextExtractor.pageOutcome")
    && courseDocumentIndexSource.contains("withWriteTransaction")
    && courseDocumentIndexSource.contains("ROLLBACK")
    && courseDocumentIndexSource.contains("storageID(for: item.id)")
    && courseDocumentIndexSource.contains("ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY rank)")
    && courseDocumentIndexSource.contains("state?.chunkCount")
    && courseDocumentIndexSource.contains("refreshChangedItemsForLookup")
    && courseDocumentIndexSource.contains("let persistedStates: [String: FileState]")
    && courseDocumentIndexSource.contains("shouldIndexImmediately = state.signature != scheduled.signature")
    && courseDocumentIndexSource.contains("shouldIndexImmediately = true")
    && courseDocumentIndexSource.contains("maximumImmediateRefreshItems = 24")
    && courseDocumentIndexSource.contains("maximumImmediateRefreshSeconds: TimeInterval = 4")
    && courseDocumentIndexSource.contains("maximumTextSourceBytes: UInt64 = 32 * 1_024 * 1_024")
    && courseDocumentIndexSource.contains("maximumForegroundPDFPages = 32")
    && courseDocumentIndexSource.contains("maximumPDFPageCharacters = 128_000")
    && courseDocumentIndexSource.contains("maximumNativePDFPages: Self.maximumForegroundPDFPages")
    && courseDocumentIndexSource.contains("maximumNativePDFSeconds: min(")
    && courseDocumentIndexSource.contains("guard !Task.isCancelled else { return false }")
    && courseDocumentIndexSource.contains("CourseIndexCancellationProbe")
    && courseDocumentIndexSource.contains("sqlite3_progress_handler")
    && courseDocumentIndexSource.contains("Unmanaged.passRetained(cancellationProbe)")
    && courseDocumentIndexSource.contains("fromOpaque(cancellationContext).release()")
    && courseDocumentIndexSource.contains("acquireItemIndexLock")
    && courseDocumentIndexSource.contains("BoundedPDFTextExtractor.pages")
    && courseDocumentIndexSource.contains("foregroundPDFTextBudget: TimeInterval = 2")
    && courseDocumentIndexSource.contains("backgroundPDFTextBudget: TimeInterval = 20")
    && courseDocumentIndexSource.contains("CREATE TABLE IF NOT EXISTS native_attempted_pages")
    && courseDocumentIndexSource.contains("let pagesToOCR = nativeAttemptedPages.subtracting(processedPages).sorted()")
    && courseDocumentIndexSource.contains("hasPendingNativePDFPages")
    && courseDocumentIndexSource.contains("extraction_kind = 'failed'")
    && !courseDocumentIndexSource.contains("page.string")
    && courseDocumentIndexSource.contains("text-partial")
    && courseDocumentIndexSource.contains("htmlSectionLocationID")
    && courseDocumentIndexSource.contains("html-section-%08x")
    && courseDocumentIndexSource.contains("[\\(locationID)][html-heading-\\(index)]")
    && courseDocumentIndexSource.contains("guard isExpected(signature: signature, for: storageID) else { return false }")
    && courseDocumentIndexSource.contains("BEGIN DEFERRED")
    && courseDocumentIndexSource.contains("CREATE INDEX IF NOT EXISTS chunk_index_item_sort")
    && courseDocumentIndexSource.contains("SELECT COUNT(*) FROM chunk_index WHERE item_id = ?")
    && courseDocumentIndexSource.contains("WHERE item_id = ? AND signature = ?")
    && courseDocumentIndexSource.contains("PRAGMA max_page_count")
    && courseDocumentIndexSource.contains("integerValue(\"PRAGMA max_page_count\"")
    && courseDocumentIndexSource.contains("PRAGMA journal_size_limit=67108864")
    && courseDocumentIndexSource.contains("INSERT INTO chunks(chunks, rank) VALUES('merge', 64)")
    && !courseDocumentIndexSource.contains("VALUES('optimize')")
    && courseDocumentIndexSource.contains("PRAGMA incremental_vacuum")
    && !courseDocumentIndexSource.contains("public func lookup(\n        items: [StudyItem],\n        query: String,\n        maximumCharactersPerItem: Int = 24_000\n    ) -> [String: CourseDocumentIndexResult] {\n        schedule(items)"), "course search persists private FTS chunks, uses rollback-safe writes, OCRs every missing PDF page, and reports incomplete excerpts without rescanning files per question")
expect(pdfTextWorkerSource.contains("setrlimit(RLIMIT_CPU")
    && pdfTextWorkerSource.contains("maximumUTF8Bytes")
    && pdfTextWorkerSource.contains("rawText.prefix(maximumCharacters)")
    && pdfTextWorkerSource.contains("runVerificationProbe"), "native PDF text extraction runs in a resource-limited helper with bounded output")
expect(boundedPDFTextExtractorSource.contains("maximumWorkerTimeout: TimeInterval = 3.5")
    && boundedPDFTextExtractorSource.contains("maximumWorkerResidentBytes: UInt64 = 384 * 1_024 * 1_024")
    && boundedPDFTextExtractorSource.contains("process.environment = environment")
    && boundedPDFTextExtractorSource.contains("proc_pidinfo(processID, PROC_PIDTASKINFO")
    && boundedPDFTextExtractorSource.contains("$0 > maximumResidentBytes")
    && boundedPDFTextExtractorSource.contains("process.terminate()")
    && boundedPDFTextExtractorSource.contains("Darwin.kill(process.processIdentifier, SIGKILL)")
    && boundedPDFTextExtractorSource.contains("outputBox.append(chunk, limit: maximumOutputBytes)")
    && boundedPDFTextExtractorSource.contains("runSafetySelfCheck"), "PDF text worker calls are cancellable, time-limited, memory-monitored, output-bounded, and expose a real safety self-check")
let quietScrollersSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/QuietScrollers.swift")
let quietScrollersSource = (try? String(contentsOf: quietScrollersSourceURL, encoding: .utf8)) ?? ""
let quietScrollersAxisBeforeSize = quietScrollersSource.range(of: "scrollView.hasVerticalScroller = hasVerticalScroller").flatMap { flagRange in
    quietScrollersSource.range(of: "scrollView.verticalScroller?.controlSize = .small").map { sizeRange in
        flagRange.lowerBound < sizeRange.lowerBound
    }
} ?? false
expect(quietScrollersSource.contains("scrollView.scrollerStyle = .overlay")
    && quietScrollersSource.contains("scrollView.autohidesScrollers = true")
    && quietScrollersSource.contains("scrollView.scrollerKnobStyle = .default")
    && !quietScrollersSource.contains("scrollView.scrollerKnobStyle = .dark")
    && quietScrollersAxisBeforeSize
    && quietScrollersSource.contains("hasVerticalScroller: Bool? = nil")
    && quietScrollersSource.contains("configureRecursively(\n        in view: NSView,")
    && quietScrollersSource.contains("static func flashRecursively(in view: NSView, repeatCount: Int = 0)")
    && quietScrollersSource.contains("view.layoutSubtreeIfNeeded()")
    && quietScrollersSource.contains("scrollView.flashScrollers()")
    && quietScrollersSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.18)"), "native scroll views use overlay auto-hiding scrollers with explicit axis control and a delayed visible scroll flash")

expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.pdf")) == .pdf, "pdf detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.html")) == .html, "html detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.md")) == .markdown, "markdown detection")
expect(StudyItemKind.detect(from: URL(fileURLWithPath: "/tmp/a.txt")) == .text, "text detection")

func makeSelectablePDF(at url: URL) {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 420, height: 260)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        expect(false, "create pdf context")
        return
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSString(string: "PDF 可选文本层：利率是资金使用价格的表达。").draw(
        at: CGPoint(x: 42, y: 178),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]
    )
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    expect(data.write(to: url, atomically: true), "write selectable pdf")
}

func makeImageOnlyPDF(at url: URL) {
    let image = NSImage(size: NSSize(width: 900, height: 260))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    NSString(string: "INTEREST RATE OCR PRICE").draw(
        at: CGPoint(x: 48, y: 96),
        withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 54),
            .foregroundColor: NSColor.black
        ]
    )
    image.unlockFocus()

    let document = PDFDocument()
    guard let page = PDFPage(image: image) else {
        expect(false, "create image-only pdf page")
        return
    }
    document.insert(page, at: 0)
    expect(document.write(to: url), "write image-only pdf")
}

func makeBlankImageOnlyPDF(at url: URL) {
    let image = NSImage(size: NSSize(width: 600, height: 300))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    image.unlockFocus()
    let document = PDFDocument()
    guard let page = PDFPage(image: image) else {
        expect(false, "create blank image-only pdf page")
        return
    }
    document.insert(page, at: 0)
    expect(document.write(to: url), "write blank image-only pdf")
}

let selectablePDFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-selectable-pdf-check-\(UUID().uuidString).pdf")
makeSelectablePDF(at: selectablePDFURL)
defer { try? FileManager.default.removeItem(at: selectablePDFURL) }
let selectablePDF = PDFDocument(url: selectablePDFURL)
expect(selectablePDF?.string?.contains("利率是资金使用价格") == true, "PDFKit extracts text from selectable PDF text layer")
let pdfSelections = selectablePDF?.findString("资金使用价格", withOptions: []) ?? []
expect(pdfSelections.count == 1, "PDFKit finds selectable text in generated PDF")
if let selection = pdfSelections.first, let page = selection.pages.first {
    expect(selection.string == "资金使用价格", "PDFSelection preserves selected text")
    let selectedPDFPageIndex = selectablePDF?.index(for: page)
    expect(selectedPDFPageIndex == 0, "PDFSelection resolves selected page index")
    expect(!selection.bounds(for: page).isEmpty, "PDFSelection exposes non-empty page bounds for floating agent anchor")
    let ownerTitle = "Mishkin 教材样例，第 \((selectedPDFPageIndex ?? 0) + 1) 页"
    let context = SelectionContext(text: selection.string ?? "", source: .document, ownerTitle: ownerTitle)
    let reference = SourceReferenceTitle.parse("来源：\(context.ownerTitle)")
    expect(context.label(language: .chinese) == "文档选区：Mishkin 教材样例，第 1 页", "PDF selection context carries the selected page label into the floating agent")
    expect(reference.title == "Mishkin 教材样例" && reference.pageIndex == 0, "PDF selection reference can jump back to the selected page")
} else {
    expect(false, "PDFSelection contains page")
}

let imageOnlyPDFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-image-only-pdf-check-\(UUID().uuidString).pdf")
makeImageOnlyPDF(at: imageOnlyPDFURL)
defer { try? FileManager.default.removeItem(at: imageOnlyPDFURL) }
let imageOnlyPDF = PDFDocument(url: imageOnlyPDFURL)
expect(imageOnlyPDF?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false, "image-only PDF has no native text layer")
let ocrText = imageOnlyPDF.flatMap { PDFOCRTextExtractor.text(from: $0, maxPages: 1) }?.uppercased() ?? ""
expect(ocrText.contains("INTEREST") && ocrText.contains("OCR") && ocrText.contains("PRICE"), "Vision OCR extracts text from image-only PDF pages")
let ocrPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, maxPages: 1) } ?? []
expect(ocrPages.count == 1 && ocrPages[0].lines.contains { $0.text.uppercased().contains("INTEREST") && !$0.boundingBox.isEmpty }, "Vision OCR keeps page text bounds for scanned PDF selection overlays")
let targetedOCRPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, pageIndexes: [0]) } ?? []
expect(targetedOCRPages.count == 1 && targetedOCRPages[0].pageIndex == 0, "Vision OCR can target a specific PDF page for mixed text and scanned documents")
let outOfRangeOCRPages = imageOnlyPDF.map { PDFOCRTextExtractor.pages(from: $0, pageIndexes: [1]) } ?? []
expect(outOfRangeOCRPages.isEmpty, "targeted OCR ignores pages outside the PDF")
let blankImagePDFURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-blank-image-pdf-check-\(UUID().uuidString).pdf")
makeBlankImageOnlyPDF(at: blankImagePDFURL)
defer { try? FileManager.default.removeItem(at: blankImagePDFURL) }
if let blankImagePDF = PDFDocument(url: blankImagePDFURL) {
    expect(
        PDFOCRTextExtractor.pageOutcome(from: blankImagePDF, pageIndex: 0) == .empty(pageIndex: 0),
        "Vision OCR distinguishes a successfully scanned blank page from an extraction failure"
    )
} else {
    expect(false, "open blank image-only pdf")
}

func makeMixedLateOCRPDF(at url: URL) {
    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: 720, height: 420)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        expect(false, "create mixed PDF context")
        return
    }

    for pageIndex in 0..<13 {
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(mediaBox)
        if pageIndex < 12 {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSString(string: "Native text layer content for page \(pageIndex + 1) with enough characters").draw(
                at: CGPoint(x: 48, y: 210),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 24),
                    .foregroundColor: NSColor.black,
                ]
            )
            NSGraphicsContext.restoreGraphicsState()
        } else {
            let image = NSImage(size: NSSize(width: 1_200, height: 500))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: image.size).fill()
            NSString(string: "LATEPAGE OCR TARGET").draw(
                at: CGPoint(x: 70, y: 190),
                withAttributes: [
                    .font: NSFont.boldSystemFont(ofSize: 82),
                    .foregroundColor: NSColor.black,
                ]
            )
            image.unlockFocus()
            var imageRect = CGRect(origin: .zero, size: image.size)
            if let cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) {
                context.draw(cgImage, in: CGRect(x: 35, y: 70, width: 650, height: 270))
            }
        }
        context.endPDFPage()
    }
    context.closePDF()
    expect(data.write(to: url, atomically: true), "write mixed late-OCR PDF")
}

let courseIndexRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-course-index-check-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: courseIndexRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: courseIndexRoot) }
let mixedPDFURL = courseIndexRoot.appendingPathComponent("mixed-late-ocr.pdf")
makeMixedLateOCRPDF(at: mixedPDFURL)
let mixedPDFItem = StudyItem(
    id: "file:\(mixedPDFURL.path)",
    title: "Mixed late OCR",
    subtitle: mixedPDFURL.lastPathComponent,
    kind: .pdf,
    urlPath: mixedPDFURL.path,
    isSample: false
)
let markdownIndexURL = courseIndexRoot.appendingPathComponent("late-section.md")
let lateMarkdownToken = "PERSISTENT_LATE_INDEX_TOKEN"
try? (String(repeating: "ordinary material\n\n", count: 1_500) + lateMarkdownToken)
    .write(to: markdownIndexURL, atomically: true, encoding: .utf8)
let markdownIndexItem = StudyItem(
    id: "file:\(markdownIndexURL.path)",
    title: "Late markdown section",
    subtitle: markdownIndexURL.lastPathComponent,
    kind: .markdown,
    urlPath: markdownIndexURL.path,
    isSample: false
)
let stableHTMLURL = courseIndexRoot.appendingPathComponent("stable-sections.html")
let stableHTMLOriginal = """
<html><body>
<h1>利率</h1><p>ORIGINAL_ALPHA_SECTION 资金价格。</p>
<h2>利率</h2><p>ORIGINAL_BETA_SECTION 购买力变化。</p>
</body></html>
"""
try? stableHTMLOriginal.write(to: stableHTMLURL, atomically: true, encoding: .utf8)
let stableHTMLItem = StudyItem(
    id: "file:\(stableHTMLURL.path)",
    title: "Stable duplicate sections",
    subtitle: stableHTMLURL.lastPathComponent,
    kind: .html,
    urlPath: stableHTMLURL.path,
    isSample: false
)
let blankPDFIndexItem = StudyItem(
    id: "file:\(blankImagePDFURL.path)",
    title: "Blank scanned page",
    subtitle: blankImagePDFURL.lastPathComponent,
    kind: .pdf,
    urlPath: blankImagePDFURL.path,
    isSample: false
)
let courseIndexDatabaseURL = courseIndexRoot.appendingPathComponent("course-search.sqlite3")
let courseIndex = CourseDocumentSearchIndex(databaseURL: courseIndexDatabaseURL)
expect(
    BoundedPDFTextExtractor.runSafetySelfCheck(),
    "bounded PDF worker passes normal execution, timeout, cancellation, memory, and output-overflow probes"
)
let boundedNativeProbe = BoundedPDFTextExtractor.pages(
    from: mixedPDFURL,
    pageIndexes: Array(0..<8),
    maximumCharactersPerPage: 128_000,
    timeout: 3.5
)
if boundedNativeProbe?[0]?.text.contains("Native text layer content for page 1") != true {
    fputs("bounded native PDF diagnostic: \(String(describing: boundedNativeProbe))\n", stderr)
}
expect(
    boundedNativeProbe?[0]?.text.contains("Native text layer content for page 1") == true,
    "bounded PDF worker returns native text for a generated multi-page PDF"
)
courseIndex.schedule([mixedPDFItem, markdownIndexItem, stableHTMLItem, blankPDFIndexItem])
var mixedIndexResult: CourseDocumentIndexResult?
var markdownIndexResult: CourseDocumentIndexResult?
var blankPDFIndexResult: CourseDocumentIndexResult?
var stableHTMLIndexResult: CourseDocumentIndexResult?
for _ in 0..<600 {
    mixedIndexResult = courseIndex.lookup(items: [mixedPDFItem], query: "LATEPAGE OCR TARGET")[mixedPDFItem.id]
    markdownIndexResult = courseIndex.lookup(items: [markdownIndexItem], query: lateMarkdownToken)[markdownIndexItem.id]
    blankPDFIndexResult = courseIndex.lookup(items: [blankPDFIndexItem], query: "blank page")[blankPDFIndexItem.id]
    stableHTMLIndexResult = courseIndex.lookup(items: [stableHTMLItem], query: "ORIGINAL_ALPHA_SECTION ORIGINAL_BETA_SECTION")[stableHTMLItem.id]
    if mixedIndexResult?.text?.uppercased().contains("LATEPAGE") == true,
       markdownIndexResult?.text?.contains(lateMarkdownToken) == true,
       stableHTMLIndexResult?.text?.contains("ORIGINAL_ALPHA_SECTION") == true,
       blankPDFIndexResult?.isTruncated == false {
        break
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
}
expect(
    mixedIndexResult?.isTruncated == true
        && mixedIndexResult?.text?.uppercased().contains("LATEPAGE") == true
        && mixedIndexResult?.text?.contains("第 13 页（OCR）") == true,
    "persistent course index OCRs a scanned page beyond page twelve, keeps its page location, and marks the returned excerpt partial"
)
let nativePDFIndexResult = courseIndex.lookup(
    items: [mixedPDFItem],
    query: "Native text layer content for page 1"
)[mixedPDFItem.id]
if nativePDFIndexResult?.text?.contains("Native text layer content for page 1") != true
    || nativePDFIndexResult?.text?.contains("第 1 页（OCR）") == true {
    fputs("native PDF index diagnostic: \(nativePDFIndexResult?.text ?? "<nil>")\n", stderr)
}
expect(
    nativePDFIndexResult?.text?.contains("Native text layer content for page 1") == true
        && nativePDFIndexResult?.text?.contains("第 1 页（OCR）") != true,
    "persistent course index executes the bounded worker and preserves a real native PDF text-layer result"
)
let indexedPDFCourseContext = CourseKnowledgeIndex.build(
    title: "Indexed PDF",
    sources: [
        CourseKnowledgeSource(
            id: mixedPDFItem.id,
            title: mixedPDFItem.title,
            subtitle: mixedPDFItem.subtitle,
            kind: mixedPDFItem.kind.rawValue,
            role: "material",
            text: mixedIndexResult?.text ?? "",
            isTruncated: mixedIndexResult?.isTruncated ?? true
        ),
    ],
    links: [],
    query: "LATEPAGE OCR TARGET",
    currentMaterialID: nil,
    currentNoteID: nil
)
expect(
    indexedPDFCourseContext.items.first?.headings.contains("第 13 页（OCR）") == true,
    "course search preserves confirmed OCR page locations for exact PDF jumps"
)
if blankPDFIndexResult?.isTruncated != false || blankPDFIndexResult?.text != nil {
    fputs("blank PDF index diagnostic: \(String(describing: blankPDFIndexResult))\n", stderr)
}
expect(
    blankPDFIndexResult?.isTruncated == false && blankPDFIndexResult?.text == nil,
    "persistent course index records a successfully scanned blank PDF page without retrying it forever"
)
expect(
    markdownIndexResult?.isTruncated == true
        && markdownIndexResult?.text?.contains(lateMarkdownToken) == true,
    "persistent course index finds a late text-file section without per-question rescanning and marks the excerpt partial"
)
func stableHTMLSectionIDs(in text: String) -> Set<String> {
    guard let regex = try? NSRegularExpression(pattern: #"\[(html-section-[A-Za-z0-9-]+)\]"#) else {
        return []
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return Set(regex.matches(in: text, range: range).compactMap { match in
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    })
}
let originalStableSectionIDs = stableHTMLSectionIDs(in: stableHTMLIndexResult?.text ?? "")
let stableHTMLWithInsertedDuplicate = """
<html><body>
<h1>利率</h1><p>NEW_INSERTED_SECTION 新增解释。</p>
<h1>利率</h1><p>ORIGINAL_ALPHA_SECTION 资金价格。</p>
<h2>利率</h2><p>ORIGINAL_BETA_SECTION 购买力变化。</p>
</body></html>
"""
try? stableHTMLWithInsertedDuplicate.write(to: stableHTMLURL, atomically: true, encoding: .utf8)
let refreshedStableHTML = courseIndex.lookup(
    items: [stableHTMLItem],
    query: "ORIGINAL_ALPHA_SECTION ORIGINAL_BETA_SECTION"
)[stableHTMLItem.id]
let refreshedStableSectionIDs = stableHTMLSectionIDs(in: refreshedStableHTML?.text ?? "")
expect(
    originalStableSectionIDs.count == 2
        && originalStableSectionIDs.isSubset(of: refreshedStableSectionIDs)
        && refreshedStableSectionIDs.count == 3,
    "HTML section content fingerprints survive insertion of a new same-title section before existing sections"
)
let reopenedCourseIndex = CourseDocumentSearchIndex(databaseURL: courseIndexDatabaseURL)
reopenedCourseIndex.schedule([mixedPDFItem])
let reopenedResult = reopenedCourseIndex.lookup(
    items: [mixedPDFItem],
    query: "LATEPAGE OCR TARGET"
)[mixedPDFItem.id]
expect(
    reopenedResult?.isTruncated == true
        && reopenedResult?.text?.uppercased().contains("LATEPAGE") == true,
    "course full-text index survives reopening without rebuilding the PDF"
)

let splitFailureIndex = CourseDocumentSearchIndex(
    databaseURL: courseIndexRoot.appendingPathComponent("course-search-split-failure.sqlite3"),
    nativePDFTextLoader: { _, pageIndexes, _, _ in
        guard pageIndexes.count == 1, let pageIndex = pageIndexes.first else { return nil }
        let text = pageIndex < 12
            ? "SPLIT_NATIVE_LAYER_PAGE_\(pageIndex + 1) remains native after a failed batch extraction"
            : ""
        return [pageIndex: BoundedPDFTextPage(text: text, isPartial: false)]
    }
)
splitFailureIndex.schedule([mixedPDFItem])
var splitFailureResult: CourseDocumentIndexResult?
for _ in 0..<200 {
    splitFailureResult = splitFailureIndex.lookup(
        items: [mixedPDFItem],
        query: "SPLIT_NATIVE_LAYER_PAGE_1"
    )[mixedPDFItem.id]
    if splitFailureResult?.text?.contains("SPLIT_NATIVE_LAYER_PAGE_1") == true { break }
    try? await Task.sleep(nanoseconds: 50_000_000)
}
expect(
    splitFailureResult?.text?.contains("SPLIT_NATIVE_LAYER_PAGE_1") == true
        && splitFailureResult?.text?.contains("第 1 页（OCR）") != true,
    "a failed native PDF batch is bisected to single pages instead of sending unattempted text pages to OCR"
)

let data = Data("""
{"output":[{"content":[{"type":"output_text","text":"只根据当前材料回答。"}]}]}
""".utf8)
let text = try OpenAIResponsesClient.extractText(from: data)
expect(text == "只根据当前材料回答。", "response parser")
let groundedPrompt = OpenAIResponsesClient.composePrompt(
    question: "解释金融体系",
    materialTitle: "Mishkin 教材样例",
    materialText: "金融体系把储蓄者的资金转移给有投资机会的人。",
    noteTitle: "利率笔记",
    noteText: "## 摘录\n金融体系和利率相关。",
    selectionTitle: "Mishkin 教材样例，第 1 页选区",
    selectionText: "储蓄者的资金转移给有投资机会的人",
    recentMessages: [
        AgentMessage(role: .user, text: "上一问", source: "利率笔记")
    ]
)
expect(groundedPrompt.input.contains("当前材料：Mishkin 教材样例"), "agent prompt includes material title")
expect(groundedPrompt.input.contains("当前笔记：利率笔记"), "agent prompt includes note title")
expect(groundedPrompt.input.contains("当前选区（来源：Mishkin 教材样例，第 1 页选区）："), "agent prompt includes selection source")
expect(groundedPrompt.input.contains("用户（来源：利率笔记）：上一问"), "agent prompt keeps recent message source")
expect(groundedPrompt.instructions.contains("来源依据") && groundedPrompt.instructions.contains("没有用到的来源不要列"), "agent prompt requires grounded source evidence")
expect(groundedPrompt.instructions.contains("学习助手") && !groundedPrompt.instructions.contains("学习 Agent"), "agent prompt speaks as a study assistant instead of internal agent copy")
let multiSelectionPrompt = OpenAIResponsesClient.composePrompt(
    question: "比较这些片段",
    materialTitle: "Mishkin 教材样例",
    materialText: "金融体系与利率。",
    noteTitle: "利率笔记",
    noteText: "",
    selectionTitle: "2 个已选文本片段",
    selectionText: """
    片段 1（来源：Mishkin 教材样例，第 1 页）：
    金融体系转移资金。

    片段 2（来源：利率笔记）：
    利率是资金使用价格。
    """,
    recentMessages: []
)
expect(multiSelectionPrompt.input.contains("当前选区（来源：2 个已选文本片段）：")
    && multiSelectionPrompt.input.contains("片段 1（来源：Mishkin 教材样例，第 1 页）：")
    && multiSelectionPrompt.input.contains("片段 2（来源：利率笔记）："), "agent prompt can carry multiple selected text attachments with source labels")
let assistantDialoguePrompt = OpenAIResponsesClient.composePrompt(
    question: "继续解释",
    materialTitle: "Mishkin 教材样例",
    materialText: "金融体系把储蓄者的资金转移给有投资机会的人。",
    noteTitle: "利率笔记",
    noteText: "",
    selectionText: nil,
    recentMessages: [
        AgentMessage(role: .assistant, text: "上一答", source: nil)
    ]
)
expect(assistantDialoguePrompt.input.contains("助手：上一答")
    && !assistantDialoguePrompt.input.contains("Agent：上一答"), "assistant dialogue turns avoid internal agent labels")
let currentPagePrompt = OpenAIResponsesClient.composePrompt(
    question: "解释当前页",
    materialTitle: "Mishkin 教材样例，第 3 页",
    materialText: "第 1 页\n旧页面内容\n\n第 3 页\n当前页内容\n\n第 4 页\n后续页面内容",
    noteTitle: "利率笔记",
    noteText: "",
    selectionText: nil,
    recentMessages: []
)
expect(currentPagePrompt.input.contains("当前材料：Mishkin 教材样例，第 3 页")
    && currentPagePrompt.input.contains("第 3 页\n当前页内容")
    && !currentPagePrompt.input.contains("旧页面内容")
    && !currentPagePrompt.input.contains("后续页面内容"), "agent prompt focuses PDF material text on the current reader page when the material title has a page reference")
let noteOnlyPrompt = OpenAIResponsesClient.composePrompt(
    question: "整理这段",
    materialTitle: "未选择材料",
    materialText: "",
    noteTitle: "概念笔记",
    noteText: "实际利率需要区分通胀预期。",
    selectionText: "实际利率",
    recentMessages: []
)
expect(noteOnlyPrompt.input.contains("当前材料：无") && noteOnlyPrompt.input.contains("当前选区（来源：概念笔记）："), "note-only prompt anchors selection to the current note")
let englishPrompt = OpenAIResponsesClient.composePrompt(
    question: "Summarize this",
    materialTitle: "",
    materialText: "",
    noteTitle: "",
    noteText: "Real interest rates account for expected inflation.",
    selectionTitle: "",
    selectionText: "real interest rates",
    recentMessages: [
        AgentMessage(role: .assistant, text: "Earlier answer", source: "Current note")
    ],
    language: .english
)
expect(
    englishPrompt.input.contains("Current material: none")
        && englishPrompt.input.contains("Current note: Current note")
        && englishPrompt.input.contains("Current selection (source: Current note):")
        && englishPrompt.input.contains("Assistant (source: Current note): Earlier answer")
        && englishPrompt.instructions.contains("Answer in English")
        && englishPrompt.instructions.contains("Sources used")
        && !englishPrompt.input.contains("当前笔记"),
    "agent prompt has a complete English note-only mode"
)
expect(OpenAIAPIKeyStore.cleaned("  sk-test\n") == "sk-test", "api key cleaning")

do {
    let temporaryKeychainURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("weibei-selfcheck-\(UUID().uuidString).keychain-db")
    let temporaryKeychainPassword = Data("weibei-selfcheck-only".utf8)
    var temporaryKeychain: SecKeychain?
    let createStatus = temporaryKeychainURL.path.withCString { path in
        temporaryKeychainPassword.withUnsafeBytes { password in
            SecKeychainCreate(path, UInt32(password.count), password.baseAddress, false, nil, &temporaryKeychain)
        }
    }
    expect(createStatus == errSecSuccess && temporaryKeychain != nil, "isolated self-check keychain is created without changing the user's default keychain")
    guard let temporaryKeychain else { exit(1) }
    defer {
        SecKeychainDelete(temporaryKeychain)
    }

    let temporaryCredentialStore = WeiBeiCredentialStore(
        service: "com.changfenhuang.weibei.selfcheck.\(UUID().uuidString)",
        account: "OPENAI_API_KEY",
        keychain: temporaryKeychain
    )
    try? temporaryCredentialStore.delete()
    try temporaryCredentialStore.save("  sk-selfcheck\n")
    expect(temporaryCredentialStore.load() == "sk-selfcheck", "isolated credential store save and load")
    try temporaryCredentialStore.delete()
    expect(temporaryCredentialStore.load().isEmpty, "isolated credential store delete")

    // Production path: file under Application Support, no login-keychain UI.
    let fileService = "com.changfenhuang.weibei.selfcheck.file.\(UUID().uuidString)"
    let fileStore = WeiBeiCredentialStore(service: fileService, account: "TEST_KEY")
    try? fileStore.delete()
    try fileStore.save(" sk-file-store \n")
    expect(fileStore.load() == "sk-file-store", "WeiBei app-data credential file save and load")
    try fileStore.delete()
    expect(fileStore.load().isEmpty, "WeiBei app-data credential file delete")
}

expect(
    {
        let paths = readSource("Sources/WeiBeiCore/WeiBeiAgentDataPaths.swift")
        let oauth = readSource("Sources/WeiBei/Support/PiOAuthService.swift")
        let runtime = readSource("Sources/WeiBeiCore/PiAgentRuntime.swift")
        return paths.contains("enum WeiBeiAgentDataPaths")
            && paths.contains("piAuthJSON")
            && oauth.contains("WeiBeiAgentDataPaths.piAuthJSON")
            && !oauth.contains("homeAuthURL")
            && runtime.contains("WeiBeiAgentDataPaths.piAgentDirectory")
            && !runtime.contains("homeDirectoryForCurrentUser.appendingPathComponent(\".pi/agent\"")
    }(),
    "OAuth and Pi config use WeiBei Application Support paths, not terminal ~/.pi"
)

let missingSelectionInsight = QuietInsight.make(
    materialTitle: "利率资料",
    materialText: "实际利率扣除了通货膨胀后的购买力变化。",
    noteText: "# 利率资料\n",
    selectionText: "实际利率扣除了通货膨胀后的购买力变化。"
)
expect(missingSelectionInsight.body.contains("还没有进入笔记"), "selection insight")

let coveredMaterialInsight = QuietInsight.make(
    materialTitle: "利率资料",
    materialText: "实际利率扣除了通货膨胀后的购买力变化。",
    noteText: "实际利率扣除了通货膨胀后的购买力变化。",
    selectionText: nil
)
expect(coveredMaterialInsight.body.contains("已经覆盖"), "covered material insight")
let noteOnlyInsight = QuietInsight.make(
    materialTitle: "新概念笔记",
    materialText: "",
    noteText: "实际利率需要区分名义利率和通胀预期。",
    selectionText: nil
)
expect(noteOnlyInsight.body.contains("当前笔记有一条") && !noteOnlyInsight.body.contains("先导入"), "note-only quiet insight uses note context")
expect(noteOnlyInsight.noteBlock.contains("来源：新概念笔记"), "note-only quiet insight keeps note source")
expect(noteOnlyInsight.noteBlock.contains("> [!note] 阅读线索\n>\n>") && !noteOnlyInsight.noteBlock.contains("静默洞察"), "quiet insight writes as a readable callout instead of a noisy bullet")
let coveredNoteSelectionInsight = QuietInsight.make(
    materialTitle: "新概念笔记",
    materialText: "",
    noteText: "实际利率需要区分名义利率和通胀预期。",
    selectionText: "实际利率需要区分名义利率和通胀预期。"
)
expect(!coveredNoteSelectionInsight.body.contains("当前材料其他段落"), "covered note selection avoids fake material relation")
let agentInsight = QuietInsight.agent(materialTitle: "利率资料", answer: "这份材料更适合先补通胀预期这一层。")
expect(agentInsight?.body.contains("通胀预期") == true, "agent insight keeps answer")
expect(agentInsight?.noteBlock.contains("> [!note] 阅读线索\n>\n>") == true && agentInsight?.noteBlock.contains("Agent 洞察") == false, "agent insight writes the same quiet reading-line callout")
expect(QuietInsight.agent(materialTitle: "利率资料", answer: "   \n") == nil, "empty agent insight is ignored")
let markdownNoiseInsight = QuietInsight.make(
    materialTitle: "Markdown 验收",
    materialText: """
    ![image](missing.png)
    | 能力 | 状态 |
    | --- | --- |
    - [ ] todo
    删除线、重点高亮、货币理论、新概念笔记。
    """,
    noteText: "",
    selectionText: nil
)
expect(!markdownNoiseInsight.body.contains("[image]"), "quiet insight ignores markdown image syntax")
expect(markdownNoiseInsight.body.contains("货币理论"), "quiet insight keeps readable markdown prose")
let foldedCalloutInsight = QuietInsight.make(
    materialTitle: "Callout 验收",
    materialText: """
    > [!note]-折叠标题不应泄漏控制符
    >
    > 利率是资金使用价格的表达。
    """,
    noteText: "",
    selectionText: nil
)
expect(!foldedCalloutInsight.body.contains("[!note]")
    && !foldedCalloutInsight.body.contains("-折叠标题"), "quiet insight removes Obsidian callout control and fold markers")
let calloutSelectionText = MarkdownSelectionSanitizer.clean("""
[!quote] 选区摘录
利率是资金使用价格的表达。
""")
expect(calloutSelectionText == "选区摘录\n利率是资金使用价格的表达。", "selection sanitizer removes visible Obsidian callout control markers from rendered selections")
let quotedCalloutSelectionText = MarkdownSelectionSanitizer.clean("""
> [!warning]- 风险提示
> 普通美元 $5 不应被误伤。
""")
expect(!quotedCalloutSelectionText.contains("[!warning]")
    && quotedCalloutSelectionText.contains("风险提示")
    && quotedCalloutSelectionText.contains("$5"), "selection sanitizer handles quoted and folded callouts without damaging ordinary prose")
let readableMarkdownSelectionText = MarkdownSelectionSanitizer.clean("""
==重点==<br />
[[货币理论|理论别名]]
[[货币理论\\|表格别名]]
![曲线图|120x80](assets/curve.png)
![[assets/curve.png|180]]
~~删除线~~、`代码`、^[脚注说明]
%%内部注释%%
- [x] 已完成项
""")
let expectedReadableMarkdownSelectionText = """
重点
理论别名
表格别名
曲线图
assets/curve.png
删除线、代码、脚注说明
已完成项
"""
expect(readableMarkdownSelectionText == expectedReadableMarkdownSelectionText, "selection sanitizer turns common Markdown and Obsidian writing syntax into readable text for Agent context")
let searchableTags = MarkdownTagSearch.tags(in: """
---
tags:
  - property/rate
  - "#quoted-tag"
---

# 标题不是标签
正文标签 #finance/rate 和 #nested/tag
行内代码 `#not-tag` 不应该进入标签

```swift
let tag = "#code-tag"
```
""")
expect(searchableTags == ["#finance/rate", "#nested/tag", "#property/rate", "#quoted-tag"], "markdown tag search extracts real prose and frontmatter property tags")
expect(MarkdownTagSearch.tags(in: "---\ntags: [banking, #macro/rate]\n---\n正文") == ["#banking", "#macro/rate"], "markdown tag search reads inline frontmatter tag arrays")
expect(MarkdownTagSearch.matches(query: "finance", in: "#finance/rate")
    && MarkdownTagSearch.matches(query: "macro", in: "---\ntags: [banking, macro/rate]\n---")
    && MarkdownTagSearch.matches(query: "#nested", in: "#nested/tag")
    && !MarkdownTagSearch.matches(query: "code-tag", in: "`#code-tag`"), "markdown tag search supports library queries without indexing code")

expect(PageNavigator.previous(0) == 0, "pdf previous clamps first page")
expect(PageNavigator.next(0, pageCount: 2) == 1, "pdf next advances")
expect(PageNavigator.next(1, pageCount: 2) == 1, "pdf next clamps last page")
expect(PageNavigator.display(0, pageCount: 0) == "1 / 1", "pdf display empty")
expect(TopBarLeadingInset.value(isFullScreen: true) == 12, "fullscreen top-left controls start from the left edge")
expect(TopBarLeadingInset.value(isFullScreen: false) == 80
    && TopBarLeadingInset.value(isFullScreen: false) > TopBarLeadingInset.value(isFullScreen: true), "windowed top-left controls clear the traffic-light area")
expect(!PDFModeChipPresentation.showsLabel(isExpanded: false), "pdf mode chip hides text after collapse")
expect(PDFModeChipPresentation.showsLabel(isExpanded: true), "pdf mode chip shows text only during transient expansion")
expect(PDFModeChipPresentation.controlOpacity(isExpanded: false, isHovering: true)
    < PDFModeChipPresentation.controlOpacity(isExpanded: true, isHovering: true), "pdf mode chip fades back even when hover state lingers")
expect(ReaderSearch.cleaned("  利率\n") == "利率", "reader search trims query")
expect(ReaderSearch.firstMatch(in: "实际利率与名义利率", query: "名义")?.location == 5, "reader search finds first match")
expect(ReaderSearch.firstMatch(in: "Money and Banking", query: "money")?.location == 0, "reader search ignores case")
expect(ReaderSearch.firstMatch(in: "Money and Banking", query: " ") == nil, "reader search ignores empty query")
let pdfSourceReference = SourceReferenceTitle.parse("> 来源：Mishkin 教材样例，第 3 页")
expect(pdfSourceReference.title == "Mishkin 教材样例" && pdfSourceReference.pageIndex == 2, "source reference parses pdf page")
let htmlSourceReference = SourceReferenceTitle.parse("来源：货币金融学课程 HTML，章节：实际利率")
expect(
    htmlSourceReference.title == "货币金融学课程 HTML"
        && htmlSourceReference.pageIndex == nil
        && htmlSourceReference.sectionTitle == "实际利率"
        && htmlSourceReference.sectionLocationID == nil
        && htmlSourceReference.sectionOrdinal == nil,
    "source reference parses an exact HTML section"
)
let disambiguatedSourceReference = SourceReferenceTitle.parse("来源：重复教材，条目：7，章节标识：html-section-a1b2c3d4，章节序号：4，章节：利率")
expect(
    disambiguatedSourceReference.title == "重复教材"
        && disambiguatedSourceReference.courseItemOrdinal == 7
        && disambiguatedSourceReference.sectionLocationID == "html-section-a1b2c3d4"
        && disambiguatedSourceReference.sectionOrdinal == 4
        && disambiguatedSourceReference.sectionTitle == "利率",
    "source reference preserves the file and section ordinals needed to disambiguate duplicate titles"
)
let englishSectionReference = SourceReferenceTitle.parse("Source: Repeated Course, item: 2, section id: html-section-d4c3b2a1, section number: 5, section: Interest")
expect(
    englishSectionReference.title == "Repeated Course"
        && englishSectionReference.courseItemOrdinal == 2
        && englishSectionReference.sectionLocationID == "html-section-d4c3b2a1"
        && englishSectionReference.sectionOrdinal == 5
        && englishSectionReference.sectionTitle == "Interest",
    "source reference preserves stable HTML section ordinals in English"
)
let emphasizedSourceReference = SourceReferenceTitle.parse("来源：**Mishkin 教材样例**")
expect(emphasizedSourceReference.title == "Mishkin 教材样例", "source reference ignores whole-title Markdown emphasis")
let inlineCodeSourceReference = SourceReferenceTitle.parse("- 相关资料：`来源：Mishkin 教材样例`")
expect(inlineCodeSourceReference.title == "Mishkin 教材样例", "source reference remains actionable when PI wraps the jump in inline code")
let calloutSourceReference = SourceReferenceTitle.parse("""
> [!quote] 选区摘录
> 实际利率
>
> 来源：Mishkin 教材样例，第 12 页
""")
expect(calloutSourceReference.title == "Mishkin 教材样例" && calloutSourceReference.pageIndex == 11, "source reference parses quote callout")
expect(WikiLink.targetTitle(from: "  货币理论 | 显示名 ") == "货币理论", "wikilink alias keeps target title")
expect(WikiLink.targetTitle(from: "  货币理论 ") == "货币理论", "wikilink plain title")
expect(WikiLink.targetTitle(from: "货币理论#利率") == "货币理论", "wikilink heading target opens note title")
expect(WikiLink.targetTitle(from: "货币理论#^rate-block") == "货币理论", "wikilink block target opens note title")
expect(WikiLink.enclosingTitle(in: "参考 [[货币理论|Money]] 继续写", cursor: 6) == "货币理论", "wikilink title at cursor")
expect(WikiLink.enclosingTitle(in: "参考 [[货币理论#利率]] 继续写", cursor: 8) == "货币理论", "wikilink heading title at cursor")
expect(WikiLink.enclosingTitle(in: "没有双链", cursor: 2) == nil, "wikilink title ignores plain text")
expect(WorkspaceLayout.documentAgentNotes.hasCollapsibleRightPane, "three-pane layout can collapse right pane")
expect(WorkspaceLayout.documentNotesSplit.hasCollapsibleRightPane, "split layout can collapse right pane")
expect(!WorkspaceLayout.immersiveReading.hasCollapsibleRightPane, "immersive reading has no right pane to collapse")
expect(!WorkspaceLayout.immersiveWriting.hasCollapsibleRightPane, "immersive writing keeps one uninterrupted note canvas")
expect(WorkspaceLayout.documentAgentNotes.isDocumentThreePane
    && WorkspaceLayout.documentNotesAgent.isDocumentThreePane
    && !WorkspaceLayout.documentNotesSplit.isDocumentThreePane, "only full document layouts participate in three-pane reordering")
expect(WorkspaceLayout.documentAgentNotes.allowsRailOnlyPanes
    && WorkspaceLayout.documentNotesSplit.allowsRailOnlyPanes
    && !WorkspaceLayout.immersiveConversation.allowsRailOnlyPanes
    && !WorkspaceLayout.immersiveWriting.allowsRailOnlyPanes, "only normal multi-pane layouts can collapse content panes into rail-only mode")
expect(WorkspaceLayout.documentAgentNotes.defaultThreePaneOrder == [.reader, .agent, .notes]
    && WorkspaceLayout.documentNotesAgent.defaultThreePaneOrder == [.reader, .notes, .agent], "legacy three-pane layout presets map to pane role order")
expect(WorkspacePaneRole.normalized([.notes, .reader, .notes]) == [.notes, .reader, .agent], "pane role order normalization preserves user pane order and restores missing panes")
expect(WorkspacePaneRole.agent.focus == .agent
    && WorkspacePaneRole.reader.shortLabel(language: .chinese) == "文"
    && WorkspacePaneRole.notes.label(language: .english) == "Notes", "pane roles expose focus and localized labels")
let reorderOrder: [WorkspacePaneRole] = [.reader, .agent, .notes]
let reorderFrames: [WorkspacePaneRole: CGRect] = [
    .reader: CGRect(x: 0, y: 0, width: 320, height: 600),
    .agent: CGRect(x: 330, y: 0, width: 620, height: 600),
    .notes: CGRect(x: 960, y: 0, width: 360, height: 600)
]
expect(ThreePaneReorderTargeting.targetIndex(order: reorderOrder, frames: reorderFrames, role: .reader, horizontalDelta: 180) == 1, "pane reorder target follows real resized pane overlap instead of fixed thirds")
expect(ThreePaneReorderTargeting.targetIndex(order: reorderOrder, frames: reorderFrames, role: .notes, horizontalDelta: -420) == 1, "pane reorder target works from either edge using the current pane widths")
expect(NoteRenderMode.visibleCases == [.rich, .split, .source]
    && NoteRenderMode.preview.visibleMode == .rich
    && NoteRenderMode.source.visibleMode == .source, "note render modes keep legacy preview data readable while hiding preview from the writing controls")
expect(WorkspaceLayout.documentAgentNotes.label(language: .chinese) == "阅读-对话-笔记"
    && WorkspaceLayout.documentAgentNotes.label(language: .english) == "Reader-Chat-Notes"
    && WorkspaceLayout.documentNotesAgent.label(language: .chinese) == "阅读-笔记-对话"
    && WorkspaceLayout.documentNotesSplit.label(language: .english) == "Reader / Notes", "layout labels use localized task language instead of internal pane names")
expect(WorkspaceLayout.immersiveConversation.systemImage == "bubble.left.and.text.bubble.right" && WorkspaceLayout.immersiveWriting.systemImage == "square.and.pencil", "immersive layouts expose semantic menu icons")
let contentViewSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ContentView.swift")
let contentViewSource = (try? String(contentsOf: contentViewSourceURL, encoding: .utf8)) ?? ""
expect(!contentViewSource.isEmpty, "content view source is readable")
let stableDocumentSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/StableDocumentWorkspace.swift")
let stableDocumentSource = (try? String(contentsOf: stableDocumentSourceURL, encoding: .utf8)) ?? ""
let paneContinuityRecorderSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/PaneContinuityRecorder.swift")
let paneContinuityRecorderSource = (try? String(contentsOf: paneContinuityRecorderSourceURL, encoding: .utf8)) ?? ""
let documentPaneTransitionSource: String = {
    guard let start = contentViewSource.range(of: "private func documentPaneLayoutView() -> some View")?.lowerBound,
          let end = contentViewSource[start...].range(of: "private func estimatedDocumentPaneFrames")?.lowerBound else {
        return ""
    }
    return String(contentViewSource[start..<end])
}()
let threePaneChromeSource: String = {
    guard let start = contentViewSource.range(of: "private struct ThreePaneWorkspaceChrome: View")?.lowerBound,
          let end = contentViewSource[start...].range(of: "private struct LayoutContentView: View")?.lowerBound else {
        return ""
    }
    return String(contentViewSource[start..<end])
}()
expect(!documentPaneTransitionSource.isEmpty
    && documentPaneTransitionSource.contains("ThreePaneWorkspaceChrome(")
    && threePaneChromeSource.contains("StableDocumentWorkspace(")
    && threePaneChromeSource.contains("@EnvironmentObject private var paneReorder: ThreePaneReorderState")
    && !documentPaneTransitionSource.contains("switch order.count")
    && !documentPaneTransitionSource.contains("ResizableTwoPane(")
    && !documentPaneTransitionSource.contains("ResizableThreePane(")
    && !documentPaneTransitionSource.contains(".transition(WeiBeiTransition.layout)")
    && !documentPaneTransitionSource.contains(".transition(WeiBeiTransition.rightPanel)"), "ordinary pane-count changes keep one stable container instead of replacing the layout tree")
expect(stableDocumentSource.contains("WorkspacePaneRole.allCases.map")
    && stableDocumentSource.contains("splitView.install(roleHosts: roleHosts, emptyHost: emptyHost)")
    && stableDocumentSource.contains("animator().frame = frame")
    && stableDocumentSource.contains("private let layoutAnimationDuration = 0.24")
    && stableDocumentSource.contains("equalPaneWidths(count:")
    && stableDocumentSource.contains("visibleOrder.count > displayedVisibleOrder.count")
    && stableDocumentSource.contains("func assertStableOwnership()")
    && stableDocumentSource.contains("roleHosts.values.allSatisfy { $0.superview === self }")
    && stableDocumentSource.contains("EmptyWorkspaceLauncherView().environmentObject(store)")
    && stableDocumentSource.contains("let appearanceMode: WeiBeiAppearanceMode")
    && stableDocumentSource.contains("applyEmptyBoardPaper(to: splitView, mode: appearanceMode)")
    && stableDocumentSource.contains("emptyHost?.layer?.backgroundColor = cgPaper")
    && !stableDocumentSource.contains("removeFromSuperview()")
    && !stableDocumentSource.contains("rootView ="), "document pane hosts remain under one AppKit parent while frames animate; empty board paper syncs via layer + explicit appearanceMode")
expect(stableDocumentSource.contains("recordContinuityTransition(duration: layoutAnimationDuration)")
    && stableDocumentSource.contains("host.layer?.presentation()?.frame ?? host.frame")
    && paneContinuityRecorderSource.contains("WEIBEI_VERIFY_PANE_TRACE_DIR")
    && paneContinuityRecorderSource.contains("1.0 / 60.0"), "pane verification records ownership and presentation frames throughout each animation")
expect(!contentViewSource.contains(".animation(WeiBeiMotion.panel, value: store.showReader)")
    && !contentViewSource.contains(".animation(WeiBeiMotion.panel, value: store.showAgent)")
    && !contentViewSource.contains(".animation(WeiBeiMotion.panel, value: store.showNotes)")
    && !contentViewSource.contains(".animation(WeiBeiMotion.panel, value: store.showRightPane)"), "pane toggles do not animate the entire layout tree")
let paneToggleClusterSource: String = {
    guard let start = contentViewSource.range(of: "private var paneToggleCluster: some View")?.lowerBound,
          let end = contentViewSource[start...].range(of: "private var agentPaneToggleHelp: String")?.lowerBound else {
        return ""
    }
    return String(contentViewSource[start..<end])
}()
expect(!paneToggleClusterSource.isEmpty
    && !paneToggleClusterSource.contains("withAnimation")
    && paneToggleClusterSource.contains("store.toggleReader()")
    && paneToggleClusterSource.contains("store.toggleAgent()")
    && paneToggleClusterSource.contains("store.toggleNotes()"), "top-bar pane toggles hand animation ownership to the stable AppKit container")
let emptyWorkspaceSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/EmptyWorkspaceLauncherView.swift")
let emptyWorkspaceSource = (try? String(contentsOf: emptyWorkspaceSourceURL, encoding: .utf8)) ?? ""
let inspirationCatalogSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBeiCore/EmptyWorkspaceInspiration.swift")
let inspirationCatalogSource = (try? String(contentsOf: inspirationCatalogSourceURL, encoding: .utf8)) ?? ""
let contentRailSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ContentRailView.swift")
let contentRailSource = (try? String(contentsOf: contentRailSourceURL, encoding: .utf8)) ?? ""
expect(contentRailSource.contains("struct ContentRailView: View")
    && contentRailSource.contains("static let normalWidth: CGFloat = ContentRailPolicy.dormantWidth")
    && contentRailSource.contains("static let railOnlyThreshold = ContentRailPolicy.railOnlyThreshold")
    && contentRailSource.contains("ContentRailPolicy.previewWidth(")
    && contentRailSource.contains("ContentRailFloatingPreviewBridge(")
    && contentRailSource.contains("SpatialTapGesture()")
    && contentRailSource.contains("private func nearestItem")
    && !contentRailSource.contains(".popover("), "shared content rail uses the latest compact policy and floats previews beyond the existing pane edge")
expect(stableDocumentSource.contains("EmptyWorkspaceLauncherView().environmentObject(store)")
    && emptyWorkspaceSource.contains("Text(title)")
    && emptyWorkspaceSource.contains("title: \"DOC\"")
    && emptyWorkspaceSource.contains("title: \"CHAT\"")
    && emptyWorkspaceSource.contains("title: \"NOTES\"")
    && emptyWorkspaceSource.contains("action: store.toggleReader")
    && emptyWorkspaceSource.contains("action: store.toggleAgent")
    && emptyWorkspaceSource.contains("action: store.toggleNotes"), "empty workspace exposes direct document, chat, and notes entries through the existing pane toggles")
expect(emptyWorkspaceSource.contains("WeiBeiTypography.englishBrandFont")
    && emptyWorkspaceSource.contains("entryDivider")
    && emptyWorkspaceSource.contains("Rectangle()")
    && !emptyWorkspaceSource.contains("RoundedRectangle")
    && !emptyWorkspaceSource.contains("Capsule()")
    && !emptyWorkspaceSource.contains("stroke(WeiBeiTheme.cinnabar"), "empty workspace entry uses WeiBei English lettering, hairlines, and whitespace without cards, pills, or red outlines")
expect(emptyWorkspaceSource.contains("TimelineView(.periodic(from: .now, by: 60))")
    && emptyWorkspaceSource.contains("EmptyWorkspaceDayPeriod.current(at:")
    && emptyWorkspaceSource.contains("static let compactWidthThreshold: CGFloat = 1140")
    && emptyWorkspaceSource.contains("static let compactHeightThreshold: CGFloat = 680")
    && emptyWorkspaceSource.contains("geometry.size.width < EmptyWorkspaceLayoutMetrics.compactWidthThreshold")
    && emptyWorkspaceSource.contains("min(116, max(76")
    && emptyWorkspaceSource.contains("minimumScaleFactor(0.78)")
    && emptyWorkspaceSource.contains("EmptyWorkspacePaperField(mode: mode, compact: compact)")
    && emptyWorkspaceSource.contains("EmptyWorkspaceResolvedColor.paper")
    && emptyWorkspaceSource.contains("onChange(of: store.appearanceMode)")
    && emptyWorkspaceSource.contains("appearanceEpoch")
    && !emptyWorkspaceSource.contains("WeiBeiThemeRuntime.didChangeNotification"), "empty workspace greeting updates with time; paper field rebuilds once on appearanceMode change")
expect(emptyWorkspaceSource.contains("selectedInspirationID")
    && emptyWorkspaceSource.contains("randomItem(excludingID: currentID")
    && emptyWorkspaceSource.contains("static let entryCenterRatio: CGFloat = 0.402")
    && emptyWorkspaceSource.contains("static let inspirationCenterRatio: CGFloat = 0.66")
    && emptyWorkspaceSource.contains("let entryCenterY = clampedCenterY(")
    && emptyWorkspaceSource.contains("let minimumInspirationCenterY = max(")
    && emptyWorkspaceSource.contains("let inspirationCenterY = min(")
    && emptyWorkspaceSource.contains(".position(x: availableSize.width / 2, y: entryCenterY)")
    && emptyWorkspaceSource.contains(".position(x: availableSize.width / 2, y: inspirationCenterY)")
    && emptyWorkspaceSource.contains("let inspirationSlotHeight = compact")
    && emptyWorkspaceSource.contains("height: inspirationSlotHeight")
    && emptyWorkspaceSource.contains("private func workspaceContent(")
    && emptyWorkspaceSource.contains("if store.showDailyInspiration")
    && emptyWorkspaceSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)")
    && emptyWorkspaceSource.contains("private func entryCluster(")
    && emptyWorkspaceSource.contains("let entryCenterRatio: CGFloat = store.showDailyInspiration ? EmptyWorkspaceLayoutMetrics.entryCenterRatio : 0.5")
    && emptyWorkspaceSource.contains(".id(inspiration.id)")
    && emptyWorkspaceSource.contains(".transition(.opacity)")
    && emptyWorkspaceSource.contains("随机换一则")
    && emptyWorkspaceSource.contains("WeiBeiTypography.englishBrandFont(size: 22, weight: .semibold)")
    && emptyWorkspaceSource.contains("formulaContent(size: compact ? 24 : 30)")
    && emptyWorkspaceSource.contains("inspirationText(size: compact ? 21 : 26)")
    && emptyWorkspaceSource.contains("foregroundStyle(WeiBeiTheme.ink.opacity(0.90))")
    && emptyWorkspaceSource.contains("foregroundStyle(WeiBeiTheme.tertiaryInk)")
    && !emptyWorkspaceSource.contains("Text(store.ui(\"随机换一则\", \"RANDOM\"))")
    && emptyWorkspaceSource.contains("accessibilityHint(Text(store.ui(\"随机换一则灵感\", \"Show a random inspiration\")))")
    && !emptyWorkspaceSource.contains("greetingRule")
    && !emptyWorkspaceSource.contains("inspirationCounter")
    && !emptyWorkspaceSource.contains("%02d / %02d")
    && !emptyWorkspaceSource.contains("inspirationOffset"), "empty workspace inspiration switches randomly without repeating the current item or showing catalog counters")
expect(emptyWorkspaceSource.contains("if store.showDailyInspiration")
    && emptyWorkspaceSource.contains("EmptyWorkspaceInspirationCatalog.item")
    && emptyWorkspaceSource.contains("case \"empty-workspace-calligraphy-light\":")
    && emptyWorkspaceSource.contains("forcedID = \"lanting-clear-breeze\"")
    && emptyWorkspaceSource.contains("case \"empty-workspace-calligraphy-dark\":")
    && emptyWorkspaceSource.contains("forcedID = \"lanting-universe\"")
    && emptyWorkspaceSource.contains("Link(inspiration.sourceLabel")
    && emptyWorkspaceSource.contains("Link(inspiration.rightsLabel")
    && emptyWorkspaceSource.contains("Bundle.module.url(forResource:")
    && !emptyWorkspaceSource.contains("URLSession")
    && !inspirationCatalogSource.contains("URLSession"), "daily inspiration is bundled for offline use while retaining visible source and rights links")
expect(emptyWorkspaceSource.contains("empty-workspace-entry-doc")
    && emptyWorkspaceSource.contains("empty-workspace-entry-chat")
    && emptyWorkspaceSource.contains("empty-workspace-entry-notes")
    && emptyWorkspaceSource.contains("accessibilityLabel"), "empty workspace entries remain individually named and reachable to accessibility automation")
expect(contentViewSource.contains("case .immersiveReading:\n                PersistentPaneHost(role: .reader")
    && !contentViewSource.contains("QuietInsightView")
    && !contentViewSource.contains("AgentDrawerView")
    && !contentViewSource.contains("CornerAgentView"), "immersive reading hosts only the reader; deleted agent overlays are gone")
let themeSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/Theme.swift")
let themeSource = (try? String(contentsOf: themeSourceURL, encoding: .utf8)) ?? ""
// Settings views must be loaded early: top-bar / theme assertions below scan agentSettingsSource.
let settingsViewsDirEarly = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/Settings")
let settingsViewsSourceEarly: String = {
    let urls = (try? FileManager.default.contentsOfDirectory(at: settingsViewsDirEarly, includingPropertiesForKeys: nil)) ?? []
    return urls
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
}()
// appSource is defined later; for early theme checks only the settings union is needed.
// Full agentSettingsSource (app + settings) is rebound after appSource loads.
var agentSettingsSource = settingsViewsSourceEarly
expect(themeSource.contains(".fill(.regularMaterial)") && themeSource.contains("paperWashOpacity"), "header glass uses one shared paper material wash")
expect(themeSource.contains("WeiBeiTheme.glassTint.opacity(0.16 * opacity)") && !themeSource.contains("WeiBeiTheme.paperInset.opacity(0.10 * opacity)"), "header handoff fade avoids a hard paper edge")
expect(themeSource.contains("static func glassTint(for mode:")
    && themeSource.contains("static func glassHighlight(for mode:")
    && themeSource.contains("static func documentMaskFill(for mode:")
    && themeSource.contains("var appearanceMode: WeiBeiAppearanceMode")
    && themeSource.contains("Match the page/window paper exactly")
    && themeSource.contains(".regularMaterial"), "dark glass headers match page paper solidly; light themes keep material wash")
expect(themeSource.contains("paperRaised.opacity(0.985)")
    && themeSource.contains(".opacity(0.015)")
    && !themeSource.contains("paperRaised.opacity(0.92)"), "floating panels stay readable without losing the light glass surface")
expect(!themeSource.contains("func weibeiInputPrompt")
    && !themeSource.contains(".overlay(alignment: .topLeading)")
    && !themeSource.contains("prompt.padding(.top, top)")
    && !themeSource.contains(".foregroundColor(.white)")
    && !themeSource.contains(".foregroundStyle(.white)"), "input placeholders use native prompt text instead of a separate overlay")
expect(themeSource.contains("hovering = isEnabled && isHovering")
    && themeSource.contains(".onChange(of: isEnabled)")
    && themeSource.contains("hovering = false"), "icon buttons clear stale hover state when controls disable or the pointer leaves")
expect(themeSource.contains("func weibeiInputSurface")
    && (themeSource.contains("static var placeholderInk") || themeSource.contains("static func placeholderInk"))
    && themeSource.contains("horizontalPadding: CGFloat = 10")
    && themeSource.contains(".padding(.horizontal, horizontalPadding)")
    && themeSource.contains(".foregroundColor(WeiBeiTheme.ink)")
    && themeSource.contains(".foregroundStyle(WeiBeiTheme.ink)")
    && themeSource.contains(".tint(WeiBeiTheme.link)")
    && !themeSource.contains(".environment(\\.colorScheme, .light)")
    && themeSource.contains(".fill(WeiBeiTheme.paperRaised.opacity(active ? 0.66 : 0.60))")
    && themeSource.contains(".stroke(WeiBeiTheme.glassHighlight.opacity(active ? 0.34 : 0.24), lineWidth: 1)")
    && themeSource.contains(".stroke(WeiBeiTheme.paperInset.opacity(active ? 0.30 : 0.38), lineWidth: 1)")
    && themeSource.contains(".stroke(active ? WeiBeiTheme.link.opacity(0.34) : WeiBeiTheme.hairline.opacity(0.54), lineWidth: 1)")
    && !themeSource.contains("secondaryInk.opacity(0.84)"), "input surfaces use semantic ink without forcing the old light color scheme")
expect(themeSource.contains("enum WeiBeiAppearanceMode")
    && themeSource.contains("case paper")
    && themeSource.contains("case xuan")
    && themeSource.contains("case inkstone")
    && themeSource.contains("case stele")
    && themeSource.contains("var isDark: Bool")
    && themeSource.contains("WeiBeiNativePalette")
    && themeSource.contains("WeiBeiThemeRuntime")
    && themeSource.contains("static var paper: Color")
    && themeSource.contains("documentMaskFill")
    && themeSource.contains("didChangeNotification"), "theme exposes four appearance modes with live palette resolution and document mask fills")
expect(!themeSource.contains("var label: String")
    && !themeSource.contains("var actionLabel: String"), "theme-facing labels require an interface language instead of Chinese-only fallback properties")
expect(themeSource.contains("static let appearance = Animation.easeOut(duration: 0.12)"), "appearance changes use a snappy theme transition")
expect(themeSource.contains("tertiaryInk.opacity(0.58)") && themeSource.contains("tertiaryInk.opacity(0.60)"), "disabled button text remains legible on light paper surfaces")
expect(themeSource.contains("englishDisplayFontName = \"WeiBeiStele-Regular\"")
    && themeSource.contains("englishMonoFontName = \"WeiBeiSteleMono-Regular\"")
    && themeSource.contains("WeiBeiResources.bundle.url(forResource: name, withExtension: \"ttf\")\n                ?? WeiBeiResources.bundle.url(forResource: name, withExtension: \"ttf\", subdirectory: \"Fonts\")")
    && themeSource.contains("case .english:\n            registerBundledFonts()\n            return .custom(englishDisplayFontName, size: size).weight(weight)")
    && themeSource.contains("static func englishBrandFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {\n        registerBundledFonts()")
    && themeSource.contains("case .english:\n            registerBundledFonts()\n            return .custom(englishMonoFontName, size: size)")
    && themeSource.contains("return .custom(englishDisplayFontName, size: size).weight(weight)")
    && !themeSource.contains("englishDisplayFontName = \"WeiBeiStele\"")
    && !themeSource.contains("englishMonoFontName = \"WeiBeiSteleMono\""), "bundled English fonts use registered PostScript names and register before custom SwiftUI font construction")
expect(contentViewSource.contains("ResizableTwoPane<First: View, Second: View>: NSViewRepresentable"), "two-pane layout uses native bridge")
expect(contentViewSource.contains("ResizableThreePane<First: View, Second: View, Third: View>: NSViewRepresentable"), "three-pane layout uses native bridge")
expect(contentViewSource.contains("WeiBeiSplitView: NSSplitView"), "content panes use native split view")
expect(contentViewSource.contains("dividerFill.setFill()")
    && contentViewSource.contains("rect.fill()")
    && contentViewSource.contains("private var dividerFill: NSColor")
    && contentViewSource.contains("private var dividerLine: NSColor")
    && contentViewSource.contains("rect.minY + 14")
    && !contentViewSource.contains("NSColor.clear.setFill()"), "native split divider uses the current paper surface instead of a transparent hard gap")
expect(contentViewSource.contains("override func layout()"), "native split applies saved positions after first real layout")
let courseDrawerHostSource = (try? String(
    contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/WeiBei/Views/CourseDrawerHost.swift"),
    encoding: .utf8
)) ?? ""
expect(contentViewSource.contains("LayoutContentView()")
    && contentViewSource.contains("CourseLibraryDrawerLayer")
    && contentViewSource.contains("struct CourseLibraryDrawerLayer")
    && contentViewSource.contains("CourseDrawerHost")
    // Drawer chrome is AppKit-hosted; ContentView itself must not observe libraryDrawer.
    && contentViewSource.contains("LibraryAwareEscapeBridge")
    && courseDrawerHostSource.contains("NSAnimationContext")
    && courseDrawerHostSource.contains("CourseImmersiveDrawerView")
    && courseDrawerHostSource.contains("installHostingIfNeeded")
    && !contentViewSource.contains("@EnvironmentObject private var libraryDrawer: LibraryDrawerState\n    @FocusState")
    && !contentViewSource.contains(".animation(WeiBeiMotion.layout, value: store.showLibrary)")
    && !contentViewSource.contains("libraryResizeHandle")
    && !contentViewSource.contains("minimumContentWidthWithLibrary"), "course drawer slides over the living workspace without remount lag or layout-spring thrash")
expect(contentViewSource.contains("private let railWidth = ContentRailMetrics.railOnlyWidth")
    && contentRailSource.contains("static let snapThreshold = ContentRailPolicy.snapThreshold")
    && contentRailSource.contains("static let readableWidth = ContentRailPolicy.readableWidth")
    && contentViewSource.contains("handleExpansionRequest(store.paneExpansionRequest")
    && stableDocumentSource.contains("ContentRailPolicy.expansionWidth(recentWidth:"), "normal multi-pane layouts snap to the latest compact rail and restore a bounded readable width")
expect(!contentViewSource.contains("DragGesture()"), "content panes avoid SwiftUI drag resizing")
expect(!contentViewSource.contains(".id(store.layout)"), "layout changes avoid whole-screen identity resets")
expect(contentViewSource.contains("case .immersiveWriting:\n                PersistentPaneHost(role: .notes")
    && !contentViewSource.contains("writingDocumentRailItems")
    && !contentViewSource.contains("writingAssistRailItems")
    && !contentViewSource.contains("writingFirstSplitStorage"), "immersive writing reuses the persistent note host without permanent document or writing-aid rails")
expect(!contentViewSource.contains("PaneSeparator"), "content panes avoid hand-drawn split separators")
expect(contentViewSource.components(separatedBy: ".transition(WeiBeiTransition.layout)").count >= 2
    && !documentPaneTransitionSource.contains(".transition(WeiBeiTransition"), "immersive layouts keep shared transitions while ordinary pane visibility is animated inside the stable container")
expect(!contentViewSource.contains("topBarContentFade"), "top bar avoids a duplicate content fade wash")
expect(contentViewSource.contains("store.toggleLibrary()")
    && contentViewSource.contains("sidebar.left")
    && contentViewSource.contains("private var libraryButton: some View")
    && contentViewSource.contains("active: libraryDrawer.isOpen")
    && contentViewSource.contains("libraryDrawer.isOpen ? store.ui(\"收起课程抽屉\"")
    && !contentViewSource.contains("恢复课程目录")
    && !contentViewSource.contains(".opacity(isImmersiveLayout ? 0.45 : 1)"), "immersive top bar keeps a clear stateful library chooser instead of dimming a live control")
if let leftControlsStart = contentViewSource.range(of: "private var leftPrimaryControls: some View")?.lowerBound,
   let leftControlsEnd = contentViewSource[leftControlsStart...].range(of: "\n    }\n\n    @ViewBuilder\n    private var navigationButtons")?.lowerBound {
    let leftControlsSource = String(contentViewSource[leftControlsStart..<leftControlsEnd])
    if let libraryRange = leftControlsSource.range(of: "libraryButton"),
       let navigationRange = leftControlsSource.range(of: "navigationButtons") {
        expect(libraryRange.lowerBound < navigationRange.lowerBound
            && !leftControlsSource.contains("appearanceToggleButton")
            && !leftControlsSource.contains("books.vertical")
            && !leftControlsSource.contains("presentCourseWorkspace")
            && !leftControlsSource.contains("settingsMenu"), "top-left controls keep library and navigation only; theme + Settings live on the right")
    } else {
        expect(false, "top-left controls expose library and navigation")
    }
} else {
    expect(false, "top-left controls block is inspectable")
}
expect(contentViewSource.contains("WindowFullScreenReader(isFullScreen: $windowIsFullScreen)")
    && contentViewSource.contains("let isFullScreen: Bool")
    && contentViewSource.contains("TopBarLeadingInset.value(isFullScreen: isFullScreen)")
    && contentViewSource.contains("topIconButton(\"arrow.left\", help: store.ui(\"后退\"")
    && contentViewSource.contains("store.navigateBackInWorkspace()")
    && contentViewSource.contains(".keyboardShortcut(\"[\", modifiers: [.command])")
    && contentViewSource.contains("topIconButton(\"arrow.right\", help: store.ui(\"前进\"")
    && contentViewSource.contains("store.navigateForwardInWorkspace()")
    && contentViewSource.contains(".keyboardShortcut(\"]\", modifiers: [.command])")
    && contentViewSource.contains(".disabled(!store.canNavigateBack)")
    && contentViewSource.contains(".disabled(!store.canNavigateForward)"), "top bar exposes app back/forward and shifts left controls away from traffic lights outside fullscreen")
expect(contentViewSource.contains("WeiBeiHeaderHandoffFade(")
    && contentViewSource.contains("opacity: isImmersiveLayout ? 0.42 : 0.34")
    && contentViewSource.contains("appearanceMode: store.appearanceMode")
    && contentViewSource.contains("paperOpacity: backgroundPaperOpacity - (isImmersiveLayout ? 0.06 : 0)")
    && contentViewSource.contains("materialOpacity: backgroundMaterialOpacity + (isImmersiveLayout ? 0.03 : 0)"), "immersive top bar keeps the same chrome while using a lighter glass handoff")
expect(!contentViewSource.contains("文代笔")
    && !contentViewSource.contains("Agent中")
    && !contentViewSource.contains("对话中栏")
    && !contentViewSource.contains("对话右栏")
    && !contentViewSource.contains("shortLayoutLabel"), "compact top bar drops the layout label; no legacy fixed-position labels")
expect(!contentViewSource.contains("showLibrary = false")
    && !contentViewSource.contains("store.layout = ")
    && !contentViewSource.contains("store.showRightPane = true"), "content view routes durable layout changes through WorkspaceStore without closing a user-opened library")
expect(contentViewSource.contains(".weibeiInputSurface(active: searchFocused.wrappedValue, height: controlHeight)")
    && contentViewSource.contains("prompt: Text(store.ui(\"资料内搜索\"")
    && contentViewSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
    && contentViewSource.contains("topIconButton(\"magnifyingglass\", help: store.ui(\"打开资料内搜索\"")
    && !contentViewSource.contains("Label(\"搜索\", systemImage: \"magnifyingglass\")")
    && contentViewSource.contains(".foregroundColor(WeiBeiTheme.ink)")
    && contentViewSource.contains(".foregroundStyle(WeiBeiTheme.ink)")
    && !contentViewSource.contains(".foregroundColor(primaryText)\n                    .foregroundStyle(primaryText)\n                    .tint(WeiBeiTheme.link)"), "top search uses fixed ink on its paper input surface instead of inheriting top bar chrome text")
expect(contentViewSource.contains("private var controlHeight: CGFloat {\n        28\n    }"), "compact top bar controls keep a readable 28-point height")
expect(contentViewSource.contains("private var leftPrimaryControls: some View")
    && contentViewSource.contains("libraryButton\n\n            navigationButtons")
    && !contentViewSource.contains("private var appearanceToggleButton: some View")
    && !contentViewSource.contains("AppearanceThemePaletteButton()")
    && themeSource.contains("struct AppearanceThemePaletteButton")
    && themeSource.contains("ForEach(WeiBeiAppearanceMode.allCases)")
    && themeSource.contains("store.setAppearanceMode(mode)")
    // Theme chooser lives only on Settings → Interface as AionUI-style layout cards.
    && agentSettingsSource.contains("private var themePicker")
    && agentSettingsSource.contains("WeiBeiThemeLayoutPreview(mode:")
    && themeSource.contains("struct WeiBeiThemeLayoutPreview")
    && !agentSettingsSource.contains("AppearanceThemePaletteButton()")
    && !contentViewSource.contains("WeiBeiBrandMark.image(for: store.appearanceMode)")
    && !contentViewSource.contains("private var brandBlock: some View")
    && contentViewSource.contains("openSettings")
    && contentViewSource.contains("openSettings()")
    && contentViewSource.contains("slider.horizontal.3")
    && contentViewSource.contains("打开设置")
    && contentViewSource.contains("WeiBeiIconButtonStyle(active: active, size: 24)")
    && !contentViewSource.contains("WeiBeiIconButtonStyle(active: store.appearanceMode == .inkstone")
    && !contentViewSource.contains("private var settingsMenu: some View")
    && !contentViewSource.contains("Image(systemName: \"gearshape\")"), "top bar is brandless and theme-free; theme lives only on Settings → Interface as layout preview cards")
expect(themeSource.contains("enum WeiBeiIconButtonProminence")
    && themeSource.contains("@Environment(\\.colorScheme)")
    && themeSource.contains("prominence == .primary")
    && themeSource.contains("return (isPressed || hovering) ? WeiBeiTheme.onCinnabar : WeiBeiTheme.cinnabar")
    && themeSource.contains("if isPressed || hovering {\n                return WeiBeiTheme.cinnabar.opacity(primaryOpacity(isPressed: isPressed))")
    && themeSource.contains("? WeiBeiTheme.paperInset.opacity(0.58)\n                : WeiBeiTheme.cinnabarSoft.opacity(0.72)")
    && themeSource.contains("if active { return WeiBeiTheme.cinnabar }")
    && themeSource.contains("colorScheme == .dark ? 0.34 : 0.28")
    && themeSource.contains(".onHover { isHovering in"), "icon buttons share adaptive neutral, selected, primary, hover and press states across light and dark modes")
expect(contentViewSource.contains("private var hasReaderScopedTopActions: Bool")
    && contentViewSource.contains("store.isPaneToggleActive(.reader)")
    && contentViewSource.contains("store.hasSelectedMaterial && hasReaderScopedTopActions")
    && !contentViewSource.contains("shouldShowReferenceAction"), "top material search stays scoped to reader-first layouts; copy-reference is not top-bar chrome")
expect(contentViewSource.contains("if shouldShowSearchAction && !store.showReaderSearch"), "top bar hides the search icon while the search field is already open")
expect(contentViewSource.contains("private var paneToggleCluster: some View")
    && contentViewSource.contains("store.toggleReader()")
    && contentViewSource.contains("store.toggleAgent()")
    && contentViewSource.contains("store.toggleNotes()"), "top bar exposes persistent reader, chat, and notes pane toggles")
expect(!contentViewSource.contains("private var layoutMenu")
    && !contentViewSource.contains(".accessibilityLabel(Text(store.ui(\"切换布局\"")
    && !contentViewSource.contains("shortLayoutLabel")
    && !contentViewSource.contains("englishBrandFont(size: 15.5, weight: .semibold)")
    && !contentViewSource.contains("AppearanceThemePaletteButton()")
    && !agentSettingsSource.contains("AppearanceThemePaletteButton()")
    && agentSettingsSource.contains("themePicker"), "compact top bar is brandless and theme-free; theme lives only on Settings → Interface; legacy layout dropdown stays removed")
expect(contentViewSource.contains("打开设置")
    && contentViewSource.contains("Open Settings"), "top bar settings control has a readable semantic label")
expect(contentViewSource.contains("private var agentPaneToggleHelp: String")
    && contentViewSource.contains("用当前选区打开对话")
    && contentViewSource.contains("store.isPaneToggleActive(.agent)")
    && !contentViewSource.contains("topIconButton(\"bubble.left.and.text.bubble.right\", help: agentButtonHelp)")
    && !contentViewSource.contains("Section(\"Agent 入口\")")
    && !contentViewSource.contains("打开 Agent 对话区"), "top bar names conversation entry by the actual action instead of a generic agent label")
expect(contentViewSource.contains("private var showsGlobalFloatingAgent: Bool")
    && !contentViewSource.contains("guard !store.isConversationSurfaceVisible else { return false }")
    && contentViewSource.contains("SelectionFloatingAgentPlacement.isVisible")
    && contentViewSource.contains("routesToConversation: store.isConversationSurfaceVisible")
    && contentViewSource.contains("multi-pane as well as immersive"), "global selection float appears in multi-pane and immersive; 问 routes to conversation when chat is open")
expect(!themeSource.contains("enum TopBarVariant")
    && themeSource.contains("static let topBarHeight: CGFloat = 38")
    && !contentViewSource.contains("TopBarVariant")
    && !contentViewSource.contains("topBarVariant")
    && !contentViewSource.contains("setTopBarVariant"), "top bar is locked to compact constants; TopBarVariant and its selectors are gone")
let sidebarSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/SidebarView.swift")
let sidebarSource = (try? String(contentsOf: sidebarSourceURL, encoding: .utf8)) ?? ""
expect(sidebarSource.contains("Text(store.ui(\"课程目录\", \"Course Index\")")
    && sidebarSource.contains("Text(store.ui(\"课程空间\", \"Course Space\")")
    && sidebarSource.contains("store.presentCourseWorkspace(.hub)")
    && sidebarSource.contains("store.openCourseSpace(course.id)")
    && sidebarSource.contains("Text(store.ui(\"进入\", \"Enter\")")
    && sidebarSource.contains("store.openCourseSpace(courseID)")
    && sidebarSource.contains("prompt: Text(store.ui(\"搜索课程资料与笔记\"")
    && sidebarSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
    && sidebarSource.contains(".foregroundColor(WeiBeiTheme.ink)"), "course index exposes course-space entry, per-course Enter, and searches materials and notes with readable ink")
let notesAgentSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/NotesAgentView.swift")
let notesAgentSource = (try? String(contentsOf: notesAgentSourceURL, encoding: .utf8)) ?? ""
runRichAnswerEmbeddingSelfChecks()
expect(notesAgentSource.contains("private var noteRailItems: [ContentRailItem]")
    && notesAgentSource.contains("NoteEditorCommand(kind: .scrollToHeading")
    && notesAgentSource.contains("private var agentRailItems: [ContentRailItem]")
    && notesAgentSource.contains("store.requestPaneExpansion(.agent)")
    && notesAgentSource.components(separatedBy: "let railOnly = ContentRailMetrics.isRailOnly(").count >= 3, "notes and conversation share the content rail and navigate after restoring a narrow pane")
let notePaneHeaderSource: String = {
    guard let start = notesAgentSource.range(of: "struct NotePaneView: View")?.lowerBound,
          let end = notesAgentSource.range(of: "private func noteFileStatusColor", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let noteModeControlSource: String = {
    guard let start = notesAgentSource.range(of: "private var noteModeControl: some View")?.lowerBound,
          let end = notesAgentSource.range(of: "private var noteHeaderSubtitle", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let agentPaneHeaderSource: String = {
    guard let start = notesAgentSource.range(of: "struct AgentPaneView: View")?.lowerBound,
          let end = notesAgentSource.range(of: "private var agentPrompt", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let paneHeaderReorderSource: String = {
    guard let start = notesAgentSource.range(of: "struct PaneHeaderReorderModifier")?.lowerBound,
          let end = notesAgentSource.range(of: "private struct AgentComposerField", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let emptyAgentStateSource: String = {
    guard let start = notesAgentSource.range(of: "private var emptyAgentState: some View")?.lowerBound,
          let end = notesAgentSource.range(of: "private func starterChip", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
let notebookCreationPanelSource: String = {
    guard let start = notesAgentSource.range(of: "private struct NotebookCreationPanel")?.lowerBound,
          let end = notesAgentSource.range(of: "final class MarkdownSourceTextView", range: start..<notesAgentSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(notesAgentSource[start..<end])
}()
expect(notesAgentSource.contains("private struct AgentComposerField")
    && notesAgentSource.contains("prompt: Text(prompt)")
    && notesAgentSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)"), "agent tray placeholder uses native prompt text so the cursor and text baseline align")
expect(notesAgentSource.contains("SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)")
    && !notesAgentSource.contains("SelectionAnchorCoordinate.y(")
    && !notesAgentSource.contains("contentView.convert("), "note source editor selection anchors use the shared coordinate helper")
expect(notesAgentSource.contains("onSelectionChange(\"\", nil)")
    && notesAgentSource.contains("guard range.length > 0, let stringRange = Range(range, in: textView.string) else"),
    "note source editor clears stale floating selection state when text selection is removed")
expect(notesAgentSource.contains("applySourcePresentation(")
    && notesAgentSource.contains("in textView: NSTextView")
    && notesAgentSource.contains("calloutControlRegex")
    && notesAgentSource.contains(#"(?m)^(\s*(?:>\s*)*)"#)
    && notesAgentSource.contains(#"(\\?\[![A-Za-z][A-Za-z0-9_-]*\][+-]?\s*)"#)
    && notesAgentSource.contains("let markerColor = NSColor.clear")
    && notesAgentSource.contains("NSFont.monospacedSystemFont(ofSize: 0.1")
    && notesAgentSource.contains(".baselineOffset: 0"), "source and compare mode collapse Obsidian callout control markers, including trailing source spaces, without changing saved markdown")
expect(notesAgentSource.contains("private func refreshSourcePresentation(in textView: NSTextView)")
    && notesAgentSource.contains("refreshSourcePresentation(in: textView)")
    && notesAgentSource.contains("case .applyAgentPatch")
    && notesAgentSource.contains("case .insertMarkdown"), "source editor refreshes callout presentation after agent, command, or attachment insertions")
expect(!sidebarSource.contains("commandPalettePresented.toggle()") && !sidebarSource.contains("Label(\"命令\", systemImage: \"command\")"), "sidebar does not duplicate the command palette entry")
expect(sidebarSource.contains("ScrollView(showsIndicators: false)"), "sidebar hides the heavy system scroll indicator that reads as a divider")
expect(sidebarSource.contains("sidebarSection(title: store.ui(\"内置示例\"")
    && sidebarSource.contains("courseSection")
    && sidebarSource.contains("courseContents(for: course)")
    && sidebarSource.contains("courseItemGroup(")
    && sidebarSource.contains("title: store.ui(\"资料\", \"Materials\")")
    && sidebarSource.contains("title: store.ui(\"笔记\", \"Notes\")")
    && sidebarSource.contains("LinearGradient(")
    && sidebarSource.contains("sidebarSection(title: store.ui(\"独立资料\"")
    && sidebarSource.contains("sidebarSection(title: store.ui(\"独立笔记\""), "course drawer keeps the original styling while expanding each course into a visually nested material-note tree")
expect(sidebarSource.contains("store.unassignedCourseMaterials")
    && sidebarSource.contains("store.courseMaterials(in: courseID)")
    && sidebarSource.contains("store.courseNotes(in: courseID)")
    && sidebarSource.contains("store.filteredItems.filter(\\.isNotebookNote)"), "course drawer filters materials and notes by real membership without hiding notebook notes")
expect(sidebarSource.contains("item.isNotebookNote ? store.activeNotebookItemID == item.id : store.selectedItemID == item.id"), "sidebar highlights the active notebook note separately from the selected reader material")
expect(sidebarSource.contains(".contextMenu")
    && sidebarSource.contains("Button(store.ui(\"重命名笔记\"")
    && sidebarSource.contains("store.promptRenameNotebookNote(itemID: item.id)")
    && sidebarSource.contains("private struct NotebookRenameRow")
    && sidebarSource.contains("store.confirmRenameNotebookNote()")
    && sidebarSource.contains("store.cancelRenameNotebookNote()"), "notebook notes expose inline rename from the library row context menu")
expect(sidebarSource.contains("private var tags: [String]")
    && sidebarSource.contains("store.displayTags(for: item)")
    && sidebarSource.contains("Text(tags.joined(separator: \" \"))")
    && sidebarSource.contains("if !compact, !tags.isEmpty")
    && sidebarSource.contains("compact ? 38 : (tags.isEmpty ? 48 : 58)"), "full notebook rows surface Markdown tags while nested course rows stay compact")
expect(contentViewSource.contains("topIconButton(\"command\", help: store.ui(\"命令面板\""), "top bar keeps the command palette entry")
let commandPaletteSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/CommandPaletteView.swift")
let commandPaletteSource = (try? String(contentsOf: commandPaletteSourceURL, encoding: .utf8)) ?? ""
expect(commandPaletteSource.contains(".weibeiInputSurface(active: searchFocused, height: 36)")
    && commandPaletteSource.contains("prompt: Text(store.ui(\"输入命令\"")
    && commandPaletteSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
    && commandPaletteSource.contains("WeiBeiTheme.hairline.opacity(0.72)")
    && !commandPaletteSource.contains("Divider()"), "command palette search uses WeiBei input surface and semantic hairline")
expect(commandPaletteSource.contains("ScrollView(showsIndicators: false)"), "command palette hides system scroll indicators inside the transient floating panel")
expect(commandPaletteSource.contains("withAnimation(command.animation)") && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "command palette uses layout motion for layout commands")
expect(commandPaletteSource.contains("PaletteCommand(title: store.ui(\"三栏工作台\", \"Three-Pane Workspace\"), shortcut: \"⌥⌘1\"")
    && !commandPaletteSource.contains("WorkspaceLayout.documentNotesAgent.label")
    && commandPaletteSource.contains("WorkspaceLayout.documentNotesSplit.label(language: store.interfaceLanguage), shortcut: \"⌥⌘2\"")
    && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"交换笔记与对话\"")
    && commandPaletteSource.contains("shortcut: \"⌥⌘S\"")
    && commandPaletteSource.contains("store.swapThreePaneSecondaryPanes()"), "command palette exposes one draggable three-pane workspace entry instead of two fixed three-pane presets")
expect(commandPaletteSource.contains("PaletteCommand(title: store.ui(\"聚焦对话\"")
    && !commandPaletteSource.contains("PaletteCommand(title: \"聚焦 Agent\""), "command palette names the conversation pane by task language")
expect(!commandPaletteSource.contains("收起右栏"), "command palette avoids fixed right-pane wording")
expect(!commandPaletteSource.contains("Agent 整理资料与笔记") && !commandPaletteSource.contains("本地排序资料库"), "command palette avoids half-built library organization shortcuts")
expect(commandPaletteSource.contains("store.showLibrary ? store.ui(\"收起课程目录\"")
    && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"聚焦课程目录\"")
    && !commandPaletteSource.contains("恢复资料"), "command palette names the unified library action explicitly")
expect(!commandPaletteSource.contains("PaletteCommand(title: \"顶栏")
    && !contentViewSource.contains("Section(store.ui(\"顶部栏\""), "top bar style selector is removed from settings menu and command palette")
expect(commandPaletteSource.contains("private var rightPaneCommand: PaletteCommand?") && commandPaletteSource.contains("store.layout.hasCollapsibleRightPane"), "command palette hides right pane command when the layout has no auxiliary pane")
expect(commandPaletteSource.contains("收起辅助栏") && commandPaletteSource.contains("展开辅助栏"), "command palette names auxiliary pane action by current state")
expect(commandPaletteSource.contains("title: store.showRightPane ? store.ui(\"收起辅助栏\"")
    && commandPaletteSource.contains("shortcut: \"⌘J\"")
    && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "command palette auxiliary pane command uses layout motion")
expect(commandPaletteSource.contains("if store.canCopyReference")
    && commandPaletteSource.contains("PaletteCommand(title: store.copyReferenceActionTitle")
    && commandPaletteSource.contains("if store.hasSelectedMaterial")
    && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"打开资料内搜索\""), "command palette names copy-reference by the actual current target")
expect(appSource.contains("Button(store.copyReferenceActionTitle) { store.copyCurrentReference() }")
    && !contentViewSource.contains("quote.opening")
    && !contentViewSource.contains("shouldShowReferenceAction"), "copy-reference stays in menu/palette/shortcut, not as permanent top-bar chrome")
expect(commandPaletteSource.contains("private var canControlAgent: Bool")
    && commandPaletteSource.contains("store.isAskingAgent || !store.agentDraft.trimmingCharacters")
    && commandPaletteSource.contains("store.isAskingAgent ? store.cancelAgentRequest() : store.askAgent()"), "command palette switches the send command to stop while the agent is running")
expect(commandPaletteSource.contains("if store.canApplyAgentAnswer") && commandPaletteSource.contains("if store.canReplaceNoteSelection") && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"替换笔记选区\""), "command palette hides agent answer actions until they can work")
if let selectionCommandStart = commandPaletteSource.range(of: "PaletteCommand(title: store.ui(\"问当前选区\"")?.lowerBound,
   let selectionCommandEnd = commandPaletteSource[selectionCommandStart...].range(of: "\n            })")?.upperBound {
    let selectionCommandSource = String(commandPaletteSource[selectionCommandStart..<selectionCommandEnd])
    expect(commandPaletteSource.contains("if store.selectionContext != nil")
        && selectionCommandSource.contains("store.askSelection()")
        && !selectionCommandSource.contains("askAgent()"), "command palette selection action attaches the selection without auto-sending a generated prompt")
} else {
    expect(false, "command palette selection command is inspectable")
}
expect(commandPaletteSource.contains("if store.canOpenSelectedSourceReference") && commandPaletteSource.contains("PaletteCommand(title: store.ui(\"打开选区来源\""), "command palette exposes source jump only for parseable note references")
expect(commandPaletteSource.contains("if store.canUseSelectionAgentSurface") && commandPaletteSource.contains("items.insert(agentSurfaceCommand(.selectionFloat, shortcut: \"⌃⌥3\")"), "command palette only exposes selection-float mode when an anchored selection exists")
expect(commandPaletteSource.contains("private func agentSurfaceCommand(_ surface: AgentSurface, shortcut: String)")
    && commandPaletteSource.contains("surface.actionLabel")
    && !commandPaletteSource.contains("Agent 底部抽屉")
    && !commandPaletteSource.contains("Agent 右下角小窗")
    && !commandPaletteSource.contains("Agent 划线浮层")
    && !commandPaletteSource.contains("Agent 静默洞察"), "command palette uses user-facing agent surface actions instead of internal surface names")
expect(commandPaletteSource.contains("if store.agentSurface != .hidden") && commandPaletteSource.contains("agentSurfaceCommand(.hidden, shortcut: \"⌃⌥0\")"), "command palette hides the agent hide action when already hidden")
let readerViewSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/ReaderView.swift")
let readerViewSource = (try? String(contentsOf: readerViewSourceURL, encoding: .utf8)) ?? ""
expect(readerViewSource.contains("private final class PDFContentRailPreviewLoader")
    && readerViewSource.contains("page.thumbnail(of:")
    && readerViewSource.contains("static let contentRailScript")
    && readerViewSource.contains("window.WeiBeiContentRail")
    && readerViewSource.contains("if railOnly {\n            store.requestPaneExpansion(.reader)"), "PDF and HTML rails use real page or document content and restore narrow reader panes")
expect(readerViewSource.contains("now <= state.userScrollUntil ? \"scroll\"")
    && !readerViewSource.contains("jumpUntil")
    && readerViewSource.contains("postMessage({ id, reason: \"jump\" })"), "html reader treats only the explicit target acknowledgement as a jump and lets real user scrolling take priority")
let selectionAnchorContentPointSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Support/SelectionAnchorContentPoint.swift")
let selectionAnchorContentPointSource = (try? String(contentsOf: selectionAnchorContentPointSourceURL, encoding: .utf8)) ?? ""
expect(selectionAnchorContentPointSource.contains("static func fromLocalPoint")
    && selectionAnchorContentPointSource.contains("static func fromWebPoint")
    && selectionAnchorContentPointSource.contains("static func fromScreenPoint")
    && selectionAnchorContentPointSource.contains("SelectionAnchorCoordinate.y"), "selection anchors use one AppKit-to-SwiftUI coordinate helper")
expect(readerViewSource.contains("readerStyleScript"), "html reader injects responsive reading style")
expect(readerViewSource.contains("overflow-wrap: anywhere"), "html reader prevents narrow-pane clipping")
expect(!readerViewSource.contains("Bundle.module.url(forResource: \"WeiBeiStele\", withExtension: \"ttf\")")
    && !readerViewSource.contains("font-family: \"WeiBeiStele\"")
    && !readerViewSource.contains("h1, h2, h3 { font-family:")
    && readerViewSource.contains("readerStyleScript"), "html reader keeps imported document fonts instead of injecting bundled WeiBei display fonts into file headings")
expect(readerViewSource.contains("WeiBeiNativePalette.cssHex(for: mode)")
    && readerViewSource.contains("color-scheme: \\(scheme)")
    && readerViewSource.contains("tokens.ink")
    && readerViewSource.contains("tokens.link")
    && readerViewSource.contains("tokens.cinnabar")
    && readerViewSource.contains("tokens.selection")
    && readerViewSource.contains("mode.isDark"), "html reader injects per-theme CSS tokens for all four appearance modes")
expect(readerViewSource.contains("::selection { background: \\(tokens.selection); color: \\(tokens.ink); }")
    || readerViewSource.contains("tokens.selection"), "html reader uses theme-token selection colors instead of the default blue highlight")
expect(readerViewSource.contains("document.addEventListener(\"selectionchange\", reportSelection)")
    && readerViewSource.contains("document.addEventListener(\"pointerdown\", () => {")
    && readerViewSource.contains("lastPayload = { text: \"\", x: null, y: null }")
    && readerViewSource.contains("window.requestAnimationFrame")
    && readerViewSource.contains("window.webkit.messageHandlers.selection.postMessage(payload)")
    && readerViewSource.contains("x: rect && text ? rect.left + rect.width / 2 : null")
    && readerViewSource.contains("y: rect && text ? rect.bottom : null")
    && readerViewSource.contains("messageHandlers?.selection?.postMessage")
    && readerViewSource.contains("if (window.weiBeiSuppressSelectionReport) return;")
    && readerViewSource.contains("window.weiBeiSuppressSelectionReport = true;")
    && readerViewSource.contains("x: null,")
    && readerViewSource.contains("y: null"), "html reader reports selection changes live and also clears the floating agent when selection is empty")
expect(readerViewSource.contains("private static let scriptMessageNames = [")
    && readerViewSource.contains("\"appShortcut\"")
    && readerViewSource.contains("private static let scriptMessageNames")
    && readerViewSource.contains("controller.add(context.coordinator, name: name)")
    && readerViewSource.contains("static let appShortcutScript")
    && readerViewSource.contains("[\"1\", \"2\", \"3\", \"a\", \"n\", \"r\", \"t\"].includes(key)")
    && readerViewSource.contains("[\"1\", \"2\", \"3\", \"4\", \"[\", \"]\", \"b\", \"j\", \"k\", \"f\"].includes(key)")
    && readerViewSource.contains("store.handleAppShortcut(key: key, modifiers: modifiers)")
    && readerViewSource.contains("controller.removeScriptMessageHandler(forName: name)"), "html reader forwards app keyboard shortcuts while the web document has focus")
expect(!readerViewSource.contains("readerHeader") && !readerViewSource.contains("statusBar"), "reader avoids duplicate internal chrome under unified top bar")
expect(readerViewSource.contains("ReaderStateMessage") && !readerViewSource.contains("ContentUnavailableView("), "reader empty states use WeiBei paper styling")
expect(readerViewSource.contains("store.selectedMaterialItem?.kind == .pdf") && readerViewSource.contains("if let item = store.selectedMaterialItem"), "reader renders materials, not notebook notes")
expect(readerViewSource.contains("NotebookSelectedReaderView") && readerViewSource.contains("阅读区只显示资料"), "reader explains notebook selection instead of rendering it as material")
expect(readerViewSource.contains("ZStack(alignment: .bottomTrailing)")
    && readerViewSource.contains(".padding(.trailing, isImmersive ? 18 : 10)")
    && readerViewSource.contains(".padding(.bottom, isImmersive ? 18 : 12)")
    && readerViewSource.contains("pdfFloatingControls")
    && !readerViewSource.contains("ZStack(alignment: .bottomLeading)")
    && !readerViewSource.contains("ZStack(alignment: .trailing)"), "pdf controls sit on the bottom-right page edge instead of covering the reading start")
expect(readerViewSource.contains("pdfControlsHovering")
    && readerViewSource.contains("pdfControlsExpanded")
    && readerViewSource.contains("pdfControlsCollapseToken")
    && readerViewSource.contains("private var pdfControlsActive: Bool")
    && readerViewSource.contains("private var pdfControlsActive: Bool {\n        pdfControlsExpanded\n    }")
    && readerViewSource.contains(".onAppear {\n            schedulePDFControlsCollapse(after: 0.9)\n        }")
    && readerViewSource.contains("PDFModeChipPresentation.fillOpacity(isExpanded: pdfControlsExpanded, isHovering: pdfControlsHovering)")
    && readerViewSource.contains("PDFModeChipPresentation.controlOpacity(isExpanded: pdfControlsExpanded, isHovering: pdfControlsHovering)")
    && readerViewSource.contains(".offset(x: 0)")
    && readerViewSource.contains(".scaleEffect(pdfControlsExpanded ? 1 : 0.985, anchor: .trailing)")
    && readerViewSource.contains(".onHover")
    && readerViewSource.contains("if !hovering {\n                schedulePDFControlsCollapse(after: 0.28)\n            }")
    && readerViewSource.contains("revealPDFControls(collapseAfter: 0.85)")
    && readerViewSource.contains("private func collapsePDFControls()")
    && readerViewSource.contains("pdfControlsHovering = false")
    && readerViewSource.contains("guard pdfControlsCollapseToken == token else { return }")
    && !readerViewSource.contains("if hovering {\n                revealPDFControls()\n            }")
    && !readerViewSource.contains("guard pdfControlsCollapseToken == token, !pdfControlsHovering else { return }")
    && !readerViewSource.contains("pdfControlsHovering || pdfControlsExpanded"), "pdf controls stay low-distraction and collapse after pointer idle instead of sticking open")
expect(!readerViewSource.contains("var label: String")
    && !readerViewSource.contains("var help: String")
    && readerViewSource.contains("func label(language: WeiBeiInterfaceLanguage) -> String")
    && readerViewSource.contains("return language.text(\"滚动\", \"Scroll\")")
    && readerViewSource.contains("func help(language: WeiBeiInterfaceLanguage) -> String")
    && readerViewSource.contains("return language.text(\"连续滚动浏览 PDF\", \"continuous PDF scrolling\")")
    && readerViewSource.contains("case .scroll: \"arrow.up.and.down\"")
    && readerViewSource.contains("case .page: \"rectangle.portrait\"")
    && readerViewSource.contains("private var pdfModeToggle: some View")
    && readerViewSource.contains("private var showsPDFModeLabel: Bool")
    && readerViewSource.contains("PDFModeChipPresentation.showsLabel(isExpanded: pdfControlsExpanded)")
    && readerViewSource.contains("if pdfBrowseMode == .page, pdfPageCount > 1")
    && readerViewSource.contains("private func revealPDFControls")
    && readerViewSource.contains("DispatchQueue.main.asyncAfter")
    && readerViewSource.contains("pdfBrowseMode = pdfBrowseMode.toggled")
    && readerViewSource.contains("Image(systemName: pdfBrowseMode.systemImage)")
    && readerViewSource.contains("if showsPDFModeLabel {\n                    Text(pdfBrowseMode.label(language: store.interfaceLanguage))")
    && readerViewSource.contains("private var pdfModeForeground: Color")
    && readerViewSource.contains("return WeiBeiTheme.secondaryInk")
    && readerViewSource.contains(".frame(width: showsPDFModeLabel ? nil : 18, height: 24)")
    && readerViewSource.contains(".accessibilityLabel(Text(store.ui(\"切换 PDF 浏览方式")
    && !readerViewSource.contains("ForEach(PDFBrowseMode.allCases)")
    && !readerViewSource.contains("Button(mode.label)")
    && !readerViewSource.contains("case .scroll: \"连续\""), "pdf mode control uses one compact readable toggle instead of a bulky two-choice segment")
expect(readerViewSource.components(separatedBy: "WeiBeiQuietScrollers.configureRecursively(\n                in: view,\n                hasVerticalScroller: true,\n                hasHorizontalScroller: false\n            )").count >= 3
    && readerViewSource.components(separatedBy: "WeiBeiQuietScrollers.flashRecursively(in: view, repeatCount: 2)").count >= 3, "pdf reader keeps a vertical overlay scrollbar available and flashes it when loading or switching modes")
expect(readerViewSource.contains(".accessibilityLabel(Text(store.ui(\"上一页\"") && readerViewSource.contains(".accessibilityLabel(Text(store.ui(\"下一页\""), "pdf page controls have readable icon labels")
expect(readerViewSource.contains(".keyboardShortcut(\"[\", modifiers: [.command, .option])")
    && readerViewSource.contains(".keyboardShortcut(\"]\", modifiers: [.command, .option])"), "pdf page shortcuts yield command-brackets to workspace history")
expect(!readerViewSource.contains(".disabled(pdfPageIndex"), "pdf pager keeps arrows visible instead of showing grey dead buttons")
expect(readerViewSource.contains("syncReaderLocationTitle")
    && readerViewSource.contains("onUserPageChange: schedulePDFLocationCommit")
    && readerViewSource.contains("if pendingPDFPageRecordsLocation")
    && readerViewSource.contains("Date() <= self.userNavigationDeadline")
    && readerViewSource.contains("[.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .keyDown]")
    && readerViewSource.components(separatedBy: "schedulePDFLocationCommit(next)").count >= 3
    && readerViewSource.contains("store.updateReaderPageIndex(pageIndex)")
    && readerViewSource.components(separatedBy: "store.recordReaderPageNavigationPoint()").count >= 3
    && readerViewSource.contains("let next = PageNavigator.previous(pdfPageIndex)")
    && readerViewSource.contains("let next = PageNavigator.next(pdfPageIndex, pageCount: pdfPageCount)")
    && readerViewSource.components(separatedBy: "guard next != pdfPageIndex else { return }").count >= 3
    && readerViewSource.contains("第 \\(pdfPageIndex + 1) 页"), "pdf reader page updates feed shared reference title and app navigation history")
expect(readerViewSource.contains("var onSelectionChange: (String, CGPoint?, Int) -> Void") && readerViewSource.contains("pageIndex(for: selection, in: view)") && readerViewSource.contains("ownerTitle: ownerTitle"), "pdf selection source uses the selected page, not only the current page")
expect(readerViewSource.contains("private final class ReaderPDFView: PDFView")
    && readerViewSource.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool")
    && readerViewSource.contains("window?.makeFirstResponder(self)")
    && readerViewSource.contains("var reportCurrentSelection: (() -> Void)?")
    && readerViewSource.contains("override func mouseDragged(with event: NSEvent)")
    && readerViewSource.contains("override func mouseUp(with event: NSEvent)")
    && readerViewSource.contains("let view = ReaderPDFView()"), "native PDF text selection accepts first drag and focuses the PDF view instead of losing the first gesture")
if let pdfViewStart = readerViewSource.range(of: "private final class ReaderPDFView: PDFView")?.lowerBound,
   let pdfViewEnd = readerViewSource[pdfViewStart...].range(of: "\n}\n\nextension PDFReaderRepresentable.Coordinator")?.upperBound {
    let readerPDFViewSource = String(readerViewSource[pdfViewStart..<pdfViewEnd])
    expect(readerPDFViewSource.contains("super.mouseDown(with: event)\n        reportCurrentSelection?()")
        && !readerPDFViewSource.contains("clearSelection()"), "PDF mouse down lets PDFKit handle native text selection before reporting instead of clearing the selection first")
    expect(readerPDFViewSource.contains("override func draw(_ page: PDFPage, to context: CGContext)")
        && readerPDFViewSource.contains("guard adaptsDocumentColors else")
        && readerPDFViewSource.contains("super.draw(page, to: context)")
        && readerPDFViewSource.contains("context.setFillColor(adaptedPaperColor.cgColor)")
        && readerPDFViewSource.contains("context.setBlendMode(.multiply)")
        && readerPDFViewSource.contains("page.draw(with: displayBox, to: context)")
        && readerPDFViewSource.contains("layoutDocumentView()")
        && readerPDFViewSource.contains("if let documentView")
        && !readerPDFViewSource.contains("pageOverlayViewProvider"), "PDF color adaptation redraws visible pages below native selection and OCR overlays, with an immediate original-color path")
} else {
    expect(false, "ReaderPDFView source is inspectable")
}
expect(readerViewSource.contains("func reportCurrentSelection(in view: PDFView)")
    && readerViewSource.contains("view.reportCurrentSelection = { [weak coordinator = context.coordinator, weak view] in")
    && readerViewSource.contains("coordinator?.reportCurrentSelection(in: view)")
    && readerViewSource.contains("NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .keyDown])")
    && readerViewSource.contains("if event.type == .leftMouseDown")
    && readerViewSource.contains("view.bounds.contains(location)")
    && readerViewSource.contains("NSEvent.removeMonitor(eventMonitor)"), "PDF selection reporting polls currentSelection after PDFKit internal drag gestures instead of relying only on outer PDFView mouse events")
expect(readerViewSource.contains("PDFPageOverlayViewProvider")
    && readerViewSource.contains("PDFOCRPageOverlayView")
    && readerViewSource.contains("private func setOCRPageOverlayProvider(_ provider: PDFPageOverlayViewProvider?, in view: PDFView)")
    && readerViewSource.contains("view.pageOverlayViewProvider = provider")
    && readerViewSource.contains("view.isInMarkupMode = false"), "scanned PDF OCR overlays are only enabled for image-only PDFs and cleared for native text PDFs")
if let pageOverlayStart = readerViewSource.range(of: "private final class PDFOCRPageOverlayView")?.lowerBound,
   let lineTextStart = readerViewSource.range(of: "private final class PDFOCRLineTextView")?.lowerBound {
    let pageOverlaySource = String(readerViewSource[pageOverlayStart..<lineTextStart])
    let lineTextSource = String(readerViewSource[lineTextStart...])
    expect(pageOverlaySource.contains("override var isFlipped: Bool { false }")
        && !lineTextSource.contains("override var isFlipped"), "PDF OCR page overlay keeps PDF coordinates while line text views keep native NSTextView hit testing")
} else {
    expect(false, "PDF OCR overlay source is readable")
}
expect(readerViewSource.contains("private class ReaderSelectableTextView: NSTextView")
    && readerViewSource.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool")
    && readerViewSource.contains("override func mouseDown(with event: NSEvent)")
    && readerViewSource.contains("window?.makeFirstResponder(self)")
    && readerViewSource.contains("private final class PDFOCRLineTextView: ReaderSelectableTextView")
    && readerViewSource.components(separatedBy: "let textView = ReaderSelectableTextView()").count >= 3
    && !readerViewSource.contains("let textView = NSTextView()"), "PDF OCR, sample PDF, and plain text readers accept first mouse for immediate drag selection")
expect(readerViewSource.contains("private var ocrHighlightedLinesByPageIndex: [Int: Set<Int>] = [:]")
    && readerViewSource.contains("func applySearch(_ query: String, in view: PDFView, force: Bool = false)")
    && readerViewSource.contains("applyOCRSearch(query, in: view)")
    && readerViewSource.contains("line.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])")
    && readerViewSource.contains("highlightedLineIndexes: ocrHighlightedLinesByPageIndex[index] ?? []")
    && readerViewSource.contains("view.go(to: page)")
    && readerViewSource.contains("self.applySearch(self.lastSearchQuery, in: view, force: true)"), "scanned PDF OCR search falls back to recognized lines, jumps to the first OCR hit, and highlights the matching line")
expect(readerViewSource.contains("view.highlightedSelections = matches")
    && readerViewSource.contains("view.go(to: first)")
    && !readerViewSource.contains("view.setCurrentSelection(first, animate: true)"), "PDF search highlights and jumps without creating a fake user selection or selection-agent context")
expect(readerViewSource.contains("@State private var pdfHasSelectableText: Bool?")
    && readerViewSource.contains("var onSelectableTextChange: (Bool?) -> Void")
    && readerViewSource.contains("private var nativeTextPageIndexes: Set<Int> = []")
    && readerViewSource.contains("private var pendingOCRPageIndexes: Set<Int> = []")
    && readerViewSource.contains("private static func selectableTextPageIndexes")
    && readerViewSource.contains("private static func ocrCandidatePageIndexes")
    && readerViewSource.contains("PDFOCRTextExtractor.pages(from: document, pageIndexes: pageIndexes)")
    && readerViewSource.contains("private func ensureOCRForCurrentPage(in view: PDFView)")
    && readerViewSource.contains("PDFOCRTextExtractor.pages(from: document, pageIndexes: [index])")
    && readerViewSource.contains("self.configureOCROverlays(for: document, generation: generation, in: view)\n                    self.ensureOCRForCurrentPage(in: view)")
    && readerViewSource.contains("self.ensureOCRForCurrentPage(in: view)")
    && readerViewSource.contains("onSelectableTextChange(nativeTextPageIndexes.contains(index) || ocrPagesByPageIndex[index] != nil)")
    && readerViewSource.contains("Text(store.ui(\"未检测到可选文本层\"")
    && readerViewSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)")
    && readerViewSource.contains(".allowsHitTesting(false)")
    && !readerViewSource.contains("configureOCROverlays(for: document, hasTextLayer:"), "pdf reader reports selectable text per page so mixed text/scanned PDFs still get OCR overlays")
expect(readerViewSource.contains("selection.color = WeiBeiNativePalette.selectionFill(for: appearanceMode)"), "pdf reader applies the theme-aware WeiBei cinnabar selection tint to the active PDFKit selection")
expect(readerViewSource.contains("onSelectionChange(\"\", nil, pageIndex.wrappedValue)"), "pdf reader clears the floating selection agent when PDF selection is removed")
expect(readerViewSource.contains("private func reportSelectionAfterDragSettles")
    && readerViewSource.contains("selectionWork?.cancel()")
    && readerViewSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.06")
    && !readerViewSource.contains("self.onSelectionChange(text, Self.anchor(for: selection, in: view), selectedPageIndex)"), "pdf reader delays the floating agent callback until dragging settles so selection is not interrupted")
expect((readerViewSource.contains("if let url = item.url {\n                    PDFReaderRepresentable(")
            || readerViewSource.contains("if let url = item.url {\n                    ZStack {\n                        PDFReaderRepresentable("))
    && readerViewSource.contains("SamplePDFView(appearanceMode: store.appearanceMode, language: store.interfaceLanguage)")
    && readerViewSource.contains("SamplePDFSelectablePageView")
    && readerViewSource.contains("textView.isSelectable = true")
    && readerViewSource.contains("textView.delegate = context.coordinator")
    && readerViewSource.contains("coordinator.appliedAppearanceMode != appearanceMode")
    && readerViewSource.contains("SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)")
    && readerViewSource.contains("applyAskUnderlines")
    && readerViewSource.contains("selectionsByLine()")
    && readerViewSource.contains("selectionAskThreadsMenu")
    && readerViewSource.contains("已问 · \\(threads.count)")
    && readerViewSource.contains("handleAskUnderlineHover")
    && readerViewSource.contains("handleAskUnderlineClick")
    && readerViewSource.contains("askUnderlineHoverMarker")
    && !readerViewSource.contains("SelectionAskMarksLegend"), "pdf samples prefer the real PDFKit reader while keeping a selectable fallback page and selection-ask underlines")
expect(readerViewSource.contains("textView.selectedTextAttributes")
    && readerViewSource.contains(".backgroundColor: WeiBeiNativePalette.selectionFill(for: appearanceMode)")
    && readerViewSource.contains(".foregroundColor: WeiBeiNativePalette.selectedText(for: appearanceMode)")
    && readerViewSource.contains("onSelectionChange(\"\", nil)"), "plain text reader uses WeiBei selection color and clears stale floating selection")
expect(readerViewSource.contains("private var suppressSelectionReport = false")
    && readerViewSource.contains("guard !suppressSelectionReport else { return }")
    && readerViewSource.contains("suppressSelectionReport = true\n            textView.setSelectedRange(range)\n            suppressSelectionReport = false"), "plain text search can scroll to a hit without reporting it as a user selection")
expect(readerViewSource.contains("SelectionAnchorContentPoint.fromLocalPoint(localPoint, in: view)")
    && readerViewSource.contains("SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)")
    && readerViewSource.contains("SelectionAnchorContentPoint.fromScreenPoint(screenPoint, in: window)")
    && !readerViewSource.contains("SelectionAnchorCoordinate.y(")
    && !readerViewSource.contains("contentView.convert("), "reader selection anchors route PDF, HTML, and text through the shared coordinate helper")
expect(readerViewSource.contains("private var importedDocumentAdaptationControl: some View")
    && readerViewSource.contains("item.url != nil")
    && readerViewSource.contains("item.kind == .pdf || item.kind == .html")
    && readerViewSource.contains("Image(systemName: \"eyeglasses\")")
    && readerViewSource.contains("WeiBeiIconButtonStyle(active: store.adaptImportedDocumentColors, size: 22)")
    && readerViewSource.contains("store.toggleImportedDocumentColorAdaptation()"), "DOC hover title offers a quiet stateful adaptation control only for imported PDF and HTML materials")
let readerStyleScriptSource: String = {
    guard let start = readerViewSource.range(of: "static func readerStyleScript")?.lowerBound,
          let end = readerViewSource.range(of: "final class Coordinator", range: start..<readerViewSource.endIndex)?.lowerBound else {
        return ""
    }
    return String(readerViewSource[start..<end])
}()
expect(readerViewSource.contains("static func readerStyleScript(for mode: WeiBeiAppearanceMode, adaptsDocumentColors: Bool = true)")
    && readerViewSource.contains("document.documentElement.dataset.weibeiTheme = adaptsDocumentColors ? appearance : \"original\"")
    && readerViewSource.contains("[data-weibei-paper-surface] { background-color: transparent !important; }")
    && readerViewSource.contains(".slice(0, 2500)")
    && readerViewSource.contains("element.removeAttribute(\"data-weibei-paper-surface\")")
    && !readerStyleScriptSource.contains("MutationObserver"), "HTML adaptation is reversible and bounds its one-time near-white surface pass without a persistent DOM observer")
expect(readerViewSource.contains("pendingPDFPageIndex")
    && readerViewSource.contains("pendingPDFPageRecordsLocation")
    && readerViewSource.contains("applyPendingPDFPageIfReady")
    && readerViewSource.contains("store.consumeReaderPDFPageRequest(requestID)"), "pdf reader consumes source-jump target pages and only persists requests marked as user navigation")
expect(readerViewSource.contains("applyPendingHTMLLocationIfReady")
    && readerViewSource.contains("store.readerTargetLocationID")
    && readerViewSource.contains("store.readerTargetLocationTitle")
    && readerViewSource.contains("targetID = matches.count == 1 ? matches[0].id : nil")
    && readerViewSource.contains("Self.normalizedHTMLSectionTitle(savedSection.title)")
    && readerViewSource.contains("document.querySelectorAll(\"h1, h2, h3, h4\")")
    && !readerViewSource.contains("h1, h2, h3, h4, [role='heading']")
    && readerViewSource.contains("const headings = Array.from(document.querySelectorAll")
    && readerViewSource.contains("sectionFingerprintBody")
    && readerViewSource.contains("sectionLocationID")
    && readerViewSource.contains("new TextEncoder().encode(normalized)")
    && readerViewSource.contains("`html-section-${hash.toString(16).padStart(8, \"0\")}`")
    && readerViewSource.contains("store.updateReaderHTMLLocation(id: id, title: title, reason: reason.rawValue)"), "HTML reader persists the active section and consumes exact section jumps")
expect(readerViewSource.contains("onSourceReference: { reference in store.openSourceReference(reference) }"), "markdown reader source references can jump back to material")
expect(readerViewSource.contains("private struct SamplePDFView")
    && readerViewSource.contains("ScrollView {")
    && !readerViewSource.contains("SamplePDFView: View {\n    var body: some View {\n        ScrollView(showsIndicators: false)"), "sample pdf page keeps the system scroll indicator available")
let richEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/RichMarkdownEditorView.swift")
let richEditorSource = (try? String(contentsOf: richEditorSourceURL, encoding: .utf8)) ?? ""
expect(richEditorSource.contains("let editorDirectory = url.deletingLastPathComponent()")
    && richEditorSource.contains("view.loadFileURL(url, allowingReadAccessTo: editorDirectory.deletingLastPathComponent())"), "rich Markdown editor grants WKWebView access across the bundled resource directory for font assets")
expect(richEditorSource.contains("SelectionAnchorContentPoint.fromWebPoint(x: x, y: y, in: view)")
    && !richEditorSource.contains("SelectionAnchorCoordinate.y(")
    && !richEditorSource.contains("contentView.convert("), "rich markdown editor selection anchors use the shared coordinate helper")
expect(richEditorSource.contains("var passesVerticalScrollToSuperview = false")
    && richEditorSource.contains("override func scrollWheel(with event: NSEvent)")
    && richEditorSource.contains("override func hitTest(_ point: NSPoint) -> NSView?")
    && richEditorSource.contains("NSApp.currentEvent?.type == .scrollWheel")
    && richEditorSource.contains("abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)")
    && richEditorSource.contains("nearestSuperviewScrollView()")
    && richEditorSource.contains("func scrollOuterSuperview(deltaY: CGFloat)")
    && richEditorSource.contains("window.addEventListener(\"wheel\"")
    && richEditorSource.contains("compactPreviewWheel")
    && richEditorSource.contains("clipView.scroll(to:")
    && richEditorSource.contains("outerScrollView.scrollWheel(with: event)")
    && richEditorSource.contains("return self.forwardVerticalScroll(event) ? nil : event")
    && richEditorSource.contains("guard abs(nextY - clipView.bounds.origin.y) > 0.01 else { return false }")
    && richEditorSource.contains("view.passesVerticalScrollToSuperview = isCompactPreview")
    && richEditorSource.contains("(view as? MarkdownWebView)?.passesVerticalScrollToSuperview = isCompactPreview")
    && richEditorSource.contains("NSEvent.addLocalMonitorForEvents(matching: .scrollWheel)")
    && richEditorSource.contains("bounds.contains(localPoint)")
    && richEditorSource.contains("return nil"), "compact markdown previews pass vertical wheel events to the outer conversation scroll instead of trapping the pointer over message text")
expect(richEditorSource.contains("var documentID = \"\"") && richEditorSource.contains("var pendingExternalMarkdown: String?"), "rich editor tracks document identity and pending external sync")
expect(!richEditorSource.contains("nativeViewCache")
    && !richEditorSource.contains("cached.view.removeFromSuperview()")
    && !readerViewSource.contains("nativeViewCache")
    && !readerViewSource.contains("cached.view.removeFromSuperview()"), "native readers and editors rely on stable pane ownership instead of detach-and-reattach caches")
expect(
    richEditorSource.contains("window.weiBeiDocumentID")
        && richEditorSource.contains("func setDocumentID(_ id: String)")
        && richEditorSource.contains("if message.name != \"editorReady\" {")
        && richEditorSource.contains("guard messageMatchesDocument(message.body) else { return }")
        && richEditorSource.contains("case \"editorReady\":\n                isReady = true\n                setDocumentID(documentID)")
        && richEditorSource.contains("setMarkdownBaseURL(markdownBaseURLString)")
        && richEditorSource.contains("setEditable(isEditable)"),
    "rich editor accepts a late ready callback, reapplies the current document, and rejects every other stale callback"
)
expect(richEditorSource.contains("guard text == pendingExternalMarkdown else { return }"), "rich editor ignores stale markdown callbacks during document sync")
expect(richEditorSource.contains("command && shift && !option && !control") && richEditorSource.contains("[\"a\", \"r\", \"e\", \"c\"].includes(key)"), "rich editor forwards command-shift agent shortcuts to Swift")
expect(richEditorSource.contains("[\"1\", \"2\", \"3\", \"4\", \"[\", \"]\", \"b\", \"j\", \"k\", \"f\"].includes(key)"), "rich editor forwards workspace history shortcuts to Swift")
expect(richEditorSource.contains("runPendingCommandIfReady()")
    && richEditorSource.contains("guard isReady,")
    && richEditorSource.contains("self.command.wrappedValue = nil"), "rich editor does not drop commands before the web editor is ready")
expect(richEditorSource.contains("var appearanceMode: WeiBeiAppearanceMode = .paper")
    && richEditorSource.components(separatedBy: "appearanceMode: appearanceMode").count >= 4
    && richEditorSource.contains("private static func applyWebAppearance(to view: WKWebView, appearanceMode: WeiBeiAppearanceMode)")
    && richEditorSource.contains("view.underPageBackgroundColor = WeiBeiNativePalette.paper(for: appearanceMode)")
    && richEditorSource.contains("view.appearance = NSAppearance(named: appearanceMode.isDark ? .darkAqua : .aqua)")
    && richEditorSource.contains("private var missingImageColors: (background: String, accent: String, text: String)")
    && richEditorSource.contains("case .inkstone:")
    && richEditorSource.contains("case .xuan:")
    && richEditorSource.contains("case .stele:")
    && richEditorSource.contains("return (\"#151515\", \"#a6362b\", \"#d7cbb0\")"), "native missing-image placeholders follow the current editor theme instead of always using a pale SVG")
expect(richEditorSource.contains("selection?.removeAllRanges();")
    && richEditorSource.contains("messageHandlers?.selectionChanged?.postMessage")
    && richEditorSource.contains("text: \"\",")
    && richEditorSource.contains("rect: null")
    && richEditorSource.contains("window.weiBeiSuppressSelectionReport = true;")
    && richEditorSource.contains("window.setTimeout(() => { window.weiBeiSuppressSelectionReport = false; }, 80);"), "rich markdown search clears stale floating selection state without reporting the search hit as an agent selection")
expect(richEditorSource.contains("window.weiBeiInterfaceLanguage =")
    && richEditorSource.contains("document.documentElement.dataset.weibeiLanguage = window.weiBeiInterfaceLanguage")
    && richEditorSource.contains("func setInterfaceLanguage(_ language: WeiBeiInterfaceLanguage)")
    && richEditorSource.contains("context.coordinator.setInterfaceLanguage(interfaceLanguage)"), "rich markdown editor passes interface language changes into the web editor")
expect(!webEditorSource.contains("event.metaKey && event.shiftKey && event.key.toLowerCase() === 'a'"), "web editor does not steal command-shift-a from Swift agent write action")
expect(webEditorSource.contains("const insertionCursorMarker = '{{WEIBEI_CURSOR}}'")
    && webEditorSource.contains("insertionSelectionStartMarker")
    && webEditorSource.contains("placeCursorAtInsertionMarker()"), "web editor removes command snippet cursor markers after insertion")
expect(webEditorSource.contains("createBridge(window.webkit?.messageHandlers, window.weiBeiDocumentID || '')")
    && webEditorSource.contains("let currentDocumentID = initialDocumentID || ''")
    && webEditorSource.contains("postMessage({ ...body, documentID: currentDocumentID })")
    && webEditorSource.contains("setDocumentID(next)"), "web editor tags bridge messages with the current document identity")
expect(webEditorSource.contains("let lastSelectionReport = { text: null, rectKey: null }")
    && webEditorSource.contains("post('selectionChanged', { text: '', rect: null })")
    && webEditorSource.contains("lastSelectionRange = null")
    && webEditorSource.contains("if (isSelectionReportSuppressed()) return;")
    && webEditorSource.contains("if (text === lastSelectionReport.text && rectKey === lastSelectionReport.rectKey) return"), "web editor reports cleared selections once so floating selection UI and included-selection badges disappear")
expect(webEditorSource.contains("const palette = getCurrentTheme() === 'inkstone'")
    && webEditorSource.contains("background: '#151515', accent: '#a6362b', text: '#d7cbb0'")
    && webEditorSource.contains("background: '#efe6d8', accent: '#9f3b2f', text: '#6b5148'")
    && webEditorSource.contains("img[data-weibei-image-placeholder=\"true\"]")
    && webEditorSource.contains("image.setAttribute('src', missingImageURL());")
    && webEditorSource.contains("images.refreshMissingPlaceholders()"), "web missing-image placeholders follow the current theme and refresh after theme switches")
expect(webEditorSource.contains("const decorateCalloutHeadingSource = (decorations, node, pos) =>")
    && webEditorSource.contains("const firstParagraphText = (node) =>")
    && webEditorSource.contains("const calloutMatchForBlockquote = (node) =>")
    && webEditorSource.contains("const isBlockquoteType = (typeName) => typeName === 'blockquote' || typeName === 'block_quote'")
    && webEditorSource.contains("const calloutTypePattern = '[A-Za-z][A-Za-z0-9_-]*'")
    && webEditorSource.contains("const calloutPrefixPattern = '(?:\\\\s*>\\\\s*)*\\\\s*'")
    && webEditorSource.contains("const selectedTextCalloutControlRegex = new RegExp")
    && webEditorSource.contains("const cleanSelectedText = (text) =>")
    && webEditorSource.contains("const decorateLeakedCalloutControls = (decorations, text, pos) =>")
    && webEditorSource.contains("weibei-callout-custom")
    && webEditorSource.contains(#"^${calloutPrefixPattern}\\\\?\\[!"#)
    && webEditorSource.contains("const contentStart = pos + 1")
    && webEditorSource.contains("addRangeDecoration(decorations, contentStart, markerEnd, 'weibei-callout-marker')")
    && webEditorSource.contains("if (isBlockquoteType(typeName))")
    && webEditorSource.contains("const match = calloutMatchForBlockquote(node);")
    && webEditorSource.contains("typeName === 'paragraph' && isBlockquoteType(parentName)")
    && webEditorSource.contains("decorateCalloutHeadingSource(decorations, node, pos);")
    && webEditorSource.contains("return cleanSelectedText(content.textBetween")
    && webEditorSource.contains("const selectedText = () => cleanSelectedText")
    && webEditorSource.contains("if (insideBlockquote) decorateLeakedCalloutControls(decorations, text, textPos);")
    && !webEditorSource.contains("Array.from(calloutTypes).join('|')"), "callout heading decorations collapse the raw [!type] marker at paragraph range level so split inline nodes do not leak")
expect(webEditorSource.contains("const normalizeInterfaceLanguage")
    && webEditorSource.contains("let currentLanguage = normalizeInterfaceLanguage('zh-Hans')")
    && webEditorSource.contains("setInterfaceLanguage(window.weiBeiInterfaceLanguage)")
    && webEditorSource.contains("const calloutLabels = {")
    && webEditorSource.contains("en: {")
    && webEditorSource.contains("note: 'Note'")
    && webEditorSource.contains("'data-callout-title': (match[3] || calloutLabel(calloutType)).trim()")
    && webEditorSource.contains("setInterfaceLanguage: (next) =>"), "web editor callout fallback labels follow the current interface language")
expect(webEditorSource.contains(#"const htmlBreakPattern = /<br\s*\/?>/gi;"#)
    && webEditorSource.contains(#".replace(htmlBreakPattern, '\n')"#)
    && webEditorSource.contains("const isEscapedMarkdownPosition = (source, index) =>")
    && webEditorSource.contains("const findUnescapedMarkdownMarker = (source, marker, from) =>")
    && webEditorSource.contains("const mapMarkdownOutsideBackticks = (line, transform) =>")
    && webEditorSource.contains("const normalizeMarkdownOutputSegment = (text) =>")
    && webEditorSource.contains("const mapMarkdownOutsideCode = (markdown, transform) =>")
    && webEditorSource.contains("const normalizeMarkdownOutput = (markdown) => mapMarkdownOutsideCode(markdown, normalizeMarkdownOutputSegment)")
    && webEditorSource.contains("const normalizeHtmlBreaksInLine = (line) =>")
    && webEditorSource.contains("const normalizeHtmlBreaks = (markdown) =>")
    && webEditorSource.contains("const tick = findUnescapedMarkdownMarker(source, '`', cursor)")
    && webEditorSource.contains("const close = findUnescapedMarkdownMarker(source, marker, tick + marker.length)")
    && webEditorSource.contains(#"line.match(/^\s*(?:>\s*)*(`{3,}|~{3,})/)"#)
    && webEditorSource.contains("let inFence = false")
    && webEditorSource.contains("let fenceLength = 0")
    && webEditorSource.contains("if (inFence)")
    && webEditorSource.contains(#".replace(/<br\s*\/?>[ \t]*/gi, '  \n')"#)
    && webEditorSource.contains("const decorateHtmlBreaks = (decorations, text, pos) =>")
    && webEditorSource.contains("weibei-html-break-source")
    && webEditorSource.contains("if (hasCodeMark) return true;")
    && webEditorSource.contains("decorateHtmlBreaks(decorations, text, textPos)")
    && webEditorSource.contains("handleTextInput(view, from, to, text)")
    && webEditorSource.contains("view.state.schema.nodes.hardbreak || view.state.schema.nodes.hard_break")
    && webEditorSource.contains(#".replace(/!\[\[([^\]\n]+)\]\]/g, (_, raw) =>"#)
    && webEditorSource.contains(#".replace(/==([^=\n]+)==/g, '$1')"#)
    && webEditorSource.contains(#".replace(/%%[\s\S]*?%%\n?/g, '')"#), "web editor cleans common Markdown and Obsidian source markers from selected Agent context and renders HTML breaks softly")
let appSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/App/WeiBeiApp.swift")
let appSource = (try? String(contentsOf: appSourceURL, encoding: .utf8)) ?? ""
// Rebind full settings union (app entrypoint + Views/Settings/*) for later assertions.
agentSettingsSource = appSource + "\n" + settingsViewsSourceEarly
expect(appSource.contains("private var shouldActivateOnLaunch: Bool")
    && appSource.contains("WEIBEI_SUPPRESS_ACTIVATION")
    && appSource.contains("Task { await store.runVerificationScenarioIfNeeded() }")
    && appSource.contains("if shouldActivateOnLaunch {\n            NSApp.activate(ignoringOtherApps: true)\n        }"), "app activation is skipped during non-invasive verification launches")
expect(appSource.contains("applyVerificationWindowSize(to: window)")
    && appSource.contains("environment[\"WEIBEI_SUPPRESS_ACTIVATION\"] == \"1\"")
    && appSource.contains("environment[\"WEIBEI_VERIFY_WINDOW_SIZE\"]")
    && appSource.contains("window.setContentSize(target)")
    && appSource.contains("window.center()"), "verification-only window sizing supports real wide and narrow screenshots without changing normal launch behavior")
expect(appSource.contains("window.isOpaque = true"), "main window declares opaque paper backing for stable capture")
expect(appSource.contains("environment[\"WEIBEI_VERIFY_CAPTURE_PATH\"]")
    && appSource.contains("bitmapImageRepForCachingDisplay")
    && appSource.contains("cacheDisplay(in: bounds, to: bitmap)")
    && appSource.contains("visibleWebViews(in: contentView)")
    && appSource.contains("private static func visibleRect(")
    && appSource.contains(".intersection(contentView.bounds)")
    && appSource.contains("view.convert(view.bounds, to: contentView)")
    && appSource.contains("configuration.rect = rect")
    && appSource.contains("webView.takeSnapshot(with: configuration)")
    && appSource.contains("overlay.image.draw(in: overlay.rect, from: .zero, operation: .sourceOver, fraction: 1)")
    && !appSource.contains("operation: .copy"), "isolated verification capture preserves the opaque window underneath transparent WebView snapshots")
expect(appSource.contains("let scenario = environment[\"WEIBEI_VERIFY_SCENARIO\"] ?? \"\"")
    && appSource.contains("\"course-workspace-overview-flow\"")
    && appSource.contains("\"course-workspace-workflow-flow\""), "course workspace verification scenarios opt into completion-aware capture")
expect(appSource.contains("remainingAttempts: scenario == \"pane-toggle-continuity-flow\" ? 1_800 : 600")
    && appSource.contains("waitForVerificationCompletion")
    && appSource.contains("stages.split(separator: \"\\n\").contains(\"completed\")")
    && appSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 1.5)"), "isolated verification capture waits for an explicit completion marker and settled rendering")
expect(appSource.contains("sharedWorkspaceStore"), "main window and settings share one workspace store")
expect(!appSource.contains("launchProbe"), "app launch path has no temporary probe logging")
expect(appSource.contains("WeiBeiAppearanceTransition")
    && appSource.contains(".modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))")
    && !appSource.contains(".animation(WeiBeiMotion.appearance, value: mode)")
    // SettingsView migrated to its own file (Sources/WeiBei/Views/Settings/
    // SettingsView.swift), so the modifier now appears once in WeiBeiApp.swift
    // (the main window) and once in the settings views union. Count across the
    // union, not just appSource — see L1 in the settings diagnosis report.
    && agentSettingsSource.components(separatedBy: ".modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))").count >= 3
    && appSource.contains("private func animateAppearance(_ action: () -> Void)")
    && appSource.contains("animateAppearance {\n                        store.toggleAppearanceMode()")
    && workspaceStoreSource.contains("Transaction(animation: WeiBeiMotion.appearance)")
    // setAppearanceMode call now lives in SettingsView.swift (migrated out with
    // the settings UI). Scan the union — see L1.
    && agentSettingsSource.contains("store.setAppearanceMode(mode)")
    && appSource.contains("@State private var washColor = Color.clear")
    && appSource.contains("washColor = Color(nsColor: oldMode.windowBackground)")
    && appSource.contains("washOpacity = 0.16")
    && appSource.contains("crossFamily")
    && appSource.contains("transaction.disablesAnimations = true")
    && appSource.contains("withAnimation(WeiBeiMotion.appearance) {\n                    washOpacity = 0\n                }"), "appearance mode changes stage a wash only across light/dark families, not same-family swaps")
expect(appSource.contains("addLocalMonitorForEvents(matching: .keyDown)") && appSource.contains("removeMonitor(shortcutMonitor)"), "app-level shortcuts survive focused web editor")
expect(appSource.contains("var reopenMainWindow: (() -> Void)?")
    && appSource.contains("applicationShouldHandleReopen")
    && appSource.contains("if !flag")
    && appSource.contains("window.deminiaturize(nil)")
    && appSource.contains("window.makeKeyAndOrderFront(nil)")
    && appSource.contains("reopenMainWindow?()")
    && appSource.contains("MainWindowReopenBridge(appDelegate: appDelegate)")
    && appSource.contains("@Environment(\\.openWindow) private var openWindow")
    && appSource.contains("openWindow(id: \"main\")")
    && appSource.contains("return false")
    && !appSource.contains("return flag"), "reopen restores a hidden/minimized window or opens the main SwiftUI window instead of leaving a zero-window process")
expect(!agentSettingsSource.contains("Form {")
    // Settings IA (2026-07-26): 对话 | 界面 | 快捷键 | 关于.
    // Preferences only; one-shot actions live in command palette / workspace.
    // Theme only on Interface page as paper swatches. Default section is always .agent.
    && agentSettingsSource.contains("@State private var selectedSection: SettingsSection = .agent")
    && agentSettingsSource.contains("private enum SettingsSection: String, CaseIterable, Identifiable")
    && !agentSettingsSource.contains("case overview")
    && !agentSettingsSource.contains("case appearance")
    && !agentSettingsSource.contains("case reading")
    && !agentSettingsSource.contains("case writing")
    && !agentSettingsSource.contains("case data")
    && agentSettingsSource.contains("case agent")
    && agentSettingsSource.contains("case interface")
    && agentSettingsSource.contains("case shortcuts")
    && agentSettingsSource.contains("case about")
    && agentSettingsSource.contains("aboutSettings")
    && agentSettingsSource.contains("interfaceSettings")
    && agentSettingsSource.contains("WeiBeiUpdateChecker.check")
    && agentSettingsSource.contains("runUpdateCheck")
    && agentSettingsSource.contains("settingsSidebar")
    && agentSettingsSource.contains("settingsDetail")
    && !agentSettingsSource.contains("overviewSettings")
    && !agentSettingsSource.contains("appearanceSettings")
    && !agentSettingsSource.contains("readingSettings")
    && !agentSettingsSource.contains("writingSettings")
    && !agentSettingsSource.contains("dataSettings")
    && agentSettingsSource.contains("agentSettings")
    && agentSettingsSource.contains("Text(store.ui(\"设置\", \"Settings\"))")
    && !agentSettingsSource.contains("Text(\"SETTINGS\")")
    && !agentSettingsSource.contains("case .overview: return \"HOME\"")
    && !agentSettingsSource.contains("case .appearance: return \"LOOK\"")
    && !agentSettingsSource.contains("case .agent: return \"CHAT\"")
    && !agentSettingsSource.contains("var code: String")
    && agentSettingsSource.contains("case .agent: return store.ui(\"对话\", \"Chat\")")
    && agentSettingsSource.contains("case .interface: return store.ui(\"界面\", \"Interface\")")
    && agentSettingsSource.contains(".frame(minWidth: 860, minHeight: 610)")
    && !agentSettingsSource.contains(".frame(width: 860, height: 610)")
    && agentSettingsSource.contains("settingsGroup(store.ui(\"对话服务\", \"Chat Service\")")
    && agentSettingsSource.contains("ForEach(AgentProviderID.subscriptionProviders)")
    && agentSettingsSource.contains("ForEach(AgentProviderID.apiKeyProviders)")
    && agentSettingsSource.contains("ForEach(AgentProviderID.localOrCustomProviders)")
    && agentSettingsSource.contains("store.setAgentProviderID(provider)")
    && agentSettingsSource.contains("store.updateAgentBaseURL")
    && agentSettingsSource.contains("openAgentProviderConsole")
    && agentSettingsSource.contains("AgentProviderID.subscriptionProviders")
    && agentSettingsSource.contains("agentModelPicker()")
    && !agentSettingsSource.contains("settingsGroup(store.ui(\"对话形态\", \"Chat Surface\")")
    && !agentSettingsSource.contains("页边洞察")
    && !agentSettingsSource.contains("Agent 上下文")
    && !agentSettingsSource.contains("Agent 与 API")
    && !agentSettingsSource.contains("title: store.ui(\"对话与 API\"")
    && !agentSettingsSource.contains("settingsGroup(store.ui(\"API\"")
    && !agentSettingsSource.contains("把 Agent 作为")
    && agentSettingsSource.contains("prompt: Text(store.ui(\"粘贴 API Key\"")
    && !agentSettingsSource.contains("Button(store.ui(\"保存到当前配置\"")
    && !agentSettingsSource.contains("Button(store.ui(\"保存\", \"Save\")")
    && agentSettingsSource.contains("onChange(of: store.openAIAPIKey)")
    && agentSettingsSource.contains("AgentAuthMethod")
    && agentSettingsSource.contains("createAgentCredentialProfile")
    && agentSettingsSource.contains("openAgentProviderConsole")
    && !agentSettingsSource.contains("prompt: Text(\"OpenAI 密钥\")")
    && agentSettingsSource.contains("store.saveOpenAIAPIKey()")
    && agentSettingsSource.contains(".onSubmit { store.saveOpenAIAPIKey() }")
    && agentSettingsSource.contains("SecureField(")
    && agentSettingsSource.contains(".foregroundStyle(WeiBeiTheme.placeholderInk)")
    && agentSettingsSource.contains(".foregroundColor(WeiBeiTheme.ink)")
    && agentSettingsSource.contains(".weibeiInputSurface(active: focusedField == .apiKey, height: 38)")
    // Theme: Interface page layout-preview cards only — no header palette, no sidebar jump pills.
    && agentSettingsSource.contains("private var themePicker")
    && agentSettingsSource.contains("WeiBeiAppearanceMode.allCases")
    && agentSettingsSource.contains("WeiBeiThemeLayoutPreview(mode:")
    && !agentSettingsSource.contains("settingsAppearanceToggleButton")
    && !agentSettingsSource.contains("AppearanceThemePaletteButton()")
    // One-shot actions must not reappear in Views/Settings/* (menus/workspace may still call them).
    && !settingsViewsSourceEarly.contains("importFilesFromPanel")
    && !settingsViewsSourceEarly.contains("promptCreateBlankNotebookNote")
    && !settingsViewsSourceEarly.contains("revealReaderSearch")
    && !settingsViewsSourceEarly.contains("clearSelectionAttachments")
    && !agentSettingsSource.contains("Image(systemName: store.appearanceMode.systemImage)")
    && !agentSettingsSource.contains("WeiBeiIconButtonStyle(active: store.appearanceMode == .inkstone")
    && !agentSettingsSource.contains("TopBarVariant")
    && !agentSettingsSource.contains("setTopBarVariant")
    && !agentSettingsSource.contains("顶部栏样式"), "settings center uses 4 sections (Chat/Interface/Shortcuts/About), durable prefs only, theme name segments on Interface")
// Model list is discovered live per-provider (OpenAI-compatible / Anthropic / Gemini /
// Azure / Bedrock / GitHub Models / OpenRouter), with a built-in fallback for providers
// whose listing is unavailable or untrustworthy (e.g. Codex subscription).
func readSource(_ relativePath: String) -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}
let workspaceStoreSource = readSource("Sources/WeiBei/Stores/WorkspaceStore.swift")
let modelListServiceSource = readSource("Sources/WeiBeiCore/AgentModelListService.swift")
let workspaceModelsSource = readSource("Sources/WeiBeiCore/WorkspaceModels.swift")
expect(modelListServiceSource.contains("enum ModelListStrategy")
    && modelListServiceSource.contains("case openAICompatible")
    && modelListServiceSource.contains("case anthropic")
    && modelListServiceSource.contains("case gemini")
    && modelListServiceSource.contains("case azureOpenAI")
    && modelListServiceSource.contains("case bedrock")
    && modelListServiceSource.contains("case gitHubModels")
    && modelListServiceSource.contains("case openRouterPublic")
    && modelListServiceSource.contains("case codexSubscription(token: String, accountID: String)")
    && modelListServiceSource.contains("chatgpt.com/backend-api/codex/models")
    && modelListServiceSource.contains("ChatGPT-Account-ID")
    && modelListServiceSource.contains("func fetchModels(strategy:")
    && modelListServiceSource.contains("x-api-key")
    && modelListServiceSource.contains("anthropic-version")
    && modelListServiceSource.contains("foundation-models")
    && workspaceModelsSource.contains("var modelListProtocol: ModelListProtocol")
    && workspaceModelsSource.contains("var recommendedModels: [String]")
    && workspaceModelsSource.contains("var defaultListBaseURL: String?")
    && workspaceStoreSource.contains("var availableModels: [String]")
    && workspaceStoreSource.contains("var modelListStatus: ModelListStatus")
    && workspaceStoreSource.contains("func resolvedModelListStrategy()")
    && workspaceStoreSource.contains("func refreshModelList()")
    && workspaceStoreSource.contains("AgentModelListService.shared.fetchModels")
    && agentSettingsSource.contains("agentModelPicker()")
    && agentSettingsSource.contains("requestModelListRefresh()"), "chat service enumerates models live per provider with a built-in fallback and surfaces them in a dropdown")
// Regression: refreshModelList must not cancel modelFetchTask at entry. The scheduler
// stores the Task that awaits refreshModelList; cancelling there self-cancels the
// in-flight fetch, discards a successful Codex catalog, and leaves status .loading.
// Exactly one cancel site remains, inside scheduleModelListRefresh.
expect(workspaceStoreSource.contains("func scheduleModelListRefresh()")
    && workspaceStoreSource.components(separatedBy: "modelFetchTask?.cancel()").count == 2
    && workspaceStoreSource.contains("must NOT cancel `modelFetchTask`")
    && !workspaceStoreSource.contains("func refreshModelList() async {\n        modelFetchTask?.cancel()"),
    "model-list race guard cancels only from scheduleModelListRefresh, never self-cancels refreshModelList")
// L5: provider console links + key-help live in one metadata table (behavior locked).
let credentialProfilesSource = readSource("Sources/WeiBeiCore/AgentCredentialProfiles.swift")
expect(credentialProfilesSource.contains("public struct Metadata: Sendable, Equatable")
    && credentialProfilesSource.contains("public enum KeyHelp: Sendable, Equatable")
    && credentialProfilesSource.contains("public static func metadata(for provider: AgentProviderID) -> Metadata")
    && credentialProfilesSource.contains("public static func loginURL(for provider: AgentProviderID) -> URL?")
    && credentialProfilesSource.contains("public static func accountURL(for provider: AgentProviderID) -> URL?")
    && credentialProfilesSource.contains("public static func keyHelp(language: WeiBeiInterfaceLanguage, provider: AgentProviderID) -> String"),
    "provider console metadata is table-driven behind the existing AgentProviderConsoleLinks API")
// Runtime golden values — keep the pre-L5 URLs/help strings from drifting.
for provider in AgentProviderID.allCases {
    _ = AgentProviderConsoleLinks.loginURL(for: provider)
    _ = AgentProviderConsoleLinks.accountURL(for: provider)
    _ = AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: provider)
    _ = AgentProviderConsoleLinks.keyHelp(language: .english, provider: provider)
    _ = AgentProviderConsoleLinks.metadata(for: provider)
}
expect(AgentProviderConsoleLinks.loginURL(for: .openai)?.absoluteString == "https://platform.openai.com/api-keys"
    && AgentProviderConsoleLinks.accountURL(for: .openai)?.absoluteString == "https://platform.openai.com/"
    && AgentProviderConsoleLinks.loginURL(for: .openaiCodex)?.absoluteString == "https://platform.openai.com/api-keys"
    && AgentProviderConsoleLinks.accountURL(for: .openaiCodex)?.absoluteString == "https://chatgpt.com/"
    && AgentProviderConsoleLinks.loginURL(for: .anthropic)?.absoluteString == "https://console.anthropic.com/settings/keys"
    && AgentProviderConsoleLinks.accountURL(for: .anthropic)?.absoluteString == "https://claude.ai/"
    && AgentProviderConsoleLinks.loginURL(for: .githubCopilot)?.absoluteString == "https://github.com/settings/copilot"
    && AgentProviderConsoleLinks.accountURL(for: .githubCopilot)?.absoluteString == "https://github.com/login"
    && AgentProviderConsoleLinks.loginURL(for: .xai)?.absoluteString == "https://console.x.ai/"
    && AgentProviderConsoleLinks.accountURL(for: .xai)?.absoluteString == "https://x.ai/"
    && AgentProviderConsoleLinks.loginURL(for: .deepseek)?.absoluteString == "https://platform.deepseek.com/api_keys"
    && AgentProviderConsoleLinks.loginURL(for: .openrouter)?.absoluteString == "https://openrouter.ai/keys"
    && AgentProviderConsoleLinks.loginURL(for: .custom) == nil
    && AgentProviderConsoleLinks.loginURL(for: .llamaCpp) == nil
    && AgentProviderConsoleLinks.loginURL(for: .xiaomi) == nil
    && AgentProviderConsoleLinks.accountURL(for: .deepseek)?.absoluteString == "https://platform.deepseek.com/api_keys",
    "provider console login/account URLs match the pre-L5 golden set")
expect(AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .openaiCodex).contains("订阅 OAuth")
    && AgentProviderConsoleLinks.keyHelp(language: .english, provider: .openaiCodex).contains("Subscription OAuth")
    && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .anthropic).contains("ANTHROPIC_API_KEY")
    && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .azureOpenAI).contains("AZURE_OPENAI_BASE_URL")
    && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .amazonBedrock).contains("AWS_BEARER_TOKEN_BEDROCK")
    && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .custom).contains("OpenAI 兼容")
    && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .llamaCpp).contains("llama.cpp")
    && AgentProviderConsoleLinks.keyHelp(language: .chinese, provider: .openai).contains("OPENAI_API_KEY")
    && AgentProviderConsoleLinks.metadata(for: .openai).help == .genericEnv
    && AgentProviderConsoleLinks.metadata(for: .openaiCodex).help == .openaiCodex
    && AgentProviderConsoleLinks.metadata(for: .cloudflareAIGateway).help == .cloudflareAIGateway
    && AgentProviderConsoleLinks.metadata(for: .cloudflareWorkersAI).help == .cloudflareWorkersAI,
    "provider key-help copy matches the pre-L5 golden set for special and generic cases")
expect(agentSettingsSource.contains(".contentShape(Rectangle())")
    && agentSettingsSource.contains("func settingsSwitch(isOn: Binding<Bool>, accessibilityLabel: String)")
    // Sidebar is a pure section list — no language/theme jump pills at the bottom.
    && !agentSettingsSource.contains("icon: \"character.book.closed\"")
    && !agentSettingsSource.contains("前往外观设置")
    && !agentSettingsSource.contains("管理魏碑的界面、写作、对话和本地资料")
    && !agentSettingsSource.contains("private var sectionSubtitle")
    && !agentSettingsSource.contains("布局说明")
    && !agentSettingsSource.contains("当前阅读位置")
    && !agentSettingsSource.contains("选区入口")
    && !agentSettingsSource.contains("编辑器主题")
    && !agentSettingsSource.contains("title: store.ui(\"当前资料\""), "settings sidebar is a pure section list; rows are decluttered; hit area is full-width")
expect(agentSettingsSource.contains("title: store.ui(\"每日灵感\", \"Daily Inspiration\")")
    && agentSettingsSource.contains("get: { store.showDailyInspiration }")
    && agentSettingsSource.contains("set: { store.setDailyInspirationEnabled($0) }")
    && agentSettingsSource.contains("settingsSwitch(")
    && agentSettingsSource.contains("accessibilityLabel: store.ui(\"显示每日灵感\", \"Show Daily Inspiration\")")
    && agentSettingsSource.contains(".tint(WeiBeiTheme.cinnabar)")
    && agentSettingsSource.contains("interfaceSettings"), "settings toggles daily inspiration on Interface with a cinnabar switch (no filler detail copy)")
expect(!agentSettingsSource.contains("title: store.ui(\"笔记模式\", \"Note Mode\")")
    && !agentSettingsSource.contains("segmented(NoteRenderMode.visibleCases")
    && agentSettingsSource.contains("title: store.ui(\"文稿随主题调色\", \"Match documents to theme\")")
    && agentSettingsSource.contains("title: store.ui(\"语言\", \"Language\")")
    && agentSettingsSource.contains("compactMenu(store.interfaceLanguage.nativeName)")
    && agentSettingsSource.contains("private var themePicker")
    && agentSettingsSource.contains("WeiBeiThemeLayoutPreview(mode:")
    && agentSettingsSource.contains("showFeedbackSheet")
    && agentSettingsSource.contains("submitFeedback")
    && agentSettingsSource.contains("openPrefilledGitHubIssue")
    && agentSettingsSource.contains("github.com/weibei-app/weibei/issues/new")
    && agentSettingsSource.contains("beginShortcutRecording")
    && agentSettingsSource.contains("AppShortcutID")
    && !agentSettingsSource.contains("lock.shield")
    && !agentSettingsSource.contains("copyUserFacingVersionInfo")
    && !agentSettingsSource.contains("笔记预览")
    && !agentSettingsSource.contains("Note Preview")
    && !agentSettingsSource.contains("setNoteRenderMode(.preview)")
    && !commandPaletteSource.contains("笔记预览")
    && !commandPaletteSource.contains("Note Preview")
    && !commandPaletteSource.contains("setNoteRenderMode(.preview)"), "settings: language menu, AionUI-style theme layout cards, editable shortcuts, in-app feedback")
let interactiveInputSources = [contentViewSource, sidebarSource, commandPaletteSource, notesAgentSource, appSource].joined(separator: "\n")
expect(!interactiveInputSources.contains(".weibeiInputPrompt("), "interactive input placeholders stay on native prompts instead of overlay text")
expect(agentSettingsSource.contains("WeiBeiTextActionButtonStyle(active: true)") && agentSettingsSource.contains(".background(WeiBeiTheme.paper)") && agentSettingsSource.contains("WeiBeiGlassHeaderBackground(paperOpacity: 0.66"), "settings view uses WeiBei paper, glass header, and button styles")
expect(appSource.contains("init() {")
    && appSource.contains("WeiBeiTypography.registerBundledFonts()"), "app registers bundled WeiBei fonts before the SwiftUI window tree is built")
expect(workspaceStoreSource.components(separatedBy: "recordVerificationStage(\"completed\")").count >= 4, "verification scenarios record completion before capture")
let linkedSourcesSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/LinkedSourcesView.swift")
let linkedSourcesSource = (try? String(contentsOf: linkedSourcesSourceURL, encoding: .utf8)) ?? ""
let courseWorkspaceSourceNames = [
    "CourseWorkspaceView.swift",
    "CourseHubView.swift",
    "CourseRelationsView.swift",
    "CourseRelationPaperView.swift",
    "CourseRelationGraphModel.swift",
    "CourseImmersiveDrawerView.swift",
    "CourseRecordsView.swift",
    "CourseWorkspaceComponents.swift",
]
let courseWorkspaceSource = courseWorkspaceSourceNames.map { name in
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Sources/WeiBei/Views")
        .appendingPathComponent(name)
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}.joined(separator: "\n")
let selectItemSource: String = {
    guard let start = workspaceStoreSource.range(of: "func select(itemID: String?)")?.lowerBound,
          let end = workspaceStoreSource[start...].range(of: "func selectAdjacentItem")?.lowerBound else {
        return ""
    }
    return String(workspaceStoreSource[start..<end])
}()
expect(!selectItemSource.contains("activeNotebookItemID = nil")
    && selectItemSource.contains("selectedItemID = itemID"), "opening another material does not detach the note the user is writing")
expect(workspaceStoreSource.contains("noteSourceLinksMigrationVersion < 1")
    && workspaceStoreSource.contains("noteSourceLinksMigrationVersion = 1")
    && workspaceStoreSource.contains("setLinkedSourceIDsForActiveNote"), "note-source migration runs once and explicit relationship management remains available")
expect(workspaceStoreSource.contains("invalidateAgentContext()\n            activeNotebookItemID = item.id")
    && workspaceStoreSource.components(separatedBy: "removeLinksWhereSourceItemID").count >= 3, "switching notes invalidates in-flight agent work and source-to-note conversion removes invalid relationships")
expect(linkedSourcesSource.contains("@State private var noteItemID: String?")
    && linkedSourcesSource.contains("noteItemID = store.activeNotebookItemID")
    && linkedSourcesSource.contains("store.setLinkedSourceIDs(draftIDs, for: noteItemID)"), "relationship editing remains bound to the note that opened the popover")
expect(contentViewSource.contains("if store.courseWorkspacePresented")
    && contentViewSource.contains("CourseWorkspaceView()")
    && contentViewSource.contains("LayoutContentView()")
    && contentViewSource.contains("container.isHidden = store.courseWorkspacePresented")
    && !contentViewSource.contains("if store.courseWorkspacePresented {\n                            CourseWorkspaceView()\n                        } else"), "course workspace covers and hides native pane hosts without replacing the persistent pane tree")
expect(courseWorkspaceSource.contains("case hub")
    && courseWorkspaceSource.contains("case relations")
    && courseWorkspaceSource.contains("case records")
    && !courseWorkspaceSource.contains("case overview")
    && courseWorkspaceSource.contains("CourseHubView(")
    && courseWorkspaceSource.contains("对话记录")
    && courseWorkspaceSource.contains("管理关系")
    && courseWorkspaceSource.contains("导入文稿")
    && courseWorkspaceSource.contains("导入笔记")
    && courseWorkspaceSource.contains("CourseHubRowProminence")
    && courseWorkspaceSource.contains("选择一门课程")
    && courseWorkspaceSource.contains("选择课程")
    && courseWorkspaceSource.contains("关系台")
    && courseWorkspaceSource.contains("资料与笔记")
    && courseWorkspaceSource.contains("资料关系台")
    && courseWorkspaceSource.contains("同色标签表示同一课程")
    && courseWorkspaceSource.contains("primaryCourseID(for:")
    && courseWorkspaceSource.contains("CourseHubColumnEmptyState")
    && courseWorkspaceSource.contains("courseTitleDisplayFont")
    && courseWorkspaceSource.contains("frame(height: 44, alignment: .center)")
    && courseWorkspaceSource.contains("继续阅读")
    && courseWorkspaceSource.contains("继续对话")
    && courseWorkspaceSource.contains("CourseHubContinueRow")
    && courseWorkspaceSource.contains("linkedSessionIDs"), "course workspace hub is a continue-learning launcher with course picking and material-linked conversation prominence")
expect(courseWorkspaceSource.contains("CourseRelationPaperView(")
    && courseWorkspaceSource.contains("CourseImmersiveDrawerView")
    && (courseWorkspaceSource.contains("static let width: CGFloat = 292")
        || courseWorkspaceSource.contains(".frame(width: 292)")
        || courseWorkspaceSource.contains("CourseDrawerContainerView.panelWidth"))
    && courseWorkspaceSource.contains("未归属课程")
    && courseWorkspaceSource.contains("未建立关系")
    && courseWorkspaceSource.contains("showsOnlyUnlinked")
    && courseWorkspaceSource.contains("edgeHazeColor")
    && courseWorkspaceSource.contains("nodeProminence")
    && courseWorkspaceSource.contains("private struct CourseRelationPaperNodeView: View"), "course drawer and relation paper share explicit course membership while keeping course assignment separate from note-material links")
expect(courseWorkspaceSource.contains("@State private var pendingConnection")
    && courseWorkspaceSource.contains("private func handleConnectionTap")
    && courseWorkspaceSource.contains("private func connectionButton")
    && courseWorkspaceSource.contains("MagnificationGesture()")
    && courseWorkspaceSource.contains("private func zoomControls")
    && courseWorkspaceSource.contains("private func fitZoomScale")
    && courseWorkspaceSource.contains("scrollProxy.scrollTo(Self.paperOriginID, anchor: .topLeading)")
    && courseWorkspaceSource.contains("private struct CourseRelationNodeDragModifier")
    && courseWorkspaceSource.contains(".accessibilityLabel(\"\\(node.item.title)：\\(connectionLabel(state))\")")
    && courseWorkspaceSource.contains("private static func fanOffsets")
    && courseWorkspaceSource.contains("courseScopeRail")
    && courseWorkspaceSource.contains("private var defaultScope")
    && courseWorkspaceSource.contains("let candidate = scope ?? defaultScope")
    && courseWorkspaceSource.contains("Thin toolbar only")
    && courseWorkspaceSource.contains("frame(height: 40)"), "relationship paper scopes by course on a left rail, defaults to the active course, uses a thin toolbar, supports click-to-link and zoom, and fans dense bands at shared nodes")
expect(courseWorkspaceSource.contains("更改自动保存")
    && courseWorkspaceSource.contains("private func addLink(materialID: String, noteID: String)")
    && courseWorkspaceSource.contains("private func removeLink(noteID: String, materialID: String)")
    && courseWorkspaceSource.contains("store.setLinkedNoteIDs")
    && courseWorkspaceSource.contains("store.setLinkedCourseSourceIDs")
    && !courseWorkspaceSource.contains("store.courseMaterials + store.sampleItems"), "course relationship edits save immediately in both directions while built-in samples stay outside course counts")
expect(workspaceStoreSource.contains("@Published private(set) var workspaceSaveError")
    && workspaceStoreSource.contains("func retryWorkspaceSave()")
    && workspaceStoreSource.contains("Course changes were not saved to disk")
    && courseWorkspaceSource.contains("保存失败，点此重试")
    && courseWorkspaceSource.contains("draft.automaticMaterialCount + draft.markdownFiles.count - notePaths.count")
    && courseWorkspaceSource.contains("url.deletingLastPathComponent().path"), "course autosave failures stay visible and mixed-folder classification reports complete counts with unambiguous paths")
expect(workspaceStoreSource.contains("func presentCourseWorkspace(")
    && workspaceStoreSource.contains("CourseWorkspaceDestination = .hub")
    && workspaceStoreSource.contains("func openCourseSpace(_ courseID: UUID)")
    && workspaceStoreSource.contains("func sessionsTouchingCourse(_ courseID: UUID)")
    && workspaceStoreSource.contains("func sessionsTouchingMaterial(_ materialID: String")
    && workspaceStoreSource.contains("func primaryCourseID(for session: StudySession)")
    && workspaceStoreSource.contains("func importCourseFilesFromURLs(_ urls: [URL]")
    && workspaceStoreSource.contains("func dismissCourseWorkspace()")
    && workspaceStoreSource.contains("func openCourseMaterial(")
    && workspaceStoreSource.contains("func openCourseNote(")
    && workspaceStoreSource.contains("func continueCourseSession(")
    && workspaceStoreSource.contains("func prepareCourseFolderImportFromPanel()")
    && workspaceStoreSource.contains("func importCourseMaterialsFromPanel()")
    && workspaceStoreSource.contains("func importCourseNotesFromPanel()")
    && workspaceStoreSource.contains("markdownNotePaths: Set<String>? = nil")
    && workspaceStoreSource.contains("reclassifiesExistingMarkdown: true")
    && workspaceStoreSource.contains("defaultMarkdownIsNotebookNote")
    && workspaceStoreSource.contains("func createCourseNotebookNote(title: String) -> String?")
    && courseWorkspaceSource.contains("确认 Markdown 的角色")
    && courseWorkspaceSource.contains("guard let noteID = store.createCourseNotebookNote")
    && courseWorkspaceSource.contains("newNoteError = store.noteFileError")
    && courseWorkspaceSource.contains("store.sessionsTouchingCourse(courseID)")
    && courseWorkspaceSource.contains("importCourseFilesFromURLs")
    && appSource.contains("打开课程空间")
    && commandPaletteSource.contains("打开课程空间")
    && sidebarSource.contains("store.presentCourseWorkspace(.hub)")
    && linkedSourcesSource.contains("store.presentCourseWorkspace(.notes"), "course hub routing, session membership helpers, and top-level open actions stay wired without replacing note-relationship entry points")
expect(workspaceStoreSource.contains("scenario == \"course-index-navigation-flow\"")
    && workspaceStoreSource.contains("course-material-unassigned")
    && workspaceStoreSource.contains("activeCourseID = nil")
    && workspaceStoreSource.contains("showLibrary = true")
    && workspaceStoreSource.contains("CourseItemMemberships()"), "course-drawer verification uses isolated real courses, shared items, and one genuinely unassigned material")
expect(workspaceStoreSource.contains("noteSourceRelationIndex = NoteSourceRelationIndex(links: noteSourceLinks)")
    && workspaceStoreSource.contains("func linkedNoteCount(for sourceItemID: String)")
    && workspaceStoreSource.contains("verifyCourseOverlayContinuity(itemID:")
    && workspaceStoreSource.contains("verifyCourseOverlayContinuity(itemID: \"sample-pdf\")")
    && workspaceStoreSource.contains("PaneToggleContinuityVerifier.endMeasurement()"), "course relationships use a reusable index and overlay continuity measures live HTML and PDF panes")
expect(readerViewSource.contains("var isEnabled = true")
    && readerViewSource.contains("NSApp.modalWindow == nil")
    && courseWorkspaceSource.contains("isEnabled: !showsNewNotePrompt && store.courseFolderImportDraft == nil"), "escape dismisses only the active course surface and leaves sheets or file panels in control")
expect(workspaceStoreSource.contains("DocumentTextExtractor.cachedText(for: item)")
    && workspaceStoreSource.contains("Task.detached(priority: .userInitiated)")
    && workspaceStoreSource.contains("DocumentTextExtractor.indexText(for: candidate.item, query: query)")
    && workspaceStoreSource.contains("DocumentTextExtractor.text(for: item)")
    && workspaceStoreSource.contains("candidate.item.id == currentMaterialID")
    && !workspaceStoreSource.contains("if let text = DocumentTextExtractor.text(for: item)"), "main-actor workspace reads cached document text; cold current-material extract runs inside the detached course-context task")
expect(workspaceStoreSource.contains("@Published var showDailyInspiration = true")
    && workspaceStoreSource.contains("func setDailyInspirationEnabled(_ enabled: Bool)")
    && workspaceStoreSource.contains("showDailyInspiration = snapshot.showDailyInspiration ?? true")
    && workspaceStoreSource.contains("showDailyInspiration: showDailyInspiration"), "daily inspiration preference persists in the isolated workspace file and older workspaces default to enabled")
expect(workspaceStoreSource.contains("var brandLatinName: String")
    && workspaceStoreSource.contains("\"WeiBei\"")
    && !contentViewSource.contains("Text(store.brandLatinName)")
    && !contentViewSource.contains("WeiBeiTypography.englishBrandFont(size: 15.5, weight: .semibold)")
    && !contentViewSource.contains("WeiBeiBrandMark.image(for: store.appearanceMode)")
    // Settings sidebar keeps a single localized title only — no second "WeiBei SETTINGS" line.
    && !agentSettingsSource.contains("Text(\"SETTINGS\")")
    && notesAgentSource.contains("latinMark: store.interfaceLanguage == .chinese ? \"NOTES\" : nil")
    && notesAgentSource.contains("latinMark: store.interfaceLanguage == .chinese ? \"CHAT\" : nil"), "top bar stays brandless; pane headers keep CHAT/NOTES marks; settings title is not duplicated")
expect(notesAgentSource.contains("ForEach(NoteRenderMode.visibleCases)")
    && notesAgentSource.contains("switch store.noteRenderMode.visibleMode")
    && !notesAgentSource.contains("ForEach(NoteRenderMode.allCases)")
    && notesAgentSource.contains("let label = mode.label(language: store.interfaceLanguage)")
    && notesAgentSource.contains("Text(label)")
    && !notesAgentSource.contains("return \"Diff\"")
    && !notesAgentSource.contains("return \"Src\"")
    && !notesAgentSource.contains("private func compactModeLabel")
    && !notesAgentSource.contains("Text(\"预览\")")
    && !notesAgentSource.contains("Text(\"Preview\")")
    && notesAgentSource.contains(".accessibilityLabel(Text(label))")
    && notesAgentSource.contains(".help(label)"), "note pane header exposes only writing, compare, and source with clear shared labels and full accessibility/help text")
expect(
    workspaceStoreSource.contains("shortcutKey(from event: NSEvent)")
        && workspaceStoreSource.contains("case 0: return \"a\"")
        && workspaceStoreSource.contains("case 18: return \"1\"")
        && workspaceStoreSource.contains("case 30: return \"]\"")
        && workspaceStoreSource.contains("case 33: return \"[\"")
        && workspaceStoreSource.contains("case 125: return \"down\""),
    "app shortcuts normalize hardware keys"
)
expect(workspaceStoreSource.contains("animateLayoutChange") && workspaceStoreSource.contains("withAnimation(WeiBeiMotion.layout)"), "app shortcut layout changes stay animated")
expect(workspaceStoreSource.contains("animatePanelChange") && workspaceStoreSource.contains("withAnimation(WeiBeiMotion.panel)"), "app shortcut panel changes stay animated")
expect(workspaceStoreSource.contains("if modifiers == [.command, .shift]") && workspaceStoreSource.contains("applyLastAgentAnswerToNote()") && workspaceStoreSource.contains("replaceSelectionWithLastAgentAnswer()") && workspaceStoreSource.contains("applyAgentPatchToEditor()"), "app shortcut handler owns command-shift agent write actions")
expect(workspaceStoreSource.contains("case \"a\":\n                guard canApplyAgentAnswer else { return false }\n                animatePanelChange { applyLastAgentAnswerToNote() }")
    && workspaceStoreSource.contains("case \"r\":\n                guard canReplaceNoteSelection else { return false }\n                animatePanelChange { replaceSelectionWithLastAgentAnswer() }")
    && workspaceStoreSource.contains("case \"e\":\n                guard canApplyAgentAnswer else { return false }\n                animatePanelChange { applyAgentPatchToEditor() }"), "agent write shortcuts do not swallow unavailable actions")
expect(workspaceStoreSource.contains("case \"j\":\n                guard layout.hasCollapsibleRightPane else { return false }\n                animateLayoutChange { toggleRightPane() }"), "right-pane shortcut does not swallow unavailable layouts")
expect(workspaceStoreSource.contains("case \"2\":\n                animateLayoutChange { setLayout(.documentNotesSplit) }")
    && !workspaceStoreSource.contains("case \"3\":\n                animateLayoutChange { setLayout(.documentNotesSplit) }")
    && workspaceStoreSource.contains("case \"s\":\n                guard layout.isDocumentThreePane else { return false }\n                animateLayoutChange { swapThreePaneSecondaryPanes() }"), "three-pane keyboard shortcuts match the command palette and only swap panes inside the three-pane workspace")
expect(workspaceStoreSource.contains("case .navigateBack:")
    && workspaceStoreSource.contains("guard canNavigateBack else { return false }")
    && workspaceStoreSource.contains("animateLayoutChange { navigateBackInWorkspace() }")
    && workspaceStoreSource.contains("case .navigateForward:")
    && workspaceStoreSource.contains("guard canNavigateForward else { return false }")
    && workspaceStoreSource.contains("animateLayoutChange { navigateForwardInWorkspace() }")
    && workspaceStoreSource.contains("AppShortcutCatalog.action(matching:")
    && workspaceStoreSource.contains("performCustomizableShortcut"), "command-bracket shortcuts drive workspace back and forward via the customizable shortcut catalog")
expect(workspaceStoreSource.contains("var canCopyReference: Bool")
    && workspaceStoreSource.contains("var copyReferenceActionTitle: String")
    && workspaceStoreSource.contains("hasSelectionAttachments || selectionContext != nil")
    && workspaceStoreSource.contains("if hasSelectionAttachments || selectionContext != nil { return ui(\"复制选区引用\"")
    && workspaceStoreSource.contains("if hasSelectedMaterial { return ui(\"复制资料引用\"")
    && workspaceStoreSource.contains("guard canCopyReference else { return false }")
    && workspaceStoreSource.contains("guard hasSelectedMaterial else { return false }"), "app shortcuts and menus name copy-reference by the actual current target")
expect(workspaceStoreSource.contains("selectAdjacentItem(step: -1)")
    && workspaceStoreSource.contains("if isAskingAgent {\n                    cancelAgentRequest()")
    && workspaceStoreSource.contains("guard !agentDraft.trimmingCharacters")
    && workspaceStoreSource.contains("askAgent()"), "app shortcut handler covers navigation plus agent send and stop")
expect(workspaceStoreSource.contains("return allItems.filter { itemMatchesLibrarySearch($0, query: query) }")
    && workspaceStoreSource.contains("return materialItems.filter { itemMatchesLibrarySearch($0, query: query) }")
    && workspaceStoreSource.contains("func displayTags(for item: StudyItem, limit: Int = 3) -> [String]")
    && workspaceStoreSource.contains("return Array(MarkdownTagSearch.tags(in: noteMarkdownText(for: item)).prefix(limit))")
    && workspaceStoreSource.contains("private func noteTagsMatchLibrarySearch(_ item: StudyItem, query: String) -> Bool")
    && workspaceStoreSource.contains("private func noteMarkdownText(for item: StudyItem) -> String")
    && workspaceStoreSource.contains("MarkdownTagSearch.matches(query: query, in: noteMarkdownText(for: item))")
    && workspaceStoreSource.contains("item.id == activeNoteItemID"), "course index search includes active and cached notebook Markdown tags without indexing all notes separately")
expect(workspaceStoreSource.contains("backNavigationStack: [NavigationSnapshot]")
    && workspaceStoreSource.contains("forwardNavigationStack: [NavigationSnapshot]")
    && workspaceStoreSource.contains("func navigateBackInWorkspace()")
    && workspaceStoreSource.contains("func navigateForwardInWorkspace()")
    && workspaceStoreSource.contains("private func recordNavigationPoint()")
    && workspaceStoreSource.contains("private func applyNavigationSnapshot")
    && workspaceStoreSource.contains("forwardNavigationStack.append(navigationSnapshot())")
    && workspaceStoreSource.contains("backNavigationStack.append(navigationSnapshot())")
    && workspaceStoreSource.contains("agentSurface == .selectionFloat ? .hidden : agentSurface"), "workspace back/forward stores app page state without restoring transient selection floats")
expect(workspaceStoreSource.contains("@Published var readerPageIndex = 0")
    && workspaceStoreSource.contains("var readerPageIndex: Int")
    && workspaceStoreSource.contains("func updateReaderPageIndex(_ index: Int)")
    && workspaceStoreSource.contains("func recordReaderPageNavigationPoint()")
    && workspaceStoreSource.contains("readerPageIndex: readerPageIndex")
    && workspaceStoreSource.contains("selectedMaterialItem?.kind == .pdf ? snapshot.readerPageIndex : nil")
    && workspaceStoreSource.contains("recordsLocation: false"), "workspace navigation snapshots restore PDF page position without treating restoration as new study activity")
expect(workspaceStoreSource.contains("case \"return\":\n                if isAskingAgent")
    && workspaceStoreSource.contains("guard !agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }"), "app shortcut stops a running answer but does not swallow command-return when idle with no draft")
expect(workspaceStoreSource.contains("showQuietInsight = false")
    && !workspaceStoreSource.contains("agentSurface == .quietInsight")
    && !workspaceStoreSource.contains("setAgentSurface(.quietInsight)"), "quiet insight surface is disabled and no longer auto-enabled on immersive reading")
expect(workspaceStoreSource.contains("@Published var activeNotebookItemID")
    && workspaceStoreSource.contains("var activeNoteItem: StudyItem?")
    && workspaceStoreSource.contains("guard itemID == activeNoteItemID else { return }"), "note writes are bound to the active note instead of the selected reader material")
expect(workspaceStoreSource.contains("private var pendingNotePersistenceByItemID: [String: PendingNotePersistence] = [:]")
    && workspaceStoreSource.contains("private var pendingNotePersistenceTasks: [String: Task<Void, Never>] = [:]")
    && workspaceStoreSource.contains("private let notePersistenceDebounceDelay")
    && workspaceStoreSource.contains("func updateNote(_ value: String) {\n        guard noteText != value else { return }")
    && workspaceStoreSource.contains("scheduleNotePersistence(value, for: item)")
    && !workspaceStoreSource.contains("func updateNote(_ value: String) {\n        noteText = value\n        clearGeneratedQuietInsight()\n        persistCurrentNote()\n        save()")
    && workspaceStoreSource.contains("func flushPendingNotePersistence()")
    && appSource.contains("sharedWorkspaceStore.flushPendingNotePersistence()"), "markdown typing updates memory immediately but debounces note persistence and flushes pending edits on quit")
expect(workspaceStoreSource.contains("let item = allItems.first(where: { $0.id == itemID && $0.isNotebookNote })")
    && workspaceStoreSource.contains("activeNotebookItemID = item.id")
    && workspaceStoreSource.contains("noteText = noteText(for: item)")
    && !workspaceStoreSource.contains("select(itemID: item.id)\n            noteFileError = ui(\"已创建笔记"), "selecting or creating a notebook note does not replace the current reader material")
expect(workspaceStoreSource.contains("@Published var readerLocationID")
    && workspaceStoreSource.contains("@Published var readerLocationTitle")
    && workspaceStoreSource.contains("func updateReaderHTMLLocation")
    && workspaceStoreSource.contains("var currentReferenceTitle"), "store tracks durable PDF and HTML reader locations")
expect(workspaceStoreSource.contains("private func sessionContinuitySummary(for session: StudySession)")
    && workspaceStoreSource.contains("messages.suffix(20)")
    && workspaceStoreSource.contains("olderMessages.prefix(4)")
    && workspaceStoreSource.contains("olderMessages.suffix(8)"), "durable study sessions inject recent turns plus bounded earlier conversation excerpts into each clean PI run")
expect(workspaceStoreSource.contains("let itemTitle = sourceReferenceBaseTitle(for: item)")
    && workspaceStoreSource.contains("itemTitle: itemTitle")
    && workspaceStoreSource.contains("private func refreshStudyLocationReferenceTitles() -> Bool")
    && workspaceStoreSource.contains("learningMemoryEntries[index].origin = .userStatement\n                    learningMemoryEntries[index].sessionID = activeStudySessionID")
    && workspaceStoreSource.contains("$0.sessionID == activeStudySessionID")
    && workspaceStoreSource.contains("learningMemoryEntries[index].origin == .userStatement")
    && workspaceStoreSource.contains("proposed.origin != .userStatement")
    && !workspaceStoreSource.contains("learningMemoryEntries[index].sessionID = activeStudySessionID\n                learningMemoryEntries[index].updatedAt"), "learning locations preserve duplicate-file identity and inferred memories keep their original session provenance")
expect(workspaceStoreSource.contains("@Published var readerTargetPageIndex")
    && workspaceStoreSource.contains("@Published var readerTargetLocationTitle")
    && workspaceStoreSource.contains("func openSourceReference")
    && workspaceStoreSource.contains("reference.sectionTitle")
    && workspaceStoreSource.contains("reference.sectionLocationID")
    && workspaceStoreSource.contains("reference.sectionOrdinal.map { \"html-heading-\\(max($0 - 1, 0))\" }")
    && workspaceStoreSource.contains("private func sourceReferenceBaseTitle")
    && workspaceStoreSource.contains("return matches.count == 1 ? matches[0] : nil"), "store can jump from source references to PDF pages and HTML sections without guessing between duplicate file titles")
expect(workspaceStoreSource.contains("let sampleItems: [StudyItem] = WorkspaceStore.makeSampleItems()")
    && workspaceStoreSource.contains("StudyItem(id: \"sample-pdf\", title: \"Mishkin 教材样例\", subtitle: \"PDF 阅读\", kind: .pdf, urlPath: samplePDFURL()?.path, isSample: true)")
    && workspaceStoreSource.contains("private var didRunVerificationScenario = false")
    && workspaceStoreSource.contains("func runVerificationScenarioIfNeeded() async")
    && workspaceStoreSource.contains("let scenario = Self.environmentValue(\"WEIBEI_VERIFY_SCENARIO\")")
    && workspaceStoreSource.contains("scenario == \"offline-learning-flow\"")
    && workspaceStoreSource.contains("scenario == \"immersive-conversation-flow\"")
    && workspaceStoreSource.contains("scenario == \"notebook-creation-flow\"")
    && workspaceStoreSource.contains("layout = scenario == \"immersive-conversation-flow\" ? .immersiveConversation : .documentAgentNotes")
    && workspaceStoreSource.contains("if scenario == \"notebook-creation-flow\" {\n            layout = .immersiveWriting")
    && workspaceStoreSource.contains("showLibrary = scenario != \"immersive-conversation-flow\"")
    && workspaceStoreSource.contains("updateSelection(\n            ui(\"利率是资金使用价格的表达。\"")
    && workspaceStoreSource.contains("await askAgentAndWait()")
    && workspaceStoreSource.contains("applyLastAgentAnswerToNote()")
    && workspaceStoreSource.contains("WEIBEI_FORCE_OFFLINE_AGENT")
    && workspaceStoreSource.contains("private static func workspaceRootDirectory() -> URL?")
    && workspaceStoreSource.contains("environmentValue(\"WEIBEI_WORKSPACE_DIR\")")
    && workspaceStoreSource.contains("let directory = root.appendingPathComponent(\"Samples\", isDirectory: true)")
    && workspaceStoreSource.contains("let directory = root.appendingPathComponent(\"Files\", isDirectory: true)")
    && workspaceStoreSource.contains("private static func writeSamplePDF(to url: URL) -> Bool")
    && workspaceStoreSource.contains("CGDataConsumer(data: data as CFMutableData)")
    && workspaceStoreSource.contains("利率是资金使用价格的表达。")
    && !workspaceStoreSource.contains("StudyItem(id: \"sample-pdf\", title: \"Mishkin 教材样例\", subtitle: \"PDF 阅读\", kind: .pdf, urlPath: nil, isSample: true)"), "sample PDF item points at a generated selectable PDF file instead of the fake PDF fallback")
expect(workspaceStoreSource.contains("empty-workspace-light-wide")
    && workspaceStoreSource.contains("empty-workspace-light-narrow")
    && workspaceStoreSource.contains("empty-workspace-calligraphy-light")
    && workspaceStoreSource.contains("empty-workspace-calligraphy-dark")
    && workspaceStoreSource.contains("empty-workspace-dark-wide")
    && workspaceStoreSource.contains("empty-workspace-dark-narrow")
    && workspaceStoreSource.contains("empty-workspace-inspiration-off")
    && workspaceStoreSource.contains("configureEmptyWorkspaceVerificationScenario")
    && workspaceStoreSource.contains("guard Self.environmentValue(\"WEIBEI_SUPPRESS_ACTIVATION\") == \"1\" else { return }")
    && workspaceStoreSource.contains("showReader = false")
    && workspaceStoreSource.contains("showAgent = false")
    && workspaceStoreSource.contains("showNotes = false")
    && workspaceStoreSource.contains("case \"empty-workspace-open-doc\":\n            toggleReader()")
    && workspaceStoreSource.contains("case \"empty-workspace-open-chat\":\n            toggleAgent()")
    && workspaceStoreSource.contains("case \"empty-workspace-open-notes\":\n            toggleNotes()")
    && workspaceStoreSource.contains("Empty workspace entry state marker"), "verification scenarios cover empty light and dark wide and narrow windows plus all three preserved-state entry paths")
expect(workspaceStoreSource.contains("ownerTitle: String? = nil") && workspaceStoreSource.contains("let resolvedOwnerTitle"), "selection updates can carry a precise reader source title")
expect(workspaceStoreSource.contains("@Published var selectionAttachments: [SelectionContext] = []")
    && workspaceStoreSource.contains("@Published var floatingSelectionPrompt = \"\"")
    && workspaceStoreSource.contains("floatingSelectionPrompt = ui(\"当前选区\", \"Current selection\")")
    && workspaceStoreSource.contains("var agentSelectionTitle: String?")
    && workspaceStoreSource.contains("var agentSelectionText: String?")
    && workspaceStoreSource.contains("func removeSelectionAttachment(id: UUID)")
    && workspaceStoreSource.contains("if selectionContext?.id == id {\n                clearUnpinnedFloatingSelection(keepContext: false)")
    && workspaceStoreSource.contains("func clearSelectionAttachments()")
    && workspaceStoreSource.contains("private var pendingSelectionAttachmentTask: Task<Void, Never>?")
    && workspaceStoreSource.contains("private var lastSelectionUpdateDate: Date?")
    && workspaceStoreSource.contains("lastSelectionUpdateDate = Date()")
    && workspaceStoreSource.contains("now.timeIntervalSince($0) > selectionAttachmentMergeWindow")
    && !workspaceStoreSource.contains("guard Self.hasMeaningfulSelectionCharacter(cleaned) else {\n            lastSelectionUpdateDate = nil")
    && !workspaceStoreSource.contains("scheduleSelectionAttachment(nextSelection")
    && workspaceStoreSource.contains("private func scheduleSelectionAttachment(_ selection: SelectionContext, withinSelectionGesture: Bool)")
    && workspaceStoreSource.contains("private let selectionAttachmentDebounceDelay: UInt64 = 520_000_000")
    && workspaceStoreSource.contains("try? await Task.sleep(nanoseconds: self?.selectionAttachmentDebounceDelay ?? 520_000_000)")
    && workspaceStoreSource.contains("private func cancelPendingSelectionAttachment()")
    && workspaceStoreSource.contains("clearUnpinnedFloatingSelection(keepContext: false)")
    // Clear fragments lives on the conversation surface (NotesAgent), not Settings.
    && notesAgentSource.contains("store.clearSelectionAttachments()")
    && workspaceStoreSource.contains("func addSelectionAttachment(_ selection: SelectionContext, withinSelectionGesture: Bool = false)")
    && workspaceStoreSource.contains("private var lastSelectionAttachmentDate: Date?")
    && workspaceStoreSource.contains("private let selectionAttachmentMergeWindow: TimeInterval = 1.8")
    && workspaceStoreSource.contains("while let mergeIndex = selectionAttachments.indices.reversed().first")
    && workspaceStoreSource.contains("selectionAttachments.remove(at: mergeIndex)")
    && workspaceStoreSource.contains("SelectionAttachmentMerge.mergedText")
    && workspaceStoreSource.contains("withinSelectionGesture || withinSelectionGestureHint")
    && workspaceStoreSource.contains("let maxAttachments = 8")
    && workspaceStoreSource.contains("Live selection (before/without")
    && workspaceStoreSource.contains("if selectionAttachments.isEmpty,\n           let selectionContext,"), "agent selection context uses removable attachments, falls back to live selection, and attaches before send")
expect(workspaceStoreSource.contains("selectionTitle: sentSelectionTitle")
    && workspaceStoreSource.contains("selectionText: sentSelectionText")
    && !workspaceStoreSource.contains("selectionText: selectionContext?.text,\n                recentMessages: recentMessages"), "agent requests capture selection via sentSelectionText (attachments or live fallback), not a raw live-only field")
expect(workspaceStoreSource.contains("let sentSelectionTitle = agentSelectionTitle")
    && workspaceStoreSource.contains("let sentSelectionText = agentSelectionText")
    && workspaceStoreSource.contains("selectionAttachments = []")
    && workspaceStoreSource.contains("selectionTitle: sentSelectionTitle")
    && workspaceStoreSource.contains("selectionText: sentSelectionText"), "sending captures selected text attachments for the request and clears the composer attachments afterward")
expect(workspaceStoreSource.contains("private static func boundedSelectionText")
    && workspaceStoreSource.contains("let cleaned = MarkdownSelectionSanitizer.clean(text)")
    && workspaceStoreSource.contains("Self.boundedSelectionText(cleaned)")
    && workspaceStoreSource.contains("lastIndex(where:")
    && !workspaceStoreSource.contains("String(cleaned.prefix(2_000))"), "selection context cleans callout control markers and truncates at a word or line boundary")
expect(workspaceStoreSource.contains("var hasPrimaryConversationPaneVisible: Bool")
    && workspaceStoreSource.contains("case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:\n            return showAgent")
    && workspaceStoreSource.contains("case .immersiveConversation:\n            return true")
    && workspaceStoreSource.contains("var isConversationSurfaceVisible: Bool")
    && workspaceStoreSource.contains("var canShowSelectionPromptSurface: Bool")
    && workspaceStoreSource.contains("var canShowSelectionPromptSurface: Bool {\n        true")
    && workspaceStoreSource.contains("case .immersiveReading, .immersiveWriting:")
    && workspaceStoreSource.contains("// Overlay chat surfaces"), "workspace has one shared rule for primary conversation panes, formal conversation surfaces, and prompt-only selection affordances")
if let updateSelectionStart = workspaceStoreSource.range(of: "func updateSelection(_ text: String")?.lowerBound,
   let removeSelectionStart = workspaceStoreSource.range(of: "func removeSelectionAttachment")?.lowerBound {
    let updateSelectionSource = String(workspaceStoreSource[updateSelectionStart..<removeSelectionStart])
    expect(updateSelectionSource.contains("let shouldRevealSelectionPrompt = anchor != nil || pinnedFloatingAgent")
        && !updateSelectionSource.contains("&& !isConversationSurfaceVisible")
        && updateSelectionSource.contains("selectionAnchor = anchor")
        && updateSelectionSource.contains("cancelPendingSelectionAttachment()")
        && !updateSelectionSource.contains("scheduleSelectionAttachment(nextSelection")
        && !updateSelectionSource.contains("let shouldRouteToConversation")
        && !updateSelectionSource.contains("addSelectionAttachment(nextSelection)")
        && !updateSelectionSource.contains("focusedPane = .agent\n                focusRequest += 1")
        && updateSelectionSource.contains("if shouldRevealSelectionPrompt {"), "selection updates show the local selection capsule in multi-pane and immersive without auto-adding chat attachments")
} else {
    expect(false, "updateSelection source is readable")
}
expect(workspaceStoreSource.contains("func askSelection()")
    && workspaceStoreSource.contains("agentSurface = .selectionFloat")
    && workspaceStoreSource.contains("keepFloatingSelectionForAnswer = true")
    && workspaceStoreSource.contains("beginOrReuseSelectionAskThread")
    && workspaceStoreSource.contains("func routeSelectionToConversation")
    && workspaceStoreSource.components(separatedBy: "withAnimation(WeiBeiMotion.panel) {").count >= 3, "asking a selection keeps the floating agent open for dual-surface answers")
if let askSelectionStart = workspaceStoreSource.range(of: "func askSelection()")?.lowerBound,
   let routeSelectionStart = workspaceStoreSource.range(of: "func routeSelectionToConversation")?.lowerBound {
    let askSelectionSource = String(workspaceStoreSource[askSelectionStart..<routeSelectionStart])
    expect(askSelectionSource.contains("addSelectionAttachment(selectionContext)")
        && askSelectionSource.contains("keepFloatingSelectionForAnswer = true")
        && askSelectionSource.contains("beginOrReuseSelectionAskThread")
        && askSelectionSource.contains("activeSelectionAskThreadID")
        && askSelectionSource.contains("if isConversationSurfaceVisible")
        && askSelectionSource.contains("keepFloatingSelectionForAnswer = false")
        && !askSelectionSource.contains("pinnedFloatingAgent = true")
        && !askSelectionSource.contains("请解释当前已选文本片段")
        && !askSelectionSource.contains("agentDraft = prompt")
        && !askSelectionSource.contains("选区："), "selection question attaches context; float opens only when conversation pane is closed")
} else {
    expect(false, "askSelection source is readable")
}
expect(workspaceStoreSource.contains("selectionAttachments\n                .map { quotedReferenceBlock(text: $0.text, sourceTitle: $0.ownerTitle) }")
    && workspaceStoreSource.contains("sourceTitle: selectionContext.ownerTitle")
    && workspaceStoreSource.contains("来源：\\(currentSourceReferenceTitle)")
    && workspaceStoreSource.contains("\\(itemTitle)，章节标识：\\(locationID)，章节：\\(locationTitle)")
    && workspaceStoreSource.contains("\\(itemTitle)，章节序号：\\(sectionOrdinal)，章节：\\(locationTitle)"), "copy reference uses attached selections or a canonical file-plus-location source")
expect(workspaceStoreSource.contains("private func quotedReferenceBlock")
    && workspaceStoreSource.contains("let quoted = MarkdownSelectionSanitizer.clean(text)")
    && workspaceStoreSource.contains("> [!quote] 选区摘录")
    && workspaceStoreSource.contains("> [!quote] Selection excerpt")
    && workspaceStoreSource.contains("\\(quoted)")
    && workspaceStoreSource.contains("> 来源：\\(sourceTitle)")
    && workspaceStoreSource.contains("> Source: \\(sourceTitle)")
    && !workspaceStoreSource.contains("## 选区摘录"), "selection excerpts use the shared quote callout format with a separate editable body")
expect(workspaceStoreSource.contains("selectionOwnerTitle(for source: SelectionSource)") && workspaceStoreSource.contains("activeNoteItem?.isNotebookNote == true"), "selection fallback title treats notebook notes as notes")
expect(workspaceStoreSource.contains("var selectedMaterialItem") && workspaceStoreSource.contains("!item.isNotebookNote"), "selected material excludes notebook notes")
expect(workspaceStoreSource.contains("var navigableItems") && workspaceStoreSource.contains("let materialItems = allItems.filter { !$0.isNotebookNote }"), "material navigation skips notebook notes")
expect(
    workspaceStoreSource.contains("guard hasSelectedMaterial else")
        && workspaceStoreSource.contains("clearReaderSearchIfNeeded()")
        && workspaceStoreSource.contains("if layout == .immersiveConversation || layout == .immersiveWriting")
        && workspaceStoreSource.contains("setLayout(.immersiveReading)"),
    "reader search reveal refuses notebook-only context and moves to a visible reader layout"
)
expect(
    workspaceStoreSource.contains("clearReaderSearchIfNeeded()")
        && workspaceStoreSource.contains("guard !hasSelectedMaterial else { return }")
        && workspaceStoreSource.contains("showReaderSearch = false")
        && workspaceStoreSource.contains("readerSearch = \"\""),
    "material search state clears when selection no longer points to a material"
)
if let hideReaderSearchStart = workspaceStoreSource.range(of: "func hideReaderSearch()")?.lowerBound,
   let updateReaderLocationStart = workspaceStoreSource.range(of: "func updateReaderLocationTitle")?.lowerBound {
    let hideReaderSearchSource = String(workspaceStoreSource[hideReaderSearchStart..<updateReaderLocationStart])
    expect(hideReaderSearchSource.contains("clearUnpinnedFloatingSelection(keepContext: false)") && !hideReaderSearchSource.contains("selectionContext = nil"), "reader search dismissal preserves pinned selection agents through the shared clear helper")
} else {
    expect(false, "reader search dismissal source is readable")
}
expect(workspaceStoreSource.contains("var selectedMaterialTitle") && workspaceStoreSource.contains("selectedMaterialItem.map(displayTitle) ?? ui(\"未选择材料\""), "agent material title does not invent a current material")
expect(workspaceStoreSource.contains("var agentMessageSourceTitle: String?") && workspaceStoreSource.contains("hasSelectedMaterial ? currentSourceReferenceTitle : activeNoteItem.map(displayTitle)") && !workspaceStoreSource.contains("source: selectedMaterialItem?.title"), "agent message source uses the canonical file location and falls back to the localized active note title")
expect(workspaceStoreSource.contains("let sentMaterialTitle = currentSourceReferenceTitle")
    && workspaceStoreSource.contains("materialTitle: sentMaterialTitle"), "agent prompt snapshots the canonical file location so PDF pages and HTML sections reach the model")
expect(workspaceStoreSource.contains("private var quietInsightReferenceTitle: String")
    && workspaceStoreSource.contains("selectionContext?.ownerTitle")
    && workspaceStoreSource.contains("currentSourceReferenceTitle")
    && workspaceStoreSource.contains("Quiet insight generation disabled for 1.0"), "quiet insight reference title remains available while generation stays disabled for 1.0")
expect(workspaceStoreSource.contains("private func clearUnpinnedFloatingSelection(keepContext: Bool = true, invalidatesAgentContext: Bool = true)")
    && workspaceStoreSource.contains("if invalidatesAgentContext, selectionContext != nil")
    && workspaceStoreSource.contains("selectionContext = nil")
    && workspaceStoreSource.contains("selectionAnchor = nil")
    && workspaceStoreSource.contains("floatingSelectionPrompt = ui(\"当前选区\"")
    && workspaceStoreSource.contains("pinnedFloatingAgent = false")
    && workspaceStoreSource.contains("if agentSurface == .selectionFloat {\n                agentSurface = .hidden\n            }\n            return")
    && workspaceStoreSource.contains("guard !pinnedFloatingAgent else { return }")
    && workspaceStoreSource.contains("if agentSurface == .selectionFloat"), "cleared selections remove stale context badges before preserving any pinned floating window")
if let dismissFloatingStart = workspaceStoreSource.range(of: "func dismissFloatingSelectionAgent()")?.lowerBound,
   let setNoteRenderModeStart = workspaceStoreSource.range(of: "func setNoteRenderMode")?.lowerBound {
    let dismissFloatingSource = String(workspaceStoreSource[dismissFloatingStart..<setNoteRenderModeStart])
    expect(!dismissFloatingSource.contains("agentDraft = \"\""), "dismissing the selection float does not erase text already typed in the shared agent composer")
} else {
    expect(false, "floating selection dismissal source is readable")
}
expect(workspaceStoreSource.contains("guard Self.hasMeaningfulSelectionCharacter(cleaned) else {")
    && workspaceStoreSource.contains("now.timeIntervalSince($0) > selectionAttachmentMergeWindow")
    && workspaceStoreSource.contains("clearUnpinnedFloatingSelection(keepContext: false)\n            return\n        }")
    && workspaceStoreSource.contains("private static func hasMeaningfulSelectionCharacter(_ text: String) -> Bool")
    && workspaceStoreSource.contains("!CharacterSet.whitespacesAndNewlines.contains(scalar)")
    && workspaceStoreSource.contains("!CharacterSet.punctuationCharacters.contains(scalar)")
    && workspaceStoreSource.contains("!CharacterSet.controlCharacters.contains(scalar)"), "empty, whitespace, punctuation, or control-only selections clear the prompt without breaking a live drag-selection gesture")
if let updateSelectionStart = workspaceStoreSource.range(of: "func updateSelection(_ text: String")?.lowerBound,
   let removeSelectionStart = workspaceStoreSource.range(of: "func removeSelectionAttachment")?.lowerBound {
    let liveSelectionUpdateSource = String(workspaceStoreSource[updateSelectionStart..<removeSelectionStart])
    expect(liveSelectionUpdateSource.contains("floatingSelectionPrompt = nextSelection.label(language: interfaceLanguage)")
        && liveSelectionUpdateSource.contains("if pinnedFloatingAgent || keepFloatingSelectionForAnswer")
        && !liveSelectionUpdateSource.contains("pinnedFloatingAgent = false")
        && liveSelectionUpdateSource.contains("cancelPendingSelectionAttachment()")
        && liveSelectionUpdateSource.contains("if shouldRevealSelectionPrompt {")
        && liveSelectionUpdateSource.contains("anchorsApproximatelyEqual")
        && !liveSelectionUpdateSource.contains("withAnimation(WeiBeiMotion.panel) {\n            selectionContext = nextSelection")
        && !liveSelectionUpdateSource.contains("withAnimation(WeiBeiMotion.panel) {\n            selectionContext = nextSelection\n            selectionAnchor = anchor"), "pinned/answer-locked floats survive new selections; continuous selection fields update without a panel spring, and only surface show/hide may animate")
} else {
    expect(false, "updateSelection animation policy source is readable")
}
expect(workspaceStoreSource.contains("let itemChanged = selectedItemID != itemID") && workspaceStoreSource.contains("clearUnpinnedFloatingSelection(keepContext: false)"), "selecting a different item clears the old selection context")
expect(workspaceStoreSource.contains("func toggleLibrary()")
    && workspaceStoreSource.contains("let willShow = !showLibrary")
    && workspaceStoreSource.contains("showLibrary = willShow")
    && workspaceStoreSource.contains("final class LibraryDrawerState: ObservableObject")
    && workspaceStoreSource.contains("let libraryDrawer = LibraryDrawerState()")
    && workspaceStoreSource.contains("DispatchQueue.main.async")
    && workspaceStoreSource.contains("clearUnpinnedFloatingSelection()")
    && !workspaceStoreSource.contains("func toggleLibrary() {\n        recordNavigationPoint()")
    && workspaceStoreSource.contains("func toggleRightPane() {\n        guard layout.hasCollapsibleRightPane else { return }\n        recordNavigationPoint()\n        showRightPane.toggle()\n        clearUnpinnedFloatingSelection()"), "the transient course drawer stays out of navigation history while durable pane visibility still records navigation")
expect(workspaceStoreSource.contains("collapseSelectionFloatIntoConversationIfVisible()\n        focusedPane = pane")
    && workspaceStoreSource.contains("private func collapseSelectionFloatIntoConversationIfVisible()")
    && workspaceStoreSource.contains("guard isConversationSurfaceVisible, agentSurface == .selectionFloat else { return }")
    && workspaceStoreSource.contains("selectionAnchor = nil\n        pinnedFloatingAgent = false"), "opening or focusing the formal conversation surface collapses any stale selection mini window but keeps the selected text context")
expect(workspaceStoreSource.contains("focus(showRightPane ? rightPaneRevealFocus : fallbackDocumentPaneFocus())")
    && workspaceStoreSource.contains("private var rightPaneRevealFocus: PaneFocus")
    && workspaceStoreSource.contains("if layout.isDocumentThreePane")
    && workspaceStoreSource.contains("return normalizedThreePaneOrder.last?.focus ?? .notes")
    && workspaceStoreSource.contains("case .documentNotesAgent, .immersiveConversation:\n            return .agent"), "right-pane reveal focuses the visible pane by current role order instead of legacy fixed layout names")
expect(workspaceStoreSource.contains("func revealLibrary()")
    && workspaceStoreSource.contains("if !showLibrary {\n            clearUnpinnedFloatingSelection()\n        }")
    && workspaceStoreSource.contains("showLibrary = true\n        focus(.library)")
    && !workspaceStoreSource.contains("focus(.library)\n        save()"), "library reveal uses transient in-memory state without writing the workspace")
expect(workspaceStoreSource.contains("layout == .immersiveReading || layout == .immersiveWriting")
    && workspaceStoreSource.contains("layout = .immersiveConversation")
    && !workspaceStoreSource.contains("agentSurface = .cornerPanel")
    && !workspaceStoreSource.contains("agentSurface = .bottomDrawer"), "agent focus in immersive layouts opens immersive conversation instead of deleted overlays")
if let setLayoutStart = workspaceStoreSource.range(of: "func setLayout(_ layout: WorkspaceLayout)")?.lowerBound,
   let setAgentSurfaceStart = workspaceStoreSource.range(of: "func setAgentSurface")?.lowerBound {
    let setLayoutSource = String(workspaceStoreSource[setLayoutStart..<setAgentSurfaceStart])
    expect(!setLayoutSource.contains("showLibrary = false"), "layout switching preserves the current library visibility")
    expect(!setLayoutSource.contains("showRightPane = true"), "layout switching preserves a user-collapsed auxiliary pane")
    expect(setLayoutSource.contains("clearUnpinnedFloatingSelection()"), "layout switching invalidates stale floating selection anchors")
} else {
    expect(false, "layout switching source is readable")
}
if let agentFocusStart = workspaceStoreSource.range(of: "if pane == .agent")?.lowerBound,
   let focusEnd = workspaceStoreSource.range(of: "focusedPane = pane")?.lowerBound {
    let agentFocusSource = String(workspaceStoreSource[agentFocusStart..<focusEnd])
    expect(!agentFocusSource.contains("showLibrary = false"), "agent focus does not close a user-opened immersive library")
} else {
    expect(false, "agent focus source is readable")
}
if let insertStart = workspaceStoreSource.range(of: "func insertMarkdownSnippet")?.lowerBound,
   let insertEnd = workspaceStoreSource[insertStart...].range(of: "\n    }\n")?.upperBound {
    let insertSource = String(workspaceStoreSource[insertStart..<insertEnd])
    expect(!insertSource.contains("showLibrary = false"), "markdown insertion keeps a user-opened immersive library visible")
} else {
    expect(false, "markdown insertion source is readable")
}
if let setNoteModeStart = workspaceStoreSource.range(of: "func setNoteRenderMode(_ mode: NoteRenderMode)")?.lowerBound,
   let revealStart = workspaceStoreSource.range(of: "private func revealRichWritingSurface")?.lowerBound {
    let setNoteModeSource = String(workspaceStoreSource[setNoteModeStart..<revealStart])
    expect(
        setNoteModeSource.contains("let nextMode = mode.visibleMode")
            && setNoteModeSource.contains("layout = .immersiveWriting")
            && setNoteModeSource.contains("showNotes = true")
            && setNoteModeSource.contains("noteRenderMode = nextMode")
            && setNoteModeSource.contains("focus(.notes)"),
        "note render mode commands normalize legacy preview, reveal, and focus the writing surface"
    )
} else {
    expect(false, "note render mode source is readable")
}
expect(workspaceStoreSource.contains("var canUseSelectionAgentSurface: Bool")
    && workspaceStoreSource.contains("var visibleAgentSurfaces: [AgentSurface]")
    && workspaceStoreSource.contains("guard surface != .selectionFloat || canUseSelectionAgentSurface else { return }")
    && workspaceStoreSource.contains("case .selectionPrompt:")
    && workspaceStoreSource.contains("guard canUseSelectionAgentSurface else { return false }")
    && workspaceStoreSource.contains("setAgentSurface(.selectionFloat)")
    && workspaceStoreSource.contains("self.agentSurface = agentSurface == .selectionFloat ? .hidden : agentSurface")
    && workspaceStoreSource.contains("agentSurface: agentSurface == .selectionFloat ? .hidden : agentSurface"), "selection-float agent surface is hidden, rejected, and never restored as durable workspace chrome")
expect(!workspaceStoreSource.contains("selectedItem?.title ?? \"当前材料\"")
    && !workspaceStoreSource.contains("保存后 Agent 会用")
    && !workspaceStoreSource.contains("Agent 可在打包应用里直接读取")
    && !workspaceStoreSource.contains("Agent 不会编造回答")
    && workspaceStoreSource.contains("AgentFailureKind.classify(error)")
    && workspaceStoreSource.contains("draftPreserved: true")
    && workspaceStoreSource.contains("func retryLastFailedAgentRequest()")
    && !workspaceStoreSource.contains("Agent 设置")
    && workspaceStoreSource.contains("PI 与在线密钥均不可用，当前使用离线草稿。")
    && workspaceStoreSource.contains("OfflineStudyAgentRuntime().respond")
    && workspaceStoreSource.contains("PiAgentRuntime")
    && workspaceStoreSource.contains("appendAgentMessage(AgentMessage(role: .user, text: question, source: sourceTitle))")
    && !workspaceStoreSource.contains("未配置 OPENAI_API_KEY 或钥匙串密钥")
    // Provider-aware key help + in-field key used for requests (local secret file + keychain mirror).
    && workspaceStoreSource.contains("正在使用本机环境变量")
    && workspaceStoreSource.contains("设置中的密钥")
    && workspaceStoreSource.contains("密钥保存在魏碑应用数据中")
    && workspaceStoreSource.contains("let fieldKey = OpenAIAPIKeyStore.cleaned(openAIAPIKey)")
    && workspaceStoreSource.contains("resolveStoredAPIKey()")
    && workspaceStoreSource.contains("已清除密钥。")
    && workspaceStoreSource.contains("密钥已保存到当前配置。")
    && workspaceStoreSource.contains("AgentCredentialProfileStore")
    && !workspaceStoreSource.contains("打包应用可直接读取")
    && !workspaceStoreSource.contains("已清除钥匙串密钥。")
    && !workspaceStoreSource.contains("已保存到 macOS 钥匙串。")
    && !workspaceStoreSource.contains("已选择材料、当前选区和右侧笔记"), "agent context and setup notices avoid fake material fallback copy and visible internal agent labels")
expect(
    workspaceStoreSource.contains("let selectedProvider = agentProviderID")
        && workspaceStoreSource.contains("let linkedOAuth = PiOAuthService.readLinkedOAuthProviders")
        && workspaceStoreSource.contains("if !explicitProvider.isEmpty { return explicitProvider }")
        && workspaceStoreSource.contains("if selectedProvider == .openaiCodex { return \"openai-codex\" }")
        && workspaceStoreSource.contains("apiKey: usesOAuth ? nil : credential?.key")
        && workspaceStoreSource.contains("thinkingLevel: thinking.isEmpty ? \"medium\" : thinking"),
    "PI honors the selected provider, reuses subscription OAuth without injecting an API key, and keeps the current thinking default"
)
if let requestStart = workspaceStoreSource.range(of: "private func performAgentRequest() async")?.lowerBound,
   let executionStart = workspaceStoreSource.range(of: "private func executeStudyAgentRequest")?.lowerBound {
    let requestSource = String(workspaceStoreSource[requestStart..<executionStart])
    expect(requestSource.contains("agentDraft = \"\"")
        && requestSource.contains("flushStagedNoteDraftForAgentContext()")
        && requestSource.contains("selectionAttachments = []")
        && requestSource.contains("let shouldClearSentDocumentSelection = sentSelectionText != nil && selectionContext?.source == .document")
        && requestSource.contains("clearUnpinnedFloatingSelection(keepContext: false, invalidatesAgentContext: false)")
        && requestSource.contains("appendAgentMessage(AgentMessage(role: .user, text: question, source: sourceTitle))")
        && requestSource.contains("let sentLearningContext = makeLearningContext()")
        && requestSource.contains("let courseBuild = try await makeCourseContext(query: courseQuery)")
        && requestSource.contains("materialIsTruncated: courseBuild.selectedMaterialIsTruncated")
        && requestSource.contains("courseContext: courseBuild.context")
        && requestSource.contains("learningContext: sentLearningContext")
        && requestSource.contains("let reply = try await executeStudyAgentRequest(request)")
        && requestSource.contains("applyLearningUpdate(")
        && requestSource.contains("expectedUserQuestion: request.question")
        && requestSource.contains("requestWorkspaceRevision == agentContextRevision")
        && requestSource.contains("requestMemoryRevision == learningMemoryRevision")
        && requestSource.contains("lastAgentReplyContextRevision = requestWorkspaceRevision")
        && requestSource.contains("contextRevision: \"\\(requestWorkspaceRevision):\\(requestID.uuidString.lowercased())\""),
        "agent send clears the composer, executes the unified runtime, and accepts only the current context revision")
} else {
    expect(false, "unified agent request source is readable")
}
expect(workspaceStoreSource.contains("@Published private(set) var studySessions")
    && workspaceStoreSource.contains("func createStudySession()")
    && workspaceStoreSource.contains("func activateStudySession(_ id: UUID)")
    && workspaceStoreSource.contains("private func syncActiveStudySession(titleSeed: String? = nil)")
    && workspaceStoreSource.contains("private func appendAgentMessage(_ message: AgentMessage)"), "agent conversations are durable course study sessions")
expect(workspaceStoreSource.contains("noteSourceLinks: noteSourceLinks")
    && workspaceStoreSource.contains("studyLocationsByItemID: studyLocationsByItemID")
    && workspaceStoreSource.contains("learningMemoryEntries: learningMemoryEntries")
    && workspaceStoreSource.contains("learningMemoryRevision: learningMemoryRevision")
    && workspaceStoreSource.contains("studySessions: studySessions")
    && workspaceStoreSource.contains("activeStudySessionID: activeStudySessionID"), "course links, progress, memory, and sessions are saved with the workspace")
expect(workspaceStoreSource.contains("acceptedUpdate.resolutions = update.resolutions.prefix(12).filter")
    && workspaceStoreSource.contains("func confirmLearningMemoryResolution")
    && workspaceStoreSource.contains("private static func resolutionEvidenceMatches")
    && workspaceStoreSource.contains("StudyAgentResolutionEvidence.matches")
    && workspaceStoreSource.contains("func restoreLearningMemory(")
    && workspaceStoreSource.contains("resolutionEvidence = \"[用户：界面确认]\"")
    && notesAgentSource.contains("建议结案：")
    && notesAgentSource.contains("store.confirmLearningMemoryResolution(resolution)")
    && notesAgentSource.contains("store.restoreLearningMemoryResolution(resolution)"), "PI can only propose memory resolution; user confirmation persists it and the UI can undo it")
expect(workspaceStoreSource.contains("} else {\n            restoreCurrentStudyLocation()\n            recordCurrentStudyLocation(incrementVisit: false)\n        }")
    && workspaceStoreSource.contains("private func restoreCurrentStudyLocation()")
    && workspaceStoreSource.contains("readerPageIndex = max(location.pageIndex ?? 0, 0)")
    && workspaceStoreSource.contains("requestReaderPDFPage(location.pageIndex, recordsLocation: false)"), "saved heading and PDF page are restored before startup records the current study location")
expect(workspaceStoreSource.contains("private func makeCourseContext(query: String) async throws")
    && workspaceStoreSource.contains("CourseKnowledgeIndex.build(")
    && workspaceStoreSource.contains("courseDocumentSearchIndex: CourseDocumentSearchIndex")
    && workspaceStoreSource.contains("course-search-v3.sqlite3")
    && workspaceStoreSource.contains("removeLegacyCourseIndex")
    && workspaceStoreSource.contains("let indexedByItemID = searchIndex.lookup(")
    && workspaceStoreSource.contains("candidate.item.isSample")
    && workspaceStoreSource.contains("Task.detached(priority: .userInitiated)")
    && workspaceStoreSource.contains("withTaskCancellationHandler")
    && workspaceStoreSource.contains("migrateNoteSourceLinksFromMarkdown()"), "agent queries the persistent course index in the background and migrates durable note-source links")
if let selectStart = workspaceStoreSource.range(of: "func select(itemID: String?)")?.lowerBound,
   let selectEnd = workspaceStoreSource[selectStart...].range(of: "\n    func ", options: [], range: workspaceStoreSource.index(after: selectStart)..<workspaceStoreSource.endIndex)?.lowerBound {
    let selectSource = String(workspaceStoreSource[selectStart..<selectEnd])
    expect(!selectSource.contains("messages = []")
        && selectSource.contains("syncActiveStudySession()")
        && selectSource.contains("recordCurrentStudyLocation("), "changing course material preserves the active conversation and records progress")
} else {
    expect(false, "course material selection source is readable")
}
expect(workspaceStoreSource.contains("func stageNoteDraft(_ value: String, for itemID: String?)")
    && workspaceStoreSource.contains("if stagedNoteDraft?.itemID != itemID || stagedNoteDraft?.value != value {\n            invalidateAgentContext()")
    && workspaceStoreSource.contains("private func flushStagedNoteDraftForAgentContext()")
    && notesAgentSource.contains("store.stageNoteDraft(value, for: draftNoteItemID)"), "agent requests flush the current local note-editor draft before snapshotting context")
expect(workspaceStoreSource.contains("func updateReaderLocationTitle(_ title: String?)")
    && workspaceStoreSource.contains("func updateReaderHTMLLocation(id: String?, title: String?, reason: String)")
    && workspaceStoreSource.contains("PaneToggleContinuityVerifier.recordHTMLLocationCall(reason: reason)")
    && workspaceStoreSource.contains("if !incrementVisit,")
    && workspaceStoreSource.contains("previous?.locationID == locationID")
    && workspaceStoreSource.contains("private(set) var studyLocationsByItemID")
    && !workspaceStoreSource.contains("@Published private(set) var studyLocationsByItemID")
    && readerViewSource.contains("guard change.reason == .scroll || change.reason == .jump else { return }")
    && readerViewSource.contains("Task.sleep(nanoseconds: 350_000_000)"), "passive reader layout stays local while settled user navigation persists without publishing duplicate study locations")
expect(workspaceStoreSource.contains("var agentPromptScope") && workspaceStoreSource.contains("var selectionPromptScope") && !workspaceStoreSource.contains("var libraryOrganizationScope"), "agent prompt builders avoid half-built library organization context")
expect(!workspaceStoreSource.contains("请根据当前文档和当前笔记") && !workspaceStoreSource.contains("请根据当前材料和当前笔记") && !workspaceStoreSource.contains("结合当前文档和笔记"), "agent draft presets do not hardcode fake material context")
expect(workspaceStoreSource.contains("正在静默阅读当前材料和笔记。")
    && workspaceStoreSource.contains("正在静默阅读当前笔记。")
    && !workspaceStoreSource.contains("Agent 正在静默阅读"), "quiet insight progress copy avoids a visible internal agent label")
expect(workspaceStoreSource.contains("scenario == \"notebook-creation-flow\"")
    && workspaceStoreSource.contains("promptCreateBlankNotebookNote()\n            return"), "visual verification can exercise blank notebook creation")
expect(workspaceStoreSource.contains("private func noteBlockForAgentAnswer")
    && workspaceStoreSource.contains("AgentOfflinePreview.suggestedNoteBlock(from: text, language: interfaceLanguage)")
    && workspaceStoreSource.contains("guard !text.hasPrefix(\"#\") else { return text }")
    && workspaceStoreSource.contains("return \"## \\(ui(\"整理建议\", \"Organization suggestion\"))\\n\\(text)\"")
    && workspaceStoreSource.contains("let content = latestAgentNoteProposal?.markdown ?? answer.text")
    && workspaceStoreSource.contains("markdown: \"\\n\\(noteBlockForAgentAnswer(content))\"")
    && !workspaceStoreSource.contains("## Agent 整理建议"), "agent note writeback prefers a revision-matched PI proposal before falling back to a reader-facing answer section")
expect(workspaceStoreSource.contains("func createBlankNotebookNote()")
    && workspaceStoreSource.contains("func createNotebookNoteFromCurrentMaterial()")
    && workspaceStoreSource.contains("func promptCreateBlankNotebookNote()")
    && workspaceStoreSource.contains("func promptCreateNotebookNoteFromCurrentMaterial()")
    && workspaceStoreSource.contains("@Published var notebookCreationDraft")
    && workspaceStoreSource.contains("struct NotebookCreationDraft")
    && workspaceStoreSource.contains("private func createNotebookNote(seed: NotebookNoteSeed, title")
    && !workspaceStoreSource.contains("func resetNote()")
    && !workspaceStoreSource.contains("updateNote(defaultNote(for: selectedItem))"), "new note commands separate blank notes from current-material notes and route through the inline naming strip")
expect(workspaceStoreSource.contains("private func openExistingNotebookNote(for material: StudyItem) -> Bool")
    && workspaceStoreSource.contains("if openExistingNotebookNote(for: selectedMaterialItem)")
    && workspaceStoreSource.contains("private func existingNotebookNote(for material: StudyItem) -> StudyItem?")
    && workspaceStoreSource.contains("let titles = Set([currentTitle, chineseTitle, englishTitle, displayChineseTitle, displayEnglishTitle])")
    && workspaceStoreSource.contains("已打开现有资料笔记"), "current-material note creation opens an existing matching notebook note instead of prompting a duplicate")
expect(workspaceStoreSource.contains("case currentMaterial(StudyItem)")
    && workspaceStoreSource.contains("private func suggestedNotebookTitle(for seed: NotebookNoteSeed)")
    && workspaceStoreSource.contains("let markdown = defaultNotebookNote(title: item.title, sourceItem: sourceItem)")
    && workspaceStoreSource.contains("try markdown.write(to: url"), "new notebook notes are backed by local markdown files and can be seeded from the current material")
expect(workspaceStoreSource.contains("func cancelNotebookNoteCreation()")
    && workspaceStoreSource.contains("func confirmNotebookNoteCreation()")
    && workspaceStoreSource.contains("notebookCreationDraft = NotebookCreationDraft(")
    && workspaceStoreSource.contains("let title = draft.title.trimmingCharacters")
    && workspaceStoreSource.contains("func select(itemID: String?)")
    && workspaceStoreSource.contains("private func selectMeasured(itemID: String?) {\n        invalidateAgentContext()\n        persistCurrentNote()\n        notebookCreationDraft = nil")
    && !workspaceStoreSource.contains("private func promptCreateNotebookNote(seed: NotebookNoteSeed)")
    && !workspaceStoreSource.contains("alert.messageText = seed.isBlank"), "new-note creation opens the inline naming strip and confirms through the shared local markdown creator")
expect(workspaceStoreSource.contains("importedItems.append(item)")
    && workspaceStoreSource.contains("courseDocumentSearchIndex.synchronize(allItems)")
    && workspaceStoreSource.contains("addNoteSourceLink(noteItemID: item.id, sourceItemID: sourceItem.id)")
    && workspaceStoreSource.contains("activeNotebookItemID = item.id\n            noteText = markdown\n            revealRichWritingSurface()\n            focus(.notes)\n            save()"), "new notebook notes persist their material link, join the course index, and open in the note pane without replacing the reader material")
expect(workspaceStoreSource.contains("private func showTransientNoteStatus(_ message: String)")
    && workspaceStoreSource.contains("transientNoteStatus = message")
    && workspaceStoreSource.contains("@Published var transientNoteStatus")
    && workspaceStoreSource.contains("Task { @MainActor [weak self] in")
    && workspaceStoreSource.contains("if self.transientNoteStatus == token")
    && workspaceStoreSource.contains("已新建空白笔记")
    && workspaceStoreSource.contains("已为当前资料新建笔记"), "successful note creation feedback clears itself and names the creation path")
expect(workspaceStoreSource.contains("func promptRenameNotebookNote(itemID: String)")
    && workspaceStoreSource.contains("@Published var notebookRenameDraft")
    && workspaceStoreSource.contains("struct NotebookRenameDraft")
    && workspaceStoreSource.contains("func cancelRenameNotebookNote()")
    && workspaceStoreSource.contains("func confirmRenameNotebookNote()")
    && workspaceStoreSource.contains("func renameNotebookNote(itemID: String, to rawTitle: String)")
    && workspaceStoreSource.contains("sourceMarkdown = wasActiveNotebook ? noteText : try notebookMarkdownReader(oldURL)")
    && workspaceStoreSource.contains("try writePendingNotebookRenameJournal(renameJournal)")
    && workspaceStoreSource.contains("try notebookFileMover(oldURL, newURL)")
    && workspaceStoreSource.contains("let coordinator = NSFileCoordinator(filePresenter: nil)")
    && workspaceStoreSource.contains("try notebookMarkdownWriter(retitledMarkdown, coordinatedURL)")
    && workspaceStoreSource.contains("outputDigest == expectedOutputDigest")
    && workspaceStoreSource.contains("activeNotebookItemID = newID")
    && workspaceStoreSource.contains("noteText = retitledMarkdown")
    && workspaceStoreSource.contains("replaceNavigationItemID(oldID, with: newID)")
    && workspaceStoreSource.contains("guard save() else")
    && workspaceStoreSource.contains("文件已重命名，但课程状态尚未写入磁盘")
    && workspaceStoreSource.contains("notebookRenameDraft = nil")
    && !workspaceStoreSource.contains("alert.messageText = ui(\"重命名笔记\""), "renaming a notebook note updates the local markdown file, active note identity, heading, and navigation snapshots without a system alert")
expect(workspaceStoreSource.contains("let title = item.map(displayTitle) ?? ui(\"新笔记\"")
    && workspaceStoreSource.contains("let sourceItem = item?.isNotebookNote == true ? nil : item")
    && workspaceStoreSource.contains("private func defaultNotebookNote(title: String, sourceItem: StudyItem?)")
    && workspaceStoreSource.contains("let excerptSeed = sourceItem.map { ui(\"> 来源：\\(displayTitle(for: $0))\\n\"")
    && workspaceStoreSource.contains("## \\(ui(\"核心要点\", \"Key Points\"))")
    && workspaceStoreSource.contains("## \\(ui(\"待追问\", \"Follow-up Questions\"))")
    && !workspaceStoreSource.contains("## 核心要点\n        - ")
    && !workspaceStoreSource.contains("## 待追问\n        - ")
    && !workspaceStoreSource.contains("未命名材料"), "new note templates avoid fake source copy and empty bullets")
expect(workspaceStoreSource.contains("return cleanLegacyPlaceholder(notesByItemID[item.id] ?? defaultNote(for: item))")
    && workspaceStoreSource.contains("guard let markdown = String(data: data, encoding: .utf8)")
    && workspaceStoreSource.contains("noteBackingContentDigestsByItemID[item.id] = Self.noteContentDigest(data)")
    && workspaceStoreSource.contains("return cleanLegacyPlaceholder(markdown)")
    && workspaceStoreSource.contains("静默洞察|Agent 洞察")
    && workspaceStoreSource.contains("with: \"> [!note] 阅读线索\\n>\\n> $1\\n>\\n> 来源：$2\"")
    && workspaceStoreSource.contains(#"(?m)^> \[!note\] 阅读线索\n> ([^\n])"#)
    && workspaceStoreSource.contains(#"(?m)^> \[!quote\]([^\n]*)\n> ([^\n])"#)
    && workspaceStoreSource.contains(".replacingOccurrences(of: \"\\n* <br />\\n\", with: \"\\n\")")
    && workspaceStoreSource.contains(".replacingOccurrences(of: \"\\n- <br />\\n\", with: \"\\n\")"), "note loading cleans legacy empty-list placeholders")
expect(workspaceStoreSource.contains("已创建双链笔记：\\(url.lastPathComponent)") && !workspaceStoreSource.contains("已创建双链笔记：\\(url.path)") && !workspaceStoreSource.contains("无法创建双链笔记：\\(url.path)"), "wikilink note statuses avoid exposing full local paths")
expect(workspaceStoreSource.contains("private func revealRichWritingSurface()")
    && workspaceStoreSource.contains("layout = .immersiveWriting")
    && workspaceStoreSource.contains("showNotes = true")
    && workspaceStoreSource.contains("noteRenderMode = .rich"), "writing actions share one rich writing surface reveal")
expect(workspaceStoreSource.contains("func insertMarkdownSnippet(_ markdown: String) {\n        revealRichWritingSurface()")
    && workspaceStoreSource.contains("func useSelectedMarkdownAsNotebookNote()")
    && workspaceStoreSource.contains("revealRichWritingSurface()\n        focus(.notes)"), "markdown insertion and imported markdown notes reveal the rich writing surface")
expect(!workspaceStoreSource.contains("当前页提示"), "quiet insight avoids old page alert title")
expect(workspaceStoreSource.contains("阅读线索"), "quiet insight uses margin-note language")
expect(appSource.contains("if store.canCopyReference") && appSource.contains("if store.hasSelectedMaterial") && appSource.contains("Button(store.ui(\"打开资料内搜索\""), "app menu hides material-only actions when there is no material context")
expect(appSource.contains("Button(store.ui(\"新建空白笔记\"") && appSource.contains("{ animateLayout { store.promptCreateBlankNotebookNote() } }")
    && appSource.contains("Button(store.ui(\"从当前资料开笔记\"")
    && appSource.contains("animateLayout { store.promptCreateNotebookNoteFromCurrentMaterial() }"), "new-note menu commands use layout motion and expose blank/material paths separately")
expect(appSource.contains("Button(store.sendAgentActionTitle)") && workspaceStoreSource.contains("var sendAgentActionTitle: String"), "app send command uses one stable action label")
expect(appSource.contains("if store.isAskingAgent || !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty")
    && appSource.contains("store.isAskingAgent ? store.cancelAgentRequest() : store.askAgent()")
    && appSource.contains(".keyboardShortcut(.return, modifiers: [.command])"), "app menu hides the agent send action until a draft can really send")
expect(appSource.contains("Button(store.showLibrary ? store.ui(\"收起课程目录\"")
    && !appSource.contains("恢复资料")
    && appSource.contains("Button(store.showRightPane ? store.ui(\"收起辅助栏\""), "app menu names pane toggles by current state")
expect(appSource.contains("Button(store.ui(\"三栏工作台\", \"Three-Pane Workspace\"))")
    && !appSource.contains("Button(WorkspaceLayout.documentNotesAgent.label")
    && appSource.contains("Button(WorkspaceLayout.documentNotesSplit.label(language: store.interfaceLanguage))")
    && appSource.contains("Button(store.ui(\"交换笔记与对话\"")
    && appSource.contains("store.swapThreePaneSecondaryPanes()")
    && appSource.contains(".keyboardShortcut(\"s\", modifiers: [.command, .option])")
    && appSource.contains(".keyboardShortcut(\"2\", modifiers: [.command, .option])"), "app menu exposes one draggable three-pane workspace entry and gives split view the second layout shortcut")
expect(!appSource.contains("AgentSurface.bottomDrawer")
    && !appSource.contains("AgentSurface.cornerPanel")
    && !appSource.contains("AgentSurface.quietInsight")
    && appSource.contains("Button(AgentSurface.selectionFloat.actionLabel(language: store.interfaceLanguage))")
    && appSource.contains("if store.canUseSelectionAgentSurface")
    && AgentSurface.hidden.label(language: .chinese) == "隐藏对话"
    && AgentSurface.hidden.label(language: .english) == "Hide Chat"
    && AgentSurface.hidden.actionLabel(language: .english) == "Hide Chat"
    && !appSource.contains("Agent 底部抽屉")
    && !appSource.contains("Agent 右下角小窗")
    && !appSource.contains("Agent 划线浮层")
    && !appSource.contains("Agent 静默洞察"), "app menu uses the same user-facing agent surface labels as the command palette")
expect(appSource.contains("if store.layout.hasCollapsibleRightPane")
    && appSource.contains("if store.canApplyAgentAnswer")
    && appSource.contains("if store.canReplaceNoteSelection")
    && !appSource.contains(".disabled("), "app menu hides unavailable actions instead of showing disabled grey items")
expect(appSource.contains("Button(store.ui(\"聚焦课程目录\"")
    && appSource.contains("{ animateLayout { store.focus(.library) } }")
    && appSource.contains("Button(store.ui(\"聚焦对话\"")
    && appSource.contains("{ animateLayout { store.focus(.agent) } }")
    && !appSource.contains("Button(\"聚焦 Agent\")")
    && appSource.contains("Button(store.ui(\"下一份资料\"")
    && appSource.contains("{ animateLayout { store.selectAdjacentItem(step: 1) } }"), "app menu focus and material navigation use the same layout motion as shortcuts")
expect(appSource.contains("Button(store.ui(\"写入回答到笔记\"")
    && appSource.contains("{ animatePanel { store.applyLastAgentAnswerToNote() } }")
    && appSource.contains("Button(store.ui(\"替换笔记选区\"")
    && appSource.contains("{ animatePanel { store.replaceSelectionWithLastAgentAnswer() } }")
    && appSource.contains("Button(store.ui(\"追加整理建议\"")
    && appSource.contains("{ animatePanel { store.applyAgentPatchToEditor() } }")
    && !appSource.contains("用 Agent 替换笔记选区")
    && !appSource.contains("追加 Agent 整理建议"), "app menu agent write actions use the same panel motion as shortcuts")
let directPromptConsumers = [appSource, contentViewSource, sidebarSource, commandPaletteSource, notesAgentSource].joined(separator: "\n")
expect(!directPromptConsumers.contains("WeiBeiInputPrompt("), "views use the shared input prompt overlay instead of direct prompt layering")
expect(!workspaceStoreSource.contains("请解释我刚才选中的内容") && !notesAgentSource.contains("请解释我刚才选中的内容"), "agent entry does not invent a missing selection")
expect(!notesAgentSource.contains("compactHovering")
    && !notesAgentSource.contains("struct QuietInsightView")
    && !notesAgentSource.contains("忽略阅读线索")
    && !notesAgentSource.contains("收进摘录"), "quiet insight margin-note UI is removed with the quiet insight surface")
expect(notesAgentSource.contains("let itemID = store.activeNoteItemID") && notesAgentSource.contains("store.updateNote(value, for: itemID)"), "rich note editor writes through active note guard")
expect(notesAgentSource.components(separatedBy: "MarkdownPreviewView(").dropFirst().allSatisfy { $0.contains("appearanceMode: store.appearanceMode") }, "all markdown preview paths inherit the current appearance mode, including split compare")
expect(notesAgentSource.contains("case .split:")
    && notesAgentSource.contains("MarkdownPreviewView(\n                        markdown: draftNoteText")
    && notesAgentSource.contains("compact: true,\n                        fitsContentHeight: false")
    && notesAgentSource.contains("var fitsContentHeight = true")
    && notesAgentSource.contains("guard compact && fitsContentHeight else { return }")
    && notesAgentSource.contains(".frame(height: compact && fitsContentHeight ? max(contentHeight, Self.compactPreviewLoadingHeight) : nil)"), "split note compare uses compact preview typography without collapsing the preview pane height")
expect(notesAgentSource.contains("func weibeiPaneHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View")
    && notesAgentSource.contains("struct WeiBeiPaneHeader<Actions: View>: View")
    && notesAgentSource.contains("var title: String")
    && notesAgentSource.contains("var latinMark: String? = nil")
    && notesAgentSource.contains("var subtitle: String")
    && notesAgentSource.contains("var reorderRole: WorkspacePaneRole? = nil")
    && notesAgentSource.contains("HStack(alignment: .firstTextBaseline, spacing: 8)")
    && notesAgentSource.contains("Text(title)")
    && notesAgentSource.contains("Text(subtitle)")
    && !notesAgentSource.contains("VStack(alignment: .leading, spacing: 2) {\n                Text(title)")
    && notesAgentSource.contains("WeiBeiHeaderHandoffFade(height: 28, opacity: 0.34)")
    && notesAgentSource.contains("func weibeiHeaderAccessoryGroup() -> some View")
    && noteModeControlSource.contains(".weibeiHeaderAccessoryGroup()")
    && !agentPaneHeaderSource.contains(".weibeiHeaderAccessoryGroup()")
    && !notesAgentSource.contains("private var hasAgentHeaderActions: Bool")
    && notesAgentSource.contains(".background(WeiBeiGlassHeaderBackground(paperOpacity: 0.72, materialOpacity: 0.12))")
    && !notesAgentSource.contains(".animation(WeiBeiMotion.appearance, value: appearanceMode)")
    && notesAgentSource.components(separatedBy: ".weibeiPaneHeaderChrome(appearanceMode: appearanceMode)").count >= 2
    && notePaneHeaderSource.contains("title: store.ui(\"笔记\"")
    && agentPaneHeaderSource.contains("title: store.ui(\"对话\"")
    && notePaneHeaderSource.contains("latinMark: store.interfaceLanguage == .chinese ? \"NOTES\" : nil")
    && agentPaneHeaderSource.contains("latinMark: store.interfaceLanguage == .chinese ? \"CHAT\" : nil")
    && agentPaneHeaderSource.contains("subtitle: store.agentConversationSubtitle")
    && notePaneHeaderSource.contains("private var noteHeaderSubtitle: String")
    && notePaneHeaderSource.contains("Menu {")
    && notePaneHeaderSource.contains("store.ui(\"空白课程笔记\"")
    && notePaneHeaderSource.contains("store.ui(\"当前资料笔记\"")
    && notePaneHeaderSource.contains("if store.hasSelectedMaterial")
    && !notePaneHeaderSource.contains("if !isImmersiveWriting")
    && !notesAgentSource.contains("private var isImmersiveWriting")
    && notePaneHeaderSource.contains("store.promptCreateNotebookNoteFromCurrentMaterial()")
    && notePaneHeaderSource.contains("store.promptCreateBlankNotebookNote()")
    && !notePaneHeaderSource.contains("store.createNotebookNoteFromCurrentMaterial()")
    && !notePaneHeaderSource.contains("store.createBlankNotebookNote()")
    && notePaneHeaderSource.contains(".accessibilityLabel(Text(store.ui(\"新建课程笔记\"")
    && notePaneHeaderSource.contains(".accessibilityLabel(Text(store.ui(\"新建空白课程笔记\"")
    && notePaneHeaderSource.contains("Image(systemName: \"doc.badge.plus\")")
    && notePaneHeaderSource.contains(".buttonStyle(WeiBeiIconButtonStyle(size: 24))")
    && notePaneHeaderSource.contains("private var noteHeader: some View")
    && notePaneHeaderSource.contains("if let draft = store.notebookCreationDraft")
    && notePaneHeaderSource.contains(".weibeiPaneHeaderChrome(appearanceMode: store.appearanceMode)")
    && notePaneHeaderSource.contains(".modifier(PaneHeaderReorderModifier(role: reorderRole))")
    && notePaneHeaderSource.contains("private var newNoteControl: some View")
    && !notePaneHeaderSource.contains(".frame(width: 560, height: 42)")
    && notePaneHeaderSource.contains(".frame(width: 420, height: 34)")
    && notebookCreationPanelSource.contains("private var canCreate: Bool")
    && notebookCreationPanelSource.contains("store.ui(\"新建笔记\"")
    && notebookCreationPanelSource.contains("Image(systemName: \"checkmark\")")
    && notebookCreationPanelSource.contains("@State private var hoveredConfirm")
    && notebookCreationPanelSource.contains(".foregroundStyle(confirmColor)")
    && notebookCreationPanelSource.contains("return hoveredConfirm ? WeiBeiTheme.onCinnabar : WeiBeiTheme.secondaryInk")
    && notebookCreationPanelSource.contains("private var confirmBackground: Color")
    && notebookCreationPanelSource.contains("return WeiBeiTheme.cinnabar.opacity(0.88)")
    && notebookCreationPanelSource.contains("private var cancelBackground: Color")
    && notebookCreationPanelSource.contains("hoveredCancel ? WeiBeiTheme.cinnabarSoft.opacity(0.68) : Color.clear")
    && notebookCreationPanelSource.contains("withAnimation(WeiBeiMotion.hover)")
    && notebookCreationPanelSource.contains(".frame(height: 30)")
    && notebookCreationPanelSource.contains("WeiBeiTheme.paperInset.opacity(0.24)")
    && notebookCreationPanelSource.contains("WeiBeiTheme.hairline.opacity(0.34)")
    && !notebookCreationPanelSource.contains("Rectangle()\n                .fill(WeiBeiTheme.cinnabar")
    && !notebookCreationPanelSource.contains(".weibeiHeaderAccessoryGroup()")
    && notesAgentSource.contains("store.confirmNotebookNoteCreation()")
    && notesAgentSource.contains("store.cancelNotebookNoteCreation()")
    && !notesAgentSource.contains(".alert(")
    && !notesAgentSource.contains("NSAlert()")
    && !notesAgentSource.contains("store.ui(\"先命名，再创建本地 Markdown\"")
    && !notesAgentSource.contains("store.ui(\"资料笔记名称\"")
    && !notePaneHeaderSource.contains(".transition(WeiBeiTransition.message)")
    && !notePaneHeaderSource.contains(".padding(.top, 50)")
    && notePaneHeaderSource.contains(".transition(WeiBeiTransition.floating)")
    && !notesAgentSource.contains("NSAlert()")
    && !notePaneHeaderSource.contains("NoteCreateMenuLabel")
    && !notePaneHeaderSource.contains("Button(\"作为笔记编辑\")")
    && agentPaneHeaderSource.contains("sessionMenu")
    && notesAgentSource.contains("private var sessionMenu: some View")
    && notesAgentSource.contains("store.createStudySession()")
    && notesAgentSource.contains("store.activateStudySession(session.id)")
    && notesAgentSource.contains("store.clearCurrentSessionInferredMemory()")
    && !agentPaneHeaderSource.contains("agentToolButton(")
    && !notesAgentSource.contains("private func agentToolButton")
    && notesAgentSource.contains("Button(store.agentWriteActionTitle)")
    && notesAgentSource.contains("Button(store.ui(\"替换\", \"Replace\"")
    && !notesAgentSource.contains(".labelStyle(.titleAndIcon)\n        }\n        .buttonStyle(WeiBeiTextActionButtonStyle())")
    && notePaneHeaderSource.contains(".background(WeiBeiTheme.paper)")
    && !notePaneHeaderSource.contains("mode.id != NoteRenderMode.visibleCases.last?.id"), "note pane creation and agent header stay custom, light, and context-only")
expect(noteModeControlSource.contains("NoteRenderMode.visibleCases")
    && notePaneHeaderSource.contains("@State private var hoveredNoteMode: NoteRenderMode?")
    && noteModeControlSource.contains("HStack(spacing: 3)")
    && !noteModeControlSource.contains("ViewThatFits(in: .horizontal)")
    && !noteModeControlSource.contains("noteModeButtonRail")
    && noteModeControlSource.contains("Image(systemName: noteModeIcon(for: mode))")
    && noteModeControlSource.contains("return Image(systemName: noteModeIcon(for: mode))")
    && noteModeControlSource.contains(".accessibilityLabel(Text(label))")
    && noteModeControlSource.contains("private func noteModeIcon(for mode: NoteRenderMode) -> String")
    && noteModeControlSource.contains(".fixedSize(horizontal: true, vertical: false)")
    && noteModeControlSource.contains("hoveredNoteMode == mode")
    && noteModeControlSource.contains("hoveredNoteMode = hovering ? mode")
    && !noteModeControlSource.contains("Image(systemName: noteModeSystemImage(for: mode))")
    && !notesAgentSource.contains("private func noteModeSystemImage(for mode: NoteRenderMode) -> String")
    && noteModeControlSource.contains("selected ? WeiBeiTheme.cinnabar : hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk")
    && !noteModeControlSource.contains("Capsule()")
    && noteModeControlSource.contains("noteModeButtonFill(selected: selected, hovering: hovering)")
    && noteModeControlSource.contains("noteModeButtonStroke(selected: selected, hovering: hovering)")
    && noteModeControlSource.contains("WeiBeiTheme.cinnabarSoft.opacity(store.appearanceMode.isDark ? 0.44 : 0.62)")
    && noteModeControlSource.contains("WeiBeiTheme.paperRaised.opacity(store.appearanceMode.isDark ? 0.16 : 0.20)")
    && noteModeControlSource.contains(".weibeiHeaderAccessoryGroup()")
    && noteModeControlSource.contains(".scaleEffect(hovering && !selected ? 1.012 : 1)")
    && !noteModeControlSource.contains(".stroke(WeiBeiTheme.hairline.opacity(0.14), lineWidth: 1)"), "note mode control is icon-only so narrow panes never collapse labels into ellipses")
expect(!notesAgentSource.contains(".id(store.noteRenderMode)"), "note mode changes avoid forced hard view identity resets")
expect(!notesAgentSource.contains(".id(expanded)"), "selection agent expands without forcing a hard view identity reset")
expect(!contentViewSource.contains("ContextRailView(title: store.ui(\"文档\"")
    && !contentViewSource.contains("ContextRailView(title: store.ui(\"写作辅助\""), "immersive writing has no permanent side rails")
expect(notesAgentSource.contains("LinkedSourcesControl()")
    && notesAgentSource.contains("private var writingAssistControl: some View")
    && notesAgentSource.contains("if store.layout != .immersiveWriting")
    && notesAgentSource.contains(".accessibilityLabel(Text(store.ui(\"整理当前笔记\""), "note relationships and writing aids live in accessible, on-demand header actions")
expect(contentViewSource.contains("@StateObject private var paneHostRegistry = PersistentPaneHostRegistry()")
    && contentViewSource.contains("final class PersistentPaneHostRegistry: ObservableObject")
    && contentViewSource.contains("struct PersistentPaneHost: NSViewRepresentable")
    && contentViewSource.contains("final class PersistentPaneContainerView: NSView")
    && contentViewSource.contains("private final class PaneContentHostingView: NSHostingView<AnyView>")
    && contentViewSource.contains("PaneContentHostingView(rootView: AnyView(root))")
    && contentViewSource.contains("override var mouseDownCanMoveWindow: Bool { false }")
    && contentViewSource.contains("override func viewDidMoveToWindow()")
    && contentViewSource.contains("guard container.window != nil else")
    && contentViewSource.contains("PersistentPaneHost(role: .reader, registry: paneHostRegistry)")
    && contentViewSource.contains("PersistentPaneHost(role: .agent, registry: paneHostRegistry)")
    && contentViewSource.contains("PersistentPaneHost(role: .notes, registry: paneHostRegistry)")
    && contentViewSource.contains("host.removeFromSuperview()")
    && contentViewSource.contains("host.autoresizingMask = [.width, .height]")
    && contentViewSource.contains("struct OwnerToken: Equatable")
    && contentViewSource.contains("func registerOwner(for role: WorkspacePaneRole) -> OwnerToken")
    && contentViewSource.contains("guard latestOwnerGeneration[role] == owner.generation else { return }")
    && contentViewSource.contains("guard activeOwners[role] == owner, host.superview === container else { return }")
    && !contentViewSource.contains("paneView(for: drag.role, reorderable: false)"), "core pane hosts survive immersive, single-pane, and split-layout changes instead of recreating their reader or editor state")
expect(contentViewSource.contains("case .documentAgentNotes, .documentNotesAgent:")
    || contentViewSource.contains("case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:"), "ordinary document layouts share one routing branch")
expect(contentViewSource.contains("documentPaneLayoutView()")
    && contentViewSource.contains("StableDocumentWorkspace(")
    && contentViewSource.contains("ThreePaneWorkspaceChrome(")
    && contentViewSource.contains("PaneReorderPreviewView(role: drag.role)")
    && contentViewSource.contains(".opacity(0.11)")
    && contentViewSource.contains("appearanceMode: store.appearanceMode")
    && stableDocumentSource.contains("PersistentPaneHost(role: role, registry: registry)")
    && contentViewSource.contains("private struct PersistentPaneRoot: View")
    && contentViewSource.contains("AgentPaneView(showsPaneHeader: false, reorderRole: reorderRole)")
    && contentViewSource.contains("NotePaneView(showsPaneHeader: false, reorderRole: reorderRole)")
    && !contentViewSource.contains("PaneReorderGhostView")
    && contentViewSource.contains("PaneDropTargetView(role: visibleOrder[targetIndex])")
    && contentViewSource.contains("threePaneReorderOverlay")
    && contentViewSource.contains("private func documentPaneLayoutView() -> some View")
    && contentViewSource.contains("let order = store.visibleDocumentPaneOrder")
    && stableDocumentSource.contains("EmptyWorkspaceLauncherView()")
    && !contentViewSource.contains("documentTwoPaneView(order: order)")
    && !contentViewSource.contains("documentThreePaneView(order: Array(order.prefix(3)))")
    && contentViewSource.contains("let fallbackFrames = estimatedDocumentPaneFrames(order: order, size: geometry.size)")
    && contentViewSource.contains("store.threePaneReorderFrameList(order: order, fallback: fallbackFrames)")
    && contentViewSource.contains("onFramesChange: { reportedOrder, frames in")
    && stableDocumentSource.contains("self?.onFramesChange?(order, frames)")
    && !contentViewSource.contains("case .documentAgentNotes:\n                if store.showRightPane"), "document pane layouts render from the visible pane set and one draggable pane role order")
expect(paneHeaderReorderSource.contains("struct PaneHeaderReorderModifier")
    && paneHeaderReorderSource.contains(".textSelection(.disabled)")
    && paneHeaderReorderSource.contains(".highPriorityGesture(")
    && paneHeaderReorderSource.contains("DragGesture(minimumDistance: 12, coordinateSpace: .global)")
    && paneHeaderReorderSource.contains("@State private var hovering = false")
    && !paneHeaderReorderSource.contains("@State private var dragOffset")
    && !paneHeaderReorderSource.contains(".offset(x: dragOffset)")
    && paneHeaderReorderSource.contains(".offset(y: hovering || dragActive ? -1 : 0)")
    && paneHeaderReorderSource.contains(".scaleEffect(dragActive ? 1.01 : hovering ? 1.004 : 1, anchor: .top)")
    && !paneHeaderReorderSource.contains("Rectangle()\n                            .stroke(WeiBeiTheme.cinnabar.opacity")
    && paneHeaderReorderSource.contains("NSCursor.openHand.push()")
    && paneHeaderReorderSource.contains(".onHover { value in")
    && paneHeaderReorderSource.contains("store.beginThreePaneReorder(role)")
    && paneHeaderReorderSource.contains("store.updateThreePaneReorder(role, horizontalDelta: value.translation.width)")
    && paneHeaderReorderSource.contains("store.finishThreePaneReorder(role, horizontalDelta: value.translation.width)")
    && !paneHeaderReorderSource.contains(".help(store.ui(\"拖动标题栏重排三栏\"")
    && readerViewSource.contains(".modifier(PaneHeaderReorderModifier(role: reorderRole))")
    && notesAgentSource.contains("reorderRole: reorderRole"), "floating pane title slips act as handles while the full pane reorder ghost is rendered by the workspace")
expect(!readerViewSource.contains("struct ReaderPaneView")
    && readerViewSource.contains("struct ImmersiveHoverTitleView")
    && readerViewSource.contains("var reorderRole: WorkspacePaneRole?")
    && readerViewSource.contains("WeiBeiTypography.englishBrandFont(size: 9.8")
    && readerViewSource.contains(".baselineOffset(0.7)")
    && readerViewSource.contains("ViewThatFits(in: .horizontal)")
    && readerViewSource.contains(".fixedSize(horizontal: true, vertical: false)")
    && readerViewSource.contains(".truncationMode(.tail)")
    && readerViewSource.contains(".frame(maxWidth: .infinity)")
    && readerViewSource.contains(".frame(maxWidth: actionsAlignedTrailing ? .infinity : nil, alignment: .leading)")
    && readerViewSource.contains(".padding(.horizontal, actionsAlignedTrailing ? 14 : 0)")
    && readerViewSource.contains("mark: \"DOC\"")
    && readerViewSource.contains("title: floatingTitle")
    && readerViewSource.contains("reorderRole: floatingTitleReorderRole")
    && readerViewSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)")
    && contentViewSource.contains("isImmersive: store.layout == .immersiveReading")
    && contentViewSource.contains("case .immersiveConversation:\n                PersistentPaneHost(role: .agent, registry: paneHostRegistry)")
    && !contentViewSource.contains("case .immersiveConversation:\n                if store.showRightPane")
    && contentViewSource.contains("PersistentPaneHost(role: .reader, registry: paneHostRegistry)")
    && contentViewSource.contains("PersistentPaneHost(role: .notes, registry: paneHostRegistry)")
    && notesAgentSource.contains("mark: \"CHAT\"")
    && notesAgentSource.contains("title: store.agentConversationSubtitle")
    && notesAgentSource.contains("agentSessionCatalogMenu")
    && notesAgentSource.contains("reorderRole: reorderRole")
    && notesAgentSource.contains("mark: \"NOTES\"")
    && notesAgentSource.contains("title: noteHeaderSubtitle")
    && notesAgentSource.contains("actionsAlignedTrailing: true")
    && notesAgentSource.contains("noteModeControl")
    && notesAgentSource.contains("newNoteControl")
    && notesAgentSource.contains("isPinned: store.notebookCreationDraft != nil")
    && notesAgentSource.contains("notebookCreationPanel(draft: draft)"), "immersive and single-pane views hide heavy pane headers while the Notes hover slip keeps mode and new-note actions")
expect(workspaceStoreSource.contains("@Published var threePaneOrder")
    && workspaceStoreSource.contains("final class ThreePaneReorderState: ObservableObject")
    && workspaceStoreSource.contains("let threePaneReorder = ThreePaneReorderState()")
    && workspaceStoreSource.contains("var threePaneReorderDrag: ThreePaneReorderDrag?")
    && workspaceStoreSource.contains("func threePaneReorderFrameList(order: [WorkspacePaneRole], fallback: [CGRect]) -> [CGRect]")
    && workspaceStoreSource.contains("private func sameReorderFrames")
    && workspaceStoreSource.contains("func swapThreePaneRoles")
    && workspaceStoreSource.contains("func swapThreePaneSecondaryPanes")
    && workspaceStoreSource.contains("func moveThreePaneRole")
    && workspaceStoreSource.contains("func beginThreePaneReorder")
    && workspaceStoreSource.contains("func updateThreePaneReorderFrames")
    && workspaceStoreSource.contains("func updateThreePaneReorder")
    && workspaceStoreSource.contains("func finishThreePaneReorder")
    && workspaceStoreSource.contains("ThreePaneReorderTargeting.targetIndex(")
    && workspaceStoreSource.contains("frames: threePaneReorderFrames")
    && !workspaceStoreSource.contains("contains(CGPoint(x: draggedCenterX")
    && !workspaceStoreSource.contains("let threshold: CGFloat = 84")
    && workspaceStoreSource.contains("private func threePaneReorderTargetIndex")
    && workspaceStoreSource.contains("private func applyThreePaneOrder")
    && !workspaceStoreSource.contains("guard dragged != .reader, target != .reader else { return }")
    && !workspaceStoreSource.contains("guard role != .reader else { return }")
    && workspaceStoreSource.contains("layoutMatchingThreePaneOrder")
    && workspaceStoreSource.contains("threePaneOrder: normalizedThreePaneOrder"), "workspace store owns, drags, swaps, and persists custom three-pane order")
expect(!contentViewSource.contains("ContextRailItem")
    && (contentViewSource.contains("topIconButton(\"sidebar.left\"")
        || contentViewSource.contains("\"sidebar.left\""))
    && contentViewSource.contains("store.toggleLibrary()")
    && workspaceStoreSource.contains("func revealLibrary()"), "immersive surfaces do not duplicate the library because the top bar owns its entry")
expect(!appSource.contains("沉浸模式也保留课程目录入口")
    && !appSource.contains("Immersive modes keep the course index entry")
    && !appSource.contains("Button(store.showLibrary ? store.ui(\"收起\", \"Hide\") : store.ui(\"打开\", \"Show\"))"), "settings does not duplicate the top bar course index toggle")
expect(notesAgentSource.contains("store.ui(\"大纲建议\"")
    && notesAgentSource.contains("store.ui(\"补来源\"")
    && notesAgentSource.contains("store.ui(\"润色表达\"")
    && !notesAgentSource.contains("help: \"用 Agent")
    && !notesAgentSource.contains("help: \"让 Agent"), "on-demand writing tools use direct task language instead of internal agent wording")
expect(notesAgentSource.contains("store.agentPromptScope")
    && notesAgentSource.contains("store.hasSelectedMaterial")
    && notesAgentSource.contains("请检查当前笔记缺少来源的位置，并标出需要补证据的段落。"), "on-demand writing tools reuse real context wording")
expect(!contentViewSource.contains("agentOverlay")
    && !contentViewSource.contains("agentAlignment")
    && !contentViewSource.contains("QuietInsightView"), "immersive layouts no longer mount deleted lightweight agent overlays")
expect(!contentViewSource.contains("来源预览"), "immersive writing avoids duplicate reader entries")
expect(!contentViewSource.contains("title: store.selectedItem?.title ?? \"当前材料\""), "immersive writing avoids fake current material entries")
expect(!notesAgentSource.contains("Agent 抽屉"), "agent drawer avoids engineering labels")
expect(!notesAgentSource.contains("Agent 只在右下角待命"), "corner agent avoids explanatory placeholder copy")
expect(!notesAgentSource.contains("魏碑会优先读取材料"), "agent empty state avoids product-explainer copy")
expect(!notesAgentSource.contains("Text(\"当前上下文\")") && !notesAgentSource.contains("contextLine("), "agent empty state avoids diagnostic context rows")
expect(notesAgentSource.contains("private struct AgentSelectionAttachmentPill")
    && notesAgentSource.contains("Image(systemName: \"text.bubble\")")
    && notesAgentSource.contains("Text(store.ui(\"\\(store.selectionAttachments.count) 个已选文本片段\"")
    && notesAgentSource.contains("\"\\(store.selectionAttachments.count) selected text fragments\"")
    && notesAgentSource.contains("store.ui(\"清空已选文本片段\"")
    && notesAgentSource.contains(".popover(isPresented: popoverPresented, arrowEdge: .bottom)")
    && notesAgentSource.contains("store.clearSelectionAttachments()")
    && notesAgentSource.contains("store.ui(\"清空\", \"Clear\")")
    && notesAgentSource.contains("ForEach(Array(store.selectionAttachments.enumerated()), id: \\.element.id)")
    && notesAgentSource.contains("store.removeSelectionAttachment(id: selection.id)")
    && notesAgentSource.contains("Image(systemName: \"xmark\")")
    && notesAgentSource.contains(".buttonStyle(WeiBeiIconButtonStyle(size: 20))")
    && notesAgentSource.contains("selectionAttachmentRow(index: index, selection: selection)")
    && notesAgentSource.components(separatedBy: "AgentSelectionAttachmentPill()").count >= 2
    && !notesAgentSource.contains("Text(\"1 个已选文本片段\")")
    && !notesAgentSource.contains("Text(\"已含选区\")"), "agent selection context renders as a hoverable attachment pill near composers instead of text inside the empty state")
if let attachmentRowStart = notesAgentSource.range(of: "private func selectionAttachmentRow")?.lowerBound,
   let attachmentHoverStart = notesAgentSource[attachmentRowStart...].range(of: "private func setPillHovering")?.lowerBound {
    let attachmentRowSource = String(notesAgentSource[attachmentRowStart..<attachmentHoverStart])
    expect(attachmentRowSource.contains("Text(selection.text)")
        && attachmentRowSource.contains(".allowsHitTesting(false)")
        && !attachmentRowSource.contains(".textSelection(.enabled)"), "selected text attachment popover previews do not trap scroll or text drag events")
} else {
    expect(false, "selected text attachment row source is inspectable")
}
if let noteBridgeStart = notesAgentSource.range(of: "onAskAgentWithSelection: { text, anchor in")?.lowerBound,
   let wikiLinkStart = notesAgentSource[noteBridgeStart...].range(of: "}, onWikiLink:")?.lowerBound {
    let noteSelectionBridgeSource = String(notesAgentSource[noteBridgeStart..<wikiLinkStart])
    expect(noteSelectionBridgeSource.contains("store.updateSelection(text, source: .note, anchor: anchor)")
        && noteSelectionBridgeSource.contains("store.askSelection()")
        && !noteSelectionBridgeSource.contains("askAgent()"), "rich markdown selection ask action attaches the selection without auto-sending a generated prompt")
} else {
    expect(false, "rich markdown selection ask bridge is inspectable")
}
expect(!emptyAgentStateSource.isEmpty
    && !emptyAgentStateSource.contains("noteContextTitle")
    && !emptyAgentStateSource.contains("Text(store.selectedMaterialItem?.title ?? \"当前笔记\")")
    && !emptyAgentStateSource.contains(".fill(WeiBeiTheme.cinnabar.opacity(0.34))"), "agent empty state avoids a repeated title card and heavy cinnabar rule")
expect(notesAgentSource.contains("AgentStarterChip") && notesAgentSource.contains("hovering ? -1 : 0"), "agent starter chips keep subtle hover motion")
expect(notesAgentSource.contains("if store.hasSelectedMaterial")
    && notesAgentSource.contains("starterChip(store.ui(\"梳理\", \"Outline\"")
    && notesAgentSource.contains("help: store.ui(\"梳理当前材料\", \"Outline current material\"")
    && notesAgentSource.contains("starterChip(store.ui(\"出题\", \"Quiz\"")
    && notesAgentSource.contains("help: store.ui(\"生成复习题\", \"Generate review questions\"")
    && !notesAgentSource.contains("starterChip(\"梳理材料\"")
    && !notesAgentSource.contains("starterChip(\"出复习题\""), "agent starter chips hide material actions without a selected material and avoid clipped long labels")
expect(notesAgentSource.contains("let availableWidth = max(agentPaneWidth, 1)")
    && notesAgentSource.contains("private enum AgentChatLayoutMetrics")
    && notesAgentSource.contains("static let wideMaxWidth: CGFloat = 920")
    && notesAgentSource.contains("static let compactMaxWidth: CGFloat = 560")
    && notesAgentSource.contains("AgentChatLayoutMetrics.contentWidth(")
    && notesAgentSource.contains("isImmersiveConversation")
    && notesAgentSource.contains("agentMessageRow(")
    && notesAgentSource.contains("geometryWidth: geometryWidth")
    && notesAgentSource.contains("private func agentMessageRow(")
    && notesAgentSource.contains(".padding(.top, store.messages.isEmpty ? 22 : 0)")
    && notesAgentSource.contains(".frame(maxWidth: .infinity, alignment: .topLeading)")
    && notesAgentSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)")
    && notesAgentSource.contains("AgentPaneWidthKey")
    && !notesAgentSource.contains("GeometryReader { paneGeometry in")
    && !notesAgentSource.contains(".frame(minHeight: geometry.size.height, alignment: .topLeading)")
    && !notesAgentSource.contains(".frame(width: geometry.size.width, alignment: .topLeading)")
    && !notesAgentSource.contains("alignment: store.messages.isEmpty ? .bottomLeading : .topLeading"), "agent empty state starts in the content area; scroll content avoids GeometryReader parent thrash")
expect(notesAgentSource.contains(".clipped()\n                    .zIndex(0)")
    && notesAgentSource.contains("agentInputTray(wide: wide, contentWidth: contentWidth)\n                        .zIndex(1)")
    && notesAgentSource.contains("AgentPaneWidthKey")
    && notesAgentSource.contains("NEVER put GeometryReader as an ancestor of ScrollView+LazyVStack"), "agent conversation clips long rich answers above the composer; pane width is background-probed without GeometryReader thrash")
expect(notesAgentSource.contains("canPolishNoteSelection") && notesAgentSource.contains("store.selectionContext?.isNoteSelection == true"), "selection agent only shows polish for note selections")
expect(notesAgentSource.contains("AgentThinkingIndicator()")
    && notesAgentSource.contains("selection-float-thinking")
    && notesAgentSource.contains("Same order as immersive chat")
    && notesAgentSource.contains("WorkspaceStore.isAgentFailureMessage(message.text)")
    && notesAgentSource.contains("floatResizeHandle")
    && notesAgentSource.contains("SelectionFloatingAgentPlacement.expandedHalfWidth * 2")
    && notesAgentSource.contains("isError ? WeiBeiTheme.cinnabar : WeiBeiTheme.cinnabar.opacity(0.76)")
    && notesAgentSource.contains(".foregroundStyle(WeiBeiTheme.cinnabar)")
    && !notesAgentSource.contains("if message.role == .user || message.text.hasPrefix(\"Agent 请求失败：\")"), "selection floating agent mirrors immersive order/thinking, stays resizable, and reserves cinnabar for real failures")
expect(notesAgentSource.contains("private var isCredentialNotice: Bool")
    && notesAgentSource.contains("message.text.hasPrefix(\"未配置密钥\")")
    && notesAgentSource.contains("message.text.hasPrefix(\"未配置 OPENAI_API_KEY\")")
    && notesAgentSource.contains("message.text.hasPrefix(\"No key is configured\")")
    && notesAgentSource.contains("isOfflineContextPreview")
    && notesAgentSource.contains("return message.text")
    && notesAgentSource.contains("Text(store.ui(\"需要设置密钥\", \"Key Required\"))")
    && notesAgentSource.contains("let scope = store.hasSelectionAttachments ? store.ui(\"\\(store.agentPromptScope)、已选文本片段\"")
    && notesAgentSource.contains("store.ui(\"设置后会结合\\(scope)作答；未配置时不会编造内容。\"")
    && notesAgentSource.contains("private var assistantTurn: some View")
    && notesAgentSource.contains("AgentMessageMarkdownText(")
    && notesAgentSource.contains("rendersRichMarkdown: false")
    && notesAgentSource.contains("rendersRichMarkdown: true")
    && notesAgentSource.contains(".background(WeiBeiTheme.paper)")
    && notesAgentSource.contains("// Same opaque paper as notes/reader")
    && notesAgentSource.contains("paperOpacity: showsPaneHeader ? 0.34 : 0.14")
    // Hang-proof agent chat: finalized KaTeX with frozen height; streaming stays native.
    && notesAgentSource.contains("usesFinalizedKaTeX")
    && notesAgentSource.contains("freezeHeightAfterMeasure")
    && notesAgentSource.contains("AgentFinalizedMarkdownHeightCache")
    && notesAgentSource.contains("agentChatLayoutWidth")
    && notesAgentSource.contains("AttributedString(markdown: display")
    && notesAgentSource.contains("RichAnswerDisplayText.normalizedInlineMath")
    && notesAgentSource.contains("AgentStreamingMarkdownText")
    && notesAgentSource.contains(".allowsHitTesting(false)")
    && !notesAgentSource.contains("onContentHeightChange: onMarkdownHeightChange")
    && !notesAgentSource.contains("scrollTargetLayout()")
    && !notesAgentSource.contains("scrollPosition(id: $visibleAgentMessageID")
    && notesAgentSource.contains(".contentShape(Rectangle())")
    && notesAgentSource.contains("private var messageMetadata: some View")
    && notesAgentSource.contains("Text(\"WeiBei\")")
    && notesAgentSource.contains("rendersRichMarkdown: true")
    && notesAgentSource.contains("WeiBeiTheme.link.opacity(hovering ? 0.50 : 0.34)")
    && !notesAgentSource.contains("assistantMarkColor")
    && !notesAgentSource.contains("return isCredentialNotice ? store.ui(\"需要设置密钥\", \"Key Required\") : store.appDisplayName")
    && !notesAgentSource.contains("WeiBeiTheme.paperRaised.opacity(hovering ? 0.14 : 0.0)")
    && !notesAgentSource.contains(".frame(maxWidth: bubbleMaxWidth, alignment: .leading)")
    && !notesAgentSource.contains("private var bubbleFill")
    && !notesAgentSource.contains("RoundedRectangle(cornerRadius: 11)")
    && !notesAgentSource.contains(".fill(WeiBeiTheme.paperRaised.opacity(store.appearanceMode == .inkstone ? 0.28 : 0.76))")
    && notesAgentSource.contains("private var userBubbleFill: Color")
    && notesAgentSource.contains("private var userBubbleStroke: Color")
    && notesAgentSource.contains("RoundedRectangle(cornerRadius: 9, style: .continuous)")
    && notesAgentSource.contains("strokeBorder(userBubbleStroke, lineWidth: 1)"), "main agent conversation keeps assistant text open without a cinnabar mark while user turns use a quiet paper bubble")
if let userTurnStart = notesAgentSource.range(of: "private var userTurn: some View")?.lowerBound,
   let assistantTurnStart = notesAgentSource[userTurnStart...].range(of: "private var assistantTurn: some View")?.lowerBound {
    let userTurnSource = String(notesAgentSource[userTurnStart..<assistantTurnStart])
    expect(userTurnSource.contains(".frame(maxWidth: .infinity, alignment: .trailing)")
        && userTurnSource.contains("userBubbleFill")
        && userTurnSource.contains("AgentMessageMarkdownText(")
        && !userTurnSource.contains("store.ui(\"你\", \"You\")")
        && !userTurnSource.contains("Capsule()")
        && !userTurnSource.contains(".padding(.leading, 96)")
        && !userTurnSource.contains("Spacer(minLength: 42)"), "agent user messages hug a paper bubble on the right edge without speaker labels or accent rails")
} else {
    expect(false, "agent user message source is inspectable")
}
if let credentialStart = notesAgentSource.range(of: "private var credentialNoticeContent")?.lowerBound,
   let isUserStart = notesAgentSource[credentialStart...].range(of: "private var isUser")?.lowerBound {
    let credentialSource = String(notesAgentSource[credentialStart..<isUserStart])
    expect(credentialSource.contains("Text(displayText)")
        && credentialSource.contains(".allowsHitTesting(false)")
        && !credentialSource.contains(".textSelection(.enabled)"), "agent credential notice text lets wheel events pass to the conversation scroll")
} else {
    expect(false, "agent credential notice source is inspectable")
}
if let messageTextStart = notesAgentSource.range(of: "private struct AgentMessageMarkdownText")?.lowerBound,
   let thinkingStart = notesAgentSource[messageTextStart...].range(of: "private struct AgentThinkingIndicator")?.lowerBound {
    let messageTextSource = String(notesAgentSource[messageTextStart..<thinkingStart])
    expect(messageTextSource.contains("usesFinalizedKaTeX")
        && messageTextSource.contains("MarkdownPreviewView(")
        && messageTextSource.contains("freezeHeightAfterMeasure: true")
        && messageTextSource.contains("layoutWidthBucket")
        && messageTextSource.contains("AgentChatKaTeXMarkdown")
        && messageTextSource.contains("NEVER wire onContentHeightChange to scrollAgentToBottom")
        && messageTextSource.contains("AttributedString(markdown:")
        && messageTextSource.contains("RichAnswerDisplayText.normalizedInlineMath")
        && messageTextSource.contains(".textSelection(.enabled)")
        && !messageTextSource.contains("onContentHeightChange: onMarkdownHeightChange"), "agent chat uses finalized KaTeX with width-aware height and selectable native text")
} else {
    expect(false, "agent message text source is inspectable")
}
// WP9: 行文进行中 V3 loading motion — no three-dot pulse card; hang-proof AppKit orbit.
if let thinkingStart = notesAgentSource.range(of: "private struct AgentThinkingIndicator")?.lowerBound,
   let streamingStart = notesAgentSource[thinkingStart...].range(of: "private struct AgentStreamingResponse")?.lowerBound {
    let thinkingSource = String(notesAgentSource[thinkingStart..<streamingStart])
    expect(!thinkingSource.contains("ForEach(0..<3")
        && !thinkingSource.contains("repeatForever")
        && !thinkingSource.contains("AgentThinkingInkDots")
        && !thinkingSource.contains("pulse = true"), "AgentThinkingIndicator no longer uses a three-dot pulse implementation")
    expect(!thinkingSource.contains("RoundedRectangle(cornerRadius: 7)")
        && !thinkingSource.contains("paperRaised.opacity(0.34)")
        && !thinkingSource.contains(".clipShape(RoundedRectangle"), "AgentThinkingIndicator has no loading-card chrome (fill/stroke/rounded rect)")
    // Hang-proof contract: AppKit CADisplayLink host only setNeedsDisplay; never TimelineView inside ScrollView.
    expect(thinkingSource.contains("accessibilityReduceMotion")
        && thinkingSource.contains("TextOrbitSegment")
        && thinkingSource.contains("TextOrbitPath")
        && thinkingSource.contains("NSViewRepresentable")
        && thinkingSource.contains("CADisplayLink")
        && thinkingSource.contains("intrinsicContentSize")
        && thinkingSource.contains("store.agentActivityText")
        && !thinkingSource.contains("TimelineView(.animation"), "AgentThinkingIndicator uses reduce-motion, TextOrbitSegment/Path, hang-proof CADisplayLink NSView host, and agentActivityText")
} else {
    expect(false, "AgentThinkingIndicator and AgentStreamingResponse source bounds are inspectable")
}
expect(notesAgentSource.contains("if store.isAskingAgent && store.agentStreamingText.isEmpty")
    && notesAgentSource.contains("AgentThinkingIndicator()"), "loading motion appears only while asking and streaming text is still empty")
// Deleted overlay views (drawer / corner / quiet insight / compact previews) are gone.
expect(!notesAgentSource.contains("struct AgentDrawerView")
    && !notesAgentSource.contains("struct CornerAgentView")
    && !notesAgentSource.contains("struct QuietInsightView")
    && !notesAgentSource.contains("CompactAgentMessagePreviewList")
    && !notesAgentSource.contains("CompactAgentMessagePreviewRow"), "deleted agent overlay view types are removed from NotesAgentView")
if let selectionStart = notesAgentSource.range(of: "struct FloatingSelectionAgentView")?.lowerBound,
   let agentBubbleStart = notesAgentSource.range(of: "private struct AgentBubble")?.lowerBound {
    let floatingSelectionSource = String(notesAgentSource[selectionStart..<agentBubbleStart])
    expect(floatingSelectionSource.contains("private var promptSeparator: some View")
        && floatingSelectionSource.contains("WeiBeiTheme.hairline.opacity(0.78)")
        && !floatingSelectionSource.contains("Divider()"), "selection floating agent uses WeiBei hairline separators instead of system dividers")
    expect(floatingSelectionSource.contains("AgentComposerField(")
        && floatingSelectionSource.contains("prompt: store.ui(\"问选区或继续追问\", \"Ask about selection…\")")
        && floatingSelectionSource.contains("lineLimit: 1...5")
        && floatingSelectionSource.contains("height: 56")
        && floatingSelectionSource.contains("sendButtonSize: 26"), "expanded selection agent keeps a usable follow-up composer for full answers")
    expect(floatingSelectionSource.contains("Button(store.ui(\"问\", \"Ask\"))")
        && floatingSelectionSource.contains(".help(store.ui(\"问当前选区\", \"Ask current selection\"))")
        && !floatingSelectionSource.contains("Button(\"问 Agent\")"), "compact selection prompt uses short task language instead of a visible internal agent label")
    if let openStart = floatingSelectionSource.range(of: "private func openExpandedComposer()")?.lowerBound,
       let openSourceStart = floatingSelectionSource.range(of: "private func openSourceReference()")?.lowerBound {
        let openComposerSource = String(floatingSelectionSource[openStart..<openSourceStart])
        expect(openComposerSource.contains("store.askSelection()")
            && !openComposerSource.contains("store.askAgent()")
            && openComposerSource.contains("keepFloatingSelectionForAnswer = true"), "selection prompt expands the float without auto-sending a generated question")
    } else {
        expect(false, "floating selection open-composer action is inspectable")
    }
    expect(floatingSelectionSource.contains("var routesToConversation = false")
        && floatingSelectionSource.contains("private var showsExpandedBody: Bool")
        && floatingSelectionSource.contains("store.keepFloatingSelectionForAnswer")
        && floatingSelectionSource.contains("isThreadReopen")
        && floatingSelectionSource.contains("if showsExpandedBody")
        && floatingSelectionSource.contains("store.isAskingAgent")
        && floatingSelectionSource.contains("selectionTagLabel")
        && floatingSelectionSource.contains("Never fall back to the global conversation feed")
        && floatingSelectionSource.contains("AgentMessageMarkdownText(")
        && floatingSelectionSource.contains("compact: true"), "selection float expands on ask/reopen, isolates threads, and renders compact markdown")
    expect(floatingSelectionSource.contains("message.text.hasPrefix(\"请解释当前已选文本片段\")")
        && floatingSelectionSource.contains("message.text.hasPrefix(\"请解释下面选区\")"), "selection floating feed hides generated selection prompts from both current and legacy drafts")
    expect(floatingSelectionSource.contains("closeFloatingAgent()")
        && floatingSelectionSource.contains("togglePinnedFloatingAgent")
        && floatingSelectionSource.contains("pin.fill")
        && floatingSelectionSource.contains("Unpin must not dismiss"), "selection floating agent supports pin and explicit close")
} else {
    expect(false, "selection floating agent source is readable")
}
expect(notesAgentSource.contains("private func agentInputTray(wide: Bool, contentWidth: CGFloat)"), "agent pane uses a dedicated input tray")
expect(notesAgentSource.contains("private var agentContentMaxWidth: CGFloat?")
    && notesAgentSource.contains("private enum AgentChatLayoutMetrics")
    && notesAgentSource.contains("static let wideComposerMinHeight: CGFloat = 108")
    && notesAgentSource.contains("static let compactComposerHeight: CGFloat = 52")
    && notesAgentSource.contains("layout == .immersiveConversation")
    && notesAgentSource.contains("let isUser = message.role == .user")
    // Shared reading column helper — messages, streaming, and loading status share the same inset.
    && notesAgentSource.contains("private func agentReadingColumn")
    && notesAgentSource.contains("let limit: CGFloat = canvasWide ? 540 : 500")
    && notesAgentSource.contains("let readingLeadingInset = max((geometryWidth - readingWidth) / 2, 0)")
    && notesAgentSource.contains(".padding(.leading, readingLeadingInset)")
    && notesAgentSource.contains(".frame(maxWidth: .infinity, alignment: .leading)")
    && notesAgentSource.contains("AgentThinkingIndicator()")
    && !notesAgentSource.contains("maxWidth: isUser ? .infinity : readingWidth")
    && notesAgentSource.contains("private var userBubbleFill: Color")
    && notesAgentSource.contains("private var userBubbleStroke: Color")
    && notesAgentSource.contains(".frame(maxWidth: 520, alignment: .trailing)")
    && notesAgentSource.contains("showsContentRail")
    && notesAgentSource.contains("!wide && store.layout.allowsRailOnlyPanes")
    && notesAgentSource.contains("AgentCitationParser")
    && notesAgentSource.contains("AgentCitationTagRow")
    && workspaceStoreSource.contains("func openAgentCitation")
    && workspaceStoreSource.contains("resolveStudyItem(matchingCitationTitle:")
    && workspaceStoreSource.contains("keepFloatingSelectionForAnswer")
    && workspaceStoreSource.contains("SelectionAskThread"), "agent uses one centered reading column; immersive Codex-like chat is 920×108+, three-pane is 560×52")
expect(notesAgentSource.contains("private let agentBottomAnchorID = \"agentConversationBottom\"")
    && notesAgentSource.contains(".id(agentBottomAnchorID)")
    && notesAgentSource.contains("proxy.scrollTo(agentBottomAnchorID, anchor: .bottom)")
    && !notesAgentSource.contains("AgentScrollBottomPreferenceKey")
    && !notesAgentSource.contains("onPreferenceChange(AgentScrollBottomPreferenceKey"), "agent conversation uses a stable bottom anchor without a geometry preference loop")
expect(notesAgentSource.contains("// No scrollTargetLayout / scrollPosition / minHeight:viewport /")
    && notesAgentSource.contains("guard agentFollowsLatest else { return }")
    && !notesAgentSource.contains("AgentMessageFramePreferenceKey")
    && !notesAgentSource.contains(".coordinateSpace(name: agentConversationCoordinateSpace)")
    && !notesAgentSource.contains(".scrollPosition(id:"), "agent conversation avoids geometry preference and scroll-position loops that re-center a long rich answer after an internal interaction")
expect(notesAgentSource.contains("private var agentInputMaxWidth: CGFloat?")
    && notesAgentSource.contains("AgentChatLayoutMetrics.contentWidth(")
    && notesAgentSource.contains("composerFieldHeight")
    && notesAgentSource.contains("static let wideComposerMinHeight: CGFloat = 108")
    && notesAgentSource.contains("showsModelFooter: wide")
    && notesAgentSource.contains(".frame(width: contentWidth, alignment: .bottom)")
    && notesAgentSource.contains("agent-input-tray-wide"), "agent composer matches reading column width with growable immersive height and model footer")
expect(notesAgentSource.contains(".contentShape(Rectangle())")
    && notesAgentSource.contains("focused.wrappedValue = true")
    && notesAgentSource.components(separatedBy: "AgentComposerField(").count >= 3
    && notesAgentSource.components(separatedBy: "draftFocused = true").count >= 2, "agent composer surfaces focus when tapping the visible input tray, not only the exact text glyph")
expect(notesAgentSource.contains("ScrollView(showsIndicators: true)")
    && notesAgentSource.components(separatedBy: "ScrollView(showsIndicators: false)").count >= 3
    // Hang-proof: follow latest on message count when agentFollowsLatest,
    // not via per-message WKWebView height measurement or GeometryReader parent thrash.
    && notesAgentSource.contains("scrollAgentToBottom(proxy)")
    && notesAgentSource.contains("guard agentFollowsLatest else { return }")
    && notesAgentSource.contains("onChange(of: store.messages.count)")
    && notesAgentSource.contains("AgentPaneWidthKey")
    && !notesAgentSource.contains("GeometryReader { paneGeometry in")
    && !notesAgentSource.contains("onMarkdownHeightChange: message.id == store.messages.last?.id"), "agent conversation keeps a light scroll affordance and follows the latest turn without WebView height thrash")
expect(notesAgentSource.contains("WeiBeiGlassHeaderBackground(") && notesAgentSource.contains("WeiBeiTheme.glassTint.opacity(0.40)"), "agent input tray uses paper glass fade instead of a hard white strip")
expect(notesAgentSource.contains("WeiBeiTheme.ink.opacity(0.42), WeiBeiTheme.ink.opacity(0.78)")
    && !notesAgentSource.contains(".black.opacity(0.72), .black"), "agent input tray fade mask uses semantic ink instead of a fixed black ramp")
expect(notesAgentSource.contains("lineLimit: wide ? 1...10 : 1...6")
    && notesAgentSource.contains("showsModelFooter: wide")
    && notesAgentSource.contains(".frame(width: contentWidth, alignment: .bottom)")
    && notesAgentSource.contains("height: minHeight")
    && notesAgentSource.contains("maxHeight: maxHeight")
    && notesAgentSource.contains("prompt: agentPrompt")
    && notesAgentSource.contains("WeiBeiIconButtonStyle(size: sendButtonSize, prominence: store.isAskingAgent ? .neutral : .primary)")
    && notesAgentSource.contains("sendButtonSize: wide ? 32 : 28")
    && notesAgentSource.contains("sendBottom: wide ? 10 : 8")
    && notesAgentSource.contains("private var isWideComposer: Bool"), "main agent input uses a growable Codex-like composer in wide chat with model footer and send control")
expect(notesAgentSource.contains("Image(systemName: store.isAskingAgent ? \"stop.fill\" : \"paperplane.fill\")")
    && notesAgentSource.contains("store.isAskingAgent ? store.cancelAgentRequest() : submit()")
    && !notesAgentSource.contains("Image(systemName: \"arrow.up\")")
    && !notesAgentSource.contains("AgentComposerSendButtonStyle"), "main agent composer switches between the paper-plane send control and a stop control")
expect(!notesAgentSource.contains("RoundedRectangle(cornerRadius: 9)")
    && !notesAgentSource.contains(".stroke(draftFocused ? WeiBeiTheme.link.opacity(0.16) : WeiBeiTheme.hairline.opacity(0.34), lineWidth: 1)")
    && !notesAgentSource.contains("WeiBeiTheme.paperRaised.opacity(0.46)"), "agent input tray avoids a heavy nested form border")
expect(!notesAgentSource.contains(".disabled(store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)") && !notesAgentSource.contains(".disabled(!canSend)") && !notesAgentSource.contains(".disabled(store.isAskingAgent)"), "agent inputs hide unavailable send actions instead of showing disabled buttons")
expect(!notesAgentSource.contains("agentToolButton(") && !notesAgentSource.contains("help: store.ui(\"整理笔记\""), "main agent header does not become a toolbar")
expect(notesAgentSource.contains("LazyVGrid(columns: starterChipColumns")
    && notesAgentSource.contains("GridItem(.adaptive(minimum: 56)")
    && !notesAgentSource.contains("HStack(spacing: 8) {\n                if store.hasSelectedMaterial {\n                    starterChip(\"梳理材料\""), "agent empty-state starter actions adapt in narrow panes instead of squeezing into one row")
expect(notesAgentSource.contains("private func togglePinnedFloatingAgent()")
    && notesAgentSource.contains("store.pinnedFloatingAgent = next")
    && notesAgentSource.contains("store.keepFloatingSelectionForAnswer = true")
    && notesAgentSource.contains("pin.fill")
    && notesAgentSource.contains("accessibilityLabel(Text(store.pinnedFloatingAgent")
    && !notesAgentSource.contains("iconButton(\"xmark\", help: \"关闭选区对话\")"), "selection float pin control keeps the panel open without a redundant close-button helper")
expect(!notesAgentSource.contains(".help(\"收起右下角 Agent\")")
    && !notesAgentSource.contains("收起对话浮窗"), "deleted corner agent close affordance is gone and no engineering labels remain")
expect(commandPaletteSource.contains("插入行内公式") && commandPaletteSource.contains("${{WEIBEI_SELECT_START}}x_i = \\\\frac{a}{b}{{WEIBEI_SELECT_END}}$") && commandPaletteSource.contains("插入矩阵公式"), "markdown command templates keep an editable landing point")
expect(commandPaletteSource.contains("插入 Callout") && commandPaletteSource.contains("> [!note] 标题\\n>\\n> {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}}"), "callout insertion separates title from body")
expect(commandPaletteSource.contains("private func markdownInsertCommand") && commandPaletteSource.contains("animation: WeiBeiMotion.layout"), "markdown insert commands use layout motion when revealing writing")
expect(webEditorSource.contains("decorateSourceReferences") && webEditorSource.contains("sourceReferenceActivated") && webEditorSource.contains("activateSourceReference"), "web editor exposes source references as clickable bridge actions")
let richMarkdownEditorSourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/WeiBei/Views/RichMarkdownEditorView.swift")
let richMarkdownEditorSource = (try? String(contentsOf: richMarkdownEditorSourceURL, encoding: .utf8)) ?? ""
expect(richMarkdownEditorSource.contains("\"sourceReferenceActivated\"") && richMarkdownEditorSource.contains("onSourceReference(reference)"), "rich editor bridges source-reference clicks into Swift")
expect(LibraryNavigator.adjacentID(in: [], selectedID: nil, step: 1) == nil, "library navigation empty")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: nil, step: 1) == "a", "library navigation defaults first")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "b", step: 1) == "c", "library navigation next")
expect(LibraryNavigator.adjacentID(in: ["a", "b", "c"], selectedID: "a", step: -1) == "c", "library navigation wraps previous")

expect(SelectionContext(text: "文档", source: .document, ownerTitle: "资料").isNoteSelection == false, "document selection is read-only")
expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isNoteSelection == true, "note selection is replaceable")
expect(SelectionContext(text: "笔记", source: .note, ownerTitle: "资料").isReplaceableNoteSelection, "editable note selection can be replaced")
expect(!SelectionContext(text: "预览", source: .note, ownerTitle: "资料", isEditable: false).isReplaceableNoteSelection, "preview note selection is not replaceable")
expect(SelectionAttachmentMerge.mergedText(existing: "当前笔记已经覆盖材", incoming: "开头。建议检查是否写了来源、例子和待追问。", withinSelectionGesture: true) == "当前笔记已经覆盖材开头。建议检查是否写了来源、例子和待追问。", "same-gesture selection attachment stitches split live selection fragments into one attachment")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用", incoming: "使用价格的表达", withinSelectionGesture: true) == "利率是资金使用价格的表达", "same-gesture overlapping fragments merge without duplicate overlap text")
expect(SelectionAttachmentMerge.mergedText(existing: "你们", incoming: "好", withinSelectionGesture: true) == "你们好", "same-gesture single-character live-selection fragments merge into one human selection")
expect(SelectionAttachmentMerge.mergedText(existing: "开头。建议检查是否写了来源。", incoming: "你们好", withinSelectionGesture: true) == "开头。建议检查是否写了来源。你们好", "same-gesture short trailing live-selection fragments still merge after sentence punctuation")
expect(SelectionAttachmentMerge.mergedText(existing: "利率", incoming: "利率是资金使用价格", withinSelectionGesture: false) == "利率是资金使用价格", "selection attachment merge still replaces a shorter contained selection with the fuller text")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用价格。", incoming: "通货膨胀预期会改变真实利率。", withinSelectionGesture: true) == nil, "same-gesture selection attachment does not blindly stitch separate complete sentences")
expect(SelectionAttachmentMerge.mergedText(existing: "利率是资金使用价格", incoming: "通货膨胀预期", withinSelectionGesture: false) == nil, "separate selections outside one gesture remain separate fragments")
expect(SelectionAttachmentMerge.containsSelection("当前笔记已经覆盖材料开头。建议检查是否写了来源。", fragment: "材料 开头。")
    && !SelectionAttachmentMerge.containsSelection("利率是资金使用价格", fragment: ""), "selection attachment containment ignores whitespace and rejects empty fragments")
expect(workspaceStoreSource.contains("SelectionAttachmentMerge.containsSelection($0.text, fragment: cleanedText)")
    && workspaceStoreSource.contains("selectionAttachments.removeAll")
    && workspaceStoreSource.contains("SelectionAttachmentMerge.containsSelection(cleanedText, fragment: $0.text)"), "selection attachment intake collapses stale short fragments once the fuller live selection arrives")
expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: true) == 20, "flipped content view keeps selection y")
expect(SelectionAnchorCoordinate.y(20, contentHeight: 100, contentViewIsFlipped: false) == 80, "non-flipped content view converts selection y")
expect(!SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: false, pinned: false), "selection agent waits for anchor before floating")
expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: true, pinned: false), "selection agent appears when anchored")
expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: true, hasAnchor: false, pinned: false, keepOpen: true), "keepOpen floats stay visible without a live drag anchor")
expect(SelectionFloatingAgentPlacement.isVisible(surface: .selectionFloat, hasSelection: false, hasAnchor: false, pinned: true), "pinned floats stay visible without selection")
if let reopenStart = workspaceStoreSource.range(of: "func openSelectionAskThread")?.lowerBound,
   let reuseStart = workspaceStoreSource.range(of: "func beginOrReuseSelectionAskThread")?.lowerBound,
   reopenStart < reuseStart {
    let reopenSource = String(workspaceStoreSource[reopenStart..<reuseStart])
    expect(reopenSource.contains("keepFloatingSelectionForAnswer = true")
        && reopenSource.contains("anchor: CGPoint?")
        && !reopenSource.contains("pinnedFloatingAgent = true"), "reopening an asked thread expands without force-pinning and can dock to an underline anchor")
} else {
    expect(false, "openSelectionAskThread source is readable")
}
expect(SelectionFloatingAgentPlacement.expandedHalfWidth == 230 && SelectionFloatingAgentPlacement.compactHalfWidth == 82, "selection agent placement constants match the compact and expanded surfaces")
expect(contentViewSource.contains("SelectionFloatingAgentPlacement.expandedHalfWidth")
    && contentViewSource.contains("SelectionFloatingAgentPlacement.compactHalfWidth")
    && !contentViewSource.contains("surfaceHalfWidth: floatingAgentExpanded ? 170 : 82"), "selection agent placement uses shared width constants instead of duplicate magic numbers")
expect(notesAgentSource.contains(".frame(width: panelWidth, alignment: .leading)")
    && notesAgentSource.contains("SelectionFloatingAgentPlacement.expandedHalfWidth * 2")
    && !notesAgentSource.contains(".frame(width: 312, alignment: .leading)"), "expanded selection agent visual width matches placement half-width and stays resizable")
let floatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
let topInsetFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    topInset: 42
)
expect(floatingPoint.x == 562 && floatingPoint.y == 245.5, "selection agent opens close beside the text anchor")
expect(topInsetFloatingPoint.x == 562 && topInsetFloatingPoint.y == 228, "selection agent compensates top bar coordinate space")
let compactEdgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 12, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
    prefersAnchorCenter: true
)
let compactCenterFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 320, y: 200),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800),
    surfaceHalfWidth: SelectionFloatingAgentPlacement.compactHalfWidth,
    prefersAnchorCenter: true
)
expect(compactCenterFloatingPoint.x == 320 && compactCenterFloatingPoint.y == 210, "selection prompt centers on the text anchor when compact")
expect(compactEdgeFloatingPoint.x == 100 && compactEdgeFloatingPoint.y == 210, "selection prompt clamps only at the edge when compact")
let edgeFloatingPoint = SelectionFloatingAgentPlacement.position(
    anchor: FloatingAgentCoordinate(x: 1160, y: 760),
    canvas: FloatingAgentCoordinate(x: 1200, y: 800)
)
expect(edgeFloatingPoint.x == 918 && edgeFloatingPoint.y == 572, "selection agent flips to the left of text near the window edge")
expect(AgentMessage(role: .assistant, text: "整理完成", source: nil).isUsableAgentAnswer, "usable agent answer")
expect(!AgentMessage(role: .assistant, text: "未配置密钥。", source: nil).isUsableAgentAnswer, "credential setup message is not writable")
expect(!AgentMessage(role: .assistant, text: "未配置 OPENAI_API_KEY。", source: nil).isUsableAgentAnswer, "api key setup message is not writable")
expect(!AgentMessage(role: .assistant, text: "未配置 OPENAI_API_KEY 或钥匙串密钥。", source: nil).isUsableAgentAnswer, "keychain setup message is not writable")
expect(AgentMessage(role: .assistant, text: offlineChinesePreview, source: nil).isUsableAgentAnswer, "offline draft is visible in chat and writable to notes")
expect(AgentMessage(role: .assistant, text: offlineEnglishPreview, source: nil).isUsableAgentAnswer, "English offline draft is visible in chat and writable to notes")
expect(!AgentMessage(role: .assistant, text: "请求失败：网络错误", source: nil).isUsableAgentAnswer, "agent error is not writable")
expect(!AgentMessage(role: .assistant, text: "请求失败\n可直接重试。", source: nil).isUsableAgentAnswer, "generic failure header without colon is not writable")
expect(!AgentMessage(role: .assistant, text: "Agent 请求失败：网络错误", source: nil).isUsableAgentAnswer, "legacy agent error is not writable")

let importedMarkdown = StudyItem(id: "file:/tmp/note.md", title: "note", subtitle: "note.md", kind: .markdown, urlPath: "/tmp/note.md", isSample: false)
let notebookMarkdown = StudyItem(id: "file:/tmp/notebook.md", title: "notebook", subtitle: "notebook.md", kind: .markdown, urlPath: "/tmp/notebook.md", isSample: false, isNotebookNote: true)
let sampleMarkdown = StudyItem(id: "sample", title: "sample", subtitle: "sample", kind: .markdown, urlPath: nil, isSample: true)
expect(importedMarkdown.isImportedMarkdownFile, "imported markdown is readable as material")
expect(!importedMarkdown.editsBackingMarkdownFile, "imported markdown material does not edit backing file")
expect(importedMarkdown.canBecomeNotebookNote, "imported markdown can become an editable notebook note")
expect(notebookMarkdown.editsBackingMarkdownFile, "notebook markdown edits its backing file")
expect(!notebookMarkdown.canBecomeNotebookNote, "notebook markdown does not offer duplicate conversion")
expect(!sampleMarkdown.isImportedMarkdownFile, "sample markdown stays app-owned")
expect(!sampleMarkdown.canBecomeNotebookNote, "sample markdown cannot become a backing-file note")

let relationNoteID = "note:research"
let relationNoteB = "note:shared"
let relationNoteC = "note:replacement"
let relationSourceA = "file:/tmp/a.pdf"
let relationSourceB = "file:/tmp/b.html"
let oldestLink = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    noteItemID: relationNoteID,
    sourceItemID: relationSourceA,
    createdAt: Date(timeIntervalSince1970: 1)
)
let duplicateLink = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
    noteItemID: relationNoteID,
    sourceItemID: relationSourceA,
    createdAt: Date(timeIntervalSince1970: 2)
)
let sharedSourceLink = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
    noteItemID: relationNoteB,
    sourceItemID: relationSourceA,
    createdAt: Date(timeIntervalSince1970: 3)
)
let sharedSourceDuplicate = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
    noteItemID: relationNoteB,
    sourceItemID: relationSourceA,
    createdAt: Date(timeIntervalSince1970: 4)
)
let unrelatedSourceLink = NoteSourceLink(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
    noteItemID: relationNoteID,
    sourceItemID: relationSourceB,
    createdAt: Date(timeIntervalSince1970: 5)
)
var noteSourceRelations = NoteSourceRelations(links: [duplicateLink, oldestLink])
expect(noteSourceRelations.links == [oldestLink]
    && noteSourceRelations.sourceIDs(for: relationNoteID) == [relationSourceA], "note-source relations keep one durable pair and preserve the oldest identity")
noteSourceRelations.replaceSources(for: relationNoteID, sourceItemIDs: [relationSourceB])
expect(noteSourceRelations.sourceIDs(for: relationNoteID) == [relationSourceB]
    && !noteSourceRelations.isLinked(noteItemID: relationNoteID, sourceItemID: relationSourceA), "explicitly replacing a note's sources removes unlinked material")
noteSourceRelations.sanitize(validNoteItemIDs: [relationNoteID], validSourceItemIDs: [relationSourceA])
expect(noteSourceRelations.links.isEmpty, "note-source sanitation removes relationships whose source no longer exists")

var sharedSourceRelations = NoteSourceRelations(
    links: [unrelatedSourceLink, sharedSourceDuplicate, sharedSourceLink, duplicateLink, oldestLink]
)
expect(sharedSourceRelations.links == [oldestLink, sharedSourceLink, unrelatedSourceLink]
    && sharedSourceRelations.noteIDs(for: relationSourceA) == [relationNoteID, relationNoteB], "one source can be shared by multiple notes while duplicate pairs keep their oldest identity")
sharedSourceRelations.replaceNotes(
    for: relationSourceA,
    noteItemIDs: [relationNoteB, relationNoteC]
)
expect(sharedSourceRelations.noteIDs(for: relationSourceA) == [relationNoteB, relationNoteC]
    && sharedSourceRelations.links.contains(sharedSourceLink)
    && sharedSourceRelations.links.contains(unrelatedSourceLink)
    && !sharedSourceRelations.isLinked(noteItemID: relationNoteID, sourceItemID: relationSourceA), "replacing a source's notes preserves retained links and removes only deselected notes")
let relationIndex = NoteSourceRelationIndex(links: sharedSourceRelations.links)
expect(relationIndex.sourceIDs(for: relationNoteB) == [relationSourceA]
    && relationIndex.noteIDs(for: relationSourceA) == [relationNoteB, relationNoteC]
    && relationIndex.sourceCount(for: relationNoteID) == 1
    && relationIndex.noteCount(for: relationSourceB) == 1, "relationship index reuses normalized note-to-source and source-to-note lookups")

let courseMaterials = [
    StudyItem(id: "material:a", title: "第一讲", subtitle: "第一讲.pdf", kind: .pdf, urlPath: "/tmp/course/a.pdf", isSample: false),
    StudyItem(id: "material:b", title: "第二讲", subtitle: "第二讲.html", kind: .html, urlPath: "/tmp/course/b.html", isSample: false),
    StudyItem(id: "material:c", title: "补充材料", subtitle: "补充材料.txt", kind: .text, urlPath: "/tmp/course/c.txt", isSample: false)
]
let courseNotes = [
    StudyItem(id: "note:a", title: "第一讲笔记", subtitle: "第一讲笔记.md", kind: .markdown, urlPath: "/tmp/course/note-a.md", isSample: false, isNotebookNote: true),
    StudyItem(id: "note:b", title: "共同主题", subtitle: "共同主题.md", kind: .markdown, urlPath: "/tmp/course/note-b.md", isSample: false, isNotebookNote: true),
    StudyItem(id: "note:c", title: "待整理", subtitle: "待整理.md", kind: .markdown, urlPath: "/tmp/course/note-c.md", isSample: false, isNotebookNote: true)
]
let builtInSample = StudyItem(id: "sample:ignored", title: "内置样例", subtitle: "样例", kind: .html, urlPath: nil, isSample: true)
let courseLinks = [
    NoteSourceLink(noteItemID: "note:a", sourceItemID: "material:a", createdAt: Date(timeIntervalSince1970: 10)),
    NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:a", createdAt: Date(timeIntervalSince1970: 11)),
    NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:b", createdAt: Date(timeIntervalSince1970: 12)),
    NoteSourceLink(noteItemID: "note:b", sourceItemID: "material:b", createdAt: Date(timeIntervalSince1970: 13)),
    NoteSourceLink(noteItemID: "note:missing", sourceItemID: "material:c", createdAt: Date(timeIntervalSince1970: 14)),
    NoteSourceLink(noteItemID: "note:a", sourceItemID: "sample:ignored", createdAt: Date(timeIntervalSince1970: 15))
]
let firstCourseSessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
let secondCourseSessionID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
let courseSummary = CourseWorkspaceSummary(
    importedItems: courseMaterials + courseNotes + [builtInSample],
    noteSourceLinks: courseLinks,
    studyLocationsByItemID: [
        "material:a": StudyLocation(itemID: "material:a", itemTitle: "第一讲"),
        "material:c": StudyLocation(itemID: "material:c", itemTitle: "补充材料"),
        "material:missing": StudyLocation(itemID: "material:missing", itemTitle: "已移除资料")
    ],
    studySessions: [
        StudySession(
            id: firstCourseSessionID,
            title: "第一次学习",
            messages: [AgentMessage(role: .user, text: "解释第一讲", source: "第一讲")]
        ),
        StudySession(id: secondCourseSessionID, title: "第二次学习")
    ],
    learningMemoryEntries: [
        LearningMemoryEntry(kind: .confusion, text: "困惑一", evidence: "用户提出", origin: .userStatement),
        LearningMemoryEntry(kind: .confusion, text: "困惑二", evidence: "用户提出", origin: .userStatement),
        LearningMemoryEntry(kind: .confusion, text: "已解决困惑", evidence: "用户提出", origin: .userStatement, status: .resolved),
        LearningMemoryEntry(kind: .goal, text: "课程目标", evidence: "用户提出", origin: .userStatement)
    ]
)
expect(courseSummary.materialCount == 3
    && courseSummary.noteCount == 3
    && courseSummary.explicitLinkCount == 3
    && courseSummary.readingPositionCount == 2
    && courseSummary.unlinkedMaterialCount == 1
    && courseSummary.unlinkedNoteCount == 1
    && courseSummary.studySessionCount == 1
    && courseSummary.unresolvedConfusionCount == 2, "course workspace summary reports only durable facts from the imported course")

let courseA = Course(
    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    title: "货币金融学",
    colorIndex: 0,
    sourceRootPath: "/Courses/Money"
)
let courseB = Course(
    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
    title: "经济思想史",
    colorIndex: 1,
    sourceRootPath: "/Courses/History"
)
var courseMemberships = CourseItemMemberships()
courseMemberships.assign(itemIDs: Set(["material-a", "note-a"]), to: courseA.id)
courseMemberships.assign(itemIDs: Set(["material-a", "material-b"]), to: courseB.id)
expect(Set(courseMemberships.courseIDs(for: "material-a")) == Set([courseA.id, courseB.id])
    && Set(courseMemberships.itemIDs(in: courseA.id)) == Set(["material-a", "note-a"])
    && Set(courseMemberships.itemIDs(in: courseB.id)) == Set(["material-a", "material-b"]), "one item can belong to multiple real courses without duplicating the item")
courseMemberships.replaceCourses(for: "note-a", courseIDs: Set([courseB.id]))
expect(courseMemberships.courseIDs(for: "note-a") == [courseB.id]
    && !courseMemberships.itemIDs(in: courseA.id).contains("note-a"), "changing course membership removes only the replaced item-course pair")

let persisted = PersistedWorkspace(
    courses: [courseA, courseB],
    courseItemMemberships: courseMemberships.values,
    activeCourseID: courseB.id,
    noteSourceLinks: [oldestLink],
    noteSourceLinksMigrationVersion: 1,
    threePaneOrder: [.agent, .reader, .notes],
    noteRenderMode: .preview,
    showLibrary: false,
    showReader: false,
    showAgent: true,
    showNotes: false,
    showRightPane: true,
    showDailyInspiration: false,
    adaptImportedDocumentColors: false
)
let restored = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(persisted))
expect(restored.showLibrary == false && restored.showReader == false && restored.showAgent == true && restored.showNotes == false && restored.showRightPane == true, "pane visibility state persists")
expect(restored.courses == [courseA, courseB]
    && restored.courseItemMemberships == courseMemberships.values
    && restored.activeCourseID == courseB.id, "courses, many-to-many membership, and the active course persist together")
expect(restored.showDailyInspiration == false, "daily inspiration can be disabled and restored from workspace persistence")
let reenabledInspiration = try JSONDecoder().decode(PersistedWorkspace.self, from: try JSONEncoder().encode(PersistedWorkspace(showDailyInspiration: true)))
expect(reenabledInspiration.showDailyInspiration == true, "daily inspiration can be re-enabled and restored from workspace persistence")
let legacyWorkspace = try JSONDecoder().decode(PersistedWorkspace.self, from: Data(#"{"importedItems":[],"notesByItemID":{}}"#.utf8))
expect(legacyWorkspace.showDailyInspiration == nil
    && legacyWorkspace.courses == nil
    && legacyWorkspace.courseItemMemberships == nil
    && legacyWorkspace.activeCourseID == nil
    && workspaceStoreSource.contains("showDailyInspiration = snapshot.showDailyInspiration ?? true"), "older workspace snapshots remain decodable without inventing a fake course")
expect(restored.adaptImportedDocumentColors == false
    && workspaceStoreSource.contains("adaptImportedDocumentColors = snapshot.adaptImportedDocumentColors ?? true")
    && workspaceStoreSource.contains("adaptImportedDocumentColors: adaptImportedDocumentColors"), "imported-document color adaptation persists while old workspaces default to adapted reading")
expect(restored.noteRenderMode == .preview, "legacy preview note mode remains decodable for old workspace snapshots")
expect(restored.threePaneOrder == [.agent, .reader, .notes], "custom three-pane order persists")
expect(restored.noteSourceLinks == [oldestLink] && restored.noteSourceLinksMigrationVersion == 1, "note-source relations and one-time migration state persist together")
expect(workspaceStoreSource.contains("if let noteRenderMode = snapshot.noteRenderMode {\n            self.noteRenderMode = noteRenderMode.visibleMode\n        }")
    && workspaceStoreSource.contains("noteRenderMode = snapshot.noteRenderMode.visibleMode")
    && workspaceStoreSource.contains("let nextMode = mode.visibleMode")
    && !workspaceStoreSource.contains("noteRenderMode == .source ? .source : .rich"), "workspace load and navigation normalize legacy preview mode back to writing")

let attachmentRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("weibei-self-check-\(UUID().uuidString)", isDirectory: true)
let attachmentDirectory = attachmentRoot.appendingPathComponent(".weibei-assets", isDirectory: true)
let dataURL = "data:image/png;base64,\(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString())"
let firstAttachment = try MarkdownAttachmentStore.save(
    dataURL: dataURL,
    originalName: "图 1).png",
    mime: "image/png",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(firstAttachment.src == ".weibei-assets/图 1).png", "attachment uses relative markdown path")
expect(firstAttachment.alt == "图 1)", "attachment alt uses safe stem")
expect(MarkdownAttachmentStore.markdownImage(for: firstAttachment) == "![图 1)](.weibei-assets/图%201%29.png)", "markdown image escapes path")

let secondAttachment = try MarkdownAttachmentStore.save(
    dataURL: dataURL,
    originalName: "图 1).png",
    mime: "image/png",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(secondAttachment.src == ".weibei-assets/图 1)-2.png", "attachment avoids overwriting duplicate names")
expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(firstAttachment.src).path), "first attachment written")
expect(FileManager.default.fileExists(atPath: attachmentRoot.appendingPathComponent(secondAttachment.src).path), "second attachment written")
let rawAttachment = try MarkdownAttachmentStore.save(
    data: Data([1, 2, 3]),
    originalName: "dragged.webp",
    mime: "",
    attachmentDirectory: attachmentDirectory,
    markdownBaseURLString: attachmentRoot.absoluteString
)
expect(rawAttachment.src == ".weibei-assets/dragged.webp", "raw image data save keeps image extension")
expect(MarkdownAttachmentStore.isSupportedImageExtension("HEIC"), "image extension check is case insensitive")
expect(MarkdownAttachmentStore.mimeType(forFileExtension: "jpeg") == "image/jpeg", "mime from extension")
let blockInsert = MarkdownBlockInsertion.insert(
    "![pasted](Attachments/pasted.png)",
    into: "来源：课程 HTML",
    replacing: NSRange(location: ("来源：课程 HTML" as NSString).length, length: 0)
)
expect(blockInsert.text == "来源：课程 HTML\n\n![pasted](Attachments/pasted.png)", "block markdown insertion separates from inline text")
let middleBlockInsert = MarkdownBlockInsertion.insert(
    "![pasted](Attachments/pasted.png)",
    into: "前文后文",
    replacing: NSRange(location: ("前文" as NSString).length, length: 0)
)
expect(middleBlockInsert.text == "前文\n\n![pasted](Attachments/pasted.png)\n\n后文", "block markdown insertion separates both sides")
try? FileManager.default.removeItem(at: attachmentRoot)

print("WeiBei self-check passed")
}
