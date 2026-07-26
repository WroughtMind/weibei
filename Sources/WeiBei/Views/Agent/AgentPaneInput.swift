import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

extension AgentPaneView {
    var agentPrompt: String {
        store.agentInputPrompt
    }

    func agentInputTray(wide: Bool, contentWidth: CGFloat) -> some View {
        let fieldHeight = AgentChatLayoutMetrics.composerHeight(wide: wide)
        let fontSize = AgentChatLayoutMetrics.composerFontSize(wide: wide)
        return VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .clear,
                    WeiBeiTheme.paper.opacity(0.18),
                    WeiBeiTheme.glassTint.opacity(0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: wide ? 16 : 22)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                if store.hasSelectionAttachments {
                    AgentSelectionAttachmentPill()
                        .transition(WeiBeiTransition.floating)
                }

                AgentComposerField(
                    prompt: agentPrompt,
                    focused: $draftFocused,
                    font: .system(size: fontSize),
                    promptFont: .system(size: fontSize),
                    lineLimit: wide ? 1...12 : 1...6,
                    height: fieldHeight,
                    sendButtonSize: wide ? 38 : 28,
                    trailingPadding: wide ? 56 : 40,
                    sendTrailing: wide ? 18 : 10,
                    sendBottom: wide ? 24 : 8,
                    horizontalPadding: wide ? 22 : 12,
                    verticalPadding: wide ? 20 : 8
                ) {
                    store.askAgent()
                }
            }
            .font(.system(size: fontSize))
            // Fixed width = reading column. Fixed height = real composer block.
            .frame(width: contentWidth, height: fieldHeight, alignment: .bottom)
            .padding(.top, wide ? 12 : 4)
            .padding(.bottom, wide ? 28 : 12)
            .frame(maxWidth: .infinity)
            .background(WeiBeiTheme.paper)
            .animation(WeiBeiMotion.reveal, value: store.agentDraft)
            .animation(WeiBeiMotion.panel, value: fieldHeight)
            .accessibilityIdentifier(wide ? "agent-input-tray-wide" : "agent-input-tray-compact")
        }
        .background(alignment: .bottom) {
            WeiBeiGlassHeaderBackground(
                paperOpacity: showsPaneHeader ? 0.34 : 0.14,
                materialOpacity: showsPaneHeader ? 0.04 : 0.02
            )
            .mask(
                LinearGradient(
                    colors: [.clear, WeiBeiTheme.ink.opacity(0.42), WeiBeiTheme.ink.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    var agentInputMaxWidth: CGFloat? {
        AgentChatLayoutMetrics.contentWidth(
            availableWidth: max(agentPaneWidth, 1),
            wide: usesWideChatLayout
        )
    }

    var agentContentMaxWidth: CGFloat? {
        agentInputMaxWidth
    }

    var composerFieldHeight: CGFloat {
        AgentChatLayoutMetrics.composerHeight(wide: usesWideChatLayout)
    }

    var composerFontSize: CGFloat {
        AgentChatLayoutMetrics.composerFontSize(wide: usesWideChatLayout)
    }

    var agentScrollBottomInset: CGFloat {
        // Fixed inset only — tray GeometryReader preference → LazyVStack height feedback
        // re-entered sizeThatFits every scroll frame and froze the app.
        // Tray already sits outside the ScrollView (VStack), so keep this small;
        // large fixed insets stole message viewport height and made immersive feel tiny.
        hasVisibleRichAnswer
            ? (usesWideChatLayout ? 28 : 20)
            : (usesWideChatLayout ? 16 : 12)
    }

    var hasVisibleRichAnswer: Bool {
        store.messages.contains { message in
            message.richAnswer?.mode == .rich && message.richAnswer?.scenes.isEmpty == false
        }
    }

    var agentRailBottomInset: CGFloat {
        usesWideChatLayout ? 120 : 100
    }

}
