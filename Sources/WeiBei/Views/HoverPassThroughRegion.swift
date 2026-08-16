import AppKit
import SwiftUI

/// Hover probe that never wins hit-testing. Clicks fall through to the
/// document underneath (HTML controls, PDF selection, note editor).
struct HoverPassThroughRegion: NSViewRepresentable {
    var onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> HoverPassThroughTrackingView {
        HoverPassThroughTrackingView(onHoverChange: onHoverChange)
    }

    func updateNSView(_ view: HoverPassThroughTrackingView, context: Context) {
        view.onHoverChange = onHoverChange
    }
}

final class HoverPassThroughTrackingView: NSView {
    var onHoverChange: (Bool) -> Void
    private var activeTrackingArea: NSTrackingArea?

    init(onHoverChange: @escaping (Bool) -> Void) {
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let activeTrackingArea {
            removeTrackingArea(activeTrackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(trackingArea)
        activeTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
