# 模型服务账号登录

魏碑沿用现有模型适配器和本地凭据文件，新增 Grok、Kimi Code、OpenRouter 账号授权。设置中的“账号登录”与“API 密钥”互斥，不会在缺少所选凭据时改用另一种凭据。Webi 授权结果页支持中文、英文、深浅色与窄屏。

| 服务 | 授权方式 | 模型请求地址 | 凭据生命周期 |
| --- | --- | --- | --- |
| ChatGPT | 浏览器授权码 + PKCE | 既有 Codex 后端 | 既有刷新流程 |
| Grok | 官方设备授权码 | `https://api.x.ai/v1` | 到期前刷新，保留或轮换刷新令牌 |
| Kimi Code | 官方设备授权码 | `https://api.kimi.com/coding/v1` | 到期前刷新，保留或轮换刷新令牌 |
| OpenRouter | 浏览器授权码 + PKCE | `https://openrouter.ai/api/v1` | 用户控制的密钥，无刷新令牌；使用 OpenRouter 余额 |

账号授权完成后，先访问服务商的模型目录或当前密钥信息，再保存凭据并显示连接成功。这验证账号凭据被接口接受，不代表每个模型均可调用，也不代表账户拥有无限额度。失败时不写入新凭据。设备码不包含令牌；本地结果页只返回状态，不展示账号或凭据。

设备授权遵守服务商的轮询间隔、减速指令和有效期。取消操作立即停止等待；迟到的续期结果不能恢复已退出的账号。授权请求不跟随重定向，验证链接只允许服务商的 HTTPS 域名。结果监听器仅绑定本机回环地址，使用随机端口及随机状态校验。

## 接入依据与边界

- Grok：[xAI 官方认证说明](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/02-authentication.md)、[Pi 当前 xAI 授权实现](https://github.com/earendil-works/pi/blob/main/packages/ai/src/auth/oauth/xai.ts)。使用其公开设备客户端标识，不发送伪装 CLI 身份的请求头。
- Kimi Code：[官方 CLI 授权实现](https://github.com/MoonshotAI/kimi-cli/blob/main/src/kimi_cli/auth/oauth.py)、[官方服务地址](https://www.kimi.com/code/docs/en/kimi-code-cli/configuration/env-vars)。使用公开设备客户端标识。
- OpenRouter：[官方 PKCE 文档](https://openrouter.ai/docs/guides/overview/auth/oauth)、[当前密钥信息接口](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key)。本地回调支持任意端口；授权界面显示本机回调地址，密钥标签为 WeiBei。
- Copilot 暂未新增账号登录：[GitHub 官方接入流程](https://docs.github.com/en/copilot/how-tos/copilot-sdk/setup/github-oauth)要求注册自己的授权应用。仓库没有魏碑的客户端配置，因此没有复用其他产品的授权应用；保留既有手动凭据入口。
- Gemini、Claude、Qwen 等未在本次新增账号授权入口；没有为它们放置不能完成登录的按钮。

## 验证范围

2026-09-17：Grok、Kimi 官方设备授权端点均实测返回 HTTP 200，授权域名分别为 `accounts.x.ai`、`www.kimi.com`，服务端返回 1800 秒有效期和 5 秒轮询间隔。该探测没有登录用户账号，未保存或展示设备令牌。

自动测试覆盖设备轮询/减速/拒绝/过期、链接及响应校验、PKCE 交换、续期并发和退出竞态、账号与密钥分离、模型路由、本地随机端口和 Webi 多服务/多语言结果页。真实账号授权、实际模型回答及账单归属仍需相应账号端到端验证；编译和模拟测试不能替代这一项。

本地验证结果：`swift test --filter 'ProviderOAuthTests|OAuthCallbackPageTests|NativeAgentRuntimeTests|AgentEndpointSecurityTests'` 60 项通过；Mac Catalyst Debug arm64 构建通过；三个新增服务的中英文窄屏页面检查通过，截图未发现横向溢出或缺失图片。构建未安装或运行，尚未合并、发布。
