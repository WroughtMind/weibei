import AppKit
import SwiftUI
import WeiBeiCore

@MainActor private let sharedWorkspaceStore = WorkspaceStore()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shortcutMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            sharedWorkspaceStore.handleAppShortcut(event) ? nil : event
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }
}

@main
struct WeiBeiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = sharedWorkspaceStore

    var body: some Scene {
        WindowGroup("魏碑", id: "main") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(store.appearanceMode.colorScheme)
                .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
                .background(WindowChromeConfigurator(appearanceMode: store.appearanceMode))
                .onOpenURL { url in
                    store.importFiles([url])
                }
                .frame(minWidth: 1120, minHeight: 720)
                .ignoresSafeArea(.container, edges: .top)
        }
        .defaultSize(width: 1240, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("魏碑") {
                Button("打开资料") { store.importFilesFromPanel() }
                    .keyboardShortcut("o")

                Button("新建笔记") { animateLayout { store.resetNote() } }
                    .keyboardShortcut("n")

                Divider()

                Button("聚焦资料") { animateLayout { store.focus(.library) } }
                    .keyboardShortcut("1")
                Button("聚焦阅读") { animateLayout { store.focus(.reader) } }
                    .keyboardShortcut("2")
                Button("聚焦笔记") { animateLayout { store.focus(.notes) } }
                    .keyboardShortcut("3")
                Button("聚焦对话") { animateLayout { store.focus(.agent) } }
                    .keyboardShortcut("4")

                Divider()

                Button("上一份资料") { animateLayout { store.selectAdjacentItem(step: -1) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("下一份资料") { animateLayout { store.selectAdjacentItem(step: 1) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Divider()

                Button(store.showLibrary ? "收起资料库" : "打开资料库") {
                    animateLayout {
                        store.toggleLibrary()
                    }
                }
                    .keyboardShortcut("b")
                if store.layout.hasCollapsibleRightPane {
                    Button(store.showRightPane ? "收起辅助栏" : "展开辅助栏") {
                        animateLayout {
                            store.toggleRightPane()
                        }
                    }
                    .keyboardShortcut("j")
                }

                Divider()

                Button(WorkspaceLayout.documentAgentNotes.label) { setLayout(.documentAgentNotes) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button(WorkspaceLayout.documentNotesAgent.label) { setLayout(.documentNotesAgent) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button(WorkspaceLayout.documentNotesSplit.label) { setLayout(.documentNotesSplit) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("沉浸阅读") { setLayout(.immersiveReading) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button("沉浸对话") { setLayout(.immersiveConversation) }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                Button("沉浸写笔记") { setLayout(.immersiveWriting) }
                    .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button(store.appearanceMode.actionLabel) {
                    animatePanel {
                        store.toggleAppearanceMode()
                    }
                }
                    .keyboardShortcut("t", modifiers: [.command, .option])

                Divider()

                Button(AgentSurface.bottomDrawer.actionLabel) { setAgentSurface(.bottomDrawer) }
                    .keyboardShortcut("1", modifiers: [.control, .option])
                Button(AgentSurface.cornerPanel.actionLabel) { setAgentSurface(.cornerPanel) }
                    .keyboardShortcut("2", modifiers: [.control, .option])
                if store.canUseSelectionAgentSurface {
                    Button(AgentSurface.selectionFloat.actionLabel) { setAgentSurface(.selectionFloat) }
                        .keyboardShortcut("3", modifiers: [.control, .option])
                }
                Button(AgentSurface.quietInsight.actionLabel) { setAgentSurface(.quietInsight) }
                    .keyboardShortcut("4", modifiers: [.control, .option])
                Button(AgentSurface.hidden.actionLabel) { setAgentSurface(.hidden) }
                    .keyboardShortcut("0", modifiers: [.control, .option])

                Divider()

                Button("笔记原地写作") { setNoteRenderMode(.rich) }
                    .keyboardShortcut("1", modifiers: [.control, .command])
                Button("笔记源码对照") { setNoteRenderMode(.split) }
                    .keyboardShortcut("2", modifiers: [.control, .command])
                Button("笔记源码") { setNoteRenderMode(.source) }
                    .keyboardShortcut("3", modifiers: [.control, .command])
                Button("笔记预览") { setNoteRenderMode(.preview) }
                    .keyboardShortcut("4", modifiers: [.control, .command])

                if store.canApplyAgentAnswer {
                    Divider()

                    Button("写入回答到笔记") { animatePanel { store.applyLastAgentAnswerToNote() } }
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                    if store.canReplaceNoteSelection {
                        Button("替换笔记选区") { animatePanel { store.replaceSelectionWithLastAgentAnswer() } }
                            .keyboardShortcut("r", modifiers: [.command, .shift])
                    }
                    Button("追加整理建议") { animatePanel { store.applyAgentPatchToEditor() } }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                }

                Divider()

                Button("命令面板") {
                    animatePanel {
                        store.commandPalettePresented.toggle()
                    }
                }
                    .keyboardShortcut("k")

                Divider()

                if store.canCopyReference {
                    Button(store.copyReferenceActionTitle) { store.copyCurrentReference() }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                if store.hasSelectedMaterial {
                    Button("打开资料内搜索") {
                        animatePanel {
                            store.revealReaderSearch()
                        }
                    }
                    .keyboardShortcut("f")
                }
                if !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(store.sendAgentActionTitle) { Task { await store.askAgent() } }
                        .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
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

    private func setNoteRenderMode(_ mode: NoteRenderMode) {
        animatePanel {
            store.setNoteRenderMode(mode)
        }
    }
}

private struct WeiBeiAppearanceTransition: ViewModifier {
    var mode: WeiBeiAppearanceMode
    @State private var washOpacity = 0.0
    @State private var washColor = Color.clear

    func body(content: Content) -> some View {
        content
            .animation(WeiBeiMotion.appearance, value: mode)
            .overlay {
                washColor
                    .opacity(washOpacity)
                    .allowsHitTesting(false)
            }
            .onChange(of: mode) { oldMode, _ in
                washColor = Color(nsColor: oldMode.windowBackground)
                washOpacity = 0.36
                withAnimation(WeiBeiMotion.appearance) {
                    washOpacity = 0
                }
            }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    var appearanceMode: WeiBeiAppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(view.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = true
        window.backgroundColor = appearanceMode.windowBackground
        window.isMovableByWindowBackground = true
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("界面")

                HStack(spacing: 8) {
                    ForEach(WeiBeiAppearanceMode.allCases) { mode in
                        Button(mode.label) {
                            withAnimation(WeiBeiMotion.panel) {
                                store.setAppearanceMode(mode)
                            }
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: store.appearanceMode == mode))
                    }
                }

                Text("墨石模式使用深色砚台底、纸白正文、砚金链接和克制朱砂选区。")
                    .font(.footnote)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("对话设置")

                SecureField(
                    "",
                    text: $store.openAIAPIKey,
                    prompt: Text("OpenAI 密钥")
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                    .textFieldStyle(.plain)
                    .foregroundColor(WeiBeiTheme.ink)
                    .focused($focusedField, equals: .apiKey)
                .font(.system(size: 13))
                .weibeiInputSurface(active: focusedField == .apiKey)

                HStack(spacing: 8) {
                    Button("保存到钥匙串") { store.saveOpenAIAPIKey() }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    Button("清除") { store.clearOpenAIAPIKey() }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                }

                if let status = store.openAIKeyStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                }

                Text(store.openAIKeyHelpText)
                    .font(.footnote)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("模型")

                TextField(
                    "",
                    text: Binding(
                        get: { store.modelName },
                        set: { store.updateModelName($0) }
                    ),
                    prompt: Text("模型")
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                )
                .textFieldStyle(.plain)
                .foregroundColor(WeiBeiTheme.ink)
                .focused($focusedField, equals: .model)
                .font(.system(size: 13))
                .weibeiInputSurface(active: focusedField == .model)

                Text("本机环境变量 WEIBEI_OPENAI_MODEL 会覆盖这里的模型。")
                    .font(.footnote)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .preferredColorScheme(store.appearanceMode.colorScheme)
    }

    private enum Field: Hashable {
        case apiKey
        case model
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .serif))
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
    }
}
