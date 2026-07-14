---
name: weibei-interactive-study
description: 主动判断材料中被纯文字掩盖的学习结构，并把它转成魏碑内建的 28 种安全研习块，例如研习板、关系图、时间线、比较矩阵、测验、图表、函数实验、单位工作台、反应配平、算法跟踪、语言对齐、论证图、视觉分析、空间示意和通路实验。用户明确要求互动，或真实证据呈现观察、预测、核验、比较、反例、迁移或复习机会时使用。
compatibility: 需要 PI 0.80.2、魏碑上下文工具与 weibei-interactive 安全渲染协议。
allowed-tools: weibei_context weibei_course_map weibei_course_search weibei_learning_memory
---

# 魏碑互动研习

## 工作流

1. 第一项动作必须调用 `weibei_context`，确认本轮材料、笔记、选区和 `contextRevision`。
2. 先判断用户想完成的学习动作、材料证据是否够用、正文是否已经足够、是否需要一个主互动；这个判断不需要写出来。
3. 只有跨文件比较、找关联或核对多材料时才调用课程地图与搜索。目录标题不是答案证据。
4. 组件前后只写必要说明；不要再复制一份同内容的静态模板答案。
5. 互动只是正文的一部分。普通 Markdown、公式和可点击来源仍按系统契约输出。
6. 如果没有触发互动，仍要给出充实回答：直接解释、就近标来源、指出缺口或给下一步，不要为了“富回答”硬塞组件。

## 内容层

魏碑的内容语言是“题、引、释、证、辨、练、返”。这些是组织内容的内在层次，不是要展示给用户的固定标题。

| 层 | 作用 | 何时出现 |
| --- | --- | --- |
| 题 | 把用户此刻的问题收窄成一个可回答对象 | 每轮都要在心里完成，正文可直接回答 |
| 引 | 引入当前材料、选区、笔记或搜索片段 | 有事实判断、原文细读或跨材料关系时 |
| 释 | 解释概念、过程、公式、段落或设计选择 | 用户问“是什么 / 为什么 / 怎么理解”时 |
| 证 | 给出可核对来源、数据、原文或步骤依据 | 任何课程内容判断都必须出现 |
| 辨 | 比较、反例、边界、误解、争议或适用条件 | 用户容易混淆，或材料含多个对象/立场时 |
| 练 | 让用户做一次预测、核验、排序、翻卡、调参或配平 | 证据足够且互动能显著降低理解成本时 |
| 返 | 回到阅读、笔记、下一问或复习安排 | 用户需要继续学、整理笔记或巩固时 |

内容组织优先级：先把“题、释、证”讲清；证据和关系足够时加入“辨”；需要亲自操作才更清楚时加入“练”；最后用“返”收束到下一步。不要每次凑齐七层。

本 skill 只决定 `weibei_answer` 中是否放入一个 `weibei-interactive` 主研习块，以及这个块服务哪种学习动作；不得新增字段、组件 `kind`、JSON schema、HTML、JavaScript 或 CSS。

## 主动呈现判断

不要等待用户说出“图表”或“可视化”，但主动不等于高频。读完真实证据后，按以下顺序判断：

1. 先问“用户此刻要做什么”：理解定义、解释原因、比较差异、验证主张、预测结果、复盘记忆、迁移应用、整理笔记，还是只是要一个短答。
2. 再问“证据形状是什么”：数字/单位、公式/步骤、原文/译文、时间/阶段、因果/关系、空间/图像、论证/反驳、状态/条件，还是只有一段普通说明。
3. 再问“用户是否需要动手”：需要先猜、再揭晓、排序、翻卡、调参、核验、对齐或切换状态时，才考虑主互动；只要读正文更快，就不要互动。
4. 最后选择一个最小的语义形状。相邻回答不要机械复用同一构图，但不得为了变化随机选型。
5. 简单定义、寒暄、单句解释、证据残缺、单位冲突、只有目录标题、只有学习记忆、没有课程证据时主动选择纯文字。

有主互动时，回答节奏默认是：一两句直接回答 → 一个主研习面 → 魏碑来源附件。没有主互动时，直接用正文和来源附件回答。主研习面已经表达的信息不要在正文再抄一遍。

## 跨学科认知动作

同一个 `kind` 可以跨学科使用，但认知动作必须不同，不能只替换名词。

