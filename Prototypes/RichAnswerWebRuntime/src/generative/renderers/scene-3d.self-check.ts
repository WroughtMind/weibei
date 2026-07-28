import { z } from "zod/v4";
import {
  createRendererIssue,
  type RenderPlan,
  type RendererIssue,
} from "../renderer-registry";

export const SCENE3D_RENDERER = "weibei.scene-3d";
export const SCENE3D_SPEC_VERSION = "weibei.scene-3d.v1";

export const maxScene3DObjects = 24;
export const maxScene3DLayers = 12;
export const maxScene3DStates = 12;
export const maxScene3DReadouts = 12;
export const maxScene3DPointsPerObject = 800;
export const maxScene3DDataPoints = 3_200;

const finiteNumber = z.number().refine(Number.isFinite, "必须是有限数字");
const identifier = z.string().min(1).max(64);
const vector3Schema = z.tuple([finiteNumber, finiteNumber, finiteNumber]);
const rangeSchema = z.object({ min: finiteNumber, max: finiteNumber }).strict();
const ratioSchema = z.number().min(0).max(1);
const colorSchema = z.string().min(1).max(40).refine((value) => {
  const trimmed = value.trim();
  return /^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(trimmed)
    || /^rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\)$/.test(trimmed)
    || /^(?:stone|ink|cinnabar|moss|water|ochre|blue|green|red|purple|gray|grey|black|white)$/i.test(trimmed);
}, "颜色只允许 hex、rgb(a) 或内置色名，不允许 url / 外链 / 脚本。");

const cameraSchema = z.object({
  yaw: z.number().min(-360).max(360),
  pitch: z.number().min(-89).max(89),
  distance: z.number().min(0.8).max(14),
  lookAt: vector3Schema,
  fov: z.number().min(20).max(95).default(58),
}).strict();

const layerSchema = z.object({
  id: identifier,
  title: z.string().min(1).max(80).optional(),
  visibleDefault: z.boolean().default(true),
}).strict();

const boundsSchema = z.object({
  x: rangeSchema,
  y: rangeSchema,
  z: rangeSchema,
}).strict();

const coordinateUnitsSchema = z.object({
  x: z.string().min(1).max(36).default("x"),
  y: z.string().min(1).max(36).default("y"),
  z: z.string().min(1).max(36).default("z"),
}).strict();

const baseObjectSchema = z.object({
  id: identifier,
  layer: identifier.optional(),
  label: z.string().min(1).max(80).optional(),
  visible: z.boolean().default(true),
  color: colorSchema.optional(),
  alpha: ratioSchema.default(0.9),
}).strict();

const pointObjectSchema = baseObjectSchema.extend({
  kind: z.literal("point"),
  position: vector3Schema,
  radius: finiteNumber.min(0.002).max(1.6).default(0.06),
}).strict();

const polylineObjectSchema = baseObjectSchema.extend({
  kind: z.literal("polyline"),
  points: z.array(vector3Schema).min(2).max(maxScene3DPointsPerObject),
  closed: z.boolean().default(false),
  strokeWidth: z.number().min(0.5).max(8).default(2),
}).strict();

const wireGridObjectSchema = baseObjectSchema.extend({
  kind: z.literal("wireframe-grid"),
  xRange: rangeSchema,
  zRange: rangeSchema,
  cellSize: z.number().min(0.05).max(5).default(1),
  y: finiteNumber.default(0),
}).strict();

const surfaceObjectSchema = baseObjectSchema.extend({
  kind: z.literal("surface"),
  yValues: z.array(z.array(finiteNumber).min(2).max(80)).min(2).max(60),
  xRange: rangeSchema,
  zRange: rangeSchema,
  wireColor: colorSchema.optional(),
}).strict().superRefine((surface, context) => {
  const width = surface.yValues[0]?.length ?? 0;
  for (let index = 1; index < surface.yValues.length; index += 1) {
      if (surface.yValues[index]!.length !== width) {
      context.addIssue({
        code: "custom",
        message: "surface.yValues 必须是规则矩阵，不能交给 renderer 猜网格。",
        path: ["yValues", index],
      });
    }
  }
});

