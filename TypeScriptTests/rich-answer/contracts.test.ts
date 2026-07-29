import { describe, expect, it } from "vitest";

import {
  validateRichAnswerNarrativeFlow,
  validateRichAnswerProgram,
} from "../../Sources/WeiBeiCore/AgentResources/extension.js";
import { generatedPrograms } from "../../Prototypes/RichAnswerWebRuntime/src/generative/programs.js";
import {
  parseHostProgram,
  parseHostPrograms,
} from "../../Prototypes/RichAnswerWebRuntime/src/generative/protocol.js";
import {
  RendererRegistry,
  parseRenderPlan,
} from "../../Prototypes/RichAnswerWebRuntime/src/generative/renderer-registry.js";
import { standardEChartsRenderer } from "../../Prototypes/RichAnswerWebRuntime/src/generative/renderers/echarts-chart.js";
import { geometry2DRenderer } from "../../Prototypes/RichAnswerWebRuntime/src/generative/renderers/geometry-2d.js";
import { imageOverlayRenderer } from "../../Prototypes/RichAnswerWebRuntime/src/generative/renderers/image-overlay.js";
import { mathFunctionRenderer } from "../../Prototypes/RichAnswerWebRuntime/src/generative/renderers/math-function.js";
import { openUIDomRenderer } from "../../Prototypes/RichAnswerWebRuntime/src/generative/renderers/openui-dom.js";
import { scene3DRenderer } from "../../Prototypes/RichAnswerWebRuntime/src/generative/renderers/scene-3d.js";
import { spatialMapRenderer } from "../../Prototypes/RichAnswerWebRuntime/src/generative/renderers/spatial-map.js";

const rendererDeclarations = [
  openUIDomRenderer,
  standardEChartsRenderer,
  mathFunctionRenderer,
  geometry2DRenderer,
  scene3DRenderer,
  spatialMapRenderer,
  imageOverlayRenderer,
] as const;

const expectedRendererVersions = new Map([
  ["weibei.openui.dom", "weibei.openui.v1"],
  ["weibei.echarts.chart", "weibei.chart.v1"],
  ["weibei.math.function", "weibei.math-function.v1"],
  ["weibei.geometry.2d", "weibei.geometry-2d.v1"],
  ["weibei.scene-3d", "weibei.scene-3d.v1"],
  ["weibei.spatial.map", "weibei.spatial.map.v1"],
  ["weibei.image.overlay", "weibei.image-overlay.v1"],
]);

/**
 * Adapts a checked-in Web runtime program to the extension validator's scene
 * envelope without duplicating the program itself.
 */
function extensionSceneForProgram(program: (typeof generatedPrograms)[number]) {
  const graphics: "dom" | "canvas" =
    program.budget.graphics === "dom" ? "dom" : "canvas";
  return {
    id: `scene-${program.id}`,
    family: "quantityAndCoordinates",
    evidenceIDs: program.evidenceBindings.map((binding) => binding.id),
    program: {
      version: program.version,
      source: program.source,
      capabilities: program.capabilities,
      directManipulation: program.capabilities.includes("direct-manipulation"),
      maxHeight: program.budget.maxHeight,
      graphics,
    },
  };
}

