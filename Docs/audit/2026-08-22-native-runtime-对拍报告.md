# NativeStudyAgentRuntime 对拍报告

日期：2026-08-22  
分支：`codex/native-agent-runtime`  
草稿 MR：https://github.com/weibei-app/weibei/pull/285  
默认后端：`pi`（本实验不改默认）

## 1. 基准与环境

- 仓库：`~/projects/魏碑`，实验分支已 merge 当时的 `origin/main`。
- Pi：0.82.1，本地缓存约 72 MB。
- Native：`WEIBEI_AGENT_BACKEND=native` 开关；UI 未改。
- 质量测评模型（用户确认）：**ChatGPT 订阅 `gpt-5.6-luna` + `reasoning.effort=low`**。
- 命令：

```
swift build
.build/debug/WeiBeiSelfCheck
.build/debug/WeiBeiPiCheck --native-engine-smoke
.build/debug/WeiBeiPiCheck --native-capability-demo
.build/debug/WeiBeiPiCheck --native-eval
.build/debug/WeiBeiPiCheck --native-live available
```

本机无 Xcode，`swift test` 交 CI。`script/build_and_run.sh check` 因同一原因卡在 `swift test`，未伪造通过。

## 2. 能力矩阵（40 入口）

见 `Docs/audit/2026-08-22-native-agent-runtime-能力矩阵.md`。

- 覆盖：四族协议（Chat Completions / Responses / Anthropic Messages / Gemini）。
- 未覆盖：Azure Responses、Vertex、Bedrock、Cloudflare 两个占位 URL。
- 订阅：ChatGPT 六步已真验后退出。Anthropic / Copilot / Radius 按用户指示不真验，跟 Pi OAuth 同模式理论可接。

## 3. 行为差分（12 场景）

Pi 基线：`Docs/audit/2026-08-22-native-agent-runtime-Pi行为夹具/`。  
Native 侧本轮用脚本夹具 + DeepSeek/ChatGPT 真闭环，**不是**同一 ChatGPT 会话上 pi/native 逐题对打（质量测评账号已按六步退出）。

| 场景 | Pi 夹具 | Native | 高危差异 |
|---|---|---|---|
| 1 普通问答 | 01 答 4 | `--native-engine-smoke` / DeepSeek / ChatGPT 均非空 | 无 |
| 2 课程搜索后回答 | 02 调了 search/read/map；宿主目录报错 | 脚本与 ChatGPT/DeepSeek live 均调用 `weibei_course_search` 后作答 | Pi 夹具有宿主目录错误，属基线环境，不记 native 回退 |
| 3 课程正文 | 03 同样宿主错误 | 脚本 search-then-answer 含来源 | 未做 live 正文对打 |
| 4 记忆读取 | 04 调 `weibei_learning_memory` | 工具已回迁；无 live 对打 | 未对打 |
| 5 课程档案建议 | 05 调 profile_update | 工具已回迁；提案不落库 | 未对打 |
| 6 笔记/关系建议 | 夹具有 | 工具已回迁；提案不落库 | 未对打 |
| 7 可视化结构 | 夹具有 | `weibei_visualize` 仍在；技能包迁移后行为等价 | 不评生成质量 |
| 8 图片输入 | 夹具有 | `weibei_visual_asset` 在 | 未 live 对打 |
| 9 中途取消 | 09 | 脚本 / ChatGPT / DeepSeek live 均 `cancelled` | 无 |
| 10 错误分类 | 10 unauthorized | Native `AgentFailureKind` 映射自测通过 | 结构一致 |
| 11 续聊 | 11/12 | JSONL 账本回放自测通过 | 未 live 对打 |
| 12 多工具 | 13 | 循环支持多 step | 未 live 对打 |

结论：已 live 的问答 / 课程搜索 / 取消无高危回退。其余场景有工具与自测，缺同一模型双后端 live 账本 diff。

## 4. 评测集质量

- 草案 42 题：`Docs/audit/2026-08-22-native-agent-runtime-评测集草案.md` 与 `.json`。
- 配置：**模型 `gpt-5.6-luna`，effort `low`**。命令 `WeiBeiPiCheck --native-eval`。
- 本机 native OAuth 为 **signed-out**（第二棒六步要求退出无残留）。质量双评 **未跑**，不编造分数。
- 独立 judge（Kimi）因此无双侧原文可评。
- 重新登录后执行：`./.build/debug/WeiBeiPiCheck --native-eval`。

## 5. 性能

未做 5 次中位 TTFT/内存实测。预期 native 少一个 Pi 进程；本报告不填假数。

## 6. 体积

未改发布脚本，未出「删 Pi」候选包。Pi 二进制约 72 MB 仍在。未压缩 `.app` ≤ 55 MB 的 go 门槛 **未测**。

## 7. ChatGPT OAuth 六步

通过：登录 → 发消息（答 4）→ `weibei_course_search` → 中途取消 → 强制刷新 → 退出。`.bak` 残留已修。现为 signed-out。

## 8. 能力面三件套

命令：`WeiBeiPiCheck --native-capability-demo`

| 项 | 结果 |
|---|---|
| 技能目录 | `visualize` + `socratic-questioning` |
| 加载后目录 | 不变（纯指令注入） |
| 加载后风格 | 「只问一个问题：利息和利率差在哪？」 |
| create_document | 写出 `利率笔记.md` + CSP `script-src 'none'` 查看页 |
| delegate | 一轮完整分工，失败走值 |
| Assistant 默认 | `create_document` / `delegate` 隐藏 |

## 9. 已知差异与风险

- 质量双评与 12 场景全量 live 对拍缺 ChatGPT 登录。
- Azure / Vertex / Bedrock / Cloudflare 未覆盖。
- Mistral 走官方 `/v1` 兼容，不是 Pi 的 Conversations API。
- `#296` 占用 `WorkspaceStore.swift`；第三棒未再改该文件。
- 本分支不删 Pi、不改发布脚本、不打标签。

## 10. go / no-go

**条件 go，不能按 §5.5 全绿放行。**

已满足：OAuth 六步、三件套演示、默认 pi 不改、DeepSeek/ChatGPT 三闭环、40 入口路由、CI 快速检查（测试修复后）。

未满足：评测集 luna+low 双评分数、12 场景同一模型账本 diff、体积 ≤55 MB、性能表。

建议：保持草稿；重新登录 ChatGPT 后跑 `--native-eval`（luna + low），再补体积测量。删除 Pi 仍需单独授权。
