import {
  parseMarkdownImageAlt,
  parseObsidianEmbed,
  parseObsidianTarget,
} from "./obsidian.js";

export const calloutTypePattern = "[A-Za-z][A-Za-z0-9_-]*";
export const calloutPrefixPattern = "(?:\\s*>\\s*)*\\s*";
export const selectedTextCalloutControlRegex = new RegExp(
  `(^|\\n)\\s*(?:>\\s*)*\\\\?\\[!(?:${calloutTypePattern})\\][+-]?[ \\t]*`,
  "gi",
);
const htmlBreakPattern = /<br\s*\/?>/gi;

/**
 * Checks whether a Markdown marker is escaped by an odd number of backslashes.
 *
 * @param source - Markdown source
 * @param index - Marker offset
 * @returns Whether the marker is escaped
 */
export const isEscapedMarkdownPosition = (
  source: string,
  index: number,
): boolean => {
  let slashCount = 0;
  for (
    let cursor = index - 1;
    cursor >= 0 && source[cursor] === "\\";
    cursor -= 1
  ) {
    slashCount += 1;
  }
  return slashCount % 2 === 1;
};

/**
 * Finds the next unescaped Markdown marker.
 *
 * @param source - Markdown source
 * @param marker - Marker to find
 * @param from - Search start offset
 * @returns Marker offset, or -1
 */
export const findUnescapedMarkdownMarker = (
  source: string,
  marker: string,
  from: number,
): number => {
  let index = source.indexOf(marker, from);
  while (index >= 0 && isEscapedMarkdownPosition(source, index)) {
    index = source.indexOf(marker, index + marker.length);
  }
  return index;
};

/**
 * Transforms Markdown text outside inline-code spans.
 *
 * @param line - Single Markdown line
 * @param transform - Text transformation
 * @returns Transformed line
 */
