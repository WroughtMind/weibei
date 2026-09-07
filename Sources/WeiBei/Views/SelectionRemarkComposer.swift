import SwiftUI

/// 问/记共用浮层顶部的模式切换:问=提问,记=札记。低调融入浮层头部,不抢主操作。
struct FloatingAgentModeSwitch: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interaction: WorkspaceInteractionState

    var body: some View {
        HStack(spacing: 2) {
            modeButton(store.ui("问", "Ask"), mode: .ask,
                       help: store.ui("就这段提问", "Ask about this passage"))
            modeButton(store.ui("记", "Remark"), mode: .remark,
                       help: store.ui("记一句摘抄", "Save a remark"))
        }
        .padding(2)
        .background(
            WeiBeiTheme.paperInset.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private func modeButton(_ label: String, mode: FloatingSelectionComposerMode, help: String) -> some View {
        let active = interaction.floatingComposerMode == mode
        return Button {
            withAnimation(WeiBeiMotion.micro) { interaction.floatingComposerMode = mode }
        } label: {
            Text(label)
        .weiBeiText(12, weight: .semibold)
        .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
        .padding(.horizontal, 9)
        .frame(minWidth: 30, minHeight: 28)
        .contentShape(Rectangle())
        .background {
            if active {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(WeiBeiTheme.paper.opacity(0.92))
            }
        }
        }
        .buttonStyle(WeiBeiTextActionButtonStyle(fontSize: 12, height: 28))
        .help(help)
        .accessibilityLabel(Text(help))
    }
}

/// "记"输入框:⌘↩/回车提交;留空提交=只存原文引用。草稿存 interaction.selectionNoteDraft,
/// 与问的 agentDraft 互不覆盖。
struct SelectionRemarkField: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var interaction: WorkspaceInteractionState
    var submit: () -> Void
    @FocusState private var focused: Bool
    @State private var editorHeight: CGFloat = 0
    @State private var active = false
    @State private var focusRequest = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                AgentComposerTextEditor(
                    text: $interaction.selectionNoteDraft,
                    measuredHeight: $editorHeight,
                    active: $active,
                    focused: $focused,
                    fontSize: 15,
                    lineLimit: 1...3,
                    focusRequest: focusRequest,
                    appearanceMode: store.appearanceMode,
                    accessibilityLabel: store.ui("记一句，留空只存原文", "Add a remark; empty saves the passage"),
                    submit: submit
                )
                .frame(height: max(20, editorHeight))
                if interaction.selectionNoteDraft.isEmpty && !active {
                    Text(store.ui("记一句…（留空只存原文）", "Add a remark…"))
                        .weiBeiText(15)
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focusRequest &+= 1 }

            Button {
                submit()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(WeiBeiIconButtonStyle(
                size: 26,
                prominence: .primary,
                cornerRadius: 13
            ))
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityLabel(Text(store.ui("保存到摘抄本", "Save excerpt")))
            .help(store.ui("保存到摘抄本（⌘↩，留空只存原文）", "Save excerpt (⌘↩; empty saves the passage)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .weibeiComposerCard(
            cornerRadius: WeiBeiMetric.controlRadius,
            focused: focused,
            showsChrome: false
        )
        .onAppear { focused = true }
    }
}
