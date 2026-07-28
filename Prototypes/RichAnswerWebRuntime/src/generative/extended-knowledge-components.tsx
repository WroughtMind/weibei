import { useEffect, useMemo, useRef } from "react";
import type { PointerEvent as ReactPointerEvent } from "react";
import { defineComponent, reactive, useStateField } from "@openuidev/react-lang";
import { z } from "zod/v4";
import "./extended-knowledge-components.css";

function numeric(value: unknown, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(maximum, Math.max(minimum, value));
}

function formatNumber(value: number, precision = 1) {
  if (!Number.isFinite(value)) return "—";
  if (Math.abs(value) < 0.0001) return "0";
  return Number.isInteger(value)
    ? String(value)
    : value.toFixed(precision).replace(/\.0+$/, "");
}

function mean(values: number[]) {
  return values.length ? values.reduce((total, value) => total + value, 0) / values.length : Number.NaN;
}

function median(values: number[]) {
  if (!values.length) return Number.NaN;
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle]! : (sorted[middle - 1]! + sorted[middle]!) / 2;
}

function coordinatePairs(values: number[]) {
  const pairs: Array<[number, number]> = [];
  for (let index = 0; index + 1 < values.length; index += 2) {
    pairs.push([clamp(values[index]!, 0, 1), clamp(values[index + 1]!, 0, 1)]);
  }
  return pairs;
}

const spatialToneSchema = z.enum(["stone", "water", "moss", "ochre", "cinnabar", "indigo"]);

const spatialTones: Record<z.infer<typeof spatialToneSchema>, { fill: string; stroke: string }> = {
  stone: { fill: "rgba(100, 92, 80, 0.14)", stroke: "#756d62" },
  water: { fill: "rgba(63, 113, 107, 0.16)", stroke: "#3f716b" },
  moss: { fill: "rgba(96, 115, 68, 0.16)", stroke: "#607344" },
  ochre: { fill: "rgba(176, 121, 59, 0.16)", stroke: "#a06f3b" },
  cinnabar: { fill: "rgba(143, 63, 47, 0.14)", stroke: "#8f3f2f" },
  indigo: { fill: "rgba(93, 99, 133, 0.15)", stroke: "#5d6385" },
};

export const SpatialLayer = defineComponent({
  name: "SpatialLayer",
  description: "空间视图中的语义图层。模型只声明图层身份、名称、内容类型和色调，不提供 CSS 或像素布局。",
  props: z.object({
    id: z.string(),
    label: z.string(),
    kind: z.enum(["region", "path", "point"]),
    defaultVisible: z.boolean(),
    tone: spatialToneSchema,
  }),
  component: () => null,
});

export const SpatialRegion = defineComponent({
  name: "SpatialRegion",
  description: "由 0 到 1 的归一化坐标围成的区域。coordinates 按 x,y 成对排列，不接受 SVG path。",
  props: z.object({
    id: z.string(),
    layerID: z.string(),
    label: z.string(),
    coordinates: z.array(z.number().min(0).max(1)).min(6).max(120),
    tone: spatialToneSchema,
  }),
  component: () => null,
});

export const SpatialPath = defineComponent({
  name: "SpatialPath",
  description: "由归一化坐标构成的路径。模型提供语义点列和路径类型，组件在 Canvas 内绘制。",
  props: z.object({
    id: z.string(),
    layerID: z.string(),
    label: z.string(),
    coordinates: z.array(z.number().min(0).max(1)).min(4).max(120),
    kind: z.enum(["primary", "secondary", "dashed"]),
    tone: spatialToneSchema,
  }),
  component: () => null,
});

export const SpatialPoint = defineComponent({
  name: "SpatialPoint",
  description: "可选中的语义点位，位置使用 0 到 1 的归一化坐标。detail 是选中后显示的局部说明。",
  props: z.object({
    id: z.string(),
    layerID: z.string(),
    label: z.string(),
    x: z.number().min(0).max(1),
    y: z.number().min(0).max(1),
    detail: z.string(),
    importance: z.enum(["context", "normal", "focus"]),
    evidenceID: z.string().optional(),
  }),
  component: () => null,
});

