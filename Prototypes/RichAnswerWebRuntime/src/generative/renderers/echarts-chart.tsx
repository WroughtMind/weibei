import { useEffect, useMemo, useRef, useState } from "react";
import * as echarts from "echarts";
import type { ECharts, EChartsOption } from "echarts";
import { z } from "zod/v4";
import {
  createRendererIssue,
  type CompiledRenderPlan,
  type RenderPlan,
  type RendererIssue,
  type RendererLifecycleContext,
  type RichAnswerRenderer,
} from "../renderer-registry";

const CHART_RENDERER = "weibei.echarts.chart";
const CHART_SPEC_VERSION = "weibei.chart.v1";
const maxTrustedSeries = 8;
const maxTrustedDataPoints = 4000;
const chartSizeWaitMS = 1500;

const finiteNumber = z.number().refine(Number.isFinite, "必须是有限数字");

const chartSeriesSchema = z.object({
  name: z.string().min(1).max(80),
  values: z.array(finiteNumber).min(1).max(1000),
  xValues: z.array(finiteNumber).min(1).max(1000).optional(),
  chartKind: z.enum(["line", "bar", "area"]).optional(),
  unit: z.string().min(1).max(24).optional(),
}).strict();

const chartSpecSchema = z.object({
  chartKind: z.enum(["line", "bar", "area", "scatter", "mixed", "histogram"]),
  title: z.string().min(1).max(120).optional(),
  series: z.array(chartSeriesSchema).min(1).max(maxTrustedSeries).optional(),
  xLabels: z.array(z.string().min(1).max(80)).min(1).max(1000).optional(),
  xAxisLabel: z.string().min(1).max(80).optional(),
  yAxisLabel: z.string().min(1).max(80).optional(),
  caption: z.string().min(1).max(220).optional(),
  focusEnabled: z.boolean().optional(),
  binCount: z.number().int().min(3).max(60).optional(),
  samples: z.array(finiteNumber).min(1).max(maxTrustedDataPoints).optional(),
}).strict();

type ChartSpec = z.infer<typeof chartSpecSchema>;

type FocusState = {
  seriesName: string;
  label: string;
  value: number;
  unit?: string;
  dataIndex: number;
};

type ChartCompiledRenderPlan = CompiledRenderPlan & {
  spec: ChartSpec;
  pointCount: number;
};

type ChartSurfaceSize = {
  width: number;
  height: number;
};

function parseChartSpec(plan: RenderPlan) {
  const result = chartSpecSchema.safeParse(plan.spec);
  if (!result.success) {
    return {
      ok: false as const,
      issue: createRendererIssue(
        "validation_error",
        plan.renderer,
        result.error.issues[0]?.message ?? "标准图表规格不符合协议。",
        result.error.issues.map((issue) => issue.path.join(".")).filter(Boolean),
      ),
    };
  }

  const issue = guardChartPlan(plan, result.data);
  if (issue) return { ok: false as const, issue };

  return { ok: true as const, spec: result.data };
}

