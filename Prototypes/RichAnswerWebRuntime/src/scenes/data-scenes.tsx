import { useEffect, useMemo, useRef, useState } from "react";
import type { PointerEvent as ReactPointerEvent } from "react";
import type { LearningSceneProps } from "../types";
import { EvidenceButton, InlineReadout, LearningSurface, clamp } from "../shared";
import "./data-scenes.css";

const population = [
  21, 24, 26, 28, 29, 31, 32, 33, 34, 34, 35, 36, 36, 37, 38, 38, 39, 40, 40, 41, 42, 43, 43, 44, 45, 46, 47, 49,
  51, 54, 58, 67,
];

export function StatisticsSamplingScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [brush, setBrush] = useState<[number, number]>([0.18, 0.7]);
  const dragOrigin = useRef<number | null>(null);
  const minimum = Math.min(...population);
  const maximum = Math.max(...population);
  const range = maximum - minimum;
  const selected = population.filter((value) => {
    const ratio = (value - minimum) / range;
    return ratio >= Math.min(...brush) && ratio <= Math.max(...brush);
  });
  const overallMean = mean(population);
  const selectedMean = mean(selected);
  const selectedMedian = median(selected);

  const updateBrush = (event: ReactPointerEvent<SVGSVGElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    const ratio = clamp((event.clientX - bounds.left) / bounds.width, 0, 1);
    if (dragOrigin.current === null) {
      dragOrigin.current = ratio;
      event.currentTarget.setPointerCapture(event.pointerId);
    }
    setBrush([dragOrigin.current, ratio]);
  };

  const stacks = new Map<number, number>();

  return (
    <LearningSurface
      eyebrow="统计 · 刷选抽样窗"
      title={title}
      prompt={prompt}
      accent="#3f6870"
      footer={<EvidenceButton evidenceID="stats-source-1" label="回到总体样本表" onEvidence={onEvidence} />}
    >
      <div className="stats-scene">
        <div className="stats-instruction">在分布上直接拖出一个样本窗，观察“样本看起来像总体”这件事有多不稳定。</div>
        <svg
          className="stats-plot"
          viewBox="0 0 640 238"
          role="img"
          aria-label="总体分布与刷选样本"
          onPointerDown={updateBrush}
          onPointerMove={(event) => dragOrigin.current !== null && updateBrush(event)}
          onPointerUp={(event) => {
            dragOrigin.current = null;
            event.currentTarget.releasePointerCapture(event.pointerId);
          }}
          onPointerCancel={() => {
            dragOrigin.current = null;
          }}
        >
          <line x1="34" y1="198" x2="608" y2="198" className="stats-axis" />
          {[0, 0.25, 0.5, 0.75, 1].map((ratio) => (
            <g key={ratio}>
              <line x1={34 + ratio * 574} y1="38" x2={34 + ratio * 574} y2="205" className="stats-grid" />
              <text x={34 + ratio * 574} y="224" textAnchor="middle" className="stats-tick">
                {Math.round(minimum + ratio * range)}
              </text>
            </g>
          ))}
          <rect
            x={34 + Math.min(...brush) * 574}
            y="26"
            width={Math.max(4, Math.abs(brush[1] - brush[0]) * 574)}
            height="172"
            className="stats-brush"
          />
          {population.map((value, index) => {
            const bin = Math.round(value / 2) * 2;
            const level = stacks.get(bin) ?? 0;
            stacks.set(bin, level + 1);
            const ratio = (value - minimum) / range;
            const inSample = ratio >= Math.min(...brush) && ratio <= Math.max(...brush);
            return (
              <circle
                key={`${value}-${index}`}
                cx={34 + ratio * 574}
                cy={188 - level * 17}
                r={inSample ? 6.2 : 4.8}
                className={inSample ? "stats-dot is-sampled" : "stats-dot"}
              />
            );
          })}
          <line
            x1={34 + ((overallMean - minimum) / range) * 574}
            y1="40"
            x2={34 + ((overallMean - minimum) / range) * 574}
            y2="198"
            className="stats-mean overall"
          />
          {selected.length > 0 ? (
            <line
              x1={34 + ((selectedMean - minimum) / range) * 574}
              y1="55"
              x2={34 + ((selectedMean - minimum) / range) * 574}
              y2="198"
              className="stats-mean sample"
            />
          ) : null}
        </svg>
        <div className="stats-readout-line">
          <InlineReadout label="总体均值" value={overallMean.toFixed(1)} detail="墨色虚线" />
          <InlineReadout label="样本均值" value={selected.length ? selectedMean.toFixed(1) : "—"} detail="青色实线" />
          <InlineReadout label="样本中位数" value={selected.length ? selectedMedian.toFixed(1) : "—"} detail={`${selected.length} 个观测`} />
          <p>
            {selected.length < 5
              ? "样本太窄：少量点会让均值剧烈摆动。"
              : Math.abs(selectedMean - overallMean) > 4
                ? "这个样本窗明显偏向总体的一侧，样本均值正在误导你。"
                : "当前样本较接近总体，但换一个窗口，结论仍可能改变。"}
          </p>
        </div>
      </div>
    </LearningSurface>
  );
}

