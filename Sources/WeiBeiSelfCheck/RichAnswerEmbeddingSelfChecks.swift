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
}
