#!/usr/bin/env -S npm exec -- tsx
/// <reference lib="dom" />

import fs from "node:fs";
import path from "node:path";
import { z } from "zod/v4";
import { parseEvidenceJson } from "./evidence-json.js";

type AssetMode = "copy" | "hardlink" | "symlink";

const displayValueSchema = z.union([
  z.string(),
  z.number(),
  z.boolean(),
  z.null(),
]);
const screenshotSchema = z.union([
  z.string(),
  z.object({ path: z.string() }).passthrough(),
  z.null(),
]);
const repairEvidenceSchema = z
  .object({ manifestPath: z.string().optional() })
  .passthrough();
const indexEntrySchema = z
  .object({
    runID: displayValueSchema.optional(),
    repetition: displayValueSchema.optional(),
    sequence: displayValueSchema.optional(),
    caseID: displayValueSchema.optional(),
    caseKind: displayValueSchema.optional(),
    status: displayValueSchema.optional(),
    recordPath: z.string().optional(),
    failureReason: displayValueSchema.optional(),
    screenshots: z.record(z.string(), screenshotSchema).optional(),
    repairEvidence: repairEvidenceSchema.optional(),
    screenshotManifest: z.string().optional(),
    originalScreenshotStatus: displayValueSchema.optional(),
    screenshotStatus: displayValueSchema.optional(),
    qualityStatus: displayValueSchema.optional(),
  })
  .passthrough();
const runMetadataSchema = z
  .object({
    runID: displayValueSchema.optional(),
    rootPath: displayValueSchema.optional(),
    createdAt: displayValueSchema.optional(),
    retestOfRunID: displayValueSchema.optional(),
    repairNote: displayValueSchema.optional(),
    continueAfterFailure: displayValueSchema.optional(),
    requestedIDs: z.array(z.json()).optional(),
    filters: z.array(z.json()).optional(),
  })
  .passthrough();
const indexSchema = z
  .object({ records: z.array(indexEntrySchema).optional() })
  .passthrough();
const requestSchema = z
  .object({
    materialTitle: displayValueSchema.optional(),
    materialKind: displayValueSchema.optional(),
    materialText: displayValueSchema.optional(),
    selectionTitle: displayValueSchema.optional(),
    selectionText: displayValueSchema.optional(),
    workflow: displayValueSchema.optional(),
    resolvedWorkflow: displayValueSchema.optional(),
    materialIsTruncated: displayValueSchema.optional(),
    contextRevision: displayValueSchema.optional(),
  })
  .passthrough();
const validationSchema = z
  .object({
    status: displayValueSchema.optional(),
    validationKind: displayValueSchema.optional(),
    passedChecks: z.array(z.json()).optional(),
    issues: z.array(z.json()).optional(),
    protocolDiagnostics: z.array(z.json()).optional(),
    toolTrace: z.array(z.json()).optional(),
  })
  .passthrough();
const replySchema = z
  .object({
    text: displayValueSchema.optional(),
    backend: displayValueSchema.optional(),
    toolTrace: z.array(z.json()).optional(),
    richAnswer: z.json().optional(),
  })
  .passthrough();
const t1ProgramSchema = z
  .object({
    sceneID: displayValueSchema.optional(),
    family: displayValueSchema.optional(),
    version: displayValueSchema.optional(),
    maxHeight: displayValueSchema.optional(),
    capabilities: z.array(z.json()).optional(),
    directManipulation: displayValueSchema.optional(),
    componentNames: z.array(z.json()).optional(),
  })
  .passthrough();
const t2CompositionSchema = z
  .object({
    sceneID: displayValueSchema.optional(),
    family: displayValueSchema.optional(),
    rootID: displayValueSchema.optional(),
    roles: z.array(z.json()).optional(),
    nodeCount: displayValueSchema.optional(),
    datasetCount: displayValueSchema.optional(),
    dataRowCount: displayValueSchema.optional(),
    bindingCount: displayValueSchema.optional(),
  })
  .passthrough();
const recordSchema = z
  .object({
    runID: displayValueSchema.optional(),
    caseID: displayValueSchema.optional(),
    repetition: displayValueSchema.optional(),
    sequence: displayValueSchema.optional(),
    subject: displayValueSchema.optional(),
    status: displayValueSchema.optional(),
    elapsedSeconds: displayValueSchema.optional(),
    failureReason: displayValueSchema.optional(),
    caseSnapshot: z
      .object({
        id: displayValueSchema.optional(),
        caseKind: displayValueSchema.optional(),
        subject: displayValueSchema.optional(),
        question: z.json().optional(),
        materialTitle: displayValueSchema.optional(),
        materialKind: displayValueSchema.optional(),
        materialText: displayValueSchema.optional(),
        selectionTitle: displayValueSchema.optional(),
        selectionText: displayValueSchema.optional(),
        expectedCapabilityFamilies: z.array(z.json()).optional(),
        userBenefitCriteria: z.array(z.json()).optional(),
        rejectedOrDegradedBehaviors: z.array(z.json()).optional(),
      })
      .passthrough()
      .optional(),
    shapeDecision: z
      .object({
        expectedShape: displayValueSchema.optional(),
        actualShape: displayValueSchema.optional(),
        preferredSurface: displayValueSchema.optional(),
        directManipulation: displayValueSchema.optional(),
        t1SceneCount: displayValueSchema.optional(),
        t2SceneCount: displayValueSchema.optional(),
        narrativeCharacterCount: displayValueSchema.optional(),
      })
      .passthrough()
      .optional(),
    expressionPlan: z
      .object({
        expressionPlan: z.json().optional(),
        t1Programs: z.array(t1ProgramSchema).optional(),
        t2Compositions: z.array(t2CompositionSchema).optional(),
      })
      .passthrough()
      .optional(),
    sourceBinding: z
      .object({
        textSourceLabels: z.array(z.json()).optional(),
        evidenceLedgerLabels: z.array(z.json()).optional(),
        evidenceState: displayValueSchema.optional(),
        sceneEvidenceIDs: z.array(z.json()).optional(),
        hasExpectedSource: displayValueSchema.optional(),
      })
      .passthrough()
      .optional(),
    repairAndRetest: z
      .object({
        previousRunID: displayValueSchema.optional(),
        previousStatus: displayValueSchema.optional(),
        repairNote: displayValueSchema.optional(),
        isRetest: displayValueSchema.optional(),
      })
      .passthrough()
      .optional(),
    toolAndProtocolValidation: validationSchema.optional(),
    modelRawReply: replySchema.optional(),
  })
  .passthrough();
const captureManifestSchema = z
  .object({
    status: displayValueSchema.optional(),
    captureStatus: displayValueSchema.optional(),
    qualityGate: z
      .object({
        status: displayValueSchema.optional(),
        inputs: z
          .record(
            z.string(),
            z
              .object({
                present: z.boolean().optional(),
                stablePaneFrames: z.boolean().optional(),
              })
              .passthrough(),
          )
          .optional(),
        checks: z
          .array(
            z
              .object({
                id: z.string().optional(),
                status: displayValueSchema.optional(),
              })
              .passthrough(),
          )
          .optional(),
      })
      .passthrough()
      .optional(),
  })
  .passthrough();

type JsonValue = z.infer<ReturnType<typeof z.json>>;
type IndexEntry = z.infer<typeof indexEntrySchema>;
type RunMetadata = z.infer<typeof runMetadataSchema>;
type EvidenceRecord = z.infer<typeof recordSchema>;

interface ScreenshotAssets {
  overview: string | null;
  before: string | null;
  after: string | null;
  missing: string[];
  expectsAfter: boolean;
}

interface VisibleEvidence {
  status: "verified" | "failed";
  reason: string;
  manifestPath: string;
  qualityStatus: string;
  visibleContentStatus: string;
  missingStages: string[];
  unprovenStages: string[];
}

interface T1ProgramView {
  sceneID: string;
  family: string;
  version: string;
  maxHeight: number | null;
  capabilities: JsonValue[];
  directManipulation: string;
  componentNames: JsonValue[];
}

interface T2CompositionView {
  sceneID: string;
  family: string;
  rootID: string;
  roles: JsonValue[];
  nodeCount: number;
  datasetCount: number;
  dataRowCount: number;
  bindingCount: number;
}

interface AttemptRecord {
  runID: string;
  caseID: string;
  repetition: number;
  sequence: number;
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
  expectedShape: string;
  actualShape: string;
  preferredSurface: string;
  directManipulation: string;
  t1SceneCount: number;
  t2SceneCount: number;
  narrativeCharacterCount: number | null;
  toolAndProtocolValidation: {
    status: string;
    validationKind: string;
    passedChecks: JsonValue[];
    issues: JsonValue[];
    protocolDiagnostics: JsonValue[];
    toolTrace: JsonValue[];
  };
  sourceBinding: {
    textSourceLabels: JsonValue[];
    evidenceLedgerLabels: JsonValue[];
    evidenceState: string;
    sceneEvidenceIDs: JsonValue[];
    hasExpectedSource: boolean;
  };
  expressionPlan: {
    expressionPlanRaw: string;
    t1Programs: T1ProgramView[];
    t2Compositions: T2CompositionView[];
  };
  promptAndMaterial: {
    requestJSON: string;
    workflow: string;
    resolvedWorkflow: string;
    materialIsTruncated: string;
    contextRevision: string;
  };
  modelRawReply: {
    replyText: string;
    backend: string;
    toolTrace: JsonValue[];
    richAnswerExists: boolean;
    replyJSON: string;
  };
  failureReason: string;
  repairAndRetest: {
    previousRunID: string;
    previousStatus: string;
    repairNote: string;
    isRetest: string;
  };
  screenshotEvidence: {
    originalStatus: string;
    qualityStatus: string;
    replaced: boolean;
    repairEvidence: z.infer<typeof repairEvidenceSchema> | null;
    screenshotManifest: string;
  };
  visibleEvidence: VisibleEvidence;
  expectedCapabilityFamilies: JsonValue[];
  userBenefitCriteria: JsonValue[];
  rejectedOrDegradedBehaviors: JsonValue[];
  beforeImage: string | null;
  afterImage: string | null;
  overviewImage: string | null;
  interactionEvidence: boolean;
  missing: {
    overviewScreenshot: string;
    beforeScreenshot: string;
    afterScreenshot: string;
    request: string;
    reply: string;
    validation: string;
    record: string;
  };
}

