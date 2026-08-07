import { createElement, type ReactNode } from "react";
import { z } from "zod/v4";
import type {
  RenderPlanBudgetContext,
  RichAnswerProgram,
  WeiBeiRuntimeMessage,
} from "./protocol";
import type {
  RenderGroupResourceLimits,
  RenderGroupResourceUsage,
} from "./render-group";

export type RendererIssueCode =
  | "capability_mismatch"
  | "validation_error"
  | "compile_error"
  | "unsafe_payload";

export type RendererIssue = {
  code: RendererIssueCode;
  renderer: string;
  message: string;
  details?: string[];
};

export type RendererValidationResult = {
  ok: true;
} | {
  ok: false;
  issue: RendererIssue;
};

export type RendererCompileResult = {
  ok: true;
  compiled: CompiledRenderPlan;
} | {
  ok: false;
  issue: RendererIssue;
};

export type RendererCapabilityDeclaration = {
  renderer: string;
  version: string;
  specVersions: string[];
  displayName: string;
  data: string[];
  interactions: string[];
  resources: string[];
  maxNodes: number;
  maxDataPoints: number;
  maxArtifacts: number;
  maxBytes: number;
  maxWidth: number;
  maxHeight: number;
  maxAnimationFPS: number;
  maxInteractionLatencyMS: number;
  allowAnimation: boolean;
  allowWebGL: boolean;
  allowNetwork: boolean;
  fallback: Array<"narrativeOnly">;
};

type HistoricalFallbackMode =
  | "artifactPreview"
  | "narrativeOnly"
  | "simplifiedRenderer"
  | "staticSnapshot";

export type RenderPlan = {
  renderer: string;
  specVersion: string;
  spec: Record<string, unknown>;
  interactionBindings: Array<Record<string, unknown>>;
  sourceBindings: Array<Record<string, unknown>>;
  artifactRefs: Array<Record<string, unknown>>;
  fallback: {
    mode: "narrativeOnly";
    reason: string;
    text: string;
    renderer?: string;
    artifactID?: string;
    preservesSourceBinding: boolean;
  };
  qualityBudget: {
    maxNodes?: number;
    maxHeight?: number;
    maxDataPoints?: number;
    maxArtifacts?: number;
    maxBytes?: number;
    maxWidth?: number;
    maxAnimationFPS?: number;
    maxInteractionLatencyMS?: number;
    allowAnimation: boolean;
    allowWebGL: boolean;
    allowNetwork: boolean;
  };
};

export type CompiledRenderPlan = {
  renderer: string;
  version: string;
  plan: RenderPlan;
  programID: string;
  title: string;
};

export type RendererLifecycleContext = {
  program: RichAnswerProgram;
  budgetContext?: RenderPlanBudgetContext;
  showNotice: (message: string) => void;
  postMessage: (message: WeiBeiRuntimeMessage) => void;
};

export type RichAnswerRenderer = {
  id: string;
  version: string;
  capabilities: RendererCapabilityDeclaration;
  validate: (plan: RenderPlan, context: RendererLifecycleContext) => RendererValidationResult;
  compile: (plan: RenderPlan, context: RendererLifecycleContext) => RendererCompileResult;
  mount: (compiled: CompiledRenderPlan, context: RendererLifecycleContext) => ReactNode;
  update: (compiled: CompiledRenderPlan, previous: CompiledRenderPlan | null, context: RendererLifecycleContext) => ReactNode;
  dispose: (compiled: CompiledRenderPlan, context: RendererLifecycleContext) => void;
  fallback: (plan: RenderPlan, issue: RendererIssue, context: RendererLifecycleContext) => ReactNode;
};

const unsafeKeyPrefixes = [
  "dangerouslysetinnerhtml",
  "echartsconfig",
  "echartsoption",
  "innerhtml",
  "javascript",
  "plotlyconfig",
  "plotlyfigure",
  "rawhtml",
  "rawjs",
  "script",
  "svg",
];

const unsafeKeyTokens = new Set(["html", "javascript", "script", "svg"]);

const unsafeStringPattern = /<\/?(?:html|svg|script|iframe)\b|javascript:/i;

// These maxima only admit a plan into the protocol. `validateRendererBudget`
// then applies the selected renderer's own, sometimes lower, capability.
export const formalRenderPlanAdmissionEnvelope = Object.freeze({
  maxNodes: 280,
  maxDataPoints: 8_000,
  maxArtifacts: 4,
  maxBytes: 1_500_000,
  maxWidth: 960,
  maxHeight: 720,
  maxAnimationFPS: 30,
  maxInteractionLatencyMS: 160,
});

