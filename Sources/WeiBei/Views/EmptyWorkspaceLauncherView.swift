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
    static let watermarkMaxWidth: CGFloat = 720
    static let watermarkCenterRatio: CGFloat = 0.64
}

struct EmptyWorkspaceLauncherView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Environment(\.weiBeiTextScale) private var textScale

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
                    if !mode.isGlass {
                        EmptyWorkspacePaperField(mode: mode, compact: compact)
                            .frame(height: geometry.size.height + WeiBeiMetric.topBarHeight * textScale)
                            .offset(y: -WeiBeiMetric.topBarHeight * textScale)
                    }

                    if store.showDailyInspiration && store.inspirationAsWatermark {
                        // Paper-grain mode: the daily line sits behind the entry
                        // cluster as a faint ink impression. Still tappable —
                        // one click shuffles to another line.
                        EmptyWorkspaceInkWatermarkView(
                            inspiration: currentInspiration,
                            mode: mode,
                            compact: compact,
                            onAdvance: { advanceInspiration(from: currentInspiration.id) }
                        )
                        .frame(width: min(EmptyWorkspaceLayoutMetrics.watermarkMaxWidth, geometry.size.width - horizontalPadding * 2))
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height * EmptyWorkspaceLayoutMetrics.watermarkCenterRatio
                        )
                    }

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
        .background(
            liveAppearanceMode.isGlass
                ? Color.clear
                : EmptyWorkspaceResolvedColor.paper(liveAppearanceMode)
        )
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
        let showsInspirationBlock = store.showDailyInspiration && !store.inspirationAsWatermark
        let entryHeight: CGFloat = (compact ? 84 : 98) * textScale
        let entryCenterY = clampedCenterY(
            ratio: showsInspirationBlock ? EmptyWorkspaceLayoutMetrics.entryCenterRatio : 0.5,
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
                spacing: (showsInspirationBlock ? (compact ? 18 : 26) : (compact ? 16 : 29)) * textScale,
                entryWidth: entryWidth
            )
            .frame(width: contentWidth)
            .position(x: availableSize.width / 2, y: entryCenterY)

            if showsInspirationBlock {
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
            if store.courses.isEmpty && store.importedItems.isEmpty {
                LibraryPlacementNoticeCard()
                AgentSetupPromptCard()
            }
        }
    }

    private func greeting(at date: Date, compact: Bool) -> some View {
        Text(EmptyWorkspaceDayPeriod.current(at: date).greeting(language: store.interfaceLanguage))
            .weiBeiBrandFont(language: store.interfaceLanguage, size: compact ? 23 : 25.5, weight: .regular)
            .tracking(store.interfaceLanguage == .chinese ? 1.3 : 0.55)
            .foregroundStyle(EmptyWorkspaceResolvedColor.secondaryInk(liveAppearanceMode).opacity(0.92))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("empty-workspace-greeting")
    }

    private func inspiration(at date: Date) -> EmptyWorkspaceInspiration {
        let baseInspiration = EmptyWorkspaceInspirationCatalog.item(for: date)
        guard let selectedInspirationID else { return baseInspiration }
        return EmptyWorkspaceInspirationCatalog.rotationItems.first(where: { $0.id == selectedInspirationID }) ?? baseInspiration
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
        Color(nsColor: WeiBeiNativePalette.paper(for: mode))
    }

    static func paperRaised(_ mode: WeiBeiAppearanceMode) -> Color {
        Color(nsColor: WeiBeiNativePalette.paperRaised(for: mode))
    }

    static func ink(_ mode: WeiBeiAppearanceMode) -> Color {
        Color(nsColor: WeiBeiNativePalette.ink(for: mode))
    }

    static func secondaryInk(_ mode: WeiBeiAppearanceMode) -> Color {
        Color(nsColor: WeiBeiNativePalette.secondaryInk(for: mode))
    }

    static func hairline(_ mode: WeiBeiAppearanceMode) -> Color {
        Color(nsColor: WeiBeiNativePalette.hairline(for: mode))
    }
}

struct EmptyWorkspacePaperField: View {
    let mode: WeiBeiAppearanceMode
    let compact: Bool

