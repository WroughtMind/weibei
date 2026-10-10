import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit
#endif

/// One action in the toolbar; the attached hover surface is only for reading.
struct WeiBeiUpdateControl: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var updates: WeiBeiUpdateService
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingNotes = false
    @State private var isHoveringButton = false
    @State private var dismissTask: Task<Void, Never>?

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        if updates.showsToolbarControl, let update = updates.availableUpdate {
            Button {
                showingNotes = false
                updates.installAvailableUpdate()
            } label: {
                contentPill
            }
            .buttonStyle(WeiBeiUpdateButtonStyle())
            // Keep hover readable during progress; the service rejects duplicate actions.
            .accessibilityLabel(updates.actionLabel(english: store.interfaceLanguage == .english))
            .accessibilityValue(updates.downloadProgress.map { "\(Int($0 * 100))%" } ?? "")
            .onHover { hovering in
                isHoveringButton = hovering
                hoverChanged(hovering)
            }
            .popover(isPresented: $showingNotes, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                WeiBeiUpdateNotesPanel(update: update,
                    error: updates.errorDescription,
                    english: store.interfaceLanguage == .english)
                    .onHover(perform: hoverChanged)
                    .presentationBackground(WeiBeiTheme.paperRaised)
#if targetEnvironment(macCatalyst)
                    .presentationCompactAdaptation(.popover)
                    .background(UpdatePopoverPassthrough())
#endif
            }
            .onDisappear {
                dismissTask?.cancel()
                showingNotes = false
            }
        }
    }

    private var isExpanded: Bool {
        updates.status == .downloading || updates.status == .ready || updates.status == .failed || updates.status == .extracting || updates.status == .saving || updates.status == .installing
    }

    private var badgeColor: Color {
        switch updates.status {
        case .ready:
            return Color(red: 0.16, green: 0.74, blue: 0.46)
        case .failed:
            return Color(red: 0.90, green: 0.28, blue: 0.24)
        default:
            return Color(red: 0.92, green: 0.35, blue: 0.24)
        }
    }

    private var contentPill: some View {
        HStack(spacing: 5.5) {
            statusBadge

            if isExpanded {
                textContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.leading, isExpanded ? 3.5 : 0)
        .padding(.trailing, isExpanded ? 8.5 : 0)
        .frame(height: 24)
        .background {
            if isExpanded {
                Capsule()
                    .fill(
                        isDark
                            ? Color(white: 0.18).opacity(isHoveringButton || showingNotes ? 0.95 : 0.82)
                            : Color(white: 0.93).opacity(isHoveringButton || showingNotes ? 1.0 : 0.88)
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                isHoveringButton || showingNotes ? badgeColor.opacity(0.40) : (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)),
                                lineWidth: 0.6
                            )
                    }
                    .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.06), radius: 2, y: 1)
            }
        }
        .scaleEffect(isHoveringButton ? 1.03 : 1.0)
        .animation(WeiBeiMotion.hover, value: isHoveringButton)
        .animation(WeiBeiMotion.layout, value: isExpanded)
        .contentShape(Rectangle())
    }

    private var statusBadge: some View {
        ZStack {
            Circle()
                .fill(badgeColor)
                .frame(width: isExpanded ? 18 : 24, height: isExpanded ? 18 : 24)
                .shadow(
                    color: badgeColor.opacity(isHoveringButton || showingNotes ? 0.45 : 0.22),
                    radius: isHoveringButton ? 3 : 1.5,
                    y: 1
                )

            if updates.status == .downloading, let progress = updates.downloadProgress {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.6)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(progress, 0.05), 1.0)))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12)
            } else if updates.isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                    .frame(width: 12, height: 12)
            } else if updates.status == .ready {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.white)
            } else if updates.status == .failed {
                Image(systemName: "arrow.trianglehead.clockwise")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.white)
            } else {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: isExpanded ? 9.5 : 11, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: isExpanded ? 18 : 24, height: isExpanded ? 18 : 24)
    }

    @ViewBuilder
    private var textContent: some View {
        if updates.status == .downloading, let progress = updates.downloadProgress {
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.85))
        } else {
            Text(updates.actionLabel(english: store.interfaceLanguage == .english))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isDark ? Color.white.opacity(0.92) : Color.black.opacity(0.85))
        }
    }

    private func hoverChanged(_ hovering: Bool) {
        dismissTask?.cancel()
        if hovering {
            showingNotes = true
        } else {
            // Let the pointer cross the small native popover gap without losing it.
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                showingNotes = false
            }
        }
    }
}

