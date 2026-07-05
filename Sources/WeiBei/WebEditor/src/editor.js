import { Editor, defaultValueCtx, editorViewCtx, editorViewOptionsCtx, rootCtx } from '@milkdown/kit/core';
import { commonmark } from '@milkdown/kit/preset/commonmark';
import { gfm } from '@milkdown/kit/preset/gfm';
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener';
import { readImageAsBase64, upload, uploadConfig } from '@milkdown/kit/plugin/upload';
import { Plugin, TextSelection } from '@milkdown/kit/prose/state';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';
import { getMarkdown as readMarkdown, insert, replaceAll, replaceRange, $prose } from '@milkdown/kit/utils';
import { katexOptionsCtx, math } from '@milkdown/plugin-math';
import 'katex/dist/katex.css';
import mermaid from 'mermaid';
import Prism from 'prismjs';
import 'prismjs/components/prism-bash';
import 'prismjs/components/prism-css';
import 'prismjs/components/prism-java';
import 'prismjs/components/prism-json';
import 'prismjs/components/prism-jsx';
import 'prismjs/components/prism-markdown';
import 'prismjs/components/prism-python';
import 'prismjs/components/prism-r';
import 'prismjs/components/prism-ruby';
import 'prismjs/components/prism-rust';
import 'prismjs/components/prism-sql';
import 'prismjs/components/prism-swift';
import 'prismjs/components/prism-tsx';
import 'prismjs/components/prism-typescript';
import 'prismjs/components/prism-yaml';

const bridge = window.webkit?.messageHandlers;
let editor;
let lastMarkdown = '';
let lastSelectionRange = null;
let lastSelectionReport = { text: null, rectKey: null };
let frontmatterBlock = '';
let isEditable = window.weiBeiMarkdownEditable !== false;
let currentDocumentID = window.weiBeiDocumentID || '';
let markdownBaseURL = window.weiBeiMarkdownBaseURL || '';
const localImageScheme = window.weiBeiLocalImageScheme || 'weibeiimage';
let attachmentRequestID = 0;
let imageRefreshFrame = 0;
let mermaidRenderID = 0;
const pendingAttachments = new Map();
const insertionCursorMarker = '{{WEIBEI_CURSOR}}';
const insertionSelectionStartMarker = '{{WEIBEI_SELECT_START}}';
const insertionSelectionEndMarker = '{{WEIBEI_SELECT_END}}';
const calloutTypes = new Set([
  'note',
  'tip',
  'important',
  'warning',
  'caution',
  'summary',
  'abstract',
  'quote',
  'question',
  'example',
  'info',
  'success',
  'failure',
  'danger',
  'bug',
  'todo',
]);
const calloutTypePattern = '[A-Za-z][A-Za-z0-9_-]*';
const calloutPrefixPattern = '(?:\\s*>\\s*)*\\s*';
const normalizeInterfaceLanguage = (value) => (value === 'en' ? 'en' : 'zh-Hans');
let currentLanguage = normalizeInterfaceLanguage(window.weiBeiInterfaceLanguage);
const calloutLabels = {
  'zh-Hans': {
    note: '札记',
    tip: '提示',
    important: '重点',
    warning: '留心',
    caution: '谨慎',
    summary: '提要',
    abstract: '摘要',
    quote: '引文',
    question: '问题',
    example: '例子',
    info: '信息',
    success: '可行',
    failure: '失败',
    danger: '风险',
    bug: '问题',
    todo: '待办',
  },
  en: {
    note: 'Note',
    tip: 'Tip',
    important: 'Important',
    warning: 'Warning',
    caution: 'Caution',
    summary: 'Summary',
    abstract: 'Abstract',
    quote: 'Quote',
    question: 'Question',
    example: 'Example',
    info: 'Info',
    success: 'Success',
    failure: 'Failure',
    danger: 'Danger',
    bug: 'Bug',
    todo: 'Todo',
  },
};
const calloutLabel = (type) => calloutLabels[currentLanguage]?.[type] || calloutLabels['zh-Hans'][type] || type;
const calloutRegex = new RegExp(`^${calloutPrefixPattern}\\\\?\\[!(${calloutTypePattern})\\]([+-]?)(?:[ \\t]+([^\\n]+))?`, 'i');
const calloutMarkerRegex = new RegExp(`^${calloutPrefixPattern}\\\\?\\[!(?:${calloutTypePattern})\\][+-]?\\s*`, 'i');
const calloutHeadingRegex = new RegExp(`^${calloutPrefixPattern}\\\\?\\[!(?:${calloutTypePattern})\\][+-]?(?:[ \\t]+[^\\n]+)?$`, 'i');
const selectedTextCalloutControlRegex = new RegExp(`(^|\\n)\\s*(?:>\\s*)*\\\\?\\[!(?:${calloutTypePattern})\\][+-]?[ \\t]*`, 'gi');
const cleanSelectedText = (text) => String(text || '')
  .replace(selectedTextCalloutControlRegex, '$1')
  .replace(/[ \t]+\n/g, '\n')
  .trim();
