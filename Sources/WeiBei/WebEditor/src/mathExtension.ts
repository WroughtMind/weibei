import { Fragment } from '@milkdown/kit/prose/model';
import { InputRule } from '@milkdown/kit/prose/inputrules';
import { $inputRule, $nodeSchema, $remark } from '@milkdown/kit/utils';
import { Plugin, PluginKey, Selection, TextSelection } from '@milkdown/kit/prose/state';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';
import { findCompleteInlineMathSpans } from './syntax-scanner';
import remarkMath from 'remark-math';

declare const WEIBEI_EDITOR_RUNTIME: boolean;

export const remarkMathPlugin = $remark('weiBeiRemarkMath', () => remarkMath);

export const mathInlineSchema = $nodeSchema('math_inline', () => ({
  group: 'inline', content: 'text*', inline: true, marks: '', code: true,
  parseDOM: [{
    tag: 'span[data-type="math_inline"]',
    getContent: (element: Node, schema: any) => (element as HTMLElement).dataset.value ? Fragment.from(schema.text((element as HTMLElement).dataset.value)) : Fragment.empty,
  }],
  toDOM: (node: any) => ['span', { 'data-type': 'math_inline', 'data-value': node.textContent }, node.textContent],
  parseMarkdown: { match: (node: any) => node.type === 'inlineMath', runner: (state: any, node: any, type: any) => state.openNode(type).addText(node.value).closeNode() },
  toMarkdown: { match: (node: any) => node.type.name === 'math_inline', runner: (state: any, node: any) => state.addNode('inlineMath', undefined, node.textContent) },
}));

export const mathBlockSchema = $nodeSchema('math_block', () => ({
  content: 'text*', group: 'block', marks: '', defining: true, code: true,
  parseDOM: [{ tag: 'div[data-type="math_block"]', preserveWhitespace: 'full', getContent: (element: Node, schema: any) => (element as HTMLElement).dataset.value ? Fragment.from(schema.text((element as HTMLElement).dataset.value)) : Fragment.empty }],
  toDOM: (node: any) => ['div', { 'data-type': 'math_block', 'data-value': node.textContent }, node.textContent],
  parseMarkdown: { match: (node: any) => node.type === 'math', runner: (state: any, node: any, type: any) => state.openNode(type).addText(node.value).closeNode() },
  toMarkdown: { match: (node: any) => node.type.name === 'math_block', runner: (state: any, node: any) => state.addNode('math', undefined, node.textContent) },
}));

export const mathBlockInputRule = WEIBEI_EDITOR_RUNTIME ? $inputRule((ctx) => new InputRule(/^\$\$\s$/, (state, _match, start, end) => {
  const $start = state.doc.resolve(start);
  return $start.node(-1).canReplaceWith($start.index(-1), $start.indexAfter(-1), mathBlockSchema.type(ctx))
    ? state.tr.delete(start, end).setBlockType(start, start, mathBlockSchema.type(ctx))
    : null;
})) : null as any;

const mathEditingKey = new PluginKey('weibeiMathEditing');

/** Math source is ordinary editor content: selection alone chooses source or preview. */
export const createMathEditingPlugin = (isEditable: () => boolean) => new Plugin({
  key: mathEditingKey,
  appendTransaction(transactions, _oldState, state) {
    if (!isEditable() || !transactions.some((tr) => tr.docChanged) || transactions.some((tr) => tr.getMeta(mathEditingKey))) return null;
    const { selection } = state;
    const { $from } = selection;
    const block = $from.parent;
    if (!block.isTextblock || block.type.spec.code) return null;
    // A complete double-dollar paragraph becomes editable block math.
    const text = block.textBetween(0, block.content.size, '\n', '\ufffc');
    if (block.type.name === 'paragraph' && /^\$\$[\s\S]+\$\$$/.test(text)) {
      const value = text.slice(2, -2);
      const pos = $from.before();
      const tr = state.tr.replaceWith(pos, pos + block.nodeSize, state.schema.nodes.math_block.create(null, state.schema.text(value)));
      const offset = Math.max(0, Math.min(value.length, $from.parentOffset - 2));
      tr.setSelection(TextSelection.create(tr.doc, pos + 1 + offset));
      return tr.setMeta(mathEditingKey, true);
    }
    const spans: Array<{ from: number; to: number; source: string }> = [];
    block.forEach((child, offset) => {
      if (child.isText) spans.push(...findCompleteInlineMathSpans(child.text!).map((span) => ({ ...span, from: offset + span.from, to: offset + span.to })));
    });
    if (!spans.length) return null;
    const tr = state.tr;
    for (const span of spans.reverse()) {
      const from = $from.start() + span.from;
      tr.replaceWith(from, $from.start() + span.to, state.schema.nodes.math_inline.create(null, state.schema.text(span.source)));
    }
    // $source$ and the inline node have equal sizes, so the caret stays at the same text offset.
    tr.setSelection(TextSelection.create(tr.doc, selection.from, selection.to));
    return tr.setMeta(mathEditingKey, true);
  },
  props: {
    decorations(state) {
      if (!isEditable()) return null;
      const { $from } = state.selection;
      if (!['math_inline', 'math_block'].includes($from.parent.type.name)) return null;
      return DecorationSet.create(state.doc, [Decoration.node($from.before(), $from.after(), { class: 'weibei-math-editing' })]);
    },
    handleKeyDown(view, event) {
      if (!isEditable() || event.isComposing || event.keyCode === 229) return false;
      const { state } = view;
      const { $from, empty } = state.selection;
      const parent = $from.parent;
      if (parent.type.name === 'paragraph' && empty && parent.textContent === '$$' && event.key === 'Enter') {
        const pos = $from.before();
        const tr = state.tr.replaceWith(pos, $from.after(), state.schema.nodes.math_block.create());
        view.dispatch(tr.setSelection(TextSelection.create(tr.doc, pos + 1)).scrollIntoView());
        return true;
      }
      if (!empty || !['math_inline', 'math_block'].includes(parent.type.name)) return false;
      const inline = parent.type.name === 'math_inline';
      const left = (event.key === 'ArrowLeft' && $from.parentOffset === 0) || (inline && event.key === 'ArrowUp');
      const right = event.key === 'ArrowRight' && $from.parentOffset === parent.content.size;
      const leave = event.key === 'Escape' || (inline && event.key === 'ArrowDown') || (event.key === 'Enter' && (inline || event.metaKey || event.ctrlKey));
      if (!left && !right && !leave) return false;
      const tr = state.tr;
      const pos = left ? $from.before() : $from.after();
      if (!inline && pos === tr.doc.content.size) tr.insert(pos, state.schema.nodes.paragraph.create());
      tr.setSelection(Selection.near(tr.doc.resolve(pos), left ? -1 : 1));
      view.dispatch(tr.scrollIntoView());
      return true;
    },
  },
});
