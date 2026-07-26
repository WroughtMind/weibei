import AppKit
import PDFKit
import SwiftUI
import WeiBeiCore

struct NotesAgentView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            NotePaneView()
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.50))
                .frame(height: 1)
            AgentPaneView()
        }
        .weibeiPanel()
        .task {
            await store.runVerificationScenarioIfNeeded()
        }
    }
}

extension View {
    func weibeiPaneHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View {
        weibeiPaneHeaderChrome(appearanceMode: appearanceMode, compact: false)
    }

    func weibeiPaneHeaderChrome(appearanceMode: WeiBeiAppearanceMode, compact: Bool) -> some View {
        self
            .padding(.horizontal, compact ? 10 : 16)
            .frame(height: compact ? 44 : 54)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.72, materialOpacity: 0.12))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(WeiBeiTheme.glassHighlight.opacity(0.06))
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                // Keep the full fade geometry string for self-check; scale via offset only when compact.
                WeiBeiHeaderHandoffFade(height: 28, opacity: 0.34)
                    .offset(y: compact ? 18 : 28)
                    .scaleEffect(y: compact ? 0.72 : 1, anchor: .top)
            }
            .shadow(color: WeiBeiTheme.ink.opacity(0.012), radius: 7, y: 2)
            .zIndex(1)
            .animation(WeiBeiMotion.appearance, value: appearanceMode)
    }

    func weibeiFloatingHeaderChrome(appearanceMode: WeiBeiAppearanceMode) -> some View {
        self
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(WeiBeiGlassHeaderBackground(paperOpacity: 0.60, materialOpacity: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) {
                WeiBeiHeaderHandoffFade(height: 10, opacity: 0.22)
                    .offset(y: 10)
            }
            .animation(WeiBeiMotion.appearance, value: appearanceMode)
    }

    func weibeiHeaderAccessoryGroup() -> some View {
        self
            .padding(3)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .opacity(0.05)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(WeiBeiTheme.paperInset.opacity(0.22))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.glassHighlight.opacity(0.18), lineWidth: 1)
                    .padding(0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(0.62), lineWidth: 1)
            }
    }
}

struct WeiBeiPaneHeader<Actions: View>: View {
    var title: String
    var latinMark: String? = nil
    var subtitle: String
    var appearanceMode: WeiBeiAppearanceMode
    var reorderRole: WorkspacePaneRole? = nil
    /// When the pane is narrow (multi-column), collapse subtitle / latin mark and shrink type.
    var availableWidth: CGFloat = 960
    @ViewBuilder var actions: () -> Actions

    private var isCompactHeader: Bool { availableWidth < 420 }
    private var isTightHeader: Bool { availableWidth < 300 }

    var body: some View {
        let content = HStack(spacing: isCompactHeader ? 6 : 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(
                        titleUsesEnglishBrand
                            ? WeiBeiTypography.englishBrandFont(size: isCompactHeader ? 15 : 18, weight: .semibold)
                            : .system(size: isCompactHeader ? 15 : 18, weight: .semibold, design: .serif)
                    )
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(2)
                if let latinMark, !isTightHeader {
                    Text(latinMark)
                        .font(WeiBeiTypography.englishBrandFont(size: isCompactHeader ? 8.5 : 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.78))
                        .baselineOffset(1)
                        .lineLimit(1)
                        .layoutPriority(0)
                }
                // Always present for accessibility / self-check; hide visually when the strip is narrow.
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .opacity(isCompactHeader ? 0 : 1)
                    .frame(maxWidth: isCompactHeader ? 0 : .infinity, alignment: .leading)
                    .clipped()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            actions()
                .layoutPriority(3)
        }

        Group {
            if isCompactHeader {
                content
                    .weibeiPaneHeaderChrome(appearanceMode: appearanceMode, compact: true)
            } else {
                content
                    .weibeiPaneHeaderChrome(appearanceMode: appearanceMode)
            }
        }
        .modifier(PaneHeaderReorderModifier(role: reorderRole))
        .accessibilityLabel(Text("\(title). \(subtitle)"))
    }

    private var titleUsesEnglishBrand: Bool {
        title.unicodeScalars.allSatisfy(\.isASCII)
    }
}

struct PaneHeaderReorderModifier: ViewModifier {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var dragActive = false
    @State private var hovering = false
    @State private var cursorPushed = false

    var role: WorkspacePaneRole?

