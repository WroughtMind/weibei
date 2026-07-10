import AppKit
import SwiftUI
import WeiBeiCore

struct EmptyWorkspaceLauncherView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            GeometryReader { geometry in
                let compact = geometry.size.width < 760 || geometry.size.height < 620
                let horizontalPadding: CGFloat = compact ? 28 : 52
                let entryWidth = min(116, max(76, (geometry.size.width - (horizontalPadding * 2) - 2) / 3))

                ZStack {
                    WeiBeiTheme.paper

                    VStack(spacing: compact ? 20 : 28) {
                        Spacer(minLength: compact ? 24 : 44)

                        greeting(at: timeline.date)

                        EmptyWorkspaceEntryRow(entryWidth: entryWidth)

                        if store.showDailyInspiration {
                            EmptyWorkspaceInspirationView(
                                inspiration: inspiration(at: timeline.date),
                                compact: compact
                            )
                            .transition(.opacity)
                        }

                        Spacer(minLength: compact ? 24 : 44)
                    }
                    .frame(maxWidth: 760)
                    .padding(.horizontal, horizontalPadding)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-workspace-launcher")
    }

    private func greeting(at date: Date) -> some View {
        Text(EmptyWorkspaceDayPeriod.current(at: date).greeting(language: store.interfaceLanguage))
            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 15, weight: .regular))
            .foregroundStyle(WeiBeiTheme.secondaryInk)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("empty-workspace-greeting")
    }

    private func inspiration(at date: Date) -> EmptyWorkspaceInspiration {
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
               let requested = EmptyWorkspaceInspirationCatalog.items.first(where: { $0.id == forcedID }) {
                return requested
            }
        }
        return EmptyWorkspaceInspirationCatalog.item(for: date)
    }
}

private struct EmptyWorkspaceEntryRow: View {
    @EnvironmentObject private var store: WorkspaceStore
    let entryWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            EmptyWorkspaceEntryButton(
                title: "DOC",
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
                title: "NOTES",
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
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}

private struct EmptyWorkspaceEntryButton: View {
    let title: String
    let accessibilityLabel: String
    let identifier: String
    let width: CGFloat
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WeiBeiTypography.englishBrandFont(size: 20, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(focused || hovering ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
                .frame(width: width, height: 48)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(WeiBeiTheme.ink.opacity(focused ? 0.62 : hovering ? 0.34 : 0))
                        .frame(width: 26, height: 1)
                        .padding(.bottom, 4)
                }
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: focused)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityIdentifier(identifier)
        .help(accessibilityLabel)
    }
}

private struct EmptyWorkspaceInspirationView: View {
    let inspiration: EmptyWorkspaceInspiration
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.72))
                .frame(width: 34, height: 1)
                .padding(.bottom, compact ? 2 : 5)

            inspirationContent

            Text(inspiration.credit)
                .font(.system(size: compact ? 10.5 : 11.5, weight: .medium, design: .serif))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .lineLimit(2)

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
            .lineLimit(2)
            .minimumScaleFactor(0.78)
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
        let url = WeiBeiResources.bundle.url(forResource: name, withExtension: "png", subdirectory: "Inspiration/Calligraphy")
            ?? WeiBeiResources.bundle.url(forResource: name, withExtension: "png", subdirectory: "Calligraphy")
            ?? WeiBeiResources.bundle.url(forResource: name, withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
