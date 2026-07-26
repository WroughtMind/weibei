import { z } from "zod/v4";
import {
  createRendererIssue,
  type RenderPlan,
} from "../renderer-registry";

export const IMAGE_OVERLAY_RENDERER = "weibei.image.overlay";
export const IMAGE_OVERLAY_SPEC_VERSION = "weibei.image-overlay.v1";

const maxLayers = 32;
const maxAnnotations = 80;
const maxFeaturesPerLayer = 128;
const maxEmbeddedImageSourceLength = 1_500_000;
const finiteNumber = z.number().refine(Number.isFinite, "必须是有限数字");
const finitePositive = finiteNumber.refine((value) => value > 0, "必须是大于 0 的有限数");
const color = z.string().min(4).max(40).regex(/^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$|^rgba?\(\s*(?:\d{1,3}\s*,\s*){2}\d{1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$/, "颜色必须是 hex 或 rgb(a)");
const identifier = z.string().min(1).max(80);
const objectFit = z.enum(["contain", "cover", "fill", "none"]);
const orientation = z.enum(["vertical", "horizontal"]);
const overlayEmphasis = z.enum(["subtle", "normal", "strong"]);
const overlayTone = z.enum(["earth", "neutral", "accent", "caution"]);
const safeRasterAssetPath = /^[a-zA-Z0-9._/@:\-]+(?:\/[a-zA-Z0-9._@:\-]+)*\.(?:png|jpg|jpeg|webp|gif)$/i;

const imagePointSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
}).strict();

const imageRectSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
  width: z.number().min(0).max(1),
  height: z.number().min(0).max(1),
}).strict().superRefine((value, context) => {
  if (value.width <= 0) context.addIssue({ code: "custom", message: "矩形 width 必须大于 0", path: ["width"] });
  if (value.height <= 0) context.addIssue({ code: "custom", message: "矩形 height 必须大于 0", path: ["height"] });
  if (value.x + value.width > 1.0001) context.addIssue({ code: "custom", message: "矩形 x+width 不能超出 [0,1]", path: ["x"] });
  if (value.y + value.height > 1.0001) context.addIssue({ code: "custom", message: "矩形 y+height 不能超出 [0,1]", path: ["y"] });
});

const measureScaleSchema = z.object({
  unit: z.string().min(1).max(24).default("px"),
  pxPerUnit: finitePositive.optional(),
  precision: z.number().int().min(0).max(8).default(2),
}).strict();

const styleSchema = z.object({
  stroke: color.default("rgba(84, 70, 58, 0.9)"),
  strokeWidth: z.number().min(0.5).max(8).default(2),
  fill: z.union([z.literal("transparent"), color]).default("transparent"),
  opacity: z.number().min(0).max(1).default(0.65),
  dash: z.boolean().default(false),
}).strict();

const overlayPointSchema = z.object({
  id: identifier,
  kind: z.literal("point"),
  label: z.string().min(1).max(80).optional(),
  point: imagePointSchema,
  emphasis: overlayEmphasis.default("subtle"),
  tone: overlayTone.default("earth"),
  style: styleSchema.optional(),
  value: z.union([z.string(), finiteNumber]).optional(),
}).strict();

const overlayLineSchema = z.object({
  id: identifier,
  kind: z.literal("line"),
  label: z.string().min(1).max(80).optional(),
  start: imagePointSchema.optional(),
  end: imagePointSchema.optional(),
  points: z.array(imagePointSchema).min(2).max(64).optional(),
  emphasis: overlayEmphasis.default("subtle"),
  tone: overlayTone.default("earth"),
  style: styleSchema.optional(),
  value: z.union([z.string(), finiteNumber]).optional(),
}).strict().superRefine((value, context) => {
  const hasSegment = value.start !== undefined || value.end !== undefined;
  const hasPolyline = value.points !== undefined;
  if (hasSegment && hasPolyline) {
    context.addIssue({ code: "custom", message: "line 不能同时提交 start/end 与 points" });
  } else if (hasSegment && (!value.start || !value.end)) {
    context.addIssue({ code: "custom", message: "线段必须同时提交 start 与 end" });
  } else if (!hasSegment && !hasPolyline) {
    context.addIssue({ code: "custom", message: "line 必须提交 start/end 或至少两个 points" });
  }
});

const overlayRectSchema = z.object({
  id: identifier,
  kind: z.literal("rect"),
  label: z.string().min(1).max(80).optional(),
  box: imageRectSchema,
  emphasis: overlayEmphasis.default("subtle"),
  tone: overlayTone.default("earth"),
  style: styleSchema.optional(),
  value: z.union([z.string(), finiteNumber]).optional(),
}).strict();

