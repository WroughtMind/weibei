import AppKit
import SwiftUI
import WeiBeiCore

struct CommandPaletteView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private var commands: [PaletteCommand] {
        var items = [
            PaletteCommand(title: "打开资料", shortcut: "⌘O") { store.importFilesFromPanel() },
            PaletteCommand(title: "新建笔记", shortcut: "⌘N") { store.resetNote() },
            PaletteCommand(title: "聚焦资料", shortcut: "⌘1", animation: WeiBeiMotion.layout) { store.focus(.library) },
            PaletteCommand(title: "聚焦阅读", shortcut: "⌘2", animation: WeiBeiMotion.layout) { store.focus(.reader) },
            PaletteCommand(title: "聚焦笔记", shortcut: "⌘3", animation: WeiBeiMotion.layout) { store.focus(.notes) },
            PaletteCommand(title: "聚焦 Agent", shortcut: "⌘4", animation: WeiBeiMotion.layout) { store.focus(.agent) },
            PaletteCommand(title: "上一份资料", shortcut: "⌥⌘↑", animation: WeiBeiMotion.layout) { store.selectAdjacentItem(step: -1) },
            PaletteCommand(title: "下一份资料", shortcut: "⌥⌘↓", animation: WeiBeiMotion.layout) { store.selectAdjacentItem(step: 1) },
            PaletteCommand(title: store.showLibrary ? "收起资料库" : "打开资料库", shortcut: "⌘B", animation: WeiBeiMotion.layout) { store.toggleLibrary() },
            PaletteCommand(title: "文档 Agent 笔记", shortcut: "⌥⌘1", animation: WeiBeiMotion.layout) { store.setLayout(.documentAgentNotes) },
            PaletteCommand(title: "文档 笔记 Agent", shortcut: "⌥⌘2", animation: WeiBeiMotion.layout) { store.setLayout(.documentNotesAgent) },
            PaletteCommand(title: "文档笔记对半", shortcut: "⌥⌘3", animation: WeiBeiMotion.layout) { store.setLayout(.documentNotesSplit) },
            PaletteCommand(title: "沉浸阅读", shortcut: "⌥⌘R", animation: WeiBeiMotion.layout) { store.setLayout(.immersiveReading) },
            PaletteCommand(title: "沉浸对话", shortcut: "⌥⌘A", animation: WeiBeiMotion.layout) { store.setLayout(.immersiveConversation) },
            PaletteCommand(title: "沉浸写笔记", shortcut: "⌥⌘N", animation: WeiBeiMotion.layout) { store.setLayout(.immersiveWriting) },
            PaletteCommand(title: "Agent 底部抽屉", shortcut: "⌃⌥1") { store.setAgentSurface(.bottomDrawer) },
            PaletteCommand(title: "Agent 右下角小窗", shortcut: "⌃⌥2") { store.setAgentSurface(.cornerPanel) },
            PaletteCommand(title: "Agent 划线浮层", shortcut: "⌃⌥3") { store.setAgentSurface(.selectionFloat) },
            PaletteCommand(title: "Agent 静默洞察", shortcut: "⌃⌥4") { store.setAgentSurface(.quietInsight) },
            PaletteCommand(title: "笔记原地写作", shortcut: "⌃⌘1") { store.setNoteRenderMode(.rich) },
            PaletteCommand(title: "笔记源码对照", shortcut: "⌃⌘2") { store.setNoteRenderMode(.split) },
            PaletteCommand(title: "笔记源码", shortcut: "⌃⌘3") { store.setNoteRenderMode(.source) },
            PaletteCommand(title: "笔记预览", shortcut: "⌃⌘4") { store.setNoteRenderMode(.preview) },
            markdownInsertCommand(title: "插入行内公式", markdown: "${{WEIBEI_SELECT_START}}x_i = \\frac{a}{b}{{WEIBEI_SELECT_END}}$"),
            markdownInsertCommand(title: "插入块级公式", markdown: "\n$$\n{{WEIBEI_SELECT_START}}E = mc^2{{WEIBEI_SELECT_END}}\n$$\n"),
            markdownInsertCommand(title: "插入矩阵公式", markdown: "\n$$\n\\begin{bmatrix}\n{{WEIBEI_SELECT_START}}a{{WEIBEI_SELECT_END}} & b \\\\\nc & d\n\\end{bmatrix}\n$$\n"),
            markdownInsertCommand(title: "插入 Callout", markdown: "\n> [!note] 标题\n> {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}}\n"),
            markdownInsertCommand(title: "插入表格", markdown: "\n| A | B |\n| --- | --- |\n| {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}} |  |\n"),
            markdownInsertCommand(title: "插入 Mermaid", markdown: "\n```mermaid\ngraph TD\n  {{WEIBEI_SELECT_START}}A[开始] --> B[整理]{{WEIBEI_SELECT_END}}\n```\n")
        ]
        if store.canUseSelectedMarkdownAsNotebookNote {
            items.insert(
                PaletteCommand(title: "作为笔记编辑当前 Markdown", shortcut: "") { store.useSelectedMarkdownAsNotebookNote() },
                at: 2
            )
        }
        if let rightPaneCommand {
            items.insert(rightPaneCommand, at: 9)
        }
        if store.hasSelectedMaterial {
            items.append(PaletteCommand(title: "复制引用", shortcut: "⌘⇧C") { store.copyCurrentReference() })
            items.append(PaletteCommand(title: "搜索当前资料", shortcut: "⌘F") { store.revealReaderSearch() })
        } else if store.selectionContext != nil {
            items.append(PaletteCommand(title: "复制引用", shortcut: "⌘⇧C") { store.copyCurrentReference() })
        }
        if store.selectionContext != nil {
            items.append(PaletteCommand(title: "问选区 Agent", shortcut: "") { store.askSelection() })
        }
        if store.canOpenSelectedSourceReference {
            items.append(PaletteCommand(title: "打开选区来源", shortcut: "") { store.openSelectedSourceReference() })
        }
        if store.agentSurface != .hidden {
            items.append(PaletteCommand(title: "隐藏 Agent", shortcut: "⌃⌥0") { store.setAgentSurface(.hidden) })
        }
        if store.canApplyAgentAnswer {
            items.append(PaletteCommand(title: "写入 Agent 回答", shortcut: "⌘⇧A") { store.applyLastAgentAnswerToNote() })
            items.append(PaletteCommand(title: "追加 Agent 整理建议", shortcut: "⌘⇧E") { store.applyAgentPatchToEditor() })
        }
        if store.canReplaceNoteSelection {
            items.append(PaletteCommand(title: "替换笔记选区", shortcut: "⌘⇧R") { store.replaceSelectionWithLastAgentAnswer() })
        }
        if canSendAgentDraft {
            items.append(PaletteCommand(title: "发送 Agent 问题", shortcut: "⌘↩") { Task { await store.askAgent() } })
        }
        return items
    }

    private var canSendAgentDraft: Bool {
        !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func markdownInsertCommand(title: String, markdown: String) -> PaletteCommand {
        PaletteCommand(title: title, shortcut: "", animation: WeiBeiMotion.layout) {
            store.insertMarkdownSnippet(markdown)
        }
    }

    private var rightPaneCommand: PaletteCommand? {
        guard store.layout.hasCollapsibleRightPane else { return nil }
        return PaletteCommand(
            title: store.showRightPane ? "收起辅助栏" : "展开辅助栏",
            shortcut: "⌘J",
            animation: WeiBeiMotion.layout
        ) {
            store.toggleRightPane()
        }
    }

    private var filtered: [PaletteCommand] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return commands }
        return commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            ZStack {
                WeiBeiTheme.chrome.opacity(0.18)
                Rectangle()
                    .fill(.thinMaterial)
                    .opacity(0.08)
            }
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(WeiBeiMotion.panel) {
                    store.commandPalettePresented = false
                }
            }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "command")
                        .foregroundStyle(WeiBeiTheme.link)
                    TextField("", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundColor(WeiBeiTheme.ink)
                        .focused($searchFocused)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .weibeiInputPrompt("命令", visible: query.isEmpty, leading: 0, fontSize: 18, weight: .semibold)
                }
                .weibeiInputSurface(active: searchFocused, height: 36)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.72))
                    .frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            if filtered.isEmpty {
                                Text("没有匹配命令")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 18)
                            } else {
                                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                                    Button {
                                        run(command)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Text(command.title)
                                                .font(.system(size: 13, weight: .medium))
                                                .lineLimit(1)
                                            Spacer()
                                            if !command.shortcut.isEmpty {
                                                Text(command.shortcut)
                                                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                                    .font(.caption.monospaced())
                                            }
                                        }
                                        .padding(.horizontal, 13)
                                        .frame(height: 34)
                                        .contentShape(Rectangle())
                                        .background(index == selectedIndex ? WeiBeiTheme.cinnabarSoft : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .scaleEffect(index == selectedIndex ? 1.006 : 1, anchor: .center)
                                        .animation(WeiBeiMotion.micro, value: selectedIndex)
                                    }
                                    .id(command.id)
                                    .buttonStyle(.plain)
                                    .onHover { hovering in
                                        if hovering {
                                            withAnimation(WeiBeiMotion.micro) {
                                                selectedIndex = index
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 408)
                    .onChange(of: selectedIndex) { _, index in
                        guard filtered.indices.contains(index) else { return }
                        withAnimation(WeiBeiMotion.micro) {
                            proxy.scrollTo(filtered[index].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 500)
            .weibeiFloatingPanel(cornerRadius: 8, shadowOpacity: 0.16)
            .transition(WeiBeiTransition.commandPalette)
            .background {
                PaletteKeyboardBridge(
                    onUp: { moveSelection(-1) },
                    onDown: { moveSelection(1) },
                    onReturn: { runSelected() },
                    onEscape: {
                        withAnimation(WeiBeiMotion.panel) {
                            store.commandPalettePresented = false
                        }
                    }
                )
            }
        }
        .onAppear {
            searchFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onChange(of: filtered.count) { _, count in
            selectedIndex = min(selectedIndex, max(count - 1, 0))
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        withAnimation(WeiBeiMotion.micro) {
            selectedIndex = (selectedIndex + delta + filtered.count) % filtered.count
        }
    }

    private func runSelected() {
        guard filtered.indices.contains(selectedIndex) else { return }
        run(filtered[selectedIndex])
    }

    private func run(_ command: PaletteCommand) {
        withAnimation(command.animation) {
            command.action()
            store.commandPalettePresented = false
        }
    }
}

private struct PaletteCommand: Identifiable {
    var title: String
    var shortcut: String
    var animation = WeiBeiMotion.panel
    var action: () -> Void

    var id: String { title }
}

private struct PaletteKeyboardBridge: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onUp: onUp, onDown: onDown, onReturn: onReturn, onEscape: onEscape)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onUp = onUp
        context.coordinator.onDown = onDown
        context.coordinator.onReturn = onReturn
        context.coordinator.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onUp: () -> Void
        var onDown: () -> Void
        var onReturn: () -> Void
        var onEscape: () -> Void
        private var monitor: Any?

        init(onUp: @escaping () -> Void, onDown: @escaping () -> Void, onReturn: @escaping () -> Void, onEscape: @escaping () -> Void) {
            self.onUp = onUp
            self.onDown = onDown
            self.onReturn = onReturn
            self.onEscape = onEscape
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 126:
                    self.onUp()
                    return nil
                case 125:
                    self.onDown()
                    return nil
                case 36:
                    self.onReturn()
                    return nil
                case 53:
                    self.onEscape()
                    return nil
                default:
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
