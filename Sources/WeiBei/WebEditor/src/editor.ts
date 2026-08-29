import { commandsCtx, Editor, defaultValueCtx, editorViewCtx, editorViewOptionsCtx, rootCtx } from '@milkdown/kit/core';
import { commonmark } from '@milkdown/kit/preset/commonmark';
import { gfm } from '@milkdown/kit/preset/gfm';
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener';
import { history } from '@milkdown/kit/plugin/history';
import { clipboard } from '@milkdown/kit/plugin/clipboard';
import {
  abortStreamingCmd,
  endStreamingCmd,
  pushChunkCmd,
  startStreamingCmd,
  streaming,
  streamingConfig,
  streamingPluginKey,
} from '@milkdown/plugin-streaming';
import { streamingAppearancePlugin } from './streaming-appearance';
import { createSyntaxMarksPlugin } from './syntax-marks';
import { SlashProvider, slashFactory } from '@milkdown/kit/plugin/slash';
import { readImageAsBase64, upload, uploadConfig } from '@milkdown/kit/plugin/upload';
import { exitCode, lift, setBlockType, toggleMark, wrapIn } from '@milkdown/kit/prose/commands';
import { closeHistory, redo, undo } from '@milkdown/kit/prose/history';
import { nodeRule } from '@milkdown/kit/prose';
import { Fragment } from '@milkdown/kit/prose/model';
import { NodeSelection, Plugin, Selection, TextSelection } from '@milkdown/kit/prose/state';
import { liftListItem, sinkListItem } from '@milkdown/kit/prose/schema-list';
import { addColumn, addColumnAfter, addRow, addRowAfter, columnResizing, deleteColumn, deleteRow, deleteTable, goToNextCell, isInTable, selectedRect, TableMap } from '@milkdown/kit/prose/tables';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';
import { getMarkdown as readMarkdown, insert, replaceAll, replaceRange, $inputRule, $prose } from '@milkdown/kit/utils';
import {
  mathBlockInputRule,
  mathBlockSchema,
  mathInlineSchema,
  remarkMathPlugin,
} from './mathExtension';
import { loadedKaTeX, loadKaTeX, loadMermaid, loadPrism } from './localRuntime';
import {
  calloutTypePattern,
  inlineMathInputPattern,
  joinFrontmatter,
  looksLikeMarkdownSyntax,
  normalizeMarkdownSource,
  splitFrontmatter,
} from './markdownRules';
import {
  addEditorMetric,
  createEditorCheckMetrics,
  resetEditorCheckMetrics,
} from './checkMetrics';
import { outlineChangeKey, type EditorOutlineItem } from './outline';
import {
  acceptsEditorCommand,
  createEditorEvent,
  editorProtocolVersion,
  parseEditorCommand,
  reduceRevision,
  type EditorCommand,
} from './bridge/protocol';
import { structuredMarkdown } from './structuredMarkdown';

declare const WEIBEI_EDITOR_RUNTIME: boolean;

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: any;
    };
    weiBeiMarkdownEditable?: boolean;
    weiBeiMarkdownCompactPreview?: boolean;
    weiBeiDocumentID?: string;
    weiBeiDocumentGeneration?: number;
    weiBeiMarkdownBaseURL?: string;
    weiBeiLocalImageScheme?: string;
    weiBeiInterfaceLanguage?: unknown;
    weiBeiTheme?: unknown;
    weiBeiSuppressSelectionReport?: boolean;
    weiBeiEditorCheckMode?: boolean;
    initialMarkdown?: string;
    WeiBeiEditorBootFailed?: (error: unknown) => void;
    WeiBeiEditor?: Record<string, unknown>;
    WeiBeiCompactPreviewHeight?: number;
    WeiBeiCompactPreviewMeasuredAt?: number;
  }
}

const bridge = window.webkit?.messageHandlers;
const checkMetrics = window.weiBeiEditorCheckMode ? createEditorCheckMetrics() : null;
let editor: Editor;
let lastMarkdown = '';
let compositionStartMarkdown: string | null = null;
let compositionTextblockFrom: number | null = null;
let compositionEndPending = false;
let lastSelectionRange: { from: number; to: number } | null = null;
let lastSelectionReport: { text: string | null; rectKey: string | null; detailKey: string | null } = { text: null, rectKey: null, detailKey: null };
let frontmatterBlock = '';
let isEditable = WEIBEI_EDITOR_RUNTIME && window.weiBeiMarkdownEditable !== false;
const isCompactPreview = window.weiBeiMarkdownCompactPreview === true;
let currentDocumentID = window.weiBeiDocumentID || '';
let currentDocumentGeneration = window.weiBeiDocumentGeneration || 0;
let revisionState = { revision: 0, dirty: false };
const appliedCommandIDs = new Set<string>();
let suppressDirtyTransactions = false;
let editorReadyPosted = false;
let fullMarkdownBridgeMessages = 0;
let markdownBaseURL = window.weiBeiMarkdownBaseURL || '';
const localImageScheme = window.weiBeiLocalImageScheme || 'weibeiimage';
let attachmentRequestID = 0;
let mermaidRenderID = 0;
let mermaidPreviewID = 0;
let mermaidPreviewGeneration = 0;
const pendingAttachments = new Map();
const pendingImagePickers = new Map();
const weiBeiSlash = WEIBEI_EDITOR_RUNTIME ? slashFactory('WEIBEI_BLOCK_COMMAND') : null as any;
let mathTypedLandingPosition: number | null = null;
const weiBeiMathInlineInputRule = WEIBEI_EDITOR_RUNTIME ? $inputRule((ctx) => nodeRule(
  inlineMathInputPattern,
  mathInlineSchema.type(ctx),
  {
    updateCaptured: (captured: any) => ({ group: String(captured.group || '').trim() }),
    beforeDispatch: ({ tr, match, start }: any) => {
      const content = String(match[1] || '').trim();
      if (content) tr.insertText(content, start + 1);
      const landing = start + content.length + 2;
      tr.setSelection(TextSelection.create(tr.doc, landing));
      mathTypedLandingPosition = landing;
    },
  },
)) : null;
const weiBeiMath = [
  remarkMathPlugin,
  mathInlineSchema,
  mathBlockSchema,
  ...(WEIBEI_EDITOR_RUNTIME ? [mathBlockInputRule, weiBeiMathInlineInputRule] : []),
].flat();
let currentContentGeneration = 0;
let streamingMarkdownBuffer: string | null = null;
// Raw body of the last push when it is byte-identical to the processed body
// (normalization was a no-op). While set, a push whose new tail contains none
// of the characters the normalization rules react to can splice the raw tail
// directly, skipping the full-text passes. Any rewriting push clears it.
let streamingRawBody: string | null = null;
// Full markdown text the JS side currently believes is rendered. While set,
// the native side may send only the appended suffix (appendStreamingMarkdown)
// instead of re-sending the whole document on every streaming push.
let streamingFullTextBase: string | null = null;
let selectionAskMarks: any[] = [];
let selectionRemarkMarks: any[] = [];
let decorationGeneration = 0;
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
const calloutPrefixPattern = '(?:\\s*>\\s*)*\\s*';
const normalizeInterfaceLanguage = (value: any) => (value === 'en' ? 'en' : 'zh-Hans');
let currentLanguage: 'en' | 'zh-Hans' = normalizeInterfaceLanguage(window.weiBeiInterfaceLanguage);
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
const calloutLabel = (type: any) => (calloutLabels[currentLanguage] as Record<string, string>)?.[type] || (calloutLabels['zh-Hans'] as Record<string, string>)[type] || type;
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
    uploadingImage: '正在收纳图片...',
    emptyNotePlaceholder: '从这里开始写下第一句…',
    slashNoResults: '没有匹配命令', slashStructure: '结构', slashLists: '列表', slashContent: '内容', slashRichContent: '丰富内容', slashFonts: '字体',
    slashHeading1: '一级标题', slashHeading2: '二级标题', slashHeading3: '三级标题', slashHeading4: '四级标题', slashHeading5: '五级标题', slashHeading6: '六级标题', slashBulletList: '无序列表', slashOrderedList: '有序列表', slashTaskList: '待办列表', slashQuote: '引用', slashCallout: '提示块', slashCode: '代码块', slashDivider: '分隔线', slashTable: '表格', slashImage: '图片', slashMermaid: 'Mermaid 图表', slashLink: '链接', slashWikiLink: '笔记链接', slashFootnote: '脚注', slashInlineMath: '行内公式', slashBlockMath: '块级公式',
    slashFontSystem: '字体：SF Pro / PingFang SC', slashFontSerif: '字体：Songti SC', slashFontLiterary: '字体：WeiBeiStele',
    slashRows: '行', slashColumns: '列', slashInsertTable: '插入表格', slashImageFailed: '图片读取或保存失败', tableAddRow: '＋行', tableDeleteRow: '−行', tableAddColumn: '＋列', tableDeleteColumn: '−列', tableDelete: '删除表格', linkPlaceholder: '链接文字', wikiLinkPlaceholder: '笔记标题', footnotePlaceholder: '脚注内容', codeLanguage: '代码语言', codeLanguagePlaceholder: 'text',
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
    uploadingImage: 'Saving image...',
    emptyNotePlaceholder: 'Start writing here…',
    slashNoResults: 'No matching commands', slashStructure: 'Structure', slashLists: 'Lists', slashContent: 'Content', slashRichContent: 'Rich content', slashFonts: 'Fonts',
    slashHeading1: 'Heading 1', slashHeading2: 'Heading 2', slashHeading3: 'Heading 3', slashHeading4: 'Heading 4', slashHeading5: 'Heading 5', slashHeading6: 'Heading 6', slashBulletList: 'Bulleted list', slashOrderedList: 'Numbered list', slashTaskList: 'To-do list', slashQuote: 'Quote', slashCallout: 'Callout', slashCode: 'Code block', slashDivider: 'Divider', slashTable: 'Table', slashImage: 'Image', slashMermaid: 'Mermaid diagram', slashLink: 'Link', slashWikiLink: 'Note link', slashFootnote: 'Footnote', slashInlineMath: 'Inline formula', slashBlockMath: 'Block formula',
    slashFontSystem: 'Font: SF Pro / PingFang SC', slashFontSerif: 'Font: Songti SC', slashFontLiterary: 'Font: WeiBeiStele',
    slashRows: 'Rows', slashColumns: 'Columns', slashInsertTable: 'Insert table', slashImageFailed: 'Image could not be read or saved', tableAddRow: '+ Row', tableDeleteRow: '− Row', tableAddColumn: '+ Column', tableDeleteColumn: '− Column', tableDelete: 'Delete table', linkPlaceholder: 'Link text', wikiLinkPlaceholder: 'Note title', footnotePlaceholder: 'Footnote', codeLanguage: 'Code language', codeLanguagePlaceholder: 'text',
  },
};
const editorLabel = (key: any, values: any = {}) => {
  let text = (editorLabels[currentLanguage] as Record<string, string>)?.[key] || (editorLabels['zh-Hans'] as Record<string, string>)[key] || key;
  for (const [name, value] of Object.entries(values)) {
    text = text.split(`{${name}}`).join(String(value));
  }
  return text;
};
const frontmatterLabel = () => editorLabel('properties');
const selectedTextCalloutControlRegex = new RegExp(`(^|\\n)\\s*(?:>\\s*)*\\\\?\\[!(?:${calloutTypePattern})\\][+-]?[ \\t]*`, 'gi');
const htmlBreakPattern = /<br\s*\/?>/gi;
const cleanSelectedText = (text: any) => String(text || '')
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
// Glass keeps the matching readable paper palette while exposing its own
// surface flag for translucent menus and other floating editor chrome.
const normalizeTheme = (theme: any) => {
  if (theme === 'glassLight' || theme === 'glassMist') return 'xuan';
  if (theme === 'glassDark' || theme === 'glassSlate') return 'stele';
  if (theme === 'xuan' || theme === 'inkstone' || theme === 'stele' || theme === 'paper') return theme;
  return 'paper';
};
const normalizeGlassTheme = (theme: any) => ['glassLight', 'glassDark', 'glassMist', 'glassSlate'].includes(theme) ? theme : '';
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

const initializeMermaid = (mermaid: any) => {
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: 'base',
    themeVariables: mermaidThemeVariables(),
  });
};

const applyTheme = (theme: any) => {
  currentTheme = normalizeTheme(theme);
  const glassTheme = normalizeGlassTheme(theme);
  document.documentElement.dataset.weibeiTheme = currentTheme;
  if (document.body) document.body.dataset.weibeiTheme = currentTheme;
  if (glassTheme) {
    document.documentElement.dataset.weibeiGlass = glassTheme;
    if (document.body) document.body.dataset.weibeiGlass = glassTheme;
  } else {
    delete document.documentElement.dataset.weibeiGlass;
    if (document.body) delete document.body.dataset.weibeiGlass;
  }
  mermaidPreviewGeneration += 1;
};

applyTheme(window.weiBeiTheme);

const showFailure = (error: any) => {
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

const post = (name: any, body: any = {}) => {
  const handler = bridge?.[name];
  if (!handler) return;
  const message = createEditorEvent({
    documentID: currentDocumentID,
    documentGeneration: currentDocumentGeneration,
    revision: revisionState.revision,
  }, body);
  if (typeof message.markdown === 'string') fullMarkdownBridgeMessages += 1;
  addEditorMetric(checkMetrics, 'bridgeMessages');
  if (checkMetrics) addEditorMetric(checkMetrics, 'bridgeBytes', new TextEncoder().encode(JSON.stringify(message)).byteLength);
  handler.postMessage(message);
};

const slashMenuElement = (WEIBEI_EDITOR_RUNTIME ? document.createElement('div') : null) as HTMLDivElement;
const slashStatusElement = (WEIBEI_EDITOR_RUNTIME ? document.createElement('div') : null) as HTMLDivElement;
const linePlusElement = (WEIBEI_EDITOR_RUNTIME ? document.createElement('button') : null) as HTMLButtonElement;
const tableToolbarElement = (WEIBEI_EDITOR_RUNTIME ? document.createElement('div') : null) as HTMLDivElement;
if (WEIBEI_EDITOR_RUNTIME) {
  slashMenuElement.className = 'weibei-slash-menu';
  slashMenuElement.dataset.show = 'false';
  slashMenuElement.dataset.state = 'closed';
  slashMenuElement.setAttribute('role', 'listbox');
  slashMenuElement.setAttribute('aria-label', 'Slash commands');
  slashStatusElement.className = 'weibei-visually-hidden';
  slashStatusElement.setAttribute('role', 'status');
  slashStatusElement.setAttribute('aria-live', 'polite');
  linePlusElement.type = 'button';
  linePlusElement.className = 'weibei-line-plus';
  linePlusElement.textContent = '＋';
  linePlusElement.setAttribute('aria-label', '插入内容');
  linePlusElement.hidden = true;
  tableToolbarElement.className = 'weibei-table-toolbar';
  tableToolbarElement.dataset.state = 'closed';
  tableToolbarElement.setAttribute('aria-hidden', 'true');
  tableToolbarElement.setAttribute('role', 'toolbar');
  for (const [action, label] of [['addRow', 'tableAddRow'], ['deleteRow', 'tableDeleteRow'], ['addColumn', 'tableAddColumn'], ['deleteColumn', 'tableDeleteColumn'], ['deleteTable', 'tableDelete']]) {
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.action = action;
    button.dataset.label = label;
    tableToolbarElement.append(button);
  }
}
let slashTablePanelElement: HTMLElement | null = null;

const slashGroups = [
  { id: 'structure', label: 'slashStructure' }, { id: 'lists', label: 'slashLists' },
  { id: 'content', label: 'slashContent' }, { id: 'rich', label: 'slashRichContent' }, { id: 'fonts', label: 'slashFonts' },
];
const slashCommands = [
  { id: 'heading1', group: 'structure', label: 'slashHeading1', aliases: ['h1', 'heading_1', 'yjbt', 'yijibiaoti', '一级', '标题1'] },
  { id: 'heading2', group: 'structure', label: 'slashHeading2', aliases: ['h2', 'heading_2', 'ejbt', 'erjibiaoti', '二级', '标题2'] },
  { id: 'heading3', group: 'structure', label: 'slashHeading3', aliases: ['h3', 'heading_3', 'sjbt', 'sanjibiaoti', '三级', '标题3'] },
  { id: 'heading4', group: 'structure', label: 'slashHeading4', aliases: ['h4', 'heading_4', 'sijbt', 'sijibiaoti', '四级', '标题4'] },
  { id: 'heading5', group: 'structure', label: 'slashHeading5', aliases: ['h5', 'heading_5', 'wjbt', 'wujibiaoti', '五级', '标题5'] },
  { id: 'heading6', group: 'structure', label: 'slashHeading6', aliases: ['h6', 'heading_6', 'ljbt', 'liujibiaoti', '六级', '标题6'] },
  { id: 'bulletList', group: 'lists', label: 'slashBulletList', aliases: ['bullet_list', 'bullet', 'ul', 'wxlb', 'wuxuliebiao', '无序', '项目符号'] },
  { id: 'orderedList', group: 'lists', label: 'slashOrderedList', aliases: ['ordered_list', 'ol', 'yxlb', 'youxuliebiao', '有序', '编号'] },
  { id: 'taskList', group: 'lists', label: 'slashTaskList', aliases: ['task_list', 'todo', 'task', 'checklist', 'dblb', 'daibanliebiao', '待办', '任务'] },
  { id: 'quote', group: 'lists', label: 'slashQuote', aliases: ['quote', 'blockquote', 'yy', 'yinyong', '引用'] },
  { id: 'callout', group: 'content', label: 'slashCallout', aliases: ['callout', 'note', 'tsk', 'tishikuai', '提示', '札记'] },
  { id: 'code', group: 'content', label: 'slashCode', aliases: ['code', 'code_block', 'dmk', 'daimakuai', '代码'] },
  { id: 'divider', group: 'content', label: 'slashDivider', aliases: ['divider', 'horizontal_rule', 'hr', 'fgx', 'fengexian', '分隔', '横线'] },
  { id: 'link', group: 'content', label: 'slashLink', aliases: ['link', 'url', 'lj', 'lianjie', '链接', '网址'] },
  { id: 'wikiLink', group: 'content', label: 'slashWikiLink', aliases: ['wiki', 'note_link', 'bjl', 'bijilianjie', '笔记', '双链'] },
  { id: 'footnote', group: 'content', label: 'slashFootnote', aliases: ['footnote', 'note_ref', 'jz', 'jiaozhu', '脚注', '注释'] },
  { id: 'table', group: 'rich', label: 'slashTable', aliases: ['table', 'grid', 'bg', 'biaoge', '表格'] },
  { id: 'image', group: 'rich', label: 'slashImage', aliases: ['image', 'photo', 'picture', 'tp', 'tupian', '图片', '照片'] },
  { id: 'mermaid', group: 'rich', label: 'slashMermaid', aliases: ['mermaid', 'diagram', 'flowchart', 'lct', 'liuchengtu', '图表', '流程图'] },
  { id: 'inlineMath', group: 'rich', label: 'slashInlineMath', aliases: ['math', 'formula', 'inline_math', 'hngs', 'hangneigongshi', '公式', '行内'] },
  { id: 'blockMath', group: 'rich', label: 'slashBlockMath', aliases: ['display_math', 'equation', 'block_math', 'kjgs', 'kuaijigongshi', '方程', '块级'] },
  { id: 'fontSystem', group: 'fonts', label: 'slashFontSystem', aliases: ['font', 'system', 'sf pro', 'pingfang sc', 'ziti', '字体', '苹方'] },
  { id: 'fontSerif', group: 'fonts', label: 'slashFontSerif', aliases: ['font', 'serif', 'songti sc', 'ziti', '字体', '宋体'] },
  { id: 'fontLiterary', group: 'fonts', label: 'slashFontLiterary', aliases: ['font', 'weibeistele', 'wei bei stele', 'ziti', '字体', '魏碑'] },
];
const writingFontValues = new Set(['system', 'serif', 'literary']);
const slashWritingFonts: Record<string, string> = { fontSystem: 'system', fontSerif: 'serif', fontLiterary: 'literary' };
const slashRuntime: {
  provider: any;
  view: any;
  context: any;
  commands: any[];
  activeIndex: number;
  dismissedContext: string;
  activationContext: string;
  tableOpen: boolean;
  tableFocus: string;
  tableRows: number;
  tableColumns: number;
  tableMenuBaseLeft: string;
  error: string;
} = { provider: null, view: null, context: null, commands: [], activeIndex: 0, dismissedContext: '', activationContext: '', tableOpen: false, tableFocus: 'rows', tableRows: 3, tableColumns: 3, tableMenuBaseLeft: '', error: '' };
const slashExcludedAncestors = new Set(['list_item', 'task_list_item', 'table', 'table_row', 'table_header_row', 'table_cell', 'table_header', 'code_block', 'math_block']);

/** Slash menu visual phase + the generation that guards every deferred cleanup. */
const slashMenuPhase: { state: 'closed' | 'opening' | 'open' | 'closing'; generation: number; timer: number; frame: number } = { state: 'closed', generation: 0, timer: 0, frame: 0 };

const isEditorReduceMotion = () => document.documentElement.dataset.weibeiReduceMotion === 'true';

/** Native reduce-motion sync: written before the page scripts run and pushed
 * live on preference changes — never reloads the note. */
const setReduceMotionInternal = (next: unknown) => {
  document.documentElement.dataset.weibeiReduceMotion = next === true || next === 'true' ? 'true' : 'false';
};

/** Native text-scale sync: drives --weibei-text-scale so editor body copy
 * follows the app-wide interface text tier without a reload. */
const setTextScaleInternal = (next: unknown) => {
  const value = Number(next);
  const scale = Number.isFinite(value) && value > 0 ? value : 1;
  document.documentElement.style.setProperty('--weibei-text-scale', String(scale));
};

/** Returns the `/query` immediately before the caret without consuming surrounding content. */
const slashContextForView = (view: any) => {
  if (!isEditable || view.composing) return null;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || !selection.empty) return null;
  const { $from } = selection;
  if ($from.parent.type.name !== 'paragraph') return null;
  for (let depth = $from.depth; depth > 0; depth -= 1) if (slashExcludedAncestors.has($from.node(depth).type.name)) return null;
  const beforeCaret = $from.parent.textBetween(0, $from.parentOffset, '\uFFFC', '\uFFFC');
  const slashOffset = beforeCaret.lastIndexOf('/');
  if (slashOffset < 0) return null;
  const query = beforeCaret.slice(slashOffset + 1);
  if (/[\s/]/u.test(query)) return null;
  const triggerStartOffset = /^[\u200B\uFEFF]*$/u.test(beforeCaret.slice(0, slashOffset)) ? 0 : slashOffset;
  const depth = $from.depth;
  const blockFrom = $from.before(depth);
  const triggerFrom = $from.start(depth) + triggerStartOffset;
  return { query, parent: $from.parent, triggerFrom, triggerTo: $from.pos, triggerStartOffset, triggerEndOffset: $from.parentOffset, blockFrom, blockTo: $from.after(depth), index: $from.index(depth - 1), container: $from.node(depth - 1), key: `${triggerFrom}:${query}` };
};

