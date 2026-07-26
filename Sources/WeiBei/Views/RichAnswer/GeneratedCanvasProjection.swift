import CoreGraphics

/**
 * 封装生成画布的归一化坐标投影，确保绘制与命中测试使用同一坐标系。
 */
struct GeneratedCanvasProjection {
    let rect: CGRect

    /**
     * 根据画布可用尺寸创建带固定绘图边距的投影。
     */
    init(canvasSize: CGSize) {
        rect = CGRect(x: 32, y: 18, width: max(20, canvasSize.width - 52), height: max(20, canvasSize.height - 42))
    }

    /**
     * 使用已有绘图区创建投影。
     */
    init(rect: CGRect) {
        self.rect = rect
    }

    /**
     * 将左下原点的归一化数据坐标映射到 SwiftUI 画布坐标。
     */
    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.maxY - rect.height * y)
    }
}
