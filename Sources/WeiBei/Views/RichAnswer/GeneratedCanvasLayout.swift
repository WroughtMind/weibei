import CoreGraphics
import WeiBeiCore

/**
 * 汇集生成画布的纯值尺寸与标签约束计算。
 */
enum GeneratedCanvasLayout {
    /**
     * 返回画布语义尺寸对应的显示高度。
     */
    static func height(for size: RichAnswerUISize) -> CGFloat {
        switch size {
        case .compact: return 168
        case .regular: return 232
        case .large: return 306
        }
    }

    /**
     * 将标签矩形约束在允许区域内。
     */
    static func constrain(_ frame: CGRect, to allowedRect: CGRect) -> CGRect {
        var constrained = frame
        if constrained.minX < allowedRect.minX { constrained.origin.x += allowedRect.minX - constrained.minX }
        if constrained.maxX > allowedRect.maxX { constrained.origin.x -= constrained.maxX - allowedRect.maxX }
        if constrained.minY < allowedRect.minY { constrained.origin.y += allowedRect.minY - constrained.minY }
        if constrained.maxY > allowedRect.maxY { constrained.origin.y -= constrained.maxY - allowedRect.maxY }
        return constrained
    }

    /**
     * 返回两个矩形相交区域的面积。
     */
    static func intersectionArea(_ first: CGRect, _ second: CGRect) -> CGFloat {
        let intersection = first.intersection(second)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
