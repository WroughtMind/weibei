import { useEffect, useMemo, useRef } from "react";
import { BarChart, LineChart } from "echarts/charts";
import { GridComponent, LegendComponent, MarkLineComponent, TooltipComponent } from "echarts/components";
import * as echarts from "echarts/core";
import type { EChartsCoreOption, EChartsType } from "echarts/core";
import { CanvasRenderer } from "echarts/renderers";
import { defineComponent, reactive, useStateField } from "@openuidev/react-lang";
import { z } from "zod/v4";
import { isEmbeddedRuntime } from "./protocol";
import "./knowledge-components.css";

echarts.use([BarChart, LineChart, GridComponent, LegendComponent, MarkLineComponent, TooltipComponent, CanvasRenderer]);

function numeric(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function formatNumber(value: number, digits = 1) {
  if (!Number.isFinite(value)) return "—";
  if (Math.abs(value) < 0.0001) return "0";
  return Number.isInteger(value) ? String(value) : value.toFixed(digits).replace(/\.0+$/, "");
}

function visibleUnit(value: string) {
  const unit = value.trim();
  return ["", "无单位", "unitless", "dimensionless", "none"].includes(unit.toLowerCase()) ? "" : unit;
}

const chartColors = ["#8f3f2f", "#3f716b", "#b0793b", "#5d6385", "#7f6558", "#607344"] as const;

export const ChartSeries = defineComponent({
  name: "ChartSeries",
  description: "图表中的一条数据序列。只提供真实数据与视觉编码，不负责整张图表布局。",
  props: z.object({
    name: z.string(),
    kind: z.enum(["line", "bar"]),
    values: z.array(z.number()).min(2).max(40),
    unit: z.string(),
    color: z.enum(["cinnabar", "jade", "ochre", "indigo", "umber", "moss"]),
  }),
  component: () => null,
});

const chartColorByName: Record<string, string> = {
  cinnabar: chartColors[0],
  jade: chartColors[1],
  ochre: chartColors[2],
  indigo: chartColors[3],
  umber: chartColors[4],
  moss: chartColors[5],
};

export const LinkedDataChart = defineComponent({
  name: "LinkedDataChart",
  description: "由 AI 提供横轴和多条真实序列；用户点击任意点后，图表与当前读数共同聚焦。Canvas 本地绘制。",
  props: z.object({
    stateName: z.string(),
    focusIndex: reactive(z.number()),
    title: z.string(),
    xLabels: z.array(z.string()).min(2).max(40),
    series: z.array(ChartSeries.ref).min(1).max(6),
    caption: z.string(),
    height: z.number().int().min(220).max(420),
  }),
  component: ({ props }) => {
    const focusField = useStateField(props.stateName, props.focusIndex);
    const focusIndex = Math.max(0, Math.min(props.xLabels.length - 1, Math.round(numeric(focusField.value))));
    const elementRef = useRef<HTMLDivElement>(null);
    const chartRef = useRef<EChartsType | null>(null);

    const option = useMemo<EChartsCoreOption>(() => ({
      animation: true,
      aria: { enabled: true, decal: { show: false } },
      grid: { left: 42, right: 16, top: props.series.length > 1 ? 46 : 24, bottom: 38, containLabel: false },
      legend: props.series.length > 1
        ? { top: 4, left: 4, itemWidth: 14, itemHeight: 3, textStyle: { color: "#6d6255", fontSize: 10 } }
        : undefined,
      tooltip: {
        trigger: "axis",
        confine: true,
        backgroundColor: "#332e27",
        borderWidth: 0,
        padding: [7, 9],
        textStyle: { color: "#f7f1e7", fontSize: 11 },
      },
      xAxis: {
        type: "category",
        data: props.xLabels,
        axisLine: { lineStyle: { color: "#776c5e" } },
        axisTick: { show: false },
        axisLabel: { color: "#817668", fontSize: 10, interval: "auto" },
      },
      yAxis: {
        type: "value",
        scale: true,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: "rgba(76, 65, 51, 0.08)" } },
        axisLabel: { color: "#817668", fontSize: 10 },
      },
      series: props.series.map((series, seriesIndex) => ({
        name: series.props.name,
        type: series.props.kind,
        data: series.props.values.slice(0, props.xLabels.length),
        showSymbol: series.props.kind === "line",
        symbolSize: 5,
        barMaxWidth: 24,
        smooth: false,
        animationDuration: 180,
        itemStyle: { color: chartColorByName[series.props.color] ?? chartColors[seriesIndex % chartColors.length] ?? chartColors[0] },
        lineStyle: { width: 2.2, color: chartColorByName[series.props.color] ?? chartColors[seriesIndex % chartColors.length] ?? chartColors[0] },
        markLine: seriesIndex === 0
          ? {
              silent: true,
              symbol: "none",
              label: { show: false },
              lineStyle: { color: "rgba(143, 63, 47, 0.44)", width: 1 },
              data: [{ xAxis: props.xLabels[focusIndex] }],
            }
          : undefined,
      })),
    }), [focusIndex, props.height, props.series, props.xLabels]);

    useEffect(() => {
      const element = elementRef.current;
      if (!element) return;
      const chart = echarts.init(element, undefined, { renderer: "canvas" });
      chartRef.current = chart;
      const onClick = (event: { dataIndex?: number }) => {
        if (typeof event.dataIndex === "number") focusField.setValue(event.dataIndex);
      };
      chart.on("click", onClick);
      const observer = new ResizeObserver(() => chart.resize());
      observer.observe(element);
      return () => {
        observer.disconnect();
        chart.off("click", onClick);
        chart.dispose();
        chartRef.current = null;
      };
    }, []);

    useEffect(() => {
      chartRef.current?.setOption(
        isEmbeddedRuntime() ? { ...option, animation: false } : option,
        { notMerge: true, lazyUpdate: false },
      );
    }, [option]);

    return (
      <figure className="ra-linked-chart">
        <figcaption>
          <span>{props.title}</span>
          <strong>{props.xLabels[focusIndex]}</strong>
        </figcaption>
        <div
          ref={elementRef}
          role="img"
          aria-label={`${props.title} 图表，当前聚焦 ${props.xLabels[focusIndex]}`}
          data-weibei-control="linked-data-chart"
          data-weibei-control-id={props.stateName}
          style={{ height: `${props.height}px` }}
        />
        <div className="ra-linked-chart__readout">
          {props.series.map((series) => (
            <span key={series.props.name}>
              <small>{series.props.name}</small>
              <strong>{formatNumber(series.props.values[focusIndex] ?? 0)}</strong>
              {visibleUnit(series.props.unit) ? <i>{visibleUnit(series.props.unit)}</i> : null}
            </span>
          ))}
        </div>
        <p>{props.caption}</p>
      </figure>
    );
  },
});

