<!-- Generated from @changfenhuang/dsh-genui; edit script/build_genui.mjs for host integration. -->
# GenUI — 魏碑常用界面规范

本技能负责判断何时使用界面，以及常用组件的完整调用方法。Webi 的身份、语气、材料引用、记忆和笔记规则继续遵循系统契约；界面只帮助当前回答，不改变任务。

## 先判断：有结构才画，有操作才交互

口诀：纯解释直接说；并列信息用表；数量趋势用图；步骤用流程；确需用户输入再放控件。
两三句话能说清时不要调用 render_ui，也不要把普通回答包进卡片；不要把回答自动改成待办清单、练习或仪表盘，list 只用于真正并列的信息。

## 调用方式

调用 `render_ui`，参数必须含稳定的 `id` 和完整 `spec`；spec 至少有 items，可选 title、gap。
同一界面更新时复用 id，新界面换 id；id 只用小写字母、数字和连字符。
下方 JSON 是工具参数示例，不放进回答正文：

```json
{"id":"concept-compare","spec":{"title":"观点与证据","items":[{"type":"table","columns":["项目","含义"],"rows":[["观点","对事情的判断"],["证据","支持判断的事实或资料"]]}]}}
```

## 内容 → 组件

| 内容 | 组件 |
|---|---|
| 标题、段落、公式、代码 | text |
| 短内容横排或纵排 | row / col |
| 多组同级内容 | grid |
| 明细对照 | table |
| 关键数字、状态、进度 | stat / badge / progress |
| 并列项、键值、提醒 | list / keyvalue / callout |
| 阶段、操作顺序或时间轴 | steps / timeline |
| 简单数量、趋势、占比 | chart |
| 收集输入后继续处理 | input / select / textarea / submit |

## 高频组件规格

- text: `{"type":"text","size":"h1|h2|h3|body|muted|caption","content":"富文本","center":true?}`
- row: `{"type":"row","items":[...],"wrap":true?,"spacer":true?}`
- col: `{"type":"col","items":[...],"gap":8?}`
- grid: `{"type":"grid","cols":2,"items":[...]}`
- table: `{"type":"table","columns":["列"],"rows":[["值"]]}`；只要需要筛选 filter、导出 export、展开明细 details、列类型 types 或联动排序 sortField，无论行数，先加载 genui-advanced。
- stat: `{"type":"stat","label":"指标","value":"42","delta":"+8%","spark":[3,5,4,8]}`
- badge: `{"type":"badge","label":"状态","tone":"success|warn|danger|accent"}`
- progress: `{"type":"progress","label":"进度","value":64,"valueLabel":"64%"}`
- list: `{"type":"list","items":["项目"]}`
- keyvalue: `{"type":"keyvalue","pairs":[{"key":"名称","value":"内容"}]}`
- callout: `{"type":"callout","tone":"info|success|warning|error","title":"提醒","content":"内容"}`
- steps: `{"type":"steps","current":1,"steps":[{"title":"步骤","desc":"说明"}]}`
- timeline: `{"type":"timeline","items":[{"title":"事件","desc":"说明","time":"第 1 天"}]}`
- chart: `{"type":"chart","kind":"bars|line|donut","data":[{"label":"A","value":1}]}`；只做不超过 8 点的快速对比。
- button: `{"type":"button","label":"继续","tone":"primary|danger|success|ghost","action":"continue"}`
- input: `{"type":"input","id":"query","label":"问题","placeholder":"请输入","inputType":"text|email|color"}`
- select: `{"type":"select","id":"choice","label":"选择","options":["甲","乙"],"selected":0?}`
- textarea: `{"type":"textarea","id":"note","label":"补充","rows":3,"value":""}`
- submit: `{"type":"submit","label":"继续","action":"continue"}`；统一提交 fields，不给输入框重复设置 action。

## 富文本与公式

`text.content`、list、table 文本列、`keyvalue.value` 和 callout 支持行内代码、`**粗体**`、`==高亮==`、安全链接、行内公式 `$x^2$` 与独立公式 `$$...$$`；代码块使用 code 组件。只使用用户给出或确认可公开访问的 HTTPS 媒体地址。

## 版式三判据

1. 能否一眼看出主次：标题、正文、辅助说明各司其职。
2. 能否顺着阅读：长表、图表、步骤纵向铺开；row 只放短控件，grid 只并排同级内容。
3. 是否重复：同一信息只选最合适的表达；图看趋势，表查明细，正文不再逐项复述。

## 交互与边界

需要模型处理的 button 或 submit 才设置 action；本地排序、筛选、展开和选择无需逐次请求模型。
action 只是当前会话的互动请求，不代表检索、记忆或笔记操作已经完成；这些仍用原有工具。
用户明确要求自测时才使用题目和判分；不编造进度、掌握程度或材料数据。
不得索取或生成密码、API Key、访问令牌、恢复码等秘密输入。
渲染器报错时按原因修正后重调 render_ui；工具回执只表示已提交，不保证显示正确。

表格只要需要筛选、导出、展开明细、列类型或联动排序，无论行数，或需要 13 种 ECharts 预设、full option、Diagram、Plot、3D 与低频组件时，先调用 `load_skill`，参数 `{"id":"genui-advanced"}`；加载后仍用 `render_ui`。