const emptyLineContextForView = (view: any) => {
  if (!isEditable || view.composing) return null;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || !selection.empty || selection.$from.parent.type.name !== 'paragraph' || selection.$from.parent.content.size !== 0) return null;
  for (let depth = selection.$from.depth; depth > 0; depth -= 1) if (slashExcludedAncestors.has(selection.$from.node(depth).type.name)) return null;
  return selection.$from;
};

const syncLinePlus = (view: any) => {
  const $from = emptyLineContextForView(view);
  linePlusElement.hidden = !$from;
  if (!$from) return;
  const rect = view.coordsAtPos($from.pos);
  linePlusElement.style.left = `${Math.max(6, rect.left - 30)}px`;
  linePlusElement.style.top = `${Math.max(6, rect.top - 2)}px`;
};

/** Builds the replacement nodes directly instead of reparsing generated Markdown. */
const slashReplacement = (commandID: any, schema: any, options: any = {}) => {
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
  if (commandID === 'callout') {
    const callout = schema.nodes.callout;
    const node = callout?.create({ calloutType: 'note', title: '', fold: '' }, paragraph.create());
    return node ? { content: Fragment.from(node), selectionOffset: 2 } : null;
  }
  if (commandID === 'quote') {
    const blockquote = schema.nodes.blockquote || schema.nodes.block_quote;
    if (!blockquote) return null;
    const node = blockquote.create(null, paragraph.create());
    return { content: Fragment.from(node), selectionOffset: 2 };
  }
  if (commandID === 'code' || commandID === 'mermaid') {
    const code = schema.nodes.code_block;
    if (!code) return null;
    const source = commandID === 'mermaid' ? 'graph TD\n\tA --> B' : '';
    return { content: Fragment.from(code.create({ language: commandID === 'mermaid' ? 'mermaid' : '' }, source ? schema.text(source) : null)), selectionOffset: source.length + 1 };
  }
  if (commandID === 'inlineMath') {
    const mathInline = schema.nodes.math_inline;
    const node = mathInline?.create(null, schema.text('x'));
    return node ? { content: Fragment.from(paragraph.create(null, node)), selectionOffset: 1 } : null;
  }
  if (commandID === 'link') {
    const link = schema.marks.link;
    const label = editorLabel('linkPlaceholder');
    const node = link ? paragraph.create(null, schema.text(label, [link.create({ href: '' })])) : null;
    return node ? { content: Fragment.from(node), selectionFromOffset: 1, selectionToOffset: label.length + 1 } : null;
  }
  if (commandID === 'wikiLink') {
    const wikiLink = schema.nodes.wiki_link;
    const target = editorLabel('wikiLinkPlaceholder');
    const node = wikiLink?.create({ raw: target, target, label: '' });
    return node ? { content: Fragment.from(paragraph.create(null, node)), selectionOffset: 1, activateEvent: 'weibei-edit-structured' } : null;
  }
  if (commandID === 'footnote') {
    const footnote = schema.nodes.inline_footnote;
    const node = footnote?.create({ value: editorLabel('footnotePlaceholder') });
    return node ? { content: Fragment.from(paragraph.create(null, node)), selectionOffset: 1, activateEvent: 'weibei-edit-structured' } : null;
  }
  if (commandID === 'blockMath') {
    const mathBlock = schema.nodes.math_block;
    const node = mathBlock?.create({ value: 'x' });
    return node ? { content: Fragment.from(node), selectionOffset: 0 } : null;
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

/** Preserves the paragraph around an inline command, or splits it around a block command. */
const slashContentForContext = (context: any, replacement: any) => {
  const first = replacement?.content?.firstChild;
  if (!context || !first) return null;
  if (replacement.content.childCount === 1 && first.type === context.parent.type) {
    const content = context.parent.content.cut(0, context.triggerStartOffset)
      .append(first.content)
      .append(context.parent.content.cut(context.triggerEndOffset));
    return { content: Fragment.from(context.parent.type.create(context.parent.attrs, content, context.parent.marks)), selectionBase: context.triggerFrom - 1 };
  }
  const nodes: any[] = [];
  const prefix = context.parent.content.cut(0, context.triggerStartOffset);
  const suffix = context.parent.content.cut(context.triggerEndOffset);
  if (prefix.size) nodes.push(context.parent.type.create(context.parent.attrs, prefix, context.parent.marks));
  const selectionBase = context.blockFrom + nodes.reduce((size, node) => size + node.nodeSize, 0);
  replacement.content.forEach((node: any) => nodes.push(node));
  if (suffix.size) nodes.push(context.parent.type.create(context.parent.attrs, suffix, context.parent.marks));
  return { content: Fragment.from(nodes), selectionBase };
};

/** Checks whether the current container accepts the requested replacement. */
const slashCommandIsAllowed = (command: any, context: any, schema: any) => {
  if (!context) return false;
  if (slashWritingFonts[command.id]) return Boolean(schema.marks.writing_font);
  if (command.id === 'image') return Boolean(schema.nodes.image);
  const replacement = slashReplacement(command.id, schema, { rows: 3, columns: 3 });
  const applied = slashContentForContext(context, replacement);
  return Boolean(applied && context.container.canReplace(context.index, context.index + 1, applied.content));
};

/** Filters commands by localized labels and stable aliases. */
const filteredSlashCommands = (query: any, context: any, schema: any) => {
  const normalized = String(query || '').toLocaleLowerCase();
  return slashCommands.filter((command) => slashCommandIsAllowed(command, context, schema) && (!normalized || [(editorLabels['zh-Hans'] as Record<string, string>)[command.label], (editorLabels.en as Record<string, string>)[command.label], ...command.aliases].some((value) => String(value).toLocaleLowerCase().includes(normalized))));
};

/** Applies exactly one history event for a slash block replacement. */
const applySlashReplacement = (view: any, context: any, replacement: any) => {
  if (!context || !replacement) return false;
  const node = view.state.doc.nodeAt(context.blockFrom);
  const applied = slashContentForContext(context, replacement);
  if (!node?.eq(context.parent) || !applied || !context.container.canReplace(context.index, context.index + 1, applied.content)) return false;
  const tr = closeHistory(view.state.tr.replaceWith(context.blockFrom, context.blockTo, applied.content));
  const selection = replacement.activateEvent
    ? NodeSelection.create(tr.doc, applied.selectionBase + replacement.selectionOffset)
    : Number.isInteger(replacement.selectionFromOffset) && Number.isInteger(replacement.selectionToOffset)
    ? TextSelection.create(tr.doc, applied.selectionBase + replacement.selectionFromOffset, applied.selectionBase + replacement.selectionToOffset)
    : Selection.findFrom(tr.doc.resolve(Math.min(applied.selectionBase + replacement.selectionOffset, tr.doc.content.size)), 1, true);
  if (selection) tr.setSelection(selection);
  view.dispatch(tr.scrollIntoView());
  slashRuntime.dismissedContext = '';
  slashRuntime.provider?.hide();
  view.focus();
  if (replacement.activateEvent && selection) window.requestAnimationFrame(() => {
    (view.nodeDOM(selection.from) as HTMLElement | null)?.dispatchEvent(new CustomEvent(replacement.activateEvent));
  });
  window.requestAnimationFrame(reportSelection);
  return true;
};

/** Records a native picker request without changing the slash paragraph. */
const requestSlashImage = (view: any, context: any) => {
  const id = `image-picker-${Date.now()}-${attachmentRequestID += 1}`;
  pendingImagePickers.set(id, { mode: 'insert', view, context, documentID: currentDocumentID, documentGeneration: currentDocumentGeneration });
  slashRuntime.dismissedContext = context.key;
  slashRuntime.provider?.hide();
  post('imagePickerRequested', { id });
};

const applySlashWritingFont = (view: any, context: any, font: string) => {
  const mark = view.state.schema.marks.writing_font;
  if (!mark || !writingFontValues.has(font)) return false;
  const existingMarks = view.state.storedMarks || view.state.selection.$from.marks();
  const tr = closeHistory(view.state.tr.delete(context.triggerFrom, context.triggerTo));
  tr.setSelection(TextSelection.create(tr.doc, context.triggerFrom));
  tr.setStoredMarks([...existingMarks.filter((existing: any) => existing.type !== mark), mark.create({ font })]);
  view.dispatch(tr.scrollIntoView());
  slashRuntime.dismissedContext = '';
  slashRuntime.provider?.hide();
  view.focus();
  window.requestAnimationFrame(reportSelection);
  return true;
};

/** Executes a selected command or opens the image picker. */
const executeSlashCommand = (commandID: any) => {
  const view = slashRuntime.view;
  const context = view && slashContextForView(view);
  if (!view || !context) return false;
  if (commandID === 'image') { requestSlashImage(view, context); return true; }
  if (slashWritingFonts[commandID]) return applySlashWritingFont(view, context, slashWritingFonts[commandID]);
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

/** Structure identity of the command list: only a real change in query results,
 * language, or error state may rebuild the DOM. Pointer motion and arrow keys
 * never enter this path, so button identity stays stable across hovers. */
const slashMenuStructureKey = () => `${currentLanguage}::${slashRuntime.error ? '!' : ''}::${slashRuntime.commands.length}::${slashRuntime.commands.map((command) => command.id).join(',')}`;

let builtSlashMenuStructureKey: string | null = null;

/** Builds the command list DOM. Called only when the structure key changed. */
const buildSlashMenuList = () => {
  slashMenuElement.replaceChildren();
  if (slashRuntime.error) {
    const error = document.createElement('div');
    error.className = 'weibei-slash-error';
    error.textContent = slashRuntime.error;
    slashMenuElement.appendChild(error);
  }
  if (!slashRuntime.commands.length) {
    const empty = document.createElement('div');
    empty.className = 'weibei-slash-empty';
    empty.textContent = editorLabel('slashNoResults');
    slashMenuElement.appendChild(empty);
    return;
  }
  for (const group of slashGroups) {
    const commands = slashRuntime.commands.filter((command) => command.group === group.id);
    if (!commands.length) continue;
    const section = document.createElement('section');
    section.className = 'weibei-slash-section';
    const title = document.createElement('div');
    title.className = 'weibei-slash-group';
    title.textContent = editorLabel(group.label);
    section.appendChild(title);
    for (const command of commands) {
      const index = slashRuntime.commands.indexOf(command);
      const row = document.createElement('div');
      row.id = `weibei-slash-command-${command.id}`;
      row.className = `weibei-slash-command${index === slashRuntime.activeIndex ? ' is-active' : ''}`;
      row.setAttribute('role', 'option');
      row.setAttribute('aria-selected', String(index === slashRuntime.activeIndex));
      row.setAttribute('aria-posinset', String(index + 1));
      row.setAttribute('aria-setsize', String(slashRuntime.commands.length));
      const button = document.createElement('button');
      button.type = 'button';
      button.tabIndex = -1;
      button.className = 'weibei-slash-command-button';
      button.textContent = editorLabel(command.label);
      button.addEventListener('pointerdown', (event) => event.preventDefault());
      button.addEventListener('pointermove', (event) => {
        if (!Number(event.movementX) && !Number(event.movementY)) return;
        slashRuntime.activeIndex = index;
        slashRuntime.tableOpen = command.id === 'table';
        updateSlashActiveItem();
        syncSlashTablePanel();
      });
      button.addEventListener('click', () => { if (command.id !== 'table') executeSlashCommand(command.id); });
      row.appendChild(button);
      section.appendChild(row);
    }
    slashMenuElement.appendChild(section);
  }
};

/** In-place active row update: class + ARIA attributes only — never rebuilds rows. */
const updateSlashActiveItem = () => {
  slashMenuElement.querySelectorAll('.weibei-slash-command').forEach((row, index) => {
    row.classList.toggle('is-active', index === slashRuntime.activeIndex);
    row.setAttribute('aria-selected', String(index === slashRuntime.activeIndex));
  });
  slashMenuElement.querySelector('.weibei-slash-command.is-active')?.scrollIntoView({ block: 'nearest' });
  syncSlashAccessibility();
};

type SlashTablePanelParts = {
  panel: HTMLDivElement;
  rowsInput: HTMLInputElement;
  columnsInput: HTMLInputElement;
  rowsDecrement: HTMLButtonElement;
  rowsIncrement: HTMLButtonElement;
  columnsDecrement: HTMLButtonElement;
  columnsIncrement: HTMLButtonElement;
  rowsStepper: HTMLDivElement;
  columnsStepper: HTMLDivElement;
};

let slashTablePanelParts: SlashTablePanelParts | null = null;

const dismissSlashTablePanel = () => {
  slashTablePanelElement?.remove();
  slashTablePanelElement = null;
  slashTablePanelParts = null;
  if (slashRuntime.tableMenuBaseLeft) {
    slashMenuElement.style.left = slashRuntime.tableMenuBaseLeft;
    slashRuntime.tableMenuBaseLeft = '';
  }
};

/** Keeps exactly one table submenu instance alive while open; stepper handlers
 * read live runtime values at event time, so nothing captures stale rows/columns. */
const syncSlashTablePanel = () => {
  const tableButton = slashMenuElement.querySelector<HTMLElement>('#weibei-slash-command-table .weibei-slash-command-button');
  if (!slashRuntime.tableOpen || slashMenuElement.dataset.show !== 'true' || !tableButton) {
    dismissSlashTablePanel();
    return;
  }
  let parts = slashTablePanelParts;
  if (!parts) {
    const panel = document.createElement('div');
    panel.className = 'weibei-slash-table-panel';
    panel.setAttribute('role', 'group');
    const makeStepper = (kind: 'rows' | 'columns') => {
      const isRows = kind === 'rows';
      const stepper = document.createElement('div');
      stepper.className = `weibei-slash-stepper${slashRuntime.tableFocus === kind ? ' is-focused' : ''}`;
      const label = document.createElement('span');
      label.className = 'weibei-slash-stepper-label';
      label.textContent = editorLabel(isRows ? 'slashRows' : 'slashColumns');
      stepper.appendChild(label);
      const readValue = () => isRows ? slashRuntime.tableRows : slashRuntime.tableColumns;
      const writeValue = (next: number) => { if (isRows) slashRuntime.tableRows = next; else slashRuntime.tableColumns = next; };
      const decrement = document.createElement('button');
      decrement.type = 'button';
      decrement.textContent = '\u2212';
      decrement.setAttribute('aria-label', `${label.textContent} \u2212`);
      decrement.addEventListener('pointerdown', (event) => event.preventDefault());
      decrement.addEventListener('click', () => { writeValue(Math.max(1, readValue() - 1)); slashRuntime.tableFocus = kind; syncSlashTablePanel(); });
      stepper.appendChild(decrement);
      const input = document.createElement('input');
      input.className = 'weibei-slash-stepper-input';
      input.type = 'number';
      input.inputMode = 'numeric';
      input.min = '1';
      input.max = String(isRows ? 20 : 12);
      input.step = '1';
      input.setAttribute('aria-label', label.textContent!);
      input.addEventListener('focus', () => {
        slashRuntime.tableFocus = kind;
        panel.querySelectorAll('.weibei-slash-stepper.is-focused').forEach((element) => element.classList.remove('is-focused'));
        stepper.classList.add('is-focused');
      });
      input.addEventListener('input', () => {
        const next = Number.parseInt(input.value, 10);
        if (!Number.isFinite(next)) return;
        writeValue(Math.min(isRows ? 20 : 12, Math.max(1, next)));
      });
      input.addEventListener('change', () => {
        const next = Math.min(isRows ? 20 : 12, Math.max(1, Number.parseInt(input.value, 10) || 1));
        input.value = String(next);
        writeValue(next);
      });
      input.addEventListener('keydown', (event) => {
        event.stopPropagation();
        if (event.key === 'Enter') {
          const next = Math.min(isRows ? 20 : 12, Math.max(1, Number.parseInt(input.value, 10) || 1));
          writeValue(next);
          executeSlashCommand('table');
          event.preventDefault();
        }
      });
      stepper.appendChild(input);
      const increment = document.createElement('button');
      increment.type = 'button';
      increment.textContent = '+';
      increment.setAttribute('aria-label', `${label.textContent} +`);
      increment.addEventListener('pointerdown', (event) => event.preventDefault());
      increment.addEventListener('click', () => { writeValue(Math.min(isRows ? 20 : 12, readValue() + 1)); slashRuntime.tableFocus = kind; syncSlashTablePanel(); });
      stepper.appendChild(increment);
      return { stepper, input, decrement, increment };
    };
    const rows = makeStepper('rows');
    const columns = makeStepper('columns');
    const insert = document.createElement('button');
    insert.type = 'button';
    insert.className = 'weibei-slash-table-insert';
    insert.textContent = editorLabel('slashInsertTable');
    insert.addEventListener('pointerdown', (event) => event.preventDefault());
    insert.addEventListener('click', () => executeSlashCommand('table'));
    panel.append(rows.stepper, columns.stepper, insert);
    document.body.appendChild(panel);
    parts = {
      panel,
      rowsInput: rows.input,
      rowsDecrement: rows.decrement,
      rowsIncrement: rows.increment,
      rowsStepper: rows.stepper,
      columnsInput: columns.input,
      columnsDecrement: columns.decrement,
      columnsIncrement: columns.increment,
      columnsStepper: columns.stepper,
    };
    slashTablePanelElement = panel;
    slashTablePanelParts = parts;
  }

  // Value/disabled/focus updates only — inputs are never rebuilt while open, and
  // the focused input keeps whatever the user is typing.
  if (document.activeElement !== parts.rowsInput) parts.rowsInput.value = String(slashRuntime.tableRows);
  if (document.activeElement !== parts.columnsInput) parts.columnsInput.value = String(slashRuntime.tableColumns);
  parts.rowsDecrement.disabled = slashRuntime.tableRows <= 1;
  parts.rowsIncrement.disabled = slashRuntime.tableRows >= 20;
  parts.columnsDecrement.disabled = slashRuntime.tableColumns <= 1;
  parts.columnsIncrement.disabled = slashRuntime.tableColumns >= 12;
  parts.rowsStepper.classList.toggle('is-focused', slashRuntime.tableFocus === 'rows');
  parts.columnsStepper.classList.toggle('is-focused', slashRuntime.tableFocus === 'columns');

  const inset = 8;
  const gap = 6;
  const panelWidth = parts.panel.offsetWidth;
  let menuRect = slashMenuElement.getBoundingClientRect();
  const fitsRight = menuRect.right + gap + panelWidth <= window.innerWidth - inset;
  const fitsLeft = menuRect.left - gap - panelWidth >= inset;
  if (!fitsRight && !fitsLeft && menuRect.width + gap + panelWidth <= window.innerWidth - inset * 2) {
    if (!slashRuntime.tableMenuBaseLeft) slashRuntime.tableMenuBaseLeft = slashMenuElement.style.left;
    slashMenuElement.style.left = `${inset}px`;
    menuRect = slashMenuElement.getBoundingClientRect();
  }
  const showRight = menuRect.right + gap + panelWidth <= window.innerWidth - inset;
  parts.panel.dataset.side = showRight ? 'right' : 'left';
  const preferredLeft = showRight ? menuRect.right + gap : menuRect.left - gap - panelWidth;
  parts.panel.style.left = `${Math.max(inset, Math.min(window.innerWidth - panelWidth - inset, preferredLeft))}px`;
  const tableRect = tableButton.getBoundingClientRect();
  parts.panel.style.top = `${Math.max(inset, Math.min(window.innerHeight - parts.panel.offsetHeight - inset, tableRect.top))}px`;
};

/** Renders the slash menu: computes commands, rebuilds the list only when the
 * structure truly changed, then updates selection and the table submenu in place. */
const renderSlashMenu = () => {
  const view = slashRuntime.view;
  const context = view && slashContextForView(view);
  if (!view || !context || slashRuntime.dismissedContext === context.key) { slashRuntime.provider?.hide(); syncSlashAccessibility(); return; }
  if (slashRuntime.activationContext !== `${context.blockFrom}:${currentDocumentID}`) {
    Object.assign(slashRuntime, { activationContext: `${context.blockFrom}:${currentDocumentID}`, activeIndex: 0, tableOpen: false, tableFocus: 'rows', tableRows: 3, tableColumns: 3, tableMenuBaseLeft: '', error: '' });
  }
  slashRuntime.context = context;
  slashRuntime.commands = filteredSlashCommands(context.query, context, view.state.schema);
  slashRuntime.activeIndex = Math.min(slashRuntime.activeIndex, Math.max(0, slashRuntime.commands.length - 1));
  const structureKey = slashMenuStructureKey();
  if (structureKey !== builtSlashMenuStructureKey) {
    builtSlashMenuStructureKey = structureKey;
    buildSlashMenuList();
  }
  updateSlashActiveItem();
  syncSlashTablePanel();
};


/** Handles command navigation before the editor's ordinary key handlers. */
const handleSlashMenuKeyDown = (view: any, event: any) => {
  const context = slashContextForView(view);
  if (slashMenuElement.dataset.show !== 'true' || !context || event.isComposing || event.keyCode === 229) return false;
  if (event.key === 'Escape') { slashRuntime.dismissedContext = context.key; slashRuntime.provider?.hide(); event.preventDefault(); return true; }
  if (slashRuntime.tableOpen) {
    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight') { const delta = event.key === 'ArrowLeft' ? -1 : 1; if (slashRuntime.tableFocus === 'rows') slashRuntime.tableRows = Math.min(20, Math.max(1, slashRuntime.tableRows + delta)); else slashRuntime.tableColumns = Math.min(12, Math.max(1, slashRuntime.tableColumns + delta)); syncSlashTablePanel(); event.preventDefault(); return true; }
    if (['Tab', 'ArrowUp', 'ArrowDown'].includes(event.key)) { slashRuntime.tableFocus = slashRuntime.tableFocus === 'rows' ? 'columns' : 'rows'; syncSlashTablePanel(); event.preventDefault(); return true; }
    if (event.key === 'Enter') { executeSlashCommand('table'); event.preventDefault(); return true; }
  }
  if (event.key === 'ArrowUp' || event.key === 'ArrowDown') { if (!slashRuntime.commands.length) return true; slashRuntime.activeIndex = (slashRuntime.activeIndex + (event.key === 'ArrowUp' ? -1 : 1) + slashRuntime.commands.length) % slashRuntime.commands.length; slashRuntime.tableOpen = false; updateSlashActiveItem(); syncSlashTablePanel(); event.preventDefault(); return true; }
  const active = slashRuntime.commands[slashRuntime.activeIndex];
  if (event.key === 'ArrowRight' && active?.id === 'table') { slashRuntime.tableOpen = true; syncSlashTablePanel(); event.preventDefault(); return true; }
  if (event.key === 'Enter' && active) { if (active.id === 'table') { slashRuntime.tableOpen = true; syncSlashTablePanel(); } else executeSlashCommand(active.id); event.preventDefault(); return true; }
  if (event.key === 'Tab' && active?.id !== 'table') { executeSlashCommand(active.id); event.preventDefault(); return true; }
  return false;
};

document.documentElement.dataset.weibeiCompactPreview = isCompactPreview ? 'true' : 'false';
// Deterministic checks: visual transitions are state, not assertions — disable them.
if (window.weiBeiEditorCheckMode) document.documentElement.dataset.weibeiCheckMode = 'true';

let contentHeightFrame = 0;
let contentHeightTimer = 0;
let lastReportedContentHeight = 0;
let lastReportedContentWidth = 0;

const compactPreviewMeasureNodes = () => ([
  document.querySelector('#editor'),
  document.querySelector('.milkdown'),
  document.querySelector('.ProseMirror'),
].filter(Boolean)) as any[];

const measuredNodeHeight = (node: any) => {
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
  if (!isCompactPreview || !editorReadyPosted) return;
  publishContentHeight();
  window.cancelAnimationFrame(contentHeightFrame);
  contentHeightFrame = window.requestAnimationFrame(publishContentHeight);
};

const scheduleContentHeightReports = () => {
  if (!isCompactPreview) return;
  if (contentHeightTimer) return;
  // A timer still fires for an off-screen WKWebView; the following frame catches
  // painted font/image drift without every caller running its own retry ladder.
  // Streaming relaxes the cadence: each report re-lays-out the whole chat list.
  const interval = streamingMarkdownBuffer !== null ? 100 : 40;
  contentHeightTimer = window.setTimeout(() => {
    contentHeightTimer = 0;
    reportContentHeight();
  }, interval);
};

const installContentHeightObserver = () => {
  if (!isCompactPreview) return;
  if (window.ResizeObserver) {
    const observer = new ResizeObserver(scheduleContentHeightReports);
    compactPreviewMeasureNodes().forEach((node) => observer.observe(node));
  }
  scheduleContentHeightReports();
  document.fonts?.ready?.then(scheduleContentHeightReports).catch(() => {});
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

const withFrontmatter = (markdown: any) => joinFrontmatter(frontmatterBlock, markdown);

const frontmatterRows = (frontmatter: any) => String(frontmatter || '')
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
  const panel = document.querySelector<HTMLElement>('#frontmatter-panel');
  if (!panel) return;
  const rows = frontmatterRows(frontmatterBlock) as { key: string; value: string }[];
  panel.dataset.visible = rows.length > 0 ? 'true' : 'false';
  panel.innerHTML = rows.length > 0
    ? `<div class="frontmatter-title">${frontmatterLabel()}</div>${rows.map((row) => (
      `<div class="frontmatter-row"><span class="frontmatter-key">${escapeHTML(row.key)}</span><span>${escapeHTML(row.value)}</span></div>`
    )).join('')}`
    : '';
};

const escapeHTML = (value: any) => String(value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

const localImageURL = (src: any) => `${localImageScheme}://image?src=${encodeURIComponent(src)}`;
const imageTargetPattern = /\.(?:png|jpe?g|gif|webp|svg|avif|bmp|tiff?)(?:$|[?#])/i;

const parseImageSize = (value: any) => {
  const raw = (value || '').trim();
  const match = raw.match(/^(\d{1,4})(?:x(\d{1,4}))?$/i);
  if (!match) return null;
  return {
    width: Math.max(1, Number(match[1])),
    height: match[2] ? Math.max(1, Number(match[2])) : null,
  };
};

const applyImageSize = (element: any, size: any) => {
  element.style.width = size ? `${size.width}px` : '';
  element.style.maxWidth = size ? '100%' : '';
  element.style.height = size?.height ? `${size.height}px` : '';
};

const parseMarkdownImageAlt = (alt: any) => {
  const parts = String(alt || '').split('|');
  const size = parts.length > 1 ? parseImageSize(parts.at(-1)) : null;
  return {
    alt: size ? parts.slice(0, -1).join('|').trim() : String(alt || ''),
    size,
  };
};

const rawTrimRange = (source: any, start: any, end: any) => {
  let from = start;
  let to = end;
  while (from < to && /\s/.test(source[from])) from += 1;
  while (to > from && /\s/.test(source[to - 1])) to -= 1;
  return { start: from, end: to };
};

const splitObsidianFields = (raw: any) => {
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

const parseObsidianTarget = (raw: any) => {
  const source = String(raw || '').trim();
  const fields = splitObsidianFields(source);
  const targetField = fields.shift() || { value: '', start: 0, end: 0 };
  const target = targetField.value.trim();
  const aliasFields = fields;
  const alias = aliasFields.map((field) => field.value).join('|').trim();
  const aliasRange = aliasFields.length > 0
    ? rawTrimRange(source, aliasFields[0].start, aliasFields.at(-1)!.end)
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

const parseObsidianEmbed = (raw: any) => {
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

const resolveMarkdownURL = (src: any) => {
  if (!src || /^(?:data:|blob:|weibeiimage:)/i.test(src)) return src;
  if (/^https:/i.test(src)) return localImageURL(src);
  if (/^http:/i.test(src)) return '';
  try {
    const resolved = new URL(src, markdownBaseURL || window.location.href).href;
    if (/^(?:file:|https:)/i.test(resolved)) return localImageURL(resolved);
    return /^(?:data:|blob:|weibeiimage:)/i.test(resolved) ? resolved : '';
  } catch {
    return '';
  }
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

const imageNodeRefreshers = new Set<() => void>();
const structuredNodeRenderers = new Set<() => void>();

const createReadOnlyImageNodeView = (initialNode: any) => {
  let node = initialNode;
  const image = document.createElement('img');
  image.className = 'weibei-image';
  const refresh = () => {
    const parsed = parseMarkdownImageAlt(node.attrs.alt || '');
    const resolved = resolveMarkdownURL(String(node.attrs.src || ''));
    image.alt = parsed.alt;
    image.title = String(node.attrs.title || '');
    applyImageSize(image, parsed.size);
    image.src = resolved || missingImageURL();
  };
  image.addEventListener('load', scheduleContentHeightReports);
  image.addEventListener('error', () => { image.src = missingImageURL(); });
  imageNodeRefreshers.add(refresh);
  refresh();
  return {
    dom: image,
    update(nextNode: any) { if (nextNode.type !== node.type) return false; node = nextNode; refresh(); return true; },
    destroy() { imageNodeRefreshers.delete(refresh); },
  };
};

/** Lets each image own its URL, size and failure state instead of matching two full-tree scans by index. */
const createImageNodeView = (initialNode: any, view: any, getPos: any) => {
  let node = initialNode;
  const dom = document.createElement('span');
  const image = document.createElement('img');
  const controls = document.createElement('span');
  const replaceButton = document.createElement('button');
  const deleteButton = document.createElement('button');
  const size = document.createElement('select');
  dom.className = 'weibei-image-node';
  dom.contentEditable = 'false';
  image.className = 'weibei-image';
  controls.className = 'weibei-image-controls';
  replaceButton.type = deleteButton.type = 'button';
  replaceButton.textContent = '更换';
  deleteButton.textContent = '删除';
  replaceButton.setAttribute('aria-label', '更换图片');
  deleteButton.setAttribute('aria-label', '删除图片');
  for (const [value, label] of [['', '原尺寸'], ['320', '小'], ['560', '中'], ['900', '大']]) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    size.append(option);
  }
  size.setAttribute('aria-label', '图片尺寸');
  controls.append(replaceButton, deleteButton, size);
  dom.append(image, controls);
  controls.dataset.state = 'closed';
  controls.setAttribute('aria-hidden', 'true');

  const onError = () => {
    image.dataset.weibeiImageMissingFor = image.dataset.weibeiResolvedSrc || image.getAttribute('src') || '';
    image.dataset.weibeiImagePlaceholder = 'true';
    image.classList.add('weibei-image-missing');
    image.title = editorLabel('imageMissing');
    scheduleContentHeightReports();
  };
  const onLoad = () => {
    if (image.dataset.weibeiImagePlaceholder === 'true') return;
    image.classList.remove('weibei-image-missing');
    scheduleContentHeightReports();
  };
  const refresh = () => {
    addEditorMetric(checkMetrics, 'imageNodeUpdates');
    const source = String(node.attrs.src || '');
    const resolved = resolveMarkdownURL(source);
    const parsed = parseMarkdownImageAlt(node.attrs.alt || '');
    image.alt = parsed.alt;
    image.title = String(node.attrs.title || '');
    image.dataset.weibeiMarkdownSrc = source;
    size.value = parsed.size && ['320', '560', '900'].includes(String(parsed.size.width)) ? String(parsed.size.width) : '';
    applyImageSize(image, parsed.size);
    if (image.dataset.weibeiImagePlaceholder === 'true' && image.dataset.weibeiImageMissingFor === resolved) {
      return;
    }
    if (!resolved) {
      image.dataset.weibeiImageMissingFor = resolved;
      image.dataset.weibeiImagePlaceholder = 'true';
      image.classList.add('weibei-image-missing');
      image.setAttribute('src', missingImageURL());
      return;
    }
    image.dataset.weibeiResolvedSrc = resolved;
    delete image.dataset.weibeiImagePlaceholder;
    image.classList.remove('weibei-image-missing');
    image.setAttribute('src', resolved);
  };
  const requestReplacement = () => {
    const id = `image-picker-${Date.now()}-${attachmentRequestID += 1}`;
    pendingImagePickers.set(id, { mode: 'replace', view, getPos, documentID: currentDocumentID, documentGeneration: currentDocumentGeneration });
    post('imagePickerRequested', { id });
  };
  const deleteImage = () => {
    const pos = getPos();
    const current = typeof pos === 'number' ? view.state.doc.nodeAt(pos) : null;
    if (current?.type === node.type) view.dispatch(view.state.tr.delete(pos, pos + current.nodeSize).scrollIntoView());
  };
  const resizeImage = () => {
    const pos = getPos();
    const current = typeof pos === 'number' ? view.state.doc.nodeAt(pos) : null;
    if (current?.type !== node.type) return;
    const parsed = parseMarkdownImageAlt(current.attrs.alt || '');
    const alt = `${parsed.alt}${size.value ? `|${size.value}` : ''}`;
    view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, { ...current.attrs, alt }).scrollIntoView());
    view.focus();
  };
  image.addEventListener('error', onError);
  image.addEventListener('load', onLoad);
  replaceButton.addEventListener('click', requestReplacement);
  deleteButton.addEventListener('click', deleteImage);
  size.addEventListener('change', resizeImage);
  imageNodeRefreshers.add(refresh);
  refresh();

  return {
    dom,
    update(nextNode: any) {
      if (nextNode.type !== node.type) return false;
      const changed = nextNode.attrs.src !== node.attrs.src
        || nextNode.attrs.alt !== node.attrs.alt
        || nextNode.attrs.title !== node.attrs.title;
      node = nextNode;
      if (changed) refresh();
      return true;
    },
    selectNode() { dom.classList.add('ProseMirror-selectednode'); image.classList.add('ProseMirror-selectednode'); controls.dataset.state = 'open'; controls.setAttribute('aria-hidden', 'false'); },
    deselectNode() { dom.classList.remove('ProseMirror-selectednode'); image.classList.remove('ProseMirror-selectednode'); controls.dataset.state = 'closed'; controls.setAttribute('aria-hidden', 'true'); },
    stopEvent(event: Event) { return controls.contains(event.target as Node); },
    ignoreMutation(mutation: any) { return controls.contains(mutation.target); },
    destroy() {
      imageNodeRefreshers.delete(refresh);
      image.removeEventListener('error', onError);
      image.removeEventListener('load', onLoad);
      replaceButton.removeEventListener('click', requestReplacement);
      deleteButton.removeEventListener('click', deleteImage);
      size.removeEventListener('change', resizeImage);
    },
  };
};

const refreshRenderedImages = () => imageNodeRefreshers.forEach((refresh) => refresh());

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

const addRangeDecoration = (decorations: any, from: any, to: any, className: any, attrs: any = {}) => {
  if (to <= from) return;
  decorations.push(Decoration.inline(from, to, { ...attrs, class: className }));
};

const normalizeSelectionAskMarks = (marks: any) => (Array.isArray(marks) ? marks : [])
  .map((mark) => ({
    id: String(mark?.id || ''),
    text: String(mark?.text || '').trim(),
  }))
  .filter((mark) => mark.id && mark.text.length >= 4);

// 记过原文标记:句末朱砂短棒(样式由原生 bootstrap 注入),点击回访续记。
const normalizeSelectionRemarkMarks = (marks: any) => (Array.isArray(marks) ? marks : [])
  .map((mark) => ({
    id: String(mark?.id || ''),
    text: String(mark?.text || '').trim(),
  }))
  .filter((mark) => mark.id && mark.text.length >= 2);

const decorateSelectionRemarkMarks = (decorations: any, text: any, pos: any, counts: any) => {
  if (isEditable || selectionRemarkMarks.length === 0) return;
  selectionRemarkMarks.forEach((mark) => {
    let start = 0;
    let count = counts.get(mark.id) || 0;
    while (count < 3) {
      const index = text.indexOf(mark.text, start);
      if (index < 0) break;
      addRangeDecoration(
        decorations,
        pos + index,
        pos + index + mark.text.length,
        'weibei-remark-mark',
        {
          'data-record-id': mark.id,
          title: '回访这句的札记',
        },
      );
      count += 1;
      start = index + mark.text.length;
    }
    counts.set(mark.id, count);
  });
};

const decorateSelectionAskMarks = (decorations: any, text: any, pos: any, counts: any) => {
  if (isEditable || selectionAskMarks.length === 0) return;
  selectionAskMarks.forEach((mark) => {
    let start = 0;
    let count = counts.get(mark.id) || 0;
    while (count < 3) {
      const index = text.indexOf(mark.text, start);
      if (index < 0) break;
      addRangeDecoration(
        decorations,
        pos + index,
        pos + index + mark.text.length,
        'weibei-selection-ask-mark',
        {
          'data-thread-id': mark.id,
          title: '打开当时的选区问答',
        },
      );
      count += 1;
      start = index + mark.text.length;
    }
    counts.set(mark.id, count);
  });
};

const isInsideNode = (state: any, pos: any, typeName: any) => {
  const resolved = state.doc.resolve(pos);
  for (let depth = resolved.depth; depth >= 0; depth -= 1) {
    if (resolved.node(depth).type.name === typeName) return true;
  }
  return false;
};

const decorateSourceReferences = (decorations: any, text: any, pos: any) => {
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

const decorateComments = (decorations: any, text: any, pos: any, commentState: any) => {
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

const decorateTagsAndBlocks = (decorations: any, text: any, pos: any) => {
  for (const match of text.matchAll(/(^|\s)(#[\p{L}\p{N}_/-]+)\b/gu)) {
    const from = pos + (match.index || 0) + match[1].length;
    addRangeDecoration(decorations, from, from + match[2].length, 'weibei-tag');
  }
  for (const match of text.matchAll(/(^|\s)(\^[A-Za-z0-9-]+)\s*$/g)) {
    const from = pos + (match.index || 0) + match[1].length;
    addRangeDecoration(decorations, from, from + match[2].length, 'weibei-block-id');
  }
};

const decorateHtmlBreaks = (decorations: any, text: any, pos: any) => {
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

const mermaidWidget = (initialSource: any) => {
  const container = document.createElement('div');
  container.className = 'weibei-mermaid-render';
  container.textContent = editorLabel('mermaidRendering');
  let desiredSource = '\0';
  let renderTimer = 0;
  let requestGeneration = 0;

  const updateSource = (source: any, debounce = false) => {
    const nextSource = String(source || '');
    if (nextSource === desiredSource) return;
    desiredSource = nextSource;
    const request = requestGeneration += 1;
    window.clearTimeout(renderTimer);
    renderTimer = window.setTimeout(async () => {
      if (!container.isConnected || request !== requestGeneration) return;
      container.classList.remove('weibei-mermaid-error');
      try {
        const mermaid = await loadMermaid();
        initializeMermaid(mermaid);
        const id = `weibei-mermaid-${mermaidRenderID += 1}`;
        addEditorMetric(checkMetrics, 'mermaidRenders');
        const { svg, bindFunctions } = await mermaid.render(id, nextSource, container);
        if (!container.isConnected || request !== requestGeneration) return;
        container.innerHTML = svg;
        bindFunctions?.(container);
        container.dataset.rendered = 'true';
      } catch (error) {
        if (!container.isConnected || request !== requestGeneration) return;
        container.classList.add('weibei-mermaid-error');
        container.textContent = editorLabel('mermaidFailed', { value: String((error as any)?.message || error) });
      }
      scheduleContentHeightReports();
    }, debounce ? 300 : 0);
  };
  updateSource(initialSource);
  return { element: container, updateSource };
};

let mermaidPreviewCache = new WeakMap();
let activeMermaidPreview: any = null;
let mermaidSourceHasFocus = false;

/** Returns the Mermaid code block containing the focused text selection. */
const focusedMermaidBlock = (state: any) => {
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
const synchronizeActiveMermaidPreview = (focusedBlock: any) => {
  if (!activeMermaidPreview) return;
  if (activeMermaidPreview.documentGeneration !== currentDocumentGeneration || activeMermaidPreview.contentGeneration !== currentContentGeneration || activeMermaidPreview.generation !== mermaidPreviewGeneration || focusedBlock?.pos !== activeMermaidPreview.pos) activeMermaidPreview = null;
};

/** Creates or reuses the SVG preview committed for a Mermaid block. */
const mermaidPreviewForBlock = (node: any, pos: any, focusedBlock: any) => {
  const isFocused = focusedBlock?.pos === pos;
  if (isFocused && !activeMermaidPreview) {
    const cached = mermaidPreviewCache.get(node);
    activeMermaidPreview = cached?.generation === mermaidPreviewGeneration
      ? { ...cached, pos, documentGeneration: currentDocumentGeneration, contentGeneration: currentContentGeneration }
      : { ...mermaidWidget(node.textContent), generation: mermaidPreviewGeneration, key: `mermaid-preview-${mermaidPreviewID += 1}`, pos, documentGeneration: currentDocumentGeneration, contentGeneration: currentContentGeneration };
  }
  if (isFocused) {
    activeMermaidPreview.updateSource(node.textContent, true);
    return activeMermaidPreview;
  }
  const cached = mermaidPreviewCache.get(node);
  if (cached?.generation === mermaidPreviewGeneration) {
    cached.updateSource(node.textContent);
    return cached;
  }
  const preview = { ...mermaidWidget(node.textContent), generation: mermaidPreviewGeneration, key: `mermaid-preview-${mermaidPreviewID += 1}` };
  mermaidPreviewCache.set(node, preview);
  return preview;
};

const decorateMermaidBlock = (decorations: any, node: any, pos: any, focusedBlock: any) => {
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

const wikiNavigationTitle = (raw: any) => {
  const parsed = parseObsidianTarget(raw);
  return parsed.target || parsed.noteTitle;
};

const wikiTitleFromTarget = (target: any) => {
  const link = target instanceof Element
    ? target.closest('.weibei-wikilink, .weibei-embed-note[data-wikilink-title]')
    : null;
  return link?.getAttribute('data-wikilink-title') || link?.textContent?.trim() || '';
};

const activateWikiLink = (target: any) => {
  const title = wikiTitleFromTarget(target);
  if (!title) return false;
  post('wikiLinkActivated', { title });
  return true;
};

const sourceReferenceFromTarget = (target: any) => {
  const link = target instanceof Element
    ? target.closest('.weibei-source-reference[data-source-reference]')
    : null;
  return link?.getAttribute('data-source-reference') || '';
};

const activateSourceReference = (target: any) => {
  const reference = sourceReferenceFromTarget(target);
  if (!reference) return false;
  post('sourceReferenceActivated', { reference });
  return true;
};

const activateSelectionAskMark = (target: any) => {
  const mark = target instanceof Element
    ? target.closest('.weibei-selection-ask-mark[data-thread-id]')
    : null;
  const threadId = mark?.getAttribute('data-thread-id') || '';
  if (!threadId) return false;
  post('selectionAskMark', { threadId, text: mark!.textContent || '' });
  return true;
};

const activateSelectionRemarkMark = (target: any) => {
  const mark = target instanceof Element
    ? target.closest('.weibei-remark-mark[data-record-id]')
    : null;
  const recordId = mark?.getAttribute('data-record-id') || '';
  if (!recordId) return false;
  post('remarkMark', { recordId, text: mark!.textContent || '' });
  return true;
};

const toggleFoldedCallout = (target: any) => {
  if (isEditable || !(target instanceof Element)) return false;
  const callout = target.closest('blockquote.weibei-callout[data-callout-fold="-"]');
  if (!callout) return false;
  callout.classList.toggle('weibei-callout-open');
  return true;
};

const normalizeLanguage = (language: any) => {
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
  return (aliases as Record<string, string>)[key] || key;
};

const tokenLength = (token: any) => {
  if (typeof token === 'string') return token.length;
  if (Array.isArray(token.content)) return token.content.reduce((sum: any, child: any) => sum + tokenLength(child), 0);
  return String(token.content || '').length;
};

const tokenClass = (token: any) => {
  const aliases = Array.isArray(token.alias) ? token.alias : token.alias ? [token.alias] : [];
  return ['weibei-prism-token', 'token', token.type, ...aliases].filter(Boolean).join(' ');
};

const codeTokenCache = new WeakMap<any, { from: number; to: number; className: string }[]>();
const prismLanguages = new Set(['bash', 'css', 'do', 'java', 'javascript', 'json', 'jsx', 'markdown', 'python', 'r', 'ruby', 'rust', 'sql', 'stata', 'swift', 'tsx', 'typescript', 'yaml']);
let prismRuntime: any = null;
let prismLoading = false;

const requestPrism = () => {
  if (prismRuntime || prismLoading) return;
  prismLoading = true;
  loadPrism().then((runtime) => {
    prismRuntime = runtime;
    decorationGeneration += 1;
    editor?.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      view.dispatch(view.state.tr.setMeta('weibeiPrismReady', true));
    });
  }).catch(showFailure);
};

const collectTokenDecorations = (decorations: { from: number; to: number; className: string }[], tokens: any, start: any) => {
  let cursor = start;
  for (const token of tokens) {
    const length = tokenLength(token);
    if (typeof token !== 'string' && length > 0) {
      decorations.push({ from: cursor, to: cursor + length, className: tokenClass(token) });
      if (Array.isArray(token.content)) {
        collectTokenDecorations(decorations, token.content, cursor);
      }
    }
    cursor += length;
  }
};

const decorateCodeBlock = (decorations: any, node: any, pos: any) => {
  const language = normalizeLanguage(node.attrs.language || '');
  if (!prismLanguages.has(language)) return;
  if (!prismRuntime) { requestPrism(); return; }
  let cached = codeTokenCache.get(node);
  try {
    if (!cached) {
      addEditorMetric(checkMetrics, 'codeTokenizations');
      cached = [];
      collectTokenDecorations(cached, prismRuntime.tokenize(node.textContent, prismRuntime.languages[language]), 0);
      codeTokenCache.set(node, cached);
    }
    cached.forEach((token) => addRangeDecoration(decorations, pos + 1 + token.from, pos + 1 + token.to, token.className));
  } catch {
    // Prism should not be allowed to break editing.
  }
};

const createReadOnlyMathNodeView = (initialNode: any) => {
  let node = initialNode;
  const isBlock = node.type.name === 'math_block';
  const dom = document.createElement(isBlock ? 'div' : 'span');
  dom.className = `weibei-math-node ${isBlock ? 'weibei-math-block' : 'weibei-math-inline'}`;
  dom.dataset.type = node.type.name;
  let renderRequest = 0;
  const source = () => isBlock ? String(node.attrs.value || '') : node.textContent;
  const render = async () => {
    const request = renderRequest += 1;
    const value = source();
    dom.dataset.value = value;
    dom.textContent = value || '公式';
    const apply = (katex: any, requireConnected = false) => {
      if (request !== renderRequest || (requireConnected && !dom.isConnected)) return;
      addEditorMetric(checkMetrics, 'katexRenders');
      katex.render(value, dom, { throwOnError: true, strict: false, trust: false, displayMode: isBlock });
    };
    try {
      const katex = loadedKaTeX();
      if (katex) apply(katex);
      else apply(await loadKaTeX(), true);
    } catch { if (request === renderRequest) dom.textContent = value || '公式'; }
    scheduleContentHeightReports();
  };
  render();
  return {
    dom,
    update(nextNode: any) { if (nextNode.type !== node.type) return false; node = nextNode; render(); return true; },
    ignoreMutation() { return true; },
  };
};

/** Renders and edits one math node without scanning the document. */
const createMathNodeView = (initialNode: any, view: any, getPos: any) => {
  let node = initialNode;
  const isBlock = node.type.name === 'math_block';
  const dom = document.createElement(isBlock ? 'div' : 'span');
  dom.className = `weibei-math-node ${isBlock ? 'weibei-math-block' : 'weibei-math-inline'}`;
  dom.dataset.type = node.type.name;
  dom.contentEditable = 'false';
  dom.tabIndex = 0;
  const preview = document.createElement(isBlock ? 'div' : 'span');
  preview.className = 'weibei-math-preview';
  const input = document.createElement(isBlock ? 'textarea' : 'input') as HTMLInputElement | HTMLTextAreaElement;
  input.className = 'weibei-math-source';
  input.setAttribute('aria-label', isBlock ? editorLabel('slashBlockMath') : editorLabel('slashInlineMath'));
  input.setAttribute('autocapitalize', 'none');
  input.setAttribute('autocomplete', 'off');
  input.setAttribute('spellcheck', 'false');
  if (input instanceof HTMLInputElement) input.type = 'text';
  dom.append(preview, input);
  let editing = false;
  let renderRequest = 0;

  const source = () => isBlock ? String(node.attrs.value || '') : node.textContent;
  const render = async (value = source()) => {
    const request = renderRequest += 1;
    dom.dataset.value = value;
    preview.replaceChildren();
    preview.textContent = value || '公式';
    const apply = (katex: any, requireConnected = false) => {
      if (request !== renderRequest || (requireConnected && !dom.isConnected)) return;
      preview.replaceChildren();
      addEditorMetric(checkMetrics, 'katexRenders');
      katex.render(value, preview, { throwOnError: true, strict: false, trust: false, displayMode: isBlock });
      dom.classList.remove('weibei-math-invalid');
      dom.removeAttribute('title');
    };
    try {
      const katex = loadedKaTeX();
      if (katex) apply(katex);
      else apply(await loadKaTeX(), true);
    } catch {
      if (request !== renderRequest) return;
      preview.textContent = value || '公式';
      dom.classList.add('weibei-math-invalid');
      dom.title = currentLanguage === 'en' ? 'Not displayable yet; keep editing.' : '暂时无法显示，继续编辑即可';
    }
  };

  const setEditing = (next: boolean) => {
    if (!isEditable && next) return;
    editing = next;
    dom.classList.toggle('weibei-math-editing', next);
    if (next) {
      input.value = source();
      input.focus();
      input.select();
    }
  };

  const commit = () => {
    const value = input.value;
    setEditing(false);
    const pos = getPos();
    if (typeof pos !== 'number') return;
    if (value === source()) {
      view.dispatch(view.state.tr.setSelection(NodeSelection.create(view.state.doc, pos)));
      render();
      view.focus();
      return;
    }
    const nextNode = isBlock
      ? node.type.create({ ...node.attrs, value })
      : node.type.create(node.attrs, value ? view.state.schema.text(value) : null, node.marks);
    const tr = view.state.tr.replaceWith(pos, pos + node.nodeSize, nextNode);
    tr.setSelection(NodeSelection.create(tr.doc, pos));
    view.dispatch(tr.scrollIntoView());
    view.focus();
  };

  dom.addEventListener('click', (event) => { if (!editing && event.target !== input) setEditing(true); });
  dom.addEventListener('weibei-edit-math', () => setEditing(true));
  dom.addEventListener('keydown', (event) => {
    const keyEvent = event as KeyboardEvent;
    if (!editing && keyEvent.key === 'Enter') {
      event.preventDefault();
      setEditing(true);
      return;
    }
    if (!editing) return;
    if (keyEvent.key === 'Escape' || (keyEvent.key === 'Enter' && (!isBlock || keyEvent.metaKey))) {
      event.preventDefault();
      commit();
    }
  });
  input.addEventListener('input', () => render(input.value));
  input.addEventListener('blur', commit);
  render();

  return {
    dom,
    update(nextNode: any) {
      if (nextNode.type !== node.type) return false;
      const changed = (isBlock ? nextNode.attrs.value : nextNode.textContent) !== source();
      node = nextNode;
      if (changed && !editing) render();
      return true;
    },
    selectNode() { dom.classList.add('ProseMirror-selectednode'); },
    deselectNode() { dom.classList.remove('ProseMirror-selectednode'); },
    stopEvent(event: Event) { return event.target === input || input.contains(event.target as Node); },
    ignoreMutation() { return true; },
  };
};

/**
 * Creates a code block NodeView whose `<code>` child is ProseMirror's only contentDOM.
 *
 * The language control stays in the `<pre>` shell, preventing it from becoming a
 * text decoration inside the editable code content.
 */
const createCodeBlockNodeView = (node: any, view: any, getPos: any) => {
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
  const onKeyDown = (event: any) => {
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
    update(nextNode: any) {
      if (nextNode.type.name !== 'code_block') return false;
      // A document replacement must not reuse a control that captured an older generation.
      if (documentID !== currentDocumentID || documentGeneration !== currentDocumentGeneration || contentGeneration !== currentContentGeneration) return false;
      language = String(nextNode.attrs.language || '');
      syncControl();
      return true;
    },
    stopEvent(event: any) { return event.target === input || (event.target instanceof Node && input.contains(event.target)); },
    ignoreMutation(mutation: any) { return mutation.target === input || input.contains(mutation.target); },
    destroy() {
      input.removeEventListener('change', commit);
      input.removeEventListener('blur', commit);
      input.removeEventListener('keydown', onKeyDown);
    },
  };
};

const createStructuredInlineNodeView = (initialNode: any, view: any, getPos: any) => {
  let node = initialNode;
  let editing = false;
  const dom = document.createElement('span');
  dom.contentEditable = 'false';
  const render = () => {
    editing = false;
    const type = node.type.name;
    dom.className = `weibei-structured-node ${type === 'wiki_link' ? 'weibei-wikilink' : type === 'embed' ? 'weibei-embed-preview weibei-embed-note' : 'weibei-inline-footnote'}`;
    dom.dataset.type = type;
    dom.dataset.wikilinkTarget = type === 'inline_footnote' ? '' : node.attrs.target;
    dom.dataset.wikilinkTitle = type === 'inline_footnote' ? '' : node.attrs.target;
    dom.setAttribute('role', type === 'inline_footnote' ? 'note' : 'link');
    dom.tabIndex = 0;
    dom.replaceChildren();
    if (type === 'embed' && imageTargetPattern.test(node.attrs.target)) {
      const image = document.createElement('img');
      image.className = 'weibei-embed-image';
      image.alt = node.attrs.label || node.attrs.target;
      image.src = resolveMarkdownURL(node.attrs.target);
      image.addEventListener('error', () => { image.src = missingImageURL(); image.classList.add('weibei-image-missing'); }, { once: true });
      dom.append(image);
    } else {
      dom.textContent = type === 'inline_footnote' ? node.attrs.value : (node.attrs.label || node.attrs.target);
    }
    dom.title = type === 'inline_footnote'
      ? editorLabel('inlineFootnote', { value: node.attrs.value })
      : editorLabel(type === 'embed' ? 'embed' : 'openOrCreateNote', { value: node.attrs.target });
  };
  const edit = () => {
    if (!isEditable || editing) return;
    editing = true;
    const footnote = node.type.name === 'inline_footnote';
    const target = document.createElement('input');
    const label = document.createElement('input');
    target.className = label.className = 'weibei-structured-input';
    target.value = footnote ? node.attrs.value : node.attrs.target;
    label.value = footnote ? '' : node.attrs.label;
    target.setAttribute('aria-label', footnote ? '脚注' : '目标');
    label.setAttribute('aria-label', '标题');
    label.placeholder = '标题';
    const finish = (save: boolean) => {
      if (!editing) return;
      editing = false;
      if (save) {
        const pos = getPos();
        const current = typeof pos === 'number' ? view.state.doc.nodeAt(pos) : null;
        if (current?.type === node.type) {
          const attrs = footnote
            ? { value: target.value }
            : { target: target.value.trim(), label: label.value.trim(), raw: `${target.value.trim()}${label.value.trim() ? `|${label.value.trim()}` : ''}` };
          view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, attrs));
        }
      } else render();
    };
    const keydown = (event: KeyboardEvent) => {
      if (event.key === 'Enter') { event.preventDefault(); finish(true); }
      if (event.key === 'Escape') { event.preventDefault(); finish(false); }
    };
    target.addEventListener('keydown', keydown);
    label.addEventListener('keydown', keydown);
    dom.replaceChildren(target);
    if (!footnote) dom.append(label);
    dom.addEventListener('focusout', () => window.setTimeout(() => { if (!dom.contains(document.activeElement)) finish(true); }), { once: true });
    target.focus();
    target.select();
  };
  dom.addEventListener('click', (event) => { if (isEditable) { event.preventDefault(); event.stopPropagation(); edit(); } });
  dom.addEventListener('weibei-edit-structured', edit);
  structuredNodeRenderers.add(render);
  render();
  return {
    dom,
    update(next: any) { if (next.type !== node.type) return false; node = next; if (!editing) render(); return true; },
    selectNode() { dom.classList.add('ProseMirror-selectednode'); },
    deselectNode() { dom.classList.remove('ProseMirror-selectednode'); },
    stopEvent(event: Event) { return event.target instanceof HTMLInputElement; },
    ignoreMutation() { return true; },
    destroy() { structuredNodeRenderers.delete(render); },
  };
};

const createCalloutNodeView = (initialNode: any, view: any, getPos: any) => {
  let node = initialNode;
  const dom = document.createElement('blockquote');
  const header = document.createElement('div');
  const type = document.createElement('select');
  const title = document.createElement('input');
  const content = document.createElement('div');
  // Collapse wrapper: the only layer allowed to animate height (grid 0fr ↔ 1fr).
  // `content` stays the editor-managed content DOM — Markdown structure unchanged.
  const collapse = document.createElement('div');
  header.className = 'weibei-callout-header';
  type.className = 'weibei-callout-type';
  title.className = 'weibei-callout-title';
  title.placeholder = '标题';
  content.className = 'weibei-callout-content';
  collapse.className = 'weibei-callout-collapse';
  header.append(type, title);
  collapse.append(content);
  dom.append(header, collapse);
  const render = () => {
    const value = String(node.attrs.calloutType || 'note');
    const choices = calloutTypes.has(value) ? Array.from(calloutTypes) : [value, ...calloutTypes];
    type.replaceChildren(...choices.map((choice) => {
      const option = document.createElement('option');
      option.value = choice;
      option.textContent = calloutLabel(choice);
      return option;
    }));
    type.value = value;
    title.value = node.attrs.title || '';
    type.disabled = !isEditable;
    title.readOnly = !isEditable;
    dom.className = `weibei-callout weibei-callout-has-heading weibei-callout-${value}`;
    dom.dataset.type = 'callout';
    dom.dataset.callout = value;
    dom.dataset.calloutFold = node.attrs.fold || '';
    dom.dataset.calloutTitle = node.attrs.title || calloutLabel(value);
  };
  const commit = () => {
    const pos = getPos();
    const current = isEditable && typeof pos === 'number' ? view.state.doc.nodeAt(pos) : null;
    if (current?.type === node.type) view.dispatch(view.state.tr.setNodeMarkup(pos, undefined, { ...node.attrs, calloutType: type.value, title: title.value.trim() }));
  };
  type.addEventListener('change', commit);
  title.addEventListener('blur', commit);
  title.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') { event.preventDefault(); commit(); title.blur(); }
    if (event.key === 'Escape') { event.preventDefault(); render(); title.blur(); }
  });
  structuredNodeRenderers.add(render);
  render();
  return {
    dom,
    contentDOM: content,
    update(next: any) { if (next.type !== node.type) return false; node = next; render(); return true; },
    stopEvent(event: Event) { return event.target === type || event.target === title; },
    ignoreMutation(mutation: any) { return header.contains(mutation.target); },
    destroy() { structuredNodeRenderers.delete(render); },
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

const requestAttachment = async (file: any) => {
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

const looksLikeBlockMarkdown = (markdown: any) => {
  const text = String(markdown || '');
  const trimmed = text.trim();
  if (!trimmed) return false;
  if (text.includes('\n')) return true;
  return /^(?:#{1,6}\s|[-*+]\s|\d+\.\s|>\s|```|~~~|\$\$|\|.*\||---$)/.test(trimmed);
};

const normalizeMarkdownInsertion = (markdown: any) => {
  const text = String(markdown || '');
  if (!looksLikeBlockMarkdown(text)) return text;
  return `\n\n${text.trim()}\n\n`;
};

const placeCursorAtInsertionMarker = () => editor.action((ctx) => {
  const view = ctx.get(editorViewCtx);
  let selectionRange: any = null;
  let range: any = null;
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

const localImageUploader = async (files: any, schema: any) => {
  if (!isEditable) return [];
  const images: any[] = [];
  for (let i = 0; i < files.length; i += 1) {
    const file = files.item(i);
    if (file && file.type.includes('image')) images.push(file);
  }
  const imageNode = schema.nodes.image;
  if (!imageNode || images.length === 0) return [];
  const saved = (await Promise.all(images.map(requestAttachment))) as { alt: string; src: string }[];
  return saved.map(({ alt, src }) => imageNode.createAndFill({ alt, src })).filter(Boolean);
};

const imageFilesFromItems = (items: any) => (Array.from(items || []) as any[])
  .map((item) => item.getAsFile?.())
  .filter((file) => file && file.type.includes('image'));

const markdownImage = ({ alt, src }: { alt: any; src: any }) => {
  const safeAlt = (alt || 'image').replace(/[\[\]\n\r]/g, ' ').trim() || 'image';
  const safeSrc = String(src || '').replace(/\s/g, '%20').replace(/\)/g, '%29');
  return `![${safeAlt}](${safeSrc})`;
};

const insertImageFiles = async (files: any) => {
  if (!isEditable) return;
  const saved = await Promise.all(files.map(requestAttachment));
  replaceSelectionInternal(saved.map(markdownImage).join('\n\n'));
};

const quietScrollableSelector = '#editor, .ProseMirror pre, .weibei-math-block';
const scrollFadeTimers = new WeakMap();

const markScrollActive = (element: any) => {
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
const meaningfulListText = (node: any) => (node.textContent || '').replace(/[\u200B\uFEFF]/g, '').trim();

const emptyListItemTypeAtSelection = (state: any) => {
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

const clearInvisibleCurrentTextblock = (view: any) => {
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

const exitEmptyListItem = (view: any) => {
  let listItemType = emptyListItemTypeAtSelection(view.state);
  if (!listItemType) return false;
  clearInvisibleCurrentTextblock(view);
  listItemType = emptyListItemTypeAtSelection(view.state) || listItemType;
  return liftListItem(listItemType)(view.state, view.dispatch, view);
};

/** Converts an empty code block back to a paragraph for Backspace and Delete. */
const clearEmptyCodeBlock = (view: any, event: any) => {
  if (!isEditable || event.shiftKey || event.altKey || event.metaKey || event.ctrlKey || !['Backspace', 'Delete'].includes(event.key)) return false;
  const { selection, schema } = view.state;
  return selection instanceof TextSelection && selection.empty && selection.$from.parent.type.spec.code === true && selection.$from.parent.content.size === 0 && Boolean(schema.nodes.paragraph && setBlockType(schema.nodes.paragraph)(view.state, view.dispatch));
};

/** Inserts a literal tab character without moving focus out of a code block. */
const insertCodeBlockTab = (view: any, event: any) => {
  if (!isEditable || event.key !== 'Tab' || event.shiftKey || event.altKey || event.metaKey || event.ctrlKey || event.isComposing || event.keyCode === 229) return false;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || selection.$from.parent !== selection.$to.parent || selection.$from.parent.type.spec.code !== true) return false;
  const transaction = view.state.tr.replaceWith(selection.from, selection.to, view.state.schema.text('\t'));
  view.dispatch(transaction.setSelection(TextSelection.create(transaction.doc, selection.from + 1)).scrollIntoView());
  return true;
};

const literalCodeBlockCharacters = new Set(['-', "'", '"']);

/** Inserts ASCII punctuation directly so WebKit cannot apply smart substitutions. */
const insertLiteralCodeBlockCharacter = (view: any, event: any) => {
  if (!isEditable || !literalCodeBlockCharacters.has(event.key) || event.altKey || event.metaKey || event.ctrlKey || event.isComposing || event.keyCode === 229) return false;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || selection.$from.parent !== selection.$to.parent || selection.$from.parent.type.spec.code !== true) return false;
  const transaction = view.state.tr.replaceWith(selection.from, selection.to, view.state.schema.text(event.key));
  view.dispatch(transaction.setSelection(TextSelection.create(transaction.doc, selection.from + event.key.length)).scrollIntoView());
  return true;
};

/** Rejects spell checking, text replacement, and writing suggestion edits in code blocks. */
const preventCodeBlockAutomaticReplacement = (view: any, event: any) => {
  if (!isEditable || event.inputType !== 'insertReplacementText' || event.isComposing || !event.cancelable) return false;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || selection.$from.parent !== selection.$to.parent || selection.$from.parent.type.spec.code !== true) return false;
  event.preventDefault();
  event.stopImmediatePropagation();
  return true;
};

/** Leaves a terminal code block only at the document's final visual or logical line. */
const exitTerminalCodeBlock = (view: any, event: any) => {
  if (!isEditable || event.shiftKey || event.altKey || event.metaKey || event.ctrlKey || !['ArrowRight', 'ArrowDown'].includes(event.key)) return false;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || !selection.empty || selection.$from.parent.type.spec.code !== true) return false;
  const { $from } = selection;
  if ($from.indexAfter(-1) !== $from.node(-1).childCount) return false;
  if (event.key === 'ArrowRight' && $from.parentOffset !== $from.parent.content.size) return false;
  if (event.key === 'ArrowDown' && !view.endOfTextblock('down') && $from.parentOffset !== $from.parent.content.size) return false;
  return exitCode(view.state, view.dispatch);
};

const appendTableRowFromLastCell = (view: any, event: KeyboardEvent) => {
  if (!isEditable || event.key !== 'Tab' || event.shiftKey || event.altKey || event.metaKey || event.ctrlKey || event.isComposing || !isInTable(view.state)) return false;
  const rect = selectedRect(view.state);
  if (rect.bottom !== rect.map.height || rect.right !== rect.map.width) return false;
  let added = false;
  addRowAfter(view.state, (tr: any) => { view.dispatch(tr); added = true; });
  if (added) goToNextCell(1)(view.state, view.dispatch, view);
  return added;
};

const runTableToolbarAction = (view: any, action: string) => {
  if (!isEditable || !isInTable(view.state)) return false;
  if (action === 'addRow') return addRowAfter(view.state, view.dispatch);
  if (action === 'deleteRow') return deleteRow(view.state, view.dispatch);
  if (action === 'addColumn') return addColumnAfter(view.state, view.dispatch);
  if (action === 'deleteColumn') return deleteColumn(view.state, view.dispatch);
  if (action === 'deleteTable') return deleteTable(view.state, view.dispatch);
  return false;
};

const setTableToolbarState = (open: boolean) => {
  if (open) {
    tableToolbarElement.dataset.state = 'open';
    tableToolbarElement.setAttribute('aria-hidden', 'false');
  } else if (tableToolbarElement.dataset.state !== 'closed') {
    // Closing blocks hits and assistive tech immediately, then rests at closed
    // after the ~150ms fade. Reopening flips straight back to open.
    tableToolbarElement.dataset.state = 'closed';
    tableToolbarElement.setAttribute('aria-hidden', 'true');
  }
};

const syncTableToolbar = (view: any) => {
  tableToolbarElement.querySelectorAll('button').forEach((button) => {
    const label = editorLabel((button as HTMLElement).dataset.label);
    button.textContent = label;
    button.setAttribute('aria-label', label);
  });
  if (!isEditable || !isInTable(view.state)) { setTableToolbarState(false); return; }
  const dom = view.domAtPos(view.state.selection.from).node;
  const cell = (dom instanceof Element ? dom : dom.parentElement)?.closest('td, th');
  if (!(cell instanceof HTMLElement)) { setTableToolbarState(false); return; }
  const rect = cell.getBoundingClientRect();
  // Position first, then enter open: moving between cells only updates the
  // coordinates — the state stays open, so the entrance never replays.
  tableToolbarElement.style.left = `${Math.max(8, Math.min(window.innerWidth - tableToolbarElement.offsetWidth - 8, rect.left))}px`;
  tableToolbarElement.style.top = `${Math.max(8, rect.top - 32)}px`;
  setTableToolbarState(true);
};

let decorationCache: {
  doc: any;
  focusedMermaidPos: number | null;
  generation: number;
  decorations: any;
} = { doc: null, focusedMermaidPos: null, generation: -1, decorations: DecorationSet.empty };

const rangeContainsHeading = (doc: any, from: number, to: number) => {
  let found = false;
  const start = Math.max(0, Math.min(doc.content.size, from - 1));
  const end = Math.max(start, Math.min(doc.content.size, Math.max(to, from + 1) + 1));
  doc.nodesBetween(start, end, (node: any) => {
    if (node.type.name === 'heading') found = true;
    return !found;
  });
  return found;
};

/** Limits outline work to transaction ranges that gained, lost, or edited a heading. */
const transactionTouchesHeading = (transaction: any) => transaction.steps.some((step: any, index: number) => {
  const before = transaction.docs[index];
  const after = transaction.docs[index + 1] || transaction.doc;
  let touchesHeading = false;
  step.getMap().forEach((oldStart: number, oldEnd: number, newStart: number, newEnd: number) => {
    if (rangeContainsHeading(before, oldStart, oldEnd) || rangeContainsHeading(after, newStart, newEnd)) touchesHeading = true;
  });
  return touchesHeading;
});

const weiBeiDialectPlugin = $prose(() => new Plugin({
  state: {
    init: () => null,
    apply: (transaction, value, _oldState, newState) => {
      addEditorMetric(checkMetrics, 'transactions');
      if (WEIBEI_EDITOR_RUNTIME && transaction.docChanged && !suppressDirtyTransactions) {
        revisionState = reduceRevision(revisionState, true);
        post('dirtyChanged', { dirty: revisionState.dirty });
      }
      if (transaction.docChanged && transactionTouchesHeading(transaction)) reportOutline(newState.doc);
      return value;
    },
  },
  view(view) {
    const codeInputAttributeValues = { autocapitalize: 'none', autocorrect: 'off', spellcheck: 'false' };
    const defaultCodeInputAttributes = new Map(Object.keys(codeInputAttributeValues).map((name) => [name, view.dom.getAttribute(name)]));
    /** Applies literal-input attributes only while the selection is inside a code block. */
    const synchronizeCodeInputAttributes = (updatedView: any) => {
      if (updatedView.state.selection.$from.parent.type.spec.code === true) {
        for (const [name, value] of Object.entries(codeInputAttributeValues)) updatedView.dom.setAttribute(name, value);
        return;
      }
      for (const [name, value] of defaultCodeInputAttributes) {
        if (value === null) updatedView.dom.removeAttribute(name);
        else updatedView.dom.setAttribute(name, value);
      }
    };
    const synchronizeEmptyPlaceholder = (updatedView: any) => {
      const doc = updatedView.state.doc;
      updatedView.dom.classList.toggle('weibei-empty-document', doc.childCount === 1 && doc.firstChild?.type.name === 'paragraph' && doc.firstChild.content.size === 0);
      updatedView.dom.dataset.emptyPlaceholder = editorLabel('emptyNotePlaceholder');
    };
    const setMermaidSourceFocus = (focused: any) => {
      if (mermaidSourceHasFocus === focused) return;
      mermaidSourceHasFocus = focused;
      view.dispatch(view.state.tr.setMeta('weibeiMermaidFocusChanged', focused));
    };
    const handleEditorFocus = (event: any) => setMermaidSourceFocus(event.target === view.dom);
    const handleEditorBlur = (event: any) => { if (event.target === view.dom) setMermaidSourceFocus(false); };
    const handleCompositionStart = () => {
      compositionStartMarkdown = lastMarkdown;
      compositionEndPending = false;
      const { $from } = view.state.selection;
      compositionTextblockFrom = $from.parent.isTextblock && $from.parent.content.size === 0 ? $from.before($from.depth) : null;
      reportSelection();
    };
    const handleCompositionEnd = () => {
      compositionEndPending = true;
      setTimeout(publishCompletedCompositionMarkdown);
    };
    /** Handles keys that must run before WebKit or lower-priority editor keymaps. */
    const handleEditorKeyDown = (event: any) => {
      if (event.target !== view.dom || !view.hasFocus()) return;
      const handled = insertCodeBlockTab(view, event)
        || insertLiteralCodeBlockCharacter(view, event)
        || (event.key === 'Tab' && !event.shiftKey && !event.altKey && !event.metaKey && !event.ctrlKey && !event.isComposing && event.keyCode !== 229
          && sinkListItem(view.state.schema.nodes.list_item)(view.state, view.dispatch, view));
      if (!handled) return;
      event.preventDefault();
      event.stopImmediatePropagation();
    };
    /** Cancels automatic replacement events without affecting composition or paste input. */
    const handleBeforeInput = (event: any) => {
      if (event.target === view.dom) preventCodeBlockAutomaticReplacement(view, event);
    };
    const keepTableSelection = (event: MouseEvent) => event.preventDefault();
    const handleTableToolbarClick = (event: MouseEvent) => {
      const button = event.target instanceof Element ? event.target.closest('button[data-action]') : null;
      if (!(button instanceof HTMLElement)) return;
      runTableToolbarAction(view, button.dataset.action || '');
      view.focus();
      window.requestAnimationFrame(() => syncTableToolbar(view));
    };
    view.dom.addEventListener('focus', handleEditorFocus, true);
    view.dom.addEventListener('blur', handleEditorBlur, true);
    if (WEIBEI_EDITOR_RUNTIME) {
      view.dom.addEventListener('compositionstart', handleCompositionStart, true);
      view.dom.addEventListener('compositionend', handleCompositionEnd, true);
      view.dom.addEventListener('keydown', handleEditorKeyDown, true);
      view.dom.addEventListener('beforeinput', handleBeforeInput, true);
      tableToolbarElement.addEventListener('mousedown', keepTableSelection);
      tableToolbarElement.addEventListener('click', handleTableToolbarClick);
      document.body.appendChild(tableToolbarElement);
      synchronizeCodeInputAttributes(view);
      synchronizeEmptyPlaceholder(view);
      syncTableToolbar(view);
    }
    mermaidSourceHasFocus = view.hasFocus();
    return {
      update(updatedView, previousState) {
        if (WEIBEI_EDITOR_RUNTIME) {
          synchronizeCodeInputAttributes(updatedView);
          synchronizeEmptyPlaceholder(updatedView);
          syncTableToolbar(updatedView);
        }
        if (updatedView.state.doc.eq(previousState.doc)) return;
        scheduleContentHeightReports();
        reportActiveHeading();
      },
      destroy() {
        view.dom.removeEventListener('focus', handleEditorFocus, true);
        view.dom.removeEventListener('blur', handleEditorBlur, true);
        if (WEIBEI_EDITOR_RUNTIME) {
          view.dom.removeEventListener('compositionstart', handleCompositionStart, true);
          view.dom.removeEventListener('compositionend', handleCompositionEnd, true);
          view.dom.removeEventListener('keydown', handleEditorKeyDown, true);
          view.dom.removeEventListener('beforeinput', handleBeforeInput, true);
          tableToolbarElement.removeEventListener('mousedown', keepTableSelection);
          tableToolbarElement.removeEventListener('click', handleTableToolbarClick);
          tableToolbarElement.remove();
          for (const [name, value] of defaultCodeInputAttributes) {
            if (value === null) view.dom.removeAttribute(name);
            else view.dom.setAttribute(name, value);
          }
        }
        mermaidSourceHasFocus = false;
        activeMermaidPreview = null;
        mermaidPreviewCache = new WeakMap();
      },
    };
  },
  props: {
    handlePaste: WEIBEI_EDITOR_RUNTIME ? (view: any, event: ClipboardEvent) => {
      if (!isEditable) return false;
      const files = imageFilesFromItems(event.clipboardData?.items);
      if (files.length > 0) {
        event.preventDefault();
        insertImageFiles(files).catch(showFailure);
        return true;
      }
      if (pasteTargetIsCode(view)) return false;
      const text = event.clipboardData?.getData('text/plain') || '';
      const tsv = parseTSV(text);
      if (tsv) {
        event.preventDefault();
        if (!pasteTSVIntoTable(view, tsv)) {
          view.dispatch(closeHistory(view.state.tr));
          replaceSelectionInternal(tsvToMarkdown(tsv));
        }
        return true;
      }
      const normalized = normalizeMarkdownSource(text, 'userPaste');
      if (!text || (normalized === text && !looksLikeMarkdownSyntax(normalized))) return false;
      event.preventDefault();
      replaceSelectionInternal(normalized);
      return true;
    } : () => false,
    handleDrop: WEIBEI_EDITOR_RUNTIME ? (_: any, event: DragEvent) => {
      if (!isEditable) return false;
      const files = imageFilesFromItems(event.dataTransfer?.items);
      if (files.length === 0) return false;
      event.preventDefault();
      insertImageFiles(files).catch(showFailure);
      return true;
    } : () => false,
    handleTextInput: WEIBEI_EDITOR_RUNTIME ? (view: any, from: number, to: number, text: string) => {
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
    } : () => false,
    handleClick(view, pos, event) {
      return activateSelectionRemarkMark(event.target)
        || activateSelectionAskMark(event.target)
        || activateWikiLink(event.target)
        || activateSourceReference(event.target)
        || toggleFoldedCallout(event.target);
    },
    handleKeyDown(view, event) {
      if (WEIBEI_EDITOR_RUNTIME) {
        if (appendTableRowFromLastCell(view, event)) { event.preventDefault(); return true; }
        if (handleSlashMenuKeyDown(view, event)) return true;
        if ((event.metaKey || event.ctrlKey) && !event.altKey && (event.key === 'k' || event.key === 'K')) {
          const selection = view.state.selection;
          if (isEditable && !selection.empty) {
            post('linkEditorRequested', {});
            event.preventDefault();
            return true;
          }
        }
        if (event.key === 'Enter' && view.state.selection instanceof NodeSelection) {
          const selected = view.state.selection.node;
          if (selected.type.name === 'math_inline' || selected.type.name === 'math_block') {
            (view.nodeDOM(view.state.selection.from) as HTMLElement | null)?.dispatchEvent(new CustomEvent('weibei-edit-math'));
            event.preventDefault();
            return true;
          }
        }
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
      const focusedBlock = focusedMermaidBlock(state);
      synchronizeActiveMermaidPreview(focusedBlock);
      const focusedMermaidPos = focusedBlock?.pos ?? null;
      const cached = decorationCache;
      if (cached.doc === state.doc
          && cached.focusedMermaidPos === focusedMermaidPos
          && cached.generation === decorationGeneration) {
        addEditorMetric(checkMetrics, 'decorationCacheHits');
        return cached.decorations;
      }

      const decorations: any[] = [];
      const commentState = { open: false };
      const selectionAskCounts = new Map();
      const selectionRemarkCounts = new Map();

      state.doc.descendants((node, pos, parent) => {
        addEditorMetric(checkMetrics, 'decorationNodes');
        const typeName = node.type.name;

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
          // The content regex passes walk every text node on every streaming
          // flush (~30x/second) and compete with the fade animations for the
          // web process main thread. They are irrelevant to mid-stream agent
          // previews; the finished render rebuilds them in full.
          if (streamingMarkdownBuffer !== null) return true;
          decorateHtmlBreaks(decorations, text, textPos);
          decorateComments(decorations, text, textPos, commentState);
          decorateSourceReferences(decorations, text, textPos);
          decorateTagsAndBlocks(decorations, text, textPos);
          decorateSelectionAskMarks(decorations, text, textPos, selectionAskCounts);
          decorateSelectionRemarkMarks(decorations, text, textPos, selectionRemarkCounts);

        }

        return true;
      });

      const set = DecorationSet.create(state.doc, decorations);
      decorationCache = {
        doc: state.doc,
        focusedMermaidPos,
        generation: decorationGeneration,
        decorations: set,
      };
      return set;
    },
  },
}));

const reportSelection = () => {
  if (window.weiBeiSuppressSelectionReport) return;
  const text = compositionStartMarkdown === null ? selectedText() : '';
  const rect = text ? rectFromSelection() : null;
  const details = text && editor ? editor.action((ctx) => {
    const { state } = ctx.get(editorViewCtx);
    const { selection } = state;
    const markNames = ['strong', 'emphasis', 'strike_through', 'highlight', 'link', 'inlineCode'];
    const activeMarks = markNames.filter((name) => state.schema.marks[name] && state.doc.rangeHasMark(selection.from, selection.to, state.schema.marks[name]));
    const writingFont = state.schema.marks.writing_font;
    let selectedFont: string | undefined;
    let mixedFont = false;
    if (writingFont) state.doc.nodesBetween(selection.from, selection.to, (node: any) => {
      if (!node.isText) return true;
      const font = writingFont.isInSet(node.marks || [])?.attrs.font || 'serif';
      if (selectedFont === undefined) selectedFont = font;
      else if (selectedFont !== font) mixedFont = true;
      return true;
    });
    if (selectedFont && !mixedFont) activeMarks.push(`font:${selectedFont}`);
    const isInlineMath = selection instanceof NodeSelection && selection.node.type.name === 'math_inline';
    if (isInlineMath) activeMarks.push('inlineMath');
    let blockType = selection.$from.parent.type.name;
    for (let depth = selection.$from.depth; depth > 0; depth -= 1) {
      const name = selection.$from.node(depth).type.name;
      if (name === 'blockquote' || name === 'block_quote') { blockType = 'blockquote'; break; }
    }
    if (blockType === 'heading') blockType = `heading${selection.$from.parent.attrs.level || ''}`;
    let linkTarget = '';
    const link = state.schema.marks.link;
    if (link) state.doc.nodesBetween(selection.from, selection.to, (node: any) => {
      const mark = link.isInSet(node.marks || []);
      if (mark && !linkTarget) linkTarget = String(mark.attrs.href || '');
      return !linkTarget;
    });
    return {
      activeMarks,
      blockType,
      canConvertToMath: isInlineMath || (selection instanceof TextSelection && !selection.empty && selection.$from.parent === selection.$to.parent && selection.$from.parent.isTextblock),
      linkTarget,
    };
  }) : { activeMarks: [], blockType: '', canConvertToMath: false, linkTarget: '' };
  const rectKey = rect
    ? `${Math.round(rect.x)}:${Math.round(rect.y)}:${Math.round(rect.width)}:${Math.round(rect.height)}`
    : '';
  const detailKey = JSON.stringify(details);
  if (text === lastSelectionReport.text && rectKey === lastSelectionReport.rectKey && detailKey === lastSelectionReport.detailKey) return;
  lastSelectionReport = { text, rectKey, detailKey };
  if (!text) {
    lastSelectionRange = null;
    post('selectionChanged', { text: '', rect: null, ...details });
    return;
  }
  lastSelectionRange = editorSelectionRange();
  post('selectionChanged', { text, rect, ...details });
};

const executeSelectionCommandInternal = (action: unknown, value: unknown = '') => {
  if (!editor || !isEditable || typeof action !== 'string') return false;
  return editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    if (view.state.selection.empty && lastSelectionRange) {
      const from = Math.min(lastSelectionRange.from, view.state.doc.content.size);
      const to = Math.min(lastSelectionRange.to, view.state.doc.content.size);
      if (from < to) view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, from, to)));
    }
    const { state } = view;
    const { selection } = state;
    if (selection.empty) return false;
    let applied = false;
    const toggle = (markName: string) => {
      const mark = state.schema.marks[markName];
      return Boolean(mark && toggleMark(mark)(view.state, view.dispatch, view));
    };
    switch (action) {
      case 'bold': applied = toggle('strong'); break;
      case 'italic': applied = toggle('emphasis'); break;
      case 'strike': applied = toggle('strike_through'); break;
      case 'highlight': applied = toggle('highlight'); break;
      case 'inlineCode': applied = toggle('inlineCode'); break;
      case 'font': {
        const font = typeof value === 'string' && writingFontValues.has(value) ? value : '';
        const mark = state.schema.marks.writing_font;
        if (!font || !mark) break;
        const tr = state.tr.removeMark(selection.from, selection.to, mark)
          .addMark(selection.from, selection.to, mark.create({ font }));
        view.dispatch(tr.scrollIntoView());
        applied = true;
        break;
      }
      case 'link': {
        const link = state.schema.marks.link;
        if (!link) break;
        const href = typeof value === 'string' ? value.trim() : '';
        const tr = state.tr.removeMark(selection.from, selection.to, link);
        if (href) tr.addMark(selection.from, selection.to, link.create({ href }));
        view.dispatch(tr.scrollIntoView());
        applied = true;
        break;
      }
      case 'inlineMath': {
        const math = state.schema.nodes.math_inline;
        const selectedMath = selection instanceof NodeSelection ? selection.node : state.doc.nodeAt(selection.from);
        if (selectedMath?.type === math && selection.to === selection.from + selectedMath.nodeSize) {
          const source = selectedMath.textContent;
          const tr = closeHistory(source
            ? state.tr.replaceWith(selection.from, selection.to, state.schema.text(source))
            : state.tr.delete(selection.from, selection.to));
          tr.setSelection(source
            ? TextSelection.create(tr.doc, selection.from, selection.from + source.length)
            : Selection.near(tr.doc.resolve(Math.min(selection.from, tr.doc.content.size))));
          view.dispatch(tr.scrollIntoView());
          applied = true;
          break;
        }
        const source = state.doc.textBetween(selection.from, selection.to, '\n', '\n');
        if (!math || !source || !(selection instanceof TextSelection) || selection.$from.parent !== selection.$to.parent) break;
        const node = math.create(null, state.schema.text(source));
        const tr = closeHistory(state.tr.replaceRangeWith(selection.from, selection.to, node));
        tr.setSelection(NodeSelection.create(tr.doc, selection.from));
        view.dispatch(tr.scrollIntoView());
        applied = true;
        break;
      }
      case 'quote': {
        const quote = state.schema.nodes.blockquote || state.schema.nodes.block_quote;
        if (!quote) break;
        const inQuote = Array.from({ length: selection.$from.depth }, (_, index) => selection.$from.node(index + 1)).some((node: any) => node.type === quote);
        applied = Boolean((inQuote ? lift : wrapIn(quote))(view.state, view.dispatch, view));
        break;
      }
      default: return false;
    }
    if (applied) {
      view.focus();
      window.requestAnimationFrame(reportSelection);
    }
    return applied;
  });
};

const ensureEditor = () => {
  if (!editor) throw new Error('WeiBei editor is not ready');
};

const setSelectionAskMarksInternal = (marks: any) => {
  selectionAskMarks = normalizeSelectionAskMarks(marks);
  decorationGeneration += 1;
  if (!editor) return;
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.dispatch(view.state.tr.setMeta('weibeiSelectionAskMarksChanged', true));
  });
};

const setSelectionRemarkMarksInternal = (marks: any) => {
  selectionRemarkMarks = normalizeSelectionRemarkMarks(marks);
  decorationGeneration += 1;
  if (!editor) return;
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.dispatch(view.state.tr.setMeta('weibeiSelectionAskMarksChanged', true));
  });
};

/** Removes WebKit-created line breaks when IME composition began in an empty text block. */
const normalizeCompletedEmptyTextblockComposition = () => {
  if (!editor || compositionTextblockFrom === null) return;
  const textblockFrom = compositionTextblockFrom;
  compositionTextblockFrom = null;
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    (view as any).domObserver?.flush();
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
      (view as any).domObserver?.flush();
    }
  });
};

