import SwiftUI
#if targetEnvironment(macCatalyst)
import UIKit
#endif

/// One action in the toolbar; the attached hover surface is only for reading.
struct WeiBeiUpdateControl: View {
    @EnvironmentObject private var store: WorkspaceStore
    @EnvironmentObject private var updates: WeiBeiUpdateService
    @Environment(\.weiBeiTextScale) private var textScale
    @State private var showingNotes = false
    @State private var isHoveringButton = false
    @State private var isHoveringNotes = false
    @State private var suppressNotesUntilExit = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        if updates.showsToolbarControl, let update = updates.availableUpdate {
            Button {
                hoverTask?.cancel()
                suppressNotesUntilExit = isHoveringButton
                showingNotes = false
                updates.installAvailableUpdate()
            } label: {
                contentPill
            }
            .buttonStyle(WeiBeiUpdateButtonStyle(
                expanded: isExpanded, highlighted: isHoveringButton || showingNotes, accent: badgeColor))
            .disabled(updates.isBusy)
            .accessibilityLabel(updates.actionLabel(english: store.interfaceLanguage == .english))
            .accessibilityValue(updates.downloadProgress.map { "\(Int($0 * 100))%" } ?? "")
            .onHover { hovering in
                isHoveringButton = hovering
                if !hovering { suppressNotesUntilExit = false }
                updateNotesVisibility()
            }
#if targetEnvironment(macCatalyst)
            .background {
                UpdateNotesPopover(isPresented: $showingNotes, content: notesPanel(update))
            }
#else
            .popover(isPresented: $showingNotes, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                notesPanel(update)
                    .presentationBackground(.clear)
            }
#endif
            .onDisappear {
                hoverTask?.cancel()
                showingNotes = false
                isHoveringButton = false
                isHoveringNotes = false
                suppressNotesUntilExit = false
            }
        }
    }

    private func notesPanel(_ update: WeiBeiAvailableUpdate) -> some View {
        WeiBeiUpdateNotesPanel(update: update,
            error: updates.errorDescription,
            english: store.interfaceLanguage == .english)
            .environment(\.weiBeiTextScale, textScale)
            .preferredColorScheme(WeiBeiThemeRuntime.mode.isDark ? .dark : .light)
            .onHover { hovering in
                isHoveringNotes = hovering
                updateNotesVisibility()
            }
            .onDisappear { isHoveringNotes = false }
    }

    private var isExpanded: Bool {
        [.downloading, .ready, .failed, .extracting, .saving, .installing].contains(updates.status)
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
        HStack(spacing: 6) {
            statusBadge

            if isExpanded {
                textContent
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, isExpanded ? 5 : 3)
        .padding(.trailing, isExpanded ? 5 : 0)
        .frame(height: 30)
        .contentShape(Capsule())
        .animation(WeiBeiMotion.layout, value: isExpanded)
    }

    private var statusBadge: some View {
        ZStack {
            Circle().fill(badgeColor)

            if updates.status == .downloading, let progress = updates.downloadProgress {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.6)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(progress, 0), 1)))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 12, height: 12)
            } else if updates.isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.white)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: updates.status == .ready ? "arrow.clockwise"
                    : updates.status == .failed ? "arrow.trianglehead.clockwise" : "arrow.down.to.line")
                    .font(.system(size: isExpanded ? 10 : 11, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: isExpanded ? 20 : 24, height: isExpanded ? 20 : 24)
    }

    @ViewBuilder private var textContent: some View {
        if updates.status == .downloading, let progress = updates.downloadProgress {
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit()
                .weiBeiText(11.5, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
        } else {
            Text(updates.actionLabel(english: store.interfaceLanguage == .english))
                .weiBeiText(11.5, weight: .medium)
                .foregroundStyle(WeiBeiTheme.ink)
        }
    }

    private func updateNotesVisibility() {
        hoverTask?.cancel()
        if isHoveringButton || isHoveringNotes {
            guard !suppressNotesUntilExit else { return }
            // A brief dwell lets a direct click win before presenting reading content.
            guard !showingNotes else { return }
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                showingNotes = true
            }
        } else {
            // Keep the panel open while the pointer crosses the native arrow gap.
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                showingNotes = false
            }
        }
    }
}

private struct WeiBeiUpdateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var expanded: Bool
    var highlighted: Bool
    var accent: Color

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && isEnabled
        let shape = Capsule()
        return configuration.label
            .background {
                shape.fill(pressed ? WeiBeiTheme.paperInset
                    : highlighted || expanded ? WeiBeiTheme.paperRaised : .clear)
                if highlighted || pressed {
                    shape.fill(accent.opacity(pressed ? 0.20 : 0.10))
                }
            }
            .overlay {
                shape.strokeBorder(highlighted || pressed ? accent.opacity(pressed ? 0.75 : 0.55)
                    : expanded ? WeiBeiTheme.hairline : .clear, lineWidth: 1)
            }
            .shadow(color: accent.opacity(highlighted && isEnabled ? 0.22 : 0), radius: 4, y: 2)
            .scaleEffect(pressed ? 0.92 : highlighted && isEnabled ? 1.04 : 1)
            .animation(WeiBeiMotion.press, value: pressed)
            .animation(WeiBeiMotion.hover, value: highlighted)
    }
}

