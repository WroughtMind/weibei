import { z } from "zod/v4";
import { createRendererIssue, type RenderPlan } from "../renderer-registry";

export const SPATIAL_MAP_RENDERER = "weibei.spatial.map";
export const SPATIAL_MAP_SPEC_VERSION = "weibei.spatial.map.v1";

const finiteNumber = z.number().refine(Number.isFinite, "必须是有限数字");
const identifier = z.string().min(1).max(64);
const colorName = z.string().min(4).max(40);
const coordinateMode = z.enum(["schematic", "geographic"]).default("schematic");
const coordinateSystem = z.enum(["cartesian", "WGS84"]).default("cartesian");
const safeSourceKind = z.enum(["none", "dataUrl", "assetRef"]).default("none");
const maxEmbeddedMapSourceLength = 1_200_000;

const mapAssetSchema = z.object({
  kind: safeSourceKind,
  source: z.string().max(maxEmbeddedMapSourceLength).optional(),
  label: z.string().min(1).max(80).optional(),
  width: z.number().int().min(16).max(12_000).optional(),
  height: z.number().int().min(16).max(12_000).optional(),
  _weibeiHostInjected: z.literal(true).optional(),
}).strict();

const styleSchema = z.object({
  stroke: colorName.default("#6e5144"),
  strokeWidth: z.number().min(0.5).max(6).default(1.8),
  fill: z.string().min(4).max(40).default("rgba(111, 88, 70, 0.2)"),
  opacity: z.number().min(0).max(1).default(0.9),
  dash: z.boolean().default(false),
}).strict();

const boundsSchema = z.object({
  xMin: z.number(),
  xMax: z.number(),
  yMin: z.number(),
  yMax: z.number(),
}).strict();

const pointSchema = z.object({
  id: identifier,
  kind: z.literal("point"),
  x: finiteNumber,
  y: finiteNumber,
  layer: identifier.optional(),
  visibilityGroup: identifier.optional(),
  visible: z.boolean().optional(),
  label: z.string().min(1).max(80).optional(),
  radius: z.number().min(0.001).max(24).default(3),
  style: styleSchema.optional(),
  value: z.union([z.string().min(1).max(100), finiteNumber]).optional(),
}).strict();

const polylineSchema = z.object({
  id: identifier,
  kind: z.literal("line"),
  points: z.array(z.object({ x: finiteNumber, y: finiteNumber })).min(2).max(300),
  closed: z.boolean().default(false),
  layer: identifier.optional(),
  visibilityGroup: identifier.optional(),
  visible: z.boolean().optional(),
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  value: z.union([z.string().min(1).max(100), finiteNumber]).optional(),
}).strict();

const polygonSchema = z.object({
  id: identifier,
  kind: z.literal("polygon"),
  points: z.array(z.object({ x: finiteNumber, y: finiteNumber })).min(3).max(400),
  fillMode: z.enum(["fill", "wire"]).default("fill"),
  layer: identifier.optional(),
  visibilityGroup: identifier.optional(),
  visible: z.boolean().optional(),
  label: z.string().min(1).max(80).optional(),
  style: styleSchema.optional(),
  value: z.union([z.string().min(1).max(100), finiteNumber]).optional(),
}).strict();

const labelSchema = z.object({
  id: identifier,
  kind: z.literal("label"),
  x: finiteNumber,
  y: finiteNumber,
  text: z.string().min(1).max(120),
  layer: identifier.optional(),
  visibilityGroup: identifier.optional(),
  bindTo: identifier.optional(),
  visible: z.boolean().optional(),
  style: z.object({
    color: colorName.default("#3f3326"),
    size: z.number().min(10).max(24).default(12),
    weight: z.enum(["normal", "bold"]).default("normal"),
    shadow: z.boolean().default(false),
  }).strict().default({ color: "#3f3326", size: 12, weight: "normal", shadow: false }),
}).strict();

const featureSchema = z.discriminatedUnion("kind", [
  pointSchema,
  polylineSchema,
  polygonSchema,
  labelSchema,
]);

const layerSchema = z.object({
  id: identifier,
  title: z.string().min(1).max(80).optional(),
  visibleDefault: z.boolean().default(true),
  note: z.string().max(200).optional(),
}).strict();

