import { useRef, useState } from "react";
import type { PointerEvent as ReactPointerEvent } from "react";
import type { CSSProperties } from "react";
import type { LearningSceneProps } from "../types";
import { EvidenceButton, LearningSurface, clamp } from "../shared";
import "./humanities-scenes.css";

const argumentSentences = [
  { id: "claim", role: "主张", text: "城市公共空间的价值，不在于被看见，而在于允许陌生人低成本地共同停留。", note: "作者真正要证明的结论。", evidence: "text-p1" },
  { id: "reason", role: "理由", text: "当停留不必先消费，人们才可能在同一场所形成弱联系。", note: "主张成立所依赖的机制。", evidence: "text-p2" },
  { id: "evidence", role: "证据", text: "观察记录显示，移除围栏和最低消费后，午间平均停留时长从 11 分钟增加到 27 分钟。", note: "能被核验的数据，不等于完整因果。", evidence: "text-p3" },
  { id: "counter", role: "反驳", text: "但停留时间上升，也可能来自同期树荫和座椅数量增加。", note: "削弱原有解释的替代原因。", evidence: "text-p4" },
  { id: "rebuttal", role: "回应", text: "因此，这组观察支持“降低进入门槛”有作用，却不足以单独证明它是唯一原因。", note: "作者收紧结论，避免过度归因。", evidence: "text-p5" },
];

export function TextArgumentScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [selectedID, setSelectedID] = useState("claim");
  const selected = argumentSentences.find((sentence) => sentence.id === selectedID) ?? argumentSentences[0]!;

  return (
    <LearningSurface
      eyebrow="文本 · 逐句论证剖面"
      title={title}
      prompt={prompt}
      accent="#8c4c3d"
      footer={<EvidenceButton evidenceID={selected.evidence} label={`回到原文：${selected.role}`} onEvidence={onEvidence} />}
    >
      <div className="text-scene">
        <article className="argument-page">
          <aside>逐句点读</aside>
          <div className="argument-copy">
            {argumentSentences.map((sentence, index) => (
              <button
                key={sentence.id}
                type="button"
                className={sentence.id === selectedID ? "is-selected" : ""}
                onClick={() => setSelectedID(sentence.id)}
              >
                <sup>{index + 1}</sup>
                {sentence.text}
              </button>
            ))}
          </div>
          <div className="argument-margin">
            <span>{selected.role}</span>
            <strong>{selected.note}</strong>
            <p>证据锚点 {argumentSentences.findIndex((sentence) => sentence.id === selected.id) + 1}</p>
          </div>
        </article>
        <div className="argument-spine" aria-label="论证骨架">
          {argumentSentences.map((sentence, index) => (
            <button
              key={sentence.id}
              type="button"
              className={sentence.id === selectedID ? "is-selected" : ""}
              onClick={() => setSelectedID(sentence.id)}
            >
              <span>{index + 1}</span>
              <strong>{sentence.role}</strong>
              {index < argumentSentences.length - 1 ? <i /> : null}
            </button>
          ))}
        </div>
      </div>
    </LearningSurface>
  );
}

const historyNodes = [
  { id: "structure", x: 10, y: 18, lane: "背景条件", label: "财政紧张", detail: "长期财政压力压缩了政府的选择空间。", evidence: "history-1" },
  { id: "harvest", x: 28, y: 72, lane: "触发事件", label: "歉收与粮价", detail: "短期冲击把既有矛盾推到日常生活。", evidence: "history-2" },
  { id: "assembly", x: 47, y: 45, lane: "人物选择", label: "召集会议", detail: "政治行动把分散不满转成制度冲突。", evidence: "history-3" },
  { id: "mobilize", x: 64, y: 78, lane: "直接结果", label: "城市动员", detail: "信息与组织网络使局部冲突迅速扩散。", evidence: "history-4" },
  { id: "reform", x: 82, y: 30, lane: "长期后果", label: "制度重组", detail: "短期事件最终改变权利与财政关系。", evidence: "history-5" },
];

const historyEdges = [
  { from: "structure", to: "assembly", kind: "背景约束", strength: "强" },
  { from: "harvest", to: "mobilize", kind: "直接推动", strength: "强" },
  { from: "assembly", to: "mobilize", kind: "行动选择", strength: "中" },
  { from: "mobilize", to: "reform", kind: "长期传导", strength: "中" },
  { from: "harvest", to: "reform", kind: "仅有先后", strength: "不足" },
];

