import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  maxScene3DDataPoints,
  maxScene3DObjects,
  parseScene3DSpec,
  SCENE3D_RENDERER,
  SCENE3D_SPEC_VERSION,
  type Scene3DObject,
  type Scene3DReadout,
  type Scene3DSlice,
  type Scene3DSpec,
  type Scene3DState,
  type Scene3DVector,
} from "./scene-3d.self-check";
import {
  type CompiledRenderPlan,
  type RendererIssue,
  type RendererLifecycleContext,
  type RichAnswerRenderer,
} from "../renderer-registry";

type Bounds3D = {
  x: { min: number; max: number };
  y: { min: number; max: number };
  z: { min: number; max: number };
};

type CameraState = {
  yaw: number;
  pitch: number;
  distance: number;
  lookAt: Scene3DVector;
  fov: number;
  fitScale: number;
};

type ProjectionPoint = {
  x: number;
  y: number;
  depth: number;
  scale: number;
  visible: boolean;
};

type LayeredObject = Scene3DObject & {
  layerKey: string;
  finalColor: string;
  finalAlpha: number;
};

type LayeredSceneState = Omit<Scene3DState, "objects"> & {
  objects: LayeredObject[];
};

type MoleculeObject = Extract<Scene3DObject, { kind: "molecule" }>;
type MoleculeAtom = MoleculeObject["atoms"][number];
type MoleculeBond = MoleculeObject["bonds"][number];
type MoleculeElectronDomain = MoleculeObject["electronDomains"][number];
type MoleculeAngleMarker = MoleculeObject["angleMarkers"][number];
type LayeredMoleculeObject = LayeredObject & MoleculeObject;

type ProjectedAtom = {
  atom: MoleculeAtom;
  projected: ProjectionPoint;
  radius: number;
  color: string;
};

type LabelCandidate = {
  text: string;
  x: number;
  y: number;
  priority: number;
  color?: string;
  align?: "left" | "center";
};

type SceneFocus = {
  targetId: string;
  screenX: number;
  screenY: number;
  distance: number;
  label: string;
};

type Scene3DCompiledRenderPlan = CompiledRenderPlan & {
  spec: Scene3DSpec;
  objects: LayeredObject[];
  states: LayeredSceneState[];
  dataPointCount: number;
  layers: Array<{ id: string; title?: string; visibleDefault: boolean }>;
};

const colorPalette: Record<string, string> = {
  stone: "#766c5e",
  ink: "#2f2a25",
  cinnabar: "#a34b3f",
  moss: "#68784c",
  water: "#426f74",
  ochre: "#ad7a42",
  blue: "#3f72af",
  green: "#4f8a5b",
  red: "#bf4a4a",
  purple: "#7a4f9a",
  gray: "#6f6f6f",
  grey: "#6f6f6f",
  black: "#282522",
  white: "#ffffff",
};

const elementPalette: Record<string, string> = {
  H: "#f7f3ea",
  C: "#4d453d",
  N: "#506da6",
  O: "#a84f44",
  F: "#6b8f59",
  P: "#b0804e",
  S: "#c49a43",
  CL: "#6f8b57",
  BR: "#8d5d4b",
  I: "#6d5b82",
};

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function toRadians(value: number) {
  return (value * Math.PI) / 180;
}

function normalizeColor(value: string | undefined, fallback = "#6f665b") {
  if (!value) return fallback;
  const trimmed = value.trim();
  return colorPalette[trimmed.toLowerCase()] ?? trimmed;
}

function addVector(left: Scene3DVector, right: Scene3DVector): Scene3DVector {
  return [left[0] + right[0], left[1] + right[1], left[2] + right[2]];
}

function scaleVector(vector: Scene3DVector, scale: number): Scene3DVector {
  return [vector[0] * scale, vector[1] * scale, vector[2] * scale];
}

function normalizeVector(vector: Scene3DVector | undefined, fallback: Scene3DVector = [0, 1, 0]): Scene3DVector {
  if (!vector) return fallback;
  const length = Math.hypot(vector[0], vector[1], vector[2]);
  if (!Number.isFinite(length) || length < 1e-6) return fallback;
  return [vector[0] / length, vector[1] / length, vector[2] / length];
}

function alphaColor(color: string, alpha: number) {
  const normalized = normalizeColor(color);
  if (normalized.startsWith("#")) {
    const hex = normalized.slice(1);
    const pair = hex.length <= 4
      ? hex.slice(0, 3).split("").map((item) => item + item)
      : [hex.slice(0, 2), hex.slice(2, 4), hex.slice(4, 6)];
    const [red, green, blue] = pair.map((item) => Number.parseInt(item, 16));
    if ([red, green, blue].every(Number.isFinite)) return `rgba(${red}, ${green}, ${blue}, ${alpha})`;
  }
  if (normalized.startsWith("rgb(")) return normalized.replace("rgb(", "rgba(").replace(")", `, ${alpha})`);
  return normalized;
}

function axisIndex(axis: Scene3DSlice["axis"]) {
  if (axis === "x") return 0;
  if (axis === "y") return 1;
  return 2;
}

function scenePointPassesSlice(point: Scene3DVector, slice: Scene3DSlice | null, enabled: boolean, value: number) {
  if (!enabled || !slice) return true;
  return Math.abs(point[axisIndex(slice.axis)] - value) <= slice.thickness / 2;
}

function degToCompass(yaw: number) {
  const normalized = ((yaw % 360) + 360) % 360;
  if (normalized >= 315 || normalized < 45) return "东向";
  if (normalized >= 45 && normalized < 135) return "南向";
  if (normalized >= 135 && normalized < 225) return "西向";
  return "北向";
}

function computeSceneBounds(spec: Scene3DSpec, objects: Scene3DObject[] = spec.objects): Bounds3D {
  if (spec.bounds) return spec.bounds;

  let hasMolecule = false;
  const bounds = {
    x: { min: Number.POSITIVE_INFINITY, max: Number.NEGATIVE_INFINITY },
    y: { min: Number.POSITIVE_INFINITY, max: Number.NEGATIVE_INFINITY },
    z: { min: Number.POSITIVE_INFINITY, max: Number.NEGATIVE_INFINITY },
  };

  const mergePoint = (point: Scene3DVector) => {
    bounds.x.min = Math.min(bounds.x.min, point[0]);
    bounds.x.max = Math.max(bounds.x.max, point[0]);
    bounds.y.min = Math.min(bounds.y.min, point[1]);
    bounds.y.max = Math.max(bounds.y.max, point[1]);
    bounds.z.min = Math.min(bounds.z.min, point[2]);
    bounds.z.max = Math.max(bounds.z.max, point[2]);
  };

  for (const object of objects) {
    if (object.kind === "point") {
      mergePoint(object.position);
    } else if (object.kind === "polyline") {
      object.points.forEach(mergePoint);
    } else if (object.kind === "wireframe-grid") {
      mergePoint([object.xRange.min, object.y, object.zRange.min]);
      mergePoint([object.xRange.max, object.y, object.zRange.max]);
    } else if (object.kind === "molecule") {
      hasMolecule = true;
      object.atoms.forEach((atom) => mergePoint(atom.position));
      object.electronDomains.forEach((domain) => mergePoint(resolveElectronDomainPosition(object, domain)));
    } else {
      const rows = object.yValues.length;
      const cols = object.yValues[0]?.length ?? 0;
      for (let row = 0; row < rows; row += 1) {
        for (let col = 0; col < cols; col += 1) {
          mergePoint(surfacePoint(object, row, col));
        }
      }
    }
  }

  const padded = padDegenerateBounds(bounds);
  return hasMolecule ? expandBounds(padded, 0.22) : padded;
}

