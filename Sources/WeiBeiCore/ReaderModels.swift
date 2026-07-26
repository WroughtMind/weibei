import CoreGraphics
import Foundation

public struct QuietInsight: Hashable {
    public var body: String
    public var noteBlock: String

    public init(body: String, noteBlock: String) {
        self.body = body
        self.noteBlock = noteBlock
    }

    public static func agent(materialTitle: String, answer: String, language: WeiBeiInterfaceLanguage = .chinese) -> QuietInsight? {
        let body = String(answer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(360))
        guard !body.isEmpty else { return nil }
        return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
    }

    public static func make(materialTitle: String, materialText: String, noteText: String, selectionText: String?, language: WeiBeiInterfaceLanguage = .chinese) -> QuietInsight {
        let hasMaterial = !materialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let selection = selectionText?.trimmingCharacters(in: .whitespacesAndNewlines), !selection.isEmpty {
            let excerpt = short(selection, count: 54)
            if !noteText.contains(String(selection.prefix(18))) {
                let body = language.text("选区还没有进入笔记：\(excerpt)。先收为摘录，再补一句自己的判断。", "The selection is not in the note yet: \(excerpt). Save it as an excerpt, then add one sentence of your own judgment.")
                return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
            }
            let body = hasMaterial
                ? language.text("选区已经出现在笔记里。下一步更适合追问它和当前材料其他段落的关系。", "The selection is already in the note. Next, ask how it relates to other parts of the current material.")
                : language.text("选区已经出现在笔记里。下一步更适合追问这段话还能补哪条依据。", "The selection is already in the note. Next, ask what evidence could support this passage.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        let candidate = firstUsefulLine(in: materialText)
        guard !candidate.isEmpty else {
            let noteCandidate = firstUsefulLine(in: noteText)
            if !noteCandidate.isEmpty {
                let body = language.text("当前笔记有一条可以继续整理：\(short(noteCandidate, count: 58))。建议补来源或写成问题。", "The current note has a line worth organizing: \(short(noteCandidate, count: 58)). Add a source or turn it into a question.")
                return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
            }
            let body = language.text("当前没有可读材料。先导入或选择一份 HTML、PDF 或 Markdown。", "There is no readable material yet. Import or choose an HTML, PDF, or Markdown file first.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        if !noteText.contains(String(candidate.prefix(14))) {
            let body = language.text("当前材料有一条还没进入笔记：\(short(candidate, count: 58))。建议补到摘录区。", "The current material has a line not yet in the note: \(short(candidate, count: 58)). Add it to the excerpts.")
            return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
        }

        let body = language.text("当前笔记已经覆盖材料开头。建议检查是否写了来源、例子和待追问。", "The current note already covers the start of the material. Check whether it includes sources, examples, and follow-up questions.")
        return QuietInsight(body: body, noteBlock: noteBlock(body: body, source: materialTitle, language: language))
    }

    private static func noteBlock(body: String, source: String, language: WeiBeiInterfaceLanguage) -> String {
        """
        > [!note] \(language.text("阅读线索", "Reading clue"))
        >
        > \(body)
        >
        > \(language.text("来源", "Source"))：\(source)
        """
    }

    private static func firstUsefulLine(in text: String) -> String {
        text.components(separatedBy: .newlines)
            .map(cleanMarkdownLine)
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "。！？.!?")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: isUsefulCandidate) ?? ""
    }

    private static func cleanMarkdownLine(_ rawLine: String) -> String {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.hasPrefix("```"), !line.hasPrefix("|") else { return "" }
        line = line.replacingOccurrences(of: #"!\[[^\]]*\]\([^\)]*\)"#, with: " ", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"\[\[([^\]\|]+)(?:\|[^\]]+)?\]\]"#, with: "$1", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^>\s*(?:\[[!][^\]]+\][+-]?\s*)?"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[-*+]\s+\[[ xX]\]\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[-*+]?\s*\d*\.?\s+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"[*_`~=#]"#, with: "", options: .regularExpression)
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsefulCandidate(_ text: String) -> Bool {
        guard text.count >= 8, !text.contains("|") else { return false }
        let readableCount = text.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || (0x4E00...0x9FFF).contains($0.value)
        }.count
        return readableCount >= 6
    }

    private static func short(_ text: String, count: Int) -> String {
        text.count > count ? "\(text.prefix(count))..." : text
    }
}

public enum PageNavigator {
    public static func previous(_ index: Int) -> Int {
        max(index - 1, 0)
    }

    public static func next(_ index: Int, pageCount: Int) -> Int {
        min(index + 1, max(pageCount - 1, 0))
    }

    public static func display(_ index: Int, pageCount: Int) -> String {
        "\(min(index + 1, max(pageCount, 1))) / \(max(pageCount, 1))"
    }
}

public enum TopBarLeadingInset {
    public static func value(isFullScreen: Bool) -> Double {
        isFullScreen ? 12 : 80
    }
}

public enum PDFModeChipPresentation {
    public static func showsLabel(isExpanded: Bool) -> Bool {
        isExpanded
    }

    public static func fillOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.86 }
        return isHovering ? 0.78 : 0.66
    }

    public static func strokeOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.58 }
        return isHovering ? 0.34 : 0.18
    }

    public static func controlOpacity(isExpanded: Bool, isHovering: Bool) -> Double {
        if isExpanded { return 0.94 }
        return isHovering ? 0.84 : 0.70
    }
}

public enum ReaderSearch {
    public static func cleaned(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func firstMatch(in text: String, query: String) -> NSRange? {
        let query = cleaned(query)
        guard !query.isEmpty else { return nil }
        let range = (text as NSString).range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        return range.location == NSNotFound ? nil : range
    }
}

public enum LibraryNavigator {
    public static func adjacentID(in ids: [String], selectedID: String?, step: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let selectedID, let index = ids.firstIndex(of: selectedID) else {
            return ids[0]
        }
        return ids[(index + step + ids.count) % ids.count]
    }
}
