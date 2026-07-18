# 富回答验收包（离线浏览器）

## 1. 新增文件
本任务仅新增：
- `generate-offline-evidence-package.mjs`
- `README_OFFLINE_EVIDENCE_VIEWER.md`
- `fixtures/demo-run/...`（本地验证用例）
- `out/demo-offline-viewer/...`（脚本生成结果，仅作本地验收输出示例）

## 2. 生成命令

```bash
cd /Users/changfenhuang/.codex/worktrees/rich-answer-protocol/魏碑
node Prototypes/RichAnswerEvidenceViewer/generate-offline-evidence-package.mjs \
  --run-dir Prototypes/RichAnswerEvidenceViewer/fixtures/demo-run \
  --output Prototypes/RichAnswerEvidenceViewer/out/demo-offline-viewer \
  --force
```

## 3. 推荐命令（真实 run）

```bash
node Prototypes/RichAnswerEvidenceViewer/generate-offline-evidence-package.mjs \
  --run-id <runID> \
  --source .build/rich-answer-evidence \
  --output Prototypes/RichAnswerEvidenceViewer/out/<runID>-viewer \
  --force
```

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
- `assets/*.png`：原始截图拷贝（只读本地引用）

## 6. 验证标准（本地）
- 运行 `--force` 生成时，旧目录会被覆盖
- 运行后页面会显示：
  - 总览（40+6+9+1）
  - 状态/学科/形态/轮次过滤
  - 每题逐条信息（题目材料、原始回复、T1/T2、协议与来源、耗时、失败/修复）
  - 操作前/后并排截图
  - 轮次差异表（至少两轮会显示）
- 明确列出缺失字段（如 request/reply/validation/截图缺失）

## 7. 关键约束提醒
- 脚本是**验收浏览器工具**，不是 Agent 回答里的完整网页。
- `fixtures/demo-run` 是本地测试数据，用于本地验证，不代表真实56题已跑。
- 真实验收需由用户在离线包中确认“待用户验收”后再宣告完成。
