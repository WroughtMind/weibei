import AppKit
import SwiftUI
import WeiBeiCore

private enum EmptyWorkspaceLayoutMetrics {
    static let compactWidthThreshold: CGFloat = 1140
    static let compactHeightThreshold: CGFloat = 680
    static let entryCenterRatio: CGFloat = 0.402
    static let inspirationCenterRatio: CGFloat = 0.66
    static let contentMaxWidth: CGFloat = 760
    static let inspirationMaxWidth: CGFloat = 660
    static let inspirationSlotHeight: CGFloat = 210
    static let compactInspirationSlotHeight: CGFloat = 176
}

struct EmptyWorkspaceLauncherView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedInspirationID: String?
    /// Bumped on theme change so a long-lived NSHostingView cannot keep a stale paper snapshot.
    @State private var appearanceEpoch = 0

    private var liveAppearanceMode: WeiBeiAppearanceMode { store.appearanceMode }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            GeometryReader { geometry in
                let compact = geometry.size.width < EmptyWorkspaceLayoutMetrics.compactWidthThreshold
                    || geometry.size.height < EmptyWorkspaceLayoutMetrics.compactHeightThreshold
                let horizontalPadding: CGFloat = compact ? 24 : 52
                let entryWidth = min(116, max(76, (geometry.size.width - (horizontalPadding * 2) - 2) / 3))
                let inspirationSlotHeight = compact
                    ? EmptyWorkspaceLayoutMetrics.compactInspirationSlotHeight
                    : EmptyWorkspaceLayoutMetrics.inspirationSlotHeight
                let currentInspiration = inspiration(at: timeline.date)
                let mode = liveAppearanceMode

                ZStack {
                    EmptyWorkspacePaperField(mode: mode, compact: compact)

                    workspaceContent(
                        at: timeline.date,
                        inspiration: currentInspiration,
                        availableSize: geometry.size,
                        compact: compact,
                        horizontalPadding: horizontalPadding,
                        entryWidth: entryWidth,
                        inspirationSlotHeight: inspirationSlotHeight
                    )
                }
                // Rebuild the board when theme changes — long-lived NSHostingView
                // does not always re-resolve ambient WeiBeiTheme Color snapshots.
                .id("\(mode.rawValue)-\(appearanceEpoch)")
            }
        }
        .background(EmptyWorkspaceResolvedColor.paper(liveAppearanceMode))
        // One rebuild trigger only — onChange + didChangeNotification used to fire
        // twice per switch and made the empty board lag the rest of the chrome.
        .onChange(of: store.appearanceMode) { _, _ in
            appearanceEpoch &+= 1
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-workspace-launcher")
    }

    @ViewBuilder
    private func workspaceContent(
        at date: Date,
        inspiration: EmptyWorkspaceInspiration,
        availableSize: CGSize,
        compact: Bool,
        horizontalPadding: CGFloat,
        entryWidth: CGFloat,
        inspirationSlotHeight: CGFloat
    ) -> some View {
        let contentWidth = max(
            1,
            min(EmptyWorkspaceLayoutMetrics.contentMaxWidth, availableSize.width - horizontalPadding * 2)
        )
        let entryHeight: CGFloat = compact ? 84 : 98
        let entryCenterRatio: CGFloat = store.showDailyInspiration ? EmptyWorkspaceLayoutMetrics.entryCenterRatio : 0.5
        let entryCenterY = clampedCenterY(
            ratio: entryCenterRatio,
            elementHeight: entryHeight,
            availableHeight: availableSize.height,
            edgeInset: compact ? 14 : 20
        )
        let minimumInspirationCenterY = max(
            clampedCenterY(
                ratio: EmptyWorkspaceLayoutMetrics.inspirationCenterRatio,
                elementHeight: inspirationSlotHeight,
                availableHeight: availableSize.height,
                edgeInset: compact ? 12 : 18
            ),
            entryCenterY + entryHeight / 2 + (compact ? 12 : 20) + inspirationSlotHeight / 2
        )
        let inspirationCenterY = min(
            minimumInspirationCenterY,
            availableSize.height - (compact ? 12 : 18) - inspirationSlotHeight / 2
        )

        ZStack {
            entryCluster(
                at: date,
                compact: compact,
                spacing: store.showDailyInspiration ? (compact ? 18 : 26) : (compact ? 16 : 29),
                entryWidth: entryWidth
            )
            .frame(width: contentWidth)
            .position(x: availableSize.width / 2, y: entryCenterY)

            if store.showDailyInspiration {
                ZStack {
                    EmptyWorkspaceInspirationView(
                        inspiration: inspiration,
                        compact: compact,
                        onAdvance: { advanceInspiration(from: inspiration.id) }
                    )
                    .id(inspiration.id)
                    .transition(.opacity)
                }
                .frame(
                    width: min(EmptyWorkspaceLayoutMetrics.inspirationMaxWidth, contentWidth),
                    height: inspirationSlotHeight
                )
                .position(x: availableSize.width / 2, y: inspirationCenterY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clampedCenterY(
        ratio: CGFloat,
        elementHeight: CGFloat,
        availableHeight: CGFloat,
        edgeInset: CGFloat
    ) -> CGFloat {
        let halfHeight = elementHeight / 2
        return min(
            max(availableHeight * ratio, edgeInset + halfHeight),
            availableHeight - edgeInset - halfHeight
        )
    }

    private func entryCluster(at date: Date, compact: Bool, spacing: CGFloat, entryWidth: CGFloat) -> some View {
        VStack(spacing: spacing) {
            greeting(at: date, compact: compact)
            EmptyWorkspaceEntryRow(entryWidth: entryWidth)
        }
    }

    private func greeting(at date: Date, compact: Bool) -> some View {
        Text(EmptyWorkspaceDayPeriod.current(at: date).greeting(language: store.interfaceLanguage))
            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: compact ? 14.5 : 16, weight: .regular))
            .tracking(store.interfaceLanguage == .chinese ? 0.8 : 0.35)
            .foregroundStyle(EmptyWorkspaceResolvedColor.secondaryInk(liveAppearanceMode).opacity(0.92))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("empty-workspace-greeting")
    }

    private func inspiration(at date: Date) -> EmptyWorkspaceInspiration {
        let baseInspiration = dailyInspiration(at: date)
        guard let selectedInspirationID else { return baseInspiration }
        return EmptyWorkspaceInspirationCatalog.rotationItems.first(where: { $0.id == selectedInspirationID }) ?? baseInspiration
    }

    private func dailyInspiration(at date: Date) -> EmptyWorkspaceInspiration {
        let environment = ProcessInfo.processInfo.environment
        if environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1" {
            let forcedID: String?
            switch environment["WEIBEI_VERIFY_SCENARIO"] {
            case "empty-workspace-calligraphy-light":
                forcedID = "lanting-clear-breeze"
            case "empty-workspace-calligraphy-dark":
                forcedID = "lanting-universe"
            default:
                forcedID = environment["WEIBEI_VERIFY_INSPIRATION_ID"]
            }
            if let forcedID,
               let requested = EmptyWorkspaceInspirationCatalog.rotationItems.first(where: { $0.id == forcedID }) {
                return requested
            }
        }
        return EmptyWorkspaceInspirationCatalog.item(for: date)
    }

    private func advanceInspiration(from currentID: String) {
        guard !EmptyWorkspaceInspirationCatalog.rotationItems.isEmpty else { return }
        var generator = SystemRandomNumberGenerator()
        let nextID = EmptyWorkspaceInspirationCatalog.randomItem(excludingID: currentID, using: &generator).id
        if reduceMotion {
            selectedInspirationID = nextID
        } else {
            withAnimation(.easeInOut(duration: 0.24)) {
                selectedInspirationID = nextID
            }
        }
    }
}

