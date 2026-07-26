/**
 * Validates inline scene markers and returns the independently readable prose.
 */
export function validateRichAnswerNarrativeFlow(
  narrative: string,
  sceneIDs: readonly string[],
): string {
  const knownSceneIDs = new Set(sceneIDs);
  const referencedSceneIDs = new Set<string>();
  const narrativeLines: string[] = [];
  const markerPattern = /^<!-- weibei-scene:([A-Za-z][A-Za-z0-9_-]{0,119}) -->$/u;

  for (const [index, line] of narrative.split(/\r?\n/gu).entries()) {
    const trimmed = line.trim();
    if (!trimmed.includes("weibei-scene:")) {
      narrativeLines.push(line);
      continue;
    }
    const match = trimmed.match(markerPattern);
    if (!match) {
      throw new Error(
        `富回答 narrative 第 ${index + 1} 行的场景标记格式无效；必须独占一行写成 <!-- weibei-scene:场景ID -->`,
      );
    }
    const sceneID = match[1];
    if (!knownSceneIDs.has(sceneID)) {
      throw new Error(`富回答 narrative 引用了不存在的场景 ${sceneID}`);
    }
    if (referencedSceneIDs.has(sceneID)) {
      throw new Error(`富回答 narrative 重复插入了场景 ${sceneID}`);
    }
    referencedSceneIDs.add(sceneID);
  }

  const plainNarrative = narrativeLines.join("\n").trim();
  if (!plainNarrative) {
    throw new Error("富回答 narrative 不能只有场景标记，必须保留可独立阅读的正文");
  }
  return plainNarrative;
}
