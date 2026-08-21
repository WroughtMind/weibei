import XCTest
@testable import WeiBei

final class AgentMarkdownBlockFallbackParserTests: XCTestCase {

    private func kinds(_ markdown: String) -> [AgentMarkdownBlockFallback.Block.Kind] {
        AgentMarkdownBlockParser.parse(markdown).map(\.kind)
    }

    func testParsesHeadingsParagraphsAndLists() {
        let markdown = """
        # 标题一

        普通段落,**加粗**继续。

        ## 小节

        - 第一项
        - 第二项

        1. 步骤一
        2. 步骤二
        """
        let parsed = kinds(markdown)
        guard case let .heading(level1) = parsed[0], level1 == 1,
              case .paragraph = parsed[1],
              case let .heading(level2) = parsed[2], level2 == 2,
              case .bulletList = parsed[3],
              case .orderedList = parsed[4] else {
            return XCTFail("unexpected structure: \(parsed)")
        }
    }

    func testParsesCodeFenceQuoteAndDivider() {
        let markdown = """
        前文

        ```python
        print(1)
        ```

        > 引用第一行
        > 引用第二行

        ---

        后文
        """
        let parsed = kinds(markdown)
        guard case .paragraph = parsed[0],
              case let .code(language) = parsed[1], language == "python",
              case .quote = parsed[2],
              case .divider = parsed[3],
              case .paragraph = parsed[4] else {
            return XCTFail("unexpected structure: \(parsed)")
        }
    }

    func testBareFenceAndUnterminatedFenceAreForgiving() {
        let bare = AgentMarkdownBlockParser.parse("```\nabc\n```")
        guard bare.count == 1,
              case let .code(language) = bare[0].kind,
              language == nil,
              bare[0].lines == ["abc"] else {
            return XCTFail("bare fence should collect its body: \(bare)")
        }

        let unterminated = AgentMarkdownBlockParser.parse("```swift\nlet x = 1")
        guard unterminated.count == 1,
              case let .code(swiftLanguage) = unterminated[0].kind,
              swiftLanguage == "swift" else {
            return XCTFail("unterminated fence should still be a code block: \(unterminated)")
        }
    }

    func testListHelpers() {
        XCTAssertEqual(AgentMarkdownBlockParser.listItemBody("- 一项"), "一项")
        XCTAssertEqual(AgentMarkdownBlockParser.listItemBody("12. 编号"), "编号")
        XCTAssertEqual(AgentMarkdownBlockParser.listItemBody("  - 缩进项"), "缩进项")
        XCTAssertEqual(AgentMarkdownBlockParser.listIndentLevel("- 顶"), 0)
        XCTAssertEqual(AgentMarkdownBlockParser.listIndentLevel("  - 一层"), 1)
        XCTAssertEqual(AgentMarkdownBlockParser.headingBody("### 三级"), "三级")
        XCTAssertEqual(AgentMarkdownBlockParser.quoteBody("> 引用"), "引用")
    }

    func testUnknownSyntaxFallsBackToParagraphs() {
        let markdown = "$$x = y$$\n|表格|列|"
        let parsed = AgentMarkdownBlockParser.parse(markdown)
        XCTAssertTrue(parsed.allSatisfy { block in
            if case .paragraph = block.kind { return true }
            return false
        }, "unrecognized syntax must surface its raw text, not vanish")
    }
}
