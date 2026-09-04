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

App 内的 `WeiBeiArchitecture` 和 `SUFeedURL` 会绑定当前包的真实架构。`WeiBeiDev verify-release-architecture` 会检查主程序、PDF Helper 和 Sparkle 中的全部 Mach-O；主程序与 Helper 必须是单架构原生二进制，嵌套框架至少必须包含目标架构。

两个安装盘共用仓库内固定背景图，只保留安装指引、Webi 和箭头；芯片类型由 DMG 文件名和 App 元数据表达，不在背景图上重复绘制。

## 日常 PR 门禁

`.github/workflows/pr-checks.yml` 保留 Apple Silicon 的既有必需检查，并新增常驻的 `macos-26-intel` job。代码变更在 Intel 上原生编译和运行核心自检；发布链路变更还会打包、实际启动进程、检查签名、元数据、生产卫生和二进制架构，并保留一天的验收包。

如果 GitHub 将来停止提供 Intel 托管 runner，必须先把 `macos-26-intel` 替换为运行受支持 Xcode 的 Intel 自托管 runner，保持 job 名称和所有验收步骤不变；不得跳过 Intel job 后继续发布。

## 正式发布工作流

在 GitHub Actions 中从 `main` 手动运行“魏碑双架构正式发布”，输入与 `VERSION`、`package.json` 和 `Docs/update-summaries/v<version>.md` 一致的版本号。当前发布路线固定使用 ad-hoc 签名，不需要付费 Apple 开发者账号，也不执行 Apple 公证。发布说明和 Cask 必须保留首次启动指引。

工作流要求以下 GitHub Secrets：

| Secret | 用途 |
|---|---|
| `WEIBEI_SPARKLE_PUBLIC_KEY` | 写入 App 并验证更新签名 |
| `WEIBEI_SPARKLE_PRIVATE_KEY_BASE64` | 两个 appcast 的 EdDSA 私钥 |

Sparkle 密钥与 Apple 公证无关。首次公开发布前生成一次正式密钥对：公钥写入 App，私钥放入 GitHub Secret 并保留一份离线加密备份；已有用户后不得随意更换。

仓库应配置受保护的 `production-release` Environment。两个架构先并行完成最终 App 启动、签名结构、DMG、架构、dSYM 和 appcast 验证，再进入该环境的发布 job；发布 job 下载并重新核对两个 DMG 的哈希和 appcast 指向，打包双架构调试符号，生成双架构 Cask，先创建草稿 Release，全部资产上传成功后才将其公开并标记为 latest。

本流程不会由普通 PR 自动创建 Tag 或 Release。执行正式发布工作流本身就是发布授权；合并代码不等于授权发布。
