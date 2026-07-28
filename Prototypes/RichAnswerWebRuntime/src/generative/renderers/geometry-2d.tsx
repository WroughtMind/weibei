import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from "react";
import {
  createRendererIssue,
  type CompiledRenderPlan,
  type RendererLifecycleContext,
  type RichAnswerRenderer,
} from "../renderer-registry";
import {
  GEOMETRY_2D_RENDERER,
  GEOMETRY_2D_SPEC_VERSION,
  geometry2DSurfaceMetrics,
  parseGeometry2DSpec,
  type Geometry2DSpec,
  type GeometryBounds,
  type GeometryConstraint,
  type GeometryControl,
  type GeometryControlBinding,
  type GeometryCoordinate,
  type GeometryPoint,
  type GeometryReadout,
  type GeometryShape,
} from "./geometry-2d.self-check";

type GeometryCompiled = CompiledRenderPlan & {
  spec: Geometry2DSpec;
};

type Viewport = {
  width: number;
  height: number;
};

type PlotRect = {
  left: number;
  top: number;
  width: number;
  height: number;
};

type ScreenProjection = {
  bounds: GeometryBounds;
  plot: PlotRect;
  xScale: number;
  yScale: number;
};

type GeometryControlValue = GeometryControl["value"];

type ScenePoint = GeometryCoordinate & {
  id: string;
  label?: string;
  draggable: boolean;
  constraint?: GeometryConstraint;
  style?: GeometryPoint["style"];
};

type SceneState = {
  points: Map<string, ScenePoint>;
  radiusOverrides: Record<string, number>;
};

type DragState = {
  pointID: string;
  pointerID: number;
};

type LabelBox = {
  x: number;
  y: number;
  width: number;
  height: number;
};

type LineObstacle = {
  start: GeometryCoordinate;
  end: GeometryCoordinate;
};

type LabelCandidate = {
  x: number;
  y: number;
  box: LabelBox;
  score: number;
  align: "start" | "middle" | "end";
};

type PlannedLabel = {
  id: string;
  text: string;
  x: number;
  y: number;
  box: LabelBox;
  align: "start" | "middle" | "end";
  fontSize: number;
  weight: number;
  fill: string;
  background: string;
  priority: number;
};

type PointVisual = {
  visible: boolean;
  radius: number;
  opacity: number;
};

const defaultStyle = {
  stroke: "rgba(85, 64, 43, 0.92)",
  strokeWidth: 2,
  fill: "transparent",
  opacity: 0.92,
  dash: false,
};

const defaultPointStyle = {
  stroke: "rgba(80, 52, 35, 0.96)",
  fill: "rgba(156, 73, 49, 0.95)",
  radius: 5,
};

const clamp = (value: number, minimum: number, maximum: number) => Math.max(minimum, Math.min(maximum, value));
const roundValue = (value: number) => Math.round(value * 1_000_000) / 1_000_000;

function formatNumber(value: number) {
  if (!Number.isFinite(value)) return "—";
  if (Math.abs(value) >= 10_000 || (Math.abs(value) > 0 && Math.abs(value) < 0.001)) {
    return value.toExponential(2);
  }
  return Number.isInteger(value) ? String(value) : value.toFixed(3).replace(/\.?0+$/, "");
}

function distance(left: GeometryCoordinate, right: GeometryCoordinate) {
  return Math.hypot(left.x - right.x, left.y - right.y);
}

function samePoint(left: GeometryCoordinate, right: GeometryCoordinate) {
  return distance(left, right) <= 1e-12;
}

function interpolate(left: GeometryCoordinate, right: GeometryCoordinate, t: number) {
  return {
    x: left.x + (right.x - left.x) * t,
    y: left.y + (right.y - left.y) * t,
  };
}

function projectToSegment(point: GeometryCoordinate, start: GeometryCoordinate, end: GeometryCoordinate) {
  const vx = end.x - start.x;
  const vy = end.y - start.y;
  const lengthSq = vx * vx + vy * vy;
  if (lengthSq <= 1e-12) return { ...start, t: 0 };
  const t = clamp(((point.x - start.x) * vx + (point.y - start.y) * vy) / lengthSq, 0, 1);
  return { ...interpolate(start, end, t), t };
}

function projectToCircle(point: GeometryCoordinate, center: GeometryCoordinate, radius: number) {
  const angle = Math.atan2(point.y - center.y, point.x - center.x);
  const safeAngle = Number.isFinite(angle) ? angle : 0;
  return {
    x: center.x + Math.cos(safeAngle) * radius,
    y: center.y + Math.sin(safeAngle) * radius,
    t: ((safeAngle + Math.PI * 2) % (Math.PI * 2)) / (Math.PI * 2),
  };
}

function roundedTrackMetrics(box: GeometryBounds, radius: number) {
  const width = box.xMax - box.xMin;
  const height = box.yMax - box.yMin;
  const r = clamp(radius, 0, Math.min(width, height) / 2);
  const straightX = Math.max(0, width - 2 * r);
  const straightY = Math.max(0, height - 2 * r);
  const arc = (Math.PI * r) / 2;
  const total = 2 * straightX + 2 * straightY + 4 * arc;
  return { r, straightX, straightY, arc, total: Math.max(total, 1e-12) };
}

function roundedTrackPointAt(box: GeometryBounds, radius: number, t: number): GeometryCoordinate {
  const metrics = roundedTrackMetrics(box, radius);
  const { r, straightX, straightY, arc, total } = metrics;
  let remaining = ((t % 1) + 1) % 1 * total;
  const consume = (length: number) => {
    if (remaining <= length) return false;
    remaining -= length;
    return true;
  };

  if (!consume(straightX)) return { x: box.xMin + r + remaining, y: box.yMin };
  if (!consume(arc)) {
    const angle = -Math.PI / 2 + (remaining / Math.max(arc, 1e-12)) * Math.PI / 2;
    return { x: box.xMax - r + Math.cos(angle) * r, y: box.yMin + r + Math.sin(angle) * r };
  }
  if (!consume(straightY)) return { x: box.xMax, y: box.yMin + r + remaining };
  if (!consume(arc)) {
    const angle = (remaining / Math.max(arc, 1e-12)) * Math.PI / 2;
    return { x: box.xMax - r + Math.cos(angle) * r, y: box.yMax - r + Math.sin(angle) * r };
  }
  if (!consume(straightX)) return { x: box.xMax - r - remaining, y: box.yMax };
  if (!consume(arc)) {
    const angle = Math.PI / 2 + (remaining / Math.max(arc, 1e-12)) * Math.PI / 2;
    return { x: box.xMin + r + Math.cos(angle) * r, y: box.yMax - r + Math.sin(angle) * r };
  }
  if (!consume(straightY)) return { x: box.xMin, y: box.yMax - r - remaining };

  const angle = Math.PI + (remaining / Math.max(arc, 1e-12)) * Math.PI / 2;
  return { x: box.xMin + r + Math.cos(angle) * r, y: box.yMin + r + Math.sin(angle) * r };
}

function nearestRoundedTrackPoint(point: GeometryCoordinate, box: GeometryBounds, radius: number) {
  let best = { ...roundedTrackPointAt(box, radius, 0), t: 0, d: Number.POSITIVE_INFINITY };
  const samples = 160;
  for (let index = 0; index < samples; index += 1) {
    const t = index / samples;
    const candidate = roundedTrackPointAt(box, radius, t);
    const d = distance(point, candidate);
    if (d < best.d) best = { ...candidate, t, d };
  }

  const step = 1 / samples;
  for (let pass = 0; pass < 5; pass += 1) {
    const span = step / (2 ** pass);
    const left = roundedTrackPointAt(box, radius, best.t - span);
    const right = roundedTrackPointAt(box, radius, best.t + span);
    const leftD = distance(point, left);
    const rightD = distance(point, right);
    if (leftD < best.d) best = { ...left, t: ((best.t - span) % 1 + 1) % 1, d: leftD };
    if (rightD < best.d) best = { ...right, t: ((best.t + span) % 1 + 1) % 1, d: rightD };
  }
  return { x: best.x, y: best.y, t: best.t };
}

