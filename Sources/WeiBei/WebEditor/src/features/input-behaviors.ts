import { exitCode, setBlockType } from "@milkdown/kit/prose/commands";
import type { Node as ProseMirrorNode } from "@milkdown/kit/prose/model";
import type { EditorState } from "@milkdown/kit/prose/state";
import { Plugin, TextSelection } from "@milkdown/kit/prose/state";
import { liftListItem } from "@milkdown/kit/prose/schema-list";
import type { EditorView } from "@milkdown/kit/prose/view";
import { $prose } from "@milkdown/kit/utils";

import type { createCodeRendering } from "./code-rendering.js";
import type { createDecorationFeature } from "./decorations.js";
import type { createImageFeature } from "./images.js";
import type { createSelectionFeature } from "./selection.js";
import type { createSlashFeature } from "./slash/menu.js";
import type { EditorBridge, ShowFailure } from "../types.js";

interface InputBehaviorDependencies {
  codeRendering: ReturnType<typeof createCodeRendering>;
  decorations: ReturnType<typeof createDecorationFeature>;
  images: ReturnType<typeof createImageFeature>;
  isEditable: () => boolean;
  post: EditorBridge["post"];
  selection: ReturnType<typeof createSelectionFeature>;
  showFailure: ShowFailure;
  slash: ReturnType<typeof createSlashFeature>;
}

