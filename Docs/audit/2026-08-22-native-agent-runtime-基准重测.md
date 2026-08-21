# NativeStudyAgentRuntime 开工基准重测

- 日期：2026-08-22
- 仓库：`~/projects/魏碑`
- 对照计划：`Docs/plans/2026-08-22-native-agent-runtime-实验计划.md` v3.2.1 §2
- 计划写的 origin/main：`7bc1c08`
- 开工实测 origin/main：`c7018f0`（Merge pull request #281 from weibei-app/codex/filemodel-phase1-write-gate）
- 本任务分支：`codex/native-agent-runtime`（从 `origin/main` 新建，不带其他任务工作区改动）

`7bc1c08..c7018f0` 已合入 file-model 阶段 0/1、资料库位置、导入 UX、历史会话冷渲染等。共享核心文件 `WorkspaceStore.swift`、`WeiBeiSelfCheck/main.swift` 在这段里都有改动，行号必然漂移。下表按计划 §2.1 / §2.2 逐条重测。

## 2.1 魏碑侧

| 事实断言 | 计划记录 | 开工实测 | 差异 |
|---|---|---|---|
| Pi 版本与获取 | `Vendor/PiRuntime/manifest.json`：Pi 0.82.1，source commit `b4f2936`；`script/prepare_pi_runtime.sh` 构建期下载、SHA-256 校验、ad-hoc 签名 | 仍是 Pi 0.82.1，sourceCommit `b4f293684bba718d59cc1157679bcf6157b3a7f5`；脚本仍做 SHA-256、`codesign --sign -`、verify | 无实质差异 |
| Pi 二进制体积 | 约 72 MB | `.build/pi-runtime/0.82.1/darwin-arm64/PiRuntime/bin/pi` = **72 MB**（2026-08-21 缓存） | 与计划一致；Release `.app` 总包体积开工时未复测，第四棒体积对拍时实测 |
| Pi 启动参数 | `PiAgentRuntime.swift:1181-1183`：`--mode rpc` + `--no-builtin-tools` 等全关，再显式 `--extension` | `launchArguments` 现位于 **1180–1195**：`--mode rpc`、`--no-builtin-tools`、`--no-extensions` 后再挂 `extension.ts` + `management-extension.ts`，另有 `--no-skills` / `--no-prompt-templates` / `--no-themes` / `--no-context-files` / `--no-approve` | 行号几乎未漂；语义与计划一致 |
| 统一接口 | `StudyAgentRuntime.swift:937-941`：protocol 仅 3 方法 | **937–940**：`respond(to:progress:)` / `cancel()` / `reset()`；944 有无 progress 的便捷默认实现 | 无实质差异 |
| 后端枚举 | `WorkspaceModels.swift:1265`：`StudyAgentBackend { pi, openAI, offline }` | 现位于 **1353–1357**，仍是三 case | 行号 +88；本任务仍加 `native` |
| 后端切换点 | `WorkspaceStore.swift:637` 声明 `piRuntime`，`:937` 实例化 | 声明 **671**，实例化 **974** | 行号漂移（file-model / 库根等合入）；文件属共享核心面，且已被 PR #279 占用，见文末 |
| 12 个工具清单 | `extension.ts:15-40`：11 个 `weibei_*` + `read` | 仍在 15–40：`course_map/search/read`、`web_open`、`visual_asset`、`learning_memory/update`、`course_profile_update`、`note_proposal`、`relation_proposal`、`visualize`、`read` | 无差异 |
| 工具执行链路 | 4 个 host tool 已由 Swift 执行（`StudyAgentRuntime.swift:306-317` + `PiAgentRuntime.swift:291` + `:1442`）；其余 8 个在 extension.ts | Host 请求枚举仍在 **306–317**；`hostToolNames` 在 **291–296**；分发改为 **2257 / startHostToolCall:1451**（原 :1442 现为 `recordRejectedAction`） | 行号漂移；两类链路语义不变。extension.ts 现 **2810** 行（计划 2788） |
| 提案回传 | `StudyAgentRuntime.swift:726-767` 组装进 `StudyAgentReply` | `StudyAgentReply` 现 **726–767**，字段含 note/relation/learning/courseProfile 提案 | 无差异 |
| Provider 目录 | `WorkspaceModels.swift:514-643`：41 case = 4 订阅 OAuth + 35 API Key + 2 本地/自定义 | `AgentProviderID` 现 **573–618**：**40 个唯一 case**。`kind`：订阅 4（含 `radius`）+ apiKey 34 + localOrCustom 2。`radius` 写在 API-key 分区注释下，但 `kind` 归订阅 | **不是 41**。计划数字疑把 `radius` 既算订阅又算 API key。以 40 唯一 case 为准 |
| OAuth 现状 | `PiOAuthService.swift:144`：Pi 进程登录；凭证在 Pi auth.json | `runtime.login(...)` 现 **144**；文件 310 行 | 无实质差异 |
| Keychain | 全仓 `kSecClass/SecItemAdd` 零命中 | 仍零命中 | 无差异 |
| 会话连续性 | `StudySession`（`LearningModels.swift:243`）只存可见消息；Pi 每-chat 目录 `:925` | struct 仍在 **243**；Pi 会话目录工厂在 **930–937**（`Sessions/<uuid>/`）。`:925` 附近是 get_state 身份校验 | 行号小漂；语义不变 |
| 流式事件面 | `PiRPCMessageDecoder`；`StudyAgentProgress` `:769-776` | Decoder 仍被 `PiAgentSelfChecks` 使用；Progress 仍在 **769–776** | 无差异 |
| 错误分类 | `AgentFailureKind` `:782-935`：7 类 + 双语文案 | 仍在 **782**：offline / unauthorized / rateLimited / serverError / timedOut / cancelled / generic | 无实质差异 |
| 自测基建 | `PiAgentSelfChecks.swift`（1079 行） | 现 **1155** 行 | +76 行（main 前进） |
| 评测通道 | WeiBeiPiCheck（2641 行 CLI） | `WeiBeiPiCheckMain.swift` 仍 **2641** 行；同目录还有富回答证据链若干文件 | 主入口行数一致 |
| 技能现状 | `extension.ts:42-50` 仅 1 个 visualize Skill | 仍是唯一技能 `Visualize` 1.0.19 | 无差异 |
| 构建约束 | Package.swift：swift-tools 5.9，macOS 14，**零外部依赖**；WeiBeiCore 已链 Security.framework；JSC 可链 | tools 5.9 + macOS 14 仍在。WeiBeiCore **无 Swift 包依赖**，已链 Security。App 目标依赖 Sparkle 2.9.6。JSC **尚未**链接（第三棒才需要接缝） | “零外部依赖”只对 WeiBeiCore 成立；App 已有 Sparkle。不阻塞本实验 |
| CI | `pr-checks.yml`（fast-check + release-package）；`ci_changed_scopes.sh`：code / pi / editor / data_safety / release | 两 job 仍在；scope 现还输出 `rich_answer` / `tools` | 本任务改动会命中 code + pi；Package.swift 改动会命中 release |
| 体积基线 | App 约 113 MB（用户实测，须本地 Release 复测）；Pi 二进制约 72 MB | Pi 二进制 72 MB 已复测。未压缩 `.app` 开工未复测 | 第四棒补测 |
| 合规 / Tutor / 意图文档 / 仓库副本 | 三份审计稿、tutor 计划、意图交接、`~/Documents/魏碑` 只读副本 | 文档仍在；开发只在 `~/projects/魏碑` | 无差异 |

