import { Plugin, PluginKey } from '@milkdown/kit/prose/state';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';
import { findPendingSyntaxMarkers, PendingSyntaxKind } from './syntax-scanner';

const syntaxMarksKey = new PluginKey('weibeiSyntaxMarks');

const revealMarkCandidates: Array<{ typeNames: string[]; marker: string; kind: PendingSyntaxKind }> = [
  { typeNames: ['strong'], marker: '**', kind: 'bold' },
  { typeNames: ['emphasis'], marker: '*', kind: 'italic' },
  { typeNames: ['code'], marker: '`', kind: 'code' },
  { typeNames: ['highlight'], marker: '==', kind: 'highlight' },
  { typeNames: ['strike', 'strike_through', 'strikethrough', 'strikeThrough'], marker: '~~', kind: 'strike' },
];

const isCodeContext = (state: any) => {
  const { $from } = state.selection;
  if ($from.parent.type.spec.code) return true;
  for (let depth = $from.depth; depth >= 0; depth -= 1) {
    if ($from.node(depth).type.name === 'code_block') return true;
  }
  return false;
};

const markCandidateFor = (schemaMarks: any, markType: any, cache: Map<string, any>) => {
  const typeName = markType.name;
  if (!cache.has(typeName)) {
    const candidate = revealMarkCandidates.find((entry) => entry.typeNames.includes(typeName));
    cache.set(typeName, candidate && schemaMarks[typeName] ? candidate : null);
  }
  return cache.get(typeName);
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

/**
 * Reveal markers ride on real text positions via CSS ::before/::after so no
 * synthetic cursor positions are introduced — widgets at run boundaries were
 * blocking arrow-key motion out of the run. The per-kind color travels as a
 * custom property so one CSS rule serves every syntax type.
 */
const markerDecoration = (from: number, to: number, marker: string, kind: PendingSyntaxKind, edge: 'open' | 'close') =>
  Decoration.inline(from, to, {
    class: `weibei-syntax-mark weibei-syntax-mark-${edge}`,
    'data-marker': marker,
    style: `--weibei-marker-color: var(--weibei-syntax-${kind})`,
  });

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
  /**
   * Position where the inline-math input rule just landed the caret. Real
   * WebKit typing fires extra normalization updates after the input
   * transaction, so the adjacent-source peek must stay suppressed while the
   * caret RESTS on the landing (cleared once it moves away).
   */
  mathLanding: () => number | null;
  clearMathLanding: () => void;
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
  const candidateCache = new Map<string, any>();
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
        const landing = deps.mathLanding();
        if (landing !== null) {
          if (view.state.selection.from === landing) {
            clearAdjacent();
            return;
          }
          deps.clearMathLanding();
        }
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
            { class: `weibei-syntax-pending weibei-syntax-k-${range.kind}` },
          ));
        }
        const schemaMarks = doc.type.schema.marks;
        // Reveal not only when the caret carries the mark, but also when it sits
        // immediately beside a marked run — adjacency is the natural "I want to
        // edit around here" state.
        const candidateTypes: any[] = [];
        const seenTypes = new Set<string>();
        const collectType = (mark: any) => {
          if (!mark || seenTypes.has(mark.type.name)) return;
          if (!markCandidateFor(schemaMarks, mark.type, candidateCache)) return;
          seenTypes.add(mark.type.name);
          candidateTypes.push(mark.type);
        };
        for (const mark of selection.$from.marks() || []) collectType(mark);
        for (const mark of selection.$from.nodeBefore?.marks || []) collectType(mark);
        for (const mark of selection.$to.nodeAfter?.marks || []) collectType(mark);
        for (const markType of candidateTypes) {
          const candidate = markCandidateFor(schemaMarks, markType, candidateCache);
          let run = markRunAround(doc, from, markType);
          if (!run && selection.$to.parent === selection.$from.parent) {
            run = markRunAround(doc, selection.to, markType);
          }
          if (!run || run.to <= run.from) continue;
          // Boundary positions show only the marker on the caret's side, so it
          // reads as "at the edge" rather than "still trapped inside".
          const rel = selection.$from.parentOffset;
          const relFrom = run.from - blockStart;
          const relTo = run.to - blockStart;
          if (rel < relTo) {
            decorations.push(markerDecoration(run.from, Math.min(run.from + 1, run.to), candidate.marker, candidate.kind, 'open'));
          }
          if (rel > relFrom) {
            decorations.push(markerDecoration(Math.max(run.to - 1, run.from), run.to, candidate.marker, candidate.kind, 'close'));
          }
        }
        const nodeMarkerDecoration = (nodePos: number, nodeSize: number, marker: string, kind: PendingSyntaxKind) =>
          Decoration.node(nodePos, nodePos + nodeSize, {
            class: 'weibei-syntax-mark weibei-syntax-mark-node',
            'data-marker': marker,
            style: `--weibei-marker-color: var(--weibei-syntax-${kind})`,
          });
        const heading = closestAncestorOfName(selection.$from, 'heading');
        if (heading) {
          decorations.push(nodeMarkerDecoration(
            selection.$from.before(heading.depth),
            heading.node.nodeSize,
            '#'.repeat(heading.node.attrs.level || 1),
            'heading',
          ));
        }
        if (closestAncestorOfName(selection.$from, 'blockquote')) {
          decorations.push(nodeMarkerDecoration(
            selection.$from.before(selection.$from.depth),
            selection.$from.parent.nodeSize,
            '>',
            'quote',
          ));
        }
        const set = DecorationSet.create(doc, decorations);
        cache = { doc, from, to, set };
        return set;
      },
    },
  });
};
