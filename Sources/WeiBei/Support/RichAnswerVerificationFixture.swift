import AppKit
import Foundation
import WeiBeiCore

enum RichAnswerVerificationFixture {
    enum Example: String, CaseIterable {
        case text = "rich-answer-text"
        case quantity = "rich-answer-quantity"
        case process = "rich-answer-process"
        case relation = "rich-answer-relation"
        case timeline = "rich-answer-timeline"
        case space = "rich-answer-space"
        case image = "rich-answer-image"
        case comparison = "rich-answer-comparison"
        case calculation = "rich-answer-calculation"
        case constraint = "rich-answer-constraint"
        case pendulum = "rich-answer-pendulum"
        case sequence = "rich-answer-sequence"

        var question: String {
            switch self {
            case .text:
                return "把这句诗的原文、意象和主题判断放在一起批注，不要只写一段解释。"
            case .quantity:
                return "画出 y = x²，并让我拖动 x，看点和读数一起变化。"
            case .process:
                return "画出钠把最外层电子交给氯的过程，让我拖动电子观察离子键怎样形成。"
            case .relation:
                return "画一个植物细胞，直接标出光合作用发生的位置和关键结构。"
            case .timeline:
                return "把材料里的三个历史事件放进可拖动时间线。"
            case .space:
                return "把河流上中下游的路径和地貌变化画在同一张空间图上。"
            case .image:
                return "在样例版面上覆盖三分线、视觉重心和留白区域。"
            case .comparison:
                return "比较物块在斜面低位、中位和高位时的受力方向，让我拖动位置核对哪些方向改变、哪些不变。"
            case .calculation:
                return "让我调异常值，看均值怎样被拉动。"
            case .constraint:
                return "把 60 分钟复习时间分给概念和练习；让我调整概念时间，同时保证两项总和始终是 60 分钟。"
            case .pendulum:
                return "这是一条通用原语验收题：当前目录没有预制单摆组件，请组合通用原语画出摆长 L 与周期 T 的关系，让我拖动摆长看曲线、探针和读数联动。"
            case .sequence:
                return "把这段论证的前提、桥接、反证和结论做成可逐步检查的序列，让我点选每一步看证据关系。"
            }
        }

        var narrative: String {
            switch self {
            case .text:
                return "原文、意象和判断并排出现，来源紧贴对应解释。"
            case .quantity:
                return "同一组函数采样同时驱动曲线、探针和数值读数。"
            case .process:
                return "电子本身在两个原子之间移动，原子、价电子与离子状态同时可见。"
            case .relation:
                return "细胞膜、液泡、细胞核和叶绿体以不同实体形状嵌套呈现。"
            case .timeline:
                return "拖动时间尺时，当前事件在同一条时间线上被强调。"
            case .space:
                return "区域、路径、节点和标签由通用画布图元组合。"
            case .image:
                return "图像、比例线、区域和开关共同组成叠层，不是固定艺术模板。"
            case .comparison:
                return "低位、中位和高位放在同一套受力基准里比较：位置改变，重力仍竖直向下，支持力仍垂直斜面。"
            case .calculation:
                return "实体柱形与均值读数共用同一异常值参数。"
            case .constraint:
                return "概念时间与练习时间由同一个分配参数联动，两项始终满足总计 60 分钟。"
            case .pendulum:
                return "小角度近似下，周期按摆长的平方根增长；下面的曲线、探针和读数完全由通用原语组合。"
            case .sequence:
                return "这条论证不是一张流程卡片，而是一条可点选、可核对来源的语义序列。"
            }
        }

        var summary: String {
            switch self {
            case .text:
                return "文学批注：原文与解释形成非对称双栏"
            case .quantity:
                return "数学函数：曲线、探针、读数共享一个参数"
            case .process:
                return "化学过程：原子、价电子与移动电子组成微观模型"
            case .relation:
                return "生物结构：细胞与细胞器形成实体嵌套图"
            case .timeline:
                return "历史材料：时间点随拖动状态变化"
            case .space:
                return "地理路径：区域、路线和地貌节点叠加"
            case .image:
                return "艺术设计：原图、比例线和观察区域叠层"
            case .comparison:
                return "物理比较：低、中、高三个位置共用同一受力方向基准"
            case .calculation:
                return "统计实验：柱形分布与均值同步变化"
            case .constraint:
                return "约束计算：两项分配联动且总和固定为 60 分钟"
            case .pendulum:
                return "长尾验收：通用路径、探针、滑杆与读数组合单摆关系"
            case .sequence:
                return "通用序列：步骤、证据与当前状态共用一个绑定"
            }
        }
    }

    static let galleryScenario = "rich-answer-gallery"
    static let openUIProgramScenario = "rich-answer-openui"
    static let extendedOpenUIProgramScenario = "rich-answer-openui-extended"
    static let inlineExtendedOpenUIProgramScenario = "rich-answer-openui-extended-inline"

    static func supports(_ scenario: String) -> Bool {
        scenario == "rich-answer-preview"
            || scenario == galleryScenario
            || scenario == openUIProgramScenario
            || scenario == extendedOpenUIProgramScenario
            || scenario == inlineExtendedOpenUIProgramScenario
            || Example(rawValue: scenario) != nil
    }

    static func question(for scenario: String) -> String {
        if scenario == galleryScenario {
            return "用同一套生成式 UI 协议，给我一组真正不同学科、不同结构的可视化回答。"
        }
        if scenario == openUIProgramScenario {
            return "材料说参数 a 同时决定抛物线的方向和宽窄，我总是混在一起，能用图帮我看明白吗？"
        }
        if scenario == extendedOpenUIProgramScenario || scenario == inlineExtendedOpenUIProgramScenario {
            return "把空间图层、抽样窗口和逐层传导分别放进同一篇回答里，我要确认三种通用深组件都能在 Agent 对话流中真实运行。"
        }
        return example(for: scenario).question
    }

    static func presentation(for scenario: String) -> RichAnswerPresentation {
        ensureVerificationAssets()
        ensureFixtureContracts()
        if scenario == openUIProgramScenario {
            return openUIProgramPresentation
        }
        if scenario == extendedOpenUIProgramScenario || scenario == inlineExtendedOpenUIProgramScenario {
            return extendedOpenUIProgramPresentation
        }
        let examples = scenario == galleryScenario ? Example.allCases : [example(for: scenario)]
        let scenes = examples.map(scene)
        let presentation = RichAnswerEngine.prepare(
            envelope: RichAnswerEnvelope(
                schemaVersion: 2,
                contextRevision: contextRevision,
                narrative: examples.count == 1
                    ? examples[0].narrative
                    : "这组跨学科场景来自同一套布局、画布、数据、控件和来源节点；模型组合结构，宿主统一风格。",
                expressionPlan: RichAnswerExpressionPlan(
                    action: .manipulate,
                    summary: examples.count == 1
                        ? examples[0].summary
                        : "不是固定模板清单：不同 UI 树共用一套可扩展渲染协议",
                    families: Set(scenes.map(\.family)),
                    preferredSurface: .expanded,
                    directManipulation: scenes.contains { scene in
                        scene.ui?.nodes.contains(where: {
                            [.slider, .toggle, .scrubber, .select, .probe].contains($0.role)
                        }) == true
                    }
                ),
                scenes: scenes,
                evidenceLedger: evidenceLedger,
                fallback: RichAnswerFallback(
                    text: "当前生成式界面不可用时，保留材料中的核心解释。",
                    reason: "生成式 UI 验收场景降级"
                )
            ),
            environment: RichAnswerEnvironment(
                contextRevision: contextRevision,
                allowedSourceLabels: Set(evidenceLedger.map(\.sourceLabel)),
                allowedAssetIDs: Set(evidenceLedger.flatMap(\.assetIDs)),
                resourceBudget: RichAnswerResourceBudget(maxScenes: 12)
            )
        )
        let truthfulFixtureExamples: Set<Example> = [.text, .comparison, .constraint]
        let requiredSceneIDs = Set(
            examples
                .filter(truthfulFixtureExamples.contains)
                .map { scene($0).id }
        )
        precondition(
            Set(presentation.scenes.map(\.id)).isSuperset(of: requiredSceneIDs),
            "本轮修正的富回答验证素材未全部通过协议验收"
        )
        return presentation
    }

    static func assetPreview(for assetID: String) -> NSImage? {
        RichAnswerVerificationAssets.image(for: assetID)
    }

    static func assetURL(for assetID: String) -> URL? {
        RichAnswerVerificationAssets.url(for: assetID)
    }

    static func validateVerificationAssets() throws {
        try RichAnswerVerificationAssets.validateBundledResources()
    }

    private static let contextRevision = "rich-ui-cross-discipline-v2"
    private static let artVerificationAssetID = RichAnswerVerificationAssets.keplerPoster
    private static let verificationAssetSelfCheck: Void = {
        do {
            try RichAnswerVerificationAssets.validateBundledResources()
        } catch {
            preconditionFailure("富回答验证图像资产不可用：\(error.localizedDescription)")
        }
    }()