/// Tactile button press feedback for the toolbar update button
private struct WeiBeiUpdateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(WeiBeiMotion.press, value: configuration.isPressed)
    }
}

struct WeiBeiUpdateNotesPanel: View {
    let update: WeiBeiAvailableUpdate
    var error: String?
    var english = false
    @State private var contentHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private let viewportLimit: CGFloat = 310

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            headerView

            Rectangle()
                .fill(WeiBeiTheme.hairline)
                .frame(height: 0.5)

            if let error {
                errorBanner(error)
            }

            ScrollView {
                notes
                    .padding(.vertical, contentHeight > viewportLimit ? 4 : 0)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                    })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, viewportLimit))
            .mask {
                VStack(spacing: 0) {
                    Rectangle().fill(Color.black)

                    if contentHeight > viewportLimit {
                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 12)
                    }
                }
            }
        }
        .padding(15)
        .frame(width: 348)
        .background(WeiBeiTheme.paperRaised)
        .environment(\.locale, Locale(identifier: english ? "en" : "zh_CN"))
    }

    private var headerView: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("魏碑 \(update.version)")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)

            Spacer(minLength: 12)

            if let date = update.publishedDate {
                Text(date, format: .dateTime.year().month().day())
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(WeiBeiTheme.cinnabar)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.cinnabar.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            if update.releaseNotesLines.isEmpty {
                Text(english ? "Fetching release notes…" : "正在获取更新说明…")
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            ForEach(Array(update.releaseNotesLines.enumerated()), id: \.offset) { index, line in
                if WeiBeiAvailableUpdate.isHeading(line) {
                    headingRow(line, isFirst: index == 0)
                } else {
                    bulletRow(line)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headingRow(_ line: String, isFirst: Bool) -> some View {
        let title = WeiBeiAvailableUpdate.displayText(line)
        let color = headingColor(title)
        return HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 3, height: 11)
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
        }
        .padding(.top, isFirst ? 0 : 7)
    }

    private func headingColor(_ title: String) -> Color {
        if title.contains("新增") || title.contains("New") {
            return Color(red: 0.16, green: 0.74, blue: 0.46)
        } else if title.contains("改进") || title.contains("优化") || title.contains("Improvements") {
            return Color(red: 0.24, green: 0.60, blue: 0.98)
        } else if title.contains("修复") || title.contains("Fixed") || title.contains("Fixes") {
            return Color(red: 0.94, green: 0.52, blue: 0.18)
        }
        return WeiBeiTheme.tertiaryInk
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(WeiBeiTheme.tertiaryInk.opacity(0.7))
                .frame(width: 3.5, height: 3.5)
                .offset(y: -1.5)
            Text(LocalizedStringKey(text))
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if targetEnvironment(macCatalyst)
/// UIKit otherwise consumes the first click outside a presented popover.
/// Passing through its source view keeps the hovered update button actionable.
private struct UpdatePopoverPassthrough: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.configure() }
    final class Probe: UIView {
        override func didMoveToWindow() { super.didMoveToWindow(); configure() }
        func configure() {
            DispatchQueue.main.async { [weak self] in
                var responder: UIResponder? = self
                while let current = responder {
                    if let controller = current as? UIViewController,
                       let popover = controller.popoverPresentationController,
                       let source = popover.sourceView {
                        popover.passthroughViews = [source]
                        return
                    }
                    responder = current.next
                }
            }
        }
    }
}
#endif
