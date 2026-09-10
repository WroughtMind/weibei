import AppKit

// Protect the native event surface below UIKit: view.hitTest alone cannot detect
// WindowServer skipping transparent glass between messages or above an empty chat.
@main
enum WindowInputCheck {
    @MainActor
    static func main() {
        precondition(ProcessInfo.processInfo.environment["CI"] == "true",
                     "Run real local windows through picture-in-picture.")
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 480),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        let bridge = NativeWindowBridge()
        var results: [String: Bool] = [:]
        for mode in ["glassLight", "glassDark"] {
            for intensity in [0.02, 1.0] {
                bridge.configure(mode: mode, intensity: intensity)
                // Let AppKit publish the backing surface before querying the
                // system's real window hit test. No synthetic mouse events.
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                let points = [NSPoint(x: 24, y: 240), NSPoint(x: 320, y: 240),
                              NSPoint(x: 616, y: 240), NSPoint(x: 320, y: 460)]
                let acceptsBlank = points.allSatisfy {
                    NSWindow.windowNumber(at: window.convertPoint(toScreen: $0), belowWindowWithWindowNumber: 0)
                        == window.windowNumber
                }
                results["\(mode)_\(intensity)"] = acceptsBlank && window.acceptsMouseMovedEvents
            }
        }
        let data = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        window.close()
        exit(results.values.allSatisfy { $0 } ? 0 : 1)
    }
}
