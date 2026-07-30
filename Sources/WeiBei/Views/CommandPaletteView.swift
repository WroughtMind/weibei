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
            PaletteCommand(title: store.ui("打开课程空间", "Open Course Space"), shortcut: "⌘0", animation: WeiBeiMotion.panel) { store.presentCourseWorkspace(.hub) },
            PaletteCommand(title: store.ui("打开资料", "Open Material"), shortcut: "⌘O") { store.importFilesFromPanel() },
            PaletteCommand(title: store.ui("新建空白笔记", "New Blank Note"), shortcut: "⌘N") { store.promptCreateBlankNotebookNote() },
            PaletteCommand(title: store.ui("聚焦课程目录", "Focus Course Index"), shortcut: "⌘1", animation: WeiBeiMotion.layout) { store.focus(.library) },
            PaletteCommand(title: store.ui("聚焦阅读", "Focus Reader"), shortcut: "⌘2", animation: WeiBeiMotion.layout) { store.focus(.reader) },
            PaletteCommand(title: store.ui("聚焦笔记", "Focus Notes"), shortcut: "⌘3", animation: WeiBeiMotion.layout) { store.focus(.notes) },
            PaletteCommand(title: store.ui("聚焦对话", "Focus Chat"), shortcut: "⌘4", animation: WeiBeiMotion.layout) { store.focus(.agent) },
            PaletteCommand(title: store.ui("上一份资料", "Previous Material"), shortcut: "⌥⌘↑", animation: WeiBeiMotion.layout) { store.selectAdjacentItem(step: -1) },
            PaletteCommand(title: store.ui("下一份资料", "Next Material"), shortcut: "⌥⌘↓", animation: WeiBeiMotion.layout) { store.selectAdjacentItem(step: 1) },
            PaletteCommand(title: store.showLibrary ? store.ui("收起课程目录", "Hide Course Index") : store.ui("打开课程目录", "Show Course Index"), shortcut: "⌘B") { store.toggleLibrary() },
            PaletteCommand(title: store.ui("三栏工作台", "Three-Pane Workspace"), shortcut: "⌥⌘1", animation: WeiBeiMotion.layout) { store.setLayout(.documentAgentNotes) },
            PaletteCommand(title: WorkspaceLayout.documentNotesSplit.label(language: store.interfaceLanguage), shortcut: "⌥⌘2", animation: WeiBeiMotion.layout) { store.setLayout(.documentNotesSplit) },
            PaletteCommand(title: WorkspaceLayout.immersiveReading.label(language: store.interfaceLanguage), shortcut: "⌥⌘R", animation: WeiBeiMotion.layout) { store.setLayout(.immersiveReading) },
            PaletteCommand(title: WorkspaceLayout.immersiveConversation.label(language: store.interfaceLanguage), shortcut: "⌥⌘A", animation: WeiBeiMotion.layout) { store.setLayout(.immersiveConversation) },
            PaletteCommand(title: WorkspaceLayout.immersiveWriting.label(language: store.interfaceLanguage), shortcut: "⌥⌘N", animation: WeiBeiMotion.layout) { store.setLayout(.immersiveWriting) },
            agentSurfaceCommand(.hidden, shortcut: "⌃⌥0"),
            PaletteCommand(title: store.ui("笔记原地写作", "Live Markdown Writing"), shortcut: "⌃⌘1") { store.setNoteRenderMode(.rich) },
            PaletteCommand(title: store.ui("笔记源码对照", "Source Compare"), shortcut: "⌃⌘2") { store.setNoteRenderMode(.split) },
            PaletteCommand(title: store.ui("笔记源码", "Note Source"), shortcut: "⌃⌘3") { store.setNoteRenderMode(.source) },
            markdownInsertCommand(title: store.ui("插入行内公式", "Insert inline formula"), markdown: "${{WEIBEI_SELECT_START}}x_i = \\frac{a}{b}{{WEIBEI_SELECT_END}}$"),
            markdownInsertCommand(title: store.ui("插入块级公式", "Insert block formula"), markdown: "\n$$\n{{WEIBEI_SELECT_START}}E = mc^2{{WEIBEI_SELECT_END}}\n$$\n"),
            markdownInsertCommand(title: store.ui("插入矩阵公式", "Insert matrix formula"), markdown: "\n$$\n\\begin{bmatrix}\n{{WEIBEI_SELECT_START}}a{{WEIBEI_SELECT_END}} & b \\\\\nc & d\n\\end{bmatrix}\n$$\n"),
            markdownInsertCommand(title: store.ui("插入 Callout", "Insert callout"), markdown: store.ui("\n> [!note] 标题\n>\n> {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}}\n", "\n> [!note] Title\n>\n> {{WEIBEI_SELECT_START}}Content{{WEIBEI_SELECT_END}}\n")),
            markdownInsertCommand(title: store.ui("插入表格", "Insert table"), markdown: store.ui("\n| A | B |\n| --- | --- |\n| {{WEIBEI_SELECT_START}}内容{{WEIBEI_SELECT_END}} |  |\n", "\n| A | B |\n| --- | --- |\n| {{WEIBEI_SELECT_START}}Content{{WEIBEI_SELECT_END}} |  |\n")),
            markdownInsertCommand(title: store.ui("插入 Mermaid", "Insert Mermaid"), markdown: store.ui("\n```mermaid\ngraph TD\n  {{WEIBEI_SELECT_START}}A[开始] --> B[整理]{{WEIBEI_SELECT_END}}\n```\n", "\n```mermaid\ngraph TD\n  {{WEIBEI_SELECT_START}}A[Start] --> B[Organize]{{WEIBEI_SELECT_END}}\n```\n"))
        ]
        if store.canUseSelectionAgentSurface {
            items.insert(agentSurfaceCommand(.selectionFloat, shortcut: "⌃⌥3"), at: min(17, items.count))
        }
        if store.hasSelectedMaterial {
            items.insert(
                PaletteCommand(title: store.ui("从当前资料开笔记", "Note from Current Material"), shortcut: "", animation: WeiBeiMotion.layout) { store.promptCreateNotebookNoteFromCurrentMaterial() },
                at: 2
            )
        }
        if store.canUseSelectedMarkdownAsNotebookNote {
            items.insert(
                PaletteCommand(title: store.ui("作为笔记编辑当前 Markdown", "Edit current Markdown as note"), shortcut: "") { store.useSelectedMarkdownAsNotebookNote() },
                at: 2
            )
        }
        if let rightPaneCommand {
            items.insert(rightPaneCommand, at: 9)
        }
        if store.layout.isDocumentThreePane {
            items.insert(
                PaletteCommand(title: store.ui("交换笔记与对话", "Swap Notes and Chat"), shortcut: "⌥⌘S", animation: WeiBeiMotion.layout) { store.swapThreePaneSecondaryPanes() },
                at: 11
            )
        }
        if store.canCopyReference {
            items.append(PaletteCommand(title: store.copyReferenceActionTitle, shortcut: "⌘⇧C") { store.copyCurrentReference() })
        }
        if store.hasSelectedMaterial {
            items.append(PaletteCommand(title: store.ui("打开资料内搜索", "Search in Material"), shortcut: "⌘F") { store.revealReaderSearch() })
        }
        if store.selectionContext != nil {
            items.append(PaletteCommand(title: store.ui("问当前选区", "Ask Current Selection"), shortcut: "") {
                store.askSelection()
            })
        }
        if store.canOpenSelectedSourceReference {
            items.append(PaletteCommand(title: store.ui("打开选区来源", "Open Selection Source"), shortcut: "") { store.openSelectedSourceReference() })
        }
        if store.agentSurface != .hidden {
            items.append(agentSurfaceCommand(.hidden, shortcut: "⌃⌥0"))
        }
        if store.canApplyAgentAnswer {
            items.append(PaletteCommand(title: store.ui("写入回答到笔记", "Write Answer to Note"), shortcut: "⌘⇧A") { store.applyLastAgentAnswerToNote() })
            items.append(PaletteCommand(title: store.ui("追加整理建议", "Append Organization Suggestion"), shortcut: "⌘⇧E") { store.applyAgentPatchToEditor() })
        }
        if store.canReplaceNoteSelection {
            items.append(PaletteCommand(title: store.ui("替换笔记选区", "Replace Note Selection"), shortcut: "⌘⇧R") { store.replaceSelectionWithLastAgentAnswer() })
        }
        if canControlAgent {
            items.append(PaletteCommand(title: store.sendAgentActionTitle, shortcut: "⌘↩") {
                store.submitAgentDraft()
            })
        }
        return items
    }

    private var canControlAgent: Bool {
        store.isAgentRunningInActiveChat || !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func markdownInsertCommand(title: String, markdown: String) -> PaletteCommand {
        PaletteCommand(title: title, shortcut: "", animation: WeiBeiMotion.layout) {
            store.insertMarkdownSnippet(markdown)
        }
    }

    private func agentSurfaceCommand(_ surface: AgentSurface, shortcut: String) -> PaletteCommand {
        PaletteCommand(title: surface.actionLabel(language: store.interfaceLanguage), shortcut: shortcut) {
            store.setAgentSurface(surface)
        }
    }

    private var rightPaneCommand: PaletteCommand? {
        guard store.layout.hasCollapsibleRightPane else { return nil }
        return PaletteCommand(
            title: store.showRightPane ? store.ui("收起辅助栏", "Hide Assistant Pane") : store.ui("展开辅助栏", "Show Assistant Pane"),
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
                    TextField(
                        "",
                        text: $query,
                        prompt: Text(store.ui("输入命令", "Type a command"))
                            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 18, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.placeholderInk)
                    )
                        .textFieldStyle(.plain)
                        .foregroundColor(WeiBeiTheme.ink)
                        .focused($searchFocused)
                        .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 18, weight: .semibold))
                }
                .weibeiInputSurface(active: searchFocused, height: 36)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.72))
                    .frame(height: 1)

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 3) {
                            if filtered.isEmpty {
                                Text(store.ui("没有匹配命令", "No matching commands"))
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
