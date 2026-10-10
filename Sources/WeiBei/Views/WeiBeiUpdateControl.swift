import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit
#endif

/// One action in the toolbar; the attached hover surface is only for reading.
struct WeiBeiUpdateControl: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var updates: WeiBeiUpdateService
    @State private var showingNotes = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        if updates.showsToolbarControl, let update = updates.availableUpdate {
            Button {
                showingNotes = false
                updates.installAvailableUpdate()
            } label: {
                HStack(spacing: 5) {
                    indicator
                    if let progress = updates.downloadProgress, updates.status == .downloading {
                        Text(progress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                    } else if [.extracting, .ready, .saving, .installing, .failed].contains(updates.status) {
                        Text(updates.actionLabel(english: store.interfaceLanguage == .english))
                    }
                }
                .weiBeiText(12, weight: .medium)
                .foregroundStyle(WeiBeiTheme.cinnabar)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Keep hover readable during progress; the service rejects duplicate actions.
            .accessibilityLabel(updates.actionLabel(english: store.interfaceLanguage == .english))
            .accessibilityValue(updates.downloadProgress.map { "\(Int($0 * 100))%" } ?? "")
            .onHover(perform: hoverChanged)
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

    @ViewBuilder private var indicator: some View {
        if updates.status == .downloading, let progress = updates.downloadProgress {
            ZStack {
                Circle().stroke(WeiBeiTheme.hairline, lineWidth: 1.5)
                Circle().trim(from: 0, to: progress)
                    .stroke(WeiBeiTheme.cinnabar, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
        } else if updates.isBusy {
            ProgressView().controlSize(.mini)
                .frame(width: 14, height: 14)
        } else {
            Image(systemName: updates.status == .ready ? "arrow.clockwise" : updates.status == .failed ? "arrow.trianglehead.clockwise" : "arrow.down")
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

struct WeiBeiUpdateNotesPanel: View {
    let update: WeiBeiAvailableUpdate
    var error: String?
    var english = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("魏碑 \(update.version)")
                    .weiBeiText(13, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer(minLength: 12)
                if let date = update.publishedDate {
                    Text(date, format: .dateTime.year().month().day())
                        .weiBeiText(10.5)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }
            }
            Rectangle().fill(WeiBeiTheme.hairline).frame(height: 0.5)
            if let error {
                Text(error).weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                notes
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                    })
            }
            .scrollBounceBehavior(.basedOnSize)
            // Limit only the viewport; every actual note remains scrollable.
            .frame(height: min(contentHeight, 360))
        }
        .padding(16)
        .frame(width: 340)
        .background(WeiBeiTheme.paperRaised)
        .environment(\.locale, Locale(identifier: english ? "en" : "zh_CN"))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 9) {
            if update.releaseNotesLines.isEmpty {
                Text(english ? "Release notes are unavailable." : "暂无更新说明。")
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            ForEach(Array(update.releaseNotesLines.enumerated()), id: \.offset) { index, line in
                if WeiBeiAvailableUpdate.isHeading(line) {
                    Text(WeiBeiAvailableUpdate.displayText(line))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .padding(.top, index == 0 ? 0 : 5)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("·").foregroundStyle(WeiBeiTheme.tertiaryInk)
                        Text(line).foregroundStyle(WeiBeiTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .weiBeiText(12)
                    .lineSpacing(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
