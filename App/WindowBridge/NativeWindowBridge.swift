import AppKit
import Combine

/// Native window services and Sparkle use this bridge; content stays in Catalyst.
@objc(WeiBeiCatalystWindowBridge)
final class NativeWindowBridge: NSObject, CatalystWindowBridge {
    private var mode = "paper"
    private var intensity = 1.0
    private let materials = NSMapTable<NSWindow, NSVisualEffectView>.weakToStrongObjects()
    private var observers: [NSObjectProtocol] = []
    @MainActor private lazy var updateService = WeiBeiUpdateService()
    @MainActor private var updateObservation: AnyCancellable?

    required override init() {
        super.init()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let window = note.object as? NSWindow else { return }
                self?.apply(to: window)
            })
        }
        // A Catalyst scene can acquire its NSWindow after configure(), and a
        // background/PiP window need not become key. Apply input settings too.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow,
                  !window.acceptsMouseMovedEvents
                    || (self.mode.hasPrefix("glass") && self.materials.object(forKey: window)?.superview == nil) else { return }
            self.apply(to: window)
        })
    }
    func configure(mode: String, intensity: Double) {
        self.mode = mode; self.intensity = intensity
        NSApp.windows.forEach(apply)
    }
    private func apply(to window: NSWindow) {
        guard window.styleMask.contains(.titled), let content = window.contentView else { return }
        window.acceptsMouseMovedEvents = true
        let glass = ["glassLight", "glassDark", "glassMist", "glassSlate"].contains(mode)
        window.isOpaque = !glass
        guard glass else {
            materials.object(forKey: window)?.removeFromSuperview()
            materials.removeObject(forKey: window)
            return
        }
        let material: NSVisualEffectView
        if let existing = materials.object(forKey: window), existing.superview === content {
            material = existing
        } else {
            material = NSVisualEffectView(frame: content.bounds)
            material.autoresizingMask = [.width, .height]
            material.blendingMode = .behindWindow
            material.state = .active
            content.addSubview(material, positioned: .below, relativeTo: nil)
            materials.setObject(material, forKey: window)
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        let fullScreen = window.styleMask.contains(.fullScreen)
        switch mode {
        case "glassLight":
            material.material = fullScreen ? .windowBackground : .underWindowBackground
            material.alphaValue = (fullScreen ? 0.88 : 0.38) * intensity
        case "glassDark":
            material.material = .hudWindow
            material.alphaValue = 0.58 * intensity
        case "glassMist":
            material.material = .popover
            material.alphaValue = 1
        case "glassSlate":
            material.material = .hudWindow
            material.alphaValue = 1
        default: break
        }
    }
    func pushCursor(_ name: String) {
        switch name {
        case "openHand": NSCursor.openHand.push()
        case "closedHand": NSCursor.closedHand.push()
        case "resizeLeftRight": NSCursor.resizeLeftRight.push()
        case "resizeUpDown": NSCursor.resizeUpDown.push()
        case "crosshair": NSCursor.crosshair.push()
        default: NSCursor.arrow.push()
        }
    }
    func popCursor() { NSCursor.pop() }
    func setCursor(_ name: String) {
        if name == "pointingHand" { NSCursor.pointingHand.set() }
        else { NSCursor.iBeam.set() }
    }
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func materialWindowCount() -> Int { materials.count }
    @MainActor func observeUpdates(_ observer: @escaping (String, String?, [String], Bool, URL?) -> Void) {
        updateObservation = updateService.$status.combineLatest(updateService.$availableUpdate)
            .sink { status, update in
                observer(status.rawValue, update?.version, update?.releaseNotesLines ?? [],
                    update?.informationOnly ?? false, update?.informationURL)
            }
    }
    @MainActor func checkForUpdates() { updateService.checkForUpdates() }
    @MainActor func installAvailableUpdate() { updateService.installAvailableUpdate() }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}
