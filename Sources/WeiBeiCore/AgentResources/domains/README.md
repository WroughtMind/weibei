# Pi extension 领域边界

`../extension.ts` 是 Pi 默认入口，只负责工具注册顺序、单轮状态和生命周期钩子。
领域实现按以下边界维护：

- `agent-contracts.ts`、`context-snapshot.ts`：工具名、快照模型、严格解析、
  来源与学习证据。
- `python-artifact.ts`：隔离 Python 工人的请求、响应、预算和工具注册。
- `rich-answer-component-catalog.ts`、`rich-answer-renderer-registrations.ts`：
  OpenUI 组件目录与专业 renderer 能力注册。
- `rich-answer-schema.ts`：只接受 `schemaVersion: 2` 的外层 Envelope schema。
- `rich-answer-validation-models.ts`、`rich-answer-chart-validation.ts`、
  `rich-answer-spatial-validation.ts`、`rich-answer-render-plan-validation.ts`：
  通用校验模型和各 renderer family 的验证。
- `openui-parser.ts`、`openui-component-semantics.ts`、
  `openui-program-validation.ts`：受控 OpenUI 语法、组件语义和程序校验。

`agent-context.ts`、`rich-answer-catalog.ts`、`rich-answer-validation.ts` 等短文件
只是稳定聚合出口，避免调用方依赖内部文件布局。新增实现应放进具体领域文件，
不能回填到聚合文件或默认入口。
