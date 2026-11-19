import SwiftUI
import WeiBeiCore

/// 浮窗直接编辑该选区会话的草稿；主对话沿用本地编辑状态。
struct ComposerView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weiBeiTextScale) private var textScale
    @ObservedObject var agentAccount = AgentAccountService.shared
    @State private var mainDraft = ""
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
    var isFloating = false
    var focusesOnAppear = false
    var focusTrigger = 0
    var showsReasoningEffort = false
    var sessionID: UUID? = nil
    var submit: () -> Void

    private var targetID: UUID? { isFloating ? sessionID : store.activeStudySessionID }
    private var isRunning: Bool { targetID.map { store.isAgentRunning(in: $0) } ?? false }
    private var isStopping: Bool { targetID.flatMap { store.agentRuns[$0]?.isStoppingAgent } ?? false }

    private var visibleDraft: String { isFloating ? store.composerDraft(for: sessionID) : mainDraft }

    private var editorDraft: Binding<String> {
        guard isFloating else { return $mainDraft }
        return Binding(
            get: { store.composerDraft(for: sessionID) },
            set: { store.saveComposerDraft($0, for: sessionID) }
        )
    }

    private var canSend: Bool {
        !isStopping
            && !visibleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasReasoningControl: Bool {
        showsReasoningEffort && !agentAccount.reasoningLevels(provider: store.agentProviderID, model: store.agentReasoningModelName).isEmpty
    }

    private var showsControl: Bool {
        isRunning || canSend
    }

    var body: some View {
        let corner: CGFloat = isFloating ? WeiBeiMetric.controlRadius : 22
        let textHeight = max(editorHeight, fontSize + 3)
        let reservedControlHeight = sendButtonSize * textScale + verticalPadding * 2
        let controlBottomInset = max(verticalPadding, (height - sendButtonSize * textScale) / 2)
        HStack(alignment: .bottom, spacing: 0) {
            ZStack(alignment: .topLeading) {
                AgentComposerTextEditor(
                    text: editorDraft,
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

                if visibleDraft.isEmpty && (isFloating || !editorActive) {
                    Text(prompt)
                        .weiBeiText(fontSize)
                        .foregroundStyle(WeiBeiTheme.placeholderInk)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: textHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, verticalPadding)
            .padding(.trailing, hasReasoningControl ? 0 : max(trailingPadding, sendButtonSize * textScale + sendTrailing))
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: max(height, reservedControlHeight), alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focusRequest &+= 1 }
            .overlay(alignment: .bottomTrailing) {
                if showsControl && !hasReasoningControl {
                    sendButton
                        .padding(.trailing, sendTrailing)
                        .padding(.bottom, controlBottomInset)
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
                .padding(.bottom, controlBottomInset)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: min(
            max(height, textHeight + verticalPadding * 2, reservedControlHeight),
            compactMaxHeight.map { $0 * textScale } ?? .greatestFiniteMagnitude
        ), alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .weibeiComposerCard(
            cornerRadius: corner,
            focused: focused.wrappedValue,
            fill: isFloating ? WeiBeiTheme.paperInset.opacity(0.38) : WeiBeiTheme.paperRaised
        )
        .contentShape(RoundedRectangle(cornerRadius: corner))
        .onAppear {
            if !isFloating { mainDraft = store.composerDraft(for: targetID) }
            if focusesOnAppear || focused.wrappedValue { focusRequest &+= 1 }
        }
        .onChange(of: focused.wrappedValue) { _, focused in
            if focused { focusRequest &+= 1 }
        }
        .onChange(of: focusTrigger) { _, _ in focusRequest &+= 1 }
        .onChange(of: targetID) { _, id in
            if !isFloating { mainDraft = store.composerDraft(for: id) }
        }
        .onReceive(store.$agentDraft) { newValue in
            guard !isFloating, mainDraft != newValue else { return }
            mainDraft = newValue
        }
        .onChange(of: mainDraft) { _, newValue in
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
        .task(id: store.activeAgentProfileID.uuidString
            + store.agentProviderID.rawValue
            + store.agentBaseURL
            + store.agentAuthMethod.rawValue) {
            guard showsReasoningEffort, store.agentProviderID == .openaiCodex else { return }
            agentAccount.refreshReasoningCatalogIfNeeded(
                provider: store.agentProviderID,
                baseURL: store.agentBaseURL,
                authMethod: store.agentAuthMethod
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .weiBeiAgentOAuthDidSucceed)) { _ in
            guard showsReasoningEffort, store.agentProviderID == .openaiCodex else { return }
            agentAccount.refreshModels(
                provider: store.agentProviderID,
                baseURL: store.agentBaseURL,
                authMethod: store.agentAuthMethod
            )
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
            ReasoningModeMenu(selection: store.agentReasoningMode) { mode in
                store.agentReasoningMode = mode
                showsReasoningPicker = false
            }
        }
        .accessibilityLabel(store.ui("推理模式", "Reasoning mode"))
        .accessibilityValue(store.agentReasoningMode.label)
        .help(store.ui("Flash 快速回答，Think 深入思考。可在对话设置中调整对应强度。", "Flash for quick answers, Think for deeper reasoning. Configure their effort in Chat settings."))
        .accessibilityIdentifier("agent-reasoning-effort")
    }

    private func commitAndSubmit() {
        // A1: 正在回答或正在停止时，回车不做任何事；停止只留给停止按钮。
        guard !isRunning, canSend else { return }
        if !isFloating { store.saveComposerDraft(mainDraft, for: targetID) }
        submit()
    }

    private var sendButton: some View {
        Button {
            if isRunning, let targetID { store.cancelAgentRequest(in: targetID) }
            else { commitAndSubmit() }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : isFloating ? "paperplane.fill" : "arrow.up")
        }
        .buttonStyle(WeiBeiIconButtonStyle(
            size: sendButtonSize,
            prominence: isRunning ? .neutral : .primary,
            cornerRadius: sendButtonSize / 2
        ))
        .accessibilityLabel(Text(isRunning ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send")))
        .help(isRunning ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send"))
        .keyboardShortcut(focused.wrappedValue && !isRunning ? KeyboardShortcut(.return, modifiers: [.command]) : nil)
        .transition(WeiBeiTransition.floating)
        .animation(WeiBeiMotion.micro, value: showsControl)
    }
}

private struct ReasoningModeMenu: View {
    let selection: AgentReasoningMode
    let choose: (AgentReasoningMode) -> Void
    @State private var hoveredMode: AgentReasoningMode?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(AgentReasoningMode.allCases, id: \.self) { mode in
                Button { choose(mode) } label: {
                    HStack(spacing: 24) {
                        Text(mode.label)
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .opacity(mode == selection ? 1 : 0)
                    }
                    .weiBeiText(13)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ReasoningModeButtonStyle(
                    selected: mode == selection,
                    menuHovered: hoveredMode == mode
                ))
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        hoveredMode = mode
                    case .ended:
                        if hoveredMode == mode { hoveredMode = nil }
                    }
                }
                .accessibilityAddTraits(mode == selection ? .isSelected : [])
            }
        }
        .padding(10)
        .fixedSize(horizontal: true, vertical: true)
        .presentationBackground(WeiBeiTheme.paperRaised)
    }
}

/// Menu rows receive pointer state from their whole button, outside the label style.
private struct ReasoningModeButtonStyle: ButtonStyle {
    var selected: Bool
    var menuHovered: Bool? = nil

    func makeBody(configuration: Configuration) -> some View {
        ReasoningModeButtonBody(configuration: configuration, selected: selected, menuHovered: menuHovered)
    }
}

private struct ReasoningModeButtonBody: View {
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @State private var triggerHovered = false
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let menuHovered: Bool?
    private var hovering: Bool { menuHovered ?? triggerHovered }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        configuration.label
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .background {
                shape
                    .fill(hovering || configuration.isPressed ? WeiBeiTheme.paperRaised : Color.clear)
                    .overlay {
                        shape
                            .fill(WeiBeiTheme.ink.opacity(configuration.isPressed ? 0.16 : hovering ? 0.11 : selected ? 0.04 : 0))
                    }
                    .compositingGroup()
                    .shadow(
                        color: Color.black.opacity(hovering && !configuration.isPressed ? 0.18 : 0),
                        radius: 3, y: 1
                    )
            }
            .contentShape(.interaction, shape)
            .onHover { if menuHovered == nil { triggerHovered = $0 } }
            .animation(reduceMotion ? nil : WeiBeiMotion.micro, value: hovering)
            .animation(reduceMotion || configuration.isPressed ? nil : WeiBeiMotion.micro, value: configuration.isPressed)
    }
}
