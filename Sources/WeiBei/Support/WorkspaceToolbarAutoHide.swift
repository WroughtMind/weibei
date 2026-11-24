#if !targetEnvironment(macCatalyst)
import AppKit
#if SWIFT_PACKAGE
import WeiBeiCore
#endif

/// Windowed toolbar controls animate without changing the reading viewport or
/// the native hit frames. The system owns the title bar in full screen.
@MainActor
final class WorkspaceToolbarAutoHide {
    private weak var toolbar: NSToolbar?
    private weak var window: NSWindow?
    let hoverRegion = WorkspaceToolbarHoverRegion()
    private var presentations: [Presentation] = []
    private weak var navigationView: NSView?
    private var navigationTravel: CGFloat = 0
    private var unclippedAncestors: [WeakView] = []
    private var revealTask: Task<Void, Never>?
    private var delayingWindowButtons = false
    private var fadingOutUntil: TimeInterval = 0
    private var hideTask: Task<Void, Never>?
    private var inputMonitor: Any?
    private var pointerInside = false
    private var keyboardFocused = false
    private(set) var controlsVisible = false
    var reduceMotion: Bool {
        didSet {
            guard reduceMotion, !oldValue, revealTask != nil else { return }
            let buttonsAreWaiting = delayingWindowButtons
            cancelReveal()
            if buttonsAreWaiting { fade(presentations.filter(\.isWindowButton), visible: true) }
        }
    }
    private static let opacityAnimation = "weibei.toolbar-opacity"

    private struct Presentation {
        weak var view: NSView?
        let alpha: CGFloat
        let isWindowButton: Bool
        let installedLayer: Bool
    }

    private struct WeakView {
        weak var view: NSView?
    }

    init(toolbar: NSToolbar, reduceMotion: Bool = false) {
        self.toolbar = toolbar
        self.reduceMotion = reduceMotion
        hoverRegion.onHoverChange = { [weak self] inside in self?.setPointerInside(inside) }
    }

