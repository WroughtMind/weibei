# 魏碑

本地学习用的 macOS 工作台。

读 HTML / PDF / Markdown，在材料边上写笔记，按**当前资料、选区、笔记**提问。三栏在同一窗口里切换，不把「读 / 记 / 问」拆成三个 App。

界面两套：**纸面**、**墨石**。配色是纸、墨、石青、朱砂。作者做的魏碑风格字体只用在英文品牌字（顶栏、栏目标记、设置里的 Latin 标识等），正文和笔记仍是系统字体。名字借的是书体，产品也按这个方向收——方一点、少一点装饰、回答尽量带出处。

设计稿在 [`DesignReferences/`](DesignReferences/)。

## 功能

| | |
| --- | --- |
| 资料 | 导入 HTML、PDF、Markdown、纯文本 |
| 阅读 | HTML（WebKit）、PDF（PDFKit，连续或单页，`⌘[` / `⌘]`）、Markdown 渲染 |
| 笔记 | 绑当前资料，存本机；Milkdown 原地编辑，可切源码 / 对照 |
| 划线 | 选区浮层带摘录，可写入或替换笔记 |
| 对话 | PI 先读当前材料、选区与笔记并带来源；证据不足时标为未确认 |
| 布局 | 三栏可调；文档笔记对半；沉浸阅读 / 对话 / 写作 |
| Agent | 固定列、抽屉、小窗、划线浮层、静默洞察、隐藏 |
| 键位 | `⌘1`–`⌘4` 聚焦，`⌘B` 资料库，`⌘K` 命令面板 |

沉浸对话：用户句在居中列里右对齐（浅色纸面气泡），助手句按正文排。静默洞察仍是本地提示为主。

## 要求

- macOS 14+
- `swift`（Xcode Command Line Tools）
- 改 Web 编辑器源码时需要 Node.js
- 首次构建需要联网下载并校验固定版本的 PI 独立运行体；用户不需要安装 PI、Node.js 或 Bun

## 运行

```bash
git clone https://github.com/taekchef/weibei.git
cd weibei
./script/build_and_run.sh
```

```bash
./script/build_and_run.sh check
./script/build_and_run.sh package
./script/build_and_run.sh --verify
```

## Agent

魏碑把 PI 当内部学习 Agent，不给它文件、终端或网络工具。PI 每轮只能读取魏碑生成的受限上下文快照；笔记整理只能返回待确认建议，最终写回仍由魏碑和用户决定。

应用内建固定到 `0.80.2` 的 PI macOS 独立运行体，只从自身资源目录启动，不扫描用户的 `PATH`、NVM、Node.js、Bun 或全局 PI。构建脚本按架构下载官方开源产物，先核对 SHA-256，再把最小运行文件、MIT 许可证和来源清单装进应用包。PI 内核以后可替换成我们的源码分支，Swift/RPC 契约无需跟着重写。

PI 在接收问题前不可用时会尝试原有在线接口，再使用离线草稿。已经被 PI 接收的请求若中途失败，不会自动重放，原问题会留在输入框供用户决定是否重试。

魏碑为 PI 建立独立配置目录，只迁入本机已有 PI 的认证信息和默认提供方；全局扩展、技能、提示模板、主题和会话都不会加载。PI 子进程使用环境白名单，不继承宿主里的其他密钥。PI 会话和回答轨迹默认不落盘。

三个内置学习技能：细读与证据核对、Markdown 笔记整理、主动回忆与自测。上下文读取、工具白名单、修订号失效和写回边界由 PI 扩展钩子强制执行。

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `OPENAI_API_KEY` | API Key | 无 |
| `WEIBEI_OPENAI_MODEL` | 模型 | `gpt-5.1` |
| `WEIBEI_PI_PROVIDER` | 指定 PI 提供方 | PI 当前配置；有应用 Key 时为 `openai` |
| `WEIBEI_PI_MODEL` | 指定 PI 模型 | PI 当前配置；有应用 Key 时沿用应用模型 |
| `WEIBEI_PI_THINKING` | PI 思考强度 | `medium` |
| `WEIBEI_PI_DISABLED` | 设为 `1` 跳过 PI | 未设置 |
| `WEIBEI_PI_LIVE_CHECK` | `1` 强制、`0` 跳过真实笔记技能冒烟 | 有可用认证时自动运行 |
| `WEIBEI_PI_EVAL` | 运行细读、笔记、回忆三项真实评测 | 未设置 |
| `WEIBEI_PI_EXECUTABLE` | 仅供 `WeiBeiPiCheck` 指向准备好的内建运行体 | 未设置 |

Key 只在本机。

## 目录

```text
Sources/WeiBei/           App、界面、编辑器资源
Sources/WeiBeiCore/       工作区、Agent、密钥、PDF OCR
  AgentResources/         PI 扩展、系统契约与三个学习技能
Sources/WeiBeiSelfCheck/
Sources/WeiBeiPiCheck/    PI 启动检查与可选真模型冒烟
Sources/WeiBei/WebEditor/ 编辑器源码 → Resources/Editor
Vendor/PiRuntime/         PI 固定版本、哈希、许可证与维护边界
DesignReferences/         纸 / 墨 / 石 / 朱砂参考
script/build_and_run.sh
script/prepare_pi_runtime.sh
```

```bash
swift build
swift run WeiBeiSelfCheck
swift run WeiBeiWebEditorCheck
PI_RUNTIME="$(./script/prepare_pi_runtime.sh)"
WEIBEI_PI_EXECUTABLE="$PI_RUNTIME/bin/pi" swift run WeiBeiPiCheck
WEIBEI_PI_EXECUTABLE="$PI_RUNTIME/bin/pi" WEIBEI_PI_LIVE_CHECK=1 swift run WeiBeiPiCheck
WEIBEI_PI_EXECUTABLE="$PI_RUNTIME/bin/pi" WEIBEI_PI_EVAL=1 swift run WeiBeiPiCheck
```

动布局或对话结构时，把 SelfCheck 里的断言一并改掉。

## 状态

开发中。许可未定；有 `LICENSE` 之前请勿默认可任意再分发。品牌字体（`WeiBeiStele` / `WeiBeiSteleMono`）归作者，随项目使用，不作正文字体。
