#!/usr/bin/env -S npm exec -- tsx

import fs from "node:fs";
import path from "node:path";
import { z } from "zod/v4";
import { parseEvidenceJson } from "./evidence-json.js";

const jsonObjectSchema = z.object({}).catchall(z.json());
const optionalJson = z.json().optional();

const caseSnapshotSchema = z
  .object({
    caseID: optionalJson,
    id: optionalJson,
    caseId: optionalJson,
    caseKind: optionalJson,
    question: optionalJson,
    subject: optionalJson,
    materialTitle: optionalJson,
    materialKind: optionalJson,
    materialText: optionalJson,
    selectionTitle: optionalJson,
    selectionText: optionalJson,
  })
  .catchall(z.json());

const shapeDecisionSchema = z
  .object({
    caseKind: optionalJson,
    preferredShape: optionalJson,
    actualShape: optionalJson,
    expectedShape: optionalJson,
    directManipulation: optionalJson,
  })
  .catchall(z.json());

const t1ProgramSchema = z
  .object({
    sceneID: optionalJson,
    family: optionalJson,
    version: optionalJson,
    maxHeight: optionalJson,
    directManipulation: optionalJson,
    componentNames: z.array(z.json()).optional(),
  })
  .catchall(z.json());

const t2CompositionSchema = z
  .object({
    sceneID: optionalJson,
    family: optionalJson,
    rootID: optionalJson,
    roles: z.array(z.json()).optional(),
    nodeCount: optionalJson,
    dataRowCount: optionalJson,
  })
  .catchall(z.json());

const expressionPlanSchema = z
  .object({
    t1Programs: z.array(t1ProgramSchema).optional(),
    t2Compositions: z.array(t2CompositionSchema).optional(),
  })
  .catchall(z.json());

const sourceBindingSchema = z
  .object({
    textSourceLabels: z.array(z.json()).optional(),
    evidenceLedgerLabels: z.array(z.json()).optional(),
    sceneEvidenceIDs: z.array(z.json()).optional(),
    evidenceState: optionalJson,
    hasExpectedSource: optionalJson,
  })
  .catchall(z.json());

const repairSchema = z
  .object({
    failureReason: optionalJson,
    previousRunID: optionalJson,
    previousStatus: optionalJson,
    repairNote: optionalJson,
    isRetest: optionalJson,
  })
  .catchall(z.json());

const protocolSchema = z
  .object({
    status: optionalJson,
    validationKind: optionalJson,
    passedChecks: z.array(z.json()).optional(),
    issues: z.array(z.json()).optional(),
    protocolDiagnostics: z.array(z.json()).optional(),
  })
  .catchall(z.json());

const indexEntrySchema = z
  .object({
    recordPath: z.string().optional(),
    record_file: z.string().optional(),
    recordJson: z.string().optional(),
    record: z.string().optional(),
    recordPathRelative: z.string().optional(),
    requestPath: z.string().optional(),
    request_file: z.string().optional(),
    requestJson: z.string().optional(),
    request: z.string().optional(),
    replyPath: z.string().optional(),
    reply_file: z.string().optional(),
    replyJson: z.string().optional(),
    reply: z.string().optional(),
    validationPath: z.string().optional(),
    validation_file: z.string().optional(),
    validationJson: z.string().optional(),
    validation: z.string().optional(),
    caseDir: z.string().optional(),
    case_id: optionalJson,
    caseID: optionalJson,
    caseSnapshot: caseSnapshotSchema.optional(),
    repetition: optionalJson,
    round: optionalJson,
    roundIndex: optionalJson,
    question: optionalJson,
    status: optionalJson,
    elapsedSeconds: optionalJson,
    subject: optionalJson,
    materialText: optionalJson,
    selectionTitle: optionalJson,
    selectionText: optionalJson,
    caseKind: optionalJson,
  })
  .catchall(z.json());

const indexDocumentSchema = z
  .object({ records: z.array(indexEntrySchema).optional() })
  .catchall(z.json());

const recordDocumentSchema = z
  .object({
    caseSnapshot: caseSnapshotSchema.optional(),
    shapeDecision: shapeDecisionSchema.optional(),
    expressionPlan: expressionPlanSchema.optional(),
    sourceBinding: sourceBindingSchema.optional(),
    repairAndRetest: repairSchema.optional(),
    toolAndProtocolValidation: protocolSchema.optional(),
    repetition: optionalJson,
    round: optionalJson,
    question: optionalJson,
    status: optionalJson,
    state: optionalJson,
    elapsedSeconds: optionalJson,
    duration: optionalJson,
    caseKind: optionalJson,
    subject: optionalJson,
  })
  .catchall(z.json());

const requestDocumentSchema = z
  .object({
    caseSnapshot: caseSnapshotSchema.optional(),
    shapeDecision: shapeDecisionSchema.optional(),
    expressionPlan: expressionPlanSchema.optional(),
    sourceBinding: sourceBindingSchema.optional(),
    repairAndRetest: repairSchema.optional(),
    question: optionalJson,
    prompt: optionalJson,
    subject: optionalJson,
    materialTitle: optionalJson,
    materialKind: optionalJson,
    materialText: optionalJson,
    selectionTitle: optionalJson,
    selectionText: optionalJson,
  })
  .catchall(z.json());

const replyDocumentSchema = z
  .object({
    backend: optionalJson,
    text: optionalJson,
    richAnswer: optionalJson,
  })
  .catchall(z.json());

const runDocumentSchema = z
  .object({
    createdAt: optionalJson,
    runID: optionalJson,
    rootPath: optionalJson,
    retestOfRunID: optionalJson,
  })
  .catchall(z.json());

type JsonValue = z.infer<ReturnType<typeof z.json>>;
type IndexEntry = z.infer<typeof indexEntrySchema>;
type IndexDocument = z.infer<typeof indexDocumentSchema>;
type RecordDocument = z.infer<typeof recordDocumentSchema>;
type RequestDocument = z.infer<typeof requestDocumentSchema>;
type ReplyDocument = z.infer<typeof replyDocumentSchema>;
type ProtocolDocument = z.infer<typeof protocolSchema>;
type RunDocument = z.infer<typeof runDocumentSchema>;

interface ReadResult<T> {
  ok: boolean;
  value: T | null;
  path: string;
  error: string | null;
  missing: boolean;
}

interface CliOptions {
  runDir: string | null;
  runId: string | null;
  source: string;
  output: string | null;
  force: boolean;
  help?: boolean;
}

interface CopiedAssets {
  count: number;
  dir: string;
  runDir: string;
}

interface BuildReport {
  missing: string[];
  copied: CopiedAssets;
}

interface Screenshots {
  before: string | null;
  after: string | null;
  missing: string[];
}

interface T1ProgramView {
  sceneID: string;
  family: string;
  version: string;
  maxHeight: number | null;
  directManipulation: string;
  componentNames: JsonValue[];
}

interface T2CompositionView {
  sceneID: string;
  family: string;
  rootID: string;
  roles: JsonValue[];
  nodeCount: number;
  dataRowCount: number;
}

