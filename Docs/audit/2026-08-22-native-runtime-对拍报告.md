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

Pi 基线：`Docs/audit/2026-08-22-native-agent-runtime-Pi行为夹具/`（DeepSeek live）。  
Native 确定性夹具：`WeiBeiPiCheck --native-scenario-pair` → `Docs/audit/2026-08-22-native-runtime-12场景对拍.json`（13/13 通过）。

| 场景 | Pi 夹具工具 | Native 脚本工具 | 高危差异 |
|---|---|---|---|
| 1 普通问答 | 无 | 无，答 4 | 无 |
| 2 课程搜索 | search/read/map（宿主目录报错） | `weibei_course_search` | Pi 基线环境错误，不记 native 回退 |
| 3 课程正文 | read/map/search 报错 | `weibei_course_read` | 无（结构） |
| 4 记忆读取 | `weibei_learning_memory` | 同 | 无 |
| 5 课程档案 | `weibei_course_profile_update` | 同，提案不落库 | 无 |
| 6 笔记/关系 | 有 | `note_proposal` + `relation_proposal`，待确认 | 无 |
| 7 可视化 | 有 | `weibei_visualize` 合法 spec | 不评生成质量 |
| 8 图片输入 | 有 | `weibei_visual_asset` | 无 |
| 9 中途取消 | 有 | `cancelled` | 无 |
| 10 错误分类 | unauthorized | 401 映射为登录文案（classify 现为 generic，文案含「认证已失效」） | 文案对，枚举名未完全对齐 |
| 11–12 续聊 | 有 | 同账本 11 search → 12 纯文本 | 无 |
| 13 多工具 | 有 | search + read 同轮 | 无 |

luna+low live 评测里，课程搜索/正文/记忆/档案/笔记题也会调对应工具（见第 4 节日志）。未做 Pi 后端同一 `gpt-5.6-luna` 逐题对打。

## 4. 评测集质量

- 42 题，模型 **`gpt-5.6-luna` + `low`**。
- Native：`WeiBeiPiCheck --native-eval` → live-ran=40。
- Pi：`WeiBeiPiCheck --native-eval --backend pi` → live-ran=40。
- **完整答卷**在 `Docs/audit/2026-08-22-eval-luna-low/{native,pi}/`（每题一份 `.md` + `answers.jsonl`）。早期 `*-eval-luna-low.log` 只有前 80 字，不能当全文。cancel/error 两题两边都跳过。
- 闭式题两边 prefix 一致：`01→4`，`02→1/4`，`19→180`，`20→1191`，`23→10`，`33→1月1日`，`34→-3`，`35→利率升债券跌`，`39→12.68%`，`40→中位数是正中间`。
- 课程工具：native 能 search/read 到夹具正文；Pi 多次报「宿主工具响应根目录发生了变化」（与第一棒 Pi 夹具同类），因此 04–07、10–12、36 的课程引用 Pi 更常拒答。这是 CLI 宿主差异，不是 luna 答错。
- **没有编造 5 分制分数**。独立 judge（Kimi）仍未逐题打分。闭式题两边一致，开放题需人工/Kimi 再评。

## 5. 性能

未做 5 次中位 TTFT/内存。`--native-eval` 40 题墙钟约 6.2 分钟（含工具题），不能当 TTFT 中位。

## 6. 体积

未改发布脚本，未组正式 `.app`。本机 `swift build -c release --product WeiBei`：

| 件 | 大小 |
|---|---|
| Release `WeiBei` 二进制 | 30 MB |
| `WeiBei_WeiBei.bundle` | 7.8 MB |
| `WeiBei_WeiBeiCore.bundle` | 0.2 MB |
| Pi 0.82.1 运行时 | 72 MB |

不含 Pi 的二进制+资源约 **38 MB**，有望低于 55 MB 门槛，但完整 `.app`（Sparkle、图标、Helpers）未组装，**不能宣称已过门槛**。含 Pi 仍约 +72 MB。

## 7. ChatGPT OAuth 六步

通过：登录 → 发消息（答 4）→ `weibei_course_search` → 中途取消 → 强制刷新 → 退出（含 `.bak` 擦除）。质量测评时再次登录，现为 signed-in。

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

- 401 用户文案正确，但 `AgentFailureKind.classify` 对「认证已失效」仍可能落到 generic。
- Azure / Vertex / Bedrock / Cloudflare 未覆盖。
- 无独立 judge 5 分制双评均分。Pi 课程宿主在 CLI 里仍会报响应目录变化。
- 完整 `.app` 体积未组装测量。
- 本分支不删 Pi、不改发布脚本、不打标签。

## 10. go / no-go

**仍是条件 go。**

已有：OAuth 六步、三件套、默认 pi、DeepSeek/ChatGPT 三闭环、12 场景 native 脚本、**luna+low 40 题 Pi 与 native 都 live 跑完**、闭式题两边一致、Release 二进制+资源约 38 MB（不含 Pi）。

仍缺：Kimi 5 分制双评、未压缩 `.app` 实装、性能中位。删除 Pi 需单独授权。保持草稿。
