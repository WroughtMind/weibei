import { readFile } from "node:fs/promises";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@earendil-works/pi-ai";

const CONTEXT_FILE_ENV = "WEIBEI_AGENT_CONTEXT_FILE";
const CONTEXT_TOOL = "weibei_context";
const COURSE_MAP_TOOL = "weibei_course_map";
const COURSE_SEARCH_TOOL = "weibei_course_search";
const LEARNING_MEMORY_TOOL = "weibei_learning_memory";
const LEARNING_UPDATE_TOOL = "weibei_learning_update";
const NOTE_PROPOSAL_TOOL = "weibei_note_proposal";
const RICH_ANSWER_CATALOG_TOOL = "weibei_ui_catalog";
const RICH_ANSWER_TOOL = "weibei_rich_answer";
const ALLOWED_TOOLS = new Set([
  CONTEXT_TOOL,
  COURSE_MAP_TOOL,
  COURSE_SEARCH_TOOL,
  LEARNING_MEMORY_TOOL,
  LEARNING_UPDATE_TOOL,
  NOTE_PROPOSAL_TOOL,
  RICH_ANSWER_CATALOG_TOOL,
  RICH_ANSWER_TOOL,
]);

const LIMITS = {
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
  richAnswerEvidence: 12,
  richAnswerExcerpt: 600,
  richAnswerText: 800,
} as const;

interface SourceSnapshot {
  title: string;
  text: string;
  isTruncated: boolean;
}

interface RecentMessageSnapshot {
  role: string;
  text: string;
  source?: string;
}