    var body: some View {
        let paper = EmptyWorkspaceResolvedColor.paper(mode)
        let raised = EmptyWorkspaceResolvedColor.paperRaised(mode)
        let ink = EmptyWorkspaceResolvedColor.ink(mode)

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

        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct EmptyWorkspaceEntryRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weiBeiTextScale) private var textScale
    let entryWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            EmptyWorkspaceEntryButton(
                title: "READ",
                accessibilityLabel: store.ui("打开文稿", "Open document"),
                identifier: "empty-workspace-entry-doc",
                width: entryWidth,
                action: store.toggleReader
            )

            entryDivider

            EmptyWorkspaceEntryButton(
                title: "CHAT",
                accessibilityLabel: store.ui("打开对话", "Open chat"),
                identifier: "empty-workspace-entry-chat",
                width: entryWidth,
                action: store.toggleAgent
            )

            entryDivider

            EmptyWorkspaceEntryButton(
                title: "NOTE",
                accessibilityLabel: store.ui("打开笔记", "Open notes"),
                identifier: "empty-workspace-entry-notes",
                width: entryWidth,
                action: store.toggleNotes
            )
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }

    private var entryDivider: some View {
        Rectangle()
            .fill(WeiBeiTheme.hairline.opacity(0.78))
            .frame(width: 1, height: 18 * textScale)
            .accessibilityHidden(true)
    }
}

private struct EmptyWorkspaceEntryButton: View {
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Environment(\.weiBeiTextScale) private var textScale

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
            VStack(spacing: 2 * textScale) {
                Text(title)
                    .weiBeiEnglishBrandFont(size: 22, weight: .semibold)
                    .tracking((active ? 3.5 : 2.2) * textScale)
                    .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk.opacity(0.88))
                    .offset(y: active && !reduceMotion ? -2.5 * textScale : 0)

