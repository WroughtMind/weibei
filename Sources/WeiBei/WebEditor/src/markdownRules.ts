export const calloutTypePattern = '[A-Za-z][A-Za-z0-9_-]*';

const isEscapedMarkdownPosition = (source: string, index: number) => {
  let slashCount = 0;
  for (let cursor = index - 1; cursor >= 0 && source[cursor] === '\\'; cursor -= 1) {
    slashCount += 1;
  }
  return slashCount % 2 === 1;
};

const findUnescapedMarkdownMarker = (source: string, marker: string, from: number) => {
  let index = source.indexOf(marker, from);
  while (index >= 0 && isEscapedMarkdownPosition(source, index)) {
    index = source.indexOf(marker, index + marker.length);
  }
  return index;
};

const mapMarkdownOutsideBackticks = (line: string, transform: (value: string) => string) => {
  const source = String(line || '');
  let result = '';
  let cursor = 0;
  while (cursor < source.length) {
    const tick = findUnescapedMarkdownMarker(source, '`', cursor);
    if (tick < 0) {
      result += transform(source.slice(cursor));
      break;
    }
    result += transform(source.slice(cursor, tick));
    const marker = source.slice(tick).match(/^`+/)?.[0] || '`';
    const close = findUnescapedMarkdownMarker(source, marker, tick + marker.length);
    if (close < 0) {
      result += transform(source.slice(tick));
      break;
    }
    result += source.slice(tick, close + marker.length);
    cursor = close + marker.length;
  }
  return result;
};

const normalizeMarkdownOutputSegment = (text: string) => String(text || '')
  .replace(/(?<!\\)`/g, '\\`')
  .replace(/\\\[\\\[/g, '[[')
  .replace(/\\\]\\\]/g, ']]')
  .replace(/\\=\\=([^=\n]+?)\\=\\=/g, '==$1==')
  .replace(/\^\\\[/g, '^[')
  .replace(/(^|\s)\\#(?=[\p{L}\p{N}_/-])/gu, '$1#')
  .replace(/\\\$(?=\d)/g, '$')
  .replace(new RegExp(`^(\\s*(?:>\\s*)*)\\\\(\\[!(?:${calloutTypePattern})\\])`, 'gim'), '$1$2');

const mapMarkdownOutsideCode = (markdown: string, transform: (value: string) => string) => {
  const parts = String(markdown || '').split(/(\r?\n)/);
  let inFence = false;
  let fenceMarker = '';
  let fenceLength = 0;
  let result = '';
  for (let index = 0; index < parts.length; index += 2) {
    const line = parts[index] || '';
    const newline = parts[index + 1] || '';
    const fence = line.match(/^\s*(?:>\s*)*(`{3,}|~{3,})/);
    if (fence) {
      if (!inFence) {
        inFence = true;
        fenceMarker = fence[1][0];
        fenceLength = fence[1].length;
      } else if (fence[1][0] === fenceMarker && fence[1].length >= fenceLength) {
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
    if (!(normalizedLine.endsWith('\n') && newline)) result += newline;
  }
  return result;
};

// ponytail: line scanner skips code fences/backtick spans; use a Markdown AST only if more rewrites are added.
export const normalizeMarkdownOutput = (markdown: string) => mapMarkdownOutsideCode(markdown, normalizeMarkdownOutputSegment);

const normalizeHtmlBreaksInLine = (line: string) => /^\s*(?:>\s*)*<br\s*\/?>\s*$/i.test(line)
  ? line
  : String(line || '').replace(/<br\s*\/?>[ \t]*/gi, '\n'.padStart(3));

export const normalizeHtmlBreaks = (markdown: string) => mapMarkdownOutsideCode(markdown, normalizeHtmlBreaksInLine);

export type MarkdownSource = 'userDocument' | 'userPaste' | 'agentGenerated' | 'internalFragment';

export const inlineMathInputPattern = /(?<!\\)\$((?!\d)[^$\n]+)\$$/;

const protectCurrencySegment = (text: string) => String(text || '').replace(/(^|[^\\])\$(?=\d)/g, '$1\\$');

/** Prevents remark-math from treating ordinary prices and ranges as formulas. */
export const protectCurrencyDollars = (markdown: string) => mapMarkdownOutsideCode(markdown, protectCurrencySegment);

const normalizeCompatibleMathDelimiters = (markdown: string) => mapMarkdownOutsideCode(markdown, (text) => text
  .replace(/\\\[([\s\S]*?)\\\]/g, (_match, source) => `$$\n${String(source).trim()}\n$$`)
  .replace(/\\\(([^\n]*?)\\\)/g, (_match, source) => `$${String(source).trim()}$`));

const normalizeAgentMath = (markdown: string) => mapMarkdownOutsideCode(markdown, (text) => text
  .replace(/^[ \t]*\[\s*([^\n\]]*?\\[A-Za-z]+[^\n\]]*?)\s*\][ \t]*$/gm, (_match, source) => `$$\n${String(source).trim()}\n$$`)
  .replace(/^[ \t]*\$\$([^$\n]+)\$\$[ \t]*$/gm, (_match, source) => `$$\n${String(source).trim()}\n$$`)
  .replace(/\\hat\s+(\\[A-Za-z]+|[A-Za-z])/g, '\\hat{$1}')
  .replace(/\\hat(?!\{)(\\[A-Za-z]+|[A-Za-z])/g, '\\hat{$1}'));

/** The one source matrix used by document loads, paste, Agent output, and internal inserts. */
export const normalizeMarkdownSource = (markdown: string, source: MarkdownSource) => {
  let normalized = normalizeHtmlBreaks(markdown);
  if (source === 'userPaste' || source === 'agentGenerated') normalized = normalizeCompatibleMathDelimiters(normalized);
  if (source === 'agentGenerated') normalized = normalizeAgentMath(normalized);
  return protectCurrencyDollars(normalized);
};

const markdownSyntaxLineProbes: RegExp[] = [
  /^#{1,6}\s+\S/,
  /^>\s+\S/,
  /^>\s*\[![A-Za-z][A-Za-z0-9_-]*\]/,
  /^\s*[-*+]\s+\S/,
  /^\s*\d{1,9}[.)]\s+\S/,
  /^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/,
  /^\s*(?:>\s*)*(?:```|~~~)/,
  /^\|.*\|\s*$/,
  /!?\[[^\]\n]*\]\([^)\n]+\)/,
  /\[\[[^\]\n]+(?:\|[^\]\n]*)?\]\]/,
];

const markdownSyntaxInlineProbes: RegExp[] = [
  /\*\*|__/,
  /~~/,
  /==/,
  /`[^`\n]+`/,
  /\$\$/,
  /\$(?![\d\s$])[^$\n]+\$/,
];

/**
 * Conservative probe used by the editor paste path: does this clipboard text carry
 * Markdown worth parsing? Chat windows and browsers also put text/html on the
 * clipboard, and the Milkdown clipboard plugin prefers that HTML slice — plain
 * Markdown source then lands as literal text. Probing positive lets the editor
 * intercept and parse the Markdown before that fallback.
 */
export const looksLikeMarkdownSyntax = (text: string) => {
  const source = String(text || '');
  if (!source.trim()) return false;
  if (/^---[ \t]*\r?\n[\s\S]*?\r?\n---[ \t]*(?:\r?\n|$)/.test(source)) return true;
  for (const line of source.split(/\r?\n/)) {
    for (const probe of markdownSyntaxLineProbes) {
      if (probe.test(line)) return true;
    }
    for (const probe of markdownSyntaxInlineProbes) {
      if (probe.test(line)) return true;
    }
  }
  return false;
};

export const splitFrontmatter = (markdown: string) => {
  const source = markdown || '';
  const match = source.match(/^(---\n[\s\S]*?\n---)(?:\n+|$)/);
  if (!match) return { frontmatter: '', body: source };
  return {
    frontmatter: match[1],
    body: source.slice(match[0].length),
  };
};

export const joinFrontmatter = (frontmatter: string, markdown: string) => {
  const normalized = normalizeMarkdownOutput(markdown);
  const body = frontmatter ? normalized.replace(/^\n+/, '') : normalized;
  return frontmatter ? `${frontmatter}\n\n${body}` : body;
};
