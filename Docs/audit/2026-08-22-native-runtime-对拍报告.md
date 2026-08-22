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
.build/debug/WeiBeiPiCheck --native-eval --backend pi
.build/debug/WeiBeiPiCheck --native-eval --ids 16,08,10,11
.build/debug/WeiBeiPiCheck --native-live available
.build/debug/WeiBeiPiCheck --native-perf
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
| 10 错误分类 | Pi 夹具把坏 key 标 generic | `unauthorized`（`WeiBei.NativeAgent` 401 +「认证已失效」） | 无高危；native 已对齐枚举，Pi 夹具仍偏 generic |
| 11–12 续聊 | 有 | 同账本 11 search → 12 纯文本 | 无 |
| 13 多工具 | 有 | search + read 同轮 | 无 |

luna+low live 评测里，课程搜索/正文/记忆/档案/笔记题也会调对应工具。Pi 已用同一套 42 题、同一 `gpt-5.6-luna` + `low` 跑完对照。

## 4. 评测集质量

- 42 题，模型 **`gpt-5.6-luna` + `low`**。
- Native：`WeiBeiPiCheck --native-eval` → live-ran=40。
- Pi：`WeiBeiPiCheck --native-eval --backend pi` → live-ran=40。
- **完整答卷**在 `Docs/audit/2026-08-22-eval-luna-low/{native,pi}/`（每题一份 `.md` + `answers.jsonl`）。早期 `*-eval-luna-low.log` 只有前 80 字，不能当全文。cancel/error 两题两边都跳过。
- 闭式题两边 prefix 一致：`01→4`，`02→1/4`，`19→180`，`20→1191`，`23→10`，`33→1月1日`，`34→-3`，`35→利率升债券跌`，`39→12.68%`，`40→中位数是正中间`。
- 课程工具：native 能 search/read 到夹具正文；Pi 多次报「宿主工具响应根目录发生了变化」（与第一棒 Pi 夹具同类），因此 04–06 等题 Pi 更常拒答。这是 CLI 宿主差异，不是 luna 答错。
- 独立 judge：`Docs/audit/2026-08-22-eval-luna-low/独立judge评分报告.md`（Kimi，未参与实现）。40 题双评：

| 侧 | 正确性 | 流畅度 | 长度 | 折算 5 分制 |
|---|---|---|---|---|
| native | 4.95 | 5.00 | 4.98 | **4.98** |
| pi | 4.88 | 5.00 | 5.00 | **4.96** |

均分差 0.02，低于 0.3 门槛；无单题回退 ≥2。Judge 结论：内容质量无实质差别，Pi 少的 2 分来自 CLI 宿主拒答。

收尾重跑（native / luna+low，`--ids`，完整答卷覆盖原 `.md` / jsonl 对应行）：

- **16**：工具描述已加课程优先引导；评测预期改为「优先课程 search→read，课程无材料时允许说明后转网页」。重跑未调课程工具，也未转网页，改成追问「查哪种利率」。夹具里有《利率课程》，按方案不算自动失败，交 judge 复核。
- **08**：`load_skill` 已幂等。重跑工具序列只有 `weibei_learning_memory`，不再连发两次 `load_skill`；仍如实说没有记忆。
- **10 / 11**：见第 9 节。Kimi 原双评均分不因这 4 题重跑改写。

## 5. 性能

luna 评测（40 题含工具）墙钟：native ≈ 6.3 min，Pi ≈ 6.4 min，模型占主导，不能当短问答 TTFT。未再拿 luna 做 5 次中位，以免抢订阅配额。

短问答对拍（DeepSeek `deepseek-chat`，`2+2`，5 次中位，`WeiBeiPiCheck --native-perf`）：

| 指标 | native | Pi |
|---|---|---|
| 整轮墙钟中位 | **0.678 s**（0.528–1.069） | **1.615 s**（1.356–1.833） |
| 首字中位 | **0.526 s**（0.439–0.955） | **1.580 s**（1.322–1.800） |
| 峰值内存 | CLI `getrusage` **22.3 MiB**（工具调用后） | 子进程 `pi` **171 MiB RSS** + 两个 `bun` 约 **39 MiB** |

native 明显更快、更省内存；无 Pi/Bun 常驻子进程。这是 CLI 路径，不是完整 `.app` 冷启动。

## 6. 体积

未改发布脚本。用已有 Release 产物在临时目录按 `build_and_run.sh` 的打包清单组装测量用 `.app`（含 Sparkle、PDF helper、资源包、图标；一次含 Pi，一次不含）：

| 组装 | 未压缩体积 |
|---|---|
| 含 Pi 0.82.1 | **117.2 MiB**（`du` 116M） |
| 不含 Pi | **44.9 MiB**（`du` 44M） |

不含 Pi 低于 55 MB 门槛。这不是公证过的正式安装包，只是同清单本地组装。含 Pi 仍约 117 MB。

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

- 401：`WeiBei.NativeAgent` 的 401/「认证已失效」归到 unauthorized（自测覆盖；场景 10 现为 `unauthorized`）。
- Q10/Q11 定点重跑（luna low）：工具失败不再变成「内部错误」。Q10 先 `profile_update` 再 `course_map` 再重试，模型答「已提交知识档案更新建议」。Q11 复述真实原因「上下文版本不匹配」，不再说内部错误。
- 提案闭环：CLI live 没有真实笔记库 / WorkspaceStore，即便工具回执写「已提交」也不会落库。12 场景脚本只能验协议。**闭环方式 = 真实 App 冒烟**，四条提案清单见 `Docs/audit/2026-08-22-native-runtime-用户验收清单草稿.md`。
- Q16 引导后仍未走课程工具（改成澄清问），按方案交 judge 复核，不记自动失败。
- Azure / Vertex / Bedrock / Cloudflare 未覆盖。
- Pi 课程宿主在 CLI 里仍会报响应目录变化。
- 正式公证包未出；体积是临时目录按同一清单组装的测量值。
- 本分支不删 Pi、不改发布脚本、不打标签。

## 10. go / no-go

**质量 + 体积 + DeepSeek 性能：通过。整体仍是条件 go**（公证包、删 Pi、真实 App 提案四条未验收）。

已有：OAuth 六步、三件套、默认 pi、DeepSeek/ChatGPT 三闭环、12 场景 native 脚本（401 已对齐，本轮 `--native-scenario-pair` / `--native-capability-demo` 仍绿）、luna+low 40 题两侧 live 全文、Kimi 双评 native 4.98 / pi 4.96、16/08/10/11 收尾重跑、本地组装不含 Pi **44.9 MiB**、DeepSeek 短问答 native 墙钟 0.678 s / 首字 0.526 s、CLI 峰值 22.3 MiB、Pi 子进程约 171 MiB。

仍缺：公证安装包、luna 首字中位（刻意未测）、真实 App 提案四条冒烟。删除 Pi 需单独授权。保持草稿。