const calloutHeaderText = (node) => {
  const text = node.textBetween
    ? node.textBetween(0, node.content.size, '\n')
    : (node.textContent || '');
  return (text.split('\n')[0] || '').trimStart();
};
const firstParagraphText = (node) => {
  let first = '';
  node.descendants((child) => {
    if (first) return false;
    if (child.type?.name !== 'paragraph') return true;
    const text = (child.textContent || '').trimStart();
    if (!text) return true;
    first = text;
    return false;
  });
  return first;
};
const calloutMatchForBlockquote = (node) => (
  calloutHeaderText(node).match(calloutRegex)
    || firstParagraphText(node).match(calloutRegex)
);
const isBlockquoteType = (typeName) => typeName === 'blockquote' || typeName === 'block_quote';
const decorateCalloutHeadingSource = (decorations, node, pos) => {
  const text = node.textBetween
    ? node.textBetween(0, node.content.size, '')
    : (node.textContent || '');
  const marker = text.match(calloutMarkerRegex);
  if (!marker) return;
  const contentStart = pos + 1;
  const markerEnd = contentStart + marker[0].length;
  addRangeDecoration(decorations, contentStart, markerEnd, 'weibei-callout-marker');

  const heading = text.match(calloutHeadingRegex);
  if (!heading) return;
  const titleEnd = contentStart + heading[0].length;
  if (titleEnd > markerEnd) {
    addRangeDecoration(decorations, markerEnd, titleEnd, 'weibei-callout-heading-source');
  }
};
const decorateLeakedCalloutControls = (decorations, text, pos) => {
  for (const match of text.matchAll(selectedTextCalloutControlRegex)) {
    const lineBreakSize = match[1]?.length || 0;
    const from = pos + (match.index || 0) + lineBreakSize;
    const to = pos + (match.index || 0) + match[0].length;
    addRangeDecoration(decorations, from, to, 'weibei-callout-marker');
  }
};

const normalizeTheme = (theme) => (theme === 'inkstone' ? 'inkstone' : 'paper');
let currentTheme = normalizeTheme(window.weiBeiTheme);

const mermaidThemeVariables = () => {
  if (currentTheme === 'inkstone') {
    return {
      background: '#151515',
      primaryColor: '#1c1c1c',
      primaryTextColor: '#d7cbb0',
      primaryBorderColor: '#3a3328',
      lineColor: '#8b5e3c',
      secondaryColor: '#222222',
      tertiaryColor: '#171717',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Songti SC", serif',
    };
  }
  return {
    background: '#fbf5e8',
    primaryColor: '#f6eddc',
    primaryTextColor: '#2e261f',
    primaryBorderColor: '#cbb79b',
    lineColor: '#7a6250',
    secondaryColor: '#efe4d2',
    tertiaryColor: '#f8f0e1',
    fontFamily: '-apple-system, BlinkMacSystemFont, "Songti SC", serif',
  };
};

const initializeMermaid = () => {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: 'base',
    themeVariables: mermaidThemeVariables(),
  });
};

const applyTheme = (theme) => {
  currentTheme = normalizeTheme(theme);
  document.documentElement.dataset.weibeiTheme = currentTheme;
  if (document.body) document.body.dataset.weibeiTheme = currentTheme;
  initializeMermaid();
};

applyTheme(currentTheme);

const showFailure = (error) => {
  if (window.WeiBeiEditorBootFailed) {
    window.WeiBeiEditorBootFailed(error);
    return;
  }
  const root = document.querySelector('#editor');
  if (!root) return;
  root.innerHTML = `<pre style="white-space:pre-wrap;color:#9f3427;padding:24px;font:13px/1.5 SFMono-Regular,Menlo,monospace;">Milkdown 初始化失败\n${String(error?.stack || error)}</pre>`;
};

window.addEventListener('error', (event) => showFailure(event.error || event.message));
window.addEventListener('unhandledrejection', (event) => showFailure(event.reason));

const post = (name, body = {}) => {
  bridge?.[name]?.postMessage({ ...body, documentID: currentDocumentID });
};

const rectFromSelection = () => {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return null;
  const rect = selection.getRangeAt(0).getBoundingClientRect();
  if (!rect || rect.width + rect.height === 0) return null;
  return {
    x: rect.left + rect.width / 2,
    y: rect.bottom,
    width: rect.width,
    height: rect.height,
  };
};

