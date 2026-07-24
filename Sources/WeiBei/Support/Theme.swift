import AppKit
import CoreText
import SwiftUI
import WeiBeiCore

/// Four surface themes. Light pair: 纸面 (warm product paper) + 宣纸 (cooler fibrous xuan).
/// Dark pair: 墨石 (near-black warm ink) + 石碑 (cool carved stele grey).
enum WeiBeiAppearanceMode: String, CaseIterable, Identifiable {
    case paper
    case xuan
    case inkstone
    case stele

    var id: String { rawValue }

    /// True for both dark surfaces (墨石 / 石碑). Prefer this over `== .inkstone`.
    var isDark: Bool {
        switch self {
        case .paper, .xuan: return false
        case .inkstone, .stele: return true
        }
    }

    func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .paper:
            return language.text("纸面", "Paper")
        case .xuan:
            return language.text("宣纸", "Xuan")
        case .inkstone:
            return language.text("墨石", "Inkstone")
        case .stele:
            return language.text("石碑", "Stele")
        }
    }

    func detail(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .paper:
            return language.text("暖色产品纸面", "Warm product paper")
        case .xuan:
            return language.text("素净宣纸白", "Cool fibrous xuan white")
        case .inkstone:
            return language.text("暖黑墨石", "Warm near-black ink")
        case .stele:
            return language.text("冷灰碑面", "Cool carved stone")
        }
    }

    func actionLabel(language: WeiBeiInterfaceLanguage) -> String {
        language.text("切换外观主题", "Switch appearance theme")
    }

    var systemImage: String {
        switch self {
        case .paper:
            return "sun.max"
        case .xuan:
            return "doc.plaintext"
        case .inkstone:
            return "moon.stars"
        case .stele:
            return "rectangle.split.3x1"
        }
    }

    var colorScheme: ColorScheme {
        isDark ? .dark : .light
    }

    var webThemeName: String {
        rawValue
    }

    var windowBackground: NSColor {
        WeiBeiNativePalette.paper(for: self)
    }

    /// Cycles all four themes (used by legacy toggle API / shortcuts).
    var toggled: WeiBeiAppearanceMode {
        switch self {
        case .paper: return .xuan
        case .xuan: return .inkstone
        case .inkstone: return .stele
        case .stele: return .paper
        }
    }

    /// Next theme in the light↔dark pair, or full cycle when no pair preference.
    var oppositeFamily: WeiBeiAppearanceMode {
        isDark ? .paper : .inkstone
    }
}

/// Live appearance used by dynamic `WeiBeiTheme` colors. Updated when the store
/// changes mode so SwiftUI redraws pick the correct palette.
enum WeiBeiThemeRuntime {
    static var mode: WeiBeiAppearanceMode = .paper
}

enum WeiBeiTypography {
    static let englishDisplayFontName = "WeiBeiStele-Regular"
    static let englishMonoFontName = "WeiBeiSteleMono-Regular"

    private static var didRegisterBundledFonts = false

    static func registerBundledFonts() {
        guard !didRegisterBundledFonts else { return }
        didRegisterBundledFonts = true
        ["WeiBeiStele", "WeiBeiSteleMono"].forEach { name in
            guard let url = WeiBeiResources.bundle.url(forResource: name, withExtension: "ttf")
                ?? WeiBeiResources.bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
            else { return }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func brandFont(language: WeiBeiInterfaceLanguage, size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        switch language {
        case .chinese:
            return .system(size: size, weight: weight, design: .serif)
        case .english:
            registerBundledFonts()
            return .custom(englishDisplayFontName, size: size).weight(weight)
        }
    }

    static func englishBrandFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        registerBundledFonts()
        return .custom(englishDisplayFontName, size: size).weight(weight)
    }

    static func monoFont(language: WeiBeiInterfaceLanguage, size: CGFloat) -> Font {
        switch language {
        case .chinese:
            return .system(size: size, design: .monospaced)
        case .english:
            registerBundledFonts()
            return .custom(englishMonoFontName, size: size)
        }
    }
}

private struct WeiBeiTone {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: Int, alpha: CGFloat = 1) {
        self.red = CGFloat((hex >> 16) & 0xFF) / 255
        self.green = CGFloat((hex >> 8) & 0xFF) / 255
        self.blue = CGFloat(hex & 0xFF) / 255
        self.alpha = alpha
    }

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension Color {
    /// Resolve a four-mode palette from `WeiBeiThemeRuntime.mode` (not system appearance alone).
    static func weiBei(
        paper: WeiBeiTone,
        xuan: WeiBeiTone,
        inkstone: WeiBeiTone,
        stele: WeiBeiTone
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { _ in
            switch WeiBeiThemeRuntime.mode {
            case .paper: return paper.nsColor
            case .xuan: return xuan.nsColor
            case .inkstone: return inkstone.nsColor
            case .stele: return stele.nsColor
            }
        })
    }