type AssumptionKey = "growth" | "margin" | "discount";

export function FinanceCashflowScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [assumptions, setAssumptions] = useState({ growth: 8, margin: 18, discount: 11 });
  const [active, setActive] = useState<AssumptionKey>("growth");
  const model = useMemo(() => buildCashflowModel(assumptions), [assumptions]);
  const maximumFlow = Math.max(...model.years.map((year) => year.cashflow));

  const update = (key: AssumptionKey, raw: string) => {
    const limits: Record<AssumptionKey, [number, number]> = {
      growth: [-5, 18],
      margin: [4, 35],
      discount: [5, 24],
    };
    const value = clamp(Number(raw), ...limits[key]);
    setActive(key);
    setAssumptions((current) => ({ ...current, [key]: Number.isFinite(value) ? value : current[key] }));
  };

  return (
    <LearningSurface
      eyebrow="金融 · 假设传导模型"
      title={title}
      prompt={prompt}
      accent="#596c43"
      footer={<EvidenceButton evidenceID="finance-source-1" label="回到财报假设来源" onEvidence={onEvidence} />}
    >
      <div className="finance-scene">
        <div className="finance-assumptions" aria-label="可编辑模型假设">
          <p>直接改模型单元格，不需要“应用”按钮。</p>
          {(
            [
              ["growth", "收入增长", "%"],
              ["margin", "自由现金流率", "%"],
              ["discount", "折现率", "%"],
            ] as const
          ).map(([key, label, unit]) => (
            <label key={key} className={active === key ? "is-active" : ""}>
              <span>{label}</span>
              <input
                type="number"
                value={assumptions[key]}
                step="1"
                onFocus={() => setActive(key)}
                onChange={(event) => update(key, event.target.value)}
              />
              <b>{unit}</b>
            </label>
          ))}
          <div className="finance-path">
            <span>本次变化路径</span>
            <strong>{assumptionPath(active)}</strong>
          </div>
        </div>
        <div className="finance-flow">
          <div className="finance-flow__headline">
            <span>五年折现现金流</span>
            <strong>估值 {model.valuation.toFixed(0)} 百万</strong>
          </div>
          <div className="finance-waterfall">
            {model.years.map((year) => (
              <div className="finance-year" key={year.year}>
                <div className="finance-year__bar" style={{ height: `${42 + (year.cashflow / maximumFlow) * 118}px` }}>
                  <i style={{ height: `${(year.presentValue / year.cashflow) * 100}%` }} />
                  <span>{year.cashflow.toFixed(1)}</span>
                </div>
                <b>Y{year.year}</b>
                <small>PV {year.presentValue.toFixed(1)}</small>
              </div>
            ))}
          </div>
          <div className="finance-ledger-line">
            <InlineReadout label="终值现值" value={model.terminalPresentValue.toFixed(0)} detail="百万" />
            <InlineReadout label="现金流现值" value={model.cashflowPresentValue.toFixed(0)} detail="百万" />
            <p>{model.explanation}</p>
          </div>
        </div>
      </div>
    </LearningSurface>
  );
}