| 学科/材料形态 | 优先认知动作 | 常用组件 |
| --- | --- | --- |
| 数学：定义、公式、证明、函数 | 先定位已知，再逐步推导；用反例检查条件；把结论迁移到新题 | `derivation-steps`、`function-plot`、`parameter-lab`、`quiz` |
| 物理：量、单位、实验条件、变量关系 | 先统一量纲，再预测变量变化，最后核验情境结果 | `unit-workbench`、`scenario-lab`、`chart`、`relationship-map` |
| 化学：反应式、守恒、结构、通路 | 先观察两侧物种，再核对守恒或状态切换 | `reaction-balance`、`pathway-lab`、`sequence-builder`、`evidence-board` |
| 计算机：算法、代码片段、状态机、架构 | 手动跑输入，观察状态变化，辨认边界条件 | `algorithm-trace`、`decision-path`、`relationship-map`、`study-board` |
| 语言：原文、译文、术语、语气 | 对齐词句，比较译法，解释语气和术语选择 | `language-aligner`、`text-study`、`annotated-passage` |
| 文学：段落、意象、叙述、修辞 | 先夹批原文，再辨析意象/视角/张力 | `annotated-passage`、`argument-map`、`spectrum`、`text-study` |
| 历史：事件、制度、因果、史料 | 按时间或证据链组织，区分事实、解释和缺口 | `timeline`、`evidence-board`、`relationship-map`、`comparison-matrix` |
| 哲学：概念、命题、前提、反驳 | 拆主张与前提，先给反例，再回到定义边界 | `argument-map`、`decision-path`、`reveal`、`evidence-board` |
| 艺术：图像、构图、风格、观察路径 | 先观察区域，再判断构图、色调和证据来源 | `visual-analysis`、`palette`、`spectrum`、`annotated-passage` |
| 设计：方案、层级、版式、表达目标 | 比较方案对信息层级和任务效率的影响 | `design-compare`、`palette`、`visual-analysis`、`decision-path` |
| 经济：指标、模型、政策、情境 | 比较口径，观察趋势，切换条件并核验结论 | `chart`、`comparison-matrix`、`scenario-lab`、`decision-path` |

## 组件选择

| 学习动作 | 使用组件 | 不适用时 |
| --- | --- | --- |
| 作答后核对 | `quiz` | 没有唯一可核对答案时不用 |
| 先思考再看解释 | `reveal` | 内容不需要延迟揭示时直接写正文 |
| 比较数值、类别或趋势 | `chart` | 数据不完整或单位不一致时不用 |
| 展示已经确认的函数关系 | `function-plot` | 没有公式或可靠采样点时不用 |
| 拖动参数观察关系变化 | `parameter-lab` | 关系不属于内建函数白名单时改用预采样曲线 |
| 比较措辞、论证和改写效果 | `text-study` | 只需要润色一句时直接回答 |
| 比较版式、层级和表达方案 | `design-compare` | 不能由内建预览表达时用文字说明 |
| 研究颜色角色与组合 | `palette` | 颜色与任务无关时不用 |
| 建立一组知识的全貌与层次 | `study-board` | 一两句话能讲清时不用 |
| 追踪概念、证据或因果关系 | `relationship-map` | 关系只有猜测、没有证据时不用 |
| 展示阶段、演变或操作顺序 | `timeline` | 材料没有明确次序时不用 |
| 按统一维度比较多个对象 | `comparison-matrix` | 维度无法对齐时改用正文 |
| 在原文中逐处解释关键词或论证 | `annotated-passage` | 批注词不在原文中时不用 |
| 逐步展开公式、证明或推理链 | `derivation-steps` | 步骤之间没有可靠承接时不用 |
| 复习多组概念、术语或问答 | `flashcards` | 只有一题时优先 `quiz` |
| 让用户亲自排列流程或因果顺序 | `sequence-builder` | 没有唯一可核对顺序时不用 |
| 切换有限条件并观察已确认结果 | `scenario-lab` | 无法预先枚举结果时不用 |
| 核查一个主张的支持、反证和缺口 | `evidence-board` | 只有单一事实、没有论证任务时不用 |
| 比较连续程度、立场或风格位置 | `spectrum` | 对象不构成同一连续维度时不用 |
| 沿条件逐步判断并抵达建议 | `decision-path` | 分支依据没有被证据确认时不用 |
| 换算单位、检查量纲或统一数据口径 | `unit-workbench` | 没有数值和单位时不用 |
| 配平化学反应并检查原子守恒 | `reaction-balance` | 没有反应两侧或元素计数证据时不用 |
| 跟踪算法输入、状态和输出 | `algorithm-trace` | 需要执行未知代码时不用 |
| 对齐原文、译文、术语和语气差异 | `language-aligner` | 没有可配对文本时不用 |
| 拆解论点、前提、反驳和缺口 | `argument-map` | 只有事实罗列、没有论证关系时不用 |
| 分析材料里的图像、画面或标注区域 | `visual-analysis` | 输入是 URL、HTML 或网页时不用 |
| 表达空间方位、层级或结构剖面 | `spatial-layers` | 材料没有方位/层级证据时不用 |
| 切换通路、状态或阶段并观察结果 | `pathway-lab` | 状态和转换无法预先枚举时不用 |

## 学习流程

互动块要服务学习流程，不是展示能力。根据本轮问题选择一条主流程即可。

| 流程 | 内容组织 | 常见组件 |
| --- | --- | --- |
| 渐进揭示 | 先让用户带着问题看，再揭晓解释和证据 | `reveal`、`derivation-steps`、`annotated-passage` |
| 先观察再判断 | 先看原文、图像、数据或状态，再给结论边界 | `visual-analysis`、`chart`、`algorithm-trace`、`evidence-board` |
| 先预测再验证 | 先让用户预测变量、顺序或结果，再用材料核验 | `scenario-lab`、`parameter-lab`、`sequence-builder`、`quiz` |
| 比较与辨析 | 把对象放到同一维度下比较，指出误解和边界 | `comparison-matrix`、`spectrum`、`language-aligner`、`text-study` |
| 反例与边界 | 用一个反例或缺口说明结论不能过度外推 | `argument-map`、`evidence-board`、`decision-path` |
| 迁移应用 | 把已确认规则换到相邻情境，说明哪些条件仍成立 | `scenario-lab`、`decision-path`、`unit-workbench` |
| 复习巩固 | 从材料证据生成可核对的小题或卡片，不声称已掌握 | `flashcards`、`quiz`、`sequence-builder` |

