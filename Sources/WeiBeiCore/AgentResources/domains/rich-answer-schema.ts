import { Type } from "@earendil-works/pi-ai";
import { LIMITS } from "./agent-context";
import {
  RICH_ANSWER_CHART_KINDS,
  RICH_ANSWER_KNOWLEDGE_NATURES,
  RICH_ANSWER_T2_PRIMITIVE_ROLES,
} from "./rich-answer-component-catalog";
import { RICH_ANSWER_FAMILY_CONTRACT } from "./rich-answer-renderer-registrations";


export const richAnswerIdentifierSchema = Type.String({ minLength: 1, maxLength: LIMITS.identifier });


export const richAnswerPointSchema = Type.Object(
  {
    x: Type.Number(),
    y: Type.Number(),
  },
  { additionalProperties: true },
);


export const richAnswerRegionSchema = Type.Object(
  {
    x: Type.Number({ minimum: 0, maximum: 1 }),
    y: Type.Number({ minimum: 0, maximum: 1 }),
    width: Type.Number({ exclusiveMinimum: 0, maximum: 1 }),
    height: Type.Number({ exclusiveMinimum: 0, maximum: 1 }),
  },
  { additionalProperties: true },
);


export const richAnswerAxisSchema = Type.Object(
  {
    label: Type.String({ minLength: 1, maxLength: 200 }),
    minimum: Type.Number(),
    maximum: Type.Number(),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
  },
  { additionalProperties: true },
);


export const richAnswerObjectSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      [
        "text",
        "quantity",
        "formula",
        "event",
        "region",
        "state",
        "claim",
        "image",
        "dataPoint",
        "step",
        "constraint",
        "option",
      ].map((value) => Type.Literal(value)),
    ),
    label: Type.String({ minLength: 1, maxLength: 300 }),
    text: Type.Optional(Type.String({ minLength: 1, maxLength: LIMITS.richAnswerText })),
    number: Type.Optional(Type.Number()),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
    evidenceIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
    ),
    assetID: Type.Optional(richAnswerIdentifierSchema),
    frameID: Type.Optional(richAnswerIdentifierSchema),
    coordinate: Type.Optional(richAnswerPointSchema),
    bounds: Type.Optional(richAnswerRegionSchema),
  },
  { additionalProperties: true },
);


export const richAnswerRelationSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      [
        "supports",
        "refutes",
        "causes",
        "precedes",
        "aligns",
        "contains",
        "transforms",
        "dependsOn",
        "contrasts",
        "constrains",
      ].map((value) => Type.Literal(value)),
    ),
    sourceID: richAnswerIdentifierSchema,
    targetID: richAnswerIdentifierSchema,
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    evidenceIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
    ),
  },
  { additionalProperties: true },
);


export const richAnswerParameterSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    label: Type.String({ minLength: 1, maxLength: 200 }),
    minimum: Type.Number(),
    maximum: Type.Number(),
    step: Type.Number({ exclusiveMinimum: 0 }),
    initialValue: Type.Number(),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
  },
  { additionalProperties: true },
);


export const richAnswerOperationSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      [
        "adjust",
        "toggle",
        "step",
        "zoom",
        "pan",
        "filter",
        "sort",
        "probe",
        "reset",
        "compare",
        "reveal",
        "select",
        "scrub",
        "playPause",
        "measure",
      ].map((value) => Type.Literal(value)),
    ),
    label: Type.String({ minLength: 1, maxLength: 300 }),
    targetIDs: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 32 }),
    parameter: Type.Optional(richAnswerParameterSchema),
    frameID: Type.Optional(richAnswerIdentifierSchema),
  },
  {
    additionalProperties: true,
    description:
      "operation 必须是当前 family 的原生 SwiftUI 渲染器已支持操作；不支持的 sort/filter/pan/measure 等不要提交。",
  },
);


export const richAnswerFrameSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      ["cartesian", "numberLine", "timeline", "space", "image", "text", "table", "graph", "process"]
        .map((value) => Type.Literal(value)),
    ),
    title: Type.String({ minLength: 1, maxLength: 300 }),
    objectIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerObjects }),
    ),
    xAxis: Type.Optional(richAnswerAxisSchema),
    yAxis: Type.Optional(richAnswerAxisSchema),
    assetID: Type.Optional(richAnswerIdentifierSchema),
    evidenceIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
    ),
  },
  { additionalProperties: true },
);