function padDegenerateBounds(bounds: Bounds3D): Bounds3D {
  const padRange = (range: { min: number; max: number }) => {
    if (!Number.isFinite(range.min) || !Number.isFinite(range.max)) return { min: -1, max: 1 };
    if (range.min === range.max) return { min: range.min - 1, max: range.max + 1 };
    const pad = Math.max(0.08, (range.max - range.min) * 0.08);
    return { min: range.min - pad, max: range.max + pad };
  };

  return {
    x: padRange(bounds.x),
    y: padRange(bounds.y),
    z: padRange(bounds.z),
  };
}

function expandBounds(bounds: Bounds3D, ratio: number): Bounds3D {
  const expandRange = (range: { min: number; max: number }) => {
    const pad = Math.max(0.18, (range.max - range.min) * ratio);
    return { min: range.min - pad, max: range.max + pad };
  };
  return {
    x: expandRange(bounds.x),
    y: expandRange(bounds.y),
    z: expandRange(bounds.z),
  };
}

function surfacePoint(object: Extract<Scene3DObject, { kind: "surface" }>, row: number, col: number): Scene3DVector {
  const rowCount = object.yValues.length;
  const colCount = object.yValues[0]?.length ?? 1;
  return [
    object.xRange.min + (object.xRange.max - object.xRange.min) * (col / Math.max(1, colCount - 1)),
    object.yValues[row]![col]!,
    object.zRange.min + (object.zRange.max - object.zRange.min) * (row / Math.max(1, rowCount - 1)),
  ];
}

function projectPoint(
  point: Scene3DVector,
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
): ProjectionPoint {
  const span = Math.max(
    bounds.x.max - bounds.x.min,
    bounds.y.max - bounds.y.min,
    bounds.z.max - bounds.z.min,
    1,
  );
  const baseScale = (Math.min(width, height) * 0.46) / span;
  const fovScale = 58 / camera.fov;
  const translatedX = point[0] - camera.lookAt[0];
  const translatedY = point[1] - camera.lookAt[1];
  const translatedZ = point[2] - camera.lookAt[2];

  const yaw = toRadians(camera.yaw);
  const pitch = toRadians(camera.pitch);
  const sinYaw = Math.sin(yaw);
  const cosYaw = Math.cos(yaw);
  const sinPitch = Math.sin(pitch);
  const cosPitch = Math.cos(pitch);

  const yawX = translatedX * cosYaw + translatedZ * sinYaw;
  const yawZ = -translatedX * sinYaw + translatedZ * cosYaw;
  const pitchY = translatedY * cosPitch - yawZ * sinPitch;
  const pitchZ = translatedY * sinPitch + yawZ * cosPitch;
  const perspective = camera.distance / Math.max(0.18, camera.distance + pitchZ);
  const scale = baseScale * fovScale * perspective * camera.fitScale;

  return {
    x: width / 2 + yawX * scale,
    y: height / 2 - pitchY * scale,
    depth: pitchZ,
    scale,
    visible: Number.isFinite(scale) && perspective > 0.02,
  };
}

function objectDepth(object: LayeredObject, camera: CameraState, bounds: Bounds3D, width: number, height: number) {
  const points = objectSamplePoints(object);
  if (!points.length) return 0;
  return points.reduce((sum, point) => sum + projectPoint(point, camera, bounds, width, height).depth, 0) / points.length;
}

function objectSamplePoints(object: Scene3DObject): Scene3DVector[] {
  if (object.kind === "point") return [object.position];
  if (object.kind === "polyline") return object.points;
  if (object.kind === "molecule") {
    return [
      ...object.atoms.map((atom) => atom.position),
      ...object.electronDomains.map((domain) => resolveElectronDomainPosition(object, domain)),
    ];
  }
  if (object.kind === "wireframe-grid") {
    return [
      [object.xRange.min, object.y, object.zRange.min],
      [object.xRange.max, object.y, object.zRange.max],
    ];
  }
  const lastRow = object.yValues.length - 1;
  const lastCol = (object.yValues[0]?.length ?? 1) - 1;
  return [
    surfacePoint(object, 0, 0),
    surfacePoint(object, 0, lastCol),
    surfacePoint(object, lastRow, 0),
    surfacePoint(object, lastRow, lastCol),
  ];
}

function computeProjectionFitScale(
  objects: Scene3DObject[],
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
) {
  if (!objects.length || !objects.every((object) => object.kind === "molecule")) return 1;
  const projected = objects
    .flatMap(objectSamplePoints)
    .map((point) => projectPoint(point, { ...camera, fitScale: 1 }, bounds, width, height))
    .filter((point) => point.visible);
  if (projected.length < 2) return 1;

  const minX = Math.min(...projected.map((point) => point.x));
  const maxX = Math.max(...projected.map((point) => point.x));
  const minY = Math.min(...projected.map((point) => point.y));
  const maxY = Math.max(...projected.map((point) => point.y));
  const projectedWidth = Math.max(1, maxX - minX);
  const projectedHeight = Math.max(1, maxY - minY);
  const targetWidth = width * 0.68;
  const targetHeight = height * 0.64;
  return clamp(Math.min(targetWidth / projectedWidth, targetHeight / projectedHeight), 1, 1.85);
}

function atomDisplayText(atom: MoleculeAtom) {
  const base = atom.label ?? atom.element ?? atom.id;
  return atom.charge ? `${base}${atom.charge}` : base;
}

function atomDisplayColor(atom: MoleculeAtom, fallback: string) {
  const elementKey = atom.element?.trim().toUpperCase();
  return normalizeColor(atom.color, elementKey ? elementPalette[elementKey] ?? fallback : fallback);
}

function resolveElectronDomainPosition(object: MoleculeObject, domain: MoleculeElectronDomain): Scene3DVector {
  if (domain.position) return domain.position;
  const atom = object.atoms.find((item) => item.id === domain.atom);
  if (!atom) return [0, 0, 0];
  return addVector(atom.position, scaleVector(normalizeVector(domain.direction), domain.distance));
}

function screenDistance(left: ProjectionPoint, right: ProjectionPoint) {
  return Math.hypot(left.x - right.x, left.y - right.y);
}

function shortenedBondEndpoints(from: ProjectedAtom, to: ProjectedAtom) {
  const length = Math.max(1, screenDistance(from.projected, to.projected));
  const unitX = (to.projected.x - from.projected.x) / length;
  const unitY = (to.projected.y - from.projected.y) / length;
  const startPad = Math.min(length * 0.32, from.radius * 0.78);
  const endPad = Math.min(length * 0.32, to.radius * 0.78);
  return {
    start: { x: from.projected.x + unitX * startPad, y: from.projected.y + unitY * startPad },
    end: { x: to.projected.x - unitX * endPad, y: to.projected.y - unitY * endPad },
    normal: { x: -unitY, y: unitX },
    length,
  };
}

