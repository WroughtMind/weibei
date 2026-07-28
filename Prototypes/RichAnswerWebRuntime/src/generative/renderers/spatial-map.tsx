import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  createRendererIssue,
  type CompiledRenderPlan,
  type RenderPlan,
  type RendererLifecycleContext,
  type RichAnswerRenderer,
} from "../renderer-registry";
import {
  SPATIAL_MAP_RENDERER,
  SPATIAL_MAP_SPEC_VERSION,
  type SpatialMapFeature,
  type SpatialMapScreenTransform,
  type SpatialMapSpec,
  parseSpatialMapSpec,
  resolveSpatialMapVisibility,
  runSpatialMapVisibilitySelfCheck,
  runSpatialMapViewportSelfCheck,
  spatialMapBaseToScreen,
  spatialMapScreenToBase,
} from "./spatial-map.self-check";

type SpatialCompiled = CompiledRenderPlan & {
  spec: SpatialMapSpec;
};

type ViewPort = { x: number; y: number; width: number; height: number; scale: number };

type MapBounds = {
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
};

type MapState = {
  x: number;
  y: number;
  scale: number;
};

type Focus = {
  targetId: string;
  kind: SpatialMapFeature["kind"];
  x: number;
  y: number;
  label: string;
  value?: string;
};

type GeometryFeature = Extract<SpatialMapFeature, { kind: "point" | "line" | "polygon" }>;
type FeatureStyle = NonNullable<GeometryFeature["style"]>;
type CanvasPoint = { x: number; y: number };
type DeferredLabel = {
  id: string;
  targetId?: string;
  text: string;
  anchor: CanvasPoint;
  color: string;
  size: number;
  weight: "normal" | "bold";
  priority: number;
  shadow?: boolean;
};
type LabelBox = { x: number; y: number; width: number; height: number };

const defaultFeatureStyle: FeatureStyle = {
  stroke: "#6e5144",
  strokeWidth: 1.8,
  fill: "rgba(111, 88, 70, 0.2)",
  opacity: 0.9,
  dash: false,
};

const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));

function toDisplayColor(value: string, fallback: string) {
  return value && value !== "none" ? value : fallback;
}

function mercatorY(latDeg: number) {
  const lat = clamp(latDeg, -85.05, 85.05);
  const latRad = (lat * Math.PI) / 180;
  return (1 - Math.log(Math.tan(Math.PI / 4 + latRad / 2)) / Math.PI) / 2;
}

function worldToNormalized(
  point: { x: number; y: number },
  coordinateMode: SpatialMapSpec["coordinateMode"],
  bounds: MapBounds,
) {
  if (coordinateMode === "geographic") {
    const xSpan = Math.max(bounds.xMax - bounds.xMin, 1e-12);
    const yMaxMercator = mercatorY(bounds.yMax);
    const yMinMercator = mercatorY(bounds.yMin);
    const ySpan = Math.max(yMinMercator - yMaxMercator, 1e-12);
    const x = clamp((point.x - bounds.xMin) / xSpan, 0, 1);
    const y = clamp((yMinMercator - mercatorY(point.y)) / ySpan, 0, 1);
    return { x, y };
  }

  const xSpan = Math.max(bounds.xMax - bounds.xMin, 1e-12);
  const ySpan = Math.max(bounds.yMax - bounds.yMin, 1e-12);
  return {
    x: clamp((point.x - bounds.xMin) / xSpan, 0, 1),
    y: clamp((point.y - bounds.yMin) / ySpan, 0, 1),
  };
}

function chooseBounds(spec: SpatialMapSpec): MapBounds {
  if (spec.coordinateMode === "geographic") {
    return spec.bounds
      ? {
        xMin: clamp(spec.bounds.xMin, -180, 180),
        xMax: clamp(spec.bounds.xMax, -180, 180),
        yMin: clamp(spec.bounds.yMin, -90, 90),
        yMax: clamp(spec.bounds.yMax, -90, 90),
      }
      : { xMin: -180, xMax: 180, yMin: -90, yMax: 90 };
  }

  let xMin = Number.POSITIVE_INFINITY;
  let xMax = Number.NEGATIVE_INFINITY;
  let yMin = Number.POSITIVE_INFINITY;
  let yMax = Number.NEGATIVE_INFINITY;

  const geometryFeatures = spec.features.filter((feature) => feature.kind !== "label");
  const boundsFeatures = geometryFeatures.length ? geometryFeatures : spec.features;

  for (const feature of boundsFeatures) {
    const points = feature.kind === "label" || feature.kind === "point"
      ? [{ x: feature.x, y: feature.y }]
      : feature.points;
    for (const point of points) {
      xMin = Math.min(xMin, point.x);
      xMax = Math.max(xMax, point.x);
      yMin = Math.min(yMin, point.y);
      yMax = Math.max(yMax, point.y);
    }
  }

  if (!Number.isFinite(xMin) || xMin === xMax) {
    return { xMin: 0, xMax: 1, yMin: 0, yMax: 1 };
  }
  if (!Number.isFinite(yMin) || yMin === yMax) {
    return { xMin: 0, xMax: 1, yMin: 0, yMax: 1 };
  }

  const padX = (xMax - xMin) * 0.08 || 0.06;
  const padY = (yMax - yMin) * 0.08 || 0.06;
  return {
    xMin: xMin - padX,
    xMax: xMax + padX,
    yMin: yMin - padY,
    yMax: yMax + padY,
  };
}