const overlayPolygonSchema = z.object({
  id: identifier,
  kind: z.literal("polygon"),
  label: z.string().min(1).max(80).optional(),
  points: z.array(imagePointSchema).min(3).max(64),
  emphasis: overlayEmphasis.default("subtle"),
  tone: overlayTone.default("earth"),
  style: styleSchema.optional(),
  value: z.union([z.string(), finiteNumber]).optional(),
}).strict();

const overlaySchema = z.discriminatedUnion("kind", [
  overlayPointSchema,
  overlayLineSchema,
  overlayRectSchema,
  overlayPolygonSchema,
]);

type _ImageOverlayFeature = z.infer<typeof overlaySchema>;

const layerSchema = z.object({
  id: identifier,
  title: z.string().min(1).max(100).optional(),
  visibleDefault: z.boolean().default(true),
  features: z.array(overlaySchema).min(1).max(maxFeaturesPerLayer),
  annotation: z.string().max(300).optional(),
}).strict();

const annotationSchema = z.object({
  id: identifier,
  point: imagePointSchema,
  text: z.string().min(1).max(260),
  color: color.default("rgba(84, 70, 58, 0.95)"),
  layer: identifier.optional(),
}).strict();

const imageSourceSchema = z.object({
  source: z.string().min(1).max(maxEmbeddedImageSourceLength),
  kind: z.union([z.literal("dataUrl"), z.literal("assetRef")]).default("dataUrl"),
  label: z.string().min(1).max(80).optional(),
  width: z.number().int().min(16).max(12000).optional(),
  height: z.number().int().min(16).max(12000).optional(),
}).strict();

const comparisonSchema = z.object({
  enabled: z.boolean().default(false),
  image: imageSourceSchema,
  ratio: z.number().min(0.1).max(0.9).default(0.5),
  axis: orientation.default("vertical"),
  leftLabel: z.string().min(1).max(80).default("原图"),
  rightLabel: z.string().min(1).max(80).default("对比"),
}).strict();

const imageOverlaySpecSchema = z.object({
  title: z.string().min(1).max(140).optional(),
  image: imageSourceSchema,
  objectFit: objectFit.default("contain"),
  measurement: measureScaleSchema.partial().default({}),
  layers: z.array(layerSchema).max(maxLayers),
  annotations: z.array(annotationSchema).max(maxAnnotations).default([]),
  comparison: comparisonSchema.optional(),
  caption: z.string().min(1).max(260).optional(),
  showReadout: z.boolean().default(true),
}).strict();

export type ImageOverlaySpec = z.infer<typeof imageOverlaySpecSchema>;
export type ImageOverlayLayer = z.infer<typeof layerSchema>;
export type ImageOverlayFeature = _ImageOverlayFeature;
export type ImageOverlayStateEvidence = ReturnType<typeof createImageOverlayStateEvidence>;

type CheckResult =
  | { ok: true; spec: ImageOverlaySpec }
  | { ok: false; issue: ReturnType<typeof createRendererIssue> };

export function parseImageOverlaySpec(plan: RenderPlan): CheckResult {
  const result = imageOverlaySpecSchema.safeParse(plan.spec);
  if (!result.success) {
    return {
      ok: false,
      issue: createRendererIssue(
        "validation_error",
        plan.renderer,
        result.error.issues[0]?.message ?? "图像覆盖规格不符合协议。",
        result.error.issues.map((item) => item.path.join(".")).filter(Boolean),
      ),
    };
  }

  const semanticIssue = guardImageOverlayPlan(plan, result.data);
  if (semanticIssue) return { ok: false, issue: semanticIssue };
  return { ok: true, spec: result.data };
}

function guardImageOverlayPlan(plan: RenderPlan, spec: ImageOverlaySpec) {
  if (plan.renderer !== IMAGE_OVERLAY_RENDERER) {
    return createRendererIssue("capability_mismatch", plan.renderer, `图像覆盖渲染器不能渲染 ${plan.renderer}。`);
  }
  if (plan.specVersion !== IMAGE_OVERLAY_SPEC_VERSION) {
    return createRendererIssue("capability_mismatch", plan.renderer, `图像覆盖渲染器只支持 ${IMAGE_OVERLAY_SPEC_VERSION}。`);
  }
  if (plan.qualityBudget.allowNetwork) {
    return createRendererIssue("capability_mismatch", plan.renderer, "图像覆盖渲染器不允许请求网络资源。请使用本地素材或已内嵌素材。 ");
  }
  if (plan.qualityBudget.allowWebGL) {
    return createRendererIssue("capability_mismatch", plan.renderer, "图像覆盖渲染器不使用 WebGL。" );
  }

  const sourceIssue = validateImageSource(plan, spec.image);
  if (sourceIssue) return sourceIssue;

  if (spec.comparison?.enabled) {
    const compareIssue = validateImageSource(plan, spec.comparison.image);
    if (compareIssue) return compareIssue;
  }

  const layerIds = new Set<string>();
  for (const layer of spec.layers) {
    if (layerIds.has(layer.id)) {
      return createRendererIssue("validation_error", plan.renderer, `图层 id 重复：${layer.id}。`);
    }
    layerIds.add(layer.id);
    const featureIds = new Set<string>();
    for (const feature of layer.features) {
      if (featureIds.has(feature.id)) {
        return createRendererIssue("validation_error", plan.renderer, `图层 ${layer.id} 中存在重复图形 id：${feature.id}。`);
      }
      featureIds.add(feature.id);
      if (!isNormalizedValue(feature)) {
        return createRendererIssue("validation_error", plan.renderer, `${feature.kind} 形状坐标超出 [0, 1]。`);
      }
    }
  }

  if (!spec.layers.length && !spec.annotations.length) {
    return createRendererIssue("validation_error", plan.renderer, "当前场景至少要有一个图层或一个批注。图像叠加需要可交互内容。 ");
  }

  return null;
}

