import { describe, expect, it } from "vitest";
import { validateExtendedKnowledgeComponentExamples } from "../src/generative/extended-knowledge-components.validation";
import {
  runGeometry2DSelfChecks,
  runGeometry2DSurfaceSelfCheck,
} from "../src/generative/renderers/geometry-2d.self-check";
import { runImageOverlaySelfChecks } from "../src/generative/renderers/image-overlay.self-check";
import { runScene3DSelfChecks } from "../src/generative/renderers/scene-3d.self-check";
import {
  runSpatialMapViewportSelfCheck,
  runSpatialMapVisibilitySelfCheck,
} from "../src/generative/renderers/spatial-map.self-check";

describe("rich-answer renderer self-checks", () => {
  it("accepts and rejects the expected geometry plans", () => {
    expect(runGeometry2DSelfChecks().every((result) => result.passed)).toBe(
      true,
    );
    expect(runGeometry2DSurfaceSelfCheck().passed).toBe(true);
  });

  it("keeps image overlay behavior within its bounded layout contract", () => {
    expect(runImageOverlaySelfChecks().ok).toBe(true);
  });

  it("accepts and rejects the expected 3D scene plans", () => {
    expect(runScene3DSelfChecks().every((result) => result.ok)).toBe(true);
  });

  it("preserves spatial-map coordinates and visibility rules", () => {
    expect(runSpatialMapViewportSelfCheck().ok).toBe(true);
    expect(runSpatialMapVisibilitySelfCheck().ok).toBe(true);
  });

  it("parses every extended knowledge component example completely", () => {
    const results = validateExtendedKnowledgeComponentExamples();
    expect(results).not.toHaveLength(0);
    expect(
      results.every(
        (result) =>
          result.hasRoot &&
          !result.incomplete &&
          result.unresolved.length === 0 &&
          result.errors.length === 0,
      ),
    ).toBe(true);
  });
});
