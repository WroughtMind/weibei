# 魏碑 Agent 开发与发布规则

本文件适用于整个仓库。用户已授权把这些规则作为长期流程约束；所有 Agent 和新任务都必须遵守。

## 分支与合并请求

1. `codex/course-workspace` 是唯一开发整合线，`main` 只接收整合线验收通过的版本。
2. 每个新任务先拉取远端，再从最新 `origin/codex/course-workspace` 创建一个短分支 `codex/<任务名>`。普通功能任务不得直接在整合线或 `main` 上开发。
3. 一个任务只对应一个分支、一个工作目录和一个合并请求。开始工作的当天必须推送分支，并建立目标为 `codex/course-workspace` 的草稿合并请求；不能把未推送的本地工作目录当作长期成果保存处。
4. 旧功能分支和救援分支只可用于取证。禁止把旧分支整体 merge、rebase 或批量 cherry-pick 到当前开发线。需要复用旧成果时，必须从最新整合线开新分支，只迁移经过审查的最小改动，并重新完成验证。

## 共享核心文件占用

以下位置默认属于共享核心面：

- `Sources/WeiBei/Stores/WorkspaceStore.swift`
- `Sources/WeiBei/App/WeiBeiApp.swift`
- `Sources/WeiBei/Views/ContentView.swift`
- `Sources/WeiBei/Views/StableDocumentWorkspace.swift`
- `Sources/WeiBeiSelfCheck/SelfCheckSupport.swift`
- `Sources/WeiBeiSelfCheck/SelfCheckRunner.swift`
- `Sources/WeiBeiSelfCheck/WeiBeiSelfCheckMain.swift`
- `Package.swift`
- `script/`
- `.github/`
- `VERSION`

修改共享核心面之前，必须在任务对应的 issue 或草稿合并请求中写明“占用文件、负责人任务、预计释放条件”。同一文件同一时间只能由一个活跃任务占用；发现已有占用时，停止修改并交由整合任务协调，不得在另一条分支上并行改出第二套实现。

## 权限边界

- 只有明确标记为“整合”或“发布”的任务可以合并合并请求、更新 `codex/course-workspace`、把整合线合入 `main`、创建标签、发布版本或上传正式安装包。
- 功能任务可以生成本地安装包做验收，但不得把它当作正式发布物，也不得自行合并自己的合并请求。
- 不绕过自动检查，不用回退实现伪造通过结果；检查失败必须修复或明确记录真实阻塞。

## 完成定义

任务只有同时满足下列条件才算完成：

1. 需求范围内的实现和必要文档已经完成，没有混入无关改动。
2. 已运行与风险相称的构建、自检和真实体验验收；界面改动必须有真实窗口证据，发布链路改动必须验证安装包元数据和签名。
3. 草稿合并请求已更新，写清实际改动、未做内容、共享文件占用、验证命令和结果。
4. 分支已推送，工作树干净，成果不只存在于本地或临时目录。
5. 已把合并风险和后续动作交给整合任务；只有整合任务可以宣布已合并或已发布。