const policyEvents = [
  { id: "supply", date: "Q1", title: "供给受阻", kind: "前置条件", strength: "可确认", index: 101, note: "成本先于政策上升。" },
  { id: "prices", date: "Q2", title: "价格扩散", kind: "观察结果", strength: "可确认", index: 108, note: "核心价格也开始抬升。" },
  { id: "guidance", date: "Q3", title: "政策转向", kind: "政策信号", strength: "有争议", index: 112, note: "市场预期先于工具落地改变。" },
  { id: "tighten", date: "Q4", title: "利率上调", kind: "直接机制", strength: "可确认", index: 109, note: "融资成本上升，信用扩张放缓。" },
  { id: "demand", date: "Q5", title: "需求降温", kind: "滞后结果", strength: "部分证据", index: 104, note: "住房与耐用品先出现回落。" },
  { id: "cool", date: "Q6", title: "通胀回落", kind: "长期结果", strength: "因果不足", index: 99, note: "政策与供给修复共同作用，不能全归因。" },
];

export function EconomicsPolicyScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [selectedID, setSelectedID] = useState("tighten");
  const selectedIndex = policyEvents.findIndex((event) => event.id === selectedID);
  const selected = policyEvents[selectedIndex] ?? policyEvents[0]!;
  const points = policyEvents.map((event, index) => `${42 + index * 104},${154 - (event.index - 96) * 6}`).join(" ");

  return (
    <LearningSurface
      eyebrow="经济 · 证据因果路径"
      title={title}
      prompt={prompt}
      accent="#9a5a36"
      footer={<EvidenceButton evidenceID={`policy-${selected.id}`} label={`回到“${selected.title}”材料`} onEvidence={onEvidence} />}
    >
      <div className="policy-scene">
        <div className="policy-river" role="list" aria-label="政策事件证据时间线">
          {policyEvents.map((event, index) => (
            <button
              key={event.id}
              type="button"
              role="listitem"
              className={event.id === selectedID ? "is-selected" : index < selectedIndex ? "is-before" : ""}
              onClick={() => setSelectedID(event.id)}
            >
              <span>{event.date}</span>
              <strong>{event.title}</strong>
              <small>{event.kind}</small>
            </button>
          ))}
        </div>
        <div className="policy-analysis">
          <svg viewBox="0 0 580 184" role="img" aria-label="指标随事件变化">
            <line x1="30" y1="154" x2="560" y2="154" className="policy-axis" />
            <polyline points={points} className="policy-indicator" />
            {policyEvents.map((event, index) => (
              <g key={event.id} className={event.id === selectedID ? "is-selected" : ""}>
                <line x1={42 + index * 104} y1="34" x2={42 + index * 104} y2="160" className="policy-guide" />
                <circle cx={42 + index * 104} cy={154 - (event.index - 96) * 6} r={event.id === selectedID ? 7 : 4} />
              </g>
            ))}
          </svg>
          <div className="policy-evidence-rail">
            <span>{selected.kind}</span>
            <strong>{selected.title}</strong>
            <p>{selected.note}</p>
            <b data-strength={selected.strength}>{selected.strength}</b>
          </div>
        </div>
        <p className="policy-caveat">
          这里把“先发生”和“能证明因果”分开：选中任何节点，只高亮它能支持的路径；证据不足不会被自动补成影响评分。
        </p>
      </div>
    </LearningSurface>
  );
}

interface SortFrame {
  values: number[];
  line: number;
  pair: [number, number] | null;
  iteration: number;
  message: string;
  swapped: boolean;
}

const sortCode = [
  "for end from n - 1 down to 1",
  "  for i from 0 to end - 1",
  "    if a[i] > a[i + 1]",
  "      swap(a[i], a[i + 1])",
  "return a",
];