function pointAtConstraint(constraint: GeometryConstraint | undefined, base: GeometryCoordinate, rawT: number) {
  const t = clamp(rawT, 0, 1);
  if (!constraint || constraint.kind === "free") return base;
  if (constraint.kind === "axis") {
    return constraint.axis === "x"
      ? { x: constraint.value, y: base.y }
      : { x: base.x, y: constraint.value };
  }
  if (constraint.kind === "lineSegment") return interpolate(constraint.start, constraint.end, t);
  if (constraint.kind === "circle") {
    return {
      x: constraint.center.x + Math.cos(t * Math.PI * 2) * constraint.radius,
      y: constraint.center.y + Math.sin(t * Math.PI * 2) * constraint.radius,
    };
  }
  return roundedTrackPointAt(constraint.box, constraint.cornerRadius, t);
}

function projectToConstraint(point: GeometryCoordinate, constraint?: GeometryConstraint) {
  if (!constraint || constraint.kind === "free") return point;
  if (constraint.kind === "axis") {
    return constraint.axis === "x"
      ? { x: constraint.value, y: point.y }
      : { x: point.x, y: constraint.value };
  }
  if (constraint.kind === "lineSegment") return projectToSegment(point, constraint.start, constraint.end);
  if (constraint.kind === "circle") return projectToCircle(point, constraint.center, constraint.radius);
  return nearestRoundedTrackPoint(point, constraint.box, constraint.cornerRadius);
}

function initialControlValues(controls: GeometryControl[]): Record<string, GeometryControlValue> {
  return Object.fromEntries(controls.map((control) => [control.id, control.value]));
}

function clampBindingValue(value: number, minimum?: number, maximum?: number) {
  if (minimum !== undefined && maximum !== undefined) return clamp(value, minimum, maximum);
  if (minimum !== undefined) return Math.max(minimum, value);
  if (maximum !== undefined) return Math.min(maximum, value);
  return value;
}

function applyBinding(
  binding: GeometryControlBinding,
  value: number,
  points: Map<string, ScenePoint>,
  radiusOverrides: Record<string, number>,
) {
  const nextValue = value * binding.multiplier + binding.offset;
  if (binding.kind === "circleRadius") {
    radiusOverrides[binding.shapeID] = clampBindingValue(nextValue, binding.minimum, binding.maximum);
    return;
  }

  const point = points.get(binding.pointID);
  if (!point) return;
  if (binding.kind === "pointOnConstraint") {
    points.set(point.id, { ...point, ...pointAtConstraint(point.constraint, point, nextValue) });
    return;
  }

  const coordinate = binding.axis === "x"
    ? { x: clampBindingValue(nextValue, binding.minimum, binding.maximum), y: point.y }
    : { x: point.x, y: clampBindingValue(nextValue, binding.minimum, binding.maximum) };
  points.set(point.id, { ...point, ...projectToConstraint(coordinate, point.constraint) });
}

function computeScene(
  spec: Geometry2DSpec,
  controlValues: Record<string, GeometryControlValue>,
  pointOverrides: Record<string, GeometryCoordinate>,
): SceneState {
  const points = new Map<string, ScenePoint>();
  const radiusOverrides: Record<string, number> = {};

  for (const point of spec.points) {
    const projected = projectToConstraint({ x: point.x, y: point.y }, point.constraint);
    points.set(point.id, {
      id: point.id,
      label: point.label,
      draggable: point.draggable,
      constraint: point.constraint,
      style: point.style,
      x: roundValue(projected.x),
      y: roundValue(projected.y),
    });
  }

  for (const control of spec.controls) {
    const value = controlValues[control.id] ?? control.value;
    if (typeof value !== "number") continue;
    for (const binding of control.bindings) {
      applyBinding(binding, value, points, radiusOverrides);
    }
  }

  for (const [pointID, override] of Object.entries(pointOverrides)) {
    const point = points.get(pointID);
    if (point) points.set(pointID, { ...point, ...projectToConstraint(override, point.constraint) });
  }

  return { points, radiusOverrides };
}

function expandBounds(bounds: GeometryBounds, viewport: Viewport, preserveAspectRatio: boolean): GeometryBounds {
  if (!preserveAspectRatio || viewport.width <= 0 || viewport.height <= 0) return bounds;
  const plotRatio = viewport.width / Math.max(viewport.height, 1);
  const spanX = bounds.xMax - bounds.xMin;
  const spanY = bounds.yMax - bounds.yMin;
  const domainRatio = spanX / Math.max(spanY, 1e-12);
  if (Math.abs(plotRatio - domainRatio) <= 1e-6) return bounds;

  const centerX = (bounds.xMin + bounds.xMax) / 2;
  const centerY = (bounds.yMin + bounds.yMax) / 2;
  if (domainRatio < plotRatio) {
    const nextSpanX = spanY * plotRatio;
    return { ...bounds, xMin: centerX - nextSpanX / 2, xMax: centerX + nextSpanX / 2 };
  }

  const nextSpanY = spanX / plotRatio;
  return { ...bounds, yMin: centerY - nextSpanY / 2, yMax: centerY + nextSpanY / 2 };
}

function createProjection(spec: Geometry2DSpec, viewport: Viewport): ScreenProjection {
  const padding = viewport.width < 420 ? 26 : 34;
  const plot = {
    left: padding,
    top: padding,
    width: Math.max(1, viewport.width - padding * 2),
    height: Math.max(1, viewport.height - padding * 2),
  };
  const bounds = expandBounds(spec.coordinateSpace, { width: plot.width, height: plot.height }, spec.coordinateSpace.preserveAspectRatio);
  return {
    bounds,
    plot,
    xScale: plot.width / Math.max(bounds.xMax - bounds.xMin, 1e-12),
    yScale: plot.height / Math.max(bounds.yMax - bounds.yMin, 1e-12),
  };
}

function worldToScreen(point: GeometryCoordinate, projection: ScreenProjection) {
  return {
    x: projection.plot.left + (point.x - projection.bounds.xMin) * projection.xScale,
    y: projection.plot.top + (projection.bounds.yMax - point.y) * projection.yScale,
  };
}

function screenToWorld(point: GeometryCoordinate, projection: ScreenProjection) {
  return {
    x: projection.bounds.xMin + (point.x - projection.plot.left) / projection.xScale,
    y: projection.bounds.yMax - (point.y - projection.plot.top) / projection.yScale,
  };
}

function worldLengthToScreen(length: number, projection: ScreenProjection) {
  return {
    x: Math.abs(length * projection.xScale),
    y: Math.abs(length * projection.yScale),
  };
}

function rectToScreen(box: GeometryBounds, projection: ScreenProjection) {
  const topLeft = worldToScreen({ x: box.xMin, y: box.yMax }, projection);
  const bottomRight = worldToScreen({ x: box.xMax, y: box.yMin }, projection);
  return {
    x: topLeft.x,
    y: topLeft.y,
    width: bottomRight.x - topLeft.x,
    height: bottomRight.y - topLeft.y,
  };
}

function lineDash(style: typeof defaultStyle) {
  return style.dash ? "5 5" : undefined;
}

function boxesOverlap(left: LabelBox, right: LabelBox, gap = 0) {
  return (
    left.x < right.x + right.width + gap
    && left.x + left.width + gap > right.x
    && left.y < right.y + right.height + gap
    && left.y + left.height + gap > right.y
  );
}

function boxDistance(left: LabelBox, right: LabelBox) {
  const dx = Math.max(right.x - (left.x + left.width), left.x - (right.x + right.width), 0);
  const dy = Math.max(right.y - (left.y + left.height), left.y - (right.y + right.height), 0);
  return Math.hypot(dx, dy);
}

function clampBoxToViewport(box: LabelBox, viewport: Viewport) {
  const margin = 5;
  return {
    ...box,
    x: clamp(box.x, margin, Math.max(margin, viewport.width - box.width - margin)),
    y: clamp(box.y, margin, Math.max(margin, viewport.height - box.height - margin)),
  };
}