const moleculeAtomSchema = z.object({
  id: identifier,
  element: z.string().min(1).max(8).optional(),
  label: z.string().min(1).max(48).optional(),
  position: vector3Schema,
  radius: finiteNumber.min(0.04).max(0.9).default(0.16),
  color: colorSchema.optional(),
  role: z.enum(["central", "terminal", "substituent", "marker"]).default("terminal"),
  charge: z.string().min(1).max(16).optional(),
}).strict();

const moleculeBondSchema = z.object({
  id: identifier.optional(),
  from: identifier,
  to: identifier,
  order: z.number().int().min(1).max(3).default(1),
  style: z.enum(["solid", "dashed", "wedge"]).default("solid"),
  label: z.string().min(1).max(48).optional(),
  color: colorSchema.optional(),
  radius: finiteNumber.min(0.004).max(0.16).default(0.035),
}).strict();

const moleculeElectronDomainSchema = z.object({
  id: identifier,
  kind: z.enum(["lonePair", "bonding", "empty"]).default("lonePair"),
  atom: identifier,
  label: z.string().min(1).max(48).optional(),
  direction: vector3Schema.optional(),
  position: vector3Schema.optional(),
  distance: finiteNumber.min(0.08).max(2.4).default(0.42),
  radius: finiteNumber.min(0.02).max(0.45).default(0.08),
  color: colorSchema.optional(),
  alpha: ratioSchema.default(0.72),
}).strict().superRefine((domain, context) => {
  if (!domain.direction && !domain.position) {
    context.addIssue({
      code: "custom",
      message: "electronDomains 必须给出 direction 或 position，不能让 renderer 猜电子域方向。",
      path: ["direction"],
    });
  }
});

const moleculeAngleMarkerSchema = z.object({
  id: identifier,
  from: identifier,
  via: identifier,
  to: identifier,
  degrees: finiteNumber.min(0).max(180).optional(),
  label: z.string().min(1).max(48).optional(),
  color: colorSchema.optional(),
}).strict();

const moleculeObjectSchema = baseObjectSchema.extend({
  kind: z.literal("molecule"),
  atoms: z.array(moleculeAtomSchema).min(1).max(64),
  bonds: z.array(moleculeBondSchema).max(96).default([]),
  electronDomains: z.array(moleculeElectronDomainSchema).max(48).default([]),
  angleMarkers: z.array(moleculeAngleMarkerSchema).max(32).default([]),
  showAtomLabels: z.boolean().default(true),
  showBondLabels: z.boolean().default(false),
  showElectronDomains: z.boolean().default(true),
}).strict();

const sceneObjectSchema = z.discriminatedUnion("kind", [
  pointObjectSchema,
  polylineObjectSchema,
  wireGridObjectSchema,
  surfaceObjectSchema,
  moleculeObjectSchema,
]);

const sliceSchema = z.object({
  axis: z.enum(["x", "y", "z"]),
  value: finiteNumber,
  thickness: finiteNumber.min(0.01).max(9).default(0.6),
  label: z.string().min(1).max(60).optional(),
  color: colorSchema.optional(),
}).strict();

const scene3DReadoutSchema = z.object({
  id: identifier,
  label: z.string().min(1).max(80),
  value: z.union([finiteNumber, z.string().min(1).max(80)]),
  unit: z.string().min(1).max(24).optional(),
  evidenceIDs: z.array(identifier).max(8).default([]),
}).strict();

const scene3DStateSchema = z.object({
  id: identifier,
  title: z.string().min(1).max(80).optional(),
  description: z.string().min(1).max(180).optional(),
  objectIds: z.array(identifier).max(maxScene3DObjects).optional(),
  objects: z.array(sceneObjectSchema).max(maxScene3DObjects).default([]),
  readouts: z.array(scene3DReadoutSchema).max(maxScene3DReadouts).default([]),
  evidenceIDs: z.array(identifier).max(12).default([]),
}).strict();

