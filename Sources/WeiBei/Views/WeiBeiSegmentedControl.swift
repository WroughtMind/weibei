import SwiftUI

/// Capsule segmented control in the native macOS style: one outer capsule,
/// a floating stadium highlight that slides onto the hovered segment, and
/// hairline dividers that only render between segments no highlight touches.
/// Selected segments keep a persistent raised pill with the cinnabar accent
/// icon (WeiBei's active-state convention), mirroring how a multi-select
/// native segmented control keeps its selected segments lit.
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
        ZStack(alignment: .leading) {
            dividers
            selectedPills
            hoverPill
            segmentButtons
        }
        .frame(width: segmentWidth * CGFloat(segments.count), height: height)
        .background {
            Capsule()
                .fill(WeiBeiTheme.paperInset.opacity(colorScheme == .dark ? 0.50 : 0.44))
                .overlay {
                    Capsule()
                        .stroke(WeiBeiTheme.glassHighlight.opacity(0.16), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Highlights

    @ViewBuilder
    private var selectedPills: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                // The hover pill takes over the hovered segment so the two
                // fills never stack; while sliding it may briefly overlap a
                // neighbouring selected pill, as the native control does.
                if segment.isSelected, hoveredIndex != index {
                    pillShape
                        .fill(WeiBeiTheme.paperRaised.opacity(colorScheme == .dark ? 0.72 : 0.96))
                        .frame(width: segmentWidth - pillInset * 2, height: height - pillInset * 2)
                        .overlay {
                            pillShape
                                .stroke(WeiBeiTheme.hairline.opacity(colorScheme == .dark ? 0.5 : 0.35), lineWidth: 1)
                        }
                        .offset(x: pillInset + CGFloat(index) * segmentWidth)
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var hoverPill: some View {
        let target = hoveredIndex ?? restingIndex
        let coversSelected = segments.indices.contains(target) && segments[target].isSelected
        pillShape
            .fill(
                coversSelected
                    ? WeiBeiTheme.paperRaised.opacity(colorScheme == .dark ? 0.72 : 0.96)
                    : WeiBeiTheme.paperRaised.opacity(colorScheme == .dark ? 0.42 : 0.80)
            )
            .frame(width: segmentWidth - pillInset * 2, height: height - pillInset * 2)
            .overlay {
                pillShape
                    .stroke(WeiBeiTheme.hairline.opacity(colorScheme == .dark ? 0.5 : 0.35), lineWidth: 1)
            }
            .shadow(color: WeiBeiTheme.ink.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 2, y: 1)
            .offset(x: pillInset + CGFloat(target) * segmentWidth)
            .opacity(hoveredIndex == nil ? 0 : 1)
            .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: hoveredIndex)
            .allowsHitTesting(false)
    }

    private var pillShape: some InsettableShape {
        RoundedRectangle(cornerRadius: (height - pillInset * 2) / 2, style: .continuous)
    }

    // MARK: Dividers

    @ViewBuilder
    private var dividers: some View {
        ZStack(alignment: .leading) {
            ForEach(1..<max(segments.count, 1), id: \.self) { boundary in
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.26 : 0.80))
                    .frame(width: 1, height: 12 * textScale)
                    .offset(x: CGFloat(boundary) * segmentWidth - 0.5)
                    .opacity(hasHighlight(at: boundary - 1) || hasHighlight(at: boundary) ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : WeiBeiMotion.hover, value: hoveredIndex)
    }

    /// A segment "has a highlight" when it is selected or hovered; dividers
    /// touching it are absorbed by that segment's pill.
    private func hasHighlight(at index: Int) -> Bool {
        guard segments.indices.contains(index) else { return false }
        return segments[index].isSelected || hoveredIndex == index
    }

    // MARK: Segments

    @ViewBuilder
    private var segmentButtons: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                Button(action: segment.action) {
                    Image(systemName: segment.systemImage)
                        .weiBeiText(13, weight: .semibold)
                        .foregroundStyle(iconColor(for: segment, at: index))
                        .frame(width: segmentWidth, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(WeiBeiSegmentPressStyle(reduceMotion: reduceMotion))
                .onHover { hovering in
                    guard segments.indices.contains(index) else { return }
                    if hovering {
                        hoveredIndex = index
                        restingIndex = index
                    } else if hoveredIndex == index {
                        hoveredIndex = nil
                    }
                }
                .help(segment.help)
                .accessibilityLabel(Text(segment.help))
                .offset(x: CGFloat(index) * segmentWidth)
            }
        }
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