/** Finishes IME cleanup without serializing the document. */
const publishCompletedCompositionMarkdown = () => {
  if (!editor) return;
  normalizeCompletedEmptyTextblockComposition();
  compositionEndPending = false;
  compositionStartMarkdown = null;
  reportSelection();
  scheduleContentHeightReports();
  reportActiveHeading();
};

const streamingCommands = () => editor.action((ctx) => ctx.get(commandsCtx));

const stopStreamingMarkdown = (keep = true) => {
  cancelFinalizeDelay();
  if (streamingMarkdownBuffer === null) return;
  streamingCommands().call(abortStreamingCmd.key, { keep });
  streamingMarkdownBuffer = null;
  streamingRawBody = null;
  streamingFullTextBase = null;
};

/** Streaming tails whose NEXT character changes how already-received
 * characters normalize: a trailing `$` may become `\$5` (currency guard),
 * `\[`/`\(` may become `$$`/`$` delimiters, `\hat x` becomes `\hat{x}`, and
 * `<br>` becomes a hard break. Normalizing before the deciding character
 * arrives rewrites the buffered prefix, which forces a whole-document
 * streaming restart (the visible completion flash). Withhold the undecidable
 * tail instead: nothing is lost — the withheld text re-enters with the next
 * chunk, and the buffer only ever grows by appends. One-line `$$…$$` stays
 * withheld for a short window after closing because normalizeAgentMath
 * expands it to a multi-line block once following text lands; likewise
 * `\[…\]`/`\(...\)` right after their closer. A lone trailing backslash is
 * held so a partial `\h`/`\ha`/`\hat` (or `\[`…) never enters the buffer
 * before the guard can recognize it. */
