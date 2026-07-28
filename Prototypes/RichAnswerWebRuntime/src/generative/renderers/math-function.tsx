import { useEffect, useMemo, useRef, useState } from "react";
import * as echarts from "echarts";
import type { ECharts, EChartsOption } from "echarts";
import { z } from "zod/v4";
import {
  createRendererIssue,
  type CompiledRenderPlan,
  type RenderPlan,
  type RendererLifecycleContext,
  type RichAnswerRenderer,
} from "../renderer-registry";

const FUNCTION_RENDERER = "weibei.math.function";
const FUNCTION_SPEC_VERSION = "weibei.math-function.v1";
const maxExpressionNodes = 64;
const maxParameters = 4;
const maxGeneratedPoints = 1600;
const unaryOperations = new Set(["abs", "cos", "exp", "log", "negate", "sin", "sqrt", "tan"]);
const binaryOperations = new Set(["add", "divide", "multiply", "power", "subtract"]);

const finiteNumber = z.number().refine(Number.isFinite, "必须是有限数");
const identifier = z.string().min(1).max(256);
const operation = z.enum([
  "abs",
  "add",
  "cos",
  "divide",
  "exp",
  "log",
  "multiply",
  "negate",
  "power",
  "sin",
  "sqrt",
  "subtract",
  "tan",
]);
const expressionNodeSchema = z.discriminatedUnion("kind", [
  z.object({ id: identifier, kind: z.literal("constant"), value: finiteNumber }).strict(),
  z.object({ id: identifier, kind: z.literal("variable") }).strict(),
  z.object({ id: identifier, kind: z.literal("parameter"), parameterID: identifier }).strict(),
  z.object({
    id: identifier,
    kind: z.literal("operation"),
    operation,
    inputIDs: z.array(identifier).min(1).max(2),
  }).strict(),
]);
const parameterSchema = z.object({
  id: identifier,
  label: z.string().min(1).max(80),
  value: finiteNumber,
  minimum: finiteNumber,
  maximum: finiteNumber,
  step: finiteNumber.refine((value) => value > 0, "step 必须大于 0"),
  unit: z.string().min(1).max(24).optional(),
}).strict();
const functionSpecSchema = z.object({
  title: z.string().min(1).max(120),
  variable: z.string().min(1).max(12),
  domain: z.object({ minimum: finiteNumber, maximum: finiteNumber }).strict(),
  parameters: z.array(parameterSchema).max(maxParameters).optional(),
  expression: z.object({
    rootNodeID: identifier,
    nodes: z.array(expressionNodeSchema).min(1).max(maxExpressionNodes),
  }).strict(),
  xAxisLabel: z.string().min(1).max(80).optional(),
  yAxisLabel: z.string().min(1).max(80).optional(),
  caption: z.string().min(1).max(220).optional(),
  probeEnabled: z.boolean().optional(),
}).strict();

type FunctionSpec = z.infer<typeof functionSpecSchema>;
type ExpressionNode = z.infer<typeof expressionNodeSchema>;
type ParameterValues = Record<string, number>;
type FunctionPoint = [number, number];
type FunctionFocus = { x: number; y: number };
type FunctionCompiledRenderPlan = CompiledRenderPlan & {
  spec: FunctionSpec;
  nodeByID: Map<string, ExpressionNode>;
};

function parseFunctionSpec(plan: RenderPlan) {
  const parsed = functionSpecSchema.safeParse(plan.spec);
  if (!parsed.success) {
    return {
      ok: false as const,
      issue: createRendererIssue(
        "validation_error",
        plan.renderer,
        parsed.error.issues[0]?.message ?? "函数规格不符合协议。",
        parsed.error.issues.map((item) => item.path.join(".")).filter(Boolean),
      ),
    };
  }
  const semanticIssue = guardFunctionPlan(plan, parsed.data);
  if (semanticIssue) return { ok: false as const, issue: semanticIssue };
  return { ok: true as const, spec: parsed.data, nodeByID: indexExpression(parsed.data) };
}

