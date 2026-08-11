# 布局循环崩溃交接：给 Fable（2026-08-11）

状态：**待排查**（用户复现并提供完整 Crash Report；记录人：Grok / hard stop 收尾会话）。

## 一句话

用户用 hard stop 合入后的 main 候选 `魏碑.app` 点几下就「卡死」——实际是 **主线程 Auto Layout / SwiftUI 布局死循环断言崩**，不是无响应挂起，也不是 hard stop 栈上的存储/watcher 路径。

## 给用户的结论（已口头说明）

- 不是打开错了包；包是 `730b3954` 线、adhoc 签名候选。
- 不是 hard stop（C1–C3 / H1–H5）写盘或监听代码直接炸的——**崩溃栈 0 帧落在 WorkspaceStore / NoteFileWatcher**。
- 是 **界面布局**：`NSWindow _postWindowNeedsUpdateConstraints` 在 display cycle 里被反复 `setNeedsUpdateConstraints`，最终 `EXC_BREAKPOINT` + `NSException`。
- 因此：**该 `/tmp` 候选不能当日常验收包**；hard stop 功能线仍以 CI/自检为准，UI 稳定性是另开的阻断问题。

## 复现环境（已确认）

| 项 | 值 |
|---|---|
| 机器 | Mac16,12（MacBook Air M4），16GB，macOS **26.5 (25F71)** |
| 包路径 | `/private/tmp/weibei-smoke-hardstop/dist/魏碑.app` |
| Bundle ID | `com.changfenhuang.weibei` |
| Version | **0.1.0 (900)** |
| 代码基线 | 打包时 main **`730b3954`**（含 #189/#190/#191 hard stop；其后文档 #192） |
| 启动 | `open` 该 app；PID **41705** |
| 时间线 | Launch **17:25:47** → Crash **17:26:54**（约 **67 秒**）+0800 |
| 用户操作 | 「操作几下」即崩；**未**要求按技术清单验收；具体点了哪几个 UI 控件 **未精确记录** |

### 本地证据文件（本机）

```text
# 系统崩溃报告（完整 IPS）
~/Library/Logs/DiagnosticReports/WeiBei-2026-08-11-172705.ips

# Incident
0F31D5A3-E49E-4CE3-87A9-5358913A079C

# 候选包（若仍在）
/tmp/weibei-smoke-hardstop/dist/魏碑.app
# 二进制时间戳约 2026-08-11 17:02，~27.8MB arm64 adhoc
```

用户已把 Translated Report 贴进会话；IPS 与报告一致。

## 崩溃摘要（从 IPS / Translated Report）

```text
Exception Type:    EXC_BREAKPOINT (SIGTRAP)
Exception Codes:   0x0000000000000001, 0x000000018b411640
Termination:       SIGNAL 5 Trace/BPT trap
Triggered:         Thread 0 / com.apple.main-thread
```

### 关键路径（精简）

```text
NSException throw
→ -[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]   // AppKit +1716
→ -[NSView _informContainerThatSubviewsNeedUpdateConstraints] ×N
→ -[_NSConstraintBasedLayoutHostingView ...]
→ -[NSView setNeedsUpdateConstraints:]
→ SwiftUI NSHostingView.setNeedsUpdate / requestUpdate
→ SwiftUICore GraphHost graphInvalidation / flushTransactions / render
→ NSHostingView.layout  (in NSAnimationContext.runAnimationGroup)
→ NSView layout 深树（_layoutSubtreeWithOldSize 多次嵌套）
→ NSWindow layoutIfNeeded
→ NSDisplayCycleFlush / CATransaction commit
→ run loop
→ NSApplicationMain / SwiftUI App.main / WeiBei_main
```

**解读（高置信度）：**

1. 正在 **display cycle 的 layout 阶段**。
2. SwiftUI 图又 **invalidate → setNeedsUpdateConstraints**。
3. AppKit 认为窗口 **约束更新次数超过合理次数**（常见文案：*more Update Constraints in Window passes than there are views*；本 IPS 的 `asiDescriptions` 未单独抽出可读 reason 字符串，但入口与栈与该类断言一致）。
4. 进程被 SIGTRAP 杀掉 → 用户体感「卡一下没了」。

### 与 hard stop 的关系

| 维度 | 判断 |
|---|---|
| 栈上是否有 `WorkspaceStore` / 写盘 / `NoteFileWatcher` | **否** |
| hard stop PR 是否改 UI 布局核心 | **基本否**（#190 改 watcher；#189/#191 改 store/scan/rebind 文案少量 UI） |
| 能否完全排除回归 | **不能 100%**：`@Published` 更频繁或启动后 reconcile 可能 **加剧** 布局刷新；但 **直接锅不能甩 hard stop 数据路径** |
| 历史同型 IPS | 本机 Retired 里 2026-08-05/08 的 WeiBei IPS **未** 带 `_postWindowNeedsUpdateConstraints`；**此形态本次明确记一笔** |

