import SwiftUI
import WeiBeiCore

/// Chat 输入框。草稿放在本地 `@State`，打字不写 `store.agentDraft`，避免整棵对话树刷新。
struct ComposerView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weiBeiTextScale) private var textScale
    @ObservedObject private var agentAccount = AgentAccountService.shared
    @State private var draft = ""
    @State private var editorHeight: CGFloat = 0
    @State private var editorActive = false
    @State private var focusRequest = 0
    var prompt: String
    var focused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var lineLimit: ClosedRange<Int>
    var height: CGFloat
    /// Cap for immersive grow; nil means fixed compact height.
    var maxHeight: CGFloat? = nil
    /// Optional safety cap for a compact composer hosted inside a floating surface.
    var compactMaxHeight: CGFloat? = nil
    var sendButtonSize: CGFloat
    var trailingPadding: CGFloat
    var sendTrailing: CGFloat
    var sendBottom: CGFloat
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 0
    /// Codex-style footer: model chip on the left, send on the right inside the card.
    var showsModelFooter: Bool = false
    /// Floating paper surfaces already provide their own chrome.
    var showsChrome = true
    var submit: () -> Void

    private var canSend: Bool {
        AgentProviderReadiness.isConfigured(for: store)
            && !store.isStoppingAgent
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsControl: Bool {
        store.isAgentRunningInActiveChat || canSend
    }

    private var isWideComposer: Bool { maxHeight != nil || showsModelFooter }

    var body: some View {
        let corner: CGFloat = isWideComposer ? 24 : WeiBeiMetric.controlRadius
        let textHeight = max(editorHeight, fontSize + 3)
        let reservedControlHeight = sendButtonSize * textScale + verticalPadding * 2
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                AgentComposerTextEditor(
                    text: $draft,
                    measuredHeight: $editorHeight,
                    active: $editorActive,
                    focused: focused,
                    fontSize: fontSize,
                    lineLimit: lineLimit,
                    focusRequest: focusRequest,
                    appearanceMode: store.appearanceMode,
                    accessibilityLabel: prompt,
                    submit: commitAndSubmit
                )
                .frame(maxWidth: .infinity)
                .frame(height: textHeight)

                if draft.isEmpty && !editorActive {
                    Text(prompt)
                        .weiBeiText(fontSize)
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .allowsHitTesting(false)
                }
            }
            .padding(.top, verticalPadding)
            .padding(.bottom, showsModelFooter ? 6 : verticalPadding)
            .padding(.trailing, showsModelFooter ? 0 : trailingPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: isWideComposer
                    ? nil
                    : max(
                        CGFloat(SelectionFloatingAgentPlacement.composerControlHostMinimumHeight(
                            composerMinimumHeight: Double(height)
                        )),
                        reservedControlHeight
                    ),
                maxHeight: isWideComposer ? .infinity : nil,
                alignment: .leading
            )
            .overlay(alignment: .trailing) {
                if showsControl && !showsModelFooter {
                    sendButton
                        .padding(.trailing, sendTrailing)
                }
            }

            if showsModelFooter {
                HStack(spacing: 10) {
                    Text(store.modelName.isEmpty ? store.ui("模型", "Model") : store.modelName)
                        .weiBeiText(12, weight: .medium)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    ZStack {
                        Color.clear
                            .frame(
                                width: sendButtonSize * textScale,
                                height: sendButtonSize * textScale
                            )
                        if showsControl {
                            sendButton
                        }
                    }
                }
                .padding(.leading, horizontalPadding)
                .padding(.trailing, sendTrailing)
                .padding(.bottom, sendBottom)
                .padding(.top, 2)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: height,
            maxHeight: isWideComposer ? maxHeight : compactMaxHeight,
            alignment: .topLeading
        )
        .fixedSize(horizontal: false, vertical: true)
        .weibeiComposerCard(
            cornerRadius: corner,
            focused: focused.wrappedValue,
            showsChrome: showsChrome
        )
        .contentShape(RoundedRectangle(cornerRadius: corner))
        .onTapGesture {
            focusRequest &+= 1
        }
        .onAppear {
            draft = store.agentDraft
            store.pendingComposerDraft = draft
        }
        .onChange(of: store.agentDraft) { _, newValue in
            guard draft != newValue else { return }
            draft = newValue
        }
        .onChange(of: draft) { _, newValue in
            store.pendingComposerDraft = newValue
            guard focused.wrappedValue else { return }
            guard let span = WeiBeiPerf.begin(
                "input.agent_to_next_main_queue_proxy"
            ) else {
                return
            }
            DispatchQueue.main.async {
                WeiBeiPerf.end(
                    span,
                    extra:
                        "outcome=completed endpoint=next_main_queue_proxy"
                )
            }
        }
        .animation(WeiBeiMotion.micro, value: showsControl)
        .accessibilityIdentifier(isWideComposer ? "agent-composer-codex" : "agent-composer-compact")
    }

    private func commitAndSubmit() {
        guard AgentProviderReadiness.isConfigured(for: store) else { return }
        store.pendingComposerDraft = draft
        store.agentDraft = draft
        submit()
    }

    private var sendButton: some View {
        Button {
            store.isAgentRunningInActiveChat ? store.cancelAgentRequest() : commitAndSubmit()
        } label: {
            Image(systemName: store.isAgentRunningInActiveChat ? "stop.fill" : "paperplane.fill")
        }
        .buttonStyle(WeiBeiIconButtonStyle(
            size: sendButtonSize,
            prominence: store.isAgentRunningInActiveChat ? .neutral : .primary,
            cornerRadius: sendButtonSize / 2
        ))
        .accessibilityLabel(Text(store.isAgentRunningInActiveChat ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send")))
        .help(store.isAgentRunningInActiveChat ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send"))
        .keyboardShortcut(.return, modifiers: [.command])
        .transition(WeiBeiTransition.floating)
        .animation(WeiBeiMotion.micro, value: showsControl)
    }
}
