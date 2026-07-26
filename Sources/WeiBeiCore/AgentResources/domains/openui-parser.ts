import { richAnswerFault } from "./agent-context";
import {
  OPENUI_COMPONENT_ORDER,
  OPENUI_COMPONENT_SIGNATURES,
  OpenUIComponentName,
} from "./rich-answer-catalog";
import { RichAnswerSceneParam } from "./rich-answer-render-validation";


export type OpenUIValue =
  | { kind: "string"; value: string; column: number }
  | { kind: "number"; value: number; column: number }
  | { kind: "boolean"; value: boolean; column: number }
  | { kind: "null"; column: number }
  | { kind: "state"; name: string; column: number }
  | { kind: "reference"; id: string; column: number }
  | { kind: "array"; items: OpenUIValue[]; column: number };


export interface OpenUIStateDeclaration {
  kind: "stateDeclaration";
  name: string;
  value: OpenUIValue;
  line: number;
  column: number;
}


export interface OpenUIComponentDeclaration {
  kind: "componentDeclaration";
  id: string;
  component: OpenUIComponentName;
  arguments: OpenUIValue[];
  line: number;
  column: number;
}


export type OpenUIDeclaration = OpenUIStateDeclaration | OpenUIComponentDeclaration;


export type OpenUIArgumentRule =
  | { kind: "string"; values?: readonly string[]; nullable?: boolean; optional?: boolean }
  | { kind: "number"; integer?: boolean; minimum?: number; maximum?: number }
  | { kind: "boolean" }
  | {
      kind: "state";
      valueKind: "number" | "string" | "numberArray" | "stringArray";
      minimum?: number;
      maximum?: number;
    }
  | { kind: "reference"; components: readonly OpenUIComponentName[] }
  | { kind: "array"; item: OpenUIArgumentRule; minimum: number; maximum: number };


export const openUIString = (
  values?: readonly string[],
  nullable = false,
  optional = false,
): OpenUIArgumentRule => ({ kind: "string", values, nullable, optional });


export const openUINumber = (
  options: { integer?: boolean; minimum?: number; maximum?: number } = {},
): OpenUIArgumentRule => ({ kind: "number", ...options });


export const openUIBoolean = (): OpenUIArgumentRule => ({ kind: "boolean" });


export const openUIState = (
  valueKind: "number" | "string" | "numberArray" | "stringArray" = "number",
  options: { minimum?: number; maximum?: number } = {},
): OpenUIArgumentRule => ({ kind: "state", valueKind, ...options });


export const openUIReference = (...components: OpenUIComponentName[]): OpenUIArgumentRule => ({
  kind: "reference",
  components,
});


export const openUIArray = (
  item: OpenUIArgumentRule,
  minimum: number,
  maximum: number,
): OpenUIArgumentRule => ({ kind: "array", item, minimum, maximum });


export const OPENUI_LEARNING_BLOCK_COMPONENTS: readonly OpenUIComponentName[] = [
  "NarrativeBlock",
  "ParameterSlider",
  "ParameterReadout",
  "ValuePicker",
  "FunctionPlot",
  "ComparisonTable",
  "EvidenceSnippet",
  "ProcessStepper",
  "QuadraticMechanism",
  "FollowUpAction",
  "LinkedDataChart",
  "MetricStrip",
  "ExecutionTrack",
  "ArgumentReader",
  "CausalTrack",
  "TwoPointLineLab",
  "BalanceExperiment",
  "LayeredSpatialView",
  "DistributionBrush",
  "DependencyFlow",
];


export const OPENUI_COMPONENT_ARGUMENT_RULES: Record<
  OpenUIComponentName,
  readonly OpenUIArgumentRule[]
