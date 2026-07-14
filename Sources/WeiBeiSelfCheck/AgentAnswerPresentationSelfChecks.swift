import Foundation
import WeiBeiCore

func runAgentAnswerPresentationSelfChecks() {
    let answer = AgentAnswerPresentation.parse(
        """
        ## 实际利率

        它把名义利率与通胀预期联系起来。这里的来源：不是一条跳转命令，而是正文。

        ## 来源
        - 来源：Mishkin 教材样例，第 3 页
        > Source: 货币金融学课程 HTML，章节：实际利率
        """,
        fallbackSource: "Mishkin 教材样例"
    )

    expect(answer.bodyMarkdown.contains("## 实际利率"), "agent answer presentation preserves ordinary Markdown")
    expect(answer.bodyMarkdown.contains("这里的来源：不是一条跳转命令"), "agent answer presentation keeps inline source prose")
    expect(!answer.bodyMarkdown.contains("## 来源"), "agent answer presentation removes an empty dedicated source heading")
    expect(!answer.bodyMarkdown.contains("- 来源：Mishkin"), "agent answer presentation removes dedicated source lines from the body")
    expect(answer.sourceReferences.count == 2, "agent answer presentation extracts and deduplicates source attachments")
    expect(answer.sourceReferences[0].title == "Mishkin 教材样例"
        && answer.sourceReferences[0].pageIndex == 2, "agent answer presentation preserves PDF locators")
    expect(answer.sourceReferences[1].title == "货币金融学课程 HTML"
        && answer.sourceReferences[1].sectionTitle == "实际利率", "agent answer presentation preserves HTML section locators")

    let noSource = AgentAnswerPresentation.parse("\n\n只有一段普通回答。\n", fallbackSource: nil)
    expect(noSource.bodyMarkdown == "只有一段普通回答。"
        && noSource.sourceReferences.isEmpty, "agent answer presentation keeps source-free answers clean")

    let mixedLine = AgentAnswerPresentation.parse("请对照来源：教材第三章再回答。", fallbackSource: nil)
    expect(mixedLine.sourceReferences.isEmpty
        && mixedLine.bodyMarkdown.contains("教材第三章"), "agent answer presentation never promotes mixed prose into an attachment")

    let inlineEvidence = AgentAnswerPresentation.parse(
        "根据[材料：Mishkin 教材样例]的定义，再对照[笔记：利率课堂笔记]。",
        fallbackSource: nil
    )
    expect(inlineEvidence.bodyMarkdown.contains("[材料：Mishkin 教材样例]")
        && inlineEvidence.sourceReferences.map(\.title) == ["Mishkin 教材样例", "利率课堂笔记"], "inline evidence labels stay in the body and also become source attachments")

    let preciseAttachment = AgentAnswerPresentation.parse(
        "这个判断来自[材料：Mishkin 教材样例]。\n\n来源：Mishkin 教材样例，第 3 页",
        fallbackSource: nil
    )
    expect(preciseAttachment.sourceReferences.count == 1
        && preciseAttachment.sourceReferences[0].pageIndex == 2, "a precise jump replaces the title-only attachment for the same source")

    let interactiveSources = AgentAnswerPresentation.parse(
        """
        先看这张关系图。

        ```weibei-interactive
        {"kind":"relationship-map","title":"利率传导","layout":"flow","nodes":[{"id":"a","label":"准备金减少","source":"材料：货币金融学课程 HTML，章节：准备金"},{"id":"b","label":"市场利率上升"}],"edges":[{"from":"a","to":"b","label":"推动"}],"sources":["材料：货币金融学课程 HTML，章节：准备金","笔记：利率课堂笔记"]}
        ```
        """,
        fallbackSource: nil
    )
    expect(
        interactiveSources.bodyMarkdown.contains("```weibei-interactive")
            && interactiveSources.sourceReferences.map(\.title) == ["货币金融学课程 HTML", "利率课堂笔记"]
            && interactiveSources.interactiveKinds == ["relationship-map"],
        "interactive block sources join the answer attachment ribbon without removing the rendered block"
    )

    let nestedInteractiveSource = AgentAnswerPresentation.parse(
        """
        ```weibei-interactive
        {"kind":"timeline","title":"学习过程","events":[{"label":"第一步","title":"阅读材料","source":"材料：课程导论，章节：开始"}]}
        ```
        """,
        fallbackSource: nil
    )
    expect(
        nestedInteractiveSource.sourceReferences.count == 1
            && nestedInteractiveSource.sourceReferences[0].title == "课程导论"
            && nestedInteractiveSource.sourceReferences[0].sectionTitle == "开始",
        "source-aware interactive items become precise native jump attachments even without a top-level source list"
    )

    let expandedInteractiveSources = AgentAnswerPresentation.parse(
        """
        ```weibei-interactive
        {"kind":"annotated-passage","title":"夹批","text":"实际利率反映真实资金成本。","annotations":[{"term":"实际利率","note":"扣除预期通胀","source":"材料：利率教材，第 4 页"}]}
        ```

        ```weibei-interactive
        {"kind":"decision-path","title":"选择指标","startID":"start","nodes":[{"id":"start","title":"目标","body":"先判断目标","choices":[{"label":"真实成本","nextID":"real","source":"笔记：课堂判断"}]},{"id":"real","title":"实际利率","body":"观察真实成本","choices":[],"source":"材料：利率课程 HTML，章节：实际利率"}]}
        ```
        """,
        fallbackSource: nil
    )
    expect(
        expandedInteractiveSources.sourceReferences.map(\.title) == ["利率教材", "课堂判断", "利率课程 HTML"]
            && expandedInteractiveSources.sourceReferences[0].pageIndex == 3
            && expandedInteractiveSources.sourceReferences[2].sectionTitle == "实际利率"
            && expandedInteractiveSources.interactiveKinds == ["annotated-passage", "decision-path"],
        "expanded interactive annotations and nested decisions contribute precise native source attachments"
    )

    let disciplineInteractiveSources = AgentAnswerPresentation.parse(
        """
        ```weibei-interactive
        {"kind":"unit-workbench","title":"量纲核对","variables":[{"symbol":"v","unit":"m/s","source":"材料：物理讲义，第 8 页"}],"checks":[{"label":"速度","source":"笔记：量纲错题"}]}
        ```

        ```weibei-interactive
        {"kind":"reaction-balance","title":"反应配平","species":[{"formula":"H2","side":"reactant","atoms":{"H":2},"source":"材料：化学教材，章节：化学计量"}]}
        ```

        ```weibei-interactive
        {"kind":"visual-analysis","title":"形式分析","zones":[{"label":"主视觉","source":"材料：作品图版，第 2 页"}],"lenses":[{"label":"构图","source":"笔记：艺术史夹注"}]}
        ```
        """,
        fallbackSource: nil
    )
    expect(
        disciplineInteractiveSources.sourceReferences.map(\.title) == ["物理讲义", "量纲错题", "化学教材", "作品图版", "艺术史夹注"]
            && disciplineInteractiveSources.sourceReferences[0].pageIndex == 7
            && disciplineInteractiveSources.sourceReferences[2].sectionTitle == "化学计量"
            && disciplineInteractiveSources.sourceReferences[3].pageIndex == 1
            && disciplineInteractiveSources.interactiveKinds == ["unit-workbench", "reaction-balance", "visual-analysis"],
        "cross-discipline interactive variables, species, zones, and lenses retain native source attachments"
    )

    let unsupportedInteractive = AgentAnswerPresentation.parse(
        """
        ```weibei-interactive
        {"version":2,"kind":"reveal","title":"未来协议"}
        ```

        ```weibei-interactive
        {"kind":"arbitrary-html","html":"<button>no</button>"}
        ```
        """,
        fallbackSource: nil
    )
    expect(
        unsupportedInteractive.interactiveKinds.isEmpty,
        "unsupported interactive kinds and future protocol fixtures never drive native rich-answer presentation"
    )
}
