import SwiftUI
import WeiBeiCore

/// Chat 输入框。草稿放在本地 `@State`，打字不写 `store.agentDraft`，避免整棵对话树刷新。
struct ComposerView: View {
    static let reasoningControlHeight: CGFloat = 26
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

    private var showsControl: Bool {
        isRunning || canSend
    }

    var body: some View {
        let corner: CGFloat = showsChrome ? 24 : WeiBeiMetric.controlRadius
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
            .padding(.bottom, verticalPadding)
            .padding(.trailing, trailingPadding)
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
                if showsControl {
                    sendButton
                        .padding(.trailing, sendTrailing)
                }
            }
            if showsReasoningEffort {
                reasoningEffortPicker
                    .frame(height: Self.reasoningControlHeight - 8)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, 8)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: height,
            maxHeight: compactMaxHeight,
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
        let levels = store.agentReasoningLevels
        return Menu {
            ForEach(levels, id: \.self) { effort in
                Button {
                    store.agentReasoningEfforts[store.agentReasoningModelKey] = effort
                } label: {
                    if effort == store.agentReasoningEffort {
                        Label(AgentReasoningEffort.label(effort, language: store.interfaceLanguage), systemImage: "checkmark")
                    } else {
                        Text(AgentReasoningEffort.label(effort, language: store.interfaceLanguage))
                    }
                }
            }
        } label: {
            Text(store.agentReasoningEffort.map {
                store.ui("推理：", "Reasoning: ") + AgentReasoningEffort.label($0, language: store.interfaceLanguage)
            } ?? store.ui("推理：模型默认", "Reasoning: model default"))
                .weiBeiText(11, weight: .medium)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(levels.isEmpty)
        .help(store.ui("强度越高，思考通常越久。仅对支持推理强度的模型生效。", "Higher effort usually takes longer. Applies only to models that support reasoning effort."))
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
            Image(systemName: isRunning ? "stop.fill" : "paperplane.fill")
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
