import { markRule, nodeRule } from '@milkdown/kit/prose';
import { $inputRule, $markSchema, $nodeSchema, $remark } from '@milkdown/kit/utils';
import {
  parseCalloutHeader,
  parseStructuredInline,
  serializeCalloutHeader,
  type StructuredInlineToken,
} from './structuredMarkdownRules';

type MarkdownNode = {
  type: string;
  value?: string;
  children?: MarkdownNode[];
  [key: string]: unknown;
};

const writingFonts = new Set(['system', 'serif', 'literary']);

const groupWritingFontSpans = (children: MarkdownNode[]) => {
  const grouped: MarkdownNode[] = [];
  for (let index = 0; index < children.length; index += 1) {
    const child = children[index];
    const match = child.type === 'html'
      ? String(child.value || '').match(/^<span data-weibei-font="(system|serif|literary)">$/)
      : null;
    if (!match) {
      grouped.push(child);
      continue;
    }
    const close = children.findIndex((candidate, candidateIndex) => candidateIndex > index
      && candidate.type === 'html'
      && String(candidate.value || '') === '</span>');
    if (close < 0) {
      grouped.push(child);
      continue;
    }
    grouped.push({ type: 'writingFont', font: match[1], children: children.slice(index + 1, close) });
    index = close;
  }
  return grouped;
};

const inlineTokenToMarkdownNode = (token: StructuredInlineToken): MarkdownNode => {
  if (token.type === 'text') return { type: 'text', value: token.value };
  if (token.type === 'highlight') return { type: 'highlight', children: [{ type: 'text', value: token.value }] };
  if (token.type === 'inlineFootnote') return { type: 'inlineFootnote', value: token.value };
  return { type: token.type, raw: token.raw, target: token.target, label: token.label };
};

const transformDialectTree = (node: MarkdownNode) => {
  if (!node.children || ['code', 'inlineCode', 'html'].includes(node.type)) return;
  if (node.type === 'blockquote') {
    const first = node.children[0];
    const firstText = first?.type === 'paragraph' && first.children?.length === 1 && first.children[0].type === 'text'
      ? String(first.children[0].value || '')
      : '';
    const match = parseCalloutHeader(firstText);
    if (match) {
      node.type = 'callout';
      node.calloutType = match.calloutType;
      node.fold = match.fold;
      node.title = match.title;
      node.children = node.children.slice(1);
      if (node.children.length === 0) node.children.push({ type: 'paragraph', children: [] });
      const firstBodyText = node.children[0]?.type === 'paragraph' ? node.children[0].children?.[0] : null;
      if (firstBodyText?.type === 'text') {
        firstBodyText.value = String(firstBodyText.value || '').replace(/^\[![A-Za-z][A-Za-z0-9_-]*\][+-]?[ \t]*/, '');
      }
    }
  }
  const children = node.children.flatMap((child) => {
    if (child.type !== 'text') {
      transformDialectTree(child);
      return [child];
    }
    return parseStructuredInline(String(child.value || '')).map(inlineTokenToMarkdownNode);
  });
  node.children = groupWritingFontSpans(children);
};

const structuredRemark = $remark('weiBeiStructuredMarkdown', () => (function weiBeiStructuredMarkdown(this: any) {
  const data = this.data();
  const extensions = data.toMarkdownExtensions || (data.toMarkdownExtensions = []);
  extensions.push({
    handlers: {
      wikiLink: (node: any, _parent: any, state: any, info: any) => `[[${state.safe(node.raw, { ...info, before: '[[', after: ']]' })}]]`,
      embed: (node: any, _parent: any, state: any, info: any) => `![[${state.safe(node.raw, { ...info, before: '![[', after: ']]' })}]]`,
      inlineFootnote: (node: any, _parent: any, state: any, info: any) => `^[${state.safe(node.value, { ...info, before: '^[', after: ']' })}]`,
      highlight: (node: any, _parent: any, state: any, info: any) => {
        const value = state.containerPhrasing(node, { ...info, before: '==', after: '==' });
        return `==${value}==`;
      },
      writingFont: (node: any, _parent: any, state: any, info: any) => {
        const font = writingFonts.has(node.font) ? node.font : 'serif';
        const value = state.containerPhrasing(node, { ...info, before: '>', after: '<' });
        return `<span data-weibei-font="${font}">${value}</span>`;
      },
      callout: (node: any, _parent: any, state: any, info: any) => {
        const header = serializeCalloutHeader({ calloutType: node.calloutType, fold: node.fold || '', title: node.title || '' });
        const blockquote = {
          type: 'blockquote',
          children: [{ type: 'paragraph', children: [{ type: 'text', value: header }] }, ...(node.children || [])],
        };
        const exit = state.enter('blockquote');
        const tracker = state.createTracker(info);
        tracker.move('> ');
        tracker.shift(2);
        const value = state.indentLines(state.containerFlow(blockquote, tracker.current()), (line: string, _index: number, blank: boolean) => `>${blank ? '' : ' '}${line}`);
        exit();
        return value;
      },
    },
  });
  return (tree: MarkdownNode) => transformDialectTree(tree);
}) as any);

