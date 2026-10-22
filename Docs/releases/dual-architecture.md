# macOS 双架构发布

魏碑使用同一份源码、版本号、Bundle ID 和用户数据目录，分别在原生 Apple Silicon 与 Intel runner 上构建。两个架构不是两个产品分支；任何一边失败，正式 Release 都不会公开。

## 公开资产契约

每个版本必须同时包含：

- `WeiBei-<version>-macOS-arm64.dmg` 与 `.sha256`；
- `WeiBei-<version>-macOS-x86_64.dmg` 与 `.sha256`；
- `appcast-arm64.xml`；
- `appcast-x86_64.xml`；
- `appcast.xml`，内容与 ARM 清单一致，仅供已经安装的旧 ARM 客户端兼容；
- `weibei.rb`，包含 ARM 与 Intel 两份 SHA-256；
- `WeiBei-<version>-debug-symbols.zip`，保存两种架构对应的崩溃分析符号，仅供开发者排查问题，不会装进用户电脑。

App 内的 `WeiBeiArchitecture` 和 `SUFeedURL` 会绑定当前包的真实架构。`WeiBeiDev verify-release-architecture` 会检查主程序、PDF 助手、窗口桥接及 Sparkle 中的全部 Mach-O；所有嵌套程序和框架都必须只包含目标架构，主程序还必须声明真实的 Mac Catalyst 平台。裁剪、资源整理在最终签名前完成。

两个安装盘共用仓库内固定背景图，只保留安装指引、Webi 和箭头；芯片类型由 DMG 文件名和 App 元数据表达，不在背景图上重复绘制。

## 日常 PR 门禁

`.github/workflows/pr-checks.yml` 保留必需汇总检查。共用业务自检运行一次；同一 Catalyst 任务分别在 `macos-26` 与 `macos-26-intel` 原生构建正式 App、启动检查，并在隔离的验收 App 中运行会话及资料保存重开检查。发布链路变更还会生成、挂载并检查当前架构 DMG，证据保留两天。旧独立会话工作流已并入此入口。

如果 GitHub 将来停止提供 Intel 托管 runner，必须先把 `macos-26-intel` 替换为运行受支持 Xcode 的 Intel 自托管 runner，保留两种架构的所有验收步骤；不得跳过 Intel job 后继续发布。

解压后 App 的逻辑字节数与 DMG 下载字节数分别记录在 `dist/package-<arch>.json`；字体、公式、图表和图片资源完整保留。

`package.json` 和 `package-lock.json` 仅根版本字段变化时，只进入发布链路检查；依赖、脚本或其他字段变化仍按完整影响范围检查。识别失败时按完整范围处理。发布接力与公开资产脚本只运行 Linux 上的行为与路由检查；版本号、声明或安装盘装配变化仍构建、启动和检查双架构正式包，不重复验收应用交互。应用、依赖、原生测试或构建输入变化仍运行双架构完整交互验收；混合改动取并集。

验收包与正式包分别编译，安装盘只装配已经构建和验证、编译配置为 Release 的正式 App，Debug 包会在装配前被拒绝：

```bash
./script/build_and_run.sh package
./script/build_release_dmg.sh --arch arm64
```

架构必须与构建环境一致；Intel 使用 `WEIBEI_TARGET_ARCH=x86_64`。`make release` 顺序调用这两个入口。单独运行安装盘脚本不会再次编译，缺少 App，或源码、版本、构建号、架构、公钥、更新地址及验收标记不符时直接失败。

### 定向诊断

失败时使用“魏碑定向诊断”，选原生架构和 `picker`、`conversation` 或 `business`。选择界面诊断复用真实的引导、导入与界面建立步骤，记录聚焦前后的位置、高度、安全区及控制器证据，随后结束；不会继续跑无关的保存重开流程。失败时仍上传已取得的截图与 JSON。完整 PR 门禁保持原有检查。

在诊断工作流尚未进入主线的分支，也可以通过已有 PR 工作流转发：

```bash
gh workflow run pr-checks.yml --ref codex/example \
  -f diagnostic_arch=arm64 -f diagnostic_scenario=picker
```

