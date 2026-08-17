import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import { fileURLToPath } from "node:url";
import { renderToStaticMarkup } from "react-dom/server";
import { createServer } from "vite";

const root = fileURLToPath(new URL("..", import.meta.url));
const server = await createServer({
  root,
  appType: "custom",
  logLevel: "silent",
  server: { middlewareMode: true },
});

const sourceBinding = {
  id: "source",
  evidenceID: "evidence",
  target: "spec",
  role: "basis",
};

function renderPlan(renderer: any, specVersion: any, spec: any, qualityBudget: Record<string, number> = {}) {
  return {
    renderer,
    specVersion,
    spec,
    interactionBindings: [],
    sourceBindings: [sourceBinding],
    artifactRefs: [],
    fallback: {
      mode: "narrativeOnly",
      reason: "视觉不可用",
      text: "保留普通正文。",
      preservesSourceBinding: true,
    },
    qualityBudget: {
      maxNodes: 24,
      maxDataPoints: 120,
      maxArtifacts: 0,
      maxBytes: 12_000,
      maxWidth: 960,
      maxHeight: 640,
      maxAnimationFPS: 30,
      maxInteractionLatencyMS: 120,
      allowAnimation: true,
      allowWebGL: false,
      allowNetwork: false,
      ...qualityBudget,
    },
  };
}

