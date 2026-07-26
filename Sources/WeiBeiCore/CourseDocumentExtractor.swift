import AppKit
import Foundation

/**
 * Extracts searchable text and stable HTML heading anchors from supported course documents.
 */
enum CourseDocumentExtractor {
    static func text(for item: StudyItem) -> String? {
        guard let url = item.url else { return nil }
        switch item.kind {
        case .html:
            guard let data = try? Data(contentsOf: url) else { return nil }
            let headings = htmlHeadings(in: data)
            if let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
            ) {
                let headingText = headings.map { "# \($0)" }.joined(separator: "\n")
                return headingText.isEmpty ? attributed.string : "\(headingText)\n\n\(attributed.string)"
            }
            return String(data: data, encoding: .utf8)
        case .markdown, .text:
            return try? String(contentsOf: url, encoding: .utf8)
        case .pdf:
            return nil
        }
    }
    
    static func htmlHeadings(in data: Data) -> [String] {
        guard let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(
                  pattern: #"<h([1-4])\b[^>]*>(.*?)</h\1\s*>"#,
                  options: [.caseInsensitive, .dotMatchesLineSeparators]
              ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var headings: [String] = []
        var locationIDCounts: [String: Int] = [:]
        let matches = regex.matches(in: html, range: range)
        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges > 2,
                  let matchRange = Range(match.range(at: 2), in: html) else { continue }
            let text = htmlPlainText(String(html[matchRange]))
            if !text.isEmpty {
                let bodyStart = NSMaxRange(match.range)
                let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : range.length
                let body: String
                if bodyStart <= bodyEnd,
                   let bodyRange = Range(NSRange(location: bodyStart, length: bodyEnd - bodyStart), in: html) {
                    body = htmlPlainText(String(html[bodyRange]))
                } else {
                    body = ""
                }
                let baseLocationID = htmlSectionLocationID(title: text, body: body)
                let count = locationIDCounts[baseLocationID, default: 0] + 1
                locationIDCounts[baseLocationID] = count
                let locationID = count == 1 ? baseLocationID : "\(baseLocationID)-dup-\(count)"
                headings.append("[\(locationID)][html-heading-\(index)] \(text.prefix(300))")
            }
        }
        return headings
    }
    
    static func htmlPlainText(_ fragment: String) -> String {
        let data = Data("<html><body>\(fragment)</body></html>".utf8)
        return (try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ))?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    static func htmlSectionLocationID(title: String, body: String) -> String {
        let source = "\(title)|\(body)".lowercased()
        let normalized = String(source.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }.map(String.init).joined().prefix(500))
        var hash: UInt32 = 2_166_136_261
        for byte in normalized.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "html-section-%08x", hash)
    }
    
    static func hasMeaningfulText(_ text: String) -> Bool {
        text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.count >= 20
    }
    
    static func chunked(_ text: String, maximumCharacters: Int) -> [String] {
        guard text.count > maximumCharacters else { return text.isEmpty ? [] : [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maximumCharacters, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }
}
