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
    var lineLimit: ClosedRange<Int>?
    var height: CGFloat
    /// Optional safety cap for a compact composer hosted inside a floating surface.
    var compactMaxHeight: CGFloat? = nil
    var sendButtonSize: CGFloat
    var trailingPadding: CGFloat
    var sendTrailing: CGFloat
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 0
    /// Floating paper surfaces already provide their own chrome.
    var showsChrome = true
    var focusesOnAppear = false
    var focusTrigger = 0
    var showsReasoningEffort = false
    var sessionID: UUID? = nil
    var submit: () -> Void

    private var targetID: UUID? { sessionID ?? store.activeStudySessionID }
    private var isRunning: Bool { targetID.map { store.isAgentRunning(in: $0) } ?? false }
    private var isStopping: Bool { targetID.flatMap { store.agentRuns[$0]?.isStoppingAgent } ?? false }

    private var canSend: Bool {
        AgentProviderReadiness.isConfigured(for: store)
            && !isStopping
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasReasoningControl: Bool {
        showsReasoningEffort && !store.agentReasoningLevels.isEmpty
    }

    private var showsControl: Bool {
        isRunning || canSend
    }

    var body: some View {
        let corner: CGFloat = showsChrome ? 22 : WeiBeiMetric.controlRadius
        let textHeight = max(editorHeight, fontSize + 3)
        let reservedControlHeight = sendButtonSize * textScale + verticalPadding * 2
        HStack(spacing: 0) {
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
            .padding(.vertical, verticalPadding)
            .padding(.trailing, hasReasoningControl ? 0 : trailingPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(
                maxWidth: .infinity,
                minHeight: max(
                    CGFloat(SelectionFloatingAgentPlacement.composerControlHostMinimumHeight(
                        composerMinimumHeight: Double(height)
                    )),
                    reservedControlHeight
                ),
                alignment: .leading
            )
            .overlay(alignment: .trailing) {
                if showsControl && !hasReasoningControl {
                    sendButton
                        .padding(.trailing, sendTrailing)
                }
            }
            if hasReasoningControl {
                HStack(spacing: 12) {
                    reasoningEffortPicker
                    sendButton
                        .opacity(showsControl ? 1 : 0)
                        .disabled(!showsControl)
                        .accessibilityHidden(!showsControl)
                }
                .padding(.trailing, sendTrailing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(
            max(height, textHeight + verticalPadding * 2, reservedControlHeight),
            compactMaxHeight ?? .greatestFiniteMagnitude
        ), alignment: .topLeading)
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
            draft = store.composerDraft(for: targetID)
            if focusesOnAppear || focused.wrappedValue { focusRequest &+= 1 }
        }
        .onChange(of: focused.wrappedValue) { _, focused in
            if focused { focusRequest &+= 1 }
        }
        .onChange(of: focusTrigger) { _, _ in focusRequest &+= 1 }
        .onChange(of: targetID) { _, _ in draft = store.composerDraft(for: targetID) }
        .onReceive(store.$floatingAgentDraft) { newValue in
            guard let sessionID, sessionID == store.activeSelectionAskThreadID, draft != newValue else { return }
            draft = newValue
        }
        .onReceive(store.$agentDraft) { newValue in
            guard sessionID == nil, draft != newValue else { return }
            draft = newValue
        }
        .onChange(of: draft) { _, newValue in
            store.saveComposerDraft(newValue, for: targetID)
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
        .task(id: store.activeAgentProfileID.uuidString + store.agentProviderID.rawValue + store.agentBaseURL) {
            guard showsReasoningEffort else { return }
            agentAccount.refreshModels(provider: store.agentProviderID, baseURL: store.agentBaseURL)
        }
        .accessibilityIdentifier("agent-composer-compact")
    }

    private var reasoningEffortPicker: some View {
        Menu {
            ForEach(AgentReasoningMode.allCases, id: \.self) { mode in
                Button {
                    store.agentReasoningMode = mode
                } label: {
                    if mode == store.agentReasoningMode {
                        Label(mode.label, systemImage: "checkmark")
                    } else {
                        Text(mode.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.agentReasoningMode.label)
                    .weiBeiText(fontSize, weight: .regular)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9 * textScale, weight: .medium))
            }
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .frame(minHeight: sendButtonSize * textScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(store.ui("推理强度", "Reasoning effort"))
        .help(store.ui("Flash 快速回答，Think 深入思考。可在对话设置中调整对应强度。", "Flash for quick answers, Think for deeper reasoning. Configure their effort in Chat settings."))
        .accessibilityIdentifier("agent-reasoning-effort")
    }

    private func commitAndSubmit() {
        guard AgentProviderReadiness.isConfigured(for: store) else { return }
        store.saveComposerDraft(draft, for: targetID)
        submit()
    }

    private var sendButton: some View {
        Button {
            if isRunning, let targetID { store.cancelAgentRequest(in: targetID) }
            else { commitAndSubmit() }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : showsChrome ? "arrow.up" : "paperplane.fill")
        }
        .buttonStyle(WeiBeiIconButtonStyle(
            size: sendButtonSize,
            prominence: isRunning ? .neutral : .primary,
            cornerRadius: sendButtonSize / 2
        ))
        .accessibilityLabel(Text(isRunning ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send")))
        .help(isRunning ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send"))
        .keyboardShortcut(focused.wrappedValue ? KeyboardShortcut(.return, modifiers: [.command]) : nil)
        .transition(WeiBeiTransition.floating)
        .animation(WeiBeiMotion.micro, value: showsControl)
    }
}
