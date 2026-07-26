import { realpathSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { normalizedEvidenceText, richAnswerEvidenceText } from "./rich-answer-validation";
import {
  AnswerFormPolicy,
  CONTEXT_FILE_ENV,
  ContextSnapshotV2,
  CourseCatalogItemSnapshot,
  CourseItemSnapshot,
  CourseSnapshot,
  LIMITS,
  LearningMemoryEntrySnapshot,
  LearningMemoryKind,
  LearningMemoryOrigin,
  LearningSnapshot,
  RecentMessageSnapshot,
  SessionSnapshot,
  SourceSnapshot,
  StudyLocationSnapshot,
  VisualAssetFileSnapshot,
} from "./agent-contracts";


export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}


export function requireRecord(value: unknown, field: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new Error(`魏碑上下文字段 ${field} 必须是对象`);
  }
  return value;
}


export function requireString(value: unknown, field: string): string {
  if (typeof value !== "string") {
    throw new Error(`魏碑上下文字段 ${field} 必须是字符串`);
  }
  return value;
}


export function requireBoolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") {
    throw new Error(`魏碑上下文字段 ${field} 必须是布尔值`);
  }
  return value;
}


export function requireNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`魏碑上下文字段 ${field} 必须是数字`);
  }
  return value;
}


export function requireIdentifier(value: unknown, field: string): string {
  const text = requireString(value, field);
  if (text.length === 0 || text.length > LIMITS.identifier) {
    throw new Error(`魏碑上下文字段 ${field} 长度无效`);
  }
  return text;
}


export function readAnswerFormPolicy(value: unknown): AnswerFormPolicy {
  if (value === undefined || value === null) return "automatic";
  const policy = requireString(value, "answerFormPolicy");
  if (policy === "automatic" || policy === "textOnly" || policy === "partialRichAllowed") {
    return policy;
  }
  throw new Error("魏碑上下文字段 answerFormPolicy 无效");
}


export function truncate(text: string, maximumCharacters: number): string {
  if (text.length <= maximumCharacters) return text;

  let result = text.slice(0, maximumCharacters);
  const finalCodeUnit = result.charCodeAt(result.length - 1);
  if (finalCodeUnit >= 0xd800 && finalCodeUnit <= 0xdbff) {
    result = result.slice(0, -1);
  }
  return result;
}


export function readSource(value: unknown, field: string, textLimit: number): SourceSnapshot {
  const source = requireRecord(value, field);
  const originalText = requireString(source.text, `${field}.text`);
  return {
    title: truncate(requireString(source.title, `${field}.title`), LIMITS.title),
    text: truncate(originalText, textLimit),
    isTruncated:
      requireBoolean(source.isTruncated, `${field}.isTruncated`) || originalText.length > textLimit,
  };
}


export function readOptionalSource(value: unknown, field: string, textLimit: number): SourceSnapshot | undefined {
  if (value === undefined || value === null) return undefined;
  return readSource(value, field, textLimit);
}