## 安全呈现协议

只能输出 `weibei-interactive` 声明式 JSON 代码块。不得输出原始 HTML，不得输出原始 SVG、JavaScript、事件、CSS、URL 或可执行公式。JSON 是单个对象，文本字段不使用 Markdown。

- 当前协议版本是 `1`；可以省略 `version`，若显式提供则只能写 `"version":1`。
- `source` 使用本轮工具返回的精确跳转；多来源可使用 `sources` 数组。不得改写定位符。
- 一条回答最多一个主互动块。不能连续输出多个 `weibei-interactive` 代码块来凑完整。
- 主动生成必须有课程证据支撑；证据不足时写纯文字，并说明“当前上下文未确认”哪一项。用户明确点名某种组件时，也只能在证据足够时生成，否则解释缺口。
- 所有数组都必须短小。图表最多 4 组，每组最多 48 点；函数曲线最多 4 条、每条最多 80 个预采样点；调节器最多 4 个控制项；对照最多 4 个方案；配色最多 8 色；研习板最多 4 个指标和 6 个条目；关系图最多 7 个节点和 10 条边；时间线最多 8 个事件；比较矩阵最多 4 列和 6 行；夹批最多 8 条；推导最多 8 步；记忆卡最多 10 张；排序最多 8 项；情境实验最多 3 个控制项且每项最多 4 个选项；证据板最多 10 条；光谱最多 8 个点；决策路径最多 10 个节点且每节点最多 4 个选择；单位工作台最多 8 个 `variables` 和 6 个 `checks`；反应配平最多 10 个 `species` 和 12 种元素；算法跟踪最多 12 行 `codeLines` 和 12 个 `steps`；语言对齐最多 8 个 `pairs`；论证图最多 10 个 `nodes` 和 12 条 `edges`；视觉分析最多 8 个 `zones`、5 个 `lenses` 和 8 个 `palette` 项；空间层次最多 5 个 `layers`、10 个 `features`，每个 feature 最多 12 个点；通路实验最多 7 个 `nodes`、8 个 `states` 和 10 条 `edges`。
- `unit-workbench: title, optional question, variables[{id,label,value(字符串),unit,optional role,source}], checks[{id,label,left,right,result,source}], sources`。`value` 必须是字符串。
- `reaction-balance: title, species[{id,label,side reactant/product,coefficient 1...9,atoms 元素->单个分子原子数,source}], sources`。前端只按给定 `atoms` 乘系数，绝不解析 `formula`。
- `algorithm-trace: title, codeLines[string], steps[{lineIndex,summary,optional note,source}], sources`。它只是展示预枚举步骤，不执行 `codeLines`。
- `language-aligner: title, pairs[{label,sourceText,targetText,note,source}], sources`。
- `argument-map: title, optional question, nodes[{id,type premise/claim/objection/reply,label,optional detail,source}], edges[{from,to,optional label}], sources`。`type` 只能是 `premise`、`claim`、`objection` 或 `reply`。
- `visual-analysis: title, zones[{id,label,x,y,width,height,note,tone,source}], optional palette[{label,role,tone}], optional lenses[{id,label,note,zoneIds}], sources`。坐标限 0...100，且 `x + width <= 100`、`y + height <= 100`；禁止 URL、HTML、网页、iframe、img 标签、SVG 字符串和 image src。
- `spatial-layers: title, layers[{id,label,visible}], features[{id,type point/route/region,layerId,label,note,points:[[x,y]...],source}], sources`。坐标限 0...100；没有真实坐标证据时文案必须称“示意图”。
- `pathway-lab: title, nodes[{id,label,detail,source}], states[{id,label,note,activeNodeIds,source}], edges[{from,to,label}], sources`。只允许用户切换预先枚举的 `states`；不得根据用户输入临时生成新状态或运行规则表达式。
- 色调只使用 `cinnabar`、`ochre`、`moss`、`blue-ink`、`violet-ink` 或 `ink`。
- 互动块里的 `source` / `sources` 会并入魏碑回答下方的来源附件并生成点击跳转；正文不要重复生成“相关文件”列表。块外仍使用到的精确跳转继续在回答末尾各自输出独立 `来源：...` 行。

## 基础练习模板

选择题：

````markdown
```weibei-interactive
{"kind":"quiz","prompt":"题目","options":["选项 A","选项 B"],"correctIndex":0,"explanation":"揭晓后显示的解释","source":"来源：工具返回的精确跳转"}
```
````

先想后揭晓：

````markdown
```weibei-interactive
{"kind":"reveal","title":"点开前先回答的提示","content":"揭晓后显示的内容","source":"来源：工具返回的精确跳转"}
```
````

## 数据图表模板

`chartType` 只用 `line`、`bar`、`scatter` 或 `area`。每个点的 `x` 是有限数字或短标签，`y` 是有限数字；单位写在轴标签，不能藏在数值字符串里。

````markdown
```weibei-interactive
{"kind":"chart","title":"指标变化","chartType":"line","xLabel":"时期","yLabel":"百分比","series":[{"name":"指标 A","tone":"cinnabar","points":[{"x":1,"y":2.4},{"x":2,"y":3.1}]},{"name":"指标 B","tone":"ochre","points":[{"x":1,"y":1.8},{"x":2,"y":2.2}]}],"source":"来源：精确跳转"}
```
````

