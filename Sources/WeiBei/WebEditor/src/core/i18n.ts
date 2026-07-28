export type InterfaceLanguage = "zh-Hans" | "en";
type LabelDictionary = Record<string, string>;

/**
 * Normalizes the host language to one of the editor's supported locales.
 *
 * @param value - Host-provided language identifier
 * @returns Supported editor locale
 */
export const normalizeInterfaceLanguage = (
  value: string | undefined,
): InterfaceLanguage => (value === "en" ? "en" : "zh-Hans");
let currentLanguage = normalizeInterfaceLanguage("zh-Hans");
export const calloutLabels: Record<InterfaceLanguage, LabelDictionary> = {
  "zh-Hans": {
    note: "札记",
    tip: "提示",
    important: "重点",
    warning: "留心",
    caution: "谨慎",
    summary: "提要",
    abstract: "摘要",
    quote: "引文",
    question: "问题",
    example: "例子",
    info: "信息",
    success: "可行",
    failure: "失败",
    danger: "风险",
    bug: "问题",
    todo: "待办",
  },
  en: {
    note: "Note",
    tip: "Tip",
    important: "Important",
    warning: "Warning",
    caution: "Caution",
    summary: "Summary",
    abstract: "Abstract",
    quote: "Quote",
    question: "Question",
    example: "Example",
    info: "Info",
    success: "Success",
    failure: "Failure",
    danger: "Danger",
    bug: "Bug",
    todo: "Todo",
  },
};
/**
 * Returns the localized title for an Obsidian callout type.
 *
 * @param type - Normalized callout type
 * @returns Localized callout title
 */
export const calloutLabel = (type: string): string =>
  calloutLabels[currentLanguage][type] ||
  calloutLabels["zh-Hans"][type] ||
  type;
export const editorLabels: Record<InterfaceLanguage, LabelDictionary> = {
  "zh-Hans": {
    properties: "属性",
    bootFailed: "Milkdown 初始化失败",
    imageMissing: "图片未找到",
    inlineFootnote: "行内脚注：{value}",
    openOrCreateNote: "打开或创建笔记：{value}",
    openSource: "打开来源：{value}",
    embed: "嵌入：{value}",
    mermaidRendering: "正在渲染 Mermaid 图表...",
    mermaidFailed: "Mermaid 图表未解析\n{value}",
    mathError:
      "公式没有通过 KaTeX 解析。常用写法：x_i、x^{2}、\\frac{a}{b}、\\begin{bmatrix}...\\end{bmatrix}",
    uploadingImage: "正在收纳图片...",
    slashNoResults: "没有匹配命令",
    slashStructure: "结构",
    slashLists: "列表",
    slashContent: "内容",
    slashRichContent: "丰富内容",
    slashHeading1: "一级标题",
    slashHeading2: "二级标题",
    slashHeading3: "三级标题",
    slashBulletList: "无序列表",
    slashOrderedList: "有序列表",
    slashTaskList: "待办列表",
    slashQuote: "引用",
    slashCallout: "提示块",
    slashCode: "代码块",
    slashDivider: "分隔线",
    slashTable: "表格",
    slashImage: "图片",
    slashMermaid: "Mermaid 图表",
    slashRows: "行",
    slashColumns: "列",
    slashInsertTable: "插入表格",
    codeLanguage: "代码语言",
    codeLanguagePlaceholder: "语言",
  },
  en: {
    properties: "Properties",
    bootFailed: "Milkdown failed to initialize",
    imageMissing: "Image not found",
    inlineFootnote: "Inline footnote: {value}",
    openOrCreateNote: "Open or create note: {value}",
    openSource: "Open source: {value}",
    embed: "Embed: {value}",
    mermaidRendering: "Rendering Mermaid diagram...",
    mermaidFailed: "Mermaid diagram did not parse\n{value}",
    mathError:
      "KaTeX could not parse this formula. Common forms: x_i, x^{2}, \\frac{a}{b}, \\begin{bmatrix}...\\end{bmatrix}",
    uploadingImage: "Saving image...",
    slashNoResults: "No matching commands",
    slashStructure: "Structure",
    slashLists: "Lists",
    slashContent: "Content",
    slashRichContent: "Rich content",
    slashHeading1: "Heading 1",
    slashHeading2: "Heading 2",
    slashHeading3: "Heading 3",
    slashBulletList: "Bulleted list",
    slashOrderedList: "Numbered list",
    slashTaskList: "To-do list",
    slashQuote: "Quote",
    slashCallout: "Callout",
    slashCode: "Code block",
    slashDivider: "Divider",
    slashTable: "Table",
    slashImage: "Image",
    slashMermaid: "Mermaid diagram",
    slashRows: "Rows",
    slashColumns: "Columns",
    slashInsertTable: "Insert table",
    codeLanguage: "Code language",
    codeLanguagePlaceholder: "Language",
  },
};
/**
 * Formats a localized editor label.
 *
 * @param key - Label key
 * @param values - Template substitutions
 * @returns Localized label
 */
export const editorLabel = (
  key: string,
  values: Record<string, unknown> = {},
): string => {
  let text =
    editorLabels[currentLanguage][key] || editorLabels["zh-Hans"][key] || key;
  for (const [name, value] of Object.entries(values)) {
    text = text.split(`{${name}}`).join(String(value));
  }
  return text;
};
/**
 * Returns the localized frontmatter panel title.
 *
 * @returns Frontmatter panel title
 */
export const frontmatterLabel = (): string => editorLabel("properties");

/**
 * Updates the interface language used by editor labels.
 *
 * @param next - Requested interface language
 * @returns Normalized language
 */
export function setInterfaceLanguage(
  next: string | undefined,
): InterfaceLanguage {
  currentLanguage = normalizeInterfaceLanguage(next);
  return currentLanguage;
}

/**
 * Returns the active interface language.
 *
 * @returns Active language
 */
export function getInterfaceLanguage(): InterfaceLanguage {
  return currentLanguage;
}
