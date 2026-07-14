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
const ALLOWED_TOOLS = new Set([
  CONTEXT_TOOL,
  COURSE_MAP_TOOL,
  COURSE_SEARCH_TOOL,
  LEARNING_MEMORY_TOOL,
  LEARNING_UPDATE_TOOL,
  NOTE_PROPOSAL_TOOL,
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
  interactions: 12,
  interactionDetail: 1_200,
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

interface InteractionSnapshot {
  blockID: string;
  kind: string;
  action: string;
  detail: string;
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
  interactions: InteractionSnapshot[];
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

function readInteractions(value: unknown): InteractionSnapshot[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) {
    throw new Error("魏碑上下文字段 interactions 必须是数组");
  }

  return value.slice(-LIMITS.interactions).map((entry, index) => {
    const interaction = requireRecord(entry, `interactions[${index}]`);
    return {
      blockID: requireIdentifier(interaction.blockID, `interactions[${index}].blockID`),
      kind: requireIdentifier(interaction.kind, `interactions[${index}].kind`),
      action: requireIdentifier(interaction.action, `interactions[${index}].action`),
      detail: truncate(
        requireString(interaction.detail, `interactions[${index}].detail`),
        LIMITS.interactionDetail,
      ),
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
    interactions: readInteractions(envelope.interactions),
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
  const terms = lower.match(/[\p{L}\p{N}_-]{2,}/gu) ?? [];
  const chineseRuns = lower.match(/[\u4e00-\u9fff]{2,}/g) ?? [];
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

export default function weibeiExtension(pi: ExtensionAPI) {
  let requiredContextRevision: string | undefined;
  let lastReadContextRevision: string | undefined;
  let lastReadMemoryRevision: number | undefined;
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
                interactions: snapshot.interactions,
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
    searchedCourseItemIDs.clear();

    let purpose = "unavailable";
    let revision = "unavailable";
    try {
      const snapshot = await readCurrentSnapshot();
      purpose = snapshot.purpose;
      revision = snapshot.contextRevision;
      requiredContextRevision = revision;
    } catch {
      requiredContextRevision = undefined;
    }

    const turnContract = [
      "<weibei_turn>",
      `purpose: ${JSON.stringify(purpose)}`,
      `contextRevision: ${JSON.stringify(revision)}`,
      "本轮第一次工具调用必须是 weibei_context。调用成功前不得回答事实问题，也不得提出笔记建议。",
      "当前材料、笔记和选区是本轮直接证据；课程关联需要读课程地图或搜索；学习历史需要读学习记忆。",
      "学习记忆只能说明用户的学习状态，不能作为课程事实证据。",
      "</weibei_turn>",
    ].join("\n");

    return { systemPrompt: `${event.systemPrompt}\n\n${turnContract}` };
  });

  pi.on("tool_call", (event) => {
    if (!ALLOWED_TOOLS.has(event.toolName)) {
      return {
        block: true,
        reason: `魏碑 Agent 只允许调用受控的上下文、课程、记忆与笔记建议工具`,
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
