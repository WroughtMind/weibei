import AppKit
import Foundation
import SwiftUI

/// Scroll-rate reading-line crossings for chat turn starts, keyed by message id.
/// Mutated inside probe callbacks only — never a SwiftUI-published value.
final class AgentTurnReadingPositionModel {
    var passedByMessageID: [UUID: Bool] = [:]
}

/// Reports whether the reading line (upper third of the chat viewport) has
/// crossed this row's top edge. Same coalescing contract as the viewport
/// visibility probe: the callback fires only on a flip, so ordinary scrolling
/// never re-enters SwiftUI per frame.
struct AgentTurnReadingPositionProbe: NSViewRepresentable {
    var messageID: UUID
    var onChange: (UUID, Bool) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.messageID = messageID
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.messageID = messageID
        nsView.onChange = onChange
        nsView.ensureObserversInstalled()
        nsView.report()
    }

    final class ProbeView: NSView {
        var messageID: UUID?
        var onChange: ((UUID, Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?
        private weak var observedClipView: NSClipView?

        override func layout() {
            super.layout()
            ensureObserversInstalled()
            report()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            ensureObserversInstalled()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            ensureObserversInstalled()
        }

        fileprivate func report() {
            guard let clipView = enclosingScrollView?.contentView,
                  window != nil,
                  bounds.width > 1,
                  bounds.height > 1 else { return }
            let frameInClip = convert(bounds, to: clipView)
            // Flip-aware reading line: SwiftUI hosting content is flipped, but
            // the predicate must not depend on that.
            let viewportHeight = clipView.bounds.height
            let rowTop: CGFloat
            let readingLine: CGFloat
            if clipView.isFlipped {
                rowTop = frameInClip.minY
                readingLine = clipView.bounds.minY + viewportHeight * 0.32
            } else {
                rowTop = frameInClip.maxY
                readingLine = clipView.bounds.maxY - viewportHeight * 0.32
            }
            let passed = clipView.isFlipped ? rowTop <= readingLine : rowTop >= readingLine
            guard passed != lastReported else { return }
            lastReported = passed
            guard let id = messageID else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(id, passed)
            }
        }

        fileprivate func ensureObserversInstalled() {
            guard let clipView = enclosingScrollView?.contentView else { return }
            guard observedClipView !== clipView else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            observedClipView = clipView
            clipView.postsBoundsChangedNotifications = true
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in self?.report() })
            observers.append(center.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in self?.report() })
            report()
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
