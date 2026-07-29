import {
  Component,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ErrorInfo,
  type ReactNode,
} from "react";
import { Renderer } from "@openuidev/react-lang";
import type { ActionEvent, OpenUIError } from "@openuidev/react-lang";
import { weiBeiGenerativeLibrary } from "./library";
import { generatedPrograms, programForID } from "./programs";
import {
  RendererRegistry,
  formalRenderGroupResourceLimits,
  measureRenderPlanResourceUsage,
  parseRenderPlan,
  parseRenderPlans,
  type CompiledRenderPlan,
  type RenderPlan,
  type RendererIssue,
  type RendererLifecycleContext,
} from "./renderer-registry";
import {
  admitRenderGroupItems,
  mergeIndexedRenderGroupItems,
  runtimeFailureIsFatal,
} from "./render-group";
import { standardEChartsRenderer } from "./renderers/echarts-chart";
import { geometry2DRenderer } from "./renderers/geometry-2d";
import { imageOverlayRenderer } from "./renderers/image-overlay";
import { mathFunctionRenderer } from "./renderers/math-function";
import { scene3DRenderer } from "./renderers/scene-3d";
import { spatialMapRenderer } from "./renderers/spatial-map";
import {
  parseHostProgram,
  parseHostPrograms,
  isEmbeddedRuntime,
  postRuntimeMessage,
  setHostEvidenceContent,
  type RenderPlanBudgetContext,
  type RichAnswerProgram,
  type WeiBeiHostMessage,
} from "./protocol";
import "./workbench.css";

const renderRegistry = new RendererRegistry()
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
      fatal: runtimeFailureIsFatal("program-entry"),
    });
  }, [errors, program.id]);

  useEffect(() => {
    if (!guardError) return;
    postRuntimeMessage({
      type: "weibei:error",
      programID: program.id,
      message: guardError,
      fatal: runtimeFailureIsFatal("program-entry"),
    });
  }, [guardError, program.id]);

  function handleStateUpdate(state: Record<string, unknown>) {
    setRuntimeState(state);
    postRuntimeMessage({ type: "weibei:state", programID: program.id, state });
  }

  function handleAction(action: ActionEvent) {
    showNotice(`已交给 Agent·${action.humanFriendlyMessage}`);
    postRuntimeMessage({ type: "weibei:action", programID: program.id, action });
  }

  const failure = guardError ?? errors.map((error) => error.message).join("；");
  if (failure) {
    return (
      <div className="generation-fallback" role="status" data-weibei-renderer-issue="validation_error">
        <strong>这项富回答无法显示</strong>
        <span>请继续阅读正文。</span>
      </div>
    );
  }

  return (
    <section className="generation-answer__program" aria-label={program.title}>
      <div className="generation-answer__status">
        <span>{parseReady && !errors.length && !guardError ? "程序已通过验证" : "正在校验界面程序"}</span>
        <i>{program.budget.graphics === "canvas" ? "Canvas 图形内核" : "HTML 交互内核"}</i>
      </div>
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
  fallbackReason?: string;
  fallbackText?: string;
  budgetContext?: RenderPlanBudgetContext;
  index: number;
};

function programEntry(program: RichAnswerProgram, index = 0): RenderEntry {
  return { key: `program:${index}:${program.id}:${program.source}`, program, index };
}

function itemFailureEntry(
  index: number,
  fallbackReason = "这项视觉暂不可用",
  fallbackText = "请继续阅读正文。",
  programID = `rich-item-${index + 1}`,
  title = `富回答第 ${index + 1} 项`,
): RenderEntry {
  return {
    key: `failure:${index}:${programID}:${fallbackReason}:${fallbackText}`,
    index,
    program: {
      version: "weibei.openui.v1",
      id: programID,
      title,
      question: title,
      mode: "declarative",
      source: "",
      initialState: {},
      capabilities: ["failure-isolation"],
      evidenceBindings: [],
      budget: {
        maxHeight: 160,
        maxNodes: 1,
        maxSeries: 1,
        graphics: "dom",
      },
    },
    fallbackReason,
    fallbackText,
  };
}