function mapToCanvas(point: { x: number; y: number }, viewport: ViewPort, bounds: MapBounds, mode: SpatialMapSpec["coordinateMode"]) {
  const normalized = worldToNormalized(point, mode, bounds);
  const x = clamp(normalized.x * viewport.width, -Infinity, viewport.width);
  const y = mode === "geographic"
    ? normalized.y * viewport.height
    : (1 - normalized.y) * viewport.height;
  return { x, y };
}

function buildScreenTransform(viewport: ViewPort): SpatialMapScreenTransform {
  return {
    width: viewport.width,
    height: viewport.height,
    panX: viewport.x,
    panY: viewport.y,
    scale: viewport.scale,
  };
}

function pointDistance(a: { x: number; y: number }, b: { x: number; y: number }) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function pointLineDistance(point: { x: number; y: number }, a: { x: number; y: number }, b: { x: number; y: number }) {
  const vx = b.x - a.x;
  const vy = b.y - a.y;
  const wx = point.x - a.x;
  const wy = point.y - a.y;
  const vv = vx * vx + vy * vy;
  if (vv <= 0) return pointDistance(point, a);
  const t = clamp((wx * vx + wy * vy) / vv, 0, 1);
  const cx = a.x + t * vx;
  const cy = a.y + t * vy;
  return pointDistance(point, { x: cx, y: cy });
}

function polygonCentroid(points: Array<{ x: number; y: number }>) {
  const sum = points.reduce((acc, p) => {
    acc.x += p.x;
    acc.y += p.y;
    return acc;
  }, { x: 0, y: 0 });
  return { x: sum.x / Math.max(points.length, 1), y: sum.y / Math.max(points.length, 1) };
}

function labelMapKey(label: DeferredLabel) {
  return label.targetId ? `target:${label.targetId}` : `label:${label.id}`;
}

function upsertDeferredLabel(labels: Map<string, DeferredLabel>, label: DeferredLabel) {
  const key = labelMapKey(label);
  const existing = labels.get(key);
  if (!existing || label.priority > existing.priority || (label.priority === existing.priority && label.text.length > existing.text.length)) {
    labels.set(key, label);
  }
}

function truncateLabel(ctx: CanvasRenderingContext2D, text: string, maxWidth: number) {
  if (ctx.measureText(text).width <= maxWidth) return text;
  let next = text.trim();
  while (next.length > 2 && ctx.measureText(`${next}…`).width > maxWidth) {
    next = next.slice(0, -1);
  }
  return `${next}…`;
}

function boxesOverlap(left: LabelBox, right: LabelBox) {
  return left.x < right.x + right.width
    && left.x + left.width > right.x
    && left.y < right.y + right.height
    && left.y + left.height > right.y;
}

function placeLabel(
  label: DeferredLabel,
  anchor: CanvasPoint,
  ctx: CanvasRenderingContext2D,
  occupied: LabelBox[],
  width: number,
  height: number,
  isNarrow: boolean,
) {
  const maxWidth = Math.max(72, Math.min(isNarrow ? 132 : 190, width - 20));
  const text = truncateLabel(ctx, label.text, maxWidth);
  const textWidth = Math.min(maxWidth, ctx.measureText(text).width);
  const textHeight = Math.max(14, label.size + 5);
  const paddingX = 6;
  const paddingY = 4;
  const boxWidth = textWidth + paddingX * 2;
  const boxHeight = textHeight + paddingY;
  const candidates = [
    { dx: 8, dy: -boxHeight - 5 },
    { dx: 8, dy: 9 },
    { dx: -boxWidth - 8, dy: -boxHeight - 5 },
    { dx: -boxWidth - 8, dy: 9 },
    { dx: -boxWidth / 2, dy: -boxHeight - 16 },
    { dx: -boxWidth / 2, dy: 18 },
  ];

  for (const candidate of candidates) {
    const box = {
      x: clamp(anchor.x + candidate.dx, 6, Math.max(6, width - boxWidth - 6)),
      y: clamp(anchor.y + candidate.dy, 6, Math.max(6, height - boxHeight - 6)),
      width: boxWidth,
      height: boxHeight,
    };
    if (!occupied.some((item) => boxesOverlap(item, box))) {
      return { box, text, textWidth, textHeight, paddingX, paddingY };
    }
  }

  return null;
}

function drawDeferredLabels(
  ctx: CanvasRenderingContext2D,
  labels: Map<string, DeferredLabel>,
  transform: SpatialMapScreenTransform,
  width: number,
  height: number,
  isNarrow: boolean,
) {
  const occupied: LabelBox[] = [];
  const visibleLabels = Array.from(labels.values()).sort((left, right) => right.priority - left.priority);
  for (const label of visibleLabels) {
    const anchor = spatialMapBaseToScreen(label.anchor, transform);
    if (anchor.x < -90 || anchor.x > width + 90 || anchor.y < -70 || anchor.y > height + 70) continue;
    ctx.font = `${label.weight === "bold" ? "600 " : ""}${label.size}px sans-serif`;
    const placed = placeLabel(label, anchor, ctx, occupied, width, height, isNarrow);
    if (!placed) continue;

    occupied.push(placed.box);
    ctx.save();
    ctx.globalAlpha = 0.96;
    ctx.fillStyle = "rgba(250, 247, 239, 0.88)";
    ctx.strokeStyle = "rgba(102, 83, 68, 0.16)";
    ctx.lineWidth = 1;
    const radius = 7;
    ctx.beginPath();
    ctx.roundRect(placed.box.x, placed.box.y, placed.box.width, placed.box.height, radius);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = label.color;
    if (label.shadow) {
      ctx.shadowColor = "rgba(250, 247, 239, 0.9)";
      ctx.shadowBlur = 3;
    }
    ctx.fillText(label.text === placed.text ? label.text : placed.text, placed.box.x + placed.paddingX, placed.box.y + placed.paddingY + placed.textHeight - 6);
    ctx.shadowBlur = 0;
    ctx.restore();
  }
}