export function HistoryCausalityScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [selectedID, setSelectedID] = useState("assembly");
  const selected = historyNodes.find((node) => node.id === selectedID) ?? historyNodes[0]!;
  const connected = new Set(
    historyEdges.filter((edge) => edge.from === selectedID || edge.to === selectedID).flatMap((edge) => [edge.from, edge.to]),
  );
  connected.add(selectedID);

  return (
    <LearningSurface
      eyebrow="历史 · 因果时间河"
      title={title}
      prompt={prompt}
      accent="#8a6337"
      footer={<EvidenceButton evidenceID={selected.evidence} label={`查看“${selected.label}”史料`} onEvidence={onEvidence} />}
    >
      <div className="history-scene">
        <div className="history-legend">
          <span><i className="background" />背景条件</span>
          <span><i className="direct" />可支持因果</span>
          <span><i className="sequence" />只有先后</span>
        </div>
        <div className="history-river">
          <svg viewBox="0 0 680 330" preserveAspectRatio="none" aria-hidden="true">
            <path d="M34 168 C170 132 286 196 420 154 S568 130 648 162" className="history-time" />
            {historyEdges.map((edge) => {
              const from = historyNodes.find((node) => node.id === edge.from)!;
              const to = historyNodes.find((node) => node.id === edge.to)!;
              const active = edge.from === selectedID || edge.to === selectedID;
              return (
                <path
                  key={`${edge.from}-${edge.to}`}
                  d={curveBetween(from, to)}
                  className={`history-edge ${edge.kind === "仅有先后" ? "is-sequence" : ""} ${active ? "is-active" : ""}`}
                />
              );
            })}
          </svg>
          {historyNodes.map((node) => (
            <button
              key={node.id}
              type="button"
              className={`${node.id === selectedID ? "is-selected" : ""} ${connected.has(node.id) ? "is-connected" : "is-dimmed"}`}
              style={{ left: `${node.x}%`, top: `${node.y}%` }}
              onClick={() => setSelectedID(node.id)}
            >
              <small>{node.lane}</small>
              <strong>{node.label}</strong>
            </button>
          ))}
          <div className="history-note">
            <span>{selected.lane}</span>
            <strong>{selected.label}</strong>
            <p>{selected.detail}</p>
            <ul>
              {historyEdges
                .filter((edge) => edge.from === selectedID || edge.to === selectedID)
                .map((edge) => <li key={`${edge.from}-${edge.to}`}>{edge.kind} · 证据{edge.strength}</li>)}
            </ul>
          </div>
        </div>
      </div>
    </LearningSurface>
  );
}

const mapPlaces = [
  { id: "pass", x: 28, y: 31, label: "北隘口", note: "山口控制了最短陆路，也是运输最脆弱的节点。", evidence: "map-1" },
  { id: "port", x: 74, y: 67, label: "东港", note: "港口把河运与沿海航线接在一起。", evidence: "map-2" },
  { id: "market", x: 48, y: 56, label: "河谷市集", note: "市集位于河流转折和两条道路交汇处。", evidence: "map-3" },
  { id: "plain", x: 61, y: 38, label: "冲积平原", note: "人口与耕作集中，但也暴露于季节洪水。", evidence: "map-4" },
];

export function GeographyMapScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [layers, setLayers] = useState({ terrain: true, region: true, route: true });
  const [selectedID, setSelectedID] = useState("market");
  const selected = mapPlaces.find((place) => place.id === selectedID) ?? mapPlaces[0]!;

  return (
    <LearningSurface
      eyebrow="地理 · 空间图层探查"
      title={title}
      prompt={prompt}
      accent="#3f6b68"
      footer={<EvidenceButton evidenceID={selected.evidence} label={`回到“${selected.label}”材料`} onEvidence={onEvidence} />}
    >
      <div className="map-scene">
        <div className="map-tools" aria-label="地图图层">
          {(
            [
              ["terrain", "地形"],
              ["region", "洪泛区"],
              ["route", "运输路线"],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              <input
                type="checkbox"
                checked={layers[key]}
                onChange={(event) => setLayers((current) => ({ ...current, [key]: event.target.checked }))}
              />
              {label}
            </label>
          ))}
          <span>比例尺 20 km</span>
        </div>
        <div className="map-canvas">
          <svg viewBox="0 0 680 390" role="img" aria-label="河谷交通与洪泛区地图">
            <path d="M0 82 C110 24 205 78 294 44 C405 2 520 48 680 20 L680 0 L0 0 Z" className={layers.terrain ? "terrain ridge is-visible" : "terrain ridge"} />
            <path d="M0 330 C120 285 218 344 326 296 C430 250 528 302 680 248 L680 390 L0 390 Z" className={layers.terrain ? "terrain foothill is-visible" : "terrain foothill"} />
            <path d="M46 126 C170 154 238 98 336 150 C438 204 512 176 636 246" className="river" />
            <path d="M30 182 C160 212 242 150 354 204 C470 258 548 218 666 294 L650 342 C528 270 450 308 330 252 C214 198 140 258 20 224 Z" className={layers.region ? "flood-region is-visible" : "flood-region"} />
            <path d="M110 92 L190 132 L328 214 L500 262 L610 292" className={layers.route ? "route main is-visible" : "route main"} />
            <path d="M190 132 L300 108 L420 140 L505 230" className={layers.route ? "route branch is-visible" : "route branch"} />
            {layers.terrain ? (
              <g className="mountains">
                {[90, 142, 194, 520, 566].map((x, index) => <path key={x} d={`M${x - 14} ${68 + (index % 2) * 24} L${x} ${42 + (index % 2) * 24} L${x + 15} ${68 + (index % 2) * 24}`} />)}
              </g>
            ) : null}
          </svg>
          {mapPlaces.map((place) => (
            <button
              key={place.id}
              type="button"
              className={place.id === selectedID ? "is-selected" : ""}
              style={{ left: `${place.x}%`, top: `${place.y}%` }}
              onClick={() => setSelectedID(place.id)}
            >
              <i />
              <span>{place.label}</span>
            </button>
          ))}
          <div className="map-note">
            <strong>{selected.label}</strong>
            <p>{selected.note}</p>
          </div>
        </div>
      </div>
    </LearningSurface>
  );
}

