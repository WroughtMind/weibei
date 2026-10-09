import AppKit
import Darwin

// Visible windows are permitted only on the isolated CI desktop.
guard ProcessInfo.processInfo.environment["CI"] == "true",
      CommandLine.arguments.count == 2 else {
    fputs("原生全屏对照仅能在隔离 CI 桌面运行。\n", stderr)
    exit(2)
}

@MainActor
final class NativeFullScreenCheck: NSObject, NSApplicationDelegate {
    private let output: URL
    private var window: NSWindow!
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var stage = "launch"
    private var deadline = Date().addingTimeInterval(20)
    private var events: [[String: Any]] = []

    init(output: URL) { self.output = output }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "原生全屏环境对照"
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.center()
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.willExitFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.received(note) }
            })
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func state() -> [String: Any] {
        ["stage": stage, "main_thread": Thread.isMainThread,
         "run_loop_mode": RunLoop.current.currentMode?.rawValue ?? "nil",
         "app_active": NSApp.isActive, "visible": window.isVisible,
         "key": window.isKeyWindow, "on_active_space": window.isOnActiveSpace,
         "full_screen": window.styleMask.contains(.fullScreen),
         "frame": NSStringFromRect(window.frame),
         "window_identity": String(describing: ObjectIdentifier(window!))]
    }

    private func tick() {
        if Date() >= deadline { finish("failed", failure: "timeout: " + stage); return }
        guard stage == "launch", NSApp.isActive, window.isKeyWindow else { return }
        stage = "entering"
        deadline = Date().addingTimeInterval(20)
        events.append(state())
        window.toggleFullScreen(nil)
    }

    private func received(_ note: Notification) {
        var event = state()
        event["notification"] = note.name.rawValue
        events.append(event)
        if note.name == NSWindow.didEnterFullScreenNotification, stage == "entering" {
            guard window.styleMask.contains(.fullScreen), window.isOnActiveSpace else {
                finish("failed", failure: "entered notification without full-screen state"); return
            }
            stage = "entered"
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stage = "exiting"
                self.deadline = Date().addingTimeInterval(20)
                self.window.toggleFullScreen(nil)
            }
        } else if note.name == NSWindow.didExitFullScreenNotification, stage == "exiting" {
            guard !window.styleMask.contains(.fullScreen), window.isOnActiveSpace else {
                finish("failed", failure: "exited notification without windowed state"); return
            }
            finish("passed")
        }
    }

    private func finish(_ status: String, failure: String? = nil) {
        timer?.invalidate()
        var result = state()
        result["status"] = status
        result["failure"] = failure
        result["events"] = events
        result["system"] = ProcessInfo.processInfo.operatingSystemVersionString
        result["screens"] = NSScreen.screens.map { NSStringFromRect($0.frame) }
        result["dock_pids"] = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").map(\.processIdentifier)
        result["runner"] = ProcessInfo.processInfo.environment.filter {
            ["ImageOS", "ImageVersion", "RUNNER_ARCH", "RUNNER_ENVIRONMENT"].contains($0.key)
        }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        } catch {
            fputs("全屏对照记录写入失败：\(error)\n", stderr)
            exit(1)
        }
        print("原生全屏对照：\(status) \(failure ?? "")")
        exit(status == "passed" ? 0 : 1)
    }
}

MainActor.assumeIsolated {
    let controller = NativeFullScreenCheck(output: URL(fileURLWithPath: CommandLine.arguments[1]))
    let app = NSApplication.shared
    app.delegate = controller
    app.setActivationPolicy(.regular)
    withExtendedLifetime(controller) { app.run() }
}
