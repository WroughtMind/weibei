import { editorViewCtx } from "@milkdown/kit/core";
import { readImageAsBase64 } from "@milkdown/kit/plugin/upload";
import type {
  Node as ProseMirrorNode,
  Schema,
} from "@milkdown/kit/prose/model";
import type { EditorState } from "@milkdown/kit/prose/state";
import type { EditorView } from "@milkdown/kit/prose/view";

import { getCurrentTheme } from "../core/theme.js";
import { escapeHTML } from "../markdown/normalize.js";
import { applyImageSize, parseMarkdownImageAlt } from "../markdown/obsidian.js";
import type { EditorBridge, EditorLabel, GetEditor } from "../types.js";

interface ImageFeatureDependencies {
  bridge: EditorBridge;
  getEditor: GetEditor;
  isEditable: () => boolean;
  label: EditorLabel;
  localImageScheme?: string | undefined;
  markdownBaseURL?: string | undefined;
  replaceSelection: (markdown: string) => void;
}

interface SavedImage {
  alt: string;
  src: string;
}

interface PendingAttachment {
  resolve: (image: SavedImage) => void;
  reject: (reason: Error) => void;
  documentID: string;
}

/**
 * Creates image resolution, native attachment, and upload behavior.
 *
 * @param dependencies - Image feature dependencies
 * @returns Image feature API
 */
