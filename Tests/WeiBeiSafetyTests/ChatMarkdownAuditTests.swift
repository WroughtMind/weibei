import AppKit
import WeiBeiCore
import SwiftMath
import XCTest
@testable import WeiBei

final class ChatMarkdownAuditTests: XCTestCase {
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
}
