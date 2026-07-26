import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct AgentRailTurn {
    var id: UUID
    var startMessageID: UUID
    var startIndex: Int
    var question: String
    var answer: String
}

/// Standard chat column metrics — one centered axis shared by messages and composer.
/// Compact = three-pane agent strip; wide = immersive conversation (Codex-like full chat).
///
/// Critical: content width must always fit the measured pane. Never invent a floor larger
/// than `availableWidth`, or multi-pane text centers as if the strip were full-window wide.
enum AgentChatLayoutMetrics {
    static let compactMaxWidth: CGFloat = 560
    /// Immersive conversation: nearly full pane (not a skinny centered strip).
    static let wideMaxWidth: CGFloat = 1600
    static let compactSideGutter: CGFloat = 12
    /// Tight gutters so the reading column owns the immersive canvas.
    static let wideSideGutter: CGFloat = 48
    static let compactComposerHeight: CGFloat = 52
    /// Tall real composer — empty state must still read as a writing surface, not a search field.
    static let wideComposerHeight: CGFloat = 148
    static let compactFontSize: CGFloat = 14.5
    static let wideFontSize: CGFloat = 17

    static func isWide(layout: WorkspaceLayout) -> Bool {
        // Immersive conversation only — document multi-pane keeps compact strip metrics.
        layout == .immersiveConversation
    }

    static func contentWidth(availableWidth: CGFloat, wide: Bool) -> CGFloat {
        let gutter = (wide ? wideSideGutter : compactSideGutter) * 2
        let usable = max(availableWidth - gutter, 1)
        // Wide: use nearly the whole measured pane (gutter only). Cap only for ultra-wide displays.
        if wide {
            return min(usable, wideMaxWidth)
        }
        return min(usable, compactMaxWidth)
    }

    static func composerHeight(wide: Bool) -> CGFloat {
        wide ? wideComposerHeight : compactComposerHeight
    }

    static func composerFontSize(wide: Bool) -> CGFloat {
        wide ? wideFontSize : compactFontSize
    }
}

struct AgentPaneView: View {
    @EnvironmentObject var store: WorkspaceStore
    var showsPaneHeader = true
    var reorderRole: WorkspacePaneRole? = nil
    @FocusState var draftFocused: Bool
    @State var activeAgentRailID: String?
    @State var agentFollowsLatest = true
    /// Live pane width from a background probe. 0 until first real measurement.
    @State var measuredPaneWidth: CGFloat = 0

    let agentBottomAnchorID = "agentConversationBottom"

    var isImmersiveConversation: Bool {
        store.layout == .immersiveConversation
    }

    var usesWideChatLayout: Bool {
        AgentChatLayoutMetrics.isWide(layout: store.layout)
    }

    /// Prefer a measured width; for immersive before the first probe, seed wide so we do not flash the three-pane strip size.
    var agentPaneWidth: CGFloat {
        if measuredPaneWidth > 1 {
            return measuredPaneWidth
        }
        return usesWideChatLayout ? 1100 : 360
    }

