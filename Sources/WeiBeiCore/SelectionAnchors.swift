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

    public init(pageIndex: Int, lineRects: [SelectionRect]) {
        self.pageIndex = pageIndex
        self.lineRects = lineRects
    }

    /// 两个锚是否指向同一处文本(同页且行矩形有显著重叠)。
    public func overlaps(_ other: PDFSelectionAnchor, tolerance: Double = 2) -> Bool {
        guard pageIndex == other.pageIndex else { return false }
        let mine = lineRects.map(\.cgRect)
        let theirs = other.lineRects.map(\.cgRect)
        return mine.contains { a in
            theirs.contains { b in
                abs(a.minY - b.minY) <= tolerance + max(a.height, b.height) * 0.5
                    && a.minX < b.maxX + tolerance
                    && b.minX < a.maxX + tolerance
            }
        }
    }
}

/// 选区在原文档中的位置锚。字段全部可选:旧数据解码后为 nil,
/// 匹配回访时锚点优先、文字匹配兜底。网页/Markdown 锚点后续按需扩展。
public struct SelectionDocumentAnchor: Codable, Hashable, Sendable {
    public var pdf: PDFSelectionAnchor?

    public init(pdf: PDFSelectionAnchor? = nil) {
        self.pdf = pdf
    }

    public func matches(_ other: SelectionDocumentAnchor?) -> Bool {
        guard let other, let pdf, let otherPDF = other.pdf else { return false }
        return pdf.overlaps(otherPDF)
    }
}

/// 选区"记"的留痕记录:不建线程、不挂消息,只记"这段原文被记过、记了什么"。
/// 供原文标记渲染(第三/四刀)与回访使用。
public struct SelectionRemarkRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var selectionText: String
    /// 用户附的一句话;纯摘录时为空字符串。
    public var remarkText: String
    public var source: SelectionSource
    public var ownerTitle: String
    public var itemID: String?
    public var documentAnchor: SelectionDocumentAnchor?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        selectionText: String,
        remarkText: String,
        source: SelectionSource,
        ownerTitle: String,
        itemID: String? = nil,
        documentAnchor: SelectionDocumentAnchor? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.selectionText = selectionText
        self.remarkText = remarkText
        self.source = source
        self.ownerTitle = ownerTitle
        self.itemID = itemID
        self.documentAnchor = documentAnchor
        self.createdAt = createdAt
    }
}