const normalizeMarkdownOutput = (markdown) => (markdown || '')
  .replace(/\\\[\\\[/g, '[[')
  .replace(/\\\]\\\]/g, ']]')
  .replace(/\\=\\=([^=\n]+?)\\=\\=/g, '==$1==')
  .replace(/\^\\\[/g, '^[')
  .replace(/(^|\s)\\#(?=[\p{L}\p{N}_/-])/gu, '$1#')
  .replace(/\\\$(?=\d)/g, '$')
  .replace(new RegExp(`^(\\s*(?:>\\s*)*)\\\\(\\[!(?:${calloutTypePattern})\\])`, 'gim'), '$1$2');

const splitFrontmatter = (markdown) => {
  const source = markdown || '';
  const match = source.match(/^(---\n[\s\S]*?\n---)(?:\n+|$)/);
  if (!match) return { frontmatter: '', body: source };
  return {
    frontmatter: match[1],
    body: source.slice(match[0].length),
  };
};

const withFrontmatter = (markdown) => {
  const normalized = normalizeMarkdownOutput(markdown);
  const body = frontmatterBlock ? normalized.replace(/^\n+/, '') : normalized;
  return frontmatterBlock ? `${frontmatterBlock}\n\n${body}` : body;
};

const frontmatterRows = (frontmatter) => String(frontmatter || '')
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

const syncFrontmatterPanel = () => {
  const panel = document.querySelector('#frontmatter-panel');
  if (!panel) return;
  const rows = frontmatterRows(frontmatterBlock);
  panel.dataset.visible = rows.length > 0 ? 'true' : 'false';
  panel.innerHTML = rows.length > 0
    ? `<div class="frontmatter-title">Properties</div>${rows.map((row) => (
      `<div class="frontmatter-row"><span class="frontmatter-key">${escapeHTML(row.key)}</span><span>${escapeHTML(row.value)}</span></div>`
    )).join('')}`
    : '';
};

const escapeHTML = (value) => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

const localImageURL = (src) => `${localImageScheme}://image?src=${encodeURIComponent(src)}`;
const imageTargetPattern = /\.(?:png|jpe?g|gif|webp|svg|avif|bmp|tiff?)(?:$|[?#])/i;

const parseImageSize = (value) => {
  const raw = (value || '').trim();
  const match = raw.match(/^(\d{1,4})(?:x(\d{1,4}))?$/i);
  if (!match) return null;
  return {
    width: Math.max(1, Number(match[1])),
    height: match[2] ? Math.max(1, Number(match[2])) : null,
  };
};

const applyImageSize = (element, size) => {
  if (!size) return;
  element.style.width = `${size.width}px`;
  element.style.maxWidth = '100%';
  if (size.height) element.style.height = `${size.height}px`;
};

const parseMarkdownImageAlt = (alt) => {
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

const parseObsidianTarget = (raw) => {
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

const parseObsidianEmbed = (raw) => {
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

const missingImageURL = () => {
  const palette = currentTheme === 'inkstone'
    ? { background: '#151515', accent: '#a6362b', text: '#d7cbb0' }
    : { background: '#efe6d8', accent: '#9f3b2f', text: '#6b5148' };
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="156" height="34" viewBox="0 0 156 34">
  <rect width="156" height="34" rx="3" fill="${palette.background}"/>
  <path d="M18 22l5-6 4 4 3-3 6 5" fill="none" stroke="${palette.accent}" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
  <rect x="17" y="11" width="20" height="14" rx="2" fill="none" stroke="${palette.accent}" stroke-width="1.2"/>
  <text x="48" y="22" fill="${palette.text}" font-family="-apple-system, BlinkMacSystemFont, 'Songti SC', serif" font-size="13">图片未找到</text>
</svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
};

const resolveMarkdownURL = (src) => {
  if (!src || /^(?:https?:|data:|blob:|weibeiimage:)/i.test(src)) return src;
  try {
    const resolved = new URL(src, markdownBaseURL || window.location.href).href;
    return /^file:/i.test(resolved) ? localImageURL(resolved) : resolved;
  } catch {
    return src;
  }
};

const documentImageSources = (state) => {
  const sources = [];
  state.doc.descendants((node) => {
    if (node.type.name === 'image' && node.attrs.src) sources.push(node.attrs.src);
    return true;
  });
  return sources;
};

const syncEditableState = () => {
  document.body.dataset.editable = isEditable ? 'true' : 'false';
};

const resolveEditorImages = (view) => {
  const sources = documentImageSources(view.state);
  const images = Array.from(view.dom.querySelectorAll('img'));
  images.forEach((image, index) => {
    const source = sources[index];
    if (!source) return;
    const resolved = resolveMarkdownURL(source);
    const { alt, size } = parseMarkdownImageAlt(image.getAttribute('alt') || '');
    if (alt) image.setAttribute('alt', alt);
    applyImageSize(image, size);
    image.dataset.weibeiMarkdownSrc = source;
    if (!image.dataset.weibeiImageEventsBound) {
      image.dataset.weibeiImageEventsBound = 'true';
      image.addEventListener('error', () => {
        image.dataset.weibeiImageMissingFor = image.dataset.weibeiResolvedSrc || image.getAttribute('src') || '';
        image.dataset.weibeiImagePlaceholder = 'true';
        image.classList.add('weibei-image-missing');
        image.setAttribute('src', missingImageURL());
      });
      image.addEventListener('load', () => {
        if (image.dataset.weibeiImagePlaceholder === 'true') return;
        image.classList.remove('weibei-image-missing');
      });
    }
    if (image.dataset.weibeiImageMissingFor === resolved && image.dataset.weibeiImagePlaceholder === 'true') {
      return;
    }
    if (resolved && image.getAttribute('src') !== resolved) {
      image.dataset.weibeiResolvedSrc = resolved;
      delete image.dataset.weibeiImagePlaceholder;
      image.classList.remove('weibei-image-missing');
      image.setAttribute('src', resolved);
    }
  });
};

const scheduleImageResolution = (view) => {
  window.cancelAnimationFrame(imageRefreshFrame);
  imageRefreshFrame = window.requestAnimationFrame(() => resolveEditorImages(view));
};

const refreshRenderedImages = () => {
  if (!editor) return;
  editor.action((ctx) => scheduleImageResolution(ctx.get(editorViewCtx)));
};

const editorSelectionRange = () => {
  if (!editor) return null;
  const selection = editor.action((ctx) => ctx.get(editorViewCtx).state.selection);
  if (!selection || selection.empty) return null;
  return { from: selection.from, to: selection.to };
};

const editorSelectedText = () => {
  if (!editor) return '';
  return editor.action((ctx) => {
    const { selection } = ctx.get(editorViewCtx).state;
    if (!selection || selection.empty) return '';
    const content = selection.content().content;
    return cleanSelectedText(content.textBetween(0, content.size, '\n'));
  });
};

const selectedText = () => cleanSelectedText(window.getSelection()?.toString() || editorSelectedText());

const addRangeDecoration = (decorations, from, to, className, attrs = {}) => {
  if (to <= from) return;
  decorations.push(Decoration.inline(from, to, { ...attrs, class: className }));
};

const isInsideNode = (state, pos, typeName) => {
  const resolved = state.doc.resolve(pos);
  for (let depth = resolved.depth; depth >= 0; depth -= 1) {
    if (resolved.node(depth).type.name === typeName) return true;
  }
  return false;
};

const decorateDelimitedInline = (decorations, text, pos, regex, markerSize, className) => {
  for (const match of text.matchAll(regex)) {
    const from = pos + (match.index || 0);
    const to = from + match[0].length;
    addRangeDecoration(decorations, from, from + markerSize, 'weibei-md-marker');
    addRangeDecoration(decorations, from + markerSize, to - markerSize, className);
    addRangeDecoration(decorations, to - markerSize, to, 'weibei-md-marker');
  }
};

const decorateInlineFootnotes = (decorations, text, pos) => {
  for (const match of text.matchAll(/(^|[^\\])\^\[([^\]\n]+)\]/g)) {
    const prefixLength = match[1]?.length || 0;
    const content = match[2] || '';
    const from = pos + (match.index || 0) + prefixLength;
    const to = from + match[0].length - prefixLength;
    addRangeDecoration(decorations, from, from + 2, 'weibei-md-marker');
    addRangeDecoration(decorations, from + 2, to - 1, 'weibei-inline-footnote', {
      title: `行内脚注：${content}`,
      'aria-label': `行内脚注：${content}`,
    });
    addRangeDecoration(decorations, to - 1, to, 'weibei-md-marker');
  }
};

const decorateWikiLinks = (decorations, text, pos) => {
  for (const match of text.matchAll(/\[\[([^\]\n]+)\]\]/g)) {
    const index = match.index || 0;
    if (text[index - 1] === '!') continue;
    const from = pos + index;
    const to = from + match[0].length;
    const parsed = parseObsidianTarget(match[1]);
    const title = parsed.noteTitle || parsed.target;
    const bridgeTitle = parsed.target || title;
    addRangeDecoration(decorations, from, from + 2, 'weibei-md-marker');
    if (parsed.aliasRange && parsed.aliasRange.end > parsed.aliasRange.start) {
      addRangeDecoration(decorations, from + 2, from + 2 + parsed.aliasRange.start, 'weibei-md-marker');
      addRangeDecoration(decorations, from + 2 + parsed.aliasRange.start, from + 2 + parsed.aliasRange.end, 'weibei-wikilink', {
        role: 'link',
        tabindex: '0',
        title: `打开或创建笔记：${title}`,
        'data-wikilink-target': parsed.target,
        'data-wikilink-title': bridgeTitle,
      });
      addRangeDecoration(decorations, from + 2 + parsed.aliasRange.end, to - 2, 'weibei-md-marker');
    } else {
      addRangeDecoration(decorations, from + 2, to - 2, 'weibei-wikilink', {
        role: 'link',
        tabindex: '0',
        title: `打开或创建笔记：${title}`,
        'data-wikilink-target': parsed.target,
        'data-wikilink-title': bridgeTitle,
      });
    }
    addRangeDecoration(decorations, to - 2, to, 'weibei-md-marker');
  }
};

const decorateSourceReferences = (decorations, text, pos) => {
  for (const match of text.matchAll(/(?:^|\s)(来源：[^\n]+)/g)) {
    const prefixLength = match[0].startsWith('来源：') ? 0 : 1;
    const from = pos + (match.index || 0) + prefixLength;
    const to = from + match[1].length;
    addRangeDecoration(decorations, from, to, 'weibei-source-reference', {
      role: 'link',
      tabindex: '0',
      title: `打开来源：${match[1].slice('来源：'.length).trim()}`,
      'data-source-reference': match[1],
    });
  }
};

const decorateObsidianEmbeds = (decorations, text, pos) => {
  for (const match of text.matchAll(/!\[\[([^\]\n]+)\]\]/g)) {
    const from = pos + (match.index || 0);
    const to = from + match[0].length;
    const embed = parseObsidianEmbed(match[1]);
    addRangeDecoration(decorations, from, to, 'weibei-embed-source');
    decorations.push(Decoration.widget(to, () => {
      if (imageTargetPattern.test(embed.target)) {
        const image = document.createElement('img');
        image.className = 'weibei-embed-preview weibei-embed-image';
        image.alt = embed.target;
        image.src = resolveMarkdownURL(embed.target);
        applyImageSize(image, embed.size);
        image.addEventListener('error', () => {
          image.src = missingImageURL();
          image.classList.add('weibei-image-missing');
        });
        return image;
      }
      const chip = document.createElement('span');
      chip.className = 'weibei-embed-preview weibei-embed-note';
      chip.textContent = `嵌入：${embed.label || embed.target}`;
      chip.setAttribute('role', 'link');
      chip.setAttribute('tabindex', '0');
      chip.setAttribute('title', `打开或创建笔记：${embed.target}`);
      chip.dataset.wikilinkTarget = embed.target;
      chip.dataset.wikilinkTitle = embed.target;
      return chip;
    }, { side: 1 }));
  }
};

const decorateComments = (decorations, text, pos, commentState) => {
  let cursor = 0;
  while (cursor < text.length) {
    if (commentState.open) {
      const end = text.indexOf('%%', cursor);
      if (end < 0) {
        addRangeDecoration(decorations, pos + cursor, pos + text.length, 'weibei-comment');
        return;
      }
      addRangeDecoration(decorations, pos + cursor, pos + end + 2, 'weibei-comment');
      commentState.open = false;
      cursor = end + 2;
      continue;
    }

    const start = text.indexOf('%%', cursor);
    if (start < 0) return;
    const end = text.indexOf('%%', start + 2);
    if (end < 0) {
      addRangeDecoration(decorations, pos + start, pos + text.length, 'weibei-comment');
      commentState.open = true;
      return;
    }
    addRangeDecoration(decorations, pos + start, pos + end + 2, 'weibei-comment');
    cursor = end + 2;
  }
};

const decorateTagsAndBlocks = (decorations, text, pos) => {
  for (const match of text.matchAll(/(^|\s)(#[\p{L}\p{N}_/-]+)\b/gu)) {
    const from = pos + (match.index || 0) + match[1].length;
    addRangeDecoration(decorations, from, from + match[2].length, 'weibei-tag');
  }
  for (const match of text.matchAll(/(^|\s)(\^[A-Za-z0-9-]+)\s*$/g)) {
    const from = pos + (match.index || 0) + match[1].length;
    addRangeDecoration(decorations, from, from + match[2].length, 'weibei-block-id');
  }
};

const mermaidWidget = (source) => {
  const container = document.createElement('div');
  container.className = 'weibei-mermaid-render';
  container.textContent = '正在渲染 Mermaid 图表...';
  window.setTimeout(async () => {
    try {
      const id = `weibei-mermaid-${mermaidRenderID += 1}`;
      const { svg, bindFunctions } = await mermaid.render(id, source, container);
      container.innerHTML = svg;
      bindFunctions?.(container);
      container.dataset.rendered = 'true';
    } catch (error) {
      container.classList.add('weibei-mermaid-error');
      container.textContent = `Mermaid 图表未解析\n${String(error?.message || error)}`;
    }
  }, 0);
  return container;
};

const decorateMermaidBlock = (decorations, node, pos) => {
  if (normalizeLanguage(node.attrs.language || '') !== 'mermaid') return false;
  decorations.push(Decoration.node(pos, pos + node.nodeSize, {
    class: 'weibei-code-block weibei-mermaid-block',
    'data-language': 'mermaid',
  }));
  decorations.push(Decoration.widget(pos + node.nodeSize - 1, () => mermaidWidget(node.textContent), { side: 1 }));
  return true;
};

const wikiNavigationTitle = (raw) => {
  const parsed = parseObsidianTarget(raw);
  return parsed.target || parsed.noteTitle;
};

const wikiTitleFromTarget = (target) => {
  const link = target instanceof Element
    ? target.closest('.weibei-wikilink, .weibei-embed-note[data-wikilink-title]')
    : null;
  return link?.getAttribute('data-wikilink-title') || link?.textContent?.trim() || '';
};

const activateWikiLink = (target) => {
  const title = wikiTitleFromTarget(target);
  if (!title) return false;
  post('wikiLinkActivated', { title });
  return true;
};

const sourceReferenceFromTarget = (target) => {
  const link = target instanceof Element
    ? target.closest('.weibei-source-reference[data-source-reference]')
    : null;
  return link?.getAttribute('data-source-reference') || '';
};

const activateSourceReference = (target) => {
  const reference = sourceReferenceFromTarget(target);
  if (!reference) return false;
  post('sourceReferenceActivated', { reference });
  return true;
};

const normalizeLanguage = (language) => {
  const key = (language || '').trim().toLowerCase();
  const aliases = {
    js: 'javascript',
    jsx: 'jsx',
    ts: 'typescript',
    tsx: 'tsx',
    py: 'python',
    rb: 'ruby',
    sh: 'bash',
    shell: 'bash',
    zsh: 'bash',
    md: 'markdown',
    yml: 'yaml',
  };
  return aliases[key] || key;
};

const tokenLength = (token) => {
  if (typeof token === 'string') return token.length;
  if (Array.isArray(token.content)) return token.content.reduce((sum, child) => sum + tokenLength(child), 0);
  return String(token.content || '').length;
};

const tokenClass = (token) => {
  const aliases = Array.isArray(token.alias) ? token.alias : token.alias ? [token.alias] : [];
  return ['weibei-prism-token', 'token', token.type, ...aliases].filter(Boolean).join(' ');
};

const addTokenDecorations = (decorations, tokens, start) => {
  let cursor = start;
  for (const token of tokens) {
    const length = tokenLength(token);
    if (typeof token !== 'string' && length > 0) {
      addRangeDecoration(decorations, cursor, cursor + length, tokenClass(token));
      if (Array.isArray(token.content)) {
        addTokenDecorations(decorations, token.content, cursor);
      }
    }
    cursor += length;
  }
};

const decorateCodeBlock = (decorations, node, pos) => {
  const language = normalizeLanguage(node.attrs.language || '');
  if (!language || !Prism.languages[language]) return;
  try {
    addTokenDecorations(decorations, Prism.tokenize(node.textContent, Prism.languages[language]), pos + 1);
  } catch {
    // Prism should not be allowed to break editing.
  }
};

const wikiTitleAtSelection = () => {
  if (!editor) return '';
  return editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    const pos = view.state.selection.from;
    let title = '';
    view.state.doc.descendants((node, nodePos) => {
      if (!node.isText || title) return true;
      const text = node.text || '';
      const start = nodePos;
      const end = nodePos + text.length;
      if (pos < start || pos > end) return true;
      for (const match of text.matchAll(/\[\[([^\]\n]+)\]\]/g)) {
        const from = start + (match.index || 0);
        const to = from + match[0].length;
        if (pos >= from && pos <= to) {
          title = wikiNavigationTitle(match[1]);
          return false;
        }
      }
      return true;
    });
    return title;
  });
};

const requestAttachment = async (file) => {
  const { alt, src } = await readImageAsBase64(file);
  if (!bridge?.imageAttachmentRequested) {
    return { alt, src };
  }
  const id = `attachment-${Date.now()}-${attachmentRequestID += 1}`;
  return new Promise((resolve, reject) => {
    pendingAttachments.set(id, { resolve, reject });
    post('imageAttachmentRequested', {
      id,
      name: file.name || alt || 'image',
      mime: file.type || 'image/png',
      dataURL: src,
    });
    window.setTimeout(() => {
      if (!pendingAttachments.has(id)) return;
      pendingAttachments.delete(id);
      reject(new Error('Attachment save timed out'));
    }, 15000);
  });
};

const looksLikeBlockMarkdown = (markdown) => {
  const text = String(markdown || '');
  const trimmed = text.trim();
  if (!trimmed) return false;
  if (text.includes('\n')) return true;
  return /^(?:#{1,6}\s|[-*+]\s|\d+\.\s|>\s|```|~~~|\$\$|\|.*\||---$)/.test(trimmed);
};

const normalizeMarkdownInsertion = (markdown) => {
  const text = String(markdown || '');
  if (!looksLikeBlockMarkdown(text)) return text;
  return `\n\n${text.trim()}\n\n`;
};

const placeCursorAtInsertionMarker = () => editor.action((ctx) => {
  const view = ctx.get(editorViewCtx);
  let selectionRange = null;
  let range = null;
  view.state.doc.descendants((node, pos) => {
    if (!node.isText || selectionRange || range) return true;
    const text = node.text || '';
    const startIndex = text.indexOf(insertionSelectionStartMarker);
    const endIndex = text.indexOf(insertionSelectionEndMarker);
    if (startIndex >= 0 && endIndex > startIndex) {
      selectionRange = {
        startFrom: pos + startIndex,
        startTo: pos + startIndex + insertionSelectionStartMarker.length,
        endFrom: pos + endIndex,
        endTo: pos + endIndex + insertionSelectionEndMarker.length,
      };
      return false;
    }
    const index = text.indexOf(insertionCursorMarker);
    if (index < 0) return true;
    range = {
      from: pos + index,
      to: pos + index + insertionCursorMarker.length,
    };
    return false;
  });
  if (selectionRange) {
    const tr = view.state.tr
      .delete(selectionRange.endFrom, selectionRange.endTo)
      .delete(selectionRange.startFrom, selectionRange.startTo);
    const from = Math.min(selectionRange.startFrom, tr.doc.content.size);
    const to = Math.min(
      Math.max(from, selectionRange.endFrom - insertionSelectionStartMarker.length),
      tr.doc.content.size,
    );
    tr.setSelection(TextSelection.create(tr.doc, from, to));
    view.dispatch(tr);
    return true;
  }
  if (!range) return false;
  const tr = view.state.tr.delete(range.from, range.to);
  const selectionPosition = Math.min(range.from, tr.doc.content.size);
  tr.setSelection(TextSelection.create(tr.doc, selectionPosition));
  view.dispatch(tr);
  return true;
});

const collapseSelectionToEnd = () => editor.action((ctx) => {
  const view = ctx.get(editorViewCtx);
  const position = Math.min(view.state.selection.to, view.state.doc.content.size);
  view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, position)));
});

const localImageUploader = async (files, schema) => {
  if (!isEditable) return [];
  const images = [];
  for (let i = 0; i < files.length; i += 1) {
    const file = files.item(i);
    if (file && file.type.includes('image')) images.push(file);
  }
  const imageNode = schema.nodes.image;
  if (!imageNode || images.length === 0) return [];
  const saved = await Promise.all(images.map(requestAttachment));
  return saved.map(({ alt, src }) => imageNode.createAndFill({ alt, src })).filter(Boolean);
};

const imageFilesFromItems = (items) => Array.from(items || [])
  .map((item) => item.getAsFile?.())
  .filter((file) => file && file.type.includes('image'));

const markdownImage = ({ alt, src }) => {
  const safeAlt = (alt || 'image').replace(/[\[\]\n\r]/g, ' ').trim() || 'image';
  const safeSrc = String(src || '').replace(/\s/g, '%20').replace(/\)/g, '%29');
  return `![${safeAlt}](${safeSrc})`;
};

