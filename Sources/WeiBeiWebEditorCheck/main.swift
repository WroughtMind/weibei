import AppKit
import Foundation
import WebKit

let sampleMarkdown = """
---
course: 货币金融学
tags:
  - finance/rate
---

# 魏碑 Markdown Web 验收

| 能力 | 状态 |
| --- | --- |
| 表格 | 可编辑 |
| Agent | 可追问 |
| 双链 | [[货币理论\\|理论别名]] |
| 转义 | A \\| B |

- [ ] todo
- [x] done
- 普通列表
  - 嵌套列表

~~删除线~~、==重点高亮==、[[货币理论|理论别名]]、[[货币理论#利率]]、[[货币理论#^rate-block]]、[[#本页标题]]、[[^^利率搜索]]。
%%这是一条只在写作时弱显示的注释%%
%%
这是一段块注释
跨行也应该弱显示
%%
#finance #nested/tag
重点段落 ^rate-block

HTML 换行第一行<br />第二行，选区应读作两行。

脚注引用[^1]，行内脚注^[行内脚注内容]。

[^1]: 这是脚注内容。

> [!note]- 可编辑标题
>
> 温和洞察应该放在不打断阅读的位置。

> [!quote] 选区摘录
>
> 利率是资金使用价格的表达。
>
> 来源：Mishkin 教材样例，第 12 页
>
> Source: Mishkin sample, page 13

> [!quote] 旧摘录
>
> [!quote] 旧逻辑泄露
> 这行旧摘录正文不能带着控制符显示。

> > [!quote] 嵌套摘录
> >
> > 嵌套摘录里的控制符不应该露出来。

> [!attention]+ 自定义标题
>
> 自定义 Callout 不应该漏出源标记。

> 引用里的代码块：
>
> ```txt
> \\#quoted-code \\$5 \\[!note] <br />
> ```

行内公式 $E = mc^2$、$\\alpha_1 + \\beta^2$、$A^*$，普通金额 $5 不应该被误伤。

Milkdown 公式插件应直接渲染 $text^*$，不能额外生成源码灰块。

$$
\\frac{a_1}{b^2} + \\sum_{i=1}^{n} x_i
$$

$$
\\begin{bmatrix}
a & b \\\\
c & d
\\end{bmatrix}
$$

```swift
let note = "魏碑"
print(note)
```

行内代码 `<br />` 不应被当成换行。
双反引号 ``内部 ` <br />`` 也要保留源码。
行内代码 `[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />` 不应触发魏碑语法装饰。
行内代码 `\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]` 保存时不能被清理反斜杠。
转义反引号 \\` 后面的 \\[\\[转义双链\\]\\] \\#escaped-tag \\$5 仍应按正文保存。

回答引用应可点击：[材料：利率章节]、[笔记：新笔记 17]、[选区：教材第 12 页]。

```html
<span>保留<br />源码</span>
```

```txt
\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]
```

```mermaid
graph TD
  A[阅读] --> B[整理]
```

```weibei-interactive
{"kind":"quiz","prompt":"名义利率和实际利率的区别是什么？","options":["是否扣除通胀","是否来自银行","是否用于汇率"],"correctIndex":0,"explanation":"实际利率会把通胀影响扣掉。","source":"材料：利率章节"}
```

```weibei-interactive
{"kind":"reveal","title":"先自己想","content":"名义利率是票面看到的利率，实际利率更接近真实购买力变化。","source":"笔记：新笔记 17"}
```

```weibei-interactive
{"kind":"reveal","title":"安全文本","content":"<img src=x onerror=alert(1)> 这段只能作为文字出现。","source":"选区：教材第 12 页"}
```

```weibei-interactive
{"kind":"chart","title":"利率与通胀","chartType":"line","xLabel":"时期","yLabel":"百分比","series":[{"name":"名义利率","tone":"cinnabar","points":[{"x":1,"y":5.2},{"x":2,"y":4.8},{"x":3,"y":4.3}]},{"name":"通胀率","tone":"ochre","points":[{"x":1,"y":2.1},{"x":2,"y":2.7},{"x":3,"y":3.0}]}],"sources":["材料：利率章节","笔记：新笔记 17"]}
```

```weibei-interactive
{"kind":"chart","title":"掌握层级","chartType":"bar","xLabel":"层级","yLabel":"人数","series":[{"name":"本次测验","tone":"moss","points":[{"x":"记忆","y":8},{"x":"理解","y":6},{"x":"迁移","y":3}]}],"source":"笔记：新笔记 17"}
```

```weibei-interactive
{"kind":"chart","title":"风险与收益","chartType":"scatter","xLabel":"风险","yLabel":"收益","series":[{"name":"资产","tone":"blue-ink","points":[{"x":1,"y":2.2},{"x":2,"y":3.1},{"x":3,"y":5.0}]}],"source":"材料：利率章节"}
```

```weibei-interactive
{"kind":"chart","title":"累计理解","chartType":"area","xLabel":"学习轮次","yLabel":"掌握度","series":[{"name":"掌握度","tone":"ochre","points":[{"x":1,"y":1.4},{"x":2,"y":2.8},{"x":3,"y":4.6}]}],"source":"笔记：新笔记 17"}
```

```weibei-interactive
{"kind":"function-plot","title":"二次函数曲线","xLabel":"x","yLabel":"y","xDomain":[-3,3],"yDomain":[-1,10],"curves":[{"name":"平方函数","formulaLabel":"y = x^2","tone":"blue-ink","points":[[-3,9],[-2,4],[-1,1],[0,0],[1,1],[2,4],[3,9]]}],"source":"笔记：新笔记 17"}
```

```weibei-interactive
{"kind":"parameter-lab","title":"二次函数调参","family":"quadratic","xDomain":[-4,4],"yDomain":[-4,12],"controls":[{"key":"a","label":"开口 a","min":-2,"max":2,"step":0.5,"value":1},{"key":"h","label":"横移 h","min":-2,"max":2,"step":0.5,"value":0},{"key":"k","label":"纵移 k","min":-2,"max":4,"step":0.5,"value":0}],"source":"材料：利率章节"}
```

```weibei-interactive
{"kind":"parameter-lab","title":"反比例函数断点","family":"inverse","xDomain":[-4,4],"yDomain":[-6,6],"controls":[{"key":"a","label":"尺度 a","min":0.5,"max":2,"step":0.5,"value":1},{"key":"h","label":"渐近线 h","min":-1,"max":1,"step":0.5,"value":0},{"key":"k","label":"纵移 k","min":-1,"max":1,"step":0.5,"value":0}],"source":"材料：利率章节"}
```

```weibei-interactive
{"kind":"text-study","title":"论证语气比较","variants":[{"label":"原句","text":"数字金融一定提高资源配置效率。","note":"结论过满，缺少条件。"},{"label":"收束后","text":"在信息披露充分时，数字金融可能提高资源配置效率。","note":"补出条件，并降低无证据的绝对断言。"}],"highlightTerms":["信息披露充分","可能"],"source":"选区：教材第 12 页"}
```

```weibei-interactive
{"kind":"design-compare","title":"学习摘要版式","variants":[{"label":"文稿型","headline":"名义利率与实际利率","body":"先给定义，再用通胀条件解释二者差异。","treatment":"editorial","tone":"cinnabar"},{"label":"注释型","headline":"先看购买力","body":"把实际利率写成对名义利率的条件修正。","treatment":"annotated","tone":"moss"}],"source":"笔记：新笔记 17"}
```

```weibei-interactive
{"kind":"palette","title":"纸墨配色","previewText":"利率是资金跨期配置的价格。","colors":[{"name":"宣纸","value":"#F1E4CF","role":"底色"},{"name":"墨色","value":"#1D1814","role":"正文"},{"name":"朱砂","value":"#91261C","role":"强调"},{"name":"苔绿","value":"#395F48","role":"正确与确认"}],"source":"笔记：新笔记 17"}
```

```weibei-interactive
{"kind":"study-board","title":"利率学习操作图","summary":"先分清定义，再把通胀、期限和风险串起来。","layout":"lanes","treatment":"annotated","metrics":[{"label":"核心概念","value":"3","note":"定义/通胀/期限","tone":"cinnabar"},{"label":"待回看","value":"1","tone":"ochre"}],"items":[{"kicker":"定义","title":"名义利率","body":"票面或合约中直接看到的利率。","status":"已读","tone":"cinnabar","source":"材料：利率章节"},{"kicker":"修正","title":"实际利率","body":"扣除通胀影响后，更接近购买力变化。","status":"待例题","tone":"moss","source":"笔记：新笔记 17"},{"kicker":"迁移","title":"期限结构","body":"把短期和长期利率放到同一张图里比较。","tone":"blue-ink"}],"sources":["材料：利率章节","笔记：新笔记 17"]}
```

```weibei-interactive
{"kind":"relationship-map","title":"利率关系图","layout":"radial","nodes":[{"id":"rate","label":"利率","detail":"资金跨期配置的价格","tone":"cinnabar","source":"材料：利率章节"},{"id":"inflation","label":"通胀","detail":"影响实际购买力","tone":"ochre"},{"id":"term","label":"期限","detail":"改变风险与流动性","tone":"blue-ink"},{"id":"risk","label":"风险补偿","detail":"要求更高回报","tone":"moss","source":"笔记：新笔记 17"}],"edges":[{"from":"rate","to":"inflation","label":"扣除后得到实际利率"},{"from":"rate","to":"term","label":"形成期限结构"},{"from":"risk","to":"rate","label":"推高要求收益"}],"sources":["材料：利率章节"]}
```

```weibei-interactive
{"kind":"timeline","title":"复习节奏","events":[{"label":"D1","title":"读定义","detail":"先把名义/实际利率写成自己的话。","tone":"cinnabar","source":"材料：利率章节"},{"label":"D2","title":"补例题","detail":"用通胀例子算近似实际利率。","tone":"moss"},{"label":"D3","title":"连期限","detail":"把短期、长期和风险补偿放在一起。","tone":"blue-ink","source":"笔记：新笔记 17"}],"sources":["笔记：新笔记 17"]}
```

```weibei-interactive
{"kind":"comparison-matrix","title":"名义利率与实际利率","columns":["观察口径","关键问题","学习动作"],"rows":[{"label":"名义利率","values":["合约看到的数字","有没有扣除通胀","先记定义"],"emphasisIndex":0},{"label":"实际利率","values":["购买力变化","通胀如何修正","做一个计算例子"],"emphasisIndex":2},{"label":"期限结构","values":["不同期限比较","风险补偿在哪里","画出方向关系"]}],"sources":["材料：利率章节","笔记：新笔记 17"]}
```

```weibei-interactive
{"kind":"annotated-passage","title":"原文夹批","text":"名义利率包含预期通胀，实际利率反映真实资金成本。","annotations":[{"term":"名义利率","note":"合约直接标示的利率。","tone":"ochre","source":"材料：利率章节"},{"term":"实际利率","note":"扣除预期通胀后的观察口径。","tone":"cinnabar","source":"笔记：新笔记 17"}],"sources":["材料：利率章节"]}
```

```weibei-interactive
{"kind":"derivation-steps","title":"实际利率推导","prompt":"先判断通胀应当加上还是扣除。","steps":[{"label":"已知","statement":"名义利率约等于实际利率加预期通胀。","reason":"材料给出组成关系。","source":"材料：利率章节"},{"label":"移项","statement":"实际利率约等于名义利率减预期通胀。","reason":"从名义利率中剔除价格预期。","source":"材料：利率章节"},{"label":"检验","statement":"代入同一组数值核对。","reason":"结果应还原名义利率。","source":"笔记：新笔记 17"}],"sources":["材料：利率章节"]}
```

```weibei-interactive
{"kind":"flashcards","title":"利率记忆卡","cards":[{"front":"名义利率包含什么？","back":"包含预期通胀。","hint":"想报价中的价格预期。","source":"材料：利率章节"},{"front":"实际利率衡量什么？","back":"更接近真实资金成本。","source":"笔记：新笔记 17"}],"sources":["材料：利率章节"]}
```

```weibei-interactive
{"kind":"sequence-builder","title":"政策观察顺序","instruction":"依次点选，再检查顺序。","items":[{"id":"goal","label":"确认目标","detail":"明确观察指标","source":"材料：利率章节"},{"id":"tool","label":"调整工具","detail":"选择对应工具","source":"材料：利率章节"},{"id":"review","label":"复盘结果","detail":"对照目标与反应","source":"笔记：新笔记 17"}],"correctOrder":["goal","tool","review"],"successText":"顺序正确。","retryText":"再看每一步的前置条件。","sources":["材料：利率章节"]}
```

```weibei-interactive
{"kind":"scenario-lab","title":"通胀预期实验","controls":[{"id":"inflation","label":"预期通胀","options":["保持不变","上升"],"initialIndex":0}],"outcomes":[{"selections":[0],"title":"基准情境","body":"名义与实际利率保持基准差额。","tone":"ink","source":"材料：利率章节"},{"selections":[1],"title":"差额扩大","body":"实际利率不变时，名义利率需要反映更高预期通胀。","tone":"cinnabar","source":"材料：利率章节"}],"sources":["材料：利率章节"]}
```

```weibei-interactive
{"kind":"evidence-board","title":"核验判断","claim":"实际利率更适合衡量真实资金成本。","items":[{"stance":"support","title":"扣除预期通胀","detail":"材料明确给出扣除关系。","tone":"moss","source":"材料：利率章节"},{"stance":"challenge","title":"短期冲击","detail":"短期预期变化可能让估计发生偏移。","tone":"cinnabar","source":"笔记：新笔记 17"},{"stance":"gap","title":"适用范围未说明","detail":"当前片段没有列出全部市场条件。","tone":"ochre","source":"材料：利率章节"}],"sources":["材料：利率章节","笔记：新笔记 17"]}
```

```weibei-interactive
{"kind":"spectrum","title":"观察口径光谱","axisStart":"报价表面","axisEnd":"真实负担","points":[{"label":"名义利率","position":20,"detail":"直接显示在合约或报价中。","tone":"ochre","source":"材料：利率章节"},{"label":"实际利率","position":80,"detail":"扣除预期通胀后更接近真实资金成本。","tone":"cinnabar","source":"笔记：新笔记 17"}],"sources":["材料：利率章节"]}
```

```weibei-interactive
{"kind":"decision-path","title":"选择观察指标","startID":"goal","nodes":[{"id":"goal","title":"你要观察什么？","body":"先区分报价本身与真实资金成本。","choices":[{"label":"看合约标示","nextID":"nominal"},{"label":"看真实成本","nextID":"real"}],"source":"材料：利率章节"},{"id":"nominal","title":"使用名义利率","body":"读取报价直接标示的利率。","choices":[],"source":"材料：利率章节"},{"id":"real","title":"使用实际利率","body":"读取扣除预期通胀后的利率。","choices":[],"source":"笔记：新笔记 17"}],"sources":["材料：利率章节"]}
```

```weibei-interactive
{"blockId":"cross-unit-workbench-v1","kind":"unit-workbench","title":"速度单位工作台","question":"用路程和时间核验平均速度。","variables":[{"id":"distance","label":"路程","value":"120","unit":"km","role":"已知量","source":"材料：运动章节"},{"id":"time","label":"时间","value":"2","unit":"h","role":"已知量","source":"笔记：速度例题"}],"checks":[{"id":"speed-check","label":"量纲核验","left":"120 km / 2 h","right":"60 km/h","result":"数值与单位一致","source":"材料：运动章节"}],"sources":["材料：运动章节","笔记：速度例题"]}
```

```weibei-interactive
{"blockId":"cross-reaction-balance-v1","kind":"reaction-balance","title":"水的生成反应配平","species":[{"id":"hydrogen","label":"H2","side":"reactant","coefficient":1,"atoms":{"H":2},"source":"材料：化学方程式"},{"id":"oxygen","label":"O2","side":"reactant","coefficient":1,"atoms":{"O":2},"source":"材料：化学方程式"},{"id":"water","label":"H2O","side":"product","coefficient":1,"atoms":{"H":2,"O":1},"source":"笔记：配平练习"}],"sources":["材料：化学方程式","笔记：配平练习"]}
```

```weibei-interactive
{"blockId":"cross-algorithm-trace-v1","kind":"algorithm-trace","title":"求和算法跟踪","codeLines":["sum = 0","for value in [2, 3]","  sum += value","print(sum)"],"steps":[{"lineIndex":0,"summary":"初始化总和","note":"sum 从 0 开始。","source":"材料：算法章节"},{"lineIndex":2,"summary":"累加当前数字","note":"第一次把 2 加入 sum。","source":"材料：算法章节"},{"lineIndex":3,"summary":"输出结果","note":"循环结束后输出 5。","source":"笔记：求和跟踪"}],"sources":["材料：算法章节","笔记：求和跟踪"]}
```

```weibei-interactive
{"blockId":"cross-language-aligner-v1","kind":"language-aligner","title":"中英论述对齐","pairs":[{"label":"定义","sourceText":"实际利率扣除了通胀影响。","targetText":"The real interest rate adjusts for inflation.","note":"adjust for 表示把某因素纳入修正。","source":"材料：双语金融"},{"label":"条件","sourceText":"信息充分时，配置效率可能提高。","targetText":"Efficiency may improve when information is sufficient.","note":"may 保留结论的条件性。","source":"笔记：学术表达"}],"sources":["材料：双语金融","笔记：学术表达"]}
```

```weibei-interactive
{"blockId":"cross-argument-map-v1","kind":"argument-map","title":"数字金融论证图","question":"数字金融是否必然提高配置效率？","nodes":[{"id":"premise-info","type":"premise","label":"信息成本下降","detail":"搜索和匹配成本降低。","source":"材料：数字金融"},{"id":"claim-efficiency","type":"claim","label":"配置效率可能提高","detail":"结论受信息质量条件约束。","source":"材料：数字金融"},{"id":"objection-bias","type":"objection","label":"数据偏差会放大误配","detail":"样本偏差可能抵消效率收益。","source":"笔记：论证边界"}],"edges":[{"from":"premise-info","to":"claim-efficiency","label":"支持"},{"from":"objection-bias","to":"claim-efficiency","label":"限制"}],"sources":["材料：数字金融","笔记：论证边界"]}
```

```weibei-interactive
{"blockId":"cross-visual-analysis-v1","kind":"visual-analysis","title":"碑刻版面视觉分析","zones":[{"id":"title-zone","label":"题额","x":8,"y":8,"width":84,"height":18,"note":"题额形成第一层视觉重心。","tone":"cinnabar","source":"材料：碑刻图版"},{"id":"body-zone","label":"正文区","x":12,"y":34,"width":76,"height":56,"note":"正文纵向列阵控制阅读节奏。","tone":"ink","source":"笔记：版面观察"}],"palette":[{"label":"墨色","role":"正文主体","tone":"ink"},{"label":"朱砂","role":"题记强调","tone":"cinnabar"}],"lenses":[{"id":"hierarchy","label":"层级","note":"比较题额和正文的视觉权重。","zoneIds":["title-zone","body-zone"]}],"sources":["材料：碑刻图版","笔记：版面观察"]}
```

```weibei-interactive
{"blockId":"cross-spatial-layers-v1","kind":"spatial-layers","title":"河谷聚落空间分层","layers":[{"id":"terrain","label":"地形层","visible":true},{"id":"settlement","label":"聚落层","visible":true}],"features":[{"id":"river-route","type":"route","layerId":"terrain","label":"河道","note":"河道贯穿谷地。","points":[{"x":8,"y":72},{"x":42,"y":50},{"x":88,"y":28}],"source":"材料：河谷地图"},{"id":"village-point","type":"point","layerId":"settlement","label":"东村","note":"聚落靠近河道缓坡。","points":[{"x":58,"y":43}],"source":"笔记：聚落观察"},{"id":"farmland-region","type":"region","layerId":"settlement","label":"耕作区","note":"耕作区位于河道下游。","points":[{"x":52,"y":58},{"x":82,"y":52},{"x":76,"y":80}],"source":"材料：河谷地图"}],"sources":["材料：河谷地图","笔记：聚落观察"]}
```

```weibei-interactive
{"blockId":"cross-pathway-lab-v1","kind":"pathway-lab","title":"细胞呼吸路径状态","nodes":[{"id":"glucose","label":"葡萄糖","detail":"反应起点","source":"材料：细胞呼吸"},{"id":"pyruvate","label":"丙酮酸","detail":"糖酵解产物","source":"材料：细胞呼吸"},{"id":"atp","label":"ATP","detail":"可用能量","source":"笔记：能量路径"}],"states":[{"id":"start","label":"起始态","note":"先观察葡萄糖。","activeNodeIds":["glucose"],"source":"材料：细胞呼吸"},{"id":"glycolysis","label":"糖酵解后","note":"丙酮酸和少量 ATP 已生成。","activeNodeIds":["pyruvate","atp"],"source":"笔记：能量路径"}],"edges":[{"from":"glucose","to":"pyruvate","label":"糖酵解"},{"from":"pyruvate","to":"atp","label":"释放能量"}],"sources":["材料：细胞呼吸","笔记：能量路径"]}
```

```weibei-interactive
{"blockId":"rejected-visual-fields-v1","kind":"visual-analysis","title":"视觉外部内容拒绝夹具","imageURL":"javascript:alert('visual-url')","html":"<img src=x onerror=alert('visual-html')>","zones":[{"id":"safe-zone","label":"安全区域","x":10,"y":10,"width":20,"height":20,"note":"只渲染协议允许的文本。","tone":"moss","source":"材料：安全夹具"}],"palette":[],"lenses":[],"sources":["材料：安全夹具"]}
```

```weibei-interactive
{"blockId":"rejected-spatial-bounds-v1","kind":"spatial-layers","title":"越界空间坐标不得渲染","layers":[{"id":"map","label":"地图层","visible":true}],"features":[{"id":"outside","type":"point","layerId":"map","label":"越界点","points":[{"x":120,"y":40}],"source":"材料：安全夹具"}],"sources":["材料：安全夹具"]}
```

```weibei-interactive
{"blockId":"rejected-pathway-node-v1","kind":"pathway-lab","title":"未知路径节点不得渲染","nodes":[{"id":"known","label":"已知节点","source":"材料：安全夹具"}],"states":[{"id":"invalid-state","label":"非法状态","activeNodeIds":["missing-node"],"source":"材料：安全夹具"}],"edges":[],"sources":["材料：安全夹具"]}
```

```weibei-interactive
{"version":2,"kind":"reveal","title":"未来协议不得渲染","content":"未知版本必须保留源码，不能猜测执行。"}
```

![魏碑测试图|100x80](assets/weibei.svg)
![[assets/weibei.svg|100]]
![[货币理论#利率]]
"""

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("web-editor-check failed: \(message)\n", stderr)
        exit(1)
    }
}

