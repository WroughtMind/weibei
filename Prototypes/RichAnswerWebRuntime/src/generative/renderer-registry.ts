import { createElement, type ReactNode } from "react";
import { z } from "zod/v4";
import type { RichAnswerProgram, WeiBeiRuntimeMessage } from "./protocol";

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
  fallback: Array<"static_snapshot" | "simplified_component" | "structured_error">;
};

export type RenderPlan = {
  renderer: string;
  specVersion: string;
  spec: Record<string, unknown>;
  interactionBindings: Array<Record<string, unknown>>;
  sourceBindings: Array<Record<string, unknown>>;
  artifactRefs: Array<Record<string, unknown>>;
  fallback: {
    mode: "artifactPreview" | "narrativeOnly" | "simplifiedRenderer" | "staticSnapshot";
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
  fallback: (issue: RendererIssue, context: RendererLifecycleContext) => ReactNode;
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

const renderPlanSchema = z.object({
  renderer: z.string().min(1),
  specVersion: z.string().min(1),
  spec: z.record(z.string(), z.unknown()),
  interactionBindings: z.array(z.record(z.string(), z.unknown())).default([]),
  sourceBindings: z.array(z.record(z.string(), z.unknown())).min(1),
  artifactRefs: z.array(z.record(z.string(), z.unknown())).default([]),
  fallback: z.object({
    mode: z.enum(["artifactPreview", "narrativeOnly", "simplifiedRenderer", "staticSnapshot"]),
    reason: z.string().min(1),
    text: z.string().min(1),
    renderer: z.string().min(1).optional(),
    artifactID: z.string().min(1).optional(),
    preservesSourceBinding: z.boolean(),
  }).strict(),
  qualityBudget: z.object({
    maxNodes: z.number().int().min(1).max(1000).optional(),
    maxHeight: z.number().int().min(120).max(2400).optional(),
    maxDataPoints: z.number().int().min(1).max(20000).optional(),
    maxArtifacts: z.number().int().min(0).max(64).optional(),
    maxBytes: z.number().int().min(1).max(8_000_000).optional(),
    maxWidth: z.number().int().min(120).max(4000).optional(),
    maxAnimationFPS: z.number().int().min(0).max(120).optional(),
    maxInteractionLatencyMS: z.number().int().min(1).max(10_000).optional(),
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

  fallback(issue: RendererIssue, context: RendererLifecycleContext) {
    const renderer = this.renderers.get(issue.renderer);
    if (renderer) return renderer.fallback(issue, context);
    return createElement(
      "div",
      { className: "generation-error", role: "alert", "data-weibei-renderer-issue": issue.code },
      createElement("strong", null, "渲染器未注册"),
      createElement("span", null, issue.message),
      issue.details?.length ? createElement("small", null, issue.details.join("；")) : null,
    );
  }
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
  return renderPlanSchema.safeParse(value);
}

export function parseRenderPlans(value: unknown) {
  return z.array(renderPlanSchema).min(1).max(6).safeParse(value);
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
