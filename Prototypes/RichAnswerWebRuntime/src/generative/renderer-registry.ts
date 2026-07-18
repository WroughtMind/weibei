import type { ReactNode } from "react";
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
  graphics: Array<"dom" | "canvas" | "webgl">;
  data: string[];
  interactions: string[];
  resources: string[];
  maxNodes: number;
  maxSeries: number;
  fallback: Array<"static_snapshot" | "simplified_component" | "structured_error">;
};

export type RenderPlan = {
  protocol: "weibei.renderplan.v1";
  renderer: string;
  specVersion: string;
  spec: Record<string, unknown>;
  interactionBindings: Array<Record<string, unknown>>;
  sourceBindings: Array<Record<string, unknown>>;
  artifactRefs: Array<Record<string, unknown>>;
  fallback?: {
    kind: "static_snapshot" | "simplified_component" | "structured_error";
    reason: string;
    artifactRef?: string;
    summary?: string;
  };
  qualityBudget: {
    maxHeight: number;
    maxNodes: number;
    maxSeries: number;
    graphics: "dom" | "canvas" | "webgl";
    animation: "none" | "reduced" | "full";
    maxDataPoints: number;
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

const unsafeKeyFragments = [
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

const unsafeStringPattern = /<\/?(?:html|svg|script|iframe)\b|javascript:/i;

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
}

export function createRendererIssue(
  code: RendererIssueCode,
  renderer: string,
  message: string,
  details: string[] = [],
): RendererIssue {
  return { code, renderer, message, details };
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
      if (unsafeKeyFragments.some((fragment) => normalizedKey.includes(fragment))) {
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
