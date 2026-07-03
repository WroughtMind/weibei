import AppKit
import Foundation
import PDFKit
import WeiBeiCore

enum DocumentTextExtractor {
    static func text(for item: StudyItem) -> String? {
        guard let url = item.url else { return nil }

        switch item.kind {
        case .pdf:
            return PDFDocument(url: url)?.string
        case .html:
            return htmlText(url: url)
        case .markdown, .text:
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    private static func htmlText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        return String(data: data, encoding: .utf8)
    }
}
