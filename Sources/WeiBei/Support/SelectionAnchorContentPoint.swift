import AppKit
import WeiBeiCore

enum SelectionAnchorContentPoint {
    static func fromWebPayload(_ payload: [String: Any]?, in view: NSView?) -> SelectionPopoverAnchor? {
        guard let payload, let view, let x = payload["x"] as? Double, let y = payload["y"] as? Double,
              x.isFinite, y.isFinite,
              var result = fromWebPoint(x: x, y: y, prefersAbove: payload["prefersAbove"] as? Bool == true, in: view) else { return nil }
        if let anchor = payload["anchor"] as? [String: Any],
           let start = anchor["startOffset"] as? Int, let end = anchor["endOffset"] as? Int,
           start >= 0, end > start {
            result.textAnchor = SelectionTextAnchor(startOffset: start, endOffset: end)
        }
        return result
    }

    static func fromLocalPoint(_ point: CGPoint, in view: NSView) -> SelectionPopoverAnchor? {
        guard let window = view.window,
              let contentView = window.contentView else {
            return nil
        }
        return fromWindowPoint(view.convert(point, to: nil), in: contentView)
    }

    static func fromWebPoint(x: Double, y: Double, prefersAbove: Bool = false, in view: NSView) -> SelectionPopoverAnchor? {
        let localY = view.isFlipped ? CGFloat(y) : view.bounds.height - CGFloat(y)
        guard var anchor = fromLocalPoint(CGPoint(x: CGFloat(x), y: localY), in: view) else { return nil }
        anchor.prefersAbove = prefersAbove
        return anchor
    }

    static func fromScreenPoint(_ point: CGPoint, in window: NSWindow) -> SelectionPopoverAnchor? {
        guard let contentView = window.contentView else { return nil }
        return fromWindowPoint(window.convertPoint(fromScreen: point), in: contentView)
    }

    private static func fromWindowPoint(_ point: CGPoint, in contentView: NSView) -> SelectionPopoverAnchor {
        let contentPoint = contentView.convert(point, from: nil)
        let y = SelectionAnchorCoordinate.y(
            Double(contentPoint.y),
            contentHeight: Double(contentView.bounds.height),
            contentViewIsFlipped: contentView.isFlipped
        )
        return SelectionPopoverAnchor(x: contentPoint.x, y: y)
    }
}