## 2.2 DSH/Cordis 侧

| 事实断言 | 计划记录 | 开工实测 | 差异 |
|---|---|---|---|
| checkout | `~/projects/dsh` @ `7b9644f2` | HEAD 仍是 `7b9644f2`（Private DSH final unwatermarked snapshot 20260812T172954Z） | 无 |
| Cordis 本体 | `vendor/cordis/src/` 9 文件 2693 行 | 9 文件、2693 行；events 352 / registry 337 / fiber 754 / reflect 418 均一致 | 无 |
| per-agent scope | `packages/core/scope` 561 行 | `packages/core/scope/src/*.ts` 合计 **561** 行（index 204 + store 267 + invariant 41 + generated 49） | 无。若把 tests/lib 算进去会膨胀到约 1491，计划口径是 src |

## 共享核心面占用（开工发现）

本任务计划占用：

- `Package.swift`（新增源文件 / target 资源）— **当前无其他活跃 PR 占用**
- `Sources/WeiBei/Stores/WorkspaceStore.swift`（后端开关 `WEIBEI_AGENT_BACKEND`）
- `Sources/WeiBeiSelfCheck/main.swift`（挂 `NativeAgentSelfChecks`）

释放条件：本草稿 MR 合并。

**冲突：** 草稿 PR #279（`codex/text-scaling`，界面文字大小五档）已声明占用：

- `Sources/WeiBei/Stores/WorkspaceStore.swift`（+33/−33：注释压缩 + `interfaceTextScale` 持久化）
- `Sources/WeiBeiSelfCheck/main.swift`（+14：`checkInterfaceTextScalePersistence`）
- 另占 `WeiBeiApp.swift`、`ContentView.swift`（本任务不需要这两份）

按 AGENTS.md：**发现占用即停止修改这两份文件**，等主会话协调。`Package.swift` 与 `Sources/WeiBeiCore/NativeAgentRuntime/` 新文件不在 #279 占用范围内。

另外：开工时本工作区停在 `codex/filemodel-phase2-backup-first`，有未提交的 `WorkspaceStore.swift` 等改动。已 stash 为 `WIP filemodel-phase2-backup-first (unrelated to native-agent-runtime)`，**没有带进本分支**。该本地 WIP 无开放 PR，不构成本任务对 #279 的替代占用声明。

## 本实验纪律备忘

- 全程一个草稿 MR，不滚动合并；不删 Pi、不改发布脚本、不打标签。
- 默认后端仍是 pi。
- 旧 56 题作废，不得使用。
- 用户介入时点：第二棒 ChatGPT 真账号登录；第三棒评测集与新技能审定；第四棒对拍报告拍板。
