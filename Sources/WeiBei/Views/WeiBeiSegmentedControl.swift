import SwiftUI

/// Pane switches share the toolbar's transparent surface. Selection stays on
/// the cinnabar icon; only pointer hover adds a transient, translucent highlight.
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

    private var segmentWidth: CGFloat { 34 * textScale }
    private var height: CGFloat { 28 * textScale }
    private var pillInset: CGFloat { 2 * textScale }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                segmentButton(segment, index: index)
            }
        }
        .frame(height: height)
        .background(alignment: .leading) { hoverPill }
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
        Button(action: segment.action) {
            Image(systemName: segment.systemImage)
                .weiBeiText(13, weight: .semibold)
                .foregroundStyle(iconColor(for: segment, at: index))
                .frame(width: segmentWidth, height: height)
                .contentShape(Rectangle())
        }
        .buttonStyle(WeiBeiSegmentPressStyle(reduceMotion: reduceMotion))
        .onHover { hovering in
            if hovering {
                hoveredIndex = index
                restingIndex = index
            } else if hoveredIndex == index {
                hoveredIndex = nil
            }
        }
        .help(segment.help)
        .accessibilityLabel(Text(segment.help))
        .accessibilityAddTraits(segment.isSelected ? .isSelected : [])
    }

    private func iconColor(for segment: Segment, at index: Int) -> Color {
        if segment.isSelected { return WeiBeiTheme.cinnabar }
        if hoveredIndex == index { return WeiBeiTheme.ink }
        return WeiBeiTheme.secondaryInk
    }
}

private struct WeiBeiSegmentPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : WeiBeiMotion.press, value: configuration.isPressed)
    }
}