const insertImageFiles = async (files) => {
  if (!isEditable) return;
  const saved = await Promise.all(files.map(requestAttachment));
  replaceSelectionInternal(saved.map(markdownImage).join('\n\n'));
};

const annotateMathErrors = () => {
  window.requestAnimationFrame(() => {
    document.querySelectorAll('.ProseMirror .katex-error').forEach((element) => {
      if (element.getAttribute('title')) return;
      element.setAttribute('title', '公式没有通过 KaTeX 解析。常用写法：x_i、x^{2}、\\frac{a}{b}、\\begin{bmatrix}...\\end{bmatrix}');
    });
  });
};

const quietScrollableSelector = '#editor, .ProseMirror pre, .ProseMirror div[data-type="math_block"], .ProseMirror div[data-type="math-block"]';
const scrollFadeTimers = new WeakMap();

const markScrollActive = (element) => {
  if (!(element instanceof Element)) return;
  element.classList.add('weibei-scroll-active');
  const timer = scrollFadeTimers.get(element);
  if (timer) window.clearTimeout(timer);
  scrollFadeTimers.set(element, window.setTimeout(() => {
    element.classList.remove('weibei-scroll-active');
    scrollFadeTimers.delete(element);
  }, 850));
};

const installQuietScrollIndicators = () => {
  document.addEventListener('scroll', (event) => {
    const target = event.target instanceof Element
      ? event.target.closest(quietScrollableSelector)
      : null;
    if (target) markScrollActive(target);
  }, true);
};

