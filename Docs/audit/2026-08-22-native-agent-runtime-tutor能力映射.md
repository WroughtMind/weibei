# Native 第一棒 · Tutor 能力映射

计划引用 `Docs/research/tutor-mode-product-plan-2026-08-14.md` §13/§17。开工时该路径**不在当前 origin/main 树里**（`Docs/research/` 目录不存在）。本表按意图交接、实验计划 v3.2.1、`CONTEXT.md` 与现有 12 工具回填。若该研究稿稍后入库，只做对照补行，不改已钉死的原生路径。

北极星（意图交接 §二）：这是 **agent 设计哲学**，不是 tutor 专属指标。Tutor 长在同一 runtime 上，不另起一套。

| Tutor 需要的能力 | 现状（Pi + Swift） | Native 路径 | 棒次 |
|---|---|---|---|
| 普通问答 / 人设 | Pi 循环 + `system.md` | 同一 `system.md` 经 prompt 组装器注入 | 1 |
| 课程地图 / 搜索 / 正文 | 4 host tool | 同一 `StudyAgentHostToolHandler` / `executeAgentHostTool` | 1 |
| 引用与跳转 | Swift 校验 jumpReference / 来源标签 | 复用现校验，不平行实现 | 1 |
| 学习记忆读写 | TS 读快照 + `applyLearningUpdate` 提案 | live `learningMemoryEntries` + 同一 apply | 1 |
| 课程知识档案 | TS + `applyCourseProfileUpdate` | live profile + 同一 apply | 1 |
| 笔记 / 关系建议 | TS 提案，用户确认后写 | 同结构提案；确认流不变 | 1 |
| 可视化学习辅助 | visualize Skill + `weibei_visualize` | 第一棒契约等价；第三棒迁技能包 | 1 / 3 |
| 图片材料 | `weibei_visual_asset` | live asset，不暴露路径 | 1 |
| 中途停止 | `StudyAgentRuntime.cancel` | 循环取消 + 账本配平 | 1 |
| 错误分类 | `AgentFailureKind` 7 类 | Native 错误映射同一枚举 | 1 |
| 续聊 | Pi 私有会话目录 | 自持 JSONL 账本回放 | 1 |
| ChatGPT 订阅登录 | Pi OAuth | 第二棒 `NativeAgentOAuth` | 2 |
| 多协议（Claude/Gemini/…） | Pi 适配 | 第二棒四族；Pi 能跑通的订阅就跟 | 2 |
| 技能渐进披露 | 仅 visualize stub | 第三棒技能包；Assistant 模式可用 | 3 |
| 费曼 / 苏格拉底等教法 | 无 | 第三棒新增教学技能（用户审定） | 3 |
| 整理成讲义（文稿） | 无 | `create_document`；Assistant 默认关 | 3 |
| 出题分工（子智能体） | 无 | `delegate`；深度常量；Assistant 默认关 | 3 |
| 无限制后台自主循环 | 明确不做 | 不做 | — |

不建设无边际通用平台。Tutor 需要的新能力 = 往 ToolRegistry 加条目，引擎不动。
