import { z } from "zod/v4";
import { createRendererIssue, type RenderPlan } from "../renderer-registry";

export const GEOMETRY_2D_RENDERER = "weibei.geometry.2d";
export const GEOMETRY_2D_SPEC_VERSION = "weibei.geometry-2d.v1";

const maxPoints = 32;
const maxShapes = 64;
const maxControls = 8;
const maxBindings = 32;
const maxLocusPoints = 240;
const maxDataPoints = 1_200;
const finiteNumber = z.number().refine(Number.isFinite, "必须是有限数字");
const controlValueSchema = z.union([finiteNumber, z.string().min(1).max(80)]);
const positiveNumber = finiteNumber.refine((value) => value > 0, "必须大于 0");
const nonNegativeNumber = finiteNumber.refine((value) => value >= 0, "必须大于等于 0");
const identifier = z.string().min(1).max(80).regex(/^[a-zA-Z0-9._:-]+$/, "id 只能包含字母、数字、点、下划线、冒号或短横线");
const color = z.string().min(4).max(48).regex(/^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$|^rgba?\(/, "颜色必须是 hex 或 rgb(a)");

const visibleWhenSchema = z.object({
  controlID: identifier,
  equals: controlValueSchema,
}).strict();

const coordinateSchema = z.object({
  x: finiteNumber,
  y: finiteNumber,
}).strict();

const boundsSchema = z.object({
  xMin: finiteNumber,
  xMax: finiteNumber,
  yMin: finiteNumber,
  yMax: finiteNumber,
}).strict();

const styleSchema = z.object({
  stroke: color.default("rgba(85, 64, 43, 0.92)"),
  strokeWidth: z.number().min(0.5).max(8).default(2),
  fill: z.string().min(0).max(48).default("transparent"),
  opacity: z.number().min(0).max(1).default(0.92),
  dash: z.boolean().default(false),
}).strict();

const pointStyleSchema = z.object({
  stroke: color.default("rgba(80, 52, 35, 0.96)"),
  fill: color.default("rgba(156, 73, 49, 0.95)"),
  radius: z.number().min(2).max(16).default(5),
}).strict();

const freeConstraintSchema = z.object({
  kind: z.literal("free"),
}).strict();

const axisConstraintSchema = z.object({
  kind: z.literal("axis"),
  axis: z.enum(["x", "y"]),
  value: finiteNumber,
  showTrack: z.boolean().default(true),
}).strict();

const lineSegmentConstraintSchema = z.object({
  kind: z.literal("lineSegment"),
  start: coordinateSchema,
  end: coordinateSchema,
  showTrack: z.boolean().default(true),
}).strict();

const circleConstraintSchema = z.object({
  kind: z.literal("circle"),
  center: coordinateSchema,
  radius: positiveNumber,
  showTrack: z.boolean().default(true),
}).strict();

const roundedBoxTrackConstraintSchema = z.object({
  kind: z.literal("roundedBoxTrack"),
  box: boundsSchema,
  cornerRadius: nonNegativeNumber,
  showTrack: z.boolean().default(true),
}).strict();

const constraintSchema = z.discriminatedUnion("kind", [
  freeConstraintSchema,
  axisConstraintSchema,
  lineSegmentConstraintSchema,
  circleConstraintSchema,
  roundedBoxTrackConstraintSchema,
]);

const pointSchema = z.object({
  id: identifier,
  label: z.string().min(1).max(80).optional(),
  x: finiteNumber,
  y: finiteNumber,
  draggable: z.boolean().default(false),
  constraint: constraintSchema.optional(),
  style: pointStyleSchema.optional(),
}).strict();

const segmentShapeSchema = z.object({
  id: identifier,
  kind: z.literal("segment"),
  from: identifier,
  to: identifier,
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  visibleWhen: visibleWhenSchema.optional(),
}).strict();

const circleShapeSchema = z.object({
  id: identifier,
  kind: z.literal("circle"),
  center: identifier,
  radius: positiveNumber.optional(),
  through: identifier.optional(),
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  visibleWhen: visibleWhenSchema.optional(),
}).strict();

const angleShapeSchema = z.object({
  id: identifier,
  kind: z.literal("angle"),
  vertex: identifier,
  from: identifier,
  to: identifier,
  radius: positiveNumber.default(0.55),
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  visibleWhen: visibleWhenSchema.optional(),
}).strict();

const roundedBoxShapeSchema = z.object({
  id: identifier,
  kind: z.literal("roundedBox"),
  box: boundsSchema,
  cornerRadius: nonNegativeNumber,
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  visibleWhen: visibleWhenSchema.optional(),
}).strict();

const locusShapeSchema = z.object({
  id: identifier,
  kind: z.literal("locus"),
  points: z.array(coordinateSchema).min(2).max(maxLocusPoints),
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  visibleWhen: visibleWhenSchema.optional(),
}).strict();

const vectorShapeSchema = z.object({
  id: identifier,
  kind: z.literal("vector"),
  from: identifier,
  to: identifier,
  label: z.string().min(1).max(80),
  style: styleSchema.optional(),
  visibleWhen: visibleWhenSchema.optional(),
}).strict();

const polygonShapeSchema = z.object({
  id: identifier,
  kind: z.literal("polygon"),
  points: z.array(identifier).min(3).max(16),
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  visibleWhen: visibleWhenSchema.optional(),
}).strict();

const orientedBoxShapeSchema = z.object({
  id: identifier,
  kind: z.literal("orientedBox"),
  center: identifier,
  width: positiveNumber,
  height: positiveNumber,
  rotationDegrees: finiteNumber,
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  visibleWhen: visibleWhenSchema.optional(),
}).strict();

const shapeSchema = z.discriminatedUnion("kind", [
  segmentShapeSchema,
  circleShapeSchema,
  angleShapeSchema,
  roundedBoxShapeSchema,
  locusShapeSchema,
  vectorShapeSchema,
  polygonShapeSchema,
  orientedBoxShapeSchema,
]);

const pointCoordinateBindingSchema = z.object({
  kind: z.literal("pointCoordinate"),
  pointID: identifier,
  axis: z.enum(["x", "y"]),
  multiplier: finiteNumber.default(1),
  offset: finiteNumber.default(0),
  minimum: finiteNumber.optional(),
  maximum: finiteNumber.optional(),
}).strict();

const pointOnConstraintBindingSchema = z.object({
  kind: z.literal("pointOnConstraint"),
  pointID: identifier,
  multiplier: finiteNumber.default(1),
  offset: finiteNumber.default(0),
}).strict();

const circleRadiusBindingSchema = z.object({
  kind: z.literal("circleRadius"),
  shapeID: identifier,
  multiplier: finiteNumber.default(1),
  offset: finiteNumber.default(0),
  minimum: positiveNumber.optional(),
  maximum: positiveNumber.optional(),
}).strict();

const controlBindingSchema = z.discriminatedUnion("kind", [
  pointCoordinateBindingSchema,
  pointOnConstraintBindingSchema,
  circleRadiusBindingSchema,
]);

const controlSchema = z.object({
  id: identifier,
  label: z.string().min(1).max(80),
  value: controlValueSchema,
  minimum: finiteNumber.optional(),
  maximum: finiteNumber.optional(),
  step: positiveNumber.optional(),
  unit: z.string().min(1).max(24).optional(),
  options: z.array(z.object({
    value: controlValueSchema,
    label: z.string().min(1).max(80),
  }).strict()).min(1).max(12).optional(),
  presentation: z.enum(["slider", "segmented"]).default("slider"),
  bindings: z.array(controlBindingSchema).max(maxBindings).default([]),
}).strict().superRefine((control, context) => {
  const hasRange = control.minimum !== undefined && control.maximum !== undefined && control.step !== undefined;
  if (control.presentation === "slider" && !hasRange) {
    context.addIssue({ code: "custom", message: `滑杆控件 ${control.id} 必须提供 minimum / maximum / step。` });
  }
  if (hasRange && typeof control.value !== "number") {
    context.addIssue({ code: "custom", message: `范围控件 ${control.id} 的 value 必须是数字。` });
  }
});

const distanceReadoutSchema = z.object({
  id: identifier,
  kind: z.literal("distance"),
  label: z.string().min(1).max(80),
  from: identifier,
  to: identifier,
  unit: z.string().min(1).max(24).default("单位"),
}).strict();

const angleReadoutSchema = z.object({
  id: identifier,
  kind: z.literal("angle"),
  label: z.string().min(1).max(80),
  vertex: identifier,
  from: identifier,
  to: identifier,
  unit: z.literal("deg").default("deg"),
}).strict();

const pointReadoutSchema = z.object({
  id: identifier,
  kind: z.literal("point"),
  label: z.string().min(1).max(80),
  pointID: identifier,
}).strict();

const stateReadoutSchema = z.object({
  id: identifier,
  kind: z.literal("state"),
  label: z.string().min(1).max(80),
  controlID: identifier,
  options: z.array(z.object({
    value: controlValueSchema,
    label: z.string().min(1).max(80),
  }).strict()).min(1).max(12),
}).strict();

const readoutSchema = z.discriminatedUnion("kind", [
  distanceReadoutSchema,
  angleReadoutSchema,
  pointReadoutSchema,
  stateReadoutSchema,
]);

const coordinateSpaceSchema = boundsSchema.extend({
  preserveAspectRatio: z.boolean().default(true),
  gridStep: positiveNumber.optional(),
}).strict();

const geometry2DSpecSchema = z.object({
  title: z.string().min(1).max(140).default("二维几何实验"),
  coordinateSpace: coordinateSpaceSchema,
  points: z.array(pointSchema).min(1).max(maxPoints),
  shapes: z.array(shapeSchema).max(maxShapes).default([]),
  controls: z.array(controlSchema).max(maxControls).default([]),
  readouts: z.array(readoutSchema).max(16).default([]),
  showAxes: z.boolean().default(true),
  showGrid: z.boolean().default(true),
  caption: z.string().min(1).max(260).optional(),
}).strict();

export type Geometry2DSpec = z.infer<typeof geometry2DSpecSchema>;
export type GeometryPoint = z.infer<typeof pointSchema>;
export type GeometryShape = z.infer<typeof shapeSchema>;
export type GeometryConstraint = z.infer<typeof constraintSchema>;
export type GeometryControl = z.infer<typeof controlSchema>;
export type GeometryControlBinding = z.infer<typeof controlBindingSchema>;
export type GeometryReadout = z.infer<typeof readoutSchema>;
export type GeometryCoordinate = z.infer<typeof coordinateSchema>;
export type GeometryBounds = z.infer<typeof boundsSchema>;

type CheckResult =
  | { ok: true; spec: Geometry2DSpec }
  | { ok: false; issue: ReturnType<typeof createRendererIssue> };

export function parseGeometry2DSpec(plan: RenderPlan): CheckResult {
  const forbiddenPath = findForbiddenPayload(plan.spec);
  if (forbiddenPath) {
    return {
      ok: false,
      issue: createRendererIssue(
        "unsafe_payload",
        plan.renderer,
        "二维几何规格只能提交高层几何对象，不能提交 SVG path、脚本或像素布局。",
        [forbiddenPath],
      ),
    };
  }

  const result = geometry2DSpecSchema.safeParse(plan.spec);
  if (!result.success) {
    return {
      ok: false,
      issue: createRendererIssue(
        "validation_error",
        plan.renderer,
        result.error.issues[0]?.message ?? "二维几何规格不符合协议。",
        result.error.issues.map((issue) => issue.path.join(".")).filter(Boolean),
      ),
    };
  }

  const issue = guardGeometry2DSpec(plan, result.data);
  if (issue) return { ok: false, issue };
  return { ok: true, spec: result.data };
}

function guardGeometry2DSpec(plan: RenderPlan, spec: Geometry2DSpec) {
  if (plan.renderer !== GEOMETRY_2D_RENDERER) {
    return createRendererIssue("capability_mismatch", plan.renderer, `二维几何渲染器不能渲染 ${plan.renderer}。`);
  }
  if (plan.specVersion !== GEOMETRY_2D_SPEC_VERSION) {
    return createRendererIssue("capability_mismatch", plan.renderer, `二维几何只支持 ${GEOMETRY_2D_SPEC_VERSION}。`);
  }
  if (plan.qualityBudget.allowNetwork) {
    return createRendererIssue("capability_mismatch", plan.renderer, "二维几何渲染器不允许请求网络资源。");
  }
  if (plan.qualityBudget.allowWebGL) {
    return createRendererIssue("capability_mismatch", plan.renderer, "二维几何渲染器只使用本地 2D 图形，不接受 WebGL。");
  }
  if (spec.coordinateSpace.xMin >= spec.coordinateSpace.xMax) {
    return createRendererIssue("validation_error", plan.renderer, "coordinateSpace.xMin 必须小于 xMax。");
  }
  if (spec.coordinateSpace.yMin >= spec.coordinateSpace.yMax) {
    return createRendererIssue("validation_error", plan.renderer, "coordinateSpace.yMin 必须小于 yMax。");
  }

  const pointIDs = new Set<string>();
  for (const point of spec.points) {
    if (pointIDs.has(point.id)) {
      return createRendererIssue("validation_error", plan.renderer, `点 id 重复：${point.id}。`);
    }
    pointIDs.add(point.id);
    const constraintIssue = guardConstraint(plan, point);
    if (constraintIssue) return constraintIssue;
  }

  const shapeIDs = new Set<string>();
  let dataPointCount = spec.points.length;
  for (const shape of spec.shapes) {
    if (shapeIDs.has(shape.id) || pointIDs.has(shape.id)) {
      return createRendererIssue("validation_error", plan.renderer, `几何对象 id 重复：${shape.id}。`);
    }
    shapeIDs.add(shape.id);
    const shapeIssue = guardShape(plan, shape, pointIDs);
    if (shapeIssue) return shapeIssue;
    if (shape.kind === "locus") dataPointCount += shape.points.length;
  }

  const controlIDs = new Set<string>();
  let bindingCount = 0;
  for (const control of spec.controls) {
    if (controlIDs.has(control.id)) {
      return createRendererIssue("validation_error", plan.renderer, `控件 id 重复：${control.id}。`);
    }
    controlIDs.add(control.id);
    if (
      control.minimum !== undefined &&
      control.maximum !== undefined &&
      typeof control.value === "number" &&
      (control.minimum >= control.maximum || control.value < control.minimum || control.value > control.maximum)
    ) {
      return createRendererIssue("validation_error", plan.renderer, `控件 ${control.id} 的范围或初值无效。`);
    }
    if (control.options?.length && !control.options.some((option) => option.value === control.value)) {
      return createRendererIssue("validation_error", plan.renderer, `控件 ${control.id} 的初值不在 options 中。`);
    }
    if (control.bindings.length && typeof control.value !== "number") {
      return createRendererIssue("validation_error", plan.renderer, `带几何绑定的控件 ${control.id} 必须使用数字 value。`);
    }
    bindingCount += control.bindings.length;
    for (const binding of control.bindings) {
      const bindingIssue = guardBinding(plan, binding, pointIDs, shapeIDs, spec);
      if (bindingIssue) return bindingIssue;
    }
  }

  const visibleWhenControlIDs = new Set<string>();
  for (const shape of spec.shapes) {
    if (!shape.visibleWhen) continue;
    if (!controlIDs.has(shape.visibleWhen.controlID)) {
      return createRendererIssue("validation_error", plan.renderer, `几何对象 ${shape.id} 的 visibleWhen 引用了不存在的控件：${shape.visibleWhen.controlID}。`);
    }
    visibleWhenControlIDs.add(shape.visibleWhen.controlID);
  }

  const stateReadoutControlIDs = new Set<string>();
  for (const readout of spec.readouts) {
    if (readout.kind === "state") {
      if (!controlIDs.has(readout.controlID)) {
        return createRendererIssue("validation_error", plan.renderer, `状态读数 ${readout.id} 引用了不存在的控件：${readout.controlID}。`);
      }
      stateReadoutControlIDs.add(readout.controlID);
      continue;
    }
    const refs = readout.kind === "point"
      ? [readout.pointID]
      : readout.kind === "distance"
        ? [readout.from, readout.to]
        : [readout.from, readout.to, readout.vertex];
    const missing = refs.filter((id) => !pointIDs.has(id));
    if (missing.length) {
      return createRendererIssue("validation_error", plan.renderer, `读数 ${readout.id} 引用了不存在的点：${missing.join("、")}。`);
    }
  }

  for (const control of spec.controls) {
    if (
      control.bindings.length === 0 &&
      !visibleWhenControlIDs.has(control.id) &&
      !stateReadoutControlIDs.has(control.id)
    ) {
      return createRendererIssue("validation_error", plan.renderer, `无绑定控件 ${control.id} 必须驱动 visibleWhen 或 state 读数。`);
    }
  }

  const nodeBudget = plan.qualityBudget.maxNodes ?? 260;
  const nodeCount = spec.points.length + spec.shapes.length + spec.controls.length + bindingCount + spec.readouts.length;
    if (nodeCount > nodeBudget) {
    return createRendererIssue("validation_error", plan.renderer, `二维几何节点数 ${nodeCount} 超过预算 ${nodeBudget}。`);
  }

  const dataBudget = plan.qualityBudget.maxDataPoints ?? maxDataPoints;
  if (dataPointCount > dataBudget || dataPointCount > maxDataPoints) {
    return createRendererIssue("validation_error", plan.renderer, `二维几何采样点数 ${dataPointCount} 超过预算。`);
  }

  return null;
}

function guardConstraint(plan: RenderPlan, point: GeometryPoint) {
  const constraint = point.constraint;
  if (!constraint) return null;
  if (constraint.kind === "lineSegment" && samePoint(constraint.start, constraint.end)) {
    return createRendererIssue("validation_error", plan.renderer, `点 ${point.id} 的线段约束长度不能为 0。`);
  }
  if (constraint.kind === "roundedBoxTrack") {
    const issue = guardBounds(plan, constraint.box, `点 ${point.id} 的圆角轨道`);
    if (issue) return issue;
    const maxRadius = Math.min(
      constraint.box.xMax - constraint.box.xMin,
      constraint.box.yMax - constraint.box.yMin,
    ) / 2;
    if (constraint.cornerRadius > maxRadius) {
      return createRendererIssue("validation_error", plan.renderer, `点 ${point.id} 的圆角半径不能超过轨道半宽或半高。`);
    }
  }
  return null;
}

function guardShape(plan: RenderPlan, shape: GeometryShape, pointIDs: Set<string>) {
  const requirePoint = (id: string, label: string) => {
    return pointIDs.has(id)
      ? null
      : createRendererIssue("validation_error", plan.renderer, `${shape.id}.${label} 引用了不存在的点 ${id}。`);
  };

  if (shape.kind === "segment" || shape.kind === "vector") {
    return requirePoint(shape.from, "from") ?? requirePoint(shape.to, "to");
  }
  if (shape.kind === "circle") {
    const issue = requirePoint(shape.center, "center") ?? (shape.through ? requirePoint(shape.through, "through") : null);
    if (issue) return issue;
    if (!shape.radius && !shape.through) {
      return createRendererIssue("validation_error", plan.renderer, `圆 ${shape.id} 必须提供 radius 或 through。`);
    }
    return null;
  }
  if (shape.kind === "angle") {
    return requirePoint(shape.vertex, "vertex") ?? requirePoint(shape.from, "from") ?? requirePoint(shape.to, "to");
  }
  if (shape.kind === "roundedBox") {
    const issue = guardBounds(plan, shape.box, `圆角框 ${shape.id}`);
    if (issue) return issue;
    const maxRadius = Math.min(shape.box.xMax - shape.box.xMin, shape.box.yMax - shape.box.yMin) / 2;
    if (shape.cornerRadius > maxRadius) {
      return createRendererIssue("validation_error", plan.renderer, `圆角框 ${shape.id} 的 cornerRadius 过大。`);
    }
  }
  if (shape.kind === "polygon") {
    const missing = shape.points.filter((id) => !pointIDs.has(id));
    if (missing.length) {
      return createRendererIssue("validation_error", plan.renderer, `多边形 ${shape.id} 引用了不存在的点：${missing.join("、")}。`);
    }
  }
  if (shape.kind === "orientedBox") {
    return requirePoint(shape.center, "center");
  }
  return null;
}

function guardBinding(
  plan: RenderPlan,
  binding: GeometryControlBinding,
  pointIDs: Set<string>,
  shapeIDs: Set<string>,
  spec: Geometry2DSpec,
) {
  if (binding.kind === "circleRadius") {
    const target = spec.shapes.find((shape) => shape.id === binding.shapeID);
    if (!shapeIDs.has(binding.shapeID) || target?.kind !== "circle") {
      return createRendererIssue("validation_error", plan.renderer, `控件绑定引用了不存在的圆：${binding.shapeID}。`);
    }
    if (binding.minimum !== undefined && binding.maximum !== undefined && binding.minimum >= binding.maximum) {
      return createRendererIssue("validation_error", plan.renderer, `圆半径绑定 ${binding.shapeID} 的 minimum 必须小于 maximum。`);
    }
    return null;
  }

  if (!pointIDs.has(binding.pointID)) {
    return createRendererIssue("validation_error", plan.renderer, `控件绑定引用了不存在的点：${binding.pointID}。`);
  }

  if (binding.kind === "pointOnConstraint") {
    const point = spec.points.find((item) => item.id === binding.pointID);
    if (!point?.constraint || point.constraint.kind === "free") {
      return createRendererIssue("validation_error", plan.renderer, `pointOnConstraint 只能绑定到带轨道约束的点：${binding.pointID}。`);
    }
  }

  if (
    binding.kind === "pointCoordinate" &&
    binding.minimum !== undefined &&
    binding.maximum !== undefined &&
    binding.minimum >= binding.maximum
  ) {
    return createRendererIssue("validation_error", plan.renderer, `点坐标绑定 ${binding.pointID}.${binding.axis} 的 minimum 必须小于 maximum。`);
  }

  return null;
}

function guardBounds(plan: RenderPlan, bounds: GeometryBounds, label: string) {
  if (bounds.xMin >= bounds.xMax) {
    return createRendererIssue("validation_error", plan.renderer, `${label}.xMin 必须小于 xMax。`);
  }
  if (bounds.yMin >= bounds.yMax) {
    return createRendererIssue("validation_error", plan.renderer, `${label}.yMin 必须小于 yMax。`);
  }
  return null;
}

function samePoint(left: GeometryCoordinate, right: GeometryCoordinate) {
  return Math.abs(left.x - right.x) <= 1e-12 && Math.abs(left.y - right.y) <= 1e-12;
}

function findForbiddenPayload(value: unknown, path = "spec"): string | null {
  const forbiddenKey = /(?:svg|path|script|pixel|pixels|px|clientx|clienty|screenx|screeny|offsetleft|offsettop|absolute|fixed|css|html)/i;
  const forbiddenString = /<\/?(?:svg|script|iframe|html)\b|javascript:|data:text\/html|<path\b|\bd\s*=\s*["'][Mm][^"']*/i;

  if (typeof value === "string") {
    return forbiddenString.test(value) ? path : null;
  }
  if (!value || typeof value !== "object") return null;
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      const issue = findForbiddenPayload(value[index], `${path}.${index}`);
      if (issue) return issue;
    }
    return null;
  }

  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (forbiddenKey.test(key)) return `${path}.${key}`;
    const issue = findForbiddenPayload(child, `${path}.${key}`);
    if (issue) return issue;
  }
  return null;
}

