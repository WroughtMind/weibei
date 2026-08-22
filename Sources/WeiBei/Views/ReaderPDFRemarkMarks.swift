import PDFKit
import SwiftUI
import WeiBeiCore

/// 单条记过标记的命中信息:朱砂圆点热区 + hover 时要高亮的整句行矩形。
struct PDFRemarkMarkHit {
    var recordID: String
    var pageIndex: Int
    var hitBounds: CGRect
    var highlightRects: [CGRect]
}

// 记过原文标记渲染(用户定稿 2026-08-22 验收修订):
// 圆点(非竖线)、放在**整行的最右端**(非句子文字末端)、同行多条堆叠从右往左排。
// hover 圆点时整句高亮;点击回访续记浮层。问过下划线沿用 ReaderView 内既有实现。
extension PDFReaderRepresentable.Coordinator {
    static let remarkMarkMarker = "weibei-selection-remark"
    static let remarkMarkHoverMarker = "weibei-selection-remark-hover"

    private var remarkCinnabar: NSColor {
        NSColor(calibratedRed: 0.56, green: 0.16, blue: 0.12, alpha: 1.0)
    }

    private static let dotDiameter: CGFloat = 8
    private static let dotSpacing: CGFloat = 4

    /// 渲染记过朱砂圆点。只有带 PDF 锚点的记录能画;无锚旧数据不渲染。
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

        struct PendingDot {
            var recordID: String
            var pageIndex: Int
            var lineMidY: CGFloat
            var lineRight: CGFloat
            var textEndX: CGFloat
            var highlightRects: [CGRect]
        }
        var pendings: [PendingDot] = []
        for mark in marks {
            guard let pdf = mark.anchor?.pdf,
                  pdf.pageIndex != NSNotFound,
                  let page = document.page(at: pdf.pageIndex) else { continue }
            let rects = pdf.lineRects.map(\.cgRect).filter { $0.width > 1 && $0.height > 0.5 }
            guard let lastLine = rects.last else { continue }
            pendings.append(
                PendingDot(
                    recordID: mark.id,
                    pageIndex: pdf.pageIndex,
                    lineMidY: lastLine.midY,
                    lineRight: Self.pageLineRightEdge(
                        containing: lastLine,
                        in: page,
                        document: document
                    ),
                    textEndX: lastLine.maxX,
                    highlightRects: rects
                )
            )
        }

        // 同一行(pageIndex + midY 相近)堆叠:句尾越靠右的点越贴行缘。
        var grouped: [[PendingDot]] = []
        for dot in pendings.sorted(by: { $0.pageIndex < $1.pageIndex || $0.lineMidY < $1.lineMidY }) {
            if var lastGroup = grouped.last,
               lastGroup.first!.pageIndex == dot.pageIndex,
               abs(lastGroup.first!.lineMidY - dot.lineMidY) < 4 {
                lastGroup.append(dot)
                grouped[grouped.count - 1] = lastGroup
            } else {
                grouped.append([dot])
            }
        }

        let cinnabar = remarkCinnabar
        // cropBox 才是真正显示出来的页面范围,圆点必须收在它里面。
        let pageRightLimit = { (page: PDFPage) -> CGFloat in
            page.bounds(for: .cropBox).maxX - Self.dotDiameter - 2
        }
        // baseLeft = 首个点允许的最靠右"左缘"。
        for group in grouped {
            guard let page = document.page(at: group[0].pageIndex) else { continue }
            let ordered = group.sorted(by: { $0.textEndX > $1.textEndX })
            // 点贴在整行右缘外侧留一点空隙;行写满到页缘时向内收,仍压不住可见性。
            let baseLeft = min(ordered[0].lineRight + 4, pageRightLimit(page))
            for (slot, dot) in ordered.enumerated() {
                let dotX = baseLeft - CGFloat(slot) * (Self.dotDiameter + Self.dotSpacing)
                let dotRect = CGRect(
                    x: dotX,
                    y: dot.lineMidY - Self.dotDiameter / 2,
                    width: Self.dotDiameter,
                    height: Self.dotDiameter
                )
                let annotation = PDFAnnotation(bounds: dotRect, forType: .circle, withProperties: nil)
                annotation.color = cinnabar
                annotation.setValue(cinnabar, forAnnotationKey: .interiorColor)
                let border = PDFBorder()
                border.lineWidth = 1.2
                annotation.border = border
                annotation.userName = Self.remarkMarkMarker
                page.addAnnotation(annotation)
                remarkHits.append(
                    PDFRemarkMarkHit(
                        recordID: dot.recordID,
                        pageIndex: dot.pageIndex,
                        hitBounds: dotRect.insetBy(dx: -6, dy: -6),
                        highlightRects: dot.highlightRects
                    )
                )
            }
        }
    }

    /// 整页文本按行分解,取"句子末行所在整行"的右缘(同列判定:行起点最接近)。
    /// 拿不到行布局时退回句子自身末行右缘。
    static func pageLineRightEdge(containing line: CGRect, in page: PDFPage, document: PDFDocument) -> CGFloat {
        guard let full = page.selection(for: page.bounds(for: .mediaBox)) else {
            return line.maxX
        }
        var best: CGRect?
        for pageLine in full.selectionsByLine() {
            let bounds = pageLine.bounds(for: page)
            guard line.midY >= bounds.minY - 1, line.midY <= bounds.maxY + 1 else { continue }
            if best == nil
                || abs(bounds.minX - line.minX) < abs(best!.minX - line.minX) {
                best = bounds
            }
        }
        return best?.maxX ?? line.maxX
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
