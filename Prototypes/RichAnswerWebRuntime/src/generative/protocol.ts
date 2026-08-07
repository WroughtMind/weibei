import { z } from "zod/v4";

const evidenceBindingSchema = z.object({
  id: z.string().min(1),
  sourceID: z.string().min(1),
  locator: z.string().min(1),
});

const evidenceContentSchema = z.object({
  id: z.string().min(1),
  sourceLabel: z.string().default(""),
  excerpt: z.string().default(""),
  isTruncated: z.boolean(),
});

const renderBudgetSchema = z.object({
  maxHeight: z.number().int().min(160).max(720),
  maxNodes: z.number().int().min(1).max(120),
  maxSeries: z.number().int().min(1).max(12),
  graphics: z.enum(["dom", "canvas", "webgl"]),
});

export const richAnswerProgramSchema = z.object({
  version: z.literal("weibei.openui.v1"),
  id: z.string().min(1),
  title: z.string().min(1),
  question: z.string().min(1),
  mode: z.literal("declarative"),
  source: z.string().min(1),
  initialState: z.record(z.string(), z.unknown()).optional(),
  capabilities: z.array(z.string().min(1)).min(1),
  evidenceBindings: z.array(evidenceBindingSchema),
  evidenceContent: z.array(evidenceContentSchema).optional(),
  budget: renderBudgetSchema,
});

export type RichAnswerProgram = z.infer<typeof richAnswerProgramSchema>;

export type RenderPlanBudgetContext = {
  logicalPlanBytes: number;
  trustedAssetBytes: number[];
};

export type HostItemFailure = {
  index: number;
  programID: string;
  title: string;
  fallbackReason: string;
  fallbackText: string;
};

export type WeiBeiHostMessage = {
  type: "weibei:setProgram";
  program: RichAnswerProgram;
  heightLimit?: number;
} | {
  type: "weibei:setPrograms";
  programs: RichAnswerProgram[];
  heightLimit: number;
} | {
  type: "weibei:setRenderPlan";
  renderPlan?: unknown;
  plan?: unknown;
  evidenceContent?: z.infer<typeof evidenceContentSchema>[];
  budgetContext?: RenderPlanBudgetContext;
  itemFailures?: HostItemFailure[];
  sourceIndex?: number;
  heightLimit?: number;
} | {
  type: "weibei:setRenderPlans";
  renderPlans?: unknown[];
  plans?: unknown[];
  evidenceContent?: z.infer<typeof evidenceContentSchema>[];
  budgetContexts?: RenderPlanBudgetContext[];
  itemFailures?: HostItemFailure[];
  sourceIndices?: number[];
  heightLimit?: number;
} | {
  type: "weibei:setRenderFailures";
  itemFailures: HostItemFailure[];
  heightLimit?: number;
};

export type WeiBeiRuntimeMessage =
  | { type: "weibei:ready"; protocol: string }
  | { type: "weibei:height"; height: number; overflowed: boolean }
  | { type: "weibei:state"; programID: string; state: Record<string, unknown> }
  | { type: "weibei:evidence"; programID: string; evidenceID: string }
  | { type: "weibei:action"; programID: string; action: unknown }
  | { type: "weibei:error"; programID?: string; message: string; fatal?: boolean };

declare global {
  interface Window {
    __WEIBEI_EMBEDDED__?: boolean;
    webkit?: {
      messageHandlers?: {
        weibeiRichAnswer?: {
          postMessage: (message: WeiBeiRuntimeMessage) => void;
        };
      };
    };
  }
}

export function postRuntimeMessage(message: WeiBeiRuntimeMessage) {
  window.webkit?.messageHandlers?.weibeiRichAnswer?.postMessage(message);
  if (window.parent !== window) {
    window.parent.postMessage(message, "*");
  }
}

export function isEmbeddedRuntime() {
  return window.__WEIBEI_EMBEDDED__ === true
    || new URLSearchParams(window.location.search).get("embed") === "1";
}

export function parseHostProgram(value: unknown) {
  return richAnswerProgramSchema.safeParse(value);
}

export function parseHostPrograms(value: unknown) {
  const group = z.array(z.unknown()).min(1).max(6).safeParse(value);
  if (!group.success) return group;

  const data: RichAnswerProgram[] = [];
  const indices: number[] = [];
  const issues: Array<{ index: number; message: string }> = [];
  group.data.forEach((candidate, index) => {
    const parsed = richAnswerProgramSchema.safeParse(candidate);
    if (parsed.success) {
      data.push(parsed.data);
      indices.push(index);
    } else {
      issues.push({
        index,
        message: parsed.error.issues[0]?.message ?? "界面程序不符合协议。",
      });
    }
  });
  return data.length > 0
    ? { success: true as const, data, indices, issues }
    : { success: false as const, error: { issues }, issues };
}

let hostEvidenceByID = new Map<string, z.infer<typeof evidenceContentSchema>>();

export function setHostEvidenceContent(items: z.infer<typeof evidenceContentSchema>[]) {
  hostEvidenceByID = new Map(items.map((item) => [item.id, item]));
}

export function hostEvidenceForID(evidenceID: string) {
  return hostEvidenceByID.get(evidenceID);
}
