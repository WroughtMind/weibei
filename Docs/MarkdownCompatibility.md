# 魏碑 Markdown / Obsidian 兼容矩阵

状态口径：支持 = 写作、阅读/预览、保存重开都保留；部分支持 = 可读可保存，但 Obsidian 的完整行为还没做完；不支持 = 有可见退路或按代码块/普通文本保留。

| 语法 | 状态 | 当前口径 |
| --- | --- | --- |
| CommonMark 标题/段落/强调/引用/列表/代码/分割线 | 支持 | 由 Milkdown commonmark 处理 |
| GFM 表格/任务列表/删除线/普通脚注 | 支持 | 由 Milkdown gfm 处理 |
| `==高亮==` | 支持 | 魏碑装饰，原 Markdown 保留 |
| `%%注释%%` | 部分支持 | 写作弱显示，阅读/预览隐藏；跨复杂节点的块注释后续补 |
| `[[Note]]` | 支持 | 点击/键盘打开或创建对应笔记 |
| `[[Note|Alias]]` | 支持 | 显示 alias，打开 Note |
| `[[Note\|Alias]]` | 支持 | 表格内可用转义竖线保存语法，点击仍打开 Note |
| `[[Note#Heading]]` / `[[Note#^block-id]]` | 部分支持 | 打开 Note；精确跳到标题/块后续补 |
| `[[#Heading]]` / `[[^^block search]]` | 部分支持 | 保留为内部链接样式；当前不做跨文档定位 |
| 行尾/独立行 `^block-id` | 部分支持 | 识别和弱样式；反链/块级定位后续补 |
| `![[image.png]]` / `![[image.png|100]]` | 部分支持 | 本地图片嵌入预览和尺寸；附件解析沿当前 Markdown 基准目录 |
| `![[Note]]` / `![[Note#Heading]]` | 部分支持 | 显示嵌入占位，完整笔记片段渲染后续补 |
| `![alt|100](url)` / `![alt|100x145](url)` | 支持 | 图片按 alt 尺寸约束显示，原 Markdown 保留 |
| Obsidian Callout 类型 | 支持 | note/tip/important/warning/caution/summary/abstract/info/success/failure/danger/bug/example/question/quote/todo |
| Callout `+` / `-` 折叠标记 | 支持 | `-` 在只读阅读/预览中默认折叠并可点击展开；写作态保留正文可编辑 |
| `$...$` / `$$...$$` 数学 | 支持 | KaTeX 渲染；错误以 KaTeX 错误样式显示 |
| 数学插入命令 | 支持 | 命令面板插入行内/块级/矩阵公式，块级公式按块结构落位 |
| 普通金额 `$5` | 支持 | 验收样例覆盖，不应误伤 |
| Mermaid 代码块 | 支持 | `mermaid` 渲染为 SVG；源码保留可编辑，解析错误显示可见提示 |
| Frontmatter / Properties | 部分支持 | 保存不丢；显示本地化只读属性条；可编辑属性面板后续补 |
| `#tag` / `#nested/tag` | 部分支持 | 标签样式识别；课程目录搜索可按笔记标签命中；独立标签索引/反链后续补 |
| HTML | 部分支持 | 按 Markdown 内联 HTML 能力保留；不承诺在 HTML 内继续解析 Markdown |
