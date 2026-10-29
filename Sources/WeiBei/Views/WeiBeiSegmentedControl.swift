import SwiftUI
import WeiBeiCore

/// Reading toolbar controls share an outline symbol, a fixed hit region, and
/// a cinnabar selected symbol with a neutral fill. Segments also share their moving hover pill.
struct WeiBeiTopBarButton: View {
    static let width: CGFloat = 34
    static let height: CGFloat = 28
    static let hoverInset: CGFloat = 2

    let id: String
    let systemImage: String
    let help: String
    var isSelected = false
    var usesGroupHover = false
    var isGroupHovered = false
    var onHoverChanged: ((Bool) -> Void)? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.weiBeiTextScale) private var textScale
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var isHovered: Bool { isEnabled && (usesGroupHover ? isGroupHovered : hovering) }

    var body: some View {
        Button {
            WeiBeiLog.workspace.notice("code=toolbar_action control=\(id, privacy: .public) source=button")
            action()
        } label: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .symbolVariant(.none)
                .weiBeiText(14, weight: .medium)
                .foregroundStyle(iconColor)
                .frame(width: Self.width * textScale, height: Self.height * textScale)
                .contentShape(Rectangle())
        }
        .buttonStyle(WeiBeiTopBarPressStyle(reduceMotion: reduceMotion))
        .background {
            Capsule()
                .fill(WeiBeiTheme.ink.opacity(colorScheme == .dark ? 0.16 : 0.09))
                .frame(width: (Self.width - Self.hoverInset * 2) * textScale,
                       height: (Self.height - Self.hoverInset * 2) * textScale)
                .opacity(isSelected && isEnabled ? 1 : 0)
                .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: isSelected)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if !usesGroupHover {
                RoundedRectangle(cornerRadius: (Self.height - Self.hoverInset * 2) * textScale / 2,
                                 style: .continuous)
                    .fill(WeiBeiTheme.ink.opacity(colorScheme == .dark ? 0.10 : 0.06))
                    .frame(width: (Self.width - Self.hoverInset * 2) * textScale,
                           height: (Self.height - Self.hoverInset * 2) * textScale)
                    .opacity(isHovered ? 1 : 0)
                    .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: isHovered)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onHover { value in
            let next = isEnabled && value
            hovering = next
            onHoverChanged?(next)
        }
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                hovering = false
                onHoverChanged?(false)
            }
        }
        .help(help)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconColor: Color {
        if !isEnabled { return WeiBeiTheme.secondaryInk.opacity(0.4) }
        if isSelected { return WeiBeiTheme.cinnabar }
        return isHovered ? WeiBeiTheme.ink : WeiBeiTheme.ink.opacity(0.85)
    }
}

/// A quiet group outline, sized by the existing controls so grouping does not
/// change their hit regions or the native toolbar's overflow measurements.
struct WeiBeiToolbarGroupBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule()
            .fill(WeiBeiTheme.paperRaised.opacity(colorScheme == .dark ? 0.65 : 0.55))
            .overlay {
                Capsule()
                    .strokeBorder(WeiBeiTheme.ink.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Independent pane switches share a reading-toolbar capsule. Each open pane
/// keeps its own selected fill; the moving hover highlight is only transient.
struct WeiBeiSegmentedControl: View {
    struct Segment: Identifiable {
        let id: String
        let systemImage: String
        let help: String
        let isSelected: Bool
        let action: () -> Void
    }

    let segments: [Segment]

    @State private var hoveredIndex: Int?
    /// Where the hover pill rests while fading out, so leaving the capsule
    /// fades the pill in place instead of sliding it back to segment zero.
    @State private var restingIndex: Int = 0

    @Environment(\.weiBeiTextScale) private var textScale
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var segmentWidth: CGFloat { WeiBeiTopBarButton.width * textScale }
    private var height: CGFloat { WeiBeiTopBarButton.height * textScale }
    private var pillInset: CGFloat { WeiBeiTopBarButton.hoverInset * textScale }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                segmentButton(segment, index: index)
            }
        }
        .frame(height: height)
        .background(alignment: .leading) { hoverPill }
        .background { WeiBeiToolbarGroupBackground() }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var hoverPill: some View {
        let target = hoveredIndex ?? restingIndex
        pillShape
            .fill(WeiBeiTheme.ink.opacity(colorScheme == .dark ? 0.10 : 0.06))
            .frame(width: pillWidth, height: pillHeight)
            .offset(x: pillInset + CGFloat(target) * segmentWidth)
            .opacity(hoveredIndex == nil ? 0 : 1)
            .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: hoveredIndex)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var pillShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: (height - pillInset * 2) / 2,
            style: .continuous
        )
    }

    private var pillWidth: CGFloat { segmentWidth - pillInset * 2 }
    private var pillHeight: CGFloat { height - pillInset * 2 }

    // MARK: Segments

    private func segmentButton(_ segment: Segment, index: Int) -> some View {
        WeiBeiTopBarButton(id: segment.id, systemImage: segment.systemImage, help: segment.help,
            isSelected: segment.isSelected, usesGroupHover: true, isGroupHovered: hoveredIndex == index,
            onHoverChanged: { hovering in
                if hovering {
                    hoveredIndex = index
                    restingIndex = index
                } else if hoveredIndex == index {
                    hoveredIndex = nil
                }
            }, action: segment.action)
    }
}

private struct WeiBeiTopBarPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : WeiBeiMotion.press, value: configuration.isPressed)
    }
}
