# 卡顿与布局崩溃根因交接：给 Grok（2026-08-11）

状态：**根因已定位，待修复**（记录人：Fable / hunt 排查会话）。承接 `Docs/plans/2026-08-11-layout-crash-fable-handoff.md`（Grok → Fable 的原始交接），本文档是排查结果 + 修复任务书。

## 一句话

用户报的「打字/换行卡、侧边栏与顶部三按钮动画掉帧、点几下崩溃」是**三个独立问题**，全部在 7月26日（83bc301c，用户上一个流畅版本）→ 当前 main 的回归窗口内引入：① 阅读器 `updateNSView` 每帧同步走 WebKit IPC（卡顿主因）；② SwiftUI 测量-回写布局反馈环（崩溃根因，`AttributeGraph cycle` 已实锤）；③ 打开课程资料新加了 identity 严格校验拒绝门（违反已批准的产品红线）。三个修复都是小改动。

## 排查方法与证据总览

- 复现机 = 用户机（Mac16,12 / M4 / 16GB / macOS 26.5）。候选包 `/tmp/weibei-smoke-hardstop/dist/魏碑.app`（0.1.0 (900)，main@730b3954 线）由 Fable 从终端直接执行、stderr 接管；用户亲自操作复现（打字、换行、点侧边栏、反复点顶部三个面板按钮）。
- 自动监控：CPU ≥35% 即 `sample` 主线程（1ms 粒度）。用户操作期间 CPU 反复冲到 **85.9% / 88.2%**，共抓 7 份样本。
- 关键运行时证据（原件在 `/tmp`，重启即失，要点已内嵌本文档）：
  - `/tmp/weibei-stderr.log`：
    ```
    === AttributeGraph: cycle detected through attribute 889236 ===
    === AttributeGraph: cycle detected through attribute 889236 ===
    ```
    （SwiftUI 官方图循环警告，布局反馈环实锤。）
  - `/tmp/weibei-sample-1827*.txt` ×7（每份 3000+ 样本）。两条热栈：
    ```
    热栈 A（单次阻塞 37ms+，37 连续样本）：
    WebReaderRepresentable.updateNSView (ReaderView.swift:2349)
    → Coordinator.applySelectionAskMarksIfNeeded (ReaderView.swift:2981)
    → -[WKWebView evaluateJavaScript:] → WebKit::WebPageProxy → XPC 序列化/发送

    热栈 B（busy 段大头，display cycle 反复重排）：
    NSDisplayCycleFlush → NSWindow layoutIfNeeded → 深层 _layoutSubtreeWithOldSize
    → NSHostingView.layout → render → GraphHost.flushTransactions
    → GeometryReaderLayout.placeSubviews → sizeThatFits → _ZStackLayout.sizeThatFits
    ```
  - 崩溃报告：`~/Library/Logs/DiagnosticReports/WeiBei-2026-08-11-172705.ips`（`_postWindowNeedsUpdateConstraints` 断言，形态与热栈 B 同源）。
- 基线对照：三个问题的代码在 `83bc301c`（7/26）均**不存在**（`git show 83bc301c:<file>` 逐一比对过）——用户「之前明明很流畅」属实。

---

## 问题一（卡顿主因）：阅读器 updateNSView 每帧同步 WebKit IPC

### 根因

`WebReaderRepresentable.updateNSView`（`Sources/WeiBei/Views/ReaderView.swift:2349` 起）在「签名未变」的 else 分支里**每次都**调用：

```swift
context.coordinator.applySearch(in: view)
context.coordinator.applySelectionAskMarksIfNeeded()
```

SwiftUI 动画期间（面板开关、分栏动画）representable 的 `updateNSView` **每帧重进**。`applySelectionAskMarksIfNeeded`（`:2977`）虽有字符串去重 guard，但 sample 证明它反复走到 `evaluateJavaScript`，且**单次调用的主线程同步段（跨进程序列化+发送）就占 37ms+**——动画每帧背一次，16ms 帧预算直接爆掉。这就是「点顶部三个按钮动画不顺畅、点侧边栏延迟」的主因。

两个叠加因素：

1. `selectionAskMarksJSON`（`ReaderView.swift:316-330`）用 `JSONSerialization.data(withJSONObject:)` **不带 `.sortedKeys`**——字典 key 输出顺序不保证，同一份数据可能序列化出不同字符串，打穿 `selectionAskMarks != lastAppliedSelectionAskMarks` 去重 guard（`:2978`）。
2. 即使 guard 生效，`applySearch` 与 marks 应用都在 `updateNSView` **同步路径**上，本质上把 IPC 成本挂在了渲染帧里。

