import AppKit
import SwiftUI
import WeiBeiCore

@MainActor private let sharedWorkspaceStore: WorkspaceStore = {
    WeiBeiPerf.beginLaunch()
    return WorkspaceStore()
}()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var resignFlushTask: Task<Void, Never>?
    private var terminationSaveInFlight = false
    private var terminationApproved = false
    var reopenMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        WeiBeiTypography.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = sender.windows.first(where: { $0.canBecomeKey }) {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            } else {
                reopenMainWindow?()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await sharedWorkspaceStore.reconcileActiveNoteEditorWithBackingFile()
        }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        if terminationApproved {
            return .terminateNow
        }
        guard !terminationSaveInFlight else {
            return .terminateLater
        }
        terminationSaveInFlight = true
        resignFlushTask?.cancel()
        resignFlushTask = nil
        Task { @MainActor [weak self] in
            guard await sharedWorkspaceStore.freshActiveNoteEditorSnapshot() else {
                self?.terminationSaveInFlight = false
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            sharedWorkspaceStore.cancelAgentRequest(restoreDraft: false)
            sharedWorkspaceStore.flushPendingNotePersistence(flushWorkspace: false)
            let saved = await sharedWorkspaceStore.flushPendingWorkspaceSaveAsync()
            guard let self else {
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            self.terminationSaveInFlight = false
            self.terminationApproved = saved
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        sharedWorkspaceStore.cancelAgentRequest(restoreDraft: false)
        if !terminationApproved {
            _ = sharedWorkspaceStore.flushPendingWorkspaceSave()
        }
        sharedWorkspaceStore.shutdownAgentRuntime()
        resignFlushTask?.cancel()
        resignFlushTask = nil
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard !terminationSaveInFlight else { return }
        resignFlushTask?.cancel()
        resignFlushTask = Task { @MainActor in
            guard await sharedWorkspaceStore.freshActiveNoteEditorSnapshot(),
                  !Task.isCancelled else { return }
            sharedWorkspaceStore.flushPendingNotePersistence(flushWorkspace: false)
            _ = await sharedWorkspaceStore.flushPendingWorkspaceSaveAsync()
        }
    }

}

extension Notification.Name {
    /// 菜单 ⌘, → 主窗口里的 openWindow 桥(Commands 拿不到环境 action)。
    static let weibeiOpenSettings = Notification.Name("WeiBeiOpenSettings")
}

@main
struct WeiBeiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = sharedWorkspaceStore
    @StateObject private var updateService = WeiBeiUpdateService()

    init() {
        WeiBeiTypography.registerBundledFonts()
        WorkspaceStore.loadPersistedGlassIntensity()
    }

    var body: some Scene {
        WindowGroup("魏碑", id: "main") {
            // TEMPORARY: streaming-completion probe harness (WEIBEI_STREAM_PROBE_SCENARIO).
            if ProcessInfo.processInfo.environment["WEIBEI_STREAM_PROBE_SCENARIO"] != nil {
                StreamFinalizeHarnessView()
            } else {
            ContentView()
                .environmentObject(store)
                .environmentObject(updateService)
                .environmentObject(store.libraryDrawer)
                .environmentObject(store.threePaneReorder)
                .environmentObject(store.paneState)
                .environmentObject(store.interaction)
                .preferredColorScheme(store.appearanceMode.colorScheme)
                .environment(\.weiBeiTextScale, store.interfaceTextScale.multiplier)
                .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
                .background(WindowChromeConfigurator(appearanceMode: store.appearanceMode))
                .background(MainWindowReopenBridge(appDelegate: appDelegate))
                .modifier(SystemAppearanceObserver(store: store))
                .onOpenURL { url in
                    store.importFiles([url])
                }
                // 自适应窗口：统一 520 起——必须小于半个屏宽，macOS 才会在
                // 拖近屏幕边缘时给出贴边分屏吸附区；窄窗下窗格收 28pt 细轨。
                .frame(minWidth: 520, minHeight: 720)
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .defaultSize(width: 1240, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(store.ui("设置…", "Settings…")) {
                    NotificationCenter.default.post(name: .weibeiOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu(store.appDisplayName) {
                Button(store.ui("打开课程空间", "Open Course Space")) { store.presentCourseWorkspace(.hub) }
                    .keyboardShortcut("0")

                Divider()

                Button(store.ui("打开资料", "Open Material")) { store.importFilesFromPanel() }
                    .keyboardShortcut("o")

                Button(store.ui("新建空白笔记", "New Blank Note")) { animateLayout { store.promptCreateBlankNotebookNote() } }
                    .keyboardShortcut("n")
                if store.hasSelectedMaterial {
                    Button(store.ui("从当前资料开笔记", "Note from Current Material")) {
                        animateLayout { store.promptCreateNotebookNoteFromCurrentMaterial() }
                    }
                }

                Divider()

                Button(store.ui("聚焦课程目录", "Focus Course Index")) { animateLayout { store.focus(.library) } }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .focusLibrary))
                Button(store.ui("聚焦阅读", "Focus Reader")) { animateLayout { store.focus(.reader) } }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .focusReader))
                Button(store.ui("聚焦笔记", "Focus Notes")) { animateLayout { store.focus(.notes) } }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .focusNotes))
                Button(store.ui("聚焦对话", "Focus Chat")) { animateLayout { store.focus(.agent) } }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .focusChat))

                Divider()

                Button(store.ui("上一份资料", "Previous Material")) { animateLayout { store.selectAdjacentItem(step: -1) } }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .previousMaterial))
                Button(store.ui("下一份资料", "Next Material")) { animateLayout { store.selectAdjacentItem(step: 1) } }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .nextMaterial))

                Divider()

                Button(store.showLibrary ? store.ui("收起课程目录", "Hide Course Index") : store.ui("打开课程目录", "Show Course Index")) {
                    store.toggleLibrary()
                }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .courseIndex))
                if store.layout.hasCollapsibleRightPane {
                    Button(store.showRightPane ? store.ui("收起辅助栏", "Hide Assistant Pane") : store.ui("展开辅助栏", "Show Assistant Pane")) {
                        animateLayout {
                            store.toggleRightPane()
                        }
                    }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .toggleRightPane))
                }

                Divider()

                Button(store.ui("三栏工作台", "Three-Pane Workspace")) { setLayout(.documentAgentNotes) }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .threePaneWorkspace))
                if store.layout.isDocumentThreePane {
                    Button(store.ui("交换笔记与对话", "Swap Notes and Chat")) {
                        animateLayout {
                            store.swapThreePaneSecondaryPanes()
                        }
                    }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .swapThreePaneSecondaryPanes))
                }
                Button(WorkspaceLayout.immersiveReading.label(language: store.interfaceLanguage)) { setLayout(.immersiveReading) }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .immersiveReading))
                Button(WorkspaceLayout.immersiveConversation.label(language: store.interfaceLanguage)) { setLayout(.immersiveConversation) }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .immersiveChat))
                Button(WorkspaceLayout.immersiveWriting.label(language: store.interfaceLanguage)) { setLayout(.immersiveWriting) }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .immersiveWriting))

                Divider()

                Button(store.appearanceMode.actionLabel(language: store.interfaceLanguage)) {
                    animateAppearance {
                        store.toggleAppearanceMode()
                    }
                }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .toggleAppearance))

                Button(store.ui("放大文字", "Zoom Text In")) {
                    if let larger = store.interfaceTextScale.nextLarger {
                        store.setInterfaceTextScale(larger)
                    }
                }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(store.interfaceTextScale.nextLarger == nil)
                Button(store.ui("缩小文字", "Zoom Text Out")) {
                    if let smaller = store.interfaceTextScale.nextSmaller {
                        store.setInterfaceTextScale(smaller)
                    }
                }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(store.interfaceTextScale.nextSmaller == nil)
                Button(store.ui("重置文字大小", "Reset Text Size")) {
                    store.setInterfaceTextScale(.standard)
                }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                    .disabled(store.interfaceTextScale == .standard)

                Divider()

                if store.canUseSelectionAgentSurface {
                    Button(AgentSurface.selectionFloat.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.selectionFloat) }
                        .weiBeiKeyboardShortcut(store.executableChord(for: .selectionPrompt))
                }
                Button(AgentSurface.hidden.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.hidden) }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .hideChatOverlay))

                if store.canApplyAgentAnswer {
                    Divider()

                    Button(store.ui("写入回答到笔记", "Write Answer to Note")) { animatePanel { store.applyLastAgentAnswerToNote() } }
                        .weiBeiKeyboardShortcut(store.executableChord(for: .applyAgentAnswerToNote))
                    if store.canReplaceNoteSelection {
                        Button(store.ui("替换笔记选区", "Replace Note Selection")) { animatePanel { store.replaceSelectionWithLastAgentAnswer() } }
                            .weiBeiKeyboardShortcut(store.executableChord(for: .replaceNoteSelection))
                    }
                    Button(store.ui("追加整理建议", "Append Organization Suggestion")) { animatePanel { store.applyAgentPatchToEditor() } }
                        .weiBeiKeyboardShortcut(store.executableChord(for: .applyAgentPatchToEditor))
                }

                Divider()

                Button(store.ui("命令面板", "Command Palette")) {
                    store.commandPalettePresented.toggle()
                }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .commandPalette))

                Divider()

                if store.canCopyReference {
                    Button(store.copyReferenceActionTitle) { store.copyCurrentReference() }
                        .weiBeiKeyboardShortcut(store.executableChord(for: .copyCurrentReference))
                }
                if store.hasSelectedMaterial {
                    Button(store.ui("打开资料内搜索", "Search in Material")) {
                        animatePanel {
                            store.revealReaderSearch()
                        }
                    }
                    .weiBeiKeyboardShortcut(store.executableChord(for: .searchInMaterial))
                }
                if store.isAgentRunningInActiveChat || !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(store.sendAgentActionTitle) {
                        store.submitAgentDraft()
                    }
                        .weiBeiKeyboardShortcut(store.executableChord(for: .submitAgentDraft))
                }
            }
        }

        // Settings scene cannot take .windowStyle(.hiddenTitleBar) and reasserts
        // its own titlebar chrome — a plain WindowGroup shares the main window's
        // borderless glass look instead.
        WindowGroup("设置", id: "weibei-settings") {
            SettingsView()
                .weiBeiMotionScoped()
                .environmentObject(store)
                .environmentObject(updateService)
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }

    private func animateLayout(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.layout) {
            action()
        }
    }

    private func animatePanel(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.panel) {
            action()
        }
    }

    private func animateAppearance(_ action: () -> Void) {
        // Theme animation is owned by WorkspaceStore.setAppearanceMode.
        action()
    }

    private func setLayout(_ layout: WorkspaceLayout) {
        animateLayout {
            store.setLayout(layout)
        }
    }

    private func setAgentSurface(_ surface: AgentSurface) {
        animatePanel {
            store.setAgentSurface(surface)
        }
    }
}