const weiBeiDialectPlugin = $prose(() => new Plugin({
  view(view) {
    scheduleImageResolution(view);
    annotateMathErrors();
    return {
      update(updatedView) {
        scheduleImageResolution(updatedView);
        annotateMathErrors();
      },
    };
  },
  props: {
    handlePaste(_, event) {
      if (!isEditable) return false;
      const files = imageFilesFromItems(event.clipboardData?.items);
      if (files.length === 0) return false;
      event.preventDefault();
      insertImageFiles(files).catch(showFailure);
      return true;
    },
    handleDrop(_, event) {
      if (!isEditable) return false;
      const files = imageFilesFromItems(event.dataTransfer?.items);
      if (files.length === 0) return false;
      event.preventDefault();
      insertImageFiles(files).catch(showFailure);
      return true;
    },
    handleClick(view, pos, event) {
      return activateWikiLink(event.target) || activateSourceReference(event.target);
    },
    handleKeyDown(_, event) {
      if (event.key !== 'Enter' && event.key !== ' ') return false;
      if (activateSourceReference(event.target)) {
        event.preventDefault();
        return true;
      }
      if (!event.metaKey && !event.ctrlKey) return false;
      const title = wikiTitleAtSelection();
      if (!title) return false;
      post('wikiLinkActivated', { title });
      event.preventDefault();
      return true;
    },
    decorations(state) {
      const decorations = [];
      const commentState = { open: false };

      state.doc.descendants((node, pos, parent) => {
        const typeName = node.type.name;
        const parentName = parent?.type?.name || '';

        if (isBlockquoteType(typeName)) {
          const match = calloutMatchForBlockquote(node);
          if (match) {
            const calloutType = match[1].toLowerCase();
            const calloutClass = calloutTypes.has(calloutType)
              ? `weibei-callout-${calloutType}`
              : `weibei-callout-${calloutType} weibei-callout-custom`;
            decorations.push(Decoration.node(pos, pos + node.nodeSize, {
              class: `weibei-callout weibei-callout-has-heading ${calloutClass}`,
              'data-callout': calloutType,
              'data-callout-fold': match[2] || '',
              'data-callout-title': (match[3] || calloutLabel(calloutType)).trim(),
            }));
          }
        }

        if (typeName === 'paragraph' && isBlockquoteType(parentName)) {
          const calloutHeading = node.textContent.trimStart().match(calloutRegex);
          if (calloutHeading) {
            decorations.push(Decoration.node(pos, pos + node.nodeSize, {
              class: 'weibei-callout-heading',
            }));
            decorateCalloutHeadingSource(decorations, node, pos);
          }
        }

        if (typeName === 'image' && node.attrs.src) {
          decorations.push(Decoration.node(pos, pos + node.nodeSize, {
            class: 'weibei-image',
            src: resolveMarkdownURL(node.attrs.src),
          }));
        }

        if (typeName === 'code_block') {
          if (decorateMermaidBlock(decorations, node, pos)) return false;
          decorations.push(Decoration.node(pos, pos + node.nodeSize, {
            class: 'weibei-code-block',
            'data-language': node.attrs.language || '',
          }));
          decorateCodeBlock(decorations, node, pos);
          return false;
        }

        if (node.isText) {
          const textPos = pos;
          const text = node.text || '';
          const hasCodeMark = (node.marks || []).some((mark) => mark.type.name.toLowerCase().includes('code'));
          const insideBlockquote = isInsideNode(state, textPos, 'blockquote') || isInsideNode(state, textPos, 'block_quote');
          if (insideBlockquote) decorateLeakedCalloutControls(decorations, text, textPos);
          decorateDelimitedInline(decorations, text, textPos, /==([^=\n]+)==/g, 2, 'weibei-highlight');
          if (!hasCodeMark) {
            decorateInlineFootnotes(decorations, text, textPos);
          }
          decorateComments(decorations, text, textPos, commentState);
          decorateObsidianEmbeds(decorations, text, textPos);
          decorateWikiLinks(decorations, text, textPos);
          decorateSourceReferences(decorations, text, textPos);
          decorateTagsAndBlocks(decorations, text, textPos);

        }

        return true;
      });

      return DecorationSet.create(state.doc, decorations);
    },
  },
}));

