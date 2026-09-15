<!-- Generated from @changfenhuang/dsh-genui; edit script/build_genui.mjs for host integration. -->
# GenUI — 魏碑界面组件规范

本技能只说明界面组件的规格和呈现方式。Webi 的身份、交流方式、回答长短、材料检索、引用、学习记忆和笔记写入继续遵循系统契约与现有工具。界面文案跟随用户要求的语言，字段名、组件类型、id 和 action 保持原样。是否使用组件取决于它能否帮助回答当前问题，不按回答行数或组件数量强制使用。

围绕当前阅读、整理或讨论选择组件。只有用户明确要求练习、自测或探索参数变化时，才安排题目、判分或调参控件；不要把解释自动改成做题，不编造学习进度和掌握程度。

## 调用方式

调用 `render_ui` 将组件插入当前回答，参数包含稳定的 `id` 和完整组件树 `spec`；spec 必须含 items，可选 title 和 gap。下文 JSON 示例都是工具参数，不作为回答正文输出。文字可以自然穿插在工具调用前后。

调用 `render_ui`，参数示例：

```json
{"id":"concept-comparison","spec":{"title":"观点与证据","items":[{"type":"table","columns":["区别","观点","证据"],"rows":[["作用","说明作者的判断","支撑判断的事实或资料"],["例子","这本书适合入门","前两章使用了生活中的例子"]]}]}}
```

- 同一条回答中用相同 id 更新原界面，用不同 id 插入另一块界面；id 只使用小写字母、数字和连字符。
- action 由魏碑转成当前会话中的互动请求。需要检索、记忆或笔记操作时，Webi 继续使用原有工具；按钮被点击不代表相关操作已经完成。
- 显示引擎随魏碑安装，按组件需要加载；只使用用户给出或已确认可公开访问的 HTTPS 图片、音视频地址。

富文本字段（text、list、table 文本单元格、keyvalue.value、callout）支持 `$E=mc^2$` 行内公式与 `$$\\frac{a}{b}$$` 独立公式。JSON 中的反斜杠必须写成 `\\`；代码片段内的美元符号保持字面值。公式由宿主 KaTeX 渲染，不执行 HTML 或脚本。

## 组件词汇（先列常用类型，完整规格见后文）

布局：`text` `row` `col` `grid` `card` `divider` `spacer`
展示：`stat` `badge` `progress` `list` `table` `keyvalue` `avatar` `image` `audio` `video` `timeline` `file-tree` `breadcrumb` `diff` `json` `code` `callout` `steps`
图表：`chart`（bars/line/donut，可多序列）`plot`（数学函数图）`echart`（ECharts 全功能图表）
交互：`button` `input` `select` `checkbox` `radio` `switch` `textarea` `tabs` `accordion` `copy`

### 布局
- text: `{"type":"text","size":"h1|h2|h3|body|muted|caption","content":"...","center":true?}`
- row / col: `{"type":"row"|"col","items":[...],"wrap":true?,"spacer":true?,"gap":n?}`
- grid: `{"type":"grid","cols":n,"items":[...]}`
- hero: `{"type":"hero","title":"...","subtitle":"...","value":"99.96%","label":"可用率","delta":"+0.02%","spark":[...],"tone":"accent|success|warning|danger"}` — **封面块**：eyebrow + 突出数字（字号跟随魏碑主题，带入场计数）+ 标题 + 副标题 + tone 渐变底色。**一条回答最多用一个**，放在最前面当视觉锚点
- span: 任意节点都可加 `"span":2`（grid 子节点占几列）——bento 排版的唯一原语：一张 `span:2` 宽卡配一张窄卡，比一列方块堆下去好看得多
- card: `{"type":"card","title":"...","items":[...]}`；`"accent":"#f59e0b"` 指定强调色（边框 + 标题 + 极淡底色）
- palette: `chart` / `echart` 都支持 `"palette":["#ff8800","#3ecf8e"]` 覆盖分类色板（默认跟随宿主主题）。**只有语义上需要指定颜色时才写**（成本=红、收益=绿），否则跟随主题更稳；`"tone":"info|success|warning|danger"` 给卡片底色（用于结论卡/风险卡）
- divider: `{"type":"divider"}`; spacer: `{"type":"spacer"}`

