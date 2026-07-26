import {
  LIMITS,
  RICH_ANSWER_CATALOG_TOOL,
  isRecord,
} from "./agent-context";
import {
  RICH_ANSWER_CHART_KINDS,
  RICH_ANSWER_INTERACTION_ACTIONS,
  RichAnswerKnowledgeShape,
  RichAnswerRepresentationNeeds,
  RichAnswerStandardChartType,
} from "./rich-answer-component-catalog";


export interface RichAnswerRendererRegistration {
  id: string;
  label: string;
  specVersion: string;
  validatorKind:
    | "chart"
    | "mathFunction"
    | "geometry2D"
    | "scene3D"
    | "spatialMap"
    | "imageOverlay";
  knowledgeShapes: readonly RichAnswerKnowledgeShape[];
  interactionActions: readonly (typeof RICH_ANSWER_INTERACTION_ACTIONS[number])[];
  interactionBindingKinds: readonly string[];
  standardKinds: readonly RichAnswerStandardChartType[];
  representationSupport: {
    spatialDimensions: readonly RichAnswerRepresentationNeeds["spatialDimension"][];
    temporalBehaviors: readonly RichAnswerRepresentationNeeds["temporalBehavior"][];
    dataOrigins: readonly RichAnswerRepresentationNeeds["dataOrigin"][];
    coordinateFrames: readonly RichAnswerRepresentationNeeds["coordinateFrame"][];
    computeNeeds: readonly RichAnswerRepresentationNeeds["computeNeed"][];
    precisionNeeds: readonly RichAnswerRepresentationNeeds["precisionNeed"][];
    assetDependencies: readonly RichAnswerRepresentationNeeds["assetDependency"][];
  };
  allowedSpecFields: readonly string[];
  allowedSeriesFields: readonly string[];
  forbiddenSpecFields: readonly string[];
  specGuidance: string;
  minimalSpecSkeleton: Record<string, unknown>;
  budgets: {
    maxNodes: number;
    maxSeries: number;
    maxDataPoints: number;
    maxArtifacts: number;
    maxBytes: number;
    maxWidth: number;
    maxHeight: number;
    maxAnimationFPS: number;
    maxInteractionLatencyMS: number;
    allowAnimation: boolean;
    allowWebGL: boolean;
    allowNetwork: boolean;
  };
}