该入口只启动诊断，不发布同名的 PR 必需检查结果；修复后仍须让当前 PR 提交的必要检查通过。

### 构建耗时与缓存

编辑器资源、GenUI 资源、依赖解析、原生编译、DMG 装配和更新安装分别记录到 `.build/timings/*.jsonl`。编译输出实时保留，Xcode 输出 `Build Timing Summary`，失败也写入退出码与耗时。工作流会上传这些文件。

缓存键包含 macOS、Xcode、SDK、架构、去掉根版本号的 Node 依赖清单、Swift 锁文件、项目配置、构建脚本与依赖补丁。同一架构和配置顺序复用一个编译目录；验收开关只传给实际包含验收代码的主应用和窗口组件，因此切换正式包时重编这两个目标，复用未变化的核心库、依赖与 SDK 模块。最终 App 和窗口组件每次重新装配、裁剪并签名，最终包不进入 CI 缓存；正式包继续校验源码、架构、dSYM、签名及验收代码残留。日志以 `build-1.log`（验收）和 `build-0.log`（正式）分开保存。测试失败时也保留已生成的中间结果，失败结果仍阻止合并和发布。

Release 的 `-Osize` 优化统一传给应用和 Swift 依赖，保留整模块优化；Debug 仍使用 `-Onone`。衡量冷编译时运行“Catalyst 冷编译基准”，指定旧提交与架构。它在同一台原生机器上依次构建旧提交和当前分支，使用各自空的编译目录，不恢复缓存，校验两个正式 App 并实际启动；`comparison.json` 保留机器、源码、编译和完整构建耗时。后一次构建可能受操作系统文件缓存影响，因此单次结果仍需结合 PR 阶段日志判断。

## 正式发布工作流

准备或修订发版说明时，先按仓库内的 [Release Changelog 规范](../../.agents/skills/release-changelog/SKILL.md) 核对版本区间与 PR，随后同步 `Docs/releases/v<version>.md` 和 `Docs/update-summaries/v<version>.md`。正文按“功能 / 改进 / 修复”归类，每项标明对应 PR；下载与安装信息留在下载区，应用内摘要只保留变更内容。

在 GitHub Actions 中手动运行“魏碑双架构正式发布”，输入与 `VERSION`、`package.json` 和 `Docs/update-summaries/v<version>.md` 一致的版本号。默认构建并验证两种架构及更新签名，然后汇总完整候选集合，保存在 Actions 的 `release-ready` 产物中，不创建 Tag 或 Release；可以从待合并分支验证仓库密钥。获得正式发布授权后，从 `main` 运行并勾选 `publish`，才会公开版本。

当前发布路线固定使用 ad-hoc 签名，不需要付费 Apple 开发者账号，也不执行 Apple 公证。发布说明和 Cask 必须保留首次启动指引。

工作流要求以下 GitHub Secrets：

| Secret | 用途 |
|---|---|
| `WEIBEI_SPARKLE_PUBLIC_KEY` | 写入 App 并验证更新签名 |
| `WEIBEI_SPARKLE_PRIVATE_KEY_BASE64` | 两个 appcast 的 EdDSA 私钥 |

Sparkle 密钥与 Apple 公证无关。首次公开发布前生成一次正式密钥对：公钥写入 App，私钥放入 GitHub Secret 并保留一份离线加密备份；已有用户后不得随意更换。

正式密钥保存在开发机系统钥匙串的 `WroughtMind/weibei` 账户中；使用 Sparkle 的 `generate_keys --account WroughtMind/weibei -p` 核对公钥，`-x <文件>` 导出，`-f <文件>` 从备份恢复。私钥 Secret 必须是导出文件整体再次 Base64 编码后的内容。早期开发版内的测试公钥没有对应的正式私钥，需要手动安装一次采用正式公钥的版本，后续版本始终沿用这套密钥。

