import CoreGraphics
import Foundation

/// Codable-friendly CGRect value type(AppKit 类型不入 Core 模块)。
public struct SelectionRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// PDF 选区位置锚:页码 + 按行的矩形(页面坐标系,PDF 点,稳定不随缩放变化)。
public struct PDFSelectionAnchor: Codable, Hashable, Sendable {
    public var pageIndex: Int
    public var lineRects: [SelectionRect]
    public var additionalPageRects: [Int: [SelectionRect]]?

    public init(pageIndex: Int, lineRects: [SelectionRect], additionalPageRects: [Int: [SelectionRect]]? = nil) {
        self.pageIndex = pageIndex
        self.lineRects = lineRects
        self.additionalPageRects = additionalPageRects
    }

    public var rectsByPage: [Int: [SelectionRect]] {
        var pages = additionalPageRects ?? [:]
        pages[pageIndex] = lineRects
        return pages
    }

    /// 两个锚是否指向同一处文本(同页且行矩形有显著重叠)。
    public func overlaps(_ other: PDFSelectionAnchor, tolerance: Double = 2) -> Bool {
        rectsByPage.contains { pageIndex, rects in
            rects.contains { a in
                (other.rectsByPage[pageIndex] ?? []).contains { b in
                    abs(a.cgRect.minY - b.cgRect.minY) <= tolerance + max(a.height, b.height) * 0.5
                        && a.cgRect.minX < b.cgRect.maxX + tolerance
                        && b.cgRect.minX < a.cgRect.maxX + tolerance
                }
            }
        }
    }
}

/// 选区在原文档中的位置锚。字段全部可选:旧数据解码后为 nil,
/// PDF 保存页面矩形；HTML/Markdown 保存完整文档中的文字位置。
public struct SelectionDocumentAnchor: Codable, Hashable, Sendable {
    public var pdf: PDFSelectionAnchor?
    public var text: SelectionTextAnchor?

    public init(pdf: PDFSelectionAnchor? = nil, text: SelectionTextAnchor? = nil) {
        self.pdf = pdf
        self.text = text
    }

    public func matches(_ other: SelectionDocumentAnchor?) -> Bool {
        if let text, let otherText = other?.text { return text == otherText }
        guard let other, let pdf, let otherPDF = other.pdf else { return false }
        return pdf.overlaps(otherPDF)
    }
}

/// Offsets in the document's non-whitespace text identify repeated passages independently.
public struct SelectionTextAnchor: Codable, Hashable, Sendable {
    public var startOffset: Int
    public var endOffset: Int

    public init(startOffset: Int, endOffset: Int) {
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

/// 选区"记"的留痕记录:不建线程、不挂消息,只记"这段原文被记过、记了什么"。
/// 供原文标记渲染(第三/四刀)与回访使用。
public struct SelectionRemarkRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var selectionText: String
    /// 用户附的一句话;纯摘录时为空字符串。
    public var remarkText: String
    public var courseID: UUID?
    public var source: SelectionSource
    public var ownerTitle: String
    public var itemID: String?
    public var documentAnchor: SelectionDocumentAnchor?
    public var createdAt: Date

    public var excerptSourceKey: String { itemID ?? ownerTitle }

    public static func inDocumentOrder(_ left: Self, _ right: Self) -> Bool {
        func position(_ record: Self) -> (Int, Int, Double, Double) {
            if let pdf = record.documentAnchor?.pdf {
                return (0, pdf.pageIndex, -(pdf.lineRects.first?.y ?? 0), pdf.lineRects.first?.x ?? 0)
            }
            if let text = record.documentAnchor?.text { return (1, 0, Double(text.startOffset), 0) }
            return (2, 0, 0, 0)
        }
        if position(left) != position(right) { return position(left) < position(right) }
        if left.createdAt != right.createdAt { return left.createdAt < right.createdAt }
        return left.id.uuidString < right.id.uuidString
    }

    public init(
        id: UUID = UUID(),
        selectionText: String,
        remarkText: String,
        courseID: UUID? = nil,
        source: SelectionSource,
        ownerTitle: String,
        itemID: String? = nil,
        documentAnchor: SelectionDocumentAnchor? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.selectionText = selectionText
        self.remarkText = remarkText
        self.courseID = courseID
        self.source = source
        self.ownerTitle = ownerTitle
        self.itemID = itemID
        self.documentAnchor = documentAnchor
        self.createdAt = createdAt
    }
}