function polygonContains(points: Array<{ x: number; y: number }>, target: { x: number; y: number }) {
  let inside = false;
  for (let i = 0; i < points.length; i += 1) {
    const a = points[i]!;
    const b = points[(i + 1) % points.length]!;
    const intersect = ((a.y > target.y) !== (b.y > target.y))
      && (target.x < (b.x - a.x) * (target.y - a.y) / ((b.y - a.y) || 1e-12) + a.x);
    if (intersect) inside = !inside;
  }
  return inside;
}

function distancePointToPoints(points: Array<{ x: number; y: number }>, target: { x: number; y: number }) {
  if (points.length === 1) return pointDistance(points[0]!, target);
  let min = Number.POSITIVE_INFINITY;
  for (let i = 0; i < points.length - 1; i += 1) {
    const a = points[i]!;
    const b = points[i + 1]!;
    min = Math.min(min, pointLineDistance(target, a, b));
  }
  if (points.length > 2) {
    min = Math.min(min, pointLineDistance(target, points[points.length - 1]!, points[0]!));
  }
  return min;
}

function formatValue(value: unknown) {
  return String(value ?? "");
}

function resolveSource(spec: SpatialMapSpec) {
  const mapSource = spec.mapAsset;
  if (mapSource.kind === "none") return "";
  if (!mapSource.source) return "";
  return mapSource.source;
}

function toLayerMap(spec: SpatialMapSpec) {
  return Object.fromEntries(
    spec.layers.map((layer) => [layer.id, layer.visibleDefault ?? true]),
  ) as Record<string, boolean>;
}

function getFeatureStyle(feature: GeometryFeature): FeatureStyle {
  return { ...defaultFeatureStyle, ...(feature.style ?? {}) };
}

function buildLayerLegend(spec: SpatialMapSpec, grouped: Map<string, SpatialMapFeature[]>) {
  const layerMap = new Map<string, { id: string; title: string; visible: boolean }>();
  for (const layer of spec.layers) {
    layerMap.set(layer.id, { id: layer.id, title: layer.title ?? layer.id, visible: layer.visibleDefault ?? true });
  }

  for (const layerID of grouped.keys()) {
    if (!layerMap.has(layerID)) {
      layerMap.set(layerID, { id: layerID, title: layerID, visible: true });
    }
  }

  if (!layerMap.size) {
    layerMap.set("default", { id: "default", title: "默认图层", visible: true });
  }

  return Array.from(layerMap.values());
}

function normalizeLayers(spec: SpatialMapSpec) {
  const layerDefaults = { ...toLayerMap(spec) };
  const grouped = new Map<string, SpatialMapFeature[]>();
  for (const feature of spec.features) {
    const layerID = feature.layer ?? "default";
    const target = grouped.get(layerID) ?? [];
    target.push(feature);
    grouped.set(layerID, target);
    if (!(layerID in layerDefaults)) {
      layerDefaults[layerID] = true;
    }
  }
  return {
    grouped,
    layerDefaults,
  };
}

function formatScaleBar(spec: SpatialMapSpec, viewport: ViewPort, bounds: MapBounds) {
  if (!spec.scaleBar.enabled) return null;

  const pixels = Math.max(spec.scaleBar.targetPixels, 40);
  if (viewport.width <= 0 || viewport.height <= 0) return null;

  if (spec.coordinateMode === "geographic") {
    const xSpanDeg = (Math.max(bounds.xMax - bounds.xMin, 1e-9) * pixels) / Math.max(viewport.width, 1);
    const meanLat = (bounds.yMin + bounds.yMax) * 0.5;
    const kmPerDeg = 111_320 * Math.cos((meanLat * Math.PI) / 180);
    const meters = xSpanDeg * kmPerDeg;
    if (!Number.isFinite(meters)) return null;

    const isKilometer = Math.abs(meters) >= 1000;
    const value = isKilometer ? meters / 1000 : meters;
    const label = `${spec.scaleBar.label}：${value.toFixed(isKilometer ? 1 : 0)} ${isKilometer ? "km" : "m"}`;
    return { pixels: Math.max(30, Math.min(pixels, viewport.width * 0.55)), label };
  }

  const xSpan = bounds.xMax - bounds.xMin;
  if (!Number.isFinite(xSpan) || xSpan === 0) return null;
  const valuePerPx = xSpan / Math.max(viewport.width, 1);
  const value = valuePerPx * pixels;
  const digits = Math.abs(value) >= 10 ? 0 : 2;
  return {
    pixels: Math.max(30, Math.min(pixels, viewport.width * 0.55)),
    label: `${spec.scaleBar.label}：${value.toFixed(digits)} 单位`,
  };
}

function SpatialMapFallback({ issue }: { issue: ReturnType<typeof parseSpatialMapSpec> extends infer T
  ? T extends { issue: infer I } ? I : never
  : never;
}) {
  return (
    <div
      className="generation-error"
      role="alert"
      data-weibei-renderer-issue={issue.code}
      style={{ padding: "12px", border: "1px dashed rgba(139, 20, 20, 0.35)", borderRadius: "8px", background: "rgba(255, 245, 245, 0.95)" }}
    >
      <strong>{issue.code === "capability_mismatch" ? "空间地图能力不匹配" : "空间地图渲染未通过"}</strong>
      <p style={{ margin: "6px 0 0" }}>{issue.message}</p>
      {issue.details?.length ? <small>{issue.details.join("；")}</small> : null}
    </div>
  );
}

