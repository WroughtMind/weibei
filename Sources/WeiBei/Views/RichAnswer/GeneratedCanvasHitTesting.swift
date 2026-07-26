import CoreGraphics
import WeiBeiCore

/**
 * 提供与 SwiftUI 无关的生成画布命中测试。
 */
enum GeneratedCanvasHitTesting {
    /**
     * 返回首个命中指定位置的图形实例。
     */
    static func firstInstance(at location: CGPoint, in instances: [GeneratedCanvasMarkInstance], padding: CGFloat) -> GeneratedCanvasMarkInstance? {
        instances.first { $0.rect.insetBy(dx: -padding, dy: -padding).contains(location) }
    }

    /**
     * 返回点击半径内距离最近的数据行 ID。
     */
    static func nearestRowID(at location: CGPoint, rows: [RichAnswerUIDataRow], projection: GeneratedCanvasProjection, radius: CGFloat) -> String? {
        rows.min {
            distance(location, projection.point(x: $0.x, y: $0.y)) < distance(location, projection.point(x: $1.x, y: $1.y))
        }.flatMap { row in
            distance(location, projection.point(x: row.x, y: row.y)) <= radius ? row.id : nil
        }
    }
}