    func refresh(in window: NSWindow) {
        guard let toolbar, toolbar.isVisible, !window.styleMask.contains(.fullScreen) else {
            detach()
            return
        }
        let items = toolbar.items.compactMap(\.view).filter { $0.window != nil }
        guard let host = items.first?.window,
              let root = host.contentView?.superview else {
            detach()
            return
        }
        self.window = window
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
            .filter { $0.window === host }
        let attached = items.filter { $0.window === host } + buttons
        guard !attached.isEmpty else { return }
        let itemBounds = attached.reduce(NSRect.null) { $0.union($1.convert($1.bounds, to: root)) }
        let nativeHeight = host === window ? max(0, window.frame.height - window.contentLayoutRect.maxY) : 0
        let controlsHeight = root.isFlipped ? itemBounds.maxY - root.bounds.minY : root.bounds.maxY - itemBounds.minY
        let height = min(root.bounds.height, max(nativeHeight, controlsHeight))
        let region = NSRect(x: root.bounds.minX,
                            y: root.isFlipped ? root.bounds.minY : root.bounds.maxY - height,
                            width: root.bounds.width, height: height)

        // Keep AppKit's overflow with the toolbar groups and the traffic lights
        // separate, even when all of them share a title-bar ancestor.
        let roots = items.filter { $0.window === host }.map { view -> NSView in
            var candidate = view
            while let parent = candidate.superview, parent !== root,
                  parent !== host.contentView,
                  region.insetBy(dx: -1, dy: -1).contains(parent.convert(parent.bounds, to: root)),
                  !buttons.contains(where: { $0.isDescendant(of: parent) }) {
                candidate = parent
            }
            return candidate
        }
        var controls: [NSView] = []
        for view in roots where !controls.contains(where: { $0 === view }) {
            if !roots.contains(where: { $0 !== view && view.isDescendant(of: $0) }) { controls.append(view) }
        }
        replaceControls(controls + buttons, windowButtons: buttons)
        let navigation = toolbar.items.first { $0.itemIdentifier.rawValue == "weibei.navigation" }?.view
        let nextNavigation = navigation?.window === host ? navigation : nil
        if navigationView !== nextNavigation {
            let wasDelaying = delayingWindowButtons
            cancelReveal()
            navigationView = nextNavigation
            if wasDelaying {
                fade(presentations.filter(\.isWindowButton), visible: true)
            }
        }
        if let navigation = nextNavigation, let firstButton = buttons.first {
            navigationTravel = max(0, navigation.convert(navigation.bounds, to: root).minX
                - firstButton.convert(firstButton.bounds, to: root).minX)
        } else { navigationTravel = 0 }
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
                        let inside = self.hoverRegion.bounds.contains(point)
                        self.setPointerInside(inside)
                        if inside && self.delayingWindowButtons
                            && (event.type == .leftMouseDown || event.type == .rightMouseDown) {
                            // A click where the sliding capsule just was must
                            // not activate a window button that has yet to appear.
                            if self.presentations.contains(where: {
                                guard $0.isWindowButton, let view = $0.view else { return false }
                                return view.bounds.contains(view.convert(host.convertPoint(fromScreen: screenPoint), from: nil))
                            }) { return nil }
                        }
                    }
                    return event
                }
                // AppKit moves keyboard focus after dispatching the key. Only
                // toolbar focus reveals it; typing in a document does not.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.keyboardFocused = self.hasToolbarFocus
                    if self.keyboardFocused { self.setVisible(true, animated: false) }
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

    private func replaceControls(_ controls: [NSView], windowButtons: [NSView]) {
        for item in presentations where !controls.contains(where: { $0 === item.view }) {
            restore(item)
        }
        presentations = controls.map { view in
            if let existing = presentations.first(where: { $0.view === view }) { return existing }
            let isWindowButton = windowButtons.contains { $0 === view }
            // AppKit can create a traffic light's first layer when alpha is
            // set to 1. Install it beforehand so the first reveal can animate.
            let installedLayer = view.layer == nil && !view.wantsLayer
            let item = Presentation(view: view, alpha: view.alphaValue,
                                    isWindowButton: isWindowButton, installedLayer: installedLayer)
            if installedLayer { view.wantsLayer = true }
            view.alphaValue = controlsVisible && !(isWindowButton && delayingWindowButtons) ? item.alpha : 0
            return item
        }
    }

    private func setVisible(_ visible: Bool, animated: Bool = true) {
        guard controlsVisible != visible || !animated else { return }
        controlsVisible = visible
        cancelReveal()
        guard animated else {
            for item in presentations {
                item.view?.layer?.removeAnimation(forKey: Self.opacityAnimation)
                item.view?.alphaValue = visible ? item.alpha : 0
            }
            return
        }

        if !visible {
            fadingOutUntil = CACurrentMediaTime() + fadeDuration
            fade(presentations, visible: false)
            return
        }

        // Reversing a fade-out keeps the capsule at its existing position.
        guard !reduceMotion, CACurrentMediaTime() >= fadingOutUntil, beginNavigationSlide() else {
            fade(presentations, visible: true)
            return
        }
        delayingWindowButtons = true
        fade(presentations.filter { !$0.isWindowButton }, visible: true)
        // Start the lights near the end of the navigation's deceleration.
        // The stagger and fade fit within one small entrance.
        let delay = WeiBeiMotionTokens.durationSm - fadeDuration
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.delayingWindowButtons = false
            self.fade(self.presentations.filter(\.isWindowButton), visible: true)
            try? await Task.sleep(for: .seconds(WeiBeiMotionTokens.durationSmExit - delay))
            guard !Task.isCancelled else { return }
            self.cancelReveal()
        }
    }

    private var fadeDuration: TimeInterval {
        reduceMotion ? WeiBeiMotionTokens.durationSmExit : WeiBeiMotionTokens.durationControl
    }

    private func fade(_ items: [Presentation], visible: Bool) {
        let curve = visible || reduceMotion ? WeiBeiMotionTokens.easeOut : WeiBeiMotionTokens.easeIn
        let timing = CAMediaTimingFunction(
            controlPoints: Float(curve.x1), Float(curve.y1), Float(curve.x2), Float(curve.y2)
        )
        let duration = fadeDuration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for item in items {
            guard let view = item.view else { continue }
            let target = visible ? item.alpha : 0
            let current = view.layer?.presentation()?.opacity ?? Float(view.alphaValue)
            // Publish the hit-test state immediately and animate from the
            // rendered opacity so reversing direction doesn't flash.
            view.alphaValue = target
            guard let layer = view.layer else { continue }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = current
            fade.toValue = Float(target)
            fade.duration = duration
            fade.timingFunction = timing
            layer.add(fade, forKey: Self.opacityAnimation)
        }
        CATransaction.commit()
    }

    private func restore(_ item: Presentation) {
        guard let view = item.view else { return }
        view.layer?.removeAnimation(forKey: Self.opacityAnimation)
        view.alphaValue = item.alpha
        if item.installedLayer { view.wantsLayer = false }
    }

    private func beginNavigationSlide() -> Bool {
        guard let navigationView, navigationTravel > 0, let root = hoverRegion.superview,
              let host = navigationView.window else { return false }
        if navigationView.layer == nil { navigationView.wantsLayer = true }
        guard let layer = navigationView.layer else { return false }

        // The capsule crosses the native leading gap during the animation. Only
        // loosen clipping in the toolbar; the model frame stays at its hit target.
        var ancestor = navigationView.superview
        while let view = ancestor, view !== root, view !== host.contentView,
              hoverRegion.frame.insetBy(dx: -1, dy: -1).contains(view.convert(view.bounds, to: root)) {
            if view.clipsToBounds {
                view.clipsToBounds = false
                unclippedAncestors.append(WeakView(view: view))
            }
            ancestor = view.superview
        }
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = -navigationTravel
        slide.toValue = 0
        slide.isAdditive = true
        slide.duration = WeiBeiMotionTokens.durationSmExit
        let curve = WeiBeiMotionTokens.easeOutStrong
        slide.timingFunction = CAMediaTimingFunction(
            controlPoints: Float(curve.x1), Float(curve.y1), Float(curve.x2), Float(curve.y2)
        )
        layer.add(slide, forKey: "weibei.navigation-reveal")
        return true
    }

    private func cancelReveal() {
        revealTask?.cancel()
        revealTask = nil
        delayingWindowButtons = false
        navigationView?.layer?.removeAnimation(forKey: "weibei.navigation-reveal")
        for entry in unclippedAncestors { entry.view?.clipsToBounds = true }
        unclippedAncestors.removeAll()
    }

    func detach() {
        cancelReveal()
        navigationView = nil
        fadingOutUntil = 0
        hideTask?.cancel(); hideTask = nil
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
        hoverRegion.removeFromSuperview()
        for item in presentations { restore(item) }
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