function guardFunctionPlan(plan: RenderPlan, spec: FunctionSpec) {
  if (plan.renderer !== FUNCTION_RENDERER) {
    return createRendererIssue("capability_mismatch", plan.renderer, `函数渲染器不能渲染 ${plan.renderer}。`);
  }
  if (plan.specVersion !== FUNCTION_SPEC_VERSION) {
    return createRendererIssue("capability_mismatch", plan.renderer, `函数渲染器只支持 ${FUNCTION_SPEC_VERSION}。`);
  }
  if (plan.qualityBudget.allowNetwork || plan.qualityBudget.allowWebGL) {
    return createRendererIssue("capability_mismatch", plan.renderer, "函数渲染器只使用本地 Canvas，不请求网络或 WebGL。");
  }
  if (spec.domain.minimum >= spec.domain.maximum) {
    return createRendererIssue("validation_error", plan.renderer, "函数定义域必须满足 minimum < maximum。");
  }
  const parameterIDs = new Set<string>();
  for (const parameter of spec.parameters ?? []) {
    if (parameterIDs.has(parameter.id)) {
      return createRendererIssue("validation_error", plan.renderer, `函数参数 id 重复：${parameter.id}。`);
    }
    parameterIDs.add(parameter.id);
    if (
      parameter.minimum >= parameter.maximum ||
      parameter.value < parameter.minimum ||
      parameter.value > parameter.maximum
    ) {
      return createRendererIssue("validation_error", plan.renderer, `函数参数 ${parameter.id} 的范围或初值无效。`);
    }
  }

  const nodeByID = new Map<string, ExpressionNode>();
  for (const node of spec.expression.nodes) {
    if (nodeByID.has(node.id)) {
      return createRendererIssue("validation_error", plan.renderer, `表达式节点 id 重复：${node.id}。`);
    }
    nodeByID.set(node.id, node);
  }
  if (!nodeByID.has(spec.expression.rootNodeID)) {
    return createRendererIssue("validation_error", plan.renderer, "expression.rootNodeID 必须引用存在节点。");
  }
  for (const node of nodeByID.values()) {
    if (node.kind === "parameter" && !parameterIDs.has(node.parameterID)) {
      return createRendererIssue("validation_error", plan.renderer, `表达式引用了不存在的参数 ${node.parameterID}。`);
    }
    if (node.kind !== "operation") continue;
    const expectedInputs = unaryOperations.has(node.operation) ? 1 : binaryOperations.has(node.operation) ? 2 : 0;
    if (node.inputIDs.length !== expectedInputs) {
      return createRendererIssue("validation_error", plan.renderer, `${node.operation} 需要 ${expectedInputs} 个输入。`);
    }
    const missing = node.inputIDs.filter((inputID) => !nodeByID.has(inputID));
    if (missing.length) {
      return createRendererIssue("validation_error", plan.renderer, `表达式引用了不存在的节点：${missing.join("、")}。`);
    }
  }

  const visiting = new Set<string>();
  const visited = new Set<string>();
  const visit = (nodeID: string, depth: number): string | null => {
    if (depth > 24) return "表达式图深度超过 24。";
    if (visiting.has(nodeID)) return `表达式图存在循环：${nodeID}。`;
    if (visited.has(nodeID)) return null;
    const node = nodeByID.get(nodeID);
    if (!node) return null;
    visiting.add(nodeID);
    if (node.kind === "operation") {
      for (const inputID of node.inputIDs) {
        const issue = visit(inputID, depth + 1);
        if (issue) return issue;
      }
    }
    visiting.delete(nodeID);
    visited.add(nodeID);
    return null;
  };
  const graphIssue = visit(spec.expression.rootNodeID, 0);
  return graphIssue ? createRendererIssue("validation_error", plan.renderer, graphIssue) : null;
}

function indexExpression(spec: FunctionSpec) {
  return new Map(spec.expression.nodes.map((node) => [node.id, node]));
}

function initialParameterValues(spec: FunctionSpec): ParameterValues {
  return Object.fromEntries((spec.parameters ?? []).map((parameter) => [parameter.id, parameter.value]));
}

