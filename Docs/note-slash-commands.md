# 笔记 Slash 命令

在每个可编辑普通空白行的行首输入 `/`，可使用 13 个块命令：`/h1`、`/h2`、`/h3`、`/bullet_list`、`/ordered_list`、`/task_list`、`/quote`、`/callout`、`/code`、`/divider`、`/table`、`/image` 和 `/mermaid`。schema 允许的引用块空白行同样可用；已有文字、列表、表格、代码块和公式块不会触发。中文名称与拼音缩写同样可以筛选。

别名是单个 token；例如 `/code block` 与 `/ordered list` 不受支持。表格默认 3×3，行数范围为 1–20、列数范围为 1–12。每次命令替换是一次撤销操作。

图片命令会打开 macOS 图片选择器，支持 PNG、JPEG、GIF、WebP、TIFF 和 HEIC。取消或保存失败会保留原 `/image`；若期间切换笔记，旧请求会被静默丢弃。Undo 仅恢复 Markdown 引用，不会删除已经保存的附件。

代码块右上角可编辑语言；输入仅采用第一个非空白 token（最多 32 字符）。切换笔记或替换外部内容后，旧控件不会写入新内容。空代码块可用 Backspace/Delete 还原为段落；普通与 Mermaid 代码块可在终端行用右箭头或下箭头退出。只读模式会禁用语言输入框。Slash 菜单提供 VoiceOver listbox 状态与当前命令播报。
