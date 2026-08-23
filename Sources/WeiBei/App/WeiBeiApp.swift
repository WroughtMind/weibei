import AppKit
import SwiftUI
import WeiBeiCore

@MainActor private let sharedWorkspaceStore: WorkspaceStore = {
    WeiBeiPerf.beginLaunch()
    return WorkspaceStore()
}()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shortcutMonitor: Any?
    private var resignFlushTask: Task<Void, Never>?
    private var terminationSaveInFlight = false
    private var terminationApproved = false
    var reopenMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        WeiBeiTypography.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            sharedWorkspaceStore.handleAppShortcut(event) ? nil : event
        }
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
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
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
        .defaultSize(width: 1240, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
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
                    .weiBeiKeyboardShortcut(store.chord(for: .focusLibrary))
                Button(store.ui("聚焦阅读", "Focus Reader")) { animateLayout { store.focus(.reader) } }
                    .weiBeiKeyboardShortcut(store.chord(for: .focusReader))
                Button(store.ui("聚焦笔记", "Focus Notes")) { animateLayout { store.focus(.notes) } }
                    .weiBeiKeyboardShortcut(store.chord(for: .focusNotes))
                Button(store.ui("聚焦对话", "Focus Chat")) { animateLayout { store.focus(.agent) } }
                    .weiBeiKeyboardShortcut(store.chord(for: .focusChat))

                Divider()

                Button(store.ui("上一份资料", "Previous Material")) { animateLayout { store.selectAdjacentItem(step: -1) } }
                    .weiBeiKeyboardShortcut(store.chord(for: .previousMaterial))
                Button(store.ui("下一份资料", "Next Material")) { animateLayout { store.selectAdjacentItem(step: 1) } }
                    .weiBeiKeyboardShortcut(store.chord(for: .nextMaterial))

                Divider()

                Button(store.showLibrary ? store.ui("收起课程目录", "Hide Course Index") : store.ui("打开课程目录", "Show Course Index")) {
                    store.toggleLibrary()
                }
                    .weiBeiKeyboardShortcut(store.chord(for: .courseIndex))
                if store.layout.hasCollapsibleRightPane {
                    Button(store.showRightPane ? store.ui("收起辅助栏", "Hide Assistant Pane") : store.ui("展开辅助栏", "Show Assistant Pane")) {
                        animateLayout {
                            store.toggleRightPane()
                        }
                    }
                    .weiBeiKeyboardShortcut(store.chord(for: .toggleRightPane))
                }

                Divider()

                Button(store.ui("三栏工作台", "Three-Pane Workspace")) { setLayout(.documentAgentNotes) }
                    .weiBeiKeyboardShortcut(store.chord(for: .threePaneWorkspace))
                if store.layout.isDocumentThreePane {
                    Button(store.ui("交换笔记与对话", "Swap Notes and Chat")) {
                        animateLayout {
                            store.swapThreePaneSecondaryPanes()
                        }
                    }
                    .weiBeiKeyboardShortcut(store.chord(for: .swapThreePaneSecondaryPanes))
                }
                Button(WorkspaceLayout.immersiveReading.label(language: store.interfaceLanguage)) { setLayout(.immersiveReading) }
                    .weiBeiKeyboardShortcut(store.chord(for: .immersiveReading))
                Button(WorkspaceLayout.immersiveConversation.label(language: store.interfaceLanguage)) { setLayout(.immersiveConversation) }
                    .weiBeiKeyboardShortcut(store.chord(for: .immersiveChat))
                Button(WorkspaceLayout.immersiveWriting.label(language: store.interfaceLanguage)) { setLayout(.immersiveWriting) }
                    .weiBeiKeyboardShortcut(store.chord(for: .immersiveWriting))

                Divider()

                Button(store.appearanceMode.actionLabel(language: store.interfaceLanguage)) {
                    animateAppearance {
                        store.toggleAppearanceMode()
                    }
                }
                    .weiBeiKeyboardShortcut(store.chord(for: .toggleAppearance))

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
                        .weiBeiKeyboardShortcut(store.chord(for: .selectionPrompt))
                }
                Button(AgentSurface.hidden.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.hidden) }
                    .weiBeiKeyboardShortcut(store.chord(for: .hideChatOverlay))

                if store.canApplyAgentAnswer {
                    Divider()

                    Button(store.ui("写入回答到笔记", "Write Answer to Note")) { animatePanel { store.applyLastAgentAnswerToNote() } }
                        .weiBeiKeyboardShortcut(store.chord(for: .applyAgentAnswerToNote))
                    if store.canReplaceNoteSelection {
                        Button(store.ui("替换笔记选区", "Replace Note Selection")) { animatePanel { store.replaceSelectionWithLastAgentAnswer() } }
                            .weiBeiKeyboardShortcut(store.chord(for: .replaceNoteSelection))
                    }
                    Button(store.ui("追加整理建议", "Append Organization Suggestion")) { animatePanel { store.applyAgentPatchToEditor() } }
                        .weiBeiKeyboardShortcut(store.chord(for: .applyAgentPatchToEditor))
                }

                Divider()

                Button(store.ui("命令面板", "Command Palette")) {
                    store.commandPalettePresented.toggle()
                }
                    .weiBeiKeyboardShortcut(store.chord(for: .commandPalette))

                Divider()

                if store.canCopyReference {
                    Button(store.copyReferenceActionTitle) { store.copyCurrentReference() }
                        .weiBeiKeyboardShortcut(store.chord(for: .copyCurrentReference))
                }
                if store.hasSelectedMaterial {
                    Button(store.ui("打开资料内搜索", "Search in Material")) {
                        animatePanel {
                            store.revealReaderSearch()
                        }
                    }
                    .weiBeiKeyboardShortcut(store.chord(for: .searchInMaterial))
                }
                if store.isAgentRunningInActiveChat || !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(store.sendAgentActionTitle) {
                        store.submitAgentDraft()
                    }
                        .weiBeiKeyboardShortcut(store.chord(for: .submitAgentDraft))
                }
            }
        }

        Settings {
            SettingsView()
                .weiBeiMotionScoped()
                .environmentObject(store)
                .environmentObject(updateService)
        }
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

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window {
            configure(window)
        } else {
            DispatchQueue.main.async {
                configure(view.window)
            }
        }
    }

    private func configure(_ window: NSWindow?) {
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
        window.appearance = NSAppearance(
            named: appearanceMode.isDark ? .darkAqua : .aqua
        )
        window.contentView?.wantsLayer = appearanceMode.isGlass
        window.contentView?.layer?.backgroundColor = appearanceMode.isGlass ? NSColor.clear.cgColor : nil
        window.isMovableByWindowBackground = true
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

extension View {
    func weiBeiKeyboardShortcut(_ chord: AppShortcutChord) -> some View {
        keyboardShortcut(chord.swiftUIKeyEquivalent, modifiers: chord.swiftUIModifiers)
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
