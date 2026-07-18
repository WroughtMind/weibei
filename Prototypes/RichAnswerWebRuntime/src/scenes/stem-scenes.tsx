import React, { useMemo, useRef, useState } from "react";
import type { CSSProperties, DragEvent, PointerEvent as ReactPointerEvent } from "react";
import type { LearningSceneProps } from "../types";
import { LearningSurface, EvidenceButton, InlineReadout, clamp } from "../shared";
import "./stem-scenes.css";

type Point = { x: number; y: number };
type DragHandle = "a" | "b" | null;
type ForceVector = { x: number; y: number };
type PerturbationKey = "add-reactant" | "add-product" | "heat" | "compress";
type StageKey = "pair" | "cross" | "divide-one" | "divide-two";

const MATH_W = 620;
const MATH_H = 360;
const MATH_PAD = 34;
const PHYSICS_W = 620;
const PHYSICS_H = 330;
const FORCE_SCALE = 4.6;
const CHART_W = 560;
const CHART_H = 170;

function mapMathToSvg(point: Point) {
  return {
    x: MATH_PAD + ((point.x + 5) / 10) * (MATH_W - MATH_PAD * 2),
    y: MATH_PAD + ((4 - point.y) / 8) * (MATH_H - MATH_PAD * 2),
  };
}

function mapSvgToMath(svgX: number, svgY: number): Point {
  return {
    x: clamp(((svgX - MATH_PAD) / (MATH_W - MATH_PAD * 2)) * 10 - 5, -5, 5),
    y: clamp(4 - ((svgY - MATH_PAD) / (MATH_H - MATH_PAD * 2)) * 8, -4, 4),
  };
}

function getSvgPoint(svg: SVGSVGElement, event: ReactPointerEvent<SVGElement>) {
  const rect = svg.getBoundingClientRect();
  return {
    x: ((event.clientX - rect.left) / rect.width) * MATH_W,
    y: ((event.clientY - rect.top) / rect.height) * MATH_H,
  };
}

function formatNumber(value: number, digits = 2) {
  if (!Number.isFinite(value)) return "未定义";
  const fixed = value.toFixed(digits);
  return fixed.replace(/\.00$/, "").replace(/(\.\d)0$/, "$1");
}

function classNames(...names: Array<string | false | null | undefined>) {
  return names.filter(Boolean).join(" ");
}