const stateBindingSchema = z.object({
  initial: identifier,
  control: z.enum(["segmented", "slider"]).default("segmented"),
  label: z.string().min(1).max(80).default("状态"),
}).strict();

const controlsSchema = z.object({
  allowLayerToggle: z.boolean().default(true),
  allowSlice: z.boolean().default(false),
  allowCameraDrag: z.boolean().default(true),
  allowReset: z.boolean().default(true),
  allowProbe: z.boolean().default(true),
}).strict();

const scene3DSpecSchema = z.object({
  title: z.string().min(1).max(120),
  camera: cameraSchema,
  layers: z.array(layerSchema).max(maxScene3DLayers).default([]),
  objects: z.array(sceneObjectSchema).max(maxScene3DObjects).default([]),
  stateBinding: stateBindingSchema.optional(),
  states: z.array(scene3DStateSchema).max(maxScene3DStates).default([]),
  coordinateUnits: coordinateUnitsSchema.default({ x: "x", y: "y", z: "z" }),
  bounds: boundsSchema.optional(),
  slices: z.array(sliceSchema).max(4).default([]),
  caption: z.string().min(1).max(260).optional(),
  controls: controlsSchema.default({
    allowLayerToggle: true,
    allowSlice: false,
    allowCameraDrag: true,
    allowReset: true,
    allowProbe: true,
  }),
  focusEnabled: z.boolean().default(false),
}).strict();

export type Scene3DVector = z.infer<typeof vector3Schema>;
export type Scene3DSlice = z.infer<typeof sliceSchema>;
export type Scene3DObject = z.infer<typeof sceneObjectSchema>;
export type Scene3DLayer = z.infer<typeof layerSchema>;
export type Scene3DReadout = z.infer<typeof scene3DReadoutSchema>;
export type Scene3DState = z.infer<typeof scene3DStateSchema>;
export type Scene3DSpec = z.infer<typeof scene3DSpecSchema>;
export type Scene3DParseResult =
  | { ok: true; spec: Scene3DSpec; layers: Scene3DLayer[]; dataPointCount: number }
  | { ok: false; issue: RendererIssue };

export function parseScene3DSpec(plan: RenderPlan): Scene3DParseResult {
  const result = scene3DSpecSchema.safeParse(plan.spec);
  if (!result.success) {
    return {
      ok: false,
      issue: createRendererIssue(
        "validation_error",
        plan.renderer,
        result.error.issues[0]?.message ?? "三维场景规格不符合协议。",
        result.error.issues.map((issue) => issue.path.join(".")).filter(Boolean),
      ),
    };
  }

  const semanticIssue = guardScene3DPlan(plan, result.data);
  if (semanticIssue) return { ok: false, issue: semanticIssue };

  const layers = normalizeLayers(result.data);
  const layerIds = new Set(layers.map((layer) => layer.id));
  const spec = {
    ...result.data,
    layers,
    objects: result.data.objects.map((object) => normalizeScene3DObjectLayer(object, layerIds)),
    states: result.data.states.map((state) => ({
      ...state,
      objects: state.objects.map((object) => normalizeScene3DObjectLayer(object, layerIds)),
    })),
  };

  return { ok: true, spec, layers, dataPointCount: countScene3DPoints(spec) };
}