const reportSelection = () => {
  if (window.weiBeiSuppressSelectionReport) return;
  const text = selectedText();
  const rect = text ? rectFromSelection() : null;
  const rectKey = rect
    ? `${Math.round(rect.x)}:${Math.round(rect.y)}:${Math.round(rect.width)}:${Math.round(rect.height)}`
    : '';
  if (text === lastSelectionReport.text && rectKey === lastSelectionReport.rectKey) return;
  lastSelectionReport = { text, rectKey };
  if (!text) {
    lastSelectionRange = null;
    post('selectionChanged', { text: '', rect: null });
    return;
  }
  lastSelectionRange = editorSelectionRange();
  post('selectionChanged', { text, rect });
};

const ensureEditor = () => {
  if (!editor) throw new Error('WeiBei editor is not ready');
};

const setMarkdownInternal = (markdown) => {
  ensureEditor();
  const document = splitFrontmatter(markdown || '');
  frontmatterBlock = document.frontmatter;
  editor.action(replaceAll(document.body || ''));
  lastMarkdown = withFrontmatter(document.body);
};

const getMarkdownInternal = () => {
  ensureEditor();
  return withFrontmatter(editor.action(readMarkdown()));
};

const replaceSelectionInternal = (markdown) => {
  ensureEditor();
  const range = lastSelectionRange || editorSelectionRange();
  if (range) {
    editor.action(replaceRange(markdown || '', range));
  } else {
    editor.action(insert(markdown || ''));
  }
  const next = getMarkdownInternal();
  lastMarkdown = next;
  lastSelectionRange = null;
  post('markdownChanged', { markdown: next });
};