function drawMoleculeBond(
  context: CanvasRenderingContext2D,
  bond: MoleculeBond,
  from: ProjectedAtom,
  to: ProjectedAtom,
  fallbackColor: string,
  labels: LabelCandidate[],
) {
  if (!from.projected.visible || !to.projected.visible) return;
  const endpoints = shortenedBondEndpoints(from, to);
  if (endpoints.length < 4) return;
  const color = normalizeColor(bond.color, alphaColor(fallbackColor, 0.78));
  const lineWidth = clamp((bond.radius ?? 0.035) * Math.max(from.projected.scale, to.projected.scale), 2, 7);
  const offsets = bond.order === 1 ? [0] : bond.order === 2 ? [-lineWidth * 0.85, lineWidth * 0.85] : [-lineWidth * 1.08, 0, lineWidth * 1.08];

  context.save();
  context.strokeStyle = color;
  context.fillStyle = color;
  context.lineCap = "round";
  context.lineJoin = "round";
  context.lineWidth = lineWidth;
  if (bond.style === "dashed") context.setLineDash([5, 5]);
  if (bond.style === "wedge") {
    const wedgeWidth = Math.max(8, lineWidth * 3.2);
    context.beginPath();
    context.moveTo(endpoints.start.x, endpoints.start.y);
    context.lineTo(
      endpoints.end.x + endpoints.normal.x * wedgeWidth,
      endpoints.end.y + endpoints.normal.y * wedgeWidth,
    );
    context.lineTo(
      endpoints.end.x - endpoints.normal.x * wedgeWidth,
      endpoints.end.y - endpoints.normal.y * wedgeWidth,
    );
    context.closePath();
    context.globalAlpha = 0.72;
    context.fill();
  } else {
    for (const offset of offsets) {
      context.beginPath();
      context.moveTo(
        endpoints.start.x + endpoints.normal.x * offset,
        endpoints.start.y + endpoints.normal.y * offset,
      );
      context.lineTo(
        endpoints.end.x + endpoints.normal.x * offset,
        endpoints.end.y + endpoints.normal.y * offset,
      );
      context.stroke();
    }
  }
  context.restore();

  if (bond.label) {
    labels.push({
      text: bond.label,
      x: (endpoints.start.x + endpoints.end.x) / 2 + endpoints.normal.x * 12,
      y: (endpoints.start.y + endpoints.end.y) / 2 + endpoints.normal.y * 12,
      priority: 1.6,
      color,
      align: "center",
    });
  }
}

function drawMoleculeAtom(context: CanvasRenderingContext2D, item: ProjectedAtom) {
  const { atom, projected, radius, color } = item;
  if (!projected.visible) return;
  context.save();
  const highlightX = projected.x - radius * 0.34;
  const highlightY = projected.y - radius * 0.42;
  const gradient = context.createRadialGradient(highlightX, highlightY, radius * 0.12, projected.x, projected.y, radius);
  gradient.addColorStop(0, alphaColor("#ffffff", atom.element?.toUpperCase() === "H" ? 0.95 : 0.72));
  gradient.addColorStop(0.48, alphaColor(color, 0.9));
  gradient.addColorStop(1, alphaColor(color, 0.56));
  context.fillStyle = gradient;
  context.strokeStyle = atom.role === "central" ? "rgba(92, 61, 45, 0.82)" : "rgba(58, 49, 40, 0.48)";
  context.lineWidth = atom.role === "central" ? 1.6 : 1;
  context.beginPath();
  context.arc(projected.x, projected.y, radius, 0, Math.PI * 2);
  context.fill();
  context.stroke();
  const symbol = atom.element?.trim();
  if (symbol && radius >= 6) {
    context.fillStyle = atom.element?.toUpperCase() === "H" ? "rgba(52, 45, 38, 0.86)" : "rgba(255, 252, 246, 0.94)";
    context.font = `600 ${clamp(radius * 0.92, 8, 14)}px ui-serif, Georgia, serif`;
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillText(symbol, projected.x, projected.y + 0.5);
  }
  context.restore();
}

function drawElectronDomain(
  context: CanvasRenderingContext2D,
  object: MoleculeObject,
  domain: MoleculeElectronDomain,
  atomsById: Map<string, ProjectedAtom>,
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
  labels: LabelCandidate[],
) {
  if (!object.showElectronDomains || domain.kind === "empty") return;
  const anchor = atomsById.get(domain.atom);
  if (!anchor?.projected.visible) return;
  const position = resolveElectronDomainPosition(object, domain);
  const projected = projectPoint(position, camera, bounds, width, height);
  if (!projected.visible) return;
  const color = normalizeColor(domain.color, domain.kind === "lonePair" ? "#426f74" : "#9a7a54");
  const size = clamp(domain.radius * Math.max(34, projected.scale), 5, width < 360 ? 13 : 17);
  const connectorAlpha = domain.kind === "lonePair" ? 0.24 : 0.14;

  context.save();
  context.strokeStyle = alphaColor(color, connectorAlpha);
  context.lineWidth = 1;
  context.setLineDash([3, 4]);
  drawLine(context, anchor.projected, projected);
  context.setLineDash([]);

  context.fillStyle = alphaColor(color, 0.12 + domain.alpha * 0.18);
  context.strokeStyle = alphaColor(color, 0.5);
  context.lineWidth = 1.1;
  context.beginPath();
  context.ellipse(projected.x, projected.y, size * 1.32, size * 0.72, -0.25, 0, Math.PI * 2);
  context.fill();
  context.stroke();

  if (domain.kind === "lonePair") {
    context.fillStyle = color;
    context.beginPath();
    context.arc(projected.x - size * 0.34, projected.y, Math.max(2, size * 0.18), 0, Math.PI * 2);
    context.arc(projected.x + size * 0.34, projected.y, Math.max(2, size * 0.18), 0, Math.PI * 2);
    context.fill();
  }
  context.restore();

  if (domain.label) {
    labels.push({
      text: domain.label,
      x: projected.x,
      y: projected.y - size - 8,
      priority: 2.3,
      color,
      align: "center",
    });
  }
}

function drawAngleMarker(
  context: CanvasRenderingContext2D,
  marker: MoleculeAngleMarker,
  atomsById: Map<string, ProjectedAtom>,
  labels: LabelCandidate[],
) {
  const from = atomsById.get(marker.from);
  const via = atomsById.get(marker.via);
  const to = atomsById.get(marker.to);
  if (!from?.projected.visible || !via?.projected.visible || !to?.projected.visible) return;
  const startAngle = Math.atan2(from.projected.y - via.projected.y, from.projected.x - via.projected.x);
  const endAngle = Math.atan2(to.projected.y - via.projected.y, to.projected.x - via.projected.x);
  let delta = endAngle - startAngle;
  while (delta > Math.PI) delta -= Math.PI * 2;
  while (delta < -Math.PI) delta += Math.PI * 2;
  const radius = Math.max(via.radius + 14, 24);
  const color = normalizeColor(marker.color, "#a34b3f");

  context.save();
  context.strokeStyle = alphaColor(color, 0.72);
  context.lineWidth = 1.4;
  context.beginPath();
  context.arc(via.projected.x, via.projected.y, radius, startAngle, startAngle + delta, delta < 0);
  context.stroke();
  context.restore();

  const middleAngle = startAngle + delta / 2;
  labels.push({
    text: marker.label ?? (marker.degrees ? `${marker.degrees.toFixed(marker.degrees % 1 ? 1 : 0)}°` : marker.id),
    x: via.projected.x + Math.cos(middleAngle) * (radius + 18),
    y: via.projected.y + Math.sin(middleAngle) * (radius + 18),
    priority: 2.2,
    color,
    align: "center",
  });
}

