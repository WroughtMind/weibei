import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { Renderer } from "@openuidev/react-lang";
import type { ActionEvent, OpenUIError } from "@openuidev/react-lang";
import { weiBeiGenerativeLibrary } from "./library";
import { generatedPrograms, programForID } from "./programs";
import {
  RendererRegistry,
  parseRenderPlan,
  parseRenderPlans,
  type CompiledRenderPlan,
  type RenderPlan,
  type RendererIssue,
  type RendererLifecycleContext,
} from "./renderer-registry";
import { standardEChartsRenderer } from "./renderers/echarts-chart";
import { geometry2DRenderer } from "./renderers/geometry-2d";
import { imageOverlayRenderer } from "./renderers/image-overlay";
import { mathFunctionRenderer } from "./renderers/math-function";
import { openUIDomRenderer } from "./renderers/openui-dom";
import { scene3DRenderer } from "./renderers/scene-3d";
import { spatialMapRenderer } from "./renderers/spatial-map";
import {
  parseHostProgram,
  parseHostPrograms,
  isEmbeddedRuntime,
  postRuntimeMessage,
  setHostEvidenceContent,
  type RichAnswerProgram,
  type WeiBeiHostMessage,
} from "./protocol";
import "./workbench.css";

const renderRegistry = new RendererRegistry()
  .register(openUIDomRenderer)
  .register(standardEChartsRenderer)
  .register(mathFunctionRenderer)
  .register(geometry2DRenderer)
  .register(scene3DRenderer)
  .register(spatialMapRenderer)
  .register(imageOverlayRenderer);

function programFromURL() {
  const parameters = new URLSearchParams(window.location.search);
  const programID = parameters.get("program");
  if (isEmbeddedRuntime() && !programID) return null;
  return programForID(programID);
}

function programGuard(program: RichAnswerProgram) {
  const statementCount = program.source.split("\n").filter((line) => line.trim()).length;
  if (statementCount > program.budget.maxNodes) {
    return `界面程序有 ${statementCount} 条语句，超过上限 ${program.budget.maxNodes}。`;
  }
  if (/<\/?(?:svg|script|iframe)\b/i.test(program.source)) {
    return "默认声明式通道不接受 SVG、script 或 iframe。";
  }
  if (
    program.budget.graphics === "dom" &&
    [
      "FunctionPlot(",
      "LinkedDataChart(",
      "TwoPointLineLab(",
      "LayeredSpatialView(",
      "DistributionBrush(",
    ].some((component) => program.source.includes(component))
  ) {
    return "当前程序使用 Canvas 图形组件，但没有声明 Canvas 图形预算。";
  }
  return null;
}

function updateURL(program: RichAnswerProgram) {
  const url = new URL(window.location.href);
  url.searchParams.set("program", program.id);
  url.searchParams.delete("case");
  window.history.pushState({}, "", url);
}

type ProgramRendererProps = {
  program: RichAnswerProgram;
  showNotice: (message: string) => void;
};

function ProgramRenderer({ program, showNotice }: ProgramRendererProps) {
  const [errors, setErrors] = useState<OpenUIError[]>([]);
  const [runtimeState, setRuntimeState] = useState<Record<string, unknown>>(program.initialState ?? {});
  const [parseReady, setParseReady] = useState(false);
  const guardError = useMemo(() => programGuard(program), [program]);

  useEffect(() => {
    if (!errors.length) return;
    postRuntimeMessage({
      type: "weibei:error",
      programID: program.id,
      message: errors.map((error) => error.message).join("；"),
    });
  }, [errors, program.id]);

  function handleStateUpdate(state: Record<string, unknown>) {
    setRuntimeState(state);
    postRuntimeMessage({ type: "weibei:state", programID: program.id, state });
  }

  function handleAction(action: ActionEvent) {
    showNotice(`已交给 Agent·${action.humanFriendlyMessage}`);
    postRuntimeMessage({ type: "weibei:action", programID: program.id, action });
  }

  return (
    <section className="generation-answer__program" aria-label={program.title}>
      <div className="generation-answer__status">
        <span>{parseReady && !errors.length && !guardError ? "程序已通过验证" : "正在校验界面程序"}</span>
        <i>{program.budget.graphics === "canvas" ? "Canvas 图形内核" : "HTML 交互内核"}</i>
      </div>
      {guardError ? (
        <p className="generation-error">{guardError}</p>
      ) : (
        <Renderer
          response={program.source}
          library={weiBeiGenerativeLibrary}
          isStreaming={false}
          initialState={runtimeState}
          onStateUpdate={handleStateUpdate}
          onAction={handleAction}
          onError={setErrors}
          onParseResult={(result) => setParseReady(Boolean(result && result.meta.unresolved.length === 0))}
        />
      )}
      {errors.length ? (
        <p className="generation-error">协议渲染失败：{errors.map((error) => error.message).join("；")}</p>
      ) : null}
    </section>
  );
}