    /// Convenience when light-pair / dark-pair share tones.
    static func weiBei(light: WeiBeiTone, dark: WeiBeiTone) -> Color {
        weiBei(paper: light, xuan: light, inkstone: dark, stele: dark)
    }
}

enum WeiBeiTheme {
    // 纸面 = warm product paper; 宣纸 = cooler fibrous white; 墨石 = warm black; 石碑 = cool stele grey.
    static let paper = Color.weiBei(
        paper: WeiBeiTone(red: 0.955, green: 0.918, blue: 0.835),
        xuan: WeiBeiTone(red: 0.972, green: 0.962, blue: 0.942),
        inkstone: WeiBeiTone(hex: 0x0F0F0F),
        stele: WeiBeiTone(hex: 0x16181C)
    )
    static let paperRaised = Color.weiBei(
        paper: WeiBeiTone(red: 0.976, green: 0.944, blue: 0.872),
        xuan: WeiBeiTone(red: 0.992, green: 0.988, blue: 0.978),
        inkstone: WeiBeiTone(hex: 0x151515),
        stele: WeiBeiTone(hex: 0x1E2228)
    )
    static let paperInset = Color.weiBei(
        paper: WeiBeiTone(red: 0.908, green: 0.858, blue: 0.748),
        xuan: WeiBeiTone(red: 0.930, green: 0.918, blue: 0.892),
        inkstone: WeiBeiTone(hex: 0x1C1C1C),
        stele: WeiBeiTone(hex: 0x252A32)
    )
    static let chrome = Color.weiBei(
        paper: WeiBeiTone(red: 0.155, green: 0.145, blue: 0.130),
        xuan: WeiBeiTone(red: 0.140, green: 0.138, blue: 0.132),
        inkstone: WeiBeiTone(hex: 0x0B0B0B),
        stele: WeiBeiTone(hex: 0x101217)
    )
    static let ink = Color.weiBei(
        paper: WeiBeiTone(red: 0.115, green: 0.095, blue: 0.080),
        xuan: WeiBeiTone(red: 0.145, green: 0.140, blue: 0.128),
        inkstone: WeiBeiTone(hex: 0xD7CBB0),
        stele: WeiBeiTone(hex: 0xD2D6DC)
    )
    static let secondaryInk = Color.weiBei(
        paper: WeiBeiTone(red: 0.335, green: 0.285, blue: 0.245),
        xuan: WeiBeiTone(red: 0.360, green: 0.345, blue: 0.320),
        inkstone: WeiBeiTone(hex: 0x9B9178),
        stele: WeiBeiTone(hex: 0x9AA1AB)
    )
    static let tertiaryInk = Color.weiBei(
        paper: WeiBeiTone(red: 0.490, green: 0.430, blue: 0.365),
        xuan: WeiBeiTone(red: 0.500, green: 0.480, blue: 0.450),
        inkstone: WeiBeiTone(hex: 0x6F6655),
        stele: WeiBeiTone(hex: 0x6E7682)
    )
    static let placeholderInk = Color.weiBei(
        paper: WeiBeiTone(red: 0.405, green: 0.345, blue: 0.290),
        xuan: WeiBeiTone(red: 0.430, green: 0.410, blue: 0.380),
        inkstone: WeiBeiTone(hex: 0xAFA48C),
        stele: WeiBeiTone(hex: 0xA8AFB8)
    )
    static let hairline = Color.weiBei(
        paper: WeiBeiTone(red: 0.500, green: 0.380, blue: 0.260, alpha: 0.24),
        xuan: WeiBeiTone(red: 0.420, green: 0.400, blue: 0.360, alpha: 0.22),
        inkstone: WeiBeiTone(hex: 0x3A3328, alpha: 0.72),
        stele: WeiBeiTone(hex: 0x3A414C, alpha: 0.78)
    )
    static let cinnabar = Color.weiBei(
        paper: WeiBeiTone(red: 0.570, green: 0.150, blue: 0.105),
        xuan: WeiBeiTone(red: 0.540, green: 0.145, blue: 0.110),
        inkstone: WeiBeiTone(hex: 0xA6362B),
        stele: WeiBeiTone(hex: 0xB04034)
    )
    static let cinnabarSoft = Color.weiBei(
        paper: WeiBeiTone(red: 0.570, green: 0.150, blue: 0.105, alpha: 0.10),
        xuan: WeiBeiTone(red: 0.540, green: 0.145, blue: 0.110, alpha: 0.09),
        inkstone: WeiBeiTone(hex: 0x5C2621, alpha: 0.62),
        stele: WeiBeiTone(hex: 0x5A2A28, alpha: 0.58)
    )
    static let onCinnabar = Color.weiBei(
        paper: WeiBeiTone(hex: 0xF8EAD4),
        xuan: WeiBeiTone(hex: 0xF7F2EA),
        inkstone: WeiBeiTone(hex: 0xF3DEC2),
        stele: WeiBeiTone(hex: 0xE8ECF0)
    )
    static let link = Color.weiBei(
        paper: WeiBeiTone(red: 0.190, green: 0.330, blue: 0.410),
        xuan: WeiBeiTone(red: 0.200, green: 0.320, blue: 0.390),
        inkstone: WeiBeiTone(hex: 0xC8B98A),
        stele: WeiBeiTone(hex: 0xB8C4D0)
    )
    static let moss = Color.weiBei(
        paper: WeiBeiTone(red: 0.230, green: 0.385, blue: 0.300),
        xuan: WeiBeiTone(red: 0.250, green: 0.380, blue: 0.310),
        inkstone: WeiBeiTone(hex: 0xB88A42),
        stele: WeiBeiTone(hex: 0x8FA06A)
    )
    static let codePaper = Color.weiBei(
        paper: WeiBeiTone(red: 0.180, green: 0.145, blue: 0.115, alpha: 0.055),
        xuan: WeiBeiTone(red: 0.160, green: 0.150, blue: 0.130, alpha: 0.050),
        inkstone: WeiBeiTone(hex: 0x171717, alpha: 0.92),
        stele: WeiBeiTone(hex: 0x1A1E24, alpha: 0.94)
    )
    static let glassTint = Color.weiBei(
        paper: WeiBeiTone(red: 0.982, green: 0.948, blue: 0.875),
        xuan: WeiBeiTone(red: 0.988, green: 0.984, blue: 0.974),
        inkstone: WeiBeiTone(hex: 0x1A1814),
        stele: WeiBeiTone(hex: 0x1C2026)
    )
    static let glassHighlight = Color.weiBei(
        paper: WeiBeiTone(red: 0.992, green: 0.970, blue: 0.918),
        xuan: WeiBeiTone(red: 0.995, green: 0.992, blue: 0.986),
        inkstone: WeiBeiTone(hex: 0x3A3328),
        stele: WeiBeiTone(hex: 0x3E4652)
    )
    static let stone = secondaryInk
}