> = {
  RichAnswerRoot: [
    openUIString(),
    openUIString(),
    openUIString(),
    openUIString(["workbench", "comparison", "reasoning", "flow", "document", "timeline", "track"]),
    openUIArray(openUIReference("LearningStage"), 1, 8),
  ],
  LearningStage: [
    openUIString(["controls", "visual", "explanation", "evidence", "full"]),
    openUIString(undefined, true),
    openUIArray(openUIReference(...OPENUI_LEARNING_BLOCK_COMPONENTS), 1, 6),
  ],
  NarrativeBlock: [
    openUIString(),
    openUIString(),
    openUIString(["mechanism", "diagnosis", "neutral"]),
  ],
  ParameterSlider: [
    openUIString(),
    openUIString(),
    openUIState(),
    openUINumber(),
    openUINumber(),
    openUINumber(),
    openUIString(),
  ],
  ParameterReadout: [openUIString(), openUIState(), openUIString()],
  ValuePicker: [
    openUIString(),
    openUIString(),
    openUIState(),
    openUIArray(openUINumber(), 2, 8),
    openUIString(),
  ],
  FunctionPlot: [
    openUIString(),
    openUIString(["quadratic"]),
    openUIString(),
    openUIState(),
    openUIArray(openUINumber(), 0, 8),
    openUINumber(),
    openUINumber(),
    openUINumber({ integer: true, minimum: 220, maximum: 420 }),
  ],
  ComparisonRow: [openUIString(), openUINumber(), openUIString(), openUIString(), openUIString()],
  ComparisonTable: [
    openUIString(),
    openUIState(),
    openUIArray(openUIReference("ComparisonRow"), 2, 8),
  ],
  EvidenceSnippet: [openUIString(), openUIString(), openUIString(), openUIString()],
  ReasonStep: [openUIString(), openUIString()],
  ProcessStepper: [
    openUIString(),
    openUIState(),
    openUIArray(openUIReference("ReasonStep"), 2, 7),
  ],
  QuadraticMechanism: [openUIString(), openUIState(), openUINumber()],
  FollowUpAction: [openUIString(), openUIString()],
  ChartSeries: [
    openUIString(),
    openUIString(["line", "bar"]),
    openUIArray(openUINumber(), 2, 40),
    openUIString(),
    openUIString(["cinnabar", "jade", "ochre", "indigo", "umber", "moss"]),
  ],
  LinkedDataChart: [
    openUIString(),
    openUIState(),
    openUIString(),
    openUIArray(openUIString(), 2, 40),
    openUIArray(openUIReference("ChartSeries"), 1, 6),
    openUIString(),
    openUINumber({ integer: true, minimum: 220, maximum: 420 }),
  ],
  MetricItem: [
    openUIString(),
    openUIString(),
    openUIString(),
    openUIString(),
    openUIString(["neutral", "positive", "warning"]),
  ],
  MetricStrip: [openUIArray(openUIReference("MetricItem"), 2, 6)],
  ExecutionFrame: [
    openUIString(),
    openUINumber({ integer: true, minimum: 0, maximum: 80 }),
    openUIArray(openUIString(), 1, 16),
    openUIArray(openUINumber({ integer: true, minimum: 0, maximum: 15 }), 0, 8),
    openUIString(),
  ],
  ExecutionTrack: [
    openUIString(),
    openUIState(),
    openUIString(),
    openUIArray(openUIString(), 1, 40),
    openUIArray(openUIReference("ExecutionFrame"), 2, 48),
  ],
  ArgumentUnit: [
    openUIString(["claim", "reason", "evidence", "counter", "response", "context"]),
    openUIString(),
    openUIString(),
    openUIString(),
    openUIString(),
  ],
  ArgumentReader: [
    openUIString(),
    openUIState(),
    openUIString(),
    openUIArray(openUIReference("ArgumentUnit"), 2, 12),
  ],
  CausalEvent: [
    openUIString(),
    openUIString(),
    openUIString(["context", "trigger", "action", "result", "uncertain"]),
    openUIString(),
    openUIString(),
    openUIString(["strong", "medium", "insufficient"]),
    openUIString(),
    openUIString(),
  ],
  CausalTrack: [
    openUIString(),
    openUIState(),
    openUIString(),
    openUIArray(openUIReference("CausalEvent"), 2, 10),
  ],
  TwoPointLineLab: [
    openUIString(),
    openUIState(),
    openUIString(),
    openUIState(),
    openUIString(),
    openUIState(),
    openUIString(),
    openUIState(),
    openUIString(),
    openUINumber(),
    openUINumber(),
    openUINumber(),
    openUINumber(),
    openUINumber({ integer: true, minimum: 240, maximum: 420 }),
  ],
  BalanceExperiment: [
    openUIString(),
    openUIState(),
    openUIString(),
    openUIString(),
    openUIString(),
    openUIString(),
    openUIString(),
    openUIString(),
  ],
  SpatialLayer: [
    openUIString(),
    openUIString(),
    openUIString(["region", "path", "point"]),
    openUIBoolean(),
    openUIString(["stone", "water", "moss", "ochre", "cinnabar", "indigo"]),
  ],
  SpatialRegion: [
    openUIString(),
    openUIString(),
    openUIString(),
    openUIArray(openUINumber({ minimum: 0, maximum: 1 }), 6, 120),
    openUIString(["stone", "water", "moss", "ochre", "cinnabar", "indigo"]),
  ],
  SpatialPath: [
    openUIString(),
    openUIString(),
    openUIString(),
    openUIArray(openUINumber({ minimum: 0, maximum: 1 }), 4, 120),
    openUIString(["primary", "secondary", "dashed"]),
    openUIString(["stone", "water", "moss", "ochre", "cinnabar", "indigo"]),
  ],
  SpatialPoint: [
    openUIString(),
    openUIString(),
    openUIString(),
    openUINumber({ minimum: 0, maximum: 1 }),
    openUINumber({ minimum: 0, maximum: 1 }),
    openUIString(),
    openUIString(["context", "normal", "focus"]),
    openUIString(undefined, false, true),
  ],
  LayeredSpatialView: [
    openUIString(),
    openUIState("stringArray", { minimum: 1, maximum: 8 }),
    openUIString(),
    openUIState("string"),
    openUIString(),
    openUIArray(openUIReference("SpatialLayer"), 1, 8),
    openUIArray(openUIReference("SpatialRegion"), 0, 20),
    openUIArray(openUIReference("SpatialPath"), 0, 20),
    openUIArray(openUIReference("SpatialPoint"), 1, 30),
    openUINumber({ minimum: Number.MIN_VALUE }),
    openUIString(),
    openUIString(),
  ],
  DistributionBrush: [
    openUIString(),
    openUIState(),
    openUIString(),
    openUIState(),
    openUIString(),
    openUIArray(openUINumber(), 5, 240),
    openUIString(),
    openUINumber({ integer: true, minimum: 6, maximum: 30 }),
    openUIString(),
  ],
  FlowAssumption: [
    openUIString(),
    openUIString(),
    openUINumber(),
    openUINumber(),
    openUINumber({ minimum: Number.MIN_VALUE }),
    openUIString(),
    openUIString(),
  ],
  DependencyNode: [
    openUIString(),
    openUIString(),
    openUINumber({ integer: true, minimum: 1, maximum: 8 }),
    openUIString(["identity", "sum", "difference", "product", "ratio", "weightedSum", "power", "minimum", "maximum", "percentChange"]),
    openUIArray(openUIString(), 1, 6),
    openUIArray(openUINumber(), 0, 7),
    openUIString(),
    openUINumber({ integer: true, minimum: 0, maximum: 4 }),
    openUIString(),
  ],
  FlowMetric: [
    openUIString(),
    openUIString(),
    openUIString(),
    openUINumber({ integer: true, minimum: 0, maximum: 4 }),
    openUIString(["primary", "secondary", "warning"]),
    openUIString(),
  ],
  DependencyFlow: [
    openUIString(),
    openUIState("numberArray", { minimum: 1, maximum: 6 }),
    openUIString(),
    openUIState(),
    openUIString(),
    openUIArray(openUIReference("FlowAssumption"), 1, 6),
    openUIArray(openUIReference("DependencyNode"), 1, 24),
    openUIArray(openUIReference("FlowMetric"), 1, 6),
    openUIString(),
  ],
};


