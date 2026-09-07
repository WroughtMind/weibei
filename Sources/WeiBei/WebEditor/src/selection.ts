/** The selection's focus is the drag endpoint, even when its DOM range runs backwards. */
export const selectionEndpointRect = (selection: Selection | null) => {
  if (!selection || selection.isCollapsed || !selection.rangeCount || !selection.focusNode) return null;
  const range = selection.getRangeAt(0);
  const prefersAbove = range.startContainer === selection.focusNode && range.startOffset === selection.focusOffset;
  const endpoint = range.cloneRange();
  endpoint.collapse(prefersAbove);
  let rect = endpoint.getBoundingClientRect();
  if (!rect.height) {
    const rects = Array.from(range.getClientRects()).filter(rect => rect.height > 0 && rect.width > 0);
    const edge = prefersAbove ? rects[0] : rects.at(-1);
    if (!edge) return null;
    rect = edge;
  }
  return {
    x: prefersAbove ? rect.left : rect.right,
    y: prefersAbove ? rect.top : rect.bottom,
    width: rect.width,
    height: rect.height,
    prefersAbove,
  };
};

export type SelectionTextAnchor = { startOffset: number; endOffset: number };
export type SelectionMark = { id: string; text: string; anchor?: SelectionTextAnchor; active?: boolean; reveal?: string };
export type SelectionTextIndex<T> = { text: string; points: T[] };

/** Whitespace has no stable layout across PDF/HTML/Markdown; anchors count visible characters. */
export const indexSelectionText = <T>(runs: Array<{ text: string; point: (offset: number) => T }>): SelectionTextIndex<T> => {
  const characters: string[] = [];
  const points: T[] = [];
  for (const run of runs) {
    for (let offset = 0; offset < run.text.length; offset += 1) {
      const character = run.text[offset];
      if (/[\s\u200b]/.test(character)) continue;
      characters.push(character);
      points.push(run.point(offset));
    }
  }
  return { text: characters.join(''), points };
};

export const selectionMarkRange = (text: string, mark: SelectionMark): SelectionTextAnchor | null => {
  const needle = mark.text.replace(/[\s\u200b]+/g, '');
  if (!needle) return null;
  const anchor = mark.anchor;
  if (anchor && Number.isInteger(anchor.startOffset) && Number.isInteger(anchor.endOffset)
      && anchor.startOffset >= 0 && anchor.endOffset > anchor.startOffset
      && text.slice(anchor.startOffset, anchor.endOffset) === needle) return anchor;
  const startOffset = text.indexOf(needle);
  // Relocate after an external edit only when the original passage is unambiguous.
  if (startOffset < 0 || text.indexOf(needle, startOffset + 1) >= 0) return null;
  return { startOffset, endOffset: startOffset + needle.length };
};

export const indexDOMSelectionText = (root: Node) => {
  const runs: Array<{ text: string; point: (offset: number) => { node: Text; offset: number } }> = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: node => node.parentElement?.closest('script, style, [data-weibei-annotation-ui]')
      ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
  });
  while (walker.nextNode()) {
    const node = walker.currentNode as Text;
    runs.push({ text: node.data, point: offset => ({ node, offset }) });
  }
  return indexSelectionText(runs);
};

export const domSelectionTextAnchor = (selection: Selection | null, root: Node) => {
  if (!selection?.rangeCount || selection.isCollapsed) return null;
  const range = selection.getRangeAt(0);
  const index = indexDOMSelectionText(root);
  const startOffset = index.points.findIndex(point => range.comparePoint(point.node, point.offset) === 0);
  if (startOffset < 0) return null;
  let endOffset = startOffset;
  while (endOffset < index.points.length) {
    const point = index.points[endOffset];
    if (range.comparePoint(point.node, point.offset + 1) !== 0) break;
    endOffset += 1;
  }
  return endOffset > startOffset ? { startOffset, endOffset } : null;
};

let lastRevealRequest = '';
export const revealSelectionMarks = (root: ParentNode, marks: SelectionMark[]) => {
  const mark = marks.find(mark => mark.reveal && mark.reveal !== lastRevealRequest);
  if (!mark) return;
  const element = Array.from(root.querySelectorAll('.weibei-remark-mark[data-record-id]'))
    .find(element => element.getAttribute('data-record-id') === mark.id);
  if (!element) return;
  element.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
  lastRevealRequest = mark.reveal!;
};

export const applyDOMSelectionMarks = (root: HTMLElement, marks: SelectionMark[], className: string, idAttribute: string) => {
  const selection = window.getSelection();
  const selected = selection?.anchorNode && selection.focusNode
    && root.contains(selection.anchorNode) && root.contains(selection.focusNode)
    ? domSelectionTextAnchor(selection, root) : null;
  const backwards = selected && selection?.focusNode === selection?.getRangeAt(0).startContainer
    && selection?.focusOffset === selection?.getRangeAt(0).startOffset;
  root.querySelectorAll(`.${className}`).forEach(element => {
    const parent = element.parentNode;
    if (!parent) return;
    element.replaceWith(...Array.from(element.childNodes));
    parent.normalize();
  });
  for (const mark of Array.isArray(marks) ? marks : []) {
    if (!mark?.id || typeof mark.text !== 'string') continue;
    const index = indexDOMSelectionText(root);
    const range = selectionMarkRange(index.text, mark);
    if (!range) continue;
    const portions = new Map<Text, { from: number; to: number }>();
    for (const point of index.points.slice(range.startOffset, range.endOffset)) {
      const portion = portions.get(point.node);
      portions.set(point.node, { from: portion?.from ?? point.offset, to: point.offset + 1 });
    }
    let last = true;
    for (const [node, portion] of Array.from(portions).reverse()) {
      const fragment = document.createRange();
      fragment.setStart(node, portion.from);
      fragment.setEnd(node, portion.to);
      const span = document.createElement('span');
      span.className = className;
      if (mark.active && className === 'weibei-remark-mark') span.classList.add('weibei-remark-active');
      if (last && className === 'weibei-remark-mark') span.classList.add('weibei-remark-end');
      span.setAttribute(idAttribute, mark.id);
      fragment.surroundContents(span);
      last = false;
    }
  }
  // Rewrapping marks moves text nodes; restore the reader's live selection by its stable text offsets.
  if (selected && selection) {
    const points = indexDOMSelectionText(root).points;
    const first = points[selected.startOffset], last = points[selected.endOffset - 1];
    if (first && last) selection.setBaseAndExtent(
      backwards ? last.node : first.node, backwards ? last.offset + 1 : first.offset,
      backwards ? first.node : last.node, backwards ? first.offset : last.offset + 1);
  }
  if (className === 'weibei-remark-mark') revealSelectionMarks(root, marks);
};
