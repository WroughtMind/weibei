import { useEffect, useRef } from "react";
import { LineChart } from "echarts/charts";
import {
  GridComponent,
  LegendComponent,
  MarkLineComponent,
  TooltipComponent,
} from "echarts/components";
import * as echarts from "echarts/core";
import type { EChartsCoreOption, EChartsType } from "echarts/core";
import { CanvasRenderer } from "echarts/renderers";
import {
  createLibrary,
  defineComponent,
  reactive,
  useStateField,
  useTriggerAction,
} from "@openuidev/react-lang";
import { z } from "zod/v4";
import {
  ArgumentReader,
  ArgumentUnit,
  BalanceExperiment,
  CausalEvent,
  CausalTrack,
  ChartSeries,
  ExecutionFrame,
  ExecutionTrack,
  LinkedDataChart,
  MetricItem,
  MetricStrip,
  TwoPointLineLab,
} from "./knowledge-components";
import {
  DependencyFlow,
  DependencyNode,
  DistributionBrush,
  FlowAssumption,
  FlowMetric,
  LayeredSpatialView,
  SpatialLayer,
  SpatialPath,
  SpatialPoint,
  SpatialRegion,
} from "./extended-knowledge-components";
import { extendedKnowledgeComponentExamples } from "./extended-knowledge-components.examples";
import { hostEvidenceForID, isEmbeddedRuntime } from "./protocol";
import "./runtime.css";

echarts.use([LineChart, GridComponent, LegendComponent, MarkLineComponent, TooltipComponent, CanvasRenderer]);

