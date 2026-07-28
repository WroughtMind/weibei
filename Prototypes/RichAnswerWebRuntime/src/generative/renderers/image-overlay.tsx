import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type MouseEvent,
  type WheelEvent,
} from "react";
import type { ReactNode } from "react";
import type {
  CompiledRenderPlan,
  RenderPlan,
  RendererLifecycleContext,
  RichAnswerRenderer,
} from "../renderer-registry";
import {
  computeResponsiveImageOverlayViewport,
  computeObjectFitRect,
  computeImageOverlayFocusPolicy,
  computePointOnImage,
  createImageOverlayStateEvidence,
  formatMeasurement,
  imageOverlayAnnotationKey,
  imageOverlayFeatureKey,
  measurementUnitLabel,
  parseImageOverlaySpec,
  runImageOverlaySelfChecks,
  segmentLengthPxl,
  IMAGE_OVERLAY_RENDERER,
  IMAGE_OVERLAY_SPEC_VERSION,
  type ImageOverlayFeature,
  type ImageOverlaySpec,
} from "./image-overlay.self-check";

type ImageSource = ImageOverlaySpec["image"];

type CompiledImageOverlay = CompiledRenderPlan & {
  spec: ImageOverlaySpec;
};

type ViewRect = {
  left: number;
  top: number;
  width: number;
  height: number;
  scaleX: number;
  scaleY: number;
};

type LayerVisibilityMap = Record<string, boolean>;

type Annotation = ImageOverlaySpec["annotations"][number];

type PanState = { x: number; y: number };
type DragState = { x: number; y: number };
type MarkerMap = Record<string, string>;
type OverlayFocusPolicy = ReturnType<typeof computeImageOverlayFocusPolicy>;
type OverlayFeatureMode = "focus" | "context" | "muted";

const MIN_ZOOM = 0.45;
const MAX_ZOOM = 5;
const ZOOM_STEP = 0.12;

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function toSourceUrl(source: ImageSource) {
  return source.source;
}

function toViewModeLabel(mode: ImageOverlaySpec["objectFit"]) {
  if (mode === "contain") return "contain（完整显示）";
  if (mode === "cover") return "cover（铺满裁剪）";
  if (mode === "fill") return "fill（拉伸）";
  return "none（原始尺寸）";
}

function toViewportRect(
  viewport: { width: number; height: number },
  source: ImageSource,
  objectFit: ImageOverlaySpec["objectFit"],
  fallback: { width: number; height: number },
): ViewRect {
  const sourceWidth = Math.max(source.width ?? fallback.width, 1);
  const sourceHeight = Math.max(source.height ?? fallback.height, 1);
  return computeObjectFitRect(viewport.width, viewport.height, sourceWidth, sourceHeight, objectFit);
}

function toLocalContentRect(viewRect: ViewRect): ViewRect {
  return {
    left: 0,
    top: 0,
    width: viewRect.width,
    height: viewRect.height,
    scaleX: viewRect.scaleX,
    scaleY: viewRect.scaleY,
  };
}

function featureLabel(feature: ImageOverlayFeature): string {
  if (feature.label === undefined) return feature.id;
  if (feature.value !== undefined) {
    return `${feature.label}：${String(feature.value)}`;
  }
  return feature.label;
}

function featureKey(layerId: string, featureId: string) {
  return imageOverlayFeatureKey(layerId, featureId);
}

function imageOverlayLinePoints(feature: Extract<ImageOverlayFeature, { kind: "line" }>) {
  if (feature.points) return feature.points;
  if (feature.start && feature.end) return [feature.start, feature.end];
  return [];
}

function polylineLengthPxl(points: Array<{ x: number; y: number }>) {
  return points.slice(1).reduce(
    (sum, point, index) => sum + segmentLengthPxl(points[index]!, point),
    0,
  );
}

function annotationKey(annotationId: string) {
  return imageOverlayAnnotationKey(annotationId);
}

function buildMarkerMap(
  spec: ImageOverlaySpec,
  layerVisibility: LayerVisibilityMap,
  showAnnotations: boolean,
  focusPolicy?: OverlayFocusPolicy,
) {
  const markers: MarkerMap = {};
  let next = 1;
  const dense = focusPolicy?.dense ?? false;

  for (const layer of spec.layers) {
    const visible = layerVisibility[layer.id] ?? layer.visibleDefault;
    if (!visible) continue;
    for (const feature of layer.features) {
      const key = featureKey(layer.id, feature.id);
      if (dense && !focusPolicy?.focusedFeatureKeys.has(key)) continue;
      if (!feature.label && feature.value === undefined) continue;
      markers[key] = String(next);
      next += 1;
    }
  }

  if (showAnnotations) {
    for (const annotation of spec.annotations) {
      if (annotation.layer && !(layerVisibility[annotation.layer] ?? true)) continue;
      const key = annotationKey(annotation.id);
      if (dense && !focusPolicy?.focusedAnnotationKeys.has(key)) continue;
      markers[annotationKey(annotation.id)] = String(next);
      next += 1;
    }
  }

  return markers;
}

function alphaLimitFor(feature: ImageOverlayFeature) {
  if (feature.emphasis === "strong") return 0.9;
  if (feature.emphasis === "normal") return 0.72;
  return 0.58;
}

function withAlphaLimit(color: string, maxAlpha: number) {
  const rgba = color.match(/^rgba\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(0|1|0?\.\d+)\s*\)$/i);
  if (rgba) {
    return `rgba(${rgba[1]}, ${rgba[2]}, ${rgba[3]}, ${Math.min(Number(rgba[4]), maxAlpha)})`;
  }
  const rgb = color.match(/^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$/i);
  if (rgb) {
    return `rgba(${rgb[1]}, ${rgb[2]}, ${rgb[3]}, ${maxAlpha})`;
  }
  return color;
}

function overlayToneColor(feature: ImageOverlayFeature) {
  if (feature.style?.stroke) return feature.style.stroke;
  if (feature.tone === "neutral") return "rgba(55, 57, 60, 0.54)";
  if (feature.tone === "accent") return "rgba(31, 91, 132, 0.58)";
  if (feature.tone === "caution") return "rgba(148, 85, 32, 0.62)";
  return "rgba(96, 72, 58, 0.58)";
}

