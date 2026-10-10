import AppKit
import WeiBeiCore
import SwiftMath
import XCTest
@testable import WeiBei

final class ChatMarkdownAuditTests: XCTestCase {
    func testSingleDollarInlineMathIsProtectedBeforeMarkdownParsing() {
        let source = "若 $f(|succ_i|,|succ_{-i}|)$ 成立，则继续。"
        let protected = AgentChatKaTeXMarkdown.protectInlineMath(source)

        XCTAssertEqual(protected, "若 \\(f(|succ_i|,|succ_{-i}|)\\) 成立，则继续。")
        XCTAssertEqual(AgentChatKaTeXMarkdown.protectInlineMath(protected), protected)
        let document = NativeChatMarkdownParser.parse(protected)
        XCTAssertTrue(document.runs.contains {
            $0.attachment == .math(latex: "f(|succ_i|,|succ_{-i}|)", display: false)
        })
    }

    func testInlineMathProtectionPreservesLiteralAndEscapedDollars() {
        let literals = [
            "`$x_i$`",
            "[金额 $5$](https://example.com)",
            #"\$5$"#,
            #"$x\$"#,
            "$$x_i$$"
        ]

        for literal in literals {
            XCTAssertEqual(AgentChatKaTeXMarkdown.protectInlineMath(literal), literal, literal)
        }
    }

    func testRichAnswerSegmentsExtractAttachmentsWithoutChangingTextWhitespace() {
        let source = "  前文\n\n![图示](weibei-visualization:activity/0)\n\n    后文\n"

        XCTAssertEqual(
            AgentAnswerMarkdownSegments.split(source),
            [
                .text("  前文\n\n"),
                .attachment("activity/0"),
                .text("\n\n    后文\n")
            ]
        )
    }

    func testRichAnswerSegmentsDecodePersistedContentIdentifiers() {
        XCTAssertEqual(
            AgentAnswerMarkdownSegments.split("![图示](weibei-visualization:chart%20one)"),
            [.attachment("chart one")]
        )
    }

    func testRichAnswerSegmentsPreserveMarkerExamplesInCodeAndLinks() {
        let examples = [
            "`![图示](weibei-visualization:activity/0)`",
            "```markdown\n![图示](weibei-visualization:some-id)\n```",
            "[![图示](weibei-visualization:some-id)](https://example.com)"
        ]

        for example in examples {
            XCTAssertEqual(AgentAnswerMarkdownSegments.split(example), [.text(example)], example)
        }
    }