struct WeiBeiUpdateNotesPanel: View {
    let update: WeiBeiAvailableUpdate
    var error: String?
    var english = false
    @State private var contentHeight: CGFloat = 0
    private let viewportLimit: CGFloat = 310

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("魏碑 \(update.version)")
                    .weiBeiText(15, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.ink)
                Spacer(minLength: 0)
                if let date = update.publishedDate {
                    Text(date, format: .dateTime.year().month().day())
                        .weiBeiText(11)
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }
            }

            Rectangle().fill(WeiBeiTheme.hairline).frame(height: 0.5)

            if let error { errorBanner(error) }

            ScrollView {
                notes
                    .padding(.vertical, 2)
                    .background(GeometryReader { proxy in
                        Color.clear
                            .onAppear { contentHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                    })
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(contentHeight, viewportLimit))
        }
        .padding(18)
        .frame(width: 360)
        .weibeiFloatingPanel(cornerRadius: 12, shadowOpacity: 0.16)
        .environment(\.locale, Locale(identifier: english ? "en" : "zh_CN"))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
            Text(message)
                .weiBeiText(12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(WeiBeiTheme.cinnabar)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeiBeiTheme.cinnabarSoft, in: RoundedRectangle(cornerRadius: 7))
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 9) {
            if update.releaseNotesLines.isEmpty {
                Text(english ? "Fetching release notes…" : "正在获取更新说明…")
                    .weiBeiText(12)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            ForEach(Array(update.releaseNotesLines.enumerated()), id: \.offset) { index, line in
                if WeiBeiAvailableUpdate.isHeading(line) {
                    Text(LocalizedStringKey(WeiBeiAvailableUpdate.displayText(line)))
                        .weiBeiText(12, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.ink)
                        .padding(.top, index == 0 ? 0 : 9)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(WeiBeiTheme.tertiaryInk)
                        Text(LocalizedStringKey(line))
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .weiBeiText(12)
                    .lineSpacing(4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if targetEnvironment(macCatalyst)
/// The AppKit reading popover owns no modal input layer. UIKit's popover
/// dismissal can consume a real toolbar click even when passthrough is set.
struct UpdateNotesPopover<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let content: Content

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(content: AnyView(content), presented: isPresented) { isPresented = false }
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.stop() }

    final class Controller: UIViewController {
        private var content = AnyView(EmptyView())
        private var wantsPresentation = false
        private var active = true
        private var onDismiss: (() -> Void)?
        private var host: NotesHost?
        private var contentItem: NSUIViewToolbarItem?
        private var presentation: NSObject?

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); synchronize() }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); synchronize() }

        func update(content: AnyView, presented: Bool, onDismiss: @escaping () -> Void) {
            self.content = content
            wantsPresentation = presented
            self.onDismiss = onDismiss
            host?.rootView = content
            scheduleLayout()
        }
        private func scheduleLayout() {
            DispatchQueue.main.async { [weak self] in self?.synchronize() }
        }
        private func synchronize() {
            guard active else { return }
            guard wantsPresentation else { dismissPresentation(); return }
            guard view.window != nil,
                  let sourceItem = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .compactMap({ $0.titlebar?.toolbar }).flatMap({ $0.items })
                    .compactMap({ $0 as? NSUIViewToolbarItem })
                    .first(where: { view.isDescendant(of: $0.uiView) }) else { return }
            if host == nil {
                let host = NotesHost(rootView: content)
                host.safeAreaRegions = []
                host.sizingOptions = [.preferredContentSize]
                host.view.backgroundColor = .clear
                host.sizeChanged = { [weak self] in self?.scheduleLayout() }
                self.host = host
                contentItem = NSUIViewToolbarItem(itemIdentifier: .init("weibei.update.notes"), uiView: host.view)
            }
            guard let host, let contentItem else { return }
            let size = host.sizeThatFits(in: UIView.layoutFittingExpandedSize)
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
            let rect = view.convert(view.bounds, to: sourceItem.uiView)
            let dark = WeiBeiThemeRuntime.mode.isDark
            if let presentation {
                CatalystDesktopWindow.shared.updateUpdateNotes(presentation, sourceRect: rect, size: size, dark: dark)
            } else {
                presentation = CatalystDesktopWindow.shared.presentUpdateNotes(contentItem: contentItem,
                    sourceItem: sourceItem, sourceRect: rect, size: size, dark: dark) { [weak self] in
                        guard let self else { return }
                        self.presentation = nil
                        self.wantsPresentation = false
                        self.onDismiss?()
                    }
            }
        }
        private func dismissPresentation() {
            let previous = presentation
            presentation = nil
            if let previous { CatalystDesktopWindow.shared.dismissUpdateNotes(previous) }
            host?.sizeChanged = nil
            contentItem = nil
            host = nil
        }
        func stop() { active = false; dismissPresentation() }

        private final class NotesHost: UIHostingController<AnyView> {
            var sizeChanged: (() -> Void)?
            override var preferredContentSize: CGSize {
                didSet { if oldValue != preferredContentSize { sizeChanged?() } }
            }
        }
    }
}
#endif