export function MathLineScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const svgRef = useRef<SVGSVGElement>(null);
  const [pointA, setPointA] = useState<Point>({ x: -3.4, y: -1.5 });
  const [pointB, setPointB] = useState<Point>({ x: 2.8, y: 2.2 });
  const [dragging, setDragging] = useState<DragHandle>(null);

  const derived = useMemo(() => {
    const dx = pointB.x - pointA.x;
    const dy = pointB.y - pointA.y;
    const vertical = Math.abs(dx) < 0.08;
    const slope = vertical ? Number.POSITIVE_INFINITY : dy / dx;
    const intercept = vertical ? Number.NaN : pointA.y - slope * pointA.x;
    const samples = [-4, -2, 0, 2, 4].map((x) => ({ x, y: vertical ? Number.NaN : slope * x + intercept }));
    const svgA = mapMathToSvg(pointA);
    const svgB = mapMathToSvg(pointB);
    const triangleBase = mapMathToSvg({ x: pointB.x, y: pointA.y });
    const lineStart = vertical ? { x: pointA.x, y: -4 } : { x: -5, y: slope * -5 + intercept };
    const lineEnd = vertical ? { x: pointA.x, y: 4 } : { x: 5, y: slope * 5 + intercept };
    return { dx, dy, vertical, slope, intercept, samples, svgA, svgB, triangleBase, lineStart, lineEnd };
  }, [pointA, pointB]);

  function updatePoint(handle: DragHandle, event: ReactPointerEvent<SVGElement>) {
    if (!handle || !svgRef.current) return;
    const svgPoint = getSvgPoint(svgRef.current, event);
    const next = mapSvgToMath(svgPoint.x, svgPoint.y);
    if (handle === "a") setPointA(next);
    if (handle === "b") setPointB(next);
  }

  function onPointerDown(handle: Exclude<DragHandle, null>, event: ReactPointerEvent<SVGElement>) {
    event.currentTarget.setPointerCapture(event.pointerId);
    setDragging(handle);
    updatePoint(handle, event);
  }

  const lineSvgStart = mapMathToSvg(derived.lineStart);
  const lineSvgEnd = mapMathToSvg(derived.lineEnd);
  const slopeLabel = derived.vertical ? "斜率未定义" : `斜率 ${formatNumber(derived.slope)}`;

  return (
    <LearningSurface
      eyebrow="数学"
      title={title}
      prompt={prompt}
      accent="#266f86"
      footer={<EvidenceButton evidenceID="stem.math.line-slope" label="查看两点式依据" onEvidence={onEvidence} />}
    >
      <div className="stem-scene math-line-scene">
        <div className="stem-canvas math-canvas" aria-label="拖动两点生成直线">
          <svg
            ref={svgRef}
            viewBox={`0 0 ${MATH_W} ${MATH_H}`}
            role="img"
            onPointerMove={(event) => updatePoint(dragging, event)}
            onPointerUp={() => setDragging(null)}
            onPointerCancel={() => setDragging(null)}
          >
            <g className="math-grid">
              {Array.from({ length: 11 }).map((_, index) => {
                const x = MATH_PAD + (index / 10) * (MATH_W - MATH_PAD * 2);
                return <line key={`v-${index}`} x1={x} y1={MATH_PAD} x2={x} y2={MATH_H - MATH_PAD} />;
              })}
              {Array.from({ length: 9 }).map((_, index) => {
                const y = MATH_PAD + (index / 8) * (MATH_H - MATH_PAD * 2);
                return <line key={`h-${index}`} x1={MATH_PAD} y1={y} x2={MATH_W - MATH_PAD} y2={y} />;
              })}
            </g>
            <line className="math-axis" x1={MATH_PAD} y1={mapMathToSvg({ x: 0, y: 0 }).y} x2={MATH_W - MATH_PAD} y2={mapMathToSvg({ x: 0, y: 0 }).y} />
            <line className="math-axis" x1={mapMathToSvg({ x: 0, y: 0 }).x} y1={MATH_PAD} x2={mapMathToSvg({ x: 0, y: 0 }).x} y2={MATH_H - MATH_PAD} />
            <line className="line-graph" x1={lineSvgStart.x} y1={lineSvgStart.y} x2={lineSvgEnd.x} y2={lineSvgEnd.y} />
            <path
              className="slope-triangle"
              d={`M ${derived.svgA.x} ${derived.svgA.y} L ${derived.triangleBase.x} ${derived.triangleBase.y} L ${derived.svgB.x} ${derived.svgB.y}`}
            />
            <text className="triangle-label base" x={(derived.svgA.x + derived.triangleBase.x) / 2} y={derived.triangleBase.y + 18}>
              Δx {formatNumber(derived.dx, 1)}
            </text>
            <text className="triangle-label rise" x={derived.triangleBase.x + 8} y={(derived.svgB.y + derived.triangleBase.y) / 2}>
              Δy {formatNumber(derived.dy, 1)}
            </text>
            {[
              { key: "a" as const, point: pointA, svg: derived.svgA, label: "A" },
              { key: "b" as const, point: pointB, svg: derived.svgB, label: "B" },
            ].map((item) => (
              <g key={item.key} className="math-point" onPointerDown={(event) => onPointerDown(item.key, event)}>
                <circle cx={item.svg.x} cy={item.svg.y} r="13" />
                <text x={item.svg.x} y={item.svg.y + 4}>{item.label}</text>
                <title>{`${item.label} (${formatNumber(item.point.x, 1)}, ${formatNumber(item.point.y, 1)})`}</title>
              </g>
            ))}
          </svg>
        </div>
        <div className="stem-readouts math-readouts">
          <InlineReadout label="公式" value={derived.vertical ? `x = ${formatNumber(pointA.x)}` : `y = ${formatNumber(derived.slope)}x ${derived.intercept >= 0 ? "+" : "-"} ${formatNumber(Math.abs(derived.intercept))}`} detail="由两点实时重算" />
          <InlineReadout label="斜率三角形" value={slopeLabel} detail={`Δy / Δx = ${formatNumber(derived.dy, 1)} / ${formatNumber(derived.dx, 1)}`} />
          <div className="math-table" aria-label="函数值表">
            {derived.samples.map((sample) => (
              <span key={sample.x}>
                <b>x {sample.x}</b>
                <strong>{derived.vertical ? "无单值 y" : formatNumber(sample.y, 1)}</strong>
              </span>
            ))}
          </div>
        </div>
      </div>
    </LearningSurface>
  );
}

