// Compile with App/WindowBridge/WindowBridgeContract.swift; pass the packaged bridge bundle path.
import AppKit

final class ToolbarCheckDelegate: NSObject, NSToolbarDelegate {
    let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("weibei.navigation"))
    override init() {
        super.init()
        item.view = NSButton(title: "Toolbar action", target: nil, action: nil)
        item.autovalidates = false
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [item.itemIdentifier] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { item }
}

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
        let delegate = ToolbarCheckDelegate()
        toolbar.delegate = delegate
        main.toolbar = toolbar
        let originalStyle = main.styleMask
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: main)
        precondition(main.titlebarAppearsTransparent && main.styleMask == originalStyle)
        // Catalyst owns its full-height content and toolbar input geometry.
        main.styleMask.insert(.fullSizeContentView)
        for mode in ["glassLight", "glassDark", "paper"] {
            bridge.configure(mode: mode, intensity: 1)
            precondition(main.toolbar === toolbar && main.titlebarAppearsTransparent)
            precondition(main.styleMask == originalStyle.union(.fullSizeContentView))
            precondition(main.contentView!.frame.height > main.contentLayoutRect.height)
            // Native glass backgrounds stay below content; no tint or hit-test
            // layer may be inserted over the toolbar's scrolling content.
            precondition(main.contentView!.subviews.allSatisfy {
                !($0 is NSVisualEffectView) || ($0 as! NSVisualEffectView).blendingMode == .behindWindow
            })
            precondition(!windows[1].titlebarAppearsTransparent)
        }
        // Reproduce AppKit moving the existing toolbar views to its full-screen
        // host, without opening a window or changing the user's desktop Space.
        func background(in view: NSView) -> NSView? {
            if NSStringFromClass(Swift.type(of: view)) == "NSTitlebarBackgroundView" { return view }
            return view.subviews.lazy.compactMap { background(in: $0) }.first
        }
        let fill = background(in: main.contentView!.superview!)!
        let button = delegate.item.view!
        let buttonFrame = button.frame
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 40), styleMask: [], backing: .buffered, defer: false)
        host.contentView!.addSubview(fill)
        host.contentView!.addSubview(button)
        fill.isHidden = false
        fill.alphaValue = 1
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: main)
        precondition(fill.alphaValue == 0 && button.window === host && delegate.item.isEnabled)
        // AppKit owns visibility and can reset it during its next layout.
        // The background must remain transparent through that update.
        fill.isHidden = false
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: main)
        precondition(fill.alphaValue == 0 && button.frame == buttonFrame)
        precondition(!host.isVisible)
        precondition(windows.allSatisfy { !$0.isVisible })
        print("workspace toolbar: fullscreen fill is transparent; native controls and frames preserved")
        withExtendedLifetime((bridge, delegate)) {}
    }
}