export const MetricItem = defineComponent({
  name: "MetricItem",
  description: "一个有语义的读数，可与图表、实验或推导结果共同出现。",
  props: z.object({
    label: z.string(),
    value: z.string(),
    unit: z.string(),
    detail: z.string(),
    tone: z.enum(["neutral", "positive", "warning"]),
  }),
  component: () => null,
});

export const MetricStrip = defineComponent({
  name: "MetricStrip",
  description: "展示二到六个关键读数，不把每个读数做成独立装饰卡片。",
  props: z.object({
    items: z.array(MetricItem.ref).min(2).max(6),
  }),
  component: ({ props }) => (
    <div className="ra-metric-strip">
      {props.items.map((item) => {
        const unit = visibleUnit(item.props.unit);
        return (
          <div key={`${item.props.label}-${item.props.value}`} data-tone={item.props.tone}>
            <span>{item.props.label}</span>
            <strong>{item.props.value}</strong>
            {unit ? <i>{unit}</i> : null}
            <small>{item.props.detail}</small>
          </div>
        );
      })}
    </div>
  ),
});

export const ExecutionFrame = defineComponent({
  name: "ExecutionFrame",
  description: "执行过程的一帧：当前行、变量状态和这一帧真正发生的变化。",
  props: z.object({
    label: z.string(),
    activeLine: z.number().int().min(0).max(80),
    values: z.array(z.string()).min(1).max(16),
    changedIndices: z.array(z.number().int().min(0).max(15)).max(8),
    explanation: z.string(),
  }),
  component: () => null,
});