enum WeiBeiNativePalette {
    static func paper(for mode: WeiBeiAppearanceMode) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.955, green: 0.918, blue: 0.835, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.972, green: 0.962, blue: 0.942, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.059, green: 0.059, blue: 0.059, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.086, green: 0.094, blue: 0.110, alpha: 1.0)
        }
    }

    static func ink(for mode: WeiBeiAppearanceMode) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.115, green: 0.095, blue: 0.080, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.145, green: 0.140, blue: 0.128, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.843, green: 0.796, blue: 0.690, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.824, green: 0.839, blue: 0.863, alpha: 1.0)
        }
    }

    static func selectedText(for mode: WeiBeiAppearanceMode) -> NSColor {
        switch mode {
        case .paper, .xuan:
            return ink(for: mode)
        case .inkstone:
            return NSColor(calibratedRed: 0.961, green: 0.906, blue: 0.784, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.930, green: 0.940, blue: 0.955, alpha: 1.0)
        }
    }

    static func selectionFill(for mode: WeiBeiAppearanceMode) -> NSColor {
        switch mode {
        case .paper, .xuan:
            return NSColor(calibratedRed: 0.570, green: 0.150, blue: 0.105, alpha: 0.20)
        case .inkstone:
            return NSColor(calibratedRed: 0.651, green: 0.212, blue: 0.169, alpha: 0.35)
        case .stele:
            return NSColor(calibratedRed: 0.690, green: 0.250, blue: 0.200, alpha: 0.32)
        }
    }
}

