import { courseEvidenceLabel } from "./course-navigation";
import {
  ContextSnapshotV2,
  LIMITS,
  isRecord,
} from "./agent-context";
import {
  RICH_ANSWER_CHART_KINDS,
  RichAnswerRendererRegistration,
  RichAnswerStandardChartType,
} from "./rich-answer-catalog";


export function normalizedEvidenceText(value: string): string {
  return value.normalize("NFKC").replace(/\s+/gu, " ").trim();
}


export function canonicalRichAnswerEvidenceLabel(
  rawLabel: string,
  availableLabels: Iterable<string>,
): string | undefined {
  const raw = normalizedEvidenceText(rawLabel);
  const matches = Array.from(availableLabels).filter((label) => {
    const comparableLabel = normalizedEvidenceText(label);
    if (raw === comparableLabel) return true;
    const inner = comparableLabel.startsWith("[") && comparableLabel.endsWith("]")
      ? comparableLabel.slice(1, -1)
      : comparableLabel;
    const separator = inner.search(/[:：]/u);
    const title = separator >= 0 ? inner.slice(separator + 1) : inner;
    return raw === inner || raw === title || raw === `[${title}]`;
  });
  return matches.length === 1 ? matches[0] : undefined;
}


export interface RichAnswerEvidenceSource {
  text: string;
  isTruncated: boolean;
}


export function richAnswerEvidenceText(
  snapshot: ContextSnapshotV2,
  searchedCourseItemIDs: ReadonlySet<string>,
): Map<string, RichAnswerEvidenceSource> {
  const evidence = new Map<string, RichAnswerEvidenceSource>();
  if (snapshot.note.text.trim()) {
    evidence.set(`[笔记：${snapshot.note.title}]`, {
      text: snapshot.note.text,
      isTruncated: snapshot.note.isTruncated,
    });
  }
  if (snapshot.material?.text.trim()) {
    evidence.set(`[材料：${snapshot.material.title}]`, {
      text: snapshot.material.text,
      isTruncated: snapshot.material.isTruncated,
    });
  }
  if (snapshot.selection?.text.trim()) {
    evidence.set(`[选区：${snapshot.selection.title}]`, {
      text: snapshot.selection.text,
      isTruncated: snapshot.selection.isTruncated,
    });
  }
  snapshot.course.items
    .filter((item) => searchedCourseItemIDs.has(item.id) && item.searchText.trim())
    .forEach((item) => evidence.set(courseEvidenceLabel(snapshot.course, item), {
      text: item.searchText,
      isTruncated: item.isTruncated,
    }));
  return evidence;
}


export interface RichAnswerPointParam {
  x: number;
  y: number;
}


export interface RichAnswerObjectParam {
  id: string;
  kind: string;
  text?: string;
  number?: number;
  assetID?: string;
  frameID?: string;
  coordinate?: RichAnswerPointParam;
  bounds?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}


export interface RichAnswerRelationParam {
  id: string;
  sourceID: string;
  targetID: string;
}


export interface RichAnswerOperationParam {
  id: string;
  kind: string;
  targetIDs: string[];
  parameter?: {
    id: string;
    label: string;
    minimum: number;
    maximum: number;
    step: number;
    initialValue: number;
    unit?: string;
  };
  frameID?: string;
}


export interface RichAnswerFrameParam {
  id: string;
  kind: string;
  objectIDs?: string[];
  assetID?: string;
}


export interface RichAnswerUIDataRowParam {
  id: string;
  x: number;
  y: number;
  x2?: number;
  y2?: number;
  value?: number;
  result?: number;
  label?: string;
  evidenceIDs?: string[];
}


export interface RichAnswerUIDatasetParam {
  id: string;
  rows: RichAnswerUIDataRowParam[];
}


export interface RichAnswerUIBindingParam {
  id: string;
  label: string;
  minimum: number;
  maximum: number;
  step: number;
  initialValue: number;
  unit?: string;
}


export interface RichAnswerUINodeParam {
  id: string;
  role: string;
  children?: string[];
  label?: string;
  text?: string;
  unit?: string;
  datasetID?: string;
  bindingID?: string;
  assetID?: string;
  evidenceIDs?: string[];
  xAxis?: { label?: string; minimum: number; maximum: number; unit?: string };
  yAxis?: { label?: string; minimum: number; maximum: number; unit?: string };
  region?: { x: number; y: number; width: number; height: number };
  shape?: "rectangle" | "roundedRectangle" | "circle" | "ellipse" | "triangle" | "diamond" | "capsule";
  fill?: "outline" | "soft" | "solid";
  columns?: number;
}


export interface RichAnswerUICompositionParam {
  rootID: string;
  nodes: RichAnswerUINodeParam[];
  datasets?: RichAnswerUIDatasetParam[];
  bindings?: RichAnswerUIBindingParam[];
}


