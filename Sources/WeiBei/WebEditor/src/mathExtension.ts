import { Fragment } from '@milkdown/kit/prose/model';
import { InputRule } from '@milkdown/kit/prose/inputrules';
import { $inputRule, $nodeSchema, $remark } from '@milkdown/kit/utils';
import remarkMath from 'remark-math';

declare const WEIBEI_EDITOR_RUNTIME: boolean;

export const remarkMathPlugin = $remark('weiBeiRemarkMath', () => remarkMath);

export const mathInlineSchema = $nodeSchema('math_inline', () => ({
  group: 'inline', content: 'text*', inline: true, atom: true,
  parseDOM: [{
    tag: 'span[data-type="math_inline"]',
    getContent: (element: Node, schema: any) => Fragment.from(schema.text((element as HTMLElement).dataset.value || '')),
  }],
  toDOM: (node: any) => ['span', { 'data-type': 'math_inline', 'data-value': node.textContent }, node.textContent],
  parseMarkdown: { match: (node: any) => node.type === 'inlineMath', runner: (state: any, node: any, type: any) => state.openNode(type).addText(node.value).closeNode() },
  toMarkdown: { match: (node: any) => node.type.name === 'math_inline', runner: (state: any, node: any) => state.addNode('inlineMath', undefined, node.textContent) },
}));

export const mathBlockSchema = $nodeSchema('math_block', () => ({
  content: 'text*', group: 'block', marks: '', defining: true, atom: true, isolating: true,
  attrs: { value: { default: '' } },
  parseDOM: [{ tag: 'div[data-type="math_block"]', preserveWhitespace: 'full', getAttrs: (element: HTMLElement) => ({ value: element.dataset.value || '' }) }],
  toDOM: (node: any) => ['div', { 'data-type': 'math_block', 'data-value': node.attrs.value }, node.attrs.value],
  parseMarkdown: { match: (node: any) => node.type === 'math', runner: (state: any, node: any, type: any) => state.addNode(type, { value: node.value }) },
  toMarkdown: { match: (node: any) => node.type.name === 'math_block', runner: (state: any, node: any) => state.addNode('math', undefined, node.attrs.value) },
}));

export const mathBlockInputRule = WEIBEI_EDITOR_RUNTIME ? $inputRule((ctx) => new InputRule(/^\$\$\s$/, (state, _match, start, end) => {
  const $start = state.doc.resolve(start);
  return $start.node(-1).canReplaceWith($start.index(-1), $start.indexAfter(-1), mathBlockSchema.type(ctx))
    ? state.tr.delete(start, end).setBlockType(start, start, mathBlockSchema.type(ctx))
    : null;
})) : null as any;
