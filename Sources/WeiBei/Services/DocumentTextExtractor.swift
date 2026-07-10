import AppKit
import Foundation
import PDFKit
import WeiBeiCore

enum DocumentTextExtractor {
    private static var pdfTextCache: [String: String] = [:]
    private static var fileTextCache: [String: String] = [:]
    private static let cacheLock = NSLock()

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
        if let cached = locked({ pdfTextCache[cacheKey] }) {
            return cached
        }

        guard let document = PDFDocument(url: url) else { return nil }
        let textLayerText = pagedText(from: document)
        let text = textLayerText.isEmpty ? PDFOCRTextExtractor.text(from: document) : textLayerText
        if let text, !text.isEmpty {
            locked { pdfTextCache[cacheKey] = text }
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
        if let cached = locked({ fileTextCache[cacheKey] }) {
            return cached
        }
        guard let text = load(url) else { return nil }
        if !text.isEmpty {
            locked { fileTextCache[cacheKey] = text }
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

    private static func locked<T>(_ operation: () -> T) -> T {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return operation()
    }
}

struct AgentSourceLoadRequest: Sendable {
    var item: StudyItem
    var title: String
    var fallbackText: String
}

actor AgentSourceTextLoader {
    static let shared = AgentSourceTextLoader()

    func sources(for requests: [AgentSourceLoadRequest]) -> [StudyAgentSource] {
        requests.compactMap { request in
            let text = DocumentTextExtractor.text(for: request.item) ?? request.fallbackText
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return StudyAgentSource(id: request.item.id, title: request.title, kind: request.item.kind, text: text)
        }
    }
}