export function CodeSortScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const frames = useMemo(() => buildBubbleSortFrames([7, 3, 5, 2, 6]), []);
  const [step, setStep] = useState(0);
  const frame = frames[step]!;
  const next = () => setStep((current) => Math.min(frames.length - 1, current + 1));
  const previous = () => setStep((current) => Math.max(0, current - 1));

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "ArrowRight") next();
      if (event.key === "ArrowLeft") previous();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [frames.length]);

  return (
    <LearningSurface
      eyebrow="代码 · 状态执行轨道"
      title={title}
      prompt={prompt}
      accent="#6a5680"
      footer={<EvidenceButton evidenceID="code-source-1" label="回到算法题与输入" onEvidence={onEvidence} />}
    >
      <div className="code-scene">
        <div className="code-list" aria-label="冒泡排序代码">
          {sortCode.map((line, index) => (
            <pre key={line} className={frame.line === index ? "is-current" : ""}>
              <span>{index + 1}</span>
              <code>{line}</code>
            </pre>
          ))}
        </div>
        <div className="code-execution">
          <div className="array-track" aria-label="数组状态">
            {frame.values.map((value, index) => {
              const active = frame.pair?.includes(index);
              return (
                <div key={`${index}-${value}`} className={active ? (frame.swapped ? "is-swapped" : "is-compared") : ""}>
                  <i style={{ height: `${34 + value * 16}px` }} />
                  <strong>{value}</strong>
                  <span>a[{index}]</span>
                </div>
              );
            })}
          </div>
          <div className="execution-message">
            <span>第 {frame.iteration} 轮 · 步骤 {step + 1}/{frames.length}</span>
            <strong>{frame.message}</strong>
          </div>
          <div className="execution-controls">
            <button type="button" onClick={previous} disabled={step === 0}>上一步</button>
            <div className="execution-progress"><i style={{ width: `${((step + 1) / frames.length) * 100}%` }} /></div>
            <button type="button" onClick={next} disabled={step === frames.length - 1}>下一步</button>
          </div>
          <small className="keyboard-hint">也可以用键盘 ← → 回看变量状态。</small>
        </div>
      </div>
    </LearningSurface>
  );
}

function mean(values: number[]) {
  return values.length ? values.reduce((total, value) => total + value, 0) / values.length : 0;
}

function median(values: number[]) {
  if (!values.length) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle]! : (sorted[middle - 1]! + sorted[middle]!) / 2;
}

function buildCashflowModel(assumptions: { growth: number; margin: number; discount: number }) {
  const growth = assumptions.growth / 100;
  const margin = assumptions.margin / 100;
  const discount = assumptions.discount / 100;
  let revenue = 120;
  const years = Array.from({ length: 5 }, (_, index) => {
    revenue *= 1 + growth;
    const cashflow = revenue * margin;
    const presentValue = cashflow / (1 + discount) ** (index + 1);
    return { year: index + 1, revenue, cashflow, presentValue };
  });
  const safeSpread = Math.max(0.015, discount - Math.min(growth, discount - 0.015));
  const terminalValue = (years[4]!.cashflow * (1 + Math.min(growth, discount - 0.015))) / safeSpread;
  const terminalPresentValue = terminalValue / (1 + discount) ** 5;
  const cashflowPresentValue = years.reduce((total, year) => total + year.presentValue, 0);
  const valuation = cashflowPresentValue + terminalPresentValue;
  const explanation =
    assumptions.discount <= assumptions.growth
      ? "增长率接近或超过折现率，终值会失真；模型已收紧长期增长假设。"
      : `终值占估值 ${Math.round((terminalPresentValue / valuation) * 100)}%，说明结果对长期假设很敏感。`;
  return { years, terminalPresentValue, cashflowPresentValue, valuation, explanation };
}

function assumptionPath(key: AssumptionKey) {
  switch (key) {
    case "growth":
      return "收入增长 → 各期收入 → 自由现金流 → 终值";
    case "margin":
      return "现金流率 → 每期现金流 → 终值 → 估值";
    case "discount":
      return "折现率 → 每期现值 + 终值现值 → 估值";
  }
}

function buildBubbleSortFrames(initial: number[]) {
  const values = [...initial];
  const frames: SortFrame[] = [
    { values: [...values], line: 0, pair: null, iteration: 0, message: "准备从右向左缩短未排序区间。", swapped: false },
  ];
  for (let end = values.length - 1; end > 0; end -= 1) {
    for (let index = 0; index < end; index += 1) {
      const left = values[index]!;
      const right = values[index + 1]!;
      frames.push({
        values: [...values],
        line: 2,
        pair: [index, index + 1],
        iteration: values.length - end,
        message: `比较 ${left} 和 ${right}。`,
        swapped: false,
      });
      if (left > right) {
        values[index] = right;
        values[index + 1] = left;
        frames.push({
          values: [...values],
          line: 3,
          pair: [index, index + 1],
          iteration: values.length - end,
          message: "左值更大，交换后较大值向右沉底。",
          swapped: true,
        });
      }
    }
  }
  frames.push({ values: [...values], line: 4, pair: null, iteration: values.length - 1, message: "未排序区间归零，返回结果。", swapped: false });
  return frames;
}