/// sRGB SwiftUI colors resolved from an explicit mode (not ambient WeiBeiTheme).
/// `Color(nsColor:)` can stick to the wrong snapshot inside a long-lived NSHostingView.
private enum EmptyWorkspaceResolvedColor {
    static func paper(_ mode: WeiBeiAppearanceMode) -> Color {
        color(WeiBeiNativePalette.paper(for: mode))
    }

    static func paperRaised(_ mode: WeiBeiAppearanceMode) -> Color {
        color(WeiBeiNativePalette.paperRaised(for: mode))
    }

    static func ink(_ mode: WeiBeiAppearanceMode) -> Color {
        color(WeiBeiNativePalette.ink(for: mode))
    }

    static func secondaryInk(_ mode: WeiBeiAppearanceMode) -> Color {
        color(WeiBeiNativePalette.secondaryInk(for: mode))
    }

    static func hairline(_ mode: WeiBeiAppearanceMode) -> Color {
        color(WeiBeiNativePalette.hairline(for: mode))
    }

    private static func color(_ nsColor: NSColor) -> Color {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

private struct EmptyWorkspacePaperField: View {
    let mode: WeiBeiAppearanceMode
    let compact: Bool

    var body: some View {
        let paper = EmptyWorkspaceResolvedColor.paper(mode)
        let raised = EmptyWorkspaceResolvedColor.paperRaised(mode)
        let ink = EmptyWorkspaceResolvedColor.ink(mode)
        let hairline = EmptyWorkspaceResolvedColor.hairline(mode)

        return ZStack {
            paper

            RadialGradient(
                colors: [
                    raised.opacity(mode.isDark ? 0.45 : 0.72),
                    paper.opacity(0),
                ],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 8,
                endRadius: compact ? 330 : 520
            )

            LinearGradient(
                colors: [
                    ink.opacity(mode.isDark ? 0.04 : 0.025),
                    Color.clear,
                    ink.opacity(mode.isDark ? 0.03 : 0.018),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(hairline.opacity(mode.isDark ? 0.40 : 0.30))
                .frame(width: 1, height: compact ? 24 : 48)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, compact ? 14 : 24)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EmptyWorkspaceEntryRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let entryWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(EmptyWorkspaceEntry.allCases.enumerated()), id: \.element) { index, entry in
                if index > 0 {
                    entryDivider
                }
                EmptyWorkspaceEntryButton(
                    title: entry.title,
                    accessibilityLabel: accessibilityLabel(for: entry),
                    identifier: entry.accessibilityIdentifier,
                    width: entryWidth,
                    action: { toggle(entry) }
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }

    private var entryDivider: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.78))
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }

    /**
     * Returns the localized action label for a semantic empty-workspace entry.
     */
    private func accessibilityLabel(for entry: EmptyWorkspaceEntry) -> String {
        switch entry {
        case .document: store.ui("打开文稿", "Open document")
        case .chat: store.ui("打开对话", "Open chat")
        case .notes: store.ui("打开笔记", "Open notes")
        }
    }

    /**
     * Routes an empty-workspace entry through the same pane toggle used by app chrome.
     */
    private func toggle(_ entry: EmptyWorkspaceEntry) {
        switch entry.paneRole {
        case .reader: store.toggleReader()
        case .agent: store.toggleAgent()
        case .notes: store.toggleNotes()
        }
    }
}

private struct EmptyWorkspaceEntryButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let accessibilityLabel: String
    let identifier: String
    let width: CGFloat
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        let active = focused || hovering

        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(WeiBeiTypography.englishBrandFont(size: 22, weight: .semibold))
                    .tracking(active ? 3.5 : 2.2)
                    .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk.opacity(0.88))
                    .offset(y: active && !reduceMotion ? -2.5 : 0)

