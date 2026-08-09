---
name: visualize
description: "Create visual explanations and interactive tools directly in conversation. Use when seeing, comparing, adjusting, rehearsing, or exploring would improve understanding."
---

# Visualize

Visualize 是魏碑唯一的生成式界面判断入口。先决定什么表达真正有帮助，再决定是否生成界面：

1. 文字已经足够：只用普通回答。
2. 静态关系、顺序、层级或流程：使用普通 Mermaid 围栏。
3. 确实需要动态变化、空间操作、可调输入、练习或模拟：调用 `weibei_visualize`。

不要为了“看起来丰富”生成界面。需要时可以连续生成任意数量；每完成一个可用界面就立即提交，不等待整段回答结束，也不要求用户确认数量。

## 提交方式

```json
{
  "id": "stable-short-id",
  "spec": {
    "title": "可选标题",
    "gap": 12,
    "items": []
  }
}
```

- `id` 使用小写 ASCII 与连字符。同一 `id` 会在原位置更新；新 `id` 按调用顺序加入回答。
- 所有界面都按调用顺序穿插在回答正文里，并随内容完整展开；不要另做侧栏、常驻面板或分页界面。
- `spec` 只使用下列白名单组件，不输出 HTML、CSS 或 JavaScript。
- 界面中的 `action` 会把动作和当前值直接作为下一轮消息发给模型；用清楚的人话命名动作。
- 标签页、滑块、练习和模拟进度由魏碑自动保存，重开后恢复。

## 组件词汇

所有节点都可带可选 `id`，用于在同一界面更新时稳定保留局部状态。

### 布局

- `text`: `{"type":"text","content":"...","size":"h1|h2|h3|body|muted|caption","center":true?}`
- `row`: `{"type":"row","items":[...],"wrap":true?,"spacer":true?}`
- `col`: `{"type":"col","items":[...],"gap":12?}`
- `grid`: `{"type":"grid","cols":2,"items":[...]}`
- `card`: `{"type":"card","title":"..."?,"items":[...]}`
- `divider`: `{"type":"divider"}`
- `spacer`: `{"type":"spacer"}`

### 信息展示

- `stat`: `{"type":"stat","label":"...","value":"...","delta":"+12%"?}`
- `badge`: `{"type":"badge","label":"...","tone":"success|warn|danger|accent"?}`
- `progress`: `{"type":"progress","label":"..."?,"value":0-100,"valueLabel":"..."?}`
- `list`: `{"type":"list","items":["..."]}` 或 `items:[{"title":"...","desc":"..."?}]`
- `table`: `{"type":"table","columns":["..."],"rows":[["...",1]]}`
- `keyvalue`: `{"type":"keyvalue","pairs":[{"key":"...","value":"..."}]}`
- `callout`: `{"type":"callout","tone":"info|success|warning|error","title":"..."?,"content":"..."}`
- `steps`: `{"type":"steps","current":1,"steps":[{"title":"...","desc":"..."?}]}`
- `timeline`: `{"type":"timeline","items":[{"title":"...","desc":"..."?,"time":"..."?}]}`
### 图形

- `chart`: 柱状、折线或环形图。

```json
{"type":"chart","kind":"bars|line|donut","data":[{"label":"一月","value":12,"color":"#a94b35"?}]}
```

- `plot`: 已采样的二维曲线；每条 series 的 points 为 `[x,y]`。

```json
{"type":"plot","title":"..."?,"xLabel":"时间 / s"?,"yLabel":"速度 / m·s⁻¹"?,"series":[{"label":"方案 A","points":[[0,0],[1,2]],"color":"#a94b35"?}]}
```

- `scene3d`: 可拖动旋转的轻量空间示意。

```json
{"type":"scene3d","title":"..."?,"objects":[{"shape":"box|sphere|cone|cylinder","label":"..."?,"color":"#a94b35"?,"position":[0,0,0],"scale":[1,1,1]?}]}
```