interface RunData {
  runMetadata: RunMetadata | null;
  rawIndex: z.infer<typeof indexSchema> | null;
  records: AttemptRecord[];
}

interface CaseGroup {
  caseID: string;
  attempts: AttemptRecord[];
  question: string;
  subject: string;
  caseKind: string;
}

interface GroupData {
  groups: CaseGroup[];
  filters: {
    statuses: string[];
    subjects: string[];
    shapes: string[];
    repetitions: string[];
  };
  counts: {
    status: Record<string, number>;
    byKind: Record<string, number>;
    byCaseKind: Record<string, number>;
    repetitionCounts: Record<string, number>;
    totalsByKindAndTarget: Record<string, number>;
  };
}

interface EvidencePayload {
  generatedAt: string;
  run: {
    runID: string;
    rootPath: string;
    createdAt: string;
    repairedFrom: string;
    repairNote: string;
    continueAfterFailure: string;
    requestedIDs: JsonValue[];
    filters: JsonValue[];
    sourceRoot: string;
    sourceRunDir: string;
  };
  overview: {
    totalActualRecords: number;
    totalActualCases: number;
    totalExpectedTarget: number;
    expectedByKind: Record<string, number>;
    actualByKind: Record<string, number>;
    statusCount: Record<string, number>;
    subjectCount: number;
    missingGapByKind: Array<{
      kind: string;
      expected: number;
      actual: number;
      gap: number;
    }>;
    filterOptions: GroupData["filters"];
    repetitionCount: number;
    completionState: string;
  };
  cases: CaseGroup[];
  missingFields: string[];
}

interface ViewerFilter {
  reviewMode: "rich" | "boundary" | "all";
  status: string;
  subject: string;
  shape: string;
  repetition: string;
  keyword: string;
}

interface ViewerScreenshotAsset {
  key: "overview" | "before" | "after";
  label: string;
  src: string;
}

declare global {
  interface Window {
    __EVIDENCE_DATA: EvidencePayload;
  }
}

interface CliOptions {
  source: string;
  force: boolean;
  output: string | null;
  assetMode: AssetMode | string;
  runDir?: string;
  runId?: string;
  help?: boolean;
}

interface ReadResult<T> {
  ok: boolean;
  value: T | null;
  missing: boolean;
  parseError: string | null;
  path: string;
}

interface BuildReport {
  missingFields: string[];
  outputDir: string;
  copiedFiles: number;
  linkedFiles: number;
  assetMode: AssetMode;
}

const TARGET_BREAKDOWN: Record<string, number> = {
  rich: 40,
  "text-only": 6,
  degradation: 9,
  "invalid-protocol": 1,
};
const TARGET_TOTAL = 56;
const DATASET_PATH = ".build/rich-answer-evidence";

/** 将未知输入规范化为非空展示文本。 */
function toString(v: unknown, fallback = "缺失"): string {
  if (v === null || v === undefined) return fallback;
  if (typeof v === "string") return v.trim() || fallback;
  return String(v);
}

/** 将可空真值转换为中文展示文本。 */
function boolText(v: unknown): string {
  return v === undefined || v === null ? "缺失" : v ? "是" : "否";
}

/** 安全序列化任意 JSON 兼容值。 */
function safeJsonString(value: unknown, fallback = "缺失"): string {
  if (value === undefined) return fallback;
  if (value === null) return "null";
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return fallback;
  }
}

/** 返回当前 ISO 时间戳。 */
function nowStamp(): string {
  return new Date().toISOString();
}

/** 确保目标目录存在。 */
function ensureDir(dirPath: string): void {
  fs.mkdirSync(dirPath, { recursive: true });
}

/** 判断路径是否为普通文件。 */
function fileExists(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

/** 判断路径是否为目录。 */
function dirExists(dirPath: string): boolean {
  try {
    return fs.statSync(dirPath).isDirectory();
  } catch {
    return false;
  }
}

/**
 * 读取 JSON 文件并用调用方领域 schema 验证，同时保留缺失与结构错误信息。
 *
 * @param filePath - 待读取的 JSON 文件路径
 * @param schema - 对应证据文件类型的 Zod schema
 * @returns 带解析结果或可诊断错误的读取结果
 */
function readJSON<T>(filePath: string, schema: z.ZodType<T>): ReadResult<T> {
  try {
    const content = fs.readFileSync(filePath, "utf8");
    return {
      ok: true,
      value: parseEvidenceJson(content, filePath, schema),
      missing: false,
      parseError: null,
      path: filePath,
    };
  } catch (error: unknown) {
    return {
      ok: false,
      value: null,
      missing: !fileExists(filePath),
      parseError: error instanceof Error ? error.message : String(error),
      path: filePath,
    };
  }
}

/** 读取原始文本文件。 */
function readRawText(filePath: string): ReadResult<string> {
  try {
    return {
      ok: true,
      value: fs.readFileSync(filePath, "utf8"),
      missing: false,
      path: filePath,
      parseError: null,
    };
  } catch (error: unknown) {
    return {
      ok: false,
      value: null,
      missing: !fileExists(filePath),
      path: filePath,
      parseError: error instanceof Error ? error.message : String(error),
    };
  }
}

/** 解析命令行参数。 */
function parseArgs(): CliOptions {
  const args = process.argv.slice(2);
  const out: CliOptions = {
    source: DATASET_PATH,
    force: false,
    output: null,
    assetMode: "copy",
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--run-dir") {
      out.runDir = path.resolve(args[index + 1]!);
      index += 1;
      continue;
    }
    if (arg === "--run-id") {
      out.runId = args[index + 1]!;
      index += 1;
      continue;
    }
    if (arg === "--source") {
      out.source = args[index + 1]!;
      index += 1;
      continue;
    }
    if (arg === "--output" || arg === "--out") {
      out.output = path.resolve(args[index + 1]!);
      index += 1;
      continue;
    }
    if (arg === "--force") {
      out.force = true;
      continue;
    }
    if (arg === "--asset-mode") {
      out.assetMode = args[index + 1]!;
      index += 1;
      continue;
    }
    if (arg === "--help" || arg === "-h") {
      out.help = true;
      continue;
    }
    throw new Error(`未知参数: ${arg}`);
  }
  return out;
}

/** 构造命令行帮助文本。 */
function usage(): string {
  return [
    "用途：将 .build/rich-answer-evidence/<runID>/ 下的证据目录生成离线验收包。",
    "",
    "用法:",
    "  npm exec -- tsx Prototypes/RichAnswerEvidenceViewer/generate-evidence-package.ts --run-dir <run-dir> --output <out-dir> [--force]",
    "  npm exec -- tsx Prototypes/RichAnswerEvidenceViewer/generate-evidence-package.ts --run-id <runID> --source .build/rich-answer-evidence --output <out-dir> [--force]",
    "",
    "参数:",
    "  --run-dir      直接指定证据目录（如 .build/rich-answer-evidence/xxx）",
    "  --run-id       指定 runID（与 --source 一起使用）",
    "  --source       run 目录父路径，默认 .build/rich-answer-evidence",
    "  --output/--out 输出目录",
    "  --asset-mode   图片落档方式：copy / hardlink / symlink，默认 copy",
    "  --force        如输出目录已存在，允许覆盖",
    "  --help         显示此帮助",
  ].join("\n");
}

/** 规范化用例分类。 */
function normalizeRunKind(kind: unknown): string {
  if (!kind) return "unknown";
  const value = String(kind).toLowerCase();
  if (value.includes("invalid")) return "invalid-protocol";
  if (value.includes("degradation")) return "degradation";
  if (value.includes("text")) return "text-only";
  if (value.includes("rich")) return "rich";
  if (value.includes("success")) return "rich";
  return value;
}

/** 从用例目录中提取用例名。 */
function pickCaseName(caseDir: string): string {
  return path.basename(caseDir);
}

/** 从用例目录选择操作前后截图。 */
function pickScreenshots(caseDir: string): {
  before: string | null;
  after: string | null;
} {
  const files = dirExists(caseDir)
    ? fs.readdirSync(caseDir).filter((item) => /\.png$/i.test(item))
    : [];

  /** 计算截图文件名与目标阶段的匹配分数。 */
  const score = (name: string, target: string): number => {
    const lower = name.toLowerCase();
    const t = target.toLowerCase();
    if (lower === `${t}.png`) return 100;
    if (new RegExp(`^${t}[ _-]`).test(lower)) return 90;
    if (new RegExp(`[._-]${t}[._-]?`).test(lower)) return 80;
    if (lower.includes(t)) return 70;
    if (
      t === "after" &&
      /(after|after-action|afterstate|after_state|final|result)/i.test(lower)
    )
      return 50;
    if (
      t === "before" &&
      /(before|pre|init|start|beforestate|before_state)/i.test(lower)
    )
      return 50;
    return 0;
  };

  /** 选择给定阶段得分最高的截图文件。 */
  const choose = (target: string): string | null => {
    let best: string | null = null;
    let bestScore = -1;
    for (const file of files) {
      const s = score(file, target);
      if (s > bestScore) {
        bestScore = s;
        best = file;
      }
    }
    return best;
  };

  return {
    before: choose("before"),
    after: choose("after"),
  };
}

/** 将未知值转换为可嵌入 Markdown 的文本。 */
function asMarkdownSafe(value: unknown): string {
  if (value === undefined || value === null) return "缺失";
  if (typeof value !== "string") return safeJsonString(value, "缺失");
  return value;
}

/** 生成稳定且适合文件名的资源标识。 */
function toAssetId(caseID: unknown, repetition: unknown): string {
  return `case_${String(caseID || "unknown").replace(/[^a-zA-Z0-9\u4e00-\u9fff_-]/g, "_")}_r${String(repetition || 0)}`;
}