    func testSelectionAnswerFormulaRendersInsteadOfShowingLatexSource() {
        let answer = #"$$\text{本币回报} \approx \underbrace{(1+i_{f})}_{\text{外币利息}}\times\underbrace{(1+\Delta e)}_{\text{汇率变动}}-1$$"#
        let prepared = AgentChatKaTeXMarkdown.prepare(answer)
        let latex = prepared.replacingOccurrences(of: "$$", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let renderer = MTMathImage(latex: latex, fontSize: 16, textColor: .black, labelMode: .text)
        renderer.font?.fallbackFont = NSFont.systemFont(ofSize: 16)
        let (error, image) = renderer.asImage()
        XCTAssertNil(error)
        XCTAssertNotNil(image)
        XCTAssertTrue(latex.contains("外币利息") && latex.contains("汇率变动"))
    }

    func testFormulaCleanupPreservesLiteralCodeAndLinks() {
        let literals = [
            "`\\hat y`", "``code ` \\hat y``", "```latex\n$$x$$\n\\hat\\beta\n```",
            "~~~latex\n$$x$$\n~~~", "    \\hat y\n", "```latex\n\\hat y",
            "中文🙂 `\\hat y` 尾部", "- `\\hat y`", "> `\\hat y`",
            "\t\\hat y\n", "```latex\r\n$$x$$\r\n```", "```latex\r$$x$$\r```",
            "> ```latex\n> \\hat y\n> ```",
            "[链接](https://example.com \"\\hat y\")", "<span title=\"\\hat y\">内容</span>",
            #"`\underbrace{x}_{y}`"#, "```latex\n\\underbrace{x}_{y}\n```",
        ]
        for literal in literals {
            XCTAssertEqual(AgentChatKaTeXMarkdown.prepare(literal), literal, literal)
        }
        let source = "正文 \\hat y\n\n`\\hat y`\n\n$$x$$"
        XCTAssertEqual(AgentChatKaTeXMarkdown.prepare(source), "正文 \\hat{y}\n\n`\\hat y`\n\n$$\nx\n$$")
        XCTAssertTrue(MarkdownLiteralRanges.ranges(in: "").isEmpty)
    }

    func testCitationAndFormulaPipelinePreservesCodeAndClickableLinks() {
        let code = "```latex\n[材料：示例] \\hat y\n$$x$$\n```"
        let link = "[材料：示例](https://example.com)"
        let source = "正文 [材料：示例]\n\n" + code + "\n\n" + link + "\n\n`[材料：示例]`"
        let reference = AgentReplySource(itemID: nil, kind: .material, title: "真实材料", label: "[材料：示例]", excerpt: "示例")
        let presentation = AgentReplySourceInlinePresentation(text: source, sources: [reference], language: .chinese)
        XCTAssertTrue(presentation.markdown.contains("真实材料"))
        XCTAssertTrue(presentation.markdown.contains("weibei-source://" + reference.id.uuidString.lowercased()))
        XCTAssertTrue(presentation.markdown.contains(code))
        XCTAssertTrue(presentation.markdown.contains(link))
        for references in [[], [reference]] {
            let rendered = AgentMessageMarkdownMemo().outputs(text: source, sources: references, language: .chinese).finalized
            XCTAssertTrue(rendered.contains(code))
            XCTAssertTrue(rendered.contains(link))
            XCTAssertTrue(rendered.contains("`[材料：示例]`"))
        }
        for boundary in ["[`x`]", "`x`$$y$$", "$$y$$`x`", "[材料：`示例`]"] {
            XCTAssertEqual(AgentMessageMarkdownMemo().outputs(text: boundary, sources: [], language: .chinese).finalized, boundary)
        }
        let emptyLabel = AgentReplySource(itemID: nil, kind: .material, title: "空标签", label: "", excerpt: "")
        XCTAssertEqual(AgentReplySourceInlinePresentation(text: "原文", sources: [emptyLabel], language: .chinese).markdown, "原文")
        let partialCode = "```text\n[材料：未完成"
        XCTAssertEqual(AgentMessageMarkdownMemo().outputs(text: partialCode, sources: [], language: .chinese).finalized, partialCode)
    }

    func testCitationPunctuationTetheringAndCircledGlyphs() {
        let s1 = AgentReplySource(itemID: nil, kind: .material, title: "潜在结果框架", label: "[材料：框架1]", excerpt: "摘录1", pageIndex: 6)
        let s2 = AgentReplySource(itemID: nil, kind: .material, title: "潜在结果框架", label: "[材料：框架2]", excerpt: "摘录2", pageIndex: 8)

        // 1. 标点连带：逗号紧随引用时，逗号移至引用前，正文不被打断
        let commaText = "只是把观测值写出来 [材料：框架1]，不依赖任何假设"
        let commaPres = AgentReplySourceInlinePresentation(text: commaText, sources: [s1], language: .chinese)
        XCTAssertTrue(commaPres.markdown.contains("只是把观测值写出来，[①]("))
        XCTAssertTrue(commaPres.markdown.contains("潜在结果框架 · 第 7 页"))
        XCTAssertFalse(commaPres.markdown.contains(" [材料：框架1]，"))

        // 2. 标点连带：句号紧随引用时，句号移至引用前
        let periodText = "同样无法同时观测到 [材料：框架2]。问题在于"
        let periodPres = AgentReplySourceInlinePresentation(text: periodText, sources: [s2], language: .chinese)
        XCTAssertTrue(periodPres.markdown.contains("同样无法同时观测到。[①]("))
        XCTAssertTrue(periodPres.markdown.contains("潜在结果框架 · 第 9 页"))

        // 3. 标点已在引用前时，保持连贯且不重复添加标点
        let aheadText = "只是把观测值写出来，[材料：框架1] 不依赖任何假设"
        let aheadPres = AgentReplySourceInlinePresentation(text: aheadText, sources: [s1], language: .chinese)
        XCTAssertTrue(aheadPres.markdown.contains("只是把观测值写出来，[①]("))
        XCTAssertFalse(aheadPres.markdown.contains("，，"))

        // 4. 多来源依序编号，同来源复用编号
        let multiText = "首引 [材料：框架1]，次引 [材料：框架2]，复引 [材料：框架1]。"
        let multiPres = AgentReplySourceInlinePresentation(text: multiText, sources: [s1, s2], language: .chinese)
        XCTAssertTrue(multiPres.markdown.contains("首引，[①]("))
        XCTAssertTrue(multiPres.markdown.contains("次引，[②]("))
        XCTAssertTrue(multiPres.markdown.contains("复引。[①]("))

        // 5. 相邻来源分组折叠
        let groupText = "依据 [材料：框架1]、[材料：框架2] 推导"
        let groupPres = AgentReplySourceInlinePresentation(text: groupText, sources: [s1, s2], language: .chinese)
        XCTAssertTrue(groupPres.markdown.contains("[①]("))
        XCTAssertTrue(groupPres.markdown.contains("[+1]("))
    }
}