function overlayStroke(feature: ImageOverlayFeature) {
  return withAlphaLimit(overlayToneColor(feature), alphaLimitFor(feature));
}

function overlayFill(feature: ImageOverlayFeature) {
  if (feature.style?.fill) return feature.style.fill;
  if (feature.emphasis === "strong") return "rgba(156, 108, 82, 0.11)";
  if (feature.emphasis === "normal") return "rgba(156, 108, 82, 0.075)";
  return "rgba(156, 108, 82, 0.045)";
}

function overlayStrokeWidth(feature: ImageOverlayFeature) {
  if (feature.style?.strokeWidth !== undefined) {
    if (feature.emphasis === "strong") return Math.max(feature.style.strokeWidth, 0.5);
    if (feature.emphasis === "normal") return clamp(feature.style.strokeWidth, 0.5, 1.6);
    return clamp(feature.style.strokeWidth, 0.5, 1.15);
  }
  if (feature.emphasis === "strong") return 1.8;
  if (feature.emphasis === "normal") return 1.35;
  return 1.05;
}

function overlayFillOpacity(feature: ImageOverlayFeature, fallback: number) {
  if (feature.style?.opacity !== undefined) {
    if (feature.emphasis === "strong") return feature.style.opacity;
    if (feature.emphasis === "normal") return Math.min(feature.style.opacity, 0.14);
    return Math.min(feature.style.opacity, 0.075);
  }
  if (feature.emphasis === "strong") return Math.min(fallback, 0.14);
  if (feature.emphasis === "normal") return Math.min(fallback, 0.09);
  return Math.min(fallback, 0.055);
}

function overlayFeatureOpacity(feature: ImageOverlayFeature, mode: OverlayFeatureMode, dense: boolean) {
  if (mode === "focus") {
    if (feature.emphasis === "strong") return 1;
    if (feature.emphasis === "normal") return 0.9;
    return dense ? 0.78 : 0.86;
  }
  if (mode === "muted") {
    if (feature.emphasis === "strong") return 0.055;
    if (feature.emphasis === "normal") return 0.035;
    return 0.018;
  }
  if (feature.emphasis === "strong") return 0.22;
  if (feature.emphasis === "normal") return 0.11;
  return 0.055;
}

function overlayFeatureMode(
  key: string,
  layerId: string,
  focusPolicy: OverlayFocusPolicy,
): OverlayFeatureMode {
  if (!focusPolicy.dense) return "focus";
  if (focusPolicy.focusedFeatureKeys.has(key)) return "focus";
  return focusPolicy.activeLayerId === layerId ? "context" : "muted";
}

function labelBadgeNode({
  key,
  x,
  y,
  marker,
  color,
  emphasis = "subtle",
  mode = "focus",
  zoom,
  viewRect,
}: {
  key: string;
  x: number;
  y: number;
  marker: string | undefined;
  color: string;
  emphasis?: ImageOverlayFeature["emphasis"];
  mode?: OverlayFeatureMode;
  zoom: number;
  viewRect: ViewRect;
}) {
  if (!marker || mode !== "focus") return null;
  const radiusBase = emphasis === "strong" ? 9 : emphasis === "normal" ? 7.5 : 6.5;
  const radius = Math.max(5.5, radiusBase / Math.max(zoom, 0.75));
  const safeX = clamp(x, radius + 2, Math.max(radius + 2, viewRect.width - radius - 2));
  const safeY = clamp(y, radius + 2, Math.max(radius + 2, viewRect.height - radius - 2));
  const fontSize = Math.max(7.5, (emphasis === "strong" ? 10 : 8.5) / Math.max(zoom, 0.75));
  const badgeOpacity = emphasis === "strong" ? 0.88 : emphasis === "normal" ? 0.76 : 0.62;

  return (
    <g key={key} aria-label={`标注 ${marker}`}>
      <circle
        cx={safeX}
        cy={safeY}
        r={radius}
        fill={`rgba(255, 252, 246, ${badgeOpacity})`}
        stroke={color}
        strokeWidth={emphasis === "strong" ? 1.35 : 1}
        opacity={badgeOpacity}
        vectorEffect="non-scaling-stroke"
      />
      <text
        x={safeX}
        y={safeY + fontSize * 0.34}
        textAnchor="middle"
        fontSize={fontSize}
        fontWeight={emphasis === "strong" ? 700 : 650}
        fill={color}
        opacity={Math.min(1, badgeOpacity + 0.14)}
        style={{ userSelect: "none" }}
      >
        {marker}
      </text>
    </g>
  );
}

function largeRectCornerPath(x: number, y: number, width: number, height: number) {
  const tick = Math.min(26, Math.max(12, Math.min(width, height) * 0.16));
  return [
    `M${x} ${y + tick}L${x} ${y}L${x + tick} ${y}`,
    `M${x + width - tick} ${y}L${x + width} ${y}L${x + width} ${y + tick}`,
    `M${x + width} ${y + height - tick}L${x + width} ${y + height}L${x + width - tick} ${y + height}`,
    `M${x + tick} ${y + height}L${x} ${y + height}L${x} ${y + height - tick}`,
  ].join("");
}