const insertMarkdownInternal = (markdown) => {
  ensureEditor();
  const range = editorSelectionRange();
  const insertion = normalizeMarkdownInsertion(markdown);
  if (range) {
    editor.action(replaceRange(insertion, range));
  } else {
    editor.action(insert(insertion));
  }
  if (!placeCursorAtInsertionMarker()) {
    collapseSelectionToEnd();
  }
  const next = getMarkdownInternal();
  lastMarkdown = next;
  lastSelectionRange = null;
  post('markdownChanged', { markdown: next });
};

const selectFirstTextForCheck = (needle) => {
  ensureEditor();
  if (!window.weiBeiEditorCheckMode || !needle) return false;
  return editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    let range = null;
    view.state.doc.descendants((node, pos) => {
      if (!node.isText || range) return true;
      const index = (node.text || '').indexOf(needle);
      if (index < 0) return true;
      range = { from: pos + index, to: pos + index + needle.length };
      return false;
    });
    if (!range) return false;
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, range.from, range.to)));
    lastSelectionRange = range;
    return true;
  });
};

const typeTextForCheck = (text) => {
  ensureEditor();
  if (!window.weiBeiEditorCheckMode) return false;
  return editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.focus();
    for (const character of String(text || '')) {
      const { from, to } = view.state.selection;
      let handled = false;
      view.someProp('handleTextInput', (handler) => {
        if (handled) return true;
        handled = handler(view, from, to, character) === true;
        return handled;
      });
      if (!handled) {
        view.dispatch(view.state.tr.insertText(character, from, to));
      }
    }
    return true;
  });
};