export function openUIComponentConstraintGuidance(name: OpenUIComponentName): string {
  const signature = OPENUI_COMPONENT_SIGNATURES[name];
  const openIndex = signature.indexOf("(");
  const closeIndex = signature.lastIndexOf(")");
  const argumentNames = signature
    .slice(openIndex + 1, closeIndex)
    .split(",")
    .map((argumentName) => argumentName.trim().replace(/^\$/u, "").replace(/\?$/u, ""));
  const descriptions = OPENUI_COMPONENT_ARGUMENT_RULES[name].flatMap((rule, index) => {
    const argumentName = argumentNames[index] ?? `arg${index + 1}`;
    switch (rule.kind) {
      case "string":
        return rule.values && rule.values.length > 0
          ? [`${argumentName}=${rule.values.map((value) => `"${value}"`).join("|")}`]
          : [];
      case "number": {
        if (rule.minimum === undefined && rule.maximum === undefined && !rule.integer) return [];
        const lower = rule.minimum === undefined ? "-∞" : String(rule.minimum);
        const upper = rule.maximum === undefined ? "+∞" : String(rule.maximum);
        return [`${argumentName}=${rule.integer ? "整数" : "数值"}[${lower},${upper}]`];
      }
      case "array": {
        const itemKind = rule.item.kind === "number"
          ? "数值"
          : rule.item.kind === "reference"
            ? `引用(${rule.item.components.join("|")})`
            : rule.item.kind;
        return [`${argumentName}=${itemKind}[${rule.minimum}–${rule.maximum}项]`];
      }
      default:
        return [];
    }
  });
  return descriptions.length > 0 ? `参数约束：${descriptions.join("；")}` : "";
}


