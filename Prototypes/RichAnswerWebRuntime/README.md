# 魏碑富回答网页运行时原型

这是魏碑内置的富回答网页运行时及本地验收台，用真实 `@openuidev/react-lang` 承载“OpenUI 受控生成协议 + 魏碑深学习组件 + 通用组合原语”。它不导入 OpenUI 默认组件库，也不把能力封死在少数固定案例里。

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
cd /path/to/weibei
nvm use
npm ci
cd Prototypes/RichAnswerWebRuntime
npm run dev
```

依赖由仓库根 npm workspace 统一安装；本目录不再维护独立安装结果或 lockfile。

构建和本地预览：

```bash
npm run typecheck
npm run test
npm run build
npm run serve
```

一次运行类型检查、单元测试和生产构建：

```bash
npm run check
```

只运行现有 renderer 行为自检：

```bash
npm run self-check
```

把当前源码构建并同步到魏碑 App 的内置资源：

```bash
npm run build:embed
```

App 验收前必须使用这个命令，避免本地原型源码与 App 内实际运行的资源版本不一致。

## URL 参数

```text
/?case=math-line
/?case=physics-force
/?case=chem-equilibrium
/?case=biology-meiosis
/?case=text-argument
/?case=history-causality
/?case=geography-map
/?case=art-observation
/?case=statistics-sampling
/?case=finance-cashflow
/?case=economics-policy
/?case=code-sort
```

## 当前边界

- package 依赖写死版本，方便复现这次判断。
- 当前入口验证 `@openuidev/react-lang` 自定义组件库能否承载多学科深组件和新组合程序；十二个旧 URL 只是回归入口。
- 任意 HTML/JavaScript 的沙盒路线留在架构决策文档，不作为产品默认入口。
- 没有持久化、没有远端接口、没有安全策略完备性。