export const wikiLinkSchema = $nodeSchema('wiki_link', () => ({
  group: 'inline', inline: true, atom: true, selectable: true,
  attrs: { raw: { default: '' }, target: { default: '' }, label: { default: '' } },
  parseDOM: [{ tag: 'span[data-type="wiki_link"]', getAttrs: (dom) => dom instanceof HTMLElement ? ({ raw: dom.dataset.raw || '', target: dom.dataset.target || '', label: dom.dataset.label || '' }) : false }],
  toDOM: (node) => ['span', { 'data-type': 'wiki_link', 'data-raw': node.attrs.raw, 'data-target': node.attrs.target, 'data-label': node.attrs.label, class: 'weibei-wikilink weibei-structured-node' }, node.attrs.label || node.attrs.target],
  parseMarkdown: { match: (node) => node.type === 'wikiLink', runner: (state, node, type) => { state.addNode(type, { raw: node.raw, target: node.target, label: node.label }); } },
  toMarkdown: { match: (node) => node.type.name === 'wiki_link', runner: (state, node) => state.addNode('wikiLink', undefined, undefined, node.attrs) },
}));

export const embedSchema = $nodeSchema('embed', () => ({
  group: 'inline', inline: true, atom: true, selectable: true,
  attrs: { raw: { default: '' }, target: { default: '' }, label: { default: '' } },
  parseDOM: [{ tag: 'span[data-type="embed"]', getAttrs: (dom) => dom instanceof HTMLElement ? ({ raw: dom.dataset.raw || '', target: dom.dataset.target || '', label: dom.dataset.label || '' }) : false }],
  toDOM: (node) => ['span', { 'data-type': 'embed', 'data-raw': node.attrs.raw, 'data-target': node.attrs.target, 'data-label': node.attrs.label, class: 'weibei-embed-note weibei-structured-node' }, node.attrs.label || node.attrs.target],
  parseMarkdown: { match: (node) => node.type === 'embed', runner: (state, node, type) => state.addNode(type, { raw: node.raw, target: node.target, label: node.label }) },
  toMarkdown: { match: (node) => node.type.name === 'embed', runner: (state, node) => state.addNode('embed', undefined, undefined, node.attrs) },
}));

export const inlineFootnoteSchema = $nodeSchema('inline_footnote', () => ({
  group: 'inline', inline: true, atom: true, selectable: true,
  attrs: { value: { default: '' } },
  parseDOM: [{ tag: 'span[data-type="inline_footnote"]', getAttrs: (dom) => dom instanceof HTMLElement ? ({ value: dom.dataset.value || '' }) : false }],
  toDOM: (node) => ['span', { 'data-type': 'inline_footnote', 'data-value': node.attrs.value, class: 'weibei-inline-footnote weibei-structured-node' }, node.attrs.value],
  parseMarkdown: { match: (node) => node.type === 'inlineFootnote', runner: (state, node, type) => state.addNode(type, { value: node.value }) },
  toMarkdown: { match: (node) => node.type.name === 'inline_footnote', runner: (state, node) => state.addNode('inlineFootnote', undefined, undefined, { value: node.attrs.value }) },
}));