const UNDECIDABLE_STREAMING_TAIL = /(?:\$\$[^$\n]+\$\$[^\n]{0,7}|\$\$[^$\n]*\$?|\$+|\\h(?:a(?:t[\s\\]*[A-Za-z]*)?)?|\\\[[^\]\n]*(?:\\\][^\]\n]{0,7})?|\\\([^)\n]*(?:\\\)[^)\n]{0,7})?|<\/?[A-Za-z][^>\n]*|<|\\)$/;
/** Line-initial `[…` while unterminated (or just closed): normalizeAgentMath
 * rewrites such a line to a `$$` block when it turns out to be math, so hold
 * the line back until more of the line (or the next one) has arrived. Plain
 * links/lists reappear one tick after `]` lands; citation brackets are
 * already withheld natively by AgentCitationParser. */
const UNDECIDABLE_STREAMING_MATH_LINE = /(?:^|\n)[ \t]*\[[^\]\n]*(?:\][ \t]*\n?)?$/;

const withholdUndecidableStreamingTail = (rawBody: string): string => {
  let cut = rawBody.length;
  const tail = UNDECIDABLE_STREAMING_TAIL.exec(rawBody);
  if (tail) cut = tail.index;
  const mathLine = UNDECIDABLE_STREAMING_MATH_LINE.exec(rawBody);
  if (mathLine) {
    const index = mathLine.index + (mathLine[0].startsWith('\n') ? 1 : 0);
    if (index < cut) cut = index;
  }
  return cut < rawBody.length ? rawBody.slice(0, cut) : rawBody;
};

