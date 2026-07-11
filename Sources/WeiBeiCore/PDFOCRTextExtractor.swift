import AppKit
import Foundation
import PDFKit
import Vision

public struct PDFOCRLine: Equatable {
    public var text: String
    public var boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

public struct PDFOCRPage: Equatable {
    public var pageIndex: Int
    public var lines: [PDFOCRLine]

    public init(pageIndex: Int, lines: [PDFOCRLine]) {
        self.pageIndex = pageIndex
        self.lines = lines
    }

    public var text: String {
        lines.map(\.text).joined(separator: "\n")
    }
}

public enum PDFOCRPageOutcome: Equatable {
    case text(PDFOCRPage)
    case empty(pageIndex: Int)
    case failed(pageIndex: Int)
}

public enum PDFOCRTextExtractor {
    public static func text(from document: PDFDocument, maxPages: Int = 12) -> String? {
        let text = pages(from: document, maxPages: maxPages)
            .map { "第 \($0.pageIndex + 1) 页（OCR）\n\($0.text)" }
            .joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    public static func pages(from document: PDFDocument, maxPages: Int = 12) -> [PDFOCRPage] {
        let pageLimit = min(max(document.pageCount, 0), max(maxPages, 0))
        guard pageLimit > 0 else { return [] }

        return pages(from: document, pageIndexes: Array(0..<pageLimit))
    }

    public static func pages(from document: PDFDocument, pageIndexes: [Int]) -> [PDFOCRPage] {
        let pageCount = max(document.pageCount, 0)
        let indexes = Array(Set(pageIndexes))
            .filter { $0 >= 0 && $0 < pageCount }
            .sorted()

        return indexes.compactMap { index in
            guard case let .text(page) = pageOutcome(from: document, pageIndex: index) else {
                return nil
            }
            return page
        }
    }

    public static func pageOutcome(from document: PDFDocument, pageIndex: Int) -> PDFOCRPageOutcome {
        guard pageIndex >= 0,
              pageIndex < document.pageCount,
              let page = document.page(at: pageIndex),
              let image = cgImage(for: page),
              let lines = recognizeLines(in: image) else {
            return .failed(pageIndex: pageIndex)
        }
        guard !lines.isEmpty else { return .empty(pageIndex: pageIndex) }
        return .text(PDFOCRPage(pageIndex: pageIndex, lines: lines))
    }

    private static func cgImage(for page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2.0, 1600.0 / max(bounds.width, bounds.height))
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        var rect = CGRect(origin: .zero, size: size)
        return page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func recognizeLines(in image: CGImage) -> [PDFOCRLine]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        }

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }

        return (request.results ?? [])
            .sorted { lhs, rhs in
                let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                return yDelta > 0.02
                    ? lhs.boundingBox.midY > rhs.boundingBox.midY
                    : lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { observation -> PDFOCRLine? in
                let text = observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty, !observation.boundingBox.isEmpty else { return nil }
                return PDFOCRLine(text: text, boundingBox: observation.boundingBox)
            }
    }
}
