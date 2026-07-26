import { openUIComponentConstraintGuidance } from "./rich-answer-validation";


export const OPENUI_COMPONENT_SIGNATURES = {
  RichAnswerRoot: "RichAnswerRoot(eyebrow, title, summary, layout, stages)",
  LearningStage: "LearningStage(role, title, children)",
  NarrativeBlock: "NarrativeBlock(title, text, tone)",
  ParameterSlider: "ParameterSlider(name, label, $value, minimum, maximum, step, caption)",
  ParameterReadout: "ParameterReadout(name, $value, caption)",
  ValuePicker: "ValuePicker(name, label, $value, options, prefix)",
  FunctionPlot: "FunctionPlot(title, family, parameterName, $parameter, compareValues, xMinimum, xMaximum, height)",
  ComparisonRow: "ComparisonRow(label, coefficient, direction, width, interpretation)",
  ComparisonTable: "ComparisonTable(focusName, $focus, rows)",
  EvidenceSnippet: "EvidenceSnippet(evidenceID, locator, quote, relation)",
  ReasonStep: "ReasonStep(title, explanation)",
  ProcessStepper: "ProcessStepper(stateName, $activeStep, steps)",
  QuadraticMechanism: "QuadraticMechanism(stateName, $activeStep, coefficient)",
  FollowUpAction: "FollowUpAction(label, userMessage)",
  ChartSeries: "ChartSeries(name, kind, values, unit, color)",
  LinkedDataChart: "LinkedDataChart(stateName, $focusIndex, title, xLabels, series, caption, height)",
  MetricItem: "MetricItem(label, value, unit, detail, tone)",
  MetricStrip: "MetricStrip(items)",
  ExecutionFrame: "ExecutionFrame(label, activeLine, values, changedIndices, explanation)",
  ExecutionTrack: "ExecutionTrack(stateName, $activeStep, title, codeLines, frames)",
  ArgumentUnit: "ArgumentUnit(role, roleLabel, text, note, evidenceID)",
  ArgumentReader: "ArgumentReader(stateName, $activeUnit, title, units)",
  CausalEvent: "CausalEvent(time, label, kind, kindLabel, relationFromPrevious, confidence, detail, evidenceID)",
  CausalTrack: "CausalTrack(stateName, $activeEvent, title, events)",
  TwoPointLineLab: "TwoPointLineLab(x1Name, $x1, y1Name, $y1, x2Name, $x2, y2Name, $y2, title, xMinimum, xMaximum, yMinimum, yMaximum, height)",
  BalanceExperiment: "BalanceExperiment(stateName, $shift, title, leftLabel, rightLabel, forwardLabel, reverseLabel, caption)",
  SpatialLayer: "SpatialLayer(id, label, kind, defaultVisible, tone)",
  SpatialRegion: "SpatialRegion(id, layerID, label, coordinates, tone)",
  SpatialPath: "SpatialPath(id, layerID, label, coordinates, kind, tone)",
  SpatialPoint: "SpatialPoint(id, layerID, label, x, y, detail, importance, evidenceID?)",
  LayeredSpatialView: "LayeredSpatialView(visibilityStateName, $visibleLayerIDs, selectionStateName, $selectedPointID, title, layers, regions, paths, points, scaleDistance, scaleUnit, caption)",
  DistributionBrush: "DistributionBrush(centerStateName, $windowCenter, spanStateName, $windowSpan, title, values, unit, binCount, caption)",
  FlowAssumption: "FlowAssumption(id, label, minimum, maximum, step, unit, detail)",
  DependencyNode: "DependencyNode(id, label, layer, operation, sourceIDs, parameters, unit, precision, detail)",
  FlowMetric: "FlowMetric(nodeID, label, unit, precision, emphasis, detail)",
  DependencyFlow: "DependencyFlow(valuesStateName, $inputValues, focusStateName, $focusedInputIndex, title, assumptions, nodes, metrics, caption)",
} as const;


export type OpenUIComponentName = keyof typeof OPENUI_COMPONENT_SIGNATURES;


export const OPENUI_COMPONENT_ORDER = Object.keys(OPENUI_COMPONENT_SIGNATURES) as OpenUIComponentName[];


