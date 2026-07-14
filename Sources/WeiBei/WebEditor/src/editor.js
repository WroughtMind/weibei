import { Editor, defaultValueCtx, editorViewCtx, editorViewOptionsCtx, rootCtx } from '@milkdown/kit/core';
import { commonmark } from '@milkdown/kit/preset/commonmark';
import { gfm } from '@milkdown/kit/preset/gfm';
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener';
import { readImageAsBase64, upload, uploadConfig } from '@milkdown/kit/plugin/upload';
import { Plugin, TextSelection } from '@milkdown/kit/prose/state';
import { liftListItem } from '@milkdown/kit/prose/schema-list';
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
const isCompactPreview = window.weiBeiMarkdownCompactPreview === true;
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
const editorLabels = {
  'zh-Hans': {
    properties: '属性',
    bootFailed: 'Milkdown 初始化失败',
    imageMissing: '图片未找到',
    inlineFootnote: '行内脚注：{value}',
    openOrCreateNote: '打开或创建笔记：{value}',
    openSource: '打开来源：{value}',
    interactiveQuiz: '问答',
    interactiveReveal: '揭晓',
    interactivePrevious: '上一步',
    interactiveNext: '下一步',
    interactiveReset: '重来',
    interactiveCheck: '检查',
    interactiveRevealAll: '全部展开',
    interactiveAgain: '再练一次',
    interactiveKnow: '已经掌握',
    interactiveAll: '全部',
    interactiveSupport: '支持',
    interactiveChallenge: '反例',
    interactiveGap: '缺口',
    interactiveNoOutcome: '继续切换条件，观察可核对的结果。',
    interactiveStatusCorrect: '核对正确，可以继续说明理由。',
    interactiveStatusRetry: '这一项还未对上，保留现场继续核对。',
    interactiveStatusFamiliar: '已标为本轮熟悉，不等同于长期掌握。',
    interactiveStatusReview: '已放回复习队列，稍后再练。',
    interactiveStatusReset: '已回到起始状态。',
    interactiveStatusRevealed: '内容已展开，可以继续核对。',
    interactiveStatusCollapsed: '内容已收起。',
    interactiveStatusLocked: '已固定当前观察，再次点击可取消。',
    interactiveStatusUnlocked: '已取消固定，悬停可继续查看。',
    interactiveStatusUpdated: '当前观察已更新。',
    interactiveChartHint: '悬停图形查看细节，点击可固定。',
    embed: '嵌入：{value}',
    mermaidRendering: '正在渲染 Mermaid 图表...',
    mermaidFailed: 'Mermaid 图表未解析\n{value}',
    mathError: '公式没有通过 KaTeX 解析。常用写法：x_i、x^{2}、\\frac{a}{b}、\\begin{bmatrix}...\\end{bmatrix}',
    uploadingImage: '正在收纳图片...',
  },
  en: {
    properties: 'Properties',
    bootFailed: 'Milkdown failed to initialize',
    imageMissing: 'Image not found',
    inlineFootnote: 'Inline footnote: {value}',
    openOrCreateNote: 'Open or create note: {value}',
    openSource: 'Open source: {value}',
    interactiveQuiz: 'Quiz',
    interactiveReveal: 'Reveal',
    interactivePrevious: 'Previous',
    interactiveNext: 'Next',
    interactiveReset: 'Reset',
    interactiveCheck: 'Check',
    interactiveRevealAll: 'Reveal all',
    interactiveAgain: 'Again',
    interactiveKnow: 'Know it',
    interactiveAll: 'All',
    interactiveSupport: 'Support',
    interactiveChallenge: 'Challenge',
    interactiveGap: 'Gap',
    interactiveNoOutcome: 'Keep changing the conditions to inspect a grounded outcome.',
    interactiveStatusCorrect: 'Correct. Continue by explaining why.',
    interactiveStatusRetry: 'Not aligned yet. Keep the current state and check again.',
    interactiveStatusFamiliar: 'Marked familiar for this turn, not as long-term mastery.',
    interactiveStatusReview: 'Added back to review for another attempt.',
    interactiveStatusReset: 'Returned to the starting state.',
    interactiveStatusRevealed: 'Content revealed for closer checking.',
    interactiveStatusCollapsed: 'Content collapsed.',
    interactiveStatusLocked: 'Observation pinned. Click again to release it.',
    interactiveStatusUnlocked: 'Observation released. Hover to continue inspecting.',
    interactiveStatusUpdated: 'The current observation has been updated.',
    interactiveChartHint: 'Hover for detail. Click a mark to pin it.',
    embed: 'Embed: {value}',
    mermaidRendering: 'Rendering Mermaid diagram...',
    mermaidFailed: 'Mermaid diagram did not parse\n{value}',
    mathError: 'KaTeX could not parse this formula. Common forms: x_i, x^{2}, \\frac{a}{b}, \\begin{bmatrix}...\\end{bmatrix}',
    uploadingImage: 'Saving image...',
  },
};
const editorLabel = (key, values = {}) => {
  let text = editorLabels[currentLanguage]?.[key] || editorLabels['zh-Hans'][key] || key;
  for (const [name, value] of Object.entries(values)) {
    text = text.split(`{${name}}`).join(String(value));
  }
  return text;
};
const frontmatterLabel = () => editorLabel('properties');
const calloutRegex = new RegExp(`^${calloutPrefixPattern}\\\\?\\[!(${calloutTypePattern})\\]([+-]?)(?:[ \\t]+([^\\n]+))?`, 'i');
const calloutMarkerRegex = new RegExp(`^${calloutPrefixPattern}\\\\?\\[!(?:${calloutTypePattern})\\][+-]?\\s*`, 'i');
const calloutHeadingRegex = new RegExp(`^${calloutPrefixPattern}\\\\?\\[!(?:${calloutTypePattern})\\][+-]?(?:[ \\t]+[^\\n]+)?$`, 'i');
const selectedTextCalloutControlRegex = new RegExp(`(^|\\n)\\s*(?:>\\s*)*\\\\?\\[!(?:${calloutTypePattern})\\][+-]?[ \\t]*`, 'gi');
const htmlBreakPattern = /<br\s*\/?>/gi;
const MAX_SOURCE_REFERENCE_LENGTH = 300;
const sourceBracketKinds = new Set(['材料', '笔记', '选区', 'material', 'note', 'selection']);
const sourceBracketRegex = /(^|[^\[])\[((材料|笔记|选区|material|note|selection)[:：]([^\]\n]{1,300}))\]/gi;
const MAX_INTERACTIVE_SOURCE_LENGTH = 5000;
const MAX_INTERACTIVE_STRING_LENGTH = 700;
const MAX_INTERACTIVE_CONTENT_LENGTH = 1200;
const MAX_INTERACTIVE_OPTIONS = 6;
const MAX_INTERACTIVE_OPTION_LENGTH = 120;
const MAX_INTERACTIVE_SERIES = 4;
const MAX_INTERACTIVE_POINTS = 80;
const MAX_INTERACTIVE_CONTROLS = 4;
const MAX_INTERACTIVE_CATEGORIES = 12;
const MAX_INTERACTIVE_VARIANTS = 4;
const MAX_INTERACTIVE_COLORS = 8;
const MAX_INTERACTIVE_METRICS = 4;
const MAX_INTERACTIVE_BOARD_ITEMS = 6;
const MAX_INTERACTIVE_MAP_NODES = 7;
const MAX_INTERACTIVE_MAP_EDGES = 10;
const MAX_INTERACTIVE_TIMELINE_EVENTS = 8;
const MAX_INTERACTIVE_MATRIX_COLUMNS = 4;
const MAX_INTERACTIVE_MATRIX_ROWS = 6;
const MAX_INTERACTIVE_ANNOTATIONS = 8;
const MAX_INTERACTIVE_DERIVATION_STEPS = 8;
const MAX_INTERACTIVE_FLASHCARDS = 10;
const MAX_INTERACTIVE_SEQUENCE_ITEMS = 8;
const MAX_INTERACTIVE_SCENARIO_CONTROLS = 3;
const MAX_INTERACTIVE_SCENARIO_OPTIONS = 4;
const MAX_INTERACTIVE_SCENARIO_OUTCOMES = 16;
const MAX_INTERACTIVE_EVIDENCE_ITEMS = 10;
const MAX_INTERACTIVE_SPECTRUM_POINTS = 8;
const MAX_INTERACTIVE_DECISION_NODES = 10;
const MAX_INTERACTIVE_DECISION_CHOICES = 4;
const MAX_INTERACTIVE_UNIT_VARIABLES = 8;
const MAX_INTERACTIVE_UNIT_CHECKS = 6;
const MAX_INTERACTIVE_REACTION_SPECIES = 10;
const MAX_INTERACTIVE_REACTION_ELEMENTS = 12;
const MAX_INTERACTIVE_ALGORITHM_LINES = 12;
const MAX_INTERACTIVE_ALGORITHM_STEPS = 12;
const MAX_INTERACTIVE_LANGUAGE_PAIRS = 8;
const MAX_INTERACTIVE_ARGUMENT_NODES = 10;
const MAX_INTERACTIVE_ARGUMENT_EDGES = 12;
const MAX_INTERACTIVE_VISUAL_ZONES = 8;
const MAX_INTERACTIVE_VISUAL_LENSES = 5;
const MAX_INTERACTIVE_SPATIAL_LAYERS = 5;
const MAX_INTERACTIVE_SPATIAL_FEATURES = 10;
const MAX_INTERACTIVE_SPATIAL_POINTS = 12;
const MAX_INTERACTIVE_PATHWAY_STATES = 8;
const MAX_INTERACTIVE_SOURCES = 4;
const MAX_INTERACTIVE_NUMBER = 1000000;
const INTERACTIVE_PROTOCOL_VERSION = 1;
const interactiveToneNames = new Set(['cinnabar', 'ochre', 'moss', 'blue-ink', 'violet-ink', 'ink']);
const interactiveTreatments = new Set(['editorial', 'annotated', 'compact', 'outline']);
const interactiveStudyBoardLayouts = new Set(['lanes', 'grid', 'sequence']);
const interactiveRelationshipLayouts = new Set(['radial', 'flow']);
const interactiveToneColors = {
  cinnabar: '#91261C',
  ochre: '#77582F',
  moss: '#395F48',
  'blue-ink': '#31566B',
  'violet-ink': '#5D4B6D',
  ink: '#1D1814',
};
const interactiveInkstoneToneColors = {
  cinnabar: '#C95B50',
  ochre: '#C7A16A',
  moss: '#8FB08F',
  'blue-ink': '#8FAEC0',
  'violet-ink': '#B7A0C6',
  ink: '#D7CBB0',
};
const interactiveFunctionFamilies = {
  linear: (x, values) => (values.a ?? 1) * x + (values.b ?? 0),
  quadratic: (x, values) => (values.a ?? 1) * ((x - (values.h ?? 0)) ** 2) + (values.k ?? 0),
  exponential: (x, values) => (values.a ?? 1) * Math.exp((values.b ?? 1) * x) + (values.c ?? 0),
  logistic: (x, values) => (values.L ?? 1) / (1 + Math.exp(-1 * (values.k ?? 1) * (x - (values.x0 ?? 0)))) + (values.c ?? 0),
  inverse: (x, values) => {
    const distance = x - (values.h ?? 0);
    if (Math.abs(distance) < 0.001) return null;
    return (values.a ?? 1) / distance + (values.k ?? 0);
  },
};
const interactiveFunctionParameterKeys = {
  linear: new Set(['a', 'b']),
  quadratic: new Set(['a', 'h', 'k']),
  exponential: new Set(['a', 'b', 'c']),
  logistic: new Set(['L', 'k', 'x0', 'c']),
  inverse: new Set(['a', 'h', 'k']),
};
const cleanSelectedText = (text) => String(text || '')
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
  root.innerHTML = `<pre style="white-space:pre-wrap;color:#9f3427;padding:24px;font:13px/1.5 SFMono-Regular,Menlo,monospace;">${editorLabel('bootFailed')}\n${String(error?.stack || error)}</pre>`;
};

window.addEventListener('error', (event) => showFailure(event.error || event.message));
window.addEventListener('unhandledrejection', (event) => showFailure(event.reason));

const post = (name, body = {}) => {
  bridge?.[name]?.postMessage({ ...body, documentID: currentDocumentID });
};

document.documentElement.dataset.weibeiCompactPreview = isCompactPreview ? 'true' : 'false';

let contentHeightFrame = 0;
let lastReportedContentHeight = 0;

const publishContentHeight = () => {
  const editorRoot = document.querySelector('#editor');
  const milkdownRoot = document.querySelector('.milkdown');
  const proseMirror = document.querySelector('.ProseMirror');
  const rootTop = editorRoot?.getBoundingClientRect().top || 0;
  const contentBottom = Array.from(proseMirror?.children || []).reduce(
    (maximum, child) => Math.max(maximum, child.getBoundingClientRect().bottom),
    rootTop
  );
  const geometryHeight = Math.max(0, contentBottom - rootTop);
  const height = Math.ceil(Math.max(
    1,
    editorRoot?.scrollHeight || 0,
    milkdownRoot?.scrollHeight || 0,
    proseMirror?.scrollHeight || 0,
    document.body?.scrollHeight || 0,
    document.documentElement?.scrollHeight || 0,
    geometryHeight
  ));
  if (Math.abs(height - lastReportedContentHeight) < 1) return;
  lastReportedContentHeight = height;
  post('contentHeightChanged', { height });
};

const reportContentHeight = () => {
  if (!isCompactPreview) return;
  publishContentHeight();
  window.cancelAnimationFrame(contentHeightFrame);
  contentHeightFrame = window.requestAnimationFrame(publishContentHeight);
};

const installContentHeightObserver = () => {
  if (!isCompactPreview) return;
  const editorRoot = document.querySelector('#editor');
  const milkdownRoot = document.querySelector('.milkdown');
  const proseMirror = document.querySelector('.ProseMirror');
  if (window.ResizeObserver) {
    const observer = new ResizeObserver(reportContentHeight);
    if (editorRoot) observer.observe(editorRoot);
    if (milkdownRoot) observer.observe(milkdownRoot);
    if (proseMirror) observer.observe(proseMirror);
  }
  if (proseMirror && window.MutationObserver) {
    const mutationObserver = new MutationObserver(reportContentHeight);
    mutationObserver.observe(proseMirror, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'hidden', 'style'],
    });
  }
  reportContentHeight();
  window.setTimeout(reportContentHeight, 80);
  window.setTimeout(reportContentHeight, 260);
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

const isEscapedMarkdownPosition = (source, index) => {
  let slashCount = 0;
  for (let cursor = index - 1; cursor >= 0 && source[cursor] === '\\'; cursor -= 1) {
    slashCount += 1;
  }
  return slashCount % 2 === 1;
};

const findUnescapedMarkdownMarker = (source, marker, from) => {
  let index = source.indexOf(marker, from);
  while (index >= 0 && isEscapedMarkdownPosition(source, index)) {
    index = source.indexOf(marker, index + marker.length);
  }
  return index;
};

