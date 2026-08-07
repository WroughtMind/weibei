# 内置 Pi 统一认证、模型与请求计划

关联议题：#143

## 目标

魏碑只启动安装包内由 Bun 编译的固定 Pi 二进制。OAuth、API Key、凭证刷新、登出、提供商目录、模型目录和生产模型请求统一经过这份内置 Pi；用户电脑不需要安装 Node、Bun 或全局 Pi。

魏碑继续负责课程、材料、选区、笔记、来源、写回和界面。Pi 不接管这些产品数据。

## 实现边界

- 复用 Pi 公共 `ModelRuntime` 的 `login`、`logout`、认证状态和模型目录能力，不复制任何厂商 OAuth。
- 通过魏碑已加载的 Pi 扩展注册结构化认证命令；Swift 使用现有 RPC 扩展交互通道接收授权网址、进度、输入请求、取消和结果。
- API Key 与 OAuth 凭证只保存在魏碑自己的 Pi `auth.json`，目录 `0700`、文件 `0600`。
- 认证数据变化后只重启内置 Pi 子进程，不重启魏碑 App。
- 删除外部 Node 探测、独立 OAuth 脚本、独立 API Key 文件、跨提供商密钥环境变量注入和魏碑自建模型目录请求。
- 保留自定义 OpenAI 兼容端点所需的 Pi `models.json`；其余内置提供商与模型元数据以 Pi 为准。
- 正式产品的模型请求统一经过 Pi；离线确定性运行时只保留在自检目标中。

## 不采用

- 不要求用户安装 Node、Bun 或 Pi。
- 不额外引入钥匙串。
- 不模拟 Pi 交互终端按键。
- 不通过私有字段访问 Pi 运行时。
- 不维护第二套 OAuth、提供商或模型目录实现。

## 共享文件占用

负责人任务：`codex/pi-unified-runtime`。

等待 PR #144 释放后接续占用：

- `Sources/WeiBei/Stores/WorkspaceStore.swift`
- `Sources/WeiBeiSelfCheck/main.swift`
- `Package.swift`（仅在验证目标确需调整时）
- `script/`（仅在打包检查确需调整时）

在 PR #144 释放前，本任务不修改以上共享位置。其他主要改动位于 Pi RPC、Pi 运行时、认证服务、凭证配置、模型目录和设置界面。

预计释放条件：构建与自检通过；无 Node/Bun 的候选 App 完成 OAuth、API Key、模型加载、真实 Pi 回答、重开连续性及失效凭证恢复验收；草稿 PR 写清合并风险并交给整合任务。

## 验收

- 没有安装 Node/Bun 的干净环境可完成 OpenAI Codex 与 Anthropic OAuth。
- API Key 登录与 OAuth 登录都由 Pi 执行，并写入同一份魏碑 Pi `auth.json`。
- 登录进度、授权网址、输入、取消、成功和错误均为结构化事件。
- 登录后无需重启 App 即可获取模型并完成一次真实 Pi 回答；退出重开后仍可继续使用。
- 失效或重复使用的刷新令牌停止重试，并明确进入重新登录状态。
- 正式 App 不包含 `pi-oauth-login.mjs`，不查找 Node/Bun/全局 Pi，不把 API Key 注入子进程环境。
- 提供商与模型目录来自 Pi；正式模型请求不存在绕过 Pi 的直连回退。