function evaluateFunction(
  compiled: FunctionCompiledRenderPlan,
  x: number,
  parameters: ParameterValues,
) {
  const cache = new Map<string, number>();
  const evaluateNode = (nodeID: string, depth: number): number => {
    if (depth > 24) return Number.NaN;
    const cached = cache.get(nodeID);
    if (cached !== undefined) return cached;
    const node = compiled.nodeByID.get(nodeID);
    if (!node) return Number.NaN;
    let value: number;
    if (node.kind === "constant") value = node.value;
    else if (node.kind === "variable") value = x;
    else if (node.kind === "parameter") value = parameters[node.parameterID] ?? Number.NaN;
    else {
      const inputs = node.inputIDs.map((inputID) => evaluateNode(inputID, depth + 1));
      value = applyOperation(node.operation, inputs);
    }
    const safeValue = Number.isFinite(value) ? value : Number.NaN;
    cache.set(nodeID, safeValue);
    return safeValue;
  };
  return evaluateNode(compiled.spec.expression.rootNodeID, 0);
}

function applyOperation(name: z.infer<typeof operation>, inputs: number[]) {
  const first = inputs[0] ?? Number.NaN;
  const second = inputs[1] ?? Number.NaN;
  if (inputs.some((value) => !Number.isFinite(value))) return Number.NaN;
  switch (name) {
    case "abs": return Math.abs(first);
    case "add": return first + second;
    case "cos": return Math.cos(first);
    case "divide": return Math.abs(second) <= 1e-12 * Math.max(1, Math.abs(first)) ? Number.NaN : first / second;
    case "exp": return Math.exp(first);
    case "log": return first > 0 ? Math.log(first) : Number.NaN;
    case "multiply": return first * second;
    case "negate": return -first;
    case "power": return Math.pow(first, second);
    case "sin": return Math.sin(first);
    case "sqrt": return first >= 0 ? Math.sqrt(first) : Number.NaN;
    case "subtract": return first - second;
    case "tan": return Math.abs(Math.cos(first)) < 1e-9 ? Number.NaN : Math.tan(first);
  }
}

function adaptivePoints(
  compiled: FunctionCompiledRenderPlan,
  parameters: ParameterValues,
  pointBudget: number,
) {
  const { minimum, maximum } = compiled.spec.domain;
  const initialIntervals = 48;
  const minimumWidth = (maximum - minimum) / 2048;
  const points = new Map<number, number>();
  const sample = (x: number) => {
    const existing = points.get(x);
    if (existing !== undefined) return existing;
    const value = evaluateFunction(compiled, x, parameters);
    points.set(x, value);
    return value;
  };
  const refine = (leftX: number, rightX: number, leftY: number, rightY: number, depth: number) => {
    if (depth >= 8 || rightX - leftX <= minimumWidth || points.size >= pointBudget) return;
    const middleX = (leftX + rightX) / 2;
    const middleY = sample(middleX);
    const finite = [leftY, middleY, rightY].map(Number.isFinite);
    const scale = Math.max(1, Math.abs(leftY), Math.abs(middleY), Math.abs(rightY));
    const curvature = finite.every(Boolean)
      ? Math.abs(middleY - (leftY + rightY) / 2) / scale
      : Number.POSITIVE_INFINITY;
    const signSpike = finite.every(Boolean) && Math.sign(leftY) !== Math.sign(rightY) &&
      Math.max(Math.abs(leftY), Math.abs(rightY)) > 12 * Math.max(1, Math.abs(middleY));
    if (curvature < 0.004 && !signSpike) return;
    refine(leftX, middleX, leftY, middleY, depth + 1);
    refine(middleX, rightX, middleY, rightY, depth + 1);
  };

  let leftX = minimum;
  let leftY = sample(leftX);
  for (let index = 1; index <= initialIntervals; index += 1) {
    const rightX = minimum + ((maximum - minimum) * index) / initialIntervals;
    const rightY = sample(rightX);
    refine(leftX, rightX, leftY, rightY, 0);
    leftX = rightX;
    leftY = rightY;
  }
  return [...points.entries()].sort((left, right) => left[0] - right[0]);
}