function segmentIntersectsBox(start: GeometryCoordinate, end: GeometryCoordinate, box: LabelBox, padding = 3) {
  const expanded = {
    xMin: box.x - padding,
    yMin: box.y - padding,
    xMax: box.x + box.width + padding,
    yMax: box.y + box.height + padding,
  };
  const inside = (point: GeometryCoordinate) => (
    point.x >= expanded.xMin
    && point.x <= expanded.xMax
    && point.y >= expanded.yMin
    && point.y <= expanded.yMax
  );
  if (inside(start) || inside(end)) return true;

  const cross = (a: GeometryCoordinate, b: GeometryCoordinate, c: GeometryCoordinate) => (
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
  );
  const intersects = (
    a: GeometryCoordinate,
    b: GeometryCoordinate,
    c: GeometryCoordinate,
    d: GeometryCoordinate,
  ) => {
    const first = cross(a, b, c);
    const second = cross(a, b, d);
    const third = cross(c, d, a);
    const fourth = cross(c, d, b);
    return first * second <= 0 && third * fourth <= 0;
  };
  const topLeft = { x: expanded.xMin, y: expanded.yMin };
  const topRight = { x: expanded.xMax, y: expanded.yMin };
  const bottomRight = { x: expanded.xMax, y: expanded.yMax };
  const bottomLeft = { x: expanded.xMin, y: expanded.yMax };
  return (
    intersects(start, end, topLeft, topRight)
    || intersects(start, end, topRight, bottomRight)
    || intersects(start, end, bottomRight, bottomLeft)
    || intersects(start, end, bottomLeft, topLeft)
  );
}

function labelWidth(text: string, fontSize: number) {
  const ascii = text.match(/[ -~]/g)?.length ?? 0;
  const fullWidth = Math.max(0, text.length - ascii);
  return Math.min(260, Math.max(18, ascii * fontSize * 0.55 + fullWidth * fontSize * 0.92 + 12));
}

function candidateForLabel(
  anchor: GeometryCoordinate,
  text: string,
  fontSize: number,
  dx: number,
  dy: number,
  viewport: Viewport,
  align: "start" | "middle" | "end" = "start",
  baseScore = 0,
): LabelCandidate {
  const width = labelWidth(text, fontSize);
  const height = fontSize + 8;
  const rawX = anchor.x + dx - (align === "middle" ? width / 2 : align === "end" ? width : 0);
  const rawY = anchor.y + dy - height / 2;
  const box = clampBoxToViewport({ x: rawX, y: rawY, width, height }, viewport);
  const clampPenalty = Math.abs(box.x - rawX) + Math.abs(box.y - rawY);
  return {
    x: box.x + (align === "middle" ? width / 2 : align === "end" ? width : 0),
    y: box.y + height / 2 + fontSize * 0.36,
    box,
    align,
    score: baseScore + clampPenalty * 0.7 + Math.hypot(dx, dy) * 0.04,
  };
}

function pointAnchorBox(point: ScenePoint, projection: ScreenProjection, radius: number): LabelBox {
  const screen = worldToScreen(point, projection);
  const padding = point.draggable ? 7 : 4;
  return {
    x: screen.x - radius - padding,
    y: screen.y - radius - padding,
    width: (radius + padding) * 2,
    height: (radius + padding) * 2,
  };
}

function resolveLabel(
  label: Omit<PlannedLabel, "x" | "y" | "box" | "align"> & { candidates: LabelCandidate[] },
  occupied: LabelBox[],
  viewport: Viewport,
  lineObstacles: LineObstacle[],
): PlannedLabel | null {
  const safeCandidates = label.candidates
    .map((candidate) => {
      const overlapPenalty = occupied.reduce((sum, box) => (
        sum + (boxesOverlap(candidate.box, box, 3) ? 1_000 : Math.max(0, 24 - boxDistance(candidate.box, box)))
      ), 0);
      const edgePenalty = (
        candidate.box.x <= 6
        || candidate.box.y <= 6
        || candidate.box.x + candidate.box.width >= viewport.width - 6
        || candidate.box.y + candidate.box.height >= viewport.height - 6
      ) ? 22 : 0;
      const linePenalty = lineObstacles.reduce((sum, obstacle) => (
        sum + (segmentIntersectsBox(obstacle.start, obstacle.end, candidate.box) ? 700 : 0)
      ), 0);
      return { ...candidate, score: candidate.score + overlapPenalty + edgePenalty + linePenalty };
    })
    .sort((left, right) => left.score - right.score);

  const best = safeCandidates[0];
  if (!best) return null;
  const hardOverlap = occupied.some((box) => boxesOverlap(best.box, box, 2));
  if (hardOverlap && label.priority <= 8) return null;
  return {
    id: label.id,
    text: label.text,
    x: best.x,
    y: best.y,
    box: best.box,
    align: best.align,
    fontSize: label.fontSize,
    weight: label.weight,
    fill: label.fill,
    background: label.background,
    priority: label.priority,
  };
}

function pointReferenceCounts(spec: Geometry2DSpec) {
  const counts = new Map<string, number>();
  const add = (id: string | undefined) => {
    if (!id) return;
    counts.set(id, (counts.get(id) ?? 0) + 1);
  };
  for (const shape of spec.shapes) {
    if (shape.kind === "segment" || shape.kind === "vector") {
      add(shape.from);
      add(shape.to);
    } else if (shape.kind === "circle") {
      add(shape.center);
      add(shape.through);
    } else if (shape.kind === "angle") {
      add(shape.vertex);
      add(shape.from);
      add(shape.to);
    } else if (shape.kind === "polygon") {
      shape.points.forEach(add);
    } else if (shape.kind === "orientedBox") {
      add(shape.center);
    }
  }
  return counts;
}

function pointPresentationRoles(spec: Geometry2DSpec) {
  const roles = new Map<string, { structural: number; semantic: number }>();
  const add = (id: string | undefined, role: "structural" | "semantic") => {
    if (!id) return;
    const current = roles.get(id) ?? { structural: 0, semantic: 0 };
    current[role] += 1;
    roles.set(id, current);
  };
  for (const shape of spec.shapes) {
    if (shape.kind === "vector") {
      add(shape.from, "structural");
      add(shape.to, "structural");
    } else if (shape.kind === "polygon") {
      shape.points.forEach((id) => add(id, "structural"));
    } else if (shape.kind === "orientedBox") {
      add(shape.center, "structural");
    } else if (shape.kind === "segment") {
      add(shape.from, "semantic");
      add(shape.to, "semantic");
    } else if (shape.kind === "circle") {
      add(shape.center, "semantic");
      add(shape.through, "semantic");
    } else if (shape.kind === "angle") {
      add(shape.vertex, "semantic");
      add(shape.from, "semantic");
      add(shape.to, "semantic");
    }
  }
  for (const readout of spec.readouts) {
    if (readout.kind === "point") {
      add(readout.pointID, "semantic");
    } else if (readout.kind === "distance") {
      add(readout.from, "semantic");
      add(readout.to, "semantic");
    } else if (readout.kind === "angle") {
      add(readout.vertex, "semantic");
      add(readout.from, "semantic");
      add(readout.to, "semantic");
    }
  }
  return roles;
}

function computePointVisuals(
  spec: Geometry2DSpec,
  scene: SceneState,
  projection: ScreenProjection,
  viewport: Viewport,
  focusID: string | null,
) {
  const references = pointReferenceCounts(spec);
  const presentationRoles = pointPresentationRoles(spec);
  const visuals = new Map<string, PointVisual>();
  const placed: LabelBox[] = [];
  const denseScene = scene.points.size > (viewport.width < 420 ? 9 : 14);
  const sorted = [...scene.points.values()].sort((left, right) => {
    const leftScore = (left.draggable ? 100 : 0) + (left.label ? 30 : 0) + (references.get(left.id) ?? 0);
    const rightScore = (right.draggable ? 100 : 0) + (right.label ? 30 : 0) + (references.get(right.id) ?? 0);
    return rightScore - leftScore;
  });

  for (const point of sorted) {
    const style = { ...defaultPointStyle, ...point.style };
    const active = focusID === point.id;
    const referenceCount = references.get(point.id) ?? 0;
    const presentationRole = presentationRoles.get(point.id);
    const structural = !point.draggable && (presentationRole?.structural ?? 0) > 0 && (presentationRole?.semantic ?? 0) === 0;
    const radius = active ? style.radius + 2 : structural ? Math.max(2.4, style.radius * 0.58) : style.radius;
    const box = pointAnchorBox(point, projection, radius);
    const overlaps = placed.some((item) => boxesOverlap(box, item, denseScene ? 4 : 2));
    const explicitlyStyled = point.style !== undefined;
    const visible = point.draggable || active || explicitlyStyled || (!structural && (Boolean(point.label) || (!overlaps && (!denseScene || referenceCount <= 2))));
    visuals.set(point.id, {
      visible,
      radius,
      opacity: point.draggable ? 0.98 : structural ? 0.46 : 0.82,
    });
    if (visible) placed.push(box);
  }
  return visuals;
}