export const ExecutionTrack = defineComponent({
  name: "ExecutionTrack",
  description: "把代码行、数组或变量、执行步骤联动。AI 提供代码与状态帧，组件只负责安全地前后步进。",
  props: z.object({
    stateName: z.string(),
    activeStep: reactive(z.number()),
    title: z.string(),
    codeLines: z.array(z.string()).min(1).max(40),
    frames: z.array(ExecutionFrame.ref).min(2).max(48),
  }),
  component: ({ props }) => {
    const stepField = useStateField(props.stateName, props.activeStep);
    const activeIndex = Math.max(0, Math.min(props.frames.length - 1, Math.round(numeric(stepField.value))));
    const activeFrame = props.frames[activeIndex]!;
    const progress = ((activeIndex + 1) / props.frames.length) * 100;

    return (
      <section className="ra-execution-track">
        <header>
          <span>{props.title}</span>
          <strong>{activeFrame.props.label}</strong>
        </header>
        <div className="ra-execution-track__body">
          <div className="ra-code-list" aria-label="代码">
            {props.codeLines.map((line, index) => (
              <pre key={`${line}-${index}`} className={index === activeFrame.props.activeLine ? "is-active" : ""}>
                <span>{index + 1}</span>
                <code>{line}</code>
              </pre>
            ))}
          </div>
          <div className="ra-state-frame">
            <div className="ra-state-frame__values">
              {activeFrame.props.values.map((value, index) => (
                <span key={`${value}-${index}`} className={activeFrame.props.changedIndices.includes(index) ? "is-changed" : ""}>
                  <small>{index}</small>
                  <strong>{value}</strong>
                </span>
              ))}
            </div>
            <p>{activeFrame.props.explanation}</p>
            <div className="ra-execution-controls">
              <button
                type="button"
                aria-label={`${props.title} 上一步`}
                data-weibei-control="execution-prev"
                data-weibei-control-id={props.stateName}
                disabled={activeIndex === 0}
                onClick={() => stepField.setValue(activeIndex - 1)}
              >上一步</button>
              <div><i style={{ width: `${progress}%` }} /></div>
              <button
                type="button"
                aria-label={`${props.title} 下一步`}
                data-weibei-control="execution-next"
                data-weibei-control-id={props.stateName}
                disabled={activeIndex === props.frames.length - 1}
                onClick={() => stepField.setValue(activeIndex + 1)}
              >下一步</button>
            </div>
          </div>
        </div>
      </section>
    );
  },
});

export const ArgumentUnit = defineComponent({
  name: "ArgumentUnit",
  description: "原文中的一个论证单元，保留原句、角色、解释与证据锚点。",
  props: z.object({
    role: z.enum(["claim", "reason", "evidence", "counter", "response", "context"]),
    roleLabel: z.string(),
    text: z.string(),
    note: z.string(),
    evidenceID: z.string(),
  }),
  component: () => null,
});

export const ArgumentReader = defineComponent({
  name: "ArgumentReader",
  description: "逐句点读原文并同步显示论证角色。AI 决定切分和角色，不把原文改写成固定流程图。",
  props: z.object({
    stateName: z.string(),
    activeUnit: reactive(z.number()),
    title: z.string(),
    units: z.array(ArgumentUnit.ref).min(2).max(12),
  }),
  component: ({ props }) => {
    const activeField = useStateField(props.stateName, props.activeUnit);
    const activeIndex = Math.max(0, Math.min(props.units.length - 1, Math.round(numeric(activeField.value))));
    const active = props.units[activeIndex]!;

    return (
      <section className="ra-argument-reader">
        <header><span>{props.title}</span><strong>{active.props.roleLabel}</strong></header>
        <div className="ra-argument-reader__copy">
          {props.units.map((unit, index) => (
            <button
              key={`${unit.props.role}-${index}`}
              type="button"
              aria-label={`${props.title} 第 ${index + 1} 句：${unit.props.roleLabel}`}
              data-weibei-control="argument-unit"
              data-weibei-control-id={`${props.stateName}-${index}`}
              className={index === activeIndex ? "is-active" : ""}
              onClick={() => activeField.setValue(index)}
            >
              <sup>{index + 1}</sup>{unit.props.text}
            </button>
          ))}
        </div>
        <aside>
          <span>{active.props.roleLabel}</span>
          <p>{active.props.note}</p>
          <button
            type="button"
            aria-label={`回到原文第 ${activeIndex + 1} 处`}
            data-weibei-control="argument-evidence"
            data-weibei-control-id={active.props.evidenceID}
            onClick={() => window.dispatchEvent(new CustomEvent("weibei:evidence", { detail: { evidenceID: active.props.evidenceID } }))}
          >回到原文第 {activeIndex + 1} 处</button>
        </aside>
      </section>
    );
  },
});