### 展示
- stat: `{"type":"stat","label":"...","value":"...","delta":"+12.4%|-3%"}`（`-` 开头自动红、`+` 绿）；可选 `"spark":[3,5,4,8,6]` 画一条微趋势线（2–60 个有限数值）；`"size":"hero"` 渲染超大数字（一条回答最多用一次，作为视觉锚点）
- badge: `{"type":"badge","label":"...","tone":"success|warn|danger|accent","icon":"emoji?"}`
- progress: `{"type":"progress","label":"...","value":0-100,"valueLabel":"70%"}`；`"variant":"ring"` 画环形进度，`"target":70` 在轨道上标出目标刻度
- avatar: `{"type":"avatar","name":"...","color":"#hex?"}`
- image: `{"type":"image","src":"https://example.com/result.png","alt":"结果图片"}` — 展示浏览器可访问的 HTTPS 图片地址；懒加载；不支持 `file:`/`data:` 等本地或主动协议
- audio: `{"type":"audio","src":"https://example.com/result.mp3","alt":"语音结果","loop":true?}` — 原生控制条；用户主动播放，不自动播放；仅已确认的 HTTPS 地址
- video: `{"type":"video","src":"https://example.com/result.mp4","alt":"视频结果","poster":"https://example.com/poster.jpg"?,"loop":true?,"muted":true?,"aspectRatio":"16:9|4:3|1:1|9:16"?}` — 原生播放/音量/全屏控制；不自动播放
- list: `{"type":"list","items":["..."] 或 [{"title":"...","desc":"..."}] 或嵌套节点(如 {"type":"badge","label":"TS"})}` — 行内可嵌节点（计入节点预算）
- table: `{"type":"table","columns":["..."],"rows":[["...","..."]],"types":["text|num|delta|bar|badge"]?,"details":[[...]]?,"total":true?}` — 表头点击本地排序（升/降/还原，零往返）；数值感知：千分位（`1,234`）、`k/m/b`、`万/亿`、`%`、货币符号都能按真实数值比较，纯数值列自动右对齐；**带符号单元格自动着色**（`+12.4%` 绿、`-3` 红，无需额外字段）；`types` 可按列指定 `bar`（0-100 内联进度条）、`ring`（0-100 小环）、`spark`（单元格写 `"3,5,4,8"` 画微趋势线）、`badge`（胶囊标签）、`delta`（强制涨跌色）、`num`（强制右对齐）、`index`（行号）、`group`（首列当分组标题：该行只有第一格有内容时渲染成跨列小标题）；`"total":true` 追加合计行（数值列自动求和）；**`"export":true`**：表格上方出现「复制 Markdown / 复制 CSV」两个小按钮（纯本地剪贴板，不发请求）；**`"filter":"输入框id"`**：把表格和某个 input/select 绑定，读者输入即时过滤（`filterColumn` 可限定列）——数据多时**默认就该配一个**；**`"sortField":"下拉id"`** 用下拉的值（列名）排序；**`"details"` 与 rows 同序**，第 i 项是该行展开后的内容（可放任意组件，`null` = 该行不可展开）——首列出现 chevron，点开在整行下方展开明细，适合「主表 + 明细」
- keyvalue: `{"type":"keyvalue","pairs":[{"key":"...","value":"..."}]}`
- timeline: `{"type":"timeline","items":[{"title":"...","desc":"...","time":"..."}]}`
- file-tree: `{"type":"file-tree","items":[{"name":"...","type":"file|dir","children":[...]?}]}` — 目录行可点击折叠/展开（本地，零往返）
- breadcrumb: `{"type":"breadcrumb","items":["首页","设置","账户"]}`
- diff: `{"type":"diff","diffs":[{"path":"...","oldText":"..."|null,"newText":"..."}]}`
- json: `{"type":"json","value":...}`（JSON 树查看器）
- code: `{"type":"code","lang":"ts","code":"..."}`
- callout: `{"type":"callout","tone":"info|success|warning|error","title":"...","content":"..."}`
- steps: `{"type":"steps","current":n,"steps":[{"title":"...","desc":"..."}]}`

