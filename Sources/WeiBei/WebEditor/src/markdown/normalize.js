import { parseMarkdownImageAlt, parseObsidianEmbed, parseObsidianTarget } from './obsidian.js';

export const calloutTypePattern = '[A-Za-z][A-Za-z0-9_-]*';
export const calloutPrefixPattern = '(?:\\s*>\\s*)*\\s*';
export const selectedTextCalloutControlRegex = new RegExp(`(^|\\n)\\s*(?:>\\s*)*\\\\?\\[!(?:${calloutTypePattern})\\][+-]?[ \\t]*`, 'gi');
const htmlBreakPattern = /<br\s*\/?>/gi;

/**
 * Checks whether a Markdown marker is escaped by an odd number of backslashes.
 *
 * @param {string} source - Markdown source
 * @param {number} index - Marker offset
 * @returns {boolean} Whether the marker is escaped
 */
export const isEscapedMarkdownPosition = (source, index) => {
  let slashCount = 0;
  for (let cursor = index - 1; cursor >= 0 && source[cursor] === '\\'; cursor -= 1) {
    slashCount += 1;
  }
  return slashCount % 2 === 1;
};

/**
 * Finds the next unescaped Markdown marker.
 *
 * @param {string} source - Markdown source
 * @param {string} marker - Marker to find
 * @param {number} from - Search start offset
 * @returns {number} Marker offset, or -1
 */
export const findUnescapedMarkdownMarker = (source, marker, from) => {
  let index = source.indexOf(marker, from);
  while (index >= 0 && isEscapedMarkdownPosition(source, index)) {
    index = source.indexOf(marker, index + marker.length);
  }
  return index;
};

/**
 * Transforms Markdown text outside inline-code spans.
 *
 * @param {string} line - Single Markdown line
 * @param {(text: string) => string} transform - Text transformation
 * @returns {string} Transformed line
 */
export const mapMarkdownOutsideBackticks = (line, transform) => {
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
 * @param {string} text - Markdown segment outside code
 * @returns {string} Normalized Markdown segment
 */
export const normalizeMarkdownOutputSegment = (text) => String(text || '')
  .replace(/\\\[\\\[/g, '[[')
  .replace(/\\\]\\\]/g, ']]')
  .replace(/\\=\\=([^=\n]+?)\\=\\=/g, '==$1==')
  .replace(/\^\\\[/g, '^[')
  .replace(/(^|\s)\\#(?=[\p{L}\p{N}_/-])/gu, '$1#')
  .replace(/\\\$(?=\d)/g, '$')
  .replace(new RegExp(`^(\\s*(?:>\\s*)*)\\\\(\\[!(?:${calloutTypePattern})\\])`, 'gim'), '$1$2');

/**
 * Transforms Markdown outside fenced and inline code.
 *
 * @param {string} markdown - Markdown source
 * @param {(text: string) => string} transform - Text transformation
 * @returns {string} Transformed Markdown
 */
export const mapMarkdownOutsideCode = (markdown, transform) => {
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
/**
 * Normalizes serialized Markdown while preserving code verbatim.
 *
 * @param {string} markdown - Serialized Markdown
 * @returns {string} Normalized Markdown
 */
export const normalizeMarkdownOutput = (markdown) => mapMarkdownOutsideCode(markdown, normalizeMarkdownOutputSegment);

/**
 * Converts HTML breaks to Markdown hard breaks in a non-code line.
 *
 * @param {string} line - Markdown line
 * @returns {string} Line with Markdown hard breaks
 */
export const normalizeHtmlBreaksInLine = (line) => String(line || '').replace(/<br\s*\/?>[ \t]*/gi, '  \n');

/**
 * Converts HTML breaks outside code to Markdown hard breaks.
 *
 * @param {string} markdown - Markdown source
 * @returns {string} Markdown with normalized breaks
 */
export const normalizeHtmlBreaks = (markdown) => mapMarkdownOutsideCode(markdown, normalizeHtmlBreaksInLine);

/**
 * Separates a leading YAML frontmatter block from Markdown content.
 *
 * @param {string} markdown - Complete Markdown document
 * @returns {{ frontmatter: string, body: string }} Split document
 */
export const splitFrontmatter = (markdown) => {
  const source = markdown || '';
  const match = source.match(/^(---\n[\s\S]*?\n---)(?:\n+|$)/);
  if (!match) return { frontmatter: '', body: source };
  return {
    frontmatter: match[1],
    body: source.slice(match[0].length),
  };
};

/**
 * Reattaches frontmatter to normalized Markdown content.
 *
 * @param {string} frontmatterBlock - YAML frontmatter including delimiters
 * @param {string} markdown - Markdown body
 * @returns {string} Complete Markdown document
 */
export const withFrontmatter = (frontmatterBlock, markdown) => {
  const normalized = normalizeMarkdownOutput(markdown);
  const body = frontmatterBlock ? normalized.replace(/^\n+/, '') : normalized;
  return frontmatterBlock ? `${frontmatterBlock}\n\n${body}` : body;
};

/**
 * Extracts displayable key-value rows from YAML frontmatter.
 *
 * @param {string} frontmatter - YAML frontmatter including delimiters
 * @returns {Array<{ key: string, value: string }>} Display rows
 */
export const frontmatterRows = (frontmatter) => String(frontmatter || '')
  .split(/\r?\n/)
  .slice(1, -1)
  .map((line) => {
    const match = line.match(/^\s*([^:#][^:]*):\s*(.*)$/);
    if (!match) return null;
    return {
      key: match[1].trim(),
      value: match[2].trim() || ' ',
    };
  })
  .filter(Boolean);

/**
 * Escapes plain text for safe insertion into editor-owned HTML.
 *
 * @param {unknown} value - Plain value
 * @returns {string} Escaped HTML text
 */
export const escapeHTML = (value) => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

/**
 * Removes Markdown controls that should not enter Agent selection context.
 *
 * @param {string} text - Selected Markdown text
 * @returns {string} Readable selection text
 */
export const cleanSelectedText = (text) => String(text || '')
  .replace(htmlBreakPattern, '\n')
  .replace(/%%[\s\S]*?%%\n?/g, '')
  .replace(/!\[\[([^\]\n]+)\]\]/g, (_, raw) => {
    const embed = parseObsidianEmbed(raw);
    return embed.label || embed.target;
  })
  .replace(/\[\[([^\]\n]+)\]\]/g, (_, raw) => {
    const target = parseObsidianTarget(raw);
    return target.display || target.target;
  })
  .replace(/!\[([^\]\n]*)\]\([^\)\n]+\)/g, (_, alt) => parseMarkdownImageAlt(alt).alt || '')
  .replace(/\[([^\]\n]+)\]\([^\)\n]+\)/g, '$1')
  .replace(/==([^=\n]+)==/g, '$1')
  .replace(/~~([^~\n]+)~~/g, '$1')
  .replace(/`([^`\n]+)`/g, '$1')
  .replace(/\^\[([^\]\n]+)\]/g, '$1')
  .replace(selectedTextCalloutControlRegex, '$1')
  .replace(/(^|\n)\s*>\s?/g, '$1')
  .replace(/(^|\n)\s*[-*+]\s+\[[ xX]\]\s*/g, '$1')
  .replace(/[ \t]+\n/g, '\n')
  .replace(/\n{2,}/g, '\n')
  .trim();
