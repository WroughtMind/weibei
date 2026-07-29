import { editorViewCtx } from '@milkdown/kit/core';
import { undo } from '@milkdown/kit/prose/history';
import { getMarkdown as readMarkdown, insert, replaceAll, replaceRange } from '@milkdown/kit/utils';

import { applyTheme, getCurrentTheme } from './core/theme.js';
import { getInterfaceLanguage, setInterfaceLanguage } from './core/i18n.js';
import {
  escapeHTML,
  frontmatterRows,
  normalizeHtmlBreaks,
  splitFrontmatter,
  withFrontmatter,
} from './markdown/normalize.js';

/**
 * Creates the stable window.WeiBeiEditor API and document controller.
 *
 * @param {object} dependencies - Editor services coordinated by the public API
 * @returns {object} Public API and document lifecycle hooks
 */
export function createEditorAPI({
  bridge,
  frontmatterLabel,
  getEditor,
  images,
  initialFrontmatter,
  isCheckMode,
  preview,
  selection,
  setEditable,
  showFailure,
  slash,
}) {
  let frontmatterBlock = initialFrontmatter || '';
  let lastMarkdown = '';

  const ensureEditor = () => {
    if (!getEditor()) throw new Error('WeiBei editor is not ready');
  };

  const syncFrontmatterPanel = () => {
    const panel = document.querySelector('#frontmatter-panel');
    if (!panel) return;
    const rows = frontmatterRows(frontmatterBlock);
    panel.dataset.visible = rows.length > 0 ? 'true' : 'false';
    panel.innerHTML = rows.length > 0
      ? `<div class="frontmatter-title">${frontmatterLabel()}</div>${rows.map((row) => (
        `<div class="frontmatter-row"><span class="frontmatter-key">${escapeHTML(row.key)}</span><span>${escapeHTML(row.value)}</span></div>`
      )).join('')}`
      : '';
  };

  const getMarkdownInternal = () => {
    ensureEditor();
    return withFrontmatter(frontmatterBlock, getEditor().action(readMarkdown()));
  };

  const setMarkdownInternal = (markdown) => {
    ensureEditor();
    const document = splitFrontmatter(markdown || '');
    const body = normalizeHtmlBreaks(document.body);
    frontmatterBlock = document.frontmatter;
    syncFrontmatterPanel();
    getEditor().action(replaceAll(body));
    lastMarkdown = withFrontmatter(frontmatterBlock, body);
    preview.scheduleContentHeightReports();
  };

  const replaceSelectionInternal = (markdown) => {
    ensureEditor();
    const insertion = normalizeHtmlBreaks(markdown || '');
    const range = selection.getStoredRange() || selection.getCurrentRange();
    if (range) {
      getEditor().action(replaceRange(insertion, range));
    } else {
      getEditor().action(insert(insertion));
    }
    const next = getMarkdownInternal();
    lastMarkdown = next;
    selection.clearStoredRange();
    bridge.post('markdownChanged', { markdown: next });
  };

  const insertMarkdownInternal = (markdown) => {
    ensureEditor();
    const range = selection.getCurrentRange();
    const insertion = selection.normalizeMarkdownInsertion(normalizeHtmlBreaks(markdown));
    if (range) {
      getEditor().action(replaceRange(insertion, range));
    } else {
      getEditor().action(insert(insertion));
    }
    if (!selection.placeCursorAtInsertionMarker()) {
      selection.collapseSelectionToEnd();
    }
    const next = getMarkdownInternal();
    lastMarkdown = next;
    selection.clearStoredRange();
    bridge.post('markdownChanged', { markdown: next });
  };

  const guarded = (action) => (...args) => {
    try {
      return action(...args);
    } catch (error) {
      showFailure(error);
      return undefined;
    }
  };

  const publicAPI = {
    getMarkdown: getMarkdownInternal,
    setMarkdown: setMarkdownInternal,
    replaceSelection: guarded(replaceSelectionInternal),
    applyAgentPatch: guarded((markdown) => {
      const current = getMarkdownInternal();
      setMarkdownInternal(`${current.trimEnd()}\n\n${markdown || ''}\n`);
      const next = getMarkdownInternal();
      lastMarkdown = next;
      bridge.post('markdownChanged', { markdown: next });
    }),
    askAgentWithSelection: () => {
      selection.setStoredRange(selection.getCurrentRange() || selection.getStoredRange());
      bridge.post('askAgentWithSelection', {
        text: selection.selectedText(),
        rect: selection.rectFromSelection(),
      });
    },
    insertMarkdownImage: guarded(replaceSelectionInternal),
    insertMarkdown: guarded(insertMarkdownInternal),
    resolveAttachment: images.resolveAttachment,
    rejectAttachment: images.rejectAttachment,
    discardAttachment: images.discardAttachment,
    resolveImagePicker: slash.resolveImagePicker,
    cancelImagePicker: slash.cancelImagePicker,
    discardImagePicker: slash.discardImagePicker,
    rejectImagePicker: slash.rejectImagePicker,
    setEditable,
    setDocumentID: (next) => {
      const documentID = next || '';
      if (documentID === bridge.getDocumentID()) return;
      images.discardAllAttachments();
      slash.discardAllImagePickers();
      bridge.setDocumentID(documentID);
    },
    setMarkdownBaseURL: images.setMarkdownBaseURL,
    setTheme: (next) => {
      applyTheme(next);
      images.refreshMissingPlaceholders();
      if (!getEditor()) return;
      getEditor().action((ctx) => {
        const view = ctx.get(editorViewCtx);
        view.dispatch(view.state.tr.setMeta('weibeiThemeChanged', getCurrentTheme()));
      });
    },
    setInterfaceLanguage: (next) => {
      const language = setInterfaceLanguage(next);
      document.documentElement.dataset.weibeiLanguage = language;
      syncFrontmatterPanel();
      if (slash.isVisible()) slash.refresh();
      if (!getEditor()) return;
      getEditor().action((ctx) => {
        const view = ctx.get(editorViewCtx);
        view.dispatch(view.state.tr.setMeta('weibeiLanguageChanged', getInterfaceLanguage()));
      });
    },
    scrollToHeading: preview.scrollToHeading,
  };

  if (isCheckMode) {
    Object.assign(publicAPI, selection.checkAPI(), slash.checkAPI(), {
      undoForCheck: () => getEditor().action((ctx) => {
        const view = ctx.get(editorViewCtx);
        return undo(view.state, view.dispatch);
      }),
    });
  }

  return {
    publicAPI,
    getLastMarkdown: () => lastMarkdown,
    handleMarkdownUpdated: (markdown) => {
      const normalizedMarkdown = withFrontmatter(frontmatterBlock, markdown);
      if (normalizedMarkdown === lastMarkdown) return;
      lastMarkdown = normalizedMarkdown;
      bridge.post('markdownChanged', { markdown: normalizedMarkdown });
      preview.scheduleContentHeightReports();
      preview.reportActiveHeading();
    },
    markReady: () => {
      lastMarkdown = getMarkdownInternal();
      return lastMarkdown;
    },
    replaceSelectionInternal,
    syncFrontmatterPanel,
  };
}