const updateStreamingMarkdownInternal = (markdown: any) => {
  ensureEditor();
  cancelFinalizeDelay();
  const fullText = String(markdown || '');
  streamingFullTextBase = fullText;
  const document = splitFrontmatter(fullText);
  frontmatterBlock = document.frontmatter;
  syncFrontmatterPanel();
  // Full-text normalization and the withFrontmatter serialization walk the
  // whole document on every push (~30x/second during streaming). When the
  // appended tail is verbatim-clean for those rules, splice it onto the raw
  // anchor instead; any tail containing rule triggers falls back to the full
  // passes, and the finished render always normalizes once, fully.
  const rawBody = withholdUndecidableStreamingTail(document.body);
  const rawTail = streamingRawBody !== null && streamingMarkdownBuffer === streamingRawBody && rawBody.startsWith(streamingRawBody)
    ? rawBody.slice(streamingRawBody.length)
    : null;
  let body: string;
  if (rawTail !== null && !/[$<>\\`\r]/.test(rawTail)) {
    body = rawBody;
    streamingRawBody = rawBody;
  } else {
    body = normalizeMarkdownSource(rawBody, 'agentGenerated');
    streamingRawBody = body === rawBody ? rawBody : null;
    lastMarkdown = withFrontmatter(body);
  }
  const commands = streamingCommands();
  if (streamingMarkdownBuffer === null) {
    commands.call(startStreamingCmd.key);
    streamingMarkdownBuffer = '';
  } else if (!body.startsWith(streamingMarkdownBuffer)) {
    // TEMPORARY probe: prefix-break forces a whole-document streaming restart.
    let divergeAt = 0;
    while (divergeAt < Math.min(body.length, streamingMarkdownBuffer.length)
      && body[divergeAt] === streamingMarkdownBuffer[divergeAt]) divergeAt += 1;
    post('streamDebug', {
      event: 'prefix-break', where: 'update', divergeAt,
      bufferLen: streamingMarkdownBuffer.length, bodyLen: body.length,
      bufferAround: streamingMarkdownBuffer.slice(Math.max(0, divergeAt - 12), divergeAt + 24),
      bodyAround: body.slice(Math.max(0, divergeAt - 12), divergeAt + 24),
      bufferTail: streamingMarkdownBuffer.slice(-40), bodyHead: body.slice(0, 40),
    });
    commands.call(endStreamingCmd.key, { diffReview: false });
    commands.call(startStreamingCmd.key);
    streamingMarkdownBuffer = '';
  }
  const delta = body.slice(streamingMarkdownBuffer.length);
  // Let the appearance plugin inspect the same complete body during the
  // transaction so it can hide unfinished syntax without withholding text.
  streamingMarkdownBuffer = body;
  if (delta) commands.call(pushChunkCmd.key, delta);
  scheduleContentHeightReports();
};

// Native streaming pushes normally carry only the suffix appended since the
// previous push. Without a baseline (cold start, after setMarkdown) the
// suffix IS the full document, which keeps the bridge safe with one rule.
const appendStreamingMarkdownInternal = (suffix: any) => {
  const tail = String(suffix || '');
  if (!tail) return;
  const base = streamingFullTextBase;
  updateStreamingMarkdownInternal(base === null ? tail : base + tail);
};

/** Ending the session clears fade decorations instantly — for text still
 * mid-fade that is a whole-answer opacity snap ("everything flashes once").
 * The final body is already in the document, so the session can outlive the
 * last push by one fade window and end with every animation completed. */
let finalizeDelayTimer: number | null = null;
// Must exceed the CSS blur-in window (FADE_MILLISECONDS in
// streaming-appearance.ts) with headroom: finalizing earlier would unwrap
// decoration spans while the last characters are still materializing, which
// reads as the tail flashing once.
const FINALIZE_FADE_SETTLE_MILLISECONDS = 560;
const cancelFinalizeDelay = () => {
  if (finalizeDelayTimer == null) return;
  window.clearTimeout(finalizeDelayTimer);
  finalizeDelayTimer = null;
};
const scheduleFinalizeAfterFades = () => {
  cancelFinalizeDelay();
  // throttleMs=0 already flushed the final push synchronously. Retire only the
  // plugin state: endStreamingCmd reparses the same Markdown and rewrites text
  // nodes, which looks like a second final answer even when the text is equal.
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.dispatch(view.state.tr.setMeta(streamingPluginKey, { type: 'end' }));
  });
  if (document.hidden || isEditorReduceMotion()) {
    finalizeStreamingSession();
    return;
  }
  finalizeDelayTimer = window.setTimeout(() => {
    finalizeDelayTimer = null;
    finalizeStreamingSession();
  }, FINALIZE_FADE_SETTLE_MILLISECONDS);
};

/** Push a caller-normalized body through the streaming session, mirroring
 * updateStreamingMarkdownInternal's session bookkeeping. */
const pushStreamingBodyForFinish = (body: string) => {
  const commands = streamingCommands();
  // TEMPORARY probe: report the finalize path's buffer relation.
  post('streamDebug', {
    event: 'finish-enter',
    bufferLen: streamingMarkdownBuffer === null ? -1 : streamingMarkdownBuffer.length,
    bodyLen: body.length,
    prefixMatch: streamingMarkdownBuffer === null ? null : body.startsWith(streamingMarkdownBuffer),
  });
  if (streamingMarkdownBuffer === null) {
    commands.call(startStreamingCmd.key);
    streamingMarkdownBuffer = '';
  } else if (!body.startsWith(streamingMarkdownBuffer)) {
    // TEMPORARY probe: prefix-break at finalize = whole-document re-parse.
    post('streamDebug', {
      event: 'prefix-break', where: 'finish',
      bufferLen: streamingMarkdownBuffer.length, bodyLen: body.length,
      bufferTail: streamingMarkdownBuffer.slice(-40), bodyHead: body.slice(0, 40),
    });
    commands.call(endStreamingCmd.key, { diffReview: false });
    commands.call(startStreamingCmd.key);
    streamingMarkdownBuffer = '';
  }
  const delta = body.slice(streamingMarkdownBuffer.length);
  streamingMarkdownBuffer = body;
  if (delta) commands.call(pushChunkCmd.key, delta);
  scheduleContentHeightReports();
};

const finalizeStreamingSession = () => {
  cancelFinalizeDelay();
  // Hide the decorative caret before retiring the visual streaming state. It
  // is absolutely positioned, so this changes neither wrapping nor row height.
  document.querySelectorAll('.wb-stream-caret').forEach((caret) => {
    caret.classList.add('is-finalized');
  });
  streamingRawBody = null;
  streamingMarkdownBuffer = null;
  streamingFullTextBase = null;
  // Do not force a same-state ProseMirror redraw here. The fully opaque fade
  // wrappers are visually inert and clear on the next real transaction; a
  // completion-only redraw was the visible whole-answer flash.
  publishContentHeight();
  post('finalizedStreaming', {
    height: Number(window.WeiBeiCompactPreviewHeight || 1),
  });
  scheduleContentHeightReports();
};

const finishStreamingMarkdownInternal = (markdown: any) => {
  streamingRawBody = null; // force the full normalize + serialization pass
  const fullText = String(markdown || '');
  const document = splitFrontmatter(fullText);
  frontmatterBlock = document.frontmatter;
  syncFrontmatterPanel();
  const body = normalizeMarkdownSource(document.body, 'agentGenerated');
  lastMarkdown = withFrontmatter(body);
  streamingFullTextBase = fullText;
  // Native already owns the visible cadence. Synchronously catch up any bridge
  // lag once, then keep the existing fade-settle and finalized-height receipt.
  pushStreamingBodyForFinish(body);
  scheduleFinalizeAfterFades();
};

const setMarkdownInternal = (markdown: any) => {
  ensureEditor();
  stopStreamingMarkdown();
  streamingFullTextBase = null;
  compositionStartMarkdown = null;
  compositionTextblockFrom = null;
  compositionEndPending = false;
  currentContentGeneration += 1;
  const document = splitFrontmatter(markdown || '');
  const body = normalizeMarkdownSource(document.body, 'userDocument');
  frontmatterBlock = document.frontmatter;
  syncFrontmatterPanel();
  editor.action(replaceAll(body));
  lastMarkdown = withFrontmatter(body);
  editor.action((ctx) => reportOutline(ctx.get(editorViewCtx).state.doc));
  scheduleContentHeightReports();
};

const loadMarkdownInternal = (markdown: any, revision = 0, dirty = false) => {
  suppressDirtyTransactions = true;
  revisionState = { revision, dirty };
  try {
    setMarkdownInternal(markdown);
  } finally {
    suppressDirtyTransactions = false;
  }
  if (WEIBEI_EDITOR_RUNTIME) post('dirtyChanged', { dirty });
};

const getMarkdownInternal = () => {
  ensureEditor();
  addEditorMetric(checkMetrics, 'fullSerializations');
  const markdown = editor.action(readMarkdown()).replace(/^\s*\|.*\|\s*$/gm, (line) => (
    line.replace(/(?<=\|)[ \t]*<br\s*\/?>[ \t]*(?=\|)/gi, ' ')
  ));
  return withFrontmatter(markdown);
};

const pasteTargetIsCode = (view: any) => {
  const selection = view?.state?.selection;
  if (!selection?.$from) return false;
  if (selection.$from.parent.type.spec.code) return true;
  const marks = selection.$from.marks() || [];
  return marks.some((mark: any) => String(mark?.type?.name || '').toLowerCase().includes('code'));
};

const parseTSV = (text: string) => {
  if (!text.includes('\t')) return null;
  return text.replace(/\r\n?/g, '\n').replace(/\n$/, '').split('\n').map((row) => row.split('\t'));
};

const tsvToMarkdown = (rows: string[][]) => {
  const width = Math.max(...rows.map((row) => row.length));
  const line = (row: string[]) => `| ${Array.from({ length: width }, (_, index) => String(row[index] || '').replace(/\\/g, '\\\\').replace(/\|/g, '\\|')).join(' | ')} |`;
  return [line(rows[0]), line(Array.from({ length: width }, () => '---')), ...rows.slice(1).map(line)].join('\n');
};

const pasteTSVIntoTable = (view: any, rows: string[][]) => {
  if (!isInTable(view.state)) return false;
  const start = selectedRect(view.state);
  const tablePosition = start.tableStart - 1;
  const targetRows = start.top + rows.length;
  const targetColumns = start.left + Math.max(...rows.map((row) => row.length));
  const transaction = view.state.tr;
  let rect = start;
  const refresh = () => {
    const table = transaction.doc.nodeAt(tablePosition);
    if (!table) return false;
    rect = { ...rect, table, map: TableMap.get(table) };
    return true;
  };
  while (rect.map.width < targetColumns) {
    addColumn(transaction, rect, rect.map.width);
    if (!refresh()) return false;
  }
  while (rect.map.height < targetRows) {
    addRow(transaction, rect, rect.map.height);
    if (!refresh()) return false;
  }
  const cells = rows.flatMap((row, rowIndex) => row.map((value, columnIndex) => {
    const position = rect.tableStart + rect.map.positionAt(start.top + rowIndex, start.left + columnIndex, rect.table);
    return { cell: transaction.doc.nodeAt(position), position, value };
  })).filter(({ cell }) => Boolean(cell)).sort((left, right) => right.position - left.position);
  const paragraph = view.state.schema.nodes.paragraph;
  if (!paragraph || cells.length !== rows.reduce((count, row) => count + row.length, 0)) return false;
  for (const { cell, position, value } of cells) {
    transaction.replaceWith(position + 1, position + cell.nodeSize - 1, paragraph.create(null, value ? view.state.schema.text(value) : null));
  }
  const firstPosition = rect.tableStart + rect.map.positionAt(start.top, start.left, rect.table);
  transaction.setSelection(Selection.near(transaction.doc.resolve(firstPosition + 1), 1));
  view.dispatch(closeHistory(transaction).scrollIntoView());
  return true;
};

const replaceSelectionInternal = (markdown: any) => {
  ensureEditor();
  const insertion = normalizeMarkdownSource(markdown || '', 'internalFragment');
  const range = lastSelectionRange || editorSelectionRange();
  if (range) {
    editor.action(replaceRange(insertion, range));
  } else {
    editor.action(insert(insertion));
  }
  lastSelectionRange = null;
};

const insertMarkdownInternal = (markdown: any, source: 'agentGenerated' | 'internalFragment' = 'internalFragment') => {
  ensureEditor();
  const range = editorSelectionRange();
  const insertion = normalizeMarkdownInsertion(normalizeMarkdownSource(markdown, source));
  if (range) {
    editor.action(replaceRange(insertion, range));
  } else {
    editor.action(insert(insertion));
  }
  if (!placeCursorAtInsertionMarker()) {
    collapseSelectionToEnd();
  }
  lastSelectionRange = null;
};

const appendMarkdownInternal = (markdown: any) => {
  ensureEditor();
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.dispatch(view.state.tr.setSelection(Selection.atEnd(view.state.doc)));
  });
  insertMarkdownInternal(markdown, 'agentGenerated');
};

const selectFirstTextForCheck = (needle: any) => {
  ensureEditor();
  if (!window.weiBeiEditorCheckMode || !needle) return false;
  return editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    let range: any = null;
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

const typeTextForCheck = (text: any) => {
  ensureEditor();
  if (!window.weiBeiEditorCheckMode) return false;
  return editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.focus();
    for (const character of String(text || '')) {
      const { from, to } = view.state.selection;
      let handled = false;
      view.someProp('handleTextInput', (handler: any) => {
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

const pressKeyForCheck = (key: any, options: any = {}) => {
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

const headingElements = () => Array.from(document.querySelectorAll('.ProseMirror h1, .ProseMirror h2, .ProseMirror h3, .ProseMirror h4, .ProseMirror h5, .ProseMirror h6'));
let activeHeadingFrame = 0;
let lastActiveHeadingIndex = -2;
let lastOutlineChangeKey: string | null = null;

const reportOutline = (doc: any) => {
  const items: EditorOutlineItem[] = [];
  const documentSize = Math.max(1, doc.content.size);
  doc.descendants((node: any, pos: number) => {
    if (node.type.name !== 'heading') return true;
    const title = node.textContent.trim();
    if (!title) return false;
    const index = items.length;
    items.push({
      id: `note-heading-${index}`,
      index,
      level: Number(node.attrs.level || 1),
      title,
      position: Math.max(0, Math.min(1, pos / documentSize)),
    });
    return false;
  });
  const key = outlineChangeKey(items);
  if (key === lastOutlineChangeKey) return;
  lastOutlineChangeKey = key;
  addEditorMetric(checkMetrics, 'outlineReports');
  post('outlineChanged', { items });
};

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

const scrollToHeadingInternal = (rawIndex: any) => {
  const index = Number(rawIndex);
  const headings = headingElements();
  const heading = Number.isFinite(index) ? headings[Math.max(0, Math.floor(index))] : null;
  if (!heading) return false;
  const reduceMotion = isEditorReduceMotion();
  heading.scrollIntoView({ block: 'start', behavior: reduceMotion ? 'auto' : 'smooth' });
  if (reduceMotion) {
    // Instant jump settled this frame — report the position immediately;
    // only smooth scrolling needs the delayed report.
    reportActiveHeading();
  } else {
    window.setTimeout(reportActiveHeading, 180);
  }
  return true;
};

const setDocumentIdentityInternal = (documentID: string, documentGeneration: number) => {
  const changed = documentID !== currentDocumentID || documentGeneration !== currentDocumentGeneration;
  currentDocumentID = documentID;
  currentDocumentGeneration = documentGeneration;
  if (!changed) return;
  appliedCommandIDs.clear();
  lastOutlineChangeKey = null;
  currentContentGeneration += 1;
  pendingImagePickers.clear();
  pendingAttachments.clear();
  setSelectionAskMarksInternal([]);
  setSelectionRemarkMarksInternal([]);
};

const setEditableInternal = (next: unknown) => {
  isEditable = next !== false;
  syncEditableState();
  if (!editor) return;
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.dispatch(view.state.tr.setMeta('weibeiEditableChanged', isEditable));
  });
};

const setThemeInternal = (next: unknown) => {
  applyTheme(next);
  decorationGeneration += 1;
  refreshRenderedImages();
  if (!editor) return;
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.dispatch(view.state.tr.setMeta('weibeiThemeChanged', currentTheme));
  });
};

const setLanguageInternal = (next: unknown) => {
  currentLanguage = normalizeInterfaceLanguage(next);
  decorationGeneration += 1;
  document.documentElement.dataset.weibeiLanguage = currentLanguage;
  syncFrontmatterPanel();
  syncEditableState();
  structuredNodeRenderers.forEach((render) => render());
  if (WEIBEI_EDITOR_RUNTIME && slashMenuElement.dataset.show === 'true') renderSlashMenu();
  if (!editor) return;
  editor.action((ctx) => {
    const view = ctx.get(editorViewCtx);
    view.dispatch(view.state.tr.setMeta('weibeiLanguageChanged', currentLanguage));
  });
};

const focusInternal = () => {
  if (!editor) return false;
  editor.action((ctx) => ctx.get(editorViewCtx).focus());
  return true;
};

const commandPayloadValue = (command: EditorCommand, name: string) => command.payload[name] ?? command.payload.value;

const dispatchEditorCommand = (value: unknown) => {
  const command = parseEditorCommand(value);
  if (!command) return false;
  if (appliedCommandIDs.has(command.commandID)) {
    post('commandApplied', { commandID: command.commandID });
    return true;
  }
  if (!acceptsEditorCommand(command, {
    documentID: currentDocumentID,
    documentGeneration: currentDocumentGeneration,
    revision: revisionState.revision,
  })) {
    post('commandRejected', { commandID: command.commandID, reason: 'document or revision mismatch' });
    return false;
  }

  let applied = false;
  try {
    switch (command.type) {
    case 'loadDocument': {
      const markdown = commandPayloadValue(command, 'markdown');
      const initialRevision = commandPayloadValue(command, 'initialRevision');
      if (typeof markdown !== 'string'
          || (initialRevision !== undefined && !Number.isInteger(initialRevision))) break;
      setDocumentIdentityInternal(command.documentID, command.documentGeneration);
      loadMarkdownInternal(markdown, Number(initialRevision ?? 0));
      applied = true;
      break;
    }
    case 'requestSnapshot': {
      const markdown = getMarkdownInternal();
      lastMarkdown = markdown;
      post('snapshotReady', { requestID: command.requestID!, markdown });
      applied = true;
      break;
    }
    case 'setTheme':
      setThemeInternal(commandPayloadValue(command, 'theme'));
      applied = true;
      break;
    case 'setLanguage':
      setLanguageInternal(commandPayloadValue(command, 'language'));
      applied = true;
      break;
    case 'setEditable':
      setEditableInternal(commandPayloadValue(command, 'editable'));
      applied = true;
      break;
    case 'focus':
      applied = focusInternal();
      break;
    case 'scrollToHeading':
      applied = scrollToHeadingInternal(commandPayloadValue(command, 'index'));
      break;
    case 'applyMarkdownFragment': {
      const markdown = commandPayloadValue(command, 'markdown');
      if (typeof markdown !== 'string') break;
      appendMarkdownInternal(markdown);
      applied = true;
      break;
    }
    case 'replaceSelection': {
      const markdown = commandPayloadValue(command, 'markdown');
      if (typeof markdown !== 'string') break;
      replaceSelectionInternal(markdown);
      applied = true;
      break;
    }
    case 'executeSelectionCommand':
      applied = executeSelectionCommandInternal(commandPayloadValue(command, 'action'), commandPayloadValue(command, 'value'));
      break;
    case 'insertStructuredBlock': {
      const markdown = commandPayloadValue(command, 'markdown');
      if (typeof markdown !== 'string') break;
      insertMarkdownInternal(markdown);
      applied = true;
      break;
    }
    case 'restoreCheckpoint': {
      const markdown = commandPayloadValue(command, 'markdown');
      const revision = commandPayloadValue(command, 'revision');
      if (typeof markdown !== 'string' || (revision !== undefined && (!Number.isInteger(revision) || Number(revision) < 0))) break;
      loadMarkdownInternal(markdown, revision === undefined ? revisionState.revision : Number(revision), true);
      applied = true;
      break;
    }
    }
  } catch (error) {
    post('commandRejected', { commandID: command.commandID, reason: String((error as any)?.message || error) });
    return false;
  }
  if (!applied) {
    post('commandRejected', { commandID: command.commandID, reason: 'command could not be applied' });
    return false;
  }
  appliedCommandIDs.add(command.commandID);
  post('commandApplied', { commandID: command.commandID });
  return true;
};

window.WeiBeiEditor = {
  ...(WEIBEI_EDITOR_RUNTIME ? {
    dispatchCommand: dispatchEditorCommand,
    resolveAttachment: (id: any, src: any, alt: any) => {
      const pending = pendingAttachments.get(id);
      if (!pending) return;
      pendingAttachments.delete(id);
      pending.resolve({ src, alt });
    },
    rejectAttachment: (id: any, message: any) => {
      const pending = pendingAttachments.get(id);
      if (!pending) return;
      pendingAttachments.delete(id);
      pending.reject(new Error(message || 'Attachment save failed'));
    },
    resolveImagePicker: (id: any, src: any, alt: any) => {
      const pending = pendingImagePickers.get(id);
      if (!pending) return false;
      pendingImagePickers.delete(id);
      if (pending.documentID !== currentDocumentID || pending.documentGeneration !== currentDocumentGeneration) return false;
      if (pending.mode === 'replace') {
        const pos = pending.getPos();
        const current = typeof pos === 'number' ? pending.view.state.doc.nodeAt(pos) : null;
        if (current?.type.name !== 'image') return false;
        const oldSize = parseMarkdownImageAlt(current.attrs.alt || '').size;
        const nextAlt = `${String(alt || 'image')}${oldSize ? `|${oldSize.width}${oldSize.height ? `x${oldSize.height}` : ''}` : ''}`;
        pending.view.dispatch(pending.view.state.tr.setNodeMarkup(pos, undefined, { ...current.attrs, src, alt: nextAlt }).scrollIntoView());
        pending.view.focus();
        return true;
      }
      return applySlashReplacement(pending.view, pending.context, slashReplacement('image', pending.view.state.schema, { src, alt }));
    },
    cancelImagePicker: (id: any) => {
      const pending = pendingImagePickers.get(id);
      if (!pending) return false;
      pendingImagePickers.delete(id);
      if (pending.mode === 'replace') pending.view.focus();
      return pending.documentID === currentDocumentID && pending.documentGeneration === currentDocumentGeneration;
    },
    discardImagePicker: (id: any) => pendingImagePickers.delete(id),
    rejectImagePicker: (id: any, message: any) => {
      const pending = pendingImagePickers.get(id);
      if (!pending) return false;
      pendingImagePickers.delete(id);
      if (pending.documentID !== currentDocumentID || pending.documentGeneration !== currentDocumentGeneration) return false;
      if (pending.mode === 'replace') { pending.view.focus(); return true; }
      slashRuntime.dismissedContext = '';
      slashRuntime.error = message || editorLabel('slashImageFailed');
      slashRuntime.view = pending.view;
      slashRuntime.provider?.show();
      renderSlashMenu();
      return true;
    },
  } : {
    getMarkdown: getMarkdownInternal,
    setMarkdown: (markdown: any) => setMarkdownInternal(String(markdown || '')),
    updateStreamingMarkdown: (markdown: any) => {
      try {
        updateStreamingMarkdownInternal(markdown);
      } catch (error) {
        showFailure(error);
      }
    },
    appendStreamingMarkdown: (suffix: any) => {
      try {
        appendStreamingMarkdownInternal(suffix);
      } catch (error) {
        showFailure(error);
      }
    },
    finishStreamingMarkdown: (markdown: any) => {
      try {
        finishStreamingMarkdownInternal(markdown);
        return true;
      } catch (error) {
        showFailure(error);
        return false;
      }
    },
    setDocumentID: (next: any) => {
      const nextID = next || '';
      if (nextID !== currentDocumentID) setDocumentIdentityInternal(nextID, currentDocumentGeneration + 1);
    },
  }),
  // Unconditional exports: the native side calls these right after editor
  // ready (theme / language / reduce-motion / text-tier sync / focus / rail
  // scroll). They must exist in plain app boots, not only check mode — a
  // missing method throws inside the page, and the editorFailure hook then
  // remounts the webview in a loop (2026-08-22 notes flicker regression).
  setTheme: setThemeInternal,
  setInterfaceLanguage: setLanguageInternal,
  setReduceMotion: setReduceMotionInternal,
  setTextScale: setTextScaleInternal,
  focus: focusInternal,
  scrollToHeading: scrollToHeadingInternal,
  setSelectionAskMarks: setSelectionAskMarksInternal,
  setSelectionRemarkMarks: setSelectionRemarkMarksInternal,
  setMarkdownBaseURL: (next: any) => {
    markdownBaseURL = next || '';
    refreshRenderedImages();
  },
};

if (WEIBEI_EDITOR_RUNTIME && window.weiBeiEditorCheckMode) {
  Object.assign(window.WeiBeiEditor, {
    getMarkdown: getMarkdownInternal,
    setMarkdown: setMarkdownInternal,
    updateStreamingMarkdown: updateStreamingMarkdownInternal,
    appendStreamingMarkdown: appendStreamingMarkdownInternal,
    finishStreamingMarkdown: (markdown: any) => { finishStreamingMarkdownInternal(markdown); return true; },
    replaceSelection: replaceSelectionInternal,
    executeSelectionCommand: executeSelectionCommandInternal,
    applyAgentPatch: appendMarkdownInternal,
    insertMarkdownImage: replaceSelectionInternal,
    insertMarkdown: insertMarkdownInternal,
    setEditable: setEditableInternal,
    setDocumentID: (next: any) => setDocumentIdentityInternal(String(next || ''), currentDocumentGeneration + 1),
    setTheme: setThemeInternal,
    setInterfaceLanguage: setLanguageInternal,
    setReduceMotion: setReduceMotionInternal,
    setTextScale: setTextScaleInternal,
    focus: focusInternal,
    scrollToHeading: scrollToHeadingInternal,
  });
  window.WeiBeiEditor.getCheckMetrics = () => ({ ...checkMetrics!, fullBridgeMessages: fullMarkdownBridgeMessages });
  window.WeiBeiEditor.resetCheckMetrics = () => {
    resetEditorCheckMetrics(checkMetrics);
    fullMarkdownBridgeMessages = 0;
  };
  window.WeiBeiEditor.getBridgeSessionForCheck = () => ({
    protocolVersion: editorProtocolVersion,
    documentID: currentDocumentID,
    documentGeneration: currentDocumentGeneration,
    revision: revisionState.revision,
    dirty: revisionState.dirty,
  });
  window.WeiBeiEditor.selectFirstTextForCheck = selectFirstTextForCheck;
  window.WeiBeiEditor.selectedTextForCheck = editorSelectedText;
  window.WeiBeiEditor.typeTextForCheck = typeTextForCheck;
  window.WeiBeiEditor.pressKeyForCheck = pressKeyForCheck;
  window.WeiBeiEditor.compositionStateForCheck = () => ({ start: compositionStartMarkdown, last: lastMarkdown, composing: editor.action((ctx) => ctx.get(editorViewCtx).composing) });
  window.WeiBeiEditor.openSlashMenuForCheck = () => { const view = slashRuntime.view; if (!view || !slashContextForView(view)) return false; slashRuntime.dismissedContext = ''; slashRuntime.provider?.show(); renderSlashMenu(); return slashMenuElement.dataset.show === 'true'; };
  window.WeiBeiEditor.slashStateForCheck = () => ({ show: slashMenuElement.dataset.show === 'true', commands: Array.from(slashMenuElement.querySelectorAll('.weibei-slash-command-button')).map((button) => button.textContent), groups: Array.from(slashMenuElement.querySelectorAll('.weibei-slash-group')).map((group) => group.textContent), rows: slashRuntime.tableRows, columns: slashRuntime.tableColumns, tableOpen: slashRuntime.tableOpen, tableSide: slashTablePanelElement?.dataset.side || '', activeDescendant: slashRuntime.view?.dom.getAttribute('aria-activedescendant') || '', announcement: slashStatusElement.textContent, error: slashRuntime.error });
  window.WeiBeiEditor.renderSlashMenuForCheck = renderSlashMenu;
  window.WeiBeiEditor.executeSlashCommandForCheck = (id: any) => executeSlashCommand(id);
  window.WeiBeiEditor.pendingImagePickerIDsForCheck = () => Array.from(pendingImagePickers.keys());
  window.WeiBeiEditor.undoForCheck = () => editor.action((ctx) => undo(ctx.get(editorViewCtx).state, ctx.get(editorViewCtx).dispatch));
  window.WeiBeiEditor.redoForCheck = () => editor.action((ctx) => redo(ctx.get(editorViewCtx).state, ctx.get(editorViewCtx).dispatch));
  window.WeiBeiEditor.selectFirstCodeBlockEndForCheck = () => editor.action((ctx) => { const view = ctx.get(editorViewCtx); let target: any = null; view.state.doc.descendants((node, pos) => { if (target !== null || node.type.name !== 'code_block') return true; target = pos + node.content.size + 1; return false; }); if (target === null) return false; view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, target))); view.focus(); return true; });
  window.WeiBeiEditor.selectDocumentEndForCheck = () => editor.action((ctx) => { const view = ctx.get(editorViewCtx); view.dispatch(view.state.tr.setSelection(Selection.atEnd(view.state.doc))); view.focus(); return true; });
  window.WeiBeiEditor.selectionForCheck = () => editor.action((ctx) => {
    const selection = ctx.get(editorViewCtx).state.selection;
    return { from: selection.from, to: selection.to, parent: selection.$from.parent.type.name, parentOffset: selection.$from.parentOffset };
  });
}

const initialDocument = splitFrontmatter(window.initialMarkdown || '');
initialDocument.body = normalizeMarkdownSource(initialDocument.body, 'userDocument');
frontmatterBlock = initialDocument.frontmatter;
lastMarkdown = withFrontmatter(initialDocument.body);
syncFrontmatterPanel();

let editorBuilder = Editor
  .make()
  .config((ctx) => {
    ctx.set(rootCtx, document.querySelector('#editor'));
    ctx.set(defaultValueCtx, initialDocument.body);
    ctx.set(editorViewOptionsCtx, {
      editable: () => isEditable,
      nodeViews: WEIBEI_EDITOR_RUNTIME ? {
        code_block: createCodeBlockNodeView,
        image: createImageNodeView,
        math_inline: createMathNodeView,
        math_block: createMathNodeView,
        wiki_link: createStructuredInlineNodeView,
        embed: createStructuredInlineNodeView,
        inline_footnote: createStructuredInlineNodeView,
        callout: createCalloutNodeView,
      } : {
        image: createReadOnlyImageNodeView,
        math_inline: createReadOnlyMathNodeView,
        math_block: createReadOnlyMathNodeView,
      },
    });
    ctx.set(streamingConfig.key, {
      throttleMs: 0,
      scrollFollow: false,
      diffReviewOnEnd: false,
      ignoreAttrs: { heading: ['id'] },
    });
  });

if (WEIBEI_EDITOR_RUNTIME) {
  editorBuilder = editorBuilder.config((ctx) => {
    ctx.set(uploadConfig.key, {
      uploader: localImageUploader,
      enableHtmlFileUploader: true,
      uploadWidgetFactory: (pos: any, spec: any) => {
        const widget = document.createElement('span');
        widget.className = 'weibei-uploading';
        widget.textContent = editorLabel('uploadingImage');
        return Decoration.widget(pos, widget, spec);
      },
    });
    ctx.set(weiBeiSlash.key, {
      view(view: any) {
        const preventLinePlusBlur = (event: MouseEvent) => event.preventDefault();
        const openLineMenu = () => {
          const $from = emptyLineContextForView(view);
          if (!$from) return;
          view.dispatch(view.state.tr.insertText('/', $from.pos).scrollIntoView());
          view.focus();
          slashRuntime.dismissedContext = '';
        };
        linePlusElement.addEventListener('mousedown', preventLinePlusBlur);
        linePlusElement.addEventListener('click', openLineMenu);
        document.body.append(slashStatusElement, linePlusElement);
        const provider = new SlashProvider({ content: slashMenuElement, debounce: 0, offset: 6, root: document.body, shouldShow: (updatedView) => { const context = slashContextForView(updatedView); return Boolean(context && slashRuntime.dismissedContext !== context.key); } });
        slashRuntime.provider = provider; slashRuntime.view = view;
        // Visual state machine (closed → opening → open → closing → closed) wraps the
        // provider's raw show/hide: open fades ~250ms, close fades ~150ms and blocks
        // hit testing + assistive tech immediately. Every open or close bumps a
        // generation; cleanup callbacks (transitionend + a missed-event fallback)
        // only run while their generation is still current, so a fast close → reopen
        // can never be torn down by the stale close.
        const providerShow = provider.show.bind(provider);
        const providerHide = provider.hide.bind(provider);
        const finishSlashMenuHide = (generation: number) => {
          if (slashMenuPhase.generation !== generation) return;
          slashMenuPhase.state = 'closed';
          slashMenuElement.dataset.state = 'closed';
          providerHide();
        };
        provider.show = () => {
          slashMenuPhase.generation += 1;
          window.clearTimeout(slashMenuPhase.timer);
          if (window.weiBeiEditorCheckMode || isEditorReduceMotion()) {
            slashMenuPhase.state = 'open';
            slashMenuElement.dataset.state = 'open';
            providerShow();
            return;
          }
          providerShow();
          slashMenuPhase.state = 'opening';
          slashMenuElement.dataset.state = 'opening';
          const generation = slashMenuPhase.generation;
          slashMenuPhase.frame = window.requestAnimationFrame(() => {
            if (slashMenuPhase.generation !== generation) return;
            slashMenuPhase.state = 'open';
            slashMenuElement.dataset.state = 'open';
          });
        };
        provider.hide = () => {
          slashMenuPhase.generation += 1;
          window.clearTimeout(slashMenuPhase.timer);
          window.cancelAnimationFrame(slashMenuPhase.frame);
          if (slashMenuElement.dataset.show !== 'true' || window.weiBeiEditorCheckMode || isEditorReduceMotion()) {
            finishSlashMenuHide(slashMenuPhase.generation);
            return;
          }
          slashMenuPhase.state = 'closing';
          slashMenuElement.dataset.state = 'closing';
          slashMenuElement.setAttribute('aria-hidden', 'true');
          const generation = slashMenuPhase.generation;
          const finish = () => {
            if (slashMenuPhase.generation !== generation) return;
            slashMenuElement.removeAttribute('aria-hidden');
            finishSlashMenuHide(generation);
          };
          slashMenuElement.addEventListener('transitionend', function onSlashMenuTransitionEnd(event) {
            if (event.target !== slashMenuElement || event.propertyName !== 'opacity') return;
            slashMenuElement.removeEventListener('transitionend', onSlashMenuTransitionEnd);
            finish();
          });
          slashMenuPhase.timer = window.setTimeout(finish, 200);
        };
        provider.onShow = () => { slashRuntime.view = view; renderSlashMenu(); };
        provider.onHide = () => { slashRuntime.context = null; slashRuntime.tableOpen = false; dismissSlashTablePanel(); syncSlashAccessibility(); };
        provider.update(view);
        syncLinePlus(view);
        return { update(updatedView: any, previousState: any) { slashRuntime.view = updatedView; const context = slashContextForView(updatedView); if (slashRuntime.dismissedContext && context?.key !== slashRuntime.dismissedContext) slashRuntime.dismissedContext = ''; provider.update(updatedView, previousState); syncLinePlus(updatedView); }, destroy() { provider.destroy(); linePlusElement.removeEventListener('mousedown', preventLinePlusBlur); linePlusElement.removeEventListener('click', openLineMenu); slashMenuElement.remove(); slashStatusElement.remove(); linePlusElement.remove(); slashTablePanelElement?.remove(); slashRuntime.provider = null; slashRuntime.view = null; } };
      },
    });
  });
}

editorBuilder = editorBuilder
  .use(weiBeiDialectPlugin)
  .use(commonmark)
  .use(gfm)
  .use(structuredMarkdown)
  .use(weiBeiMath)
  .use(streaming)
  .use($prose(() => streamingAppearancePlugin(() => streamingMarkdownBuffer)));

if (WEIBEI_EDITOR_RUNTIME) {
  editorBuilder = editorBuilder
    .use($prose(() => createSyntaxMarksPlugin({
      isEditable: () => isEditable,
      isStreaming: () => streamingMarkdownBuffer !== null,
      mathLanding: () => mathTypedLandingPosition,
      clearMathLanding: () => { mathTypedLandingPosition = null; },
    })))
    .use($prose(() => columnResizing()))
    .use(weiBeiSlash)
    .use(history)
    .use(clipboard)
    .use(upload);
}

editorBuilder
  .use(listener)
  .config((ctx) => {
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
    document.addEventListener('mouseup', reportSelection);
    document.addEventListener('pointerdown', () => {
      if (window.weiBeiSuppressSelectionReport) return;
      lastSelectionRange = null;
      lastSelectionReport.text = '';
      lastSelectionReport.rectKey = '';
      post('selectionChanged', { text: '', rect: null });
    }, true);
    document.addEventListener('click', (event) => {
      if (isEditable && event.target instanceof Element && event.target.closest('.weibei-structured-node')) return;
      if (!activateSelectionRemarkMark(event.target)
          && !activateSelectionAskMark(event.target)
          && !activateWikiLink(event.target)
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
    post('editorReady', {});
    window.setTimeout(() => {
      editorReadyPosted = true;
      installContentHeightObserver();
      editor.action((ctx) => reportOutline(ctx.get(editorViewCtx).state.doc));
      reportActiveHeading();
    });
  })
  .catch(showFailure);
