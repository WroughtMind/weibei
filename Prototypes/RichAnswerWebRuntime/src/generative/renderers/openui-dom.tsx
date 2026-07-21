import { useEffect, useState } from "react";
import { Renderer } from "@openuidev/react-lang";
import type { ActionEvent, OpenUIError } from "@openuidev/react-lang";
import { z } from "zod/v4";
import { weiBeiGenerativeLibrary } from "../library";
import {
  createRendererIssue,
  type CompiledRenderPlan,
  type RenderPlan,
  type RendererLifecycleContext,
  type RichAnswerRenderer,
} from "../renderer-registry";

const OPENUI_DOM_RENDERER = "weibei.openui.dom";
const OPENUI_DOM_SPEC_VERSION = "1.0";

const renderBudgetSchema = z.object({
  maxHeight: z.number().int().min(160).max(720),
  maxNodes: z.number().int().min(1).max(120),
  maxSeries: z.number().int().min(1).max(12),
  graphics: z.enum(["dom", "canvas", "webgl"]),
});

const openUISpecSchema = z.object({
  version: z.literal("weibei.openui.v1"),
  mode: z.literal("declarative"),
  source: z.string().min(1).max(40000),
  initialState: z.record(z.string(), z.unknown()).optional(),
  capabilities: z.array(z.string().min(1)).min(1),
  budget: renderBudgetSchema,
}).strict();

type OpenUISpec = z.infer<typeof openUISpecSchema>;

type OpenUICompiledRenderPlan = CompiledRenderPlan & {
  source: string;
  initialState: Record<string, unknown>;
  capabilities: string[];
  graphics: "dom" | "canvas" | "webgl";
};

const canvasComponents = [
  "FunctionPlot(",
  "LinkedDataChart(",
  "TwoPointLineLab(",
  "LayeredSpatialView(",
  "DistributionBrush(",
];

function guardOpenUISpec(plan: RenderPlan, spec: OpenUISpec) {
  if (plan.renderer !== OPENUI_DOM_RENDERER) {
    return createRendererIssue("capability_mismatch", plan.renderer, `OpenUI DOM 适配器不能渲染 ${plan.renderer}。`);
  }
  if (plan.specVersion !== OPENUI_DOM_SPEC_VERSION) {
    return createRendererIssue("capability_mismatch", plan.renderer, `OpenUI DOM 适配器只支持规格 ${OPENUI_DOM_SPEC_VERSION}。`);
  }

  const statementCount = spec.source.split("\n").filter((line) => line.trim()).length;
  if (statementCount > spec.budget.maxNodes || statementCount > plan.qualityBudget.maxNodes) {
    return createRendererIssue(
      "validation_error",
      plan.renderer,
      `界面程序有 ${statementCount} 条语句，超过节点预算。`,
      [`program=${spec.budget.maxNodes}`, `renderPlan=${plan.qualityBudget.maxNodes}`],
    );
  }
  if (/<\/?(?:svg|script|iframe|html)\b|javascript:/i.test(spec.source)) {
    return createRendererIssue("unsafe_payload", plan.renderer, "OpenUI DOM 通道不接受 HTML、SVG、script、iframe 或 javascript URL。");
  }
  if (/\b(?:eval|import|export)\b|=>|new\s+Function\b/i.test(spec.source)) {
    return createRendererIssue("unsafe_payload", plan.renderer, "OpenUI DOM 通道不接受原始 JavaScript。");
  }
  if (/\b(?:echarts|plotly)\b/i.test(spec.source)) {
    return createRendererIssue("unsafe_payload", plan.renderer, "OpenUI DOM 通道不接受裸 ECharts 或 Plotly 配置。");
  }
  if (spec.budget.graphics === "dom" && canvasComponents.some((component) => spec.source.includes(component))) {
    return createRendererIssue("validation_error", plan.renderer, "当前程序使用 Canvas 图形组件，但没有声明 Canvas 图形预算。");
  }
  if (!plan.qualityBudget.graphics || plan.qualityBudget.graphics !== spec.budget.graphics) {
    return createRendererIssue(
      "capability_mismatch",
      plan.renderer,
      "renderPlan 的图形预算与 OpenUI program 不一致，请重新协商能力。",
      [`program=${spec.budget.graphics}`, `renderPlan=${plan.qualityBudget.graphics}`],
    );
  }

  return null;
}

function parseOpenUISpec(plan: RenderPlan) {
  const result = openUISpecSchema.safeParse(plan.spec);
  if (!result.success) {
    return {
      ok: false as const,
      issue: createRendererIssue(
        "validation_error",
        plan.renderer,
        result.error.issues[0]?.message ?? "OpenUI DOM 规格不符合协议。",
        result.error.issues.map((issue) => issue.path.join(".")).filter(Boolean),
      ),
    };
  }

  const guardIssue = guardOpenUISpec(plan, result.data);
  if (guardIssue) {
    return { ok: false as const, issue: guardIssue };
  }

  return { ok: true as const, spec: result.data };
}

