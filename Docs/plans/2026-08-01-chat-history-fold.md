# 主对话历史折叠（长会话可扩展方案）

> 日期：2026-08-01；接续 `2026-08-01-chat-scroll-hang-handoff.md`。
> 前提：build 666 的 eager VStack 修复已由用户滑动验证通过（不再卡死）。

## Context

滑动卡死根因是 LazyVStack 回收/重挂 KaTeX WKWebView 触发 `sizeThatFits` 布局风暴。
止血方案 eager VStack 消除了 remount，但代价是所有消息的 WebView 常驻——超长会话
打开慢、内存高。任何"回收再装回"式虚拟化（预测量固定 frame / NSTableView 托管 /
受控 lazy 占位）都绕不开 remount 成本，只是挪到别的时机。

本方案改为**根本不渲染没人看的历史**：打开会话只挂载最近一页消息，更早的历史折叠
成"查看更早消息"按钮，点击才向上追加渲染。渲染管线、高度冻结、`requiresWebRenderer`
路由零改动，Markdown/KaTeX 渲染无任何回退。

## 实现（均在 `Sources/WeiBei/Views/NotesAgentView.swift` `AgentPaneView`）

- [x] `agentVisibleMessageLimit`（初始 30 = `agentHistoryPageSize`）+ `visibleAgentMessages = store.messages.suffix(limit)`
- [x] `ForEach(visibleAgentMessages)` 替换 `ForEach(store.messages)`；窗口上方渲染 `agentHistoryRevealButton`
- [x] **窗口只增不减**：消息追加时 limit 同步增长（已挂载的行永不因折叠被拆——否则重蹈 remount 覆辙）；会话切换（`activeStudySessionID` 变化或 count 减少）重置为 30
- [x] 展开时记录原顶部消息 id，布局后 `proxy.scrollTo(anchor: .top)` 保持阅读位置
- [x] 对话轨道（rail）跳转折叠中的轮次时先 `revealAgentHistory(throughMessageID:)` 展开到位
- [x] selfcheck 新增契约：折叠存在、窗口只增不减、rail 联动（`Sources/WeiBeiSelfCheck/main.swift`）
- [x] 顺带修复遗留：`afc7f2c` 删掉了 "No scrollTargetLayout…" 护栏注释导致 HEAD selfcheck 失败（build 666 是带着失败自检出的包），已恢复注释，selfcheck 全绿

## 验证

- [x] `swift build` 通过
- [x] `swift run WeiBeiSelfCheck` → "WeiBei self-check passed"
- [ ] 打包 `--package` 后用户验证：
  1. ≤30 条会话行为与 build 666 完全一致（滑动不卡、渲染完整）
  2. >30 条长会话：打开只见最近 30 条 + "查看更早的 N 条消息"按钮；点击展开一页且阅读位置不跳
  3. 展开后来回拖滚动条不卡死；公式/列表/表格渲染正常

## Review

（待用户验证后补充）
