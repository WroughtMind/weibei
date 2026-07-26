import { isRecord } from "./agent-context";
import { RICH_ANSWER_CHART_KINDS, RichAnswerRendererRegistration } from "./rich-answer-catalog";
import {
  RICH_ANSWER_CHART_KIND_SET,
  RICH_ANSWER_MATH_BINARY_OPERATIONS,
  RICH_ANSWER_MATH_UNARY_OPERATIONS,
  RichAnswerRenderPlanSpecParam,
  RichAnswerSceneParam,
  rendererFieldList,
  richAnswerRenderPlanForbiddenFieldPaths,
  richAnswerRenderPlanIntegerInRange,
  richAnswerRenderPlanNumberArray,
  richAnswerRenderPlanStringArray,
  richAnswerRenderPlanUnknownFields,
  richAnswerRenderPlanValidIdentifier,
} from "./rich-answer-validation-models";


export function validateRichAnswerChartSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  issue: (message: string) => void,
): number {
  const unknownSpecFields = richAnswerRenderPlanUnknownFields(spec, registration.allowedSpecFields);
  if (unknownSpecFields.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的 renderPlan.spec 只能使用高层字段 ${rendererFieldList(registration.allowedSpecFields)}，不能包含 ${unknownSpecFields.join("、")}`,
    );
  }

  const forbiddenPaths = richAnswerRenderPlanForbiddenFieldPaths(spec, registration);
  if (forbiddenPaths.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的 renderPlan.spec 包含禁止字段：${forbiddenPaths.join("、")}；只给高层字段，不给 raw option、脚本、HTML 或 SVG path`,
    );
  }

  const chartKind = spec.chartKind;
  if (typeof chartKind !== "string" || !RICH_ANSWER_CHART_KIND_SET.has(chartKind)) {
    issue(
      `富回答场景 ${scene.id} 的 chartKind 必须是 ${RICH_ANSWER_CHART_KINDS.join("、")} 之一`,
    );
  }
  if (typeof spec.title !== "string" || spec.title.trim().length === 0) {
    issue(`富回答场景 ${scene.id} 的图表 spec.title 不能为空`);
  }

  const series = Array.isArray(spec.series) ? spec.series : [];
  if (spec.series !== undefined && !Array.isArray(spec.series)) {
    issue(`富回答场景 ${scene.id} 的 spec.series 必须是数组`);
  }
  if (series.length > registration.budgets.maxSeries) {
    issue(
      `富回答场景 ${scene.id} 的 series 数量超出预算：${series.length}/${registration.budgets.maxSeries}`,
    );
  }

  let dataPointCount = 0;
  let longestSeriesLength = 0;
  for (const [seriesIndex, rawSeries] of series.entries()) {
    if (!isRecord(rawSeries)) {
      issue(`富回答场景 ${scene.id} 的 series[${seriesIndex}] 必须是对象`);
      continue;
    }
    const unknownSeriesFields = richAnswerRenderPlanUnknownFields(
      rawSeries,
      registration.allowedSeriesFields,
    );
    if (unknownSeriesFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 series[${seriesIndex}] 只能使用 ${rendererFieldList(registration.allowedSeriesFields)}，不能包含 ${unknownSeriesFields.join("、")}`,
      );
    }
    if (typeof rawSeries.name !== "string" || rawSeries.name.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 series[${seriesIndex}].name 不能为空`);
    }
    if (
      rawSeries.unit !== undefined &&
      (typeof rawSeries.unit !== "string" || rawSeries.unit.trim().length === 0)
    ) {
      issue(`富回答场景 ${scene.id} 的 series[${seriesIndex}].unit 必须是非空字符串`);
    }
    if (
      rawSeries.chartKind !== undefined &&
      (typeof rawSeries.chartKind !== "string" || !["line", "bar"].includes(rawSeries.chartKind))
    ) {
      issue(`富回答场景 ${scene.id} 的 series[${seriesIndex}].chartKind 只能是 line 或 bar`);
    }
    if (chartKind === "line" && rawSeries.chartKind !== undefined && rawSeries.chartKind !== "line") {
      issue(`富回答场景 ${scene.id} 的 line 图不能包含非 line series`);
    }
    if (chartKind === "bar" && rawSeries.chartKind !== undefined && rawSeries.chartKind !== "bar") {
      issue(`富回答场景 ${scene.id} 的 bar 图不能包含非 bar series`);
    }
    if (chartKind === "mixed" && rawSeries.chartKind !== undefined && !["line", "bar"].includes(rawSeries.chartKind)) {
      issue(`富回答场景 ${scene.id} 的 mixed 图每个 series.chartKind 必须是 line 或 bar`);
    }
    const values = richAnswerRenderPlanNumberArray(rawSeries.values);
    if (rawSeries.values !== undefined && values === undefined) {
      issue(`富回答场景 ${scene.id} 的 series[${seriesIndex}].values 必须是有限数字数组`);
    }
    if (values === undefined || values.length === 0) {
      issue(`富回答场景 ${scene.id} 的 series[${seriesIndex}].values 不能为空`);
    }
    if (values !== undefined) {
      dataPointCount += values.length;
      longestSeriesLength = Math.max(longestSeriesLength, values.length);
    }
    const xValues = richAnswerRenderPlanNumberArray(rawSeries.xValues);
    if (rawSeries.xValues !== undefined && xValues === undefined) {
      issue(`富回答场景 ${scene.id} 的 series[${seriesIndex}].xValues 必须是有限数字数组`);
    }
    if (chartKind === "scatter") {
      if (xValues === undefined || values === undefined || xValues.length !== values.length) {
        issue(`富回答场景 ${scene.id} 的 scatter series[${seriesIndex}] 必须提供与 values 等长的 xValues`);
      }
    } else if (rawSeries.xValues !== undefined) {
      issue(`富回答场景 ${scene.id} 只有 scatter 图可以提供 series[${seriesIndex}].xValues`);
    }
  }

  if (chartKind === "mixed") {
    const units = series
      .map((rawSeries) => isRecord(rawSeries) && typeof rawSeries.unit === "string" ? rawSeries.unit.trim() : "")
      .filter((unit) => unit.length > 0);
    if (units.length !== series.length || new Set(units).size !== 1) {
      issue(`富回答场景 ${scene.id} 的 mixed 图必须为每个 series 声明同一个 unit；跨单位混合图需要另一个已注册渲染器`);
    }
  }

  const xLabels = richAnswerRenderPlanStringArray(spec.xLabels);
  if (spec.xLabels !== undefined && xLabels === undefined) {
    issue(`富回答场景 ${scene.id} 的 xLabels 必须是非空字符串数组`);
  }
  if (chartKind !== "scatter" && xLabels !== undefined && longestSeriesLength > 0 && xLabels.length !== longestSeriesLength) {
    issue(
      `富回答场景 ${scene.id} 的 xLabels 数量必须与 series.values 对齐：${xLabels.length}/${longestSeriesLength}`,
    );
  }
  const samples = richAnswerRenderPlanNumberArray(spec.samples);
  if (spec.samples !== undefined && samples === undefined) {
    issue(`富回答场景 ${scene.id} 的 samples 必须是有限数字数组`);
  }
  if (samples !== undefined) {
    dataPointCount += samples.length;
  }
  if (
    spec.binCount !== undefined &&
    !richAnswerRenderPlanIntegerInRange(spec.binCount, 3, 60)
  ) {
    issue(`富回答场景 ${scene.id} 的 binCount 必须是 3–60 的整数`);
  }
  if (chartKind === "histogram") {
    if ((samples?.length ?? 0) === 0) {
      issue(`富回答场景 ${scene.id} 的 histogram 必须提供 samples`);
    }
    if (spec.series !== undefined || spec.xLabels !== undefined) {
      issue(`富回答场景 ${scene.id} 的 histogram 只接受 samples/binCount，不接受 series/xLabels`);
    }
  } else {
    if (series.length === 0) {
      issue(`富回答场景 ${scene.id} 的 ${String(chartKind)} 图必须提供至少一个 series`);
    }
    if (chartKind === "scatter" && spec.xLabels !== undefined) {
      issue(`富回答场景 ${scene.id} 的 scatter 使用 series[].xValues，不接受分类 xLabels`);
    } else if (chartKind !== "scatter" && (xLabels === undefined || xLabels.length === 0)) {
      issue(`富回答场景 ${scene.id} 的 ${String(chartKind)} 图必须提供 xLabels`);
    }
    if (spec.samples !== undefined || spec.binCount !== undefined) {
      issue(`富回答场景 ${scene.id} 只有 histogram 能提交 samples 或 binCount`);
    }
  }

  if (dataPointCount > registration.budgets.maxDataPoints) {
    issue(
      `富回答场景 ${scene.id} 的图表数据点超出专业渲染器预算：${dataPointCount}/${registration.budgets.maxDataPoints}`,
    );
  }
  return dataPointCount;
}


export function validateRichAnswerMathFunctionSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  issue: (message: string) => void,
): number {
  const unknownSpecFields = richAnswerRenderPlanUnknownFields(spec, registration.allowedSpecFields);
  if (unknownSpecFields.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的函数 spec 只能使用 ${rendererFieldList(registration.allowedSpecFields)}，不能包含 ${unknownSpecFields.join("、")}`,
    );
  }
  const forbiddenPaths = richAnswerRenderPlanForbiddenFieldPaths(spec, registration);
  if (forbiddenPaths.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的函数 spec 包含禁止字段：${forbiddenPaths.join("、")}；只给表达式图、定义域和参数，不给采样点或渲染代码`,
    );
  }
  if (typeof spec.title !== "string" || spec.title.trim().length === 0) {
    issue(`富回答场景 ${scene.id} 的函数 spec.title 不能为空`);
  }
  if (typeof spec.variable !== "string" || spec.variable.trim().length === 0) {
    issue(`富回答场景 ${scene.id} 的函数 variable 不能为空`);
  }

  const domain = isRecord(spec.domain) ? spec.domain : undefined;
  if (domain === undefined) {
    issue(`富回答场景 ${scene.id} 的函数 domain 必须是对象`);
  } else {
    const unknownDomainFields = richAnswerRenderPlanUnknownFields(domain, ["minimum", "maximum"]);
    if (unknownDomainFields.length > 0) {
      issue(`富回答场景 ${scene.id} 的 domain 不能包含 ${unknownDomainFields.join("、")}`);
    }
    if (
      typeof domain.minimum !== "number" ||
      !Number.isFinite(domain.minimum) ||
      typeof domain.maximum !== "number" ||
      !Number.isFinite(domain.maximum) ||
      domain.minimum >= domain.maximum
    ) {
      issue(`富回答场景 ${scene.id} 的 domain 必须是有限数，且 minimum < maximum`);
    }
  }

  const rawParameters = spec.parameters === undefined
    ? []
    : Array.isArray(spec.parameters) ? spec.parameters : [];
  if (spec.parameters !== undefined && !Array.isArray(spec.parameters)) {
    issue(`富回答场景 ${scene.id} 的 parameters 必须是数组`);
  }
  if (rawParameters.length > 4) {
    issue(`富回答场景 ${scene.id} 最多提交 4 个可调参数`);
  }
  const parameterIDs = new Set<string>();
  for (const [index, parameter] of rawParameters.entries()) {
    if (!isRecord(parameter)) {
      issue(`富回答场景 ${scene.id} 的 parameters[${index}] 必须是对象`);
      continue;
    }
    const unknownParameterFields = richAnswerRenderPlanUnknownFields(
      parameter,
      ["id", "label", "value", "minimum", "maximum", "step", "unit"],
    );
    if (unknownParameterFields.length > 0) {
      issue(`富回答场景 ${scene.id} 的 parameters[${index}] 不能包含 ${unknownParameterFields.join("、")}`);
    }
    if (!richAnswerRenderPlanValidIdentifier(parameter.id)) {
      issue(`富回答场景 ${scene.id} 的 parameters[${index}].id 无效`);
    } else if (parameterIDs.has(parameter.id)) {
      issue(`富回答场景 ${scene.id} 的参数 id 重复：${parameter.id}`);
    } else {
      parameterIDs.add(parameter.id);
    }
    if (typeof parameter.label !== "string" || parameter.label.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 parameters[${index}].label 不能为空`);
    }
    const numericFields = ["value", "minimum", "maximum", "step"] as const;
    if (numericFields.some((field) => typeof parameter[field] !== "number" || !Number.isFinite(parameter[field]))) {
      issue(`富回答场景 ${scene.id} 的 parameters[${index}] 数值必须是有限数`);
      continue;
    }
    const minimum = parameter.minimum as number;
    const maximum = parameter.maximum as number;
    const value = parameter.value as number;
    const step = parameter.step as number;
    if (minimum >= maximum || step <= 0 || value < minimum || value > maximum) {
      issue(`富回答场景 ${scene.id} 的 parameters[${index}] 必须满足 minimum < maximum、step > 0 且 value 在范围内`);
    }
  }

  const expression = isRecord(spec.expression) ? spec.expression : undefined;
  if (expression === undefined) {
    issue(`富回答场景 ${scene.id} 的 expression 必须是表达式图对象`);
    return 1;
  }
  const unknownExpressionFields = richAnswerRenderPlanUnknownFields(expression, ["rootNodeID", "nodes"]);
  if (unknownExpressionFields.length > 0) {
    issue(`富回答场景 ${scene.id} 的 expression 不能包含 ${unknownExpressionFields.join("、")}`);
  }
  const nodes = Array.isArray(expression.nodes) ? expression.nodes : [];
  if (!Array.isArray(expression.nodes) || nodes.length === 0) {
    issue(`富回答场景 ${scene.id} 的 expression.nodes 不能为空`);
  }
  if (nodes.length > registration.budgets.maxNodes) {
    issue(`富回答场景 ${scene.id} 的表达式节点超出预算：${nodes.length}/${registration.budgets.maxNodes}`);
  }
  const nodeByID = new Map<string, Record<string, unknown>>();
  for (const [index, node] of nodes.entries()) {
    if (!isRecord(node)) {
      issue(`富回答场景 ${scene.id} 的 expression.nodes[${index}] 必须是对象`);
      continue;
    }
    const unknownNodeFields = richAnswerRenderPlanUnknownFields(
      node,
      ["id", "kind", "value", "parameterID", "operation", "inputIDs"],
    );
    if (unknownNodeFields.length > 0) {
      issue(`富回答场景 ${scene.id} 的 expression.nodes[${index}] 不能包含 ${unknownNodeFields.join("、")}`);
    }
    if (!richAnswerRenderPlanValidIdentifier(node.id)) {
      issue(`富回答场景 ${scene.id} 的 expression.nodes[${index}].id 无效`);
      continue;
    }
    if (nodeByID.has(node.id)) {
      issue(`富回答场景 ${scene.id} 的表达式节点 id 重复：${node.id}`);
      continue;
    }
    nodeByID.set(node.id, node);
  }

  for (const [nodeID, node] of nodeByID.entries()) {
    if (node.kind === "constant") {
      if (typeof node.value !== "number" || !Number.isFinite(node.value)) {
        issue(`富回答场景 ${scene.id} 的常数节点 ${nodeID} 必须有有限 value`);
      }
    } else if (node.kind === "parameter") {
      if (typeof node.parameterID !== "string" || !parameterIDs.has(node.parameterID)) {
        issue(`富回答场景 ${scene.id} 的参数节点 ${nodeID} 引用了不存在的 parameterID`);
      }
    } else if (node.kind === "operation") {
      const operation = typeof node.operation === "string" ? node.operation : "";
      const inputIDs = Array.isArray(node.inputIDs)
        ? node.inputIDs.filter((value): value is string => typeof value === "string")
        : [];
      const expectedInputs = RICH_ANSWER_MATH_UNARY_OPERATIONS.has(operation)
        ? 1
        : RICH_ANSWER_MATH_BINARY_OPERATIONS.has(operation) ? 2 : 0;
      if (expectedInputs === 0) {
        issue(`富回答场景 ${scene.id} 的运算节点 ${nodeID} 使用了未注册运算 ${operation || "空"}`);
      } else if (inputIDs.length !== expectedInputs) {
        issue(`富回答场景 ${scene.id} 的运算节点 ${nodeID} 需要 ${expectedInputs} 个 inputIDs`);
      }
      const missingInputs = inputIDs.filter((inputID) => !nodeByID.has(inputID));
      if (missingInputs.length > 0) {
        issue(`富回答场景 ${scene.id} 的运算节点 ${nodeID} 引用了不存在的节点：${missingInputs.join("、")}`);
      }
    } else if (node.kind !== "variable") {
      issue(`富回答场景 ${scene.id} 的节点 ${nodeID} kind 无效`);
    }
  }

  const rootNodeID = typeof expression.rootNodeID === "string" ? expression.rootNodeID : "";
  if (!rootNodeID || !nodeByID.has(rootNodeID)) {
    issue(`富回答场景 ${scene.id} 的 expression.rootNodeID 必须引用存在的节点`);
  } else {
    const visiting = new Set<string>();
    const visited = new Set<string>();
    const visit = (nodeID: string, depth: number): void => {
      if (visiting.has(nodeID)) {
        issue(`富回答场景 ${scene.id} 的表达式图存在循环：${nodeID}`);
        return;
      }
      if (visited.has(nodeID)) return;
      if (depth > 24) {
        issue(`富回答场景 ${scene.id} 的表达式图深度超过 24`);
        return;
      }
      const node = nodeByID.get(nodeID);
      if (!node) return;
      visiting.add(nodeID);
      if (Array.isArray(node.inputIDs)) {
        node.inputIDs.forEach((inputID) => {
          if (typeof inputID === "string") visit(inputID, depth + 1);
        });
      }
      visiting.delete(nodeID);
      visited.add(nodeID);
    };
    visit(rootNodeID, 0);
  }
  return 1;
}


export function richAnswerRenderPlanEstimatedNodes(spec: Record<string, unknown>, bindingCount: number, sourceCount: number): number {
  const seriesCount = Array.isArray(spec.series) ? spec.series.length : 0;
  const expressionNodeCount = isRecord(spec.expression) && Array.isArray(spec.expression.nodes)
    ? spec.expression.nodes.length
    : 0;
  const structuredNodeCount = [
    "points",
    "shapes",
    "controls",
    "readouts",
    "layers",
    "objects",
    "slices",
    "features",
    "annotations",
  ].reduce((count, field) => count + (Array.isArray(spec[field]) ? spec[field].length : 0), 0);
  return 1 + seriesCount + expressionNodeCount + structuredNodeCount + bindingCount + sourceCount;
}


export function richAnswerRenderPlanGenericDataPoints(value: unknown, field = ""): number {
  if (Array.isArray(value)) {
    if (["points", "values", "samples"].includes(field)) return value.length;
    if (field === "yValues") {
      return value.reduce(
        (count, row) => count + (Array.isArray(row) ? row.length : 0),
        0,
      );
    }
    return value.reduce(
      (count, item) => count + richAnswerRenderPlanGenericDataPoints(item),
      0,
    );
  }
  if (!isRecord(value)) return 0;
  return Object.entries(value).reduce(
    (count, [childField, child]) => count + richAnswerRenderPlanGenericDataPoints(child, childField),
    0,
  );
}


export function validateRichAnswerGenericRenderSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  issue: (message: string) => void,
): number {
  if (Object.keys(spec).length === 0) {
    issue(`富回答场景 ${scene.id} 的 ${registration.id} spec 不能为空`);
  }
  const unknownSpecFields = richAnswerRenderPlanUnknownFields(spec, registration.allowedSpecFields);
  if (unknownSpecFields.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的 ${registration.id} spec 只能使用高层字段 ${rendererFieldList(registration.allowedSpecFields)}，不能包含 ${unknownSpecFields.join("、")}`,
    );
  }
  const forbiddenPaths = richAnswerRenderPlanForbiddenFieldPaths(spec, registration);
  if (forbiddenPaths.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的 ${registration.id} spec 包含禁止字段：${forbiddenPaths.join("、")}；只能提交高层 JSON 语义，不能提交脚本、网页、SVG path 或外链`,
    );
  }
  const dataPointCount = richAnswerRenderPlanGenericDataPoints(spec);
  if (dataPointCount > registration.budgets.maxDataPoints) {
    issue(
      `富回答场景 ${scene.id} 的高层规格数据点超出渲染器预算：${dataPointCount}/${registration.budgets.maxDataPoints}`,
    );
  }
  return dataPointCount;
}


export function richAnswerRenderPlanFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}


export function richAnswerRenderPlanControlValue(value: unknown): value is number | string {
  return richAnswerRenderPlanFiniteNumber(value) || (
    typeof value === "string" &&
    value.trim().length > 0 &&
    value.length <= 80
  );
}


export function richAnswerValidateNestedFields(
  scene: RichAnswerSceneParam,
  value: unknown,
  allowedFields: readonly string[],
  path: string,
  issue: (message: string) => void,
): value is Record<string, unknown> {
  if (!isRecord(value)) {
    issue(`富回答场景 ${scene.id} 的 ${path} 必须是对象`);
    return false;
  }
  const unknownFields = richAnswerRenderPlanUnknownFields(value, allowedFields);
  if (unknownFields.length > 0) {
    issue(`富回答场景 ${scene.id} 的 ${path} 包含未知字段：${unknownFields.join("、")}`);
  }
  return true;
}


export function richAnswerNormalizeScene3DRange(
  value: unknown,
  path: string,
  normalizations: string[],
): unknown {
  if (
    Array.isArray(value) &&
    value.length === 2 &&
    value.every(richAnswerRenderPlanFiniteNumber) &&
    value[0] < value[1]
  ) {
    normalizations.push(`${path} 已由 [min,max] 归一化为 {min,max}`);
    return { min: value[0], max: value[1] };
  }
  if (
    isRecord(value) &&
    Object.keys(value).every((field) => ["minimum", "maximum"].includes(field)) &&
    richAnswerRenderPlanFiniteNumber(value.minimum) &&
    richAnswerRenderPlanFiniteNumber(value.maximum) &&
    value.minimum < value.maximum
  ) {
    normalizations.push(`${path} 已由 {minimum,maximum} 归一化为 {min,max}`);
    return { min: value.minimum, max: value.maximum };
  }
  return value;
}


export function normalizeRichAnswerScene3DSpec(
  scene: RichAnswerSceneParam,
): string[] {
  const plan = scene.renderPlan;
  if (!plan || plan.renderer !== "weibei.scene-3d" || !isRecord(plan.spec)) return [];

  const normalizations: string[] = [];
  const spec: Record<string, unknown> = { ...plan.spec };

  if (
    Array.isArray(spec.coordinateUnits) &&
    spec.coordinateUnits.length === 3 &&
    spec.coordinateUnits.every((value) => typeof value === "string" && value.trim().length > 0)
  ) {
    spec.coordinateUnits = {
      x: spec.coordinateUnits[0],
      y: spec.coordinateUnits[1],
      z: spec.coordinateUnits[2],
    };
    normalizations.push("spec.coordinateUnits 已由三项数组归一化为 {x,y,z}");
  }

  if (isRecord(spec.bounds)) {
    const bounds = { ...spec.bounds };
    for (const axis of ["x", "y", "z"] as const) {
      bounds[axis] = richAnswerNormalizeScene3DRange(
        bounds[axis],
        `spec.bounds.${axis}`,
        normalizations,
      );
    }
    spec.bounds = bounds;
  }

  if (isRecord(spec.stateBinding)) {
    const stateBinding = { ...spec.stateBinding };
    if (["select", "picker"].includes(String(stateBinding.control))) {
      stateBinding.control = "segmented";
      normalizations.push("spec.stateBinding.control 已归一化为 segmented");
    }
    spec.stateBinding = stateBinding;
  }

  if (isRecord(spec.controls)) {
    const controls: Record<string, unknown> = { ...spec.controls };
    const aliases: Record<string, string> = {
      layerToggle: "allowLayerToggle",
      slice: "allowSlice",
      cameraDrag: "allowCameraDrag",
      reset: "allowReset",
      probe: "allowProbe",
    };
    for (const [alias, canonical] of Object.entries(aliases)) {
      if (typeof controls[alias] !== "boolean" || controls[canonical] !== undefined) continue;
      controls[canonical] = controls[alias];
      delete controls[alias];
      normalizations.push(`spec.controls.${alias} 已归一化为 ${canonical}`);
    }

    const hasStateSelector = Array.isArray(spec.states) &&
      spec.states.length > 1 &&
      isRecord(spec.stateBinding);
    if (hasStateSelector) {
      for (const [field, value] of Object.entries(controls)) {
        if (
          value === true &&
          !["allowLayerToggle", "allowSlice", "allowCameraDrag", "allowReset", "allowProbe"].includes(field) &&
          /(?:select|selector)$/iu.test(field)
        ) {
          delete controls[field];
          normalizations.push(`spec.controls.${field} 已由 stateBinding 的通用状态选择器承接`);
        }
      }
    }
    spec.controls = controls;
  }

  plan.spec = spec as RichAnswerRenderPlanSpecParam;
  return normalizations;
}