export function countScene3DPoints(spec: Pick<Scene3DSpec, "objects"> & Partial<Pick<Scene3DSpec, "states">>) {
  const stateObjects = spec.states?.flatMap((state) => state.objects) ?? [];
  return [...spec.objects, ...stateObjects].reduce((sum, object) => {
    if (object.kind === "point") return sum + 1;
    if (object.kind === "polyline") return sum + object.points.length;
    if (object.kind === "molecule") {
      return sum
        + object.atoms.length
        + object.bonds.length * 2
        + object.electronDomains.length
        + object.angleMarkers.length * 3;
    }
    if (object.kind === "wireframe-grid") {
      const xSteps = Math.ceil((object.xRange.max - object.xRange.min) / object.cellSize) + 1;
      const zSteps = Math.ceil((object.zRange.max - object.zRange.min) / object.cellSize) + 1;
      return sum + Math.max(2, xSteps) * 2 + Math.max(2, zSteps) * 2;
    }
    return sum + object.yValues.length * (object.yValues[0]?.length ?? 0);
  }, 0);
}

function guardScene3DPlan(plan: RenderPlan, spec: Scene3DSpec) {
  if (plan.renderer !== SCENE3D_RENDERER) {
    return createRendererIssue("capability_mismatch", plan.renderer, `三维渲染器不能渲染 ${plan.renderer}。`);
  }
  if (plan.specVersion !== SCENE3D_SPEC_VERSION) {
    return createRendererIssue("capability_mismatch", plan.renderer, `三维渲染器只支持 ${SCENE3D_SPEC_VERSION}。`);
  }
  if (plan.qualityBudget.allowNetwork || plan.qualityBudget.allowWebGL) {
    return createRendererIssue("capability_mismatch", plan.renderer, "三维渲染器不使用网络、WebGL、外链模型或任意脚本，只做确定性 Canvas 投影。");
  }
  if (!plan.sourceBindings.length) {
    return createRendererIssue("validation_error", plan.renderer, "三维场景必须保留来源绑定，不能生成无来源演示。");
  }
  const sourceIds = new Set(plan.sourceBindings.flatMap((binding) => [
    binding.sourceID,
    binding.evidenceID,
  ].filter((value): value is string => typeof value === "string" && value.length > 0)));
  const totalObjectCount = spec.objects.length + spec.states.reduce((sum, state) => sum + state.objects.length, 0);
  if (totalObjectCount === 0) {
    return createRendererIssue("validation_error", plan.renderer, "三维场景至少需要一个共享对象或状态对象。");
  }
  if ((plan.qualityBudget.maxNodes ?? maxScene3DObjects) < totalObjectCount) {
    return createRendererIssue("validation_error", plan.renderer, `对象总数 ${totalObjectCount} 超过本轮质量预算。`);
  }
  if (spec.bounds && !boundsAreValid(spec.bounds)) {
    return createRendererIssue("validation_error", plan.renderer, "bounds 的 min/max 必须满足 min < max。");
  }

  const dataPointBudget = Math.min(plan.qualityBudget.maxDataPoints ?? maxScene3DDataPoints, maxScene3DDataPoints);
  const dataPointCount = countScene3DPoints(spec);
  if (dataPointCount > dataPointBudget) {
    return createRendererIssue(
      "validation_error",
      plan.renderer,
      `三维场景点数 ${dataPointCount} 超过预算 ${dataPointBudget}。`,
      ["请减少曲面网格或折线采样点"],
    );
  }

  const layerIds = new Set<string>();
  for (const layer of spec.layers) {
    if (layerIds.has(layer.id)) {
      return createRendererIssue("validation_error", plan.renderer, `图层 id 重复：${layer.id}。`);
    }
    layerIds.add(layer.id);
  }
  const implicitLayerIds = new Set([...spec.objects, ...spec.states.flatMap((state) => state.objects)].map((object) => object.layer ?? "default"));
  for (const layerId of implicitLayerIds) layerIds.add(layerId);
  if (layerIds.size > maxScene3DLayers) {
    return createRendererIssue("validation_error", plan.renderer, `图层数量 ${layerIds.size} 超过上限 ${maxScene3DLayers}。`);
  }

  const objectIds = new Set<string>();
  const baseObjectIds = new Set<string>();
  const allStateObjectIds = new Set<string>();

  for (const object of spec.objects) {
    if (objectIds.has(object.id)) {
      return createRendererIssue("validation_error", plan.renderer, `几何体 id 重复：${object.id}。`);
    }
    objectIds.add(object.id);
    baseObjectIds.add(object.id);

    if (object.kind === "wireframe-grid") {
      const xCells = (object.xRange.max - object.xRange.min) / object.cellSize;
      const zCells = (object.zRange.max - object.zRange.min) / object.cellSize;
      if (!Number.isFinite(xCells) || !Number.isFinite(zCells) || xCells > 240 || zCells > 240) {
        return createRendererIssue("validation_error", plan.renderer, `网格 ${object.id} 过密，请增大 cellSize。`);
      }
    }
    if (object.kind === "molecule") {
      const moleculeIssue = guardMoleculeObject(plan, object);
      if (moleculeIssue) return moleculeIssue;
    }

    if ("xRange" in object && !rangeIsValid(object.xRange)) {
      return createRendererIssue("validation_error", plan.renderer, `${object.id}.xRange 必须满足 min < max。`);
    }
    if ("zRange" in object && !rangeIsValid(object.zRange)) {
      return createRendererIssue("validation_error", plan.renderer, `${object.id}.zRange 必须满足 min < max。`);
    }
  }

  const stateIds = new Set<string>();
  if (spec.states.length && !spec.stateBinding) {
    return createRendererIssue("validation_error", plan.renderer, "states 存在时必须提供 stateBinding.initial。", ["stateBinding"]);
  }
  if (spec.stateBinding && !spec.states.length) {
    return createRendererIssue("validation_error", plan.renderer, "stateBinding 不能脱离 states 单独存在。", ["states"]);
  }

  for (const state of spec.states) {
    if (stateIds.has(state.id)) {
      return createRendererIssue("validation_error", plan.renderer, `状态 id 重复：${state.id}。`);
    }
    stateIds.add(state.id);

    const readoutIds = new Set<string>();
    for (const readout of state.readouts) {
      if (readoutIds.has(readout.id)) {
        return createRendererIssue("validation_error", plan.renderer, `状态 ${state.id} 的读数 id 重复：${readout.id}。`);
      }
      readoutIds.add(readout.id);
      for (const evidenceId of readout.evidenceIDs) {
        if (!sourceIds.has(evidenceId)) {
          return createRendererIssue("validation_error", plan.renderer, `状态 ${state.id} 的读数引用了不存在的证据：${evidenceId}。`);
        }
      }
    }
    for (const evidenceId of state.evidenceIDs) {
      if (!sourceIds.has(evidenceId)) {
        return createRendererIssue("validation_error", plan.renderer, `状态 ${state.id} 引用了不存在的证据：${evidenceId}。`);
      }
    }

    for (const objectId of state.objectIds ?? []) {
      if (!baseObjectIds.has(objectId)) {
        return createRendererIssue("validation_error", plan.renderer, `状态 ${state.id} 引用了不存在的基础对象：${objectId}。`);
      }
    }

    for (const object of state.objects) {
      if (baseObjectIds.has(object.id) || allStateObjectIds.has(object.id)) {
        return createRendererIssue("validation_error", plan.renderer, `状态对象 id 重复：${object.id}。`);
      }
      allStateObjectIds.add(object.id);
      if (object.kind === "wireframe-grid") {
        const xCells = (object.xRange.max - object.xRange.min) / object.cellSize;
        const zCells = (object.zRange.max - object.zRange.min) / object.cellSize;
        if (!Number.isFinite(xCells) || !Number.isFinite(zCells) || xCells > 240 || zCells > 240) {
          return createRendererIssue("validation_error", plan.renderer, `网格 ${object.id} 过密，请增大 cellSize。`);
        }
      }
      if (object.kind === "molecule") {
        const moleculeIssue = guardMoleculeObject(plan, object);
        if (moleculeIssue) return moleculeIssue;
      }
      if ("xRange" in object && !rangeIsValid(object.xRange)) {
        return createRendererIssue("validation_error", plan.renderer, `${object.id}.xRange 必须满足 min < max。`);
      }
      if ("zRange" in object && !rangeIsValid(object.zRange)) {
        return createRendererIssue("validation_error", plan.renderer, `${object.id}.zRange 必须满足 min < max。`);
      }
    }
  }

  if (spec.stateBinding && !stateIds.has(spec.stateBinding.initial)) {
    return createRendererIssue("validation_error", plan.renderer, `初始状态不存在：${spec.stateBinding.initial}。`);
  }

  return null;
}

