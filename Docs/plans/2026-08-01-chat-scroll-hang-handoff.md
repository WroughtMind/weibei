# Handoff：主对话滑动卡死 / Markdown 渲染

> 给 Fable（或后续接手者）。  
> 日期：2026-08-01  
> 作者会话：Cursor Grok 续修 Grokbuild 未完成项 + 对话区滑动卡死排查  

---

## 现场

| 项 | 值 |
|---|---|
| Worktree | `/private/tmp/WeiBei-bun-restore`（不要用陈旧的 `~/projects/weibei` / `Documents/魏碑`） |
| 测试 App | `/private/tmp/WeiBei-bun-restore/dist/魏碑.app` |
| Branch | `codex/fix-global-chat-open-material-focus` |
| PR | https://github.com/weibei-app/weibei/pull/129 |
| 文档落盘时 tip | `afc7f2c`（曾打包 build **666**） |
| 打包 | `WEIBEI_PI_REDISTRIBUTION_REVIEWED=1 ./script/build_and_run.sh --package` |

用户复现材料：桌面计量 HTML（如 `…上机题预测_完整解答与模板导航.html`）。

卡死截图点：对话滑到「你能不能介绍一下你自己」那条 **带 bullet list 的自我介绍**（iClip 截图曾存于  
`~/Library/Application Support/iClip/.tmp/魏碑 Clipping (01∶31∶46).tiff`）。

---

## 产品约束（必须遵守）

1. **禁止**靠关掉 Milkdown/KaTeX、把列表改成原生 `AttributedString` 来“止血”——用户已明确反对（`72f39a1` 做过，已在 `afc7f2c` 撤回）。
2. 公式 / 列表 / 表格 / 代码块等 **完整 Web Markdown 渲染要保留**。
3. 先有 **runtime 证据**（`sample` / cpu diag）再改；改完要打包让用户滑对话区验证。
4. 默认中文、简洁；不要乱扩大 scope。

---

## 已证实的卡死族（同一大类：主线程布局风暴）

| 场景 | 证据 | 根因摘要 | 状态 |
|---|---|---|---|
| 发送消息 | cpu diag / sample | `flushPendingWorkspaceSave` → MainActor RunLoop | ✅ `c1001dd` |
| 打开资料进全局对话 | — | 无 grant 时看不到打开材料 | ✅ `201b0ef` |
| 读 HTML 滚动 | sample | GeometryReader 测 WKWebView；viewport `@Published` | ✅ `5bdabfc` `28b878a` |
| selection / SelectionOverlay | sample 661 | `selectionchange` → store 发布 + `.textSelection` | ✅ `04f6dc7` 等 |
| 对话区拖滚动条 | **sample build 663/664** | `NSScroller.trackKnob` → ViewGraph → **`AgentMessageMarkdownText` / `RichMarkdownEditorView` `sizeThatFits`** ~100% CPU | ⚠ 用 VStack 规避中 |

最新卡死栈特征（对话滑动）：

- `SelectionOverlay` 已为 0（chat 气泡 `.textSelection` 已关）
- 热点：`sizeThatFits` 数百次、`PlatformView`、`AgentMessageMarkdownText`、`RichMarkdownEditorView`
- 用户拖的是 **对话区 scroller**，不是阅读器

本地 sample 文件（若仍在）：

- `/tmp/weibei-chat-scroll-hang.txt`
- `/tmp/weibei-clip-hang.txt`
- `/tmp/weibei-hang-again.txt`
- `/tmp/weibei-scroll-only-hang.txt`

---

## 当前代码策略（`afc7f2c`）

### 保留渲染

- `AgentChatKaTeXMarkdown.requiresWebRenderer`：**已恢复**列表/多段等走 Web（`- 单项列表` → `true`）
- 主路径 `usesFinalizedKaTeX: !isFailureMessage` 等保留

### 滑动规避

