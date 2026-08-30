# 魏碑 Windows 核心版本实施与合并边界

> 状态：Windows 核心实现已落地；既有 PR 合并引用的 Windows CI 已全绿，5 张打包后截图已人工审阅。本轮合并不等于完整功能或精确像素等价验收
> 分支：`codex/windows-parity-v2`  
> 历史实施基线：`main@5cdcdd4ee2627506356d424dbcc26d16a7ec8571`

## 目标

Windows 版不是宣传页复刻，也不是只把三栏画出来。最终产品目标是用户从导入课程开始，能够走完与 macOS 版相同的核心闭环：

```text
打开资料 → 选中 → 提问 → 查看证据 → 回到原文 → 确认写入笔记
```

这是最终等价目标，不是本次合并的完成声明。本次只以范围中已实现的 Windows 核心底座为合并边界，并以当前提交的 CI 复验为合并条件。

## 本次可合并范围

- Electron Windows 壳、八套主题、资料库 / 课程空间、三栏重排与显隐、设置和当前课程全文搜索；
- PDF.js 阅读、文本层选区、页码、缩放、连续 / 单页模式和文内搜索；HTML 安全渲染，Markdown / 笔记复用同一份 canonical Milkdown 运行时；
- Swift portable course / workspace / session JSON 兼容，课程文件外部变更自动刷新，SQLite FTS5 搜索独立进程；
- Agent 流式网络独立进程、停止、崩溃隔离与部分回答持久化、课程 FTS 有界上下文、来源条目打开和会话持久化；
- Windows DPAPI 凭据、唯一笔记写闸、覆盖前备份、草稿恢复、外部修改冲突选择；
- NSIS 与 Portable x64 打包、安装 / 卸载脚本，以及 3 条真实打包后 Electron 冒烟路径。

既有 `windows-2025` CI 已在打包后完成 3 条 Playwright 场景、NSIS 安装 / 同版覆盖 / 卸载和 Portable 运行检查；5 张 1240 × 760 截图已人工审阅，未发现 P0 渲染缺陷。该证据只证明那一次 CI 合并引用的打包后核心 UI 可用，不是最终精确像素等价或真实用户验收。具体视觉证据与限制见仓库根目录 `design-qa.md`。

## 本次不宣称完成

- 精确像素等价尚未完成；当前截图没有与参考图同时呈现活跃文档、有来源的 Agent 回答和活跃笔记。
- Agent → 笔记的提案、用户确认和安全写入闭环尚未完成。
- Chat 当前只显示纯文本回答；富 Markdown / 公式 / 图表、工具调用、失败重试和 action UI 尚未完成。来源只能打开命中的课程条目，尚无页 / 节级精确定位。
- 完整的出处关系台、学习记忆管理、自动更新与 OAuth provider 目录尚未完成。
- 扫描 PDF 的 OCR 尚未实现；无文本层时只能如实显示未建立文本。
- CI 中的 NSIS / Portable 产物是短期验收候选，不是经正式签名、发布授权与最终验收的 release。

## 架构决定

Windows 客户端采用固定 Chromium 运行时的 Electron 壳层，界面和平台服务放在独立的 `windows/` 工作区，现有 macOS SwiftUI / AppKit 路径保持原样。

选择这条路线的原因：

1. SwiftUI、AppKit、PDFKit、WKWebView、Vision、Security 与 Sparkle 没有可直接编译到 Windows 的等价实现，原应用不能通过条件编译得到 Windows 产品。
2. 固定 Chromium 比依赖用户系统 WebView2 版本更容易控制渲染；现有 Milkdown、KaTeX、Mermaid 和 Prism 已用于文稿与笔记的 canonical 运行时，Chat 尚未接入这套富文本渲染。
3. Electron 主进程可以把文件、凭据、SQLite、网络和窗口能力收在隔离边界内；渲染进程继续保持无 Node 权限、上下文隔离和沙箱。
4. 当前玻璃主题使用 CSS token 与 `backdrop-filter` 模拟透明层次；系统 Mica / Acrylic 尚未接入，实色主题不依赖系统背景材料。

这不是把产品改成网页。Electron 只负责可重复渲染和桌面承载；课程文件、索引、会话、凭据和写盘仍是本地桌面能力。

## 最终等价目标（非本次完成声明）

### 必须相同

- 八套主题的语义 token、正文层级、朱砂 / 石青分工、1 px 分隔线和连续纸面；
- `reader / agent / notes` 三个平等且可重排的工作面；
- 课程目录 220–430、正文可读宽度 560–780、10 px 分隔命中区、28 px 休眠轨道、240 px 可读阈值和 420 px 默认展开宽度；
- 两栏、三栏、对半和三个沉浸模式，以及切换时的阅读位置、草稿、流式回答和编辑器状态连续性；
- PDF、HTML、Markdown、纯文本的阅读、搜索、选区、引用定位和失败边界；
- 本地课程、全文索引、会话、学习记忆、出处关系、笔记提案与确认写入；
- 流式输出的停止、重试、错误恢复、末尾稳定和不闪动；
- 文件即真相、唯一写闸、覆盖前备份、外部变更采用和瞬时缺席容忍；
- 中英文、90%–160% 字号梯级、键盘操作、减少动态效果和屏幕阅读器标签。

### 平台化但保持同一效果