function controlValueEquals(left: GeometryControlValue | undefined, right: GeometryControlValue) {
  return left === right || String(left) === String(right);
}

function shapeIsVisible(shape: GeometryShape, controlValues: Record<string, GeometryControlValue>) {
  return !shape.visibleWhen || controlValueEquals(controlValues[shape.visibleWhen.controlID], shape.visibleWhen.equals);
}

function shapeLabelPriority(shape: GeometryShape) {
  if (shape.kind === "vector" && shape.visibleWhen) return 9;
  if (shape.kind === "vector") return 7;
  if (shape.kind === "segment" || shape.kind === "angle") return 6;
  return 5;
}

function controlOptionLabel(control: GeometryControl, value: GeometryControlValue | undefined) {
  const match = control.options?.find((option) => controlValueEquals(value, option.value));
  return match?.label ?? (value === undefined ? "—" : String(value));
}

function readoutOptionLabel(readout: Extract<GeometryReadout, { kind: "state" }>, value: GeometryControlValue | undefined) {
  const match = readout.options.find((option) => controlValueEquals(value, option.value));
  return match?.label ?? (value === undefined ? "—" : String(value));
}

function makePolyline(points: GeometryCoordinate[], projection: ScreenProjection) {
  return points.map((point) => {
    const screen = worldToScreen(point, projection);
    return `${screen.x.toFixed(2)},${screen.y.toFixed(2)}`;
  }).join(" ");
}

function parallelLinearShapeOffsets(shapes: GeometryShape[]) {
  const groups = new Map<string, Array<Extract<GeometryShape, { kind: "segment" | "vector" }>>>();
  for (const shape of shapes) {
    if (shape.kind !== "segment" && shape.kind !== "vector") continue;
    const key = [shape.from, shape.to].sort().join("::");
    const group = groups.get(key) ?? [];
    group.push(shape);
    groups.set(key, group);
  }
  const offsets = new Map<string, number>();
  for (const group of groups.values()) {
    const center = (group.length - 1) / 2;
    group.forEach((shape, index) => offsets.set(shape.id, (index - center) * 10));
  }
  return offsets;
}

function shiftedLinearShapeEndpoints(
  shape: Extract<GeometryShape, { kind: "segment" | "vector" }>,
  scene: SceneState,
  projection: ScreenProjection,
  parallelOffset = 0,
) {
  const from = scene.points.get(shape.from);
  const to = scene.points.get(shape.to);
  if (!from || !to) return null;
  const start = worldToScreen(from, projection);
  const end = worldToScreen(to, projection);
  const length = Math.max(1, Math.hypot(end.x - start.x, end.y - start.y));
  const normal = { x: -(end.y - start.y) / length, y: (end.x - start.x) / length };
  return {
    start: { x: start.x + normal.x * parallelOffset, y: start.y + normal.y * parallelOffset },
    end: { x: end.x + normal.x * parallelOffset, y: end.y + normal.y * parallelOffset },
    normal,
  };
}

function circleRadiusForShape(shape: Extract<GeometryShape, { kind: "circle" }>, scene: SceneState) {
  const radiusOverride = scene.radiusOverrides[shape.id];
  if (radiusOverride !== undefined) return radiusOverride;
  if (shape.radius !== undefined) return shape.radius;
  const center = scene.points.get(shape.center);
  const through = shape.through ? scene.points.get(shape.through) : undefined;
  return center && through ? distance(center, through) : 0;
}

function shapeLabelPosition(shape: GeometryShape, scene: SceneState): GeometryCoordinate | null {
  if (shape.kind === "segment" || shape.kind === "vector") {
    const from = scene.points.get(shape.from);
    const to = scene.points.get(shape.to);
    return from && to
      ? { x: from.x + (to.x - from.x) * (shape.kind === "vector" ? 0.68 : 0.5), y: from.y + (to.y - from.y) * (shape.kind === "vector" ? 0.68 : 0.5) }
      : null;
  }
  if (shape.kind === "circle") {
    const center = scene.points.get(shape.center);
    const radius = circleRadiusForShape(shape, scene);
    return center ? { x: center.x + radius * 0.7, y: center.y + radius * 0.7 } : null;
  }
  if (shape.kind === "angle") return scene.points.get(shape.vertex) ?? null;
  if (shape.kind === "roundedBox") return { x: (shape.box.xMin + shape.box.xMax) / 2, y: shape.box.yMax };
  if (shape.kind === "polygon") {
    const points = shape.points.map((id) => scene.points.get(id)).filter((point): point is ScenePoint => Boolean(point));
    if (!points.length) return null;
    return {
      x: points.reduce((sum, point) => sum + point.x, 0) / points.length,
      y: points.reduce((sum, point) => sum + point.y, 0) / points.length,
    };
  }
  if (shape.kind === "orientedBox") return scene.points.get(shape.center) ?? null;
  const middle = shape.points[Math.floor(shape.points.length / 2)];
  return middle ?? null;
}

function renderConstraintTrack(point: ScenePoint, projection: ScreenProjection): ReactNode {
  const constraint = point.constraint;
  if (!constraint || constraint.kind === "free" || !("showTrack" in constraint) || !constraint.showTrack) return null;
  const stroke = "rgba(145, 83, 55, 0.28)";
  const common = {
    stroke,
    strokeWidth: 1.4,
    fill: "none",
    strokeDasharray: "4 5",
    pointerEvents: "none" as const,
  };

  if (constraint.kind === "axis") {
    const start = constraint.axis === "x"
      ? worldToScreen({ x: constraint.value, y: projection.bounds.yMin }, projection)
      : worldToScreen({ x: projection.bounds.xMin, y: constraint.value }, projection);
    const end = constraint.axis === "x"
      ? worldToScreen({ x: constraint.value, y: projection.bounds.yMax }, projection)
      : worldToScreen({ x: projection.bounds.xMax, y: constraint.value }, projection);
    return <line key={`track-${point.id}`} x1={start.x} y1={start.y} x2={end.x} y2={end.y} {...common} />;
  }

  if (constraint.kind === "lineSegment") {
    const start = worldToScreen(constraint.start, projection);
    const end = worldToScreen(constraint.end, projection);
    return <line key={`track-${point.id}`} x1={start.x} y1={start.y} x2={end.x} y2={end.y} {...common} />;
  }

  if (constraint.kind === "circle") {
    const center = worldToScreen(constraint.center, projection);
    const radius = worldLengthToScreen(constraint.radius, projection);
    return <ellipse key={`track-${point.id}`} cx={center.x} cy={center.y} rx={radius.x} ry={radius.y} {...common} />;
  }

  const rect = rectToScreen(constraint.box, projection);
  const radius = worldLengthToScreen(constraint.cornerRadius, projection);
  return (
    <rect
      key={`track-${point.id}`}
      x={rect.x}
      y={rect.y}
      width={rect.width}
      height={rect.height}
      rx={radius.x}
      ry={radius.y}
      {...common}
    />
  );
}

