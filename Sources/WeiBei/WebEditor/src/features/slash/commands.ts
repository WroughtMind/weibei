import { Fragment } from "@milkdown/kit/prose/model";
import type {
  Node as ProseMirrorNode,
  Schema,
} from "@milkdown/kit/prose/model";
import { TextSelection } from "@milkdown/kit/prose/state";
import type { EditorView } from "@milkdown/kit/prose/view";

import { editorLabels } from "../../core/i18n.js";

export interface SlashGroup {
  id: string;
  label: string;
}

export interface SlashCommand {
  id: string;
  group: string;
  label: string;
  aliases: string[];
}

export interface SlashContext {
  query: string;
  source: string;
  blockFrom: number;
  blockTo: number;
  index: number;
  container: ProseMirrorNode;
  key: string;
}

export interface SlashReplacement {
  content: Fragment;
  selectionOffset: number;
}

export interface SlashReplacementOptions {
  rows?: number;
  columns?: number;
  src?: string;
  alt?: string;
}

export const slashGroups: SlashGroup[] = [
  { id: "structure", label: "slashStructure" },
  { id: "lists", label: "slashLists" },
  { id: "content", label: "slashContent" },
  { id: "rich", label: "slashRichContent" },
];

export const slashCommands: SlashCommand[] = [
  {
    id: "heading1",
    group: "structure",
    label: "slashHeading1",
    aliases: ["h1", "heading 1", "一级", "标题1"],
  },
  {
    id: "heading2",
    group: "structure",
    label: "slashHeading2",
    aliases: ["h2", "heading 2", "二级", "标题2"],
  },
  {
    id: "heading3",
    group: "structure",
    label: "slashHeading3",
    aliases: ["h3", "heading 3", "三级", "标题3"],
  },
  {
    id: "bulletList",
    group: "lists",
    label: "slashBulletList",
    aliases: [
      "bullet",
      "bulleted list",
      "unordered list",
      "ul",
      "无序",
      "项目符号",
    ],
  },
  {
    id: "orderedList",
    group: "lists",
    label: "slashOrderedList",
    aliases: ["numbered list", "ordered list", "ol", "有序", "编号"],
  },
  {
    id: "taskList",
    group: "lists",
    label: "slashTaskList",
    aliases: ["todo", "task", "task list", "checklist", "待办", "任务"],
  },
  {
    id: "quote",
    group: "lists",
    label: "slashQuote",
    aliases: ["quote", "blockquote", "引用"],
  },
  {
    id: "callout",
    group: "content",
    label: "slashCallout",
    aliases: ["callout", "note", "提示", "札记"],
  },
  {
    id: "code",
    group: "content",
    label: "slashCode",
    aliases: ["code", "code block", "代码"],
  },
  {
    id: "divider",
    group: "content",
    label: "slashDivider",
    aliases: ["divider", "horizontal rule", "hr", "分隔", "横线"],
  },
  {
    id: "table",
    group: "rich",
    label: "slashTable",
    aliases: ["table", "grid", "表格"],
  },
  {
    id: "image",
    group: "rich",
    label: "slashImage",
    aliases: ["image", "photo", "picture", "图片", "照片"],
  },
  {
    id: "mermaid",
    group: "rich",
    label: "slashMermaid",
    aliases: ["mermaid", "diagram", "flowchart", "图表", "流程图"],
  },
];
const slashExcludedAncestors = new Set([
  "list_item",
  "task_list_item",
  "table",
  "table_row",
  "table_header_row",
  "table_cell",
  "table_header",
  "code_block",
  "math_block",
]);

/**
 * Returns the active slash query when the caret is in an eligible empty-origin paragraph.
 *
 * @param view - Current ProseMirror view
 * @returns Slash context when the caret is eligible
 */
export const slashContextForView = (
  view: EditorView,
  isEditable: boolean,
): SlashContext | null => {
  if (!isEditable || view.composing) return null;
  const { selection } = view.state;
  if (!(selection instanceof TextSelection) || !selection.empty) return null;
  const { $from } = selection;
  if (
    $from.parent.type.name !== "paragraph" ||
    $from.parentOffset !== $from.parent.content.size
  )
    return null;
  for (let depth = $from.depth; depth > 0; depth -= 1) {
    if (slashExcludedAncestors.has($from.node(depth).type.name)) return null;
  }
  const source = $from.parent.textContent || "";
  const match = source.match(/^\/([^\s/]*)$/u);
  if (!match) return null;
  const paragraphDepth = $from.depth;
  const containerDepth = paragraphDepth - 1;
  const blockFrom = $from.before(paragraphDepth);
  const blockTo = $from.after(paragraphDepth);
  return {
    query: match[1] || "",
    source,
    blockFrom,
    blockTo,
    index: $from.index(containerDepth),
    container: $from.node(containerDepth),
    key: `${blockFrom}:${blockTo}:${source}`,
  };
};

/**
 * Builds a schema-valid block replacement and the caret position within it.
 *
 * @param commandID - Slash command identifier
 * @param schema - Active editor schema
 * @param options - Command-specific dimensions or image metadata
 * @returns Schema-valid replacement and its caret offset
 */
