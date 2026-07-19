import type { RichAnswerProgram } from "./protocol";

const question = "为什么二次函数 y = ax² 中，a 的正负和绝对值会改变开口方向与宽窄？";

export const generatedPrograms: RichAnswerProgram[] = [
  {
    version: "weibei.openui.v1",
    id: "quadratic-experiment",
    title: "参数实验",
    question,
    mode: "declarative",
    capabilities: ["parameter-control", "function-plot", "linked-readout", "evidence-jump"],
    evidenceBindings: [
      { id: "textbook-definition", sourceID: "current-document", locator: "第 2 节·二次函数图像" },
    ],
    budget: { maxHeight: 680, maxNodes: 32, maxSeries: 6, graphics: "canvas" },
    source: `$a = 1.2
root = RichAnswerRoot("数学 · 参数理解", "拖动 a，别先背结论", "把符号和绝对值拆成两次可见的变化。", "workbench", [controls, graph, explanation, sources])
controls = LearningStage("controls", "你来改变条件", [slider, live])
graph = LearningStage("visual", "图像立即回应", [plot])
explanation = LearningStage("explanation", "只保留当下有用的解释", [insight])
sources = LearningStage("evidence", "", [evidence])
slider = ParameterSlider("a", "参数 a", $a, -3, 3, 0.1, "跨过 0 时看开口翻转；远离 0 时看曲线收紧。")
live = ParameterReadout("a", $a, "开口方向与纵向伸缩由同一个参数控制。")
plot = FunctionPlot("y = ax²", "quadratic", "a", $a, [], -3, 3, 320)
insight = NarrativeBlock("关键机制", "x² 永远不小于 0；a 先决定结果是否翻到 x 轴下方，再决定每个高度被放大还是压缩。", "mechanism")
evidence = EvidenceSnippet("textbook-definition", "第 2 节·二次函数图像", "对比 y=x²、y=2x² 与 y=-x² 的图像。", "这条材料支撑的是“符号决定方向，绝对值决定伸缩”。")`,
  },
  {
    version: "weibei.openui.v1",
    id: "quadratic-compare",
    title: "对比诊断",
    question,
    mode: "declarative",
    capabilities: ["curve-comparison", "focus-selector", "comparison-table", "evidence-jump"],
    evidenceBindings: [
      { id: "worked-example", sourceID: "current-document", locator: "例 3·参数对比" },
    ],
    budget: { maxHeight: 680, maxNodes: 40, maxSeries: 6, graphics: "canvas" },
    source: `$focus = 0.5
root = RichAnswerRoot("数学 · 对比诊断", "同时看四条曲线，再锁定差别", "当问题是“哪里不同”，对比比单条滑杆更直接。", "comparison", [chooserStage, chartStage, tableStage, sourceStage])
chooserStage = LearningStage("controls", "", [chooser])
chartStage = LearningStage("visual", "一张图里只高亮当前样本", [family])
tableStage = LearningStage("full", "", [table, distinction])
sourceStage = LearningStage("evidence", "", [evidence])
chooser = ValuePicker("focus", "聚焦一条曲线", $focus, [-2, -0.5, 0.5, 2], "a =")
family = FunctionPlot("四种 a 的形状对比", "quadratic", "focus", $focus, [-2, -0.5, 0.5, 2], -3, 3, 300)
row1 = ComparisonRow("a = -2", -2, "向下", "窄", "翻转并纵向拉伸")
row2 = ComparisonRow("a = -0.5", -0.5, "向下", "宽", "翻转并纵向压缩")
row3 = ComparisonRow("a = 0.5", 0.5, "向上", "宽", "保持方向并纵向压缩")
row4 = ComparisonRow("a = 2", 2, "向上", "窄", "保持方向并纵向拉伸")
table = ComparisonTable("focus", $focus, [row1, row2, row3, row4])
distinction = NarrativeBlock("判别顺序", "先看正负判断上下，再比较 |a| 判断宽窄；不要把两个问题混成一个口诀。", "diagnosis")
evidence = EvidenceSnippet("worked-example", "例 3·参数对比", "在同一坐标系中画出四个参数样本。", "表格中的每一行都能回到这组例题。")`,
  },
  {
    version: "weibei.openui.v1",
    id: "quadratic-reasoning",
    title: "推导路径",
    question,
    mode: "declarative",
    capabilities: ["process-stepper", "mechanism-board", "follow-up-action", "evidence-jump"],
    evidenceBindings: [
      { id: "definition-chain", sourceID: "current-document", locator: "定义旁注·从 x 到 ax²" },
    ],
    budget: { maxHeight: 680, maxNodes: 36, maxSeries: 2, graphics: "dom" },
    source: `$step = 0
root = RichAnswerRoot("数学 · 机制推导", "不背图像，沿计算顺序走一遍", "这种界面适合“我知道结论，但不知道为什么”。", "reasoning", [stepsStage, mechanismStage, closeStage])
stepsStage = LearningStage("controls", "点步骤改变解释焦点", [stepper])
mechanismStage = LearningStage("visual", "", [mechanism])
closeStage = LearningStage("full", "", [summary, evidence, followup])
s1 = ReasonStep("输入 x", "先选一个横坐标，它可以在原点两侧。")
s2 = ReasonStep("平方 x²", "正负号被消去，所有结果都落在非负一侧。")
s3 = ReasonStep("乘以 a", "a 的符号决定是否翻转，|a| 决定高度被放大多少。")
s4 = ReasonStep("放回坐标系", "每个 x 都经历同一条变换链，所有点连成抛物线。")
stepper = ProcessStepper("step", $step, [s1, s2, s3, s4])
mechanism = QuadraticMechanism("step", $step, -1.5)
summary = NarrativeBlock("机制回看", "图像的开口与宽窄，是“先平方，再乘 a”在整个坐标系上重复发生的结果。", "mechanism")
evidence = EvidenceSnippet("definition-chain", "定义旁注·从 x 到 ax²", "对函数值的运算顺序做逐步拆解。", "这条证据用于证明机制，不是再给一张结论图。")
followup = FollowUpAction("换成 y = a(x-h)²+k 再试", "继续学习平移后的二次函数")`,
  },
  {
    version: "weibei.openui.v1",
    id: "line-composition",
    title: "双点关系",
    question: "两点怎样共同决定一条直线？",
    mode: "declarative",
    capabilities: ["direct-manipulation", "coordinate-canvas", "linked-equation", "evidence-jump"],
    evidenceBindings: [
      { id: "line-definition", sourceID: "current-document", locator: "一次函数·两点式" },
    ],
    budget: { maxHeight: 680, maxNodes: 28, maxSeries: 2, graphics: "canvas" },
    source: `$x1 = -3
$y1 = -1.2
$x2 = 2.5
$y2 = 2.1
root = RichAnswerRoot("数学 · 关系实验", "拖两个点，让公式自己变化", "直线、斜率三角形和公式共享同一组点状态。", "flow", [visual, close])
visual = LearningStage("visual", "", [lab])
close = LearningStage("evidence", "", [insight, evidence])
lab = TwoPointLineLab("x1", $x1, "y1", $y1, "x2", $x2, "y2", $y2, "两点决定直线", -5, 5, -4, 4, 320)
insight = NarrativeBlock("观察任务", "先把两点调到同一高度，再让它们接近同一横坐标；比较斜率为零和斜率未定义。", "mechanism")
evidence = EvidenceSnippet("line-definition", "一次函数·两点式", "两点横坐标不同时，存在唯一一次函数经过这两点。", "拖点实验验证的是唯一性与变化率。")`,
  },
  {
    version: "weibei.openui.v1",
    id: "equilibrium-composition",
    title: "动态平衡",
    question: "动态平衡为什么不是反应停止？",
    mode: "declarative",
    capabilities: ["parameter-control", "animated-particles", "linked-rates", "evidence-jump"],
    evidenceBindings: [
      { id: "equilibrium-source", sourceID: "current-document", locator: "化学平衡·速率解释" },
    ],
    budget: { maxHeight: 680, maxNodes: 28, maxSeries: 2, graphics: "dom" },
    source: `$shift = 0
root = RichAnswerRoot("化学 · 双向系统", "扰动之后，两个方向都没有停", "调节扰动，观察粒子数量与正逆速率怎样先分离、再趋近。", "workbench", [controls, visual, explanation, source])
controls = LearningStage("controls", "投入扰动", [slider])
visual = LearningStage("visual", "粒子与速率共用状态", [balance])
explanation = LearningStage("explanation", "不要把平衡理解成静止", [insight])
source = LearningStage("evidence", "", [evidence])
slider = ParameterSlider("shift", "扰动方向", $shift, -1, 1, 0.1, "向左偏增加生成物侧影响，向右偏增加反应物侧影响。")
balance = BalanceExperiment("shift", $shift, "A ⇌ B", "A 粒子", "B 粒子", "正向过程", "逆向过程", "两边都持续变化；相等的是宏观速率，不是微观运动归零。")
insight = NarrativeBlock("判断标准", "观察正逆速率是否接近，而不是看粒子是否还在运动。", "diagnosis")
evidence = EvidenceSnippet("equilibrium-source", "化学平衡·速率解释", "平衡时正反应速率等于逆反应速率。", "这条定义约束了界面中的判断标准。")`,
  },
  {
    version: "weibei.openui.v1",
    id: "argument-composition",
    title: "论证点读",
    question: "这段文字的主张、证据和反驳分别是什么？",
    mode: "declarative",
    capabilities: ["source-alignment", "argument-focus", "evidence-jump"],
    evidenceBindings: [
      { id: "argument-p1", sourceID: "current-document", locator: "第 1 句" },
      { id: "argument-p2", sourceID: "current-document", locator: "第 2 句" },
      { id: "argument-p3", sourceID: "current-document", locator: "第 3 句" },
      { id: "argument-p4", sourceID: "current-document", locator: "第 4 句" },
      { id: "argument-p5", sourceID: "current-document", locator: "第 5 句" },
    ],
    budget: { maxHeight: 700, maxNodes: 34, maxSeries: 2, graphics: "dom" },
    source: `$focus = 0
root = RichAnswerRoot("文本 · 原文剖面", "结论不是流程图，是原句之间的作用关系", "点选任一句，始终保留回到材料的路径。", "document", [reading])
reading = LearningStage("visual", "", [reader])
u1 = ArgumentUnit("claim", "主张", "公共空间的价值，在于允许陌生人低成本共同停留。", "作者真正要证明的结论。", "argument-p1")
u2 = ArgumentUnit("reason", "理由", "不必先消费，人们才可能形成弱联系。", "主张依赖的机制。", "argument-p2")
u3 = ArgumentUnit("evidence", "证据", "移除围栏后，平均停留时长从 11 分钟增加到 27 分钟。", "可核验数据，但还不是完整因果。", "argument-p3")
u4 = ArgumentUnit("counter", "反驳", "同期增加的树荫与座椅也可能延长停留。", "指出替代原因。", "argument-p4")
u5 = ArgumentUnit("response", "回应", "观察支持降低门槛有作用，却不足以证明它是唯一原因。", "收紧结论，避免过度归因。", "argument-p5")
reader = ArgumentReader("focus", $focus, "逐句点读", [u1, u2, u3, u4, u5])`,
  },
  {
    version: "weibei.openui.v1",
    id: "sampling-composition",
    title: "抽样波动",
    question: "为什么一个样本不能自动代表总体？",
    mode: "declarative",
    capabilities: ["linked-chart", "focus-probe", "metric-readout", "evidence-jump"],
    evidenceBindings: [
      { id: "sampling-source", sourceID: "current-document", locator: "样本组表" },
    ],
    budget: { maxHeight: 680, maxNodes: 30, maxSeries: 4, graphics: "canvas" },
    source: `$focus = 0
root = RichAnswerRoot("统计 · 样本波动", "点不同样本，看均值怎样摆动", "不是用一张仪表盘宣布结论，而是直接比较每次抽样的偏差。", "flow", [visual, metrics, close])
visual = LearningStage("visual", "", [chart])
metrics = LearningStage("full", "总体基准", [strip])
close = LearningStage("evidence", "", [insight, evidence])
meanSeries = ChartSeries("样本均值", "line", [39.2, 44.8, 35.6, 41.3, 47.1, 38.7], "分", "jade")
medianSeries = ChartSeries("样本中位数", "line", [38, 45, 34, 42, 48, 39], "分", "ochre")
chart = LinkedDataChart("focus", $focus, "六次抽样结果", ["样本 1", "样本 2", "样本 3", "样本 4", "样本 5", "样本 6"], [meanSeries, medianSeries], "点击任意样本，读数和聚焦线一起移动。", 280)
m1 = MetricItem("总体均值", "41.0", "分", "所有观测", "neutral")
m2 = MetricItem("最大偏差", "6.1", "分", "样本 5", "warning")
m3 = MetricItem("抽样次数", "6", "组", "每组样本量相同", "neutral")
strip = MetricStrip([m1, m2, m3])
insight = NarrativeBlock("真正要看的", "每组样本都有自己的均值；样本量、抽取方式和偶然性共同决定它离总体有多远。", "mechanism")
evidence = EvidenceSnippet("sampling-source", "样本组表", "六次抽样使用相同样本量，但得到不同均值。", "图中的每个点对应材料中的一组抽样。")`,
  },
  {
    version: "weibei.openui.v1",
    id: "cashflow-composition",
    title: "现金流传导",
    question: "估值为什么会对长期假设特别敏感？",
    mode: "declarative",
    capabilities: ["mixed-series-chart", "focus-probe", "metric-readout", "evidence-jump"],
    evidenceBindings: [
      { id: "cashflow-source", sourceID: "current-document", locator: "估值假设表" },
    ],
    budget: { maxHeight: 700, maxNodes: 34, maxSeries: 5, graphics: "canvas" },
    source: `$focus = 0
root = RichAnswerRoot("金融 · 假设传导", "沿年份看收入与现金流，不把估值做成黑箱", "点击年份查看收入和自由现金流，再回到终值占比判断敏感性。", "flow", [visual, metrics, close])
visual = LearningStage("visual", "", [chart])
metrics = LearningStage("full", "结果边界", [strip])
close = LearningStage("evidence", "", [insight, evidence])
revenue = ChartSeries("收入", "line", [120, 130, 140, 151, 163], "百万元", "indigo")
cashflow = ChartSeries("自由现金流", "bar", [21.6, 23.4, 25.2, 27.2, 29.3], "百万元", "moss")
chart = LinkedDataChart("focus", $focus, "五年经营传导", ["第 1 年", "第 2 年", "第 3 年", "第 4 年", "第 5 年"], [revenue, cashflow], "点击年份查看同一时期的收入与现金流。", 280)
m1 = MetricItem("显式期现值", "94", "百万元", "五年折现现金流", "neutral")
m2 = MetricItem("终值占比", "72", "%", "长期假设影响较大", "warning")
m3 = MetricItem("折现率", "11", "%", "材料给定假设", "neutral")
strip = MetricStrip([m1, m2, m3])
insight = NarrativeBlock("敏感性来源", "终值代表显式预测期之后的长期现金流；占比越高，估值越依赖无法直接观察的长期假设。", "diagnosis")
evidence = EvidenceSnippet("cashflow-source", "估值假设表", "收入增长 8%，现金流率 18%，折现率 11%。", "所有序列和读数都来自这组假设的可核验计算。")`,
  },
  {
    version: "weibei.openui.v1",
    id: "policy-composition",
    title: "政策证据",
    question: "怎样区分政策之后发生的变化与政策造成的变化？",
    mode: "declarative",
    capabilities: ["causal-focus", "confidence-boundary", "evidence-jump"],
    evidenceBindings: [
      { id: "policy-1", sourceID: "current-document", locator: "政策发布" },
      { id: "policy-2", sourceID: "current-document", locator: "市场反应" },
      { id: "policy-3", sourceID: "current-document", locator: "供给修复" },
      { id: "policy-4", sourceID: "current-document", locator: "通胀回落" },
    ],
    budget: { maxHeight: 680, maxNodes: 30, maxSeries: 2, graphics: "dom" },
    source: `$event = 1
root = RichAnswerRoot("经济 · 证据路径", "时间线只负责排序，证据强度负责因果", "选择节点查看它能证明什么，也保留不能证明的边界。", "timeline", [path])
path = LearningStage("visual", "", [track])
e1 = CausalEvent("Q1", "政策发布", "action", "政策行动", "起点", "strong", "政策文本明确记录了工具与实施时间。", "policy-1")
e2 = CausalEvent("Q2", "预期变化", "result", "短期反应", "紧随政策", "medium", "市场预期在发布后变化，但同期还有外部冲击。", "policy-2")
e3 = CausalEvent("Q3", "供给修复", "context", "并行条件", "另一条机制", "strong", "供应恢复独立影响价格，不能从政策链中删掉。", "policy-3")
e4 = CausalEvent("Q5", "通胀回落", "uncertain", "长期结果", "只有先后", "insufficient", "回落发生在政策之后，但材料不足以把全部变化归给政策。", "policy-4")
track = CausalTrack("event", $event, "政策与指标的证据链", [e1, e2, e3, e4])`,
  },
  {
    version: "weibei.openui.v1",
    id: "code-composition",
    title: "执行轨道",
    question: "冒泡排序每一步怎样改变数组？",
    mode: "declarative",
    capabilities: ["process-stepper", "code-state-link", "local-state", "evidence-jump"],
    evidenceBindings: [
      { id: "code-source", sourceID: "current-document", locator: "冒泡排序示例" },
    ],
    budget: { maxHeight: 700, maxNodes: 42, maxSeries: 2, graphics: "dom" },
    source: `$step = 0
root = RichAnswerRoot("代码 · 状态执行", "代码行、比较对象和数组状态一起走", "每一帧由真实执行结果给出，界面不会在本地运行模型生成的代码。", "track", [execution, source])
execution = LearningStage("visual", "", [track])
source = LearningStage("evidence", "", [evidence])
f1 = ExecutionFrame("准备比较", 1, ["5", "2", "4", "1"], [0, 1], "比较 a[0] 与 a[1]。")
f2 = ExecutionFrame("第一次交换", 2, ["2", "5", "4", "1"], [0, 1], "5 大于 2，交换后较大值向右移动。")
f3 = ExecutionFrame("继续比较", 1, ["2", "5", "4", "1"], [1, 2], "比较 a[1] 与 a[2]。")
f4 = ExecutionFrame("第二次交换", 2, ["2", "4", "5", "1"], [1, 2], "5 大于 4，再向右移动一位。")
f5 = ExecutionFrame("本轮结束", 3, ["2", "4", "1", "5"], [2, 3], "最大值 5 已沉到本轮末尾。")
track = ExecutionTrack("step", $step, "冒泡排序 · 第一轮", ["for i in 0..<end", "  if a[i] > a[i+1]", "    swap(a[i], a[i+1])", "end -= 1"], [f1, f2, f3, f4, f5])
evidence = EvidenceSnippet("code-source", "冒泡排序示例", "相邻元素逆序时交换，每轮把当前最大值移动到末尾。", "执行帧严格对应这段代码和输入数组。")`,
  },
];

export function programForID(id: string | null) {
  return generatedPrograms.find((program) => program.id === id) ?? generatedPrograms[0];
}