const mapMarkdownOutsideBackticks = (line, transform) => {
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

const normalizeMarkdownOutputSegment = (text) => String(text || '')
  .replace(/\\\[\\\[/g, '[[')
  .replace(/\\\]\\\]/g, ']]')
  .replace(/\\=\\=([^=\n]+?)\\=\\=/g, '==$1==')
  .replace(/\^\\\[/g, '^[')
  .replace(/(^|\s)\\#(?=[\p{L}\p{N}_/-])/gu, '$1#')
  .replace(/\\\$(?=\d)/g, '$')
  .replace(new RegExp(`^(\\s*(?:>\\s*)*)\\\\(\\[!(?:${calloutTypePattern})\\])`, 'gim'), '$1$2');

const mapMarkdownOutsideCode = (markdown, transform) => {
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
const normalizeMarkdownOutput = (markdown) => mapMarkdownOutsideCode(markdown, normalizeMarkdownOutputSegment);

const normalizeHtmlBreaksInLine = (line) => String(line || '').replace(/<br\s*\/?>[ \t]*/gi, '  \n');

const normalizeHtmlBreaks = (markdown) => mapMarkdownOutsideCode(markdown, normalizeHtmlBreaksInLine);

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
    ? `<div class="frontmatter-title">${frontmatterLabel()}</div>${rows.map((row) => (
      `<div class="frontmatter-row"><span class="frontmatter-key">${escapeHTML(row.key)}</span><span>${escapeHTML(row.value)}</span></div>`
    )).join('')}`
    : '';
};

const escapeHTML = (value) => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

const safeInteractiveString = (value, maxLength = MAX_INTERACTIVE_STRING_LENGTH) => {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  if (!text || text.length > maxLength) return null;
  return text;
};

const safeOptionalInteractiveString = (value, maxLength = MAX_INTERACTIVE_STRING_LENGTH) => {
  if (value === undefined || value === null) return '';
  return safeInteractiveString(value, maxLength);
};

const safeInteractiveNumber = (value, min = -MAX_INTERACTIVE_NUMBER, max = MAX_INTERACTIVE_NUMBER) => {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  if (value < min || value > max) return null;
  return value;
};

const safeInteractiveInteger = (value, min, max) => (
  Number.isInteger(value) && value >= min && value <= max ? value : null
);

const safeInteractiveArray = (value, maxLength) => {
  if (!Array.isArray(value) || value.length > maxLength) return null;
  return value;
};

const safeInteractiveTone = (value, fallback = 'cinnabar') => (
  typeof value === 'string' && interactiveToneNames.has(value) ? value : fallback
);

const safeInteractiveTreatment = (value) => (
  typeof value === 'string' && interactiveTreatments.has(value) ? value : null
);

const safeOptionalInteractiveTone = (value, fallback = 'cinnabar') => {
  if (value === undefined) return fallback;
  return safeInteractiveTone(value, null);
};

const safeOptionalInteractiveTreatment = (value, fallback = 'compact') => {
  if (value === undefined) return fallback;
  return safeInteractiveTreatment(value);
};

const safeInteractiveStudyBoardLayout = (value) => (
  typeof value === 'string' && interactiveStudyBoardLayouts.has(value) ? value : null
);

const safeInteractiveRelationshipLayout = (value) => (
  typeof value === 'string' && interactiveRelationshipLayouts.has(value) ? value : null
);

const safeInteractiveHex = (value) => {
  if (typeof value !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(value.trim())) return null;
  return value.trim().toUpperCase();
};

const interactiveHexTextColor = (hex) => {
  const value = hex.replace('#', '');
  const red = parseInt(value.slice(0, 2), 16);
  const green = parseInt(value.slice(2, 4), 16);
  const blue = parseInt(value.slice(4, 6), 16);
  const luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255;
  return luminance > 0.58 ? '#1D1814' : '#FFFFFF';
};

const interactiveToneColor = (tone) => {
  const name = safeInteractiveTone(tone, 'ink');
  const palette = currentTheme === 'inkstone' ? interactiveInkstoneToneColors : interactiveToneColors;
  return palette[name] || palette.ink;
};

const safeInteractiveSources = (value) => {
  const rawSources = value.sources === undefined
    ? (value.source === undefined ? [] : [value.source])
    : safeInteractiveArray(value.sources, MAX_INTERACTIVE_SOURCES);
  if (!rawSources) return null;
  const sources = rawSources.map((source) => safeInteractiveString(source, MAX_SOURCE_REFERENCE_LENGTH));
  if (sources.some((source) => source === null)) return null;
  return sources.filter(Boolean);
};

const safeInteractiveDomain = (value, fallback) => {
  if (value === undefined) return fallback;
  if (!Array.isArray(value) || value.length !== 2) return null;
  const min = safeInteractiveNumber(value[0]);
  const max = safeInteractiveNumber(value[1]);
  if (min === null || max === null || min >= max) return null;
  return [min, max];
};

const safeInteractivePoint = (value) => {
  const x = Array.isArray(value) ? value[0] : value?.x;
  const y = Array.isArray(value) ? value[1] : value?.y;
  const safeX = safeInteractiveNumber(x);
  const safeY = safeInteractiveNumber(y);
  if (safeX === null || safeY === null) return null;
  return { x: safeX, y: safeY };
};

const safeInteractiveChartPoint = (value) => {
  const rawX = Array.isArray(value) ? value[0] : value?.x;
  const safeY = safeInteractiveNumber(Array.isArray(value) ? value[1] : value?.y);
  if (safeY === null) return null;
  if (typeof rawX === 'string') {
    const label = safeInteractiveString(rawX, 40);
    return label ? { x: label, y: safeY } : null;
  }
  const safeX = safeInteractiveNumber(rawX);
  if (safeX === null) return null;
  return { x: safeX, y: safeY };
};

const safeInteractivePoints = (value, minLength = 2) => {
  const points = safeInteractiveArray(value, MAX_INTERACTIVE_POINTS);
  if (!points || points.length < minLength) return null;
  const parsed = points.map(safeInteractivePoint);
  if (parsed.some((point) => !point)) return null;
  return parsed;
};

const safeInteractiveChartPoints = (value, minLength = 1) => {
  const points = safeInteractiveArray(value, MAX_INTERACTIVE_POINTS);
  if (!points || points.length < minLength) return null;
  const parsed = points.map(safeInteractiveChartPoint);
  if (parsed.some((point) => !point)) return null;
  return parsed;
};

const safeInteractiveID = (value) => {
  const id = safeInteractiveString(value, 48);
  return id && /^[A-Za-z0-9_-]+$/.test(id) ? id : null;
};

const safeInteractiveEnum = (value, allowed) => (
  typeof value === 'string' && allowed.has(value) ? value : null
);

const safeInteractivePercent = (value) => safeInteractiveNumber(value, 0, 100);

const safeInteractivePercentPoint = (value) => {
  const x = safeInteractivePercent(Array.isArray(value) ? value[0] : value?.x);
  const y = safeInteractivePercent(Array.isArray(value) ? value[1] : value?.y);
  return x !== null && y !== null ? { x, y } : null;
};

const safeInteractivePercentPoints = (value, maxLength, minLength = 1) => {
  const rawPoints = safeInteractiveArray(value, maxLength);
  if (!rawPoints || rawPoints.length < minLength) return null;
  const points = rawPoints.map(safeInteractivePercentPoint);
  return points.some((point) => !point) ? null : points;
};

const safeInteractiveAtoms = (value) => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const atoms = {};
  const entries = Object.entries(value);
  if (entries.length < 1 || entries.length > MAX_INTERACTIVE_REACTION_ELEMENTS) return null;
  for (const [rawElement, rawCount] of entries) {
    const element = safeInteractiveString(rawElement, 4);
    const count = safeInteractiveInteger(rawCount, 1, 99);
    if (!element || !/^[A-Z][a-z]?$/.test(element) || count === null || atoms[element]) return null;
    atoms[element] = count;
  }
  return atoms;
};

const hasUnsafeInteractiveVisualPayload = (value, depth = 0) => {
  if (depth > 4) return true;
  if (typeof value === 'string') {
    return /https?:\/\/|<\s*\/?\s*(?:html|script|style|iframe|img|svg)\b/i.test(value);
  }
  if (Array.isArray(value)) {
    return value.some((item) => hasUnsafeInteractiveVisualPayload(item, depth + 1));
  }
  if (!value || typeof value !== 'object') return false;
  return Object.entries(value).some(([key, child]) => (
    /^(?:url|src|html|markup|svg|iframe|image|imageurl)$/i.test(key)
      || hasUnsafeInteractiveVisualPayload(child, depth + 1)
  ));
};

const normalizeChartSeries = (series) => {
  const hasCategoryX = series.some((item) => item.points.some((point) => typeof point.x === 'string'));
  const hasNumberX = series.some((item) => item.points.some((point) => typeof point.x === 'number'));
  if (hasCategoryX && hasNumberX) return null;
  if (!hasCategoryX) {
    return {
      xMode: 'number',
      categories: [],
      series: series.map((item) => ({
        ...item,
        points: item.points.map((point) => ({ ...point, plotX: point.x })),
      })),
    };
  }
  const categories = [];
  const categoryIndex = new Map();
  series.forEach((item) => {
    item.points.forEach((point) => {
      if (categoryIndex.has(point.x)) return;
      categoryIndex.set(point.x, categories.length);
      categories.push(point.x);
    });
  });
  if (categories.length < 1 || categories.length > MAX_INTERACTIVE_POINTS) return null;
  return {
    xMode: 'category',
    categories,
    series: series.map((item) => ({
      ...item,
      points: item.points.map((point) => ({ ...point, plotX: categoryIndex.get(point.x) })),
    })),
  };
};

const extentForPoints = (pointGroups, key, fallback) => {
  const values = pointGroups.flatMap((points) => points.map((point) => point[key]));
  if (values.length < 1) return fallback;
  let min = Math.min(...values);
  let max = Math.max(...values);
  if (!Number.isFinite(min) || !Number.isFinite(max)) return fallback;
  if (min === max) {
    min -= 1;
    max += 1;
  }
  const pad = (max - min) * 0.08;
  return [min - pad, max + pad];
};

const yExtentForChart = (pointGroups, chartType) => {
  const values = pointGroups.flatMap((points) => points.map((point) => point.y));
  if (chartType === 'bar') values.push(0);
  if (values.length < 1) return [0, 1];
  let min = Math.min(...values);
  let max = Math.max(...values);
  if (!Number.isFinite(min) || !Number.isFinite(max)) return [0, 1];
  if (min === max) {
    min -= 1;
    max += 1;
  }
  const pad = (max - min) * 0.08;
  return [min - pad, max + pad];
};

const canonicalSourceReference = (value) => {
  const text = safeInteractiveString(value, MAX_SOURCE_REFERENCE_LENGTH);
  if (!text) return '';
  const match = text.match(/^(来源：|Source:|材料[:：]|笔记[:：]|选区[:：]|Material:|Note:|Selection:)\s*(.+)$/i);
  if (!match) return `来源：${text}`;
  return `来源：${match[2].trim()}`;
};

const sourceReferenceTitle = (value) => {
  const reference = canonicalSourceReference(value);
  return reference.startsWith('来源：') ? reference.slice('来源：'.length).trim() : reference;
};

const setSourceReferenceAttributes = (element, source) => {
  const reference = canonicalSourceReference(source);
  if (!reference) return false;
  element.dataset.sourceReference = reference;
  element.setAttribute('title', editorLabel('openSource', { value: sourceReferenceTitle(source) }));
  return true;
};

const stableInteractiveID = (value) => {
  let hash = 2166136261;
  const text = String(value || '');
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `block-${(hash >>> 0).toString(16)}`;
};

const parseWeiBeiInteractiveBlock = (source) => {
  const raw = String(source || '').trim();
  if (!raw || raw.length > MAX_INTERACTIVE_SOURCE_LENGTH) return null;
  let value;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  if (value.version !== undefined && value.version !== INTERACTIVE_PROTOCOL_VERSION) return null;
  const kind = value.kind;
  const entry = typeof kind === 'string' ? weiBeiInteractiveRegistry[kind] : null;
  const model = entry?.parse(value) || null;
  if (!model) return null;
  model.blockId = safeOptionalInteractiveString(value.blockId, 120) || stableInteractiveID(raw);
  return model;
};

const appendTextElement = (parent, tag, className, text) => {
  const element = document.createElement(tag);
  if (className) element.className = className;
  element.textContent = text;
  parent.appendChild(element);
  return element;
};

const sourceReferenceElement = (source) => {
  if (!source) return null;
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'weibei-source-reference weibei-interactive-source-link';
  button.textContent = source;
  if (!setSourceReferenceAttributes(button, source)) return null;
  return button;
};

const appendInteractiveSource = (parent, source) => {
  const link = sourceReferenceElement(source);
  if (!link) return;
  const row = document.createElement('div');
  row.className = 'weibei-interactive-source-row';
  row.appendChild(link);
  parent.appendChild(row);
};

const appendInteractiveSources = (parent, sources) => {
  if (isCompactPreview) return;
  const safeSources = Array.isArray(sources) ? sources.slice(0, MAX_INTERACTIVE_SOURCES) : [];
  safeSources.forEach((source) => appendInteractiveSource(parent, source));
};

const interactiveKindFamilies = {
  quiz: 'practice',
  reveal: 'reading',
  chart: 'atlas',
  'function-plot': 'lab',
  'parameter-lab': 'lab',
  'text-study': 'reading',
  'design-compare': 'atlas',
  palette: 'atlas',
  'study-board': 'planning',
  'relationship-map': 'reasoning',
  timeline: 'reasoning',
  'comparison-matrix': 'reasoning',
  'annotated-passage': 'reading',
  'derivation-steps': 'reasoning',
  flashcards: 'practice',
  'sequence-builder': 'practice',
  'scenario-lab': 'lab',
  'evidence-board': 'reasoning',
  spectrum: 'reasoning',
  'decision-path': 'reasoning',
  'unit-workbench': 'lab',
  'reaction-balance': 'lab',
  'algorithm-trace': 'lab',
  'language-aligner': 'reading',
  'argument-map': 'reasoning',
  'visual-analysis': 'atlas',
  'spatial-layers': 'atlas',
  'pathway-lab': 'lab',
};

const configureWeiBeiInteractiveRoot = (root, kind) => {
  root.dataset.kind = kind;
  root.dataset.family = interactiveKindFamilies[kind] || 'reading';
  root.dataset.interactionState = root.dataset.interactionState || 'idle';
  root.setAttribute('role', 'group');
};

const ensureInteractiveStatus = (root) => {
  let status = root.querySelector(':scope > .weibei-interactive-status');
  if (status) return status;
  status = document.createElement('div');
  status.className = 'weibei-interactive-status';
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  status.hidden = true;
  root.appendChild(status);
  return status;
};

const interactiveStatusForAction = (action, payload) => {
  if (action === 'answer' || action === 'check-order') {
    return payload?.correct ? ['correct', 'interactiveStatusCorrect'] : ['retry', 'interactiveStatusRetry'];
  }
  if (action === 'mark-known') return ['familiar', 'interactiveStatusFamiliar'];
  if (action === 'mark-again') return ['review', 'interactiveStatusReview'];
  if (action.startsWith('reset')) return ['idle', 'interactiveStatusReset'];
  if (action === 'reveal' || action === 'reveal-step' || action === 'reveal-all') return ['active', 'interactiveStatusRevealed'];
  if (action === 'collapse') return ['idle', 'interactiveStatusCollapsed'];
  if (action === 'clear-focus' || action === 'clear-node' || action === 'clear-column' || action === 'clear-lens') {
    return ['idle', 'interactiveStatusReset'];
  }
  if (action === 'inspect-mark') {
    return payload?.locked === false
      ? ['idle', 'interactiveStatusUnlocked']
      : ['active', 'interactiveStatusLocked'];
  }
  return ['active', 'interactiveStatusUpdated'];
};

const updateInteractiveStatus = (root, action, payload) => {
  if (!root) return;
  const [state, label] = interactiveStatusForAction(action, payload);
  root.dataset.interactionState = state;
  const status = ensureInteractiveStatus(root);
  status.textContent = editorLabel(label);
  status.hidden = false;
};

const postInteractiveAction = (root, action, payload = {}, source = '') => {
  const safeAction = safeInteractiveString(action, 80);
  if (!safeAction) return;
  updateInteractiveStatus(root, safeAction, payload);
  let payloadJSON = '{}';
  try {
    payloadJSON = JSON.stringify(payload).slice(0, 1200);
  } catch {
    payloadJSON = '{}';
  }
  post('interactiveAction', {
    blockId: root?.dataset.blockId || '',
    kind: root?.dataset.kind || '',
    action: safeAction,
    detail: payloadJSON,
    source: canonicalSourceReference(source),
  });
};

const appendInlineSourceButton = (parent, source) => {
  const button = sourceReferenceElement(source);
  if (!button) return null;
  button.classList.add('weibei-interactive-inline-source');
  button.textContent = editorLabel('openSource', { value: sourceReferenceTitle(source) });
  parent.appendChild(button);
  return button;
};

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
  <text x="48" y="22" fill="${palette.text}" font-family="-apple-system, BlinkMacSystemFont, 'Songti SC', serif" font-size="13">${escapeHTML(editorLabel('imageMissing'))}</text>
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
      title: editorLabel('inlineFootnote', { value: content }),
      'aria-label': editorLabel('inlineFootnote', { value: content }),
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
        title: editorLabel('openOrCreateNote', { value: title }),
        'data-wikilink-target': parsed.target,
        'data-wikilink-title': bridgeTitle,
      });
      addRangeDecoration(decorations, from + 2 + parsed.aliasRange.end, to - 2, 'weibei-md-marker');
    } else {
      addRangeDecoration(decorations, from + 2, to - 2, 'weibei-wikilink', {
        role: 'link',
        tabindex: '0',
        title: editorLabel('openOrCreateNote', { value: title }),
        'data-wikilink-target': parsed.target,
        'data-wikilink-title': bridgeTitle,
      });
    }
    addRangeDecoration(decorations, to - 2, to, 'weibei-md-marker');
  }
};

const decorateSourceReferences = (decorations, text, pos) => {
  for (const match of text.matchAll(/(?:^|[\s`])((?:来源：|Source:)[^`\n]+)/g)) {
    const prefixLength = match[0].startsWith(match[1]) ? 0 : 1;
    const sourcePrefix = match[1].startsWith('来源：') ? '来源：' : 'Source:';
    const from = pos + (match.index || 0) + prefixLength;
    const to = from + match[1].length;
    addRangeDecoration(decorations, from, to, 'weibei-source-reference', {
      role: 'link',
      tabindex: '0',
      title: editorLabel('openSource', { value: match[1].slice(sourcePrefix.length).trim() }),
      'data-source-reference': match[1],
    });
  }
};

