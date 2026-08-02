import Foundation

/// Splits in-flight streaming text into a *stable prefix* (complete blocks,
/// safe to hand to the Milkdown/KaTeX renderer) and a *tail* (still growing,
/// shown as native typewriter text until its block closes).
///
/// Invariant: as the snapshot grows, the stable prefix only ever appends —
/// a boundary's balance depends solely on the text before it, so once chosen
/// it never un-balances. This keeps the WebView on an append-only diet and
/// prevents re-render churn.
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
        var searchEnd = text.endIndex
        while let gap = text.range(of: "\n\n", options: .backwards, range: text.startIndex..<searchEnd) {
            let prefix = String(text[text.startIndex..<gap.upperBound])
            if isBalanced(prefix) {
                let tail = String(text[gap.upperBound...])
                return Split(stablePrefix: prefix, tail: tail)
            }
            searchEnd = gap.lowerBound
        }
        return Split(stablePrefix: "", tail: text)
    }

    private static func isBalanced(_ text: String) -> Bool {
        occurrences(of: "```", in: text) % 2 == 0
            && occurrences(of: "$$", in: text) % 2 == 0
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        var count = 0
        var searchStart = text.startIndex
        while let found = text.range(of: needle, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = found.upperBound
        }
        return count
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
        ]
        return cases.allSatisfy { input, stable, tail in
            let result = splitUnchecked(input)
            return result.stablePrefix == stable && result.tail == tail
        }
    }()
    #endif
}