function quantile(values: number[], ratio: number) {
  if (!values.length) return 0;
  const position = (values.length - 1) * ratio;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  const weight = position - lower;
  return values[lower]! * (1 - weight) + values[upper]! * weight;
}

function splitSegments(points: Array<[number, number]>) {
  const finiteValues = points.map(([, value]) => value).filter(Number.isFinite).sort((left, right) => left - right);
  if (!finiteValues.length) return [] as FunctionPoint[][];
  const low = quantile(finiteValues, 0.1);
  const high = quantile(finiteValues, 0.9);
  const robustSpan = Math.max(1, high - low);
  const lowerBound = low - robustSpan * 12;
  const upperBound = high + robustSpan * 12;
  const jumpLimit = robustSpan * 8;
  const segments: FunctionPoint[][] = [];
  let current: FunctionPoint[] = [];
  let previousY: number | null = null;
  const flush = () => {
    if (current.length >= 2) segments.push(current);
    current = [];
    previousY = null;
  };
  for (const [x, y] of points) {
    if (!Number.isFinite(y) || y < lowerBound || y > upperBound || (previousY !== null && Math.abs(y - previousY) > jumpLimit)) {
      flush();
      continue;
    }
    current.push([x, y]);
    previousY = y;
  }
  flush();
  return segments;
}

function formatNumber(value: number) {
  if (Math.abs(value) >= 1000 || (Math.abs(value) > 0 && Math.abs(value) < 0.001)) {
    return value.toExponential(2);
  }
  return Number.isInteger(value) ? String(value) : value.toFixed(3).replace(/\.?0+$/, "");
}

function functionOption(
  compiled: FunctionCompiledRenderPlan,
  segments: FunctionPoint[][],
  narrow: boolean,
): EChartsOption {
  return {
    animation: compiled.plan.qualityBudget.allowAnimation,
    backgroundColor: "transparent",
    tooltip: {
      trigger: "axis",
      confine: true,
      formatter: (params: unknown) => {
        const items = Array.isArray(params) ? params : [params];
        const item = items.find((candidate) => {
          const value = (candidate as { value?: unknown })?.value;
          return Array.isArray(value) && value.length >= 2;
        }) as { value?: [number, number] } | undefined;
        return item?.value ? `${compiled.spec.variable} = ${formatNumber(item.value[0])}<br/>y = ${formatNumber(item.value[1])}` : "";
      },
    },
    grid: {
      top: narrow ? 18 : 20,
      left: narrow ? 46 : 58,
      right: narrow ? 12 : 18,
      bottom: narrow ? 50 : 42,
      containLabel: true,
    },
    xAxis: {
      type: "value",
      name: compiled.spec.xAxisLabel ?? compiled.spec.variable,
      nameLocation: "middle",
      nameGap: narrow ? 34 : 30,
      min: compiled.spec.domain.minimum,
      max: compiled.spec.domain.maximum,
      axisLine: { onZero: true, lineStyle: { color: "#9b9185" } },
      axisLabel: { color: "#6f665b", fontSize: narrow ? 10 : 11, hideOverlap: true },
      splitLine: { lineStyle: { color: "rgba(70, 58, 43, 0.1)" } },
    },
    yAxis: {
      type: "value",
      name: compiled.spec.yAxisLabel ?? "y",
      nameLocation: "middle",
      nameRotate: 90,
      nameGap: narrow ? 34 : 40,
      nameTextStyle: { color: "#6f665b", fontSize: narrow ? 10 : 11, align: "center" },
      axisLine: { onZero: true, lineStyle: { color: "#9b9185" } },
      axisLabel: { color: "#6f665b", fontSize: narrow ? 10 : 11, hideOverlap: true },
      splitLine: { lineStyle: { color: "rgba(70, 58, 43, 0.1)" } },
    },
    series: segments.map((segment, index) => ({
      name: index === 0 ? compiled.spec.title : `${compiled.spec.title}-${index + 1}`,
      type: "line",
      data: segment,
      showSymbol: false,
      symbolSize: 7,
      smooth: false,
      connectNulls: false,
      silent: !compiled.spec.probeEnabled,
      lineStyle: { width: 2, color: "#914737" },
      itemStyle: { color: "#914737" },
      emphasis: { focus: "series" },
    })),
  };
}

