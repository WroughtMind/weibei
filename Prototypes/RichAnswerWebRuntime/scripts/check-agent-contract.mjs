import assert from "node:assert/strict";
import {
  cp,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const packageRoot = resolve(scriptDirectory, "..");
const repositoryRoot = resolve(packageRoot, "../..");
const agentResourcesRoot = join(
  repositoryRoot,
  "Sources/WeiBeiCore/AgentResources",
);
const extensionPath = join(agentResourcesRoot, "extension.ts");
const stubsPath = join(scriptDirectory, "agent-contract-stubs.d.ts");

const program = ts.createProgram(
  [extensionPath, stubsPath],
  {
    allowSyntheticDefaultImports: true,
    lib: ["lib.es2022.d.ts", "lib.dom.d.ts"],
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    noEmit: true,
    noImplicitAny: false,
    skipLibCheck: true,
    strict: false,
    target: ts.ScriptTarget.ES2022,
  },
);
const typeErrors = ts
  .getPreEmitDiagnostics(program)
  .filter((diagnostic) => diagnostic.category === ts.DiagnosticCategory.Error);
assert.equal(
  typeErrors.length,
  0,
  ts.formatDiagnosticsWithColorAndContext(typeErrors, {
    getCanonicalFileName: (name) => name,
    getCurrentDirectory: () => repositoryRoot,
    getNewLine: () => "\n",
  }),
);

const extensionSource = await readFile(extensionPath, "utf8");
assert.match(
  extensionSource,
  /pi\.on\("before_agent_start"[\s\S]*?verifiedVisualAssetBytes\.clear\(\);/u,
  "each new Agent turn must clear the trusted visual-asset byte table",
);
const transpiled = ts.transpileModule(extensionSource, {
  compilerOptions: {
    module: ts.ModuleKind.ESNext,
    target: ts.ScriptTarget.ES2022,
  },
  fileName: extensionPath,
  reportDiagnostics: true,
});
const transpileErrors = (transpiled.diagnostics ?? []).filter(
  (diagnostic) => diagnostic.category === ts.DiagnosticCategory.Error,
);
assert.equal(transpileErrors.length, 0, "Agent extension must transpile cleanly");

const temporaryRoot = await mkdtemp(join(tmpdir(), "weibei-agent-contract-"));
try {
  const runtimeRoot = join(temporaryRoot, "AgentResources");
  await cp(agentResourcesRoot, runtimeRoot, { recursive: true });
  const runtimeExtensionPath = join(runtimeRoot, "extension.mjs");
  const runtimeSource = transpiled.outputText.replace(
    /import\s*\{\s*Type\s*\}\s*from\s*["']@earendil-works\/pi-ai["'];?/u,
    "const Type = new Proxy({}, { get: () => (..._args) => ({}) });",
  );
  assert.doesNotMatch(
    runtimeSource,
    /@earendil-works\/pi-ai/u,
    "the runtime harness must replace the schema-only Pi dependency",
  );
  await writeFile(runtimeExtensionPath, runtimeSource, "utf8");

  const contextPath = join(temporaryRoot, "context.json");
  const materialText = "共同依据原文足够长，足以支持三个空间场景的真实来源校验。";
  const catalogItem = {
    id: "material-1",
    title: "测试材料",
    subtitle: "",
    kind: "text",
    role: "material",
    isCurrentMaterial: true,
    isCurrentNote: false,
    linkedItemIDs: [],
    tags: [],
  };
  await writeFile(
    contextPath,
    JSON.stringify({
      schemaVersion: 2,
      requestID: "agent-contract-request",
      contextRevision: "agent-contract-revision",
      answerFormPolicy: "automatic",
      purpose: "chat",
      workflow: "chat",
      language: "zh-Hans",
      question: "比较三个空间场景",
      material: {
        title: "测试材料",
        text: materialText,
        isTruncated: false,
      },
      note: {
        title: "课堂笔记",
        text: "",
        isTruncated: false,
      },
      recentMessages: [],
      course: {
        title: "测试课程",
        catalog: [catalogItem],
        items: [{
          ...catalogItem,
          headings: [],
          searchText: materialText,
          isTruncated: false,
        }],
        relations: [],
        isTruncated: false,
      },
      learning: {
        memoryRevision: 0,
        memories: [],
      },
    }),
    "utf8",
  );
  process.env.WEIBEI_AGENT_CONTEXT_FILE = contextPath;

  const registeredTools = new Map();
  const extensionModule = await import(
    `${pathToFileURL(runtimeExtensionPath).href}?contract=${Date.now()}`
  );
  extensionModule.default({
    registerTool(tool) {
      registeredTools.set(tool.name, tool);
    },
    on() {},
  });
  const contextTool = registeredTools.get("weibei_context");
  const catalogTool = registeredTools.get("weibei_ui_catalog");
  const richAnswerTool = registeredTools.get("weibei_rich_answer");
  assert.ok(contextTool && catalogTool && richAnswerTool);

  await contextTool.execute("context-1", {});
  await catalogTool.execute("catalog-1", {
    learningAction: "explain",
    knowledgeShapes: ["spatialLayers"],
    knowledgeNatures: ["spatialStructure"],
    knowledgeObjects: ["空间点"],
    knowledgeRelations: ["位置关系"],
    knowledgeProcesses: [],
    interactions: ["none"],
    sourceMedium: "text",
    surface: "inline",
    representationNeeds: {
      spatialDimension: "twoDimensional",
      temporalBehavior: "static",
      dataOrigin: "conceptual",
      coordinateFrame: "cartesian",
      computeNeed: "none",
      precisionNeed: "illustrative",
      assetDependency: "none",
    },
    reason: "验证整组资源由宿主逐场景收敛",
  });

  const longText = "空".repeat(100_000);
  const layers = Array.from({ length: 276 }, (_, index) => ({
    id: `layer-${index}`,
    title: `层 ${index}`,
    visibleDefault: true,
    note: `空间说明 ${index} ${"层".repeat(64)}`,
  }));
  const makeScene = (index) => ({
    id: `scene-${index}`,
    title: `空间场景 ${index}`,
    family: "timeAndSpace",
    objects: [],
    relations: [],
    operations: [],
    frames: [],
    evidenceIDs: ["evidence-1"],
    renderPlan: {
      renderer: "weibei.spatial.map",
      specVersion: "weibei.spatial.map.v1",
      spec: {
        title: longText,
        coordinateMode: "schematic",
        coordinateHint: longText,
        layers,
        features: [{
          id: `point-${index}`,
          kind: "point",
          x: 0.5,
          y: 0.5,
          label: longText,
        }],
        caption: longText,
      },
      interactionBindings: [],
      sourceBindings: [{
        id: `source-${index}`,
        evidenceID: "evidence-1",
        target: "spec.features",
        role: "data",
        requiredForFallback: true,
      }],
      artifactRefs: [],
      fallback: {
        mode: "narrativeOnly",
        reason: "空间场景暂不可用",
        text: `场景 ${index} 安全正文`,
        preservesSourceBinding: true,
      },
      qualityBudget: {
        maxNodes: 280,
        maxDataPoints: 8_000,
        maxArtifacts: 0,
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
  });
  const scenes = [1, 2, 3].map(makeScene);
  const planBytes = scenes.map((scene) =>
    Buffer.byteLength(JSON.stringify(scene.renderPlan), "utf8")
  );
  assert.ok(planBytes.every((bytes) => bytes < 1_500_000));
  assert.ok(
    planBytes.reduce((sum, bytes) => sum + bytes, 0) > 1_500_000,
    `fixture must exceed the whole-group logical budget: ${planBytes.join(",")}`,
  );

  const result = await richAnswerTool.execute("rich-1", {
    schemaVersion: 2,
    contextRevision: "agent-contract-revision",
    narrative: [
      "[材料：测试材料] 三个场景共用同一段真实来源。",
      "<!-- weibei-scene:scene-1 -->",
      "<!-- weibei-scene:scene-2 -->",
      "<!-- weibei-scene:scene-3 -->",
    ].join("\n"),
    expressionPlan: {
      action: "explain",
      summary: "按顺序解释三个空间场景",
      knowledgeNatures: ["spatialStructure"],
      knowledgeObjects: ["空间点"],
      knowledgeRelations: ["位置关系"],
      knowledgeProcesses: [],
      visualPrimitives: ["point"],
      visualRationale: ["空间位置需要可见点"],
      families: ["timeAndSpace"],
      preferredSurface: "inline",
      directManipulation: false,
    },
    scenes,
    evidenceLedger: [{
      id: "evidence-1",
      sourceLabel: "[材料：测试材料]",
      excerpt: "共同依据原文足够长",
      assetIDs: [],
      tags: [],
      isTruncated: false,
    }],
    fallback: {
      text: "[材料：测试材料] 三个场景的安全正文。",
      reason: "整组视觉不可用",
    },
  });
  assert.equal(result.details.kind, "rich_answer");
  assert.equal(result.details.envelope.scenes.length, 3);
  assert.match(result.content[0].text, /宿主会继续按整组预算逐场景收敛/u);
} finally {
  await rm(temporaryRoot, { recursive: true, force: true });
}

process.stdout.write("rich-answer Agent extension contract passed\n");
