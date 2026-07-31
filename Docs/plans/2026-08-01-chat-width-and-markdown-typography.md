# 计划：对话区宽度自适应 + 聊天/笔记 Markdown 排版美化

> 日期：2026-08-01。执行者：Grok（或任意接手 Agent）。
> 流程：按 AGENTS.md，从最新 `origin/main` 开短分支 `codex/chat-width-markdown-typography`，当天推草稿 PR。
> 共享文件占用需在 PR 声明：`Sources/WeiBeiSelfCheck/main.swift`（新增/更新契约断言）。

---

## 背景与目标

用户反馈三件事：

1. **对话区显示的最大范围太小**——沉浸式内容列压在 920pt；非沉浸式（三栏）压在 560pt，把窗格拉宽内容也不跟着变宽。目标：两种模式下内容宽度都随实际可用宽度自适应，只保留合理的可读性上限。
2. **AI 回答排版没有字号层级、密密麻麻**。已定位两个实锤原因（见下）。目标：沉浸式与非沉浸式下阅读都舒服。
3. **笔记和 AI 回答的 Markdown 样式整体偏丑**，希望美化。

### 已取证的根因（不要重复排查）

- `index.html:361-363` 只定义了 h1/h2/h3 字号，**h4–h6 没有任何规则**。现代模型答题惯用 `####` 小节标题，h4 按浏览器默认渲染成 1em 加粗，和正文几乎无差别——这就是"没有字号变化"的直接原因。
- 聊天 WebView 永远走 compact 模式（`data-weibei-compact-preview="true"`）：正文 14px/行高 1.68，**不区分三栏窄条和沉浸式全屏**。920pt 宽列配 14px 字，行太长、字太小、段距 `.55em`、标题距 `.55em/.25em` 全被压缩 → "密密麻麻"。
- 宽度上限硬编码在 `NotesAgentView.swift` 的 `AgentChatLayoutMetrics`（约 1690 行）：`compactMaxWidth=560`、`wideMaxWidth=920`、`wideComposerMaxHeight=220`。

---

## 硬约束（违反任何一条 = 返工）

1. **不得触碰滑动卡死修复线的不变量**：eager VStack、高度冻结机制、`agentVisibleMessageLimit` 折叠窗口只增不减、`fittingSize` 短路、`requiresWebRenderer` 路由。这些由 `WeiBeiSelfCheck` 与 `WeiBeiWebEditorCheck` 的源码契约守护——**契约允许同步更新以匹配新设计，但不许删弱其守护意图**。
2. 改动后 `swift build`、`swift run WeiBeiSelfCheck`、`swift run WeiBeiWebEditorCheck` 三个必须全绿才能推。CI 挂了必须修，不许绕。
3. 打包（`WEIBEI_PI_REDISTRIBUTION_REVIEWED=1 ./script/build_and_run.sh --package`）交用户滑动冒烟后才算完成。
4. 默认中文提交信息；不扩大 scope（不做单 WebView 重构、不做消息操作条，那是另外的任务）。

---

## 任务一：对话内容宽度自适应

文件：`Sources/WeiBei/Views/NotesAgentView.swift` → `AgentChatLayoutMetrics`。

- [ ] 沉浸式：`contentWidth = min(usable, max(920, usable * 0.78))`，并把绝对上限提到 **1180pt**（超宽屏不无限拉长行）。即窗口 ≤1200 时基本占满（留 gutter），更宽时按 78% 增长到 1180 封顶。
- [ ] 非沉浸式（三栏）：`contentWidth = min(usable, 760)`（原 560）。窄条时 usable 本来就小，不受影响；用户把对话窗格拉宽时内容跟着变宽，760 后封顶。
- [ ] 输入框：`wideComposerMaxHeight` 220 → **340**；`wideComposerMinHeight` 108 保持。三栏 composer 不变。
- [ ] 侧边距 `wideSideGutter=28`、`compactSideGutter=12` 保持不变。
- [ ] 同步更新 `WeiBeiSelfCheck` 中断言 "920×108+"/"560×52" 的契约字符串（搜 `immersive Codex-like chat is 920`），改为新值并保留其守护意图（"一条居中阅读列"）。
- [ ] 验证宽度变化链路：内容宽度变化 → `agentChatLayoutWidth` environment → 24pt 宽度桶跨桶时行高解冻重测（现有机制，勿改）。拉伸窗格时短暂重测是预期行为，只要不持续空转即可。

## 任务二：聊天排版分档（沉浸式 vs 三栏）

文件：`Sources/WeiBei/Views/RichMarkdownEditorView.swift`、`Sources/WeiBei/Resources/Editor/index.html`、`Sources/WeiBei/Views/NotesAgentView.swift`。