const decorateBracketSourceReferences = (decorations, text, pos) => {
  for (const match of text.matchAll(sourceBracketRegex)) {
    const prefixLength = match[1]?.length || 0;
    const label = match[2] || '';
    const kind = match[3] || '';
    if (!sourceBracketKinds.has(kind.toLowerCase())) continue;
    const from = pos + (match.index || 0) + prefixLength;
    const innerFrom = from + 1;
    const innerTo = innerFrom + label.length;
    const to = innerTo + 1;
    const reference = canonicalSourceReference(label);
    addRangeDecoration(decorations, from, innerFrom, 'weibei-md-marker');
    addRangeDecoration(decorations, innerFrom, innerTo, 'weibei-source-reference', {
      role: 'link',
      tabindex: '0',
      title: editorLabel('openSource', { value: sourceReferenceTitle(label) }),
      'data-source-kind': kind,
      'data-source-reference': reference,
    });
    addRangeDecoration(decorations, innerTo, to, 'weibei-md-marker');
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
      chip.textContent = editorLabel('embed', { value: embed.label || embed.target });
      chip.setAttribute('role', 'link');
      chip.setAttribute('tabindex', '0');
      chip.setAttribute('title', editorLabel('openOrCreateNote', { value: embed.target }));
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

const decorateHtmlBreaks = (decorations, text, pos) => {
  for (const match of text.matchAll(/<br\s*\/?>/gi)) {
    const from = pos + (match.index || 0);
    const to = from + match[0].length;
    addRangeDecoration(decorations, from, to, 'weibei-html-break-source');
    decorations.push(Decoration.widget(to, () => {
      const node = document.createElement('br');
      node.className = 'weibei-html-break-preview';
      return node;
    }, { side: 1 }));
  }
};

const mermaidWidget = (source) => {
  const container = document.createElement('div');
  container.className = 'weibei-mermaid-render';
  container.textContent = editorLabel('mermaidRendering');
  window.setTimeout(async () => {
    try {
      const id = `weibei-mermaid-${mermaidRenderID += 1}`;
      const { svg, bindFunctions } = await mermaid.render(id, source, container);
      container.innerHTML = svg;
      bindFunctions?.(container);
      container.dataset.rendered = 'true';
    } catch (error) {
      container.classList.add('weibei-mermaid-error');
      container.textContent = editorLabel('mermaidFailed', { value: String(error?.message || error) });
    }
  }, 0);
  return container;
};

const renderWeiBeiQuiz = (model) => {
  const root = document.createElement('div');
  root.className = 'weibei-interactive weibei-interactive-quiz';
  root.dataset.kind = 'quiz';
  appendTextElement(root, 'div', 'weibei-interactive-label', editorLabel('interactiveQuiz'));
  appendTextElement(root, 'div', 'weibei-interactive-prompt', model.prompt);
  const options = document.createElement('div');
  options.className = 'weibei-interactive-options';
  const explanation = appendTextElement(root, 'div', 'weibei-interactive-explanation', model.explanation);
  explanation.hidden = true;
  model.options.forEach((option, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-interactive-option';
    button.textContent = option;
    button.addEventListener('click', () => {
      options.querySelectorAll('.weibei-interactive-option').forEach((node) => {
        node.classList.remove('is-selected', 'is-correct', 'is-wrong');
        node.setAttribute('aria-pressed', 'false');
      });
      button.classList.add('is-selected', index === model.correctIndex ? 'is-correct' : 'is-wrong');
      button.setAttribute('aria-pressed', 'true');
      explanation.hidden = false;
      postInteractiveAction(root, 'answer', {
        optionIndex: index,
        correct: index === model.correctIndex,
      }, model.sources[0]);
      reportContentHeight();
    });
    options.appendChild(button);
  });
  root.insertBefore(options, explanation);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiReveal = (model) => {
  const root = document.createElement('div');
  root.className = 'weibei-interactive weibei-interactive-reveal';
  root.dataset.kind = 'reveal';
  const header = document.createElement('button');
  header.type = 'button';
  header.className = 'weibei-interactive-reveal-toggle';
  appendTextElement(header, 'span', 'weibei-interactive-label', editorLabel('interactiveReveal'));
  appendTextElement(header, 'span', 'weibei-interactive-title', model.title);
  const content = appendTextElement(root, 'div', 'weibei-interactive-reveal-content', model.content);
  content.hidden = true;
  header.addEventListener('click', () => {
    content.hidden = !content.hidden;
    header.setAttribute('aria-expanded', content.hidden ? 'false' : 'true');
    postInteractiveAction(root, content.hidden ? 'collapse' : 'reveal', {
      expanded: !content.hidden,
    }, model.sources[0]);
    reportContentHeight();
  });
  header.setAttribute('aria-expanded', 'false');
  root.insertBefore(header, content);
  appendInteractiveSources(root, model.sources);
  return root;
};

const createWeiBeiInteractiveRoot = (kind, className) => {
  const root = document.createElement('div');
  root.className = `weibei-interactive ${className}`;
  configureWeiBeiInteractiveRoot(root, kind);
  return root;
};

const createInteractiveSurface = (tag, className, source = '') => {
  const element = document.createElement(source ? 'button' : tag);
  if (source) {
    element.type = 'button';
    element.className = `${className} weibei-source-reference`;
    setSourceReferenceAttributes(element, source);
  } else {
    element.className = className;
  }
  return element;
};

const createSVGElement = (tag) => document.createElementNS('http://www.w3.org/2000/svg', tag);

const appendSVGElement = (parent, tag, attrs = {}, text = '') => {
  const element = createSVGElement(tag);
  Object.entries(attrs).forEach(([name, value]) => {
    if (value !== null && value !== undefined) element.setAttribute(name, String(value));
  });
  if (text) element.textContent = text;
  parent.appendChild(element);
  return element;
};

const appendSVGTitle = (element, text) => appendSVGElement(element, 'title', {}, text);

const chartPointLabel = (seriesName, point) => `${seriesName}：x ${point.x}，y ${formatChartTick(point.y)}`;

const chartSeriesLabel = (item) => {
  const first = item.points[0];
  const last = item.points.at(-1);
  return `${item.name}，共 ${item.points.length} 个点；从 x ${first.x}、y ${formatChartTick(first.y)} 到 x ${last.x}、y ${formatChartTick(last.y)}`;
};

const chartProjector = (xDomain, yDomain, width = 320, height = 180, pad = 26) => {
  const innerWidth = width - (pad * 2);
  const innerHeight = height - (pad * 2);
  return {
    width,
    height,
    pad,
    yDomainMin: yDomain[0],
    yDomainMax: yDomain[1],
    x: (value) => pad + ((value - xDomain[0]) / (xDomain[1] - xDomain[0])) * innerWidth,
    y: (value) => height - pad - ((value - yDomain[0]) / (yDomain[1] - yDomain[0])) * innerHeight,
  };
};

const pathForPoints = (points, project, xKey = 'x') => points
  .map((point, index) => `${index === 0 || point.breakBefore ? 'M' : 'L'}${project.x(point[xKey]).toFixed(2)} ${project.y(point.y).toFixed(2)}`)
  .join(' ');

const formatChartTick = (value) => {
  if (!Number.isFinite(value)) return '';
  if (Math.abs(value) >= 100) return value.toFixed(0);
  if (Math.abs(value) >= 10) return value.toFixed(1).replace(/\.0$/, '');
  return value.toFixed(2).replace(/\.?0+$/, '');
};

const chartTickValues = (domain, count = 4) => {
  const ticks = [];
  for (let index = 0; index < count; index += 1) {
    const ratio = count === 1 ? 0 : index / (count - 1);
    ticks.push(domain[0] + (domain[1] - domain[0]) * ratio);
  }
  return ticks;
};

const appendChartFrame = (root, xLabel, yLabel, xDomain, yDomain, options = {}) => {
  const svg = createSVGElement('svg');
  svg.classList.add('weibei-interactive-chart-svg');
  svg.setAttribute('viewBox', '0 0 320 180');
  svg.setAttribute('role', 'img');
  svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
  const project = chartProjector(xDomain, yDomain);
  const xTicks = options.xTickLabels
    ? options.xTickLabels.map((label, index) => ({ value: index, label }))
    : chartTickValues(xDomain, 4).map((value) => ({ value, label: formatChartTick(value) }));
  const yTicks = chartTickValues(yDomain, 4).map((value) => ({ value, label: formatChartTick(value) }));
  xTicks.forEach((tick) => {
    const x = project.x(tick.value);
    appendSVGElement(svg, 'line', { x1: x, y1: project.pad, x2: x, y2: project.height - project.pad, class: 'weibei-chart-grid' });
    appendSVGElement(svg, 'text', { x, y: project.height - 13, class: 'weibei-chart-tick-label', 'text-anchor': 'middle' }, tick.label);
  });
  yTicks.forEach((tick) => {
    const y = project.y(tick.value);
    appendSVGElement(svg, 'line', { x1: project.pad, y1: y, x2: project.width - project.pad, y2: y, class: 'weibei-chart-grid' });
    appendSVGElement(svg, 'text', { x: project.pad - 6, y: y + 3, class: 'weibei-chart-tick-label', 'text-anchor': 'end' }, tick.label);
  });
  appendSVGElement(svg, 'line', { x1: project.pad, y1: project.height - project.pad, x2: project.width - project.pad, y2: project.height - project.pad, class: 'weibei-chart-axis' });
  appendSVGElement(svg, 'line', { x1: project.pad, y1: project.pad, x2: project.pad, y2: project.height - project.pad, class: 'weibei-chart-axis' });
  appendSVGElement(svg, 'text', { x: project.width / 2, y: project.height - 7, class: 'weibei-interactive-axis-label', 'text-anchor': 'middle' }, xLabel);
  appendSVGElement(svg, 'text', { x: 10, y: 18, class: 'weibei-interactive-axis-label' }, yLabel);
  root.appendChild(svg);
  return { svg, project };
};

const appendChartLegend = (root, series) => {
  const legend = document.createElement('div');
  legend.className = 'weibei-chart-legend';
  series.forEach((item, seriesIndex) => {
    const legendItem = document.createElement('button');
    legendItem.type = 'button';
    legendItem.className = 'weibei-chart-legend-item';
    legendItem.setAttribute('aria-pressed', 'true');
    const swatch = document.createElement('span');
    swatch.className = 'weibei-chart-legend-swatch';
    swatch.style.backgroundColor = interactiveToneColor(item.tone);
    legendItem.appendChild(swatch);
    appendTextElement(legendItem, 'span', '', item.name);
    legendItem.addEventListener('click', () => {
      const visible = legendItem.getAttribute('aria-pressed') !== 'false';
      legendItem.setAttribute('aria-pressed', visible ? 'false' : 'true');
      root.querySelectorAll(`[data-series-index="${seriesIndex}"]`).forEach((mark) => {
        mark.classList.toggle('is-hidden-series', visible);
      });
      postInteractiveAction(root, 'toggle-series', {
        seriesIndex,
        name: item.name,
        visible: !visible,
      });
    });
    legend.appendChild(legendItem);
  });
  root.appendChild(legend);
};

const renderWeiBeiLineChart = (svg, project, series) => {
  series.forEach((item, seriesIndex) => {
    const path = appendSVGElement(svg, 'path', {
      d: pathForPoints(item.points, project, 'plotX'),
      class: 'weibei-chart-series weibei-chart-line',
      fill: 'none',
      stroke: interactiveToneColor(item.tone),
      role: 'img',
      tabindex: 0,
      'aria-label': chartSeriesLabel(item),
      'data-series-index': seriesIndex,
    });
    appendSVGTitle(path, chartSeriesLabel(item));
  });
};

const renderWeiBeiAreaChart = (svg, project, series, yDomain) => {
  series.forEach((item, seriesIndex) => {
    const top = pathForPoints(item.points, project, 'plotX');
    const first = item.points[0];
    const last = item.points.at(-1);
    const baseline = Math.max(yDomain[0], Math.min(yDomain[1], 0));
    const d = `${top} L${project.x(last.plotX).toFixed(2)} ${project.y(baseline).toFixed(2)} L${project.x(first.plotX).toFixed(2)} ${project.y(baseline).toFixed(2)} Z`;
    const path = appendSVGElement(svg, 'path', {
      d,
      class: 'weibei-chart-series weibei-chart-area',
      stroke: interactiveToneColor(item.tone),
      fill: interactiveToneColor(item.tone),
      role: 'img',
      tabindex: 0,
      'aria-label': chartSeriesLabel(item),
      'data-series-index': seriesIndex,
    });
    appendSVGTitle(path, chartSeriesLabel(item));
  });
};

const renderWeiBeiScatterChart = (svg, project, series) => {
  series.forEach((item, seriesIndex) => {
    item.points.forEach((point) => {
      const label = chartPointLabel(item.name, point);
      const mark = appendSVGElement(svg, 'circle', {
        cx: project.x(point.plotX).toFixed(2),
        cy: project.y(point.y).toFixed(2),
        r: 3.2,
        class: 'weibei-chart-point',
        fill: interactiveToneColor(item.tone),
        tabindex: 0,
        role: 'img',
        'aria-label': label,
        'data-series-index': seriesIndex,
      });
      appendSVGTitle(mark, label);
    });
  });
};

const renderWeiBeiBarChart = (svg, project, series, categories) => {
  const seriesCount = Math.max(1, series.length);
  const categoryCount = Math.max(1, categories.length);
  const step = (project.width - project.pad * 2) / categoryCount;
  const groupWidth = Math.min(32, step * 0.68);
  const barWidth = Math.max(3, groupWidth / seriesCount - 2);
  const baselineValue = Math.max(project.yDomainMin || -MAX_INTERACTIVE_NUMBER, Math.min(project.yDomainMax || MAX_INTERACTIVE_NUMBER, 0));
  const baseline = project.y(baselineValue);
  series.forEach((item, seriesIndex) => {
    item.points.forEach((point) => {
      const center = project.x(point.plotX);
      const x = center - groupWidth / 2 + seriesIndex * (barWidth + 2);
      const y = project.y(Math.max(point.y, 0));
      const height = Math.max(1, Math.abs(project.y(point.y) - baseline));
      const label = chartPointLabel(item.name, point);
      const mark = appendSVGElement(svg, 'rect', {
        x: x.toFixed(2),
        y: y.toFixed(2),
        width: barWidth.toFixed(2),
        height: height.toFixed(2),
        rx: 1.5,
        class: 'weibei-chart-bar',
        fill: interactiveToneColor(item.tone),
        tabindex: 0,
        role: 'img',
        'aria-label': label,
        'data-series-index': seriesIndex,
      });
      appendSVGTitle(mark, label);
    });
  });
};

const renderWeiBeiChart = (model) => {
  const root = createWeiBeiInteractiveRoot('chart', 'weibei-interactive-chart');
  root.dataset.chartType = model.chartType;
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const { svg, project } = appendChartFrame(root, model.xLabel, model.yLabel, model.xDomain, model.yDomain, {
    xTickLabels: model.xMode === 'category' ? model.categories : null,
  });
  if (model.chartType === 'bar') renderWeiBeiBarChart(svg, project, model.series, model.categories);
  if (model.chartType === 'scatter') renderWeiBeiScatterChart(svg, project, model.series);
  if (model.chartType === 'area') renderWeiBeiAreaChart(svg, project, model.series, model.yDomain);
  if (model.chartType === 'line') renderWeiBeiLineChart(svg, project, model.series);
  const inspector = appendTextElement(root, 'div', 'weibei-chart-inspector', editorLabel('interactiveChartHint'));
  inspector.dataset.empty = 'true';
  let lockedMark = null;
  const showInspector = (mark) => {
    const label = mark?.getAttribute('aria-label') || '';
    if (!label) return;
    inspector.textContent = label;
    inspector.dataset.empty = 'false';
  };
  const restoreInspectorHint = () => {
    inspector.textContent = editorLabel('interactiveChartHint');
    inspector.dataset.empty = 'true';
  };
  root.querySelectorAll('.weibei-chart-point, .weibei-chart-bar, .weibei-chart-line, .weibei-chart-area').forEach((mark) => {
    mark.addEventListener('mouseenter', () => {
      if (!lockedMark) showInspector(mark);
    });
    mark.addEventListener('mouseleave', () => {
      if (!lockedMark) restoreInspectorHint();
    });
    mark.addEventListener('focus', () => {
      if (!lockedMark) showInspector(mark);
    });
    mark.addEventListener('blur', () => {
      if (!lockedMark) restoreInspectorHint();
    });
    mark.addEventListener('click', () => {
      const label = mark.getAttribute('aria-label') || '';
      if (!label) return;
      const releasing = lockedMark === mark;
      root.querySelectorAll('.is-inspected').forEach((node) => node.classList.remove('is-inspected'));
      if (releasing) {
        lockedMark = null;
        restoreInspectorHint();
      } else {
        lockedMark = mark;
        mark.classList.add('is-inspected');
        showInspector(mark);
      }
      postInteractiveAction(root, 'inspect-mark', { label, locked: !releasing }, model.sources[0]);
    });
  });
  appendChartLegend(root, model.series);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiFunctionPlot = (model) => {
  const root = createWeiBeiInteractiveRoot('function-plot', 'weibei-interactive-function');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const { svg, project } = appendChartFrame(root, model.xLabel, model.yLabel, model.xDomain, model.yDomain);
  model.curves.forEach((curve) => {
    appendSVGElement(svg, 'path', {
      d: pathForPoints(curve.points, project),
      class: 'weibei-function-curve',
      fill: 'none',
      stroke: interactiveToneColor(curve.tone),
    });
    appendTextElement(root, 'div', 'weibei-function-formula', curve.formulaLabel);
  });
  appendInteractiveSources(root, model.sources);
  return root;
};

const sampleInteractiveFamily = (family, controls, xDomain) => {
  const fn = interactiveFunctionFamilies[family];
  const values = Object.fromEntries(controls.map((control) => [control.key, control.value]));
  const points = [];
  const count = Math.min(MAX_INTERACTIVE_POINTS, 72);
  const asymptote = family === 'inverse' ? values.h ?? 0 : null;
  let previousX = null;
  let breakBefore = false;
  for (let index = 0; index < count; index += 1) {
    const ratio = count === 1 ? 0 : index / (count - 1);
    const x = xDomain[0] + (xDomain[1] - xDomain[0]) * ratio;
    if (asymptote !== null && previousX !== null && ((previousX < asymptote && x > asymptote) || (previousX > asymptote && x < asymptote))) {
      breakBefore = true;
    }
    if (asymptote !== null && Math.abs(x - asymptote) < 0.001) {
      previousX = x;
      breakBefore = true;
      continue;
    }
    const y = fn(x, values);
    if (Number.isFinite(y)) {
      points.push({ x, y, breakBefore });
      breakBefore = false;
    } else {
      breakBefore = true;
    }
    previousX = x;
  }
  return points;
};

const renderWeiBeiParameterLab = (model) => {
  const root = createWeiBeiInteractiveRoot('parameter-lab', 'weibei-interactive-parameter');
  root.dataset.functionFamily = model.family;
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const { svg, project } = appendChartFrame(root, model.xLabel, model.yLabel, model.xDomain, model.yDomain);
  const curve = appendSVGElement(svg, 'path', {
    class: 'weibei-parameter-curve',
    fill: 'none',
    stroke: interactiveToneColor(model.tone),
  });
  const controlsRoot = document.createElement('div');
  controlsRoot.className = 'weibei-parameter-controls';
  const initialValues = model.controls.map((control) => control.value);
  const updateCurve = () => {
    const points = sampleInteractiveFamily(model.family, model.controls, model.xDomain);
    curve.setAttribute('d', pathForPoints(points, project));
  };
  model.controls.forEach((control) => {
    const row = document.createElement('label');
    row.className = 'weibei-parameter-control';
    appendTextElement(row, 'span', 'weibei-parameter-label', control.label);
    const input = document.createElement('input');
    input.type = 'range';
    input.className = 'weibei-parameter-slider';
    input.min = String(control.min);
    input.max = String(control.max);
    input.step = String(control.step);
    input.value = String(control.value);
    const value = appendTextElement(row, 'span', 'weibei-parameter-value', String(control.value));
    input.addEventListener('input', () => {
      const nextValue = safeInteractiveNumber(Number(input.value), control.min, control.max);
      if (nextValue === null) return;
      control.value = nextValue;
      value.textContent = input.value;
      updateCurve();
    });
    input.addEventListener('change', () => {
      postInteractiveAction(root, 'adjust-parameters', {
        values: Object.fromEntries(model.controls.map((item) => [item.key, item.value])),
      }, model.sources[0]);
    });
    row.appendChild(input);
    controlsRoot.appendChild(row);
  });
  updateCurve();
  root.appendChild(controlsRoot);
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.className = 'weibei-interactive-action weibei-parameter-reset';
  reset.textContent = editorLabel('interactiveReset');
  reset.addEventListener('click', () => {
    model.controls.forEach((control, index) => {
      control.value = initialValues[index];
      const row = controlsRoot.children[index];
      const input = row?.querySelector('.weibei-parameter-slider');
      const value = row?.querySelector('.weibei-parameter-value');
      if (input) input.value = String(control.value);
      if (value) value.textContent = String(control.value);
    });
    updateCurve();
    postInteractiveAction(root, 'reset-parameters');
  });
  root.appendChild(reset);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderHighlightedText = (parent, text, terms) => {
  parent.textContent = '';
  const matches = [];
  terms.forEach((term) => {
    let start = text.indexOf(term);
    while (start >= 0) {
      matches.push({ start, end: start + term.length });
      start = text.indexOf(term, start + term.length);
    }
  });
  matches.sort((a, b) => a.start - b.start || b.end - a.end);
  let cursor = 0;
  matches.forEach((match) => {
    if (match.start < cursor) return;
    if (match.start > cursor) parent.appendChild(document.createTextNode(text.slice(cursor, match.start)));
    const mark = document.createElement('mark');
    mark.className = 'weibei-text-highlight';
    mark.textContent = text.slice(match.start, match.end);
    parent.appendChild(mark);
    cursor = match.end;
  });
  if (cursor < text.length) parent.appendChild(document.createTextNode(text.slice(cursor)));
};

const bindInteractiveTabs = (tabs, activate, onActivate = () => {}) => {
  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => {
      activate(index);
      onActivate(index);
    });
    tab.addEventListener('keydown', (event) => {
      if (!['ArrowRight', 'ArrowLeft', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      let nextIndex = index;
      if (event.key === 'Home') nextIndex = 0;
      if (event.key === 'End') nextIndex = tabs.length - 1;
      if (event.key === 'ArrowRight') nextIndex = (index + 1) % tabs.length;
      if (event.key === 'ArrowLeft') nextIndex = (index - 1 + tabs.length) % tabs.length;
      tabs[nextIndex].focus();
      activate(nextIndex);
      onActivate(nextIndex);
    });
  });
};

const renderWeiBeiTextStudy = (model) => {
  const root = createWeiBeiInteractiveRoot('text-study', 'weibei-interactive-text-study');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const tabRow = document.createElement('div');
  tabRow.className = 'weibei-interactive-tabs';
  tabRow.setAttribute('role', 'tablist');
  tabRow.setAttribute('aria-label', model.title);
  const copy = document.createElement('div');
  copy.className = 'weibei-text-study-copy';
  copy.id = `${stableInteractiveID(`text-study-${model.title}`)}-panel`;
  copy.setAttribute('role', 'tabpanel');
  copy.tabIndex = 0;
  const note = document.createElement('div');
  note.className = 'weibei-text-study-note';
  const tabs = model.variants.map((variant, index) => {
    const tab = document.createElement('button');
    tab.type = 'button';
    tab.className = 'weibei-interactive-tab';
    tab.textContent = variant.label;
    tab.setAttribute('role', 'tab');
    tab.id = `${copy.id}-tab-${index}`;
    tab.setAttribute('aria-controls', copy.id);
    tabRow.appendChild(tab);
    return tab;
  });
  const activate = (index) => {
    model.variants.forEach((variant, variantIndex) => {
      tabs[variantIndex].setAttribute('aria-selected', variantIndex === index ? 'true' : 'false');
      tabs[variantIndex].tabIndex = variantIndex === index ? 0 : -1;
      if (variantIndex === index) {
        copy.setAttribute('aria-labelledby', tabs[variantIndex].id);
        renderHighlightedText(copy, variant.text, model.highlightTerms);
        note.textContent = variant.note;
      }
    });
  };
  bindInteractiveTabs(tabs, activate, (index) => {
    postInteractiveAction(root, 'select-variant', {
      index,
      label: model.variants[index]?.label || '',
    }, model.sources[0]);
  });
  activate(0);
  root.appendChild(tabRow);
  root.appendChild(copy);
  root.appendChild(note);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiDesignCompare = (model) => {
  const root = createWeiBeiInteractiveRoot('design-compare', 'weibei-interactive-design');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const tabRow = document.createElement('div');
  tabRow.className = 'weibei-interactive-tabs';
  tabRow.setAttribute('role', 'tablist');
  tabRow.setAttribute('aria-label', model.title);
  const preview = document.createElement('div');
  preview.className = 'weibei-design-preview';
  preview.id = `${stableInteractiveID(`design-compare-${model.title}`)}-panel`;
  preview.setAttribute('role', 'tabpanel');
  preview.tabIndex = 0;
  const title = appendTextElement(preview, 'div', 'weibei-design-preview-title', '');
  const body = appendTextElement(preview, 'div', 'weibei-design-preview-body', '');
  const tabs = model.variants.map((variant, index) => {
    const tab = document.createElement('button');
    tab.type = 'button';
    tab.className = 'weibei-interactive-tab';
    tab.textContent = variant.label;
    tab.setAttribute('role', 'tab');
    tab.id = `${preview.id}-tab-${index}`;
    tab.setAttribute('aria-controls', preview.id);
    tabRow.appendChild(tab);
    return tab;
  });
  const activate = (index) => {
    model.variants.forEach((variant, variantIndex) => {
      tabs[variantIndex].setAttribute('aria-selected', variantIndex === index ? 'true' : 'false');
      tabs[variantIndex].tabIndex = variantIndex === index ? 0 : -1;
      if (variantIndex === index) {
        preview.setAttribute('aria-labelledby', tabs[variantIndex].id);
        preview.dataset.treatment = variant.treatment;
        preview.dataset.tone = variant.tone;
        preview.style.setProperty('--weibei-design-tone', interactiveToneColor(variant.tone));
        title.textContent = variant.headline;
        body.textContent = variant.body;
      }
    });
  };
  bindInteractiveTabs(tabs, activate, (index) => {
    postInteractiveAction(root, 'select-design', {
      index,
      label: model.variants[index]?.label || '',
    }, model.sources[0]);
  });
  activate(0);
  root.appendChild(tabRow);
  root.appendChild(preview);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiPalette = (model) => {
  const root = createWeiBeiInteractiveRoot('palette', 'weibei-interactive-palette');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const swatchRow = document.createElement('div');
  swatchRow.className = 'weibei-palette-swatches';
  const detail = document.createElement('div');
  detail.className = 'weibei-palette-detail';
  const preview = appendTextElement(root, 'div', 'weibei-palette-preview', model.previewText);
  const swatches = [];
  const activate = (index) => {
    const color = model.colors[index];
    if (!color) return;
    swatches.forEach((swatch, swatchIndex) => {
      swatch.setAttribute('aria-pressed', swatchIndex === index ? 'true' : 'false');
    });
    detail.dataset.value = color.value;
    detail.textContent = `${color.name} ${color.value} ${color.role}`;
    preview.style.borderColor = color.value;
  };
  model.colors.forEach((color, index) => {
    const swatch = document.createElement('button');
    swatch.type = 'button';
    swatch.className = 'weibei-palette-swatch';
    swatch.style.backgroundColor = color.value;
    swatch.style.color = interactiveHexTextColor(color.value);
    swatch.style.textShadow = interactiveHexTextColor(color.value) === '#1D1814' ? 'none' : '0 1px 1px rgba(0, 0, 0, .42)';
    swatch.textContent = color.name;
    swatch.setAttribute('aria-label', `${color.name} ${color.value} ${color.role}`);
    swatch.setAttribute('aria-pressed', 'false');
    swatch.addEventListener('click', () => {
      activate(index);
      postInteractiveAction(root, 'select-color', {
        index,
        name: color.name,
        value: color.value,
      }, model.sources[0]);
    });
    swatches.push(swatch);
    swatchRow.appendChild(swatch);
  });
  root.insertBefore(swatchRow, preview);
  root.appendChild(detail);
  activate(0);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiStudyBoard = (model) => {
  const root = createWeiBeiInteractiveRoot('study-board', 'weibei-interactive-study-board');
  root.dataset.layout = model.layout;
  root.dataset.treatment = model.treatment;
  const header = document.createElement('div');
  header.className = 'weibei-study-board-header';
  appendTextElement(header, 'div', 'weibei-interactive-title', model.title);
  if (model.summary) appendTextElement(header, 'div', 'weibei-study-board-summary', model.summary);
  root.appendChild(header);
  if (model.metrics.length > 0) {
    const metrics = document.createElement('div');
    metrics.className = 'weibei-study-board-metrics';
    model.metrics.forEach((metric) => {
      const item = document.createElement('div');
      item.className = 'weibei-study-board-metric';
      item.dataset.tone = metric.tone;
      item.style.setProperty('--weibei-interactive-tone', interactiveToneColor(metric.tone));
      appendTextElement(item, 'div', 'weibei-study-board-metric-label', metric.label);
      appendTextElement(item, 'div', 'weibei-study-board-metric-value', metric.value);
      if (metric.note) appendTextElement(item, 'div', 'weibei-study-board-metric-note', metric.note);
      metrics.appendChild(item);
    });
    root.appendChild(metrics);
  }
  const items = document.createElement('div');
  items.className = 'weibei-study-board-items';
  const boardItems = [];
  const activeSource = document.createElement('div');
  activeSource.className = 'weibei-interactive-focus-source';
  model.items.forEach((entry, index) => {
    const item = document.createElement('button');
    item.type = 'button';
    item.className = 'weibei-study-board-item';
    item.dataset.tone = entry.tone;
    item.style.setProperty('--weibei-interactive-tone', interactiveToneColor(entry.tone));
    item.dataset.index = String(index + 1);
    if (entry.kicker || entry.status) {
      const meta = document.createElement('div');
      meta.className = 'weibei-study-board-item-meta';
      if (entry.kicker) appendTextElement(meta, 'span', 'weibei-study-board-kicker', entry.kicker);
      if (entry.status) appendTextElement(meta, 'span', 'weibei-study-board-status', entry.status);
      item.appendChild(meta);
    }
    appendTextElement(item, 'div', 'weibei-study-board-item-title', entry.title);
    appendTextElement(item, 'div', 'weibei-study-board-item-body', entry.body);
    item.addEventListener('click', () => {
      const isActive = item.classList.contains('is-active');
      boardItems.forEach((candidate) => {
        candidate.classList.remove('is-active');
        candidate.classList.toggle('is-muted', !isActive && candidate !== item);
      });
      if (!isActive) item.classList.add('is-active');
      activeSource.textContent = '';
      if (!isActive && entry.source) appendInlineSourceButton(activeSource, entry.source);
      postInteractiveAction(root, isActive ? 'clear-focus' : 'focus-item', {
        index,
        title: entry.title,
      }, entry.source);
      reportContentHeight();
    });
    boardItems.push(item);
    items.appendChild(item);
  });
  root.appendChild(items);
  root.appendChild(activeSource);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiRelationshipMap = (model) => {
  const root = createWeiBeiInteractiveRoot('relationship-map', 'weibei-interactive-relationship-map');
  root.dataset.layout = model.layout;
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const nodes = document.createElement('div');
  nodes.className = 'weibei-relationship-nodes';
  const nodeElements = new Map();
  const edgeElements = [];
  const activeSource = document.createElement('div');
  activeSource.className = 'weibei-interactive-focus-source';
  model.nodes.forEach((node, index) => {
    const item = document.createElement('button');
    item.type = 'button';
    item.className = 'weibei-relationship-node';
    item.dataset.nodeId = node.id;
    item.dataset.tone = node.tone;
    item.dataset.role = index === 0 && model.layout === 'radial' ? 'center' : 'node';
    item.style.setProperty('--weibei-interactive-tone', interactiveToneColor(node.tone));
    appendTextElement(item, 'div', 'weibei-relationship-node-label', node.label);
    if (node.detail) appendTextElement(item, 'div', 'weibei-relationship-node-detail', node.detail);
    item.addEventListener('click', () => {
      const wasActive = item.classList.contains('is-active');
      const connected = new Set([node.id]);
      model.edges.forEach((edge) => {
        if (edge.from === node.id) connected.add(edge.to);
        if (edge.to === node.id) connected.add(edge.from);
      });
      nodeElements.forEach((candidate, id) => {
        candidate.classList.toggle('is-active', !wasActive && id === node.id);
        candidate.classList.toggle('is-muted', !wasActive && !connected.has(id));
      });
      edgeElements.forEach(({ element, edge }) => {
        element.classList.toggle('is-active', !wasActive && (edge.from === node.id || edge.to === node.id));
        element.classList.toggle('is-muted', !wasActive && edge.from !== node.id && edge.to !== node.id);
      });
      activeSource.textContent = '';
      if (!wasActive && node.source) appendInlineSourceButton(activeSource, node.source);
      postInteractiveAction(root, wasActive ? 'clear-node' : 'select-node', {
        nodeID: node.id,
        label: node.label,
        connectedNodeIDs: Array.from(connected),
      }, node.source);
      reportContentHeight();
    });
    nodeElements.set(node.id, item);
    nodes.appendChild(item);
  });
  root.appendChild(nodes);
  const edges = document.createElement('div');
  edges.className = 'weibei-relationship-edges';
  const labelsByID = new Map(model.nodes.map((node) => [node.id, node.label]));
  model.edges.forEach((edge) => {
    const row = document.createElement('div');
    row.className = 'weibei-relationship-edge';
    row.dataset.from = edge.from;
    row.dataset.to = edge.to;
    appendTextElement(row, 'span', 'weibei-relationship-edge-from', labelsByID.get(edge.from) || edge.from);
    appendTextElement(row, 'span', 'weibei-relationship-edge-arrow', '→');
    appendTextElement(row, 'span', 'weibei-relationship-edge-to', labelsByID.get(edge.to) || edge.to);
    if (edge.label) appendTextElement(row, 'span', 'weibei-relationship-edge-label', edge.label);
    edgeElements.push({ element: row, edge });
    edges.appendChild(row);
  });
  root.appendChild(edges);
  root.appendChild(activeSource);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiTimeline = (model) => {
  const root = createWeiBeiInteractiveRoot('timeline', 'weibei-interactive-timeline');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const events = document.createElement('div');
  events.className = 'weibei-timeline-events';
  const eventItems = [];
  const activeSource = document.createElement('div');
  activeSource.className = 'weibei-interactive-focus-source';
  const activate = (index) => {
    const event = model.events[index];
    if (!event) return;
    eventItems.forEach((item, itemIndex) => {
      item.classList.toggle('is-active', itemIndex === index);
      item.classList.toggle('is-muted', itemIndex !== index);
      item.setAttribute('aria-pressed', itemIndex === index ? 'true' : 'false');
    });
    activeSource.textContent = '';
    if (event.source) appendInlineSourceButton(activeSource, event.source);
    root.dataset.activeEvent = String(index);
    postInteractiveAction(root, 'select-event', {
      index,
      label: event.label,
      title: event.title,
    }, event.source);
  };
  model.events.forEach((event, index) => {
    const item = document.createElement('button');
    item.type = 'button';
    item.className = 'weibei-timeline-event';
    item.setAttribute('aria-pressed', 'false');
    item.dataset.tone = event.tone;
    item.style.setProperty('--weibei-interactive-tone', interactiveToneColor(event.tone));
    appendTextElement(item, 'div', 'weibei-timeline-label', event.label);
    appendTextElement(item, 'div', 'weibei-timeline-title', event.title);
    if (event.detail) appendTextElement(item, 'div', 'weibei-timeline-detail', event.detail);
    item.addEventListener('click', () => activate(index));
    eventItems.push(item);
    events.appendChild(item);
  });
  root.appendChild(events);
  const controls = document.createElement('div');
  controls.className = 'weibei-timeline-controls';
  const previous = document.createElement('button');
  previous.type = 'button';
  previous.className = 'weibei-interactive-action';
  previous.textContent = editorLabel('interactivePrevious');
  previous.addEventListener('click', () => {
    const current = Number(root.dataset.activeEvent || 0);
    activate((current - 1 + model.events.length) % model.events.length);
  });
  const next = document.createElement('button');
  next.type = 'button';
  next.className = 'weibei-interactive-action';
  next.textContent = editorLabel('interactiveNext');
  next.addEventListener('click', () => {
    const current = Number(root.dataset.activeEvent || -1);
    activate((current + 1) % model.events.length);
  });
  controls.appendChild(previous);
  controls.appendChild(next);
  root.appendChild(controls);
  root.appendChild(activeSource);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiComparisonMatrix = (model) => {
  const root = createWeiBeiInteractiveRoot('comparison-matrix', 'weibei-interactive-comparison-matrix');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const table = document.createElement('table');
  table.className = 'weibei-comparison-table';
  const thead = document.createElement('thead');
  const headRow = document.createElement('tr');
  appendTextElement(headRow, 'th', 'weibei-comparison-corner', '');
  const headerButtons = [];
  const cellsByColumn = model.columns.map(() => []);
  const setFocus = (nextIndex) => {
    const current = root.dataset.focusedColumn === undefined ? -1 : Number(root.dataset.focusedColumn);
    const activeIndex = current === nextIndex ? -1 : nextIndex;
    if (activeIndex < 0) {
      delete root.dataset.focusedColumn;
    } else {
      root.dataset.focusedColumn = String(activeIndex);
    }
    headerButtons.forEach((button, index) => {
      button.setAttribute('aria-pressed', index === activeIndex ? 'true' : 'false');
    });
    cellsByColumn.forEach((cells, index) => {
      cells.forEach((cell) => cell.classList.toggle('is-focused-column', index === activeIndex));
    });
    postInteractiveAction(root, activeIndex < 0 ? 'clear-column' : 'focus-column', {
      columnIndex: activeIndex,
      column: activeIndex < 0 ? '' : model.columns[activeIndex],
    }, model.sources[0]);
  };
  model.columns.forEach((column, index) => {
    const th = document.createElement('th');
    th.scope = 'col';
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-comparison-column-button';
    button.textContent = column;
    button.setAttribute('aria-pressed', 'false');
    button.addEventListener('click', () => setFocus(index));
    button.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      event.preventDefault();
      setFocus(index);
    });
    headerButtons.push(button);
    th.appendChild(button);
    headRow.appendChild(th);
  });
  thead.appendChild(headRow);
  table.appendChild(thead);
  const tbody = document.createElement('tbody');
  model.rows.forEach((row) => {
    const tr = document.createElement('tr');
    const rowHeader = appendTextElement(tr, 'th', 'weibei-comparison-row-label', row.label);
    rowHeader.scope = 'row';
    row.values.forEach((value, index) => {
      const cell = appendTextElement(tr, 'td', 'weibei-comparison-cell', value);
      cell.dataset.columnIndex = String(index);
      if (row.emphasisIndex === index) cell.classList.add('is-emphasized');
      cellsByColumn[index].push(cell);
    });
    tbody.appendChild(tr);
  });
  table.appendChild(tbody);
  root.appendChild(table);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiAnnotatedPassage = (model) => {
  const root = createWeiBeiInteractiveRoot('annotated-passage', 'weibei-interactive-annotated-passage');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const layout = document.createElement('div');
  layout.className = 'weibei-annotated-layout';
  const copy = document.createElement('div');
  copy.className = 'weibei-annotated-copy';
  const margin = document.createElement('div');
  margin.className = 'weibei-annotation-margin';
  const activeSource = document.createElement('div');
  activeSource.className = 'weibei-interactive-focus-source';
  const ranges = model.annotations.map((annotation, index) => {
    const start = model.text.indexOf(annotation.term);
    return start < 0 ? null : { start, end: start + annotation.term.length, index };
  }).filter(Boolean).sort((left, right) => left.start - right.start || right.end - left.end);
  const accepted = [];
  ranges.forEach((range) => {
    if (accepted.some((item) => range.start < item.end && range.end > item.start)) return;
    accepted.push(range);
  });
  const marks = [];
  const entries = [];
  const activate = (index) => {
    const annotation = model.annotations[index];
    if (!annotation) return;
    marks.forEach((mark) => mark.classList.toggle('is-active', Number(mark.dataset.annotationIndex) === index));
    entries.forEach((entry, entryIndex) => entry.classList.toggle('is-active', entryIndex === index));
    activeSource.textContent = '';
    if (annotation.source) appendInlineSourceButton(activeSource, annotation.source);
    postInteractiveAction(root, 'open-annotation', {
      index,
      term: annotation.term,
    }, annotation.source);
  };
  let cursor = 0;
  accepted.forEach((range) => {
    if (range.start > cursor) copy.appendChild(document.createTextNode(model.text.slice(cursor, range.start)));
    const annotation = model.annotations[range.index];
    const mark = document.createElement('button');
    mark.type = 'button';
    mark.className = 'weibei-annotated-mark';
    mark.dataset.annotationIndex = String(range.index);
    mark.style.setProperty('--weibei-interactive-tone', interactiveToneColor(annotation.tone));
    mark.textContent = model.text.slice(range.start, range.end);
    mark.addEventListener('click', () => activate(range.index));
    copy.appendChild(mark);
    marks.push(mark);
    cursor = range.end;
  });
  if (cursor < model.text.length) copy.appendChild(document.createTextNode(model.text.slice(cursor)));
  model.annotations.forEach((annotation, index) => {
    const entry = document.createElement('button');
    entry.type = 'button';
    entry.className = 'weibei-annotation-entry';
    entry.style.setProperty('--weibei-interactive-tone', interactiveToneColor(annotation.tone));
    appendTextElement(entry, 'span', 'weibei-annotation-term', annotation.term);
    appendTextElement(entry, 'span', 'weibei-annotation-note', annotation.note);
    entry.addEventListener('click', () => activate(index));
    entries.push(entry);
    margin.appendChild(entry);
  });
  layout.appendChild(copy);
  layout.appendChild(margin);
  root.appendChild(layout);
  root.appendChild(activeSource);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiDerivationSteps = (model) => {
  const root = createWeiBeiInteractiveRoot('derivation-steps', 'weibei-interactive-derivation');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  if (model.prompt) appendTextElement(root, 'div', 'weibei-derivation-prompt', model.prompt);
  const progress = appendTextElement(root, 'div', 'weibei-derivation-progress', '');
  const stepsRoot = document.createElement('div');
  stepsRoot.className = 'weibei-derivation-steps';
  const activeSource = document.createElement('div');
  activeSource.className = 'weibei-interactive-focus-source';
  const steps = model.steps.map((step, index) => {
    const item = document.createElement('article');
    item.className = 'weibei-derivation-step';
    item.dataset.index = String(index + 1);
    appendTextElement(item, 'div', 'weibei-derivation-label', step.label);
    appendTextElement(item, 'div', 'weibei-derivation-statement', step.statement);
    if (step.reason) appendTextElement(item, 'div', 'weibei-derivation-reason', step.reason);
    stepsRoot.appendChild(item);
    return item;
  });
  let visibleIndex = 0;
  const renderState = () => {
    steps.forEach((item, index) => {
      item.hidden = index > visibleIndex;
      item.classList.toggle('is-active', index === visibleIndex);
      item.classList.toggle('is-complete', index < visibleIndex);
    });
    progress.textContent = `${Math.min(visibleIndex + 1, model.steps.length)} / ${model.steps.length}`;
    activeSource.textContent = '';
    const source = model.steps[visibleIndex]?.source;
    if (source) appendInlineSourceButton(activeSource, source);
    reportContentHeight();
  };
  root.appendChild(stepsRoot);
  const controls = document.createElement('div');
  controls.className = 'weibei-derivation-controls';
  const previous = document.createElement('button');
  previous.type = 'button';
  previous.className = 'weibei-interactive-action';
  previous.textContent = editorLabel('interactivePrevious');
  previous.addEventListener('click', () => {
    visibleIndex = Math.max(0, visibleIndex - 1);
    renderState();
    postInteractiveAction(root, 'previous-step', { visibleIndex }, model.steps[visibleIndex]?.source);
  });
  const next = document.createElement('button');
  next.type = 'button';
  next.className = 'weibei-interactive-action';
  next.textContent = editorLabel('interactiveNext');
  next.addEventListener('click', () => {
    visibleIndex = Math.min(model.steps.length - 1, visibleIndex + 1);
    renderState();
    postInteractiveAction(root, 'reveal-step', { visibleIndex }, model.steps[visibleIndex]?.source);
  });
  const revealAll = document.createElement('button');
  revealAll.type = 'button';
  revealAll.className = 'weibei-interactive-action';
  revealAll.textContent = editorLabel('interactiveRevealAll');
  revealAll.addEventListener('click', () => {
    visibleIndex = model.steps.length - 1;
    renderState();
    postInteractiveAction(root, 'reveal-all', { visibleIndex }, model.steps[visibleIndex]?.source);
  });
  controls.appendChild(previous);
  controls.appendChild(next);
  controls.appendChild(revealAll);
  root.appendChild(controls);
  root.appendChild(activeSource);
  renderState();
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiFlashcards = (model) => {
  const root = createWeiBeiInteractiveRoot('flashcards', 'weibei-interactive-flashcards');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const status = appendTextElement(root, 'div', 'weibei-flashcard-status', '');
  const stage = document.createElement('div');
  stage.className = 'weibei-flashcard-stage';
  const card = document.createElement('button');
  card.type = 'button';
  card.className = 'weibei-flashcard';
  const front = document.createElement('div');
  front.className = 'weibei-flashcard-front';
  const back = document.createElement('div');
  back.className = 'weibei-flashcard-back';
  card.appendChild(front);
  card.appendChild(back);
  stage.appendChild(card);
  root.appendChild(stage);
  const sourceRoot = document.createElement('div');
  sourceRoot.className = 'weibei-interactive-focus-source';
  let index = 0;
  let known = 0;
  let flipped = false;
  const renderCard = () => {
    const item = model.cards[index];
    front.textContent = item.front;
    back.textContent = item.back;
    if (item.hint) front.setAttribute('data-hint', item.hint); else front.removeAttribute('data-hint');
    card.classList.toggle('is-flipped', flipped);
    card.setAttribute('aria-pressed', flipped ? 'true' : 'false');
    status.textContent = `${index + 1} / ${model.cards.length} · ${known}`;
    sourceRoot.textContent = '';
    if (item.source) appendInlineSourceButton(sourceRoot, item.source);
  };
  card.addEventListener('click', () => {
    flipped = !flipped;
    renderCard();
    postInteractiveAction(root, flipped ? 'flip-back' : 'flip-front', {
      index,
      front: model.cards[index].front,
    }, model.cards[index].source);
  });
  const controls = document.createElement('div');
  controls.className = 'weibei-flashcard-controls';
  const move = (mastered) => {
    if (mastered) known = Math.min(model.cards.length, known + 1);
    postInteractiveAction(root, mastered ? 'mark-known' : 'mark-again', {
      index,
      front: model.cards[index].front,
    }, model.cards[index].source);
    index = (index + 1) % model.cards.length;
    flipped = false;
    renderCard();
  };
  const again = document.createElement('button');
  again.type = 'button';
  again.className = 'weibei-interactive-action';
  again.textContent = editorLabel('interactiveAgain');
  again.addEventListener('click', () => move(false));
  const know = document.createElement('button');
  know.type = 'button';
  know.className = 'weibei-interactive-action';
  know.textContent = editorLabel('interactiveKnow');
  know.addEventListener('click', () => move(true));
  controls.appendChild(again);
  controls.appendChild(know);
  root.appendChild(controls);
  root.appendChild(sourceRoot);
  renderCard();
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiSequenceBuilder = (model) => {
  const root = createWeiBeiInteractiveRoot('sequence-builder', 'weibei-interactive-sequence-builder');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  if (model.instruction) appendTextElement(root, 'div', 'weibei-sequence-instruction', model.instruction);
  const pool = document.createElement('div');
  pool.className = 'weibei-sequence-pool';
  const answer = document.createElement('div');
  answer.className = 'weibei-sequence-answer';
  const feedback = appendTextElement(root, 'div', 'weibei-sequence-feedback', '');
  feedback.hidden = true;
  const selectedIDs = [];
  const itemButtons = new Map();
  const renderOrder = () => {
    pool.textContent = '';
    answer.textContent = '';
    model.items.forEach((item) => {
      const button = itemButtons.get(item.id);
      const selectedIndex = selectedIDs.indexOf(item.id);
      button.classList.toggle('is-active', selectedIndex >= 0);
      button.dataset.order = selectedIndex >= 0 ? String(selectedIndex + 1) : '';
      if (selectedIndex < 0) pool.appendChild(button);
    });
    selectedIDs.forEach((id) => {
      const button = itemButtons.get(id);
      if (button) answer.appendChild(button);
    });
    feedback.hidden = true;
    feedback.classList.remove('is-correct', 'is-wrong');
    reportContentHeight();
  };
  model.items.forEach((item) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-sequence-item';
    appendTextElement(button, 'span', 'weibei-sequence-item-label', item.label);
    if (item.detail) appendTextElement(button, 'span', 'weibei-sequence-item-detail', item.detail);
    button.addEventListener('click', () => {
      const selectedIndex = selectedIDs.indexOf(item.id);
      if (selectedIndex >= 0) selectedIDs.splice(selectedIndex, 1); else selectedIDs.push(item.id);
      renderOrder();
      postInteractiveAction(root, selectedIndex >= 0 ? 'remove-step' : 'place-step', {
        itemID: item.id,
        order: selectedIDs,
      }, item.source);
    });
    itemButtons.set(item.id, button);
  });
  root.appendChild(pool);
  root.appendChild(answer);
  const controls = document.createElement('div');
  controls.className = 'weibei-sequence-controls';
  const check = document.createElement('button');
  check.type = 'button';
  check.className = 'weibei-interactive-action';
  check.textContent = editorLabel('interactiveCheck');
  check.addEventListener('click', () => {
    const correct = selectedIDs.length === model.correctOrder.length
      && selectedIDs.every((id, index) => id === model.correctOrder[index]);
    feedback.hidden = false;
    feedback.textContent = correct ? model.successText : model.retryText;
    feedback.classList.toggle('is-correct', correct);
    feedback.classList.toggle('is-wrong', !correct);
    postInteractiveAction(root, 'check-order', { correct, order: selectedIDs }, model.sources[0]);
    reportContentHeight();
  });
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.className = 'weibei-interactive-action';
  reset.textContent = editorLabel('interactiveReset');
  reset.addEventListener('click', () => {
    selectedIDs.splice(0);
    renderOrder();
    postInteractiveAction(root, 'reset-order');
  });
  controls.appendChild(check);
  controls.appendChild(reset);
  root.appendChild(controls);
  root.appendChild(feedback);
  renderOrder();
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiScenarioLab = (model) => {
  const root = createWeiBeiInteractiveRoot('scenario-lab', 'weibei-interactive-scenario-lab');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const layout = document.createElement('div');
  layout.className = 'weibei-scenario-layout';
  const controlsRoot = document.createElement('div');
  controlsRoot.className = 'weibei-scenario-controls';
  const result = document.createElement('div');
  result.className = 'weibei-scenario-result';
  const selections = model.controls.map((control) => control.initialIndex);
  const optionGroups = [];
  const renderOutcome = (emit = false) => {
    optionGroups.forEach((buttons, controlIndex) => {
      buttons.forEach((button, optionIndex) => {
        button.classList.toggle('is-active', selections[controlIndex] === optionIndex);
        button.setAttribute('aria-pressed', selections[controlIndex] === optionIndex ? 'true' : 'false');
      });
    });
    const outcome = model.outcomes.find((item) => item.selections.every((value, index) => value === selections[index]));
    result.textContent = '';
    if (outcome) {
      result.style.setProperty('--weibei-interactive-tone', interactiveToneColor(outcome.tone));
      appendTextElement(result, 'div', 'weibei-scenario-result-title', outcome.title);
      appendTextElement(result, 'div', 'weibei-scenario-result-body', outcome.body);
      if (outcome.source) appendInlineSourceButton(result, outcome.source);
    } else {
      appendTextElement(result, 'div', 'weibei-scenario-result-body', editorLabel('interactiveNoOutcome'));
    }
    if (emit) postInteractiveAction(root, 'change-scenario', { selections }, outcome?.source || model.sources[0]);
    reportContentHeight();
  };
  model.controls.forEach((control, controlIndex) => {
    const group = document.createElement('div');
    group.className = 'weibei-scenario-control';
    appendTextElement(group, 'div', 'weibei-scenario-control-label', control.label);
    const buttons = control.options.map((option, optionIndex) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'weibei-scenario-option';
      button.textContent = option;
      button.setAttribute('aria-pressed', 'false');
      button.addEventListener('click', () => {
        selections[controlIndex] = optionIndex;
        renderOutcome(true);
      });
      group.appendChild(button);
      return button;
    });
    optionGroups.push(buttons);
    controlsRoot.appendChild(group);
  });
  layout.appendChild(controlsRoot);
  layout.appendChild(result);
  root.appendChild(layout);
  renderOutcome();
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiEvidenceBoard = (model) => {
  const root = createWeiBeiInteractiveRoot('evidence-board', 'weibei-interactive-evidence-board');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  appendTextElement(root, 'div', 'weibei-evidence-claim', model.claim);
  const toolbar = document.createElement('div');
  toolbar.className = 'weibei-evidence-toolbar';
  const list = document.createElement('div');
  list.className = 'weibei-evidence-list';
  const detail = document.createElement('div');
  detail.className = 'weibei-evidence-detail';
  const itemButtons = [];
  const filters = [
    ['all', editorLabel('interactiveAll')],
    ['support', editorLabel('interactiveSupport')],
    ['challenge', editorLabel('interactiveChallenge')],
    ['gap', editorLabel('interactiveGap')],
  ];
  const filterButtons = [];
  const applyFilter = (stance, emit = true) => {
    filterButtons.forEach((button) => button.classList.toggle('is-active', button.dataset.stance === stance));
    itemButtons.forEach(({ button, item }) => {
      button.hidden = stance !== 'all' && item.stance !== stance;
    });
    if (emit) postInteractiveAction(root, 'filter-evidence', { stance });
    reportContentHeight();
  };
  filters.forEach(([stance, label]) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-evidence-filter';
    button.dataset.stance = stance;
    button.textContent = label;
    button.addEventListener('click', () => applyFilter(stance));
    filterButtons.push(button);
    toolbar.appendChild(button);
  });
  model.items.forEach((item, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-evidence-item';
    button.dataset.stance = item.stance;
    button.style.setProperty('--weibei-interactive-tone', interactiveToneColor(item.tone));
    appendTextElement(button, 'span', 'weibei-evidence-item-title', item.title);
    button.addEventListener('click', () => {
      itemButtons.forEach((entry) => entry.button.classList.toggle('is-active', entry.button === button));
      detail.textContent = '';
      appendTextElement(detail, 'div', 'weibei-evidence-detail-title', item.title);
      appendTextElement(detail, 'div', 'weibei-evidence-detail-body', item.detail);
      if (item.source) appendInlineSourceButton(detail, item.source);
      postInteractiveAction(root, 'inspect-evidence', { index, stance: item.stance, title: item.title }, item.source);
      reportContentHeight();
    });
    itemButtons.push({ button, item });
    list.appendChild(button);
  });
  root.appendChild(toolbar);
  root.appendChild(list);
  root.appendChild(detail);
  applyFilter('all', false);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiSpectrum = (model) => {
  const root = createWeiBeiInteractiveRoot('spectrum', 'weibei-interactive-spectrum');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const track = document.createElement('div');
  track.className = 'weibei-spectrum-track';
  track.dataset.start = model.axisStart;
  track.dataset.end = model.axisEnd;
  const detail = document.createElement('div');
  detail.className = 'weibei-spectrum-detail';
  const markers = model.points.map((point, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-spectrum-marker';
    button.style.left = `${point.position}%`;
    button.style.setProperty('--weibei-interactive-tone', interactiveToneColor(point.tone));
    button.textContent = point.label;
    button.addEventListener('click', () => {
      markers.forEach((marker, markerIndex) => marker.classList.toggle('is-active', markerIndex === index));
      detail.textContent = '';
      appendTextElement(detail, 'div', 'weibei-spectrum-detail-title', point.label);
      appendTextElement(detail, 'div', 'weibei-spectrum-detail-body', point.detail);
      if (point.source) appendInlineSourceButton(detail, point.source);
      postInteractiveAction(root, 'select-point', { index, label: point.label, position: point.position }, point.source);
      reportContentHeight();
    });
    track.appendChild(button);
    return button;
  });
  root.appendChild(track);
  root.appendChild(detail);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiDecisionPath = (model) => {
  const root = createWeiBeiInteractiveRoot('decision-path', 'weibei-interactive-decision-path');
  appendTextElement(root, 'div', 'weibei-interactive-title', model.title);
  const trail = document.createElement('div');
  trail.className = 'weibei-decision-trail';
  const nodeRoot = document.createElement('div');
  nodeRoot.className = 'weibei-decision-node';
  const choicesRoot = document.createElement('div');
  choicesRoot.className = 'weibei-decision-choices';
  const path = [];
  let currentID = model.startID;
  const renderNode = (emit = false) => {
    const node = model.nodes.find((item) => item.id === currentID);
    if (!node) return;
    trail.textContent = path.map((id) => model.nodes.find((item) => item.id === id)?.title || id).join(' → ');
    nodeRoot.textContent = '';
    appendTextElement(nodeRoot, 'div', 'weibei-decision-node-title', node.title);
    appendTextElement(nodeRoot, 'div', 'weibei-decision-node-body', node.body);
    if (node.source) appendInlineSourceButton(nodeRoot, node.source);
    choicesRoot.textContent = '';
    node.choices.forEach((choice) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'weibei-decision-choice';
      button.textContent = choice.label;
      button.addEventListener('click', () => {
        if (path.length >= MAX_INTERACTIVE_DECISION_NODES * 2) path.shift();
        path.push(node.id);
        currentID = choice.nextID;
        renderNode(true);
      });
      choicesRoot.appendChild(button);
    });
    if (path.length > 0) {
      const reset = document.createElement('button');
      reset.type = 'button';
      reset.className = 'weibei-decision-choice weibei-decision-reset';
      reset.textContent = editorLabel('interactiveReset');
      reset.addEventListener('click', () => {
        path.splice(0);
        currentID = model.startID;
        renderNode(true);
      });
      choicesRoot.appendChild(reset);
    }
    if (emit) postInteractiveAction(root, 'choose-path', { path, currentID }, node.source);
    reportContentHeight();
  };
  root.appendChild(trail);
  root.appendChild(nodeRoot);
  root.appendChild(choicesRoot);
  renderNode();
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiUnitWorkbench = (model) => {
  const root = createWeiBeiInteractiveRoot('unit-workbench', 'weibei-interactive-unit-workbench');
  root.setAttribute('aria-label', model.title);
  appendTextElement(root, 'div', 'weibei-unit-title', model.title);
  if (model.question) appendTextElement(root, 'div', 'weibei-unit-question', model.question);
  const variablesRoot = document.createElement('div');
  variablesRoot.className = 'weibei-unit-variables';
  const checksRoot = document.createElement('div');
  checksRoot.className = 'weibei-unit-checks';
  const detail = document.createElement('div');
  detail.className = 'weibei-unit-detail';
  const buttons = [];
  const selectItem = (button, action, payload, body, source = '') => {
    buttons.forEach((item) => item.setAttribute('aria-pressed', item === button ? 'true' : 'false'));
    detail.textContent = '';
    body.forEach(([className, text]) => appendTextElement(detail, 'div', className, text));
    if (source) appendInlineSourceButton(detail, source);
    postInteractiveAction(root, action, payload, source);
    reportContentHeight();
  };
  model.variables.forEach((variable, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-unit-variable';
    button.setAttribute('aria-pressed', 'false');
    appendTextElement(button, 'span', 'weibei-unit-variable-label', variable.label);
    appendTextElement(button, 'span', 'weibei-unit-variable-value', `${variable.value} ${variable.unit}`);
    if (variable.role) appendTextElement(button, 'span', 'weibei-unit-variable-role', variable.role);
    button.addEventListener('click', () => selectItem(button, 'inspect-variable', {
      id: variable.id,
      index,
      unit: variable.unit,
    }, [
      ['weibei-unit-detail-title', variable.label],
      ['weibei-unit-detail-body', `${variable.value} ${variable.unit}`],
      ['weibei-unit-detail-note', variable.role],
    ], variable.source));
    buttons.push(button);
    variablesRoot.appendChild(button);
  });
  model.checks.forEach((check, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-unit-check';
    button.setAttribute('aria-pressed', 'false');
    appendTextElement(button, 'span', 'weibei-unit-check-label', check.label);
    appendTextElement(button, 'span', 'weibei-unit-check-chain', `${check.left} = ${check.right}`);
    button.addEventListener('click', () => selectItem(button, 'inspect-check', {
      id: check.id,
      index,
      result: check.result,
    }, [
      ['weibei-unit-detail-title', check.label],
      ['weibei-unit-detail-body', `${check.left} = ${check.right}`],
      ['weibei-unit-detail-note', check.result],
    ], check.source));
    buttons.push(button);
    checksRoot.appendChild(button);
  });
  root.appendChild(variablesRoot);
  root.appendChild(checksRoot);
  root.appendChild(detail);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiReactionBalance = (model) => {
  const root = createWeiBeiInteractiveRoot('reaction-balance', 'weibei-interactive-reaction-balance');
  root.setAttribute('aria-label', model.title);
  appendTextElement(root, 'div', 'weibei-reaction-title', model.title);
  const equation = document.createElement('div');
  equation.className = 'weibei-reaction-equation';
  const reactants = document.createElement('div');
  reactants.className = 'weibei-reaction-side weibei-reaction-reactants';
  const products = document.createElement('div');
  products.className = 'weibei-reaction-side weibei-reaction-products';
  const balance = document.createElement('div');
  balance.className = 'weibei-reaction-balance';
  balance.setAttribute('role', 'status');
  balance.setAttribute('aria-live', 'polite');
  const sourceRoot = document.createElement('div');
  sourceRoot.className = 'weibei-reaction-source';
  const coefficients = model.species.map((species) => species.coefficient);
  const speciesButtons = [];
  const computeTotals = (side) => {
    const totals = {};
    model.species.forEach((species, index) => {
      if (species.side !== side) return;
      Object.entries(species.atoms).forEach(([element, count]) => {
        totals[element] = (totals[element] || 0) + count * coefficients[index];
      });
    });
    return totals;
  };
  const renderBalance = (emit = false, action = 'change-coefficient', source = model.sources[0]) => {
    speciesButtons.forEach(({ value, index }) => {
      value.textContent = String(coefficients[index]);
    });
    balance.textContent = '';
    const left = computeTotals('reactant');
    const right = computeTotals('product');
    model.elements.forEach((element) => {
      const row = document.createElement('div');
      row.className = 'weibei-reaction-element';
      const same = (left[element] || 0) === (right[element] || 0);
      row.classList.toggle('is-balanced', same);
      appendTextElement(row, 'span', 'weibei-reaction-element-name', element);
      appendTextElement(row, 'span', 'weibei-reaction-element-count', `${left[element] || 0} / ${right[element] || 0}`);
      balance.appendChild(row);
    });
    if (emit) {
      postInteractiveAction(root, action, {
        coefficients,
        balanced: model.elements.every((element) => (left[element] || 0) === (right[element] || 0)),
      }, source);
    }
    reportContentHeight();
  };
  model.species.forEach((species, index) => {
    const item = document.createElement('div');
    item.className = 'weibei-reaction-species';
    item.dataset.side = species.side;
    const minus = document.createElement('button');
    minus.type = 'button';
    minus.className = 'weibei-reaction-stepper weibei-reaction-minus';
    minus.textContent = '-';
    minus.setAttribute('aria-label', `${species.label} -1`);
    item.appendChild(minus);
    const value = appendTextElement(item, 'span', 'weibei-reaction-coefficient', String(species.coefficient));
    const plus = document.createElement('button');
    plus.type = 'button';
    plus.className = 'weibei-reaction-stepper weibei-reaction-plus';
    plus.textContent = '+';
    plus.setAttribute('aria-label', `${species.label} +1`);
    item.appendChild(plus);
    appendTextElement(item, 'span', 'weibei-reaction-label', species.label);
    const change = (delta) => {
      coefficients[index] = Math.max(1, Math.min(9, coefficients[index] + delta));
      sourceRoot.textContent = '';
      if (species.source) appendInlineSourceButton(sourceRoot, species.source);
      renderBalance(true, delta > 0 ? 'increase-coefficient' : 'decrease-coefficient', species.source);
    };
    minus.addEventListener('click', () => change(-1));
    plus.addEventListener('click', () => change(1));
    speciesButtons.push({ value, index });
    (species.side === 'reactant' ? reactants : products).appendChild(item);
  });
  equation.appendChild(reactants);
  appendTextElement(equation, 'div', 'weibei-reaction-arrow', '->');
  equation.appendChild(products);
  root.appendChild(equation);
  root.appendChild(balance);
  root.appendChild(sourceRoot);
  renderBalance();
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiAlgorithmTrace = (model) => {
  const root = createWeiBeiInteractiveRoot('algorithm-trace', 'weibei-interactive-algorithm-trace');
  root.setAttribute('aria-label', model.title);
  appendTextElement(root, 'div', 'weibei-algorithm-title', model.title);
  const code = document.createElement('ol');
  code.className = 'weibei-algorithm-code';
  code.setAttribute('aria-label', model.title);
  const lines = model.codeLines.map((line) => appendTextElement(code, 'li', 'weibei-algorithm-line', line));
  const stepRoot = document.createElement('div');
  stepRoot.className = 'weibei-algorithm-step';
  const progress = appendTextElement(root, 'div', 'weibei-algorithm-progress', '');
  let stepIndex = 0;
  const renderStep = (emit = false, action = 'select-step') => {
    const step = model.steps[stepIndex];
    lines.forEach((line, index) => line.classList.toggle('is-active', index === step.lineIndex));
    stepRoot.textContent = '';
    appendTextElement(stepRoot, 'div', 'weibei-algorithm-step-title', step.summary);
    if (step.note) appendTextElement(stepRoot, 'div', 'weibei-algorithm-step-note', step.note);
    if (step.source) appendInlineSourceButton(stepRoot, step.source);
    progress.textContent = `${stepIndex + 1} / ${model.steps.length}`;
    previous.disabled = stepIndex === 0;
    next.disabled = stepIndex === model.steps.length - 1;
    if (emit) postInteractiveAction(root, action, { stepIndex, lineIndex: step.lineIndex }, step.source);
    reportContentHeight();
  };
  const controls = document.createElement('div');
  controls.className = 'weibei-algorithm-controls';
  const previous = document.createElement('button');
  previous.type = 'button';
  previous.className = 'weibei-algorithm-action';
  previous.textContent = editorLabel('interactivePrevious');
  previous.addEventListener('click', () => {
    stepIndex = Math.max(0, stepIndex - 1);
    renderStep(true, 'previous-step');
  });
  const next = document.createElement('button');
  next.type = 'button';
  next.className = 'weibei-algorithm-action';
  next.textContent = editorLabel('interactiveNext');
  next.addEventListener('click', () => {
    stepIndex = Math.min(model.steps.length - 1, stepIndex + 1);
    renderStep(true, 'next-step');
  });
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.className = 'weibei-algorithm-action';
  reset.textContent = editorLabel('interactiveReset');
  reset.addEventListener('click', () => {
    stepIndex = 0;
    renderStep(true, 'reset-trace');
  });
  controls.appendChild(previous);
  controls.appendChild(next);
  controls.appendChild(reset);
  root.appendChild(code);
  root.appendChild(stepRoot);
  root.appendChild(controls);
  renderStep();
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiLanguageAligner = (model) => {
  const root = createWeiBeiInteractiveRoot('language-aligner', 'weibei-interactive-language-aligner');
  root.setAttribute('aria-label', model.title);
  appendTextElement(root, 'div', 'weibei-language-title', model.title);
  const pairsRoot = document.createElement('div');
  pairsRoot.className = 'weibei-language-pairs';
  const note = document.createElement('div');
  note.className = 'weibei-language-note';
  const buttons = [];
  const activate = (index) => {
    const pair = model.pairs[index];
    buttons.forEach((button, buttonIndex) => button.setAttribute('aria-pressed', buttonIndex === index ? 'true' : 'false'));
    note.textContent = '';
    appendTextElement(note, 'div', 'weibei-language-note-source', pair.sourceText);
    appendTextElement(note, 'div', 'weibei-language-note-target', pair.targetText);
    appendTextElement(note, 'div', 'weibei-language-note-body', pair.note);
    if (pair.source) appendInlineSourceButton(note, pair.source);
    postInteractiveAction(root, 'select-pair', { index, label: pair.label }, pair.source);
    reportContentHeight();
  };
  model.pairs.forEach((pair, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-language-pair';
    button.setAttribute('aria-pressed', 'false');
    appendTextElement(button, 'span', 'weibei-language-pair-label', pair.label);
    appendTextElement(button, 'span', 'weibei-language-source-text', pair.sourceText);
    appendTextElement(button, 'span', 'weibei-language-target-text', pair.targetText);
    button.addEventListener('click', () => activate(index));
    buttons.push(button);
    pairsRoot.appendChild(button);
  });
  root.appendChild(pairsRoot);
  root.appendChild(note);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiArgumentMap = (model) => {
  const root = createWeiBeiInteractiveRoot('argument-map', 'weibei-interactive-argument-map');
  root.setAttribute('aria-label', model.title);
  appendTextElement(root, 'div', 'weibei-argument-title', model.title);
  if (model.question) appendTextElement(root, 'div', 'weibei-argument-question', model.question);
  const nodesRoot = document.createElement('div');
  nodesRoot.className = 'weibei-argument-nodes';
  const detail = document.createElement('div');
  detail.className = 'weibei-argument-detail';
  const buttons = [];
  const activate = (index) => {
    const node = model.nodes[index];
    buttons.forEach((button, buttonIndex) => button.setAttribute('aria-pressed', buttonIndex === index ? 'true' : 'false'));
    detail.textContent = '';
    appendTextElement(detail, 'div', 'weibei-argument-detail-type', node.type);
    appendTextElement(detail, 'div', 'weibei-argument-detail-label', node.label);
    if (node.detail) appendTextElement(detail, 'div', 'weibei-argument-detail-body', node.detail);
    if (node.source) appendInlineSourceButton(detail, node.source);
    postInteractiveAction(root, 'select-node', { id: node.id, type: node.type }, node.source);
    reportContentHeight();
  };
  model.nodes.forEach((node, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-argument-node';
    button.dataset.argumentType = node.type;
    button.setAttribute('aria-pressed', 'false');
    appendTextElement(button, 'span', 'weibei-argument-node-type', node.type);
    appendTextElement(button, 'span', 'weibei-argument-node-label', node.label);
    button.addEventListener('click', () => activate(index));
    buttons.push(button);
    nodesRoot.appendChild(button);
  });
  const edgesRoot = document.createElement('div');
  edgesRoot.className = 'weibei-argument-edges';
  const labels = new Map(model.nodes.map((node) => [node.id, node.label]));
  model.edges.forEach((edge) => {
    const row = document.createElement('div');
    row.className = 'weibei-argument-edge';
    appendTextElement(row, 'span', 'weibei-argument-edge-from', labels.get(edge.from) || edge.from);
    appendTextElement(row, 'span', 'weibei-argument-edge-arrow', '->');
    appendTextElement(row, 'span', 'weibei-argument-edge-to', labels.get(edge.to) || edge.to);
    if (edge.label) appendTextElement(row, 'span', 'weibei-argument-edge-label', edge.label);
    edgesRoot.appendChild(row);
  });
  root.appendChild(nodesRoot);
  root.appendChild(edgesRoot);
  root.appendChild(detail);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiVisualAnalysis = (model) => {
  const root = createWeiBeiInteractiveRoot('visual-analysis', 'weibei-interactive-visual-analysis');
  root.setAttribute('aria-label', model.title);
  appendTextElement(root, 'div', 'weibei-visual-analysis-title', model.title);
  const surface = createSVGElement('svg');
  surface.classList.add('weibei-visual-analysis-surface');
  surface.setAttribute('viewBox', '0 0 150 100');
  surface.setAttribute('role', 'img');
  surface.setAttribute('aria-label', model.title);
  const zoneMarks = new Map();
  model.zones.forEach((zone) => {
    const mark = appendSVGElement(surface, 'rect', {
      x: zone.x * 1.5,
      y: zone.y,
      width: zone.width * 1.5,
      height: zone.height,
      class: 'weibei-visual-analysis-zone',
      fill: interactiveToneColor(zone.tone),
    });
    appendSVGTitle(mark, zone.label);
    zoneMarks.set(zone.id, mark);
  });
  root.appendChild(surface);
  const lensRoot = document.createElement('div');
  lensRoot.className = 'weibei-visual-analysis-lenses';
  const zoneRoot = document.createElement('div');
  zoneRoot.className = 'weibei-visual-analysis-zones';
  const paletteRoot = document.createElement('div');
  paletteRoot.className = 'weibei-visual-analysis-palette';
  const detail = document.createElement('div');
  detail.className = 'weibei-visual-analysis-detail';
  const setActiveZones = (ids) => {
    zoneMarks.forEach((mark, id) => {
      mark.classList.toggle('is-active', ids.includes(id));
      mark.classList.toggle('is-muted', ids.length > 0 && !ids.includes(id));
    });
  };
  model.lenses.forEach((lens) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-visual-analysis-lens';
    button.setAttribute('aria-pressed', 'false');
    button.textContent = lens.label;
    button.addEventListener('click', () => {
      const active = button.getAttribute('aria-pressed') !== 'true';
      lensRoot.querySelectorAll('button').forEach((item) => item.setAttribute('aria-pressed', 'false'));
      button.setAttribute('aria-pressed', active ? 'true' : 'false');
      setActiveZones(active ? lens.zoneIds : []);
      detail.textContent = active ? lens.note : '';
      postInteractiveAction(root, active ? 'select-lens' : 'clear-lens', { id: lens.id, zoneIds: active ? lens.zoneIds : [] }, model.sources[0]);
      reportContentHeight();
    });
    lensRoot.appendChild(button);
  });
  model.zones.forEach((zone) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-visual-analysis-zone-button';
    button.setAttribute('aria-pressed', 'false');
    button.textContent = zone.label;
    button.addEventListener('click', () => {
      zoneRoot.querySelectorAll('button').forEach((item) => item.setAttribute('aria-pressed', item === button ? 'true' : 'false'));
      setActiveZones([zone.id]);
      detail.textContent = '';
      appendTextElement(detail, 'div', 'weibei-visual-analysis-zone-title', zone.label);
      appendTextElement(detail, 'div', 'weibei-visual-analysis-zone-note', zone.note);
      if (zone.source) appendInlineSourceButton(detail, zone.source);
      postInteractiveAction(root, 'select-zone', { id: zone.id, label: zone.label }, zone.source);
      reportContentHeight();
    });
    zoneRoot.appendChild(button);
  });
  model.palette.forEach((item) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-visual-analysis-palette-item';
    button.setAttribute('aria-pressed', 'false');
    button.style.setProperty('--weibei-interactive-tone', interactiveToneColor(item.tone));
    appendTextElement(button, 'span', 'weibei-visual-analysis-palette-label', item.label);
    appendTextElement(button, 'span', 'weibei-visual-analysis-palette-role', item.role);
    button.addEventListener('click', () => {
      paletteRoot.querySelectorAll('button').forEach((candidate) => candidate.setAttribute('aria-pressed', candidate === button ? 'true' : 'false'));
      detail.textContent = `${item.label} ${item.role}`;
      postInteractiveAction(root, 'select-palette', { label: item.label, role: item.role });
      reportContentHeight();
    });
    paletteRoot.appendChild(button);
  });
  root.appendChild(lensRoot);
  root.appendChild(zoneRoot);
  root.appendChild(paletteRoot);
  root.appendChild(detail);
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiSpatialLayers = (model) => {
  const root = createWeiBeiInteractiveRoot('spatial-layers', 'weibei-interactive-spatial-layers');
  root.setAttribute('aria-label', model.title);
  appendTextElement(root, 'div', 'weibei-spatial-title', model.title);
  const surface = createSVGElement('svg');
  surface.classList.add('weibei-spatial-surface');
  surface.setAttribute('viewBox', '0 0 150 100');
  surface.setAttribute('role', 'img');
  surface.setAttribute('aria-label', model.title);
  const layerGroups = new Map();
  model.layers.forEach((layer) => {
    const group = appendSVGElement(surface, 'g', { class: 'weibei-spatial-layer', 'data-layer-id': layer.id });
    layerGroups.set(layer.id, group);
  });
  model.features.forEach((feature) => {
    const group = layerGroups.get(feature.layerId);
    if (!group) return;
    if (feature.type === 'point') {
      const point = feature.points[0];
      const mark = appendSVGElement(group, 'circle', {
        cx: point.x * 1.5,
        cy: point.y,
        r: 2.4,
        class: 'weibei-spatial-point',
      });
      appendSVGTitle(mark, feature.label);
    } else if (feature.type === 'route') {
      const path = feature.points.map((point, index) => `${index === 0 ? 'M' : 'L'}${point.x * 1.5} ${point.y}`).join(' ');
      const mark = appendSVGElement(group, 'path', {
        d: path,
        class: 'weibei-spatial-route',
        fill: 'none',
      });
      appendSVGTitle(mark, feature.label);
    } else {
      const points = feature.points.map((point) => `${point.x * 1.5},${point.y}`).join(' ');
      const mark = appendSVGElement(group, 'polygon', {
        points,
        class: 'weibei-spatial-region',
      });
      appendSVGTitle(mark, feature.label);
    }
  });
  root.appendChild(surface);
  const toolbar = document.createElement('div');
  toolbar.className = 'weibei-spatial-toolbar';
  const list = document.createElement('div');
  list.className = 'weibei-spatial-features';
  const detail = document.createElement('div');
  detail.className = 'weibei-spatial-detail';
  const activeLayers = new Set(model.layers.filter((layer) => layer.visible).map((layer) => layer.id));
  const renderLayers = () => {
    layerGroups.forEach((group, id) => {
      group.classList.toggle('is-hidden-layer', !activeLayers.has(id));
    });
    list.querySelectorAll('.weibei-spatial-feature').forEach((button) => {
      button.hidden = !activeLayers.has(button.dataset.layerId);
    });
  };
  model.layers.forEach((layer) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-spatial-layer-toggle';
    button.textContent = layer.label;
    button.setAttribute('aria-pressed', layer.visible ? 'true' : 'false');
    button.addEventListener('click', () => {
      if (activeLayers.has(layer.id)) activeLayers.delete(layer.id); else activeLayers.add(layer.id);
      button.setAttribute('aria-pressed', activeLayers.has(layer.id) ? 'true' : 'false');
      renderLayers();
      postInteractiveAction(root, 'toggle-layer', { id: layer.id, visible: activeLayers.has(layer.id) });
      reportContentHeight();
    });
    toolbar.appendChild(button);
  });
  model.features.forEach((feature) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-spatial-feature';
    button.dataset.layerId = feature.layerId;
    button.setAttribute('aria-pressed', 'false');
    appendTextElement(button, 'span', 'weibei-spatial-feature-type', feature.type);
    appendTextElement(button, 'span', 'weibei-spatial-feature-label', feature.label);
    button.addEventListener('click', () => {
      list.querySelectorAll('.weibei-spatial-feature').forEach((candidate) => candidate.setAttribute('aria-pressed', candidate === button ? 'true' : 'false'));
      detail.textContent = '';
      appendTextElement(detail, 'div', 'weibei-spatial-detail-title', feature.label);
      if (feature.note) appendTextElement(detail, 'div', 'weibei-spatial-detail-note', feature.note);
      if (feature.source) appendInlineSourceButton(detail, feature.source);
      postInteractiveAction(root, 'select-feature', { id: feature.id, type: feature.type, layerId: feature.layerId }, feature.source);
      reportContentHeight();
    });
    list.appendChild(button);
  });
  root.appendChild(toolbar);
  root.appendChild(list);
  root.appendChild(detail);
  renderLayers();
  appendInteractiveSources(root, model.sources);
  return root;
};

const renderWeiBeiPathwayLab = (model) => {
  const root = createWeiBeiInteractiveRoot('pathway-lab', 'weibei-interactive-pathway-lab');
  root.setAttribute('aria-label', model.title);
  appendTextElement(root, 'div', 'weibei-pathway-title', model.title);
  const statesRoot = document.createElement('div');
  statesRoot.className = 'weibei-pathway-states';
  const mapRoot = document.createElement('div');
  mapRoot.className = 'weibei-pathway-map';
  mapRoot.setAttribute('role', 'group');
  mapRoot.setAttribute('aria-label', model.title);
  const detail = document.createElement('div');
  detail.className = 'weibei-pathway-detail';
  const nodeButtons = new Map();
  const stateButtons = [];
  const labels = new Map(model.nodes.map((node) => [node.id, node.label]));
  const activateState = (index, emit = true) => {
    const state = model.states[index];
    const active = new Set(state.activeNodeIds);
    stateButtons.forEach((button, buttonIndex) => button.setAttribute('aria-pressed', buttonIndex === index ? 'true' : 'false'));
    nodeButtons.forEach((button, id) => {
      button.classList.toggle('is-active', active.has(id));
      button.classList.toggle('is-muted', !active.has(id));
      button.setAttribute('aria-pressed', active.has(id) ? 'true' : 'false');
    });
    detail.textContent = '';
    appendTextElement(detail, 'div', 'weibei-pathway-state-label', state.label);
    if (state.note) appendTextElement(detail, 'div', 'weibei-pathway-state-note', state.note);
    if (state.source) appendInlineSourceButton(detail, state.source);
    if (emit) postInteractiveAction(root, 'select-state', { id: state.id, activeNodeIds: state.activeNodeIds }, state.source);
    reportContentHeight();
  };
  model.states.forEach((state, index) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-pathway-state';
    button.setAttribute('aria-pressed', 'false');
    button.textContent = state.label;
    button.addEventListener('click', () => activateState(index));
    stateButtons.push(button);
    statesRoot.appendChild(button);
  });
  model.nodes.forEach((node) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'weibei-pathway-node';
    button.dataset.nodeId = node.id;
    button.setAttribute('aria-pressed', 'false');
    appendTextElement(button, 'span', 'weibei-pathway-node-label', node.label);
    if (node.detail) appendTextElement(button, 'span', 'weibei-pathway-node-detail', node.detail);
    button.addEventListener('click', () => {
      detail.textContent = '';
      appendTextElement(detail, 'div', 'weibei-pathway-node-title', node.label);
      if (node.detail) appendTextElement(detail, 'div', 'weibei-pathway-node-note', node.detail);
      if (node.source) appendInlineSourceButton(detail, node.source);
      postInteractiveAction(root, 'select-node', { id: node.id }, node.source);
      reportContentHeight();
    });
    nodeButtons.set(node.id, button);
    mapRoot.appendChild(button);
  });
  const edgesRoot = document.createElement('div');
  edgesRoot.className = 'weibei-pathway-edges';
  model.edges.forEach((edge) => {
    const row = document.createElement('div');
    row.className = 'weibei-pathway-edge';
    appendTextElement(row, 'span', 'weibei-pathway-edge-from', labels.get(edge.from) || edge.from);
    appendTextElement(row, 'span', 'weibei-pathway-edge-arrow', '->');
    appendTextElement(row, 'span', 'weibei-pathway-edge-to', labels.get(edge.to) || edge.to);
    if (edge.label) appendTextElement(row, 'span', 'weibei-pathway-edge-label', edge.label);
    edgesRoot.appendChild(row);
  });
  root.appendChild(statesRoot);
  root.appendChild(mapRoot);
  root.appendChild(edgesRoot);
  root.appendChild(detail);
  activateState(0, false);
  appendInteractiveSources(root, model.sources);
  return root;
};

const weiBeiInteractiveRegistry = {
  'quiz': {
    parse(value) {
      const prompt = safeInteractiveString(value.prompt);
      const explanation = safeInteractiveString(value.explanation, MAX_INTERACTIVE_CONTENT_LENGTH);
      const options = safeInteractiveArray(value.options, MAX_INTERACTIVE_OPTIONS)
        ?.map((option) => safeInteractiveString(option, MAX_INTERACTIVE_OPTION_LENGTH)) || [];
      const correctIndex = safeInteractiveInteger(value.correctIndex, 0, options.length - 1);
      const sources = safeInteractiveSources(value);
      if (!prompt || !explanation || options.length < 2 || options.some((option) => !option) || correctIndex === null || !sources) return null;
      return { kind: 'quiz', prompt, options, correctIndex, explanation, sources, source: sources[0] || '' };
    },
    render: renderWeiBeiQuiz,
  },
  'reveal': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const content = safeInteractiveString(value.content, MAX_INTERACTIVE_CONTENT_LENGTH);
      const sources = safeInteractiveSources(value);
      if (!title || !content || !sources) return null;
      return { kind: 'reveal', title, content, sources, source: sources[0] || '' };
    },
    render: renderWeiBeiReveal,
  },
  'chart': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const chartType = value.chartType === undefined ? 'line' : safeInteractiveString(value.chartType, 20);
      const xLabel = safeInteractiveString(value.xLabel || 'x', 80);
      const yLabel = safeInteractiveString(value.yLabel || 'y', 80);
      const rawSeries = safeInteractiveArray(value.series, MAX_INTERACTIVE_SERIES);
      const sources = safeInteractiveSources(value);
      if (!title || !['line', 'bar', 'scatter', 'area'].includes(chartType) || !xLabel || !yLabel || !rawSeries || rawSeries.length < 1 || !sources) return null;
      const series = rawSeries.map((item) => {
        const name = safeInteractiveString(item?.name, 80);
        const tone = safeOptionalInteractiveTone(item?.tone, 'cinnabar');
        const points = safeInteractiveChartPoints(item?.points, chartType === 'area' || chartType === 'line' ? 2 : 1);
        return name && tone && points ? { name, tone, points } : null;
      });
      if (series.some((item) => !item)) return null;
      const normalized = normalizeChartSeries(series);
      if (!normalized) return null;
      if (normalized.xMode === 'category' && normalized.categories.length > MAX_INTERACTIVE_CATEGORIES) return null;
      const pointGroups = normalized.series.map((item) => item.points);
      const xDomain = normalized.xMode === 'category'
        ? [-0.5, normalized.categories.length - 0.5]
        : safeInteractiveDomain(value.xDomain, extentForPoints(pointGroups, 'plotX', [0, 1]));
      const yDomain = safeInteractiveDomain(value.yDomain, yExtentForChart(pointGroups, chartType));
      if (!xDomain || !yDomain) return null;
      return {
        kind: 'chart',
        title,
        chartType,
        xLabel,
        yLabel,
        series: normalized.series,
        xDomain,
        yDomain,
        sources,
        xMode: normalized.xMode,
        categories: normalized.categories,
      };
    },
    render: renderWeiBeiChart,
  },
  'function-plot': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const xLabel = safeInteractiveString(value.xLabel || 'x', 80);
      const yLabel = safeInteractiveString(value.yLabel || 'y', 80);
      const rawCurves = safeInteractiveArray(value.curves, MAX_INTERACTIVE_SERIES);
      const sources = safeInteractiveSources(value);
      if (!title || !xLabel || !yLabel || !rawCurves || rawCurves.length < 1 || !sources) return null;
      const curves = rawCurves.map((item) => {
        const name = safeInteractiveString(item?.name, 80);
        const formulaLabel = safeInteractiveString(item?.formulaLabel, 120);
        const tone = safeOptionalInteractiveTone(item?.tone, 'blue-ink');
        const points = safeInteractivePoints(item?.points);
        return name && formulaLabel && tone && points ? { name, formulaLabel, tone, points } : null;
      });
      if (curves.some((item) => !item)) return null;
      const pointGroups = curves.map((item) => item.points);
      const xDomain = safeInteractiveDomain(value.xDomain, extentForPoints(pointGroups, 'x', [-1, 1]));
      const yDomain = safeInteractiveDomain(value.yDomain, extentForPoints(pointGroups, 'y', [-1, 1]));
      if (!xDomain || !yDomain) return null;
      return { kind: 'function-plot', title, xLabel, yLabel, curves, xDomain, yDomain, sources };
    },
    render: renderWeiBeiFunctionPlot,
  },
  'parameter-lab': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const family = safeInteractiveString(value.family, 40);
      const xDomain = safeInteractiveDomain(value.xDomain, [-5, 5]);
      const yDomain = safeInteractiveDomain(value.yDomain, [-5, 5]);
      const rawControls = safeInteractiveArray(value.controls, MAX_INTERACTIVE_CONTROLS);
      const sources = safeInteractiveSources(value);
      const tone = safeOptionalInteractiveTone(value.tone, 'cinnabar');
      const xLabel = safeInteractiveString(value.xLabel || 'x', 80);
      const yLabel = safeInteractiveString(value.yLabel || 'y', 80);
      if (!title || !family || !interactiveFunctionFamilies[family] || !xDomain || !yDomain || !rawControls || rawControls.length < 1 || !sources || !tone || !xLabel || !yLabel) return null;
      const allowedKeys = interactiveFunctionParameterKeys[family];
      const keys = new Set();
      const controls = rawControls.map((control) => {
        const key = safeInteractiveString(control?.key, 20);
        const label = safeInteractiveString(control?.label, 80);
        const min = safeInteractiveNumber(control?.min, -1000, 1000);
        const max = safeInteractiveNumber(control?.max, -1000, 1000);
        const step = safeInteractiveNumber(control?.step, 0.0001, 1000);
        const numberValue = safeInteractiveNumber(control?.value, -1000, 1000);
        if (!key || !allowedKeys.has(key) || keys.has(key) || !label || min === null || max === null || step === null || numberValue === null || min >= max || numberValue < min || numberValue > max) return null;
        keys.add(key);
        return { key, label, min, max, step, value: numberValue };
      });
      if (controls.some((control) => !control)) return null;
      return { kind: 'parameter-lab', title, family, xDomain, yDomain, controls, sources, tone, xLabel, yLabel };
    },
    render: renderWeiBeiParameterLab,
  },
  'text-study': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawVariants = safeInteractiveArray(value.variants, MAX_INTERACTIVE_VARIANTS);
      const rawTerms = safeInteractiveArray(value.highlightTerms || [], MAX_INTERACTIVE_OPTIONS);
      const sources = safeInteractiveSources(value);
      if (!title || !rawVariants || rawVariants.length < 1 || !rawTerms || !sources) return null;
      const variants = rawVariants.map((variant) => {
        const label = safeInteractiveString(variant?.label, 80);
        const text = safeInteractiveString(variant?.text, MAX_INTERACTIVE_CONTENT_LENGTH);
        const note = safeInteractiveString(variant?.note, MAX_INTERACTIVE_CONTENT_LENGTH);
        return label && text && note ? { label, text, note } : null;
      });
      const highlightTerms = rawTerms.map((term) => safeInteractiveString(term, 80));
      if (variants.some((variant) => !variant) || highlightTerms.some((term) => !term)) return null;
      return { kind: 'text-study', title, variants, highlightTerms, sources };
    },
    render: renderWeiBeiTextStudy,
  },
  'design-compare': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawVariants = safeInteractiveArray(value.variants, MAX_INTERACTIVE_VARIANTS);
      const sources = safeInteractiveSources(value);
      if (!title || !rawVariants || rawVariants.length < 1 || !sources) return null;
      const variants = rawVariants.map((variant) => {
        const label = safeInteractiveString(variant?.label, 80);
        const headline = safeInteractiveString(variant?.headline, 120);
        const body = safeInteractiveString(variant?.body, MAX_INTERACTIVE_CONTENT_LENGTH);
        const treatment = safeOptionalInteractiveTreatment(variant?.treatment, 'compact');
        const tone = safeOptionalInteractiveTone(variant?.tone, 'cinnabar');
        return label && headline && body && treatment && tone ? { label, headline, body, treatment, tone } : null;
      });
      if (variants.some((variant) => !variant)) return null;
      return { kind: 'design-compare', title, variants, sources };
    },
    render: renderWeiBeiDesignCompare,
  },
  'palette': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const previewText = safeInteractiveString(value.previewText, MAX_INTERACTIVE_CONTENT_LENGTH);
      const rawColors = safeInteractiveArray(value.colors, MAX_INTERACTIVE_COLORS);
      const sources = safeInteractiveSources(value);
      if (!title || !previewText || !rawColors || rawColors.length < 1 || !sources) return null;
      const colors = rawColors.map((color) => {
        const name = safeInteractiveString(color?.name, 80);
        const role = safeInteractiveString(color?.role, 120);
        const hex = safeInteractiveHex(color?.value);
        return name && role && hex ? { name, role, value: hex } : null;
      });
      if (colors.some((color) => !color)) return null;
      return { kind: 'palette', title, previewText, colors, sources };
    },
    render: renderWeiBeiPalette,
  },
  'study-board': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const summary = safeOptionalInteractiveString(value.summary, MAX_INTERACTIVE_CONTENT_LENGTH);
      const layout = safeInteractiveStudyBoardLayout(value.layout);
      const treatment = safeInteractiveTreatment(value.treatment);
      const rawMetrics = value.metrics === undefined ? [] : safeInteractiveArray(value.metrics, MAX_INTERACTIVE_METRICS);
      const rawItems = safeInteractiveArray(value.items, MAX_INTERACTIVE_BOARD_ITEMS);
      const sources = safeInteractiveSources(value);
      if (!title || summary === null || !layout || !treatment || !rawMetrics || !rawItems || rawItems.length < 1 || !sources) return null;
      const metrics = rawMetrics.map((metric) => {
        const label = safeInteractiveString(metric?.label, 80);
        const valueText = safeInteractiveString(metric?.value, 120);
        const note = safeOptionalInteractiveString(metric?.note, 160);
        const tone = safeOptionalInteractiveTone(metric?.tone, 'cinnabar');
        return label && valueText && note !== null && tone ? { label, value: valueText, note, tone } : null;
      });
      const items = rawItems.map((item) => {
        const kicker = safeOptionalInteractiveString(item?.kicker, 80);
        const titleText = safeInteractiveString(item?.title, 140);
        const body = safeInteractiveString(item?.body, MAX_INTERACTIVE_CONTENT_LENGTH);
        const status = safeOptionalInteractiveString(item?.status, 80);
        const tone = safeOptionalInteractiveTone(item?.tone, 'ink');
        const source = safeOptionalInteractiveString(item?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return kicker !== null && titleText && body && status !== null && tone && source !== null
          ? { kicker, title: titleText, body, status, tone, source }
          : null;
      });
      if (metrics.some((metric) => !metric) || items.some((item) => !item)) return null;
      return { kind: 'study-board', title, summary, layout, treatment, metrics, items, sources };
    },
    render: renderWeiBeiStudyBoard,
  },
  'relationship-map': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const layout = safeInteractiveRelationshipLayout(value.layout);
      const rawNodes = safeInteractiveArray(value.nodes, MAX_INTERACTIVE_MAP_NODES);
      const rawEdges = value.edges === undefined ? [] : safeInteractiveArray(value.edges, MAX_INTERACTIVE_MAP_EDGES);
      const sources = safeInteractiveSources(value);
      if (!title || !layout || !rawNodes || rawNodes.length < 1 || !rawEdges || !sources) return null;
      const ids = new Set();
      const nodes = rawNodes.map((node) => {
        const id = safeInteractiveString(node?.id, 48);
        const label = safeInteractiveString(node?.label, 120);
        const detail = safeOptionalInteractiveString(node?.detail, MAX_INTERACTIVE_CONTENT_LENGTH);
        const tone = safeOptionalInteractiveTone(node?.tone, 'ink');
        const source = safeOptionalInteractiveString(node?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || ids.has(id) || !label || detail === null || !tone || source === null) return null;
        ids.add(id);
        return { id, label, detail, tone, source };
      });
      if (nodes.some((node) => !node)) return null;
      const edges = rawEdges.map((edge) => {
        const from = safeInteractiveString(edge?.from, 48);
        const to = safeInteractiveString(edge?.to, 48);
        const label = safeOptionalInteractiveString(edge?.label, 120);
        return from && to && from !== to && ids.has(from) && ids.has(to) && label !== null ? { from, to, label } : null;
      });
      if (edges.some((edge) => !edge)) return null;
      return { kind: 'relationship-map', title, layout, nodes, edges, sources };
    },
    render: renderWeiBeiRelationshipMap,
  },
  'timeline': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawEvents = safeInteractiveArray(value.events, MAX_INTERACTIVE_TIMELINE_EVENTS);
      const sources = safeInteractiveSources(value);
      if (!title || !rawEvents || rawEvents.length < 1 || !sources) return null;
      const events = rawEvents.map((event) => {
        const label = safeInteractiveString(event?.label, 80);
        const titleText = safeInteractiveString(event?.title, 140);
        const detail = safeOptionalInteractiveString(event?.detail, MAX_INTERACTIVE_CONTENT_LENGTH);
        const tone = safeOptionalInteractiveTone(event?.tone, 'ink');
        const source = safeOptionalInteractiveString(event?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return label && titleText && detail !== null && tone && source !== null
          ? { label, title: titleText, detail, tone, source }
          : null;
      });
      if (events.some((event) => !event)) return null;
      return { kind: 'timeline', title, events, sources };
    },
    render: renderWeiBeiTimeline,
  },
  'comparison-matrix': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawColumns = safeInteractiveArray(value.columns, MAX_INTERACTIVE_MATRIX_COLUMNS);
      const rawRows = safeInteractiveArray(value.rows, MAX_INTERACTIVE_MATRIX_ROWS);
      const sources = safeInteractiveSources(value);
      if (!title || !rawColumns || rawColumns.length < 2 || !rawRows || rawRows.length < 1 || !sources) return null;
      const columns = rawColumns.map((column) => safeInteractiveString(column, 80));
      if (columns.some((column) => !column)) return null;
      const rows = rawRows.map((row) => {
        const label = safeInteractiveString(row?.label, 120);
        const rawValues = Array.isArray(row?.values) && row.values.length === columns.length
          ? row.values
          : null;
        const values = rawValues?.map((item) => safeInteractiveString(item, MAX_INTERACTIVE_CONTENT_LENGTH)) || null;
        const hasEmphasis = row?.emphasisIndex !== undefined;
        const emphasisIndex = hasEmphasis ? safeInteractiveInteger(row.emphasisIndex, 0, columns.length - 1) : null;
        return label && values && values.every(Boolean) && (!hasEmphasis || emphasisIndex !== null)
          ? { label, values, emphasisIndex }
          : null;
      });
      if (rows.some((row) => !row)) return null;
      return { kind: 'comparison-matrix', title, columns, rows, sources };
    },
    render: renderWeiBeiComparisonMatrix,
  },
  'annotated-passage': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const text = safeInteractiveString(value.text, MAX_INTERACTIVE_CONTENT_LENGTH);
      const rawAnnotations = safeInteractiveArray(value.annotations, MAX_INTERACTIVE_ANNOTATIONS);
      const sources = safeInteractiveSources(value);
      if (!title || !text || !rawAnnotations || rawAnnotations.length < 1 || !sources) return null;
      const terms = new Set();
      const annotations = rawAnnotations.map((annotation) => {
        const term = safeInteractiveString(annotation?.term, 120);
        const note = safeInteractiveString(annotation?.note, MAX_INTERACTIVE_CONTENT_LENGTH);
        const tone = safeOptionalInteractiveTone(annotation?.tone, 'cinnabar');
        const source = safeOptionalInteractiveString(annotation?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!term || terms.has(term) || !text.includes(term) || !note || !tone || source === null) return null;
        terms.add(term);
        return { term, note, tone, source };
      });
      if (annotations.some((annotation) => !annotation)) return null;
      return { kind: 'annotated-passage', title, text, annotations, sources };
    },
    render: renderWeiBeiAnnotatedPassage,
  },
  'derivation-steps': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const prompt = safeOptionalInteractiveString(value.prompt, MAX_INTERACTIVE_CONTENT_LENGTH);
      const rawSteps = safeInteractiveArray(value.steps, MAX_INTERACTIVE_DERIVATION_STEPS);
      const sources = safeInteractiveSources(value);
      if (!title || prompt === null || !rawSteps || rawSteps.length < 2 || !sources) return null;
      const steps = rawSteps.map((step) => {
        const label = safeInteractiveString(step?.label, 80);
        const statement = safeInteractiveString(step?.statement, MAX_INTERACTIVE_CONTENT_LENGTH);
        const reason = safeOptionalInteractiveString(step?.reason, MAX_INTERACTIVE_CONTENT_LENGTH);
        const source = safeOptionalInteractiveString(step?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return label && statement && reason !== null && source !== null
          ? { label, statement, reason, source }
          : null;
      });
      if (steps.some((step) => !step)) return null;
      return { kind: 'derivation-steps', title, prompt, steps, sources };
    },
    render: renderWeiBeiDerivationSteps,
  },
  'flashcards': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawCards = safeInteractiveArray(value.cards, MAX_INTERACTIVE_FLASHCARDS);
      const sources = safeInteractiveSources(value);
      if (!title || !rawCards || rawCards.length < 2 || !sources) return null;
      const cards = rawCards.map((card) => {
        const front = safeInteractiveString(card?.front, MAX_INTERACTIVE_CONTENT_LENGTH);
        const back = safeInteractiveString(card?.back, MAX_INTERACTIVE_CONTENT_LENGTH);
        const hint = safeOptionalInteractiveString(card?.hint, 240);
        const source = safeOptionalInteractiveString(card?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return front && back && hint !== null && source !== null ? { front, back, hint, source } : null;
      });
      if (cards.some((card) => !card)) return null;
      return { kind: 'flashcards', title, cards, sources };
    },
    render: renderWeiBeiFlashcards,
  },
  'sequence-builder': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const instruction = safeOptionalInteractiveString(value.instruction, MAX_INTERACTIVE_CONTENT_LENGTH);
      const successText = safeInteractiveString(value.successText || '顺序正确。', 240);
      const retryText = safeInteractiveString(value.retryText || '顺序还不对，再试一次。', 240);
      const rawItems = safeInteractiveArray(value.items, MAX_INTERACTIVE_SEQUENCE_ITEMS);
      const rawOrder = safeInteractiveArray(value.correctOrder, MAX_INTERACTIVE_SEQUENCE_ITEMS);
      const sources = safeInteractiveSources(value);
      if (!title || instruction === null || !successText || !retryText || !rawItems || rawItems.length < 2 || !rawOrder || rawOrder.length !== rawItems.length || !sources) return null;
      const ids = new Set();
      const items = rawItems.map((item) => {
        const id = safeInteractiveString(item?.id, 48);
        const label = safeInteractiveString(item?.label, 160);
        const detail = safeOptionalInteractiveString(item?.detail, 300);
        const source = safeOptionalInteractiveString(item?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || ids.has(id) || !label || detail === null || source === null) return null;
        ids.add(id);
        return { id, label, detail, source };
      });
      const correctOrder = rawOrder.map((id) => safeInteractiveString(id, 48));
      if (items.some((item) => !item) || correctOrder.some((id) => !id) || new Set(correctOrder).size !== ids.size || correctOrder.some((id) => !ids.has(id))) return null;
      return { kind: 'sequence-builder', title, instruction, items, correctOrder, successText, retryText, sources };
    },
    render: renderWeiBeiSequenceBuilder,
  },
  'scenario-lab': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawControls = safeInteractiveArray(value.controls, MAX_INTERACTIVE_SCENARIO_CONTROLS);
      const rawOutcomes = safeInteractiveArray(value.outcomes, MAX_INTERACTIVE_SCENARIO_OUTCOMES);
      const sources = safeInteractiveSources(value);
      if (!title || !rawControls || rawControls.length < 1 || !rawOutcomes || rawOutcomes.length < 1 || !sources) return null;
      const ids = new Set();
      const controls = rawControls.map((control) => {
        const id = safeInteractiveString(control?.id, 48);
        const label = safeInteractiveString(control?.label, 120);
        const rawOptions = safeInteractiveArray(control?.options, MAX_INTERACTIVE_SCENARIO_OPTIONS);
        if (!id || ids.has(id) || !label || !rawOptions || rawOptions.length < 2) return null;
        const options = rawOptions.map((option) => safeInteractiveString(option, 100));
        const initialIndex = control?.initialIndex === undefined
          ? 0
          : safeInteractiveInteger(control.initialIndex, 0, options.length - 1);
        if (options.some((option) => !option) || initialIndex === null) return null;
        ids.add(id);
        return { id, label, options, initialIndex };
      });
      if (controls.some((control) => !control)) return null;
      const seen = new Set();
      const outcomes = rawOutcomes.map((outcome) => {
        const rawSelections = Array.isArray(outcome?.selections) && outcome.selections.length === controls.length
          ? outcome.selections
          : null;
        const selections = rawSelections?.map((selection, index) => safeInteractiveInteger(selection, 0, controls[index].options.length - 1)) || null;
        const titleText = safeInteractiveString(outcome?.title, 160);
        const body = safeInteractiveString(outcome?.body, MAX_INTERACTIVE_CONTENT_LENGTH);
        const tone = safeOptionalInteractiveTone(outcome?.tone, 'ink');
        const source = safeOptionalInteractiveString(outcome?.source, MAX_SOURCE_REFERENCE_LENGTH);
        const key = selections?.join(':') || '';
        if (!selections || selections.some((selection) => selection === null) || seen.has(key) || !titleText || !body || !tone || source === null) return null;
        seen.add(key);
        return { selections, title: titleText, body, tone, source };
      });
      if (outcomes.some((outcome) => !outcome)) return null;
      return { kind: 'scenario-lab', title, controls, outcomes, sources };
    },
    render: renderWeiBeiScenarioLab,
  },
  'evidence-board': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const claim = safeInteractiveString(value.claim, MAX_INTERACTIVE_CONTENT_LENGTH);
      const rawItems = safeInteractiveArray(value.items, MAX_INTERACTIVE_EVIDENCE_ITEMS);
      const sources = safeInteractiveSources(value);
      if (!title || !claim || !rawItems || rawItems.length < 1 || !sources) return null;
      const items = rawItems.map((item) => {
        const stance = ['support', 'challenge', 'gap'].includes(item?.stance) ? item.stance : null;
        const titleText = safeInteractiveString(item?.title, 160);
        const detail = safeInteractiveString(item?.detail, MAX_INTERACTIVE_CONTENT_LENGTH);
        const tone = safeOptionalInteractiveTone(item?.tone, stance === 'support' ? 'moss' : stance === 'challenge' ? 'cinnabar' : 'ochre');
        const source = safeOptionalInteractiveString(item?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return stance && titleText && detail && tone && source !== null
          ? { stance, title: titleText, detail, tone, source }
          : null;
      });
      if (items.some((item) => !item)) return null;
      return { kind: 'evidence-board', title, claim, items, sources };
    },
    render: renderWeiBeiEvidenceBoard,
  },
  'spectrum': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const axisStart = safeInteractiveString(value.axisStart, 100);
      const axisEnd = safeInteractiveString(value.axisEnd, 100);
      const rawPoints = safeInteractiveArray(value.points, MAX_INTERACTIVE_SPECTRUM_POINTS);
      const sources = safeInteractiveSources(value);
      if (!title || !axisStart || !axisEnd || !rawPoints || rawPoints.length < 2 || !sources) return null;
      const points = rawPoints.map((point) => {
        const label = safeInteractiveString(point?.label, 120);
        const position = safeInteractiveNumber(point?.position, 0, 100);
        const detail = safeInteractiveString(point?.detail, MAX_INTERACTIVE_CONTENT_LENGTH);
        const tone = safeOptionalInteractiveTone(point?.tone, 'ink');
        const source = safeOptionalInteractiveString(point?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return label && position !== null && detail && tone && source !== null
          ? { label, position, detail, tone, source }
          : null;
      });
      if (points.some((point) => !point)) return null;
      return { kind: 'spectrum', title, axisStart, axisEnd, points, sources };
    },
    render: renderWeiBeiSpectrum,
  },
  'decision-path': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const startID = safeInteractiveString(value.startID, 48);
      const rawNodes = safeInteractiveArray(value.nodes, MAX_INTERACTIVE_DECISION_NODES);
      const sources = safeInteractiveSources(value);
      if (!title || !startID || !rawNodes || rawNodes.length < 2 || !sources) return null;
      const ids = new Set();
      const baseNodes = rawNodes.map((node) => {
        const id = safeInteractiveString(node?.id, 48);
        const titleText = safeInteractiveString(node?.title, 160);
        const body = safeInteractiveString(node?.body, MAX_INTERACTIVE_CONTENT_LENGTH);
        const source = safeOptionalInteractiveString(node?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || ids.has(id) || !titleText || !body || source === null) return null;
        ids.add(id);
        return { id, title: titleText, body, source, rawChoices: node?.choices };
      });
      if (baseNodes.some((node) => !node) || !ids.has(startID)) return null;
      const nodes = baseNodes.map((node) => {
        const rawChoices = safeInteractiveArray(node.rawChoices || [], MAX_INTERACTIVE_DECISION_CHOICES);
        if (!rawChoices) return null;
        const choices = rawChoices.map((choice) => {
          const label = safeInteractiveString(choice?.label, 140);
          const nextID = safeInteractiveString(choice?.nextID, 48);
          return label && nextID && nextID !== node.id && ids.has(nextID) ? { label, nextID } : null;
        });
        return choices.some((choice) => !choice) ? null : { id: node.id, title: node.title, body: node.body, source: node.source, choices };
      });
      if (nodes.some((node) => !node)) return null;
      return { kind: 'decision-path', title, startID, nodes, sources };
    },
    render: renderWeiBeiDecisionPath,
  },
  'unit-workbench': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const question = safeOptionalInteractiveString(value.question, MAX_INTERACTIVE_CONTENT_LENGTH);
      const rawVariables = safeInteractiveArray(value.variables, MAX_INTERACTIVE_UNIT_VARIABLES);
      const rawChecks = value.checks === undefined ? [] : safeInteractiveArray(value.checks, MAX_INTERACTIVE_UNIT_CHECKS);
      const sources = safeInteractiveSources(value);
      if (!title || question === null || !rawVariables || rawVariables.length < 1 || !rawChecks || !sources) return null;
      const ids = new Set();
      const variables = rawVariables.map((variable) => {
        const id = safeInteractiveID(variable?.id);
        const label = safeInteractiveString(variable?.label, 120);
        const valueText = safeInteractiveString(variable?.value, 120);
        const unit = safeInteractiveString(variable?.unit, 80);
        const role = safeOptionalInteractiveString(variable?.role, 160);
        const source = safeOptionalInteractiveString(variable?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || ids.has(id) || !label || !valueText || !unit || role === null || source === null) return null;
        ids.add(id);
        return { id, label, value: valueText, unit, role, source };
      });
      const checks = rawChecks.map((check) => {
        const id = safeInteractiveID(check?.id);
        const label = safeInteractiveString(check?.label, 120);
        const left = safeInteractiveString(check?.left, 180);
        const right = safeInteractiveString(check?.right, 180);
        const result = safeInteractiveString(check?.result, MAX_INTERACTIVE_CONTENT_LENGTH);
        const source = safeOptionalInteractiveString(check?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || !label || !left || !right || !result || source === null) return null;
        return { id, label, left, right, result, source };
      });
      if (variables.some((item) => !item) || checks.some((item) => !item)) return null;
      return { kind: 'unit-workbench', title, question, variables, checks, sources };
    },
    render: renderWeiBeiUnitWorkbench,
  },
  'reaction-balance': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawSpecies = safeInteractiveArray(value.species, MAX_INTERACTIVE_REACTION_SPECIES);
      const sources = safeInteractiveSources(value);
      if (!title || !rawSpecies || rawSpecies.length < 2 || !sources) return null;
      const ids = new Set();
      const species = rawSpecies.map((item) => {
        const id = safeInteractiveID(item?.id);
        const label = safeInteractiveString(item?.label, 120);
        const side = safeInteractiveEnum(item?.side, new Set(['reactant', 'product']));
        const coefficient = safeInteractiveInteger(item?.coefficient === undefined ? 1 : item.coefficient, 1, 9);
        const atoms = safeInteractiveAtoms(item?.atoms);
        const source = safeOptionalInteractiveString(item?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || ids.has(id) || !label || !side || coefficient === null || !atoms || source === null) return null;
        ids.add(id);
        return { id, label, side, coefficient, atoms, source };
      });
      if (species.some((item) => !item)) return null;
      if (!species.some((item) => item.side === 'reactant') || !species.some((item) => item.side === 'product')) return null;
      const elements = Array.from(new Set(species.flatMap((item) => Object.keys(item.atoms)))).sort();
      if (elements.length < 1 || elements.length > MAX_INTERACTIVE_REACTION_ELEMENTS) return null;
      return { kind: 'reaction-balance', title, species, elements, sources };
    },
    render: renderWeiBeiReactionBalance,
  },
  'algorithm-trace': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawLines = safeInteractiveArray(value.codeLines, MAX_INTERACTIVE_ALGORITHM_LINES);
      const rawSteps = safeInteractiveArray(value.steps, MAX_INTERACTIVE_ALGORITHM_STEPS);
      const sources = safeInteractiveSources(value);
      if (!title || !rawLines || rawLines.length < 1 || !rawSteps || rawSteps.length < 1 || !sources) return null;
      const codeLines = rawLines.map((line) => safeInteractiveString(line, 180));
      if (codeLines.some((line) => !line)) return null;
      const steps = rawSteps.map((step) => {
        const lineIndex = safeInteractiveInteger(step?.lineIndex, 0, codeLines.length - 1);
        const summary = safeInteractiveString(step?.summary, MAX_INTERACTIVE_CONTENT_LENGTH);
        const note = safeOptionalInteractiveString(step?.note, MAX_INTERACTIVE_CONTENT_LENGTH);
        const source = safeOptionalInteractiveString(step?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return lineIndex !== null && summary && note !== null && source !== null
          ? { lineIndex, summary, note, source }
          : null;
      });
      if (steps.some((step) => !step)) return null;
      return { kind: 'algorithm-trace', title, codeLines, steps, sources };
    },
    render: renderWeiBeiAlgorithmTrace,
  },
  'language-aligner': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawPairs = safeInteractiveArray(value.pairs, MAX_INTERACTIVE_LANGUAGE_PAIRS);
      const sources = safeInteractiveSources(value);
      if (!title || !rawPairs || rawPairs.length < 1 || !sources) return null;
      const pairs = rawPairs.map((pair) => {
        const label = safeInteractiveString(pair?.label, 80);
        const sourceText = safeInteractiveString(pair?.sourceText, MAX_INTERACTIVE_CONTENT_LENGTH);
        const targetText = safeInteractiveString(pair?.targetText, MAX_INTERACTIVE_CONTENT_LENGTH);
        const note = safeInteractiveString(pair?.note, MAX_INTERACTIVE_CONTENT_LENGTH);
        const source = safeOptionalInteractiveString(pair?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return label && sourceText && targetText && note && source !== null
          ? { label, sourceText, targetText, note, source }
          : null;
      });
      if (pairs.some((pair) => !pair)) return null;
      return { kind: 'language-aligner', title, pairs, sources };
    },
    render: renderWeiBeiLanguageAligner,
  },
  'argument-map': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const question = safeOptionalInteractiveString(value.question, MAX_INTERACTIVE_CONTENT_LENGTH);
      const rawNodes = safeInteractiveArray(value.nodes, MAX_INTERACTIVE_ARGUMENT_NODES);
      const rawEdges = value.edges === undefined ? [] : safeInteractiveArray(value.edges, MAX_INTERACTIVE_ARGUMENT_EDGES);
      const sources = safeInteractiveSources(value);
      if (!title || question === null || !rawNodes || rawNodes.length < 1 || !rawEdges || !sources) return null;
      const ids = new Set();
      const allowedTypes = new Set(['premise', 'claim', 'objection', 'reply']);
      const nodes = rawNodes.map((node) => {
        const id = safeInteractiveID(node?.id);
        const type = safeInteractiveEnum(node?.type, allowedTypes);
        const label = safeInteractiveString(node?.label, 160);
        const detail = safeOptionalInteractiveString(node?.detail, MAX_INTERACTIVE_CONTENT_LENGTH);
        const source = safeOptionalInteractiveString(node?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || ids.has(id) || !type || !label || detail === null || source === null) return null;
        ids.add(id);
        return { id, type, label, detail, source };
      });
      if (nodes.some((node) => !node)) return null;
      const edges = rawEdges.map((edge) => {
        const from = safeInteractiveID(edge?.from);
        const to = safeInteractiveID(edge?.to);
        const label = safeOptionalInteractiveString(edge?.label, 120);
        return from && to && from !== to && ids.has(from) && ids.has(to) && label !== null
          ? { from, to, label }
          : null;
      });
      if (edges.some((edge) => !edge)) return null;
      return { kind: 'argument-map', title, question, nodes, edges, sources };
    },
    render: renderWeiBeiArgumentMap,
  },
  'visual-analysis': {
    parse(value) {
      if (hasUnsafeInteractiveVisualPayload(value)) return null;
      const title = safeInteractiveString(value.title);
      const rawZones = safeInteractiveArray(value.zones, MAX_INTERACTIVE_VISUAL_ZONES);
      const rawPalette = value.palette === undefined ? [] : safeInteractiveArray(value.palette, MAX_INTERACTIVE_COLORS);
      const rawLenses = value.lenses === undefined ? [] : safeInteractiveArray(value.lenses, MAX_INTERACTIVE_VISUAL_LENSES);
      const sources = safeInteractiveSources(value);
      if (!title || !rawZones || rawZones.length < 1 || !rawPalette || !rawLenses || !sources) return null;
      const zoneIDs = new Set();
      const zones = rawZones.map((zone) => {
        const id = safeInteractiveID(zone?.id);
        const label = safeInteractiveString(zone?.label, 120);
        const x = safeInteractivePercent(zone?.x);
        const y = safeInteractivePercent(zone?.y);
        const width = safeInteractiveNumber(zone?.width, 1, 100);
        const height = safeInteractiveNumber(zone?.height, 1, 100);
        const note = safeInteractiveString(zone?.note, MAX_INTERACTIVE_CONTENT_LENGTH);
        const tone = safeOptionalInteractiveTone(zone?.tone, 'ink');
        const source = safeOptionalInteractiveString(zone?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || zoneIDs.has(id) || !label || x === null || y === null || width === null || height === null || x + width > 100 || y + height > 100 || !note || !tone || source === null) return null;
        zoneIDs.add(id);
        return { id, label, x, y, width, height, note, tone, source };
      });
      const palette = rawPalette.map((item) => {
        const label = safeInteractiveString(item?.label, 80);
        const role = safeInteractiveString(item?.role, 160);
        const tone = safeOptionalInteractiveTone(item?.tone, 'ink');
        return label && role && tone ? { label, role, tone } : null;
      });
      const lenses = rawLenses.map((lens) => {
        const id = safeInteractiveID(lens?.id);
        const label = safeInteractiveString(lens?.label, 100);
        const note = safeInteractiveString(lens?.note, MAX_INTERACTIVE_CONTENT_LENGTH);
        const rawZoneIDs = lens?.zoneIds === undefined ? [] : safeInteractiveArray(lens.zoneIds, MAX_INTERACTIVE_VISUAL_ZONES);
        const zoneIds = rawZoneIDs?.map(safeInteractiveID) || null;
        return id && label && note && zoneIds && zoneIds.every((item) => item && zoneIDs.has(item))
          ? { id, label, note, zoneIds }
          : null;
      });
      if (zones.some((zone) => !zone) || palette.some((item) => !item) || lenses.some((lens) => !lens)) return null;
      return { kind: 'visual-analysis', title, zones, palette, lenses, sources };
    },
    render: renderWeiBeiVisualAnalysis,
  },
  'spatial-layers': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawLayers = safeInteractiveArray(value.layers, MAX_INTERACTIVE_SPATIAL_LAYERS);
      const rawFeatures = safeInteractiveArray(value.features, MAX_INTERACTIVE_SPATIAL_FEATURES);
      const sources = safeInteractiveSources(value);
      if (!title || !rawLayers || rawLayers.length < 1 || !rawFeatures || rawFeatures.length < 1 || !sources) return null;
      const layerIDs = new Set();
      const layers = rawLayers.map((layer, index) => {
        const id = safeInteractiveID(layer?.id);
        const label = safeInteractiveString(layer?.label, 100);
        const visible = layer?.visible === undefined ? index === 0 : layer.visible === true;
        if (!id || layerIDs.has(id) || !label) return null;
        layerIDs.add(id);
        return { id, label, visible };
      });
      if (layers.some((layer) => !layer)) return null;
      const allowedTypes = new Set(['point', 'route', 'region']);
      const featureIDs = new Set();
      const features = rawFeatures.map((feature) => {
        const id = safeInteractiveID(feature?.id);
        const type = safeInteractiveEnum(feature?.type, allowedTypes);
        const layerId = safeInteractiveID(feature?.layerId);
        const label = safeInteractiveString(feature?.label, 120);
        const note = safeOptionalInteractiveString(feature?.note, MAX_INTERACTIVE_CONTENT_LENGTH);
        const points = safeInteractivePercentPoints(feature?.points, MAX_INTERACTIVE_SPATIAL_POINTS, type === 'point' ? 1 : type === 'route' ? 2 : 3);
        const source = safeOptionalInteractiveString(feature?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || featureIDs.has(id) || !type || !layerId || !layerIDs.has(layerId) || !label || note === null || !points || source === null) return null;
        if (type === 'point' && points.length !== 1) return null;
        featureIDs.add(id);
        return { id, type, layerId, label, note, points, source };
      });
      if (features.some((feature) => !feature)) return null;
      return { kind: 'spatial-layers', title, layers, features, sources };
    },
    render: renderWeiBeiSpatialLayers,
  },
  'pathway-lab': {
    parse(value) {
      const title = safeInteractiveString(value.title);
      const rawNodes = safeInteractiveArray(value.nodes, MAX_INTERACTIVE_MAP_NODES);
      const rawStates = safeInteractiveArray(value.states, MAX_INTERACTIVE_PATHWAY_STATES);
      const rawEdges = value.edges === undefined ? [] : safeInteractiveArray(value.edges, MAX_INTERACTIVE_MAP_EDGES);
      const sources = safeInteractiveSources(value);
      if (!title || !rawNodes || rawNodes.length < 1 || !rawStates || rawStates.length < 1 || !rawEdges || !sources) return null;
      const nodeIDs = new Set();
      const nodes = rawNodes.map((node) => {
        const id = safeInteractiveID(node?.id);
        const label = safeInteractiveString(node?.label, 120);
        const detail = safeOptionalInteractiveString(node?.detail, MAX_INTERACTIVE_CONTENT_LENGTH);
        const source = safeOptionalInteractiveString(node?.source, MAX_SOURCE_REFERENCE_LENGTH);
        if (!id || nodeIDs.has(id) || !label || detail === null || source === null) return null;
        nodeIDs.add(id);
        return { id, label, detail, source };
      });
      if (nodes.some((node) => !node)) return null;
      const states = rawStates.map((state) => {
        const id = safeInteractiveID(state?.id);
        const label = safeInteractiveString(state?.label, 120);
        const note = safeOptionalInteractiveString(state?.note, MAX_INTERACTIVE_CONTENT_LENGTH);
        const rawActive = safeInteractiveArray(state?.activeNodeIds, MAX_INTERACTIVE_MAP_NODES);
        const activeNodeIds = rawActive?.map(safeInteractiveID) || null;
        const source = safeOptionalInteractiveString(state?.source, MAX_SOURCE_REFERENCE_LENGTH);
        return id && label && note !== null && activeNodeIds && activeNodeIds.length > 0 && activeNodeIds.every((nodeID) => nodeID && nodeIDs.has(nodeID)) && source !== null
          ? { id, label, note, activeNodeIds, source }
          : null;
      });
      const edges = rawEdges.map((edge) => {
        const from = safeInteractiveID(edge?.from);
        const to = safeInteractiveID(edge?.to);
        const label = safeOptionalInteractiveString(edge?.label, 120);
        return from && to && from !== to && nodeIDs.has(from) && nodeIDs.has(to) && label !== null
          ? { from, to, label }
          : null;
      });
      if (states.some((state) => !state) || edges.some((edge) => !edge)) return null;
      return { kind: 'pathway-lab', title, nodes, states, edges, sources };
    },
    render: renderWeiBeiPathwayLab,
  },
};