export const richAnswerUIRoleSchema = Type.Union(
  [
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
  ].map((value) => Type.Literal(value)),
);


export const richAnswerUIShapeSchema = Type.Union(
  ["rectangle", "roundedRectangle", "circle", "ellipse", "triangle", "diamond", "capsule"]
    .map((value) => Type.Literal(value)),
);


export const richAnswerUIFillSchema = Type.Union(
  ["outline", "soft", "solid"].map((value) => Type.Literal(value)),
);


export const richAnswerUIDataRowSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    x: Type.Number({ minimum: 0, maximum: 1 }),
    y: Type.Number({ minimum: 0, maximum: 1 }),
    x2: Type.Optional(Type.Number({ minimum: 0, maximum: 1 })),
    y2: Type.Optional(Type.Number({ minimum: 0, maximum: 1 })),
    value: Type.Optional(Type.Number()),
    result: Type.Optional(Type.Number()),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 200 })),
    evidenceIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
    ),
  },
  { additionalProperties: true },
);


export const richAnswerUIDatasetSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    rows: Type.Array(richAnswerUIDataRowSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerUIRows,
    }),
  },
  { additionalProperties: true },
);


export const richAnswerUIBindingSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    label: Type.String({ minLength: 1, maxLength: 200 }),
    minimum: Type.Number(),
    maximum: Type.Number(),
    step: Type.Number({ exclusiveMinimum: 0 }),
    initialValue: Type.Number(),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
  },
  { additionalProperties: true },
);


export const richAnswerUINodeStyleFields = {
  id: richAnswerIdentifierSchema,
  tone: Type.Optional(
    Type.Union(["ink", "muted", "accent", "warning", "positive", "gridline"]
      .map((value) => Type.Literal(value))),
  ),
  emphasis: Type.Optional(
    Type.Union(["quiet", "regular", "strong"].map((value) => Type.Literal(value))),
  ),
  spacing: Type.Optional(
    Type.Union(["tight", "regular", "loose"].map((value) => Type.Literal(value))),
  ),
  alignment: Type.Optional(
    Type.Union(["leading", "center", "trailing"].map((value) => Type.Literal(value))),
  ),
  size: Type.Optional(
    Type.Union(["compact", "regular", "large"].map((value) => Type.Literal(value))),
  ),
};


export const richAnswerUINodeEvidenceFields = {
  evidenceIDs: Type.Optional(
    Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
  ),
};


export const richAnswerUIContainerNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Union(["vstack", "hstack", "zstack", "panel"].map((value) => Type.Literal(value))),
    children: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 12 }),
  },
  { additionalProperties: false },
);


export const richAnswerUIGridNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("grid"),
    children: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 12 }),
    columns: Type.Integer({ minimum: 2, maximum: 3 }),
  },
  { additionalProperties: false },
);


export const richAnswerUICanvasNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("canvas"),
    children: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 12 }),
    xAxis: Type.Optional(richAnswerAxisSchema),
    yAxis: Type.Optional(richAnswerAxisSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUITextNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("text"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    text: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerText }),
  },
  { additionalProperties: false },
);


export const richAnswerUIMetricNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("metric"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUISequenceNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("sequence"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUIAxisNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("axis"),
  },
  { additionalProperties: false },
);


export const richAnswerUIStrokeMarkNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Union(["line", "path", "point", "vector"].map((value) => Type.Literal(value))),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUIFilledMarkNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Union(["area", "bar", "dotMatrix"].map((value) => Type.Literal(value))),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
    fill: Type.Optional(richAnswerUIFillSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUILabelMarkNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("label"),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUIStaticShapeNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("shape"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    region: richAnswerRegionSchema,
    shape: richAnswerUIShapeSchema,
    fill: richAnswerUIFillSchema,
  },
  { additionalProperties: false },
);


export const richAnswerUIRepeatedShapeNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("shape"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    datasetID: richAnswerIdentifierSchema,
    region: richAnswerRegionSchema,
    shape: richAnswerUIShapeSchema,
    fill: richAnswerUIFillSchema,
  },
  { additionalProperties: false },
);


export const richAnswerUIInteractiveShapeNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("shape"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    datasetID: richAnswerIdentifierSchema,
    bindingID: richAnswerIdentifierSchema,
    region: richAnswerRegionSchema,
    shape: richAnswerUIShapeSchema,
    fill: richAnswerUIFillSchema,
  },
  { additionalProperties: false },
);


export const richAnswerUIRegionNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("region"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    bindingID: Type.Optional(richAnswerIdentifierSchema),
    region: richAnswerRegionSchema,
    fill: Type.Optional(richAnswerUIFillSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUIImageNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("image"),
    assetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUIDividerNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("divider"),
  },
  { additionalProperties: false },
);


export const richAnswerUIBoundControlNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Union(["slider", "toggle", "scrubber", "probe"].map((value) => Type.Literal(value))),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    bindingID: richAnswerIdentifierSchema,
  },
  { additionalProperties: false },
);


export const richAnswerUISelectNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("select"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    datasetID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);


export const richAnswerUIResetNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("reset"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
  },
  { additionalProperties: false },
);


export const richAnswerUIEvidenceNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("evidence"),
    evidenceIDs: Type.Array(richAnswerIdentifierSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerEvidence,
    }),
  },
  { additionalProperties: false },
);


export const richAnswerUINodeSchema = Type.Union(
  [
    richAnswerUIContainerNodeSchema,
    richAnswerUIGridNodeSchema,
    richAnswerUICanvasNodeSchema,
    richAnswerUITextNodeSchema,
    richAnswerUIMetricNodeSchema,
    richAnswerUISequenceNodeSchema,
    richAnswerUIAxisNodeSchema,
    richAnswerUIStrokeMarkNodeSchema,
    richAnswerUIFilledMarkNodeSchema,
    richAnswerUILabelMarkNodeSchema,
    richAnswerUIStaticShapeNodeSchema,
    richAnswerUIRepeatedShapeNodeSchema,
    richAnswerUIInteractiveShapeNodeSchema,
    richAnswerUIRegionNodeSchema,
    richAnswerUIImageNodeSchema,
    richAnswerUIDividerNodeSchema,
    richAnswerUIBoundControlNodeSchema,
    richAnswerUISelectNodeSchema,
    richAnswerUIResetNodeSchema,
    richAnswerUIEvidenceNodeSchema,
  ],
  {
    description:
      "按 role 选择节点结构；不要给节点添加该角色未声明的字段。文字用 text，步骤/证据链/周期节点用 sequence 引用 dataset。",
  },
);


export const richAnswerUICompositionSchema = Type.Object(
  {
    rootID: richAnswerIdentifierSchema,
    nodes: Type.Array(richAnswerUINodeSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerUINodes,
    }),
    datasets: Type.Optional(
      Type.Array(richAnswerUIDatasetSchema, { maxItems: 12 }),
    ),
    bindings: Type.Optional(
      Type.Array(richAnswerUIBindingSchema, { maxItems: LIMITS.richAnswerUIBindings }),
    ),
  },
  { additionalProperties: false },
);


export const richAnswerUIProgramSchema = Type.Object(
  {
    version: Type.Literal("weibei.openui.v1"),
    source: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerProgramSource }),
    capabilities: Type.Array(Type.String({ minLength: 1, maxLength: 80 }), {
      minItems: 1,
      maxItems: LIMITS.richAnswerProgramCapabilities,
    }),
    maxHeight: Type.Integer({ minimum: 160, maximum: 720 }),
  },
  {
    additionalProperties: false,
    description:
      `${RICH_ANSWER_FAMILY_CONTRACT}\ngraphics 与 directManipulation 由魏碑根据实际组件自动推导，不要提交。`,
  },
);