function labelsOverlap(left: { x: number; y: number; width: number; height: number }, right: { x: number; y: number; width: number; height: number }) {
  return !(
    left.x + left.width < right.x
    || right.x + right.width < left.x
    || left.y + left.height < right.y
    || right.y + right.height < left.y
  );
}

function drawLabelCandidates(
  context: CanvasRenderingContext2D,
  candidates: LabelCandidate[],
  width: number,
  height: number,
) {
  const placed: Array<{ x: number; y: number; width: number; height: number }> = [];
  const maxLabels = width < 360 ? 9 : 16;
  const sorted = [...candidates].sort((left, right) => right.priority - left.priority);

  context.save();
  context.textBaseline = "middle";
  context.font = `${width < 360 ? 11 : 12}px ui-serif, Georgia, serif`;
  for (const candidate of sorted) {
    if (placed.length >= maxLabels) break;
    const measuredWidth = Math.min(width < 360 ? 72 : 110, context.measureText(candidate.text).width + 14);
    const labelHeight = width < 360 ? 20 : 22;
    const offsetOptions: Array<readonly [number, number]> = candidate.align === "center"
      ? [[-measuredWidth / 2, -labelHeight / 2], [-measuredWidth / 2, -labelHeight - 6], [-measuredWidth / 2, 6]]
      : [[8, -12], [8, 8], [-measuredWidth - 8, -12], [-measuredWidth - 8, 8]];
    let target: { x: number; y: number; width: number; height: number } | null = null;
    for (const [offsetX, offsetY] of offsetOptions) {
      const box = {
        x: clamp(candidate.x + offsetX, 4, Math.max(4, width - measuredWidth - 4)),
        y: clamp(candidate.y + offsetY, 4, Math.max(4, height - labelHeight - 4)),
        width: measuredWidth,
        height: labelHeight,
      };
      if (!placed.some((item) => labelsOverlap(item, box))) {
        target = box;
        break;
      }
    }
    if (!target) continue;
    placed.push(target);
    context.fillStyle = "rgba(250, 246, 236, 0.84)";
    context.strokeStyle = alphaColor(candidate.color ?? "#766c5e", 0.28);
    context.lineWidth = 1;
    context.beginPath();
    context.roundRect(target.x, target.y, target.width, target.height, 7);
    context.fill();
    context.stroke();
    context.fillStyle = alphaColor(candidate.color ?? "#3b332b", 0.9);
    context.fillText(candidate.text, target.x + 7, target.y + target.height / 2, target.width - 10);
  }
  context.restore();
}

function drawMoleculeObject(
  context: CanvasRenderingContext2D,
  object: LayeredMoleculeObject,
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
  slice: Scene3DSlice | null,
  sliceEnabled: boolean,
  sliceValue: number,
) {
  const labels: LabelCandidate[] = [];
  const atomsById = new Map<string, ProjectedAtom>();
  for (const atom of object.atoms) {
    if (!scenePointPassesSlice(atom.position, slice, sliceEnabled, sliceValue)) continue;
    const projected = projectPoint(atom.position, camera, bounds, width, height);
    if (!projected.visible) continue;
    const radius = clamp(atom.radius * Math.max(30, projected.scale), width < 360 ? 4.8 : 5.6, width < 360 ? 14 : 19);
    atomsById.set(atom.id, {
      atom,
      projected,
      radius: atom.role === "central" ? radius * 1.12 : radius,
      color: atomDisplayColor(atom, object.finalColor),
    });
  }

  const bondItems = object.bonds
    .map((bond) => ({ bond, from: atomsById.get(bond.from), to: atomsById.get(bond.to) }))
    .filter((item): item is { bond: MoleculeBond; from: ProjectedAtom; to: ProjectedAtom } => Boolean(item.from && item.to))
    .sort((left, right) => ((right.from.projected.depth + right.to.projected.depth) - (left.from.projected.depth + left.to.projected.depth)));
  for (const item of bondItems) drawMoleculeBond(context, item.bond, item.from, item.to, object.finalColor, object.showBondLabels ? labels : []);

  for (const domain of object.electronDomains) {
    const domainLabels = domain.kind === "lonePair" || object.electronDomains.length <= 2 ? labels : [];
    drawElectronDomain(context, object, domain, atomsById, camera, bounds, width, height, domainLabels);
  }

  for (const marker of object.angleMarkers) {
    drawAngleMarker(context, marker, atomsById, labels);
  }

  const atomItems = [...atomsById.values()].sort((left, right) => right.projected.depth - left.projected.depth);
  for (const item of atomItems) {
    drawMoleculeAtom(context, item);
    if (object.showAtomLabels) {
      const atomText = atomDisplayText(item.atom);
      const symbol = item.atom.element?.trim();
      if (item.atom.role === "central" || !symbol || atomText !== symbol) {
        labels.push({
          text: atomText,
          x: item.projected.x + item.radius,
          y: item.projected.y - item.radius,
          priority: item.atom.role === "central" ? 3 : 1.8,
          color: item.color,
        });
      }
    }
  }

  drawLabelCandidates(context, labels, width, height);
}

function drawLine(
  context: CanvasRenderingContext2D,
  from: ProjectionPoint,
  to: ProjectionPoint,
) {
  if (!from.visible || !to.visible) return;
  context.beginPath();
  context.moveTo(from.x, from.y);
  context.lineTo(to.x, to.y);
  context.stroke();
}

function drawCoordinateFrame(
  context: CanvasRenderingContext2D,
  spec: Scene3DSpec,
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
) {
  context.save();
  context.strokeStyle = "rgba(89, 76, 62, 0.35)";
  context.fillStyle = "rgba(58, 48, 39, 0.76)";
  context.lineWidth = 1.2;
  context.font = "12px ui-serif, Georgia, serif";

  const origin: Scene3DVector = [
    clamp(0, bounds.x.min, bounds.x.max),
    clamp(0, bounds.y.min, bounds.y.max),
    clamp(0, bounds.z.min, bounds.z.max),
  ];
  const axes: Array<{ point: Scene3DVector; label: string }> = [
    { point: [bounds.x.max, origin[1], origin[2]], label: spec.coordinateUnits.x },
    { point: [origin[0], bounds.y.max, origin[2]], label: spec.coordinateUnits.y },
    { point: [origin[0], origin[1], bounds.z.max], label: spec.coordinateUnits.z },
  ];
  const projectedOrigin = projectPoint(origin, camera, bounds, width, height);
  for (const axis of axes) {
    const projected = projectPoint(axis.point, camera, bounds, width, height);
    drawLine(context, projectedOrigin, projected);
    if (projected.visible) context.fillText(axis.label, projected.x + 6, projected.y - 4);
  }
  context.restore();
}

function drawReferenceGrid(
  context: CanvasRenderingContext2D,
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
) {
  context.save();
  context.strokeStyle = "rgba(121, 104, 83, 0.12)";
  context.lineWidth = 1;

  const y = bounds.y.min;
  for (let step = 0; step <= 4; step += 1) {
    const x = bounds.x.min + ((bounds.x.max - bounds.x.min) * step) / 4;
    drawLine(
      context,
      projectPoint([x, y, bounds.z.min], camera, bounds, width, height),
      projectPoint([x, y, bounds.z.max], camera, bounds, width, height),
    );
    const z = bounds.z.min + ((bounds.z.max - bounds.z.min) * step) / 4;
    drawLine(
      context,
      projectPoint([bounds.x.min, y, z], camera, bounds, width, height),
      projectPoint([bounds.x.max, y, z], camera, bounds, width, height),
    );
  }
  context.restore();
}

