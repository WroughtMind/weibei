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
    /// - no open backtick or tilde code fence, and
    /// - an even number of `$$` markers (no open display-math block).
    /// The last such boundary wins; without one, everything stays in the tail.
    private static func splitUnchecked(_ text: String) -> Split {
        guard !text.isEmpty else { return Split(stablePrefix: "", tail: "") }
        var lineStart = text.startIndex
        var openCodeFence: (marker: Character, length: Int)?
        var displayMathOpen = false
        var lastStableEnd: String.Index?

        while lineStart < text.endIndex {
            let newline = text[lineStart...].firstIndex(of: "\n")
            let lineEnd = newline ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            var handledFenceLine = false

            if let candidate = codeFence(in: line) {
                if let activeFence = openCodeFence,
                   candidate.marker == activeFence.marker,
                   candidate.length >= activeFence.length,
                   candidate.trailingOnlyWhitespace {
                    openCodeFence = nil
                    handledFenceLine = true
                } else if openCodeFence == nil, !displayMathOpen {
                    openCodeFence = (candidate.marker, candidate.length)
                    handledFenceLine = true
                }
            }

            if openCodeFence == nil, !handledFenceLine {
                toggleDisplayMath(in: line, open: &displayMathOpen)
            }

            guard let newline else { break }
            let nextLineStart = text.index(after: newline)
            if nextLineStart < text.endIndex,
               text[nextLineStart] == "\n",
               openCodeFence == nil,
               !displayMathOpen {
                lastStableEnd = text.index(after: nextLineStart)
            }
            lineStart = nextLineStart
        }

        guard let stableEnd = lastStableEnd else {
            return Split(stablePrefix: "", tail: text)
        }
        return Split(
            stablePrefix: String(text[..<stableEnd]),
            tail: String(text[stableEnd...])
        )
    }

    private static func codeFence(
        in line: Substring
    ) -> (marker: Character, length: Int, trailingOnlyWhitespace: Bool)? {
        var index = line.startIndex
        var indentation = 0
        while index < line.endIndex, line[index] == " ", indentation < 4 {
            indentation += 1
            index = line.index(after: index)
        }
        guard indentation <= 3, index < line.endIndex else { return nil }
        let marker = line[index]
        guard marker == "`" || marker == "~" else { return nil }

        var length = 0
        while index < line.endIndex, line[index] == marker {
            length += 1
            index = line.index(after: index)
        }
        guard length >= 3 else { return nil }
        if marker == "`", line[index...].contains("`") {
            return nil
        }
        let trailingOnlyWhitespace = line[index...].allSatisfy { $0 == " " || $0 == "\t" }
        return (marker, length, trailingOnlyWhitespace)
    }

    private static func toggleDisplayMath(in line: Substring, open: inout Bool) {
        var index = line.startIndex
        while index < line.endIndex {
            if line[index...].hasPrefix("$$") {
                open.toggle()
                index = line.index(index, offsetBy: 2)
            } else {
                index = line.index(after: index)
            }
        }
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
            // 行内三反引号不是代码围栏
            ("解释 ``` 符号。\n\n下一段", "解释 ``` 符号。\n\n", "下一段"),
            // 行首合法内联代码也不是代码围栏
            ("```x```\n\n下一段", "```x```\n\n", "下一段"),
            // 四反引号不能被更短的围栏提前闭合
            ("前文\n\n````swift\na\n```\n\nb", "前文\n\n", "````swift\na\n```\n\nb"),
        ]
        return cases.allSatisfy { input, stable, tail in
            let result = splitUnchecked(input)
            return result.stablePrefix == stable && result.tail == tail
        }
    }()
    #endif
}