/** 将未知值转换为有限数值。 */
function safeNumber(value: unknown): number | null {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

/** 从截图字段中提取字符串路径。 */
function screenshotPath(value: unknown): string | null {
  if (typeof value === "string") return value;
  if (
    value &&
    typeof value === "object" &&
    "path" in value &&
    typeof value.path === "string"
  )
    return value.path;
  return null;
}

/** 将证据路径解析为绝对路径。 */
function resolveEvidencePath(
  value: string | null | undefined,
  runRoot: string,
): string | null {
  if (!value) return null;
  return path.isAbsolute(value) ? value : path.join(runRoot, value);
}

/** 汇总真实窗口截图证据的完整性。 */
function captureEvidenceSummary(
  entry: IndexEntry,
  runRoot: string,
): VisibleEvidence {
  const manifestPath = resolveEvidencePath(
    entry.repairEvidence?.manifestPath ?? entry.screenshotManifest,
    runRoot,
  );
  const manifestResult = manifestPath
    ? readJSON(manifestPath, captureManifestSchema)
    : { ok: false, value: null };
  const manifest = manifestResult.value;
  const qualityGate = manifest?.qualityGate;
  const inputs = qualityGate?.inputs ?? {};
  const visibleCheck = (qualityGate?.checks ?? []).find(
    (check) => check.id === "visible-content",
  );
  const caseKind = normalizeRunKind(entry.caseKind);
  const requiredStages =
    caseKind === "rich" ? ["overview", "before", "after"] : ["single"];
  const screenshots = entry.screenshots ?? {};
  const missingStages = requiredStages.filter(
    (stage) => !screenshotPath(screenshots[stage]),
  );
  const unprovenStages = requiredStages.filter((stage) => {
    const acknowledgement = inputs[`${stage}Ack`];
    return (
      acknowledgement?.present !== true ||
      acknowledgement?.stablePaneFrames !== true
    );
  });
  const visibleContentPassed = visibleCheck?.status === "pass";
  const verified =
    manifestResult.ok &&
    manifest?.status === "succeeded" &&
    manifest.captureStatus === "succeeded" &&
    missingStages.length === 0 &&
    unprovenStages.length === 0 &&
    visibleContentPassed;

  let reason = "真实窗口、正文可见性与稳定窗格回执均已核对";
  if (!manifestResult.ok) reason = "截图清单缺失或不可读";
  else if (
    manifest?.status !== "succeeded" ||
    manifest?.captureStatus !== "succeeded"
  )
    reason = "截图捕获链失败";
  else if (missingStages.length > 0)
    reason = `缺少截图：${missingStages.join("、")}`;
  else if (unprovenStages.length > 0)
    reason = `旧截图未证明正文与窗格稳定：${unprovenStages.join("、")}`;
  else if (!visibleContentPassed) reason = "自动可见内容检查未通过";

  return {
    status: verified ? "verified" : "failed",
    reason,
    manifestPath: manifestPath || "缺失",
    qualityStatus: toString(qualityGate?.status, "缺失"),
    visibleContentStatus: toString(visibleCheck?.status, "缺失"),
    missingStages,
    unprovenStages,
  };
}

/** 按指定模式将截图落入验收包。 */
function materializeAsset(
  source: string,
  target: string,
  report: BuildReport,
): void {
  fs.rmSync(target, { force: true });
  if (report.assetMode === "symlink") {
    fs.symlinkSync(source, target);
    report.linkedFiles += 1;
    return;
  }
  if (report.assetMode === "hardlink") {
    try {
      fs.linkSync(source, target);
      report.linkedFiles += 1;
      return;
    } catch {}
  }
  fs.copyFileSync(source, target);
  report.copiedFiles += 1;
}

/** 收集单次尝试关联的截图资源。 */
function collectImageAssets(
  caseDir: string,
  outputAssetsDir: string,
  caseID: unknown,
  repetition: unknown,
  entry: IndexEntry,
  report: BuildReport,
): ScreenshotAssets {
  const screenshots = pickScreenshots(caseDir);
  const explicit = entry.screenshots ?? {};
  const explicitOverview = screenshotPath(explicit.overview);
  const explicitSingle = screenshotPath(explicit.single);
  const explicitInteractionBefore = screenshotPath(explicit.before);
  const explicitBefore = explicitInteractionBefore || explicitSingle;
  const explicitAfter = screenshotPath(explicit.after);
  const expectsAfter =
    explicitSingle && !explicitInteractionBefore && !explicitAfter
      ? false
      : normalizeRunKind(entry.caseKind) === "rich";
  const asset: ScreenshotAssets = {
    overview: null,
    before: null,
    after: null,
    missing: [],
    expectsAfter,
  };

  const assetBase = toAssetId(caseID, repetition);
  ensureDir(outputAssetsDir);

  /** 在源文件存在时将其落档并返回相对资源路径。 */
  const materializeIfExist = (
    kind: string,
    source: string | null,
  ): string | null => {
    if (!source) return null;
    const resolvedSource = path.isAbsolute(source)
      ? source
      : path.join(caseDir, source);
    if (!fileExists(resolvedSource)) return null;
    const filename = path.basename(resolvedSource);
    const targetName = `${assetBase}-${kind}-${filename}`;
    const target = path.join(outputAssetsDir, targetName);
    materializeAsset(resolvedSource, target, report);
    return `assets/${targetName}`;
  };

  asset.overview = materializeIfExist("overview", explicitOverview) || null;
  asset.before =
    materializeIfExist("before", explicitBefore || screenshots.before) || null;
  asset.after =
    materializeIfExist("after", explicitAfter || screenshots.after) || null;
  if (!asset.before) asset.missing.push("before截图缺失");
  if (expectsAfter && !asset.after) asset.missing.push("after截图缺失");
  return asset;
}

/** 读取索引条目及其关联证据，生成离线展示记录。 */
function readRecordFromEntry(
  entry: IndexEntry,
  runRoot: string,
  outputAssetsDir: string,
  report: BuildReport,
): AttemptRecord {
  const recordPath = entry.recordPath ?? "";
  const runCasePath = path.isAbsolute(recordPath)
    ? recordPath
    : path.join(runRoot, recordPath);

  const caseDir =
    runCasePath && !runCasePath.endsWith(".json")
      ? runCasePath
      : path.dirname(runCasePath || "");

  const recordResult = readJSON(
    path.join(caseDir || runRoot, "record.json"),
    recordSchema,
  );
  if (!recordResult.ok) {
    report.missingFields.push(
      `record.json 读取失败: ${recordResult.path}: ${recordResult.parseError || "未知错误"}`,
    );
  }

  const record: EvidenceRecord = recordResult.value ?? {};
  const prompt = readJSON(path.join(caseDir, "request.json"), requestSchema);
  const reply = readJSON(path.join(caseDir, "reply.json"), replySchema);
  const validation = readJSON(
    path.join(caseDir, "validation.json"),
    validationSchema,
  );

  if (!prompt.ok)
    report.missingFields.push(
      `request.json 读取失败: ${prompt.path}: ${prompt.parseError || "未知错误"}`,
    );
  if (!reply.ok)
    report.missingFields.push(
      `reply.json 读取失败: ${reply.path}: ${reply.parseError || "未知错误"}`,
    );
  if (!validation.ok)
    report.missingFields.push(
      `validation.json 读取失败: ${validation.path}: ${validation.parseError || "未知错误"}`,
    );

  const caseSnapshot = record.caseSnapshot ?? {};
  const shapeDecision = record.shapeDecision ?? {};
  const expr = record.expressionPlan ?? {};
  const source = record.sourceBinding ?? {};
  const repair = record.repairAndRetest ?? {};
  const status = toString(record.status || entry.status, "unknown");

  const caseID = toString(
    caseSnapshot.id || entry.caseID || record.caseID,
    "unknown-case",
  );
  const repetition = safeNumber(record.repetition ?? entry.repetition);
  const sequence = safeNumber(record.sequence ?? entry.sequence);

  const images = collectImageAssets(
    caseDir,
    outputAssetsDir,
    caseID,
    repetition,
    entry,
    report,
  );
  const visibleEvidence = captureEvidenceSummary(entry, runRoot);
  const t1Programs = expr.t1Programs ?? [];
  const t2Compositions = expr.t2Compositions ?? [];

  return {
    runID: toString(record.runID || entry.runID),
    caseID,
    repetition: repetition || 0,
    sequence: sequence || 0,
    caseKind: normalizeRunKind(
      entry.caseKind || caseSnapshot.caseKind || "unknown",
    ),
    subject: toString(caseSnapshot.subject || record.subject || "未定义学科"),
    question: asMarkdownSafe(caseSnapshot.question || "未定义题目"),
    materialTitle: toString(
      caseSnapshot.materialTitle || prompt.value?.materialTitle,
    ),
    materialKind: toString(
      caseSnapshot.materialKind || prompt.value?.materialKind,
    ),
    materialText: toString(
      caseSnapshot.materialText || prompt.value?.materialText,
    ),
    selectionTitle: toString(
      caseSnapshot.selectionTitle || prompt.value?.selectionTitle,
    ),
    selectionText: toString(
      caseSnapshot.selectionText || prompt.value?.selectionText,
    ),
    status,
    elapsedSeconds: safeNumber(record.elapsedSeconds),
    expectedShape: toString(shapeDecision.expectedShape),
    actualShape: toString(shapeDecision.actualShape),
    preferredSurface: toString(shapeDecision.preferredSurface, "缺失"),
    directManipulation: boolText(shapeDecision.directManipulation),
    t1SceneCount: safeNumber(shapeDecision.t1SceneCount) || t1Programs.length,
    t2SceneCount:
      safeNumber(shapeDecision.t2SceneCount) || t2Compositions.length,
    narrativeCharacterCount: safeNumber(shapeDecision.narrativeCharacterCount),
    toolAndProtocolValidation: {
      status: toString(
        validation.value?.status || record.toolAndProtocolValidation?.status,
      ),
      validationKind: toString(
        validation.value?.validationKind ||
          record.toolAndProtocolValidation?.validationKind,
      ),
      passedChecks:
        validation.value?.passedChecks ||
        record.toolAndProtocolValidation?.passedChecks ||
        [],
      issues:
        validation.value?.issues ||
        record.toolAndProtocolValidation?.issues ||
        [],
      protocolDiagnostics:
        validation.value?.protocolDiagnostics ||
        record.toolAndProtocolValidation?.protocolDiagnostics ||
        [],
      toolTrace:
        validation.value?.toolTrace ||
        record.toolAndProtocolValidation?.toolTrace ||
        [],
    },
    sourceBinding: {
      textSourceLabels: source.textSourceLabels || [],
      evidenceLedgerLabels: source.evidenceLedgerLabels || [],
      evidenceState: toString(source.evidenceState),
      sceneEvidenceIDs: source.sceneEvidenceIDs || [],
      hasExpectedSource: Boolean(source.hasExpectedSource),
    },
    expressionPlan: {
      expressionPlanRaw: safeJsonString(expr.expressionPlan, "缺失"),
      t1Programs: t1Programs.map((item) => ({
        sceneID: toString(item.sceneID),
        family: toString(item.family),
        version: toString(item.version),
        maxHeight: safeNumber(item.maxHeight),
        capabilities: item.capabilities || [],
        directManipulation: boolText(item.directManipulation),
        componentNames: item.componentNames || [],
      })),
      t2Compositions: t2Compositions.map((item) => ({
        sceneID: toString(item.sceneID),
        family: toString(item.family),
        rootID: toString(item.rootID),
        roles: item.roles || [],
        nodeCount: safeNumber(item.nodeCount) || 0,
        datasetCount: safeNumber(item.datasetCount) || 0,
        dataRowCount: safeNumber(item.dataRowCount) || 0,
        bindingCount: safeNumber(item.bindingCount) || 0,
      })),
    },
    promptAndMaterial: {
      requestJSON: safeJsonString(prompt.value, "缺失"),
      workflow: toString(prompt.value?.workflow),
      resolvedWorkflow: toString(prompt.value?.resolvedWorkflow),
      materialIsTruncated: boolText(prompt.value?.materialIsTruncated),
      contextRevision: toString(prompt.value?.contextRevision),
    },
    modelRawReply: {
      replyText: toString(reply.value?.text || record.modelRawReply?.text),
      backend: toString(reply.value?.backend || record.modelRawReply?.backend),
      toolTrace: (
        reply.value?.toolTrace ||
        record.modelRawReply?.toolTrace ||
        []
      ).slice(),
      richAnswerExists: Boolean(
        reply.value?.richAnswer || record.modelRawReply?.richAnswer,
      ),
      replyJSON: safeJsonString(reply.value, "缺失"),
    },
    failureReason: toString(record.failureReason || entry.failureReason, "无"),
    repairAndRetest: {
      previousRunID: toString(repair.previousRunID, "缺失"),
      previousStatus: toString(repair.previousStatus, "缺失"),
      repairNote: toString(repair.repairNote),
      isRetest: boolText(repair.isRetest),
    },
    screenshotEvidence: {
      originalStatus: toString(
        entry.originalScreenshotStatus || entry.screenshotStatus,
        "缺失",
      ),
      qualityStatus: toString(entry.qualityStatus, "缺失"),
      replaced: Boolean(entry.repairEvidence),
      repairEvidence: entry.repairEvidence || null,
      screenshotManifest: toString(entry.screenshotManifest, "缺失"),
    },
    visibleEvidence,
    expectedCapabilityFamilies: caseSnapshot.expectedCapabilityFamilies || [],
    userBenefitCriteria: caseSnapshot.userBenefitCriteria || [],
    rejectedOrDegradedBehaviors: caseSnapshot.rejectedOrDegradedBehaviors || [],
    beforeImage: images.before,
    afterImage: images.after,
    overviewImage: images.overview,
    interactionEvidence: images.expectsAfter,
    missing: {
      overviewScreenshot: images.overview ? "已提供" : "不适用",
      beforeScreenshot: images.before ? "已提供" : "缺失",
      afterScreenshot: images.expectsAfter
        ? images.after
          ? "已提供"
          : "缺失"
        : "不适用",
      request: prompt.ok ? "已提供" : "缺失",
      reply: reply.ok ? "已提供" : "缺失",
      validation: validation.ok ? "已提供" : "缺失",
      record: recordResult.ok ? "已提供" : "缺失",
    },
  };
}

/** 从 run 目录收集并去重所有尝试记录。 */
function collectRecordsFromRunDir(
  runDir: string,
  report: BuildReport,
): RunData {
  const runJSON = readJSON(path.join(runDir, "run.json"), runMetadataSchema);
  const indexJSON = readJSON(path.join(runDir, "index.json"), indexSchema);

  if (!runJSON.ok)
    report.missingFields.push(
      `run.json 读取失败: ${runJSON.path}: ${runJSON.parseError || "未知错误"}`,
    );
  if (!indexJSON.ok)
    report.missingFields.push(
      `index.json 读取失败: ${indexJSON.path}: ${indexJSON.parseError || "未知错误"}`,
    );

  const runRootPath = runDir;
  const entries = indexJSON.value?.records ?? [];
  const assetsDir = path.join(report.outputDir, "assets");
  const records: AttemptRecord[] = [];

  if (Array.isArray(entries) && entries.length > 0) {
    for (const entry of entries) {
      records.push(readRecordFromEntry(entry, runRootPath, assetsDir, report));
    }
  } else {
    // 兼容未写入 index.json 的场景：按目录扫描
    const dirs = dirExists(runRootPath)
      ? fs.readdirSync(runRootPath, { withFileTypes: true })
      : [];
    for (const repetitionDir of dirs.filter(
      (item) => item.isDirectory() && /^repetition-/.test(item.name),
    )) {
      const repPath = path.join(runRootPath, repetitionDir.name);
      const repNumber =
        Number(String(repetitionDir.name).replace("repetition-", "")) || 0;
      for (const caseDirEnt of fs
        .readdirSync(repPath, { withFileTypes: true })
        .filter((item) => item.isDirectory())) {
        const caseID = pickCaseName(caseDirEnt.name);
        const caseDir = path.join(repPath, caseDirEnt.name);
        const entry: IndexEntry = {
          runID: runJSON.value?.runID || path.basename(runRootPath),
          repetition: repNumber,
          sequence: 0,
          caseID,
          caseKind: "unknown",
          subject: "未定义学科",
          status: "unknown",
          elapsedSeconds: 0,
          recordPath: path.join(caseDir, "record.json"),
          failureReason: null,
        };
        records.push(
          readRecordFromEntry(entry, runRootPath, assetsDir, report),
        );
      }
    }
  }

  // 记录唯一性：避免重复 entry（极端情况下可能重复）
  const unique = new Map<string, AttemptRecord>();
  for (const record of records) {
    const key = `${record.caseID}@@${record.repetition}@@${record.runID}`;
    unique.set(key, record);
  }

  return {
    runMetadata: runJSON.value || null,
    rawIndex: indexJSON.value || null,
    records: Array.from(unique.values()),
  };
}

/** 按用例聚合尝试记录并生成筛选元数据。 */
function buildGroupData(records: AttemptRecord[]): GroupData {
  const map = new Map<string, CaseGroup>();
  const subjects = new Set<string>();
  const shapes = new Set<string>();
  const statuses = new Set<string>();
  const repetitions = new Set<string>();
  const kindCounts: Record<string, number> = {
    rich: 0,
    "text-only": 0,
    degradation: 0,
    "invalid-protocol": 0,
    unknown: 0,
  };

  for (const item of records) {
    const key = item.caseID || "unknown-case";
    const existingGroup = map.get(key);
    if (existingGroup) {
      existingGroup.attempts.push(item);
    } else {
      map.set(key, {
        caseID: key,
        attempts: [item],
        question: item.question,
        subject: item.subject,
        caseKind: item.caseKind,
      });
    }
    subjects.add(item.subject || "未定义学科");
    shapes.add(item.actualShape || "缺失");
    statuses.add(item.status || "缺失");
    repetitions.add(String(item.repetition || "0"));
    const kind = item.caseKind || "unknown";
    if (kindCounts[kind] === undefined)
      kindCounts.unknown = (kindCounts.unknown ?? 0) + 1;
    else kindCounts[kind] += 1;
  }

  const groups = Array.from(map.values())
    .map((group) => {
      group.attempts.sort((a, b) => a.repetition - b.repetition);
      group.question = group.attempts[0]?.question || "未定义题目";
      group.subject = group.attempts[0]?.subject || "未定义学科";
      group.caseKind = group.attempts[0]?.caseKind || "unknown";
      return group;
    })
    .sort((a, b) => {
      if (a.subject !== b.subject)
        return String(a.subject).localeCompare(String(b.subject));
      return String(a.caseID).localeCompare(String(b.caseID));
    });

  const counts = {
    status: Array.from(statuses)
      .sort()
      .reduce<Record<string, number>>((acc, status) => {
        acc[status] = records.filter((item) => item.status === status).length;
        return acc;
      }, {}),
    byKind: kindCounts,
    byCaseKind: groups.reduce<Record<string, number>>(
      (acc, group) => {
        const kind = group.caseKind || "unknown";
        acc[kind] = (acc[kind] || 0) + 1;
        return acc;
      },
      {
        rich: 0,
        "text-only": 0,
        degradation: 0,
        "invalid-protocol": 0,
        unknown: 0,
      },
    ),
    repetitionCounts: Array.from(repetitions)
      .sort((a, b) => Number(a) - Number(b))
      .reduce<Record<string, number>>((acc, value) => {
        acc[value] = records.filter(
          (item) => String(item.repetition) === String(value),
        ).length;
        return acc;
      }, {}),
    totalsByKindAndTarget: TARGET_BREAKDOWN,
  };

  return {
    groups,
    filters: {
      statuses: Array.from(statuses).sort(),
      subjects: Array.from(subjects).sort(),
      shapes: Array.from(shapes).sort(),
      repetitions: Array.from(repetitions).sort(
        (a, b) => Number(a) - Number(b),
      ),
    },
    counts,
  };
}

/** 构造写入离线验收包的完整数据载荷。 */
function buildPayload(
  runDir: string,
  runID: string,
  runData: RunData,
  report: BuildReport,
): EvidencePayload {
  const grouped = buildGroupData(runData.records);
  const runMetadata = runData.runMetadata || {};

  const statusCountActual = { ...grouped.counts.status };

  const expectedTotals = Object.entries(TARGET_BREAKDOWN).reduce<
    Record<string, number>
  >((acc, [kind, count]) => {
    acc[kind] = count;
    return acc;
  }, {});
  expectedTotals.total = TARGET_TOTAL;

  const actualTotalByKind: Record<string, number> = {
    ...grouped.counts.byCaseKind,
  };
  actualTotalByKind.total = grouped.groups.length;

  const subjectGap: Record<string, number> = {};
  for (const item of runData.records) {
    subjectGap[item.subject] = (subjectGap[item.subject] || 0) + 1;
  }

  const missingFlags = Object.entries(grouped.counts.byCaseKind).map(
    ([kind, count]) => {
      const expected = TARGET_BREAKDOWN[kind] || 0;
      return {
        kind,
        expected,
        actual: count,
        gap: expected - Number(count),
      };
    },
  );

  return {
    generatedAt: nowStamp(),
    run: {
      runID: runID || toString(runMetadata.runID, path.basename(runDir)),
      rootPath: toString(runMetadata.rootPath, runDir),
      createdAt: toString(runMetadata.createdAt, "缺失"),
      repairedFrom: toString(runMetadata.retestOfRunID, "无"),
      repairNote: toString(runMetadata.repairNote, "无"),
      continueAfterFailure: toString(runMetadata.continueAfterFailure, "无"),
      requestedIDs: runMetadata.requestedIDs ?? [],
      filters: runMetadata.filters ?? [],
      sourceRoot: path.resolve(path.dirname(runDir)),
      sourceRunDir: runDir,
    },
    overview: {
      totalActualRecords: runData.records.length,
      totalActualCases: grouped.groups.length,
      totalExpectedTarget: TARGET_TOTAL,
      expectedByKind: expectedTotals,
      actualByKind: actualTotalByKind,
      statusCount: statusCountActual,
      subjectCount: Object.keys(subjectGap).length,
      missingGapByKind: missingFlags,
      filterOptions: grouped.filters,
      repetitionCount: grouped.filters.repetitions.length,
      completionState: grouped.groups.length > 0 ? "待用户验收" : "未开始",
    },
    cases: grouped.groups,
    missingFields: report.missingFields,
  };
}

/** 生成离线浏览器的 HTML 与客户端脚本。 */
function makeHtml(outputPath: string, payload: EvidencePayload): void {
  const htmlPath = path.join(outputPath, "index.html");
  const jsPath = path.join(outputPath, "viewer.js");
  const css = `
    :root {
      --paper: #f5f1e7;
      --paper-soft: #fefdfb;
      --ink: #2d2418;
      --ink-soft: #5c4f3e;
      --line: #d8cfbf;
      --accent: #6d5b47;
      --warn: #9a5a13;
      --ok: #335d3a;
    }

    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 24px 18px;
      background: linear-gradient(180deg, var(--paper) 0%, #efe9dc 100%);
      color: var(--ink);
      font-family: "PingFang SC", "Noto Serif SC", "Songti SC", Georgia, "Times New Roman", serif;
      line-height: 1.55;
    }
    .page {
      max-width: 1260px;
      margin: 0 auto;
    }
    .title {
      border-bottom: 2px solid var(--line);
      padding-bottom: 10px;
      margin-bottom: 10px;
      position: relative;
    }
    .title h1 {
      margin: 0;
      font-size: 26px;
      letter-spacing: 0.5px;
    }
    .meta-line {
      color: var(--ink-soft);
      font-size: 14px;
      margin: 6px 0;
    }
    .pending-pill {
      position: absolute;
      right: 0;
      top: 8px;
      background: #fff5dd;
      border: 1px solid #e2cc92;
      color: #7b5d1d;
      border-radius: 0;
      padding: 5px 10px;
      font-size: 12px;
      letter-spacing: 0.4px;
    }
    .panel {
      background: var(--paper-soft);
      border: 1px solid var(--line);
      padding: 12px 14px;
      margin: 12px 0;
      box-shadow: 0 2px 0 rgba(90, 70, 40, 0.06);
    }
    .grid2 {
      display: grid;
      grid-template-columns: repeat(2,minmax(0,1fr));
      gap: 10px;
    }
    .grid3 {
      display: grid;
      grid-template-columns: repeat(3,minmax(0,1fr));
      gap: 10px;
    }
    @media (max-width: 980px) {
      .grid2, .grid3 { grid-template-columns: 1fr; }
    }
    .summary-table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 8px;
    }
    .summary-table th, .summary-table td {
      border: 1px solid var(--line);
      padding: 8px;
      text-align: left;
      font-size: 13px;
    }
    .summary-table th {
      background: #f0e9d9;
      font-weight: 600;
      color: #4d3f2f;
    }
    .filter-row {
      display: grid;
      gap: 10px;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      margin: 12px 0;
    }
    .filter-row select, .filter-row input {
      width: 100%;
      border: 1px solid var(--line);
      background: #fff;
      padding: 8px;
      color: var(--ink);
    }
    .badges {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      margin-top: 8px;
      align-items: center;
    }
    .badge {
      font-size: 12px;
      border: 1px solid var(--line);
      padding: 3px 8px;
      background: #faf7ef;
    }
    .badge.ok { border-color: #b7d7be; color: var(--ok); background: #edf7ee; }
    .badge.warn { border-color: #e8cb95; color: var(--warn); background: #fff3dd; }
    .case-item {
      border: 1px solid var(--line);
      margin-top: 18px;
      background: #fffdf8;
      padding: 0;
      overflow: hidden;
    }
    .case-head {
      display: flex;
      gap: 8px;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
      padding: 16px 18px 12px;
      border-bottom: 1px solid var(--line);
      background: #f8f3e8;
    }
    .case-head b { font-size: 18px; }
    .case-head .question { max-width: 820px; color: var(--ink-soft); }
    .small { font-size: 12px; color: var(--ink-soft);}
    .attempt {
      padding: 14px 18px 18px;
    }
    .attempt h4 {
      margin: 0 0 5px 0;
      font-size: 14px;
    }
    .mode-bar {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      align-items: center;
      margin: 12px 0 8px;
    }
    .mode-button, .visual-choice, .dialog-close {
      appearance: none;
      border: 1px solid var(--line);
      background: #fffdf8;
      color: var(--ink);
      padding: 8px 12px;
      font: inherit;
      cursor: pointer;
    }
    .mode-button.active, .visual-choice.active {
      border-color: #8f563f;
      background: #8f563f;
      color: #fff;
    }
    .mode-note {
      margin: 0;
      color: var(--ink-soft);
      font-size: 13px;
    }
    .case-summary {
      padding: 0 18px;
    }
    .visual-review {
      margin-bottom: 14px;
    }
    .visual-toolbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 10px;
      flex-wrap: wrap;
      margin-bottom: 8px;
    }
    .visual-choices {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
    }
    .visual-choice {
      padding: 5px 9px;
      font-size: 12px;
    }
    .visual-frame {
      display: block;
      width: 100%;
      border: 1px solid var(--line);
      padding: 0;
      background: #ece5d8;
      cursor: zoom-in;
    }
    .visual-frame img {
      width: 100%;
      max-height: 760px;
      object-fit: contain;
      display: block;
      margin: 0 auto;
      background: #ece5d8;
    }
    .visual-empty {
      border: 1px dashed #d6b270;
      background: #fff5df;
      color: #76531c;
      padding: 18px;
    }
    .review-status {
      display: flex;
      gap: 6px;
      flex-wrap: wrap;
      margin: 10px 0;
    }
    .evidence-details {
      margin-top: 10px;
      border-top: 1px dashed var(--line);
      padding-top: 10px;
    }
    dialog {
      width: min(96vw, 1540px);
      max-height: 94vh;
      border: 1px solid var(--line);
      padding: 12px;
      background: #f8f3e8;
      color: var(--ink);
    }
    dialog::backdrop { background: rgba(24, 20, 15, 0.82); }
    .dialog-head {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      margin-bottom: 10px;
    }
    .dialog-image {
      display: block;
      width: 100%;
      max-height: calc(94vh - 72px);
      object-fit: contain;
      background: #ece5d8;
    }
    .code {
      white-space: pre-wrap;
      background: #faf6ed;
      border: 1px solid var(--line);
      padding: 8px;
      font-size: 12px;
      overflow: auto;
      max-height: 320px;
    }
    .muted { color: var(--ink-soft); font-size: 12px; }
    .missing { color: #a34a2e; }
    .diff {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      margin-top: 8px;
    }
    .diff .item {
      border: 1px solid var(--line);
      padding: 6px 8px;
      background: #fcf9f0;
      min-width: 130px;
      font-size: 12px;
    }
    @media (max-width: 720px) {
      body { padding: 12px 8px; }
      .panel { padding: 10px; }
      .filter-row { grid-template-columns: 1fr 1fr; }
      .attempt { padding: 10px; }
      .case-head { padding: 12px 10px; }
      .case-summary { padding: 0 10px; }
    }
  `;
  const html = `<!DOCTYPE html>
  <html lang="zh">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>富回答生成式 UI 验收</title>
    <style>${css}</style>
  </head>
  <body>
    <div class="page">
      <div class="title">
        <h1>富回答生成式 UI 验收</h1>
        <div class="meta-line">默认只展示 40 个真实富回答截图；纯文本、诚实降级和非法协议另放在“边界验证”。</div>
        <div class="meta-line">协议通过不等于视觉通过；这里保留原始留档，最终仍由用户验收。</div>
        <div class="pending-pill">${payload.overview.completionState}</div>
      </div>

      <section class="panel">
        <h2>总览</h2>
        <div class="grid3">
          <div>runID: <strong>${escapeHtml(payload.run.runID)}</strong></div>
          <div>run 目录: ${escapeHtml(payload.run.sourceRunDir)}</div>
          <div>生成时间: ${escapeHtml(payload.generatedAt)}</div>
          <div>目标总数: ${payload.overview.totalExpectedTarget}</div>
          <div>实际题目: ${payload.overview.totalActualCases}</div>
          <div>实际尝试: ${payload.overview.totalActualRecords}</div>
          <div>轮次数量: ${payload.overview.repetitionCount}</div>
        </div>
        <div class="badges">
          <span class="badge">待用户验收</span>
          ${payload.missingFields
            .slice(0, 3)
            .map(
              (item) => `<span class=\"badge warn\">${escapeHtml(item)}</span>`,
            )
            .join("")}
          ${payload.missingFields.length === 0 ? '<span class="badge ok">关键字段完整读取</span>' : ""}
        </div>
        <table class="summary-table">
          <thead>
            <tr><th>维度</th><th>应有</th><th>实际</th><th>差值</th><th>覆盖</th></tr>
          </thead>
          <tbody>
            <tr><td>rich（生成式 UI）</td><td>40</td><td>${payload.overview.actualByKind["rich"]}</td><td>${payload.overview.missingGapByKind.find((item) => item.kind === "rich")?.gap ?? 40}</td><td>${(payload.overview.actualByKind["rich"] ?? 0) >= 40 ? "完整" : "不足"}</td></tr>
            <tr><td>text-only（纯文本边界）</td><td>6</td><td>${payload.overview.actualByKind["text-only"]}</td><td>${payload.overview.missingGapByKind.find((item) => item.kind === "text-only")?.gap ?? 6}</td><td>${(payload.overview.actualByKind["text-only"] ?? 0) >= 6 ? "完整" : "不足"}</td></tr>
            <tr><td>degradation（诚实降级边界）</td><td>9</td><td>${payload.overview.actualByKind["degradation"]}</td><td>${payload.overview.missingGapByKind.find((item) => item.kind === "degradation")?.gap ?? 9}</td><td>${(payload.overview.actualByKind["degradation"] ?? 0) >= 9 ? "完整" : "不足"}</td></tr>
            <tr><td>invalid-protocol（非法协议边界）</td><td>1</td><td>${payload.overview.actualByKind["invalid-protocol"]}</td><td>${payload.overview.missingGapByKind.find((item) => item.kind === "invalid-protocol")?.gap ?? 1}</td><td>${(payload.overview.actualByKind["invalid-protocol"] ?? 0) >= 1 ? "完整" : "不足"}</td></tr>
            <tr><td>总计</td><td>56</td><td>${payload.overview.totalActualCases}</td><td>${TARGET_TOTAL - payload.overview.totalActualCases}</td><td>${payload.overview.totalActualCases >= 56 ? "完整" : "不足"}</td></tr>
          </tbody>
        </table>
      </section>

      <section class="panel">
        <h2>验收范围</h2>
        <div class="mode-bar" id="review-mode-bar">
          <button class="mode-button active" type="button" data-review-mode="rich">生成式 UI（40）</button>
          <button class="mode-button" type="button" data-review-mode="boundary">边界验证（16）</button>
          <button class="mode-button" type="button" data-review-mode="all">全部证据（56）</button>
        </div>
        <p class="mode-note" id="review-mode-note">当前只展示真正要求富回答的题目；每题默认显示最新一轮，点击截图可放大。</p>
        <h3>筛选</h3>
        <div class="filter-row">
          <select id="filter-status"><option value="__all">全部模型/协议记录</option></select>
          <select id="filter-subject"><option value="__all">全部学科</option></select>
          <select id="filter-shape"><option value="__all">全部形态</option></select>
          <select id="filter-repetition"><option value="__latest">最新一轮</option><option value="__all">全部轮次</option></select>
        </div>
        <input id="filter-keyword" type="text" placeholder="关键词搜索（题目 / caseID）" />
      </section>

      <section class="panel">
        <h2>缺失字段说明（不允许伪造）</h2>
        <div id="missing-list" class="small"></div>
      </section>

      <section>
        <h2 id="case-list-title">生成式 UI 逐题验收</h2>
        <div id="case-list"></div>
      </section>
    </div>
    <dialog id="image-dialog">
      <div class="dialog-head">
        <strong id="image-dialog-title">真实魏碑窗口</strong>
        <button class="dialog-close" type="button" id="image-dialog-close">关闭</button>
      </div>
      <img class="dialog-image" id="image-dialog-image" alt="真实魏碑窗口截图" />
    </dialog>
    <script>
      const EVIDENCE_DATA = ${safeJsonString(payload)};
      window.__EVIDENCE_DATA = EVIDENCE_DATA;
    </script>
    <script src="./viewer.js"></script>
  </body>
  </html>`;
  fs.writeFileSync(htmlPath, html, "utf8");
  fs.writeFileSync(jsPath, buildClientScript(), "utf8");
}

/** 将浏览器运行时序列化为可直接执行的脚本。 */
function buildClientScript(): string {
  return `(${evidenceViewerRuntime.toString()})();\n`;
}

/** 驱动离线验收页面的筛选、渲染与截图预览。 */
function evidenceViewerRuntime(): void {
  const data = window.__EVIDENCE_DATA;
  const cases = data.cases;
  const filters = data.overview.filterOptions;
  type ReviewMode = "rich" | "boundary" | "all";
  let reviewMode: ReviewMode = "rich";

  /** 按 ID 获取离线页面元素，缺失时立即报告生成模板错误。 */
  function byId<T extends HTMLElement>(id: string): T {
    const element = document.getElementById(id);
    if (!element) throw new Error(`离线验收页面缺少元素：${id}`);
    return element as T;
  }

  /** 转义动态内容，避免证据字段破坏页面 HTML。 */
  function e(v: unknown): string {
    if (v === undefined || v === null) return "";
    return String(v).replace(
      /[&<>"]/g,
      (c) =>
        ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c] ?? c,
    );
  }

  /** 渲染证据采集过程中记录的缺失项。 */
  function fillMissingList(): void {
    const container = byId<HTMLDivElement>("missing-list");
    const list = data.missingFields || [];
    if (!list || list.length === 0) {
      container.innerHTML =
        "<span class='badge ok'>当前 run 未发现缺失字段</span>";
      return;
    }
    container.innerHTML = list
      .slice(0, 30)
      .map((item) => `<div class="badge warn">缺失：${e(item)}</div>`)
      .join("");
  }

  /** 填充状态、学科、形态与轮次筛选选项。 */
  function buildOptions(): void {
    const statusEl = byId<HTMLSelectElement>("filter-status");
    const subjectEl = byId<HTMLSelectElement>("filter-subject");
    const shapeEl = byId<HTMLSelectElement>("filter-shape");
    const repEl = byId<HTMLSelectElement>("filter-repetition");

    /** 对筛选值去重、去空并排序。 */
    const all = (array: string[]): string[] =>
      Array.from(new Set(array)).filter(Boolean).sort();
    const statusList = all(
      filters.statuses.concat(
        cases
          .flatMap((caseItem) => caseItem.attempts)
          .map((attempt) => attempt.status),
      ),
    );
    const subjectList = all(
      filters.subjects.concat(cases.map((caseItem) => caseItem.subject)),
    );
    const shapeList = all(
      filters.shapes.concat(
        cases
          .flatMap((caseItem) => caseItem.attempts)
          .map((attempt) => attempt.actualShape),
      ),
    );
    const repetitionList = all(
      filters.repetitions.concat(
        cases
          .flatMap((caseItem) => caseItem.attempts)
          .map((attempt) => String(attempt.repetition)),
      ),
    );

    /** 将内部执行状态转换为面向验收者的说明。 */
    const statusLabel = (status: string): string =>
      status === "passed"
        ? "模型/协议记录正常"
        : status === "failed"
          ? "模型/协议记录待修"
          : status;
    statusList.forEach((status) =>
      statusEl.appendChild(new Option(statusLabel(status), status)),
    );
    subjectList.forEach((subject) =>
      subjectEl.appendChild(new Option(subject, subject)),
    );
    shapeList.forEach((shape) => shapeEl.appendChild(new Option(shape, shape)));
    repetitionList.forEach((rep) =>
      repEl.appendChild(new Option(`第 ${rep} 轮`, rep)),
    );
  }

  /** 读取当前页面筛选条件。 */
  function getFilters(): ViewerFilter {
    return {
      reviewMode,
      status: byId<HTMLSelectElement>("filter-status").value,
      subject: byId<HTMLSelectElement>("filter-subject").value,
      shape: byId<HTMLSelectElement>("filter-shape").value,
      repetition: byId<HTMLSelectElement>("filter-repetition").value,
      keyword: (byId<HTMLInputElement>("filter-keyword").value || "")
        .trim()
        .toLowerCase(),
    };
  }

  /** 判断一次尝试是否满足当前筛选条件。 */
  function isMatchedAttempt(
    attempt: AttemptRecord,
    filter: ViewerFilter,
  ): boolean {
    if (!attempt) return false;
    if (filter.status !== "__all" && attempt.status !== filter.status)
      return false;
    if (filter.subject !== "__all" && attempt.subject !== filter.subject)
      return false;
    if (filter.shape !== "__all" && attempt.actualShape !== filter.shape)
      return false;
    if (
      filter.repetition !== "__all" &&
      filter.repetition !== "__latest" &&
      String(attempt.repetition) !== String(filter.repetition)
    )
      return false;
    if (filter.keyword) {
      const keyword = filter.keyword;
      const fields = [
        attempt.caseID,
        attempt.question,
        attempt.subject,
        attempt.caseKind,
      ];
      const matched = fields.some((item) =>
        String(item || "")
          .toLowerCase()
          .includes(keyword),
      );
      if (!matched) return false;
    }
    return true;
  }

  /** 判断一次尝试是否真实产生了富回答。 */
  function isRichAttempt(attempt: AttemptRecord): boolean {
    return (
      attempt?.caseKind === "rich" &&
      String(attempt?.actualShape || "").includes("rich") &&
      Boolean(attempt?.modelRawReply?.richAnswerExists)
    );
  }

  /** 收集一次尝试可展示的真实窗口截图。 */
  function screenshotAssets(attempt: AttemptRecord): ViewerScreenshotAsset[] {
    return [
      { key: "overview", label: "完整窗口", src: attempt?.overviewImage },
      { key: "before", label: "操作前", src: attempt?.beforeImage },
      {
        key: "after",
        label: "操作后",
        src: attempt?.interactionEvidence ? attempt?.afterImage : null,
      },
    ].filter(
      (item): item is ViewerScreenshotAsset => typeof item.src === "string",
    );
  }

  /** 渲染真实窗口截图验收区。 */
  function renderVisualReview(attempt: AttemptRecord): string {
    const assets = screenshotAssets(attempt);
    if (assets.length === 0) {
      return `<div class="visual-empty">没有可展示的真实窗口截图，本轮不能进入视觉验收。</div>`;
    }
    const preferred =
      assets.find((item) => item.key === "overview") || assets[0];
    if (!preferred) {
      return `<div class="visual-empty">没有可展示的真实窗口截图，本轮不能进入视觉验收。</div>`;
    }
    const choices = assets
      .map(
        (item) =>
          `<button class="visual-choice ${item.key === preferred.key ? "active" : ""}" type="button" data-src="${e(item.src)}" data-label="${e(item.label)}">${e(item.label)}</button>`,
      )
      .join("");
    return `<div class="visual-review">
    <div class="visual-toolbar">
      <div class="visual-choices">${choices}</div>
      <span class="small">第 ${e(attempt.repetition)} 轮真实魏碑窗口 · 点击图片放大</span>
    </div>
    <button class="visual-frame" type="button" data-image-title="${e(attempt.caseID)} · ${e(preferred.label)}">
      <img src="${e(preferred.src)}" alt="${e(attempt.caseID)} · ${e(preferred.label)}" loading="lazy" />
    </button>
  </div>`;
  }

  /** 生成协议、显示与视觉验收状态徽标。 */
  function reviewBadges(attempt: AttemptRecord): string {
    const protocol =
      attempt.status === "passed"
        ? `<span class="badge">${attempt.caseKind === "rich" ? "模型与协议记录正常" : "安全边界判断正确（仅逻辑）"}</span>`
        : `<span class="badge warn">协议或模型结果待修</span>`;
    const visibleEvidence =
      attempt.visibleEvidence?.status === "verified"
        ? `<span class="badge ok">真实窗口正文已呈现</span>`
        : `<span class="badge warn">真实显示失败：${e(attempt.visibleEvidence?.reason || "缺少可验证证据")}</span>`;
    if (attempt.caseKind !== "rich") {
      return `${protocol}${visibleEvidence}<span class="badge">本题按要求不生成 UI</span><span class="badge warn">仍待用户验收</span>`;
    }
    const generated = isRichAttempt(attempt)
      ? `<span class="badge ok">已产生生成式 UI</span>`
      : `<span class="badge warn">没有真实生成式 UI</span>`;
    const screenshot =
      screenshotAssets(attempt).length > 0
        ? `<span class="badge">真实窗口截图已留档</span>`
        : `<span class="badge warn">截图缺失</span>`;
    return `${protocol}${generated}${visibleEvidence}${screenshot}<span class="badge warn">待用户审美与学习效果验收</span>`;
  }

  /** 渲染一次尝试的完整证据详情。 */
  function renderAttempt(attempt: AttemptRecord): string {
    const missing = attempt.missing || {};
    const screenshotEvidence = attempt.screenshotEvidence || {};
    const t1Rows = (attempt.expressionPlan?.t1Programs || [])
      .map((item) => {
        return `<li>scene:${e(item.sceneID)} / family:${e(item.family)} / version:${e(item.version)} / direct:${e(item.directManipulation)} / maxHeight:${e(item.maxHeight)} / components:${e((item.componentNames || []).join(",") || "无")}</li>`;
      })
      .join("");

    const t2Rows = (attempt.expressionPlan?.t2Compositions || [])
      .map((item) => {
        return `<li>scene:${e(item.sceneID)} / family:${e(item.family)} / rootID:${e(item.rootID)} / roles:${e((item.roles || []).join(",") || "无")} / nodes:${e(item.nodeCount)} / rows:${e(item.dataRowCount)}</li>`;
      })
      .join("");

    const protocolItems = (
      attempt.toolAndProtocolValidation?.passedChecks || []
    )
      .map((item) => `<li>${e(item)}</li>`)
      .join("");
    const issueItems = (attempt.toolAndProtocolValidation?.issues || [])
      .map((item) => `<li>${e(item)}</li>`)
      .join("");
    const diagItems = (
      attempt.toolAndProtocolValidation?.protocolDiagnostics || []
    )
      .map((item) => `<li>${e(item)}</li>`)
      .join("");
    const sourceLines = [
      `<li>textSource: ${e((attempt.sourceBinding?.textSourceLabels || []).join("、") || "无")}</li>`,
      `<li>ledger: ${e((attempt.sourceBinding?.evidenceLedgerLabels || []).join("、") || "无")}</li>`,
      `<li>sceneIDs: ${e((attempt.sourceBinding?.sceneEvidenceIDs || []).join("、") || "无")}</li>`,
      `<li>expectedMatch: ${attempt.sourceBinding?.hasExpectedSource ? "是" : "否"}</li>`,
    ].join("");

    const delta = `耗时:${e(attempt.elapsedSeconds)}s / 形态:${e(attempt.actualShape)} / 直操:${e(attempt.directManipulation)} / 预期:${e(attempt.expectedShape)} / 模型与协议记录:${e(attempt.status)}`;

    return `
      <div class="attempt">
        ${renderVisualReview(attempt)}
        <div class="review-status">
          ${reviewBadges(attempt)}
          <span class="badge">形态 ${e(attempt.actualShape)}</span>
          <span class="badge">T1 ${e(attempt.t1SceneCount)} / T2 ${e(attempt.t2SceneCount)}</span>
          <span class="badge">耗时 ${e(attempt.elapsedSeconds ?? "缺失")}s</span>
          <span class="badge ${screenshotEvidence.replaced ? "ok" : ""}">${screenshotEvidence.replaced ? "已补真实窗口证据" : "原始截图链"}</span>
        </div>
        <details class="evidence-details">
          <summary>查看本轮协议、来源和原始记录</summary>
          <div class="small">运行摘要：${e(delta)}</div>
          <div class="badges">
            <span class="badge">request: ${e(missing.request)}</span>
            <span class="badge">reply: ${e(missing.reply)}</span>
            <span class="badge">validation: ${e(missing.validation)}</span>
            <span class="badge">record: ${e(missing.record)}</span>
            <span class="badge">完整窗口: ${e(missing.overviewScreenshot)}</span>
            <span class="badge">before截图: ${e(missing.beforeScreenshot)}</span>
            <span class="badge">after截图: ${e(missing.afterScreenshot)}</span>
          </div>
          <p><strong>失败原因:</strong> ${e(attempt.failureReason || "无")}</p>
          <p><strong>截图技术状态:</strong> 原状态 ${e(screenshotEvidence.originalStatus)} / 自动检查 ${e(screenshotEvidence.qualityStatus)}${screenshotEvidence.replaced ? ` / 修复记录 ${e(screenshotEvidence.repairEvidence?.manifestPath || "已登记")}` : ""}</p>
        </details>
        <details>
          <summary>题目与材料</summary>
          <p><strong>题目：</strong>${e(attempt.question)}</p>
          <p><strong>材料标题：</strong>${e(attempt.materialTitle)}</p>
          <p><strong>材料类型：</strong>${e(attempt.materialKind)} / 选区：${e(attempt.selectionTitle)}</p>
          <div class="code">${e(attempt.materialText)}</div>
          <div class="code">${e(attempt.selectionText)}</div>
        </details>
        <details>
          <summary>原始回复</summary>
          <p>reply backend: ${e(attempt.modelRawReply?.backend)} / richAnswer: ${e(attempt.modelRawReply?.richAnswerExists ? "有" : "无")}</p>
          <div class="code">${e(attempt.modelRawReply?.replyText || attempt.modelRawReply?.replyJSON || "")}</div>
        </details>
        <details>
          <summary>T1/T2 计划与形态</summary>
          <div class="small">expressionPlan: ${e(attempt.expressionPlan?.expressionPlanRaw || "")}</div>
          <div>T1</div>
          <ul>${t1Rows || "<li>无</li>"}</ul>
          <div>T2</div>
          <ul>${t2Rows || "<li>无</li>"}</ul>
        </details>
        <details>
          <summary>协议与源绑定</summary>
          <div class="small">validation status: ${e(attempt.toolAndProtocolValidation?.status)} / type: ${e(attempt.toolAndProtocolValidation?.validationKind)}</div>
          <div>passedChecks</div>
          <ul>${protocolItems || "<li>无</li>"}</ul>
          <div>issues</div>
          <ul>${issueItems || "<li>无</li>"}</ul>
          <div>protocolDiagnostics</div>
          <ul>${diagItems || "<li>无</li>"}</ul>
          <div>sourceBinding</div>
          <ul>${sourceLines || "<li>无</li>"}</ul>
        </details>
      </div>
  `;
  }

  /** 汇总相邻轮次之间的状态与耗时变化。 */
  function buildDiff(attempts: AttemptRecord[]): string {
    if (!attempts || attempts.length < 2) return "";
    const lines = [];
    for (let index = 1; index < attempts.length; index += 1) {
      const prev = attempts[index - 1];
      const cur = attempts[index];
      if (!prev || !cur) continue;
      const delta = safeDelta(prev.elapsedSeconds, cur.elapsedSeconds);
      lines.push({
        label: `第${prev.repetition}→第${cur.repetition}轮`,
        text: `模型与协议记录 ${e(prev.status)}→${e(cur.status)}；形态 ${e(prev.actualShape)}→${e(cur.actualShape)}；耗时 ${e(delta)}`,
      });
    }
    return `<div class="diff">${lines.map((line) => `<div class="item"><strong>${line.label}</strong><br/>${line.text}</div>`).join("")}</div>`;
  }

  /** 计算两次尝试的耗时差。 */
  function safeDelta(prev: unknown, next: unknown): string {
    const p = Number(prev || 0);
    const n = Number(next || 0);
    if (Number.isNaN(p) || Number.isNaN(n)) return "缺失";
    const v = (n - p).toFixed(3);
    const prefix = n >= p ? "+" : "";
    return `${prefix}${v}s`;
  }

  /** 判断用例是否属于当前验收模式。 */
  function matchesReviewMode(
    caseItem: CaseGroup,
    mode: ViewerFilter["reviewMode"],
  ): boolean {
    if (mode === "rich") return caseItem.caseKind === "rich";
    if (mode === "boundary") return caseItem.caseKind !== "rich";
    return true;
  }

  /** 返回重复尝试中的最新一轮。 */
  function newestAttempt(attempts: AttemptRecord[]): AttemptRecord {
    const newest = [...attempts].sort(
      (left, right) =>
        Number(right.repetition || 0) - Number(left.repetition || 0),
    )[0];
    if (!newest) throw new Error("用例缺少可展示的尝试记录");
    return newest;
  }

  /** 判断用例是否仍存在协议、显示或截图待复核项。 */
  function caseNeedsReview(caseItem: CaseGroup): boolean {
    return caseItem.attempts.some((attempt) => {
      if (attempt.status !== "passed") return true;
      if (attempt.visibleEvidence?.status !== "verified") return true;
      if (caseItem.caseKind === "rich" && !isRichAttempt(attempt)) return true;
      return screenshotAssets(attempt).length === 0;
    });
  }

  /** 按当前筛选条件渲染单个用例及其尝试。 */
  function renderCase(caseItem: CaseGroup, filter: ViewerFilter): string {
    if (!matchesReviewMode(caseItem, filter.reviewMode)) return "";
    const matchedAttempts = caseItem.attempts.filter((attempt) =>
      isMatchedAttempt(attempt, filter),
    );
    if (matchedAttempts.length === 0) return "";
    const visibleAttempts =
      filter.repetition === "__latest"
        ? [newestAttempt(matchedAttempts)]
        : matchedAttempts;

    const caseTag = caseItem.caseID || "unknown";
    const head = `<div class="case-head"><div><b>${e(caseItem.subject || "未定义学科")}</b><div class="question">${e(caseItem.question || "")}</div></div><span class="small">${e(caseTag)}</span></div>`;
    const attemptsBlocks = visibleAttempts.map(renderAttempt).join("");
    const diffHtml =
      filter.repetition === "__all" ? buildDiff(visibleAttempts) : "";
    const needsReview = caseNeedsReview(caseItem);
    return `<article class="case-item">
    ${head}
    <div class="case-summary badges">
      ${needsReview ? '<span class="badge warn">存在待修或待复核轮次</span>' : '<span class="badge">四轮协议记录完整</span>'}
      <span class="badge warn">视觉仍待用户验收</span>
      <span class="badge">重复数：${caseItem.attempts.length}</span>
      <span class="badge">类型：${e(caseItem.caseKind)}</span>
    </div>
    ${diffHtml ? `<div class="case-summary"><strong>四轮差异</strong>${diffHtml}</div>` : ""}
    ${attemptsBlocks}
  </article>`;
  }

  /** 排序并刷新离线页面中的用例列表。 */
  function render(): void {
    const filter = getFilters();
    const list = byId<HTMLDivElement>("case-list");
    const orderedCases = [...cases].sort((left, right) => {
      const reviewDelta =
        Number(caseNeedsReview(left)) - Number(caseNeedsReview(right));
      if (reviewDelta !== 0) return reviewDelta;
      const subjectDelta = String(left.subject || "").localeCompare(
        String(right.subject || ""),
        "zh-CN",
      );
      if (subjectDelta !== 0) return subjectDelta;
      return String(left.caseID || "").localeCompare(
        String(right.caseID || ""),
      );
    });
    const rendered = orderedCases
      .map((item) => renderCase(item, filter))
      .filter(Boolean)
      .join("");
    list.innerHTML = rendered || '<div class="badge warn">当前筛选无结果</div>';
  }

  byId<HTMLSelectElement>("filter-status").addEventListener("change", render);
  byId<HTMLSelectElement>("filter-subject").addEventListener("change", render);
  byId<HTMLSelectElement>("filter-shape").addEventListener("change", render);
  byId<HTMLSelectElement>("filter-repetition").addEventListener(
    "change",
    render,
  );
  byId<HTMLInputElement>("filter-keyword").addEventListener("input", render);
  byId<HTMLDivElement>("review-mode-bar").addEventListener("click", (event) => {
    const button = (event.target as Element | null)?.closest<HTMLButtonElement>(
      "[data-review-mode]",
    );
    if (!button) return;
    reviewMode =
      (button.dataset.reviewMode as ReviewMode | undefined) || "rich";
    document
      .querySelectorAll("[data-review-mode]")
      .forEach((item) => item.classList.toggle("active", item === button));
    const notes: Record<ReviewMode, string> = {
      rich: "当前只展示真正要求富回答的 40 道题；每题默认显示最新一轮，点击截图可放大。",
      boundary:
        "这里验证应保持纯文本、诚实降级或拦截非法协议；协议通过不代表生成式 UI 或视觉质量通过。",
      all: "这里展示全部 56 题证据；生成式 UI 与边界题仍使用不同标记，不能混为整体视觉通过。",
    };
    byId<HTMLParagraphElement>("review-mode-note").textContent =
      notes[reviewMode];
    byId<HTMLHeadingElement>("case-list-title").textContent =
      reviewMode === "rich"
        ? "生成式 UI 逐题验收"
        : reviewMode === "boundary"
          ? "边界行为逐题核对"
          : "全部证据";
    render();
  });

  const caseList = byId<HTMLDivElement>("case-list");
  const imageDialog = byId<HTMLDialogElement>("image-dialog");
  const imageDialogImage = byId<HTMLImageElement>("image-dialog-image");
  const imageDialogTitle = byId<HTMLElement>("image-dialog-title");

  caseList.addEventListener("click", (event) => {
    const choice = (event.target as Element | null)?.closest<HTMLButtonElement>(
      ".visual-choice",
    );
    if (choice) {
      const review = choice.closest<HTMLElement>(".visual-review");
      const image =
        review?.querySelector<HTMLImageElement>(".visual-frame img");
      const frame = review?.querySelector<HTMLButtonElement>(".visual-frame");
      if (!review || !image || !frame) return;
      review
        .querySelectorAll(".visual-choice")
        .forEach((item: Element) =>
          item.classList.toggle("active", item === choice),
        );
      image.src = choice.dataset.src || image.src;
      image.alt = `${choice.closest(".case-item")?.querySelector(".case-head .small")?.textContent || "富回答"} · ${choice.dataset.label || "窗口截图"}`;
      frame.dataset.imageTitle = image.alt;
      return;
    }
    const frame = (event.target as Element | null)?.closest<HTMLButtonElement>(
      ".visual-frame",
    );
    if (!frame) return;
    const image = frame.querySelector("img");
    if (!image) return;
    imageDialogImage.src = image.src;
    imageDialogImage.alt = image.alt;
    imageDialogTitle.textContent =
      frame.dataset.imageTitle || image.alt || "真实魏碑窗口";
    imageDialog.showModal();
  });

  byId<HTMLButtonElement>("image-dialog-close").addEventListener("click", () =>
    imageDialog.close(),
  );
  imageDialog.addEventListener("click", (event) => {
    if (event.target === imageDialog) imageDialog.close();
  });

  buildOptions();
  fillMissingList();
  render();
}

/** 转义服务端 HTML 插值。 */
function escapeHtml(value: unknown): string {
  return toString(value, "").replace(
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

/** 对展示列表去重并移除空值。 */
function dedupeArray(list: unknown[]): unknown[] {
  return Array.from(new Set(list)).filter(
    (value) =>
      value !== null && value !== undefined && `${value}`.trim().length > 0,
  );
}

/** 执行证据包生成命令。 */
function run(): void {
  const argv = parseArgs();
  if (argv.help || process.argv.length <= 2) {
    console.log(usage());
    return;
  }

  if (!argv.runDir && !argv.runId) {
    throw new Error("必须提供 --run-dir 或 --run-id");
  }

  const runDir =
    argv.runDir ||
    path.resolve(path.resolve(argv.source || DATASET_PATH), argv.runId!);
  const output =
    argv.output ||
    path.join(
      process.cwd(),
      `rich-answer-evidence-view-${argv.runId || path.basename(runDir)}`,
    );

  if (!dirExists(runDir)) {
    throw new Error(`证据目录不存在：${runDir}`);
  }
  if (dirExists(output) && !argv.force) {
    throw new Error(
      `输出目录已存在：${output}；请加 --force 覆盖或换一个输出路径`,
    );
  }
  if (dirExists(output)) {
    fs.rmSync(output, { recursive: true, force: true });
  }
  ensureDir(output);

  if (!new Set(["copy", "hardlink", "symlink"]).has(argv.assetMode)) {
    throw new Error(`不支持的 --asset-mode：${argv.assetMode}`);
  }
  const report: BuildReport = {
    missingFields: [],
    outputDir: output,
    copiedFiles: 0,
    linkedFiles: 0,
    assetMode: argv.assetMode as AssetMode,
  };
  const runData = collectRecordsFromRunDir(runDir, report);
  if (!Array.isArray(runData.records) || runData.records.length === 0) {
    report.missingFields.push(
      "未识别到任何 record.json，验收包仍可生成但不可用于实际验收",
    );
  }

  const runID = toString(
    runData.runMetadata?.runID || argv.runId,
    path.basename(runDir),
  );
  const payload = buildPayload(runDir, runID, runData, report);
  makeHtml(output, payload);

  const summary = [
    `runID: ${runID}`,
    `输出目录: ${output}`,
    `记录数: ${payload.overview.totalActualRecords}`,
    `缺失项: ${payload.missingFields.length}`,
    `已复制图片: ${report.copiedFiles}`,
    `已链接图片: ${report.linkedFiles}`,
    `图片模式: ${report.assetMode}`,
    `生成时间: ${payload.generatedAt}`,
  ];
  console.log("富回答验收包已生成：\n" + summary.join("\n"));
}

run();