function guardMoleculeObject(plan: RenderPlan, object: Extract<Scene3DObject, { kind: "molecule" }>) {
  const atomIds = new Set<string>();
  for (const atom of object.atoms) {
    if (atomIds.has(atom.id)) {
      return createRendererIssue("validation_error", plan.renderer, `分子 ${object.id} 的 atom id 重复：${atom.id}。`);
    }
    atomIds.add(atom.id);
  }
  for (const bond of object.bonds) {
    if (!atomIds.has(bond.from) || !atomIds.has(bond.to)) {
      return createRendererIssue("validation_error", plan.renderer, `分子 ${object.id} 的键引用了不存在的原子。`, [bond.from, bond.to]);
    }
    if (bond.from === bond.to) {
      return createRendererIssue("validation_error", plan.renderer, `分子 ${object.id} 的键不能连接同一个原子：${bond.from}。`);
    }
  }
  for (const domain of object.electronDomains) {
    if (!atomIds.has(domain.atom)) {
      return createRendererIssue("validation_error", plan.renderer, `分子 ${object.id} 的电子域引用了不存在的原子：${domain.atom}。`);
    }
  }
  for (const marker of object.angleMarkers) {
    if (!atomIds.has(marker.from) || !atomIds.has(marker.via) || !atomIds.has(marker.to)) {
      return createRendererIssue("validation_error", plan.renderer, `分子 ${object.id} 的角度标记引用了不存在的原子。`, [marker.from, marker.via, marker.to]);
    }
    if (marker.from === marker.via || marker.via === marker.to || marker.from === marker.to) {
      return createRendererIssue("validation_error", plan.renderer, `分子 ${object.id} 的角度标记必须使用三个不同原子：${marker.id}。`);
    }
  }
  return null;
}