export const mapMarkdownOutsideBackticks = (
  line: string,
  transform: (text: string) => string,
): string => {
  const source = String(line || "");
  let result = "";
  let cursor = 0;
  while (cursor < source.length) {
    const tick = findUnescapedMarkdownMarker(source, "`", cursor);
    if (tick < 0) {
      result += transform(source.slice(cursor));
      break;
    }
    result += transform(source.slice(cursor, tick));
    const marker = source.slice(tick).match(/^`+/)?.[0] || "`";
    const close = findUnescapedMarkdownMarker(
      source,
      marker,
      tick + marker.length,
    );
    if (close < 0) {
      result += source.slice(tick);
      break;
    }
    result += source.slice(tick, close + marker.length);
    cursor = close + marker.length;
  }
  return result;
};

/**
 * Restores source syntax escaped by the editor serializer.
 *
 * @param text - Markdown segment outside code
 * @returns Normalized Markdown segment
 */
export const normalizeMarkdownOutputSegment = (text: string): string =>
  String(text || "")
    .replace(/\\\[\\\[/g, "[[")
    .replace(/\\\]\\\]/g, "]]")
    .replace(/\\=\\=([^=\n]+?)\\=\\=/g, "==$1==")
    .replace(/\^\\\[/g, "^[")
    .replace(/(^|\s)\\#(?=[\p{L}\p{N}_/-])/gu, "$1#")
    .replace(/\\\$(?=\d)/g, "$")
    .replace(
      new RegExp(
        `^(\\s*(?:>\\s*)*)\\\\(\\[!(?:${calloutTypePattern})\\])`,
        "gim",
      ),
      "$1$2",
    );

/**
 * Transforms Markdown outside fenced and inline code.
 *
 * @param markdown - Markdown source
 * @param transform - Text transformation
 * @returns Transformed Markdown
 */
export const mapMarkdownOutsideCode = (
  markdown: string,
  transform: (text: string) => string,
): string => {
  const parts = String(markdown || "").split(/(\r?\n)/);
  let inFence = false;
  let fenceMarker = "";
  let fenceLength = 0;
  let result = "";
  for (let index = 0; index < parts.length; index += 2) {
    const line = parts[index] || "";
    const newline = parts[index + 1] || "";
    const fence = line.match(/^\s*(?:>\s*)*(`{3,}|~{3,})/);
    const marker = fence?.[1];
    if (marker) {
      if (!inFence) {
        inFence = true;
        fenceMarker = marker[0] ?? "";
        fenceLength = marker.length;
      } else if (marker[0] === fenceMarker && marker.length >= fenceLength) {
        inFence = false;
        fenceLength = 0;
      }
      result += line + newline;
      continue;
    }
    if (inFence) {
      result += line + newline;
      continue;
    }
    const normalizedLine = mapMarkdownOutsideBackticks(line, transform);
    result += normalizedLine;
    if (!(normalizedLine.endsWith("\n") && newline)) result += newline;
  }
  return result;
};

// ponytail: line scanner skips code fences/backtick spans; use a Markdown AST only if more rewrites are added.
/**
 * Normalizes serialized Markdown while preserving code verbatim.
 *
 * @param markdown - Serialized Markdown
 * @returns Normalized Markdown
 */
export const normalizeMarkdownOutput = (markdown: string): string =>
  mapMarkdownOutsideCode(markdown, normalizeMarkdownOutputSegment);

/**
 * Converts HTML breaks to Markdown hard breaks in a non-code line.
 *
 * @param line - Markdown line
 * @returns Line with Markdown hard breaks
 */
export const normalizeHtmlBreaksInLine = (line: string): string =>
  String(line || "").replace(/<br\s*\/?>[ \t]*/gi, "  \n");

/**
 * Converts HTML breaks outside code to Markdown hard breaks.
 *
 * @param markdown - Markdown source
 * @returns Markdown with normalized breaks
 */
export const normalizeHtmlBreaks = (markdown: string): string =>
  mapMarkdownOutsideCode(markdown, normalizeHtmlBreaksInLine);

/**
 * Separates a leading YAML frontmatter block from Markdown content.
 *
 * @param markdown - Complete Markdown document
 * @returns Split document
 */
export const splitFrontmatter = (
  markdown: string,
): { frontmatter: string; body: string } => {
  const source = markdown || "";
  const match = source.match(/^(---\n[\s\S]*?\n---)(?:\n+|$)/);
  if (!match) return { frontmatter: "", body: source };
  return {
    frontmatter: match[1] ?? "",
    body: source.slice(match[0].length),
  };
};

/**
 * Reattaches frontmatter to normalized Markdown content.
 *
 * @param frontmatterBlock - YAML frontmatter including delimiters
 * @param markdown - Markdown body
 * @returns Complete Markdown document
 */
export const withFrontmatter = (
  frontmatterBlock: string,
  markdown: string,
): string => {
  const normalized = normalizeMarkdownOutput(markdown);
  const body = frontmatterBlock ? normalized.replace(/^\n+/, "") : normalized;
  return frontmatterBlock ? `${frontmatterBlock}\n\n${body}` : body;
};

/**
 * Extracts displayable key-value rows from YAML frontmatter.
 *
 * @param frontmatter - YAML frontmatter including delimiters
 * @returns Display rows
 */
export const frontmatterRows = (
  frontmatter: string,
): Array<{ key: string; value: string }> =>
  String(frontmatter || "")
    .split(/\r?\n/)
    .slice(1, -1)
    .map((line) => {
      const match = line.match(/^\s*([^:#][^:]*):\s*(.*)$/);
      if (!match) return null;
      return {
        key: (match[1] ?? "").trim(),
        value: (match[2] ?? "").trim() || " ",
      };
    })
    .filter((row): row is { key: string; value: string } => row !== null);

/**
 * Escapes plain text for safe insertion into editor-owned HTML.
 *
 * @param value - Plain value
 * @returns Escaped HTML text
 */
export const escapeHTML = (value: unknown): string =>
  String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

/**
 * Removes Markdown controls that should not enter Agent selection context.
 *
 * @param text - Selected Markdown text
 * @returns Readable selection text
 */
export const cleanSelectedText = (text: string): string =>
  String(text || "")
    .replace(htmlBreakPattern, "\n")
    .replace(/%%[\s\S]*?%%\n?/g, "")
    .replace(/!\[\[([^\]\n]+)\]\]/g, (_, raw) => {
      const embed = parseObsidianEmbed(raw);
      return embed.label || embed.target;
    })
    .replace(/\[\[([^\]\n]+)\]\]/g, (_, raw) => {
      const target = parseObsidianTarget(raw);
      return target.display || target.target;
    })
    .replace(
      /!\[([^\]\n]*)\]\([^\)\n]+\)/g,
      (_, alt) => parseMarkdownImageAlt(alt).alt || "",
    )
    .replace(/\[([^\]\n]+)\]\([^\)\n]+\)/g, "$1")
    .replace(/==([^=\n]+)==/g, "$1")
    .replace(/~~([^~\n]+)~~/g, "$1")
    .replace(/`([^`\n]+)`/g, "$1")
    .replace(/\^\[([^\]\n]+)\]/g, "$1")
    .replace(selectedTextCalloutControlRegex, "$1")
    .replace(/(^|\n)\s*>\s?/g, "$1")
    .replace(/(^|\n)\s*[-*+]\s+\[[ xX]\]\s*/g, "$1")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{2,}/g, "\n")
    .trim();
