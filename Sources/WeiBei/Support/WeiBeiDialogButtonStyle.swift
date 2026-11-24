import SwiftUI
import WeiBeiCore

/// The shared style for labeled actions in sheets and larger inline forms.
struct WeiBeiDialogButtonStyle: ButtonStyle {
    enum Prominence: CaseIterable, Sendable {
        case primary, secondary, tertiary, ghost, text
    }

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    var prominence: Prominence = .secondary

    func makeBody(configuration: Configuration) -> some View {
        DialogButtonPresentation(
            label: configuration.label,
            prominence: prominence,
            interaction: .init(hovered: isEnabled && hovering, pressed: isEnabled && configuration.isPressed)
        )
        .onHover { hovering = $0 }
    }
}

private extension WeiBeiMetric {
    enum DialogButton {
        static let mediumLabel: CGFloat = 14
        static let largeLabel: CGFloat = 16
        static let height: CGFloat = 40
        static let horizontalPadding: CGFloat = 18
        static let cornerRadius: CGFloat = 10
        static let iconSize: CGFloat = 16
        static let spacing: CGFloat = 8
    }
}

private struct DialogButtonInteraction: Equatable {
    var hovered: Bool
    var pressed: Bool

    var material: CGPoint { CGPoint(x: hovered && !pressed ? 1 : 0, y: pressed ? 1 : 0) }
    var offset: CGPoint { CGPoint(x: hovered ? 1 : 0, y: pressed ? 1 : 0) }
}