export const LayeredSpatialView = defineComponent({
  name: "LayeredSpatialView",
  description: "组合区域、路径和点位的通用空间深组件；支持图层开关、点位详情与比例尺。模型不得提供 SVG path、HTML/CSS 或像素布局。",
  props: z.object({
    visibilityStateName: z.string(),
    visibleLayerIDs: reactive(z.array(z.string())),
    selectionStateName: z.string(),
    selectedPointID: reactive(z.string()),
    title: z.string(),
    layers: z.array(SpatialLayer.ref).min(1).max(8),
    regions: z.array(SpatialRegion.ref).max(20),
    paths: z.array(SpatialPath.ref).max(20),
    points: z.array(SpatialPoint.ref).min(1).max(30),
    scaleDistance: z.number().positive(),
    scaleUnit: z.string(),
    caption: z.string(),
  }),
  component: ({ props }) => {
    const visibilityField = useStateField(props.visibilityStateName, props.visibleLayerIDs);
    const selectionField = useStateField(props.selectionStateName, props.selectedPointID);
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const frameRef = useRef<HTMLDivElement>(null);
    const defaultLayers = props.layers.filter((layer) => layer.props.defaultVisible).map((layer) => layer.props.id);
    const visibleLayerIDs = Array.isArray(visibilityField.value)
      ? visibilityField.value.map(String)
      : defaultLayers;
    const visibleSet = new Set(visibleLayerIDs);
    const visiblePoints = props.points.filter((point) => visibleSet.has(point.props.layerID));
    const requestedPointID = String(selectionField.value ?? "");
    const selectedPoint = visiblePoints.find((point) => point.props.id === requestedPointID) ?? visiblePoints[0] ?? null;

    useEffect(() => {
      const canvas = canvasRef.current;
      const frame = frameRef.current;
      if (!canvas || !frame) return;

      const draw = () => {
        const bounds = frame.getBoundingClientRect();
        const width = Math.max(260, bounds.width);
        const height = Math.max(230, Math.min(390, width * 0.58));
        const ratio = window.devicePixelRatio || 1;
        canvas.width = Math.round(width * ratio);
        canvas.height = Math.round(height * ratio);
        canvas.style.height = `${height}px`;
        const context = canvas.getContext("2d");
        if (!context) return;
        context.setTransform(ratio, 0, 0, ratio, 0, 0);
        context.clearRect(0, 0, width, height);

        context.strokeStyle = "rgba(78, 68, 55, 0.07)";
        context.lineWidth = 1;
        for (let fraction = 0.2; fraction < 1; fraction += 0.2) {
          context.beginPath();
          context.moveTo(width * fraction, 0);
          context.lineTo(width * fraction, height);
          context.stroke();
          context.beginPath();
          context.moveTo(0, height * fraction);
          context.lineTo(width, height * fraction);
          context.stroke();
        }

        props.regions.forEach((region) => {
          if (!visibleSet.has(region.props.layerID)) return;
          const coordinates = coordinatePairs(region.props.coordinates);
          if (coordinates.length < 3) return;
          const tone = spatialTones[region.props.tone];
          context.beginPath();
          coordinates.forEach(([x, y], index) => {
            if (index === 0) context.moveTo(x * width, y * height);
            else context.lineTo(x * width, y * height);
          });
          context.closePath();
          context.fillStyle = tone.fill;
          context.strokeStyle = tone.stroke;
          context.lineWidth = 1;
          context.fill();
          context.stroke();
        });

        props.paths.forEach((path) => {
          if (!visibleSet.has(path.props.layerID)) return;
          const coordinates = coordinatePairs(path.props.coordinates);
          if (coordinates.length < 2) return;
          const tone = spatialTones[path.props.tone];
          context.beginPath();
          coordinates.forEach(([x, y], index) => {
            if (index === 0) context.moveTo(x * width, y * height);
            else context.lineTo(x * width, y * height);
          });
          context.strokeStyle = tone.stroke;
          context.lineWidth = path.props.kind === "primary" ? 5 : path.props.kind === "secondary" ? 2.5 : 1.5;
          context.lineCap = "round";
          context.lineJoin = "round";
          context.setLineDash(path.props.kind === "dashed" ? [6, 6] : []);
          context.stroke();
          context.setLineDash([]);
        });
      };

      draw();
      const observer = new ResizeObserver(draw);
      observer.observe(frame);
      return () => observer.disconnect();
    }, [props.paths, props.regions, visibleLayerIDs.join("|")]);

    const toggleLayer = (layerID: string) => {
      const next = visibleSet.has(layerID)
        ? visibleLayerIDs.filter((id) => id !== layerID)
        : [...visibleLayerIDs, layerID];
      visibilityField.setValue(next);
    };

    return (
      <section className="ra-spatial-view">
        <header>
          <span>{props.title}</span>
          <div className="ra-spatial-view__layers" aria-label="图层开关">
            {props.layers.map((layer) => (
              <label key={layer.props.id} data-tone={layer.props.tone}>
                <input
                  aria-label={`图层：${layer.props.label}`}
                  data-weibei-control="spatial-layer-toggle"
                  data-weibei-control-id={layer.props.id}
                  type="checkbox"
                  checked={visibleSet.has(layer.props.id)}
                  onChange={() => toggleLayer(layer.props.id)}
                />
                <span>{layer.props.label}</span>
              </label>
            ))}
          </div>
        </header>
        <div className="ra-spatial-view__frame" ref={frameRef}>
          <canvas ref={canvasRef} role="img" aria-label={props.title} />
          <div className="ra-spatial-view__points">
            {visiblePoints.map((point) => (
              <button
                key={point.props.id}
                type="button"
                aria-label={`${props.title} 点位：${point.props.label}`}
                data-weibei-control="spatial-point"
                data-weibei-control-id={point.props.id}
                className={point.props.id === selectedPoint?.props.id ? "is-active" : ""}
                data-importance={point.props.importance}
                data-edge={point.props.x > 0.72 ? "end" : "start"}
                style={{ left: `${point.props.x * 100}%`, top: `${point.props.y * 100}%` }}
                onClick={() => selectionField.setValue(point.props.id)}
              >
                <i />
                <span>{point.props.label}</span>
              </button>
            ))}
          </div>
          <div className="ra-spatial-view__scale" aria-label={`比例尺 ${props.scaleDistance} ${props.scaleUnit}`}>
            <i />
            <span>{formatNumber(props.scaleDistance)} {props.scaleUnit}</span>
          </div>
          {selectedPoint ? (
            <aside>
              <strong>{selectedPoint.props.label}</strong>
              <p>{selectedPoint.props.detail}</p>
              {selectedPoint.props.evidenceID ? (
                <button
                  type="button"
                  aria-label={`回到依据：${selectedPoint.props.label}`}
                  data-weibei-control="spatial-evidence"
                  data-weibei-control-id={selectedPoint.props.evidenceID}
                  onClick={() => window.dispatchEvent(new CustomEvent("weibei:evidence", { detail: { evidenceID: selectedPoint.props.evidenceID } }))}
                >回到依据</button>
              ) : null}
            </aside>
          ) : null}
        </div>
        <p>{props.caption}</p>
      </section>
    );
  },
});

