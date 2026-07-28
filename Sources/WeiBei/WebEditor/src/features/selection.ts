import { editorViewCtx } from "@milkdown/kit/core";
import { TextSelection } from "@milkdown/kit/prose/state";
import type { EditorView } from "@milkdown/kit/prose/view";

import { cleanSelectedText } from "../markdown/normalize.js";
import { parseObsidianTarget } from "../markdown/obsidian.js";
import type { EditorBridge, EditorRange, GetEditor } from "../types.js";

interface SelectionFeatureDependencies {
  getEditor: GetEditor;
  isCheckMode: boolean;
  isSelectionReportSuppressed: () => boolean;
  post: EditorBridge["post"];
}

interface SelectionRectangle {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface InsertionSelectionRange {
  startFrom: number;
  startTo: number;
  endFrom: number;
  endTo: number;
}

interface KeyOptions {
  shiftKey?: boolean;
  altKey?: boolean;
  metaKey?: boolean;
  ctrlKey?: boolean;
}

const insertionCursorMarker = "{{WEIBEI_CURSOR}}";
const insertionSelectionStartMarker = "{{WEIBEI_SELECT_START}}";
const insertionSelectionEndMarker = "{{WEIBEI_SELECT_END}}";

/**
 * Creates selection reporting, insertion cursor, and editor check behavior.
 *
 * @param dependencies - Selection dependencies
 * @returns Selection feature API
 */
export function createSelectionFeature({
  getEditor,
  isCheckMode,
  isSelectionReportSuppressed,
  post,
}: SelectionFeatureDependencies) {
  let lastSelectionRange: EditorRange | null = null;
  let lastSelectionReport: { text: string | null; rectKey: string | null } = {
    text: null,
    rectKey: null,
  };

  const rectFromSelection = (): SelectionRectangle | null => {
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) return null;
    const rect = selection.getRangeAt(0).getBoundingClientRect();
    if (!rect || rect.width + rect.height === 0) return null;
    return {
      x: rect.left + rect.width / 2,
      y: rect.bottom,
      width: rect.width,
      height: rect.height,
    };
  };

  const editorSelectionRange = (): EditorRange | null => {
    const editor = getEditor();
    if (!editor) return null;
    const selection = editor.action(
      (ctx) => ctx.get(editorViewCtx).state.selection,
    );
    if (!selection || selection.empty) return null;
    return { from: selection.from, to: selection.to };
  };

  const editorSelectedText = (): string => {
    const editor = getEditor();
    if (!editor) return "";
    return editor.action((ctx) => {
      const { selection } = ctx.get(editorViewCtx).state;
      if (!selection || selection.empty) return "";
      const content = selection.content().content;
      return cleanSelectedText(content.textBetween(0, content.size, "\n"));
    });
  };

  const selectedText = (): string =>
    cleanSelectedText(
      window.getSelection()?.toString() || editorSelectedText(),
    );
  const wikiNavigationTitle = (raw: string): string => {
    const parsed = parseObsidianTarget(raw);
    return parsed.target || parsed.noteTitle;
  };

