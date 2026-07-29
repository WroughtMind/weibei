import {
  Editor,
  defaultValueCtx,
  editorViewOptionsCtx,
  rootCtx,
} from "@milkdown/kit/core";
import { history } from "@milkdown/kit/plugin/history";
import { listener, listenerCtx } from "@milkdown/kit/plugin/listener";
import { upload, uploadConfig } from "@milkdown/kit/plugin/upload";
import { commonmark } from "@milkdown/kit/preset/commonmark";
import { gfm } from "@milkdown/kit/preset/gfm";
import { Decoration } from "@milkdown/kit/prose/view";
import { katexOptionsCtx, math } from "@milkdown/plugin-math";
import "katex/dist/katex.css";

import { createEditorAPI } from "./api.js";
import { createBridge } from "./core/bridge.js";
import {
  calloutLabel,
  editorLabel,
  frontmatterLabel,
  setInterfaceLanguage,
} from "./core/i18n.js";
import { applyTheme } from "./core/theme.js";
import { createCodeRendering } from "./features/code-rendering.js";
import { createDecorationFeature } from "./features/decorations.js";
import { createImageFeature } from "./features/images.js";
import { createInputBehaviors } from "./features/input-behaviors.js";
import { createPreviewFeature } from "./features/preview.js";
import { createSelectionFeature } from "./features/selection.js";
import { createSlashFeature } from "./features/slash/menu.js";
import { normalizeHtmlBreaks, splitFrontmatter } from "./markdown/normalize.js";
import type { Editor as MilkdownEditor } from "@milkdown/kit/core";

const bridge = createBridge(
  window.webkit?.messageHandlers,
  window.weiBeiDocumentID || "",
);
let editor: MilkdownEditor | undefined;
let editorAPI: ReturnType<typeof createEditorAPI> | undefined;
let isEditable = window.weiBeiMarkdownEditable !== false;
const isCompactPreview = window.weiBeiMarkdownCompactPreview === true;
const isCheckMode = window.weiBeiEditorCheckMode === true;

/**
 * Displays an editor boot or runtime failure.
 *
 * @param error - Failure reported by the browser or editor
 */
const showFailure = (error: unknown): void => {
  if (window.WeiBeiEditorBootFailed) {
    window.WeiBeiEditorBootFailed(error);
    return;
  }
  const root = document.querySelector("#editor");
  if (!root) return;
  const detail =
    error instanceof Error
      ? error.stack || error.message
      : typeof error === "object" &&
          error !== null &&
          "message" in error &&
          typeof error.message === "string"
        ? error.message
        : String(error);
  root.innerHTML = `<pre style="white-space:pre-wrap;color:#9f3427;padding:24px;font:13px/1.5 SFMono-Regular,Menlo,monospace;">${editorLabel("bootFailed")}\n${detail}</pre>`;
};

/**
 * Updates the editor's editable DOM state.
 *
 * @param next - Requested editable state
 */
const setEditable = (next: boolean): void => {
  isEditable = next !== false;
  document.body.dataset.editable = isEditable ? "true" : "false";
  document
    .querySelectorAll<HTMLInputElement>(".weibei-code-language-input")
    .forEach((input) => {
      input.readOnly = !isEditable;
      input.tabIndex = isEditable ? 0 : -1;
      input.setAttribute("aria-readonly", input.readOnly ? "true" : "false");
    });
};

applyTheme(window.weiBeiTheme);
const initialLanguage = setInterfaceLanguage(window.weiBeiInterfaceLanguage);
document.documentElement.dataset.weibeiLanguage = initialLanguage;
document.documentElement.dataset.weibeiCompactPreview = isCompactPreview
  ? "true"
  : "false";

window.addEventListener("error", (event) =>
  showFailure(event.error || event.message),
);
window.addEventListener("unhandledrejection", (event) =>
  showFailure(event.reason),
);

