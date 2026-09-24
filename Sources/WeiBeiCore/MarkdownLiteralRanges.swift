import Foundation
import Markdown

/// Source ranges whose spelling must survive display-only prose cleanup.
public enum AgentCitationMarkup {
    private static let pattern = #"\[(材料|笔记|选区|学习记录|学习记忆|会话|问答)[：:]\s*([^\]\n]{1,300})\]"#
    private static let regex = try? NSRegularExpression(pattern: pattern)

    public static func displayText(from text: String) -> String {
        guard let regex, text.contains("[") else { return text }
        let literals = MarkdownLiteralRanges.ranges(in: text)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range).filter { match in
            !literals.contains(where: { NSIntersectionRange($0, match.range).length > 0 })
        }
        var cleaned = text
        for match in matches.reversed() {
            if let span = Range(match.range, in: cleaned) { cleaned.removeSubrange(span) }
        }
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : cleaned
    }
}

public enum MarkdownLiteralRanges {
    public static func ranges(in source: String) -> [NSRange] {
        guard !source.isEmpty else { return [] }
        let original = source as NSString
        let breaks = try! NSRegularExpression(pattern: "\r\n|\r|\n")
        var lineOffsets = [0]
        for match in breaks.matches(in: source, range: NSRange(location: 0, length: original.length)) {
            lineOffsets.append(NSMaxRange(match.range))
        }
        lineOffsets.append(original.length)
        func offset(_ location: SourceLocation) -> Int {
            let line = min(max(0, location.line - 1), lineOffsets.count - 2)
            let start = lineOffsets[line]
            let text = original.substring(with: NSRange(location: start, length: lineOffsets[line + 1] - start))
            return start + String(decoding: text.utf8.prefix(max(0, location.column - 1)), as: UTF8.self).utf16.count
        }
        var ranges: [NSRange] = []
        func visit(_ node: any Markup) {
            if node is CodeBlock || node is InlineCode || node is HTMLBlock || node is InlineHTML || node is Link || node is Image,
               let range = node.range {
                let start = offset(range.lowerBound)
                ranges.append(NSRange(location: start, length: offset(range.upperBound) - start))
            } else {
                for child in node.children { visit(child) }
            }
        }
        visit(Document(parsing: source))
        return ranges
    }
}