function guardChartPlan(plan: RenderPlan, spec: ChartSpec) {
  if (plan.renderer !== CHART_RENDERER) {
    return createRendererIssue("capability_mismatch", plan.renderer, `标准图表渲染器不能渲染 ${plan.renderer}。`);
  }
  if (plan.specVersion !== CHART_SPEC_VERSION) {
    return createRendererIssue("capability_mismatch", plan.renderer, `标准图表渲染器只支持 ${CHART_SPEC_VERSION}。`);
  }
  if (plan.qualityBudget.allowNetwork) {
    return createRendererIssue("capability_mismatch", plan.renderer, "标准图表渲染器不允许使用外部网络资源。");
  }
  if (plan.qualityBudget.allowWebGL) {
    return createRendererIssue("capability_mismatch", plan.renderer, "标准图表渲染器只使用本地 Canvas，不接受 WebGL 预算。");
  }

  const pointCount = chartPointCount(spec);
  const pointBudget = plan.qualityBudget.maxDataPoints ?? maxTrustedDataPoints;
  if (pointCount > pointBudget || pointCount > maxTrustedDataPoints) {
    return createRendererIssue(
      "validation_error",
      plan.renderer,
      `图表数据点 ${pointCount} 超过预算。`,
      [`renderPlan=${pointBudget}`, `renderer=${maxTrustedDataPoints}`],
    );
  }

  if (spec.chartKind === "histogram") {
    if (!spec.samples?.length) {
      return createRendererIssue("validation_error", plan.renderer, "直方图必须提供 samples。");
    }
    if (spec.series || spec.xLabels) {
      return createRendererIssue("validation_error", plan.renderer, "直方图只接受 samples/binCount，不接受 series/xLabels。");
    }
    return null;
  }

  if (spec.samples) {
    return createRendererIssue("validation_error", plan.renderer, "非直方图不接受 samples。");
  }
  if (!spec.series?.length) {
    return createRendererIssue("validation_error", plan.renderer, "标准图表必须提供 series。");
  }
  if (spec.chartKind === "scatter") {
    if (spec.xLabels) {
      return createRendererIssue("validation_error", plan.renderer, "散点图使用 series[].xValues，不接受分类 xLabels。");
    }
    for (const series of spec.series) {
      if (!series.xValues || series.xValues.length !== series.values.length) {
        return createRendererIssue(
          "validation_error",
          plan.renderer,
          `${series.name} 的 xValues 必须存在并与 values 等长。`,
        );
      }
    }
    return null;
  }
  if (!spec.xLabels?.length) {
    return createRendererIssue("validation_error", plan.renderer, "line/bar/area/mixed 图表必须提供 xLabels。");
  }
  for (const series of spec.series) {
    if (series.xValues) {
      return createRendererIssue("validation_error", plan.renderer, "只有散点图可以提供 series[].xValues。");
    }
    if (series.values.length !== spec.xLabels.length) {
      return createRendererIssue(
        "validation_error",
        plan.renderer,
        `${series.name} 的数据长度必须等于 xLabels 长度。`,
        [`series=${series.values.length}`, `xLabels=${spec.xLabels.length}`],
      );
    }
  }
  if (spec.chartKind === "mixed") {
    const units = spec.series.map((series) => series.unit?.trim()).filter(Boolean) as string[];
    if (units.length !== spec.series.length || new Set(units).size !== 1) {
      return createRendererIssue(
        "validation_error",
        plan.renderer,
        "混合图必须为每个系列声明同一个 unit；跨单位比较需要注册双轴或归一化渲染器。",
      );
    }
  }
  return null;
}

function chartPointCount(spec: ChartSpec) {
  if (spec.chartKind === "histogram") return spec.samples?.length ?? 0;
  return spec.series?.reduce((sum, series) => sum + series.values.length, 0) ?? 0;
}

function histogramBins(samples: number[], binCount: number) {
  const min = Math.min(...samples);
  const max = Math.max(...samples);
  const width = max === min ? 1 : (max - min) / binCount;
  const bins = Array.from({ length: binCount }, (_, index) => ({
    start: min + width * index,
    end: index === binCount - 1 ? max : min + width * (index + 1),
    count: 0,
  }));

  for (const sample of samples) {
    const rawIndex = max === min ? 0 : Math.floor((sample - min) / width);
    const index = Math.max(0, Math.min(binCount - 1, rawIndex));
    bins[index]!.count += 1;
  }

  return bins.map((bin) => ({
    label: `${formatNumber(bin.start)}–${formatNumber(bin.end)}`,
    value: bin.count,
  }));
}

function formatNumber(value: number) {
  if (Math.abs(value) >= 1000 || (Math.abs(value) > 0 && Math.abs(value) < 0.01)) {
    return value.toExponential(1);
  }
  return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/\.?0+$/, "");
}

function measureChartSurface(element: HTMLElement): ChartSurfaceSize | null {
  const rect = element.getBoundingClientRect();
  const style = window.getComputedStyle(element);
  const styleWidth = Number.parseFloat(style.width);
  const styleHeight = Number.parseFloat(style.height);
  const width = Math.round(rect.width || element.clientWidth || styleWidth);
  const height = Math.round(rect.height || element.clientHeight || styleHeight);

  if (!Number.isFinite(width) || !Number.isFinite(height) || width < 2 || height < 2) return null;
  return { width, height };
}