function SpatialMapMount({ compiled, context }: { compiled: SpatialCompiled; context: RendererLifecycleContext }) {
  const { spec, title = "空间地图视图" } = compiled;
  const surfaceRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [viewport, setViewport] = useState({ width: 0, height: 0 });
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState<string | null>(null);
  const [layerVisibility, setLayerVisibility] = useState<Record<string, boolean>>(() => toLayerMap(spec));
  const [viewState, setViewState] = useState<MapState>({ x: 0, y: 0, scale: 1 });
  const [dragging, setDragging] = useState(false);
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  const [dragOrigin, setDragOrigin] = useState({ x: 0, y: 0 });
  const [focus, setFocus] = useState<Focus | null>(null);
  const [statusText, setStatusText] = useState("就绪");

  const bounds = useMemo(() => chooseBounds(spec), [spec.coordinateMode, spec.bounds, spec.features]);
  const grouped = useMemo(() => normalizeLayers(spec), [spec.features, spec.layers]);
  const layers = useMemo(() => buildLayerLegend(spec, grouped.grouped), [spec.layers, grouped.grouped]);
  const resolvedVisibility = useMemo(() => resolveSpatialMapVisibility(spec, layerVisibility), [spec, layerVisibility]);

  const normalizedView = useMemo<ViewPort>(() => {
    const width = Math.max(1, viewport.width);
    const height = Math.max(1, viewport.height);
    const scale = clamp(spec.controls?.allowZoom ? viewState.scale : 1, 0.45, 4);
    return {
      x: viewState.x,
      y: viewState.y,
      width,
      height,
      scale,
    };
  }, [spec.controls?.allowZoom, viewport.width, viewport.height, viewState.scale, viewState.x, viewState.y]);

  const mapSource = resolveSource(spec);
  const scaleBarViewport = useMemo<ViewPort>(() => ({
    ...normalizedView,
    width: normalizedView.width * normalizedView.scale,
    height: normalizedView.height * normalizedView.scale,
  }), [normalizedView]);
  const scaleBar = useMemo(() => formatScaleBar(spec, scaleBarViewport, bounds), [spec.coordinateMode, spec.scaleBar, scaleBarViewport, bounds]);

  const isLayerVisible = useCallback((layerID: string) => (
    resolvedVisibility.layerStates[layerID] ?? grouped.layerDefaults[layerID] ?? true
  ), [grouped.layerDefaults, resolvedVisibility.layerStates]);

  const isFeatureVisible = useCallback((feature: SpatialMapFeature): boolean => {
    return resolvedVisibility.visibleFeatureIds.has(feature.id);
  }, [resolvedVisibility.visibleFeatureIds]);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    const host = surfaceRef.current;
    const image = document.getElementById(`${compiled.programID}-weibei-spatial-bg`) as HTMLImageElement | null;
    if (!canvas || !host) return;

    const dpr = Math.max(window.devicePixelRatio || 1, 1);
    const styleWidth = Math.max(1, host.clientWidth);
    const styleHeight = Math.max(220, host.clientHeight);
    if (canvas.width !== Math.floor(styleWidth * dpr) || canvas.height !== Math.floor(styleHeight * dpr)) {
      canvas.width = Math.floor(styleWidth * dpr);
      canvas.height = Math.floor(styleHeight * dpr);
      canvas.style.width = `${styleWidth}px`;
      canvas.style.height = `${styleHeight}px`;
    }

    const ctx = canvas.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, styleWidth, styleHeight);

    const base = spec.coordinateMode === "geographic" ? "rgba(246, 243, 238, 0.92)" : "rgba(250, 250, 246, 0.88)";
    const grid = spec.coordinateMode === "geographic" ? "rgba(180, 160, 140, 0.35)" : "rgba(180, 190, 204, 0.35)";
    ctx.fillStyle = base;
    ctx.fillRect(0, 0, styleWidth, styleHeight);
    const deferredLabels = new Map<string, DeferredLabel>();

    ctx.save();
    ctx.translate(normalizedView.x, normalizedView.y);
    ctx.scale(normalizedView.scale, normalizedView.scale);

    // 背景（本地底图）
    if (imageLoaded && image && image.src && spec.mapAsset.kind !== "none") {
      ctx.drawImage(image, 0, 0, normalizedView.width, normalizedView.height);
    } else {
      ctx.strokeStyle = grid;
      ctx.lineWidth = 1 / Math.max(normalizedView.scale, 1e-9);
      for (let x = 0; x <= normalizedView.width; x += 24) {
        ctx.beginPath();
        ctx.moveTo(x, 0);
        ctx.lineTo(x, normalizedView.height);
        ctx.stroke();
      }
      for (let y = 0; y <= normalizedView.height; y += 24) {
        ctx.beginPath();
        ctx.moveTo(0, y);
        ctx.lineTo(normalizedView.width, y);
        ctx.stroke();
      }
    }

    // 坐标到共享 CSS 像素映射
    const toCanvas = (item: { x: number; y: number }) => {
      return mapToCanvas(item, normalizedView, bounds, spec.coordinateMode);
    };

    const drawViewport = {
      x: 0,
      y: 0,
      width: styleWidth,
      height: styleHeight,
      scale: normalizedView.scale,
    };

    // 图形绘制
    for (const [layerID, items] of grouped.grouped.entries()) {
      const visible = isLayerVisible(layerID);
      if (!visible) continue;
      for (const feature of items) {
        if (!isFeatureVisible(feature)) continue;
        if (feature.kind === "point") {
          const point = toCanvas({ x: feature.x, y: feature.y });
          const r = Math.max(2, (feature.radius ?? 3) * (1 / drawViewport.scale));
          const style = getFeatureStyle(feature);
          const stroke = toDisplayColor(style.stroke, "#6d5948");
          const fill = toDisplayColor(style.fill, "rgba(255,255,255,0.2)");
          ctx.beginPath();
          ctx.arc(point.x, point.y, r, 0, Math.PI * 2);
          ctx.fillStyle = fill;
          ctx.globalAlpha = style.opacity;
          ctx.fill();
          ctx.globalAlpha = 1;
          ctx.strokeStyle = stroke;
          ctx.lineWidth = Math.max(1, style.strokeWidth / Math.max(1, drawViewport.scale));
          ctx.stroke();
          if (feature.label) {
            upsertDeferredLabel(deferredLabels, {
              id: `${feature.id}-label`,
              targetId: feature.id,
              text: feature.label,
              anchor: point,
              color: stroke,
              size: 12,
              weight: "bold",
              priority: 70,
            });
          }
        } else if (feature.kind === "line" || feature.kind === "polygon") {
          const points = feature.points.map((p) => toCanvas(p));
          if (points.length < 2) continue;
          const style = getFeatureStyle(feature);
          const stroke = toDisplayColor(style.stroke, "#4c3d31");
          const fill = feature.kind === "polygon" && feature.fillMode !== "wire"
            ? toDisplayColor(style.fill, "rgba(98, 76, 51, 0.24)")
            : "transparent";

          ctx.beginPath();
          ctx.moveTo(points[0]!.x, points[0]!.y);
          for (let i = 1; i < points.length; i += 1) {
            ctx.lineTo(points[i]!.x, points[i]!.y);
          }
          if (feature.kind === "polygon" || feature.closed) {
            ctx.closePath();
          }

          if (feature.kind === "polygon" && feature.fillMode !== "wire") {
            ctx.fillStyle = fill;
            ctx.globalAlpha = style.opacity;
            ctx.fill();
            ctx.globalAlpha = 1;
          }
          ctx.strokeStyle = stroke;
          ctx.lineWidth = Math.max(1, style.strokeWidth / Math.max(1, drawViewport.scale));
          ctx.setLineDash(style.dash ? [4, 4] : []);
          ctx.stroke();
          ctx.setLineDash([]);

          if (feature.label) {
            const c = polygonCentroid(points);
            upsertDeferredLabel(deferredLabels, {
              id: `${feature.id}-label`,
              targetId: feature.id,
              text: feature.label,
              anchor: c,
              color: stroke,
              size: 12,
              weight: "bold",
              priority: feature.kind === "polygon" ? 58 : 54,
            });
          }
        } else if (feature.kind === "label") {
          const point = toCanvas({ x: feature.x, y: feature.y });
          const size = feature.style.size ?? 12;
          const color = toDisplayColor(feature.style.color ?? "#4b4538", "#4b4538");
          upsertDeferredLabel(deferredLabels, {
            id: feature.id,
            targetId: feature.bindTo,
            text: feature.text,
            anchor: point,
            color,
            size: Math.max(10, Math.min(16, size)),
            weight: feature.style.weight ?? "normal",
            priority: feature.bindTo ? 86 : 52,
            shadow: feature.style.shadow,
          });
        }
      }
    }

    ctx.restore();

    drawDeferredLabels(
      ctx,
      deferredLabels,
      buildScreenTransform(normalizedView),
      styleWidth,
      styleHeight,
      styleWidth < 560,
    );

    // 比例尺
    if (scaleBar) {
      const px = Math.max(40, scaleBar.pixels);
      const y = Math.max(styleHeight - 26, 26);
      const x = 14;
      ctx.fillStyle = "rgba(255,255,255,0.88)";
      ctx.strokeStyle = "rgba(0,0,0,0.4)";
      ctx.lineWidth = 2;
      ctx.fillRect(x, y, px, 7);
      ctx.strokeRect(x, y, px, 7);
      ctx.fillStyle = "rgba(40,40,42,0.8)";
      ctx.font = "11px sans-serif";
      ctx.fillText(scaleBar.label, x, y - 5);
    }

    // 焦点高亮
    if (focus) {
      ctx.strokeStyle = "rgba(25, 85, 125, 0.8)";
      ctx.fillStyle = "rgba(25, 85, 125, 0.12)";
      ctx.beginPath();
      const focusPoint = spatialMapBaseToScreen(focus, buildScreenTransform(normalizedView));
      ctx.arc(focusPoint.x, focusPoint.y, 12, 0, Math.PI * 2);
      ctx.stroke();
      ctx.fill();
      ctx.fillStyle = "#1f3d5f";
      ctx.font = "12px sans-serif";
      ctx.fillText(`${focus.label}（${focus.value ?? ""}）`, focusPoint.x + 14, focusPoint.y - 6);
    }
  }, [compiled.programID, grouped.grouped, isLayerVisible, normalizedView, bounds, imageLoaded, spec.coordinateMode, spec.mapAsset.kind, scaleBar, focus, isFeatureVisible]);

  const surfaceHeight = Math.max(280, Math.min(520, compiled.plan.qualityBudget.maxHeight ?? 380));

  useEffect(() => {
    const host = surfaceRef.current;
    if (!host) return;
    const resizeObserver = new ResizeObserver((entries) => {
      const entry = entries[0];
      if (entry) {
        const width = Math.max(220, Math.floor(entry.contentRect.width));
        const height = Math.max(1, Math.floor(entry.contentRect.height));
        setViewport({ width, height });
        setViewState((current) => ({ ...current, x: 0, y: 0 }));
      }
    });
    resizeObserver.observe(host);
    const rect = host.getBoundingClientRect();
    if (rect.width && rect.height) setViewport({ width: rect.width, height: rect.height });
    return () => resizeObserver.disconnect();
  }, [surfaceHeight]);

  useEffect(() => {
    const img = document.getElementById(`${compiled.programID}-weibei-spatial-bg`) as HTMLImageElement | null;
    if (!img) return;
    const onLoad = () => {
      setImageLoaded(true);
      setImageError(null);
      setStatusText("底图已就绪");
      draw();
      context.showNotice(`空间地图底图加载完成：${spec.mapAsset.label ?? "底图"}`);
    };
    const onError = () => {
      setImageLoaded(false);
      setImageError("底图加载失败：请检查 assetRef 或 data:image 是否可访问。");
      setStatusText("底图读取失败");
      draw();
    };
    img.addEventListener("load", onLoad);
    img.addEventListener("error", onError);
    if (img.complete && img.naturalWidth > 0) {
      onLoad();
    }
    return () => {
      img.removeEventListener("load", onLoad);
      img.removeEventListener("error", onError);
    };
  }, [compiled.programID, draw, spec.mapAsset.label]);

  useEffect(() => {
    draw();
  }, [draw, viewport.width, viewport.height, layerVisibility, viewState, spec.features.length, focus, bounds, spec.coordinateMode, spec.scaleBar.enabled, spec.scaleBar.targetPixels]);

  useEffect(() => {
    context.postMessage({
      type: "weibei:state",
      programID: compiled.programID,
      state: {
        renderer: SPATIAL_MAP_RENDERER,
        coordinateMode: spec.coordinateMode,
        crs: spec.coordinateMode === "geographic" ? (spec.crs ?? "WGS84") : "cartesian",
        bounds,
        layers: Object.entries(layerVisibility).map(([name, visible]) => ({ layer: name, visible })),
        view: {
          x: Number(viewState.x.toFixed(2)),
          y: Number(viewState.y.toFixed(2)),
          scale: Number(viewState.scale.toFixed(3)),
        },
        focus,
        source: spec.mapAsset.kind,
      },
    });
  }, [compiled.programID, context, spec.coordinateMode, spec.crs, layerVisibility, viewState.x, viewState.y, viewState.scale, focus, bounds]);

  const onWheel = useCallback((event: React.WheelEvent<HTMLCanvasElement>) => {
    if (!compiled.spec.controls.allowZoom) return;
    event.preventDefault();
    const step = event.deltaY > 0 ? -0.08 : 0.08;
    setViewState((current) => ({ ...current, scale: clamp(current.scale * (1 + step), 0.48, 4.2) }));
    setStatusText("已缩放");
  }, [compiled.spec.controls.allowZoom]);

  const onPointerDown = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!compiled.spec.controls.allowPan) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    setDragging(true);
    setDragStart({ x: event.clientX, y: event.clientY });
    setDragOrigin({ x: viewState.x, y: viewState.y });
    setStatusText("移动中");
  };

  const onPointerMove = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!dragging || !compiled.spec.controls.allowPan) return;
    const dx = event.clientX - dragStart.x;
    const dy = event.clientY - dragStart.y;
    setViewState((current) => ({ ...current, x: dragOrigin.x + dx / 1.1, y: dragOrigin.y + dy / 1.1 }));
  };

  const onPointerUp = () => {
    if (!dragging) return;
    setDragging(false);
    setStatusText("就绪");
  };

  const onDoubleClick = () => {
    if (!compiled.spec.controls.allowReset) return;
    setViewState({ x: 0, y: 0, scale: 1 });
    setStatusText("已重置");
    setTimeout(() => setStatusText("就绪"), 800);
  };

  const onCanvasClick = (event: React.MouseEvent<HTMLCanvasElement>) => {
    if (!compiled.spec.controls.probeEnabled) return;
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return;
    const cursor = { x: event.clientX - rect.left, y: event.clientY - rect.top };
    const baseCursor = spatialMapScreenToBase(cursor, buildScreenTransform(normalizedView));

    const candidates: Array<{ dist: number; target: Focus }> = [];

    const toCanvas = (pt: { x: number; y: number }) => {
      return mapToCanvas(pt, normalizedView, bounds, spec.coordinateMode);
    };

    for (const [layerID, items] of grouped.grouped.entries()) {
      if (!(layerVisibility[layerID] ?? grouped.layerDefaults[layerID] ?? true)) continue;
      for (const feature of items) {
        if (!isFeatureVisible(feature)) continue;
        if (feature.kind === "point") {
          const point = toCanvas({ x: feature.x, y: feature.y });
          const dist = pointDistance(point, baseCursor) * normalizedView.scale;
          if (dist < 22) {
            candidates.push({
              dist,
              target: {
                targetId: feature.id,
                kind: feature.kind,
                x: point.x,
                y: point.y,
                label: feature.label ?? feature.id,
                value: formatValue(feature.value),
              },
            });
          }
          continue;
        }
        if (feature.kind === "label") {
          const point = toCanvas({ x: feature.x, y: feature.y });
          const dist = pointDistance(point, baseCursor) * normalizedView.scale;
          if (dist < 20) {
            candidates.push({
              dist,
              target: {
                targetId: feature.id,
                kind: feature.kind,
                x: point.x,
                y: point.y,
                label: feature.text,
              },
            });
          }
          continue;
        }

        const points = feature.points.map((item) => toCanvas(item));
        const dist = feature.kind === "line"
          ? distancePointToPoints(points, baseCursor) * normalizedView.scale
          : (polygonContains(points, baseCursor) ? 0 : distancePointToPoints(points, baseCursor) * normalizedView.scale);
        if (dist <= 12) {
          const centroid = polygonCentroid(points);
          candidates.push({
            dist,
            target: {
              targetId: feature.id,
              kind: feature.kind,
              x: centroid.x,
              y: centroid.y,
              label: feature.label ?? feature.id,
              value: feature.value ? formatValue(feature.value) : feature.id,
            },
          });
        }
      }
    }

    candidates.sort((left, right) => left.dist - right.dist);
    const winner = candidates[0];
    setFocus(winner?.target ?? null);
  };

  useEffect(() => {
    const mapImage = mapSource
      ? document.getElementById(`${compiled.programID}-weibei-spatial-bg`) as HTMLImageElement | null
      : null;
    if (mapImage || spec.mapAsset.kind === "none") {
      draw();
      return;
    }
    if (!mapImage && mapSource) {
      const image = new Image();
      image.id = `${compiled.programID}-weibei-spatial-bg`;
      image.loading = "eager";
      image.referrerPolicy = "no-referrer";
      image.crossOrigin = "anonymous";
      image.src = mapSource;
      image.decoding = "async";
      image.draggable = false;
      image.onload = () => {
        imageLoaded || setImageLoaded(true);
        draw();
      };
      image.onerror = () => {
        setImageError("底图源无法解析，按示意底图展示");
        draw();
      };
      document.body.appendChild(image);
      return () => {
        image.onload = null;
        image.onerror = null;
        if (image.parentElement === document.body) {
          document.body.removeChild(image);
        }
      };
    }
  }, [compiled.programID, draw, mapSource, spec.mapAsset.kind, imageLoaded]);

  const handleLayerToggle = useCallback((layerId: string, visible: boolean) => {
    setLayerVisibility((prev) => ({ ...prev, [layerId]: visible }));
    setFocus(null);
    setStatusText(visible ? "图层已显示" : "图层已隐藏");
  }, []);

  const isNarrow = viewport.width > 0 && viewport.width < 560;
  const canvasHeight = Math.min(surfaceHeight, Math.max(isNarrow ? 240 : 280, viewport.width * (isNarrow ? 0.72 : 0.58)));

  return (
    <figure className="weibei-spatial-map" data-weibei-renderer={SPATIAL_MAP_RENDERER} style={{ margin: 0, width: "100%", minWidth: 0, color: "inherit", fontFamily: "inherit" }}>
      <header style={{ display: "grid", gap: 6, marginBottom: 8 }}>
        <h3 style={{ margin: 0, lineHeight: 1.35, fontSize: 14, fontWeight: 600 }}>{title}</h3>
        <p style={{ margin: 0, fontSize: 12, color: "rgba(32, 31, 28, 0.78)" }}>
          形态：{spec.coordinateMode === "geographic" ? "真实地理投影（WGS84 / Web Mercator 显示）" : "示意空间（不声明真实投影）"}；
          底图：{spec.mapAsset.kind === "none" ? "无本地底图" : "本地来源 asset"}；
          图层 {layers.length}；点位 {spec.features.filter((it) => it.kind === "point").length}；
          缩放 {viewState.scale.toFixed(2)}；状态 {statusText}
        </p>
      </header>

      {spec.mapAsset.kind !== "none" && mapSource ? (
        <img
          id={`${compiled.programID}-weibei-spatial-bg`}
          src={mapSource}
          alt={spec.mapAsset.label ?? "空间底图"}
          style={{ display: "none" }}
        />
      ) : null}

      {imageError ? (
        <div style={{ marginBottom: 8, fontSize: 12, color: "#8b4a4a", background: "rgba(255, 239, 239, 0.8)", padding: 8, borderRadius: 6 }}>
          {imageError}
        </div>
      ) : null}

      <section
        style={{
          width: "100%",
          border: "1px solid rgba(0,0,0,0.14)",
          borderRadius: 10,
          overflow: "hidden",
          background: "transparent",
          position: "relative",
        }}
      >
        <div
          ref={surfaceRef}
          onDoubleClick={onDoubleClick}
          style={{ width: "100%", height: `${canvasHeight}px` }}
        >
          <canvas
            ref={canvasRef}
            role="img"
            aria-label={title}
            onWheel={onWheel}
            onPointerDown={onPointerDown}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerLeave={onPointerUp}
            onClick={onCanvasClick}
            style={{ width: "100%", height: "100%", display: "block", cursor: dragging ? "grabbing" : "grab" }}
            data-weibei-control="spatial-map-probe"
            data-weibei-control-id={compiled.programID}
            data-weibei-state={JSON.stringify({
              state: "ok",
              view: viewState,
              focus,
              layers: Object.entries(layerVisibility).map(([id, visible]) => ({ id, visible })),
            })}
          />
        </div>
      </section>

      <section style={{ display: "grid", gap: 8, marginTop: 8 }}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center", flexDirection: isNarrow ? "column" : "row" }}>
          <strong style={{ fontSize: 12 }}>图层</strong>
          {layers.map((layer) => (
            <label key={layer.id} style={{
              display: "inline-flex",
              alignItems: "center",
              gap: 6,
              padding: "4px 8px",
              border: "1px solid rgba(0,0,0,0.14)",
              borderRadius: 999,
              background: "rgba(255,255,255,0.9)",
              fontSize: 12,
            }}>
              <input
                type="checkbox"
                checked={layerVisibility[layer.id] ?? layer.visible}
                onChange={(event) => handleLayerToggle(layer.id, event.currentTarget.checked)}
              />
              <span>{layer.title}</span>
            </label>
          ))}
          <button
            type="button"
            onClick={() => {
              setViewState({ x: 0, y: 0, scale: 1 });
              setStatusText("已重置");
            }}
            style={{
              marginLeft: isNarrow ? 0 : "auto",
              border: "1px solid rgba(0,0,0,0.15)",
              borderRadius: 6,
              background: "#ffffff",
              padding: "4px 8px",
              fontSize: "12px",
            }}
          >
            重置视图
          </button>
          <span style={{ fontSize: 12, color: "rgba(60,60,63,0.7)" }}>
            {spec.coordinateHint ? `坐标提示：${spec.coordinateHint}` : (spec.coordinateMode === "geographic" ? "坐标按经纬度投影显示，不等同外部瓦片地图。" : "坐标只表达示意关系，不代表真实经纬度。")}
          </span>
        </div>

        {focus ? (
          <div style={{ fontSize: 12, color: "rgba(36, 40, 52, 0.88)", display: "grid", gap: 4 }}>
            <strong>当前聚焦</strong>
            <div>对象：{focus.label}</div>
            <div>图层：{focus.kind}</div>
            {focus.value ? <div>数值：{focus.value}</div> : null}
            <div>坐标：x={focus.x.toFixed(1)} y={focus.y.toFixed(1)}</div>
          </div>
        ) : (
          <div style={{ fontSize: 12, color: "rgba(70, 70, 72, 0.72)", lineHeight: 1.4 }}>
            点击几何或点位查看焦点读数；双击画布重置视角。
          </div>
        )}

        {spec.caption ? <p style={{ margin: 0, fontSize: 12, color: "rgba(52, 48, 48, 0.8)" }}>{spec.caption}</p> : null}
      </section>
    </figure>
  );
}

