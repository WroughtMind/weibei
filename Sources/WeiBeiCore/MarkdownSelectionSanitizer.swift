import Foundation

public enum MarkdownSelectionSanitizer {
    public static func clean(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map(cleanLine)
            .joined(separator: "\n")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanLine(_ rawLine: String) -> String {
        rawLine.replacingOccurrences(
            of: #"^\s*(?:>\s*)*(?:\\)?\[![A-Za-z][A-Za-z0-9_-]*\][+-]?\s*"#,
            with: "",
            options: .regularExpression
        )
    }
}
