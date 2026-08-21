# Pi 行为夹具（第一棒基线）

录制命令：

```
WEIBEI_PI_EXECUTABLE=.build/pi-runtime/0.82.1/darwin-arm64/PiRuntime/bin/pi \
  .build/debug/WeiBeiPiCheck --native-baseline
```

凭证：本机 `~/Library/Application Support/com.changfenhuang.weibei/PiAgent/auth.json` 的 DeepSeek key，运行时拷进隔离目录，不入库。模型 `deepseek-chat` thinking=low。

12 场景对应计划 §5.1；另加 `11/12` 拆成续聊两步。逐条 JSON 含 progress、toolTrace、提案标志、错误分类，不含 token。

## 录到的行为（2026-08-22）

| 场景 | 结果 |
|---|---|
| 01 普通问答 | 通过，答 `4` |
| 02/03/05/13 课程 host 工具 | 模型确实调用了 search/read/map，但 CLI 夹具把 runtime 放在 `/var/folders`，`realpath` 变成 `/private/var/folders`，extension 报「宿主工具响应根目录发生了变化」。这是 Pi 现有护栏 + macOS 临时目录符号链接，不是课程内容问题。App 数据目录路径不受影响。 |
| 04 学习记忆 | 调用 `weibei_learning_memory`，读到期限结构 |
| 06 笔记建议 | `hasNoteProposal=true`；关系建议调用了但未落 reply 字段 |
| 07 可视化 | 先 `read` visualize Skill，再 `weibei_visualize` |
| 08 图像 | 模型调用了 `weibei_visual_asset`，1×1 PNG 未进入本轮 envelope 的可观察集 |
| 09 取消 | `failureKind=cancelled`，progress 停在 preparing |
| 10 无效 key | 0.6s 失败；Pi 把坏 key 标成 `generic` 而非 `unauthorized`（对拍时要记） |
| 11/12 续聊 | 第二问不再搜索，记得「资金价格」 |

原生引擎三闭环不经 Pi host 目录，见 `--native-engine-smoke` / `--native-deepseek-smoke`。