interface AttemptView {
  caseID: string;
  repetition: number;
  caseKind: string;
  subject: string;
  question: string;
  materialTitle: string;
  materialKind: string;
  materialText: string;
  selectionTitle: string;
  selectionText: string;
  status: string;
  elapsedSeconds: number | null;
  elapsedDisplay: string;
  preferredShape: string;
  actualShape: string;
  expectedShape: string;
  directManipulation: string;
  expressionPlan: {
    t1SceneCount: number;
    t2SceneCount: number;
    t1Programs: T1ProgramView[];
    t2Compositions: T2CompositionView[];
  };
  protocol: {
    status: string;
    validationKind: string;
    passedChecks: JsonValue[];
    issues: JsonValue[];
    protocolDiagnostics: JsonValue[];
  };
  sourceBinding: {
    textSourceLabels: JsonValue[];
    evidenceLedgerLabels: JsonValue[];
    sceneEvidenceIDs: JsonValue[];
    evidenceState: string;
    hasExpectedSource: boolean;
  };
  rawRequest: string;
  rawReply: {
    backend: string;
    text: string;
    hasRichAnswer: string;
    json: string;
  };
  rawValidation: string;
  failureReason: string;
  repair: {
    previousRunID: string;
    previousStatus: string;
    repairNote: string;
    isRetest: string;
  };
  beforeImage: string | null;
  afterImage: string | null;
  missingFields: string[];
  missingScreenshotFields: string[];
}

interface CaseGroup {
  caseID: string;
  subject: string;
  caseKind: string;
  attempts: AttemptView[];
  question: string;
  materialTitle: string;
  materialKind: string;
  selectionTitle: string;
  rounds: string[];
  latestAttempt: AttemptView;
  acceptState: string;
}

interface MissingKindSummary {
  kind: string;
  target: number;
  actual: number;
  gap: number;
  pass: boolean;
}

interface Overview {
  totalExpected: number;
  totalActual: number;
  totalGap: number;
  expectedByKind: Record<string, number>;
  actualByKind: Record<string, number>;
  missingByKind: MissingKindSummary[];
  filterOptions: {
    subjects: string[];
    statuses: string[];
    shapes: string[];
    repetitions: string[];
  };
  statusCount: Record<string, number>;
  subjectCount: number;
  runCreatedAt: string;
  runId: string;
  retestOfRunID: string;
  completionState: string;
  missingMandatoryCount: number;
}

interface CollectedRecords {
  runMeta: RunDocument;
  indexMeta: IndexDocument;
  records: AttemptView[];
}

interface EvidencePayload {
  generatedAt: string;
  runDir: string;
  runId: string;
  runMeta: RunDocument;
  indexMeta: IndexDocument;
  overview: Overview;
  cases: CaseGroup[];
  missing: string[];
  copiedImages: number;
}

const TARGET_BREAKDOWN: Record<string, number> = {
  rich: 40,
  "text-only": 6,
  degradation: 9,
  "invalid-protocol": 1,
};
const TARGET_TOTAL = 56;
const DEFAULT_SOURCE = ".build/rich-answer-evidence";

/** 解析离线验收包生成命令的参数。 */
function parseArgs(): CliOptions {
  const args = process.argv.slice(2);
  const result: CliOptions = {
    runDir: null,
    runId: null,
    source: DEFAULT_SOURCE,
    output: null,
    force: false,
  };

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    if (arg === "--run-dir") {
      result.runDir = args[i + 1]!;
      i += 1;
      continue;
    }
    if (arg === "--run-id") {
      result.runId = args[i + 1]!;
      i += 1;
      continue;
    }
    if (arg === "--source") {
      result.source = args[i + 1] || DEFAULT_SOURCE;
      i += 1;
      continue;
    }
    if (arg === "--output") {
      result.output = args[i + 1]!;
      i += 1;
      continue;
    }
    if (arg === "--force") {
      result.force = true;
      continue;
    }
    if (arg === "--help" || arg === "-h") {
      result.help = true;
    }
  }

  return result;
}

/** 构造命令行帮助文本。 */
function usage(): string {
  return [
    "用途：将 .build/rich-answer-evidence/<runID>/ 的验收留档生成离线浏览包",
    "",
    "用法: ",
    "  npm exec -- tsx Prototypes/RichAnswerEvidenceViewer/generate-offline-evidence-package.ts --run-dir <runDir> --output <outDir> [--force]",
    "  npm exec -- tsx Prototypes/RichAnswerEvidenceViewer/generate-offline-evidence-package.ts --run-id <runID> --source <sourceDir> --output <outDir> [--force]",
    "",
    "参数:",
    "  --run-dir      直接指定 run 目录",
    "  --run-id       指定 runID（配合 --source）",
    "  --source       run 目录父路径，默认 .build/rich-answer-evidence",
    "  --output       输出目录（建议：./Prototypes/RichAnswerEvidenceViewer/out）",
    "  --force        输出目录存在时覆盖",
  ].join("\n");
}

/** 将未知输入规范化为非空展示文本。 */
function toText(value: unknown, fallback = "缺失"): string {
  if (value === null || value === undefined) return fallback;
  if (typeof value === "string") return value.trim() || fallback;
  return String(value);
}