function drawSlicePlane(
  context: CanvasRenderingContext2D,
  slice: Scene3DSlice,
  value: number,
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
) {
  const color = normalizeColor(slice.color, "#b36b4c");
  const corners: Scene3DVector[] = slice.axis === "x"
    ? [[value, bounds.y.min, bounds.z.min], [value, bounds.y.min, bounds.z.max], [value, bounds.y.max, bounds.z.max], [value, bounds.y.max, bounds.z.min]]
    : slice.axis === "y"
      ? [[bounds.x.min, value, bounds.z.min], [bounds.x.max, value, bounds.z.min], [bounds.x.max, value, bounds.z.max], [bounds.x.min, value, bounds.z.max]]
      : [[bounds.x.min, bounds.y.min, value], [bounds.x.max, bounds.y.min, value], [bounds.x.max, bounds.y.max, value], [bounds.x.min, bounds.y.max, value]];
  const projected = corners.map((point) => projectPoint(point, camera, bounds, width, height));
  if (!projected.every((point) => point.visible)) return;

  context.save();
  context.fillStyle = alphaColor(color, 0.08);
  context.strokeStyle = alphaColor(color, 0.45);
  context.lineWidth = 1.4;
  context.beginPath();
  projected.forEach((point, index) => {
    if (index === 0) context.moveTo(point.x, point.y);
    else context.lineTo(point.x, point.y);
  });
  context.closePath();
  context.fill();
  context.stroke();
  context.restore();
}

function drawSceneObject(
  context: CanvasRenderingContext2D,
  object: LayeredObject,
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
  slice: Scene3DSlice | null,
  sliceEnabled: boolean,
  sliceValue: number,
) {
  context.save();
  context.strokeStyle = object.finalColor;
  context.fillStyle = object.finalColor;
  context.globalAlpha = object.finalAlpha;
  context.lineCap = "round";
  context.lineJoin = "round";

  if (object.kind === "molecule") {
    drawMoleculeObject(context, object, camera, bounds, width, height, slice, sliceEnabled, sliceValue);
    context.restore();
    return;
  }

  if (object.kind === "point") {
    if (!scenePointPassesSlice(object.position, slice, sliceEnabled, sliceValue)) {
      context.restore();
      return;
    }
    const projected = projectPoint(object.position, camera, bounds, width, height);
    if (projected.visible) {
      const radius = Math.max(2.8, object.radius * Math.max(24, projected.scale));
      context.beginPath();
      context.arc(projected.x, projected.y, radius, 0, Math.PI * 2);
      context.fill();
      if (object.label) {
        context.globalAlpha = 0.92;
        context.font = "12px ui-serif, Georgia, serif";
        context.fillText(object.label, projected.x + radius + 5, projected.y - radius - 2);
      }
    }
    context.restore();
    return;
  }

  if (object.kind === "polyline") {
    context.lineWidth = object.strokeWidth;
    let previous: ProjectionPoint | null = null;
    let first: ProjectionPoint | null = null;
    let last: ProjectionPoint | null = null;
    for (const point of object.points) {
      if (!scenePointPassesSlice(point, slice, sliceEnabled, sliceValue)) {
        previous = null;
        continue;
      }
      const projected = projectPoint(point, camera, bounds, width, height);
      if (!projected.visible) {
        previous = null;
        continue;
      }
      if (!first) first = projected;
      if (previous) drawLine(context, previous, projected);
      previous = projected;
      last = projected;
    }
    if (object.closed && first && last) drawLine(context, last, first);
    context.restore();
    return;
  }

  if (object.kind === "wireframe-grid") {
    context.lineWidth = 1.2;
    const xSteps = Math.max(2, Math.ceil((object.xRange.max - object.xRange.min) / object.cellSize));
    const zSteps = Math.max(2, Math.ceil((object.zRange.max - object.zRange.min) / object.cellSize));
    for (let index = 0; index <= xSteps; index += 1) {
      const x = object.xRange.min + ((object.xRange.max - object.xRange.min) * index) / xSteps;
      const from: Scene3DVector = [x, object.y, object.zRange.min];
      const to: Scene3DVector = [x, object.y, object.zRange.max];
      if (!scenePointPassesSlice(from, slice, sliceEnabled, sliceValue) && !scenePointPassesSlice(to, slice, sliceEnabled, sliceValue)) continue;
      drawLine(context, projectPoint(from, camera, bounds, width, height), projectPoint(to, camera, bounds, width, height));
    }
    for (let index = 0; index <= zSteps; index += 1) {
      const z = object.zRange.min + ((object.zRange.max - object.zRange.min) * index) / zSteps;
      const from: Scene3DVector = [object.xRange.min, object.y, z];
      const to: Scene3DVector = [object.xRange.max, object.y, z];
      if (!scenePointPassesSlice(from, slice, sliceEnabled, sliceValue) && !scenePointPassesSlice(to, slice, sliceEnabled, sliceValue)) continue;
      drawLine(context, projectPoint(from, camera, bounds, width, height), projectPoint(to, camera, bounds, width, height));
    }
    context.restore();
    return;
  }

  context.strokeStyle = normalizeColor(object.wireColor, object.finalColor);
  context.lineWidth = 1;
  const rowCount = object.yValues.length;
  const colCount = object.yValues[0]?.length ?? 0;
  for (let row = 0; row < rowCount; row += 1) {
    let previous: ProjectionPoint | null = null;
    for (let col = 0; col < colCount; col += 1) {
      const point = surfacePoint(object, row, col);
      if (!scenePointPassesSlice(point, slice, sliceEnabled, sliceValue)) {
        previous = null;
        continue;
      }
      const projected = projectPoint(point, camera, bounds, width, height);
      if (!projected.visible) {
        previous = null;
        continue;
      }
      if (previous) drawLine(context, previous, projected);
      previous = projected;
    }
  }
  for (let col = 0; col < colCount; col += 1) {
    let previous: ProjectionPoint | null = null;
    for (let row = 0; row < rowCount; row += 1) {
      const point = surfacePoint(object, row, col);
      if (!scenePointPassesSlice(point, slice, sliceEnabled, sliceValue)) {
        previous = null;
        continue;
      }
      const projected = projectPoint(point, camera, bounds, width, height);
      if (!projected.visible) {
        previous = null;
        continue;
      }
      if (previous) drawLine(context, previous, projected);
      previous = projected;
    }
  }
  context.restore();
}

function buildHitCandidates(
  objects: LayeredObject[],
  layerState: Record<string, boolean>,
  camera: CameraState,
  bounds: Bounds3D,
  width: number,
  height: number,
  slice: Scene3DSlice | null,
  sliceEnabled: boolean,
  sliceValue: number,
) {
  const candidates: Array<{ id: string; label: string; x: number; y: number; distance: number; depth: number }> = [];
  for (const object of objects) {
    if (!object.visible || !layerState[object.layerKey]) continue;
    const points = object.kind === "point"
      ? [{ id: object.id, label: object.label ?? object.id, point: object.position }]
      : object.kind === "polyline"
        ? object.points.map((point, index) => ({ id: object.id, label: object.label ?? `${object.id} #${index + 1}`, point }))
        : object.kind === "molecule"
          ? [
            ...object.atoms.map((atom) => ({
              id: `${object.id}:${atom.id}`,
              label: `${object.label ? `${object.label} · ` : ""}${atomDisplayText(atom)}`,
              point: atom.position,
            })),
            ...object.electronDomains.map((domain) => ({
              id: `${object.id}:${domain.id}`,
              label: domain.label ?? (domain.kind === "lonePair" ? "孤对电子" : "电子域"),
              point: resolveElectronDomainPosition(object, domain),
            })),
          ]
          : [];
    for (const point of points) {
      if (!scenePointPassesSlice(point.point, slice, sliceEnabled, sliceValue)) continue;
      const projected = projectPoint(point.point, camera, bounds, width, height);
      if (!projected.visible) continue;
      candidates.push({
        id: point.id,
        label: point.label,
        x: projected.x,
        y: projected.y,
        distance: 0,
        depth: projected.depth,
      });
    }
  }
  return candidates;
}