    private static func ensureVerificationAssets() {
        _ = verificationAssetSelfCheck
    }

    private static let fixtureContractSelfCheck: Void = {
        let examples = Example.allCases.map { ($0, scene($0)) }
        precondition(
            Set(examples.map { $0.1.family }) == Set(RichAnswerCapabilityFamily.allCases),
            "富回答验证素材必须覆盖八个能力家族"
        )

        let textScene = scene(.text)
        let textToggleBinding = textScene.ui?.nodes.first(where: { $0.id == "lit-alignment-toggle" })?.bindingID
        precondition(
            textToggleBinding != nil
                && textScene.ui?.nodes.contains(where: {
                    $0.role == .region && $0.bindingID == textToggleBinding
                }) == true
                && textScene.ui?.nodes.contains(where: {
                    $0.role == .metric && $0.bindingID == textToggleBinding && $0.datasetID != nil
                }) == true,
            "文字对齐素材的控件必须真实改变画布标记"
        )

        let comparisonScene = scene(.comparison)
        precondition(
            comparisonScene.family == .comparisonAndEvaluation
                && comparisonScene.ui?.nodes.contains(where: { $0.id == "physics-position-comparison" }) == true,
            "比较素材必须展示可核对的并列状态"
        )

        let constraintScene = scene(.constraint)
        let conceptRows = constraintScene.ui?.datasets.first(where: { $0.id == "allocation-concept" })?.rows ?? []
        let practiceRows = constraintScene.ui?.datasets.first(where: { $0.id == "allocation-practice" })?.rows ?? []
        let stateRows = constraintScene.ui?.datasets.first(where: { $0.id == "allocation-states" })?.rows ?? []
        let stateControl = constraintScene.ui?.nodes.first(where: { $0.id == "allocation-state-control" })
        let stateValues = Set(stateRows.compactMap(\.value))
        let satisfiesFixedTotal = conceptRows.allSatisfy { concept in
            practiceRows.contains { practice in
                practice.value == concept.value
                    && abs((concept.result ?? 0) + (practice.result ?? 0) - 60) < 0.001
            }
        }
        let discreteStatesDriveEveryBar = stateControl?.role == .sequence
            && stateControl?.bindingID == "allocation-concept-time"
            && stateControl?.datasetID == "allocation-states"
            && stateRows.count == 5
            && Set(conceptRows.compactMap(\.value)) == stateValues
            && Set(practiceRows.compactMap(\.value)) == stateValues
        precondition(
            constraintScene.family == .calculationAndConstraints
                && !conceptRows.isEmpty
                && conceptRows.count == practiceRows.count
                && satisfiesFixedTotal
                && discreteStatesDriveEveryBar,
            "约束计算素材必须由离散状态驱动两根柱，并在每个状态保持两项总和为 60"
        )
    }()

    private static func ensureFixtureContracts() {
        _ = fixtureContractSelfCheck
    }

    private static let openUIProgramPresentation = RichAnswerEngine.prepare(
        envelope: RichAnswerEnvelope(
            schemaVersion: 2,
            contextRevision: contextRevision,
            narrative: """
            可以把 a 拆成两个判断：正负决定抛物线朝上还是朝下，|a| 决定曲线更窄还是更宽。

            <!-- weibei-scene:openui-inline-figure -->

            拖动 a 时先看它穿过 0，确认开口方向怎样翻转；再越过 ±1，观察曲线宽窄怎样变化。
            """,
            expressionPlan: RichAnswerExpressionPlan(
                action: .manipulate,
                summary: "在正文结论后插入一个可拖动的参数图解",
                families: [.quantityAndCoordinates],
                preferredSurface: .inline,
                directManipulation: true
            ),
            scenes: [openUIInlineFigure],
            evidenceLedger: openUIEvidenceLedger,
            fallback: RichAnswerFallback(
                text: "当前 OpenUI 运行时不可用，保留二次函数的文本解释。",
                reason: "OpenUI 验收场景降级"
            )
        ),
        environment: RichAnswerEnvironment(
            contextRevision: contextRevision,
            allowedSourceLabels: Set(openUIEvidenceLedger.map(\.sourceLabel)),
            allowedAssetIDs: [],
            resourceBudget: RichAnswerResourceBudget(maxScenes: 1)
        )
    )

    private static let openUIEvidenceLedger = evidenceLedger.filter { $0.id == "math-source" }

    private static let extendedOpenUIEvidenceLedger = evidenceLedger.filter {
        ["geography-source", "statistics-source", "finance-source"].contains($0.id)
    }

    private static let extendedOpenUIProgramPresentation = RichAnswerEngine.prepare(
        envelope: RichAnswerEnvelope(
            schemaVersion: 2,
            contextRevision: contextRevision,
            narrative: """
            河流材料首先需要同时看区域、路径、点位和尺度，而不是把地点改排成列表。[验收材料：河流地貌]

            <!-- weibei-scene:openui-spatial-layers -->

            抽样问题的关键是窗口怎样改变样本统计量，所以要直接在总体分布上移动窗口。[验收材料：均值与异常值]

            <!-- weibei-scene:openui-distribution-brush -->

            金融假设则要沿依赖链逐层传到结果，单独摆四个输入框看不出机制。[验收材料：现金流传导]

            <!-- weibei-scene:openui-dependency-flow -->

            三块使用不同知识结构，但都保持在同一篇回答里，并共享魏碑的来源与交互边界。
            """,
            expressionPlan: RichAnswerExpressionPlan(
                action: .manipulate,
                summary: "在正文中依次验证空间、分布与依赖传导三种通用深组件",
                families: [.timeAndSpace, .quantityAndCoordinates, .calculationAndConstraints],
                preferredSurface: .inline,
                directManipulation: true
            ),
            scenes: [openUISpatialScene, openUIDistributionScene, openUIDependencyScene],
            evidenceLedger: extendedOpenUIEvidenceLedger,
            fallback: RichAnswerFallback(
                text: "当前扩展 OpenUI 运行时不可用，保留空间、分布与依赖传导的文字说明。",
                reason: "扩展 OpenUI 验收场景降级"
            )
        ),
        environment: RichAnswerEnvironment(
            contextRevision: contextRevision,
            allowedSourceLabels: Set(extendedOpenUIEvidenceLedger.map(\.sourceLabel)),
            allowedAssetIDs: [],
            resourceBudget: RichAnswerResourceBudget(maxScenes: 3)
        )
    )

    private static let openUIInlineFigure = RichAnswerScene(
        id: "openui-inline-figure",
        title: "参数 a 与抛物线形状",
        family: .quantityAndCoordinates,
        objects: [],
        evidenceIDs: ["math-source"],
        placement: .inline,
        program: RichAnswerUIProgram(
            source: """
            $a = 1.2
            root = RichAnswerRoot("互动图解", "参数 a 与抛物线形状", "正文之后的一张可操作插图。", "workbench", [controls, graph, sources])
            controls = LearningStage("controls", "", [slider, live])
            graph = LearningStage("visual", "", [plot])
            sources = LearningStage("evidence", "", [evidence])
            slider = ParameterSlider("a", "参数 a", $a, -3, 3, 0.1, "先跨过 0 看方向，再越过 ±1 看宽窄。")
            live = ParameterReadout("a", $a, "当前读数只解释你正在操作的图像。")
            plot = FunctionPlot("y = ax²", "quadratic", "a", $a, [], -3, 3, 270)
            evidence = EvidenceSnippet("math-source", "验收材料·二次函数", "", "")
            """,
            capabilities: ["parameter-control", "function-plot", "linked-readout", "evidence-jump"],
            directManipulation: true,
            maxHeight: 500,
            graphics: .canvas
        )
    )

    private static let openUISpatialScene = RichAnswerScene(
        id: "openui-spatial-layers",
        title: "空间图层",
        family: .timeAndSpace,
        objects: [],
        evidenceIDs: ["geography-source"],
        placement: .inline,
        program: RichAnswerUIProgram(
            source: """
            $visible = ["basin", "river", "city"]
            $selected = "city-a"
            root = RichAnswerRoot("空间", "图层与点位", "切换图层并点选位置。", "flow", [visual, sources])
            visual = LearningStage("visual", "", [view])
            sources = LearningStage("evidence", "", [evidence])
            basin = SpatialLayer("basin", "流域范围", "region", true, "stone")
            river = SpatialLayer("river", "河流路径", "path", true, "water")
            city = SpatialLayer("city", "聚落点位", "point", true, "cinnabar")
            region = SpatialRegion("basin-a", "basin", "河谷范围", [0.04, 0.20, 0.88, 0.12, 0.96, 0.78, 0.12, 0.90], "stone")
            route = SpatialPath("river-a", "river", "主河道", [0.12, 0.76, 0.42, 0.50, 0.84, 0.26], "primary", "water")
            pointA = SpatialPoint("city-a", "city", "河谷市集", 0.42, 0.50, "河流路径与河谷聚落的交会位置。", "focus", "geography-source")
            pointB = SpatialPoint("city-b", "city", "下游港口", 0.84, 0.26, "下游运输节点。", "normal")
            view = LayeredSpatialView("visible", $visible, "selected", $selected, "河流空间关系", [basin, river, city], [region], [route], [pointA, pointB], 20, "km", "关闭图层或点选位置，观察空间解释怎样变化。")
            evidence = EvidenceSnippet("geography-source", "验收材料·河流地貌", "", "")
            """,
            capabilities: ["layer-toggle", "point-selection", "normalized-spatial-data", "evidence-jump"],
            directManipulation: true,
            maxHeight: 560,
            graphics: .canvas
        )
    )