function describeChartSurface(element: HTMLElement) {
  const rect = element.getBoundingClientRect();
  return [
    `rect=${Math.round(rect.width)}×${Math.round(rect.height)}`,
    `client=${element.clientWidth}×${element.clientHeight}`,
  ];
}

function buildOption(compiled: ChartCompiledRenderPlan, width: number): EChartsOption {
  const spec = compiled.spec;
  const narrow = width < 520;
  const showLegend = spec.chartKind !== "histogram" && (spec.series?.length ?? 0) > 1;
  const titleTop = spec.title ? 6 : 0;
  const legendTop = spec.title ? 34 : 8;
  const gridTop = showLegend ? (narrow ? 94 : 68) : (spec.title ? 48 : 24);
  const animation = compiled.plan.qualityBudget.allowAnimation;

  if (spec.chartKind === "histogram") {
    const bins = histogramBins(spec.samples ?? [], spec.binCount ?? 12);
    return {
      animation,
      backgroundColor: "transparent",
      title: spec.title ? chartTitle(spec.title, titleTop) : undefined,
      tooltip: { trigger: "axis", confine: true },
      grid: chartGrid(gridTop, narrow),
      xAxis: chartCategoryAxis(bins.map((bin) => bin.label), spec.xAxisLabel ?? "区间", narrow),
      yAxis: chartValueAxis(spec.yAxisLabel ?? "频次"),
      series: [{
        name: "频次",
        type: "bar",
        data: bins.map((bin) => bin.value),
        barMaxWidth: 28,
        emphasis: { focus: "series" },
      }],
    };
  }

  if (spec.chartKind === "scatter") {
    const chartSeries = spec.series ?? [];
    return {
      animation,
      backgroundColor: "transparent",
      title: spec.title ? chartTitle(spec.title, titleTop) : undefined,
      tooltip: { trigger: "item", confine: true },
      legend: showLegend ? {
        type: "scroll",
        top: legendTop,
        left: 0,
        right: 0,
        itemWidth: 10,
        itemHeight: 6,
        textStyle: { color: "#665c50", fontSize: narrow ? 10 : 11 },
      } : undefined,
      grid: chartGrid(gridTop, narrow),
      xAxis: chartNumericAxis(spec.xAxisLabel),
      yAxis: chartValueAxis(spec.yAxisLabel),
      series: chartSeries.map((series) => ({
        name: series.name,
        type: "scatter",
        data: (series.xValues ?? []).map((xValue, index) => [xValue, series.values[index]]),
        symbolSize: 8,
        emphasis: { focus: "series" },
      })),
    };
  }

  const labels = spec.xLabels ?? [];
  const chartSeries = spec.series ?? [];
  return {
    animation,
    backgroundColor: "transparent",
    title: spec.title ? chartTitle(spec.title, titleTop) : undefined,
    tooltip: { trigger: "axis", confine: true },
    legend: showLegend ? {
      type: "scroll",
      top: legendTop,
      left: 0,
      right: 0,
      itemWidth: 10,
      itemHeight: 6,
      itemGap: narrow ? 12 : 18,
      textStyle: { color: "#665c50", fontSize: narrow ? 10 : 11 },
    } : undefined,
    grid: chartGrid(gridTop, narrow),
    xAxis: chartCategoryAxis(labels, spec.xAxisLabel, narrow),
    yAxis: chartValueAxis(spec.yAxisLabel),
    series: chartSeries.map((series, index) => {
      const kind = seriesKind(spec.chartKind, series.chartKind, index);
      return {
        name: series.name,
        type: kind === "area" ? "line" : kind,
        data: series.values,
        smooth: false,
        areaStyle: kind === "area" ? { opacity: 0.18 } : undefined,
        barMaxWidth: 28,
        emphasis: { focus: "series" },
      };
    }),
  };
}