export function PhysicsForceScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const svgRef = useRef<SVGSVGElement>(null);
  const [force, setForce] = useState<ForceVector>({ x: 36, y: -10 });
  const [dragging, setDragging] = useState(false);
  const mass = 2.4;
  const netMagnitude = Math.hypot(force.x, force.y);
  const acceleration = { x: force.x / mass, y: force.y / mass };
  const zeroNet = netMagnitude < 0.45;
  const origin = { x: 168, y: 178 };
  const end = { x: origin.x + force.x * FORCE_SCALE, y: origin.y + force.y * FORCE_SCALE };
  const accEnd = { x: origin.x + acceleration.x * 7.6, y: origin.y + acceleration.y * 7.6 };
  const velocity = { x: 42, y: 0 };
  const trajectory = Array.from({ length: 16 }).map((_, index) => {
    const t = index / 3.2;
    return {
      x: 258 + velocity.x * t + 0.5 * acceleration.x * t * t,
      y: 186 + velocity.y * t + 0.5 * acceleration.y * t * t,
    };
  });
  const path = trajectory.map((point, index) => `${index === 0 ? "M" : "L"} ${point.x} ${point.y}`).join(" ");

  function updateForce(event: ReactPointerEvent<SVGElement>) {
    if (!dragging || !svgRef.current) return;
    const rect = svgRef.current.getBoundingClientRect();
    const svgX = ((event.clientX - rect.left) / rect.width) * PHYSICS_W;
    const svgY = ((event.clientY - rect.top) / rect.height) * PHYSICS_H;
    setForce({
      x: clamp((svgX - origin.x) / FORCE_SCALE, -44, 54),
      y: clamp((svgY - origin.y) / FORCE_SCALE, -34, 34),
    });
  }

  function nudgeToZero() {
    setForce({ x: 0, y: 0 });
  }

  return (
    <LearningSurface
      eyebrow="物理"
      title={title}
      prompt={prompt}
      accent="#b15a2c"
      footer={<EvidenceButton evidenceID="stem.physics.force-newton" label="查看牛顿第二定律依据" onEvidence={onEvidence} />}
    >
      <div className="stem-scene physics-force-scene">
        <div className="stem-canvas physics-canvas" aria-label="拖动力箭头端点改变合力">
          <svg
            ref={svgRef}
            viewBox={`0 0 ${PHYSICS_W} ${PHYSICS_H}`}
            role="img"
            onPointerMove={updateForce}
            onPointerUp={() => setDragging(false)}
            onPointerCancel={() => setDragging(false)}
          >
            <defs>
              <marker id="forceArrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 z" />
              </marker>
              <marker id="netArrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
                <path d="M 0 0 L 10 5 L 0 10 z" />
              </marker>
            </defs>
            <path className="physics-track" d="M 46 230 C 172 216, 282 218, 574 230" />
            <path className={classNames("trajectory-path", zeroNet && "is-inertia")} d={path} />
            {trajectory.map((point, index) => (
              <circle key={index} className="trajectory-dot" cx={point.x} cy={point.y} r={index % 3 === 0 ? 3.2 : 2.1} />
            ))}
            <g className="cart-body" transform={`translate(${origin.x - 50} ${origin.y + 14})`}>
              <rect x="0" y="0" width="100" height="36" rx="4" />
              <circle cx="24" cy="42" r="10" />
              <circle cx="76" cy="42" r="10" />
            </g>
            <line className="force-line" x1={origin.x} y1={origin.y} x2={end.x} y2={end.y} markerEnd="url(#forceArrow)" />
            {!zeroNet ? <line className="net-line" x1={origin.x} y1={origin.y} x2={accEnd.x} y2={accEnd.y} markerEnd="url(#netArrow)" /> : null}
            <circle
              className="force-handle"
              cx={end.x}
              cy={end.y}
              r="14"
              onPointerDown={(event) => {
                event.currentTarget.setPointerCapture(event.pointerId);
                setDragging(true);
              }}
            />
            <text className="force-label" x={end.x + 10} y={end.y - 12}>拖动合力端点</text>
            <text className="inertia-label" x="386" y="88">{zeroNet ? "零合力: 保持匀速直线" : "合力改变轨迹弯曲"}</text>
          </svg>
        </div>
        <div className="stem-readouts physics-readouts">
          <InlineReadout label="合力" value={`${formatNumber(netMagnitude, 1)} N`} detail={`Fx ${formatNumber(force.x, 1)} N, Fy ${formatNumber(force.y, 1)} N`} />
          <InlineReadout label="加速度" value={`${formatNumber(Math.hypot(acceleration.x, acceleration.y), 1)} m/s²`} detail={`质量 ${mass} kg`} />
          <button className="stem-plain-button" type="button" onClick={nudgeToZero}>切到零合力</button>
        </div>
      </div>
    </LearningSurface>
  );
}

