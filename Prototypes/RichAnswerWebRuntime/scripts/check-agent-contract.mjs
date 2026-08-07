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
    kind: "image",
    role: "material",
    isCurrentMaterial: true,
    isCurrentNote: false,
    linkedItemIDs: [],
    tags: [],
  };
  const otherAssetItem = {
    ...catalogItem,
    id: "material-2",
    title: "另一份图像材料",
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
      selection: {
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
        catalog: [catalogItem, otherAssetItem],
        items: [{
          ...catalogItem,
          headings: [],
          searchText: materialText,
          isTruncated: false,
        }, {
          ...otherAssetItem,
          headings: [],
          searchText: "另一份图像材料的独立说明。",
          isTruncated: false,
        }],
        relations: [],
        isTruncated: false,
      },
      project: {
        kind: "global",
        chatID: "agent-contract-chat",
        items: [],
        isTruncated: false,
      },
      focus: {
        chatID: "agent-contract-chat",
        materialItemID: "material-1",
        materialTitle: "测试材料",
        selectionText: materialText,
        actionSource: "selection",
      },
      learning: {
        memoryRevision: 0,
        memories: [],
      },
      courseProfile: {
        revision: 0,
        overview: "",
        entries: [],
      },
    }),
    "utf8",
  );
  process.env.WEIBEI_AGENT_CONTEXT_FILE = contextPath;

  const registeredTools = new Map();
  const registeredHandlers = new Map();
  const extensionModule = await import(
    `${pathToFileURL(runtimeExtensionPath).href}?contract=${Date.now()}`
  );
  extensionModule.default({
    registerTool(tool) {
      registeredTools.set(tool.name, tool);
    },
    on(event, handler) {
      registeredHandlers.set(event, handler);
    },
  });
  const catalogTool = registeredTools.get("weibei_ui_catalog");
  const richAnswerTool = registeredTools.get("weibei_rich_answer");
  const beforeAgentStart = registeredHandlers.get("before_agent_start");
  assert.ok(beforeAgentStart && catalogTool && richAnswerTool);

  await beforeAgentStart({ systemPrompt: "测试系统提示" });
  const catalogRequest = {
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
  };
  await catalogTool.execute("catalog-1", catalogRequest);

  const formulaCatalog = await catalogTool.execute("catalog-formula-conceptual", {
    ...catalogRequest,
    knowledgeShapes: ["formula"],
    knowledgeNatures: ["quantityRelation"],
    knowledgeObjects: ["公式曲线"],
    knowledgeRelations: ["变量关系"],
    representationNeeds: {
      ...catalogRequest.representationNeeds,
      temporalBehavior: "stateChange",
      dataOrigin: "conceptual",
      computeNeed: "lightDeterministic",
      precisionNeed: "quantitative",
    },
  });
  assert.ok(
    formulaCatalog.details.allowedRenderers.some(
      (renderer) => renderer.id === "weibei.math.function",
    ),
    "a source-free conceptual formula still receives the function renderer",
  );

  const sourceFreeRequest = {
    schemaVersion: 2,
    contextRevision: "agent-contract-revision",
    narrative: [
      "这是按给定坐标生成的概念示意，不是课程原文。",
      "<!-- weibei-scene:source-free-scene -->",
    ].join("\n"),
    expressionPlan: {
      action: "explain",
      summary: "用示意点解释相对位置",
      knowledgeNatures: ["spatialStructure"],
      knowledgeObjects: ["示意点"],
      knowledgeRelations: ["相对位置"],
      knowledgeProcesses: [],
      visualPrimitives: ["point"],
      visualRationale: ["空间位置需要可见点"],
      families: ["timeAndSpace"],
      preferredSurface: "inline",
      directManipulation: false,
    },
    scenes: [{
      id: "source-free-scene",
      title: "相对位置示意",
      family: "timeAndSpace",
      evidenceIDs: [],
      renderPlan: {
        renderer: "weibei.spatial.map",
        specVersion: "weibei.spatial.map.v1",
        spec: {
          title: "相对位置示意",
          coordinateMode: "schematic",
          features: [{ id: "origin", kind: "point", x: 0.5, y: 0.5, label: "示意点" }],
        },
        interactionBindings: [],
        sourceBindings: [],
        artifactRefs: [],
        fallback: {
          mode: "narrativeOnly",
          reason: "示意图暂不可用",
          text: "示意点位于画面中央。",
          preservesSourceBinding: false,
        },
        qualityBudget: {
          maxNodes: 16,
          maxDataPoints: 8,
          maxArtifacts: 0,
          maxBytes: 32_000,
          maxWidth: 640,
          maxHeight: 320,
          maxAnimationFPS: 0,
          maxInteractionLatencyMS: 120,
          allowAnimation: false,
          allowWebGL: false,
          allowNetwork: false,
        },
      },
    }],
    evidenceLedger: [],
    fallback: {
      text: "示意点位于画面中央。",
      reason: "解释性示意不可用",
    },
  };

  await catalogTool.execute("catalog-user-provided", {
    ...catalogRequest,
    representationNeeds: {
      ...catalogRequest.representationNeeds,
      dataOrigin: "userProvided",
    },
  });
  const normalizedDisclosureResult = await richAnswerTool.execute(
    "rich-normalized-disclosure",
    {
      ...sourceFreeRequest,
      narrative: [
        "这不是用户本轮给定数据，而是模型自己的说明。",
        "<!-- weibei-scene:source-free-scene -->",
      ].join("\n"),
    },
  );
  assert.match(
    normalizedDisclosureResult.details.envelope.narrative,
    /^用户本轮给定数据。/u,
    "the host adds the canonical data-origin disclosure instead of rejecting honest wording",
  );

  await catalogTool.execute("catalog-conceptual", catalogRequest);
  const sourceFreeResult = await richAnswerTool.execute("rich-source-free", sourceFreeRequest);
  assert.equal(sourceFreeResult.details.kind, "rich_answer");
  assert.deepEqual(sourceFreeResult.details.envelope.evidenceLedger, []);

  await catalogTool.execute("catalog-source-required", {
    ...catalogRequest,
    representationNeeds: {
      ...catalogRequest.representationNeeds,
      dataOrigin: "sourceObserved",
    },
  });
  await assert.rejects(
    () => richAnswerTool.execute("rich-source-required", sourceFreeRequest),
    /不能省略真实来源/u,
    "source-observed content cannot bypass evidence validation with empty arrays",
  );

  await beforeAgentStart({ systemPrompt: "测试系统提示" });
  await catalogTool.execute("catalog-geographic-source-required", {
    ...catalogRequest,
    representationNeeds: {
      ...catalogRequest.representationNeeds,
      coordinateFrame: "geographic",
    },
  });
  await assert.rejects(
    () => richAnswerTool.execute("rich-geographic-source-required", sourceFreeRequest),
    /不能省略真实来源/u,
    "real geographic coordinates cannot enter the source-free path",
  );

  await beforeAgentStart({ systemPrompt: "测试系统提示" });
  await catalogTool.execute("catalog-payload-geographic", catalogRequest);
  await assert.rejects(
    () => richAnswerTool.execute("rich-payload-geographic", {
      ...sourceFreeRequest,
      scenes: [{
        ...sourceFreeRequest.scenes[0],
        renderPlan: {
          ...sourceFreeRequest.scenes[0].renderPlan,
          spec: {
            ...sourceFreeRequest.scenes[0].renderPlan.spec,
            coordinateMode: "geographic",
            crs: "WGS84",
          },
        },
      }],
    }),
    /真实地理坐标不能通过 cartesian 目录声明进入无来源路径/u,
    "a cartesian source-free catalog cannot smuggle in a geographic map payload",
  );

  await beforeAgentStart({ systemPrompt: "测试系统提示" });
  await catalogTool.execute("catalog-source-free-asset", catalogRequest);
  await assert.rejects(
    () => richAnswerTool.execute("rich-unreturned-renderer", {
      ...sourceFreeRequest,
      expressionPlan: {
        ...sourceFreeRequest.expressionPlan,
        families: ["imageAndOverlay"],
        visualPrimitives: ["image"],
      },
      scenes: [{
        ...sourceFreeRequest.scenes[0],
        family: "imageAndOverlay",
        renderPlan: {
          ...sourceFreeRequest.scenes[0].renderPlan,
          renderer: "weibei.image.overlay",
          specVersion: "weibei.image-overlay.v1",
          spec: {
            title: "无来源图像叠层",
            image: { kind: "dataUrl", source: "data:image/png;base64,iVBORw0KGgo=" },
            layers: [],
            annotations: [],
          },
          qualityBudget: {
            ...sourceFreeRequest.scenes[0].renderPlan.qualityBudget,
            maxArtifacts: 1,
            maxBytes: 1_500_000,
          },
        },
      }],
    }),
    (error) => {
      assert.match(String(error), /不是本轮 weibei_ui_catalog 返回的能力/u);
      assert.match(String(error), /spec\.image\.kind 必须是 assetRef/u);
      return true;
    },
    "a source-free catalog cannot submit an asset-backed renderer from the global index",
  );
  await assert.rejects(
    () => richAnswerTool.execute("rich-fake-source-label", {
      ...sourceFreeRequest,
      narrative: [
        "[材料：不存在] 这是概念示意。",
        "<!-- weibei-scene:source-free-scene -->",
      ].join("\n"),
    }),
    /没有对应 evidenceLedger 的来源标签/u,
    "source-free text cannot fabricate a material label",
  );
  await assert.rejects(
    () => richAnswerTool.execute("rich-source-free-asset", {
      ...sourceFreeRequest,
      narrative: [
        "[选区：测试材料] 这是带来源上下文的概念示意。",
        "<!-- weibei-scene:source-free-scene -->",
      ].join("\n"),
      scenes: [{
        ...sourceFreeRequest.scenes[0],
        renderPlan: {
          ...sourceFreeRequest.scenes[0].renderPlan,
          spec: {
            ...sourceFreeRequest.scenes[0].renderPlan.spec,
            mapAsset: { kind: "assetRef", source: "material-1" },
          },
        },
      }],
      evidenceLedger: [{
        id: "evidence-asset",
        sourceLabel: "[选区：测试材料]",
        excerpt: "共同依据原文足够长",
        assetIDs: [],
        tags: [],
        isTruncated: false,
      }],
    }),
    /无来源富回答不能引用当前材料资产/u,
    "adding an evidence ledger cannot bypass a source-free catalog declaration",
  );

  await beforeAgentStart({ systemPrompt: "测试系统提示" });
  await catalogTool.execute("catalog-source-bound", {
    ...catalogRequest,
    representationNeeds: {
      ...catalogRequest.representationNeeds,
      dataOrigin: "sourceObserved",
    },
  });
  await assert.rejects(
    () => richAnswerTool.execute("rich-cross-source-asset", {
      ...sourceFreeRequest,
      narrative: [
        "[选区：测试材料] 这是材料中的空间点。",
        "<!-- weibei-scene:source-free-scene -->",
      ].join("\n"),
      scenes: [{
        ...sourceFreeRequest.scenes[0],
        evidenceIDs: ["evidence-asset"],
        renderPlan: {
          ...sourceFreeRequest.scenes[0].renderPlan,
          sourceBindings: [{
            id: "source-asset",
            evidenceID: "evidence-asset",
            target: "spec.features",
            role: "data",
            requiredForFallback: true,
          }],
          fallback: {
            ...sourceFreeRequest.scenes[0].renderPlan.fallback,
            preservesSourceBinding: true,
          },
        },
      }],
      evidenceLedger: [{
        id: "evidence-asset",
        sourceLabel: "[选区：测试材料]",
        excerpt: "共同依据原文足够长",
        assetIDs: ["material-2"],
        tags: [],
        isTruncated: false,
      }],
    }),
    /不属于同一来源的材料资产/u,
    "evidence from material A cannot bind material B's globally allowed image",
  );

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
      "[选区：测试材料] 三个场景共用同一段真实来源。",
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
      sourceLabel: "[选区：测试材料]",
      excerpt: "共同依据原文足够长",
      assetIDs: [],
      tags: [],
      isTruncated: false,
    }],
    fallback: {
      text: "[选区：测试材料] 三个场景的安全正文。",
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
