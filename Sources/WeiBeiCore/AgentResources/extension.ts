import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { realpathSync } from "node:fs";
import { open, readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@earendil-works/pi-ai";

const CONTEXT_FILE_ENV = "WEIBEI_AGENT_CONTEXT_FILE";
const CONTEXT_TOOL = "weibei_context";
const COURSE_MAP_TOOL = "weibei_course_map";
const COURSE_SEARCH_TOOL = "weibei_course_search";
const VISUAL_ASSET_TOOL = "weibei_visual_asset";
const LEARNING_MEMORY_TOOL = "weibei_learning_memory";
const LEARNING_UPDATE_TOOL = "weibei_learning_update";
const NOTE_PROPOSAL_TOOL = "weibei_note_proposal";
const READ_TOOL = "read";
const RICH_ANSWER_CATALOG_TOOL = "weibei_ui_catalog";
const COMPUTE_ARTIFACT_TOOL = "weibei_compute_artifact";
const RICH_ANSWER_TOOL = "weibei_rich_answer";
const PYTHON_ARTIFACT_WORKER_PATH = fileURLToPath(
  new URL("./python/rich_answer_worker.py", import.meta.url),
);
const PYTHON_ARTIFACT_OPERATIONS = [
  "compute_statistics",
  "fit_regression",
  "bin_distribution",
  "sample_function",
] as const;
const PYTHON_ARTIFACT_OUTPUT_KINDS = ["json_spec", "numeric_series", "table"] as const;
type PythonArtifactOperation = typeof PYTHON_ARTIFACT_OPERATIONS[number];
type PythonArtifactOutputKind = typeof PYTHON_ARTIFACT_OUTPUT_KINDS[number];
const ALLOWED_TOOLS = new Set([
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

const RICH_ANSWER_SKILLS = {
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

type RichAnswerSkillID = keyof typeof RICH_ANSWER_SKILLS;

interface SkillReadDetails {
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

const RICH_ANSWER_SKILL_BY_PATH = new Map(
  Object.entries(RICH_ANSWER_SKILLS).map(([id, skill]) => [
    realpathSync(resolve(fileURLToPath(new URL(`./${skill.relativePath}`, import.meta.url)))),
    { id: id as RichAnswerSkillID, ...skill },
  ]),
);

function canonicalReadPath(value: unknown): string | undefined {
  if (typeof value !== "string" || !value.trim()) return undefined;
  try {
    return realpathSync(resolve(value));
  } catch {
    return undefined;
  }
}

function canonicalJSON(value: unknown): string {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("受控计算不能包含非有限数值");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJSON(item)).join(",")}]`;
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => `${JSON.stringify(key)}:${canonicalJSON(item)}`);
    return `{${entries.join(",")}}`;
  }
  throw new Error("受控计算只接受 JSON 值");
}

function sha256UTF8(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

function safeArtifactIdentifier(value: unknown): value is string {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/u.test(value);
}

interface PythonArtifactWorkerSuccess {
  schemaVersion: 1;
  ok: true;
  workerVersion: string;
  requestID: string;
  operation: PythonArtifactOperation;
  artifacts: Array<{
    id: string;
    kind: PythonArtifactOutputKind;
    mimeType: "application/json";
    role: string;
    payload: unknown;
    payloadCanonicalJSON?: string;
    sizeBytes: number;
    sha256: string;
    sourceEvidenceIDs: string[];
    metadata: Record<string, unknown>;
  }>;
  diagnostics: string[];
}

interface PythonArtifactWorkerFailure {
  schemaVersion?: number;
  ok?: false;
  workerVersion?: string;
  error?: { code?: string; message?: string };
}

async function runPythonArtifactWorker(
  request: Record<string, unknown>,
  limits: {
    maxInputBytes: number;
    maxOutputBytes: number;
    maxRuntimeMS: number;
  },
): Promise<{
  result: PythonArtifactWorkerSuccess;
  pythonExecutable: string;
  requestSHA256: string;
  outputSHA256: string;
  durationMS: number;
}> {
  const requestJSON = canonicalJSON(request);
  const requestBytes = Buffer.byteLength(requestJSON, "utf8");
  if (requestBytes > limits.maxInputBytes) {
    throw new Error(`受控计算输入超出预算：${requestBytes}/${limits.maxInputBytes} bytes`);
  }

  const pythonExecutable = process.env.WEIBEI_PYTHON_EXECUTABLE?.trim() || "/usr/bin/python3";
  const startedAt = performance.now();
  const outputJSON = await new Promise<string>((resolveOutput, rejectOutput) => {
    const child = spawn(
      pythonExecutable,
      ["-I", "-B", "-S", PYTHON_ARTIFACT_WORKER_PATH],
      {
        cwd: resolve(PYTHON_ARTIFACT_WORKER_PATH, ".."),
        env: {
          PATH: "/usr/bin:/bin",
          PYTHONNOUSERSITE: "1",
          PYTHONDONTWRITEBYTECODE: "1",
          PYTHONHASHSEED: "0",
          LC_ALL: "C.UTF-8",
          LANG: "C.UTF-8",
        },
        shell: false,
        stdio: ["pipe", "pipe", "pipe"],
      },
    );
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let settled = false;
    const finishWithError = (error: Error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      child.kill("SIGKILL");
      rejectOutput(error);
    };
    const timer = setTimeout(() => {
      finishWithError(new Error(`受控 Python 计算超过 ${limits.maxRuntimeMS}ms`));
    }, limits.maxRuntimeMS);

    child.stdout.on("data", (chunk: Buffer) => {
      stdoutBytes += chunk.length;
      if (stdoutBytes > limits.maxOutputBytes) {
        finishWithError(
          new Error(`受控计算输出超出预算：${stdoutBytes}/${limits.maxOutputBytes} bytes`),
        );
        return;
      }
      stdout.push(chunk);
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderrBytes += chunk.length;
      if (stderrBytes > 8_192) {
        finishWithError(new Error("受控 Python 计算产生了过量诊断输出"));
        return;
      }
      stderr.push(chunk);
    });
    child.on("error", (error) => finishWithError(error));
    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      const output = Buffer.concat(stdout).toString("utf8").trim();
      if (!output) {
        const stderrHash = stderrBytes > 0
          ? sha256UTF8(Buffer.concat(stderr).toString("utf8"))
          : "none";
        rejectOutput(
          new Error(`受控 Python 计算没有返回 JSON（exit=${code ?? "unknown"}, stderrHash=${stderrHash}）`),
        );
        return;
      }
      resolveOutput(output);
    });
    child.stdin.on("error", (error) => finishWithError(error));
    child.stdin.end(`${requestJSON}\n`, "utf8");
  });

  let decoded: PythonArtifactWorkerSuccess | PythonArtifactWorkerFailure;
  try {
    decoded = JSON.parse(outputJSON) as PythonArtifactWorkerSuccess | PythonArtifactWorkerFailure;
  } catch {
    throw new Error("受控 Python 计算返回了无法解析的 JSON");
  }
  if (decoded.ok !== true) {
    const code = decoded.error?.code?.trim() || "worker_error";
    const message = decoded.error?.message?.trim() || "受控 Python 计算失败";
    throw new Error(`${code}: ${message}`);
  }
  if (
    decoded.schemaVersion !== 1 ||
    !decoded.workerVersion ||
    decoded.requestID !== request.requestID ||
    decoded.operation !== request.operation ||
    !Array.isArray(decoded.artifacts) ||
    !Array.isArray(decoded.diagnostics)
  ) {
    throw new Error("受控 Python 计算返回的契约不完整");
  }
  const outputSHA256 = sha256UTF8(outputJSON);
  for (const artifact of decoded.artifacts) {
    if (
      !safeArtifactIdentifier(artifact.id) ||
      !PYTHON_ARTIFACT_OUTPUT_KINDS.includes(artifact.kind) ||
      artifact.mimeType !== "application/json" ||
      !safeArtifactIdentifier(artifact.role) ||
      !Array.isArray(artifact.sourceEvidenceIDs)
    ) {
      throw new Error("受控 Python 计算返回了非法产物元数据");
    }
    if (typeof artifact.payloadCanonicalJSON !== "string") {
      throw new Error(`受控 Python 产物 ${artifact.id} 缺少真实 canonical payload bytes`);
    }
    let canonicalPayload: unknown;
    try {
      canonicalPayload = JSON.parse(artifact.payloadCanonicalJSON);
    } catch {
      throw new Error(`受控 Python 产物 ${artifact.id} 的 canonical payload 无法解析`);
    }
    if (canonicalJSON(canonicalPayload) !== canonicalJSON(artifact.payload)) {
      throw new Error(`受控 Python 产物 ${artifact.id} 的 payload 与 canonical bytes 不一致`);
    }
    const payloadBytes = Buffer.byteLength(artifact.payloadCanonicalJSON, "utf8");
    if (
      artifact.sizeBytes !== payloadBytes ||
      artifact.sha256 !== sha256UTF8(artifact.payloadCanonicalJSON)
    ) {
      throw new Error(`受控 Python 产物 ${artifact.id} 的长度或哈希不匹配`);
    }
    delete artifact.payloadCanonicalJSON;
  }

  return {
    result: decoded,
    pythonExecutable,
    requestSHA256: sha256UTF8(requestJSON),
    outputSHA256,
    durationMS: Math.max(0, Math.round(performance.now() - startedAt)),
  };
}

type AnswerFormPolicy = "automatic" | "textOnly" | "partialRichAllowed";

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
  normalizations: string[];
}

interface ComputeArtifactToolDetails {
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
  | "invalid_render_plan"
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
    humanFixHint: "按错误位置重新生成完整富回答 payload；如果无法确定修复点，先重查目录并在 program、renderPlan 与 ui 之间重新选择；三次耗尽后停止富回答并正常回答用户问题，不暴露内部校验失败。",
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

function readAnswerFormPolicy(value: unknown): AnswerFormPolicy {
  if (value === undefined || value === null) return "automatic";
  const policy = requireString(value, "answerFormPolicy");
  if (policy === "automatic" || policy === "textOnly" || policy === "partialRichAllowed") {
    return policy;
  }
  throw new Error("魏碑上下文字段 answerFormPolicy 无效");
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

function evidenceLabels(snapshot: ContextSnapshotV2): string[] {
  const labels: string[] = [];
  if (snapshot.note.text.trim()) labels.push(`[笔记：${snapshot.note.title}]`);
  if (snapshot.material?.text.trim()) labels.push(`[材料：${snapshot.material.title}]`);
  if (snapshot.selection?.text.trim()) labels.push(`[选区：${snapshot.selection.title}]`);
  return labels;
}

function richAnswerRenderableAssetKind(kind: string, title: string): boolean {
  const normalizedKind = kind.trim().toLocaleLowerCase();
  if (["image", "pdf", "png", "jpg", "jpeg", "webp", "gif"].includes(normalizedKind)) {
    return true;
  }
  return /\.(?:png|jpe?g|webp|gif|pdf)$/iu.test(title.trim());
}

function richAnswerCurrentItems(
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

function richAnswerAllowedAssetIDs(
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

function richAnswerSourceBindings(
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
    const before = index === 0 ? "" : (snapshot.question[index - 1] ?? "");
    const after = end >= snapshot.question.length ? "" : (snapshot.question[end] ?? "");
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
      title: stableMatch[3]!,
      ordinal: Number(stableMatch[2]!) + 1,
      locationID: stableMatch[1]!,
    };
  }
  const stableOnlyMatch = rawHeading.match(/^\[(html-section-[A-Za-z0-9-]+)\]\s+(.+)$/);
  if (stableOnlyMatch) return { title: stableOnlyMatch[2]!, locationID: stableOnlyMatch[1]! };
  const legacyMatch = rawHeading.match(/^\[html-heading-(\d+)\]\s+(.+)$/);
  if (!legacyMatch) return { title: rawHeading };
  return { title: legacyMatch[2]!, ordinal: Number(legacyMatch[1]!) + 1 };
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
  DistributionBrush: "跨统计、实验与数据阅读使用；总体数值由模型提供，窗口统计由本地组件计算。windowSpan 是完整窗口宽度，实际范围为 [windowCenter - windowSpan/2, windowCenter + windowSpan/2]；例如覆盖 10–50 应设 center=30、span=40，覆盖 10–13 应设 center=11.5、span=3。初始窗口应显示与学习目标有关的观测，除非空窗口本身就是观察对象；caption 必须描述运行时实际范围",
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

const RICH_ANSWER_STANDARD_CHART_TYPES = [
  "line",
  "bar",
  "area",
  "scatter",
  "mixed",
  "histogram",
] as const;
type RichAnswerStandardChartType = typeof RICH_ANSWER_STANDARD_CHART_TYPES[number];

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

const RICH_ANSWER_KNOWLEDGE_SHAPES = [
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
] as const;

type RichAnswerKnowledgeShape = typeof RICH_ANSWER_KNOWLEDGE_SHAPES[number];

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

const RICH_ANSWER_SPATIAL_DIMENSIONS = [
  "notSpatial",
  "oneDimensional",
  "twoDimensional",
  "threeDimensional",
] as const;
const RICH_ANSWER_TEMPORAL_BEHAVIORS = ["static", "stateChange", "timeEvolution"] as const;
const RICH_ANSWER_DATA_ORIGINS = [
  "sourceObserved",
  "derivedFromSource",
  "deterministicSimulation",
  "sourceAsset",
  "conceptual",
] as const;
const RICH_ANSWER_COORDINATE_FRAMES = [
  "none",
  "categorical",
  "cartesian",
  "polar",
  "geometric",
  "imagePixel",
  "geographic",
  "threeDimensional",
] as const;
const RICH_ANSWER_COMPUTE_NEEDS = ["none", "lightDeterministic", "heavyOrExternal"] as const;
const RICH_ANSWER_PRECISION_NEEDS = ["illustrative", "quantitative", "measurementSensitive"] as const;
const RICH_ANSWER_ASSET_DEPENDENCIES = ["none", "currentSourceAssetRequired"] as const;

interface RichAnswerRepresentationNeeds {
  spatialDimension: typeof RICH_ANSWER_SPATIAL_DIMENSIONS[number];
  temporalBehavior: typeof RICH_ANSWER_TEMPORAL_BEHAVIORS[number];
  dataOrigin: typeof RICH_ANSWER_DATA_ORIGINS[number];
  coordinateFrame: typeof RICH_ANSWER_COORDINATE_FRAMES[number];
  computeNeed: typeof RICH_ANSWER_COMPUTE_NEEDS[number];
  precisionNeed: typeof RICH_ANSWER_PRECISION_NEEDS[number];
  assetDependency: typeof RICH_ANSWER_ASSET_DEPENDENCIES[number];
}

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

const RICH_ANSWER_CHART_KINDS = RICH_ANSWER_STANDARD_CHART_TYPES;

interface RichAnswerRendererRegistration {
  id: string;
  label: string;
  specVersion: string;
  validatorKind:
    | "chart"
    | "mathFunction"
    | "geometry2D"
    | "scene3D"
    | "spatialMap"
    | "imageOverlay";
  knowledgeShapes: readonly RichAnswerKnowledgeShape[];
  interactionActions: readonly (typeof RICH_ANSWER_INTERACTION_ACTIONS[number])[];
  interactionBindingKinds: readonly string[];
  standardKinds: readonly RichAnswerStandardChartType[];
  representationSupport: {
    spatialDimensions: readonly RichAnswerRepresentationNeeds["spatialDimension"][];
    temporalBehaviors: readonly RichAnswerRepresentationNeeds["temporalBehavior"][];
    dataOrigins: readonly RichAnswerRepresentationNeeds["dataOrigin"][];
    coordinateFrames: readonly RichAnswerRepresentationNeeds["coordinateFrame"][];
    computeNeeds: readonly RichAnswerRepresentationNeeds["computeNeed"][];
    precisionNeeds: readonly RichAnswerRepresentationNeeds["precisionNeed"][];
    assetDependencies: readonly RichAnswerRepresentationNeeds["assetDependency"][];
  };
  allowedSpecFields: readonly string[];
  allowedSeriesFields: readonly string[];
  forbiddenSpecFields: readonly string[];
  specGuidance: string;
  minimalSpecSkeleton: Record<string, unknown>;
  budgets: {
    maxNodes: number;
    maxSeries: number;
    maxDataPoints: number;
    maxArtifacts: number;
    maxBytes: number;
    maxWidth: number;
    maxHeight: number;
    maxAnimationFPS: number;
    maxInteractionLatencyMS: number;
    allowAnimation: boolean;
    allowWebGL: boolean;
    allowNetwork: boolean;
  };
}

const RICH_ANSWER_RENDERER_REGISTRATIONS: readonly RichAnswerRendererRegistration[] = [
  {
    id: "weibei.echarts.chart",
    label: "注册专业图表渲染器",
    specVersion: "weibei.chart.v1",
    validatorKind: "chart",
    knowledgeShapes: ["series", "distribution"],
    interactionActions: ["none", "select", "focusEvidence", "probe"],
    interactionBindingKinds: ["probe", "select"],
    standardKinds: RICH_ANSWER_CHART_KINDS,
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange"],
      dataOrigins: ["sourceObserved", "derivedFromSource"],
      coordinateFrames: ["categorical", "cartesian"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative"],
      assetDependencies: ["none"],
    },
    allowedSpecFields: [
      "chartKind",
      "title",
      "series",
      "xLabels",
      "xAxisLabel",
      "yAxisLabel",
      "caption",
      "focusEnabled",
      "binCount",
      "samples",
    ],
    allowedSeriesFields: ["name", "values", "xValues", "chartKind", "unit"],
    forbiddenSpecFields: [
      "rawOption",
      "option",
      "options",
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "query",
      "mutation",
      "url",
      "iframe",
    ],
    specGuidance:
      "只提交有语义的系列、分组标签、散点 xValues/values 数值对或直方图原始样本；坐标轴、布局、响应式与 Canvas 绘制由本地 ECharts 适配器负责。",
    minimalSpecSkeleton: {
      chartKind: "line",
      series: [{ name: "语义系列名", values: [0, 1, 2], unit: "真实单位" }],
      xLabels: ["状态一", "状态二", "状态三"],
      xAxisLabel: "横轴语义",
      yAxisLabel: "纵轴语义",
      caption: "这张图帮助用户检查什么",
      focusEnabled: true,
    },
    budgets: {
      maxNodes: LIMITS.richAnswerRenderPlanNodes,
      maxSeries: LIMITS.richAnswerRenderPlanSeries,
      maxDataPoints: LIMITS.richAnswerRenderPlanDataPoints,
      maxArtifacts: 0,
      maxBytes: LIMITS.richAnswerRenderPlanSpecBytes,
      maxWidth: 960,
      maxHeight: 640,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 120,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.math.function",
    label: "受限数学函数渲染器",
    specVersion: "weibei.math-function.v1",
    validatorKind: "mathFunction",
    knowledgeShapes: ["formula"],
    interactionActions: ["none", "adjust", "probe"],
    interactionBindingKinds: ["probe", "slider"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange"],
      dataOrigins: ["derivedFromSource", "deterministicSimulation"],
      coordinateFrames: ["cartesian"],
      computeNeeds: ["lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative"],
      assetDependencies: ["none"],
    },
    allowedSpecFields: [
      "title",
      "variable",
      "domain",
      "parameters",
      "expression",
      "xAxisLabel",
      "yAxisLabel",
      "caption",
      "probeEnabled",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "points",
      "samples",
      "series",
      "rawOption",
      "option",
      "options",
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
    ],
    specGuidance:
      "模型只提交受限表达式图（常数、变量、参数与白名单运算）、定义域和可调参数；不提交采样点、SVG path 或图表配置。本地渲染器负责自适应采样、间断切段、设备像素比和窄宽布局。",
    minimalSpecSkeleton: {
      title: "参数怎样改变函数",
      variable: "x",
      domain: { minimum: -4, maximum: 4 },
      parameters: [{ id: "p", label: "参数 p", value: 1, minimum: -3, maximum: 3, step: 0.1 }],
      expression: {
        rootNodeID: "root",
        nodes: [
          { id: "x", kind: "variable" },
          { id: "p", kind: "parameter", parameterID: "p" },
          { id: "root", kind: "operation", operation: "multiply", inputIDs: ["p", "x"] },
        ],
      },
      xAxisLabel: "x",
      yAxisLabel: "结果",
      probeEnabled: true,
    },
    budgets: {
      maxNodes: 64,
      maxSeries: 1,
      maxDataPoints: 1600,
      maxArtifacts: 0,
      maxBytes: LIMITS.richAnswerRenderPlanSpecBytes,
      maxWidth: 960,
      maxHeight: 640,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 120,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.geometry.2d",
    label: "受限二维几何与确定性实验渲染器",
    specVersion: "weibei.geometry-2d.v1",
    validatorKind: "geometry2D",
    knowledgeShapes: ["customGeometry", "process"],
    interactionActions: ["none", "adjust", "dragPoints", "probe", "select"],
    interactionBindingKinds: ["probe", "select", "slider", "toggle", "zoomPan"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange", "timeEvolution"],
      dataOrigins: ["derivedFromSource", "deterministicSimulation", "conceptual"],
      coordinateFrames: ["cartesian", "geometric"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative", "measurementSensitive"],
      assetDependencies: ["none"],
    },
    allowedSpecFields: [
      "title",
      "coordinateSpace",
      "points",
      "shapes",
      "controls",
      "readouts",
      "showAxes",
      "showGrid",
      "caption",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
      "pixelLayout",
    ],
    specGuidance:
      "提交点、线段、带箭头向量、多边形、有方向盒体、圆、角、轨迹、约束、离散状态、协调控件与语义读数的高层几何语义；状态可通过 visibleWhen 切换对象，不提交 SVG path 或像素布局。坐标换算、拖拽投影、状态联动和响应式绘制由本地适配器负责。",
    minimalSpecSkeleton: {
      title: "几何关系检查",
      coordinateSpace: { xMin: -1, xMax: 9, yMin: -1, yMax: 7, preserveAspectRatio: true },
      points: [
        { id: "A", label: "A", x: 0, y: 0, draggable: false },
        { id: "B", label: "B", x: 8, y: 0, draggable: false },
        { id: "C", label: "C", x: 4, y: 4, draggable: false },
      ],
      shapes: [
        { id: "AB", kind: "segment", from: "A", to: "B", label: "AB" },
        { id: "direction", kind: "vector", from: "A", to: "C", label: "方向" },
      ],
      controls: [{
        id: "state",
        label: "观察状态",
        value: 0,
        minimum: 0,
        maximum: 1,
        step: 1,
        options: [{ value: 0, label: "状态一" }, { value: 1, label: "状态二" }],
        presentation: "segmented",
        bindings: [],
      }],
      readouts: [
        { id: "length-ab", kind: "distance", label: "AB 长度", from: "A", to: "B", unit: "单位" },
        { id: "state-label", kind: "state", label: "当前状态", controlID: "state", options: [{ value: 0, label: "状态一" }, { value: 1, label: "状态二" }] },
      ],
      showAxes: true,
      showGrid: true,
      caption: "说明该图验证的条件而不是替代证明",
    },
    budgets: {
      maxNodes: 260,
      maxSeries: 0,
      maxDataPoints: 1200,
      maxArtifacts: 0,
      maxBytes: LIMITS.richAnswerRenderPlanSpecBytes,
      maxWidth: 960,
      maxHeight: 720,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 120,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.scene-3d",
    label: "受控三维场景渲染器",
    specVersion: "weibei.scene-3d.v1",
    validatorKind: "scene3D",
    knowledgeShapes: ["customGeometry", "spatialLayers", "process", "imageRegions"],
    interactionActions: ["none", "adjust", "toggleLayers", "probe", "select"],
    interactionBindingKinds: ["probe", "select", "slider", "toggle", "zoomPan"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["threeDimensional"],
      temporalBehaviors: ["static", "stateChange", "timeEvolution"],
      dataOrigins: ["derivedFromSource", "deterministicSimulation", "conceptual"],
      coordinateFrames: ["threeDimensional"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative"],
      assetDependencies: ["none"],
    },
    allowedSpecFields: [
      "title",
      "camera",
      "layers",
      "objects",
      "stateBinding",
      "states",
      "coordinateUnits",
      "bounds",
      "slices",
      "caption",
      "controls",
      "focusEnabled",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
      "modelUrl",
      "shader",
    ],
    specGuidance:
      "提交相机、坐标、点、折线、网格、曲面、分子、切片、图层与受控交互；比较多个结构或状态时，用 objects 承载共享对象，用 stateBinding.initial/control/label 与 states[].objects/readouts 切换状态。coordinateUnits 必须是 {x,y,z}，bounds 的 x/y/z 必须各自是 {min,max}；不要自行发明 controls 字段。默认使用本地确定性 Canvas 投影，不提交外链模型、着色器、WebGL 代码或装饰性三维。",
    minimalSpecSkeleton: {
      title: "空间结构观察",
      camera: { yaw: 35, pitch: 20, distance: 4.2, lookAt: [0, 0, 0], fov: 58 },
      layers: [{ id: "structure", title: "结构", visibleDefault: true }],
      objects: [],
      stateBinding: { initial: "state-a", control: "segmented", label: "比较状态" },
      states: [{
        id: "state-a",
        title: "状态 A",
        description: "用来源支持的空间关系说明这一状态",
        objects: [{
          id: "state-a-structure",
          kind: "molecule",
          layer: "structure",
          label: "空间结构",
          atoms: [
            { id: "center-a", element: "C", label: "中心原子", position: [0, 0, 0], role: "central" },
            { id: "terminal-a", element: "H", label: "成键原子", position: [1, 1, 1], role: "terminal" },
          ],
          bonds: [{ id: "bond-a", from: "center-a", to: "terminal-a", order: 1, style: "solid" }],
          electronDomains: [],
          angleMarkers: [],
          showAtomLabels: true,
          showBondLabels: false,
          showElectronDomains: true,
        }],
        readouts: [{ id: "state-a-reading", label: "关键读数", value: "来源支持的值" }],
      }],
      slices: [],
      controls: { allowLayerToggle: true, allowSlice: false, allowCameraDrag: true, allowReset: true, allowProbe: true },
      focusEnabled: true,
      caption: "旋转或聚焦时要帮助检查的空间关系",
    },
    budgets: {
      maxNodes: 24,
      maxSeries: 0,
      maxDataPoints: 3200,
      maxArtifacts: 0,
      maxBytes: LIMITS.richAnswerRenderPlanSpecBytes,
      maxWidth: 960,
      maxHeight: 720,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 160,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.spatial.map",
    label: "地图与空间图层渲染器",
    specVersion: "weibei.spatial.map.v1",
    validatorKind: "spatialMap",
    knowledgeShapes: ["spatialLayers", "causalSequence", "comparison"],
    interactionActions: ["none", "select", "toggleLayers", "probe"],
    interactionBindingKinds: ["probe", "select", "toggle", "zoomPan"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange"],
      dataOrigins: ["sourceObserved", "derivedFromSource", "sourceAsset", "conceptual"],
      coordinateFrames: ["cartesian", "geographic"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative", "measurementSensitive"],
      assetDependencies: ["none", "currentSourceAssetRequired"],
    },
    allowedSpecFields: [
      "title",
      "coordinateMode",
      "crs",
      "coordinateHint",
      "mapAsset",
      "bounds",
      "layers",
      "features",
      "scaleBar",
      "controls",
      "caption",
      "focusEnabled",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
      "tileUrl",
    ],
    specGuidance:
      "提交本地底图引用或无底图的示意空间，以及点、线、面、标签、图层、比例尺和显隐绑定；图形与标签必须共享 visibilityGroup 或 bindTo。",
    minimalSpecSkeleton: {
      title: "空间证据观察",
      coordinateMode: "schematic",
      coordinateHint: "坐标来自当前材料；若依赖原图，必须替换 CURRENT_MATERIAL_ASSET_ID",
      mapAsset: { kind: "assetRef", source: "CURRENT_MATERIAL_ASSET_ID", label: "当前材料底图" },
      layers: [{ id: "evidence", title: "证据层", visibleDefault: true }],
      features: [
        { id: "route", kind: "line", layer: "evidence", visibilityGroup: "route", points: [{ x: 0.2, y: 0.3 }, { x: 0.8, y: 0.7 }], label: "路线" },
        { id: "route-label", kind: "label", layer: "evidence", visibilityGroup: "route", bindTo: "route", x: 0.5, y: 0.5, text: "路线证据" },
      ],
      scaleBar: { enabled: false, label: "比例尺", targetPixels: 120 },
      controls: { allowPan: true, allowZoom: true, allowLayerToggle: true, allowReset: true, probeEnabled: true },
      focusEnabled: true,
      caption: "图形与标签共享显隐状态",
    },
    budgets: {
      maxNodes: 280,
      maxSeries: 0,
      maxDataPoints: 8000,
      maxArtifacts: 2,
      maxBytes: 1_500_000,
      maxWidth: 960,
      maxHeight: 720,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 140,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
  {
    id: "weibei.image.overlay",
    label: "图像覆盖与观察渲染器",
    specVersion: "weibei.image-overlay.v1",
    validatorKind: "imageOverlay",
    knowledgeShapes: ["imageRegions", "spatialLayers", "comparison", "customGeometry"],
    interactionActions: ["none", "select", "toggleLayers", "probe"],
    interactionBindingKinds: ["annotation", "probe", "select", "slider", "toggle", "zoomPan"],
    standardKinds: [],
    representationSupport: {
      spatialDimensions: ["twoDimensional"],
      temporalBehaviors: ["static", "stateChange"],
      dataOrigins: ["sourceObserved", "derivedFromSource", "sourceAsset"],
      coordinateFrames: ["imagePixel"],
      computeNeeds: ["none", "lightDeterministic"],
      precisionNeeds: ["illustrative", "quantitative", "measurementSensitive"],
      assetDependencies: ["currentSourceAssetRequired"],
    },
    allowedSpecFields: [
      "title",
      "image",
      "objectFit",
      "measurement",
      "layers",
      "annotations",
      "comparison",
      "caption",
      "showReadout",
    ],
    allowedSeriesFields: [],
    forbiddenSpecFields: [
      "script",
      "html",
      "css",
      "svg",
      "svgPath",
      "pathD",
      "javascript",
      "url",
      "iframe",
    ],
    specGuidance:
      "提交当前材料中的本地位图引用、归一化坐标叠层、测量、批注与对照；line 可用 start/end 表示线段，也可用 points 表示折线。feature 默认使用 emphasis=subtle、tone=earth；只把少量关键证据设为 normal/strong，避免满图粗框与编号遮挡。图层、标签、批注和读数必须共享显隐状态，禁止外链和脚本型图片。",
    minimalSpecSkeleton: {
      title: "原图观察",
      image: { kind: "assetRef", source: "CURRENT_MATERIAL_ASSET_ID", label: "当前材料图像" },
      objectFit: "contain",
      measurement: { unit: "px", precision: 1 },
      layers: [{
        id: "observation",
        title: "观察层",
        visibleDefault: true,
          features: [{ id: "focus-region", kind: "rect", label: "观察区域", box: { x: 0.2, y: 0.2, width: 0.4, height: 0.3 }, emphasis: "subtle", tone: "earth" }],
        annotation: "说明该叠层怎样帮助判断",
      }],
      annotations: [{ id: "focus-note", layer: "observation", point: { x: 0.4, y: 0.35 }, text: "观察重点", color: "#8f4638" }],
      caption: "叠层坐标均为相对原图的归一化坐标",
      showReadout: false,
    },
    budgets: {
      maxNodes: 180,
      maxSeries: 0,
      maxDataPoints: 1200,
      maxArtifacts: 2,
      maxBytes: 1_500_000,
      maxWidth: 960,
      maxHeight: 720,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 140,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
    },
  },
];

const RICH_ANSWER_RENDERER_REGISTRATION_BY_ID = new Map(
  RICH_ANSWER_RENDERER_REGISTRATIONS.map((registration) => [registration.id, registration]),
);

function matchingRichAnswerRendererRegistrations(
  knowledgeShapes: readonly string[],
  representationNeeds?: RichAnswerRepresentationNeeds,
  sourceMedium?: string,
  knowledgeNatures: readonly string[] = [],
  knowledgeObjects: readonly string[] = [],
  knowledgeRelations: readonly string[] = [],
  knowledgeProcesses: readonly string[] = [],
  hasCurrentSourceAsset = false,
): RichAnswerRendererRegistration[] {
  const shapes = new Set(knowledgeShapes);
  const natures = new Set(knowledgeNatures);
  const semanticText = [
    ...knowledgeObjects,
    ...knowledgeRelations,
    ...knowledgeProcesses,
  ].join(" ").normalize("NFKC").toLocaleLowerCase();
  const asksForThreeDimensions =
    representationNeeds?.spatialDimension === "threeDimensional" ||
    representationNeeds?.coordinateFrame === "threeDimensional" ||
    (
      natures.has("spatialStructure") &&
      /(?:分子|构型|电子域|键角|三维|立体|空间几何|轨道|3d|molecule|vsepr|tetrahedral|trigonal|orbital)/iu.test(semanticText)
    );
  const asksForGeometry =
    representationNeeds?.coordinateFrame === "geometric" ||
    /(?:几何|三角|相似|全等|角度|圆|轨迹|直线|约束|geometry|triangle|angle|circle)/iu.test(semanticText);
  const asksForMap =
    sourceMedium === "map" ||
    representationNeeds?.coordinateFrame === "geographic" ||
    /(?:地图|河流|坡向|等高线|地形|区域|路线|经纬|空间分布|map|river|contour|geograph)/iu.test(semanticText);
  const asksForImageOverlay =
    hasCurrentSourceAsset &&
    (
      sourceMedium === "image" ||
      representationNeeds?.coordinateFrame === "imagePixel" ||
      natures.has("imageObservation") ||
      /(?:图像|构图|比例|覆盖|叠层|批注|测量|原图|image|overlay|composition)/iu.test(semanticText)
    );
  return RICH_ANSWER_RENDERER_REGISTRATIONS.filter((registration) => {
    if (registration.id === "weibei.image.overlay" && !hasCurrentSourceAsset) return false;
    if (registration.id === "weibei.scene-3d" && asksForThreeDimensions) return true;
    if (registration.id === "weibei.geometry.2d" && asksForGeometry) return true;
    if (registration.id === "weibei.spatial.map" && asksForMap) return true;
    if (registration.id === "weibei.image.overlay" && asksForImageOverlay) return true;
    if (registration.knowledgeShapes.some((shape) => shapes.has(shape))) return true;
    if (!representationNeeds) return false;
    return false;
  });
}

function richAnswerRendererInteractionCoverage(
  registration: RichAnswerRendererRegistration,
  interactions: readonly string[],
) {
  const requested = interactions.filter((interaction) => interaction !== "none");
  const supported = requested.filter((interaction) => registration.interactionActions.includes(
    interaction as typeof RICH_ANSWER_INTERACTION_ACTIONS[number],
  ));
  const unsupported = requested.filter((interaction) => !supported.includes(interaction));
  return {
    requested,
    supported,
    unsupported,
    fullySupported: unsupported.length === 0,
  };
}

function richAnswerRendererRepresentationCoverage(
  registration: RichAnswerRendererRegistration,
  needs?: RichAnswerRepresentationNeeds,
) {
  if (!needs) {
    return {
      requested: null,
      unsupported: [] as string[],
      fullySupported: true,
    };
  }
  const support = registration.representationSupport;
  const unsupported = [
    !support.spatialDimensions.includes(needs.spatialDimension)
      ? `spatialDimension:${needs.spatialDimension}`
      : undefined,
    !support.temporalBehaviors.includes(needs.temporalBehavior)
      ? `temporalBehavior:${needs.temporalBehavior}`
      : undefined,
    !support.dataOrigins.includes(needs.dataOrigin)
      ? `dataOrigin:${needs.dataOrigin}`
      : undefined,
    !support.coordinateFrames.includes(needs.coordinateFrame)
      ? `coordinateFrame:${needs.coordinateFrame}`
      : undefined,
    !support.computeNeeds.includes(needs.computeNeed)
      ? `computeNeed:${needs.computeNeed}`
      : undefined,
    !support.precisionNeeds.includes(needs.precisionNeed)
      ? `precisionNeed:${needs.precisionNeed}`
      : undefined,
    !support.assetDependencies.includes(needs.assetDependency)
      ? `assetDependency:${needs.assetDependency}`
      : undefined,
  ].filter((value): value is string => value !== undefined);
  return {
    requested: needs,
    unsupported,
    fullySupported: unsupported.length === 0,
  };
}

function richAnswerRendererMinimalSpecSkeleton(
  registration: RichAnswerRendererRegistration,
  allowedAssetIDs: readonly string[],
): Record<string, unknown> {
  const replacementAssetID = allowedAssetIDs[0];
  const replaceAssetPlaceholder = (value: unknown): unknown => {
    if (value === "CURRENT_MATERIAL_ASSET_ID") {
      return replacementAssetID ?? value;
    }
    if (Array.isArray(value)) return value.map(replaceAssetPlaceholder);
    if (!isRecord(value)) return value;
    return Object.fromEntries(
      Object.entries(value).map(([field, child]) => [field, replaceAssetPlaceholder(child)]),
    );
  };
  const skeleton = replaceAssetPlaceholder(registration.minimalSpecSkeleton);
  if (!isRecord(skeleton)) return {};
  if (registration.id === "weibei.spatial.map" && replacementAssetID === undefined) {
    return {
      ...skeleton,
      coordinateHint: "当前没有可渲染底图；使用来源支持的示意坐标，不得伪造地理精度",
      mapAsset: { kind: "none" },
    };
  }
  return skeleton;
}

function richAnswerRendererNestedFieldContracts(
  registration: RichAnswerRendererRegistration,
): Record<string, unknown> | undefined {
  if (registration.id === "weibei.echarts.chart") {
    return {
      series: {
        requiredFields: ["name", "values"],
        optionalFields: ["xValues", "chartKind", "unit"],
        scatterRule: "scatter 的每个 series 必须提交等长的 xValues/values，且不能提交 xLabels。",
        categoricalRule: "line/bar/area/mixed 不提交 xValues，series.values 必须与 xLabels 等长。",
      },
    };
  }
  if (registration.id === "weibei.geometry.2d") {
    return {
      controls: {
        presentation: ["slider", "segmented"],
        bindingVariants: [
          {
            kind: "pointCoordinate",
            requiredFields: ["kind", "pointID", "axis"],
            axis: ["x", "y"],
            optionalFields: ["multiplier", "offset", "minimum", "maximum"],
          },
          {
            kind: "pointOnConstraint",
            requiredFields: ["kind", "pointID"],
            optionalFields: ["multiplier", "offset"],
          },
          {
            kind: "circleRadius",
            requiredFields: ["kind", "shapeID"],
            optionalFields: ["multiplier", "offset", "minimum", "maximum"],
          },
        ],
        unboundControlRule:
          "bindings 可以为空，但该控件必须由某个 shape.visibleWhen 或 state readout 的 controlID 使用；bindings 中每一项都必须是对象，不能写字符串。",
      },
    };
  }
  return undefined;
}

function richAnswerRendererCapabilityDeclarations(
  knowledgeShapes: readonly string[],
  interactions: readonly string[],
  representationNeeds?: RichAnswerRepresentationNeeds,
  sourceMedium?: string,
  knowledgeNatures: readonly string[] = [],
  knowledgeObjects: readonly string[] = [],
  knowledgeRelations: readonly string[] = [],
  knowledgeProcesses: readonly string[] = [],
  allowedAssetIDs: readonly string[] = [],
): Array<Record<string, unknown>> {
  return matchingRichAnswerRendererRegistrations(
    knowledgeShapes,
    representationNeeds,
    sourceMedium,
    knowledgeNatures,
    knowledgeObjects,
    knowledgeRelations,
    knowledgeProcesses,
    allowedAssetIDs.length > 0,
  ).map((registration) => {
    const interactionCoverage = richAnswerRendererInteractionCoverage(registration, interactions);
    const representationCoverage = richAnswerRendererRepresentationCoverage(
      registration,
      representationNeeds,
    );
    return {
      id: registration.id,
      label: registration.label,
      specVersion: registration.specVersion,
      knowledgeShapes: registration.knowledgeShapes,
      interactionActions: registration.interactionActions,
      interactionBindingKinds: registration.interactionBindingKinds,
      requestedInteractionCoverage: interactionCoverage,
      requestedRepresentationCoverage: representationCoverage,
      representationSupport: registration.representationSupport,
      standardKinds: registration.standardKinds,
      selectionGuidance:
        "这是本轮可用候选，不是固定答案。完全覆盖只表示它能诚实承载所需表达；仍需与成熟深组件、长尾组合和文本比较学习增益、独特联动、来源资产、精度与性能。",
      modelSpecContract: {
        allowedTopLevelSpecFields: registration.allowedSpecFields,
        allowedSeriesFields: registration.allowedSeriesFields,
        nestedFieldContracts: richAnswerRendererNestedFieldContracts(registration),
        forbiddenFields: registration.forbiddenSpecFields,
        guidance: registration.specGuidance,
        minimalSpecSkeleton: richAnswerRendererMinimalSpecSkeleton(
          registration,
          allowedAssetIDs,
        ),
        placeholderRule:
          "骨架只展示字段形状；CURRENT_MATERIAL_ASSET_ID 必须替换为本轮 sourceBindings 中真实可用的当前材料资产 ID，所有示例值都必须换成来源支持的语义与数据。",
        rule: "模型只提交高层 spec、interactionBindings、sourceBindings、fallback 与 qualityBudget；不得提交 raw option、脚本、HTML、SVG path、外链或任意渲染代码。",
      },
      qualityBudgetCeiling: registration.budgets,
    };
  });
}
const COMPOSABLE_PRIMITIVE_CATALOG = [
  "ui 可组合原语：先确定 rootID 作为回答内联块的根，再组织 nodes + datasets + bindings；所有节点必须从 rootID 可达，用于目录里没有贴合深组件或注册专业渲染器的长尾问题，不生成 HTML/SVG。",
  `硬预算：每个 scene 最多 ${LIMITS.richAnswerUINodes} 个 nodes；所有 datasets 合计最多 ${LIMITS.richAnswerUIRows} 行；最多 ${LIMITS.richAnswerUIBindings} 个 bindings。函数或过程曲线优先共享横轴并使用少量有代表性的采样点，不要为两条曲线各复制高密度数据。`,
  "容器：vstack|hstack|zstack|grid|panel；画布：canvas；正文内优先透明容器，不把 panel 堆成卡片墙。",
  "图元：axis|line|path|point|area|shape|bar|dotMatrix|vector|region|image|label；统一使用归一化坐标与魏碑主题令牌。label 是画布标注，必须引用带 label 的 dataset.rows；同一 dataset 的图形受 binding 控制时，label 必须共享同一 bindingID，不能图形隐藏后留下孤立标签；画布外说明文字使用 text。",
  "函数曲线与真实数据关系本来适合 line/path/point/metric；但物体、空间、过程、机制、证据链不能只剩曲线和读数，必须加入 shape/vector/region/area/sequence/image/bar/dotMatrix 等能表达对象或状态的通用图元。",
  "非过程题不能只用 sequence、metric、text、label 或 grid 改排版；数量、空间、机制、证据、图像、比较和计算题，可绑定控件必须驱动 line/path/point/area/shape/bar/dotMatrix/vector 等非文字图元或空间编码产生可检查变化。",
  "图像材料：当路线、区域、比例或构图判断依赖原图位置时，必须把 weibei_context.course.catalog 中当前材料的 item.id 写入 image.assetID，并在对应 evidenceLedger.assetIDs 中声明，再作为 canvas 底图叠加 path/region/point/label；只有材料已给出完整数值几何时才可重绘，并明确标成示意关系。",
  "序列：sequence 用于通用步骤、证据链、周期节点、过程状态和时间节点；必须引用 dataset，至少两行，每行 label 是用户可见语义，bindingID 可选；不要自造 stepList/list/items 字段。",
  "控件：slider|toggle|scrubber|probe 通过 bindingID 连接共享数值状态；select/reset 用作选择或重置入口，不冒充数值 binding。最多两个主要控件，但允许多个联动读数与图元。每个 binding 必须同时连接一个可见可绑定控件和至少一个可达的 metric、sequence 或视觉图元，不能只放一个不会改变画面的滑杆。",
  "数据：dataset.rows 提供 x/y、可选 x2/y2、value/result/label；带 bindingID 的图元和 metric 会按 value 插值或选择当前行。",
  "语义：决定结论的条件、变量、方向或关系必须出现在可见的 label/text/axis/dataset 标签里，并随对应图元或状态可检查；不能只画无标注路径，也不能只在 UI 外正文里解释。",
  "证据：evidence 节点与数据行的 evidenceIDs 必须来自本轮 evidenceLedger；只做定位，不复制原文。",
].join("\n");

const OPENUI_STATE_SHAPE_GUIDANCE = [
  "普通组件继续使用数字状态，例如 `$focus = 0`。",
  "组件的 name/stateName 参数是状态标识，不是界面标题：它必须与紧随其后的 $状态引用同名，例如 `ParameterReadout(\"timeIndex\", $timeIndex, \"当前 t/τ\")`，不能写成 `ParameterReadout(\"当前 t/τ\", $timeIndex, ...)`。",
  "MetricItem 的 value 是带引号的静态显示字符串；需要随数值状态变化时使用 ParameterReadout，或用 LinkedDataChart/其他签名明确支持的状态组件，不要把数字或 $状态直接塞进 MetricItem.value。",
  "空间图层允许字符串数组与字符串状态，例如 `$visible = [\"terrain\", \"route\"]`、`$selected = \"city-a\"`；名称参数必须分别写成 \"visible\" 与 \"selected\"。",
  "依赖传导允许数字数组状态，例如 `$inputs = [8, 18, 11]`；数组顺序必须与 FlowAssumption 引用顺序一致。",
  "数组和字符串状态只用于签名明确要求的组件；不要把它们当成任意数据通道。",
].join("\n");

const RICH_ANSWER_FAMILY_CONTRACT = [
  "富回答 schemaVersion 必须为 2；每个 scene 必须且只能提交 program、renderPlan、ui 三条表达出口之一。program 是深组件程序；renderPlan 是注册专业渲染器计划；ui 是可组合原语树。",
  "富回答先过内容与专业性，再过视觉。提交前必须核对结论、公式、单位、数值、方向、因果边界和学科术语；不能由本轮材料或确定性内核验证的数字、关系和模拟结果不得让界面假装计算，也不得用漂亮图形掩盖知识错误。",
  "需要富回答时，先形成表达意图：用户真正卡住的判断、正文难呈现的知识对象/关系/过程、初始状态应出现的现象、一次操作前后应改变的状态和真实证据；再调用目录选择能力。不要先选图或组件再倒填内容。",
  "生成式 UI 是 Agent 回答流中的生成式视觉体验块，不是第二篇回答、独立小网页或完整网页外壳。它可以按问题需要组合多个视觉、控件、读数、局部解释和实验步骤。",
  "narrative 是本次富回答最终显示的完整正文：建议先给结论、就近标注真实来源，并用场景标记把视觉体验插在最有帮助的位置。优先用自然段连接解释与场景，避免页面级标题和标题—摘要—结论式第二篇文章；工具成功后不得再生成一份不同正文。",
  `提交富回答前必须先调用 ${RICH_ANSWER_CATALOG_TOOL}，让魏碑按本轮学习动作、知识形状、来源媒介、直接操作和表面重量返回相关深组件、注册专业渲染器与通用原语提示；组件目录可以再次调用，但不得绕过。`,
  "优先选择最贴合问题的表达出口：标准图表或统计形状匹配注册专业渲染器时先用 renderPlan；只有深组件能提供渲染器没有的领域实验或状态联动时才用 program；两者都不贴合的长尾组合才用 ui。",
  "program 中模型负责选择深组件、布局、数据、$state 反应变量和动作；renderPlan 中模型只给注册渲染器的高层 spec、绑定、来源和质量预算；ui 中模型负责组合容器、画布图元、数据集与 bindings；魏碑本地运行时统一负责渲染、联动与风格。",
  "ui 的画面必须能独立读出支撑结论的关键语义：用可见标签标明决定性条件、变量、方向、对应关系和当前状态，并把标签与实际图元、数据行或 binding 联动；禁止只画漂亮但无语义的线、点和区域。",
  "expressionPlan.knowledgeObjects 中声明的关键数值、比例、公式片段、采样尺寸和阈值，建议在 ui 的可见 label/text/axis/dataset 标签里原样或等价出现；不要只把它们留在计划或 narrative。",
  "sequence 单独只适合真实过程或状态演进；数量、空间、机制、证据、图像、比较和计算题必须让可绑定控件改变非文字图元或空间编码，不能只把正文拆成步骤、指标、卡片、表格或时间线。",
  "图像、地图和设计题若结论依赖原图中的空间位置，ui 必须使用 weibei_context.course.catalog 中当前材料的 item.id 作为 image.assetID，在对应 evidenceLedger.assetIDs 中声明，并作为画布底图叠加标注；不得脱离原图凭空重画路线、区域、比例或构图。材料已提供完整数值坐标时可画明确标注为示意的关系图。",
  "不要用固定的一图一控件或单场景模板限制表达。单个问题默认只提交一个最有帮助的 scene、一个主要操作和必要联动读数；相互关联的视觉、控件、读数和步骤优先组合进同一个 scene，只有两个体验确实独立时才拆分。每个元素都必须服务当前问题，不得用装饰、重复内容或穷举节点凑页面。",
  "保持多学科、多形态：根据知识对象选择函数图、数据图、执行轨、论证阅读、因果时间线、坐标实验、平衡实验或其他目录能力，不要把不同问题压成同一种外观。",
  "禁止在 program 中重复 Agent 正文的整套标题、摘要、结论或 evidenceLedger.excerpt，也不得从头重讲同一答案。RichAnswerRoot 与 LearningStage 只提供体验块内部的局部导向；证据组件只承担来源定位和回原文。",
  "NarrativeBlock 允许呈现局部状态解释、读数含义、诊断或互动反馈，但不得复述正文、扩写背景、另做摘要或再下一个完整结论。",
  "placement 与 preferredSurface 应按体验复杂度选择 inline、expanded 或 focus。复杂体验可以自然展开或进入专注模式；专注模式仍然是同一回答的延展，不得变成独立网页。",
  "program 只允许使用本轮目录工具返回的组件签名；每行只能声明一个有限状态或一个组件。状态默认是数字；只有签名明确要求时才可使用字符串、数字数组或字符串数组。参数必须严格匹配签名。不得自造组件、嵌套组件调用、SVG path、HTML、CSS、JavaScript、Query、Mutation、URL、iframe 或外部资源。",
  "program 的组件引用必须先声明后引用；引用数组使用 [step1, step2] 这种不加引号的组件 id，不能写成字符串数组。枚举参数只能使用目录指导列出的固定值，不能把公式或自然语言塞进枚举位。",
  "文字已经足够时不要调用富回答；禁止使用网站导航、页面级页头、功能菜单、营销区块或其他完整网页外壳，也不要用第二套标题—摘要—结论结构重新包装正文。",
  "renderPlan 必须使用本轮目录返回的 renderer 与 specVersion；标准图表只提交 chartKind、title、series(name, values, xValues?, chartKind?, unit?)、xLabels、xAxisLabel、yAxisLabel、caption、focusEnabled、binCount、samples 这些高层字段，不提交 raw option、脚本、HTML、SVG path 或外链。scatter 用等长 xValues/values 数值对；line/bar/area/mixed 使用 xLabels；mixed 图必须给每个 series 声明相同 unit；跨单位混合图需要另一个已注册渲染器。",
  "program 的函数图、联动数据图和双点坐标实验由 Canvas 内核计算，不要提交采样路径；program、renderPlan 与 ui 都无法诚实表达对象时，才使用正常文本，不要假造可视化。",
  "压力样例不是场景模板。先选择知识对象，再组合不同组件；禁止复用样例标题、数据和整套结构。",
  "所有状态名和组件 id 必须唯一；$状态、组件引用和 root 组件树必须完整可达，不能有重复、悬空、循环或孤立声明。",
  "EvidenceSnippet、ArgumentUnit、CausalEvent、SpatialPoint 中的 evidenceID 必须属于 scene.evidenceIDs，并与本轮 evidenceLedger 中的真实材料对应；普通文本里出现 id 不算证据绑定。",
  "工具会在拒绝 program 时批量返回场景、行列、预期组件签名和修正动作。按完整诊断修正；仍有遗漏时可再修一轮，不要用改写字符串绕过校验。",
  "工具拒绝富回答时会返回 weibei.rich_answer.repair_fault；必须保留其中的 code、jsonPath 与 humanFixHint，并按 replanningFeedback 在 program、renderPlan 与 ui 之间重新选择或修正后完整重发 RichAnswerUI。不能解释原因代替提交，也不能在坏树基础上局部 patch。remainingAttempts 为 0 时停止富回答并诚实使用普通文本；正文只回答用户问题和真实限制，不得提富回答校验、协议失败、repair_fault、payload 或内部工具错误。",
  OPENUI_STATE_SHAPE_GUIDANCE,
  COMPOSABLE_PRIMITIVE_CATALOG,
].join("\n");

const richAnswerIdentifierSchema = Type.String({ minLength: 1, maxLength: LIMITS.identifier });
const richAnswerPointSchema = Type.Object(
  {
    x: Type.Number(),
    y: Type.Number(),
  },
  { additionalProperties: true },
);
const richAnswerRegionSchema = Type.Object(
  {
    x: Type.Number({ minimum: 0, maximum: 1 }),
    y: Type.Number({ minimum: 0, maximum: 1 }),
    width: Type.Number({ exclusiveMinimum: 0, maximum: 1 }),
    height: Type.Number({ exclusiveMinimum: 0, maximum: 1 }),
  },
  { additionalProperties: true },
);
const richAnswerAxisSchema = Type.Object(
  {
    label: Type.String({ minLength: 1, maxLength: 200 }),
    minimum: Type.Number(),
    maximum: Type.Number(),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 64 })),
  },
  { additionalProperties: true },
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
  { additionalProperties: true },
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
  { additionalProperties: true },
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
  { additionalProperties: true },
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
    additionalProperties: true,
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
  { additionalProperties: true },
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
  { additionalProperties: true },
);
const richAnswerUIDatasetSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    rows: Type.Array(richAnswerUIDataRowSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerUIRows,
    }),
  },
  { additionalProperties: true },
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
  { additionalProperties: true },
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
    bindingID: Type.Optional(richAnswerIdentifierSchema),
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
const richAnswerRenderPlanChartSeriesSchema = Type.Object(
  {
    name: Type.String({ minLength: 1, maxLength: 80 }),
    values: Type.Array(Type.Number(), {
      minItems: 1,
      maxItems: LIMITS.richAnswerRenderPlanDataPoints,
    }),
    xValues: Type.Optional(
      Type.Array(Type.Number(), {
        minItems: 1,
        maxItems: LIMITS.richAnswerRenderPlanDataPoints,
      }),
    ),
    chartKind: Type.Optional(
      Type.Union([Type.Literal("line"), Type.Literal("bar")]),
    ),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 24 })),
  },
  { additionalProperties: false },
);
const richAnswerRenderPlanChartSpecSchema = Type.Object(
  {
    chartKind: Type.Union(RICH_ANSWER_CHART_KINDS.map((value) => Type.Literal(value))),
    title: Type.String({ minLength: 1, maxLength: 120 }),
    series: Type.Optional(
      Type.Array(richAnswerRenderPlanChartSeriesSchema, {
        maxItems: LIMITS.richAnswerRenderPlanSeries,
      }),
    ),
    xLabels: Type.Optional(
      Type.Array(Type.String({ minLength: 1, maxLength: 80 }), {
        maxItems: LIMITS.richAnswerRenderPlanDataPoints,
      }),
    ),
    xAxisLabel: Type.Optional(Type.String({ minLength: 1, maxLength: 80 })),
    yAxisLabel: Type.Optional(Type.String({ minLength: 1, maxLength: 80 })),
    caption: Type.Optional(Type.String({ minLength: 1, maxLength: 220 })),
    focusEnabled: Type.Optional(Type.Boolean()),
    binCount: Type.Optional(Type.Integer({ minimum: 3, maximum: 60 })),
    samples: Type.Optional(
      Type.Array(Type.Number(), {
        minItems: 1,
        maxItems: LIMITS.richAnswerRenderPlanDataPoints,
      }),
    ),
  },
  {
    additionalProperties: false,
    description:
      "注册专业渲染器的高层图表 spec；series 只允许 name、values、xValues、chartKind、unit。scatter 用等长 xValues/values 数值对且不提交 xLabels；line/bar/area/mixed 使用 xLabels，mixed 图每个 series 必须声明同一个 unit。不得给 raw option、script、HTML、SVG path 或渲染器私有配置。",
  },
);
const richAnswerMathFunctionParameterSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    label: Type.String({ minLength: 1, maxLength: 80 }),
    value: Type.Number(),
    minimum: Type.Number(),
    maximum: Type.Number(),
    step: Type.Number({ exclusiveMinimum: 0 }),
    unit: Type.Optional(Type.String({ minLength: 1, maxLength: 24 })),
  },
  { additionalProperties: false },
);
const richAnswerMathOperationSchema = Type.Union(
  [
    "abs",
    "add",
    "cos",
    "divide",
    "exp",
    "log",
    "multiply",
    "negate",
    "power",
    "sin",
    "sqrt",
    "subtract",
    "tan",
  ].map((value) => Type.Literal(value)),
);
const richAnswerMathFunctionExpressionNodeSchema = Type.Union([
  Type.Object(
    { id: richAnswerIdentifierSchema, kind: Type.Literal("constant"), value: Type.Number() },
    { additionalProperties: false },
  ),
  Type.Object(
    { id: richAnswerIdentifierSchema, kind: Type.Literal("variable") },
    { additionalProperties: false },
  ),
  Type.Object(
    {
      id: richAnswerIdentifierSchema,
      kind: Type.Literal("parameter"),
      parameterID: richAnswerIdentifierSchema,
    },
    { additionalProperties: false },
  ),
  Type.Object(
    {
      id: richAnswerIdentifierSchema,
      kind: Type.Literal("operation"),
      operation: richAnswerMathOperationSchema,
      inputIDs: Type.Array(richAnswerIdentifierSchema, { minItems: 1, maxItems: 2 }),
    },
    { additionalProperties: false },
  ),
]);
const richAnswerMathFunctionSpecSchema = Type.Object(
  {
    title: Type.String({ minLength: 1, maxLength: 120 }),
    variable: Type.String({ minLength: 1, maxLength: 12 }),
    domain: Type.Object(
      {
        minimum: Type.Number(),
        maximum: Type.Number(),
      },
      { additionalProperties: false },
    ),
    parameters: Type.Optional(
      Type.Array(richAnswerMathFunctionParameterSchema, { maxItems: 4 }),
    ),
    expression: Type.Object(
      {
        rootNodeID: richAnswerIdentifierSchema,
        nodes: Type.Array(richAnswerMathFunctionExpressionNodeSchema, {
          minItems: 1,
          maxItems: 64,
        }),
      },
      { additionalProperties: false },
    ),
    xAxisLabel: Type.Optional(Type.String({ minLength: 1, maxLength: 80 })),
    yAxisLabel: Type.Optional(Type.String({ minLength: 1, maxLength: 80 })),
    caption: Type.Optional(Type.String({ minLength: 1, maxLength: 220 })),
    probeEnabled: Type.Optional(Type.Boolean()),
  },
  {
    additionalProperties: false,
    description:
      "受限函数 spec。expression 使用带 id 的表达式图；模型不提交采样点、裸公式代码、SVG path 或图表 option。",
  },
);
const richAnswerRenderPlanSpecSchema = Type.Union([
  richAnswerRenderPlanChartSpecSchema,
  richAnswerMathFunctionSpecSchema,
  Type.Record(Type.String({ minLength: 1, maxLength: 120 }), Type.Unknown(), {
    minProperties: 1,
    maxProperties: 24,
    description:
      "其他注册专业渲染器的高层 JSON spec。具体允许字段、禁止字段、预算与最小骨架以 weibei_ui_catalog 返回的 matchingRenderers.modelSpecContract 为准。",
  }),
]);
const richAnswerRenderPlanInteractionBindingSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.Union(
      [
        "annotation",
        "brush",
        "picker",
        "playPause",
        "probe",
        "scrubber",
        "select",
        "slider",
        "sourceJump",
        "stateReveal",
        "step",
        "toggle",
        "zoomPan",
      ].map((value) => Type.Literal(value)),
    ),
    target: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerRenderPlanTarget }),
    stateKey: Type.Optional(Type.String({ minLength: 1, maxLength: 120 })),
    actionName: Type.Optional(Type.String({ minLength: 1, maxLength: 120 })),
    knowledgeStateEffect: Type.Optional(
      Type.String({ minLength: 1, maxLength: LIMITS.richAnswerRenderPlanText }),
    ),
  },
  { additionalProperties: false },
);
const richAnswerRenderPlanSourceBindingSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    evidenceID: richAnswerIdentifierSchema,
    target: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerRenderPlanTarget }),
    role: Type.String({ minLength: 1, maxLength: 80 }),
    requiredForFallback: Type.Boolean(),
  },
  { additionalProperties: false },
);
const richAnswerRenderPlanArtifactRefSchema = Type.Object(
  {
    id: richAnswerIdentifierSchema,
    kind: Type.String({ minLength: 1, maxLength: 80 }),
    mimeType: Type.String({ minLength: 1, maxLength: 120 }),
    role: Type.String({ minLength: 1, maxLength: 80 }),
    width: Type.Optional(Type.Integer({ minimum: 1, maximum: 20_000 })),
    height: Type.Optional(Type.Integer({ minimum: 1, maximum: 20_000 })),
    sizeBytes: Type.Optional(Type.Integer({ minimum: 0, maximum: 2_000_000 })),
    checksum: Type.Optional(Type.String({ minLength: 64, maxLength: 64 })),
    summary: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })),
    metadata: Type.Optional(Type.Record(Type.String({ minLength: 1, maxLength: 80 }), Type.Unknown())),
  },
  { additionalProperties: false },
);
const richAnswerRenderPlanFallbackSchema = Type.Object(
  {
    mode: Type.Union(
      ["narrativeOnly", "simplifiedRenderer", "staticSnapshot"].map((value) => Type.Literal(value)),
    ),
    reason: Type.String({ minLength: 1, maxLength: 600 }),
    text: Type.String({ minLength: 1, maxLength: LIMITS.richAnswerNarrative }),
    renderer: Type.Optional(Type.String({ minLength: 1, maxLength: 160 })),
    artifactID: Type.Optional(richAnswerIdentifierSchema),
    preservesSourceBinding: Type.Boolean(),
  },
  { additionalProperties: false },
);
const richAnswerRenderPlanQualityBudgetSchema = Type.Object(
  {
    maxNodes: Type.Optional(Type.Integer({ minimum: 1, maximum: LIMITS.richAnswerRenderPlanNodes })),
    maxDataPoints: Type.Optional(Type.Integer({ minimum: 1, maximum: LIMITS.richAnswerRenderPlanDataPoints })),
    maxArtifacts: Type.Optional(Type.Integer({ minimum: 0, maximum: LIMITS.richAnswerRenderPlanArtifacts })),
    maxBytes: Type.Optional(Type.Integer({ minimum: 1, maximum: LIMITS.richAnswerRenderPlanSpecBytes })),
    maxWidth: Type.Optional(Type.Integer({ minimum: 240, maximum: 960 })),
    maxHeight: Type.Optional(Type.Integer({ minimum: 160, maximum: 640 })),
    maxAnimationFPS: Type.Optional(Type.Integer({ minimum: 0, maximum: 30 })),
    maxInteractionLatencyMS: Type.Optional(Type.Integer({ minimum: 1, maximum: 120 })),
    allowAnimation: Type.Boolean(),
    allowWebGL: Type.Boolean(),
    allowNetwork: Type.Boolean(),
  },
  { additionalProperties: false },
);
const richAnswerRenderPlanSchema = Type.Object(
  {
    renderer: Type.String({ minLength: 1, maxLength: 160 }),
    specVersion: Type.String({ minLength: 1, maxLength: 160 }),
    spec: richAnswerRenderPlanSpecSchema,
    interactionBindings: Type.Array(richAnswerRenderPlanInteractionBindingSchema, {
      maxItems: LIMITS.richAnswerRenderPlanBindings,
    }),
    sourceBindings: Type.Array(richAnswerRenderPlanSourceBindingSchema, {
      minItems: 1,
      maxItems: LIMITS.richAnswerRenderPlanSourceBindings,
    }),
    artifactRefs: Type.Array(richAnswerRenderPlanArtifactRefSchema, {
      maxItems: LIMITS.richAnswerRenderPlanArtifacts,
    }),
    fallback: richAnswerRenderPlanFallbackSchema,
    qualityBudget: richAnswerRenderPlanQualityBudgetSchema,
  },
  {
    additionalProperties: false,
    description:
      "注册专业渲染器计划。只能引用目录返回的 renderer/specVersion，并提交 spec、interactionBindings、sourceBindings、artifactRefs、fallback、qualityBudget；禁止 raw option/script/html/svgPath，安全和预算由工具返回 repair_fault。",
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
const richAnswerRenderPlanSceneSchema = Type.Object(
  {
    ...richAnswerSceneCommonFields,
    renderPlan: richAnswerRenderPlanSchema,
  },
  { additionalProperties: false },
);
const richAnswerSceneSchema = Type.Union(
  [richAnswerT1SceneSchema, richAnswerRenderPlanSceneSchema, richAnswerT2SceneSchema],
  {
    description:
      `${RICH_ANSWER_FAMILY_CONTRACT}\n场景从输入层三选一：深组件只提交 program，注册专业渲染器只提交 renderPlan，通用原语只提交 ui，不再提交 objects、relations、operations 或 frames。`,
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
            description: "列出本次实际计划使用的 ui role；使用 program 或 renderPlan 时也要列出其等价视觉角色，不能写不存在的网页/SVG/颜色。",
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
    const sceneID = match[1]!;
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

interface RichAnswerRegionParam extends RichAnswerPointParam {
  width: number;
  height: number;
}

interface RichAnswerAxisParam {
  label: string;
  minimum: number;
  maximum: number;
  unit?: string;
}

interface RichAnswerObjectParam {
  id: string;
  kind: string;
  label: string;
  text?: string;
  number?: number;
  unit?: string;
  evidenceIDs?: string[];
  assetID?: string;
  frameID?: string;
  coordinate?: RichAnswerPointParam;
  bounds?: RichAnswerRegionParam;
}

interface RichAnswerRelationParam {
  id: string;
  kind: string;
  sourceID: string;
  targetID: string;
  label?: string;
  evidenceIDs?: string[];
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
  title: string;
  objectIDs?: string[];
  xAxis?: RichAnswerAxisParam;
  yAxis?: RichAnswerAxisParam;
  assetID?: string;
  evidenceIDs?: string[];
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

interface RichAnswerRenderPlanChartSeriesParam {
  name: string;
  values: number[];
  xValues?: number[];
  chartKind?: "line" | "bar";
  unit?: string;
}

interface RichAnswerRenderPlanChartSpecParam {
  chartKind: RichAnswerStandardChartType;
  title: string;
  series?: RichAnswerRenderPlanChartSeriesParam[];
  xLabels?: string[];
  xAxisLabel?: string;
  yAxisLabel?: string;
  caption?: string;
  focusEnabled?: boolean;
  binCount?: number;
  samples?: number[];
}

interface RichAnswerMathFunctionParameterParam {
  id: string;
  label: string;
  value: number;
  minimum: number;
  maximum: number;
  step: number;
  unit?: string;
}

interface RichAnswerMathFunctionExpressionNodeParam {
  id: string;
  kind: "constant" | "variable" | "parameter" | "operation";
  value?: number;
  parameterID?: string;
  operation?: string;
  inputIDs?: string[];
}

interface RichAnswerMathFunctionSpecParam {
  title: string;
  variable: string;
  domain: { minimum: number; maximum: number };
  parameters?: RichAnswerMathFunctionParameterParam[];
  expression: {
    rootNodeID: string;
    nodes: RichAnswerMathFunctionExpressionNodeParam[];
  };
  xAxisLabel?: string;
  yAxisLabel?: string;
  caption?: string;
  probeEnabled?: boolean;
}

type RichAnswerRenderPlanSpecParam =
  | RichAnswerRenderPlanChartSpecParam
  | RichAnswerMathFunctionSpecParam
  | Record<string, unknown>;

interface RichAnswerRenderPlanInteractionBindingParam {
  id: string;
  kind: string;
  target: string;
  stateKey?: string;
  actionName?: string;
  knowledgeStateEffect?: string;
}

interface RichAnswerRenderPlanSourceBindingParam {
  id: string;
  evidenceID: string;
  target: string;
  role: string;
  requiredForFallback: boolean;
  [key: string]: unknown;
}

interface RichAnswerRenderPlanArtifactRefParam {
  id: string;
  kind: string;
  mimeType: string;
  role: string;
  width?: number;
  height?: number;
  sizeBytes?: number;
  checksum?: string;
  summary?: string;
  metadata?: Record<string, unknown>;
}

interface RichAnswerRenderPlanFallbackParam {
  mode: "narrativeOnly" | "simplifiedRenderer" | "staticSnapshot";
  reason: string;
  text: string;
  renderer?: string;
  artifactID?: string;
  preservesSourceBinding: boolean;
  [key: string]: unknown;
}

interface RichAnswerRenderPlanQualityBudgetParam {
  maxNodes?: number;
  maxDataPoints?: number;
  maxArtifacts?: number;
  maxBytes?: number;
  maxWidth?: number;
  maxHeight?: number;
  maxAnimationFPS?: number;
  maxInteractionLatencyMS?: number;
  allowAnimation: boolean;
  allowWebGL: boolean;
  allowNetwork: boolean;
  [key: string]: unknown;
}

interface RichAnswerRenderPlanParam {
  renderer: string;
  specVersion: string;
  spec: RichAnswerRenderPlanSpecParam;
  interactionBindings: RichAnswerRenderPlanInteractionBindingParam[];
  sourceBindings: RichAnswerRenderPlanSourceBindingParam[];
  artifactRefs: RichAnswerRenderPlanArtifactRefParam[];
  fallback: RichAnswerRenderPlanFallbackParam;
  qualityBudget: RichAnswerRenderPlanQualityBudgetParam;
  [key: string]: unknown;
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
  renderPlan?: RichAnswerRenderPlanParam;
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

const RICH_ANSWER_RENDER_PLAN_FIELDS = new Set([
  "renderer",
  "specVersion",
  "spec",
  "interactionBindings",
  "sourceBindings",
  "artifactRefs",
  "fallback",
  "qualityBudget",
]);
const RICH_ANSWER_RENDER_INTERACTION_FIELDS = new Set([
  "id",
  "kind",
  "target",
  "stateKey",
  "actionName",
  "knowledgeStateEffect",
]);
const RICH_ANSWER_RENDER_SOURCE_BINDING_FIELDS = new Set([
  "id",
  "evidenceID",
  "target",
  "role",
  "requiredForFallback",
]);
const RICH_ANSWER_RENDER_ARTIFACT_FIELDS = new Set([
  "id",
  "kind",
  "mimeType",
  "role",
  "width",
  "height",
  "sizeBytes",
  "checksum",
  "summary",
  "metadata",
]);
const RICH_ANSWER_RENDER_ARTIFACT_KINDS = new Set([
  "generated",
  "source",
  "snapshot",
  "table",
  "numeric_series",
  "json_spec",
  "static_png",
  "static_svg",
  "static_html",
  "image_overlay_spec",
  "interactive_adapter_spec",
]);
const RICH_ANSWER_RENDER_FALLBACK_FIELDS = new Set([
  "mode",
  "reason",
  "text",
  "renderer",
  "artifactID",
  "preservesSourceBinding",
]);
const RICH_ANSWER_RENDER_QUALITY_BUDGET_FIELDS = new Set([
  "maxNodes",
  "maxDataPoints",
  "maxArtifacts",
  "maxBytes",
  "maxWidth",
  "maxHeight",
  "maxAnimationFPS",
  "maxInteractionLatencyMS",
  "allowAnimation",
  "allowWebGL",
  "allowNetwork",
]);
const RICH_ANSWER_RENDER_INTERACTION_KINDS = new Set([
  "annotation",
  "brush",
  "picker",
  "playPause",
  "probe",
  "scrubber",
  "select",
  "slider",
  "sourceJump",
  "stateReveal",
  "step",
  "toggle",
  "zoomPan",
]);
const RICH_ANSWER_RENDER_SOURCE_BINDING_ROLES = new Set([
  "dataset",
  "data",
  "series",
  "function",
  "point",
  "bin",
  "axis",
  "caption",
  "annotation",
  "fallback",
  "artifact",
]);
const RICH_ANSWER_RENDER_FALLBACK_MODES = new Set([
  "narrativeOnly",
  "simplifiedRenderer",
  "staticSnapshot",
]);
const RICH_ANSWER_CHART_KIND_SET = new Set<string>(RICH_ANSWER_CHART_KINDS);
const RICH_ANSWER_MATH_UNARY_OPERATIONS = new Set([
  "abs",
  "cos",
  "exp",
  "log",
  "negate",
  "sin",
  "sqrt",
  "tan",
]);
const RICH_ANSWER_MATH_BINARY_OPERATIONS = new Set([
  "add",
  "divide",
  "multiply",
  "power",
  "subtract",
]);
const RICH_ANSWER_RENDER_UNSAFE_TEXT_PATTERN =
  /(?:<\s*script|<\s*iframe|javascript\s*:|data\s*:\s*text\/html|onerror\s*=|onload\s*=|eval\s*\(|Function\s*\(|https?:\/\/)/iu;

function normalizedRendererFieldName(value: string): string {
  return value.replace(/[\s_-]/gu, "").toLocaleLowerCase();
}

function rendererFieldList(value: ReadonlySet<string> | readonly string[]): string {
  return Array.from(value).join("、");
}

function richAnswerRenderPlanByteLength(value: unknown): number {
  return Buffer.byteLength(JSON.stringify(value), "utf8");
}

function richAnswerRenderPlanUnknownFields(
  value: unknown,
  allowedFields: ReadonlySet<string> | readonly string[],
): string[] {
  if (!isRecord(value)) return [];
  const allowed = allowedFields instanceof Set ? allowedFields : new Set(allowedFields);
  return Object.keys(value).filter((field) => !allowed.has(field));
}

function richAnswerRenderPlanContainsUnsafeText(value: unknown): boolean {
  if (typeof value === "string") {
    return RICH_ANSWER_RENDER_UNSAFE_TEXT_PATTERN.test(value);
  }
  if (Array.isArray(value)) {
    return value.some((item) => richAnswerRenderPlanContainsUnsafeText(item));
  }
  if (isRecord(value)) {
    return Object.values(value).some((item) => richAnswerRenderPlanContainsUnsafeText(item));
  }
  return false;
}

function richAnswerRenderPlanForbiddenFieldPaths(
  value: unknown,
  registration: RichAnswerRendererRegistration,
  path = "$.renderPlan.spec",
): string[] {
  if (!isRecord(value) && !Array.isArray(value)) return [];
  const forbidden = new Set(registration.forbiddenSpecFields.map(normalizedRendererFieldName));
  const paths: string[] = [];
  const visit = (current: unknown, currentPath: string): void => {
    if (paths.length >= 12) return;
    if (Array.isArray(current)) {
      current.forEach((item, index) => visit(item, `${currentPath}[${index}]`));
      return;
    }
    if (!isRecord(current)) return;
    for (const [field, child] of Object.entries(current)) {
      const childPath = `${currentPath}.${field}`;
      if (forbidden.has(normalizedRendererFieldName(field))) {
        paths.push(childPath);
      }
      visit(child, childPath);
      if (paths.length >= 12) return;
    }
  };
  visit(value, path);
  return paths;
}

function richAnswerRenderPlanNumberArray(value: unknown): number[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.every((item) => typeof item === "number" && Number.isFinite(item))
    ? value
    : undefined;
}

function richAnswerRenderPlanStringArray(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.every((item) => typeof item === "string" && item.trim().length > 0)
    ? value
    : undefined;
}

function richAnswerRenderPlanValidIdentifier(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= LIMITS.identifier;
}

function richAnswerRenderPlanValidActionName(value: string): boolean {
  return /^[A-Za-z][A-Za-z0-9_.-]{0,119}$/u.test(value) &&
    !RICH_ANSWER_RENDER_UNSAFE_TEXT_PATTERN.test(value);
}

function richAnswerRenderPlanSpecEvidenceIDs(spec: unknown): string[] {
  void spec;
  return [];
}

function richAnswerRenderPlanIntegerInRange(
  value: unknown,
  minimum: number,
  maximum: number,
): value is number {
  return typeof value === "number"
    && Number.isInteger(value)
    && value >= minimum
    && value <= maximum;
}

function validateRichAnswerChartSpec(
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
    if (chartKind === "mixed"
      && rawSeries.chartKind !== undefined
      && rawSeries.chartKind !== "line"
      && rawSeries.chartKind !== "bar") {
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

function validateRichAnswerMathFunctionSpec(
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

function richAnswerRenderPlanEstimatedNodes(spec: Record<string, unknown>, bindingCount: number, sourceCount: number): number {
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

function richAnswerRenderPlanGenericDataPoints(value: unknown, field = ""): number {
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

function validateRichAnswerGenericRenderSpec(
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

function richAnswerRenderPlanFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

/**
 * Narrows a renderer record to a normalized rectangle after validating every numeric edge.
 */
function richAnswerRenderPlanRegion(value: unknown): value is RichAnswerRegionParam {
  return isRecord(value)
    && richAnswerRenderPlanFiniteNumber(value.x)
    && richAnswerRenderPlanFiniteNumber(value.y)
    && richAnswerRenderPlanFiniteNumber(value.width)
    && richAnswerRenderPlanFiniteNumber(value.height);
}

interface RichAnswerCoordinateBoundsParam {
  xMin: number;
  xMax: number;
  yMin: number;
  yMax: number;
}

/**
 * Narrows renderer coordinate bounds only after all four limits are finite numbers.
 */
function richAnswerRenderPlanCoordinateBounds(value: unknown): value is RichAnswerCoordinateBoundsParam {
  return isRecord(value)
    && richAnswerRenderPlanFiniteNumber(value.xMin)
    && richAnswerRenderPlanFiniteNumber(value.xMax)
    && richAnswerRenderPlanFiniteNumber(value.yMin)
    && richAnswerRenderPlanFiniteNumber(value.yMax);
}

interface RichAnswerSliderValuesParam {
  value: number;
  minimum: number;
  maximum: number;
  step: number;
}

/**
 * Narrows a slider record only after its value, range, and step are all finite.
 */
function richAnswerRenderPlanSliderValues(value: unknown): value is RichAnswerSliderValuesParam {
  return isRecord(value)
    && richAnswerRenderPlanFiniteNumber(value.value)
    && richAnswerRenderPlanFiniteNumber(value.minimum)
    && richAnswerRenderPlanFiniteNumber(value.maximum)
    && richAnswerRenderPlanFiniteNumber(value.step);
}

function richAnswerRenderPlanControlValue(value: unknown): value is number | string {
  return richAnswerRenderPlanFiniteNumber(value) || (
    typeof value === "string" &&
    value.trim().length > 0 &&
    value.length <= 80
  );
}

function richAnswerValidateNestedFields(
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

function richAnswerNormalizeScene3DRange(
  value: unknown,
  path: string,
  normalizations: string[],
): unknown {
  if (
    Array.isArray(value) &&
    value.length === 2 &&
    value.every(richAnswerRenderPlanFiniteNumber) &&
    value[0]! < value[1]!
  ) {
    normalizations.push(`${path} 已由 [min,max] 归一化为 {min,max}`);
    return { min: value[0]!, max: value[1]! };
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

function normalizeRichAnswerScene3DSpec(
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

  plan.spec = spec;
  return normalizations;
}

function richAnswerValidateIdentifier(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
): value is string {
  if (!richAnswerRenderPlanValidIdentifier(value)) {
    issue(`富回答场景 ${scene.id} 的 ${path} 必须是非空 id`);
    return false;
  }
  return true;
}

function richAnswerValidateCoordinate2D(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
  normalized = false,
): value is RichAnswerPointParam {
  if (!richAnswerValidateNestedFields(scene, value, ["x", "y"], path, issue)) return false;
  if (!richAnswerRenderPlanFiniteNumber(value.x) || !richAnswerRenderPlanFiniteNumber(value.y)) {
    issue(`富回答场景 ${scene.id} 的 ${path}.x/y 必须是有限数字`);
    return false;
  }
  if (normalized && (value.x < 0 || value.x > 1 || value.y < 0 || value.y > 1)) {
    issue(`富回答场景 ${scene.id} 的 ${path}.x/y 必须落在 0–1`);
    return false;
  }
  return true;
}

function richAnswerValidateVector3(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
): value is [number, number, number] {
  if (
    !Array.isArray(value) ||
    value.length !== 3 ||
    !value.every(richAnswerRenderPlanFiniteNumber)
  ) {
    issue(`富回答场景 ${scene.id} 的 ${path} 必须是三个有限数字组成的三维向量`);
    return false;
  }
  return true;
}

function richAnswerValidateRange(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
): value is Record<string, unknown> {
  if (!richAnswerValidateNestedFields(scene, value, ["min", "max"], path, issue)) return false;
  if (
    !richAnswerRenderPlanFiniteNumber(value.min) ||
    !richAnswerRenderPlanFiniteNumber(value.max) ||
    value.min >= value.max
  ) {
    issue(`富回答场景 ${scene.id} 的 ${path} 必须满足有限数 min < max`);
    return false;
  }
  return true;
}

function richAnswerValidateStyle(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  issue: (message: string) => void,
  fields: readonly string[],
): void {
  if (value === undefined) return;
  richAnswerValidateNestedFields(scene, value, fields, path, issue);
}

function richAnswerValidateRasterSource(
  scene: RichAnswerSceneParam,
  value: unknown,
  path: string,
  allowedAssetIDs: ReadonlySet<string>,
  issue: (message: string) => void,
  allowNone: boolean,
): void {
  if (!richAnswerValidateNestedFields(
    scene,
    value,
    ["kind", "source", "label", "width", "height"],
    path,
    issue,
  )) return;
  const kind = value.kind;
  const allowedKinds = allowNone ? ["none", "dataUrl", "assetRef"] : ["dataUrl", "assetRef"];
  if (typeof kind !== "string" || !allowedKinds.includes(kind)) {
    issue(`富回答场景 ${scene.id} 的 ${path}.kind 必须是 ${allowedKinds.join("、")}`);
    return;
  }
  if (kind === "none") {
    if (value.source !== undefined) {
      issue(`富回答场景 ${scene.id} 的 ${path}.kind=none 时不能提交 source`);
    }
    return;
  }
  const source = typeof value.source === "string" ? value.source.trim() : "";
  if (!source) {
    issue(`富回答场景 ${scene.id} 的 ${path}.source 不能为空`);
    return;
  }
  if (kind === "assetRef") {
    if (!allowedAssetIDs.has(source)) {
      issue(`富回答场景 ${scene.id} 的 ${path}.source 必须引用 sourceBindings.allowedAssetIDs 中的真实材料资产：${source}`);
    }
  } else if (!/^data:image\/(?:png|jpe?g|webp|gif);base64,/iu.test(source)) {
    issue(`富回答场景 ${scene.id} 的 ${path}.source 只接受安全 raster data URL`);
  }
  for (const dimension of ["width", "height"] as const) {
    if (
      value[dimension] !== undefined &&
      (!Number.isInteger(value[dimension]) || (value[dimension] as number) < 16)
    ) {
      issue(`富回答场景 ${scene.id} 的 ${path}.${dimension} 必须是至少 16 的整数`);
    }
  }
}

function validateRichAnswerImageOverlaySpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  allowedAssetIDs: ReadonlySet<string>,
  issue: (message: string) => void,
): number {
  const dataPointCount = validateRichAnswerGenericRenderSpec(scene, spec, registration, issue);
  richAnswerValidateRasterSource(scene, spec.image, "spec.image", allowedAssetIDs, issue, false);
  if (spec.objectFit !== undefined && !["contain", "cover", "fill", "none"].includes(String(spec.objectFit))) {
    issue(`富回答场景 ${scene.id} 的 spec.objectFit 必须是 contain、cover、fill 或 none`);
  }
  if (spec.measurement !== undefined && richAnswerValidateNestedFields(
    scene,
    spec.measurement,
    ["unit", "pxPerUnit", "precision"],
    "spec.measurement",
    issue,
  )) {
    if (spec.measurement.pxPerUnit !== undefined && (!richAnswerRenderPlanFiniteNumber(spec.measurement.pxPerUnit) || spec.measurement.pxPerUnit <= 0)) {
      issue(`富回答场景 ${scene.id} 的 spec.measurement.pxPerUnit 必须大于 0`);
    }
    if (spec.measurement.precision !== undefined && !richAnswerRenderPlanIntegerInRange(spec.measurement.precision, 0, 8)) {
      issue(`富回答场景 ${scene.id} 的 spec.measurement.precision 必须是 0–8 的整数`);
    }
  }

  const layers = Array.isArray(spec.layers) ? spec.layers : [];
  if (!Array.isArray(spec.layers)) issue(`富回答场景 ${scene.id} 的 spec.layers 必须是数组`);
  const layerIDs = new Set<string>();
  let visibleFeatureCount = 0;
  for (const [layerIndex, rawLayer] of layers.entries()) {
    const layerPath = `spec.layers[${layerIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawLayer,
      ["id", "title", "visibleDefault", "features", "annotation"],
      layerPath,
      issue,
    )) continue;
    if (richAnswerValidateIdentifier(scene, rawLayer.id, `${layerPath}.id`, issue)) {
      if (layerIDs.has(rawLayer.id)) issue(`富回答场景 ${scene.id} 的图层 id 重复：${rawLayer.id}`);
      layerIDs.add(rawLayer.id);
    }
    const features = Array.isArray(rawLayer.features) ? rawLayer.features : [];
    if (!Array.isArray(rawLayer.features) || features.length === 0) {
      issue(`富回答场景 ${scene.id} 的 ${layerPath}.features 必须是非空数组`);
    }
    const featureIDs = new Set<string>();
    for (const [featureIndex, rawFeature] of features.entries()) {
      const featurePath = `${layerPath}.features[${featureIndex}]`;
      if (!isRecord(rawFeature)) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath} 必须是对象`);
        continue;
      }
      const kind = rawFeature.kind;
      const allowedFeatureFields = kind === "point"
        ? ["id", "kind", "label", "point", "emphasis", "tone", "style", "value"]
        : kind === "line"
          ? ["id", "kind", "label", "start", "end", "points", "emphasis", "tone", "style", "value"]
          : kind === "rect"
            ? ["id", "kind", "label", "box", "emphasis", "tone", "style", "value"]
            : kind === "polygon"
              ? ["id", "kind", "label", "points", "emphasis", "tone", "style", "value"]
              : ["id", "kind"];
      richAnswerValidateNestedFields(scene, rawFeature, allowedFeatureFields, featurePath, issue);
      if (!["point", "line", "rect", "polygon"].includes(String(kind))) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath}.kind 只能是 point、line、rect 或 polygon`);
        continue;
      }
      if (richAnswerValidateIdentifier(scene, rawFeature.id, `${featurePath}.id`, issue)) {
        if (featureIDs.has(rawFeature.id)) issue(`富回答场景 ${scene.id} 的图形 id 重复：${rawFeature.id}`);
        featureIDs.add(rawFeature.id);
      }
      if (rawFeature.emphasis !== undefined && !["subtle", "normal", "strong"].includes(String(rawFeature.emphasis))) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath}.emphasis 只能是 subtle、normal 或 strong`);
      }
      if (rawFeature.tone !== undefined && !["earth", "neutral", "accent", "caution"].includes(String(rawFeature.tone))) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath}.tone 只能是 earth、neutral、accent 或 caution`);
      }
      if (kind === "point") {
        richAnswerValidateCoordinate2D(scene, rawFeature.point, `${featurePath}.point`, issue, true);
        visibleFeatureCount += 1;
      } else if (kind === "line") {
        const points = Array.isArray(rawFeature.points) ? rawFeature.points : [];
        const hasSegment = rawFeature.start !== undefined || rawFeature.end !== undefined;
        if (points.length > 0 && hasSegment) {
          issue(`富回答场景 ${scene.id} 的 ${featurePath} 不能同时提交 start/end 与 points`);
        } else if (points.length > 0) {
          if (points.length < 2 || points.length > 64) {
            issue(`富回答场景 ${scene.id} 的 ${featurePath}.points 必须包含 2–64 个点`);
          }
          points.forEach((point, pointIndex) => richAnswerValidateCoordinate2D(
            scene,
            point,
            `${featurePath}.points[${pointIndex}]`,
            issue,
            true,
          ));
          visibleFeatureCount += points.length;
        } else {
          richAnswerValidateCoordinate2D(scene, rawFeature.start, `${featurePath}.start`, issue, true);
          richAnswerValidateCoordinate2D(scene, rawFeature.end, `${featurePath}.end`, issue, true);
          visibleFeatureCount += 2;
        }
      } else if (kind === "rect") {
        if (richAnswerValidateNestedFields(
          scene,
          rawFeature.box,
          ["x", "y", "width", "height"],
          `${featurePath}.box`,
          issue,
        )) {
          const box = rawFeature.box;
          if (
            !richAnswerRenderPlanRegion(box) ||
            box.x < 0 || box.y < 0 || box.width <= 0 || box.height <= 0 ||
            box.x + box.width > 1 || box.y + box.height > 1
          ) issue(`富回答场景 ${scene.id} 的 ${featurePath}.box 必须是 0–1 内的正面积矩形`);
        }
        visibleFeatureCount += 2;
      } else {
        const points = Array.isArray(rawFeature.points) ? rawFeature.points : [];
        if (points.length < 3 || points.length > 64) {
          issue(`富回答场景 ${scene.id} 的 ${featurePath}.points 必须包含 3–64 个点`);
        }
        points.forEach((point, pointIndex) => richAnswerValidateCoordinate2D(
          scene,
          point,
          `${featurePath}.points[${pointIndex}]`,
          issue,
          true,
        ));
        visibleFeatureCount += points.length;
      }
      richAnswerValidateStyle(
        scene,
        rawFeature.style,
        `${featurePath}.style`,
        issue,
        ["stroke", "strokeWidth", "fill", "opacity", "dash"],
      );
    }
  }

  const annotations = Array.isArray(spec.annotations) ? spec.annotations : [];
  if (spec.annotations !== undefined && !Array.isArray(spec.annotations)) {
    issue(`富回答场景 ${scene.id} 的 spec.annotations 必须是数组`);
  }
  for (const [annotationIndex, rawAnnotation] of annotations.entries()) {
    const annotationPath = `spec.annotations[${annotationIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawAnnotation,
      ["id", "point", "text", "color", "layer"],
      annotationPath,
      issue,
    )) continue;
    richAnswerValidateIdentifier(scene, rawAnnotation.id, `${annotationPath}.id`, issue);
    richAnswerValidateCoordinate2D(scene, rawAnnotation.point, `${annotationPath}.point`, issue, true);
    if (rawAnnotation.layer !== undefined && !layerIDs.has(String(rawAnnotation.layer))) {
      issue(`富回答场景 ${scene.id} 的 ${annotationPath}.layer 引用了不存在的图层`);
    }
  }

  if (spec.comparison !== undefined && richAnswerValidateNestedFields(
    scene,
    spec.comparison,
    ["enabled", "image", "ratio", "axis", "leftLabel", "rightLabel"],
    "spec.comparison",
    issue,
  )) {
    richAnswerValidateRasterSource(
      scene,
      spec.comparison.image,
      "spec.comparison.image",
      allowedAssetIDs,
      issue,
      false,
    );
    if (spec.comparison.ratio !== undefined && (!richAnswerRenderPlanFiniteNumber(spec.comparison.ratio) || spec.comparison.ratio < 0.1 || spec.comparison.ratio > 0.9)) {
      issue(`富回答场景 ${scene.id} 的 spec.comparison.ratio 必须在 0.1–0.9`);
    }
    if (spec.comparison.axis !== undefined && !["vertical", "horizontal"].includes(String(spec.comparison.axis))) {
      issue(`富回答场景 ${scene.id} 的 spec.comparison.axis 必须是 vertical 或 horizontal`);
    }
  }
  if (visibleFeatureCount === 0 && annotations.length === 0) {
    issue(`富回答场景 ${scene.id} 的图像叠层至少需要一个图形或批注`);
  }
  return Math.max(dataPointCount, visibleFeatureCount + annotations.length);
}

function validateRichAnswerSpatialMapSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  allowedAssetIDs: ReadonlySet<string>,
  issue: (message: string) => void,
): number {
  validateRichAnswerGenericRenderSpec(scene, spec, registration, issue);
  const coordinateMode = spec.coordinateMode;
  if (coordinateMode !== "schematic" && coordinateMode !== "geographic") {
    issue(`富回答场景 ${scene.id} 的 spec.coordinateMode 必须是 schematic 或 geographic`);
  }
  if (spec.mapAsset !== undefined) {
    richAnswerValidateRasterSource(scene, spec.mapAsset, "spec.mapAsset", allowedAssetIDs, issue, true);
  }
  if (spec.bounds !== undefined && richAnswerValidateNestedFields(
    scene,
    spec.bounds,
    ["xMin", "xMax", "yMin", "yMax"],
    "spec.bounds",
    issue,
  )) {
    const bounds = spec.bounds;
    if (
      !richAnswerRenderPlanCoordinateBounds(bounds) ||
      bounds.xMin >= bounds.xMax || bounds.yMin >= bounds.yMax
    ) issue(`富回答场景 ${scene.id} 的 spec.bounds 必须满足有限数 xMin<xMax、yMin<yMax`);
  }
  if (spec.scaleBar !== undefined) {
    richAnswerValidateNestedFields(
      scene,
      spec.scaleBar,
      ["enabled", "label", "targetPixels"],
      "spec.scaleBar",
      issue,
    );
  }
  if (spec.controls !== undefined) {
    richAnswerValidateNestedFields(
      scene,
      spec.controls,
      ["allowPan", "allowZoom", "allowLayerToggle", "allowReset", "probeEnabled"],
      "spec.controls",
      issue,
    );
  }
  const layers = Array.isArray(spec.layers) ? spec.layers : [];
  if (spec.layers !== undefined && !Array.isArray(spec.layers)) issue(`富回答场景 ${scene.id} 的 spec.layers 必须是数组`);
  const layerIDs = new Set<string>();
  for (const [layerIndex, rawLayer] of layers.entries()) {
    const layerPath = `spec.layers[${layerIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawLayer,
      ["id", "title", "visibleDefault", "note"],
      layerPath,
      issue,
    )) continue;
    if (richAnswerValidateIdentifier(scene, rawLayer.id, `${layerPath}.id`, issue)) {
      if (layerIDs.has(rawLayer.id)) issue(`富回答场景 ${scene.id} 的地图图层 id 重复：${rawLayer.id}`);
      layerIDs.add(rawLayer.id);
    }
  }
  const features = Array.isArray(spec.features) ? spec.features : [];
  if (!Array.isArray(spec.features) || features.length === 0) {
    issue(`富回答场景 ${scene.id} 的 spec.features 必须是非空数组`);
  }
  const featureIDs = new Set<string>();
  const geometryIDs = new Set<string>();
  let pointCount = 0;
  for (const [featureIndex, rawFeature] of features.entries()) {
    const featurePath = `spec.features[${featureIndex}]`;
    if (!isRecord(rawFeature)) {
      issue(`富回答场景 ${scene.id} 的 ${featurePath} 必须是对象`);
      continue;
    }
    const kind = rawFeature.kind;
    const commonFields = ["id", "kind", "layer", "visibilityGroup", "visible", "label", "style", "value"];
    const allowedFields = kind === "point"
      ? [...commonFields, "x", "y", "radius"]
      : kind === "line"
        ? [...commonFields, "points", "closed"]
        : kind === "polygon"
          ? [...commonFields, "points", "fillMode"]
          : kind === "label"
            ? ["id", "kind", "x", "y", "text", "layer", "visibilityGroup", "bindTo", "visible", "style"]
            : ["id", "kind"];
    richAnswerValidateNestedFields(scene, rawFeature, allowedFields, featurePath, issue);
    if (!["point", "line", "polygon", "label"].includes(String(kind))) {
      issue(`富回答场景 ${scene.id} 的 ${featurePath}.kind 只能是 point、line、polygon 或 label`);
      continue;
    }
    if (richAnswerValidateIdentifier(scene, rawFeature.id, `${featurePath}.id`, issue)) {
      if (featureIDs.has(rawFeature.id)) issue(`富回答场景 ${scene.id} 的地图元素 id 重复：${rawFeature.id}`);
      featureIDs.add(rawFeature.id);
      if (kind !== "label") geometryIDs.add(rawFeature.id);
    }
    if (rawFeature.layer !== undefined && !layerIDs.has(String(rawFeature.layer))) {
      issue(`富回答场景 ${scene.id} 的 ${featurePath}.layer 引用了不存在的图层`);
    }
    if (kind === "point" || kind === "label") {
      if (!richAnswerRenderPlanFiniteNumber(rawFeature.x) || !richAnswerRenderPlanFiniteNumber(rawFeature.y)) {
        issue(`富回答场景 ${scene.id} 的 ${featurePath}.x/y 必须是有限数字`);
      } else if (
        coordinateMode === "geographic" &&
        (rawFeature.x < -180 || rawFeature.x > 180 || rawFeature.y < -90 || rawFeature.y > 90)
      ) issue(`富回答场景 ${scene.id} 的 ${featurePath} 经纬度越界`);
      pointCount += 1;
    } else {
      const points = Array.isArray(rawFeature.points) ? rawFeature.points : [];
      const minimum = kind === "polygon" ? 3 : 2;
      if (points.length < minimum) issue(`富回答场景 ${scene.id} 的 ${featurePath}.points 至少需要 ${minimum} 个点`);
      points.forEach((point, pointIndex) => {
        if (richAnswerValidateCoordinate2D(scene, point, `${featurePath}.points[${pointIndex}]`, issue) && coordinateMode === "geographic") {
          if (point.x < -180 || point.x > 180 || point.y < -90 || point.y > 90) {
            issue(`富回答场景 ${scene.id} 的 ${featurePath}.points[${pointIndex}] 经纬度越界`);
          }
        }
      });
      pointCount += points.length;
    }
    richAnswerValidateStyle(
      scene,
      rawFeature.style,
      `${featurePath}.style`,
      issue,
      kind === "label"
        ? ["color", "size", "weight", "shadow"]
        : ["stroke", "strokeWidth", "fill", "opacity", "dash"],
    );
  }
  for (const [featureIndex, rawFeature] of features.entries()) {
    if (isRecord(rawFeature) && rawFeature.kind === "label" && rawFeature.bindTo !== undefined && !geometryIDs.has(String(rawFeature.bindTo))) {
      issue(`富回答场景 ${scene.id} 的 spec.features[${featureIndex}].bindTo 引用了不存在的图形`);
    }
  }
  if (pointCount > registration.budgets.maxDataPoints) {
    issue(`富回答场景 ${scene.id} 的地图数据点超出预算：${pointCount}/${registration.budgets.maxDataPoints}`);
  }
  return pointCount;
}

function validateRichAnswerGeometry2DSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  issue: (message: string) => void,
): number {
  validateRichAnswerGenericRenderSpec(scene, spec, registration, issue);
  if (!richAnswerValidateNestedFields(
    scene,
    spec.coordinateSpace,
    ["xMin", "xMax", "yMin", "yMax", "preserveAspectRatio", "gridStep"],
    "spec.coordinateSpace",
    issue,
  )) return 0;
  const coordinateSpace = spec.coordinateSpace;
  if (
    !richAnswerRenderPlanCoordinateBounds(coordinateSpace) ||
    coordinateSpace.xMin >= coordinateSpace.xMax || coordinateSpace.yMin >= coordinateSpace.yMax
  ) issue(`富回答场景 ${scene.id} 的 spec.coordinateSpace 范围无效`);

  const points = Array.isArray(spec.points) ? spec.points : [];
  if (!Array.isArray(spec.points) || points.length === 0) issue(`富回答场景 ${scene.id} 的 spec.points 必须是非空数组`);
  const pointIDs = new Set<string>();
  let dataPointCount = points.length;
  for (const [pointIndex, rawPoint] of points.entries()) {
    const pointPath = `spec.points[${pointIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawPoint,
      ["id", "label", "x", "y", "draggable", "constraint", "style"],
      pointPath,
      issue,
    )) continue;
    if (richAnswerValidateIdentifier(scene, rawPoint.id, `${pointPath}.id`, issue)) {
      if (pointIDs.has(rawPoint.id)) issue(`富回答场景 ${scene.id} 的点 id 重复：${rawPoint.id}`);
      pointIDs.add(rawPoint.id);
    }
    if (!richAnswerRenderPlanFiniteNumber(rawPoint.x) || !richAnswerRenderPlanFiniteNumber(rawPoint.y)) {
      issue(`富回答场景 ${scene.id} 的 ${pointPath}.x/y 必须是有限数字`);
    }
    richAnswerValidateStyle(scene, rawPoint.style, `${pointPath}.style`, issue, ["stroke", "fill", "radius"]);
    if (rawPoint.constraint !== undefined && isRecord(rawPoint.constraint)) {
      const constraint = rawPoint.constraint;
      const fields = constraint.kind === "free"
        ? ["kind"]
        : constraint.kind === "axis"
          ? ["kind", "axis", "value", "showTrack"]
          : constraint.kind === "lineSegment"
            ? ["kind", "start", "end", "showTrack"]
            : constraint.kind === "circle"
              ? ["kind", "center", "radius", "showTrack"]
              : constraint.kind === "roundedBoxTrack"
                ? ["kind", "box", "cornerRadius", "showTrack"]
                : ["kind"];
      richAnswerValidateNestedFields(scene, constraint, fields, `${pointPath}.constraint`, issue);
      if (!["free", "axis", "lineSegment", "circle", "roundedBoxTrack"].includes(String(constraint.kind))) {
        issue(`富回答场景 ${scene.id} 的 ${pointPath}.constraint.kind 无效`);
      }
      if (constraint.kind === "lineSegment") {
        richAnswerValidateCoordinate2D(scene, constraint.start, `${pointPath}.constraint.start`, issue);
        richAnswerValidateCoordinate2D(scene, constraint.end, `${pointPath}.constraint.end`, issue);
      } else if (constraint.kind === "circle") {
        richAnswerValidateCoordinate2D(scene, constraint.center, `${pointPath}.constraint.center`, issue);
      }
    } else if (rawPoint.constraint !== undefined) {
      issue(`富回答场景 ${scene.id} 的 ${pointPath}.constraint 必须是对象`);
    }
  }

  const shapes = Array.isArray(spec.shapes) ? spec.shapes : [];
  if (spec.shapes !== undefined && !Array.isArray(spec.shapes)) issue(`富回答场景 ${scene.id} 的 spec.shapes 必须是数组`);
  const shapeIDs = new Set<string>();
  const visibilityControlRefs: Array<{ path: string; controlID: string }> = [];
  const validateVisibility = (value: unknown, path: string) => {
    if (value === undefined) return;
    if (!richAnswerValidateNestedFields(scene, value, ["controlID", "equals"], path, issue)) return;
    if (richAnswerValidateIdentifier(scene, value.controlID, `${path}.controlID`, issue)) {
      visibilityControlRefs.push({ path, controlID: value.controlID });
    }
    if (!richAnswerRenderPlanControlValue(value.equals)) {
      issue(`富回答场景 ${scene.id} 的 ${path}.equals 必须是有限数字或短状态值`);
    }
  };
  for (const [shapeIndex, rawShape] of shapes.entries()) {
    const shapePath = `spec.shapes[${shapeIndex}]`;
    if (!isRecord(rawShape)) {
      issue(`富回答场景 ${scene.id} 的 ${shapePath} 必须是对象`);
      continue;
    }
    const kind = rawShape.kind;
    const fields = kind === "segment"
      ? ["id", "kind", "from", "to", "label", "style", "visibleWhen"]
      : kind === "vector"
        ? ["id", "kind", "from", "to", "label", "style", "visibleWhen"]
      : kind === "circle"
        ? ["id", "kind", "center", "radius", "through", "label", "style", "visibleWhen"]
        : kind === "angle"
          ? ["id", "kind", "vertex", "from", "to", "radius", "label", "style", "visibleWhen"]
          : kind === "roundedBox"
            ? ["id", "kind", "box", "cornerRadius", "label", "style", "visibleWhen"]
            : kind === "locus"
              ? ["id", "kind", "points", "label", "style", "visibleWhen"]
              : kind === "polygon"
                ? ["id", "kind", "points", "label", "style", "visibleWhen"]
                : kind === "orientedBox"
                  ? ["id", "kind", "center", "width", "height", "rotationDegrees", "label", "style", "visibleWhen"]
              : ["id", "kind"];
    richAnswerValidateNestedFields(scene, rawShape, fields, shapePath, issue);
    if (!["segment", "vector", "circle", "angle", "roundedBox", "locus", "polygon", "orientedBox"].includes(String(kind))) {
      issue(`富回答场景 ${scene.id} 的 ${shapePath}.kind 无效`);
      continue;
    }
    validateVisibility(rawShape.visibleWhen, `${shapePath}.visibleWhen`);
    if (richAnswerValidateIdentifier(scene, rawShape.id, `${shapePath}.id`, issue)) {
      if (shapeIDs.has(rawShape.id) || pointIDs.has(rawShape.id)) issue(`富回答场景 ${scene.id} 的几何对象 id 重复：${rawShape.id}`);
      shapeIDs.add(rawShape.id);
    }
    const pointRefs = kind === "segment" || kind === "vector"
      ? [rawShape.from, rawShape.to]
      : kind === "circle"
        ? [rawShape.center, rawShape.through].filter((value) => value !== undefined)
        : kind === "angle"
          ? [rawShape.vertex, rawShape.from, rawShape.to]
          : kind === "polygon"
            ? (Array.isArray(rawShape.points) ? rawShape.points : [])
            : kind === "orientedBox"
              ? [rawShape.center]
          : [];
    pointRefs.forEach((pointRef) => {
      if (!pointIDs.has(String(pointRef))) issue(`富回答场景 ${scene.id} 的 ${shapePath} 引用了不存在的点 ${String(pointRef)}`);
    });
    if (kind === "circle" && rawShape.radius === undefined && rawShape.through === undefined) {
      issue(`富回答场景 ${scene.id} 的圆 ${String(rawShape.id)} 必须提供 radius 或 through`);
    }
    if (kind === "locus") {
      const locusPoints = Array.isArray(rawShape.points) ? rawShape.points : [];
      if (locusPoints.length < 2) issue(`富回答场景 ${scene.id} 的 ${shapePath}.points 至少需要两个点`);
      locusPoints.forEach((point, pointIndex) => richAnswerValidateCoordinate2D(scene, point, `${shapePath}.points[${pointIndex}]`, issue));
      dataPointCount += locusPoints.length;
    }
    if (kind === "polygon") {
      const polygonPoints = Array.isArray(rawShape.points) ? rawShape.points : [];
      if (polygonPoints.length < 3) issue(`富回答场景 ${scene.id} 的 ${shapePath}.points 至少需要三个点 id`);
    }
    if (kind === "orientedBox") {
      if (!richAnswerRenderPlanFiniteNumber(rawShape.width) || rawShape.width <= 0) {
        issue(`富回答场景 ${scene.id} 的 ${shapePath}.width 必须大于 0`);
      }
      if (!richAnswerRenderPlanFiniteNumber(rawShape.height) || rawShape.height <= 0) {
        issue(`富回答场景 ${scene.id} 的 ${shapePath}.height 必须大于 0`);
      }
      if (!richAnswerRenderPlanFiniteNumber(rawShape.rotationDegrees)) {
        issue(`富回答场景 ${scene.id} 的 ${shapePath}.rotationDegrees 必须是有限数字`);
      }
    }
    richAnswerValidateStyle(scene, rawShape.style, `${shapePath}.style`, issue, ["stroke", "strokeWidth", "fill", "opacity", "dash"]);
  }

  const controls = Array.isArray(spec.controls) ? spec.controls : [];
  if (spec.controls !== undefined && !Array.isArray(spec.controls)) issue(`富回答场景 ${scene.id} 的 spec.controls 必须是数组`);
  const controlIDs = new Set<string>();
  const controlsWithoutBindings: Array<{ path: string; id: string }> = [];
  for (const [controlIndex, rawControl] of controls.entries()) {
    const controlPath = `spec.controls[${controlIndex}]`;
    if (!richAnswerValidateNestedFields(
      scene,
      rawControl,
      ["id", "label", "value", "minimum", "maximum", "step", "unit", "options", "presentation", "bindings"],
      controlPath,
      issue,
    )) continue;
    if (richAnswerValidateIdentifier(scene, rawControl.id, `${controlPath}.id`, issue)) {
      if (controlIDs.has(rawControl.id)) issue(`富回答场景 ${scene.id} 的控件 id 重复：${rawControl.id}`);
      controlIDs.add(rawControl.id);
    }
    const presentation = rawControl.presentation === undefined ? "slider" : String(rawControl.presentation);
    if (!richAnswerRenderPlanControlValue(rawControl.value)) {
      issue(`富回答场景 ${scene.id} 的 ${controlPath}.value 必须是有限数字或短状态值`);
    }
    if (presentation === "slider") {
      if (
        !richAnswerRenderPlanSliderValues(rawControl) ||
        rawControl.minimum >= rawControl.maximum || rawControl.step <= 0 ||
        rawControl.value < rawControl.minimum || rawControl.value > rawControl.maximum
      ) issue(`富回答场景 ${scene.id} 的 ${controlPath} 滑杆范围或初值无效`);
    }
    const bindings = Array.isArray(rawControl.bindings) ? rawControl.bindings : [];
    if (!Array.isArray(rawControl.bindings)) issue(`富回答场景 ${scene.id} 的 ${controlPath}.bindings 必须是数组`);
    if (bindings.length === 0 && typeof rawControl.id === "string") {
      controlsWithoutBindings.push({ path: controlPath, id: rawControl.id });
    }
    const options = Array.isArray(rawControl.options) ? rawControl.options : [];
    if (rawControl.options !== undefined && (options.length < 2 || options.length > 12)) {
      issue(`富回答场景 ${scene.id} 的 ${controlPath}.options 必须有 2–12 项`);
    }
    const optionValues = new Set<number | string>();
    for (const [optionIndex, rawOption] of options.entries()) {
      const optionPath = `${controlPath}.options[${optionIndex}]`;
      if (!richAnswerValidateNestedFields(scene, rawOption, ["value", "label"], optionPath, issue)) continue;
      if (!richAnswerRenderPlanControlValue(rawOption.value)) {
        issue(`富回答场景 ${scene.id} 的 ${optionPath}.value 必须是有限数字或短状态值`);
      } else {
        if (optionValues.has(rawOption.value)) issue(`富回答场景 ${scene.id} 的 ${controlPath}.options value 不能重复`);
        optionValues.add(rawOption.value);
      }
      if (typeof rawOption.label !== "string" || rawOption.label.trim().length === 0) {
        issue(`富回答场景 ${scene.id} 的 ${optionPath}.label 不能为空`);
      }
    }
    if (rawControl.presentation !== undefined && !["slider", "segmented"].includes(String(rawControl.presentation))) {
      issue(`富回答场景 ${scene.id} 的 ${controlPath}.presentation 必须是 slider 或 segmented`);
    }
    if (presentation === "segmented") {
      const selectedValue = rawControl.value;
      if (!options.some((option) => isRecord(option) && option.value === selectedValue)) {
        issue(`富回答场景 ${scene.id} 的 ${controlPath}.value 必须命中一个分段选项`);
      }
    }
    if (bindings.length > 0 && !richAnswerRenderPlanFiniteNumber(rawControl.value)) {
      issue(`富回答场景 ${scene.id} 的 ${controlPath} 有几何绑定时 value 必须是有限数字`);
    }
    for (const [bindingIndex, rawBinding] of bindings.entries()) {
      const bindingPath = `${controlPath}.bindings[${bindingIndex}]`;
      if (!isRecord(rawBinding)) {
        issue(`富回答场景 ${scene.id} 的 ${bindingPath} 必须是对象`);
        continue;
      }
      const fields = rawBinding.kind === "pointCoordinate"
        ? ["kind", "pointID", "axis", "multiplier", "offset", "minimum", "maximum"]
        : rawBinding.kind === "pointOnConstraint"
          ? ["kind", "pointID", "multiplier", "offset"]
          : rawBinding.kind === "circleRadius"
            ? ["kind", "shapeID", "multiplier", "offset", "minimum", "maximum"]
            : ["kind"];
      richAnswerValidateNestedFields(scene, rawBinding, fields, bindingPath, issue);
      if (rawBinding.kind === "circleRadius") {
        if (!shapeIDs.has(String(rawBinding.shapeID))) issue(`富回答场景 ${scene.id} 的 ${bindingPath}.shapeID 不存在`);
      } else if (["pointCoordinate", "pointOnConstraint"].includes(String(rawBinding.kind))) {
        if (!pointIDs.has(String(rawBinding.pointID))) issue(`富回答场景 ${scene.id} 的 ${bindingPath}.pointID 不存在`);
      } else {
        issue(`富回答场景 ${scene.id} 的 ${bindingPath}.kind 无效`);
      }
    }
  }

  const readouts = Array.isArray(spec.readouts) ? spec.readouts : [];
  if (spec.readouts !== undefined && !Array.isArray(spec.readouts)) issue(`富回答场景 ${scene.id} 的 spec.readouts 必须是数组`);
  const stateReadoutControlRefs: Array<{ path: string; controlID: string }> = [];
  for (const [readoutIndex, rawReadout] of readouts.entries()) {
    const readoutPath = `spec.readouts[${readoutIndex}]`;
    if (!isRecord(rawReadout)) {
      issue(`富回答场景 ${scene.id} 的 ${readoutPath} 必须是对象`);
      continue;
    }
    const fields = rawReadout.kind === "point"
      ? ["id", "kind", "label", "pointID"]
      : rawReadout.kind === "distance"
        ? ["id", "kind", "label", "from", "to", "unit"]
        : rawReadout.kind === "angle"
          ? ["id", "kind", "label", "vertex", "from", "to", "unit"]
          : rawReadout.kind === "state"
            ? ["id", "kind", "label", "controlID", "options"]
          : ["id", "kind"];
    richAnswerValidateNestedFields(scene, rawReadout, fields, readoutPath, issue);
    const refs = rawReadout.kind === "point"
      ? [rawReadout.pointID]
      : rawReadout.kind === "distance"
        ? [rawReadout.from, rawReadout.to]
        : rawReadout.kind === "angle"
          ? [rawReadout.vertex, rawReadout.from, rawReadout.to]
          : [];
    refs.forEach((pointRef) => {
      if (!pointIDs.has(String(pointRef))) issue(`富回答场景 ${scene.id} 的 ${readoutPath} 引用了不存在的点`);
    });
    if (rawReadout.kind === "state") {
      if (richAnswerValidateIdentifier(scene, rawReadout.controlID, `${readoutPath}.controlID`, issue)) {
        stateReadoutControlRefs.push({ path: readoutPath, controlID: rawReadout.controlID });
      }
      const options = Array.isArray(rawReadout.options) ? rawReadout.options : [];
      if (options.length < 2 || options.length > 12) issue(`富回答场景 ${scene.id} 的 ${readoutPath}.options 必须有 2–12 项`);
      options.forEach((rawOption, optionIndex) => {
        const optionPath = `${readoutPath}.options[${optionIndex}]`;
        if (!richAnswerValidateNestedFields(scene, rawOption, ["value", "label"], optionPath, issue)) return;
        if (!richAnswerRenderPlanControlValue(rawOption.value)) issue(`富回答场景 ${scene.id} 的 ${optionPath}.value 必须是有限数字或短状态值`);
        if (typeof rawOption.label !== "string" || rawOption.label.trim().length === 0) issue(`富回答场景 ${scene.id} 的 ${optionPath}.label 不能为空`);
      });
    }
  }
  const stateConsumerControlIDs = new Set([
    ...visibilityControlRefs.map((reference) => reference.controlID),
    ...stateReadoutControlRefs.map((reference) => reference.controlID),
  ]);
  for (const reference of [...visibilityControlRefs, ...stateReadoutControlRefs]) {
    if (!controlIDs.has(reference.controlID)) {
      issue(`富回答场景 ${scene.id} 的 ${reference.path} 引用了不存在的控件 ${reference.controlID}`);
    }
  }
  for (const control of controlsWithoutBindings) {
    if (!stateConsumerControlIDs.has(control.id)) {
      issue(`富回答场景 ${scene.id} 的 ${control.path} 没有几何绑定，也没有驱动 visibleWhen 或 state 读数`);
    }
  }
  if (dataPointCount > registration.budgets.maxDataPoints) {
    issue(`富回答场景 ${scene.id} 的二维几何数据点超出预算：${dataPointCount}/${registration.budgets.maxDataPoints}`);
  }
  return dataPointCount;
}

function validateRichAnswerScene3DSpec(
  scene: RichAnswerSceneParam,
  spec: Record<string, unknown>,
  registration: RichAnswerRendererRegistration,
  allowedEvidenceIDs: ReadonlySet<string>,
  issue: (message: string) => void,
  validateStateCollections = true,
): number {
  validateRichAnswerGenericRenderSpec(scene, spec, registration, issue);
  if (richAnswerValidateNestedFields(
    scene,
    spec.camera,
    ["yaw", "pitch", "distance", "lookAt", "fov"],
    "spec.camera",
    issue,
  )) {
    richAnswerValidateVector3(scene, spec.camera.lookAt, "spec.camera.lookAt", issue);
    if (![spec.camera.yaw, spec.camera.pitch, spec.camera.distance].every(richAnswerRenderPlanFiniteNumber)) {
      issue(`富回答场景 ${scene.id} 的 spec.camera 数值必须是有限数字`);
    }
  }
  if (spec.coordinateUnits !== undefined) {
    richAnswerValidateNestedFields(scene, spec.coordinateUnits, ["x", "y", "z"], "spec.coordinateUnits", issue);
  }
  if (spec.bounds !== undefined && richAnswerValidateNestedFields(scene, spec.bounds, ["x", "y", "z"], "spec.bounds", issue)) {
    richAnswerValidateRange(scene, spec.bounds.x, "spec.bounds.x", issue);
    richAnswerValidateRange(scene, spec.bounds.y, "spec.bounds.y", issue);
    richAnswerValidateRange(scene, spec.bounds.z, "spec.bounds.z", issue);
  }
  if (spec.controls !== undefined) {
    richAnswerValidateNestedFields(
      scene,
      spec.controls,
      ["allowLayerToggle", "allowSlice", "allowCameraDrag", "allowReset", "allowProbe"],
      "spec.controls",
      issue,
    );
  }
  const layers = Array.isArray(spec.layers) ? spec.layers : [];
  if (spec.layers !== undefined && !Array.isArray(spec.layers)) issue(`富回答场景 ${scene.id} 的 spec.layers 必须是数组`);
  const layerIDs = new Set<string>();
  for (const [layerIndex, rawLayer] of layers.entries()) {
    const layerPath = `spec.layers[${layerIndex}]`;
    if (!richAnswerValidateNestedFields(scene, rawLayer, ["id", "title", "visibleDefault"], layerPath, issue)) continue;
    if (richAnswerValidateIdentifier(scene, rawLayer.id, `${layerPath}.id`, issue)) {
      if (layerIDs.has(rawLayer.id)) issue(`富回答场景 ${scene.id} 的三维图层 id 重复：${rawLayer.id}`);
      layerIDs.add(rawLayer.id);
    }
  }
  const states = Array.isArray(spec.states) ? spec.states : [];
  if (spec.states !== undefined && !Array.isArray(spec.states)) issue(`富回答场景 ${scene.id} 的 spec.states 必须是数组`);
  const objects = Array.isArray(spec.objects) ? spec.objects : [];
  if (spec.objects !== undefined && !Array.isArray(spec.objects)) issue(`富回答场景 ${scene.id} 的 spec.objects 必须是数组`);
  if (objects.length === 0 && states.length === 0) issue(`富回答场景 ${scene.id} 至少需要一个共享对象或状态对象`);
  const objectIDs = new Set<string>();
  let dataPointCount = 0;
  for (const [objectIndex, rawObject] of objects.entries()) {
    const objectPath = `spec.objects[${objectIndex}]`;
    if (!isRecord(rawObject)) {
      issue(`富回答场景 ${scene.id} 的 ${objectPath} 必须是对象`);
      continue;
    }
    const baseFields = ["id", "kind", "layer", "label", "visible", "color", "alpha"];
    const fields = rawObject.kind === "point"
      ? [...baseFields, "position", "radius"]
      : rawObject.kind === "polyline"
        ? [...baseFields, "points", "closed", "strokeWidth"]
        : rawObject.kind === "wireframe-grid"
          ? [...baseFields, "xRange", "zRange", "cellSize", "y"]
          : rawObject.kind === "surface"
            ? [...baseFields, "yValues", "xRange", "zRange", "wireColor"]
            : rawObject.kind === "molecule"
              ? [...baseFields, "atoms", "bonds", "electronDomains", "angleMarkers", "showAtomLabels", "showBondLabels", "showElectronDomains"]
              : ["id", "kind"];
    richAnswerValidateNestedFields(scene, rawObject, fields, objectPath, issue);
    if (!["point", "polyline", "wireframe-grid", "surface", "molecule"].includes(String(rawObject.kind))) {
      issue(`富回答场景 ${scene.id} 的 ${objectPath}.kind 无效`);
      continue;
    }
    if (richAnswerValidateIdentifier(scene, rawObject.id, `${objectPath}.id`, issue)) {
      if (objectIDs.has(rawObject.id)) issue(`富回答场景 ${scene.id} 的三维对象 id 重复：${rawObject.id}`);
      objectIDs.add(rawObject.id);
    }
    if (rawObject.layer !== undefined && !layerIDs.has(String(rawObject.layer))) {
      issue(`富回答场景 ${scene.id} 的 ${objectPath}.layer 引用了不存在的图层`);
    }
    if (rawObject.kind === "point") {
      richAnswerValidateVector3(scene, rawObject.position, `${objectPath}.position`, issue);
      dataPointCount += 1;
    } else if (rawObject.kind === "polyline") {
      const points = Array.isArray(rawObject.points) ? rawObject.points : [];
      if (points.length < 2) issue(`富回答场景 ${scene.id} 的 ${objectPath}.points 至少需要两个点`);
      points.forEach((point, pointIndex) => richAnswerValidateVector3(scene, point, `${objectPath}.points[${pointIndex}]`, issue));
      dataPointCount += points.length;
    } else if (rawObject.kind === "wireframe-grid") {
      richAnswerValidateRange(scene, rawObject.xRange, `${objectPath}.xRange`, issue);
      richAnswerValidateRange(scene, rawObject.zRange, `${objectPath}.zRange`, issue);
      if (!richAnswerRenderPlanFiniteNumber(rawObject.cellSize) || rawObject.cellSize <= 0) issue(`富回答场景 ${scene.id} 的 ${objectPath}.cellSize 必须大于 0`);
      dataPointCount += 4;
    } else if (rawObject.kind === "surface") {
      richAnswerValidateRange(scene, rawObject.xRange, `${objectPath}.xRange`, issue);
      richAnswerValidateRange(scene, rawObject.zRange, `${objectPath}.zRange`, issue);
      const rows = Array.isArray(rawObject.yValues) ? rawObject.yValues : [];
      const width = Array.isArray(rows[0]) ? rows[0].length : 0;
      if (rows.length < 2 || width < 2) issue(`富回答场景 ${scene.id} 的 ${objectPath}.yValues 必须是至少 2×2 的规则有限数矩阵`);
      rows.forEach((row, rowIndex) => {
        if (!Array.isArray(row) || row.length !== width || !row.every(richAnswerRenderPlanFiniteNumber)) {
          issue(`富回答场景 ${scene.id} 的 ${objectPath}.yValues[${rowIndex}] 必须与首行等长且只含有限数`);
        }
      });
      dataPointCount += rows.length * width;
    } else {
      const atoms = Array.isArray(rawObject.atoms) ? rawObject.atoms : [];
      if (atoms.length === 0) issue(`富回答场景 ${scene.id} 的 ${objectPath}.atoms 必须是非空数组`);
      const atomIDs = new Set<string>();
      for (const [atomIndex, rawAtom] of atoms.entries()) {
        const atomPath = `${objectPath}.atoms[${atomIndex}]`;
        if (!richAnswerValidateNestedFields(
          scene,
          rawAtom,
          ["id", "element", "label", "position", "radius", "color", "role", "charge"],
          atomPath,
          issue,
        )) continue;
        if (richAnswerValidateIdentifier(scene, rawAtom.id, `${atomPath}.id`, issue)) {
          if (atomIDs.has(rawAtom.id)) issue(`富回答场景 ${scene.id} 的分子原子 id 重复：${rawAtom.id}`);
          atomIDs.add(rawAtom.id);
        }
        richAnswerValidateVector3(scene, rawAtom.position, `${atomPath}.position`, issue);
      }
      const bonds = Array.isArray(rawObject.bonds) ? rawObject.bonds : [];
      for (const [bondIndex, rawBond] of bonds.entries()) {
        const bondPath = `${objectPath}.bonds[${bondIndex}]`;
        if (!richAnswerValidateNestedFields(
          scene,
          rawBond,
          ["id", "from", "to", "order", "style", "label", "color", "radius"],
          bondPath,
          issue,
        )) continue;
        if (!atomIDs.has(String(rawBond.from)) || !atomIDs.has(String(rawBond.to)) || rawBond.from === rawBond.to) {
          issue(`富回答场景 ${scene.id} 的 ${bondPath} 必须连接两个不同且存在的原子`);
        }
      }
      const domains = Array.isArray(rawObject.electronDomains) ? rawObject.electronDomains : [];
      for (const [domainIndex, rawDomain] of domains.entries()) {
        const domainPath = `${objectPath}.electronDomains[${domainIndex}]`;
        if (!richAnswerValidateNestedFields(
          scene,
          rawDomain,
          ["id", "kind", "atom", "label", "direction", "position", "distance", "radius", "color", "alpha"],
          domainPath,
          issue,
        )) continue;
        if (!atomIDs.has(String(rawDomain.atom))) issue(`富回答场景 ${scene.id} 的 ${domainPath}.atom 不存在`);
        if (rawDomain.direction === undefined && rawDomain.position === undefined) issue(`富回答场景 ${scene.id} 的 ${domainPath} 必须提供 direction 或 position`);
        if (rawDomain.direction !== undefined) richAnswerValidateVector3(scene, rawDomain.direction, `${domainPath}.direction`, issue);
        if (rawDomain.position !== undefined) richAnswerValidateVector3(scene, rawDomain.position, `${domainPath}.position`, issue);
      }
      const markers = Array.isArray(rawObject.angleMarkers) ? rawObject.angleMarkers : [];
      for (const [markerIndex, rawMarker] of markers.entries()) {
        const markerPath = `${objectPath}.angleMarkers[${markerIndex}]`;
        if (!richAnswerValidateNestedFields(
          scene,
          rawMarker,
          ["id", "from", "via", "to", "degrees", "label", "color"],
          markerPath,
          issue,
        )) continue;
        const refs = [rawMarker.from, rawMarker.via, rawMarker.to].map(String);
        if (new Set(refs).size !== 3 || refs.some((atomID) => !atomIDs.has(atomID))) {
          issue(`富回答场景 ${scene.id} 的 ${markerPath} 必须引用三个不同且存在的原子`);
        }
      }
      dataPointCount += atoms.length + bonds.length * 2 + domains.length + markers.length * 3;
    }
  }
  let totalObjectCount = objects.length;
  if (validateStateCollections) {
    const stateBinding = spec.stateBinding;
    if (states.length > 12) issue(`富回答场景 ${scene.id} 的 spec.states 最多支持 12 个状态`);
    if (states.length > 0 && !isRecord(stateBinding)) {
      issue(`富回答场景 ${scene.id} 的 spec.states 存在时必须提交 stateBinding`);
    } else if (states.length === 0 && stateBinding !== undefined) {
      issue(`富回答场景 ${scene.id} 的 spec.stateBinding 不能脱离 states 单独存在`);
    } else if (isRecord(stateBinding)) {
      richAnswerValidateNestedFields(scene, stateBinding, ["initial", "control", "label"], "spec.stateBinding", issue);
      richAnswerValidateIdentifier(scene, stateBinding.initial, "spec.stateBinding.initial", issue);
      if (stateBinding.control !== undefined && !["segmented", "slider"].includes(String(stateBinding.control))) {
        issue(`富回答场景 ${scene.id} 的 spec.stateBinding.control 只能是 segmented 或 slider`);
      }
      if (stateBinding.label !== undefined && (typeof stateBinding.label !== "string" || stateBinding.label.trim().length === 0)) {
        issue(`富回答场景 ${scene.id} 的 spec.stateBinding.label 必须是非空文本`);
      }
    }

    const stateIDs = new Set<string>();
    const sceneEvidenceIDs = new Set(scene.evidenceIDs);
    const validateStateEvidenceIDs = (value: unknown, path: string, maximum: number): void => {
      const evidenceIDs = value === undefined ? [] : richAnswerRenderPlanStringArray(value);
      if (evidenceIDs === undefined) {
        issue(`富回答场景 ${scene.id} 的 ${path} 必须是证据 id 数组`);
        return;
      }
      if (evidenceIDs.length > maximum) issue(`富回答场景 ${scene.id} 的 ${path} 最多包含 ${maximum} 个证据 id`);
      for (const evidenceID of evidenceIDs) {
        if (!allowedEvidenceIDs.has(evidenceID)) issue(`富回答场景 ${scene.id} 的 ${path} 引用了不存在的证据：${evidenceID}`);
        if (!sceneEvidenceIDs.has(evidenceID)) issue(`富回答场景 ${scene.id} 的 ${path} 必须引用 scene.evidenceIDs 中的证据：${evidenceID}`);
      }
    };

    for (const [stateIndex, rawState] of states.entries()) {
      const statePath = `spec.states[${stateIndex}]`;
      if (!richAnswerValidateNestedFields(
        scene,
        rawState,
        ["id", "title", "description", "objectIds", "objects", "readouts", "evidenceIDs"],
        statePath,
        issue,
      )) continue;
      if (richAnswerValidateIdentifier(scene, rawState.id, `${statePath}.id`, issue)) {
        if (stateIDs.has(rawState.id)) issue(`富回答场景 ${scene.id} 的三维状态 id 重复：${rawState.id}`);
        stateIDs.add(rawState.id);
      }
      const objectRefs = rawState.objectIds === undefined ? [] : richAnswerRenderPlanStringArray(rawState.objectIds);
      if (objectRefs === undefined) {
        issue(`富回答场景 ${scene.id} 的 ${statePath}.objectIds 必须是对象 id 数组`);
      } else {
        objectRefs.forEach((objectID) => {
          if (!objectIDs.has(objectID)) issue(`富回答场景 ${scene.id} 的 ${statePath}.objectIds 引用了不存在的共享对象：${objectID}`);
        });
      }

      const stateObjects = Array.isArray(rawState.objects) ? rawState.objects : [];
      if (rawState.objects !== undefined && !Array.isArray(rawState.objects)) issue(`富回答场景 ${scene.id} 的 ${statePath}.objects 必须是数组`);
      totalObjectCount += stateObjects.length;
      for (const [stateObjectIndex, rawStateObject] of stateObjects.entries()) {
        if (!isRecord(rawStateObject)) continue;
        const stateObjectPath = `${statePath}.objects[${stateObjectIndex}]`;
        if (richAnswerValidateIdentifier(scene, rawStateObject.id, `${stateObjectPath}.id`, issue)) {
          if (objectIDs.has(rawStateObject.id)) issue(`富回答场景 ${scene.id} 的三维对象 id 重复：${rawStateObject.id}`);
          objectIDs.add(rawStateObject.id);
        }
      }
      if (stateObjects.length > 0) {
        dataPointCount += validateRichAnswerScene3DSpec(
          scene,
          {
            title: rawState.title ?? spec.title,
            camera: spec.camera,
            layers: spec.layers ?? [],
            objects: stateObjects,
            coordinateUnits: spec.coordinateUnits,
            bounds: spec.bounds,
            slices: [],
            controls: spec.controls,
            focusEnabled: spec.focusEnabled,
          },
          registration,
          allowedEvidenceIDs,
          issue,
          false,
        );
      }

      const readouts = Array.isArray(rawState.readouts) ? rawState.readouts : [];
      if (rawState.readouts !== undefined && !Array.isArray(rawState.readouts)) issue(`富回答场景 ${scene.id} 的 ${statePath}.readouts 必须是数组`);
      if (readouts.length > 12) issue(`富回答场景 ${scene.id} 的 ${statePath}.readouts 最多支持 12 项`);
      const readoutIDs = new Set<string>();
      for (const [readoutIndex, rawReadout] of readouts.entries()) {
        const readoutPath = `${statePath}.readouts[${readoutIndex}]`;
        if (!richAnswerValidateNestedFields(scene, rawReadout, ["id", "label", "value", "unit", "evidenceIDs"], readoutPath, issue)) continue;
        if (richAnswerValidateIdentifier(scene, rawReadout.id, `${readoutPath}.id`, issue)) {
          if (readoutIDs.has(rawReadout.id)) issue(`富回答场景 ${scene.id} 的状态读数 id 重复：${rawReadout.id}`);
          readoutIDs.add(rawReadout.id);
        }
        if (typeof rawReadout.label !== "string" || rawReadout.label.trim().length === 0) issue(`富回答场景 ${scene.id} 的 ${readoutPath}.label 必须是非空文本`);
        if (!richAnswerRenderPlanFiniteNumber(rawReadout.value) && (typeof rawReadout.value !== "string" || rawReadout.value.trim().length === 0)) {
          issue(`富回答场景 ${scene.id} 的 ${readoutPath}.value 必须是有限数字或非空文本`);
        }
        validateStateEvidenceIDs(rawReadout.evidenceIDs, `${readoutPath}.evidenceIDs`, 8);
      }
      validateStateEvidenceIDs(rawState.evidenceIDs, `${statePath}.evidenceIDs`, 12);
    }

    if (isRecord(stateBinding) && typeof stateBinding.initial === "string" && !stateIDs.has(stateBinding.initial)) {
      issue(`富回答场景 ${scene.id} 的 spec.stateBinding.initial 引用了不存在的状态：${stateBinding.initial}`);
    }
    if (totalObjectCount === 0) {
      issue(`富回答场景 ${scene.id} 至少需要一个共享对象或状态对象`);
    }
    if (totalObjectCount > registration.budgets.maxNodes) {
      issue(`富回答场景 ${scene.id} 的三维对象总数超出预算：${totalObjectCount}/${registration.budgets.maxNodes}`);
    }
  }
  const slices = Array.isArray(spec.slices) ? spec.slices : [];
  if (spec.slices !== undefined && !Array.isArray(spec.slices)) issue(`富回答场景 ${scene.id} 的 spec.slices 必须是数组`);
  for (const [sliceIndex, rawSlice] of slices.entries()) {
    const slicePath = `spec.slices[${sliceIndex}]`;
    if (!richAnswerValidateNestedFields(scene, rawSlice, ["axis", "value", "thickness", "label", "color"], slicePath, issue)) continue;
    if (!["x", "y", "z"].includes(String(rawSlice.axis)) || !richAnswerRenderPlanFiniteNumber(rawSlice.value)) {
      issue(`富回答场景 ${scene.id} 的 ${slicePath} 轴或数值无效`);
    }
  }
  if (dataPointCount > registration.budgets.maxDataPoints) {
    issue(`富回答场景 ${scene.id} 的三维数据点超出预算：${dataPointCount}/${registration.budgets.maxDataPoints}`);
  }
  return dataPointCount;
}

function validateRichAnswerRenderPlan(
  scene: RichAnswerSceneParam,
  allowedEvidenceIDs: ReadonlySet<string>,
  allowedAssetIDs: ReadonlySet<string>,
  catalogRendererSelection: ReadonlySet<string> | undefined,
): number {
  const plan = scene.renderPlan;
  const validationIssues: string[] = [];
  const issue = (message: string): void => {
    if (!validationIssues.includes(message) && validationIssues.length < 24) {
      validationIssues.push(message);
    }
  };

  if (!plan || !isRecord(plan)) {
    throw new Error(`富回答场景 ${scene.id} 缺少 renderPlan 对象`);
  }

  const unknownPlanFields = richAnswerRenderPlanUnknownFields(plan, RICH_ANSWER_RENDER_PLAN_FIELDS);
  if (unknownPlanFields.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的 renderPlan 只能包含 ${rendererFieldList(RICH_ANSWER_RENDER_PLAN_FIELDS)}，不能包含 ${unknownPlanFields.join("、")}`,
    );
  }

  const renderer = plan.renderer;
  const registration = typeof renderer === "string"
    ? RICH_ANSWER_RENDERER_REGISTRATION_BY_ID.get(renderer)
    : undefined;
  if (typeof renderer !== "string" || renderer.trim().length === 0) {
    issue(`富回答场景 ${scene.id} 的 renderPlan.renderer 不能为空`);
  } else if (registration === undefined) {
    issue(`富回答场景 ${scene.id} 的 renderer 未注册：${renderer}`);
  } else if (!catalogRendererSelection?.has(renderer)) {
    issue(`富回答场景 ${scene.id} 的 renderer ${renderer} 不是本轮 ${RICH_ANSWER_CATALOG_TOOL} 返回的能力`);
  }

  if (registration !== undefined && plan.specVersion !== registration.specVersion) {
    issue(
      `富回答场景 ${scene.id} 的 specVersion 必须是 ${registration.specVersion}，当前为 ${String(plan.specVersion)}`,
    );
  }

  if (richAnswerRenderPlanContainsUnsafeText(plan)) {
    issue(`富回答场景 ${scene.id} 的 renderPlan 含脚本、网页、外链或事件处理文本；只能提交本地高层 JSON`);
  }

  const spec = isRecord(plan.spec) ? plan.spec : undefined;
  if (spec === undefined) {
    issue(`富回答场景 ${scene.id} 的 renderPlan.spec 必须是对象`);
  }
  let dataPointCount = 0;
  if (spec !== undefined && registration !== undefined) {
    switch (registration.validatorKind) {
      case "mathFunction":
        dataPointCount = validateRichAnswerMathFunctionSpec(scene, spec, registration, issue);
        break;
      case "chart":
        dataPointCount = validateRichAnswerChartSpec(scene, spec, registration, issue);
        break;
      case "geometry2D":
        dataPointCount = validateRichAnswerGeometry2DSpec(scene, spec, registration, issue);
        break;
      case "scene3D":
        dataPointCount = validateRichAnswerScene3DSpec(scene, spec, registration, allowedEvidenceIDs, issue);
        break;
      case "spatialMap":
        dataPointCount = validateRichAnswerSpatialMapSpec(scene, spec, registration, allowedAssetIDs, issue);
        break;
      case "imageOverlay":
        dataPointCount = validateRichAnswerImageOverlaySpec(scene, spec, registration, allowedAssetIDs, issue);
        break;
    }
  }

  const interactionBindings = Array.isArray(plan.interactionBindings)
    ? plan.interactionBindings
    : [];
  if (!Array.isArray(plan.interactionBindings)) {
    issue(`富回答场景 ${scene.id} 的 interactionBindings 必须是数组`);
  }
  const interactionIDs = new Set<string>();
  for (const [bindingIndex, binding] of interactionBindings.entries()) {
    if (!isRecord(binding)) {
      issue(`富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}] 必须是对象`);
      continue;
    }
    const unknownBindingFields = richAnswerRenderPlanUnknownFields(
      binding,
      RICH_ANSWER_RENDER_INTERACTION_FIELDS,
    );
    if (unknownBindingFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}] 包含未知字段：${unknownBindingFields.join("、")}`,
      );
    }
    if (!richAnswerRenderPlanValidIdentifier(binding.id)) {
      issue(`富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}].id 无效`);
    } else if (interactionIDs.has(binding.id)) {
      issue(`富回答场景 ${scene.id} 的 interactionBinding id 重复：${binding.id}`);
    } else {
      interactionIDs.add(binding.id);
    }
    if (typeof binding.kind !== "string" || !RICH_ANSWER_RENDER_INTERACTION_KINDS.has(binding.kind)) {
      issue(
        `富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}].kind 必须是 ${rendererFieldList(RICH_ANSWER_RENDER_INTERACTION_KINDS)} 之一`,
      );
    } else if (
      registration !== undefined &&
      !registration.interactionBindingKinds.includes(binding.kind)
    ) {
      issue(
        `富回答场景 ${scene.id} 的 renderer ${registration.id} 只接受 interactionBindings.kind=${registration.interactionBindingKinds.join("、")}；当前 ${binding.kind} 不受支持`,
      );
    }
    if (typeof binding.target !== "string" || binding.target.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}].target 不能为空`);
    }
    if (
      binding.actionName !== undefined &&
      (typeof binding.actionName !== "string" || !richAnswerRenderPlanValidActionName(binding.actionName))
    ) {
      issue(`富回答场景 ${scene.id} 的 interactionBindings[${bindingIndex}].actionName 只能是本地动作名，不得是代码或 URL`);
    }
  }

  const sourceBindings = Array.isArray(plan.sourceBindings) ? plan.sourceBindings : [];
  if (!Array.isArray(plan.sourceBindings)) {
    issue(`富回答场景 ${scene.id} 的 sourceBindings 必须是数组`);
  }
  const sceneEvidenceIDs = new Set(scene.evidenceIDs);
  const specEvidenceIDs = richAnswerRenderPlanSpecEvidenceIDs(spec);
  for (const evidenceID of specEvidenceIDs) {
    if (!allowedEvidenceIDs.has(evidenceID)) {
      issue(`富回答场景 ${scene.id} 的 renderPlan.spec 引用了不存在的证据：${evidenceID}`);
    }
    if (!sceneEvidenceIDs.has(evidenceID)) {
      issue(`富回答场景 ${scene.id} 的 renderPlan.spec evidenceID 必须列入 scene.evidenceIDs：${evidenceID}`);
    }
  }
  if (sceneEvidenceIDs.size !== scene.evidenceIDs.length) {
    issue(`富回答场景 ${scene.id} 的 scene.evidenceIDs 不能重复`);
  }
  const sourceBindingIDs = new Set<string>();
  const boundSceneEvidenceIDs = new Set<string>();
  const requiresSourcePreservingFallback = sourceBindings.some((binding) =>
    isRecord(binding) && binding.requiredForFallback === true
  );
  for (const [bindingIndex, binding] of sourceBindings.entries()) {
    if (!isRecord(binding)) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}] 必须是对象`);
      continue;
    }
    const unknownBindingFields = richAnswerRenderPlanUnknownFields(
      binding,
      RICH_ANSWER_RENDER_SOURCE_BINDING_FIELDS,
    );
    if (unknownBindingFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}] 包含未知字段：${unknownBindingFields.join("、")}`,
      );
    }
    if (!richAnswerRenderPlanValidIdentifier(binding.id)) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}].id 无效`);
    } else if (sourceBindingIDs.has(binding.id)) {
      issue(`富回答场景 ${scene.id} 的 sourceBinding id 重复：${binding.id}`);
    } else {
      sourceBindingIDs.add(binding.id);
    }
    if (!richAnswerRenderPlanValidIdentifier(binding.evidenceID)) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}].evidenceID 无效`);
    } else {
      if (!allowedEvidenceIDs.has(binding.evidenceID)) {
        issue(`富回答场景 ${scene.id} 的 sourceBinding 引用了不存在的证据：${binding.evidenceID}`);
      }
      if (!sceneEvidenceIDs.has(binding.evidenceID)) {
        issue(`富回答场景 ${scene.id} 的 sourceBinding 证据必须同时列入 scene.evidenceIDs：${binding.evidenceID}`);
      } else {
        boundSceneEvidenceIDs.add(binding.evidenceID);
      }
    }
    if (typeof binding.target !== "string" || binding.target.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}].target 不能为空`);
    }
    if (typeof binding.role !== "string" || !RICH_ANSWER_RENDER_SOURCE_BINDING_ROLES.has(binding.role)) {
      issue(
        `富回答场景 ${scene.id} 的 sourceBindings[${bindingIndex}].role 必须是 ${rendererFieldList(RICH_ANSWER_RENDER_SOURCE_BINDING_ROLES)} 之一`,
      );
    }
  }
  const missingSourceBindings = scene.evidenceIDs.filter((evidenceID) => !boundSceneEvidenceIDs.has(evidenceID));
  if (missingSourceBindings.length > 0) {
    issue(
      `富回答场景 ${scene.id} 的 scene.evidenceIDs 没有被 sourceBindings 覆盖：${missingSourceBindings.join("、")}`,
    );
  }

  const artifactRefs = Array.isArray(plan.artifactRefs) ? plan.artifactRefs : [];
  if (!Array.isArray(plan.artifactRefs)) {
    issue(`富回答场景 ${scene.id} 的 artifactRefs 必须是数组`);
  }
  const artifactIDs = new Set<string>();
  for (const [artifactIndex, artifact] of artifactRefs.entries()) {
    if (!isRecord(artifact)) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}] 必须是对象`);
      continue;
    }
    const unknownArtifactFields = richAnswerRenderPlanUnknownFields(
      artifact,
      RICH_ANSWER_RENDER_ARTIFACT_FIELDS,
    );
    if (unknownArtifactFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}] 包含未知字段：${unknownArtifactFields.join("、")}`,
      );
    }
    if (!richAnswerRenderPlanValidIdentifier(artifact.id)) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].id 无效`);
    } else if (artifactIDs.has(artifact.id)) {
      issue(`富回答场景 ${scene.id} 的 artifactRef id 重复：${artifact.id}`);
    } else {
      artifactIDs.add(artifact.id);
    }
    if (typeof artifact.mimeType !== "string" || artifact.mimeType.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].mimeType 不能为空`);
    }
    if (typeof artifact.role !== "string" || artifact.role.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].role 不能为空`);
    }
    if (typeof artifact.kind !== "string" || !RICH_ANSWER_RENDER_ARTIFACT_KINDS.has(artifact.kind)) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].kind 无效`);
    }
    if (
      artifact.checksum !== undefined &&
      (typeof artifact.checksum !== "string" || !/^[0-9a-f]{64}$/i.test(artifact.checksum))
    ) {
      issue(`富回答场景 ${scene.id} 的 artifactRefs[${artifactIndex}].checksum 必须是 64 位 sha256`);
    }
  }
  if (registration !== undefined && artifactRefs.length > registration.budgets.maxArtifacts) {
    issue(
      `富回答场景 ${scene.id} 的 artifactRefs 超出预算：${artifactRefs.length}/${registration.budgets.maxArtifacts}`,
    );
  }

  const fallback = isRecord(plan.fallback) ? plan.fallback : undefined;
  if (fallback === undefined) {
    issue(`富回答场景 ${scene.id} 的 fallback 必须是对象`);
  } else {
    const unknownFallbackFields = richAnswerRenderPlanUnknownFields(
      fallback,
      RICH_ANSWER_RENDER_FALLBACK_FIELDS,
    );
    if (unknownFallbackFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 fallback 包含未知字段：${unknownFallbackFields.join("、")}`,
      );
    }
    if (typeof fallback.mode !== "string" || !RICH_ANSWER_RENDER_FALLBACK_MODES.has(fallback.mode)) {
      issue(
        `富回答场景 ${scene.id} 的 fallback.mode 必须是 ${rendererFieldList(RICH_ANSWER_RENDER_FALLBACK_MODES)} 之一`,
      );
    }
    if (typeof fallback.reason !== "string" || fallback.reason.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 fallback.reason 不能为空`);
    }
    if (typeof fallback.text !== "string" || fallback.text.trim().length === 0) {
      issue(`富回答场景 ${scene.id} 的 fallback.text 不能为空`);
    }
    if (
      fallback.renderer !== undefined &&
      (typeof fallback.renderer !== "string" ||
        !RICH_ANSWER_RENDERER_REGISTRATION_BY_ID.has(fallback.renderer))
    ) {
      issue(`富回答场景 ${scene.id} 的 fallback.renderer 必须是已注册 renderer`);
    }
    if (
      fallback.artifactID !== undefined &&
      (typeof fallback.artifactID !== "string" || !artifactIDs.has(fallback.artifactID))
    ) {
      issue(`富回答场景 ${scene.id} 的 fallback.artifactID 必须来自 artifactRefs`);
    }
    if (requiresSourcePreservingFallback && fallback.preservesSourceBinding !== true) {
      issue(`富回答场景 ${scene.id} 的 sourceBindings 要求 fallback 保留来源绑定，fallback.preservesSourceBinding 必须为 true`);
    }
  }

  const qualityBudget = isRecord(plan.qualityBudget) ? plan.qualityBudget : undefined;
  if (qualityBudget === undefined) {
    issue(`富回答场景 ${scene.id} 的 qualityBudget 必须是对象`);
  } else {
    const unknownBudgetFields = richAnswerRenderPlanUnknownFields(
      qualityBudget,
      RICH_ANSWER_RENDER_QUALITY_BUDGET_FIELDS,
    );
    if (unknownBudgetFields.length > 0) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget 包含未知字段：${unknownBudgetFields.join("、")}`,
      );
    }
    if (typeof qualityBudget.allowAnimation !== "boolean") {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.allowAnimation 必须是布尔值`);
    }
    if (qualityBudget.allowWebGL !== false) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.allowWebGL 必须为 false`);
    }
    if (qualityBudget.allowNetwork !== false) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.allowNetwork 必须为 false`);
    }
    const estimatedNodes = spec === undefined
      ? 1 + interactionBindings.length + sourceBindings.length
      : richAnswerRenderPlanEstimatedNodes(spec, interactionBindings.length, sourceBindings.length);
    if (
      qualityBudget.maxNodes !== undefined &&
      (!richAnswerRenderPlanIntegerInRange(qualityBudget.maxNodes, estimatedNodes, registration?.budgets.maxNodes ?? LIMITS.richAnswerRenderPlanNodes))
    ) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.maxNodes 必须覆盖估算节点数 ${estimatedNodes}，且不超过 ${registration?.budgets.maxNodes ?? LIMITS.richAnswerRenderPlanNodes}`);
    }
    if (
      registration !== undefined &&
      qualityBudget.maxDataPoints !== undefined &&
      !richAnswerRenderPlanIntegerInRange(
        qualityBudget.maxDataPoints,
        dataPointCount,
        registration.budgets.maxDataPoints,
      )
    ) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget.maxDataPoints 必须覆盖实际数据点 ${dataPointCount}，且不超过 ${registration.budgets.maxDataPoints}`,
      );
    }
    if (
      registration !== undefined &&
      qualityBudget.maxArtifacts !== undefined &&
      !richAnswerRenderPlanIntegerInRange(
        qualityBudget.maxArtifacts,
        artifactRefs.length,
        registration.budgets.maxArtifacts,
      )
    ) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget.maxArtifacts 必须覆盖 artifactRefs 数量 ${artifactRefs.length}，且不超过 ${registration.budgets.maxArtifacts}`,
      );
    }
    const byteLength = richAnswerRenderPlanByteLength(plan);
    if (
      registration !== undefined &&
      qualityBudget.maxBytes !== undefined &&
      !richAnswerRenderPlanIntegerInRange(qualityBudget.maxBytes, byteLength, registration.budgets.maxBytes)
    ) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget.maxBytes 必须覆盖 renderPlan ${byteLength} bytes，且不超过 ${registration.budgets.maxBytes}`,
      );
    }
    if (registration !== undefined && byteLength > registration.budgets.maxBytes) {
      issue(
        `富回答场景 ${scene.id} 的 renderPlan 超出字节预算：${byteLength}/${registration.budgets.maxBytes}`,
      );
    }
    if (
      registration !== undefined &&
      qualityBudget.maxWidth !== undefined &&
      !richAnswerRenderPlanIntegerInRange(qualityBudget.maxWidth, 240, registration.budgets.maxWidth)
    ) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.maxWidth 超出 renderer 上限 ${registration.budgets.maxWidth}`);
    }
    if (
      registration !== undefined &&
      qualityBudget.maxHeight !== undefined &&
      !richAnswerRenderPlanIntegerInRange(qualityBudget.maxHeight, 160, registration.budgets.maxHeight)
    ) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.maxHeight 超出 renderer 上限 ${registration.budgets.maxHeight}`);
    }
    if (
      registration !== undefined &&
      qualityBudget.maxAnimationFPS !== undefined &&
      !richAnswerRenderPlanIntegerInRange(qualityBudget.maxAnimationFPS, 0, registration.budgets.maxAnimationFPS)
    ) {
      issue(`富回答场景 ${scene.id} 的 qualityBudget.maxAnimationFPS 超出 renderer 上限 ${registration.budgets.maxAnimationFPS}`);
    }
    if (
      registration !== undefined &&
      qualityBudget.maxInteractionLatencyMS !== undefined &&
      !richAnswerRenderPlanIntegerInRange(
        qualityBudget.maxInteractionLatencyMS,
        1,
        registration.budgets.maxInteractionLatencyMS,
      )
    ) {
      issue(
        `富回答场景 ${scene.id} 的 qualityBudget.maxInteractionLatencyMS 超出 renderer 上限 ${registration.budgets.maxInteractionLatencyMS}`,
      );
    }
  }

  if (validationIssues.length > 0) {
    throw new Error(validationIssues.join("\n"));
  }
  return interactionBindings.length > 0 ? 1 : 0;
}

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
        default: throw new Error(`未知 OpenUI 状态类型：${String(rule.valueKind)}`);
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
      declaration.arguments[nameIndex]!.column,
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
      declaration.arguments[stateIndex]!.column,
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
    argumentIndex === undefined ? declaration.column : declaration.arguments[argumentIndex]!.column,
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
          "windowSpan 是完整宽度；让 span 大于 0 且不超过总体极差，并让 [center - span/2, center + span/2] 完整落在最小值与最大值之间。例如覆盖 10–13 应使用 center=11.5、span=3",
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
        const initialValue = inputValues[index]!;
        if (maximum <= minimum || step <= 0 || initialValue < minimum || initialValue > maximum) {
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
    throw new Error(`富回答场景 ${scene.id} 缺少 program OpenUI 程序`);
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
    openUIProgramFailure(scene.id, "program 场景同时提交了旧 operations", "清空 operations，把交互全部放进 OpenUI 状态与组件");
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
        validateOpenUIArgument(scene, declaration, value, rules[index]!, index, statesByName, componentsByID);
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
        const declaration = componentsByID.get(orphaned[0]!)!;
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
    const evidenceArgument = declaration.arguments[evidenceIndex];
    if (evidenceArgument === undefined || evidenceArgument.kind === "null") continue;
    const evidenceID = openUIStringValue(declaration, evidenceIndex);
    if (!sceneEvidenceIDs.has(evidenceID)) {
      captureSemanticError(() =>
        openUIProgramFailure(
          scene.id,
          `组件 ${declaration.id} 引用了未在 scene.evidenceIDs 声明的证据 ${JSON.stringify(evidenceID)}`,
          "改用本场景 evidenceIDs 中的真实 id，或把经过 evidenceLedger 校验的 id 加入 scene.evidenceIDs",
          declaration.line,
          evidenceArgument.column,
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
    issue(
      `富回答场景 ${scene.id} 的 UI 数据或绑定超出预算：rows=${rows.length}/${LIMITS.richAnswerUIRows}，bindings=${bindings.length}/${LIMITS.richAnswerUIBindings}`,
    );
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

  for (const labelNode of ui.nodes.filter((node) => node.role === "label" && node.datasetID !== undefined)) {
    const siblingBindings = Array.from(new Set(
      ui.nodes
        .filter((node) =>
          node.id !== labelNode.id &&
          node.datasetID === labelNode.datasetID &&
          node.role !== "label" &&
          node.bindingID !== undefined
        )
        .map((node) => node.bindingID as string),
    ));
    if (siblingBindings.length === 1 && labelNode.bindingID !== siblingBindings[0]) {
      issue(
        `富回答场景 ${scene.id} 的 label 节点 ${labelNode.id} 必须与同数据集图形共享 binding ${siblingBindings[0]}，避免图形隐藏后留下孤立标签`,
      );
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

const pythonArtifactNumberSeriesSchema = Type.Array(Type.Number(), {
  minItems: 1,
  maxItems: LIMITS.pythonArtifactRows,
});

const pythonArtifactDataSchema = Type.Object(
  {
    values: Type.Optional(pythonArtifactNumberSeriesSchema),
    xValues: Type.Optional(pythonArtifactNumberSeriesSchema),
    yValues: Type.Optional(pythonArtifactNumberSeriesSchema),
    expression: Type.Optional(Type.String({ minLength: 1, maxLength: 500 })),
    domain: Type.Optional(Type.Object(
      {
        min: Type.Number(),
        max: Type.Number(),
        samples: Type.Integer({ minimum: 16, maximum: 1_000 }),
      },
      { additionalProperties: false },
    )),
  },
  { additionalProperties: false },
);

const pythonArtifactParametersSchema = Type.Object(
  {
    binCount: Type.Optional(Type.Integer({ minimum: 2, maximum: 100 })),
    ddof: Type.Optional(Type.Integer({ minimum: 0, maximum: 1 })),
    regressionKind: Type.Optional(Type.Literal("linear")),
  },
  { additionalProperties: false },
);

export default function weibeiExtension(pi: ExtensionAPI) {
  let requiredContextRevision: string | undefined;
  let lastReadContextRevision: string | undefined;
  let lastReadMemoryRevision: number | undefined;
  let richAnswerAttemptCount = 0;
  let richAnswerCatalogRevision: string | undefined;
  let richAnswerCatalogSelection: Set<OpenUIComponentName> | undefined;
  let richAnswerCatalogRendererSelection: Set<string> | undefined;
  let activeAnswerFormPolicy: AnswerFormPolicy = "automatic";
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
      const visualAssets = await readCurrentVisualAssets(snapshot);
      requiredContextRevision = snapshot.contextRevision;
      lastReadContextRevision = snapshot.contextRevision;
      richAnswerCatalogRevision = undefined;
      richAnswerCatalogSelection = undefined;
      richAnswerCatalogRendererSelection = undefined;
      activeAnswerFormPolicy = snapshot.answerFormPolicy;

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
                richAnswerGrounding: richAnswerSourceBindings(snapshot),
                visualInspection: {
                  availableAssetIDs: [...visualAssets.keys()],
                  tool: VISUAL_ASSET_TOOL,
                },
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
    async execute(_toolCallID, params) {
      const current = await readCurrentSnapshot();
      if (lastReadContextRevision !== current.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
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
          const evidenceLabel = item.evidenceLabel;
          if (!evidenceLabel || !item.jumpReference) return [];
          return [item.jumpReference, ...item.sectionJumpReferences, ...item.pageJumpReferences]
            .map((jumpReference) => [jumpReference, evidenceLabel] as const);
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
    name: COMPUTE_ARTIFACT_TOOL,
    label: "执行受控专业计算",
    description:
      "用魏碑随 App 打包的固定 Python 工人执行白名单确定性计算。只接受数列、成对数值或受限数学表达式；不执行模型生成代码，不联网，不读取任意文件。结果可作为标准图表、函数或其他注册渲染器的高层数据规格。",
    promptSnippet:
      "需要统计、线性回归、分箱或函数采样时调用受控 Python；保留产物哈希和来源标签，再把结果用于本轮目录返回的专业渲染器",
    parameters: Type.Object(
      {
        contextRevision: Type.String({ minLength: 1, maxLength: LIMITS.identifier }),
        requestID: Type.String({ minLength: 1, maxLength: 128 }),
        operation: Type.Union(
          PYTHON_ARTIFACT_OPERATIONS.map((value) => Type.Literal(value)),
        ),
        data: pythonArtifactDataSchema,
        parameters: Type.Optional(pythonArtifactParametersSchema),
        requestedOutput: Type.Object(
          {
            id: Type.String({ minLength: 1, maxLength: 128 }),
            kind: Type.Union(
              PYTHON_ARTIFACT_OUTPUT_KINDS.map((value) => Type.Literal(value)),
            ),
            mimeType: Type.Literal("application/json"),
            role: Type.String({ minLength: 1, maxLength: 128 }),
          },
          { additionalProperties: false },
        ),
        sourceEvidenceIDs: Type.Array(
          Type.String({ minLength: 1, maxLength: 300 }),
          { minItems: 1, maxItems: LIMITS.richAnswerEvidence },
        ),
        reason: Type.String({ minLength: 1, maxLength: 500 }),
      },
      { additionalProperties: false },
    ),
    executionMode: "sequential",
    async execute(_toolCallID, params) {
      const current = await readCurrentSnapshot();
      if (lastReadContextRevision !== current.contextRevision) {
        throw new Error(`必须先调用 ${CONTEXT_TOOL} 读取本轮当前上下文`);
      }
      if (params.contextRevision !== current.contextRevision) {
        throw new Error("受控计算请求引用了过期的魏碑上下文");
      }
      if (!safeArtifactIdentifier(params.requestID)) {
        throw new Error("受控计算 requestID 只能使用安全的字母、数字、点、下划线或连字符");
      }
      if (
        !safeArtifactIdentifier(params.requestedOutput.id) ||
        !safeArtifactIdentifier(params.requestedOutput.role)
      ) {
        throw new Error("受控计算产物 id/role 只能使用安全标识符");
      }

      const availableEvidence = richAnswerEvidenceText(current, searchedCourseItemIDs);
      const sourceEvidenceIDs = params.sourceEvidenceIDs.map((sourceLabel) => {
        const canonical = canonicalRichAnswerEvidenceLabel(sourceLabel, availableEvidence.keys());
        if (!canonical) {
          throw new Error(`受控计算引用了本轮不可用的来源标签：${sourceLabel}`);
        }
        return canonical;
      });
      if (new Set(sourceEvidenceIDs).size !== sourceEvidenceIDs.length) {
        throw new Error("受控计算的 sourceEvidenceIDs 不能重复");
      }

      const data: Record<string, unknown> = {};
      if (params.data.values !== undefined) data.values = params.data.values;
      if (params.data.xValues !== undefined) data.xValues = params.data.xValues;
      if (params.data.yValues !== undefined) data.yValues = params.data.yValues;
      if (params.data.expression !== undefined) data.expression = params.data.expression.trim();
      if (params.data.domain !== undefined) data.domain = params.data.domain;
      const operation = params.operation as PythonArtifactOperation;

      switch (operation) {
        case "compute_statistics": {
          if (!params.data.values?.length) {
            throw new Error("compute_statistics 需要非空 values");
          }
          const ddof = params.parameters?.ddof ?? 0;
          if (ddof >= params.data.values.length) {
            throw new Error("compute_statistics 的 ddof 必须小于样本数量");
          }
          break;
        }
        case "fit_regression":
          if (
            !params.data.xValues ||
            !params.data.yValues ||
            params.data.xValues.length < 2 ||
            params.data.xValues.length !== params.data.yValues.length
          ) {
            throw new Error("fit_regression 需要至少两组成对且等长的 xValues/yValues");
          }
          break;
        case "bin_distribution":
          if (!params.data.values?.length) {
            throw new Error("bin_distribution 需要非空 values");
          }
          break;
        case "sample_function":
          if (
            !params.data.expression?.trim() ||
            !params.data.domain ||
            !(params.data.domain.min < params.data.domain.max)
          ) {
            throw new Error("sample_function 需要受限 expression 和 min < max 的 domain");
          }
          break;
      }

      const parameters: Record<string, unknown> = {};
      if (params.parameters?.binCount !== undefined) {
        parameters.binCount = params.parameters.binCount;
      }
      if (params.parameters?.ddof !== undefined) parameters.ddof = params.parameters.ddof;
      if (params.parameters?.regressionKind !== undefined) {
        parameters.regressionKind = params.parameters.regressionKind;
      }
      const limits = {
        maxInputBytes: LIMITS.pythonArtifactInputBytes,
        maxOutputBytes: LIMITS.pythonArtifactOutputBytes,
        maxRows: LIMITS.pythonArtifactRows,
        maxColumns: LIMITS.pythonArtifactColumns,
        maxRuntimeMS: LIMITS.pythonArtifactRuntimeMS,
      };
      const request: Record<string, unknown> = {
        schemaVersion: 1,
        requestID: params.requestID,
        operation,
        data,
        parameters,
        requestedOutput: params.requestedOutput,
        limits,
        sourceEvidenceIDs,
      };
      const execution = await runPythonArtifactWorker(request, limits);
      const { result } = execution;
      if (result.artifacts.length !== 1) {
        throw new Error("受控 Python 工人必须且只能返回一个请求产物");
      }
      const artifact = result.artifacts[0]!;
      if (
        artifact.id !== params.requestedOutput.id ||
        artifact.kind !== params.requestedOutput.kind ||
        artifact.mimeType !== params.requestedOutput.mimeType ||
        artifact.role !== params.requestedOutput.role
      ) {
        throw new Error("受控 Python 工人返回的产物与 requestedOutput 不一致");
      }
      if (
        artifact.sourceEvidenceIDs.length !== sourceEvidenceIDs.length ||
        artifact.sourceEvidenceIDs.some((sourceID) => !sourceEvidenceIDs.includes(sourceID))
      ) {
        throw new Error("受控 Python 工人没有保留完整来源绑定");
      }
      if (
        result.diagnostics.some(
          (diagnostic) => typeof diagnostic !== "string" || diagnostic.length > 500,
        )
      ) {
        throw new Error("受控 Python 工人返回了非法诊断信息");
      }

      const details: ComputeArtifactToolDetails = {
        kind: "compute_artifact",
        schemaVersion: 1,
        contextRevision: current.contextRevision,
        requestID: result.requestID,
        operation: result.operation,
        workerVersion: result.workerVersion,
        pythonExecutable: execution.pythonExecutable,
        requestSHA256: execution.requestSHA256,
        outputSHA256: execution.outputSHA256,
        durationMS: execution.durationMS,
        artifacts: result.artifacts.map((produced) => ({
          id: produced.id,
          kind: produced.kind,
          mimeType: produced.mimeType,
          role: produced.role,
          sizeBytes: produced.sizeBytes,
          sha256: produced.sha256,
          sourceEvidenceIDs: produced.sourceEvidenceIDs,
        })),
        diagnostics: result.diagnostics,
      };
      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(
              {
                requestID: result.requestID,
                operation: result.operation,
                workerVersion: result.workerVersion,
                artifacts: result.artifacts,
                diagnostics: result.diagnostics,
                nextUse: [
                  "只把产物 payload 中与当前学习目标有关的高层数据放进本轮目录返回的 renderPlan.spec；不要复制成 raw 图表配置或代码。",
                  "把产物 id/kind/mimeType/sizeBytes/sha256 记录到 renderPlan.artifacts，并用 evidenceLedger 与 sourceBindings 继续绑定同一真实来源。",
                  "若计算结果与材料、单位或专业判断冲突，先解释冲突并重新核对，不用图形掩盖。",
                ],
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
    name: RICH_ANSWER_CATALOG_TOOL,
    label: "选择生成式视觉能力",
    description:
      "在提交富回答前，根据本轮学习动作、知识形状、来源媒介、直接操作和呈现表面，检索相关的魏碑深组件、注册专业渲染器与通用原语提示。它返回相关子集，不返回固定场景或标准答案；问题变化时可以重新调用。",
    promptSnippet:
      "先描述学习动作和知识形状，取得相关深组件、专业渲染器和长尾原语提示；不要让完整目录挤进每次生成",
    parameters: Type.Object(
      {
        learningAction: Type.Union(
          RICH_ANSWER_LEARNING_ACTIONS.map((value) => Type.Literal(value)),
        ),
        knowledgeShapes: Type.Array(
          Type.Union(RICH_ANSWER_KNOWLEDGE_SHAPES.map((value) => Type.Literal(value))),
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
        representationNeeds: Type.Optional(Type.Object(
          {
            spatialDimension: Type.Union(
              RICH_ANSWER_SPATIAL_DIMENSIONS.map((value) => Type.Literal(value)),
            ),
            temporalBehavior: Type.Union(
              RICH_ANSWER_TEMPORAL_BEHAVIORS.map((value) => Type.Literal(value)),
            ),
            dataOrigin: Type.Union(
              RICH_ANSWER_DATA_ORIGINS.map((value) => Type.Literal(value)),
            ),
            coordinateFrame: Type.Union(
              RICH_ANSWER_COORDINATE_FRAMES.map((value) => Type.Literal(value)),
            ),
            computeNeed: Type.Union(
              RICH_ANSWER_COMPUTE_NEEDS.map((value) => Type.Literal(value)),
            ),
            precisionNeed: Type.Union(
              RICH_ANSWER_PRECISION_NEEDS.map((value) => Type.Literal(value)),
            ),
            assetDependency: Type.Union(
              RICH_ANSWER_ASSET_DEPENDENCIES.map((value) => Type.Literal(value)),
            ),
          },
          { additionalProperties: false },
        )),
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
      const currentAllowedAssetIDs = richAnswerAllowedAssetIDs(
        current,
        searchedCourseItemIDs,
      );
      const selectedGroups = selectedOpenUIComponentGroups(
        params.knowledgeShapes,
        params.interactions,
      );
      const matchingRenderers = matchingRichAnswerRendererRegistrations(
        params.knowledgeShapes,
        params.representationNeeds,
        params.sourceMedium,
        params.knowledgeNatures,
        params.knowledgeObjects,
        params.knowledgeRelations,
        params.knowledgeProcesses,
        currentAllowedAssetIDs.length > 0,
      );
      const representationMatchingRenderers = matchingRenderers.filter((registration) =>
        richAnswerRendererRepresentationCoverage(
          registration,
          params.representationNeeds,
        ).fullySupported
      );
      const fullyMatchingRenderers = representationMatchingRenderers.filter((registration) =>
        richAnswerRendererInteractionCoverage(registration, params.interactions).fullySupported
      );
      const routeRecommendation = {
        decisionOwner: "agent",
        professionalRendererCoverage: fullyMatchingRenderers.length > 0
          ? "complete"
          : representationMatchingRenderers.length > 0
            ? "partial-interaction"
            : matchingRenderers.length > 0
              ? "representation-mismatch"
              : "none",
        fullyCoveredRendererIDs: fullyMatchingRenderers.map((registration) => registration.id),
        partiallyCoveredRendererIDs: representationMatchingRenderers
          .filter((registration) => !fullyMatchingRenderers.includes(registration))
          .map((registration) => registration.id),
        mismatchedRendererIDs: matchingRenderers
          .filter((registration) => !representationMatchingRenderers.includes(registration))
          .map((registration) => registration.id),
        reason: "这里只说明注册专业渲染器的覆盖与缺口，不替 Agent 决定路线。Agent 需比较标准表达质量、独特联动、来源资产、精度、性能和学习价值后自主选择。",
      };
      const selectedComponents = new Set<OpenUIComponentName>(OPENUI_ALWAYS_COMPONENTS);
      selectedGroups.forEach((group) => {
        OPENUI_COMPONENT_GROUPS[group].components.forEach((component) => selectedComponents.add(component));
      });
      richAnswerCatalogRevision = current.contextRevision;
      richAnswerCatalogSelection = selectedComponents;
      richAnswerCatalogRendererSelection = new Set(
        RICH_ANSWER_RENDERER_REGISTRATIONS.map((registration) => registration.id),
      );

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
          representationNeeds: params.representationNeeds,
          reason: params.reason.trim(),
        },
        selectedGroups: selectedGroups.map((group) => ({
          id: group,
          label: OPENUI_COMPONENT_GROUPS[group].label,
        })),
        sourceBindings: richAnswerSourceBindings(current, searchedCourseItemIDs),
        controlledComputation: {
          tool: COMPUTE_ARTIFACT_TOOL,
          adapter: "bundled-fixed-python-worker",
          coverage: params.representationNeeds?.computeNeed === "heavyOrExternal"
            ? "partial-light-deterministic-only"
            : params.representationNeeds?.computeNeed === "lightDeterministic"
              ? "complete-for-allowlisted-operations"
              : "available-when-needed",
          operations: PYTHON_ARTIFACT_OPERATIONS,
          outputKinds: PYTHON_ARTIFACT_OUTPUT_KINDS,
          sourceEvidenceIDs:
            richAnswerSourceBindings(current, searchedCourseItemIDs).readableSourceLabels,
          rules: [
            "只执行固定统计、线性回归、分箱和受限函数采样；不执行模型代码。",
            "无网络、无任意文件访问、无 shell；每次返回长度、哈希、来源和耗时。",
            "产物只提供数据/规格，再由 Agent 选择本轮目录返回的专业 renderer、成熟深组件或长尾组合。",
          ],
        },
        actionBus: {
          learningActions: RICH_ANSWER_LEARNING_ACTIONS,
          interactions: RICH_ANSWER_INTERACTION_ACTIONS,
          rule: "交互只能落到 program 状态、renderPlan interactionBindings 或 ui binding；不得提交 HTML/JS 回调、外部事件或自造 action 类型。",
        },
        routeRecommendation,
        candidateComparison: {
          notRanked: true,
          routes: [
          {
            route: "renderPlan",
            candidates: representationMatchingRenderers.map((registration) => registration.id),
            fullyCovered: fullyMatchingRenderers.map((registration) => registration.id),
            reason: "成熟专业渲染器提供标准表达、统一主题、精度和性能边界；是否采用取决于本题学习价值。",
          },
          {
            route: "program",
            candidates: selectedGroups,
            reason: "保留成熟深组件；当它提供专业渲染器没有的刷选、实验联动、证据阅读或领域机制时，可以成为更优选择。",
          },
          {
            route: "ui",
            candidates: ["restricted-composable-ui"],
            reason: "仅用于前两条都不贴合的真正长尾组合，不用于低级重画标准图表、函数、几何、地图、图像或三维。",
          },
          {
            route: "text",
            candidates: ["source-grounded-text"],
            reason: "可视化没有明确学习增益、能力不足或来源不够时保持正常文本。",
          },
          ],
          rule: "这些是对称候选，不是固定排名；不能按题号或路线标签强迫选择。",
        },
        planningLoop: {
          steps: [
            "判断纯文本是否已经足够；足够则停止，不为装饰生成 UI。",
            "写清用户要看懂的判断、要观察的对象/关系/过程、初始状态、操作后变化和证据。",
            "先声明维度、动态性、数据来源、坐标系、计算、精度和原图依赖，再按知识形状匹配注册专业渲染器并检查交互覆盖。",
            "只有前两者都不贴合且形态本身确属长尾时，才组合 ui；能力不足则保留正文并诚实表达边界。",
            "生成正文与内联体验交错的结果；局部 UI 不重复整篇回答。",
            "提交前核对初始状态可读、操作真实改变目标状态、文案与计算一致、窄宽仍完整。",
          ],
          completionQuestions: [
            "去掉体验块，用户是否会明显更难理解？",
            "初始状态是否已经显示与学习目标有关的对象或差异？",
            "主要操作是否改变了对应图形、读数或知识状态？",
            "局部标题、说明、选区和读数是否与运行时实际状态一致？",
            "缩窄到对话栏后，它是否仍像回答的一部分而不是独立网页？",
          ],
        },
        expressionPriority: [
          "对称比较注册专业渲染器与成熟深组件：前者强调标准表达、精度与性能，后者可能提供不可替代的刷选、实验联动、状态机制或证据阅读。",
          "requestedRepresentationCoverage 核对维度、动态性、数据来源、坐标系、计算、精度和原图依赖；requestedInteractionCoverage 核对交互，但两者都不替 Agent 作最终选择。",
          "标准图表、函数、几何、物理仿真、地图、图像叠层和三维并不因为当前适配器缺少某个互动就自动变成长尾；不要用 ui 的点线、形状和标签重画成熟形态。",
          "最后才看通用原语：只有专业渲染器和成熟深组件都不贴合、且知识形态本身确属长尾组合时才用 ui；否则保留正文并诚实说明当前表达边界。",
        ],
        renderPlan: {
          useWhen:
            "本轮 matchingRenderers 非空时，把它作为与成熟 program 对称比较的候选；完整覆盖不等于强制采用，部分覆盖也不等于必须放弃。提交时 interactionBindings.kind 必须来自对应 renderer 的 interactionBindingKinds，不能把 learning interaction 名称直接当作 binding kind。",
          matchingRenderers: richAnswerRendererCapabilityDeclarations(
            params.knowledgeShapes,
            params.interactions,
            params.representationNeeds,
            params.sourceMedium,
            params.knowledgeNatures,
            params.knowledgeObjects,
            params.knowledgeRelations,
            params.knowledgeProcesses,
            currentAllowedAssetIDs,
          ),
          rendererIndex: RICH_ANSWER_RENDERER_REGISTRATIONS.map((registration) => ({
            id: registration.id,
            label: registration.label,
            specVersion: registration.specVersion,
            knowledgeShapes: registration.knowledgeShapes,
            interactionActions: registration.interactionActions,
            assetDependencies: registration.representationSupport.assetDependencies,
          })),
          sceneContract:
            "scene 三选一时只保留 renderPlan，不同时提交 program 或 ui。renderer/specVersion 必须来自 rendererIndex；matchingRenderers 提供当前请求的详细规格。若目标能力只出现在 rendererIndex，应按真实语义重新调用目录取得详细规格，不要猜 schema。",
        },
        program: {
          catalogSize: OPENUI_COMPONENT_CATALOG_SIZE,
          allowedComponentCount: selectedComponents.size,
          signatures: openUIComponentCatalog(Array.from(selectedComponents)),
          syntaxRules: [
            "每行只声明一个状态或组件；先声明子组件，再由父组件引用。",
            "组件引用数组写 [step1, step2]，引用 id 不加引号；不要在参数中嵌套组件调用。",
            "枚举参数只能写签名或指导中列出的固定值；FunctionPlot.family 当前只能写 \"quadratic\"，不是公式输入框。",
          ],
        },
        ui: {
          useWhen: "返回的深组件与注册专业渲染器都无法诚实表达、且当前知识形态本身确属长尾组合时，才组合通用原语；适配器暂缺、互动未覆盖或想做得更花哨都不是把标准图表、函数、几何、物理、地图、图像叠层、三维硬拆成低级点线树的理由。",
          guidance: COMPOSABLE_PRIMITIVE_CATALOG.split("\n"),
          intentGuidance: [
            "不要按 knowledgeNatures 机械套固定 role 组合；曲线、点、区域、图像、形状、序列、读数都只是可组合的视觉语法。",
            "line/path/point/metric 可以在函数、过程、机制、论证或证据场景中成为主表达，前提是它们真实编码了知识对象、关系或状态，而不是装饰线。",
            "非过程题不要只用 sequence、metric、text、label、grid 变换排版；数量、空间、机制、证据、图像、比较和计算题要让可绑定控件驱动非文字图元或空间编码出现可检查状态变化。",
            "只有当材料和问题确实依赖空间位置、图像局部或对象外形时，才需要选择 image、region、shape、area 等对应图元；不要为通过形式检查而硬凑。",
            "有控件时，控件必须改变与学习目标绑定的可见图元或读数；可以同时协调多个控件、图层和状态。",
            "用户或材料明确指定的观察动作、测量方法和结论边界必须进入可见节点语义；不要只写在 expressionPlan，也不要用不相干的通用控件替代。",
            "knowledgeObjects 要在可见标签里留下关键锨点；knowledgeRelations 可由有标注的曲线、数据、读数或序列结构编码；knowledgeProcesses 若是拖动、切换、观察等互动，可由真实 binding 结构兑现，不必把计划长句逐字复制进 UI。",
            "visualPrimitives 必须列出实际会使用的 ui role，后续 weibei_rich_answer 会校验声明与 UI 节点一致。",
          ],
        },
        guardrails: [
          "返回的是相关能力子集和签名，不是固定模板、场景数量上限或标准答案。",
          "program 只能使用本次返回的签名；renderPlan 只能使用本次返回的 renderer/specVersion；需要另一类能力时重新调用目录。",
          "ui 必须从 rootID 开始形成单父节点树；孤立节点、只在不可达 dataset 里放证据、控件不驱动图元或读数都会被拒绝。",
          "不要引入 Card、Tabs、KPI、Slide、Gallery 这类整页看板组件；要把视觉、控件和读数作为回答流里的内联体验块。",
          "先核对结论、公式、单位、数值、方向和因果边界；不能验证的结果不得交给界面假装计算。",
          "无论 program、renderPlan 或 ui，最终内容、单位、关系与来源都必须由本轮真实材料支撑。",
        ],
      };
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        details: {
          kind: "rich_answer_catalog",
          contextRevision: current.contextRevision,
          selectedGroups,
          allowedComponents: Array.from(selectedComponents),
          allowedRenderers: representationMatchingRenderers.map((registration) => ({
            id: registration.id,
            specVersion: registration.specVersion,
          })),
        },
      };
    },
  });

  pi.registerTool({
    name: RICH_ANSWER_TOOL,
    label: "插入生成式视觉体验",
    description:
      `当可视化或直接操作能明显帮助理解时，在 Agent 回答流中插入受控的生成式视觉体验块。提交前必须先调用 ${RICH_ANSWER_CATALOG_TOOL}；program 只能使用本轮目录返回的签名，renderPlan 只能使用本轮目录返回的注册渲染器，ui 使用受控通用原语。它不是第二篇回答或完整网页。${RICH_ANSWER_FAMILY_CONTRACT}`,
    promptSnippet:
      "先判断文本是否足够；需要时在 program、renderPlan、ui 三条出口里选最贴合的一条，不要画 SVG、套完整网页外壳或从头复述正文",
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
          richAnswerCatalogSelection === undefined ||
          richAnswerCatalogRendererSelection === undefined
        ) {
          richAnswerFault({
            code: "catalog_required",
            jsonPath: "$.scenes",
            field: "scenes",
            message: `提交富回答前必须先调用 ${RICH_ANSWER_CATALOG_TOOL} 取得本轮相关能力子集`,
            humanFixHint: `先调用 ${RICH_ANSWER_CATALOG_TOOL} 取得本轮 program/renderPlan/ui 能力，再重发完整 RichAnswerUI。`,
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
          humanFixHint: "修正正文中的来源标签或场景标记；若不需要指定插入点，可省略标记让未引用场景顺延到正文末尾，然后完整重发 RichAnswerUI。",
        });
      }
      const evidenceIDs: string[] = params.evidenceLedger.map((entry) => entry.id);
      if (new Set(evidenceIDs).size !== evidenceIDs.length) {
        richAnswerFault({
          code: "duplicate_id",
          jsonPath: "$.evidenceLedger[*].id",
          field: "id",
          message: "富回答证据 id 必须唯一",
          humanFixHint: "为 evidenceLedger 去重并同步 scene.evidenceIDs、program 证据组件、renderPlan sourceBindings 或 ui evidenceIDs 后完整重发。",
        });
      }

      const allowedAssetIDs = new Set<string>(
        richAnswerAllowedAssetIDs(current, searchedCourseItemIDs),
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
      const renderPlanNormalizations: string[] = [];
      for (const [sceneIndex, submittedScene] of params.scenes.entries()) {
        const scene: RichAnswerSceneParam = submittedScene;
        const scenePath = `$.scenes[${sceneIndex}]`;
        const sceneLayerCount = [
          scene.program,
          scene.renderPlan,
          scene.ui,
        ].filter((layer) => layer !== undefined).length;
        if (sceneLayerCount !== 1) {
          richAnswerFault({
            code: "scene_layer_choice",
            jsonPath: scenePath,
            sceneID: scene.id,
            field: "program/renderPlan/ui",
            message: `富回答场景 ${scene.id} 必须且只能提交 program、renderPlan、ui 之一`,
            humanFixHint: "深组件只保留 program；专业渲染器只保留 renderPlan；通用原语只保留 ui。删除其他出口后完整重发 RichAnswerUI。",
          });
        }
        renderPlanNormalizations.push(
          ...normalizeRichAnswerScene3DSpec(scene).map((message) => `${scene.id}: ${message}`),
        );
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
          ...(scene.renderPlan?.sourceBindings ?? []).map((binding) => binding.evidenceID),
        ].filter((evidenceID): evidenceID is string => evidenceID !== undefined);
        if (referencedEvidenceIDs.some((evidenceID) => !allowedEvidenceIDs.has(evidenceID))) {
          richAnswerFault({
            code: "missing_evidence",
            jsonPath: `${scenePath}.evidenceIDs`,
            sceneID: scene.id,
            field: "evidenceIDs",
            message: `富回答场景 ${scene.id} 引用了不存在的证据`,
            humanFixHint: "让 scene、renderPlan sourceBindings、program 证据组件或 ui 可达节点/数据行只引用 evidenceLedger 中已有 id，并把证据真实绑定后完整重发。",
          });
        }
        try {
          operationCount += scene.program !== undefined
            ? validateRichAnswerProgram(scene, richAnswerCatalogSelection)
            : scene.renderPlan !== undefined
              ? validateRichAnswerRenderPlan(
                scene,
                allowedEvidenceIDs,
                allowedAssetIDs,
                richAnswerCatalogRendererSelection,
              )
              : validateRichAnswerUI(scene, allowedEvidenceIDs, allowedAssetIDs);
        } catch (error) {
          if (error instanceof RichAnswerFaultError) throw error;
          const sceneLayer = scene.program !== undefined
            ? "program"
            : scene.renderPlan !== undefined
              ? "renderPlan"
              : "ui";
          richAnswerFault({
            code: scene.program !== undefined
              ? "invalid_openui_program"
              : scene.renderPlan !== undefined
                ? "invalid_render_plan"
                : "invalid_t2_ui",
            jsonPath: `${scenePath}.${sceneLayer}`,
            sceneID: scene.id,
            field: sceneLayer,
            message: error instanceof Error ? error.message : String(error),
            humanFixHint: scene.program !== undefined
              ? "按行列诊断修正 program；不要局部 patch，必须带完整 envelope、完整 scenes 和 evidenceLedger 重发。"
              : scene.renderPlan !== undefined
                ? (() => {
                    const registration = RICH_ANSWER_RENDERER_REGISTRATION_BY_ID.get(
                      scene.renderPlan.renderer,
                    );
                    if (!registration) {
                      return "按注册 renderer、specVersion、高层 spec、interactionBindings、sourceBindings、fallback 和 qualityBudget 诊断修正 renderPlan；不要改成 raw option、脚本、HTML 或 SVG path。";
                    }
                    return [
                      `若当前 renderer ${registration.id}@${registration.specVersion} 仍与本题知识对象和学习动作匹配，就按目录字段形状修正高层规格；若错误暴露的是路线不匹配，返回本轮目录重新对称比较 renderer、program 与 ui，不要机械保留当前路线，也不要直接退回低级通用点线。`,
                      registration.specGuidance,
                      `字段形状：${JSON.stringify({
                        minimalSpecSkeleton: registration.minimalSpecSkeleton,
                        nestedFieldContracts: richAnswerRendererNestedFieldContracts(registration),
                      })}`,
                      "仍需完整重发 envelope、scenes 与 evidenceLedger；禁止 raw option、脚本、HTML 或 SVG path。",
                    ].join(" ");
                  })()
                : "按 UI 节点、数据集、binding 和证据诊断修正 ui 原语树；不要局部 patch，必须完整重发。",
          });
        }
      }

      const details: RichAnswerToolDetails = {
        kind: "rich_answer",
        contextRevision: current.contextRevision,
        normalizations: renderPlanNormalizations,
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
            text: "完整 narrative 与生成式视觉体验已通过魏碑的来源、内联位置、program/renderPlan/ui、状态、预算和资源边界校验，并会作为同一篇回答显示。请勿另写或改写第二份正文，只需简短结束本轮。",
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
    richAnswerCatalogRevision = undefined;
    richAnswerCatalogSelection = undefined;
    richAnswerCatalogRendererSelection = undefined;
    searchedCourseItemIDs.clear();

    let purpose = "unavailable";
    let revision = "unavailable";
    let answerFormPolicy: AnswerFormPolicy = "automatic";
    let readableSourceLabels: string[] = [];
    let explicitRichAnswerRequested = false;
    try {
      const snapshot = await readCurrentSnapshot();
      purpose = snapshot.purpose;
      revision = snapshot.contextRevision;
      answerFormPolicy = snapshot.answerFormPolicy;
      readableSourceLabels = evidenceLabels(snapshot);
      explicitRichAnswerRequested =
        answerFormPolicy === "automatic" &&
        snapshot.workflow !== "noteMaking" &&
        /(?:富回答|可调|交互|互动|图示|函数图|关系图|时间线|图像叠层|叠层|模拟|实验|rich answer|interactive|adjustable|diagram|function graph|relationship graph|timeline|image overlay|simulation|experiment)/iu.test(
          snapshot.question,
        );
      requiredContextRevision = revision;
      activeAnswerFormPolicy = answerFormPolicy;
    } catch {
      requiredContextRevision = undefined;
      activeAnswerFormPolicy = "automatic";
    }

    const answerFormPolicyInstruction =
      answerFormPolicy === "textOnly"
        ? "本轮 answerFormPolicy=textOnly：即使问题文本出现“富回答、图示、互动、实验、叠层”等词，也必须保持普通文本；不得调用 weibei_ui_catalog 或 weibei_rich_answer；不要向用户暴露这是内部策略。"
        : answerFormPolicy === "partialRichAllowed"
          ? "本轮 answerFormPolicy=partialRichAllowed：允许在证据充分且学习收益明显时使用富回答，但问题文本里的“富回答、图示、互动、实验、叠层”等词不构成强制调用。"
          : explicitRichAnswerRequested
            ? "本轮用户明确指定富回答或互动形态。当前证据足够时必须调用 weibei_rich_answer；不能满足时必须在正文明确说明限制，不得静默退成纯文本。"
            : "本轮没有检测到用户指定富回答形态；由你按学习收益判断是否调用 weibei_rich_answer。";

    const sourceAvailabilityInstruction =
      readableSourceLabels.length === 0
        ? "本轮没有可读材料、笔记或选区来源标签：不得引用空材料/空笔记标签，不得提交富回答；只用普通文本诚实说明当前缺少可读材料证据。"
        : `本轮可读来源标签：${readableSourceLabels.join("、")}；课程事实引用必须逐字使用这些标签或本轮课程搜索返回的 evidenceLabel。`;

    const turnContract = [
      "<weibei_turn>",
      `purpose: ${JSON.stringify(purpose)}`,
      `contextRevision: ${JSON.stringify(revision)}`,
      `answerFormPolicy: ${JSON.stringify(answerFormPolicy)}`,
      "本轮第一次工具调用必须是 weibei_context。调用成功前不得回答事实问题，也不得提出富回答或笔记建议。",
      "当前材料、笔记和选区是本轮直接证据；课程关联需要读课程地图或搜索；学习历史需要读学习记忆。",
      "学习记忆只能说明用户的学习状态，不能作为课程事实证据。",
      sourceAvailabilityInstruction,
      "富回答必须提交 schemaVersion 2，并为每个 scene 在 program、renderPlan、ui 三条表达出口中只选择一条；它作为 Agent 回答流中的生成式视觉体验块，可以组合多个视觉、控件、读数和实验步骤，但不是第二篇回答或完整网页。模型负责提交受控组件程序、注册渲染计划或通用原语数据，魏碑宿主用本地渲染内核呈现。",
      `提交富回答前必须调用 ${RICH_ANSWER_CATALOG_TOOL}，按本轮知识形状取得相关组件子集；不要让完整目录或旧回合组件记忆代替本轮选择。`,
      RICH_ANSWER_FAMILY_CONTRACT,
      answerFormPolicyInstruction,
      "</weibei_turn>",
    ].join("\n");

    return { systemPrompt: `${event.systemPrompt}\n\n${turnContract}` };
  });

  pi.on("tool_call", (event) => {
    if (!ALLOWED_TOOLS.has(event.toolName)) {
      return {
        block: true,
        reason: `魏碑 Agent 只允许读取随 App 打包的 Skill，并调用受控的上下文、课程、记忆、富回答与笔记建议工具`,
      };
    }

    if (event.toolName === READ_TOOL) {
      const requestedPath = (event.input as { path?: unknown }).path;
      const normalizedPath = canonicalReadPath(requestedPath);
      if (!normalizedPath || !RICH_ANSWER_SKILL_BY_PATH.has(normalizedPath)) {
        return {
          block: true,
          reason: "魏碑只允许 Pi 原生 read 读取随 App 打包的富回答 Skill，不能读取其它文件。",
        };
      }
    }

    if (
      activeAnswerFormPolicy === "textOnly" &&
      (event.toolName === RICH_ANSWER_CATALOG_TOOL || event.toolName === RICH_ANSWER_TOOL)
    ) {
      return {
        block: true,
        reason:
          "本轮 answerFormPolicy=textOnly：只能普通文本回答。不要调用富回答目录或富回答工具，也不要向用户暴露内部策略、工具名称或被阻止原因。",
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

  pi.on("tool_result", async (event) => {
    if (event.toolName !== READ_TOOL || event.isError) return;
    const requestedPath = (event.input as { path?: unknown }).path;
    const normalizedPath = canonicalReadPath(requestedPath);
    if (!normalizedPath) return;
    const skill = RICH_ANSWER_SKILL_BY_PATH.get(normalizedPath);
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