export const OPENUI_COMPONENT_GUIDANCE: Partial<Record<OpenUIComponentName, string>> = {
  RichAnswerRoot: "Agent 回答流中的生成式视觉体验块根；title/summary 只作局部导向，不得形成第二套正文；layout: workbench|comparison|reasoning|flow|document|timeline|track",
  LearningStage: "title 只标记当前操作区域，可留空或使用 null；role: controls|visual|explanation|evidence|full",
  NarrativeBlock: "用于局部状态解释、读数含义或互动反馈，不得复述正文或另写摘要/结论；tone: mechanism|diagnosis|neutral",
  EvidenceSnippet: "只承担来源定位与回原文；evidenceID 必须来自当前 scene.evidenceIDs",
  FunctionPlot: "family 当前固定写 \"quadratic\"，表示由本地内核绘制 y=a·x²；不要把公式或表达式传进 family",
  ProcessStepper: "先逐行声明 s1 = ReasonStep(...) 等步骤，再写 [s1, s2]；组件引用不加引号，也不要嵌套组件调用",
  ChartSeries: "kind: line|bar；color: cinnabar|jade|ochre|indigo|umber|moss",
  LayeredSpatialView: "跨地理、历史、艺术与图像观察使用；只接收归一化区域、路径、点位和语义图层，不接收 SVG path",
  DistributionBrush: "跨统计、实验与数据阅读使用；总体数值由模型提供，窗口统计由本地组件计算。windowSpan 是完整窗口宽度，实际范围为 [windowCenter - windowSpan/2, windowCenter + windowSpan/2]；例如覆盖 10–50 应设 center=30、span=40，覆盖 10–13 应设 center=11.5、span=3。初始窗口应显示与学习目标有关的观测，除非空窗口本身就是观察对象；caption 必须描述运行时实际范围",
  DependencyFlow: "跨金融、经济、自然科学与系统分析使用；只接收受限运算节点，不接收表达式或代码",
};


export const OPENUI_ALWAYS_COMPONENTS: OpenUIComponentName[] = [
  "RichAnswerRoot",
  "LearningStage",
  "NarrativeBlock",
  "EvidenceSnippet",
  "FollowUpAction",
];


export const OPENUI_COMPONENT_GROUPS = {
  quantitative: {
    label: "数量、函数与比较",
    components: [
      "ParameterSlider",
      "ParameterReadout",
      "ValuePicker",
      "FunctionPlot",
      "ComparisonRow",
      "ComparisonTable",
      "QuadraticMechanism",
    ] as OpenUIComponentName[],
  },
  data: {
    label: "数据、分布与读数",
    components: [
      "ChartSeries",
      "LinkedDataChart",
      "MetricItem",
      "MetricStrip",
      "DistributionBrush",
    ] as OpenUIComponentName[],
  },
  process: {
    label: "过程、状态与算法",
    components: [
      "ReasonStep",
      "ProcessStepper",
      "ExecutionFrame",
      "ExecutionTrack",
      "BalanceExperiment",
    ] as OpenUIComponentName[],
  },
  argument: {
    label: "原文、论证与证据",
    components: ["ArgumentUnit", "ArgumentReader"] as OpenUIComponentName[],
  },
  causal: {
    label: "因果与时间",
    components: ["CausalEvent", "CausalTrack"] as OpenUIComponentName[],
  },
  directExperiment: {
    label: "坐标与直接实验",
    components: ["TwoPointLineLab", "BalanceExperiment"] as OpenUIComponentName[],
  },
  spatial: {
    label: "空间、图层与点位",
    components: [
      "SpatialLayer",
      "SpatialRegion",
      "SpatialPath",
      "SpatialPoint",
      "LayeredSpatialView",
    ] as OpenUIComponentName[],
  },
  dependency: {
    label: "依赖、计算与传导",
    components: [
      "FlowAssumption",
      "DependencyNode",
      "FlowMetric",
      "DependencyFlow",
    ] as OpenUIComponentName[],
  },
} as const;


export type OpenUIComponentGroupName = keyof typeof OPENUI_COMPONENT_GROUPS;


export const RICH_ANSWER_STANDARD_CHART_TYPES = [
  "line",
  "bar",
  "area",
  "scatter",
  "mixed",
  "histogram",
] as const;


export type RichAnswerStandardChartType = typeof RICH_ANSWER_STANDARD_CHART_TYPES[number];


export function selectedOpenUIComponentGroups(
  knowledgeShapes: readonly string[],
  interactions: readonly string[],
): OpenUIComponentGroupName[] {
  const selected: OpenUIComponentGroupName[] = [];
  const add = (group: OpenUIComponentGroupName) => {
    if (!selected.includes(group) && selected.length < 3) selected.push(group);
  };
  for (const shape of knowledgeShapes) {
    switch (shape) {
      case "formula":
      case "comparison":
        add("quantitative");
        break;
      case "series":
      case "distribution":
        add("data");
        break;
      case "process":
      case "algorithmState":
        add("process");
        break;
      case "argument":
        add("argument");
        break;
      case "causalSequence":
        add("causal");
        break;
      case "spatialLayers":
      case "imageRegions":
        add("spatial");
        break;
      case "dependencyGraph":
        add("dependency");
        break;
      case "customGeometry":
        add("directExperiment");
        break;
      default:
        break;
    }
  }
  for (const interaction of interactions) {
    switch (interaction) {
      case "brush":
        add("data");
        break;
      case "step":
        add("process");
        break;
      case "focusEvidence":
        add("argument");
        break;
      case "toggleLayers":
        add("spatial");
        break;
      case "dragPoints":
        add("directExperiment");
        break;
      case "adjust":
        if (selected.length === 0) add("quantitative");
        break;
      default:
        break;
    }
  }
  return selected;
}