const scaleSchema = z.object({
  enabled: z.boolean().default(true),
  label: z.string().min(1).max(60).default("比例尺"),
  targetPixels: z.number().min(40).max(380).default(120),
}).strict();

const controlsSchema = z.object({
  allowPan: z.boolean().default(true),
  allowZoom: z.boolean().default(true),
  allowLayerToggle: z.boolean().default(true),
  allowReset: z.boolean().default(true),
  probeEnabled: z.boolean().default(true),
}).strict();

const spatialMapSpecSchema = z.object({
  title: z.string().min(1).max(140).default("地图空间视图"),
  coordinateMode: coordinateMode,
  crs: coordinateSystem.optional(),
  coordinateHint: z.string().min(1).max(160).optional(),
  mapAsset: mapAssetSchema.default({ kind: "none" }),
  bounds: boundsSchema.optional(),
  layers: z.array(layerSchema).default([]),
  features: z.array(featureSchema).max(400).default([]),
  scaleBar: scaleSchema.default({ enabled: true, label: "比例尺", targetPixels: 120 }),
  controls: controlsSchema.default({ allowPan: true, allowZoom: true, allowLayerToggle: true, allowReset: true, probeEnabled: true }),
  caption: z.string().min(1).max(260).optional(),
  focusEnabled: z.boolean().default(true),
}).strict();

const maxFeaturePerLayer = 280;
const maxDataPoints = 8_000;

export type SpatialMapSpec = z.infer<typeof spatialMapSpecSchema>;
export type SpatialMapFeature = z.infer<typeof featureSchema>;

export type SpatialMapScreenTransform = {
  width: number;
  height: number;
  panX: number;
  panY: number;
  scale: number;
};

export type SpatialMapVisibilityState = {
  visibleFeatureIds: Set<string>;
  hiddenFeatureIds: Set<string>;
  layerStates: Record<string, boolean>;
};

export function spatialMapBaseToScreen(point: { x: number; y: number }, transform: SpatialMapScreenTransform) {
  return {
    x: transform.panX + point.x * transform.scale,
    y: transform.panY + point.y * transform.scale,
  };
}

export function spatialMapScreenToBase(point: { x: number; y: number }, transform: SpatialMapScreenTransform) {
  const scale = Math.max(transform.scale, 1e-9);
  return {
    x: (point.x - transform.panX) / scale,
    y: (point.y - transform.panY) / scale,
  };
}

export function resolveSpatialMapVisibility(
  spec: Pick<SpatialMapSpec, "features" | "layers">,
  layerOverrides: Record<string, boolean> = {},
): SpatialMapVisibilityState {
  const layerStates: Record<string, boolean> = {};
  for (const layer of spec.layers) {
    layerStates[layer.id] = layerOverrides[layer.id] ?? layer.visibleDefault ?? true;
  }
  for (const feature of spec.features) {
    const layer = feature.layer ?? "default";
    if (!(layer in layerStates)) {
      layerStates[layer] = layerOverrides[layer] ?? true;
    }
  }

  const byId = new Map<string, SpatialMapFeature>();
  const geometryByGroup = new Map<string, SpatialMapFeature[]>();
  for (const feature of spec.features) {
    byId.set(feature.id, feature);
    if (feature.kind !== "label" && feature.visibilityGroup) {
      const group = geometryByGroup.get(feature.visibilityGroup) ?? [];
      group.push(feature);
      geometryByGroup.set(feature.visibilityGroup, group);
    }
  }

  const memo = new Map<string, boolean>();
  const isVisible = (feature: SpatialMapFeature): boolean => {
    const cached = memo.get(feature.id);
    if (cached !== undefined) return cached;

    let visible = true;
    if (feature.visible === false) {
      visible = false;
    } else if (!(layerStates[feature.layer ?? "default"] ?? true)) {
      visible = false;
    } else if (feature.kind === "label" && feature.bindTo) {
      const target = byId.get(feature.bindTo);
      visible = target ? isVisible(target) : false;
    } else if (feature.kind === "label" && feature.visibilityGroup) {
      const boundGeometry = geometryByGroup.get(feature.visibilityGroup) ?? [];
      visible = boundGeometry.length === 0 || boundGeometry.some((item) => isVisible(item));
    }

    memo.set(feature.id, visible);
    return visible;
  };

  const visibleFeatureIds = new Set<string>();
  const hiddenFeatureIds = new Set<string>();
  for (const feature of spec.features) {
    if (isVisible(feature)) {
      visibleFeatureIds.add(feature.id);
    } else {
      hiddenFeatureIds.add(feature.id);
    }
  }

  return { visibleFeatureIds, hiddenFeatureIds, layerStates };
}