export const formalTrustedAssetMaxBytes = 850_000;

export const formalRenderGroupResourceLimits: RenderGroupResourceLimits = Object.freeze({
  maxLogicalPlanBytes: formalRenderPlanAdmissionEnvelope.maxBytes,
  maxTrustedAssets: formalRenderPlanAdmissionEnvelope.maxArtifacts,
  maxTrustedAssetBytes: formalTrustedAssetMaxBytes,
  maxTrustedAssetTotalBytes:
    formalRenderPlanAdmissionEnvelope.maxArtifacts * formalTrustedAssetMaxBytes,
});

const renderPlanSchema = z.object({
  renderer: z.string().min(1),
  specVersion: z.string().min(1),
  spec: z.record(z.string(), z.unknown()),
  interactionBindings: z.array(z.record(z.string(), z.unknown())).default([]),
  sourceBindings: z.array(z.record(z.string(), z.unknown())).default([]),
  artifactRefs: z.array(z.record(z.string(), z.unknown())).default([]),
  fallback: z.object({
    mode: z.enum(["artifactPreview", "narrativeOnly", "simplifiedRenderer", "staticSnapshot"]),
    reason: z.string().min(1),
    text: z.string().min(1),
    renderer: z.string().min(1).optional(),
    artifactID: z.string().min(1).optional(),
    preservesSourceBinding: z.boolean().default(false),
  }).strict(),
  qualityBudget: z.object({
    maxNodes: z.number().int().min(1).max(formalRenderPlanAdmissionEnvelope.maxNodes).optional(),
    maxHeight: z.number().int().min(160).max(formalRenderPlanAdmissionEnvelope.maxHeight).optional(),
    maxDataPoints: z.number().int().min(1).max(formalRenderPlanAdmissionEnvelope.maxDataPoints).optional(),
    maxArtifacts: z.number().int().min(0).max(formalRenderPlanAdmissionEnvelope.maxArtifacts).optional(),
    maxBytes: z.number().int().min(1).max(formalRenderPlanAdmissionEnvelope.maxBytes).optional(),
    maxWidth: z.number().int().min(240).max(formalRenderPlanAdmissionEnvelope.maxWidth).optional(),
    maxAnimationFPS: z.number().int().min(0).max(formalRenderPlanAdmissionEnvelope.maxAnimationFPS).optional(),
    maxInteractionLatencyMS: z.number().int().min(1).max(formalRenderPlanAdmissionEnvelope.maxInteractionLatencyMS).optional(),
    allowAnimation: z.boolean(),
    allowWebGL: z.boolean(),
    allowNetwork: z.boolean(),
  }).strict(),
}).strict();

export class RendererRegistry {
  private readonly renderers = new Map<string, RichAnswerRenderer>();

  register(renderer: RichAnswerRenderer) {
    if (this.renderers.has(renderer.id)) {
      throw new Error(`Renderer already registered: ${renderer.id}`);
    }
    this.renderers.set(renderer.id, renderer);
    return this;
  }

  listCapabilities() {
    return [...this.renderers.values()].map((renderer) => renderer.capabilities);
  }

  rendererIDs() {
    return [...this.renderers.keys()];
  }

  resolve(plan: RenderPlan): { ok: true; renderer: RichAnswerRenderer } | { ok: false; issue: RendererIssue } {
    const renderer = this.renderers.get(plan.renderer);
    if (!renderer) {
      return {
        ok: false,
        issue: {
          code: "capability_mismatch",
          renderer: plan.renderer,
          message: `当前 Web 运行时未注册 ${plan.renderer} 渲染器，请 Agent 重新规划到已声明能力。`,
          details: [`已注册：${this.rendererIDs().join("、") || "无"}`],
        },
      };
    }
    return { ok: true, renderer };
  }

  validate(plan: RenderPlan, context: RendererLifecycleContext): RendererValidationResult {
    const unsafePath = findUnsafePayload(plan.spec);
    if (unsafePath) {
      return {
        ok: false,
        issue: {
          code: "unsafe_payload",
          renderer: plan.renderer,
          message: "renderPlan 含有被禁止的原始脚本、HTML、SVG 或裸图表配置。",
          details: [unsafePath],
        },
      };
    }

    const resolved = this.resolve(plan);
    if (!resolved.ok) return resolved;

    const budgetIssue = validateRendererBudget(
      plan,
      resolved.renderer.capabilities,
      context.budgetContext,
    );
    if (budgetIssue) return { ok: false, issue: budgetIssue };

    return resolved.renderer.validate(plan, context);
  }

