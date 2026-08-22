# 魏碑 Agent（NativeStudyAgentRuntime）实验计划 v3.2

> 执行 Agent（Grok）零上下文起步，按本文档独立完成四棒与对拍评估。用户介入时点：
> 第二棒 ChatGPT 真账号登录、第三棒评测集与新技能审定、第四棒报告与最终合并拍板。
> 所有已确认决策见第 1 节，无需中途请示；遇到本文档未覆盖且影响范围的决策点，
> 在草稿 MR 描述中记录后按第 8 节"风险与止损"处理。
>
> 本计划按 AGENTS.md 默认口径随首个实现 MR 一并纳入 `main`。
> **配套意图文档**：`Docs/plans/2026-08-22-native-agent-runtime-意图交接.md`。
> 优先级：执行细节以本计划为准；意图判断以意图交接文档为准。
>
> v1 → v2：能力面（技能系统 / 文稿 artifact / 子智能体）升为一等公民；三棒改四棒。
> v2 → v3：完成对 DSH（DeepSeek Harness）与其底层 Cordis 框架的源码取证（本地 checkout
> `~/projects/dsh` @ `7b9644f2`，2026-08-12），架构从"自创"改为"有参照地剪裁"。
> v3 → v3.1（用户复审修订）：凭证不进钥匙串改存魏碑自持凭证文件；旧 56 题题库作废；
> 纳入能力层统一愿景与权限分层；8 个回迁工具升级为直读 live stores。
> v3.1 → v3.2（grilling 第一轮裁决固化）：① 订阅判定口径改为 **Pi 现状基线**
> （Pi 能实现 → 原生也要实现）；② 质量评测**不经真实 App**，走 CLI 通道，独立 judge
> 双评，不考 GenUI/可视化生成质量；③ Assistant 模式技能可用、文稿/子智能体默认关闭；
> ④ **全程草稿 MR，不滚动合并**，报告通过后用户最终拍板一次性合并；⑤ 旧会话处置
> 选定方案 a（可见历史保留、内部上下文不迁移）；⑥ 北极星定位修正：是用户的 agent
> 设计哲学，不是 tutor 专属指标。
> v3.2 → v3.2.1（grilling 第二轮裁决固化）：① 质量测试模型定为 ChatGPT 订阅的
> `gpt-5.6-luna` + low 推理档（模型存在性已经 OpenAI 官方模型页核实）；② 评测集素材
> 定为混合来源（模型生成 / 网络习题 / 真实学习场景疑问 / 闲聊 / 深聊请求）；
> ③ 质量 rubric 改为 **正确性 / 语言流畅度 / 回答长度合理性**——引用完整性与来源
> 可跳转属功能性指标，由 5.1 行为差分覆盖，不进质量分；④ 订阅口径确认：Pi 能跑通的
> 订阅（如 Claude）就跟其实现，本实验完成技术验证与实现方案。

---

## 1. 任务背景与已确认决策

魏碑当前安装包约 113 MB，其中约 72 MB 是内置的 Pi 0.82.1 standalone 二进制（Bun
`build --compile` 单文件，见第 2 节基准）。本任务用纯 Swift 实现魏碑自己的 Agent
（`NativeStudyAgentRuntime`），挂在现有 `StudyAgentRuntime` 协议后面，目标是在
**用户能力零损失**的前提下，最终删除 Pi/Bun 二进制，把 App 缩到 40–50 MB 量级；
同时把能力面（工具、技能、文稿产物、子智能体）建成魏碑自有的可生长体系。

已确认决策（用户拍板，不再讨论；grilling 第一轮裁决已并入）：

1. 自研 Agent 完整替代 Pi，**不做**"Pi 按需下载"过渡形态。
2. 能力面是一等公民：工具注册表、技能系统（progressive disclosure）、文稿 artifact、
   子智能体机制全部进本次设计范围。
3. ChatGPT 订阅登录（`openai-codex`）必须保留，且放在最前面验证（第二棒）。用户判断
   被拦可能性低（开源 agent 生态多有使用此订阅路径的先例），验证步骤照旧执行；若真
   被拦，按预裁决退路：API key 先行、订阅入口暂时隐藏等待官方路径，**不保留 Pi 混合形态**。
4. **本实验分支不删除 Pi**。Native 与 Pi 并存、可切换，默认仍走 Pi。是否删除 Pi/Bun
   是对拍报告出来之后的独立决策，需用户单独授权。
5. 不打标签、不发布版本、不出正式 DMG；只允许本地构建做测量。
6. 维护哲学：协议适配靠自己，缺什么接什么；社区有需求就社区 PR。不把厂商接口漂移
   当作决策阻力，只当作普通迭代。
7. 子智能体：机制进引擎（递归循环），递归深度常量能防失控即可，本轮不做精细预算体系。
8. 架构参照 DSH/Cordis 的机制纪律（第 3 节逐条取舍），**不引入其插件运行时**。
9. **凭证不进系统钥匙串**：API Key 与 OAuth token 存魏碑自持凭证文件（App 数据目录内，
   文件权限 0600），形态延续现状（Pi 的 auth.json 同样是明文文件），只是改由魏碑自己
   管理、带损坏恢复。
10. 愿景方向（见意图交接文档 §二）：能力层统一是用户的 **agent 设计哲学**（不是 tutor
    专属指标）——同一份能力定义未来派生 UI 命令、模型工具、测试入口；权限分层
    （读自动放行 / 写用户确认 / 破坏二次确认 / 硬护栏不可绕过）；暴露意图级能力。
    引擎与 ToolRegistry 按此方向设计（工具定义携带权限等级字段），本实验不追求三处
    派生全部落地。