function chartTitle(title: string, top: number): EChartsOption["title"] {
  return {
    text: title,
    top,
    left: 0,
    textStyle: {
      color: "#2c261f",
      fontFamily: "Songti SC, STSong, serif",
      fontSize: 15,
      fontWeight: 600,
    },
  };
}

function chartGrid(top: number, narrow: boolean): EChartsOption["grid"] {
  return {
    top,
    left: narrow ? 44 : 54,
    right: narrow ? 12 : 18,
    bottom: narrow ? 58 : 46,
    containLabel: true,
  };
}

function chartCategoryAxis(labels: string[], name: string | undefined, narrow: boolean): EChartsOption["xAxis"] {
  return {
    type: "category",
    name,
    nameLocation: "middle",
    nameGap: narrow ? 42 : 34,
    data: labels,
    axisLabel: {
      color: "#6f665b",
      fontSize: narrow ? 10 : 11,
      interval: "auto",
      hideOverlap: true,
      rotate: narrow ? 32 : 0,
    },
    axisLine: { lineStyle: { color: "#c7bcae" } },
    axisTick: { alignWithLabel: true },
  };
}

function chartValueAxis(name: string | undefined): EChartsOption["yAxis"] {
  return {
    type: "value",
    name,
    nameTextStyle: { color: "#6f665b", fontSize: 11, align: "left" },
    axisLabel: { color: "#6f665b", fontSize: 11 },
    splitLine: { lineStyle: { color: "rgba(70, 58, 43, 0.12)" } },
  };
}

function chartNumericAxis(name: string | undefined): EChartsOption["xAxis"] {
  return {
    type: "value",
    name,
    nameLocation: "middle",
    nameGap: 32,
    nameTextStyle: { color: "#6f665b", fontSize: 11 },
    axisLabel: { color: "#6f665b", fontSize: 11 },
    axisLine: { lineStyle: { color: "#c7bcae" } },
    splitLine: { lineStyle: { color: "rgba(70, 58, 43, 0.12)" } },
  };
}

function seriesKind(
  chartKind: ChartSpec["chartKind"],
  requestedKind: "line" | "bar" | "area" | undefined,
  index: number,
): "line" | "bar" | "area" {
  if (chartKind === "mixed") return requestedKind ?? (index === 0 ? "bar" : "line");
  if (chartKind === "histogram") return "bar";
  if (chartKind === "scatter") return "line";
  return chartKind;
}

