import { describe, expect, it } from "vitest";

import {
  runGeometry2DSelfChecks,
  runGeometry2DSurfaceSelfCheck,
} from "./geometry-2d.domain";
import { runImageOverlaySelfChecks } from "./image-overlay.domain";
import { runScene3DSelfChecks } from "./scene-3d.domain";
import {
  createSelfCheckPlan,
  runSpatialMapViewportSelfCheck,
  runSpatialMapVisibilitySelfCheck,
  spatialMapSelfCheckCases,
} from "./spatial-map.domain";

describe("registered renderer domain contracts", () => {
  it("accepts and rejects the geometry fixtures as declared", () => {
    expect(runGeometry2DSelfChecks().filter((item) => !item.passed)).toEqual([]);
    expect(runGeometry2DSurfaceSelfCheck().passed).toBe(true);
  });

  it("keeps image overlay geometry, evidence, and validation deterministic", () => {
    expect(runImageOverlaySelfChecks()).toMatchObject({ ok: true });
  });

  it("accepts and rejects the 3D fixtures as declared", () => {
    expect(runScene3DSelfChecks().filter((item) => !item.ok)).toEqual([]);
  });

  it("keeps spatial map transforms and visibility deterministic", () => {
    expect(runSpatialMapViewportSelfCheck().ok).toBe(true);
    expect(runSpatialMapVisibilitySelfCheck().ok).toBe(true);
  });

  it("accepts and rejects the spatial map fixtures as declared", () => {
    for (const fixture of spatialMapSelfCheckCases) {
      const result = createSelfCheckPlan(fixture);
      expect(result.ok, fixture.name).toBe(fixture.expectOk);
      if (!fixture.expectOk && !result.ok && "issueCode" in fixture) {
        expect(result.issue.code, fixture.name).toBe(fixture.issueCode);
      }
    }
  });
});
