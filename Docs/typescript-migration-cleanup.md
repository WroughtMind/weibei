# TypeScript 迁移遗留清理

## 目标

本任务清理 JavaScript 迁移到 TypeScript 后遗留的类型噪声，在不改变现有产品行为和证据格式兼容范围的前提下，让类型直接表达模块契约和领域数据。

## 范围

- 统一两套富回答证据生成器使用的输入 schema、旧字段兼容适配和规范化模型。
- 为 WebEditor feature、WebKit 消息和公开编辑器 API 建立显式契约。
- 移除仅用于绕过 TypeScript 控制流分析的非空断言和可变状态盒。
- 使用 Node 命令行参数解析能力替代数组索引断言。
- 将缺少上游声明的第三方类型移出业务脚本，并复用依赖已经提供的类型。

## 兼容边界

本次仍接受当前证据生成器已支持的历史字段别名和宽松 JSON 输入。兼容逻辑只保留在输入适配层；进入规范化模型后，生成器不再重复判断旧字段形态。

本次不修改 Swift 业务逻辑、Rich Answer 协议语义或生成页面的展示内容。

## 技术选择

- 证据输入继续使用项目已有的 Zod，通过共享 schema 的 `parse` / `safeParse` 同时完成运行时校验和 TypeScript 类型推导。运行时 JSON 边界需要真实校验，仅增加手写类型不能替代该能力；安装命令为 `npm install --save-dev --save-exact zod@4.4.3`。
- 命令行参数使用 Node.js 内置的 `util.parseArgs`。参数解析较简单，内置 API 已覆盖别名、布尔值、必填值和未知参数校验，不需要再引入 CLI 框架。
- Prism token 直接使用 `@types/prismjs` 提供的 `Prism.Token` / `Prism.TokenStream`；`appdmg` 没有发布类型声明，因此只在 `script/dmg/appdmg.d.ts` 提供最小模块边界，业务脚本不再维护第三方 API 的镜像接口。

## 代码结构

- `Prototypes/RichAnswerEvidenceViewer/evidence-contract.ts` 是两套证据生成器唯一的输入兼容与领域类型来源。
- `Sources/WeiBei/WebEditor/src/types.ts` 定义 WebKit 消息、公开编辑器 API 和共享数据结构；各 feature 暴露具名接口。
- CLI 入口与参数解析分离，参数解析可以在 Vitest 中直接覆盖，导入模块不会触发脚本执行。

## 验证要求

- TypeScript 类型检查、ESLint 和 Vitest 全部通过。
- WebEditor 和证据生成器的已有测试全部通过，并为共享适配层和命令行缺值补充覆盖。
- 编辑器、OAuth、官网和 Rich Answer 生成资源可重复构建，生成物验证通过。