function validateImageSource(plan: RenderPlan, source: { kind: "dataUrl" | "assetRef"; source: string }) {
  const raw = source.source.trim();

  if (source.kind === "dataUrl") {
    if (!/^data:image\/(?:png|jpeg|jpg|webp|gif);base64,/i.test(raw)) {
      return createRendererIssue("validation_error", plan.renderer, "图像源必须是 raster 图片 base64 data URL，不能使用 SVG、HTML 或脚本型内容。 ");
    }
    if (raw.length > maxEmbeddedImageSourceLength) {
      return createRendererIssue("validation_error", plan.renderer, "图像数据过大，建议压缩后再提交。 ");
    }
    return null;
  }

  const lowered = raw.toLowerCase();
  if (/^(?:https?:)?\/\//.test(lowered) || lowered.startsWith("javascript:") || lowered.startsWith("data:")) {
    return createRendererIssue("capability_mismatch", plan.renderer, "图像源不得使用外链、javascript 或伪装 data URL。请改为 artifact 引用或内嵌安全 raster data URL。 ");
  }

  if (!raw) {
    return createRendererIssue("validation_error", plan.renderer, "图像 assetRef 不能为空。");
  }

  if (!safeRasterAssetPath.test(raw)) {
    return createRendererIssue("validation_error", plan.renderer, "图像 assetRef 只能引用本地 raster 图片路径。");
  }

  return null;
}

function isNormalizedValue(feature: ImageOverlayFeature) {
  if (feature.kind === "point") return inUnitRange(feature.point);
  if (feature.kind === "line") {
    if (feature.points) return feature.points.every(inUnitRange);
    return feature.start !== undefined && feature.end !== undefined
      && inUnitRange(feature.start) && inUnitRange(feature.end);
  }
  if (feature.kind === "rect") return inUnitRange({ x: feature.box.x, y: feature.box.y }) && inUnitRange({ x: feature.box.x + feature.box.width, y: feature.box.y + feature.box.height });
  return feature.points.every(inUnitRange);
}

export function inUnitRange(point: { x: number; y: number }) {
  return Number.isFinite(point.x) && Number.isFinite(point.y) && point.x >= -0.02 && point.x <= 1.02 && point.y >= -0.02 && point.y <= 1.02;
}

export function createPoint(x: number, y: number) {
  return { x, y };
}

export function imageOverlayFeatureKey(layerId: string, featureId: string) {
  return `${layerId}:${featureId}`;
}

export function imageOverlayAnnotationKey(annotationId: string) {
  return `annotation:${annotationId}`;
}

function imageOverlayEmphasisScore(feature: ImageOverlayFeature) {
  if (feature.emphasis === "strong") return 3;
  if (feature.emphasis === "normal") return 2;
  return 1;
}