type RenderSet = {
  entries: RenderEntry[];
  heightLimit: number;
};

type RenderEntry = {
  key: string;
  program: RichAnswerProgram;
  plan?: RenderPlan;
  compiled?: CompiledRenderPlan;
  issue?: RendererIssue;
};

function programEntry(program: RichAnswerProgram): RenderEntry {
  return { key: `program:${program.id}:${program.source}`, program };
}

function programForRenderPlan(plan: RenderPlan, index: number): RichAnswerProgram {
  const title = titleFromRenderPlan(plan, index);

  return {
    version: "weibei.openui.v1",
    id: renderPlanID(plan, index, title),
    title,
    question: title,
    mode: "declarative",
    source: "",
    initialState: {},
    capabilities: [plan.renderer, plan.specVersion],
    evidenceBindings: evidenceBindingsFromRenderPlan(plan),
    budget: {
      maxHeight: plan.qualityBudget.maxHeight ?? 360,
      maxNodes: Math.min(120, plan.qualityBudget.maxNodes ?? 24),
      maxSeries: 1,
      graphics: plan.qualityBudget.allowWebGL ? "webgl" : "canvas",
    },
  };
}

function titleFromRenderPlan(plan: RenderPlan, index: number) {
  const title = plan.spec.title;
  if (typeof title === "string" && title.trim()) return title.trim();
  return `开放渲染 ${index + 1}`;
}

function renderPlanID(plan: RenderPlan, index: number, title: string) {
  const artifactID = firstString(plan.artifactRefs, ["id", "artifactID", "artifactRef"]);
  const sourceID = firstString(plan.sourceBindings, ["id", "sourceID", "evidenceID"]);
  const seed = artifactID ?? sourceID ?? title;
  return `render-plan-${index + 1}-${slug(plan.renderer)}-${slug(seed)}`;
}

function firstString(records: Array<Record<string, unknown>>, keys: string[]) {
  for (const record of records) {
    for (const key of keys) {
      const value = record[key];
      if (typeof value === "string" && value.trim()) return value.trim();
    }
  }
  return null;
}

function slug(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9\u4e00-\u9fff]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 64) || "inline";
}

function evidenceBindingsFromRenderPlan(plan: RenderPlan): RichAnswerProgram["evidenceBindings"] {
  return plan.sourceBindings.flatMap((binding, index) => {
    const id = stringField(binding, "id") ?? stringField(binding, "evidenceID") ?? `source-${index + 1}`;
    const sourceID = stringField(binding, "sourceID") ?? stringField(binding, "sourceId") ?? stringField(binding, "source");
    const locator = stringField(binding, "locator") ?? stringField(binding, "range") ?? stringField(binding, "quote");
    return sourceID && locator ? [{ id, sourceID, locator }] : [];
  });
}