export const OPENUI_CANVAS_COMPONENTS = new Set<OpenUIComponentName>([
  "FunctionPlot",
  "LinkedDataChart",
  "TwoPointLineLab",
  "LayeredSpatialView",
  "DistributionBrush",
]);


export const OPENUI_DIRECT_MANIPULATION_COMPONENTS = new Set<OpenUIComponentName>([
  "ParameterSlider",
  "ValuePicker",
  "FunctionPlot",
  "ProcessStepper",
  "FollowUpAction",
  "LinkedDataChart",
  "ExecutionTrack",
  "ArgumentReader",
  "CausalTrack",
  "TwoPointLineLab",
  "LayeredSpatialView",
  "DistributionBrush",
  "DependencyFlow",
]);


export function isOpenUIComponentName(value: string): value is OpenUIComponentName {
  return Object.prototype.hasOwnProperty.call(OPENUI_COMPONENT_SIGNATURES, value);
}


export function openUIProgramFailure(
  sceneID: string,
  message: string,
  fix: string,
  line?: number,
  column?: number,
): never {
  const location = line === undefined
    ? ""
    : `第 ${line} 行${column === undefined ? "" : `第 ${column} 列`}`;
  richAnswerFault({
    code: "invalid_openui_program",
    jsonPath: `$.scenes[?(@.id=="${sceneID}")].program.source`,
    sceneID,
    field: "program.source",
    line,
    column,
    message: `富回答场景 ${sceneID} 的 OpenUI${location}校验失败：${message}`,
    humanFixHint: `${fix}。修正后必须重发完整 RichAnswerUI，不能只提交该行或局部 patch。`,
  });
}


export class OpenUILineParser {
  private position = 0;

  constructor(
    private readonly sceneID: string,
    private readonly text: string,
    private readonly line: number,
  ) {}

