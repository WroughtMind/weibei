import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct FloatingSelectionAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var expanded: Bool
    var routesToConversation = false
    @State private var dragOffset = CGSize.zero
    @State private var settledOffset = CGSize.zero
    /// User-resizable panel; default matches placement constant (half-width × 2).
    @State private var panelWidth = CGFloat(SelectionFloatingAgentPlacement.expandedHalfWidth * 2)
    @State private var feedMaxHeight: CGFloat = 380
    @State private var resizeOriginWidth: CGFloat = 0
    @State private var resizeOriginFeedHeight: CGFloat = 0
    @FocusState private var draftFocused: Bool
    @Namespace private var floatingNamespace

    var body: some View {
        Group {
            if showsExpandedBody {
                expandedBody
            } else {
                promptBody
            }
        }
        .matchedGeometryEffect(id: "selection-agent-surface", in: floatingNamespace)
        .transition(WeiBeiTransition.floating)
        .modifier(SelectionFloatChrome(expanded: showsExpandedBody, pinned: store.pinnedFloatingAgent))
        .scaleEffect(showsExpandedBody ? 1 : 0.985)
        .animation(WeiBeiMotion.panel, value: expanded)
        .animation(WeiBeiMotion.panel, value: store.pinnedFloatingAgent)
        .animation(WeiBeiMotion.panel, value: store.isAskingAgent)
        .offset(x: dragOffset.width + settledOffset.width, y: dragOffset.height + settledOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    withAnimation(WeiBeiMotion.panel) {
                        settledOffset = CGSize(
                            width: settledOffset.width + value.translation.width,
                            height: settledOffset.height + value.translation.height
                        )
                        dragOffset = .zero
                        // Dragging repositions; pin is only set by the pin control.
                    }
                }
        )
        .onChange(of: store.selectionContext) { previous, next in
            guard !store.pinnedFloatingAgent, !store.isAskingAgent else { return }
            let sameContent = previous?.text == next?.text
                && previous?.source == next?.source
                && previous?.ownerTitle == next?.ownerTitle
                && previous?.isEditable == next?.isEditable
            guard !sameContent else { return }
            // Reopen uses SelectionContext.id == thread.id — expand beside the mark.
            let isThreadReopen = next.map { store.activeSelectionAskThreadID == $0.id } ?? false
            if isThreadReopen, store.keepFloatingSelectionForAnswer {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
                return
            }
            // Live reselection → capsule only.
            withAnimation(WeiBeiMotion.panel) {
                expanded = false
                store.keepFloatingSelectionForAnswer = false
                store.activeSelectionAskThreadID = nil
                dragOffset = .zero
                settledOffset = .zero
            }
        }
        .onChange(of: store.keepFloatingSelectionForAnswer) { _, keep in
            if keep {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
            }
        }
        .onChange(of: store.activeSelectionAskThreadID) { _, id in
            if id != nil, store.keepFloatingSelectionForAnswer {
                withAnimation(WeiBeiMotion.panel) {
                    expanded = true
                    dragOffset = .zero
                    settledOffset = .zero
                }
            }
        }
        .onChange(of: store.isAskingAgent) { _, asking in
            if asking {
                withAnimation(WeiBeiMotion.panel) { expanded = true }
            }
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
            if store.pinnedFloatingAgent || store.isAskingAgent || store.keepFloatingSelectionForAnswer {
                expanded = true
            }
        }
        .onExitCommand {
            closeFloatingAgent()
        }
    }

    private var showsExpandedBody: Bool {
        // Capsule for bare selection; expand for 问 / pin / stream / 红线回访(keepOpen).
        expanded || store.pinnedFloatingAgent || store.isAskingAgent || store.keepFloatingSelectionForAnswer
    }

    private var promptBody: some View {
        HStack(spacing: 0) {
            Button(store.ui("问", "Ask")) {
                openExpandedComposer()
            }
            .foregroundStyle(WeiBeiTheme.link)
            .accessibilityLabel(Text(store.ui("问当前选区", "Ask current selection")))
            .help(store.ui("问当前选区", "Ask current selection"))

            if store.canOpenSelectedSourceReference {
                promptSeparator
                Button(store.ui("来源", "Source")) {
                    openSourceReference()
                }
            }

            if store.selectionContext != nil {
                promptSeparator
                Button(store.ui("摘录", "Excerpt")) {
                    store.appendSelectionToNote()
                    closeFloatingAgent()
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .fixedSize()
    }

    private var promptSeparator: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.78))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 8)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(store.ui("选区对话", "Selection chat"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                if store.pinnedFloatingAgent {
                    Text(store.ui("已固定", "Pinned"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.9))
                }
                Spacer(minLength: 4)
                if store.isConversationSurfaceVisible, store.activeSelectionAskThreadID != nil {
                    Button(store.ui("跳到对话", "Jump to chat")) {
                        if let id = store.activeSelectionAskThreadID {
                            store.openSelectionAskThread(id, jumpToConversation: true)
                        }
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle())
                }
                Button {
                    withAnimation(WeiBeiMotion.micro) { togglePinnedFloatingAgent() }
                } label: {
                    Image(systemName: store.pinnedFloatingAgent ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.pinnedFloatingAgent ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(store.pinnedFloatingAgent
                      ? store.ui("取消固定：选区变化时浮层可收起", "Unpin: float may dismiss when selection changes")
                      : store.ui("固定浮层：选区变化时保持打开", "Pin float: keep open when selection changes"))
                .accessibilityLabel(Text(store.pinnedFloatingAgent ? store.ui("取消固定浮层", "Unpin floating layer") : store.ui("固定浮层", "Pin floating layer")))

                Button {
                    closeFloatingAgent()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(store.ui("关闭", "Close"))
                .accessibilityLabel(Text(store.ui("关闭", "Close")))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.55))
                .frame(height: 1)
                .padding(.horizontal, 12)

            if let selection = store.selectionContext?.text, !selection.isEmpty {
                HStack(spacing: 6) {
                    Text(store.ui("选区", "Selection"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.9))
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(WeiBeiTheme.cinnabarSoft.opacity(0.62), in: Capsule())
                    Text(Self.selectionTagLabel(selection))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }

            ScrollView(showsIndicators: false) {
                // Same order as immersive chat: messages → streaming → thinking.
                LazyVStack(alignment: .leading, spacing: 12) {
                    if visibleFloatingMessages.isEmpty && !(store.isAskingAgent && store.agentStreamingText.isEmpty) {
                        Text(store.ui("写下问题后发送，回答会出现在这里。", "Write a question and send — the reply appears here."))
                            .font(.system(size: 12))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(visibleFloatingMessages) { message in
                        floatBubble(
                            messageID: message.id,
                            roleLabel: message.role == .user ? store.ui("你", "You") : "WeiBei",
                            text: floatingText(for: message),
                            isUser: message.role == .user,
                            isError: WorkspaceStore.isAgentFailureMessage(message.text)
                        )
                    }

                    if store.isAskingAgent && !store.agentStreamingText.isEmpty {
                        floatStreamingBubble(text: store.agentStreamingText)
                            .id("selection-float-streaming")
                    }

                    if store.isAskingAgent && store.agentStreamingText.isEmpty {
                        AgentThinkingIndicator()
                            .id("selection-float-thinking")
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .environment(\.agentChatLayoutWidth, max(panelWidth - 28, 1))
            }
            .frame(minHeight: floatingFeedHeight, maxHeight: feedMaxHeight)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.45))
                    .frame(height: 1)
                AgentComposerField(
                    prompt: store.ui("问选区或继续追问", "Ask about selection…"),
                    focused: $draftFocused,
                    font: .system(size: 13.5),
                    promptFont: .system(size: 13.5),
                    lineLimit: 1...5,
                    height: 56,
                    sendButtonSize: 26,
                    trailingPadding: 36,
                    sendTrailing: 8,
                    sendBottom: 8,
                    horizontalPadding: 10,
                    verticalPadding: 8
                ) {
                    sendDraft()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .frame(width: panelWidth, alignment: .leading)
        .frame(minWidth: 420)
        .overlay(alignment: .bottomTrailing) {
            floatResizeHandle
        }
        .onAppear {
            draftFocused = true
        }
    }

    private var floatResizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(WeiBeiTheme.tertiaryInk.opacity(0.9))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .padding(6)
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeOriginWidth == 0 {
                            resizeOriginWidth = panelWidth
                            resizeOriginFeedHeight = feedMaxHeight
                        }
                        panelWidth = min(max(resizeOriginWidth + value.translation.width, 420), 720)
                        feedMaxHeight = min(max(resizeOriginFeedHeight + value.translation.height, 160), 640)
                    }
                    .onEnded { _ in
                        resizeOriginWidth = 0
                        resizeOriginFeedHeight = 0
                    }
            )
            .help(store.ui("拖拽调整选区对话大小", "Drag to resize selection chat"))
            .accessibilityLabel(Text(store.ui("调整选区对话大小", "Resize selection chat")))
    }

    private func floatBubble(messageID: UUID, roleLabel: String, text: String, isUser: Bool, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if isUser {
                Text(roleLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.link.opacity(0.85))
            } else {
                HStack(spacing: 6) {
                    Text("WeiBei")
                        .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                        .foregroundStyle(isError ? WeiBeiTheme.cinnabar : WeiBeiTheme.cinnabar.opacity(0.76))
                    if !isError {
                        Text("PI")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                    }
                }
            }
            if isError {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
            } else {
                // Same markdown path as immersive chat (`AgentMessageMarkdownText`).
                AgentMessageMarkdownText(
                    text: text,
                    rendersRichMarkdown: !isUser,
                    compact: true,
                    usesFinalizedKaTeX: !isUser,
                    messageID: messageID
                )
            }
        }
        .padding(.vertical, 3)
    }

    private func floatStreamingBubble(text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("WeiBei")
                    .font(WeiBeiTypography.englishBrandFont(size: 9.8, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.76))
                Text("PI")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            // Streaming: native text only (no KaTeX WebView mid-stream).
            AgentStreamingMarkdownText(text: text, compact: true)
        }
        .padding(.vertical, 3)
        .accessibilityLabel(Text(store.ui("PI 正在回答", "PI is responding")))
    }

    private static func selectionTagLabel(_ text: String, limit: Int = 18) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit)) + "…"
    }

    private var visibleFloatingMessages: [AgentMessage] {
        // Strict isolation: only messages belonging to the active selection-ask thread.
        // Never fall back to the global conversation feed.
        guard let threadID = store.activeSelectionAskThreadID,
              let thread = store.selectionAskThreads.first(where: { $0.id == threadID }) else {
            return []
        }
        let idSet = Set(thread.messageIDs)
        return store.messages.filter { idSet.contains($0.id) }
    }

    private var canPolishNoteSelection: Bool {
        store.selectionContext?.isNoteSelection == true
    }

    private var floatingFeedHeight: CGFloat {
        if store.isAskingAgent { return 160 }
        if visibleFloatingMessages.isEmpty { return 88 }
        switch visibleFloatingMessages.count {
        case 1: return 130
        case 2: return 200
        case 3: return 260
        default: return 320
        }
    }

    private func floatingText(for message: AgentMessage) -> String {
        if isCredentialNotice(message) {
            if isOfflineContextPreview(message) {
                return message.text
            }
            return store.ui("未配置密钥。设置后会结合\(store.agentPromptScope)和已选文本片段作答。", "No key is configured. After setup, answers will use \(store.agentPromptScope) and selected text fragments.")
        }
        return message.text
    }

    private func isCredentialNotice(_ message: AgentMessage) -> Bool {
        message.role == .assistant
            && (message.text.hasPrefix("未配置密钥") || message.text.hasPrefix("未配置 OPENAI_API_KEY") || message.text.hasPrefix("No key is configured"))
    }

    private func isOfflineContextPreview(_ message: AgentMessage) -> Bool {
        message.text.contains("## 离线草稿")
            || message.text.contains("## Offline Draft")
    }

    private func isGeneratedSelectionPrompt(_ message: AgentMessage) -> Bool {
        message.role == .user
            && (message.text.hasPrefix("请解释当前已选文本片段")
                || message.text.hasPrefix("请解释下面选区")
                || message.text.hasPrefix("请解释当前选区"))
    }

    private func togglePinnedFloatingAgent() {
        let next = !store.pinnedFloatingAgent
        store.pinnedFloatingAgent = next
        if next {
            store.agentSurface = .selectionFloat
            store.keepFloatingSelectionForAnswer = true
        } else {
            // Unpin must not dismiss — keepOpen holds the float without a drag anchor.
            store.keepFloatingSelectionForAnswer = true
            store.agentSurface = .selectionFloat
            expanded = true
        }
    }

    private func openExpandedComposer() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
            store.keepFloatingSelectionForAnswer = true
            // Do not invent a prompt or auto-send — only open a normal composer.
            store.askSelection()
            draftFocused = true
        }
    }

    private func openSourceReference() {
        store.openSelectedSourceReference()
    }

    private func sendDraft() {
        guard !store.isAskingAgent,
              !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        withAnimation(WeiBeiMotion.panel) {
            expanded = true
            store.keepFloatingSelectionForAnswer = true
            if let selection = store.selectionContext {
                store.addSelectionAttachment(selection)
                let thread = store.beginOrReuseSelectionAskThread(for: selection)
                store.activeSelectionAskThreadID = thread.id
            }
        }
        store.askAgent()
    }

    private func closeFloatingAgent() {
        withAnimation(WeiBeiMotion.panel) {
            expanded = false
            dragOffset = .zero
            settledOffset = .zero
            store.dismissFloatingSelectionAgent()
        }
    }
}

/// Paper float chrome: quieter radius; cinnabar edge only when pinned.
struct SelectionFloatChrome: ViewModifier {
    var expanded: Bool
    var pinned: Bool

    func body(content: Content) -> some View {
        content
            .foregroundColor(WeiBeiTheme.ink)
            .background {
                RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous)
                    .fill(WeiBeiTheme.paperRaised.opacity(0.98))
            }
            .clipShape(RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: expanded ? 12 : 9, style: .continuous)
                    .strokeBorder(
                        pinned ? WeiBeiTheme.cinnabar.opacity(0.34) : WeiBeiTheme.hairline.opacity(0.65),
                        lineWidth: 1
                    )
            }
            .shadow(color: WeiBeiTheme.ink.opacity(pinned ? 0.1 : 0.06), radius: pinned ? 12 : 8, y: pinned ? 4 : 3)
    }
}