interface CourseCatalogItemSnapshot {
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

interface CourseItemSnapshot extends CourseCatalogItemSnapshot {
  headings: string[];
  searchText: string;
  isTruncated: boolean;
}

interface CourseRelationSnapshot {
  noteItemID: string;
  sourceItemID: string;
}

interface CourseMapRelationSnapshot extends CourseRelationSnapshot {
  noteTitle: string;
  sourceTitle: string;
}

interface CourseSnapshot {
  title: string;
  catalog: CourseCatalogItemSnapshot[];
  items: CourseItemSnapshot[];
  relations: CourseRelationSnapshot[];
  isTruncated: boolean;
}

type LearningMemoryKind = "goal" | "understood" | "confusion" | "nextStep" | "preference";
type LearningMemoryOrigin = "userStatement" | "agentInference" | "observed";

interface LearningMemoryEntrySnapshot {
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

interface StudyLocationSnapshot {
  itemID: string;
  itemTitle: string;
  locationID?: string;
  locationTitle?: string;
  pageIndex?: number;
  lastStudiedAt: number;
  visitCount: number;
}

interface SessionSnapshot {
  id: string;
  title: string;
  summary: string;
  phase: string;
  focusItemIDs: string[];
  turnCount: number;
}

interface LearningSnapshot {
  memoryRevision: number;
  lastLocation?: StudyLocationSnapshot;
  memories: LearningMemoryEntrySnapshot[];
  session?: SessionSnapshot;
}

interface ContextSnapshotV2 {
  schemaVersion: 2;
  requestID: string;
  contextRevision: string;
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

interface ContextToolDetails {
  kind: "weibei_context";
  schemaVersion: 2;
  contextRevision: string;
  snapshot: ContextSnapshotV2;
}

interface CourseMapToolDetails {
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

interface CourseSearchToolDetails {
  kind: "course_search";
  contextRevision: string;
  query: string;
  results: CourseItemSnapshot[];
  evidenceLabels: string[];
  jumpReferences: string[];
  jumpEvidence: Record<string, string>;
}

interface LearningMemoryToolDetails {
  kind: "learning_memory";
  contextRevision: string;
  memoryRevision: number;
  learning: LearningSnapshot;
  jumpReferences: string[];
  jumpEvidence: Record<string, string>;
}

interface LearningUpdateDetails {
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

interface NoteProposalDetails {
  kind: "note_proposal";
  markdown: string;
  evidence: string[];
  contextRevision: string;
}

interface RichAnswerToolDetails {
  kind: "rich_answer";
  contextRevision: string;
  envelope: unknown;
}

type RichAnswerFaultCode =
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
  | "invalid_t2_ui"
  | "weak_ui"
  | "invalid_plan";

interface RichAnswerFaultInput {
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

interface RichAnswerFaultPayload extends RichAnswerFaultInput {
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
          allowed: Array<"program" | "ui" | "plain_text">;
          chooseProgramWhen: string;
          chooseUIWhen: string;
          choosePlainTextWhen: string;
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

class RichAnswerFaultError extends Error {
  constructor(readonly fault: RichAnswerFaultInput) {
    super(fault.message);
    this.name = "RichAnswerFaultError";
  }
}

function richAnswerFault(input: RichAnswerFaultInput): never {
  throw new RichAnswerFaultError(input);
}

function richAnswerNextActionInstruction(remainingAttempts: number): string {
  if (remainingAttempts <= 0) {
    return "三次富回答提交已耗尽：停止提交 weibei_rich_answer，改用普通文本诚实降级；正文只回答用户问题和真实限制，不得提富回答校验、协议失败、repair_fault、payload 或内部工具错误，也不能声称富回答已生成。";
  }
  return "丢弃被拒绝的坏 payload，下一次必须重新提交完整 weibei_rich_answer payload（schemaVersion、contextRevision、narrative、expressionPlan、完整 scenes、evidenceLedger、fallback 全部重发）；不能只解释原因，也不能在坏树基础上局部 patch。";
}

function richAnswerPathSpecificRepair(input: RichAnswerFaultInput): string {
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

function richAnswerLayerReplanHint(input: RichAnswerFaultInput): string {
  switch (input.code) {
    case "invalid_openui_program":
      return "当前 T1 program 未过受控程序校验：若只是签名、状态类型、引用或行列错误，按目录签名修正 T1；若目录组件不贴合本题学习对象，重新选择 T2 ui。";
    case "invalid_t2_ui":
    case "weak_ui":
      return "当前 T2 ui 未兑现知识对象、语义绑定、能力合同或交互结果：先对照错误里的可见语义摘要；未呈现的对象或关系用短标签、坐标、读数或序列补足，已由 binding 驱动图元或读数实现的互动不要逐字复制过程长句。若表达计划声明过度，收窄为 UI 实际编码的对象、关系和过程；若 T2 确实不贴合，再改选 T1 或更朴素的 T2。";
    case "scene_layer_choice":
      return "每个 scene 必须只选一层：选择 T1 program 或 T2 ui，不要同时提交、不要两层都空。";
    case "catalog_required":
      return "先重新调用 weibei_ui_catalog 取得本轮相关能力，再基于返回子集选择 T1 program 或 T2 ui。";
    default:
      return "先保留当前学习目标和来源结论，再按错误位置修复；如果修复会让所选层变成硬凑或无法表达，重新在 T1 program 与 T2 ui 之间选择。";
  }
}

function richAnswerReplanningFeedback(
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
      allowed: ["program", "ui", "plain_text"],
      chooseProgramWhen: "目录返回的 T1 深组件签名能真实表达当前知识对象、状态联动和来源绑定，并且不需要自造组件、脚本、SVG、网页壳或任意配置。",
      chooseUIWhen: "没有贴合的 T1 深组件，或当前问题需要用受控节点、数据集、图层、binding、证据位置和读数组合成长尾形态。",
      choosePlainTextWhen: "证据不足、目录能力不足、三次提交耗尽，或继续做 UI 会误导用户；文本要直接回答问题和限制，不提内部校验失败。",
    },
    nextAttemptChecklist: [
      "先保持原问题的学习目标、专业结论和真实来源，不把修复变成换题或删减关键信息。",
      richAnswerLayerReplanHint(input),
      "expressionPlan 必须覆盖 scene.family、学习收益、交互结果、来源绑定和首选表面；scenes 必须与 narrative 的场景标记一一对应。",
      "T1 program 与 T2 ui 二选一；如果换层，删除另一层全部字段，并同步 evidenceLedger、scene.evidenceIDs 和 narrative。",
      "完整重发 schemaVersion、contextRevision、narrative、expressionPlan、scenes、evidenceLedger、fallback；不要只补 jsonPath 那一个字段。",
    ],
    forbiddenActions: [
      "不要把“富回答校验失败”“协议未通过”“payload 错误”“repair_fault”写进用户正文。",
      "不要提交局部 patch、解释原因代替工具调用，或在坏 payload 上改几个字段继续赌。",
      "不要写 56 题 caseID、不要新增专属场景组件、不要固定某几个外部渲染器或技术栈名单。",
      "不要用自造 HTML、CSS、JavaScript、SVG path、网页外壳或装饰性卡片伪装成生成式 UI。",
    ],
    pathSpecificRepair: richAnswerPathSpecificRepair(input),
  };
}

function richAnswerFaultMessage(
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

function rethrowRichAnswerFault(error: unknown, remainingAttempts: number): never {
  if (error instanceof RichAnswerFaultError) {
    throw new Error(richAnswerFaultMessage(error.fault, remainingAttempts));
  }
  throw new Error(richAnswerFaultMessage({
    code: "invalid_plan",
    jsonPath: "$",
    message: error instanceof Error ? error.message : String(error),
    humanFixHint: "按错误位置重新生成完整富回答 payload；如果无法确定修复点，先重查目录并在 T1 program 与 T2 ui 之间重新选择；三次耗尽后停止富回答并正常回答用户问题，不暴露内部校验失败。",
  }, remainingAttempts));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requireRecord(value: unknown, field: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new Error(`魏碑上下文字段 ${field} 必须是对象`);
  }
  return value;
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new Error(`魏碑上下文字段 ${field} 必须是字符串`);
  }
  return value;
}

function requireBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new Error(`魏碑上下文字段 ${field} 必须是布尔值`);
  }
  return value;
}

function requireNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`魏碑上下文字段 ${field} 必须是数字`);
  }
  return value;
}

function requireIdentifier(value: unknown, field: string): string {
  const text = requireString(value, field);
  if (text.length === 0 || text.length > LIMITS.identifier) {
    throw new Error(`魏碑上下文字段 ${field} 长度无效`);
  }
  return text;
}

function truncate(text: string, maximumCharacters: number): string {
  if (text.length <= maximumCharacters) return text;

  let result = text.slice(0, maximumCharacters);
  const finalCodeUnit = result.charCodeAt(result.length - 1);
  if (finalCodeUnit >= 0xd800 && finalCodeUnit <= 0xdbff) {
    result = result.slice(0, -1);
  }
  return result;
}

function readSource(value: unknown, field: string, textLimit: number): SourceSnapshot {
  const source = requireRecord(value, field);
  const originalText = requireString(source.text, `${field}.text`);
  return {
    title: truncate(requireString(source.title, `${field}.title`), LIMITS.title),
    text: truncate(originalText, textLimit),
    isTruncated:
      requireBoolean(source.isTruncated, `${field}.isTruncated`) || originalText.length > textLimit,
  };
}

function readOptionalSource(value: unknown, field: string, textLimit: number): SourceSnapshot | undefined {
  if (value === undefined || value === null) return undefined;
  return readSource(value, field, textLimit);
}

function readRecentMessages(value: unknown): RecentMessageSnapshot[] {
  if (!Array.isArray(value)) {
    throw new Error("魏碑上下文字段 recentMessages 必须是数组");
  }

  return value.slice(-LIMITS.recentMessages).map((entry, index) => {
    const message = requireRecord(entry, `recentMessages[${index}]`);
    const source = message.source;
    return {
      role: requireIdentifier(message.role, `recentMessages[${index}].role`),
      text: truncate(
        requireString(message.text, `recentMessages[${index}].text`),
        LIMITS.recentMessageText,
      ),
      source:
        source === undefined || source === null
          ? undefined
          : truncate(requireString(source, `recentMessages[${index}].source`), LIMITS.messageSource),
    };
  });
}

function readStringArray(
  value: unknown,
  field: string,
  maximumItems: number,
  maximumCharacters: number,
): string[] {
  if (!Array.isArray(value)) {
    throw new Error(`魏碑上下文字段 ${field} 必须是数组`);
  }
  return value
    .slice(0, maximumItems)
    .map((item, index) => truncate(requireString(item, `${field}[${index}]`), maximumCharacters));
}

function readCourseCatalogItem(
  item: Record<string, unknown>,
  field: string,
): CourseCatalogItemSnapshot {
  const role = requireString(item.role, `${field}.role`);
  if (role !== "material" && role !== "note") {
    throw new Error(`${field}.role 无效`);
  }
  return {
    id: requireIdentifier(item.id, `${field}.id`),
    title: truncate(requireString(item.title, `${field}.title`), LIMITS.title),
    subtitle: truncate(requireString(item.subtitle, `${field}.subtitle`), LIMITS.title),
    kind: requireIdentifier(item.kind, `${field}.kind`),
    role,
    isCurrentMaterial: requireBoolean(item.isCurrentMaterial, `${field}.isCurrentMaterial`),
    isCurrentNote: requireBoolean(item.isCurrentNote, `${field}.isCurrentNote`),
    linkedItemIDs: readStringArray(
      item.linkedItemIDs,
      `${field}.linkedItemIDs`,
      LIMITS.courseLinkedItems,
      LIMITS.identifier,
    ),
    tags: readStringArray(item.tags, `${field}.tags`, LIMITS.courseTags, 64),
  };
}

function readCourse(value: unknown): CourseSnapshot {
  const course = requireRecord(value, "course");
  if (
    !Array.isArray(course.catalog) ||
    !Array.isArray(course.items) ||
    !Array.isArray(course.relations)
  ) {
    throw new Error("魏碑课程快照缺少 catalog、items 或 relations");
  }
  const catalog = course.catalog.slice(0, LIMITS.courseCatalogItems).map((entry, index) => {
    const field = `course.catalog[${index}]`;
    return readCourseCatalogItem(requireRecord(entry, field), field);
  });
  const catalogIDs = new Set<string>();
  catalog.forEach((item, index) => {
    if (catalogIDs.has(item.id)) {
      throw new Error(`course.catalog[${index}].id 与已有 catalog ID 重复`);
    }
    catalogIDs.add(item.id);
  });
  const items = course.items.slice(0, LIMITS.courseItems).map((entry, index) => {
    const field = `course.items[${index}]`;
    const item = requireRecord(entry, field);
    const parsedItem = {
      ...readCourseCatalogItem(item, field),
      headings: readStringArray(
        item.headings,
        `${field}.headings`,
        LIMITS.courseHeadings,
        200,
      ),
      searchText: truncate(
        requireString(item.searchText, `${field}.searchText`),
        LIMITS.courseSearchText,
      ),
      isTruncated: requireBoolean(item.isTruncated, `${field}.isTruncated`),
    } satisfies CourseItemSnapshot;
    if (!catalogIDs.has(parsedItem.id)) {
      throw new Error(`${field}.id 在 catalog 中不存在`);
    }
    return parsedItem;
  });
  const relations = course.relations
    .slice(0, LIMITS.courseRelations)
    .map((entry, index) => {
      const relation = requireRecord(entry, `course.relations[${index}]`);
      const parsedRelation = {
        noteItemID: requireIdentifier(
          relation.noteItemID,
          `course.relations[${index}].noteItemID`,
        ),
        sourceItemID: requireIdentifier(
          relation.sourceItemID,
          `course.relations[${index}].sourceItemID`,
        ),
      };
      if (
        !catalogIDs.has(parsedRelation.noteItemID) ||
        !catalogIDs.has(parsedRelation.sourceItemID)
      ) {
        throw new Error(`course.relations[${index}] 引用了 catalog 中不存在的 ID`);
      }
      return parsedRelation;
    });
  return {
    title: truncate(requireString(course.title, "course.title"), LIMITS.title),
    catalog,
    items,
    relations,
    isTruncated:
      requireBoolean(course.isTruncated, "course.isTruncated") ||
      course.catalog.length > catalog.length ||
      course.items.length > items.length ||
      course.relations.length > relations.length,
  };
}

function readLearning(value: unknown): LearningSnapshot {
  const learning = requireRecord(value, "learning");
  if (!Array.isArray(learning.memories)) {
    throw new Error("魏碑学习记忆字段 memories 必须是数组");
  }
  const allowedKinds = new Set<LearningMemoryKind>([
    "goal",
    "understood",
    "confusion",
    "nextStep",
    "preference",
  ]);
  const allowedOrigins = new Set<LearningMemoryOrigin>([
    "userStatement",
    "agentInference",
    "observed",
  ]);
  const memories = learning.memories.slice(0, LIMITS.learningMemories).map((entry, index) => {
    const memory = requireRecord(entry, `learning.memories[${index}]`);
    const kind = requireString(memory.kind, `learning.memories[${index}].kind`) as LearningMemoryKind;
    const origin = requireString(
      memory.origin,
      `learning.memories[${index}].origin`,
    ) as LearningMemoryOrigin;
    const status = requireString(memory.status, `learning.memories[${index}].status`);
    if (!allowedKinds.has(kind) || !allowedOrigins.has(origin) || !["active", "resolved"].includes(status)) {
      throw new Error(`learning.memories[${index}] 枚举值无效`);
    }
    return {
      id: requireIdentifier(memory.id, `learning.memories[${index}].id`),
      kind,
      text: truncate(
        requireString(memory.text, `learning.memories[${index}].text`),
        LIMITS.learningText,
      ),
      evidence: truncate(
        requireString(memory.evidence, `learning.memories[${index}].evidence`),
        LIMITS.learningEvidence,
      ),
      origin,
      status: status as "active" | "resolved",
      sessionID:
        memory.sessionID === undefined || memory.sessionID === null
          ? undefined
          : requireIdentifier(memory.sessionID, `learning.memories[${index}].sessionID`),
      createdAt: requireNumber(memory.createdAt, `learning.memories[${index}].createdAt`),
      updatedAt: requireNumber(memory.updatedAt, `learning.memories[${index}].updatedAt`),
    } satisfies LearningMemoryEntrySnapshot;
  });

  let lastLocation: StudyLocationSnapshot | undefined;
  if (learning.lastLocation !== undefined && learning.lastLocation !== null) {
    const location = requireRecord(learning.lastLocation, "learning.lastLocation");
    lastLocation = {
      itemID: requireIdentifier(location.itemID, "learning.lastLocation.itemID"),
      itemTitle: truncate(requireString(location.itemTitle, "learning.lastLocation.itemTitle"), LIMITS.title),
      locationID:
        location.locationID === undefined || location.locationID === null
          ? undefined
          : requireIdentifier(location.locationID, "learning.lastLocation.locationID"),
      locationTitle:
        location.locationTitle === undefined || location.locationTitle === null
          ? undefined
          : truncate(requireString(location.locationTitle, "learning.lastLocation.locationTitle"), LIMITS.title),
      pageIndex:
        location.pageIndex === undefined || location.pageIndex === null
          ? undefined
          : Math.max(0, Math.trunc(requireNumber(location.pageIndex, "learning.lastLocation.pageIndex"))),
      lastStudiedAt: requireNumber(location.lastStudiedAt, "learning.lastLocation.lastStudiedAt"),
      visitCount: Math.max(1, Math.trunc(requireNumber(location.visitCount, "learning.lastLocation.visitCount"))),
    };
  }

  let session: SessionSnapshot | undefined;
  if (learning.session !== undefined && learning.session !== null) {
    const rawSession = requireRecord(learning.session, "learning.session");
    session = {
      id: requireIdentifier(rawSession.id, "learning.session.id"),
      title: truncate(requireString(rawSession.title, "learning.session.title"), LIMITS.title),
      summary: truncate(
        requireString(rawSession.summary, "learning.session.summary"),
        LIMITS.sessionSummary,
      ),
      phase: requireIdentifier(rawSession.phase, "learning.session.phase"),
      focusItemIDs: readStringArray(
        rawSession.focusItemIDs,
        "learning.session.focusItemIDs",
        LIMITS.courseLinkedItems,
        LIMITS.identifier,
      ),
      turnCount: Math.max(0, Math.trunc(requireNumber(rawSession.turnCount, "learning.session.turnCount"))),
    };
  }

  return {
    memoryRevision: Math.max(0, Math.trunc(requireNumber(learning.memoryRevision, "learning.memoryRevision"))),
    lastLocation,
    memories,
    session,
  };
}

async function readCurrentSnapshot(): Promise<ContextSnapshotV2> {
  const contextFile = process.env[CONTEXT_FILE_ENV]?.trim();
  if (!contextFile) {
    throw new Error(`缺少环境变量 ${CONTEXT_FILE_ENV}`);
  }

  let data: Buffer;
  try {
    data = await readFile(contextFile);
  } catch {
    throw new Error(`${CONTEXT_FILE_ENV} 指向的上下文文件无法读取`);
  }

  if (data.byteLength > LIMITS.contextFileBytes) {
    throw new Error("魏碑上下文文件超过大小限制");
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(data.toString("utf8")) as unknown;
  } catch {
    throw new Error("魏碑上下文文件不是合法 JSON");
  }

  const envelope = requireRecord(parsed, "root");
  if (envelope.schemaVersion !== 2) {
    throw new Error("魏碑上下文仅支持 schemaVersion=2");
  }

  return {
    schemaVersion: 2,
    requestID: requireIdentifier(envelope.requestID, "requestID"),
    contextRevision: requireIdentifier(envelope.contextRevision, "contextRevision"),
    purpose: requireIdentifier(envelope.purpose, "purpose"),
    workflow: requireIdentifier(envelope.workflow, "workflow"),
    language: requireIdentifier(envelope.language, "language"),
    question: truncate(requireString(envelope.question, "question"), LIMITS.question),
    material: readOptionalSource(envelope.material, "material", LIMITS.materialText),
    note: readSource(envelope.note, "note", LIMITS.noteText),
    selection: readOptionalSource(envelope.selection, "selection", LIMITS.selectionText),
    recentMessages: readRecentMessages(envelope.recentMessages),
    course: readCourse(envelope.course),
    learning: readLearning(envelope.learning),
  };
}

function contextRevisionFromDetails(details: unknown): string | undefined {
  if (!isRecord(details)) return undefined;
  return typeof details.contextRevision === "string" ? details.contextRevision : undefined;
}

function evidenceLabels(snapshot: ContextSnapshotV2): string[] {
  const labels: string[] = [];
  if (snapshot.note.text.trim()) labels.push(`[笔记：${snapshot.note.title}]`);
  if (snapshot.material?.text.trim()) labels.push(`[材料：${snapshot.material.title}]`);
  if (snapshot.selection?.text.trim()) labels.push(`[选区：${snapshot.selection.title}]`);
  return labels;
}

function currentTurnEvidenceMatches(snapshot: ContextSnapshotV2, evidence: string): boolean {
  const statement = currentTurnEvidenceStatement(evidence);
  if (!statement || statement.length < 2) return false;
  const normalize = (value: string) => value.replace(/[\p{P}\p{Z}\s]/gu, "");
  if (statement.length < 4) return normalize(statement) === normalize(snapshot.question);
  let searchStart = 0;
  while (searchStart < snapshot.question.length) {
    const index = snapshot.question.indexOf(statement, searchStart);
    if (index < 0) return false;
    const end = index + statement.length;
    const before = index === 0 ? "" : snapshot.question[index - 1];
    const after = end >= snapshot.question.length ? "" : snapshot.question[end];
    const isBoundary = (value: string) => !value || /[\p{P}\p{Z}\s]/u.test(value);
    const prefix = snapshot.question.slice(0, index).toLowerCase();
    const immediate = prefix.trimEnd();
    const immediateNegation = ["不", "没", "未", "无", "别", "勿"]
      .some((term) => immediate.endsWith(term));
    const clause = prefix.split(/[，,。！？；;:：.!?]/u).at(-1) ?? prefix;
    const paddedClause = ` ${clause} `;
    const negativePhrases = [
      "不想", "不喜欢", "不太", "不能", "不会", "不要", "不愿", "没有", "没法", "尚未", "还没", "并不", "并非",
      " not ", " never ", " no ", " without ", "cannot", "can't", "don't", "doesn't", "didn't",
    ];
    if (
      isBoundary(before) &&
      isBoundary(after) &&
      !immediateNegation &&
      !negativePhrases.some((term) => paddedClause.includes(term))
    ) {
      return true;
    }
    searchStart = end;
  }
  return false;
}

function resolutionEvidenceMatches(snapshot: ContextSnapshotV2, evidence: string): boolean {
  if (!currentTurnEvidenceMatches(snapshot, evidence)) return false;
  const statement = currentTurnEvidenceStatement(evidence);
  if (!statement) return false;
  const value = statement.toLowerCase();
  const unresolvedTerms = [
    "不懂", "不理解", "不会", "没懂", "仍然困惑", "还是困惑", "不知道", "不能区分", "不能够",
    "还不能", "尚不能", "无法", "没法", "尚未", "还没", "并不", "不太", "不确定",
    "不正确", "并非正确", "答错", "错误", "不对",
    "don't understand", "do not understand", "can't", "cannot", "still confused", "not sure",
    "not able", "unable", "not yet", "have not", "haven't", "incorrect", "not correct", "wrong answer", "is wrong",
  ];
  if (unresolvedTerms.some((term) => value.includes(term))) return false;
  const questionTerms = ["什么", "为什么", "怎么", "为何", "吗", "？", "?", "what", "why", "how"];
  if (questionTerms.some((term) => value.includes(term))) return false;
  const masteryTerms = [
    "懂了", "明白了", "会了", "掌握了", "可以区分", "能够区分", "能解释", "答对", "正确",
    "解决了", "不再困惑", "understand now", "got it", "can distinguish", "can explain", "correct",
  ];
  if (masteryTerms.some((term) => value.includes(term))) return true;
  const answerMarkers = [
    "是", "指", "因为", "所以", "而", "但是", "扣除", "等于", "相比", "表示", "反映", "意味着", "即", "=",
    " is ", " means", "because", "therefore", "while", "equals", "represents", "reflects", "differs",
  ];
  if (!answerMarkers.some((term) => value.includes(term))) return false;
  return (statement.match(/[\p{L}\p{N}]/gu) ?? []).length >= 12;
}

function currentTurnEvidenceStatement(evidence: string): string | undefined {
  const prefix = evidence.startsWith("[用户：本轮]")
    ? "[用户：本轮]"
    : evidence.startsWith("[会话：当前]")
      ? "[会话：当前]"
      : undefined;
  if (!prefix) return undefined;
  const statement = evidence
    .slice(prefix.length)
    .trim()
    .replace(/^["'“”‘’]+|["'“”‘’]+$/g, "")
    .trim();
  return statement || undefined;
}

function courseSearchTerms(query: string): string[] {
  const lower = query.toLowerCase();
  const terms: string[] = lower.match(/[\p{L}\p{N}_-]{2,}/gu) ?? [];
  const chineseRuns: string[] = lower.match(/[\u4e00-\u9fff]{2,}/g) ?? [];
  for (const run of chineseRuns) {
    if (run.length <= 20) terms.push(run);
    for (let index = 0; index < run.length - 1; index += 1) {
      terms.push(run.slice(index, index + 2));
    }
  }
  return Array.from(new Set(terms)).sort((left, right) => right.length - left.length);
}

function searchCourse(course: CourseSnapshot, query: string, limit: number): CourseItemSnapshot[] {
  const terms = courseSearchTerms(query);
  return course.items
    .map((item, index) => {
      const title = `${item.title} ${item.subtitle} ${item.headings.join(" ")} ${item.tags.join(" ")}`.toLowerCase();
      const body = item.searchText.toLowerCase();
      const score = terms.reduce((total, term) => {
        const titleMatches = title.split(term).length - 1;
        const bodyMatches = Math.min(body.split(term).length - 1, 8);
        return total + titleMatches * 8 + bodyMatches;
      }, item.isCurrentMaterial || item.isCurrentNote ? 1 : 0);
      return { item, index, score };
    })
    .filter((entry) => entry.score > 0 || terms.length === 0)
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .slice(0, limit)
    .map((entry) => entry.item);
}

function courseJumpReference(
  course: CourseSnapshot,
  item: CourseCatalogItemSnapshot,
  rawHeading?: string,
): string {
  const duplicateTitle = course.catalog.filter((candidate) => candidate.title === item.title).length > 1;
  const ordinal = course.catalog.findIndex((candidate) => candidate.id === item.id) + 1;
  const ordinalSuffix = duplicateTitle && ordinal > 0 ? `，条目：${ordinal}` : "";
  const page = rawHeading ? coursePage(rawHeading) : undefined;
  const heading = rawHeading && !page ? courseHeading(rawHeading) : undefined;
  const pageSuffix = page ? `，第 ${page} 页` : "";
  const sectionLocationSuffix = heading?.locationID ? `，章节标识：${heading.locationID}` : "";
  const sectionOrdinalSuffix = heading?.ordinal ? `，章节序号：${heading.ordinal}` : "";
  const sectionSuffix = heading?.title ? `，章节：${heading.title}` : "";
  return `来源：${item.title}${ordinalSuffix}${pageSuffix}${sectionLocationSuffix}${sectionOrdinalSuffix}${sectionSuffix}`;
}

function courseEvidenceLabel(
  course: CourseSnapshot,
  item: CourseCatalogItemSnapshot,
): string {
  const duplicateTitle = course.catalog.filter((candidate) => candidate.title === item.title).length > 1;
  const ordinal = course.catalog.findIndex((candidate) => candidate.id === item.id) + 1;
  const ordinalSuffix = duplicateTitle && ordinal > 0 ? `，条目：${ordinal}` : "";
  return item.role === "note"
    ? `[笔记：${item.title}${ordinalSuffix}]`
    : `[材料：${item.title}${ordinalSuffix}]`;
}

function courseHeading(rawHeading: string): { title: string; ordinal?: number; locationID?: string } {
  const stableMatch = rawHeading.match(/^\[(html-section-[A-Za-z0-9-]+)\]\[html-heading-(\d+)\]\s+(.+)$/);
  if (stableMatch) {
    return {
      title: stableMatch[3],
      ordinal: Number(stableMatch[2]) + 1,
      locationID: stableMatch[1],
    };
  }
  const stableOnlyMatch = rawHeading.match(/^\[(html-section-[A-Za-z0-9-]+)\]\s+(.+)$/);
  if (stableOnlyMatch) return { title: stableOnlyMatch[2], locationID: stableOnlyMatch[1] };
  const legacyMatch = rawHeading.match(/^\[html-heading-(\d+)\]\s+(.+)$/);
  if (!legacyMatch) return { title: rawHeading };
  return { title: legacyMatch[2], ordinal: Number(legacyMatch[1]) + 1 };
}

function coursePage(rawHeading: string): number | undefined {
  const match = rawHeading.match(/^第\s*(\d+)\s*页(?:（OCR）)?$/);
  if (!match) return undefined;
  const page = Number(match[1]);
  return Number.isInteger(page) && page > 0 ? page : undefined;
}

function learningLocationJumpReference(snapshot: ContextSnapshotV2): string | undefined {
  const location = snapshot.learning.lastLocation;
  if (!location) return undefined;
  const item = snapshot.course.catalog.find((candidate) => candidate.id === location.itemID);
  if (!item) return undefined;
  if (location.pageIndex && location.pageIndex > 0) {
    return courseJumpReference(snapshot.course, item, `第 ${location.pageIndex} 页`);
  }
  if (
    (location.locationID?.startsWith("html-section-") ||
      location.locationID?.startsWith("html-heading-")) &&
    location.locationTitle
  ) {
    return courseJumpReference(
      snapshot.course,
      item,
      `[${location.locationID}] ${location.locationTitle}`,
    );
  }
  return courseJumpReference(snapshot.course, item);
}

const OPENUI_COMPONENT_SIGNATURES = {
  RichAnswerRoot: "RichAnswerRoot(eyebrow, title, summary, layout, stages)",
  LearningStage: "LearningStage(role, title, children)",
  NarrativeBlock: "NarrativeBlock(title, text, tone)",
  ParameterSlider: "ParameterSlider(name, label, $value, minimum, maximum, step, caption)",
  ParameterReadout: "ParameterReadout(name, $value, caption)",
  ValuePicker: "ValuePicker(name, label, $value, options, prefix)",
  FunctionPlot: "FunctionPlot(title, family, parameterName, $parameter, compareValues, xMinimum, xMaximum, height)",
  ComparisonRow: "ComparisonRow(label, coefficient, direction, width, interpretation)",
  ComparisonTable: "ComparisonTable(focusName, $focus, rows)",
  EvidenceSnippet: "EvidenceSnippet(evidenceID, locator, quote, relation)",
  ReasonStep: "ReasonStep(title, explanation)",
  ProcessStepper: "ProcessStepper(stateName, $activeStep, steps)",
  QuadraticMechanism: "QuadraticMechanism(stateName, $activeStep, coefficient)",
  FollowUpAction: "FollowUpAction(label, userMessage)",
  ChartSeries: "ChartSeries(name, kind, values, unit, color)",
  LinkedDataChart: "LinkedDataChart(stateName, $focusIndex, title, xLabels, series, caption, height)",
  MetricItem: "MetricItem(label, value, unit, detail, tone)",
  MetricStrip: "MetricStrip(items)",
  ExecutionFrame: "ExecutionFrame(label, activeLine, values, changedIndices, explanation)",
  ExecutionTrack: "ExecutionTrack(stateName, $activeStep, title, codeLines, frames)",
  ArgumentUnit: "ArgumentUnit(role, roleLabel, text, note, evidenceID)",
  ArgumentReader: "ArgumentReader(stateName, $activeUnit, title, units)",
  CausalEvent: "CausalEvent(time, label, kind, kindLabel, relationFromPrevious, confidence, detail, evidenceID)",
  CausalTrack: "CausalTrack(stateName, $activeEvent, title, events)",
  TwoPointLineLab: "TwoPointLineLab(x1Name, $x1, y1Name, $y1, x2Name, $x2, y2Name, $y2, title, xMinimum, xMaximum, yMinimum, yMaximum, height)",
  BalanceExperiment: "BalanceExperiment(stateName, $shift, title, leftLabel, rightLabel, forwardLabel, reverseLabel, caption)",
  SpatialLayer: "SpatialLayer(id, label, kind, defaultVisible, tone)",
  SpatialRegion: "SpatialRegion(id, layerID, label, coordinates, tone)",
  SpatialPath: "SpatialPath(id, layerID, label, coordinates, kind, tone)",
  SpatialPoint: "SpatialPoint(id, layerID, label, x, y, detail, importance, evidenceID?)",
  LayeredSpatialView: "LayeredSpatialView(visibilityStateName, $visibleLayerIDs, selectionStateName, $selectedPointID, title, layers, regions, paths, points, scaleDistance, scaleUnit, caption)",
  DistributionBrush: "DistributionBrush(centerStateName, $windowCenter, spanStateName, $windowSpan, title, values, unit, binCount, caption)",
  FlowAssumption: "FlowAssumption(id, label, minimum, maximum, step, unit, detail)",
  DependencyNode: "DependencyNode(id, label, layer, operation, sourceIDs, parameters, unit, precision, detail)",
  FlowMetric: "FlowMetric(nodeID, label, unit, precision, emphasis, detail)",
  DependencyFlow: "DependencyFlow(valuesStateName, $inputValues, focusStateName, $focusedInputIndex, title, assumptions, nodes, metrics, caption)",
} as const;

type OpenUIComponentName = keyof typeof OPENUI_COMPONENT_SIGNATURES;

const OPENUI_COMPONENT_ORDER = Object.keys(OPENUI_COMPONENT_SIGNATURES) as OpenUIComponentName[];
const OPENUI_COMPONENT_GUIDANCE: Partial<Record<OpenUIComponentName, string>> = {
  RichAnswerRoot: "Agent 回答流中的生成式视觉体验块根；title/summary 只作局部导向，不得形成第二套正文；layout: workbench|comparison|reasoning|flow|document|timeline|track",
  LearningStage: "title 只标记当前操作区域，可留空或使用 null；role: controls|visual|explanation|evidence|full",
  NarrativeBlock: "用于局部状态解释、读数含义或互动反馈，不得复述正文或另写摘要/结论；tone: mechanism|diagnosis|neutral",
  EvidenceSnippet: "只承担来源定位与回原文；evidenceID 必须来自当前 scene.evidenceIDs",
  FunctionPlot: "family 当前固定写 \"quadratic\"，表示由本地内核绘制 y=a·x²；不要把公式或表达式传进 family",
  ProcessStepper: "先逐行声明 s1 = ReasonStep(...) 等步骤，再写 [s1, s2]；组件引用不加引号，也不要嵌套组件调用",
  ChartSeries: "kind: line|bar；color: cinnabar|jade|ochre|indigo|umber|moss",
  LayeredSpatialView: "跨地理、历史、艺术与图像观察使用；只接收归一化区域、路径、点位和语义图层，不接收 SVG path",
  DistributionBrush: "跨统计、实验与数据阅读使用；总体数值由模型提供，窗口统计由本地组件计算",
  DependencyFlow: "跨金融、经济、自然科学与系统分析使用；只接收受限运算节点，不接收表达式或代码",
};
const OPENUI_ALWAYS_COMPONENTS: OpenUIComponentName[] = [
  "RichAnswerRoot",
  "LearningStage",
  "NarrativeBlock",
  "EvidenceSnippet",
  "FollowUpAction",
];
const OPENUI_COMPONENT_GROUPS = {
  quantitative: {
    label: "数量、函数与比较",
    components: [
      "ParameterSlider",
      "ParameterReadout",
      "ValuePicker",
      "FunctionPlot",
      "ComparisonRow",
      "ComparisonTable",
      "QuadraticMechanism",
    ] as OpenUIComponentName[],
  },
  data: {
    label: "数据、分布与读数",
    components: [
      "ChartSeries",
      "LinkedDataChart",
      "MetricItem",
      "MetricStrip",
      "DistributionBrush",
    ] as OpenUIComponentName[],
  },
  process: {
    label: "过程、状态与算法",
    components: [
      "ReasonStep",
      "ProcessStepper",
      "ExecutionFrame",
      "ExecutionTrack",
      "BalanceExperiment",
    ] as OpenUIComponentName[],
  },
  argument: {
    label: "原文、论证与证据",
    components: ["ArgumentUnit", "ArgumentReader"] as OpenUIComponentName[],
  },
  causal: {
    label: "因果与时间",
    components: ["CausalEvent", "CausalTrack"] as OpenUIComponentName[],
  },
  directExperiment: {
    label: "坐标与直接实验",
    components: ["TwoPointLineLab", "BalanceExperiment"] as OpenUIComponentName[],
  },
  spatial: {
    label: "空间、图层与点位",
    components: [
      "SpatialLayer",
      "SpatialRegion",
      "SpatialPath",
      "SpatialPoint",
      "LayeredSpatialView",
    ] as OpenUIComponentName[],
  },
  dependency: {
    label: "依赖、计算与传导",
    components: [
      "FlowAssumption",
      "DependencyNode",
      "FlowMetric",
      "DependencyFlow",
    ] as OpenUIComponentName[],
  },
} as const;
type OpenUIComponentGroupName = keyof typeof OPENUI_COMPONENT_GROUPS;

function selectedOpenUIComponentGroups(
  knowledgeShapes: readonly string[],
  interactions: readonly string[],
): OpenUIComponentGroupName[] {
  const selected: OpenUIComponentGroupName[] = [];
  const add = (group: OpenUIComponentGroupName) => {
    if (!selected.includes(group) && selected.length < 3) selected.push(group);
  };
  for (const shape of knowledgeShapes) {
    switch (shape) {
      case "formula":
      case "comparison":
        add("quantitative");
        break;
      case "series":
      case "distribution":
        add("data");
        break;
      case "process":
      case "algorithmState":
        add("process");
        break;
      case "argument":
        add("argument");
        break;
      case "causalSequence":
        add("causal");
        break;
      case "spatialLayers":
      case "imageRegions":
        add("spatial");
        break;
      case "dependencyGraph":
        add("dependency");
        break;
      case "customGeometry":
        add("directExperiment");
        break;
      default:
        break;
    }
  }
  for (const interaction of interactions) {
    switch (interaction) {
      case "brush":
        add("data");
        break;
      case "step":
        add("process");
        break;
      case "focusEvidence":
        add("argument");
        break;
      case "toggleLayers":
        add("spatial");
        break;
      case "dragPoints":
        add("directExperiment");
        break;
      case "adjust":
        if (selected.length === 0) add("quantitative");
        break;
      default:
        break;
    }
  }
  return selected;
}

function openUIComponentCatalog(names: readonly OpenUIComponentName[]): string[] {
  return OPENUI_COMPONENT_ORDER
    .filter((name) => names.includes(name))
    .map((name) => {
      const guidance = OPENUI_COMPONENT_GUIDANCE[name];
      const constraints = openUIComponentConstraintGuidance(name);
      const details = [guidance, constraints].filter((value) => value && value.length > 0);
      return `${OPENUI_COMPONENT_SIGNATURES[name]}${details.length > 0 ? ` // ${details.join("；")}` : ""}`;
    });
}

const OPENUI_COMPONENT_CATALOG_SIZE = OPENUI_COMPONENT_ORDER.length;
const RICH_ANSWER_LEARNING_ACTIONS = [
  "explain",
  "compare",
  "derive",
  "trace",
  "calculate",
  "observe",
  "manipulate",
  "evaluate",
  "practice",
] as const;
const RICH_ANSWER_INTERACTION_ACTIONS = [
  "none",
  "adjust",
  "select",
  "step",
  "brush",
  "toggleLayers",
  "dragPoints",
  "focusEvidence",
  "probe",
] as const;

const RICH_ANSWER_KNOWLEDGE_NATURES = [
  "functionOrDataCurve",
  "objectMechanism",
  "spatialStructure",
  "processOrState",
  "argumentOrEvidence",
  "imageObservation",
  "comparisonOrEvaluation",
  "calculationOrConstraint",
] as const;

const RICH_ANSWER_T2_PRIMITIVE_ROLES = [
  "vstack",
  "hstack",
  "zstack",
  "grid",
  "panel",
  "canvas",
  "text",
  "metric",
  "sequence",
  "axis",
  "line",
  "path",
  "point",
  "area",
  "vector",
  "region",
  "shape",
  "bar",
  "dotMatrix",
  "image",
  "label",
  "divider",
  "slider",
  "toggle",
  "scrubber",
  "select",
  "reset",
  "probe",
  "evidence",
] as const;
const RICH_ANSWER_T2_PRIMITIVE_ROLE_SET = new Set<string>(RICH_ANSWER_T2_PRIMITIVE_ROLES);

const COMPOSABLE_PRIMITIVE_CATALOG = [
  "T2 可组合原语 ui：先确定 rootID 作为回答内联块的根，再组织 nodes + datasets + bindings；所有节点必须从 rootID 可达，用于目录里没有贴合深组件的长尾问题，不生成 HTML/SVG。",
  "容器：vstack|hstack|zstack|grid|panel；画布：canvas；正文内优先透明容器，不把 panel 堆成卡片墙。",
  "图元：axis|line|path|point|area|shape|bar|dotMatrix|vector|region|image|label；统一使用归一化坐标与魏碑主题令牌。label 是画布标注，必须引用带 label 的 dataset.rows；画布外说明文字使用 text。",
  "函数曲线与真实数据关系本来适合 line/path/point/metric；但物体、空间、过程、机制、证据链不能只剩曲线和读数，必须加入 shape/vector/region/area/sequence/image/bar/dotMatrix 等能表达对象或状态的通用图元。",
  "图像材料：当路线、区域、比例或构图判断依赖原图位置时，必须把 weibei_context.course.catalog 中当前材料的 item.id 写入 image.assetID，并在对应 evidenceLedger.assetIDs 中声明，再作为 canvas 底图叠加 path/region/point/label；只有材料已给出完整数值几何时才可重绘，并明确标成示意关系。",
  "序列：sequence 用于通用步骤、证据链、周期节点、过程状态和时间节点；必须引用 dataset，至少两行，每行 label 是用户可见语义，bindingID 可选；不要自造 stepList/list/items 字段。",
  "控件：slider|toggle|scrubber|select|reset|probe；通过 bindingID 连接共享数值状态，最多两个主要控件，但允许多个联动读数与图元。每个 binding 必须同时连接一个可见控件和至少一个可达的 metric、sequence 或视觉图元，不能只放一个不会改变画面的滑杆。",
  "数据：dataset.rows 提供 x/y、可选 x2/y2、value/result/label；带 bindingID 的图元和 metric 会按 value 插值或选择当前行。",
  "语义：决定结论的条件、变量、方向或关系必须出现在可见的 label/text/axis/dataset 标签里，并随对应图元或状态可检查；不能只画无标注路径，也不能只在 UI 外正文里解释。",
  "证据：evidence 节点与数据行的 evidenceIDs 必须来自本轮 evidenceLedger；只做定位，不复制原文。",
].join("\n");

const OPENUI_STATE_SHAPE_GUIDANCE = [
  "普通组件继续使用数字状态，例如 `$focus = 0`。",
  "空间图层允许字符串数组与字符串状态，例如 `$visible = [\"terrain\", \"route\"]`、`$selected = \"city-a\"`；名称参数必须分别写成 \"visible\" 与 \"selected\"。",
  "依赖传导允许数字数组状态，例如 `$inputs = [8, 18, 11]`；数组顺序必须与 FlowAssumption 引用顺序一致。",
  "数组和字符串状态只用于签名明确要求的组件；不要把它们当成任意数据通道。",
].join("\n");

const RICH_ANSWER_FAMILY_CONTRACT = [
  "富回答 schemaVersion 必须为 2；每个 scene 必须且只能提交 program 或 ui 之一。program 是 T1 深组件程序，ui 是 T2 可组合原语树。",
  "富回答先过内容与专业性，再过视觉。提交前必须核对结论、公式、单位、数值、方向、因果边界和学科术语；不能由本轮材料或确定性内核验证的数字、关系和模拟结果不得让界面假装计算，也不得用漂亮图形掩盖知识错误。",
  "生成式 UI 是 Agent 回答流中的生成式视觉体验块，不是第二篇回答、独立小网页或完整网页外壳。它可以按问题需要组合多个视觉、控件、读数、局部解释和实验步骤。",
  "narrative 是本次富回答最终显示的完整正文：先给结论、就近标注真实来源，并用场景标记把视觉体验插在最有帮助的位置。优先用自然段连接解释与场景，最多两个 ##/### 小标题，禁止页面级 # 标题和标题—摘要—结论式第二篇文章；工具成功后不得再生成一份不同正文。",
  `提交富回答前必须先调用 ${RICH_ANSWER_CATALOG_TOOL}，让魏碑按本轮学习动作、知识形状、来源媒介、直接操作和表面重量返回相关 T1 组件组与 T2 提示；组件目录可以再次调用，但不得绕过。`,
  "优先选择最贴合问题的表达层：已有深组件能真实解决问题时用 program；没有贴合深组件时必须先尝试 ui 通用原语组合，不能仅因目录缺少专属实验室就退回文字。",
  "program 中模型负责选择深组件、布局、数据、$state 反应变量和动作；ui 中模型负责组合容器、画布图元、数据集与 bindings；魏碑本地运行时统一负责渲染、联动与风格。",
  "T2 的画面必须能独立读出支撑结论的关键语义：用可见标签标明决定性条件、变量、方向、对应关系和当前状态，并把标签与实际图元、数据行或 binding 联动；禁止只画漂亮但无语义的线、点和区域。",
  "图像、地图和设计题若结论依赖原图中的空间位置，T2 必须使用 weibei_context.course.catalog 中当前材料的 item.id 作为 image.assetID，在对应 evidenceLedger.assetIDs 中声明，并作为画布底图叠加标注；不得脱离原图凭空重画路线、区域、比例或构图。材料已提供完整数值坐标时可画明确标注为示意的关系图。",
  "不要用固定的一图一控件或单场景模板限制表达。单个问题默认只提交一个最有帮助的 scene、一个主要操作和必要联动读数；相互关联的视觉、控件、读数和步骤优先组合进同一个 scene，只有两个体验确实独立时才拆分。每个元素都必须服务当前问题，不得用装饰、重复内容或穷举节点凑页面。",
  "保持多学科、多形态：根据知识对象选择函数图、数据图、执行轨、论证阅读、因果时间线、坐标实验、平衡实验或其他目录能力，不要把不同问题压成同一种外观。",
  "禁止在 program 中重复 Agent 正文的整套标题、摘要、结论或 evidenceLedger.excerpt，也不得从头重讲同一答案。RichAnswerRoot 与 LearningStage 只提供体验块内部的局部导向；证据组件只承担来源定位和回原文。",
  "NarrativeBlock 允许呈现局部状态解释、读数含义、诊断或互动反馈，但不得复述正文、扩写背景、另做摘要或再下一个完整结论。",
  "placement 与 preferredSurface 应按体验复杂度选择 inline、expanded 或 focus。复杂体验可以自然展开或进入专注模式；专注模式仍然是同一回答的延展，不得变成独立网页。",
  "T1 只允许使用本轮目录工具返回的组件签名；每行只能声明一个有限状态或一个组件。状态默认是数字；只有签名明确要求时才可使用字符串、数字数组或字符串数组。参数必须严格匹配签名。不得自造组件、嵌套组件调用、SVG path、HTML、CSS、JavaScript、Query、Mutation、URL、iframe 或外部资源。",
  "T1 的组件引用必须先声明后引用；引用数组使用 [step1, step2] 这种不加引号的组件 id，不能写成字符串数组。枚举参数只能使用目录指导列出的固定值，不能把公式或自然语言塞进枚举位。",
  "文字已经足够时不要调用富回答；禁止使用网站导航、页面级页头、功能菜单、营销区块或其他完整网页外壳，也不要用第二套标题—摘要—结论结构重新包装正文。",
  "T1 的函数图、联动数据图和双点坐标实验由 Canvas 内核计算，不要提交采样路径；T1 与 T2 都无法诚实表达对象时，才使用正常文本，不要假造可视化。",
  "压力样例不是场景模板。先选择知识对象，再组合不同组件；禁止复用样例标题、数据和整套结构。",
  "所有状态名和组件 id 必须唯一；$状态、组件引用和 root 组件树必须完整可达，不能有重复、悬空、循环或孤立声明。",
  "EvidenceSnippet、ArgumentUnit、CausalEvent、SpatialPoint 中的 evidenceID 必须属于 scene.evidenceIDs，并与本轮 evidenceLedger 中的真实材料对应；普通文本里出现 id 不算证据绑定。",
  "工具会在拒绝 program 时批量返回场景、行列、预期组件签名和修正动作。按完整诊断修正；仍有遗漏时可再修一轮，不要用改写字符串绕过校验。",
  "工具拒绝富回答时会返回 weibei.rich_answer.repair_fault；必须保留其中的 code、jsonPath 与 humanFixHint，并按 replanningFeedback 在 T1 program 与 T2 ui 之间重新选择或修正后完整重发 RichAnswerUI。不能解释原因代替提交，也不能在坏树基础上局部 patch。remainingAttempts 为 0 时停止富回答并诚实使用普通文本；正文只回答用户问题和真实限制，不得提富回答校验、协议失败、repair_fault、payload 或内部工具错误。",
  OPENUI_STATE_SHAPE_GUIDANCE,
  COMPOSABLE_PRIMITIVE_CATALOG,
].join("\n");

const richAnswerIdentifierSchema = Type.String({ minLength: 1, maxLength: LIMITS.identifier });
const richAnswerPointSchema = Type.Object(
  {
    x: Type.Number(),
    y: Type.Number(),
  },
  { additionalProperties: false },
);
const richAnswerRegionSchema = Type.Object(
  {
    x: Type.Number({ minimum: 0, maximum: 1 }),
    y: Type.Number({ minimum: 0, maximum: 1 }),
    width: Type.Number({ exclusiveMinimum: 0, maximum: 1 }),
    height: Type.Number({ exclusiveMinimum: 0, maximum: 1 }),
  },
  { additionalProperties: false },
);
const richAnswerAxisSchema = Type.Object(
  {
    label: Type.String({ minLength: 1, maxLength: 200 }),
    minimum: Type.Number(),
    maximum: Type.Number(),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
  },
  { additionalProperties: false },
);
const richAnswerObjectSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      [
        "text",
        "quantity",
        "formula",
        "event",
        "region",
        "state",
        "claim",
        "image",
        "dataPoint",
        "step",
        "constraint",
        "option",
      ].map((value) => Type.Literal(value)),
    ),
    label: Type.String({ minLength: 1, maxLength: 300 }),
    text: Type.Optional(Type.String({ minLength: 1, maxLength: LIMITS.richAnswerText })),
    number: Type.Optional(Type.Number()),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
    evidenceIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
    ),
    assetID: Type.Optional(richAnswerIdentifierSchema),
    frameID: Type.Optional(richAnswerIdentifierSchema),
    coordinate: Type.Optional(richAnswerPointSchema),
    bounds: Type.Optional(richAnswerRegionSchema),
  },
  { additionalProperties: false },
);
const richAnswerRelationSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      [
        "supports",
        "refutes",
        "causes",
        "precedes",
        "aligns",
        "contains",
        "transforms",
        "dependsOn",
        "contrasts",
        "constrains",
      ].map((value) => Type.Literal(value)),
    ),
    sourceID: richAnswerIdentifierSchema,
    targetID: richAnswerIdentifierSchema,
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    evidenceIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
    ),
  },
  { additionalProperties: false },
);
const richAnswerParameterSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    label: Type.String({ minLength: 1, maxLength: 200 }),
    minimum: Type.Number(),
    maximum: Type.Number(),
    step: Type.Number({ exclusiveMinimum: 0 }),
    initialValue: Type.Number(),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
  },
  { additionalProperties: false },
);
const richAnswerOperationSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      [
        "adjust",
        "toggle",
        "step",
        "zoom",
        "pan",
        "filter",
        "sort",
        "probe",
        "reset",
        "compare",
        "reveal",
        "select",
        "scrub",
        "playPause",
        "measure",
      ].map((value) => Type.Literal(value)),
    ),
    label: Type.String({ minLength: 1, maxLength: 300 }),
    targetIDs: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 32 }),
    parameter: Type.Optional(richAnswerParameterSchema),
    frameID: Type.Optional(richAnswerIdentifierSchema),
  },
  {
    additionalProperties: false,
    description:
      "operation 必须是当前 family 的原生 SwiftUI 渲染器已支持操作；不支持的 sort/filter/pan/measure 等不要提交。",
  },
);
const richAnswerFrameSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      ["cartesian", "numberLine", "timeline", "space", "image", "text", "table", "graph", "process"]
        .map((value) => Type.Literal(value)),
    ),
    title: Type.String({ minLength: 1, maxLength: 300 }),
    objectIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerObjects }),
    ),
    xAxis: Type.Optional(richAnswerAxisSchema),
    yAxis: Type.Optional(richAnswerAxisSchema),
    assetID: Type.Optional(richAnswerIdentifierSchema),
    evidenceIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
    ),
  },
  { additionalProperties: false },
);
const richAnswerUIRoleSchema = Type.Union(
  [
    "vstack",
    "hstack",
    "zstack",
    "grid",
    "panel",
    "canvas",
    "text",
    "metric",
    "sequence",
    "axis",
    "line",
    "path",
    "point",
    "area",
    "vector",
    "region",
    "shape",
    "bar",
    "dotMatrix",
    "image",
    "label",
    "divider",
    "slider",
    "toggle",
    "scrubber",
    "select",
    "reset",
    "probe",
    "evidence",
  ].map((value) => Type.Literal(value)),
);
const richAnswerUIShapeSchema = Type.Union(
  ["rectangle", "roundedRectangle", "circle", "ellipse", "triangle", "diamond", "capsule"]
    .map((value) => Type.Literal(value)),
);
const richAnswerUIFillSchema = Type.Union(
  ["outline", "soft", "solid"].map((value) => Type.Literal(value)),
);
const richAnswerUIDataRowSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    x: Type.Number({ minimum: 0, maximum: 1 }),
    y: Type.Number({ minimum: 0, maximum: 1 }),
    x2: Type.Optional(Type.Number({ minimum: 0, maximum: 1 })),
    y2: Type.Optional(Type.Number({ minimum: 0, maximum: 1 })),
    value: Type.Optional(Type.Number()),
    result: Type.Optional(Type.Number()),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 200 })),
    evidenceIDs: Type.Optional(
      Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
    ),
  },
  { additionalProperties: false },
);
const richAnswerUIDatasetSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    rows: Type.Array(richAnswerUIDataRowSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerUIRows,
    }),
  },
  { additionalProperties: false },
);
const richAnswerUIBindingSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    label: Type.String({ minLength: 1, maxLength: 200 }),
    minimum: Type.Number(),
    maximum: Type.Number(),
    step: Type.Number({ exclusiveMinimum: 0 }),
    initialValue: Type.Number(),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
  },
  { additionalProperties: false },
);
const richAnswerUINodeStyleFields = {
  id: richAnswerIdentifierSchema,
  tone: Type.Optional(
    Type.Union(["ink", "muted", "accent", "warning", "positive", "gridline"]
      .map((value) => Type.Literal(value))),
  ),
  emphasis: Type.Optional(
    Type.Union(["quiet", "regular", "strong"].map((value) => Type.Literal(value))),
  ),
  spacing: Type.Optional(
    Type.Union(["tight", "regular", "loose"].map((value) => Type.Literal(value))),
  ),
  alignment: Type.Optional(
    Type.Union(["leading", "center", "trailing"].map((value) => Type.Literal(value))),
  ),
  size: Type.Optional(
    Type.Union(["compact", "regular", "large"].map((value) => Type.Literal(value))),
  ),
};
const richAnswerUINodeEvidenceFields = {
  evidenceIDs: Type.Optional(
    Type.Array(richAnswerIdentifierSchema, { maxItems: LIMITS.richAnswerEvidence }),
  ),
};
const richAnswerUIContainerNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Union(["vstack", "hstack", "zstack", "panel"].map((value) => Type.Literal(value))),
    children: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 12 }),
  },
  { additionalProperties: false },
);
const richAnswerUIGridNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("grid"),
    children: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 12 }),
    columns: Type.Integer({ minimum: 2, maximum: 3 }),
  },
  { additionalProperties: false },
);
const richAnswerUICanvasNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("canvas"),
    children: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 12 }),
    xAxis: Type.Optional(richAnswerAxisSchema),
    yAxis: Type.Optional(richAnswerAxisSchema),
  },
  { additionalProperties: false },
);
const richAnswerUITextNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("text"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    text: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerText }),
  },
  { additionalProperties: false },
);
const richAnswerUIMetricNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("metric"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);
const richAnswerUISequenceNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("sequence"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);
const richAnswerUIAxisNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("axis"),
  },
  { additionalProperties: false },
);
const richAnswerUIStrokeMarkNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Union(["line", "path", "point", "vector"].map((value) => Type.Literal(value))),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);
const richAnswerUIFilledMarkNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Union(["area", "bar", "dotMatrix"].map((value) => Type.Literal(value))),
    datasetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
    fill: Type.Optional(richAnswerUIFillSchema),
  },
  { additionalProperties: false },
);
const richAnswerUILabelMarkNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("label"),
    datasetID: richAnswerIdentifierSchema,
  },
  { additionalProperties: false },
);
const richAnswerUIStaticShapeNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("shape"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    region: richAnswerRegionSchema,
    shape: richAnswerUIShapeSchema,
    fill: richAnswerUIFillSchema,
  },
  { additionalProperties: false },
);
const richAnswerUIRepeatedShapeNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("shape"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    datasetID: richAnswerIdentifierSchema,
    region: richAnswerRegionSchema,
    shape: richAnswerUIShapeSchema,
    fill: richAnswerUIFillSchema,
  },
  { additionalProperties: false },
);
const richAnswerUIInteractiveShapeNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("shape"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    datasetID: richAnswerIdentifierSchema,
    bindingID: richAnswerIdentifierSchema,
    region: richAnswerRegionSchema,
    shape: richAnswerUIShapeSchema,
    fill: richAnswerUIFillSchema,
  },
  { additionalProperties: false },
);
const richAnswerUIRegionNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("region"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    bindingID: Type.Optional(richAnswerIdentifierSchema),
    region: richAnswerRegionSchema,
    fill: Type.Optional(richAnswerUIFillSchema),
  },
  { additionalProperties: false },
);
const richAnswerUIImageNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    ...richAnswerUINodeEvidenceFields,
    role: Type.Literal("image"),
    assetID: richAnswerIdentifierSchema,
    bindingID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);
const richAnswerUIDividerNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("divider"),
  },
  { additionalProperties: false },
);
const richAnswerUIBoundControlNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Union(["slider", "toggle", "scrubber", "probe"].map((value) => Type.Literal(value))),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    bindingID: richAnswerIdentifierSchema,
  },
  { additionalProperties: false },
);
const richAnswerUISelectNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("select"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    datasetID: Type.Optional(richAnswerIdentifierSchema),
  },
  { additionalProperties: false },
);
const richAnswerUIResetNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("reset"),
    label: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
  },
  { additionalProperties: false },
);
const richAnswerUIEvidenceNodeSchema = Type.Object(
  {
    ...richAnswerUINodeStyleFields,
    role: Type.Literal("evidence"),
    evidenceIDs: Type.Array(richAnswerIdentifierSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerEvidence,
    }),
  },
  { additionalProperties: false },
);
const richAnswerUINodeSchema = Type.Union(
  [
    richAnswerUIContainerNodeSchema,
    richAnswerUIGridNodeSchema,
    richAnswerUICanvasNodeSchema,
    richAnswerUITextNodeSchema,
    richAnswerUIMetricNodeSchema,
    richAnswerUISequenceNodeSchema,
    richAnswerUIAxisNodeSchema,
    richAnswerUIStrokeMarkNodeSchema,
    richAnswerUIFilledMarkNodeSchema,
    richAnswerUILabelMarkNodeSchema,
    richAnswerUIStaticShapeNodeSchema,
    richAnswerUIRepeatedShapeNodeSchema,
    richAnswerUIInteractiveShapeNodeSchema,
    richAnswerUIRegionNodeSchema,
    richAnswerUIImageNodeSchema,
    richAnswerUIDividerNodeSchema,
    richAnswerUIBoundControlNodeSchema,
    richAnswerUISelectNodeSchema,
    richAnswerUIResetNodeSchema,
    richAnswerUIEvidenceNodeSchema,
  ],
  {
    description:
      "按 role 选择节点结构；不要给节点添加该角色未声明的字段。文字用 text，步骤/证据链/周期节点用 sequence 引用 dataset。",
  },
);
const richAnswerUICompositionSchema = Type.Object(
  {
    rootID: richAnswerIdentifierSchema,
    nodes: Type.Array(richAnswerUINodeSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerUINodes,
    }),
    datasets: Type.Optional(
      Type.Array(richAnswerUIDatasetSchema, { maxItems: 12 }),
    ),
    bindings: Type.Optional(
      Type.Array(richAnswerUIBindingSchema, { maxItems: LIMITS.richAnswerUIBindings }),
    ),
  },
  { additionalProperties: false },
);
const richAnswerUIProgramSchema = Type.Object(
  {
    version: Type.Literal("weibei.openui.v1"),
    source: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerProgramSource }),
    capabilities: Type.Array(Type.String({ minLength: 1, maxLength: 80 }), {
      minItems: 1,
      maxItems: LIMITS.richAnswerProgramCapabilities,
    }),
    maxHeight: Type.Integer({ minimum: 160, maximum: 720 }),
  },
  {
    additionalProperties: false,
    description:
      `${RICH_ANSWER_FAMILY_CONTRACT}\ngraphics 与 directManipulation 由魏碑根据实际组件自动推导，不要提交。`,
  },
);
const richAnswerSceneCommonFields = {
  id: richAnswerIdentifierSchema,
  title: Type.String({ minLength: 1, maxLength: 300 }),
  family: Type.Union(
    [
      "textAndAlignment",
      "quantityAndCoordinates",
      "processAndState",
      "relationAndEvidence",
      "timeAndSpace",
      "imageAndOverlay",
      "comparisonAndEvaluation",
      "calculationAndConstraints",
    ].map((value) => Type.Literal(value)),
  ),
  evidenceIDs: Type.Array(richAnswerIdentifierSchema, {
    minItems: 1,
    maxItems: LIMITS.richAnswerEvidence,
  }),
  placement: Type.Optional(
    Type.Union([Type.Literal("inline"), Type.Literal("expanded"), Type.Literal("focus")]),
  ),
};
const richAnswerT1SceneSchema = Type.Object(
  {
    ...richAnswerSceneCommonFields,
    program: richAnswerUIProgramSchema,
  },
  { additionalProperties: false },
);
const richAnswerT2SceneSchema = Type.Object(
  {
    ...richAnswerSceneCommonFields,
    ui: richAnswerUICompositionSchema,
  },
  { additionalProperties: false },
);
const richAnswerSceneSchema = Type.Union(
  [richAnswerT1SceneSchema, richAnswerT2SceneSchema],
  {
    description:
      `${RICH_ANSWER_FAMILY_CONTRACT}\n场景从输入层就二选一：T1 只提交 program，T2 只提交 ui，不再提交 objects、relations、operations 或 frames。T2 节点按 role 选择专属结构。`,
  },
);
const richAnswerEnvelopeSchema = Type.Object(
  {
    schemaVersion: Type.Literal(2),
    contextRevision: richAnswerIdentifierSchema,
    narrative: Type.String({
      minLength: 1,
      maxLength: LIMITS.richAnswerNarrative,
      description: "本次最终显示的完整、带真实来源标签的回答正文；可用独占一行的 <!-- weibei-scene:场景ID --> 把场景插入正文中间",
    }),
    expressionPlan: Type.Object(
      {
        action: Type.Union(
          ["explain", "compare", "derive", "trace", "calculate", "observe", "manipulate", "evaluate", "practice"]
            .map((value) => Type.Literal(value)),
        ),
        summary: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerSummary }),
        knowledgeNatures: Type.Array(
          Type.Union(RICH_ANSWER_KNOWLEDGE_NATURES.map((value) => Type.Literal(value))),
          {
            minItems: 1,
            maxItems: 4,
            description: "声明本轮要表达的是函数曲线、物体机制、空间结构、过程状态、论证证据、图像观察、对照评价或计算约束；不能留空。",
          },
        ),
        knowledgeObjects: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 1,
          maxItems: 8,
          description: "显式列出 UI 要表达的关键知识对象，例如 摆长L、摆球、摩擦力、论点、样本窗口。",
        }),
        knowledgeRelations: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 0,
          maxItems: 8,
          description: "显式列出要表达的关系，例如 T 随 L 增长、静摩擦阻碍潜在相对运动、证据支持主张。",
        }),
        knowledgeProcesses: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 0,
          maxItems: 8,
          description: "显式列出要表达的过程或状态变化；若不是过程题可为空数组。",
        }),
        visualPrimitives: Type.Array(
          Type.Union(RICH_ANSWER_T2_PRIMITIVE_ROLES.map((value) => Type.Literal(value))),
          {
            minItems: 1,
            maxItems: 12,
            description: "列出本次实际计划使用的 T2 role；使用 T1 program 时也要列出其等价视觉角色，不能写不存在的网页/SVG/颜色。",
          },
        ),
        visualRationale: Type.Array(Type.String({ minLength: 1, maxLength: 200 }), {
          minItems: 1,
          maxItems: 8,
          description: "说明为什么这些视觉原语能表达上述知识对象、关系或过程，不能只写排版理由。",
        }),
        families: Type.Array(
          Type.Union(
            [
              "textAndAlignment",
              "quantityAndCoordinates",
              "processAndState",
              "relationAndEvidence",
              "timeAndSpace",
              "imageAndOverlay",
              "comparisonAndEvaluation",
              "calculationAndConstraints",
            ].map((value) => Type.Literal(value)),
          ),
          { minItems: 1, maxItems: 8 },
        ),
        preferredSurface: Type.Union([
          Type.Literal("inline"),
          Type.Literal("expanded"),
          Type.Literal("focus"),
        ]),
      },
      { additionalProperties: false },
    ),
    scenes: Type.Array(richAnswerSceneSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerScenes,
    }),
    evidenceLedger: Type.Array(
      Type.Object(
        {
          id: richAnswerIdentifierSchema,
          sourceLabel: Type.String({ minLength: 1, maxLength: 400 }),
          excerpt: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerExcerpt }),
          isTruncated: Type.Optional(Type.Boolean()),
          tags: Type.Optional(
            Type.Array(Type.String({ minLength: 1, maxLength: 120 }), { maxItems: 16 }),
          ),
          assetIDs: Type.Optional(
            Type.Array(richAnswerIdentifierSchema, { maxItems: 16 }),
          ),
        },
        { additionalProperties: false },
      ),
      { minItems: 1, maxItems: LIMITS.richAnswerEvidence },
    ),
    fallback: Type.Object(
      {
        text: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerNarrative }),
        reason: Type.String({ minLength: 1, maxLength: 600 }),
      },
      { additionalProperties: false },
    ),
  },
  { additionalProperties: false },
);