export function computeImageOverlayFocusPolicy(
  spec: ImageOverlaySpec,
  layerVisibility: Record<string, boolean>,
  showAnnotations: boolean,
  viewportWidth: number,
  preferredLayerId?: string | null,
) {
  const visibleFeatures: Array<{
    key: string;
    layerId: string;
    layerIndex: number;
    featureIndex: number;
    feature: ImageOverlayFeature;
  }> = [];
  const visibleLayerIds: string[] = [];

  spec.layers.forEach((layer, layerIndex) => {
    const visible = layerVisibility[layer.id] ?? layer.visibleDefault;
    if (!visible) return;
    visibleLayerIds.push(layer.id);
    layer.features.forEach((feature, featureIndex) => {
      visibleFeatures.push({
        key: imageOverlayFeatureKey(layer.id, feature.id),
        layerId: layer.id,
        layerIndex,
        featureIndex,
        feature,
      });
    });
  });

  const visibleAnnotations = showAnnotations
    ? spec.annotations.filter((annotation) => {
        if (!annotation.layer) return true;
        return layerVisibility[annotation.layer] ?? true;
      })
    : [];

  const visibleItemCount = visibleFeatures.length + visibleAnnotations.length;
  const narrow = viewportWidth < 460;
  const medium = viewportWidth < 680;
  const denseLimit = narrow ? 5 : medium ? 8 : 10;
  const maxFocus = narrow ? 3 : medium ? 4 : 5;
  const dense = visibleItemCount > denseLimit
    || (visibleLayerIds.length > 1 && visibleItemCount > maxFocus);
  const focusedFeatureKeys = new Set<string>();
  const activeLayerId = visibleLayerIds.includes(preferredLayerId ?? "")
    ? preferredLayerId ?? null
    : visibleLayerIds[0] ?? null;

  if (!dense) {
    for (const item of visibleFeatures) focusedFeatureKeys.add(item.key);
  } else {
    const sorted = [...visibleFeatures].sort((a, b) => {
      const scoreDiff = imageOverlayEmphasisScore(b.feature) - imageOverlayEmphasisScore(a.feature);
      if (scoreDiff !== 0) return scoreDiff;
      if (a.layerIndex !== b.layerIndex) return a.layerIndex - b.layerIndex;
      return a.featureIndex - b.featureIndex;
    });

    const activeCandidates = activeLayerId
      ? sorted.filter((item) => item.layerId === activeLayerId)
      : sorted;

    for (const item of activeCandidates) {
      if (focusedFeatureKeys.size >= maxFocus) break;
      if (item.feature.emphasis === "strong") focusedFeatureKeys.add(item.key);
    }

    for (const item of activeCandidates) {
      if (focusedFeatureKeys.size >= maxFocus) break;
      focusedFeatureKeys.add(item.key);
    }
  }

  const focusedLayerIds = new Set(activeLayerId ? [activeLayerId] : []);
  const maxFocusedAnnotations = narrow ? 1 : medium ? 2 : 2;
  const focusedAnnotationKeys = new Set<string>();
  for (const annotation of visibleAnnotations) {
    if (!dense || !annotation.layer || focusedLayerIds.has(annotation.layer)) {
      focusedAnnotationKeys.add(imageOverlayAnnotationKey(annotation.id));
    }
    if (dense && focusedAnnotationKeys.size >= maxFocusedAnnotations) break;
  }

  return {
    dense,
    narrow,
    activeLayerId,
    maxFocus,
    visibleFeatureCount: visibleFeatures.length,
    visibleAnnotationCount: visibleAnnotations.length,
    focusedFeatureKeys,
    focusedAnnotationKeys,
    focusedLayerIds,
    maxReadoutItems: narrow ? 3 : medium ? 4 : 5,
  };
}

export function computeObjectFitRect(
  containerWidth: number,
  containerHeight: number,
  sourceWidth: number,
  sourceHeight: number,
  mode: "contain" | "cover" | "fill" | "none",
) {
  const safeContainerWidth = Math.max(1, containerWidth);
  const safeContainerHeight = Math.max(1, containerHeight);
  const safeSourceWidth = Math.max(1, sourceWidth);
  const safeSourceHeight = Math.max(1, sourceHeight);

  if (mode === "fill") {
    return {
      left: 0,
      top: 0,
      width: safeContainerWidth,
      height: safeContainerHeight,
      scaleX: safeContainerWidth / safeSourceWidth,
      scaleY: safeContainerHeight / safeSourceHeight,
    };
  }

  if (mode === "none") {
    return {
      left: (safeContainerWidth - safeSourceWidth) / 2,
      top: (safeContainerHeight - safeSourceHeight) / 2,
      width: safeSourceWidth,
      height: safeSourceHeight,
      scaleX: 1,
      scaleY: 1,
    };
  }

  const ratioW = safeContainerWidth / safeSourceWidth;
  const ratioH = safeContainerHeight / safeSourceHeight;
  const scale = mode === "contain" ? Math.min(ratioW, ratioH) : Math.max(ratioW, ratioH);
  const width = safeSourceWidth * scale;
  const height = safeSourceHeight * scale;
  return {
    left: (safeContainerWidth - width) / 2,
    top: (safeContainerHeight - height) / 2,
    width,
    height,
    scaleX: scale,
    scaleY: scale,
  };
}