window.WeiBeiEditor = {
  getMarkdown: getMarkdownInternal,
  setMarkdown: setMarkdownInternal,
  replaceSelection: (markdown) => {
    try {
      replaceSelectionInternal(markdown);
    } catch (error) {
      showFailure(error);
    }
  },
  applyAgentPatch: (markdown) => {
    try {
      const current = getMarkdownInternal();
      setMarkdownInternal(`${current.trimEnd()}\n\n${markdown || ''}\n`);
      const next = getMarkdownInternal();
      lastMarkdown = next;
      post('markdownChanged', { markdown: next });
    } catch (error) {
      showFailure(error);
    }
  },
  askAgentWithSelection: () => {
    lastSelectionRange = editorSelectionRange() || lastSelectionRange;
    const text = selectedText();
    post('askAgentWithSelection', { text, rect: rectFromSelection() });
  },
  insertMarkdownImage: (markdown) => {
    try {
      replaceSelectionInternal(markdown);
    } catch (error) {
      showFailure(error);
    }
  },
  insertMarkdown: (markdown) => {
    try {
      insertMarkdownInternal(markdown);
    } catch (error) {
      showFailure(error);
    }
  },
  resolveAttachment: (id, src, alt) => {
    const pending = pendingAttachments.get(id);
    if (!pending) return;
    pendingAttachments.delete(id);
    pending.resolve({ src, alt });
  },
  rejectAttachment: (id, message) => {
    const pending = pendingAttachments.get(id);
    if (!pending) return;
    pendingAttachments.delete(id);
    pending.reject(new Error(message || 'Attachment save failed'));
  },
  setEditable: (next) => {
    isEditable = next !== false;
    syncEditableState();
  },
  setDocumentID: (next) => {
    currentDocumentID = next || '';
  },
  setMarkdownBaseURL: (next) => {
    markdownBaseURL = next || '';
    refreshRenderedImages();
  },
  setTheme: (next) => {
    applyTheme(next);
    document.querySelectorAll('img[data-weibei-image-placeholder="true"]').forEach((image) => {
      image.setAttribute('src', missingImageURL());
    });
    if (!editor) return;
    editor.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      view.dispatch(view.state.tr.setMeta('weibeiThemeChanged', currentTheme));
    });
  },
  setInterfaceLanguage: (next) => {
    currentLanguage = normalizeInterfaceLanguage(next);
    document.documentElement.dataset.weibeiLanguage = currentLanguage;
    if (!editor) return;
    editor.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      view.dispatch(view.state.tr.setMeta('weibeiLanguageChanged', currentLanguage));
    });
  },
};

if (window.weiBeiEditorCheckMode) {
  window.WeiBeiEditor.selectFirstTextForCheck = selectFirstTextForCheck;
  window.WeiBeiEditor.selectedTextForCheck = editorSelectedText;
  window.WeiBeiEditor.typeTextForCheck = typeTextForCheck;
}

const initialDocument = splitFrontmatter(window.initialMarkdown || '');
frontmatterBlock = initialDocument.frontmatter;

Editor
  .make()
  .config((ctx) => {
    ctx.set(rootCtx, document.querySelector('#editor'));
    ctx.set(defaultValueCtx, initialDocument.body);
    ctx.set(editorViewOptionsCtx, {
      editable: () => isEditable,
    });
    ctx.set(uploadConfig.key, {
      uploader: localImageUploader,
      enableHtmlFileUploader: true,
      uploadWidgetFactory: (pos, spec) => {
        const widget = document.createElement('span');
        widget.className = 'weibei-uploading';
        widget.textContent = '正在收纳图片...';
        return Decoration.widget(pos, widget, spec);
      },
    });
    ctx.set(katexOptionsCtx.key, {
      throwOnError: false,
      strict: false,
      trust: false,
    });
  })
  .use(commonmark)
  .use(gfm)
  .use(math)
  .use(upload)
  .use(weiBeiDialectPlugin)
  .use(listener)
  .config((ctx) => {
    ctx.get(listenerCtx).markdownUpdated((_, markdown) => {
      const normalizedMarkdown = withFrontmatter(markdown);
      if (normalizedMarkdown === lastMarkdown) return;
      lastMarkdown = normalizedMarkdown;
      post('markdownChanged', { markdown: normalizedMarkdown });
    });
    ctx.get(listenerCtx).selectionUpdated(() => {
      requestAnimationFrame(reportSelection);
    });
  })
  .create()
  .then((created) => {
    editor = created;
    syncEditableState();
    installQuietScrollIndicators();
    document.querySelector('#editor-status')?.remove();
    lastMarkdown = getMarkdownInternal();
    document.addEventListener('mouseup', reportSelection);
    document.addEventListener('click', (event) => {
      if (!activateWikiLink(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
    }, true);
    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      if (!activateWikiLink(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
    }, true);
    document.addEventListener('keyup', (event) => {
      reportSelection();
    });
    post('editorReady', { markdown: lastMarkdown });
  })
  .catch(showFailure);
