import Foundation

public enum StudyAgentPurpose: String, Codable, Sendable {
    case conversation
    case quietInsight
}

public enum StudyAgentWorkflow: String, Codable, Sendable {
    case automatic
    case studyCompanion
    case courseWayfinding
    case closeReading
    case noteMaking
    case recallPractice
    case interactiveStudy
}

public enum StudyAgentRichPresentationShape: String, Codable, Equatable, Sendable {
    case quiz
    case reveal
    case chart
    case functionPlot = "function-plot"
    case parameterLab = "parameter-lab"
    case textStudy = "text-study"
    case designCompare = "design-compare"
    case palette
    case studyBoard = "study-board"
    case relationshipMap = "relationship-map"
    case timeline
    case comparisonMatrix = "comparison-matrix"
    case annotatedPassage = "annotated-passage"
    case derivationSteps = "derivation-steps"
    case flashcards
    case sequenceBuilder = "sequence-builder"
    case scenarioLab = "scenario-lab"
    case evidenceBoard = "evidence-board"
    case spectrum
    case decisionPath = "decision-path"
    case unitWorkbench = "unit-workbench"
    case reactionBalance = "reaction-balance"
    case algorithmTrace = "algorithm-trace"
    case languageAligner = "language-aligner"
    case argumentMap = "argument-map"
    case visualAnalysis = "visual-analysis"
    case spatialLayers = "spatial-layers"
    case pathwayLab = "pathway-lab"
}

public struct StudyAgentRichPresentationDecision: Equatable, Sendable {
    public var shape: StudyAgentRichPresentationShape?
    public var reason: String?

    public init(shape: StudyAgentRichPresentationShape?, reason: String? = nil) {
        self.shape = shape
        self.reason = reason
    }

    public var promptHint: String? {
        guard let shape else { return nil }
        return "回答前先判断富表达是否真的比纯文字更清楚。当前证据适合优先尝试 \(shape.rawValue)；若证据不足则退回简洁正文。最多使用一个主互动块，并为可跳转内容标注真实来源。协议提示：\(shape.protocolHint)"
    }
}

private extension StudyAgentRichPresentationShape {
    var protocolHint: String {
        switch self {
        case .studyBoard:
            return "study-board 使用 title、可选 summary、layout(lanes/grid/sequence)、treatment(editorial/annotated/compact/outline)、可选 metrics 与 items。"
        case .relationshipMap:
            return "relationship-map 使用 title、layout(radial/flow)、唯一 id 的 nodes，以及 from/to 只指向现有节点的 edges。"
        case .timeline:
            return "timeline 使用 title 与 events；每个事件包含 label、title，可选 detail、tone、source。"
        case .comparisonMatrix:
            return "comparison-matrix 使用 2 到 4 个 columns 与最多 6 个 rows；每行 values 数量必须等于列数。"
        case .chart:
            return "chart 使用 title、chartType(line/bar/scatter/area)、轴标签和带有限 points 的 series。"
        case .functionPlot:
            return "function-plot 只展示已确认关系，公式只作标签，曲线数据必须放在有限预采样 points 中。"
        case .parameterLab:
            return "parameter-lab 只能使用 skill 中列出的函数 family 与白名单参数。"
        case .quiz:
            return "quiz 使用 prompt、options、correctIndex、explanation。"
        case .reveal:
            return "reveal 使用 title 与 content。"
        case .textStudy:
            return "text-study 使用 variants 对齐原句、改写或论证策略。"
        case .designCompare:
            return "design-compare 使用 2 到 4 个 variants 与内建 treatment，不输出自定义样式。"
        case .palette:
            return "palette 使用带名称、六位十六进制值和用途的 colors。"
        case .annotatedPassage:
            return "annotated-passage 使用一段受限 text 与 annotations；每条批注用原文中真实 term 定位，可带 note、tone、source。"
        case .derivationSteps:
            return "derivation-steps 使用 title、可选 prompt 与有序 steps；每步包含 label、statement，可选 reason、source。"
        case .flashcards:
            return "flashcards 使用 2 到 10 张 cards；每张卡包含 front、back，可选 hint、source。"
        case .sequenceBuilder:
            return "sequence-builder 使用唯一 id 的 items 与引用这些 id 的 correctOrder，用户可以自行排序后检查。"
        case .scenarioLab:
            return "scenario-lab 使用 1 到 3 个有限选项 controls 与预先枚举的 outcomes，不运行模型生成的表达式。"
        case .evidenceBoard:
            return "evidence-board 使用 claim 与按 support/challenge/gap 分类的 items，每条可带 source。"
        case .spectrum:
            return "spectrum 使用 axisStart、axisEnd 与 position 位于 0 到 100 的 points。"
        case .decisionPath:
            return "decision-path 使用有限 nodes、唯一 id、startID 与只指向现有节点的 choices，不执行任意逻辑。"
        case .unitWorkbench:
            return "unit-workbench: title, optional question, variables[{id,label,value(字符串),unit,optional role,source}], checks[{id,label,left,right,result,source}], sources。所有换算和检查结果预先写入，不让前端推算。"
        case .reactionBalance:
            return "reaction-balance: title, species[{id,label,side reactant/product,coefficient 1...9,atoms 元素->单个分子原子数,source}], sources。前端只按给定 atoms 乘系数，绝不解析 formula。"
        case .algorithmTrace:
            return "algorithm-trace: title, codeLines[string], steps[{lineIndex,summary,optional note,source}], sources。只是展示预枚举步骤，不执行 codeLines。"
        case .languageAligner:
            return "language-aligner: title, pairs[{label,sourceText,targetText,note,source}], sources。每组短小并绑定来源。"
        case .argumentMap:
            return "argument-map: title, optional question, nodes[{id,type premise/claim/objection/reply,label,optional detail,source}], edges[{from,to,optional label}], sources。只画材料支持的论证关系。"
        case .visualAnalysis:
            return "visual-analysis: title, zones[{id,label,x,y,width,height,note,tone,source}], optional palette[{label,role,tone}], optional lenses[{id,label,note,zoneIds}], sources。坐标限 0...100，禁止 URL/HTML/image src。"
        case .spatialLayers:
            return "spatial-layers: title, layers[{id,label,visible}], features[{id,type point/route/region,layerId,label,note,points:[[x,y]...],source}], sources。无真实坐标证据时文案必须称示意图。"
        case .pathwayLab:
            return "pathway-lab: title, nodes[{id,label,detail,source}], states[{id,label,note,activeNodeIds,source}], edges[{from,to,label}], sources。只切换预枚举 states。"
        }
    }
}