function FunctionMount({
  compiled,
  context,
}: {
  compiled: FunctionCompiledRenderPlan;
  context: RendererLifecycleContext;
}) {
  const elementRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<ECharts | null>(null);
  const [width, setWidth] = useState(560);
  const [parameters, setParameters] = useState<ParameterValues>(() => initialParameterValues(compiled.spec));
  const [focus, setFocus] = useState<FunctionFocus | null>(null);
  const parametersRef = useRef(parameters);
  const segmentsRef = useRef<FunctionPoint[][]>([]);
  const compiledKey = useMemo(() => JSON.stringify(compiled.spec), [compiled.spec]);
  const pointBudget = Math.max(120, Math.min(maxGeneratedPoints, compiled.plan.qualityBudget.maxDataPoints ?? 800));
  const points = useMemo(
    () => adaptivePoints(compiled, parameters, pointBudget),
    [compiled, parameters, pointBudget],
  );
  const segments = useMemo(() => splitSegments(points), [points]);
  parametersRef.current = parameters;
  segmentsRef.current = segments;

  useEffect(() => {
    setParameters(initialParameterValues(compiled.spec));
    setFocus(null);
  }, [compiledKey, compiled.spec]);

  useEffect(() => {
    const element = elementRef.current;
    if (!element) return;
    const chart = echarts.init(element, undefined, {
      renderer: "canvas",
      devicePixelRatio: Math.min(2, Math.max(1, window.devicePixelRatio || 1)),
    });
    chartRef.current = chart;
    const resize = () => {
      setWidth(Math.max(1, Math.round(element.getBoundingClientRect().width)));
      chart.resize();
    };
    const focusFromChart = (params: unknown) => {
      if (!compiled.spec.probeEnabled) return;
      const value = (params as { value?: unknown }).value;
      if (!Array.isArray(value) || value.length < 2) return;
      const [x, y] = value;
      if (typeof x === "number" && typeof y === "number" && Number.isFinite(x) && Number.isFinite(y)) {
        setFocus({ x, y });
      }
    };
    const verifyInteraction = () => {
      const firstParameter = compiled.spec.parameters?.[0];
      if (firstParameter) {
        const current = parametersRef.current[firstParameter.id] ?? firstParameter.value;
        const next = current + firstParameter.step <= firstParameter.maximum
          ? current + firstParameter.step
          : firstParameter.minimum;
        setParameters((values) => ({ ...values, [firstParameter.id]: next }));
        return;
      }
      const currentSegments = segmentsRef.current;
      const segment = currentSegments[Math.floor(currentSegments.length / 2)] ?? currentSegments[0];
      const point = segment?.[Math.floor(segment.length / 2)];
      if (point) setFocus({ x: point[0], y: point[1] });
    };
    chart.on("click", focusFromChart);
    element.addEventListener("weibei:verify-interaction", verifyInteraction);
    const observer = new ResizeObserver(resize);
    observer.observe(element);
    resize();
    return () => {
      observer.disconnect();
      chart.off("click", focusFromChart);
      element.removeEventListener("weibei:verify-interaction", verifyInteraction);
      chart.dispose();
      chartRef.current = null;
    };
  }, [compiled, compiledKey]);

  useEffect(() => {
    chartRef.current?.setOption(functionOption(compiled, segments, width < 520), { notMerge: true });
    chartRef.current?.resize();
  }, [compiled, segments, width]);

  useEffect(() => {
    context.postMessage({
      type: "weibei:state",
      programID: compiled.programID,
      state: { renderer: FUNCTION_RENDERER, parameters, focus },
    });
  }, [compiled.programID, context, focus, parameters]);

  const surfaceHeight = Math.max(230, Math.min(500, compiled.plan.qualityBudget.maxHeight ?? 360));
  return (
    <figure className="weibei-function" data-weibei-renderer={FUNCTION_RENDERER}>
      <figcaption className="weibei-function__title">{compiled.spec.title}</figcaption>
      <div
        ref={elementRef}
        className="weibei-function__surface"
        data-weibei-control="function-probe"
        data-weibei-control-id={compiled.programID}
        data-weibei-state={JSON.stringify({ parameters, focus })}
        role="img"
        aria-label={compiled.title}
        style={{ height: `clamp(250px, 54vw, ${surfaceHeight}px)` }}
      />
      {(compiled.spec.parameters ?? []).length > 0 ? (
        <div className="weibei-function__parameters" aria-label="函数参数">
          {(compiled.spec.parameters ?? []).map((parameter) => {
            const value = parameters[parameter.id] ?? parameter.value;
            return (
              <label key={parameter.id} className="weibei-function__parameter">
                <span>{parameter.label}</span>
                <input
                  type="range"
                  min={parameter.minimum}
                  max={parameter.maximum}
                  step={parameter.step}
                  value={value}
                  onChange={(event) => setParameters((current) => ({
                    ...current,
                    [parameter.id]: Number(event.currentTarget.value),
                  }))}
                />
                <strong>{formatNumber(value)}{parameter.unit ? ` ${parameter.unit}` : ""}</strong>
              </label>
            );
          })}
        </div>
      ) : null}
      {compiled.spec.probeEnabled ? (
        <figcaption className={`weibei-function__readout${focus ? " is-active" : ""}`}>
          {focus ? (
            <span>{compiled.spec.variable} = {formatNumber(focus.x)}，y = {formatNumber(focus.y)}</span>
          ) : (
            <span>点击曲线查看对应读数</span>
          )}
        </figcaption>
      ) : null}
      {segments.length === 0 ? (
        <figcaption className="weibei-function__empty">当前定义域和参数下没有可绘制的实数值。</figcaption>
      ) : null}
      {compiled.spec.caption ? <figcaption className="weibei-function__caption">{compiled.spec.caption}</figcaption> : null}
    </figure>
  );
}