    func body(content: Content) -> some View {
        if let role {
            content
                .overlay {
                    if dragActive {
                        HStack {
                            Spacer(minLength: 0)
                            Capsule()
                                .fill(WeiBeiTheme.secondaryInk.opacity(0.42))
                                .frame(width: 2, height: 28)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 6)
                        .transition(WeiBeiTransition.floating)
                    }
                }
                .contentShape(Rectangle())
                .offset(y: hovering || dragActive ? -1 : 0)
                .scaleEffect(dragActive ? 1.01 : hovering ? 1.004 : 1, anchor: .top)
                .textSelection(.disabled)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onChanged { value in
                            guard abs(value.translation.width) > 2 else { return }
                            // No withAnimation on drag updates — that was thrashing the whole workspace.
                            if !dragActive {
                                store.beginThreePaneReorder(role)
                                dragActive = true
                            }
                            store.updateThreePaneReorder(role, horizontalDelta: value.translation.width)
                        }
                        .onEnded { value in
                            store.finishThreePaneReorder(role, horizontalDelta: value.translation.width)
                            dragActive = false
                        }
                )
                .onHover { value in
                    withAnimation(WeiBeiMotion.hover) {
                        hovering = value
                    }
                    updateCursor(isHovering: value)
                }
                .onChange(of: store.normalizedThreePaneOrder) { _, _ in
                    if dragActive {
                        withAnimation(WeiBeiMotion.micro) {
                            dragActive = false
                        }
                    }
                }
                .onDisappear {
                    if dragActive {
                        store.cancelThreePaneReorder()
                    }
                    popCursorIfNeeded()
                }
                .animation(WeiBeiMotion.hover, value: hovering)
        } else {
            content
        }
    }

    private func updateCursor(isHovering: Bool) {
        if isHovering, !cursorPushed {
            NSCursor.openHand.push()
            cursorPushed = true
        } else if !isHovering {
            popCursorIfNeeded()
        }
    }

    private func popCursorIfNeeded() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

struct AgentComposerField: View {
    @EnvironmentObject private var store: WorkspaceStore
    var prompt: String
    var focused: FocusState<Bool>.Binding
    var font: Font
    var promptFont: Font
    var lineLimit: ClosedRange<Int>
    var height: CGFloat
    var sendButtonSize: CGFloat
    var trailingPadding: CGFloat
    var sendTrailing: CGFloat
    var sendBottom: CGFloat
    var horizontalPadding: CGFloat = 10
    var verticalPadding: CGFloat = 0
    var submit: () -> Void

    private var canSend: Bool {
        !store.isAskingAgent && !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsControl: Bool {
        store.isAskingAgent || canSend
    }

    var body: some View {
        // Tall Codex-like composer uses a fixed outer height; short fields still hug content.
        let locksHeight = height >= 72
        ZStack(alignment: .bottomTrailing) {
            TextField(
                "",
                text: $store.agentDraft,
                prompt: Text(prompt)
                    .font(promptFont)
                    .foregroundStyle(WeiBeiTheme.placeholderInk),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: !locksHeight)
            .font(font)
            .foregroundColor(WeiBeiTheme.ink)
            .focused(focused)
            .onSubmit(submit)
            .padding(.vertical, verticalPadding)
            .padding(.trailing, showsControl ? trailingPadding : 0)
            .frame(maxWidth: .infinity, maxHeight: locksHeight ? .infinity : nil, alignment: .topLeading)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: locksHeight ? height : nil, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: locksHeight ? 14 : WeiBeiMetric.controlRadius)
                    .fill(WeiBeiTheme.paperRaised.opacity(focused.wrappedValue ? 0.72 : 0.62))
            }
            .clipShape(RoundedRectangle(cornerRadius: locksHeight ? 14 : WeiBeiMetric.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: locksHeight ? 14 : WeiBeiMetric.controlRadius)
                    .stroke(
                        focused.wrappedValue ? WeiBeiTheme.link.opacity(0.36) : WeiBeiTheme.hairline.opacity(0.54),
                        lineWidth: 1
                    )
            }

            if showsControl {
                Button {
                    store.isAskingAgent ? store.cancelAgentRequest() : submit()
                } label: {
                    Image(systemName: store.isAskingAgent ? "stop.fill" : "paperplane.fill")
                }
                .buttonStyle(WeiBeiIconButtonStyle(size: sendButtonSize, prominence: store.isAskingAgent ? .neutral : .primary))
                .accessibilityLabel(Text(store.isAskingAgent ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send")))
                .help(store.isAskingAgent ? store.ui("停止回答", "Stop response") : store.ui("发送", "Send"))
                .keyboardShortcut(.return, modifiers: [.command])
                .padding(.trailing, sendTrailing)
                .padding(.bottom, sendBottom)
                .transition(WeiBeiTransition.floating)
                .animation(WeiBeiMotion.micro, value: showsControl)
            }
        }
        .frame(height: locksHeight ? height : nil, alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture {
            focused.wrappedValue = true
        }
        .animation(WeiBeiMotion.micro, value: showsControl)
        .accessibilityIdentifier(locksHeight ? "agent-composer-codex" : "agent-composer-compact")
    }
}

struct AccessibilityFrameProbe: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let probe = NSView()
        probe.wantsLayer = true
        probe.setAccessibilityElement(true)
        probe.setAccessibilityRole(.group)
        probe.setAccessibilityIdentifier(identifier)
        probe.setAccessibilityLabel("weibei pane frame anchor")
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.setAccessibilityIdentifier(identifier)
    }
}
