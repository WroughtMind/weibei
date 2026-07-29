import { describe, expect, it } from "vitest";

import {
  activePreviewHeadingIndex,
  nextPreviewContentHeight,
  normalizedPreviewHeadingIndex,
} from "../../Sources/WeiBei/WebEditor/src/features/preview.js";

describe("WebEditor compact preview state", () => {
  it("normalizes measured height and suppresses duplicate bridge reports", () => {
    expect(nextPreviewContentHeight([], 0)).toBe(1);
    expect(nextPreviewContentHeight([87.1, 120.2, 96], 0)).toBe(121);
    expect(nextPreviewContentHeight([120.2], 121)).toBeNull();
    expect(nextPreviewContentHeight([Number.NaN, 42], 0)).toBe(42);
  });

  it("tracks the final heading at or above the reading line", () => {
    expect(activePreviewHeadingIndex([], 1_000)).toBeNull();
    expect(activePreviewHeadingIndex([400, 620], 1_000)).toBe(0);
    expect(activePreviewHeadingIndex([-20, 120, 321], 1_000)).toBe(1);
    expect(activePreviewHeadingIndex([-20, 120, 319], 1_000)).toBe(2);
  });

  it("accepts only heading indexes that can resolve in the current document", () => {
    expect(normalizedPreviewHeadingIndex(-3, 2)).toBe(0);
    expect(normalizedPreviewHeadingIndex(1.9, 2)).toBe(1);
    expect(normalizedPreviewHeadingIndex("1", 2)).toBe(1);
    expect(normalizedPreviewHeadingIndex(2, 2)).toBeNull();
    expect(normalizedPreviewHeadingIndex("heading", 2)).toBeNull();
    expect(normalizedPreviewHeadingIndex(0, 0)).toBeNull();
  });
});
