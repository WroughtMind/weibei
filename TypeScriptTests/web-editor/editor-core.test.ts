import { afterEach, describe, expect, it, vi } from "vitest";

import { createBridge } from "../../Sources/WeiBei/WebEditor/src/core/bridge.js";
import {
  calloutLabel,
  editorLabel,
  getInterfaceLanguage,
  setInterfaceLanguage,
} from "../../Sources/WeiBei/WebEditor/src/core/i18n.js";
import {
  cleanSelectedText,
  normalizeHtmlBreaks,
  normalizeMarkdownOutput,
  splitFrontmatter,
  withFrontmatter,
} from "../../Sources/WeiBei/WebEditor/src/markdown/normalize.js";
import {
  parseImageSize,
  parseMarkdownImageAlt,
  parseObsidianEmbed,
  parseObsidianTarget,
} from "../../Sources/WeiBei/WebEditor/src/markdown/obsidian.js";
import { slashCommands } from "../../Sources/WeiBei/WebEditor/src/features/slash/commands.js";

afterEach(() => {
  setInterfaceLanguage("zh-Hans");
});

describe("WebEditor native bridge", () => {
  it("adds the current document identity to every native message", () => {
    const postMessage = vi.fn();
    const bridge = createBridge(
      { markdownChanged: { postMessage } },
      "document-a",
    );

    bridge.post("markdownChanged", { markdown: "# A" });
    bridge.setDocumentID("document-b");
    bridge.post("markdownChanged", { markdown: "# B" });

    expect(postMessage).toHaveBeenNthCalledWith(1, {
      markdown: "# A",
      documentID: "document-a",
    });
    expect(postMessage).toHaveBeenNthCalledWith(2, {
      markdown: "# B",
      documentID: "document-b",
    });
    expect(bridge.hasHandler("markdownChanged")).toBe(true);
  });
});

describe("WebEditor localization", () => {
  it("normalizes unsupported locales and formats placeholders", () => {
    expect(setInterfaceLanguage("fr")).toBe("zh-Hans");
    expect(calloutLabel("warning")).toBe("留心");

    expect(setInterfaceLanguage("en")).toBe("en");
    expect(getInterfaceLanguage()).toBe("en");
    expect(editorLabel("openSource", { value: "design.md" })).toBe(
      "Open source: design.md",
    );
  });

  it("uses a language-neutral code language placeholder", () => {
    expect(editorLabel("codeLanguagePlaceholder")).toBe("text");
    setInterfaceLanguage("en");
    expect(editorLabel("codeLanguagePlaceholder")).toBe("text");
  });
});

describe("WebEditor Slash command aliases", () => {
  it("publishes stable aliases without accepting whitespace forms", () => {
    const stableAliases = [
      "h1",
      "h2",
      "h3",
      "bullet_list",
      "ordered_list",
      "task_list",
      "quote",
      "callout",
      "code",
      "divider",
      "table",
      "image",
      "mermaid",
    ];

    expect(slashCommands).toHaveLength(13);
    expect(
      stableAliases.every((alias) =>
        slashCommands.some((command) => command.aliases.includes(alias)),
      ),
    ).toBe(true);
    expect(
      slashCommands
        .flatMap((command) => command.aliases)
        .some((alias) => /\s/u.test(alias)),
    ).toBe(false);
    expect(
      slashCommands.find((command) => command.id === "code")?.aliases,
    ).toContain("dmk");
    expect(
      slashCommands.find((command) => command.id === "orderedList")?.aliases,
    ).toContain("yxlb");
  });
});

describe("WebEditor Markdown normalization", () => {
  it("normalizes serialized syntax without changing code spans or fences", () => {
    const markdown = [
      "\\[\\[Design\\]\\] and `\\[\\[literal\\]\\]`",
      "",
      "```md",
      "\\[\\[fenced\\]\\]",
      "```",
    ].join("\n");

    expect(normalizeMarkdownOutput(markdown)).toBe(
      [
        "[[Design]] and `\\[\\[literal\\]\\]`",
        "",
        "```md",
        "\\[\\[fenced\\]\\]",
        "```",
      ].join("\n"),
    );
  });

  it("preserves frontmatter while normalizing the document body", () => {
    const document = "---\ntitle: Demo\ntags: [swift]\n---\n\nLine<br>next";
    const split = splitFrontmatter(document);

    expect(split.frontmatter).toBe("---\ntitle: Demo\ntags: [swift]\n---");
    expect(normalizeHtmlBreaks(split.body)).toBe("Line  \nnext");
    expect(withFrontmatter(split.frontmatter, "\\[\\[Note\\]\\]")).toBe(
      "---\ntitle: Demo\ntags: [swift]\n---\n\n[[Note]]",
    );
  });

  it("removes editor controls from selected Markdown context", () => {
    expect(
      cleanSelectedText(
        "> [!warning] Read [[Architecture|the design]] and ![[diagram.png|320x180]]",
      ),
    ).toBe("Read the design and diagram.png");
  });
});

describe("WebEditor Obsidian syntax", () => {
  it("parses aliases, headings, embeds, and image dimensions", () => {
    expect(parseObsidianTarget("Design#Decisions|Architecture")).toMatchObject({
      target: "Design#Decisions",
      noteTitle: "Design",
      display: "Architecture",
      alias: "Architecture",
    });
    expect(parseObsidianEmbed("diagram.png|Overview|640x360")).toEqual({
      target: "diagram.png",
      label: "Overview",
      size: { width: 640, height: 360 },
    });
    expect(parseMarkdownImageAlt("Diagram|480")).toEqual({
      alt: "Diagram",
      size: { width: 480, height: null },
    });
    expect(parseImageSize("0x20")).toEqual({ width: 1, height: 20 });
    expect(parseImageSize("wide")).toBeNull();
  });
});