  parse(): OpenUIDeclaration {
    this.skipWhitespace();
    if (this.peek() === "$") return this.parseStateDeclaration();
    return this.parseComponentDeclaration();
  }

  private parseStateDeclaration(): OpenUIStateDeclaration {
    const column = this.position + 1;
    this.position += 1;
    const name = this.parseIdentifier("状态名", false);
    this.expect("=", "状态声明必须使用 $name = number", "把状态写成 `$name = 0`");
    const value = this.parseValue();
    this.requireEnd();
    return { kind: "stateDeclaration", name, value, line: this.line, column };
  }

  private parseComponentDeclaration(): OpenUIComponentDeclaration {
    const column = this.position + 1;
    const id = this.parseIdentifier("组件 id", true);
    this.expect("=", "组件声明缺少等号", "按 `id = Component(...)` 重写这一行");
    const rawComponent = this.parseIdentifier("组件名", false);
    if (!isOpenUIComponentName(rawComponent)) {
      this.fail(
        `组件 ${rawComponent} 不在魏碑目录中`,
        `只使用工具提示列出的 ${OPENUI_COMPONENT_ORDER.length} 个组件名；不要自造整场景组件`,
      );
    }
    this.expect("(", `组件 ${rawComponent} 缺少参数括号`, `按 ${OPENUI_COMPONENT_SIGNATURES[rawComponent]} 重写`);
    const argumentsList: OpenUIValue[] = [];
    this.skipWhitespace();
    if (this.peek() !== ")") {
      while (true) {
        argumentsList.push(this.parseValue());
        this.skipWhitespace();
        if (this.peek() === ")") break;
        this.expect(",", `组件 ${rawComponent} 的参数之间缺少逗号`, `按 ${OPENUI_COMPONENT_SIGNATURES[rawComponent]} 重写`);
        this.skipWhitespace();
        if (this.peek() === ")") {
          this.fail("参数列表不能以逗号结尾", `删除 ${rawComponent} 最后一个参数后的逗号`);
        }
      }
    }
    this.expect(")", `组件 ${rawComponent} 的参数括号没有闭合`, `按 ${OPENUI_COMPONENT_SIGNATURES[rawComponent]} 重写`);
    this.requireEnd();
    return {
      kind: "componentDeclaration",
      id,
      component: rawComponent,
      arguments: argumentsList,
      line: this.line,
      column,
    };
  }

  private parseValue(): OpenUIValue {
    this.skipWhitespace();
    const column = this.position + 1;
    const character = this.peek();
    if (character === '"') return this.parseString();
    if (character === "$") {
      this.position += 1;
      return { kind: "state", name: this.parseIdentifier("状态引用", false), column };
    }
    if (character === "[") return this.parseArray();

    const numericMatch = this.text.slice(this.position).match(/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/u);
    if (numericMatch) {
      this.position += numericMatch[0].length;
      const value = Number(numericMatch[0]);
      if (!Number.isFinite(value)) {
        this.fail("数值参数不是有限数", "改成有限的十进制数字", column);
      }
      return { kind: "number", value, column };
    }

    const identifier = this.parseIdentifier("参数值", true);
    if (identifier === "true" || identifier === "false") {
      return { kind: "boolean", value: identifier === "true", column };
    }
    if (identifier === "null") return { kind: "null", column };
    this.skipWhitespace();
    if (this.peek() === "(") {
      this.fail("参数中不能嵌套调用组件", "先单独声明该组件，再用它的 id 作为引用", column);
    }
    return { kind: "reference", id: identifier, column };
  }

