import { realpathSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { PythonArtifactOperation, PythonArtifactOutputKind } from "./python-artifact";
import { evidenceLabels } from "./context-snapshot";


export const CONTEXT_FILE_ENV = "WEIBEI_AGENT_CONTEXT_FILE";


export const CONTEXT_TOOL = "weibei_context";


export const COURSE_MAP_TOOL = "weibei_course_map";


export const COURSE_SEARCH_TOOL = "weibei_course_search";


export const VISUAL_ASSET_TOOL = "weibei_visual_asset";


export const LEARNING_MEMORY_TOOL = "weibei_learning_memory";


export const LEARNING_UPDATE_TOOL = "weibei_learning_update";


export const NOTE_PROPOSAL_TOOL = "weibei_note_proposal";


export const READ_TOOL = "read";


export const RICH_ANSWER_CATALOG_TOOL = "weibei_ui_catalog";


export const COMPUTE_ARTIFACT_TOOL = "weibei_compute_artifact";


export const RICH_ANSWER_TOOL = "weibei_rich_answer";


export const ALLOWED_TOOLS = new Set([
  CONTEXT_TOOL,
  COURSE_MAP_TOOL,
  COURSE_SEARCH_TOOL,
  VISUAL_ASSET_TOOL,
  LEARNING_MEMORY_TOOL,
  LEARNING_UPDATE_TOOL,
  NOTE_PROPOSAL_TOOL,
  READ_TOOL,
  RICH_ANSWER_CATALOG_TOOL,
  COMPUTE_ARTIFACT_TOOL,
  RICH_ANSWER_TOOL,
]);


export const RICH_ANSWER_SKILLS = {
  "rich-answer-director": {
    name: "富回答导演",
    version: "1.0.0",
    description: "判断文本是否足够，明确学习目标、内联位置和应继续加载的专业指导。",
    trigger: "准备生成富回答时先加载；只做纯文本时不加载。",
    relativePath: "skills/rich-answer/rich-answer-director/SKILL.md",
  },
  "professional-visualization": {
    name: "专业可视化",
    version: "1.0.0",
    description: "比较标准图表、函数、二维三维、地图、图像覆盖与受控计算能力。",
    trigger: "题目涉及数据、函数、空间、原图或确定性实验时加载。",
    relativePath: "skills/rich-answer/professional-visualization/SKILL.md",
  },
  "deep-interaction-components": {
    name: "深交互组件",
    version: "1.0.0",
    description: "判断成熟深组件是否提供不可替代的实验、刷选、证据阅读或状态联动。",
    trigger: "目录返回成熟 program，且其联动可能比标准渲染器更有学习价值时加载。",
    relativePath: "skills/rich-answer/deep-interaction-components/SKILL.md",
  },
  "generative-composition": {
    name: "生成式组合",
    version: "1.0.0",
    description: "处理专业能力和成熟深组件都不覆盖的长尾高价值组合。",
    trigger: "确认前两条路线存在真实缺口后才加载。",
    relativePath: "skills/rich-answer/generative-composition/SKILL.md",
  },
} as const;


export type RichAnswerSkillID = keyof typeof RICH_ANSWER_SKILLS;


export interface SkillReadDetails {
  kind: "weibei_skill_read";
  contextRevision: string;
  loaded: {
    id: RichAnswerSkillID;
    name: string;
    version: string;
    sha256: string;
    byteCount: number;
    relativePath: string;
    loadedAtContextRevision: string;
  };
}


export const RICH_ANSWER_SKILL_BY_PATH = new Map(
  Object.entries(RICH_ANSWER_SKILLS).map(([id, skill]) => [
    realpathSync(resolve(fileURLToPath(new URL(`../${skill.relativePath}`, import.meta.url)))),
    { id: id as RichAnswerSkillID, ...skill },
  ]),
);


export function canonicalReadPath(value: unknown): string | undefined {
  if (typeof value !== "string" || !value.trim()) return undefined;
  try {
    return realpathSync(resolve(value));
  } catch {
    return undefined;
  }
}


export type AnswerFormPolicy = "automatic" | "textOnly" | "partialRichAllowed";


export const LIMITS = {
  contextFileBytes: 4 * 1024 * 1024,
  identifier: 256,
  title: 300,
  question: 4_000,
  materialText: 18_000,
  noteText: 6_000,
  selectionText: 2_000,
  recentMessages: 20,
  recentMessageText: 1_200,
  messageSource: 300,
  courseCatalogItems: 500,
  courseItems: 80,
  courseRelations: 500,
  courseMapPageItems: 60,
  courseSearchText: 2_400,
  courseHeadings: 12,
  courseTags: 16,
  courseLinkedItems: 24,
  learningMemories: 48,
  learningText: 500,
  learningEvidence: 400,
  sessionSummary: 2_000,
  proposalMarkdown: 24_000,
  proposalEvidenceItems: 16,
  proposalEvidenceText: 500,
  richAnswerNarrative: 3_200,
  richAnswerSummary: 600,
  richAnswerScenes: 3,
  richAnswerObjects: 24,
  richAnswerRelations: 32,
  richAnswerOperations: 8,
  richAnswerFrames: 6,
  richAnswerUINodes: 32,
  richAnswerUIRows: 64,
  richAnswerUIBindings: 4,
  richAnswerProgramSource: 10_000,
  richAnswerProgramCapabilities: 8,
  richAnswerRenderPlanSpecBytes: 16_000,
  richAnswerRenderPlanDataPoints: 240,
  richAnswerRenderPlanSeries: 8,
  richAnswerRenderPlanBindings: 8,
  richAnswerRenderPlanSourceBindings: 12,
  richAnswerRenderPlanArtifacts: 4,
  richAnswerRenderPlanNodes: 80,
  richAnswerRenderPlanText: 600,
  richAnswerRenderPlanTarget: 160,
  pythonArtifactInputBytes: 128_000,
  pythonArtifactOutputBytes: 256_000,
  pythonArtifactRows: 2_000,
  pythonArtifactColumns: 80,
  pythonArtifactRuntimeMS: 3_000,
  richAnswerEvidence: 12,
  richAnswerExcerpt: 600,
  richAnswerText: 800,
  visualAssetBytes: 6_000_000,
  visualAssets: 4,
} as const;


export interface SourceSnapshot {
  title: string;
  text: string;
  isTruncated: boolean;
}


export interface RecentMessageSnapshot {
  role: string;
  text: string;
  source?: string;
}


export interface CourseCatalogItemSnapshot {
  id: string;
  title: string;
  subtitle: string;
  kind: string;
  role: "material" | "note";
  isCurrentMaterial: boolean;
  isCurrentNote: boolean;
  linkedItemIDs: string[];
  tags: string[];
}


export interface CourseItemSnapshot extends CourseCatalogItemSnapshot {
  headings: string[];
  searchText: string;
  isTruncated: boolean;
}


export interface CourseRelationSnapshot {
  noteItemID: string;
  sourceItemID: string;
}


export interface CourseMapRelationSnapshot extends CourseRelationSnapshot {
  noteTitle: string;
  sourceTitle: string;
}


export interface CourseSnapshot {
  title: string;
  catalog: CourseCatalogItemSnapshot[];
  items: CourseItemSnapshot[];
  relations: CourseRelationSnapshot[];
  isTruncated: boolean;
}


export type LearningMemoryKind = "goal" | "understood" | "confusion" | "nextStep" | "preference";


export type LearningMemoryOrigin = "userStatement" | "agentInference" | "observed";


export interface LearningMemoryEntrySnapshot {
  id: string;
  kind: LearningMemoryKind;
  text: string;
  evidence: string;
  origin: LearningMemoryOrigin;
  status: "active" | "resolved";
  sessionID?: string;
  createdAt: number;
  updatedAt: number;
}


export interface StudyLocationSnapshot {
  itemID: string;
  itemTitle: string;
  locationID?: string;
  locationTitle?: string;
  pageIndex?: number;
  lastStudiedAt: number;
  visitCount: number;
}


export interface SessionSnapshot {
  id: string;
  title: string;
  summary: string;
  phase: string;
  focusItemIDs: string[];
  turnCount: number;
}


export interface LearningSnapshot {
  memoryRevision: number;
  lastLocation?: StudyLocationSnapshot;
  memories: LearningMemoryEntrySnapshot[];
  session?: SessionSnapshot;
}


export interface ContextSnapshotV2 {
  schemaVersion: 2;
  requestID: string;
  contextRevision: string;
  answerFormPolicy: AnswerFormPolicy;
  purpose: string;
  workflow: string;
  language: string;
  question: string;
  material?: SourceSnapshot;
  note: SourceSnapshot;
  selection?: SourceSnapshot;
  recentMessages: RecentMessageSnapshot[];
  course: CourseSnapshot;
  learning: LearningSnapshot;
}


export interface VisualAssetFileSnapshot {
  id: string;
  filePath: string;
  mediaType: "image/jpeg" | "image/png" | "image/webp";
}


export interface VisualAssetToolDetails {
  kind: "visual_asset_read";
  contextRevision: string;
  assetID: string;
  mediaType: VisualAssetFileSnapshot["mediaType"];
  sha256: string;
  byteCount: number;
}


export interface ContextToolDetails {
  kind: "weibei_context";
  schemaVersion: 2;
  contextRevision: string;
  snapshot: ContextSnapshotV2;
}


export interface CourseMapToolDetails {
  kind: "course_map";
  contextRevision: string;
  title: string;
  offset: number;
  limit: number;
  total: number;
  hasMore: boolean;
  catalog: Array<CourseCatalogItemSnapshot & { jumpReference: string }>;
  relations: CourseMapRelationSnapshot[];
  isTruncated: boolean;
}


export interface CourseSearchToolDetails {
  kind: "course_search";
  contextRevision: string;
  query: string;
  results: CourseItemSnapshot[];
  evidenceLabels: string[];
  jumpReferences: string[];
  jumpEvidence: Record<string, string>;
}


export interface LearningMemoryToolDetails {
  kind: "learning_memory";
  contextRevision: string;
  memoryRevision: number;
  learning: LearningSnapshot;
  jumpReferences: string[];
  jumpEvidence: Record<string, string>;
}


export interface LearningUpdateDetails {
  kind: "learning_update";
  contextRevision: string;
  memoryRevision: number;
  sessionSummary?: string;
  suggestedPhase?: string;
  suggestedNext: string[];
  entries: Array<{
    kind: LearningMemoryKind;
    text: string;
    evidence: string;
    origin: "userStatement" | "agentInference";
  }>;
  resolutions: Array<{
    memoryID: string;
    text: string;
    evidence: string;
  }>;
}


export interface NoteProposalDetails {
  kind: "note_proposal";
  markdown: string;
  evidence: string[];
  contextRevision: string;
}


export interface RichAnswerToolDetails {
  kind: "rich_answer";
  contextRevision: string;
  envelope: unknown;
  normalizations: string[];
}


// NOTE: 计算产物工具保持自己的 v1 生命周期；富回答外层只接受 v2。
export interface ComputeArtifactToolDetails {
  kind: "compute_artifact";
  schemaVersion: 1;
  contextRevision: string;
  requestID: string;
  operation: PythonArtifactOperation;
  workerVersion: string;
  pythonExecutable: string;
  requestSHA256: string;
  outputSHA256: string;
  durationMS: number;
  artifacts: Array<{
    id: string;
    kind: PythonArtifactOutputKind;
    mimeType: "application/json";
    role: string;
    sizeBytes: number;
    sha256: string;
    sourceEvidenceIDs: string[];
  }>;
  diagnostics: string[];
}


export type RichAnswerFaultCode =
  | "attempts_exhausted"
  | "context_required"
  | "stale_context"
  | "catalog_required"
  | "unknown_field"
  | "unknown_role"
  | "duplicate_id"
  | "narrative_flow"
  | "source_not_available"
  | "excerpt_mismatch"
  | "unauthorized_asset"
  | "scene_layer_choice"
  | "broken_reference"
  | "invalid_frame"
  | "invalid_binding"
  | "missing_evidence"
  | "invalid_openui_program"
  | "invalid_render_plan"
  | "invalid_t2_ui"
  | "weak_ui"
  | "invalid_plan";


export interface RichAnswerFaultInput {
  code: RichAnswerFaultCode;
  jsonPath: string;
  message: string;
  humanFixHint: string;
  sceneID?: string;
  nodeID?: string;
  field?: string;
  line?: number;
  column?: number;
}


export interface RichAnswerFaultPayload extends RichAnswerFaultInput {
  type: "weibei.rich_answer.repair_fault";
  remainingAttempts: number;
  mustDiscardRejectedPayload: true;
  mayPatchPreviousPayload: false;
  audience: "model_replanning_only";
  userVisibleFailureTextAllowed: false;
  preserveDiagnostic: {
    code: RichAnswerFaultCode;
    jsonPath: string;
    humanFixHint: string;
    sceneID?: string;
    nodeID?: string;
    field?: string;
    line?: number;
    column?: number;
  };
  replanningFeedback:
    | {
        mode: "repair";
        primarySignal: {
          code: RichAnswerFaultCode;
          meaning: string;
          requiredAction: string;
        };
        layerChoice: {
          allowed: Array<"program" | "renderPlan" | "ui">;
          chooseProgramWhen: string;
          chooseRenderPlanWhen: string;
          chooseUIWhen: string;
        };
        nextAttemptChecklist: string[];
        forbiddenActions: string[];
        pathSpecificRepair: string;
      }
    | {
        mode: "plain_text_fallback";
        primarySignal: {
          code: RichAnswerFaultCode;
          meaning: string;
          requiredAction: string;
        };
        forbiddenActions: string[];
      };
  nextSubmission:
    | "resubmit_complete_rich_answer_payload"
    | "stop_rich_answer_and_answer_plain_text";
  nextActionInstruction: string;
}


export class RichAnswerFaultError extends Error {
  constructor(readonly fault: RichAnswerFaultInput) {
    super(fault.message);
    this.name = "RichAnswerFaultError";
  }
}


export function richAnswerFault(input: RichAnswerFaultInput): never {
  throw new RichAnswerFaultError(input);
}


export function richAnswerNextActionInstruction(remainingAttempts: number): string {
  if (remainingAttempts <= 0) {
    return "三次富回答提交已耗尽：停止提交 weibei_rich_answer，改用普通文本诚实降级；正文只回答用户问题和真实限制，不得提富回答校验、协议失败、repair_fault、payload 或内部工具错误，也不能声称富回答已生成。";
  }
  return "丢弃被拒绝的坏 payload，下一次必须重新提交完整 weibei_rich_answer payload（schemaVersion、contextRevision、narrative、expressionPlan、完整 scenes、evidenceLedger、fallback 全部重发）；不能只解释原因，也不能在坏树基础上局部 patch。";
}


export function richAnswerPathSpecificRepair(input: RichAnswerFaultInput): string {
  if (input.jsonPath && input.jsonPath !== "$") {
    const target = [
      input.sceneID ? `sceneID=${input.sceneID}` : undefined,
      input.nodeID ? `nodeID=${input.nodeID}` : undefined,
      input.field ? `field=${input.field}` : undefined,
      input.line !== undefined ? `line=${input.line}` : undefined,
      input.column !== undefined ? `column=${input.column}` : undefined,
    ].filter(Boolean).join("，");
    return `先修 ${input.jsonPath}${target ? `（${target}）` : ""}：${input.humanFixHint}；然后检查同一层的所有引用、证据绑定和 narrative 场景标记，最后完整重发。`;
  }
  return `没有更深 jsonPath 时，不要猜局部补丁；根据 code=${input.code} 和 humanFixHint 重新规划整个表达层，再完整重发。`;
}


export function richAnswerLayerReplanHint(input: RichAnswerFaultInput): string {
  switch (input.code) {
    case "invalid_openui_program":
      return "当前 program 深组件未过受控程序校验：若只是签名、状态类型、引用或行列错误，按目录签名修正 program；若目录组件不贴合本题学习对象，重新选择 renderPlan 或 ui。";
    case "invalid_render_plan":
      return "当前 renderPlan 未过注册、版本、字段、安全、来源或预算校验：若知识形状仍匹配本轮注册专业渲染器，修正高层 spec 和绑定；若不匹配，重新选择 program 或 ui。";
    case "invalid_t2_ui":
      if (input.message.includes("超出预算")) {
        return "当前 ui 通用原语的表达层适合本题，但节点、数据行或 binding 超出硬预算：优先保留同一学习动作，减少采样行、合并共享数据集并删除无关 binding；不要只因为数量超限就换成 program。";
      }
      return "当前 ui 通用原语未通过节点、数据、binding、证据或资源边界校验：先按错误位置修正客观结构；若所选层确实不贴合当前学习动作，再改选 program、renderPlan 或更朴素的 ui。";
    case "weak_ui":
      return "当前回答的视觉表达质量需要重新规划：这类内容、形态和审美建议不再作为运行时硬拒绝；下一次优先保持来源结论正确，再让 Agent 自主选择 program、renderPlan、ui 或普通文本。";
    case "scene_layer_choice":
      return "每个 scene 必须只选一条表达出口：program、renderPlan 或 ui，不要同时提交、不要三条都空。";
    case "catalog_required":
      return "先重新调用 weibei_ui_catalog 取得本轮相关能力，再基于返回子集选择 program、renderPlan 或 ui。";
    default:
      return "先保留当前学习目标和来源结论，再按错误位置修复；如果修复会让所选出口变成硬凑或无法表达，重新在 program、renderPlan 与 ui 之间选择。";
  }
}


export function richAnswerReplanningFeedback(
  input: RichAnswerFaultInput,
  remainingAttempts: number,
): RichAnswerFaultPayload["replanningFeedback"] {
  const primarySignal = {
    code: input.code,
    meaning: input.message,
    requiredAction: remainingAttempts > 0
      ? `${richAnswerLayerReplanHint(input)} ${richAnswerPathSpecificRepair(input)}`
      : "停止调用富回答工具，直接正常回答用户问题；只说明真实材料限制，不得暴露校验、协议、payload、repair_fault 或内部工具错误。",
  };

  if (remainingAttempts <= 0) {
    return {
      mode: "plain_text_fallback",
      primarySignal,
      forbiddenActions: [
        "不要再次提交富回答或局部 patch。",
        "不要把富回答校验、协议失败、payload、repair_fault 或内部工具错误写进用户正文。",
        "不要声称富回答已经生成。",
      ],
    };
  }

  return {
    mode: "repair",
    primarySignal,
    layerChoice: {
      allowed: ["program", "renderPlan", "ui"],
      chooseProgramWhen: "目录返回的深组件签名能真实表达当前知识对象、状态联动和来源绑定，并且不需要自造组件、脚本、SVG、网页壳或任意配置。",
      chooseRenderPlanWhen: "本轮目录返回的注册专业渲染器匹配知识形状，且模型只需给高层 spec、交互绑定、来源绑定和质量预算，不需要 raw option、脚本、HTML 或 SVG path。",
      chooseUIWhen: "没有贴合的深组件或注册专业渲染器，或当前问题需要用受控节点、数据集、图层、binding、证据位置和读数组合成长尾形态。",
    },
    nextAttemptChecklist: [
      "先保持原问题的学习目标、专业结论和真实来源，不把修复变成换题或删减关键信息。",
      richAnswerLayerReplanHint(input),
      "remainingAttempts 仍大于 0，当前轮必须先完成一次完整富回答重试；只有次数耗尽，或重新核对后确认本轮来源/目录客观不足且继续生成会误导用户时，才停止工具并使用正常文本。",
      "expressionPlan 必须覆盖 scene.family、学习收益、交互结果、来源绑定和首选表面；scenes 必须与 narrative 的场景标记一一对应。",
      "program、renderPlan、ui 三选一；如果换出口，删除另外两条出口的全部字段，并同步 evidenceLedger、scene.evidenceIDs 和 narrative。",
      "完整重发 schemaVersion、contextRevision、narrative、expressionPlan、scenes、evidenceLedger、fallback；不要只补 jsonPath 那一个字段。",
    ],
    forbiddenActions: [
      "不要把“富回答校验失败”“协议未通过”“payload 错误”“repair_fault”写进用户正文。",
      "不要提交局部 patch、解释原因代替工具调用，或在坏 payload 上改几个字段继续赌。",
      "不要写 56 题 caseID、不要新增专属场景组件、不要把当前注册能力误当成永久技术名单。",
      "不要用自造 HTML、CSS、JavaScript、SVG path、网页外壳或装饰性卡片伪装成生成式 UI。",
    ],
    pathSpecificRepair: richAnswerPathSpecificRepair(input),
  };
}


export function richAnswerFaultMessage(
  input: RichAnswerFaultInput,
  remainingAttempts: number,
): string {
  const payload: RichAnswerFaultPayload = {
    type: "weibei.rich_answer.repair_fault",
    ...input,
    remainingAttempts,
    mustDiscardRejectedPayload: true,
    mayPatchPreviousPayload: false,
    audience: "model_replanning_only",
    userVisibleFailureTextAllowed: false,
    preserveDiagnostic: {
      code: input.code,
      jsonPath: input.jsonPath,
      humanFixHint: input.humanFixHint,
      sceneID: input.sceneID,
      nodeID: input.nodeID,
      field: input.field,
      line: input.line,
      column: input.column,
    },
    replanningFeedback: richAnswerReplanningFeedback(input, remainingAttempts),
    nextSubmission: remainingAttempts > 0
      ? "resubmit_complete_rich_answer_payload"
      : "stop_rich_answer_and_answer_plain_text",
    nextActionInstruction: richAnswerNextActionInstruction(remainingAttempts),
  };
  return JSON.stringify(payload, undefined, 2);
}


export function rethrowRichAnswerFault(error: unknown, remainingAttempts: number): never {
  if (error instanceof RichAnswerFaultError) {
    throw new Error(richAnswerFaultMessage(error.fault, remainingAttempts));
  }
  throw new Error(richAnswerFaultMessage({
    code: "invalid_plan",
    jsonPath: "$",
    message: error instanceof Error ? error.message : String(error),
    humanFixHint: "按错误位置重新生成完整富回答 payload；如果无法确定修复点，先重查目录并在 program、renderPlan 与 ui 之间重新选择；三次耗尽后停止富回答并正常回答用户问题，不暴露内部校验失败。",
  }, remainingAttempts));
}