### 图表
- chart: `{"type":"chart","kind":"bars|line|donut","data":[{"label":"...","value":n,"color":"#hex?"}],"series":[{"label":"...","data":[...]}]?,"horizontal":true?}` — bars 默认；line 趋势；donut 占比；**series：bars 是分组柱，line 是多序列折线**；**`horizontal:true` 画横向柱**（排行/长标签首选）；**`stacked:true` 把 series 堆叠**（构成/占比随时间）；堆叠段够高时数值直接印在段内，鼠标悬停任意柱/段/点/扇区都会弹出即时 tooltip（堆叠显示该段数值 + 合计）。v3 渲染：宽度自适应、Y 轴 1/2/5 刻度、单序列负值在零线以下真实绘制、line 带面积渐变与抽稀 X 标签、donut 图例显示数值与百分比。**≤8 个点的快速对比用 chart；多序列、需要缩放/交互或数据量大时用 echart**
- plot: `{"type":"plot","series":[{"expr":"a*sin(b*x)","label":"...","color":"#hex?","params":[{"name":"a","value":1,"min":0,"max":5,"animateTo":3,"durationMs":4000,"loop":true},{"name":"b","value":1,"min":0.5,"max":5}]}],"xMin":-6.28,"xMax":6.28,"title":"..."}` — SVG 函数图；**series 可带 `"kind":"line|area|scatter"`**（缺省 line；area 填色到基线；scatter 散点）；**params 渲染成实时滑块**（拖动即时重绘，**y 轴锁定**=只变曲线不变数轴）；**animateTo 参数会显示播放按钮**（自动动画演示）；SVG 可拖拽平移、滚轮缩放；表达式支持 sin/cos/tan/asin/acos/atan/sqrt/cbrt/exp/log/ln/abs/floor/ceil/round/min/max/pow，常量 pi/e/tau，变量 x（其他字母=参数）
- echart: `{"type":"echart","title":"...","height":300,"preset":"bar|line|area|pie|scatter","data":[{"label":"...","value":n}],"series":[...]?}` — **ECharts 全功能图表**，视觉效果远超 `chart`（渐变、tooltip、动画、图例交互）；**preset 模式**：用和 `chart` 一样的 `data`/`series` 格式，自动构建主题化的 ECharts 配置（颜色跟随宿主主题）；**preset 一览**（只写 preset + data/series/links，主题自动跟随）：
`bar` · `line` · `area` · `pie` · `scatter` · **`radar`**（每 series 一个多边形，指标取第一条 series 的 label）· **`gauge`**（每个 datum 一个仪表，适合单 KPI）· **`funnel`**（漏斗/转化）· **`treemap`**（体积/层级占比）· **`sankey`**（流向，用 `links:[{from,to,value}]`）· **`graph`**（关系图，`links` 驱动，节点大小随连接数）· **`heatmap`**（`series` 当行、第一条 series 的 label 当列）· **`bigline`**（长序列 + 内置缩放）
**full option 模式**：传 `"option":{...}` 直接写 ECharts 原生配置（支持 dataZoom/visualMap/radar/gauge/heatmap 等所有图表类型），option 中的函数会被过滤（只接受数据）。选择原则：**chart 轻量（无需加载额外引擎）适合 ≤8 点的快速对比；echart 视觉更丰富（渐变、tooltip、图例交互、dataZoom），引擎随魏碑安装并按需加载，多序列/大屏/交互场景优先**

