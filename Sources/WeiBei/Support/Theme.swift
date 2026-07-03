import SwiftUI

enum WeiBeiTheme {
    static let paper = Color(red: 0.955, green: 0.918, blue: 0.835)
    static let paperRaised = Color(red: 0.976, green: 0.944, blue: 0.872)
    static let paperInset = Color(red: 0.908, green: 0.858, blue: 0.748)
    static let chrome = Color(red: 0.155, green: 0.145, blue: 0.130)
    static let ink = Color(red: 0.115, green: 0.095, blue: 0.080)
    static let secondaryInk = Color(red: 0.335, green: 0.285, blue: 0.245)
    static let tertiaryInk = Color(red: 0.490, green: 0.430, blue: 0.365)
    static let hairline = Color(red: 0.500, green: 0.380, blue: 0.260).opacity(0.24)
    static let cinnabar = Color(red: 0.570, green: 0.150, blue: 0.105)
    static let cinnabarSoft = Color(red: 0.570, green: 0.150, blue: 0.105).opacity(0.10)
    static let link = Color(red: 0.190, green: 0.330, blue: 0.410)
    static let moss = Color(red: 0.230, green: 0.385, blue: 0.300)
    static let codePaper = Color(red: 0.180, green: 0.145, blue: 0.115).opacity(0.055)
    static let glassTint = Color(red: 0.982, green: 0.948, blue: 0.875)
    static let glassHighlight = Color(red: 0.992, green: 0.970, blue: 0.918)
    static let stone = secondaryInk
}

enum WeiBeiMetric {
    static let iconButton: CGFloat = 26
    static let inputHeight: CGFloat = 30
    static let controlRadius: CGFloat = 7
}

struct WeiBeiInputPrompt: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .opacity(0.96)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum WeiBeiMotion {
    static let press = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.82)
    static let micro = Animation.easeOut(duration: 0.14)
    static let hover = Animation.interactiveSpring(response: 0.20, dampingFraction: 0.86, blendDuration: 0.02)
    static let reveal = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.04)
    static let panel = Animation.interactiveSpring(response: 0.30, dampingFraction: 0.88, blendDuration: 0.06)
    static let layout = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.90, blendDuration: 0.08)
}

enum WeiBeiTransition {
    static let sidePanel = AnyTransition.asymmetric(
        insertion: reveal(x: -18, y: 0, scale: 0.992, blur: 1.5, anchor: .leading),
        removal: reveal(x: -12, y: 0, scale: 0.996, blur: 0.8, anchor: .leading)
    )

    static let commandPalette = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: -10, scale: 0.982, blur: 2, anchor: .top),
        removal: reveal(x: 0, y: -5, scale: 0.992, blur: 1, anchor: .top)
    )

    static let floating = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: 6, scale: 0.965, blur: 1.4, anchor: .center),
        removal: reveal(x: 0, y: 3, scale: 0.985, blur: 0.8, anchor: .center)
    )

    static let drawer = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: 18, scale: 0.988, blur: 1.4, anchor: .bottom),
        removal: reveal(x: 0, y: 10, scale: 0.994, blur: 0.8, anchor: .bottom)
    )

    static let rightPanel = AnyTransition.asymmetric(
        insertion: reveal(x: 16, y: 0, scale: 0.994, blur: 1.2, anchor: .trailing),
        removal: reveal(x: 10, y: 0, scale: 0.996, blur: 0.8, anchor: .trailing)
    )

    static let layout = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: 8, scale: 0.996, blur: 1.0, anchor: .center),
        removal: reveal(x: 0, y: -3, scale: 1.0, blur: 0.4, anchor: .center)
    )

    static let rail = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: 10, scale: 0.992, blur: 1.0, anchor: .top),
        removal: reveal(x: 0, y: -4, scale: 0.996, blur: 0.6, anchor: .top)
    )

    static let message = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: 8, scale: 0.988, blur: 0.8, anchor: .bottom),
        removal: reveal(x: 0, y: -4, scale: 0.996, blur: 0.4, anchor: .top)
    )

    private static func reveal(
        x: CGFloat,
        y: CGFloat,
        scale: CGFloat,
        blur: CGFloat,
        anchor: UnitPoint
    ) -> AnyTransition {
        .modifier(
            active: WeiBeiRevealModifier(opacity: 0, x: x, y: y, scale: scale, blur: blur, anchor: anchor),
            identity: WeiBeiRevealModifier(opacity: 1, x: 0, y: 0, scale: 1, blur: 0, anchor: anchor)
        )
    }
}

enum TopBarVariant: String, CaseIterable, Identifiable {
    case balanced
    case compact
    case reader
    case glyph
    case wide

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balanced:
            return "甲 纸脊"
        case .compact:
            return "乙 窄栏"
        case .reader:
            return "丙 阅读"
        case .glyph:
            return "丁 图形"
        case .wide:
            return "戊 宽排"
        }
    }

    var iconName: String {
        switch self {
        case .balanced:
            return "rectangle.topthird.inset.filled"
        case .compact:
            return "rectangle.compress.vertical"
        case .reader:
            return "doc.text.magnifyingglass"
        case .glyph:
            return "circle.grid.cross"
        case .wide:
            return "rectangle.expand.vertical"
        }
    }

    var height: CGFloat {
        switch self {
        case .glyph:
            return 36
        case .compact:
            return 38
        case .reader:
            return 40
        case .balanced:
            return 42
        case .wide:
            return 46
        }
    }
}