## 函数曲线模板

`formulaLabel` 只用于展示。计算数据必须放进 `points`，魏碑不会执行它。根据已确认公式预采样有限点；遇到不连续位置要断开，不得用极大数伪造竖线。

````markdown
```weibei-interactive
{"kind":"function-plot","title":"平方函数","xLabel":"x","yLabel":"y","xDomain":[-3,3],"yDomain":[-1,10],"curves":[{"name":"平方函数","formulaLabel":"y = x^2","tone":"blue-ink","points":[[-3,9],[-2,4],[-1,1],[0,0],[1,1],[2,4],[3,9]]}],"source":"来源：精确跳转"}
```
````

## 参数实验模板

`family` 只允许内建函数白名单：

- `linear`: `y = ax + b`，参数 `a`、`b`
- `quadratic`: `y = a(x - h)^2 + k`，参数 `a`、`h`、`k`
- `exponential`: `y = a exp(bx) + c`，参数 `a`、`b`、`c`
- `logistic`: `y = L / (1 + exp(-k(x - x0))) + c`，参数 `L`、`k`、`x0`、`c`
- `inverse`: `y = a / (x - h) + k`，参数 `a`、`h`、`k`

每个控制项使用白名单参数键，并提供有限的 `min`、`max`、`step`、`value`。范围应服务教学，不做无意义的大范围拖动。

````markdown
```weibei-interactive
{"kind":"parameter-lab","title":"二次函数调参","family":"quadratic","xDomain":[-4,4],"yDomain":[-4,12],"controls":[{"key":"a","label":"开口 a","min":-2,"max":2,"step":0.5,"value":1},{"key":"h","label":"横移 h","min":-2,"max":2,"step":0.5,"value":0},{"key":"k","label":"纵移 k","min":-2,"max":4,"step":0.5,"value":0}],"source":"来源：精确跳转"}
```
````

## 文本研读模板

`variants` 用于原句、改写或不同论证策略。`highlightTerms` 只放确实值得观察、并且在方案文本里出现的短语。

````markdown
```weibei-interactive
{"kind":"text-study","title":"论证语气比较","variants":[{"label":"原句","text":"原始表达。","note":"需要观察的问题。"},{"label":"收束后","text":"改写后的表达。","note":"具体改变及其作用。"}],"highlightTerms":["关键短语"],"source":"来源：精确跳转"}
```
````

## 设计对照模板

`treatment` 只允许 `editorial`、`annotated`、`compact` 或 `outline`。它们是魏碑内建版式，不是自定义 CSS。

````markdown
```weibei-interactive
{"kind":"design-compare","title":"摘要版式","variants":[{"label":"文稿型","headline":"方案标题","body":"方案正文。","treatment":"editorial","tone":"cinnabar"},{"label":"注释型","headline":"另一个标题","body":"另一个方案。","treatment":"annotated","tone":"moss"}],"source":"来源：精确跳转"}
```
````

## 配色模板

颜色只接受六位十六进制值。每个颜色必须说明名称与用途；`previewText` 使用与任务相关的真实短句。

````markdown
```weibei-interactive
{"kind":"palette","title":"阅读配色","previewText":"用于观察正文与强调色的关系。","colors":[{"name":"纸色","value":"#F1E4CF","role":"底色"},{"name":"墨色","value":"#1D1814","role":"正文"},{"name":"朱砂","value":"#91261C","role":"强调"}],"source":"来源：精确跳转"}
```
````

## 研习板模板

`layout` 决定信息关系：并列主题用 `lanes`，可扫描条目用 `grid`，有推进关系但不是严格时间线时用 `sequence`。`treatment` 只使用 `editorial`、`annotated`、`compact` 或 `outline`。同一内容应按语义选型，不要随机换皮。