export const spatialMapRenderer: RichAnswerRenderer = {
  id: SPATIAL_MAP_RENDERER,
  version: "0.1.0",
  capabilities: {
    renderer: SPATIAL_MAP_RENDERER,
    version: "0.1.0",
    specVersions: [SPATIAL_MAP_SPEC_VERSION],
    displayName: "空间地图",
    data: [
      "point-line-polygon",
      "layer-binding",
      "label-binding",
      "pan-zoom",
      "scale-bar",
      "coordinate-mode-schematic-geographic",
      "local-basemap",
      "probe",
    ],
    interactions: ["pan", "zoom", "toggle-layer", "probe", "double-tap-reset"],
    resources: ["canvas-2d", "local-assets", "self-check-spec"],
    maxNodes: 280,
    maxDataPoints: 3000,
    fallback: ["structured_error", "static_snapshot"],
  },
  validate(plan: RenderPlan) {
    const viewportCheck = runSpatialMapViewportSelfCheck();
    if (!viewportCheck.ok) {
      return {
        ok: false,
        issue: createRendererIssue(
          "validation_error",
          SPATIAL_MAP_RENDERER,
          `空间地图 CSS 像素坐标自检失败：${viewportCheck.cases.join("；")}`,
        ),
      };
    }
    const visibilityCheck = runSpatialMapVisibilitySelfCheck();
    if (!visibilityCheck.ok) {
      return {
        ok: false,
        issue: createRendererIssue(
          "validation_error",
          SPATIAL_MAP_RENDERER,
          `空间地图图层与标签绑定自检失败：${visibilityCheck.cases.join("；")}`,
        ),
      };
    }
    const parsed = parseSpatialMapSpec(plan);
    return parsed.ok ? { ok: true } : { ok: false, issue: parsed.issue };
  },
  compile(plan: RenderPlan, context) {
    const parsed = parseSpatialMapSpec(plan);
    if (!parsed.ok) return { ok: false, issue: parsed.issue };
    if (!plan.sourceBindings.length) {
      return {
        ok: false,
        issue: createRendererIssue(
          "validation_error",
          SPATIAL_MAP_RENDERER,
          "来源绑定缺失，空间地图需至少保留一个来源绑定用于学习追溯。",
        ),
      };
    }
    if (parsed.spec.coordinateMode === "geographic" && parsed.spec.mapAsset.kind === "assetRef") {
      context.showNotice("地理坐标场景已启用本地底图引用；渲染器不会加载外部瓦片或脚本。");
    }

    return {
      ok: true,
      compiled: {
        renderer: SPATIAL_MAP_RENDERER,
        version: SPATIAL_MAP_SPEC_VERSION,
        plan,
        programID: context.program.id,
        title: parsed.spec.title,
        spec: parsed.spec,
      },
    };
  },
  mount(compiled, context) {
    return <SpatialMapMount compiled={compiled as SpatialCompiled} context={context} />;
  },
  update(compiled, _previous, context) {
    return <SpatialMapMount compiled={compiled as SpatialCompiled} context={context} />;
  },
  dispose(_compiled, _context) {
    return undefined;
  },
  fallback(issue) {
    return <SpatialMapFallback issue={issue} />;
  },
};
