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
        // Catalyst installs its toolbar after the bridge is first configured.
        let main = windows[0]
        let toolbar = NSToolbar(identifier: "weibei.workspace")
        main.toolbar = toolbar
        let originalStyle = main.styleMask
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: main)
        precondition(main.titlebarAppearsTransparent && main.styleMask == originalStyle)
        for mode in ["glassLight", "glassDark", "paper"] {
            bridge.configure(mode: mode, intensity: 1)
            precondition(main.toolbar === toolbar && main.titlebarAppearsTransparent)
            precondition(main.styleMask == originalStyle)
            precondition(!windows[1].titlebarAppearsTransparent)
        }
        precondition(windows.allSatisfy { !$0.isVisible })
        print("workspace toolbar: transparent, native content frame retained, theme changes passed")
    }
}