### 修法

1. `selectionAskMarksJSON` 改用 `JSONEncoder`（输出稳定）或 `JSONSerialization` + `.sortedKeys`，保证同数据 → 同字符串。
2. marks / search 的应用**移出 `updateNSView` 同步路径**：coordinator 记录目标状态，真正变化时经 `Task { @MainActor … }` 或 `DispatchQueue.main.async` 异步应用——渲染帧只做指针级比较，绝不同步做 IPC。
3. 审计同文件 `applySearch` 的去重与调用时机，同样处理。

### 验收

- 修后同机重跑「监控 + 用户点顶部三按钮」流程：动画期间 sample 中 `evaluateJavaScript` 不再出现在 `updateNSView` 栈下。
- 面板开关动画目测流畅（用户复验）。

---

## 问题二（崩溃根因）：SwiftUI 测量-回写布局反馈环

### 根因

崩溃形态：布局 pass 中 SwiftUI graph 反复失效 → `setNeedsUpdateConstraints` → AppKit「同一 display cycle 内约束更新次数超限」断言（`_postWindowNeedsUpdateConstraints`）→ SIGTRAP。运行时 `AttributeGraph: cycle detected ×2` 证明图内存在真循环；振荡收敛慢时表现为每帧重排（热栈 B），把主线程打满（放大问题一的卡顿）；某次点击把多轮更新挤进同一 display cycle 即触发断言崩溃。

**第一嫌疑（形态完全吻合）**：`Sources/WeiBei/Views/NotesAgentView.swift:3095-3112` 悬浮选区问答面板的高度反馈环：

```swift
ScrollView { LazyVStack { … } .background { GeometryReader { proxy in
    Color.clear.preference(key: FloatingSelectionFeedHeightKey.self, value: proxy.size.height)
} } }
.frame(height: resolvedFloatingFeedHeight)          // ← 高度依赖回写值（:3166-3172）
.onPreferenceChange(FloatingSelectionFeedHeightKey.self) { height in
    guard userFeedHeight == nil, height > 1,
          abs(height - measuredFeedContentHeight) > 1 else { return }
    withAnimation(WeiBeiMotion.layout) {            // ← 每次回写包动画事务
        measuredFeedContentHeight = height          // ← 回写 state
    }
}
```

环：内容高度测量 → 写 `measuredFeedContentHeight` → `frame(height:)` 变化 → **LazyVStack 在新可视高度下实例化/回收不同行，内容高度再次变化** → 再回写。`>1pt` 容差挡不住两态振荡（高度在 A/B 间交替且 |A−B|>1）；`withAnimation` 使每次回写都排 AsyncTransaction（崩溃栈里 `flushTransactions` 处理的正是它）。

**已排除**：`ReaderPaneSizeKey`（`ReaderView.swift:237-252`）是 background 兄弟探针，`measuredPaneSize` 不反向决定 pane 尺寸，属单向测量——修复时确认一遍其消费方即可，不需要动。

### 修法

1. `FloatingSelectionFeedHeightKey` 断环，任选其一（推荐 a）：
   a. 回写加**振荡锁**：记录最近两次回写值，若新值与上上次值相差 ≤1pt（两态交替特征）则锁定不再回写，直到 `showsFloatingFeed` / 消息数变化才解锁；同时去掉 `withAnimation`（高度自适应不需要动画事务，需要过渡可用 `.animation(_:value:)` 挂在 frame 上）。
   b. 不用内容高度反馈：`automaticContentHeight` 改为按 `visibleFloatingMessages` 的条数/估算高度计算（纯函数，无测量回写）。
2. 修后 **Debug 构建复验**：同操作路径下 stderr 不再出现 `AttributeGraph: cycle detected`。若 Debug 下 cycle 仍在且指向别的 attribute，用 `AGDebugServer` / Xcode SwiftUI instrument 定位后按同思路断环——「cycle 警告清零」是本项的硬验收线，不以「崩溃没复现」代替。

### 验收

- Debug 构建 + 用户操作路径（打字、换行、选中文字唤出悬浮面板、点面板按钮）5 分钟：stderr 零 `cycle detected`。
- 同机再出候选包，用户「点几下不崩」+ 无新的 `_postWindowNeedsUpdateConstraints` IPS。

---

## 问题三：打开课程资料的 identity 拒绝门（产品红线回归）