  private parseString(): OpenUIValue {
    const column = this.position + 1;
    const start = this.position;
    this.position += 1;
    while (this.position < this.text.length) {
      const character = this.text[this.position];
      if (character === "\\") {
        this.position += 2;
        continue;
      }
      this.position += 1;
      if (character !== '"') continue;
      const literal = this.text.slice(start, this.position);
      try {
        const value = JSON.parse(literal);
        if (typeof value !== "string") throw new Error("not a string");
        return { kind: "string", value, column };
      } catch {
        this.fail("字符串转义无效", "使用 JSON 双引号字符串，并正确转义引号和反斜杠", column);
      }
    }
    this.fail("字符串没有闭合", "在这一行补齐结束双引号", column);
  }

  private parseArray(): OpenUIValue {
    const column = this.position + 1;
    this.position += 1;
    const items: OpenUIValue[] = [];
    this.skipWhitespace();
    if (this.peek() === "]") {
      this.position += 1;
      return { kind: "array", items, column };
    }
    while (true) {
      items.push(this.parseValue());
      this.skipWhitespace();
      if (this.peek() === "]") {
        this.position += 1;
        return { kind: "array", items, column };
      }
      this.expect(",", "数组元素之间缺少逗号", "用逗号分隔数组元素");
      this.skipWhitespace();
      if (this.peek() === "]") {
        this.fail("数组不能以逗号结尾", "删除数组最后一个元素后的逗号");
      }
    }
  }

  private parseIdentifier(label: string, allowHyphen: boolean): string {
    this.skipWhitespace();
    const start = this.position;
    if (!/[A-Za-z]/u.test(this.peek() ?? "")) {
      this.fail(`${label} 必须以英文字母开头`, "使用只含英文字母、数字、下划线的名称");
    }
    this.position += 1;
    const continuation = allowHyphen ? /[A-Za-z0-9_-]/u : /[A-Za-z0-9_]/u;
    while (continuation.test(this.peek() ?? "")) this.position += 1;
    return this.text.slice(start, this.position);
  }

  private expect(character: string, message: string, fix: string): void {
    this.skipWhitespace();
    if (this.peek() !== character) this.fail(message, fix);
    this.position += 1;
  }

  private requireEnd(): void {
    this.skipWhitespace();
    if (this.position !== this.text.length) {
      this.fail("声明末尾有无法解析的多余内容", "一行只保留一个状态声明或组件声明，不要附加注释、代码块标记或表达式");
    }
  }

  private skipWhitespace(): void {
    while (/\s/u.test(this.peek() ?? "")) this.position += 1;
  }

  private peek(): string | undefined {
    return this.text[this.position];
  }

  private fail(message: string, fix: string, column = this.position + 1): never {
    return openUIProgramFailure(this.sceneID, message, fix, this.line, column);
  }
}


export function openUIArgumentName(component: OpenUIComponentName, index: number): string {
  const signature = OPENUI_COMPONENT_SIGNATURES[component];
  const start = signature.indexOf("(");
  return signature.slice(start + 1, -1).split(",").map((name) => name.trim())[index] ?? `参数 ${index + 1}`;
}


export function openUIRuleDescription(rule: OpenUIArgumentRule): string {
  switch (rule.kind) {
    case "string":
      if (rule.values) return `字符串枚举 ${rule.values.map((value) => `\"${value}\"`).join("|")}`;
      return rule.nullable ? "字符串或 null" : "字符串";
    case "number":
      return rule.integer ? "整数" : "数字";
    case "boolean":
      return "布尔值 true 或 false";
    case "state":
      switch (rule.valueKind) {
        case "number": return "$数字状态引用";
        case "string": return "$字符串状态引用";
        case "numberArray": return "$数字数组状态引用";
        case "stringArray": return "$字符串数组状态引用";
      }
    case "reference":
      return `${rule.components.join("|")} 的组件 id`;
    case "array":
      return `${openUIRuleDescription(rule.item)} 数组（${rule.minimum}–${rule.maximum} 项）`;
  }
}