11. **订阅入口判定以 Pi 现状为基线**：Pi 现在能跑通的订阅（登录 + 发消息），原生就要
    实现——哪怕没有官方第三方路径，移植其实现，厂商政策风险由用户知情承担；Pi 做不到
    的才不做。第二棒的"官方边界盘点"相应改为 **Pi 现状复现验证**。
12. 删除 Pi 时旧会话处置选定方案 a：可见聊天历史保留（魏碑自存），模型内部上下文
    不迁移，老对话续聊以新账本重新开始。
13. **质量评测不经真实 App**：由 CLI 通道驱动双后端（WeiBeiPiCheck 证据链扩展）；
    评分由独立 judge（非执行者，预定 Kimi）按 rubric 逐题双评，**用户可全量过目**；
    不考 GenUI/可视化生成质量（可视化仅保留行为对拍中的结构合法性检查）。
14. 对拍凭证与模型：DeepSeek API key（验证连通即可）；ChatGPT 订阅（质量测试主用，
    模型 `gpt-5.6-luna` + low 推理档——模型存在性已于 2026-08-22 经 OpenAI 官方模型页
    核实）。未实测的协议族在报告中如实标注。
15. Assistant（普通问答）模式可见性：**技能立即可用**；`create_document` 与 `delegate`
    引擎具备但默认不对 Assistant 模式开放（按模式裁剪注册，作用域层叠天然支持），
    用开关演示其可用性。
16. **全程草稿 MR，不滚动合并**：四棒在同一草稿 MR 上累积推进，每棒更新 MR 描述；
    第四棒报告通过、用户拍板后才转正式合并。

非目标：

- 不建设无边际通用平台；能力面围绕魏碑产品生长。
- 不迁移旧 Pi 会话的内部上下文（决策 12）；迁移方案作为报告附录评估。
- 不动 UI（仅加后端开关与模式裁剪）；不重写魏碑已有产品逻辑（上下文组装、校验、
  建议确认、可视化、错误分类均在 Swift 侧，原样复用）。

## 2. 基准核查记录

**执行 Agent 开工时若 origin/main 已前进，必须重测本节全部行号与数量，差异写进 MR 描述。**

### 2.1 魏碑侧（2026-08-22 实测，仓库 `~/projects/魏碑`，origin/main = `7bc1c08`）