### 根因

`WorkspaceStore.swift:10375-10404` `openCourseMaterial`：7/26 基线版本**直接打开**（旧版 `:1655-1667` 无任何门槛）；现行版本在打开前要求 `resolveTrackedImportedFile` 解析成功 + 文件可读 + **磁盘 identity 与记录严格相等（`==`）**，任一不满足 → 拒绝打开 + transient 提示「"××"暂时不在课程文件夹中…」。

这违反存储简化方案（`Docs/plans/2026-08-11-storage-simplification.md`）用户拍板的红线：「identity 只用于尽力找回，**永不用于拒绝**」。且严格 `==` 连 PR #176 的 `matchesAcrossVolumeDrift` 容忍都没用——用户课程库在 iCloud 同步盘（Documents），文件被驱逐再下载 inode 就变，用户什么都没做也会被拒开（用户实测截图：「新概念笔记」被拒）。提示走 transient 通道这点合规，问题在「拒绝」行为本身。

### 修法

1. 删除 identity 相等这道拒绝条件：`resolveTrackedImportedFile` 解析出可读文件就打开；identity 不一致时按 #176 的自愈路径静默刷新记录（该机制已存在），最多 NSLog 一条。
2. 仅当文件**真的解析不到/不可读**时保留现提示（这属于「物理上无法打开」，不是官僚关卡）。
3. 顺带排查同窗口内是否有同型新增门：`grep -n "暂时不在\|不在课程文件夹" Sources/` + 检查 `courseMaterialIsAvailable` 的消费方，确认没有第二处「identity 严格比对 → 拒绝用户操作」。

### 验收

- SafetyTests 补一条：记录 identity 与磁盘不一致（模拟 inode 变化）但文件可读 → `openCourseMaterial` 返回 true 且记录被自愈刷新。
- 用户机上再点「新概念笔记」能直接打开（若该文件物理存在）。

---

## 次级审计项（顺带，不阻塞）

1. `StableDocumentWorkspace.swift:684` `agentHost.layoutSubtreeIfNeeded()`：在共享 frame 路径强制同步布局含 WKWebView 的 agent 子树，回归窗口内新增。样本里只出现 1 次，不是本次主因，但属于「layout 链内强制布局」反模式——确认其调用时机不会落在 `layout()` 回调内（`containerDidLayout` 有尺寸 guard，目前看安全），加注释说明约束。
2. `AgentMessageMarkdownText.renderedText / finalizedMarkdownBody`（NotesAgentView.swift:5247-5460）在动画帧内反复出现于样本——对话 markdown 每帧重渲染，考虑按 message id + 内容缓存。属性能优化，不在本单必修。

## 建议 PR 切分与流程（AGENTS.md 合规）

- **PR-1 `codex/fix-reader-frame-ipc`**（问题一 + 问题二，同为「渲染/布局帧内做重活」类，主要文件 ReaderView.swift + NotesAgentView.swift，无共享核心面冲突可合为一个 PR；拆两个亦可）。
- **PR-2 `codex/fix-open-material-gate`**（问题三，占用 `WorkspaceStore.swift` 需声明）。
- 每 PR：最新 origin/main 开分支（worktree，不碰主仓脏工作区）+ 草稿 PR + CI 绿（swift build / WeiBeiSelfCheck / WeiBeiSafetyTests）。
- 全部合入后重出候选包，用户复验三件事：顶部三按钮动画流畅、点几下不崩、「新概念笔记」能打开。

## 明确不做

- 不回退 hard stop 三 PR（#189/#190/#191）——崩溃/卡顿栈上零 hard stop 代码，Grok 原判断正确。
- 不动主对话 WebView 两条不变量。
- AgentMessageMarkdownText 缓存、`layoutSubtreeIfNeeded` 重构等性能优化不在本单。

## 遗留提醒

- Fable 启动的诊断实例（pid 53817）可能仍在运行，处理前 `pkill -f "dist/魏碑.app"` 收掉。
- `/tmp/weibei-sample-1827*.txt`、`/tmp/weibei-stderr.log` 重启即失，需要留档就趁早拷走；本文档已内嵌关键摘录。
- 崩溃 IPS：`~/Library/Logs/DiagnosticReports/WeiBei-2026-08-11-172705.ips`。

---

**记录时间**：2026-08-11
**记录目的**：hunt 排查结论 + 修复任务书，交 Grok 实施；修完建议回到 Fable 复查（对照本文档验收线逐条验）。