private struct DialogButtonPresentation<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.weiBeiTextScale) private var textScale
    @Environment(\.weibeiReduceMotion) private var reduceMotion

    let label: Label
    let prominence: WeiBeiDialogButtonStyle.Prominence
    let interaction: DialogButtonInteraction

    private struct Phase {
        var face: CGPoint
        var shadows: CGPoint
        var offset: CGPoint
    }

    var body: some View {
        let labelSize = controlSize == .large || controlSize == .extraLarge
            ? WeiBeiMetric.DialogButton.largeLabel : WeiBeiMetric.DialogButton.mediumLabel
        let unit = labelSize * textScale / WeiBeiMetric.DialogButton.mediumLabel
        let palette = DialogButtonPalette.forProminence(prominence, dark: colorScheme == .dark)
        let material = interaction.material
        let offset = interaction.offset
        let enabled = isEnabled
        let label = self.label
            .weiBeiText(labelSize, weight: .semibold)
            .labelStyle(DialogButtonLabelStyle(unit: unit))
            .underline(prominence == .text)
            .shadow(color: .black.opacity(palette.labelShade), radius: 0, y: -unit)

        Group {
            if reduceMotion {
                appearance(label, phase: .init(face: material, shadows: material, offset: .zero),
                           palette: palette, unit: unit, enabled: enabled)
            } else {
                label.keyframeAnimator(
                    initialValue: Phase(face: .zero, shadows: .zero, offset: .zero),
                    trigger: interaction
                ) { label, phase in
                    appearance(label, phase: phase, palette: palette, unit: unit, enabled: enabled)
                } keyframes: { _ in
                    KeyframeTrack(\.face) {
                        LinearKeyframe(material, duration: WeiBeiMotionTokens.durationControl, timingCurve: .easeOut)
                    }
                    KeyframeTrack(\.shadows) {
                        LinearKeyframe(material, duration: WeiBeiMotionTokens.durationControl, timingCurve: .easeOut)
                    }
                    KeyframeTrack(\.offset) {
                        LinearKeyframe(offset, duration: WeiBeiMotionTokens.durationControl, timingCurve: .easeOut)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private nonisolated func appearance(_ label: some View, phase: Phase, palette: DialogButtonPalette,
                                        unit: CGFloat, enabled: Bool) -> some View {
        HStack(spacing: WeiBeiMetric.DialogButton.spacing * unit) {
            label
            if prominence == .text {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12 * unit, weight: .medium))
                    .offset(x: 2 * unit * phase.offset.x)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(palette.ink.opacity(enabled ? 1 : (prominence == .primary ? 0.66 : 0.60)))
        .padding(.horizontal, WeiBeiMetric.DialogButton.horizontalPadding * unit)
        .frame(minHeight: WeiBeiMetric.DialogButton.height * unit)
        .background {
            if prominence != .text {
                DialogButtonMaterial(palette: palette, unit: unit, face: phase.face, shadows: phase.shadows)
                    .opacity(enabled ? 1 : 0.38)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .offset(y: unit * phase.offset.y)
    }
}

private struct DialogButtonLabelStyle: LabelStyle {
    let unit: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let icon = WeiBeiMetric.DialogButton.iconSize * unit
        HStack(spacing: WeiBeiMetric.DialogButton.spacing * unit) {
            configuration.icon
                .font(.system(size: icon, weight: .medium))
                .frame(width: icon, height: icon)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

private struct DialogButtonFace {
    let top: Color.Resolved
    let bottom: Color.Resolved

    init(_ top: UInt32, _ bottom: UInt32) {
        self.init(top: Self.resolved(top), bottom: Self.resolved(bottom))
    }

    init(top: Color.Resolved, bottom: Color.Resolved) {
        self.top = top
        self.bottom = bottom
    }

    var flipped: Self { Self(top: bottom, bottom: top) }

    static func color(_ rgb: UInt32, opacity: Double = 1) -> Color {
        Color(resolved(rgb, opacity: opacity))
    }

    static func resolved(_ rgb: UInt32, opacity: Double = 1) -> Color.Resolved {
        Color.Resolved(red: Float(rgb >> 16) / 255, green: Float((rgb >> 8) & 255) / 255,
                       blue: Float(rgb & 255) / 255, opacity: Float(opacity))
    }

    func gradient(hover: Self, press: Self, progress: CGPoint) -> Gradient {
        let hovered = Float(progress.x)
        let pressed = Float(progress.y)
        let resting = 1 - hovered - pressed
        func mix(_ base: Color.Resolved, _ over: Color.Resolved, _ down: Color.Resolved) -> Color {
            Color(.sRGBLinear,
                  red: Double(base.linearRed * resting + over.linearRed * hovered + down.linearRed * pressed),
                  green: Double(base.linearGreen * resting + over.linearGreen * hovered + down.linearGreen * pressed),
                  blue: Double(base.linearBlue * resting + over.linearBlue * hovered + down.linearBlue * pressed),
                  opacity: Double(base.opacity * resting + over.opacity * hovered + down.opacity * pressed))
        }
        return Gradient(colors: [mix(top, hover.top, press.top), mix(bottom, hover.bottom, press.bottom)])
    }
}

private struct DialogButtonPalette {
    var face: DialogButtonFace? = nil
    var hover: DialogButtonFace? = nil
    var well: DialogButtonFace? = nil
    var edge = Color.clear
    var ink = Color(.sRGB, white: 0.20)
    var highlight: Double = 0
    var shade: Double = 0
    var contact: Double = 0
    var lift: Double = 0
    var inset: Double = 0
    var paperLine: Double = 0
    var labelShade: Double = 0

    static func forProminence(_ prominence: WeiBeiDialogButtonStyle.Prominence, dark: Bool) -> Self {
        switch prominence {
        case .primary:
            Self(face: .init(0x404859, 0x273042), hover: .init(0x485163, 0x30394B),
                 edge: DialogButtonFace.color(0x12161F), ink: .white,
                 highlight: 0.18, shade: 0.16, contact: 0.12, lift: 0.19, inset: 0.40, labelShade: 0.28)
        case .secondary:
            dark ? graphiteSecondary : Self(
                face: .init(0xFFFFFF, 0xF4F5F7), hover: .init(0xFFFFFF, 0xFAFAFB),
                edge: DialogButtonFace.color(0x0F172A, opacity: 0.14),
                highlight: 1, shade: 0.06, contact: 0.05, lift: 0.07, inset: 0.14, paperLine: 0.90
            )
        case .tertiary:
            dark ? graphiteTertiary : Self(
                face: .init(0xF3F4F6, 0xE7E9EC), hover: .init(0xF8F9FA, 0xEEF0F2),
                edge: DialogButtonFace.color(0x0F172A, opacity: 0.10),
                highlight: 0.85, shade: 0.06, contact: 0.035, lift: 0.055, inset: 0.16, paperLine: 0.90
            )
        case .ghost:
            ghost(dark: dark)
        case .text:
            Self(ink: Color(.sRGB, white: dark ? 0.76 : 0.32))
        }
    }

    private static let graphiteSecondary = Self(
        face: .init(0x373737, 0x2D2D2D), hover: .init(0x3C3C3C, 0x323232),
        edge: DialogButtonFace.color(0x222222), ink: DialogButtonFace.color(0xE2E2E2),
        highlight: 0.16, shade: 0.12, contact: 0.10, lift: 0.12, inset: 0.28, paperLine: 0.12
    )

    private static let graphiteTertiary = Self(
        face: .init(0x282828, 0x1D1D1D), hover: .init(0x2D2D2D, 0x232323),
        edge: DialogButtonFace.color(0x171717), ink: DialogButtonFace.color(0xCDCDCD),
        highlight: 0.10, shade: 0.08, contact: 0.06, lift: 0.08, inset: 0.24, paperLine: 0.08
    )

    private static func ghost(dark: Bool) -> Self {
        let tint: UInt32 = dark ? 0x232323 : 0xEBEBEB
        let clear = DialogButtonFace.resolved(tint, opacity: 0)
        let hover = DialogButtonFace.resolved(tint)
        let well = dark ? DialogButtonFace(0x181818, 0x242424) : DialogButtonFace(0xE1E1E1, 0xECECEC)
        return Self(face: .init(top: clear, bottom: clear), hover: .init(top: hover, bottom: hover), well: well,
                    ink: DialogButtonFace.color(dark ? 0xC3C3C3 : 0x444444), inset: dark ? 0.28 : 0.14)
    }
}

private struct DialogButtonMaterial: View {
    let palette: DialogButtonPalette
    let unit: CGFloat
    let face: CGPoint
    let shadows: CGPoint

    var body: some View {
        // The extra drawing area accommodates the 8/16/-5 hover shadow without changing layout.
        let outset = (8 + 16 - 5) * unit
        Canvas { context, size in
            let canvas = CGRect(origin: .zero, size: size)
            let rect = canvas.insetBy(dx: outset, dy: outset)
            let radius = WeiBeiMetric.DialogButton.cornerRadius * unit
            let outline = Path(roundedRect: rect, cornerRadius: radius, style: .circular)
            let interior = Path(roundedRect: rect.insetBy(dx: unit, dy: unit),
                                cornerRadius: radius - unit, style: .circular)
            let press = shadows.y
            let cutout = FillStyle(eoFill: true)

            // Keep the two cast shadows outside the button's round silhouette.
            let outside = Path { path in
                path.addRect(canvas)
                path.addPath(outline)
            }
            var exterior = context
            exterior.clip(to: outside, style: cutout)
            let liftY = depth(4, hover: 8, press: 1)
            let liftBlur = depth(10, hover: 16, press: 0)
            let spread = depth(-3, hover: -5, press: 0)
            let liftColor = shadowColor(black: palette.lift * (1 - press), white: palette.paperLine * press)
            let liftShape = Path(roundedRect: rect.insetBy(dx: -spread, dy: -spread),
                                 cornerRadius: radius + spread, style: .circular)
            drawShadow(liftShape, in: exterior, color: liftColor, blur: liftBlur, y: liftY)
            drawShadow(outline, in: exterior, color: shadowColor(black: palette.contact), blur: (2 - press) * unit, y: unit)

            if let restingFace = palette.face {
                context.fill(outline, with: .linearGradient(
                    restingFace.gradient(hover: palette.hover ?? restingFace, press: palette.well ?? restingFace.flipped,
                                         progress: face),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                ))
            }
            let edge = Path { path in
                path.addPath(outline)
                path.addPath(interior)
            }
            context.fill(edge, with: .color(palette.edge), style: cutout)

            // Both inset shadows share the actual inner edge and keep their slots during a press.
            let stencil = Path { path in
                path.addRect(canvas)
                path.addPath(interior)
            }
            var inner = context
            inner.clip(to: interior)
            drawShadow(stencil, in: inner, color: shadowColor(black: palette.shade * (1 - press)),
                       blur: 0, y: -unit * (1 - press), inverse: true)
            drawShadow(stencil, in: inner,
                       color: shadowColor(black: palette.inset * press, white: palette.highlight * (1 - press)),
                       blur: 2 * unit * press, y: unit, inverse: true)
        }
        .padding(-outset)
    }

    private func depth(_ rest: CGFloat, hover: CGFloat, press: CGFloat) -> CGFloat {
        (rest + (hover - rest) * shadows.x + (press - rest) * shadows.y) * unit
    }

    private func drawShadow(_ shape: Path, in context: GraphicsContext, color: Color, blur: CGFloat, y: CGFloat, inverse: Bool = false) {
        guard color != .clear else { return }
        context.drawLayer { layer in
            // The design specifies a blur diameter. SwiftUI takes a radius.
            layer.addFilter(.shadow(color: color, radius: blur / 2, x: 0, y: y, options: .shadowOnly))
            layer.fill(shape, with: .color(.black), style: FillStyle(eoFill: inverse))
        }
    }

    private func shadowColor(black: Double, white: Double = 0) -> Color {
        let opacity = black + white
        return opacity > 0 ? Color(.sRGB, white: white / opacity, opacity: opacity) : .clear
    }
}
