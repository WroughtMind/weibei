import XCTest
@testable import WeiBeiCore

/// Covers selection aggregation and readable Markdown extraction used by Agent context.
final class SelectionAndMarkdownBehaviorTests: XCTestCase {
    /// Verifies live-selection fragments merge overlap without duplicating text.
    func testSelectionMergeRemovesOverlapWithinGesture() {
        XCTAssertEqual(
            SelectionAttachmentMerge.mergedText(
                existing: "利率是资金使用",
                incoming: "使用价格的表达",
                withinSelectionGesture: true
            ),
            "利率是资金使用价格的表达"
        )
    }

    /// Verifies independent complete sentences are not accidentally joined.
    func testSelectionMergeRejectsSeparateSentences() {
        XCTAssertNil(
            SelectionAttachmentMerge.mergedText(
                existing: "利率是资金使用价格。",
                incoming: "通货膨胀预期会改变真实利率。",
                withinSelectionGesture: true
            )
        )
    }

    /// Verifies containment ignores layout whitespace but rejects empty fragments.
    func testSelectionContainmentNormalizesWhitespace() {
        XCTAssertTrue(
            SelectionAttachmentMerge.containsSelection(
                "当前笔记已经覆盖材料开头。",
                fragment: "材料 开头。"
            )
        )
        XCTAssertFalse(SelectionAttachmentMerge.containsSelection("利率", fragment: "  "))
    }

    /// Verifies Markdown selection cleanup preserves human-readable labels and removes rendering syntax.
    func testMarkdownSelectionSanitizerProducesReadableContext() {
        let markdown = """
        > [!note] 摘要
        > 参见 [[货币金融学|课程讲义]] 和 [利率章节](https://example.invalid)。
        > 图片：![[curve.png|收益率曲线|320]]
        %% internal comment %%
        """

        XCTAssertEqual(
            MarkdownSelectionSanitizer.clean(markdown),
            "摘要\n参见 课程讲义 和 利率章节。\n图片：收益率曲线"
        )
    }

    /// Verifies tag discovery combines frontmatter and body while ignoring code.
    func testMarkdownTagSearchIgnoresCodeAndDeduplicatesTags() {
        let markdown = """
        ---
        tags: [金融, 利率]
        ---
        正文 #金融 #货币
        `#不是标签`
        ```
        #代码标签
        ```
        """

        XCTAssertEqual(MarkdownTagSearch.tags(in: markdown), ["#利率", "#货币", "#金融"])
        XCTAssertTrue(MarkdownTagSearch.matches(query: "#货", in: markdown))
        XCTAssertFalse(MarkdownTagSearch.matches(query: "代码", in: markdown))
    }
}