function shapeNode(shape: GeometryShape, scene: SceneState, projection: ScreenProjection, parallelOffset = 0) {
  const style = { ...defaultStyle, ...shape.style };
  const fill = (shape.kind === "polygon" || shape.kind === "orientedBox") && style.fill === "transparent"
    ? "rgba(114, 96, 69, 0.09)"
    : style.fill;
  const strokeWidth = shape.kind === "vector"
    ? Math.max(2.4, style.strokeWidth)
    : shape.kind === "polygon" || shape.kind === "orientedBox"
      ? Math.max(1.7, style.strokeWidth)
      : style.strokeWidth;
  const common = {
    stroke: style.stroke,
    strokeWidth,
    fill,
    opacity: shape.kind === "polygon" || shape.kind === "orientedBox" ? Math.max(style.opacity, 0.78) : style.opacity,
    strokeDasharray: lineDash(style),
    vectorEffect: "non-scaling-stroke" as const,
    pointerEvents: "none" as const,
  };

  if (shape.kind === "segment" || shape.kind === "vector") {
    const endpoints = shiftedLinearShapeEndpoints(shape, scene, projection, parallelOffset);
    if (!endpoints) return null;
    return (
      <line
        key={shape.id}
        x1={endpoints.start.x}
        y1={endpoints.start.y}
        x2={endpoints.end.x}
        y2={endpoints.end.y}
        markerEnd={shape.kind === "vector" ? "url(#weibei-geometry-arrowhead)" : undefined}
        strokeLinecap="round"
        {...common}
      />
    );
  }

  if (shape.kind === "circle") {
    const center = scene.points.get(shape.center);
    const radius = circleRadiusForShape(shape, scene);
    if (!center || radius <= 0) return null;
    const screen = worldToScreen(center, projection);
    const screenRadius = worldLengthToScreen(radius, projection);
    return <ellipse key={shape.id} cx={screen.x} cy={screen.y} rx={screenRadius.x} ry={screenRadius.y} {...common} />;
  }

  if (shape.kind === "angle") {
    const vertex = scene.points.get(shape.vertex);
    const from = scene.points.get(shape.from);
    const to = scene.points.get(shape.to);
    if (!vertex || !from || !to || samePoint(vertex, from) || samePoint(vertex, to)) return null;
    const fromAngle = Math.atan2(from.y - vertex.y, from.x - vertex.x);
    let delta = Math.atan2(to.y - vertex.y, to.x - vertex.x) - fromAngle;
    while (delta > Math.PI) delta -= Math.PI * 2;
    while (delta < -Math.PI) delta += Math.PI * 2;
    const samples = 18;
    const arcPoints = Array.from({ length: samples + 1 }, (_, index) => {
      const angle = fromAngle + (delta * index) / samples;
      return {
        x: vertex.x + Math.cos(angle) * shape.radius,
        y: vertex.y + Math.sin(angle) * shape.radius,
      };
    });
    return <polyline key={shape.id} points={makePolyline(arcPoints, projection)} {...common} fill="none" />;
  }

  if (shape.kind === "roundedBox") {
    const rect = rectToScreen(shape.box, projection);
    const radius = worldLengthToScreen(shape.cornerRadius, projection);
    return (
      <rect
        key={shape.id}
        x={rect.x}
        y={rect.y}
        width={rect.width}
        height={rect.height}
        rx={radius.x}
        ry={radius.y}
        {...common}
      />
    );
  }

  if (shape.kind === "polygon") {
    const points = shape.points.map((id) => scene.points.get(id)).filter((point): point is ScenePoint => Boolean(point));
    if (points.length < 3) return null;
    return <polygon key={shape.id} points={makePolyline(points, projection)} {...common} />;
  }

  if (shape.kind === "orientedBox") {
    const center = scene.points.get(shape.center);
    if (!center) return null;
    const angle = (shape.rotationDegrees * Math.PI) / 180;
    const cos = Math.cos(angle);
    const sin = Math.sin(angle);
    const halfWidth = shape.width / 2;
    const halfHeight = shape.height / 2;
    const corners = [
      { x: -halfWidth, y: -halfHeight },
      { x: halfWidth, y: -halfHeight },
      { x: halfWidth, y: halfHeight },
      { x: -halfWidth, y: halfHeight },
    ].map((corner) => ({
      x: center.x + corner.x * cos - corner.y * sin,
      y: center.y + corner.x * sin + corner.y * cos,
    }));
    return <polygon key={shape.id} points={makePolyline(corners, projection)} {...common} />;
  }

  return <polyline key={shape.id} points={makePolyline(shape.points, projection)} {...common} fill="none" />;
}

function gridNodes(spec: Geometry2DSpec, projection: ScreenProjection) {
  const nodes: ReactNode[] = [];
  const { gridStep } = spec.coordinateSpace;
  if (!spec.showGrid || !gridStep) return nodes;

  const xStart = Math.ceil(projection.bounds.xMin / gridStep) * gridStep;
  const yStart = Math.ceil(projection.bounds.yMin / gridStep) * gridStep;
  const maxLines = 90;
  let count = 0;
  for (let x = xStart; x <= projection.bounds.xMax + 1e-9 && count < maxLines; x += gridStep) {
    const a = worldToScreen({ x, y: projection.bounds.yMin }, projection);
    const b = worldToScreen({ x, y: projection.bounds.yMax }, projection);
    nodes.push(<line key={`gx-${x}`} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="rgba(84, 70, 58, 0.09)" strokeWidth={1} />);
    count += 1;
  }
  for (let y = yStart; y <= projection.bounds.yMax + 1e-9 && count < maxLines; y += gridStep) {
    const a = worldToScreen({ x: projection.bounds.xMin, y }, projection);
    const b = worldToScreen({ x: projection.bounds.xMax, y }, projection);
    nodes.push(<line key={`gy-${y}`} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="rgba(84, 70, 58, 0.09)" strokeWidth={1} />);
    count += 1;
  }
  return nodes;
}

function axisNodes(spec: Geometry2DSpec, projection: ScreenProjection) {
  if (!spec.showAxes) return [];
  const nodes: ReactNode[] = [];
  if (projection.bounds.yMin <= 0 && projection.bounds.yMax >= 0) {
    const a = worldToScreen({ x: projection.bounds.xMin, y: 0 }, projection);
    const b = worldToScreen({ x: projection.bounds.xMax, y: 0 }, projection);
    nodes.push(<line key="axis-x" x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="rgba(84, 70, 58, 0.3)" strokeWidth={1.2} />);
  }
  if (projection.bounds.xMin <= 0 && projection.bounds.xMax >= 0) {
    const a = worldToScreen({ x: 0, y: projection.bounds.yMin }, projection);
    const b = worldToScreen({ x: 0, y: projection.bounds.yMax }, projection);
    nodes.push(<line key="axis-y" x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="rgba(84, 70, 58, 0.3)" strokeWidth={1.2} />);
  }
  return nodes;
}

function readoutText(readout: GeometryReadout, scene: SceneState, controlValues: Record<string, GeometryControlValue>) {
  if (readout.kind === "state") {
    return `${readout.label}：${readoutOptionLabel(readout, controlValues[readout.controlID])}`;
  }

  if (readout.kind === "point") {
    const point = scene.points.get(readout.pointID);
    return point ? `${readout.label}：(${formatNumber(point.x)}, ${formatNumber(point.y)})` : `${readout.label}：—`;
  }

  const from = scene.points.get(readout.from);
  const to = scene.points.get(readout.to);
  if (!from || !to) return `${readout.label}：—`;

  if (readout.kind === "distance") {
    return `${readout.label}：${formatNumber(distance(from, to))} ${readout.unit}`;
  }

  const vertex = scene.points.get(readout.vertex);
  if (!vertex || samePoint(vertex, from) || samePoint(vertex, to)) return `${readout.label}：—`;
  const first = Math.atan2(from.y - vertex.y, from.x - vertex.x);
  const second = Math.atan2(to.y - vertex.y, to.x - vertex.x);
  let angle = Math.abs(second - first);
  if (angle > Math.PI) angle = Math.PI * 2 - angle;
  return `${readout.label}：${formatNumber((angle * 180) / Math.PI)}°`;
}

