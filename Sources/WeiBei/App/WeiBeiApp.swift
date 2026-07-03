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
        return flag
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
                .background(WindowChromeConfigurator())
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
                Button("聚焦 Agent") { animateLayout { store.focus(.agent) } }
                    .keyboardShortcut("4")

                Divider()

                Button("上一份资料") { animateLayout { store.selectAdjacentItem(step: -1) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("下一份资料") { animateLayout { store.selectAdjacentItem(step: 1) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Divider()

                Button(store.showLibrary ? "收起资料" : "恢复资料") {
                    animateLayout {
                        store.toggleLibrary()
                    }
                }
                    .keyboardShortcut("b")
                Button(store.showRightPane ? "收起辅助栏" : "展开辅助栏") {
                    animateLayout {
                        store.toggleRightPane()
                    }
                }
                    .keyboardShortcut("j")
                    .disabled(!store.layout.hasCollapsibleRightPane)

                Divider()

                Button("文档 Agent 笔记") { setLayout(.documentAgentNotes) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("文档 笔记 Agent") { setLayout(.documentNotesAgent) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("文档笔记对半") { setLayout(.documentNotesSplit) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("沉浸阅读") { setLayout(.immersiveReading) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button("沉浸对话") { setLayout(.immersiveConversation) }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                Button("沉浸写笔记") { setLayout(.immersiveWriting) }
                    .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button("Agent 底部抽屉") { setAgentSurface(.bottomDrawer) }
                    .keyboardShortcut("1", modifiers: [.control, .option])
                Button("Agent 右下角小窗") { setAgentSurface(.cornerPanel) }
                    .keyboardShortcut("2", modifiers: [.control, .option])
                Button("Agent 划线浮层") { setAgentSurface(.selectionFloat) }
                    .keyboardShortcut("3", modifiers: [.control, .option])
                Button("Agent 静默洞察") { setAgentSurface(.quietInsight) }
                    .keyboardShortcut("4", modifiers: [.control, .option])
                Button("隐藏 Agent") { setAgentSurface(.hidden) }
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

                Divider()

                Button("应用 Agent 到笔记") { animatePanel { store.applyLastAgentAnswerToNote() } }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!store.canApplyAgentAnswer)
                Button("用 Agent 替换笔记选区") { animatePanel { store.replaceSelectionWithLastAgentAnswer() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!store.canReplaceNoteSelection)
                Button("追加 Agent 整理建议") { animatePanel { store.applyAgentPatchToEditor() } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!store.canApplyAgentAnswer)

                Divider()

                Button("命令面板") {
                    animatePanel {
                        store.commandPalettePresented.toggle()
                    }
                }
                    .keyboardShortcut("k")

                Divider()

                if store.hasSelectedMaterial || store.selectionContext != nil {
                    Button("复制引用") { store.copyCurrentReference() }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                if store.hasSelectedMaterial {
                    Button("搜索当前资料") {
                        animatePanel {
                            store.revealReaderSearch()
                        }
                    }
                    .keyboardShortcut("f")
                }
                Button(store.hasSelectedMaterial ? "问当前材料" : "问当前笔记") { Task { await store.askAgent() } }
                    .keyboardShortcut(.return, modifiers: [.command])
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

private struct WindowChromeConfigurator: NSViewRepresentable {
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
        window.backgroundColor = NSColor(
            calibratedRed: 0.985,
            green: 0.960,
            blue: 0.905,
            alpha: 1.0
        )
        window.isMovableByWindowBackground = true
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Agent")

                ZStack(alignment: .leading) {
                    SecureField("", text: $store.openAIAPIKey)
                        .textFieldStyle(.plain)
                        .foregroundColor(WeiBeiTheme.ink)
                        .focused($focusedField, equals: .apiKey)

                    if store.openAIAPIKey.isEmpty {
                        WeiBeiInputPrompt("OpenAI 密钥")
                    }
                }
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

                ZStack(alignment: .leading) {
                    TextField(
                        "",
                        text: Binding(
                            get: { store.modelName },
                            set: { store.updateModelName($0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .foregroundColor(WeiBeiTheme.ink)
                    .focused($focusedField, equals: .model)

                    if store.modelName.isEmpty {
                        WeiBeiInputPrompt("模型")
                    }
                }
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
        .environment(\.colorScheme, .light)
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