try {
  const {
    RendererRegistry,
    createRendererIssue,
    formalRenderGroupResourceLimits,
    measureRenderPlanResourceUsage,
    parseRenderPlan,
    parseRenderPlans,
  } = await server.ssrLoadModule("/src/generative/renderer-registry.ts");
  const {
    admitRenderGroupItems,
    mergeIndexedRenderGroupItems,
    runtimeFailureIsFatal,
  } = await server.ssrLoadModule("/src/generative/render-group.ts");
  const {
    parseHostPrograms,
  } = await server.ssrLoadModule("/src/generative/protocol.ts");

  for (const scope of ["program-entry", "renderer-entry", "entry-error-boundary"]) {
    assert.equal(
      runtimeFailureIsFatal(scope),
      false,
      `${scope} keeps its safe item fallback visible`,
    );
  }
  for (const scope of ["runtime-startup", "navigation", "host-transport"]) {
    assert.equal(
      runtimeFailureIsFatal(scope),
      true,
      `${scope} is reserved for a whole-layer failure`,
    );
  }

  const context = {
    program: {
      version: "weibei.openui.v1",
      id: "failure-contract",
      title: "失败契约",
      question: "失败契约",
      mode: "declarative",
      source: "root = TextBlock(\"说明\", \"正文仍由宿主显示\", \"body\")",
      capabilities: ["failure-contract"],
      evidenceBindings: [],
      budget: { maxHeight: 160, maxNodes: 1, maxSeries: 1, graphics: "dom" },
    },
    showNotice() {},
    postMessage() {},
  };

  const rendererModules = await Promise.all([
    server.ssrLoadModule("/src/generative/renderers/echarts-chart.tsx"),
    server.ssrLoadModule("/src/generative/renderers/math-function.tsx"),
    server.ssrLoadModule("/src/generative/renderers/geometry-2d.tsx"),
    server.ssrLoadModule("/src/generative/renderers/scene-3d.tsx"),
    server.ssrLoadModule("/src/generative/renderers/spatial-map.tsx"),
    server.ssrLoadModule("/src/generative/renderers/image-overlay.tsx"),
  ]);
  const renderers = [
    rendererModules[0].standardEChartsRenderer,
    rendererModules[1].mathFunctionRenderer,
    rendererModules[2].geometry2DRenderer,
    rendererModules[3].scene3DRenderer,
    rendererModules[4].spatialMapRenderer,
    rendererModules[5].imageOverlayRenderer,
  ];
  const registry = renderers.reduce(
    (candidate, renderer) => candidate.register(renderer),
    new RendererRegistry(),
  );

  const tinyImage = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=";
  const canonicalPlans = [
    renderPlan(
      "weibei.echarts.chart",
      "weibei.chart.v1",
      {
        chartKind: "line",
        title: "趋势",
        series: [{ name: "趋势", values: [1, 2] }],
        xLabels: ["一", "二"],
      },
    ),
    renderPlan(
      "weibei.math.function",
      "weibei.math-function.v1",
      {
        title: "函数",
        variable: "x",
        domain: { minimum: -1, maximum: 1 },
        expression: {
          rootNodeID: "x",
          nodes: [{ id: "x", kind: "variable" }],
        },
      },
    ),
    renderPlan(
      "weibei.geometry.2d",
      "weibei.geometry-2d.v1",
      {
        title: "二维几何",
        coordinateSpace: { xMin: 0, xMax: 1, yMin: 0, yMax: 1 },
        points: [{ id: "A", label: "A", x: 0, y: 0 }],
      },
      { maxHeight: 720 },
    ),
    renderPlan(
      "weibei.scene-3d",
      "weibei.scene-3d.v1",
      {
        title: "空间结构",
        camera: { yaw: 35, pitch: 20, distance: 4, lookAt: [0, 0, 0], fov: 58 },
        objects: [{ id: "origin", kind: "point", position: [0, 0, 0], label: "原点" }],
      },
      { maxHeight: 720, maxInteractionLatencyMS: 160 },
    ),
    renderPlan(
      "weibei.spatial.map",
      "weibei.spatial.map.v1",
      {
        title: "空间图层",
        coordinateMode: "schematic",
        features: [{ id: "origin", kind: "point", x: 0.5, y: 0.5, label: "原点" }],
      },
      { maxArtifacts: 2, maxBytes: 1_500_000, maxHeight: 720, maxInteractionLatencyMS: 140 },
    ),
    renderPlan(
      "weibei.image.overlay",
      "weibei.image-overlay.v1",
      {
        title: "图像观察",
        image: { kind: "dataUrl", source: tinyImage },
        layers: [],
        annotations: [{ id: "focus", point: { x: 0.5, y: 0.5 }, text: "观察点" }],
      },
      { maxArtifacts: 2, maxBytes: 1_500_000, maxHeight: 720, maxInteractionLatencyMS: 140 },
    ),
  ];

  const expectedRoutes = new Map<string, any>([
    ["weibei.echarts.chart", { version: "weibei.chart.v1", maxNodes: 80, maxDataPoints: 4_000, maxArtifacts: 0, maxBytes: 256_000, maxHeight: 640, maxInteractionLatencyMS: 120 }],
    ["weibei.math.function", { version: "weibei.math-function.v1", maxNodes: 64, maxDataPoints: 1_600, maxArtifacts: 0, maxBytes: 256_000, maxHeight: 640, maxInteractionLatencyMS: 120 }],
    ["weibei.geometry.2d", { version: "weibei.geometry-2d.v1", maxNodes: 260, maxDataPoints: 1_200, maxArtifacts: 0, maxBytes: 256_000, maxHeight: 720, maxInteractionLatencyMS: 120 }],
    ["weibei.scene-3d", { version: "weibei.scene-3d.v1", maxNodes: 24, maxDataPoints: 3_200, maxArtifacts: 0, maxBytes: 256_000, maxHeight: 720, maxInteractionLatencyMS: 160 }],
    ["weibei.spatial.map", { version: "weibei.spatial.map.v1", maxNodes: 280, maxDataPoints: 8_000, maxArtifacts: 2, maxBytes: 1_500_000, maxHeight: 720, maxInteractionLatencyMS: 140 }],
    ["weibei.image.overlay", { version: "weibei.image-overlay.v1", maxNodes: 180, maxDataPoints: 1_200, maxArtifacts: 2, maxBytes: 1_500_000, maxHeight: 720, maxInteractionLatencyMS: 140 }],
  ]);
  assert.deepEqual(
    new Set(renderers.map((renderer) => renderer.id)),
    new Set(expectedRoutes.keys()),
    "Web runtime must register exactly the six canonical render-plan routes",
  );
  for (const renderer of renderers) {
    const expected = expectedRoutes.get(renderer.id)!;
    assert.deepEqual(renderer.capabilities.specVersions, [expected.version]);
    for (const field of ["maxNodes", "maxDataPoints", "maxArtifacts", "maxBytes", "maxHeight", "maxInteractionLatencyMS"]) {
      assert.equal(renderer.capabilities[field], expected[field], `${renderer.id} ${field}`);
    }
    assert.deepEqual(
      renderer.capabilities.fallback,
      ["narrativeOnly"],
      `${renderer.id} advertises only the implemented fallback`,
    );
  }
  for (const plan of canonicalPlans) {
    const parsed = parseRenderPlan(plan);
    assert.equal(parsed.success, true, `${plan.renderer} canonical plan parses`);
    const compiled = registry.compile(parsed.data, context);
    assert.equal(
      compiled.ok,
      true,
      `${plan.renderer} canonical plan really compiles: ${compiled.ok ? "" : compiled.issue.message}`,
    );
  }

  const mixedPlans = parseRenderPlans([
    canonicalPlans[0],
    { renderer: "broken" },
    canonicalPlans[1],
  ]);
  assert.equal(mixedPlans.success, true);
  assert.equal(mixedPlans.data.length, 2);
  assert.deepEqual(mixedPlans.indices, [0, 2]);
  assert.equal(mixedPlans.issues.length, 1);

  const mixedPrograms = parseHostPrograms([
    context.program,
    { version: "broken" },
  ]);
  assert.equal(mixedPrograms.success, true);
  assert.equal(mixedPrograms.data.length, 1);
  assert.equal(mixedPrograms.issues.length, 1);

  const legacyFallback = parseRenderPlan({
    ...canonicalPlans[0],
    fallback: {
      ...canonicalPlans[0].fallback,
      mode: "artifactPreview",
      artifactID: "old-preview",
    },
  });
  assert.equal(legacyFallback.success, true, "artifactPreview remains decodable");
  assert.equal(legacyFallback.data.fallback.mode, "narrativeOnly");
  assert.equal(legacyFallback.data.fallback.artifactID, undefined);

  const fallbackHTMLByRenderer = new Map();
  for (const plan of canonicalPlans) {
    const brokenPlan = { ...plan, spec: {} };
    const brokenCompile = registry.compile(brokenPlan, context);
    assert.equal(brokenCompile.ok, false, `${plan.renderer} invalid spec really fails compilation`);
    const fallback = registry.fallback(brokenPlan, brokenCompile.issue, context);
    const fallbackHTML = renderToStaticMarkup(fallback);
    const renderer = renderers.find((candidate) => candidate.id === plan.renderer);
    assert.ok(renderer, `${plan.renderer} renderer exists`);
    const rendererFallbackHTML = renderToStaticMarkup(
      renderer.fallback(brokenPlan, brokenCompile.issue, context),
    );
    fallbackHTMLByRenderer.set(plan.renderer, rendererFallbackHTML);
    assert.match(fallbackHTML, /data-weibei-fallback-mode="narrativeOnly"/);
    assert.match(fallbackHTML, /视觉不可用/);
    assert.match(fallbackHTML, /保留普通正文。/);
    assert.equal(
      fallbackHTML.includes(brokenCompile.issue.message),
      false,
      `${plan.renderer} keeps technical diagnostics out of visible fallback`,
    );
    assert.match(rendererFallbackHTML, /data-weibei-fallback-mode="narrativeOnly"/);
    assert.match(rendererFallbackHTML, /视觉不可用/);
    assert.match(rendererFallbackHTML, /保留普通正文。/);
    assert.equal(
      rendererFallbackHTML.includes(brokenCompile.issue.message),
      false,
      `${plan.renderer} renderer-owned fallback also keeps diagnostics internal`,
    );
  }
  assert.equal(
    fallbackHTMLByRenderer.size,
    6,
    "all six canonical routes execute a real SSR narrative fallback",
  );

  const orderedMixedGroup = mergeIndexedRenderGroupItems(
    [{ index: 0, value: { id: "A", kind: "compiled" } }],
    [{ index: 1, value: { id: "B", kind: "fallback" } }],
    [{ index: 2, value: { id: "C", kind: "compiled" } }],
  );
  assert.deepEqual(
    orderedMixedGroup.map((item: any) => `${item.id}:${item.kind}`),
    ["A:compiled", "B:fallback", "C:compiled"],
    "a bad middle item keeps A, local B fallback, C in original order",
  );
  const allFailedGroup = mergeIndexedRenderGroupItems(
    canonicalPlans.map((plan, index) => ({
      index,
      value: fallbackHTMLByRenderer.get(plan.renderer),
    })),
  );
  assert.equal(allFailedGroup.length, 6);
  assert.equal(
    allFailedGroup.every((html: any) =>
      html.includes('data-weibei-fallback-mode="narrativeOnly"')
        && html.includes("保留普通正文。")),
    true,
    "an all-failed group remains a renderable sequence of safe narrative fallbacks",
  );

  const logicalAdmission = admitRenderGroupItems(
    [
      { index: 0, value: "A", usage: { logicalPlanBytes: 800_000, trustedAssetBytes: [] } },
      { index: 1, value: "B", usage: { logicalPlanBytes: 800_000, trustedAssetBytes: [] } },
      { index: 2, value: "C", usage: { logicalPlanBytes: 100_000, trustedAssetBytes: [] } },
    ],
    formalRenderGroupResourceLimits,
  );
  assert.deepEqual(logicalAdmission.accepted.map((item: any) => item.index), [0, 2]);
  assert.deepEqual(
    logicalAdmission.rejected.map((item: any) => [item.index, item.reason]),
    [[1, "logical_plan_bytes"]],
    "individually legal plans cannot exceed the shared 1.5 MB group envelope",
  );
  assert.equal(logicalAdmission.totals.logicalPlanBytes, 900_000);

  const assetAdmission = admitRenderGroupItems(
    [
      {
        index: 0,
        value: "A",
        usage: { logicalPlanBytes: 1, trustedAssetBytes: [850_000, 850_000] },
      },
      {
        index: 1,
        value: "B",
        usage: { logicalPlanBytes: 1, trustedAssetBytes: [850_000, 850_000] },
      },
      {
        index: 2,
        value: "C",
        usage: { logicalPlanBytes: 1, trustedAssetBytes: [1] },
      },
    ],
    formalRenderGroupResourceLimits,
  );
  assert.deepEqual(assetAdmission.accepted.map((item: any) => item.index), [0, 1]);
  assert.deepEqual(
    assetAdmission.rejected.map((item: any) => [item.index, item.reason]),
    [[2, "trusted_asset_count"]],
  );
  assert.equal(assetAdmission.totals.trustedAssetCount, 4);
  assert.equal(assetAdmission.totals.trustedAssetTotalBytes, 4 * 850_000);
  const declaredAssetUsage = measureRenderPlanResourceUsage(
    {
      ...canonicalPlans[5],
      artifactRefs: [
        { id: "image-a", sizeBytes: 850_000 },
        { id: "image-b", sizeBytes: 850_000 },
      ],
    },
    {
      logicalPlanBytes: Buffer.byteLength(JSON.stringify(canonicalPlans[5])),
      trustedAssetBytes: [],
    },
  );
  assert.equal(declaredAssetUsage.ok, true);
  assert.deepEqual(
    declaredAssetUsage.usage.trustedAssetBytes,
    [],
    "unreferenced artifact metadata is not mislabeled as a trusted local image",
  );
  assert.equal(
    registry.compile(
      canonicalPlans[5],
      {
        ...context,
        budgetContext: {
          logicalPlanBytes: Buffer.byteLength(JSON.stringify(canonicalPlans[5])),
          trustedAssetBytes: [],
        },
      },
    ).ok,
    true,
    "an original inline data URL remains under the ordinary encoded plan budget instead of being mislabeled host-trusted",
  );

  const trustedImageA = `data:image/png;base64,${Buffer.alloc(850_000, 0x89).toString("base64")}`;
  const trustedImageB = `data:image/png;base64,${Buffer.alloc(850_000, 0x42).toString("base64")}`;
  const logicalImagePlan = {
    ...canonicalPlans[5],
    spec: {
      title: "双图比较",
      image: { kind: "assetRef", source: "image-a" },
      layers: [],
      annotations: [{ id: "focus", point: { x: 0.5, y: 0.5 }, text: "观察点" }],
      comparison: {
        enabled: true,
        image: { kind: "assetRef", source: "image-b" },
        ratio: 0.5,
        axis: "vertical",
        leftLabel: "A",
        rightLabel: "B",
      },
    },
  };
  const accountedLogicalImagePlan = {
    ...logicalImagePlan,
    artifactRefs: [
      { id: "image-a", sizeBytes: 850_000 },
      { id: "image-b", sizeBytes: 850_000 },
    ],
  };
  const accountedLogicalUsage = measureRenderPlanResourceUsage(accountedLogicalImagePlan);
  assert.equal(accountedLogicalUsage.ok, true);
  assert.deepEqual(
    accountedLogicalUsage.usage.trustedAssetBytes,
    [850_000, 850_000],
    "each logical assetRef is counted from its uniquely matched artifactRef",
  );
  const hydratedImagePlan = {
    ...logicalImagePlan,
    spec: {
      ...logicalImagePlan.spec,
      image: {
        kind: "dataUrl",
        source: trustedImageA,
        _weibeiHostInjected: true,
      },
      comparison: {
        ...logicalImagePlan.spec.comparison,
        image: {
          kind: "dataUrl",
          source: trustedImageB,
          _weibeiHostInjected: true,
        },
      },
    },
  };
  const singleHostInjectedPlan = {
    ...canonicalPlans[5],
    spec: {
      ...canonicalPlans[5].spec,
      image: {
        kind: "dataUrl",
        source: trustedImageA,
        _weibeiHostInjected: true,
      },
    },
  };
  const missingHostBudget = measureRenderPlanResourceUsage(singleHostInjectedPlan);
  assert.equal(
    missingHostBudget.ok,
    false,
    "host-injected data must fail closed when its authoritative budget context is missing",
  );
  assert.equal(missingHostBudget.issue.code, "unsafe_payload");
  const emptyHostBudget = measureRenderPlanResourceUsage(singleHostInjectedPlan, {
      logicalPlanBytes: Buffer.byteLength(JSON.stringify(canonicalPlans[5])),
      trustedAssetBytes: [],
    });
  assert.equal(
    emptyHostBudget.ok,
    false,
    "host-injected data must fail closed when its authoritative byte list is empty",
  );
  assert.equal(emptyHostBudget.issue.code, "unsafe_payload");
  for (const trustedAssetBytes of [[849_999], [850_000, 850_000]]) {
    const mismatchedHostBudget = measureRenderPlanResourceUsage(singleHostInjectedPlan, {
      logicalPlanBytes: Buffer.byteLength(JSON.stringify(canonicalPlans[5])),
      trustedAssetBytes,
    });
    assert.equal(
      mismatchedHostBudget.ok,
      false,
      "host-injected data must match the authoritative byte list in both count and actual bytes",
    );
    assert.equal(mismatchedHostBudget.issue.code, "unsafe_payload");
  }
  const trustedContext = {
    ...context,
    budgetContext: {
      logicalPlanBytes: Buffer.byteLength(JSON.stringify(logicalImagePlan)),
      trustedAssetBytes: [850_000, 850_000],
    },
  };
  assert.equal(
    registry.compile(hydratedImagePlan, trustedContext).ok,
    true,
    "two trusted 850 KB assets do not fail because base64 inflates hydrated JSON",
  );
  assert.equal(
    registry.compile(hydratedImagePlan, context).ok,
    false,
    "untrusted base64 remains inside the normal plan byte budget",
  );
  assert.equal(
    measureRenderPlanResourceUsage(logicalImagePlan).ok,
    false,
    "an assetRef without a matching artifactRef size cannot bypass the trusted asset budget",
  );

  const mixedLogicalPlan = {
    ...logicalImagePlan,
    spec: {
      ...logicalImagePlan.spec,
      image: { kind: "dataUrl", source: trustedImageA },
    },
  };
  const mixedSourcePlan = {
    ...mixedLogicalPlan,
    spec: {
      ...mixedLogicalPlan.spec,
      comparison: {
        ...mixedLogicalPlan.spec.comparison,
        image: {
          kind: "dataUrl",
          source: trustedImageB,
          _weibeiHostInjected: true,
        },
      },
    },
  };
  assert.equal(
    registry.compile(
      mixedSourcePlan,
      {
        ...context,
        budgetContext: {
          logicalPlanBytes: Buffer.byteLength(JSON.stringify(mixedLogicalPlan)),
          trustedAssetBytes: [850_000],
        },
      },
    ).ok,
    true,
    "an original inline image and one host-injected image are budgeted by their separate trust paths",
  );

  const oversizedSource = `data:image/png;base64,${Buffer.alloc(850_001, 0x21).toString("base64")}`;
  const oversizedPlan = {
    ...hydratedImagePlan,
    spec: {
      ...hydratedImagePlan.spec,
      image: {
        kind: "dataUrl",
        source: oversizedSource,
        _weibeiHostInjected: true,
      },
    },
  };
  const oversizedContext = {
    ...context,
    budgetContext: {
      logicalPlanBytes: trustedContext.budgetContext.logicalPlanBytes,
      trustedAssetBytes: [850_001, 850_000],
    },
  };
  assert.equal(
    registry.compile(oversizedPlan, oversizedContext).ok,
    false,
    "a trusted asset above 850 KB is rejected",
  );

  const issue = createRendererIssue("compile_error", "weibei.unknown", "受控失败");
  const diagnosticFallbackHTML = renderToStaticMarkup(
    registry.fallback(canonicalPlans[0], issue, context),
  );
  assert.match(diagnosticFallbackHTML, /视觉不可用/);
  assert.equal(
    diagnosticFallbackHTML.includes("受控失败"),
    false,
    "unknown-renderer diagnostics remain internal while the safe fallback stays visible",
  );

  process.stdout.write("rich-answer Web fallback contract passed\n");
} finally {
  await server.close();
}