export interface RichAnswerUIProgramParam {
  version: "weibei.openui.v1";
  source: string;
  capabilities: string[];
  directManipulation?: boolean;
  maxHeight: number;
  graphics?: "dom" | "canvas";
}


export interface RichAnswerRenderPlanChartSeriesParam {
  name: string;
  values: number[];
  chartKind?: "line" | "bar";
  unit?: string;
}


export interface RichAnswerRenderPlanChartSpecParam {
  chartKind: RichAnswerStandardChartType;
  title: string;
  series?: RichAnswerRenderPlanChartSeriesParam[];
  xLabels?: string[];
  xAxisLabel?: string;
  yAxisLabel?: string;
  caption?: string;
  focusEnabled?: boolean;
  binCount?: number;
  samples?: number[];
}


export interface RichAnswerMathFunctionParameterParam {
  id: string;
  label: string;
  value: number;
  minimum: number;
  maximum: number;
  step: number;
  unit?: string;
}


export interface RichAnswerMathFunctionExpressionNodeParam {
  id: string;
  kind: "constant" | "variable" | "parameter" | "operation";
  value?: number;
  parameterID?: string;
  operation?: string;
  inputIDs?: string[];
}


export interface RichAnswerMathFunctionSpecParam {
  title: string;
  variable: string;
  domain: { minimum: number; maximum: number };
  parameters?: RichAnswerMathFunctionParameterParam[];
  expression: {
    rootNodeID: string;
    nodes: RichAnswerMathFunctionExpressionNodeParam[];
  };
  xAxisLabel?: string;
  yAxisLabel?: string;
  caption?: string;
  probeEnabled?: boolean;
}


export type RichAnswerRenderPlanSpecParam =
  | RichAnswerRenderPlanChartSpecParam
  | RichAnswerMathFunctionSpecParam;


export interface RichAnswerRenderPlanInteractionBindingParam {
  id: string;
  kind: string;
  target: string;
  stateKey?: string;
  actionName?: string;
  knowledgeStateEffect?: string;
}


export interface RichAnswerRenderPlanSourceBindingParam {
  id: string;
  evidenceID: string;
  target: string;
  role: string;
  requiredForFallback: boolean;
  [key: string]: unknown;
}


export interface RichAnswerRenderPlanArtifactRefParam {
  id: string;
  kind: "generated" | "source" | "snapshot";
  label: string;
  sourceBindingID?: string;
}


export interface RichAnswerRenderPlanFallbackParam {
  mode: "narrativeOnly" | "simplifiedRenderer" | "staticSnapshot";
  reason: string;
  text: string;
  renderer?: string;
  artifactID?: string;
  preservesSourceBinding: boolean;
  [key: string]: unknown;
}


export interface RichAnswerRenderPlanQualityBudgetParam {
  maxNodes?: number;
  maxDataPoints?: number;
  maxArtifacts?: number;
  maxBytes?: number;
  maxWidth?: number;
  maxHeight?: number;
  maxAnimationFPS?: number;
  maxInteractionLatencyMS?: number;
  allowAnimation: boolean;
  allowWebGL: boolean;
  allowNetwork: boolean;
  [key: string]: unknown;
}


export interface RichAnswerRenderPlanParam {
  renderer: string;
  specVersion: string;
  spec: RichAnswerRenderPlanSpecParam;
  interactionBindings: RichAnswerRenderPlanInteractionBindingParam[];
  sourceBindings: RichAnswerRenderPlanSourceBindingParam[];
  artifactRefs: RichAnswerRenderPlanArtifactRefParam[];
  fallback: RichAnswerRenderPlanFallbackParam;
  qualityBudget: RichAnswerRenderPlanQualityBudgetParam;
  [key: string]: unknown;
}


export interface RichAnswerSceneParam {
  id: string;
  title?: string;
  family: string;
  objects?: RichAnswerObjectParam[];
  relations?: RichAnswerRelationParam[];
  operations?: RichAnswerOperationParam[];
  frames?: RichAnswerFrameParam[];
  evidenceIDs: string[];
  program?: RichAnswerUIProgramParam;
  renderPlan?: RichAnswerRenderPlanParam;
  ui?: RichAnswerUICompositionParam;
}


export interface RichAnswerExpressionPlanParam {
  action: string;
  summary: string;
  knowledgeNatures?: string[];
  knowledgeObjects?: string[];
  knowledgeRelations?: string[];
  knowledgeProcesses?: string[];
  visualPrimitives?: string[];
  visualRationale?: string[];
  families: string[];
  preferredSurface: string;
  directManipulation?: boolean;
}


