import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { Renderer } from "@openuidev/react-lang";
import type { ActionEvent, OpenUIError } from "@openuidev/react-lang";
import { weiBeiGenerativeLibrary } from "./library";
import { generatedPrograms, programForID } from "./programs";
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
  programs: RichAnswerProgram[];
  heightLimit: number;
};

function normalizedHeightLimit(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(160, Math.min(2400, Math.round(value)))
    : fallback;
}

export function GenerativeWorkbench() {
  const [renderSet, setRenderSet] = useState<RenderSet>(() => {
    const program = programFromURL();
    return program
      ? { programs: [program], heightLimit: program.budget.maxHeight }
      : { programs: [], heightLimit: 160 };
  });
  const [notice, setNotice] = useState<string | null>(null);
  const noticeTimerRef = useRef<number | null>(null);
  const pageRef = useRef<HTMLElement>(null);
  const renderSetRef = useRef(renderSet);
  const embedded = isEmbeddedRuntime();
  const waitingForHost = renderSet.programs.length === 0;
  const program = renderSet.programs[0] ?? null;
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
        setRenderSet({ programs: [], heightLimit: 160 });
        return;
      }
      setRenderSet({ programs: [next], heightLimit: next.budget.maxHeight });
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
          programs: [result.data],
          heightLimit: normalizedHeightLimit(event.data.heightLimit, result.data.budget.maxHeight),
        });
        return;
      }
      if (event.data?.type !== "weibei:setPrograms") return;
      const result = parseHostPrograms(event.data.programs);
      if (!result.success) {
        postRuntimeMessage({ type: "weibei:error", message: result.error.issues[0]?.message ?? "界面程序组不符合协议。" });
        return;
      }
      setHostEvidenceContent(result.data.flatMap((candidate) => candidate.evidenceContent ?? []));
      const fallbackHeight = Math.min(720, result.data.reduce((sum, candidate) => sum + candidate.budget.maxHeight, 0));
      setRenderSet({
        programs: result.data,
        heightLimit: normalizedHeightLimit(event.data.heightLimit, fallbackHeight),
      });
    };
    const onEvidence = (event: Event) => {
      const detail = (event as CustomEvent<{ evidenceID: string }>).detail;
      const currentPrograms = renderSetRef.current.programs;
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
    postRuntimeMessage({ type: "weibei:ready", protocol: "weibei.openui.v1" });

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

  function showNotice(message: string) {
    if (noticeTimerRef.current !== null) window.clearTimeout(noticeTimerRef.current);
    setNotice(message);
    noticeTimerRef.current = window.setTimeout(() => setNotice(null), 1800);
  }

  function chooseProgram(next: RichAnswerProgram) {
    updateURL(next);
    setRenderSet({ programs: [next], heightLimit: next.budget.maxHeight });
  }

  return (
    <main ref={pageRef} className={`generation-page${embedded ? " is-embedded" : ""}`}>
      {!embedded ? (
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
        <section className="generation-answer" aria-label={renderSet.programs.map((candidate) => candidate.title).join("；")}>
          {renderSet.programs.map((candidate) => (
            <ProgramRenderer
              key={`${candidate.id}:${candidate.source}`}
              program={candidate}
              showNotice={showNotice}
            />
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