struct WeiBeiGlassHeaderBackground: View {
    var paperOpacity: Double = 0.72
    var materialOpacity: Double = 0.14

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(materialOpacity)

            Rectangle()
                .fill(WeiBeiTheme.paperRaised.opacity(paperWashOpacity))

            LinearGradient(
                colors: [
                    WeiBeiTheme.glassHighlight.opacity(0.20),
                    WeiBeiTheme.glassTint.opacity(0.24),
                    WeiBeiTheme.paper.opacity(0.13),
                    WeiBeiTheme.paper.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(WeiBeiTheme.paperInset.opacity(0.018))
        }
    }

    private var paperWashOpacity: Double {
        min(0.48, max(0.22, paperOpacity * 0.42))
    }
}

struct WeiBeiHeaderHandoffFade: View {
    var height: CGFloat = 18
    var opacity: Double = 1

    var body: some View {
        LinearGradient(
            colors: [
                WeiBeiTheme.glassTint.opacity(0.16 * opacity),
                WeiBeiTheme.paperRaised.opacity(0.13 * opacity),
                WeiBeiTheme.paper.opacity(0.08 * opacity),
                .clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

private struct WeiBeiRevealModifier: ViewModifier {
    var opacity: Double
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var blur: CGFloat
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: x, y: y)
            .scaleEffect(scale, anchor: anchor)
            .blur(radius: blur)
    }
}

struct WeiBeiIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var active = false
    var size = WeiBeiMetric.iconButton

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(foreground)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(WeiBeiMotion.press, value: configuration.isPressed)
    }

    private var foreground: Color {
        guard isEnabled else { return WeiBeiTheme.tertiaryInk.opacity(0.42) }
        return active ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk
    }

    private func background(isPressed: Bool) -> Color {
        if active { return WeiBeiTheme.cinnabarSoft }
        return isPressed ? WeiBeiTheme.paperInset.opacity(0.42) : WeiBeiTheme.paperInset.opacity(0.18)
    }
}

struct WeiBeiTextActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(WeiBeiMotion.press, value: configuration.isPressed)
    }

    private var foreground: Color {
        guard isEnabled else { return WeiBeiTheme.tertiaryInk.opacity(0.45) }
        return active ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk
    }

    private func background(isPressed: Bool) -> Color {
        if active { return WeiBeiTheme.cinnabarSoft }
        return isPressed ? WeiBeiTheme.paperInset.opacity(0.40) : WeiBeiTheme.paperInset.opacity(0.20)
    }
}

extension View {
    func weibeiPanel() -> some View {
        self
            .foregroundColor(WeiBeiTheme.ink)
            .background(WeiBeiTheme.paperRaised.opacity(0.90))
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        WeiBeiTheme.glassHighlight.opacity(0.24),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 12)
            }
    }

    func weibeiInputSurface(active: Bool = false, height: CGFloat = WeiBeiMetric.inputHeight) -> some View {
        self
            .foregroundColor(WeiBeiTheme.ink)
            .foregroundStyle(WeiBeiTheme.ink)
            .tint(WeiBeiTheme.link)
            .environment(\.colorScheme, .light)
            .padding(.horizontal, 10)
            .frame(minHeight: height)
            .background(WeiBeiTheme.paperInset.opacity(active ? 0.52 : 0.30))
            .clipShape(RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius)
                    .stroke(active ? WeiBeiTheme.link.opacity(0.45) : WeiBeiTheme.hairline, lineWidth: 1)
            }
            .animation(WeiBeiMotion.reveal, value: active)
    }

    func weibeiFloatingPanel(cornerRadius: CGFloat = 8, shadowOpacity: Double = 0.10) -> some View {
        self
            .foregroundColor(WeiBeiTheme.ink)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(WeiBeiTheme.paperRaised.opacity(0.92))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(0.06)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(WeiBeiTheme.glassHighlight.opacity(0.24))
                    .frame(height: 1)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(WeiBeiTheme.hairline, lineWidth: 1)
            }
            .shadow(color: WeiBeiTheme.ink.opacity(shadowOpacity * 0.50), radius: 7, y: 3)
    }

    func weibeiAnnotationPanel(cornerRadius: CGFloat = 7) -> some View {
        self
            .foregroundStyle(WeiBeiTheme.ink)
            .background(WeiBeiTheme.paperRaised.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(WeiBeiTheme.hairline.opacity(0.86), lineWidth: 1)
            }
            .shadow(color: WeiBeiTheme.ink.opacity(0.045), radius: 7, y: 3)
    }

    func weibeiHoverLift(active: Bool, amount: CGFloat = 1.5) -> some View {
        self
            .offset(y: active ? -amount : 0)
            .shadow(color: WeiBeiTheme.ink.opacity(active ? 0.055 : 0), radius: 8, y: 4)
            .animation(WeiBeiMotion.hover, value: active)
    }
}