function formatReadoutValue(readout: Scene3DReadout) {
  const value = typeof readout.value === "number" ? Number(readout.value.toFixed(4)).toString() : readout.value;
  return readout.unit ? `${value} ${readout.unit}` : value;
}

function compileScene3DObject(object: Scene3DObject): LayeredObject {
  return {
    ...object,
    layerKey: object.layer ?? "default",
    finalColor: normalizeColor(object.color),
    finalAlpha: clamp(object.alpha, 0.12, 1),
  };
}

function Scene3DMount({
  compiled,
  context,
}: {
  compiled: Scene3DCompiledRenderPlan;
  context: RendererLifecycleContext;
}) {
  const wrapperRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const dragState = useRef<{ active: boolean; x: number; y: number } | null>(null);
  const [canvasSize, setCanvasSize] = useState({ width: 320, height: 260 });
  const [focus, setFocus] = useState<SceneFocus | null>(null);
  const [yaw, setYaw] = useState(compiled.spec.camera.yaw);
  const [pitch, setPitch] = useState(compiled.spec.camera.pitch);
  const [distance, setDistance] = useState(compiled.spec.camera.distance);
  const [activeLayerMap, setActiveLayerMap] = useState<Record<string, boolean>>(() => Object.fromEntries(
    compiled.layers.map((layer) => [layer.id, layer.visibleDefault]),
  ));
  const [activeSliceIndex, setActiveSliceIndex] = useState(0);
  const [sliceValue, setSliceValue] = useState(compiled.spec.slices[0]?.value ?? 0);
  const [activeStateIndex, setActiveStateIndex] = useState(() => {
    const initial = compiled.spec.stateBinding?.initial;
    const index = initial ? compiled.states.findIndex((state) => state.id === initial) : 0;
    return Math.max(0, index);
  });

  const stateList = compiled.states;
  const activeState = stateList[activeStateIndex] ?? null;
  const activeObjects = useMemo(() => {
    if (!activeState) return compiled.objects;
    const baseObjects = activeState.objectIds?.length
      ? compiled.objects.filter((object) => activeState.objectIds?.includes(object.id))
      : compiled.objects;
    return [...baseObjects, ...activeState.objects];
  }, [activeState, compiled.objects]);
  const bounds = useMemo(() => computeSceneBounds(compiled.spec, activeObjects), [activeObjects, compiled.spec]);
  const layerList = useMemo(
    () => [...compiled.layers].sort((left, right) => (left.title ?? left.id).localeCompare(right.title ?? right.id)),
    [compiled.layers],
  );
  const activeSlice = compiled.spec.slices[activeSliceIndex] ?? null;
  const sliceEnabled = Boolean(activeSlice && compiled.spec.controls.allowSlice);
  const visibleActiveObjects = useMemo(
    () => activeObjects.filter((object) => object.visible && (activeLayerMap[object.layerKey] ?? true)),
    [activeLayerMap, activeObjects],
  );
  const moleculeOnlyScene = visibleActiveObjects.length > 0 && visibleActiveObjects.every((object) => object.kind === "molecule");
  const baseCamera = useMemo<CameraState>(() => ({
    yaw,
    pitch,
    distance,
    lookAt: compiled.spec.camera.lookAt,
    fov: compiled.spec.camera.fov,
    fitScale: 1,
  }), [yaw, pitch, distance, compiled.spec.camera.lookAt, compiled.spec.camera.fov]);
  const camera = useMemo<CameraState>(() => ({
    ...baseCamera,
    fitScale: computeProjectionFitScale(visibleActiveObjects, baseCamera, bounds, canvasSize.width, canvasSize.height),
  }), [baseCamera, bounds, canvasSize.height, canvasSize.width, visibleActiveObjects]);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const { width, height } = canvasSize;
    const dpr = Math.min(2, Math.max(1, window.devicePixelRatio || 1));
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;

    const renderingContext = canvas.getContext("2d");
    if (!renderingContext) return;
    renderingContext.setTransform(dpr, 0, 0, dpr, 0, 0);
    renderingContext.clearRect(0, 0, width, height);

    if (!moleculeOnlyScene) {
      drawReferenceGrid(renderingContext, camera, bounds, width, height);
      drawCoordinateFrame(renderingContext, compiled.spec, camera, bounds, width, height);
    }
    if (sliceEnabled && activeSlice) {
      drawSlicePlane(renderingContext, activeSlice, sliceValue, camera, bounds, width, height);
    }

    const drawableObjects = visibleActiveObjects
      .sort((left, right) => objectDepth(right, camera, bounds, width, height) - objectDepth(left, camera, bounds, width, height));

    for (const object of drawableObjects) {
      drawSceneObject(renderingContext, object, camera, bounds, width, height, activeSlice, sliceEnabled, sliceValue);
    }

    if (sliceEnabled && activeSlice) {
      renderingContext.save();
      renderingContext.fillStyle = "rgba(63, 51, 41, 0.78)";
      renderingContext.font = "12px ui-serif, Georgia, serif";
      renderingContext.fillText(
        `切片：${activeSlice.label ?? activeSlice.axis} = ${sliceValue.toFixed(2)} ± ${activeSlice.thickness.toFixed(2)}`,
        12,
        18,
      );
      renderingContext.restore();
    }
  }, [activeSlice, bounds, camera, canvasSize, compiled.spec, moleculeOnlyScene, sliceEnabled, sliceValue, visibleActiveObjects]);

  const updateCanvasSize = useCallback(() => {
    const wrapper = wrapperRef.current;
    if (!wrapper) return;
    const rect = wrapper.getBoundingClientRect();
    const width = Math.max(280, Math.floor(rect.width || 320));
    const preferredHeight = Math.round(width * 0.58);
    const budgetHeight = compiled.plan.qualityBudget.maxHeight ?? 420;
    const height = clamp(preferredHeight, 240, Math.min(560, budgetHeight));
    setCanvasSize((current) => current.width === width && current.height === height ? current : { width, height });
  }, [compiled.plan.qualityBudget.maxHeight]);

  useEffect(() => {
    updateCanvasSize();
    const wrapper = wrapperRef.current;
    if (!wrapper) return;
    const observer = new ResizeObserver(updateCanvasSize);
    observer.observe(wrapper);
    return () => observer.disconnect();
  }, [updateCanvasSize]);

  useEffect(() => {
    draw();
  }, [draw]);

  useEffect(() => {
    setFocus(null);
  }, [activeStateIndex]);

  useEffect(() => {
    context.postMessage({
      type: "weibei:state",
      programID: compiled.programID,
      state: {
        renderer: SCENE3D_RENDERER,
        activeState: activeState
          ? {
            id: activeState.id,
            title: activeState.title ?? activeState.id,
            index: activeStateIndex,
            evidenceIDs: activeState.evidenceIDs,
            objectIds: activeObjects.map((object) => object.id),
            readouts: activeState.readouts.map((readout) => ({
              id: readout.id,
              label: readout.label,
              value: readout.value,
              unit: readout.unit ?? null,
              evidenceIDs: readout.evidenceIDs,
            })),
          }
          : null,
        view: {
          yaw: Number(yaw.toFixed(2)),
          pitch: Number(pitch.toFixed(2)),
          distance: Number(distance.toFixed(2)),
          fitScale: Number(camera.fitScale.toFixed(3)),
          facing: degToCompass(yaw),
        },
        layers: layerList.map((layer) => ({ id: layer.id, title: layer.title ?? layer.id, visible: activeLayerMap[layer.id] ?? true })),
        molecules: activeObjects
          .filter((object) => object.kind === "molecule")
          .map((object) => ({
            id: object.id,
            atoms: object.atoms.length,
            bonds: object.bonds.length,
            electronDomains: object.electronDomains.length,
          })),
        slice: sliceEnabled && activeSlice ? { axis: activeSlice.axis, value: Number(sliceValue.toFixed(3)), thickness: activeSlice.thickness } : null,
        focus,
        note: "Canvas 2D 确定性投影；不使用 WebGL、外链模型、任意脚本或手写 SVG；遮挡与曲面填充为近似表达。",
      },
    });
  }, [activeLayerMap, activeObjects, activeSlice, activeState, activeStateIndex, camera.fitScale, compiled.programID, context, distance, focus, layerList, pitch, sliceEnabled, sliceValue, yaw]);

  const resetCamera = useCallback(() => {
    setYaw(compiled.spec.camera.yaw);
    setPitch(compiled.spec.camera.pitch);
    setDistance(compiled.spec.camera.distance);
    setFocus(null);
  }, [compiled.spec.camera]);

  const handleVerifyInteraction = useCallback(() => {
    setYaw((current) => (current + 18) % 360);
    setPitch((current) => clamp(current + 6, -82, 82));
    if (compiled.spec.controls.allowSlice && compiled.spec.slices.length) {
      const next = (activeSliceIndex + 1) % compiled.spec.slices.length;
      setActiveSliceIndex(next);
      setSliceValue(compiled.spec.slices[next]?.value ?? 0);
    }
    if (stateList.length > 1) {
      setActiveStateIndex((current) => (current + 1) % stateList.length);
    }
  }, [activeSliceIndex, compiled.spec.controls.allowSlice, compiled.spec.slices, stateList.length]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const onPointerDown = (event: PointerEvent) => {
      if (!compiled.spec.controls.allowCameraDrag) return;
      dragState.current = { active: true, x: event.clientX, y: event.clientY };
      canvas.setPointerCapture?.(event.pointerId);
    };
    const onPointerMove = (event: PointerEvent) => {
      const state = dragState.current;
      if (!state?.active || !compiled.spec.controls.allowCameraDrag) return;
      setYaw((current) => current + (event.clientX - state.x) * 0.18);
      setPitch((current) => clamp(current - (event.clientY - state.y) * 0.18, -82, 82));
      state.x = event.clientX;
      state.y = event.clientY;
    };
    const onPointerUp = () => {
      if (dragState.current) dragState.current.active = false;
    };
    const onWheel = (event: WheelEvent) => {
      if (!compiled.spec.controls.allowCameraDrag) return;
      event.preventDefault();
      setDistance((current) => clamp(current * (1 + event.deltaY * 0.0009), 0.8, 14));
    };

    canvas.addEventListener("pointerdown", onPointerDown);
    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", onPointerUp);
    canvas.addEventListener("wheel", onWheel, { passive: false });
    canvas.addEventListener("weibei:verify-interaction", handleVerifyInteraction);

    return () => {
      canvas.removeEventListener("pointerdown", onPointerDown);
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("pointerup", onPointerUp);
      canvas.removeEventListener("wheel", onWheel);
      canvas.removeEventListener("weibei:verify-interaction", handleVerifyInteraction);
    };
  }, [compiled.spec.controls.allowCameraDrag, handleVerifyInteraction]);

  const onCanvasClick = useCallback((event: React.MouseEvent<HTMLCanvasElement>) => {
    if (!compiled.spec.focusEnabled && !compiled.spec.controls.allowProbe) return;
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;
    const cursorX = event.clientX - rect.left;
    const cursorY = event.clientY - rect.top;
    const candidates = buildHitCandidates(
      activeObjects,
      activeLayerMap,
      camera,
      bounds,
      canvasSize.width,
      canvasSize.height,
      activeSlice,
      sliceEnabled,
      sliceValue,
    )
      .map((candidate) => ({ ...candidate, distance: Math.hypot(candidate.x - cursorX, candidate.y - cursorY) }))
      .sort((left, right) => left.distance - right.distance || left.depth - right.depth);

    const nearest = candidates[0];
    if (!nearest || nearest.distance > 28) {
      setFocus(null);
      return;
    }
    setFocus({
      targetId: nearest.id,
      screenX: nearest.x,
      screenY: nearest.y,
      distance: nearest.depth,
      label: nearest.label,
    });
  }, [activeLayerMap, activeObjects, activeSlice, bounds, camera, canvasSize.height, canvasSize.width, compiled.spec.controls.allowProbe, compiled.spec.focusEnabled, sliceEnabled, sliceValue]);

  return (
    <figure className="weibei-scene3d" data-weibei-renderer={SCENE3D_RENDERER} style={{ margin: 0 }}>
      <div ref={wrapperRef} className="weibei-scene3d__surface-wrap" style={{ position: "relative", width: "100%" }}>
        <canvas
          ref={canvasRef}
          role="img"
          aria-label={compiled.title}
          onClick={onCanvasClick}
          style={{
            display: "block",
            width: "100%",
            minHeight: 240,
            borderRadius: 12,
            border: "1px solid rgba(140, 118, 93, 0.28)",
            background: "transparent",
            touchAction: compiled.spec.controls.allowCameraDrag ? "none" : "auto",
          }}
        />
      </div>
      <div
        className="weibei-scene3d__controls"
        style={{ display: "grid", gap: 8, marginTop: 10, gridTemplateColumns: "repeat(auto-fit, minmax(160px, 1fr))" }}
      >
        <label>
          <span>水平旋转 {yaw.toFixed(0)}°</span>
          <input type="range" min={-180} max={180} step={0.2} value={yaw} onChange={(event) => setYaw(Number(event.currentTarget.value))} />
        </label>
        <label>
          <span>俯仰 {pitch.toFixed(0)}°</span>
          <input type="range" min={-82} max={82} step={0.2} value={pitch} onChange={(event) => setPitch(Number(event.currentTarget.value))} />
        </label>
        <label>
          <span>距离 {distance.toFixed(1)}</span>
          <input type="range" min={0.8} max={14} step={0.05} value={distance} onChange={(event) => setDistance(Number(event.currentTarget.value))} />
        </label>
        {compiled.spec.controls.allowReset ? <button type="button" onClick={resetCamera}>重置视角</button> : null}
      </div>
      {layerList.length > 1 && compiled.spec.controls.allowLayerToggle ? (
        <div className="weibei-scene3d__layers" style={{ display: "flex", flexWrap: "wrap", gap: 10, marginTop: 8 }}>
          {layerList.map((layer) => (
            <label key={layer.id}>
              <input
                type="checkbox"
                checked={activeLayerMap[layer.id] ?? true}
                onChange={() => setActiveLayerMap((current) => ({ ...current, [layer.id]: !(current[layer.id] ?? true) }))}
              />
              {layer.title ?? layer.id}
            </label>
          ))}
        </div>
      ) : null}
      {stateList.length > 1 && compiled.spec.stateBinding ? (
        <div className="weibei-scene3d__states" style={{ display: "grid", gap: 6, marginTop: 8 }}>
          <div style={{ display: "grid", gap: 6 }}>
            <span>{compiled.spec.stateBinding.label}</span>
            {compiled.spec.stateBinding.control === "slider" ? (
              <input
                type="range"
                min={0}
                max={stateList.length - 1}
                step={1}
                value={activeStateIndex}
                data-weibei-control="scene-3d-state"
                data-weibei-control-id={compiled.programID}
                data-weibei-state={activeState?.id ?? ""}
                onChange={(event) => setActiveStateIndex(Number(event.currentTarget.value))}
              />
            ) : (
              <div role="group" aria-label={compiled.spec.stateBinding.label} style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                {stateList.map((state, index) => (
                  <button
                    key={state.id}
                    type="button"
                    aria-pressed={activeStateIndex === index}
                    data-weibei-control="scene-3d-state"
                    data-weibei-control-id={state.id}
                    data-weibei-state={activeStateIndex === index ? "active" : "inactive"}
                    className={activeStateIndex === index ? "is-active" : ""}
                    onClick={() => setActiveStateIndex(index)}
                    style={{
                      border: "1px solid rgba(140, 118, 93, 0.3)",
                      borderRadius: 999,
                      padding: "5px 10px",
                      background: activeStateIndex === index ? "rgba(156, 82, 61, 0.12)" : "transparent",
                      color: "inherit",
                    }}
                  >
                    {state.title ?? state.id}
                  </button>
                ))}
              </div>
            )}
          </div>
          {activeState ? (
            <div style={{ display: "grid", gap: 4 }}>
              <strong>{activeState.title ?? activeState.id}</strong>
              {activeState.description ? <span>{activeState.description}</span> : null}
              {activeState.readouts.length ? (
                <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
                  {activeState.readouts.map((readout) => (
                    <span key={readout.id} style={{ border: "1px solid rgba(140, 118, 93, 0.28)", borderRadius: 8, padding: "4px 8px" }}>
                      {readout.label}：{formatReadoutValue(readout)}
                    </span>
                  ))}
                </div>
              ) : null}
            </div>
          ) : null}
        </div>
      ) : null}
      {compiled.spec.controls.allowSlice && compiled.spec.slices.length ? (
        <div className="weibei-scene3d__slice" style={{ display: "grid", gap: 6, marginTop: 8 }}>
          <label>
            <span>切片</span>
            <select
              value={activeSliceIndex}
              onChange={(event) => {
                const next = Number(event.currentTarget.value);
                setActiveSliceIndex(next);
                setSliceValue(compiled.spec.slices[next]?.value ?? 0);
              }}
            >
              {compiled.spec.slices.map((slice, index) => (
                <option key={`${slice.axis}-${index}`} value={index}>{slice.label ?? `${slice.axis} 轴`}</option>
              ))}
            </select>
          </label>
          {activeSlice ? (
            <label>
              <span>{activeSlice.axis} = {sliceValue.toFixed(2)}</span>
              <input
                type="range"
                min={bounds[activeSlice.axis].min}
                max={bounds[activeSlice.axis].max}
                step={(bounds[activeSlice.axis].max - bounds[activeSlice.axis].min) / 200}
                value={sliceValue}
                onChange={(event) => setSliceValue(Number(event.currentTarget.value))}
              />
            </label>
          ) : null}
        </div>
      ) : null}
      {compiled.spec.focusEnabled || focus ? (
        <figcaption style={{ marginTop: 8 }}>
          {focus ? `${focus.label}：屏幕点 (${focus.screenX.toFixed(0)}, ${focus.screenY.toFixed(0)})，近似深度 ${focus.distance.toFixed(2)}` : "点击点或折线顶点可查看读数"}
        </figcaption>
      ) : null}
      {compiled.spec.caption ? <figcaption style={{ marginTop: 6 }}>{compiled.spec.caption}</figcaption> : null}
      <small style={{ marginTop: 6, color: "rgba(84, 70, 58, 0.8)", display: "inline-block" }}>
        数据点 {compiled.dataPointCount}，画布 {canvasSize.width}×{canvasSize.height}；确定性 Canvas 2D 投影，不加载 WebGL、外链模型、脚本或手写 SVG。
      </small>
    </figure>
  );
}