- `Command` 快捷键在 Windows 映射到 `Ctrl`，菜单文案显示 Windows 实际按键；
- SF Symbols 不跨 Apple 平台分发，Windows 版使用自有同语义线性 SVG，保持 1.5 px 笔画与 24 / 28 px 控件光学尺寸；
- PingFang / Songti 不作为 Windows 依赖，随包携带 OFL 授权的 CJK Sans / Serif，并继续携带 `WeiBeiStele` 品牌字体；
- Windows 11 使用系统背景材料；Windows 10 和关闭透明效果时回退为完全匹配 token 的实色表面；
- Keychain 对应 Windows DPAPI（由 Electron `safeStorage` 封装）；签名后的 Windows 更新通道是后续目标，本次不提供；
- 扫描 PDF 在没有文本层时明确保持“未建立文本”的事实，不把空结果伪装成已完成 OCR。

## 进程与信任边界

```text
Sandboxed Renderer
  ├─ Workspace UI
  ├─ Canonical document / note runtime
  │    └─ Milkdown / KaTeX / Mermaid / Prism
  └─ PDF.js / safe document renderer
           │ typed IPC only
           ▼
Electron Main
  ├─ capability roots + atomic write coordinator
  ├─ DPAPI credential vault
  ├─ dialogs / window
  ├─ file watcher + document extraction
  ├─ Agent utility process
  │    └─ provider streaming + ledger
  └─ Search-index utility process
       └─ SQLite FTS5
```

渲染进程不开启 `nodeIntegration`；启用 `contextIsolation` 和 Chromium sandbox。所有 IPC 都按命令逐项暴露并校验参数，不把 `ipcRenderer`、任意路径读写或任意网络请求直接交给页面。SQLite FTS 与 Agent 网络循环在独立进程中；文件监听、索引协调和 PDF / 文本文档提取当前仍在 Electron Main，大型文档提取是后续需要移出的性能边界。导入 HTML、网页和模型返回内容一律当数据处理。

## 后续实施顺序

下列是从当前核心版本到最终等价目标的路线，不表示每一项已在本 PR 完成。

1. 建立 Windows 壳层、token、字体、顶栏、课程抽屉、可重排 pane 与响应式布局；
2. 建立兼容课程目录和 `course-state.json` 的文件层、原子写闸、备份环和文件观察；
3. 接入 PDF.js、HTML / Markdown / 文本阅读与统一选区锚点；
4. 复用现有 Milkdown 编辑器协议，继续补齐尚缺的编辑能力；
5. 在已有供应商流式协议、会话外置存储、引用回跳与停止基础上，补齐重试和 Agent → 笔记确认写入；
6. 补齐课程首页、关系台、记忆管理、命令面板、OAuth provider 目录、OCR 和签名更新通道；
7. 在 Windows CI 生成 NSIS 与 portable 候选包，运行单元、Playwright、截图、安装 / 卸载和冷启动冒烟；
8. 用当前 macOS 真实窗口证据逐场景对拍，保留已确认的平台差异，其余差异归零。

## 本次合并门槛

- `npm` 锁文件可重复安装，TypeScript、单元测试和现有编辑器测试通过；
- 只保留关键自动检查：编辑器协议、课程 / 会话兼容、搜索、Agent 流式、凭据和笔记防丢；
- 当前提交对应的 Windows CI 重新构建 NSIS / Portable，并通过安装、同版覆盖、卸载、Portable 可见窗口和打包后 Electron 冒烟；
- 打包后 3 条 Electron 冒烟只覆盖启动空态与课程抽屉、创建空课程后的三栏工作台、设置与八套主题；
- PR 明确区分代码实现、本地通过、Windows CI 通过、候选包、真实 App 验收，未经过的阶段不提前宣称完成。

当前已有证据只覆盖既有 CI 合并引用：编译、定向测试、打包后 3 条 Playwright 场景、NSIS 安装 / 同版覆盖 / 卸载、Portable 以及 5 张截图人工审阅。任何后续代码变更都需以自己对应的检查结果为准，不得借用这次旧证据宣称通过。

## 最终等价候选门槛（本 PR 尚未满足）

- Windows x64 候选包在干净 runner 上覆盖真实导入、重启恢复和完整学习闭环；
- 在同一 1240 × 760 状态呈现活跃文档、有依据的 Agent 回答和活跃笔记，再与参考图对照；
- 补齐富文本 Chat、失败重试、Agent → 笔记确认写入、页 / 节级来源定位、关系与记忆管理后，分别完成对应专项验证；
- 用户在最终候选包上完成真实 Windows 体验验收。

## 共享核心文件占用声明

负责人任务：`codex/windows-parity-v2`。

- `.github/`：新增 Windows 验证与候选包工作流；
- `script/`：新增统一 Windows 构建 / 检查入口时占用；
- `package.json` / `package-lock.json`：把 `windows/` 纳入同一 Node 锁图；
- `Sources/WeiBei/WebEditor/` 与生成资源：只在跨平台桥接必须修正时做向后兼容改动；
- `Package.swift`、Swift 主 App 文件和 `VERSION` 默认不改，确需修改时先在 PR 更新占用说明。

整合注意点：上述路径与同时进行的 macOS 功能分支可能重叠；Windows 任务只接受经过审查的最小共享改动，不从旧分支整体合并。释放条件是合并范围内的 Windows 候选包可重复构建、定向检查与 CI 通过，PR 已记录打包后 Windows 冒烟结果、仍保留的平台差异与未实现能力。