function ChartMount({
  compiled,
  context,
}: {
  compiled: ChartCompiledRenderPlan;
  context: RendererLifecycleContext;
}) {
  const elementRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<ECharts | null>(null);
  const [focus, setFocus] = useState<FocusState | null>(null);
  const [renderIssue, setRenderIssue] = useState<RendererIssue | null>(null);
  const chartKey = useMemo(() => JSON.stringify(compiled.spec), [compiled.spec]);
  const surfaceHeight = Math.max(220, Math.min(520, compiled.plan.qualityBudget.maxHeight ?? 360));

  useEffect(() => {
    setFocus(null);
    setRenderIssue(null);
  }, [compiled.programID, chartKey]);

  useEffect(() => {
    const element = elementRef.current;
    if (!element) return;
    const surfaceElement: HTMLElement = element;

    let disposed = false;
    let chart: ECharts | null = null;
    let animationFrame: number | null = null;
    let retryTimer: number | null = null;
    const waitStartedAt = performance.now();

    const focusFromParams = (params: unknown) => {
      if (!compiled.spec.focusEnabled) return;
      const candidate = params as {
        seriesName?: string;
        seriesIndex?: number;
        name?: string;
        value?: unknown;
        dataIndex?: number;
      };
      const value = Array.isArray(candidate.value)
        ? candidate.value[candidate.value.length - 1]
        : candidate.value;
      if (typeof value !== "number" || !Number.isFinite(value)) return;
      setFocus({
        seriesName: candidate.seriesName ?? "数据",
        label: candidate.name ?? "",
        value,
        unit: compiled.spec.series?.[candidate.seriesIndex ?? -1]?.unit ?? compiled.spec.yAxisLabel,
        dataIndex: candidate.dataIndex ?? -1,
      });
    };

    const clearScheduledRender = () => {
      if (animationFrame !== null) {
        cancelAnimationFrame(animationFrame);
        animationFrame = null;
      }
      if (retryTimer !== null) {
        clearTimeout(retryTimer);
        retryTimer = null;
      }
    };

    const scheduleRender = () => {
      if (disposed || animationFrame !== null) return;
      animationFrame = requestAnimationFrame(renderChart);
    };

    const ensureChart = (size: ChartSurfaceSize) => {
      if (chart) return chart;
      try {
        chart = echarts.init(surfaceElement, undefined, {
          renderer: "canvas",
          devicePixelRatio: Math.min(2, Math.max(1, window.devicePixelRatio || 1)),
          width: size.width,
          height: size.height,
        });
        chartRef.current = chart;
        chart.on("click", focusFromParams);
        setRenderIssue(null);
        return chart;
      } catch (error) {
        setRenderIssue(createRendererIssue(
          "compile_error",
          CHART_RENDERER,
          "标准图表初始化失败，已停止静默空白呈现。",
          [error instanceof Error ? error.message : "未知初始化错误"],
        ));
        return null;
      }
    };

    function renderChart() {
      animationFrame = null;
      if (disposed) return;

      const size = measureChartSurface(surfaceElement);
      if (!size) {
        if (performance.now() - waitStartedAt >= chartSizeWaitMS) {
          setRenderIssue(createRendererIssue(
            "compile_error",
            CHART_RENDERER,
            "标准图表容器还没有可用尺寸，暂时无法绘制。",
            describeChartSurface(surfaceElement),
          ));
          return;
        }
        retryTimer = window.setTimeout(scheduleRender, 80);
        return;
      }

      const activeChart = ensureChart(size);
      if (!activeChart) return;

      try {
        activeChart.resize({ width: size.width, height: size.height });
        activeChart.setOption(buildOption(compiled, size.width), { notMerge: true });
        activeChart.resize({ width: size.width, height: size.height });
        setRenderIssue(null);
      } catch (error) {
        setRenderIssue(createRendererIssue(
          "compile_error",
          CHART_RENDERER,
          "标准图表绘制失败，已停止静默空白呈现。",
          [error instanceof Error ? error.message : "未知绘制错误"],
        ));
      }
    }

    const verifyInteraction = () => {
      if (!compiled.spec.focusEnabled) return;
      if (compiled.spec.chartKind === "histogram") {
        const bins = histogramBins(compiled.spec.samples ?? [], compiled.spec.binCount ?? 12);
        const bin = bins[Math.min(1, Math.max(0, bins.length - 1))];
        if (!bin) return;
        setFocus({
          seriesName: "频次",
          label: bin.label,
          value: bin.value,
          unit: compiled.spec.yAxisLabel ?? "次",
          dataIndex: Math.min(1, Math.max(0, bins.length - 1)),
        });
        return;
      }
      const series = compiled.spec.series?.[0];
      const dataIndex = Math.min(1, Math.max(0, (series?.values.length ?? 1) - 1));
      const value = series?.values[dataIndex];
      if (!series || value === undefined) return;
      setFocus({
        seriesName: series.name,
        label: compiled.spec.chartKind === "scatter"
          ? formatNumber(series.xValues?.[dataIndex] ?? 0)
          : compiled.spec.xLabels?.[dataIndex] ?? "",
        value,
        unit: series.unit ?? compiled.spec.yAxisLabel,
        dataIndex,
      });
    };

    surfaceElement.addEventListener("weibei:verify-interaction", verifyInteraction);

    const observer = new ResizeObserver(scheduleRender);
    observer.observe(surfaceElement);
    if (surfaceElement.parentElement) observer.observe(surfaceElement.parentElement);
    window.addEventListener("resize", scheduleRender);
    scheduleRender();

    return () => {
      disposed = true;
      clearScheduledRender();
      observer.disconnect();
      window.removeEventListener("resize", scheduleRender);
      chart?.off("click", focusFromParams);
      surfaceElement.removeEventListener("weibei:verify-interaction", verifyInteraction);
      chart?.dispose();
      chartRef.current = null;
    };
  }, [compiled, chartKey]);

  useEffect(() => {
    if (!focus) return;
    chartRef.current?.dispatchAction({ type: "highlight", seriesName: focus.seriesName, dataIndex: focus.dataIndex });
    chartRef.current?.dispatchAction({ type: "showTip", seriesName: focus.seriesName, dataIndex: focus.dataIndex });
    context.postMessage({
      type: "weibei:state",
      programID: compiled.programID,
      state: {
        renderer: CHART_RENDERER,
        focus,
      },
    });
  }, [compiled.programID, context, focus]);

  return (
    <figure className="weibei-chart" data-weibei-renderer={CHART_RENDERER}>
      <div
        ref={elementRef}
        className="weibei-chart__surface"
        data-weibei-control="chart-probe"
        data-weibei-control-id={compiled.programID}
        data-weibei-state={focus ? JSON.stringify(focus) : ""}
        role="img"
        aria-label={compiled.title}
        style={{ height: `min(${surfaceHeight}px, max(220px, 56vw))` }}
      />
      {renderIssue ? <ChartFallback issue={renderIssue} /> : null}
      {compiled.spec.focusEnabled ? (
        <figcaption className={`weibei-chart__readout${focus ? " is-active" : ""}`}>
          {focus ? (
            <>
              <strong>{focus.seriesName}</strong>
              <span>{focus.label ? `${focus.label}：` : ""}{formatNumber(focus.value)}{focus.unit ? ` ${focus.unit}` : ""}</span>
            </>
          ) : (
            <span>点击数据点查看读数</span>
          )}
        </figcaption>
      ) : null}
      {compiled.spec.caption ? <figcaption className="weibei-chart__caption">{compiled.spec.caption}</figcaption> : null}
    </figure>
  );
}