function FunctionFallback({ issue }: { issue: ReturnType<typeof createRendererIssue> }) {
  return (
    <div className="generation-error" role="alert" data-weibei-renderer-issue={issue.code}>
      <strong>函数图未渲染</strong>
      <span>{issue.message}</span>
      {issue.details?.length ? <small>{issue.details.join("；")}</small> : null}
    </div>
  );
}

export const mathFunctionRenderer: RichAnswerRenderer = {
  id: FUNCTION_RENDERER,
  version: "0.1.0",
  capabilities: {
    renderer: FUNCTION_RENDERER,
    version: "0.1.0",
    specVersions: [FUNCTION_SPEC_VERSION],
    displayName: "魏碑受限数学函数",
    data: ["restricted-expression-graph", "adaptive-sampling", "discontinuity-segmentation"],
    interactions: ["parameter-adjust", "curve-probe", "responsive-resize"],
    resources: ["local-echarts-canvas"],
    maxNodes: maxExpressionNodes,
    maxDataPoints: maxGeneratedPoints,
    fallback: ["structured_error", "simplified_component"],
  },
  validate(plan) {
    const parsed = parseFunctionSpec(plan);
    return parsed.ok ? { ok: true } : { ok: false, issue: parsed.issue };
  },
  compile(plan, context) {
    const parsed = parseFunctionSpec(plan);
    if (!parsed.ok) return { ok: false, issue: parsed.issue };
    return {
      ok: true,
      compiled: {
        renderer: FUNCTION_RENDERER,
        version: FUNCTION_SPEC_VERSION,
        plan,
        programID: context.program.id,
        title: parsed.spec.title,
        spec: parsed.spec,
        nodeByID: parsed.nodeByID,
      },
    };
  },
  mount(compiled, context) {
    return <FunctionMount compiled={compiled as FunctionCompiledRenderPlan} context={context} />;
  },
  update(compiled, _previous, context) {
    return <FunctionMount compiled={compiled as FunctionCompiledRenderPlan} context={context} />;
  },
  dispose() {
    return undefined;
  },
  fallback(issue) {
    return <FunctionFallback issue={issue} />;
  },
};