export const richAnswerRenderPlanChartSeriesSchema = Type.Object(
  {
    name: Type.String({ minLength: 1, maxLength: 80 }),
    values: Type.Array(Type.Number(), {
      minItems: 1,
      maxItems: LIMITS.richAnswerRenderPlanDataPoints,
    }),
    xValues: Type.Optional(
      Type.Array(Type.Number(), {
        minItems: 1,
        maxItems: LIMITS.richAnswerRenderPlanDataPoints,
      }),
    ),
    chartKind: Type.Optional(
      Type.Union([Type.Literal("line"), Type.Literal("bar")]),
    ),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 24 })),
  },
  { additionalProperties: false },
);


export const richAnswerRenderPlanChartSpecSchema = Type.Object(
  {
    chartKind: Type.Union(RICH_ANSWER_CHART_KINDS.map((value) => Type.Literal(value))),
    title: Type.String({ minLength: 1, maxLength: 120 }),
    series: Type.Optional(
      Type.Array(richAnswerRenderPlanChartSeriesSchema, {
        maxItems: LIMITS.richAnswerRenderPlanSeries,
      }),
    ),
    xLabels: Type.Optional(
      Type.Array(Type.String({ minLength: 1, maxLength: 80 }), {
        maxItems: LIMITS.richAnswerRenderPlanDataPoints,
      }),
    ),
    xAxisLabel: Type.Optional(Type.String({ minLength: 1, maxLength: 80 })),
    yAxisLabel: Type.Optional(Type.String({ minLength: 1, maxLength: 80 })),
    caption: Type.Optional(Type.String({ minLength: 1, maxLength: 220 })),
    focusEnabled: Type.Optional(Type.Boolean()),
    binCount: Type.Optional(Type.Integer({ minimum: 3, maximum: 60 })),
    samples: Type.Optional(
      Type.Array(Type.Number(), {
        minItems: 1,
        maxItems: LIMITS.richAnswerRenderPlanDataPoints,
      }),
    ),
  },
  {
    additionalProperties: false,
    description:
      "注册专业渲染器的高层图表 spec；series 只允许 name、values、xValues、chartKind、unit。scatter 用等长 xValues/values 数值对且不提交 xLabels；line/bar/area/mixed 使用 xLabels，mixed 图每个 series 必须声明同一个 unit。不得给 raw option、script、HTML、SVG path 或渲染器私有配置。",
  },
);


export const richAnswerMathFunctionParameterSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    label: Type.String({ minLength: 1, maxLength: 80 }),
    value: Type.Number(),
    minimum: Type.Number(),
    maximum: Type.Number(),
    step: Type.Number({ exclusiveMinimum: 0 }),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 24 })),
  },
  { additionalProperties: false },
);


export const richAnswerMathOperationSchema = Type.Union(
  [
    "abs",
    "add",
    "cos",
    "divide",
    "exp",
    "log",
    "multiply",
    "negate",
    "power",
    "sin",
    "sqrt",
    "subtract",
    "tan",
  ].map((value) => Type.Literal(value)),
);


export const richAnswerMathFunctionExpressionNodeSchema = Type.Union([
  Type.Object(
    { id: richAnswerIdentifierSchema, kind: Type.Literal("constant"), value: Type.Number() },
    { additionalProperties: false },
  ),
  Type.Object(
    { id: richAnswerIdentifierSchema, kind: Type.Literal("variable") },
    { additionalProperties: false },
  ),
  Type.Object(
    {
      id: richAnswerIdentifierSchema,
      kind: Type.Literal("parameter"),
      parameterID: richAnswerIdentifierSchema,
    },
    { additionalProperties: false },
  ),
  Type.Object(
    {
      id: richAnswerIdentifierSchema,
      kind: Type.Literal("operation"),
      operation: richAnswerMathOperationSchema,
      inputIDs: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 2 }),
    },
    { additionalProperties: false },
  ),
]);


