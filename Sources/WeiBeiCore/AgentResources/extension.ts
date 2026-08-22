import { createHash } from "node:crypto";
import { constants, realpathSync } from "node:fs";
import { lstat, open, readFile, realpath, unlink } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { fileURLToPath } from "node:url";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@earendil-works/pi-ai";

import { generateSessionTitle } from "./session-title.ts";

const CONTEXT_FILE_ENV = "WEIBEI_AGENT_CONTEXT_FILE";
const TOOL_RESPONSE_DIR_ENV = "WEIBEI_AGENT_TOOL_RESPONSE_DIR";
const COURSE_MAP_TOOL = "weibei_course_map";
const COURSE_SEARCH_TOOL = "weibei_course_search";
const COURSE_READ_TOOL = "weibei_course_read";
const WEB_OPEN_TOOL = "weibei_web_open";
const VISUAL_ASSET_TOOL = "weibei_visual_asset";
const LEARNING_MEMORY_TOOL = "weibei_learning_memory";
const LEARNING_UPDATE_TOOL = "weibei_learning_update";
const COURSE_PROFILE_UPDATE_TOOL = "weibei_course_profile_update";
const NOTE_PROPOSAL_TOOL = "weibei_note_proposal";
const RELATION_PROPOSAL_TOOL = "weibei_relation_proposal";
const VISUALIZE_TOOL = "weibei_visualize";
const READ_TOOL = "read";
const ALLOWED_TOOLS = new Set([
  COURSE_MAP_TOOL,
  COURSE_SEARCH_TOOL,
  COURSE_READ_TOOL,
  WEB_OPEN_TOOL,
  VISUAL_ASSET_TOOL,
  LEARNING_MEMORY_TOOL,
  LEARNING_UPDATE_TOOL,
  COURSE_PROFILE_UPDATE_TOOL,
  NOTE_PROPOSAL_TOOL,
  RELATION_PROPOSAL_TOOL,
  VISUALIZE_TOOL,
  READ_TOOL,
]);

const SKILLS = {
  visualize: {
    name: "Visualize",
    version: "1.0.19",
    description: "在文字、Mermaid 与受控动态体验之间选择真正有助于理解的表达。",
    trigger: "视觉表达可能明显改善理解、比较或探索时加载。",
    relativePath: "skills/visualize/SKILL.md",
  },
} as const;

type SkillID = keyof typeof SKILLS;

interface SkillReadDetails {
  kind: "weibei_skill_read";
  contextRevision: string;
  loaded: {
    id: SkillID;
    name: string;
    version: string;
    sha256: string;
    byteCount: number;
    relativePath: string;
    loadedAtContextRevision: string;
  };
}

const SKILL_BY_PATH = new Map(
  Object.entries(SKILLS).map(([id, skill]) => [
    realpathSync(resolve(fileURLToPath(new URL(`./${skill.relativePath}`, import.meta.url)))),
    { id: id as SkillID, ...skill },
  ]),
);

function skillPath(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  if (value.startsWith("skill://")) {
    const id = value.slice("skill://".length) as SkillID;
    const skill = SKILLS[id];
    return skill
      ? realpathSync(resolve(fileURLToPath(new URL(`./${skill.relativePath}`, import.meta.url))))
      : undefined;
  }
  return canonicalReadPath(value);
}

function canonicalReadPath(value: unknown): string | undefined {
  if (typeof value !== "string" || !value.trim()) return undefined;
  try {
    return realpathSync(resolve(value));
  } catch {
    return undefined;
  }
}

const LIMITS = {
  contextFileBytes: 4 * 1024 * 1024,
  identifier: 256,
  title: 300,
  question: 4_000,
  materialText: 18_000,
  noteText: 6_000,
  selectionText: 2_000,
  courseCatalogItems: 500,
  courseItems: 80,
  courseRelations: 500,
  courseMapPageItems: 40,
  courseSearchText: 2_400,
  courseHeadings: 12,
  courseTags: 16,
  courseLinkedItems: 24,
  projectItems: 500,
  projectPath: 4_096,
  projectSearchItems: 8,
  projectSearchBytes: 256_000,
  projectReadBytes: 256_000,
  webText: 20_000,
  learningMemories: 48,
  learningText: 500,
  learningEvidence: 400,
  sessionSummary: 2_000,
  proposalMarkdown: 24_000,
  proposalEvidenceItems: 16,
  proposalEvidenceText: 500,
  visualAssetBytes: 6_000_000,
  visualAssets: 4,
  visualizationSpec: 1_000_000,
} as const;

