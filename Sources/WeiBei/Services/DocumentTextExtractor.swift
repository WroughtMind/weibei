import AppKit
import Foundation
import PDFKit
import WeiBeiCore

enum DocumentTextExtractor {
    private static var pdfTextCache: [String: String] = [:]
    private static var fileTextCache: [String: String] = [:]

    static func text(for item: StudyItem) -> String? {
        guard let url = item.url else { return nil }

        switch item.kind {
        case .pdf:
            return pdfText(url: url)
        case .html:
            return cachedFileText(url: url, load: htmlText)
        case .markdown, .text:
            return cachedFileText(url: url) { fileURL in
                try? String(contentsOf: fileURL, encoding: .utf8)
            }
        }
    }

    private static func pdfText(url: URL) -> String? {
        let cacheKey = fileCacheKey(for: url)
        if let cached = pdfTextCache[cacheKey] {
            return cached
        }

        guard let document = PDFDocument(url: url) else { return nil }
        let textLayerText = pagedText(from: document)
        let text = textLayerText.isEmpty ? PDFOCRTextExtractor.text(from: document) : textLayerText
        if let text, !text.isEmpty {
            pdfTextCache[cacheKey] = text
            return text
        }
        return nil
    }

    private static func pagedText(from document: PDFDocument) -> String {
        (0..<max(document.pageCount, 0)).compactMap { index in
            guard let page = document.page(at: index),
                  let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return "第 \(index + 1) 页\n\(text)"
        }
        .joined(separator: "\n\n")
    }

    private static func fileCacheKey(for url: URL) -> String {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)#\(modified)"
    }

    private static func cachedFileText(url: URL, load: (URL) -> String?) -> String? {
        let cacheKey = fileCacheKey(for: url)
        if let cached = fileTextCache[cacheKey] {
            return cached
        }
        guard let text = load(url) else { return nil }
        if !text.isEmpty {
            fileTextCache[cacheKey] = text
        }
        return text
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
