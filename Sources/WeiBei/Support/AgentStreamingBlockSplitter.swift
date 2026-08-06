import Foundation

/// Splits in-flight streaming text into a *stable prefix* (complete blocks,
/// safe to hand to the Milkdown/KaTeX renderer) and a hidden growing tail.
///
/// Invariant: as the snapshot grows, the stable prefix only ever appends —
/// a boundary's balance depends solely on the text before it, so once chosen
/// it never un-balances. The renderer therefore appends finished blocks without
/// ever exposing incomplete Markdown as native text.
enum AgentStreamingBlockSplitter {
    struct Split: Equatable {
        var stablePrefix: String
        var tail: String
    }

    static func split(_ text: String) -> Split {
        #if DEBUG
        assert(selfCheckPassed, "AgentStreamingBlockSplitter self-check failed")
        #endif
        return splitUnchecked(text)
    }

    /// A boundary is a `\n\n` gap where everything before it has:
    /// - an even number of ``` fences (no open code block), and
    /// - an even number of `$$` markers (no open display-math block).
    /// The last such boundary wins; without one, everything stays in the tail.
    private static func splitUnchecked(_ text: String) -> Split {
        guard !text.isEmpty else { return Split(stablePrefix: "", tail: "") }
        var index = text.startIndex
        var openCodeFence: String?
        var displayMathOpen = false
        var lastStableEnd: String.Index?

        while index < text.endIndex {
            let remainder = text[index...]
            if let marker = openCodeFence, remainder.hasPrefix(marker) {
                openCodeFence = nil
                index = text.index(index, offsetBy: 3)
                continue
            }
            if openCodeFence == nil, !displayMathOpen,
               let marker = remainder.hasPrefix("```") ? "```" : (remainder.hasPrefix("~~~") ? "~~~" : nil) {
                openCodeFence = marker
                index = text.index(index, offsetBy: 3)
                continue
            }
            if remainder.hasPrefix("$$"), openCodeFence == nil {
                displayMathOpen.toggle()
                index = text.index(index, offsetBy: 2)
                continue
            }
            if remainder.hasPrefix("\n\n"), openCodeFence == nil, !displayMathOpen {
                lastStableEnd = text.index(index, offsetBy: 2)
            }
            index = text.index(after: index)
        }

        guard let stableEnd = lastStableEnd else {
            return Split(stablePrefix: "", tail: text)
        }
        return Split(
            stablePrefix: String(text[..<stableEnd]),
            tail: String(text[stableEnd...])
        )
    }

    #if DEBUG
    private static let selfCheckPassed: Bool = {
        let cases: [(String, String, String)] = [
            // 普通段落：最后一个空行前稳定
            ("第一段。\n\n第二段还在写", "第一段。\n\n", "第二段还在写"),
            // 未闭合代码围栏必须整体留在 tail
            ("说明：\n\n```stata\nreg y x", "说明：\n\n", "```stata\nreg y x"),
            // 闭合后的围栏可进入稳定区
            ("```py\na=1\n```\n\n结论开始", "```py\na=1\n```\n\n", "结论开始"),
            // 未闭合 $$ 数学块留在 tail
            ("推导：\n\n$$\n\\frac{a}{b}", "推导：\n\n", "$$\n\\frac{a}{b}"),
            // 单行 $$…$$（成对）可稳定
            ("$$a+b$$\n\n下一段", "$$a+b$$\n\n", "下一段"),
            // 无空行边界：全部留在 tail
            ("只有一段没有边界", "", "只有一段没有边界"),
            // 代码块内的空行不能成为边界
            ("前文\n\n```\na\n\nb", "前文\n\n", "```\na\n\nb"),
            // 代码内容里的 $$ 不是数学块边界
            ("```swift\nlet price = \"$$\"\n```\n\n结论", "```swift\nlet price = \"$$\"\n```\n\n", "结论"),
            // 波浪线围栏与反引号围栏遵循相同边界
            ("~~~text\na\n\nb\n~~~\n\n结论", "~~~text\na\n\nb\n~~~\n\n", "结论"),
        ]
        return cases.allSatisfy { input, stable, tail in
            let result = splitUnchecked(input)
            return result.stablePrefix == stable && result.tail == tail
        }
    }()
    #endif
}
