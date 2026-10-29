#if !targetEnvironment(macCatalyst)
import AppKit

/// The native toolbar stays mounted so its safe area and the reading viewport
/// never change. Only the controls' opacity changes, including window buttons.
@MainActor
final class WorkspaceToolbarAutoHide {
    private weak var toolbar: NSToolbar?
    private weak var window: NSWindow?
    let hoverRegion = WorkspaceToolbarHoverRegion()
    private var presentations: [Presentation] = []
    private var hideTask: Task<Void, Never>?
    private var inputMonitor: Any?
    private var pointerInside = false
    private var keyboardFocused = false
    private(set) var controlsVisible = false

    private struct Presentation {
        weak var view: NSView?
        let alpha: CGFloat
    }

    init(toolbar: NSToolbar) {
        self.toolbar = toolbar
        hoverRegion.onHoverChange = { [weak self] inside in self?.setPointerInside(inside) }
    }

    func refresh(in window: NSWindow) {
        guard let toolbar, toolbar.isVisible else { detach(); return }
        self.window = window
        let items = toolbar.items.compactMap(\.view).filter { $0.window != nil }
        guard let host = items.first?.window,
              let root = host.contentView?.superview else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        let attached = (items + buttons).filter { $0.window === host }
        guard !attached.isEmpty else { return }
        let itemBounds = attached.reduce(NSRect.null) { $0.union($1.convert($1.bounds, to: root)) }
        let nativeHeight = host === window ? max(0, window.frame.height - window.contentLayoutRect.maxY) : 0
        let controlsHeight = root.isFlipped ? itemBounds.maxY - root.bounds.minY : root.bounds.maxY - itemBounds.minY
        let height = min(root.bounds.height, max(nativeHeight, controlsHeight))
        let region = NSRect(x: root.bounds.minX,
                            y: root.isFlipped ? root.bounds.minY : root.bounds.maxY - height,
                            width: root.bounds.width, height: height)

        // Include each toolbar group's native wrapper. The shared wrapper also
        // owns AppKit's overflow button in narrow windows. Never fade content.
        let roots = attached.map { view -> NSView in
            var candidate = view
            while let parent = candidate.superview, parent !== root,
                  parent !== host.contentView,
                  region.insetBy(dx: -1, dy: -1).contains(parent.convert(parent.bounds, to: root)) {
                candidate = parent
            }
            return candidate
        }
        var controls: [NSView] = []
        for view in roots where !controls.contains(where: { $0 === view }) {
            if !roots.contains(where: { $0 !== view && view.isDescendant(of: $0) }) { controls.append(view) }
        }
        replaceControls(controls)
        if hoverRegion.superview !== root {
            hoverRegion.removeFromSuperview()
            root.addSubview(hoverRegion, positioned: .above, relativeTo: nil)
        }
        if hoverRegion.frame != region { hoverRegion.frame = region }
        if inputMonitor == nil {
            inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let eventWindow = event.window,
                      eventWindow === self.window || eventWindow === self.hoverRegion.window else { return event }
                if event.type != .keyDown {
                    if let host = self.hoverRegion.window {
                        let screenPoint = eventWindow.convertPoint(toScreen: event.locationInWindow)
                        let point = self.hoverRegion.convert(host.convertPoint(fromScreen: screenPoint), from: nil)
                        self.setPointerInside(self.hoverRegion.bounds.contains(point))
                    }
                    return event
                }
                // AppKit moves keyboard focus after dispatching the key. Only
                // toolbar focus reveals it; typing in a document does not.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.keyboardFocused = self.hasToolbarFocus
                    if self.keyboardFocused { self.setVisible(true) }
                    else if !self.pointerInside { self.scheduleHide() }
                }
                return event
            }
        }
    }

    private var hasToolbarFocus: Bool {
        guard let responder = hoverRegion.window?.firstResponder as? NSView else { return false }
        return presentations.contains { item in
            item.view.map { responder === $0 || responder.isDescendant(of: $0) } ?? false
        }
    }

    /// Shared by tracking and the native input checks; this does not synthesize
    /// a pointer event or change window focus.
    func setPointerInside(_ inside: Bool) {
        guard inside != pointerInside || keyboardFocused else { return }
        pointerInside = inside
        keyboardFocused = false
        hideTask?.cancel()
        hideTask = nil
        if inside { setVisible(true) }
        else { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            // Let the pointer cross the small gap to a toolbar popover without
            // flicker. No window or content geometry changes during this grace.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, !self.pointerInside else { return }
            if self.keyboardFocused && self.hasToolbarFocus { return }
            self.setVisible(false)
        }
    }

    private func replaceControls(_ controls: [NSView]) {
        for item in presentations where !controls.contains(where: { $0 === item.view }) {
            item.view?.alphaValue = item.alpha
        }
        presentations = controls.map { view in
            if let existing = presentations.first(where: { $0.view === view }) { return existing }
            let item = Presentation(view: view, alpha: view.alphaValue)
            view.alphaValue = controlsVisible ? item.alpha : 0
            return item
        }
    }

    private func setVisible(_ visible: Bool) {
        guard controlsVisible != visible else { return }
        controlsVisible = visible
        // Keep hit regions and accessibility actions intact. The tracking view
        // passes through clicks, so the first click can reach the revealed item.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            for item in presentations {
                item.view?.animator().alphaValue = visible ? item.alpha : 0
            }
        }
    }

    func detach() {
        hideTask?.cancel(); hideTask = nil
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        hoverRegion.removeFromSuperview()
        for item in presentations { item.view?.alphaValue = item.alpha }
        presentations.removeAll()
        pointerInside = false
        keyboardFocused = false
        controlsVisible = false
        window = nil
    }
}

@MainActor
final class WorkspaceToolbarHoverRegion: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self)
        self.area = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        onHoverChange?(true)
    }
    override func mouseMoved(with event: NSEvent) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        onHoverChange?(true)
    }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
