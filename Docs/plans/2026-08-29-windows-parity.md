# 魏碑 Windows 等价版本实施方案

> 状态：实施中  
> 分支：`codex/windows-parity`  
> 基线：`main@2640e7e2d8de133013727558d43f63a1176a20cd`

## 目标

Windows 版不是宣传页复刻，也不是只把三栏画出来。完成标准是用户从导入课程开始，能够走完与 macOS 版相同的核心闭环：

```text
打开资料 → 选中 → 提问 → 查看证据 → 回到原文 → 确认写入笔记
```

视觉、交互、数据语义、安全边界、快捷键和安装更新都必须进入同一份等价性验收；平台本身不同的地方采用 Windows 原生约定，但不能改变产品角色和信息层级。

## 架构决定

Windows 客户端采用固定 Chromium 运行时的 Electron 壳层，界面和平台服务放在独立的 `windows/` 工作区，现有 macOS SwiftUI / AppKit 路径保持原样。

选择这条路线的原因：

1. SwiftUI、AppKit、PDFKit、WKWebView、Vision、Security 与 Sparkle 没有可直接编译到 Windows 的等价实现，原应用不能通过条件编译得到 Windows 产品。
2. 固定 Chromium 比依赖用户系统 WebView2 版本更容易控制逐像素渲染；现有 Milkdown、KaTeX、Mermaid、Prism 和流式 Markdown 运行时可以直接复用。
3. Electron 主进程可以把文件、凭据、SQLite、网络和窗口能力收在隔离边界内；渲染进程继续保持无 Node 权限、上下文隔离和沙箱。
4. Windows 11 使用 Mica / Acrylic 背景材料，较旧系统使用同 token 的不透明回退；两者共享内容表面、字体和布局。

这不是把产品改成网页。Electron 只负责可重复渲染和桌面承载；课程文件、索引、会话、凭据和写盘仍是本地桌面能力。

## 等价性边界

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
- Keychain 对应 Windows DPAPI（由 Electron `safeStorage` 封装）；Sparkle 对应签名后的 Windows 更新通道；
- Vision OCR 对应 Windows OCR 可用时的本机能力，缺失时明确显示“扫描页未建立文本”，不伪造完整索引。

## 进程与信任边界

```text
Sandboxed Renderer
  ├─ Workspace UI
  ├─ Milkdown / KaTeX / Mermaid
  └─ PDF.js / safe document renderer
           │ typed IPC only
           ▼
Electron Main
  ├─ course filesystem + watcher
  ├─ atomic write gate + backup ring
  ├─ SQLite FTS5 index
  ├─ provider streaming runtime
  ├─ DPAPI credential vault
  └─ dialogs / window / updater
```

渲染进程不开启 `nodeIntegration`；启用 `contextIsolation` 和 Chromium sandbox。所有 IPC 都按命令逐项暴露并校验参数，不把 `ipcRenderer`、任意路径读写或任意网络请求直接交给页面。导入 HTML、网页和模型返回内容一律当数据处理。

## 实施顺序

1. 建立 Windows 壳层、token、字体、顶栏、课程抽屉、可重排 pane 与响应式布局；
2. 建立兼容课程目录和 `course-state.json` 的文件层、原子写闸、备份环和文件观察；
3. 接入 PDF.js、HTML / Markdown / 文本阅读与统一选区锚点；
4. 复用现有 Milkdown 编辑器协议，补齐图片、公式、Mermaid、斜杠命令、撤销和恢复；
5. 移植供应商流式协议、会话外置存储、范围快照、引用验证、停止 / 重试；
6. 补齐课程首页、关系台、记录、设置、全局搜索、命令面板和更新；
7. 在 Windows CI 生成 NSIS 与 portable 候选包，运行单元、Playwright、截图、安装 / 卸载和冷启动冒烟；
8. 用当前 macOS 真实窗口证据逐场景对拍，保留已确认的平台差异，其余差异归零。

## 验证门槛

- `npm` 锁文件可重复安装，TypeScript、单元测试和现有编辑器测试通过；
- Windows x64 候选包在干净 runner 上安装、冷启动、导入、重启恢复和卸载通过；
- 核心闭环有一条真实 provider 流式冒烟，CI 中则用确定性本地 SSE fixture 验证协议；
- 关键窗口矩阵覆盖纸面 / 墨石、三栏 / 两栏 / 沉浸、中文 / 英文、100% / 125% / 160%；
- 截图比较锁定 token、尺寸、溢出、重排和主题，不把跨 OS 字体栅格差异误判为产品差异；
- 用户数据测试覆盖外部改写、写入冲突、写中崩溃、备份恢复、路径越界、符号链接和临时缺席；
- PR 明确区分“代码实现、本地通过、Windows CI 通过、候选包、真实 App 验收”，未经过的阶段不提前宣称完成。

## 共享核心面占用

- `.github/`：新增 Windows 验证与候选包工作流；
- `script/`：新增统一 Windows 构建 / 检查入口时占用；
- `package.json` / `package-lock.json`：把 `windows/` 纳入同一 Node 锁图；
- `Sources/WeiBei/WebEditor/` 与生成资源：只在跨平台桥接必须修正时做向后兼容改动；
- `Package.swift`、Swift 主 App 文件和 `VERSION` 默认不改，确需修改时先在 PR 更新占用说明。

释放条件：Windows 候选包可重复构建、定向检查与 CI 通过，PR 已记录真实窗口冒烟结果和仍保留的平台差异。