function GeometryFallback({ issue }: { issue: ReturnType<typeof createRendererIssue> }) {
  return (
    <div
      className="generation-error"
      role="alert"
      data-weibei-renderer-issue={issue.code}
      style={{
        padding: "12px",
        border: "1px dashed rgba(139, 20, 20, 0.35)",
        borderRadius: "8px",
        background: "rgba(255, 245, 245, 0.92)",
      }}
    >
      <strong>{issue.code === "unsafe_payload" ? "二维几何规格不安全" : "二维几何未渲染"}</strong>
      <p style={{ margin: "6px 0 0" }}>{issue.message}</p>
      {issue.details?.length ? <small>{issue.details.join("；")}</small> : null}
    </div>
  );
}

function Geometry2DMount({ compiled, context }: { compiled: GeometryCompiled; context: RendererLifecycleContext }) {
  const { spec } = compiled;
  const surfaceMetrics = useMemo(
    () => geometry2DSurfaceMetrics(spec, compiled.plan.qualityBudget.maxHeight),
    [compiled.plan.qualityBudget.maxHeight, spec],
  );
  const containerRef = useRef<HTMLDivElement>(null);
  const [viewport, setViewport] = useState<Viewport>(surfaceMetrics.initialViewport);
  const [controlValues, setControlValues] = useState<Record<string, GeometryControlValue>>(() => initialControlValues(spec.controls));
  const [pointOverrides, setPointOverrides] = useState<Record<string, GeometryCoordinate>>({});
  const [dragging, setDragging] = useState<DragState | null>(null);
  const [focusID, setFocusID] = useState<string | null>(null);
  const specKey = useMemo(() => JSON.stringify(spec), [spec]);
  const projection = useMemo(() => createProjection(spec, viewport), [spec, viewport.height, viewport.width]);
  const scene = useMemo(
    () => computeScene(spec, controlValues, pointOverrides),
    [controlValues, pointOverrides, spec],
  );

  useEffect(() => {
    setControlValues(initialControlValues(spec.controls));
    setPointOverrides({});
    setFocusID(null);
    setViewport(surfaceMetrics.initialViewport);
  }, [specKey, spec.controls, surfaceMetrics.initialViewport]);

  useEffect(() => {
    const element = containerRef.current;
    if (!element) return;
    const resize = (box: DOMRectReadOnly | DOMRect) => {
      setViewport({
        width: Math.max(280, Math.round(box.width)),
        height: Math.max(surfaceMetrics.minHeight, Math.round(box.height)),
      });
    };
    const observer = new ResizeObserver((entries) => {
      const box = entries[0]?.contentRect;
      if (box) resize(box);
    });
    observer.observe(element);
    resize(element.getBoundingClientRect());
    return () => observer.disconnect();
  }, [surfaceMetrics.minHeight]);

  useEffect(() => {
    const element = containerRef.current;
    if (!element) return;
    const verifyInteraction = () => {
      const firstControl = spec.controls[0];
      if (firstControl) {
        const current = controlValues[firstControl.id] ?? firstControl.value;
        const options = firstControl.options;
        const optionIndex = options?.findIndex((option) => controlValueEquals(option.value, current)) ?? -1;
        const next = options?.length
          ? options[(optionIndex + 1 + options.length) % options.length]!.value
          : typeof current === "number" && firstControl.step !== undefined && firstControl.minimum !== undefined && firstControl.maximum !== undefined
            ? current + firstControl.step <= firstControl.maximum
              ? current + firstControl.step
              : firstControl.minimum
            : firstControl.value;
        setControlValues((values) => ({ ...values, [firstControl.id]: next }));
        return;
      }

      const draggable = [...scene.points.values()].find((point) => point.draggable);
      if (!draggable) return;
      const moved = projectToConstraint({ x: draggable.x + 0.1, y: draggable.y + 0.1 }, draggable.constraint);
      setPointOverrides((overrides) => ({ ...overrides, [draggable.id]: moved }));
      setFocusID(draggable.id);
    };
    element.addEventListener("weibei:verify-interaction", verifyInteraction);
    return () => element.removeEventListener("weibei:verify-interaction", verifyInteraction);
  }, [controlValues, scene.points, spec.controls]);

  useEffect(() => {
    context.postMessage({
      type: "weibei:state",
      programID: compiled.programID,
      state: {
        renderer: GEOMETRY_2D_RENDERER,
        controls: controlValues,
        focusID,
        points: Object.fromEntries([...scene.points.values()].map((point) => [
          point.id,
          { x: roundValue(point.x), y: roundValue(point.y) },
        ])),
      },
    });
  }, [compiled.programID, context, controlValues, focusID, scene.points]);

  const pointFromEvent = useCallback((event: ReactPointerEvent<Element>) => {
    const element = containerRef.current;
    if (!element) return null;
    const rect = element.getBoundingClientRect();
    return screenToWorld({ x: event.clientX - rect.left, y: event.clientY - rect.top }, projection);
  }, [projection]);

  const startDrag = useCallback((event: ReactPointerEvent<SVGCircleElement>, point: ScenePoint) => {
    if (!point.draggable) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    setDragging({ pointID: point.id, pointerID: event.pointerId });
    setFocusID(point.id);
  }, []);

  const moveDrag = useCallback((event: ReactPointerEvent<SVGSVGElement>) => {
    if (!dragging) return;
    const point = scene.points.get(dragging.pointID);
    const world = pointFromEvent(event);
    if (!point || !world) return;
    const projected = projectToConstraint(world, point.constraint);
    setPointOverrides((overrides) => ({
      ...overrides,
      [dragging.pointID]: { x: roundValue(projected.x), y: roundValue(projected.y) },
    }));
  }, [dragging, pointFromEvent, scene.points]);

  const stopDrag = useCallback((event: ReactPointerEvent<SVGSVGElement>) => {
    if (dragging && event.pointerId === dragging.pointerID) setDragging(null);
  }, [dragging]);

  const changeControl = useCallback((control: GeometryControl, raw: string) => {
    const option = control.options?.find((item) => String(item.value) === raw);
    const next: GeometryControlValue = option ? option.value : Number(raw);
    setControlValues((values) => ({ ...values, [control.id]: next }));
    setPointOverrides((overrides) => {
      const copy = { ...overrides };
      for (const binding of control.bindings) {
        if (binding.kind !== "circleRadius") delete copy[binding.pointID];
      }
      return copy;
    });
  }, []);

  const resetExperiment = useCallback(() => {
    setControlValues(initialControlValues(spec.controls));
    setPointOverrides({});
    setFocusID(null);
  }, [spec.controls]);

  const trackNodes = useMemo(() => {
    return [...scene.points.values()].map((point) => renderConstraintTrack(point, projection));
  }, [projection, scene.points]);

  const visibleShapes = useMemo(() => {
    return spec.shapes.filter((shape) => shapeIsVisible(shape, controlValues));
  }, [controlValues, spec.shapes]);

  const linearShapeOffsets = useMemo(() => {
    return parallelLinearShapeOffsets(visibleShapes);
  }, [visibleShapes]);

  const shapeNodes = useMemo(() => {
    const layerRank: Record<GeometryShape["kind"], number> = {
      polygon: 10,
      orientedBox: 12,
      roundedBox: 14,
      circle: 16,
      locus: 20,
      segment: 24,
      vector: 28,
      angle: 32,
    };
    return [...visibleShapes]
      .sort((left, right) => layerRank[left.kind] - layerRank[right.kind])
      .map((shape) => shapeNode(shape, scene, projection, linearShapeOffsets.get(shape.id) ?? 0));
  }, [linearShapeOffsets, projection, scene, visibleShapes]);

  const pointVisuals = useMemo(() => {
    return computePointVisuals(spec, scene, projection, viewport, focusID);
  }, [focusID, projection, scene, spec, viewport]);

  const labelNodes = useMemo(() => {
    const presentationRoles = pointPresentationRoles(spec);
    const occupied: LabelBox[] = [...scene.points.values()]
      .filter((point) => pointVisuals.get(point.id)?.visible)
      .map((point) => pointAnchorBox(point, projection, pointVisuals.get(point.id)?.radius ?? defaultPointStyle.radius));
    const lineObstacles: LineObstacle[] = visibleShapes.flatMap((shape) => {
      if (shape.kind !== "segment" && shape.kind !== "vector") return [];
      const endpoints = shiftedLinearShapeEndpoints(shape, scene, projection, linearShapeOffsets.get(shape.id) ?? 0);
      return endpoints ? [{ start: endpoints.start, end: endpoints.end }] : [];
    });
    const planned: PlannedLabel[] = [];
    const candidates = (
      anchor: GeometryCoordinate,
      text: string,
      fontSize: number,
      priority: number,
      preferred: Array<[number, number, "start" | "middle" | "end", number]>,
    ) => preferred.map(([dx, dy, align, score]) => candidateForLabel(anchor, text, fontSize, dx, dy, viewport, align, score + (10 - priority)));

    const addResolvedLabel = (
      label: Omit<PlannedLabel, "x" | "y" | "box" | "align"> & { candidates: LabelCandidate[] },
    ) => {
      const resolved = resolveLabel(label, occupied, viewport, lineObstacles);
      if (!resolved) return;
      planned.push(resolved);
      occupied.push(resolved.box);
    };

    const orderedVisibleShapes = [...visibleShapes]
      .sort((left, right) => shapeLabelPriority(right) - shapeLabelPriority(left));
    for (const shape of orderedVisibleShapes) {
      if (!shape.label) continue;
      const position = shapeLabelPosition(shape, scene);
      if (!position) continue;
      let screen = worldToScreen(position, projection);
      const priority = shapeLabelPriority(shape);
      const vectorOffsets = (() => {
        if (shape.kind !== "segment" && shape.kind !== "vector") return null;
        const parallelOffset = linearShapeOffsets.get(shape.id) ?? 0;
        const endpoints = shiftedLinearShapeEndpoints(shape, scene, projection, parallelOffset);
        if (!endpoints) return null;
        screen = {
          x: screen.x + endpoints.normal.x * parallelOffset,
          y: screen.y + endpoints.normal.y * parallelOffset,
        };
        const { start, end, normal } = endpoints;
        const length = Math.max(1, Math.hypot(end.x - start.x, end.y - start.y));
        const tangent = { x: (end.x - start.x) / length, y: (end.y - start.y) / length };
        const normalDistance = viewport.width < 480 ? 26 : 22;
        const tangentDistance = viewport.width < 480 ? 20 : 16;
        const normalOffset = { x: normal.x * normalDistance, y: normal.y * normalDistance };
        const tangentOffset = { x: tangent.x * tangentDistance, y: tangent.y * tangentDistance };
        return [
          [normalOffset.x + tangentOffset.x, normalOffset.y + tangentOffset.y, "middle" as const, shape.kind === "vector" ? 0 : 2],
          [normalOffset.x - tangentOffset.x, normalOffset.y - tangentOffset.y, "middle" as const, shape.kind === "vector" ? 1 : 3],
          [-normalOffset.x + tangentOffset.x, -normalOffset.y + tangentOffset.y, "middle" as const, 4],
          [-normalOffset.x - tangentOffset.x, -normalOffset.y - tangentOffset.y, "middle" as const, 5],
          [normalOffset.x, normalOffset.y, "middle" as const, 6],
          [-normalOffset.x, -normalOffset.y, "middle" as const, 7],
          [0, -28, "middle" as const, 9],
          [0, 28, "middle" as const, 10],
        ] satisfies Array<[number, number, "middle", number]>;
      })();
      const shapeCandidates = vectorOffsets
        ? candidates(screen, shape.label, 11, priority, vectorOffsets)
        : candidates(screen, shape.label, 11, priority, [
          [0, -18, "middle", 0],
          [18, 0, "start", 3],
          [-18, 0, "end", 4],
          [0, 20, "middle", 6],
        ]);
      addResolvedLabel({
        id: `label-${shape.id}`,
        text: shape.label,
        fontSize: 11,
        weight: shape.kind === "vector" ? 650 : 560,
        fill: "rgba(43, 34, 25, 0.68)",
        background: "rgba(247, 239, 223, 0.62)",
        priority,
        candidates: shapeCandidates,
      });
    }

    for (const point of scene.points.values()) {
      if (!point.label) continue;
      const presentationRole = presentationRoles.get(point.id);
      const structural = !point.draggable && (presentationRole?.structural ?? 0) > 0 && (presentationRole?.semantic ?? 0) === 0;
      if (structural && focusID !== point.id && point.style === undefined) continue;
      const screen = worldToScreen(point, projection);
      const pointPriority = point.draggable ? 10 : focusID === point.id ? 9 : 8;
      addResolvedLabel({
        id: `point-label-${point.id}`,
        text: point.label,
        fontSize: viewport.width < 360 ? 11 : 12,
        weight: 650,
        fill: "rgba(43, 34, 25, 0.84)",
        background: "rgba(247, 239, 223, 0.78)",
        priority: pointPriority,
        candidates: candidates(screen, point.label, viewport.width < 360 ? 11 : 12, pointPriority, [
          [12, -13, "start", 0],
          [12, 13, "start", 2],
          [-12, -13, "end", 3],
          [-12, 13, "end", 4],
          [0, -23, "middle", 6],
          [0, 23, "middle", 7],
        ]),
      });
    }
    return planned.map((label) => (
      <g key={label.id} pointerEvents="none">
        <rect
          x={label.box.x}
          y={label.box.y}
          width={label.box.width}
          height={label.box.height}
          rx={5}
          fill={label.background}
          stroke="rgba(91, 73, 54, 0.1)"
        />
        <text
          x={label.x}
          y={label.y}
          fill={label.fill}
          fontSize={label.fontSize}
          fontWeight={label.weight}
          textAnchor={label.align}
        >
          {label.text}
        </text>
      </g>
    ));
  }, [focusID, linearShapeOffsets, pointVisuals, projection, scene, spec, viewport, visibleShapes]);

  const readouts = useMemo(() => spec.readouts.map((readout) => readoutText(readout, scene, controlValues)), [controlValues, scene, spec.readouts]);
  const focusedPoint = focusID ? scene.points.get(focusID) : null;

  return (
    <figure
      data-weibei-renderer={GEOMETRY_2D_RENDERER}
      style={{
        margin: 0,
        width: "100%",
        minWidth: 0,
        display: "grid",
        gap: "10px",
        color: "var(--weibei-fg, #1b1f23)",
        fontFamily: "inherit",
        background: "transparent",
      }}
    >
      <header style={{ display: "grid", gap: "4px" }}>
        <h3 style={{ margin: 0, fontSize: "15px", lineHeight: 1.35, fontWeight: 650 }}>{compiled.title}</h3>
      </header>

      <div
        ref={containerRef}
        data-weibei-control="geometry-2d-surface"
        data-weibei-control-id={compiled.programID}
        data-weibei-verify-event="weibei:verify-interaction"
        data-weibei-state={JSON.stringify({
          controls: controlValues,
          focusID,
          points: Object.fromEntries([...scene.points.values()].map((point) => [point.id, [roundValue(point.x), roundValue(point.y)]])),
        })}
        style={{
          width: "100%",
          aspectRatio: surfaceMetrics.cssAspectRatio,
          minHeight: surfaceMetrics.minHeight,
          maxHeight: surfaceMetrics.maxHeight,
          position: "relative",
          overflow: "hidden",
          border: "1px solid rgba(91, 73, 54, 0.16)",
          borderRadius: "10px",
          background: "transparent",
          touchAction: "none",
        }}
      >
        <svg
          viewBox={`0 0 ${viewport.width} ${viewport.height}`}
          width="100%"
          height="100%"
          role="img"
          aria-label={compiled.title}
          onPointerMove={moveDrag}
          onPointerUp={stopDrag}
          onPointerCancel={stopDrag}
          style={{ display: "block", width: "100%", height: "100%", background: "transparent" }}
        >
          <defs>
            <marker
              id="weibei-geometry-arrowhead"
              viewBox="0 0 10 10"
              refX="8.5"
              refY="5"
              markerWidth="6"
              markerHeight="6"
              orient="auto-start-reverse"
            >
              <polygon points="0,0 10,5 0,10" fill="context-stroke" />
            </marker>
          </defs>
          <rect x={projection.plot.left} y={projection.plot.top} width={projection.plot.width} height={projection.plot.height} fill="transparent" />
          <g>{gridNodes(spec, projection)}</g>
          <g>{axisNodes(spec, projection)}</g>
          <g>{trackNodes}</g>
          <g>{shapeNodes}</g>
          <g>{labelNodes}</g>
          <g>
            {[...scene.points.values()].map((point) => {
              const screen = worldToScreen(point, projection);
              const style = { ...defaultPointStyle, ...point.style };
              const visual = pointVisuals.get(point.id) ?? { visible: true, radius: style.radius, opacity: 0.84 };
              if (!visual.visible) return null;
              const active = focusID === point.id;
              return (
                <circle
                  key={point.id}
                  cx={screen.x}
                  cy={screen.y}
                  r={visual.radius}
                  fill={style.fill}
                  stroke={active ? "rgba(118, 45, 31, 0.95)" : style.stroke}
                  strokeWidth={active ? 2.4 : 1.6}
                  opacity={visual.opacity}
                  data-weibei-control={point.draggable ? "geometry-2d-drag-point" : undefined}
                  data-weibei-control-id={point.id}
                  onPointerDown={(event) => startDrag(event, point)}
                  onClick={() => setFocusID(point.id)}
                  style={{ cursor: point.draggable ? "grab" : "default" }}
                >
                  <title>{point.label ?? point.id}：({formatNumber(point.x)}, {formatNumber(point.y)})</title>
                </circle>
              );
            })}
          </g>
        </svg>
      </div>

      {spec.controls.length ? (
        <div
          aria-label="二维几何控件"
          style={{
            display: "grid",
            gridTemplateColumns: "repeat(auto-fit, minmax(210px, 1fr))",
            gap: "8px",
          }}
        >
          {spec.controls.map((control) => {
            const value = controlValues[control.id] ?? control.value;
            const useSegmented = control.presentation === "segmented" && control.options?.length && viewport.width >= 360;
            const useSelect = control.presentation === "segmented" && control.options?.length && viewport.width < 360;
            return (
              <div
                key={control.id}
                style={{
                  display: "grid",
                  gap: "5px",
                  padding: "8px 10px",
                  border: "1px solid rgba(91, 73, 54, 0.14)",
                  borderRadius: "8px",
                  background: "rgba(255, 255, 255, 0.24)",
                }}
              >
                <span style={{ display: "flex", justifyContent: "space-between", gap: "10px", fontSize: "12px" }}>
                  <strong>{control.label}</strong>
                  <span>{control.options?.length ? controlOptionLabel(control, value) : typeof value === "number" ? formatNumber(value) : String(value)}{control.unit ? ` ${control.unit}` : ""}</span>
                </span>
                {useSegmented ? (
                  <div role="group" aria-label={control.label} style={{ display: "flex", flexWrap: "wrap", gap: "6px" }}>
                    {control.options?.map((option) => {
                      const active = controlValueEquals(option.value, value);
                      return (
                        <button
                          key={String(option.value)}
                          type="button"
                          onClick={() => changeControl(control, String(option.value))}
                          data-weibei-control="geometry-2d-state-control"
                          data-weibei-control-id={control.id}
                          aria-pressed={active}
                          style={{
                            flex: "1 1 92px",
                            border: `1px solid ${active ? "rgba(142, 69, 48, 0.58)" : "rgba(91, 73, 54, 0.16)"}`,
                            borderRadius: "999px",
                            background: active ? "rgba(158, 78, 51, 0.16)" : "rgba(255, 255, 255, 0.28)",
                            color: "inherit",
                            padding: "5px 9px",
                            cursor: "pointer",
                            fontSize: "12px",
                          }}
                        >
                          {option.label}
                        </button>
                      );
                    })}
                  </div>
                ) : useSelect ? (
                  <select
                    value={String(value)}
                    onChange={(event) => changeControl(control, event.currentTarget.value)}
                    data-weibei-control="geometry-2d-state-control"
                    data-weibei-control-id={control.id}
                    style={{ minWidth: 0, borderRadius: "8px", border: "1px solid rgba(91, 73, 54, 0.18)", background: "rgba(255,255,255,0.34)", padding: "6px 8px" }}
                  >
                    {control.options?.map((option) => <option key={String(option.value)} value={String(option.value)}>{option.label}</option>)}
                  </select>
                ) : (
                  <input
                    type="range"
                    min={control.minimum}
                    max={control.maximum}
                    step={control.step}
                    value={typeof value === "number" ? value : 0}
                    onChange={(event) => changeControl(control, event.currentTarget.value)}
                  />
                )}
                <small style={{ color: "rgba(27, 31, 35, 0.58)" }}>调整后图形与读数同步变化</small>
              </div>
            );
          })}
        </div>
      ) : null}

      <div
        style={{
          display: "flex",
          flexWrap: "wrap",
          alignItems: "center",
          gap: "8px",
          fontSize: "12px",
          color: "rgba(27, 31, 35, 0.72)",
        }}
      >
        <button
          type="button"
          onClick={resetExperiment}
          style={{
            border: "1px solid rgba(91, 73, 54, 0.2)",
            borderRadius: "999px",
            background: "rgba(255, 255, 255, 0.34)",
            color: "inherit",
            padding: "5px 10px",
            cursor: "pointer",
          }}
        >
          重置实验
        </button>
        {focusedPoint ? (
          <span>当前点 {focusedPoint.label ?? focusedPoint.id}：({formatNumber(focusedPoint.x)}, {formatNumber(focusedPoint.y)})</span>
        ) : [...scene.points.values()].some((point) => point.draggable) ? (
          <span>拖拽可动点，或调节滑杆观察确定性变化。</span>
        ) : spec.controls.length ? (
          <span>切换条件，观察图形与读数如何同步变化。</span>
        ) : null}
      </div>

      {readouts.length ? (
        <figcaption style={{ display: "flex", flexWrap: "wrap", gap: "8px", fontSize: "12px", color: "rgba(27, 31, 35, 0.72)" }}>
          {readouts.map((item) => <span key={item}>{item}</span>)}
        </figcaption>
      ) : null}

      {spec.caption ? (
        <figcaption style={{ fontSize: "12px", lineHeight: 1.5, color: "rgba(27, 31, 35, 0.68)" }}>{spec.caption}</figcaption>
      ) : null}
    </figure>
  );
}