type CheckResult =
  | { ok: true; spec: SpatialMapSpec }
  | { ok: false; issue: ReturnType<typeof createRendererIssue> };

function safeMapSource(plan: RenderPlan, source: { kind: "none" | "dataUrl" | "assetRef"; source?: string }) {
  if (source.kind === "none") return null;

  const raw = (source.source ?? "").trim();
  if (!raw.length) {
    return createRendererIssue("validation_error", plan.renderer, "mapAsset.source 不能为空");
  }

  const lowered = raw.toLowerCase();
  if (source.kind === "dataUrl") {
    if (!/^data:image\/(?:png|jpe?g|webp|gif);base64,/.test(lowered)) {
      return createRendererIssue("validation_error", plan.renderer, "地图资产只允许安全位图 data:image，不接受 SVG 或脚本型资源。 ");
    }
    if (raw.length > maxEmbeddedMapSourceLength) {
      return createRendererIssue("validation_error", plan.renderer, "data URL 图像过大，请先压缩。 ");
    }
    return null;
  }

  if (/^https?:\/\//.test(lowered) || lowered.startsWith("//") || lowered.startsWith("javascript:")) {
    return createRendererIssue("capability_mismatch", plan.renderer, "地图资产不得使用网络链接或 javascript。 ");
  }

  if (!/^[a-zA-Z0-9._\/\-]+\.(?:png|jpg|jpeg|webp|gif)$/i.test(raw)) {
    return createRendererIssue("validation_error", plan.renderer, "assetRef 只能是本地静态位图路径。 ");
  }

  return null;
}

function validateGeographicNumber(feature: SpatialMapFeature, plan: RenderPlan) {
  const points = feature.kind === "point" || feature.kind === "label"
    ? [{ x: feature.x, y: feature.y }]
    : feature.points;

  for (const point of points) {
    if (point.x < -180 || point.x > 180 || point.y < -90 || point.y > 90) {
      return createRendererIssue("validation_error", plan.renderer, `${feature.id} 中存在越界经纬度点。`);
    }
  }
  return null;
}

function validateFeatureLayerBoundaries(plan: RenderPlan, feature: SpatialMapFeature, featureLayers: Map<string, number>) {
  const layer = feature.layer ?? "default";
  const count = featureLayers.get(layer) ?? 0;
  featureLayers.set(layer, count + 1);

  if (count + 1 > maxFeaturePerLayer) {
    return createRendererIssue("validation_error", plan.renderer, `图层 ${layer} 的可视元素过多。`);
  }
  return null;
}

function validateSchematicBounds(feature: SpatialMapFeature, plan: RenderPlan, mode: "schematic" | "geographic") {
  if (mode !== "schematic") return null;

  const points = feature.kind === "point" || feature.kind === "label"
    ? [{ x: feature.x, y: feature.y }]
    : feature.points;
  for (const point of points) {
    if (!Number.isFinite(point.x) || !Number.isFinite(point.y)) {
      return createRendererIssue("validation_error", plan.renderer, `${feature.id} 包含非有限坐标。`);
    }
  }
  return null;
}

export function parseSpatialMapSpec(plan: RenderPlan): CheckResult {
  const result = spatialMapSpecSchema.safeParse(plan.spec);
  if (!result.success) {
    return {
      ok: false,
      issue: createRendererIssue(
        "validation_error",
        plan.renderer,
        result.error.issues[0]?.message ?? "空间地图规格不符合协议。",
        result.error.issues.map((issue) => issue.path.join(".")).filter(Boolean),
      ),
    };
  }

  const issue = guardSpatialMapSpec(plan, result.data);
  if (issue) return { ok: false, issue };

  const normalized = {
    ...result.data,
    features: result.data.features.map((feature) => ({
      ...feature,
      layer: feature.layer ?? "default",
      visible: feature.visible ?? true,
    })),
    layers: result.data.layers.length
      ? result.data.layers
      : [{ id: "default", title: "默认图层", visibleDefault: true }],
  };

  return { ok: true, spec: normalized };
}

