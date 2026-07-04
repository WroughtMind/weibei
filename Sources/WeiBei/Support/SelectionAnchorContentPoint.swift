import AppKit
import WeiBeiCore

enum SelectionAnchorContentPoint {
    static func fromLocalPoint(_ point: CGPoint, in view: NSView) -> CGPoint? {
        guard let window = view.window,
              let contentView = window.contentView else {
            return nil
        }
        return fromWindowPoint(view.convert(point, to: nil), in: contentView)
    }

    static func fromWebPoint(x: Double, y: Double, in view: NSView) -> CGPoint? {
        let localY = view.isFlipped ? CGFloat(y) : view.bounds.height - CGFloat(y)
        return fromLocalPoint(CGPoint(x: CGFloat(x), y: localY), in: view)
    }

    static func fromScreenPoint(_ point: CGPoint, in window: NSWindow) -> CGPoint? {
        guard let contentView = window.contentView else { return nil }
        return fromWindowPoint(window.convertPoint(fromScreen: point), in: contentView)
    }

    private static func fromWindowPoint(_ point: CGPoint, in contentView: NSView) -> CGPoint {
        let contentPoint = contentView.convert(point, from: nil)
        let y = SelectionAnchorCoordinate.y(
            Double(contentPoint.y),
            contentHeight: Double(contentView.bounds.height),
            contentViewIsFlipped: contentView.isFlipped
        )
        return CGPoint(x: contentPoint.x, y: y)
    }
}