export const geometry2DRenderer: RichAnswerRenderer = {
  id: GEOMETRY_2D_RENDERER,
  version: "0.1.0",
  capabilities: {
    renderer: GEOMETRY_2D_RENDERER,
    version: "0.1.0",
    specVersions: [GEOMETRY_2D_SPEC_VERSION],
    displayName: "魏碑受限二维几何",
    data: ["points", "segments", "vectors", "polygons", "oriented-boxes", "circles", "angles", "rounded-constraint-tracks", "state-readouts", "deterministic-bindings"],
    interactions: ["point-drag", "constraint-projection", "coordinated-controls", "segmented-state", "state-visibility", "responsive-resize"],
    resources: ["local-svg-primitives", "no-network", "no-webgl"],
    maxNodes: 260,
    maxDataPoints: 1_200,
    fallback: ["structured_error", "simplified_component"],
  },
  validate(plan) {
    const parsed = parseGeometry2DSpec(plan);
    return parsed.ok ? { ok: true } : { ok: false, issue: parsed.issue };
  },
  compile(plan, context) {
    const parsed = parseGeometry2DSpec(plan);
    if (!parsed.ok) return { ok: false, issue: parsed.issue };
    return {
      ok: true,
      compiled: {
        renderer: GEOMETRY_2D_RENDERER,
        version: GEOMETRY_2D_SPEC_VERSION,
        plan,
        programID: context.program.id,
        title: parsed.spec.title,
        spec: parsed.spec,
      },
    };
  },
  mount(compiled, context) {
    return <Geometry2DMount compiled={compiled as GeometryCompiled} context={context} />;
  },
  update(compiled, _previous, context) {
    return <Geometry2DMount compiled={compiled as GeometryCompiled} context={context} />;
  },
  dispose() {
    return undefined;
  },
  fallback(issue) {
    return <GeometryFallback issue={issue} />;
  },
};