/** 将未知输入转换为有限数值。 */
function toNumber(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** 将可空真值转换为中文展示文本。 */
function boolText(value: unknown): string {
  if (value === null || value === undefined) return "缺失";
  return value ? "是" : "否";
}

/** 确保目标目录存在。 */
function ensureDir(dirPath: string): void {
  fs.mkdirSync(dirPath, { recursive: true });
}

/** 判断路径是否为普通文件。 */
function existsFile(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

/** 判断路径是否为目录。 */
function existsDir(dirPath: string): boolean {
  try {
    return fs.statSync(dirPath).isDirectory();
  } catch {
    return false;
  }
}

/**
 * 读取 JSON 文件并使用对应领域 schema 验证，同时保留缺失或结构错误信息。
 *
 * @param filePath - JSON 文件路径
 * @param schema - 文件对应的领域 schema
 * @returns 成功时包含已验证数据，失败时包含可展示的错误详情
 */
function readJSON<T>(filePath: string, schema: z.ZodType<T>): ReadResult<T> {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    return {
      ok: true,
      value: parseEvidenceJson(raw, filePath, schema),
      path: filePath,
      error: null,
      missing: false,
    };
  } catch (error: unknown) {
    return {
      ok: false,
      value: null,
      path: filePath,
      error: error instanceof Error ? error.message : String(error),
      missing: !existsFile(filePath),
    };
  }
}

/** 解析存在的证据文件路径。 */
function resolveIfExists(
  runRoot: string,
  candidate: string | null | undefined,
): string | null {
  if (!candidate) return null;
  const absolute = path.isAbsolute(candidate)
    ? candidate
    : path.join(runRoot, candidate);
  return existsFile(absolute) ? absolute : null;
}

/** 返回列表中的第一个有效值。 */
function pickFirst<T>(...values: (T | null | undefined)[]): T | undefined {
  for (const value of values) {
    if (value === null || value === undefined) continue;
    if (typeof value === "string" && !value.trim()) continue;
    if (Array.isArray(value) && value.length === 0) continue;
    if (
      typeof value === "object" &&
      !Array.isArray(value) &&
      Object.keys(value).length === 0
    )
      continue;
    return value;
  }
}

/** 规范化用例分类。 */
function normalizeKind(raw: unknown): string {
  const value = toText(raw, "rich").toLowerCase();
  if (
    value.includes("invalid") ||
    value.includes("protocol") ||
    value.includes("illegal") ||
    value.includes("协议")
  )
    return "invalid-protocol";
  if (value.includes("degrad") || value.includes("降级")) return "degradation";
  if (value.includes("text") || value.includes("文本") || value.includes("纯"))
    return "text-only";
  if (value.includes("rich") || value.includes("可视") || value.includes("图"))
    return "rich";
  return "rich";
}

/** 在限定深度内递归收集 PNG 文件。 */
function walkPngs(
  rootDir: string,
  depth = 0,
  maxDepth = 5,
  result: string[] = [],
): string[] {
  if (depth > maxDepth || !existsDir(rootDir)) return result;
  const entries = fs.readdirSync(rootDir, { withFileTypes: true });
  for (const ent of entries) {
    const full = path.join(rootDir, ent.name);
    if (ent.isDirectory()) {
      walkPngs(full, depth + 1, maxDepth, result);
      continue;
    }
    if (ent.isFile() && full.toLowerCase().endsWith(".png")) result.push(full);
  }
  return result;
}

/** 按 before/after 标签选择最匹配的截图。 */
function chooseByTag(files: string[], tag: string): string | null {
  const t = tag.toLowerCase();
  let best: string | null = null;
  let bestScore = -1;
  for (const file of files) {
    const name = path.basename(file).toLowerCase();
    let score = 0;
    if (name === `${t}.png`) score = 100;
    else if (
      name.includes(`-${t}`) ||
      name.includes(`_${t}`) ||
      name.includes(`_${t}_`)
    )
      score = 90;
    else if (name.includes(t)) score = 70;
    if (
      tag === "before" &&
      /(before|start|init|init-state|initstate|before-action|before_action|原始|操作前)/.test(
        name,
      )
    )
      score += 40;
    if (
      tag === "after" &&
      /(after|final|final-state|result|answer|answer_after|操作后|更新后)/.test(
        name,
      )
    )
      score += 30;
    if (score > bestScore) {
      bestScore = score;
      best = file;
    }
  }
  return best;
}

/** 收集并复制单个用例的操作前后截图。 */
function collectScreenshots(
  caseDir: string,
  report: BuildReport,
  copiedAssets: CopiedAssets,
): Screenshots {
  const files = walkPngs(caseDir);
  if (files.length === 0) {
    report.missing.push(`截图目录为空：${caseDir}`);
  }
  const before = chooseByTag(files, "before");
  const after = chooseByTag(files, "after");
  const missing: string[] = [];
  if (!before) missing.push("before截图");
  if (!after) missing.push("after截图");
  return {
    before: before ? copyAsset(before, copiedAssets) : null,
    after: after ? copyAsset(after, copiedAssets) : null,
    missing,
  };
}

/** 将截图复制到输出资源目录。 */
function copyAsset(src: string, copiedAssets: CopiedAssets): string {
  const base = path.basename(src);
  const safeName = base.replace(/[^a-zA-Z0-9._-]/g, "_");
  const relDir = path.relative(copiedAssets.runDir || "", path.dirname(src));
  const safeDir = relDir
    .split(path.sep)
    .filter(Boolean)
    .map((part) => part.replace(/[^a-zA-Z0-9._-]/g, "_"))
    .join("-");
  const outName = `${safeDir ? `${safeDir}-` : ""}${safeName}`;
  const dst = path.join(copiedAssets.dir, outName);
  ensureDir(path.dirname(dst));
  fs.copyFileSync(src, dst);
  copiedAssets.count += 1;
  return `assets/${outName}`;
}

/** 将一个索引条目转换为离线展示尝试记录。 */
function collectAttempt(
  entry: IndexEntry,
  runDir: string,
  report: BuildReport,
  copiedAssets: CopiedAssets,
): AttemptView {
  const explicitRecordPath = pickFirst(
    entry.recordPath,
    entry.record_file,
    entry.recordJson,
    entry.record,
    entry.recordPathRelative,
  );

  const explicitRequestPath = pickFirst(
    entry.requestPath,
    entry.request_file,
    entry.requestJson,
    entry.request,
  );

  const explicitReplyPath = pickFirst(
    entry.replyPath,
    entry.reply_file,
    entry.replyJson,
    entry.reply,
  );

  const explicitValidationPath = pickFirst(
    entry.validationPath,
    entry.validation_file,
    entry.validationJson,
    entry.validation,
  );

  const caseDir = path.join(
    runDir,
    path.dirname(
      explicitRecordPath ||
        toText(pickFirst(entry.caseDir, entry.case_id, entry.caseID), "."),
    ),
  );

  const recordPath =
    resolveIfExists(runDir, explicitRecordPath) ||
    resolveIfExists(runDir, path.join(entry.caseDir || "", "record.json")) ||
    resolveIfExists(
      runDir,
      path.join(path.basename(path.dirname(caseDir)), "record.json"),
    ) ||
    path.join(caseDir, "record.json");

  const requestPath =
    resolveIfExists(runDir, explicitRequestPath) ||
    resolveIfExists(caseDir, "request.json") ||
    resolveIfExists(caseDir, "prompt.json") ||
    resolveIfExists(
      runDir,
      path.join(path.relative(runDir, caseDir), "request.json"),
    );
  const replyPath =
    resolveIfExists(runDir, explicitReplyPath) ||
    resolveIfExists(caseDir, "reply.json") ||
    resolveIfExists(
      runDir,
      path.join(path.relative(runDir, caseDir), "reply.json"),
    );
  const validationPath =
    resolveIfExists(runDir, explicitValidationPath) ||
    resolveIfExists(caseDir, "validation.json") ||
    resolveIfExists(
      runDir,
      path.join(path.relative(runDir, caseDir), "validation.json"),
    );

  const recordRes: ReadResult<RecordDocument> = existsFile(recordPath)
    ? readJSON(recordPath, recordDocumentSchema)
    : {
        ok: false,
        value: null,
        path: recordPath,
        missing: true,
        error: "缺失 record.json",
      };
  const requestRes: ReadResult<RequestDocument> = requestPath
    ? readJSON(requestPath, requestDocumentSchema)
    : {
        ok: false,
        value: null,
        path: path.join(caseDir, "request.json"),
        missing: true,
        error: "缺失 request.json",
      };
  const replyRes: ReadResult<ReplyDocument> = replyPath
    ? readJSON(replyPath, replyDocumentSchema)
    : {
        ok: false,
        value: null,
        path: path.join(caseDir, "reply.json"),
        missing: true,
        error: "缺失 reply.json",
      };
  const validationRes: ReadResult<ProtocolDocument> = validationPath
    ? readJSON(validationPath, protocolSchema)
    : {
        ok: false,
        value: null,
        path: path.join(caseDir, "validation.json"),
        missing: true,
        error: "缺失 validation.json",
      };

  if (!recordRes.ok) report.missing.push(recordRes.error + `: ${recordPath}`);
  if (!requestRes.ok)
    report.missing.push(
      requestRes.error + `: ${requestPath || `${caseDir}/request.json`}`,
    );
  if (!replyRes.ok)
    report.missing.push(
      replyRes.error + `: ${replyPath || `${caseDir}/reply.json`}`,
    );
  if (!validationRes.ok)
    report.missing.push(
      validationRes.error +
        `: ${validationPath || `${caseDir}/validation.json`}`,
    );

  const record = recordRes.value ?? recordDocumentSchema.parse({});
  const request = requestRes.value ?? requestDocumentSchema.parse({});
  const reply = replyRes.value ?? replyDocumentSchema.parse({});
  const validation = validationRes.value ?? protocolSchema.parse({});

  const caseSnapshot =
    pickFirst(
      record.caseSnapshot,
      entry.caseSnapshot,
      request.caseSnapshot,
      {},
    ) || {};
  const shapeDecision =
    pickFirst(record.shapeDecision, request.shapeDecision, {}) || {};
  const exprPlan =
    pickFirst(record.expressionPlan, request.expressionPlan, {}) || {};
  const sourceBinding =
    pickFirst(record.sourceBinding, request.sourceBinding, {}) || {};
  const repair =
    pickFirst(record.repairAndRetest, request.repairAndRetest, {}) || {};
  const toolProtocol =
    pickFirst(record.toolAndProtocolValidation, validation, {}) || {};

  const t1Programs = exprPlan.t1Programs ?? [];
  const t2Compositions = exprPlan.t2Compositions ?? [];

  const caseID = toText(
    pickFirst(
      entry.caseID,
      entry.case_id,
      caseSnapshot.caseID,
      caseSnapshot.id,
      caseSnapshot.caseId,
      "unknown",
    ),
    "unknown",
  );
  const repetition = Number(
    entry.repetition ??
      entry.round ??
      entry.roundIndex ??
      record.repetition ??
      record.round ??
      1,
  );

  const screens = collectScreenshots(caseDir, report, copiedAssets);
  const question = toText(
    pickFirst(
      entry.question,
      caseSnapshot.question,
      request.question,
      request.prompt,
      record.question,
      "未定义题目",
    ),
    "未定义题目",
  );

  const status = toText(
    pickFirst(
      entry.status,
      record.status,
      record.state,
      toolProtocol.status,
      "unknown",
    ),
    "unknown",
  );

  const elapsedSeconds = pickFirst(
    record.elapsedSeconds,
    record.duration,
    entry.elapsedSeconds,
    0,
  );
  const elapsed = toNumber(elapsedSeconds);

  const missingFields: string[] = [];
  if (!requestRes.ok) missingFields.push("request.json");
  if (!replyRes.ok) missingFields.push("reply.json");
  if (!validationRes.ok) missingFields.push("validation.json");
  if (!recordRes.ok) missingFields.push("record.json");
  if (screens.before === null) missingFields.push("before截图");
  if (screens.after === null) missingFields.push("after截图");
  if (toText(request.selectionText, "") === "缺失")
    missingFields.push("selectionText");

  return {
    caseID,
    repetition: Number.isFinite(repetition) ? repetition : 0,
    caseKind: normalizeKind(
      pickFirst(
        entry.caseKind,
        caseSnapshot.caseKind,
        record.caseKind,
        shapeDecision.caseKind,
        "rich",
      ),
    ),
    subject: toText(
      pickFirst(
        entry.subject,
        caseSnapshot.subject,
        request.subject,
        record.subject,
        "未定义学科",
      ),
      "未定义学科",
    ),
    question,
    materialTitle: toText(
      pickFirst(
        caseSnapshot.materialTitle,
        request.materialTitle,
        "未定义材料",
      ),
      "未定义材料",
    ),
    materialKind: toText(
      pickFirst(
        caseSnapshot.materialKind,
        request.materialKind,
        "未定义材料类型",
      ),
      "未定义材料类型",
    ),
    materialText: toText(
      pickFirst(
        caseSnapshot.materialText,
        request.materialText,
        entry.materialText,
        "未提供",
      ),
      "未提供",
    ),
    selectionTitle: toText(
      pickFirst(
        caseSnapshot.selectionTitle,
        request.selectionTitle,
        entry.selectionTitle,
        "未定义选区",
      ),
      "未定义选区",
    ),
    selectionText: toText(
      pickFirst(
        caseSnapshot.selectionText,
        request.selectionText,
        entry.selectionText,
        "未定义选区内容",
      ),
      "未定义选区内容",
    ),
    status,
    elapsedSeconds: elapsed,
    elapsedDisplay: elapsed === null ? "缺失" : `${elapsed}s`,
    preferredShape: toText(shapeDecision.preferredShape, "缺失"),
    actualShape: toText(shapeDecision.actualShape, "缺失"),
    expectedShape: toText(shapeDecision.expectedShape, "缺失"),
    directManipulation: boolText(shapeDecision.directManipulation),
    expressionPlan: {
      t1SceneCount: t1Programs.length,
      t2SceneCount: t2Compositions.length,
      t1Programs: t1Programs.map((item) => ({
        sceneID: toText(item.sceneID, "缺失"),
        family: toText(item.family, "缺失"),
        version: toText(item.version, "缺失"),
        maxHeight: toNumber(item.maxHeight),
        directManipulation: boolText(item.directManipulation),
        componentNames: Array.isArray(item.componentNames)
          ? item.componentNames
          : [],
      })),
      t2Compositions: t2Compositions.map((item) => ({
        sceneID: toText(item.sceneID, "缺失"),
        family: toText(item.family, "缺失"),
        rootID: toText(item.rootID, "缺失"),
        roles: Array.isArray(item.roles) ? item.roles : [],
        nodeCount: toNumber(item.nodeCount) || 0,
        dataRowCount: toNumber(item.dataRowCount) || 0,
      })),
    },
    protocol: {
      status: toText(toolProtocol.status, "缺失"),
      validationKind: toText(toolProtocol.validationKind, "缺失"),
      passedChecks: Array.isArray(toolProtocol.passedChecks)
        ? toolProtocol.passedChecks
        : [],
      issues: Array.isArray(toolProtocol.issues) ? toolProtocol.issues : [],
      protocolDiagnostics: Array.isArray(toolProtocol.protocolDiagnostics)
        ? toolProtocol.protocolDiagnostics
        : [],
    },
    sourceBinding: {
      textSourceLabels: Array.isArray(sourceBinding.textSourceLabels)
        ? sourceBinding.textSourceLabels
        : [],
      evidenceLedgerLabels: Array.isArray(sourceBinding.evidenceLedgerLabels)
        ? sourceBinding.evidenceLedgerLabels
        : [],
      sceneEvidenceIDs: Array.isArray(sourceBinding.sceneEvidenceIDs)
        ? sourceBinding.sceneEvidenceIDs
        : [],
      evidenceState: toText(sourceBinding.evidenceState, "缺失"),
      hasExpectedSource: sourceBinding.hasExpectedSource === true,
    },
    rawRequest: (() => {
      try {
        return JSON.stringify(request, null, 2);
      } catch {
        return "缺失";
      }
    })(),
    rawReply: {
      backend: toText(reply.backend, "缺失"),
      text: toText(reply.text, "缺失"),
      hasRichAnswer: reply.richAnswer ? "有" : "无",
      json: (() => {
        try {
          return JSON.stringify(reply, null, 2);
        } catch {
          return "缺失";
        }
      })(),
    },
    rawValidation: (() => {
      try {
        return JSON.stringify(validation, null, 2);
      } catch {
        return "缺失";
      }
    })(),
    failureReason: toText(repair.failureReason, "无"),
    repair: {
      previousRunID: toText(repair.previousRunID, "缺失"),
      previousStatus: toText(repair.previousStatus, "缺失"),
      repairNote: toText(repair.repairNote, "缺失"),
      isRetest: boolText(repair.isRetest),
    },
    beforeImage: screens.before,
    afterImage: screens.after,
    missingFields,
    missingScreenshotFields: screens.missing,
  };
}

/** 从 run 目录读取元数据和全部尝试记录。 */
function collectRecords(
  runDir: string,
  report: BuildReport,
  copiedAssets: CopiedAssets,
): CollectedRecords {
  const runRes = readJSON(path.join(runDir, "run.json"), runDocumentSchema);
  const indexRes = readJSON(
    path.join(runDir, "index.json"),
    indexDocumentSchema,
  );
  if (!runRes.ok)
    report.missing.push(
      `run.json 读取失败：${path.join(runDir, "run.json")}：${runRes.error}`,
    );
  if (!indexRes.ok)
    report.missing.push(
      `index.json 读取失败：${path.join(runDir, "index.json")}：${indexRes.error}`,
    );

  const indexJson = indexRes.value ?? indexDocumentSchema.parse({});
  const records: AttemptView[] = [];

  if (indexJson.records && indexJson.records.length > 0) {
    for (const entry of indexJson.records) {
      records.push(collectAttempt(entry, runDir, report, copiedAssets));
    }
  } else {
    const dirs = existsDir(runDir)
      ? fs.readdirSync(runDir, { withFileTypes: true })
      : [];
    for (const d of dirs) {
      if (!d.isDirectory() || !d.name.startsWith("repetition-")) continue;
      const repDir = path.join(runDir, d.name);
      const repMatch = d.name.match(/repetition-(\d+)/);
      const repetition = repMatch ? Number(repMatch[1]) : 1;
      const caseDirs = fs.readdirSync(repDir, { withFileTypes: true });
      for (const c of caseDirs) {
        if (!c.isDirectory()) continue;
        records.push(
          collectAttempt(
            {
              repetition,
              caseID: c.name,
              caseDir: path.join(repDir, c.name),
              recordPath: path.join(repDir, c.name, "record.json"),
            },
            runDir,
            report,
            copiedAssets,
          ),
        );
      }
    }
  }

  return {
    runMeta: runRes.value ?? runDocumentSchema.parse({}),
    indexMeta: indexJson,
    records,
  };
}

/** 按 caseID 聚合并排序尝试记录。 */
function groupCases(records: AttemptView[]): CaseGroup[] {
  const map = new Map<
    string,
    Omit<
      CaseGroup,
      | "question"
      | "materialTitle"
      | "materialKind"
      | "selectionTitle"
      | "rounds"
      | "latestAttempt"
      | "acceptState"
    >
  >();

  for (const attempt of records) {
    const id = attempt.caseID;
    if (!map.has(id)) {
      map.set(id, {
        caseID: id,
        subject: attempt.subject,
        caseKind: attempt.caseKind,
        attempts: [],
      });
    }
    const group = map.get(id);
    if (!group) continue;
    group.attempts.push(attempt);
  }

  const cases: CaseGroup[] = [];
  for (const group of map.values()) {
    group.attempts.sort((a, b) => {
      if (a.repetition !== b.repetition) return a.repetition - b.repetition;
      return a.caseID.localeCompare(b.caseID);
    });
    const firstAttempt = group.attempts[0];
    const latestAttempt = group.attempts[group.attempts.length - 1];
    if (!firstAttempt || !latestAttempt) continue;
    cases.push({
      ...group,
      question: firstAttempt.question,
      materialTitle: firstAttempt.materialTitle,
      materialKind: firstAttempt.materialKind,
      selectionTitle: firstAttempt.selectionTitle,
      rounds: group.attempts.map((item) => String(item.repetition)),
      latestAttempt,
      acceptState: latestAttempt.status === "passed" ? "已通过" : "待用户验收",
    });
  }

  cases.sort((a, b) => {
    if (a.subject !== b.subject)
      return String(a.subject).localeCompare(String(b.subject));
    return String(a.caseID).localeCompare(String(b.caseID));
  });

  return cases;
}

/** 汇总离线验收包的计数和筛选选项。 */
function buildOverview(
  cases: CaseGroup[],
  runMeta: RunDocument,
  report: BuildReport,
): Overview {
  const countsByKind: Record<string, number> = {
    rich: 0,
    "text-only": 0,
    degradation: 0,
    "invalid-protocol": 0,
    unknown: 0,
  };
  const statusCount: Record<string, number> = {};
  const subjects = new Set<string>();
  const shapes = new Set<string>();
  const repetitions = new Set<string>();

  for (const group of cases) {
    const kind = group.caseKind || "rich";
    countsByKind[kind] = (countsByKind[kind] || 0) + 1;
    subjects.add(group.subject || "未定义学科");
    const latest = group.latestAttempt || {};
    statusCount[latest.status || "unknown"] =
      (statusCount[latest.status || "unknown"] || 0) + 1;

    for (const attempt of group.attempts) {
      shapes.add(attempt.actualShape || "缺失");
      repetitions.add(String(attempt.repetition));
    }
  }

  const missingByKind = Object.entries(TARGET_BREAKDOWN).map(
    ([kind, target]) => {
      const actual = countsByKind[kind] || 0;
      return {
        kind,
        target,
        actual,
        gap: target - actual,
        pass: actual >= target,
      };
    },
  );

  return {
    totalExpected: TARGET_TOTAL,
    totalActual: cases.length,
    totalGap: TARGET_TOTAL - cases.length,
    expectedByKind: TARGET_BREAKDOWN,
    actualByKind: countsByKind,
    missingByKind,
    filterOptions: {
      subjects: Array.from(subjects).sort(),
      statuses: Object.keys(statusCount).sort(),
      shapes: Array.from(shapes).sort(),
      repetitions: Array.from(repetitions).sort(
        (a, b) => Number(a) - Number(b),
      ),
    },
    statusCount,
    subjectCount: subjects.size,
    runCreatedAt: toText(runMeta.createdAt, "缺失"),
    runId: toText(
      runMeta.runID,
      path.basename(toText(runMeta.rootPath, "unknown-run")),
    ),
    retestOfRunID: toText(runMeta.retestOfRunID, "无"),
    completionState:
      cases.length >= TARGET_TOTAL
        ? "待用户验收（需人工复核）"
        : "待用户验收（未达56场）",
    missingMandatoryCount: report.missing.length,
  };
}

/** 转义服务端 HTML 插值。 */
function escapeHtml(input: unknown): string {
  return String(input || "").replace(
    /[&<>"']/g,
    (char) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      })[char] ?? char,
  );
}