function hostItemFailureEntries(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, 6).flatMap((candidate, fallbackIndex) => {
    if (!candidate || typeof candidate !== "object") return [];
    const failure = candidate as Record<string, unknown>;
    const fallbackReason = typeof failure.fallbackReason === "string"
      ? failure.fallbackReason.trim()
      : "";
    const fallbackText = typeof failure.fallbackText === "string"
      ? failure.fallbackText.trim()
      : "";
    if (!fallbackReason || !fallbackText) return [];
    const index = typeof failure.index === "number" && Number.isSafeInteger(failure.index) && failure.index >= 0
      ? failure.index
      : fallbackIndex;
    const programID = typeof failure.programID === "string" && failure.programID.trim()
      ? failure.programID.trim()
      : `rich-item-${index + 1}`;
    const title = typeof failure.title === "string" && failure.title.trim()
      ? failure.title.trim()
      : `富回答第 ${index + 1} 项`;
    return [itemFailureEntry(index, fallbackReason, fallbackText, programID, title)];
  });
}

function mergeRenderEntries(...collections: RenderEntry[][]) {
  return mergeIndexedRenderGroupItems(
    ...collections.map((entries) =>
      entries.map((entry) => ({ index: entry.index, value: entry }))),
  );
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

function lifecycleContext(
  program: RichAnswerProgram,
  showNotice: (message: string) => void,
  budgetContext?: RenderPlanBudgetContext,
): RendererLifecycleContext {
  return {
    program,
    budgetContext,
    showNotice,
    postMessage: postRuntimeMessage,
  };
}

function compileRenderPlans(
  plans: RenderPlan[],
  showNotice: (message: string) => void,
  budgetContexts: Array<RenderPlanBudgetContext | undefined> = [],
  sourceIndices: number[] = plans.map((_, index) => index),
): RenderEntry[] {
  const entries: RenderEntry[] = [];
  const diagnostics: Array<{ programID: string; message: string }> = [];
  const candidates = plans.slice(0, 6).map((plan, planIndex) => {
    const index = sourceIndices[planIndex] ?? planIndex;
    const program = programForRenderPlan(plan, index);
    const budgetContext = budgetContexts[planIndex];
    const measured = measureRenderPlanResourceUsage(plan, budgetContext);
    if (!measured.ok) {
      diagnostics.push({ programID: program.id, message: measured.issue.message });
      entries.push({
        key: `plan:${index}:${plan.renderer}:${plan.specVersion}:fallback:${measured.issue.code}`,
        index,
        program,
        plan,
        issue: measured.issue,
        budgetContext,
      });
      return null;
    }
    return {
      index,
      value: { plan, program, budgetContext },
      usage: measured.usage,
    };
  }).filter((candidate): candidate is NonNullable<typeof candidate> => candidate !== null);
  const admission = admitRenderGroupItems(candidates, formalRenderGroupResourceLimits);
  admission.rejected.forEach(({ index, value, reason }) => {
    const issue = {
      code: "capability_mismatch" as const,
      renderer: value.plan.renderer,
      message: `富回答组资源边界拒绝第 ${index + 1} 项：${reason}。`,
    };
    diagnostics.push({ programID: value.program.id, message: issue.message });
    entries.push({
      key: `plan:${index}:${value.plan.renderer}:${value.plan.specVersion}:fallback:group-${reason}`,
      index,
      program: value.program,
      plan: value.plan,
      issue,
      budgetContext: value.budgetContext,
    });
  });
  admission.accepted.forEach(({ index, value }) => {
    const { plan, program, budgetContext } = value;
    const context = lifecycleContext(program, showNotice, budgetContext);
    try {
      const compiled = renderRegistry.compile(plan, context);
      if (!compiled.ok) {
        diagnostics.push({ programID: program.id, message: compiled.issue.message });
        entries.push({
          key: `plan:${index}:${plan.renderer}:${plan.specVersion}:fallback:${compiled.issue.message}`,
          index,
          program,
          plan,
          issue: compiled.issue,
          budgetContext,
        });
        return;
      }

      entries.push({
        key: `plan:${index}:${plan.renderer}:${plan.specVersion}:${JSON.stringify(plan.spec)}`,
        index,
        program,
        plan,
        compiled: compiled.compiled,
        budgetContext,
      });
    } catch (error) {
      const issue = {
        code: "compile_error" as const,
        renderer: plan.renderer,
        message: error instanceof Error ? error.message : "渲染计划编译失败。",
      };
      diagnostics.push({
        programID: program.id,
        message: issue.message,
      });
      entries.push({
        key: `plan:${index}:${plan.renderer}:${plan.specVersion}:fallback:${issue.message}`,
        index,
        program,
        plan,
        issue,
        budgetContext,
      });
    }
  });
  diagnostics.forEach((diagnostic) => {
    postRuntimeMessage({
      type: "weibei:error",
      ...diagnostic,
      fatal: runtimeFailureIsFatal("renderer-entry"),
    });
  });
  return entries.sort((left, right) => left.index - right.index);
}

function RenderPlanRenderer({
  entry,
  showNotice,
}: {
  entry: RenderEntry;
  showNotice: (message: string) => void;
}) {
  const previousRef = useRef<CompiledRenderPlan | null>(null);
  const context = useMemo(
    () => lifecycleContext(entry.program, showNotice, entry.budgetContext),
    [entry.budgetContext, entry.program, showNotice],
  );
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
  const context = useMemo(
    () => lifecycleContext(entry.program, showNotice, entry.budgetContext),
    [entry.budgetContext, entry.program, showNotice],
  );
  if (!entry.plan || !entry.issue) return null;
  return <>{renderRegistry.fallback(entry.plan, entry.issue, context)}</>;
}

class RichEntryErrorBoundary extends Component<
  { children: ReactNode; programID: string },
  { message: string | null }
> {
  state = { message: null as string | null };

  static getDerivedStateFromError(error: unknown) {
    return { message: error instanceof Error ? error.message : "富回答渲染失败。" };
  }

  componentDidCatch(error: unknown, _info: ErrorInfo) {
    postRuntimeMessage({
      type: "weibei:error",
      programID: this.props.programID,
      message: error instanceof Error ? error.message : "富回答渲染失败。",
      fatal: runtimeFailureIsFatal("entry-error-boundary"),
    });
  }

  render() {
    if (!this.state.message) return this.props.children;
    return (
      <div className="generation-fallback" role="status" data-weibei-renderer-issue="compile_error">
        <strong>这项富回答无法显示</strong>
        <span>请继续阅读正文。</span>
      </div>
    );
  }
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
  const hasOpenRuntimeEntries = renderSet.entries.some((entry) =>
    entry.compiled || entry.issue || entry.fallbackReason);
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
          setHostEvidenceContent([]);
          setRenderSet({ entries: [itemFailureEntry(0)], heightLimit: 160 });
          postRuntimeMessage({
            type: "weibei:error",
            message: result.error.issues[0]?.message ?? "界面程序不符合协议。",
            fatal: runtimeFailureIsFatal("program-entry"),
          });
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
          setHostEvidenceContent([]);
          const parseIssues = "issues" in result
            ? result.issues
            : result.error.issues.map((issue, index) => ({ index, message: issue.message }));
          const failures = parseIssues.map((issue) => itemFailureEntry(issue.index));
          setRenderSet({ entries: failures, heightLimit: 160 });
          postRuntimeMessage({
            type: "weibei:error",
            message: result.error.issues[0]?.message ?? "界面程序组不符合协议。",
            fatal: runtimeFailureIsFatal("program-entry"),
          });
          return;
        }
        result.issues.forEach((issue) => {
          postRuntimeMessage({
            type: "weibei:error",
            programID: `program-${issue.index + 1}`,
            message: issue.message,
            fatal: runtimeFailureIsFatal("program-entry"),
          });
        });
        setHostEvidenceContent(result.data.flatMap((candidate) => candidate.evidenceContent ?? []));
        const fallbackHeight = Math.min(720, result.data.reduce((sum, candidate) => sum + candidate.budget.maxHeight, 0));
        setRenderSet({
          entries: mergeRenderEntries(
            result.data.map((candidate, index) => programEntry(candidate, result.indices[index])),
            result.issues.map((issue) => itemFailureEntry(issue.index)),
          ),
          heightLimit: normalizedHeightLimit(event.data.heightLimit, fallbackHeight),
        });
        return;
      }
      if (event.data?.type === "weibei:setRenderFailures") {
        const failures = hostItemFailureEntries(event.data.itemFailures);
        setHostEvidenceContent([]);
        setRenderSet({
          entries: failures,
          heightLimit: normalizedHeightLimit(event.data.heightLimit, Math.max(160, failures.length * 160)),
        });
        return;
      }
      if (event.data?.type === "weibei:setRenderPlan") {
        const result = parseRenderPlan(event.data.renderPlan ?? event.data.plan);
        if (!result.success) {
          setHostEvidenceContent([]);
          const failures = hostItemFailureEntries(event.data.itemFailures);
          setRenderSet({
            entries: failures.length ? failures : [itemFailureEntry(event.data.sourceIndex ?? 0)],
            heightLimit: 160,
          });
          postRuntimeMessage({
            type: "weibei:error",
            message: result.error.issues[0]?.message ?? "渲染计划不符合协议。",
            fatal: runtimeFailureIsFatal("renderer-entry"),
          });
          return;
        }
        setHostEvidenceContent(event.data.evidenceContent ?? []);
        const sourceIndex = event.data.sourceIndex ?? 0;
        const entries = compileRenderPlans(
          [result.data],
          showNotice,
          [event.data.budgetContext],
          [sourceIndex],
        );
        setRenderSet({
          entries: mergeRenderEntries(entries, hostItemFailureEntries(event.data.itemFailures)),
          heightLimit: normalizedHeightLimit(event.data.heightLimit, result.data.qualityBudget.maxHeight ?? 360),
        });
        return;
      }
      if (event.data?.type !== "weibei:setRenderPlans") return;
      const result = parseRenderPlans(event.data.renderPlans ?? event.data.plans);
      if (!result.success) {
        setHostEvidenceContent([]);
        const sourceIndices = event.data.sourceIndices ?? [];
        const parseIssues = "issues" in result
          ? result.issues
          : result.error.issues.map((issue, index) => ({ index, message: issue.message }));
        const parserFailures = parseIssues.map((issue) =>
          itemFailureEntry(sourceIndices[issue.index] ?? issue.index));
        const entries = mergeRenderEntries(
          parserFailures,
          hostItemFailureEntries(event.data.itemFailures),
        );
        setRenderSet({ entries, heightLimit: Math.max(160, entries.length * 160) });
        postRuntimeMessage({
          type: "weibei:error",
          message: result.error.issues[0]?.message ?? "渲染计划组不符合协议。",
          fatal: runtimeFailureIsFatal("renderer-entry"),
        });
        return;
      }
      const sourceIndices = event.data.sourceIndices ?? [];
      result.issues.forEach((issue) => {
        postRuntimeMessage({
          type: "weibei:error",
          programID: `render-plan-${(sourceIndices[issue.index] ?? issue.index) + 1}`,
          message: issue.message,
          fatal: runtimeFailureIsFatal("renderer-entry"),
        });
      });
      setHostEvidenceContent(event.data.evidenceContent ?? []);
      const budgetContexts = event.data.budgetContexts;
      const entries = compileRenderPlans(
        result.data,
        showNotice,
        result.indices.map((index) => budgetContexts?.[index]),
        result.indices.map((index) => sourceIndices[index] ?? index),
      );
      const fallbackHeight = Math.min(
        1600,
        result.data.reduce((sum, candidate) => sum + (candidate.qualityBudget.maxHeight ?? 360), 0),
      );
      setRenderSet({
        entries: mergeRenderEntries(
          entries,
          result.issues.map((issue) =>
            itemFailureEntry(sourceIndices[issue.index] ?? issue.index)),
          hostItemFailureEntries(event.data.itemFailures),
        ),
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
      showNotice(`已请求定位材料·${detail.evidenceID}`);
      postRuntimeMessage({
        type: "weibei:evidence",
        programID: owner?.id ?? primaryProgram.id,
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
          {renderSet.entries.map((entry) => {
            const content = entry.fallbackReason && entry.fallbackText ? (
              <section className="generation-answer__program" aria-label={entry.program.title}>
                <div className="generation-fallback" role="status" data-weibei-renderer-issue="validation_error">
                  <strong>{entry.fallbackReason}</strong>
                  <span>{entry.fallbackText}</span>
                </div>
              </section>
            ) : entry.compiled ? (
              <section className="generation-answer__program" aria-label={entry.program.title}>
                <RenderPlanRenderer entry={entry} showNotice={showNotice} />
              </section>
            ) : entry.issue ? (
              <section className="generation-answer__program" aria-label={entry.program.title}>
                <RenderPlanFallback entry={entry} showNotice={showNotice} />
              </section>
            ) : (
              <ProgramRenderer
                program={entry.program}
                showNotice={showNotice}
              />
            );
            return (
              <RichEntryErrorBoundary
                key={entry.key}
                programID={entry.program.id}
              >
                {content}
              </RichEntryErrorBoundary>
            );
          })}
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
