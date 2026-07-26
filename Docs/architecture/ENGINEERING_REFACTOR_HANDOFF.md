# 工程化重构 PR 移交说明

更新时间：2026-07-26

本文用于把当前工程化重构任务移交给下一位 Agent。当前不是“尚未开始”的状态：6 个并行子代理的实现已经全部落入共享工作树，主要编码基本完成；剩余工作是主线集成、继续修正 SelfCheck、运行完整验证、整理提交、推送并更新草稿 PR。

## 1. Git 与 PR 状态

- 仓库：`/Users/wkp/workspace/weibei`
- 当前分支：`codex/engineering-refactor`
- 基线：`origin/codex/course-workspace` 的 `3b2abbd5cb10f128c7093721482e5b2ad472fcbf`
- 当前 HEAD：`ec9e363 chore: 建立工程重构任务`
- 个人 fork remote：`fork`，仓库为 `wang-kaopu/weibei`
- 草稿 PR：`https://github.com/weibei-app/weibei/pull/48`
- PR base：`codex/course-workspace`
- PR head：`wang-kaopu:codex/engineering-refactor`
- PR 当前没有代码提交和 CI 结果，只有用于建立 PR 的空提交。

重要：工作树中有大量已完成但尚未提交的修改和 untracked 新文件。不要执行 `git reset --hard`、`git checkout -- .`、`git clean`，也不要从旧分支整体 merge/rebase/cherry-pick。所有当前改动都属于本 PR。

共享核心文件占用已经写入 PR 描述，包括：

- `Package.swift`
- `Sources/WeiBei/App/WeiBeiApp.swift`
- `Sources/WeiBei/Views/ContentView.swift`
- `Sources/WeiBei/Views/StableDocumentWorkspace.swift`
- `Sources/WeiBei/Stores/WorkspaceStore.swift`
- `Sources/WeiBeiSelfCheck/main.swift`
- `script/`
- `.github/`

本任务是功能重构任务，不得自行合并 PR、更新整合线、打 tag 或发布。

## 2. 已确认的产品与协议决策

Rich Answer 外层 Envelope 已决定删除 v1，只保留 v2：

- initializer 默认 `schemaVersion = 2`。
- 解码时必须显式提供 `schemaVersion`。
- 缺少版本、v1、未知版本都直接拒绝。
- Agent TypeBox schema 固定为 `Type.Literal(2)`。
- 不要删除 `weibei.openui.v1`，它是独立的内部 OpenUI program 版本。
- 不要删除 Pi runtime manifest v1、Python worker v1 或 renderer `specVersion`，它们都不是 Rich Answer 外层 Envelope v1。

已有 XCTest 覆盖 v2 initializer、v2 decode，以及 v1、缺失版本、未知版本拒绝。

## 3. 七项任务完成情况

### 3.1 核心行为测试安全网：已实现

- `Package.swift` 新增 `WeiBeiCoreTests`。
- `Tests/WeiBeiCoreTests/` 新增 5 个文件、19 个 XCTest。
- 覆盖：workspace 持久化 round-trip/legacy、note-source 去重和索引、来源引用解析、选区合并、Markdown/tag，以及 Rich Answer v2-only。

本机只有 CommandLineTools，没有可用的 `XCTest.framework`，所以本机 `swift test` 会报 `no such module XCTest`。这不是测试用例失败，最终需由 GitHub Actions 的完整 Xcode 环境执行。

### 3.2 CI、生成物和设计资源检查：已实现

- `.github/workflows/pr-checks.yml` 增加 Web/生成物 job。
- Swift job 运行 `swift test` 和规范入口 `./script/build_and_run.sh check`，覆盖 imported identity、WebEditorCheck 和 PiCheck。
- 新增 `script/check-generated-resources.sh`，在临时目录重建并比较 Editor 与 Rich Answer 生成物，不改写工作树。
- `DesignSystem/scripts/build-manifest.mjs --check` 已修复为真正只读。
- DesignSystem 图标文档已更新为实际已接入状态。
- `script/build_and_run.sh` 已调整：依赖完整时 `check` 执行根 `npm run check`；普通构建分别更新 Editor 和 Rich Answer 资源；Node 依赖完全缺失时由 CI 的 Web job 负责检查，部分安装则明确失败。

### 3.3 App、布局与验证基础设施：已实现

- `WeiBeiApp.swift` 从约 1,244 行降到 236 行。
- 菜单迁到 `Sources/WeiBei/App/WeiBeiCommands.swift`。
- 截图/验证迁到：
  - `VerificationCaptureModels.swift`
  - `VerificationCaptureCoordinator.swift`
  - `WindowSnapshotService.swift`
- 删除旧的 `ResizableTwoPane`、`ResizableThreePane`、`WeiBeiSplitView`、`NativeSplitCoordinator` 旁路实现。
- 新增纯值 `PaneLayoutGeometry`，`ContentView` 与 `StableDocumentWorkspace` 共用 pane/divider 几何计算。
- 课程目录与稳定工作区改为同级水平列；目录通过 `0 ↔ 292pt` 宽度动画平滑压缩工作区，不再覆盖 AppKit 面板渲染层。

