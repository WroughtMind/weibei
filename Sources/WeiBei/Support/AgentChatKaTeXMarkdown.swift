import Foundation

/// Prepares agent markdown so Milkdown/KaTeX can parse model output that uses
/// pseudo-delimiters like `[ y_i=\hat y_i ]` instead of `$$...$$` / `\[...\]`.
enum AgentChatKaTeXMarkdown {
    private static let inlineMath = try? NSRegularExpression(
        pattern: #"(?<!\\)\$(?!\s)(?:\\.|[^$\n])+\$(?!\d)"#
    )

    static func prepare(_ raw: String) -> String {
        var text = raw
        text = convertBracketDisplayMath(in: text)
        text = fixHatArguments(in: text)
        return text
    }

    /// Keep ordinary Markdown (paragraphs, lists, headings, emphasis) on native
    /// SwiftUI `AttributedString`. WebKit is only for syntax that actually needs
    /// Milkdown/KaTeX — math, tables, fenced code, images, HTML.
    /// Hang sample build 664: scrolling the chat scroller onto a bullet-list
    /// intro mounted WKWebView in LazyVStack and spun sizeThatFits at 100% CPU.
    static func requiresWebRenderer(_ preparedText: String) -> Bool {
        #if DEBUG
        assert(classifierSelfCheckPassed, "Agent Chat Markdown routing self-check failed")
        #endif
        return requiresWebRendererUnchecked(preparedText)
    }

    private static func requiresWebRendererUnchecked(_ preparedText: String) -> Bool {
        if preparedText.contains("$$")
            || preparedText.contains("\\(")
            || preparedText.contains("\\[")
            || preparedText.contains("\\begin{")
            || hasInlineMath(in: preparedText)
            || preparedText.contains("![") {
            return true
        }

        let lines = preparedText.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        for lineSlice in lines {
            let line = String(lineSlice)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if needsWebBlockLine(trimmed) {
                return true
            }
        }
        return false
    }

    private static func hasInlineMath(in text: String) -> Bool {
        guard let inlineMath else { return false }
        return inlineMath.firstMatch(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ) != nil
    }

    /// Only blocks the native renderer cannot lay out safely in a LazyVStack.
    private static func needsWebBlockLine(_ trimmed: String) -> Bool {
        if trimmed.hasPrefix("```")
            || trimmed.hasPrefix("~~~")
            || isTableDelimiter(trimmed)
            || trimmed.hasPrefix("[^")
            || isHTMLBlock(trimmed) {
            return true
        }
        // Pipe tables: header row then delimiter; catch dense pipe rows early.
        if trimmed.contains("|"),
           trimmed.filter({ $0 == "|" }).count >= 2,
           !trimmed.hasPrefix("[[") {
            return true
        }
        return false
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        guard line.contains("|"), line.contains("-") else { return false }
        return line.allSatisfy { $0 == "|" || $0 == ":" || $0 == "-" || $0.isWhitespace }
    }

    private static func isHTMLBlock(_ line: String) -> Bool {
        guard line.first == "<", line.count > 1 else { return false }
        let marker = line[line.index(after: line.startIndex)]
        // Route any line-leading HTML declaration/tag through the mature
        // renderer instead of maintaining a permanently incomplete tag list.
        return marker.isLetter || marker == "!" || marker == "?" || marker == "/"
    }

    #if DEBUG
    private static let classifierSelfCheckPassed: Bool = {
        let cases: [(String, Bool)] = [
            ("普通单段文字", false),
            ("带有 **行内强调** 的单段", false),
            ("两段文字\n\n第二段", false),
            ("# 标题", false),
            ("> 短引用", false),
            ("- 单项列表", false),
            ("1. 有序列表", false),
            ("Setext 标题\n===", false),
            ("$x=1$", true),
            ("$$y=2$$", true),
            ("| a | b |\n| --- | --- |", true),
            ("```\ncode\n```", true),
            ("![图](x.png)", true),
            ("<!-- HTML comment -->", true),
            ("<p>段落</p>", true),
            ("<section>章节</section>", true),
            ("<article>文章</article>", true),
            ("<nav>导航</nav>", true),
            ("<script>void 0</script>", true),
        ]
        return cases.allSatisfy { requiresWebRendererUnchecked($0.0) == $0.1 }
    }()
    #endif

    /// Standalone `[ ... \cmd ... ]` (single- or multi-line) → `$$...$$`.
    /// Citations like `[材料：…]` are stripped before this runs.
    private static func convertBracketDisplayMath(in text: String) -> String {
        var result = text
        if let multi = try? NSRegularExpression(
            pattern: #"\[\s*\n([\s\S]*?\\[A-Za-z]+[\s\S]*?)\n\s*\]"#
        ) {
            result = replaceMatches(in: result, regex: multi) { match in
                "$$\n\(match)\n$$"
            }
        }
        if let single = try? NSRegularExpression(
            pattern: #"(?m)^\[\s*([^\n\]]*?\\[A-Za-z]+[^\n\]]*?)\]\s*$"#
        ) {
            result = replaceMatches(in: result, regex: single) { match in
                "$$\(match)$$"
            }
        }
        return result
    }

    /// `\hat\beta` / `\hat y` → `\hat{\beta}` / `\hat{y}` (KaTeX-friendly).
    private static func fixHatArguments(in text: String) -> String {
        var result = text
        if let spaced = try? NSRegularExpression(pattern: #"\\hat\s+([A-Za-z\\]+)"#) {
            result = replaceMatches(in: result, regex: spaced) { match in
                "\\hat{\(match)}"
            }
        }
        if let glued = try? NSRegularExpression(pattern: #"\\hat(?!\{)(\\[A-Za-z]+|[A-Za-z])"#) {
            result = replaceMatches(in: result, regex: glued) { match in
                "\\hat{\(match)}"
            }
        }
        return result
    }

    private static func replaceMatches(
        in text: String,
        regex: NSRegularExpression,
        transform: (String) -> String
    ) -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else { return text }
        var output = text
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  let full = Range(match.range, in: output),
                  let capture = Range(match.range(at: 1), in: output) else { continue }
            let inner = String(output[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
            output.replaceSubrange(full, with: transform(inner))
        }
        return output
    }
}