                ZStack {
                    Rectangle()
                        .fill(WeiBeiTheme.hairline.opacity(0.52))
                        .frame(width: (active ? 42 : 14) * textScale, height: 1)

                    Rectangle()
                        .fill(WeiBeiTheme.ink.opacity(focused ? 0.64 : hovering ? 0.42 : 0))
                        .frame(width: (active ? 32 : 0) * textScale, height: 1)
                }
                .frame(height: 4 * textScale)
                .opacity(active ? 1 : 0.72)
            }
            .frame(width: width * textScale, height: 52 * textScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .background {
            HoverPassThroughRegion { isHovering in
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

/// Block presentation: quote + credit as content below the entries; the
/// source/rights row stays mounted (fixed slot layout, VoiceOver reachable)
/// but only paints on hover.
private struct EmptyWorkspaceInspirationView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion

    let inspiration: EmptyWorkspaceInspiration
    let compact: Bool
    let onAdvance: () -> Void

    @State private var revealsSources = false

    var body: some View {
        VStack(spacing: compact ? 7 : 9) {
            Button(action: onAdvance) {
                VStack(spacing: compact ? 8 : 11) {
                    inspirationContent

                    Text(inspiration.credit)
                        .weiBeiText(compact ? 10.5 : 11.5, weight: .medium, design: .serif)
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
            .accessibilityHint(Text(store.ui("随机换一句", "Show another line")))
            .accessibilityIdentifier("empty-workspace-inspiration-next")

            sourceAndRights
                .opacity(revealsSources ? 1 : 0)
                .allowsHitTesting(revealsSources)
        }
        .frame(maxWidth: compact ? 560 : 660)
        .background {
            HoverPassThroughRegion { isHovering in
                revealsSources = isHovering
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: revealsSources)
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
            .weiBeiText(size, weight: .regular, design: .serif)
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
        .weiBeiText(compact ? 9 : 9.5, weight: .regular)
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

/// Faint ink impression of the daily line — paper grain, not content.
/// No credit line or links; attribution stays in the bundled SOURCES.md
/// ledger. Opacity is tuned per light/dark mode like the paper field
/// gradients so all eight themes carry the watermark coherently. One click
/// shuffles to another line; hovering deepens the ink as the only affordance.
private struct EmptyWorkspaceInkWatermarkView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion

    let inspiration: EmptyWorkspaceInspiration
    let mode: WeiBeiAppearanceMode
    let compact: Bool
    let onAdvance: () -> Void

    @State private var hovering = false

    private var ink: Color {
        let base: CGFloat = mode.isDark ? 0.08 : 0.055
        return EmptyWorkspaceResolvedColor.ink(mode).opacity(hovering ? min(base * 1.7, 0.16) : base)
    }

    var body: some View {
        Button(action: onAdvance) {
            Group {
                switch inspiration.presentation {
                case let .calligraphy(assetName):
                    if let image = EmptyWorkspaceCalligraphyResource.image(named: assetName) {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(ink)
                            .padding(.horizontal, compact ? 24 : 40)
                    } else {
                        lineText
                    }
                default:
                    lineText
                }
            }
            .frame(maxWidth: .infinity, maxHeight: compact ? 180 : 230)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(inspiration.id)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hovering)
        .onHover { isHovering in
            hovering = isHovering
        }
        .accessibilityLabel(Text(inspiration.text))
        .accessibilityHint(Text(store.ui("随机换一句", "Show another line")))
        .accessibilityIdentifier("empty-workspace-inspiration-next")
    }

    private var lineText: some View {
        Text(inspiration.text)
            .weiBeiText(compact ? 40 : 50, weight: .regular, design: .serif)
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.55)
    }
}

enum EmptyWorkspaceCalligraphyResource {
    static func image(named name: String) -> NSImage? {
        // WeiBeiResources resolves the staged/packaged bundle via Bundle(url:);
        // a bare Bundle.module access can fatalError inside assembled apps when
        // both the packaged path and the compiled-in dev fallback are missing.
        let bundle = WeiBeiResources.bundle
        let url = bundle.url(forResource: name, withExtension: "png", subdirectory: "Inspiration/Calligraphy")
            ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "Calligraphy")
            ?? bundle.url(forResource: name, withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// First-run notice under the entries: the library folder is pre-picked by
/// default; the user may confirm or relocate it, then explore on their own.
/// Import guidance itself lives in the reader / notes pickers, not here.
private struct LibraryPlacementNoticeCard: View {
    @EnvironmentObject private var store: WorkspaceStore

    /// 确认过一次就不再出现；偏好走 UserDefaults，不进冻结的 WorkspaceStore。
    @AppStorage("weibei.libraryPlacementConfirmed") private var confirmed = false

    @State private var isRelocating = false
    @State private var relocationErrorText: String?

    private var libraryPath: String {
        store.courseLibraryRootPath ?? CourseLibraryLayout.defaultRootURL().path
    }

    var body: some View {
        VStack(spacing: 9) {
            Text(store.ui(
                "课程资料库文件夹将安放在这里，可现在更换，之后随时能在设置里改。",
                "Your course library folder will live here — you can move it now or later in Settings."
            ))
            .weiBeiText(11.5)
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .weiBeiText(11, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                Text(libraryPath)
                    .weiBeiText(11, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                WeiBeiEtchedBackdrop(
                    shape: RoundedRectangle(cornerRadius: 7, style: .continuous),
                    fill: WeiBeiTheme.paperInset.opacity(0.32),
                    stroke: WeiBeiTheme.hairline.opacity(0.45)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            if let relocationErrorText {
                Text(relocationErrorText)
                    .weiBeiText(11)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isRelocating {
                ProgressView()
                    .progressViewStyle(.linear)
            } else {
                HStack(spacing: 10) {
                    Button(store.ui("换个位置…", "Choose Another Location…")) {
                        relocateLibrary()
                    }
                    .buttonStyle(WeiBeiDialogButtonStyle(prominence: .secondary))

                    Button(store.ui("就用这里", "Use This Folder")) {
                        confirmed = true
                    }
                    .buttonStyle(WeiBeiDialogButtonStyle(prominence: .primary))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 470)
        .background {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                fill: WeiBeiTheme.paperRaised.opacity(0.55),
                stroke: WeiBeiTheme.hairline.opacity(0.5)
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: WeiBeiTheme.ink.opacity(0.06), radius: 2, y: 1)
        .shadow(color: WeiBeiTheme.ink.opacity(0.05), radius: 10, y: 3)
        .padding(.top, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-placement-notice")
    }

    private func relocateLibrary() {
        relocationErrorText = nil
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = store.ui("选择", "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isRelocating = true
        Task { @MainActor in
            do {
                _ = try await store.migrateLibrary(to: url.standardizedFileURL)
                confirmed = true
            } catch CourseProjectRootError.destinationIsLibrary {
                relocationErrorText = store.ui(
                    "所选位置已经是一个魏碑资料库，请选择其他空文件夹。",
                    "That location is already a WeiBei library. Choose an empty folder instead."
                )
            } catch {
                relocationErrorText = error.localizedDescription
            }
            isRelocating = false
        }
    }
}