const perturbations: Array<{ key: PerturbationKey; title: string; detail: string }> = [
  { key: "add-reactant", title: "加入反应物", detail: "A 与 B 同时升高" },
  { key: "add-product", title: "加入生成物", detail: "C 瞬间升高" },
  { key: "heat", title: "升温", detail: "K 变小, 平衡反向" },
  { key: "compress", title: "压缩体积", detail: "浓度同时升高" },
];

function disturbedState(key: PerturbationKey) {
  const base = { a: 1, b: 1, c: 4, k: 4 };
  if (key === "add-reactant") return { a: 1.7, b: 1.45, c: 4, k: 4 };
  if (key === "add-product") return { a: 1, b: 1, c: 6.7, k: 4 };
  if (key === "heat") return { a: 1, b: 1, c: 4, k: 2.65 };
  return { a: 1.85, b: 1.85, c: 7.4, k: 4 };
}

function quotient(state: { a: number; b: number; c: number }) {
  return state.c / Math.max(0.01, state.a * state.b);
}

function solveEquilibrium(start: { a: number; b: number; c: number; k: number }) {
  let best = { state: start, error: Math.abs(quotient(start) - start.k), extent: 0 };
  const minExtent = -Math.min(start.c - 0.05, 2.8);
  const maxExtent = Math.min(start.a - 0.05, start.b - 0.05, 2.8);
  for (let step = 0; step <= 560; step += 1) {
    const extent = minExtent + ((maxExtent - minExtent) * step) / 560;
    const candidate = { a: start.a - extent, b: start.b - extent, c: start.c + extent, k: start.k };
    const error = Math.abs(quotient(candidate) - start.k);
    if (error < best.error) best = { state: candidate, error, extent };
  }
  return best;
}

