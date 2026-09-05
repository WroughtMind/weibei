**[English](README.en.md)** | 中文

<!-- WEIBEI_VISUAL:hero:START -->
![魏碑 / WeiBei](./Docs/brand/readme-hero-1983x793.png)
<!-- WEIBEI_VISUAL:hero:END -->

# 魏碑 / WeiBei

魏碑是一个用来读书和记笔记的地方。

> 长时间阅读、摘抄、亲手记笔记，就算完全离开 AI，本身就是有意义的事。

所以核心完全本地：导入课程、阅读、全文搜索、笔记、出处关系，不需要任何模型。想用 AI 时接上——它在你自己的资料上回答，答案带引用，一点回到原文；笔记走提案，你审过才落笔。不接，魏碑就是一个安静、完整的阅读器和笔记本，复习的晚上不用再在 PDF、AI 网页、笔记软件之间来回切窗。

<p align="center">
  <strong>开发中，暂无正式安装包</strong>
  · macOS 14 及以上 · Apple 与 Intel 芯片 · 可从源码构建
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-F05138">
</p>

## ▍复习的晚上，你大概是这样过的

浏览器里开着讲义 PDF 和网页课件，另一个窗口挂着 AI 对话，第三个软件记笔记。每跳一次窗口，刚建立的上下文就断一次：答案离原文越来越远，笔记忘了是哪个问题引出来的，“我是在哪儿看到这句的？”成了整晚的主旋律。

魏碑把资料、问题、证据、笔记连成一个整体。它诞生于我自己期末复习的深夜——切窗口切到忍无可忍的那一晚。

## ▍和“AI 网页 + 笔记软件”比一比

| | AI 网页 + 笔记软件 | 魏碑 |
|---|---|---|
| 你的资料 | 每次粘贴或上传片段 | 整个文件夹导入为课程，本地索引，同窗打开 |
| 答案 | 听起来对，出处不明 | 每个答案带引用，一点跳回原文的页或节 |
| 一周之后 | 翻聊天记录找“当时为什么” | 划过的段落留着下划线，点开就是当时的对话 |
| 笔记 | 手动摘抄打字 | AI 递提案，你审过才落笔，绝不偷改 |
| 不用 AI 时 | 聊天网页一关，就什么都不剩 | 阅读、搜索、笔记、关系，照常工作 |
| 你的数据 | 散在各家服务 | 本地保存 |

## ▍一个窗口，三步：读 → 问 → 记

阅读本地资料和记笔记不依赖任何模型；问是可选的——不接模型，魏碑照样是完整的学习工作台。

<!-- WEIBEI_VISUAL:workspace:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-offline-learning-flow.png" alt="魏碑的阅读、Agent 对话与笔记工作区" width="1200">
</p>
<!-- WEIBEI_VISUAL:workspace:END -->

**读：导入一个文件夹，就是一门课。** PDF、HTML、Markdown、纯文本都行。全部本地索引、全文可搜，阅读器直达具体的页码和小节。

**问：划选一段，就地问。** 答案带引用标签，点击跳回出处。划过的段落留一条朱砂下划线，之后回来点它，当时的对话就重新打开——对话始终附着在它所针对的文字上。公式用 KaTeX 渲染，图表用 Mermaid，可交互片段在沙箱里运行，底下永远有一份可读的纯文本兜底。

**记：值得存的，提案给你审。** 笔记是所见即所得的编辑器，支持斜杠命令、图片、代码块。AI 觉得该存，会递一张卡片，你点头才写入——笔记永远不会被悄悄改掉。有意义的学习时刻会自动记住，并有一条轻提示告诉你存了什么。每条笔记和它的出处是多对多关系，在关系台上管理：

<!-- WEIBEI_VISUAL:course-relations:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-course-workspace-overview-flow.png" alt="魏碑的课程资料与笔记关系视图" width="1200">
</p>
<!-- WEIBEI_VISUAL:course-relations:END -->

