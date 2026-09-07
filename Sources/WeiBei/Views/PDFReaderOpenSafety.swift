import AppKit
import Foundation
import PDFKit
import WeiBeiCore

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
    ) -> SelectionPopoverAnchor? {
        let lines = selection.selectionsByLine().flatMap { line in
            line.pages.compactMap { page -> CGRect? in
                let rect = view.convert(line.bounds(for: page), from: page)
                return rect.isEmpty ? nil : rect
            }
        }
        guard let first = lines.first, let last = lines.last,
              let start = SelectionAnchorContentPoint.fromLocalPoint(
                CGPoint(x: first.minX, y: view.isFlipped ? first.minY : first.maxY), in: view),
              let end = SelectionAnchorContentPoint.fromLocalPoint(
                CGPoint(x: last.maxX, y: view.isFlipped ? last.maxY : last.minY), in: view) else { return nil }
        guard let pointer = fallbackLocalPoint.flatMap({ SelectionAnchorContentPoint.fromLocalPoint($0, in: view) }) else { return end }
        let distanceToStart = hypot(pointer.x - start.x, pointer.y - start.y)
        let distanceToEnd = hypot(pointer.x - end.x, pointer.y - end.y)
        let above = distanceToStart < distanceToEnd
        return SelectionPopoverAnchor(x: pointer.x, y: above ? start.y : end.y, prefersAbove: above)
    }
}
