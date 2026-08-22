import { Plugin, PluginKey } from '@milkdown/kit/prose/state';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';
import { findPendingSyntaxMarkers } from './syntax-scanner';

const syntaxMarksKey = new PluginKey('weibeiSyntaxMarks');

const revealMarkCandidates: Array<{ typeNames: string[]; marker: string }> = [
  { typeNames: ['strong'], marker: '**' },
  { typeNames: ['emphasis'], marker: '*' },
  { typeNames: ['code'], marker: '`' },
  { typeNames: ['highlight'], marker: '==' },
  { typeNames: ['strike', 'strikethrough', 'strikeThrough'], marker: '~~' },
];

const isCodeContext = (state: any) => {
  const { $from } = state.selection;
  if ($from.parent.type.spec.code) return true;
  for (let depth = $from.depth; depth >= 0; depth -= 1) {
    if ($from.node(depth).type.name === 'code_block') return true;
  }
  return false;
};

const markMarkerFor = (schemaMarks: any, markType: any, cache: Map<string, string>) => {
  const typeName = markType.name;
  const cached = cache.get(typeName);
  if (cached !== undefined) return cached;
  const candidate = revealMarkCandidates.find((entry) => entry.typeNames.includes(typeName));
  const marker = candidate && schemaMarks[typeName] ? candidate.marker : '';
  cache.set(typeName, marker);
  return marker;
};

/** Contiguous doc range of `markType` around the position, bounded by the textblock. */
const markRunAround = (doc: any, pos: number, markType: any) => {
  const resolved = doc.resolve(pos);
  const parent = resolved.parent;
  const offset = resolved.parentOffset;
  const runs: Array<{ from: number; to: number }> = [];
  parent.forEach((child: any, childOffset: number) => {
    if (child.isText && markType.isInSet(child.marks || [])) {
      runs.push({ from: childOffset, to: childOffset + child.nodeSize });
    }
  });
  const seed = runs.find((run) => run.from <= offset && offset <= run.to);
  if (!seed) return null;
  let from = seed.from;
  let to = seed.to;
  let grew = true;
  while (grew) {
    grew = false;
    for (const run of runs) {
      if (run.from === to) {
        to = run.to;
        grew = true;
      } else if (run.to === from) {
        from = run.from;
        grew = true;
      }
    }
  }
  const blockStart = resolved.start(resolved.depth);
  return { from: blockStart + from, to: blockStart + to };
};

const createMarkerWidget = (marker: string) => () => {
  const element = document.createElement('span');
  element.className = 'weibei-syntax-mark';
  element.setAttribute('aria-hidden', 'true');
  element.textContent = marker;
  return element;
};

const closestAncestorOfName = (resolved: any, typeName: string) => {
  for (let depth = resolved.depth; depth > 0; depth -= 1) {
    if (resolved.node(depth).type.name === typeName) return { depth, node: resolved.node(depth) };
  }
  return null;
};

const adjacentMathDom = (view: any): HTMLElement | null => {
  const { $from, $to } = view.state.selection;
  const before = $from.nodeBefore;
  if (before && before.type.name === 'math_inline') {
    const dom = view.nodeDOM($from.pos - before.nodeSize) as HTMLElement | null;
    if (dom instanceof HTMLElement) return dom;
  }
  const after = $to.nodeAfter;
  if (after && after.type.name === 'math_inline') {
    const dom = view.nodeDOM($to.pos) as HTMLElement | null;
    if (dom instanceof HTMLElement) return dom;
  }
  return null;
};

export interface SyntaxMarksDeps {
  isEditable: () => boolean;
  isStreaming: () => boolean;
}

interface SyntaxMarksCache {
  doc: any;
  from: number;
  to: number;
  set: DecorationSet;
}

/**
 * Typora-style syntax affordances over the WYSIWYG document: half-typed
 * markers (`**`, `$`, leading `#`…) tint while their closer is still missing,
 * and rendered runs reveal their source markers faintly while the cursor is
 * inside. Purely decorative — widgets carry no document content.
 */
export const createSyntaxMarksPlugin = (deps: SyntaxMarksDeps): Plugin => {
  const markerCache = new Map<string, string>();
  let cache: SyntaxMarksCache | null = null;
  let adjacentDom: HTMLElement | null = null;

  const clearAdjacent = () => {
    adjacentDom?.classList.remove('weibei-math-adjacent');
    adjacentDom = null;
  };

  return new Plugin({
    key: syntaxMarksKey,
    view: () => ({
      update(view: any) {
        const next = adjacentMathDom(view);
        if (next === adjacentDom) return;
        clearAdjacent();
        adjacentDom = next;
        adjacentDom?.classList.add('weibei-math-adjacent');
      },
      destroy() {
        clearAdjacent();
      },
    }),
    props: {
      decorations(state: any) {
        if (!deps.isEditable() || deps.isStreaming() || isCodeContext(state)) {
          cache = null;
          clearAdjacent();
          return DecorationSet.empty;
        }
        const { doc, selection } = state;
        const from = selection.from;
        const to = selection.to;
        if (cache && cache.doc === doc && cache.from === from && cache.to === to) {
          return cache.set;
        }
        const decorations: Decoration[] = [];
        const block = selection.$from.parent;
        const blockStart = selection.$from.start(selection.$from.depth);
        for (const range of findPendingSyntaxMarkers(block.textBetween(0, block.content.size, '\n', '\n'))) {
          decorations.push(Decoration.inline(
            blockStart + range.from,
            blockStart + range.to,
            { class: 'weibei-syntax-pending' },
          ));
        }
        const schemaMarks = doc.type.schema.marks;
        for (const mark of selection.$from.marks() || []) {
          const marker = markMarkerFor(schemaMarks, mark.type, markerCache);
          if (!marker) continue;
          const run = markRunAround(doc, from, mark.type);
          if (!run) continue;
          decorations.push(Decoration.widget(run.from, createMarkerWidget(marker), { side: -1 }));
          decorations.push(Decoration.widget(run.to, createMarkerWidget(marker), { side: 1 }));
        }
        const heading = closestAncestorOfName(selection.$from, 'heading');
        if (heading) {
          decorations.push(Decoration.widget(
            selection.$from.before(heading.depth) + 1,
            createMarkerWidget('#'.repeat(heading.node.attrs.level || 1)),
            { side: -1 },
          ));
        }
        const quote = closestAncestorOfName(selection.$from, 'blockquote');
        if (quote) {
          decorations.push(Decoration.widget(
            selection.$from.before(selection.$from.depth) + 1,
            createMarkerWidget('>'),
            { side: -1 },
          ));
        }
        const set = DecorationSet.create(doc, decorations);
        cache = { doc, from, to, set };
        return set;
      },
    },
  });
};