function OpenUIDomMount({
  compiled,
  context,
}: {
  compiled: OpenUICompiledRenderPlan;
  context: RendererLifecycleContext;
}) {
  const [errors, setErrors] = useState<OpenUIError[]>([]);
  const [runtimeState, setRuntimeState] = useState<Record<string, unknown>>(compiled.initialState);
  const [parseReady, setParseReady] = useState(false);

  useEffect(() => {
    setRuntimeState(compiled.initialState);
    setErrors([]);
    setParseReady(false);
  }, [compiled.programID, compiled.source, compiled.initialState]);

  useEffect(() => {
    if (!errors.length) return;
    context.postMessage({
      type: "weibei:error",
      programID: compiled.programID,
      message: errors.map((error) => error.message).join("；"),
    });
  }, [compiled.programID, compiled.renderer, context, errors]);

  function handleStateUpdate(state: Record<string, unknown>) {
    setRuntimeState(state);
    context.postMessage({ type: "weibei:state", programID: compiled.programID, state });
  }

  function handleAction(action: ActionEvent) {
    context.showNotice(`已交给 Agent·${action.humanFriendlyMessage}`);
    context.postMessage({ type: "weibei:action", programID: compiled.programID, action });
  }

  return (
    <>
      <div className="generation-answer__status">
        <span>{parseReady && !errors.length ? "渲染计划已通过验证" : "正在校验渲染计划"}</span>
        <i>{compiled.graphics === "canvas" ? "OpenUI DOM + Canvas 组件" : "OpenUI DOM 组件"}</i>
      </div>
      <Renderer
        response={compiled.source}
        library={weiBeiGenerativeLibrary}
        isStreaming={false}
        initialState={runtimeState}
        onStateUpdate={handleStateUpdate}
        onAction={handleAction}
        onError={setErrors}
        onParseResult={(result) => setParseReady(Boolean(result && result.meta.unresolved.length === 0))}
      />
      {errors.length ? (
        <p className="generation-error">协议渲染失败：{errors.map((error) => error.message).join("；")}</p>
      ) : null}
    </>
  );
}

function OpenUIDomFallback({
  issue,
}: {
  issue: ReturnType<typeof createRendererIssue>;
}) {
  return (
    <div className="generation-error" role="alert" data-weibei-renderer-issue={issue.code}>
      <strong>{issue.code === "capability_mismatch" ? "渲染器能力不匹配" : "渲染计划未通过"}</strong>
      <span>{issue.message}</span>
      {issue.details?.length ? <small>{issue.details.join("；")}</small> : null}
    </div>
  );
}

export const openUIDomRenderer: RichAnswerRenderer = {
  id: OPENUI_DOM_RENDERER,
  version: "0.1.0",
  capabilities: {
    renderer: OPENUI_DOM_RENDERER,
    version: "0.1.0",
    specVersions: [OPENUI_DOM_SPEC_VERSION],
    displayName: "OpenUI DOM 适配器",
    graphics: ["dom", "canvas"],
    data: ["inline-openui-state", "bounded-series", "source-bound-evidence"],
    interactions: ["state-update", "agent-action", "evidence-jump"],
    resources: ["react-lang-library", "trusted-echarts-wrapper"],
    maxNodes: 120,
    maxSeries: 12,
    fallback: ["structured_error"],
  },
  validate(plan) {
    const parsed = parseOpenUISpec(plan);
    return parsed.ok ? { ok: true } : { ok: false, issue: parsed.issue };
  },
  compile(plan, context) {
    const parsed = parseOpenUISpec(plan);
    if (!parsed.ok) return { ok: false, issue: parsed.issue };

    return {
      ok: true,
      compiled: {
        renderer: OPENUI_DOM_RENDERER,
        version: OPENUI_DOM_SPEC_VERSION,
        plan,
        programID: context.program.id,
        title: context.program.title,
        source: parsed.spec.source,
        initialState: parsed.spec.initialState ?? {},
        capabilities: parsed.spec.capabilities,
        graphics: parsed.spec.budget.graphics,
      },
    };
  },
  mount(compiled, context) {
    return <OpenUIDomMount compiled={compiled as OpenUICompiledRenderPlan} context={context} />;
  },
  update(compiled, _previous, context) {
    return <OpenUIDomMount compiled={compiled as OpenUICompiledRenderPlan} context={context} />;
  },
  dispose() {
    return undefined;
  },
  fallback(issue) {
    return <OpenUIDomFallback issue={issue} />;
  },
};