function normalizeLayers(spec: Scene3DSpec) {
  const explicit = spec.layers;
  const explicitIds = new Set(explicit.map((layer) => layer.id));
  const objects = [...spec.objects, ...spec.states.flatMap((state) => state.objects)];
  const implicitLayers = Array.from(new Set(objects.map((object) => object.layer ?? "default")))
    .filter((id) => !explicitIds.has(id))
    .map((id) => ({ id, title: id === "default" ? "默认图层" : id, visibleDefault: true }));

  const layers = explicit.length ? [...explicit, ...implicitLayers] : implicitLayers;
  return layers.length ? layers : [{ id: "default", title: "默认图层", visibleDefault: true }];
}

function normalizeScene3DObjectLayer(object: Scene3DObject, layerIds: Set<string>): Scene3DObject {
  return {
    ...object,
    layer: object.layer && layerIds.has(object.layer) ? object.layer : "default",
  };
}

function rangeIsValid(range: { min: number; max: number }) {
  return Number.isFinite(range.min) && Number.isFinite(range.max) && range.min < range.max;
}

function boundsAreValid(bounds: Scene3DSpec["bounds"]) {
  return Boolean(bounds && rangeIsValid(bounds.x) && rangeIsValid(bounds.y) && rangeIsValid(bounds.z));
}