function featureNodes(
  layerId: string,
  feature: ImageOverlayFeature,
  viewRect: ViewRect,
  layerVisible: boolean,
  specMeasurement: ImageOverlaySpec["measurement"],
  zoom: number,
  marker: string | undefined,
  mode: OverlayFeatureMode,
  dense: boolean,
): ReactNode[] {
  if (!layerVisible) return [];

  const pxStyle = {
    userSelect: "none" as const,
  };
  const keyBase = featureKey(layerId, feature.id);
  const stroke = overlayStroke(feature);
  const strokeWidth = overlayStrokeWidth(feature);
  const featureOpacity = overlayFeatureOpacity(feature, mode, dense);

  if (feature.kind === "point") {
    const p = computePointOnImage(feature.point, viewRect);
    return [
      <g key={keyBase} opacity={featureOpacity}>
      <circle
        key={keyBase}
        cx={p.x}
        cy={p.y}
        r={Math.max(3.2, strokeWidth * 2.1)}
        fill={feature.style?.fill ?? "rgba(255, 252, 246, 0.86)"}
        fillOpacity={feature.style?.opacity ?? (feature.emphasis === "strong" ? 0.84 : 0.58)}
        stroke={stroke}
        strokeWidth={strokeWidth}
        strokeDasharray={feature.style?.dash ? "4 4" : undefined}
        vectorEffect="non-scaling-stroke"
        style={pxStyle}
      >
        <title>{featureLabel(feature)}</title>
      </circle>
      {labelBadgeNode({ key: `${keyBase}-badge`, x: p.x + 13, y: p.y - 13, marker, color: stroke, emphasis: feature.emphasis, mode, zoom, viewRect })}
      </g>,
    ];
  }

  if (feature.kind === "line") {
    const linePoints = imageOverlayLinePoints(feature).map((point) => computePointOnImage(point, viewRect));
    if (linePoints.length < 2) return [];
    const len = polylineLengthPxl(linePoints);
    const displayValue = feature.value ?? formatMeasurement(len, specMeasurement);
    const middle = linePoints[Math.floor((linePoints.length - 1) / 2)]!;

    return [
      <g key={keyBase} opacity={featureOpacity}>
      <polyline
        key={keyBase}
        points={linePoints.map((point) => `${point.x},${point.y}`).join(" ")}
        fill="none"
        stroke={stroke}
        strokeWidth={strokeWidth}
        strokeDasharray={feature.style?.dash ? "5 7" : undefined}
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
        style={pxStyle}
      >
        <title>{featureLabel({ ...feature, value: displayValue })}</title>
      </polyline>
      {labelBadgeNode({ key: `${keyBase}-badge`, x: middle.x, y: middle.y - 12, marker, color: stroke, emphasis: feature.emphasis, mode, zoom, viewRect })}
      </g>,
    ];
  }

  if (feature.kind === "rect") {
    const origin = computePointOnImage({ x: feature.box.x, y: feature.box.y }, viewRect);
    const rectW = feature.box.width * viewRect.width;
    const rectH = feature.box.height * viewRect.height;
    const label = feature.value ?? `${formatMeasurement(rectW, specMeasurement)} × ${formatMeasurement(rectH, specMeasurement)}`;
    const largeRect = (rectW * rectH) / Math.max(1, viewRect.width * viewRect.height) > 0.46;
    const useCornerMarks = largeRect || (dense && mode === "context");

    return [
      <g key={keyBase} opacity={featureOpacity}>
      {useCornerMarks
        ? (
          <g>
            <rect
              x={origin.x}
              y={origin.y}
              width={rectW}
              height={rectH}
              fill={overlayFill(feature)}
              fillOpacity={overlayFillOpacity(feature, 0.12)}
            >
              <title>{featureLabel({ ...feature, value: label })}</title>
            </rect>
            <path
              d={largeRectCornerPath(origin.x, origin.y, rectW, rectH)}
              fill="none"
              stroke={stroke}
              strokeWidth={strokeWidth}
              strokeLinecap="round"
              vectorEffect="non-scaling-stroke"
              style={pxStyle}
            />
          </g>
        )
        : (
          <rect
            x={origin.x}
            y={origin.y}
            width={rectW}
            height={rectH}
            rx={4}
            fill={overlayFill(feature)}
            fillOpacity={overlayFillOpacity(feature, 0.16)}
            stroke={stroke}
            strokeWidth={strokeWidth}
            strokeDasharray={feature.style?.dash ? "5 7" : undefined}
            vectorEffect="non-scaling-stroke"
            style={pxStyle}
          >
            <title>{featureLabel({ ...feature, value: label })}</title>
          </rect>
        )}
      {labelBadgeNode({ key: `${keyBase}-badge`, x: origin.x + Math.min(rectW - 10, 15), y: origin.y + 15, marker, color: stroke, emphasis: feature.emphasis, mode, zoom, viewRect })}
      </g>,
    ];
  }

  const points = feature.points.map((point) => {
    const mapped = computePointOnImage(point, viewRect);
    return `${mapped.x},${mapped.y}`;
  }).join(" ");

  const perimeter = feature.points.reduce((sum, point, index) => {
    const next = feature.points[(index + 1) % feature.points.length]!;
    const a = computePointOnImage(point, viewRect);
    const b = computePointOnImage(next, viewRect);
    return sum + segmentLengthPxl(a, b);
  }, 0);
  const measure = feature.value ?? formatMeasurement(perimeter, specMeasurement);
  const firstPoint = computePointOnImage(feature.points[0]!, viewRect);

  return [
    <g key={keyBase} opacity={featureOpacity}>
    <polygon
      key={keyBase}
      points={points}
      fill={overlayFill(feature)}
      fillOpacity={overlayFillOpacity(feature, 0.12)}
      stroke={stroke}
      strokeWidth={strokeWidth}
      strokeDasharray={feature.style?.dash ? "5 7" : undefined}
      vectorEffect="non-scaling-stroke"
      style={pxStyle}
    >
      <title>{featureLabel({ ...feature, value: measure })}</title>
    </polygon>
    {labelBadgeNode({
      key: `${keyBase}-badge`,
      x: firstPoint.x + 16,
      y: firstPoint.y - 16,
      marker,
      color: stroke,
      emphasis: feature.emphasis,
      mode,
      zoom,
      viewRect,
    })}
    </g>,
  ];
}