export const RICH_ANSWER_RENDERER_REGISTRATIONS: readonly RichAnswerRendererRegistration[] = [
  {
    id: "weibei.echarts.chart",
    label: "注册专业图表渲染器",
    specVersion: "weibei.chart.v1",
    validatorKind: "chart",
    knowledgeShapes: ["series", "distribution"],
    interactionActions: ["none", "select", "focusEvidence", "probe"],
    interactionBindingKinds: ["probe", "select"],
    standardKinds: RICH_ANSWER_CHART_KINDS,
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange"],
      dataOrigins: ["sourceObserved", "derivedFromSource"],
      coordinateFrames: ["categorical", "cartesian"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative"],
      assetDependencies: ["none"],
    },
    allowedSpecFields: [
      "chartKind",
      "title",
      "series",
      "xLabels",
      "xAxisLabel",
      "yAxisLabel",
      "caption",
      "focusEnabled",
      "binCount",
      "samples",
    ],
    allowedSeriesFields: ["name", "values", "xValues", "chartKind", "unit"],
    forbiddenSpecFields: [
      "rawOption",
      "option",
      "options",
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "query",
      "mutation",
      "url",
      "iframe",
    ],
    specGuidance:
      "只提交有语义的系列、分组标签、散点 xValues/values 数值对或直方图原始样本；坐标轴、布局、响应式与 Canvas 绘制由本地 ECharts 适配器负责。",
    minimalSpecSkeleton: {
      chartKind: "line",
      series: [{ name: "语义系列名", values: [0, 1, 2], unit: "真实单位" }],
      xLabels: ["状态一", "状态二", "状态三"],
      xAxisLabel: "横轴语义",
      yAxisLabel: "纵轴语义",
      caption: "这张图帮助用户检查什么",
      focusEnabled: true,
    },
    budgets: {
      maxNodes: LIMITS.richAnswerRenderPlanNodes,
      maxSeries: LIMITS.richAnswerRenderPlanSeries,
      maxDataPoints: LIMITS.richAnswerRenderPlanDataPoints,
      maxArtifacts: 0,
      maxBytes: LIMITS.richAnswerRenderPlanSpecBytes,
      maxWidth: 960,
      maxHeight: 640,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 120,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.math.function",
    label: "受限数学函数渲染器",
    specVersion: "weibei.math-function.v1",
    validatorKind: "mathFunction",
    knowledgeShapes: ["formula"],
    interactionActions: ["none", "adjust", "probe"],
    interactionBindingKinds: ["probe", "slider"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange"],
      dataOrigins: ["derivedFromSource", "deterministicSimulation"],
      coordinateFrames: ["cartesian"],
      computeNeeds: ["lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative"],
      assetDependencies: ["none"],
    },
    allowedSpecFields: [
      "title",
      "variable",
      "domain",
      "parameters",
      "expression",
      "xAxisLabel",
      "yAxisLabel",
      "caption",
      "probeEnabled",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "points",
      "samples",
      "series",
      "rawOption",
      "option",
      "options",
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
    ],
    specGuidance:
      "模型只提交受限表达式图（常数、变量、参数与白名单运算）、定义域和可调参数；不提交采样点、SVG path 或图表配置。本地渲染器负责自适应采样、间断切段、设备像素比和窄宽布局。",
    minimalSpecSkeleton: {
      title: "参数怎样改变函数",
      variable: "x",
      domain: { minimum: -4, maximum: 4 },
      parameters: [{ id: "p", label: "参数 p", value: 1, minimum: -3, maximum: 3, step: 0.1 }],
      expression: {
        rootNodeID: "root",
        nodes: [
          { id: "x", kind: "variable" },
          { id: "p", kind: "parameter", parameterID: "p" },
          { id: "root", kind: "operation", operation: "multiply", inputIDs: ["p", "x"] },
        ],
      },
      xAxisLabel: "x",
      yAxisLabel: "结果",
      probeEnabled: true,
    },
    budgets: {
      maxNodes: 64,
      maxSeries: 1,
      maxDataPoints: 1600,
      maxArtifacts: 0,
      maxBytes: LIMITS.richAnswerRenderPlanSpecBytes,
      maxWidth: 960,
      maxHeight: 640,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 120,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.geometry.2d",
    label: "受限二维几何与确定性实验渲染器",
    specVersion: "weibei.geometry-2d.v1",
    validatorKind: "geometry2D",
    knowledgeShapes: ["customGeometry", "process"],
    interactionActions: ["none", "adjust", "dragPoints", "probe", "select"],
    interactionBindingKinds: ["probe", "select", "slider", "toggle", "zoomPan"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange", "timeEvolution"],
      dataOrigins: ["derivedFromSource", "deterministicSimulation", "conceptual"],
      coordinateFrames: ["cartesian", "geometric"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative", "measurementSensitive"],
      assetDependencies: ["none"],
    },
    allowedSpecFields: [
      "title",
      "coordinateSpace",
      "points",
      "shapes",
      "controls",
      "readouts",
      "showAxes",
      "showGrid",
      "caption",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
      "pixelLayout",
    ],
    specGuidance:
      "提交点、线段、带箭头向量、多边形、有方向盒体、圆、角、轨迹、约束、离散状态、协调控件与语义读数的高层几何语义；状态可通过 visibleWhen 切换对象，不提交 SVG path 或像素布局。坐标换算、拖拽投影、状态联动和响应式绘制由本地适配器负责。",
    minimalSpecSkeleton: {
      title: "几何关系检查",
      coordinateSpace: { xMin: -1, xMax: 9, yMin: -1, yMax: 7, preserveAspectRatio: true },
      points: [
        { id: "A", label: "A", x: 0, y: 0, draggable: false },
        { id: "B", label: "B", x: 8, y: 0, draggable: false },
        { id: "C", label: "C", x: 4, y: 4, draggable: false },
      ],
      shapes: [
        { id: "AB", kind: "segment", from: "A", to: "B", label: "AB" },
        { id: "direction", kind: "vector", from: "A", to: "C", label: "方向" },
      ],
      controls: [{
        id: "state",
        label: "观察状态",
        value: 0,
        minimum: 0,
        maximum: 1,
        step: 1,
        options: [{ value: 0, label: "状态一" }, { value: 1, label: "状态二" }],
        presentation: "segmented",
        bindings: [],
      }],
      readouts: [
        { id: "length-ab", kind: "distance", label: "AB 长度", from: "A", to: "B", unit: "单位" },
        { id: "state-label", kind: "state", label: "当前状态", controlID: "state", options: [{ value: 0, label: "状态一" }, { value: 1, label: "状态二" }] },
      ],
      showAxes: true,
      showGrid: true,
      caption: "说明该图验证的条件而不是替代证明",
    },
    budgets: {
      maxNodes: 260,
      maxSeries: 0,
      maxDataPoints: 1200,
      maxArtifacts: 0,
      maxBytes: LIMITS.richAnswerRenderPlanSpecBytes,
      maxWidth: 960,
      maxHeight: 720,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 120,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.scene-3d",
    label: "受控三维场景渲染器",
    specVersion: "weibei.scene-3d.v1",
    validatorKind: "scene3D",
    knowledgeShapes: ["customGeometry", "spatialLayers", "process", "imageRegions"],
    interactionActions: ["none", "adjust", "toggleLayers", "probe", "select"],
    interactionBindingKinds: ["probe", "select", "slider", "toggle", "zoomPan"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["threeDimensional"],
      temporalBehaviors: ["static", "stateChange", "timeEvolution"],
      dataOrigins: ["derivedFromSource", "deterministicSimulation", "conceptual"],
      coordinateFrames: ["threeDimensional"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative"],
      assetDependencies: ["none"],
    },
    allowedSpecFields: [
      "title",
      "camera",
      "layers",
      "objects",
      "stateBinding",
      "states",
      "coordinateUnits",
      "bounds",
      "slices",
      "caption",
      "controls",
      "focusEnabled",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
      "modelUrl",
      "shader",
    ],
    specGuidance:
      "提交相机、坐标、点、折线、网格、曲面、分子、切片、图层与受控交互；比较多个结构或状态时，用 objects 承载共享对象，用 stateBinding.initial/control/label 与 states[].objects/readouts 切换状态。coordinateUnits 必须是 {x,y,z}，bounds 的 x/y/z 必须各自是 {min,max}；不要自行发明 controls 字段。默认使用本地确定性 Canvas 投影，不提交外链模型、着色器、WebGL 代码或装饰性三维。",
    minimalSpecSkeleton: {
      title: "空间结构观察",
      camera: { yaw: 35, pitch: 20, distance: 4.2, lookAt: [0, 0, 0], fov: 58 },
      layers: [{ id: "structure", title: "结构", visibleDefault: true }],
      objects: [],
      stateBinding: { initial: "state-a", control: "segmented", label: "比较状态" },
      states: [{
        id: "state-a",
        title: "状态 A",
        description: "用来源支持的空间关系说明这一状态",
        objects: [{
          id: "state-a-structure",
          kind: "molecule",
          layer: "structure",
          label: "空间结构",
          atoms: [
            { id: "center-a", element: "C", label: "中心原子", position: [0, 0, 0], role: "central" },
            { id: "terminal-a", element: "H", label: "成键原子", position: [1, 1, 1], role: "terminal" },
          ],
          bonds: [{ id: "bond-a", from: "center-a", to: "terminal-a", order: 1, style: "solid" }],
          electronDomains: [],
          angleMarkers: [],
          showAtomLabels: true,
          showBondLabels: false,
          showElectronDomains: true,
        }],
        readouts: [{ id: "state-a-reading", label: "关键读数", value: "来源支持的值" }],
      }],
      slices: [],
      controls: { allowLayerToggle: true, allowSlice: false, allowCameraDrag: true, allowReset: true, allowProbe: true },
      focusEnabled: true,
      caption: "旋转或聚焦时要帮助检查的空间关系",
    },
    budgets: {
      maxNodes: 24,
      maxSeries: 0,
      maxDataPoints: 3200,
      maxArtifacts: 0,
      maxBytes: LIMITS.richAnswerRenderPlanSpecBytes,
      maxWidth: 960,
      maxHeight: 720,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 160,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.spatial.map",
    label: "地图与空间图层渲染器",
    specVersion: "weibei.spatial.map.v1",
    validatorKind: "spatialMap",
    knowledgeShapes: ["spatialLayers", "causalSequence", "comparison"],
    interactionActions: ["none", "select", "toggleLayers", "probe"],
    interactionBindingKinds: ["probe", "select", "toggle", "zoomPan"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange"],
      dataOrigins: ["sourceObserved", "derivedFromSource", "sourceAsset", "conceptual"],
      coordinateFrames: ["cartesian", "geographic"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative", "measurementSensitive"],
      assetDependencies: ["none", "currentSourceAssetRequired"],
    },
    allowedSpecFields: [
      "title",
      "coordinateMode",
      "crs",
      "coordinateHint",
      "mapAsset",
      "bounds",
      "layers",
      "features",
      "scaleBar",
      "controls",
      "caption",
      "focusEnabled",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
      "tileUrl",
    ],
    specGuidance:
      "提交本地底图引用或无底图的示意空间，以及点、线、面、标签、图层、比例尺和显隐绑定；图形与标签必须共享 visibilityGroup 或 bindTo。",
    minimalSpecSkeleton: {
      title: "空间证据观察",
      coordinateMode: "schematic",
      coordinateHint: "坐标来自当前材料；若依赖原图，必须替换 CURRENT_MATERIAL_ASSET_ID",
      mapAsset: { kind: "assetRef", source: "CURRENT_MATERIAL_ASSET_ID", label: "当前材料底图" },
      layers: [{ id: "evidence", title: "证据层", visibleDefault: true }],
      features: [
        { id: "route", kind: "line", layer: "evidence", visibilityGroup: "route", points: [{ x: 0.2, y: 0.3 }, { x: 0.8, y: 0.7 }], label: "路线" },
        { id: "route-label", kind: "label", layer: "evidence", visibilityGroup: "route", bindTo: "route", x: 0.5, y: 0.5, text: "路线证据" },
      ],
      scaleBar: { enabled: false, label: "比例尺", targetPixels: 120 },
      controls: { allowPan: true, allowZoom: true, allowLayerToggle: true, allowReset: true, probeEnabled: true },
      focusEnabled: true,
      caption: "图形与标签共享显隐状态",
    },
    budgets: {
      maxNodes: 280,
      maxSeries: 0,
      maxDataPoints: 8000,
      maxArtifacts: 2,
      maxBytes: 1_500_000,
      maxWidth: 960,
      maxHeight: 720,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 140,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.image.overlay",
    label: "图像覆盖与观察渲染器",
    specVersion: "weibei.image-overlay.v1",
    validatorKind: "imageOverlay",
    knowledgeShapes: ["imageRegions", "spatialLayers", "comparison", "customGeometry"],
    interactionActions: ["none", "select", "toggleLayers", "probe"],
    interactionBindingKinds: ["annotation", "probe", "select", "slider", "toggle", "zoomPan"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange"],
      dataOrigins: ["sourceObserved", "derivedFromSource", "sourceAsset"],
      coordinateFrames: ["imagePixel"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative", "measurementSensitive"],
      assetDependencies: ["currentSourceAssetRequired"],
    },
    allowedSpecFields: [
      "title",
      "image",
      "objectFit",
      "measurement",
      "layers",
      "annotations",
      "comparison",
      "caption",
      "showReadout",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
    ],
    specGuidance:
      "提交当前材料中的本地位图引用、归一化坐标叠层、测量、批注与对照；line 可用 start/end 表示线段，也可用 points 表示折线。feature 默认使用 emphasis=subtle、tone=earth；只把少量关键证据设为 normal/strong，避免满图粗框与编号遮挡。图层、标签、批注和读数必须共享显隐状态，禁止外链和脚本型图片。",
    minimalSpecSkeleton: {
      title: "原图观察",
      image: { kind: "assetRef", source: "CURRENT_MATERIAL_ASSET_ID", label: "当前材料图像" },
      objectFit: "contain",
      measurement: { unit: "px", precision: 1 },
      layers: [{
        id: "observation",
        title: "观察层",
        visibleDefault: true,
          features: [{ id: "focus-region", kind: "rect", label: "观察区域", box: { x: 0.2, y: 0.2, width: 0.4, height: 0.3 }, emphasis: "subtle", tone: "earth" }],
        annotation: "说明该叠层怎样帮助判断",
      }],
      annotations: [{ id: "focus-note", layer: "observation", point: { x: 0.4, y: 0.35 }, text: "观察重点", color: "#8f4638" }],
      caption: "叠层坐标均为相对原图的归一化坐标",
      showReadout: false,
    },
    budgets: {
      maxNodes: 180,
      maxSeries: 0,
      maxDataPoints: 1200,
      maxArtifacts: 2,
      maxBytes: 1_500_000,
      maxWidth: 960,
      maxHeight: 720,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 140,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
];


export const RICH_ANSWER_RENDERER_REGISTRATION_BY_ID = new Map(
  RICH_ANSWER_RENDERER_REGISTRATIONS.map((registration) => [registration.id, registration]),
);


export function matchingRichAnswerRendererRegistrations(
  knowledgeShapes: readonly string[],
  representationNeeds?: RichAnswerRepresentationNeeds,
  sourceMedium?: string,
  knowledgeNatures: readonly string[] = [],
  knowledgeObjects: readonly string[] = [],
  knowledgeRelations: readonly string[] = [],
  knowledgeProcesses: readonly string[] = [],
  hasCurrentSourceAsset = false,
): RichAnswerRendererRegistration[] {
  const shapes = new Set(knowledgeShapes);
  const natures = new Set(knowledgeNatures);
  const semanticText = [
    ...knowledgeObjects,
    ...knowledgeRelations,
    ...knowledgeProcesses,
  ].join(" ").normalize("NFKC").toLocaleLowerCase();
  const asksForThreeDimensions =
    representationNeeds?.spatialDimension === "threeDimensional" ||
    representationNeeds?.coordinateFrame === "threeDimensional" ||
    (
      natures.has("spatialStructure") &&
      /(?:分子|构型|电子域|键角|三维|立体|空间几何|轨道|3d|molecule|vsepr|tetrahedral|trigonal|orbital)/iu.test(semanticText)
    );
  const asksForGeometry =
    representationNeeds?.coordinateFrame === "geometric" ||
    /(?:几何|三角|相似|全等|角度|圆|轨迹|直线|约束|geometry|triangle|angle|circle)/iu.test(semanticText);
  const asksForMap =
    sourceMedium === "map" ||
    representationNeeds?.coordinateFrame === "geographic" ||
    /(?:地图|河流|坡向|等高线|地形|区域|路线|经纬|空间分布|map|river|contour|geograph)/iu.test(semanticText);
  const asksForImageOverlay =
    hasCurrentSourceAsset &&
    (
      sourceMedium === "image" ||
      representationNeeds?.coordinateFrame === "imagePixel" ||
      natures.has("imageObservation") ||
      /(?:图像|构图|比例|覆盖|叠层|批注|测量|原图|image|overlay|composition)/iu.test(semanticText)
    );
  return RICH_ANSWER_RENDERER_REGISTRATIONS.filter((registration) => {
    if (registration.id === "weibei.image.overlay" && !hasCurrentSourceAsset) return false;
    if (registration.id === "weibei.scene-3d" && asksForThreeDimensions) return true;
    if (registration.id === "weibei.geometry.2d" && asksForGeometry) return true;
    if (registration.id === "weibei.spatial.map" && asksForMap) return true;
    if (registration.id === "weibei.image.overlay" && asksForImageOverlay) return true;
    if (registration.knowledgeShapes.some((shape) => shapes.has(shape))) return true;
    if (!representationNeeds) return false;
    return false;
  });
}


export function richAnswerRendererInteractionCoverage(
  registration: RichAnswerRendererRegistration,
  interactions: readonly string[],
) {
  const requested = interactions.filter((interaction) => interaction !== "none");
  const supported = requested.filter((interaction) => registration.interactionActions.includes(
    interaction as typeof RICH_ANSWER_INTERACTION_ACTIONS[number],
  ));
  const unsupported = requested.filter((interaction) => !supported.includes(interaction));
  return {
    requested,
    supported,
    unsupported,
    fullySupported: unsupported.length === 0,
  };
}


export function richAnswerRendererRepresentationCoverage(
  registration: RichAnswerRendererRegistration,
  needs?: RichAnswerRepresentationNeeds,
) {
  if (!needs) {
    return {
      requested: null,
      unsupported: [] as string[],
      fullySupported: true,
    };
  }
  const support = registration.representationSupport;
  const unsupported = [
    !support.spatialDimensions.includes(needs.spatialDimension)
      ? `spatialDimension:${needs.spatialDimension}`
      : undefined,
    !support.temporalBehaviors.includes(needs.temporalBehavior)
      ? `temporalBehavior:${needs.temporalBehavior}`
      : undefined,
    !support.dataOrigins.includes(needs.dataOrigin)
      ? `dataOrigin:${needs.dataOrigin}`
      : undefined,
    !support.coordinateFrames.includes(needs.coordinateFrame)
      ? `coordinateFrame:${needs.coordinateFrame}`
      : undefined,
    !support.computeNeeds.includes(needs.computeNeed)
      ? `computeNeed:${needs.computeNeed}`
      : undefined,
    !support.precisionNeeds.includes(needs.precisionNeed)
      ? `precisionNeed:${needs.precisionNeed}`
      : undefined,
    !support.assetDependencies.includes(needs.assetDependency)
      ? `assetDependency:${needs.assetDependency}`
      : undefined,
  ].filter((value): value is string => value !== undefined);
  return {
    requested: needs,
    unsupported,
    fullySupported: unsupported.length === 0,
  };
}


export function richAnswerRendererMinimalSpecSkeleton(
  registration: RichAnswerRendererRegistration,
  allowedAssetIDs: readonly string[],
): Record<string, unknown> {
  const replacementAssetID = allowedAssetIDs[0];
  const replaceAssetPlaceholder = (value: unknown): unknown => {
    if (value === "CURRENT_MATERIAL_ASSET_ID") {
      return replacementAssetID ?? value;
    }
    if (Array.isArray(value)) return value.map(replaceAssetPlaceholder);
    if (!isRecord(value)) return value;
    return Object.fromEntries(
      Object.entries(value).map(([field, child]) => [field, replaceAssetPlaceholder(child)]),
    );
  };
  const skeleton = replaceAssetPlaceholder(registration.minimalSpecSkeleton);
  if (!isRecord(skeleton)) return {};
  if (registration.id === "weibei.spatial.map" && replacementAssetID === undefined) {
    return {
      ...skeleton,
      coordinateHint: "当前没有可渲染底图；使用来源支持的示意坐标，不得伪造地理精度",
      mapAsset: { kind: "none" },
    };
  }
  return skeleton;
}


export function richAnswerRendererNestedFieldContracts(
  registration: RichAnswerRendererRegistration,
): Record<string, unknown> | undefined {
  if (registration.id === "weibei.echarts.chart") {
    return {
      series: {
        requiredFields: ["name", "values"],
        optionalFields: ["xValues", "chartKind", "unit"],
        scatterRule: "scatter 的每个 series 必须提交等长的 xValues/values，且不能提交 xLabels。",
        categoricalRule: "line/bar/area/mixed 不提交 xValues，series.values 必须与 xLabels 等长。",
      },
    };
  }
  if (registration.id === "weibei.geometry.2d") {
    return {
      controls: {
        presentation: ["slider", "segmented"],
        bindingVariants: [
          {
            kind: "pointCoordinate",
            requiredFields: ["kind", "pointID", "axis"],
            axis: ["x", "y"],
            optionalFields: ["multiplier", "offset", "minimum", "maximum"],
          },
          {
            kind: "pointOnConstraint",
            requiredFields: ["kind", "pointID"],
            optionalFields: ["multiplier", "offset"],
          },
          {
            kind: "circleRadius",
            requiredFields: ["kind", "shapeID"],
            optionalFields: ["multiplier", "offset", "minimum", "maximum"],
          },
        ],
        unboundControlRule:
          "bindings 可以为空，但该控件必须由某个 shape.visibleWhen 或 state readout 的 controlID 使用；bindings 中每一项都必须是对象，不能写字符串。",
      },
    };
  }
  return undefined;
}


export function richAnswerRendererCapabilityDeclarations(
  knowledgeShapes: readonly string[],
  interactions: readonly string[],
  representationNeeds?: RichAnswerRepresentationNeeds,
  sourceMedium?: string,
  knowledgeNatures: readonly string[] = [],
  knowledgeObjects: readonly string[] = [],
  knowledgeRelations: readonly string[] = [],
  knowledgeProcesses: readonly string[] = [],
  allowedAssetIDs: readonly string[] = [],
): Array<Record<string, unknown>> {
  return matchingRichAnswerRendererRegistrations(
    knowledgeShapes,
    representationNeeds,
    sourceMedium,
    knowledgeNatures,
    knowledgeObjects,
    knowledgeRelations,
    knowledgeProcesses,
    allowedAssetIDs.length > 0,
  ).map((registration) => {
    const interactionCoverage = richAnswerRendererInteractionCoverage(registration, interactions);
    const representationCoverage = richAnswerRendererRepresentationCoverage(
      registration,
      representationNeeds,
    );
    return {
      id: registration.id,
      label: registration.label,
      specVersion: registration.specVersion,
      knowledgeShapes: registration.knowledgeShapes,
      interactionActions: registration.interactionActions,
      interactionBindingKinds: registration.interactionBindingKinds,
      requestedInteractionCoverage: interactionCoverage,
      requestedRepresentationCoverage: representationCoverage,
      representationSupport: registration.representationSupport,
      standardKinds: registration.standardKinds,
      selectionGuidance:
        "这是本轮可用候选，不是固定答案。完全覆盖只表示它能诚实承载所需表达；仍需与成熟深组件、长尾组合和文本比较学习增益、独特联动、来源资产、精度与性能。",
      modelSpecContract: {
        allowedTopLevelSpecFields: registration.allowedSpecFields,
        allowedSeriesFields: registration.allowedSeriesFields,
        nestedFieldContracts: richAnswerRendererNestedFieldContracts(registration),
        forbiddenFields: registration.forbiddenSpecFields,
        guidance: registration.specGuidance,
        minimalSpecSkeleton: richAnswerRendererMinimalSpecSkeleton(
          registration,
          allowedAssetIDs,
        ),
        placeholderRule:
          "骨架只展示字段形状；CURRENT_MATERIAL_ASSET_ID 必须替换为本轮 sourceBindings 中真实可用的当前材料资产 ID，所有示例值都必须换成来源支持的语义与数据。",
        rule: "模型只提交高层 spec、interactionBindings、sourceBindings、fallback 与 qualityBudget；不得提交 raw option、脚本、HTML、SVG path、外链或任意渲染代码。",
      },
      qualityBudgetCeiling: registration.budgets,
    };
  });
}


export const COMPOSABLE_PRIMITIVE_CATALOG = [
  "ui 可组合原语：先确定 rootID 作为回答内联块的根，再组织 nodes + datasets + bindings；所有节点必须从 rootID 可达，用于目录里没有贴合深组件或注册专业渲染器的长尾问题，不生成 HTML/SVG。",
  `硬预算：每个 scene 最多 ${LIMITS.richAnswerUINodes} 个 nodes；所有 datasets 合计最多 ${LIMITS.richAnswerUIRows} 行；最多 ${LIMITS.richAnswerUIBindings} 个 bindings。函数或过程曲线优先共享横轴并使用少量有代表性的采样点，不要为两条曲线各复制高密度数据。`,
  "容器：vstack|hstack|zstack|grid|panel；画布：canvas；正文内优先透明容器，不把 panel 堆成卡片墙。",
  "图元：axis|line|path|point|area|shape|bar|dotMatrix|vector|region|image|label；统一使用归一化坐标与魏碑主题令牌。label 是画布标注，必须引用带 label 的 dataset.rows；同一 dataset 的图形受 binding 控制时，label 必须共享同一 bindingID，不能图形隐藏后留下孤立标签；画布外说明文字使用 text。",
  "函数曲线与真实数据关系本来适合 line/path/point/metric；但物体、空间、过程、机制、证据链不能只剩曲线和读数，必须加入 shape/vector/region/area/sequence/image/bar/dotMatrix 等能表达对象或状态的通用图元。",
  "非过程题不能只用 sequence、metric、text、label 或 grid 改排版；数量、空间、机制、证据、图像、比较和计算题，可绑定控件必须驱动 line/path/point/area/shape/bar/dotMatrix/vector 等非文字图元或空间编码产生可检查变化。",
  "图像材料：当路线、区域、比例或构图判断依赖原图位置时，必须把 weibei_context.course.catalog 中当前材料的 item.id 写入 image.assetID，并在对应 evidenceLedger.assetIDs 中声明，再作为 canvas 底图叠加 path/region/point/label；只有材料已给出完整数值几何时才可重绘，并明确标成示意关系。",
  "序列：sequence 用于通用步骤、证据链、周期节点、过程状态和时间节点；必须引用 dataset，至少两行，每行 label 是用户可见语义，bindingID 可选；不要自造 stepList/list/items 字段。",
  "控件：slider|toggle|scrubber|probe 通过 bindingID 连接共享数值状态；select/reset 用作选择或重置入口，不冒充数值 binding。最多两个主要控件，但允许多个联动读数与图元。每个 binding 必须同时连接一个可见可绑定控件和至少一个可达的 metric、sequence 或视觉图元，不能只放一个不会改变画面的滑杆。",
  "数据：dataset.rows 提供 x/y、可选 x2/y2、value/result/label；带 bindingID 的图元和 metric 会按 value 插值或选择当前行。",
  "语义：决定结论的条件、变量、方向或关系必须出现在可见的 label/text/axis/dataset 标签里，并随对应图元或状态可检查；不能只画无标注路径，也不能只在 UI 外正文里解释。",
  "证据：evidence 节点与数据行的 evidenceIDs 必须来自本轮 evidenceLedger；只做定位，不复制原文。",
].join("\n");


export const OPENUI_STATE_SHAPE_GUIDANCE = [
  "普通组件继续使用数字状态，例如 `$focus = 0`。",
  "组件的 name/stateName 参数是状态标识，不是界面标题：它必须与紧随其后的 $状态引用同名，例如 `ParameterReadout(\"timeIndex\", $timeIndex, \"当前 t/τ\")`，不能写成 `ParameterReadout(\"当前 t/τ\", $timeIndex, ...)`。",
  "MetricItem 的 value 是带引号的静态显示字符串；需要随数值状态变化时使用 ParameterReadout，或用 LinkedDataChart/其他签名明确支持的状态组件，不要把数字或 $状态直接塞进 MetricItem.value。",
  "空间图层允许字符串数组与字符串状态，例如 `$visible = [\"terrain\", \"route\"]`、`$selected = \"city-a\"`；名称参数必须分别写成 \"visible\" 与 \"selected\"。",
  "依赖传导允许数字数组状态，例如 `$inputs = [8, 18, 11]`；数组顺序必须与 FlowAssumption 引用顺序一致。",
  "数组和字符串状态只用于签名明确要求的组件；不要把它们当成任意数据通道。",
].join("\n");


export const RICH_ANSWER_FAMILY_CONTRACT = [
  "富回答 schemaVersion 必须为 2；每个 scene 必须且只能提交 program、renderPlan、ui 三条表达出口之一。program 是深组件程序；renderPlan 是注册专业渲染器计划；ui 是可组合原语树。",
  "富回答先过内容与专业性，再过视觉。提交前必须核对结论、公式、单位、数值、方向、因果边界和学科术语；不能由本轮材料或确定性内核验证的数字、关系和模拟结果不得让界面假装计算，也不得用漂亮图形掩盖知识错误。",
  "需要富回答时，先形成表达意图：用户真正卡住的判断、正文难呈现的知识对象/关系/过程、初始状态应出现的现象、一次操作前后应改变的状态和真实证据；再调用目录选择能力。不要先选图或组件再倒填内容。",
  "生成式 UI 是 Agent 回答流中的生成式视觉体验块，不是第二篇回答、独立小网页或完整网页外壳。它可以按问题需要组合多个视觉、控件、读数、局部解释和实验步骤。",
  "narrative 是本次富回答最终显示的完整正文：建议先给结论、就近标注真实来源，并用场景标记把视觉体验插在最有帮助的位置。优先用自然段连接解释与场景，避免页面级标题和标题—摘要—结论式第二篇文章；工具成功后不得再生成一份不同正文。",
  `提交富回答前必须先调用 ${RICH_ANSWER_CATALOG_TOOL}，让魏碑按本轮学习动作、知识形状、来源媒介、直接操作和表面重量返回相关深组件、注册专业渲染器与通用原语提示；组件目录可以再次调用，但不得绕过。`,
  "优先选择最贴合问题的表达出口：标准图表或统计形状匹配注册专业渲染器时先用 renderPlan；只有深组件能提供渲染器没有的领域实验或状态联动时才用 program；两者都不贴合的长尾组合才用 ui。",
  "program 中模型负责选择深组件、布局、数据、$state 反应变量和动作；renderPlan 中模型只给注册渲染器的高层 spec、绑定、来源和质量预算；ui 中模型负责组合容器、画布图元、数据集与 bindings；魏碑本地运行时统一负责渲染、联动与风格。",
  "ui 的画面必须能独立读出支撑结论的关键语义：用可见标签标明决定性条件、变量、方向、对应关系和当前状态，并把标签与实际图元、数据行或 binding 联动；禁止只画漂亮但无语义的线、点和区域。",
  "expressionPlan.knowledgeObjects 中声明的关键数值、比例、公式片段、采样尺寸和阈值，建议在 ui 的可见 label/text/axis/dataset 标签里原样或等价出现；不要只把它们留在计划或 narrative。",
  "sequence 单独只适合真实过程或状态演进；数量、空间、机制、证据、图像、比较和计算题必须让可绑定控件改变非文字图元或空间编码，不能只把正文拆成步骤、指标、卡片、表格或时间线。",
  "图像、地图和设计题若结论依赖原图中的空间位置，ui 必须使用 weibei_context.course.catalog 中当前材料的 item.id 作为 image.assetID，在对应 evidenceLedger.assetIDs 中声明，并作为画布底图叠加标注；不得脱离原图凭空重画路线、区域、比例或构图。材料已提供完整数值坐标时可画明确标注为示意的关系图。",
  "不要用固定的一图一控件或单场景模板限制表达。单个问题默认只提交一个最有帮助的 scene、一个主要操作和必要联动读数；相互关联的视觉、控件、读数和步骤优先组合进同一个 scene，只有两个体验确实独立时才拆分。每个元素都必须服务当前问题，不得用装饰、重复内容或穷举节点凑页面。",
  "保持多学科、多形态：根据知识对象选择函数图、数据图、执行轨、论证阅读、因果时间线、坐标实验、平衡实验或其他目录能力，不要把不同问题压成同一种外观。",
  "禁止在 program 中重复 Agent 正文的整套标题、摘要、结论或 evidenceLedger.excerpt，也不得从头重讲同一答案。RichAnswerRoot 与 LearningStage 只提供体验块内部的局部导向；证据组件只承担来源定位和回原文。",
  "NarrativeBlock 允许呈现局部状态解释、读数含义、诊断或互动反馈，但不得复述正文、扩写背景、另做摘要或再下一个完整结论。",
  "placement 与 preferredSurface 应按体验复杂度选择 inline、expanded 或 focus。复杂体验可以自然展开或进入专注模式；专注模式仍然是同一回答的延展，不得变成独立网页。",
  "program 只允许使用本轮目录工具返回的组件签名；每行只能声明一个有限状态或一个组件。状态默认是数字；只有签名明确要求时才可使用字符串、数字数组或字符串数组。参数必须严格匹配签名。不得自造组件、嵌套组件调用、SVG path、HTML、CSS、JavaScript、Query、Mutation、URL、iframe 或外部资源。",
  "program 的组件引用必须先声明后引用；引用数组使用 [step1, step2] 这种不加引号的组件 id，不能写成字符串数组。枚举参数只能使用目录指导列出的固定值，不能把公式或自然语言塞进枚举位。",
  "文字已经足够时不要调用富回答；禁止使用网站导航、页面级页头、功能菜单、营销区块或其他完整网页外壳，也不要用第二套标题—摘要—结论结构重新包装正文。",
  "renderPlan 必须使用本轮目录返回的 renderer 与 specVersion；标准图表只提交 chartKind、title、series(name, values, xValues?, chartKind?, unit?)、xLabels、xAxisLabel、yAxisLabel、caption、focusEnabled、binCount、samples 这些高层字段，不提交 raw option、脚本、HTML、SVG path 或外链。scatter 用等长 xValues/values 数值对；line/bar/area/mixed 使用 xLabels；mixed 图必须给每个 series 声明相同 unit；跨单位混合图需要另一个已注册渲染器。",
  "program 的函数图、联动数据图和双点坐标实验由 Canvas 内核计算，不要提交采样路径；program、renderPlan 与 ui 都无法诚实表达对象时，才使用正常文本，不要假造可视化。",
  "压力样例不是场景模板。先选择知识对象，再组合不同组件；禁止复用样例标题、数据和整套结构。",
  "所有状态名和组件 id 必须唯一；$状态、组件引用和 root 组件树必须完整可达，不能有重复、悬空、循环或孤立声明。",
  "EvidenceSnippet、ArgumentUnit、CausalEvent、SpatialPoint 中的 evidenceID 必须属于 scene.evidenceIDs，并与本轮 evidenceLedger 中的真实材料对应；普通文本里出现 id 不算证据绑定。",
  "工具会在拒绝 program 时批量返回场景、行列、预期组件签名和修正动作。按完整诊断修正；仍有遗漏时可再修一轮，不要用改写字符串绕过校验。",
  "工具拒绝富回答时会返回 weibei.rich_answer.repair_fault；必须保留其中的 code、jsonPath 与 humanFixHint，并按 replanningFeedback 在 program、renderPlan 与 ui 之间重新选择或修正后完整重发 RichAnswerUI。不能解释原因代替提交，也不能在坏树基础上局部 patch。remainingAttempts 为 0 时停止富回答并诚实使用普通文本；正文只回答用户问题和真实限制，不得提富回答校验、协议失败、repair_fault、payload 或内部工具错误。",
  OPENUI_STATE_SHAPE_GUIDANCE,
  COMPOSABLE_PRIMITIVE_CATALOG,
].join("\n");