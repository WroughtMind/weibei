**[English](README.en.md)** | 中文

<!-- WEIBEI_VISUAL:hero:START -->
![魏碑 / WeiBei](./Docs/brand/readme-hero-1983x793.png)
<!-- WEIBEI_VISUAL:hero:END -->

# 魏碑 / WeiBei

魏碑是一个用来读书和记笔记的地方。我们相信:长时间阅读、摘抄、亲手记笔记,就算完全离开 AI,本身就是有意义的事。

所以核心完全本地:导入课程、阅读、全文搜索、笔记、出处关系,不需要任何模型。想用 AI 时接上——它在你自己的资料上回答,答案带引用,一点回到原文;笔记走提案,你审过才落笔。不接,魏碑就是一个安静、完整的阅读器和笔记本,复习的晚上不用再在 PDF、AI 网页、笔记软件之间来回切窗。

**[⬇︎ 下载魏碑 1.0.0](https://github.com/weibei-app/weibei/releases/download/v1.0.0/WeiBei-1.0.0-macOS-arm64.dmg)** — macOS 14 及以上,Apple 芯片。校验值见 [Releases](https://github.com/weibei-app/weibei/releases)。

[![Release](https://img.shields.io/github/v/release/weibei-app/weibei)](https://github.com/weibei-app/weibei/releases)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Swift](https://img.shields.io/badge/Swift-5.9-F05138)

## 复习的晚上,你大概是这样过的

浏览器里开着讲义 PDF 和网页课件,另一个窗口挂着 AI 对话,第三个软件记笔记。每跳一次窗口,刚建立的上下文就断一次:答案离原文越来越远,笔记忘了是哪个问题引出来的,"我是在哪儿看到这句的?"成了整晚的主旋律。

魏碑把资料、问题、证据、笔记连成一个整体。它诞生于我自己期末复习的深夜——切窗口切到忍无可忍的那一晚。

## 和"AI 网页 + 笔记软件"比一比

| | AI 网页 + 笔记软件 | 魏碑 |
|---|---|---|
| 你的资料 | 每次粘贴或上传片段 | 整个文件夹导入为课程,本地索引,同窗打开 |
| 答案 | 听起来对,出处不明 | 每个答案带引用,一点跳回原文的页或节 |
| 一周之后 | 翻聊天记录找"当时为什么" | 划过的段落留着下划线,点开就是当时的对话 |
| 笔记 | 手动摘抄打字 | AI 递提案,你审过才落笔,绝不偷改 |
| 不用 AI 时 | 聊天网页一关,就什么都不剩 | 阅读、搜索、笔记、关系,照常工作 |
| 你的数据 | 散在各家服务 | 本地优先,只存在你的 Mac 上 |

## 一个窗口,三步:读 → 问 → 记

读和记完全离线,不依赖任何模型;问是可选的——不接模型,魏碑照样是完整的学习工作台。

<!-- WEIBEI_VISUAL:workspace:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-offline-learning-flow.png" alt="魏碑的阅读、Agent 对话与笔记工作区" width="1200">
</p>
<!-- WEIBEI_VISUAL:workspace:END -->

**读:导入一个文件夹,就是一门课。** PDF、HTML、Markdown、纯文本都行。全部本地索引、全文可搜,阅读器直达具体的页码和小节。

**问:划选一段,就地问。** 答案带引用标签,点击跳回出处。划过的段落留一条朱砂下划线,之后回来点它,当时的对话就重新打开——对话始终附着在它所针对的文字上。公式用 KaTeX 渲染,图表用 Mermaid,可交互片段在沙箱里运行,底下永远有一份可读的纯文本兜底。

**记:值得存的,提案给你审。** 笔记是所见即所得的编辑器,支持斜杠命令、图片、代码块。AI 觉得该存,会递一张卡片,你点头才写入——笔记永远不会被悄悄改掉。有意义的学习时刻会自动记住,并有一条轻提示告诉你存了什么。每条笔记和它的出处是多对多关系,在关系台上管理:

<!-- WEIBEI_VISUAL:course-relations:START -->
<p align="center">
  <img src="./Docs/release-evidence/app-course-workspace-overview-flow.png" alt="魏碑的课程资料与笔记关系视图" width="1200">
</p>
<!-- WEIBEI_VISUAL:course-relations:END -->

## 隐私不是设置项,是结构

- 课程、笔记和全文索引,只存在你的 Mac 上。
- AI 只能通过宿主开放的固定工具读取当前内容。没有 shell,没有整个文件系统的访问权;每次请求只看到一份有边界的快照。
- 引用跳转、记忆写入、笔记提案、富答案载荷,全部先经本机校验,再展示、再落盘。
- 网页和资料永远只当数据读,不当代码执行——一个页面试图指挥 AI 做事,改变不了它的行为。搜索只带问题的主题,不带你的课程原文、笔记和本地路径。
- 模型自己选:几十个内置预设(OpenAI、Anthropic、Google、DeepSeek、Kimi、OpenRouter……)、OAuth 订阅、本地 llama.cpp,或任意 OpenAI 兼容接口。

## 五分钟上手

1. 打开魏碑,把一个资料文件夹导入为课程。应用不内置示例数据,不打包你没带来的东西。
2. (可选)在设置里接上任意一家模型供应商。不接也完全能用——阅读、搜索、笔记不受影响,这一步只影响下面的第 3、5 步。
3. 在阅读器里划选一段,就地提问。
4. 点答案里的引用标签,跳回出处。
5. 让 AI 把有用的东西存进笔记,审一眼提案卡片再放行。

首次打开会被 Gatekeeper 拦下(社区构建未经 Apple 公证)。放行一次即可,之后正常打开;更新到新下载的版本后,需要再放行一次:

- macOS 15 及以后:双击尝试打开一次,再到**系统设置 → 隐私与安全性**点底部的**仍要打开**并确认。右键"打开"的旧捷径从 macOS 15 起已被系统移除。
- macOS 14:在"应用程序"里右键 `魏碑.app`,选**打开**,再确认一次**打开**。

这只放行魏碑一个应用,不要全局关闭 Gatekeeper。新版本检查在设置里,不用盯着 Releases 页。

Homebrew cask 在计划中;tap 发布前,请用 DMG 或从源码构建。

## 为长夜而生

魏碑取名自碑刻,也把这份气质做进了应用:纸、宣、砚、碑四套主题,另有四款毛玻璃变体;全局字号缩放(⌘+ / ⌘−),照顾凌晨三点的眼睛;长文档和冷启动的加载期用安静的骨架屏,不闪空白;每天一句碑帖灵感句作背景水印——五十句里每一句的出处与授权,设置里有一本台账可查。

## 当前限制

- 仅 macOS 14 及以上;安装包面向 Apple 芯片。Windows 和网页版在计划中。
- 资料与索引完全本地。读书、记笔记不需要联网,只有 AI 回答需要。
- 学习记忆自动记录,回答末尾有轻提示;正式笔记与关系修改仍需你确认。
- 大文件可能只索引了部分,应用会如实标注,不假装完整。
- 社区构建未经 Apple 公证,首次打开需手动放行。

## 给开发者

以下内容面向参与构建魏碑本身的人。魏碑出生于 OpenAI Build Week 2026 教育赛道,此后作为持续开发的产品;提交记录见 [Docs/build-week.md](Docs/build-week.md)。

### 从源码构建

要求:macOS 14+、Xcode Command Line Tools(Swift 5.9)、首次构建需联网下载并校验固定的 Pi 运行时、已配置的模型供应商(用于真实 Agent 回复);仅重建 Milkdown 网页编辑器时需要 Node.js。

```bash
git clone https://github.com/weibei-app/weibei.git
cd weibei
./script/build_and_run.sh
```

脚本会构建并打开 `dist/魏碑.app`。

### 技术架构

原生 Swift 5.9 应用:SwiftUI 负责界面,AppKit 承载长驻的阅读、Agent、笔记面板。PDFKit 读 PDF,WebKit 渲染 HTML 与 Milkdown 编辑器,Vision 处理扫描页 OCR,SQLite FTS5 存本地课程索引。固定的 Pi 0.82.1 运行时提供 Agent 循环;魏碑自身掌握资料上下文、引用、学习记忆、笔记写回与界面渲染。

每个 Agent 请求只拿到一份有边界的快照——没有文件系统,没有 shell,网页读取仅限用户当轮明确给出的 HTTPS 链接。宿主在展示或落盘之前,校验引用、跳转、学习记忆更新、笔记提案与富答案载荷;`visualize` 片段在无网络、无本地文件访问的沙箱里执行。长 PDF 与扫描件的文本抽取跑在资源受限的辅助进程里,只有无原生文本的页面才动用 Vision OCR;部分索引会如实上报,不会冒充完整。

### 工具链

根目录 `Makefile` 是薄入口,转发到底层构建脚本(`make help` 可看同一份列表):

| 目标 | 实际执行 |
|---|---|
| `make build` | `swift build` |
| `make run` | `./script/build_and_run.sh` |
| `make check` | `./script/build_and_run.sh check` |
| `make package` | `./script/build_and_run.sh package` |
| `make editor-build` | `npm run build:editor` |
| `make rich-answer-build` | `npm -w Prototypes/RichAnswerWebRuntime run build:embed` |
| `make genui-math-check` | `npx tsx script/check-genui-math.ts` |
| `make perf-p95` | `./script/perf_p95.sh $(LOG) $(METRIC)`(用法:`make perf-p95 LOG=<perf日志> METRIC=<指标名>`) |
| `make pi-prepare` | `./script/prepare_pi_runtime.sh` |
| `make release-community` | `./script/build_release_dmg.sh --community` |
| `make release-notarized` | `./script/build_release_dmg.sh --notarized` |
| `make clean` | `swift package clean && rm -rf dist`(保留 `node_modules` 与 `.build/pi-runtime`——clean 目标会在 `swift package clean` 前后把 `pi-runtime` 挪开再挪回,否则会被删——以及用户数据) |

Node 工具链:仓库只有一个根锁文件(`package-lock.json`),覆盖 `Prototypes/RichAnswerWebRuntime` 工作区,一次 `npm ci` 装齐。`script/`、`DesignSystem/scripts/` 与原型 `scripts/` 下的工具脚本是 TypeScript,用 `tsx` 运行(如 `npx tsx script/check-genui-math.ts`);`npm run typecheck:tools` 做类型检查。

### 检查

```bash
./script/build_and_run.sh check
```

也可以单独运行:

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
PI_RUNTIME="$(./script/prepare_pi_runtime.sh)"
WEIBEI_PI_EXECUTABLE="$PI_RUNTIME/bin/pi" swift run WeiBeiPiCheck
```

真实供应商检查需要本地有效凭据,不会悄悄换成模拟答案。

### 文档

- [Docs/build-week.md](Docs/build-week.md) — OpenAI Build Week 2026 提交记录与评委走查
- [Docs/note-slash-commands.md](Docs/note-slash-commands.md) — 笔记编辑器斜杠命令、图片插入与代码块行为
- [Docs/course-library-architecture.md](Docs/course-library-architecture.md) — 课程库与存储架构
- [Docs/pi-unified-runtime.md](Docs/pi-unified-runtime.md) — 固定的 Pi Agent 运行时
- [Docs/生成式界面基础与Visualize借鉴.md](Docs/生成式界面基础与Visualize借鉴.md) — 生成式界面基础与 `visualize` 决策
- [Docs/releases/v1.0.0.md](Docs/releases/v1.0.0.md) — v1.0.0 发布说明与证据

## 许可

- 代码与开发者文档:[MIT License](LICENSE)。
- `WeiBeiStele` 与 `WeiBeiSteleMono` 字体:[SIL Open Font License 1.1](Sources/WeiBei/Resources/Fonts/OFL.txt)。修改版必须改名,除非获得书面许可保留保留名。
- "魏碑 / WeiBei" 名称、logo、视觉识别、截图与发布媒体:不在 MIT 与 OFL 之内。第三方软件与参考素材保留其原始条款。
- 再分发 fork 或打包应用之前,先读 [`LICENSING.md`](LICENSING.md)。贡献流程见 [`CONTRIBUTING.md`](CONTRIBUTING.md),安全问题见 [`SECURITY.md`](SECURITY.md)。

## 技术栈

Swift · SwiftUI · AppKit · PDFKit · WebKit · Vision OCR · SQLite FTS5 · Milkdown · KaTeX · Mermaid · Pi · OpenAI Codex OAuth