describe("Rich Answer narrative and OpenUI program contracts", () => {
  it("keeps scene markers out of the readable narrative", () => {
    expect(
      validateRichAnswerNarrativeFlow(
        [
          "先观察材料中的变化。",
          "<!-- weibei-scene:experiment -->",
          "再解释变化对应的机制。",
        ].join("\n"),
        ["experiment"],
      ),
    ).toBe("先观察材料中的变化。\n再解释变化对应的机制。");
  });

  it("rejects malformed, unknown, duplicate, and marker-only narratives", () => {
    expect(() =>
      validateRichAnswerNarrativeFlow(
        "正文 <!-- weibei-scene:experiment -->",
        ["experiment"],
      ),
    ).toThrow("必须独占一行");
    expect(() =>
      validateRichAnswerNarrativeFlow(
        "正文\n<!-- weibei-scene:missing -->",
        ["experiment"],
      ),
    ).toThrow("不存在的场景");
    expect(() =>
      validateRichAnswerNarrativeFlow(
        "正文\n<!-- weibei-scene:experiment -->\n<!-- weibei-scene:experiment -->",
        ["experiment"],
      ),
    ).toThrow("重复插入");
    expect(() =>
      validateRichAnswerNarrativeFlow(
        "<!-- weibei-scene:experiment -->",
        ["experiment"],
      ),
    ).toThrow("不能只有场景标记");
  });

  it("accepts every checked-in Web runtime program in both validators", () => {
    expect(generatedPrograms.length).toBeGreaterThan(0);
    for (const program of generatedPrograms) {
      expect(parseHostProgram(program).success, program.id).toBe(true);
      expect(
        validateRichAnswerProgram(extensionSceneForProgram(program)),
        program.id,
      ).toBeGreaterThan(0);
    }
    expect(parseHostPrograms(generatedPrograms).success).toBe(false);
    expect(parseHostPrograms(generatedPrograms.slice(0, 6)).success).toBe(true);
  });

  it("rejects unsafe or structurally incomplete programs", () => {
    const program = generatedPrograms[0]!;
    expect(
      parseHostProgram({
        ...program,
        source: "",
      }).success,
    ).toBe(false);
    expect(() =>
      validateRichAnswerProgram({
        ...extensionSceneForProgram(program),
        program: {
          ...extensionSceneForProgram(program).program,
          source: 'root = RichAnswerRoot("<script>", "title", "summary", "flow", [])',
        },
      }),
    ).toThrow("程序包含标记");
  });
});

describe("Rich Answer renderer and message shape contracts", () => {
  it("keeps the complete renderer registry unique and version aligned", () => {
    const registry = new RendererRegistry();
    rendererDeclarations.forEach((renderer) => registry.register(renderer));

    expect(new Set(registry.rendererIDs()).size).toBe(
      expectedRendererVersions.size,
    );
    expect(new Set(registry.rendererIDs())).toEqual(
      new Set(expectedRendererVersions.keys()),
    );

    for (const declaration of registry.listCapabilities()) {
      expect(declaration.renderer).not.toBe("");
      expect(declaration.version).not.toBe("");
      expect(declaration.specVersions).toContain(
        expectedRendererVersions.get(declaration.renderer),
      );
      expect(declaration.maxNodes).toBeGreaterThan(0);
      expect(declaration.maxDataPoints).toBeGreaterThan(0);
      expect(declaration.fallback.length).toBeGreaterThan(0);
    }
  });

  it("requires bounded, source-preserving render-plan envelopes", () => {
    const validPlan = {
      renderer: "weibei.echarts.chart",
      specVersion: "weibei.chart.v1",
      spec: {
        chartKind: "line",
        series: [{ name: "温度", values: [18, 20, 22] }],
      },
      interactionBindings: [],
      sourceBindings: [
        {
          id: "source-1",
          evidenceID: "evidence-1",
          target: "series[0]",
          role: "data",
          requiredForFallback: true,
        },
      ],
      artifactRefs: [],
      fallback: {
        mode: "narrativeOnly",
        reason: "渲染器不可用",
        text: "温度随时间上升。",
        preservesSourceBinding: true,
      },
      qualityBudget: {
        maxNodes: 20,
        maxDataPoints: 100,
        allowAnimation: false,
        allowWebGL: false,
        allowNetwork: false,
      },
    };

    expect(parseRenderPlan(validPlan).success).toBe(true);
    expect(
      parseRenderPlan({
        ...validPlan,
        sourceBindings: [],
      }).success,
    ).toBe(false);
    expect(
      parseRenderPlan({
        ...validPlan,
        qualityBudget: {
          ...validPlan.qualityBudget,
          allowNetwork: true,
          script: "alert(1)",
        },
      }).success,
    ).toBe(false);
  });
});