export const CausalEvent = defineComponent({
  name: "CausalEvent",
  description: "因果路径中的一个事件或条件，必须标清角色、证据强度与和前一节点的关系。",
  props: z.object({
    time: z.string(),
    label: z.string(),
    kind: z.enum(["context", "trigger", "action", "result", "uncertain"]),
    kindLabel: z.string(),
    relationFromPrevious: z.string(),
    confidence: z.enum(["strong", "medium", "insufficient"]),
    detail: z.string(),
    evidenceID: z.string(),
  }),
  component: () => null,
});

export const CausalTrack = defineComponent({
  name: "CausalTrack",
  description: "沿时间顺序查看背景、触发、行动、结果与证据不足；不会把先后自动画成因果。",
  props: z.object({
    stateName: z.string(),
    activeEvent: reactive(z.number()),
    title: z.string(),
    events: z.array(CausalEvent.ref).min(2).max(10),
  }),
  component: ({ props }) => {
    const activeField = useStateField(props.stateName, props.activeEvent);
    const activeIndex = Math.max(0, Math.min(props.events.length - 1, Math.round(numeric(activeField.value))));
    const active = props.events[activeIndex]!;

    return (
      <section className="ra-causal-track">
        <header><span>{props.title}</span><strong>{active.props.time}</strong></header>
        <div className="ra-causal-track__rail">
          {props.events.map((event, index) => (
            <button
              key={`${event.props.time}-${event.props.label}`}
              type="button"
              aria-label={`${props.title}：${event.props.time} ${event.props.label}`}
              data-weibei-control="causal-event"
              data-weibei-control-id={`${props.stateName}-${index}`}
              data-kind={event.props.kind}
              data-confidence={event.props.confidence}
              className={index === activeIndex ? "is-active" : ""}
              onClick={() => activeField.setValue(index)}
            >
              <i />
              <small>{event.props.time}</small>
              <strong>{event.props.label}</strong>
              {index > 0 ? <span>{event.props.relationFromPrevious}</span> : null}
            </button>
          ))}
        </div>
        <aside>
          <span>{active.props.kindLabel} · {active.props.confidence === "insufficient" ? "证据不足" : `证据${active.props.confidence === "strong" ? "强" : "中"}`}</span>
          <strong>{active.props.label}</strong>
          <p>{active.props.detail}</p>
          <button
            type="button"
            aria-label={`查看材料：${active.props.label}`}
            data-weibei-control="causal-evidence"
            data-weibei-control-id={active.props.evidenceID}
            onClick={() => window.dispatchEvent(new CustomEvent("weibei:evidence", { detail: { evidenceID: active.props.evidenceID } }))}
          >查看这一步的材料</button>
        </aside>
      </section>
    );
  },
});