enum WeiBeiMetric {
    static let iconButton: CGFloat = 26
    static let inputHeight: CGFloat = 30
    static let controlRadius: CGFloat = 7
    static let topBarHeight: CGFloat = 38
}

/// Top-bar brand mark (DesignSystem logo exports bundled under Resources/Brand).
enum WeiBeiBrandMark {
    static func image(for mode: WeiBeiAppearanceMode) -> NSImage {
        let name = mode.isDark ? "weibei-mark-reversed" : "weibei-mark"
        if let url = WeiBeiResources.bundle.url(forResource: name, withExtension: "png", subdirectory: "Brand")
            ?? WeiBeiResources.bundle.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            return image
        }
        // Fallback: empty 1×1 so layout never crashes if resources are missing.
        return NSImage(size: NSSize(width: 1, height: 1))
    }
}

enum WeiBeiMotion {
    static let press = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.82)
    static let micro = Animation.easeOut(duration: 0.14)
    static let hover = Animation.interactiveSpring(response: 0.20, dampingFraction: 0.86, blendDuration: 0.02)
    static let reveal = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.04)
    static let panel = Animation.interactiveSpring(response: 0.26, dampingFraction: 0.90, blendDuration: 0.04)
    /// Pane / layout swaps: short ease-out — long springs + blur felt laggy over WebView panes.
    static let layout = Animation.easeOut(duration: 0.18)
    static let appearance = Animation.easeInOut(duration: 0.42)
    /// Course drawer: snappy ease-out slide (visual only; never wrap focus changes).
    static let sideDrawer = Animation.easeOut(duration: 0.12)
}

enum WeiBeiTransition {
    // No blur: blur during large panel open forces offscreen raster of the whole workspace.
    // Kept for call sites that still use transition insertion; ContentView uses offset slide.
    static let sidePanel = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
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

