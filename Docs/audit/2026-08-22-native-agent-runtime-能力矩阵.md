# Native 第二棒 · 入口能力矩阵（40）

来源：`AgentProviderID.allCases` + Pi 0.82.1 `baseUrl` 字符串 + `WeiBeiPiCheck --native-provider-matrix`。
命令不打印 token。

覆盖 = 原生工厂能按该入口选出协议族并在有凭证时发请求。未覆盖 = 明确抛 `unsupported_provider`，第四棒报告沿用。

| 入口 | 协议族 | 认证 | 覆盖 |
|---|---|---|---|
| openai-codex | openai-codex-responses | OAuth | 是（六步真验） |
| anthropic | anthropic-messages | API key 或 OAuth | API key 已接；订阅本棒不真验 |
| github-copilot | anthropic-messages | OAuth | 理论可接，本棒不真验 |
| radius | openai-chat-completions | OAuth | 理论可接，本棒不真验 |
| openai | openai-responses | API key | 是 |
| xai | openai-responses | API key | 是 |
| google | google-generative-ai | API key | 是 |
| minimax / minimax-cn | anthropic-messages | API key | 是 |
| vercel-ai-gateway | anthropic-messages | API key | 是 |
| deepseek | openai-chat-completions | API key | 是（三闭环真验） |
| ant-ling / nvidia / groq / cerebras / openrouter | openai-chat-completions | API key | 是 |
| mistral | openai-chat-completions | API key | 是（Pi 用 Conversations；原生走官方 `/v1` 兼容） |
| qwen-token-plan / qwen-token-plan-cn | openai-chat-completions | API key | 是 |
| zai / zai-coding-cn | openai-chat-completions | API key | 是 |
| opencode / opencode-go | openai-chat-completions | API key | 是 |
| huggingface / fireworks / together | openai-chat-completions | API key | 是 |
| kimi-coding / moonshotai / moonshotai-cn | openai-chat-completions | API key | 是 |
| xiaomi 及三个 token-plan | openai-chat-completions | API key | 是 |
| llama.cpp / custom | openai-chat-completions | 用户 Base URL | 是（无 URL 则拒绝） |
| azure-openai-responses | 未覆盖 | — | 否（独立族） |
| google-vertex | 未覆盖 | — | 否（独立族） |
| amazon-bedrock | 未覆盖 | — | 否（bedrock-converse-stream） |
| cloudflare-ai-gateway / cloudflare-workers-ai | 未覆盖 | — | 否（URL 含账号占位） |

真闭环本机有凭证的入口：DeepSeek API key、ChatGPT 订阅（已退出）。其余 API key 未在本机留凭证，不伪造通过。
