import AppKit
import Foundation
import PDFKit

/// Keeps PDF open/click on the main thread cheap.
/// Full-document `page.string` and PDFKit's tagged accessibility tree
/// freeze the UI on multi-page papers.
enum PDFReaderOpenSafety {
    static func disableAccessibilityTree(on view: PDFView) {
        view.setAccessibilityElement(false)
        view.setAccessibilityRole(.none)
        view.setAccessibilityChildren(nil)
        view.documentView?.setAccessibilityElement(false)
        view.documentView?.setAccessibilityChildren(nil)
    }

    static func pageHasNativeText(_ page: PDFPage) -> Bool {
        page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    static func nativeTextPageIndexes(in document: PDFDocument) -> Set<Int> {
        Set((0..<max(document.pageCount, 0)).compactMap { index in
            guard let page = document.page(at: index), pageHasNativeText(page) else {
                return nil
            }
            return index
        })
    }

    static func ocrCandidatePageIndexes(
        in document: PDFDocument,
        maxPages: Int = 12
    ) -> [Int] {
        let pageLimit = min(max(document.pageCount, 0), max(maxPages, 0))
        guard pageLimit > 0 else { return [] }
        return (0..<pageLimit).filter { index in
            guard let page = document.page(at: index) else { return false }
            return !pageHasNativeText(page)
        }
    }
}