function makeMeasureText(
  spec: ImageOverlaySpec,
  layers: ImageOverlaySpec["layers"],
  layerVisibility: LayerVisibilityMap,
  viewRect: ViewRect,
  markerMap: MarkerMap,
  focusPolicy?: OverlayFocusPolicy,
): string[] {
  const items: string[] = [];
  let omitted = 0;

  for (const layer of layers) {
    const visible = layerVisibility[layer.id] ?? layer.visibleDefault;
    if (!visible) continue;

    for (const feature of layer.features) {
      if (!feature.label) continue;
      const key = featureKey(layer.id, feature.id);
      if (focusPolicy?.dense && !focusPolicy.focusedFeatureKeys.has(key)) {
        omitted += 1;
        continue;
      }
      const marker = markerMap[key];
      const prefix = marker ? `${marker}. ` : "";

      if (feature.kind === "point") {
        const point = computePointOnImage(feature.point, viewRect);
        const value = feature.value !== undefined
          ? String(feature.value)
          : `位置 ${point.x.toFixed(0)}, ${point.y.toFixed(0)}`;
        items.push(`${prefix}${feature.label}：${value}`);
        continue;
      }
      if (feature.kind === "line") {
        const points = imageOverlayLinePoints(feature).map((point) => computePointOnImage(point, viewRect));
        if (points.length < 2) continue;
        items.push(
          `${prefix}${feature.label}：${feature.value ?? formatMeasurement(polylineLengthPxl(points), spec.measurement)}`,
        );
        continue;
      }
      if (feature.kind === "rect") {
        const w = viewRect.width * feature.box.width;
        const h = viewRect.height * feature.box.height;
        items.push(
          `${prefix}${feature.label}：${feature.value ?? `${formatMeasurement(w, spec.measurement)} × ${formatMeasurement(h, spec.measurement)}`}`,
        );
        continue;
      }
      if (feature.kind === "polygon") {
        const raw = feature.points.reduce((sum, point, i) => {
          const next = feature.points[(i + 1) % feature.points.length]!;
          const a = computePointOnImage(point, viewRect);
          const b = computePointOnImage(next, viewRect);
          return sum + segmentLengthPxl(a, b);
        }, 0);
        items.push(`${prefix}${feature.label}：${feature.value ?? formatMeasurement(raw, spec.measurement)}`);
      }
    }

    if (layer.annotation) {
      if (focusPolicy?.dense && !focusPolicy.focusedLayerIds.has(layer.id)) {
        omitted += 1;
        continue;
      }
      items.push(`${layer.title ?? layer.id} 说明：${layer.annotation}`);
    }
  }

  if (focusPolicy?.dense && omitted > 0) {
    const summary = `已弱化 ${omitted} 个背景标注；图层开关仍可逐层查看。`;
    return [...items.slice(0, Math.max(0, focusPolicy.maxReadoutItems - 1)), summary];
  }

  return focusPolicy ? items.slice(0, focusPolicy.maxReadoutItems) : items;
}

function annotationMarkerNodes(
  annotations: ReadonlyArray<Annotation>,
  viewRect: ViewRect,
  layerVisibility: LayerVisibilityMap,
  zoom: number,
  markerMap: MarkerMap,
  focusPolicy: OverlayFocusPolicy,
): ReactNode[] {
  return annotations
    .filter((annotation) => {
      if (!annotation.layer) return true;
      return layerVisibility[annotation.layer] ?? true;
    })
    .map((annotation) => {
      const pos = computePointOnImage(annotation.point, viewRect);
      const key = annotationKey(annotation.id);
      const focused = !focusPolicy.dense || focusPolicy.focusedAnnotationKeys.has(key);
      const activeContext = annotation.layer === focusPolicy.activeLayerId;
      const marker = focused ? markerMap[key] : undefined;
      return (
        <g key={annotation.id} opacity={focused ? 0.92 : activeContext ? 0.14 : 0.035}>
          <circle
            cx={pos.x}
            cy={pos.y}
            r={Math.max(2.5, 4.5 / Math.max(zoom, 0.5))}
            fill={annotation.color}
            stroke="rgba(255,255,255,0.95)"
            strokeWidth={Math.max(1, 2 / Math.max(zoom, 0.5))}
            opacity={0.95}
            vectorEffect="non-scaling-stroke"
          >
            <title>{annotation.text}</title>
          </circle>
          {labelBadgeNode({ key: `${annotation.id}-badge`, x: pos.x + 16, y: pos.y - 16, marker, color: annotation.color, mode: focused ? "focus" : "context", zoom, viewRect })}
        </g>
      );
    });
}