/** 构造离线验收页面 HTML。 */
function buildIndexHTML(payload: EvidencePayload, overview: Overview): string {
  const css = `
    :root { --paper:#f4f0e4; --paper-soft:#fbf8f1; --ink:#302716; --line:#d5ccbe; --ok:#2e7c50; --warn:#8c4e2f; --ink-soft:#5b4e3b; }
    * { box-sizing:border-box; }
    body { margin:0; padding:20px; background: var(--paper); color:var(--ink); font-family: "PingFang SC","Noto Serif SC","Microsoft YaHei", serif; line-height:1.52; }
    .wrap { max-width: 1280px; margin:0 auto; }
    .title { border-bottom: 1px solid var(--line); padding-bottom: 10px; margin-bottom: 10px; }
    .title h1 { margin:0; font-size: 30px; }
    .panel { border: 1px solid var(--line); background: var(--paper-soft); padding: 12px; margin-top: 10px; }
    h2 { margin:0 0 10px; font-size:19px; }
    .muted { color:var(--ink-soft); font-size:13px; }
    .overview-grid { display:grid; grid-template-columns: repeat(3,minmax(0,1fr)); gap: 8px; }
    .summary-table,.diff-table { width:100%; border-collapse: collapse; }
    .summary-table th,.summary-table td,.diff-table th,.diff-table td { border:1px solid var(--line); padding: 7px; font-size:13px; }
    .summary-table th { background:#efe7d6; }
    .filters { display:grid; grid-template-columns: repeat(4,minmax(0,1fr)); gap:8px; }
    .filters select, #filter-keyword { width:100%; border:1px solid var(--line); padding:8px; background:#fff; }
    #filter-keyword { margin-top:8px; }
    .badge { border:1px solid var(--line); padding:2px 8px; font-size:12px; margin-right:6px; }
    .ok { border-color:#bed5c6; background:#edf7ec; color:var(--ok); }
    .warn { border-color:#e3c8a5; background:#fff3dd; color:var(--warn); }
    .case-card { margin-top:10px; border:1px solid var(--line); padding: 10px; background:#fffef7; }
    .case-head { display:flex; justify-content:space-between; align-items:center; gap:8px; flex-wrap:wrap; }
    .badges { display:flex; gap:6px; flex-wrap:wrap; margin-top:8px; }
    details { margin-top: 8px; }
    .code { border:1px solid var(--line); background:#f8f5ec; padding:8px; white-space:pre-wrap; max-height:280px; overflow:auto; }
    .img-grid { display:grid; grid-template-columns: repeat(2,minmax(0,1fr)); gap:8px; margin-top:8px; }
    .img-item { border:1px dashed var(--line); background:#fff; padding:6px; text-align:center; }
    .img-item img { max-width:100%; max-height:220px; display:block; margin:0 auto; background:#eee; }
    .pill { border:1px solid var(--line); padding:2px 8px; }
    .diff { border-top:1px dashed var(--line); margin-top:8px; padding-top:8px; }
    .missing-list li { margin: 4px 0; }
    .block-empty { color: var(--warn); padding: 6px; }
    @media (max-width: 980px) {
      .overview-grid, .filters { grid-template-columns: 1fr; }
    }
  `;

  const kindRows = overview.missingByKind
    .map(
      (row) => `
    <tr>
      <td>${escapeHtml(row.kind)}</td>
      <td>${row.target}</td>
      <td>${row.actual}</td>
      <td>${row.gap}</td>
      <td>${row.pass ? "达标" : "不足"}</td>
    </tr>`,
    )
    .join("");

  const statusRows = Object.entries(overview.statusCount)
    .map(([k, v]) => `<li>${escapeHtml(k)}：${escapeHtml(v)}</li>`)
    .join("");

  const missingRows = payload.missing
    .slice(0, 120)
    .map((item) => `<li>${escapeHtml(item)}</li>`)
    .join("");

  const statusOptions = ['<option value="__all">全部状态</option>']
    .concat(
      (overview.filterOptions.statuses || []).map(
        (item) =>
          `<option value="${escapeHtml(item)}">${escapeHtml(item)}</option>`,
      ),
    )
    .join("");

  const subjectOptions = ['<option value="__all">全部学科</option>']
    .concat(
      (overview.filterOptions.subjects || []).map(
        (item) =>
          `<option value="${escapeHtml(item)}">${escapeHtml(item)}</option>`,
      ),
    )
    .join("");

  const shapeOptions = ['<option value="__all">全部形态</option>']
    .concat(
      (overview.filterOptions.shapes || []).map(
        (item) =>
          `<option value="${escapeHtml(item)}">${escapeHtml(item)}</option>`,
      ),
    )
    .join("");

  const repetitionOptions = ['<option value="__all">全部轮次</option>']
    .concat(
      (overview.filterOptions.repetitions || []).map(
        (item) =>
          `<option value="${escapeHtml(item)}">第${escapeHtml(item)}轮</option>`,
      ),
    )
    .join("");

  const payloadScript = `window.__EVIDENCE_DATA__ = ${JSON.stringify(payload).replace(/<\//g, "<\\/")};`;

  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>富回答56题验收包（离线）</title>
  <style>${css}</style>
</head>
<body>
  <div class="wrap">
    <div class="title">
      <h1>富回答验收包 · 离线浏览器</h1>
      <div class="muted">run目录：${escapeHtml(payload.runDir)}</div>
      <div class="muted">说明：本包为离线复核展示，不替代真实执行；真实验收仍需用户确认。未跑真实56题时不得标记完成。</div>
      <div class="muted">状态：${escapeHtml(overview.completionState)}</div>
    </div>

    <section class="panel">
      <h2>验收总览</h2>
      <div class="overview-grid">
        <div>runID：${escapeHtml(overview.runId)}</div>
        <div>目标：40 + 6 + 9 + 1 = ${overview.totalExpected}</div>
        <div>实际用例：${overview.totalActual}</div>
        <div>缺口：${overview.totalGap}</div>
        <div>创建时间：${escapeHtml(overview.runCreatedAt)}</div>
        <div>学科数：${overview.subjectCount}</div>
        <div>状态汇总：<span class="pill">${Object.entries(overview.statusCount)
          .map(([k, v]) => `${k}:${v}`)
          .join(" / ")}</span></div>
      </div>
      <table class="summary-table">
        <thead>
          <tr><th>维度</th><th>应有</th><th>实际</th><th>差值</th><th>判定</th></tr>
        </thead>
        <tbody>
          ${kindRows}
          <tr>
            <td>总计</td>
            <td>${overview.totalExpected}</td>
            <td>${overview.totalActual}</td>
            <td>${overview.totalGap}</td>
            <td>${overview.totalActual >= overview.totalExpected ? "达标" : "不足"}</td>
          </tr>
        </tbody>
      </table>
    </section>

    <section class="panel">
      <h2>缺失字段（不得伪造）</h2>
      <ul class="missing-list">${missingRows || "<li>无关键缺失</li>"}</ul>
    </section>

    <section class="panel">
      <h2>过滤器：状态 / 学科 / 形态 / 轮次</h2>
      <div class="filters">
        <select id="filter-status">${statusOptions}</select>
        <select id="filter-subject">${subjectOptions}</select>
        <select id="filter-shape">${shapeOptions}</select>
        <select id="filter-repetition">${repetitionOptions}</select>
      </div>
      <input id="filter-keyword" type="text" placeholder="关键词搜索（题目 / caseID）" />
    </section>

    <section class="panel">
      <h2>每题逐条验收（含三轮差异）</h2>
      <div id="case-list"></div>
    </section>
  </div>
  <script>${payloadScript}</script>
  <script src="viewer.js"></script>
</body>
</html>`;
}

/** 构造无需额外依赖的浏览器端运行脚本。 */
function buildViewerJS(): string {
  return [
    "(function(){",
    "  const data = window.__EVIDENCE_DATA__ || {};",
    "  const cases = Array.isArray(data.cases) ? data.cases : [];",
    '  const filterStatus = document.getElementById("filter-status");',
    '  const filterSubject = document.getElementById("filter-subject");',
    '  const filterShape = document.getElementById("filter-shape");',
    '  const filterRep = document.getElementById("filter-repetition");',
    '  const filterKw = document.getElementById("filter-keyword");',
    '  const listEl = document.getElementById("case-list");',
    "  function esc(v) {",
    '    return String(v || "").replace(/[&<>\"\\x27]/g, function(ch) {',
    '      if (ch === "&") return "&amp;";',
    '      if (ch === "<") return "&lt;";',
    '      if (ch === ">") return "&gt;";',
    '      if (ch === "\"") return "&quot;";',
    '      if (ch === "\'") return "&#39;";',
    "      return ch;",
    "    });",
    "  }",
    "  function code(v) {",
    '    return "<pre class=\"code\">" + esc(v || "") + "</pre>";',
    "  }",
    "  function img(label, src) {",
    "    if (src) {",
    '      return "<div class=\"img-item\"><div>" + esc(label) + "</div><img src=\"" + esc(src) + "\" alt=\"" + esc(label) + "\" loading=\"lazy\" /></div>";',
    "    }",
    '    return "<div class=\"img-item\">" + esc(label) + "：缺失</div>";',
    "  }",
    "  function listText(items, emptyText) {",
    '    if (!items || !items.length) return "<li>" + esc(emptyText) + "</li>";',
    '    return items.map(function(i){ return "<li>" + esc(i) + "</li>"; }).join("");',
    "  }",
    "  function diffRows(attempts) {",
    '    if (!attempts || attempts.length < 2) return "";',
    '    var rows = "";',
    "    for (var i = 1; i < attempts.length; i += 1) {",
    "      var p = attempts[i - 1];",
    "      var c = attempts[i];",
    "      var d = (Number(c.elapsedSeconds) || 0) - (Number(p.elapsedSeconds) || 0);",
    '      rows += "<tr><td>第" + esc(p.repetition) + "→第" + esc(c.repetition) + "轮</td><td>" + esc(p.status) + "→" + esc(c.status) + "</td><td>" + esc(p.actualShape) + "→" + esc(c.actualShape) + "</td><td>" + ((d >= 0 ? "+" : "") + d.toFixed(3) + "s") + "</td><td>" + esc(c.failureReason || "无") + "</td></tr>";',
    "    }",
    '    return "<div class=\"diff\"><table class=\"diff-table\"><thead><tr><th>轮次</th><th>状态</th><th>形态</th><th>耗时差</th><th>失败原因</th></tr></thead><tbody>" + rows + "</tbody></table></div>";',
    "  }",
    "  function attemptBlock(attempt) {",
    '    var proto = "<div class=\"case-card\" style=\"border-left:4px solid #b38c50\">";',
    '    var badge = attempt.status === "passed" ? "ok" : "warn";',
    '    proto += "<div class=\"case-head\"><strong>第" + esc(attempt.repetition) + "轮</strong><span class=\"badge \" + badge + "\">" + esc(attempt.status) + "</span></div>";',
    '    proto += "<div class=\"badges\"><span class=\"badge\">形态：" + esc(attempt.actualShape) + "</span><span class=\"badge\">T1:" + esc(attempt.expressionPlan.t1SceneCount || 0) + " / T2:" + esc(attempt.expressionPlan.t2SceneCount || 0) + "</span><span class=\"badge\">耗时：" + esc(attempt.elapsedDisplay) + "</span><span class=\"badge\">直观交互：" + esc(attempt.directManipulation) + "</span></div>";',
    '    proto += "<div class=\"badges\"><span class=\"badge \" + (attempt.missingFields.length ? "warn" : "ok") + "\">缺失字段：" + esc((attempt.missingFields.length ? attempt.missingFields.join("、") : "无")) + "</span></div>";',
    '    proto += "<details><summary>题目与材料</summary><p>" + esc(attempt.question || "") + "</p><p>材料：" + esc(attempt.materialTitle || "") + " / " + esc(attempt.materialKind || "") + " / " + esc(attempt.selectionTitle || "") + "</p><div class=\"code\">" + esc(attempt.materialText || "") + "</div><div>" + esc(attempt.selectionText || "") + "</div></details>";',
    '    proto += "<details><summary>原始回复</summary><p>backend：" + esc(attempt.rawReply.backend || "") + " / richAnswer：" + esc(attempt.rawReply.hasRichAnswer || "") + "</p>" + code(attempt.rawReply.text || "") + "</details>";',
    '    proto += "<details><summary>T1 / T2 计划</summary><div>expressionPlan</div>" + code(attempt.expressionPlan && (attempt.expressionPlan.t1SceneCount || 0) + " 个 T1, " + (attempt.expressionPlan.t2SceneCount || 0) + " 个 T2") + "<div>T1</div><ul>" + (attempt.expressionPlan.t1Programs || []).map(function(i){ return "<li>" + esc(i.sceneID || "") + "/" + esc(i.family || "") + "/" + esc(i.version || "") + "</li>"; }).join("") + "</ul><div>T2</div><ul>" + (attempt.expressionPlan.t2Compositions || []).map(function(i){ return "<li>" + esc(i.sceneID || "") + "/" + esc(i.family || "") + "/nodes " + esc(i.nodeCount || 0) + "/rows " + esc(i.dataRowCount || 0) + "</li>"; }).join("") + "</ul></details>";',
    '    proto += "<details><summary>协议来源</summary><p>protocol：" + esc(attempt.protocol.validationKind || "") + " / " + esc(attempt.protocol.status || "") + "</p>" + code((attempt.rawValidation || "")) + "</details>";',
    '    proto += "<details><summary>源码绑定</summary><p>textSource：" + esc((attempt.sourceBinding.textSourceLabels || []).join("、")) + "</p><p>ledger：" + esc((attempt.sourceBinding.evidenceLedgerLabels || []).join("、")) + "</p><p>sceneIDs：" + esc((attempt.sourceBinding.sceneEvidenceIDs || []).join("、")) + "</p><p>expected：" + esc(attempt.sourceBinding.hasExpectedSource ? "是" : "否") + "</p>" + code(attempt.rawRequest || "") + "</details>";',
    '    proto += "<div class=\"img-grid\">" + img("操作前", attempt.beforeImage) + img("操作后", attempt.afterImage) + "</div>";',
    '    proto += "</div>";',
    "    return proto;",
    "  }",
    "  function toList(filters) {",
    "    var rows = [];",
    "    for (var i = 0; i < cases.length; i += 1) {",
    "      var item = cases[i];",
    "      var attempts = item.attempts.filter(function (attempt) {",
    '        if (filters.status !== "__all" && attempt.status !== filters.status) return false;',
    '        if (filters.subject !== "__all" && item.subject !== filters.subject) return false;',
    '        if (filters.shape !== "__all" && attempt.actualShape !== filters.shape) return false;',
    '        if (filters.repetition !== "__all" && String(attempt.repetition) !== String(filters.repetition)) return false;',
    "        if (filters.keyword) {",
    "          var keys = [item.caseID, item.question, item.subject, attempt.question, attempt.selectionTitle];",
    "          var ok = keys.some(function (k) {",
    '            return String(k || "").toLowerCase().indexOf(filters.keyword) !== -1;',
    "          });",
    "          if (!ok) return false;",
    "        }",
    "        return true;",
    "      });",
    "      if (attempts.length === 0) continue;",
    '      var block = "<article class=\"case-card\"><div class=\"case-head\"><strong>" + esc(item.caseID) + "</strong><span class=\"badge\">学科：" + esc(item.subject || "") + "</span><span class=\"badge\">类型：" + esc(item.caseKind || "") + "</span><span class=\"badge\">轮次：" + esc((item.rounds || []).join("、")) + "</span></div>" + "<div class=\"badges\"><span class=\"badge \" + (item.acceptState === "已通过" ? "ok" : "warn") + "\">" + esc(item.acceptState || "") + "</span><span class=\"badge\">题目：" + esc(item.question || "") + "</span></div>" + "<div class=\"code\">" + esc(item.materialTitle || "") + " / " + esc(item.materialKind || "") + " / " + esc(item.selectionTitle || "") + "</div>" + diffRows(attempts) + buildAttempts(attempts) + "</article>";',
    "      rows.push(block);",
    "    }",
    '    listEl.innerHTML = rows.length ? rows.join("") : "<div class=\"block-empty\">当前筛选下无结果</div>";',
    "  }",
    "  function buildAttempts(attempts) {",
    '    return attempts.map(function (attempt) { return attemptBlock(attempt); }).join("");',
    "  }",
    "  function filters() {",
    "    return {",
    "      status: filterStatus.value,",
    "      subject: filterSubject.value,",
    "      shape: filterShape.value,",
    "      repetition: filterRep.value,",
    '      keyword: (filterKw.value || "").trim().toLowerCase(),',
    "    };",
    "  }",
    "  function render() {",
    "    toList(filters());",
    "  }",
    '  filterStatus && filterStatus.addEventListener("change", render);',
    '  filterSubject && filterSubject.addEventListener("change", render);',
    '  filterShape && filterShape.addEventListener("change", render);',
    '  filterRep && filterRep.addEventListener("change", render);',
    '  filterKw && filterKw.addEventListener("input", render);',
    "  render();",
    "})();",
  ].join("\n");
}

/** 写入离线验收包的 HTML、脚本和数据文件。 */
function writePackage(outputDir: string, payload: EvidencePayload): void {
  ensureDir(outputDir);
  ensureDir(path.join(outputDir, "assets"));
  ensureDir(path.join(outputDir));

  const indexHtml = buildIndexHTML(payload, payload.overview);
  const viewerJS = buildViewerJS();

  fs.writeFileSync(path.join(outputDir, "index.html"), indexHtml, "utf8");
  fs.writeFileSync(path.join(outputDir, "viewer.js"), viewerJS, "utf8");
  fs.writeFileSync(
    path.join(outputDir, "data.json"),
    JSON.stringify(payload, null, 2),
    "utf8",
  );
}

/** 执行离线验收包生成命令。 */
function run(): void {
  const argv = parseArgs();
  if (argv.help || (!argv.runDir && !argv.runId)) {
    console.log(usage());
    return;
  }

  const runDir = argv.runDir
    ? path.resolve(argv.runDir)
    : path.resolve(argv.source, argv.runId!);
  if (!existsDir(runDir)) throw new Error(`run目录不存在：${runDir}`);

  const output = argv.output
    ? path.resolve(argv.output)
    : path.join(
        process.cwd(),
        `rich-answer-evidence-viewer-${path.basename(runDir)}`,
      );
  if (existsDir(output)) {
    if (!argv.force) throw new Error(`输出目录已存在：${output}`);
    fs.rmSync(output, { force: true, recursive: true });
  }
  ensureDir(output);

  const report: BuildReport = {
    missing: [],
    copied: { count: 0, dir: path.join(output, "assets"), runDir },
  };
  const recordsData = collectRecords(runDir, report, report.copied);
  const cases = groupCases(recordsData.records);
  const overview = buildOverview(cases, recordsData.runMeta || {}, report);

  const payload = {
    generatedAt: new Date().toISOString(),
    runDir,
    runId: overview.runId,
    runMeta: recordsData.runMeta,
    indexMeta: recordsData.indexMeta,
    overview,
    cases,
    missing: Array.from(new Set(report.missing)),
    copiedImages: report.copied.count,
  };

  writePackage(output, payload);

  console.log("离线验收包已生成：");
  console.log(`runDir: ${runDir}`);
  console.log(`output: ${output}`);
  console.log(`cases: ${overview.totalActual} / ${overview.totalExpected}`);
  console.log(`missingCount: ${payload.missing.length}`);
  console.log(`copiedImages: ${payload.copiedImages}`);
  console.log(`completionState: ${overview.completionState}`);
}

run();