### 3.4 WorkspaceStore 拆分和 I/O 边界：已实现

- `WorkspaceStore.swift` 从约 7,994 行降到 3,169 行。
- 新增 7 个领域 extension，均低于 900 行：Course、Presentation、Pane、Layout、AgentSettings、Library、Notebook。
- 验证场景拆为 530 / 456 / 430 行三个文件。
- 新增：
  - `WorkspaceRepository` actor
  - `NotebookRepository` actor
  - `CourseLibraryService` actor
  - `AgentRequestCoordinator`
- 普通 workspace/Markdown debounce 写入和课程递归扫描已移出 MainActor。
- 显式 flush、rename 事务和 `replaceItemIDEverywhere` 仍保留同步耐久/原子协调边界。

跨文件 `extension WorkspaceStore` 需要把一部分 `private` / `private(set)` 放宽为 module-internal；`WorkspaceStore` 本身是 internal，没有扩大 public API。

### 3.5 大型 View 拆分：已实现

- `NotesAgentView.swift`：约 4,649 → 348 行。
- `ReaderView.swift`：约 3,295 → 927 行。
- `GeneratedRichAnswerView.swift`：2,092 → 668 行。
- `RichAnswerHost.swift`：2,774 → 463 行。
- `AgentPaneView.swift`：1,511 → 301 行。
- `Views/Agent/` 和 `Views/RichAnswer/` 的新实现文件均控制在 900 行以内。
- Generated canvas 已真实接入独立的 CompositionIndex、Projection、Layout、HitTesting。
- Rich Answer verification marker 已迁到 `Sources/WeiBei/Verification/`。

### 3.6 Web runtime、Editor 和 Pi extension：已实现

- `Prototypes/RichAnswerWebRuntime` 已明确为生产源码真相，不再描述为一次性 throwaway prototype。
- legacy gallery 已迁入 `src/dev/`，不进入生产 bundle。
- renderer 生产逻辑从 `*.self-check.ts` 迁到 `*.domain.ts`，新增 Vitest 合约测试。
- 根 `package.json` 已增加 Editor、Rich Answer、生成物和总检查脚本。
- `Sources/WeiBei/WebEditor/build-editor.mjs` 和 README 已新增。
- `extension.ts` 从 9,938 行降到 1,601 行。
- `AgentResources/domains/` 按 context、Python artifact、catalog、registrations、schema、renderer validation、render plan、OpenUI parser/semantics/program validation 拆分；具体领域文件均低于 1,200 行，最大约 1,058 行。
- 修复拆分后的相对资源路径：Skill 使用 `../skills`，Python worker 使用 `../python`。
- `check-agent-extension.mjs` 会检查入口/模块行数、v2-only、相对资源路径、TS 结构和完整 esbuild bundle。

已知非阻塞项：Vite 生产 bundle 约 1.61 MB，会触发大于 500 KB warning；runtime `npm audit` 仍有 2 moderate + 1 high，自动修复需要 breaking `--force`，本 PR 未擅自升级。

### 3.7 Core 模块和架构文档：已实现

- 删除原 `WorkspaceModels.swift`，拆为 8 个职责文件，公开类型和 Codable 字段保持不变。
- `RichAnswerEngine.swift` 从 3,291 行降到 290 行。
- Rich Answer Schema、Markdown、Presentation、StrictCoding、Evidence、Scene/UI/Intent/Domain validation 已分离；validator 文件均低于 900 行。
- Renderer catalog 和 self-check 已分离。
- Pi configuration、runtime bundle、diagnostics 已分离。
- Course index 拆出 extractor、query、scheduler、SQLite store。
- Study Agent 拆出 policy、DTO、failure mapping、context envelope。
- `Docs/architecture/README.md` 已新增，说明目标边界、状态流、源码真相/生成物和验证分层。

`PiAgentRuntime.swift` 仍约 1,474 行，暂未机械拆 reducer/transport，因为 Process、continuation、watchdog、active run 的事件顺序强耦合；本 PR 先保留该一致性边界。

## 4. 当前已经通过的验证

各子代理在完成各自范围时已报告通过：

- 完整 `swift build`。
- `WeiBeiCore` target build。
- `WeiBei` target build。
- Swift frontend parse。
- `npm run check`。
- 2 个 Vitest 文件、8 项测试。
- `script/check-generated-resources.sh`。
- `DesignSystem/scripts/verify-assets.sh`。
- Pi extension esbuild bundle。
- `git diff --check`。

