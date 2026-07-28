export const imageTargetPattern = /\.(?:png|jpe?g|gif|webp|svg|avif|bmp|tiff?)(?:$|[?#])/i;

/**
 * Parses Obsidian's width or width-by-height image size syntax.
 *
 * @param {string} value - Raw size suffix
 * @returns {null | { width: number, height: number | null }} Parsed dimensions
 */
export const parseImageSize = (value) => {
  const raw = (value || '').trim();
  const match = raw.match(/^(\d{1,4})(?:x(\d{1,4}))?$/i);
  if (!match) return null;
  return {
    width: Math.max(1, Number(match[1])),
    height: match[2] ? Math.max(1, Number(match[2])) : null,
  };
};

/**
 * Applies parsed Obsidian dimensions to an image-like element.
 *
 * @param {HTMLElement} element - Rendered image or placeholder
 * @param {null | { width: number, height: number | null }} size - Parsed dimensions
 */
export const applyImageSize = (element, size) => {
  if (!size) return;
  element.style.width = `${size.width}px`;
  element.style.maxWidth = '100%';
  if (size.height) element.style.height = `${size.height}px`;
};

/**
 * Separates an image alt label from an optional Obsidian size suffix.
 *
 * @param {string} alt - Markdown image alt text
 * @returns {{ alt: string, size: null | { width: number, height: number | null } }} Parsed alt metadata
 */
export const parseMarkdownImageAlt = (alt) => {
  const parts = String(alt || '').split('|');
  const size = parts.length > 1 ? parseImageSize(parts.at(-1)) : null;
  return {
    alt: size ? parts.slice(0, -1).join('|').trim() : String(alt || ''),
    size,
  };
};

const rawTrimRange = (source, start, end) => {
  let from = start;
  let to = end;
  while (from < to && /\s/.test(source[from])) from += 1;
  while (to > from && /\s/.test(source[to - 1])) to -= 1;
  return { start: from, end: to };
};

const splitObsidianFields = (raw) => {
  const source = String(raw || '');
  const fields = [];
  let start = 0;
  let value = '';
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    if (character === '\\' && next === '|') {
      fields.push({
        raw: source.slice(start, index),
        value,
        start,
        end: index,
      });
      start = index + 2;
      value = '';
      index += 1;
      continue;
    }
    if (character === '|') {
      fields.push({
        raw: source.slice(start, index),
        value,
        start,
        end: index,
      });
      start = index + 1;
      value = '';
      continue;
    }
    value += character;
  }
  fields.push({
    raw: source.slice(start),
    value,
    start,
    end: source.length,
  });
  return fields;
};

/**
 * Parses an Obsidian wiki-link target and optional display alias.
 *
 * @param {string} raw - Content between wiki-link brackets
 * @returns {object} Parsed target, title, alias, and source ranges
 */
export const parseObsidianTarget = (raw) => {
  const source = String(raw || '').trim();
  const fields = splitObsidianFields(source);
  const targetField = fields.shift() || { value: '', start: 0, end: 0 };
  const target = targetField.value.trim();
  const aliasFields = fields;
  const alias = aliasFields.map((field) => field.value).join('|').trim();
  const aliasRange = aliasFields.length > 0
    ? rawTrimRange(source, aliasFields[0].start, aliasFields.at(-1).end)
    : null;
  const hashIndex = target.indexOf('#');
  const noteTitle = hashIndex >= 0 ? target.slice(0, hashIndex).trim() : target;
  return {
    source,
    target,
    noteTitle,
    display: alias || target,
    alias,
    aliasRange,
  };
};

/**
 * Parses an Obsidian embed target, label, and optional size.
 *
 * @param {string} raw - Content between embed brackets
 * @returns {object} Parsed embed metadata
 */
export const parseObsidianEmbed = (raw) => {
  const fields = splitObsidianFields(String(raw || '').trim());
  const target = (fields.shift()?.value || '').trim();
  const lastField = fields.at(-1);
  const size = lastField ? parseImageSize(lastField.value) : null;
  const labelFields = size ? fields.slice(0, -1) : fields;
  return {
    target,
    size,
    label: labelFields.map((field) => field.value).join('|').trim(),
  };
};