export function openUIComponentCatalog(names: readonly OpenUIComponentName[]): string[] {
  return OPENUI_COMPONENT_ORDER
    .filter((name) => names.includes(name))
    .map((name) => {
      const guidance = OPENUI_COMPONENT_GUIDANCE[name];
      const constraints = openUIComponentConstraintGuidance(name);
      const details = [guidance, constraints].filter((value) => value && value.length > 0);
      return `${OPENUI_COMPONENT_SIGNATURES[name]}${details.length > 0 ? ` // ${details.join("；")}` : ""}`;
    });
}


export const OPENUI_COMPONENT_CATALOG_SIZE = OPENUI_COMPONENT_ORDER.length;


export const RICH_ANSWER_LEARNING_ACTIONS = [
  "explain",
  "compare",
  "derive",
  "trace",
  "calculate",
  "observe",
  "manipulate",
  "evaluate",
  "practice",
] as const;


export const RICH_ANSWER_INTERACTION_ACTIONS = [
  "none",
  "adjust",
  "select",
  "step",
  "brush",
  "toggleLayers",
  "dragPoints",
  "focusEvidence",
  "probe",
] as const;


export const RICH_ANSWER_KNOWLEDGE_SHAPES = [
  "formula",
  "series",
  "distribution",
  "process",
  "algorithmState",
  "argument",
  "causalSequence",
  "spatialLayers",
  "dependencyGraph",
  "comparison",
  "imageRegions",
  "customGeometry",
] as const;


export type RichAnswerKnowledgeShape = typeof RICH_ANSWER_KNOWLEDGE_SHAPES[number];


export const RICH_ANSWER_KNOWLEDGE_NATURES = [
  "functionOrDataCurve",
  "objectMechanism",
  "spatialStructure",
  "processOrState",
  "argumentOrEvidence",
  "imageObservation",
  "comparisonOrEvaluation",
  "calculationOrConstraint",
] as const;


export const RICH_ANSWER_SPATIAL_DIMENSIONS = [
  "notSpatial",
  "oneDimensional",
  "twoDimensional",
  "threeDimensional",
] as const;


export const RICH_ANSWER_TEMPORAL_BEHAVIORS = ["static", "stateChange", "timeEvolution"] as const;


export const RICH_ANSWER_DATA_ORIGINS = [
  "sourceObserved",
  "derivedFromSource",
  "deterministicSimulation",
  "sourceAsset",
  "conceptual",
] as const;


export const RICH_ANSWER_COORDINATE_FRAMES = [
  "none",
  "categorical",
  "cartesian",
  "polar",
  "geometric",
  "imagePixel",
  "geographic",
  "threeDimensional",
] as const;


export const RICH_ANSWER_COMPUTE_NEEDS = ["none", "lightDeterministic", "heavyOrExternal"] as const;


export const RICH_ANSWER_PRECISION_NEEDS = ["illustrative", "quantitative", "measurementSensitive"] as const;


export const RICH_ANSWER_ASSET_DEPENDENCIES = ["none", "currentSourceAssetRequired"] as const;


export interface RichAnswerRepresentationNeeds {
  spatialDimension: typeof RICH_ANSWER_SPATIAL_DIMENSIONS[number];
  temporalBehavior: typeof RICH_ANSWER_TEMPORAL_BEHAVIORS[number];
  dataOrigin: typeof RICH_ANSWER_DATA_ORIGINS[number];
  coordinateFrame: typeof RICH_ANSWER_COORDINATE_FRAMES[number];
  computeNeed: typeof RICH_ANSWER_COMPUTE_NEEDS[number];
  precisionNeed: typeof RICH_ANSWER_PRECISION_NEEDS[number];
  assetDependency: typeof RICH_ANSWER_ASSET_DEPENDENCIES[number];
}


export const RICH_ANSWER_T2_PRIMITIVE_ROLES = [
  "vstack",
  "hstack",
  "zstack",
  "grid",
  "panel",
  "canvas",
  "text",
  "metric",
  "sequence",
  "axis",
  "line",
  "path",
  "point",
  "area",
  "vector",
  "region",
  "shape",
  "bar",
  "dotMatrix",
  "image",
  "label",
  "divider",
  "slider",
  "toggle",
  "scrubber",
  "select",
  "reset",
  "probe",
  "evidence",
] as const;


export const RICH_ANSWER_CHART_KINDS = RICH_ANSWER_STANDARD_CHART_TYPES;