export function readRecentMessages(value: unknown): RecentMessageSnapshot[] {
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


export function readStringArray(
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


export function readCourseCatalogItem(
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


export function readCourse(value: unknown): CourseSnapshot {
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


export function readLearning(value: unknown): LearningSnapshot {
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


export async function readContextEnvelope(): Promise<Record<string, unknown>> {
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


export async function readCurrentSnapshot(): Promise<ContextSnapshotV2> {
  const envelope = await readContextEnvelope();

  return {
    schemaVersion: 2,
    requestID: requireIdentifier(envelope.requestID, "requestID"),
    contextRevision: requireIdentifier(envelope.contextRevision, "contextRevision"),
    answerFormPolicy: readAnswerFormPolicy(envelope.answerFormPolicy),
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


export async function readCurrentVisualAssets(
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
    snapshot.course.catalog.filter((item) => item.isCurrentMaterial).map((item) => item.id),
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


export function visualAssetMagicMatches(
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


export function contextRevisionFromDetails(details: unknown): string | undefined {
  if (!isRecord(details)) return undefined;
  return typeof details.contextRevision === "string" ? details.contextRevision : undefined;
}


export function evidenceLabels(snapshot: ContextSnapshotV2): string[] {
  const labels: string[] = [];
  if (snapshot.note.text.trim()) labels.push(`[笔记：${snapshot.note.title}]`);
  if (snapshot.material?.text.trim()) labels.push(`[材料：${snapshot.material.title}]`);
  if (snapshot.selection?.text.trim()) labels.push(`[选区：${snapshot.selection.title}]`);
  return labels;
}


export function richAnswerRenderableAssetKind(kind: string, title: string): boolean {
  const normalizedKind = kind.trim().toLocaleLowerCase();
  if (["image", "pdf", "png", "jpg", "jpeg", "webp", "gif"].includes(normalizedKind)) {
    return true;
  }
  return /\.(?:png|jpe?g|webp|gif|pdf)$/iu.test(title.trim());
}


export function richAnswerCurrentItems(
  snapshot: ContextSnapshotV2,
  searchedCourseItemIDs: ReadonlySet<string> = new Set<string>(),
) {
  return snapshot.course.catalog
    .filter(
      (item) =>
        item.isCurrentMaterial || item.isCurrentNote || searchedCourseItemIDs.has(item.id),
    )
    .map((item) => ({
      id: item.id,
      title: item.title,
      kind: item.kind,
      role: item.role,
      currentMaterial: item.isCurrentMaterial,
      currentNote: item.isCurrentNote,
      renderableAsset: richAnswerRenderableAssetKind(item.kind, item.title),
    }));
}


export function richAnswerAllowedAssetIDs(
  snapshot: ContextSnapshotV2,
  searchedCourseItemIDs: ReadonlySet<string> = new Set<string>(),
): string[] {
  return richAnswerCurrentItems(snapshot, searchedCourseItemIDs)
    .filter(
      (item) =>
        item.renderableAsset &&
        (item.currentMaterial || searchedCourseItemIDs.has(item.id)),
    )
    .map((item) => item.id);
}


export function richAnswerSourceBindings(
  snapshot: ContextSnapshotV2,
  searchedCourseItemIDs: ReadonlySet<string> = new Set<string>(),
) {
  const exactExcerptCandidates = Array.from(
    richAnswerEvidenceText(snapshot, searchedCourseItemIDs).entries(),
  ).map(([sourceLabel, source]) => {
    const normalizedSource = normalizedEvidenceText(source.text);
    const excerpts = normalizedSource
      .split(/[。！？.!?]\s*/u)
      .map((excerpt) => excerpt.trim())
      .filter((excerpt) => excerpt.length >= 12)
      .map((excerpt) => excerpt.slice(0, 140))
      .slice(0, 3);
    return {
      sourceLabel,
      excerpts: excerpts.length > 0
        ? excerpts
        : normalizedSource
          ? [normalizedSource.slice(0, 140)]
          : [],
    };
  });
  return {
    answerFormPolicy: snapshot.answerFormPolicy,
    readableSourceLabels: Array.from(
      richAnswerEvidenceText(snapshot, searchedCourseItemIDs).keys(),
    ),
    exactExcerptCandidates,
    allowedAssetIDs: richAnswerAllowedAssetIDs(snapshot, searchedCourseItemIDs),
    currentItems: richAnswerCurrentItems(snapshot, searchedCourseItemIDs),
    rules: {
      sourceLabels:
        "evidenceLedger.sourceLabel 必须逐字使用 readableSourceLabels 或本轮课程搜索返回的 evidenceLabel；不要引用空材料、空笔记、文件名、目录标题或学习记忆来支持课程事实。",
      assetIDs:
        "图像、地图和设计叠层只能使用 allowedAssetIDs 中的当前材料 item.id；image.assetID 与 evidenceLedger.assetIDs 都必须写 item.id，不写文件名、标签、注册名或标题。",
      excerpts:
        "evidenceLedger.excerpt 必须来自同一来源标签当前可读文本中的短摘录；可直接逐字复制 exactExcerptCandidates，也可从本轮已读原文选择其他真实短句。没有可读来源时保持纯文本，说明材料缺口，不调用富回答。",
    },
    imageOverlayGuidance: [
      "只有当前材料真实提供图像、地图或设计资产，且 allowedAssetIDs 非空时，才做图像叠层。",
      "ui 结构使用 image/canvas 作为真实当前材料底图，再叠加 region/path/point/label/vector 等 overlay primitives。",
      "保留 1–2 个有意义 binding，例如切换观察层、探查区域或对比标注；不要把图像题做成专题模板、整页看板或凭空重绘。",
      "若材料里的采样窗口、测量方法、抗锯齿、近似条件或阈值适用范围会改变结论，必须把这些解释边界同时写进 narrative 与可见 ui 标签、读数或证据节点，不能只留下最终数值。",
      "材料明确要求放大、探查、切换图层或前后对比时，要用对应的可见控件与 binding 兑现；不要用无关的通用滑杆替代指定观察动作。",
    ],
  };
}


export function currentTurnEvidenceMatches(snapshot: ContextSnapshotV2, evidence: string): boolean {
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


export function resolutionEvidenceMatches(snapshot: ContextSnapshotV2, evidence: string): boolean {
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


export function currentTurnEvidenceStatement(evidence: string): string | undefined {
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