private enum StudyAgentRichPresentationPolicy {
    static func decision(for request: StudyAgentRequest) -> StudyAgentRichPresentationDecision {
        let question = request.question.lowercased()
        let evidence = boundedEvidence(for: request).lowercased()

        if let explicitShape = explicitShape(in: question) {
            return StudyAgentRichPresentationDecision(
                shape: explicitShape,
                reason: "用户明确要求富表达"
            )
        }

        let noteTerms = ["整理", "写入", "笔记", "润色", "摘录", "要点", "outline", "organize", "note", "rewrite"]
        if noteTerms.contains(where: question.contains) {
            return StudyAgentRichPresentationDecision(shape: nil)
        }

        let unitQuestions = ["单位换算", "量纲", "换算", "单位统一", "单位工作台", "unit conversion", "dimensional analysis"]
        let unitMarkers = ["kg", "g", "mg", "m ", "cm", "mm", "km", "l", "ml", "mol", "s ", "ms", "min", "h ", "pa", "kpa", "j", "kj", "w", "%", "单位", "换算"]
        if unitQuestions.contains(where: question.contains),
           numberCount(in: evidence) >= 2,
           matchCount(of: unitMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .unitWorkbench,
                reason: "问题要求单位或量纲处理，材料包含可核对的数值与单位"
            )
        }