export function ChemEquilibriumScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [perturbation, setPerturbation] = useState<PerturbationKey>("add-reactant");
  const [startedAt, setStartedAt] = useState(() => Date.now());
  const [now, setNow] = useState(() => Date.now());

  React.useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 80);
    return () => window.clearInterval(id);
  }, []);

  function applyPerturbation(key: PerturbationKey) {
    setPerturbation(key);
    setStartedAt(Date.now());
    setNow(Date.now());
  }

  function onDrop(event: DragEvent<HTMLDivElement>) {
    event.preventDefault();
    const key = event.dataTransfer.getData("text/plain") as PerturbationKey;
    if (perturbations.some((item) => item.key === key)) applyPerturbation(key);
  }

  const start = disturbedState(perturbation);
  const solved = solveEquilibrium(start);
  const elapsed = clamp((now - startedAt) / 1800, 0, 1);
  const eased = 1 - Math.pow(1 - elapsed, 3);
  const state = {
    a: start.a + (solved.state.a - start.a) * eased,
    b: start.b + (solved.state.b - start.b) * eased,
    c: start.c + (solved.state.c - start.c) * eased,
    k: start.k,
  };
  const q = quotient(state);
  const forwardRate = state.a * state.b;
  const reverseRate = state.c / state.k;
  const direction = solved.extent > 0.04 ? "正向恢复" : solved.extent < -0.04 ? "逆向恢复" : "已接近平衡";
  const particleCounts = {
    a: Math.round(clamp(state.a * 6, 3, 15)),
    b: Math.round(clamp(state.b * 6, 3, 15)),
    c: Math.round(clamp(state.c * 2.1, 4, 18)),
  };

  return (
    <LearningSurface
      eyebrow="化学"
      title={title}
      prompt={prompt}
      accent="#3d7a52"
      footer={<EvidenceButton evidenceID="stem.chem.le-chatelier" label="查看勒夏特列原理依据" onEvidence={onEvidence} />}
    >
      <div className="stem-scene chem-equilibrium-scene">
        <div className="perturbation-rail" aria-label="扰动卡片">
          {perturbations.map((item) => (
            <button
              key={item.key}
              draggable
              className={classNames("perturbation-card", perturbation === item.key && "is-active")}
              type="button"
              onClick={() => applyPerturbation(item.key)}
              onDragStart={(event) => event.dataTransfer.setData("text/plain", item.key)}
            >
              <strong>{item.title}</strong>
              <span>{item.detail}</span>
            </button>
          ))}
        </div>
        <div
          className="stem-canvas chem-canvas"
          aria-label="动态平衡扰动池"
          onDragOver={(event) => event.preventDefault()}
          onDrop={onDrop}
        >
          <div className="chem-vessel">
            <ParticleCloud count={particleCounts.a} type="a" />
            <ParticleCloud count={particleCounts.b} type="b" />
            <ParticleCloud count={particleCounts.c} type="c" />
            <div className="equilibrium-pulse" style={{ "--recover": eased } as CSSProperties}>
              {direction}
            </div>
          </div>
          <div className="rate-chart" aria-label="正逆反应速率">
            <RateLine className="forward" value={forwardRate} max={3.4} label="正反应" />
            <RateLine className="reverse" value={reverseRate} max={3.4} label="逆反应" />
          </div>
        </div>
        <div className="stem-readouts chem-readouts">
          <InlineReadout label="Q / K" value={formatNumber(q / state.k, 2)} detail={q > state.k ? "生成物偏多" : q < state.k ? "反应物偏多" : "正好平衡"} />
          <InlineReadout label="恢复进度" value={`${Math.round(eased * 100)}%`} detail={`Q ${formatNumber(q, 2)}, K ${formatNumber(state.k, 2)}`} />
          <InlineReadout label="浓度" value={`A ${formatNumber(state.a, 2)}  B ${formatNumber(state.b, 2)}  C ${formatNumber(state.c, 2)}`} detail="A + B ⇌ C" />
        </div>
      </div>
    </LearningSurface>
  );
}

