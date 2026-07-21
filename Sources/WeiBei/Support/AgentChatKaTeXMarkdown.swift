import Foundation

/// Prepares agent markdown so Milkdown/KaTeX can parse model output that uses
/// pseudo-delimiters like `[ y_i=\hat y_i ]` instead of `$$...$$` / `\[...\]`.
enum AgentChatKaTeXMarkdown {
    static func prepare(_ raw: String) -> String {
        var text = raw
        text = convertBracketDisplayMath(in: text)
        text = fixHatArguments(in: text)
        return text
    }

    static func containsRecognizableMath(_ text: String) -> Bool {
        text.contains("$$")
            || text.contains("\\(")
            || text.contains("\\[")
            || text.contains("$")
    }

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