    private static let openUIDistributionScene = RichAnswerScene(
        id: "openui-distribution-brush",
        title: "分布刷选",
        family: .quantityAndCoordinates,
        objects: [],
        evidenceIDs: ["statistics-source"],
        placement: .inline,
        program: RichAnswerUIProgram(
            source: """
            $center = 40
            $span = 16
            root = RichAnswerRoot("统计", "总体与样本窗口", "拖动样本窗口查看偏差。", "flow", [visual, sources])
            visual = LearningStage("visual", "", [brush])
            sources = LearningStage("evidence", "", [evidence])
            brush = DistributionBrush("center", $center, "span", $span, "总体与当前样本", [21, 28, 31, 33, 35, 36, 38, 39, 40, 41, 43, 45, 47, 52, 58, 67], "分", 10, "拖动阴影窗口，或调节窗口宽度。")
            evidence = EvidenceSnippet("statistics-source", "验收材料·均值与异常值", "", "")
            """,
            capabilities: ["distribution", "brush-selection", "local-statistics", "evidence-jump"],
            directManipulation: true,
            maxHeight: 520,
            graphics: .canvas
        )
    )

    private static let openUIDependencyScene = RichAnswerScene(
        id: "openui-dependency-flow",
        title: "依赖传导",
        family: .calculationAndConstraints,
        objects: [],
        evidenceIDs: ["finance-source"],
        placement: .inline,
        program: RichAnswerUIProgram(
            source: """
            $inputs = [100, 1.08, 0.18, 1.11]
            $focus = 0
            root = RichAnswerRoot("金融", "一期现金流怎样折成现值", "调节输入并查看逐层敏感性。", "flow", [visual, sources])
            visual = LearningStage("visual", "", [flow])
            sources = LearningStage("evidence", "", [evidence])
            revenue = FlowAssumption("revenue", "基准收入", 50, 200, 5, "百万元", "本期收入基数。")
            growthFactor = FlowAssumption("growth-factor", "收入增长倍数", 1, 1.2, 0.01, "×", "1.08 表示增长 8%。")
            cashflowRate = FlowAssumption("cashflow-rate", "现金流率", 0.05, 0.35, 0.01, "×", "收入转成自由现金流的比例。")
            discountFactor = FlowAssumption("discount-factor", "折现倍数", 1.01, 1.25, 0.01, "×", "1.11 对应一期折现率 11%。")
            projectedRevenue = DependencyNode("projected-revenue", "下一期收入", 1, "product", ["revenue", "growth-factor"], [], "百万元", 2, "基准收入乘以增长倍数。")
            freeCashFlow = DependencyNode("free-cash-flow", "下一期自由现金流", 2, "product", ["projected-revenue", "cashflow-rate"], [], "百万元", 2, "下一期收入乘以现金流率。")
            presentValue = DependencyNode("present-value", "一期现金流现值", 3, "ratio", ["free-cash-flow", "discount-factor"], [], "百万元", 2, "自由现金流除以折现倍数。")
            metric = FlowMetric("present-value", "一期现金流现值", "百万元", 2, "primary", "显示当前现值与聚焦输入的一步敏感性。")
            flow = DependencyFlow("inputs", $inputs, "focus", $focus, "一期现金流现值传导", [revenue, growthFactor, cashflowRate, discountFactor], [projectedRevenue, freeCashFlow, presentValue], [metric], "计算链为收入 × 增长倍数 × 现金流率 ÷ 折现倍数。")
            evidence = EvidenceSnippet("finance-source", "验收材料·现金流传导", "", "")
            """,
            capabilities: ["assumption-control", "dependency-graph", "sensitivity", "evidence-jump"],
            directManipulation: true,
            maxHeight: 640,
            graphics: .dom
        )
    )

    private static func example(for scenario: String) -> Example {
        if scenario == "rich-answer-preview" {
            return .quantity
        }
        return Example(rawValue: scenario) ?? .quantity
    }

    private static func scene(_ example: Example) -> RichAnswerScene {
        switch example {
        case .text:
            return literatureScene
        case .quantity:
            return mathematicsScene
        case .process:
            return chemistryScene
        case .relation:
            return biologyScene
        case .timeline:
            return historyScene
        case .space:
            return geographyScene
        case .image:
            return artScene
        case .comparison:
            return physicsScene
        case .calculation:
            return statisticsScene
        case .constraint:
            return allocationConstraintScene
        case .pendulum:
            return pendulumScene
        case .sequence:
            return sequenceScene
        }
    }

    private static let evidenceLedger = [
        RichAnswerEvidence(
            id: "literature-source",
            sourceLabel: "[验收材料：诗句意象]",
            excerpt: "大漠孤烟直，长河落日圆。材料提示关注垂直线、水平线与圆形意象形成的空间秩序。"
        ),
        RichAnswerEvidence(
            id: "math-source",
            sourceLabel: "[验收材料：二次函数]",
            excerpt: "函数 y = x² 在 x 为 -2、-1、0、1、2 时，对应 y 为 4、1、0、1、4。"
        ),
        RichAnswerEvidence(
            id: "chemistry-source",
            sourceLabel: "[验收材料：离子键]",
            excerpt: "钠原子失去一个最外层电子形成钠离子，氯原子得到该电子形成氯离子，异号离子之间产生静电吸引。"
        ),
        RichAnswerEvidence(
            id: "biology-source",
            sourceLabel: "[验收材料：光合作用]",
            excerpt: "二氧化碳和水在光能参与下，于叶绿体中形成有机物并释放氧气。"
        ),
        RichAnswerEvidence(
            id: "history-source",
            sourceLabel: "[验收材料：历史时间线]",
            excerpt: "材料按 1919、1921、1924 三个时间点列出事件，并要求先确认先后关系，再讨论影响。"
        ),
        RichAnswerEvidence(
            id: "geography-source",
            sourceLabel: "[验收材料：河流地貌]",
            excerpt: "河流由上游进入中游与下游，坡降、流速和沉积特征随路径改变。"
        ),
        RichAnswerEvidence(
            id: "art-source",
            sourceLabel: "[验收材料：版面构图]",
            excerpt: "Kepler-16b 旅行海报使用大标题、双星、人物视线和底部标语构成真实版面层级。Credit: NASA/JPL-Caltech.",
            assetIDs: [artVerificationAssetID]
        ),
        RichAnswerEvidence(
            id: "physics-source",
            sourceLabel: "[验收材料：斜面受力]",
            excerpt: "物块沿斜面移动时，重力始终竖直向下，支持力始终垂直于斜面。"
        ),
        RichAnswerEvidence(
            id: "statistics-source",
            sourceLabel: "[验收材料：均值与异常值]",
            excerpt: "固定四个观测值后，提高第五个观测值会明显拉高均值。"
        ),
        RichAnswerEvidence(
            id: "allocation-source",
            sourceLabel: "[验收材料：复习时间分配]",
            excerpt: "本次复习总时长固定为 60 分钟；概念理解时间与练习时间之和必须始终等于 60 分钟。"
        ),
        RichAnswerEvidence(
            id: "finance-source",
            sourceLabel: "[验收材料：现金流传导]",
            excerpt: "一期自由现金流现值 = 基准收入 × 收入增长倍数 × 现金流率 ÷ 折现倍数。"
        ),
        RichAnswerEvidence(
            id: "pendulum-source",
            sourceLabel: "[验收材料：单摆周期]",
            excerpt: "在小角度近似下，单摆周期 T = 2π√(L/g)，因此周期随摆长 L 的平方根增长。"
        ),
        RichAnswerEvidence(
            id: "sequence-source",
            sourceLabel: "[验收材料：论证路径]",
            excerpt: "论证先提出公共空间价值，再以停留形成联系作为桥接，同时保留替代原因，最后收敛到有限结论。"
        ),
    ]