export function validateOpenUIArgument(
  scene: RichAnswerSceneParam,
  declaration: OpenUIComponentDeclaration,
  value: OpenUIValue,
  rule: OpenUIArgumentRule,
  index: number,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
  componentsByID: ReadonlyMap<string, OpenUIComponentDeclaration>,
): void {
  const argumentName = openUIArgumentName(declaration.component, index);
  const expected = openUIRuleDescription(rule);
  const fail = (message: string): never => openUIProgramFailure(
    scene.id,
    `组件 ${declaration.id}（${declaration.component}）的 ${argumentName} ${message}`,
    `按 ${OPENUI_COMPONENT_SIGNATURES[declaration.component]} 提供 ${expected}`,
    declaration.line,
    value.column,
  );

  switch (rule.kind) {
    case "string":
      if (value.kind === "null" && rule.nullable) return;
      if (value.kind !== "string") fail(`应为${expected}`);
      if (rule.values && !rule.values.includes((value as Extract<OpenUIValue, { kind: "string" }>).value)) {
        fail(`只能是 ${rule.values.join("、")}，实际为 ${JSON.stringify((value as Extract<OpenUIValue, { kind: "string" }>).value)}`);
      }
      return;
    case "number":
      if (value.kind !== "number") fail(`应为${expected}`);
      if (rule.integer && !Number.isInteger((value as Extract<OpenUIValue, { kind: "number" }>).value)) fail("必须是整数");
      if (rule.minimum !== undefined && (value as Extract<OpenUIValue, { kind: "number" }>).value < rule.minimum) fail(`不能小于 ${rule.minimum}`);
      if (rule.maximum !== undefined && (value as Extract<OpenUIValue, { kind: "number" }>).value > rule.maximum) fail(`不能大于 ${rule.maximum}`);
      return;
    case "boolean":
      if (value.kind !== "boolean") fail(`应为${expected}`);
      return;
    case "state":
      if (value.kind !== "state") fail("必须写成 $stateName");
      {
        const stateName = (value as Extract<OpenUIValue, { kind: "state" }>).name;
        const state = statesByName.get(stateName);
        if (!state) fail(`引用了未声明状态 $${stateName}`);
        const stateValue = (state as OpenUIStateDeclaration).value;
        const arrayItems = stateValue.kind === "array" ? stateValue.items : [];
        const validKind =
          (rule.valueKind === "number" && stateValue.kind === "number") ||
          (rule.valueKind === "string" && stateValue.kind === "string") ||
          (rule.valueKind === "numberArray" && stateValue.kind === "array" && arrayItems.every((item) => item.kind === "number")) ||
          (rule.valueKind === "stringArray" && stateValue.kind === "array" && arrayItems.every((item) => item.kind === "string"));
        if (!validKind) fail(`引用的 $${stateName} 初值不符合${expected}`);
        if (stateValue.kind === "array") {
          if (rule.minimum !== undefined && stateValue.items.length < rule.minimum) {
            fail(`引用的 $${stateName} 至少需要 ${rule.minimum} 项`);
          }
          if (rule.maximum !== undefined && stateValue.items.length > rule.maximum) {
            fail(`引用的 $${stateName} 最多允许 ${rule.maximum} 项`);
          }
        }
      }
      return;
    case "reference": {
      if (value.kind !== "reference") fail(`应为${expected}`);
      const referenceID = (value as Extract<OpenUIValue, { kind: "reference" }>).id;
      const target = componentsByID.get(referenceID);
      if (!target) fail(`引用了不存在的组件 id ${referenceID}`);
      const resolvedTarget = target as OpenUIComponentDeclaration;
      if (!rule.components.includes(resolvedTarget.component)) {
        fail(`引用了 ${resolvedTarget.component} 组件 ${referenceID}，但这里只接受 ${rule.components.join("、")}`);
      }
      return;
    }
    case "array":
      if (value.kind !== "array") fail(`应为${expected}`);
      if ((value as Extract<OpenUIValue, { kind: "array" }>).items.length < rule.minimum ||
          (value as Extract<OpenUIValue, { kind: "array" }>).items.length > rule.maximum) {
        fail(`必须有 ${rule.minimum}–${rule.maximum} 项，实际为 ${(value as Extract<OpenUIValue, { kind: "array" }>).items.length} 项`);
      }
      (value as Extract<OpenUIValue, { kind: "array" }>).items.forEach((item) =>
        validateOpenUIArgument(scene, declaration, item, rule.item, index, statesByName, componentsByID)
      );
      return;
  }
}