const preview = createPreviewFeature({ isCompactPreview, post: bridge.post });
const selection = createSelectionFeature({
  getEditor: () => editor,
  isCheckMode,
  isSelectionReportSuppressed: () =>
    window.weiBeiSuppressSelectionReport === true,
  post: bridge.post,
});
const slash = createSlashFeature({
  post: bridge.post,
  editorLabel,
  isEditable: () => isEditable,
  getDocumentID: bridge.getDocumentID,
  clearSelectionRange: selection.clearStoredRange,
});
const images = createImageFeature({
  bridge,
  getEditor: () => editor,
  isEditable: () => isEditable,
  label: editorLabel,
  localImageScheme: window.weiBeiLocalImageScheme,
  markdownBaseURL: window.weiBeiMarkdownBaseURL,
  replaceSelection: (markdown: string) =>
    editorAPI!.replaceSelectionInternal(markdown),
});
const codeRendering = createCodeRendering({
  editorLabel,
  isEditable: () => isEditable,
  getEditor: () => editor,
});
const decorations = createDecorationFeature({
  calloutLabel,
  codeRendering,
  images,
  isEditable: () => isEditable,
  label: editorLabel,
  post: bridge.post,
});
const inputBehaviors = createInputBehaviors({
  codeRendering,
  decorations,
  images,
  isEditable: () => isEditable,
  post: bridge.post,
  selection,
  showFailure,
  slash,
});

const initialDocument = splitFrontmatter(window.initialMarkdown || "");
initialDocument.body = normalizeHtmlBreaks(initialDocument.body);
editorAPI = createEditorAPI({
  bridge,
  frontmatterLabel,
  getEditor: () => editor,
  images,
  initialFrontmatter: initialDocument.frontmatter,
  isCheckMode,
  preview,
  selection,
  setEditable,
  showFailure,
  slash,
});
window.WeiBeiEditor = editorAPI.publicAPI;
editorAPI.syncFrontmatterPanel();

Editor.make()
  .config((ctx) => {
    ctx.set(rootCtx, document.querySelector("#editor"));
    ctx.set(defaultValueCtx, initialDocument.body);
    ctx.set(editorViewOptionsCtx, { editable: () => isEditable });
    ctx.set(uploadConfig.key, {
      uploader: images.localImageUploader,
      enableHtmlFileUploader: true,
      uploadWidgetFactory: (pos, spec) => {
        const widget = document.createElement("span");
        widget.className = "weibei-uploading";
        widget.textContent = editorLabel("uploadingImage");
        return Decoration.widget(pos, widget, spec);
      },
    });
    ctx.set(katexOptionsCtx.key, {
      throwOnError: false,
      strict: false,
      trust: false,
    });
  })
  .config(slash.configure)
  .use(inputBehaviors)
  .use(slash.plugin)
  .use(history)
  .use(commonmark)
  .use(gfm)
  .use(math)
  .use(upload)
  .use(listener)
  .config((ctx) => {
    ctx
      .get(listenerCtx)
      .markdownUpdated((_, markdown) =>
        editorAPI.handleMarkdownUpdated(markdown),
      );
    ctx
      .get(listenerCtx)
      .selectionUpdated(() => requestAnimationFrame(selection.reportSelection));
  })
  .create()
  .then((created) => {
    editor = created;
    setEditable(isEditable);
    preview.installQuietScrollIndicators();
    document.querySelector("#editor-status")?.remove();
    const markdown = editorAPI.markReady();
    selection.install();
    document.addEventListener(
      "click",
      (event) => {
        if (
          !decorations.activateWikiLink(event.target) &&
          !decorations.activateSourceReference(event.target) &&
          !decorations.toggleFoldedCallout(event.target)
        )
          return;
        event.preventDefault();
        event.stopPropagation();
      },
      true,
    );
    document.addEventListener(
      "keydown",
      (event) => {
        if (event.key !== "Enter" && event.key !== " ") return;
        if (!decorations.activateWikiLink(event.target)) return;
        event.preventDefault();
        event.stopPropagation();
      },
      true,
    );
    preview.installContentHeightObserver();
    document.addEventListener("scroll", preview.reportActiveHeading, true);
    bridge.post("editorReady", { markdown });
    preview.scheduleContentHeightReports();
    preview.reportActiveHeading();
  })
  .catch(showFailure);