const baseRenderPlan: Omit<RenderPlan, "renderer" | "specVersion" | "spec"> = {
  interactionBindings: [],
  sourceBindings: [{ id: "src-default", sourceID: "lesson-geometry", locator: "p1" }],
  artifactRefs: [],
  fallback: {
    mode: "narrativeOnly",
    reason: "schema-check",
    text: "当前场景不满足二维几何渲染规范。",
    preservesSourceBinding: true,
  },
  qualityBudget: {
    allowAnimation: false,
    allowWebGL: false,
    allowNetwork: false,
    maxDataPoints,
    maxHeight: 520,
    maxNodes: 220,
  },
};

function renderPlanForGeometry(spec: Record<string, unknown>): RenderPlan {
  return {
    renderer: GEOMETRY_2D_RENDERER,
    specVersion: GEOMETRY_2D_SPEC_VERSION,
    spec,
    ...baseRenderPlan,
  };
}

export const geometry2DSelfCheckCases = [
  {
    name: "二维几何合法：圆角轨道拖拽与多绑定控件",
    plan: renderPlanForGeometry({
      title: "圆角轨道上的动点实验",
      coordinateSpace: { xMin: -1, xMax: 7, yMin: -1, yMax: 5, gridStep: 1 },
      points: [
        { id: "a", label: "A", x: 0, y: 0, draggable: true },
        { id: "b", label: "B", x: 5, y: 0, draggable: true },
        {
          id: "p",
          label: "P",
          x: 5,
          y: 3,
          draggable: true,
          constraint: {
            kind: "roundedBoxTrack",
            box: { xMin: 0, xMax: 5, yMin: 0, yMax: 3 },
            cornerRadius: 0.6,
            showTrack: true,
          },
        },
      ],
      shapes: [
        { id: "ab", kind: "segment", from: "a", to: "b", label: "底边" },
        { id: "ap", kind: "segment", from: "a", to: "p", label: "连线" },
        { id: "bp", kind: "segment", from: "b", to: "p", label: "连线" },
        { id: "track", kind: "roundedBox", box: { xMin: 0, xMax: 5, yMin: 0, yMax: 3 }, cornerRadius: 0.6, label: "约束轨道" },
      ],
      controls: [
        {
          id: "t",
          label: "轨道位置",
          value: 0.18,
          minimum: 0,
          maximum: 1,
          step: 0.01,
          bindings: [{ kind: "pointOnConstraint", pointID: "p" }],
        },
        {
          id: "lift",
          label: "底边抬升",
          value: 0,
          minimum: -0.5,
          maximum: 0.8,
          step: 0.1,
          bindings: [
            { kind: "pointCoordinate", pointID: "a", axis: "y", multiplier: 1 },
            { kind: "pointCoordinate", pointID: "b", axis: "y", multiplier: 1 },
          ],
        },
      ],
      readouts: [
        { id: "d-ap", kind: "distance", label: "AP", from: "a", to: "p" },
        { id: "ang-a", kind: "angle", label: "∠BAP", vertex: "a", from: "b", to: "p" },
      ],
      caption: "模型只给点、线、圆角轨道与控件绑定；拖拽和约束投影由本地 renderer 决定。",
    }),
    expectOk: true,
  },
  {
    name: "二维几何合法：圆与半径控件",
    plan: renderPlanForGeometry({
      title: "圆半径协调实验",
      coordinateSpace: { xMin: -4, xMax: 4, yMin: -3, yMax: 3, gridStep: 1 },
      points: [
        { id: "o", label: "O", x: 0, y: 0, draggable: true },
        { id: "q", label: "Q", x: 2, y: 0, draggable: true, constraint: { kind: "circle", center: { x: 0, y: 0 }, radius: 2 } },
      ],
      shapes: [
        { id: "c", kind: "circle", center: "o", through: "q", label: "圆 OQ" },
        { id: "oq", kind: "segment", from: "o", to: "q", label: "半径" },
      ],
      controls: [
        {
          id: "angle",
          label: "Q 的角位置",
          value: 0.25,
          minimum: 0,
          maximum: 1,
          step: 0.01,
          bindings: [{ kind: "pointOnConstraint", pointID: "q" }],
        },
      ],
      readouts: [{ id: "q-pos", kind: "point", label: "Q 坐标", pointID: "q" }],
    }),
    expectOk: true,
  },
  {
    name: "二维几何合法：语义向量、多边形、有方向盒体与状态显隐",
    plan: renderPlanForGeometry({
      title: "二维受力关系观察",
      coordinateSpace: { xMin: -1, xMax: 7, yMin: -1, yMax: 5, gridStep: 1 },
      points: [
        { id: "a", label: "A", x: 0.6, y: 0.4 },
        { id: "b", label: "B", x: 5.8, y: 0.4 },
        { id: "c", label: "C", x: 5.8, y: 3.2 },
        { id: "body-center", label: "物体", x: 3.2, y: 1.9, draggable: true },
        { id: "force-start", x: 3.2, y: 1.9 },
        { id: "gravity-end", x: 3.2, y: 0.75 },
        { id: "normal-end", x: 2.7, y: 2.85 },
        { id: "friction-end", x: 4.15, y: 1.55 },
      ],
      shapes: [
        {
          id: "slope-face",
          kind: "polygon",
          points: ["a", "b", "c"],
          label: "参考面",
          style: { stroke: "rgba(90, 76, 56, 0.55)", fill: "rgba(126, 148, 126, 0.18)" },
        },
        {
          id: "body",
          kind: "orientedBox",
          center: "body-center",
          width: 1.0,
          height: 0.56,
          rotationDegrees: 28,
          label: "受力物体",
          style: { stroke: "rgba(84, 66, 48, 0.82)", fill: "rgba(255, 255, 255, 0.36)" },
        },
        {
          id: "gravity",
          kind: "vector",
          from: "force-start",
          to: "gravity-end",
          label: "重力",
          style: { stroke: "rgba(144, 72, 50, 0.92)", strokeWidth: 2.4 },
          visibleWhen: { controlID: "force-mode", equals: "all" },
        },
        {
          id: "normal",
          kind: "vector",
          from: "force-start",
          to: "normal-end",
          label: "支持力",
          style: { stroke: "rgba(48, 94, 110, 0.9)", strokeWidth: 2.4 },
          visibleWhen: { controlID: "force-mode", equals: "all" },
        },
        {
          id: "friction",
          kind: "vector",
          from: "force-start",
          to: "friction-end",
          label: "摩擦趋势",
          style: { stroke: "rgba(100, 112, 66, 0.9)", strokeWidth: 2.4, dash: true },
          visibleWhen: { controlID: "force-mode", equals: "friction" },
        },
      ],
      controls: [
        {
          id: "force-mode",
          label: "显示受力",
          value: "all",
          presentation: "segmented",
          options: [
            { value: "all", label: "合力关系" },
            { value: "friction", label: "只看摩擦趋势" },
          ],
          bindings: [],
        },
      ],
      readouts: [
        {
          id: "mode-readout",
          kind: "state",
          label: "当前视角",
          controlID: "force-mode",
          options: [
            { value: "all", label: "重力与支持力共同读" },
            { value: "friction", label: "突出沿面反向趋势" },
          ],
        },
      ],
      caption: "这里使用通用多边形、有方向盒体、带箭头向量与状态显隐；不是某个题目的专属组件。",
    }),
    expectOk: true,
  },
  {
    name: "拒绝 SVG path",
    plan: renderPlanForGeometry({
      title: "非法路径",
      coordinateSpace: { xMin: 0, xMax: 1, yMin: 0, yMax: 1 },
      points: [{ id: "a", x: 0, y: 0 }],
      path: "M0 0L1 1",
    }),
    expectOk: false,
    issueCode: "unsafe_payload",
  },
  {
    name: "拒绝像素布局字段",
    plan: renderPlanForGeometry({
      title: "非法像素",
      coordinateSpace: { xMin: 0, xMax: 1, yMin: 0, yMax: 1 },
      points: [{ id: "a", x: 0, y: 0, pixelX: 12 }],
    }),
    expectOk: false,
    issueCode: "unsafe_payload",
  },
  {
    name: "缺失点引用失败",
    plan: renderPlanForGeometry({
      title: "坏引用",
      coordinateSpace: { xMin: 0, xMax: 1, yMin: 0, yMax: 1 },
      points: [{ id: "a", x: 0, y: 0 }],
      shapes: [{ id: "bad", kind: "segment", from: "a", to: "missing" }],
    }),
    expectOk: false,
    issueCode: "validation_error",
  },
] as const;

export function createSelfCheckPlan(issueCase: (typeof geometry2DSelfCheckCases)[number]) {
  return parseGeometry2DSpec(issueCase.plan);
}

export function runGeometry2DSelfChecks() {
  return geometry2DSelfCheckCases.map((issueCase) => {
    const result = createSelfCheckPlan(issueCase);
    const passed = issueCase.expectOk
      ? result.ok
      : !result.ok && (!("issueCode" in issueCase) || result.issue.code === issueCase.issueCode);
    return {
      name: issueCase.name,
      passed,
      ok: result.ok,
      issueCode: result.ok ? null : result.issue.code,
    };
  });
}