extension View {
    @ViewBuilder
    func weiBeiKeyboardShortcut(_ chord: AppShortcutChord?) -> some View {
        if let chord {
            keyboardShortcut(chord.swiftUIKeyEquivalent, modifiers: chord.swiftUIModifiers)
        } else {
            self
        }
    }
}

private extension AppShortcutChord {
    var swiftUIKeyEquivalent: KeyEquivalent {
        switch key {
        case "return": .return
        case "up": .upArrow
        case "down": .downArrow
        case "left": .leftArrow
        case "right": .rightArrow
        default: KeyEquivalent(Character(key))
        }
    }

    var swiftUIModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }
}

private struct MainWindowReopenBridge: View {
    @Environment(\.openWindow) private var openWindow
    weak var appDelegate: AppDelegate?

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

// Internal (not private) so SettingsView.swift — now in its own file — can apply
// this modifier. Was `private` when SettingsView lived in this same file (L1).
struct WeiBeiAppearanceTransition: ViewModifier {
    var mode: WeiBeiAppearanceMode
    @State private var washOpacity = 0.0
    @State private var washColor = Color.clear

    func body(content: Content) -> some View {
        // No nested `.animation(value: mode)` here — ContentView / Settings already
        // animate once at the root. A second animation made chrome lag the paper.
        content
            .overlay {
                washColor
                    .opacity(washOpacity)
                    .allowsHitTesting(false)
            }
            .onChange(of: mode) { oldMode, _ in
                // Brief wash only when light↔dark family flips; same-family (纸面↔宣纸)
                // must feel instant without a laggy overlay.
                let crossFamily = oldMode.isDark != mode.isDark
                guard crossFamily else {
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

@MainActor
private struct WindowChromeConfigurator: NSViewRepresentable {
    var appearanceMode: WeiBeiAppearanceMode

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        configureWhenWindowIsReady(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.attach(to: view)
        configureWhenWindowIsReady(view)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    private func configureWhenWindowIsReady(_ view: NSView) {
        if let window = view.window {
            Self.configure(window, appearanceMode: appearanceMode)
        } else {
            let mode = appearanceMode
            DispatchQueue.main.async {
                Self.configure(view.window, appearanceMode: mode)
            }
        }
    }

    private static func configure(_ window: NSWindow?, appearanceMode: WeiBeiAppearanceMode) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = !appearanceMode.isGlass
        window.backgroundColor = appearanceMode.isGlass
            ? .clear
            : appearanceMode.windowBackground
        // Flip through nil on light↔dark — assigning a same-name appearance
        // directly leaves system titlebar material stuck on the old tint.
        let targetName: NSAppearance.Name = appearanceMode.isDark ? .darkAqua : .aqua
        if window.appearance?.name != targetName {
            window.appearance = nil
            window.appearance = NSAppearance(named: targetName)
        }
        window.contentView?.wantsLayer = appearanceMode.isGlass
        window.contentView?.layer?.backgroundColor = appearanceMode.isGlass ? NSColor.clear.cgColor : nil
        window.isMovableByWindowBackground = true
    }

    @MainActor
    final class Coordinator {
        private weak var view: NSView?
        private var themeObserver: NSObjectProtocol?

        func attach(to view: NSView) {
            self.view = view
            guard themeObserver == nil else { return }
            themeObserver = NotificationCenter.default.addObserver(
                forName: WeiBeiThemeRuntime.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let mode = notification.object as? WeiBeiAppearanceMode else { return }
                Task { @MainActor [weak self] in
                    WindowChromeConfigurator.configure(
                        self?.view?.window,
                        appearanceMode: mode
                    )
                }
            }
        }

        func stopObserving() {
            if let themeObserver {
                NotificationCenter.default.removeObserver(themeObserver)
            }
            themeObserver = nil
            view = nil
        }
    }
}

/// 跟随系统：启动时与系统深浅切换时，把主题换到同对伙伴（仅当偏好为“跟随系统”）。
private struct SystemAppearanceObserver: ViewModifier {
    @ObservedObject var store: WorkspaceStore
    @State private var distributedObserver: NSObjectProtocol?

    func body(content: Content) -> some View {
        content.onAppear {
            store.refreshAppearanceForSystemChange()
            guard distributedObserver == nil else { return }
            distributedObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { [weak store] _ in
                Task { @MainActor in
                    store?.refreshAppearanceForSystemChange()
                }
            }
        }
    }
}
