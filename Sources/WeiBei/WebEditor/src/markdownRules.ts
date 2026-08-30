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

/**
 * CommonMark 判定强调闭合时,"delimiter 前是标点、后紧跟普通文字"的组合不是
 * 有效闭合(`**第一优先：**已有` 的全角冒号几乎必然触发),星号会原样显示。
 * 渲染前只对 CommonMark 必然拒绝的组合补一个空格让规则成立,本来合法的
 * 强调形式一个都不动。
 */
const emphasisBoundarySegment = (text: string) => String(text || '')
  // opener:普通文字后紧跟 delimiter 且内容以标点开头 → 开启前补空格。先修
  // opener,closer 一侧才能在"opener 前已是空白"的形态下识别配对。
  .replace(/([\p{L}\p{N}])(\*\*|__)(?=\p{P})/gu, '$1 $2')
  // closer:内容以标点收尾、闭合 delimiter 后紧跟非标点文字 → 闭合后补空格。
  // 内容不许以空白开头、opener 前排除字母数字,双保险防止把前一对的合法
  // 闭合星号当成下一对的开头跨对误配。
  .replace(/(^|[\s\p{P}])(\*\*|__)([^\s*_\n][^*_\n]*\p{P})\2(?=[^\s\p{P}])/gu, '$1$2$3$2 ')
  // 内容以空白收尾时 CommonMark 拒绝闭合(`**更广 **，`),去掉尾随空白。
  // 起点前必须是行首/空白/标点(像一个真正的开启),内容以非空白结尾,
  // 防止把相邻两对强调的"闭合+空格+开启"误接成一对。
  .replace(/(^|[\s\p{P}])(\*\*|__)([^*_\n]*?\S)[ \t]+\2(?=\S)/gu, '$1$2$3$2');

export const normalizeEmphasisBoundaries = (markdown: string) => mapMarkdownOutsideCode(markdown, emphasisBoundarySegment);

/** The one source matrix used by document loads, paste, Agent output, and internal inserts. */
export const normalizeMarkdownSource = (markdown: string, source: MarkdownSource) => {
  let normalized = normalizeHtmlBreaks(markdown);
  if (source === 'userPaste' || source === 'agentGenerated') normalized = normalizeCompatibleMathDelimiters(normalized);
  if (source === 'agentGenerated') normalized = normalizeAgentMath(normalized);
  normalized = normalizeEmphasisBoundaries(normalized);
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
