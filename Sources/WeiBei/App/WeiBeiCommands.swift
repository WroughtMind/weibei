import SwiftUI
import WeiBeiCore

/**
 * 提供应用级菜单命令，并将快捷键动作映射到工作区状态。
 */
struct WeiBeiCommands: Commands {
    @ObservedObject var store: WorkspaceStore

    /**
     * 构建应用菜单及其快捷键。
     */
    var body: some Commands {
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
                .keyboardShortcut("1")
            Button(store.ui("聚焦阅读", "Focus Reader")) { animateLayout { store.focus(.reader) } }
                .keyboardShortcut("2")
            Button(store.ui("聚焦笔记", "Focus Notes")) { animateLayout { store.focus(.notes) } }
                .keyboardShortcut("3")
            Button(store.ui("聚焦对话", "Focus Chat")) { animateLayout { store.focus(.agent) } }
                .keyboardShortcut("4")

            Divider()

            Button(store.ui("上一份资料", "Previous Material")) { animateLayout { store.selectAdjacentItem(step: -1) } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button(store.ui("下一份资料", "Next Material")) { animateLayout { store.selectAdjacentItem(step: 1) } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

            Divider()

            Button(store.showLibrary ? store.ui("收起课程目录", "Hide Course Index") : store.ui("打开课程目录", "Show Course Index")) {
                store.toggleLibrary()
            }
            .keyboardShortcut("b")
            if store.layout.hasCollapsibleRightPane {
                Button(store.showRightPane ? store.ui("收起辅助栏", "Hide Assistant Pane") : store.ui("展开辅助栏", "Show Assistant Pane")) {
                    animateLayout {
                        store.toggleRightPane()
                    }
                }
                .keyboardShortcut("j")
            }

            Divider()

            Button(store.ui("三栏工作台", "Three-Pane Workspace")) { setLayout(.documentAgentNotes) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button(WorkspaceLayout.documentNotesSplit.label(language: store.interfaceLanguage)) { setLayout(.documentNotesSplit) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            if store.layout.isDocumentThreePane {
                Button(store.ui("交换笔记与对话", "Swap Notes and Chat")) {
                    animateLayout {
                        store.swapThreePaneSecondaryPanes()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
            Button(WorkspaceLayout.immersiveReading.label(language: store.interfaceLanguage)) { setLayout(.immersiveReading) }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button(WorkspaceLayout.immersiveConversation.label(language: store.interfaceLanguage)) { setLayout(.immersiveConversation) }
                .keyboardShortcut("a", modifiers: [.command, .option])
            Button(WorkspaceLayout.immersiveWriting.label(language: store.interfaceLanguage)) { setLayout(.immersiveWriting) }
                .keyboardShortcut("n", modifiers: [.command, .option])

            Divider()

            Button(store.appearanceMode.actionLabel(language: store.interfaceLanguage)) {
                animateAppearance {
                    store.toggleAppearanceMode()
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Divider()

            if store.canUseSelectionAgentSurface {
                Button(AgentSurface.selectionFloat.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.selectionFloat) }
                    .keyboardShortcut("3", modifiers: [.control, .option])
            }
            Button(AgentSurface.hidden.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.hidden) }
                .keyboardShortcut("0", modifiers: [.control, .option])

            Divider()

            Button(store.ui("笔记原地写作", "Live Markdown Writing")) { setNoteRenderMode(.rich) }
                .keyboardShortcut("1", modifiers: [.control, .command])
            Button(store.ui("笔记源码对照", "Source Compare")) { setNoteRenderMode(.split) }
                .keyboardShortcut("2", modifiers: [.control, .command])
            Button(store.ui("笔记源码", "Note Source")) { setNoteRenderMode(.source) }
                .keyboardShortcut("3", modifiers: [.control, .command])

            if store.canApplyAgentAnswer {
                Divider()

                Button(store.ui("写入回答到笔记", "Write Answer to Note")) { animatePanel { store.applyLastAgentAnswerToNote() } }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                if store.canReplaceNoteSelection {
                    Button(store.ui("替换笔记选区", "Replace Note Selection")) { animatePanel { store.replaceSelectionWithLastAgentAnswer() } }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                Button(store.ui("追加整理建议", "Append Organization Suggestion")) { animatePanel { store.applyAgentPatchToEditor() } }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            Divider()

            Button(store.ui("命令面板", "Command Palette")) {
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
                Button(store.ui("打开资料内搜索", "Search in Material")) {
                    animatePanel {
                        store.revealReaderSearch()
                    }
                }
                .keyboardShortcut("f")
            }
            if store.isAskingAgent || !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(store.sendAgentActionTitle) {
                    store.isAskingAgent ? store.cancelAgentRequest() : store.askAgent()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    /**
     * 使用工作区布局动效执行菜单动作。
     */
    private func animateLayout(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.layout) {
            action()
        }
    }

    /**
     * 使用面板动效执行菜单动作。
     */
    private func animatePanel(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.panel) {
            action()
        }
    }

    /**
     * 使用外观切换动效执行菜单动作。
     */
    private func animateAppearance(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.appearance) {
            action()
        }
    }

    /**
     * 切换工作区布局。
     */
    private func setLayout(_ layout: WorkspaceLayout) {
        animateLayout {
            store.setLayout(layout)
        }
    }

    /**
     * 切换 Agent 的呈现界面。
     */
    private func setAgentSurface(_ surface: AgentSurface) {
        animatePanel {
            store.setAgentSurface(surface)
        }
    }

    /**
     * 切换笔记编辑与渲染模式。
     */
    private func setNoteRenderMode(_ mode: NoteRenderMode) {
        animatePanel {
            store.setNoteRenderMode(mode)
        }
    }
}