export const DistributionBrush = defineComponent({
  name: "DistributionBrush",
  description: "显示总体分布并提供可拖动、可调完整宽度的样本窗口；实际范围为中心减/加宽度的一半，实时对照总体与窗口内样本的均值和中位数。模型只给数值和初始状态。",
  props: z.object({
    centerStateName: z.string(),
    windowCenter: reactive(z.number()),
    spanStateName: z.string(),
    windowSpan: reactive(z.number()),
    title: z.string(),
    values: z.array(z.number()).min(5).max(240),
    unit: z.string(),
    binCount: z.number().int().min(6).max(30),
    caption: z.string(),
  }),
  component: ({ props }) => {
    const centerField = useStateField(props.centerStateName, props.windowCenter);
    const spanField = useStateField(props.spanStateName, props.windowSpan);
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const dragRef = useRef<{ active: boolean; offset: number }>({ active: false, offset: 0 });
    const observedMinimum = Math.min(...props.values);
    const observedMaximum = Math.max(...props.values);
    const rawRange = observedMaximum - observedMinimum;
    const fallbackPadding = Math.max(1, Math.abs(observedMaximum) * 0.1);
    const minimum = rawRange ? observedMinimum : observedMinimum - fallbackPadding;
    const maximum = rawRange ? observedMaximum : observedMaximum + fallbackPadding;
    const range = maximum - minimum;
    const minimumSpan = range / props.binCount;
    const span = clamp(Math.abs(numeric(spanField.value, range * 0.35)), minimumSpan, range);
    const center = clamp(numeric(centerField.value, (minimum + maximum) / 2), minimum + span / 2, maximum - span / 2);
    const lower = center - span / 2;
    const upper = center + span / 2;
    const sample = props.values.filter((value) => value >= lower && value <= upper);
    const unit = ["", "无单位", "unitless", "dimensionless", "none"].includes(props.unit.trim().toLowerCase())
      ? ""
      : props.unit.trim();
    const statistics = useMemo(() => ({
      overallMean: mean(props.values),
      overallMedian: median(props.values),
      sampleMean: mean(sample),
      sampleMedian: median(sample),
    }), [props.values, lower, upper]);

    useEffect(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;

      const draw = () => {
        const bounds = canvas.getBoundingClientRect();
        const width = Math.max(260, bounds.width);
        const height = Math.max(220, Math.min(310, width * 0.43));
        const ratio = window.devicePixelRatio || 1;
        canvas.width = Math.round(width * ratio);
        canvas.height = Math.round(height * ratio);
        canvas.style.height = `${height}px`;
        const context = canvas.getContext("2d");
        if (!context) return;
        context.setTransform(ratio, 0, 0, ratio, 0, 0);
        context.clearRect(0, 0, width, height);

        const left = 28;
        const right = 14;
        const top = 18;
        const bottom = 34;
        const plotWidth = width - left - right;
        const plotHeight = height - top - bottom;
        const bins = Array.from({ length: props.binCount }, () => 0);
        const sampleBins = Array.from({ length: props.binCount }, () => 0);
        props.values.forEach((value) => {
          const index = Math.min(props.binCount - 1, Math.floor(((value - minimum) / range) * props.binCount));
          bins[index] = (bins[index] ?? 0) + 1;
          if (value >= lower && value <= upper) sampleBins[index] = (sampleBins[index] ?? 0) + 1;
        });
        const maxBin = Math.max(...bins, 1);
        const toX = (value: number) => left + ((value - minimum) / range) * plotWidth;
        const brushLeft = toX(lower);
        const brushRight = toX(upper);

        context.fillStyle = "rgba(143, 63, 47, 0.065)";
        context.fillRect(brushLeft, top, brushRight - brushLeft, plotHeight);
        context.strokeStyle = "rgba(143, 63, 47, 0.7)";
        context.lineWidth = 1;
        context.setLineDash([4, 4]);
        context.beginPath();
        context.moveTo(brushLeft, top);
        context.lineTo(brushLeft, top + plotHeight);
        context.moveTo(brushRight, top);
        context.lineTo(brushRight, top + plotHeight);
        context.stroke();
        context.setLineDash([]);

        const gap = 3;
        const barWidth = Math.max(2, plotWidth / props.binCount - gap);
        bins.forEach((count, index) => {
          const barHeight = (count / maxBin) * (plotHeight - 18);
          const x = left + (index / props.binCount) * plotWidth + gap / 2;
          const y = top + plotHeight - barHeight;
          context.fillStyle = "rgba(92, 84, 73, 0.18)";
          context.fillRect(x, y, barWidth, barHeight);
          const selectedCount = sampleBins[index] ?? 0;
          if (selectedCount) {
            const selectedHeight = (selectedCount / maxBin) * (plotHeight - 18);
            context.fillStyle = "rgba(63, 113, 107, 0.78)";
            context.fillRect(x, top + plotHeight - selectedHeight, barWidth, selectedHeight);
          }
        });

        context.strokeStyle = "rgba(79, 69, 57, 0.55)";
        context.beginPath();
        context.moveTo(left, top + plotHeight + 0.5);
        context.lineTo(width - right, top + plotHeight + 0.5);
        context.stroke();
        context.fillStyle = "#817668";
        context.font = '10px "SFMono-Regular", Menlo, monospace';
        context.textBaseline = "top";
        context.fillText(formatNumber(minimum), left, top + plotHeight + 9);
        const maximumLabel = formatNumber(maximum);
        context.fillText(maximumLabel, width - right - context.measureText(maximumLabel).width, top + plotHeight + 9);
        context.fillStyle = "#8f3f2f";
        context.fillText(`${formatNumber(lower)}–${formatNumber(upper)}`, brushLeft + 5, top + 4);
      };

      draw();
      const observer = new ResizeObserver(draw);
      observer.observe(canvas);
      return () => observer.disconnect();
    }, [props.binCount, props.values, lower, upper]);

    useEffect(() => {
      const canvas = canvasRef.current;
      if (!canvas) return;
      const verifyInteraction = () => {
        const sortedValues = [...props.values].sort((left, right) => left - right);
        let largestGapIndex = 0;
        let largestGap = Number.NEGATIVE_INFINITY;
        for (let index = 0; index < sortedValues.length - 1; index += 1) {
          const gap = sortedValues[index + 1]! - sortedValues[index]!;
          if (gap > largestGap) {
            largestGap = gap;
            largestGapIndex = index;
          }
        }
        const leftCluster = sortedValues.slice(0, largestGapIndex + 1);
        const rightCluster = sortedValues.slice(largestGapIndex + 1);
        const targetCluster = leftCluster.length >= rightCluster.length ? leftCluster : rightCluster;
        const targetMinimum = Math.min(...targetCluster);
        const targetMaximum = Math.max(...targetCluster);
        const nextSpan = clamp(Math.max(minimumSpan, targetMaximum - targetMinimum), minimumSpan, range);
        const nextCenter = clamp(
          (targetMinimum + targetMaximum) / 2,
          minimum + nextSpan / 2,
          maximum - nextSpan / 2,
        );
        spanField.setValue(nextSpan);
        centerField.setValue(nextCenter);
      };
      canvas.addEventListener("weibei:verify-interaction", verifyInteraction);
      return () => canvas.removeEventListener("weibei:verify-interaction", verifyInteraction);
    }, [centerField, maximum, minimum, minimumSpan, props.values, range, spanField]);

    const valueAtPointer = (event: ReactPointerEvent<HTMLCanvasElement>) => {
      const bounds = event.currentTarget.getBoundingClientRect();
      const fraction = clamp((event.clientX - bounds.left - 28) / Math.max(1, bounds.width - 42), 0, 1);
      return minimum + fraction * range;
    };

    const beginDrag = (event: ReactPointerEvent<HTMLCanvasElement>) => {
      const value = valueAtPointer(event);
      dragRef.current = {
        active: true,
        offset: value >= lower && value <= upper ? value - center : 0,
      };
      event.currentTarget.setPointerCapture(event.pointerId);
      centerField.setValue(clamp(value - dragRef.current.offset, minimum + span / 2, maximum - span / 2));
    };

    const moveDrag = (event: ReactPointerEvent<HTMLCanvasElement>) => {
      if (!dragRef.current.active) return;
      const nextCenter = valueAtPointer(event) - dragRef.current.offset;
      centerField.setValue(clamp(nextCenter, minimum + span / 2, maximum - span / 2));
    };

    const endDrag = (event: ReactPointerEvent<HTMLCanvasElement>) => {
      dragRef.current.active = false;
      if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    };

    return (
      <section className="ra-distribution-brush">
        <header>
          <span>{props.title}</span>
          <strong>{sample.length > 0 ? `窗口内 ${sample.length} / 总体 ${props.values.length}` : "当前窗口未覆盖观测值"}</strong>
        </header>
        <canvas
          ref={canvasRef}
          role="application"
          aria-label={`${props.title}，当前样本窗口 ${formatNumber(lower)} 到 ${formatNumber(upper)}`}
          data-weibei-control="distribution-canvas"
          data-weibei-control-id={props.centerStateName}
          onPointerDown={beginDrag}
          onPointerMove={moveDrag}
          onPointerUp={endDrag}
          onPointerCancel={endDrag}
        />
        <label className="ra-distribution-brush__span">
          <span>样本窗口完整宽度</span>
          <input
            aria-label={`${props.title} 样本窗口完整宽度`}
            data-weibei-control="distribution-span-slider"
            data-weibei-control-id={props.spanStateName}
            type="range"
            min={minimumSpan}
            max={range}
            step={minimumSpan}
            value={span}
            onChange={(event) => spanField.setValue(Number(event.currentTarget.value))}
          />
          <output>{formatNumber(span)}{unit ? ` ${unit}` : ""}</output>
        </label>
        <div className="ra-distribution-brush__stats">
          <div><span>总体均值</span><strong>{formatNumber(statistics.overallMean)}</strong>{unit ? <i>{unit}</i> : null}</div>
          <div><span>样本均值</span><strong>{formatNumber(statistics.sampleMean)}</strong>{unit ? <i>{unit}</i> : null}</div>
          <div><span>总体中位数</span><strong>{formatNumber(statistics.overallMedian)}</strong>{unit ? <i>{unit}</i> : null}</div>
          <div><span>样本中位数</span><strong>{formatNumber(statistics.sampleMedian)}</strong>{unit ? <i>{unit}</i> : null}</div>
        </div>
        <p>{props.caption}</p>
      </section>
    );
  },
});