  const wikiTitleAtSelection = (): string => {
    const editor = getEditor();
    if (!editor) return "";
    return editor.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      const pos = view.state.selection.from;
      let title = "";
      view.state.doc.descendants((node, nodePos) => {
        if (!node.isText || title) return true;
        const text = node.text || "";
        const start = nodePos;
        const end = nodePos + text.length;
        if (pos < start || pos > end) return true;
        for (const match of text.matchAll(/\[\[([^\]\n]+)\]\]/g)) {
          const rawTarget = match[1];
          if (!rawTarget) continue;
          const from = start + (match.index || 0);
          const to = from + match[0].length;
          if (pos >= from && pos <= to) {
            title = wikiNavigationTitle(rawTarget);
            return false;
          }
        }
        return true;
      });
      return title;
    });
  };
  const looksLikeBlockMarkdown = (markdown: string): boolean => {
    const text = String(markdown || "");
    const trimmed = text.trim();
    if (!trimmed) return false;
    if (text.includes("\n")) return true;
    return /^(?:#{1,6}\s|[-*+]\s|\d+\.\s|>\s|```|~~~|\$\$|\|.*\||---$)/.test(
      trimmed,
    );
  };

  const normalizeMarkdownInsertion = (markdown: string): string => {
    const text = String(markdown || "");
    if (!looksLikeBlockMarkdown(text)) return text;
    return `\n\n${text.trim()}\n\n`;
  };

  const placeCursorAtInsertionMarker = (): boolean =>
    getEditor()!.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      const selectionRange: { current: InsertionSelectionRange | null } = {
        current: null,
      };
      const range: { current: EditorRange | null } = { current: null };
      view.state.doc.descendants((node, pos) => {
        if (!node.isText || selectionRange.current || range.current)
          return true;
        const text = node.text || "";
        const startIndex = text.indexOf(insertionSelectionStartMarker);
        const endIndex = text.indexOf(insertionSelectionEndMarker);
        if (startIndex >= 0 && endIndex > startIndex) {
          selectionRange.current = {
            startFrom: pos + startIndex,
            startTo: pos + startIndex + insertionSelectionStartMarker.length,
            endFrom: pos + endIndex,
            endTo: pos + endIndex + insertionSelectionEndMarker.length,
          };
          return false;
        }
        const index = text.indexOf(insertionCursorMarker);
        if (index < 0) return true;
        range.current = {
          from: pos + index,
          to: pos + index + insertionCursorMarker.length,
        };
        return false;
      });
      if (selectionRange.current) {
        const selectedRange = selectionRange.current;
        const tr = view.state.tr
          .delete(selectedRange.endFrom, selectedRange.endTo)
          .delete(selectedRange.startFrom, selectedRange.startTo);
        const from = Math.min(selectedRange.startFrom, tr.doc.content.size);
        const to = Math.min(
          Math.max(
            from,
            selectedRange.endFrom - insertionSelectionStartMarker.length,
          ),
          tr.doc.content.size,
        );
        tr.setSelection(TextSelection.create(tr.doc, from, to));
        view.dispatch(tr);
        return true;
      }
      if (!range.current) return false;
      const cursorRange = range.current;
      const tr = view.state.tr.delete(cursorRange.from, cursorRange.to);
      const selectionPosition = Math.min(cursorRange.from, tr.doc.content.size);
      tr.setSelection(TextSelection.create(tr.doc, selectionPosition));
      view.dispatch(tr);
      return true;
    });

  const collapseSelectionToEnd = (): void =>
    getEditor()!.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      const position = Math.min(
        view.state.selection.to,
        view.state.doc.content.size,
      );
      view.dispatch(
        view.state.tr.setSelection(
          TextSelection.create(view.state.doc, position),
        ),
      );
    });

  const reportSelection = (): void => {
    if (isSelectionReportSuppressed()) return;
    const text = selectedText();
    const rect = text ? rectFromSelection() : null;
    const rectKey = rect
      ? `${Math.round(rect.x)}:${Math.round(rect.y)}:${Math.round(rect.width)}:${Math.round(rect.height)}`
      : "";
    if (
      text === lastSelectionReport.text &&
      rectKey === lastSelectionReport.rectKey
    )
      return;
    lastSelectionReport = { text, rectKey };
    if (!text) {
      lastSelectionRange = null;
      post("selectionChanged", { text: "", rect: null });
      return;
    }
    lastSelectionRange = editorSelectionRange();
    post("selectionChanged", { text, rect });
  };
  const selectFirstTextForCheck = (needle: string): boolean => {
    if (!isCheckMode || !needle) return false;
    return getEditor()!.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      const range: { current: EditorRange | null } = { current: null };
      view.state.doc.descendants((node, pos) => {
        if (!node.isText || range.current) return true;
        const index = (node.text || "").indexOf(needle);
        if (index < 0) return true;
        range.current = { from: pos + index, to: pos + index + needle.length };
        return false;
      });
      if (!range.current) return false;
      view.dispatch(
        view.state.tr.setSelection(
          TextSelection.create(
            view.state.doc,
            range.current.from,
            range.current.to,
          ),
        ),
      );
      lastSelectionRange = range.current;
      return true;
    });
  };

  /**
   * Places a collapsed test caret at an offset inside the first matching text node.
   *
   * @param needle - Text node fragment to find
   * @param offset - Offset from the fragment start
   * @returns Whether the caret was placed
   */
  const placeCursorAtTextForCheck = (needle: string, offset = 0): boolean => {
    if (!isCheckMode || !needle) return false;
    return getEditor()!.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      let position: number | null = null;
      view.state.doc.descendants((node, pos) => {
        if (!node.isText || position !== null) return true;
        const index = (node.text || "").indexOf(needle);
        if (index < 0) return true;
        position =
          pos +
          index +
          Math.min(Math.max(0, Number(offset) || 0), needle.length);
        return false;
      });
      if (position === null) return false;
      view.dispatch(
        view.state.tr.setSelection(
          TextSelection.create(view.state.doc, position),
        ),
      );
      lastSelectionRange = null;
      view.focus();
      return true;
    });
  };

  const typeTextForCheck = (text: string): boolean => {
    if (!isCheckMode) return false;
    return getEditor()!.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      view.focus();
      for (const character of String(text || "")) {
        const { from, to } = view.state.selection;
        let handled = false;
        view.someProp(
          "handleTextInput",
          (handler: NonNullable<EditorView["props"]["handleTextInput"]>) => {
            if (handled) return true;
            handled =
              handler(view, from, to, character, () =>
                view.state.tr.insertText(character, from, to),
              ) === true;
            return handled;
          },
        );
        if (!handled) {
          view.dispatch(view.state.tr.insertText(character, from, to));
        }
      }
      return true;
    });
  };

  const pressKeyForCheck = (key: string, options: KeyOptions = {}): boolean => {
    if (!isCheckMode) return false;
    return getEditor()!.action((ctx) => {
      const view = ctx.get(editorViewCtx);
      view.focus();
      const event = new KeyboardEvent("keydown", {
        key,
        bubbles: true,
        cancelable: true,
        shiftKey: options.shiftKey === true,
        altKey: options.altKey === true,
        metaKey: options.metaKey === true,
        ctrlKey: options.ctrlKey === true,
      });
      view.dom.dispatchEvent(event);
      return true;
    });
  };

  /**
   * Installs document listeners that keep native selection state synchronized.
   */
  const install = (): void => {
    document.addEventListener("mouseup", reportSelection);
    document.addEventListener(
      "pointerdown",
      () => {
        if (isSelectionReportSuppressed()) return;
        lastSelectionRange = null;
        lastSelectionReport.text = "";
        lastSelectionReport.rectKey = "";
        post("selectionChanged", { text: "", rect: null });
      },
      true,
    );
    document.addEventListener("keyup", reportSelection);
  };

  /**
   * Returns APIs enabled only in editor check mode.
   */
  const checkAPI = () => ({
    selectFirstTextForCheck,
    placeCursorAtTextForCheck,
    selectedTextForCheck: editorSelectedText,
    typeTextForCheck,
    pressKeyForCheck,
  });

  return {
    checkAPI,
    clearStoredRange: () => {
      lastSelectionRange = null;
    },
    collapseSelectionToEnd,
    editorSelectedText,
    getCurrentRange: editorSelectionRange,
    getStoredRange: () => lastSelectionRange,
    install,
    normalizeMarkdownInsertion,
    placeCursorAtInsertionMarker,
    rectFromSelection,
    reportSelection,
    selectedText,
    setStoredRange: (range: EditorRange | null) => {
      lastSelectionRange = range;
    },
    wikiTitleAtSelection,
  };
}
