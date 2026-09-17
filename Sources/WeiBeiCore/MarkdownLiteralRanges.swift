import Foundation
import Markdown

/// Source ranges whose spelling must survive display-only prose cleanup.
public enum MarkdownLiteralRanges {
    public static func ranges(in source: String) -> [NSRange] {
        guard !source.isEmpty else { return [] }
        let original = source as NSString
        let breaks = try! NSRegularExpression(pattern: "\r\n|\r|\n")
        let lineOffsets = [0] + breaks.matches(in: source, range: NSRange(location: 0, length: original.length)).map { NSMaxRange($0.range) }
        let lines = zip(lineOffsets, lineOffsets.dropFirst() + [original.length]).map { start, end in
            original.substring(with: NSRange(location: start, length: end - start))
        }
        func offset(_ location: SourceLocation) -> Int {
            let line = min(max(0, location.line - 1), lines.count - 1)
            let bytes = lines[line].utf8.prefix(max(0, location.column - 1))
            return lineOffsets[line] + String(decoding: bytes, as: UTF8.self).utf16.count
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