- 主对话 `AgentPaneView`：`LazyVStack` → **`VStack`**（避免回收时拆装 KaTeX WKWebView）
- `MarkdownPreviewView`：有 height seed 时 `onAppear` **保持冻结**；冻结后不再改 SwiftUI 帧高
- `finalizedMarkdownBody`：ready 用 **opacity**，避免拆 ZStack 节点触发 remasure
- compact `MarkdownWebView.fittingSize` 短路 Auto Layout

### 已知取舍（用户已问过）

- VStack：消息全挂着，长会话内存/进对话成本更高；普通学习会话通常可接受
- **不是最终架构**：更稳的是「完整 Markdown + 高度冻结的稳定单元格 / AppKit 列表」，而不是再切回会 remount WebView 的裸 `LazyVStack`

---

## 明确不要再做的

- ❌ 把 bullet list / 普通 Markdown 改回原生-only 来消卡死
- ❌ 关掉 RichAnswer / KaTeX「先能滑再说」
- ❌ 只改注释/selfcheck 不打包验证

---

## 相关提交（时间线摘要）

| Commit | 说明 |
|---|---|
| `c1001dd` | 发送时异步 flush，避免主线程 RunLoop 刷盘 |
| `201b0ef` | 全局对话注入当前打开资料 |
| `5bdabfc` | 阅读器不用 GeometryReader 测 WKWebView/PDFView |
| `28b878a` | 阅读滚动静默 viewport，避免对话 WKWebView 卡死 |
| `8785f6d` | 发送路径聊天 PlatformView / popover 热点 |
| `04f6dc7` | HTML 滚动抑制 selection 广播；关掉聊天气泡 textSelection |
| `f86bfc9` | 滚动勿 schedule save；24pt 宽度桶解冻 |
| `a9bfdcc` | LazyVStack 回收时保持 KaTeX 行高冻结 |
| `72f39a1` | ❌ 列表改原生（体验回退，已撤回） |
| `afc7f2c` | 恢复 Milkdown Markdown；主对话改 VStack |

---

## 建议下一步（按优先级）

1. **验证 build 666（或最新包）**：打开有列表+公式的长对话，反复拖对话区滚动条到简介那条；确认 Markdown 视觉与滑动都 OK。
2. 若仍卡：立刻  
   `sample <pid> 3 -f /tmp/weibei-chat-hang-N.txt`  
   看是否变成 `RichAnswerHost` / `RichAnswerWebRuntimeView`（富回答 WebView 同类问题）。
3. **正经方案**（保 Markdown）：
   - 预测量/缓存行高，单元格 **固定 frame**，滚动期禁止 `contentHeight` / `objectWillChange`；或
   - AppKit `NSTableView` / `NSCollectionView` 托管已测高的 WKWebView 单元格；或
   - 受控的 lazy：只对 **离屏且已冻结高度** 的行回收，回收时保留高度占位、禁止重新 `fittingSize` 进 WebKit。
4. 评估是否要把 VStack 阈值化（如消息数 > N 再换策略），但前提是 lazy 路径证明不再 remount 风暴。

---

## 关键文件

- `Sources/WeiBei/Views/NotesAgentView.swift` — `AgentPaneView` 消息列表、`MarkdownPreviewView`、`AgentMessageMarkdownText`
- `Sources/WeiBei/Views/RichMarkdownEditorView.swift` — `sizeThatFits` / `MarkdownWebView.fittingSize`
- `Sources/WeiBei/Support/AgentChatKaTeXMarkdown.swift` — `requiresWebRenderer`（勿再收窄列表）
- `Sources/WeiBei/Views/RichAnswerHost.swift`
- `Sources/WeiBei/Views/RichAnswerWebRuntimeView.swift` — 下一嫌疑
- `Sources/WeiBei/Stores/WorkspaceStore.swift` — 滚动勿乱 `@Published`（viewport/selection/save 已有一批修复）
- `Sources/WeiBeiSelfCheck/main.swift` — 相关契约断言

---

## 一句话

用户要的是：**对话 Markdown 渲染保持原样，滑动不再因 Lazy 回收 KaTeX WKWebView 卡死**。当前 VStack 是止血；请在不砍渲染的前提下做成可缩放的稳定单元格方案，并用 `sample` 证明主线程不再空转。
