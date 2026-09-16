<!-- Generated from @changfenhuang/dsh-genui; edit script/build_genui.mjs for host integration. -->
# GenUI Advanced — 魏碑高级界面规范

这是 GenUI 的按需补充。先遵循主技能的判断、富文本、版式与调用规则；只有任务确实需要下列能力时使用，不照着规格堆组件。

## 高级与低频组件

- table: `{"type":"table","columns":["..."],"rows":[["...","..."]],"types":["text|num|delta|bar|badge"]?,"details":[[...]]?,"total":true?}` — 表头点击本地排序（升/降/还原，零往返）；数值感知：千分位（`1,234`）、`k/m/b`、`万/亿`、`%`、货币符号都能按真实数值比较，纯数值列自动右对齐；**带符号单元格自动着色**（`+12.4%` 绿、`-3` 红，无需额外字段）；`types` 可按列指定 `bar`（0-100 内联进度条）、`ring`（0-100 小环）、`spark`（单元格写 `"3,5,4,8"` 画微趋势线）、`badge`（胶囊标签）、`delta`（强制涨跌色）、`num`（强制右对齐）、`index`（行号）、`group`（首列当分组标题：该行只有第一格有内容时渲染成跨列小标题）；`"total":true` 追加合计行（数值列自动求和）；**`"export":true`**：表格上方出现「复制 Markdown / 复制 CSV」两个小按钮（纯本地剪贴板，不发请求）；**`"filter":"输入框id"`**：把表格和某个 input/select 绑定，读者输入即时过滤（`filterColumn` 可限定列）——数据多时**默认就该配一个**；**`"sortField":"下拉id"`** 用下拉的值（列名）排序；**`"details"` 与 rows 同序**，第 i 项是该行展开后的内容（可放任意组件，`null` = 该行不可展开）——首列出现 chevron，点开在整行下方展开明细，适合「主表 + 明细」
- echart: `{"type":"echart","title":"...","height":300,"preset":"bar|line|area|pie|scatter","data":[{"label":"...","value":n}],"series":[...]?}` — **ECharts 全功能图表**，视觉效果远超 `chart`（渐变、tooltip、动画、图例交互）；**preset 模式**：用和 `chart` 一样的 `data`/`series` 格式，自动构建主题化的 ECharts 配置（颜色跟随宿主主题）；**preset 一览**（只写 preset + data/series/links，主题自动跟随）：
`bar` · `line` · `area` · `pie` · `scatter` · **`radar`**（每 series 一个多边形，指标取第一条 series 的 label）· **`gauge`**（每个 datum 一个仪表，适合单 KPI）· **`funnel`**（漏斗/转化）· **`treemap`**（体积/层级占比）· **`sankey`**（流向，用 `links:[{from,to,value}]`）· **`graph`**（关系图，`links` 驱动，节点大小随连接数）· **`heatmap`**（`series` 当行、第一条 series 的 label 当列）· **`bigline`**（长序列 + 内置缩放）
**full option 模式**：传 `"option":{...}` 直接写 ECharts 原生配置（支持 dataZoom/visualMap/radar/gauge/heatmap 等所有图表类型），option 中的函数会被过滤（只接受数据）。选择原则：**chart 轻量（无需加载额外引擎）适合 ≤8 点的快速对比；echart 视觉更丰富（渐变、tooltip、图例交互、dataZoom），引擎随魏碑安装并按需加载，多序列/大屏/交互场景优先**
- plot: `{"type":"plot","series":[{"expr":"a*sin(b*x)","label":"...","color":"#hex?","params":[{"name":"a","value":1,"min":0,"max":5,"animateTo":3,"durationMs":4000,"loop":true},{"name":"b","value":1,"min":0.5,"max":5}]}],"xMin":-6.28,"xMax":6.28,"title":"..."}` — SVG 函数图；**series 可带 `"kind":"line|area|scatter"`**（缺省 line；area 填色到基线；scatter 散点）；**params 渲染成实时滑块**（拖动即时重绘，**y 轴锁定**=只变曲线不变数轴）；**animateTo 参数会显示播放按钮**（自动动画演示）；SVG 可拖拽平移、滚轮缩放；表达式支持 sin/cos/tan/asin/acos/atan/sqrt/cbrt/exp/log/ln/abs/floor/ceil/round/min/max/pow，常量 pi/e/tau，变量 x（其他字母=参数）
- diagram: `{"type":"diagram","kind":"architecture","title":"可选标题","variant":"light|dark|editorial","nodes":[...],"edges":[...],"theme":{...}}` — **编辑级品牌图**（移植自 diagram-design 的 27 种视觉类型）。节点: `{"id":"a","label":"Web","type":"focal|backend|store|external|input|optional|security","x":40,"y":40,"w":128,"h":48,"sub":"可选技术子标签","tag":"可选角标如 API"}`；边: `{"from":"a","to":"b","label":"WRITE","kind":"solid|dashed|accent|link"}`。**规则由渲染器强制**: 正交连接器（r=8 弯折、禁止斜线）、4px 网格、语义 token（paper/ink/muted/accent）、焦点色 ≤2 个、复杂度预算（≤9 节点/≤12 边）、z-order（箭头在节点后）、边标签 6-10px 间隙。27 种 kind：architecture / it-state / flowchart / sequence / state / er / timeline / swimlane / quadrant / radar / loop / nested / tree / org-chart / layers / venn / pyramid / bar / line / gantt / scatter / high-level / process / medallion / data-flow / dp-integration / dp-security-matrix。**坐标类 kind**（architecture/it-state/high-level/process/medallion/data-flow/dp-integration）用 x/y/w/h 精确定位；**规则类 kind** 只给数据自动排版。架构/流程/层次结构优先用 diagram 而非 mermaid（自动布局用 mermaid，编辑级排版用 diagram）。
- scene3d: `{"type":"scene3d","title":"...","meshes":[{"shape":"box|sphere|cone|cylinder|torus","color":"#hex?","size":n|[w,h,d]?,"position":[x,y,z]?,"rotation":[rx,ry,rz]?,"scale":n?|[...]?}],"ambient":0-2?,"background":"#hex?"}` — 3D WebGL，可拖拽旋转、滚轮缩放；mesh 数量 1–5 个
- hero: `{"type":"hero","title":"...","subtitle":"...","value":"99.96%","label":"可用率","delta":"+0.02%","spark":[...],"tone":"accent|success|warning|danger"}` — **封面块**：eyebrow + 超大数字（52px，带入场计数）+ 标题 + 副标题 + tone 渐变底色。**一条回答最多用一个**，放在最前面当视觉锚点
- span: 任意节点都可加 `"span":2`（grid 子节点占几列）——bento 排版的唯一原语：一张 `span:2` 宽卡配一张窄卡，比一列方块堆下去好看得多
- card: `{"type":"card","title":"...","items":[...]}`；`"accent":"#f59e0b"` 指定强调色（边框 + 标题 + 极淡底色）
- palette: `chart` / `echart` 都支持 `"palette":["#ff8800","#3ecf8e"]` 覆盖分类色板（默认跟随宿主主题）。**只有语义上需要指定颜色时才写**（成本=红、收益=绿），否则跟随主题更稳；`"tone":"info|success|warning|danger"` 给卡片底色（用于结论卡/风险卡）
- divider: `{"type":"divider"}`; spacer: `{"type":"spacer"}`
- avatar: `{"type":"avatar","name":"...","color":"#hex?"}`
- image: `{"type":"image","src":"https://example.com/result.png","alt":"结果图片"}` — 展示浏览器可访问的 HTTPS 图片地址；懒加载；不支持 `file:`/`data:` 等本地或主动协议
- audio: `{"type":"audio","src":"https://example.com/result.mp3","alt":"语音结果","loop":true?}` — 原生控制条；用户主动播放，不自动播放；仅已确认的 HTTPS 地址
- video: `{"type":"video","src":"https://example.com/result.mp4","alt":"视频结果","poster":"https://example.com/poster.jpg"?,"loop":true?,"muted":true?,"aspectRatio":"16:9|4:3|1:1|9:16"?}` — 原生播放/音量/全屏控制；不自动播放
- timeline: `{"type":"timeline","items":[{"title":"...","desc":"...","time":"..."}]}`
- file-tree: `{"type":"file-tree","items":[{"name":"...","type":"file|dir","children":[...]?}]}` — 目录行可点击折叠/展开（本地，零往返）
- breadcrumb: `{"type":"breadcrumb","items":["首页","设置","账户"]}`
- diff: `{"type":"diff","diffs":[{"path":"...","oldText":"..."|null,"newText":"..."}]}`
- json: `{"type":"json","value":...}`（JSON 树查看器）
- code: `{"type":"code","lang":"ts","code":"..."}`
- mermaid: `{"type":"mermaid","code":"graph TD\\nA-->B"}` — flowchart/sequence/class/gantt/pie/er/state/journey；主题自动跟随宿主（暗/浅）
- quiz: `{"type":"quiz","question":"...","options":[{"label":"...","correct":true?,"feedback":"..."?}],"explanation":"...","id":"..."?,"action":"answer"?}` — 教学问答：点选即判题、可重试；`id` 变化时重置；带 action 时另回传 `{type:'quiz',question,answer,correct}`
- checkbox: `{"type":"checkbox","label":"...","checked":true?,"action":"toggle"?,"group":"组名"?}` — 默认保持逐次 `action` 行为；**加 `group` 进入多选聚合模式**：同组 checkbox 可反复勾选/取消，变化只在本地记录、不发逐次 action，兄弟 `submit` 一次性把该组已选 label 作为字符串数组放进 `answers`（例如 `{"styles":["极简","线稿"]}`）
- slider: `{"type":"slider","label":"...","min":0,"max":100,"step":1,"value":n?,"action":"name"?,"id":"field-id"?}` — 数值表单滑块：实时显示数值；带 `id` 跨刷新保留并进 submit 的 `fields`（拖拽经防抖合并成一次 action）
- radio: `{"type":"radio","label":"...","options":["...","..."],"selected":n?,"action":"pick"?}` — 单选；**加 `"group":"题目名"` 进入聚合模式**：选择只本地记录、不发往返；**加 `"answer":正确下标或标签` + `"explanation":"解析"` 后，交卷在本地判卷**
- link: `{"type":"link","label":"...","href":"https://..."?}` — 仅 http(s)/mailto 协议被接受；无 `href` 时渲染为纯文本样式（不会假装可点）
- switch: `{"type":"switch","label":"...","checked":true?,"action":"toggle"?}`
- tabs: `{"type":"tabs","tabs":[{"label":"...","items":[...]}]}`
- accordion: `{"type":"accordion","items":[{"title":"...","items":[...]}]}`
- copy: `{"type":"copy","label":"复制","text":"..."}`

