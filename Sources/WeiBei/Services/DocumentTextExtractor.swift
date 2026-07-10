import AppKit
import Foundation
import PDFKit
import WeiBeiCore

enum DocumentTextExtractor {
    private enum TextCache {
        case pdf
        case pdfIndex
        case file
    }

    private static let cacheLock = NSLock()
    private static var pdfTextCache: [String: String] = [:]
    private static var pdfIndexTextCache: [String: String] = [:]
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

    static func indexText(for item: StudyItem, maximumCharacters: Int = 24_000) -> String? {
        guard let url = item.url else { return nil }
        let text: String?
        switch item.kind {
        case .pdf:
            let cacheKey = fileCacheKey(for: url)
            if let cached = cachedValue(for: cacheKey, cache: .pdf) {
                text = cached
            } else {
                let indexCacheKey = "\(cacheKey)#\(maximumCharacters)"
                if let cached = cachedValue(for: indexCacheKey, cache: .pdfIndex) {
                    text = cached
                } else {
                    let indexed = pdfIndexText(url: url, maximumCharacters: maximumCharacters)
                    if let indexed, !indexed.isEmpty {
                        store(indexed, for: indexCacheKey, cache: .pdfIndex)
                    }
                    text = indexed
                }
            }
        case .html, .markdown, .text:
            text = self.text(for: item)
        }
        guard let text, !text.isEmpty else { return nil }
        return String(text.prefix(maximumCharacters))
    }

    private static func pdfText(url: URL) -> String? {
        let cacheKey = fileCacheKey(for: url)
        if let cached = cachedValue(for: cacheKey, cache: .pdf) {
            return cached
        }

        guard let document = PDFDocument(url: url) else { return nil }
        let textLayerText = pagedText(from: document)
        let text = textLayerText.isEmpty ? PDFOCRTextExtractor.text(from: document) : textLayerText
        if let text, !text.isEmpty {
            store(text, for: cacheKey, cache: .pdf)
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

    private static func pdfIndexText(url: URL, maximumCharacters: Int) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        var sections: [String] = []
        var characterCount = 0
        for index in 0..<min(document.pageCount, 32) {
            guard let page = document.page(at: index),
                  let pageText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !pageText.isEmpty else { continue }
            let section = "第 \(index + 1) 页\n\(pageText)"
            sections.append(section)
            characterCount += section.count
            if characterCount >= maximumCharacters { break }
        }
        let text = sections.joined(separator: "\n\n")
        return text.isEmpty ? nil : String(text.prefix(maximumCharacters))
    }

    private static func fileCacheKey(for url: URL) -> String {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(url.path)#\(modified)"
    }

    private static func cachedFileText(url: URL, load: (URL) -> String?) -> String? {
        let cacheKey = fileCacheKey(for: url)
        if let cached = cachedValue(for: cacheKey, cache: .file) {
            return cached
        }
        guard let text = load(url) else { return nil }
        if !text.isEmpty {
            store(text, for: cacheKey, cache: .file)
        }
        return text
    }

    private static func cachedValue(for key: String, cache: TextCache) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        switch cache {
        case .pdf:
            return pdfTextCache[key]
        case .pdfIndex:
            return pdfIndexTextCache[key]
        case .file:
            return fileTextCache[key]
        }
    }

    private static func store(_ value: String, for key: String, cache: TextCache) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        switch cache {
        case .pdf:
            pdfTextCache[key] = value
        case .pdfIndex:
            pdfIndexTextCache[key] = value
        case .file:
            fileTextCache[key] = value
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