function Scene3DFallback({ issue }: { issue: RendererIssue }) {
  return (
    <div className="generation-error" role="alert" data-weibei-renderer-issue={issue.code}>
      <strong>三维场景已诚实降级</strong>
      <span>{issue.message}</span>
      {issue.details?.length ? <small>{issue.details.join("；")}</small> : null}
    </div>
  );
}

export const scene3DRenderer: RichAnswerRenderer = {
  id: SCENE3D_RENDERER,
  version: "0.1.0",
  capabilities: {
    renderer: SCENE3D_RENDERER,
    version: "0.1.0",
    specVersions: [SCENE3D_SPEC_VERSION],
    displayName: "魏碑受控三维场景",
    data: ["scene-tree", "camera", "coordinates", "slices", "layers", "states", "readouts", "point", "polyline", "surface", "wireframe-grid", "molecule", "atom", "bond", "electron-domain", "angle-marker"],
    interactions: ["yaw-slider", "pitch-slider", "distance-slider", "layer-toggle", "slice-slider", "state-segmented", "state-slider", "drag-rotate", "wheel-zoom", "probe-click", "molecule-probe"],
    resources: ["canvas-2d", "deterministic-projection", "local-state-binding", "responsive-transparent-surface"],
    maxNodes: maxScene3DObjects,
    maxDataPoints: maxScene3DDataPoints,
    fallback: ["static_snapshot", "simplified_component", "structured_error"],
  },
  validate(plan) {
    const parsed = parseScene3DSpec(plan);
    return parsed.ok === true ? { ok: true } : { ok: false, issue: parsed.issue };
  },
  compile(plan, context) {
    const parsed = parseScene3DSpec(plan);
    if (parsed.ok === false) return { ok: false, issue: parsed.issue };
    return {
      ok: true,
      compiled: {
        renderer: SCENE3D_RENDERER,
        version: SCENE3D_SPEC_VERSION,
        plan,
        programID: context.program.id,
        title: parsed.spec.title,
        objects: parsed.spec.objects.map(compileScene3DObject),
        states: parsed.spec.states.map((state) => ({
          ...state,
          objects: state.objects.map(compileScene3DObject),
        })),
        layers: parsed.layers,
        dataPointCount: parsed.dataPointCount,
        spec: parsed.spec,
      } satisfies Scene3DCompiledRenderPlan,
    };
  },
  mount(compiled, context) {
    return <Scene3DMount compiled={compiled as Scene3DCompiledRenderPlan} context={context} />;
  },
  update(compiled, _previous, context) {
    return <Scene3DMount compiled={compiled as Scene3DCompiledRenderPlan} context={context} />;
  },
  dispose() {
    return undefined;
  },
  fallback(issue) {
    return <Scene3DFallback issue={issue} />;
  },
};
