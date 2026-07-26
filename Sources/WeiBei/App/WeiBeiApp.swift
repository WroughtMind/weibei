import AppKit
import SwiftUI
import WeiBeiCore

private let runsImportedIdentitySelfCheck = ProcessInfo.processInfo.arguments.contains("--self-check-imported-identity")
private let importedIdentitySelfCheckBootstrapDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-imported-identity-bootstrap-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

@MainActor let sharedWorkspaceStore = runsImportedIdentitySelfCheck
    ? WorkspaceStore(
        workspaceDirectory: importedIdentitySelfCheckBootstrapDirectory,
        apiKeyLoader: { _ in "" }
    )
    : WorkspaceStore()

/**
 * 协调 macOS 应用生命周期与工作区资源收尾。
 */
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shortcutMonitor: Any?
    var reopenMainWindow: (() -> Void)?

    /**
     * 注册字体、应用激活策略和全局快捷键监听。
     */
    func applicationDidFinishLaunching(_ notification: Notification) {
        WeiBeiTypography.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        if shouldActivateOnLaunch {
            NSApp.activate(ignoringOtherApps: true)
        }
        if shouldActivateOnLaunch {
            shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                sharedWorkspaceStore.handleAppShortcut(event) ? nil : event
            }
        }
    }

    /**
     * 在 Dock 重新打开应用时恢复或新建主窗口。
     */
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = sender.windows.first(where: { $0.canBecomeKey }) {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            } else {
                reopenMainWindow?()
            }
        }
        if shouldActivateOnLaunch {
            NSApp.activate(ignoringOtherApps: true)
        }
        return false
    }

    /**
     * 退出前落盘工作区状态并关闭 Agent runtime。
     */
    func applicationWillTerminate(_ notification: Notification) {
        sharedWorkspaceStore.flushPendingNotePersistence()
        sharedWorkspaceStore.flushPendingWorkspaceSave()
        sharedWorkspaceStore.shutdownAgentRuntime()
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }

    /**
     * 应用失焦时提前落盘待保存内容。
     */
    func applicationDidResignActive(_ notification: Notification) {
        // Durability + less work at quit: flush pending note/workspace saves on focus loss.
        sharedWorkspaceStore.flushPendingNotePersistence()
        sharedWorkspaceStore.flushPendingWorkspaceSave()
    }

    private var shouldActivateOnLaunch: Bool {
        ProcessInfo.processInfo.environment["WEIBEI_SUPPRESS_ACTIVATION"] != "1"
    }
}

/**
 * 装配魏碑主窗口、设置窗口和应用级依赖。
 */
@main
struct WeiBeiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = sharedWorkspaceStore

    init() {
        if runsImportedIdentitySelfCheck {
            defer { try? FileManager.default.removeItem(at: importedIdentitySelfCheckBootstrapDirectory) }
            do {
                try ImportedIdentitySelfCheck.run()
                print("WeiBei imported identity self-checks passed")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("WeiBei imported identity self-check failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        WeiBeiTypography.registerBundledFonts()
    }

    /**
     * 装配应用的主窗口和设置窗口。
     */
    var body: some Scene {
        WindowGroup("魏碑", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(store.libraryDrawer)
                .environmentObject(store.threePaneReorder)
                .preferredColorScheme(store.appearanceMode.colorScheme)
                .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
                .background(WindowChromeConfigurator(appearanceMode: store.appearanceMode))
                .background(MainWindowReopenBridge(appDelegate: appDelegate))
                .onOpenURL { url in
                    store.importFiles([url])
                }
                .onAppear {
                    Task { await store.runVerificationScenarioIfNeeded() }
                }
                .frame(minWidth: 1120, minHeight: 720)
                .ignoresSafeArea(.container, edges: .top)
        }
        .defaultSize(width: 1240, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            WeiBeiCommands(store: store)
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

private struct MainWindowReopenBridge: View {
    @Environment(\.openWindow) private var openWindow
    weak var appDelegate: AppDelegate?

    /**
     * 把 SwiftUI 的 openWindow 动作桥接给 AppDelegate。
     */
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate?.reopenMainWindow = {
                    openWindow(id: "main")
                }
            }
    }
}

/**
 * 在明暗外观切换时提供短暂的纸面过渡。
 */
struct WeiBeiAppearanceTransition: ViewModifier {
    var mode: WeiBeiAppearanceMode
    @State private var washOpacity = 0.0
    @State private var washColor = Color.clear

    /**
     * 为目标内容应用明暗外观过渡遮罩。
     */
    func body(content: Content) -> some View {
        content
            .overlay {
                washColor
                    .opacity(washOpacity)
                    .allowsHitTesting(false)
            }
            .onChange(of: mode) { oldMode, _ in
                let crossesColorScheme = oldMode.isDark != mode.isDark
                guard crossesColorScheme else {
                    washOpacity = 0
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    washColor = Color(nsColor: oldMode.windowBackground)
                    washOpacity = 0.16
                }
                withAnimation(WeiBeiMotion.appearance) {
                    washOpacity = 0
                }
            }
    }
}

/**
 * 将 SwiftUI 主窗口配置为应用所需的无标题栏样式，并接入验证捕获服务。
 */
@MainActor
private struct WindowChromeConfigurator: NSViewRepresentable {
    var appearanceMode: WeiBeiAppearanceMode

    /**
     * 创建用于获取所属 NSWindow 的透明 AppKit 视图。
     */
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        if let window = view.window {
            configure(window)
        } else {
            DispatchQueue.main.async {
                configure(view.window)
            }
        }
        return view
    }

    /**
     * SwiftUI 状态变化时刷新窗口样式和验证配置。
     */
    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window {
            configure(window)
        } else {
            DispatchQueue.main.async {
                configure(view.window)
            }
        }
    }

    /**
     * 应用主窗口样式并连接验证捕获协调器。
     */
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = true
        window.backgroundColor = appearanceMode.windowBackground
        window.appearance = NSAppearance(named: appearanceMode.isDark ? .darkAqua : .aqua)
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = ProcessInfo.processInfo.environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1"
        VerificationCaptureCoordinator.shared.configure(window)
    }
}
