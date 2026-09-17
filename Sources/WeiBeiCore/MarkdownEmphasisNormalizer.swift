import Foundation
import Markdown

/// Shared Chinese emphasis boundaries; code remains byte-for-byte unchanged.
public enum MarkdownEmphasisNormalizer {
    // Match the editor's emphasis boundary rules for Chinese punctuation.
    private static let emphasisRules: [(NSRegularExpression, String)] = [
        (#"([\p{L}\p{N}])(\*\*|__)(?=[\p{Ps}\p{Pi}])"#, "$1 $2"),
        (#"(^|[\s\p{P}])(\*\*|__)([^\s*_\n][^*_\n]*\p{P})\2(?=[^\s\p{P}])"#, "$1$2$3$2 "),
        (#"(^|[\s\p{P}])(\*\*|__)([^\s*_\n](?:[^*_\n]*?\S)?)[ \t]+\2(?=\S)"#, "$1$2$3$2")
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static func normalizeEmphasis(_ source: String) -> String {
        Self.emphasisRules.reduce(source) { text, rule in
            rule.0.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count), withTemplate: rule.1)
        }
    }

    public static func prepare(_ source: String) -> (text: String, codeRanges: [NSRange]) {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lineOffsets = [0]
        for line in lines { lineOffsets.append(lineOffsets.last! + line.utf16.count + 1) }
        func offset(_ location: SourceLocation) -> Int {
            let line = lines[min(location.line - 1, lines.count - 1)]
            let bytes = line.utf8.prefix(max(0, location.column - 1))
            return lineOffsets[min(location.line - 1, lines.count - 1)] + String(decoding: bytes, as: UTF8.self).utf16.count
        }
        var protected: [NSRange] = []
        func protect(_ node: any Markup) {
            if node is CodeBlock || node is InlineCode, let range = node.range {
                protected.append(NSRange(location: offset(range.lowerBound), length: offset(range.upperBound) - offset(range.lowerBound)))
            } else { for child in node.children { protect(child) } }
        }
        protect(Document(parsing: source))
        let original = source as NSString
        var normalized = "", previousEnd = 0
        var normalizedCodeRanges: [NSRange] = []
        for range in protected.sorted(by: { $0.location < $1.location }) {
            normalized += normalizeEmphasis(original.substring(with: NSRange(location: previousEnd, length: range.location - previousEnd)))
            normalizedCodeRanges.append(NSRange(location: normalized.utf16.count, length: range.length))
            normalized += original.substring(with: range)
            previousEnd = NSMaxRange(range)
        }
        normalized += normalizeEmphasis(original.substring(from: previousEnd))
        return (normalized, normalizedCodeRanges)
    }
}
