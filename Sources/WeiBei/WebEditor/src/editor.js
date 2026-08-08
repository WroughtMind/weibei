import { commandsCtx, Editor, defaultValueCtx, editorViewCtx, editorViewOptionsCtx, rootCtx } from '@milkdown/kit/core';
import { commonmark } from '@milkdown/kit/preset/commonmark';
import { gfm } from '@milkdown/kit/preset/gfm';
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener';
import { history } from '@milkdown/kit/plugin/history';
import {
  abortStreamingCmd,
  endStreamingCmd,
  pushChunkCmd,
  startStreamingCmd,
  streaming,
  streamingConfig,
} from '@milkdown/plugin-streaming';
import { SlashProvider, slashFactory } from '@milkdown/kit/plugin/slash';
import { readImageAsBase64, upload, uploadConfig } from '@milkdown/kit/plugin/upload';
import { exitCode, setBlockType } from '@milkdown/kit/prose/commands';
import { closeHistory, undo } from '@milkdown/kit/prose/history';
import { Fragment } from '@milkdown/kit/prose/model';
import { Plugin, Selection, TextSelection } from '@milkdown/kit/prose/state';
import { liftListItem } from '@milkdown/kit/prose/schema-list';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';
import { getMarkdown as readMarkdown, insert, replaceAll, replaceRange, $prose } from '@milkdown/kit/utils';
import { katexOptionsCtx, math } from '@milkdown/plugin-math';
import katex from 'katex';
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