export const slashReplacement = (
  commandID: string,
  schema: Schema,
  options: SlashReplacementOptions = {},
): SlashReplacement | null => {
  const paragraph = schema.nodes.paragraph;
  if (!paragraph) return null;
  if (commandID.startsWith("heading")) {
    const heading = schema.nodes.heading;
    const level = Number(commandID.at(-1));
    if (!heading || !Number.isFinite(level)) return null;
    return {
      content: Fragment.from(heading.create({ level })),
      selectionOffset: 1,
    };
  }
  if (
    commandID === "bulletList" ||
    commandID === "orderedList" ||
    commandID === "taskList"
  ) {
    const list =
      commandID === "orderedList"
        ? schema.nodes.ordered_list
        : schema.nodes.bullet_list;
    const listItem = schema.nodes.list_item;
    if (!list || !listItem) return null;
    const item = listItem.createAndFill(
      commandID === "taskList" ? { checked: false } : null,
      paragraph.create(),
    );
    const listNode = item ? list.createAndFill(null, item) : null;
    return listNode
      ? { content: Fragment.from(listNode), selectionOffset: 3 }
      : null;
  }
  if (commandID === "quote") {
    const blockquote = schema.nodes.blockquote || schema.nodes.block_quote;
    if (!blockquote) return null;
    return {
      content: Fragment.from(blockquote.create(null, paragraph.create())),
      selectionOffset: 2,
    };
  }
  if (commandID === "callout") {
    const blockquote = schema.nodes.blockquote || schema.nodes.block_quote;
    if (!blockquote) return null;
    const header = paragraph.create(null, schema.text("[!note]"));
    const callout = blockquote.create(null, [header, paragraph.create()]);
    return {
      content: Fragment.from(callout),
      selectionOffset: header.nodeSize + 2,
    };
  }
  if (commandID === "code" || commandID === "mermaid") {
    const codeBlock = schema.nodes.code_block;
    if (!codeBlock) return null;
    const language = commandID === "mermaid" ? "mermaid" : "";
    return {
      content: Fragment.from(codeBlock.create({ language })),
      selectionOffset: 1,
    };
  }
  if (commandID === "divider") {
    const divider = schema.nodes.hr || schema.nodes.horizontal_rule;
    if (!divider) return null;
    const dividerNode = divider.create();
    return {
      content: Fragment.from([dividerNode, paragraph.create()]),
      selectionOffset: dividerNode.nodeSize + 1,
    };
  }
  if (commandID === "table") {
    const table = schema.nodes.table;
    const headerRow = schema.nodes.table_header_row;
    const row = schema.nodes.table_row;
    const headerCell = schema.nodes.table_header;
    const cell = schema.nodes.table_cell;
    if (!table || !headerRow || !row || !headerCell || !cell) return null;
    const rows = Math.min(20, Math.max(1, Number(options.rows) || 3));
    const columns = Math.min(12, Math.max(1, Number(options.columns) || 3));
    const headerCells = Array.from({ length: columns }, () =>
      headerCell.createAndFill(),
    ).filter((node): node is ProseMirrorNode => node !== null);
    if (headerCells.length !== columns) return null;
    const bodyRows = Array.from({ length: rows - 1 }, () => {
      const cells = Array.from({ length: columns }, () =>
        cell.createAndFill(),
      ).filter((node): node is ProseMirrorNode => node !== null);
      return cells.length !== columns ? null : row.create(null, cells);
    }).filter((node): node is ProseMirrorNode => node !== null);
    if (bodyRows.length !== rows - 1) return null;
    const tableNode = table.create(null, [
      headerRow.create(null, headerCells),
      ...bodyRows,
    ]);
    return { content: Fragment.from(tableNode), selectionOffset: 4 };
  }
  if (commandID === "image") {
    const image = schema.nodes.image;
    if (!image || !options.src) return null;
    const imageNode = image.create({
      src: options.src,
      alt: options.alt || "image",
    });
    return {
      content: Fragment.from(paragraph.create(null, imageNode)),
      selectionOffset: 2,
    };
  }
  return null;
};

/**
 * Checks whether a command can replace the current paragraph without changing its parent container.
 *
 * @param command - Slash command specification
 * @param context - Active slash context
 * @param schema - Active editor schema
 * @returns Whether the current paragraph accepts the command
 */
export const slashCommandIsAllowed = (
  command: SlashCommand,
  context: SlashContext | null,
  schema: Schema,
): boolean => {
  if (!context) return false;
  if (command.id === "image") return Boolean(schema.nodes.image);
  const replacement = slashReplacement(command.id, schema, {
    rows: 3,
    columns: 3,
  });
  return Boolean(
    replacement &&
    context.container.canReplace(
      context.index,
      context.index + 1,
      replacement.content,
    ),
  );
};

/**
 * Filters commands using localized labels and stable bilingual aliases.
 *
 * @param query - Text after the slash
 * @param context - Active slash context
 * @param schema - Active editor schema
 * @returns Commands matching the current query and schema
 */
export const filteredSlashCommands = (
  query: string,
  context: SlashContext | null,
  schema: Schema,
): SlashCommand[] => {
  const normalized = String(query || "")
    .trim()
    .toLocaleLowerCase();
  return slashCommands.filter((command) => {
    if (!slashCommandIsAllowed(command, context, schema)) return false;
    if (!normalized) return true;
    const labels = [
      editorLabels["zh-Hans"][command.label],
      editorLabels.en[command.label],
      ...command.aliases,
    ]
      .filter(Boolean)
      .map((value) => String(value).toLocaleLowerCase());
    return labels.some((value) => value.includes(normalized));
  });
};