function ChartFallback({
  issue,
}: {
  issue: ReturnType<typeof createRendererIssue>;
}) {
  return (
    <div className="generation-error" role="alert" data-weibei-renderer-issue={issue.code}>
      <strong>标准图表未渲染</strong>
      <span>{issue.message}</span>
      {issue.details?.length ? <small>{issue.details.join("；")}</small> : null}
    </div>
  );
}

export const standardEChartsRenderer: RichAnswerRenderer = {
  id: CHART_RENDERER,
  version: "0.1.0",
  capabilities: {
    renderer: CHART_RENDERER,
    version: "0.1.0",
    specVersions: [CHART_SPEC_VERSION],
    displayName: "魏碑可信标准图表",
    data: ["categorical-series", "numeric-pairs", "histogram-samples", "bounded-inline-data"],
    interactions: ["focus-readout", "state-update", "responsive-resize"],
    resources: ["local-echarts"],
    maxNodes: 1,
    maxDataPoints: maxTrustedDataPoints,
    fallback: ["structured_error", "simplified_component"],
  },
  validate(plan) {
    const parsed = parseChartSpec(plan);
    return parsed.ok ? { ok: true } : { ok: false, issue: parsed.issue };
  },
  compile(plan, context) {
    const parsed = parseChartSpec(plan);
    if (!parsed.ok) return { ok: false, issue: parsed.issue };
    return {
      ok: true,
      compiled: {
        renderer: CHART_RENDERER,
        version: CHART_SPEC_VERSION,
        plan,
        programID: context.program.id,
        title: parsed.spec.title ?? context.program.title,
        spec: parsed.spec,
        pointCount: chartPointCount(parsed.spec),
      },
    };
  },
  mount(compiled, context) {
    return <ChartMount compiled={compiled as ChartCompiledRenderPlan} context={context} />;
  },
  update(compiled, _previous, context) {
    return <ChartMount compiled={compiled as ChartCompiledRenderPlan} context={context} />;
  },
  dispose() {
    return undefined;
  },
  fallback(issue) {
    return <ChartFallback issue={issue} />;
  },
};