**状态保存**：选择、输入和提交状态由魏碑随当前会话中的界面保存。同一块界面保持稳定 id；不要把重提相同 id 当成重置。

**用户明确要求自测时**，才用带唯一 group、answer、explanation 的 radio 和汇总 submit；普通解释不附题。

## 容量与宿主边界

- 完整 spec 不超过 1 MB，组件树不超过 200 个节点、8 层嵌套。
- plot 必须给合理的 xMin/xMax；scene3d 只用于空间内容，mesh 控制在 1–5 个。
- diagram 建议不超过 9 个节点、12 条边；坐标型图按上方 kind 规则提供 x、y。
- 显示引擎随魏碑安装并按需加载；只使用用户给出或确认可公开访问的 HTTPS 媒体地址。

## 完整调用示例

这个例子只示范高级组件参数，不表示任何任务都要同时用表和图：

```json
{"id":"advanced-flow","spec":{"items":[{"type":"table","columns":["阶段","人数"],"rows":[["访问",120],["注册",45]]},{"type":"echart","option":{"xAxis":{"type":"category","data":["访问","注册"]},"yAxis":{"type":"value"},"series":[{"type":"bar","data":[120,45]}]}}]}}
```

保持稳定 id，通过 `render_ui` 提交；若不再需要高级组件，继续按主技能选择最小表达。
