import { Plugin, PluginKey } from '@milkdown/kit/prose/state';
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view';

const appearanceKey = new PluginKey('weibeiStreamingAppearance');

// Shared spec objects: unchanged ranges and the caret widget keep their DOM
// across ticks, so the fade-in animation never restarts mid-flight and the
// caret blink stays continuous.
const FADE_SPEC = { class: 'wb-stream-in' };
const CARET_SPEC = { side: 1 };

/** Match the CSS animation duration of .wb-stream-in in index.html. */
const FADE_MILLISECONDS = 200;
/** Retire the caret shortly after inserts stop flowing. */
const CARET_IDLE_MILLISECONDS = 400;
/** Only animate typing-like inserts; wholesale block rewrites skip the fade.
 * Raised with the faster reveal cadence so pacing chunks still fade. */
const MAXIMUM_FADE_CHARACTERS = 32;

interface FadeEntry {
  from: number;
  to: number;
  expiresAt: number;
}

interface AppearanceState {
  fades: FadeEntry[];
  caretPosition: number | null;
  caretExpiresAt: number;
  set: DecorationSet;
}

function createCaretElement(): HTMLElement {
  const element = document.createElement('span');
  element.className = 'wb-stream-caret';
  return element;
}

/**
 * Softens the streaming cadence visually: newly inserted characters fade in
 * and a quiet caret follows the flow, so evenly paced 30 Hz inserts read as a
 * continuous stream instead of discrete character pops. Purely decorative —
 * it adds no transactions and touches no document content.
 */
export function streamingAppearancePlugin(isStreamingActive: () => boolean): Plugin {
  return new Plugin({
    key: appearanceKey,
    state: {
      init: (): AppearanceState => ({
        fades: [],
        caretPosition: null,
        caretExpiresAt: 0,
        set: DecorationSet.empty,
      }),
      apply(tr, previous): AppearanceState {
        const now = Date.now();
        let fades: FadeEntry[] = [];
        const docSize = tr.doc.content.size;
        for (const entry of previous.fades) {
          // Big replace steps (finalization diff) can map a fade past the new
          // document's end; resolve() would throw and kill the whole dispatch.
          const from = Math.min(tr.mapping.map(entry.from), docSize);
          const to = Math.min(tr.mapping.map(entry.to), docSize);
          if (from >= to || now >= entry.expiresAt) continue;
          if (tr.doc.resolve(from).parent !== tr.doc.resolve(to).parent) continue;
          fades.push({ from, to, expiresAt: entry.expiresAt });
        }
        let caretPosition = previous.caretPosition === null
          ? null
          : Math.min(tr.mapping.map(previous.caretPosition), docSize);
        let caretExpiresAt = previous.caretExpiresAt;

        if (tr.docChanged && isStreamingActive()) {
          tr.steps.forEach((step, index) => {
            const laterMaps = tr.mapping.slice(index + 1);
            tr.mapping.maps[index].forEach((_fromA, _toA, fromB, toB) => {
              if (toB <= fromB) return;
              const from = laterMaps.map(fromB);
              const to = laterMaps.map(toB);
              if (to - from > MAXIMUM_FADE_CHARACTERS) return;
              const parentFrom = tr.doc.resolve(from);
              if (parentFrom.parent !== tr.doc.resolve(to).parent) return;
              // Inline decorations and the caret must live inside a textblock;
              // top-level inserts (new paragraphs) render on their next tick.
              if (!parentFrom.parent.isTextblock) return;
              fades.push({ from, to, expiresAt: now + FADE_MILLISECONDS });
              caretPosition = to;
              caretExpiresAt = now + CARET_IDLE_MILLISECONDS;
            });
          });
        }
        if (caretPosition !== null && now >= caretExpiresAt) caretPosition = null;

        const decorations = fades.map((entry) => Decoration.inline(entry.from, entry.to, FADE_SPEC));
        if (caretPosition !== null) {
          decorations.push(Decoration.widget(caretPosition, createCaretElement, CARET_SPEC));
        }
        return {
          fades,
          caretPosition,
          caretExpiresAt,
          set: DecorationSet.create(tr.doc, decorations),
        };
      },
    },
    props: {
      // Hidden entirely once the streaming session is over: re-serving the
      // remaining fades would RE-CREATE their span elements, and a fresh
      // wb-stream-in span replays its 200ms fade from opacity 0 — the
      // just-typed text visibly vanished and faded back in at completion.
      // Unwrapping completed spans is visually silent; mid-flight ones pop
      // to full opacity, which reads as the line finishing.
      decorations(state) {
        const appearance = appearanceKey.getState(state) as AppearanceState | undefined;
        if (!appearance || !isStreamingActive()) return DecorationSet.empty;
        return appearance.set;
      },
    },
  });
}
