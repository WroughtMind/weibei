import { describe, expect, it } from "vitest";

import {
  evidenceBooleanText,
  evidenceNumber,
  evidenceText,
  firstEvidenceValue,
  indexDocumentSchema,
  parseEvidenceJson,
  recordDocumentSchema,
} from "../../Prototypes/RichAnswerEvidenceViewer/evidence-contract.js";
import { parseEvidencePackageArgs } from "../../Prototypes/RichAnswerEvidenceViewer/generate-evidence-package.js";
import { parseOfflineEvidencePackageArgs } from "../../Prototypes/RichAnswerEvidenceViewer/generate-offline-evidence-package.js";

describe("evidence compatibility contract", () => {
  it("keeps legacy aliases at the input boundary", () => {
    const index = parseEvidenceJson(
      JSON.stringify({
        records: [
          {
            case_id: "legacy-case",
            record_file: "cases/legacy/record.json",
            roundIndex: 2,
          },
        ],
      }),
      "index.json",
      indexDocumentSchema,
    );

    expect(index.records?.[0]).toMatchObject({
      case_id: "legacy-case",
      record_file: "cases/legacy/record.json",
      roundIndex: 2,
    });
  });

  it("validates canonical nested evidence once", () => {
    const record = recordDocumentSchema.parse({
      runID: "run-1",
      caseSnapshot: { id: "case-1", question: "问题" },
      shapeDecision: { actualShape: "rich" },
      expressionPlan: {
        t1Programs: [{ sceneID: "scene-1", capabilities: ["zoom"] }],
      },
    });

    expect(record.caseSnapshot?.id).toBe("case-1");
    expect(record.expressionPlan?.t1Programs?.[0]?.sceneID).toBe("scene-1");
  });

  it("normalizes display values through shared helpers", () => {
    expect(evidenceText("  内容  ")).toBe("内容");
    expect(evidenceNumber("12.5")).toBe(12.5);
    expect(evidenceBooleanText(false)).toBe("否");
    expect(firstEvidenceValue("", "有效")).toBe("有效");
    expect(firstEvidenceValue<unknown[]>([], ["有效"])).toEqual(["有效"]);
    expect(firstEvidenceValue<object>({}, { value: "有效" })).toEqual({
      value: "有效",
    });
  });
});

describe("evidence package CLI parsing", () => {
  it("parses validated package options and the output alias", () => {
    expect(
      parseEvidencePackageArgs([
        "--run-id",
        "run-1",
        "--out",
        "result",
        "--asset-mode",
        "hardlink",
        "--force",
      ]),
    ).toMatchObject({
      runId: "run-1",
      output: "result",
      assetMode: "hardlink",
      force: true,
    });
  });

  it("rejects a missing option value at the CLI boundary", () => {
    expect(() => parseEvidencePackageArgs(["--run-id"])).toThrow();
    expect(() =>
      parseOfflineEvidencePackageArgs(["--output"]),
    ).toThrow();
  });

  it("rejects unsupported options and asset modes", () => {
    expect(() => parseOfflineEvidencePackageArgs(["--unknown"])).toThrow();
    expect(() =>
      parseEvidencePackageArgs(["--asset-mode", "reflink"]),
    ).toThrow("不支持的 --asset-mode");
  });
});
