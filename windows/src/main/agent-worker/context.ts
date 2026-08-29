import type { SearchResult } from "../../shared/contracts";

export function formatAgentContext(options: {
  selection: string | null;
  hits: readonly SearchResult[];
  maximumCharacters?: number;
}): string {
  const maximumCharacters = Math.max(1_000, Math.min(options.maximumCharacters ?? 24_000, 64_000));
  const sections: string[] = [];
  if (options.selection?.trim()) {
    sections.push(`【用户当前选区】\n${options.selection.trim()}`);
  }
  for (const [index, hit] of options.hits.entries()) {
    const excerpt = hit.excerpt.replace(/\s+/gu, " ").trim();
    if (!excerpt) continue;
    sections.push(`【课程资料 ${index + 1}｜${hit.title}｜item:${hit.itemId}】\n${excerpt}`);
  }
  const preface = options.hits.length > 0
    ? "以下包含当前选区（如有）以及从当前课程本地索引检索到的原文片段。只有标为“课程资料”的片段可作为课程证据；引用时保留资料编号，不要捏造未提供的页码或出处。"
    : options.selection?.trim()
      ? "当前课程索引没有返回可验证的原文片段；下面只有用户界面提供的当前选区。不要把选区描述成已经独立核验的课程引用，若使用通用知识请明确说明。"
      : "当前课程索引没有返回可验证的原文片段。不要声称已经阅读或引用了课程材料；若使用通用知识，请明确标为通用知识。";
  const output = [preface, ...sections].join("\n\n");
  return output.length <= maximumCharacters ? output : `${output.slice(0, maximumCharacters - 12)}\n\n[已截断]`;
}
