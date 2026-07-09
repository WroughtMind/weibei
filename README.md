# 魏碑

macOS 原生学习工作台：读本地资料、写 Markdown 笔记、就着当前材料提问。

左边管资料库，中间阅读 HTML / PDF / Markdown，右边记笔记；Agent 只回答和当前材料、选区、笔记相关的事，不编造没有依据的内容。

界面走纸墨气质——纸面与墨石两套外观，字体为项目自有。

## 适合谁

- 需要对照课件 / PDF / 网页材料记笔记的人
- 希望划线提问、把回答写回笔记，而不是另开一个聊天窗口的人
- 更习惯键盘与本地文件，而不是云端笔记同步的人

## 能力

| 模块 | 说明 |
| --- | --- |
| 资料库 | 导入 HTML、PDF、Markdown、纯文本；本地索引与切换 |
| 阅读 | HTML（WebKit）、PDF（PDFKit，连续滑动 / 单页，`⌘[` `⌘]` 翻页）、Markdown 渲染阅读 |
| 笔记 | 按资料绑定，保存在本机 Application Support；Milkdown / ProseMirror 原地排版，源码与对照模式可切换 |
| 选区 Agent | 在文档或笔记中划线后唤起浮层，带真实摘录；可拖动固定，可写回或替换笔记选区 |
| 对话 Agent | 读取本机配置的 API Key；上下文固定为当前材料、选区、笔记与最近对话 |
| 布局 | 文档·对话·笔记三栏可调；文档笔记对半；沉浸阅读 / 沉浸对话 / 沉浸写笔记 |
| Agent 形态 | 固定列、底部抽屉、右下角小窗、划线浮层、静默洞察、隐藏 |
| 键盘 | `⌘1`–`⌘4` 聚焦栏位，`⌘B` 资料库，`⌘K` 命令面板 |

### 设计边界

沉浸模式只保留当前任务必要的界面：阅读时以文档为主，对话以轻浮层或静默洞察出现；写笔记时以编辑区为主。用户消息在对话列内右对齐为纸面气泡，助手回答保持正文阅读式排版。

静默洞察目前偏本地提示；页级真实判断仍在演进。

## 环境要求

- macOS 14 或更高
- Xcode Command Line Tools（提供 `swift`）
- 可选：Node.js（修改 Web 编辑器源码时需要重新打包资源）

## 运行

```bash
git clone https://github.com/taekchef/weibei.git
cd weibei
./script/build_and_run.sh
```

脚本会：

1. 若存在 `node_modules`，执行编辑器 bundle（`npm run build:editor`）
2. `swift build`
3. 打包到 `dist/魏碑.app` 并启动

其它常用命令：

```bash
./script/build_and_run.sh check      # 自检（SelfCheck + WebEditorCheck）
./script/build_and_run.sh package    # 只打包，不启动
./script/build_and_run.sh --verify   # 构建 + 自检 + 场景验证
```

## Agent 配置

魏碑不会内置云端账号。在设置里填写 API Key，或使用环境变量：

| 变量 | 作用 | 默认 |
| --- | --- | --- |
| `OPENAI_API_KEY` | 调用模型 | 无（未配置时离线预览，不编造答案） |
| `WEIBEI_OPENAI_MODEL` | 模型名 | `gpt-5.1` |

Key 保存在本机钥匙串相关存储中，不会写入仓库。

## 项目结构

```text
Sources/
  WeiBei/           # App 壳、界面、编辑器资源
  WeiBeiCore/       # 工作区模型、Agent、密钥与 PDF OCR 等
  WeiBeiSelfCheck/  # 源码与行为自检
  WeiBeiWebEditorCheck/
script/build_and_run.sh
DesignReferences/   # 视觉参考（设计稿截图）
```

编辑器前端源码在 `Sources/WeiBei/WebEditor/`，构建产物进 `Sources/WeiBei/Resources/Editor/`。

## 开发说明

- 主栈：Swift 5.9、SwiftUI / AppKit、PDFKit、WebKit
- 笔记编辑：Milkdown + ProseMirror（经 esbuild 打包）
- 外观：纸面（亮）/ 墨石（暗）；品牌字体为作者自有，随仓库分发
- 自检偏「源码契约 + 场景」：改布局或对话结构时请同步 `WeiBeiSelfCheck`

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
```

## 状态

积极开发中。接口、布局与 Agent 行为仍可能调整；欢迎开 issue 讨论方向，合并前请跑通 `./script/build_and_run.sh check`。

## 许可

开源许可待定。在添加 `LICENSE` 之前，请勿默认视为可任意再分发；使用与贡献约定将在正式开源时写明。
