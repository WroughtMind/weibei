import PDFKit
import SwiftUI
import WeiBeiCore

/// 单条记过标记的命中信息:朱砂短棒热区 + hover 时要高亮的整句行矩形。
struct PDFRemarkMarkHit {
    var recordID: String
    var pageIndex: Int
    var hitBounds: CGRect
    var highlightRects: [CGRect]
}

// 记过原文标记渲染:句末右侧全饱和朱砂短棒(用户定稿 2026-08-22:
// 放在"整个句子的最右边"、要显眼;hover 时整句高亮;点击回访续记浮层)。
// 问过下划线沿用 ReaderView 内既有实现,这里只负责"记"。
extension PDFReaderRepresentable.Coordinator {
    static let remarkMarkMarker = "weibei-selection-remark"
    static let remarkMarkHoverMarker = "weibei-selection-remark-hover"

    private var remarkCinnabar: NSColor {
        NSColor(calibratedRed: 0.56, green: 0.16, blue: 0.12, alpha: 1.0)
    }

    /// 渲染记过朱砂短棒。只有带 PDF 锚点的记录能画;无锚旧数据沿用文字匹配链路(第三刀不渲染)。
    func applyRemarkMarks(
        _ marks: [(id: String, anchor: SelectionDocumentAnchor?, text: String)],
        in view: PDFView
    ) {
        guard let document = view.document else { return }
        let signature = marks.map { "\($0.id)|\($0.anchor?.pdf != nil)" }.joined(separator: ",")
        guard signature != lastAppliedRemarkMarkSignature else { return }
        lastAppliedRemarkMarkSignature = signature
        remarkHits = []
        hoveredRemarkRecordID = nil
        clearRemarkAnnotations(in: document, includingHover: true)

        for mark in marks {
            guard let pdf = mark.anchor?.pdf,
                  pdf.pageIndex != NSNotFound,
                  let page = document.page(at: pdf.pageIndex) else { continue }
            let rects = pdf.lineRects.map(\.cgRect).filter { $0.width > 1 && $0.height > 0.5 }
            guard let lastLine = rects.last else { continue }

            // 棒贴在整句最右端(所有行最右沿),竖在末行行高中点。
            let sentenceRight = rects.map(\.maxX).max() ?? lastLine.maxX
            let pageRight = page.bounds(for: .mediaBox).maxX
            let barX = min(sentenceRight + 3, pageRight - 6)
            let barHeight = min(lastLine.height * 0.72, 14)
            let barRect = CGRect(x: barX, y: lastLine.midY - barHeight / 2, width: 2.6, height: barHeight)

            let annotation = PDFAnnotation(bounds: barRect, forType: .square, withProperties: nil)
            annotation.color = remarkCinnabar
            annotation.setValue(remarkCinnabar, forAnnotationKey: .interiorColor)
            annotation.userName = Self.remarkMarkMarker
            page.addAnnotation(annotation)

            remarkHits.append(
                PDFRemarkMarkHit(
                    recordID: mark.id,
                    pageIndex: pdf.pageIndex,
                    hitBounds: barRect.insetBy(dx: -6, dy: -6),
                    highlightRects: rects
                )
            )
        }
    }

    func handleRemarkMarkHover(at viewPoint: CGPoint, in view: PDFView) {
        let recordID = remarkHit(at: viewPoint, in: view)?.recordID
        guard recordID != hoveredRemarkRecordID else { return }
        hoveredRemarkRecordID = recordID
        applyRemarkHoverHighlight(in: view)
        // 指针只在命中时接管;无命中时保留问下划线 hover 设置的光标。
        if recordID != nil {
            NSCursor.pointingHand.set()
        }
    }

    @discardableResult
    func handleRemarkMarkClick(at viewPoint: CGPoint, in view: PDFView) -> Bool {
        guard let hit = remarkHit(at: viewPoint, in: view) else { return false }
        guard let document = view.document,
              let page = document.page(at: hit.pageIndex) else {
            onRemarkMarkActivate(hit.recordID, nil)
            return true
        }
        let localRect = view.convert(hit.hitBounds, from: page)
        let anchor = SelectionAnchorContentPoint.fromLocalPoint(
            CGPoint(x: localRect.midX, y: localRect.minY),
            in: view
        )
        onRemarkMarkActivate(hit.recordID, anchor)
        return true
    }

    private func remarkHit(at viewPoint: CGPoint, in view: PDFView) -> PDFRemarkMarkHit? {
        guard let document = view.document,
              let page = view.page(for: viewPoint, nearest: true) else { return nil }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return nil }
        let pagePoint = view.convert(viewPoint, to: page)
        return remarkHits.first {
            $0.pageIndex == pageIndex && $0.hitBounds.contains(pagePoint)
        }
    }

    private func applyRemarkHoverHighlight(in view: PDFView) {
        guard let document = view.document else { return }
        clearRemarkAnnotations(in: document, includingHover: true, bars: false)
        guard let recordID = hoveredRemarkRecordID else { return }
        let fill = NSColor(calibratedRed: 0.56, green: 0.16, blue: 0.12, alpha: 0.14)
        for hit in remarkHits where hit.recordID == recordID {
            guard let page = document.page(at: hit.pageIndex) else { continue }
            for rect in hit.highlightRects {
                let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                annotation.color = fill
                annotation.userName = Self.remarkMarkHoverMarker
                page.addAnnotation(annotation)
            }
        }
    }

    func clearRemarkAnnotations(in document: PDFDocument, includingHover: Bool, bars: Bool = true) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                let name = annotation.userName
                if bars, name == Self.remarkMarkMarker {
                    page.removeAnnotation(annotation)
                } else if includingHover, name == Self.remarkMarkHoverMarker {
                    page.removeAnnotation(annotation)
                }
            }
        }
    }
}