        let reactionQuestions = ["配平", "化学方程", "反应式", "原子守恒", "reaction balance", "balance equation"]
        let reactionMarkers = ["->", "→", "+", "=", "反应物", "生成物", "原子", "元素", "系数"]
        if reactionQuestions.contains(where: question.contains),
           matchCount(of: reactionMarkers, in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .reactionBalance,
                reason: "问题要求反应配平，材料包含反应两侧与守恒检查线索"
            )
        }

        let algorithmQuestions = ["算法跟踪", "算法过程", "执行过程", "状态变化", "逐步运行", "trace algorithm", "algorithm trace", "dry run"]
        let algorithmMarkers = ["输入", "输出", "初始", "步骤", "循环", "迭代", "比较", "更新", "input", "output", "step", "loop", "iteration"]
        if algorithmQuestions.contains(where: question.contains),
           matchCount(of: algorithmMarkers, in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .algorithmTrace,
                reason: "问题要求跟踪算法，材料包含可预枚举的输入、状态和步骤"
            )
        }

        let languageQuestions = ["语言对齐", "中英对照", "逐句翻译", "术语对齐", "原文译文", "原文和译文", "译文", "翻译", "language align", "parallel text"]
        let languageMarkers = ["原文", "译文", "术语", "表达", "语气", "translation", "term", "source", "target"]
        if languageQuestions.contains(where: question.contains),
           matchCount(of: languageMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .languageAligner,
                reason: "问题要求对齐语言表达，材料包含可配对的原文、译文或术语"
            )
        }

        let argumentQuestions = ["论证结构", "论证图", "前提", "结论", "反驳", "argument map", "premise", "objection"]
        let argumentMarkers = ["结论", "主张", "前提", "因为", "所以", "反驳", "但是", "缺口", "claim", "premise", "because", "therefore", "objection"]
        if argumentQuestions.contains(where: question.contains),
           matchCount(of: argumentMarkers, in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .argumentMap,
                reason: "问题要求拆解论证，材料包含主张、理由或反驳关系"
            )
        }

        let visualQuestions = ["视觉分析", "图像分析", "看图分析", "画面分析", "图中", "image analysis", "visual analysis"]
        let visualMarkers = ["图", "图像", "画面", "颜色", "构图", "标注", "区域", "左", "右", "上", "下", "image", "figure", "region"]
        if visualQuestions.contains(where: question.contains),
           !containsURLOrHTML(question + "\n" + evidence),
           matchCount(of: visualMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .visualAnalysis,
                reason: "问题要求分析视觉材料，当前证据包含可描述的图像区域或标注"
            )
        }

        let spatialQuestions = ["空间层次", "空间关系", "层级结构", "方位关系", "结构示意", "spatial layers", "spatial relation"]
        let spatialMarkers = ["上", "下", "左", "右", "内", "外", "前", "后", "层", "区域", "坐标", "位置", "above", "below", "left", "right", "layer"]
        if spatialQuestions.contains(where: question.contains),
           matchCount(of: spatialMarkers, in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .spatialLayers,
                reason: "问题要求看清空间层次，材料包含可分层的方位或位置关系"
            )
        }

        let pathwayQuestions = ["通路实验", "信号通路", "代谢通路", "路径切换", "pathway lab", "pathway"]
        let pathwayMarkers = ["通路", "激活", "抑制", "状态", "上游", "下游", "导致", "转换", "pathway", "activate", "inhibit", "state", "upstream", "downstream"]
        if pathwayQuestions.contains(where: question.contains),
           matchCount(of: pathwayMarkers, in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .pathwayLab,
                reason: "问题要求观察通路状态，材料包含可预先枚举的状态切换"
            )
        }

        let selectedPassage = request.selectionText?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let closeReadingQuestions = ["这段怎么理解", "逐句", "关键词", "原文里", "哪句话", "细读", "close read", "annotate this"]
        if selectedPassage.count >= 40,
           selectedPassage.count <= 1_800,
           closeReadingQuestions.contains(where: question.contains) {
            return StudyAgentRichPresentationDecision(
                shape: .annotatedPassage,
                reason: "用户正在细读一段选区，原文适合就地夹批"
            )
        }

        let derivationQuestions = ["怎么推导", "如何推导", "怎么算", "证明", "一步步", "推理过程", "derive", "derivation", "prove"]
        let derivationMarkers = ["=", "等于", "约等于", "因为", "所以", "因此", "移项", "代入", "推出", "therefore", "because"]
        if derivationQuestions.contains(where: question.contains),
           matchCount(of: derivationMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .derivationSteps,
                reason: "问题要求展开推理，材料包含可核对的推导承接"
            )
        }

        let sequencePracticeQuestions = ["练习顺序", "练一下流程", "我来排", "掌握步骤", "顺序自测", "practice the sequence"]
        let sequenceMarkers = ["第一", "第二", "第三", "首先", "其次", "然后", "随后", "接着", "最后", "最终", "阶段", "步骤", "->", "→"]
        if sequencePracticeQuestions.contains(where: question.contains),
           matchCount(of: sequenceMarkers, in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .sequenceBuilder,
                reason: "用户要练习顺序，材料包含唯一可核对的步骤链"
            )
        }

        let evidenceQuestions = ["证据够吗", "是否成立", "支持这个结论", "反驳", "反例", "证据缺口", "质疑", "evidence", "support this claim", "counterexample"]
        let evidenceMarkers = ["因为", "依据", "表明", "支持", "但是", "然而", "相反", "缺少", "未说明", "evidence", "however", "but"]
        if evidenceQuestions.contains(where: question.contains),
           matchCount(of: evidenceMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .evidenceBoard,
                reason: "问题要求核验主张，材料同时包含论据、限制或缺口"
            )
        }

        let conditionalMarkers = ["如果", "那么", "否则", "当", "取决于", "条件", "前提", "if ", "then", "otherwise", "depends on"]
        let scenarioQuestions = ["如果改变", "条件变化", "会怎样", "不同情境", "假设", "what if", "scenario"]
        if scenarioQuestions.contains(where: question.contains),
           matchCount(of: conditionalMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .scenarioLab,
                reason: "问题要求改变有限条件，材料给出了可预先枚举的结果"
            )
        }

        let decisionQuestions = ["怎么判断", "如何判断", "应该选哪个", "该怎么选", "遇到这种情况", "判断路径", "how should i decide", "which should i choose"]
        if decisionQuestions.contains(where: question.contains),
           matchCount(of: conditionalMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .decisionPath,
                reason: "问题要求作出判断，材料包含有依据的条件分支"
            )
        }

        let spectrumQuestions = ["程度差异", "偏向哪边", "从弱到强", "连续变化", "放在什么位置", "continuum", "where does it sit"]
        let spectrumMarkers = ["更", "较", "程度", "偏向", "介于", "从", "到", "弱", "强", "低", "高"]
        if spectrumQuestions.contains(where: question.contains),
           matchCount(of: spectrumMarkers, in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .spectrum,
                reason: "问题关注同一维度上的连续位置，材料包含多个相对程度"
            )
        }

        let recallQuestions = ["帮我复习", "我要背", "记住这些", "复习这些概念", "review these", "memorize"]
        if recallQuestions.contains(where: question.contains), evidence.count >= 120 {
            return StudyAgentRichPresentationDecision(
                shape: .flashcards,
                reason: "用户要复习多组知识，材料足以形成多张问答卡"
            )
        }

        let quizQuestions = ["考考我", "出一道题", "来个自测", "我想自测", "quiz me", "test me"]
        if quizQuestions.contains(where: question.contains), !evidence.isEmpty {
            return StudyAgentRichPresentationDecision(
                shape: .quiz,
                reason: "用户要立即核对单个知识点"
            )
        }

        let comparisonQuestions = ["区别", "差异", "不同", "对比", "比较", "怎么选", "versus", " vs ", "difference", "compare"]
        let comparisonEvidence = ["二者", "前者", "后者", "相比", "而", "不同", "共同", "分别", "扣除", "包含"]
        if comparisonQuestions.contains(where: question.contains),
           comparisonEvidence.contains(where: evidence.contains) {
            return StudyAgentRichPresentationDecision(
                shape: .comparisonMatrix,
                reason: "问题要求比较，材料包含可对齐的差异维度"
            )
        }

        let sequenceQuestions = ["过程", "阶段", "先后", "步骤", "演变", "发展", "经历", "timeline", "process", "stages", "steps"]
        if sequenceQuestions.contains(where: question.contains),
           matchCount(of: sequenceMarkers, in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .timeline,
                reason: "问题关注先后过程，材料包含多个有序阶段"
            )
        }

        let causalQuestions = ["为什么", "机制", "如何影响", "怎样影响", "怎么影响", "因果", "传导", "why", "mechanism", "affect", "cause"]
        let causalMarkers = ["导致", "因此", "所以", "进而", "从而", "引起", "推动", "使得", "因为", "由于", "取决于", "影响", "cause", "therefore", "leads to", "results in"]
        if causalQuestions.contains(where: question.contains),
           matchCount(of: causalMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .relationshipMap,
                reason: "问题关注机制，材料包含可追踪的因果链"
            )
        }

        let relationQuestions = ["文件关系", "知识关系", "怎么关联", "如何关联", "关联脉络", "关系图", "relation", "how are these connected"]
        if relationQuestions.contains(where: question.contains),
           (!request.courseContext.relations.isEmpty || request.courseContext.catalog.count >= 2) {
            return StudyAgentRichPresentationDecision(
                shape: .relationshipMap,
                reason: "问题要求跨材料建立关系，课程上下文包含多个条目或已确认关联"
            )
        }

        let quantitativeQuestions = ["数据", "变化", "趋势", "增长", "下降", "波动", "比例", "分布", "走势", "说明了什么", "data", "trend", "growth", "decline", "change"]
        if quantitativeQuestions.contains(where: question.contains), numberCount(in: evidence) >= 3 {
            return StudyAgentRichPresentationDecision(
                shape: .chart,
                reason: "问题关注量化变化，材料包含至少三个可比较数值"
            )
        }

        let structureQuestions = ["框架", "全貌", "结构", "脉络", "梳理一下", "概览", "知识地图", "overview", "structure", "map this"]
        let structureMarkers = ["\n#", "\n- ", "\n* ", "\n1.", "：", ";", "；"]
        if structureQuestions.contains(where: question.contains),
           matchCount(of: structureMarkers, in: evidence) >= 2 {
            return StudyAgentRichPresentationDecision(
                shape: .studyBoard,
                reason: "问题需要建立全貌，材料已有可分组的知识结构"
            )
        }

        return StudyAgentRichPresentationDecision(shape: nil)
    }

    private static func explicitShape(in question: String) -> StudyAgentRichPresentationShape? {
        let candidates: [(StudyAgentRichPresentationShape, [String])] = [
            (.unitWorkbench, ["单位工作台", "单位换算", "量纲检查", "unit workbench", "unit conversion"]),
            (.reactionBalance, ["反应配平", "配平方程", "原子守恒", "reaction balance", "balance equation"]),
            (.algorithmTrace, ["算法跟踪", "执行跟踪", "手动跑一遍", "algorithm trace", "dry run"]),
            (.languageAligner, ["语言对齐", "中英对照", "术语对齐", "language aligner", "parallel text"]),
            (.argumentMap, ["论证图", "论点地图", "前提结论图", "argument map"]),
            (.visualAnalysis, ["视觉分析", "图像分析", "看图分析", "visual analysis", "image analysis"]),
            (.spatialLayers, ["空间层次", "空间示意", "分层示意", "spatial layers"]),
            (.pathwayLab, ["通路实验", "路径实验", "状态切换实验", "pathway lab"]),
            (.functionPlot, ["函数曲线", "函数图", "function plot"]),
            (.parameterLab, ["滑块", "调参", "参数调节", "控制器", "parameter lab", "slider"]),
            (.designCompare, ["设计对比", "设计比较", "版式对比", "design comparison"]),
            (.textStudy, ["文本对照", "文稿对照", "逐句对照", "text comparison"]),
            (.palette, ["配色", "色板", "palette"]),
            (.relationshipMap, ["关系图", "因果图", "关联图", "relationship map"]),
            (.timeline, ["时间线", "流程图", "timeline"]),
            (.comparisonMatrix, ["对比矩阵", "比较矩阵", "comparison matrix"]),
            (.annotatedPassage, ["夹批", "逐条点开", "批注原文", "annotated passage"]),
            (.derivationSteps, ["逐步推导", "一步一步揭晓", "推导过程", "derivation steps"]),
            (.flashcards, ["记忆卡", "翻面", "翻卡", "flashcards", "flash cards"]),
            (.sequenceBuilder, ["自己排序", "步骤排序", "排序后检查", "sequence builder"]),
            (.scenarioLab, ["情境实验", "切换条件", "观察结果", "scenario lab"]),
            (.evidenceBoard, ["支持证据", "反例和缺口", "证据核验", "evidence board"]),
            (.spectrum, ["连续光谱", "观点光谱", "光谱上", "spectrum"]),
            (.decisionPath, ["决策路径", "逐步分支", "分支选择", "decision path"]),
            (.chart, ["图表", "可视化", "曲线图", "chart", "visualize"]),
            (.quiz, ["互动测验", "单题自测", "quiz"]),
            (.reveal, ["逐步揭晓", "先想再揭晓", "reveal"]),
            (.studyBoard, ["互动", "交互", "研习板", "interactive"]),
        ]
        for candidate in candidates where candidate.1.contains(where: question.contains) {
            if candidate.0 == .visualAnalysis, containsURLOrHTML(question) {
                continue
            }
            return candidate.0
        }
        return nil
    }

    private static func boundedEvidence(for request: StudyAgentRequest) -> String {
        let values = [request.selectionText, request.materialText, request.noteText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return String(values.joined(separator: "\n").prefix(12_000))
    }

    private static func matchCount(of terms: [String], in value: String) -> Int {
        terms.reduce(into: 0) { count, term in
            if value.contains(term) { count += 1 }
        }
    }

    private static func numberCount(in value: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: #"[-+]?\d+(?:\.\d+)?%?"#) else {
            return 0
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.numberOfMatches(in: value, range: range)
    }

    private static func containsURLOrHTML(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let markers = ["http://", "https://", "<html", "<iframe", "<script", "<img", "<svg", "</"]
        return markers.contains(where: lowered.contains)
    }
}