export const TwoPointLineLab = defineComponent({
  name: "TwoPointLineLab",
  description: "Canvas 双点直线实验。AI 提供状态名、初始点和范围；用户拖点后公式、斜率三角形与取值同步更新。",
  props: z.object({
    x1Name: z.string(),
    x1: reactive(z.number()),
    y1Name: z.string(),
    y1: reactive(z.number()),
    x2Name: z.string(),
    x2: reactive(z.number()),
    y2Name: z.string(),
    y2: reactive(z.number()),
    title: z.string(),
    xMinimum: z.number(),
    xMaximum: z.number(),
    yMinimum: z.number(),
    yMaximum: z.number(),
    height: z.number().int().min(240).max(420),
  }),
  component: ({ props }) => {
    const x1Field = useStateField(props.x1Name, props.x1);
    const y1Field = useStateField(props.y1Name, props.y1);
    const x2Field = useStateField(props.x2Name, props.x2);
    const y2Field = useStateField(props.y2Name, props.y2);
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const draggingRef = useRef<"a" | "b" | null>(null);
    const pointA = { x: numeric(x1Field.value), y: numeric(y1Field.value) };
    const pointB = { x: numeric(x2Field.value), y: numeric(y2Field.value) };
    const deltaX = pointB.x - pointA.x;
    const deltaY = pointB.y - pointA.y;
    const vertical = Math.abs(deltaX) < 0.04;
    const slope = vertical ? Number.POSITIVE_INFINITY : deltaY / deltaX;
    const intercept = vertical ? Number.NaN : pointA.y - slope * pointA.x;

    useEffect(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      const draw = () => {
        const bounds = canvas.getBoundingClientRect();
        const scale = window.devicePixelRatio || 1;
        canvas.width = Math.max(1, Math.round(bounds.width * scale));
        canvas.height = Math.max(1, Math.round(bounds.height * scale));
        const context = canvas.getContext("2d");
        if (!context) return;
        context.setTransform(scale, 0, 0, scale, 0, 0);
        context.clearRect(0, 0, bounds.width, bounds.height);
        const padding = Math.min(38, Math.max(24, bounds.width * 0.07));
        const plotWidth = bounds.width - padding * 2;
        const plotHeight = bounds.height - padding * 2;
        const mapX = (value: number) => padding + ((value - props.xMinimum) / (props.xMaximum - props.xMinimum)) * plotWidth;
        const mapY = (value: number) => padding + ((props.yMaximum - value) / (props.yMaximum - props.yMinimum)) * plotHeight;

        context.strokeStyle = "rgba(75, 64, 51, 0.10)";
        context.lineWidth = 1;
        for (let index = 0; index <= 10; index += 1) {
          const x = padding + (plotWidth * index) / 10;
          context.beginPath(); context.moveTo(x, padding); context.lineTo(x, bounds.height - padding); context.stroke();
        }
        for (let index = 0; index <= 8; index += 1) {
          const y = padding + (plotHeight * index) / 8;
          context.beginPath(); context.moveTo(padding, y); context.lineTo(bounds.width - padding, y); context.stroke();
        }

        context.strokeStyle = "rgba(66, 57, 47, 0.55)";
        if (props.yMinimum <= 0 && props.yMaximum >= 0) {
          context.beginPath(); context.moveTo(padding, mapY(0)); context.lineTo(bounds.width - padding, mapY(0)); context.stroke();
        }
        if (props.xMinimum <= 0 && props.xMaximum >= 0) {
          context.beginPath(); context.moveTo(mapX(0), padding); context.lineTo(mapX(0), bounds.height - padding); context.stroke();
        }

        context.save();
        context.beginPath();
        context.rect(padding, padding, plotWidth, plotHeight);
        context.clip();
        context.strokeStyle = "#8f3f2f";
        context.lineWidth = 2.4;
        context.beginPath();
        if (vertical) {
          context.moveTo(mapX(pointA.x), padding);
          context.lineTo(mapX(pointA.x), bounds.height - padding);
        } else {
          context.moveTo(mapX(props.xMinimum), mapY(slope * props.xMinimum + intercept));
          context.lineTo(mapX(props.xMaximum), mapY(slope * props.xMaximum + intercept));
        }
        context.stroke();
        context.setLineDash([5, 4]);
        context.strokeStyle = "rgba(63, 113, 107, 0.78)";
        context.lineWidth = 1.4;
        context.beginPath();
        context.moveTo(mapX(pointA.x), mapY(pointA.y));
        context.lineTo(mapX(pointB.x), mapY(pointA.y));
        context.lineTo(mapX(pointB.x), mapY(pointB.y));
        context.stroke();
        context.restore();

        [{ point: pointA, label: "A" }, { point: pointB, label: "B" }].forEach(({ point, label }) => {
          const x = mapX(point.x);
          const y = mapY(point.y);
          context.fillStyle = "#3f716b";
          context.beginPath(); context.arc(x, y, 11, 0, Math.PI * 2); context.fill();
          context.fillStyle = "#fffaf1";
          context.font = "600 11px -apple-system, BlinkMacSystemFont, sans-serif";
          context.textAlign = "center";
          context.textBaseline = "middle";
          context.fillText(label, x, y + 0.5);
        });
      };
      draw();
      const observer = new ResizeObserver(draw);
      observer.observe(canvas);
      return () => observer.disconnect();
    }, [pointA.x, pointA.y, pointB.x, pointB.y, props.height, props.xMaximum, props.xMinimum, props.yMaximum, props.yMinimum]);

    const updatePoint = (event: React.PointerEvent<HTMLCanvasElement>) => {
      const target = draggingRef.current;
      if (!target) return;
      const bounds = event.currentTarget.getBoundingClientRect();
      const padding = Math.min(38, Math.max(24, bounds.width * 0.07));
      const xRatio = Math.max(0, Math.min(1, (event.clientX - bounds.left - padding) / (bounds.width - padding * 2)));
      const yRatio = Math.max(0, Math.min(1, (event.clientY - bounds.top - padding) / (bounds.height - padding * 2)));
      const x = props.xMinimum + xRatio * (props.xMaximum - props.xMinimum);
      const y = props.yMaximum - yRatio * (props.yMaximum - props.yMinimum);
      if (target === "a") { x1Field.setValue(x); y1Field.setValue(y); }
      if (target === "b") { x2Field.setValue(x); y2Field.setValue(y); }
    };

    const startDragging = (event: React.PointerEvent<HTMLCanvasElement>) => {
      const bounds = event.currentTarget.getBoundingClientRect();
      const padding = Math.min(38, Math.max(24, bounds.width * 0.07));
      const mapX = (value: number) => bounds.left + padding + ((value - props.xMinimum) / (props.xMaximum - props.xMinimum)) * (bounds.width - padding * 2);
      const mapY = (value: number) => bounds.top + padding + ((props.yMaximum - value) / (props.yMaximum - props.yMinimum)) * (bounds.height - padding * 2);
      const distanceA = Math.hypot(event.clientX - mapX(pointA.x), event.clientY - mapY(pointA.y));
      const distanceB = Math.hypot(event.clientX - mapX(pointB.x), event.clientY - mapY(pointB.y));
      draggingRef.current = distanceA <= distanceB ? "a" : "b";
      event.currentTarget.setPointerCapture(event.pointerId);
      updatePoint(event);
    };

    return (
      <section className="ra-two-point-lab">
        <header><span>{props.title}</span><strong>{vertical ? `x = ${formatNumber(pointA.x)}` : `y = ${formatNumber(slope, 2)}x ${intercept >= 0 ? "+" : "−"} ${formatNumber(Math.abs(intercept), 2)}`}</strong></header>
        <canvas
          ref={canvasRef}
          style={{ height: `${props.height}px` }}
          role="application"
          aria-label={`${props.title}：拖动 A、B 两点改变直线`}
          data-weibei-control="two-point-line-canvas"
          data-weibei-control-id={props.title}
          onPointerDown={startDragging}
          onPointerMove={updatePoint}
          onPointerUp={() => { draggingRef.current = null; }}
          onPointerCancel={() => { draggingRef.current = null; }}
        />
        <div className="ra-two-point-lab__readout">
          <span><small>Δx</small><strong>{formatNumber(deltaX, 2)}</strong></span>
          <span><small>Δy</small><strong>{formatNumber(deltaY, 2)}</strong></span>
          <span><small>斜率</small><strong>{vertical ? "未定义" : formatNumber(slope, 2)}</strong></span>
        </div>
      </section>
    );
  },
});