const baseScene3DPlan: RenderPlan = {
  renderer: SCENE3D_RENDERER,
  specVersion: SCENE3D_SPEC_VERSION,
  spec: {
    title: "抛物面与切片",
    camera: { yaw: 36, pitch: 24, distance: 5.2, lookAt: [0, 0, 0], fov: 58 },
    layers: [
      { id: "surface", title: "曲面", visibleDefault: true },
      { id: "slice", title: "切片", visibleDefault: true },
    ],
    coordinateUnits: { x: "x", y: "高度", z: "z" },
    objects: [
      {
        id: "paraboloid",
        kind: "surface",
        layer: "surface",
        xRange: { min: -2, max: 2 },
        zRange: { min: -2, max: 2 },
        yValues: [
          [4, 2.5, 2, 2.5, 4],
          [2.5, 1, 0.5, 1, 2.5],
          [2, 0.5, 0, 0.5, 2],
          [2.5, 1, 0.5, 1, 2.5],
          [4, 2.5, 2, 2.5, 4],
        ],
        color: "moss",
        alpha: 0.82,
      },
      {
        id: "minimum",
        kind: "point",
        layer: "slice",
        position: [0, 0, 0],
        label: "最低点",
        color: "cinnabar",
        radius: 0.09,
      },
      {
        id: "water-like-vsepr",
        kind: "molecule",
        layer: "slice",
        label: "中心原子与电子域",
        atoms: [
          { id: "O", element: "O", label: "O", role: "central", position: [0, 0.35, 0], radius: 0.18, color: "red" },
          { id: "H1", element: "H", label: "H", position: [-0.62, 0.02, 0.24], radius: 0.11, color: "white" },
          { id: "H2", element: "H", label: "H", position: [0.62, 0.02, 0.24], radius: 0.11, color: "white" },
        ],
        bonds: [
          { from: "O", to: "H1", order: 1, label: "O-H" },
          { from: "O", to: "H2", order: 1, label: "O-H" },
        ],
        electronDomains: [
          { id: "lp-a", atom: "O", kind: "lonePair", label: "孤对电子", direction: [-0.45, 0.7, -0.45], color: "water" },
          { id: "lp-b", atom: "O", kind: "lonePair", label: "孤对电子", direction: [0.45, 0.7, -0.45], color: "water" },
        ],
        angleMarkers: [
          { id: "h-o-h", from: "H1", via: "O", to: "H2", degrees: 104.5, label: "约 104.5°" },
        ],
        color: "stone",
        alpha: 0.96,
      },
    ],
    slices: [{ axis: "y", value: 1, thickness: 0.8, label: "高度切片" }],
    controls: {
      allowLayerToggle: true,
      allowSlice: true,
      allowCameraDrag: true,
      allowReset: true,
      allowProbe: true,
    },
    caption: "这是 Canvas 2D 确定性投影，不是物理级三维引擎。",
    focusEnabled: true,
  },
  interactionBindings: [],
  sourceBindings: [{ sourceID: "self-check", range: "scene-3d" }],
  artifactRefs: [],
  fallback: {
    mode: "simplifiedRenderer",
    reason: "当前环境不能渲染受控三维场景。",
    text: "退回为坐标与对象清单。",
    preservesSourceBinding: true,
  },
  qualityBudget: {
    maxNodes: 24,
    maxHeight: 420,
    maxDataPoints: 3_200,
    allowAnimation: false,
    allowWebGL: false,
    allowNetwork: false,
  },
};