function ParticleCloud({ count, type }: { count: number; type: "a" | "b" | "c" }) {
  return (
    <div className={`particle-cloud ${type}`}>
      {Array.from({ length: count }).map((_, index) => {
        const leftSeed = type === "a" ? 37 : type === "b" ? 43 : 47;
        const topSeed = type === "a" ? 53 : type === "b" ? 31 : 41;
        const leftOffset = type === "a" ? 4 : type === "b" ? 28 : 14;
        const topOffset = type === "a" ? 8 : type === "b" ? 20 : 30;
        const style = {
          left: `${(leftOffset + index * leftSeed) % 88}%`,
          top: `${(topOffset + index * topSeed) % 82}%`,
          transform: type === "c" ? "rotate(28deg)" : undefined,
        };
        return <span key={index} style={style} />;
      })}
    </div>
  );
}

function RateLine({ className, value, max, label }: { className: string; value: number; max: number; label: string }) {
  const y = CHART_H - 24 - clamp(value / max, 0, 1) * 112;
  const points = Array.from({ length: 9 }).map((_, index) => {
    const x = 28 + index * 62;
    const wave = Math.sin(index * 0.9 + value) * 7;
    return `${x},${clamp(y + wave, 24, CHART_H - 24)}`;
  });
  return (
    <svg className={`rate-line ${className}`} viewBox={`0 0 ${CHART_W} ${CHART_H}`} aria-hidden="true">
      <polyline points={points.join(" ")} />
      <text x="30" y="22">{label}</text>
    </svg>
  );
}

const stageInfo: Record<StageKey, { label: string; note: string }> = {
  pair: { label: "同源配对", note: "同源染色体先找到彼此" },
  cross: { label: "交叉互换", note: "非姐妹染色单体交换片段" },
  "divide-one": { label: "第一次分离", note: "同源染色体分向两极" },
  "divide-two": { label: "第二次分离", note: "姐妹染色单体再分离" },
};

function analyzeMeiosis(order: StageKey[]) {
  const pair = order.indexOf("pair");
  const cross = order.indexOf("cross");
  const first = order.indexOf("divide-one");
  const second = order.indexOf("divide-two");
  const valid = pair < cross && cross < first && first < second;
  const pairingFirst = pair < first;
  const recombines = cross > pair && cross < first;
  if (!pairingFirst) {
    return {
      valid,
      verdict: "同源染色体未先配对，分离会失去对象",
      gametes: ["A?", "a?"],
      detail: "结果偏向异常配子",
      recombines: false,
    };
  }
  if (second < first) {
    return {
      valid,
      verdict: "姐妹染色单体提前分离，减数分裂顺序被打乱",
      gametes: ["AB", "AB", "ab", "ab"],
      detail: "数量像四个, 但来源不合规",
      recombines,
    };
  }
  if (!recombines) {
    return {
      valid,
      verdict: "没有有效交叉互换，只保留亲本型组合",
      gametes: ["AB", "AB", "ab", "ab"],
      detail: "亲本型占主导",
      recombines,
    };
  }
  return {
    valid,
    verdict: valid ? "顺序正确，能得到四类配子" : "顺序接近，但关键步骤仍需调整",
    gametes: valid ? ["AB", "Ab", "aB", "ab"] : ["AB", "Ab?", "aB?", "ab"],
    detail: valid ? "重组型与亲本型同时出现" : "重组发生, 但阶段顺序未闭合",
    recombines,
  };
}

