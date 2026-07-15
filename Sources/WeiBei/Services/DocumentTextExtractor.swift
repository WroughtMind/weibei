import AppKit
import Foundation
import PDFKit
import WeiBeiCore

enum DocumentTextExtractor {
    private enum TextCache {
        case pdf
        case file
    }

    private static let cacheLock = NSLock()
    private static let maximumPDFCacheEntryBytes = 4 * 1_024 * 1_024
    private static let maximumPDFCacheBytes = 12 * 1_024 * 1_024
    private static let maximumFileCacheEntryBytes = 2 * 1_024 * 1_024
    private static let maximumFileCacheBytes = 8 * 1_024 * 1_024
    private static let maximumActiveFileBytes = 4 * 1_024 * 1_024
    private static let maximumActivePDFPages = 12
    private static let maximumActivePDFCharacters = 64_000
    private static let maximumActivePDFTextSeconds: TimeInterval = 2
    private static var pdfTextCache: [String: String] = [:]
    private static var fileTextCache: [String: String] = [:]
    private static var pdfTextCacheOrder: [String] = []
    private static var fileTextCacheOrder: [String] = []

    static func text(for item: StudyItem) -> String? {
        guard let url = item.url else { return nil }
        switch item.kind {
        case .pdf:
            return pdfText(url: url)
        case .html:
            return cachedFileText(url: url, load: htmlText)
        case .markdown, .text:
            return cachedFileText(url: url) { fileURL in
                prefixData(from: fileURL).map { String(decoding: $0, as: UTF8.self) }
            }
        }
    }

    static func cachedText(for item: StudyItem) -> String? {
        guard let url = item.url else { return nil }
        let cache: TextCache = item.kind == .pdf ? .pdf : .file
        return cachedValue(for: fileCacheKey(for: url), cache: cache)
    }

    static func indexText(
        for item: StudyItem,
        maximumCharacters: Int = 24_000,
        query: String = ""
    ) -> String? {
        guard let text = text(for: item), !text.isEmpty else { return nil }
        return relevantText(
            text,
            query: query,
            maximumCharacters: max(maximumCharacters, 1)
        )
    }

    private static func pdfText(url: URL) -> String? {
        let cacheKey = fileCacheKey(for: url)
        if let cached = cachedValue(for: cacheKey, cache: .pdf) {
            return cached
        }
        guard let document = PDFDocument(url: url) else { return nil }
        var nativePages: [String] = []
        var nativeCharacterCount = 0
        let pageLimit = min(max(document.pageCount, 0), maximumActivePDFPages)
        let nativeTextByPage = BoundedPDFTextExtractor.pages(
            from: url,
            pageIndexes: Array(0..<pageLimit),
            maximumCharactersPerPage: maximumActivePDFCharacters,
            timeout: maximumActivePDFTextSeconds
        ) ?? [:]
        for pageIndex in 0..<pageLimit {
            guard let page = nativeTextByPage[pageIndex] else { continue }
            let text = page.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let pageText = "第 \(pageIndex + 1) 页\n\(text)"
            nativePages.append(pageText)
            nativeCharacterCount += pageText.count
            if nativeCharacterCount >= maximumActivePDFCharacters { break }
        }
        let nativeText = String(nativePages.joined(separator: "\n\n").prefix(maximumActivePDFCharacters))
        let text = nativeText.isEmpty
            ? PDFOCRTextExtractor.text(from: document, maxPages: 12)
            : nativeText
        if let text, !text.isEmpty {
            store(text, for: cacheKey, cache: .pdf)
            return text
        }
        return nil
    }

    private static func htmlText(url: URL) -> String? {
        guard let data = prefixData(from: url) else { return nil }
        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func prefixData(from url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maximumActiveFileBytes)
    }

    private static func relevantText(
        _ text: String,
        query: String,
        maximumCharacters: Int
    ) -> String {
        let terms = Array(searchTerms(in: query).prefix(24))
        guard !terms.isEmpty else { return String(text.prefix(maximumCharacters)) }
        let chunks = chunked(text, maximumCharacters: 2_000)
        var ranked: [(index: Int, chunk: String, score: Int)] = []
        for (index, chunk) in chunks.enumerated() {
            let lower = chunk.lowercased()
            var score = 0
            for term in terms {
                score += min(lower.components(separatedBy: term).count - 1, 12)
            }
            if score > 0 {
                ranked.append((index: index, chunk: chunk, score: score))
            }
        }
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index
        }
        guard !ranked.isEmpty else { return String(text.prefix(maximumCharacters)) }
        let selected = ranked.prefix(12).sorted { lhs, rhs in
            lhs.index < rhs.index
        }
        let joined = selected.map { $0.chunk }.joined(separator: "\n\n")
        return String(joined.prefix(maximumCharacters))
    }

    private static func chunked(_ text: String, maximumCharacters: Int) -> [String] {
        guard text.count > maximumCharacters else { return [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maximumCharacters, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }

    private static func searchTerms(in query: String) -> [String] {
        let lower = query.lowercased()
        var terms = lower
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted)
            .filter { $0.count >= 2 }
        let characters = Array(lower)
        if characters.count >= 2 {
            for index in 0..<(characters.count - 1) {
                let pair = String(characters[index...index + 1])
                if pair.unicodeScalars.allSatisfy({ (0x4E00...0x9FFF).contains(Int($0.value)) }) {
                    terms.append(pair)
                }
            }
        }
        var seen: Set<String> = []
        return terms.filter { seen.insert($0).inserted }
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
        guard let text = load(url), !text.isEmpty else { return nil }
        store(text, for: cacheKey, cache: .file)
        return text
    }

    private static func cachedValue(for key: String, cache: TextCache) -> String? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        switch cache {
        case .pdf:
            guard let value = pdfTextCache[key] else { return nil }
            touch(key, in: &pdfTextCacheOrder)
            return value
        case .file:
            guard let value = fileTextCache[key] else { return nil }
            touch(key, in: &fileTextCacheOrder)
            return value
        }
    }

    private static func store(_ value: String, for key: String, cache: TextCache) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let valueBytes = value.utf8.count
        switch cache {
        case .pdf:
            guard valueBytes <= maximumPDFCacheEntryBytes else { return }
            pdfTextCache[key] = value
            touch(key, in: &pdfTextCacheOrder)
            trim(
                &pdfTextCache,
                order: &pdfTextCacheOrder,
                countLimit: 4,
                byteLimit: maximumPDFCacheBytes
            )
        case .file:
            guard valueBytes <= maximumFileCacheEntryBytes else { return }
            fileTextCache[key] = value
            touch(key, in: &fileTextCacheOrder)
            trim(
                &fileTextCache,
                order: &fileTextCacheOrder,
                countLimit: 8,
                byteLimit: maximumFileCacheBytes
            )
        }
    }

    private static func touch(_ key: String, in order: inout [String]) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private static func trim(
        _ values: inout [String: String],
        order: inout [String],
        countLimit: Int,
        byteLimit: Int
    ) {
        var totalBytes = values.values.reduce(0) { $0 + $1.utf8.count }
        while order.count > countLimit || totalBytes > byteLimit {
            guard !order.isEmpty else { break }
            let key = order.removeFirst()
            totalBytes -= values.removeValue(forKey: key)?.utf8.count ?? 0
        }
    }
}
