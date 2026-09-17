import Foundation
import Markdown

/// Display-only tail repair, adapted from Zeron (MIT, Copyright 2026 Wing).
/// Stored, copied and completed Markdown always uses the original source.
public enum MarkdownStreamingDisplay {
    public static let pendingLink = "weibei-pending-link:"

    public static func source(_ source: String) -> String {
        guard let last = Array(Document(parsing: source).children).last, !(last is CodeBlock), !(last is HTMLBlock),
              let start = last.range?.lowerBound else { return source }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let preceding = lines.prefix(start.line - 1).reduce(0) { $0 + $1.utf8.count + 1 }
        let offset = preceding + max(0, start.column - 1)
        let bytes = Array(source.utf8)
        guard offset <= bytes.count else { return source }
        return String(decoding: bytes.prefix(offset), as: UTF8.self)
            + mend(String(decoding: bytes.dropFirst(offset), as: UTF8.self))
    }

    private struct Delimiter { var char: Character; var count: Int; var end: Int }
    private static func mend(_ text: String) -> String {
        let chars = Array(text)
        var delimiters: [Delimiter] = [], brackets: [Int] = []
        var code: (count: Int, end: Int)?
        var lastContent = -1, i = 0
        func at(_ index: Int) -> Character? { chars.indices.contains(index) ? chars[index] : nil }
        func run(_ index: Int) -> Int { chars[index...].prefix { $0 == chars[index] }.count }
        func word(_ char: Character?) -> Bool { char?.isLetter == true || char?.isNumber == true }
        while i < chars.count {
            let char = chars[i]
            if code == nil && char == "\\" { lastContent = min(i + 1, chars.count - 1); i += 2; continue }
            if char == "`" {
                let count = run(i)
                if let open = code {
                    if open.count == count { code = nil } else { lastContent = i + count - 1 }
                } else { code = (count, i + count) }
                i += count; continue
            }
            if code != nil { lastContent = i; i += 1; continue }
            if char == "*" || char == "_" || char == "~" {
                let count = run(i), end = i + run(i)
                let previous = at(i - 1), next = at(end)
                if (char == "~" && count > 2) || (word(previous) && word(next) && (char == "_" || count == 1 && char == "*")) {
                    lastContent = end - 1; i = end; continue
                }
                var remaining = count
                if let previous, !previous.isWhitespace, let index = delimiters.lastIndex(where: { $0.char == char }) {
                    let consumed = min(remaining, delimiters[index].count)
                    delimiters[index].count -= consumed; remaining -= consumed
                    delimiters.removeSubrange((delimiters[index].count == 0 ? index : index + 1)..<delimiters.count)
                }
                if remaining > 0 {
                    if let next, !next.isWhitespace, char != "~" || remaining == 2 {
                        delimiters.append(.init(char: char, count: remaining, end: end))
                    } else { lastContent = end - 1 }
                }
                i = end; continue
            }
            if char == "[" { brackets.append(i); i += 1; continue }
            if char == "]", let open = brackets.popLast() {
                delimiters.removeAll { $0.end > open }
                if at(i + 1) == "(" {
                    var j = i + 2, depth = 0
                    while j < chars.count {
                        if chars[j] == "\\" { j += 2; continue }
                        if chars[j] == "(" { depth += 1 }
                        if chars[j] == ")" {
                            if depth == 0 { break }
                            depth -= 1
                        }
                        j += 1
                    }
                    if j >= chars.count { return String(chars[..<i]) + "](\(pendingLink))" }
                    lastContent = j; i = j + 1; continue
                }
            }
            if !char.isWhitespace { lastContent = i }
            i += 1
        }
        var pending: [(Int, String)] = delimiters.filter { lastContent >= $0.end }
            .map { ($0.end, String(repeating: String($0.char), count: $0.count)) }
        if let code, lastContent >= code.end { pending.append((code.end, String(repeating: "`", count: code.count))) }
        if let open = brackets.last, lastContent > open { pending.append((open, "](\(pendingLink))")) }
        let closers = pending.sorted { $0.0 > $1.0 }.map(\.1).joined()
        if let newline = chars.lastIndex(of: "\n") {
            let tail = String(chars[(newline + 1)...]).drop(while: { $0 == " " || $0 == "\t" })
            if ["-", "--", "=", "=="].contains(String(tail)), newline > 0, !chars[newline - 1].isWhitespace {
                return String(chars[..<newline]) + closers + String(chars[newline...]) + "\u{200B}"
            }
        }
        guard !closers.isEmpty else { return text }
        let whitespace = chars.reversed().prefix { $0.isWhitespace }.count
        let end = chars.count - whitespace
        return String(chars[..<end]) + closers + String(chars[end...])
    }
}