export function createImageFeature({
  bridge,
  getEditor,
  isEditable,
  label,
  localImageScheme,
  markdownBaseURL,
  replaceSelection,
}: ImageFeatureDependencies) {
  let currentMarkdownBaseURL = markdownBaseURL || "";
  const imageScheme = localImageScheme || "weibeiimage";
  let attachmentRequestID = 0;
  let imageRefreshFrame = 0;
  const pendingAttachments = new Map<string, PendingAttachment>();

  const localImageURL = (src: string): string =>
    `${imageScheme}://image?src=${encodeURIComponent(src)}`;

  const missingImageURL = (): string => {
    const palette =
      getCurrentTheme() === "inkstone"
        ? { background: "#151515", accent: "#a6362b", text: "#d7cbb0" }
        : { background: "#efe6d8", accent: "#9f3b2f", text: "#6b5148" };
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="156" height="34" viewBox="0 0 156 34">
    <rect width="156" height="34" rx="3" fill="${palette.background}"/>
    <path d="M18 22l5-6 4 4 3-3 6 5" fill="none" stroke="${palette.accent}" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>
    <rect x="17" y="11" width="20" height="14" rx="2" fill="none" stroke="${palette.accent}" stroke-width="1.2"/>
    <text x="48" y="22" fill="${palette.text}" font-family="-apple-system, BlinkMacSystemFont, 'Songti SC', serif" font-size="13">${escapeHTML(label("imageMissing"))}</text>
  </svg>`;
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
  };

  const resolveMarkdownURL = (src: string): string => {
    if (!src || /^(?:https?:|data:|blob:|weibeiimage:)/i.test(src)) return src;
    try {
      const resolved = new URL(
        src,
        currentMarkdownBaseURL || window.location.href,
      ).href;
      return /^file:/i.test(resolved) ? localImageURL(resolved) : resolved;
    } catch {
      return src;
    }
  };

  const documentImageSources = (state: EditorState): string[] => {
    const sources: string[] = [];
    state.doc.descendants((node) => {
      if (node.type.name === "image" && typeof node.attrs.src === "string")
        sources.push(node.attrs.src);
      return true;
    });
    return sources;
  };

  const resolveEditorImages = (view: EditorView): void => {
    const sources = documentImageSources(view.state);
    const images = Array.from(
      view.dom.querySelectorAll<HTMLImageElement>("img"),
    );
    images.forEach((image, index) => {
      const source = sources[index];
      if (!source) return;
      const resolved = resolveMarkdownURL(source);
      const { alt, size } = parseMarkdownImageAlt(
        image.getAttribute("alt") || "",
      );
      if (alt) image.setAttribute("alt", alt);
      applyImageSize(image, size);
      image.dataset.weibeiMarkdownSrc = source;
      if (!image.dataset.weibeiImageEventsBound) {
        image.dataset.weibeiImageEventsBound = "true";
        image.addEventListener("error", () => {
          image.dataset.weibeiImageMissingFor =
            image.dataset.weibeiResolvedSrc || image.getAttribute("src") || "";
          image.dataset.weibeiImagePlaceholder = "true";
          image.classList.add("weibei-image-missing");
          image.setAttribute("src", missingImageURL());
        });
        image.addEventListener("load", () => {
          if (image.dataset.weibeiImagePlaceholder === "true") return;
          image.classList.remove("weibei-image-missing");
        });
      }
      if (
        image.dataset.weibeiImageMissingFor === resolved &&
        image.dataset.weibeiImagePlaceholder === "true"
      ) {
        return;
      }
      if (resolved && image.getAttribute("src") !== resolved) {
        image.dataset.weibeiResolvedSrc = resolved;
        delete image.dataset.weibeiImagePlaceholder;
        image.classList.remove("weibei-image-missing");
        image.setAttribute("src", resolved);
      }
    });
  };

  const scheduleImageResolution = (view: EditorView): void => {
    window.cancelAnimationFrame(imageRefreshFrame);
    imageRefreshFrame = window.requestAnimationFrame(() =>
      resolveEditorImages(view),
    );
  };

  const refreshRenderedImages = (): void => {
    const editor = getEditor();
    if (!editor) return;
    editor.action((ctx) => scheduleImageResolution(ctx.get(editorViewCtx)));
  };

  const requestAttachment = async (file: File): Promise<SavedImage> => {
    const documentID = bridge.getDocumentID();
    const { alt, src } = await readImageAsBase64(file);
    if (documentID !== bridge.getDocumentID()) {
      throw new DOMException("Document changed", "AbortError");
    }
    if (!bridge.hasHandler("imageAttachmentRequested")) {
      return { alt, src };
    }
    const id = `attachment-${Date.now()}-${(attachmentRequestID += 1)}`;
    return new Promise<SavedImage>((resolve, reject) => {
      pendingAttachments.set(id, {
        resolve,
        reject,
        documentID,
      });
      bridge.post("imageAttachmentRequested", {
        id,
        name: file.name || alt || "image",
        mime: file.type || "image/png",
        dataURL: src,
      });
      window.setTimeout(() => {
        if (!pendingAttachments.has(id)) return;
        pendingAttachments.delete(id);
        reject(new Error("Attachment save timed out"));
      }, 15000);
    });
  };

  const localImageUploader = async (
    files: FileList,
    schema: Schema,
  ): Promise<ProseMirrorNode[]> => {
    if (!isEditable()) return [];
    const images: File[] = [];
    for (let i = 0; i < files.length; i += 1) {
      const file = files.item(i);
      if (file && file.type.includes("image")) images.push(file);
    }
    const imageNode = schema.nodes.image;
    if (!imageNode || images.length === 0) return [];
    const saved = await Promise.all(images.map(requestAttachment));
    return saved
      .map(({ alt, src }) => imageNode.createAndFill({ alt, src }))
      .filter((node): node is ProseMirrorNode => node !== null);
  };

  const imageFilesFromItems = (
    items: DataTransferItemList | null | undefined,
  ): File[] =>
    Array.from(items || [])
      .map((item) => item.getAsFile())
      .filter((file): file is File => Boolean(file?.type.includes("image")));

  const markdownImage = ({ alt, src }: SavedImage): string => {
    const safeAlt =
      (alt || "image").replace(/[\[\]\n\r]/g, " ").trim() || "image";
    const safeSrc = String(src || "")
      .replace(/\s/g, "%20")
      .replace(/\)/g, "%29");
    return `![${safeAlt}](${safeSrc})`;
  };

  const insertImageFiles = async (files: File[]): Promise<void> => {
    if (!isEditable()) return;
    const saved = await Promise.all(files.map(requestAttachment));
    replaceSelection(saved.map(markdownImage).join("\n\n"));
  };

  /**
   * Resolves a native attachment request.
   */
  const resolveAttachment = (id: string, src: string, alt: string): void => {
    const pending = pendingAttachments.get(id);
    if (!pending) return;
    pendingAttachments.delete(id);
    if (pending.documentID !== bridge.getDocumentID()) {
      pending.reject(new DOMException("Document changed", "AbortError"));
      return;
    }
    pending.resolve({ src, alt });
  };

  /**
   * Rejects a native attachment request.
   */
  const rejectAttachment = (id: string, message?: string): void => {
    const pending = pendingAttachments.get(id);
    if (!pending) return;
    pendingAttachments.delete(id);
    pending.reject(new Error(message || "Attachment save failed"));
  };

  /**
   * Discards a native attachment response that belongs to a previous document.
   *
   * @param id - Native attachment request identifier
   * @returns Whether a pending request was discarded
   */
  const discardAttachment = (id: string): boolean => {
    const pending = pendingAttachments.get(id);
    if (!pending) return false;
    pendingAttachments.delete(id);
    pending.reject(new DOMException("Document changed", "AbortError"));
    return true;
  };

  /**
   * Aborts all outstanding attachment requests before replacing the document.
   *
   * @returns Number of discarded requests
   */
  const discardAllAttachments = (): number => {
    const pending = Array.from(pendingAttachments.values());
    pendingAttachments.clear();
    pending.forEach(({ reject }) =>
      reject(new DOMException("Document changed", "AbortError")),
    );
    return pending.length;
  };

  /**
   * Changes the base URL used for relative Markdown images.
   */
  const setMarkdownBaseURL = (next: string): void => {
    currentMarkdownBaseURL = next || "";
    refreshRenderedImages();
  };

  /**
   * Refreshes missing-image placeholders after a theme change.
   */
  const refreshMissingPlaceholders = (): void => {
    document
      .querySelectorAll<HTMLImageElement>(
        'img[data-weibei-image-placeholder="true"]',
      )
      .forEach((image) => {
        image.setAttribute("src", missingImageURL());
      });
  };

  return {
    discardAllAttachments,
    discardAttachment,
    insertImageFiles,
    imageFilesFromItems,
    localImageUploader,
    missingImageURL,
    rejectAttachment,
    refreshMissingPlaceholders,
    refreshRenderedImages,
    resolveAttachment,
    resolveMarkdownURL,
    scheduleImageResolution,
    setMarkdownBaseURL,
  };
}