// Stata has no official Prism component; econometrics answers lean on it heavily.
// Line-leading `*` is a comment in Stata — colorized here so it does not read
// as a stray Markdown artifact.
Prism.languages.stata = {
  comment: [
    { pattern: /(^|\n)\s*\*.*/, lookbehind: true },
    { pattern: /\/\/.*/ },
    { pattern: /\/\*[\s\S]*?\*\//, greedy: true },
  ],
  string: { pattern: /"[^"\n]*"/, greedy: true },
  macro: { pattern: /`[^'\n]*'|\$\{?\w+\}?/, alias: 'variable' },
  keyword: /\b(?:use|clear|gen(?:erate)?|egen|replace|drop|keep|merge|append|save|import|export|reg(?:ress)?|ivregress|areg|xtreg|logit|probit|tobit|test|testparm|lincom|nlcom|margins|display|di|summarize|sum|tabulate|tab|describe|predict|estat|esttab|estimates|vce|robust|cluster|if|in|foreach|forvalues|while|else|local|global|scalar|matrix|by|bysort|sort|gsort|label|rename|recode|encode|decode|reshape|collapse|preserve|restore|set|version|capture|quietly|noisily)\b/,
  function: /\b[a-zA-Z_]\w*(?=\()/,
  number: /\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/i,
  operator: /[-+*/^=<>!&|~#]+/,
  punctuation: /[(){}[\],;:]/,
};
Prism.languages.do = Prism.languages.stata;

const bridge = window.webkit?.messageHandlers;
let editor;
let lastMarkdown = '';
let compositionStartMarkdown = null;
let compositionTextblockFrom = null;
let compositionEndPending = false;
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
let mermaidPreviewID = 0;
let mermaidPreviewGeneration = 0;
const pendingAttachments = new Map();
const pendingImagePickers = new Map();
const weiBeiSlash = slashFactory('WEIBEI_BLOCK_COMMAND');
let currentDocumentGeneration = 0;
let currentContentGeneration = 0;
let streamingMarkdownBuffer = null;
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
    embed: '嵌入：{value}',
    mermaidRendering: '正在渲染 Mermaid 图表...',
    mermaidFailed: 'Mermaid 图表未解析\n{value}',
    mathError: '公式没有通过 KaTeX 解析。常用写法：x_i、x^{2}、\\frac{a}{b}、\\begin{bmatrix}...\\end{bmatrix}',
    uploadingImage: '正在收纳图片...',
    slashNoResults: '没有匹配命令', slashStructure: '结构', slashLists: '列表', slashContent: '内容', slashRichContent: '丰富内容',
    slashHeading1: '一级标题', slashHeading2: '二级标题', slashHeading3: '三级标题', slashBulletList: '无序列表', slashOrderedList: '有序列表', slashTaskList: '待办列表', slashQuote: '引用', slashCallout: '提示块', slashCode: '代码块', slashDivider: '分隔线', slashTable: '表格', slashImage: '图片', slashMermaid: 'Mermaid 图表',
    slashRows: '行', slashColumns: '列', slashInsertTable: '插入表格', slashImageFailed: '图片读取或保存失败', codeLanguage: '代码语言', codeLanguagePlaceholder: 'text',
  },
  en: {
    properties: 'Properties',
    bootFailed: 'Milkdown failed to initialize',
    imageMissing: 'Image not found',
    inlineFootnote: 'Inline footnote: {value}',
    openOrCreateNote: 'Open or create note: {value}',
    openSource: 'Open source: {value}',
    embed: 'Embed: {value}',
    mermaidRendering: 'Rendering Mermaid diagram...',
    mermaidFailed: 'Mermaid diagram did not parse\n{value}',
    mathError: 'KaTeX could not parse this formula. Common forms: x_i, x^{2}, \\frac{a}{b}, \\begin{bmatrix}...\\end{bmatrix}',
    uploadingImage: 'Saving image...',
    slashNoResults: 'No matching commands', slashStructure: 'Structure', slashLists: 'Lists', slashContent: 'Content', slashRichContent: 'Rich content',
    slashHeading1: 'Heading 1', slashHeading2: 'Heading 2', slashHeading3: 'Heading 3', slashBulletList: 'Bulleted list', slashOrderedList: 'Numbered list', slashTaskList: 'To-do list', slashQuote: 'Quote', slashCallout: 'Callout', slashCode: 'Code block', slashDivider: 'Divider', slashTable: 'Table', slashImage: 'Image', slashMermaid: 'Mermaid diagram',
    slashRows: 'Rows', slashColumns: 'Columns', slashInsertTable: 'Insert table', slashImageFailed: 'Image could not be read or saved', codeLanguage: 'Code language', codeLanguagePlaceholder: 'text',
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

// Keep all four product themes — CSS variables live under data-weibei-theme={paper|xuan|inkstone|stele}.
const normalizeTheme = (theme) => {
  if (theme === 'xuan' || theme === 'inkstone' || theme === 'stele' || theme === 'paper') return theme;
  return 'paper';
};
let currentTheme = normalizeTheme(window.weiBeiTheme);

const mermaidThemeVariables = () => {
  switch (currentTheme) {
    case 'inkstone':
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
    case 'stele':
      return {
        background: '#1e2228',
        primaryColor: '#252a32',
        primaryTextColor: '#d2d6dc',
        primaryBorderColor: '#3a414c',
        lineColor: '#8a7a5c',
        secondaryColor: '#2a3038',
        tertiaryColor: '#1a1e24',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Songti SC", serif',
      };
    case 'xuan':
      return {
        background: '#f7f4ef',
        primaryColor: '#fcfbf8',
        primaryTextColor: '#25231f',
        primaryBorderColor: '#d8d2c6',
        lineColor: '#6e634f',
        secondaryColor: '#ebe6dc',
        tertiaryColor: '#f7f4ef',
        fontFamily: '-apple-system, BlinkMacSystemFont, "Songti SC", serif',
      };
    default:
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
  }
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
  mermaidPreviewGeneration += 1;
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

const slashMenuElement = document.createElement('div');
slashMenuElement.className = 'weibei-slash-menu';
slashMenuElement.dataset.show = 'false';
slashMenuElement.setAttribute('role', 'listbox');
slashMenuElement.setAttribute('aria-label', 'Slash commands');
const slashStatusElement = document.createElement('div');
slashStatusElement.className = 'weibei-visually-hidden';
slashStatusElement.setAttribute('role', 'status');
slashStatusElement.setAttribute('aria-live', 'polite');
let slashTablePanelElement = null;

const slashGroups = [
  { id: 'structure', label: 'slashStructure' }, { id: 'lists', label: 'slashLists' },
  { id: 'content', label: 'slashContent' }, { id: 'rich', label: 'slashRichContent' },
];
const slashCommands = [
  { id: 'heading1', group: 'structure', label: 'slashHeading1', aliases: ['h1', 'heading_1', 'yjbt', '一级', '标题1'] },
  { id: 'heading2', group: 'structure', label: 'slashHeading2', aliases: ['h2', 'heading_2', 'ejbt', '二级', '标题2'] },
  { id: 'heading3', group: 'structure', label: 'slashHeading3', aliases: ['h3', 'heading_3', 'sjbt', '三级', '标题3'] },
  { id: 'bulletList', group: 'lists', label: 'slashBulletList', aliases: ['bullet_list', 'bullet', 'ul', 'wxlb', '无序', '项目符号'] },
  { id: 'orderedList', group: 'lists', label: 'slashOrderedList', aliases: ['ordered_list', 'ol', 'yxlb', '有序', '编号'] },
  { id: 'taskList', group: 'lists', label: 'slashTaskList', aliases: ['task_list', 'todo', 'task', 'checklist', 'dblb', '待办', '任务'] },
  { id: 'quote', group: 'lists', label: 'slashQuote', aliases: ['quote', 'blockquote', 'yy', '引用'] },
  { id: 'callout', group: 'content', label: 'slashCallout', aliases: ['callout', 'note', 'tsk', '提示', '札记'] },
  { id: 'code', group: 'content', label: 'slashCode', aliases: ['code', 'code_block', 'dmk', '代码'] },
  { id: 'divider', group: 'content', label: 'slashDivider', aliases: ['divider', 'horizontal_rule', 'hr', 'fgx', '分隔', '横线'] },
  { id: 'table', group: 'rich', label: 'slashTable', aliases: ['table', 'grid', 'bg', '表格'] },
  { id: 'image', group: 'rich', label: 'slashImage', aliases: ['image', 'photo', 'picture', 'tp', '图片', '照片'] },
  { id: 'mermaid', group: 'rich', label: 'slashMermaid', aliases: ['mermaid', 'diagram', 'flowchart', 'lct', '图表', '流程图'] },
];
const slashRuntime = { provider: null, view: null, context: null, commands: [], activeIndex: 0, dismissedContext: '', activationContext: '', tableOpen: false, tableFocus: 'rows', tableRows: 3, tableColumns: 3, tableMenuBaseLeft: '', error: '' };
const slashExcludedAncestors = new Set(['list_item', 'task_list_item', 'table', 'table_row', 'table_header_row', 'table_cell', 'table_header', 'code_block', 'math_block']);

/**
 * Returns slash context only when `/` begins an otherwise blank editable line.
 *
 * Zero-width placeholders are tolerated because ProseMirror can retain them in
 * a visually blank paragraph while a composition session finishes.  Paragraphs
 * that contain inline nodes (images, etc.) are rejected \u2014 textContent excludes
 * them, so without this check an image followed by "/" would be mistaken for a
 * blank Slash line and replaced wholesale.
 */
const slashContextForView = (view) => {
  if (!isEditable || view.composing) return null;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || !selection.empty) return null;
  const { $from } = selection;
  if ($from.parent.type.name !== 'paragraph' || $from.parentOffset !== $from.parent.content.size) return null;
  for (let depth = $from.depth; depth > 0; depth -= 1) if (slashExcludedAncestors.has($from.node(depth).type.name)) return null;
  let hasInlineNode = false;
  $from.parent.content.forEach((node) => { if (!node.isText) hasInlineNode = true; });
  if (hasInlineNode) return null;
  const source = $from.parent.textContent || '';
  const match = source.match(/^[\u200B\uFEFF]*\/([^\s/]*)$/u);
  if (!match) return null;
  const depth = $from.depth;
  return { query: match[1] || '', source, blockFrom: $from.before(depth), blockTo: $from.after(depth), index: $from.index(depth - 1), container: $from.node(depth - 1), key: `${$from.before(depth)}:${source}` };
};

/** Builds the replacement nodes directly instead of reparsing generated Markdown. */
const slashReplacement = (commandID, schema, options = {}) => {
  const paragraph = schema.nodes.paragraph;
  if (!paragraph) return null;
  if (commandID.startsWith('heading')) {
    const heading = schema.nodes.heading;
    return heading ? { content: Fragment.from(heading.create({ level: Number(commandID.at(-1)) })), selectionOffset: 1 } : null;
  }
  if (['bulletList', 'orderedList', 'taskList'].includes(commandID)) {
    const list = commandID === 'orderedList' ? schema.nodes.ordered_list : schema.nodes.bullet_list;
    const item = schema.nodes.list_item?.createAndFill(commandID === 'taskList' ? { checked: false } : null, paragraph.create());
    const listNode = item && list?.createAndFill(null, item);
    return listNode ? { content: Fragment.from(listNode), selectionOffset: 3 } : null;
  }
  if (commandID === 'quote' || commandID === 'callout') {
    const blockquote = schema.nodes.blockquote || schema.nodes.block_quote;
    if (!blockquote) return null;
    const content = commandID === 'callout' ? [paragraph.create(null, schema.text('[!note]')), paragraph.create()] : [paragraph.create()];
    const node = blockquote.create(null, content);
    return { content: Fragment.from(node), selectionOffset: commandID === 'callout' ? 10 : 2 };
  }
  if (commandID === 'code' || commandID === 'mermaid') {
    const code = schema.nodes.code_block;
    if (!code) return null;
    const source = commandID === 'mermaid' ? 'graph TD\n\tA --> B' : '';
    return { content: Fragment.from(code.create({ language: commandID === 'mermaid' ? 'mermaid' : '' }, source ? schema.text(source) : null)), selectionOffset: source.length + 1 };
  }
  if (commandID === 'divider') {
    const divider = schema.nodes.hr || schema.nodes.horizontal_rule;
    const node = divider?.create();
    return node ? { content: Fragment.from([node, paragraph.create()]), selectionOffset: node.nodeSize + 1 } : null;
  }
  if (commandID === 'table') {
    const { table, table_header_row: headerRow, table_row: row, table_header: header, table_cell: cell } = schema.nodes;
    const rows = Math.min(20, Math.max(1, Number(options.rows) || 3));
    const columns = Math.min(12, Math.max(1, Number(options.columns) || 3));
    if (!table || !headerRow || !row || !header || !cell) return null;
    const headers = Array.from({ length: columns }, () => header.createAndFill());
    const body = Array.from({ length: rows - 1 }, () => row.create(null, Array.from({ length: columns }, () => cell.createAndFill())));
    if (headers.some((node) => !node) || body.some((node) => !node)) return null;
    return { content: Fragment.from(table.create(null, [headerRow.create(null, headers), ...body])), selectionOffset: 4 };
  }
  if (commandID === 'image') {
    const image = schema.nodes.image;
    return image && options.src ? { content: Fragment.from(paragraph.create(null, image.create({ src: options.src, alt: options.alt || 'image' }))), selectionOffset: 2 } : null;
  }
  return null;
};

/** Checks whether the current container accepts the requested replacement. */
const slashCommandIsAllowed = (command, context, schema) => {
  if (!context) return false;
  if (command.id === 'image') return Boolean(schema.nodes.image);
  const replacement = slashReplacement(command.id, schema, { rows: 3, columns: 3 });
  return Boolean(replacement && context.container.canReplace(context.index, context.index + 1, replacement.content));
};

/** Filters commands by localized labels and stable aliases. */
const filteredSlashCommands = (query, context, schema) => {
  const normalized = String(query || '').toLocaleLowerCase();
  return slashCommands.filter((command) => slashCommandIsAllowed(command, context, schema) && (!normalized || [editorLabels['zh-Hans'][command.label], editorLabels.en[command.label], ...command.aliases].some((value) => String(value).toLocaleLowerCase().includes(normalized))));
};

/** Applies exactly one history event for a slash block replacement. */
const applySlashReplacement = (view, context, replacement) => {
  if (!context || !replacement) return false;
  const node = view.state.doc.nodeAt(context.blockFrom);
  if (node?.type.name !== 'paragraph' || node.textContent !== context.source) return false;
  const tr = closeHistory(view.state.tr.replaceWith(context.blockFrom, context.blockTo, replacement.content));
  const selection = Selection.findFrom(tr.doc.resolve(Math.min(context.blockFrom + replacement.selectionOffset, tr.doc.content.size)), 1, true);
  if (selection) tr.setSelection(selection);
  view.dispatch(tr.scrollIntoView());
  slashRuntime.dismissedContext = '';
  slashRuntime.provider?.hide();
  view.focus();
  return true;
};

/** Records a native picker request without changing the slash paragraph. */
const requestSlashImage = (view, context) => {
  const id = `image-picker-${Date.now()}-${attachmentRequestID += 1}`;
  pendingImagePickers.set(id, { view, context, documentID: currentDocumentID, documentGeneration: currentDocumentGeneration });
  slashRuntime.dismissedContext = context.key;
  slashRuntime.provider?.hide();
  post('imagePickerRequested', { id });
};

/** Executes a selected command or opens the image picker. */
const executeSlashCommand = (commandID) => {
  const view = slashRuntime.view;
  const context = view && slashContextForView(view);
  if (!view || !context) return false;
  if (commandID === 'image') { requestSlashImage(view, context); return true; }
  return applySlashReplacement(view, context, slashReplacement(commandID, view.state.schema, { rows: slashRuntime.tableRows, columns: slashRuntime.tableColumns }));
};

/** Synchronizes root ARIA state and announces the selected command. */
const syncSlashAccessibility = () => {
  const root = slashRuntime.view?.dom;
  const active = slashRuntime.commands[slashRuntime.activeIndex];
  if (!root || slashMenuElement.dataset.show !== 'true' || !active) {
    root?.removeAttribute('aria-controls'); root?.removeAttribute('aria-expanded'); root?.removeAttribute('aria-activedescendant');
    return;
  }
  slashMenuElement.id = 'weibei-slash-menu';
  root.setAttribute('aria-controls', slashMenuElement.id);
  root.setAttribute('aria-expanded', 'true');
  root.setAttribute('aria-activedescendant', `weibei-slash-command-${active.id}`);
  slashMenuElement.setAttribute('aria-activedescendant', `weibei-slash-command-${active.id}`);
  slashStatusElement.textContent = `${editorLabel(active.label)}，${slashRuntime.activeIndex + 1}/${slashRuntime.commands.length}`;
};

/** Renders the lightweight command list and optional table dimensions panel. */
const renderSlashMenu = () => {
  slashTablePanelElement?.remove(); slashTablePanelElement = null;
  const view = slashRuntime.view;
  const context = view && slashContextForView(view);
  if (!view || !context || slashRuntime.dismissedContext === context.key) { slashRuntime.provider?.hide(); syncSlashAccessibility(); return; }
  if (slashRuntime.activationContext !== `${context.blockFrom}:${currentDocumentID}`) {
    Object.assign(slashRuntime, { activationContext: `${context.blockFrom}:${currentDocumentID}`, activeIndex: 0, tableOpen: false, tableFocus: 'rows', tableRows: 3, tableColumns: 3, tableMenuBaseLeft: '', error: '' });
  }
  slashRuntime.context = context;
  slashRuntime.commands = filteredSlashCommands(context.query, context, view.state.schema);
  slashRuntime.activeIndex = Math.min(slashRuntime.activeIndex, Math.max(0, slashRuntime.commands.length - 1));
  slashMenuElement.replaceChildren();
  if (slashRuntime.error) { const error = document.createElement('div'); error.className = 'weibei-slash-error'; error.textContent = slashRuntime.error; slashMenuElement.appendChild(error); }
  if (!slashRuntime.commands.length) { const empty = document.createElement('div'); empty.className = 'weibei-slash-empty'; empty.textContent = editorLabel('slashNoResults'); slashMenuElement.appendChild(empty); syncSlashAccessibility(); return; }
  let tableButton = null;
  for (const group of slashGroups) {
    const commands = slashRuntime.commands.filter((command) => command.group === group.id); if (!commands.length) continue;
    const section = document.createElement('section'); section.className = 'weibei-slash-section';
    const title = document.createElement('div'); title.className = 'weibei-slash-group'; title.textContent = editorLabel(group.label); section.appendChild(title);
    for (const command of commands) {
      const index = slashRuntime.commands.indexOf(command); const row = document.createElement('div'); row.id = `weibei-slash-command-${command.id}`; row.className = `weibei-slash-command${index === slashRuntime.activeIndex ? ' is-active' : ''}`; row.setAttribute('role', 'option'); row.setAttribute('aria-selected', String(index === slashRuntime.activeIndex)); row.setAttribute('aria-posinset', String(index + 1)); row.setAttribute('aria-setsize', String(slashRuntime.commands.length));
      const button = document.createElement('button'); button.type = 'button'; button.tabIndex = -1; button.className = 'weibei-slash-command-button'; button.textContent = editorLabel(command.label);
      button.addEventListener('pointerdown', (event) => event.preventDefault());
      button.addEventListener('pointermove', (event) => { if (!Number(event.movementX) && !Number(event.movementY)) return; slashRuntime.activeIndex = index; slashRuntime.tableOpen = command.id === 'table'; renderSlashMenu(); });
      button.addEventListener('click', () => { if (command.id !== 'table') executeSlashCommand(command.id); });
      row.appendChild(button); section.appendChild(row);
      if (command.id === 'table') tableButton = button;
    }
    slashMenuElement.appendChild(section);
  }
  slashMenuElement.querySelector('.weibei-slash-command.is-active')?.scrollIntoView({ block: 'nearest' });
  if (slashRuntime.tableOpen && tableButton) {
    const panel = document.createElement('div'); panel.className = 'weibei-slash-table-panel'; panel.setAttribute('role', 'group');
    for (const kind of ['rows', 'columns']) {
      const isRows = kind === 'rows'; const value = isRows ? slashRuntime.tableRows : slashRuntime.tableColumns; const max = isRows ? 20 : 12;
      const stepper = document.createElement('div'); stepper.className = `weibei-slash-stepper${slashRuntime.tableFocus === kind ? ' is-focused' : ''}`;
      const label = document.createElement('span'); label.className = 'weibei-slash-stepper-label'; label.textContent = editorLabel(isRows ? 'slashRows' : 'slashColumns'); stepper.appendChild(label);
      const decrement = document.createElement('button'); decrement.type = 'button'; decrement.textContent = '−'; decrement.disabled = value <= 1; decrement.setAttribute('aria-label', `${label.textContent} −`); decrement.addEventListener('pointerdown', (event) => event.preventDefault()); decrement.addEventListener('click', () => { if (isRows) slashRuntime.tableRows = Math.max(1, value - 1); else slashRuntime.tableColumns = Math.max(1, value - 1); slashRuntime.tableFocus = kind; renderSlashMenu(); }); stepper.appendChild(decrement);
      const input = document.createElement('input'); input.className = 'weibei-slash-stepper-input'; input.type = 'number'; input.inputMode = 'numeric'; input.min = '1'; input.max = String(max); input.step = '1'; input.value = String(value); input.setAttribute('aria-label', label.textContent); input.addEventListener('focus', () => { slashRuntime.tableFocus = kind; panel.querySelectorAll('.weibei-slash-stepper.is-focused').forEach((element) => element.classList.remove('is-focused')); stepper.classList.add('is-focused'); }); input.addEventListener('input', () => { const next = Number.parseInt(input.value, 10); if (!Number.isFinite(next)) return; if (isRows) slashRuntime.tableRows = Math.min(max, Math.max(1, next)); else slashRuntime.tableColumns = Math.min(max, Math.max(1, next)); }); input.addEventListener('change', () => { const next = Math.min(max, Math.max(1, Number.parseInt(input.value, 10) || 1)); input.value = String(next); if (isRows) slashRuntime.tableRows = next; else slashRuntime.tableColumns = next; }); input.addEventListener('keydown', (event) => { event.stopPropagation(); if (event.key === 'Enter') { const next = Math.min(max, Math.max(1, Number.parseInt(input.value, 10) || 1)); if (isRows) slashRuntime.tableRows = next; else slashRuntime.tableColumns = next; executeSlashCommand('table'); event.preventDefault(); } }); stepper.appendChild(input);
      const increment = document.createElement('button'); increment.type = 'button'; increment.textContent = '+'; increment.disabled = value >= max; increment.setAttribute('aria-label', `${label.textContent} +`); increment.addEventListener('pointerdown', (event) => event.preventDefault()); increment.addEventListener('click', () => { if (isRows) slashRuntime.tableRows = Math.min(max, value + 1); else slashRuntime.tableColumns = Math.min(max, value + 1); slashRuntime.tableFocus = kind; renderSlashMenu(); }); stepper.appendChild(increment);
      panel.appendChild(stepper);
    }
    const insert = document.createElement('button'); insert.type = 'button'; insert.className = 'weibei-slash-table-insert'; insert.textContent = editorLabel('slashInsertTable'); insert.addEventListener('pointerdown', (event) => event.preventDefault()); insert.addEventListener('click', () => executeSlashCommand('table')); panel.appendChild(insert);
    document.body.appendChild(panel);
    const inset = 8; const gap = 6; const panelWidth = panel.offsetWidth; let menuRect = slashMenuElement.getBoundingClientRect();
    const fitsRight = menuRect.right + gap + panelWidth <= window.innerWidth - inset; const fitsLeft = menuRect.left - gap - panelWidth >= inset;
    if (!fitsRight && !fitsLeft && menuRect.width + gap + panelWidth <= window.innerWidth - inset * 2) {
      if (!slashRuntime.tableMenuBaseLeft) slashRuntime.tableMenuBaseLeft = slashMenuElement.style.left;
      slashMenuElement.style.left = `${inset}px`; menuRect = slashMenuElement.getBoundingClientRect();
    }
    const showRight = menuRect.right + gap + panelWidth <= window.innerWidth - inset;
    panel.dataset.side = showRight ? 'right' : 'left';
    const preferredLeft = showRight ? menuRect.right + gap : menuRect.left - gap - panelWidth;
    panel.style.left = `${Math.max(inset, Math.min(window.innerWidth - panelWidth - inset, preferredLeft))}px`;
    const tableRect = tableButton.getBoundingClientRect(); panel.style.top = `${Math.max(inset, Math.min(window.innerHeight - panel.offsetHeight - inset, tableRect.top))}px`;
    slashTablePanelElement = panel;
  } else if (slashRuntime.tableMenuBaseLeft) {
    slashMenuElement.style.left = slashRuntime.tableMenuBaseLeft; slashRuntime.tableMenuBaseLeft = '';
  }
  syncSlashAccessibility();
};

/** Handles command navigation before the editor's ordinary key handlers. */
const handleSlashMenuKeyDown = (view, event) => {
  const context = slashContextForView(view);
  if (slashMenuElement.dataset.show !== 'true' || !context || event.isComposing || event.keyCode === 229) return false;
  if (event.key === 'Escape') { slashRuntime.dismissedContext = context.key; slashRuntime.provider?.hide(); event.preventDefault(); return true; }
  if (slashRuntime.tableOpen) {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') { const delta = event.key === 'ArrowLeft' ? -1 : 1; if (slashRuntime.tableFocus === 'rows') slashRuntime.tableRows = Math.min(20, Math.max(1, slashRuntime.tableRows + delta)); else slashRuntime.tableColumns = Math.min(12, Math.max(1, slashRuntime.tableColumns + delta)); renderSlashMenu(); event.preventDefault(); return true; }
    if (['Tab', 'ArrowUp', 'ArrowDown'].includes(event.key)) { slashRuntime.tableFocus = slashRuntime.tableFocus === 'rows' ? 'columns' : 'rows'; renderSlashMenu(); event.preventDefault(); return true; }
    if (event.key === 'Enter') { executeSlashCommand('table'); event.preventDefault(); return true; }
  }
  if (event.key === 'ArrowUp' || event.key === 'ArrowDown') { if (!slashRuntime.commands.length) return true; slashRuntime.activeIndex = (slashRuntime.activeIndex + (event.key === 'ArrowUp' ? -1 : 1) + slashRuntime.commands.length) % slashRuntime.commands.length; slashRuntime.tableOpen = false; renderSlashMenu(); event.preventDefault(); return true; }
  const active = slashRuntime.commands[slashRuntime.activeIndex];
  if (event.key === 'ArrowRight' && active?.id === 'table') { slashRuntime.tableOpen = true; renderSlashMenu(); event.preventDefault(); return true; }
  if (event.key === 'Enter' && active) { if (active.id === 'table') { slashRuntime.tableOpen = true; renderSlashMenu(); } else executeSlashCommand(active.id); event.preventDefault(); return true; }
  if (event.key === 'Tab' && active?.id !== 'table') { executeSlashCommand(active.id); event.preventDefault(); return true; }
  return false;
};

document.documentElement.dataset.weibeiCompactPreview = isCompactPreview ? 'true' : 'false';

let contentHeightFrame = 0;
let lastReportedContentHeight = 0;
let lastReportedContentWidth = 0;
const contentHeightDelayHandles = new Set();

const compactPreviewMeasureNodes = () => [
  document.querySelector('#editor'),
  document.querySelector('.milkdown'),
  document.querySelector('.ProseMirror'),
].filter(Boolean);

const measuredNodeHeight = (node) => {
  const rect = node.getBoundingClientRect?.();
  return Math.max(
    0,
    node.scrollHeight || 0,
    node.offsetHeight || 0,
    node.clientHeight || 0,
    rect?.height || 0
  );
};

const publishContentHeight = () => {
  const nodes = compactPreviewMeasureNodes();
  const height = Math.ceil(Math.max(1, ...nodes.map(measuredNodeHeight)));
  const width = Math.ceil(Math.max(1, ...nodes.map((node) => (
    node.getBoundingClientRect?.().width || node.clientWidth || 0
  ))));
  window.WeiBeiCompactPreviewHeight = height;
  window.WeiBeiCompactPreviewMeasuredAt = Date.now();
  if (
    Math.abs(height - lastReportedContentHeight) < 1
    && Math.abs(width - lastReportedContentWidth) < 1
  ) return;
  lastReportedContentHeight = height;
  lastReportedContentWidth = width;
  post('contentHeightChanged', { height });
};

const reportContentHeight = () => {
  if (!isCompactPreview) return;
  // Background/off-screen WKWebViews can throttle requestAnimationFrame.
  // Publish once synchronously so compact Chat rows still receive a real
  // height, then measure again on the next painted frame for font/layout drift.
  publishContentHeight();
  window.cancelAnimationFrame(contentHeightFrame);
  contentHeightFrame = window.requestAnimationFrame(publishContentHeight);
};

const scheduleContentHeightReports = () => {
  if (!isCompactPreview) return;
  for (const handle of contentHeightDelayHandles) window.clearTimeout(handle);
  contentHeightDelayHandles.clear();
  lastReportedContentHeight = 0;
  lastReportedContentWidth = 0;
  reportContentHeight();
  window.requestAnimationFrame(() => {
    reportContentHeight();
    window.requestAnimationFrame(reportContentHeight);
  });
  for (const delay of [40, 120, 240, 480]) {
    const handle = window.setTimeout(() => {
      contentHeightDelayHandles.delete(handle);
      reportContentHeight();
    }, delay);
    contentHeightDelayHandles.add(handle);
  }
  document.fonts?.ready?.then(() => {
    if (isCompactPreview) reportContentHeight();
  }).catch(() => {});
};

const installContentHeightObserver = () => {
  if (!isCompactPreview) return;
  if (window.ResizeObserver) {
    const observer = new ResizeObserver(reportContentHeight);
    compactPreviewMeasureNodes().forEach((node) => observer.observe(node));
  }
  scheduleContentHeightReports();
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
  document.querySelectorAll('.weibei-code-language-input').forEach((input) => {
    if (!(input instanceof HTMLInputElement)) return;
    input.readOnly = !isEditable;
    input.tabIndex = isEditable ? 0 : -1;
    input.setAttribute('aria-readonly', input.readOnly ? 'true' : 'false');
    input.setAttribute('aria-label', editorLabel('codeLanguage'));
    input.placeholder = editorLabel('codeLanguagePlaceholder');
  });
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

let mermaidPreviewCache = new WeakMap();
let activeMermaidPreview = null;
let mermaidSourceHasFocus = false;

/** Returns the Mermaid code block containing the focused text selection. */
const focusedMermaidBlock = (state) => {
  if (!mermaidSourceHasFocus || !(state.selection instanceof TextSelection)) return null;
  const { $from } = state.selection;
  for (let depth = $from.depth; depth > 0; depth -= 1) {
    const node = $from.node(depth);
    if (node.type.name !== 'code_block') continue;
    if (normalizeLanguage(node.attrs.language || '') !== 'mermaid') return null;
    return { node, pos: $from.before(depth) };
  }
  return null;
};

/** Ends the active edit snapshot when focus or document identity changes. */
const synchronizeActiveMermaidPreview = (focusedBlock) => {
  if (!activeMermaidPreview) return;
  if (activeMermaidPreview.documentGeneration !== currentDocumentGeneration || activeMermaidPreview.contentGeneration !== currentContentGeneration || activeMermaidPreview.generation !== mermaidPreviewGeneration || focusedBlock?.pos !== activeMermaidPreview.pos) activeMermaidPreview = null;
};

/** Creates or reuses the SVG preview committed for a Mermaid block. */
const mermaidPreviewForBlock = (node, pos, focusedBlock) => {
  const isFocused = focusedBlock?.pos === pos;
  if (isFocused && !activeMermaidPreview) {
    const cached = mermaidPreviewCache.get(node);
    activeMermaidPreview = cached?.generation === mermaidPreviewGeneration
      ? { ...cached, pos, documentGeneration: currentDocumentGeneration, contentGeneration: currentContentGeneration }
      : { element: mermaidWidget(node.textContent), generation: mermaidPreviewGeneration, key: `mermaid-preview-${mermaidPreviewID += 1}`, pos, documentGeneration: currentDocumentGeneration, contentGeneration: currentContentGeneration };
  }
  if (isFocused) return activeMermaidPreview;
  const cached = mermaidPreviewCache.get(node);
  if (cached?.generation === mermaidPreviewGeneration) return cached;
  const preview = { element: mermaidWidget(node.textContent), generation: mermaidPreviewGeneration, key: `mermaid-preview-${mermaidPreviewID += 1}` };
  mermaidPreviewCache.set(node, preview);
  return preview;
};

const decorateMermaidBlock = (decorations, node, pos, focusedBlock) => {
  if (normalizeLanguage(node.attrs.language || '') !== 'mermaid') return false;
  decorations.push(Decoration.node(pos, pos + node.nodeSize, {
    class: 'weibei-code-block weibei-mermaid-block',
    'data-language': 'mermaid',
  }));
  const preview = mermaidPreviewForBlock(node, pos, focusedBlock);
  // Keep the block preview outside contentDOM so ProseMirror can place its
  // trailing caret break directly after source text that ends in a newline.
  decorations.push(Decoration.widget(pos + node.nodeSize, () => preview.element, { side: -1, key: preview.key }));
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

/**
 * Creates a code block NodeView whose `<code>` child is ProseMirror's only contentDOM.
 *
 * The language control stays in the `<pre>` shell, preventing it from becoming a
 * text decoration inside the editable code content.
 */
const createCodeBlockNodeView = (node, view, getPos) => {
  const pre = document.createElement('pre');
  pre.className = 'weibei-code-block';
  const input = document.createElement('input');
  input.type = 'text';
  input.className = 'weibei-code-language-input';
  input.maxLength = 32;
  input.setAttribute('autocomplete', 'off');
  input.setAttribute('autocapitalize', 'none');
  input.setAttribute('spellcheck', 'false');
  const code = document.createElement('code');
  code.setAttribute('autocapitalize', 'none');
  code.setAttribute('autocorrect', 'off');
  code.setAttribute('spellcheck', 'false');
  pre.append(input, code);
  let language = String(node.attrs.language || '');
  const documentID = currentDocumentID;
  const documentGeneration = currentDocumentGeneration;
  const contentGeneration = currentContentGeneration;
  const syncControl = () => {
    pre.dataset.language = language;
    input.value = language;
    input.placeholder = editorLabel('codeLanguagePlaceholder');
    input.setAttribute('aria-label', editorLabel('codeLanguage'));
    input.readOnly = !isEditable;
    input.tabIndex = isEditable ? 0 : -1;
    input.setAttribute('aria-readonly', input.readOnly ? 'true' : 'false');
  };
  const commit = () => {
    const next = input.value.trim().split(/\s+/u)[0]?.slice(0, 32) || '';
    input.value = next;
    if (!isEditable || next === language || documentID !== currentDocumentID || documentGeneration !== currentDocumentGeneration || contentGeneration !== currentContentGeneration) { input.value = language; return; }
    const position = getPos();
    const current = view.state.doc.nodeAt(position);
    if (current?.type.name !== 'code_block' || String(current.attrs.language || '') !== language) { input.value = language; return; }
    view.dispatch(view.state.tr.setNodeMarkup(position, undefined, { ...current.attrs, language: next }));
  };
  const onKeyDown = (event) => {
    if (event.key === 'Escape') { input.value = language; input.blur(); return; }
    if (event.key !== 'Enter') return;
    event.preventDefault();
    commit();
    input.blur();
    view.focus();
  };
  input.addEventListener('change', commit);
  input.addEventListener('blur', commit);
  input.addEventListener('keydown', onKeyDown);
  syncControl();
  return {
    dom: pre,
    contentDOM: code,
    update(nextNode) {
      if (nextNode.type.name !== 'code_block') return false;
      // A document replacement must not reuse a control that captured an older generation.
      if (documentID !== currentDocumentID || documentGeneration !== currentDocumentGeneration || contentGeneration !== currentContentGeneration) return false;
      language = String(nextNode.attrs.language || '');
      syncControl();
      return true;
    },
    stopEvent(event) { return event.target === input || (event.target instanceof Node && input.contains(event.target)); },
    ignoreMutation(mutation) { return mutation.target === input || input.contains(mutation.target); },
    destroy() {
      input.removeEventListener('change', commit);
      input.removeEventListener('blur', commit);
      input.removeEventListener('keydown', onKeyDown);
    },
  };
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

// plugin-math renders math_block nodes with inline-mode KaTeX (its shared
// options cannot enable displayMode without breaking inline math). Re-render
// block nodes in display mode so fractions, limits and sizing read like real
// display equations; KaTeX centers them natively via .katex-display.
const upgradeDisplayMath = () => {
  // Synchronous on purpose: requestAnimationFrame never fires in occluded or
  // offscreen WKWebViews (chat previews measure while hidden), which left
  // block math stuck in inline mode. The dialect plugin already calls this
  // after ProseMirror has flushed the DOM.
  document
    .querySelectorAll('.ProseMirror div[data-type="math_block"], .ProseMirror div[data-type="math-block"]')
    .forEach((element) => {
      const value = element.dataset.value || '';
      if (element.dataset.weibeiDisplayValue === value) return;
      try {
        katex.render(value, element, {
          throwOnError: false,
          strict: false,
          trust: false,
          displayMode: true,
        });
        element.dataset.weibeiDisplayValue = value;
      } catch (error) {
        // Keep the inline-mode render; annotateMathErrors covers bad input.
      }
    });
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

/** Converts an empty code block back to a paragraph for Backspace and Delete. */
const clearEmptyCodeBlock = (view, event) => {
  if (!isEditable || event.shiftKey || event.altKey || event.metaKey || event.ctrlKey || !['Backspace', 'Delete'].includes(event.key)) return false;
  const { selection, schema } = view.state;
  return selection instanceof TextSelection && selection.empty && selection.$from.parent.type.spec.code === true && selection.$from.parent.content.size === 0 && Boolean(schema.nodes.paragraph && setBlockType(schema.nodes.paragraph)(view.state, view.dispatch));
};

/** Inserts a literal tab character without moving focus out of a code block. */
const insertCodeBlockTab = (view, event) => {
  if (!isEditable || event.key !== 'Tab' || event.shiftKey || event.altKey || event.metaKey || event.ctrlKey || event.isComposing || event.keyCode === 229) return false;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || selection.$from.parent !== selection.$to.parent || selection.$from.parent.type.spec.code !== true) return false;
  const transaction = view.state.tr.replaceWith(selection.from, selection.to, view.state.schema.text('\t'));
  view.dispatch(transaction.setSelection(TextSelection.create(transaction.doc, selection.from + 1)).scrollIntoView());
  return true;
};

const literalCodeBlockCharacters = new Set(['-', "'", '"']);

/** Inserts ASCII punctuation directly so WebKit cannot apply smart substitutions. */
const insertLiteralCodeBlockCharacter = (view, event) => {
  if (!isEditable || !literalCodeBlockCharacters.has(event.key) || event.altKey || event.metaKey || event.ctrlKey || event.isComposing || event.keyCode === 229) return false;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || selection.$from.parent !== selection.$to.parent || selection.$from.parent.type.spec.code !== true) return false;
  const transaction = view.state.tr.replaceWith(selection.from, selection.to, view.state.schema.text(event.key));
  view.dispatch(transaction.setSelection(TextSelection.create(transaction.doc, selection.from + event.key.length)).scrollIntoView());
  return true;
};

/** Rejects spell checking, text replacement, and writing suggestion edits in code blocks. */
const preventCodeBlockAutomaticReplacement = (view, event) => {
  if (!isEditable || event.inputType !== 'insertReplacementText' || event.isComposing || !event.cancelable) return false;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || selection.$from.parent !== selection.$to.parent || selection.$from.parent.type.spec.code !== true) return false;
  event.preventDefault();
  event.stopImmediatePropagation();
  return true;
};

/** Leaves a terminal code block only at the document's final visual or logical line. */
const exitTerminalCodeBlock = (view, event) => {
  if (!isEditable || event.shiftKey || event.altKey || event.metaKey || event.ctrlKey || !['ArrowRight', 'ArrowDown'].includes(event.key)) return false;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || !selection.empty || selection.$from.parent.type.spec.code !== true) return false;
  const { $from } = selection;
  if ($from.indexAfter(-1) !== $from.node(-1).childCount) return false;
  if (event.key === 'ArrowRight' && $from.parentOffset !== $from.parent.content.size) return false;
  if (event.key === 'ArrowDown' && !view.endOfTextblock('down') && $from.parentOffset !== $from.parent.content.size) return false;
  return exitCode(view.state, view.dispatch);
};

const weiBeiDialectPlugin = $prose(() => new Plugin({
  view(view) {
    const codeInputAttributeValues = { autocapitalize: 'none', autocorrect: 'off', spellcheck: 'false' };
    const defaultCodeInputAttributes = new Map(Object.keys(codeInputAttributeValues).map((name) => [name, view.dom.getAttribute(name)]));
    /** Applies literal-input attributes only while the selection is inside a code block. */
    const synchronizeCodeInputAttributes = (updatedView) => {
      if (updatedView.state.selection.$from.parent.type.spec.code === true) {
        for (const [name, value] of Object.entries(codeInputAttributeValues)) updatedView.dom.setAttribute(name, value);
        return;
      }
      for (const [name, value] of defaultCodeInputAttributes) {
        if (value === null) updatedView.dom.removeAttribute(name);
        else updatedView.dom.setAttribute(name, value);
      }
    };
    const setMermaidSourceFocus = (focused) => {
      if (mermaidSourceHasFocus === focused) return;
      mermaidSourceHasFocus = focused;
      view.dispatch(view.state.tr.setMeta('weibeiMermaidFocusChanged', focused));
    };
    const handleEditorFocus = (event) => setMermaidSourceFocus(event.target === view.dom);
    const handleEditorBlur = (event) => { if (event.target === view.dom) setMermaidSourceFocus(false); };
    const handleCompositionStart = () => {
      compositionStartMarkdown = getMarkdownInternal();
      compositionEndPending = false;
      const { $from } = view.state.selection;
      compositionTextblockFrom = $from.parent.isTextblock && $from.parent.content.size === 0 ? $from.before($from.depth) : null;
    };
    const handleCompositionEnd = () => {
      compositionEndPending = true;
      setTimeout(publishCompletedCompositionMarkdown);
    };
    /** Handles literal code-block keys before WebKit's native text substitution runs. */
    const handleCodeBlockKeyDown = (event) => {
      if (event.target !== view.dom || !view.hasFocus() || (!insertCodeBlockTab(view, event) && !insertLiteralCodeBlockCharacter(view, event))) return;
      event.preventDefault();
      event.stopImmediatePropagation();
    };
    /** Cancels automatic replacement events without affecting composition or paste input. */
    const handleBeforeInput = (event) => {
      if (event.target === view.dom) preventCodeBlockAutomaticReplacement(view, event);
    };
    view.dom.addEventListener('compositionstart', handleCompositionStart, true);
    view.dom.addEventListener('compositionend', handleCompositionEnd, true);
    view.dom.addEventListener('focus', handleEditorFocus, true);
    view.dom.addEventListener('blur', handleEditorBlur, true);
    view.dom.addEventListener('keydown', handleCodeBlockKeyDown, true);
    view.dom.addEventListener('beforeinput', handleBeforeInput, true);
    synchronizeCodeInputAttributes(view);
    mermaidSourceHasFocus = view.hasFocus();
    scheduleImageResolution(view);
    annotateMathErrors();
    upgradeDisplayMath();
    return {
      update(updatedView) {
        synchronizeCodeInputAttributes(updatedView);
        scheduleImageResolution(updatedView);
        annotateMathErrors();
        upgradeDisplayMath();
      },
      destroy() {
        view.dom.removeEventListener('compositionstart', handleCompositionStart, true);
        view.dom.removeEventListener('compositionend', handleCompositionEnd, true);
        view.dom.removeEventListener('focus', handleEditorFocus, true);
        view.dom.removeEventListener('blur', handleEditorBlur, true);
        view.dom.removeEventListener('keydown', handleCodeBlockKeyDown, true);
        view.dom.removeEventListener('beforeinput', handleBeforeInput, true);
        for (const [name, value] of defaultCodeInputAttributes) {
          if (value === null) view.dom.removeAttribute(name);
          else view.dom.setAttribute(name, value);
        }
        mermaidSourceHasFocus = false;
        activeMermaidPreview = null;
        mermaidPreviewCache = new WeakMap();
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
      if (handleSlashMenuKeyDown(view, event)) return true;
      if (clearEmptyCodeBlock(view, event) || exitTerminalCodeBlock(view, event)) { event.preventDefault(); return true; }
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
      const focusedBlock = focusedMermaidBlock(state);
      synchronizeActiveMermaidPreview(focusedBlock);

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
          if (decorateMermaidBlock(decorations, node, pos, focusedBlock)) return false;
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

/** Removes WebKit-created line breaks when IME composition began in an empty text block. */
const normalizeCompletedEmptyTextblockComposition = () => {
  if (!editor || compositionTextblockFrom === null) return;
  const textblockFrom = compositionTextblockFrom;
  compositionTextblockFrom = null;
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.domObserver?.flush();
    const textblock = view.state.doc.nodeAt(textblockFrom);
    if (!textblock?.isTextblock || !textblock.textContent) return;
    const hardbreak = view.state.schema.nodes.hardbreak || view.state.schema.nodes.hard_break;
    const content = [];
    for (let index = 0; index < textblock.childCount; index += 1) {
      const child = textblock.child(index);
      if (child.type !== hardbreak) content.push(child);
    }
    if (content.length !== textblock.childCount) {
      const cleaned = textblock.type.create(textblock.attrs, Fragment.fromArray(content), textblock.marks);
      const tr = view.state.tr.replaceWith(textblockFrom, textblockFrom + textblock.nodeSize, cleaned).scrollIntoView();
      tr.setSelection(TextSelection.create(tr.doc, Math.min(textblockFrom + 1 + cleaned.content.size, tr.doc.content.size)));
      view.dispatch(tr);
    }
    const textblockDOM = view.nodeDOM(textblockFrom);
    if (textblockDOM instanceof HTMLElement) {
      textblockDOM.querySelectorAll('br').forEach((node) => node.remove());
      view.domObserver?.flush();
    }
  });
};

/** Publishes only the final IME composition snapshot to the Swift host. */
const publishCompletedCompositionMarkdown = () => {
  if (!editor) return;
  normalizeCompletedEmptyTextblockComposition();
  compositionEndPending = false;
  if (compositionStartMarkdown === null) return;
  const start = compositionStartMarkdown;
  const next = getMarkdownInternal();
  compositionStartMarkdown = null;
  lastMarkdown = next;
  if (next === start) return;
  post('markdownChanged', { markdown: next });
  scheduleContentHeightReports();
  reportActiveHeading();
};

const streamingCommands = () => editor.action((ctx) => ctx.get(commandsCtx));

const stopStreamingMarkdown = (keep = true) => {
  if (streamingMarkdownBuffer === null) return;
  streamingCommands().call(abortStreamingCmd.key, { keep });
  streamingMarkdownBuffer = null;
};

const updateStreamingMarkdownInternal = (markdown) => {
  ensureEditor();
  const document = splitFrontmatter(markdown || '');
  const body = normalizeHtmlBreaks(document.body);
  frontmatterBlock = document.frontmatter;
  syncFrontmatterPanel();
  const commands = streamingCommands();
  if (streamingMarkdownBuffer === null) {
    commands.call(startStreamingCmd.key);
    streamingMarkdownBuffer = '';
  } else if (!body.startsWith(streamingMarkdownBuffer)) {
    commands.call(endStreamingCmd.key, { diffReview: false });
    commands.call(startStreamingCmd.key);
    streamingMarkdownBuffer = '';
  }
  const delta = body.slice(streamingMarkdownBuffer.length);
  if (delta) commands.call(pushChunkCmd.key, delta);
  streamingMarkdownBuffer = body;
  lastMarkdown = withFrontmatter(body);
  scheduleContentHeightReports();
};

const finishStreamingMarkdownInternal = (markdown) => {
  updateStreamingMarkdownInternal(markdown);
  streamingCommands().call(endStreamingCmd.key, { diffReview: false });
  streamingMarkdownBuffer = null;
  scheduleContentHeightReports();
};

const setMarkdownInternal = (markdown) => {
  ensureEditor();
  stopStreamingMarkdown();
  compositionStartMarkdown = null;
  compositionTextblockFrom = null;
  compositionEndPending = false;
  currentContentGeneration += 1;
  const document = splitFrontmatter(markdown || '');
  const body = normalizeHtmlBreaks(document.body);
  frontmatterBlock = document.frontmatter;
  syncFrontmatterPanel();
  editor.action(replaceAll(body));
  lastMarkdown = withFrontmatter(body);
  scheduleContentHeightReports();
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
  setMarkdown: (markdown) => {
    setMarkdownInternal(markdown);
    post('markdownChanged', { markdown: String(markdown || '') });
  },
  // Milkdown's streaming plugin reparses the cumulative snapshot and applies a
  // ProseMirror document diff, preserving unchanged DOM instead of rebuilding
  // the whole answer or parsing token fragments as standalone paragraphs.
  updateStreamingMarkdown: (markdown) => {
    try {
      updateStreamingMarkdownInternal(markdown);
    } catch (error) {
      showFailure(error);
    }
  },
  finishStreamingMarkdown: (markdown) => {
    try {
      finishStreamingMarkdownInternal(markdown);
      return true;
    } catch (error) {
      showFailure(error);
      return false;
    }
  },
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
  resolveImagePicker: (id, src, alt) => {
    const pending = pendingImagePickers.get(id);
    if (!pending) return false;
    pendingImagePickers.delete(id);
    if (pending.documentID !== currentDocumentID || pending.documentGeneration !== currentDocumentGeneration) return false;
    return applySlashReplacement(pending.view, pending.context, slashReplacement('image', pending.view.state.schema, { src, alt }));
  },
  cancelImagePicker: (id) => {
    const pending = pendingImagePickers.get(id);
    if (!pending) return false;
    pendingImagePickers.delete(id);
    return pending.documentID === currentDocumentID && pending.documentGeneration === currentDocumentGeneration;
  },
  discardImagePicker: (id) => pendingImagePickers.delete(id),
  rejectImagePicker: (id, message) => {
    const pending = pendingImagePickers.get(id);
    if (!pending) return false;
    pendingImagePickers.delete(id);
    if (pending.documentID !== currentDocumentID || pending.documentGeneration !== currentDocumentGeneration) return false;
    slashRuntime.dismissedContext = '';
    slashRuntime.error = message || editorLabel('slashImageFailed');
    slashRuntime.view = pending.view;
    slashRuntime.provider?.show();
    renderSlashMenu();
    return true;
  },
  setEditable: (next) => {
    isEditable = next !== false;
    syncEditableState();
  },
  setDocumentID: (next) => {
    const nextID = next || '';
    if (nextID !== currentDocumentID) {
      currentDocumentID = nextID;
      currentDocumentGeneration += 1;
      currentContentGeneration += 1;
      pendingImagePickers.clear();
      pendingAttachments.clear();
    }
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
    syncEditableState();
    if (slashMenuElement.dataset.show === 'true') renderSlashMenu();
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
  window.WeiBeiEditor.compositionStateForCheck = () => ({ start: compositionStartMarkdown, last: lastMarkdown, composing: editor.action((ctx) => ctx.get(editorViewCtx).composing) });
  window.WeiBeiEditor.openSlashMenuForCheck = () => { const view = slashRuntime.view; if (!view || !slashContextForView(view)) return false; slashRuntime.dismissedContext = ''; slashRuntime.provider?.show(); renderSlashMenu(); return slashMenuElement.dataset.show === 'true'; };
  window.WeiBeiEditor.slashStateForCheck = () => ({ show: slashMenuElement.dataset.show === 'true', commands: Array.from(slashMenuElement.querySelectorAll('.weibei-slash-command-button')).map((button) => button.textContent), groups: Array.from(slashMenuElement.querySelectorAll('.weibei-slash-group')).map((group) => group.textContent), rows: slashRuntime.tableRows, columns: slashRuntime.tableColumns, tableOpen: slashRuntime.tableOpen, tableSide: slashTablePanelElement?.dataset.side || '', activeDescendant: slashRuntime.view?.dom.getAttribute('aria-activedescendant') || '', announcement: slashStatusElement.textContent, error: slashRuntime.error });
  window.WeiBeiEditor.renderSlashMenuForCheck = renderSlashMenu;
  window.WeiBeiEditor.executeSlashCommandForCheck = (id) => executeSlashCommand(id);
  window.WeiBeiEditor.pendingImagePickerIDsForCheck = () => Array.from(pendingImagePickers.keys());
  window.WeiBeiEditor.undoForCheck = () => editor.action((ctx) => undo(ctx.get(editorViewCtx).state, ctx.get(editorViewCtx).dispatch));
  window.WeiBeiEditor.selectFirstCodeBlockEndForCheck = () => editor.action((ctx) => { const view = ctx.get(editorViewCtx); let target = null; view.state.doc.descendants((node, pos) => { if (target !== null || node.type.name !== 'code_block') return true; target = pos + node.content.size + 1; return false; }); if (target === null) return false; view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, target))); view.focus(); return true; });
  window.WeiBeiEditor.selectDocumentEndForCheck = () => editor.action((ctx) => { const view = ctx.get(editorViewCtx); view.dispatch(view.state.tr.setSelection(Selection.atEnd(view.state.doc))); view.focus(); return true; });
  window.WeiBeiEditor.selectionForCheck = () => editor.action((ctx) => {
    const selection = ctx.get(editorViewCtx).state.selection;
    return { from: selection.from, to: selection.to, parent: selection.$from.parent.type.name, parentOffset: selection.$from.parentOffset };
  });
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
      nodeViews: { code_block: createCodeBlockNodeView },
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
    ctx.set(streamingConfig.key, {
      throttleMs: 0,
      scrollFollow: false,
      diffReviewOnEnd: false,
      ignoreAttrs: { heading: ['id'] },
    });
  })
  .config((ctx) => {
    ctx.set(weiBeiSlash.key, {
      view(view) {
        document.body.appendChild(slashStatusElement);
        const provider = new SlashProvider({ content: slashMenuElement, debounce: 0, offset: 6, root: document.body, shouldShow: (updatedView) => { const context = slashContextForView(updatedView); return Boolean(context && slashRuntime.dismissedContext !== context.key); } });
        slashRuntime.provider = provider; slashRuntime.view = view;
        provider.onShow = () => { slashRuntime.view = view; renderSlashMenu(); };
        provider.onHide = () => { slashRuntime.context = null; slashRuntime.tableOpen = false; if (slashRuntime.tableMenuBaseLeft) { slashMenuElement.style.left = slashRuntime.tableMenuBaseLeft; slashRuntime.tableMenuBaseLeft = ''; } slashTablePanelElement?.remove(); slashTablePanelElement = null; syncSlashAccessibility(); };
        provider.update(view);
        return { update(updatedView, previousState) { slashRuntime.view = updatedView; const context = slashContextForView(updatedView); if (slashRuntime.dismissedContext && context?.key !== slashRuntime.dismissedContext) slashRuntime.dismissedContext = ''; provider.update(updatedView, previousState); }, destroy() { provider.destroy(); slashMenuElement.remove(); slashStatusElement.remove(); slashTablePanelElement?.remove(); slashRuntime.provider = null; slashRuntime.view = null; } };
      },
    });
  })
  .use(weiBeiDialectPlugin)
  .use(weiBeiSlash)
  .use(history)
  .use(commonmark)
  .use(gfm)
  .use(math)
  .use(streaming)
  .use(upload)
  .use(listener)
  .config((ctx) => {
    ctx.get(listenerCtx).markdownUpdated((listenerContext, markdown) => {
      const normalizedMarkdown = withFrontmatter(markdown);
      if (normalizedMarkdown === lastMarkdown) return;
      lastMarkdown = normalizedMarkdown;
      if (listenerContext.get(editorViewCtx).composing || compositionEndPending) {
        scheduleContentHeightReports();
        reportActiveHeading();
        return;
      }
      compositionStartMarkdown = null;
      post('markdownChanged', { markdown: normalizedMarkdown });
      scheduleContentHeightReports();
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
      if (!activateWikiLink(event.target)) return;
      event.preventDefault();
      event.stopPropagation();
    }, true);
    document.addEventListener('keyup', (event) => {
      reportSelection();
    });
    document.addEventListener('scroll', reportActiveHeading, true);
    post('editorReady', { markdown: lastMarkdown });
    installContentHeightObserver();
    reportActiveHeading();
  })
  .catch(showFailure);