export function BiologyMeiosisScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [order, setOrder] = useState<StageKey[]>(["pair", "divide-one", "cross", "divide-two"]);
  const [draggingStage, setDraggingStage] = useState<StageKey | null>(null);
  const boardRef = useRef<HTMLDivElement>(null);
  const draggingStageRef = useRef<StageKey | null>(null);
  const result = analyzeMeiosis(order);

  function moveStage(stage: StageKey, targetIndex: number) {
    setOrder((current) => {
      const without = current.filter((item) => item !== stage);
      without.splice(targetIndex, 0, stage);
      return without;
    });
  }

  function beginStageDrag(stage: StageKey, event: ReactPointerEvent<HTMLButtonElement>) {
    draggingStageRef.current = stage;
    setDraggingStage(stage);
    event.currentTarget.setPointerCapture(event.pointerId);
  }

  function updateStageDrag(event: ReactPointerEvent<HTMLButtonElement>) {
    const stage = draggingStageRef.current;
    const board = boardRef.current;
    if (!stage || !board) return;
    const bounds = board.getBoundingClientRect();
    const targetIndex = Math.floor(clamp((event.clientX - bounds.left) / bounds.width, 0, 0.999) * order.length);
    if (targetIndex !== order.indexOf(stage)) moveStage(stage, targetIndex);
  }

  function finishStageDrag(event: ReactPointerEvent<HTMLButtonElement>) {
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    draggingStageRef.current = null;
    setDraggingStage(null);
  }

  return (
    <LearningSurface
      eyebrow="生物"
      title={title}
      prompt={prompt}
      accent="#7161a8"
      footer={<EvidenceButton evidenceID="stem.bio.meiosis-gametes" label="查看减数分裂依据" onEvidence={onEvidence} />}
    >
      <div className="stem-scene biology-meiosis-scene">
        <div className="stem-canvas meiosis-canvas" aria-label="拖放阶段编排配子结果">
          <div className="chromosome-stage" aria-label="染色体行为图">
            <ChromosomePair recombines={result.recombines} valid={result.valid} />
          </div>
          <div ref={boardRef} className="stage-board" aria-label="减数分裂阶段轨道">
            {order.map((stage, index) => (
              <div key={stage} className="stage-slot">
                <button
                  className={classNames("stage-token", draggingStage === stage && "is-dragging")}
                  type="button"
                  aria-grabbed={draggingStage === stage}
                  onPointerDown={(event) => beginStageDrag(stage, event)}
                  onPointerMove={updateStageDrag}
                  onPointerUp={finishStageDrag}
                  onPointerCancel={finishStageDrag}
                  onKeyDown={(event) => {
                    if (event.key === "ArrowLeft") moveStage(stage, Math.max(0, index - 1));
                    if (event.key === "ArrowRight") moveStage(stage, Math.min(order.length - 1, index + 1));
                  }}
                >
                  <small>{String(index + 1).padStart(2, "0")}</small>
                  <strong>{stageInfo[stage].label}</strong>
                  <span>{stageInfo[stage].note}</span>
                </button>
              </div>
            ))}
          </div>
        </div>
        <div className="stem-readouts biology-readouts">
          <InlineReadout label="阶段判断" value={result.valid ? "顺序成立" : "需要调整"} detail={result.verdict} />
          <InlineReadout label="配子结果" value={result.gametes.join("  ")} detail={result.detail} />
          <div className="gamete-strip" aria-label="配子输出">
            {result.gametes.map((gamete, index) => (
              <span key={`${gamete}-${index}`} className={gamete.includes("?") ? "is-uncertain" : ""}>{gamete}</span>
            ))}
          </div>
        </div>
      </div>
    </LearningSurface>
  );
}

function ChromosomePair({ recombines, valid }: { recombines: boolean; valid: boolean }) {
  return (
    <div className={classNames("chromosome-pair", recombines && "has-cross", valid && "is-valid")}>
      <span className="chromosome maternal"><i>A</i><i>B</i></span>
      <span className="chromosome paternal"><i>a</i><i>b</i></span>
      <span className="spindle left" />
      <span className="spindle right" />
      <strong>{valid ? "四分体完成后分离" : "拖阶段修正顺序"}</strong>
    </div>
  );
}