### 交互
**本地优先（v2.6）**：UI 自己能做的状态变化——排序、筛选、展开、选中、重置——一律本地即时完成，**零模型往返**。action 只用于必须模型参与的事（生成新内容、执行工具、下一步建议）。**需要模型处理的操作才设置 action；按钮需要 action 才能触发。本地选择、筛选和展开无需逐次请求模型。**
- button: `{"type":"button","label":"...","tone":"primary|danger|success|ghost","full":true?,"small":true?,"icon":"emoji?","action":"refresh"?}`
- **秘密禁令**：不得索取或生成密码、API Key、访问令牌、恢复码等秘密输入；遇到此类需求直接拒绝并解释
- input: `{"type":"input","label":"...","placeholder":"...","inputType":"text|email|color","value":"...","action":"name"?,"id":"field-id"?}` — `color` 使用浏览器原生取色器，值使用 `#RRGGBB`；action 在失焦**和回车**时触发（回车带 `submit:true`）；**blur 仅值有变化才发送**（聚焦又离开不产生空往返）；payload 带 `id` 帮模型定位字段；带 `id` 的值刷新后保留、并被 submit 收集进 `fields`
- select: `{"type":"select","label":"...","options":["...","..."],"selected":下标?,"action":"pick"?,"id":"field-id"?}` — `selected` 预选某选项（缺省显示「请选择…」占位，不静默预选第一项）；带 `id` 的选择跨刷新保留并进 submit 的 `fields`
- checkbox: `{"type":"checkbox","label":"...","checked":true?,"action":"toggle"?,"group":"组名"?}` — 默认保持逐次 `action` 行为；**加 `group` 进入多选聚合模式**：同组 checkbox 可反复勾选/取消，变化只在本地记录、不发逐次 action，兄弟 `submit` 一次性把该组已选 label 作为字符串数组放进 `answers`（例如 `{"styles":["极简","线稿"]}`）
- slider: `{"type":"slider","label":"...","min":0,"max":100,"step":1,"value":n?,"action":"name"?,"id":"field-id"?}` — 数值表单滑块：实时显示数值；带 `id` 跨刷新保留并进 submit 的 `fields`（拖拽经防抖合并成一次 action）
- radio: `{"type":"radio","label":"...","options":["...","..."],"selected":n?,"action":"pick"?}` — 单选；**加 `"group":"题目名"` 进入聚合模式**：选择只本地记录、不发往返；**加 `"answer":正确下标或标签` + `"explanation":"解析"` 后，交卷在本地判卷**
- link: `{"type":"link","label":"...","href":"https://..."?}` — 仅 http(s)/mailto 协议被接受；无 `href` 时渲染为纯文本样式（不会假装可点）
- submit: `{"type":"submit","label":"继续讨论","action":"discuss","groups":["topics"]?,"resetAction":"redo"?}` — 聚合按钮：纯 radio 且题目带 `answer` 时仍本地立即判卷（得分 + 每题 ✓/✗ + 解析，零往返）；其余聚合场景一次发送 互动操作请求，payload 为 `{answers:{q1:选项A,styles:[选项1,选项2]},fields:{id:值},total,answered}`。`groups` 中每个 radio 必须已选择、每个 checkbox 组必须至少勾选一项才可提交
- switch: `{"type":"switch","label":"...","checked":true?,"action":"toggle"?}`
- textarea: `{"type":"textarea","label":"...","placeholder":"...","rows":n?,"value":"...","action":"save"?,"id":"field-id"?}` — action 在失焦和 **Ctrl/Cmd+Enter** 时触发；blur 仅值有变化才发送；带 `id` 的值刷新后保留
- tabs: `{"type":"tabs","tabs":[{"label":"...","items":[...]}]}`
- accordion: `{"type":"accordion","items":[{"title":"...","items":[...]}]}`
- copy: `{"type":"copy","label":"复制","text":"..."}`

**状态保存**：选择、输入和提交状态由魏碑随当前会话中的界面保存。同一块界面保持稳定 id；不要把重新提交相同 id 当成重置用户输入。

**用户明确要求自测时**，可用 quiz；多道选择题使用带唯一 group、answer、explanation 的 radio，最后用 submit 汇总，本地显示结果。普通解释不附加题目。

