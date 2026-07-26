import AppKit
import PDFKit
import SwiftUI
import WebKit
import WeiBeiCore

struct WebReaderContentRailSection: Hashable {
    var id: String
    var position: CGFloat
    var level: Int
    var title: String
    var excerpt: String
    var metadata: String
}

struct WebReaderContentRailTarget: Equatable {
    var id: String
    var requestID = UUID()
}

enum WebReaderContentRailEventReason: String {
    case initial
    case resize
    case mutation
    case scroll
    case jump
    case programmatic
    case unknown
}

struct WebReaderContentRailActiveChange {
    var id: String?
    var reason: WebReaderContentRailEventReason
}

struct PDFContentRailPreview {
    var image: NSImage
    var title: String
    var excerpt: String
}

final class PDFContentRailPreviewBox: NSObject {
    let preview: PDFContentRailPreview

    init(_ preview: PDFContentRailPreview) {
        self.preview = preview
    }
}

final class PDFContentRailPreviewLoader {
    static let shared = PDFContentRailPreviewLoader()

    private let queue = DispatchQueue(label: "WeiBei.PDFContentRailPreview", qos: .userInitiated)
    private let documentCache = NSCache<NSString, PDFDocument>()
    private let previewCache = NSCache<NSString, PDFContentRailPreviewBox>()

    private init() {
        documentCache.countLimit = 3
        previewCache.countLimit = 80
    }

    func load(url: URL, pageIndex: Int, completion: @escaping (PDFContentRailPreview?) -> Void) {
        let documentKey = cacheKey(for: url)
        let previewKey = "\(documentKey)#page=\(pageIndex)" as NSString
        if let cached = previewCache.object(forKey: previewKey) {
            DispatchQueue.main.async {
                completion(cached.preview)
            }
            return
        }

        queue.async { [documentCache, previewCache] in
            let key = documentKey as NSString
            let document: PDFDocument
            if let cached = documentCache.object(forKey: key) {
                document = cached
            } else if let loaded = PDFDocument(url: url) {
                document = loaded
                documentCache.setObject(loaded, forKey: key)
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            guard let page = document.page(at: pageIndex) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            let image = page.thumbnail(of: NSSize(width: 180, height: 240), for: .mediaBox)
            let lines = (page.string ?? "")
                .split(whereSeparator: { $0.isNewline })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let title = lines.first.map { String($0.prefix(52)) } ?? ""
            let bodyLines = lines.count > 1 ? lines.dropFirst() : lines[...]
            let excerpt = String(bodyLines.joined(separator: " ").prefix(180))
            let preview = PDFContentRailPreview(image: image, title: title, excerpt: excerpt)
            previewCache.setObject(PDFContentRailPreviewBox(preview), forKey: previewKey)
            DispatchQueue.main.async {
                completion(preview)
            }
        }
    }

    private func cacheKey(for url: URL) -> String {
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)#\(modificationDate)"
    }
}

enum PDFBrowseMode: String, CaseIterable, Identifiable {
    case scroll
    case page

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .scroll:
            return language.text("滚动", "Scroll")
        case .page:
            return language.text("翻页", "Page")
        }
    }

    var systemImage: String {
        switch self {
        case .scroll: "arrow.up.and.down"
        case .page: "rectangle.portrait"
        }
    }

    var toggled: PDFBrowseMode {
        switch self {
        case .scroll: .page
        case .page: .scroll
        }
    }

    func help(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .scroll:
            return language.text("连续滚动浏览 PDF", "continuous PDF scrolling")
        case .page:
            return language.text("单页翻页浏览 PDF", "single-page PDF browsing")
        }
    }
}