  compile(plan: RenderPlan, context: RendererLifecycleContext): RendererCompileResult {
    const validation = this.validate(plan, context);
    if (!validation.ok) return validation;

    const resolved = this.resolve(plan);
    if (!resolved.ok) return resolved;

    return resolved.renderer.compile(plan, context);
  }

  mount(compiled: CompiledRenderPlan, context: RendererLifecycleContext) {
    const renderer = this.renderers.get(compiled.renderer);
    if (!renderer) {
      return this.fallback(
        compiled.plan,
        createRendererIssue("capability_mismatch", compiled.renderer, `当前 Web 运行时未注册 ${compiled.renderer} 渲染器。`),
        context,
      );
    }
    return renderer.mount(compiled, context);
  }

  update(compiled: CompiledRenderPlan, previous: CompiledRenderPlan | null, context: RendererLifecycleContext) {
    const renderer = this.renderers.get(compiled.renderer);
    if (!renderer) return this.mount(compiled, context);
    return renderer.update(compiled, previous, context);
  }

  dispose(compiled: CompiledRenderPlan, context: RendererLifecycleContext) {
    this.renderers.get(compiled.renderer)?.dispose(compiled, context);
  }

  fallback(plan: RenderPlan, issue: RendererIssue, _context: RendererLifecycleContext) {
    return createNarrativeFallbackNode(plan, issue);
  }
}

export function createNarrativeFallbackNode(
  plan: RenderPlan,
  issue: RendererIssue,
) {
  return createElement(
    "div",
    {
      className: "generation-fallback",
      role: "status",
      "data-weibei-fallback-mode": plan.fallback.mode,
      "data-weibei-renderer-issue": issue.code,
    },
    createElement("strong", null, plan.fallback.reason),
    createElement("span", null, plan.fallback.text),
  );
}

function validateRendererBudget(
  plan: RenderPlan,
  capabilities: RendererCapabilityDeclaration,
  budgetContext?: RenderPlanBudgetContext,
): RendererIssue | null {
  const declared = plan.qualityBudget;
  const numericLimits: Array<
    [keyof Pick<
      RendererCapabilityDeclaration,
      | "maxNodes"
      | "maxDataPoints"
      | "maxArtifacts"
      | "maxBytes"
      | "maxWidth"
      | "maxHeight"
      | "maxAnimationFPS"
      | "maxInteractionLatencyMS"
    >, number | undefined]
  > = [
    ["maxNodes", declared.maxNodes],
    ["maxDataPoints", declared.maxDataPoints],
    ["maxArtifacts", declared.maxArtifacts],
    ["maxBytes", declared.maxBytes],
    ["maxWidth", declared.maxWidth],
    ["maxHeight", declared.maxHeight],
    ["maxAnimationFPS", declared.maxAnimationFPS],
    ["maxInteractionLatencyMS", declared.maxInteractionLatencyMS],
  ];
  for (const [field, value] of numericLimits) {
    if (value !== undefined && value > capabilities[field]) {
      return createRendererIssue(
        "capability_mismatch",
        plan.renderer,
        `${field}=${value} 超过 ${plan.renderer} 已声明上限 ${capabilities[field]}。`,
      );
    }
  }
  const artifactBudget = declared.maxArtifacts ?? capabilities.maxArtifacts;
  if (plan.artifactRefs.length > artifactBudget || plan.artifactRefs.length > capabilities.maxArtifacts) {
    return createRendererIssue(
      "capability_mismatch",
      plan.renderer,
      `artifactRefs 数量 ${plan.artifactRefs.length} 超过 ${plan.renderer} 的素材上限。`,
    );
  }
  const measured = measureRenderPlanResourceUsage(plan, budgetContext);
  if (!measured.ok) return measured.issue;
  const { logicalPlanBytes, trustedAssetBytes } = measured.usage;
  if (
    trustedAssetBytes.length > capabilities.maxArtifacts
    || trustedAssetBytes.some((value) => value > formalTrustedAssetMaxBytes)
  ) {
    return createRendererIssue(
      "capability_mismatch",
      plan.renderer,
      `受信本地图片超过 ${capabilities.maxArtifacts} 个或单图 ${formalTrustedAssetMaxBytes} 字节上限。`,
    );
  }
  const byteBudget = declared.maxBytes ?? capabilities.maxBytes;
  if (logicalPlanBytes > byteBudget || logicalPlanBytes > capabilities.maxBytes) {
    return createRendererIssue(
      "capability_mismatch",
      plan.renderer,
      `renderPlan 原始规格 ${logicalPlanBytes} 字节超过 ${plan.renderer} 的规格预算。`,
    );
  }
  if (declared.allowAnimation && !capabilities.allowAnimation) {
    return createRendererIssue("capability_mismatch", plan.renderer, `${plan.renderer} 不允许动画。`);
  }
  if (declared.allowWebGL && !capabilities.allowWebGL) {
    return createRendererIssue("capability_mismatch", plan.renderer, `${plan.renderer} 不允许 WebGL。`);
  }
  if (declared.allowNetwork && !capabilities.allowNetwork) {
    return createRendererIssue("capability_mismatch", plan.renderer, `${plan.renderer} 不允许网络访问。`);
  }
  return null;
}