export const RICH_ANSWER_SUPPORTED_OPERATIONS: Record<string, ReadonlySet<string>> = {
  textAndAlignment: new Set(["select", "reveal", "reset"]),
  quantityAndCoordinates: new Set(["adjust", "probe", "select", "reset"]),
  processAndState: new Set(["select", "step", "playPause", "reset"]),
  relationAndEvidence: new Set(["select", "reveal", "reset"]),
  timeAndSpace: new Set(["scrub", "toggle", "reset"]),
  imageAndOverlay: new Set(["select", "toggle", "zoom"]),
  comparisonAndEvaluation: new Set(["compare", "select", "reset"]),
  calculationAndConstraints: new Set(["adjust", "reset"]),
};


export function hasMeaningfulText(value: string | undefined): boolean {
  return value !== undefined && value.trim().length > 0;
}


export function isNormalizedPoint(point: RichAnswerPointParam | undefined): boolean {
  return point !== undefined &&
    Number.isFinite(point.x) &&
    Number.isFinite(point.y) &&
    point.x >= 0 &&
    point.x <= 1 &&
    point.y >= 0 &&
    point.y <= 1;
}


export function operationTargetsAtLeast(
  scene: RichAnswerSceneParam,
  kind: string,
  minimumTargetCount: number,
  allowedTargetIDs: ReadonlySet<string>,
): boolean {
  return (scene.operations ?? []).some((operation) =>
    operation.kind === kind &&
      new Set(operation.targetIDs.filter((targetID) => allowedTargetIDs.has(targetID))).size >=
        minimumTargetCount,
  );
}


export function numericCoordinateSamples(
  scene: RichAnswerSceneParam,
  operation: RichAnswerOperationParam,
  frameIDs: ReadonlySet<string>,
): RichAnswerObjectParam[] {
  const targetIDs = new Set(operation.targetIDs);
  return (scene.objects ?? []).filter((object) =>
    targetIDs.has(object.id) &&
      object.number !== undefined &&
      isNormalizedPoint(object.coordinate) &&
      object.frameID !== undefined &&
      frameIDs.has(object.frameID),
  );
}


export const RICH_ANSWER_UI_CONTAINER_ROLES = new Set(["vstack", "hstack", "zstack", "grid", "panel"]);


export const RICH_ANSWER_UI_CANVAS_ROLES = new Set([
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
]);


export const RICH_ANSWER_UI_DATASET_ROLES = new Set([
  "metric",
  "sequence",
  "line",
  "path",
  "point",
  "area",
  "vector",
  "bar",
  "dotMatrix",
  "label",
]);


export const RICH_ANSWER_UI_BINDING_ROLES = new Set(["slider", "toggle", "scrubber", "probe"]);


export const RICH_ANSWER_UI_BINDING_OUTPUT_ROLES = new Set([
  "metric",
  "sequence",
  "line",
  "path",
  "point",
  "area",
  "shape",
  "bar",
  "dotMatrix",
  "vector",
  "region",
  "image",
]);


export const RICH_ANSWER_UI_PRIMARY_CONTROL_ROLES = new Set([
  "slider",
  "toggle",
  "scrubber",
  "select",
  "probe",
]);


export const RICH_ANSWER_RENDER_PLAN_FIELDS = new Set([
  "renderer",
  "specVersion",
  "spec",
  "interactionBindings",
  "sourceBindings",
  "artifactRefs",
  "fallback",
  "qualityBudget",
]);


export const RICH_ANSWER_RENDER_INTERACTION_FIELDS = new Set([
  "id",
  "kind",
  "target",
  "stateKey",
  "actionName",
  "knowledgeStateEffect",
]);


export const RICH_ANSWER_RENDER_SOURCE_BINDING_FIELDS = new Set([
  "id",
  "evidenceID",
  "target",
  "role",
  "requiredForFallback",
]);


export const RICH_ANSWER_RENDER_ARTIFACT_FIELDS = new Set([
  "id",
  "kind",
  "mimeType",
  "role",
  "width",
  "height",
  "sizeBytes",
  "checksum",
  "summary",
  "metadata",
]);


export const RICH_ANSWER_RENDER_ARTIFACT_KINDS = new Set([
  "generated",
  "source",
  "snapshot",
  "table",
  "numeric_series",
  "json_spec",
  "static_png",
  "static_svg",
  "static_html",
  "image_overlay_spec",
  "interactive_adapter_spec",
]);


export const RICH_ANSWER_RENDER_FALLBACK_FIELDS = new Set([
  "mode",
  "reason",
  "text",
  "renderer",
  "artifactID",
  "preservesSourceBinding",
]);


export const RICH_ANSWER_RENDER_QUALITY_BUDGET_FIELDS = new Set([
  "maxNodes",
  "maxDataPoints",
  "maxArtifacts",
  "maxBytes",
  "maxWidth",
  "maxHeight",
  "maxAnimationFPS",
  "maxInteractionLatencyMS",
  "allowAnimation",
  "allowWebGL",
  "allowNetwork",
]);