仓库应配置受保护的 `production-release` Environment。两个架构先并行完成最终 App 启动、签名结构、DMG、架构、dSYM 和 appcast 验证，再进入该环境的发布 job；候选汇总 job 下载并重新核对两个 DMG 的哈希和 appcast 指向，打包双架构调试符号，生成双架构 Cask，并加入 `Docs/releases/v<version>.md` 的完整发布正文。它同时生成 `candidate.json`，记录版本、构建号、源码提交、工作流与各文件 SHA-256。公开 job 下载这份完整集合、逐文件复核后才创建草稿 Release，全部资产上传成功后将其公开并标记为 latest。

本流程不会由普通 PR 自动创建 Tag 或 Release。明确勾选 `publish` 执行才代表发布授权；仅运行验证或合并代码不等于授权发布。

### 已授权发布的连续执行入口

必要代码审查和实际交互证据复核与 CI 并行完成后，使用已复核的确切 PR 提交调用接力脚本。该命令会合并、公开版本并同步 Homebrew，必须已有本次发布授权；`--publish` 是执行这些外部写入的显式开关：

```bash
python3 script/release.py --pr 123 --reviewed-head <40位PR提交SHA> \
  --version 0.0.3 --publish
```

脚本等待当前提交的检查，通过仓库合并限制后使用 `--match-head-commit` 合入；再固定合并后的源码触发发布。PR 变更、落后主线、未解决评审、失败检查或发布前主线推进都会停止。不能用该参数替代尚未完成的代码和体验判断。

状态和回执写入 `dist/release-flow-<PR>/`，包含检查完成、复核确认、可继续时间、合并、候选完成、公开和渠道完成时间。中断后用同一命令继续：已有合并和同一请求的工作流会被识别，不再创建新的发布。失败的构建可在 Actions 中重跑失败任务；已有完整候选而公开步骤失败时，加 `--candidate-run <原候选运行编号>` 继续。

发布末尾并行核对公开资产、官网双架构下载入口和 Homebrew 原生安装回执。Tap 更新只使用该候选中的 Cask，并校验两种架构实际安装的版本、源码、构建号和严格签名。所有渠道通过才记录发布完成；清理本地产物另行进行。

### 复用已验证候选

在相同源码提交上，给发布工作流传 `candidate_run`，即可跳过两个编译任务并下载原 `release-ready`。验证原运行属于发布工作流、候选汇总成功、两种架构及签名和安装回执齐全、每个文件哈希匹配，再进入公开步骤。`expected_source` 可固定目标提交，避免 ref 移动。候选保留 14 天；过期或输入变化时重新构建。

```bash
gh workflow run release.yml --ref main -f version=0.0.3 \
  -f expected_source=<候选源码SHA> -f candidate_run=<原候选运行编号> -f publish=true
```

公开阶段仍受 `production-release` 环境保护。已有公开资产只允许确认相同字节，不覆盖；草稿可继续上传。候选版本和构建号必须晚于已经交付的上一版本。PR 验收包不能作为候选来源；分支合并生成新提交后，也不能复用旧提交的候选。

只读复核现有公开版本时，可下载 `release-ready` 后执行：

```bash
python3 script/verify_public_release.py <候选目录> --version 0.0.3 \
  --source <候选源码SHA> --output dist/public-verification.json
```

它会下载公开的九项资产和三份 latest 更新清单，与候选哈希、正文、实际标签提交及 latest 状态比较。

每个架构的安装盘、更新清单、调试符号和体积记录从同一目录上传，下载后保持同一层级。`release-ready` 还包含 `release-notes.md`、`candidate.json` 与两种架构体积记录；这些用于发布前复核，公开资产仍以上方清单为准。候选验证运行也执行完整汇总步骤，避免公开时才首次检查文件装配。

两个架构还会在隔离 CI 中调用 Sparkle 自带的命令行更新器，把构建号设为 0 的候选副本更新为最终安装盘中的应用，并重新验证签名、版本和主程序字节。测试副本保留正式公钥；本地更新清单仅修改下载地址，再用正式密钥签名，安装盘字节不变。更新证据 `update-verification-<arch>.json` 与候选哈希对应，另检查修改过的安装盘和清单被验签拒绝。这证明更新引擎的下载和替换链路，不冒充应用内按钮的人机操作。