    // No blur on layout/rail — blur rasterizes whole pane hosts (reader/agent/notes) every frame.
    static let layout = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: 6, scale: 1.0, blur: 0, anchor: .center),
        removal: reveal(x: 0, y: -2, scale: 1.0, blur: 0, anchor: .center)
    )

    static let rail = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: 6, scale: 1.0, blur: 0, anchor: .top),
        removal: reveal(x: 0, y: -2, scale: 1.0, blur: 0, anchor: .top)
    )

    // No blur: agent LazyVStack rows must not pay blur cost on insert/remove.
    static let message = AnyTransition.asymmetric(
        insertion: reveal(x: 0, y: 6, scale: 1.0, blur: 0, anchor: .bottom),
        removal: reveal(x: 0, y: -3, scale: 1.0, blur: 0, anchor: .top)
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

struct WeiBeiGlassHeaderBackground: View {
    var paperOpacity: Double = 0.72
    var materialOpacity: Double = 0.14
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(materialOpacity)

            Rectangle()
                .fill(WeiBeiTheme.paperRaised.opacity(paperWashOpacity))

            LinearGradient(
                colors: [
                    WeiBeiTheme.glassHighlight.opacity(colorScheme == .dark ? 0.12 : 0.20),
                    WeiBeiTheme.glassTint.opacity(colorScheme == .dark ? 0.16 : 0.24),
                    WeiBeiTheme.paperRaised.opacity(colorScheme == .dark ? 0.12 : 0.13),
                    WeiBeiTheme.paper.opacity(colorScheme == .dark ? 0.10 : 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Rectangle()
                .fill(WeiBeiTheme.paperInset.opacity(0.018))
        }
    }

    private var paperWashOpacity: Double {
        let factor = colorScheme == .dark ? 0.30 : 0.42
        return min(colorScheme == .dark ? 0.34 : 0.48, max(0.20, paperOpacity * factor))
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

enum WeiBeiIconButtonProminence {
    case neutral
    case primary
}

struct WeiBeiIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var active = false
    var size = WeiBeiMetric.iconButton
    var prominence: WeiBeiIconButtonProminence = .neutral

    func makeBody(configuration: Configuration) -> some View {
        WeiBeiIconButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            active: active,
            size: size,
            prominence: prominence
        )
    }
}

private struct WeiBeiIconButtonBody: View {
    @Environment(\.colorScheme) private var colorScheme
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    let active: Bool
    let size: CGFloat
    let prominence: WeiBeiIconButtonProminence
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : hovering ? 1.015 : 1)
            .animation(WeiBeiMotion.press, value: configuration.isPressed)
            .animation(WeiBeiMotion.hover, value: hovering)
            .onHover { isHovering in
                hovering = isEnabled && isHovering
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    hovering = false
                }
            }
    }

    private func foreground(isPressed: Bool) -> Color {
        guard isEnabled else { return WeiBeiTheme.tertiaryInk.opacity(0.58) }
        if prominence == .primary {
            return (isPressed || hovering) ? WeiBeiTheme.onCinnabar : WeiBeiTheme.cinnabar
        }
        if active { return WeiBeiTheme.cinnabar }
        if isPressed || hovering { return WeiBeiTheme.ink }
        return WeiBeiTheme.secondaryInk
    }

    private func background(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.clear }
        if prominence == .primary {
            if isPressed || hovering {
                return WeiBeiTheme.cinnabar.opacity(primaryOpacity(isPressed: isPressed))
            }
            return colorScheme == .dark
                ? WeiBeiTheme.paperInset.opacity(0.58)
                : WeiBeiTheme.cinnabarSoft.opacity(0.72)
        }
        if active {
            return WeiBeiTheme.cinnabarSoft.opacity(activeOpacity(isPressed: isPressed))
        }
        if isPressed { return WeiBeiTheme.paperInset.opacity(0.46) }
        if hovering { return WeiBeiTheme.paperInset.opacity(colorScheme == .dark ? 0.34 : 0.28) }
        return Color.clear
    }

    private var border: Color {
        guard isEnabled else { return Color.clear }
        if prominence == .primary {
            if configuration.isPressed || hovering {
                return WeiBeiTheme.cinnabar.opacity(colorScheme == .dark ? 0.62 : 0.42)
            }
            return colorScheme == .dark
                ? WeiBeiTheme.hairline.opacity(0.76)
                : WeiBeiTheme.cinnabar.opacity(0.18)
        }
        if active {
            return WeiBeiTheme.cinnabar.opacity(hovering ? (colorScheme == .dark ? 0.50 : 0.42) : (colorScheme == .dark ? 0.34 : 0.25))
        }
        return hovering ? WeiBeiTheme.hairline.opacity(colorScheme == .dark ? 0.92 : 0.72) : Color.clear
    }

    private func primaryOpacity(isPressed: Bool) -> Double {
        if colorScheme == .dark {
            return isPressed ? 0.88 : 0.70
        }
        return isPressed ? 0.90 : 0.78
    }

    private func activeOpacity(isPressed: Bool) -> Double {
        if colorScheme == .dark {
            return isPressed ? 0.72 : hovering ? 0.58 : 0.42
        }
        return isPressed ? 0.86 : hovering ? 0.68 : 0.52
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
        guard isEnabled else { return WeiBeiTheme.tertiaryInk.opacity(0.60) }
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

    func weibeiInputSurface(
        active: Bool = false,
        height: CGFloat = WeiBeiMetric.inputHeight,
        horizontalPadding: CGFloat = 10
    ) -> some View {
        self
            .foregroundColor(WeiBeiTheme.ink)
            .foregroundStyle(WeiBeiTheme.ink)
            .tint(WeiBeiTheme.link)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius)
                    .fill(WeiBeiTheme.paperRaised.opacity(active ? 0.66 : 0.60))
            }
            .clipShape(RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius)
                    .stroke(WeiBeiTheme.glassHighlight.opacity(active ? 0.34 : 0.24), lineWidth: 1)
                    .padding(1)
            }
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius)
                    .stroke(WeiBeiTheme.paperInset.opacity(active ? 0.30 : 0.38), lineWidth: 1)
                    .padding(0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: WeiBeiMetric.controlRadius)
                    .stroke(active ? WeiBeiTheme.link.opacity(0.34) : WeiBeiTheme.hairline.opacity(0.54), lineWidth: 1)
            }
            .animation(WeiBeiMotion.reveal, value: active)
    }

    func weibeiFloatingPanel(cornerRadius: CGFloat = 8, shadowOpacity: Double = 0.10) -> some View {
        self
            .foregroundColor(WeiBeiTheme.ink)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(WeiBeiTheme.paperRaised.opacity(0.985))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(0.015)
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