export const RICH_ANSWER_RENDER_INTERACTION_KINDS = new Set([
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
]);


export const RICH_ANSWER_RENDER_SOURCE_BINDING_ROLES = new Set([
  "dataset",
  "data",
  "series",
  "function",
  "point",
  "bin",
  "axis",
  "caption",
  "annotation",
  "fallback",
  "artifact",
]);


export const RICH_ANSWER_RENDER_FALLBACK_MODES = new Set([
  "narrativeOnly",
  "simplifiedRenderer",
  "staticSnapshot",
]);


export const RICH_ANSWER_CHART_KIND_SET = new Set<string>(RICH_ANSWER_CHART_KINDS);


export const RICH_ANSWER_MATH_UNARY_OPERATIONS = new Set([
  "abs",
  "cos",
  "exp",
  "log",
  "negate",
  "sin",
  "sqrt",
  "tan",
]);


export const RICH_ANSWER_MATH_BINARY_OPERATIONS = new Set([
  "add",
  "divide",
  "multiply",
  "power",
  "subtract",
]);


export const RICH_ANSWER_RENDER_UNSAFE_TEXT_PATTERN =
  /(?:<\s*script|<\s*iframe|javascript\s*:|data\s*:\s*text\/html|onerror\s*=|onload\s*=|eval\s*\(|Function\s*\(|https?:\/\/)/iu;


export function normalizedRendererFieldName(value: string): string {
  return value.replace(/[\s_-]/gu, "").toLocaleLowerCase();
}


export function rendererFieldList(value: ReadonlySet<string> | readonly string[]): string {
  return Array.from(value).join("、");
}


export function richAnswerRenderPlanByteLength(value: unknown): number {
  return Buffer.byteLength(JSON.stringify(value), "utf8");
}


export function richAnswerRenderPlanUnknownFields(
  value: unknown,
  allowedFields: ReadonlySet<string> | readonly string[],
): string[] {
  if (!isRecord(value)) return [];
  const allowed = allowedFields instanceof Set ? allowedFields : new Set(allowedFields);
  return Object.keys(value).filter((field) => !allowed.has(field));
}


export function richAnswerRenderPlanContainsUnsafeText(value: unknown): boolean {
  if (typeof value === "string") {
    return RICH_ANSWER_RENDER_UNSAFE_TEXT_PATTERN.test(value);
  }
  if (Array.isArray(value)) {
    return value.some((item) => richAnswerRenderPlanContainsUnsafeText(item));
  }
  if (isRecord(value)) {
    return Object.values(value).some((item) => richAnswerRenderPlanContainsUnsafeText(item));
  }
  return false;
}


export function richAnswerRenderPlanForbiddenFieldPaths(
  value: unknown,
  registration: RichAnswerRendererRegistration,
  path = "$.renderPlan.spec",
): string[] {
  if (!isRecord(value) && !Array.isArray(value)) return [];
  const forbidden = new Set(registration.forbiddenSpecFields.map(normalizedRendererFieldName));
  const paths: string[] = [];
  const visit = (current: unknown, currentPath: string): void => {
    if (paths.length >= 12) return;
    if (Array.isArray(current)) {
      current.forEach((item, index) => visit(item, `${currentPath}[${index}]`));
      return;
    }
    if (!isRecord(current)) return;
    for (const [field, child] of Object.entries(current)) {
      const childPath = `${currentPath}.${field}`;
      if (forbidden.has(normalizedRendererFieldName(field))) {
        paths.push(childPath);
      }
      visit(child, childPath);
      if (paths.length >= 12) return;
    }
  };
  visit(value, path);
  return paths;
}


export function richAnswerRenderPlanNumberArray(value: unknown): number[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.every((item) => typeof item === "number" && Number.isFinite(item))
    ? value
    : undefined;
}


export function richAnswerRenderPlanStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.every((item) => typeof item === "string" && item.trim().length > 0)
    ? value
    : undefined;
}


export function richAnswerRenderPlanValidIdentifier(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= LIMITS.identifier;
}


export function richAnswerRenderPlanValidActionName(value: string): boolean {
  return /^[A-Za-z][A-Za-z0-9_.-]{0,119}$/u.test(value) &&
    !RICH_ANSWER_RENDER_UNSAFE_TEXT_PATTERN.test(value);
}


export function richAnswerRenderPlanSpecEvidenceIDs(spec: unknown): string[] {
  void spec;
  return [];
}


export function richAnswerRenderPlanIntegerInRange(
  value: unknown,
  minimum: number,
  maximum: number,
): value is number {
  return Number.isInteger(value) && value >= minimum && value <= maximum;
}