export const richAnswerMathFunctionSpecSchema = Type.Object(
  {
    title: Type.String({ minLength: 1, maxLength: 120 }),
    variable: Type.String({ minLength: 1, maxLength: 12 }),
    domain: Type.Object(
      {
        minimum: Type.Number(),
        maximum: Type.Number(),
      },
      { additionalProperties: false },
    ),
    parameters: Type.Optional(
      Type.Array(richAnswerMathFunctionParameterSchema, { maxItems: 4 }),
    ),
    expression: Type.Object(
      {
        rootNodeID: richAnswerIdentifierSchema,
        nodes: Type.Array(richAnswerMathFunctionExpressionNodeSchema, {
          minItems: 1,
          maxItems: 64,
        }),
      },
      { additionalProperties: false },
    ),
    xAxisLabel: Type.Optional(Type.String({ minLength: 1, maxLength: 80 })),
    yAxisLabel: Type.Optional(Type.String({ minLength: 1, maxLength: 80 })),
    caption: Type.Optional(Type.String({ minLength: 1, maxLength: 220 })),
    probeEnabled: Type.Optional(Type.Boolean()),
  },
  {
    additionalProperties: false,
    description:
      "受限函数 spec。expression 使用带 id 的表达式图；模型不提交采样点、裸公式代码、SVG path 或图表 option。",
  },
);


export const richAnswerRenderPlanSpecSchema = Type.Union([
  richAnswerRenderPlanChartSpecSchema,
  richAnswerMathFunctionSpecSchema,
  Type.Record(Type.String({ minLength: 1, maxLength: 120 }), Type.Unknown(), {
    minProperties: 1,
    maxProperties: 24,
    description:
      "其他注册专业渲染器的高层 JSON spec。具体允许字段、禁止字段、预算与最小骨架以 weibei_ui_catalog 返回的 matchingRenderers.modelSpecContract 为准。",
  }),
]);


export const richAnswerRenderPlanInteractionBindingSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      [
        "annotation",
        "brush",
        "picker",
        "playPause",
        "probe",
        "scrubber",
        "select",
        "slider",
        "sourceJump",
        "stateReveal",
        "step",
        "toggle",
        "zoomPan",
      ].map((value) => Type.Literal(value)),
    ),
    target: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerRenderPlanTarget }),
    stateKey: Type.Optional(Type.String({ minLength: 1, maxLength: 120 })),
    actionName: Type.Optional(Type.String({ minLength: 1, maxLength: 120 })),
    knowledgeStateEffect: Type.Optional(
      Type.String({ minLength: 1, maxLength: LIMITS.richAnswerRenderPlanText }),
    ),
  },
  { additionalProperties: false },
);


export const richAnswerRenderPlanSourceBindingSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    evidenceID: richAnswerIdentifierSchema,
    target: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerRenderPlanTarget }),
    role: Type.String({ minLength: 1, maxLength: 80 }),
    requiredForFallback: Type.Boolean(),
  },
  { additionalProperties: false },
);


export const richAnswerRenderPlanArtifactRefSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.String({ minLength: 1, maxLength: 80 }),
    mimeType: Type.String({ minLength: 1, maxLength: 120 }),
    role: Type.String({ minLength: 1, maxLength: 80 }),
    width: Type.Optional(Type.Integer({ minimum: 1, maximum: 20_000 })),
    height: Type.Optional(Type.Integer({ minimum: 1, maximum: 20_000 })),
    sizeBytes: Type.Optional(Type.Integer({ minimum: 0, maximum: 2_000_000 })),
    checksum: Type.Optional(Type.String({ minLength: 64, maxLength: 64 })),
    summary: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    metadata: Type.Optional(Type.Record(Type.String({ minLength: 1, maxLength: 80 }), Type.Unknown())),
  },
  { additionalProperties: false },
);


export const richAnswerRenderPlanFallbackSchema = Type.Object(
  {
    mode: Type.Union(
      ["narrativeOnly", "simplifiedRenderer", "staticSnapshot"].map((value) => Type.Literal(value)),
    ),
    reason: Type.String({ minLength: 1, maxLength: 600 }),
    text: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerNarrative }),
    renderer: Type.Optional(Type.String({ minLength: 1, maxLength: 160 })),
    artifactID: Type.Optional(richAnswerIdentifierSchema),
    preservesSourceBinding: Type.Boolean(),
  },
  { additionalProperties: false },
);


