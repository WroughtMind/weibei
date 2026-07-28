import { editorViewCtx } from "@milkdown/kit/core";
import type { Node as ProseMirrorNode } from "@milkdown/kit/prose/model";
import { Decoration } from "@milkdown/kit/prose/view";
import mermaid from "mermaid";
import Prism from "prismjs";
import "prismjs/components/prism-bash";
import "prismjs/components/prism-css";
import "prismjs/components/prism-java";
import "prismjs/components/prism-json";
import "prismjs/components/prism-jsx";
import "prismjs/components/prism-markdown";
import "prismjs/components/prism-python";
import "prismjs/components/prism-r";
import "prismjs/components/prism-ruby";
import "prismjs/components/prism-rust";
import "prismjs/components/prism-sql";
import "prismjs/components/prism-swift";
import "prismjs/components/prism-tsx";
import "prismjs/components/prism-typescript";
import "prismjs/components/prism-yaml";

import type { EditorLabel, GetEditor } from "../types.js";

type PrismToken =
  | string
  | {
      alias?: string | string[];
      content: PrismToken | PrismToken[];
      type: string;
    };

type AddRangeDecoration = (
  decorations: Decoration[],
  from: number,
  to: number,
  className: string,
) => void;

interface CodeRenderingDependencies {
  editorLabel: EditorLabel;
  isEditable: () => boolean;
  getEditor: GetEditor;
  addRangeDecoration?: AddRangeDecoration;
}

/**
 * Creates code, Mermaid, Prism, and KaTeX rendering helpers.
 *
 * @param dependencies - Rendering dependencies
 * @returns Code rendering API
 */
