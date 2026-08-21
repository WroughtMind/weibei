import AppKit
import Foundation
import PDFKit

/// Content-rail hover preview for PDF pages: thumbnail + first text lines, rendered
/// off the main thread through a latest-first serial queue. Split out of
/// ReaderView.swift so the reader view stays within its frozen size budget.
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

    /// Serial render pipeline — PDFKit must never render the same document concurrently.
    /// LatestFirstSerialQueue keeps the in-flight page and cancels queued ones, so the
    /// next rendered page is always the most recently hovered one.
    private let queue: OperationQueue
    private let documentCache = NSCache<NSString, PDFDocument>()
    private let previewCache = NSCache<NSString, PDFContentRailPreviewBox>()
    /// Cache cost is thumbnail pixel bytes (180x240x4 = 172KB per page): ~48MB ceiling
    /// keeps a long fast-sweep session from growing without bound.
    private static let previewCacheCostLimit = 48 * 1024 * 1024

    private init() {
        let renderQueue = OperationQueue()
        renderQueue.name = "WeiBei.PDFContentRailPreview"
        renderQueue.maxConcurrentOperationCount = 1
        renderQueue.qualityOfService = .userInitiated
        queue = renderQueue
        documentCache.countLimit = 3
        previewCache.countLimit = 80
        previewCache.totalCostLimit = Self.previewCacheCostLimit
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

        let operation = PDFPreviewRenderOperation(
            url: url,
            pageIndex: pageIndex,
            documentKey: documentKey as NSString,
            previewKey: previewKey,
            documentCache: documentCache,
            previewCache: previewCache
        ) { preview in
            DispatchQueue.main.async {
                completion(preview)
            }
        }
        LatestFirstSerialQueue.enqueue(operation, on: queue)
    }

    private func cacheKey(for url: URL) -> String {
        let modificationDate = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(url.standardizedFileURL.path)#\(modificationDate)"
    }
}

/// One page render. Runs on the loader's serial queue; cancelled before start it
/// produces nothing at all. A page that finishes after the pointer moved on still
/// fills the cache (the view layer guards the card), it just skips its callback.
private final class PDFPreviewRenderOperation: Operation {
    private let url: URL
    private let pageIndex: Int
    private let documentKey: NSString
    private let previewKey: NSString
    private let documentCache: NSCache<NSString, PDFDocument>
    private let previewCache: NSCache<NSString, PDFContentRailPreviewBox>
    private let completion: (PDFContentRailPreview?) -> Void

    init(
        url: URL,
        pageIndex: Int,
        documentKey: NSString,
        previewKey: NSString,
        documentCache: NSCache<NSString, PDFDocument>,
        previewCache: NSCache<NSString, PDFContentRailPreviewBox>,
        completion: @escaping (PDFContentRailPreview?) -> Void
    ) {
        self.url = url
        self.pageIndex = pageIndex
        self.documentKey = documentKey
        self.previewKey = previewKey
        self.documentCache = documentCache
        self.previewCache = previewCache
        self.completion = completion
        super.init()
    }

    override func main() {
        guard !isCancelled else { return }
        let document: PDFDocument
        if let cached = documentCache.object(forKey: documentKey) {
            document = cached
        } else if let loaded = PDFDocument(url: url) {
            documentCache.setObject(loaded, forKey: documentKey)
            document = loaded
        } else {
            if !isCancelled { completion(nil) }
            return
        }
        guard let page = document.page(at: pageIndex) else {
            if !isCancelled { completion(nil) }
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
        let pixelCost = Int(max(1, image.size.width * image.size.height * 4))
        previewCache.setObject(
            PDFContentRailPreviewBox(preview),
            forKey: previewKey,
            cost: pixelCost
        )
        if !isCancelled { completion(preview) }
    }
}
