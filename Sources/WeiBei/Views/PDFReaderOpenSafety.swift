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

    static func selectionText(in view: PDFView) -> String {
        view.currentSelection?.string ?? ""
    }

    static func pageIndex(for selection: PDFSelection, in view: PDFView) -> Int? {
        guard let page = selection.pages.first, let document = view.document else { return nil }
        let index = document.index(for: page)
        return index == NSNotFound ? nil : index
    }

    static func selectionAnchor(
        for selection: PDFSelection,
        in view: PDFView,
        fallbackLocalPoint: CGPoint?
    ) -> CGPoint? {
        if let page = selection.pages.first {
            let bounds = selection.bounds(for: page)
            if !bounds.isEmpty {
                let localRect = view.convert(bounds, from: page)
                if !localRect.isEmpty {
                    let localPoint = CGPoint(x: localRect.midX, y: localRect.minY)
                    if let anchor = SelectionAnchorContentPoint.fromLocalPoint(localPoint, in: view) {
                        return anchor
                    }
                }
            }
        }
        if let fallbackLocalPoint,
           let anchor = SelectionAnchorContentPoint.fromLocalPoint(fallbackLocalPoint, in: view) {
            return anchor
        }
        return SelectionAnchorContentPoint.fromLocalPoint(
            CGPoint(x: view.bounds.midX, y: view.bounds.midY),
            in: view
        )
    }
}
