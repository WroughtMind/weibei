# 魏碑

魏碑是 macOS 原生三栏学习工作台：左边管本地资料，中间读 HTML/PDF/Markdown，右边写 Markdown 笔记并问当前材料。

## 第一版

| 能力 | 状态 |
| --- | --- |
| 导入 HTML / PDF / Markdown / Text | 已做 |
| 中央阅读器 | HTML 用 WebKit；PDF 用 PDFKit，支持连续滑动和单页翻页，单页模式可用 `⌘[` / `⌘]` 翻页；Markdown 资料用渲染阅读 |
| 右侧笔记 | 按资料绑定并保存到本机应用支持目录 |
| Markdown 原地写作 | 默认使用 WKWebView 内嵌 Milkdown / ProseMirror，同一编辑区里输入 Markdown 并实时排版；源码、对照模式保留为辅助 |
| 选区 Agent | HTML、PDF、Markdown/Text 文档和笔记编辑器选中内容后，可唤起带真实摘录的划线浮层；浮层会尽量靠近选区并可拖动固定，Agent 可替换当前笔记选区 |
| Agent | 读取 `OPENAI_API_KEY`，固定携带当前材料、当前选区、当前笔记和最近对话作答 |
| 全键盘 | `⌘1` 到 `⌘4` 聚焦，`⌘B` 收起资料库，`⌘K` 命令面板；命令面板支持上下键、回车和 Esc |
| 布局 | 文档/Agent/笔记、文档/笔记/Agent、文档笔记对半、沉浸阅读、沉浸对话、沉浸写笔记 |
| Agent 形态 | 固定列、底部抽屉、右下角小窗、划线浮层、静默洞察、隐藏 |

## 设计边界

沉浸模式只保留当前任务必须的界面：阅读时以文档为主，Agent 以静默洞察或轻浮层出现；写笔记时以编辑区为主，Agent 只给整理、补来源、润色入口。第一版已经接入真实选区文本、选区坐标、拖动固定浮层、Milkdown 原地 Markdown 写作和 Markdown 块级阅读渲染；后续需要继续把静默洞察从本地提示升级为真实页级 Agent 判断。

## 运行

```bash
./script/build_and_run.sh
```

Agent 默认模型来自 `WEIBEI_OPENAI_MODEL`，未设置时用 `gpt-5.1`。
