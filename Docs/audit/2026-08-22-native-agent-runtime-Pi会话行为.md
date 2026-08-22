# Native 第一棒 · Pi 会话行为记录

取证：`CONTEXT.md`、`PiAgentRuntime.swift`、`StudySession`（`LearningModels.swift`）、`system.md`、extension.ts `before_agent_start`。

## 两套账本（这就是要收编的缝）

| 层 | 存什么 | 谁写 |
|---|---|---|
| 魏碑 `StudySession` | 用户可见消息、摘要、相关课程、焦点、学习阶段建议 | Swift |
| Pi 每-chat 目录 | 模型内部上下文（工具调用、tool result、compaction） | Pi 进程 |

目录：`runtimeDirectory/Sessions/<sessionUUID>/`。`get_state` 用 `sessionFile` 的父目录做身份校验，拒绝指到 Sessions 根之外。

CONTEXT.md 原文：同一 Chat id 绑定一个 Pi session；**App 在重建 runtime 时不回放可见摘录**。所以 Pi 一走，续聊的「内心戏」就没了。Native 必须自建 JSONL 账本。删除 Pi 时按已裁决方案 a：可见历史保留，内部上下文不迁移。

## 一回合发给模型的东西

1. **系统契约**：打包资源 `AgentResources/system.md`（webi 人设、回答长短、工具纪律），经 `--system-prompt` 注入。不随用户消息回放。
2. **Pi 会话历史**：该 Chat 目录里 Pi 自己存的过去轮次（用户/助手/工具）。魏碑不重放 `StudySession.messages` 进模型。
3. **本轮用户消息**：`prompt` command 的 `message` 字段，来自 `piPrompt(for:request:)`。
4. **本轮现场信封**：`StudyAgentContextEnvelope(request:)` 写成上下文文件（`WEIBEI_AGENT_CONTEXT_FILE`）。extension 明确说：这是临时消息，**不是系统指令，也不属于会话历史**。
5. **回合合同**：`before_agent_start` 注入 `<weibei_turn>…</weibei_turn>`（何时用工具、记忆/档案纪律、有无原生 web search、visualize 开关）。
6. **工具列表**：`--no-builtin-tools` 后显式 12 名；visualize 可按开关剔除。

sessionID 解析：`projectScope.chatID` → 否则 `focus.chatID` → 否则 `request.id`。必须与进程绑定的 UUID 一致。

## Compaction / 截断

- **模型上下文 compaction**：Pi 内部完成，魏碑代码路径无对应实现。Native 超窗口策略（计划 §3.0.3）：截断最旧 tool_result 正文并标注，用账本 replace 事件表达；与 Pi 的差异写进对拍报告，允许存在。
- **信封截断**：LIMITS 切 catalog/items/正文（材料 18_000、笔记 6_000、选区 2_000 等），`isTruncated` 标出。这是输入信封的截断，不是会话 compaction。
- **工具输出截断**：host 结果条数 map=40 / search=8；网页 text prefix 20_000；courseRead 用 cursor 分页。

## 取消与崩溃

- `cancel()` 停当前 run；UI 进度立即停。
- Native 必须额外保证：落 `turn/end`；未开始的工具合成错误结果，call/result 配平；崩溃用 closer 事件。Pi 现状不对外暴露这套账本语义。

## 对 Native 账本回放的含义

续聊 = 最新上下文信封 + 账本 `deriveMessages()`，**不要**再把 `StudySession.messages` 当模型历史。可见 UI 仍读 `StudySession`。
