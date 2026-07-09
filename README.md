# 魏碑

macOS 本地学习工作台：读资料、写笔记、基于当前材料提问。

三栏默认布局——资料库 / 阅读 / 笔记与对话。材料、选区、笔记在同一窗口里完成，不拆到多个 App。外观是纸面与墨石两套，字体为作者自有。

## 功能

| | |
| --- | --- |
| 资料 | 导入 HTML、PDF、Markdown、纯文本 |
| 阅读 | HTML（WebKit）、PDF（PDFKit，连续或单页，`⌘[` / `⌘]` 翻页）、Markdown 渲染 |
| 笔记 | 按资料绑定，存本机；Milkdown 原地编辑，可切源码 / 对照 |
| 划线提问 | 文档或笔记选区可唤起浮层，带摘录，可写入或替换笔记 |
| 对话 | 上下文为当前材料、选区、笔记、最近对话；无 Key 时离线预览，不编造 |
| 布局 | 三栏可调；文档笔记对半；沉浸阅读 / 对话 / 写作 |
| Agent 形态 | 固定列、抽屉、小窗、划线浮层、静默洞察、隐藏 |
| 快捷键 | `⌘1`–`⌘4` 聚焦，`⌘B` 资料库，`⌘K` 命令面板 |

沉浸对话里，用户消息在居中对话列内右对齐（纸面气泡），助手消息按正文排。静默洞察仍偏本地提示，页级判断未完成。

视觉参考图在 `DesignReferences/`。

## 要求

- macOS 14+
- `swift`（Xcode Command Line Tools）
- 改 Web 编辑器源码时需要 Node.js

## 运行

```bash
git clone https://github.com/taekchef/weibei.git
cd weibei
./script/build_and_run.sh
```

```bash
./script/build_and_run.sh check      # SelfCheck + WebEditorCheck
./script/build_and_run.sh package    # 生成 dist/魏碑.app
./script/build_and_run.sh --verify
```

## Agent

不提供托管账号。在设置里填 Key，或用环境变量：

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `OPENAI_API_KEY` | API Key | 无 |
| `WEIBEI_OPENAI_MODEL` | 模型 | `gpt-5.1` |

Key 只在本机，不进仓库。

## 目录

```text
Sources/WeiBei/              App 与界面
Sources/WeiBeiCore/          工作区、Agent、密钥、PDF OCR
Sources/WeiBeiSelfCheck/
Sources/WeiBei/WebEditor/    编辑器源码（esbuild → Resources/Editor）
DesignReferences/            设计参考图
script/build_and_run.sh
```

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
```

改布局或对话结构时，请同步自检里的源码断言。

## 字体与外观

- 纸面 / 墨石两套配色（纸、墨、石青、朱砂）
- 品牌字体由作者制作，随仓库提供

## 状态

开发中，接口与布局可能变。开源许可未定；有 `LICENSE` 之前请勿默认可任意再分发。
