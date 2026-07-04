import AppKit
import Foundation
import PDFKit
import WeiBeiCore

enum DocumentTextExtractor {
    private static var pdfTextCache: [String: String] = [:]

    static func text(for item: StudyItem) -> String? {
        guard let url = item.url else { return nil }

        switch item.kind {
        case .pdf:
            return pdfText(url: url)
        case .html:
            return htmlText(url: url)
        case .markdown, .text:
            return try? String(contentsOf: url, encoding: .utf8)
        }
    }

    private static func pdfText(url: URL) -> String? {
        let cacheKey = pdfCacheKey(for: url)
        if let cached = pdfTextCache[cacheKey] {
            return cached
        }

        guard let document = PDFDocument(url: url) else { return nil }
        let textLayerText = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = textLayerText.isEmpty ? PDFOCRTextExtractor.text(from: document) : textLayerText
        if let text, !text.isEmpty {
            pdfTextCache[cacheKey] = text
            return text
        }
        return nil
    }

    private static func pdfCacheKey(for url: URL) -> String {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)#\(modified)"
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