func json(_ value: String) -> String {
    let data = (try? JSONEncoder().encode(value)) ?? Data("".utf8)
    return String(data: data, encoding: .utf8) ?? "\"\""
}

final class EditorHarness: NSObject, WKScriptMessageHandler {
    private let webView: WKWebView
    private var isDone = false
    private var failure: String?
    private var activatedWikiTitle: String?
    private var activatedSourceReference: String?
    private var interactiveActions: [[String: Any]] = []
    private var attachmentRequests = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let source = """
        window.initialMarkdown = \(json(sampleMarkdown));
        window.weiBeiDocumentID = "web-editor-check";
        window.weiBeiMarkdownEditable = true;
        window.weiBeiEditorCheckMode = true;
        window.weiBeiLocalImageScheme = "weibeiimage";
        window.weiBeiMarkdownBaseURL = \(json(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Sources/WeiBei/Resources/Editor/").absoluteString));
        """
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 960, height: 720), configuration: configuration)
        super.init()
        for name in ["editorReady", "markdownChanged", "selectionChanged", "askAgentWithSelection", "wikiLinkActivated", "sourceReferenceActivated", "interactiveAction", "imageAttachmentRequested"] {
            controller.add(self, name: name)
        }
    }

    func run() {
        let indexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())

        let timeout = Date().addingTimeInterval(15)
        while !isDone && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        if let failure {
            fputs("web-editor-check failed: \(failure)\n", stderr)
            exit(1)
        }
        expect(isDone, "editor did not become ready")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "editorReady":
            guard (message.body as? [String: Any])?["documentID"] as? String == "web-editor-check" else {
                fail("editorReady did not include the current document identity")
                return
            }
            validateInitialMarkdown()
        case "wikiLinkActivated":
            activatedWikiTitle = (message.body as? [String: Any])?["title"] as? String
        case "sourceReferenceActivated":
            activatedSourceReference = (message.body as? [String: Any])?["reference"] as? String
        case "interactiveAction":
            if let body = message.body as? [String: Any] {
                interactiveActions.append(body)
            }
        case "imageAttachmentRequested":
            attachmentRequests += 1
        default:
            break
        }
    }

    private func validateInitialMarkdown() {
        webView.evaluateJavaScript("window.WeiBeiEditor.getMarkdown()") { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("getMarkdown threw \(error.localizedDescription)")
                return
            }
            guard let markdown = value as? String else {
                self.fail("getMarkdown did not return text")
                return
            }
            self.validate(markdown)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.validateObsidianDecorations {
                    self.validateReadOnlyInkstoneDecorations {
                        self.validateRenderedImageSource {
                            self.validateWikiLinkActivation()
                        }
                    }
                }
            }
        }
    }

    private func validateObsidianDecorations(completion: @escaping () -> Void) {
        let script = """
        (() => ({
          wikilinkText: document.querySelector('.weibei-wikilink')?.textContent || '',
          inlineFootnoteText: document.querySelector('.weibei-inline-footnote')?.textContent || '',
          inlineFootnotes: document.querySelectorAll('.weibei-inline-footnote').length,
          comments: document.querySelectorAll('.weibei-comment').length,
          commentsWeak: (() => {
            const comments = Array.from(document.querySelectorAll('.weibei-comment'));
            if (comments.length < 1) return false;
            return comments.every((comment) => {
              const style = getComputedStyle(comment);
              return parseFloat(style.opacity || '1') <= 0.72
                || style.color === 'rgba(0, 0, 0, 0)'
                || parseFloat(style.fontSize || '16') <= 12;
            });
          })(),
          tags: document.querySelectorAll('.weibei-tag').length,
          blockIds: document.querySelectorAll('.weibei-block-id').length,
          frontmatterTitle: document.querySelector('.frontmatter-title')?.textContent || '',
          embeds: document.querySelectorAll('.weibei-embed-preview').length,
          sourceReferences: document.querySelectorAll('.weibei-source-reference').length,
          bracketSourceReferences: document.querySelectorAll('.weibei-source-reference[data-source-kind]').length,
          sourceReferenceTitle: document.querySelector('.weibei-source-reference')?.getAttribute('title') || '',
          bracketSourceTitle: document.querySelector('.weibei-source-reference[data-source-reference="来源：利率章节"]')?.getAttribute('title') || '',
          editableInteractiveBlocks: document.querySelectorAll('.weibei-interactive').length,
          editableInteractiveSourceVisible: document.body.textContent.includes('```weibei-interactive') || document.querySelector('pre[data-language="weibei-interactive"]')?.textContent.includes('名义利率和实际利率') || false,
          hardBreaks: document.querySelectorAll('.ProseMirror br').length,
          noteEmbedLinks: document.querySelectorAll('.weibei-embed-note[role="link"][tabindex="0"][data-wikilink-title]').length,
          mermaid: document.querySelectorAll('.weibei-mermaid-render').length,
          mermaidSvg: document.querySelectorAll('.weibei-mermaid-render svg').length,
          mermaidPlaceholder: document.body.textContent.includes('渲染器未安装完成') ? 1 : 0,
          mermaidText: document.querySelector('.weibei-mermaid-render')?.textContent || '',
          mermaidSourceOpacity: getComputedStyle(document.querySelector('.weibei-mermaid-block') || document.body).opacity,
          mathInline: document.querySelectorAll('span[data-type="math_inline"], .math-inline, .katex').length,
          mathInlineBackground: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body).backgroundColor,
          mathInlineContainerColor: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body).color,
          mathInlineContainerFontSize: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body).fontSize,
          mathInlineKatexColor: getComputedStyle(document.querySelector('span[data-type="math_inline"] > .katex, .math-inline > .katex') || document.body).color,
          mathInlineKatexFontSize: getComputedStyle(document.querySelector('span[data-type="math_inline"] > .katex, .math-inline > .katex') || document.body).fontSize,
          mathInlineDirectTextNodes: (() => {
            const node = document.querySelector('span[data-type="math_inline"], .math-inline');
            if (!node) return -1;
            return Array.from(node.childNodes).filter((child) => child.nodeType === Node.TEXT_NODE && child.nodeValue.trim()).length;
          })(),
          mathInlineSourceChildrenVisible: (() => {
            const node = document.querySelector('span[data-type="math_inline"], .math-inline');
            if (!node) return false;
            return Array.from(node.children).some((child) => {
              if (child.classList.contains('katex')) return false;
              const style = getComputedStyle(child);
              return style.display !== 'none' && style.visibility !== 'hidden' && style.opacity !== '0';
            });
          })(),
          mathInlinePseudoBefore: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body, '::before').content,
          mathInlinePseudoAfter: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body, '::after').content,
          mathInlineMathMLHidden: (() => {
            const mathML = document.querySelector('span[data-type="math_inline"] .katex-mathml, .math-inline .katex-mathml');
            if (!mathML) return false;
            const style = getComputedStyle(mathML);
            return style.position === 'absolute' && style.overflow === 'hidden' && (style.clipPath !== 'none' || style.clip !== 'auto');
          })(),
          mathBlock: document.querySelectorAll('div[data-type="math_block"], .math-block, .katex-display').length,
          rawMathArtifacts: document.querySelectorAll('[class*="weibei-raw-math"]').length,
          rawMathPlainText: (() => {
            const root = document.querySelector('.ProseMirror');
            if (!root) return 0;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              const parent = node.parentElement;
              if (!node.nodeValue.includes('$text^*$')) continue;
              if (parent?.closest('[data-type="math_inline"], .math-inline')) continue;
              count += 1;
            }
            return count;
          })(),
          foldedCallout: document.querySelector('blockquote.weibei-callout')?.getAttribute('data-callout-fold') || '',
          calloutTitle: document.querySelector('blockquote.weibei-callout')?.getAttribute('data-callout-title') || '',
          calloutHeadingVisible: (() => {
            const heading = document.querySelector('blockquote.weibei-callout .weibei-callout-heading');
            if (!heading) return false;
            const style = getComputedStyle(heading);
            return style.opacity !== '0' && style.fontSize !== '0px' && heading.textContent.includes('可编辑标题');
          })(),
          calloutMarkerHidden: (() => {
            const marker = document.querySelector('blockquote.weibei-callout .weibei-callout-heading .weibei-callout-marker');
            if (!marker) return false;
            const style = getComputedStyle(marker);
            return style.color === 'rgba(0, 0, 0, 0)' && style.fontSize === '0px';
          })(),
          quoteCalloutTitle: document.querySelector('blockquote.weibei-callout-quote')?.getAttribute('data-callout-title') || '',
          quoteCalloutText: document.querySelector('blockquote.weibei-callout-quote')?.textContent || '',
          quoteCalloutCount: document.querySelectorAll('blockquote.weibei-callout-quote').length,
          quoteCalloutMarkerVisible: (() => {
            const marker = document.querySelector('blockquote.weibei-callout-quote .weibei-callout-marker');
            if (!marker) return true;
            const style = getComputedStyle(marker);
            return style.visibility !== 'hidden'
              || Array.from(marker.getClientRects()).some((rect) => rect.width > 0.5 || rect.height > 0.5);
          })(),
          quoteCalloutMarkerHidden: (() => {
            const marker = document.querySelector('blockquote.weibei-callout-quote .weibei-callout-marker');
            if (!marker) return false;
            const style = getComputedStyle(marker);
            return style.display === 'inline-block'
              && style.color === 'rgba(0, 0, 0, 0)'
              && style.visibility === 'hidden'
              && style.fontSize === '0px'
              && style.width === '0px'
              && marker.getBoundingClientRect().width === 0;
          })(),
          visibleBareCalloutMarkers: (() => {
            const root = document.querySelector('.ProseMirror');
            if (!root) return -1;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              if (!/\\[![A-Za-z]/.test(node.nodeValue || '')) continue;
              const parent = node.parentElement;
              if (parent?.closest('code, pre')) continue;
              if (parent?.closest('.weibei-callout-marker')) continue;
              if (!parent?.closest('blockquote.weibei-callout')) continue;
              const style = getComputedStyle(parent);
              const visible = style.display !== 'none'
                && style.visibility !== 'hidden'
                && style.opacity !== '0'
                && style.color !== 'rgba(0, 0, 0, 0)'
                && parseFloat(style.fontSize || '0') > 0;
              if (visible) count += 1;
            }
            return count;
          })(),
          visibleRawCalloutMarkers: (() => {
            const root = document.querySelector('.ProseMirror');
            if (!root) return -1;
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              if (!/\\[![A-Za-z]/.test(node.nodeValue || '')) continue;
              const parent = node.parentElement;
              if (parent?.closest('code, pre')) continue;
              if (parent?.closest('.weibei-callout-marker')) continue;
              const style = getComputedStyle(parent);
              const visible = style.display !== 'none'
                && style.visibility !== 'hidden'
                && style.opacity !== '0'
                && style.color !== 'rgba(0, 0, 0, 0)'
                && parseFloat(style.fontSize || '0') > 0;
              if (visible) count += 1;
            }
            return count;
          })(),
          cleanedCalloutSelection: (() => {
            if (!window.WeiBeiEditor.selectFirstTextForCheck('[!quote] 选区摘录')) return '__missing__';
            return window.WeiBeiEditor.selectedTextForCheck();
          })(),
          customCalloutType: document.querySelector('blockquote.weibei-callout-custom')?.getAttribute('data-callout') || '',
          customCalloutFold: document.querySelector('blockquote.weibei-callout-custom')?.getAttribute('data-callout-fold') || '',
          customCalloutTitle: document.querySelector('blockquote.weibei-callout-custom')?.getAttribute('data-callout-title') || '',
          customCalloutText: document.querySelector('blockquote.weibei-callout-custom')?.textContent || '',
          customCalloutMarkerVisible: (() => {
            const marker = document.querySelector('blockquote.weibei-callout-custom .weibei-callout-marker');
            if (!marker) return true;
            const style = getComputedStyle(marker);
            return style.visibility !== 'hidden'
              || Array.from(marker.getClientRects()).some((rect) => rect.width > 0.5 || rect.height > 0.5);
          })(),
          customCalloutMarkerHidden: (() => {
            const marker = document.querySelector('blockquote.weibei-callout-custom .weibei-callout-marker');
            if (!marker) return false;
            const style = getComputedStyle(marker);
            return style.display === 'inline-block'
              && style.color === 'rgba(0, 0, 0, 0)'
              && style.visibility === 'hidden'
              && style.fontSize === '0px'
              && style.width === '0px'
              && marker.getBoundingClientRect().width === 0;
          })(),
          inlineCodeSyntaxDecorations: document.querySelectorAll('code .weibei-wikilink, code .weibei-highlight, code .weibei-comment, code .weibei-tag, code .weibei-html-break-source').length,
          inlineCodeSyntaxText: Array.from(document.querySelectorAll('code'))
            .map((node) => node.textContent || '')
            .find((text) => text.includes('[[不是链接]]')) || ''
        }))();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("Obsidian decoration check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("Obsidian decoration check returned \(String(describing: value))")
                return
            }
            if result["wikilinkText"] as? String != "理论别名" {
                self.fail("alias wikilink did not display alias")
                return
            }
            if result["inlineFootnoteText"] as? String != "行内脚注内容"
                || (result["inlineFootnotes"] as? Int ?? 0) < 1 {
                self.fail("inline footnote was not decorated")
                return
            }
            for key in ["comments", "tags", "blockIds", "embeds", "sourceReferences", "mermaid"] {
                if (result[key] as? Int ?? 0) < 1 {
                    self.fail("missing Obsidian decoration: \(key)")
                    return
                }
            }
            if !(result["sourceReferenceTitle"] as? String ?? "").hasPrefix("打开来源：") {
                self.fail("source reference title should be localized in Chinese mode")
                return
            }
            if (result["bracketSourceReferences"] as? Int ?? 0) < 3
                || result["bracketSourceTitle"] as? String != "打开来源：利率章节" {
                self.fail("bracket source references were not decorated as native source references")
                return
            }
            if (result["editableInteractiveBlocks"] as? Int ?? -1) != 0
                || result["editableInteractiveSourceVisible"] as? Bool != true {
                self.fail("interactive fenced blocks should stay as editable source text while editing")
                return
            }
            if (result["comments"] as? Int ?? 0) < 2 {
                self.fail("block comment was not decorated")
                return
            }
            if result["commentsWeak"] as? Bool != true {
                self.fail("Obsidian comments should be weakly visible, not compete with body text")
                return
            }
            if result["frontmatterTitle"] as? String != "属性" {
                self.fail("frontmatter panel title should follow the current Chinese interface language: \(result["frontmatterTitle"] as? String ?? "__missing__")")
                return
            }
            if (result["hardBreaks"] as? Int ?? 0) < 1 {
                self.fail("HTML break syntax was not normalized into a real editor line break")
                return
            }
            if (result["noteEmbedLinks"] as? Int ?? 0) < 1 {
                self.fail("note embed was not keyboard/click activatable")
                return
            }
            if (result["mermaidSvg"] as? Int ?? 0) < 1 || (result["mermaidPlaceholder"] as? Int ?? 0) > 0 {
                self.fail("Mermaid block did not render to SVG: \(result["mermaidText"] as? String ?? "")")
                return
            }
            if let opacityText = result["mermaidSourceOpacity"] as? String,
               (Double(opacityText) ?? 0) < 0.7 {
                self.fail("Mermaid source block is too faint to edit: \(opacityText)")
                return
            }
            if (result["mathInline"] as? Int ?? 0) < 1 {
                self.fail("inline math did not render as a math node")
                return
            }
            if result["mathInlineBackground"] as? String != "rgba(0, 0, 0, 0)" {
                self.fail("inline math should not render as a filled source block")
                return
            }
            if result["mathInlineContainerColor"] as? String != "rgba(0, 0, 0, 0)" {
                self.fail("inline math container should hide raw source text")
                return
            }
            if result["mathInlineContainerFontSize"] as? String != "0px" {
                self.fail("inline math source container should collapse raw source font size")
                return
            }
            if result["mathInlineKatexColor"] as? String == "rgba(0, 0, 0, 0)" {
                self.fail("inline math rendered KaTeX should remain visible")
                return
            }
            if result["mathInlineKatexFontSize"] as? String == "0px" {
                self.fail("inline math rendered KaTeX should keep readable font size")
                return
            }
            if (result["mathInlineDirectTextNodes"] as? Int ?? 1) > 0 {
                self.fail("inline math should not render raw source text beside KaTeX")
                return
            }
            if result["mathInlineSourceChildrenVisible"] as? Bool == true {
                self.fail("inline math source child should not occupy layout beside KaTeX")
                return
            }
            if result["mathInlinePseudoBefore"] as? String != "none"
                || result["mathInlinePseudoAfter"] as? String != "none" {
                self.fail("inline math should not render source pseudo-elements")
                return
            }
            if result["mathInlineMathMLHidden"] as? Bool != true {
                self.fail("inline math MathML should be visually hidden")
                return
            }
            if (result["mathBlock"] as? Int ?? 0) < 1 {
                self.fail("block math did not render as a math node")
                return
            }
            if (result["rawMathArtifacts"] as? Int ?? 0) > 0 {
                self.fail("raw inline math fallback artifacts should not be rendered")
                return
            }
            if (result["rawMathPlainText"] as? Int ?? 0) > 0 {
                self.fail("inline math source remained visible as plain text")
                return
            }
            if result["foldedCallout"] as? String != "-" {
                self.fail("callout folded marker was not recognized")
                return
            }
            if result["calloutTitle"] as? String != "可编辑标题" {
                self.fail("callout title swallowed body text")
                return
            }
            if result["calloutHeadingVisible"] as? Bool != true {
                self.fail("callout title should stay visible and editable in writing mode")
                return
            }
            if result["calloutMarkerHidden"] as? Bool != true {
                self.fail("callout source marker should not remain visible in writing mode")
                return
            }
            if result["quoteCalloutTitle"] as? String != "选区摘录" {
                self.fail("quote callout title should be kept without exposing the source marker")
                return
            }
            if !(result["quoteCalloutText"] as? String ?? "").contains("利率是资金使用价格的表达。") {
                self.fail("quote callout body text disappeared")
                return
            }
            if (result["quoteCalloutCount"] as? Int ?? 0) < 2 {
                self.fail("nested quote callout was not recognized")
                return
            }
            if result["quoteCalloutMarkerHidden"] as? Bool != true {
                self.fail("quote callout marker should collapse in writing and preview surfaces")
                return
            }
            if result["quoteCalloutMarkerVisible"] as? Bool == true {
                self.fail("quote callout marker should not have visible boxes")
                return
            }
            if (result["visibleBareCalloutMarkers"] as? Int ?? -1) != 0 {
                self.fail("callout source markers should not leak as visible bare text")
                return
            }
            if (result["visibleRawCalloutMarkers"] as? Int ?? -1) != 0 {
                self.fail("nested callout source markers should not leak as visible text")
                return
            }
            let cleanedCalloutSelection = result["cleanedCalloutSelection"] as? String ?? ""
            if cleanedCalloutSelection == "__missing__"
                || cleanedCalloutSelection.contains("[!quote]")
                || !cleanedCalloutSelection.contains("选区摘录") {
                self.fail("callout control marker leaked into selected text: \(cleanedCalloutSelection)")
                return
            }
            if result["customCalloutType"] as? String != "attention" {
                self.fail("unknown Obsidian callout type was not recognized")
                return
            }
            if result["customCalloutFold"] as? String != "+" {
                self.fail("unknown Obsidian callout fold marker was not preserved")
                return
            }
            if result["customCalloutTitle"] as? String != "自定义标题" {
                self.fail("unknown Obsidian callout title was not preserved")
                return
            }
            if !(result["customCalloutText"] as? String ?? "").contains("自定义 Callout 不应该漏出源标记。") {
                self.fail("unknown Obsidian callout body disappeared")
                return
            }
            if result["customCalloutMarkerHidden"] as? Bool != true {
                self.fail("unknown Obsidian callout marker should collapse")
                return
            }
            if result["customCalloutMarkerVisible"] as? Bool == true {
                self.fail("unknown Obsidian callout marker should not have visible boxes")
                return
            }
            if (result["inlineCodeSyntaxDecorations"] as? Int ?? -1) != 0
                || !(result["inlineCodeSyntaxText"] as? String ?? "").contains("[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />") {
                self.fail("inline code should not receive WeiBei Markdown syntax decorations")
                return
            }
            self.validateFrontmatterLanguageCycle(completion: completion)
        }
    }

    private func validateFrontmatterLanguageCycle(completion: @escaping () -> Void) {
        let script = """
        (() => {
          const read = () => [
            document.querySelector('.frontmatter-title')?.textContent || '',
            document.querySelector('.weibei-inline-footnote')?.getAttribute('title') || '',
            document.querySelector('.weibei-wikilink')?.getAttribute('title') || '',
            document.querySelector('.weibei-embed-note')?.textContent || '',
            document.querySelector('.weibei-embed-note')?.getAttribute('title') || '',
            document.querySelector('.weibei-source-reference')?.getAttribute('title') || ''
          ].join('::');
          const initial = read();
          window.WeiBeiEditor.setInterfaceLanguage('en');
          const english = read();
          window.WeiBeiEditor.setInterfaceLanguage('zh-Hans');
          const restored = read();
          return [initial, english, restored].join('|');
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("frontmatter language switch check threw \(error.localizedDescription)")
                return
            }
            guard let raw = value as? String else {
                self.fail("frontmatter panel title should refresh when switching interface languages: \(String(describing: value))")
                return
            }
            let phases = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard phases.count == 3,
                  phases[0].hasPrefix("属性::行内脚注："),
                  phases[1].hasPrefix("Properties::Inline footnote:"),
                  phases[1].contains("::Open or create note:"),
                  phases[1].contains("::Embed:"),
                  phases[1].contains("::Open source:"),
                  phases[2].hasPrefix("属性::行内脚注："),
                  phases[2].contains("::嵌入："),
                  phases[2].contains("::打开来源：") else {
                self.fail("web editor chrome labels should refresh when switching interface languages: \(raw)")
                return
            }
            completion()
        }
    }

    private func validateReadOnlyInkstoneDecorations(completion: @escaping () -> Void) {
        webView.setFrameSize(NSSize(width: 360, height: 720))
        let prepare = """
        window.WeiBeiEditor.setTheme('inkstone');
        window.WeiBeiEditor.setEditable(false);
        """
        webView.evaluateJavaScript(prepare) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("read-only inkstone setup threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.inspectReadOnlyInkstone(completion: completion)
            }
        }
    }

    private func inspectReadOnlyInkstone(completion: @escaping () -> Void) {
        let script = """
        (() => {
          const root = document.querySelector('.ProseMirror');
          const quote = document.querySelector('blockquote.weibei-callout-quote');
          const marker = quote?.querySelector('.weibei-callout-marker');
          const heading = quote?.querySelector('.weibei-callout-heading');
          const textNodeWalker = document.createTreeWalker(root || document.body, NodeFilter.SHOW_TEXT);
          let visibleBareMarkers = 0;
          let node;
          while ((node = textNodeWalker.nextNode())) {
            if (!/\\[![A-Za-z]/.test(node.nodeValue || '')) continue;
            const parent = node.parentElement;
            if (parent?.closest('.weibei-callout-marker')) continue;
            if (!parent?.closest('blockquote.weibei-callout')) continue;
            const style = getComputedStyle(parent);
            const visible = style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.opacity !== '0'
              && style.color !== 'rgba(0, 0, 0, 0)'
              && parseFloat(style.fontSize || '0') > 0;
            if (visible) visibleBareMarkers += 1;
          }
          const markerStyle = marker ? getComputedStyle(marker) : null;
          const headingStyle = heading ? getComputedStyle(heading) : null;
          const sampleText = quote?.querySelector('p:last-child') || quote || root || document.body;
          const sampleColor = getComputedStyle(sampleText).color;
          const folded = document.querySelector('blockquote.weibei-callout[data-callout-fold="-"]');
          const quiz = document.querySelector('.weibei-interactive[data-kind="quiz"]');
          const reveal = document.querySelector('.weibei-interactive[data-kind="reveal"]');
          const initialInteractiveRoots = Array.from(document.querySelectorAll('.weibei-interactive'));
          const initialInteractiveStatuses = initialInteractiveRoots.map((node) => node.querySelector(':scope > .weibei-interactive-status'));
          const initialFamilyNames = new Set(initialInteractiveRoots.map((node) => node.dataset.family || ''));
          const initialStatusCount = initialInteractiveStatuses.filter(Boolean).length;
          const initialHiddenStatusCount = initialInteractiveStatuses.filter((node) => node?.hidden).length;
          const initialGroupedRootCount = initialInteractiveRoots.filter((node) => node.getAttribute('role') === 'group' && (node.getAttribute('aria-label') || '').length > 0).length;
          const safeText = Array.from(document.querySelectorAll('.weibei-interactive')).find((node) => node.textContent.includes('<img src=x onerror=alert(1)>'));
          const unsafeImage = document.querySelector('.weibei-interactive img');
          const hiddenInteractiveSources = Array.from(document.querySelectorAll('pre[data-language="weibei-interactive"], .weibei-interactive-source')).filter((node) => {
            const style = getComputedStyle(node);
            return style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0' || node.getBoundingClientRect().height < 1;
          }).length;
          const interactiveSources = document.querySelectorAll('pre[data-language="weibei-interactive"], .weibei-interactive-source').length;
          const quizOption = quiz?.querySelector('button.weibei-interactive-option');
          const quizExplanation = quiz?.querySelector('.weibei-interactive-explanation');
          const quizExplanationHiddenBefore = quizExplanation?.hidden ?? true;
          quizOption?.click();
          const revealToggle = reveal?.querySelector('.weibei-interactive-reveal-toggle');
          const revealBody = reveal?.querySelector('.weibei-interactive-reveal-content');
          const revealHiddenBefore = revealBody?.hidden ?? true;
          revealToggle?.click();
          const chart = document.querySelector('.weibei-interactive[data-kind="chart"]');
          const barChart = document.querySelector('.weibei-interactive[data-kind="chart"][data-chart-type="bar"]');
          const scatterChart = document.querySelector('.weibei-interactive[data-kind="chart"][data-chart-type="scatter"]');
          const areaChart = document.querySelector('.weibei-interactive[data-kind="chart"][data-chart-type="area"]');
          const chartLegendButtons = chart?.querySelectorAll('button.weibei-chart-legend-item') || [];
          chartLegendButtons[0]?.click();
          const chartLineMark = chart?.querySelector('.weibei-chart-line');
          chartLineMark?.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
          const chartInspectorOnHover = chart?.querySelector('.weibei-chart-inspector')?.textContent || '';
          chartLineMark?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
          const chartMarkLocked = chartLineMark?.classList.contains('is-inspected') || false;
          const functionPlot = document.querySelector('.weibei-interactive[data-kind="function-plot"]');
          const parameterLab = document.querySelector('.weibei-interactive[data-kind="parameter-lab"]');
          const inverseLab = document.querySelector('.weibei-interactive[data-kind="parameter-lab"][data-function-family="inverse"]');
          const parameterSlider = parameterLab?.querySelector('input.weibei-parameter-slider');
          const parameterCurve = parameterLab?.querySelector('.weibei-parameter-curve');
          const parameterPathBefore = parameterCurve?.getAttribute('d') || '';
          if (parameterSlider) {
            parameterSlider.value = '2';
            parameterSlider.dispatchEvent(new Event('input', { bubbles: true }));
          }
          const parameterPathAfter = parameterCurve?.getAttribute('d') || '';
          const textStudy = document.querySelector('.weibei-interactive[data-kind="text-study"]');
          const textTabs = textStudy?.querySelectorAll('button.weibei-interactive-tab') || [];
          textTabs[0]?.dispatchEvent(new KeyboardEvent('keydown', { key: 'End', bubbles: true, cancelable: true }));
          const textEndSelected = textTabs[textTabs.length - 1]?.getAttribute('aria-selected') || '';
          textTabs[textTabs.length - 1]?.dispatchEvent(new KeyboardEvent('keydown', { key: 'Home', bubbles: true, cancelable: true }));
          const textHomeSelected = textTabs[0]?.getAttribute('aria-selected') || '';
          textTabs[1]?.click();
          const designCompare = document.querySelector('.weibei-interactive[data-kind="design-compare"]');
          const designTabs = designCompare?.querySelectorAll('button.weibei-interactive-tab') || [];
          designTabs[1]?.click();
          const palette = document.querySelector('.weibei-interactive[data-kind="palette"]');
          const paletteSwatches = palette?.querySelectorAll('button.weibei-palette-swatch') || [];
          paletteSwatches[1]?.click();
          const studyBoard = document.querySelector('.weibei-interactive[data-kind="study-board"]');
          const relationshipMap = document.querySelector('.weibei-interactive[data-kind="relationship-map"]');
          const timeline = document.querySelector('.weibei-interactive[data-kind="timeline"]');
          studyBoard?.querySelectorAll('button.weibei-study-board-item')[1]?.click();
          relationshipMap?.querySelectorAll('button.weibei-relationship-node')[3]?.click();
          timeline?.querySelectorAll('button.weibei-timeline-event')[2]?.click();
          const matrix = document.querySelector('.weibei-interactive[data-kind="comparison-matrix"]');
          const matrixButtons = matrix?.querySelectorAll('button.weibei-comparison-column-button') || [];
          matrixButtons[1]?.click();
          const matrixFocusedAfterClick = matrix?.dataset.focusedColumn || '';
          const matrixFocusedCellsAfterClick = matrix?.querySelectorAll('.weibei-comparison-cell.is-focused-column').length || 0;
          matrixButtons[1]?.click();
          const matrixFocusClearedAfterSecondClick = matrix?.dataset.focusedColumn === undefined;
          matrixButtons[2]?.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
          const matrixFocusedAfterKeyboard = matrix?.dataset.focusedColumn || '';
          const annotated = document.querySelector('.weibei-interactive[data-kind="annotated-passage"]');
          const annotationEntries = annotated?.querySelectorAll('button.weibei-annotation-entry') || [];
          annotationEntries[1]?.click();
          const derivation = document.querySelector('.weibei-interactive[data-kind="derivation-steps"]');
          derivation?.querySelectorAll('button.weibei-interactive-action')[1]?.click();
          const flashcards = document.querySelector('.weibei-interactive[data-kind="flashcards"]');
          const flashcard = flashcards?.querySelector('button.weibei-flashcard');
          const flashcardFront = flashcards?.querySelector('.weibei-flashcard-front');
          const flashcardBack = flashcards?.querySelector('.weibei-flashcard-back');
          const flashcardFrontVisibleBefore = flashcardFront ? getComputedStyle(flashcardFront).visibility !== 'hidden' : false;
          const flashcardBackHiddenBefore = flashcardBack ? getComputedStyle(flashcardBack).visibility === 'hidden' : false;
          flashcard?.click();
          const flashcardFrontHiddenAfter = flashcardFront ? getComputedStyle(flashcardFront).visibility === 'hidden' : false;
          const flashcardBackVisibleAfter = flashcardBack ? getComputedStyle(flashcardBack).visibility !== 'hidden' : false;
          const sequence = document.querySelector('.weibei-interactive[data-kind="sequence-builder"]');
          const sequenceItems = sequence?.querySelectorAll('button.weibei-sequence-item') || [];
          sequenceItems.forEach((item) => item.click());
          sequence?.querySelectorAll('button.weibei-interactive-action')[0]?.click();
          const scenario = document.querySelector('.weibei-interactive[data-kind="scenario-lab"]');
          scenario?.querySelectorAll('button.weibei-scenario-option')[1]?.click();
          const evidence = document.querySelector('.weibei-interactive[data-kind="evidence-board"]');
          evidence?.querySelector('button.weibei-evidence-filter[data-stance="challenge"]')?.click();
          evidence?.querySelector('button.weibei-evidence-item[data-stance="challenge"]')?.click();
          const spectrum = document.querySelector('.weibei-interactive[data-kind="spectrum"]');
          spectrum?.querySelectorAll('button.weibei-spectrum-marker')[1]?.click();
          const decision = document.querySelector('.weibei-interactive[data-kind="decision-path"]');
          decision?.querySelectorAll('button.weibei-decision-choice')[1]?.click();
          const expectedNewKinds = [
            'unit-workbench', 'reaction-balance', 'algorithm-trace', 'language-aligner',
            'argument-map', 'visual-analysis', 'spatial-layers', 'pathway-lab'
          ];
          const expectedNewBlockIDs = expectedNewKinds.map((kind) => `cross-${kind}-v1`);
          const newRoots = expectedNewBlockIDs.map((blockID) => document.querySelector(`.weibei-interactive[data-block-id="${blockID}"]`));
          const unitWorkbench = newRoots[0];
          const reactionBalance = newRoots[1];
          const algorithmTrace = newRoots[2];
          const languageAligner = newRoots[3];
          const argumentMap = newRoots[4];
          const visualAnalysis = newRoots[5];
          const spatialLayers = newRoots[6];
          const pathwayLab = newRoots[7];
          const initiallyVisibleEmptyDetailCount = [
            unitWorkbench?.querySelector('.weibei-unit-detail'),
            reactionBalance?.querySelector('.weibei-reaction-source'),
            languageAligner?.querySelector('.weibei-language-note'),
            argumentMap?.querySelector('.weibei-argument-detail'),
            visualAnalysis?.querySelector('.weibei-visual-analysis-detail'),
            spatialLayers?.querySelector('.weibei-spatial-detail'),
          ].filter((node) => (
            node
              && node.textContent.trim().length === 0
              && getComputedStyle(node).display !== 'none'
          )).length;
          unitWorkbench?.querySelectorAll('button.weibei-unit-variable')[0]?.click();
          const currentReactionBalance = () => document.querySelector('.weibei-interactive[data-block-id="cross-reaction-balance-v1"]');
          const reactionLedger = () => Array.from(currentReactionBalance()?.querySelectorAll('.weibei-reaction-element') || [])
            .map((row) => row.textContent.trim()).join('|');
          const reactionLedgerBefore = reactionLedger();
          const reactionPlus = currentReactionBalance()?.querySelectorAll('button.weibei-reaction-plus')[0];
          reactionPlus?.click();
          const reactionLedgerAfterPlus = reactionLedger();
          const reactionMinus = currentReactionBalance()?.querySelectorAll('button.weibei-reaction-minus')[0];
          reactionMinus?.click();
          const reactionLedgerAfterMinus = reactionLedger();
          const algorithmButtons = algorithmTrace?.querySelectorAll('button.weibei-algorithm-action') || [];
          const algorithmPreviousDisabledInitially = algorithmButtons[0]?.disabled ?? false;
          const algorithmNextDisabledInitially = algorithmButtons[1]?.disabled ?? true;
          algorithmButtons[1]?.click();
          const algorithmActiveLineAfterNext = algorithmTrace?.querySelector('.weibei-algorithm-line.is-active')?.textContent || '';
          const algorithmProgressAfterNext = algorithmTrace?.querySelector('.weibei-algorithm-progress')?.textContent || '';
          const algorithmPreviousDisabledInMiddle = algorithmButtons[0]?.disabled ?? true;
          const algorithmNextDisabledInMiddle = algorithmButtons[1]?.disabled ?? true;
          algorithmButtons[1]?.click();
          const algorithmNextDisabledAtEnd = algorithmButtons[1]?.disabled ?? false;
          const algorithmPreviousDisabledAtEnd = algorithmButtons[0]?.disabled ?? true;
          algorithmButtons[0]?.click();
          languageAligner?.querySelectorAll('button.weibei-language-pair')[1]?.click();
          argumentMap?.querySelectorAll('button.weibei-argument-node')[2]?.click();
          visualAnalysis?.querySelectorAll('button.weibei-visual-analysis-zone-button')[1]?.click();
          spatialLayers?.querySelectorAll('button.weibei-spatial-feature')[1]?.click();
          pathwayLab?.querySelectorAll('button.weibei-pathway-state')[1]?.click();
          const newButtons = newRoots.flatMap((root) => Array.from(root?.querySelectorAll('button') || []));
          const newButtonsNative = newButtons.every((button) => button instanceof HTMLButtonElement && button.type === 'button');
          const newButtonsFocusable = newButtons.every((button) => {
            button.focus();
            return document.activeElement === button;
          });
          const newNonNativeControls = newRoots.flatMap((root) => Array.from(root?.querySelectorAll('[aria-pressed], [aria-expanded]') || []))
            .filter((control) => !(control instanceof HTMLButtonElement)).length;
          const newSVGs = newRoots.flatMap((root) => Array.from(root?.querySelectorAll('svg') || []));
          const newSVGsAccessible = newSVGs.every((svg) => svg.getAttribute('role') === 'img' && (svg.getAttribute('aria-label') || '').trim().length > 0);
          const sourceFenceNodes = Array.from(document.querySelectorAll('pre[data-language="weibei-interactive"], .weibei-interactive-source'));
          const isHidden = (node) => {
            const style = getComputedStyle(node);
            return style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0' || node.getBoundingClientRect().height < 1;
          };
          const newHiddenSourceFences = expectedNewBlockIDs.filter((blockID) => sourceFenceNodes.some((node) => (
            node.textContent.includes(`"blockId":"${blockID}"`) && isHidden(node)
          ))).length;
          const visibleRejectedSource = (blockID) => Array.from(document.querySelectorAll('pre, code, .weibei-code-block')).some((node) => (
            !node.closest('.weibei-interactive')
              && node.textContent.includes(`"blockId":"${blockID}"`)
              && !isHidden(node)
          ));
          const maliciousVisual = document.querySelector('.weibei-interactive[data-block-id="rejected-visual-fields-v1"]');
          const maliciousVisualLeakedDOM = !!maliciousVisual?.querySelector('img, iframe, object, embed, script')
            || Array.from(maliciousVisual?.querySelectorAll('[href], [src]') || []).some((node) => /javascript:|visual-url|visual-html/i.test(`${node.getAttribute('href') || ''} ${node.getAttribute('src') || ''}`))
            || /javascript:|<img|visual-url|visual-html/i.test(maliciousVisual?.textContent || '');
          const renderedKinds = new Set(Array.from(document.querySelectorAll('.weibei-interactive')).map((node) => node.dataset.kind || ''));
          const interactiveStatuses = Array.from(document.querySelectorAll('.weibei-interactive-status'));
          const visibleInteractiveStatuses = interactiveStatuses.filter((node) => !node.hidden && node.textContent.trim().length > 0).length;
          const statusRoleCount = interactiveStatuses.filter((node) => node.getAttribute('role') === 'status' && node.getAttribute('aria-live') === 'polite').length;
          const interactiveOverflowCount = Array.from(document.querySelectorAll('.weibei-interactive')).filter((node) => (
            node.scrollWidth > node.clientWidth + 1
          )).length;
          const interactiveOverflowKinds = Array.from(document.querySelectorAll('.weibei-interactive')).filter((node) => (
            node.scrollWidth > node.clientWidth + 1
          )).map((node) => `${node.dataset.kind}:${node.scrollWidth}/${node.clientWidth}`).join('|');
          const visibleFoldChildren = () => Array.from(folded?.children || []).filter((child) => {
            const style = getComputedStyle(child);
            return style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.opacity !== '0'
              && child.getBoundingClientRect().height > 0.5;
          }).length;
          const foldedVisibleBefore = visibleFoldChildren();
          folded?.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          const foldedVisibleAfter = visibleFoldChildren();
          return {
            editable: document.body.dataset.editable || '',
            theme: document.documentElement.dataset.weibeiTheme || '',
            markerHidden: markerStyle
              ? markerStyle.color === 'rgba(0, 0, 0, 0)' && markerStyle.fontSize === '0px'
              : false,
            headingHidden: headingStyle ? headingStyle.display === 'none' : false,
            visibleBareMarkers,
            sampleColor,
            foldedVisibleBefore,
            foldedVisibleAfter,
            quizPrompt: quiz?.querySelector('.weibei-interactive-prompt')?.textContent || '',
            quizOptions: quiz?.querySelectorAll('button.weibei-interactive-option').length || 0,
            quizSourceReference: quiz?.querySelector('.weibei-source-reference[data-source-reference="来源：利率章节"]')?.textContent || '',
            quizExplanationHiddenBefore,
            quizExplanationVisibleAfter: quizExplanation?.hidden === false,
            quizCorrectAfter: quizOption?.classList.contains('is-correct') || false,
            quizPressedAfter: quizOption?.getAttribute('aria-pressed') || '',
            revealTitle: reveal?.querySelector('.weibei-interactive-title')?.textContent || '',
            revealContent: reveal?.querySelector('.weibei-interactive-reveal-content')?.textContent || '',
            revealHiddenBefore,
            revealVisibleAfter: revealBody?.hidden === false,
            revealExpandedAfter: revealToggle?.getAttribute('aria-expanded') || '',
            chartTitle: chart?.querySelector('.weibei-interactive-title')?.textContent || '',
            chartSeries: chart?.querySelectorAll('.weibei-chart-series').length || 0,
            chartHasSVG: !!chart?.querySelector('svg.weibei-interactive-chart-svg'),
            chartAxisLabels: Array.from(chart?.querySelectorAll('.weibei-interactive-axis-label') || []).map((node) => node.textContent).join('|'),
            chartSourceReferences: Array.from(chart?.querySelectorAll('.weibei-interactive-source-link') || []).map((node) => node.dataset.sourceReference || '').join('|'),
            chartLegendItems: chart?.querySelectorAll('.weibei-chart-legend-item').length || 0,
            chartFirstSeriesVisible: chartLegendButtons[0]?.getAttribute('aria-pressed') || '',
            chartInspector: chart?.querySelector('.weibei-chart-inspector')?.textContent || '',
            chartInspectorOnHover,
            chartMarkLocked,
            chartTickLabels: chart?.querySelectorAll('.weibei-chart-tick-label').length || 0,
            barMarks: barChart?.querySelectorAll('rect.weibei-chart-bar').length || 0,
            scatterMarks: scatterChart?.querySelectorAll('circle.weibei-chart-point').length || 0,
            areaMarks: areaChart?.querySelectorAll('path.weibei-chart-area').length || 0,
            chartMarkTitles: document.querySelectorAll('.weibei-chart-line title, .weibei-chart-area title, .weibei-chart-bar title, .weibei-chart-point title').length,
            chartFocusableMarks: document.querySelectorAll('.weibei-chart-bar[tabindex="0"], .weibei-chart-point[tabindex="0"], .weibei-chart-line[tabindex="0"], .weibei-chart-area[tabindex="0"]').length,
            functionTitle: functionPlot?.querySelector('.weibei-interactive-title')?.textContent || '',
            functionCurves: functionPlot?.querySelectorAll('.weibei-function-curve').length || 0,
            functionFormula: functionPlot?.querySelector('.weibei-function-formula')?.textContent || '',
            parameterFamily: parameterLab?.dataset.functionFamily || '',
            parameterControls: parameterLab?.querySelectorAll('input.weibei-parameter-slider').length || 0,
            parameterValue: parameterLab?.querySelector('.weibei-parameter-value')?.textContent || '',
            parameterChanged: parameterPathBefore.length > 0 && parameterPathAfter.length > 0 && parameterPathBefore !== parameterPathAfter,
            inverseCurveSegments: (inverseLab?.querySelector('.weibei-parameter-curve')?.getAttribute('d')?.match(/M/g) || []).length,
            textTabCount: textTabs.length,
            textTabListRole: textStudy?.querySelector('.weibei-interactive-tabs')?.getAttribute('role') || '',
            textTabControls: Array.from(textTabs).filter((tab) => (tab.getAttribute('aria-controls') || '').length > 0).length,
            textEndSelected,
            textHomeSelected,
            textActiveCopy: textStudy?.querySelector('.weibei-text-study-copy')?.textContent || '',
            textActiveNote: textStudy?.querySelector('.weibei-text-study-note')?.textContent || '',
            textHighlightCount: textStudy?.querySelectorAll('mark.weibei-text-highlight').length || 0,
            designTabCount: designTabs.length,
            designActiveTitle: designCompare?.querySelector('.weibei-design-preview-title')?.textContent || '',
            designTreatment: designCompare?.querySelector('.weibei-design-preview')?.dataset.treatment || '',
            designToneColor: (() => {
              const preview = designCompare?.querySelector('.weibei-design-preview');
              return preview ? getComputedStyle(preview, '::before').backgroundColor : '';
            })(),
            paletteSwatchCount: paletteSwatches.length,
            paletteSelectedValue: palette?.querySelector('.weibei-palette-detail')?.dataset.value || '',
            palettePreviewText: palette?.querySelector('.weibei-palette-preview')?.textContent || '',
            paletteFirstTextColor: paletteSwatches[0] ? getComputedStyle(paletteSwatches[0]).color : '',
            studyBoardLayout: studyBoard?.dataset.layout || '',
            studyBoardTreatment: studyBoard?.dataset.treatment || '',
            studyBoardMetrics: studyBoard?.querySelectorAll('.weibei-study-board-metric').length || 0,
            studyBoardItems: studyBoard?.querySelectorAll('.weibei-study-board-item').length || 0,
            studyBoardInlineSource: studyBoard?.querySelector('.weibei-interactive-inline-source')?.dataset.sourceReference || '',
            studyBoardActiveItems: studyBoard?.querySelectorAll('.weibei-study-board-item.is-active').length || 0,
            relationshipLayout: relationshipMap?.dataset.layout || '',
            relationshipNodes: relationshipMap?.querySelectorAll('.weibei-relationship-node').length || 0,
            relationshipCenter: relationshipMap?.querySelector('.weibei-relationship-node[data-role="center"]')?.textContent || '',
            relationshipEdges: relationshipMap?.querySelectorAll('.weibei-relationship-edge').length || 0,
            relationshipInlineSource: relationshipMap?.querySelector('.weibei-interactive-inline-source')?.dataset.sourceReference || '',
            relationshipActiveNodes: relationshipMap?.querySelectorAll('.weibei-relationship-node.is-active').length || 0,
            timelineEvents: timeline?.querySelectorAll('.weibei-timeline-event').length || 0,
            timelineInlineSource: timeline?.querySelector('.weibei-interactive-inline-source')?.dataset.sourceReference || '',
            timelineOverflow: timeline ? timeline.scrollWidth > timeline.clientWidth + 1 : true,
            timelineActiveEvents: timeline?.querySelectorAll('.weibei-timeline-event.is-active').length || 0,
            matrixColumns: matrix?.querySelectorAll('thead th').length ? (matrix.querySelectorAll('thead th').length - 1) : 0,
            matrixRows: matrix?.querySelectorAll('tbody tr').length || 0,
            matrixFocusedAfterClick,
            matrixFocusedCellsAfterClick,
            matrixFocusClearedAfterSecondClick,
            matrixFocusedAfterKeyboard,
            matrixEmphasisCells: matrix?.querySelectorAll('.weibei-comparison-cell.is-emphasized').length || 0,
            annotatedEntries: annotationEntries.length,
            annotatedActiveMarks: annotated?.querySelectorAll('.weibei-annotated-mark.is-active').length || 0,
            annotatedActiveEntries: annotated?.querySelectorAll('.weibei-annotation-entry.is-active').length || 0,
            derivationSteps: derivation?.querySelectorAll('.weibei-derivation-step').length || 0,
            derivationVisibleSteps: Array.from(derivation?.querySelectorAll('.weibei-derivation-step') || []).filter((node) => !node.hidden).length,
            derivationProgress: derivation?.querySelector('.weibei-derivation-progress')?.textContent || '',
            flashcardCount: flashcards?.querySelector('.weibei-flashcard-status')?.textContent || '',
            flashcardFlipped: flashcard?.classList.contains('is-flipped') || false,
            flashcardFrontVisibleBefore,
            flashcardBackHiddenBefore,
            flashcardFrontHiddenAfter,
            flashcardBackVisibleAfter,
            sequenceItems: sequenceItems.length,
            sequenceAnswerItems: sequence?.querySelectorAll('.weibei-sequence-answer .weibei-sequence-item').length || 0,
            sequenceCorrect: sequence?.querySelector('.weibei-sequence-feedback')?.classList.contains('is-correct') || false,
            scenarioResult: scenario?.querySelector('.weibei-scenario-result-title')?.textContent || '',
            scenarioActiveOptions: scenario?.querySelectorAll('.weibei-scenario-option.is-active').length || 0,
            evidenceChallengeVisible: Array.from(evidence?.querySelectorAll('.weibei-evidence-item[data-stance="challenge"]') || []).filter((node) => !node.hidden).length,
            evidenceOtherVisible: Array.from(evidence?.querySelectorAll('.weibei-evidence-item:not([data-stance="challenge"])') || []).filter((node) => !node.hidden).length,
            evidenceDetail: evidence?.querySelector('.weibei-evidence-detail-body')?.textContent || '',
            spectrumPoints: spectrum?.querySelectorAll('.weibei-spectrum-marker').length || 0,
            spectrumActivePoints: spectrum?.querySelectorAll('.weibei-spectrum-marker.is-active').length || 0,
            spectrumDetail: spectrum?.querySelector('.weibei-spectrum-detail-body')?.textContent || '',
            decisionCurrentTitle: decision?.querySelector('.weibei-decision-node-title')?.textContent || '',
            decisionTrail: decision?.querySelector('.weibei-decision-trail')?.textContent || '',
            registeredKindCount: renderedKinds.size,
            initialFamilyCount: initialFamilyNames.size,
            initialFamilyNames: Array.from(initialFamilyNames).sort().join('|'),
            initialStatusCount,
            initialHiddenStatusCount,
            initialGroupedRootCount,
            visibleInteractiveStatuses,
            statusRoleCount,
            allExpectedNewKindsRendered: expectedNewKinds.every((kind) => renderedKinds.has(kind)),
            newRenderedBlockCount: newRoots.filter(Boolean).length,
            newRenderedBlockIDs: newRoots.map((root) => root?.dataset.blockId || '').join('|'),
            newHiddenSourceFences,
            newSourceLinkBlocks: newRoots.filter((root) => !!root?.querySelector('.weibei-source-reference[data-source-reference]')).length,
            initiallyVisibleEmptyDetailCount,
            unitVariablePressed: unitWorkbench?.querySelectorAll('button.weibei-unit-variable')[0]?.getAttribute('aria-pressed') || '',
            unitDetail: unitWorkbench?.querySelector('.weibei-unit-detail')?.textContent || '',
            reactionLedgerBefore,
            reactionLedgerAfterPlus,
            reactionLedgerAfterMinus,
            algorithmPreviousDisabledInitially,
            algorithmNextDisabledInitially,
            algorithmActiveLineAfterNext,
            algorithmProgressAfterNext,
            algorithmPreviousDisabledInMiddle,
            algorithmNextDisabledInMiddle,
            algorithmPreviousDisabledAtEnd,
            algorithmNextDisabledAtEnd,
            languagePressed: languageAligner?.querySelectorAll('button.weibei-language-pair')[1]?.getAttribute('aria-pressed') || '',
            languageNote: languageAligner?.querySelector('.weibei-language-note')?.textContent || '',
            argumentPressed: argumentMap?.querySelectorAll('button.weibei-argument-node')[2]?.getAttribute('aria-pressed') || '',
            argumentDetail: argumentMap?.querySelector('.weibei-argument-detail')?.textContent || '',
            visualPressed: visualAnalysis?.querySelectorAll('button.weibei-visual-analysis-zone-button')[1]?.getAttribute('aria-pressed') || '',
            visualActiveZones: visualAnalysis?.querySelectorAll('.weibei-visual-analysis-zone.is-active').length || 0,
            spatialPressed: spatialLayers?.querySelectorAll('button.weibei-spatial-feature')[1]?.getAttribute('aria-pressed') || '',
            spatialDetail: spatialLayers?.querySelector('.weibei-spatial-detail')?.textContent || '',
            pathwayPressed: pathwayLab?.querySelectorAll('button.weibei-pathway-state')[1]?.getAttribute('aria-pressed') || '',
            pathwayActiveNodes: Array.from(pathwayLab?.querySelectorAll('button.weibei-pathway-node[aria-pressed="true"]') || []).map((node) => node.dataset.nodeId || '').join('|'),
            newButtonCount: newButtons.length,
            newButtonsNative,
            newButtonsFocusable,
            newNonNativeControls,
            newSVGCount: newSVGs.length,
            newSVGsAccessible,
            maliciousVisualRendered: !!maliciousVisual,
            maliciousVisualLeakedDOM,
            maliciousVisualSourceVisible: visibleRejectedSource('rejected-visual-fields-v1'),
            rejectedSpatialRendered: !!document.querySelector('.weibei-interactive[data-block-id="rejected-spatial-bounds-v1"]'),
            rejectedSpatialSourceVisible: visibleRejectedSource('rejected-spatial-bounds-v1'),
            rejectedPathwayRendered: !!document.querySelector('.weibei-interactive[data-block-id="rejected-pathway-node-v1"]'),
            rejectedPathwaySourceVisible: visibleRejectedSource('rejected-pathway-node-v1'),
            interactiveBlockIDs: Array.from(document.querySelectorAll('.weibei-interactive')).filter((node) => (node.dataset.blockId || '').length > 0).length,
            interactiveBlockCount: document.querySelectorAll('.weibei-interactive').length,
            futureProtocolRendered: Array.from(document.querySelectorAll('.weibei-interactive')).some((node) => node.textContent.includes('未来协议不得渲染')),
            interactiveOverflowCount,
            interactiveOverflowKinds,
            safeTextRendered: !!safeText,
            unsafeImageRendered: !!unsafeImage,
            hiddenInteractiveSources,
            interactiveSources
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("read-only inkstone check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("read-only inkstone check returned \(String(describing: value))")
                return
            }
            if result["editable"] as? String != "false" || result["theme"] as? String != "inkstone" {
                self.fail("read-only inkstone state was not applied: \(result)")
                return
            }
            if result["markerHidden"] as? Bool != true || result["headingHidden"] as? Bool != true {
                self.fail("read-only callout heading or marker leaked: \(result)")
                return
            }
            if (result["visibleBareMarkers"] as? Int ?? -1) != 0 {
                self.fail("read-only callout source marker leaked as visible text")
                return
            }
            if (result["foldedVisibleBefore"] as? Int ?? -1) != 0
                || (result["foldedVisibleAfter"] as? Int ?? 0) < 1 {
                self.fail("read-only folded callout should start collapsed and expand on click: \(result)")
                return
            }
            if (result["sampleColor"] as? String ?? "").contains("255, 255, 255") {
                self.fail("read-only inkstone text fell back to pure white")
                return
            }
            if result["quizPrompt"] as? String != "名义利率和实际利率的区别是什么？"
                || (result["quizOptions"] as? Int ?? 0) != 3
                || result["quizSourceReference"] as? String != "材料：利率章节" {
                self.fail("read-only quiz interactive block did not render safely: \(result)")
                return
            }
            if result["quizExplanationHiddenBefore"] as? Bool != true
                || result["quizExplanationVisibleAfter"] as? Bool != true
                || result["quizCorrectAfter"] as? Bool != true
                || result["quizPressedAfter"] as? String != "true" {
                self.fail("interactive quiz did not reveal and mark the selected answer: \(result)")
                return
            }
            if result["revealTitle"] as? String != "先自己想"
                || !(result["revealContent"] as? String ?? "").contains("名义利率是票面看到的利率") {
                self.fail("read-only reveal interactive block did not render safely: \(result)")
                return
            }
            if result["revealHiddenBefore"] as? Bool != true
                || result["revealVisibleAfter"] as? Bool != true
                || result["revealExpandedAfter"] as? String != "true" {
                self.fail("interactive reveal block did not expand on click: \(result)")
                return
            }
            if result["chartTitle"] as? String != "利率与通胀"
                || (result["chartSeries"] as? Int ?? 0) != 2
                || result["chartHasSVG"] as? Bool != true
                || !(result["chartAxisLabels"] as? String ?? "").contains("时期|百分比")
                || result["chartSourceReferences"] as? String != "来源：利率章节|来源：新笔记 17"
                || (result["chartLegendItems"] as? Int ?? 0) != 2
                || (result["chartTickLabels"] as? Int ?? 0) < 4 {
                self.fail("interactive chart did not render bounded SVG series and axes: \(result)")
                return
            }
            if result["chartFirstSeriesVisible"] as? String != "false"
                || (result["chartInspector"] as? String ?? "").isEmpty
                || (result["chartInspectorOnHover"] as? String ?? "").isEmpty
                || result["chartMarkLocked"] as? Bool != true {
                self.fail("interactive chart legend and mark inspection did not respond: \(result)")
                return
            }
            if (result["barMarks"] as? Int ?? 0) != 3
                || (result["scatterMarks"] as? Int ?? 0) != 3
                || (result["areaMarks"] as? Int ?? 0) != 1
                || (result["chartMarkTitles"] as? Int ?? 0) < 8
                || (result["chartFocusableMarks"] as? Int ?? 0) != 9 {
                self.fail("bar, scatter, and area charts must use distinct bounded marks: \(result)")
                return
            }
            if result["functionTitle"] as? String != "二次函数曲线"
                || (result["functionCurves"] as? Int ?? 0) != 1
                || !(result["functionFormula"] as? String ?? "").contains("y = x^2") {
                self.fail("function plot did not render sampled curves without executable formulas: \(result)")
                return
            }
            if result["parameterFamily"] as? String != "quadratic"
                || (result["parameterControls"] as? Int ?? 0) != 3
                || result["parameterValue"] as? String != "2"
                || result["parameterChanged"] as? Bool != true {
                self.fail("parameter lab slider did not update the allow-listed function family: \(result)")
                return
            }
            if (result["inverseCurveSegments"] as? Int ?? 0) < 2 {
                self.fail("inverse parameter lab must break the curve at its vertical asymptote: \(result)")
                return
            }
            if (result["textTabCount"] as? Int ?? 0) != 2
                || result["textTabListRole"] as? String != "tablist"
                || (result["textTabControls"] as? Int ?? 0) != 2
                || result["textEndSelected"] as? String != "true"
                || result["textHomeSelected"] as? String != "true"
                || !(result["textActiveCopy"] as? String ?? "").contains("数字金融可能")
                || !(result["textActiveNote"] as? String ?? "").contains("降低无证据")
                || (result["textHighlightCount"] as? Int ?? 0) < 2 {
                self.fail("text study did not switch variants and preserve bounded highlights: \(result)")
                return
            }
            if (result["designTabCount"] as? Int ?? 0) != 2
                || result["designActiveTitle"] as? String != "先看购买力"
                || result["designTreatment"] as? String != "annotated"
                || result["designToneColor"] as? String != "rgb(143, 176, 143)" {
                self.fail("design comparison did not switch safe built-in preview treatments: \(result)")
                return
            }
            if (result["paletteSwatchCount"] as? Int ?? 0) != 4
                || result["paletteSelectedValue"] as? String != "#1D1814"
                || !(result["palettePreviewText"] as? String ?? "").contains("利率是资金")
                || result["paletteFirstTextColor"] as? String == "rgb(255, 255, 255)" {
                self.fail("palette explorer did not select a bounded color and update the preview: \(result)")
                return
            }
            if result["studyBoardLayout"] as? String != "lanes"
                || result["studyBoardTreatment"] as? String != "annotated"
                || (result["studyBoardMetrics"] as? Int ?? 0) != 2
                || (result["studyBoardItems"] as? Int ?? 0) != 3
                || result["studyBoardInlineSource"] as? String != "来源：新笔记 17"
                || (result["studyBoardActiveItems"] as? Int ?? 0) != 1 {
                self.fail("study board did not render bounded layout/treatment/items with clickable item sources: \(result)")
                return
            }
            if result["relationshipLayout"] as? String != "radial"
                || (result["relationshipNodes"] as? Int ?? 0) != 4
                || !(result["relationshipCenter"] as? String ?? "").contains("利率")
                || (result["relationshipEdges"] as? Int ?? 0) != 3
                || result["relationshipInlineSource"] as? String != "来源：新笔记 17"
                || (result["relationshipActiveNodes"] as? Int ?? 0) != 1 {
                self.fail("relationship map did not render radial center, edges, and clickable source nodes: \(result)")
                return
            }
            if (result["timelineEvents"] as? Int ?? 0) != 3
                || result["timelineInlineSource"] as? String != "来源：新笔记 17"
                || result["timelineOverflow"] as? Bool != false
                || (result["timelineActiveEvents"] as? Int ?? 0) != 1 {
                self.fail("timeline should render source-aware events and collapse to a non-overflowing 360pt column: \(result)")
                return
            }
            if (result["matrixColumns"] as? Int ?? 0) != 3
                || (result["matrixRows"] as? Int ?? 0) != 3
                || result["matrixFocusedAfterClick"] as? String != "1"
                || (result["matrixFocusedCellsAfterClick"] as? Int ?? 0) != 3
                || result["matrixFocusClearedAfterSecondClick"] as? Bool != true
                || result["matrixFocusedAfterKeyboard"] as? String != "2"
                || (result["matrixEmphasisCells"] as? Int ?? 0) != 2 {
                self.fail("comparison matrix column focus, keyboard path, or row constraints failed: \(result)")
                return
            }
            if (result["annotatedEntries"] as? Int ?? 0) != 2
                || (result["annotatedActiveMarks"] as? Int ?? 0) != 1
                || (result["annotatedActiveEntries"] as? Int ?? 0) != 1 {
                self.fail("annotated passage did not synchronize inline marks and margin notes: \(result)")
                return
            }
            if (result["derivationSteps"] as? Int ?? 0) != 3
                || (result["derivationVisibleSteps"] as? Int ?? 0) != 2
                || result["derivationProgress"] as? String != "2 / 3" {
                self.fail("derivation steps did not reveal progressively: \(result)")
                return
            }
            if !(result["flashcardCount"] as? String ?? "").contains("1 / 2")
                || result["flashcardFlipped"] as? Bool != true
                || result["flashcardFrontVisibleBefore"] as? Bool != true
                || result["flashcardBackHiddenBefore"] as? Bool != true
                || result["flashcardFrontHiddenAfter"] as? Bool != true
                || result["flashcardBackVisibleAfter"] as? Bool != true {
                self.fail("flashcards did not reveal exactly one readable face while preserving their bounded deck state: \(result)")
                return
            }
            if (result["sequenceItems"] as? Int ?? 0) != 3
                || (result["sequenceAnswerItems"] as? Int ?? 0) != 3
                || result["sequenceCorrect"] as? Bool != true {
                self.fail("sequence builder did not place and verify the complete order: \(result)")
                return
            }
            if result["scenarioResult"] as? String != "差额扩大"
                || (result["scenarioActiveOptions"] as? Int ?? 0) != 1 {
                self.fail("scenario lab did not switch to the pre-enumerated outcome: \(result)")
                return
            }
            if (result["evidenceChallengeVisible"] as? Int ?? 0) != 1
                || (result["evidenceOtherVisible"] as? Int ?? -1) != 0
                || !(result["evidenceDetail"] as? String ?? "").contains("短期预期变化") {
                self.fail("evidence board did not filter and inspect the selected stance: \(result)")
                return
            }
            if (result["spectrumPoints"] as? Int ?? 0) != 2
                || (result["spectrumActivePoints"] as? Int ?? 0) != 1
                || !(result["spectrumDetail"] as? String ?? "").contains("真实资金成本") {
                self.fail("spectrum did not expose the selected point detail: \(result)")
                return
            }
            if result["decisionCurrentTitle"] as? String != "使用实际利率"
                || !(result["decisionTrail"] as? String ?? "").contains("你要观察什么") {
                self.fail("decision path did not move through the selected finite branch: \(result)")
                return
            }
            if (result["registeredKindCount"] as? Int ?? 0) != 28
                || result["allExpectedNewKindsRendered"] as? Bool != true
                || (result["newRenderedBlockCount"] as? Int ?? 0) != 8
                || result["newRenderedBlockIDs"] as? String != [
                    "cross-unit-workbench-v1", "cross-reaction-balance-v1", "cross-algorithm-trace-v1", "cross-language-aligner-v1",
                    "cross-argument-map-v1", "cross-visual-analysis-v1", "cross-spatial-layers-v1", "cross-pathway-lab-v1",
                ].joined(separator: "|")
                || (result["newHiddenSourceFences"] as? Int ?? 0) != 8 {
                self.fail("all 28 interactive kinds must register and the eight cross-discipline fixtures must replace their source fences: \(result)")
                return
            }
            if (result["initialFamilyCount"] as? Int ?? 0) != 6
                || result["initialFamilyNames"] as? String != "atlas|lab|planning|practice|reading|reasoning"
                || (result["initialStatusCount"] as? Int ?? -1) != (result["interactiveBlockCount"] as? Int ?? -2)
                || (result["initialHiddenStatusCount"] as? Int ?? -1) != (result["interactiveBlockCount"] as? Int ?? -2)
                || (result["initialGroupedRootCount"] as? Int ?? -1) != (result["interactiveBlockCount"] as? Int ?? -2)
                || (result["statusRoleCount"] as? Int ?? -1) != (result["interactiveBlockCount"] as? Int ?? -2)
                || (result["visibleInteractiveStatuses"] as? Int ?? 0) < 18 {
                self.fail("interactive roots must share six semantic families and expose stable local action status without claiming mastery: \(result)")
                return
            }
            if (result["newSourceLinkBlocks"] as? Int ?? 0) != 8 {
                self.fail("every cross-discipline block must expose at least one source link: \(result)")
                return
            }
            if (result["initiallyVisibleEmptyDetailCount"] as? Int ?? -1) != 0 {
                self.fail("empty cross-discipline detail regions must stay hidden until the learner selects something: \(result)")
                return
            }
            if result["unitVariablePressed"] as? String != "true"
                || !(result["unitDetail"] as? String ?? "").contains("120 km") {
                self.fail("unit workbench did not select a real variable and expose its unit detail: \(result)")
                return
            }
            if (result["reactionLedgerBefore"] as? String ?? "").isEmpty
                || result["reactionLedgerBefore"] as? String == result["reactionLedgerAfterPlus"] as? String
                || result["reactionLedgerBefore"] as? String != result["reactionLedgerAfterMinus"] as? String {
                self.fail("reaction coefficient plus/minus did not update and restore the atom ledger: \(result)")
                return
            }
            if result["algorithmPreviousDisabledInitially"] as? Bool != true
                || result["algorithmNextDisabledInitially"] as? Bool != false
                || !(result["algorithmActiveLineAfterNext"] as? String ?? "").contains("sum += value")
                || result["algorithmProgressAfterNext"] as? String != "2 / 3"
                || result["algorithmPreviousDisabledInMiddle"] as? Bool != false
                || result["algorithmNextDisabledInMiddle"] as? Bool != false
                || result["algorithmPreviousDisabledAtEnd"] as? Bool != false
                || result["algorithmNextDisabledAtEnd"] as? Bool != true {
                self.fail("algorithm trace did not highlight the next line or bound previous/next controls correctly: \(result)")
                return
            }
            if result["languagePressed"] as? String != "true"
                || !(result["languageNote"] as? String ?? "").contains("may 保留")
                || result["argumentPressed"] as? String != "true"
                || !(result["argumentDetail"] as? String ?? "").contains("数据偏差")
                || result["visualPressed"] as? String != "true"
                || (result["visualActiveZones"] as? Int ?? 0) != 1
                || result["spatialPressed"] as? String != "true"
                || !(result["spatialDetail"] as? String ?? "").contains("东村")
                || result["pathwayPressed"] as? String != "true"
                || result["pathwayActiveNodes"] as? String != "pyruvate|atp" {
                self.fail("language, argument, visual, spatial, or pathway selection state did not stay synchronized through aria-pressed: \(result)")
                return
            }
            if (result["newButtonCount"] as? Int ?? 0) < 20
                || result["newButtonsNative"] as? Bool != true
                || result["newButtonsFocusable"] as? Bool != true
                || (result["newNonNativeControls"] as? Int ?? -1) != 0 {
                self.fail("cross-discipline controls must use focusable native buttons: \(result)")
                return
            }
            if (result["newSVGCount"] as? Int ?? 0) != 2
                || result["newSVGsAccessible"] as? Bool != true {
                self.fail("visual and spatial SVG surfaces must expose role img and a non-empty aria-label: \(result)")
                return
            }
            if result["maliciousVisualRendered"] as? Bool != false
                || result["maliciousVisualLeakedDOM"] as? Bool != false
                || result["maliciousVisualSourceVisible"] as? Bool != true
                || result["rejectedSpatialRendered"] as? Bool != false
                || result["rejectedSpatialSourceVisible"] as? Bool != true
                || result["rejectedPathwayRendered"] as? Bool != false
                || result["rejectedPathwaySourceVisible"] as? Bool != true {
                self.fail("unsafe visual fields, out-of-bounds spatial points, or unknown pathway nodes crossed the protocol boundary: \(result)")
                return
            }
            if (result["interactiveBlockIDs"] as? Int ?? -1) != (result["interactiveBlockCount"] as? Int ?? -2) {
                self.fail("every rendered interactive block must have a stable block id: \(result)")
                return
            }
            let interactionKinds = Set(self.interactiveActions.compactMap { $0["kind"] as? String })
            let expandedKinds: Set<String> = [
                "annotated-passage", "derivation-steps", "flashcards", "sequence-builder",
                "scenario-lab", "evidence-board", "spectrum", "decision-path",
                "unit-workbench", "reaction-balance", "algorithm-trace", "language-aligner",
                "argument-map", "visual-analysis", "spatial-layers", "pathway-lab",
            ]
            if !expandedKinds.isSubset(of: interactionKinds)
                || self.interactiveActions.count < 18
                || self.interactiveActions.contains(where: {
                    ($0["blockId"] as? String ?? "").isEmpty
                        || ($0["kind"] as? String ?? "").isEmpty
                        || ($0["action"] as? String ?? "").isEmpty
                        || $0["detail"] as? String == nil
                }) {
                self.fail("interactive actions did not cross the WebKit bridge with stable bounded context: \(self.interactiveActions)")
                return
            }
            let crossDisciplineActions = [
                ("unit-workbench", "inspect-variable", "cross-unit-workbench-v1"),
                ("reaction-balance", "increase-coefficient", "cross-reaction-balance-v1"),
                ("algorithm-trace", "next-step", "cross-algorithm-trace-v1"),
                ("language-aligner", "select-pair", "cross-language-aligner-v1"),
                ("argument-map", "select-node", "cross-argument-map-v1"),
                ("visual-analysis", "select-zone", "cross-visual-analysis-v1"),
                ("spatial-layers", "select-feature", "cross-spatial-layers-v1"),
                ("pathway-lab", "select-state", "cross-pathway-lab-v1"),
            ]
            if crossDisciplineActions.contains(where: { kind, action, blockID in
                !self.interactiveActions.contains(where: {
                    $0["kind"] as? String == kind
                        && $0["action"] as? String == action
                        && $0["blockId"] as? String == blockID
                        && !($0["source"] as? String ?? "").isEmpty
                })
            }) {
                self.fail("cross-discipline interactions did not return kind/action/blockId/source through the WebKit bridge: \(self.interactiveActions)")
                return
            }
            if (result["interactiveOverflowCount"] as? Int ?? -1) != 0 {
                self.fail("interactive components overflowed the 360pt narrow answer column: \(result)")
                return
            }
            if result["futureProtocolRendered"] as? Bool == true {
                self.fail("unknown interactive protocol versions must fall back to visible source instead of rendering")
                return
            }
            if result["safeTextRendered"] as? Bool != true || result["unsafeImageRendered"] as? Bool == true {
                self.fail("interactive block content must render as text, never executable HTML: \(result)")
                return
            }
            if (result["interactiveSources"] as? Int ?? 0) < 1
                || (result["hiddenInteractiveSources"] as? Int ?? 0) < (result["interactiveSources"] as? Int ?? 0) {
                self.fail("read-only interactive source fences should be hidden behind the rendered component: \(result)")
                return
            }
            self.webView.setFrameSize(NSSize(width: 960, height: 720))
            completion()
        }
    }

    private func validateRenderedImageSource(completion: @escaping () -> Void) {
        let script = """
        Array.from(document.querySelectorAll('.ProseMirror img')).map((image) => image.getAttribute('src') || image.src || '').join('\\n')
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("image source check threw \(error.localizedDescription)")
                return
            }
            guard let rawSrc = value as? String else {
                self.fail("local markdown image did not use controlled scheme: \(String(describing: value))")
                return
            }
            let src = rawSrc.trimmingCharacters(in: .whitespacesAndNewlines)
            guard src.hasPrefix("weibeiimage://image") else {
                self.fail("local markdown image did not use controlled scheme: \(src)")
                return
            }
            completion()
        }
    }

    private func validateWikiLinkActivation() {
        let script = """
        const link = document.querySelector('.weibei-wikilink');
        if (!link) throw new Error('missing wikilink decoration');
        link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("wikilink click threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论" else {
                    self.fail("wikilink did not send canonical title to native bridge: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateHeadingWikiLinkActivation()
            }
        }
    }

    private func validateHeadingWikiLinkActivation() {
        activatedWikiTitle = nil
        let script = """
        (() => {
        const links = Array.from(document.querySelectorAll('.weibei-wikilink'));
        const link = links.find((node) => node.getAttribute('data-wikilink-target') === '货币理论#利率');
        if (!link) {
          return { ok: false, targets: links.map((node) => node.getAttribute('data-wikilink-target')).join('|') };
        }
        link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        return { ok: true, targets: links.map((node) => node.getAttribute('data-wikilink-target')).join('|') };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("heading wikilink click threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any], result["ok"] as? Bool == true else {
                self.fail("missing heading wikilink decoration: \((value as? [String: Any])?["targets"] as? String ?? String(describing: value))")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论#利率" else {
                    self.fail("heading wikilink did not keep target fragment: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateEmbedWikiLinkActivation()
            }
        }
    }

    private func validateEmbedWikiLinkActivation() {
        activatedWikiTitle = nil
        let script = """
        (() => {
          const embed = document.querySelector('.weibei-embed-note[data-wikilink-target="货币理论#利率"]');
          if (!embed) return false;
          embed.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("note embed click threw \(error.localizedDescription)")
                return
            }
            guard value as? Bool == true else {
                self.fail("missing clickable note embed")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedWikiTitle == "货币理论#利率" else {
                    self.fail("note embed did not keep target fragment: \(String(describing: self.activatedWikiTitle))")
                    return
                }
                self.validateBracketSourceReferenceActivation()
            }
        }
    }

    private func validateBracketSourceReferenceActivation() {
        activatedSourceReference = nil
        let script = """
        (() => {
          const link = document.querySelector('.weibei-source-reference[data-source-reference="来源：利率章节"]');
          if (!link) return false;
          link.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
          return true;
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("bracket source reference click threw \(error.localizedDescription)")
                return
            }
            guard value as? Bool == true else {
                self.fail("missing clickable bracket source reference")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard self.activatedSourceReference == "来源：利率章节" else {
                    self.fail("bracket source reference did not send canonical raw source reference: \(String(describing: self.activatedSourceReference))")
                    return
                }
                self.validateReadOnlyImagePaste()
            }
        }
    }

    private func validateReadOnlyImagePaste() {
        let script = """
        window.WeiBeiEditor.setEditable(false);
        const editor = document.querySelector('.ProseMirror');
        const data = new DataTransfer();
        data.items.add(new File([new Uint8Array([1, 2, 3])], 'readonly.png', { type: 'image/png' }));
        const event = new ClipboardEvent('paste', { bubbles: true, cancelable: true, clipboardData: data });
        editor.dispatchEvent(event);
        window.WeiBeiEditor.setEditable(true);
        event.defaultPrevented;
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("readonly paste check threw \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.attachmentRequests != 0 {
                    self.fail("readonly image paste should not request attachment save")
                    return
                }
                self.validateSelectionReplacement()
            }
        }
    }

    private func validateSelectionReplacement() {
        replaceFirst("可追问", with: "已改写") { [weak self] in
            guard let self else { return }
            self.replaceFirst("温和洞察", with: "Agent 洞察") { [weak self] in
                guard let self else { return }
                self.webView.evaluateJavaScript("window.WeiBeiEditor.getMarkdown()") { [weak self] value, error in
                    guard let self else { return }
                    if let error {
                        self.fail("getMarkdown after replacement threw \(error.localizedDescription)")
                        return
                    }
                    guard let markdown = value as? String else {
                        self.fail("replacement markdown did not return text")
                        return
                    }
                    let tableReplaced = markdown.contains("| Agent | 已改写 |")
                        || (markdown.contains("| Agent") && markdown.contains("已改写"))
                    if !tableReplaced {
                        self.fail("table selection replacement was not serialized back to markdown")
                        return
                    }
                    if !markdown.contains("> [!note]- 可编辑标题") || !markdown.contains("Agent 洞察") {
                        self.fail("callout selection replacement was not serialized back to markdown")
                        return
                    }
                    self.validateAgentPatch()
                }
            }
        }
    }

    private func replaceFirst(_ needle: String, with replacement: String, completion: @escaping () -> Void) {
        let script = """
        if (!window.WeiBeiEditor.selectFirstTextForCheck(\(json(needle)))) {
          throw new Error("missing selection target: \(needle)");
        }
        window.WeiBeiEditor.replaceSelection(\(json(replacement)));
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.fail("replaceSelection threw \(error.localizedDescription)")
                return
            }
            completion()
        }
    }

    private func validateAgentPatch() {
        let patch = "\n## Agent 整理建议\n补充一条可写回的整理建议。"
        webView.evaluateJavaScript("window.WeiBeiEditor.applyAgentPatch(\(json(patch)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("applyAgentPatch threw \(error.localizedDescription)")
                return
            }
            self.webView.evaluateJavaScript("window.WeiBeiEditor.getMarkdown()") { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after patch threw \(error.localizedDescription)")
                    return
                }
                guard let markdown = value as? String else {
                    self.fail("patched markdown did not return text")
                    return
                }
                if !markdown.contains("Agent 整理建议") || !markdown.contains("补充一条可写回的整理建议") {
                    self.fail("Agent patch was not serialized back to markdown")
                    return
                }
                self.validateCommandInsertion()
            }
        }
    }

    private func validateCommandInsertion() {
        let snippet = "\n$$\n\\frac{x}{y}\n$$\n"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("insertMarkdown command threw \(error.localizedDescription)")
                return
            }
            self.webView.evaluateJavaScript("window.WeiBeiEditor.getMarkdown()") { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after insert command threw \(error.localizedDescription)")
                    return
                }
                guard let markdown = value as? String else {
                    self.fail("inserted markdown did not return text")
                    return
                }
                if !markdown.contains("\\frac{x}{y}") || !markdown.contains("$$") {
                    self.fail("insertMarkdown command did not serialize block math correctly")
                    return
                }
                self.validateCursorMarkerInsertion()
            }
        }
    }

    private func validateCursorMarkerInsertion() {
        let snippet = "\n> [!note] 标题\n>\n> {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}}\n"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("insertMarkdown cursor marker command threw \(error.localizedDescription)")
                return
            }
            let script = """
            (() => ({
              markdown: window.WeiBeiEditor.getMarkdown(),
              selectedText: window.WeiBeiEditor.selectedTextForCheck()
            }))()
            """
            self.webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after cursor marker insert threw \(error.localizedDescription)")
                    return
                }
                guard let result = value as? [String: Any],
                      let markdown = result["markdown"] as? String,
                      let selectedText = result["selectedText"] as? String else {
                    self.fail("cursor marker inserted markdown did not return text")
                    return
                }
                if markdown.contains("{{WEIBEI_CURSOR}}")
                    || markdown.contains("{{WEIBEI_SELECT_START}}")
                    || markdown.contains("{{WEIBEI_SELECT_END}}") {
                    self.fail("insertMarkdown cursor marker leaked into saved markdown")
                    return
                }
                if !markdown.contains("> [!note] 标题\n>\n> 内容") {
                    self.fail("insertMarkdown cursor marker command did not keep the callout: \(markdown)")
                    return
                }
                if selectedText.trimmingCharacters(in: .whitespacesAndNewlines) != "内容" {
                    self.fail("insertMarkdown cursor marker did not select the editable placeholder")
                    return
                }
                self.validateInlineFormulaCursorMarkerInsertion()
            }
        }
    }

    private func validateInlineFormulaCursorMarkerInsertion() {
        let snippet = "${{WEIBEI_SELECT_START}}x_i = \\frac{a}{b}{{WEIBEI_SELECT_END}}$"
        webView.evaluateJavaScript("window.WeiBeiEditor.insertMarkdown(\(json(snippet)))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.fail("inline formula marker command threw \(error.localizedDescription)")
                return
            }
            let script = """
            (() => ({
              markdown: window.WeiBeiEditor.getMarkdown(),
              selectedText: window.WeiBeiEditor.selectedTextForCheck()
            }))()
            """
            self.webView.evaluateJavaScript(script) { [weak self] value, error in
                guard let self else { return }
                if let error {
                    self.fail("getMarkdown after inline formula marker insert threw \(error.localizedDescription)")
                    return
                }
                guard let result = value as? [String: Any],
                      let markdown = result["markdown"] as? String,
                      let selectedText = result["selectedText"] as? String else {
                    self.fail("inline formula marker inserted markdown did not return text")
                    return
                }
                if markdown.contains("{{WEIBEI_SELECT_START}}")
                    || markdown.contains("{{WEIBEI_SELECT_END}}") {
                    self.fail("inline formula marker leaked into saved markdown")
                    return
                }
                if !markdown.contains("\\frac{a}{b}") || !markdown.contains("$") {
                    self.fail("inline formula marker command did not keep formula markdown: \(markdown)")
                    return
                }
                if selectedText.trimmingCharacters(in: .whitespacesAndNewlines) != "x_i = \\frac{a}{b}" {
                    self.fail("inline formula marker did not select the editable formula")
                    return
                }
                self.validateTypedInlineFormula()
            }
        }
    }

    private func validateTypedInlineFormula() {
        let script = """
        window.WeiBeiEditor.insertMarkdown("\\n\\n{{WEIBEI_CURSOR}}");
        if (!window.WeiBeiEditor.typeTextForCheck('$A^*$')) {
          throw new Error('typeTextForCheck unavailable');
        }
        (() => ({
          markdown: window.WeiBeiEditor.getMarkdown(),
          mathNodes: document.querySelectorAll('span[data-type="math_inline"], .math-inline').length,
          typedMathNode: !!document.querySelector('span[data-type="math_inline"][data-value="A^*"], .math-inline[data-value="A^*"]'),
          typedMathColor: getComputedStyle(document.querySelector('span[data-type="math_inline"][data-value="A^*"], .math-inline[data-value="A^*"]') || document.body).color,
          typedMathFontSize: getComputedStyle(document.querySelector('span[data-type="math_inline"][data-value="A^*"], .math-inline[data-value="A^*"]') || document.body).fontSize,
          typedKatexFontSize: getComputedStyle(document.querySelector('span[data-type="math_inline"][data-value="A^*"] > .katex, .math-inline[data-value="A^*"] > .katex') || document.body).fontSize,
          rawFormulaText: (() => {
            const root = document.querySelector('.ProseMirror');
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            let count = 0;
            let node;
            while ((node = walker.nextNode())) {
              const parent = node.parentElement;
              if (!node.nodeValue.includes('$A^*$')) continue;
              if (parent?.closest('[data-type="math_inline"], .math-inline')) continue;
              count += 1;
            }
            return count;
          })(),
          mathBackground: getComputedStyle(document.querySelector('span[data-type="math_inline"], .math-inline') || document.body).backgroundColor
        }))();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("typed inline formula check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any],
                  let markdown = result["markdown"] as? String else {
                self.fail("typed inline formula check did not return result")
                return
            }
            if !markdown.contains("$A^*$") {
                self.fail("typed inline formula did not serialize as Markdown math: \(markdown)")
                return
            }
            if (result["mathNodes"] as? Int ?? 0) < 1 {
                self.fail("typed inline formula did not become a math node")
                return
            }
            if result["typedMathNode"] as? Bool != true {
                self.fail("typed inline formula did not create a math node for A^*")
                return
            }
            if result["typedMathColor"] as? String != "rgba(0, 0, 0, 0)"
                || result["typedMathFontSize"] as? String != "0px" {
                self.fail("typed inline formula source container should be invisible and collapsed")
                return
            }
            if result["typedKatexFontSize"] as? String == "0px" {
                self.fail("typed inline formula rendered KaTeX should stay readable")
                return
            }
            if (result["rawFormulaText"] as? Int ?? 0) > 0 {
                self.fail("typed inline formula left a raw source text block beside KaTeX")
                return
            }
            if result["mathBackground"] as? String != "rgba(0, 0, 0, 0)" {
                self.fail("typed inline formula should not look like a filled source chip")
                return
            }
            self.validateTypedHtmlBreak()
        }
    }

    private func validateTypedHtmlBreak() {
        let script = """
        window.WeiBeiEditor.insertMarkdown("\\n\\n{{WEIBEI_CURSOR}}");
        if (!window.WeiBeiEditor.typeTextForCheck('手动换行第一行<br />第二行')) {
          throw new Error('typeTextForCheck unavailable');
        }
        window.WeiBeiEditor.getMarkdown();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("typed HTML break check threw \(error.localizedDescription)")
                return
            }
            guard let markdown = value as? String else {
                self.fail("typed HTML break check did not return markdown")
                return
            }
            guard let range = markdown.range(of: "手动换行第一行") else {
                self.fail("typed HTML break text did not serialize")
                return
            }
            let suffix = String(markdown[range.upperBound...])
            if !suffix.hasPrefix("  \n第二行")
                && !suffix.hasPrefix("  \n> 第二行")
                && !suffix.hasPrefix("\\\n第二行")
                && !suffix.hasPrefix("\\\n> 第二行")
                && !suffix.hasPrefix("\n第二行")
                && !suffix.hasPrefix("\n> 第二行") {
                self.fail("typed HTML break did not become a Markdown hard break: \(markdown)")
                return
            }
            if markdown.contains("手动换行第一行<br") {
                self.fail("typed HTML break leaked raw HTML syntax into saved markdown")
                return
            }
            self.validateTypedMarkdownShortcuts()
        }
    }

    private func validateTypedMarkdownShortcuts() {
        let script = """
        (() => {
        const cases = [
          ['## 现场标题', 'h2', '## 现场标题', '现场标题'],
          ['- 现场条目', 'li', '现场条目', '现场条目'],
          ['- [ ] 现场待办', 'li[data-item-type="task"], li', '现场待办', '现场待办'],
          ['**现场加粗**', 'strong', '**现场加粗**', '现场加粗'],
          ['~~现场删除~~', 's, del', '~~现场删除~~', '现场删除'],
          ['==现场高亮==', '.weibei-highlight', '==现场高亮==', '现场高亮'],
          ['[[现场概念|显示名]]', '.weibei-wikilink[data-wikilink-target="现场概念"]', '[[现场概念|显示名]]', '显示名']
        ];
        for (const [typed, selector, expectedMarkdown, visibleText] of cases) {
          window.WeiBeiEditor.setMarkdown('# 输入语法验收\\n');
          window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
          if (!window.WeiBeiEditor.typeTextForCheck(typed)) {
            return { ok: false, reason: 'typeTextForCheck unavailable for ' + typed };
          }
          const markdown = window.WeiBeiEditor.getMarkdown();
          const node = document.querySelector(selector);
          if (!markdown.includes(expectedMarkdown) || !node || !node.textContent.includes(visibleText)) {
            return { ok: false, reason: 'typed Markdown shortcut did not render in place: ' + typed, markdown, html: document.querySelector('.ProseMirror')?.innerHTML || '' };
          }
        }
        return { ok: true, markdown: window.WeiBeiEditor.getMarkdown() };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("typed Markdown shortcut check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("typed Markdown shortcut check did not return result")
                return
            }
            if result["ok"] as? Bool != true {
                self.fail("typed Markdown shortcut check failed: \(result)")
                return
            }
            guard let markdown = result["markdown"] as? String, markdown.contains("[[现场概念|显示名]]") else {
                self.fail("typed Markdown shortcut check did not finish: \(result)")
                return
            }
            self.validateBlockEnterExit()
        }
    }

    private func validateBlockEnterExit() {
        let script = """
        (() => {
        try {
        const cases = [
          ['\\n\\n- 项目{{WEIBEI_CURSOR}}', '退出无序列表', ['- 项目', '* 项目', '+ 项目'], '\\n\\n退出无序列表'],
          ['\\n\\n- \u{200B}{{WEIBEI_CURSOR}}', '退出视觉空白无序列表', [], '\\n\\n退出视觉空白无序列表'],
          ['\\n\\n1. 项目{{WEIBEI_CURSOR}}', '退出有序列表', ['1. 项目'], '\\n\\n退出有序列表'],
          ['\\n\\n- [ ] 待办{{WEIBEI_CURSOR}}', '退出任务列表', ['- [ ] 待办', '* [ ] 待办', '+ [ ] 待办'], '\\n\\n退出任务列表'],
          ['\\n\\n> 引用{{WEIBEI_CURSOR}}', '退出引用', ['> 引用'], '\\n\\n退出引用'],
          ['\\n\\n> [!note] 标题\\n>\\n> 内容{{WEIBEI_CURSOR}}', '退出 Callout', ['> 内容'], '\\n\\n退出 Callout']
        ];
        for (const [markdown, text, expectedBeforeOptions, expectedAfter] of cases) {
          window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
          window.WeiBeiEditor.insertMarkdown(markdown);
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for first Enter');
          }
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for second Enter');
          }
          if (!window.WeiBeiEditor.typeTextForCheck(text)) {
            throw new Error('typeTextForCheck unavailable after list exit');
          }
          const current = window.WeiBeiEditor.getMarkdown();
          if ((expectedBeforeOptions.length > 0 && !expectedBeforeOptions.some((expectedBefore) => current.includes(expectedBefore))) || !current.includes(expectedAfter)) {
            throw new Error('empty block Enter did not create a normal paragraph after the block: ' + text + '\\n' + current);
          }
          if (current.includes('\\u200B')) {
            throw new Error('empty block Enter left invisible list placeholder in markdown: ' + text + '\\n' + current);
          }
          if (current.includes('\\n- ' + text)
              || current.includes('\\n* ' + text)
              || current.includes('\\n+ ' + text)
              || current.includes('\\n1. ' + text)
              || current.includes('\\n2. ' + text)
              || current.includes('\\n- [ ] ' + text)
              || current.includes('\\n> ' + text)) {
            throw new Error('empty block Enter kept following text in the block: ' + text + '\\n' + current);
          }
        }
        const typedListCases = [
          ['- 手写项目', '手写退出无序列表', ['- 手写项目', '* 手写项目', '+ 手写项目'], ['\\n- 手写退出无序列表', '\\n* 手写退出无序列表', '\\n+ 手写退出无序列表']],
          ['1. 手写项目', '手写退出有序列表', ['1. 手写项目'], ['\\n1. 手写退出有序列表', '\\n2. 手写退出有序列表']],
          ['- [ ] 手写待办', '手写退出任务列表', ['- [ ] 手写待办', '* [ ] 手写待办', '+ [ ] 手写待办'], ['\\n- [ ] 手写退出任务列表', '\\n* [ ] 手写退出任务列表', '\\n+ [ ] 手写退出任务列表']]
        ];
        for (const [typed, after, expectedMarkers, forbiddenMarkers] of typedListCases) {
          window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
          window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
          if (!window.WeiBeiEditor.typeTextForCheck(typed)) {
            throw new Error('typeTextForCheck unavailable for typed list: ' + typed);
          }
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for typed list first Enter: ' + typed);
          }
          if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
            throw new Error('pressKeyForCheck unavailable for typed list second Enter: ' + typed);
          }
          if (!window.WeiBeiEditor.typeTextForCheck(after)) {
            throw new Error('typeTextForCheck unavailable after typed list exit: ' + typed);
          }
          const typedMarkdown = window.WeiBeiEditor.getMarkdown();
          if (!expectedMarkers.some((marker) => typedMarkdown.includes(marker))
              || !typedMarkdown.includes('\\n\\n' + after)
              || forbiddenMarkers.some((marker) => typedMarkdown.includes(marker))) {
            throw new Error('typed list Enter did not exit to a normal paragraph: ' + typed + '\\n' + typedMarkdown);
          }
          if (Array.from(document.querySelectorAll('.ProseMirror li')).some((item) => item.textContent.includes(after))) {
            throw new Error('typed list exit kept following text inside a list item: ' + typed + '\\n' + document.querySelector('.ProseMirror')?.innerHTML);
          }
        }
        window.WeiBeiEditor.setMarkdown('# 块退出验收\\n');
        window.WeiBeiEditor.insertMarkdown('\\n\\n{{WEIBEI_CURSOR}}');
        if (!window.WeiBeiEditor.typeTextForCheck('- ')) {
          throw new Error('typeTextForCheck unavailable for empty bullet shortcut');
        }
        if (!document.querySelector('.ProseMirror li')) {
          throw new Error('empty bullet shortcut did not create a real list item');
        }
        if (!window.WeiBeiEditor.pressKeyForCheck('Enter')) {
          throw new Error('pressKeyForCheck unavailable for empty bullet exit');
        }
        if (!window.WeiBeiEditor.typeTextForCheck('空项目退出列表')) {
          throw new Error('typeTextForCheck unavailable after empty bullet exit');
        }
        const emptyShortcutMarkdown = window.WeiBeiEditor.getMarkdown();
        if (!emptyShortcutMarkdown.includes('\\n\\n空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n- 空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n* 空项目退出列表')
            || emptyShortcutMarkdown.includes('\\n+ 空项目退出列表')
            || Array.from(document.querySelectorAll('.ProseMirror li')).some((item) => item.textContent.includes('空项目退出列表'))) {
          throw new Error('empty bullet shortcut Enter did not exit to a normal paragraph\\n' + emptyShortcutMarkdown + '\\n' + document.querySelector('.ProseMirror')?.innerHTML);
        }
        return { ok: true, markdown: window.WeiBeiEditor.getMarkdown() };
        } catch (error) {
          return { ok: false, reason: String(error?.message || error), stack: String(error?.stack || '') };
        }
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                self.fail("list Enter exit check threw \(error.localizedDescription)")
                return
            }
            guard let result = value as? [String: Any] else {
                self.fail("list Enter exit check did not return result")
                return
            }
            if let ok = result["ok"] as? Bool, ok == false {
                self.fail("list Enter exit check failed: \(result)")
                return
            }
            guard let markdown = result["markdown"] as? String else {
                self.fail("list Enter exit check did not return markdown: \(result)")
                return
            }
            if !markdown.contains("空项目退出列表") {
                self.fail("block Enter exit check did not finish all isolated cases: \(markdown)")
                return
            }
            self.isDone = true
        }
    }

    private func validate(_ markdown: String) {
        let checks = [
            ("table", "| 能力"),
            ("escaped table wikilink", "[[货币理论\\|理论别名]]"),
            ("task unchecked", "[ ] todo"),
            ("task checked", "[x] done"),
            ("strikethrough", "~~删除线~~"),
            ("highlight", "==重点高亮=="),
            ("alias wikilink", "[[货币理论|理论别名]]"),
            ("heading wikilink", "[[货币理论#利率]]"),
            ("block wikilink", "[[货币理论#^rate-block]]"),
            ("block id", "^rate-block"),
            ("embed image", "![[assets/weibei.svg|100]]"),
            ("embed note", "![[货币理论#利率]]"),
            ("footnote", "[^1]: 这是脚注内容。"),
            ("inline footnote", "^[行内脚注内容]"),
            ("callout", "> [!note]- 可编辑标题"),
            ("inline math", "E = mc^2"),
            ("star inline math", "A^*"),
            ("normal dollar", "$5 不应该被误伤"),
            ("plugin-rendered inline math", "$text^*$"),
            ("matrix math", "\\begin{bmatrix}"),
            ("fraction math", "\\frac{a_1}{b^2}"),
            ("mermaid", "```mermaid"),
            ("interactive quiz", "```weibei-interactive\n{\"kind\":\"quiz\""),
            ("interactive reveal", "\"kind\":\"reveal\""),
            ("interactive study board", "\"kind\":\"study-board\""),
            ("interactive relationship map", "\"kind\":\"relationship-map\""),
            ("interactive timeline", "\"kind\":\"timeline\""),
            ("interactive comparison matrix", "\"kind\":\"comparison-matrix\""),
            ("comment", "%%这是一条只在写作时弱显示的注释%%"),
            ("block comment", "%%\n这是一段块注释\n跨行也应该弱显示\n%%"),
            ("tag", "#nested/tag"),
            ("frontmatter", "course: 货币金融学"),
            ("quoted code block", "> \\#quoted-code \\$5 \\[!note] <br />"),
            ("code fence", "```swift"),
            ("inline html break code", "`<br />`"),
            ("double backtick html break code", "``内部 ` <br />``"),
            ("inline code markdown syntax", "`[[不是链接]] ==不是高亮== %%不是注释%% #not-tag <br />`"),
            ("inline code escaped syntax", "`\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]`"),
            ("escaped backtick prose syntax", "转义反引号 \\` 后面的 [[转义双链]] #escaped-tag $5"),
            ("code block html break", "<span>保留<br />源码</span>"),
            ("code block escaped syntax", "\\#literal \\[[x]] \\==x\\== \\$5 \\[!note]"),
            ("image size", "![魏碑测试图|100x80](assets/weibei.svg)")
        ]
        for (name, fragment) in checks {
            if !markdown.contains(fragment) {
                fail("missing \(name): \(fragment)\n--- markdown ---\n\(markdown)")
                return
            }
        }
        guard let htmlBreakRange = markdown.range(of: "HTML 换行第一行") else {
            fail("missing html break prefix\n--- markdown ---\n\(markdown)")
            return
        }
        let htmlBreakSuffix = String(markdown[htmlBreakRange.upperBound...])
        if !htmlBreakSuffix.hasPrefix("  \n第二行") && !htmlBreakSuffix.hasPrefix("\\\n第二行") && !htmlBreakSuffix.hasPrefix("\n第二行") {
            fail("HTML break was swallowed instead of becoming a Markdown hard break\n--- markdown ---\n\(markdown)")
            return
        }
        if markdown.contains("HTML 换行第一行第二行") || markdown.contains("HTML 换行第一行<br") {
            fail("HTML break serialized as joined text or raw HTML\n--- markdown ---\n\(markdown)")
            return
        }
    }

    private func fail(_ message: String) {
        failure = message
        isDone = true
    }
}