### 高级
- mermaid: `{"type":"mermaid","code":"graph TD\\nA-->B"}` — flowchart/sequence/class/gantt/pie/er/state/journey；主题自动跟随宿主（暗/浅）
- diagram: `{"type":"diagram","kind":"architecture","title":"可选标题","variant":"light|dark|editorial","nodes":[...],"edges":[...],"theme":{...}}` — **编辑级品牌图**（移植自 diagram-design 的 27 种视觉类型）。节点: `{"id":"a","label":"Web","type":"focal|backend|store|external|input|optional|security","x":40,"y":40,"w":128,"h":48,"sub":"可选技术子标签","tag":"可选角标如 API"}`；边: `{"from":"a","to":"b","label":"WRITE","kind":"solid|dashed|accent|link"}`。**规则由渲染器强制**: 正交连接器（r=8 弯折、禁止斜线）、4px 网格、语义 token（paper/ink/muted/accent）、焦点色 ≤2 个、复杂度预算（≤9 节点/≤12 边）、z-order（箭头在节点后）、边标签 6-10px 间隙。27 种 kind：architecture / it-state / flowchart / sequence / state / er / timeline / swimlane / quadrant / radar / loop / nested / tree / org-chart / layers / venn / pyramid / bar / line / gantt / scatter / high-level / process / medallion / data-flow / dp-integration / dp-security-matrix。**坐标类 kind**（architecture/it-state/high-level/process/medallion/data-flow/dp-integration）用 x/y/w/h 精确定位；**规则类 kind** 只给数据自动排版。架构/流程/层次结构优先用 diagram 而非 mermaid（自动布局用 mermaid，编辑级排版用 diagram）。
- scene3d: `{"type":"scene3d","title":"...","meshes":[{"shape":"box|sphere|cone|cylinder|torus","color":"#hex?","size":n|[w,h,d]?,"position":[x,y,z]?,"rotation":[rx,ry,rz]?,"scale":n?|[...]?}],"ambient":0-2?,"background":"#hex?"}` — 3D WebGL，可拖拽旋转、滚轮缩放；mesh 数量 1–5 个
- quiz: `{"type":"quiz","question":"...","options":[{"label":"...","correct":true?,"feedback":"..."?}],"explanation":"...","id":"..."?,"action":"answer"?}` — 教学问答：点选即判题、可重试；`id` 变化时重置；带 action 时另回传 `{type:'quiz',question,answer,correct}`

## 什么时候用：内容类型 → 组件映射

**判断口诀**：这段内容换成结构化组件，会不会比纯文字更好扫、更好懂、更好操作？会 → 就用，**不需要等用户开口要 UI**。

| 你要呈现的内容 | 用这些组件 |
|---|---|
| 关键结论 / 要点罗列（≥2 条） | `list`、`keyvalue`、`callout` |
| 重点强调 / 警告 / 注意事项 | `callout`（info/success/warning/error）、`badge`、`stat` |
| 数据对比 / 趋势 / 占比 | `chart`（bars/line/donut）、`echart`（ECharts 全功能）、`table` |
| 关键指标数字 / 进度状态 | `stat`、`progress`、`badge` |
| 回答的视觉锚点（第一个组件） | `hero`（封面块，一条回答最多一个） |
| 想排版不呆板 | `grid` + 子节点 `span`（bento：宽窄混排） |
| 数据多、需要读者自己找 | `input`（id）+ `table`/`chart`/`list` 的 `filter` 绑定 |
| 流程 / 步骤 / 阶段 / 时间线 | `steps`、`timeline`、`mermaid`（flowchart/sequence/gantt） |
| 架构 / 系统拓扑 / 数据流 / 品牌图 | `diagram`（编辑级，27 种类型；自动布局需求才用 `mermaid`） |
| 目录 / 文件结构 / 层级关系 | `file-tree`、`mermaid`、`accordion` |
| 状态一览 / 检查结果 | `badge` + `table` + `progress` 组合 |
| 代码 / 配置 / 改动对比 | `code`、`diff`、`json` |
| 图片 / 截图 / 图表预览 | `image` |
| 语音 / 音乐 / AI 视频 / 演示录像 | `audio`、`video` |
| 两个方案 / 选项对比 | `table`、`tabs`、`diff` |
| 用户明确要求自测 / 判断题 | `quiz` |
| 数学函数 / 曲线关系 | `plot`（可带参数滑块、动画） |
| 需要用户操作 / 筛选 / 反馈 | `button`、`input`、`select`、`checkbox`、`radio`、`switch`、`tabs` |
| 3D 物体 / 空间布局 | `scene3d` |

**别用的情况**：一句话能说清的事、纯闲聊、用户明确说不要 UI、以及"为了炫技硬塞"——组件服务内容，不是内容服务组件。

## 行内富文本（文字类回答的底座）

`text.content`、`list` 项、`table` 文本列、`keyvalue` 值、`callout` 标题与正文里可以直接写四种行内标记——**重点留在句子里，不必为一个词单起一个组件**：

| 写法 | 渲染 |
|---|---|
| `` `code` `` | 行内代码胶囊 |
| `**加粗**` | 强调（不换行、不成块） |
| `==高亮==` | 极淡底色标记 |
| `[文字](https://…)` | 行内链接（http/https/mailto；非法目标退化为纯文字） |

不嵌套、不解析 HTML（每个标记生成 React 元素，不走 innerHTML）；标记没闭合时原样显示。数值列 / badge / spark 单元格不解析（数字没什么可强调的）。