interface SourceSnapshot {
  title: string;
  text: string;
  isTruncated: boolean;
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
  relativePath?: string;
  courseIDs?: string[];
  courseTitles?: string[];
  sourceRevision?: string;
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

interface FileIdentitySnapshot {
  volumeID: string;
  fileID: string;
  birthTimeSeconds: string;
  birthTimeNanoseconds: string;
}

interface ProjectItemSnapshot {
  itemID: string;
  title: string;
  kind: string;
  role: "material" | "note";
  relativePath: string;
  resolvedPath: string;
  entryIdentity?: FileIdentitySnapshot;
  targetIdentity?: FileIdentitySnapshot;
  isShared: boolean;
  courseIDs: string[];
  courseTitles: string[];
  sourceRevision?: string;
}

interface ProjectSnapshot {
  kind: "course" | "global";
  chatID: string;
  courseID?: string;
  courseTitle?: string;
  rootPath?: string;
  rootIdentity?: FileIdentitySnapshot;
  items: ProjectItemSnapshot[];
  isTruncated: boolean;
}

interface FocusSnapshot {
  chatID: string;
  courseID?: string;
  materialItemID?: string;
  materialTitle?: string;
  pageIndex?: number;
  sectionTitle?: string;
  sectionLocationID?: string;
  sectionOrdinal?: number;
  selectionText?: string;
  actionSource: string;
}

type LearningMemoryKind =
  | "goal"
  | "progress"
  | "understood"
  | "confusion"
  | "nextStep"
  | "summary"
  | "preference";
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

type CourseProfileEntryKind = "overview" | "section" | "concept" | "relation";

interface CourseProfileSourceSnapshot {
  itemID: string;
  role: "material" | "note";
  location?: string;
  sourceRevision: string;
}

interface CourseProfileEntrySnapshot {
  id: string;
  kind: CourseProfileEntryKind;
  text: string;
  sources: CourseProfileSourceSnapshot[];
}

interface CourseProfileSnapshot {
  revision: number;
  overview: string;
  entries: CourseProfileEntrySnapshot[];
}

interface ContextSnapshotV2 {
  schemaVersion: 2;
  requestID: string;
  contextRevision: string;
  purpose: string;
  language: string;
  question: string;
  material?: SourceSnapshot;
  note: SourceSnapshot;
  selection?: SourceSnapshot;
  course: CourseSnapshot;
  project: ProjectSnapshot;
  focus?: FocusSnapshot;
  learning: LearningSnapshot;
  courseProfile: CourseProfileSnapshot;
  interactiveVisualizationsEnabled: boolean;
}

interface VisualAssetFileSnapshot {
  id: string;
  filePath: string;
  mediaType: "image/jpeg" | "image/png" | "image/webp";
}

interface VisualAssetToolDetails {
  kind: "visual_asset_read";
  contextRevision: string;
  assetID: string;
  mediaType: VisualAssetFileSnapshot["mediaType"];
  sha256: string;
  byteCount: number;
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
  profile: CourseProfileSnapshot;
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

interface CourseReadToolDetails {
  kind: "course_read";
  contextRevision: string;
  itemID: string;
  query: string;
  results: CourseItemSnapshot[];
  evidenceLabels: string[];
  jumpReferences: string[];
  jumpEvidence: Record<string, string>;
  nextCursor?: string;
  sourceRevision?: string;
}

type WebOpenPage = { url: string; title: string; text: string; isTruncated: boolean };
type CourseIndexResponse = { items: CourseItemSnapshot[]; total?: number; nextCursor?: string; sourceRevision?: string };

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
    memoryID?: string;
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

interface CourseProfileUpdateDetails {
  kind: "course_profile_update";
  contextRevision: string;
  profileRevision: number;
  checkpoint: string;
  entries: Array<{
    entryID?: string;
    kind: CourseProfileEntryKind;
    text: string;
    sources: CourseProfileSourceSnapshot[];
  }>;
  removedEntryIDs: string[];
}

interface NoteProposalDetails {
  kind: "note_proposal";
  markdown: string;
  evidence: string[];
  contextRevision: string;
}

interface RelationProposalDetails {
  kind: "relation_proposal";
  noteItemID: string;
  sourceItemID: string;
  contextRevision: string;
}

interface VisualizationDetails {
  kind: "weibei_visualization";
  id: string;
  spec: Record<string, unknown>;
}


function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function openAINativeSearchModel(modelID: string): boolean {
  return /^gpt-5(?:[.-]|$)/.test(modelID) ||
    ["gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano", "o3", "o3-pro", "o4-mini"].includes(modelID);
}

function nativeWebSearchSupported(model: unknown): boolean {
  if (!isRecord(model)) return false;
  const provider = model.provider;
  const api = model.api;
  const modelID = model.id;
  if (typeof provider !== "string" || typeof api !== "string" || typeof modelID !== "string") return false;
  if (provider === "openai-codex" && api === "openai-codex-responses" && /^gpt-5(?:[.-]|$)/.test(modelID)) {
    return true;
  }
  return provider === "openai" &&
    api === "openai-responses" &&
    openAINativeSearchModel(modelID);
}

function withNativeWebSearch(payload: unknown, model: unknown): unknown {
  if (!isRecord(payload) || !nativeWebSearchSupported(model)) return payload;
  if (!Array.isArray(payload.tools) || payload.include !== undefined && !Array.isArray(payload.include)) return payload;
  const tools = payload.tools as unknown[];
  if (!tools.some((candidate) => isRecord(candidate) &&
    candidate.type === "function" && candidate.name === COURSE_MAP_TOOL)) {
    return payload;
  }
  const tool = { type: "web_search" };
  const alreadyPresent = tools.some((candidate) =>
    isRecord(candidate) && candidate.type === tool.type,
  );
  let nextPayload = alreadyPresent ? payload : { ...payload, tools: [...tools, tool] };
  const include = (payload.include ?? []) as unknown[];
  const sources = "web_search_call.action.sources";
  if (!include.includes(sources)) {
    nextPayload = { ...nextPayload, include: [...include, sources] };
  }
  return nextPayload;
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

function optionalString(value: unknown, field: string, limit: number): string | undefined {
  if (value === undefined || value === null) return undefined;
  return truncate(requireString(value, field), limit);
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
  const catalog = course.catalog.slice(0, LIMITS.courseCatalogItems).map((entry: any, index) => {
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
  const items = course.items.slice(0, LIMITS.courseItems).map((entry: any, index) => {
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
    .map((entry: any, index) => {
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

function readFileIdentity(value: unknown, field: string): FileIdentitySnapshot {
  const identity = requireRecord(value, field);
  const readPart = (key: keyof FileIdentitySnapshot): string => {
    const part = requireString(identity[key], `${field}.${key}`);
    if (!/^-?\d+$/u.test(part) || part.length > 32) {
      throw new Error(`${field}.${key} 不是有效的文件身份`);
    }
    return part;
  };
  return {
    volumeID: readPart("volumeID"),
    fileID: readPart("fileID"),
    birthTimeSeconds: readPart("birthTimeSeconds"),
    birthTimeNanoseconds: readPart("birthTimeNanoseconds"),
  };
}

function safeProjectRelativePath(value: string): boolean {
  if (!value || isAbsolute(value) || value.includes("\0")) return false;
  const components = value.split("/");
  return components.every(
    (component) =>
      component.length > 0 &&
      component !== "." &&
      component !== ".." &&
      !component.startsWith("."),
  );
}

function readProject(value: unknown, catalogIDs: Set<string>): ProjectSnapshot {
  const project = requireRecord(value, "project");
  const kind = requireString(project.kind, "project.kind");
  if (kind !== "course" && kind !== "global") {
    throw new Error("project.kind 必须是 course 或 global");
  }
  if (!Array.isArray(project.items)) {
    throw new Error("project.items 必须是数组");
  }
  const courseID = optionalString(project.courseID, "project.courseID", 128);
  const rootPath = optionalString(project.rootPath, "project.rootPath", LIMITS.projectPath);
  const rootIdentity =
    project.rootIdentity === undefined || project.rootIdentity === null
      ? undefined
      : readFileIdentity(project.rootIdentity, "project.rootIdentity");
  if (kind === "course" && !courseID) {
    throw new Error("课程项目缺少固定的课程 ID");
  }
  if (
    (rootPath !== undefined || rootIdentity !== undefined) &&
    (kind !== "course" || !rootPath || !isAbsolute(rootPath) || !rootIdentity)
  ) {
    throw new Error("课程项目的文件夹授权不完整");
  }
  const items = project.items.slice(0, LIMITS.projectItems).map((entry: any, index) => {
    const field = `project.items[${index}]`;
    const item = requireRecord(entry, field);
    const itemID = requireIdentifier(item.itemID, `${field}.itemID`);
    if (!catalogIDs.has(itemID)) {
      throw new Error(`${field}.itemID 不在本轮课程目录中`);
    }
    const role = requireString(item.role, `${field}.role`);
    if (role !== "material" && role !== "note") {
      throw new Error(`${field}.role 无效`);
    }
    const relativePath = truncate(
      requireString(item.relativePath, `${field}.relativePath`),
      LIMITS.projectPath,
    );
    const resolvedPath = truncate(
      requireString(item.resolvedPath, `${field}.resolvedPath`),
      LIMITS.projectPath,
    );
    const entryIdentity =
      item.entryIdentity === undefined || item.entryIdentity === null
        ? undefined
        : readFileIdentity(item.entryIdentity, `${field}.entryIdentity`);
    const targetIdentity =
      item.targetIdentity === undefined || item.targetIdentity === null
        ? undefined
        : readFileIdentity(item.targetIdentity, `${field}.targetIdentity`);
    if (
      (relativePath || resolvedPath || entryIdentity || targetIdentity) &&
      (
        kind !== "course" ||
        !safeProjectRelativePath(relativePath) ||
        !isAbsolute(resolvedPath) ||
        !entryIdentity ||
        !targetIdentity
      )
    ) {
      throw new Error(`${field} 的课程文件授权不完整`);
    }
    return {
      itemID,
      title: truncate(requireString(item.title, `${field}.title`), LIMITS.title),
      kind: requireIdentifier(item.kind, `${field}.kind`),
      role,
      relativePath,
      resolvedPath,
      entryIdentity,
      targetIdentity,
      isShared: requireBoolean(item.isShared, `${field}.isShared`),
      courseIDs: readStringArray(item.courseIDs, `${field}.courseIDs`, 32, 128),
      courseTitles: readStringArray(item.courseTitles, `${field}.courseTitles`, 32, LIMITS.title),
      sourceRevision: optionalString(item.sourceRevision, `${field}.sourceRevision`, 500),
    } satisfies ProjectItemSnapshot;
  });
  return {
    kind,
    chatID: requireIdentifier(project.chatID, "project.chatID"),
    courseID,
    courseTitle: optionalString(project.courseTitle, "project.courseTitle", LIMITS.title),
    rootPath,
    rootIdentity,
    items,
    isTruncated:
      requireBoolean(project.isTruncated, "project.isTruncated") ||
      project.items.length > items.length,
  };
}

function readFocus(
  value: unknown,
  project: ProjectSnapshot,
  catalogIDs: Set<string>,
): FocusSnapshot | undefined {
  if (value === undefined || value === null) return undefined;
  const focus = requireRecord(value, "focus");
  const optional = (raw: unknown, field: string, limit: number): string | undefined =>
    raw === undefined || raw === null
      ? undefined
      : truncate(requireString(raw, field), limit);
  const materialItemID = optional(focus.materialItemID, "focus.materialItemID", LIMITS.identifier);
  if (materialItemID !== undefined && !catalogIDs.has(materialItemID)) {
    throw new Error("focus.materialItemID 不在本轮课程目录中");
  }
  const chatID = requireIdentifier(focus.chatID, "focus.chatID");
  const courseID = optional(focus.courseID, "focus.courseID", 128);
  if (chatID !== project.chatID || courseID !== project.courseID) {
    throw new Error("当前焦点与项目作用域不一致");
  }
  const optionalInteger = (raw: unknown, field: string): number | undefined =>
    raw === undefined || raw === null
      ? undefined
      : Math.max(0, Math.trunc(requireNumber(raw, field)));
  return {
    chatID,
    courseID,
    materialItemID,
    materialTitle: optional(focus.materialTitle, "focus.materialTitle", LIMITS.title),
    pageIndex: optionalInteger(focus.pageIndex, "focus.pageIndex"),
    sectionTitle: optional(focus.sectionTitle, "focus.sectionTitle", LIMITS.title),
    sectionLocationID: optional(
      focus.sectionLocationID,
      "focus.sectionLocationID",
      LIMITS.title,
    ),
    sectionOrdinal: optionalInteger(focus.sectionOrdinal, "focus.sectionOrdinal"),
    selectionText: optional(focus.selectionText, "focus.selectionText", LIMITS.selectionText),
    actionSource: requireIdentifier(focus.actionSource, "focus.actionSource"),
  };
}

function readLearning(value: unknown): LearningSnapshot {
  const learning = requireRecord(value, "learning");
  if (!Array.isArray(learning.memories)) {
    throw new Error("魏碑学习记忆字段 memories 必须是数组");
  }
  const allowedKinds = new Set<LearningMemoryKind>([
    "goal",
    "progress",
    "understood",
    "confusion",
    "nextStep",
    "summary",
    "preference",
  ]);
  const allowedOrigins = new Set<LearningMemoryOrigin>([
    "userStatement",
    "agentInference",
    "observed",
  ]);
  const memories = learning.memories.slice(0, LIMITS.learningMemories).map((entry: any, index) => {
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

function readCourseProfile(value: unknown, catalogIDs: Set<string>): CourseProfileSnapshot {
  const profile = requireRecord(value, "courseProfile");
  if (!Array.isArray(profile.entries)) {
    throw new Error("课程知识档案字段 entries 必须是数组");
  }
  const kinds = new Set<CourseProfileEntryKind>([
    "overview",
    "section",
    "concept",
    "relation",
  ]);
  const entries = profile.entries.slice(0, 200).map((value, index) => {
    const field = `courseProfile.entries[${index}]`;
    const entry = requireRecord(value, field);
    const kind = requireString(entry.kind, `${field}.kind`) as CourseProfileEntryKind;
    if (!kinds.has(kind) || !Array.isArray(entry.sources)) {
      throw new Error(`${field} 无效`);
    }
    const sources = entry.sources.slice(0, 8).map((value, sourceIndex) => {
      const sourceField = `${field}.sources[${sourceIndex}]`;
      const source = requireRecord(value, sourceField);
      const itemID = requireIdentifier(source.itemID, `${sourceField}.itemID`);
      const role = requireString(source.role, `${sourceField}.role`);
      if (!catalogIDs.has(itemID) || (role !== "material" && role !== "note")) {
        throw new Error(`${sourceField} 不属于本轮课程`);
      }
      return {
        itemID,
        role,
        location: optionalString(source.location, `${sourceField}.location`, 500),
        sourceRevision: truncate(
          requireString(source.sourceRevision, `${sourceField}.sourceRevision`),
          500,
        ),
      } satisfies CourseProfileSourceSnapshot;
    });
    if (sources.length === 0) throw new Error(`${field} 缺少来源`);
    return {
      id: requireIdentifier(entry.id, `${field}.id`),
      kind,
      text: truncate(requireString(entry.text, `${field}.text`), 1_200),
      sources,
    } satisfies CourseProfileEntrySnapshot;
  });
  return {
    revision: Math.max(
      0,
      Math.trunc(requireNumber(profile.revision, "courseProfile.revision")),
    ),
    overview: truncate(requireString(profile.overview, "courseProfile.overview"), 2_000),
    entries,
  };
}

async function readContextEnvelope(): Promise<Record<string, unknown>> {
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

  return envelope;
}

async function readCurrentSnapshot(): Promise<ContextSnapshotV2> {
  const envelope = await readContextEnvelope();
  const course = readCourse(envelope.course);
  const catalogIDs = new Set(course.catalog.map((item: any) => item.id));
  const project = readProject(envelope.project, catalogIDs);

  return {
    schemaVersion: 2,
    requestID: requireIdentifier(envelope.requestID, "requestID"),
    contextRevision: requireIdentifier(envelope.contextRevision, "contextRevision"),
    purpose: requireIdentifier(envelope.purpose, "purpose"),
    language: requireIdentifier(envelope.language, "language"),
    question: truncate(requireString(envelope.question, "question"), LIMITS.question),
    material: readOptionalSource(envelope.material, "material", LIMITS.materialText),
    note: readSource(envelope.note, "note", LIMITS.noteText),
    selection: readOptionalSource(envelope.selection, "selection", LIMITS.selectionText),
    course,
    project,
    focus: readFocus(envelope.focus, project, catalogIDs),
    learning: readLearning(envelope.learning),
    courseProfile: readCourseProfile(envelope.courseProfile, catalogIDs),
    interactiveVisualizationsEnabled:
      typeof envelope.interactiveVisualizationsEnabled === "boolean"
        ? envelope.interactiveVisualizationsEnabled
        : true,
  };
}

async function readCurrentVisualAssets(
  snapshot: ContextSnapshotV2,
): Promise<Map<string, VisualAssetFileSnapshot>> {
  const envelope = await readContextEnvelope();
  if (requireIdentifier(envelope.contextRevision, "contextRevision") !== snapshot.contextRevision) {
    throw new Error("魏碑上下文已变化；请重新读取当前材料");
  }
  if (envelope.visualAssets === undefined || envelope.visualAssets === null) {
    return new Map();
  }
  if (!Array.isArray(envelope.visualAssets)) {
    throw new Error("魏碑视觉材料描述必须是数组");
  }
  const currentMaterialIDs = new Set(
    snapshot.course.catalog.filter((item: any) => item.isCurrentMaterial).map((item: any) => item.id),
  );
  const assets = new Map<string, VisualAssetFileSnapshot>();
  envelope.visualAssets.slice(0, LIMITS.visualAssets).forEach((entry, index) => {
    const field = `visualAssets[${index}]`;
    const raw = requireRecord(entry, field);
    const id = requireIdentifier(raw.id, `${field}.id`);
    if (!currentMaterialIDs.has(id)) {
      throw new Error(`${field}.id 不是本轮当前材料`);
    }
    const filePath = requireString(raw.filePath, `${field}.filePath`);
    if (filePath.length > 4_096 || !filePath.startsWith("/")) {
      throw new Error(`${field}.filePath 无效`);
    }
    const mediaType = requireString(raw.mediaType, `${field}.mediaType`);
    if (mediaType !== "image/jpeg" && mediaType !== "image/png" && mediaType !== "image/webp") {
      throw new Error(`${field}.mediaType 不受支持`);
    }
    let canonicalPath: string;
    try {
      canonicalPath = realpathSync(filePath);
    } catch {
      throw new Error(`${field} 指向的当前材料图像无法读取`);
    }
    assets.set(id, { id, filePath: canonicalPath, mediaType });
  });
  return assets;
}

function visualAssetMagicMatches(
  data: Buffer,
  mediaType: VisualAssetFileSnapshot["mediaType"],
): boolean {
  if (mediaType === "image/jpeg") {
    return data.length >= 3 && data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff;
  }
  if (mediaType === "image/png") {
    return data.length >= 8 && data.subarray(0, 8).equals(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    );
  }
  return data.length >= 12 &&
    data.subarray(0, 4).toString("ascii") === "RIFF" &&
    data.subarray(8, 12).toString("ascii") === "WEBP";
}

function contextRevisionFromDetails(details: unknown): string | undefined {
  if (!isRecord(details)) return undefined;
  return typeof details.contextRevision === "string" ? details.contextRevision : undefined;
}

function evidenceLabels(
  snapshot: ContextSnapshotV2,
  readableItemIDs: ReadonlySet<string>,
): string[] {
  const labels: string[] = [];
  if (snapshot.selection?.text.trim()) labels.push(`[选区：${snapshot.selection.title}]`);
  snapshot.course.catalog
    .filter((item: any) => readableItemIDs.has(item.id))
    .forEach((item) => labels.push(courseEvidenceLabel(snapshot.course, item)));
  return labels;
}

function currentFocusMessage(snapshot: ContextSnapshotV2): string {
  const focus = snapshot.focus;
  const catalog = snapshot.course.catalog.map((item: any) => ({
    id: item.id,
    title: item.title,
    role: item.role,
    isCurrentMaterial: item.isCurrentMaterial,
    isCurrentNote: item.isCurrentNote,
  }));
  return [
    "魏碑本轮现场。它只对本轮模型请求有效，不属于会话历史；材料和笔记正文需要时使用现有读取工具。",
    JSON.stringify({
      contextRevision: snapshot.contextRevision,
      purpose: snapshot.purpose,
      language: snapshot.language,
      project: {
        kind: snapshot.project.kind,
        chatID: snapshot.project.chatID,
        courseID: snapshot.project.courseID,
        courseTitle: snapshot.project.courseTitle,
      },
      course: {
        title: snapshot.course.title,
        materialCount: catalog.filter((item: any) => item.role === "material").length,
        noteCount: catalog.filter((item: any) => item.role === "note").length,
        profileRevision: snapshot.courseProfile.revision,
        understanding: truncate(snapshot.courseProfile.overview, 600),
        currentMaterial: catalog.find((item: any) => item.isCurrentMaterial),
        currentNote: catalog.find((item: any) => item.isCurrentNote),
      },
      location: focus
        ? {
            materialItemID: focus.materialItemID,
            materialTitle: focus.materialTitle,
            pageIndex: focus.pageIndex,
            sectionTitle: focus.sectionTitle,
            sectionLocationID: focus.sectionLocationID,
            sectionOrdinal: focus.sectionOrdinal,
            actionSource: focus.actionSource,
          }
        : undefined,
      selection: snapshot.selection
        ? {
            title: snapshot.selection.title,
            label: `[选区：${snapshot.selection.title}]`,
            text: snapshot.selection.text,
            isTruncated: snapshot.selection.isTruncated,
          }
        : undefined,
    }, null, 2),
  ].join("\n");
}


function currentTurnEvidenceMatches(snapshot: ContextSnapshotV2, evidence: string): boolean {
  const statement = currentTurnEvidenceStatement(evidence);
  if (!statement || statement.length < 2) return false;
  const normalize = (value: string) => value.replace(/[\p{P}\p{Z}\s]/gu, "");
  if (statement.length < 4) return normalize(statement) === normalize(snapshot.question);
  const isBoundary = (value: string) => !value || /[\p{P}\p{Z}\s]/u.test(value);
  let searchStart = 0;
  while (searchStart < snapshot.question.length) {
    const index = snapshot.question.indexOf(statement, searchStart);
    if (index < 0) return false;
    const end = index + statement.length;
    const before = index === 0 ? "" : snapshot.question[index - 1];
    const after = end >= snapshot.question.length ? "" : snapshot.question[end];
    if (isBoundary(before) && isBoundary(after)) return true;
    searchStart = end;
  }
  return false;
}

function resolutionEvidenceMatches(snapshot: ContextSnapshotV2, evidence: string): boolean {
  return currentTurnEvidenceMatches(snapshot, evidence);
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

function readHostCourseItem(
  value: unknown,
  field: string,
  snapshot: ContextSnapshotV2,
  maximumSearchText = LIMITS.courseSearchText * 2,
): CourseItemSnapshot {
  const wrapper = requireRecord(value, field);
  const item = requireRecord(wrapper.item, `${field}.item`);
  const role = requireString(item.role, `${field}.item.role`);
  if (role !== "material" && role !== "note") {
    throw new Error(`${field}.item.role 无效`);
  }
  const courseIDs = readStringArray(
    wrapper.courseIDs,
    `${field}.courseIDs`,
    32,
    128,
  );
  if (
    snapshot.project.kind === "course" &&
    snapshot.project.courseID &&
    !courseIDs.includes(snapshot.project.courseID)
  ) {
    throw new Error(`${field} 不属于当前课程`);
  }
  const relativePath =
    wrapper.relativePath === undefined || wrapper.relativePath === null
      ? undefined
      : truncate(
          requireString(wrapper.relativePath, `${field}.relativePath`),
          LIMITS.projectPath,
        );
  if (relativePath !== undefined && !safeProjectRelativePath(relativePath)) {
    throw new Error(`${field}.relativePath 越出课程项目`);
  }
  const sourceRevision = wrapper.sourceRevision === undefined || wrapper.sourceRevision === null
    ? undefined
    : truncate(
        requireString(wrapper.sourceRevision, `${field}.sourceRevision`),
        500,
      );
  return {
    id: requireIdentifier(item.id, `${field}.item.id`),
    title: truncate(requireString(item.title, `${field}.item.title`), LIMITS.title),
    subtitle: truncate(requireString(item.subtitle, `${field}.item.subtitle`), LIMITS.title),
    kind: requireIdentifier(item.kind, `${field}.item.kind`),
    role,
    isCurrentMaterial: requireBoolean(
      item.isCurrentMaterial,
      `${field}.item.isCurrentMaterial`,
    ),
    isCurrentNote: requireBoolean(item.isCurrentNote, `${field}.item.isCurrentNote`),
    linkedItemIDs: readStringArray(
      item.linkedItemIDs,
      `${field}.item.linkedItemIDs`,
      LIMITS.courseLinkedItems,
      LIMITS.identifier,
    ),
    headings: readStringArray(
      item.headings,
      `${field}.item.headings`,
      LIMITS.courseHeadings,
      LIMITS.title,
    ),
    tags: readStringArray(
      item.tags,
      `${field}.item.tags`,
      LIMITS.courseTags,
      LIMITS.title,
    ),
    searchText: truncate(
      requireString(item.searchText, `${field}.item.searchText`),
      maximumSearchText,
    ),
    isTruncated: requireBoolean(item.isTruncated, `${field}.item.isTruncated`),
    relativePath,
    courseIDs,
    courseTitles: readStringArray(
      wrapper.courseTitles,
      `${field}.courseTitles`,
      32,
      LIMITS.title,
    ),
    sourceRevision,
  };
}

async function queryHostTool(
  snapshot: ContextSnapshotV2,
  toolCallID: string,
  toolName: string,
  signal?: AbortSignal,
): Promise<Record<string, unknown>> {
  const root = process.env[TOOL_RESPONSE_DIR_ENV]?.trim();
  if (!root || !isAbsolute(root)) {
    throw new Error(`缺少环境变量 ${TOOL_RESPONSE_DIR_ENV}`);
  }
  const canonicalRoot = await realpath(root);
  if (canonicalRoot !== resolve(root)) {
    throw new Error("宿主工具响应根目录发生了变化");
  }
  const digest = createHash("sha256").update(toolCallID, "utf8").digest("hex");
  const requestDirectory = resolve(canonicalRoot, snapshot.requestID);
  const canonicalRequestDirectory = await realpath(requestDirectory);
  if (
    canonicalRequestDirectory !== requestDirectory ||
    !canonicalRequestDirectory.startsWith(`${canonicalRoot}/`)
  ) {
    throw new Error("宿主工具本轮响应目录发生了变化");
  }
  const responsePath = resolve(requestDirectory, `${digest}.json`);
  if (
    requestDirectory !== `${canonicalRoot}/${snapshot.requestID}` ||
    responsePath !== `${requestDirectory}/${digest}.json`
  ) {
    throw new Error("宿主工具响应路径无效");
  }

  const startedAt = Date.now();
  let data: Buffer | undefined;
  while (Date.now() - startedAt < 12_000) {
    if (signal?.aborted) throw new Error("宿主工具查询已取消");
    try {
      data = await readFile(responsePath);
      break;
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      await delay(40, undefined, signal ? { signal } : undefined);
    }
  }
  if (!data) throw new Error("宿主工具查询超时");
  void unlink(responsePath).catch(() => {});
  if (data.byteLength > LIMITS.projectSearchBytes) {
    throw new Error("宿主工具返回内容超过上限");
  }
  const envelope = requireRecord(
    JSON.parse(data.toString("utf8")) as unknown,
    "hostToolResponse",
  );
  if (
    envelope.schemaVersion !== 1 ||
    requireIdentifier(envelope.requestID, "hostToolResponse.requestID") !== snapshot.requestID ||
    requireIdentifier(
      envelope.contextRevision,
      "hostToolResponse.contextRevision",
    ) !== snapshot.contextRevision ||
    requireString(envelope.toolCallID, "hostToolResponse.toolCallID") !== toolCallID ||
    requireIdentifier(envelope.toolName, "hostToolResponse.toolName") !== toolName
  ) {
    throw new Error("宿主工具响应不属于本轮调用");
  }
  if (!requireBoolean(envelope.success, "hostToolResponse.success")) {
    throw new Error(
      truncate(
        requireString(envelope.error, "hostToolResponse.error"),
        1_000,
      ),
    );
  }
  return requireRecord(envelope.payload, "hostToolResponse.payload");
}

async function queryCourseIndex(
  snapshot: ContextSnapshotV2, toolCallID: string, toolName: string, signal?: AbortSignal,
): Promise<CourseIndexResponse> {
  const payload = await queryHostTool(snapshot, toolCallID, toolName, signal);
  if (!Array.isArray(payload.items)) {
    throw new Error("课程工具响应 items 必须是数组");
  }
  const nextCursor = payload.nextCursor === undefined || payload.nextCursor === null
    ? undefined
    : truncate(
        requireString(payload.nextCursor, "hostToolResponse.payload.nextCursor"),
        1_024,
      );
  const sourceRevision = payload.sourceRevision === undefined || payload.sourceRevision === null
    ? undefined
    : truncate(
        requireString(payload.sourceRevision, "hostToolResponse.payload.sourceRevision"),
        LIMITS.identifier,
      );
  const total = payload.total === undefined || payload.total === null
    ? undefined
    : (() => {
        if (typeof payload.total !== "number" || !Number.isInteger(payload.total) || payload.total < 0) {
          throw new Error("hostToolResponse.payload.total 无效");
        }
        return payload.total;
      })();
  const maximumItems = toolName === COURSE_MAP_TOOL
    ? LIMITS.courseMapPageItems
    : LIMITS.projectSearchItems;
  return {
    items: payload.items
    .slice(0, maximumItems)
    .map((item, index) =>
      readHostCourseItem(
        item,
        `hostToolResponse.payload.items[${index}]`,
        snapshot,
        toolName === COURSE_READ_TOOL ? 12_000 : LIMITS.courseSearchText * 2,
      )
    ),
    total,
    nextCursor,
    sourceRevision,
  };
}

async function openWebPage(
  snapshot: ContextSnapshotV2, toolCallID: string, signal?: AbortSignal,
): Promise<WebOpenPage> {
  const payload = await queryHostTool(snapshot, toolCallID, WEB_OPEN_TOOL, signal);
  if (!Array.isArray(payload.webPages) || payload.webPages.length !== 1) {
    throw new Error("网页工具没有返回唯一页面");
  }
  const raw = requireRecord(payload.webPages[0], "hostToolResponse.payload.webPages[0]");
  const page: WebOpenPage = {
    url: truncate(requireString(raw.url, "webPages[0].url"), 2_048),
    title: truncate(requireString(raw.title, "webPages[0].title"), LIMITS.title),
    text: truncate(requireString(raw.text, "webPages[0].text"), LIMITS.webText),
    isTruncated: requireBoolean(raw.isTruncated, "webPages[0].isTruncated"),
  };
  let parsed: URL;
  try { parsed = new URL(page.url); } catch { throw new Error("网页工具返回地址无效"); }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password) {
    throw new Error("网页工具返回地址越出安全范围");
  }
  return page;
}

function rememberHostCourseItems(
  knownItemIDs: Set<string>,
  results: CourseItemSnapshot[],
): void {
  results.forEach((item) => {
    knownItemIDs.add(item.id);
    item.linkedItemIDs.forEach((linkedID) => knownItemIDs.add(linkedID));
  });
}

function identityFromStats(stats: Record<string, unknown>): FileIdentitySnapshot | undefined {
  const dev = stats.dev;
  const ino = stats.ino;
  const birthtimeNs = stats.birthtimeNs;
  if (
    typeof dev !== "bigint" ||
    typeof ino !== "bigint" ||
    typeof birthtimeNs !== "bigint"
  ) {
    return undefined;
  }
  const billion = 1_000_000_000n;
  return {
    volumeID: dev.toString(),
    fileID: ino.toString(),
    birthTimeSeconds: (birthtimeNs / billion).toString(),
    birthTimeNanoseconds: (birthtimeNs % billion).toString(),
  };
}

function sameIdentity(
  stats: Record<string, unknown>,
  expected: FileIdentitySnapshot | undefined,
): boolean {
  const actual = identityFromStats(stats);
  return expected !== undefined &&
    actual !== undefined &&
    actual.volumeID === expected.volumeID &&
    actual.fileID === expected.fileID &&
    actual.birthTimeSeconds === expected.birthTimeSeconds &&
    actual.birthTimeNanoseconds === expected.birthTimeNanoseconds;
}

function stableFileStats(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): boolean {
  return before.dev === after.dev &&
    before.ino === after.ino &&
    before.birthtimeNs === after.birthtimeNs &&
    before.size === after.size &&
    before.mtimeNs === after.mtimeNs;
}

export async function readApprovedProjectFile(
  snapshot: ContextSnapshotV2,
  item: ProjectItemSnapshot,
  afterOpen?: () => void | Promise<void>,
): Promise<{ data: Buffer; truncated: boolean }> {
  if (
    snapshot.project.kind !== "course" ||
    !snapshot.project.rootPath ||
    !snapshot.project.rootIdentity ||
    !item.relativePath ||
    !item.resolvedPath ||
    !item.entryIdentity ||
    !item.targetIdentity
  ) {
    throw new Error("这个资料没有本轮课程文件读取授权");
  }
  const rootPath = snapshot.project.rootPath;
  const canonicalRoot = await realpath(rootPath);
  if (canonicalRoot !== rootPath) {
    throw new Error("课程根目录在本轮发生了变化");
  }
  const rootStats = await lstat(rootPath, { bigint: true });
  if (!sameIdentity(rootStats as unknown as Record<string, unknown>, snapshot.project.rootIdentity)) {
    throw new Error("课程根目录身份与本轮授权不一致");
  }
  const entryPath = resolve(rootPath, item.relativePath);
  if (
    entryPath === rootPath ||
    !entryPath.startsWith(`${rootPath}/`) ||
    !safeProjectRelativePath(item.relativePath)
  ) {
    throw new Error("课程文件路径越出了本轮课程根目录");
  }
  const entryStats = await lstat(entryPath, { bigint: true });
  if (
    !sameIdentity(entryStats as unknown as Record<string, unknown>, item.entryIdentity) ||
    (item.isShared ? !entryStats.isSymbolicLink() : entryStats.isSymbolicLink())
  ) {
    throw new Error("课程文件入口身份与本轮授权不一致");
  }
  if (item.isShared) {
    const linkedTarget = await realpath(entryPath);
    const approvedTarget = await realpath(item.resolvedPath);
    if (linkedTarget !== approvedTarget) {
      throw new Error("共享文稿链接已发生变化");
    }
  } else if (await realpath(entryPath) !== item.resolvedPath) {
    throw new Error("课程文件真实路径已发生变化");
  }

  const targetPath = item.isShared ? item.resolvedPath : entryPath;
  const file = await open(
    targetPath,
    constants.O_RDONLY | constants.O_NOFOLLOW,
  );
  try {
    const before = await file.stat({ bigint: true });
    if (
      !before.isFile() ||
      !sameIdentity(before as unknown as Record<string, unknown>, item.targetIdentity)
    ) {
      throw new Error("课程文件身份与本轮授权不一致");
    }
    await afterOpen?.();
    const byteCount = Number(
      before.size > BigInt(LIMITS.projectReadBytes)
        ? BigInt(LIMITS.projectReadBytes)
        : before.size,
    );
    const data = Buffer.alloc(byteCount);
    const readResult = await file.read(data, 0, byteCount, 0);
    const after = await file.stat({ bigint: true });
    if (
      readResult.bytesRead !== byteCount ||
      !stableFileStats(
        before as unknown as Record<string, unknown>,
        after as unknown as Record<string, unknown>,
      )
    ) {
      throw new Error("课程文件在读取期间发生变化");
    }
    const result = data.subarray(0, readResult.bytesRead);
    if (result.includes(0)) {
      throw new Error("这个课程文件不是可直接读取的文本；请改用课程读取工具");
    }
    return {
      data: result,
      truncated: before.size > BigInt(LIMITS.projectReadBytes),
    };
  } finally {
    await file.close();
  }
}

export function projectItemForPath(
  snapshot: ContextSnapshotV2,
  requestedPath: string,
): ProjectItemSnapshot | undefined {
  if (!safeProjectRelativePath(requestedPath)) return undefined;
  return snapshot.project.items.find(
    (item) => item.relativePath === requestedPath,
  );
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

function presentCourseResults(
  snapshot: ContextSnapshotV2,
  results: CourseItemSnapshot[],
): {
  presentedResults: Array<CourseItemSnapshot & {
    evidenceLabel?: string;
    jumpReference?: string;
    sectionJumpReferences: string[];
    pageJumpReferences: string[];
  }>;
  evidenceLabels: string[];
  jumpReferences: string[];
  jumpEvidence: Record<string, string>;
} {
  const presentedResults = results.map((item: any) => {
    const hasEvidence = item.searchText.trim().length > 0;
    const sectionJumpReferences =
      hasEvidence && item.kind === "html"
        ? item.headings
            .slice(0, 5)
            .map((heading: any) => courseJumpReference(snapshot.course, item, heading))
        : [];
    const pageJumpReferences =
      hasEvidence && item.kind === "pdf"
        ? item.headings
            .filter((heading: any) => coursePage(heading) !== undefined)
            .slice(0, 5)
            .map((heading: any) => courseJumpReference(snapshot.course, item, heading))
        : [];
    return {
      ...item,
      headings: item.headings.map((heading: any) => courseHeading(heading).title),
      evidenceLabel: hasEvidence ? courseEvidenceLabel(snapshot.course, item) : undefined,
      jumpReference: hasEvidence ? courseJumpReference(snapshot.course, item) : undefined,
      sectionJumpReferences,
      pageJumpReferences,
    };
  });
  const evidenceLabels = presentedResults.flatMap((item: any) =>
    item.evidenceLabel ? [item.evidenceLabel] : [],
  );
  const jumpEvidence = Object.fromEntries(
    presentedResults.flatMap((item: any) => {
      if (!item.evidenceLabel || !item.jumpReference) return [];
      return [item.jumpReference, ...item.sectionJumpReferences, ...item.pageJumpReferences]
        .map((jumpReference) => [jumpReference, item.evidenceLabel] as const);
    }),
  );
  return {
    presentedResults,
    evidenceLabels,
    jumpReferences: Object.keys(jumpEvidence),
    jumpEvidence,
  };
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
  let lastReadMemoryRevision: number | undefined;
  let courseProfileUpdated = false;
  let interactiveVisualizationsEnabled = true;
  let courseMemoryAvailable = false;
  let currentQuestion = "";
  const searchedCourseItemIDs = new Set<string>();
  const hostCourseItemIDs = new Set<string>();
  const readCourseSourceRevisions = new Map<string, string>();

  pi.registerTool({
    name: READ_TOOL,
    label: "读取魏碑 Skill",
    description:
      "视觉表达可能明显改善理解、比较或探索时，读取魏碑随 App 打包的 visualize Skill。课程资料请用课程地图、搜索或渐进读取工具。",
    promptSnippet: "按需读取魏碑唯一的生成式界面 Skill",
    parameters: Type.Object(
      {
        path: Type.String({ minLength: 1, maxLength: 4_096 }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallID: any, params: any) {
      const normalizedSkillPath = skillPath(params.path);
      const skill = normalizedSkillPath
        ? SKILL_BY_PATH.get(normalizedSkillPath)
        : undefined;
      if (skill && normalizedSkillPath) {
        const content = await readFile(normalizedSkillPath, "utf8");
        return {
          content: [{ type: "text", text: content }],
          details: { kind: "skill_read_pending" },
        };
      }
      throw new Error("read 只接受魏碑已登记的 skill:// 路径");
    },
  });

  pi.registerTool({
    name: VISUALIZE_TOOL,
    label: "显示互动界面",
    description:
      "把一个聚焦且充分利用正文空间的 Visualize 互动片段立即穿插显示在当前回答中。一次调用提交一个可直接使用的界面；重复 id 会原地更新已有界面。",
    promptSnippet: "提交一个聚焦但不局促的 Visualize 片段；主视觉充分展开，必要控制和读数就近排布",
    parameters: Type.Object(
      {
        id: Type.String({
          minLength: 1,
          maxLength: 128,
          pattern: "^[a-z0-9]+(?:-[a-z0-9]+)*$",
          description: "稳定的短标识；更新已有界面时复用原 id",
        }),
        spec: Type.Object({
          title: Type.Optional(Type.String({ maxLength: 240 })),
          gap: Type.Optional(Type.Number({ minimum: 0, maximum: 64 })),
          items: Type.Array(Type.Any(), { minItems: 1, maxItems: 200 }),
        }, {
          additionalProperties: false,
          description: "Visualize 白名单组件树；根节点必须包含 items",
        }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallID: any, params: any) {
      const id = params.id.trim();
      const spec = params.spec as Record<string, unknown>;
      const specJSON = JSON.stringify(spec);
      if (
        !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id)
        || !Array.isArray(spec.items)
        || spec.items.length === 0
        || Buffer.byteLength(specJSON, "utf8") > LIMITS.visualizationSpec
      ) {
        throw new Error("Visualize 界面必须包含稳定 id 和完整组件树");
      }
      const details: VisualizationDetails = {
        kind: "weibei_visualization",
        id,
        spec,
      };
      return {
        content: [{ type: "text", text: `互动界面 ${id} 已显示。` }],
        details,
      };
    },
  });

  pi.registerTool({
    name: VISUAL_ASSET_TOOL,
    label: "观察当前材料图像",
    description:
      "按当前材料 assetID 读取本轮受控图像像素。只有路线、区域、构图、比例、图中对象或空间位置确实依赖原图时调用；返回给模型的是当前材料图片，不暴露文件路径。",
    promptSnippet: "观察当前材料的真实图像像素，并记录哈希与大小",
    parameters: Type.Object(
      {
        assetID: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallID: any, params: any) {
      const current = await readCurrentSnapshot();
      const visualAssets = await readCurrentVisualAssets(current);
      const asset = visualAssets.get(params.assetID);
      if (!asset) {
        throw new Error("该 assetID 不是本轮可观察的当前材料图像");
      }
      const file = await open(asset.filePath, "r");
      let data: Buffer;
      try {
        const beforeRead = await file.stat();
        if (!beforeRead.isFile() || beforeRead.size <= 0 || beforeRead.size > LIMITS.visualAssetBytes) {
          throw new Error(`当前材料图像必须是 1 到 ${LIMITS.visualAssetBytes} 字节的普通文件`);
        }
        data = await file.readFile();
        const afterRead = await file.stat();
        if (
          data.byteLength !== beforeRead.size ||
          data.byteLength > LIMITS.visualAssetBytes ||
          afterRead.size !== beforeRead.size ||
          afterRead.mtimeMs !== beforeRead.mtimeMs
        ) {
          throw new Error("当前材料图像在读取期间发生变化；请重新读取当前材料");
        }
      } finally {
        await file.close();
      }
      if (!visualAssetMagicMatches(data, asset.mediaType)) {
        throw new Error("当前材料图像的真实格式与声明不一致");
      }
      const sha256 = createHash("sha256").update(data).digest("hex");
      const details: VisualAssetToolDetails = {
        kind: "visual_asset_read",
        contextRevision: current.contextRevision,
        assetID: asset.id,
        mediaType: asset.mediaType,
        sha256,
        byteCount: data.byteLength,
      };
      return {
        content: [
          {
            type: "text",
            text: `已读取当前材料图像 ${asset.id}；请只依据可见像素和本轮来源判断，不能把近似观察说成精确测量。`,
          },
          {
            type: "image",
            mimeType: asset.mediaType,
            data: data.toString("base64"),
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
      "按需列出全部课程资料；传入资料 ID 时只返回这份资料的章节或页位置，不读取正文。",
    promptSnippet: "先看课程和资料地图，再决定搜索或读取哪一段",
    parameters: Type.Object(
      {
        itemID: Type.Optional(Type.String({ minLength: 1, maxLength: LIMITS.identifier })),
        offset: Type.Optional(Type.Integer({ minimum: 0 })),
        limit: Type.Optional(
          Type.Integer({ minimum: 1, maximum: LIMITS.courseMapPageItems }),
        ),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(toolCallID: any, params: any, signal: any) {
      const snapshot = await readCurrentSnapshot();
      const offset = params.offset ?? 0;
      const limit = params.limit ?? 40;
      const response = await queryCourseIndex(
        snapshot,
        toolCallID,
        COURSE_MAP_TOOL,
        signal,
      );
      const results = response.items;
      rememberHostCourseItems(hostCourseItemIDs, results);
      const catalog = results.map((item: any) => ({
        ...item,
        jumpReference: courseJumpReference(snapshot.course, item),
      }));
      const catalogByID = new Map(results.map((item: any) => [item.id, item] as const));
      const relations = results.flatMap((item: any) =>
        item.linkedItemIDs.flatMap((linkedID: any) => {
          const linked = catalogByID.get(linkedID);
          if (!linked || item.role === linked.role || item.id > linked.id) return [];
          const note = item.role === "note" ? item : linked;
          const source = item.role === "material" ? item : linked;
          return [{
            noteItemID: note.id,
            sourceItemID: source.id,
            noteTitle: note.title,
            sourceTitle: source.title,
          }];
        }),
      );
      const total = response.total ?? results.length;
      const page = {
        title: snapshot.course.title,
        offset,
        limit,
        total,
        hasMore: response.nextCursor !== undefined,
        catalog,
        relations,
        isTruncated: snapshot.course.isTruncated,
        profile: snapshot.courseProfile,
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
    async execute(toolCallID: any, params: any, signal: any) {
      const snapshot = await readCurrentSnapshot();
      const query = params.query.trim();
      const response = await queryCourseIndex(
        snapshot,
        toolCallID,
        COURSE_SEARCH_TOOL,
        signal,
      );
      const results = response.items;
      rememberHostCourseItems(hostCourseItemIDs, results);
      results
        .filter((item: any) => item.searchText.trim().length > 0)
        .forEach((item) => searchedCourseItemIDs.add(item.id));
      const presented = presentCourseResults(snapshot, results);
      const details: CourseSearchToolDetails = {
        kind: "course_search",
        contextRevision: snapshot.contextRevision,
        query,
        results,
        evidenceLabels: presented.evidenceLabels,
        jumpReferences: presented.jumpReferences,
        jumpEvidence: presented.jumpEvidence,
      };
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              presented.presentedResults,
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
    name: COURSE_READ_TOOL,
    label: "读取课程资料正文",
    description:
      "按临时资料 ID 渐进读取真实正文。先按当前位置、章节或搜索结果读必要片段；返回 nextCursor 时，由你判断是否继续，不要反复从开头读取。",
    promptSnippet: "按资料 ID 和页或章节继续读取真实正文",
    parameters: Type.Object(
      {
        itemID: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
        query: Type.Optional(Type.String({ maxLength: 500 })),
        location: Type.Optional(Type.String({ maxLength: LIMITS.title })),
        cursor: Type.Optional(Type.String({ minLength: 1, maxLength: 1_024 })),
        maximumCharacters: Type.Optional(
          Type.Integer({ minimum: 1_000, maximum: 12_000 }),
        ),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(toolCallID: any, params: any, signal: any) {
      const snapshot = await readCurrentSnapshot();
      if (
        !snapshot.project.items.some((item: any) => item.itemID === params.itemID) &&
        !hostCourseItemIDs.has(params.itemID)
      ) {
        throw new Error("该资料 ID 不属于本轮查询作用域");
      }
      const query = params.query?.trim() ?? "";
      const response = await queryCourseIndex(
        snapshot,
        toolCallID,
        COURSE_READ_TOOL,
        signal,
      );
      const results = response.items;
      results.forEach((item) => {
        if (item.sourceRevision) readCourseSourceRevisions.set(item.id, item.sourceRevision);
      });
      rememberHostCourseItems(hostCourseItemIDs, results);
      results.forEach((item) => searchedCourseItemIDs.add(item.id));
      const presented = presentCourseResults(snapshot, results);
      const details: CourseReadToolDetails = {
        kind: "course_read",
        contextRevision: snapshot.contextRevision,
        itemID: params.itemID,
        query,
        results,
        evidenceLabels: presented.evidenceLabels,
        jumpReferences: presented.jumpReferences,
        jumpEvidence: presented.jumpEvidence,
        nextCursor: response.nextCursor,
        sourceRevision: response.sourceRevision,
      };
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            results: presented.presentedResults,
            hasMore: response.nextCursor !== undefined,
            nextCursor: response.nextCursor,
            sourceRevision: response.sourceRevision,
          }, null, 2),
        }],
        details,
      };
    },
  });

  pi.registerTool({
    name: WEB_OPEN_TOOL,
    label: "读取用户提供的网页",
    description: "读取用户本轮明确贴出的 HTTPS 网页；不能访问未提供的地址、本机或局域网，也不执行脚本。",
    promptSnippet: "按需读取用户本轮明确提供的网页，并用返回地址标注来源",
    parameters: Type.Object({
      url: Type.String({ minLength: 1, maxLength: 2_048 }),
      maximumCharacters: Type.Optional(Type.Integer({ minimum: 1_000, maximum: LIMITS.webText })),
    }, { additionalProperties: false }),
    executionMode: "sequential",
    async execute(toolCallID: any, params: any, signal: any) {
      const snapshot = await readCurrentSnapshot();
      const page = await openWebPage(snapshot, toolCallID, signal);
      return {
        content: [{ type: "text", text: JSON.stringify(page, null, 2) }],
        details: { kind: "web_open", contextRevision: snapshot.contextRevision, page },
      };
    },
  });

  pi.registerTool({
    name: COURSE_PROFILE_UPDATE_TOOL,
    label: "整理课程知识档案",
    description:
      "把课程认识或用户自述掌握状态写入课程知识档案。用户明确要求时必须提交。自述掌握状态不要求材料来源，checkpoint 用 userRequested。材料认识仍须带来源。",
    promptSnippet: "用户明确要求时必须整理；自述掌握状态按原话记录；材料认识仍须带来源",
    parameters: Type.Object(
      {
        contextRevision: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
        profileRevision: Type.Integer({ minimum: 0 }),
        checkpoint: Type.Union([
          Type.Literal("sectionCompleted"),
          Type.Literal("topicCompleted"),
          Type.Literal("crossSourceConnection"),
          Type.Literal("beforeContextSwitch"),
          Type.Literal("userRequested"),
        ]),
        entries: Type.Optional(Type.Array(Type.Object(
          {
            entryID: Type.Optional(
              Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
            ),
            kind: Type.Union([
              Type.Literal("overview"),
              Type.Literal("section"),
              Type.Literal("concept"),
              Type.Literal("relation"),
            ]),
            text: Type.String({ minLength: 1, maxLength: 1_200 }),
            sources: Type.Array(Type.Object(
              {
                itemID: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
                role: Type.Union([Type.Literal("material"), Type.Literal("note")]),
                location: Type.Optional(Type.String({ maxLength: 500 })),
                sourceRevision: Type.String({ minLength: 1, maxLength: 500 }),
              },
              { additionalProperties: false },
            ), { minItems: 0, maxItems: 8 }),
          },
          { additionalProperties: false },
        ), { maxItems: 12 })),
        removedEntryIDs: Type.Optional(Type.Array(
          Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
          { maxItems: 12 },
        )),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallID: any, params: any) {
      const current = await readCurrentSnapshot();
      const entries = params.entries ?? [];
      const removedEntryIDs = params.removedEntryIDs ?? [];
      if (!current.project.courseID) {
        throw new Error("当前没有可归属的课程，不能更新课程知识档案");
      }
      if (courseProfileUpdated) throw new Error("本轮已经整理过课程知识档案");
      if (
        params.contextRevision !== current.contextRevision ||
        params.profileRevision !== current.courseProfile.revision
      ) {
        throw new Error("课程知识档案版本已变化，请按当前课程地图重新整理");
      }
      if (entries.length === 0 && removedEntryIDs.length === 0) {
        throw new Error("课程知识档案更新不能为空");
      }
      const catalogByID = new Map(
        current.course.catalog.map((item: any) => [item.id, item] as const),
      );
      const existingEntryIDs = new Set(current.courseProfile.entries.map((entry: any) => entry.id));
      if (
        removedEntryIDs.some((id: any) => !existingEntryIDs.has(id)) ||
        entries.some((entry: any) => entry.entryID && !existingEntryIDs.has(entry.entryID))
      ) {
        throw new Error("课程知识档案条目已变化，请重新查看课程地图");
      }
      for (const entry of entries) {
        const sources = entry.sources ?? [];
        if (sources.length === 0 && params.checkpoint !== "userRequested") {
          throw new Error("材料认识必须带来源；自述掌握状态请用 checkpoint userRequested");
        }
        for (const source of sources) {
          if (
            catalogByID.get(source.itemID)?.role !== source.role ||
            readCourseSourceRevisions.get(source.itemID) !== source.sourceRevision
          ) {
            throw new Error("课程知识档案只能引用本轮真实读到且版本一致的材料或笔记");
          }
        }
      }
      courseProfileUpdated = true;
      const details: CourseProfileUpdateDetails = {
        kind: "course_profile_update",
        contextRevision: current.contextRevision,
        profileRevision: current.courseProfile.revision,
        checkpoint: params.checkpoint,
        entries,
        removedEntryIDs,
      };
      return {
        content: [{ type: "text", text: "本轮阶段性课程认识已提交保存。" }],
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
      if (!snapshot.project.courseID) {
        throw new Error("学习记忆只在课程 Chat 中使用");
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
    label: "更新学习状态",
    description:
      "仅在课程 Chat 的学习阶段节点，根据真实阅读位置、用户自述、回忆或应用表现，智能更新本课程的目标、进度、理解、困惑、下一步或稳定偏好。用户不必明确要求保存；普通问答、模型刚讲完内容、一次普通追问都不能单独证明学习状态。它不能修改材料或笔记。",
    promptSnippet: "在课程阶段节点依据真实学习证据更新；用户无需使用固定说法，证据不足时不更新",
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
              memoryID: Type.Optional(
                Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
              ),
              kind: Type.Union(
                [
                  "goal",
                  "progress",
                  "understood",
                  "confusion",
                  "nextStep",
                  "summary",
                  "preference",
                ].map((value) => Type.Literal(value)),
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
    async execute(_toolCallId: any, params: any) {
      const current = await readCurrentSnapshot();
      if (!current.project.courseID) {
        throw new Error("学习记忆只在课程 Chat 中更新");
      }
      if (
        lastReadMemoryRevision !== current.learning.memoryRevision
      ) {
        throw new Error(
          `学习状态已变化；请重新调用 ${LEARNING_MEMORY_TOOL}`,
        );
      }
      if (
        params.contextRevision !== current.contextRevision ||
        params.memoryRevision !== current.learning.memoryRevision
      ) {
        throw new Error("学习状态建议的上下文或记忆修订号不匹配");
      }
      const entries = params.entries.map((entry: any) => ({
        memoryID: entry.memoryID?.trim().toLowerCase(),
        kind: entry.kind as LearningMemoryKind,
        text: entry.text.trim(),
        evidence: entry.evidence.trim(),
        origin: entry.origin as "userStatement" | "agentInference",
      }));
      if (entries.some((entry: any) => entry.memoryID !== undefined && !entry.memoryID)) {
        throw new Error("学习记忆 ID 不能为空");
      }
      const allowedEvidencePrefixes = [
        "[用户：本轮]",
        "[会话：当前]",
        ...(current.learning.lastLocation ? ["[学习记录：上次位置]"] : []),
        ...evidenceLabels(current, searchedCourseItemIDs),
        ...current.course.catalog
          .filter((item: any) => searchedCourseItemIDs.has(item.id))
          .map((item: any) => courseEvidenceLabel(current.course, item)),
      ];
      if (
        entries.some(
          (entry: any) =>
            !entry.text ||
            !entry.evidence ||
            !allowedEvidencePrefixes.some((prefix) => entry.evidence.startsWith(prefix)),
        )
      ) {
        throw new Error("每条学习记忆都必须携带当前用户、会话或来源依据标签");
      }
      if (
        entries.some(
          (entry: any) =>
            (entry.evidence.startsWith("[用户：本轮]") ||
              entry.evidence.startsWith("[会话：当前]")) &&
            !currentTurnEvidenceMatches(current, entry.evidence),
        )
      ) {
        throw new Error("本轮用户或会话依据必须在标签后逐字引用用户本轮真实原话");
      }
      if (
        entries.some(
          (entry: any) =>
            entry.evidence.startsWith("[学习记录：上次位置]") &&
            (entry.evidence !== "[学习记录：上次位置]" ||
              entry.origin !== "agentInference" ||
              !["progress", "nextStep"].includes(entry.kind)),
        )
      ) {
        throw new Error("阅读位置只能支持课程进度或下一步，并且必须标为模型判断");
      }
      if (
        entries.some(
          (entry: any) =>
            entry.origin === "userStatement" && !entry.evidence.startsWith("[用户：本轮]"),
        )
      ) {
        throw new Error("用户陈述型记忆必须直接依据本轮用户原话");
      }
      const suggestedNext = params.suggestedNext
        .map((item: any) => item.trim())
        .filter((item: any) => item.length > 0);
      const sessionSummary = params.sessionSummary?.trim();
      const allActiveMemoryByID = new Map(
        current.learning.memories
          .filter((memory) => memory.status === "active")
          .map((memory) => [memory.id.trim().toLowerCase(), memory] as const),
      );
      const updateTargetIDs = entries.flatMap((entry: any) =>
        entry.memoryID ? [entry.memoryID] : []
      );
      if (new Set(updateTargetIDs).size !== updateTargetIDs.length) {
        throw new Error("同一次学习状态更新不能重复修改同一条记忆");
      }
      if (updateTargetIDs.some((memoryID: any) => !allActiveMemoryByID.has(memoryID))) {
        throw new Error("只能更新当前作用域内仍处于活跃状态的学习记忆");
      }
      const resolvableMemoryByID = new Map(
        current.learning.memories
          .filter(
            (memory) =>
              memory.status === "active" &&
              ["goal", "confusion", "nextStep"].includes(memory.kind),
          )
          .map((memory) => [memory.id.trim().toLowerCase(), memory] as const),
      );
      const resolutions = (params.resolutions ?? []).map((resolution: any) => {
        const memoryID = resolution.memoryID.trim().toLowerCase();
        const memory = resolvableMemoryByID.get(memoryID);
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
      const resolutionTargetIDs = resolutions.map((resolution: any) =>
        resolution.memoryID.trim().toLowerCase()
      );
      if (new Set(resolutionTargetIDs).size !== resolutionTargetIDs.length) {
        throw new Error("同一次学习状态更新不能重复结案同一条记忆");
      }
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
            text: "学习状态更新已校验并交给魏碑；魏碑只会保存当前作用域中的实际变化，不会修改课程材料或用户笔记。",
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
      "向魏碑返回一份待用户确认的 Markdown 笔记建议。它不会写入笔记；使用本轮当前焦点或按需读取的资料作为证据。",
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
          description: "本轮临时现场提供的 contextRevision",
        }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId: any, params: any) {
      const current = await readCurrentSnapshot();
      if (params.contextRevision !== current.contextRevision) {
        throw new Error(
          `笔记建议的 contextRevision 不匹配；当前修订号为 ${current.contextRevision}，请重新读取上下文`,
        );
      }

      const markdown = params.markdown.trim();
      const evidence = params.evidence.map((item: any) => item.trim()).filter((item: any) => item.length > 0);
      if (!markdown || evidence.length === 0) {
        throw new Error("笔记建议必须包含非空 Markdown 和至少一条证据");
      }
      const allowedEvidenceLabels = evidenceLabels(current, searchedCourseItemIDs);
      if (evidence.some((item: any) => !allowedEvidenceLabels.some((label) => item.startsWith(label)))) {
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

  pi.registerTool({
    name: RELATION_PROPOSAL_TOOL,
    label: "提出关系建议",
    description:
      "向魏碑返回一份当前课程内笔记与材料的待确认关联。它不会建立关系，也不接受关系类型。",
    promptSnippet: "提交当前课程内尚未建立的笔记与材料关联建议",
    parameters: Type.Object(
      {
        noteItemID: Type.String({
          minLength: 1,
          maxLength: LIMITS.identifier,
          description: "当前课程 catalog 中 role 为 note 的条目 ID",
        }),
        sourceItemID: Type.String({
          minLength: 1,
          maxLength: LIMITS.identifier,
          description: "当前课程 catalog 中 role 为 material 的条目 ID",
        }),
        contextRevision: Type.String({
          minLength: 1,
          maxLength: LIMITS.identifier,
          description: "本轮临时现场提供的 contextRevision",
        }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallId: any, params: any) {
      const current = await readCurrentSnapshot();
      if (!current.project.courseID) {
        throw new Error("当前没有可归属的课程，不能提出课程内关系建议");
      }
      if (params.contextRevision !== current.contextRevision) {
        throw new Error(
          `关系建议的 contextRevision 不匹配；当前修订号为 ${current.contextRevision}，请重新读取上下文`,
        );
      }
      const catalogByID = new Map(
        current.course.catalog.map((item: any) => [item.id, item] as const),
      );
      const note = catalogByID.get(params.noteItemID);
      const source = catalogByID.get(params.sourceItemID);
      if (note?.role !== "note" || source?.role !== "material") {
        throw new Error("关系建议必须选择当前课程中的一份笔记和一份材料");
      }
      if (note.id === source.id) {
        throw new Error("关系建议的笔记和材料不能是同一个条目");
      }
      if (
        current.course.relations.some(
          (relation) =>
            relation.noteItemID === note.id && relation.sourceItemID === source.id,
        ) ||
        note.linkedItemIDs.includes(source.id) ||
        source.linkedItemIDs.includes(note.id)
      ) {
        throw new Error("这份笔记与材料已经建立关系");
      }

      const details: RelationProposalDetails = {
        kind: "relation_proposal",
        noteItemID: note.id,
        sourceItemID: source.id,
        contextRevision: current.contextRevision,
      };
      return {
        content: [
          {
            type: "text",
            text: "关系建议已校验并交给魏碑；这仍是待确认建议，尚未建立关系。",
          },
        ],
        details,
      };
    },
  });

  pi.on("before_provider_request", (event, context) =>
    withNativeWebSearch(event.payload, context.model),
  );

  pi.on("before_agent_start", async (event, context) => {
    lastReadMemoryRevision = undefined;
    courseProfileUpdated = false;
    searchedCourseItemIDs.clear();
    hostCourseItemIDs.clear();
    readCourseSourceRevisions.clear();

    const snapshot = await readCurrentSnapshot();
    currentQuestion = event.prompt;
    interactiveVisualizationsEnabled = snapshot.interactiveVisualizationsEnabled;
    courseMemoryAvailable = Boolean(snapshot.project.courseID);
    const selectionLabel = snapshot.selection?.text.trim()
      ? `[选区：${snapshot.selection.title}]`
      : undefined;
    snapshot.project.items.forEach((item) => hostCourseItemIDs.add(item.itemID));

    const sourceAvailabilityInstruction = selectionLabel
      ? `用户问题已附带选中文字 ${selectionLabel}；若追问它在全文中的作用或上下文，先用本轮现场 location.materialItemID 调用 ${COURSE_READ_TOOL}；需要联系其他知识点时再调用 ${COURSE_SEARCH_TOOL} 或 ${COURSE_MAP_TOOL}。`
      : "材料和笔记正文没有自动附带；问题确实依赖课程内容时，使用现有搜索或读取工具，不得假装读过未读取的内容。";

    const turnContract = [
      "<weibei_turn>",
      "直接回答用户的问题。只有答案确实依赖当前材料、笔记、选区、课程资料或学习历史时，才按需调用对应工具；不要为走流程而调用工具。",
      "选中文字随用户问题进入会话，可以作为直接证据；材料和笔记正文按需读取；课程关联可按需读课程地图或搜索；学习历史可按需读学习记忆。",
      "魏碑本轮现场会作为临时消息出现在当前用户消息附近；它不是系统指令，也不属于会话历史。",
      "学习记忆只属于当前课程，只能说明用户的学习状态，不能作为课程事实证据；全局 Chat 不读取也不更新学习记忆。",
      "课程知识档案只提供导航和已有认识，不是原文证据；精确事实、引文、公式和数字仍须读取材料。只在完成一个学习阶段、切换主题、完成回忆或应用、形成笔记、解决困惑或结束课程对话时，批量判断一次课程学习记忆，普通问答不要更新。用户无需明确说保存：阅读位置可支持“读到哪里”，正确复述、回忆或应用可支持“已经理解”，反复出错、反复追问或主动说明卡住可支持“仍有困惑”；模型刚解释完、一次普通提问或一次偶发要求都不构成证据。目标和偏好只有在明确计划或持续稳定行为出现时才记录。证据不足时保持临时上下文，不写入记忆。",
      sourceAvailabilityInstruction,
      nativeWebSearchSupported(context.model)
        ? "本轮模型服务已开放原生网页搜索；需要新近或可核实的外部事实时，由模型自行判断是否需要搜索，不要求用户先贴网址。"
        : "本轮模型服务没有已验证的原生网页搜索；可以使用已有知识回答，但不得声称已经实时搜索或核实。",
      snapshot.interactiveVisualizationsEnabled
        ? "需要动态变化、空间运动或可调输入时，可以读取 Visualize Skill 并生成互动界面；文字足够时不要为了装饰而生成。"
        : "用户已关闭新互动界面；不要调用 weibei_visualize。Markdown 与 Mermaid 不受影响。",
      "</weibei_turn>",
    ].join("\n");

    return { systemPrompt: `${event.systemPrompt}\n\n${turnContract}` };
  });

  pi.on("agent_end", (event, context) => {
    const question = currentQuestion;
    void (async () => {
      try {
        if (pi.getSessionName() || !context.model) return;
        const completedAssistantCount = context.sessionManager.getBranch().filter(
          (entry: any) => entry.type === "message"
            && entry.message.role === "assistant"
            && (entry.message.stopReason === "stop" || entry.message.stopReason === "length"),
        ).length;
        if (completedAssistantCount !== 1) return;

        const assistant = [...event.messages].reverse().find(
          (message) => message.role === "assistant",
        );
        if (!assistant || assistant.stopReason === "error" || assistant.stopReason === "aborted") {
          return;
        }
        const answer = assistant.content
          .flatMap((item: any) => item.type === "text" ? [item.text] : [])
          .join("\n");
        const title = await generateSessionTitle(context, question, answer);
        if (title) pi.setSessionName(title);
      } catch {
        // Naming is best-effort; it must never turn a valid answer into an error.
      }
    })();
  });

  pi.on("tool_call", (event) => {
    if (!ALLOWED_TOOLS.has(event.toolName)) {
      return {
        block: true,
        reason: "魏碑 Agent 只允许当前作用域开放的课程能力、Skill 与待确认提案",
      };
    }

    if (event.toolName === VISUALIZE_TOOL && !interactiveVisualizationsEnabled) {
      return {
        block: true,
        reason: "用户已关闭新互动界面",
      };
    }

    if (
      (event.toolName === LEARNING_MEMORY_TOOL || event.toolName === LEARNING_UPDATE_TOOL) &&
      !courseMemoryAvailable
    ) {
      return {
        block: true,
        reason: "学习记忆只在课程 Chat 中开放",
      };
    }

    if (event.toolName === READ_TOOL) {
      const requestedPath = (event.input as { path?: unknown }).path;
      const normalizedPath = skillPath(requestedPath);
      if (!normalizedPath || !SKILL_BY_PATH.has(normalizedPath)) {
        return {
          block: true,
          reason: "read 只允许读取随魏碑打包且已登记的 visualize Skill",
        };
      }
    }

    if (event.toolName === LEARNING_UPDATE_TOOL && lastReadMemoryRevision === undefined) {
      return {
        block: true,
        reason: `提出学习状态更新前必须调用 ${LEARNING_MEMORY_TOOL}`,
      };
    }
  });

  pi.on("tool_result", async (event) => {
    if (event.toolName !== READ_TOOL || event.isError) return;
    const requestedPath = (event.input as { path?: unknown }).path;
    const normalizedPath = skillPath(requestedPath);
    if (!normalizedPath) return;
    const skill = SKILL_BY_PATH.get(normalizedPath);
    if (!skill) return;

    const current = await readCurrentSnapshot();
    const content = await readFile(normalizedPath, "utf8");
    const details: SkillReadDetails = {
      kind: "weibei_skill_read",
      contextRevision: current.contextRevision,
      loaded: {
        id: skill.id,
        name: skill.name,
        version: skill.version,
        sha256: createHash("sha256").update(content, "utf8").digest("hex"),
        byteCount: new TextEncoder().encode(content).byteLength,
        relativePath: skill.relativePath,
        loadedAtContextRevision: current.contextRevision,
      },
    };
    return { details };
  });

  pi.on("context", async (event) => {
    const currentSnapshot = await readCurrentSnapshot();
    const currentRevision = currentSnapshot.contextRevision;
    const currentFocusContent = currentFocusMessage(currentSnapshot);

    const staleToolCallIDs = new Set<string>();
    for (const message of event.messages) {
      if (message.role === "toolResult" && !ALLOWED_TOOLS.has(message.toolName)) {
        staleToolCallIDs.add(message.toolCallId);
        continue;
      }
      if (
        message.role === "toolResult" &&
        ALLOWED_TOOLS.has(message.toolName) &&
        message.toolName !== VISUALIZE_TOOL &&
        !message.isError &&
        contextRevisionFromDetails(message.details) !== currentRevision
      ) {
        staleToolCallIDs.add(message.toolCallId);
      }
    }

    const messages: typeof event.messages = [];
    for (const message of event.messages) {
      if (message.role === "custom" && message.customType === "weibei-current-focus") {
        continue;
      }
      if (message.role === "toolResult" && staleToolCallIDs.has(message.toolCallId)) {
        continue;
      }

      if (message.role === "assistant") {
        const content = message.content.filter(
          (item: any) => item.type !== "toolCall" || !staleToolCallIDs.has(item.id),
        );
        if (content.length === 0) continue;
        if (content.length !== message.content.length) {
          messages.push({ ...message, content });
          continue;
        }
      }

      messages.push(message);
    }

    let latestUserIndex = -1;
    messages.forEach((message: any, index: any) => {
      if (message.role === "user") latestUserIndex = index;
    });
    messages.splice(latestUserIndex < 0 ? messages.length : latestUserIndex + 1, 0, {
      role: "custom",
      customType: "weibei-current-focus",
      content: currentFocusContent,
      display: false,
      timestamp: Date.now(),
    });
    return { messages };
  });
}