export function openUIReferences(value: OpenUIValue): string[] {
  if (value.kind === "reference") return [value.id];
  if (value.kind === "array") return value.items.flatMap(openUIReferences);
  return [];
}


export function openUIStateReferences(value: OpenUIValue): string[] {
  if (value.kind === "state") return [value.name];
  if (value.kind === "array") return value.items.flatMap(openUIStateReferences);
  return [];
}


export function openUIStringValue(declaration: OpenUIComponentDeclaration, index: number): string {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "string" }>).value;
}


export function openUINumberValue(declaration: OpenUIComponentDeclaration, index: number): number {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "number" }>).value;
}


export function openUIBooleanValue(declaration: OpenUIComponentDeclaration, index: number): boolean {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "boolean" }>).value;
}


export function openUIStateName(declaration: OpenUIComponentDeclaration, index: number): string {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "state" }>).name;
}


export function openUIArrayItems(declaration: OpenUIComponentDeclaration, index: number): OpenUIValue[] {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "array" }>).items;
}


export function openUIStateInitialValue(
  declaration: OpenUIComponentDeclaration,
  argumentIndex: number,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
): number {
  const stateName = openUIStateName(declaration, argumentIndex);
  const state = statesByName.get(stateName)!;
  return (state.value as Extract<OpenUIValue, { kind: "number" }>).value;
}


export function openUIStringStateInitialValue(
  declaration: OpenUIComponentDeclaration,
  argumentIndex: number,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
): string {
  const stateName = openUIStateName(declaration, argumentIndex);
  const state = statesByName.get(stateName)!;
  return (state.value as Extract<OpenUIValue, { kind: "string" }>).value;
}


export function openUIArrayStateInitialValues(
  declaration: OpenUIComponentDeclaration,
  argumentIndex: number,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
): OpenUIValue[] {
  const stateName = openUIStateName(declaration, argumentIndex);
  const state = statesByName.get(stateName)!;
  return (state.value as Extract<OpenUIValue, { kind: "array" }>).items;
}


export function validateOpenUIReactiveName(
  scene: RichAnswerSceneParam,
  declaration: OpenUIComponentDeclaration,
  nameIndex: number,
  stateIndex: number,
): void {
  const declaredName = openUIStringValue(declaration, nameIndex);
  const stateName = openUIStateName(declaration, stateIndex);
  if (declaredName !== stateName) {
    openUIProgramFailure(
      scene.id,
      `组件 ${declaration.id} 的状态名 ${JSON.stringify(declaredName)} 与引用 $${stateName} 不一致`,
      `让名称参数与状态引用同名，例如 ${JSON.stringify(stateName)}, $${stateName}`,
      declaration.line,
      declaration.arguments[nameIndex].column,
    );
  }
}


export function validateOpenUIIndexedState(
  scene: RichAnswerSceneParam,
  declaration: OpenUIComponentDeclaration,
  stateIndex: number,
  itemCount: number,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
): void {
  const initialValue = openUIStateInitialValue(declaration, stateIndex, statesByName);
  if (!Number.isInteger(initialValue) || initialValue < 0 || initialValue >= itemCount) {
    openUIProgramFailure(
      scene.id,
      `组件 ${declaration.id} 的初始索引 ${initialValue} 不在 0–${itemCount - 1} 内`,
      `把 $${openUIStateName(declaration, stateIndex)} 初始化为有效整数索引`,
      declaration.line,
      declaration.arguments[stateIndex].column,
    );
  }
}