export const embedInputRule = $inputRule((ctx) => nodeRule(
  /!\[\[([^\]\n]+)\]\]$/,
  embedSchema.type(ctx),
  { getAttr: (match) => {
    const raw = match[1] || '';
    const [target = '', ...label] = raw.split('|');
    return { raw, target: target.trim(), label: label.join('|').trim() };
  } },
));

export const wikiLinkInputRule = $inputRule((ctx) => nodeRule(
  /(?<!!)\[\[([^\]\n]+)\]\]$/,
  wikiLinkSchema.type(ctx),
  { getAttr: (match) => {
    const raw = match[1] || '';
    const [target = '', ...label] = raw.split('|');
    return { raw, target: target.trim(), label: label.join('|').trim() };
  } },
));

export const inlineFootnoteInputRule = $inputRule((ctx) => nodeRule(
  /\^\[([^\]\n]+)\]$/,
  inlineFootnoteSchema.type(ctx),
  { getAttr: (match) => ({ value: match[1] || '' }) },
));

export const highlightSchema = $markSchema('highlight', () => ({
  parseDOM: [{ tag: 'mark.weibei-highlight' }],
  toDOM: () => ['mark', { class: 'weibei-highlight' }, 0],
  parseMarkdown: { match: (node) => node.type === 'highlight', runner: (state, node, mark) => state.openMark(mark).next(node.children).closeMark(mark) },
  toMarkdown: { match: (mark) => mark.type.name === 'highlight', runner: (state, mark) => { state.withMark(mark, 'highlight'); } },
}));

export const writingFontSchema = $markSchema('writing_font', () => ({
  attrs: { font: { default: 'serif' } },
  excludes: 'writing_font',
  priority: 10,
  parseDOM: [{
    tag: 'span[data-weibei-font]',
    getAttrs: (dom) => {
      const font = dom instanceof HTMLElement ? dom.dataset.weibeiFont : '';
      return font && writingFonts.has(font) ? { font } : false;
    },
  }],
  toDOM: (mark) => {
    const font = writingFonts.has(mark.attrs.font) ? mark.attrs.font : 'serif';
    return ['span', { 'data-weibei-font': font }, 0];
  },
  parseMarkdown: {
    match: (node) => node.type === 'writingFont',
    runner: (state, node, mark) => state.openMark(mark, { font: node.font }).next(node.children).closeMark(mark),
  },
  toMarkdown: {
    match: (mark) => mark.type.name === 'writing_font',
    runner: (state, mark) => { state.withMark(mark, 'writingFont', undefined, { font: mark.attrs.font }); },
  },
}));

export const highlightInputRule = $inputRule((ctx) => markRule(
  /(?:^|[^\\=])==([^=\n]+)==$/,
  highlightSchema.type(ctx),
));

export const calloutSchema = $nodeSchema('callout', () => ({
  content: 'block+', group: 'block', defining: true, selectable: true,
  attrs: { calloutType: { default: 'note' }, title: { default: '' }, fold: { default: '' } },
  parseDOM: [{ tag: 'blockquote[data-type="callout"]', getAttrs: (dom) => dom instanceof HTMLElement ? ({ calloutType: dom.dataset.callout || 'note', title: dom.dataset.calloutTitle || '', fold: dom.dataset.calloutFold || '' }) : false }],
  toDOM: (node) => ['blockquote', { 'data-type': 'callout', 'data-callout': node.attrs.calloutType, 'data-callout-title': node.attrs.title, 'data-callout-fold': node.attrs.fold, class: `weibei-callout weibei-callout-${node.attrs.calloutType}` }, 0],
  parseMarkdown: { match: (node) => node.type === 'callout', runner: (state, node, type) => state.openNode(type, { calloutType: node.calloutType, title: node.title, fold: node.fold }).next(node.children).closeNode() },
  toMarkdown: { match: (node) => node.type.name === 'callout', runner: (state, node) => { state.openNode('callout', undefined, node.attrs).next(node.content).closeNode(); } },
}));

export const structuredMarkdown = [
  structuredRemark,
  wikiLinkSchema,
  embedSchema,
  inlineFootnoteSchema,
  writingFontSchema,
  highlightSchema,
  highlightInputRule,
  calloutSchema,
  embedInputRule,
  wikiLinkInputRule,
  inlineFootnoteInputRule,
].flat();