                ZStack {
                    Rectangle()
                        .fill(WeiBeiTheme.hairline.opacity(0.52))
                        .frame(width: active ? 42 : 14, height: 1)

                    Rectangle()
                        .fill(WeiBeiTheme.ink.opacity(focused ? 0.64 : hovering ? 0.42 : 0))
                        .frame(width: active ? 32 : 0, height: 1)
                }
                .frame(height: 4)
                .opacity(active ? 1 : 0.72)
            }
            .frame(width: width, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .background {
            EmptyWorkspaceAlwaysActiveHoverRegion { isHovering in
                hovering = isHovering
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: focused)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier(identifier)
        .help(accessibilityLabel)
    }
}

private struct EmptyWorkspaceAlwaysActiveHoverRegion: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingView {
        HoverTrackingView(onHoverChange: onHoverChange)
    }

    func updateNSView(_ view: HoverTrackingView, context: Context) {
        view.onHoverChange = onHoverChange
    }

    final class HoverTrackingView: NSView {
        var onHoverChange: (Bool) -> Void
        private var activeTrackingArea: NSTrackingArea?

        init(onHoverChange: @escaping (Bool) -> Void) {
            self.onHoverChange = onHoverChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let activeTrackingArea {
                removeTrackingArea(activeTrackingArea)
            }
            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
            let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self)
            addTrackingArea(trackingArea)
            activeTrackingArea = trackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChange(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChange(false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}

private struct EmptyWorkspaceInspirationView: View {
    @EnvironmentObject private var store: WorkspaceStore

    let inspiration: EmptyWorkspaceInspiration
    let compact: Bool
    let onAdvance: () -> Void

    var body: some View {
        VStack(spacing: compact ? 7 : 9) {
            Button(action: onAdvance) {
                VStack(spacing: compact ? 8 : 11) {
                    inspirationContent

                    Text(inspiration.credit)
                        .font(.system(size: compact ? 10.5 : 11.5, weight: .medium, design: .serif))
                        .foregroundStyle(WeiBeiTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(inspiration.text)，\(inspiration.credit)"))
            .accessibilityHint(Text(store.ui("随机换一则灵感", "Show a random inspiration")))
            .accessibilityIdentifier("empty-workspace-inspiration-next")

            sourceAndRights
        }
        .frame(maxWidth: compact ? 560 : 660)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-workspace-inspiration-\(inspiration.id)")
    }

    @ViewBuilder
    private var inspirationContent: some View {
        switch inspiration.presentation {
        case let .calligraphy(assetName):
            if let image = EmptyWorkspaceCalligraphyResource.image(named: assetName) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(WeiBeiTheme.ink.opacity(0.88))
                    .frame(maxWidth: compact ? 390 : 500, maxHeight: compact ? 54 : 72)
                    .padding(.vertical, compact ? 1 : 2)
                    .accessibilityLabel(Text(inspiration.text))
            } else {
                inspirationText(size: compact ? 24 : 30)
            }
        case .quotation:
            inspirationText(size: compact ? 21 : 26)
        case .formula:
            formulaContent(size: compact ? 24 : 30)
        }
    }

    private func formulaContent(size: CGFloat) -> some View {
        formulaText(size: size)
            .foregroundStyle(WeiBeiTheme.ink.opacity(0.90))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .accessibilityLabel(Text(inspiration.text))
    }

    private func formulaText(size: CGFloat) -> Text {
        let baseFont = Font.system(size: size, weight: .regular, design: .serif)
        let scriptFont = Font.system(size: size * 0.58, weight: .regular, design: .serif)
        let superscript = size * 0.34

        switch inspiration.id {
        case "euler-formula":
            return Text("e").font(baseFont)
                + Text("ix").font(scriptFont).baselineOffset(superscript)
                + Text(" = cos x + i sin x").font(baseFont)
        case "einstein-rest-energy":
            return Text("E").font(baseFont)
                + Text("0").font(scriptFont).baselineOffset(-size * 0.16)
                + Text(" = mc").font(baseFont)
                + Text("2").font(scriptFont).baselineOffset(superscript)
        case "cobb-douglas-production":
            return Text("P = bL").font(baseFont)
                + Text("k").font(scriptFont).baselineOffset(superscript)
                + Text("C").font(baseFont)
                + Text("1 − k").font(scriptFont).baselineOffset(superscript)
        default:
            return Text(inspiration.text).font(baseFont)
        }
    }

    private func inspirationText(size: CGFloat) -> some View {
        Text(inspiration.text)
            .font(.system(size: size, weight: .regular, design: .serif))
            .foregroundStyle(WeiBeiTheme.ink.opacity(0.90))
            .multilineTextAlignment(.center)
            .lineLimit(compact ? 3 : 2)
            .minimumScaleFactor(compact ? 0.72 : 0.78)
            .accessibilityLabel(Text(inspiration.text))
    }

    private var sourceAndRights: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                sourceLink
                Text("·")
                    .accessibilityHidden(true)
                rightsLink
            }

            VStack(spacing: 3) {
                sourceLink
                rightsLink
            }
        }
        .font(.system(size: compact ? 9 : 9.5, weight: .regular))
        .foregroundStyle(WeiBeiTheme.tertiaryInk)
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }

    @ViewBuilder
    private var sourceLink: some View {
        if let url = inspiration.sourceURL {
            Link(inspiration.sourceLabel, destination: url)
        } else {
            Text(inspiration.sourceLabel)
        }
    }

    @ViewBuilder
    private var rightsLink: some View {
        if let url = inspiration.rightsURL {
            Link(inspiration.rightsLabel, destination: url)
        } else {
            Text(inspiration.rightsLabel)
        }
    }
}

private enum EmptyWorkspaceCalligraphyResource {
    static func image(named name: String) -> NSImage? {
        let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Inspiration/Calligraphy")
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Calligraphy")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