export const scene3DSelfCheckCases = [
  {
    name: "accepts controlled scene tree",
    expectOk: true,
    plan: baseScene3DPlan,
  },
  {
    name: "accepts generic multi-state scene contract",
    expectOk: true,
    plan: {
      ...baseScene3DPlan,
      spec: {
        ...baseScene3DPlan.spec,
        stateBinding: { initial: "baseline", control: "slider", label: "观测时刻" },
        states: [
          {
            id: "baseline",
            title: "初始",
            objectIds: ["paraboloid"],
            objects: [
              {
                id: "marker-start",
                kind: "point",
                layer: "slice",
                position: [-1.2, 1.44, -1.2],
                label: "起点",
                color: "blue",
                radius: 0.08,
              },
            ],
            readouts: [{ id: "height", label: "高度", value: 1.44, unit: "m", evidenceIDs: ["self-check"] }],
            evidenceIDs: ["self-check"],
          },
          {
            id: "after",
            title: "变化后",
            objectIds: ["paraboloid"],
            objects: [
              {
                id: "marker-after",
                kind: "point",
                layer: "slice",
                position: [1.2, 1.44, 1.2],
                label: "终点",
                color: "cinnabar",
                radius: 0.12,
              },
            ],
            readouts: [{ id: "height", label: "高度", value: 1.44, unit: "m", evidenceIDs: ["self-check"] }],
            evidenceIDs: ["self-check"],
          },
        ],
      },
    },
  },
  {
    name: "rejects duplicate state id",
    expectOk: false,
    plan: {
      ...baseScene3DPlan,
      spec: {
        ...baseScene3DPlan.spec,
        stateBinding: { initial: "same" },
        states: [
          { id: "same", objects: [{ id: "state-point-a", kind: "point", position: [0, 0, 0] }] },
          { id: "same", objects: [{ id: "state-point-b", kind: "point", position: [1, 0, 0] }] },
        ],
      },
    },
  },
  {
    name: "rejects missing initial state",
    expectOk: false,
    plan: {
      ...baseScene3DPlan,
      spec: {
        ...baseScene3DPlan.spec,
        stateBinding: { initial: "missing" },
        states: [{ id: "present", objects: [{ id: "state-point", kind: "point", position: [0, 0, 0] }] }],
      },
    },
  },
  {
    name: "rejects state object reference gap",
    expectOk: false,
    plan: {
      ...baseScene3DPlan,
      spec: {
        ...baseScene3DPlan.spec,
        stateBinding: { initial: "bad-ref" },
        states: [{ id: "bad-ref", objectIds: ["ghost-object"], readouts: [{ id: "status", label: "状态", value: "缺对象" }] }],
      },
    },
  },
  {
    name: "rejects molecule references to missing atom",
    expectOk: false,
    plan: {
      ...baseScene3DPlan,
      spec: {
        ...baseScene3DPlan.spec,
        objects: [
          {
            id: "bad-molecule",
            kind: "molecule",
            atoms: [{ id: "center", element: "N", label: "N", role: "central", position: [0, 0, 0] }],
            bonds: [{ from: "center", to: "ghost" }],
          },
        ],
      },
    },
  },
  {
    name: "rejects WebGL budget",
    expectOk: false,
    plan: {
      ...baseScene3DPlan,
      qualityBudget: { ...baseScene3DPlan.qualityBudget, allowWebGL: true },
    },
  },
  {
    name: "rejects malformed bounds",
    expectOk: false,
    plan: {
      ...baseScene3DPlan,
      spec: {
        ...baseScene3DPlan.spec,
        bounds: { x: { min: 2, max: -2 }, y: { min: -1, max: 4 }, z: { min: -2, max: 2 } },
      },
    },
  },
  {
    name: "rejects ragged surface grid",
    expectOk: false,
    plan: {
      ...baseScene3DPlan,
      spec: {
        ...baseScene3DPlan.spec,
        objects: [
          {
            id: "bad-surface",
            kind: "surface",
            xRange: { min: 0, max: 1 },
            zRange: { min: 0, max: 1 },
            yValues: [[0, 1], [1]],
          },
        ],
      },
    },
  },
] satisfies Array<{ name: string; expectOk: boolean; plan: RenderPlan }>;

export function runScene3DSelfChecks() {
  return scene3DSelfCheckCases.map((item) => {
    const result = parseScene3DSpec(item.plan);
    return {
      name: item.name,
      ok: result.ok === item.expectOk,
      result,
    };
  });
}