export const FlowAssumption = defineComponent({
  name: "FlowAssumption",
  description: "依赖传导中的一个可调输入假设。值由 DependencyFlow 的共享数值数组按顺序提供。",
  props: z.object({
    id: z.string(),
    label: z.string(),
    minimum: z.number(),
    maximum: z.number(),
    step: z.number().positive(),
    unit: z.string(),
    detail: z.string(),
  }),
  component: () => null,
});

const flowOperationSchema = z.enum([
  "identity",
  "sum",
  "difference",
  "product",
  "ratio",
  "weightedSum",
  "power",
  "minimum",
  "maximum",
  "percentChange",
]);

export const DependencyNode = defineComponent({
  name: "DependencyNode",
  description: "依赖图中的一个受限计算节点。sourceIDs 可引用输入假设或前序节点；只允许声明运算类型和参数，不执行模型代码。",
  props: z.object({
    id: z.string(),
    label: z.string(),
    layer: z.number().int().min(1).max(8),
    operation: flowOperationSchema,
    sourceIDs: z.array(z.string()).min(1).max(6),
    parameters: z.array(z.number()).max(7),
    unit: z.string(),
    precision: z.number().int().min(0).max(4),
    detail: z.string(),
  }),
  component: () => null,
});

export const FlowMetric = defineComponent({
  name: "FlowMetric",
  description: "依赖传导的结果读数，引用一个已声明节点，并显示当前值与所聚焦输入的一步敏感性。",
  props: z.object({
    nodeID: z.string(),
    label: z.string(),
    unit: z.string(),
    precision: z.number().int().min(0).max(4),
    emphasis: z.enum(["primary", "secondary", "warning"]),
    detail: z.string(),
  }),
  component: () => null,
});