````markdown
```weibei-interactive
{"kind":"study-board","title":"本节的三个抓手","summary":"先看目标、机制与检验方式，再回到原文。","layout":"lanes","treatment":"annotated","metrics":[{"label":"核心概念","value":"3 个","note":"都能回到材料核对","tone":"cinnabar"}],"items":[{"kicker":"概念","title":"资金价格","body":"利率描述资金跨期配置的价格。","status":"先理解","tone":"ink","source":"材料：精确跳转"},{"kicker":"机制","title":"通胀扣除","body":"实际利率从名义利率中扣除预期通胀。","status":"再比较","tone":"moss","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 关系图模板

中心概念向外展开用 `radial`，因果或传导方向明确时用 `flow`。节点 `id` 必须唯一；边只能连接已声明节点，不能添加材料没有确认的关系。

````markdown
```weibei-interactive
{"kind":"relationship-map","title":"利率传导","layout":"flow","nodes":[{"id":"reserve","label":"准备金减少","detail":"银行可用资金收缩","tone":"ochre","source":"材料：精确跳转"},{"id":"credit","label":"信贷供给下降","tone":"moss","source":"材料：精确跳转"},{"id":"rate","label":"市场利率上升","tone":"cinnabar","source":"材料：精确跳转"}],"edges":[{"from":"reserve","to":"credit","label":"导致"},{"from":"credit","to":"rate","label":"进而推动"}],"sources":["材料：精确跳转"]}
```
````

## 时间线模板

`events` 按真实顺序排列。`label` 放时期或步骤，`title` 放阶段名称，`detail` 只解释该阶段发生了什么。宽栏横向阅读，窄栏由魏碑自动改为纵向，不需要自定义样式。

````markdown
```weibei-interactive
{"kind":"timeline","title":"政策调整过程","events":[{"label":"第一步","title":"确认目标","detail":"明确需要观察的指标。","tone":"ink","source":"材料：精确跳转"},{"label":"第二步","title":"调整工具","detail":"按目标选择对应工具。","tone":"ochre","source":"材料：精确跳转"},{"label":"最后","title":"复盘结果","detail":"比较目标与市场反应。","tone":"cinnabar","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 比较矩阵模板

`columns` 放 2 到 4 个比较对象；每行 `values` 数量必须与列数完全一致。`emphasisIndex` 只在该维度确有更值得注意的一列时使用，点击列标题可聚焦比较。

````markdown
```weibei-interactive
{"kind":"comparison-matrix","title":"名义利率与实际利率","columns":["名义利率","实际利率"],"rows":[{"label":"是否包含预期通胀","values":["包含","扣除"],"emphasisIndex":1},{"label":"主要用途","values":["观察标示价格","衡量真实资金成本"]}],"sources":["材料：精确跳转"]}
```
````

## 原文夹批模板

`term` 必须逐字出现在 `text` 中，且各批注不要互相重叠。用户点原文标记或旁批时，魏碑会同步高亮并提供精确来源跳转。

````markdown
```weibei-interactive
{"kind":"annotated-passage","title":"这段话的三个落点","text":"名义利率包含预期通胀，实际利率反映扣除预期通胀后的资金成本。","annotations":[{"term":"名义利率","note":"合约或报价直接标示的利率。","tone":"ochre","source":"材料：精确跳转"},{"term":"实际利率","note":"用于观察真实资金成本。","tone":"cinnabar","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 逐步推导模板

每一步只推进一个判断。`statement` 写本步结果，`reason` 写为什么能从上一步走到这里；用户可前后翻阅或一次揭晓。

````markdown
```weibei-interactive
{"kind":"derivation-steps","title":"从名义利率到实际利率","prompt":"先判断预期通胀应当加上还是扣除。","steps":[{"label":"已知","statement":"名义利率同时包含真实回报与预期通胀。","reason":"材料给出的组成关系。","source":"材料：精确跳转"},{"label":"移项","statement":"实际利率约等于名义利率减去预期通胀。","reason":"从名义利率中剔除价格水平预期。","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 记忆卡模板

卡片适合多组一一对应知识。`front` 是回忆提示，`back` 是可核对答案；用户翻面后可标记“再来”或“会了”，这些动作只用于承接下一轮，不自动写入长期记忆。

````markdown
```weibei-interactive
{"kind":"flashcards","title":"两张利率记忆卡","cards":[{"front":"名义利率包含什么？","back":"包含预期通胀。","hint":"想报价中的价格预期。","source":"材料：精确跳转"},{"front":"实际利率主要衡量什么？","back":"真实资金成本。","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 顺序练习模板

`items.id` 必须唯一，`correctOrder` 必须恰好包含全部 id。只有材料确认了唯一顺序时使用。

````markdown
```weibei-interactive
{"kind":"sequence-builder","title":"排出政策观察顺序","instruction":"依次点选下列步骤，再检查。","items":[{"id":"goal","label":"确认目标","detail":"明确观察指标","source":"材料：精确跳转"},{"id":"tool","label":"调整工具","detail":"选择对应政策工具","source":"材料：精确跳转"},{"id":"review","label":"复盘结果","detail":"对照目标与反应","source":"材料：精确跳转"}],"correctOrder":["goal","tool","review"],"successText":"顺序正确。","retryText":"再看每一步的前置条件。","sources":["材料：精确跳转"]}
```
````

## 情境实验模板

情境实验不执行公式或临时生成逻辑。每种选项组合都必须在 `outcomes.selections` 中预先枚举；数组中的数字是对应控制项的选项序号，从 0 开始。

````markdown
```weibei-interactive
{"kind":"scenario-lab","title":"通胀预期变化实验","controls":[{"id":"inflation","label":"预期通胀","options":["保持不变","上升"],"initialIndex":0}],"outcomes":[{"selections":[0],"title":"基准情境","body":"名义利率与实际利率的差额保持材料中的基准关系。","tone":"ink","source":"材料：精确跳转"},{"selections":[1],"title":"差额扩大","body":"在实际利率不变的前提下，名义利率需要反映更高的预期通胀。","tone":"cinnabar","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 证据核验模板

`stance` 只允许 `support`、`challenge` 或 `gap`。证据板围绕一个明确 `claim`，不能把互不相关的摘录堆成列表。

````markdown
```weibei-interactive
{"kind":"evidence-board","title":"核验这个判断","claim":"实际利率比名义利率更适合衡量真实资金成本。","items":[{"stance":"support","title":"扣除预期通胀","detail":"材料明确把实际利率定义为扣除预期通胀后的利率。","tone":"moss","source":"材料：精确跳转"},{"stance":"gap","title":"缺少应用范围","detail":"当前片段没有说明该判断适用于哪些市场条件。","tone":"ochre","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 连续光谱模板

`position` 只能是 0 到 100，用于同一维度上的相对位置，不代表未经材料确认的精确测量值。

````markdown
```weibei-interactive
{"kind":"spectrum","title":"从名义标示到真实成本","axisStart":"报价表面","axisEnd":"真实负担","points":[{"label":"名义利率","position":22,"detail":"直接显示在合约或报价中。","tone":"ochre","source":"材料：精确跳转"},{"label":"实际利率","position":78,"detail":"扣除预期通胀后更接近真实资金成本。","tone":"cinnabar","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 决策路径模板

`startID` 必须指向已声明节点；每个 `choice.nextID` 只能指向其他已声明节点。终点节点使用空 `choices`。不得把模型生成的代码或条件表达式放入分支。

````markdown
```weibei-interactive
{"kind":"decision-path","title":"该看哪一种利率","startID":"goal","nodes":[{"id":"goal","title":"你要观察什么？","body":"先区分报价本身与真实资金成本。","choices":[{"label":"看合约标示","nextID":"nominal"},{"label":"看真实成本","nextID":"real"}],"source":"材料：精确跳转"},{"id":"nominal","title":"看名义利率","body":"使用报价直接标示的利率。","choices":[],"source":"材料：精确跳转"},{"id":"real","title":"看实际利率","body":"使用扣除预期通胀后的利率。","choices":[],"source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

## 跨学科安全模板

这些组件适合材料横跨理科、工科、语言、论证和视觉分析时使用。每个块都必须有 `source` 或 `sources`，来源使用工具返回的精确跳转；没有精确来源时不要生成互动块。

### 单位工作台 `unit-workbench`

- 适用任务：单位换算、量纲检查、统一数据口径。
- 明确触发词：单位工作台、单位换算、量纲检查、unit workbench、unit conversion。
- 主动触发词：问题问“换算 / 单位统一 / 量纲是否对”，且材料含至少两个数值与单位。
- JSON schema：`title`、可选 `question`、`variables[{id,label,value(字符串),unit,optional role,source}]`、`checks[{id,label,left,right,result,source}]`、`sources`。

````markdown
```weibei-interactive
{"kind":"unit-workbench","title":"统一速度单位","question":"36 km/h 是否等于 10 m/s？","variables":[{"id":"speed_kmh","label":"实验速度","value":"36","unit":"km/h","role":"原始量","source":"材料：精确跳转"},{"id":"speed_ms","label":"换算结果","value":"10","unit":"m/s","role":"目标量","source":"材料：精确跳转"}],"checks":[{"id":"dimension","label":"量纲检查","left":"36 km/h","right":"10 m/s","result":"二者都是长度除以时间，且 36 × 1000 ÷ 3600 = 10。","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

### 反应配平 `reaction-balance`

- 适用任务：配平反应式、核对原子守恒、解释系数。
- 明确触发词：反应配平、配平方程、原子守恒、reaction balance、balance equation。
- 主动触发词：问题问“怎么配平 / 是否守恒”，且材料含反应物、生成物和元素计数线索。
- JSON schema：`title`、`species[{id,label,side reactant/product,coefficient 1...9,atoms 元素->单个分子原子数,source}]`、`sources`。前端只按给定 `atoms` 乘系数，绝不解析 `formula`。

````markdown
```weibei-interactive
{"kind":"reaction-balance","title":"氢气与氧气反应配平","species":[{"id":"h2","label":"H2","side":"reactant","coefficient":2,"atoms":{"H":2},"source":"材料：精确跳转"},{"id":"o2","label":"O2","side":"reactant","coefficient":1,"atoms":{"O":2},"source":"材料：精确跳转"},{"id":"h2o","label":"H2O","side":"product","coefficient":2,"atoms":{"H":2,"O":1},"source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

### 算法跟踪 `algorithm-trace`

- 适用任务：手动跑一遍算法、解释循环状态、核对输入输出。
- 明确触发词：算法跟踪、执行跟踪、手动跑一遍、algorithm trace、dry run。
- 主动触发词：问题问“状态怎么变 / 为什么输出这个”，且材料给出输入、步骤和输出。
- JSON schema：`title`、`codeLines[string]`、`steps[{lineIndex,summary,optional note,source}]`、`sources`。只是展示预枚举步骤，不执行 `codeLines`。

````markdown
```weibei-interactive
{"kind":"algorithm-trace","title":"二分查找跟踪","codeLines":["low = 0, high = 3","mid = 1, array[mid] = 3","low = 2, high = 3","mid = 2, array[mid] = 7"],"steps":[{"lineIndex":1,"summary":"第一次比较 3 与目标 7，目标在右侧。","note":"只更新边界，不执行代码。","source":"材料：精确跳转"},{"lineIndex":3,"summary":"第二次比较 7 与目标 7，找到目标。","note":"这是材料中预枚举的跟踪结果。","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

### 语言对齐 `language-aligner`

- 适用任务：原文/译文对齐、术语选择、语气差异、跨语言细读。
- 明确触发词：语言对齐、中英对照、术语对齐、language aligner、parallel text。
- 主动触发词：问题问“这句怎么译 / 术语怎么对应”，且材料含可配对文本。
- JSON schema：`title`、`pairs[{label,sourceText,targetText,note,source}]`、`sources`。

````markdown
```weibei-interactive
{"kind":"language-aligner","title":"术语对齐","pairs":[{"label":"术语 1","sourceText":"real interest rate","targetText":"实际利率","note":"保留经济学术语，不译成真实利率。","source":"材料：精确跳转"},{"label":"术语 2","sourceText":"expected inflation","targetText":"预期通胀","note":"对应公式中的扣除项。","source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

### 论证图 `argument-map`

- 适用任务：拆主张、前提、反驳、证据缺口。
- 明确触发词：论证图、论点地图、前提结论图、argument map。
- 主动触发词：问题问“论证是否成立 / 前提是什么 / 如何反驳”，且材料有主张与理由。
- JSON schema：`title`、可选 `question`、`nodes[{id,type premise/claim/objection/reply,label,optional detail,source}]`、`edges[{from,to,optional label}]`、`sources`。

````markdown
```weibei-interactive
{"kind":"argument-map","title":"核对论证结构","question":"实际利率是否更适合衡量真实资金成本？","nodes":[{"id":"claim_real","type":"claim","label":"实际利率更适合衡量真实资金成本","detail":"这是本段要核验的主张。","source":"材料：精确跳转"},{"id":"premise_inflation","type":"premise","label":"实际利率扣除了预期通胀","detail":"材料给出的主要理由。","source":"材料：精确跳转"},{"id":"objection_scope","type":"objection","label":"适用条件未说明","detail":"当前片段没有给出市场条件边界。","source":"材料：精确跳转"}],"edges":[{"from":"premise_inflation","to":"claim_real","label":"支持"},{"from":"objection_scope","to":"claim_real","label":"限制"}],"sources":["材料：精确跳转"]}
```
````

### 视觉分析 `visual-analysis`

- 适用任务：分析材料里的图片、图中区域、构图、标注和视觉证据。
- 明确触发词：视觉分析、图像分析、看图分析、visual analysis、image analysis。
- 主动触发词：问题问“图中说明什么 / 画面哪里关键”，且本轮材料已经包含图像说明或标注区域。
- 禁止：URL、HTML、网页截图地址、`<img>`、`<svg>`、`iframe`。
- JSON schema：`title`、`zones[{id,label,x,y,width,height,note,tone,source}]`、可选 `palette[{label,role,tone}]`、可选 `lenses[{id,label,note,zoneIds}]`、`sources`。坐标限 0...100，禁止 URL/HTML/image src。

````markdown
```weibei-interactive
{"kind":"visual-analysis","title":"图中证据观察","zones":[{"id":"input","label":"左侧输入端","x":8,"y":30,"width":28,"height":35,"note":"材料标注为输入端。","tone":"blue-ink","source":"材料：精确跳转"},{"id":"output","label":"右侧输出端","x":64,"y":30,"width":28,"height":35,"note":"材料标注为输出端。","tone":"cinnabar","source":"材料：精确跳转"}],"palette":[{"label":"蓝色","role":"输入模块","tone":"blue-ink"},{"label":"朱砂","role":"输出模块","tone":"cinnabar"}],"lenses":[{"id":"flow","label":"流程方向","note":"从输入端观察到输出端。","zoneIds":["input","output"]}],"sources":["材料：精确跳转"]}
```
````

### 空间层次 `spatial-layers`

- 适用任务：空间方位、剖面层次、系统结构和位置关系。
- 明确触发词：空间层次、空间示意、分层示意、spatial layers。
- 主动触发词：问题问“上/下/内/外/层之间关系”，且材料有方位或层级证据。
- JSON schema：`title`、`layers[{id,label,visible}]`、`features[{id,type point/route/region,layerId,label,note,points:[[x,y]...],source}]`、`sources`。无真实坐标证据时文案必须称示意图。

````markdown
```weibei-interactive
{"kind":"spatial-layers","title":"结构层次示意图","layers":[{"id":"outer","label":"外层","visible":true},{"id":"inner","label":"内层","visible":true}],"features":[{"id":"outer_region","type":"region","layerId":"outer","label":"外层边界","note":"材料说明外层包围内部结构。","points":[[12,18],[88,18],[88,82],[12,82]],"source":"材料：精确跳转"},{"id":"core_point","type":"point","layerId":"inner","label":"核心部件","note":"材料说明核心部件位于中心层。","points":[[50,50]],"source":"材料：精确跳转"}],"sources":["材料：精确跳转"]}
```
````

### 通路实验 `pathway-lab`

- 适用任务：信号通路、代谢通路、流程状态、上游/下游影响。
- 明确触发词：通路实验、路径实验、状态切换实验、pathway lab。
- 主动触发词：问题问“激活/抑制/切换后会怎样”，且材料有可预枚举状态。
- JSON schema：`title`、`nodes[{id,label,detail,source}]`、`states[{id,label,note,activeNodeIds,source}]`、`edges[{from,to,label}]`、`sources`。只切换预枚举 `states`。

````markdown
```weibei-interactive
{"kind":"pathway-lab","title":"信号通路状态切换","nodes":[{"id":"upstream","label":"上游信号","detail":"材料中的上游节点。","source":"材料：精确跳转"},{"id":"downstream","label":"下游反应","detail":"材料中的下游节点。","source":"材料：精确跳转"}],"states":[{"id":"baseline","label":"基准","note":"通路保持材料中的默认状态。","activeNodeIds":["upstream"],"source":"材料：精确跳转"},{"id":"activated","label":"上游激活","note":"下游反应增强。","activeNodeIds":["upstream","downstream"],"source":"材料：精确跳转"}],"edges":[{"from":"upstream","to":"downstream","label":"激活"}],"sources":["材料：精确跳转"]}
```
````

## 互动承接

- `weibei_context` 返回的 `interactions` 是本会话刚发生的操作，例如用户选中了哪个证据、排序是否正确、把哪个参数调到什么值。
- 下一轮应自然承接最相关的最近操作，例如解释用户刚选中的证据或对错误排序给针对性提示；不要把操作记录逐条复述成日志。
- 互动记录不是课程内容证据，也不等于掌握。不得仅凭“翻过卡片”“点过会了”或“选中某项”写入长期学习状态。
- 如果用户切换了材料或当前操作与问题无关，忽略这些记录。

## 选型示例

### 触发样例

| 用户场景 | 证据条件 | 选择 | 原因 |
| --- | --- | --- | --- |
| “这三个年度的数值变化说明什么” | 年份、数值、单位完整 | `chart` | 用户要先观察趋势，再判断变化 |
| “为什么 A 会影响 C” | 材料确认 A -> B -> C | `relationship-map` | 因果链比段落解释更容易核对 |
| “这个公式下一步怎么来的” | 每一步都有材料或已给公式支撑 | `derivation-steps` | 适合渐进揭示，避免一步跳结论 |
| “调这个参数会怎样” | 关系属于内建函数白名单，或材料给出有限情境 | `parameter-lab` 或 `scenario-lab` | 让用户先预测再验证 |
| “36 km/h 和 10 m/s 是不是一样” | 数字、单位和换算关系齐全 | `unit-workbench` | 先统一量纲，再核验结果 |
| “这个反应式为什么这样配平” | 反应物、生成物、元素计数明确 | `reaction-balance` | 直接检查两侧守恒 |
| “这段代码为什么输出这个” | 代码行、输入、预枚举步骤齐全 | `algorithm-trace` | 手动跟踪状态，不执行代码 |
| “这句英文怎么译更准确” | 有可配对原文和译文或术语 | `language-aligner` | 对齐词句和语气差异 |
| “这段小说哪里体现讽刺” | 原文短段落足够，关键词可定位 | `annotated-passage` | 先观察原句，再解释修辞 |
| “这个历史判断证据够吗” | 有主张、支持证据和缺口 | `evidence-board` | 区分事实、解释和缺失证据 |
| “这段哲学论证成立吗” | 有主张、前提、反驳或回复 | `argument-map` | 拆出论证骨架和边界 |
| “图里最关键的区域是哪” | 材料含图像说明或可定位区域 | `visual-analysis` | 先观察区域，再判断构图或证据 |
| “两个设计方案哪个更清楚” | 目标、方案文本和比较维度明确 | `design-compare` | 比较信息层级和表达效率 |
| “名义利率和实际利率怎么区分” | 维度可对齐，材料各有定义 | `comparison-matrix` | 适合辨析相似概念 |
| “快帮我复习这一节” | 有多组可核对术语或问答 | `flashcards` 或 `quiz` | 复习要能核对，不代表已经掌握 |

### 不触发样例

| 用户场景 | 处理方式 | 原因 |
| --- | --- | --- |
| “你是谁 / 讲个笑话 / 谢谢” | 纯正文 | 不涉及课程事实 |
| “这句话什么意思”且只有一句定义 | 纯正文加就近来源 | 互动会增加负担 |
| “画个趋势图”但缺数值、年份或单位 | 纯正文说明缺口 | 不补造数据 |
| “比较两个概念”但材料只有一个概念 | 纯正文说明当前上下文未确认另一项 | 不用矩阵伪装完整 |
| 只有目录标题，没有搜索片段 | 先搜索；仍无片段则纯正文说明无证据 | 标题不是内容证据 |
| `isTruncated: true` 且关键步骤在截断外 | 只解释已返回片段 | 截断部分不能推断 |
| 用户要写笔记或整理摘要 | 正文或笔记建议流程，不强行互动 | 目标是写回前的文本组织 |
| 用户刚看过同一种互动，下一问只是追问一句 | 优先纯正文承接 | 避免机械复用构图 |
| 材料是网页、URL 或图片地址，没有图像区域证据 | 不用 `visual-analysis` | 禁止 URL/HTML/image src |
| 用户要求“跑一下代码” | 不执行代码；证据足够时只用 `algorithm-trace` 展示预枚举步骤 | 协议只允许安全展示 |
| 用户让“随便发散一下”且课程证据不足 | 纯正文标明未确认 | 不把常识伪装成材料事实 |
| 一条回答已经有主互动 | 不再追加第二个互动块 | 保持一个主学习动作 |

## 证据边界

- 题目、数据、曲线关系、文本差异和解释只能来自本轮真实证据，或是对该证据明确标注的计算与设计推演。
- `isTruncated: true` 时只能使用已返回片段。
- 无法确认数字、单位、公式或文句时，删掉组件并说明缺失证据；不得补造。
- 创意配色或版式可以是 Agent 提案，但必须明确它是设计建议，不得伪装成材料原文。