export function createCodeRendering({
  editorLabel,
  isEditable,
  getEditor,
  addRangeDecoration = (decorations, from, to, className) => {
    if (to <= from) return;
    decorations.push(Decoration.inline(from, to, { class: className }));
  },
}: CodeRenderingDependencies) {
  let mermaidRenderID = 0;
  const mermaidWidget = (source: string): HTMLDivElement => {
    const container = document.createElement("div");
    container.className = "weibei-mermaid-render";
    container.textContent = editorLabel("mermaidRendering");
    window.setTimeout(async () => {
      if (!container.isConnected) return;
      try {
        const id = `weibei-mermaid-${(mermaidRenderID += 1)}`;
        const { svg, bindFunctions } = await mermaid.render(
          id,
          source,
          container,
        );
        if (!container.isConnected) return;
        container.innerHTML = svg;
        bindFunctions?.(container);
        container.dataset.rendered = "true";
      } catch (error) {
        if (!container.isConnected) return;
        container.classList.add("weibei-mermaid-error");
        const message =
          error instanceof Error
            ? error.message
            : typeof error === "object" &&
                error !== null &&
                "message" in error &&
                typeof error.message === "string"
              ? error.message
              : String(error);
        container.textContent = editorLabel("mermaidFailed", {
          value: message,
        });
      }
    }, 0);
    return container;
  };

  const decorateMermaidBlock = (
    decorations: Decoration[],
    node: ProseMirrorNode,
    pos: number,
  ): boolean => {
    if (normalizeLanguage(node.attrs.language || "") !== "mermaid")
      return false;
    decorations.push(
      Decoration.node(pos, pos + node.nodeSize, {
        class: "weibei-code-block weibei-mermaid-block",
        "data-language": "mermaid",
      }),
    );
    const source = node.textContent.trim();
    if (source) {
      decorations.push(
        Decoration.widget(
          pos + node.nodeSize,
          () => mermaidWidget(node.textContent),
          { side: -1, key: `weibei-mermaid:${pos}:${node.textContent}` },
        ),
      );
    }
    return true;
  };

  const normalizeLanguage = (language: string): string => {
    const key = (language || "").trim().toLowerCase();
    const aliases: Record<string, string> = {
      js: "javascript",
      jsx: "jsx",
      ts: "typescript",
      tsx: "tsx",
      py: "python",
      rb: "ruby",
      sh: "bash",
      shell: "bash",
      zsh: "bash",
      md: "markdown",
      yml: "yaml",
    };
    return aliases[key] || key;
  };

  const tokenLength = (token: PrismToken): number => {
    if (typeof token === "string") return token.length;
    if (Array.isArray(token.content))
      return token.content.reduce((sum, child) => sum + tokenLength(child), 0);
    return String(token.content || "").length;
  };

  const tokenClass = (token: Exclude<PrismToken, string>): string => {
    const aliases = Array.isArray(token.alias)
      ? token.alias
      : token.alias
        ? [token.alias]
        : [];
    return ["weibei-prism-token", "token", token.type, ...aliases]
      .filter(Boolean)
      .join(" ");
  };

  const addTokenDecorations = (
    decorations: Decoration[],
    tokens: PrismToken[],
    start: number,
  ): void => {
    let cursor = start;
    for (const token of tokens) {
      const length = tokenLength(token);
      if (typeof token !== "string" && length > 0) {
        addRangeDecoration(
          decorations,
          cursor,
          cursor + length,
          tokenClass(token),
        );
        if (Array.isArray(token.content)) {
          addTokenDecorations(decorations, token.content, cursor);
        }
      }
      cursor += length;
    }
  };

  const decorateCodeBlock = (
    decorations: Decoration[],
    node: ProseMirrorNode,
    pos: number,
  ): void => {
    const language = normalizeLanguage(node.attrs.language || "");
    if (!language || !Prism.languages[language]) return;
    try {
      addTokenDecorations(
        decorations,
        Prism.tokenize(
          node.textContent,
          Prism.languages[language],
        ) as PrismToken[],
        pos + 1,
      );
    } catch {
      // Prism should not be allowed to break editing.
    }
  };

  /**
   * Adds an editable language field to a fenced code block and writes changes to its node attributes.
   *
   * @param decorations - Decoration collection for the current document
   * @param node - Code block node
   * @param pos - Code block position
   */
  const decorateCodeLanguageEditor = (
    decorations: Decoration[],
    node: ProseMirrorNode,
    pos: number,
  ): void => {
    const language = String(node.attrs.language || "");
    decorations.push(
      Decoration.widget(
        pos + 1,
        () => {
          const input = document.createElement("input");
          input.type = "text";
          input.className = "weibei-code-language-input";
          input.value = language;
          input.placeholder = editorLabel("codeLanguagePlaceholder");
          input.setAttribute("aria-label", editorLabel("codeLanguage"));
          input.setAttribute("autocomplete", "off");
          input.setAttribute("autocapitalize", "none");
          input.setAttribute("spellcheck", "false");
          input.maxLength = 32;

          const commit = () => {
            const editor = getEditor();
            if (!isEditable() || !editor) {
              input.value = language;
              return;
            }
            const nextLanguage = input.value.trim().split(/\s+/u)[0] || "";
            input.value = nextLanguage;
            if (nextLanguage === language) return;
            editor.action((ctx) => {
              const view = ctx.get(editorViewCtx);
              const currentNode = view.state.doc.nodeAt(pos);
              if (currentNode?.type.name !== "code_block") return;
              view.dispatch(
                view.state.tr.setNodeMarkup(pos, undefined, {
                  ...currentNode.attrs,
                  language: nextLanguage,
                }),
              );
            });
          };

          input.addEventListener("change", commit);
          input.addEventListener("blur", commit);
          input.addEventListener("keydown", (event) => {
            if (event.key === "Escape") input.value = language;
            if (event.key !== "Enter" && event.key !== "Escape") return;
            event.preventDefault();
            commit();
            input.blur();
            window.setTimeout(() => {
              const editor = getEditor();
              if (!editor) return;
              editor.action((ctx) => ctx.get(editorViewCtx).focus());
            }, 0);
          });
          return input;
        },
        {
          side: -1,
          key: `weibei-code-language:${pos}:${language}`,
          stopEvent: (event) => event.target instanceof HTMLInputElement,
        },
      ),
    );
  };
  const annotateMathErrors = (): void => {
    window.requestAnimationFrame(() => {
      document
        .querySelectorAll(".ProseMirror .katex-error")
        .forEach((element) => {
          if (element.getAttribute("title")) return;
          element.setAttribute("title", editorLabel("mathError"));
        });
    });
  };

  return {
    annotateMathErrors,
    decorateCodeBlock,
    decorateCodeLanguageEditor,
    decorateMermaidBlock,
  };
}
