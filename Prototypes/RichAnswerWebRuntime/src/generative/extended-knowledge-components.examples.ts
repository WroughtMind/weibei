export const extendedKnowledgeComponentExamples = {
  layeredSpatialView: `$visible = ["ground", "route", "site"]
$selected = "site-a"
root = RichAnswerRoot("空间", "查看空间关系", "切换图层并点选位置。", "flow", [stage])
stage = LearningStage("visual", "", [view])
ground = SpatialLayer("ground", "区域", "region", true, "stone")
route = SpatialLayer("route", "路径", "path", true, "ochre")
site = SpatialLayer("site", "点位", "point", true, "water")
region = SpatialRegion("region-a", "ground", "范围", [0.05, 0.18, 0.9, 0.12, 0.96, 0.82, 0.1, 0.9], "stone")
path = SpatialPath("path-a", "route", "连接路径", [0.15, 0.72, 0.42, 0.46, 0.82, 0.28], "primary", "ochre")
pointA = SpatialPoint("site-a", "site", "甲点", 0.42, 0.46, "路径与区域的交会位置。", "focus")
pointB = SpatialPoint("site-b", "site", "乙点", 0.82, 0.28, "路径的另一端。", "normal")
view = LayeredSpatialView("visible", $visible, "selected", $selected, "空间关系", [ground, route, site], [region], [path], [pointA, pointB], 20, "km", "图层和点位均由通用数据驱动。")`,

  distributionBrush: `$center = 40
$span = 16
root = RichAnswerRoot("统计", "比较总体与样本", "拖动样本窗口查看偏差。", "flow", [stage])
stage = LearningStage("visual", "", [brush])
brush = DistributionBrush("center", $center, "span", $span, "总体与样本窗口", [21, 28, 31, 33, 35, 36, 38, 39, 40, 41, 43, 45, 47, 52, 58, 67], "分", 10, "拖动阴影窗口，或调节窗口宽度。")`,

  dependencyFlow: `$inputs = [100, 1.08, 0.18, 1.11]
$focus = 0
root = RichAnswerRoot("金融", "观察一期现金流现值", "调节输入并查看收入怎样逐层变成现值。", "flow", [stage])
stage = LearningStage("visual", "", [flow])
revenue = FlowAssumption("revenue", "基准收入", 50, 200, 5, "百万元", "本期收入基数。")
growthFactor = FlowAssumption("growth-factor", "收入增长倍数", 1, 1.2, 0.01, "×", "1.08 表示增长 8%。")
cashflowRate = FlowAssumption("cashflow-rate", "现金流率", 0.05, 0.35, 0.01, "×", "收入转成自由现金流的比例。")
discountFactor = FlowAssumption("discount-factor", "折现倍数", 1.01, 1.25, 0.01, "×", "1.11 对应一期折现率 11%。")
projectedRevenue = DependencyNode("projected-revenue", "下一期收入", 1, "product", ["revenue", "growth-factor"], [], "百万元", 2, "基准收入乘以增长倍数。")
freeCashFlow = DependencyNode("free-cash-flow", "下一期自由现金流", 2, "product", ["projected-revenue", "cashflow-rate"], [], "百万元", 2, "下一期收入乘以现金流率。")
presentValue = DependencyNode("present-value", "一期现金流现值", 3, "ratio", ["free-cash-flow", "discount-factor"], [], "百万元", 2, "自由现金流除以折现倍数。")
metric = FlowMetric("present-value", "一期现金流现值", "百万元", 2, "primary", "显示当前现值与聚焦输入的一步敏感性。")
flow = DependencyFlow("inputs", $inputs, "focus", $focus, "一期现金流现值传导", [revenue, growthFactor, cashflowRate, discountFactor], [projectedRevenue, freeCashFlow, presentValue], [metric], "计算链为收入 × 增长倍数 × 现金流率 ÷ 折现倍数。")`,
} as const;
