import { describe, expect, it } from "vitest";

import {
  canonicalJSON,
  safeArtifactIdentifier,
} from "../../../Sources/WeiBeiCore/AgentResources/domains/canonical-json";
import {
  courseHeading,
  courseJumpReference,
  searchCourse,
} from "../../../Sources/WeiBeiCore/AgentResources/domains/course-navigation";
import { validateRichAnswerNarrativeFlow } from "../../../Sources/WeiBeiCore/AgentResources/domains/rich-answer-narrative";

describe("Pi extension domain modules", () => {
  it("canonicalizes controlled artifact JSON deterministically", () => {
    expect(canonicalJSON({ z: 2, a: [true, { b: "值" }] })).toBe('{"a":[true,{"b":"值"}],"z":2}');
    expect(() => canonicalJSON({ invalid: Number.NaN })).toThrow("非有限");
    expect(safeArtifactIdentifier("series-1.json")).toBe(true);
    expect(safeArtifactIdentifier("../series.json")).toBe(false);
  });

  it("ranks course evidence and keeps duplicate-title jumps stable", () => {
    const items = [
      {
        id: "first",
        role: "material",
        title: "力学",
        subtitle: "入门",
        headings: ["速度"],
        tags: ["物理"],
        searchText: "速度与时间",
        isCurrentMaterial: false,
        isCurrentNote: false,
      },
      {
        id: "second",
        role: "note",
        title: "力学",
        subtitle: "牛顿",
        headings: ["加速度"],
        tags: ["运动"],
        searchText: "加速度 加速度",
        isCurrentMaterial: false,
        isCurrentNote: true,
      },
    ];
    expect(searchCourse({ items }, "加速度", 1)[0]?.id).toBe("second");
    expect(courseJumpReference({ catalog: items }, items[1], "[html-section-force][html-heading-1] 牛顿第二定律"))
      .toBe("来源：力学，条目：2，章节标识：html-section-force，章节序号：2，章节：牛顿第二定律");
    expect(courseHeading("第 3 页（OCR）")).toEqual({ title: "第 3 页（OCR）" });
  });

  it("requires v2 narrative scene markers to be valid and non-duplicated", () => {
    expect(validateRichAnswerNarrativeFlow(
      "先解释。\n<!-- weibei-scene:force -->\n再总结。",
      ["force"],
    )).toBe("先解释。\n再总结。");
    expect(() => validateRichAnswerNarrativeFlow(
      "正文\n<!-- weibei-scene:force -->\n<!-- weibei-scene:force -->",
      ["force"],
    )).toThrow("重复插入");
    expect(() => validateRichAnswerNarrativeFlow(
      "<!-- weibei-scene:unknown -->",
      ["force"],
    )).toThrow("不存在");
  });
});
