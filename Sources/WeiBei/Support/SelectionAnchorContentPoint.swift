#if targetEnvironment(macCatalyst)
import UIKit
typealias SelectionPlatformView = UIView
#else
import AppKit
typealias SelectionPlatformView = NSView
#endif
import WeiBeiCore

enum SelectionAnchorContentPoint {
    static func fromWebPayload(_ payload: [String: Any]?, in view: SelectionPlatformView?) -> SelectionPopoverAnchor? {
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

    static func fromLocalPoint(_ point: CGPoint, in view: SelectionPlatformView) -> SelectionPopoverAnchor? {
#if targetEnvironment(macCatalyst)
        guard let contentView = view.window?.rootViewController?.view else { return nil }
        let point = view.convert(point, to: contentView)
        return SelectionPopoverAnchor(x: point.x, y: point.y)
#else
        guard let window = view.window,
              let contentView = window.contentView else {
            return nil
        }
        return fromWindowPoint(view.convert(point, to: nil), in: contentView)
#endif
    }

    static func fromWebPoint(x: Double, y: Double, prefersAbove: Bool = false, in view: SelectionPlatformView) -> SelectionPopoverAnchor? {
#if targetEnvironment(macCatalyst)
        let localY = CGFloat(y)
#else
        let localY = view.isFlipped ? CGFloat(y) : view.bounds.height - CGFloat(y)
#endif
        guard var anchor = fromLocalPoint(CGPoint(x: CGFloat(x), y: localY), in: view) else { return nil }
        anchor.prefersAbove = prefersAbove
        return anchor
    }

#if !targetEnvironment(macCatalyst)
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
#endif
}
