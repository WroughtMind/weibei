# 富回答生成式 UI 验收包（离线浏览器）

## 1. 新增文件
本任务仅新增：
- `generate-offline-evidence-package.ts`
- `README_OFFLINE_EVIDENCE_VIEWER.md`
- `fixtures/demo-run/...`（本地验证用例）
- `out/demo-offline-viewer/...`（脚本生成结果，仅作本地验收输出示例）

## 2. 生成命令

```bash
# 从仓库根目录运行
npm exec -- tsx Prototypes/RichAnswerEvidenceViewer/generate-offline-evidence-package.ts \
  --run-dir Prototypes/RichAnswerEvidenceViewer/fixtures/demo-run \
  --output Prototypes/RichAnswerEvidenceViewer/out/demo-offline-viewer \
  --force
```

## 3. 推荐命令（真实 run）

```bash
npm exec -- tsx Prototypes/RichAnswerEvidenceViewer/generate-offline-evidence-package.ts \
  --run-id <runID> \
  --source .build/rich-answer-evidence \
  --output Prototypes/RichAnswerEvidenceViewer/out/<runID>-viewer \
  --force
```

需要浏览 56 题 × 4 轮的大包时，使用支持显式截图路径与节省磁盘模式的生成器：

```bash
npm exec -- tsx Prototypes/RichAnswerEvidenceViewer/generate-evidence-package.ts \
  --run-dir <run目录> \
  --output <验收包目录> \
  --asset-mode symlink \
  --force
```

`--asset-mode` 支持 `copy`、`hardlink`、`symlink`。本机大包优先使用 `symlink`，不会再次复制数百张 PNG；移动或交付到另一台机器时再使用 `copy`。

## 4. 读取输入数据规则
- 读取 `run.json` 与 `index.json`
- 优先读取 `index.records` 中给定的：
  - `recordPath`
  - `requestPath`
  - `replyPath`
  - `validationPath`
- 兼容按目录扫描 `repetition-* / case-*` 回退读取
- 截图查找：`before`、`after` 关键词 + 文件名/目录扫描 `.png`

## 5. 产物说明
- `index.html`：离线浏览主页面
- `viewer.js`：过滤、对比、图文渲染脚本
- `data.json`：脱敏后的证据数据快照（离线可核）
- `assets/*.png`：按 `--asset-mode` 复制、硬链接或符号链接原始截图

## 6. 验证标准（本地）
- 运行 `--force` 生成时，旧目录会被覆盖
- 运行后页面会显示：
  - 总览（40+6+9+1）
  - 默认仅展示 40 个真实富回答，纯文本、诚实降级和非法协议单列为“边界验证”
  - 协议检查、生成式 UI 是否存在、截图是否留档、用户视觉验收四种状态分别展示
  - 状态/学科/形态/轮次过滤，默认展示最新一轮
  - 每题逐条信息（题目材料、原始回复、T1/T2、协议与来源、耗时、失败/修复）
  - 完整窗口、操作前、操作后截图切换与放大查看
  - 选择“全部轮次”后展示轮次差异表
- 明确列出缺失字段（如 request/reply/validation/截图缺失）

## 7. 关键约束提醒
- 脚本是**验收浏览器工具**，不是 Agent 回答里的完整网页。
- `fixtures/demo-run` 是本地测试数据，用于本地验证，不代表真实56题已跑。
- `passed` 仅代表该轮协议/边界检查通过，绝不自动代表生成式 UI 的审美、可读性、学习有效性通过。
- 真实验收需由用户在离线包中确认“待用户验收”后再宣告完成。