## ▍隐私不是设置项，是结构

- 课程、笔记和全文索引在本地保存。使用在线模型时，相关摘录会发送给所选服务；远程图片等内容也会联网加载，详见[隐私说明](PRIVACY.md)。
- AI 只能通过宿主开放的固定工具读取当前内容。没有 shell，没有整个文件系统的访问权；每次请求只看到一份有边界的快照。
- 引用跳转、记忆写入、笔记提案、富答案载荷，全部先经本机校验，再展示、再落盘。
- 网页和资料永远只当数据读，不当代码执行——一个页面试图指挥 AI 做事，改变不了它的行为。搜索只带问题的主题，不带你的课程原文、笔记和本地路径。
- 模型自己选：几十个内置预设（OpenAI、Anthropic、Google、DeepSeek、Kimi、OpenRouter……）、OAuth 订阅、本地 llama.cpp，或任意 OpenAI 兼容接口。

## ▍五分钟上手

1. 打开魏碑，把一个资料文件夹导入为课程。应用不内置示例数据，不打包你没带来的东西。
2. （可选）在设置里接上任意一家模型供应商。不接也完全能用——阅读、搜索、笔记不受影响，这一步只影响下面的第 3、5 步。
3. 在阅读器里划选一段，就地提问。
4. 点答案里的引用标签，跳回出处。
5. 让 AI 把有用的东西存进笔记，审一眼提案卡片再放行。

目前没有正式发布计划；下一个正式版本号为 **0.0.1**。现在可按下方步骤从源码构建。发布状态见[发布说明](Docs/releases/README.md)。

## ▍为长夜而生

魏碑取名自碑刻，也把这份气质做进了应用：纸、宣、砚、碑四套主题，另有四款毛玻璃变体；全局字号缩放（⌘+ / ⌘−），照顾凌晨三点的眼睛；长文档和冷启动的加载期用安静的骨架屏，不闪空白；每天一句碑帖灵感句作背景水印——五十句里每一句的出处与授权，设置里有一本台账可查。

## ▍当前限制

- 本仓库支持 macOS 14 及以上；发布门禁要求 Apple Silicon 与 Intel 两个原生安装包同时通过后才能公开。
- 资料与索引在本地保存；在线模型和资料中的远程内容需要联网。
- 学习记忆自动记录，回答末尾有轻提示；正式笔记与关系修改仍需你确认。
- 大文件可能只索引了部分，应用会如实标注，不假装完整。
- 当前处于开发阶段，暂无正式安装包。

---

## ▍给开发者

以下内容面向参与构建魏碑本身的人。魏碑出生于 OpenAI Build Week 2026 教育赛道，此后作为持续开发的产品；提交记录见 [Docs/build-week.md](Docs/build-week.md)。

### 从源码构建

要求：macOS 14+、Xcode Command Line Tools（Swift 5.9）、模型供应商仅在需要真实 Agent 回复时配置。完整检查、打包和重建网页编辑器需要 Node.js 22 及以上，并先运行 `npm ci`。

```bash
git clone https://github.com/WroughtMind/weibei.git
cd weibei
./script/build_and_run.sh
```

脚本会构建并打开 `dist/魏碑.app`。

### 技术架构

原生 Swift 5.9 应用：SwiftUI 负责界面，AppKit 承载长驻的阅读、Agent、笔记面板。PDFKit 读 PDF，WebKit 渲染 HTML 与 Milkdown 编辑器，Vision 处理扫描页 OCR，SQLite FTS5 存本地课程索引。Agent 循环、供应商接入、凭据与会话账本由 Swift 原生运行时负责；魏碑自身掌握资料上下文、引用、学习记忆、笔记写回与界面渲染。

每个 Agent 请求只拿到一份有边界的快照——没有文件系统，没有 shell，网页读取仅限用户当轮明确给出的 HTTPS 链接。宿主在展示或落盘之前，校验引用、跳转、学习记忆更新、笔记提案与富答案载荷；`visualize` 片段在无网络、无本地文件访问的沙箱里执行。长 PDF 与扫描件的文本抽取跑在资源受限的辅助进程里，只有无原生文本的页面才动用 Vision OCR；部分索引会如实上报，不会冒充完整。

