import AppKit
import Combine

/// Native window services and Sparkle use this bridge; content stays in Catalyst.
@objc(WeiBeiCatalystWindowBridge)
final class NativeWindowBridge: NSObject, CatalystWindowBridge {
    private var mode = "paper"
    private var intensity = 1.0
    private let materials = NSMapTable<NSWindow, NSVisualEffectView>.weakToStrongObjects()
    private var observers: [NSObjectProtocol] = []
    private var lastSheetResizeDiagnosticSignature: String?
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
            guard let self, let window = note.object as? NSWindow else { return }
            self.updateToolbarBackground(in: window)
            guard !window.acceptsMouseMovedEvents
                || (self.mode.hasPrefix("glass") && self.materials.object(forKey: window)?.superview == nil) else { return }
            self.apply(to: window)
        })
    }
    func configure(mode: String, intensity: Double) {
        self.mode = mode; self.intensity = intensity
        NSApp.windows.forEach(apply)
    }
    private func apply(to window: NSWindow) {
        // Popovers are borderless windows too; their rows need mouse-move events.
        window.acceptsMouseMovedEvents = true
        updateToolbarBackground(in: window)
        guard window.styleMask.contains(.titled), let content = window.contentView else { return }
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
    private func updateToolbarBackground(in window: NSWindow) {
        let owner = window.toolbar?.identifier == "weibei.workspace" ? window : window.parent
        guard let owner, owner.toolbar?.identifier == "weibei.workspace" else { return }
        // 不设 titlebarAppearsTransparent：macOS 27 beta 上它会吞掉窗口模式的工具栏点击（#21）。
        // 直接清标题栏背景视图的不透明度即可透明，命中链不变（2026-09-20 层级 dump 核实）。
        // 窗口模式背景在本窗口的 NSThemeFrame 下；全屏时 AppKit 把工具栏搬进独立宿主窗口。
        var roots: [NSView] = []
        if let frame = owner.contentView?.superview { roots.append(frame) }
        if let host = owner.toolbar?.items.compactMap({ $0.view?.window }).first, host !== owner,
           let content = host.contentView { roots.append(content) }
        // AppKit resets the fill's alpha during its own layout, so clear only the
        // opacity; keep its layout and the native controls intact.
        func hideBackground(_ view: NSView) {
            if NSStringFromClass(type(of: view)) == "NSTitlebarBackgroundView" {
                if view.alphaValue != 0 { view.alphaValue = 0 }
                return
            }
            view.subviews.forEach(hideBackground)
        }
        roots.forEach(hideBackground)
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
    @MainActor func resizeWorkspaceSheetContent(width: Double, height: Double) -> Bool {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              let keyWindow = NSApp.keyWindow else { return false }
        let sheet = keyWindow.isSheet ? keyWindow : keyWindow.attachedSheet
        guard let sheet, sheet.isSheet,
              sheet.sheetParent?.toolbar?.identifier == "weibei.workspace" else { return false }
        let requested = NSSize(width: width, height: height)
        let actual = sheet.contentLayoutRect.size
        let diagnosticSignature = "\(sheet.windowNumber)|\(requested)|\(actual)|\(sheet.frame)"
        let shouldRecord = diagnosticSignature != lastSheetResizeDiagnosticSignature
        if shouldRecord {
            lastSheetResizeDiagnosticSignature = diagnosticSignature
            recordSheetResize(event: "native-appkit-sheet-before", sheet: sheet, requested: requested)
        }
        if abs(actual.width - requested.width) >= 1 || abs(actual.height - requested.height) >= 1 {
            sheet.setContentSize(requested)
        }
        if shouldRecord {
            recordSheetResize(event: "native-appkit-sheet-after-immediate", sheet: sheet, requested: requested)
            DispatchQueue.main.async { [weak self, weak sheet] in
                guard let self, let sheet else { return }
                self.recordSheetResize(
                    event: "native-appkit-sheet-after-next-runloop",
                    sheet: sheet,
                    requested: requested
                )
            }
        }
        return true
    }

    @MainActor private func recordSheetResize(event: String, sheet: NSWindow, requested: NSSize) {
        guard Bundle.main.bundleIdentifier == "com.changfenhuang.weibei.qa.cursorcloseout20260926" else {
            return
        }
        let outputURL = URL(fileURLWithPath: "/tmp/weibei-import-layout-diagnostics.jsonl")
        let parent = sheet.sheetParent
        let record: [String: Any] = [
            "event": event,
            "timestamp": Date().timeIntervalSince1970,
            "requested": Self.diagnosticSize(requested),
            "windowClass": NSStringFromClass(type(of: sheet)),
            "isKey": sheet.isKeyWindow,
            "isVisible": sheet.isVisible,
            "windowNumber": sheet.windowNumber,
            "sheetParentWindowNumber": parent?.windowNumber ?? -1,
            "frame": Self.diagnosticRect(sheet.frame),
            "contentLayoutRect": Self.diagnosticRect(sheet.contentLayoutRect),
            "contentViewBounds": Self.diagnosticRect(sheet.contentView?.bounds ?? .zero),
            "minSize": Self.diagnosticSize(sheet.minSize),
            "maxSize": Self.diagnosticSize(sheet.maxSize),
            "contentMinSize": Self.diagnosticSize(sheet.contentMinSize),
            "contentMaxSize": Self.diagnosticSize(sheet.contentMaxSize)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return }
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: outputURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data + Data([0x0A]))
        } catch {
            return
        }
    }

    private static func diagnosticRect(_ rect: NSRect) -> [String: Any] {
        [
            "x": diagnosticNumber(rect.origin.x),
            "y": diagnosticNumber(rect.origin.y),
            "width": diagnosticNumber(rect.size.width),
            "height": diagnosticNumber(rect.size.height)
        ]
    }

    private static func diagnosticSize(_ size: NSSize) -> [String: Any] {
        [
            "width": diagnosticNumber(size.width),
            "height": diagnosticNumber(size.height)
        ]
    }

    private static func diagnosticNumber(_ value: CGFloat) -> Any {
        if value.isFinite {
            return Double(value)
        }
        return String(describing: value)
    }

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