export const BalanceExperiment = defineComponent({
  name: "BalanceExperiment",
  description: "把共享扰动变量翻译成两侧粒子数量与正逆过程速率。适合平衡、库存、流入流出等双向系统。",
  props: z.object({
    stateName: z.string(),
    shift: reactive(z.number()),
    title: z.string(),
    leftLabel: z.string(),
    rightLabel: z.string(),
    forwardLabel: z.string(),
    reverseLabel: z.string(),
    caption: z.string(),
  }),
  component: ({ props }) => {
    const shiftField = useStateField(props.stateName, props.shift);
    const shift = Math.max(-1, Math.min(1, numeric(shiftField.value)));
    const leftCount = Math.round(14 + shift * 7);
    const rightCount = 28 - leftCount;
    const forwardRate = 0.55 + Math.max(0, shift) * 0.36 + Math.max(0, -shift) * 0.08;
    const reverseRate = 0.55 + Math.max(0, -shift) * 0.36 + Math.max(0, shift) * 0.08;

    return (
      <section className="ra-balance-experiment">
        <header><span>{props.title}</span><strong>{Math.abs(forwardRate - reverseRate) < 0.04 ? "动态平衡" : forwardRate > reverseRate ? props.forwardLabel : props.reverseLabel}</strong></header>
        <div className="ra-balance-experiment__field">
          <div>
            <span>{props.leftLabel}</span>
            <div>{Array.from({ length: leftCount }, (_, index) => <i key={index} style={{ "--particle-index": index } as React.CSSProperties} />)}</div>
          </div>
          <b aria-hidden="true">⇄</b>
          <div>
            <span>{props.rightLabel}</span>
            <div>{Array.from({ length: rightCount }, (_, index) => <i key={index} style={{ "--particle-index": index } as React.CSSProperties} />)}</div>
          </div>
        </div>
        <div className="ra-balance-experiment__rates">
          <span><small>{props.forwardLabel}</small><i style={{ width: `${forwardRate * 100}%` }} /><strong>{forwardRate.toFixed(2)}</strong></span>
          <span><small>{props.reverseLabel}</small><i style={{ width: `${reverseRate * 100}%` }} /><strong>{reverseRate.toFixed(2)}</strong></span>
        </div>
        <p>{props.caption}</p>
      </section>
    );
  },
});