public enum StudyAgentQuestionScope {
    public static func allowsSourceFreeAnswer(_ question: String) -> Bool {
        var remainder = normalized(question)
        let sourceFreePhrases = [
            "请给我讲一个笑话", "给我讲一个笑话", "请给我讲个笑话", "给我讲个笑话",
            "讲一个笑话", "讲个笑话", "说一个笑话", "说个笑话",
            "你叫什么名字", "你的名字是什么", "你叫什么", "你是谁",
            "介绍一下你自己", "自我介绍一下", "你能做什么", "你可以做什么",
            "你会做什么", "你是干什么的",
            "早上好", "下午好", "晚上好", "你好", "您好", "哈喽", "嗨", "在吗",
            "谢谢你", "谢谢", "多谢", "明白了", "知道了", "收到", "好的", "再见",
            "tellmeajoke", "tellajoke", "whatisyourname", "whatsyourname", "whoareyou",
            "introduceyourself", "whatcanyoudo", "hello", "hi", "hey", "thankyou", "thanks", "goodbye", "bye",
        ].sorted { $0.count > $1.count }
        var matchedSourceFreePhrase = false
        for phrase in sourceFreePhrases where remainder.contains(phrase) {
            remainder = remainder.replacingOccurrences(of: phrase, with: "")
            matchedSourceFreePhrase = true
        }
        guard matchedSourceFreePhrase else { return false }
        let benignWords = [
            "请", "一下", "可以吗", "行吗", "呀", "啊", "呢", "吧", "嘛", "哈",
            "please", "me", "a", "the", "and",
        ]
        for word in benignWords {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        return remainder.isEmpty
    }

    public static func allowsLearningOnlyAnswer(_ question: String) -> Bool {
        var remainder = normalized(question)
        let statePhrases = [
            "你记得我的学习情况吗", "你记得我学到哪吗", "我上次学习到哪了", "我上次学习到哪",
            "我上次学到哪了", "我上次学到哪", "上次学习到哪了", "上次学习到哪",
            "上次学到哪了", "上次学到哪", "我的学习进度", "学习进度", "我的学习目标", "学习目标",
            "我的目标", "我的学习困惑", "学习困惑", "我的困惑", "接下来学什么",
            "接下来做什么", "下一步学什么", "下一步做什么", "下一步", "你记得我吗",
            "wheredidistoplasttime", "whereididstoplasttime", "learningprogress", "mygoal", "mylearninggoal",
            "myconfusion", "whatnext", "doyourememberme",
        ]
        var matchedStatePhrase = false
        for phrase in statePhrases where remainder.contains(phrase) {
            remainder = remainder.replacingOccurrences(of: phrase, with: "")
            matchedStatePhrase = true
        }
        guard matchedStatePhrase else { return false }
        let benignWords = [
            "请告诉我一下", "请告诉我", "告诉我一下", "告诉我", "我", "的", "是", "什么",
            "有哪些", "请", "一下", "了", "吗", "呢", "和", "以及", "位置", "在哪", "哪里",
            "当前", "现在", "想", "要", "please", "tellme", "the", "and", "location",
            "current", "now", "what", "is", "are", "my", "i", "did", "lasttime",
        ]
        for word in benignWords {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        return remainder.isEmpty
    }

    private static func normalized(_ question: String) -> String {
        question.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
        }.map(String.init).joined()
    }
}

public enum StudyAgentResolutionEvidence {
    public static func matches(_ evidence: String, question: String) -> Bool {
        guard StudyAgentCurrentTurnEvidence.matches(evidence, question: question),
              let statement = statement(in: evidence) else { return false }
        let value = statement.lowercased()
        let unresolvedTerms = [
            "不懂", "不理解", "不会", "没懂", "仍然困惑", "还是困惑", "不知道", "不能区分", "不能够",
            "还不能", "尚不能", "无法", "没法", "尚未", "还没", "并不", "不太", "不确定",
            "不正确", "并非正确", "答错", "错误", "不对",
            "don't understand", "do not understand", "can't", "cannot", "still confused", "not sure",
            "not able", "unable", "not yet", "have not", "haven't", "incorrect", "not correct", "wrong answer", "is wrong",
        ]
        guard !unresolvedTerms.contains(where: value.contains) else { return false }
        let questionTerms = ["什么", "为什么", "怎么", "为何", "吗", "？", "?", "what", "why", "how"]
        guard !questionTerms.contains(where: value.contains) else { return false }
        let masteryTerms = [
            "懂了", "明白了", "会了", "掌握了", "可以区分", "能够区分", "能解释", "答对", "正确",
            "解决了", "不再困惑", "understand now", "got it", "can distinguish", "can explain", "correct",
        ]
        if masteryTerms.contains(where: value.contains) { return true }
        let answerMarkers = [
            "是", "指", "因为", "所以", "而", "但是", "扣除", "等于", "相比", "表示", "反映", "意味着", "即", "=",
            " is ", " means", "because", "therefore", "while", "equals", "represents", "reflects", "differs",
        ]
        guard answerMarkers.contains(where: value.contains) else { return false }
        let meaningfulCount = statement.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        return meaningfulCount >= 12
    }