export function measureRenderPlanResourceUsage(
  plan: RenderPlan,
  budgetContext?: RenderPlanBudgetContext,
): { ok: true; usage: RenderGroupResourceUsage } | { ok: false; issue: RendererIssue } {
  const encodedBytes = new TextEncoder().encode(JSON.stringify(plan)).byteLength;
  const referencedAssetIDs = collectAssetRefIDs(plan.spec);
  for (const assetID of referencedAssetIDs) {
    const matchingArtifacts = plan.artifactRefs.filter((artifact) => artifact.id === assetID);
    if (
      matchingArtifacts.length !== 1
      || typeof matchingArtifacts[0].sizeBytes !== "number"
      || !Number.isSafeInteger(matchingArtifacts[0].sizeBytes)
      || matchingArtifacts[0].sizeBytes < 0
    ) {
      return {
        ok: false,
        issue: createRendererIssue(
          "unsafe_payload",
          plan.renderer,
          `assetRef ${assetID} 必须恰好对应一个带权威 sizeBytes 的 artifactRef。`,
        ),
      };
    }
  }
  const hasInvalidDeclaredAssetBytes = plan.artifactRefs.some((artifact) =>
    artifact.sizeBytes !== undefined
      && (typeof artifact.sizeBytes !== "number"
        || !Number.isSafeInteger(artifact.sizeBytes)
        || artifact.sizeBytes < 0));
  const declaredAssetBytes = plan.artifactRefs
    .filter((artifact) =>
      typeof artifact.id === "string" && referencedAssetIDs.has(artifact.id)
    )
    .map((artifact) =>
      typeof artifact.sizeBytes === "number" ? artifact.sizeBytes : 0);
  if (hasInvalidDeclaredAssetBytes) {
    return {
      ok: false,
      issue: createRendererIssue(
        "unsafe_payload",
        plan.renderer,
        "本地素材预算元数据无效。",
      ),
    };
  }
  const hasHostInjectedData = containsHostInjectedMarker(plan.spec);
  if (!budgetContext) {
    if (hasHostInjectedData) {
      return {
        ok: false,
        issue: createRendererIssue(
          "unsafe_payload",
          plan.renderer,
          "宿主补入的本地图片缺少权威预算元数据。",
        ),
      };
    }
    return {
      ok: true,
      usage: {
        logicalPlanBytes: encodedBytes,
        trustedAssetBytes: declaredAssetBytes,
      },
    };
  }

  const actualAssetBytes = collectHostInjectedDataURLBytes(plan.spec)
    .sort((left, right) => left - right);
  const trustedAssetBytes = [...budgetContext.trustedAssetBytes].sort((left, right) => left - right);
  if (
    !Number.isSafeInteger(budgetContext.logicalPlanBytes)
    || budgetContext.logicalPlanBytes < 1
    || trustedAssetBytes.some((value) => !Number.isSafeInteger(value) || value < 0)
    || (hasHostInjectedData && (!actualAssetBytes.length || !trustedAssetBytes.length))
  ) {
    return {
      ok: false,
      issue: createRendererIssue(
        "unsafe_payload",
        plan.renderer,
        "宿主补入的本地图片预算元数据与实际内容不一致。",
      ),
    };
  }
  if (
    actualAssetBytes.length !== trustedAssetBytes.length
    || actualAssetBytes.some((value, index) => value !== trustedAssetBytes[index])
  ) {
    return {
      ok: false,
      issue: createRendererIssue(
        "unsafe_payload",
        plan.renderer,
        "宿主补入的本地图片预算元数据与实际内容不一致。",
      ),
    };
  }
  return {
    ok: true,
    usage: {
      logicalPlanBytes: budgetContext.logicalPlanBytes,
      trustedAssetBytes: trustedAssetBytes.length ? trustedAssetBytes : declaredAssetBytes,
    },
  };
}