function stringField(record: Record<string, unknown>, key: string) {
  const value = record[key];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function lifecycleContext(program: RichAnswerProgram, showNotice: (message: string) => void): RendererLifecycleContext {
  return {
    program,
    showNotice,
    postMessage: postRuntimeMessage,
  };
}

function compileRenderPlans(plans: RenderPlan[], showNotice: (message: string) => void): RenderEntry[] {
  return plans.slice(0, 6).map((plan, index) => {
    const program = programForRenderPlan(plan, index);
    const context = lifecycleContext(program, showNotice);
    const compiled = renderRegistry.compile(plan, context);
    if (!compiled.ok) {
      postRuntimeMessage({ type: "weibei:error", programID: program.id, message: compiled.issue.message });
      return {
        key: `plan:${index}:${plan.renderer}:${plan.specVersion}:compile:${compiled.issue.message}`,
        program,
        plan,
        issue: compiled.issue,
      };
    }

    return {
      key: `plan:${index}:${plan.renderer}:${plan.specVersion}:${JSON.stringify(plan.spec)}`,
      program,
      plan,
      compiled: compiled.compiled,
    };
  });
}

function RenderPlanRenderer({
  entry,
  showNotice,
}: {
  entry: RenderEntry;
  showNotice: (message: string) => void;
}) {
  const previousRef = useRef<CompiledRenderPlan | null>(null);
  const context = useMemo(() => lifecycleContext(entry.program, showNotice), [entry.program, showNotice]);
  const compiled = entry.compiled;

  useEffect(() => {
    if (!compiled) return;
    previousRef.current = compiled;
    return () => renderRegistry.dispose(compiled, context);
  }, [compiled, context]);

  if (!compiled) return null;
  return <>{previousRef.current ? renderRegistry.update(compiled, previousRef.current, context) : renderRegistry.mount(compiled, context)}</>;
}

function RenderPlanFallback({
  entry,
  showNotice,
}: {
  entry: RenderEntry;
  showNotice: (message: string) => void;
}) {
  const context = useMemo(() => lifecycleContext(entry.program, showNotice), [entry.program, showNotice]);
  if (!entry.issue) return null;
  if (entry.plan?.fallback.text) {
    return (
      <div className="generation-error" role="alert" data-weibei-renderer-issue={entry.issue.code}>
        <strong>{entry.plan.fallback.reason}</strong>
        <span>{entry.plan.fallback.text}</span>
        <small>{entry.issue.message}</small>
      </div>
    );
  }
  return <>{renderRegistry.fallback(entry.issue, context)}</>;
}

function normalizedHeightLimit(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(160, Math.min(2400, Math.round(value)))
    : fallback;
}

export function GenerativeWorkbench() {
  const [renderSet, setRenderSet] = useState<RenderSet>(() => {
    const program = programFromURL();
    return program
      ? { entries: [programEntry(program)], heightLimit: program.budget.maxHeight }
      : { entries: [], heightLimit: 160 };
  });
  const [notice, setNotice] = useState<string | null>(null);
  const noticeTimerRef = useRef<number | null>(null);
  const pageRef = useRef<HTMLElement>(null);
  const renderSetRef = useRef(renderSet);
  const embedded = isEmbeddedRuntime();
  const waitingForHost = renderSet.entries.length === 0;
  const hasOpenRuntimeEntries = renderSet.entries.some((entry) => entry.compiled || entry.issue);
  const program = hasOpenRuntimeEntries ? null : (renderSet.entries[0]?.program ?? null);
  renderSetRef.current = renderSet;

  useLayoutEffect(() => {
    document.documentElement.classList.toggle("weibei-embedded", embedded);
    return () => document.documentElement.classList.remove("weibei-embedded");
  }, [embedded]);

  useEffect(() => {
    const onPopState = () => {
      const next = programFromURL();
      if (!next) {
        setHostEvidenceContent([]);
        setRenderSet({ entries: [], heightLimit: 160 });
        return;
      }
      setRenderSet({ entries: [programEntry(next)], heightLimit: next.budget.maxHeight });
    };
    const onHostMessage = (event: MessageEvent<WeiBeiHostMessage>) => {
      if (event.data?.type === "weibei:setProgram") {
        const result = parseHostProgram(event.data.program);
        if (!result.success) {
          postRuntimeMessage({ type: "weibei:error", message: result.error.issues[0]?.message ?? "界面程序不符合协议。" });
          return;
        }
        setHostEvidenceContent(result.data.evidenceContent ?? []);
        setRenderSet({
          entries: [programEntry(result.data)],
          heightLimit: normalizedHeightLimit(event.data.heightLimit, result.data.budget.maxHeight),
        });
        return;
      }
      if (event.data?.type === "weibei:setPrograms") {
        const result = parseHostPrograms(event.data.programs);
        if (!result.success) {
          postRuntimeMessage({ type: "weibei:error", message: result.error.issues[0]?.message ?? "界面程序组不符合协议。" });
          return;
        }
        setHostEvidenceContent(result.data.flatMap((candidate) => candidate.evidenceContent ?? []));
        const fallbackHeight = Math.min(720, result.data.reduce((sum, candidate) => sum + candidate.budget.maxHeight, 0));
        setRenderSet({
          entries: result.data.map(programEntry),
          heightLimit: normalizedHeightLimit(event.data.heightLimit, fallbackHeight),
        });
        return;
      }
      if (event.data?.type === "weibei:setRenderPlan") {
        const result = parseRenderPlan(event.data.renderPlan ?? event.data.plan);
        if (!result.success) {
          postRuntimeMessage({ type: "weibei:error", message: result.error.issues[0]?.message ?? "渲染计划不符合协议。" });
          return;
        }
        setHostEvidenceContent(event.data.evidenceContent ?? []);
        const entries = compileRenderPlans([result.data], showNotice);
        setRenderSet({
          entries,
          heightLimit: normalizedHeightLimit(event.data.heightLimit, result.data.qualityBudget.maxHeight ?? 360),
        });
        return;
      }
      if (event.data?.type !== "weibei:setRenderPlans") return;
      const result = parseRenderPlans(event.data.renderPlans ?? event.data.plans);
      if (!result.success) {
        postRuntimeMessage({ type: "weibei:error", message: result.error.issues[0]?.message ?? "渲染计划组不符合协议。" });
        return;
      }
      setHostEvidenceContent(event.data.evidenceContent ?? []);
      const entries = compileRenderPlans(result.data, showNotice);
      const fallbackHeight = Math.min(
        1600,
        result.data.reduce((sum, candidate) => sum + (candidate.qualityBudget.maxHeight ?? 360), 0),
      );
      setRenderSet({
        entries,
        heightLimit: normalizedHeightLimit(event.data.heightLimit, fallbackHeight),
      });
    };
    const onEvidence = (event: Event) => {
      const detail = (event as CustomEvent<{ evidenceID: string }>).detail;
      const currentPrograms = renderSetRef.current.entries.map((entry) => entry.program);
      const owner = currentPrograms.find((candidate) =>
        candidate.evidenceBindings.some((binding) => binding.id === detail.evidenceID));
      const primaryProgram = currentPrograms[0];
      if (!owner && !primaryProgram) return;
      const programID = owner?.id ?? primaryProgram?.id;
      if (programID === undefined) return;
      showNotice(`已请求定位材料·${detail.evidenceID}`);
      postRuntimeMessage({
        type: "weibei:evidence",
        programID,
        evidenceID: detail.evidenceID,
      });
    };

    window.addEventListener("popstate", onPopState);
    window.addEventListener("message", onHostMessage);
    window.addEventListener("weibei:evidence", onEvidence);
    postRuntimeMessage({ type: "weibei:ready", protocol: "weibei.renderplan.v1" });

    return () => {
      window.removeEventListener("popstate", onPopState);
      window.removeEventListener("message", onHostMessage);
      window.removeEventListener("weibei:evidence", onEvidence);
    };
  }, []);

  useEffect(() => {
    if (waitingForHost) return;
    const element = pageRef.current;
    if (!element) return;
    const observer = new ResizeObserver(() => {
      const measuredHeight = Math.ceil(element.getBoundingClientRect().height);
      postRuntimeMessage({
        type: "weibei:height",
        height: measuredHeight,
        overflowed: measuredHeight > renderSet.heightLimit,
      });
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [renderSet.heightLimit, waitingForHost]);

  useEffect(() => () => {
    if (noticeTimerRef.current !== null) window.clearTimeout(noticeTimerRef.current);
  }, []);

  const showNotice = useCallback((message: string) => {
    if (noticeTimerRef.current !== null) window.clearTimeout(noticeTimerRef.current);
    setNotice(message);
    noticeTimerRef.current = window.setTimeout(() => setNotice(null), 1800);
  }, []);

  function chooseProgram(next: RichAnswerProgram) {
    updateURL(next);
    setRenderSet({ entries: [programEntry(next)], heightLimit: next.budget.maxHeight });
  }

  return (
    <main ref={pageRef} className={`generation-page${embedded ? " is-embedded" : ""}`}>
      {!embedded && program ? (
        <header className="generation-proofbar">
          <div>
            <span>生成能力压力验证</span>
            <strong>十个样例只验证组件可组合性，不是场景模板</strong>
          </div>
          <nav aria-label="生成界面方案">
            {generatedPrograms.map((candidate, index) => (
              <button
                key={candidate.id}
                type="button"
                className={candidate.id === program?.id ? "is-active" : ""}
                onClick={() => chooseProgram(candidate)}
              >
                <span>{String(index + 1).padStart(2, "0")}</span>
                {candidate.title}
              </button>
            ))}
          </nav>
        </header>
      ) : null}

      {!waitingForHost ? (
        <section
          className={`generation-answer${hasOpenRuntimeEntries ? " is-open-runtime" : ""}`}
          aria-label={renderSet.entries.map((entry) => entry.program.title).join("；")}
        >
          {renderSet.entries.map((entry) => (
            entry.compiled || entry.issue ? (
              <section key={entry.key} className="generation-answer__program" aria-label={entry.program.title}>
                {entry.compiled ? (
                  <RenderPlanRenderer entry={entry} showNotice={showNotice} />
                ) : entry.issue ? (
                  <RenderPlanFallback entry={entry} showNotice={showNotice} />
                ) : null}
              </section>
            ) : (
              <ProgramRenderer
                key={entry.key}
                program={entry.program}
                showNotice={showNotice}
              />
            )
          ))}
        </section>
      ) : null}

      {!embedded && program ? (
        <details className="generation-source">
          <summary>
            <span>查看这次的模型输出</span>
            <small>{program.source.split("\n").length} 条声明·{program.capabilities.length} 种能力·无 SVG path</small>
          </summary>
          <div>
            <aside>
              <strong>程序协议</strong>
              <code>{program.version}</code>
              <strong>能力选择</strong>
              <ul>
                {program.capabilities.map((capability) => <li key={capability}>{capability}</li>)}
              </ul>
            </aside>
            <pre>{program.source}</pre>
          </div>
        </details>
      ) : null}

      {!waitingForHost && notice ? <div className="generation-notice">{notice}</div> : null}
    </main>
  );
}