- [ ] `RichMarkdownEditorView` 新增参数 `isChatWideTypography: Bool = false`，沿 `AgentMessageMarkdownText → MarkdownPreviewView → RichMarkdownEditorView` 传入（`AgentPaneView` 处取 `wide`；selection float 传 false）。
- [ ] 注入：仿照 `weiBeiMarkdownCompactPreview`（RichMarkdownEditorView.swift:335,338）在用户脚本设置 `window.weiBeiChatWideTypography` + `document.documentElement.dataset.weibeiChatWide`。
- [ ] **布局切换（沉浸式↔三栏）时 WebView 不重建**（不变量 1），所以 `updateNSView` 中检测该值变化后 `evaluateJavaScript` 更新 dataset。
- [ ] **高度缓存风险处理（用户点名要求）**：排版档改变 → 同一消息同一宽度桶的高度不同。两处必改：
  - `AgentFinalizedMarkdownHeightCache.cacheKey` 加入排版档标记（如 `:wide` / `:compact`）；
  - `MarkdownPreviewView` 在排版档变化时解冻高度（仿 `layoutWidthKey` 跨桶解冻的 `onChange` 写法），触发一次重测。
  - 缓存是会话内存级（`private static var values`），无持久化污染，但**同会话内切换布局必须走上面两条**，否则行高错位。
- [ ] `index.html` 新增 `:root[data-weibei-chat-wide="true"] .ProseMirror`：`font-size: 15.5px; line-height: 1.75;`（三栏保持 14px/1.68 不动）。

## 任务三：Markdown 排版美化（笔记 + 聊天共用 index.html）

全部在 `Sources/WeiBei/Resources/Editor/index.html` 的样式块内，遵循现有的纸墨设计语言（CSS 变量 `--paper/--ink/--cinnabar/--line` 等，勿引入新配色体系）：

- [ ] **补齐标题层级**（当前只有 h1-h3）：
  - `h4 { font-size: 1.05em; font-weight: 650; margin: 1em 0 .45em; }`
  - `h5 { font-size: .95em; font-weight: 650; letter-spacing: .02em; color: var(--muted 或等价); }`
  - `h6` 同 h5 略小。compact 模式给 h4-h6 相应的收紧 margin（仿 355-359 行写法）。
- [ ] **呼吸感**：compact 模式段距 `.55em` → `.7em`；标题上边距 `.55em` → `.9em`（标题前留白比后留白重要）；`li` 间距 `.18em` → `.26em`。非 compact（笔记）段距 `.55em` → `.65em`。
- [ ] **代码块**：确认 fenced code 有独立背景、圆角、内边距与横向滚动；行内 code 有浅底色 + 1px 边框（若已有则微调至与新层级协调）。
- [ ] **表格**：表头加粗 + 底部 1.5px 分隔线；单元格内边距不小于 `.4em .6em`；斑马纹可选（用 `--paper-raised` 低透明度）。
- [ ] **引用块**：左侧 3px `--cinnabar-line` 竖线 + 文字 `--muted`（若已有则协调化）。
- [ ] **水平线 hr**：细线 + 上下 1.4em 间距，用作模型回答的分节符时不能糊在文字上。
- [ ] 所有改动同时检查三个主题（paper/inkstone/stele）下的对比度。

## 任务四：验证与交付

- [ ] `swift build` && `swift run WeiBeiSelfCheck` && `swift run WeiBeiWebEditorCheck` 全绿。
- [ ] `WeiBeiWebEditorCheck` 的运行时测量段（同桶/跨桶 resize、短块）通过——排版改动会改变测量值但断言的是行为不是具体数值；若契约里有过期的实现字符串断言（教训：24pt 桶事件），同步更新。
- [ ] 打包后用户冒烟清单：
  1. 沉浸式：窗口从 1000pt 拉到最大，内容列跟随变宽且行长舒适；输入框可拉到更高。
  2. 三栏：把对话窗格拉宽，内容宽度跟随（760 封顶）；拉伸过程不卡、不闪。
  3. 找一条含 `####` 标题的 AI 回答：h4 与正文有明确大小/间距差。
  4. 含公式+列表+表格+代码块的回答在两种模式下渲染完整、疏密舒适；**沉浸式↔三栏来回切换，行高不错位、不卡死**。
  5. 笔记编辑器排版正常（index.html 是共用的，必须回归）。
  6. 反复拖对话滚动条 —— 滑动卡死不得复发（本清单最高优先级）。
- [ ] PR 写明：实际改动 / 未做内容 / 共享文件占用（WeiBeiSelfCheck）/ 验证命令与冒烟结果。

## 风险与回滚

| 风险 | 处理 |
|---|---|
| 排版档切换导致行高错位 | 任务二的 cacheKey + 解冻双保险；冒烟第 4 项专门回归 |
| 宽度自适应导致拉伸时频繁跨桶重测 | 24pt 桶机制本身就是防抖；冒烟第 2 项观察 CPU，若空转立即 `sample` 取证再改，不许改小桶粒度 |
| index.html 改动影响笔记编辑器 | 聊天专属规则一律挂在 `data-weibei-chat-wide` / `data-weibei-compact-preview` 选择器下；通用美化（任务三）必须冒烟第 5 项回归 |
| 契约断言过期导致 CI 挂 | 改动涉及的字符串断言在同一提交内同步更新（教训见 `7f19394`） |
| 回滚 | 纯 UI/样式改动，revert PR 即回滚，无数据迁移 |

## 不做（out of scope）

单 WebView 会话渲染重构；消息操作条（复制/重新生成）；流式渐进渲染；WorkspaceStore 拆分；会话内搜索。以上在对话区优化研究报告中另行排期。
