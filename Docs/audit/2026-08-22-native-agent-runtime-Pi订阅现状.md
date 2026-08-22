# 第二棒 · Pi 订阅入口现状（2026-08-22）

命令：`WeiBeiPiCheck --pi-subscription-probe`（隔离空 auth 拉 catalog，再只读本机 auth.json 的 provider 名，不打印 token）。

| 入口 | Pi catalog | 本机已登录 | 本实验口径 |
|---|---|---|---|
| openai-codex / ChatGPT | oauth | 是 | 原生跟：OAuth + Responses |
| anthropic | oauth + apiKey，有 Claude 模型 | 否 | Pi 能登录路径存在；未实测发消息。列入移植清单，实现可后续棒次 |
| github-copilot | oauth + apiKey，有模型 | 否 | 同上 |
| radius | oauth + apiKey，catalog 无 sample models | 否 | 有登录类型、无模型样本；发消息未验证 |

登录+发消息需要用户在浏览器操作，本探测没有代替那一步。