## 回答级版式：默认无卡，焦点唯一

### 三条判据（不设组件数量上限）

1. **必要性**：这个组件承载的信息，用文字表达会明显更差吗？数字对比、趋势、空间关系、代码/数据原文才算过关，否则删掉。
2. **焦点唯一**：一条回答只有一个视觉焦点（最大那张图或那组数字）；其余组件的视觉权重必须明显更低，靠尺寸/位置/色彩强度拉开，**不是靠数组件个数**。
3. **不重复**：避免无意义复述。图表看差异或趋势，表格查明细；用户明确要求两者时照做。

### 卡片（`card`）只在两种场合用

- 需要**并排**的 `grid` 子项（没有边界就分不清内容归属）；
- 承载**数据对象**：表格、图、keyvalue、指标组。

单段文字、单个列表、已经自带边界的表格/图表，**不要包卡**。用 `h3` 标题 + 正文 + 间距代替。

### 跟随魏碑主题与阅读宽度

字号、颜色、边界和表面由魏碑主题统一处理，不指定固定底色、阴影或再套整块外框。用标题、段落和间距区分层级。图表、长表格和流程优先纵向铺开；并排使用 grid，row 只放短按钮、标签等内容，避免把图表挤进窄行。

### 不要

- 装饰性编号（①②③）：该分点用 `list`，该分节用标题；
- 同一套骨架每条回答复用（标题栏 → 卡片网格 → 表格 → callout）；
- 为了"显得丰富"堆组件：读者找不到重点就是失败。


## 阅读与讨论示例：按内容选择，不照抄顺序

### 阅读材料：看数量差异，再安排整理步骤

用户给出教材 3 份、论文 20 篇、笔记 7 份，想看看材料构成并整理阅读顺序。图表占据完整阅读宽度，步骤放在下一段：

```json
{"id":"reading-materials","spec":{"items":[{"type":"chart","kind":"bars","data":[{"label":"教材","value":3},{"label":"论文","value":20},{"label":"笔记","value":7}]},{"type":"steps","steps":[{"title":"梳理材料","desc":"标出各份材料讨论的问题"},{"title":"整理观点","desc":"把判断与支持它的证据分开"},{"title":"继续讨论","desc":"从尚未理解的地方开始"}]}]}}
```

不要这样：用户只问数量，就额外安排阅读计划；用 row 把图表和长步骤挤在一起；材料没有给出时编造篇数。

### 继续讨论：输入后由用户明确提交

用户需要在界面中记下疑问再继续讨论。textarea 设置稳定 id，不带 action；submit 收集 fields 并发送一次请求。读取 fields.question 回答当前问题，按实际需要使用原有检索和笔记工具。

```json
{"id":"reading-question","spec":{"items":[{"type":"textarea","id":"question","label":"记下疑问","placeholder":"哪一处还没想明白？","rows":3},{"type":"submit","label":"继续讨论","action":"discuss"}]}}
```

不要这样：给输入框和提交按钮同时设置 action，导致离开输入框就发送；把普通疑问框命名为考试或交卷；每条回答都强塞一个讨论入口。

### 简短解释：直接回答

用户说“用两句话解释观点和证据”，直接回答：观点是你对一件事的判断。证据是用来支持这个判断的事实或资料。

不要这样：把两句话包进卡片，或反问用户来测试掌握程度。若用户之后要求比较多个具体例子，再用表格帮助看区别。

## 使用规则

1. 只通过 `render_ui` 提交界面；普通文字、公式、代码和静态表格仍可直接写在回答里。组件内的文字、表格和代码用于组合界面，不必把普通回答再包一遍。
2. 参数必须是合法 JSON 对象，`spec.items` 使用上方组件规范。长表格或复杂内容可拆成几次调用，按内容安排顺序。
3. 魏碑渲染器校验组件。工具回执表示已提交，不代表界面已经正确显示；遇到错误时按具体原因修正后重新提交。
4. 布局按内容组合，主题跟随魏碑；不设置固定的组件数量，也不为满足版式而增加无关内容。
5. `plot` 给出合理的 xMin/xMax；3D 只用于几何或空间内容，mesh 少而精。
6. 完整 spec 不超过 1 MB，组件树不超过 200 个节点、8 层嵌套；同一份信息避免重复表达。
