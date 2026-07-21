#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const TARGET_BREAKDOWN = {
  "rich": 40,
  "text-only": 6,
  "degradation": 9,
  "invalid-protocol": 1,
};
const TARGET_TOTAL = 56;
const DATASET_PATH = ".build/rich-answer-evidence";

function toString(v, fallback = "缺失") {
  if (v === null || v === undefined) return fallback;
  if (typeof v === "string") return v.trim() || fallback;
  return String(v);
}

function boolText(v) {
  return v === undefined || v === null ? "缺失" : v ? "是" : "否";
}

function safeJsonString(value, fallback = "缺失") {
  if (value === undefined) return fallback;
  if (value === null) return "null";
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return fallback;
  }
}

function nowStamp() {
  return new Date().toISOString();
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function fileExists(filePath) {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

function dirExists(dirPath) {
  try {
    return fs.statSync(dirPath).isDirectory();
  } catch {
    return false;
  }
}

function readJSON(filePath) {
  try {
    const content = fs.readFileSync(filePath, "utf8");
    return {
      ok: true,
      value: JSON.parse(content),
      missing: false,
      parseError: null,
      path: filePath,
    };
  } catch (error) {
    return {
      ok: false,
      value: null,
      missing: !fileExists(filePath),
      parseError: error?.message || String(error),
      path: filePath,
    };
  }
}

function readRawText(filePath) {
  try {
    return {
      ok: true,
      value: fs.readFileSync(filePath, "utf8"),
      missing: false,
      path: filePath,
      parseError: null,
    };
  } catch (error) {
    return {
      ok: false,
      value: null,
      missing: !fileExists(filePath),
      path: filePath,
      parseError: error?.message || String(error),
    };
  }
}

function parseArgs() {
  const args = process.argv.slice(2);
  const out = {
    source: DATASET_PATH,
    force: false,
    output: null,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--run-dir") {
      out.runDir = path.resolve(args[index + 1]);
      index += 1;
      continue;
    }
    if (arg === "--run-id") {
      out.runId = args[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--source") {
      out.source = args[index + 1];
      index += 1;
      continue;
    }
    if (arg === "--output" || arg === "--out") {
      out.output = path.resolve(args[index + 1]);
      index += 1;
      continue;
    }
    if (arg === "--force") {
      out.force = true;
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

function usage() {
  return [
    "用途：将 .build/rich-answer-evidence/<runID>/ 下的证据目录生成离线验收包。",
    "",
    "用法:",
    "  node generate-evidence-package.mjs --run-dir <run-dir> --output <out-dir> [--force]",
    "  node generate-evidence-package.mjs --run-id <runID> --source .build/rich-answer-evidence --output <out-dir> [--force]",
    "",
    "参数:",
    "  --run-dir      直接指定证据目录（如 .build/rich-answer-evidence/xxx）",
    "  --run-id       指定 runID（与 --source 一起使用）",
    "  --source       run 目录父路径，默认 .build/rich-answer-evidence",
    "  --output/--out 输出目录",
    "  --force        如输出目录已存在，允许覆盖",
    "  --help         显示此帮助",
  ].join("\n");
}

function normalizeRunKind(kind) {
  if (!kind) return "unknown";
  const value = String(kind).toLowerCase();
  if (value.includes("invalid")) return "invalid-protocol";
  if (value.includes("degradation")) return "degradation";
  if (value.includes("text")) return "text-only";
  if (value.includes("rich")) return "rich";
  if (value.includes("success")) return "rich";
  return value;
}

function pickCaseName(caseDir) {
  return path.basename(caseDir);
}

function pickScreenshots(caseDir) {
  const files = dirExists(caseDir)
    ? fs.readdirSync(caseDir).filter((item) => /\.png$/i.test(item))
    : [];

  const score = (name, target) => {
    const lower = name.toLowerCase();
    const t = target.toLowerCase();
    if (lower === `${t}.png`) return 100;
    if (new RegExp(`^${t}[ _-]`).test(lower)) return 90;
    if (new RegExp(`[._-]${t}[._-]?`).test(lower)) return 80;
    if (lower.includes(t)) return 70;
    if (t === "after" && /(after|after-action|afterstate|after_state|final|result)/i.test(lower)) return 50;
    if (t === "before" && /(before|pre|init|start|beforestate|before_state)/i.test(lower)) return 50;
    return 0;
  };

  const choose = (target) => {
    let best = null;
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

function asMarkdownSafe(value) {
  if (value === undefined || value === null) return "缺失";
  if (typeof value !== "string") return safeJsonString(value, "缺失");
  return value;
}

function toAssetId(caseID, repetition) {
  return `case_${String(caseID || "unknown").replace(/[^a-zA-Z0-9\u4e00-\u9fff_-]/g, "_")}_r${String(repetition || 0)}`;
}

function safeNumber(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

function collectImageAssets(caseDir, outputAssetsDir, caseID, repetition, report) {
  const screenshots = pickScreenshots(caseDir);
  const asset = {
    before: null,
    after: null,
    missing: [],
  };

  const assetBase = toAssetId(caseID, repetition);
  ensureDir(outputAssetsDir);

  const copyIfExist = (kind, filename) => {
    if (!filename) return null;
    const source = path.join(caseDir, filename);
    if (!fileExists(source)) return null;
    const targetName = `${assetBase}-${kind}-${filename}`;
    const target = path.join(outputAssetsDir, targetName);
    fs.copyFileSync(source, target);
    report.copiedFiles += 1;
    return `assets/${targetName}`;
  };

  asset.before = copyIfExist("before", screenshots.before) || null;
  asset.after = copyIfExist("after", screenshots.after) || null;
  if (!asset.before) asset.missing.push("before截图缺失");
  if (!asset.after) asset.missing.push("after截图缺失");
  return asset;
}

function readRecordFromEntry(entry, runRoot, outputAssetsDir, report) {
  const runCasePath = path.isAbsolute(entry.recordPath || "")
    ? entry.recordPath
    : path.join(runRoot, toString(entry.recordPath, ""));

  const candidatePaths = new Set();
  if (runCasePath) candidatePaths.add(runCasePath);
  if (dirExists(runCasePath)) candidatePaths.add(path.join(runCasePath, "record.json"));
  if (dirExists(path.dirname(runCasePath))) {
    candidatePaths.add(path.join(path.dirname(runCasePath), "record.json"));
    candidatePaths.add(path.join(path.dirname(runCasePath), "request.json"));
    candidatePaths.add(path.join(path.dirname(runCasePath), "reply.json"));
    candidatePaths.add(path.join(path.dirname(runCasePath), "validation.json"));
  }

  const caseDir = runCasePath && !runCasePath.endsWith(".json")
    ? runCasePath
    : path.dirname(runCasePath || "");

  const recordResult = readJSON(path.join(caseDir || runRoot, "record.json"));
  if (!recordResult.ok) {
    report.missingFields.push(`缺失 record.json: ${path.join(caseDir || runRoot, "record.json")}`);
  }

  const record = recordResult.value || {};
  const prompt = readJSON(path.join(caseDir, "request.json"));
  const reply = readJSON(path.join(caseDir, "reply.json"));
  const validation = readJSON(path.join(caseDir, "validation.json"));

  if (!prompt.ok) report.missingFields.push(`缺失 request.json: ${path.join(caseDir, "request.json")}`);
  if (!reply.ok) report.missingFields.push(`缺失 reply.json: ${path.join(caseDir, "reply.json")}`);
  if (!validation.ok) report.missingFields.push(`缺失 validation.json: ${path.join(caseDir, "validation.json")}`);

  const caseSnapshot = record.caseSnapshot || {};
  const shapeDecision = record.shapeDecision || {};
  const expr = record.expressionPlan || {};
  const source = record.sourceBinding || {};
  const repair = record.repairAndRetest || {};
  const status = toString(record.status || entry.status, "unknown");

  const caseID = toString(caseSnapshot.id || entry.caseID || record.caseID, "unknown-case");
  const repetition = safeNumber(record.repetition ?? entry.repetition);
  const sequence = safeNumber(record.sequence ?? entry.sequence);

  const images = collectImageAssets(caseDir, outputAssetsDir, caseID, repetition, report);
  const t1Programs = Array.isArray(expr.t1Programs) ? expr.t1Programs : [];
  const t2Compositions = Array.isArray(expr.t2Compositions) ? expr.t2Compositions : [];

  return {
    runID: toString(record.runID || entry.runID),
    caseID,
    repetition: repetition || 0,
    sequence: sequence || 0,
    caseKind: normalizeRunKind(entry.caseKind || caseSnapshot.caseKind || "unknown"),
    subject: toString(caseSnapshot.subject || record.subject || "未定义学科"),
    question: asMarkdownSafe(caseSnapshot.question || "未定义题目"),
    materialTitle: toString(caseSnapshot.materialTitle || prompt.value?.materialTitle),
    materialKind: toString(caseSnapshot.materialKind || prompt.value?.materialKind),
    materialText: toString(caseSnapshot.materialText || prompt.value?.materialText),
    selectionTitle: toString(caseSnapshot.selectionTitle || prompt.value?.selectionTitle),
    selectionText: toString(caseSnapshot.selectionText || prompt.value?.selectionText),
    status,
    elapsedSeconds: safeNumber(record.elapsedSeconds),
    expectedShape: toString(shapeDecision.expectedShape),
    actualShape: toString(shapeDecision.actualShape),
    preferredSurface: toString(shapeDecision.preferredSurface, "缺失"),
    directManipulation: boolText(shapeDecision.directManipulation),
    t1SceneCount: safeNumber(shapeDecision.t1SceneCount) || (Array.isArray(t1Programs) ? t1Programs.length : 0),
    t2SceneCount: safeNumber(shapeDecision.t2SceneCount) || (Array.isArray(t2Compositions) ? t2Compositions.length : 0),
    narrativeCharacterCount: safeNumber(shapeDecision.narrativeCharacterCount),
    toolAndProtocolValidation: {
      status: toString(validation.value?.status || record.toolAndProtocolValidation?.status),
      validationKind: toString(validation.value?.validationKind || record.toolAndProtocolValidation?.validationKind),
      passedChecks: validation.value?.passedChecks || record.toolAndProtocolValidation?.passedChecks || [],
      issues: validation.value?.issues || record.toolAndProtocolValidation?.issues || [],
      protocolDiagnostics: validation.value?.protocolDiagnostics || record.toolAndProtocolValidation?.protocolDiagnostics || [],
      toolTrace: validation.value?.toolTrace || record.toolAndProtocolValidation?.toolTrace || [],
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
      toolTrace: (reply.value?.toolTrace || record.modelRawReply?.toolTrace || []).slice(),
      richAnswerExists: Boolean(reply.value?.richAnswer || record.modelRawReply?.richAnswer),
      replyJSON: safeJsonString(reply.value, "缺失"),
    },
    failureReason: toString(record.failureReason || entry.failureReason, "无"),
    repairAndRetest: {
      previousRunID: toString(repair.previousRunID, "缺失"),
      previousStatus: toString(repair.previousStatus, "缺失"),
      repairNote: toString(repair.repairNote),
      isRetest: boolText(repair.isRetest),
    },
    expectedCapabilityFamilies: caseSnapshot.expectedCapabilityFamilies || [],
    userBenefitCriteria: caseSnapshot.userBenefitCriteria || [],
    rejectedOrDegradedBehaviors: caseSnapshot.rejectedOrDegradedBehaviors || [],
    beforeImage: images.before,
    afterImage: images.after,
    missing: {
      beforeScreenshot: images.before ? "已提供" : "缺失",
      afterScreenshot: images.after ? "已提供" : "缺失",
      request: prompt.ok ? "已提供" : "缺失",
      reply: reply.ok ? "已提供" : "缺失",
      validation: validation.ok ? "已提供" : "缺失",
      record: recordResult.ok ? "已提供" : "缺失",
    },
  };
}

function collectRecordsFromRunDir(runDir, report) {
  const runJSON = readJSON(path.join(runDir, "run.json"));
  const indexJSON = readJSON(path.join(runDir, "index.json"));

  if (!runJSON.ok) report.missingFields.push("缺失 run.json");
  if (!indexJSON.ok) report.missingFields.push("缺失 index.json");

  const runRootPath = runDir;
  const entries = (indexJSON.value?.records || []);
  const assetsDir = path.join(report.outputDir, "assets");
  let records = [];

  if (Array.isArray(entries) && entries.length > 0) {
    for (const entry of entries) {
      records.push(readRecordFromEntry(entry, runRootPath, assetsDir, report));
    }
  } else {
    // 兼容未写入 index.json 的场景：按目录扫描
    const dirs = dirExists(runRootPath)
      ? fs.readdirSync(runRootPath, { withFileTypes: true })
      : [];
    for (const repetitionDir of dirs.filter((item) => item.isDirectory() && /^repetition-/.test(item.name))) {
      const repPath = path.join(runRootPath, repetitionDir.name);
      const repNumber = Number(String(repetitionDir.name).replace("repetition-", "")) || 0;
      for (const caseDirEnt of fs.readdirSync(repPath, { withFileTypes: true }).filter((item) => item.isDirectory())) {
        const caseID = pickCaseName(caseDirEnt.name);
        const caseDir = path.join(repPath, caseDirEnt.name);
        const entry = {
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
        records.push(readRecordFromEntry(entry, runRootPath, assetsDir, report));
      }
    }
  }

  // 记录唯一性：避免重复 entry（极端情况下可能重复）
  const unique = new Map();
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

function buildGroupData(records) {
  const map = new Map();
  const subjects = new Set();
  const shapes = new Set();
  const statuses = new Set();
  const repetitions = new Set();
  const kindCounts = { rich: 0, "text-only": 0, degradation: 0, "invalid-protocol": 0, unknown: 0 };

  for (const item of records) {
    const key = item.caseID || "unknown-case";
    if (!map.has(key)) map.set(key, { caseID: key, attempts: [] });
    map.get(key).attempts.push(item);
    subjects.add(item.subject || "未定义学科");
    shapes.add(item.actualShape || "缺失");
    statuses.add(item.status || "缺失");
    repetitions.add(String(item.repetition || "0"));
    const kind = item.caseKind || "unknown";
    if (kindCounts[kind] === undefined) kindCounts.unknown += 1;
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
      if (a.subject !== b.subject) return String(a.subject).localeCompare(String(b.subject));
      return String(a.caseID).localeCompare(String(b.caseID));
    });

  const counts = {
    status: Array.from(statuses).sort().reduce((acc, status) => {
      acc[status] = records.filter((item) => item.status === status).length;
      return acc;
    }, {}),
    byKind: kindCounts,
    repetitionCounts: Array.from(repetitions).sort((a, b) => Number(a) - Number(b)).reduce((acc, value) => {
      acc[value] = records.filter((item) => String(item.repetition) === String(value)).length;
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
      repetitions: Array.from(repetitions).sort((a, b) => Number(a) - Number(b)),
    },
    counts,
  };
}

function buildPayload(runDir, runID, runData, report) {
  const grouped = buildGroupData(runData.records);
  const runMetadata = runData.runMetadata || {};

  const statusCountActual = Object.entries(grouped.counts.status).reduce((acc, [k, v]) => {
    acc[k] = v;
    return acc;
  }, {});

  const expectedTotals = Object.entries(TARGET_BREAKDOWN).reduce((acc, [kind, count]) => {
    acc[kind] = count;
    return acc;
  }, {});
  expectedTotals.total = TARGET_TOTAL;

  const actualTotalByKind = Object.entries(grouped.counts.byKind).reduce((acc, [kind, count]) => {
    acc[kind] = count;
    return acc;
  }, {});
  actualTotalByKind.total = runData.records.length;

  const subjectGap = runData.records.reduce((acc, item) => {
    acc[item.subject] = (acc[item.subject] || 0) + 1;
    return acc;
  }, {});

  const missingFlags = Object.entries(grouped.counts.byKind).map(([kind, count]) => {
    const expected = TARGET_BREAKDOWN[kind] || 0;
    return {
      kind,
      expected,
      actual: count,
      gap: expected - count,
    };
  });

  return {
    generatedAt: nowStamp(),
    run: {
      runID: runID || runMetadata.runID || path.basename(runDir),
      rootPath: runMetadata.rootPath || runDir,
      createdAt: runMetadata.createdAt || "缺失",
      repairedFrom: runMetadata.retestOfRunID || "无",
      repairNote: runMetadata.repairNote || "无",
      continueAfterFailure: toString(runMetadata.continueAfterFailure, "无"),
      requestedIDs: runMetadata.requestedIDs || [],
      filters: runMetadata.filters || [],
      sourceRoot: path.resolve(path.dirname(runDir)),
      sourceRunDir: runDir,
    },
    overview: {
      totalActualRecords: runData.records.length,
      totalExpectedTarget: TARGET_TOTAL,
      expectedByKind: expectedTotals,
      actualByKind: actualTotalByKind,
      statusCount: statusCountActual,
      subjectCount: subjectCount,
      missingGapByKind: missingFlags,
      filterOptions: grouped.filters,
      repetitionCount: grouped.filters.repetitions.length,
      completionState: actualTotalByKind.total > 0 ? "待用户验收" : "未开始",
    },
    cases: grouped.groups,
    missingFields: report.missingFields,
  };

  function subjectCount() {
    return Object.keys(subjectGap).length;
  }
}

function makeHtml(outputPath, payload) {
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
      margin-top: 10px;
      background: #fffaf1;
      padding: 10px 12px;
    }
    .case-head {
      display: flex;
      gap: 8px;
      align-items: center;
      justify-content: space-between;
      flex-wrap: wrap;
    }
    .case-head b { font-size: 16px; }
    .small { font-size: 12px; color: var(--ink-soft);}
    .attempt {
      border-top: 1px dashed var(--line);
      margin-top: 10px;
      padding-top: 10px;
    }
    .attempt h4 {
      margin: 0 0 5px 0;
      font-size: 14px;
    }
    .images {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
      margin-top: 8px;
    }
    .img-block {
      border: 1px dashed var(--line);
      padding: 6px;
      text-align: center;
      background: #fff;
    }
    .img-block img {
      max-width: 100%;
      max-height: 220px;
      display: block;
      margin: 0 auto;
      background: #eee;
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
  `;
  const html = `<!DOCTYPE html>
  <html lang="zh">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>富回答56题验收包</title>
    <style>${css}</style>
  </head>
  <body>
    <div class="page">
      <div class="title">
        <h1>富回答验收包（离线浏览）</h1>
        <div class="meta-line">用于 40+6+9+1 场景的验收展示；读取来源：<strong>${escapeHtml(payload.run.sourceRunDir)}</strong></div>
        <div class="meta-line">本包仅聚合原始留档，不执行任何联网请求；未完成用户验收前请勿对外结项</div>
        <div class="pending-pill">${payload.overview.completionState}</div>
      </div>

      <section class="panel">
        <h2>总览</h2>
        <div class="grid3">
          <div>runID: <strong>${escapeHtml(payload.run.runID)}</strong></div>
          <div>run 目录: ${escapeHtml(payload.run.sourceRunDir)}</div>
          <div>生成时间: ${escapeHtml(payload.generatedAt)}</div>
          <div>目标总数: ${payload.overview.totalExpectedTarget}</div>
          <div>实际条目: ${payload.overview.totalActualRecords}</div>
          <div>轮次数量: ${payload.overview.repetitionCount}</div>
        </div>
        <div class="badges">
          <span class="badge">待用户验收</span>
          ${payload.missingFields.slice(0, 3).map((item) => `<span class=\"badge warn\">${escapeHtml(item)}</span>`).join("")}
          ${payload.missingFields.length === 0 ? "<span class=\"badge ok\">关键字段完整读取</span>" : ""}
        </div>
        <table class="summary-table">
          <thead>
            <tr><th>维度</th><th>应有</th><th>实际</th><th>差值</th><th>判定</th></tr>
          </thead>
          <tbody>
            <tr><td>rich（参数/可视化）</td><td>40</td><td>${payload.overview.actualByKind["rich"]}</td><td>${payload.overview.missingGapByKind.find((i) => i.kind === "rich").gap}</td><td>${(payload.overview.actualByKind["rich"] >= 40 ? "达标" : "不足")}</td></tr>
            <tr><td>text-only（纯文本）</td><td>6</td><td>${payload.overview.actualByKind["text-only"]}</td><td>${payload.overview.missingGapByKind.find((i) => i.kind === "text-only").gap}</td><td>${(payload.overview.actualByKind["text-only"] >= 6 ? "达标" : "不足")}</td></tr>
            <tr><td>degradation（降级）</td><td>9</td><td>${payload.overview.actualByKind["degradation"]}</td><td>${payload.overview.missingGapByKind.find((i) => i.kind === "degradation").gap}</td><td>${(payload.overview.actualByKind["degradation"] >= 9 ? "达标" : "不足")}</td></tr>
            <tr><td>invalid-protocol（非法协议）</td><td>1</td><td>${payload.overview.actualByKind["invalid-protocol"]}</td><td>${payload.overview.missingGapByKind.find((i) => i.kind === "invalid-protocol").gap}</td><td>${(payload.overview.actualByKind["invalid-protocol"] >= 1 ? "达标" : "不足")}</td></tr>
            <tr><td>总计</td><td>56</td><td>${payload.overview.totalActualRecords}</td><td>${TARGET_TOTAL - payload.overview.totalActualRecords}</td><td>${payload.overview.totalActualRecords >= 56 ? "达标" : "不足"}</td></tr>
          </tbody>
        </table>
      </section>

      <section class="panel">
        <h2>状态 / 学科 / 形态 / 轮次过滤</h2>
        <div class="filter-row">
          <select id="filter-status"><option value="__all">全部状态</option></select>
          <select id="filter-subject"><option value="__all">全部学科</option></select>
          <select id="filter-shape"><option value="__all">全部形态</option></select>
          <select id="filter-repetition"><option value="__all">全部轮次</option></select>
        </div>
        <input id="filter-keyword" type="text" placeholder="关键词搜索（题目 / caseID）" />
      </section>

      <section class="panel">
        <h2>缺失字段说明（不允许伪造）</h2>
        <div id="missing-list" class="small"></div>
      </section>

      <section>
        <h2>逐题验收（支持三轮差异对照）</h2>
        <div id="case-list"></div>
      </section>
    </div>
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

function buildClientScript() {
  return `
const data = window.__EVIDENCE_DATA || {};
const cases = Array.isArray(data.cases) ? data.cases : [];
const filters = data.overview && data.overview.filterOptions ? data.overview.filterOptions : {};

function e(v) {
  if (v === undefined || v === null) return "";
  return String(v)
    .replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function fillMissingList() {
  const container = document.getElementById("missing-list");
  const list = (data.missingFields || []);
  if (!list || list.length === 0) {
    container.innerHTML = "<span class='badge ok'>当前 run 未发现缺失字段</span>";
    return;
  }
  container.innerHTML = list.slice(0, 30).map((item) => `<div class="badge warn">缺失：${e(item)}</div>`).join("");
}

function buildOptions() {
  const statusEl = document.getElementById("filter-status");
  const subjectEl = document.getElementById("filter-subject");
  const shapeEl = document.getElementById("filter-shape");
  const repEl = document.getElementById("filter-repetition");

  const all = (array) => Array.from(new Set(array || [])).filter(Boolean).sort();
  const statusList = all((filters.statuses || []).concat((cases.flatMap((c) => c.attempts || []).map((a) => a.status))));
  const subjectList = all((filters.subjects || []).concat(cases.map((c) => c.subject)));
  const shapeList = all((filters.shapes || []).concat(cases.flatMap((c) => c.attempts || []).map((a) => a.actualShape)));
  const repetitionList = all((filters.repetitions || []).concat(cases.flatMap((c) => c.attempts || []).map((a) => String(a.repetition))));

  statusList.forEach((status) => statusEl.appendChild(new Option(status, status)));
  subjectList.forEach((subject) => subjectEl.appendChild(new Option(subject, subject)));
  shapeList.forEach((shape) => shapeEl.appendChild(new Option(shape, shape)));
  repetitionList.forEach((rep) => repEl.appendChild(new Option(`第 ${rep} 轮`, rep)));
}

function getFilters() {
  return {
    status: document.getElementById("filter-status").value,
    subject: document.getElementById("filter-subject").value,
    shape: document.getElementById("filter-shape").value,
    repetition: document.getElementById("filter-repetition").value,
    keyword: (document.getElementById("filter-keyword").value || "").trim().toLowerCase(),
  };
}

function isMatchedAttempt(attempt, filter) {
  if (!attempt) return false;
  if (filter.status !== "__all" && attempt.status !== filter.status) return false;
  if (filter.subject !== "__all" && attempt.subject !== filter.subject) return false;
  if (filter.shape !== "__all" && attempt.actualShape !== filter.shape) return false;
  if (filter.repetition !== "__all" && String(attempt.repetition) !== String(filter.repetition)) return false;
  if (filter.keyword) {
    const keyword = filter.keyword;
    const fields = [attempt.caseID, attempt.question, attempt.subject, attempt.caseKind];
    const matched = fields.some((item) => String(item || "").toLowerCase().includes(keyword));
    if (!matched) return false;
  }
  return true;
}

function statusBadge(value) {
  const isPass = value === "passed";
  const cls = isPass ? "ok" : "warn";
  return `<span class="badge ${cls}">${e(value || "缺失")}</span>`;
}

function safeJson(txt) {
  if (!txt) return "缺失";
  return `<div class="code">${e(txt)}</div>`;
}

function renderAttempt(attempt) {
  const missing = attempt.missing || {};
  const t1Rows = (attempt.expressionPlan?.t1Programs || []).map((item) => {
    return `<li>scene:${e(item.sceneID)} / family:${e(item.family)} / version:${e(item.version)} / direct:${e(item.directManipulation)} / maxHeight:${e(item.maxHeight)} / components:${e((item.componentNames || []).join(",") || "无")}</li>`;
  }).join("");

  const t2Rows = (attempt.expressionPlan?.t2Compositions || []).map((item) => {
    return `<li>scene:${e(item.sceneID)} / family:${e(item.family)} / rootID:${e(item.rootID)} / roles:${e((item.roles || []).join(",") || "无")} / nodes:${e(item.nodeCount)} / rows:${e(item.dataRowCount)}</li>`;
  }).join("");

  const imageBlock = (label, src, miss) => {
    if (src) {
      return `<div class="img-block"><div>${label}</div><img src="${e(src)}" alt="${label}" loading="lazy" /></div>`;
    }
    return `<div class="img-block missing">${label}：${miss}</div>`;
  };

  const protocolItems = (attempt.toolAndProtocolValidation?.passedChecks || []).map((item) => `<li>${e(item)}</li>`).join("");
  const issueItems = (attempt.toolAndProtocolValidation?.issues || []).map((item) => `<li>${e(item)}</li>`).join("");
  const diagItems = (attempt.toolAndProtocolValidation?.protocolDiagnostics || []).map((item) => `<li>${e(item)}</li>`).join("");
  const sourceLines = [
    `<li>textSource: ${e((attempt.sourceBinding?.textSourceLabels || []).join("、") || "无")}</li>`,
    `<li>ledger: ${e((attempt.sourceBinding?.evidenceLedgerLabels || []).join("、") || "无")}</li>`,
    `<li>sceneIDs: ${e((attempt.sourceBinding?.sceneEvidenceIDs || []).join("、") || "无")}</li>`,
    `<li>expectedMatch: ${attempt.sourceBinding?.hasExpectedSource ? "是" : "否"}</li>`,
  ].join("");

  const delta = `耗时:${e(attempt.elapsedSeconds)}s / 形态:${e(attempt.actualShape)} / 直操:${e(attempt.directManipulation)} / 预期:${e(attempt.expectedShape)} / 状态:${e(attempt.status)}`;

  return `
      <div class="attempt">
        <h4>第 ${e(attempt.repetition)} 轮</h4>
        <div class="badges">
          ${statusBadge(attempt.status)}
          <span class="badge">形态 ${e(attempt.actualShape)}</span>
          <span class="badge">T1 ${e(attempt.t1SceneCount)} / T2 ${e(attempt.t2SceneCount)}</span>
          <span class="badge">耗时 ${e(attempt.elapsedSeconds ?? "缺失")}s</span>
          <span class="badge ${attempt.status === "passed" ? "ok" : "warn"}">${attempt.status === "passed" ? "已达标" : "待复核"}</span>
        </div>
        <div class="small">T1/T2 计划摘要：${e(delta)}</div>
        <div class="badges">
          <span class="badge">request: ${e(missing.request)}</span>
          <span class="badge">reply: ${e(missing.reply)}</span>
          <span class="badge">validation: ${e(missing.validation)}</span>
          <span class="badge">record: ${e(missing.record)}</span>
          <span class="badge">before截图: ${e(missing.beforeScreenshot)}</span>
          <span class="badge">after截图: ${e(missing.afterScreenshot)}</span>
        </div>
        <p><strong>失败原因:</strong> ${e(attempt.failureReason || "无")}</p>
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
        <div class="images">
          ${imageBlock("操作前", attempt.beforeImage, "before截图缺失")}
          ${imageBlock("操作后", attempt.afterImage, "after截图缺失")}
        </div>
      </div>
  `;
}

function buildDiff(attempts) {
  if (!attempts || attempts.length < 2) return "";
  const lines = [];
  for (let index = 1; index < attempts.length; index += 1) {
    const prev = attempts[index - 1];
    const cur = attempts[index];
    const delta = safeDelta(prev.elapsedSeconds, cur.elapsedSeconds);
    lines.push({
      label: `第${prev.repetition}→第${cur.repetition}轮`,
      text: `状态 ${e(prev.status)}→${e(cur.status)}；形态 ${e(prev.actualShape)}→${e(cur.actualShape)}；耗时 ${e(delta)}`,
    });
  }
  return `<div class="diff">${lines.map((line) => `<div class="item"><strong>${line.label}</strong><br/>${line.text}</div>`).join("")}</div>`;
}

function safeDelta(prev, next) {
  const p = Number(prev || 0);
  const n = Number(next || 0);
  if (Number.isNaN(p) || Number.isNaN(n)) return "缺失";
  const v = (n - p).toFixed(3);
  const prefix = n >= p ? "+" : "";
  return `${prefix}${v}s`;
}

function renderCase(caseItem, filter) {
  const visibleAttempts = (caseItem.attempts || []).filter((attempt) => isMatchedAttempt(attempt, filter));
  if (visibleAttempts.length === 0) return "";

  const caseTag = caseItem.caseID || "unknown";
  const head = `<div class="case-head"><b>${e(caseItem.caseID || "unknown")}</b><span class="small">${e(caseItem.subject || "未定义学科")} / ${e(caseItem.caseKind || "unknown")} / ${e(caseItem.question || "").slice(0, 90)}</span></div>`;
  const attemptsBlocks = visibleAttempts.map(renderAttempt).join("");
  const diffHtml = buildDiff(visibleAttempts);
  return `<article class="case-item">
    ${head}
    <div class="badges">
      ${caseItem.attempts.some((item) => item.status !== "passed") ? '<span class="badge warn">待用户验收</span>' : '<span class="badge ok">已通过形态</span>'}
      <span class="badge">重复数：${caseItem.attempts.length}</span>
      <span class="badge">caseID：${e(caseTag)}</span>
    </div>
    ${diffHtml ? `<div><strong>三轮差异</strong>${diffHtml}</div>` : ""}
    ${attemptsBlocks}
  </article>`;
}

function render() {
  const filter = getFilters();
  const list = document.getElementById("case-list");
  const rendered = cases
    .map((item) => renderCase(item, filter))
    .filter(Boolean)
    .join("");
  list.innerHTML = rendered || '<div class="badge warn">当前筛选无结果</div>';
}

document.getElementById("filter-status").addEventListener("change", render);
document.getElementById("filter-subject").addEventListener("change", render);
document.getElementById("filter-shape").addEventListener("change", render);
document.getElementById("filter-repetition").addEventListener("change", render);
document.getElementById("filter-keyword").addEventListener("input", render);

buildOptions();
fillMissingList();
render();
`;
}

function escapeHtml(value) {
  return toString(value, "")
    .replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      "\"": "&quot;",
      "'": "&#39;",
    })[char]);
}

function dedupeArray(list) {
  return Array.from(new Set(list)).filter((value) => value !== null && value !== undefined && `${value}`.trim().length > 0);
}

function run() {
  const argv = parseArgs();
  if (argv.help || process.argv.length <= 2) {
    console.log(usage());
    return;
  }

  if (!argv.runDir && !argv.runId) {
    throw new Error("必须提供 --run-dir 或 --run-id");
  }

  const runDir = argv.runDir || path.resolve(path.resolve(argv.source || DATASET_PATH), argv.runId);
  const output = argv.output || path.join(process.cwd(), `rich-answer-evidence-view-${argv.runId || path.basename(runDir)}`);

  if (!dirExists(runDir)) {
    throw new Error(`证据目录不存在：${runDir}`);
  }
  if (dirExists(output) && !argv.force) {
    throw new Error(`输出目录已存在：${output}；请加 --force 覆盖或换一个输出路径`);
  }
  if (dirExists(output)) {
    fs.rmSync(output, { recursive: true, force: true });
  }
  ensureDir(output);

  const report = { missingFields: [], outputDir: output, copiedFiles: 0 };
  const runData = collectRecordsFromRunDir(runDir, report);
  if (!Array.isArray(runData.records) || runData.records.length === 0) {
    report.missingFields.push("未识别到任何 record.json，验收包仍可生成但不可用于实际验收");
  }

  const runID = (runData.runMetadata && runData.runMetadata.runID) || argv.runId || path.basename(runDir);
  const payload = buildPayload(runDir, runID, runData, report);
  makeHtml(output, payload);

  const summary = [
    `runID: ${runID}`,
    `输出目录: ${output}`,
    `记录数: ${payload.overview.totalActualRecords}`,
    `缺失项: ${payload.missingFields.length}`,
    `已复制图片: ${report.copiedFiles}`,
    `生成时间: ${payload.generatedAt}`,
  ];
  console.log("富回答验收包已生成：\n" + summary.join("\n"));
}

run();