export function validateRichAnswerNarrativeFlow(
  narrative: string,
  sceneIDs: readonly string[],
): string {
  const knownSceneIDs = new Set(sceneIDs);
  const referencedSceneIDs = new Set<string>();
  const narrativeLines: string[] = [];
  const markerPattern = /^<!-- weibei-scene:([A-Za-z][A-Za-z0-9_-]{0,119}) -->$/u;

  for (const [index, line] of narrative.split(/\r?\n/gu).entries()) {
    const trimmed = line.trim();
    if (!trimmed.includes("weibei-scene:")) {
      narrativeLines.push(line);
      continue;
    }
    const match = trimmed.match(markerPattern);
    if (!match) {
      throw new Error(
        `富回答 narrative 第 ${index + 1} 行的场景标记格式无效；必须独占一行写成 <!-- weibei-scene:场景ID -->`,
      );
    }
    if (referencedSceneIDs.size === 0 && narrativeLines.join("\n").trim().length === 0) {
      throw new Error("富回答 narrative 必须先用至少一句正文引入，再插入第一个场景；不要让视觉块孤零零顶在回答开头");
    }
    const sceneID = match[1];
    if (!knownSceneIDs.has(sceneID)) {
      throw new Error(`富回答 narrative 引用了不存在的场景 ${sceneID}`);
    }
    if (referencedSceneIDs.has(sceneID)) {
      throw new Error(`富回答 narrative 重复插入了场景 ${sceneID}`);
    }
    referencedSceneIDs.add(sceneID);
  }

  const plainNarrative = narrativeLines.join("\n").trim();
  if (!plainNarrative) {
    throw new Error("富回答 narrative 不能只有场景标记，必须保留可独立阅读的正文");
  }
  const headings = plainNarrative
    .split(/\r?\n/gu)
    .map((line) => line.trim())
    .filter((line) => /^#{1,3}\s/u.test(line));
  if (headings.some((heading) => /^#\s/u.test(heading))) {
    throw new Error("富回答 narrative 不得使用页面级 # 标题；它是 Agent 回答的正文，不是第二篇文章");
  }
  if (headings.length > 2 || (headings.length > 1 && headings.length * 180 > plainNarrative.length)) {
    throw new Error(
      `富回答 narrative 的小标题过密（${headings.length} 个 / ${plainNarrative.length} 字符）；改成自然段，最多保留两个真正必要的 ##/### 小标题`,
    );
  }
  const missingSceneIDs = sceneIDs.filter((sceneID) => !referencedSceneIDs.has(sceneID));
  if (missingSceneIDs.length > 0) {
    throw new Error(
      `富回答 narrative 没有插入场景：${missingSceneIDs.join("、")}；每个 scene 必须用独占一行的标记放进正文`,
    );
  }
  return plainNarrative;
}

function normalizedEvidenceText(value: string): string {
  return value.normalize("NFKC").replace(/\s+/gu, " ").trim();
}

function canonicalRichAnswerEvidenceLabel(
  rawLabel: string,
  availableLabels: Iterable<string>,
): string | undefined {
  const raw = normalizedEvidenceText(rawLabel);
  const matches = Array.from(availableLabels).filter((label) => {
    const comparableLabel = normalizedEvidenceText(label);
    if (raw === comparableLabel) return true;
    const inner = comparableLabel.startsWith("[") && comparableLabel.endsWith("]")
      ? comparableLabel.slice(1, -1)
      : comparableLabel;
    const separator = inner.search(/[:：]/u);
    const title = separator >= 0 ? inner.slice(separator + 1) : inner;
    return raw === inner || raw === title || raw === `[${title}]`;
  });
  return matches.length === 1 ? matches[0] : undefined;
}

interface RichAnswerEvidenceSource {
  text: string;
  isTruncated: boolean;
}

function richAnswerEvidenceText(
  snapshot: ContextSnapshotV2,
  searchedCourseItemIDs: ReadonlySet<string>,
): Map<string, RichAnswerEvidenceSource> {
  const evidence = new Map<string, RichAnswerEvidenceSource>();
  if (snapshot.note.text.trim()) {
    evidence.set(`[笔记：${snapshot.note.title}]`, {
      text: snapshot.note.text,
      isTruncated: snapshot.note.isTruncated,
    });
  }
  if (snapshot.material?.text.trim()) {
    evidence.set(`[材料：${snapshot.material.title}]`, {
      text: snapshot.material.text,
      isTruncated: snapshot.material.isTruncated,
    });
  }
  if (snapshot.selection?.text.trim()) {
    evidence.set(`[选区：${snapshot.selection.title}]`, {
      text: snapshot.selection.text,
      isTruncated: snapshot.selection.isTruncated,
    });
  }
  snapshot.course.items
    .filter((item) => searchedCourseItemIDs.has(item.id) && item.searchText.trim())
    .forEach((item) => evidence.set(courseEvidenceLabel(snapshot.course, item), {
      text: item.searchText,
      isTruncated: item.isTruncated,
    }));
  return evidence;
}

interface RichAnswerPointParam {
  x: number;
  y: number;
}

interface RichAnswerObjectParam {
  id: string;
  kind: string;
  text?: string;
  number?: number;
  assetID?: string;
  frameID?: string;
  coordinate?: RichAnswerPointParam;
  bounds?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

interface RichAnswerRelationParam {
  id: string;
  sourceID: string;
  targetID: string;
}

interface RichAnswerOperationParam {
  id: string;
  kind: string;
  targetIDs: string[];
  parameter?: {
    id: string;
    label: string;
    minimum: number;
    maximum: number;
    step: number;
    initialValue: number;
    unit?: string;
  };
  frameID?: string;
}

interface RichAnswerFrameParam {
  id: string;
  kind: string;
  objectIDs?: string[];
  assetID?: string;
}

interface RichAnswerUIDataRowParam {
  id: string;
  x: number;
  y: number;
  x2?: number;
  y2?: number;
  value?: number;
  result?: number;
  label?: string;
  evidenceIDs?: string[];
}

interface RichAnswerUIDatasetParam {
  id: string;
  rows: RichAnswerUIDataRowParam[];
}

interface RichAnswerUIBindingParam {
  id: string;
  label: string;
  minimum: number;
  maximum: number;
  step: number;
  initialValue: number;
  unit?: string;
}

interface RichAnswerUINodeParam {
  id: string;
  role: string;
  children?: string[];
  label?: string;
  text?: string;
  unit?: string;
  datasetID?: string;
  bindingID?: string;
  assetID?: string;
  evidenceIDs?: string[];
  xAxis?: { label?: string; minimum: number; maximum: number; unit?: string };
  yAxis?: { label?: string; minimum: number; maximum: number; unit?: string };
  region?: { x: number; y: number; width: number; height: number };
  shape?: "rectangle" | "roundedRectangle" | "circle" | "ellipse" | "triangle" | "diamond" | "capsule";
  fill?: "outline" | "soft" | "solid";
  columns?: number;
}

interface RichAnswerUICompositionParam {
  rootID: string;
  nodes: RichAnswerUINodeParam[];
  datasets?: RichAnswerUIDatasetParam[];
  bindings?: RichAnswerUIBindingParam[];
}

interface RichAnswerUIProgramParam {
  version: "weibei.openui.v1";
  source: string;
  capabilities: string[];
  directManipulation?: boolean;
  maxHeight: number;
  graphics?: "dom" | "canvas";
}

interface RichAnswerSceneParam {
  id: string;
  title?: string;
  family: string;
  objects?: RichAnswerObjectParam[];
  relations?: RichAnswerRelationParam[];
  operations?: RichAnswerOperationParam[];
  frames?: RichAnswerFrameParam[];
  evidenceIDs: string[];
  program?: RichAnswerUIProgramParam;
  ui?: RichAnswerUICompositionParam;
}

interface RichAnswerExpressionPlanParam {
  action: string;
  summary: string;
  knowledgeNatures?: string[];
  knowledgeObjects?: string[];
  knowledgeRelations?: string[];
  knowledgeProcesses?: string[];
  visualPrimitives?: string[];
  visualRationale?: string[];
  families: string[];
  preferredSurface: string;
  directManipulation?: boolean;
}

const RICH_ANSWER_SUPPORTED_OPERATIONS: Record<string, ReadonlySet<string>> = {
  textAndAlignment: new Set(["select", "reveal", "reset"]),
  quantityAndCoordinates: new Set(["adjust", "probe", "select", "reset"]),
  processAndState: new Set(["select", "step", "playPause", "reset"]),
  relationAndEvidence: new Set(["select", "reveal", "reset"]),
  timeAndSpace: new Set(["scrub", "toggle", "reset"]),
  imageAndOverlay: new Set(["select", "toggle", "zoom"]),
  comparisonAndEvaluation: new Set(["compare", "select", "reset"]),
  calculationAndConstraints: new Set(["adjust", "reset"]),
};

function hasMeaningfulText(value: string | undefined): boolean {
  return value !== undefined && value.trim().length > 0;
}

function isNormalizedPoint(point: RichAnswerPointParam | undefined): boolean {
  return point !== undefined &&
    Number.isFinite(point.x) &&
    Number.isFinite(point.y) &&
    point.x >= 0 &&
    point.x <= 1 &&
    point.y >= 0 &&
    point.y <= 1;
}

function operationTargetsAtLeast(
  scene: RichAnswerSceneParam,
  kind: string,
  minimumTargetCount: number,
  allowedTargetIDs: ReadonlySet<string>,
): boolean {
  return (scene.operations ?? []).some((operation) =>
    operation.kind === kind &&
      new Set(operation.targetIDs.filter((targetID) => allowedTargetIDs.has(targetID))).size >=
        minimumTargetCount,
  );
}

function numericCoordinateSamples(
  scene: RichAnswerSceneParam,
  operation: RichAnswerOperationParam,
  frameIDs: ReadonlySet<string>,
): RichAnswerObjectParam[] {
  const targetIDs = new Set(operation.targetIDs);
  return (scene.objects ?? []).filter((object) =>
    targetIDs.has(object.id) &&
      object.number !== undefined &&
      isNormalizedPoint(object.coordinate) &&
      object.frameID !== undefined &&
      frameIDs.has(object.frameID),
  );
}

const RICH_ANSWER_UI_CONTAINER_ROLES = new Set(["vstack", "hstack", "zstack", "grid", "panel"]);
const RICH_ANSWER_UI_CANVAS_ROLES = new Set([
  "axis",
  "line",
  "path",
  "point",
  "area",
  "vector",
  "region",
  "shape",
  "bar",
  "dotMatrix",
  "image",
  "label",
]);
const RICH_ANSWER_UI_DATASET_ROLES = new Set([
  "metric",
  "sequence",
  "line",
  "path",
  "point",
  "area",
  "vector",
  "bar",
  "dotMatrix",
  "label",
]);
const RICH_ANSWER_UI_BINDING_ROLES = new Set(["slider", "toggle", "scrubber", "probe"]);
const RICH_ANSWER_UI_BINDING_OUTPUT_ROLES = new Set([
  "metric",
  "sequence",
  "line",
  "path",
  "point",
  "area",
  "shape",
  "bar",
  "dotMatrix",
  "vector",
  "region",
  "image",
]);
const RICH_ANSWER_UI_PRIMARY_CONTROL_ROLES = new Set([
  "slider",
  "toggle",
  "scrubber",
  "select",
  "probe",
]);

type OpenUIValue =
  | { kind: "string"; value: string; column: number }
  | { kind: "number"; value: number; column: number }
  | { kind: "boolean"; value: boolean; column: number }
  | { kind: "null"; column: number }
  | { kind: "state"; name: string; column: number }
  | { kind: "reference"; id: string; column: number }
  | { kind: "array"; items: OpenUIValue[]; column: number };

interface OpenUIStateDeclaration {
  kind: "stateDeclaration";
  name: string;
  value: OpenUIValue;
  line: number;
  column: number;
}

interface OpenUIComponentDeclaration {
  kind: "componentDeclaration";
  id: string;
  component: OpenUIComponentName;
  arguments: OpenUIValue[];
  line: number;
  column: number;
}

type OpenUIDeclaration = OpenUIStateDeclaration | OpenUIComponentDeclaration;

type OpenUIArgumentRule =
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

const openUIString = (
  values?: readonly string[],
  nullable = false,
  optional = false,
): OpenUIArgumentRule => ({ kind: "string", values, nullable, optional });
const openUINumber = (
  options: { integer?: boolean; minimum?: number; maximum?: number } = {},
): OpenUIArgumentRule => ({ kind: "number", ...options });
const openUIBoolean = (): OpenUIArgumentRule => ({ kind: "boolean" });
const openUIState = (
  valueKind: "number" | "string" | "numberArray" | "stringArray" = "number",
  options: { minimum?: number; maximum?: number } = {},
): OpenUIArgumentRule => ({ kind: "state", valueKind, ...options });
const openUIReference = (...components: OpenUIComponentName[]): OpenUIArgumentRule => ({
  kind: "reference",
  components,
});
const openUIArray = (
  item: OpenUIArgumentRule,
  minimum: number,
  maximum: number,
): OpenUIArgumentRule => ({ kind: "array", item, minimum, maximum });

const OPENUI_LEARNING_BLOCK_COMPONENTS: readonly OpenUIComponentName[] = [
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

const OPENUI_COMPONENT_ARGUMENT_RULES: Record<
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

function openUIComponentConstraintGuidance(name: OpenUIComponentName): string {
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

const OPENUI_CANVAS_COMPONENTS = new Set<OpenUIComponentName>([
  "FunctionPlot",
  "LinkedDataChart",
  "TwoPointLineLab",
  "LayeredSpatialView",
  "DistributionBrush",
]);
const OPENUI_DIRECT_MANIPULATION_COMPONENTS = new Set<OpenUIComponentName>([
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

function isOpenUIComponentName(value: string): value is OpenUIComponentName {
  return Object.prototype.hasOwnProperty.call(OPENUI_COMPONENT_SIGNATURES, value);
}

function openUIProgramFailure(
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

class OpenUILineParser {
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

function openUIArgumentName(component: OpenUIComponentName, index: number): string {
  const signature = OPENUI_COMPONENT_SIGNATURES[component];
  const start = signature.indexOf("(");
  return signature.slice(start + 1, -1).split(",").map((name) => name.trim())[index] ?? `参数 ${index + 1}`;
}

function openUIRuleDescription(rule: OpenUIArgumentRule): string {
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

function validateOpenUIArgument(
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

function openUIReferences(value: OpenUIValue): string[] {
  if (value.kind === "reference") return [value.id];
  if (value.kind === "array") return value.items.flatMap(openUIReferences);
  return [];
}

function openUIStateReferences(value: OpenUIValue): string[] {
  if (value.kind === "state") return [value.name];
  if (value.kind === "array") return value.items.flatMap(openUIStateReferences);
  return [];
}

function openUIStringValue(declaration: OpenUIComponentDeclaration, index: number): string {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "string" }>).value;
}

function openUINumberValue(declaration: OpenUIComponentDeclaration, index: number): number {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "number" }>).value;
}

function openUIBooleanValue(declaration: OpenUIComponentDeclaration, index: number): boolean {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "boolean" }>).value;
}

function openUIStateName(declaration: OpenUIComponentDeclaration, index: number): string {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "state" }>).name;
}

function openUIArrayItems(declaration: OpenUIComponentDeclaration, index: number): OpenUIValue[] {
  return (declaration.arguments[index] as Extract<OpenUIValue, { kind: "array" }>).items;
}

function openUIStateInitialValue(
  declaration: OpenUIComponentDeclaration,
  argumentIndex: number,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
): number {
  const stateName = openUIStateName(declaration, argumentIndex);
  const state = statesByName.get(stateName)!;
  return (state.value as Extract<OpenUIValue, { kind: "number" }>).value;
}

function openUIStringStateInitialValue(
  declaration: OpenUIComponentDeclaration,
  argumentIndex: number,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
): string {
  const stateName = openUIStateName(declaration, argumentIndex);
  const state = statesByName.get(stateName)!;
  return (state.value as Extract<OpenUIValue, { kind: "string" }>).value;
}

function openUIArrayStateInitialValues(
  declaration: OpenUIComponentDeclaration,
  argumentIndex: number,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
): OpenUIValue[] {
  const stateName = openUIStateName(declaration, argumentIndex);
  const state = statesByName.get(stateName)!;
  return (state.value as Extract<OpenUIValue, { kind: "array" }>).items;
}

function validateOpenUIReactiveName(
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

function validateOpenUIIndexedState(
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

function validateOpenUIComponentSemantics(
  scene: RichAnswerSceneParam,
  declaration: OpenUIComponentDeclaration,
  statesByName: ReadonlyMap<string, OpenUIStateDeclaration>,
  componentsByID: ReadonlyMap<string, OpenUIComponentDeclaration>,
): void {
  const fail = (message: string, fix: string, argumentIndex?: number): never => openUIProgramFailure(
    scene.id,
    `组件 ${declaration.id}（${declaration.component}）${message}`,
    fix,
    declaration.line,
    argumentIndex === undefined ? declaration.column : declaration.arguments[argumentIndex].column,
  );
  const validateNamedState = (nameIndex: number, stateIndex: number): void =>
    validateOpenUIReactiveName(scene, declaration, nameIndex, stateIndex);

  switch (declaration.component) {
    case "ParameterSlider": {
      validateNamedState(0, 2);
      const minimum = openUINumberValue(declaration, 3);
      const maximum = openUINumberValue(declaration, 4);
      const step = openUINumberValue(declaration, 5);
      const initialValue = openUIStateInitialValue(declaration, 2, statesByName);
      if (maximum <= minimum || step <= 0 || initialValue < minimum || initialValue > maximum) {
        fail(
          `的范围无效：minimum=${minimum}、maximum=${maximum}、step=${step}、初值=${initialValue}`,
          "保证 maximum > minimum、step > 0，且状态初值位于范围内",
          3,
        );
      }
      return;
    }
    case "ParameterReadout":
      validateNamedState(0, 1);
      return;
    case "ValuePicker": {
      validateNamedState(0, 2);
      const initialValue = openUIStateInitialValue(declaration, 2, statesByName);
      const options = openUIArrayItems(declaration, 3).map((value) =>
        (value as Extract<OpenUIValue, { kind: "number" }>).value
      );
      if (!options.includes(initialValue)) {
        fail(`的状态初值 ${initialValue} 不在 options 中`, "把状态初值设为 options 中的一个数字", 2);
      }
      return;
    }
    case "FunctionPlot": {
      validateNamedState(2, 3);
      const minimum = openUINumberValue(declaration, 5);
      const maximum = openUINumberValue(declaration, 6);
      if (maximum <= minimum) fail("的横轴范围无效", "保证 xMaximum 大于 xMinimum", 5);
      return;
    }
    case "ComparisonTable": {
      validateNamedState(0, 1);
      const initialValue = openUIStateInitialValue(declaration, 1, statesByName);
      const coefficients = openUIArrayItems(declaration, 2).map((value) => {
        const row = componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!;
        return openUINumberValue(row, 1);
      });
      if (!coefficients.includes(initialValue)) {
        fail(`的焦点初值 ${initialValue} 没有对应 ComparisonRow`, "让 $focus 初值等于某一行的 coefficient", 1);
      }
      return;
    }
    case "ProcessStepper":
      validateNamedState(0, 1);
      validateOpenUIIndexedState(scene, declaration, 1, openUIArrayItems(declaration, 2).length, statesByName);
      return;
    case "QuadraticMechanism":
      validateNamedState(0, 1);
      validateOpenUIIndexedState(scene, declaration, 1, 4, statesByName);
      return;
    case "LinkedDataChart": {
      validateNamedState(0, 1);
      const labelCount = openUIArrayItems(declaration, 3).length;
      validateOpenUIIndexedState(scene, declaration, 1, labelCount, statesByName);
      for (const value of openUIArrayItems(declaration, 4)) {
        const seriesID = (value as Extract<OpenUIValue, { kind: "reference" }>).id;
        const series = componentsByID.get(seriesID)!;
        const valueCount = openUIArrayItems(series, 2).length;
        if (valueCount !== labelCount) {
          fail(
            `引用的序列 ${seriesID} 有 ${valueCount} 个值，但 xLabels 有 ${labelCount} 项`,
            "让每个 ChartSeries.values 与 xLabels 等长",
            4,
          );
        }
      }
      return;
    }
    case "ExecutionFrame": {
      const valueCount = openUIArrayItems(declaration, 2).length;
      const changedIndices = openUIArrayItems(declaration, 3).map((value) =>
        (value as Extract<OpenUIValue, { kind: "number" }>).value
      );
      if (new Set(changedIndices).size !== changedIndices.length || changedIndices.some((index) => index >= valueCount)) {
        fail("的 changedIndices 重复或超出 values 范围", "只保留不重复且小于 values 长度的索引", 3);
      }
      return;
    }
    case "ExecutionTrack": {
      validateNamedState(0, 1);
      const frames = openUIArrayItems(declaration, 4);
      validateOpenUIIndexedState(scene, declaration, 1, frames.length, statesByName);
      const codeLineCount = openUIArrayItems(declaration, 3).length;
      for (const value of frames) {
        const frameID = (value as Extract<OpenUIValue, { kind: "reference" }>).id;
        const frame = componentsByID.get(frameID)!;
        if (openUINumberValue(frame, 1) >= codeLineCount) {
          fail(`引用的执行帧 ${frameID} 指向不存在的代码行`, "让每个 ExecutionFrame.activeLine 小于 codeLines 长度", 4);
        }
      }
      return;
    }
    case "ArgumentReader":
      validateNamedState(0, 1);
      validateOpenUIIndexedState(scene, declaration, 1, openUIArrayItems(declaration, 3).length, statesByName);
      return;
    case "CausalTrack":
      validateNamedState(0, 1);
      validateOpenUIIndexedState(scene, declaration, 1, openUIArrayItems(declaration, 3).length, statesByName);
      return;
    case "TwoPointLineLab": {
      validateNamedState(0, 1);
      validateNamedState(2, 3);
      validateNamedState(4, 5);
      validateNamedState(6, 7);
      const xMinimum = openUINumberValue(declaration, 9);
      const xMaximum = openUINumberValue(declaration, 10);
      const yMinimum = openUINumberValue(declaration, 11);
      const yMaximum = openUINumberValue(declaration, 12);
      const xValues = [
        openUIStateInitialValue(declaration, 1, statesByName),
        openUIStateInitialValue(declaration, 5, statesByName),
      ];
      const yValues = [
        openUIStateInitialValue(declaration, 3, statesByName),
        openUIStateInitialValue(declaration, 7, statesByName),
      ];
      if (xMaximum <= xMinimum || yMaximum <= yMinimum) {
        fail("的坐标范围无效", "保证 xMaximum > xMinimum 且 yMaximum > yMinimum", 9);
      }
      if (xValues.some((value) => value < xMinimum || value > xMaximum) ||
          yValues.some((value) => value < yMinimum || value > yMaximum)) {
        fail("的初始点超出坐标范围", "把四个点状态初值放进声明的横纵轴范围", 1);
      }
      return;
    }
    case "BalanceExperiment": {
      validateNamedState(0, 1);
      const initialValue = openUIStateInitialValue(declaration, 1, statesByName);
      if (initialValue < -1 || initialValue > 1) {
        fail("的 shift 初值超出 -1 到 1", "把 shift 初值限制在 -1 到 1", 1);
      }
      return;
    }
    case "SpatialRegion":
    case "SpatialPath": {
      if (openUIArrayItems(declaration, 3).length % 2 !== 0) {
        fail("的 coordinates 不是完整的 x,y 坐标对", "让 coordinates 使用偶数个 0–1 数值", 3);
      }
      return;
    }
    case "LayeredSpatialView": {
      validateNamedState(0, 1);
      validateNamedState(2, 3);
      const layers = openUIArrayItems(declaration, 5).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const regions = openUIArrayItems(declaration, 6).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const paths = openUIArrayItems(declaration, 7).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const points = openUIArrayItems(declaration, 8).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const layerKinds = new Map(layers.map((layer) => [
        openUIStringValue(layer, 0),
        openUIStringValue(layer, 2),
      ]));
      if (layerKinds.size !== layers.length) {
        fail("引用了重复的语义图层 id", "让每个 SpatialLayer.id 唯一", 5);
      }
      const spatialItems = [...regions, ...paths, ...points];
      const spatialIDs = spatialItems.map((item) => openUIStringValue(item, 0));
      if (new Set(spatialIDs).size !== spatialIDs.length) {
        fail("引用了重复的区域、路径或点位 id", "让 SpatialRegion、SpatialPath、SpatialPoint 的语义 id 全局唯一", 6);
      }
      const expectedKind: Partial<Record<OpenUIComponentName, string>> = {
        SpatialRegion: "region",
        SpatialPath: "path",
        SpatialPoint: "point",
      };
      const mismatched = spatialItems.find((item) =>
        layerKinds.get(openUIStringValue(item, 1)) !== expectedKind[item.component]
      );
      if (mismatched) {
        fail(
          `中的 ${mismatched.component} ${openUIStringValue(mismatched, 0)} 指向缺失或类型不匹配的图层`,
          "让每个空间对象的 layerID 指向同 kind 的 SpatialLayer",
        );
      }
      const visibleLayerIDs = openUIArrayStateInitialValues(declaration, 1, statesByName).map((value) =>
        (value as Extract<OpenUIValue, { kind: "string" }>).value
      );
      if (new Set(visibleLayerIDs).size !== visibleLayerIDs.length ||
          visibleLayerIDs.some((layerID) => !layerKinds.has(layerID))) {
        fail("的初始可见图层重复或不存在", "让 $visibleLayerIDs 只包含不重复的 SpatialLayer.id", 1);
      }
      const defaultVisibleLayerIDs = layers
        .filter((layer) => openUIBooleanValue(layer, 3))
        .map((layer) => openUIStringValue(layer, 0));
      if (defaultVisibleLayerIDs.length !== visibleLayerIDs.length ||
          defaultVisibleLayerIDs.some((layerID) => !visibleLayerIDs.includes(layerID))) {
        fail(
          "的初始可见状态与 SpatialLayer.defaultVisible 不一致",
          "让 $visibleLayerIDs 恰好包含 defaultVisible 为 true 的图层 id",
          1,
        );
      }
      const pointIDs = new Set(points.map((point) => openUIStringValue(point, 0)));
      const selectedPointID = openUIStringStateInitialValue(declaration, 3, statesByName);
      if (!pointIDs.has(selectedPointID)) {
        fail("的初始选中点不存在", "让 $selectedPointID 等于某个 SpatialPoint.id", 3);
      }
      return;
    }
    case "DistributionBrush": {
      validateNamedState(0, 1);
      validateNamedState(2, 3);
      const values = openUIArrayItems(declaration, 5).map((value) =>
        (value as Extract<OpenUIValue, { kind: "number" }>).value
      );
      const minimum = Math.min(...values);
      const maximum = Math.max(...values);
      const range = maximum - minimum;
      const center = openUIStateInitialValue(declaration, 1, statesByName);
      const span = openUIStateInitialValue(declaration, 3, statesByName);
      if (range <= 0) {
        fail("的总体数值没有分布范围", "至少提供两个不同的有限数值", 5);
      }
      if (span <= 0 || span > range || center - span / 2 < minimum || center + span / 2 > maximum) {
        fail(
          `的初始窗口超出总体范围：center=${center}、span=${span}`,
          "让 span 大于 0 且不超过总体极差，并让窗口完整落在最小值与最大值之间",
          1,
        );
      }
      return;
    }
    case "DependencyFlow": {
      validateNamedState(0, 1);
      validateNamedState(2, 3);
      const assumptions = openUIArrayItems(declaration, 5).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const nodes = openUIArrayItems(declaration, 6).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const metrics = openUIArrayItems(declaration, 7).map((value) =>
        componentsByID.get((value as Extract<OpenUIValue, { kind: "reference" }>).id)!
      );
      const assumptionIDs = assumptions.map((item) => openUIStringValue(item, 0));
      const nodeIDs = nodes.map((item) => openUIStringValue(item, 0));
      const semanticIDs = [...assumptionIDs, ...nodeIDs];
      if (new Set(semanticIDs).size !== semanticIDs.length) {
        fail("的输入假设与计算节点存在重复语义 id", "让 FlowAssumption.id 与 DependencyNode.id 全部唯一", 5);
      }
      const inputValues = openUIArrayStateInitialValues(declaration, 1, statesByName).map((value) =>
        (value as Extract<OpenUIValue, { kind: "number" }>).value
      );
      if (inputValues.length !== assumptions.length) {
        fail("的输入状态数量与 assumptions 不一致", "让 $inputValues 与 assumptions 等长并按相同顺序排列", 1);
      }
      assumptions.forEach((assumption, index) => {
        const minimum = openUINumberValue(assumption, 2);
        const maximum = openUINumberValue(assumption, 3);
        const step = openUINumberValue(assumption, 4);
        if (maximum <= minimum || step <= 0 || inputValues[index] < minimum || inputValues[index] > maximum) {
          fail(
            `的输入 ${openUIStringValue(assumption, 0)} 范围或初值无效`,
            "保证每个输入 maximum > minimum、step > 0，且对应初值位于范围内",
            1,
          );
        }
      });
      validateOpenUIIndexedState(scene, declaration, 3, assumptions.length, statesByName);
      const layerByID = new Map<string, number>(assumptionIDs.map((id) => [id, 0]));
      nodes.forEach((node) => layerByID.set(openUIStringValue(node, 0), openUINumberValue(node, 2)));
      const dependenciesByNode = new Map<string, string[]>();
      nodes.forEach((node) => {
        const nodeID = openUIStringValue(node, 0);
        const layer = openUINumberValue(node, 2);
        const operation = openUIStringValue(node, 3);
        const sources = openUIArrayItems(node, 4).map((value) =>
          (value as Extract<OpenUIValue, { kind: "string" }>).value
        );
        const parameters = openUIArrayItems(node, 5);
        dependenciesByNode.set(nodeID, sources);
        if (new Set(sources).size !== sources.length ||
            sources.some((sourceID) => layerByID.get(sourceID) === undefined || layerByID.get(sourceID)! >= layer)) {
          fail(
            `的节点 ${nodeID} 引用了重复、缺失或非前序来源`,
            "每个 sourceID 必须唯一，并指向输入假设或更低层的 DependencyNode",
            6,
          );
        }
        const exactTwo = operation === "ratio" || operation === "percentChange";
        const exactOne = operation === "identity" || operation === "power";
        if ((exactTwo && sources.length !== 2) || (exactOne && sources.length !== 1)) {
          fail(
            `的节点 ${nodeID} 为 ${operation} 提供了错误数量的来源`,
            `${operation} ${exactTwo ? "必须有两个来源" : "必须有一个来源"}`,
            6,
          );
        }
        if (operation === "difference" && sources.length < 2) {
          fail(`的节点 ${nodeID} 缺少被减项`, "difference 至少提供两个来源", 6);
        }
        if (operation === "weightedSum" &&
            parameters.length !== sources.length && parameters.length !== sources.length + 1) {
          fail(
            `的节点 ${nodeID} 权重数量与来源不一致`,
            "weightedSum 的 parameters 应与来源等长，或多一项作为常数偏置",
            6,
          );
        }
        if (operation === "power" && parameters.length !== 1) {
          fail(`的节点 ${nodeID} 缺少唯一指数`, "power 的 parameters 只提供一个指数", 6);
        }
        if (operation !== "weightedSum" && operation !== "power" && parameters.length !== 0) {
          fail(`的节点 ${nodeID} 不需要 parameters`, `删除 ${operation} 的 parameters`, 6);
        }
      });
      const metricNodeIDs = metrics.map((metric) => openUIStringValue(metric, 0));
      if (metricNodeIDs.some((nodeID) => !nodeIDs.includes(nodeID))) {
        fail("的结果指标引用了不存在的计算节点", "让每个 FlowMetric.nodeID 指向一个 DependencyNode.id", 7);
      }
      const usedIDs = new Set(metricNodeIDs);
      const queue = [...metricNodeIDs];
      while (queue.length > 0) {
        const currentID = queue.pop()!;
        for (const sourceID of dependenciesByNode.get(currentID) ?? []) {
          if (usedIDs.add(sourceID)) queue.push(sourceID);
        }
      }
      const unusedSemanticID = semanticIDs.find((id) => !usedIDs.has(id));
      if (unusedSemanticID) {
        fail(
          `包含未参与任何结果指标的输入或节点 ${unusedSemanticID}`,
          "删除无关声明，或让结果指标的依赖链真实经过该输入或节点",
        );
      }
      return;
    }
    default:
      return;
  }
}

export function validateRichAnswerProgram(
  scene: RichAnswerSceneParam,
  allowedComponents: ReadonlySet<OpenUIComponentName> = new Set(OPENUI_COMPONENT_ORDER),
): number {
  const { program } = scene;
  if (program === undefined) {
    throw new Error(`富回答场景 ${scene.id} 缺少 T1 OpenUI 程序`);
  }
  const source = program.source.trim();
  const sourceLines = source
    .split(/\r?\n/gu)
    .map((text, index) => ({ text, line: index + 1 }))
    .filter(({ text }) => text.trim().length > 0);
  if (!source || source.length > LIMITS.richAnswerProgramSource || sourceLines.length > 48) {
    openUIProgramFailure(scene.id, "程序为空或超出 10,000 字符 / 48 条声明预算", "删掉无关声明，保留解决当前问题所需的组件组合");
  }
  if (
    new Set(program.capabilities).size !== program.capabilities.length ||
    program.capabilities.length > LIMITS.richAnswerProgramCapabilities
  ) {
    openUIProgramFailure(scene.id, "能力声明重复或超出预算", "去重 capabilities，并控制在 8 项以内");
  }
  if (/<\/?(?:script|svg|iframe)\b/iu.test(source) ||
      /(?:javascript:|https?:\/\/|\bQuery\(|\bMutation\(|\bOpenUrl\()/iu.test(source)) {
    openUIProgramFailure(scene.id, "程序包含标记、网络地址或可执行工具", "只提交状态、白名单组件、字面量和组件引用");
  }
  if ((scene.operations ?? []).length > 0) {
    openUIProgramFailure(scene.id, "T1 场景同时提交了旧 operations", "清空 operations，把交互全部放进 OpenUI 状态与组件");
  }

  const declarations: OpenUIDeclaration[] = [];
  const parseErrors: string[] = [];
  for (const { text, line } of sourceLines) {
    try {
      declarations.push(new OpenUILineParser(scene.id, text, line).parse());
    } catch (error) {
      parseErrors.push(error instanceof Error ? error.message : String(error));
    }
  }
  if (parseErrors.length > 0) {
    throw new Error(Array.from(new Set(parseErrors)).slice(0, 12).join("\n"));
  }
  const structuralErrors: string[] = [];
  const captureStructuralError = (validation: () => void): void => {
    try {
      validation();
    } catch (error) {
      structuralErrors.push(error instanceof Error ? error.message : String(error));
    }
  };
  const statesByName = new Map<string, OpenUIStateDeclaration>();
  const componentsByID = new Map<string, OpenUIComponentDeclaration>();
  for (const declaration of declarations) {
    if (declaration.kind === "stateDeclaration") {
      const previous = statesByName.get(declaration.name);
      if (previous) {
        captureStructuralError(() =>
          openUIProgramFailure(
            scene.id,
            `状态 $${declaration.name} 重复声明；首次在第 ${previous.line} 行`,
            "删除重复声明或改用唯一状态名",
            declaration.line,
            declaration.column,
          )
        );
        continue;
      }
      const value = declaration.value;
      const isSupportedScalar = value.kind === "number" || value.kind === "string";
      const isSupportedArray = value.kind === "array" &&
        value.items.length <= 64 &&
        value.items.every((item) => item.kind === "number" || item.kind === "string");
      if (!isSupportedScalar && !isSupportedArray) {
        captureStructuralError(() =>
          openUIProgramFailure(
            scene.id,
            `状态 $${declaration.name} 的初值不是受支持的有限状态`,
            "状态默认写有限数字；只有组件签名明确要求时才写字符串、数字数组或字符串数组",
            declaration.line,
            declaration.value.column,
          )
        );
      }
      statesByName.set(declaration.name, declaration);
      continue;
    }

    if (!allowedComponents.has(declaration.component)) {
      captureStructuralError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 ${declaration.component} 不在本轮目录选择中`,
          `重新调用 ${RICH_ANSWER_CATALOG_TOOL} 选择贴合的知识形状，或只使用本轮返回的组件：${Array.from(allowedComponents).join("、")}`,
          declaration.line,
          declaration.column,
        )
      );
    }

    const previous = componentsByID.get(declaration.id);
    if (previous) {
      captureStructuralError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 id ${declaration.id} 重复声明；首次在第 ${previous.line} 行`,
          "给每个组件声明唯一 id，并更新引用它的数组",
          declaration.line,
          declaration.column,
        )
      );
      continue;
    }
    componentsByID.set(declaration.id, declaration);
  }

  for (const namespaceCollision of Array.from(statesByName.keys()).filter((name) => componentsByID.has(name))) {
    const declaration = componentsByID.get(namespaceCollision)!;
    captureStructuralError(() =>
      openUIProgramFailure(
        scene.id,
        `状态 $${namespaceCollision} 与组件 id ${namespaceCollision} 撞名`,
        "让状态名和组件 id 使用不同且各自唯一的名称",
        declaration.line,
        declaration.column,
      )
    );
  }

  const root = componentsByID.get("root");
  const rootDeclarations = Array.from(componentsByID.values()).filter(
    (declaration) => declaration.component === "RichAnswerRoot",
  );
  if (!root || root.component !== "RichAnswerRoot" || rootDeclarations.length !== 1) {
    captureStructuralError(() =>
      openUIProgramFailure(
        scene.id,
        "程序必须且只能有一个 id 为 root 的 RichAnswerRoot",
        `保留一条 ${OPENUI_COMPONENT_SIGNATURES.RichAnswerRoot} 声明，并把它的 id 写成 root`,
        root?.line,
        root?.column,
      )
    );
  }

  const argumentErrors: string[] = [];
  for (const declaration of componentsByID.values()) {
    const rules = OPENUI_COMPONENT_ARGUMENT_RULES[declaration.component];
    const minimumArgumentCount = rules.filter((rule) => !(rule.kind === "string" && rule.optional)).length;
    if (declaration.arguments.length < minimumArgumentCount || declaration.arguments.length > rules.length) {
      try {
        openUIProgramFailure(
          scene.id,
          `组件 ${declaration.id}（${declaration.component}）需要 ${minimumArgumentCount}${minimumArgumentCount === rules.length ? "" : `–${rules.length}`} 个参数，实际收到 ${declaration.arguments.length} 个`,
          `按 ${OPENUI_COMPONENT_SIGNATURES[declaration.component]} 重写这一行`,
          declaration.line,
          declaration.column,
        );
      } catch (error) {
        argumentErrors.push(error instanceof Error ? error.message : String(error));
      }
      continue;
    }
    declaration.arguments.forEach((value, index) => {
      try {
        validateOpenUIArgument(scene, declaration, value, rules[index], index, statesByName, componentsByID);
      } catch (error) {
        argumentErrors.push(error instanceof Error ? error.message : String(error));
      }
    });
  }
  if (argumentErrors.length === 0) {
    const componentParentCounts = new Map<string, number>();
    for (const declaration of componentsByID.values()) {
      for (const referencedID of declaration.arguments.flatMap(openUIReferences)) {
        componentParentCounts.set(referencedID, (componentParentCounts.get(referencedID) ?? 0) + 1);
      }
    }
    for (const [componentID, count] of Array.from(componentParentCounts.entries()).filter(([, count]) => count > 1)) {
      const declaration = componentsByID.get(componentID)!;
      captureStructuralError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 ${componentID} 被引用了 ${count} 次，组件图不再是单父节点树`,
          "每个组件声明只挂到一个父组件；需要重复呈现时创建不同 id 的独立声明",
          declaration.line,
          declaration.column,
        )
      );
    }

    const visited = new Set<string>();
    const active = new Set<string>();
    const visit = (componentID: string, path: string[]): void => {
      if (active.has(componentID)) {
        const declaration = componentsByID.get(componentID)!;
        captureStructuralError(() =>
          openUIProgramFailure(
            scene.id,
            `组件引用形成循环：${[...path, componentID].join(" → ")}`,
            "让组件只从 root 向下引用，不要反向引用祖先组件",
            declaration.line,
            declaration.column,
          )
        );
        return;
      }
      if (visited.has(componentID)) return;
      active.add(componentID);
      const declaration = componentsByID.get(componentID)!;
      for (const referencedID of declaration.arguments.flatMap(openUIReferences)) {
        visit(referencedID, [...path, componentID]);
      }
      active.delete(componentID);
      visited.add(componentID);
    };
    if (root?.component === "RichAnswerRoot") {
      visit("root", []);
      const orphaned = Array.from(componentsByID.keys()).filter((componentID) => !visited.has(componentID));
      if (orphaned.length > 0) {
        const declaration = componentsByID.get(orphaned[0])!;
        captureStructuralError(() =>
          openUIProgramFailure(
            scene.id,
            `存在未从 root 引用的孤立组件：${orphaned.slice(0, 6).join("、")}`,
            "把需要的组件接入某个 LearningStage，删除其余孤立声明；不能用孤立组件伪造证据绑定",
            declaration.line,
            declaration.column,
          )
        );
      }
    }

    const usedStateNames = new Set(
      Array.from(componentsByID.values()).flatMap((declaration) =>
        declaration.arguments.flatMap(openUIStateReferences)
      ),
    );
    for (const unusedState of Array.from(statesByName.values()).filter((state) => !usedStateNames.has(state.name))) {
      captureStructuralError(() =>
        openUIProgramFailure(
          scene.id,
          `状态 $${unusedState.name} 没有被任何组件使用`,
          "删除该状态，或把它作为对应组件的 $状态参数",
          unusedState.line,
          unusedState.column,
        )
      );
    }
  }

  const declarationErrors = Array.from(new Set([...structuralErrors, ...argumentErrors])).slice(0, 24);
  if (declarationErrors.length > 0) {
    throw new Error(declarationErrors.join("\n"));
  }

  const semanticErrors: string[] = [];
  const captureSemanticError = (validation: () => void): void => {
    try {
      validation();
    } catch (error) {
      semanticErrors.push(error instanceof Error ? error.message : String(error));
    }
  };
  for (const declaration of componentsByID.values()) {
    captureSemanticError(() =>
      validateOpenUIComponentSemantics(scene, declaration, statesByName, componentsByID)
    );
  }

  if (new Set(scene.evidenceIDs).size !== scene.evidenceIDs.length) {
    captureSemanticError(() =>
      openUIProgramFailure(scene.id, "scene.evidenceIDs 包含重复 id", "去重 scene.evidenceIDs，并保留每条真实证据一次")
    );
  }
  const sceneEvidenceIDs = new Set(scene.evidenceIDs);
  const boundEvidenceIDs = new Set<string>();
  for (const declaration of componentsByID.values()) {
    const evidenceIndex = declaration.component === "EvidenceSnippet"
      ? 0
      : declaration.component === "ArgumentUnit"
        ? 4
      : declaration.component === "CausalEvent"
          ? 7
          : declaration.component === "SpatialPoint"
            ? 7
          : undefined;
    if (evidenceIndex === undefined) continue;
    if (declaration.arguments[evidenceIndex] === undefined || declaration.arguments[evidenceIndex].kind === "null") continue;
    const evidenceID = openUIStringValue(declaration, evidenceIndex);
    if (!sceneEvidenceIDs.has(evidenceID)) {
      captureSemanticError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 ${declaration.id} 引用了未在 scene.evidenceIDs 声明的证据 ${JSON.stringify(evidenceID)}`,
          "改用本场景 evidenceIDs 中的真实 id，或把经过 evidenceLedger 校验的 id 加入 scene.evidenceIDs",
          declaration.line,
          declaration.arguments[evidenceIndex].column,
        )
      );
    }
    boundEvidenceIDs.add(evidenceID);
  }
  const missingEvidenceIDs = scene.evidenceIDs.filter((evidenceID) => !boundEvidenceIDs.has(evidenceID));
  if (missingEvidenceIDs.length > 0) {
    captureSemanticError(() =>
      openUIProgramFailure(
        scene.id,
        `证据没有绑定到可达的 EvidenceSnippet、ArgumentUnit、CausalEvent 或 SpatialPoint：${missingEvidenceIDs.join("、")}`,
        "把每个 scene.evidenceIDs 真实放进至少一个证据组件；普通字符串出现该 id 不算绑定",
      )
    );
  }
  if (semanticErrors.length > 0) {
    throw new Error(Array.from(new Set(semanticErrors)).slice(0, 12).join("\n"));
  }

  const usedComponents = Array.from(componentsByID.values()).map((declaration) => declaration.component);
  const actualGraphics = usedComponents.some((component) => OPENUI_CANVAS_COMPONENTS.has(component))
    ? "canvas"
    : "dom";
  const actualDirectManipulation = usedComponents.some((component) =>
    OPENUI_DIRECT_MANIPULATION_COMPONENTS.has(component)
  );
  program.graphics = actualGraphics;
  program.directManipulation = actualDirectManipulation;
  return actualDirectManipulation ? 1 : 0;
}

function validateRichAnswerUI(
  scene: RichAnswerSceneParam,
  allowedEvidenceIDs: ReadonlySet<string>,
  allowedAssetIDs: ReadonlySet<string>,
): number {
  const ui = scene.ui!;
  const validationIssues: string[] = [];
  const issue = (message: string): void => {
    if (!validationIssues.includes(message) && validationIssues.length < 24) {
      validationIssues.push(message);
    }
  };
  if (ui.nodes.length === 0 || ui.nodes.length > LIMITS.richAnswerUINodes) {
    issue(`富回答场景 ${scene.id} 的 UI 节点数量无效`);
  }
  const datasets = ui.datasets ?? [];
  const bindings = ui.bindings ?? [];
  const rows = datasets.flatMap((dataset) => dataset.rows);
  if (rows.length > LIMITS.richAnswerUIRows || bindings.length > LIMITS.richAnswerUIBindings) {
    issue(`富回答场景 ${scene.id} 的 UI 数据或绑定超出预算`);
  }

  const nodeIDs = ui.nodes.map((node) => node.id);
  const datasetIDs = datasets.map((dataset) => dataset.id);
  const bindingIDs = bindings.map((binding) => binding.id);
  const rowIDs = rows.map((row) => row.id);
  const allIDs = [...nodeIDs, ...datasetIDs, ...bindingIDs, ...rowIDs];
  if (new Set(allIDs).size !== allIDs.length) {
    issue(`富回答场景 ${scene.id} 的 UI 节点、数据行和绑定 id 必须唯一`);
  }

  const nodesByID = new Map(ui.nodes.map((node) => [node.id, node]));
  const datasetsByID = new Map(datasets.map((dataset) => [dataset.id, dataset]));
  const bindingsByID = new Map(bindings.map((binding) => [binding.id, binding]));
  if (!nodesByID.has(ui.rootID)) {
    issue(`富回答场景 ${scene.id} 的 UI 根节点不存在`);
  }

  const parentCounts = new Map<string, number>();
  for (const node of ui.nodes) {
    const children = node.children ?? [];
    if (children.some((childID) => !nodesByID.has(childID))) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 存在悬空子节点`);
    }
    children.forEach((childID) => parentCounts.set(childID, (parentCounts.get(childID) ?? 0) + 1));
    if (RICH_ANSWER_UI_CONTAINER_ROLES.has(node.role)) {
      if (children.length === 0) {
        issue(`富回答场景 ${scene.id} 的 UI 容器 ${node.id} 不能为空`);
      }
    } else if (node.role === "canvas") {
      if (
        children.length === 0 ||
        children.some((childID) => !RICH_ANSWER_UI_CANVAS_ROLES.has(nodesByID.get(childID)?.role ?? ""))
      ) {
        issue(`富回答场景 ${scene.id} 的 canvas 只能包含视觉图元`);
      }
      if (
        (node.xAxis !== undefined && node.xAxis.maximum <= node.xAxis.minimum) ||
        (node.yAxis !== undefined && node.yAxis.maximum <= node.yAxis.minimum)
      ) {
        issue(`富回答场景 ${scene.id} 的 canvas 坐标范围无效`);
      }
    } else if (children.length > 0) {
      issue(`富回答场景 ${scene.id} 的 UI 叶子节点 ${node.id} 不能包含子节点`);
    }

    if (node.role === "grid" && (node.columns === undefined || node.columns < 2 || node.columns > 3)) {
      issue(`富回答场景 ${scene.id} 的 grid 只能使用两列或三列`);
    }
    if (node.role !== "grid" && node.columns !== undefined) {
      issue(`富回答场景 ${scene.id} 的非 grid 节点不能声明 columns`);
    }
    if (node.datasetID !== undefined && !datasetsByID.has(node.datasetID)) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 引用了不存在的数据集`);
    }
    if (RICH_ANSWER_UI_DATASET_ROLES.has(node.role) && node.datasetID === undefined) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 必须引用数据集`);
    }
    if (
      RICH_ANSWER_UI_BINDING_ROLES.has(node.role) &&
      (node.bindingID === undefined || !bindingsByID.has(node.bindingID))
    ) {
      issue(`富回答场景 ${scene.id} 的 UI 控件 ${node.id} 引用了不存在的绑定`);
    }
    if (node.bindingID !== undefined && !bindingsByID.has(node.bindingID)) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 引用了不存在的绑定`);
    }
    if (node.role === "text" && !hasMeaningfulText(node.text) && !hasMeaningfulText(node.label)) {
      issue(`富回答场景 ${scene.id} 的文本节点 ${node.id} 不能为空`);
    }
    if (node.role === "sequence") {
      const dataset = node.datasetID === undefined ? undefined : datasetsByID.get(node.datasetID);
      if (dataset === undefined || dataset.rows.length < 2) {
        issue(`富回答场景 ${scene.id} 的 sequence 节点 ${node.id} 必须引用至少两行数据`);
      } else if (dataset.rows.some((row) => !hasMeaningfulText(row.label))) {
        issue(`富回答场景 ${scene.id} 的 sequence 节点 ${node.id} 每行都必须提供可见 label`);
      }
    }
    if (node.role === "shape") {
      const hasDataset = node.datasetID !== undefined;
      const hasBinding = node.bindingID !== undefined;
      if (node.shape === undefined || node.fill === undefined || node.region === undefined) {
        issue(`富回答场景 ${scene.id} 的 shape 节点 ${node.id} 缺少形状、填充或区域`);
      }
      if (hasBinding && !hasDataset) {
        issue(`富回答场景 ${scene.id} 的可移动 shape 节点 ${node.id} 必须引用 dataset`);
      }
    } else if (node.shape !== undefined) {
      issue(`富回答场景 ${scene.id} 只有 shape 节点可以声明 shape`);
    }
    if (
      node.fill !== undefined &&
      !["shape", "bar", "dotMatrix", "region", "area"].includes(node.role)
    ) {
      issue(`富回答场景 ${scene.id} 的节点 ${node.id} 不能声明 fill`);
    }
    if (node.region !== undefined) {
      if (
        (node.region.x + node.region.width > 1 || node.region.y + node.region.height > 1)
      ) {
        issue(`富回答场景 ${scene.id} 的 UI 区域 ${node.id} 超出归一化边界`);
      }
    }
    if (node.role === "region" && node.region === undefined) {
      issue(`富回答场景 ${scene.id} 的 region 节点 ${node.id} 缺少区域`);
    }
    if (node.role === "image") {
      if (node.assetID === undefined || !allowedAssetIDs.has(node.assetID)) {
        issue(`富回答场景 ${scene.id} 的 image 节点引用了未开放资源`);
      }
    } else if (node.assetID !== undefined) {
      issue(`富回答场景 ${scene.id} 只有 image 节点可以引用资源`);
    }
    if ((node.evidenceIDs ?? []).some((evidenceID) => !allowedEvidenceIDs.has(evidenceID))) {
      issue(`富回答场景 ${scene.id} 的 UI 节点 ${node.id} 引用了不存在的证据`);
    }
    if (node.role === "evidence" && (node.evidenceIDs ?? []).length === 0) {
      issue(`富回答场景 ${scene.id} 的 evidence 节点没有来源`);
    }
  }

  if ((parentCounts.get(ui.rootID) ?? 0) !== 0 || Array.from(parentCounts.values()).some((count) => count > 1)) {
    issue(`富回答场景 ${scene.id} 的 UI 必须是单父节点树`);
  }
  const visited = new Set<string>();
  const active = new Set<string>();
  const visit = (nodeID: string, depth: number): boolean => {
    const node = nodesByID.get(nodeID);
    if (!node || depth > 7 || active.has(nodeID)) return false;
    if (visited.has(nodeID)) return true;
    active.add(nodeID);
    let isValid = true;
    for (const childID of node.children ?? []) {
      if (!visit(childID, depth + 1)) isValid = false;
    }
    active.delete(nodeID);
    if (!isValid) return false;
    visited.add(nodeID);
    return true;
  };
  if (!nodesByID.has(ui.rootID) || !visit(ui.rootID, 1) || visited.size !== ui.nodes.length) {
    issue(`富回答场景 ${scene.id} 的 UI 存在循环、孤立节点或嵌套过深`);
  }
  const reachableNodes = ui.nodes.filter((node) => visited.has(node.id));
  const reachableDatasetIDs = new Set(
    reachableNodes
      .map((node) => node.datasetID)
      .filter((datasetID): datasetID is string => datasetID !== undefined),
  );

  for (const dataset of datasets) {
    if (dataset.rows.length === 0) {
      issue(`富回答场景 ${scene.id} 的数据集 ${dataset.id} 不能为空`);
    }
    for (const row of dataset.rows) {
      const hasSecondPoint = row.x2 !== undefined || row.y2 !== undefined;
      if (hasSecondPoint && (row.x2 === undefined || row.y2 === undefined)) {
        issue(`富回答场景 ${scene.id} 的数据行 ${row.id} 矢量端点不完整`);
      }
      if ((row.evidenceIDs ?? []).some((evidenceID) => !allowedEvidenceIDs.has(evidenceID))) {
        issue(`富回答场景 ${scene.id} 的数据行 ${row.id} 引用了不存在的证据`);
      }
    }
  }
  for (const binding of bindings) {
    if (
      binding.maximum <= binding.minimum ||
      binding.step <= 0 ||
      binding.initialValue < binding.minimum ||
      binding.initialValue > binding.maximum
    ) {
      issue(`富回答场景 ${scene.id} 的 UI 绑定 ${binding.id} 范围无效`);
    }
    const hasControl = reachableNodes.some((node) =>
      node.bindingID === binding.id && RICH_ANSWER_UI_BINDING_ROLES.has(node.role)
    );
    const hasDrivenOutput = reachableNodes.some((node) =>
      node.bindingID === binding.id && RICH_ANSWER_UI_BINDING_OUTPUT_ROLES.has(node.role)
    );
    if (!hasControl || !hasDrivenOutput) {
      issue(`富回答场景 ${scene.id} 的 UI 绑定 ${binding.id} 必须同时驱动可见控件和图元或读数`);
    } else if (!richAnswerBindingHasChangingOutcome(binding, reachableNodes, datasetsByID)) {
      issue(`富回答场景 ${scene.id} 的 UI 绑定 ${binding.id} 没有产生可验证的语义状态或派生量变化`);
    }
  }

  const boundEvidenceIDs = new Set([
    ...reachableNodes.flatMap((node) => node.evidenceIDs ?? []),
    ...datasets
      .filter((dataset) => reachableDatasetIDs.has(dataset.id))
      .flatMap((dataset) => dataset.rows.flatMap((row) => row.evidenceIDs ?? [])),
  ]);
  const unboundEvidenceIDs = scene.evidenceIDs.filter(
    (evidenceID) => !boundEvidenceIDs.has(evidenceID),
  );
  if (unboundEvidenceIDs.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的证据没有绑定到可达 UI 节点或数据行：${unboundEvidenceIDs.join("、")}`,
    );
  }

  const primaryControlCount = ui.nodes.filter((node) =>
    RICH_ANSWER_UI_PRIMARY_CONTROL_ROLES.has(node.role)
  ).length;
  if (primaryControlCount > 2) {
    issue(`富回答场景 ${scene.id} 最多只能展示两个主要控件`);
  }
  if (validationIssues.length > 0) {
    throw new Error(validationIssues.join("\n"));
  }
  return primaryControlCount + (ui.nodes.some((node) => node.role === "sequence") ? 1 : 0);
}

function richAnswerBindingHasChangingOutcome(
  binding: RichAnswerUIBindingParam,
  reachableNodes: RichAnswerUINodeParam[],
  datasetsByID: ReadonlyMap<string, RichAnswerUIDatasetParam>,
): boolean {
  return reachableNodes
    .filter((node) =>
      node.bindingID === binding.id && RICH_ANSWER_UI_BINDING_OUTPUT_ROLES.has(node.role)
    )
    .some((node) => {
      if (node.datasetID === undefined) return false;
      const dataset = datasetsByID.get(node.datasetID);
      if (dataset === undefined) return false;
      return richAnswerRowsHaveChangingOutcome(dataset.rows, node.role === "sequence");
    });
}

function richAnswerRowsHaveChangingOutcome(
  rows: RichAnswerUIDataRowParam[],
  acceptsSemanticOnly: boolean,
): boolean {
  if (rows.length < 2) return false;
  const signature = (row: RichAnswerUIDataRowParam): string => [
    row.value ?? "",
    row.result ?? "",
    row.x,
    row.y,
    row.x2 ?? "",
    row.y2 ?? "",
    row.label?.trim().toLocaleLowerCase() ?? "",
  ].join("|");
  const signatures = new Set(rows.map(signature));
  const numericSets = [
    rows.map((row) => row.value).filter((value): value is number => value !== undefined),
    rows.map((row) => row.result).filter((value): value is number => value !== undefined),
    rows.map((row) => row.x),
    rows.map((row) => row.y),
    rows.map((row) => row.x2).filter((value): value is number => value !== undefined),
    rows.map((row) => row.y2).filter((value): value is number => value !== undefined),
  ];
  const hasVaryingNumericState = numericSets.some((values) => new Set(values).size >= 2);
  const hasVaryingSemanticState = new Set(
    rows
      .map((row) => row.label?.trim().toLocaleLowerCase() ?? "")
      .filter((label) => label.length > 0),
  ).size >= 2;
  return signatures.size >= 2 && (hasVaryingNumericState || (acceptsSemanticOnly && hasVaryingSemanticState));
}

function generatedProgramComponents(source: string): Set<string> {
  return new Set(
    source
      .split(/\r?\n/u)
      .map((line) => line.trim().match(/^[A-Za-z][A-Za-z0-9_]*\s*=\s*([A-Za-z][A-Za-z0-9_]*)\(/u)?.[1])
      .filter((component): component is string => component !== undefined),
  );
}

function validateGeneratedRichAnswerFamilyContract(scene: RichAnswerSceneParam): void {
  const components = scene.program === undefined
    ? new Set<string>()
    : generatedProgramComponents(scene.program.source);
  const roles = new Set((scene.ui?.nodes ?? []).map((node) => node.role));
  const nodes = scene.ui?.nodes ?? [];
  const dataRowCount = (scene.ui?.datasets ?? [])
    .reduce((count, dataset) => count + dataset.rows.length, 0);
  const bindingCount = scene.ui?.bindings?.length ?? 0;
  const usesComponent = (...names: string[]) => names.some((name) => components.has(name));
  const usesRole = (...candidates: string[]) => candidates.some((role) => roles.has(role));
  const hasEvidenceNode = roles.has("evidence");
  const semanticRelationLabelCount = nodes.filter((node) =>
    ["label", "text", "sequence", "metric"].includes(node.role) &&
      (
        (node.evidenceIDs ?? []).length > 0 ||
        node.datasetID !== undefined ||
        (node.text !== undefined && node.text.trim().length > 0)
      )
  ).length;
  const hasQuantityCanvas = usesRole("canvas") &&
    usesRole("axis", "line", "path", "point", "area", "bar", "dotMatrix", "vector", "metric");

  let isValid = false;
  switch (scene.family) {
    case "textAndAlignment":
      isValid = usesComponent("ArgumentReader", "ArgumentUnit", "ComparisonTable") ||
        (roles.has("text") && (roles.has("evidence") || usesRole("select", "toggle", "probe")));
      break;
    case "quantityAndCoordinates":
      isValid = usesComponent(
        "FunctionPlot", "TwoPointLineLab", "LinkedDataChart", "DistributionBrush",
        "DependencyFlow", "ComparisonTable", "MetricStrip",
      ) || (
        hasQuantityCanvas && dataRowCount > 0 && (bindingCount > 0 || usesRole("metric"))
      );
      break;
    case "processAndState":
      isValid = usesComponent(
        "ProcessStepper", "QuadraticMechanism", "ExecutionTrack", "BalanceExperiment",
        "ArgumentReader", "CausalTrack",
      ) || roles.has("sequence") || (
        usesRole("slider", "scrubber", "select", "toggle", "probe") &&
        (dataRowCount >= 2 || roles.has("text") || roles.has("metric"))
      );
      break;
    case "relationAndEvidence":
      isValid = usesComponent(
        "ArgumentReader", "CausalTrack", "DependencyFlow", "LayeredSpatialView", "ComparisonTable",
      ) || (
        hasEvidenceNode &&
        (
          (roles.has("sequence") && dataRowCount >= 2) ||
          (usesRole("path", "line", "vector") && semanticRelationLabelCount >= 2)
        )
      );
      break;
    case "timeAndSpace":
      isValid = usesComponent("CausalTrack", "LayeredSpatialView", "LinkedDataChart") || (
        usesRole("canvas", "image") && usesRole("path", "point", "region", "vector", "area")
      ) || (roles.has("sequence") && dataRowCount >= 2);
      break;
    case "imageAndOverlay":
      isValid = roles.has("image") && usesRole("region", "path", "point", "shape");
      break;
    case "comparisonAndEvaluation": {
      const comparisonValueCount = (scene.ui?.nodes ?? []).filter((node) =>
        ["metric", "text", "label", "bar", "dotMatrix"].includes(node.role)
      ).length;
      isValid = usesComponent(
        "ComparisonTable", "LinkedDataChart", "DistributionBrush", "ArgumentReader",
        "MetricStrip", "DependencyFlow",
      ) || (usesRole("grid", "hstack", "vstack") && comparisonValueCount >= 2);
      break;
    }
    case "calculationAndConstraints":
      isValid = usesComponent(
        "DependencyFlow", "FunctionPlot", "TwoPointLineLab", "QuadraticMechanism",
        "DistributionBrush", "BalanceExperiment",
      ) || (
        bindingCount > 0 && roles.has("metric") &&
        usesRole("slider", "scrubber", "probe") &&
        usesRole("shape", "line", "path", "bar", "metric")
      );
      break;
  }

  if (!isValid) {
    throw new Error(`富回答场景 ${scene.id} 的生成结构不满足声明的 ${scene.family} 能力合同`);
  }
}

function visibleRichAnswerUISemanticText(scene: RichAnswerSceneParam): string {
  const ui = scene.ui;
  if (ui === undefined) return scene.title ?? scene.id;
  return [
    scene.title,
    ...ui.nodes.flatMap((node) => [
      node.label,
      node.text,
      node.unit,
      node.xAxis?.label,
      node.yAxis?.label,
    ]),
    ...(ui.datasets ?? []).flatMap((dataset) => dataset.rows.map((row) => row.label)),
    ...(ui.bindings ?? []).flatMap((binding) => [binding.label, binding.unit]),
  ]
    .filter((value): value is string => value !== undefined && value.trim().length > 0)
    .join(" ");
}

function semanticTextIncludes(haystack: string, needle: string): boolean {
  const normalizedHaystack = richAnswerSemanticSearchText(haystack);
  const normalizedNeedle = richAnswerSemanticSearchText(needle);
  if (normalizedNeedle.length === 1) {
    if (/^[a-z]$/i.test(normalizedNeedle)) {
      const escaped = normalizedNeedle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(`(^|[^a-z0-9])${escaped}($|[^a-z0-9])`, "iu").test(haystack);
    }
    return normalizedHaystack.includes(normalizedNeedle);
  }
  if (normalizedNeedle.length < 2) return false;
  if (normalizedHaystack.includes(normalizedNeedle)) return true;
  if (normalizedNeedle.length <= 4) return false;
  const characters = Array.from(normalizedNeedle);
  const bigrams = new Set(characters.slice(0, -1).map((character, index) =>
    `${character}${characters[index + 1]}`
  ));
  if (bigrams.size === 0) return false;
  const matchedBigrams = Array.from(bigrams)
    .filter((bigram) => normalizedHaystack.includes(bigram)).length;
  const requiredRatio = normalizedNeedle.length <= 8 ? 0.6 : 0.45;
  return matchedBigrams >= 2 && matchedBigrams / bigrams.size >= requiredRatio;
}

function richAnswerSemanticSearchText(text: string): string {
  return Array.from(text.toLocaleLowerCase())
    .filter((character) => /[\p{Letter}\p{Number}=²π√∝Δ<>\/≤≥±]/u.test(character))
    .join("");
}

const RICH_ANSWER_INTERACTION_PROCESS_PATTERN =
  /(?:拖动|滑动|调节|调整|切换|选择|点击|探查|探针|观察|联动|播放|暂停|步进|筛选|缩放|旋转|重置|对照|比较)/u;

function richAnswerUIHasBoundSemanticInteraction(scene: RichAnswerSceneParam): boolean {
  const ui = scene.ui;
  if (ui === undefined || (ui.bindings ?? []).length === 0) return false;
  const datasetsByID = new Map((ui.datasets ?? []).map((dataset) => [dataset.id, dataset]));
  return (ui.bindings ?? []).some((binding) => {
    const hasControl = ui.nodes.some((node) =>
      node.bindingID === binding.id && RICH_ANSWER_UI_BINDING_ROLES.has(node.role)
    );
    const drivenNodes = ui.nodes.filter((node) =>
      node.bindingID === binding.id && RICH_ANSWER_UI_BINDING_OUTPUT_ROLES.has(node.role)
    );
    return hasControl && drivenNodes.some((node) => {
      if (node.datasetID === undefined) return false;
      const dataset = datasetsByID.get(node.datasetID);
      return dataset !== undefined && richAnswerRowsHaveChangingOutcome(
        dataset.rows,
        node.role === "sequence",
      );
    });
  });
}

const RICH_ANSWER_GENERIC_RELATION_BIGRAMS = new Set([
  "通过", "变化", "观察", "对应", "关系", "增加", "减少", "上升", "下降", "影响", "结果", "条件", "数据",
]);

function richAnswerSemanticAnchorTokens(text: string): string[] {
  const matches = text.match(/[A-Za-z]+|[0-9]+(?:\.[0-9]+)?|[πΔ√][A-Za-z0-9]+/gu) ?? [];
  return Array.from(new Set(matches.map((match) => match.toLocaleLowerCase())));
}

function richAnswerHanBigrams(text: string): string[] {
  const runs = text.match(/[\p{Script=Han}]+/gu) ?? [];
  const bigrams = runs.flatMap((run) => {
    const characters = Array.from(run);
    return characters.slice(0, -1).map((character, index) =>
      `${character}${characters[index + 1]}`
    );
  }).filter((bigram) => !RICH_ANSWER_GENERIC_RELATION_BIGRAMS.has(bigram));
  return Array.from(new Set(bigrams));
}

function richAnswerRelationHasVisibleAnchors(visibleText: string, relation: string): boolean {
  if (semanticTextIncludes(visibleText, relation)) return true;
  const tokenMatches = richAnswerSemanticAnchorTokens(relation)
    .filter((token) => semanticTextIncludes(visibleText, token)).length;
  const bigramMatches = richAnswerHanBigrams(relation)
    .filter((bigram) => visibleText.includes(bigram)).length;
  return tokenMatches >= 2 || bigramMatches >= 2 || (tokenMatches >= 1 && bigramMatches >= 1);
}

function richAnswerUIHasSemanticRelationStructure(
  scene: RichAnswerSceneParam,
  relations: string[],
  visibleText: string,
): boolean {
  const ui = scene.ui;
  if (ui === undefined) return false;
  if (!relations.some((relation) => richAnswerRelationHasVisibleAnchors(visibleText, relation))) {
    return false;
  }
  const relationRoles = new Set([
    "line", "path", "point", "area", "bar", "dotMatrix", "vector", "sequence", "metric",
  ]);
  const datasetsByID = new Map((ui.datasets ?? []).map((dataset) => [dataset.id, dataset]));
  const hasNamedAxis = ui.nodes.some((node) =>
    (node.xAxis?.label?.trim().length ?? 0) > 0 || (node.yAxis?.label?.trim().length ?? 0) > 0
  );
  const hasNamedBinding = (ui.bindings ?? []).some((binding) => binding.label.trim().length > 0);
  return ui.nodes.some((node) => {
    if (!relationRoles.has(node.role) || node.datasetID === undefined) return false;
    const dataset = datasetsByID.get(node.datasetID);
    if (dataset === undefined || !richAnswerRowsHaveChangingOutcome(
      dataset.rows,
      node.role === "sequence",
    )) return false;
    const hasVisibleLabel = (node.label?.trim().length ?? 0) > 0 ||
      dataset.rows.some((row) => (row.label?.trim().length ?? 0) > 0);
    return hasVisibleLabel || hasNamedAxis || hasNamedBinding;
  });
}

function richAnswerBoundedVisibleSemanticSummary(scene: RichAnswerSceneParam): string {
  const roles = Array.from(new Set(scene.ui?.nodes.map((node) => node.role) ?? [])).join(",");
  const visibleText = visibleRichAnswerUISemanticText(scene).replace(/\s+/g, " ").trim();
  const summary = `roles=${roles || "none"}; text=${visibleText || "none"}`;
  return summary.length <= 360 ? summary : `${summary.slice(0, 357)}...`;
}

function richAnswerDeclarationSamples(values: string[]): string {
  return values.slice(0, 2).join("、");
}

function validateGeneratedRichAnswerIntentContract(
  scene: RichAnswerSceneParam,
  plan: RichAnswerExpressionPlanParam,
): void {
  if (scene.ui === undefined) return;
  const declaresIntent = (plan.knowledgeNatures?.length ?? 0) > 0 ||
    (plan.knowledgeObjects?.length ?? 0) > 0 ||
    (plan.knowledgeRelations?.length ?? 0) > 0 ||
    (plan.knowledgeProcesses?.length ?? 0) > 0 ||
    (plan.visualPrimitives?.length ?? 0) > 0 ||
    (plan.visualRationale?.length ?? 0) > 0;
  if (!declaresIntent) return;

  const roles = new Set(scene.ui.nodes.map((node) => node.role));
  for (const primitive of plan.visualPrimitives ?? []) {
    if (!RICH_ANSWER_T2_PRIMITIVE_ROLE_SET.has(primitive)) {
      throw new Error(`富回答表达计划声明了 T2 目录外原语：${primitive}`);
    }
    if (!roles.has(primitive)) {
      throw new Error(`富回答场景 ${scene.id} 没有兑现表达计划声明的原语：${primitive}`);
    }
  }

  const visibleText = visibleRichAnswerUISemanticText(scene);
  const missingCategories: string[] = [];
  const knowledgeObjects = plan.knowledgeObjects ?? [];
  if (knowledgeObjects.length > 0) {
    const matchedObjectCount = knowledgeObjects.filter((concept) =>
      semanticTextIncludes(visibleText, concept)
    ).length;
    const requiredObjectCount = Math.min(2, knowledgeObjects.length);
    if (matchedObjectCount < requiredObjectCount) {
      missingCategories.push(`知识对象（至少可见 ${requiredObjectCount} 项）：${richAnswerDeclarationSamples(knowledgeObjects)}`);
    }
  }

  const knowledgeRelations = plan.knowledgeRelations ?? [];
  if (
    knowledgeRelations.length > 0 &&
    !knowledgeRelations.some((relation) => semanticTextIncludes(visibleText, relation)) &&
    !richAnswerUIHasSemanticRelationStructure(scene, knowledgeRelations, visibleText)
  ) {
    missingCategories.push(`知识关系：${richAnswerDeclarationSamples(knowledgeRelations)}`);
  }

  const knowledgeProcesses = plan.knowledgeProcesses ?? [];
  if (knowledgeProcesses.length > 0) {
    const hasVisibleProcess = knowledgeProcesses.some((process) =>
      semanticTextIncludes(visibleText, process)
    );
    const declaresInteractiveProcess = knowledgeProcesses.some((process) =>
      RICH_ANSWER_INTERACTION_PROCESS_PATTERN.test(process)
    );
    const processHasVisibleAnchors = knowledgeProcesses.some((process) =>
      richAnswerRelationHasVisibleAnchors(visibleText, process)
    );
    const hasStructuredProcess =
      (scene.ui.nodes.some((node) => node.role === "sequence") && processHasVisibleAnchors) ||
      (richAnswerUIHasBoundSemanticInteraction(scene) &&
        (declaresInteractiveProcess || processHasVisibleAnchors));
    if (!hasVisibleProcess && !hasStructuredProcess) {
      missingCategories.push(`知识过程：${richAnswerDeclarationSamples(knowledgeProcesses)}`);
    }
  }

  if (missingCategories.length > 0) {
    throw new Error(
      `富回答场景 ${scene.id} 没有呈现声明的语义类别：${missingCategories.join("；")}；` +
      `可见语义摘要：${richAnswerBoundedVisibleSemanticSummary(scene)}`,
    );
  }

  const embodiedNatures = new Set([
    "objectMechanism",
    "spatialStructure",
    "imageObservation",
  ]);
  const requiresEmbodiedVisual = (plan.knowledgeNatures ?? []).some((nature) =>
    embodiedNatures.has(nature)
  );
  if (!requiresEmbodiedVisual) return;

  const embodiedRoles = new Set([
    "shape",
    "vector",
    "region",
    "image",
    "area",
    "sequence",
    "bar",
    "dotMatrix",
    "line",
    "path",
    "point",
    "metric",
  ]);
  if (!Array.from(embodiedRoles).some((role) => roles.has(role))) {
    throw new Error(`富回答场景 ${scene.id} 必须把物体、空间或图像知识绑定到可见语义图元`);
  }
  const bindings = scene.ui.bindings ?? [];
  if (bindings.length > 0) {
    const controlDrivesEmbodiedMark = bindings.some((binding) =>
      scene.ui!.nodes.some((node) => node.bindingID === binding.id && embodiedRoles.has(node.role))
    );
    if (!controlDrivesEmbodiedMark) {
      throw new Error(`富回答场景 ${scene.id} 的控件必须改变与知识对象绑定的可见图元或读数`);
    }
  }
}

function validateRichAnswerFamilyContract(scene: RichAnswerSceneParam): void {
  const supportedOperations = RICH_ANSWER_SUPPORTED_OPERATIONS[scene.family];
  if (!supportedOperations) {
    throw new Error(`富回答场景 ${scene.id} 的 family 不受支持`);
  }

  const unsupportedOperation = (scene.operations ?? []).find(
    (operation) => !supportedOperations.has(operation.kind),
  );
  if (unsupportedOperation) {
    throw new Error(
      `富回答场景 ${scene.id} 的 ${scene.family} 渲染器不支持 ${unsupportedOperation.kind} 操作`,
    );
  }

  switch (scene.family) {
    case "textAndAlignment": {
      const selectableTextIDs = new Set(
        (scene.objects ?? [])
          .filter((object) => object.kind === "text" && hasMeaningfulText(object.text))
          .map((object) => object.id),
      );
      if (!operationTargetsAtLeast(scene, "select", 1, selectableTextIDs)) {
        throw new Error(`富回答场景 ${scene.id} 的文本族必须提供可选择的文本对象`);
      }
      return;
    }
    case "quantityAndCoordinates": {
      const coordinateFrameIDs = new Set(
        (scene.frames ?? [])
          .filter((frame) => frame.kind === "cartesian")
          .map((frame) => frame.id),
      );
      const plottedObjects = (scene.objects ?? []).filter((object) =>
        (object.kind === "quantity" || object.kind === "dataPoint") &&
          isNormalizedPoint(object.coordinate) &&
          object.frameID !== undefined &&
          coordinateFrameIDs.has(object.frameID),
      );
      if (coordinateFrameIDs.size === 0 || plottedObjects.length < 2) {
        throw new Error(`富回答场景 ${scene.id} 的数量族必须有至少两个坐标点和坐标框`);
      }
      return;
    }
    case "processAndState": {
      const processObjectIDs = new Set(
        (scene.objects ?? [])
          .filter((object) => object.kind === "step" || object.kind === "state")
          .map((object) => object.id),
      );
      if (
        processObjectIDs.size < 2 ||
        !operationTargetsAtLeast(scene, "step", 2, processObjectIDs) ||
        !operationTargetsAtLeast(scene, "playPause", 2, processObjectIDs)
      ) {
        throw new Error(`富回答场景 ${scene.id} 的过程族必须有至少两个步骤/状态，并提供 step 与 playPause`);
      }
      return;
    }
    case "relationAndEvidence": {
      if ((scene.relations ?? []).length === 0) {
        throw new Error(`富回答场景 ${scene.id} 的关系族必须至少有一条关系`);
      }
      return;
    }
    case "timeAndSpace": {
      const navigableFrameIDs = new Set(
        (scene.frames ?? [])
          .filter((frame) => frame.kind === "timeline" || frame.kind === "space")
          .map((frame) => frame.id),
      );
      const navigableObjectIDs = new Set(
        (scene.objects ?? [])
          .filter((object) =>
            isNormalizedPoint(object.coordinate) &&
              object.frameID !== undefined &&
              navigableFrameIDs.has(object.frameID),
          )
          .map((object) => object.id),
      );
      const scrubTargetIDs = new Set([...navigableObjectIDs, ...navigableFrameIDs]);
      if (
        navigableFrameIDs.size === 0 ||
        navigableObjectIDs.size < 2 ||
        !operationTargetsAtLeast(scene, "scrub", 1, scrubTargetIDs)
      ) {
        throw new Error(`富回答场景 ${scene.id} 的时间空间族必须有 timeline/space frame 和 scrub`);
      }
      return;
    }
    case "imageAndOverlay": {
      const imageFrames = (scene.frames ?? []).filter(
        (frame) => frame.kind === "image" && frame.assetID !== undefined,
      );
      const imageFrameIDs = new Set(imageFrames.map((frame) => frame.id));
      const frameAssetIDs = new Set(imageFrames.flatMap((frame) => frame.assetID ?? []));
      const imageObjects = (scene.objects ?? []).filter((object) =>
        object.kind === "image" &&
          object.assetID !== undefined &&
          frameAssetIDs.has(object.assetID) &&
          object.frameID !== undefined &&
          imageFrameIDs.has(object.frameID),
      );
      const regionObjects = (scene.objects ?? []).filter((object) =>
        object.kind === "region" &&
          object.bounds !== undefined &&
          object.frameID !== undefined &&
          imageFrameIDs.has(object.frameID),
      );
      if (imageFrames.length === 0 || imageObjects.length === 0 || regionObjects.length === 0) {
        throw new Error(`富回答场景 ${scene.id} 的图像叠层族必须有 image、region、frame 和 asset`);
      }
      return;
    }
    case "comparisonAndEvaluation": {
      const objectIDs = new Set((scene.objects ?? []).map((object) => object.id));
      if (!operationTargetsAtLeast(scene, "compare", 2, objectIDs)) {
        throw new Error(`富回答场景 ${scene.id} 的比较族必须有至少两个 compare 对象目标`);
      }
      return;
    }
    case "calculationAndConstraints": {
      const hasFormula = (scene.objects ?? []).some(
        (object) => object.kind === "formula" && hasMeaningfulText(object.text),
      );
      const hasConstraint = (scene.objects ?? []).some(
        (object) => object.kind === "constraint" && hasMeaningfulText(object.text),
      );
      const frameIDs = new Set((scene.frames ?? []).map((frame) => frame.id));
      const hasDeterministicAdjust = (scene.operations ?? []).some((operation) => {
        if (operation.kind !== "adjust" || operation.parameter === undefined) return false;
        const samples = numericCoordinateSamples(scene, operation, frameIDs);
        return samples.length >= 2 &&
          new Set(samples.map((sample) => sample.coordinate?.x)).size >= 2;
      });
      if (!hasFormula || !hasConstraint || !hasDeterministicAdjust) {
        throw new Error(`富回答场景 ${scene.id} 的计算族必须有 formula/constraint 和可插值 adjust 样本`);
      }
      return;
    }
    default:
      throw new Error(`富回答场景 ${scene.id} 的 family 不受支持`);
  }
}

export default function weibeiExtension(pi: ExtensionAPI) {
  let requiredContextRevision: string | undefined;
  let lastReadContextRevision: string | undefined;
  let lastReadMemoryRevision: number | undefined;
  let richAnswerAttemptCount = 0;
  let richAnswerCatalogRevision: string | undefined;
  let richAnswerCatalogSelection: Set<OpenUIComponentName> | undefined;
  const searchedCourseItemIDs = new Set<string>();

  pi.registerTool({
    name: CONTEXT_TOOL,
    label: "读取魏碑上下文",
    description:
      "读取本轮受限的魏碑上下文快照。每轮必须先调用一次，并且只能依据返回的当前材料、笔记和选区回答。",
    promptSnippet: "读取当前魏碑材料、笔记、选区与上下文修订号",
    parameters: Type.Object({}, { additionalProperties: false }),
    executionMode: "sequential",
    async execute() {
      const snapshot = await readCurrentSnapshot();
      requiredContextRevision = snapshot.contextRevision;
      lastReadContextRevision = snapshot.contextRevision;
      richAnswerCatalogRevision = undefined;
      richAnswerCatalogSelection = undefined;

      const details: ContextToolDetails = {
        kind: "weibei_context",
        schemaVersion: 2,
        contextRevision: snapshot.contextRevision,
        snapshot,
      };

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                contextRevision: snapshot.contextRevision,
                material: snapshot.material,
                note: snapshot.note,
                selection: snapshot.selection,
                recentMessages: snapshot.recentMessages,
                course: {
                  title: snapshot.course.title,
                  catalogCount: snapshot.course.catalog.length,
                  searchCandidateCount: snapshot.course.items.length,
                  relationCount: snapshot.course.relations.length,
                  isTruncated: snapshot.course.isTruncated,
                },
                learning: {
                  revision: snapshot.learning.memoryRevision,
                  hasLastLocation: snapshot.learning.lastLocation !== undefined,
                  memoryCount: snapshot.learning.memories.length,
                  session: snapshot.learning.session,
                },
              },
              null,
              2,
            ),
          },
        ],
        details,
      };
    },
  });

  pi.registerTool({
    name: COURSE_MAP_TOOL,
    label: "查看课程地图",
    description:
      "分页返回当前课程的材料、笔记、标签与长期关联。只有需要跨文件理解或导航时才调用。",
    promptSnippet: "查看课程里有哪些材料、笔记和已确认关联",
    parameters: Type.Object(
      {
        offset: Type.Optional(Type.Integer({ minimum: 0 })),
        limit: Type.Optional(
          Type.Integer({ minimum: 1, maximum: LIMITS.courseMapPageItems }),
        ),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const snapshot = await readCurrentSnapshot();
      if (lastReadContextRevision !== snapshot.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      const offset = params.offset ?? 0;
      const limit = params.limit ?? 40;
      const catalog = snapshot.course.catalog.slice(offset, offset + limit).map((item) => ({
        ...item,
        jumpReference: courseJumpReference(snapshot.course, item),
      }));
      const pageCatalogIDs = new Set(catalog.map((item) => item.id));
      const catalogByID = new Map(
        snapshot.course.catalog.map((item) => [item.id, item] as const),
      );
      const relations = snapshot.course.relations
        .filter(
          (relation) =>
            pageCatalogIDs.has(relation.noteItemID) ||
            pageCatalogIDs.has(relation.sourceItemID),
        )
        .map((relation) => ({
          ...relation,
          noteTitle: catalogByID.get(relation.noteItemID)!.title,
          sourceTitle: catalogByID.get(relation.sourceItemID)!.title,
        }));
      const total = snapshot.course.catalog.length;
      const page = {
        title: snapshot.course.title,
        offset,
        limit,
        total,
        hasMore: offset + catalog.length < total,
        catalog,
        relations,
        isTruncated: snapshot.course.isTruncated,
      };
      const details: CourseMapToolDetails = {
        kind: "course_map",
        contextRevision: snapshot.contextRevision,
        ...page,
      };
      return {
        content: [{ type: "text", text: JSON.stringify(page, null, 2) }],
        details,
      };
    },
  });

  pi.registerTool({
    name: COURSE_SEARCH_TOOL,
    label: "搜索课程关联",
    description:
      "在魏碑已建立的课程索引片段中搜索相关材料与笔记，返回可用于说明关联和跳转的精确标题。",
    promptSnippet: "按概念或学习问题搜索课程文件",
    parameters: Type.Object(
      {
        query: Type.String({ minLength: 1, maxLength: 500 }),
        limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 8 })),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const snapshot = await readCurrentSnapshot();
      if (lastReadContextRevision !== snapshot.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      const query = params.query.trim();
      const results = searchCourse(snapshot.course, query, params.limit ?? 5);
      results
        .filter((item) => item.searchText.trim().length > 0)
        .forEach((item) => searchedCourseItemIDs.add(item.id));
      const presentedResults = results.map((item) => {
        const hasEvidence = item.searchText.trim().length > 0;
        const sectionJumpReferences =
          hasEvidence && item.kind === "html"
            ? item.headings
                .slice(0, 5)
                .map((heading) => courseJumpReference(snapshot.course, item, heading))
            : [];
        const pageJumpReferences =
          hasEvidence && item.kind === "pdf"
            ? item.headings
                .filter((heading) => coursePage(heading) !== undefined)
                .slice(0, 5)
                .map((heading) => courseJumpReference(snapshot.course, item, heading))
            : [];
        return {
          ...item,
          headings: item.headings.map((heading) => courseHeading(heading).title),
          evidenceLabel: hasEvidence ? courseEvidenceLabel(snapshot.course, item) : undefined,
          jumpReference: hasEvidence ? courseJumpReference(snapshot.course, item) : undefined,
          sectionJumpReferences,
          pageJumpReferences,
        };
      });
      const evidenceLabels = presentedResults.flatMap((item) =>
        item.evidenceLabel ? [item.evidenceLabel] : [],
      );
      const jumpEvidence = Object.fromEntries(
        presentedResults.flatMap((item) => {
          if (!item.evidenceLabel || !item.jumpReference) return [];
          return [item.jumpReference, ...item.sectionJumpReferences, ...item.pageJumpReferences]
            .map((jumpReference) => [jumpReference, item.evidenceLabel] as const);
        }),
      );
      const jumpReferences = Object.keys(jumpEvidence);
      const details: CourseSearchToolDetails = {
        kind: "course_search",
        contextRevision: snapshot.contextRevision,
        query,
        results,
        evidenceLabels,
        jumpReferences,
        jumpEvidence,
      };
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              presentedResults,
              null,
              2,
            ),
          },
        ],
        details,
      };
    },
  });

  pi.registerTool({
    name: RICH_ANSWER_CATALOG_TOOL,
    label: "选择生成式视觉能力",
    description:
      "在提交富回答前，根据本轮学习动作、知识形状、来源媒介、直接操作和呈现表面，检索相关的魏碑 T1 组件组与 T2 通用原语提示。它返回相关子集，不返回固定场景或标准答案；问题变化时可以重新调用。",
    promptSnippet:
      "先描述学习动作和知识形状，取得相关组件签名；不要让不断增长的完整目录挤进每次生成",
    parameters: Type.Object(
      {
        learningAction: Type.Union(
          RICH_ANSWER_LEARNING_ACTIONS.map((value) => Type.Literal(value)),
        ),
        knowledgeShapes: Type.Array(
          Type.Union(
            [
              "formula",
              "series",
              "distribution",
              "process",
              "algorithmState",
              "argument",
              "causalSequence",
              "spatialLayers",
              "dependencyGraph",
              "comparison",
              "imageRegions",
              "customGeometry",
            ].map((value) => Type.Literal(value)),
          ),
          { minItems: 1, maxItems: 3 },
        ),
        knowledgeNatures: Type.Array(
          Type.Union(RICH_ANSWER_KNOWLEDGE_NATURES.map((value) => Type.Literal(value))),
          { minItems: 1, maxItems: 4 },
        ),
        knowledgeObjects: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 1,
          maxItems: 6,
        }),
        knowledgeRelations: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 0,
          maxItems: 6,
        }),
        knowledgeProcesses: Type.Array(Type.String({ minLength: 1, maxLength: 160 }), {
          minItems: 0,
          maxItems: 6,
        }),
        interactions: Type.Array(
          Type.Union(
            RICH_ANSWER_INTERACTION_ACTIONS.map((value) => Type.Literal(value)),
          ),
          { minItems: 1, maxItems: 3 },
        ),
        sourceMedium: Type.Union(
          ["text", "table", "code", "image", "map", "mixed"].map((value) => Type.Literal(value)),
        ),
        surface: Type.Union(
          ["inline", "expanded", "focus"].map((value) => Type.Literal(value)),
        ),
        reason: Type.String({ minLength: 1, maxLength: 500 }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const current = await readCurrentSnapshot();
      if (lastReadContextRevision !== current.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      const selectedGroups = selectedOpenUIComponentGroups(
        params.knowledgeShapes,
        params.interactions,
      );
      const selectedComponents = new Set<OpenUIComponentName>(OPENUI_ALWAYS_COMPONENTS);
      selectedGroups.forEach((group) => {
        OPENUI_COMPONENT_GROUPS[group].components.forEach((component) => selectedComponents.add(component));
      });
      richAnswerCatalogRevision = current.contextRevision;
      richAnswerCatalogSelection = selectedComponents;

      const result = {
        contextRevision: current.contextRevision,
        decision: {
          learningAction: params.learningAction,
          knowledgeShapes: params.knowledgeShapes,
          knowledgeNatures: params.knowledgeNatures,
          knowledgeObjects: params.knowledgeObjects,
          knowledgeRelations: params.knowledgeRelations,
          knowledgeProcesses: params.knowledgeProcesses,
          interactions: params.interactions,
          sourceMedium: params.sourceMedium,
          surface: params.surface,
          reason: params.reason.trim(),
        },
        selectedGroups: selectedGroups.map((group) => ({
          id: group,
          label: OPENUI_COMPONENT_GROUPS[group].label,
        })),
        actionBus: {
          learningActions: RICH_ANSWER_LEARNING_ACTIONS,
          interactions: RICH_ANSWER_INTERACTION_ACTIONS,
          rule: "交互只能落到 T1 operation 或 T2 binding；不得提交 HTML/JS 回调、外部事件或自造 action 类型。",
        },
        t1: {
          catalogSize: OPENUI_COMPONENT_CATALOG_SIZE,
          allowedComponentCount: selectedComponents.size,
          signatures: openUIComponentCatalog(Array.from(selectedComponents)),
          syntaxRules: [
            "每行只声明一个状态或组件；先声明子组件，再由父组件引用。",
            "组件引用数组写 [step1, step2]，引用 id 不加引号；不要在参数中嵌套组件调用。",
            "枚举参数只能写签名或指导中列出的固定值；FunctionPlot.family 当前只能写 \"quadratic\"，不是公式输入框。",
          ],
        },
        t2: {
          useWhen: "返回的 T1 组件无法诚实表达当前知识形状时，组合通用原语；不要为题目另造专属整页组件。",
          guidance: COMPOSABLE_PRIMITIVE_CATALOG.split("\n"),
          intentGuidance: [
            "不要按 knowledgeNatures 机械套固定 role 组合；曲线、点、区域、图像、形状、序列、读数都只是可组合的视觉语法。",
            "line/path/point/metric 可以在函数、过程、机制、论证或证据场景中成为主表达，前提是它们真实编码了知识对象、关系或状态，而不是装饰线。",
            "只有当材料和问题确实依赖空间位置、图像局部或对象外形时，才需要选择 image、region、shape、area 等对应图元；不要为通过形式检查而硬凑。",
            "有控件时，控件必须改变与学习目标绑定的可见图元或读数；可以同时协调多个控件、图层和状态。",
            "knowledgeObjects 要在可见标签里留下关键锨点；knowledgeRelations 可由有标注的曲线、数据、读数或序列结构编码；knowledgeProcesses 若是拖动、切换、观察等互动，可由真实 binding 结构兑现，不必把计划长句逐字复制进 UI。",
            "visualPrimitives 必须列出实际会使用的 T2 role，后续 weibei_rich_answer 会校验声明与 UI 节点一致。",
          ],
        },
        guardrails: [
          "返回的是相关能力子集和签名，不是固定模板、场景数量上限或标准答案。",
          "T1 程序只能使用本次返回的签名；需要另一类能力时重新调用目录。",
          "T2 必须从 rootID 开始形成单父节点树；孤立节点、只在不可达 dataset 里放证据、控件不驱动图元或读数都会被拒绝。",
          "不要引入 Card、Tabs、KPI、Slide、Gallery 这类整页看板组件；要把视觉、控件和读数作为回答流里的内联体验块。",
          "先核对结论、公式、单位、数值、方向和因果边界；不能验证的结果不得交给界面假装计算。",
          "无论 T1 或 T2，最终内容、单位、关系与来源都必须由本轮真实材料支撑。",
        ],
      };
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {
          kind: "rich_answer_catalog",
          contextRevision: current.contextRevision,
          selectedGroups,
          allowedComponents: Array.from(selectedComponents),
        },
      };
    },
  });

  pi.registerTool({
    name: RICH_ANSWER_TOOL,
    label: "插入生成式视觉体验",
    description:
      `当可视化或直接操作能明显帮助理解时，在 Agent 回答流中插入受控的生成式视觉体验块。提交前必须先调用 ${RICH_ANSWER_CATALOG_TOOL}；T1 只能使用本轮目录返回的签名，T2 使用受控通用原语。它不是第二篇回答或完整网页。${RICH_ANSWER_FAMILY_CONTRACT}`,
    promptSnippet:
      "先判断文本是否足够；需要时优先选择贴合的 T1 深组件，否则用 T2 通用原语组合，不要画 SVG、套完整网页外壳或从头复述正文",
    parameters: richAnswerEnvelopeSchema,
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      richAnswerAttemptCount += 1;
      const remainingAttempts = Math.max(0, 3 - richAnswerAttemptCount);
      if (richAnswerAttemptCount > 3) {
        throw new Error(richAnswerFaultMessage({
          code: "attempts_exhausted",
          jsonPath: "$",
          message: "本轮富回答最多提交三次；坏 payload 不会被渲染。",
          humanFixHint: "停止调用 weibei_rich_answer，用普通文本诚实降级；正文只回答用户问题和真实限制，不要提富回答校验、协议失败、repair_fault、payload 或内部工具错误。",
        }, 0));
      }
      try {
        const current = await readCurrentSnapshot();
        if (lastReadContextRevision !== current.contextRevision) {
          richAnswerFault({
            code: "context_required",
            jsonPath: "$.contextRevision",
            field: "contextRevision",
            message: `必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`,
            humanFixHint: `先调用 ${CONTEXT_TOOL}，再基于返回的 contextRevision 重新提交完整 RichAnswerUI。`,
          });
        }
        if (params.contextRevision !== current.contextRevision) {
          richAnswerFault({
            code: "stale_context",
            jsonPath: "$.contextRevision",
            field: "contextRevision",
            message: "富回答的 contextRevision 与当前上下文不匹配",
            humanFixHint: "丢弃旧 payload，重新读取上下文并用当前 contextRevision 重发完整 RichAnswerUI。",
          });
        }
        if (
          richAnswerCatalogRevision !== current.contextRevision ||
          richAnswerCatalogSelection === undefined
        ) {
          richAnswerFault({
            code: "catalog_required",
            jsonPath: "$.scenes",
            field: "scenes",
            message: `提交富回答前必须先调用 ${RICH_ANSWER_CATALOG_TOOL} 取得本轮相关能力子集`,
            humanFixHint: `先调用 ${RICH_ANSWER_CATALOG_TOOL} 取得本轮 T1/T2 能力，再重发完整 RichAnswerUI。`,
          });
        }

      const sceneIDs = params.scenes.map((scene) => scene.id);
      if (new Set(sceneIDs).size !== sceneIDs.length) {
        richAnswerFault({
          code: "duplicate_id",
          jsonPath: "$.scenes[*].id",
          field: "id",
          message: "富回答场景 id 必须唯一",
          humanFixHint: "为每个 scene 重新分配唯一 id，并同步 narrative 中所有场景标记后完整重发。",
        });
      }
      let plainNarrative = "";
      try {
        plainNarrative = validateRichAnswerNarrativeFlow(params.narrative, sceneIDs);
      } catch (error) {
        richAnswerFault({
          code: "narrative_flow",
          jsonPath: "$.narrative",
          field: "narrative",
          message: error instanceof Error ? error.message : String(error),
          humanFixHint: "修正正文中的来源标签与 <!-- weibei-scene:场景ID --> 插入点，然后完整重发 RichAnswerUI。",
        });
      }
      const evidenceIDs: string[] = params.evidenceLedger.map((entry) => entry.id);
      if (new Set(evidenceIDs).size !== evidenceIDs.length) {
        richAnswerFault({
          code: "duplicate_id",
          jsonPath: "$.evidenceLedger[*].id",
          field: "id",
          message: "富回答证据 id 必须唯一",
          humanFixHint: "为 evidenceLedger 去重并同步 scene.evidenceIDs、T1 证据组件或 T2 evidenceIDs 后完整重发。",
        });
      }

      const allowedAssetIDs = new Set<string>(
        current.course.catalog
          .filter((item) => item.isCurrentMaterial || searchedCourseItemIDs.has(item.id))
          .map((item) => item.id),
      );
      const evidenceTextByLabel = richAnswerEvidenceText(current, searchedCourseItemIDs);
      const normalizedEvidenceLedger = params.evidenceLedger.map((entry) => {
        const sourceLabel = canonicalRichAnswerEvidenceLabel(
          entry.sourceLabel,
          evidenceTextByLabel.keys(),
        );
        const source = sourceLabel ? evidenceTextByLabel.get(sourceLabel) : undefined;
        if (!source || !sourceLabel) {
          richAnswerFault({
            code: "source_not_available",
            jsonPath: "$.evidenceLedger[*].sourceLabel",
            field: "sourceLabel",
            message: `富回答引用了本轮未读取或无法唯一对应的来源：${entry.sourceLabel}；可用标签：${Array.from(evidenceTextByLabel.keys()).join("、")}`,
            humanFixHint: "只使用本轮 context 或 course_search 返回的真实来源标签，修正 evidenceLedger 后完整重发。",
          });
        }
        const excerpt = normalizedEvidenceText(entry.excerpt);
        if (!excerpt || !normalizedEvidenceText(source.text).includes(excerpt)) {
          richAnswerFault({
            code: "excerpt_mismatch",
            jsonPath: "$.evidenceLedger[*].excerpt",
            field: "excerpt",
            message: `富回答证据摘录不在对应来源中：${sourceLabel}`,
            humanFixHint: "从该来源已读取文本中逐字截取短摘录，并同步相关 scene 证据绑定后完整重发。",
          });
        }
        if ((entry.assetIDs ?? []).some((assetID) => !allowedAssetIDs.has(assetID))) {
          richAnswerFault({
            code: "unauthorized_asset",
            jsonPath: "$.evidenceLedger[*].assetIDs",
            field: "assetIDs",
            message: `富回答证据引用了本轮未开放的本地资源：${sourceLabel}`,
            humanFixHint: "只使用当前材料或本轮搜索开放的 item.id 作为资源，修正 evidenceLedger 后完整重发。",
          });
        }
        return { ...entry, sourceLabel, isTruncated: source.isTruncated, tags: [] };
      });
      const missingNarrativeSources = Array.from(
        new Set<string>(normalizedEvidenceLedger.map((entry) => entry.sourceLabel)),
      ).filter((sourceLabel) => !plainNarrative.includes(sourceLabel));
      if (missingNarrativeSources.length > 0) {
        richAnswerFault({
          code: "missing_evidence",
          jsonPath: "$.narrative",
          field: "narrative",
          message: `富回答 narrative 没有就近标注已使用的真实来源：${missingNarrativeSources.join("、")}`,
          humanFixHint: "在正文相关结论旁加入对应来源标签，并完整重发 RichAnswerUI。",
        });
      }

      const allowedEvidenceIDs = new Set<string>(evidenceIDs);
      let operationCount = 0;
      for (const [sceneIndex, scene] of params.scenes.entries()) {
        const scenePath = `$.scenes[${sceneIndex}]`;
        if ((scene.program === undefined) === (scene.ui === undefined)) {
          richAnswerFault({
            code: "scene_layer_choice",
            jsonPath: scenePath,
            sceneID: scene.id,
            field: scene.program === undefined ? "ui" : "program",
            message: `富回答场景 ${scene.id} 必须且只能提交 program 或 ui 之一`,
            humanFixHint: "T1 深组件只保留 program；T2 原语只保留 ui。删除另一层后完整重发 RichAnswerUI。",
          });
        }
        const objects = scene.objects ?? [];
        const objectIDs = objects.map((object) => object.id);
        const relationIDs = (scene.relations ?? []).map((relation) => relation.id);
        const operationIDs = (scene.operations ?? []).map((operation) => operation.id);
        const frameIDs = (scene.frames ?? []).map((frame) => frame.id);
        const localIDs = [...objectIDs, ...relationIDs, ...operationIDs, ...frameIDs];
        if (new Set(localIDs).size !== localIDs.length) {
          richAnswerFault({
            code: "duplicate_id",
            jsonPath: `${scenePath}.id`,
            sceneID: scene.id,
            field: "id",
            message: `富回答场景 ${scene.id} 内的所有 id 必须唯一`,
            humanFixHint: "为本 scene 内对象、关系、操作、坐标框重新分配唯一 id，并同步引用后完整重发。",
          });
        }
        const knownObjects = new Set(objectIDs);
        const knownFrames = new Set(frameIDs);
        const referableIDs = new Set([...objectIDs, ...relationIDs, ...frameIDs]);
        if (
          (scene.relations ?? []).some(
            (relation) =>
              !knownObjects.has(relation.sourceID) || !knownObjects.has(relation.targetID),
          )
        ) {
          richAnswerFault({
            code: "broken_reference",
            jsonPath: `${scenePath}.relations`,
            sceneID: scene.id,
            field: "relations",
            message: `富回答场景 ${scene.id} 存在悬空关系`,
            humanFixHint: "让每个 relation.sourceID/targetID 指向本 scene 内真实 object.id，或删除该关系后完整重发。",
          });
        }
        if (
          (scene.operations ?? []).some((operation) =>
            operation.targetIDs.some((targetID) => !referableIDs.has(targetID)) ||
            (operation.frameID !== undefined && !knownFrames.has(operation.frameID)),
          )
        ) {
          richAnswerFault({
            code: "broken_reference",
            jsonPath: `${scenePath}.operations`,
            sceneID: scene.id,
            field: "operations",
            message: `富回答场景 ${scene.id} 存在悬空操作目标`,
            humanFixHint: "让 operation.targetIDs/frameID 指向本 scene 内真实对象、关系或坐标框后完整重发。",
          });
        }
        if (
          (scene.frames ?? []).some((frame) =>
            (frame.objectIDs ?? []).some((objectID) => !knownObjects.has(objectID)),
          )
        ) {
          richAnswerFault({
            code: "broken_reference",
            jsonPath: `${scenePath}.frames`,
            sceneID: scene.id,
            field: "frames",
            message: `富回答场景 ${scene.id} 存在悬空坐标框对象`,
            humanFixHint: "让 frame.objectIDs 只引用本 scene 内真实 object.id，或删除悬空对象后完整重发。",
          });
        }
        if (
          objects.some(
            (object) =>
              (object.frameID !== undefined && !knownFrames.has(object.frameID)) ||
              ((object.coordinate !== undefined || object.bounds !== undefined) &&
                object.frameID === undefined),
          )
        ) {
          richAnswerFault({
            code: "broken_reference",
            jsonPath: `${scenePath}.objects`,
            sceneID: scene.id,
            field: "frameID",
            message: `富回答场景 ${scene.id} 存在缺失坐标框的对象`,
            humanFixHint: "凡是声明 coordinate/bounds 的对象都必须填写有效 frameID；修正对象引用后完整重发。",
          });
        }
        if (
          (scene.frames ?? []).some(
            (frame) =>
              (frame.xAxis !== undefined && frame.xAxis.maximum <= frame.xAxis.minimum) ||
              (frame.yAxis !== undefined && frame.yAxis.maximum <= frame.yAxis.minimum),
          )
        ) {
          richAnswerFault({
            code: "invalid_frame",
            jsonPath: `${scenePath}.frames`,
            sceneID: scene.id,
            field: "xAxis/yAxis",
            message: `富回答场景 ${scene.id} 的坐标范围无效`,
            humanFixHint: "确保每个坐标轴 maximum 大于 minimum，单位和方向符合材料后完整重发。",
          });
        }
        if (
          (scene.frames ?? []).some(
            (frame) => frame.kind === "cartesian" &&
              (frame.xAxis === undefined || frame.yAxis === undefined),
          )
        ) {
          richAnswerFault({
            code: "invalid_frame",
            jsonPath: `${scenePath}.frames`,
            sceneID: scene.id,
            field: "xAxis/yAxis",
            message: `富回答场景 ${scene.id} 的笛卡尔坐标框缺少横轴或纵轴`,
            humanFixHint: "cartesian frame 必须同时提供有效 xAxis 与 yAxis；补齐后完整重发。",
          });
        }
        if (
          (scene.operations ?? []).some((operation) => {
            const parameter = operation.parameter;
            return parameter !== undefined &&
              (parameter.maximum <= parameter.minimum ||
                parameter.initialValue < parameter.minimum ||
                parameter.initialValue > parameter.maximum);
          })
        ) {
          richAnswerFault({
            code: "invalid_binding",
            jsonPath: `${scenePath}.operations`,
            sceneID: scene.id,
            field: "parameter",
            message: `富回答场景 ${scene.id} 的可调参数范围无效`,
            humanFixHint: "让 minimum < maximum、initialValue 落在范围内、step 大于 0，并完整重发。",
          });
        }
        if (
          objects.some(
            (object) => object.assetID !== undefined && !allowedAssetIDs.has(object.assetID),
          ) ||
          (scene.frames ?? []).some(
            (frame) => frame.assetID !== undefined && !allowedAssetIDs.has(frame.assetID),
          )
        ) {
          richAnswerFault({
            code: "unauthorized_asset",
            jsonPath: scenePath,
            sceneID: scene.id,
            field: "assetID",
            message: `富回答场景 ${scene.id} 引用了本轮未开放的本地资源`,
            humanFixHint: "只引用当前材料或本轮搜索开放的 item.id，并在 evidenceLedger.assetIDs 中同步声明后完整重发。",
          });
        }
        if (
          objects.some(
            (object) =>
              object.bounds !== undefined &&
              (object.bounds.x + object.bounds.width > 1 ||
                object.bounds.y + object.bounds.height > 1),
          )
        ) {
          richAnswerFault({
            code: "invalid_frame",
            jsonPath: `${scenePath}.objects`,
            sceneID: scene.id,
            field: "bounds",
            message: `富回答场景 ${scene.id} 的图像区域超出归一化边界`,
            humanFixHint: "把 x/y/width/height 约束在 0–1 且不越界，确认区域含义后完整重发。",
          });
        }
        const referencedEvidenceIDs = [
          ...scene.evidenceIDs,
          ...objects.flatMap((object) => object.evidenceIDs ?? []),
          ...(scene.relations ?? []).flatMap((relation) => relation.evidenceIDs ?? []),
          ...(scene.frames ?? []).flatMap((frame) => frame.evidenceIDs ?? []),
        ];
        if (referencedEvidenceIDs.some((evidenceID) => !allowedEvidenceIDs.has(evidenceID))) {
          richAnswerFault({
            code: "missing_evidence",
            jsonPath: `${scenePath}.evidenceIDs`,
            sceneID: scene.id,
            field: "evidenceIDs",
            message: `富回答场景 ${scene.id} 引用了不存在的证据`,
            humanFixHint: "让 scene、节点和数据行只引用 evidenceLedger 中已有 id，并把证据真实绑定到 T1 证据组件或 T2 可达节点/数据行后完整重发。",
          });
        }
        try {
          operationCount += scene.program !== undefined
            ? validateRichAnswerProgram(scene, richAnswerCatalogSelection)
            : validateRichAnswerUI(scene, allowedEvidenceIDs, allowedAssetIDs);
        } catch (error) {
          if (error instanceof RichAnswerFaultError) throw error;
          richAnswerFault({
            code: scene.program !== undefined ? "invalid_openui_program" : "invalid_t2_ui",
            jsonPath: `${scenePath}.${scene.program !== undefined ? "program" : "ui"}`,
            sceneID: scene.id,
            field: scene.program !== undefined ? "program" : "ui",
            message: error instanceof Error ? error.message : String(error),
            humanFixHint: scene.program !== undefined
              ? "按行列诊断修正 T1 program；不要局部 patch，必须带完整 envelope、完整 scenes 和 evidenceLedger 重发。"
              : "按 UI 节点、数据集、binding 和证据诊断修正 T2 原语树；不要局部 patch，必须完整重发。",
          });
        }
        try {
          validateGeneratedRichAnswerFamilyContract(scene);
          validateGeneratedRichAnswerIntentContract(scene, params.expressionPlan);
        } catch (error) {
          richAnswerFault({
            code: "weak_ui",
            jsonPath: `${scenePath}.${scene.program !== undefined ? "program" : "ui"}`,
            sceneID: scene.id,
            field: scene.program !== undefined ? "program" : "ui",
            message: error instanceof Error ? error.message : String(error),
            humanFixHint: "对照 message 里的可见语义摘要：未呈现的对象或关系用短标签、坐标、读数或序列补足；已有控件通过 binding 驱动可变图元或读数时，不要重复互动长句；如果 expressionPlan 声明过度，收窄为 UI 真正编码的内容。必须完整重发。",
          });
        }
      }
      const plannedFamilies = new Set(params.expressionPlan.families);
      if (params.scenes.some((scene) => !plannedFamilies.has(scene.family))) {
        richAnswerFault({
          code: "invalid_plan",
          jsonPath: "$.expressionPlan.families",
          field: "families",
          message: "富回答场景能力族没有包含在表达计划中",
          humanFixHint: "让 expressionPlan.families 覆盖所有 scene.family，再完整重发 RichAnswerUI。",
        });
      }

      const details: RichAnswerToolDetails = {
        kind: "rich_answer",
        contextRevision: current.contextRevision,
        envelope: {
          ...params,
          expressionPlan: {
            ...params.expressionPlan,
            directManipulation: operationCount > 0,
          },
          evidenceLedger: normalizedEvidenceLedger,
        },
      };
      return {
        content: [
          {
            type: "text",
            text: "完整 narrative 与生成式视觉体验已通过魏碑的来源、内联位置、组件或原语、状态和资源边界校验，并会作为同一篇回答显示。请勿另写或改写第二份正文，只需简短结束本轮。",
          },
        ],
        details,
      };
      } catch (error) {
        rethrowRichAnswerFault(error, remainingAttempts);
      }
    },
  });

  pi.registerTool({
    name: LEARNING_MEMORY_TOOL,
    label: "读取学习记忆",
    description:
      "读取用户上次学到的位置、当前会话摘要、学习目标、理解、困惑和下一步。记忆不是课程事实证据。",
    promptSnippet: "读取用户学习历史与当前会话状态",
    parameters: Type.Object({}, { additionalProperties: false }),
    executionMode: "sequential",
    async execute() {
      const snapshot = await readCurrentSnapshot();
      if (lastReadContextRevision !== snapshot.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      lastReadMemoryRevision = snapshot.learning.memoryRevision;
      const locationJumpReference = learningLocationJumpReference(snapshot);
      const jumpReferences = locationJumpReference ? [locationJumpReference] : [];
      const jumpEvidence = locationJumpReference
        ? { [locationJumpReference]: "[学习记录：上次位置]" }
        : {};
      const details: LearningMemoryToolDetails = {
        kind: "learning_memory",
        contextRevision: snapshot.contextRevision,
        memoryRevision: snapshot.learning.memoryRevision,
        learning: snapshot.learning,
        jumpReferences,
        jumpEvidence,
      };
      const learningForTool = locationJumpReference && snapshot.learning.lastLocation
        ? {
            ...snapshot.learning,
            lastLocation: {
              ...snapshot.learning.lastLocation,
              jumpReference: locationJumpReference,
            },
          }
        : snapshot.learning;
      return {
        content: [{ type: "text", text: JSON.stringify(learningForTool, null, 2) }],
        details,
      };
    },
  });

  pi.registerTool({
    name: LEARNING_UPDATE_TOOL,
    label: "提出学习状态更新",
    description:
      "向魏碑提交带依据的学习记忆和会话状态建议。它不能修改材料或笔记。",
    promptSnippet: "仅在出现可长期复用的目标、理解、困惑或下一步时提交更新",
    parameters: Type.Object(
      {
        contextRevision: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
        memoryRevision: Type.Integer({ minimum: 0 }),
        sessionSummary: Type.Optional(
          Type.String({ minLength: 1, maxLength: LIMITS.sessionSummary }),
        ),
        suggestedPhase: Type.Optional(
          Type.Union(
            ["orient", "explore", "closeRead", "note", "recall", "consolidate", "plan"].map(
              (value) => Type.Literal(value),
            ),
          ),
        ),
        suggestedNext: Type.Array(Type.String({ minLength: 1, maxLength: 300 }), {
          maxItems: 3,
        }),
        entries: Type.Array(
          Type.Object(
            {
              kind: Type.Union(
                ["goal", "understood", "confusion", "nextStep", "preference"].map((value) =>
                  Type.Literal(value),
                ),
              ),
              text: Type.String({ minLength: 1, maxLength: LIMITS.learningText }),
              evidence: Type.String({ minLength: 1, maxLength: LIMITS.learningEvidence }),
              origin: Type.Union([Type.Literal("userStatement"), Type.Literal("agentInference")]),
            },
            { additionalProperties: false },
          ),
          { maxItems: 12 },
        ),
        resolutions: Type.Optional(
          Type.Array(
            Type.Object(
              {
                memoryID: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
                evidence: Type.String({ minLength: 1, maxLength: LIMITS.learningEvidence }),
              },
              { additionalProperties: false },
            ),
            { maxItems: 12 },
          ),
        ),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const current = await readCurrentSnapshot();
      if (
        lastReadContextRevision !== current.contextRevision ||
        lastReadMemoryRevision !== current.learning.memoryRevision
      ) {
        throw new Error(
          `学习状态已变化；请重新调用 ${CONTEXT_TOOL} 和 ${LEARNING_MEMORY_TOOL}`,
        );
      }
      if (
        params.contextRevision !== current.contextRevision ||
        params.memoryRevision !== current.learning.memoryRevision
      ) {
        throw new Error("学习状态建议的上下文或记忆修订号不匹配");
      }
      const entries = params.entries.map((entry) => ({
        kind: entry.kind as LearningMemoryKind,
        text: entry.text.trim(),
        evidence: entry.evidence.trim(),
        origin: entry.origin as "userStatement" | "agentInference",
      }));
      const allowedEvidencePrefixes = [
        "[用户：本轮]",
        "[会话：当前]",
        ...evidenceLabels(current),
        ...current.course.catalog
          .filter((item) => searchedCourseItemIDs.has(item.id))
          .map((item) => courseEvidenceLabel(current.course, item)),
      ];
      if (
        entries.some(
          (entry) =>
            !entry.text ||
            !entry.evidence ||
            !allowedEvidencePrefixes.some((prefix) => entry.evidence.startsWith(prefix)),
        )
      ) {
        throw new Error("每条学习记忆都必须携带当前用户、会话或来源依据标签");
      }
      if (
        entries.some(
          (entry) =>
            (entry.evidence.startsWith("[用户：本轮]") ||
              entry.evidence.startsWith("[会话：当前]")) &&
            !currentTurnEvidenceMatches(current, entry.evidence),
        )
      ) {
        throw new Error("本轮用户或会话依据必须在标签后逐字引用用户本轮真实原话");
      }
      if (
        entries.some(
          (entry) =>
            entry.origin === "userStatement" && !entry.evidence.startsWith("[用户：本轮]"),
        )
      ) {
        throw new Error("用户陈述型记忆必须直接依据本轮用户原话");
      }
      const suggestedNext = params.suggestedNext
        .map((item) => item.trim())
        .filter((item) => item.length > 0);
      const sessionSummary = params.sessionSummary?.trim();
      const activeMemoryByID = new Map(
        current.learning.memories
          .filter(
            (memory) =>
              memory.status === "active" &&
              ["goal", "confusion", "nextStep"].includes(memory.kind),
          )
          .map((memory) => [memory.id, memory] as const),
      );
      const resolutions = (params.resolutions ?? []).map((resolution) => {
        const memory = activeMemoryByID.get(resolution.memoryID);
        const evidence = resolution.evidence.trim();
        if (!memory) {
          throw new Error("只能结案当前学习记忆中仍处于活跃状态的项目");
        }
        if (!resolutionEvidenceMatches(current, evidence)) {
          throw new Error("学习记忆结案必须逐字引用用户本轮的确认或回忆表现");
        }
        return {
          memoryID: memory.id,
          text: memory.text,
          evidence,
        };
      });
      if (
        !sessionSummary &&
        !params.suggestedPhase &&
        suggestedNext.length === 0 &&
        entries.length === 0 &&
        resolutions.length === 0
      ) {
        throw new Error("学习状态建议不能为空");
      }
      const details: LearningUpdateDetails = {
        kind: "learning_update",
        contextRevision: current.contextRevision,
        memoryRevision: current.learning.memoryRevision,
        sessionSummary,
        suggestedPhase: params.suggestedPhase,
        suggestedNext,
        entries,
        resolutions,
      };
      return {
        content: [
          {
            type: "text",
            text: "学习状态建议已校验并交给魏碑；这不会修改课程材料或用户笔记。",
          },
        ],
        details,
      };
    },
  });

  pi.registerTool({
    name: NOTE_PROPOSAL_TOOL,
    label: "提出笔记建议",
    description:
      "向魏碑返回一份待用户确认的 Markdown 笔记建议。它不会写入笔记；调用前必须先读取当前上下文。",
    promptSnippet: "提交有证据、带当前修订号且尚未写回的笔记建议",
    parameters: Type.Object(
      {
        markdown: Type.String({
          minLength: 1,
          maxLength: LIMITS.proposalMarkdown,
          description: "待用户确认的 Markdown 建议正文",
        }),
        evidence: Type.Array(
          Type.String({ minLength: 1, maxLength: LIMITS.proposalEvidenceText }),
          {
            minItems: 1,
            maxItems: LIMITS.proposalEvidenceItems,
            description: "逐项列出可核对的当前材料、笔记或选区证据",
          },
        ),
        contextRevision: Type.String({
          minLength: 1,
          maxLength: LIMITS.identifier,
          description: "最近一次 weibei_context 返回的 contextRevision",
        }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      const current = await readCurrentSnapshot();
      if (lastReadContextRevision !== current.contextRevision) {
        lastReadContextRevision = undefined;
        throw new Error("魏碑上下文已变化；请重新调用 weibei_context 后再提出笔记建议");
      }
      if (params.contextRevision !== current.contextRevision) {
        throw new Error(
          `笔记建议的 contextRevision 不匹配；当前修订号为 ${current.contextRevision}，请重新读取上下文`,
        );
      }

      const markdown = params.markdown.trim();
      const evidence = params.evidence.map((item) => item.trim()).filter((item) => item.length > 0);
      if (!markdown || evidence.length === 0) {
        throw new Error("笔记建议必须包含非空 Markdown 和至少一条证据");
      }
      const allowedEvidenceLabels = evidenceLabels(current);
      if (evidence.some((item) => !allowedEvidenceLabels.some((label) => item.startsWith(label)))) {
        throw new Error("笔记建议的每条证据都必须以当前材料、笔记或选区的真实来源标签开头");
      }

      const details: NoteProposalDetails = {
        kind: "note_proposal",
        markdown,
        evidence,
        contextRevision: current.contextRevision,
      };

      return {
        content: [
          {
            type: "text",
            text: "笔记建议格式与上下文修订号已校验；这仍是待确认建议，尚未写回任何笔记。",
          },
        ],
        details,
      };
    },
  });

  pi.on("before_agent_start", async (event) => {
    lastReadContextRevision = undefined;
    lastReadMemoryRevision = undefined;
    richAnswerAttemptCount = 0;
    searchedCourseItemIDs.clear();

    let purpose = "unavailable";
    let revision = "unavailable";
    let explicitRichAnswerRequested = false;
    try {
      const snapshot = await readCurrentSnapshot();
      purpose = snapshot.purpose;
      revision = snapshot.contextRevision;
      explicitRichAnswerRequested =
        snapshot.workflow !== "noteMaking" &&
        /(?:富回答|可调|交互|互动|图示|函数图|关系图|时间线|图像叠层|叠层|模拟|实验|rich answer|interactive|adjustable|diagram|function graph|relationship graph|timeline|image overlay|simulation|experiment)/iu.test(
          snapshot.question,
        );
      requiredContextRevision = revision;
    } catch {
      requiredContextRevision = undefined;
    }

    const turnContract = [
      "<weibei_turn>",
      `purpose: ${JSON.stringify(purpose)}`,
      `contextRevision: ${JSON.stringify(revision)}`,
      "本轮第一次工具调用必须是 weibei_context。调用成功前不得回答事实问题，也不得提出富回答或笔记建议。",
      "当前材料、笔记和选区是本轮直接证据；课程关联需要读课程地图或搜索；学习历史需要读学习记忆。",
      "学习记忆只能说明用户的学习状态，不能作为课程事实证据。",
      "富回答必须提交 schemaVersion 2，并为每个 scene 选择 T1 深组件 program 或 T2 通用原语 ui；它作为 Agent 回答流中的生成式视觉体验块，可以组合多个视觉、控件、读数和实验步骤，但不是第二篇回答或完整网页。模型负责组合组件或原语、数据、状态和动作，魏碑宿主用本地渲染内核呈现。",
      `提交富回答前必须调用 ${RICH_ANSWER_CATALOG_TOOL}，按本轮知识形状取得相关组件子集；不要让完整目录或旧回合组件记忆代替本轮选择。`,
      RICH_ANSWER_FAMILY_CONTRACT,
      explicitRichAnswerRequested
        ? "本轮用户明确指定富回答或互动形态。当前证据足够时必须调用 weibei_rich_answer；不能满足时必须在正文明确说明限制，不得静默退成纯文本。"
        : "本轮没有检测到用户指定富回答形态；由你按学习收益判断是否调用 weibei_rich_answer。",
      "</weibei_turn>",
    ].join("\n");

    return { systemPrompt: `${event.systemPrompt}\n\n${turnContract}` };
  });

  pi.on("tool_call", (event) => {
    if (!ALLOWED_TOOLS.has(event.toolName)) {
      return {
        block: true,
        reason: `魏碑 Agent 只允许调用受控的上下文、课程、记忆、富回答与笔记建议工具`,
      };
    }

    if (
      event.toolName !== CONTEXT_TOOL &&
      (!requiredContextRevision ||
        !lastReadContextRevision ||
        lastReadContextRevision !== requiredContextRevision)
    ) {
      return {
        block: true,
        reason: `必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`,
      };
    }

    if (event.toolName === LEARNING_UPDATE_TOOL && lastReadMemoryRevision === undefined) {
      return {
        block: true,
        reason: `提出学习状态更新前必须调用 ${LEARNING_MEMORY_TOOL}`,
      };
    }
  });

  pi.on("context", async (event) => {
    let currentRevision: string | undefined;
    try {
      currentRevision = (await readCurrentSnapshot()).contextRevision;
    } catch {
      currentRevision = undefined;
    }

    const staleToolCallIDs = new Set<string>();
    for (const message of event.messages) {
      if (
        message.role === "toolResult" &&
        ALLOWED_TOOLS.has(message.toolName) &&
        !message.isError &&
        (currentRevision === undefined ||
          contextRevisionFromDetails(message.details) !== currentRevision)
      ) {
        staleToolCallIDs.add(message.toolCallId);
      }
    }

    if (staleToolCallIDs.size === 0) return;

    const messages: typeof event.messages = [];
    for (const message of event.messages) {
      if (message.role === "toolResult" && staleToolCallIDs.has(message.toolCallId)) {
        continue;
      }

      if (message.role === "assistant") {
        const content = message.content.filter(
          (item) => item.type !== "toolCall" || !staleToolCallIDs.has(item.id),
        );
        if (content.length === 0) continue;
        if (content.length !== message.content.length) {
          messages.push({ ...message, content });
          continue;
        }
      }

      messages.push(message);
    }

    return { messages };
  });
}