    private static func statement(in evidence: String) -> String? {
        let prefixes = ["[用户：本轮]", "[会话：当前]"]
        guard let prefix = prefixes.first(where: { evidence.hasPrefix($0) }) else { return nil }
        let quoteCharacters = CharacterSet(charactersIn: "\"'“”‘’")
        let value = String(evidence.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: quoteCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

}

public enum StudyAgentCurrentTurnEvidence {
    public static func matches(_ evidence: String, question: String) -> Bool {
        guard let statement = statement(in: evidence), statement.count >= 2 else { return false }
        if statement.count < 4 {
            return normalized(statement) == normalized(question)
        }
        var searchStart = question.startIndex
        while searchStart < question.endIndex,
              let range = question.range(of: statement, range: searchStart..<question.endIndex) {
            if hasClauseBoundaries(range, in: question),
               !omitsLeadingNegation(range, in: question) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func hasClauseBoundaries(_ range: Range<String.Index>, in question: String) -> Bool {
        let startsAtBoundary = range.lowerBound == question.startIndex
            || question[question.index(before: range.lowerBound)].isWhitespace
            || question[question.index(before: range.lowerBound)].isPunctuation
        let endsAtBoundary = range.upperBound == question.endIndex
            || question[range.upperBound].isWhitespace
            || question[range.upperBound].isPunctuation
        return startsAtBoundary && endsAtBoundary
    }

    private static func omitsLeadingNegation(
        _ range: Range<String.Index>,
        in question: String
    ) -> Bool {
        guard range.lowerBound > question.startIndex else { return false }
        let prefix = String(question[..<range.lowerBound]).lowercased()
        let immediate = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["不", "没", "未", "无", "别", "勿"].contains(where: immediate.hasSuffix) {
            return true
        }
        let clause = prefix
            .components(separatedBy: CharacterSet(charactersIn: "，,。！？；;:：.!?"))
            .last ?? prefix
        let negativePhrases = [
            "不想", "不喜欢", "不太", "不能", "不会", "不要", "不愿", "没有", "没法", "尚未", "还没", "并不", "并非",
            " not ", " never ", " no ", " without ", "cannot", "can't", "don't", "doesn't", "didn't",
        ]
        let paddedClause = " \(clause) "
        return negativePhrases.contains(where: paddedClause.contains)
    }

    private static func statement(in evidence: String) -> String? {
        let prefixes = ["[用户：本轮]", "[会话：当前]"]
        guard let prefix = prefixes.first(where: { evidence.hasPrefix($0) }) else { return nil }
        let quoteCharacters = CharacterSet(charactersIn: "\"'“”‘’")
        let value = String(evidence.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: quoteCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalized(_ text: String) -> String {
        text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.map(String.init).joined()
    }
}

public struct StudyAgentCourseCatalogItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: String
    public var role: String
    public var isCurrentMaterial: Bool
    public var isCurrentNote: Bool
    public var linkedItemIDs: [String]
    public var tags: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: String,
        role: String,
        isCurrentMaterial: Bool = false,
        isCurrentNote: Bool = false,
        linkedItemIDs: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.role = role
        self.isCurrentMaterial = isCurrentMaterial
        self.isCurrentNote = isCurrentNote
        self.linkedItemIDs = linkedItemIDs
        self.tags = tags
    }

    public init(item: StudyAgentCourseItem) {
        self.init(
            id: item.id,
            title: item.title,
            subtitle: item.subtitle,
            kind: item.kind,
            role: item.role,
            isCurrentMaterial: item.isCurrentMaterial,
            isCurrentNote: item.isCurrentNote,
            linkedItemIDs: item.linkedItemIDs,
            tags: item.tags
        )
    }
}

public struct StudyAgentCourseItem: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var kind: String
    public var role: String
    public var isCurrentMaterial: Bool
    public var isCurrentNote: Bool
    public var linkedItemIDs: [String]
    public var headings: [String]
    public var tags: [String]
    public var searchText: String
    public var isTruncated: Bool

    public init(
        id: String,
        title: String,
        subtitle: String,
        kind: String,
        role: String,
        isCurrentMaterial: Bool = false,
        isCurrentNote: Bool = false,
        linkedItemIDs: [String] = [],
        headings: [String] = [],
        tags: [String] = [],
        searchText: String = "",
        isTruncated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.role = role
        self.isCurrentMaterial = isCurrentMaterial
        self.isCurrentNote = isCurrentNote
        self.linkedItemIDs = linkedItemIDs
        self.headings = headings
        self.tags = tags
        self.searchText = searchText
        self.isTruncated = isTruncated
    }
}

public struct StudyAgentCourseRelation: Codable, Equatable, Sendable {
    public var noteItemID: String
    public var sourceItemID: String

    public init(noteItemID: String, sourceItemID: String) {
        self.noteItemID = noteItemID
        self.sourceItemID = sourceItemID
    }
}

public struct StudyAgentCourseContext: Codable, Equatable, Sendable {
    public var title: String
    public var catalog: [StudyAgentCourseCatalogItem]
    public var items: [StudyAgentCourseItem]
    public var relations: [StudyAgentCourseRelation]
    public var isTruncated: Bool

    public init(
        title: String,
        catalog: [StudyAgentCourseCatalogItem] = [],
        items: [StudyAgentCourseItem] = [],
        relations: [StudyAgentCourseRelation] = [],
        isTruncated: Bool = false
    ) {
        self.title = title
        self.catalog = catalog.isEmpty ? items.map(StudyAgentCourseCatalogItem.init(item:)) : catalog
        self.items = items
        self.relations = relations
        self.isTruncated = isTruncated
    }

    public static let empty = StudyAgentCourseContext(title: "Course")
}

public struct StudyAgentSessionSnapshot: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var phase: String
    public var focusItemIDs: [String]
    public var turnCount: Int

    public init(
        id: String,
        title: String,
        summary: String,
        phase: String,
        focusItemIDs: [String],
        turnCount: Int
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.phase = phase
        self.focusItemIDs = focusItemIDs
        self.turnCount = turnCount
    }
}

public struct StudyAgentLearningContext: Codable, Equatable, Sendable {
    public var memoryRevision: UInt64
    public var lastLocation: StudyLocation?
    public var memories: [LearningMemoryEntry]
    public var session: StudyAgentSessionSnapshot?

    public init(
        memoryRevision: UInt64 = 0,
        lastLocation: StudyLocation? = nil,
        memories: [LearningMemoryEntry] = [],
        session: StudyAgentSessionSnapshot? = nil
    ) {
        self.memoryRevision = memoryRevision
        self.lastLocation = lastLocation
        self.memories = memories
        self.session = session
    }

    public static let empty = StudyAgentLearningContext()
}

public struct StudyAgentInteractionEvent: Codable, Equatable, Sendable {
    public var blockID: String
    public var kind: String
    public var action: String
    public var detail: String

    public init(blockID: String, kind: String, action: String, detail: String) {
        self.blockID = blockID
        self.kind = kind
        self.action = action
        self.detail = detail
    }
}

public struct StudyAgentRequest: Sendable {
    public var id: UUID
    public var purpose: StudyAgentPurpose
    public var workflow: StudyAgentWorkflow
    public var question: String
    public var materialTitle: String
    public var materialText: String
    public var materialIsTruncated: Bool
    public var noteTitle: String
    public var noteText: String
    public var selectionTitle: String?
    public var selectionText: String?
    public var recentMessages: [AgentMessage]
    public var interactions: [StudyAgentInteractionEvent]
    public var courseContext: StudyAgentCourseContext
    public var learningContext: StudyAgentLearningContext
    public var language: WeiBeiInterfaceLanguage
    public var contextRevision: String

    public init(
        id: UUID = UUID(),
        purpose: StudyAgentPurpose,
        workflow: StudyAgentWorkflow = .automatic,
        question: String,
        materialTitle: String,
        materialText: String,
        materialIsTruncated: Bool = false,
        noteTitle: String,
        noteText: String,
        selectionTitle: String? = nil,
        selectionText: String? = nil,
        recentMessages: [AgentMessage] = [],
        interactions: [StudyAgentInteractionEvent] = [],
        courseContext: StudyAgentCourseContext = .empty,
        learningContext: StudyAgentLearningContext = .empty,
        language: WeiBeiInterfaceLanguage = .chinese,
        contextRevision: String
    ) {
        self.id = id
        self.purpose = purpose
        self.workflow = workflow
        self.question = question
        self.materialTitle = materialTitle
        self.materialText = materialText
        self.materialIsTruncated = materialIsTruncated
        self.noteTitle = noteTitle
        self.noteText = noteText
        self.selectionTitle = selectionTitle
        self.selectionText = selectionText
        self.recentMessages = recentMessages
        self.interactions = interactions
        self.courseContext = courseContext
        self.learningContext = learningContext
        self.language = language
        self.contextRevision = contextRevision
    }

    public var resolvedWorkflow: StudyAgentWorkflow {
        guard workflow == .automatic else { return workflow }
        if purpose == .quietInsight { return .closeReading }

        let value = question.lowercased()
        let resumeTerms = ["上次", "继续学", "学到哪", "学习进度", "resume", "last time", "continue learning"]
        if resumeTerms.contains(where: value.contains) { return .studyCompanion }

        let wayfindingTerms = ["关联", "相关", "哪本", "哪份", "哪个文件", "跳转", "去哪里", "先学", "前置", "related", "connect", "which file", "where should", "prerequisite"]
        if wayfindingTerms.contains(where: value.contains) { return .courseWayfinding }

        let recallTerms = ["出题", "测验", "复习题", "自测", "quiz", "test me", "questions"]
        if recallTerms.contains(where: value.contains) { return .recallPractice }

        let noteTerms = ["整理", "写入", "笔记", "润色", "摘录", "要点", "outline", "organize", "note", "rewrite"]
        if noteTerms.contains(where: value.contains) { return .noteMaking }

        if richPresentationDecision.shape != nil { return .interactiveStudy }

        return .studyCompanion
    }

    public var richPresentationDecision: StudyAgentRichPresentationDecision {
        StudyAgentRichPresentationPolicy.decision(for: self)
    }

}

public struct StudyAgentNoteProposal: Codable, Equatable, Sendable {
    public var markdown: String
    public var evidence: [String]
    public var contextRevision: String

    public init(markdown: String, evidence: [String], contextRevision: String) {
        self.markdown = markdown
        self.evidence = evidence
        self.contextRevision = contextRevision
    }
}

public struct StudyAgentMemoryUpdateEntry: Codable, Equatable, Sendable {
    public var kind: LearningMemoryKind
    public var text: String
    public var evidence: String
    public var origin: LearningMemoryOrigin

    public init(
        kind: LearningMemoryKind,
        text: String,
        evidence: String,
        origin: LearningMemoryOrigin
    ) {
        self.kind = kind
        self.text = text
        self.evidence = evidence
        self.origin = origin
    }
}

public struct StudyAgentMemoryResolution: Codable, Equatable, Sendable {
    public var memoryID: String
    public var text: String
    public var evidence: String

    public init(memoryID: String, text: String, evidence: String) {
        self.memoryID = memoryID
        self.text = text
        self.evidence = evidence
    }
}

public struct StudyAgentLearningUpdate: Codable, Equatable, Sendable {
    public var contextRevision: String
    public var memoryRevision: UInt64
    public var sessionSummary: String?
    public var suggestedPhase: StudyPhase?
    public var suggestedNext: [String]
    public var entries: [StudyAgentMemoryUpdateEntry]
    public var resolutions: [StudyAgentMemoryResolution]

    public init(
        contextRevision: String,
        memoryRevision: UInt64,
        sessionSummary: String? = nil,
        suggestedPhase: StudyPhase? = nil,
        suggestedNext: [String] = [],
        entries: [StudyAgentMemoryUpdateEntry] = [],
        resolutions: [StudyAgentMemoryResolution] = []
    ) {
        self.contextRevision = contextRevision
        self.memoryRevision = memoryRevision
        self.sessionSummary = sessionSummary
        self.suggestedPhase = suggestedPhase
        self.suggestedNext = suggestedNext
        self.entries = entries
        self.resolutions = resolutions
    }
}

public struct StudyAgentReply: Equatable, Sendable {
    public var text: String
    public var backend: StudyAgentBackend
    public var noteProposal: StudyAgentNoteProposal?
    public var learningUpdate: StudyAgentLearningUpdate?

    public init(
        text: String,
        backend: StudyAgentBackend,
        noteProposal: StudyAgentNoteProposal? = nil,
        learningUpdate: StudyAgentLearningUpdate? = nil
    ) {
        self.text = text
        self.backend = backend
        self.noteProposal = noteProposal
        self.learningUpdate = learningUpdate
    }
}

public enum StudyAgentProgress: Equatable, Sendable {
    case readingContext
    case usingTool(String)
    case text(String)
}

public typealias StudyAgentProgressHandler = @Sendable (StudyAgentProgress) async -> Void

public protocol StudyAgentRuntime: Sendable {
    func respond(to request: StudyAgentRequest, progress: StudyAgentProgressHandler?) async throws -> StudyAgentReply
    func cancel() async
    func reset() async
}

public extension StudyAgentRuntime {
    func respond(to request: StudyAgentRequest) async throws -> StudyAgentReply {
        try await respond(to: request, progress: nil)
    }
}

public struct OfflineStudyAgentRuntime: StudyAgentRuntime {
    public init() {}

    public func respond(to request: StudyAgentRequest, progress: StudyAgentProgressHandler?) async throws -> StudyAgentReply {
        await progress?(.readingContext)
        let text = AgentOfflinePreview.render(
            AgentOfflinePreviewInput(
                language: request.language,
                question: request.question,
                hasMaterial: !request.materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                materialTitle: request.materialTitle,
                materialText: request.materialText,
                noteTitle: request.noteTitle,
                noteText: request.noteText,
                selectionTitle: request.selectionTitle,
                selectionText: request.selectionText
            )
        )
        return StudyAgentReply(text: text, backend: .offline)
    }

    public func cancel() async {}
    public func reset() async {}
}

public struct StudyAgentContextEnvelope: Codable, Equatable, Sendable {
    public struct Source: Codable, Equatable, Sendable {
        public var title: String
        public var text: String
        public var isTruncated: Bool

        public init(title: String, text: String, isTruncated: Bool = false) {
            self.title = title
            self.text = text
            self.isTruncated = isTruncated
        }
    }

    public struct Message: Codable, Equatable, Sendable {
        public var role: String
        public var text: String
        public var source: String?

        public init(role: String, text: String, source: String?) {
            self.role = role
            self.text = text
            self.source = source
        }
    }

    public var schemaVersion: Int
    public var requestID: String
    public var contextRevision: String
    public var purpose: String
    public var workflow: String
    public var language: String
    public var question: String
    public var material: Source?
    public var note: Source
    public var selection: Source?
    public var recentMessages: [Message]
    public var interactions: [StudyAgentInteractionEvent]
    public var course: StudyAgentCourseContext
    public var learning: StudyAgentLearningContext

    public init(request: StudyAgentRequest) {
        schemaVersion = 2
        requestID = request.id.uuidString.lowercased()
        contextRevision = request.contextRevision
        purpose = request.purpose.rawValue
        workflow = request.resolvedWorkflow.rawValue
        language = request.language.rawValue
        question = String(request.question.prefix(4_000))

        let materialText = String(request.materialText.prefix(18_000))
        material = materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : Source(
                title: String(request.materialTitle.prefix(300)),
                text: materialText,
                isTruncated: request.materialIsTruncated || request.materialText.count > materialText.count
            )

        let noteText = String(request.noteText.prefix(6_000))
        note = Source(
            title: String(request.noteTitle.prefix(300)),
            text: noteText,
            isTruncated: request.noteText.count > noteText.count
        )

        let selectedText = String((request.selectionText ?? "").prefix(2_000))
        selection = selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : Source(
                title: String((request.selectionTitle ?? request.materialTitle).prefix(300)),
                text: selectedText,
                isTruncated: (request.selectionText ?? "").count > selectedText.count
            )

        recentMessages = request.recentMessages.suffix(20).map { message in
            Message(
                role: message.role.rawValue,
                text: String(message.text.prefix(1_200)),
                source: message.source
            )
        }
        interactions = request.interactions.suffix(12).map { event in
            StudyAgentInteractionEvent(
                blockID: String(event.blockID.prefix(120)),
                kind: String(event.kind.prefix(80)),
                action: String(event.action.prefix(80)),
                detail: String(event.detail.prefix(1_200))
            )
        }
        let boundedCourse = Self.boundedCourseContext(request.courseContext)
        course = boundedCourse.context
        learning = Self.boundedLearningContext(request.learningContext, itemIDMap: boundedCourse.itemIDMap)
    }

    private static func boundedCourseContext(
        _ context: StudyAgentCourseContext
    ) -> (context: StudyAgentCourseContext, itemIDMap: [String: String]) {
        let maximumCatalogItems = 500
        let maximumItems = 80
        let sourceCatalog = Array(context.catalog.prefix(maximumCatalogItems))
        var itemIDMap: [String: String] = [:]
        for (index, item) in sourceCatalog.enumerated() where itemIDMap[item.id] == nil {
            itemIDMap[item.id] = "course-item-\(index + 1)"
        }
        let catalog = sourceCatalog.compactMap { item -> StudyAgentCourseCatalogItem? in
            guard let itemID = itemIDMap[item.id] else { return nil }
            return StudyAgentCourseCatalogItem(
                id: itemID,
                title: String(item.title.prefix(300)),
                subtitle: String(item.subtitle.prefix(300)),
                kind: String(item.kind.prefix(64)),
                role: String(item.role.prefix(64)),
                isCurrentMaterial: item.isCurrentMaterial,
                isCurrentNote: item.isCurrentNote,
                linkedItemIDs: item.linkedItemIDs.prefix(24).compactMap { itemIDMap[$0] },
                tags: item.tags.prefix(16).map { String($0.prefix(64)) }
            )
        }
        let items = context.items.prefix(maximumItems).compactMap { item -> StudyAgentCourseItem? in
            guard let itemID = itemIDMap[item.id] else { return nil }
            let searchText = String(item.searchText.prefix(2_400))
            return StudyAgentCourseItem(
                id: itemID,
                title: String(item.title.prefix(300)),
                subtitle: String(item.subtitle.prefix(300)),
                kind: String(item.kind.prefix(64)),
                role: String(item.role.prefix(64)),
                isCurrentMaterial: item.isCurrentMaterial,
                isCurrentNote: item.isCurrentNote,
                linkedItemIDs: item.linkedItemIDs.prefix(24).compactMap { itemIDMap[$0] },
                headings: item.headings.prefix(12).map { String($0.prefix(200)) },
                tags: item.tags.prefix(16).map { String($0.prefix(64)) },
                searchText: searchText,
                isTruncated: item.isTruncated || item.searchText.count > searchText.count
            )
        }
        let relations = context.relations
            .prefix(500)
            .compactMap { relation -> StudyAgentCourseRelation? in
                guard let noteItemID = itemIDMap[relation.noteItemID],
                      let sourceItemID = itemIDMap[relation.sourceItemID] else { return nil }
                return StudyAgentCourseRelation(noteItemID: noteItemID, sourceItemID: sourceItemID)
            }
        return (
            StudyAgentCourseContext(
                title: String(context.title.prefix(300)),
                catalog: catalog,
                items: items,
                relations: relations,
                isTruncated: context.isTruncated
                    || context.catalog.count > catalog.count
                    || context.items.count > items.count
                    || context.relations.count > relations.count
            ),
            itemIDMap
        )
    }

    private static func boundedLearningContext(
        _ context: StudyAgentLearningContext,
        itemIDMap: [String: String]
    ) -> StudyAgentLearningContext {
        let memories = context.memories
            .filter { $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(48)
            .map { memory in
                LearningMemoryEntry(
                    id: memory.id,
                    kind: memory.kind,
                    text: String(memory.text.prefix(500)),
                    evidence: String(memory.evidence.prefix(400)),
                    origin: memory.origin,
                    status: memory.status,
                    sessionID: memory.sessionID,
                    resolvedAt: memory.resolvedAt,
                    resolutionEvidence: memory.resolutionEvidence.map { String($0.prefix(400)) },
                    createdAt: memory.createdAt,
                    updatedAt: memory.updatedAt
                )
        }
        let location = context.lastLocation.flatMap { location -> StudyLocation? in
            guard let itemID = itemIDMap[location.itemID] else { return nil }
            return StudyLocation(
                itemID: itemID,
                itemTitle: String(location.itemTitle.prefix(300)),
                locationID: location.locationID.map { String($0.prefix(500)) },
                locationTitle: location.locationTitle.map { String($0.prefix(300)) },
                pageIndex: location.pageIndex.map { max($0, 0) + 1 },
                lastStudiedAt: location.lastStudiedAt,
                visitCount: location.visitCount
            )
        }
        let session = context.session.map { session in
            StudyAgentSessionSnapshot(
                id: String(session.id.prefix(256)),
                title: String(session.title.prefix(300)),
                summary: String(session.summary.prefix(2_000)),
                phase: String(session.phase.prefix(64)),
                focusItemIDs: session.focusItemIDs.prefix(24).compactMap { itemIDMap[$0] },
                turnCount: session.turnCount
            )
        }
        return StudyAgentLearningContext(
            memoryRevision: context.memoryRevision,
            lastLocation: location,
            memories: memories,
            session: session
        )
    }
}
