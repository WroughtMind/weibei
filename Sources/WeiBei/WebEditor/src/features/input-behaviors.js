import { exitCode, setBlockType } from '@milkdown/kit/prose/commands';
import { Plugin, TextSelection } from '@milkdown/kit/prose/state';
import { liftListItem } from '@milkdown/kit/prose/schema-list';
import { $prose } from '@milkdown/kit/utils';

/**
 * Creates the single WeiBei ProseMirror behavior plugin.
 *
 * @param {object} dependencies - Behavior dependencies
 * @returns {import('@milkdown/kit/utils').$Prose} Milkdown prose plugin
 */
export function createInputBehaviors({
  codeRendering,
  decorations,
  images,
  isEditable,
  post,
  selection,
  showFailure,
  slash,
}) {
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

  /**
   * Replaces an empty code block with a paragraph so Backspace and Delete can remove the container.
   *
   * @param {import('@milkdown/kit/prose/view').EditorView} view - Current ProseMirror view
   * @param {KeyboardEvent} event - Key event from the editor
   * @returns {boolean}
   */
  const clearEmptyCodeBlock = (view, event) => {
    if (!isEditable()
        || event.shiftKey
        || event.altKey
        || event.metaKey
        || event.ctrlKey
        || (event.key !== 'Backspace' && event.key !== 'Delete')) {
      return false;
    }
    const { selection, schema } = view.state;
    if (!(selection instanceof TextSelection) || !selection.empty) return false;
    if (selection.$from.parent.type.spec.code !== true || selection.$from.parent.content.size !== 0) return false;
    const paragraph = schema.nodes.paragraph;
    return Boolean(paragraph && setBlockType(paragraph)(view.state, view.dispatch));
  };

  /**
   * Moves the caret out of a terminal code block using forward navigation keys.
   *
   * @param {import('@milkdown/kit/prose/view').EditorView} view - Current ProseMirror view
   * @param {KeyboardEvent} event - Key event from the editor
   * @returns {boolean}
   */
  const exitTerminalCodeBlock = (view, event) => {
    if (!isEditable()
        || event.shiftKey
        || event.altKey
        || event.metaKey
        || event.ctrlKey
        || (event.key !== 'ArrowRight' && event.key !== 'ArrowDown')) {
      return false;
    }
    const { selection } = view.state;
    if (!(selection instanceof TextSelection) || !selection.empty) return false;
    const { $from } = selection;
    if ($from.parent.type.spec.code !== true) return false;
    const container = $from.node(-1);
    if ($from.indexAfter(-1) !== container.childCount) return false;
    let atExitBoundary = $from.parentOffset === $from.parent.content.size;
    if (event.key === 'ArrowDown' && !atExitBoundary) {
      atExitBoundary = view.endOfTextblock('down');
      if (!atExitBoundary) {
        const codeDOM = view.nodeDOM($from.before());
        const domPosition = view.domAtPos($from.pos);
        if (codeDOM instanceof HTMLElement && codeDOM.contains(domPosition.node)) {
          const trailingRange = document.createRange();
          trailingRange.setStart(domPosition.node, domPosition.offset);
          trailingRange.setEnd(codeDOM, codeDOM.childNodes.length);
          const caretRect = view.coordsAtPos($from.pos);
          atExitBoundary = Array.from(trailingRange.getClientRects())
            .filter((rect) => rect.height > 1 && rect.width > 0)
            .every((rect) => rect.top < caretRect.bottom + 1);
        }
        if (!atExitBoundary) {
          atExitBoundary = !$from.parent.textContent.slice($from.parentOffset).includes('\n');
        }
      }
    }
    if (!atExitBoundary) return false;
    return exitCode(view.state, view.dispatch);
  };


  return $prose(() => new Plugin({
    view(view) {
      images.scheduleImageResolution(view);
      codeRendering.annotateMathErrors();
      return {
        update(updatedView) {
          images.scheduleImageResolution(updatedView);
          codeRendering.annotateMathErrors();
        },
      };
    },
    props: {
      handlePaste(_, event) {
        if (!isEditable()) return false;
        const files = images.imageFilesFromItems(event.clipboardData?.items);
        if (files.length === 0) return false;
        event.preventDefault();
        images.insertImageFiles(files).catch(showFailure);
        return true;
      },
      handleDrop(_, event) {
        if (!isEditable()) return false;
        const files = images.imageFilesFromItems(event.dataTransfer?.items);
        if (files.length === 0) return false;
        event.preventDefault();
        images.insertImageFiles(files).catch(showFailure);
        return true;
      },
      handleTextInput(view, from, to, text) {
        if (!isEditable()) return false;
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
      handleClick(_, __, event) {
        return decorations.activateWikiLink(event.target)
          || decorations.activateSourceReference(event.target)
          || decorations.toggleFoldedCallout(event.target);
      },
      handleKeyDown(view, event) {
        if (slash.handleKeyDown(view, event)) return true;
        if (clearEmptyCodeBlock(view, event)) {
          event.preventDefault();
          return true;
        }
        if (exitTerminalCodeBlock(view, event)) {
          event.preventDefault();
          return true;
        }
        if (
          event.key === 'Enter'
          && isEditable()
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
        if (decorations.activateSourceReference(event.target)) {
          event.preventDefault();
          return true;
        }
        if (!event.metaKey && !event.ctrlKey) return false;
        const title = selection.wikiTitleAtSelection();
        if (!title) return false;
        post('wikiLinkActivated', { title });
        event.preventDefault();
        return true;
      },
      decorations: decorations.buildDecorations,
    },
  }));
}