export function createRendererIssue(
  code: RendererIssueCode,
  renderer: string,
  message: string,
  details: string[] = [],
): RendererIssue {
  return { code, renderer, message, details };
}

export function parseRenderPlan(value: unknown) {
  const result = renderPlanSchema.safeParse(value);
  return result.success
    ? { success: true as const, data: normalizeHistoricalFallback(result.data) }
    : result;
}

export function parseRenderPlans(value: unknown) {
  const group = z.array(z.unknown()).min(1).max(6).safeParse(value);
  if (!group.success) return group;

  const data: RenderPlan[] = [];
  const indices: number[] = [];
  const issues: Array<{ index: number; message: string }> = [];
  group.data.forEach((candidate, index) => {
    const parsed = parseRenderPlan(candidate);
    if (parsed.success) {
      data.push(parsed.data);
      indices.push(index);
    } else {
      issues.push({
        index,
        message: parsed.error.issues[0]?.message ?? "渲染计划不符合协议。",
      });
    }
  });
  return data.length > 0
    ? { success: true as const, data, indices, issues }
    : { success: false as const, error: { issues }, issues };
}

function normalizeHistoricalFallback(
  plan: z.infer<typeof renderPlanSchema>,
): RenderPlan {
  const mode = plan.fallback.mode as HistoricalFallbackMode;
  if (mode === "narrativeOnly") return plan as RenderPlan;
  return {
    ...plan,
    fallback: {
      ...plan.fallback,
      mode: "narrativeOnly",
      renderer: undefined,
      artifactID: undefined,
    },
  };
}

function collectAssetRefIDs(value: unknown, result = new Set<string>()): Set<string> {
  if (Array.isArray(value)) {
    value.forEach((item) => collectAssetRefIDs(item, result));
    return result;
  }
  if (!value || typeof value !== "object") return result;
  const record = value as Record<string, unknown>;
  if (
    record.kind === "assetRef"
    && typeof record.source === "string"
    && record.source.trim().length > 0
  ) {
    result.add(record.source.trim());
  }
  Object.values(record).forEach((item) => collectAssetRefIDs(item, result));
  return result;
}

function collectHostInjectedDataURLBytes(value: unknown): number[] {
  if (Array.isArray(value)) return value.flatMap(collectHostInjectedDataURLBytes);
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    const ownBytes = record._weibeiHostInjected === true
      ? dataURLBytes(record.source)
      : [];
    return [
      ...ownBytes,
      ...Object.entries(record)
        .filter(([key]) => key !== "source")
        .flatMap(([, child]) => collectHostInjectedDataURLBytes(child)),
    ];
  }
  return [];
}

function containsHostInjectedMarker(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsHostInjectedMarker);
  if (!value || typeof value !== "object") return false;
  const record = value as Record<string, unknown>;
  return record._weibeiHostInjected === true
    || Object.values(record).some(containsHostInjectedMarker);
}

function dataURLBytes(value: unknown): number[] {
  if (typeof value !== "string") return [];
  const match = /^data:image\/(?:png|jpe?g|webp|gif);base64,([A-Za-z0-9+/]*={0,2})$/i.exec(value);
  if (!match) return [];
  const base64 = match[1];
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return [Math.floor(base64.length * 3 / 4) - padding];
}

function findUnsafePayload(value: unknown, path = "spec"): string | null {
  if (Array.isArray(value)) {
    for (let index = 0; index < value.length; index += 1) {
      const child = findUnsafePayload(value[index], `${path}[${index}]`);
      if (child) return child;
    }
    return null;
  }

  if (value && typeof value === "object") {
    for (const [key, childValue] of Object.entries(value)) {
      const normalizedKey = key.toLowerCase().replace(/[^a-z0-9]/g, "");
      const keyTokens = key
        .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
        .split(/[^a-zA-Z0-9]+/)
        .map((token) => token.toLowerCase())
        .filter(Boolean);
      if (
        unsafeKeyPrefixes.some((fragment) => normalizedKey.startsWith(fragment))
        || keyTokens.some((token) => unsafeKeyTokens.has(token))
      ) {
        return `${path}.${key}`;
      }
      const child = findUnsafePayload(childValue, `${path}.${key}`);
      if (child) return child;
    }
    return null;
  }

  if (typeof value === "string" && unsafeStringPattern.test(value)) {
    return path;
  }

  return null;
}
