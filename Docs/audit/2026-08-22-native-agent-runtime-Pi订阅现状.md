# 第二棒 · Pi 订阅入口现状（2026-08-22）

命令：`WeiBeiPiCheck --pi-subscription-probe`（隔离空 auth 拉 catalog，再只读本机 auth.json 的 provider 名，不打印 token）。

ChatGPT 订阅六步已在本机真账号跑通（登录 → 发消息 → 课程工具 → 中途取消 → 强制刷新 → 退出无残留，含 `.bak` 擦除）。

用户 2026-08-22 指示：Anthropic / Gemini / Copilot / Radius **订阅**按 Pi 同一套 OAuth 接入逻辑，理论上可接，本棒**不再做人登录 + 发消息真验**。API key 入口继续做。

| 入口 | Pi catalog | 本机已登录 | 本实验口径 |
|---|---|---|---|
| openai-codex / ChatGPT | oauth | 六步已真验后已退出 | 原生已跟：OAuth + Responses。六步通过。 |
| anthropic | oauth + apiKey，有 Claude 模型 | 否 | 订阅：跟 ChatGPT 同模式，本棒不真验。API key：Messages 族已接。本机无官方 Anthropic key，未做三闭环。 |
| github-copilot | oauth + apiKey，有模型 | 否 | 订阅：跟 ChatGPT 同模式，本棒不真验。OAuth 实现可后续棒次。 |
| radius | oauth + apiKey，catalog 无 sample models | 否 | 订阅：跟 ChatGPT 同模式，本棒不真验。OAuth 实现可后续棒次。 |
| google Gemini | apiKey | 否 | 原生已接 `streamGenerateContent`。本机无 Gemini API key（环境里的 `ya29` 是 Google OAuth 令牌，不当作 API key 冒充通过）。 |

Gemini 没有 Pi `/login` 订阅入口；上表「Gemini」按用户口头并列，按 API key 族处理。