| 事实断言 | 核查结果 |
|---|---|
| Pi 版本与获取 | `Vendor/PiRuntime/manifest.json`：Pi 0.82.1，source commit `b4f2936`；`script/prepare_pi_runtime.sh` 构建期下载、SHA-256 校验、ad-hoc 签名 |
| Pi 二进制体积 | 约 72 MB（`Docs/audit/2026-07-31-Node形态Pi运行时可行性.md` 实测记录）；Node 形态 node_modules 约 172 MB，已被否决 |
| Pi 启动参数 | `Sources/WeiBeiCore/PiAgentRuntime.swift:1181-1183`：`--mode rpc` + `--no-builtin-tools` 等全关，再显式 `--extension extension.ts` + `management-extension.ts`。通用编程能力已不在魏碑中运行 |
| 统一接口（替换接缝） | `Sources/WeiBeiCore/StudyAgentRuntime.swift:937-941`：`protocol StudyAgentRuntime { respond(to:progress:) / cancel() / reset() }`，仅 3 个方法 |
| 后端枚举 | `Sources/WeiBeiCore/WorkspaceModels.swift:1265`：`StudyAgentBackend { pi, openAI, offline }`；本任务加 `native` case |
| 后端切换点 | `Sources/WeiBei/Stores/WorkspaceStore.swift:637` 声明 `piRuntime`，`:937` 实例化。**该文件属共享核心面** |
| 12 个工具清单 | `Sources/WeiBeiCore/AgentResources/extension.ts:15-40`：11 个 `weibei_*` + `read`（read 仅限内置 visualize Skill 文件） |
| 工具执行链路（两类，关键） | ① 4 个取数工具（courseMap/courseSearch/courseRead/webOpen）是 **host tool**，已由 Swift 执行（`StudyAgentRuntime.swift:306-317` + `PiAgentRuntime.swift:291` + `:1442`）。② 其余 8 个在 extension.ts（2788 行 TS）内执行，靠上下文文件与响应目录传数据。**Native 化 = 8 个 TS 工具用 Swift 重实现，行为等价**；并按意图交接文档从"读提问前快照"升级为直读 live stores（提案仍须用户确认才落库） |
| 提案回传 | noteProposal / relationProposal / learningUpdate / courseProfileUpdate 经工具响应目录回传，组装进 `StudyAgentReply`（StudyAgentRuntime.swift:726-767） |
| Provider 目录 | `Sources/WeiBeiCore/WorkspaceModels.swift:514-643`：`AgentProviderID` 共 41 case = 4 订阅 OAuth + 35 API Key + 2 本地/自定义；raw value 与 Pi provider id 对齐 |
| OAuth 现状 | `Sources/WeiBei/Support/PiOAuthService.swift:144`：由 **Pi 进程**执行登录流程；凭证由 Pi 的 auth.json 文件体系保管（明文 JSON，App 数据目录）。**Swift 侧目前没有任何 Keychain 代码**（全仓 grep `kSecClass/SecItemAdd` 零命中） |
| 会话连续性 | `StudySession`（Sources/WeiBeiCore/LearningModels.swift:243`）只存用户可见消息；模型内部上下文在 Pi 每-chat 会话目录（`PiAgentRuntime.swift:925`）。**Native 化必须自建会话账本**；删除 Pi 时旧会话内部上下文不迁移（决策 12） |
| 流式事件面 | `PiRPCMessageDecoder`（JSONL 帧，UTF-8 跨包安全）；进度面 `StudyAgentProgress`（StudyAgentRuntime.swift:769-776） |
| 错误分类 | `AgentFailureKind`（StudyAgentRuntime.swift:782-935）：7 类 + 双语文案。Native 错误必须映射到同一枚举 |
| 自测基建 | `Sources/WeiBeiSelfCheck/PiAgentSelfChecks.swift`（1079 行）。新增 `NativeAgentSelfChecks.swift` 与之并列 |
| 评测通道 | **WeiBeiPiCheck（2641 行 CLI，链接 WeiBeiCore，不开真实 App 即可驱动 agent 与证据链）**——质量评测经它扩展为双后端驱动；旧 56 题题库（`Docs/富回答56题真实窗口逐题复核.json`）**已作废不得使用**（用户 2026-08-22 指示） |
| 技能现状（stub） | `extension.ts:42-50` 仅 1 个 visualize Skill，经受限 `read` 读 md 注入。无发现机制、无多技能 |
| 富内容渲染管线 | `weibei_visualize` 产出 spec 由魏碑 WKWebView + 自带运行时渲染；渲染从来不在 Pi 侧 |
| 构建约束 | `Package.swift`：swift-tools 5.9，macOS 14，**零外部依赖**；WeiBeiCore 已链接 Security.framework；macOS 系统自带 JavaScriptCore.framework 可直接链接 |
| CI | `.github/workflows/pr-checks.yml`（fast-check + release-package）；`script/ci_changed_scopes.sh` scope：code / pi / editor / data_safety / release |
| 体积基线 | App 约 113 MB（用户实测，**执行者须以本地 Release 构建复测**）；Pi 二进制约 72 MB |
| 合规背景 | `Docs/audit/2026-07-31-Pi-Bun再分发结论修订.md`：Bun 静态链 LGPL 叙事缺口，原生化一并关闭 |
| Tutor 需求背景 | `Docs/research/tutor-mode-product-plan-2026-08-14.md` §13/§17：复用同一 runtime，不新增第二套；明确不做无限制自主后台循环 |
| 意图文档 | `Docs/plans/2026-08-22-native-agent-runtime-意图交接.md`：能力层统一设计哲学、权限分层、明确不要清单；意图冲突时以它为准 |
| 仓库副本 | 规范开发仓库 `~/projects/魏碑`（origin/main=7bc1c08）。`~/Documents/魏碑` 是 .git 改名后的只读副本，禁止在其中开发 |

### 2.2 DSH/Cordis 侧（2026-08-22 取证，仓库 `~/projects/dsh` @ `7b9644f2`）

| 事实断言 | 核查结果 |
|---|---|
| Cordis 本体规模 | `vendor/cordis/src/` 共 9 文件 2693 行（events 352 / registry 337 / fiber 754 / reflect 418 等）；DSH 的 per-agent scope 原语 `packages/core/scope` 另计 561 行 |
| Cordis 核心机制 | Context=Proxy+原型链；inject 声明式依赖驱动加载顺序与替换级联；一切注册是 effect 且返回 disposer（卸载逆序执行）；事件五种分发（emit/bail/serial/parallel/waterfall），分发模式写进事件契约；waterfall=环绕中间件（不调 next() 即否决） |
| DSH 架构总纲 | `docs/architecture.md`：一切都是插件（含模型适配器、工具注册表、会话日志、Agent 循环本身）；能力缝三角色 Service Definition / Provider / Consumer；会话日志是唯一事实来源 |
| Agent 循环与会话 | `packages/core/session`（1157 行主文件）append-only SessionEvent 日志；`core/agent-loop` 相位机（idle/maintenance/running）；`deriveMessages()` 从日志投影模型历史；surface replace 事件支撑 compaction（不改历史）；"model-visible ⟺ logged"有运行时不变量插件在 `llm/stream` 边界断言；取消时未开始工具合成错误结果事件保证 call/result 配平；崩溃恢复用合成 closer 事件；fork=已完成轮次前缀快照 |
| 工具系统 | `packages/core/tools`（1946 行）：ScopedLayers（global/preset/agent，遮蔽+restriction 交集）；执行管线 = pre-execute waterfall（allow/deny/ask，ask fail-closed）→ deny-only 单调 guard → execute waterfall → body → 输出校验 → post-execute waterfall（accept/block 回灌纠错）→ finalizeContent 恰一次 → result 事件；`deferContext` 让工具把后续上下文挂在自己结果上 |
| 提示词组装 | `core/system-prompt`（516 行）：section/context/tools/variable 四个注册口 + order 排序 + assemble waterfall；工具 schema 由注册表以回调推给组装器 |
| 子智能体 | `packages/subagent`：窄接口 Provider（仅 `start()` 必选）+ 能力声明 OptionSet 前置校验 + 失败走值不走异常（stopReason）+ 部分输出必回传父级 + fork 种子=已完成轮次前缀 + 子作用域创建窗口内完成权限收窄（persona 遮蔽、toolFilter、approval 钉死 never）+ delegationDepth 持久化 |
| 技能系统 | `packages/skill`：目录摘要（name+description）注入上下文，正文由 `skill` 工具按需现读；**加载不改变任何注册状态**（不注册新工具、不改 system prompt）；目录变更用摘要比对 + 完整替换语义；modelInvocable/userInvocable 双通道；`/name` 用户手势注入 |
| LLM 抽象 | `packages/llm`：StreamChunk 封闭联合（block-start/text-delta/reasoning-delta/tool-call-delta/**block-end 携带组装完整块**/usage/finish）；tool-call 参数端到端 raw JSON 字符串；双错误路径（抛出/带内）归一为终结 error finish；provider 中立稳定错误码 + Retry-After；一次调用=一次尝试，重试决策在 loop 的 step 失败处而非流中间件；流空闲看门狗；replayState 机制（Anthropic thinking 签名）；EMPTY_RESPONSE 按可重试错误处理；max-tokens 截断丢弃半截 tool-call |
| 新增 provider 成本 | DSH 参考实现（llm-deepseek）约 600–900 行 TS，分四文件：wire 类型/请求序列化/流翻译/适配器类 |

## 3. 总体设计

### 3.0 核心设计决策（一切由此生长）

1. **一切都是工具**。Tool = 名称 + JSON Schema + 执行闭包 + **权限等级**。内置工具、
   会话动态工具（子智能体）、（后续）技能附带工具，全部进同一张显式注册表
   （`ToolRegistry`）。能力生长 = 往注册表加条目，永远不动引擎。
2. **循环是小而笨的状态机**。流式收事件 → 组装完整 tool call（参数 JSON 不完整
   禁止执行）→ 权限校验 → 执行 → 结果落账 → 继续请求；直到模型不再调工具或命中
   停止条件。停止条件（最大轮数、递归深度等）是配置常量，不做精细预算体系。
3. **会话账本是唯一的模型上下文真相**。每 chat 一个魏碑自持 JSONL 账本，完整记录
   user / assistant(text+tool calls) / tool_result 轮次；续聊 = 最新上下文信封 +
   账本回放；子智能体 = 新账本 + 工具子集，天然成立。超上下文窗口的最小策略：
   截断最旧 tool_result 正文并标注；与 Pi 的策略差异写进对拍报告。
4. **能力即数据，权限分层**（用户的 agent 设计哲学，意图交接文档 §二）。工具定义
   自带权限等级：读类自动放行 / 写类走用户确认 / 破坏类二次确认 / 硬护栏（课程、
   Chat、记忆隔离、目录越界）由 deny-only guard 承载、永远不可绕过。同一份能力定义
   未来派生 UI 命令与测试入口；本实验只要求权限等级字段进工具定义、确认流程走通
   现状等价行为、**12 个工具的实现复用与 UI 相同的 store 能力方法，不写平行实现**
   （可被代码审查核查）。

### 3.1 借鉴 DSH/Cordis 的机制（逐条取证取舍）

以下机制全部与 JS 运行时无关，用 Swift 协议/枚举/注册表/actor 即可干净复刻：

| # | 机制（DSH 出处） | 魏碑形态 |
|---|---|---|
| 1 | 三层事件域：durable 会话事件（post-commit 广播，监听器故障隔离）/ live waterfall 拦截点 / 轻量 emit 通知 | `AsyncStream` 分发账本事件；拦截点用显式中间件协议数组；UI 通知走 Observation/闭包 |
| 2 | 注册即返 disposer，卸载逆序执行（cordis effect 纪律） | `Registration` 结构体内含幂等 disposer 闭包；会话/agent 持 `DisposableStore`（约 80 行） |
| 3 | 能力缝三角色齐备：协议（Service Definition）/ Provider / Consumer（工具） | Swift protocol + 实现 + 工具消费者；新增能力必须三角色齐（如 `CourseSearchProviding` 协议 → 本地索引 provider → course_search 工具） |
| 4 | waterfall 拦截点：`agent/pre-step`（改写/拒绝对模型可见内容）、`agent/request-error`（重试决策点）、`llm/stream`（包流） | 中间件协议：`func decide(_ payload:, next:) async throws -> Decision`；`request-error` 是**不可省**的错误恢复决策点 |
| 5 | 工具执行管线：pre-execute（allow/deny/ask，**ask fail-closed**）→ deny-only 单调 guard → execute 包装 → 输出校验 → post-execute（accept/block 回灌纠错）→ finalize 恰一次 | **工具的权限等级驱动 pre-execute 默认策略**（读自动放行/写确认/破坏二次确认）；硬约束（课程/Chat/记忆隔离、目录越界）放 deny-only guard；纠错回灌走 post-execute |
| 6 | "model-visible ⟺ logged" 运行时不变量，在流边界断言请求消息 == 账本投影 | Debug/Test 构建挂不变量检查器：每步断言发出请求与账本 `deriveMessages()` 一致；**这是防引擎漂移的最便宜手段** |
| 7 | 账本投影与 surface replace：compaction/编辑不改历史，只追加 replace 事件；UI 时间线与模型上下文是同一日志的两个投影 | `SurfaceManager` struct + `deriveMessages()` 增量缓存；魏碑的超限截断策略也用 replace 事件表达 |
| 8 | 取消与崩溃配平：取消必落 `turn/end`；未开始工具合成错误结果事件；崩溃恢复用纯函数合成 closer 事件；fork = 已完成轮次前缀快照 | 全部照搬语义，用 Swift 结构化并发（`Task.checkCancellation`）表达；合成事件时间戳复用最后真实事件保证确定性 |
| 9 | StreamChunk 词汇表：封闭联合 + index 关联交错块 + **block-end 携带组装完整块** + usage 先于 finish + tool-call 参数端到端 raw JSON + max-tokens 截断丢弃半截 tool-call + EMPTY_RESPONSE 视为可重试错误 | 译为带关联值的 `enum StreamChunk: Codable, Sendable` + 共享 `BlockAssembler`；finish/usage 缓冲到流终止哨兵再 flush |
| 10 | 双错误路径归一（抛出/带内 → 终结 error 事件）+ provider 中立稳定错误码 + Retry-After 透传 | `LLMFailure: Codable`（code/status/retryAfterMs/requestId），再映射到魏碑 `AgentFailureKind` |
| 11 | 一次调用 = 一次尝试；重试策略注册时捕获为不可变值；重试决策在 step 失败处，不在流中间件 | 策略 `enum`（normal/always）按 provider 存注册表；重试计数从账本事件推导（崩溃后仍在） |
| 12 | 流空闲看门狗：只在挂起时计时；看门狗超时映射 timeout，外部取消仍映射 cancelled | `AsyncSequence` 迭代与 `Task.sleep` 竞速（约 40 行） |
| 13 | 技能 progressive disclosure：目录摘要（name+description）注入，正文按需现读；**加载不改变任何注册状态**；目录变更摘要比对 + 完整替换；modelInvocable/userInvocable 双通道 | 技能包**格式**预留附带工具声明（`tools/*.schema.json`），但 v1 加载只做纯指令注入、不注册附带工具（格式先行，机制后补）；目录注入与双通道照搬；`/技能名` 用户手势后补 |
| 14 | 子智能体窄接口：仅 `start()` 必选；能力声明 OptionSet 前置校验（请求了不支持的能力当场抛错，不静默降级）；失败走值不走异常；**部分输出必回传父级**；fork 种子 = 已完成轮次前缀；子作用域创建窗口内完成权限收窄（approval 钉死） | `SubagentProvider` 协议 + `SubagentCapabilities: OptionSet`；`delegate` 工具结果判别联合（foreground/background）；工具描述从 provider 事实派生（能否看到父上下文必须如实写进措辞） |
| 15 | 作用域层叠注册（ScopedLayers）：全局层 + 按会话覆盖层，读时合并、近层遮蔽，写时按作用域路由，生命周期随会话 | `[ScopeID: Layer]` 字典 + global 层（约 200 行）；支撑"每个 Chat 独立工具集/权限"、**Assistant/Tutor 模式裁剪**（决策 15）与未来的 agent preset |
| 16 | 工具 UI 渲染意图是纯函数（presentCall/presentResult → 卡片类型枚举），实时与回放共用同一投影 | 魏碑已有工具卡片 UI；新增工具必须实现渲染意图纯函数，无卡 UI 回退原始文本 |

### 3.2 明确不引入的部分（DSH/Cordis 中为开放生态付的税）

- 运行时插件树、热插拔、effect 作用域机的完整形态（魏碑是编译期确定的单一桌面 App；
  要的是"注册返 disposer"的纪律，不是 fiber 状态机）；
- `cordis.yml` 配置组合层、profile/bundle 分层、HMR；
- Proxy/原型链 Context、TypeScript declaration merging 的事件类型扩展（Swift 用封闭
  enum + 协议获得同等类型安全）；
- Code Mode（模型写代码调 SDK，依赖进程内 JS 运行时）；
- 跨进程/远程 provider 全家桶（ACP 等）；
- deepFreeze/structuredClone 防御层（Swift 值语义天然免疫）；
- 后台可持续子会话的 Activation 驻留状态机（约 1500 行，二期再说）。

### 3.3 模块划分（新增目录 `Sources/WeiBeiCore/NativeAgentRuntime/`）与取证校准后的工作量

| 模块 | 内容 | 粗略量级（Swift，不含测试） |
|---|---|---|
| `NativeAgentEvents.swift` | StreamChunk / 会话事件 / 统一错误类型；事件总线（四种分发模式，分发模式写进事件契约） | 400–600 行 |
| `NativeAgentLedger.swift` | append-only 账本、SurfaceManager、deriveMessages 投影、崩溃 closer、fork 前缀快照、持久化（单后端） | 1.2–1.8k 行 |
| `NativeAgentLoop.swift` | 相位机 driver、turn/step 循环、inbox（账本投影）、拦截链、取消配平、`delegate` 递归 | 1.0–1.5k 行 |
| `NativeAgentTools.swift` + `ToolRegistry` | 作用域层叠注册表（含按模式裁剪）、三段 waterfall 管线 + deny-only guard、12 工具 Swift 实现（直读 live stores；复用 UI 同一 store 能力方法；工具定义携带权限等级）、`create_document` | 800–1200 行 + 工具本体 |
| `NativeAgentPrompt.swift` | section/order 注册式 prompt 组装，工具 schema 回调注入 | ~200 行 |
| `Providers/` | `LLMAdapter` 协议 + Chat Completions 族（第一棒）+ Responses/Anthropic/Gemini（第二棒）；每族四文件（wire/序列化/翻译/适配器） | 每族 500–800 行 |
| `NativeAgentCredentials.swift` | **魏碑自持凭证文件**（App 数据目录，权限 0600；原子写入 + 损坏备份恢复；**不用系统钥匙串**） | 150–250 行 |
| `NativeAgentOAuth.swift` | openai-codex 浏览器/设备码登录、刷新、退出（第二棒）；token 存同一凭证文件 | 300–500 行 |
| `NativeAgentSkills.swift` | 技能包格式（SKILL.md + manifest + 可选附带工具声明）、注册表、`load_skill` 工具、目录注入钩子；JSC hook 仅预留接缝、仅限内置签名技能 | 800–1200 行 |
| 不变量检查器 + 自测 | model-visible⟺logged 断言、SSE 分帧、取消传播、账本 round-trip 等（挂 `NativeAgentSelfChecks.swift`） | 400–600 行 |

**总量：引擎约 5–7k 行 + 4 族协议约 2–3k 行 + 等量测试。一人全量约 8–12 周**
（含对拍与真账号验证；Grok 执行按棒次推进，不以日历排期）。

后端开关：`StudyAgentBackend` 加 `native` case；`WorkspaceStore` 按
`WEIBEI_AGENT_BACKEND` 环境变量（`native`/`pi`，默认 `pi`）选择运行器。UI 不动。

## 4. 四棒执行

每棒一个提交组，四棒共用同一分支与同一草稿 MR；**全程不滚动合并**（决策 16）。

### 第一棒：行为基线 + 引擎骨架（OpenAI 兼容族 + API Key）

基线任务（先写代码前完成，产出写入 MR 描述或 `Docs/audit/` 附页）：

- 12 工具契约表：每个工具的输入 schema、输出结构、副作用（读/写/提案）、超时与上限，
  依据 extension.ts 与 PiAgentRuntime 实际代码，不靠猜。
- Pi 行为夹具：用固定场景集（第 5.1 节）在 pi 后端各跑一遍，保存 RPC 事件流、最终
  `StudyAgentReply` 关键字段（工具序列、来源、提案、toolTrace、错误分类），作为对拍基准。
- Pi 会话行为记录：续聊时发给模型的上下文构成（哪些历史轮次回放、envelope 如何进入
  system/user prompt）、compaction/截断行为（若有）。
- Tutor 能力映射表：tutor 预期需要的每项能力逐项标注原生实现路径，写进报告。

实现任务：

- 模块：事件词汇与总线、账本（含投影与崩溃 closer）、循环（不含 delegate）、
  ToolRegistry + 三段管线 + deny-only guard（工具定义含权限等级；按模式裁剪）、
  12 工具 Swift 实现（直读 live stores，复用 UI 同一 store 方法）、prompt 组装器、
  **凭证文件存储**、`OpenAIChatCompletionsProvider`、后端开关、不变量检查器。
- `NativeAgentSelfChecks.swift`：SSE 分帧（UTF-8 跨包、CRLF、超长行上限）、tool call
  增量组装、残缺参数拒绝执行、取消传播（含未开始工具合成结果配平）、账本写入/回放
  round-trip、崩溃 closer 合成、**凭证文件读写/权限位/损坏备份恢复**、错误映射
  `AgentFailureKind`、model-visible⟺logged 断言生效。
- 端到端：用 DeepSeek API key 验证连通并跑通"普通问答 → 课程搜索后回答（带引用）
  → 中途取消"三闭环（CLI 通道即可，决策 13/14）。

完成门槛：`swift build` 全绿；`swift test` 全绿；WeiBeiSelfCheck 全绿（含新增自测）；
上述三闭环跑通并记录证据；默认后端为 pi 时 App 行为与 main 完全一致（回归冒烟）。

### 第二棒：ChatGPT 订阅 OAuth + OpenAI Responses + Anthropic/Gemini

实现任务：

- `NativeAgentOAuth.swift` + `OpenAIResponsesProvider`（含 reasoning 与原生 web_search
  平移，依据 `extension.ts:453` 的现行逻辑）。
- `AnthropicMessagesProvider`（含 replayState 机制：thinking 签名的版本化存取、
  跨适配器降级）、`GoogleGenerativeAIProvider`。
- anthropic / github-copilot / radius 三个订阅入口做 **Pi 现状复现验证**（决策 11）：
  逐个验证 Pi 当前能否完成登录 + 发消息；能 → 列入原生移植清单（本实验完成技术
  验证与实现方案，实现本身可后续棒次跟进）；不能 → 报告中标注"Pi 亦不能，下架依据"。

验证任务（真账号，用户配合提供一次登录）：

- ChatGPT 订阅全链：浏览器登录 → 发消息 → 触发课程工具调用 → 中途取消 → 强等 token
  过期（或人为使 access token 失效）→ 自动刷新成功 → 退出登录 → **凭证文件无残留**。
- 每个新协议族至少一个真实模型跑通第一棒的三闭环（CLI 通道）。

完成门槛：同第一棒 + OAuth 六步全过。若 OAuth 被服务端拒绝或流程不通：按预裁决退路
执行（决策 3：API key 先行、订阅入口暂时隐藏），留证写入报告，**不得伪造通过**。

### 第三棒：能力面三件套（技能系统 / create_document / delegate）+ 评测集起草

实现任务：

- 技能系统：技能包格式（SKILL.md + manifest.json + 可选附带工具声明）、注册表与目录
  摘要注入、`load_skill` 工具（v1 加载=纯指令注入，不改变注册状态；附带工具声明仅
  解析不落注册）；现有 visualize 迁移为第一个技能包（行为等价，对拍覆盖）；新增一个
  真实教学类技能（执行者自选，如"苏格拉底追问"，内容随评测集一起交用户审定）验证
  多技能共存；JSC hook 仅留接缝。**Assistant 模式可用性演示**：CLI 或真机演示加载技能
  前后目录与回答风格变化（决策 15）。
- `create_document`：HTML/Markdown/SVG 落盘为工作区文稿 + 沙箱渲染最小查看器
  （复用富回答 webview 策略）；**引擎具备、Assistant 模式默认关闭**（决策 15）。
- `delegate`：子智能体递归（独立账本 + 工具子集 + 深度常量 + 能力声明前置校验 +
  失败走值 + 部分输出回传）；**引擎具备、Assistant 模式默认关闭**（决策 15），
  用开关演示一轮完整分工。
- **新评测集起草**：不少于 40 题，覆盖第 5.1 节 12 场景能力面 + 真实学习问题，
  **不含 GenUI/可视化生成题**（决策 13）；每题带 rubric 期望要点；素材为**混合来源**
  （模型生成题 + 网络习题 + 真实学习场景会产生的疑问 + 闲聊场景 + 要求深聊的场景；
  用户 2026-08-22 裁决 Q14）；产出 `Docs/audit/` 下的评测集文件，**用户审定后
  才可用于第四棒**（旧 56 题作废，不得使用）。

完成门槛：三件套各有自测 + 演示证据（技能加载前后目录变化、文稿落盘可打开、
子智能体一轮完整分工）；评测集草案与新技能内容提交用户；默认 pi 后端回归零差异；
前两棒门槛持续保持。

### 第四棒：对拍评估 + 报告

前置条件：**用户已审定第三棒的评测集与新技能**。

按第 5 节执行全部对拍（CLI 通道驱动，不开真实 App，决策 13），产出：

- `Docs/audit/2026-08-2X-native-runtime-对拍报告.md`（模板见 5.5）。
- MR 描述更新：实际改动、未做内容、能力矩阵（41 入口逐一标注 覆盖/未覆盖/Pi 亦不能）、
  共享文件占用、验证命令与结果。

完成门槛：报告数据完整、可复现（命令与配置写清）；go/no-go 建议明确。

## 5. 对拍测试方案（本实验的核心交付）

总原则：**同一 workspace 副本、同一模型、同一问题，pi 与 native 各跑一遍**；比对行为与
结构，不比逐字文本（模型输出本身有随机性，质量评估走 5.2 的 rubric）。评测全程走
CLI 通道（WeiBeiPiCheck 扩展），不开真实 App（决策 13）；真实 App 只保留一次轻量冒烟。

### 5.0 首要机制：账本对拍

托"model-visible ⟺ logged"不变量的福，差分比对的主战场是**事件日志本身**：
两侧各自跑完后导出会话事件序列（工具调用、参数、来源、提案、错误分类、取消点），
做结构化 diff。这比对比最终文本可靠得多，且自动化成本最低。Pi 侧用其 RPC 事件流
录制结果，Native 侧直接读账本。

### 5.1 行为差分（CLI 自动化）

固定场景集（12 项，即第一棒基线夹具的同一组）：

1. 普通问答（无工具）
2. 课程搜索后回答（校验工具序列 + 来源列表）
3. 课程正文读取 + 引用跳转信息（jumpReference 完整）
4. 学习记忆读取 + 更新建议（提案结构等价、不落库为自动写入）
5. 课程知识档案更新建议
6. 笔记建议 + 关系建议（用户确认前不落库）
7. 可视化产出（仅校验 spec 结构合法；**不评生成质量**，决策 13）
8. 图片输入回答
9. 中途取消（流式中 cancel：立即停止、账本落中断态、未开始工具合成结果配平；
   UI 层一致性归入真实 App 轻量冒烟，不在本差分内）
10. 错误分类：401 / 429 / 断网 / 超时（可用无效 key 与代理模拟）→ 两侧 `AgentFailureKind` 一致
11. 旧会话续聊：关闭重开后追问，验证模型记得此前工具结论（账本回放有效）
12. 多工具单轮并行调用（若模型触发）+ 参数截断保护

比对项（机器可读 diff）：工具调用序列与参数 JSON、来源列表（itemID/label）、提案结构、
错误分类枚举、取消后状态、续聊可用性、最终 `StudyAgentReply` 各字段存在性。

能力面三件套（技能 / create_document / delegate）**不进对拍基线**（Pi 无对应物），
由第三棒的专项自测与演示验收。

### 5.2 回答质量（新编评测集，CLI 双后端）

- **旧 56 题题库作废，不得使用**（用户 2026-08-22 指示）。
- 使用第三棒起草、**用户审定**的新评测集（≥40 题，覆盖 12 场景能力面 + 真实学习问题，
  不含 GenUI/可视化生成题；素材混合来源：模型生成 / 网络习题 / 真实学习疑问 / 闲聊 /
  深聊请求）。
- 经 CLI 通道（WeiBeiPiCheck 证据链扩展）在两种后端各跑一遍；质量测试主用
  ChatGPT 订阅 + `gpt-5.6-luna` + low 推理档（决策 14）。
- **评分：独立 judge（非执行者，预定 Kimi）** 按 rubric 逐题双评；**用户可全量过目**；
  差异 ≥2 分的题附两侧原文摘录。
- Rubric 逐题 5 分制（用户 2026-08-22 裁决 Q15）：**正确性 / 语言流畅度 /
  回答长度合理性**。引用完整性、来源可跳转属功能性指标，由 5.1 行为差分覆盖，
  不进质量分。

### 5.3 性能

| 指标 | 方法 | 预期 |
|---|---|---|
| 冷启动到可输入 | `WEIBEI_PERF=1` 探针 + 计时，各 5 次取中位 | native ≤ pi（少一个外部进程） |
| 首字时间 TTFT | 固定问题 × 两种后端 × 5 次取中位 | 差值 ≤ ±10% |
| 整轮时延 | 同上 | 差值 ≤ ±10% |
| 峰值内存 | 回答含工具调用场景，`perf_p95.sh` 或 Instruments 记录 | native 明显低于 pi（无 Bun） |
| 空闲常驻进程 | 活动监视器/ps 记录 | native 无 pi 子进程 |

### 5.4 体积

- 同一 SHA 分别以默认（含 Pi）与" hypothetical 删除 Pi"两种配置出 Release `.app`
  （实验期用脚本临时排除 PiRuntime 资源即可，不改发布流程），对比未压缩体积。
- 另各出一个本地 DMG 对比下载体积（只记录，不卡门槛）。
- go 门槛卡未压缩 .app ≤ 55 MB（用户确认）；有异常再议。

### 5.5 报告模板与 go/no-go 标准

报告固定章节：基准与环境 / 能力矩阵（41 入口）/ 行为差分结果（账本 diff + 12 场景表）/
评测集质量得分与差异清单（独立 judge）/ 性能表 / 体积表 / OAuth 真账号验证记录 /
能力面三件套验收记录 / 已知差异与风险 / go-no-go 建议。

go 的全部必要条件（缺一即 no-go 或条件 go，由用户裁决）：

1. 12 场景行为差分零高危差异（工具序列/提案结构/错误分类不允许不一致；文本表述差异允许）。
2. 新评测集均分不低于 pi 侧 0.3 分，且无单题回退 ≥2 分（独立 judge 评分）。
3. 性能全项达标（上表预期列）。
4. 未压缩 .app ≤ 55 MB。
5. ChatGPT 订阅 OAuth 六步验证全部通过且留证。
6. 能力面三件套专项验收通过。
7. 默认 pi 后端回归冒烟零差异（本实验不改默认行为）。

## 6. 验收门槛（本实验分支的完成定义）

1. 四棒实现完成，第 4 节各棒门槛全过；CI 绿；`swift build` / `swift test` / WeiBeiSelfCheck 绿。
2. 默认后端为 pi 时全 App 回归冒烟无差异（一次轻量真实 App 冒烟，按 AGENTS.md 口径执行）。
3. 对拍报告入库，数据可复现。
4. MR 描述完整：实际改动、未做内容（Bedrock/Vertex/Azure 等未覆盖族、订阅移植清单的
   落实情况、旧会话内部上下文不迁移）、共享文件占用与释放条件、验证命令、冒烟结果。
5. **本分支不删除 Pi/Bun、不改发布脚本、不打标签。**
6. **合并方式**：全程草稿 MR；报告通过、用户最终拍板后才转正式合并（决策 16）。

## 7. 执行纪律（AGENTS.md 约束）

- 开工先 `git fetch`，从最新 `origin/main` 建分支 `codex/native-agent-runtime`；当天推送
  并建目标为 `main` 的**草稿 MR**；本任务仅此一个分支一个 MR。
- **不滚动合并**：四棒在同一草稿 MR 上累积推进，每棒更新 MR 描述（实际改动、验证证据、
  下一棒计划）；第四棒报告通过、用户拍板后才转正式（决策 16）。
- 共享核心面占用声明（写进草稿 MR 首评）：`Package.swift`（新增源文件/target 资源）、
  `Sources/WeiBei/Stores/WorkspaceStore.swift`（后端开关）、
  `Sources/WeiBeiSelfCheck/main.swift`（挂新自测）。预计释放条件：本 MR 合并。
  若发现同一文件已被其他活跃任务占用，停止修改并在 MR 中记录，等主会话协调。
- 验证命令（每棒必跑）：`swift build`；`swift test`；`.build/debug/WeiBeiSelfCheck`；
  `script/build_and_run.sh check`；推送前确认 CI 两 job 绿。
- 遇到问题不绕过检查、不回退伪造通过；真实阻塞如实记录。

## 8. 风险与止损

| 风险 | 处置 |
|---|---|
| ChatGPT 订阅 OAuth 被服务端拒绝/流程不通 | 用户判断可能性低，验证照旧；若真发生 → 预裁决退路（决策 3）：API key 先行、订阅入口暂时隐藏，不留 Pi 混合形态；留证写入报告 |
| 其他订阅（anthropic/copilot/radius）移植后被厂商封禁 | 以 Pi 现状为基线移植（决策 11），政策风险用户知情承担；报告逐家标注 Pi 现状证据 |
| 评测集质量不过关（起草偏题/覆盖不足） | 第四棒前置条件是用户审定；审定不过就打回重编，不得带病使用，更不得回退用旧 56 题 |
| 评测集素材涉真实学习材料 | 入库前脱敏（素材来源待第二轮 Q14 裁决） |
| 独立 judge 与执行者串谋或评分漂移 | judge 非执行者（预定 Kimi）；rubric 逐题留评分理由；用户可全量复核 |
| 可执行技能的安全面 | v1 纯指令注入；JSC hook 仅预留接缝、仅限内置签名技能；第三方技能永不执行脚本 |
| HTML 文稿 XSS/数据越界 | 沙箱 WKWebView，策略与现有富回答 webview 对齐；文稿内容不获得应用内数据通道 |
| 子智能体失控递归 | 深度与单轮工具数配置常量硬性限制；不做精细预算体系（本轮明确排除） |
| 协议长尾工作量 | 只保四族；未覆盖族在能力矩阵显式标注；后续缺哪族接哪族 |
| 会话账本与 Pi 上下文策略存在行为差异 | 允许差异存在，但必须写进报告"已知差异"节，由用户判断是否可接受 |
| 质量回归判定争议 | 以 rubric 得分 + 差异清单为准，不以逐字 diff 为准 |
| 真实账号登录涉及用户凭证 | 只在用户在场时由用户本人操作登录；执行者记录流程与结果，不记录任何 token 内容 |
| 基准漂移（origin/main 或 DSH checkout 前进） | 开工重测第 2 节全部断言，差异写进 MR |