function evaluateOperation(operation: z.infer<typeof flowOperationSchema>, sources: number[], parameters: number[]) {
  switch (operation) {
    case "identity": return sources[0]!;
    case "sum": return sources.reduce((total, value) => total + value, 0);
    case "difference": return sources.slice(1).reduce((result, value) => result - value, sources[0]!);
    case "product": return sources.reduce((result, value) => result * value, 1);
    case "ratio": return Math.abs(sources[1]!) < 1e-12 ? Number.NaN : sources[0]! / sources[1]!;
    case "weightedSum": {
      const weighted = sources.reduce((total, value, index) => total + value * (parameters[index] ?? 1), 0);
      return weighted + (parameters.length > sources.length ? parameters[sources.length]! : 0);
    }
    case "power": return Math.pow(sources[0]!, parameters[0] ?? sources[1] ?? 1);
    case "minimum": return Math.min(...sources);
    case "maximum": return Math.max(...sources);
    case "percentChange": return Math.abs(sources[1]!) < 1e-12 ? Number.NaN : ((sources[0]! - sources[1]!) / Math.abs(sources[1]!)) * 100;
  }
}

export const DependencyFlow = defineComponent({
  name: "DependencyFlow",
  description: "通用依赖传导深组件：调节输入假设，按层计算受限依赖图，显示结果指标并聚焦当前输入的一步敏感性。不得传入代码、HTML/CSS 或像素布局。",
  props: z.object({
    valuesStateName: z.string(),
    inputValues: reactive(z.array(z.number())),
    focusStateName: z.string(),
    focusedInputIndex: reactive(z.number()),
    title: z.string(),
    assumptions: z.array(FlowAssumption.ref).min(1).max(6),
    nodes: z.array(DependencyNode.ref).min(1).max(24),
    metrics: z.array(FlowMetric.ref).min(1).max(6),
    caption: z.string(),
  }),
  component: ({ props }) => {
    const valuesField = useStateField(props.valuesStateName, props.inputValues);
    const focusField = useStateField(props.focusStateName, props.focusedInputIndex);
    const rawValues = Array.isArray(valuesField.value) ? valuesField.value : [];
    const inputValues = props.assumptions.map((assumption, index) => clamp(
      numeric(rawValues[index], assumption.props.minimum),
      assumption.props.minimum,
      assumption.props.maximum,
    ));
    const focusedIndex = Math.max(0, Math.min(props.assumptions.length - 1, Math.round(numeric(focusField.value))));
    const focusedAssumption = props.assumptions[focusedIndex]!;
    const orderedNodes = [...props.nodes].sort((left, right) => left.props.layer - right.props.layer);

    const compute = (candidateValues: number[]) => {
      const computed = new Map<string, number>();
      props.assumptions.forEach((assumption, index) => computed.set(assumption.props.id, candidateValues[index]!));
      for (let pass = 0; pass < orderedNodes.length; pass += 1) {
        let changed = false;
        orderedNodes.forEach((node) => {
          if (computed.has(node.props.id)) return;
          const sourceValues = node.props.sourceIDs.map((sourceID) => computed.get(sourceID));
          if (sourceValues.some((value) => typeof value !== "number")) return;
          const result = evaluateOperation(
            node.props.operation,
            sourceValues as number[],
            node.props.parameters,
          );
          computed.set(node.props.id, result);
          changed = true;
        });
        if (!changed) break;
      }
      return computed;
    };

    const computed = compute(inputValues);
    const sensitivityInputs = [...inputValues];
    sensitivityInputs[focusedIndex] = clamp(
      sensitivityInputs[focusedIndex]! + focusedAssumption.props.step,
      focusedAssumption.props.minimum,
      focusedAssumption.props.maximum,
    );
    const sensitivity = compute(sensitivityInputs);
    const affectedIDs = new Set<string>([focusedAssumption.props.id]);
    orderedNodes.forEach((node) => {
      if (node.props.sourceIDs.some((sourceID) => affectedIDs.has(sourceID))) affectedIDs.add(node.props.id);
    });
    const layers = Array.from(new Set(orderedNodes.map((node) => node.props.layer))).sort((left, right) => left - right);

    const setInputValue = (index: number, value: number) => {
      const next = [...inputValues];
      next[index] = value;
      valuesField.setValue(next);
      focusField.setValue(index);
    };

    return (
      <section className="ra-dependency-flow">
        <header>
          <span>{props.title}</span>
          <strong>聚焦：{focusedAssumption.props.label}</strong>
        </header>
        <div className="ra-dependency-flow__body">
          <div className="ra-dependency-flow__inputs">
            {props.assumptions.map((assumption, index) => (
              <label key={assumption.props.id} className={index === focusedIndex ? "is-active" : ""}>
                <span>{assumption.props.label}</span>
                <output>{formatNumber(inputValues[index]!)} {assumption.props.unit}</output>
                <input
                  aria-label={`${props.title} 输入：${assumption.props.label}`}
                  data-weibei-control="dependency-input-slider"
                  data-weibei-control-id={assumption.props.id}
                  type="range"
                  min={assumption.props.minimum}
                  max={assumption.props.maximum}
                  step={assumption.props.step}
                  value={inputValues[index]}
                  onFocus={() => focusField.setValue(index)}
                  onChange={(event) => setInputValue(index, Number(event.currentTarget.value))}
                />
                <small>{assumption.props.detail}</small>
              </label>
            ))}
          </div>
          <div
            className="ra-dependency-flow__graph"
            style={{ gridTemplateColumns: `repeat(${Math.max(1, layers.length)}, minmax(130px, 1fr))` }}
          >
            {layers.map((layer, layerIndex) => (
              <div key={layer} className="ra-dependency-flow__layer">
                <span>第 {layerIndex + 1} 层</span>
                {orderedNodes.filter((node) => node.props.layer === layer).map((node) => (
                  <article key={node.props.id} className={affectedIDs.has(node.props.id) ? "is-affected" : ""}>
                    <small>{node.props.sourceIDs.join(" + ")}</small>
                    <strong>{node.props.label}</strong>
                    <output>{formatNumber(computed.get(node.props.id) ?? Number.NaN, node.props.precision)} {node.props.unit}</output>
                    <p>{node.props.detail}</p>
                  </article>
                ))}
              </div>
            ))}
          </div>
        </div>
        <div className="ra-dependency-flow__metrics">
          {props.metrics.map((metric) => {
            const value = computed.get(metric.props.nodeID) ?? Number.NaN;
            const changedValue = sensitivity.get(metric.props.nodeID) ?? Number.NaN;
            const delta = changedValue - value;
            return (
              <div key={`${metric.props.nodeID}-${metric.props.label}`} data-emphasis={metric.props.emphasis}>
                <span>{metric.props.label}</span>
                <strong>{formatNumber(value, metric.props.precision)}</strong>
                <i>{metric.props.unit}</i>
                <small>{metric.props.detail}</small>
                <em>输入 +{formatNumber(focusedAssumption.props.step)} → {delta >= 0 ? "+" : ""}{formatNumber(delta, metric.props.precision)} {metric.props.unit}</em>
              </div>
            );
          })}
        </div>
        <p>{props.caption}</p>
      </section>
    );
  },
});