function ImageOverlayMount({
  compiled,
  context,
}: {
  compiled: CompiledImageOverlay;
  context: RendererLifecycleContext;
}) {
  const { spec, title = "图像观察" } = compiled;

  const containerRef = useRef<HTMLDivElement>(null);
  const imageRef = useRef<HTMLImageElement>(null);

  const [viewport, setViewport] = useState({ width: 0, height: 0 });
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageError, setImageError] = useState<string | null>(null);
  const [imageMetaSize, setImageMetaSize] = useState({
    width: Math.max(spec.image.width ?? 0, 320),
    height: Math.max(spec.image.height ?? 0, 240),
  });

  const [pan, setPan] = useState<PanState>({ x: 0, y: 0 });
  const [zoom, setZoom] = useState(1);
  const [isDragging, setIsDragging] = useState(false);
  const [dragStart, setDragStart] = useState<DragState>({ x: 0, y: 0 });
  const [panStart, setPanStart] = useState<PanState>({ x: 0, y: 0 });

  const [layerVisibility, setLayerVisibility] = useState<LayerVisibilityMap>(() => {
    const initial = {} as LayerVisibilityMap;
    for (const layer of spec.layers) {
      initial[layer.id] = layer.visibleDefault;
    }
    return initial;
  });
  const [activeLayerId, setActiveLayerId] = useState<string | null>(() => {
    return spec.layers.find((layer) => layer.visibleDefault)?.id ?? null;
  });

  const [showReadout, setShowReadout] = useState(spec.showReadout);
  const [showAnnotations, setShowAnnotations] = useState(true);
  const [compareValue, setCompareValue] = useState(spec.comparison?.ratio ?? 0.5);

  const imageSource = toSourceUrl(spec.image);
  const showCompare = Boolean(spec.comparison?.enabled && spec.comparison?.image.source);
  const comparisonSource = showCompare ? toSourceUrl(spec.comparison!.image) : null;
  const responsiveViewport = useMemo(() => {
    return computeResponsiveImageOverlayViewport(
      viewport.width || 360,
      imageMetaSize.width,
      imageMetaSize.height,
      compiled.plan.qualityBudget.maxHeight ?? 560,
    );
  }, [compiled.plan.qualityBudget.maxHeight, imageMetaSize.height, imageMetaSize.width, viewport.width]);

  useEffect(() => {
    if (!containerRef.current) return;

    const element = containerRef.current;
    const observer = new ResizeObserver((entries) => {
      const box = entries[0]?.contentRect;
      if (box) {
        setViewport({ width: Math.max(1, box.width), height: Math.max(220, box.height) });
      }
    });
    observer.observe(element);
    const box = element.getBoundingClientRect();
    setViewport({ width: Math.max(1, box.width), height: Math.max(220, box.height) });

    return () => {
      observer.disconnect();
    };
  }, []);

  useEffect(() => {
    const initialVisibility = {} as LayerVisibilityMap;
    for (const layer of spec.layers) {
      initialVisibility[layer.id] = layer.visibleDefault;
    }
    setLayerVisibility(initialVisibility);
    setActiveLayerId(spec.layers.find((layer) => layer.visibleDefault)?.id ?? null);
    setCompareValue(spec.comparison?.ratio ?? 0.5);
    setShowReadout(spec.showReadout);
    setShowAnnotations(true);
    setZoom(1);
    setPan({ x: 0, y: 0 });
  }, [spec.image.source, spec.comparison?.ratio, spec.layers, spec.showReadout]);

  const viewRect = useMemo<ViewRect>(() => {
    const safeViewport = {
      width: viewport.width || responsiveViewport.width,
      height: viewport.height || responsiveViewport.height,
    };
    return toViewportRect(safeViewport, spec.image, spec.objectFit, imageMetaSize);
  }, [viewport.height, viewport.width, responsiveViewport.height, responsiveViewport.width, spec.image.height, spec.image.width, spec.objectFit, imageMetaSize.height, imageMetaSize.width]);

  const contentRect = useMemo<ViewRect>(() => toLocalContentRect(viewRect), [viewRect.height, viewRect.scaleX, viewRect.scaleY, viewRect.width]);
  const focusPolicy = useMemo(() => computeImageOverlayFocusPolicy(
    spec,
    layerVisibility,
    showAnnotations,
    viewport.width || responsiveViewport.width,
    activeLayerId,
  ), [activeLayerId, layerVisibility, responsiveViewport.width, showAnnotations, spec, viewport.width]);
  const markerMap = useMemo(() => buildMarkerMap(spec, layerVisibility, showAnnotations, focusPolicy), [focusPolicy, layerVisibility, showAnnotations, spec]);

  const splitPx = useMemo(() => {
    if (!showCompare) return null;
    const safe = clamp(compareValue, 0.08, 0.92);
    return spec.comparison?.axis === "vertical" ? viewRect.width * safe : viewRect.height * safe;
  }, [compareValue, showCompare, spec.comparison?.axis, viewRect.height, viewRect.width]);

  const stageTransform = useMemo(() => `translate(${pan.x}px, ${pan.y}px) scale(${zoom})`, [pan.x, pan.y, zoom]);

  const featureGraphics = useMemo(() => {
    const nodes: ReactNode[] = [];

    for (const layer of spec.layers) {
      const visible = layerVisibility[layer.id] ?? layer.visibleDefault;
      for (const feature of layer.features) {
        nodes.push(...featureNodes(
          layer.id,
          feature,
          contentRect,
          visible,
          spec.measurement,
          zoom,
          showReadout ? markerMap[featureKey(layer.id, feature.id)] : undefined,
          overlayFeatureMode(featureKey(layer.id, feature.id), layer.id, focusPolicy),
          focusPolicy.dense,
        ));
      }
    }

    if (showAnnotations) {
      nodes.push(...annotationMarkerNodes(
        spec.annotations,
        contentRect,
        layerVisibility,
        zoom,
        showReadout ? markerMap : {},
        focusPolicy,
      ));
    }

    return nodes;
  }, [contentRect, focusPolicy, layerVisibility, markerMap, showAnnotations, showReadout, spec.annotations, spec.layers, spec.measurement, zoom]);

  const measurementList = useMemo(() => {
    const items = makeMeasureText(spec, spec.layers, layerVisibility, contentRect, markerMap, focusPolicy);

    if (showAnnotations) {
      for (const annotation of spec.annotations) {
        if (annotation.layer && !(layerVisibility[annotation.layer] ?? true)) {
          continue;
        }
        const key = annotationKey(annotation.id);
        if (focusPolicy.dense && !focusPolicy.focusedAnnotationKeys.has(key)) continue;
        const marker = markerMap[key];
        items.push(`${marker ? `${marker}. ` : ""}${annotation.text}`);
      }
    }

    return items.slice(0, focusPolicy.maxReadoutItems);
  }, [contentRect, focusPolicy, layerVisibility, markerMap, showAnnotations, spec.annotations, spec.layers, spec.measurement]);

  const comparisonLeft = showCompare && spec.comparison?.axis === "vertical";
  const comparisonTop = showCompare && spec.comparison?.axis === "horizontal";
  const splitScreenX = viewRect.left + pan.x + (comparisonLeft ? (splitPx ?? 0) * zoom : 0);
  const splitScreenY = viewRect.top + pan.y + (comparisonTop ? (splitPx ?? 0) * zoom : 0);
  const zoomedContentWidth = Math.max(0, viewRect.width * zoom);
  const stateEvidence = useMemo(() => createImageOverlayStateEvidence({
    spec,
    programID: compiled.programID,
    imageLoaded,
    imageError,
    viewport,
    viewRect,
    zoom,
    pan,
    layerVisibility,
    showReadout,
    showAnnotations,
    readoutItems: measurementList,
    compareValue,
    activeLayerId: focusPolicy.activeLayerId,
    focusedFeatureKeys: [...focusPolicy.focusedFeatureKeys],
    denseFocus: focusPolicy.dense,
  }), [
    focusPolicy,
    compareValue,
    compiled.programID,
    imageError,
    imageLoaded,
    layerVisibility,
    measurementList,
    pan,
    showAnnotations,
    showReadout,
    spec,
    viewport,
    viewRect,
    zoom,
  ]);
  const stateEvidenceText = useMemo(() => JSON.stringify(stateEvidence), [stateEvidence]);

  useEffect(() => {
    context.postMessage({
      type: "weibei:state",
      programID: compiled.programID,
      state: stateEvidence,
    });
  }, [compiled.programID, context, stateEvidence]);

  const onImageLoad = useCallback(() => {
    const image = imageRef.current;
    if (image?.naturalWidth && image.naturalHeight) {
      setImageMetaSize({ width: image.naturalWidth, height: image.naturalHeight });
      setImageLoaded(true);
      setImageError(null);
      setPan({ x: 0, y: 0 });
      setZoom(1);
      context.showNotice(`图像加载完成：${spec.image.label ?? "原图"}`);
    }
  }, [context, spec.image.label]);

  const onImageError = useCallback(() => {
    setImageError("图像加载失败，请检查 image source 是否是可读的 dataUrl 或本地 assetRef。请保留 base64 或本地路径");
    setImageLoaded(false);
  }, []);

  const handleMouseWheel = useCallback((event: WheelEvent<HTMLDivElement>) => {
    event.preventDefault();
    const rect = (event.currentTarget).getBoundingClientRect();
    const cursor = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };

    setZoom((current) => {
      const next = clamp(current * (1 + (event.deltaY < 0 ? ZOOM_STEP : -ZOOM_STEP)), MIN_ZOOM, MAX_ZOOM);
      if (next === current) return current;

      const ratio = next / current;
      setPan((prev) => ({
        x: cursor.x - (cursor.x - prev.x) * ratio,
        y: cursor.y - (cursor.y - prev.y) * ratio,
      }));
      return next;
    });
  }, []);

  const handlePointerDown = useCallback((event: MouseEvent<HTMLDivElement>) => {
    setIsDragging(true);
    setDragStart({ x: event.clientX, y: event.clientY });
    setPanStart(pan);
  }, [pan]);

  const handlePointerMove = useCallback((event: MouseEvent<HTMLDivElement>) => {
    if (!isDragging) return;

    const dx = event.clientX - dragStart.x;
    const dy = event.clientY - dragStart.y;
    setPan({ x: panStart.x + dx, y: panStart.y + dy });
  }, [dragStart.x, dragStart.y, isDragging, panStart.x, panStart.y]);

  const stopDrag = useCallback(() => {
    setIsDragging(false);
  }, []);

  const resetView = useCallback(() => {
    setZoom(1);
    setPan({ x: 0, y: 0 });
  }, []);

  const onToggleLayer = useCallback((layerId: string, visible: boolean) => {
    const nextVisibility = {
      ...layerVisibility,
      [layerId]: visible,
    };
    setLayerVisibility(nextVisibility);
    if (visible) {
      setActiveLayerId(layerId);
    } else if (activeLayerId === layerId) {
      setActiveLayerId(
        spec.layers.find((layer) => nextVisibility[layer.id] ?? layer.visibleDefault)?.id ?? null,
      );
    }
  }, [activeLayerId, layerVisibility, spec.layers]);

  const activeLayer = useMemo(
    () => spec.layers.find((layer) => layer.id === focusPolicy.activeLayerId) ?? null,
    [focusPolicy.activeLayerId, spec.layers],
  );

  const compareRatioPercent = Math.round(clamp(compareValue, 0.08, 0.92) * 100);

  return (
    <figure
      data-weibei-renderer={IMAGE_OVERLAY_RENDERER}
      data-weibei-control="image-overlay"
      data-weibei-control-id={compiled.programID}
      data-weibei-state={stateEvidenceText}
      style={{
        margin: 0,
        width: "100%",
        minWidth: 0,
        background: "transparent",
        color: "var(--weibei-fg, #1b1f23)",
        fontFamily: "inherit",
        display: "grid",
        gap: "8px",
      }}>
      <header style={{ display: "grid", gap: "6px" }}>
        <h3 style={{ margin: 0, fontSize: "14px", fontWeight: 600, lineHeight: 1.35 }}>{title}</h3>
        <p style={{ margin: 0, color: "rgba(27, 31, 35, 0.72)", fontSize: "12px", lineHeight: 1.45 }}>
          当前观察：{activeLayer?.title ?? "全部图层"}{focusPolicy.dense ? " · 其他图层已淡化" : ""} · 缩放 {String((zoom * 100).toFixed(0))}%
        </p>
        {activeLayer?.annotation ? (
          <p style={{ margin: 0, color: "rgba(27, 31, 35, 0.86)", fontSize: "12px", lineHeight: 1.5 }}>
            {activeLayer.annotation}
          </p>
        ) : null}
      </header>

      <div
        ref={containerRef}
        data-weibei-control="image-overlay-viewport"
        data-weibei-control-id={compiled.programID}
        data-weibei-state={stateEvidenceText}
        onWheel={handleMouseWheel}
        onMouseDown={handlePointerDown}
        onMouseMove={handlePointerMove}
        onMouseUp={stopDrag}
        onMouseLeave={stopDrag}
        style={{
          position: "relative",
          width: "100%",
          minHeight: "220px",
          height: `${responsiveViewport.height}px`,
          border: "1px solid rgba(0, 0, 0, 0.1)",
          borderRadius: "8px",
          overflow: "hidden",
          background: "transparent",
          cursor: isDragging ? "grabbing" : "grab",
          userSelect: "none",
        }}
      >
        {imageError ? (
          <div
            style={{
              position: "absolute",
              inset: 0,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              padding: "12px",
              color: "#8a2f2f",
              fontSize: "13px",
              background: "rgba(255, 245, 245, 0.92)",
              zIndex: 10,
            }}
          >
            {imageError}
          </div>
        ) : null}

        <div
          style={{
            position: "absolute",
            left: `${viewRect.left}px`,
            top: `${viewRect.top}px`,
            width: `${viewRect.width}px`,
            height: `${viewRect.height}px`,
            overflow: "hidden",
            touchAction: "none",
            boxShadow: "0 0 0 1px rgba(84, 70, 58, 0.08)",
          }}
        >
          <div
            style={{
              position: "relative",
              width: `${viewRect.width}px`,
              height: `${viewRect.height}px`,
              transform: stageTransform,
              transformOrigin: "0 0",
            }}
          >
            <div style={{ position: "absolute", inset: 0 }}>
              <img
                ref={imageRef}
                src={imageSource}
                alt={spec.image.label ?? "图像原图"}
                onLoad={onImageLoad}
                onError={onImageError}
                style={{
                  position: "absolute",
                  left: 0,
                  top: 0,
                  width: `${viewRect.width}px`,
                  height: `${viewRect.height}px`,
                  objectFit: "fill",
                  objectPosition: "left top",
                  userSelect: "none",
                  pointerEvents: "none",
                  opacity: imageLoaded || !spec.image.width ? 1 : 0,
                } as CSSProperties}
              />

              {showCompare && comparisonSource ? (
                <div
                  style={{
                    position: "absolute",
                    left: `${comparisonLeft ? splitPx ?? 0 : 0}px`,
                    top: `${comparisonTop ? splitPx ?? 0 : 0}px`,
                    width: `${Math.max(0, comparisonLeft ? viewRect.width - (splitPx ?? 0) : viewRect.width)}px`,
                    height: `${Math.max(0, comparisonTop ? viewRect.height - (splitPx ?? 0) : viewRect.height)}px`,
                    overflow: "hidden",
                  }}
                >
                  <img
                    src={comparisonSource}
                    alt={spec.comparison?.rightLabel ?? "对照图"}
                    style={{
                      position: "absolute",
                      left: `${comparisonLeft ? -(splitPx ?? 0) : 0}px`,
                      top: `${comparisonTop ? -(splitPx ?? 0) : 0}px`,
                      width: `${viewRect.width}px`,
                      height: `${viewRect.height}px`,
                      objectFit: "fill",
                      objectPosition: "left top",
                      userSelect: "none",
                      pointerEvents: "none",
                      opacity: imageLoaded || !spec.image.width ? 1 : 0,
                    } as CSSProperties}
                  />
                </div>
              ) : null}
            </div>

            <svg
              width={viewRect.width}
              height={viewRect.height}
              viewBox={`0 0 ${viewRect.width} ${viewRect.height}`}
              style={{ position: "absolute", inset: 0, overflow: "visible", pointerEvents: "none", background: "transparent" }}
            >
              {featureGraphics}
            </svg>
          </div>
        </div>

        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: 0,
            bottom: 0,
            pointerEvents: "none",
            border: "none",
          }}
        >
          {showCompare ? (
            <>
              <div
                style={{
                  position: "absolute",
                  left: `${comparisonLeft ? splitScreenX - 1 : viewRect.left + pan.x}px`,
                  top: `${comparisonTop ? splitScreenY - 1 : viewRect.top + pan.y}px`,
                  width: comparisonLeft ? "2px" : `${Math.max(0, viewRect.width * zoom)}px`,
                  height: comparisonTop ? "2px" : `${Math.max(0, viewRect.height * zoom)}px`,
                  background: "rgba(0, 0, 0, 0.45)",
                }}
              />
              <label
                style={{
                  position: "absolute",
                  left: `${comparisonLeft ? splitScreenX - 36 : viewRect.left + pan.x + zoomedContentWidth / 2 - 28}px`,
                  top: `${comparisonTop ? splitScreenY - 24 : viewRect.top + pan.y - 28}px`,
                  background: "rgba(255,255,255,0.85)",
                  border: "1px solid rgba(0,0,0,0.15)",
                  borderRadius: "999px",
                  padding: "2px 8px",
                  fontSize: "11px",
                  color: "rgba(0,0,0,0.72)",
                  pointerEvents: "none",
                }}
              >
                对照分界
              </label>
            </>
          ) : null}

          {showCompare ? (
            <input
              type="range"
              min={8}
              max={92}
              step={1}
              value={compareRatioPercent}
              onChange={(event) => setCompareValue(Number(event.target.value) / 100)}
              data-weibei-control="image-overlay-comparison"
              data-weibei-control-id={compiled.programID}
              data-weibei-state={JSON.stringify(stateEvidence.comparison)}
              style={{
                position: "absolute",
                left: `${viewRect.left + 8}px`,
                right: "8px",
                bottom: "8px",
                pointerEvents: "auto",
                width: `${Math.max(120, viewRect.width - 24)}px`,
              }}
              aria-label="图像对照滑杆"
            />
          ) : null}
        </div>
      </div>

      <section style={{ display: "grid", gap: "8px" }}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: "8px", alignItems: "center" }}>
          {spec.layers.map((layer) => {
            const visible = layerVisibility[layer.id] ?? layer.visibleDefault;
            const layerState = stateEvidence.layers.find((item) => item.id === layer.id);
            return (
              <div
                key={layer.id}
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: "4px",
                  padding: "3px 7px",
                  border: focusPolicy.activeLayerId === layer.id
                    ? "1px solid rgba(145, 69, 45, 0.48)"
                    : "1px solid rgba(0,0,0,0.13)",
                  borderRadius: "999px",
                  background: focusPolicy.activeLayerId === layer.id
                    ? "rgba(145, 69, 45, 0.09)"
                    : "rgba(255,255,255,0.72)",
                  fontSize: "12px",
                }}
              >
                <input
                  type="checkbox"
                  checked={visible}
                  onChange={(event) => onToggleLayer(layer.id, event.currentTarget.checked)}
                  data-weibei-control="image-overlay-layer"
                  data-weibei-control-id={layer.id}
                  data-weibei-state={JSON.stringify(layerState ?? { id: layer.id, visible })}
                  aria-label={`显示 ${layer.title ?? layer.id}`}
                />
                <button
                  type="button"
                  disabled={!visible}
                  onClick={() => setActiveLayerId(layer.id)}
                  data-weibei-control="image-overlay-layer-focus"
                  data-weibei-control-id={layer.id}
                  data-weibei-state={JSON.stringify(layerState ?? { id: layer.id, visible })}
                  style={{
                    border: 0,
                    padding: "1px 2px",
                    background: "transparent",
                    color: visible ? "inherit" : "rgba(27, 31, 35, 0.42)",
                    font: "inherit",
                    cursor: visible ? "pointer" : "default",
                  }}
                >
                  {layer.title ?? layer.id}
                </button>
              </div>
            );
          })}

          <label
            data-weibei-control="image-overlay-readout-toggle"
            data-weibei-control-id={compiled.programID}
            data-weibei-state={JSON.stringify(stateEvidence.readout)}
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: "6px",
              padding: "4px 8px",
              border: "1px solid rgba(0,0,0,0.15)",
              borderRadius: "999px",
              background: "rgba(255,255,255,0.82)",
              fontSize: "12px",
            }}
          >
            <input
              type="checkbox"
              checked={showReadout}
              onChange={(event) => setShowReadout(event.currentTarget.checked)}
            />
            <span>显示测量/说明</span>
          </label>

          <label
            data-weibei-control="image-overlay-annotation-toggle"
            data-weibei-control-id={compiled.programID}
            data-weibei-state={JSON.stringify(stateEvidence.annotations)}
            style={{
              display: "inline-flex",
              alignItems: "center",
              gap: "6px",
              padding: "4px 8px",
              border: "1px solid rgba(0,0,0,0.15)",
              borderRadius: "999px",
              background: "rgba(255,255,255,0.82)",
              fontSize: "12px",
            }}
          >
            <input
              type="checkbox"
              checked={showAnnotations}
              onChange={(event) => setShowAnnotations(event.currentTarget.checked)}
            />
            <span>显示批注</span>
          </label>

          <button
            type="button"
            onClick={resetView}
            data-weibei-control="image-overlay-reset-view"
            data-weibei-control-id={compiled.programID}
            data-weibei-state={JSON.stringify(stateEvidence.transform)}
            style={{
              marginLeft: "auto",
              border: "1px solid rgba(0,0,0,0.16)",
              borderRadius: "6px",
              background: "#ffffff",
              padding: "4px 8px",
              fontSize: "12px",
            }}
          >
            重置视图
          </button>
        </div>

        {showReadout && measurementList.length ? (
          <ul
            data-weibei-control="image-overlay-readout"
            data-weibei-control-id={compiled.programID}
            data-weibei-state={JSON.stringify(stateEvidence.readout)}
            style={{
              margin: 0,
              padding: 0,
              listStyle: "none",
              display: "grid",
              gridTemplateColumns: focusPolicy.narrow ? "1fr" : "repeat(auto-fit, minmax(170px, 1fr))",
              gap: "6px",
              lineHeight: 1.42,
              fontSize: "12px",
            }}
          >
            {measurementList.map((item) => (
              <li
                key={item}
                style={{
                  minWidth: 0,
                  padding: "6px 8px",
                  border: "1px solid rgba(84, 70, 58, 0.13)",
                  borderRadius: "8px",
                  background: "rgba(255, 252, 246, 0.56)",
                  overflowWrap: "anywhere",
                }}
              >
                {item}
              </li>
            ))}
          </ul>
        ) : null}

        {spec.caption ? (
          <p style={{ margin: 0, fontSize: "12px", color: "rgba(0,0,0,0.68)" }}>
            {spec.caption}
          </p>
        ) : null}
      </section>
    </figure>
  );
}