const weiBeiInteractiveWidget = (model) => {
  const root = weiBeiInteractiveRegistry[model.kind].render(model);
  configureWeiBeiInteractiveRoot(root, model.kind);
  root.dataset.blockId = model.blockId;
  const title = root.querySelector('.weibei-interactive-title, .weibei-interactive-prompt, .weibei-unit-title, .weibei-reaction-title, .weibei-algorithm-title, .weibei-language-title, .weibei-argument-title, .weibei-visual-analysis-title, .weibei-spatial-title, .weibei-pathway-title');
  if (title?.textContent) root.setAttribute('aria-label', title.textContent);
  ensureInteractiveStatus(root);
  return root;
};

const shouldRenderWeiBeiInteractive = () => !isEditable || isCompactPreview;

const decorateWeiBeiInteractiveBlock = (decorations, node, pos) => {
  if (normalizeLanguage(node.attrs.language || '') !== 'weibei-interactive') return false;
  if (!shouldRenderWeiBeiInteractive()) {
    decorations.push(Decoration.node(pos, pos + node.nodeSize, {
      class: 'weibei-code-block',
      'data-language': node.attrs.language || '',
    }));
    return true;
  }
  const model = parseWeiBeiInteractiveBlock(node.textContent);
  if (!model) {
    decorations.push(Decoration.node(pos, pos + node.nodeSize, {
      class: 'weibei-code-block',
    }));
    return true;
  }
  decorations.push(Decoration.node(pos, pos + node.nodeSize, {
    class: 'weibei-code-block weibei-interactive-source',
    'data-language': 'weibei-interactive',
  }));
  decorations.push(Decoration.widget(pos + node.nodeSize, () => weiBeiInteractiveWidget(model), { side: 1 }));
  return true;
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

const toggleFoldedCallout = (target) => {
  if (isEditable || !(target instanceof Element)) return false;
  const callout = target.closest('blockquote.weibei-callout[data-callout-fold="-"]');
  if (!callout) return false;
  callout.classList.toggle('weibei-callout-open');
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
      element.setAttribute('title', editorLabel('mathError'));
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

const listItemTypeNames = new Set(['list_item', 'task_list_item']);
const meaningfulListText = (node) => (node.textContent || '').replace(/[\u200B\uFEFF]/g, '').trim();

const emptyListItemTypeAtSelection = (state) => {
  const { selection } = state;
  if (!selection.empty) return null;
  const { $from } = selection;
  for (let depth = $from.depth; depth > 0; depth -= 1) {
    const node = $from.node(depth);
    if (!listItemTypeNames.has(node.type.name)) continue;
    if (meaningfulListText(node).length > 0) return null;
    return node.type;
  }
  return null;
};

const clearInvisibleCurrentTextblock = (view) => {
  const { state } = view;
  const { $from } = state.selection;
  const node = $from.parent;
  if (node?.isTextblock !== true || !node.textContent || meaningfulListText(node).length > 0) return;
  const from = $from.start();
  const to = $from.end();
  const tr = state.tr.delete(from, to);
  tr.setSelection(TextSelection.create(tr.doc, Math.min(from, tr.doc.content.size)));
  view.dispatch(tr);
};

const exitEmptyListItem = (view) => {
  let listItemType = emptyListItemTypeAtSelection(view.state);
  if (!listItemType) return false;
  clearInvisibleCurrentTextblock(view);
  listItemType = emptyListItemTypeAtSelection(view.state) || listItemType;
  return liftListItem(listItemType)(view.state, view.dispatch, view);
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
    handleTextInput(view, from, to, text) {
      if (!isEditable) return false;
      const incoming = String(text || '');
      if (!incoming) return false;
      const lookBehindSize = Math.min(12, from);
      const before = view.state.doc.textBetween(from - lookBehindSize, from, '\n', '\n');
      const match = `${before}${incoming}`.match(/<br\s*\/?>$/i);
      if (!match) return false;
      const hardbreak = view.state.schema.nodes.hardbreak || view.state.schema.nodes.hard_break;
      if (!hardbreak) return false;
      const start = from - (match[0].length - incoming.length);
      const tr = view.state.tr.replaceWith(start, to, hardbreak.create()).scrollIntoView();
      tr.setSelection(TextSelection.create(tr.doc, Math.min(start + 1, tr.doc.content.size)));
      view.dispatch(tr);
      return true;
    },
    handleClick(view, pos, event) {
      return activateWikiLink(event.target)
        || activateSourceReference(event.target)
        || toggleFoldedCallout(event.target);
    },
    handleKeyDown(view, event) {
      if (
        event.key === 'Enter'
        && isEditable
        && !event.shiftKey
        && !event.altKey
        && !event.metaKey
        && !event.ctrlKey
        && exitEmptyListItem(view)
      ) {
        event.preventDefault();
        return true;
      }
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
          if (decorateWeiBeiInteractiveBlock(decorations, node, pos)) return false;
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
          if (hasCodeMark) return true;
          const insideBlockquote = isInsideNode(state, textPos, 'blockquote') || isInsideNode(state, textPos, 'block_quote');
          if (insideBlockquote) decorateLeakedCalloutControls(decorations, text, textPos);
          decorateDelimitedInline(decorations, text, textPos, /==([^=\n]+)==/g, 2, 'weibei-highlight');
          decorateInlineFootnotes(decorations, text, textPos);
          decorateHtmlBreaks(decorations, text, textPos);
          decorateComments(decorations, text, textPos, commentState);
          decorateObsidianEmbeds(decorations, text, textPos);
          decorateWikiLinks(decorations, text, textPos);
          decorateBracketSourceReferences(decorations, text, textPos);
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
  const body = normalizeHtmlBreaks(document.body);
  frontmatterBlock = document.frontmatter;
  syncFrontmatterPanel();
  editor.action(replaceAll(body));
  lastMarkdown = withFrontmatter(body);
  reportContentHeight();
};

const getMarkdownInternal = () => {
  ensureEditor();
  return withFrontmatter(editor.action(readMarkdown()));
};

const replaceSelectionInternal = (markdown) => {
  ensureEditor();
  const insertion = normalizeHtmlBreaks(markdown || '');
  const range = lastSelectionRange || editorSelectionRange();
  if (range) {
    editor.action(replaceRange(insertion, range));
  } else {
    editor.action(insert(insertion));
  }
  const next = getMarkdownInternal();
  lastMarkdown = next;
  lastSelectionRange = null;
  post('markdownChanged', { markdown: next });
};

const insertMarkdownInternal = (markdown) => {
  ensureEditor();
  const range = editorSelectionRange();
  const insertion = normalizeMarkdownInsertion(normalizeHtmlBreaks(markdown));
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

const pressKeyForCheck = (key, options = {}) => {
  ensureEditor();
  if (!window.weiBeiEditorCheckMode) return false;
  return editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.focus();
    const event = new KeyboardEvent('keydown', {
      key,
      bubbles: true,
      cancelable: true,
      shiftKey: options.shiftKey === true,
      altKey: options.altKey === true,
      metaKey: options.metaKey === true,
      ctrlKey: options.ctrlKey === true,
    });
    view.dom.dispatchEvent(event);
    return true;
  });
};

const headingElements = () => Array.from(document.querySelectorAll('.ProseMirror h1, .ProseMirror h2, .ProseMirror h3, .ProseMirror h4'));
let activeHeadingFrame = 0;
let lastActiveHeadingIndex = -2;

const reportActiveHeading = () => {
  window.cancelAnimationFrame(activeHeadingFrame);
  activeHeadingFrame = window.requestAnimationFrame(() => {
    const headings = headingElements();
    if (headings.length === 0) {
      if (lastActiveHeadingIndex !== -1) {
        lastActiveHeadingIndex = -1;
        post('activeHeadingChanged', { index: null });
      }
      return;
    }
    const readingLine = Math.max(0, window.innerHeight * 0.32);
    let activeIndex = 0;
    headings.forEach((heading, index) => {
      if (heading.getBoundingClientRect().top <= readingLine) activeIndex = index;
    });
    if (activeIndex === lastActiveHeadingIndex) return;
    lastActiveHeadingIndex = activeIndex;
    post('activeHeadingChanged', { index: activeIndex });
  });
};

const scrollToHeadingInternal = (rawIndex) => {
  const index = Number(rawIndex);
  const headings = headingElements();
  const heading = Number.isFinite(index) ? headings[Math.max(0, Math.floor(index))] : null;
  if (!heading) return false;
  heading.scrollIntoView({ block: 'start', behavior: 'smooth' });
  window.setTimeout(reportActiveHeading, 180);
  return true;
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
    if (!editor) return;
    editor.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      view.dispatch(view.state.tr.setMeta('weibeiEditableChanged', isEditable));
    });
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
    syncFrontmatterPanel();
    if (!editor) return;
    editor.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      view.dispatch(view.state.tr.setMeta('weibeiLanguageChanged', currentLanguage));
    });
  },
  scrollToHeading: scrollToHeadingInternal,
};

