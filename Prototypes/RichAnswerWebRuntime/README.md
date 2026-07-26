# 魏碑富回答网页运行时

这里是魏碑 App 内嵌富回答网页运行时的生产真源。它用
`@openuidev/react-lang` 承载“OpenUI 受控生成协议 + 魏碑深学习组件 +
通用组合原语”，构建产物同步到 `Sources/WeiBei/Resources/rich-answer*`。
App 资源目录中的三个文件是生成物，不是可手工修改的真源。

## 跨学科压力样例

下面十二题只是早期压力样例，不是“黄金内核”、固定模板或能力上限。正式能力还包括模型可组合的函数、数据、步骤、论证、因果、坐标、平衡、空间图层、分布刷选、依赖传导，以及 T2 通用原语树；参考库应持续扩充。

| 分组 | 场景 | 主互动 |
| --- | --- | --- |
| 自然科学 | 数学两点直线、物理受力运动、化学动态平衡、生物染色体分离 | 拖点、拖矢量、投入扰动、阶段编排 |
| 文史图像 | 原文论证、历史因果、地理空间、艺术观察 | 逐句点读、聚焦路径、切层定位、移动观察镜 |
| 数据社会 | 统计抽样、金融现金流、经济政策、代码执行 | 刷选、编辑单元格、追证据链、前后步进 |

组件内部负责真实计算和联动；模型只选择最适合的认知工具并提供材料与参数。

## 运行命令

```bash
cd Prototypes/RichAnswerWebRuntime
npm ci
npm run dev
```

构建和本地预览：

```bash
npm run build
npm run serve
```

运行类型检查、Vitest 和内嵌产物漂移检查：

```bash
npm run check
```

把当前源码构建并同步到魏碑 App 的内置资源：

```bash
npm run build:embed
```

App 验收前必须使用这个命令，避免本地原型源码与 App 内实际运行的资源版本不一致。

`npm run check:embedded` 只比较生成物，不会改写工作树。

Pi 默认入口仍是 `Sources/WeiBeiCore/AgentResources/extension.ts`，它只保留
工具编排和生命周期。上下文快照、Python 受控计算、能力目录、Envelope schema、
专业 renderer 校验和 OpenUI parser/semantics 位于相邻 `domains/` 模块。
`npm run check:agent-extension` 会聚合这些文件做结构类型检查、v2-only 检查、
入口行数门禁和完整 bundle 检查。

## 协议版本

Rich Answer 外层 Envelope 只接受 `schemaVersion: 2`；缺失版本、v1 和未知
版本都必须由宿主拒绝，不提供兼容回退。`weibei.openui.v1`、各 renderer 的
`specVersion` 以及受控 Python 计算工人 v1 是彼此独立的内部协议，不属于这次
外层 Envelope 版本删除。

## 旧场景开发画廊

```text
/legacy.html?case=math-line
/legacy.html?case=physics-force
/legacy.html?case=chem-equilibrium
/legacy.html?case=biology-meiosis
/legacy.html?case=text-argument
/legacy.html?case=history-causality
/legacy.html?case=geography-map
/legacy.html?case=art-observation
/legacy.html?case=statistics-sampling
/legacy.html?case=finance-cashflow
/legacy.html?case=economics-policy
/legacy.html?case=code-sort
```

## 生产与开发边界

- `index.html`、`src/main.tsx` 和 `src/app.tsx` 是唯一生产入口。
- `src/dev/legacy-main.tsx` 与 `legacy.html` 只供本地回归，不在生产
  Rollup 入口的依赖图中；使用 `npm run dev:legacy` 打开。
- `*.test.ts` 只由 Vitest 加载，不进入生产 bundle。
- renderer 的 schema、解析、状态计算放在 `*.domain.ts`，React renderer
  只依赖这些生产领域模块，不再反向依赖 `*.self-check.ts`。
- package 依赖写死或受 lockfile 约束，确保 CI 与本机可复现。
- 十二个旧 URL 只属于开发画廊，不是产品协议或能力上限。
- 任意 HTML/JavaScript 的沙盒路线留在架构决策文档，不作为产品默认入口。
- 运行时没有持久化和远端接口；网络访问由宿主协议与渲染预算禁止。
