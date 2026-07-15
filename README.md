# 魏碑

本地学习用的 macOS 工作台。

读 HTML / PDF / Markdown，在材料边上写笔记，按**当前资料、选区、笔记**提问。三栏在同一窗口里切换，不把「读 / 记 / 问」拆成三个 App。

界面两套：**纸面**、**墨石**。配色是纸、墨、石青、朱砂。作者做的魏碑风格字体只用在英文品牌字（顶栏、栏目标记、设置里的 Latin 标识等），正文和笔记仍是系统字体。名字借的是书体，产品也按这个方向收——方一点、少一点装饰、回答尽量带出处。

设计稿在 [`DesignReferences/`](DesignReferences/)。

## 功能

| | |
| --- | --- |
| 资料 | 导入单个文件或整个课程目录；支持 HTML、PDF、Markdown、纯文本 |
| 阅读 | HTML（WebKit）、PDF（PDFKit，连续或单页，`⌘[` / `⌘]`）、Markdown 渲染 |
| 笔记 | 绑当前资料，存本机；Milkdown 原地编辑，可切源码 / 对照 |
| 划线 | 选区浮层带摘录，可写入或替换笔记 |
| 对话 | PI 可检索整个课程的材料、笔记与关联，说明关系并给出可点击的文件、PDF 页或 HTML 章节 |
| 学习 | 记录上次位置、目标、已掌握、困惑和下一步；旧困惑只能凭用户原话或可验证的回忆表现提出结案，用户确认后才落盘且可撤销 |
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
./script/verify_release_metadata.sh --require-clean
./script/build_and_run.sh --verify
```

## Agent

魏碑把 PI 当内部学习 Agent，不给它文件、终端或网络工具。魏碑先索引当前课程里的材料与笔记，再把有界课程目录、关联、相关摘录、学习进度和当前会话交给 PI。PI 只能读取这份受限快照；笔记整理只能返回待确认建议，最终写回仍由魏碑和用户决定。

单个课程目录最多导入 500 个支持文件。PI 通过分页课程地图认识完整文件清单；每轮按用户问题选出最多 80 份相关知识片段，不把整个课程全文一次塞进模型。课程全文索引持久化在本机 SQLite：后台先快速扫完所有文字层和普通文本，再用独立低优先级队列逐页补齐纯扫描页 OCR，包括第 12 页之后的页面。PDF 原生文字层由应用包内单独的受限进程批量提取，每次打开同一份 PDF 处理最多 8 页，并设置内存监测、CPU、输出和超时边界，异常页面不会拖垮主应用；界面线程只读缓存，前台索引每份 PDF 最多尝试 32 页且单份预算 2 秒，整轮同步补索引最多 4 秒，剩余文字页分批在后台续跑。只有已经完成文字层尝试且确认无文字的页才进入 OCR，不会把长教材中尚未扫描到的后续文字页误当成图片页。确认无文字的空白页会记为已检查，截断页和 OCR 失败页会记为终态不完整，只有文件内容变化后才重建，不会在每次提问时永久重试。未完成的索引和只返回局部命中的摘录都会明确标记为不完整；每次提问先轻量核对文件签名，前台最多同步补齐 24 个缺失或真正改过的来源。单个可全文索引的 HTML、Markdown 或纯文本文件上限为 32MB，单页 PDF 最多索引 128K 字；更大的内容仍出现在课程目录，但内容索引明确保持不完整。跨文件检索先保证每份命中材料都有自己的候选片段，避免一本大书挤掉其他关联来源。索引目录使用私有权限；SQLite 主库按连接限制为 768MB，整个索引目录以 1GB 为停止新增写入的预算并为 WAL 留出余量，但不是操作系统磁盘配额。全文与可索引元数据分表保存，写入使用可回滚事务。达到预算时保持“未完成”标记。索引只保存文件标识的哈希，已移出课程的材料会清理并增量回收物理页；导入文件的本机绝对路径进入 PI 上下文前还会再次替换成临时匿名 ID。

应用内建固定到 `0.80.2` 的 PI macOS 独立运行体，只从自身资源目录启动，不扫描用户的 `PATH`、NVM、Node.js、Bun 或全局 PI。构建脚本按架构下载官方开源产物，先核对 SHA-256，再把最小运行文件、MIT 许可证和来源清单装进应用包。PI 内核以后可替换成我们的源码分支，Swift/RPC 契约无需跟着重写。

正式学习对话始终由 PI 处理。PI 启动、提供方或工具失败时，魏碑会明确报错并保留原问题，不会静默降级成不认识课程、记忆和工具的普通对话。静默洞察不属于用户学习会话，仍可在 PI 启动前失败时使用原有有界在线/离线路径。

魏碑为 PI 建立独立配置目录，只迁入本机已有 PI 的认证信息和默认提供方；全局扩展、技能、提示模板、主题和会话都不会加载。PI 子进程使用环境白名单，不继承宿主里的其他密钥。PI 自己的原始会话轨迹不落盘；魏碑持久化完整的用户学习会话，每轮向干净的 PI 运行会话注入最近 20 条消息、受限的更早对话摘录、会话摘要、上次位置和经过证据约束的学习记忆，因此切换材料或重启应用不会把学习连续性交给 PI 的隐藏状态。

五个内置学习技能：学习陪伴、课程关联导航、细读与证据核对、Markdown 笔记整理、主动回忆与自测。六个魏碑专用工具负责读取当前上下文、浏览课程地图、检索课程知识、读取学习记忆、提交学习更新和生成笔记建议。上下文先读、目录不等于读过来源、记忆先读、工具白名单、修订号失效和写回边界由 PI 扩展钩子与 Swift 宿主双重校验。可点击来源也由宿主按完整位置验真：重复文件的条目序号、PDF 页码、HTML 章节序号和章节名必须与本轮工具返回值一致。

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `OPENAI_API_KEY` | API Key | 无 |
| `WEIBEI_OPENAI_MODEL` | 模型 | `gpt-5.1` |
| `WEIBEI_PI_PROVIDER` | 指定 PI 提供方 | PI 当前配置；有应用 Key 时为 `openai` |
| `WEIBEI_PI_MODEL` | 指定 PI 模型 | PI 当前配置；有应用 Key 时沿用应用模型 |
| `WEIBEI_PI_THINKING` | PI 思考强度 | `medium` |
| `WEIBEI_PI_DISABLED` | 设为 `1` 跳过 PI；正式学习对话将明确报不可用 | 未设置 |
| `WEIBEI_PI_LIVE_CHECK` | `1` 强制、`0` 跳过真实笔记技能冒烟 | 有可用认证时自动运行 |
| `WEIBEI_PI_EVAL` | 运行学习陪伴、课程导航、细读、笔记、回忆五项真实评测 | 未设置 |
| `WEIBEI_PI_EXECUTABLE` | 仅供 `WeiBeiPiCheck` 指向准备好的内建运行体 | 未设置 |

Key 只在本机。

## 目录

```text
Sources/WeiBei/           App、界面、编辑器资源
Sources/WeiBeiCore/       工作区、Agent、密钥、PDF OCR
  AgentResources/         PI 扩展、系统契约与五个学习技能
Sources/WeiBeiSelfCheck/
Sources/WeiBeiPiCheck/    PI 启动检查与可选真模型冒烟
Sources/WeiBeiPDFTextWorker/  受限的 PDF 原生文字提取进程
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
