import AppKit
import Foundation
import PDFKit
import Vision

public enum PDFOCRTextExtractor {
    public static func text(from document: PDFDocument, maxPages: Int = 12) -> String? {
        let pageLimit = min(max(document.pageCount, 0), max(maxPages, 0))
        guard pageLimit > 0 else { return nil }

        let pages = (0..<pageLimit).compactMap { index -> String? in
            guard let page = document.page(at: index),
                  let image = cgImage(for: page),
                  let pageText = recognizeText(in: image),
                  !pageText.isEmpty else { return nil }
            return "第 \(index + 1) 页（OCR）\n\(pageText)"
        }
        let text = pages.joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    private static func cgImage(for page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2.0, 1600.0 / max(bounds.width, bounds.height))
        let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
        var rect = CGRect(origin: .zero, size: size)
        return page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func recognizeText(in image: CGImage) -> String? {
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

        let lines = (request.results ?? [])
            .sorted { lhs, rhs in
                let yDelta = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
                return yDelta > 0.02
                    ? lhs.boundingBox.midY > rhs.boundingBox.midY
                    : lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