    private static let literatureScene = generatedScene(
        id: "literature-annotation",
        title: "文学 · 原文与意象批注",
        family: .textAndAlignment,
        evidenceID: "literature-source",
        nodes: [
            RichAnswerUINode(id: "lit-root", role: .vstack, children: ["lit-head", "lit-columns", "lit-alignment-canvas", "lit-alignment-controls", "lit-source"], spacing: .loose),
            RichAnswerUINode(id: "lit-head", role: .text, label: "文学 · 原文批注", text: "不是把解释堆在原文下面，而是让原句与观察依据互相对照。", evidenceIDs: ["literature-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "lit-columns", role: .hstack, children: ["lit-quote-panel", "lit-notes"], spacing: .loose),
            RichAnswerUINode(id: "lit-quote-panel", role: .panel, children: ["lit-quote"], size: .large),
            RichAnswerUINode(id: "lit-quote", role: .text, label: "原句", text: "大漠孤烟直\n长河落日圆", evidenceIDs: ["literature-source"], emphasis: .strong, alignment: .center),
            RichAnswerUINode(id: "lit-notes", role: .vstack, children: ["lit-note-a", "lit-note-b", "lit-note-c"], spacing: .loose),
            RichAnswerUINode(id: "lit-note-a", role: .text, label: "垂直", text: "“孤烟直”把视线向上拉。", evidenceIDs: ["literature-source"], tone: .accent),
            RichAnswerUINode(id: "lit-note-b", role: .text, label: "水平", text: "“长河”展开辽阔的横向尺度。", evidenceIDs: ["literature-source"], tone: .muted),
            RichAnswerUINode(id: "lit-note-c", role: .text, label: "圆形", text: "“落日圆”成为稳定的视觉焦点。", evidenceIDs: ["literature-source"]),
            RichAnswerUINode(id: "lit-alignment-canvas", role: .canvas, children: ["lit-vertical-region", "lit-horizontal-region", "lit-circle-region"], label: "意象空间对齐", size: .compact),
            RichAnswerUINode(id: "lit-vertical-region", role: .region, label: "孤烟 · 垂直", bindingID: "lit-alignment", evidenceIDs: ["literature-source"], region: RichAnswerRegion(x: 0.18, y: 0.12, width: 0.12, height: 0.72), tone: .accent),
            RichAnswerUINode(id: "lit-horizontal-region", role: .region, label: "长河 · 水平", bindingID: "lit-alignment", evidenceIDs: ["literature-source"], region: RichAnswerRegion(x: 0.08, y: 0.68, width: 0.78, height: 0.12), tone: .muted),
            RichAnswerUINode(id: "lit-circle-region", role: .region, label: "落日 · 圆形焦点", bindingID: "lit-alignment", evidenceIDs: ["literature-source"], region: RichAnswerRegion(x: 0.68, y: 0.18, width: 0.18, height: 0.22), tone: .positive),
            RichAnswerUINode(id: "lit-alignment-controls", role: .hstack, children: ["lit-alignment-toggle", "lit-alignment-count"], spacing: .regular),
            RichAnswerUINode(id: "lit-alignment-toggle", role: .toggle, label: "显示意象空间标记", bindingID: "lit-alignment"),
            RichAnswerUINode(id: "lit-alignment-count", role: .metric, label: "当前显示标记", unit: "个", datasetID: "lit-alignment-state", bindingID: "lit-alignment", evidenceIDs: ["literature-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "lit-source", role: .evidence, evidenceIDs: ["literature-source"]),
        ],
        datasets: [
            RichAnswerUIDataset(id: "lit-alignment-state", rows: [
                RichAnswerUIDataRow(id: "lit-alignment-hidden", x: 0, y: 0, value: 0, result: 0, label: "隐藏标记", evidenceIDs: ["literature-source"]),
                RichAnswerUIDataRow(id: "lit-alignment-visible", x: 1, y: 1, value: 1, result: 3, label: "显示三个标记", evidenceIDs: ["literature-source"]),
            ]),
        ],
        bindings: [RichAnswerUIBinding(id: "lit-alignment", label: "意象空间标记", minimum: 0, maximum: 1, step: 1, initialValue: 1)]
    )

    private static let mathematicsScene = generatedScene(
        id: "mathematics-function",
        title: "数学 · 二次函数探针",
        family: .quantityAndCoordinates,
        evidenceID: "math-source",
        nodes: [
            RichAnswerUINode(id: "math-root", role: .vstack, children: ["math-head", "math-top", "math-canvas", "math-probe", "math-source"], spacing: .regular),
            RichAnswerUINode(id: "math-head", role: .text, label: "数学 · y = x²", text: "拖动 x，曲线上的点与函数值同步更新。", evidenceIDs: ["math-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "math-top", role: .hstack, children: ["math-formula", "math-value"]),
            RichAnswerUINode(id: "math-formula", role: .text, label: "函数", text: "y = x²", evidenceIDs: ["math-source"], emphasis: .strong),
            RichAnswerUINode(id: "math-value", role: .metric, label: "当前 y", unit: "", datasetID: "math-curve", bindingID: "math-x", evidenceIDs: ["math-source"], tone: .accent, emphasis: .strong, alignment: .trailing),
            RichAnswerUINode(id: "math-canvas", role: .canvas, children: ["math-axis", "math-line", "math-points"], xAxis: RichAnswerAxis(label: "x", minimum: -2, maximum: 2), yAxis: RichAnswerAxis(label: "y", minimum: 0, maximum: 4), size: .large),
            RichAnswerUINode(id: "math-axis", role: .axis, tone: .gridline),
            RichAnswerUINode(id: "math-line", role: .path, datasetID: "math-curve", bindingID: "math-x", evidenceIDs: ["math-source"], tone: .ink, emphasis: .strong),
            RichAnswerUINode(id: "math-points", role: .point, datasetID: "math-curve", bindingID: "math-x", evidenceIDs: ["math-source"], tone: .muted),
            RichAnswerUINode(id: "math-probe", role: .probe, label: "拖动 x", bindingID: "math-x"),
            RichAnswerUINode(id: "math-source", role: .evidence, evidenceIDs: ["math-source"]),
        ],
        datasets: [RichAnswerUIDataset(id: "math-curve", rows: functionRows)],
        bindings: [RichAnswerUIBinding(id: "math-x", label: "x", minimum: -2, maximum: 2, step: 0.25, initialValue: 1)]
    )

    private static let chemistryScene = generatedScene(
        id: "chemistry-electron-transfer",
        title: "化学 · 离子键电子转移",
        family: .processAndState,
        evidenceID: "chemistry-source",
        nodes: [
            RichAnswerUINode(id: "chem-root", role: .vstack, children: ["chem-head", "chem-layout", "chem-slider", "chem-source"], spacing: .regular),
            RichAnswerUINode(id: "chem-head", role: .text, label: "化学 · NaCl 怎样形成", text: "拖动电子，观察钠失去一个电子、氯得到一个电子的微观过程。", evidenceIDs: ["chemistry-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "chem-layout", role: .hstack, children: ["chem-canvas", "chem-side"], spacing: .loose),
            RichAnswerUINode(id: "chem-canvas", role: .canvas, children: ["chem-na", "chem-cl", "chem-valence", "chem-electron", "chem-labels"], size: .large),
            RichAnswerUINode(id: "chem-na", role: .shape, label: "Na", evidenceIDs: ["chemistry-source"], region: RichAnswerRegion(x: 0.08, y: 0.19, width: 0.28, height: 0.62), shape: .circle, fill: .soft, tone: .ink, emphasis: .strong, size: .large),
            RichAnswerUINode(id: "chem-cl", role: .shape, label: "Cl", evidenceIDs: ["chemistry-source"], region: RichAnswerRegion(x: 0.64, y: 0.13, width: 0.30, height: 0.70), shape: .circle, fill: .soft, tone: .positive, emphasis: .strong, size: .large),
            RichAnswerUINode(id: "chem-valence", role: .dotMatrix, datasetID: "chem-valence-electrons", evidenceIDs: ["chemistry-source"], fill: .solid, tone: .muted, size: .compact),
            RichAnswerUINode(id: "chem-electron", role: .shape, label: "e⁻", datasetID: "chem-electron-path", bindingID: "chem-transfer", evidenceIDs: ["chemistry-source"], region: RichAnswerRegion(x: 0, y: 0, width: 0.06, height: 0.12), shape: .circle, fill: .solid, tone: .accent, emphasis: .strong, size: .compact),
            RichAnswerUINode(id: "chem-labels", role: .label, datasetID: "chem-state-labels", evidenceIDs: ["chemistry-source"], tone: .muted),
            RichAnswerUINode(id: "chem-side", role: .vstack, children: ["chem-donor", "chem-acceptor", "chem-result"], spacing: .loose),
            RichAnswerUINode(id: "chem-donor", role: .text, label: "电子给体", text: "Na 失去最外层电子后成为 Na⁺。", evidenceIDs: ["chemistry-source"], tone: .muted),
            RichAnswerUINode(id: "chem-acceptor", role: .text, label: "电子受体", text: "Cl 得到电子后成为 Cl⁻。", evidenceIDs: ["chemistry-source"], tone: .positive),
            RichAnswerUINode(id: "chem-result", role: .text, label: "形成", text: "异号离子之间产生静电吸引。", evidenceIDs: ["chemistry-source"], emphasis: .strong),
            RichAnswerUINode(id: "chem-slider", role: .slider, label: "移动最外层电子", bindingID: "chem-transfer"),
            RichAnswerUINode(id: "chem-source", role: .evidence, evidenceIDs: ["chemistry-source"]),
        ],
        datasets: [
            RichAnswerUIDataset(id: "chem-valence-electrons", rows: [
                RichAnswerUIDataRow(id: "chem-na-dot-a", x: 0.22, y: 0.76, evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-na-dot-b", x: 0.14, y: 0.52, evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-na-dot-c", x: 0.27, y: 0.31, evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-cl-dot-a", x: 0.73, y: 0.72, evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-cl-dot-b", x: 0.84, y: 0.72, evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-cl-dot-c", x: 0.88, y: 0.53, evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-cl-dot-d", x: 0.82, y: 0.32, evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-cl-dot-e", x: 0.71, y: 0.35, evidenceIDs: ["chemistry-source"]),
            ]),
            RichAnswerUIDataset(id: "chem-electron-path", rows: [
                RichAnswerUIDataRow(id: "chem-electron-start", x: 0.34, y: 0.56, value: 0, label: "e⁻", evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-electron-end", x: 0.67, y: 0.56, value: 1, label: "e⁻", evidenceIDs: ["chemistry-source"]),
            ]),
            RichAnswerUIDataset(id: "chem-state-labels", rows: [
                RichAnswerUIDataRow(id: "chem-label-na", x: 0.22, y: 0.08, label: "Na → Na⁺", evidenceIDs: ["chemistry-source"]),
                RichAnswerUIDataRow(id: "chem-label-cl", x: 0.78, y: 0.08, label: "Cl → Cl⁻", evidenceIDs: ["chemistry-source"]),
            ]),
        ],
        bindings: [RichAnswerUIBinding(id: "chem-transfer", label: "电子转移", minimum: 0, maximum: 1, step: 0.05, initialValue: 0)]
    )

    private static let biologyScene = generatedScene(
        id: "biology-cell-structure",
        title: "生物 · 植物细胞结构",
        family: .relationAndEvidence,
        evidenceID: "biology-source",
        nodes: [
            RichAnswerUINode(id: "bio-root", role: .vstack, children: ["bio-head", "bio-layout", "bio-source"], spacing: .regular),
            RichAnswerUINode(id: "bio-head", role: .text, label: "生物 · 光合作用发生在哪里", text: "先定位植物细胞，再看叶绿体与其他细胞器的空间关系。", evidenceIDs: ["biology-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "bio-layout", role: .hstack, children: ["bio-canvas", "bio-side"], spacing: .loose),
            RichAnswerUINode(id: "bio-canvas", role: .canvas, children: ["bio-cell", "bio-vacuole", "bio-nucleus", "bio-chloroplasts", "bio-light", "bio-labels"], size: .large),
            RichAnswerUINode(id: "bio-cell", role: .shape, evidenceIDs: ["biology-source"], region: RichAnswerRegion(x: 0.04, y: 0.08, width: 0.92, height: 0.82), shape: .ellipse, fill: .soft, tone: .positive, emphasis: .strong, size: .large),
            RichAnswerUINode(id: "bio-vacuole", role: .shape, label: "液泡", evidenceIDs: ["biology-source"], region: RichAnswerRegion(x: 0.32, y: 0.27, width: 0.36, height: 0.42), shape: .roundedRectangle, fill: .soft, tone: .muted, size: .large),
            RichAnswerUINode(id: "bio-nucleus", role: .shape, label: "细胞核", evidenceIDs: ["biology-source"], region: RichAnswerRegion(x: 0.14, y: 0.34, width: 0.18, height: 0.28), shape: .circle, fill: .soft, tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "bio-chloroplasts", role: .shape, datasetID: "bio-chloroplast-positions", evidenceIDs: ["biology-source"], region: RichAnswerRegion(x: 0, y: 0, width: 0.16, height: 0.12), shape: .ellipse, fill: .solid, tone: .positive, size: .regular),
            RichAnswerUINode(id: "bio-light", role: .shape, label: "光能", evidenceIDs: ["biology-source"], region: RichAnswerRegion(x: 0.74, y: 0.10, width: 0.14, height: 0.20), shape: .circle, fill: .solid, tone: .accent, size: .regular),
            RichAnswerUINode(id: "bio-labels", role: .label, datasetID: "bio-structure-labels", evidenceIDs: ["biology-source"], tone: .ink),
            RichAnswerUINode(id: "bio-side", role: .vstack, children: ["bio-place", "bio-input", "bio-output", "bio-select"], spacing: .loose),
            RichAnswerUINode(id: "bio-place", role: .text, label: "场所", text: "叶绿体吸收光能，是光合作用的主要场所。", evidenceIDs: ["biology-source"], tone: .positive, emphasis: .strong),
            RichAnswerUINode(id: "bio-input", role: .text, label: "原料", text: "二氧化碳 + 水", evidenceIDs: ["biology-source"], tone: .muted),
            RichAnswerUINode(id: "bio-output", role: .text, label: "产物", text: "有机物 + 氧气", evidenceIDs: ["biology-source"]),
            RichAnswerUINode(id: "bio-select", role: .select, label: "点选细胞结构查看边界"),
            RichAnswerUINode(id: "bio-source", role: .evidence, evidenceIDs: ["biology-source"]),
        ],
        datasets: [
            RichAnswerUIDataset(id: "bio-chloroplast-positions", rows: [
                RichAnswerUIDataRow(id: "bio-chloroplast-a", x: 0.34, y: 0.76, evidenceIDs: ["biology-source"]),
                RichAnswerUIDataRow(id: "bio-chloroplast-b", x: 0.68, y: 0.72, evidenceIDs: ["biology-source"]),
                RichAnswerUIDataRow(id: "bio-chloroplast-c", x: 0.76, y: 0.36, evidenceIDs: ["biology-source"]),
                RichAnswerUIDataRow(id: "bio-chloroplast-d", x: 0.38, y: 0.20, evidenceIDs: ["biology-source"]),
            ]),
            RichAnswerUIDataset(id: "bio-structure-labels", rows: [
                RichAnswerUIDataRow(id: "bio-cell-label", x: 0.10, y: 0.88, label: "植物细胞", evidenceIDs: ["biology-source"]),
                RichAnswerUIDataRow(id: "bio-chloroplast-label", x: 0.64, y: 0.80, label: "叶绿体", evidenceIDs: ["biology-source"]),
            ]),
        ]
    )

    private static let historyScene = generatedScene(
        id: "history-timeline",
        title: "历史 · 多事件时间线",
        family: .timeAndSpace,
        evidenceID: "history-source",
        nodes: [
            RichAnswerUINode(id: "history-root", role: .vstack, children: ["history-head", "history-canvas", "history-scrub", "history-source"], spacing: .regular),
            RichAnswerUINode(id: "history-head", role: .text, label: "历史 · 先后关系", text: "先确认材料给出的三个时间点，再讨论影响，不把相关性自动画成因果。", evidenceIDs: ["history-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "history-canvas", role: .canvas, children: ["history-line", "history-points", "history-labels"], xAxis: RichAnswerAxis(label: "年份", minimum: 1919, maximum: 1924), size: .regular),
            RichAnswerUINode(id: "history-line", role: .path, datasetID: "history-events", bindingID: "history-year", evidenceIDs: ["history-source"], tone: .muted),
            RichAnswerUINode(id: "history-points", role: .point, datasetID: "history-events", bindingID: "history-year", evidenceIDs: ["history-source"], tone: .ink),
            RichAnswerUINode(id: "history-labels", role: .label, datasetID: "history-events", evidenceIDs: ["history-source"], tone: .muted),
            RichAnswerUINode(id: "history-scrub", role: .scrubber, label: "拖动年份", bindingID: "history-year"),
            RichAnswerUINode(id: "history-source", role: .evidence, evidenceIDs: ["history-source"]),
        ],
        datasets: [RichAnswerUIDataset(id: "history-events", rows: [
            RichAnswerUIDataRow(id: "history-1919", x: 0.08, y: 0.50, value: 1919, label: "1919 · 事件一", evidenceIDs: ["history-source"]),
            RichAnswerUIDataRow(id: "history-1921", x: 0.42, y: 0.50, value: 1921, label: "1921 · 事件二", evidenceIDs: ["history-source"]),
            RichAnswerUIDataRow(id: "history-1924", x: 0.92, y: 0.50, value: 1924, label: "1924 · 事件三", evidenceIDs: ["history-source"]),
        ])],
        bindings: [RichAnswerUIBinding(id: "history-year", label: "年份", minimum: 1919, maximum: 1924, step: 1, initialValue: 1921)]
    )

    private static let geographyScene = generatedScene(
        id: "geography-route",
        title: "地理 · 河流空间路径",
        family: .timeAndSpace,
        evidenceID: "geography-source",
        nodes: [
            RichAnswerUINode(id: "geo-root", role: .vstack, children: ["geo-head", "geo-canvas", "geo-scrub", "geo-source"], spacing: .regular),
            RichAnswerUINode(id: "geo-head", role: .text, label: "地理 · 上中下游", text: "区域轮廓、河道路径、位置节点和标签叠在同一张画布上。", evidenceIDs: ["geography-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "geo-canvas", role: .canvas, children: ["geo-area", "geo-path", "geo-points", "geo-labels"], size: .large),
            RichAnswerUINode(id: "geo-area", role: .area, datasetID: "geo-basin", evidenceIDs: ["geography-source"], tone: .gridline, emphasis: .quiet),
            RichAnswerUINode(id: "geo-path", role: .path, datasetID: "geo-river", bindingID: "geo-stage", evidenceIDs: ["geography-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "geo-points", role: .point, datasetID: "geo-river", bindingID: "geo-stage", evidenceIDs: ["geography-source"], tone: .ink),
            RichAnswerUINode(id: "geo-labels", role: .label, datasetID: "geo-river", evidenceIDs: ["geography-source"], tone: .muted),
            RichAnswerUINode(id: "geo-scrub", role: .scrubber, label: "沿河流观察", bindingID: "geo-stage"),
            RichAnswerUINode(id: "geo-source", role: .evidence, evidenceIDs: ["geography-source"]),
        ],
        datasets: [
            RichAnswerUIDataset(id: "geo-basin", rows: [
                RichAnswerUIDataRow(id: "geo-area-a", x: 0.04, y: 0.18, evidenceIDs: ["geography-source"]),
                RichAnswerUIDataRow(id: "geo-area-b", x: 0.18, y: 0.86, evidenceIDs: ["geography-source"]),
                RichAnswerUIDataRow(id: "geo-area-c", x: 0.72, y: 0.78, evidenceIDs: ["geography-source"]),
                RichAnswerUIDataRow(id: "geo-area-d", x: 0.96, y: 0.26, evidenceIDs: ["geography-source"]),
            ]),
            RichAnswerUIDataset(id: "geo-river", rows: [
                RichAnswerUIDataRow(id: "geo-upstream", x: 0.10, y: 0.78, value: 1, label: "上游 · 坡陡", evidenceIDs: ["geography-source"]),
                RichAnswerUIDataRow(id: "geo-midstream", x: 0.50, y: 0.54, value: 2, label: "中游 · 河谷展开", evidenceIDs: ["geography-source"]),
                RichAnswerUIDataRow(id: "geo-downstream", x: 0.90, y: 0.24, value: 3, label: "下游 · 沉积增强", evidenceIDs: ["geography-source"]),
            ]),
        ],
        bindings: [RichAnswerUIBinding(id: "geo-stage", label: "河段", minimum: 1, maximum: 3, step: 1, initialValue: 1)]
    )

    private static let artScene = generatedScene(
        id: "art-overlay",
        title: "艺术设计 · 构图叠层",
        family: .imageAndOverlay,
        evidenceID: "art-source",
        nodes: [
            RichAnswerUINode(id: "art-root", role: .vstack, children: ["art-head", "art-canvas", "art-controls", "art-source"], spacing: .regular),
            RichAnswerUINode(id: "art-head", role: .text, label: "艺术设计 · 版面观察", text: "比例线只是辅助观察，区域标注可以显式开关。", evidenceIDs: ["art-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "art-canvas", role: .canvas, children: ["art-image", "art-grid", "art-focus", "art-space"], size: .large),
            RichAnswerUINode(id: "art-image", role: .image, assetID: artVerificationAssetID, evidenceIDs: ["art-source"]),
            RichAnswerUINode(id: "art-grid", role: .line, datasetID: "art-thirds", evidenceIDs: ["art-source"], tone: .gridline, emphasis: .quiet),
            RichAnswerUINode(id: "art-focus", role: .region, label: "视觉重心", bindingID: "art-overlay", evidenceIDs: ["art-source"], region: RichAnswerRegion(x: 0.54, y: 0.18, width: 0.28, height: 0.24), tone: .accent),
            RichAnswerUINode(id: "art-space", role: .region, label: "主要留白", bindingID: "art-overlay", evidenceIDs: ["art-source"], region: RichAnswerRegion(x: 0.12, y: 0.56, width: 0.34, height: 0.26), tone: .muted),
            RichAnswerUINode(id: "art-controls", role: .hstack, children: ["art-toggle", "art-select"]),
            RichAnswerUINode(id: "art-toggle", role: .toggle, label: "显示观察区域", bindingID: "art-overlay"),
            RichAnswerUINode(id: "art-select", role: .select, label: "点选区域查看状态"),
            RichAnswerUINode(id: "art-source", role: .evidence, evidenceIDs: ["art-source"]),
        ],
        datasets: [RichAnswerUIDataset(id: "art-thirds", rows: [
            RichAnswerUIDataRow(id: "art-v1", x: 0.33, y: 0.04, x2: 0.33, y2: 0.96, evidenceIDs: ["art-source"]),
            RichAnswerUIDataRow(id: "art-v2", x: 0.66, y: 0.04, x2: 0.66, y2: 0.96, evidenceIDs: ["art-source"]),
            RichAnswerUIDataRow(id: "art-h1", x: 0.04, y: 0.33, x2: 0.96, y2: 0.33, evidenceIDs: ["art-source"]),
            RichAnswerUIDataRow(id: "art-h2", x: 0.04, y: 0.66, x2: 0.96, y2: 0.66, evidenceIDs: ["art-source"]),
        ])],
        bindings: [RichAnswerUIBinding(id: "art-overlay", label: "观察区域", minimum: 0, maximum: 1, step: 1, initialValue: 1)]
    )

    private static let physicsScene = generatedScene(
        id: "physics-incline",
        title: "物理 · 斜面位置受力比较",
        family: .comparisonAndEvaluation,
        evidenceID: "physics-source",
        nodes: [
            RichAnswerUINode(id: "physics-root", role: .vstack, children: ["physics-head", "physics-layout", "physics-slider", "physics-source"], spacing: .regular),
            RichAnswerUINode(id: "physics-head", role: .text, label: "物理 · 低位、中位与高位", text: "拖动物块比较三个位置：位置改变，但两种力的方向基准不变。", evidenceIDs: ["physics-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "physics-layout", role: .hstack, children: ["physics-canvas", "physics-side"], spacing: .loose),
            RichAnswerUINode(id: "physics-canvas", role: .canvas, children: ["physics-plane", "physics-block", "physics-gravity", "physics-normal", "physics-labels"], size: .large),
            RichAnswerUINode(id: "physics-plane", role: .area, datasetID: "physics-plane-shape", evidenceIDs: ["physics-source"], fill: .soft, tone: .muted),
            RichAnswerUINode(id: "physics-block", role: .shape, label: "物块", datasetID: "physics-block-positions", bindingID: "physics-position", evidenceIDs: ["physics-source"], region: RichAnswerRegion(x: 0, y: 0, width: 0.12, height: 0.16), shape: .roundedRectangle, fill: .solid, tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "physics-gravity", role: .vector, datasetID: "physics-gravity-vectors", bindingID: "physics-position", evidenceIDs: ["physics-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "physics-normal", role: .vector, datasetID: "physics-normal-vectors", bindingID: "physics-position", evidenceIDs: ["physics-source"], tone: .positive, emphasis: .strong),
            RichAnswerUINode(id: "physics-labels", role: .label, datasetID: "physics-force-labels", evidenceIDs: ["physics-source"], tone: .ink),
            RichAnswerUINode(id: "physics-side", role: .vstack, children: ["physics-position-value", "physics-position-comparison", "physics-gravity-note", "physics-normal-note"], spacing: .loose),
            RichAnswerUINode(id: "physics-position-value", role: .metric, label: "沿斜面位置", unit: "m", datasetID: "physics-block-positions", bindingID: "physics-position", evidenceIDs: ["physics-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "physics-position-comparison", role: .hstack, children: ["physics-low-state", "physics-high-state"], spacing: .regular),
            RichAnswerUINode(id: "physics-low-state", role: .text, label: "低位 0 m", text: "g ↓；N ⟂ 斜面", evidenceIDs: ["physics-source"], tone: .muted),
            RichAnswerUINode(id: "physics-high-state", role: .text, label: "高位 10 m", text: "g ↓；N ⟂ 斜面", evidenceIDs: ["physics-source"], tone: .accent),
            RichAnswerUINode(id: "physics-gravity-note", role: .text, label: "比较结论 · 重力 g", text: "低位、中位和高位都竖直向下。", evidenceIDs: ["physics-source"], tone: .accent),
            RichAnswerUINode(id: "physics-normal-note", role: .text, label: "比较结论 · 支持力 N", text: "低位、中位和高位都垂直于斜面。", evidenceIDs: ["physics-source"], tone: .positive),
            RichAnswerUINode(id: "physics-slider", role: .slider, label: "沿斜面拖动物块", bindingID: "physics-position"),
            RichAnswerUINode(id: "physics-source", role: .evidence, evidenceIDs: ["physics-source"]),
        ],
        datasets: [
            RichAnswerUIDataset(id: "physics-plane-shape", rows: [
                RichAnswerUIDataRow(id: "physics-plane-left", x: 0.08, y: 0.10, evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-plane-right", x: 0.86, y: 0.10, evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-plane-top", x: 0.88, y: 0.72, evidenceIDs: ["physics-source"]),
            ]),
            RichAnswerUIDataset(id: "physics-block-positions", rows: [
                RichAnswerUIDataRow(id: "physics-block-low", x: 0.25, y: 0.28, value: 0, result: 0, evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-block-mid", x: 0.50, y: 0.47, value: 5, result: 5, evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-block-high", x: 0.75, y: 0.66, value: 10, result: 10, evidenceIDs: ["physics-source"]),
            ]),
            RichAnswerUIDataset(id: "physics-gravity-vectors", rows: [
                RichAnswerUIDataRow(id: "physics-g-low", x: 0.25, y: 0.28, x2: 0.25, y2: 0.09, value: 0, evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-g-mid", x: 0.50, y: 0.47, x2: 0.50, y2: 0.28, value: 5, evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-g-high", x: 0.75, y: 0.66, x2: 0.75, y2: 0.47, value: 10, evidenceIDs: ["physics-source"]),
            ]),
            RichAnswerUIDataset(id: "physics-normal-vectors", rows: [
                RichAnswerUIDataRow(id: "physics-n-low", x: 0.25, y: 0.28, x2: 0.16, y2: 0.41, value: 0, evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-n-mid", x: 0.50, y: 0.47, x2: 0.41, y2: 0.60, value: 5, evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-n-high", x: 0.75, y: 0.66, x2: 0.66, y2: 0.79, value: 10, evidenceIDs: ["physics-source"]),
            ]),
            RichAnswerUIDataset(id: "physics-force-labels", rows: [
                RichAnswerUIDataRow(id: "physics-g-label", x: 0.54, y: 0.25, label: "重力 g", evidenceIDs: ["physics-source"]),
                RichAnswerUIDataRow(id: "physics-n-label", x: 0.38, y: 0.66, label: "支持力 N", evidenceIDs: ["physics-source"]),
            ]),
        ],
        bindings: [RichAnswerUIBinding(id: "physics-position", label: "沿斜面位置", minimum: 0, maximum: 10, step: 0.5, initialValue: 5, unit: "m")]
    )

    private static let statisticsScene = generatedScene(
        id: "statistics-outlier",
        title: "统计 · 异常值实验",
        family: .calculationAndConstraints,
        evidenceID: "statistics-source",
        nodes: [
            RichAnswerUINode(id: "stats-root", role: .vstack, children: ["stats-head", "stats-top", "stats-canvas", "stats-slider", "stats-source"], spacing: .regular),
            RichAnswerUINode(id: "stats-head", role: .text, label: "统计 · 异常值怎样拉动均值", text: "固定四个观测值，只改变第五个值。", evidenceIDs: ["statistics-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "stats-top", role: .hstack, children: ["stats-data", "stats-mean"], spacing: .loose),
            RichAnswerUINode(id: "stats-data", role: .text, label: "固定数据", text: "2, 3, 3, 4, x", evidenceIDs: ["statistics-source"], emphasis: .strong),
            RichAnswerUINode(id: "stats-mean", role: .metric, label: "当前均值", datasetID: "stats-samples", bindingID: "stats-outlier", evidenceIDs: ["statistics-source"], tone: .accent, emphasis: .strong, alignment: .trailing),
            RichAnswerUINode(id: "stats-canvas", role: .canvas, children: ["stats-bars"], size: .large),
            RichAnswerUINode(id: "stats-bars", role: .bar, datasetID: "stats-samples", bindingID: "stats-outlier", evidenceIDs: ["statistics-source"], fill: .solid, tone: .ink, emphasis: .strong),
            RichAnswerUINode(id: "stats-slider", role: .slider, label: "第五个观测值", bindingID: "stats-outlier"),
            RichAnswerUINode(id: "stats-source", role: .evidence, evidenceIDs: ["statistics-source"]),
        ],
        datasets: [RichAnswerUIDataset(id: "stats-samples", rows: [
            RichAnswerUIDataRow(id: "stats-x4", x: 0.10, y: 0.40, value: 4, result: 3.2, label: "x=4", evidenceIDs: ["statistics-source"]),
            RichAnswerUIDataRow(id: "stats-x8", x: 0.30, y: 0.50, value: 8, result: 4.0, label: "x=8", evidenceIDs: ["statistics-source"]),
            RichAnswerUIDataRow(id: "stats-x12", x: 0.50, y: 0.60, value: 12, result: 4.8, label: "x=12", evidenceIDs: ["statistics-source"]),
            RichAnswerUIDataRow(id: "stats-x16", x: 0.70, y: 0.70, value: 16, result: 5.6, label: "x=16", evidenceIDs: ["statistics-source"]),
            RichAnswerUIDataRow(id: "stats-x20", x: 0.90, y: 0.80, value: 20, result: 6.4, label: "x=20", evidenceIDs: ["statistics-source"]),
        ])],
        bindings: [RichAnswerUIBinding(id: "stats-outlier", label: "异常值", minimum: 4, maximum: 20, step: 1, initialValue: 12)]
    )

    private static let allocationConstraintScene = generatedScene(
        id: "study-time-allocation",
        title: "学习计划 · 固定总时长分配",
        family: .calculationAndConstraints,
        evidenceID: "allocation-source",
        nodes: [
            RichAnswerUINode(id: "allocation-root", role: .vstack, children: ["allocation-head", "allocation-metrics", "allocation-canvas", "allocation-state-control", "allocation-source"], spacing: .regular),
            RichAnswerUINode(id: "allocation-head", role: .text, label: "约束 · 总计 60 分钟", text: "调整概念理解时间，练习时间自动补足；两项之和始终保持 60 分钟。", evidenceIDs: ["allocation-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "allocation-metrics", role: .hstack, children: ["allocation-concept-metric", "allocation-practice-metric", "allocation-total"], spacing: .loose),
            RichAnswerUINode(id: "allocation-concept-metric", role: .metric, label: "概念理解", unit: "分钟", datasetID: "allocation-concept", bindingID: "allocation-concept-time", evidenceIDs: ["allocation-source"], tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "allocation-practice-metric", role: .metric, label: "练习", unit: "分钟", datasetID: "allocation-practice", bindingID: "allocation-concept-time", evidenceIDs: ["allocation-source"], tone: .positive, emphasis: .strong),
            RichAnswerUINode(id: "allocation-total", role: .text, label: "硬约束", text: "概念理解 + 练习 = 60 分钟", evidenceIDs: ["allocation-source"], emphasis: .strong),
            RichAnswerUINode(id: "allocation-canvas", role: .canvas, children: ["allocation-concept-bar", "allocation-practice-bar"], label: "时间分配", yAxis: RichAnswerAxis(label: "分钟", minimum: 0, maximum: 60, unit: "分钟"), size: .compact),
            RichAnswerUINode(id: "allocation-concept-bar", role: .bar, label: "概念理解", datasetID: "allocation-concept", bindingID: "allocation-concept-time", evidenceIDs: ["allocation-source"], fill: .solid, tone: .accent, emphasis: .strong),
            RichAnswerUINode(id: "allocation-practice-bar", role: .bar, label: "练习", datasetID: "allocation-practice", bindingID: "allocation-concept-time", evidenceIDs: ["allocation-source"], fill: .solid, tone: .positive, emphasis: .strong),
            RichAnswerUINode(id: "allocation-state-control", role: .sequence, label: "选择分配方案", datasetID: "allocation-states", bindingID: "allocation-concept-time", evidenceIDs: ["allocation-source"], tone: .accent),
            RichAnswerUINode(id: "allocation-source", role: .evidence, evidenceIDs: ["allocation-source"]),
        ],
        datasets: [
            RichAnswerUIDataset(id: "allocation-concept", rows: [
                RichAnswerUIDataRow(id: "allocation-concept-10", x: 0.30, y: 10.0 / 60.0, value: 10, result: 10, label: "概念 10 分钟", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-concept-20", x: 0.30, y: 20.0 / 60.0, value: 20, result: 20, label: "概念 20 分钟", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-concept-30", x: 0.30, y: 30.0 / 60.0, value: 30, result: 30, label: "概念 30 分钟", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-concept-40", x: 0.30, y: 40.0 / 60.0, value: 40, result: 40, label: "概念 40 分钟", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-concept-50", x: 0.30, y: 50.0 / 60.0, value: 50, result: 50, label: "概念 50 分钟", evidenceIDs: ["allocation-source"]),
            ]),
            RichAnswerUIDataset(id: "allocation-practice", rows: [
                RichAnswerUIDataRow(id: "allocation-practice-10", x: 0.70, y: 50.0 / 60.0, value: 10, result: 50, label: "练习 50 分钟", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-practice-20", x: 0.70, y: 40.0 / 60.0, value: 20, result: 40, label: "练习 40 分钟", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-practice-30", x: 0.70, y: 30.0 / 60.0, value: 30, result: 30, label: "练习 30 分钟", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-practice-40", x: 0.70, y: 20.0 / 60.0, value: 40, result: 20, label: "练习 20 分钟", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-practice-50", x: 0.70, y: 10.0 / 60.0, value: 50, result: 10, label: "练习 10 分钟", evidenceIDs: ["allocation-source"]),
            ]),
            RichAnswerUIDataset(id: "allocation-states", rows: [
                RichAnswerUIDataRow(id: "allocation-state-10", x: 0.10, y: 0.50, value: 10, label: "10 / 50", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-state-20", x: 0.30, y: 0.50, value: 20, label: "20 / 40", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-state-30", x: 0.50, y: 0.50, value: 30, label: "30 / 30", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-state-40", x: 0.70, y: 0.50, value: 40, label: "40 / 20", evidenceIDs: ["allocation-source"]),
                RichAnswerUIDataRow(id: "allocation-state-50", x: 0.90, y: 0.50, value: 50, label: "50 / 10", evidenceIDs: ["allocation-source"]),
            ]),
        ],
        bindings: [
            RichAnswerUIBinding(
                id: "allocation-concept-time",
                label: "概念理解时间",
                minimum: 10,
                maximum: 50,
                step: 10,
                initialValue: 30,
                unit: "分钟"
            ),
        ]
    )

    private static let pendulumScene = generatedScene(
        id: "pendulum-primitives",
        title: "单摆 · 通用原语验收",
        family: .quantityAndCoordinates,
        evidenceID: "pendulum-source",
        placement: .inline,
        nodes: [
            RichAnswerUINode(id: "pendulum-root", role: .vstack, children: ["pendulum-caption", "pendulum-summary", "pendulum-canvas", "pendulum-probe", "pendulum-source"], spacing: .regular),
            RichAnswerUINode(id: "pendulum-caption", role: .text, text: "拖动摆长，观察周期不是等比例增加，而是逐渐变缓。", evidenceIDs: ["pendulum-source"], tone: .muted, emphasis: .quiet),
            RichAnswerUINode(id: "pendulum-summary", role: .hstack, children: ["pendulum-formula", "pendulum-period"], spacing: .loose),
            RichAnswerUINode(id: "pendulum-formula", role: .text, label: "小角度关系", text: "T = 2π√(L/g)", evidenceIDs: ["pendulum-source"], emphasis: .strong),
            RichAnswerUINode(id: "pendulum-period", role: .metric, label: "当前周期", unit: "s", datasetID: "pendulum-curve", bindingID: "pendulum-length", evidenceIDs: ["pendulum-source"], tone: .accent, emphasis: .strong, alignment: .trailing),
            RichAnswerUINode(
                id: "pendulum-canvas",
                role: .canvas,
                children: ["pendulum-axis", "pendulum-path", "pendulum-points"],
                xAxis: RichAnswerAxis(label: "摆长 L", minimum: 0.25, maximum: 2, unit: "m"),
                yAxis: RichAnswerAxis(label: "周期 T", minimum: 0, maximum: 3.2, unit: "s"),
                size: .regular
            ),
            RichAnswerUINode(id: "pendulum-axis", role: .axis, tone: .gridline, emphasis: .quiet),
            RichAnswerUINode(id: "pendulum-path", role: .path, datasetID: "pendulum-curve", evidenceIDs: ["pendulum-source"], tone: .ink, emphasis: .strong),
            RichAnswerUINode(id: "pendulum-points", role: .point, datasetID: "pendulum-curve", bindingID: "pendulum-length", evidenceIDs: ["pendulum-source"], tone: .muted),
            RichAnswerUINode(id: "pendulum-probe", role: .probe, label: "摆长 L", bindingID: "pendulum-length"),
            RichAnswerUINode(id: "pendulum-source", role: .evidence, evidenceIDs: ["pendulum-source"]),
        ],
        datasets: [RichAnswerUIDataset(id: "pendulum-curve", rows: pendulumRows)],
        bindings: [RichAnswerUIBinding(id: "pendulum-length", label: "摆长 L", minimum: 0.25, maximum: 2, step: 0.05, initialValue: 1, unit: "m")]
    )

    private static let sequenceScene = generatedScene(
        id: "argument-sequence",
        title: "论证路径",
        family: .relationAndEvidence,
        evidenceID: "sequence-source",
        placement: .inline,
        nodes: [
            RichAnswerUINode(id: "sequence-root", role: .vstack, children: ["sequence-caption", "sequence-track", "sequence-control", "sequence-source"], spacing: .regular),
            RichAnswerUINode(id: "sequence-caption", role: .text, text: "点选节点，逐步核对论证怎样从前提走到有限结论。", evidenceIDs: ["sequence-source"], tone: .muted, emphasis: .quiet),
            RichAnswerUINode(id: "sequence-track", role: .sequence, label: "可检查的论证链", datasetID: "sequence-rows", bindingID: "sequence-step", evidenceIDs: ["sequence-source"], tone: .accent),
            RichAnswerUINode(id: "sequence-control", role: .scrubber, label: "当前步骤", bindingID: "sequence-step"),
            RichAnswerUINode(id: "sequence-source", role: .evidence, evidenceIDs: ["sequence-source"]),
        ],
        datasets: [
            RichAnswerUIDataset(id: "sequence-rows", rows: [
                RichAnswerUIDataRow(id: "sequence-premise", x: 0, y: 0.5, value: 0, label: "前提：公共空间允许陌生人低成本共处", evidenceIDs: ["sequence-source"]),
                RichAnswerUIDataRow(id: "sequence-bridge", x: 0.33, y: 0.5, value: 1, label: "桥接：停留增加形成联系的机会", evidenceIDs: ["sequence-source"]),
                RichAnswerUIDataRow(id: "sequence-counter", x: 0.67, y: 0.5, value: 2, label: "反证：时间变化也可能来自其他原因", evidenceIDs: ["sequence-source"]),
                RichAnswerUIDataRow(id: "sequence-conclusion", x: 1, y: 0.5, value: 3, label: "结论：观察支持作用，但不能证明唯一因果", evidenceIDs: ["sequence-source"]),
            ]),
        ],
        bindings: [RichAnswerUIBinding(id: "sequence-step", label: "步骤", minimum: 0, maximum: 3, step: 1, initialValue: 0)]
    )

    private static let functionRows: [RichAnswerUIDataRow] = stride(from: -2.0, through: 2.0, by: 0.5).enumerated().map { index, x in
        let result = x * x
        return RichAnswerUIDataRow(
            id: "math-row-\(index)",
            x: (x + 2) / 4,
            y: result / 4,
            value: x,
            result: result,
            label: "x=\(String(format: "%.1f", x))",
            evidenceIDs: ["math-source"]
        )
    }

    private static let pendulumRows: [RichAnswerUIDataRow] = stride(from: 0.25, through: 2.0, by: 0.05).enumerated().map { index, length in
        let period = 2 * Double.pi * sqrt(length / 9.81)
        return RichAnswerUIDataRow(
            id: "pendulum-row-\(index)",
            x: (length - 0.25) / 1.75,
            y: period / 3.2,
            value: length,
            result: period,
            label: "L=\(String(format: "%.2f", length)) m",
            evidenceIDs: ["pendulum-source"]
        )
    }

    private static func generatedScene(
        id: String,
        title: String,
        family: RichAnswerCapabilityFamily,
        evidenceID: String,
        placement: RichAnswerSurface = .expanded,
        nodes: [RichAnswerUINode],
        datasets: [RichAnswerUIDataset] = [],
        bindings: [RichAnswerUIBinding] = []
    ) -> RichAnswerScene {
        RichAnswerScene(
            id: id,
            title: title,
            family: family,
            objects: [],
            evidenceIDs: [evidenceID],
            placement: placement,
            ui: RichAnswerUIComposition(
                rootID: nodes[0].id,
                nodes: nodes,
                datasets: datasets,
                bindings: bindings
            )
        )
    }
}
