import Foundation
import SwiftStreamingMarkdown

/// Finite, structure-only cleanup for historic agent formula input. Mathematical
/// commands are never renamed, removed, or simplified here.
enum AgentMarkdownInputNormalizer {
    private static let bracketMultiLineMath = try! NSRegularExpression(
        pattern: #"(?m)^[ \t]*\[\s*\n([\s\S]*?\\[A-Za-z]+[\s\S]*?)\n\s*\][ \t]*$"#
    )
    private static let bracketSingleLineMath = try! NSRegularExpression(
        pattern: #"(?m)^\[\s*([^\n\]]*?\\[A-Za-z]+[^\n\]]*?)\]\s*$"#
    )
    private static let historicHatY = try! NSRegularExpression(
        pattern: #"\\hat[ \t]+(y)(?![A-Za-z])"#
    )
    static func normalize(_ raw: String, isStreaming: Bool) -> String {
        guard !isStreaming else { return raw }
        let fullRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        let completeCandidates = [bracketMultiLineMath, bracketSingleLineMath, historicHatY]
        let hasHistoricCandidate = completeCandidates.contains {
            $0.firstMatch(in: raw, range: fullRange) != nil
        }
        guard hasHistoricCandidate else { return raw }

        let codeRanges = MarkdownCodeRangeScanner.ranges(in: raw).sorted {
            $0.location < $1.location
        }
        let stable = raw
        var collected: [Replacement] = []
        collected += replacements(in: stable, regex: bracketMultiLineMath, codeRanges: codeRanges) {
            "$$\n\(normalizingHistoricHatY(in: $0))\n$$"
        }
        collected += replacements(in: stable, regex: bracketSingleLineMath, codeRanges: codeRanges) {
            "$$\(normalizingHistoricHatY(in: $0))$$"
        }
        let bracketRanges = collected.map(\.range).sorted { $0.location < $1.location }
        collected += replacements(in: stable, regex: historicHatY, codeRanges: codeRanges) {
            "\\hat{\($0)}"
        }.filter { !overlaps($0.range, bracketRanges) }
        let result = NSMutableString(string: stable)
        for replacement in collected.sorted(by: { $0.range.location > $1.range.location }) {
            result.replaceCharacters(in: replacement.range, with: replacement.value)
        }
        return result as String
    }

    private struct Replacement {
        let range: NSRange
        let value: String
    }

    private static func replacements(
        in text: String,
        regex: NSRegularExpression,
        codeRanges: [NSRange],
        transform: (String) -> String
    ) -> [Replacement] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard !overlaps(match.range, codeRanges),
                  let captureRange = Range(match.range(at: 1), in: text) else { return nil }
            let content = text[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
            return Replacement(range: match.range, value: transform(content))
        }
    }

    private static func overlaps(_ range: NSRange, _ sortedRanges: [NSRange]) -> Bool {
        var lower = 0
        var upper = sortedRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(sortedRanges[middle]) <= range.location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower < sortedRanges.count else { return false }
        return sortedRanges[lower].location < NSMaxRange(range)
    }

    private static func normalizingHistoricHatY(in text: String) -> String {
        let result = NSMutableString(string: text)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in historicHatY.matches(in: text, range: range).reversed() {
            guard let capture = Range(match.range(at: 1), in: text) else { continue }
            result.replaceCharacters(in: match.range, with: "\\hat{\(text[capture])}")
        }
        return result as String
    }
}
