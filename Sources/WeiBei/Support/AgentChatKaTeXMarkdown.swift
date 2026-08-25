import Foundation

/// Prepares agent markdown so Milkdown/KaTeX can parse model output that uses
/// pseudo-delimiters like `[ y_i=\hat y_i ]` instead of `$$...$$` / `\[...\]`.
enum AgentChatKaTeXMarkdown {
    private static let inlineMath = try? NSRegularExpression(
        pattern: #"(?<!\\)\$(?!\s)(?:\\.|[^$\n])+\$(?!\d)"#
    )
    private static let singleLineDisplayMath = try? NSRegularExpression(
        pattern: #"^[ \t]*\$\$([^$\n]+)\$\$[ \t]*$"#,
        options: [.anchorsMatchLines]
    )
    private static let bracketMultiLineMath = try? NSRegularExpression(
        pattern: #"\[\s*\n([\s\S]*?\\[A-Za-z]+[\s\S]*?)\n\s*\]"#
    )
    private static let bracketSingleLineMath = try? NSRegularExpression(
        pattern: #"(?m)^\[\s*([^\n\]]*?\\[A-Za-z]+[^\n\]]*?)\]\s*$"#
    )
    private static let hatSpacedArgument = try? NSRegularExpression(pattern: #"\\hat\s+([A-Za-z\\]+)"#)
    private static let hatGluedArgument = try? NSRegularExpression(pattern: #"\\hat(?!\{)(\\[A-Za-z]+|[A-Za-z])"#)

    /// Streaming tails whose prepared form depends on characters not yet
    /// received (`\hat \b` vs `\hat \beta`, an unclosed `$$`, `[`, `<`, `\`).
    /// Withheld while streaming so every prepared prefix stays a strict prefix
    /// of the next one — otherwise prepare rewrites already-shown characters
    /// and the WebView does a full re-parse (the visible flash).
    private static let undecidableStreamingTail = try? NSRegularExpression(
        pattern: #"(?:\$\$[^$\n]+\$\$[^\n]{0,7}|\$\$[^$\n]*\$?|\$+|\\h(?:a(?:t[\s\\]*[A-Za-z]*)?)?|\\\[[^\]\n]*(?:\\\][^\]\n]{0,7})?|\\\([^)\n]*(?:\\\)[^)\n]{0,7})?|<\/?[A-Za-z][^>\n]*|<|\\)$"#
    )
    private static let undecidableStreamingMathLine = try? NSRegularExpression(
        pattern: #"(?:^|\n)[ \t]*\[[^\]\n]*(?:\][ \t]*\n?)?$"#
    )
    private static let undecidableStreamingMultilineBracket = try? NSRegularExpression(
        pattern: #"(?:^|\n)[ \t]*\[[ \t]*\n(?:(?!\n[ \t]*\])[\s\S])*$"#
    )

    static func withholdUndecidableStreamingTail(_ text: String) -> String {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var cut = text.endIndex
        if let match = undecidableStreamingTail?.firstMatch(in: text, range: nsRange),
           let range = Range(match.range, in: text) {
            cut = range.lowerBound
        }
        for pattern in [undecidableStreamingMathLine, undecidableStreamingMultilineBracket] {
            guard let match = pattern?.firstMatch(in: text, range: nsRange),
                  let range = Range(match.range, in: text) else { continue }
            let start = text[range.lowerBound] == "\n"
                ? text.index(after: range.lowerBound)
                : range.lowerBound
            if start < cut { cut = start }
        }
        return cut < text.endIndex ? String(text[..<cut]) : text
    }

    static func prepare(_ raw: String) -> String {
        var text = raw
        text = convertBracketDisplayMath(in: text)
        text = expandSingleLineDisplayMath(in: text)
        text = fixHatArguments(in: text)
        return text
    }

    /// `$$x$$` on one line parses as INLINE math (micromark math flow needs the
    /// fences on their own lines), so block formulas stayed left-aligned at
    /// text size. Models emit the one-line form constantly — expand it so the
    /// editor produces a real math_block and the displayMode upgrade applies.
    static func expandSingleLineDisplayMath(in text: String) -> String {
        #if DEBUG
        assert(displayMathExpansionSelfCheckPassed, "single-line $$ expansion self-check failed")
        #endif
        guard text.contains("$$") else { return text }
        return expandSingleLineDisplayMathUnchecked(text)
    }

    #if DEBUG
    private static let displayMathExpansionSelfCheckPassed: Bool = {
        let expanded = expandSingleLineDisplayMathUnchecked("前文\n\n$$a + b$$\n\n后文 $c$ 与 $$d$$ 行内混排")
        return expanded.contains("$$\na + b\n$$")
            && expanded.contains("与 $$d$$ 行内混排")
    }()
    #endif

    private static func expandSingleLineDisplayMathUnchecked(_ text: String) -> String {
        guard let pattern = singleLineDisplayMath else { return text }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        for match in pattern.matches(in: text, range: fullRange).reversed() {
            guard let matchRange = Range(match.range, in: result),
                  let contentRange = Range(match.range(at: 1), in: text) else { continue }
            let content = String(text[contentRange]).trimmingCharacters(in: .whitespaces)
            result.replaceSubrange(matchRange, with: "$$\n\(content)\n$$")
        }
        return result
    }

    /// Keep ordinary one-paragraph / inline Markdown on native SwiftUI text.
    /// WebKit is reserved for syntax whose layout or rendering actually needs
    /// the mature block renderer (paragraphs, lists, tables, code, math, etc.).
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
            || preparedText.contains("[[")
            || preparedText.contains("![") {
            return true
        }

        let lines = preparedText.split(
            omittingEmptySubsequences: false,
            whereSeparator: \.isNewline
        )
        var hasContent = false
        var hasGapAfterContent = false
        for lineSlice in lines {
            let line = String(lineSlice)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if hasContent { hasGapAfterContent = true }
                continue
            }
            if hasGapAfterContent {
                return true
            }
            hasContent = true
            if isBlockLine(trimmed, original: line) {
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

    private static func isBlockLine(_ trimmed: String, original: String) -> Bool {
        if isHeading(trimmed)
            || trimmed.hasPrefix(">")
            || trimmed.hasPrefix("```")
            || trimmed.hasPrefix("~~~")
            || trimmed.hasPrefix("- ")
            || trimmed.hasPrefix("* ")
            || trimmed.hasPrefix("+ ")
            || isOrderedListItem(trimmed)
            || isHorizontalRule(trimmed)
            || isSetextUnderline(trimmed)
            || isTableDelimiter(trimmed)
            || trimmed.hasPrefix("[^")
            || isHTMLBlock(trimmed)
            || original.hasPrefix("\t")
            || original.hasPrefix("    ") {
            return true
        }
        return false
    }

    private static func isHeading(_ line: String) -> Bool {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount), line.count > markerCount else { return false }
        let markerEnd = line.index(line.startIndex, offsetBy: markerCount)
        return line[markerEnd].isWhitespace
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count < line.count else { return false }
        let punctuationIndex = line.index(line.startIndex, offsetBy: digits.count)
        guard line[punctuationIndex] == "." || line[punctuationIndex] == ")" else { return false }
        let contentIndex = line.index(after: punctuationIndex)
        return contentIndex < line.endIndex && line[contentIndex].isWhitespace
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first, "-*_".contains(marker) else {
            return false
        }
        return compact.allSatisfy { $0 == marker }
    }

    private static func isSetextUnderline(_ line: String) -> Bool {
        guard let marker = line.first, marker == "=" || marker == "-" else { return false }
        return line.allSatisfy { $0 == marker }
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
            ("Setext 标题\n===", true),
            ("<!-- HTML comment -->", true),
            ("<p>段落</p>", true),
            ("<section>章节</section>", true),
            ("<article>文章</article>", true),
            ("<nav>导航</nav>", true),
            ("<script>void 0</script>", true),
            ("> 短引用", true),
            ("- 单项列表", true),
        ]
        return cases.allSatisfy { requiresWebRendererUnchecked($0.0) == $0.1 }
    }()
    #endif

    /// Standalone `[ ... \cmd ... ]` (single- or multi-line) → `$$...$$`.
    /// Citations like `[材料：…]` are stripped before this runs.
    private static func convertBracketDisplayMath(in text: String) -> String {
        var result = text
        if let multi = bracketMultiLineMath {
            result = replaceMatches(in: result, regex: multi) { match in
                "$$\n\(match)\n$$"
            }
        }
        if let single = bracketSingleLineMath {
            result = replaceMatches(in: result, regex: single) { match in
                "$$\(match)$$"
            }
        }
        return result
    }

    /// `\hat\beta` / `\hat y` → `\hat{\beta}` / `\hat{y}` (KaTeX-friendly).
    private static func fixHatArguments(in text: String) -> String {
        var result = text
        if let spaced = hatSpacedArgument {
            result = replaceMatches(in: result, regex: spaced) { match in
                "\\hat{\(match)}"
            }
        }
        if let glued = hatGluedArgument {
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
