// Compile with App/WindowBridge/WindowBridgeContract.swift; pass the packaged bridge bundle path.
import AppKit

@main struct WindowHoverCheck {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let bundle = Bundle(path: CommandLine.arguments[1])!
        guard bundle.load(), let type = NSClassFromString("WeiBeiCatalystWindowBridge") as? CatalystWindowBridge.Type else {
            fatalError("Cannot load native bridge")
        }
        let bridge = type.init()
        let windows = [NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: [.titled], backing: .buffered, defer: false), NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)]
        for window in windows { window.acceptsMouseMovedEvents = false }
        bridge.configure(mode: "paper", intensity: 1)
        for (index, window) in windows.enumerated() {
            print("\(index == 0 ? "main" : "popover"): mouseMoved=\(window.acceptsMouseMovedEvents), visible=\(window.isVisible)")
        }
        if windows.contains(where: { !$0.acceptsMouseMovedEvents }) { exit(1) }
    }
}