function ImageOverlayFallback({
  issue,
}: {
  issue: { code: string; renderer: string; message: string; details?: string[] };
}) {
  return (
    <div
      className="generation-error"
      role="alert"
      data-weibei-renderer-issue={issue.code}
      style={{
        padding: "12px",
        border: "1px dashed rgba(139, 20, 20, 0.35)",
        borderRadius: "8px",
        background: "rgba(255, 245, 245, 0.95)",
      }}
    >
      <strong>{issue.code === "capability_mismatch" ? "渲染器能力不匹配" : "图像覆盖渲染未通过"}</strong>
      <p style={{ margin: "6px 0 0" }}>{issue.message}</p>
      {issue.details?.length ? <small>{issue.details.join("；")}</small> : null}
    </div>
  );
}

export const imageOverlayRenderer: RichAnswerRenderer = {
  id: IMAGE_OVERLAY_RENDERER,
  version: "0.1.0",
  capabilities: {
    renderer: IMAGE_OVERLAY_RENDERER,
    version: "0.1.0",
    specVersions: [IMAGE_OVERLAY_SPEC_VERSION],
    displayName: "图像覆盖观察",
    data: [
      "image-overlay",
      "measurement",
      "compare-image",
      "label-layer-binding",
      "pan-zoom",
      "annotation-marker",
    ],
    interactions: ["pan", "zoom", "toggle-layer", "toggle-annotation", "switch-comparison", "reset-view"],
    resources: ["react-svg"],
    maxNodes: 180,
    maxDataPoints: 1200,
    fallback: ["structured_error", "simplified_component"],
  },
  validate(plan) {
    const selfCheck = runImageOverlaySelfChecks();
    if (!selfCheck.ok) {
      return {
        ok: false,
        issue: {
          code: "validation_error",
          renderer: IMAGE_OVERLAY_RENDERER,
          message: `图像覆盖响应式自检失败：${selfCheck.cases.filter((item) => !item.ok).map((item) => item.name).join("；")}`,
        },
      };
    }
    const parsed = parseImageOverlaySpec(plan);
    return parsed.ok === false ? { ok: false, issue: parsed.issue } : { ok: true };
  },
  compile(plan, context) {
    const parsed = parseImageOverlaySpec(plan);
    if (parsed.ok === false) return { ok: false, issue: parsed.issue };

    return {
      ok: true,
      compiled: {
        renderer: IMAGE_OVERLAY_RENDERER,
        version: IMAGE_OVERLAY_SPEC_VERSION,
        plan,
        programID: context.program.id,
        title: parsed.spec.title ?? "图像观察",
        spec: parsed.spec,
      },
    };
  },
  mount(compiled, context) {
    return <ImageOverlayMount compiled={compiled as CompiledImageOverlay} context={context} />;
  },
  update(compiled, _previous, context) {
    return <ImageOverlayMount compiled={compiled as CompiledImageOverlay} context={context} />;
  },
  dispose() {
    return undefined;
  },
  fallback(issue) {
    return <ImageOverlayFallback issue={issue} />;
  },
};