    var body: some View {
        // Hang-proof structure:
        // NEVER put GeometryReader as an ancestor of ScrollView+LazyVStack.
        // Sampled freezes were GeometryReaderLayout → ScrollView.sizeThatFits → LazyVStack thrash.
        // Pane width is measured only via background preference (sibling, not parent).
        let wide = AgentChatLayoutMetrics.isWide(layout: store.layout)
        let availableWidth = max(agentPaneWidth, 1)
        let railOnly = ContentRailMetrics.isRailOnly(
            availableWidth: availableWidth,
            allowed: store.layout.allowsRailOnlyPanes
        )
        let showsContentRail = !wide && store.layout.allowsRailOnlyPanes
        let railItems = showsContentRail ? agentRailItems : []
        let contentWidth = AgentChatLayoutMetrics.contentWidth(
            availableWidth: availableWidth,
            wide: wide
        )
        let geometryWidth = availableWidth
        let headerHeight: CGFloat = showsPaneHeader
            ? (availableWidth < 420 ? 44 : 54)
            : 0

        ScrollViewReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    if showsPaneHeader {
                        WeiBeiPaneHeader(
                            title: store.ui("对话", "Chat"),
                            latinMark: store.interfaceLanguage == .chinese ? "CHAT" : nil,
                            subtitle: store.agentConversationSubtitle,
                            appearanceMode: store.appearanceMode,
                            reorderRole: reorderRole,
                            availableWidth: availableWidth
                        ) {
                            sessionMenu
                        }
                    }

                    ScrollView(showsIndicators: true) {
                        // No scrollTargetLayout / scrollPosition / minHeight:viewport /
                        // GeometryReader parent — all thrash sizeThatFits on LazyVStack.
                        LazyVStack(alignment: .leading, spacing: wide ? 16 : 12) {
                            ForEach(store.messages) { message in
                                agentMessageRow(
                                    message: message,
                                    geometryWidth: geometryWidth,
                                    contentWidth: contentWidth,
                                    wide: wide
                                )
                            }
                            if store.isAskingAgent && !store.agentStreamingText.isEmpty {
                                agentReadingColumn(
                                    geometryWidth: geometryWidth,
                                    contentWidth: contentWidth,
                                    wideLayout: wide,
                                    alignment: .leading
                                ) {
                                    AgentStreamingResponse(text: store.agentStreamingText)
                                }
                                .id("agent-streaming-response")
                                .transition(WeiBeiTransition.message)
                            }
                            if store.isAskingAgent && store.agentStreamingText.isEmpty {
                                agentReadingColumn(
                                    geometryWidth: geometryWidth,
                                    contentWidth: contentWidth,
                                    wideLayout: wide,
                                    alignment: .leading
                                ) {
                                    AgentThinkingIndicator()
                                }
                                .id("agent-thinking")
                                .transition(WeiBeiTransition.message)
                            }
                            if store.messages.isEmpty && !(store.isAskingAgent && store.agentStreamingText.isEmpty) {
                                emptyAgentState
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(WeiBeiTransition.message)
                            }
                            Color.clear
                                .frame(height: agentScrollBottomInset)
                                .id(agentBottomAnchorID)
                        }
                        .padding(.horizontal, wide ? 16 : 10)
                        .padding(.vertical, wide ? 10 : 10)
                        .environment(\.agentChatLayoutWidth, contentWidth)
                        .padding(.top, store.messages.isEmpty ? 22 : 0)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .zIndex(0)

                    agentInputTray(wide: wide, contentWidth: contentWidth)
                        .zIndex(1)
                        .animation(WeiBeiMotion.panel, value: store.layout)
                        .animation(WeiBeiMotion.panel, value: wide)
                }
                .opacity(railOnly ? 0 : 1)
                .allowsHitTesting(!railOnly)

                if showsContentRail {
                    ContentRailView(
                        label: store.ui("对话轨道", "Conversation rail"),
                        items: railItems,
                        activeID: activeAgentRailID ?? railItems.first?.id,
                        appearanceMode: store.appearanceMode,
                        isRailOnly: railOnly,
                        availableWidth: availableWidth,
                        topInset: railOnly ? 0 : headerHeight,
                        bottomInset: railOnly ? 0 : agentRailBottomInset,
                        onActivate: { activateAgentRailItem($0, railOnly: railOnly, proxy: proxy) }
                    )
                    .zIndex(4)
                }
            }
            .onChange(of: store.messages.count) { _, _ in
                if showsContentRail, let lastID = store.messages.last?.id {
                    updateAgentRailPosition(for: lastID)
                }
                scrollAgentToBottom(proxy)
            }
            .onRichAnswerVerificationStage { stage in
                handleRichAnswerVerificationStage(stage, proxy: proxy)
            }
        }
        // Width probe as background sibling — never parent of ScrollView.
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: AgentPaneWidthKey.self,
                    value: geo.size.width
                )
            }
        }
        .onPreferenceChange(AgentPaneWidthKey.self) { width in
            applyMeasuredPaneWidth(width)
        }
        .onChange(of: store.layout) { _, layout in
            // Entering immersive: seed wide so we never flash the last three-pane strip width.
            // Leaving immersive: drop to 0 so the next probe owns the multi-pane strip.
            if layout == .immersiveConversation {
                if measuredPaneWidth < 700 {
                    measuredPaneWidth = max(measuredPaneWidth, 1100)
                }
            } else if measuredPaneWidth > 700 {
                // Drop stale full-window width; real strip measure arrives next frame.
                measuredPaneWidth = 0
            }
        }
        .frame(minHeight: 260)
        .foregroundStyle(WeiBeiTheme.ink)
        // Same opaque paper as notes/reader — clear background lets
        // isMovableByWindowBackground steal header drags as window moves.
        .background(WeiBeiTheme.paper)
        .overlay(alignment: .topLeading) {
            AccessibilityFrameProbe(identifier: "stable-document-slot-agent")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if showsPaneHeader {
                LinearGradient(
                    colors: [
                        WeiBeiTheme.glassHighlight.opacity(0.18),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 10)
                .allowsHitTesting(false)
            } else {
                // Match notes: floating slip overlay only — no extra clear ZStack.
                ImmersiveHoverTitleView(
                    mark: "CHAT",
                    title: store.agentConversationSubtitle,
                    appearanceMode: store.appearanceMode,
                    actionsAlignedTrailing: true,
                    reorderRole: reorderRole
                ) {
                    agentSessionCatalogMenu
                }
            }
        }
        .onChange(of: store.focusRequest) { _, _ in
            draftFocused = store.focusedPane == .agent
        }
        .onAppear {
            draftFocused = store.focusedPane == .agent
            if usesWideChatLayout, measuredPaneWidth < 700 {
                measuredPaneWidth = max(measuredPaneWidth, 1100)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stable-document-slot-agent")
        .accessibilityLabel(Text("agent chat pane"))
    }

    /// Accept real pane measures; ignore transient shrinks while immersive (host re-attach).
    func applyMeasuredPaneWidth(_ width: CGFloat) {
        guard width > 1 else { return }
        if usesWideChatLayout {
            // PersistentPaneHost re-attach can briefly report the old strip width — do not keep it.
            if width < 520, measuredPaneWidth >= 700 {
                return
            }
        }
        guard abs(measuredPaneWidth - width) > 0.5 else { return }
        measuredPaneWidth = width
    }

}