function clampNumber(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

export function computeResponsiveImageOverlayViewport(
  containerWidth: number,
  sourceWidth: number,
  sourceHeight: number,
  maxHeight = 560,
) {
  const width = Math.max(240, Math.round(containerWidth || 360));
  const safeSourceWidth = Math.max(1, sourceWidth || width);
  const safeSourceHeight = Math.max(1, sourceHeight || Math.round(width * 0.68));
  const aspectRatio = safeSourceWidth / safeSourceHeight;
  const naturalHeight = width / aspectRatio;
  const minHeight = width < 380 ? 220 : 240;
  const safeMaxHeight = Math.max(minHeight, Math.min(maxHeight, width < 420 ? 520 : 620));
  const height = Math.round(clampNumber(naturalHeight, minHeight, safeMaxHeight));

  return { width, height, aspectRatio };
}

export function computePointOnImage(
  point: { x: number; y: number },
  rect: { left: number; top: number; width: number; height: number },
) {
  return {
    x: rect.left + point.x * rect.width,
    y: rect.top + point.y * rect.height,
  };
}

export function segmentLengthPxl(a: { x: number; y: number }, b: { x: number; y: number }) {
  const dx = a.x - b.x;
  const dy = a.y - b.y;
  return Math.hypot(dx, dy);
}

export function formatMeasurement(value: number, measure: ImageOverlaySpec["measurement"]) {
  const pxPerUnit = measure.pxPerUnit;
  const precision = measure.precision ?? 2;
  const label = measure.unit ?? "px";
  if (!pxPerUnit && isRelativeCoordinateUnit(label)) return "比例坐标";
  if (!pxPerUnit && !isPixelUnit(label)) return `未标定（${label}）`;
  const converted = pxPerUnit ? value / pxPerUnit : value;
  if (!Number.isFinite(converted)) return "—";
  const fixed = precision >= 0 && precision <= 8 ? converted.toFixed(precision) : String(converted);
  return `${fixed}${label}`;
}

function isRelativeCoordinateUnit(unit: string) {
  const normalized = unit.trim().toLowerCase();
  return ["normalized", "relative", "ratio", "proportion", "percent", "%"].includes(normalized)
    || /(?:归一|相对|比例)/.test(normalized);
}

function isPixelUnit(unit: string) {
  const normalized = unit.trim().toLowerCase();
  return ["px", "pixel", "pixels", "像素", "像素单位"].includes(normalized);
}

export function measurementUnitLabel(measure: ImageOverlaySpec["measurement"]) {
  const unit = measure.unit ?? "px";
  if (isRelativeCoordinateUnit(unit)) {
    return measure.pxPerUnit
      ? `${unit}（比例坐标，1单位=${measure.pxPerUnit}px）`
      : `${unit}（比例坐标）`;
  }
  if (measure.pxPerUnit) {
    return `${unit}（1${unit}=${measure.pxPerUnit}px）`;
  }
  return isPixelUnit(unit) ? `${unit}（像素单位）` : `${unit}（未标定）`;
}

function roundForEvidence(value: number, precision = 3) {
  if (!Number.isFinite(value)) return 0;
  const factor = 10 ** precision;
  return Math.round(value * factor) / factor;
}

export function createImageOverlayStateEvidence({
  spec,
  programID,
  imageLoaded,
  imageError,
  viewport,
  viewRect,
  zoom,
  pan,
  layerVisibility,
  showReadout,
  showAnnotations,
  readoutItems,
  compareValue,
  activeLayerId = null,
  focusedFeatureKeys = [],
  denseFocus = false,
}: {
  spec: ImageOverlaySpec;
  programID: string;
  imageLoaded: boolean;
  imageError: string | null;
  viewport: { width: number; height: number };
  viewRect: { left: number; top: number; width: number; height: number; scaleX: number; scaleY: number };
  zoom: number;
  pan: { x: number; y: number };
  layerVisibility: Record<string, boolean>;
  showReadout: boolean;
  showAnnotations: boolean;
  readoutItems: string[];
  compareValue: number;
  activeLayerId?: string | null;
  focusedFeatureKeys?: string[];
  denseFocus?: boolean;
}) {
  const visibleLayerIds = spec.layers
    .filter((layer) => layerVisibility[layer.id] ?? layer.visibleDefault)
    .map((layer) => layer.id);
  const visibleAnnotations = spec.annotations.filter((annotation) => {
    if (!showAnnotations) return false;
    if (!annotation.layer) return true;
    return layerVisibility[annotation.layer] ?? true;
  });
  const comparisonEnabled = Boolean(spec.comparison?.enabled);
  const ratio = comparisonEnabled ? Math.min(0.92, Math.max(0.08, compareValue)) : null;
  const totalFeatureCount = spec.layers.reduce((count, layer) => count + layer.features.length, 0);
  const visibleFeatureCount = spec.layers.reduce((count, layer) => {
    const visible = layerVisibility[layer.id] ?? layer.visibleDefault;
    return visible ? count + layer.features.length : count;
  }, 0);

  return {
    renderer: IMAGE_OVERLAY_RENDERER,
    programID,
    state: imageError ? "image-error" : (imageLoaded ? "ready" : "loading"),
    image: {
      label: spec.image.label ?? null,
      kind: spec.image.kind,
      loaded: imageLoaded,
      error: imageError,
      width: spec.image.width ?? null,
      height: spec.image.height ?? null,
      objectFit: spec.objectFit,
    },
    measurement: {
      unit: spec.measurement.unit ?? "px",
      unitLabel: measurementUnitLabel(spec.measurement),
      pxPerUnit: spec.measurement.pxPerUnit ?? null,
      precision: spec.measurement.precision ?? 2,
    },
    viewport: {
      width: Math.round(viewport.width),
      height: Math.round(viewport.height),
    },
    viewRect: {
      left: roundForEvidence(viewRect.left),
      top: roundForEvidence(viewRect.top),
      width: roundForEvidence(viewRect.width),
      height: roundForEvidence(viewRect.height),
      scaleX: roundForEvidence(viewRect.scaleX, 5),
      scaleY: roundForEvidence(viewRect.scaleY, 5),
    },
    transform: {
      zoom: roundForEvidence(zoom),
      panX: roundForEvidence(pan.x),
      panY: roundForEvidence(pan.y),
    },
    layers: spec.layers.map((layer) => ({
      id: layer.id,
      title: layer.title ?? layer.id,
      visible: layerVisibility[layer.id] ?? layer.visibleDefault,
      active: layer.id === activeLayerId,
      featureCount: layer.features.length,
      annotation: layer.annotation ?? null,
    })),
    visibleLayerIds,
    focus: {
      dense: denseFocus,
      activeLayerId,
      focusedFeatureKeys: focusedFeatureKeys.slice(0, 24),
      focusedFeatureCount: focusedFeatureKeys.length,
    },
    features: {
      totalCount: totalFeatureCount,
      visibleCount: visibleFeatureCount,
    },
    readout: {
      visible: spec.showReadout && showReadout,
      itemCount: readoutItems.length,
      items: readoutItems.slice(0, 24),
    },
    annotations: {
      visible: showAnnotations,
      totalCount: spec.annotations.length,
      visibleCount: visibleAnnotations.length,
      items: visibleAnnotations.slice(0, 24).map((annotation) => ({
        id: annotation.id,
        layer: annotation.layer ?? null,
        text: annotation.text,
      })),
    },
    comparison: comparisonEnabled && spec.comparison
      ? {
          enabled: true,
          axis: spec.comparison.axis,
          ratio,
          percent: ratio === null ? null : Math.round(ratio * 100),
          leftLabel: spec.comparison.leftLabel,
          rightLabel: spec.comparison.rightLabel,
        }
      : {
          enabled: false,
          axis: null,
          ratio: null,
          percent: null,
          leftLabel: null,
          rightLabel: null,
        },
  };
}

const imageOverlaySelfCheckSpec: ImageOverlaySpec = {
  title: "自检图像覆盖",
  image: {
    kind: "dataUrl",
    source: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=",
    width: 640,
    height: 900,
    label: "竖版海报",
  },
  objectFit: "contain",
  measurement: { unit: "cm", pxPerUnit: 20, precision: 1 },
  layers: [
    {
      id: "safe-area",
      title: "安全区",
      visibleDefault: true,
      features: [
        {
          id: "poster-safe",
          kind: "rect",
          label: "主视觉安全区",
          box: { x: 0.08, y: 0.08, width: 0.84, height: 0.84 },
          emphasis: "subtle",
          tone: "earth",
          style: { stroke: "rgba(120, 74, 55, 0.9)", strokeWidth: 2, fill: "rgba(120, 74, 55, 0.12)", opacity: 0.18, dash: true },
        },
      ],
    },
    {
      id: "measure",
      title: "测量",
      visibleDefault: false,
      features: [
        {
          id: "width-line",
          kind: "line",
          label: "标题宽度",
          emphasis: "subtle",
          tone: "earth",
          points: [
            { x: 0.22, y: 0.22 },
            { x: 0.46, y: 0.18 },
            { x: 0.78, y: 0.22 },
          ],
        },
      ],
    },
  ],
  annotations: [
    { id: "a1", point: { x: 0.48, y: 0.18 }, text: "标题与图像留出呼吸感", color: "rgba(84, 70, 58, 0.95)", layer: "safe-area" },
  ],
  comparison: {
    enabled: true,
    image: {
      kind: "dataUrl",
      source: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=",
      width: 640,
      height: 900,
      label: "对照海报",
    },
    ratio: 0.54,
    axis: "vertical",
    leftLabel: "原图",
    rightLabel: "对照",
  },
  caption: "自检：竖版图像窄窗完整显示，叠层切换改变证据。",
  showReadout: true,
};

export function runImageOverlaySelfChecks() {
  const narrowViewport = computeResponsiveImageOverlayViewport(320, 640, 900, 560);
  const narrowRect = computeObjectFitRect(narrowViewport.width, narrowViewport.height, 640, 900, "contain");
  const narrowAreaCoverage = (narrowRect.width * narrowRect.height) / (narrowViewport.width * narrowViewport.height);
  const wideViewport = computeResponsiveImageOverlayViewport(720, 1600, 900, 560);
  const wideRect = computeObjectFitRect(wideViewport.width, wideViewport.height, 1600, 900, "contain");
  const wideAreaCoverage = (wideRect.width * wideRect.height) / (wideViewport.width * wideViewport.height);
  const visibleEvidence = createImageOverlayStateEvidence({
    spec: imageOverlaySelfCheckSpec,
    programID: "image-overlay-self-check",
    imageLoaded: true,
    imageError: null,
    viewport: narrowViewport,
    viewRect: narrowRect,
    zoom: 1,
    pan: { x: 0, y: 0 },
    layerVisibility: { "safe-area": true, measure: false },
    showReadout: true,
    showAnnotations: true,
    readoutItems: ["① 主视觉安全区：28.2cm × 37.8cm", "批注 A1：标题与图像留出呼吸感"],
    compareValue: 0.54,
  });
  const toggledEvidence = createImageOverlayStateEvidence({
    spec: imageOverlaySelfCheckSpec,
    programID: "image-overlay-self-check",
    imageLoaded: true,
    imageError: null,
    viewport: narrowViewport,
    viewRect: narrowRect,
    zoom: 1,
    pan: { x: 0, y: 0 },
    layerVisibility: { "safe-area": false, measure: false },
    showReadout: true,
    showAnnotations: true,
    readoutItems: [],
    compareValue: 0.54,
  });
  const normalizedPlan: RenderPlan = {
    renderer: IMAGE_OVERLAY_RENDERER,
    specVersion: IMAGE_OVERLAY_SPEC_VERSION,
    qualityBudget: {
      allowAnimation: false,
      allowNetwork: false,
      allowWebGL: false,
      maxHeight: 560,
      maxNodes: 180,
    },
    interactionBindings: [],
    sourceBindings: [],
    artifactRefs: [],
    fallback: {
      mode: "narrativeOnly",
      reason: "self-check",
      text: "图像叠层不可用。",
      preservesSourceBinding: true,
    },
    spec: {
      ...imageOverlaySelfCheckSpec,
      measurement: { unit: "normalized", precision: 2 },
    },
  };
  const normalizedSummary = summary(normalizedPlan);
  const legacySemanticPlan: RenderPlan = {
    ...normalizedPlan,
    spec: {
      image: imageOverlaySelfCheckSpec.image,
      objectFit: "contain",
      measurement: { unit: "normalized", precision: 2 },
      layers: [
        {
          id: "legacy",
          visibleDefault: true,
          features: [
            {
              id: "legacy-line",
              kind: "line",
              label: "旧协议线段",
              start: { x: 0.12, y: 0.16 },
              end: { x: 0.66, y: 0.38 },
            },
          ],
        },
      ],
      annotations: [],
      showReadout: true,
    },
  };
  const legacySemanticParse = parseImageOverlaySpec(legacySemanticPlan);
  const denseFocusPolicy = computeImageOverlayFocusPolicy(
    {
      ...imageOverlaySelfCheckSpec,
      layers: [
        {
          id: "grid",
          title: "网格",
          visibleDefault: true,
          features: Array.from({ length: 8 }, (_, index) => ({
            id: `grid-${index}`,
            kind: "line" as const,
            label: `辅助线 ${index + 1}`,
            emphasis: "subtle" as const,
            tone: "neutral" as const,
            start: { x: 0.08 + index * 0.08, y: 0.08 },
            end: { x: 0.08 + index * 0.08, y: 0.92 },
          })),
        },
        {
          id: "subject",
          title: "主体",
          visibleDefault: true,
          features: [
            {
              id: "subject-focus",
              kind: "rect" as const,
              label: "主体焦点",
              emphasis: "strong" as const,
              tone: "earth" as const,
              box: { x: 0.24, y: 0.24, width: 0.36, height: 0.28 },
            },
          ],
        },
      ],
      annotations: [
        { id: "dense-a1", point: { x: 0.34, y: 0.32 }, text: "主体说明", color: "rgba(84, 70, 58, 0.95)", layer: "subject" },
        { id: "dense-a2", point: { x: 0.12, y: 0.32 }, text: "网格说明", color: "rgba(84, 70, 58, 0.95)", layer: "grid" },
      ],
    },
    { grid: true, subject: true },
    true,
    360,
    "subject",
  );

  const cases = [
    {
      name: "窄窗竖版图完整显示",
      ok:
        narrowRect.left >= -0.001
        && narrowRect.top >= -0.001
        && narrowRect.left + narrowRect.width <= narrowViewport.width + 0.001
        && narrowRect.top + narrowRect.height <= narrowViewport.height + 0.001
        && narrowAreaCoverage >= 0.92,
    },
    {
      name: "宽图不会被固定高度裁成小图",
      ok:
        wideRect.width >= 719
        && wideRect.height >= 400
        && wideAreaCoverage >= 0.9,
    },
    {
      name: "图层切换改变真实状态证据",
      ok:
        visibleEvidence.features.visibleCount === 1
        && toggledEvidence.features.visibleCount === 0
        && visibleEvidence.annotations.visibleCount === 1
        && toggledEvidence.annotations.visibleCount === 0,
    },
    {
      name: "对照滑杆比例被安全限制",
      ok:
        visibleEvidence.comparison.enabled === true
        && visibleEvidence.comparison.percent === 54,
    },
    {
      name: "normalized 不再被说明为像素单位",
      ok:
        normalizedSummary.ok === true
        && normalizedSummary.stateEvidence?.unitLabel.includes("比例坐标")
        && !normalizedSummary.stateEvidence?.unitLabel.includes("（像素单位）")
        && formatMeasurement(120, { unit: "relative", precision: 2 }) === "比例坐标",
    },
    {
      name: "未标定自定义单位不伪造测量值",
      ok:
        measurementUnitLabel({ unit: "cm", precision: 1 }) === "cm（未标定）"
        && formatMeasurement(120, { unit: "cm", precision: 1 }) === "未标定（cm）",
    },
    {
      name: "像素单位别名保持真实像素语义",
      ok:
        measurementUnitLabel({ unit: "像素", precision: 0 }) === "像素（像素单位）"
        && measurementUnitLabel({ unit: "pixels", precision: 0 }) === "pixels（像素单位）"
        && formatMeasurement(120, { unit: "pixel", precision: 0 }) === "120pixel",
    },
    {
      name: "旧图形数据默认获得轻量语义",
      ok:
        legacySemanticParse.ok === true
        && legacySemanticParse.spec.layers[0]?.features[0]?.emphasis === "subtle"
        && legacySemanticParse.spec.layers[0]?.features[0]?.tone === "earth",
    },
    {
      name: "密集覆盖层自动焦点降噪",
      ok:
        denseFocusPolicy.dense === true
        && denseFocusPolicy.narrow === true
        && denseFocusPolicy.activeLayerId === "subject"
        && denseFocusPolicy.focusedFeatureKeys.has("subject:subject-focus")
        && !denseFocusPolicy.focusedFeatureKeys.has("grid:grid-0")
        && denseFocusPolicy.focusedFeatureKeys.size <= denseFocusPolicy.maxFocus
        && denseFocusPolicy.focusedFeatureKeys.size < denseFocusPolicy.visibleFeatureCount
        && denseFocusPolicy.focusedAnnotationKeys.has("annotation:dense-a1"),
    },
  ];

  return {
    ok: cases.every((item) => item.ok),
    cases,
  };
}

export function summary(plan: RenderPlan) {
  const parsed = parseImageOverlaySpec(plan);
  if (parsed.ok === false) {
    return { ok: false, issues: [parsed.issue.message] };
  }

  const stateEvidence = createImageOverlayStateEvidence({
    spec: parsed.spec,
    programID: "self-check",
    imageLoaded: true,
    imageError: null,
    viewport: { width: 640, height: 360 },
    viewRect: computeObjectFitRect(
      640,
      360,
      parsed.spec.image.width ?? 640,
      parsed.spec.image.height ?? 360,
      parsed.spec.objectFit,
    ),
    zoom: 1.25,
    pan: { x: 12, y: -8 },
    layerVisibility: Object.fromEntries(parsed.spec.layers.map((layer) => [layer.id, layer.visibleDefault])),
    showReadout: true,
    showAnnotations: true,
    readoutItems: ["self-check readout"],
    compareValue: parsed.spec.comparison?.ratio ?? 0.5,
  });

  return {
    ok: true,
    layerCount: parsed.spec.layers.length,
    featureCount: parsed.spec.layers.reduce((count, layer) => count + layer.features.length, 0),
    annotationCount: parsed.spec.annotations.length,
    hasComparison: Boolean(parsed.spec.comparison?.enabled),
    stateEvidence: {
      hasLayerState: stateEvidence.layers.length === parsed.spec.layers.length,
      hasReadoutState: stateEvidence.readout.itemCount > 0,
      hasAnnotationState: stateEvidence.annotations.totalCount === parsed.spec.annotations.length,
      hasComparisonState: stateEvidence.comparison.enabled === Boolean(parsed.spec.comparison?.enabled),
      hasFeatureVisibilityState: stateEvidence.features.totalCount >= stateEvidence.features.visibleCount,
      unitLabel: stateEvidence.measurement.unitLabel,
      zoom: stateEvidence.transform.zoom,
      panX: stateEvidence.transform.panX,
      panY: stateEvidence.transform.panY,
    },
  };
}