/**
 * Creates the single WeiBei ProseMirror behavior plugin.
 *
 * @param dependencies - Behavior dependencies
 * @returns Milkdown prose plugin
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
}: InputBehaviorDependencies) {
  /**
   * Ignores document-switch cancellations while surfacing real image failures.
   *
   * @param error - Image insertion failure
   */
  const reportImageFailure = (error: unknown): void => {
    if (error instanceof DOMException && error.name === "AbortError") return;
    showFailure(error);
  };

  const listItemTypeNames = new Set(["list_item", "task_list_item"]);
  const meaningfulListText = (node: ProseMirrorNode): string =>
    (node.textContent || "").replace(/[\u200B\uFEFF]/g, "").trim();

  const emptyListItemTypeAtSelection = (state: EditorState) => {
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

  const clearInvisibleCurrentTextblock = (view: EditorView): void => {
    const { state } = view;
    const { $from } = state.selection;
    const node = $from.parent;
    if (
      node?.isTextblock !== true ||
      !node.textContent ||
      meaningfulListText(node).length > 0
    )
      return;
    const from = $from.start();
    const to = $from.end();
    const tr = state.tr.delete(from, to);
    tr.setSelection(
      TextSelection.create(tr.doc, Math.min(from, tr.doc.content.size)),
    );
    view.dispatch(tr);
  };

  const exitEmptyListItem = (view: EditorView): boolean => {
    let listItemType = emptyListItemTypeAtSelection(view.state);
    if (!listItemType) return false;
    clearInvisibleCurrentTextblock(view);
    listItemType = emptyListItemTypeAtSelection(view.state) || listItemType;
    return liftListItem(listItemType)(view.state, view.dispatch, view);
  };

  /**
   * Replaces an empty code block with a paragraph so Backspace and Delete can remove the container.
   *
   * @param view - Current ProseMirror view
   * @param event - Key event from the editor
   * @returns Whether the empty code block was replaced
   */
  const clearEmptyCodeBlock = (
    view: EditorView,
    event: KeyboardEvent,
  ): boolean => {
    if (
      !isEditable() ||
      event.shiftKey ||
      event.altKey ||
      event.metaKey ||
      event.ctrlKey ||
      (event.key !== "Backspace" && event.key !== "Delete")
    ) {
      return false;
    }
    const { selection, schema } = view.state;
    if (!(selection instanceof TextSelection) || !selection.empty) return false;
    if (
      selection.$from.parent.type.spec.code !== true ||
      selection.$from.parent.content.size !== 0
    )
      return false;
    const paragraph = schema.nodes.paragraph;
    return Boolean(
      paragraph && setBlockType(paragraph)(view.state, view.dispatch),
    );
  };

  /**
   * Returns the rendered rectangle of a code character at a text offset.
   *
   * A DOM range avoids the upstream line bias of `coordsAtPos` at newline
   * boundaries while still following browser line wrapping.
   *
   * @param codeDOM - ProseMirror DOM node for the code block
   * @param textOffset - Character offset in the code block
   * @returns Character rectangle when one can be measured
   */
  const codeCharacterRectAtOffset = (
    codeDOM: Node | null,
    textOffset: number,
  ): DOMRect | null => {
    if (!(codeDOM instanceof HTMLElement)) return null;
    const codeContent = codeDOM.matches("code")
      ? codeDOM
      : codeDOM.querySelector("code") || codeDOM;
    const walker = document.createTreeWalker(
      codeContent,
      NodeFilter.SHOW_TEXT,
    );
    let remainingOffset = Math.max(0, Math.trunc(textOffset));
    let fallback: { node: Node; offset: number } | null = null;
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      const text = node.textContent || "";
      if (text.length === 0) continue;
      for (let index = text.length - 1; index >= 0; index -= 1) {
        if (text[index] !== "\n" && text[index] !== "\r") {
          fallback = { node, offset: index };
          break;
        }
      }
      if (remainingOffset >= text.length) {
        remainingOffset -= text.length;
        continue;
      }
      let offset = remainingOffset;
      while (
        offset < text.length &&
        (text[offset] === "\n" || text[offset] === "\r")
      ) {
        offset += 1;
      }
      if (offset >= text.length) {
        remainingOffset = 0;
        continue;
      }
      const range = document.createRange();
      range.setStart(node, offset);
      range.setEnd(node, offset + 1);
      const rect = range.getBoundingClientRect();
      return rect.height > 1 && rect.width > 0 ? rect : null;
    }
    if (!fallback) return null;
    const range = document.createRange();
    range.setStart(fallback.node, fallback.offset);
    range.setEnd(fallback.node, fallback.offset + 1);
    const rect = range.getBoundingClientRect();
    return rect.height > 1 && rect.width > 0 ? rect : null;
  };

  /**
   * Moves the caret out of a terminal code block using forward navigation keys.
   *
   * @param view - Current ProseMirror view
   * @param event - Key event from the editor
   * @returns Whether the caret moved out of the terminal code block
   */
  const exitTerminalCodeBlock = (
    view: EditorView,
    event: KeyboardEvent,
  ): boolean => {
    if (
      !isEditable() ||
      event.shiftKey ||
      event.altKey ||
      event.metaKey ||
      event.ctrlKey ||
      (event.key !== "ArrowRight" && event.key !== "ArrowDown")
    ) {
      return false;
    }
    const { selection } = view.state;
    if (!(selection instanceof TextSelection) || !selection.empty) return false;
    const { $from } = selection;
    if ($from.parent.type.spec.code !== true) return false;
    const container = $from.node(-1);
    if ($from.indexAfter(-1) !== container.childCount) return false;
    let atExitBoundary = $from.parentOffset === $from.parent.content.size;
    if (event.key === "ArrowDown" && !atExitBoundary) {
      const codeDOM = view.nodeDOM($from.before());
      const caretRect = codeCharacterRectAtOffset(
        codeDOM,
        $from.parentOffset,
      );
      const finalRect = codeCharacterRectAtOffset(
        codeDOM,
        $from.parent.content.size - 1,
      );
      atExitBoundary = Boolean(
        caretRect &&
        finalRect &&
        finalRect.top < caretRect.bottom + 1 &&
        finalRect.bottom > caretRect.top - 1,
      );
    }
    if (!atExitBoundary) return false;
    return exitCode(view.state, view.dispatch);
  };

  return $prose(
    () =>
      new Plugin({
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
            const files = images.imageFilesFromItems(
              event.clipboardData?.items,
            );
            if (files.length === 0) return false;
            event.preventDefault();
            images.insertImageFiles(files).catch(reportImageFailure);
            return true;
          },
          handleDrop(_, event) {
            if (!isEditable()) return false;
            const files = images.imageFilesFromItems(event.dataTransfer?.items);
            if (files.length === 0) return false;
            event.preventDefault();
            images.insertImageFiles(files).catch(reportImageFailure);
            return true;
          },
          handleTextInput(view, from, to, text) {
            if (!isEditable()) return false;
            const incoming = String(text || "");
            if (!incoming) return false;
            const lookBehindSize = Math.min(12, from);
            const before = view.state.doc.textBetween(
              from - lookBehindSize,
              from,
              "\n",
              "\n",
            );
            const match = `${before}${incoming}`.match(/<br\s*\/?>$/i);
            if (!match) return false;
            const hardbreak =
              view.state.schema.nodes.hardbreak ||
              view.state.schema.nodes.hard_break;
            if (!hardbreak) return false;
            const start = from - (match[0].length - incoming.length);
            const tr = view.state.tr
              .replaceWith(start, to, hardbreak.create())
              .scrollIntoView();
            tr.setSelection(
              TextSelection.create(
                tr.doc,
                Math.min(start + 1, tr.doc.content.size),
              ),
            );
            view.dispatch(tr);
            return true;
          },
          handleClick(_, __, event) {
            return (
              decorations.activateWikiLink(event.target) ||
              decorations.activateSourceReference(event.target) ||
              decorations.toggleFoldedCallout(event.target)
            );
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
              event.key === "Enter" &&
              isEditable() &&
              !event.shiftKey &&
              !event.altKey &&
              !event.metaKey &&
              !event.ctrlKey &&
              exitEmptyListItem(view)
            ) {
              event.preventDefault();
              return true;
            }
            if (event.key !== "Enter" && event.key !== " ") return false;
            if (decorations.activateSourceReference(event.target)) {
              event.preventDefault();
              return true;
            }
            if (!event.metaKey && !event.ctrlKey) return false;
            const title = selection.wikiTitleAtSelection();
            if (!title) return false;
            post("wikiLinkActivated", { title });
            event.preventDefault();
            return true;
          },
          decorations: decorations.buildDecorations,
        },
      }),
  );
}
