# 魏碑

本地学习用的 macOS 工作台。

读 HTML / PDF / Markdown，在材料边上写笔记，按**当前资料、选区、笔记**提问。三栏在同一窗口里切换，不把「读 / 记 / 问」拆成三个 App。

界面两套：**纸面**、**墨石**。配色是纸、墨、石青、朱砂。作者做的魏碑风格字体只用在英文品牌字（顶栏、栏目标记、设置里的 Latin 标识等），正文和笔记仍是系统字体。名字借的是书体，产品也按这个方向收——方一点、少一点装饰、回答尽量带出处。

设计稿在 [`DesignReferences/`](DesignReferences/)。

## 功能

| | |
| --- | --- |
| 资料 | 导入 HTML、PDF、Markdown、纯文本 |
| 阅读 | HTML（WebKit）、PDF（PDFKit，连续或单页，`⌘[` / `⌘]`）、Markdown 渲染 |
| 笔记 | 绑当前资料，存本机；Milkdown 原地编辑，可切源码 / 对照 |
| 划线 | 选区浮层带摘录，可写入或替换笔记 |
| 对话 | 上下文固定为当前材料与笔记；无 Key 时离线预览，不编造 |
| 布局 | 三栏可调；文档笔记对半；沉浸阅读 / 对话 / 写作 |
| Agent | 固定列、抽屉、小窗、划线浮层、静默洞察、隐藏 |
| 键位 | `⌘1`–`⌘4` 聚焦，`⌘B` 资料库，`⌘K` 命令面板 |

沉浸对话：用户句在居中列里右对齐（浅色纸面气泡），助手句按正文排。静默洞察仍是本地提示为主。

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
./script/build_and_run.sh check
./script/build_and_run.sh package
./script/build_and_run.sh --verify
```

## Agent

自备 API Key（设置页或环境变量），应用不托管账号。

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `OPENAI_API_KEY` | API Key | 无 |
| `WEIBEI_OPENAI_MODEL` | 模型 | `gpt-5.1` |

Key 只在本机。

## 目录

```text
Sources/WeiBei/           App、界面、编辑器资源
Sources/WeiBeiCore/       工作区、Agent、密钥、PDF OCR
Sources/WeiBeiSelfCheck/
Sources/WeiBei/WebEditor/ 编辑器源码 → Resources/Editor
DesignReferences/         纸 / 墨 / 石 / 朱砂参考
script/build_and_run.sh
```

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
```

动布局或对话结构时，把 SelfCheck 里的断言一并改掉。

## 状态

开发中。许可未定；有 `LICENSE` 之前请勿默认可任意再分发。品牌字体（`WeiBeiStele` / `WeiBeiSteleMono`）归作者，随项目使用，不作正文字体。
