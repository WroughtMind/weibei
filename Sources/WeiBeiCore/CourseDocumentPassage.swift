import Foundation
import Markdown

/// 同一页或章节的原文；技术分块不改变它的位置或正文。
public struct CourseDocumentPassage: Sendable, Equatable {
    public var location: String
    public var title: String?
    public var pageIndex: Int?
    public var sectionOrdinal: Int?
    public var text: String

    init(storedLocation: String, text: String) {
        self.text = text
        if storedLocation.hasPrefix("第 "),
           let number = Int(storedLocation.split(separator: " ").dropFirst().first ?? "") {
            pageIndex = number - 1
            location = "page-\(number)"
            title = nil
            sectionOrdinal = nil
        } else {
            let parts = storedLocation.split(separator: " ", maxSplits: 1)
            location = parts.first.map(String.init) ?? ""
            title = parts.dropFirst().first.map(String.init)
            if title?.hasPrefix("html-heading-") == true {
                title = title?.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init)
            }
            pageIndex = nil
            if location.hasPrefix("markdown-heading-"),
               let index = Int(location.dropFirst("markdown-heading-".count)) {
                sectionOrdinal = index + 1
            } else {
                sectionOrdinal = nil
            }
        }
    }

    func matches(page: Int?, location requested: String?) -> Bool {
        if let page { return pageIndex == page - 1 }
        guard let requested, !requested.isEmpty else { return true }
        return location == requested
    }

    public func excerpt(matching query: String, maximumCharacters: Int = 2_000) -> CourseDocumentPassage? {
        guard !query.isEmpty, let match = text.range(of: query, options: .caseInsensitive) else { return nil }
        var result = self
        let start = text.index(match.lowerBound, offsetBy: -maximumCharacters / 4, limitedBy: text.startIndex)
            ?? text.startIndex
        let end = text.index(start, offsetBy: max(maximumCharacters, text.distance(from: start, to: match.upperBound)), limitedBy: text.endIndex)
            ?? text.endIndex
        result.text = String(text[start..<end])
        return result
    }
}

enum CourseMarkdownSections {
    struct Section {
        var location: String
        var title: String?
        var text: String
    }

    static func parse(_ source: String) -> [Section] {
        let lines = source.components(separatedBy: "\n")
        var parsingLines = lines
        // 编辑器将文件头独立显示；保留行数供解析范围回指原文。
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            for index in 0...end { parsingLines[index] = "" }
        }
        // 与编辑器已有的块公式一致：公式内容不产生 Markdown 标题。
        var mathFence = false
        var codeFence: (Character, Int)?
        for index in parsingLines.indices {
            let line = parsingLines[index].trimmingCharacters(in: .whitespaces)
            let marker = line.prefix(while: { $0 == "`" || $0 == "~" })
            if let first = marker.first, marker.count >= 3, marker.allSatisfy({ $0 == first }) {
                if let fence = codeFence {
                    if first == fence.0, marker.count >= fence.1 { codeFence = nil }
                } else if !mathFence { codeFence = (first, marker.count) }
            }
            guard codeFence == nil else { continue }
            if line.hasPrefix("$$") {
                parsingLines[index] = ""
                if mathFence { mathFence = false }
                else if !line.dropFirst(2).contains("$$") { mathFence = true }
            } else if mathFence { parsingLines[index] = "" }
        }
        let document = Document(parsing: parsingLines.joined(separator: "\n"))
        var headings: [(line: Int, title: String)] = []
        func visit(_ node: Markup) {
            if let heading = node as? Heading, let range = heading.range {
                headings.append((range.lowerBound.line - 1, heading.plainText))
            }
            for child in node.children { visit(child) }
        }
        visit(document)
        var result: [Section] = []
        if let first = headings.first, first.line > 0 {
            result.append(Section(location: "", title: nil, text: lines[..<first.line].joined(separator: "\n") + "\n"))
        } else if headings.isEmpty {
            return [Section(location: "", title: nil, text: source)]
        }
        for (index, heading) in headings.enumerated() {
            let end = index + 1 < headings.count ? headings[index + 1].line : lines.count
            let text = lines[heading.line..<end].joined(separator: "\n") + (end < lines.count ? "\n" : "")
            result.append(Section(location: "markdown-heading-\(index)", title: heading.title, text: text))
        }
        return result
    }
}