静态节点关系仍优先使用普通 Mermaid，不要把 Mermaid 塞进互动界面。

### 基础交互

- `button`: `{"type":"button","label":"...","tone":"primary|danger|success|ghost"?,"action":"..."?}`
- `input`: `{"type":"input","label":"..."?,"placeholder":"..."?,"value":"..."?,"action":"..."?}`
- `textarea`: `{"type":"textarea","label":"..."?,"rows":4?,"value":"..."?,"action":"..."?}`
- `select`: `{"type":"select","label":"..."?,"options":["..."],"selected":0?,"action":"..."?}`
- `checkbox`: `{"type":"checkbox","label":"...","checked":true?,"action":"..."?}`
- `radio`: `{"type":"radio","label":"..."?,"options":["..."],"selected":0?,"action":"..."?}`
- `switch`: `{"type":"switch","label":"...","checked":true?,"action":"..."?}`
- `slider`: `{"type":"slider","label":"...","value":2,"min":0,"max":5,"step":0.5?,"unit":"m/s"?,"action":"..."?}`
- `tabs`: `{"type":"tabs","tabs":[{"label":"...","items":[...]}]}`
- `accordion`: `{"type":"accordion","items":[{"title":"...","items":[...]}]}`
- `copy`: `{"type":"copy","label":"复制"?,"text":"..."}`

只有需要模型继续分析、重算或改变整个界面时才设置 `action`。标签页、折叠、练习判定和模拟播放默认在本地即时完成。

### 学习组件

- `formula`: 公式与逐步推演。表达式使用可读的 Unicode 数学文本，避免依赖 TeX 命令。

```json
{"type":"formula","label":"勾股定理"?,"expression":"a² + b² = c²","steps":[{"expression":"c² = a² + b²","explanation":"移项"?}]}
```

- `quiz`: 单选判题、反馈与重试。

```json
{"type":"quiz","question":"...","options":[{"label":"...","correct":true?,"feedback":"..."?}],"explanation":"..."?}
```

- `sort`: 拖拽排序。

```json
{"type":"sort","prompt":"按顺序排列"?,"items":["巡航","点火"],"answer":["点火","巡航"],"action":"..."?}
```

- `match`: 拖拽或点击配对。

```json
{"type":"match","prompt":"完成配对"?,"pairs":[{"left":"H₂O","right":"水"}],"action":"..."?}
```

- `classify`: 把项目拖入分类。

```json
{"type":"classify","prompt":"完成归类"?,"groups":[{"label":"哺乳类","items":["鲸"]},{"label":"鱼类","items":["鲫鱼"]}],"action":"..."?}
```

- `simulation`: 可播放、暂停、跳转和逐步推进的过程。

```json
{"type":"simulation","title":"星舟协议","steps":[{"label":"点火","content":"消耗 2 枚令牌"},{"label":"巡航","content":"生成 5 单位能量"}],"intervalMs":1200?,"loop":true?,"action":"..."?}
```

## 组合判断

- 用最少的组件清楚表达，不拼模板式仪表盘。
- 数量由内容决定；不强行限制卡片、图表或界面个数，也不为了填空增加指标。
- 可调解释器以一个主视觉和紧凑控制为中心；实时值放在控制旁边。
- 比较场景优先共享尺度、并排或小倍图；信息过密时自然换行，不缩小到难读。
- 练习必须让用户能直接操作并看到结果；失败时保留当前操作，不清空。
- 过程模拟默认展示当前一步，允许前后跳转；只有连续变化有价值时才自动播放。
- 产品界面预览要沿用对话中已知的品牌、内容和平台语境，不生成通用模板页面。

## 回答配合

- 普通文字继续承担解释；互动界面只承载看、调、练、演示本身。
- 一个界面完成就调用工具。工具之后可以继续写回答或生成下一个界面。
- 不在用户可见文字里讨论组件树、渲染器、脚本或实现细节。
- 用户明确要求把界面保存成网站或项目文件时，按普通项目任务处理，不让对话内界面自行写文件。
