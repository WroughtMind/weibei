import { Plugin } from '@milkdown/kit/prose/state';

export const setTypewriterMode = (enabled: boolean) => {
  document.body.dataset.typewriter = String(enabled);
  document.dispatchEvent(new Event('weibei-typewriter-changed'));
};

/** Follow typing only. Mouse selection, wheel scrolling and remote note reloads
 * must never pull the reader back to the caret. */
export const createTypewriterPlugin = () => {
  let pendingInput = false;
  const enabled = () => document.body.dataset.typewriter === 'true';
  return new Plugin({
    props: {
      handleScrollToSelection: () => enabled() && pendingInput,
    },
    view(view) {
      let scrollTimer = 0;
      let compositionTimer = 0;
      const scroll = document.getElementById('editor')!;
      const cancel = () => {
        pendingInput = false;
        clearTimeout(scrollTimer);
        clearTimeout(compositionTimer);
      };
      const schedule = () => {
        if (!enabled()) return;
        pendingInput = true;
        clearTimeout(scrollTimer);
        scrollTimer = window.setTimeout(() => {
          const follow = pendingInput;
          pendingInput = false;
          if (!follow || !enabled() || view.composing || !view.hasFocus()
              || !view.state.selection.empty || !view.editable) return;
          const caret = view.coordsAtPos(view.state.selection.head);
          const bounds = scroll.getBoundingClientRect();
          scroll.scrollTop += (caret.top + caret.bottom) / 2 - bounds.top - scroll.clientHeight / 2;
        }, 0);
      };
      const keydown = (event: KeyboardEvent) => {
        if (event.key === 'Enter' || event.key === 'Backspace' || event.key === 'Delete'
            || (event.key.length === 1 && !event.metaKey && !event.ctrlKey)) schedule();
      };
      const compositionEnd = () => {
        // ProseMirror finishes the IME transaction after the native end event.
        compositionTimer = window.setTimeout(schedule, 30);
      };
      const modeChanged = () => { cancel(); if (enabled()) schedule(); };
      view.dom.addEventListener('beforeinput', schedule);
      view.dom.addEventListener('input', schedule);
      view.dom.addEventListener('keydown', keydown);
      view.dom.addEventListener('compositionstart', cancel);
      view.dom.addEventListener('compositionend', compositionEnd);
      scroll.addEventListener('wheel', cancel, { passive: true });
      scroll.addEventListener('pointerdown', cancel);
      document.addEventListener('weibei-typewriter-changed', modeChanged);
      return {
        update(updatedView, previousState) {
          if (pendingInput && updatedView.state.doc !== previousState.doc) schedule();
        },
        destroy() {
          cancel();
          view.dom.removeEventListener('beforeinput', schedule);
          view.dom.removeEventListener('input', schedule);
          view.dom.removeEventListener('keydown', keydown);
          view.dom.removeEventListener('compositionstart', cancel);
          view.dom.removeEventListener('compositionend', compositionEnd);
          scroll.removeEventListener('wheel', cancel);
          scroll.removeEventListener('pointerdown', cancel);
          document.removeEventListener('weibei-typewriter-changed', modeChanged);
        },
      };
    },
  });
};
