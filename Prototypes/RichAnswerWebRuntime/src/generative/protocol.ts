import { z } from "zod/v4";

const evidenceBindingSchema = z.object({
  id: z.string().min(1),
  sourceID: z.string().min(1),
  locator: z.string().min(1),
});

const evidenceContentSchema = z.object({
  id: z.string().min(1),
  sourceLabel: z.string().min(1),
  excerpt: z.string().min(1),
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
  heightLimit?: number;
} | {
  type: "weibei:setRenderPlans";
  renderPlans?: unknown[];
  plans?: unknown[];
  evidenceContent?: z.infer<typeof evidenceContentSchema>[];
  heightLimit?: number;
};

export type WeiBeiRuntimeMessage =
  | { type: "weibei:ready"; protocol: string }
  | { type: "weibei:height"; height: number; overflowed: boolean }
  | { type: "weibei:state"; programID: string; state: Record<string, unknown> }
  | { type: "weibei:evidence"; programID: string; evidenceID: string }
  | { type: "weibei:action"; programID: string; action: unknown }
  | { type: "weibei:error"; programID?: string; message: string };

interface WeiBeiRuntimeWindow extends Window {
  webkit?: {
    messageHandlers?: {
      weibeiRichAnswer?: {
        postMessage: (message: WeiBeiRuntimeMessage) => void;
      };
    };
  };
}

declare global {
  interface Window {
    __WEIBEI_EMBEDDED__?: boolean;
  }
}

export function postRuntimeMessage(message: WeiBeiRuntimeMessage) {
  (window as WeiBeiRuntimeWindow).webkit?.messageHandlers?.weibeiRichAnswer?.postMessage(message);
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
  return z.array(richAnswerProgramSchema).min(1).max(6).safeParse(value);
}

let hostEvidenceByID = new Map<string, z.infer<typeof evidenceContentSchema>>();

export function setHostEvidenceContent(items: z.infer<typeof evidenceContentSchema>[]) {
  hostEvidenceByID = new Map(items.map((item) => [item.id, item]));
}

export function hostEvidenceForID(evidenceID: string) {
  return hostEvidenceByID.get(evidenceID);
}
