import SwiftUI

/// Structured native fallback shown while a cold chat row awaits its WebKit
/// renderer. A single `Text(markdown)` strips block structure, so opening a
/// historical session first showed a dense wall of text. This keeps headings,
/// lists, code fences, quotes and paragraph rhythm recognizable so the wait
/// reads as "almost ready" instead of broken. It is a placeholder only — the
/// WebView remains the authoritative renderer once it measures.
struct AgentMarkdownBlockFallback: View {
    var markdown: String
    var compact = false

    struct Block: Identifiable {
        let id: Int
        let lines: [String]
        let kind: Kind

        enum Kind {
            case heading(level: Int)
            case paragraph
            case bulletList
            case orderedList
            case code(language: String?)
            case quote
            case divider
        }
    }

    @State private var parsedCache: (text: String, blocks: [Block])?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { refreshCacheIfNeeded() }
        .onChange(of: markdown) { _, _ in refreshCacheIfNeeded() }
    }

    private var blocks: [Block] {
        if let cache = parsedCache, cache.text == markdown {
            return cache.blocks
        }
        return AgentMarkdownBlockParser.parse(markdown)
    }

    private func refreshCacheIfNeeded() {
        guard parsedCache?.text != markdown else { return }
        parsedCache = (markdown, AgentMarkdownBlockParser.parse(markdown))
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block.kind {
        case let .heading(level):
            Text(inline(AgentMarkdownBlockParser.headingBody(block.lines.first ?? "")))
                .weiBeiText(headingFontSize(level), weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph:
            Text(inline(block.lines.joined(separator: "\n")))
                .weiBeiText(compact ? 13.2 : 15)
                .lineSpacing(compact ? 4.2 : 5.2)
                .foregroundStyle(WeiBeiTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .bulletList, .orderedList:
            let ordered = block.kind.isOrderedList
            VStack(alignment: .leading, spacing: compact ? 3.4 : 4.4) {
                ForEach(Array(block.lines.enumerated()), id: \.offset) { index, rawLine in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(ordered ? "\(index + 1)." : "•")
                            .weiBeiText(compact ? 13.2 : 15)
                            .foregroundStyle(WeiBeiTheme.ink.opacity(0.72))
                        Text(inline(AgentMarkdownBlockParser.listItemBody(rawLine)))
                            .weiBeiText(compact ? 13.2 : 15)
                            .lineSpacing(compact ? 3.6 : 4.4)
                            .foregroundStyle(WeiBeiTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(
                        .leading,
                        CGFloat(AgentMarkdownBlockParser.listIndentLevel(rawLine)) * (compact ? 12 : 15)
                    )
                }
            }
        case let .code(language):
            VStack(alignment: .leading, spacing: 1.5) {
                if let language, !language.isEmpty {
                    Text(language)
                        .weiBeiText(10.5, weight: .medium)
                        .foregroundStyle(WeiBeiTheme.ink.opacity(0.55))
                }
                ForEach(Array(block.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .weiBeiText(compact ? 11.6 : 12.4, design: .monospaced)
                        .foregroundStyle(WeiBeiTheme.ink.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WeiBeiTheme.paperInset.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .quote:
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(WeiBeiTheme.cinnabar.opacity(0.6))
                    .frame(width: 2.5)
                Text(inline(block.lines.map(AgentMarkdownBlockParser.quoteBody).joined(separator: "\n")))
                    .weiBeiText(compact ? 13 : 14.6)
                    .lineSpacing(compact ? 3.8 : 4.6)
                    .foregroundStyle(WeiBeiTheme.ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .divider:
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.7))
                .frame(height: 1)
                .padding(.vertical, 3)
        }
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        let base: CGFloat = compact ? 13.2 : 15
        switch level {
        case 1: return base + 2.4
        case 2: return base + 1.4
        case 3: return base + 0.7
        default: return base
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

extension AgentMarkdownBlockFallback.Block.Kind {
    var isOrderedList: Bool {
        if case .orderedList = self { return true }
        return false
    }
}

/// Line scanner for the block fallback. Deliberately forgiving: anything it
/// does not recognize becomes a paragraph, so unknown syntax still shows its
/// raw text instead of disappearing.
enum AgentMarkdownBlockParser {
    /// nil = not a fence line; .some(nil) = bare fence; .some(lang) = labeled.
    static func codeFenceLanguage(_ line: String) -> String?? {
        let marker: Character = line.hasPrefix("```") ? "`" : "~"
        guard line.hasPrefix("```") || line.hasPrefix("~~~") else { return nil }
        let fenceCount = line.prefix(while: { $0 == marker }).count
        guard fenceCount >= 3 else { return nil }
        let language = String(line.dropFirst(fenceCount)).trimmingCharacters(in: .whitespaces)
        guard language.allSatisfy({ String($0) != String(marker) }) else { return nil }
        return .some(language.isEmpty ? nil : language)
    }

    static func parse(_ markdown: String) -> [AgentMarkdownBlockFallback.Block] {
        var blocks: [AgentMarkdownBlockFallback.Block] = []
        var paragraph: [String] = []
        var blockIndex = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.init(id: blockIndex, lines: paragraph, kind: .paragraph))
            blockIndex += 1
            paragraph = []
        }

        let lines = markdown.components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let maybeLanguage = codeFenceLanguage(trimmed) {
                flushParagraph()
                var codeLines: [String] = []
                index += 1
                while index < lines.count, codeFenceLanguage(lines[index].trimmingCharacters(in: .whitespaces)) == nil {
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.init(
                    id: blockIndex,
                    lines: codeLines,
                    kind: .code(language: maybeLanguage)
                ))
                blockIndex += 1
            } else if isDivider(trimmed) {
                flushParagraph()
                blocks.append(.init(id: blockIndex, lines: [line], kind: .divider))
                blockIndex += 1
            } else if let level = headingLevel(trimmed) {
                flushParagraph()
                blocks.append(.init(id: blockIndex, lines: [trimmed], kind: .heading(level: level)))
                blockIndex += 1
            } else if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoteLines = [line]
                index += 1
                while index < lines.count,
                      lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoteLines.append(lines[index])
                    index += 1
                }
                blocks.append(.init(id: blockIndex, lines: quoteLines, kind: .quote))
                blockIndex += 1
                continue
            } else if isListLine(trimmed) {
                flushParagraph()
                let ordered = trimmed.first.map(\.isNumber) == true
                var listLines = [line]
                index += 1
                while index < lines.count {
                    let nextTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if isListLine(nextTrimmed) || (!nextTrimmed.isEmpty && isIndented(lines[index])) {
                        listLines.append(lines[index])
                        index += 1
                    } else {
                        break
                    }
                }
                blocks.append(.init(
                    id: blockIndex,
                    lines: listLines,
                    kind: ordered ? .orderedList : .bulletList
                ))
                blockIndex += 1
                continue
            } else if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
            index += 1
        }
        flushParagraph()
        return blocks
    }

    static func headingBody(_ line: String) -> String {
        var rest = Substring(line)
        while let first = rest.first, first == "#" || first == " " || first == "\t" {
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    static func quoteBody(_ line: String) -> String {
        var rest = Substring(line)
        while let first = rest.first, first == ">" || first == " " || first == "\t" {
            rest = rest.dropFirst()
        }
        return String(rest)
    }

    static func listItemBody(_ line: String) -> String {
        var rest = Substring(line).trimmingLeadingWhitespace()
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
            rest = rest.dropFirst(2)
        } else {
            let digits = rest.prefix(while: { $0.isNumber })
            if !digits.isEmpty {
                var afterDigits = rest.dropFirst(digits.count)
                if afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") {
                    afterDigits = afterDigits.dropFirst(2)
                }
                rest = afterDigits
            }
        }
        return String(rest)
    }

    static func listIndentLevel(_ line: String) -> Int {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let spaces = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return min(spaces / 2, 4)
    }

    private static func isIndented(_ line: String) -> Bool {
        line.hasPrefix("  ") || line.hasPrefix("\t")
    }

    private static func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for character in line {
            if character == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        return level
    }

    private static func isDivider(_ line: String) -> Bool {
        guard line.count >= 3,
              let marker = line.first,
              ["-", "*", "_"].contains(marker),
              line.allSatisfy({ $0 == marker }) else {
            return false
        }
        return true
    }

    private static func isListLine(_ line: String) -> Bool {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return true
        }
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3 else { return false }
        let rest = line.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }
}

private extension Substring {
    func trimmingLeadingWhitespace() -> Substring {
        var rest = self
        while let first = rest.first, first == " " || first == "\t" {
            rest = rest.dropFirst()
        }
        return rest
    }
}

/// Quiet loading placeholder for a cold chat row. Deliberately content-free:
/// any real-content preview renders a typography that never matches the
/// WebView's final layout, and that mismatch read as a glitch ("它闪一下") —
/// an abstract skeleton reads as loading instead.
struct AgentMarkdownSkeleton: View {
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(WeiBeiTheme.ink.opacity(0.10))
                .frame(height: compact ? 9 : 11)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(WeiBeiTheme.ink.opacity(0.10))
                .frame(height: compact ? 9 : 11)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(WeiBeiTheme.ink.opacity(0.10))
                .frame(height: compact ? 9 : 11)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(WeiBeiTheme.ink.opacity(0.10))
                .frame(height: compact ? 9 : 11)
                .frame(maxWidth: .infinity)
                .padding(.trailing, compact ? 64 : 96)
        }
        .accessibilityHidden(true)
    }
}