function guardSpatialMapSpec(plan: RenderPlan, spec: SpatialMapSpec) {
  if (plan.renderer !== SPATIAL_MAP_RENDERER) {
    return createRendererIssue("capability_mismatch", plan.renderer, `空间地图渲染器不能渲染 ${plan.renderer}。`);
  }
  if (plan.specVersion !== SPATIAL_MAP_SPEC_VERSION) {
    return createRendererIssue("capability_mismatch", plan.renderer, `空间地图只支持 ${SPATIAL_MAP_SPEC_VERSION}。`);
  }
  if (plan.qualityBudget.allowNetwork) {
    return createRendererIssue("capability_mismatch", plan.renderer, "空间地图渲染器不允许外链资源。");
  }
  if (plan.qualityBudget.allowWebGL) {
    return createRendererIssue("capability_mismatch", plan.renderer, "空间地图渲染器使用 2D Canvas，不接受 WebGL。 ");
  }

  const sourceIssue = safeMapSource(plan, spec.mapAsset);
  if (sourceIssue) return sourceIssue;

  if (!spec.features.length) {
    return createRendererIssue("validation_error", plan.renderer, "至少需要一个可视元素（点、线、面或标签）。");
  }

  const layerIds = new Set<string>();
  for (const layer of spec.layers) {
    if (layerIds.has(layer.id)) {
      return createRendererIssue("validation_error", plan.renderer, `图层 id 重复：${layer.id}。`);
    }
    layerIds.add(layer.id);
  }

  const featureIds = new Set<string>();
  const geometryIds = new Set<string>();
  for (const feature of spec.features) {
    if (featureIds.has(feature.id)) {
      return createRendererIssue("validation_error", plan.renderer, `可视元素 id 重复：${feature.id}。`);
    }
    featureIds.add(feature.id);
    if (feature.kind !== "label") geometryIds.add(feature.id);
  }

  const featureLayers = new Map<string, number>();
  let pointBudget = 0;
  for (const feature of spec.features) {
    if (feature.kind === "label" && feature.bindTo && !geometryIds.has(feature.bindTo)) {
      return createRendererIssue("validation_error", plan.renderer, `标签 ${feature.id} 绑定的图形 ${feature.bindTo} 不存在。`);
    }

    const byLayer = validateFeatureLayerBoundaries(plan, feature, featureLayers);
    if (byLayer) return byLayer;

    const mode = spec.coordinateMode;
    const boundsIssue = mode === "geographic"
      ? validateGeographicNumber(feature, plan)
      : validateSchematicBounds(feature, plan, "schematic");
    if (boundsIssue) return boundsIssue;

    if (feature.kind === "point" || feature.kind === "label") {
      pointBudget += 1;
      continue;
    }

    pointBudget += feature.points.length;
  }

  const budget = plan.qualityBudget.maxDataPoints ?? maxDataPoints;
  if (pointBudget > budget || pointBudget > maxDataPoints) {
    return createRendererIssue(
      "validation_error",
      plan.renderer,
      `空间数据点数 ${pointBudget} 超过预算。`,
      [`renderPlan=${budget}`, `renderer=${maxDataPoints}`],
    );
  }

  if (spec.coordinateMode === "geographic" && spec.crs && spec.crs !== "WGS84") {
    return createRendererIssue("validation_error", plan.renderer, `地理坐标默认使用 WGS84，当前 crs 不匹配。`);
  }

  if (spec.coordinateMode === "geographic" && spec.bounds && (spec.bounds.xMin < -180 || spec.bounds.xMax > 180 || spec.bounds.yMin < -90 || spec.bounds.yMax > 90)) {
    return createRendererIssue("validation_error", plan.renderer, "地理坐标边界必须落在合法经纬度范围内。");
  }

  if (spec.bounds && spec.bounds.xMin >= spec.bounds.xMax) {
    return createRendererIssue("validation_error", plan.renderer, "bounds.xMin 必须小于 bounds.xMax。");
  }
  if (spec.bounds && spec.bounds.yMin >= spec.bounds.yMax) {
    return createRendererIssue("validation_error", plan.renderer, "bounds.yMin 必须小于 bounds.yMax。");
  }

  return null;
}