if (window.weiBeiEditorCheckMode) {
  window.WeiBeiEditor.selectFirstTextForCheck = selectFirstTextForCheck;
  window.WeiBeiEditor.selectedTextForCheck = editorSelectedText;
  window.WeiBeiEditor.typeTextForCheck = typeTextForCheck;
  window.WeiBeiEditor.pressKeyForCheck = pressKeyForCheck;
}

const initialDocument = splitFrontmatter(window.initialMarkdown || '');
initialDocument.body = normalizeHtmlBreaks(initialDocument.body);
frontmatterBlock = initialDocument.frontmatter;
syncFrontmatterPanel();

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
        widget.textContent = editorLabel('uploadingImage');
        return Decoration.widget(pos, widget, spec);
      },
    });
    ctx.set(katexOptionsCtx.key, {
      throwOnError: false,
      strict: false,
      trust: false,
    });
  })
  .use(weiBeiDialectPlugin)
  .use(commonmark)
  .use(gfm)
  .use(math)
  .use(upload)
  .use(listener)
  .config((ctx) => {
    ctx.get(listenerCtx).markdownUpdated((_, markdown) => {
      const normalizedMarkdown = withFrontmatter(markdown);
      if (normalizedMarkdown === lastMarkdown) return;
      lastMarkdown = normalizedMarkdown;
      post('markdownChanged', { markdown: normalizedMarkdown });
      reportActiveHeading();
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
    document.addEventListener('pointerdown', () => {
      if (window.weiBeiSuppressSelectionReport) return;
      lastSelectionRange = null;
      lastSelectionReport.text = '';
      lastSelectionReport.rectKey = '';
      post('selectionChanged', { text: '', rect: null });
    }, true);
    document.addEventListener('click', (event) => {
      if (!activateWikiLink(event.target)
          && !activateSourceReference(event.target)
          && !toggleFoldedCallout(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
    }, true);
    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' && event.key !== ' ') return;
      if (!activateWikiLink(event.target) && !activateSourceReference(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
    }, true);
    document.addEventListener('keyup', (event) => {
      reportSelection();
    });
    installContentHeightObserver();
    document.addEventListener('scroll', reportActiveHeading, true);
    post('editorReady', { markdown: lastMarkdown });
    reportContentHeight();
    reportActiveHeading();
  })
  .catch(showFailure);