final class CompactPreviewHarness: NSObject, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var isDone = false
    private var failure: String?
    private var reportedHeight: Double = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let markdown = """
        名义利率与实际利率需要一起理解。[材料：利率章节]

        | 概念 | 含义 |
        | --- | --- |
        | 名义利率 | 账面数字 |
        | 实际利率 | 扣除通胀 |

        ```weibei-interactive
        {"kind":"quiz","prompt":"近似实际利率？","options":["2%","4%","6%"],"correctIndex":1,"explanation":"6% - 2% = 4%","source":"来源：利率章节"}
        ```
        """
        controller.addUserScript(WKUserScript(
            source: """
            window.initialMarkdown = \(json(markdown));
            window.weiBeiDocumentID = "compact-preview-check";
            window.weiBeiMarkdownEditable = false;
            window.weiBeiMarkdownCompactPreview = true;
            window.weiBeiTheme = "paper";
            window.weiBeiInterfaceLanguage = "zh-Hans";
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        super.init()
        controller.add(self, name: "editorReady")
        controller.add(self, name: "contentHeightChanged")
        configuration.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 760, height: 44), configuration: configuration)
    }

    func run() {
        let indexURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/WeiBei/Resources/Editor/index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        let timeout = Date().addingTimeInterval(12)
        while !isDone && Date() < timeout {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        if let failure {
            fputs("web-editor-check failed: \(failure)\n", stderr)
            exit(1)
        }
        expect(isDone, "compact preview did not finish")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "contentHeightChanged":
            if let height = (message.body as? [String: Any])?["height"] as? NSNumber {
                reportedHeight = height.doubleValue
            }
        case "editorReady":
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.validateRenderedHeight()
            }
        default:
            break
        }
    }

    private func validateRenderedHeight() {
        let script = """
        (() => {
          const root = document.querySelector('#editor');
          const prose = document.querySelector('.ProseMirror');
          const top = root?.getBoundingClientRect().top || 0;
          const bottom = Array.from(prose?.children || []).reduce((value, child) => Math.max(value, child.getBoundingClientRect().bottom), top);
          return {
            rootScrollHeight: root?.scrollHeight || 0,
            proseScrollHeight: prose?.scrollHeight || 0,
            geometryHeight: Math.max(0, bottom - top),
            hasTable: !!document.querySelector('table'),
            hasQuiz: !!document.querySelector('.weibei-interactive[data-kind="quiz"]'),
            sourceRows: document.querySelectorAll('.weibei-interactive-source-row').length,
            bodyBackground: getComputedStyle(document.body).backgroundColor,
            editorBackground: root ? getComputedStyle(root).backgroundColor : '',
            interactiveBackground: getComputedStyle(document.querySelector('.weibei-interactive') || document.body).backgroundColor
          };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error {
                failure = "compact preview inspection threw \(error.localizedDescription)"
                isDone = true
                return
            }
            let result = value as? [String: Any] ?? [:]
            let geometryHeight = (result["geometryHeight"] as? NSNumber)?.doubleValue ?? 0
            let rootHeight = (result["rootScrollHeight"] as? NSNumber)?.doubleValue ?? 0
            guard result["hasTable"] as? Bool == true,
                  result["hasQuiz"] as? Bool == true,
                  (result["sourceRows"] as? Int ?? -1) == 0,
                  result["bodyBackground"] as? String == "rgb(246, 238, 221)",
                  result["editorBackground"] as? String == "rgb(246, 238, 221)",
                  !(result["interactiveBackground"] as? String ?? "").contains("255, 255, 255"),
                  geometryHeight > 160,
                  rootHeight > 160,
                  reportedHeight >= max(geometryHeight, rootHeight) - 2 else {
                failure = "compact preview height/source-row check did not include table and interactive DOM cleanly: reported=\(reportedHeight), result=\(result)"
                isDone = true
                return
            }
            isDone = true
        }
    }
}

func validateSourceContracts() {
    let editorPath = "Sources/WeiBei/WebEditor/src/editor.js"
    let editorSource = (try? String(contentsOfFile: editorPath, encoding: .utf8)) ?? ""
    let interactiveKinds = [
        "quiz", "reveal", "chart", "function-plot", "parameter-lab", "text-study", "design-compare", "palette",
        "study-board", "relationship-map", "timeline", "comparison-matrix", "annotated-passage", "derivation-steps",
        "flashcards", "sequence-builder", "scenario-lab", "evidence-board", "spectrum", "decision-path",
        "unit-workbench", "reaction-balance", "algorithm-trace", "language-aligner",
        "argument-map", "visual-analysis", "spatial-layers", "pathway-lab",
    ]
    expect(editorSource.contains("parseWeiBeiInteractiveBlock"), "editor source should contain a dedicated safe interactive-block parser")
    expect(editorSource.contains("INTERACTIVE_PROTOCOL_VERSION"), "interactive parser should reject unknown future protocol versions")
    expect(editorSource.contains("weiBeiInteractiveRegistry"), "interactive components should be registered instead of selected by a growing kind switch")
    expect(editorSource.contains("MAX_INTERACTIVE_STRING_LENGTH"), "interactive parser should cap string sizes")
    expect(editorSource.contains("MAX_INTERACTIVE_OPTIONS"), "interactive parser should cap option arrays")
    expect(editorSource.contains("MAX_INTERACTIVE_SERIES")
        && editorSource.contains("MAX_INTERACTIVE_POINTS")
        && editorSource.contains("MAX_INTERACTIVE_CONTROLS")
        && editorSource.contains("MAX_INTERACTIVE_VARIANTS")
        && editorSource.contains("MAX_INTERACTIVE_COLORS")
        && editorSource.contains("MAX_INTERACTIVE_METRICS")
        && editorSource.contains("MAX_INTERACTIVE_BOARD_ITEMS")
        && editorSource.contains("MAX_INTERACTIVE_MAP_NODES")
        && editorSource.contains("MAX_INTERACTIVE_MAP_EDGES")
        && editorSource.contains("MAX_INTERACTIVE_TIMELINE_EVENTS")
        && editorSource.contains("MAX_INTERACTIVE_MATRIX_COLUMNS")
        && editorSource.contains("MAX_INTERACTIVE_MATRIX_ROWS")
        && editorSource.contains("MAX_INTERACTIVE_ANNOTATIONS")
        && editorSource.contains("MAX_INTERACTIVE_DERIVATION_STEPS")
        && editorSource.contains("MAX_INTERACTIVE_FLASHCARDS")
        && editorSource.contains("MAX_INTERACTIVE_SEQUENCE_ITEMS")
        && editorSource.contains("MAX_INTERACTIVE_SCENARIO_OUTCOMES")
        && editorSource.contains("MAX_INTERACTIVE_EVIDENCE_ITEMS")
        && editorSource.contains("MAX_INTERACTIVE_SPECTRUM_POINTS")
        && editorSource.contains("MAX_INTERACTIVE_DECISION_NODES")
        && editorSource.contains("MAX_INTERACTIVE_UNIT_VARIABLES")
        && editorSource.contains("MAX_INTERACTIVE_UNIT_CHECKS")
        && editorSource.contains("MAX_INTERACTIVE_REACTION_SPECIES")
        && editorSource.contains("MAX_INTERACTIVE_REACTION_ELEMENTS")
        && editorSource.contains("MAX_INTERACTIVE_ALGORITHM_LINES")
        && editorSource.contains("MAX_INTERACTIVE_ALGORITHM_STEPS")
        && editorSource.contains("MAX_INTERACTIVE_LANGUAGE_PAIRS")
        && editorSource.contains("MAX_INTERACTIVE_ARGUMENT_NODES")
        && editorSource.contains("MAX_INTERACTIVE_ARGUMENT_EDGES")
        && editorSource.contains("MAX_INTERACTIVE_VISUAL_ZONES")
        && editorSource.contains("MAX_INTERACTIVE_VISUAL_LENSES")
        && editorSource.contains("MAX_INTERACTIVE_SPATIAL_LAYERS")
        && editorSource.contains("MAX_INTERACTIVE_SPATIAL_FEATURES")
        && editorSource.contains("MAX_INTERACTIVE_SPATIAL_POINTS")
        && editorSource.contains("MAX_INTERACTIVE_PATHWAY_STATES"), "interactive parser should bound every collection used by rich components")
    for kind in interactiveKinds {
        expect(editorSource.contains("'\(kind)'"), "interactive registry should include \(kind)")
    }
    let bundledEditorPath = "Sources/WeiBei/Resources/Editor/editor.js"
    let bundledEditorSource = (try? String(contentsOfFile: bundledEditorPath, encoding: .utf8)) ?? ""
    let missingBundledKinds = interactiveKinds.filter { !bundledEditorSource.contains($0) }
    expect(missingBundledKinds.isEmpty, "generated Web editor bundle is stale; missing interactive kinds: \(missingBundledKinds.joined(separator: ", "))")
    expect(editorSource.contains("interactiveStudyBoardLayouts")
        && editorSource.contains("interactiveRelationshipLayouts")
        && editorSource.contains("interactiveTreatments"), "interactive layouts and treatments should stay on explicit allow-lists")
    expect(editorSource.contains("ids.has(from)")
        && editorSource.contains("ids.has(to)")
        && editorSource.contains("ids.has(id)"), "relationship map should enforce unique node ids and edge endpoints")
    expect(editorSource.contains("row.values.length === columns.length"), "comparison matrix rows should require values to match column count exactly")
    expect(editorSource.contains("setSourceReferenceAttributes")
        && editorSource.contains("weibei-source-reference"), "source-aware interactive nodes should use the canonical source reference bridge")
    expect(editorSource.contains("safeInteractiveNumber")
        && editorSource.contains("interactiveFunctionFamilies")
        && editorSource.contains("interactiveFunctionParameterKeys"), "numeric widgets should validate finite values and use allow-listed function families and parameter keys")
    expect(editorSource.contains("createElement") && editorSource.contains("textContent"), "interactive renderer should build DOM with createElement/textContent")
    expect(editorSource.contains("interactiveKindFamilies")
        && editorSource.contains("configureWeiBeiInteractiveRoot")
        && editorSource.contains("weibei-interactive-status"), "interactive roots should carry a semantic family and bounded local status")
    expect(editorSource.contains("role', 'tablist")
        && editorSource.contains("event.key === 'Home'")
        && editorSource.contains("event.key === 'End'"), "interactive tabs should follow the desktop tablist keyboard contract")
    expect(editorSource.contains("geometryHeight")
        && editorSource.contains("MutationObserver(reportContentHeight)"), "compact answer height should follow rendered interactive DOM")
    expect(!editorSource.contains("weibeiInteractiveHTML"), "interactive renderer must not use raw HTML templates")
    expect(!editorSource.contains("eval(")
        && !editorSource.contains("new Function"), "interactive renderer must never evaluate model-provided code or formulas")

    let htmlPath = "Sources/WeiBei/Resources/Editor/index.html"
    let htmlSource = (try? String(contentsOfFile: htmlPath, encoding: .utf8)) ?? ""
    let answerDesignPath = "Sources/WeiBei/Resources/Editor/answer-design.css"
    let answerDesignSource = (try? String(contentsOfFile: answerDesignPath, encoding: .utf8)) ?? ""
    expect(htmlSource.contains("<link rel=\"stylesheet\" href=\"./answer-design.css\">"), "editor HTML should load the dedicated WeiBei answer design layer last")
    expect(answerDesignSource.contains("data-family=\"reading\"")
        && answerDesignSource.contains("data-family=\"reasoning\"")
        && answerDesignSource.contains("data-family=\"practice\"")
        && answerDesignSource.contains("data-family=\"lab\"")
        && answerDesignSource.contains("data-family=\"atlas\"")
        && answerDesignSource.contains("data-family=\"planning\""), "answer design should distinguish all six semantic instrument families")
    expect(answerDesignSource.contains(".weibei-interactive-status")
        && answerDesignSource.contains("prefers-reduced-motion")
        && answerDesignSource.contains("@media (max-width: 390px)"), "answer design should include visible action status, reduced motion, and narrow-column behavior")
    expect(htmlSource.contains(".weibei-interactive"), "editor HTML should include WeiBei interactive component styles")
    expect(htmlSource.contains(".weibei-interactive-chart-svg")
        && htmlSource.contains(".weibei-parameter-slider")
        && htmlSource.contains(".weibei-text-study-copy")
        && htmlSource.contains(".weibei-design-preview")
        && htmlSource.contains(".weibei-palette-swatch")
        && htmlSource.contains(".weibei-study-board-item")
        && htmlSource.contains(".weibei-relationship-node")
        && htmlSource.contains(".weibei-timeline-event")
        && htmlSource.contains(".weibei-comparison-column-button")
        && htmlSource.contains(".weibei-annotated-layout")
        && htmlSource.contains(".weibei-derivation-step")
        && htmlSource.contains(".weibei-flashcard")
        && htmlSource.contains(".weibei-sequence-item")
        && htmlSource.contains(".weibei-scenario-result")
        && htmlSource.contains(".weibei-evidence-item")
        && htmlSource.contains(".weibei-spectrum-marker")
        && htmlSource.contains(".weibei-decision-choice")
        && htmlSource.contains(".weibei-unit-variable")
        && htmlSource.contains(".weibei-reaction-stepper")
        && htmlSource.contains(".weibei-algorithm-action")
        && htmlSource.contains(".weibei-language-pair")
        && htmlSource.contains(".weibei-argument-node")
        && htmlSource.contains(".weibei-visual-analysis-zone-button")
        && htmlSource.contains(".weibei-spatial-layer-toggle")
        && htmlSource.contains(".weibei-pathway-state"), "editor HTML should style the full WeiBei interactive component vocabulary")
    expect(htmlSource.contains(":root[data-weibei-compact-preview=\"true\"] body")
        && htmlSource.contains(":root[data-weibei-compact-preview=\"true\"] #editor"), "compact answer surfaces should inherit the native chat paper instead of painting a second panel")
    expect(htmlSource.contains("max-width: 390px"), "wide-column charts should stay compact instead of expanding to the full reader width")
    expect(htmlSource.contains("@media (max-width: 420px)")
        && htmlSource.contains("grid-auto-flow: row"), "timeline and composite blocks should have a 360pt non-overflow layout")
    let interactiveStyle = htmlSource.components(separatedBy: ".weibei-interactive").dropFirst().prefix(24).joined(separator: ".weibei-interactive") + answerDesignSource
    expect(!interactiveStyle.contains("linear-gradient"), "interactive styles should avoid gradient-heavy AI templates")
    expect(!interactiveStyle.contains("border-radius: 8")
        && !interactiveStyle.contains("border-radius: 10")
        && !interactiveStyle.contains("border-radius: 12"), "interactive styles should keep corners at 6px or below")
}

NSApplication.shared.setActivationPolicy(.prohibited)
validateSourceContracts()
EditorHarness().run()
CompactPreviewHarness().run()
print("WeiBei web editor check passed")