### 工具链

根目录 `Makefile` 是薄入口，转发到底层构建脚本（`make help` 可看同一份列表）：

| 目标 | 实际执行 |
|---|---|
| `make build` | `swift build` |
| `make run` | `./script/build_and_run.sh` |
| `make check` | `./script/build_and_run.sh check` |
| `make package` | `./script/build_and_run.sh package` |
| `make verify` | `./script/build_and_run.sh verify`（打包并完成一次真实进程启动验收） |
| `make editor-build` | `npm run build:editor` |
| `make genui-math-check` | `npx tsx script/check-genui-math.ts` |
| `make perf-p95` | `./script/perf_p95.sh $(LOG) $(METRIC)`（用法：`make perf-p95 LOG=<perf日志> METRIC=<指标名>`） |
| `make release` | `./script/build_release_dmg.sh`（构建当前架构未公证的正式 DMG） |
| `make clean` | `swift package clean && rm -rf dist`（保留 `node_modules` 与用户数据） |

Node 工具链：在仓库根目录运行 `npm ci`，按唯一的 `package-lock.json` 安装依赖。`script/` 和 `DesignSystem/scripts/` 下的 TypeScript 工具用 `tsx` 运行；`npm run typecheck:tools` 做类型检查。

应用和 DMG 始终在对应芯片的 Mac 上原生构建：Apple runner 使用 `--arch arm64`，Intel runner 使用 `--arch x86_64`。完整双架构发布资产、密钥变量和原子公开流程见 [Docs/releases/dual-architecture.md](Docs/releases/dual-architecture.md)。

### 检查

```bash
npm ci
./script/build_and_run.sh check
```

也可以单独运行：

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
swift run WeiBeiNativeCheck --authentication-status
```

真实供应商检查需要本地有效凭据，不会悄悄换成模拟答案。

### 文档

- [Docs/build-week.md](Docs/build-week.md) — OpenAI Build Week 2026 提交记录与评委走查
- [Docs/note-slash-commands.md](Docs/note-slash-commands.md) — 笔记编辑器斜杠命令、图片插入与代码块行为
- [Docs/course-library-architecture.md](Docs/course-library-architecture.md) — 课程库与存储架构
- [Docs/plans/2026-08-22-native-agent-runtime-实验计划.md](Docs/plans/2026-08-22-native-agent-runtime-实验计划.md) — Swift 原生 Agent 运行时的验证与落地记录
- [Docs/生成式界面基础与Visualize借鉴.md](Docs/生成式界面基础与Visualize借鉴.md) — 生成式界面基础与 `visualize` 决策
- [Docs/releases/README.md](Docs/releases/README.md) — 当前发布状态

---

## ▍许可

- 代码与开发者文档：[MIT License](LICENSE)。
- `WeiBeiStele` 与 `WeiBeiSteleMono` 字体：[SIL Open Font License 1.1](Sources/WeiBei/Resources/Fonts/OFL.txt)。修改版必须改名，除非另行获得保留名的书面许可。
- “魏碑 / WeiBei” 名称、logo、视觉识别、截图与发布媒体：不在 MIT 与 OFL 之内。第三方软件与参考素材保留其原始条款。
- 再分发 fork 或打包应用之前，先读 [`LICENSING.md`](LICENSING.md)。贡献流程见 [`CONTRIBUTING.md`](CONTRIBUTING.md)，安全问题见 [`SECURITY.md`](SECURITY.md)。

## ▍技术栈

`Swift` · `SwiftUI` · `AppKit` · `PDFKit` · `WebKit` · `Vision OCR` · `SQLite FTS5` · `Milkdown` · `KaTeX` · `Mermaid` · `OpenAI Codex OAuth`