function numeric(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function formatNumber(value: number) {
  if (Math.abs(value) < 0.0001) return "0";
  return Number.isInteger(value) ? String(value) : value.toFixed(1).replace(/\.0$/, "");
}

const NarrativeBlock = defineComponent({
  name: "NarrativeBlock",
  description: "只解释视觉块当前状态的短注释。正文结论留在 Agent 回答中，不在界面里重讲。",
  props: z.object({
    title: z.string(),
    text: z.string(),
    tone: z.enum(["mechanism", "diagnosis", "neutral"]),
  }),
  component: ({ props }) => (
    <article className={`ra-narrative ra-narrative--${props.tone}`}>
      <span>{props.title}</span>
      <p>{props.text}</p>
    </article>
  ),
});

const ParameterSlider = defineComponent({
  name: "ParameterSlider",
  description: "连续调节一个数值参数，并把值写回共享的反应变量。",
  props: z.object({
    name: z.string(),
    label: z.string(),
    value: reactive(z.number()),
    minimum: z.number(),
    maximum: z.number(),
    step: z.number(),
    caption: z.string(),
  }),
  component: ({ props }) => {
    const field = useStateField(props.name, props.value);
    const value = numeric(field.value);

    return (
      <label className="ra-slider">
        <span className="ra-slider__topline">
          <span>{props.label}</span>
          <output>{formatNumber(value)}</output>
        </span>
        <input
          aria-label={props.label}
          data-weibei-control="parameter-slider"
          data-weibei-control-id={props.name}
          type="range"
          min={props.minimum}
          max={props.maximum}
          step={props.step}
          value={value}
          onChange={(event) => field.setValue(Number(event.currentTarget.value))}
        />
        <span className="ra-slider__scale">
          <span>{formatNumber(props.minimum)}</span>
          <i style={{ left: `${((0 - props.minimum) / (props.maximum - props.minimum)) * 100}%` }} />
          <span>{formatNumber(props.maximum)}</span>
        </span>
        <small>{props.caption}</small>
      </label>
    );
  },
});

const ParameterReadout = defineComponent({
  name: "ParameterReadout",
  description: "把反应参数翻译成当前可见的数学含义。",
  props: z.object({
    name: z.string(),
    value: reactive(z.number()),
    caption: z.string(),
  }),
  component: ({ props }) => {
    const field = useStateField(props.name, props.value);
    const value = numeric(field.value);
    const direction = value > 0 ? "向上" : value < 0 ? "向下" : "退化为直线";
    const width = Math.abs(value) > 1 ? "更窄" : Math.abs(value) < 1 && value !== 0 ? "更宽" : "基准宽度";

    return (
      <div className="ra-readout" data-sign={value > 0 ? "positive" : value < 0 ? "negative" : "zero"}>
        <div>
          <span>开口</span>
          <strong>{direction}</strong>
        </div>
        <div>
          <span>形状</span>
          <strong>{value === 0 ? "不再是抛物线" : width}</strong>
        </div>
        <p>{props.caption}</p>
      </div>
    );
  },
});

const ValuePicker = defineComponent({
  name: "ValuePicker",
  description: "在少量离散数值中选一个，用于聚焦图表或表格的某个样本。",
  props: z.object({
    name: z.string(),
    label: z.string(),
    value: reactive(z.number()),
    options: z.array(z.number()).min(2).max(8),
    prefix: z.string(),
  }),
  component: ({ props }) => {
    const field = useStateField(props.name, props.value);
    const value = numeric(field.value);

    return (
      <div className="ra-picker">
        <span>{props.label}</span>
        <div role="listbox" aria-label={props.label}>
          {props.options.map((option) => (
            <button
              key={option}
              type="button"
              role="option"
              aria-label={`${props.label}：${props.prefix} ${formatNumber(option)}`}
              data-weibei-control="value-picker-option"
              data-weibei-control-id={`${props.name}-${option}`}
              aria-selected={option === value}
              className={option === value ? "is-active" : ""}
              onClick={() => field.setValue(option)}
            >
              {props.prefix} {formatNumber(option)}
            </button>
          ))}
        </div>
      </div>
    );
  },
});

function useCanvasChart(option: EChartsCoreOption) {
  const elementRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<EChartsType | null>(null);

  useEffect(() => {
    const element = elementRef.current;
    if (!element) return;

    const chart = echarts.init(element, undefined, { renderer: "canvas" });
    chartRef.current = chart;
    const observer = new ResizeObserver(() => chart.resize());
    observer.observe(element);

    return () => {
      observer.disconnect();
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

  return elementRef;
}

const curveColors = ["#8f3f2f", "#c08b48", "#47716b", "#5d6385", "#8d6b7d", "#4e493f"];

const FunctionPlot = defineComponent({
  name: "FunctionPlot",
  description: "由 ECharts Canvas 绘制可探查的函数图像。模型只给函数族、参数和范围，不生成 SVG path。",
  props: z.object({
    title: z.string(),
    family: z.enum(["quadratic"]),
    parameterName: z.string(),
    parameter: reactive(z.number()),
    compareValues: z.array(z.number()).max(8),
    xMinimum: z.number(),
    xMaximum: z.number(),
    height: z.number().int().min(220).max(420),
  }),
  component: ({ props }) => {
    const field = useStateField(props.parameterName, props.parameter);
    const parameter = numeric(field.value, 1);
    const values = props.compareValues.length ? props.compareValues : [parameter];
    const sampleCount = 120;
    const series = values.map((coefficient, index) => {
      const data = Array.from({ length: sampleCount + 1 }, (_, sampleIndex) => {
        const x = props.xMinimum + ((props.xMaximum - props.xMinimum) * sampleIndex) / sampleCount;
        return [Number(x.toFixed(3)), Number((coefficient * x * x).toFixed(3))];
      });
      const active = props.compareValues.length === 0 || Math.abs(coefficient - parameter) < 0.0001;

      return {
        name: `a = ${formatNumber(coefficient)}`,
        type: "line" as const,
        data,
        showSymbol: false,
        animationDuration: 180,
        animationEasing: "cubicOut" as const,
        lineStyle: {
          color: active ? "#8f3f2f" : curveColors[index % curveColors.length],
          opacity: active ? 1 : 0.28,
          width: active ? 3 : 1.5,
        },
        emphasis: { lineStyle: { width: 3, opacity: 1 } },
        z: active ? 4 : 1,
      };
    });
    const option: EChartsCoreOption = {
      animation: true,
      aria: { enabled: true, decal: { show: false } },
      grid: { left: 38, right: 18, top: props.compareValues.length ? 48 : 26, bottom: 34, containLabel: false },
      legend: props.compareValues.length
        ? { top: 4, left: 6, itemWidth: 14, itemHeight: 2, textStyle: { color: "#6d6255", fontSize: 10 } }
        : undefined,
      tooltip: {
        trigger: "axis",
        confine: true,
        backgroundColor: "#332e27",
        borderWidth: 0,
        padding: [7, 9],
        textStyle: { color: "#f7f1e7", fontSize: 11 },
        valueFormatter: (value: unknown) => formatNumber(numeric(Array.isArray(value) ? value[1] : value)),
      },
      xAxis: {
        type: "value",
        min: props.xMinimum,
        max: props.xMaximum,
        axisLine: { show: true, onZero: true, lineStyle: { color: "#776c5e", width: 1 } },
        axisTick: { show: false },
        splitLine: { show: true, lineStyle: { color: "rgba(76, 65, 51, 0.08)" } },
        axisLabel: { color: "#817668", fontSize: 10 },
      },
      yAxis: {
        type: "value",
        scale: true,
        axisLine: { show: true, onZero: true, lineStyle: { color: "#776c5e", width: 1 } },
        axisTick: { show: false },
        splitLine: { show: true, lineStyle: { color: "rgba(76, 65, 51, 0.08)" } },
        axisLabel: { color: "#817668", fontSize: 10 },
      },
      series,
    };
    const chartRef = useCanvasChart(option);

    return (
      <figure className="ra-plot">
        <figcaption>
          <span>{props.title}</span>
          <strong>{props.compareValues.length ? `当前聚焦 a = ${formatNumber(parameter)}` : `a = ${formatNumber(parameter)}`}</strong>
        </figcaption>
        <div
          ref={chartRef}
          role="img"
          aria-label={`${props.title} 函数图，当前参数 ${props.parameterName} = ${formatNumber(parameter)}`}
          data-weibei-control="function-plot"
          data-weibei-control-id={props.parameterName}
          style={{ height: `${props.height}px` }}
        />
        <small>悬停查点值·拖动或选择参数后由 Canvas 重算</small>
      </figure>
    );
  },
});

const ComparisonRow = defineComponent({
  name: "ComparisonRow",
  description: "对比表的一个参数样本。",
  props: z.object({
    label: z.string(),
    coefficient: z.number(),
    direction: z.string(),
    width: z.string(),
    interpretation: z.string(),
  }),
  component: ({ props }) => (
    <tr>
      <th>{props.label}</th>
      <td>{props.direction}</td>
      <td>{props.width}</td>
      <td>{props.interpretation}</td>
    </tr>
  ),
});

const ComparisonTable = defineComponent({
  name: "ComparisonTable",
  description: "将少量样本并排比较，并与反应选择变量联动高亮。",
  props: z.object({
    focusName: z.string(),
    focus: reactive(z.number()),
    rows: z.array(ComparisonRow.ref).min(2).max(8),
  }),
  component: ({ props }) => {
    const field = useStateField(props.focusName, props.focus);
    const focus = numeric(field.value);

    return (
      <div className="ra-table-wrap">
        <table className="ra-comparison">
          <thead>
            <tr>
              <th>样本</th>
              <th>方向</th>
              <th>宽窄</th>
              <th>运算含义</th>
            </tr>
          </thead>
          <tbody>
            {props.rows.map((row) => (
              <tr key={row.props.coefficient} className={Math.abs(row.props.coefficient - focus) < 0.0001 ? "is-active" : ""}>
                <th>{row.props.label}</th>
                <td>{row.props.direction}</td>
                <td>{row.props.width}</td>
                <td>{row.props.interpretation}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  },
});

const EvidenceSnippet = defineComponent({
  name: "EvidenceSnippet",
  description: "把结论绑定到当前学习材料的具体位置，点击可跳回原文。",
  props: z.object({
    evidenceID: z.string(),
    locator: z.string(),
    quote: z.string(),
    relation: z.string(),
  }),
  component: ({ props }) => {
    const hostEvidence = hostEvidenceForID(props.evidenceID);
    return (
      <button
        className="ra-evidence"
        type="button"
        aria-label={`回到来源：${hostEvidence?.sourceLabel ?? props.locator}`}
        data-weibei-control="evidence-snippet"
        data-weibei-control-id={props.evidenceID}
        onClick={() => window.dispatchEvent(new CustomEvent("weibei:evidence", { detail: { evidenceID: props.evidenceID } }))}
      >
        <span className="ra-evidence__mark">{String.fromCharCode(0x301d)}</span>
        <span>
          <strong>{hostEvidence?.sourceLabel ?? props.locator}</strong>
          <q>{hostEvidence?.excerpt ?? props.quote}{hostEvidence?.isTruncated ? "…" : ""}</q>
          <small>{props.relation}</small>
        </span>
        <i aria-hidden="true">回原文</i>
      </button>
    );
  },
});

const ReasonStep = defineComponent({
  name: "ReasonStep",
  description: "机制推导的一步，只写本步转换和原因。",
  props: z.object({
    title: z.string(),
    explanation: z.string(),
  }),
  component: ({ props }) => (
    <article className="ra-reason-step">
      <strong>{props.title}</strong>
      <p>{props.explanation}</p>
    </article>
  ),
});

const ProcessStepper = defineComponent({
  name: "ProcessStepper",
  description: "用离散步骤控制反应推导的当前焦点。",
  props: z.object({
    stateName: z.string(),
    activeStep: reactive(z.number()),
    steps: z.array(ReasonStep.ref).min(2).max(7),
  }),
  component: ({ props }) => {
    const field = useStateField(props.stateName, props.activeStep);
    const activeIndex = Math.max(0, Math.min(props.steps.length - 1, Math.round(numeric(field.value))));
    const active = props.steps[activeIndex]!;

    return (
      <div className="ra-stepper">
        <div className="ra-stepper__rail" role="tablist" aria-label="推导步骤">
          {props.steps.map((step, index) => (
            <button
              key={`${step.props.title}-${index}`}
              type="button"
              role="tab"
              aria-label={`推导步骤 ${index + 1}：${step.props.title}`}
              data-weibei-control="process-step"
              data-weibei-control-id={`${props.stateName}-${index}`}
              aria-selected={index === activeIndex}
              className={index === activeIndex ? "is-active" : index < activeIndex ? "is-complete" : ""}
              onClick={() => field.setValue(index)}
            >
              <span>{index + 1}</span>
              <strong>{step.props.title}</strong>
            </button>
          ))}
        </div>
        <article className="ra-stepper__detail">
          <span>0{activeIndex + 1}</span>
          <div>
            <strong>{active.props.title}</strong>
            <p>{active.props.explanation}</p>
          </div>
        </article>
      </div>
    );
  },
});

const QuadraticMechanism = defineComponent({
  name: "QuadraticMechanism",
  description: "用 HTML/CSS 对象演示 x 到 x² 再到 ax² 的运算变换，不由模型绘图。",
  props: z.object({
    stateName: z.string(),
    activeStep: reactive(z.number()),
    coefficient: z.number(),
  }),
  component: ({ props }) => {
    const field = useStateField(props.stateName, props.activeStep);
    const activeIndex = Math.max(0, Math.min(3, Math.round(numeric(field.value))));
    const x = -2;
    const squared = x * x;
    const result = props.coefficient * squared;
    const stages = [
      { label: "输入", value: `x = ${x}`, detail: "原点左侧" },
      { label: "平方", value: `x² = ${squared}`, detail: "符号消失" },
      { label: "缩放 / 翻转", value: `× ${formatNumber(props.coefficient)}`, detail: props.coefficient < 0 ? "翻到轴下" : "保持轴上" },
      { label: "输出", value: `y = ${formatNumber(result)}`, detail: "图像上的点" },
    ];

    return (
      <div className="ra-mechanism">
        <div className="ra-mechanism__formula">
          <span>y</span>
          <i>=</i>
          <strong>{formatNumber(props.coefficient)}</strong>
          <span>x²</span>
        </div>
        <div className="ra-mechanism__track">
          {stages.map((stage, index) => (
            <div key={stage.label} className={index === activeIndex ? "is-active" : index < activeIndex ? "is-complete" : ""}>
              <span>{stage.label}</span>
              <strong>{stage.value}</strong>
              <small>{stage.detail}</small>
            </div>
          ))}
        </div>
        <div className="ra-mechanism__area" aria-label="平方与缩放的面积示意">
          <div className={activeIndex >= 1 ? "is-visible" : ""}>
            {Array.from({ length: 16 }, (_, index) => <i key={index} />)}
          </div>
          <span className={activeIndex >= 2 ? "is-visible" : ""} style={{ transform: `scaleY(${Math.min(1.45, Math.max(0.45, Math.abs(props.coefficient)))})` }} />
          <small>{activeIndex < 1 ? "先选定 x" : activeIndex < 2 ? "x² 可看作正方形面积" : `${props.coefficient < 0 ? "向下翻转" : "向上保留"}，高度 × ${formatNumber(Math.abs(props.coefficient))}`}</small>
        </div>
      </div>
    );
  },
});

const FollowUpAction = defineComponent({
  name: "FollowUpAction",
  description: "把有明确学习目的的后续问题送回 Agent，不伪装成本地按钮。",
  props: z.object({
    label: z.string(),
    userMessage: z.string(),
  }),
  component: ({ props }) => {
    const triggerAction = useTriggerAction();
    return (
      <button
        className="ra-followup"
        type="button"
        aria-label={`继续追问：${props.label}`}
        data-weibei-control="follow-up"
        data-weibei-control-id={props.label}
        onClick={() => triggerAction(props.userMessage)}
      >
        <span>{props.label}</span>
        <i aria-hidden="true">继续 →</i>
      </button>
    );
  },
});

const learningBlock = z.union([
  NarrativeBlock.ref,
  ParameterSlider.ref,
  ParameterReadout.ref,
  ValuePicker.ref,
  FunctionPlot.ref,
  ComparisonTable.ref,
  EvidenceSnippet.ref,
  ProcessStepper.ref,
  QuadraticMechanism.ref,
  FollowUpAction.ref,
  LinkedDataChart.ref,
  MetricStrip.ref,
  ExecutionTrack.ref,
  ArgumentReader.ref,
  CausalTrack.ref,
  TwoPointLineLab.ref,
  BalanceExperiment.ref,
  LayeredSpatialView.ref,
  DistributionBrush.ref,
  DependencyFlow.ref,
]);

const LearningStage = defineComponent({
  name: "LearningStage",
  description: "在回答中组织一个有明确角色的学习区域，可装载控制、可视化、解释或证据。",
  props: z.object({
    role: z.enum(["controls", "visual", "explanation", "evidence", "full"]),
    title: z.string().nullable(),
    children: z.array(learningBlock).min(1).max(6),
  }),
  component: ({ props, renderNode }) => (
    <section className="ra-stage" data-role={props.role}>
      {props.title ? <h3>{props.title}</h3> : null}
      <div className="ra-stage__content">{renderNode(props.children)}</div>
    </section>
  ),
});

const RichAnswerRoot = defineComponent({
  name: "RichAnswerRoot",
  description: "魏碑回答流内生成式视觉块的唯一根组件。标题信息仅用于独立预览与无障碍标注，嵌入 Agent 时不显示第二套回答标题。",
  props: z.object({
    eyebrow: z.string(),
    title: z.string(),
    summary: z.string(),
    layout: z.enum(["workbench", "comparison", "reasoning", "flow", "document", "timeline", "track"]),
    stages: z.array(LearningStage.ref).min(1).max(8),
  }),
  component: ({ props, renderNode }) => {
    const embedded = isEmbeddedRuntime();
    return (
      <figure
        className={`ra-root ra-root--${props.layout}`}
        aria-label={embedded ? props.title : undefined}
      >
        {!embedded ? (
          <header className="ra-root__header">
            <span>{props.eyebrow}</span>
            <h1>{props.title}</h1>
            <p>{props.summary}</p>
          </header>
        ) : null}
        <div className="ra-root__body">{renderNode(props.stages)}</div>
      </figure>
    );
  },
});

export const weiBeiGenerativeLibrary = createLibrary({
  root: "RichAnswerRoot",
  components: [
    RichAnswerRoot,
    LearningStage,
    NarrativeBlock,
    ParameterSlider,
    ParameterReadout,
    ValuePicker,
    FunctionPlot,
    ComparisonRow,
    ComparisonTable,
    EvidenceSnippet,
    ReasonStep,
    ProcessStepper,
    QuadraticMechanism,
    FollowUpAction,
    ChartSeries,
    LinkedDataChart,
    MetricItem,
    MetricStrip,
    ExecutionFrame,
    ExecutionTrack,
    ArgumentUnit,
    ArgumentReader,
    CausalEvent,
    CausalTrack,
    TwoPointLineLab,
    BalanceExperiment,
    SpatialLayer,
    SpatialRegion,
    SpatialPath,
    SpatialPoint,
    LayeredSpatialView,
    DistributionBrush,
    FlowAssumption,
    DependencyNode,
    FlowMetric,
    DependencyFlow,
  ],
  componentGroups: [
    {
      name: "布局",
      components: ["RichAnswerRoot", "LearningStage"],
      notes: ["根组件只用 RichAnswerRoot。", "它是回答中的生成式视觉体验，不是第二篇回答；不要为了像网页而凑区域。"],
    },
    {
      name: "解释与证据",
      components: ["NarrativeBlock", "EvidenceSnippet", "FollowUpAction"],
      notes: ["NarrativeBlock 只写随当前互动状态有意义的局部读数或诊断。", "正文已经说过的标题、摘要和结论不得在图件中重复。"],
    },
    {
      name: "参数与数学",
      components: ["ParameterSlider", "ParameterReadout", "ValuePicker", "FunctionPlot", "ComparisonRow", "ComparisonTable"],
      notes: ["FunctionPlot 使用 Canvas，不接受 SVG 路径。", "只在用户需要实验、对比或诊断时使用。"],
    },
    {
      name: "过程理解",
      components: ["ReasonStep", "ProcessStepper", "QuadraticMechanism", "ExecutionFrame", "ExecutionTrack"],
      notes: ["步骤要表达真实转换，不把段落硬切成时间线。", "ExecutionFrame 由模型提供真实状态，不运行模型代码。"],
    },
    {
      name: "数据与读数",
      components: ["ChartSeries", "LinkedDataChart", "MetricItem", "MetricStrip"],
      notes: ["图表序列由当前材料或可核验计算提供。", "点击图表只改变本地聚焦状态。"],
    },
    {
      name: "原文与因果",
      components: ["ArgumentUnit", "ArgumentReader", "CausalEvent", "CausalTrack"],
      notes: ["原句、论证角色和 evidenceID 必须成组出现。", "只有先后关系时使用 insufficient，不伪造因果边。"],
    },
    {
      name: "直接实验",
      components: ["TwoPointLineLab", "BalanceExperiment"],
      notes: ["这些是可复用的知识机制，不是整套固定学科页面。", "模型仍需自行组合控制、解释和证据。"],
    },
    {
      name: "空间、分布与传导",
      components: ["SpatialLayer", "SpatialRegion", "SpatialPath", "SpatialPoint", "LayeredSpatialView", "DistributionBrush", "FlowAssumption", "DependencyNode", "FlowMetric", "DependencyFlow"],
      notes: [
        "空间组件只接受 0 到 1 的归一化区域、路径和点位，不接受 SVG path 或像素坐标。",
        "分布组件只接受总体数值与样本窗口状态；统计量由本地组件计算。",
        "依赖传导只接受输入范围、受限运算节点和结果引用；不得传入代码或任意表达式。",
      ],
    },
  ],
});

export const weiBeiGenerativePrompt = weiBeiGenerativeLibrary.prompt({
  preamble: "你是魏碑学习 Agent 的界面规划器。只在互动或可视化明显比文字更能帮助学习时输出 OpenUI Lang。",
  additionalRules: [
    "模型输出组件树、数据、反应状态和动作；不输出 SVG path。",
    "模型不得输出 HTML、CSS、像素布局或可执行计算代码；空间位置只能使用组件要求的 0 到 1 归一化坐标。",
    "Agent 正文负责回答问题；OpenUI 是回答流内的生成式视觉体验，不得从头再回答一次。",
    "嵌入视觉块不得重复正文标题、摘要、结论或证据原文，只保留理解和操作当前体验所需的标签、读数、控件与局部反馈。",
    "每个界面要围绕一个可验证的学习动作，不得只改文字排版。",
    "围绕一个主要学习目标按需组合多个视觉、控件、读数与步骤；不要为了简洁牺牲真正有帮助的互动，也不要为了丰富拼成网页。",
    "优先使用一个主视觉或主互动，不把每条内容都做成卡片。",
    "证据必须绑定当前材料的 evidenceID 和 locator。",
    "示例场景只用于理解组件能力，禁止把示例标题、数据或整套结构当作模板复用。",
    "先选择知识对象，再从不同组件组组合；不得调用一个包办标题、数据、互动和结论的整场景组件。",
    "LayeredSpatialView、DistributionBrush 和 DependencyFlow 是跨学科深组件；只在空间关系、抽样偏差或逐层传导确实是问题核心时使用。",
  ],
  examples: generatedExamples(),
});

function generatedExamples() {
  return [
    `$value = 1\nroot = RichAnswerRoot("数学", "改变参数", "用一次操作验证结论。", "flow", [stage])\nstage = LearningStage("controls", "", [slider])\nslider = ParameterSlider("value", "参数", $value, -2, 2, 0.1, "观察变化。")`,
    `$focus = 0\nroot = RichAnswerRoot("数据", "点击年份查看联动读数", "横轴、序列和解释都来自当前材料。", "flow", [visual])\nvisual = LearningStage("visual", "", [chart])\nseries = ChartSeries("指标", "line", [12, 18, 15], "点", "jade")\nchart = LinkedDataChart("focus", $focus, "三期变化", ["第一期", "第二期", "第三期"], [series], "点击任意数据点聚焦。", 240)`,
    `$step = 0\nroot = RichAnswerRoot("代码", "逐步查看变量状态", "AI 提供真实执行帧，组件只负责前后步进。", "track", [visual])\nvisual = LearningStage("visual", "", [track])\nf1 = ExecutionFrame("初始化", 0, ["3", "1"], [], "读取输入。")\nf2 = ExecutionFrame("交换", 1, ["1", "3"], [0, 1], "左值更大，因此交换。")\ntrack = ExecutionTrack("step", $step, "执行轨道", ["values = [3, 1]", "swap(values, 0, 1)"], [f1, f2])`,
    ...Object.values(extendedKnowledgeComponentExamples),
  ];
}