const artHotspots = [
  { id: "center", x: 42, y: 42, label: "中宫收紧", note: "中心笔画密度高，外轮廓因此显得开张。" },
  { id: "shoulder", x: 63, y: 25, label: "横势上扬", note: "右肩略高，制造不完全对称的张力。" },
  { id: "foot", x: 60, y: 73, label: "下部支撑", note: "末笔重量压低，稳定了上方的倾斜。" },
  { id: "damage", x: 27, y: 62, label: "拓片残损", note: "缺口来自材料，不应误判为原始笔形。" },
  { id: "edge", x: 76, y: 51, label: "侧锋毛边", note: "边缘颗粒提示刻石与拓印共同作用。" },
];

export function ArtObservationScene({ title, prompt, onEvidence }: LearningSceneProps) {
  const [lens, setLens] = useState({ x: 48, y: 46 });
  const [dragging, setDragging] = useState(false);
  const [selectedID, setSelectedID] = useState("center");
  const [showStructure, setShowStructure] = useState(true);
  const canvasRef = useRef<HTMLDivElement>(null);
  const selected = artHotspots.find((hotspot) => hotspot.id === selectedID) ?? artHotspots[0]!;

  const moveLens = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!dragging && event.type !== "pointerdown") return;
    const bounds = event.currentTarget.getBoundingClientRect();
    setLens({
      x: clamp(((event.clientX - bounds.left) / bounds.width) * 100, 4, 96),
      y: clamp(((event.clientY - bounds.top) / bounds.height) * 100, 5, 95),
    });
  };

  const lensStyle = {
    "--lens-x": `${lens.x}%`,
    "--lens-y": `${lens.y}%`,
  } as CSSProperties;

  return (
    <LearningSurface
      eyebrow="艺术 · 可移动观察镜"
      title={title}
      prompt={prompt}
      accent="#9a493b"
      footer={<EvidenceButton evidenceID={`art-${selected.id}`} label={`查看图像局部：${selected.label}`} onEvidence={onEvidence} />}
    >
      <div className="art-scene">
        <div
          ref={canvasRef}
          className="art-canvas"
          style={lensStyle}
          onPointerDown={(event) => {
            setDragging(true);
            event.currentTarget.setPointerCapture(event.pointerId);
            moveLens(event);
          }}
          onPointerMove={moveLens}
          onPointerUp={(event) => {
            setDragging(false);
            event.currentTarget.releasePointerCapture(event.pointerId);
          }}
          onPointerCancel={() => setDragging(false)}
        >
          <RubbingArtwork detailed={false} />
          <div className="art-detail-layer"><RubbingArtwork detailed /></div>
          {showStructure ? <div className="art-structure"><i /><i /><b /></div> : null}
          <div className="art-lens" />
          {artHotspots.map((hotspot, index) => (
            <button
              key={hotspot.id}
              type="button"
              className={hotspot.id === selectedID ? "is-selected" : ""}
              style={{ left: `${hotspot.x}%`, top: `${hotspot.y}%` }}
              onPointerDown={(event) => event.stopPropagation()}
              onClick={() => {
                setSelectedID(hotspot.id);
                setLens({ x: hotspot.x, y: hotspot.y });
              }}
            >
              {index + 1}
            </button>
          ))}
          <div className="art-note">
            <span>观察点</span>
            <strong>{selected.label}</strong>
            <p>{selected.note}</p>
          </div>
        </div>
        <div className="art-controls">
          <span>拖动圆形观察镜，或点编号定位局部。</span>
          <label>
            <input type="checkbox" checked={showStructure} onChange={(event) => setShowStructure(event.target.checked)} />
            显示重心与中宫结构
          </label>
        </div>
      </div>
    </LearningSurface>
  );
}

function RubbingArtwork({ detailed }: { detailed: boolean }) {
  return (
    <div className={detailed ? "rubbing-art is-detailed" : "rubbing-art"} aria-hidden="true">
      <span className="rubbing-main">龍</span>
      <span className="rubbing-side">門</span>
      <i className="abrasion one" />
      <i className="abrasion two" />
      <i className="abrasion three" />
      <b className="stone-crack one" />
      <b className="stone-crack two" />
    </div>
  );
}

function curveBetween(from: (typeof historyNodes)[number], to: (typeof historyNodes)[number]) {
  const x1 = (from.x / 100) * 680;
  const y1 = (from.y / 100) * 330;
  const x2 = (to.x / 100) * 680;
  const y2 = (to.y / 100) * 330;
  const midpoint = (x1 + x2) / 2;
  return `M${x1} ${y1} C${midpoint} ${y1}, ${midpoint} ${y2}, ${x2} ${y2}`;
}
