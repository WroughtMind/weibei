import type { Node as ProseMirrorNode } from "@milkdown/kit/prose/model";
import type { EditorState } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";
import type { DecorationAttrs } from "@milkdown/kit/prose/view";

import type { createCodeRendering } from "./code-rendering.js";
import type { createImageFeature } from "./images.js";
import {
  applyImageSize,
  imageTargetPattern,
  parseObsidianEmbed,
  parseObsidianTarget,
} from "../markdown/obsidian.js";
import type { EditorBridge, EditorLabel } from "../types.js";

interface DecorationFeatureDependencies {
  calloutLabel: (type: string) => string;
  codeRendering: ReturnType<typeof createCodeRendering>;
  images: ReturnType<typeof createImageFeature>;
  isEditable: () => boolean;
  label: EditorLabel;
  post: EditorBridge["post"];
}

interface CommentState {
  open: boolean;
}

/**
 * Creates WeiBei Markdown decorations and interactive link behavior.
 *
 * @param dependencies - Decoration dependencies
 * @returns Decoration feature API
 */
export function createDecorationFeature({
  calloutLabel,
  codeRendering,
  images,
  isEditable,
  label,
  post,
}: DecorationFeatureDependencies) {
  const { missingImageURL, resolveMarkdownURL } = images;

  const calloutTypes = new Set([
    "note",
    "tip",
    "important",
    "warning",
    "caution",
    "summary",
    "abstract",
    "quote",
    "question",
    "example",
    "info",
    "success",
    "failure",
    "danger",
    "bug",
    "todo",
  ]);
  const calloutTypePattern = "[A-Za-z][A-Za-z0-9_-]*";
  const calloutPrefixPattern = "(?:\\s*>\\s*)*\\s*";
  const calloutRegex = new RegExp(
    `^${calloutPrefixPattern}\\\\?\\[!(${calloutTypePattern})\\]([+-]?)(?:[ \\t]+([^\\n]+))?`,
    "i",
  );
  const calloutMarkerRegex = new RegExp(
    `^${calloutPrefixPattern}\\\\?\\[!(?:${calloutTypePattern})\\][+-]?\\s*`,
    "i",
  );
  const calloutHeadingRegex = new RegExp(
    `^${calloutPrefixPattern}\\\\?\\[!(?:${calloutTypePattern})\\][+-]?(?:[ \\t]+[^\\n]+)?$`,
    "i",
  );
  const selectedTextCalloutControlRegex = new RegExp(
    `(^|\\n)\\s*(?:>\\s*)*\\\\?\\[!(?:${calloutTypePattern})\\][+-]?[ \\t]*`,
    "gi",
  );
  const calloutHeaderText = (node: ProseMirrorNode): string => {
    const text = node.textBetween
      ? node.textBetween(0, node.content.size, "\n")
      : node.textContent || "";
    return (text.split("\n")[0] || "").trimStart();
  };
  const firstParagraphText = (node: ProseMirrorNode): string => {
    let first = "";
    node.descendants((child) => {
      if (first) return false;
      if (child.type?.name !== "paragraph") return true;
      const text = (child.textContent || "").trimStart();
      if (!text) return true;
      first = text;
      return false;
    });
    return first;
  };
  const calloutMatchForBlockquote = (
    node: ProseMirrorNode,
  ): RegExpMatchArray | null =>
    calloutHeaderText(node).match(calloutRegex) ||
    firstParagraphText(node).match(calloutRegex);
  const isBlockquoteType = (typeName: string): boolean =>
    typeName === "blockquote" || typeName === "block_quote";
  const decorateCalloutHeadingSource = (
    decorations: Decoration[],
    node: ProseMirrorNode,
    pos: number,
  ): void => {
    const text = node.textBetween
      ? node.textBetween(0, node.content.size, "")
      : node.textContent || "";
    const marker = text.match(calloutMarkerRegex);
    if (!marker) return;
    const contentStart = pos + 1;
    const markerEnd = contentStart + marker[0].length;
    addRangeDecoration(
      decorations,
      contentStart,
      markerEnd,
      "weibei-callout-marker",
    );

    const heading = text.match(calloutHeadingRegex);
    if (!heading) return;
    const titleEnd = contentStart + heading[0].length;
    if (titleEnd > markerEnd) {
      addRangeDecoration(
        decorations,
        markerEnd,
        titleEnd,
        "weibei-callout-heading-source",
      );
    }
  };
  const decorateLeakedCalloutControls = (
    decorations: Decoration[],
    text: string,
    pos: number,
  ): void => {
    for (const match of text.matchAll(selectedTextCalloutControlRegex)) {
      const lineBreakSize = match[1]?.length || 0;
      const from = pos + (match.index || 0) + lineBreakSize;
      const to = pos + (match.index || 0) + match[0].length;
      addRangeDecoration(decorations, from, to, "weibei-callout-marker");
    }
  };
  const addRangeDecoration = (
    decorations: Decoration[],
    from: number,
    to: number,
    className: string,
    attrs: DecorationAttrs = {},
  ): void => {
    if (to <= from) return;
    decorations.push(
      Decoration.inline(from, to, { ...attrs, class: className }),
    );
  };

  const isInsideNode = (
    state: EditorState,
    pos: number,
    typeName: string,
  ): boolean => {
    const resolved = state.doc.resolve(pos);
    for (let depth = resolved.depth; depth >= 0; depth -= 1) {
      if (resolved.node(depth).type.name === typeName) return true;
    }
    return false;
  };

  const decorateDelimitedInline = (
    decorations: Decoration[],
    text: string,
    pos: number,
    regex: RegExp,
    markerSize: number,
    className: string,
  ): void => {
    for (const match of text.matchAll(regex)) {
      const from = pos + (match.index || 0);
      const to = from + match[0].length;
      addRangeDecoration(
        decorations,
        from,
        from + markerSize,
        "weibei-md-marker",
      );
      addRangeDecoration(
        decorations,
        from + markerSize,
        to - markerSize,
        className,
      );
      addRangeDecoration(decorations, to - markerSize, to, "weibei-md-marker");
    }
  };

  const decorateInlineFootnotes = (
    decorations: Decoration[],
    text: string,
    pos: number,
  ): void => {
    for (const match of text.matchAll(/(^|[^\\])\^\[([^\]\n]+)\]/g)) {
      const prefixLength = match[1]?.length || 0;
      const content = match[2] || "";
      const from = pos + (match.index || 0) + prefixLength;
      const to = from + match[0].length - prefixLength;
      addRangeDecoration(decorations, from, from + 2, "weibei-md-marker");
      addRangeDecoration(
        decorations,
        from + 2,
        to - 1,
        "weibei-inline-footnote",
        {
          title: label("inlineFootnote", { value: content }),
          "aria-label": label("inlineFootnote", { value: content }),
        },
      );
      addRangeDecoration(decorations, to - 1, to, "weibei-md-marker");
    }
  };

  const decorateWikiLinks = (
    decorations: Decoration[],
    text: string,
    pos: number,
  ): void => {
    for (const match of text.matchAll(/\[\[([^\]\n]+)\]\]/g)) {
      const rawTarget = match[1];
      if (!rawTarget) continue;
      const index = match.index || 0;
      if (text[index - 1] === "!") continue;
      const from = pos + index;
      const to = from + match[0].length;
      const parsed = parseObsidianTarget(rawTarget);
      const title = parsed.noteTitle || parsed.target;
      const bridgeTitle = parsed.target || title;
      addRangeDecoration(decorations, from, from + 2, "weibei-md-marker");
      if (
        parsed.aliasRange &&
        parsed.aliasRange.end > parsed.aliasRange.start
      ) {
        addRangeDecoration(
          decorations,
          from + 2,
          from + 2 + parsed.aliasRange.start,
          "weibei-md-marker",
        );
        addRangeDecoration(
          decorations,
          from + 2 + parsed.aliasRange.start,
          from + 2 + parsed.aliasRange.end,
          "weibei-wikilink",
          {
            role: "link",
            tabindex: "0",
            title: label("openOrCreateNote", { value: title }),
            "data-wikilink-target": parsed.target,
            "data-wikilink-title": bridgeTitle,
          },
        );
        addRangeDecoration(
          decorations,
          from + 2 + parsed.aliasRange.end,
          to - 2,
          "weibei-md-marker",
        );
      } else {
        addRangeDecoration(decorations, from + 2, to - 2, "weibei-wikilink", {
          role: "link",
          tabindex: "0",
          title: label("openOrCreateNote", { value: title }),
          "data-wikilink-target": parsed.target,
          "data-wikilink-title": bridgeTitle,
        });
      }
      addRangeDecoration(decorations, to - 2, to, "weibei-md-marker");
    }
  };

  const decorateSourceReferences = (
    decorations: Decoration[],
    text: string,
    pos: number,
  ): void => {
    for (const match of text.matchAll(
      /(?:^|[\s`])((?:来源：|Source:)[^`\n]+)/g,
    )) {
      const reference = match[1];
      if (!reference) continue;
      const prefixLength = match[0].startsWith(reference) ? 0 : 1;
      const sourcePrefix = reference.startsWith("来源：")
        ? "来源："
        : "Source:";
      const from = pos + (match.index || 0) + prefixLength;
      const to = from + reference.length;
      addRangeDecoration(decorations, from, to, "weibei-source-reference", {
        role: "link",
        tabindex: "0",
        title: label("openSource", {
          value: reference.slice(sourcePrefix.length).trim(),
        }),
        "data-source-reference": reference,
      });
    }
  };

  const decorateObsidianEmbeds = (
    decorations: Decoration[],
    text: string,
    pos: number,
  ): void => {
    for (const match of text.matchAll(/!\[\[([^\]\n]+)\]\]/g)) {
      const rawTarget = match[1];
      if (!rawTarget) continue;
      const from = pos + (match.index || 0);
      const to = from + match[0].length;
      const embed = parseObsidianEmbed(rawTarget);
      addRangeDecoration(decorations, from, to, "weibei-embed-source");
      decorations.push(
        Decoration.widget(
          to,
          () => {
            if (imageTargetPattern.test(embed.target)) {
              const image = document.createElement("img");
              image.className = "weibei-embed-preview weibei-embed-image";
              image.alt = embed.target;
              image.src = resolveMarkdownURL(embed.target);
              applyImageSize(image, embed.size);
              image.addEventListener("error", () => {
                image.src = missingImageURL();
                image.classList.add("weibei-image-missing");
              });
              return image;
            }
            const chip = document.createElement("span");
            chip.className = "weibei-embed-preview weibei-embed-note";
            chip.textContent = label("embed", {
              value: embed.label || embed.target,
            });
            chip.setAttribute("role", "link");
            chip.setAttribute("tabindex", "0");
            chip.setAttribute(
              "title",
              label("openOrCreateNote", { value: embed.target }),
            );
            chip.dataset.wikilinkTarget = embed.target;
            chip.dataset.wikilinkTitle = embed.target;
            return chip;
          },
          { side: 1 },
        ),
      );
    }
  };

  const decorateComments = (
    decorations: Decoration[],
    text: string,
    pos: number,
    commentState: CommentState,
  ): void => {
    let cursor = 0;
    while (cursor < text.length) {
      if (commentState.open) {
        const end = text.indexOf("%%", cursor);
        if (end < 0) {
          addRangeDecoration(
            decorations,
            pos + cursor,
            pos + text.length,
            "weibei-comment",
          );
          return;
        }
        addRangeDecoration(
          decorations,
          pos + cursor,
          pos + end + 2,
          "weibei-comment",
        );
        commentState.open = false;
        cursor = end + 2;
        continue;
      }

      const start = text.indexOf("%%", cursor);
      if (start < 0) return;
      const end = text.indexOf("%%", start + 2);
      if (end < 0) {
        addRangeDecoration(
          decorations,
          pos + start,
          pos + text.length,
          "weibei-comment",
        );
        commentState.open = true;
        return;
      }
      addRangeDecoration(
        decorations,
        pos + start,
        pos + end + 2,
        "weibei-comment",
      );
      cursor = end + 2;
    }
  };

  const decorateTagsAndBlocks = (
    decorations: Decoration[],
    text: string,
    pos: number,
  ): void => {
    for (const match of text.matchAll(/(^|\s)(#[\p{L}\p{N}_/-]+)\b/gu)) {
      const prefix = match[1] ?? "";
      const tag = match[2];
      if (!tag) continue;
      const from = pos + (match.index || 0) + prefix.length;
      addRangeDecoration(decorations, from, from + tag.length, "weibei-tag");
    }
    for (const match of text.matchAll(/(^|\s)(\^[A-Za-z0-9-]+)\s*$/g)) {
      const prefix = match[1] ?? "";
      const blockID = match[2];
      if (!blockID) continue;
      const from = pos + (match.index || 0) + prefix.length;
      addRangeDecoration(
        decorations,
        from,
        from + blockID.length,
        "weibei-block-id",
      );
    }
  };

  const decorateHtmlBreaks = (
    decorations: Decoration[],
    text: string,
    pos: number,
  ): void => {
    for (const match of text.matchAll(/<br\s*\/?>/gi)) {
      const from = pos + (match.index || 0);
      const to = from + match[0].length;
      addRangeDecoration(decorations, from, to, "weibei-html-break-source");
      decorations.push(
        Decoration.widget(
          to,
          () => {
            const node = document.createElement("br");
            node.className = "weibei-html-break-preview";
            return node;
          },
          { side: 1 },
        ),
      );
    }
  };

  const wikiNavigationTitle = (raw: string): string => {
    const parsed = parseObsidianTarget(raw);
    return parsed.target || parsed.noteTitle;
  };

  const wikiTitleFromTarget = (target: EventTarget | null): string => {
    const link =
      target instanceof Element
        ? target.closest(
            ".weibei-wikilink, .weibei-embed-note[data-wikilink-title]",
          )
        : null;
    return (
      link?.getAttribute("data-wikilink-title") ||
      link?.textContent?.trim() ||
      ""
    );
  };

  const activateWikiLink = (target: EventTarget | null): boolean => {
    const title = wikiTitleFromTarget(target);
    if (!title) return false;
    post("wikiLinkActivated", { title });
    return true;
  };

  const sourceReferenceFromTarget = (target: EventTarget | null): string => {
    const link =
      target instanceof Element
        ? target.closest(".weibei-source-reference[data-source-reference]")
        : null;
    return link?.getAttribute("data-source-reference") || "";
  };

  const activateSourceReference = (target: EventTarget | null): boolean => {
    const reference = sourceReferenceFromTarget(target);
    if (!reference) return false;
    post("sourceReferenceActivated", { reference });
    return true;
  };

  const toggleFoldedCallout = (target: EventTarget | null): boolean => {
    if (isEditable() || !(target instanceof Element)) return false;
    const callout = target.closest(
      'blockquote.weibei-callout[data-callout-fold="-"]',
    );
    if (!callout) return false;
    callout.classList.toggle("weibei-callout-open");
    return true;
  };
  /**
   * Builds all editor decorations for the current document.
   *
   * @param state - Current editor state
   * @returns Current decoration set
   */
  const buildDecorations = (state: EditorState): DecorationSet => {
    const decorations: Decoration[] = [];
    const commentState = { open: false };

    state.doc.descendants((node, pos, parent) => {
      const typeName = node.type.name;
      const parentName = parent?.type?.name || "";

      if (isBlockquoteType(typeName)) {
        const match = calloutMatchForBlockquote(node);
        const matchedType = match?.[1];
        if (match && matchedType) {
          const calloutType = matchedType.toLowerCase();
          const calloutClass = calloutTypes.has(calloutType)
            ? `weibei-callout-${calloutType}`
            : `weibei-callout-${calloutType} weibei-callout-custom`;
          decorations.push(
            Decoration.node(pos, pos + node.nodeSize, {
              class: `weibei-callout weibei-callout-has-heading ${calloutClass}`,
              "data-callout": calloutType,
              "data-callout-fold": match[2] || "",
              "data-callout-title": (
                match[3] || calloutLabel(calloutType)
              ).trim(),
            }),
          );
        }
      }

      if (typeName === "paragraph" && isBlockquoteType(parentName)) {
        const calloutHeading = node.textContent.trimStart().match(calloutRegex);
        if (calloutHeading) {
          decorations.push(
            Decoration.node(pos, pos + node.nodeSize, {
              class: "weibei-callout-heading",
            }),
          );
          decorateCalloutHeadingSource(decorations, node, pos);
        }
      }

      if (typeName === "image" && node.attrs.src) {
        decorations.push(
          Decoration.node(pos, pos + node.nodeSize, {
            class: "weibei-image",
            src: resolveMarkdownURL(node.attrs.src),
          }),
        );
      }

      if (typeName === "code_block") {
        codeRendering.decorateCodeLanguageEditor(decorations, node, pos);
        if (codeRendering.decorateMermaidBlock(decorations, node, pos))
          return false;
        decorations.push(
          Decoration.node(pos, pos + node.nodeSize, {
            class: "weibei-code-block",
            "data-language": node.attrs.language || "",
          }),
        );
        codeRendering.decorateCodeBlock(decorations, node, pos);
        return false;
      }

      if (node.isText) {
        const textPos = pos;
        const text = node.text || "";
        const hasCodeMark = (node.marks || []).some((mark) =>
          mark.type.name.toLowerCase().includes("code"),
        );
        if (hasCodeMark) return true;
        const insideBlockquote =
          isInsideNode(state, textPos, "blockquote") ||
          isInsideNode(state, textPos, "block_quote");
        if (insideBlockquote)
          decorateLeakedCalloutControls(decorations, text, textPos);
        decorateDelimitedInline(
          decorations,
          text,
          textPos,
          /==([^=\n]+)==/g,
          2,
          "weibei-highlight",
        );
        decorateInlineFootnotes(decorations, text, textPos);
        decorateHtmlBreaks(decorations, text, textPos);
        decorateComments(decorations, text, textPos, commentState);
        decorateObsidianEmbeds(decorations, text, textPos);
        decorateWikiLinks(decorations, text, textPos);
        decorateSourceReferences(decorations, text, textPos);
        decorateTagsAndBlocks(decorations, text, textPos);
      }

      return true;
    });

    return DecorationSet.create(state.doc, decorations);
  };

  return {
    activateSourceReference,
    activateWikiLink,
    addRangeDecoration,
    buildDecorations,
    toggleFoldedCallout,
  };
}