export const richAnswerRenderPlanQualityBudgetSchema = Type.Object(
  {
    maxNodes: Type.Optional(Type.Integer({ minimum: 1, maximum: LIMITS.richAnswerRenderPlanNodes })),
    maxDataPoints: Type.Optional(Type.Integer({ minimum: 1, maximum: LIMITS.richAnswerRenderPlanDataPoints })),
    maxArtifacts: Type.Optional(Type.Integer({ minimum: 0, maximum: LIMITS.richAnswerRenderPlanArtifacts })),
    maxBytes: Type.Optional(Type.Integer({ minimum: 1, maximum: LIMITS.richAnswerRenderPlanSpecBytes })),
    maxWidth: Type.Optional(Type.Integer({ minimum: 240, maximum: 960 })),
    maxHeight: Type.Optional(Type.Integer({ minimum: 160, maximum: 640 })),
    maxAnimationFPS: Type.Optional(Type.Integer({ minimum: 0, maximum: 30 })),
    maxInteractionLatencyMS: Type.Optional(Type.Integer({ minimum: 1, maximum: 120 })),
    allowAnimation: Type.Boolean(),
    allowWebGL: Type.Boolean(),
    allowNetwork: Type.Boolean(),
  },
  { additionalProperties: false },
);


export const richAnswerRenderPlanSchema = Type.Object(
  {
    renderer: Type.String({ minLength: 1, maxLength: 160 }),
    specVersion: Type.String({ minLength: 1, maxLength: 160 }),
    spec: richAnswerRenderPlanSpecSchema,
    interactionBindings: Type.Array(richAnswerRenderPlanInteractionBindingSchema, {
      maxItems: LIMITS.richAnswerRenderPlanBindings,
    }),
    sourceBindings: Type.Array(richAnswerRenderPlanSourceBindingSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerRenderPlanSourceBindings,
    }),
    artifactRefs: Type.Array(richAnswerRenderPlanArtifactRefSchema, {
      maxItems: LIMITS.richAnswerRenderPlanArtifacts,
    }),
    fallback: richAnswerRenderPlanFallbackSchema,
    qualityBudget: richAnswerRenderPlanQualityBudgetSchema,
  },
  {
    additionalProperties: false,
    description:
      "注册专业渲染器计划。只能引用目录返回的 renderer/specVersion，并提交 spec、interactionBindings、sourceBindings、artifactRefs、fallback、qualityBudget；禁止 raw option/script/html/svgPath，安全和预算由工具返回 repair_fault。",
  },
);


export const richAnswerSceneCommonFields = {
  id: richAnswerIdentifierSchema,
  title: Type.String({ minLength: 1, maxLength: 300 }),
  family: Type.Union(
    [
      "textAndAlignment",
      "quantityAndCoordinates",
      "processAndState",
      "relationAndEvidence",
      "timeAndSpace",
      "imageAndOverlay",
      "comparisonAndEvaluation",
      "calculationAndConstraints",
    ].map((value) => Type.Literal(value)),
  ),
  evidenceIDs: Type.Array(richAnswerIdentifierSchema, {
    minItems: 1,
    maxItems: LIMITS.richAnswerEvidence,
  }),
  placement: Type.Optional(
    Type.Union([Type.Literal("inline"), Type.Literal("expanded"), Type.Literal("focus")]),
  ),
};


export const richAnswerT1SceneSchema = Type.Object(
  {
    ...richAnswerSceneCommonFields,
    program: richAnswerUIProgramSchema,
  },
  { additionalProperties: false },
);


export const richAnswerT2SceneSchema = Type.Object(
  {
    ...richAnswerSceneCommonFields,
    ui: richAnswerUICompositionSchema,
  },
  { additionalProperties: false },
);


export const richAnswerRenderPlanSceneSchema = Type.Object(
  {
    ...richAnswerSceneCommonFields,
    renderPlan: richAnswerRenderPlanSchema,
  },
  { additionalProperties: false },
);


export const richAnswerSceneSchema = Type.Union(
  [richAnswerT1SceneSchema, richAnswerRenderPlanSceneSchema, richAnswerT2SceneSchema],
  {
    description:
      `${RICH_ANSWER_FAMILY_CONTRACT}\n场景从输入层三选一：深组件只提交 program，注册专业渲染器只提交 renderPlan，通用原语只提交 ui，不再提交 objects、relations、operations 或 frames。`,
  },
);