主代理集成后又实际执行并通过：

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/weibei-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/weibei-swiftpm-module-cache \
swift build --disable-sandbox
```

结果：完整 Swift build 成功。使用默认 MacOSX 26.5 SDK；不要设置 `SDKROOT=MacOSX15.4.sdk`，当前 Swift 6.3.3 与该旧 SDK 不匹配。缓存必须指向可写的 `/private/tmp`，否则沙箱内会尝试写 `~/.cache/clang` 并失败。

当前最新一次静态检查也已通过：

```bash
git diff --check
swiftc -frontend -parse Sources/WeiBeiSelfCheck/main.swift Sources/WeiBeiSelfCheck/PiAgentSelfChecks.swift
bash -n script/build_and_run.sh script/check-generated-resources.sh DesignSystem/scripts/verify-assets.sh
```

## 5. 当前未完成：SelfCheck 集成

这是下一位 Agent 的第一优先级。

重构前的 `WeiBeiSelfCheck/main.swift` 大量断言要求某段代码必须位于旧单文件。主代理已做了以下集成：

- 新增 `readSourceTree(_:)`，按领域目录聚合源码。
- Notes/Agent、Reader、RichAnswer、Core、AgentResources、App/Verification、Stores/Verification 改为目录级读取。
- PiAgentSelfChecks 改为聚合 `extension.ts + domains/*.ts`。
- CourseDocument index 改为读取拆出的 5 个文件。
- 删除旧 split 的正向断言，改为验证旧实现不存在、`StableDocumentWorkspace + PaneLayoutGeometry` 存在。
- 对跨文件 extension 必须放宽的可见性，不再要求字符串包含 `private`。
- 已逐项修正 Course index、Reader、App capture、Appearance、WorkspaceStore 等重构后的源码断言。

SelfCheck 必须在沙箱外运行，因为 Vision OCR 和系统框架在沙箱内会失败：

```bash
CLANG_MODULE_CACHE_PATH=/private/tmp/weibei-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/weibei-swiftpm-module-cache \
swift build --disable-sandbox --product WeiBeiSelfCheck

.build/debug/WeiBeiSelfCheck
```

上一次实际运行的失败是：

```text
self-check failed: note pane creation and agent header stay custom, light, and context-only
```

失败后已经修改但尚未重新构建/验证：

- `agentPaneHeaderSource` 改为读取整个 `Sources/WeiBei/Views/Agent`。
- `notebookCreationPanelSource` 改为读取整个 `Sources/WeiBei/Views/Notes`。

因此接手后应直接重新 build SelfCheck 并运行；不要假定仍会停在同一个失败点。每次只修正因文件迁移、可见性变化或合理包装函数产生的结构断言，不要删除真实行为检查，也不要通过回退实现伪造通过。

## 6. 后续验证清单

建议按以下顺序完成：

1. 重新 build 并在沙箱外运行 `.build/debug/WeiBeiSelfCheck`，直到通过。
2. 检查项目没有 `.nvmrc`；本轮已使用 nvm 的 Node `v22.22.3`。所有本机 Node 命令按仓库规则在沙箱外、nvm 环境执行。
3. 运行根 `npm run check`。
4. 运行 `./script/check-generated-resources.sh`。
5. 运行 `./DesignSystem/scripts/verify-assets.sh`。
6. 运行完整 Swift build。
7. 运行 `./script/build_and_run.sh check`，它会准备 Pi runtime 并执行 SelfCheck、imported identity、WebEditorCheck、PiCheck。
8. 运行 `swift test`；本机预计因缺 XCTest module 失败，必须记录为工具链限制，并以 GitHub Actions 完整 Xcode 结果为最终证据。
9. 运行 `./script/build_and_run.sh package`，校验安装包元数据和签名。
10. 因包含界面与验证链路修改，运行 `./script/build_and_run.sh --visual-verify`，保留真实窗口证据。

已知需要重点复核：

- imported identity 自检在沙箱内曾于 `NSFileCoordinator` rename 报 Cocoa 512；一次沙箱外执行曾长时间无输出并被终止。需要重新运行并判断是环境等待还是回归。
- `script/build_and_run.sh check` 现在在两套 Node 依赖都存在时会先执行 `npm run check`；若只装了一套依赖会明确失败。
- Agent API Key 已移出 macOS 钥匙串，统一保存在魏碑的 Application Support 私有目录。

## 7. 提交、推送与 PR 更新

所有代码仍未提交。完成验证后按逻辑分组提交，提交信息使用中文 Conventional Commits。可参考：

```text
test: 建立核心行为测试与重构安全网
build: 统一检查入口和生成物校验
refactor: 隔离验证基础设施并删除旧布局
refactor: 拆分工作区存储与业务边界
refactor: 按功能拆分大型视图
refactor: 正式化网页运行时与协议
refactor: 整理核心模块与架构文档
```

提交时注意：大量新增目录仍是 untracked，必须全部复核并纳入；不要只 `git add -u`。

提交后推送：

```bash
git push fork codex/engineering-refactor
```

然后更新 PR 48，至少写清：

- 实际完成的七项改动。
- Rich Answer Envelope v2-only 决策及明确保留的其他 v1 协议。
- 共享文件占用和释放条件。
- 实际执行的全部验证命令与结果。
- 本机 XCTest 工具链限制、npm audit/Vite warning 等未解决但非伪装通过的问题。
- 合并风险和后续动作由整合任务处理，本任务不自行合并。

最后确认：

```bash
git status --short
gh pr view 48 --repo weibei-app/weibei
```

完成定义要求分支已推送、PR 已更新、工作树干净、CI 通过，并把合并风险交给整合任务。