## 高嫌疑代码区（给 Fable 的优先排查表）

按「布局过程中触发尺寸回写 / 强制 layoutSubtree」排：

1. **`Sources/WeiBei/Views/ContentView.swift`**  
   - 多处 `GeometryReader`  
   - `splitView.layoutSubtreeIfNeeded()`（约 1428 一带）  
   - 分栏宽度 capture / snap 与 SwiftUI 宿主互踢

2. **`Sources/WeiBei/Views/StableDocumentWorkspace.swift`**  
   - `agentHost.layoutSubtreeIfNeeded()`（约 684）  
   - NSSplitView 与 SwiftUI hosting 混布

3. **`Sources/WeiBei/Views/CourseDrawerHost.swift`**  
   - `layoutSubtreeIfNeeded()` + `hostingView?.layoutSubtreeIfNeeded()`（约 115–116）

4. **`Sources/WeiBei/Views/NotesAgentView.swift`**  
   - 多处 GeometryReader / PreferenceKey  
   - 注释已写明 **不要** 在 LazyVStack 上搞 GeometryReader 反馈（约 2536、4754、5064）  
   - 仍可能有悬浮输入 / 宽度 preference 回写

5. **`Sources/WeiBei/Views/ReaderView.swift`**  
   - 已有 2026-08-01 hang 注释：`GeometryReader` 祖先 + WKWebView/PDFView  
   - 若用户打开了阅读器，优先怀疑

6. **`Sources/WeiBei/Views/RichAnswerHost.swift` / GeneratedRichAnswerView**  
   - 多个 GeometryReader；WebKit 区域 VM 中有较大 WebKit Malloc（本次约 256MB 级，属线索非根因）

7. **`Sources/WeiBei/Support/QuietScrollers.swift`**  
   - `layoutSubtreeIfNeeded()`（约 44）

## 建议复现步骤（给 Fable）

1. 干净 main 打包（**不要用 iCloud 下的 Documents worktree 编**，易「file modified during build」）：
   ```bash
   git fetch origin main
   git worktree add /tmp/weibei-layout-repro origin/main
   cd /tmp/weibei-layout-repro
   ./script/build_and_run.sh package
   open dist/魏碑.app
   ```
2. 启动后 **1 分钟内** 做常见操作：进课程 → 点笔记 → 点资料/Chat 分栏 → 拖分栏 → 开阅读器。  
3. 若崩：对照新 IPS 是否仍 `_postWindowNeedsUpdateConstraints`。  
4. 调试手段：
   - Xcode 跑 Debug，Exception Breakpoint 抓 `NSException` reason 全文  
   - 临时 `OS_ACTIVITY_MODE` / AppKit 约束日志  
   - 二分：注释可疑 `layoutSubtreeIfNeeded`、PreferenceKey 写回 `@State` 的路径

## 修复方向（建议，未实施）

- **禁止** 在 layout 回调链里同步改会触发 `setNeedsUpdateConstraints` 的 `@State` / 分栏常量（改为 `DispatchQueue.main.async` 或下一 runloop）。  
- 审计所有 `layoutSubtreeIfNeeded()` 调用点：是否在 `updateConstraints` / `layout` 期间被 SwiftUI 再次进入。  
- GeometryReader + PreferenceKey 写回父级尺寸：改为 `onGeometryChange`（新 API）或固定 min 宽度，打断反馈环。  
- 阅读器：严格遵守「GeometryReader 不作 WKWebView/PDF 祖先」。  
- 修完后：同机 macOS 26.5 上 **手动 5 分钟** 点课程/笔记/Chat/分栏；并保留一份 IPS 对比「不再出现该断言」。

## 明确不在本单范围

- hard stop 功能回退或重测 17 条验收清单  
- 为「通过验收」再开 adhoc 包糊弄用户  
- 在未复现前大改存储层

## 相关会话上下文

- hard stop 三 PR：#189（完整性）、#190（watcher）、#191（课程边界），文档 #192  
- 冒烟文档：`Docs/plans/2026-08-11-hardstop-smoke-and-acceptance.md`  
- 用户反馈路径：Agent 打开 `/tmp/weibei-smoke-hardstop/dist/魏碑.app` → 操作几下 → 贴 Translated Report  

## 交接检查清单（Fable）

- [ ] 用 Exception Breakpoint 拿到 **完整 NSException reason 字符串** 写入本文件  
- [ ] 确认是否必现；记录最小操作路径  
- [ ] 定主因文件与是否 layout 反馈环  
- [ ] 出最小修复 PR（避免再涨 WorkspaceStore 无必要行数）  
- [ ] 用户机 macOS 26.5 再验一次「点几下不崩」

---

**记录时间：** 2026-08-11  
**记录目的：** 用户明确要求「记一下、好好说明、给 Fable 看」。
