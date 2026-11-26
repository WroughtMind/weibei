#if targetEnvironment(macCatalyst)
import UIKit
import WebKit
typealias SelectionPlatformView = UIView
#else
import AppKit
typealias SelectionPlatformView = NSView
#endif
import WeiBeiCore

enum SelectionAnchorContentPoint {
    static func fromWebPayload(_ payload: [String: Any]?, in view: SelectionPlatformView?) -> SelectionPopoverAnchor? {
        guard let payload, let view, let x = payload["x"] as? Double, let y = payload["y"] as? Double,
              x.isFinite, y.isFinite else { return nil }
        var point = CGPoint(x: x, y: y)
        var scale: CGFloat = 1
#if targetEnvironment(macCatalyst)
        if let scrollView = (view as? WKWebView)?.scrollView,
           let scrollX = payload["scrollX"] as? Double, let scrollY = payload["scrollY"] as? Double,
           scrollX.isFinite, scrollY.isFinite {
            // The browser reports viewport coordinates. Map through the native scroll view
            // so the selection includes the actual toolbar inset and page scale.
            scale = scrollView.zoomScale
            let documentPoint = CGPoint(x: (x + scrollX) * scale, y: (y + scrollY) * scale)
            point = scrollView.convert(documentPoint, to: view)
        }
#endif
        guard var result = fromWebPoint(x: point.x, y: point.y,
            prefersAbove: payload["prefersAbove"] as? Bool == true, in: view) else { return nil }
        if let height = payload["height"] as? Double, height.isFinite, height > 0 {
            result.selectionHeight = height * scale
        }
        if let anchor = payload["anchor"] as? [String: Any],
           let start = anchor["startOffset"] as? Int, let end = anchor["endOffset"] as? Int,
           start >= 0, end > start {
            result.textAnchor = SelectionTextAnchor(startOffset: start, endOffset: end, location: anchor["location"] as? String, revision: (anchor["revision"] as? NSNumber)?.uint64Value, sourceOrder: anchor["sourceOrder"] as? [Int])
        }
        return result
    }

    static func fromLocalPoint(_ point: CGPoint, in view: SelectionPlatformView, selectionHeight: CGFloat? = nil) -> SelectionPopoverAnchor? {
#if targetEnvironment(macCatalyst)
        guard let contentView = view.window?.rootViewController?.view else { return nil }
        let point = view.convert(point, to: contentView)
        return SelectionPopoverAnchor(x: point.x, y: point.y, selectionHeight: selectionHeight)
#else
        guard let window = view.window,
              let contentView = window.contentView else {
            return nil
        }
        var anchor = fromWindowPoint(view.convert(point, to: nil), in: contentView)
        anchor.selectionHeight = selectionHeight
        return anchor
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
    static func fromTextRange(_ range: NSRange, in view: NSTextView) -> SelectionPopoverAnchor? {
        guard range.length > 0, let window = view.window else { return nil }
        let first = view.firstRect(forCharacterRange: range, actualRange: nil)
        guard !first.isEmpty else { return nil }
        let lastRange = NSRange(location: NSMaxRange(range) - 1, length: 1)
        let last = view.firstRect(forCharacterRange: lastRange, actualRange: nil)
        let rect = last.isEmpty ? first : last
        return fromScreenPoint(CGPoint(x: rect.midX, y: rect.minY), in: window,
                               selectionHeight: first.union(rect).height)
    }

    static func fromScreenPoint(_ point: CGPoint, in window: NSWindow, selectionHeight: CGFloat? = nil) -> SelectionPopoverAnchor? {
        guard let contentView = window.contentView else { return nil }
        var anchor = fromWindowPoint(window.convertPoint(fromScreen: point), in: contentView)
        anchor.selectionHeight = selectionHeight
        return anchor
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
