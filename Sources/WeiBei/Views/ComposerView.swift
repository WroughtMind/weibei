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
    @State private var showsReasoningPicker = false
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
            .contentShape(Rectangle())
            .onTapGesture { focusRequest &+= 1 }
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
        .onChange(of: store.agentReasoningModelKey) { _, _ in showsReasoningPicker = false }
        .task(id: store.activeAgentProfileID.uuidString + store.agentProviderID.rawValue + store.agentBaseURL) {
            guard showsReasoningEffort else { return }
            agentAccount.refreshModels(provider: store.agentProviderID, baseURL: store.agentBaseURL)
        }
        .accessibilityIdentifier("agent-composer-compact")
    }

    private var reasoningEffortPicker: some View {
        Button {
            showsReasoningPicker.toggle()
        } label: {
            HStack(spacing: 5) {
                ZStack(alignment: .leading) {
                    // Reserve the widest mode label so selection never resizes the editor.
                    ForEach(AgentReasoningMode.allCases, id: \.self) { mode in
                        Text(mode.label).hidden().accessibilityHidden(true)
                    }
                    Text(store.agentReasoningMode.label)
                }
                .weiBeiText(fontSize, weight: .regular)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9 * textScale, weight: .medium))
            }
            .padding(.horizontal, 6)
            .frame(minHeight: sendButtonSize * textScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(ReasoningModeButtonStyle(selected: showsReasoningPicker))
        .fixedSize()
        .popover(isPresented: $showsReasoningPicker, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            VStack(spacing: 2) {
                ForEach(AgentReasoningMode.allCases, id: \.self) { mode in
                    Button {
                        store.agentReasoningMode = mode
                        showsReasoningPicker = false
                    } label: {
                        HStack(spacing: 24) {
                            Text(mode.label)
                            Spacer(minLength: 0)
                            Image(systemName: "checkmark")
                                .opacity(mode == store.agentReasoningMode ? 1 : 0)
                        }
                        .weiBeiText(13)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ReasoningModeButtonStyle(selected: mode == store.agentReasoningMode))
                    .accessibilityAddTraits(mode == store.agentReasoningMode ? .isSelected : [])
                }
            }
            .padding(6)
            .fixedSize(horizontal: true, vertical: true)
            .background(WeiBeiTheme.paperRaised)
        }
        .accessibilityLabel(store.ui("推理模式", "Reasoning mode"))
        .accessibilityValue(store.agentReasoningMode.label)
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

/// Hover lifts the surface with a shadow; pressing settles it without scaling.
private struct ReasoningModeButtonStyle: ButtonStyle {
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @State private var hovering = false
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? WeiBeiTheme.paperRaised : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(WeiBeiTheme.ink.opacity(configuration.isPressed ? 0.12 : hovering || selected ? 0.07 : 0))
                    }
                    .shadow(
                        color: WeiBeiTheme.ink.opacity(hovering && !configuration.isPressed ? 0.14 : 0),
                        radius: 3, y: 1
                    )
            }
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : WeiBeiMotion.micro, value: hovering)
            .animation(reduceMotion || configuration.isPressed ? nil : WeiBeiMotion.micro, value: configuration.isPressed)
    }
}