export const richAnswerEnvelopeSchema = Type.Object(
  {
    schemaVersion: Type.Literal(2),
    contextRevision: richAnswerIdentifierSchema,
    narrative: Type.String({
      minLength: 1,
      maxLength: LIMITS.richAnswerNarrative,
      description: "本次最终显示的完整、带真实来源标签的回答正文；可用独占一行的 <!-- weibei-scene:场景ID --> 把场景插入正文中间",
    }),
    expressionPlan: Type.Object(
      {
        action: Type.Union(
          ["explain", "compare", "derive", "trace", "calculate", "observe", "manipulate", "evaluate", "practice"]
            .map((value) => Type.Literal(value)),
        ),
        summary: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerSummary }),
        knowledgeNatures: Type.Array(
          Type.Union(RICH_ANSWER_KNOWLEDGE_NATURES.map((value) => Type.Literal(value))),
          {
            minItems: 1,
            maxItems: 4,
            description: "声明本轮要表达的是函数曲线、物体机制、空间结构、过程状态、论证证据、图像观察、对照评价或计算约束；不能留空。",
          },
        ),
        knowledgeObjects: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 1,
          maxItems: 8,
          description: "显式列出 UI 要表达的关键知识对象，例如 摆长L、摆球、摩擦力、论点、样本窗口。",
        }),
        knowledgeRelations: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 0,
          maxItems: 8,
          description: "显式列出要表达的关系，例如 T 随 L 增长、静摩擦阻碍潜在相对运动、证据支持主张。",
        }),
        knowledgeProcesses: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 0,
          maxItems: 8,
          description: "显式列出要表达的过程或状态变化；若不是过程题可为空数组。",
        }),
        visualPrimitives: Type.Array(
          Type.Union(RICH_ANSWER_T2_PRIMITIVE_ROLES.map((value) => Type.Literal(value))),
          {
            minItems: 1,
            maxItems: 12,
            description: "列出本次实际计划使用的 ui role；使用 program 或 renderPlan 时也要列出其等价视觉角色，不能写不存在的网页/SVG/颜色。",
          },
        ),
        visualRationale: Type.Array(Type.String({ minLength: 1, maxLength: 200 }), {
          minItems: 1,
          maxItems: 8,
          description: "说明为什么这些视觉原语能表达上述知识对象、关系或过程，不能只写排版理由。",
        }),
        families: Type.Array(
          Type.Union(
            [
              "textAndAlignment",
              "quantityAndCoordinates",
              "processAndState",
              "relationAndEvidence",
              "timeAndSpace",
              "imageAndOverlay",
              "comparisonAndEvaluation",
              "calculationAndConstraints",
            ].map((value) => Type.Literal(value)),
          ),
          { minItems: 1, maxItems: 8 },
        ),
        preferredSurface: Type.Union([
          Type.Literal("inline"),
          Type.Literal("expanded"),
          Type.Literal("focus"),
        ]),
      },
      { additionalProperties: false },
    ),
    scenes: Type.Array(richAnswerSceneSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerScenes,
    }),
    evidenceLedger: Type.Array(
      Type.Object(
        {
          id: richAnswerIdentifierSchema,
          sourceLabel: Type.String({ minLength: 1, maxLength: 400 }),
          excerpt: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerExcerpt }),
          isTruncated: Type.Optional(Type.Boolean()),
          tags: Type.Optional(
            Type.Array(Type.String({ minLength: 1, maxLength: 120 }), { maxItems: 16 }),
          ),
          assetIDs: Type.Optional(
            Type.Array(richAnswerIdentifierSchema, { maxItems: 16 }),
          ),
        },
        { additionalProperties: false },
      ),
      { minItems: 1, maxItems: LIMITS.richAnswerEvidence },
    ),
    fallback: Type.Object(
      {
        text: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerNarrative }),
        reason: Type.String({ minLength: 1, maxLength: 600 }),
      },
      { additionalProperties: false },
    ),
  },
  { additionalProperties: false },
);