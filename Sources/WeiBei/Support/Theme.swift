import AppKit
import CoreText
import SwiftUI
import WeiBeiCore

/// Eight surface themes: four paper/stone palettes plus two light/dark glass pairs.
enum WeiBeiAppearanceMode: String, CaseIterable, Identifiable {
    case paper
    case xuan
    case inkstone
    case stele
    case glassLight
    case glassDark
    case glassMist
    case glassSlate

    var id: String { rawValue }

    /// Prefer this over checking individual dark palettes.
    var isDark: Bool {
        switch self {
        case .paper, .xuan, .glassLight, .glassMist: return false
        case .inkstone, .stele, .glassDark, .glassSlate: return true
        }
    }

    var isGlass: Bool {
        switch self {
        case .glassLight, .glassDark, .glassMist, .glassSlate: return true
        default: return false
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
        case .glassLight:
            return language.text("晴璃", "Clear Glass")
        case .glassDark:
            return language.text("夜璃", "Dark Glass")
        case .glassMist:
            return language.text("雾璃", "Mist Glass")
        case .glassSlate:
            return language.text("玄璃", "Slate Glass")
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
        case .glassLight:
            return language.text("明亮液态磨砂玻璃", "Bright liquid frosted glass")
        case .glassDark:
            return language.text("深色液态磨砂玻璃", "Dark liquid frosted glass")
        case .glassMist:
            return language.text("雾白磨砂玻璃", "Mist-white frosted glass")
        case .glassSlate:
            return language.text("玄蓝磨砂玻璃", "Slate-blue frosted glass")
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
        case .glassLight:
            return "sun.haze"
        case .glassDark:
            return "moon.haze"
        case .glassMist:
            return "cloud.fog"
        case .glassSlate:
            return "cloud.moon"
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

    /// Cycles all themes (used by legacy toggle API / shortcuts).
    var toggled: WeiBeiAppearanceMode {
        switch self {
        case .paper: return .xuan
        case .xuan: return .inkstone
        case .inkstone: return .stele
        case .stele: return .glassLight
        case .glassLight: return .glassDark
        case .glassDark: return .glassMist
        case .glassMist: return .glassSlate
        case .glassSlate: return .paper
        }
    }

    /// Next theme in the light↔dark pair, or full cycle when no pair preference.
    var oppositeFamily: WeiBeiAppearanceMode {
        switch self {
        case .glassLight: return .glassDark
        case .glassDark: return .glassLight
        case .glassMist: return .glassSlate
        case .glassSlate: return .glassMist
        default: return isDark ? .paper : .inkstone
        }
    }
}

/// Live appearance used by theme colors. Always update **before** publishing
/// `appearanceMode` so SwiftUI bodies that re-read `WeiBeiTheme.*` see the new palette.
enum WeiBeiThemeRuntime {
    static var mode: WeiBeiAppearanceMode = .paper
    /// Posted after mode changes so AppKit views (PDF mask, splitters) can redraw.
    static let didChangeNotification = Notification.Name("WeiBeiThemeRuntimeDidChange")
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

enum WeiBeiTheme {
    // Computed colors — resolved from the current mode on every access.
    // Static `Color(nsColor:)` only re-queries on system appearance change, so
    // paper↔xuan / inkstone↔stele switches would otherwise look "stuck".
    // Call sites re-evaluate when `@Published appearanceMode` changes.

    static var paper: Color { Color(nsColor: WeiBeiNativePalette.paper()) }
    static var paperRaised: Color { Color(nsColor: WeiBeiNativePalette.paperRaised()) }
    static var paperInset: Color { Color(nsColor: WeiBeiNativePalette.paperInset()) }
    static var chrome: Color { Color(nsColor: WeiBeiNativePalette.chrome()) }
    static var ink: Color { Color(nsColor: WeiBeiNativePalette.ink()) }
    static var secondaryInk: Color { Color(nsColor: WeiBeiNativePalette.secondaryInk()) }
    static var tertiaryInk: Color { Color(nsColor: WeiBeiNativePalette.tertiaryInk()) }
    static var placeholderInk: Color { Color(nsColor: WeiBeiNativePalette.placeholderInk()) }
    static var hairline: Color { Color(nsColor: WeiBeiNativePalette.hairline()) }
    static var cinnabar: Color { Color(nsColor: WeiBeiNativePalette.cinnabar()) }
    static var cinnabarSoft: Color { Color(nsColor: WeiBeiNativePalette.cinnabarSoft()) }
    static var onCinnabar: Color { Color(nsColor: WeiBeiNativePalette.onCinnabar()) }
    static var link: Color { Color(nsColor: WeiBeiNativePalette.link()) }
    static var moss: Color { Color(nsColor: WeiBeiNativePalette.moss()) }
    static var codePaper: Color { Color(nsColor: WeiBeiNativePalette.codePaper()) }
    static var glassTint: Color { Color(nsColor: WeiBeiNativePalette.glassTint()) }
    static var glassHighlight: Color { Color(nsColor: WeiBeiNativePalette.glassHighlight()) }
    static var stone: Color { secondaryInk }
}

/// One native behind-window material layer for each glass window.
struct WeiBeiThemeBackdrop: View {
    let mode: WeiBeiAppearanceMode
    var isFullScreen = false

    @ViewBuilder
    var body: some View {
        if mode.isGlass {
            ZStack {
                WeiBeiBehindWindowMaterial(
                    mode: mode,
                    isFullScreen: isFullScreen
                )
                Color(nsColor: WeiBeiNativePalette.glassBaseTint(for: mode))
            }
        } else {
            Color(nsColor: WeiBeiNativePalette.paper(for: mode))
        }
    }
}

private struct WeiBeiBehindWindowMaterial: NSViewRepresentable {
    let mode: WeiBeiAppearanceMode
    let isFullScreen: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = mode.isDark
            ? .hudWindow
            : isFullScreen ? .windowBackground : .underWindowBackground
        view.alphaValue = mode.isDark ? 0.68 : isFullScreen ? 0.88 : 0.36
    }
}

/// AppKit / WebKit palette — single source of truth for all eight themes.
/// Prefer these over hard-coded paper/inkstone RGB pairs in native views.
enum WeiBeiNativePalette {
    /// Current mode used by AppKit code that cannot take an explicit mode parameter.
    static var current: WeiBeiAppearanceMode { WeiBeiThemeRuntime.mode }

    static func paper(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.955, green: 0.918, blue: 0.835, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.972, green: 0.962, blue: 0.942, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.059, green: 0.059, blue: 0.059, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.086, green: 0.094, blue: 0.110, alpha: 1.0)
        case .glassLight, .glassDark, .glassMist, .glassSlate:
            return .clear
        }
    }

    static func paperRaised(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.976, green: 0.944, blue: 0.872, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.992, green: 0.988, blue: 0.978, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.082, green: 0.082, blue: 0.082, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.118, green: 0.133, blue: 0.157, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.965, green: 0.980, blue: 1.000, alpha: 0.18)
        case .glassDark:
            return NSColor(calibratedRed: 0.105, green: 0.135, blue: 0.185, alpha: 0.22)
        case .glassMist:
            return NSColor(calibratedRed: 0.957, green: 0.976, blue: 1.000, alpha: 0.72)
        case .glassSlate:
            return NSColor(calibratedRed: 0.106, green: 0.129, blue: 0.169, alpha: 0.66)
        }
    }

    static func paperInset(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.908, green: 0.858, blue: 0.748, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.930, green: 0.918, blue: 0.892, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.110, green: 0.110, blue: 0.110, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.145, green: 0.165, blue: 0.196, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.700, green: 0.760, blue: 0.830, alpha: 0.13)
        case .glassDark:
            return NSColor(calibratedRed: 0.180, green: 0.230, blue: 0.310, alpha: 0.16)
        case .glassMist:
            return NSColor(calibratedRed: 0.700, green: 0.760, blue: 0.830, alpha: 0.16)
        case .glassSlate:
            return NSColor(calibratedRed: 0.180, green: 0.220, blue: 0.290, alpha: 0.20)
        }
    }

    static func glassBaseTint(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .glassLight:
            return NSColor(calibratedRed: 0.94, green: 0.98, blue: 1.00, alpha: 0.02)
        case .glassDark:
            return NSColor(calibratedRed: 0.025, green: 0.040, blue: 0.065, alpha: 0.46)
        case .glassMist:
            return NSColor(calibratedRed: 0.957, green: 0.976, blue: 1.000, alpha: 0.22)
        case .glassSlate:
            return NSColor(calibratedRed: 0.106, green: 0.129, blue: 0.169, alpha: 0.46)
        default:
            return .clear
        }
    }

    /// Raised drawer surface. Glass themes keep one window blur and use only a
    /// translucent tint here so foreground navigation stays legible.
    static func drawerSurface(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .glassLight:
            return NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 0.20)
        case .glassDark:
            return NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.105, alpha: 0.28)
        case .glassMist:
            return NSColor(calibratedRed: 0.957, green: 0.976, blue: 1.000, alpha: 0.36)
        case .glassSlate:
            return NSColor(calibratedRed: 0.106, green: 0.129, blue: 0.169, alpha: 0.46)
        default:
            return paper(for: mode)
        }
    }

    /// Full-window foreground workspace surface. It must hide any open drawer
    /// below it while remaining visibly translucent to the desktop material.
    static func foregroundWorkspaceSurface(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .glassLight:
            return NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 0.12)
        case .glassDark:
            return NSColor(calibratedRed: 0.040, green: 0.055, blue: 0.080, alpha: 0.22)
        case .glassMist:
            return NSColor(calibratedRed: 0.957, green: 0.976, blue: 1.000, alpha: 0.28)
        case .glassSlate:
            return NSColor(calibratedRed: 0.106, green: 0.129, blue: 0.169, alpha: 0.38)
        default:
            return paper(for: mode)
        }
    }

    static func ink(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.115, green: 0.095, blue: 0.080, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.145, green: 0.140, blue: 0.128, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.843, green: 0.796, blue: 0.690, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.824, green: 0.839, blue: 0.863, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.090, green: 0.115, blue: 0.150, alpha: 0.96)
        case .glassDark:
            return NSColor(calibratedRed: 0.910, green: 0.935, blue: 0.975, alpha: 0.98)
        case .glassMist:
            return NSColor(calibratedRed: 0.145, green: 0.140, blue: 0.128, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.824, green: 0.839, blue: 0.863, alpha: 1.0)
        }
    }

    static func secondaryInk(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.335, green: 0.285, blue: 0.245, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.360, green: 0.345, blue: 0.320, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.608, green: 0.569, blue: 0.471, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.604, green: 0.631, blue: 0.671, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.275, green: 0.315, blue: 0.370, alpha: 0.92)
        case .glassDark:
            return NSColor(calibratedRed: 0.680, green: 0.730, blue: 0.800, alpha: 0.94)
        case .glassMist:
            return NSColor(calibratedRed: 0.360, green: 0.345, blue: 0.320, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.604, green: 0.631, blue: 0.671, alpha: 1.0)
        }
    }

    static func tertiaryInk(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.490, green: 0.430, blue: 0.365, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.500, green: 0.480, blue: 0.450, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.435, green: 0.400, blue: 0.333, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.430, green: 0.460, blue: 0.510, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.430, green: 0.480, blue: 0.550, alpha: 0.82)
        case .glassDark:
            return NSColor(calibratedRed: 0.480, green: 0.550, blue: 0.640, alpha: 0.86)
        case .glassMist:
            return NSColor(calibratedRed: 0.500, green: 0.480, blue: 0.450, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.430, green: 0.460, blue: 0.510, alpha: 1.0)
        }
    }

    static func hairline(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.500, green: 0.380, blue: 0.260, alpha: 0.24)
        case .xuan:
            return NSColor(calibratedRed: 0.420, green: 0.400, blue: 0.360, alpha: 0.22)
        case .inkstone:
            return NSColor(calibratedRed: 0.227, green: 0.200, blue: 0.157, alpha: 0.72)
        case .stele:
            return NSColor(calibratedRed: 0.227, green: 0.255, blue: 0.298, alpha: 0.78)
        case .glassLight:
            return NSColor(calibratedRed: 0.280, green: 0.350, blue: 0.440, alpha: 0.24)
        case .glassDark:
            return NSColor(calibratedRed: 0.790, green: 0.860, blue: 0.950, alpha: 0.26)
        case .glassMist:
            return NSColor(calibratedRed: 0.275, green: 0.350, blue: 0.455, alpha: 0.18)
        case .glassSlate:
            return NSColor(calibratedRed: 0.725, green: 0.776, blue: 0.847, alpha: 0.14)
        }
    }

    static func cinnabar(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.570, green: 0.150, blue: 0.105, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.540, green: 0.145, blue: 0.110, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.651, green: 0.212, blue: 0.169, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.690, green: 0.250, blue: 0.200, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.610, green: 0.155, blue: 0.115, alpha: 1.0)
        case .glassDark:
            return NSColor(calibratedRed: 0.920, green: 0.335, blue: 0.275, alpha: 1.0)
        case .glassMist:
            return NSColor(calibratedRed: 0.540, green: 0.145, blue: 0.110, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.690, green: 0.250, blue: 0.200, alpha: 1.0)
        }
    }

    static func link(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.190, green: 0.330, blue: 0.410, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.200, green: 0.320, blue: 0.390, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.784, green: 0.725, blue: 0.541, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.722, green: 0.769, blue: 0.816, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.120, green: 0.355, blue: 0.540, alpha: 1.0)
        case .glassDark:
            return NSColor(calibratedRed: 0.490, green: 0.745, blue: 0.960, alpha: 1.0)
        case .glassMist:
            return NSColor(calibratedRed: 0.200, green: 0.320, blue: 0.390, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.722, green: 0.769, blue: 0.816, alpha: 1.0)
        }
    }

    static func chrome(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.155, green: 0.145, blue: 0.130, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.140, green: 0.138, blue: 0.132, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.043, green: 0.043, blue: 0.043, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.063, green: 0.071, blue: 0.090, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.090, green: 0.115, blue: 0.150, alpha: 1.0)
        case .glassDark:
            return NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.055, alpha: 0.92)
        case .glassMist:
            return NSColor(calibratedRed: 0.140, green: 0.138, blue: 0.132, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.063, green: 0.071, blue: 0.090, alpha: 1.0)
        }
    }

    static func placeholderInk(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.405, green: 0.345, blue: 0.290, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.430, green: 0.410, blue: 0.380, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.686, green: 0.643, blue: 0.549, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.659, green: 0.686, blue: 0.722, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.390, green: 0.440, blue: 0.510, alpha: 0.88)
        case .glassDark:
            return NSColor(calibratedRed: 0.600, green: 0.665, blue: 0.750, alpha: 0.90)
        case .glassMist:
            return NSColor(calibratedRed: 0.430, green: 0.410, blue: 0.380, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.659, green: 0.686, blue: 0.722, alpha: 1.0)
        }
    }

    static func cinnabarSoft(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.570, green: 0.150, blue: 0.105, alpha: 0.10)
        case .xuan:
            return NSColor(calibratedRed: 0.540, green: 0.145, blue: 0.110, alpha: 0.09)
        case .inkstone:
            return NSColor(calibratedRed: 0.361, green: 0.149, blue: 0.129, alpha: 0.62)
        case .stele:
            return NSColor(calibratedRed: 0.353, green: 0.165, blue: 0.157, alpha: 0.58)
        case .glassLight:
            return NSColor(calibratedRed: 0.610, green: 0.155, blue: 0.115, alpha: 0.11)
        case .glassDark:
            return NSColor(calibratedRed: 0.620, green: 0.190, blue: 0.165, alpha: 0.42)
        case .glassMist:
            return NSColor(calibratedRed: 0.540, green: 0.145, blue: 0.110, alpha: 0.09)
        case .glassSlate:
            return NSColor(calibratedRed: 0.353, green: 0.165, blue: 0.157, alpha: 0.58)
        }
    }

    static func onCinnabar(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.973, green: 0.918, blue: 0.831, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.969, green: 0.949, blue: 0.918, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.953, green: 0.871, blue: 0.761, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.910, green: 0.925, blue: 0.941, alpha: 1.0)
        case .glassLight, .glassDark, .glassMist, .glassSlate:
            return NSColor(calibratedRed: 0.975, green: 0.985, blue: 1.000, alpha: 1.0)
        }
    }

    static func moss(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.230, green: 0.385, blue: 0.300, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.250, green: 0.380, blue: 0.310, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.722, green: 0.541, blue: 0.259, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.561, green: 0.627, blue: 0.416, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.190, green: 0.420, blue: 0.335, alpha: 1.0)
        case .glassDark:
            return NSColor(calibratedRed: 0.520, green: 0.750, blue: 0.565, alpha: 1.0)
        case .glassMist:
            return NSColor(calibratedRed: 0.250, green: 0.380, blue: 0.310, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.561, green: 0.627, blue: 0.416, alpha: 1.0)
        }
    }

    static func codePaper(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.180, green: 0.145, blue: 0.115, alpha: 0.055)
        case .xuan:
            return NSColor(calibratedRed: 0.160, green: 0.150, blue: 0.130, alpha: 0.050)
        case .inkstone:
            return NSColor(calibratedRed: 0.090, green: 0.090, blue: 0.090, alpha: 0.92)
        case .stele:
            return NSColor(calibratedRed: 0.102, green: 0.118, blue: 0.141, alpha: 0.94)
        case .glassLight:
            return NSColor(calibratedWhite: 0.150, alpha: 0.055)
        case .glassDark:
            return NSColor(calibratedWhite: 0.020, alpha: 0.42)
        case .glassMist:
            return NSColor(calibratedWhite: 0.150, alpha: 0.050)
        case .glassSlate:
            return NSColor(calibratedRed: 0.102, green: 0.118, blue: 0.141, alpha: 0.72)
        }
    }

    static func glassTint(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.982, green: 0.948, blue: 0.875, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.988, green: 0.984, blue: 0.974, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.102, green: 0.094, blue: 0.078, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.110, green: 0.125, blue: 0.149, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.820, green: 0.910, blue: 1.000, alpha: 1.0)
        case .glassDark:
            return NSColor(calibratedRed: 0.150, green: 0.210, blue: 0.300, alpha: 1.0)
        case .glassMist:
            return NSColor(calibratedRed: 0.957, green: 0.976, blue: 1.000, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.106, green: 0.129, blue: 0.169, alpha: 1.0)
        }
    }

    static func glassHighlight(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.992, green: 0.970, blue: 0.918, alpha: 1.0)
        case .xuan:
            return NSColor(calibratedRed: 0.995, green: 0.992, blue: 0.986, alpha: 1.0)
        case .inkstone:
            return NSColor(calibratedRed: 0.227, green: 0.200, blue: 0.157, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.243, green: 0.275, blue: 0.322, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedWhite: 1.000, alpha: 1.0)
        case .glassDark:
            return NSColor(calibratedRed: 0.720, green: 0.840, blue: 0.970, alpha: 1.0)
        case .glassMist:
            return NSColor(calibratedWhite: 1.000, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.725, green: 0.776, blue: 0.847, alpha: 1.0)
        }
    }

    /// PDF/imported-document color mask fill under `.multiply` page draw.
    /// Light themes use the paper surface; dark themes use a mid-tone wash so ink stays readable.
    static func documentMaskFill(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return paper(for: .paper)
        case .xuan:
            return paper(for: .xuan)
        case .inkstone:
            // Warm parchment mid-tone so multiply darkens white page into inkstone paper.
            return NSColor(calibratedRed: 0.66, green: 0.61, blue: 0.50, alpha: 1.0)
        case .stele:
            // Cool stone mid-tone for 石碑.
            return NSColor(calibratedRed: 0.58, green: 0.60, blue: 0.64, alpha: 1.0)
        case .glassLight:
            return NSColor(calibratedRed: 0.82, green: 0.86, blue: 0.91, alpha: 1.0)
        case .glassDark:
            return NSColor(calibratedRed: 0.56, green: 0.60, blue: 0.67, alpha: 1.0)
        case .glassMist:
            return NSColor(calibratedRed: 0.84, green: 0.88, blue: 0.93, alpha: 1.0)
        case .glassSlate:
            return NSColor(calibratedRed: 0.58, green: 0.60, blue: 0.64, alpha: 1.0)
        }
    }

    /// Split-view divider fill — glass themes keep their transparency.
    static func dividerFill(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        mode.isGlass ? paper(for: mode) : paper(for: mode).withAlphaComponent(0.96)
    }

    /// Split-view hairline on the divider.
    static func dividerLine(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.500, green: 0.380, blue: 0.260, alpha: 0.13)
        case .xuan:
            return NSColor(calibratedRed: 0.420, green: 0.400, blue: 0.360, alpha: 0.14)
        case .inkstone:
            return NSColor(calibratedRed: 0.230, green: 0.200, blue: 0.155, alpha: 0.24)
        case .stele:
            return NSColor(calibratedRed: 0.220, green: 0.250, blue: 0.300, alpha: 0.28)
        case .glassLight:
            return NSColor(calibratedRed: 0.250, green: 0.340, blue: 0.440, alpha: 0.18)
        case .glassDark:
            return NSColor(calibratedRed: 0.700, green: 0.820, blue: 0.950, alpha: 0.19)
        case .glassMist:
            return NSColor(calibratedRed: 0.275, green: 0.350, blue: 0.455, alpha: 0.14)
        case .glassSlate:
            return NSColor(calibratedRed: 0.725, green: 0.776, blue: 0.847, alpha: 0.14)
        }
    }

    static func selectedText(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper, .xuan, .glassLight, .glassMist:
            return ink(for: mode)
        case .inkstone:
            return NSColor(calibratedRed: 0.961, green: 0.906, blue: 0.784, alpha: 1.0)
        case .stele:
            return NSColor(calibratedRed: 0.930, green: 0.940, blue: 0.955, alpha: 1.0)
        case .glassDark, .glassSlate:
            return NSColor(calibratedRed: 0.955, green: 0.975, blue: 1.000, alpha: 1.0)
        }
    }

    static func selectionFill(for mode: WeiBeiAppearanceMode = current) -> NSColor {
        switch mode {
        case .paper:
            return NSColor(calibratedRed: 0.570, green: 0.150, blue: 0.105, alpha: 0.20)
        case .xuan:
            return NSColor(calibratedRed: 0.540, green: 0.145, blue: 0.110, alpha: 0.18)
        case .inkstone:
            return NSColor(calibratedRed: 0.651, green: 0.212, blue: 0.169, alpha: 0.35)
        case .stele:
            return NSColor(calibratedRed: 0.690, green: 0.250, blue: 0.200, alpha: 0.32)
        case .glassLight:
            return NSColor(calibratedRed: 0.610, green: 0.155, blue: 0.115, alpha: 0.20)
        case .glassDark:
            return NSColor(calibratedRed: 0.920, green: 0.335, blue: 0.275, alpha: 0.34)
        case .glassMist:
            return NSColor(calibratedRed: 0.540, green: 0.145, blue: 0.110, alpha: 0.18)
        case .glassSlate:
            return NSColor(calibratedRed: 0.690, green: 0.250, blue: 0.200, alpha: 0.32)
        }
    }

    /// CSS hex tokens for WebKit injection (reader / editor helpers).
    static func cssHex(for mode: WeiBeiAppearanceMode = current) -> (
        paper: String, paperRaised: String, ink: String, muted: String,
        cinnabar: String, link: String, selection: String
    ) {
        switch mode {
        case .paper:
            return ("#f4ead5", "#f9f1de", "#1d1814", "rgba(58,46,38,.72)", "#91261c", "#31566b", "rgba(145,38,28,.18)")
        case .xuan:
            return ("#f8f5f0", "#fdfcf9", "#25231f", "rgba(90,86,78,.74)", "#8a2f24", "#335266", "rgba(138,47,36,.16)")
        case .inkstone:
            return ("#0f0f0f", "#151515", "#d7cbb0", "rgba(155,145,120,.88)", "#a6362b", "#c8b98a", "rgba(166,54,43,.35)")
        case .stele:
            return ("#16181c", "#1e2228", "#d2d6dc", "rgba(154,161,171,.88)", "#b04034", "#b8c4d0", "rgba(176,64,52,.32)")
        case .glassLight:
            return ("rgba(230,240,250,.42)", "rgba(248,251,255,.62)", "#171d26", "rgba(62,74,90,.78)", "#9c281d", "#1f5a89", "rgba(156,40,29,.20)")
        case .glassDark:
            return ("rgba(12,16,24,.52)", "rgba(27,35,48,.56)", "#e8eef9", "rgba(174,186,204,.88)", "#eb5746", "#7dbeF5", "rgba(235,87,70,.34)")
        case .glassMist:
            return ("rgba(244,249,255,.72)", "rgba(244,249,255,.72)", "#25231f", "rgba(90,86,78,.74)", "#8a2f24", "#335266", "rgba(138,47,36,.16)")
        case .glassSlate:
            return ("rgba(27,33,43,.66)", "rgba(27,33,43,.66)", "#d2d6dc", "rgba(154,161,171,.88)", "#b04034", "#b8c4d0", "rgba(176,64,52,.32)")
        }
    }
}

enum WeiBeiMetric {
    static let iconButton: CGFloat = 26
    static let inputHeight: CGFloat = 30
    static let controlRadius: CGFloat = 7
    static let topBarHeight: CGFloat = 36
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
    /// Theme swaps: one short global ease — longer / nested animations made panes desync.
    static let appearance = Animation.easeOut(duration: 0.12)
    /// Course drawer: snappy ease-out slide (visual only; never wrap focus changes).
    static let sideDrawer = Animation.easeOut(duration: 0.12)
}

private struct WeiBeiReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// WeiBei's resolved reduce-motion result. Native surfaces read this instead of
    /// `accessibilityReduceMotion` so the "完整动态效果" preference can override the
    /// macOS switch and "减少动态效果" can force it off app-wide.
    var weibeiReduceMotion: Bool {
        get { self[WeiBeiReduceMotionKey.self] }
        set { self[WeiBeiReduceMotionKey.self] = newValue }
    }
}

/// Single motion scope for the whole app: resolves the three-way preference against
/// the macOS switch, publishes the boolean into WeiBei's own environment, and — when
/// motion is reduced — strips animation from every transaction inside. Individual
/// `withAnimation` call sites stay untouched.
struct WeiBeiMotionScope: ViewModifier {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    func body(content: Content) -> some View {
        let reduceMotion = store.motionPreference.resolvesReduceMotion(
            systemReduceMotion: systemReduceMotion
        )
        content
            .environment(\.weibeiReduceMotion, reduceMotion)
            .transaction { transaction in
                guard reduceMotion else { return }
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

extension View {
    /// Applies the app motion scope. Long-lived manually hosted `NSHostingView` roots
    /// (pane hosts, course drawer, floating previews) must call this — they do not
    /// inherit the window scene's SwiftUI environment.
    func weiBeiMotionScoped() -> some View {
        modifier(WeiBeiMotionScope())
    }
}

/// Top-bar / settings theme control: compact surface swatches instead of a menu.
struct AppearanceThemePaletteButton: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: WeiBeiNativePalette.paper(for: store.appearanceMode)))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(WeiBeiTheme.hairline.opacity(0.85), lineWidth: 1)
                }
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 24))
        .accessibilityLabel(Text(store.appearanceMode.actionLabel(language: store.interfaceLanguage)))
        .help(store.appearanceMode.actionLabel(language: store.interfaceLanguage))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AppearanceThemePalettePopover(isPresented: $isPresented)
                .environmentObject(store)
        }
    }
}

private struct AppearanceThemePalettePopover: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Binding var isPresented: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(WeiBeiAppearanceMode.allCases) { mode in
                Button {
                    // Store owns a single appearance transaction — do not wrap again.
                    store.setAppearanceMode(mode)
                    isPresented = false
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: previewSurface(for: mode)))
                                .frame(width: 52, height: 36)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    mode == store.appearanceMode
                                        ? WeiBeiTheme.cinnabar.opacity(0.90)
                                        : WeiBeiTheme.hairline.opacity(0.70),
                                    lineWidth: mode == store.appearanceMode ? 1.5 : 1
                                )
                                .frame(width: 52, height: 36)
                            // Ink sample line so the swatch reads as paper + text, not a flat chip.
                            Capsule()
                                .fill(Color(nsColor: WeiBeiNativePalette.ink(for: mode)).opacity(0.55))
                                .frame(width: 22, height: 2)
                        }
                        Text(mode.label(language: store.interfaceLanguage))
                            .font(.system(size: 11, weight: mode == store.appearanceMode ? .semibold : .medium))
                            .foregroundStyle(
                                mode == store.appearanceMode ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk
                            )
                            .lineLimit(1)
                    }
                    .frame(width: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(mode.label(language: store.interfaceLanguage)))
                .accessibilityAddTraits(mode == store.appearanceMode ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(WeiBeiTheme.paperRaised)
    }
}

// MARK: - Theme layout preview (real WeiBei chrome, not a chat-shell mock)
//
// Matches the live default workspace: full-width UnifiedTopBar + document
// three-pane (阅读 | 对话 | 笔记). Library is a drawer, not a permanent column.

struct WeiBeiThemeLayoutPreview: View {
    let mode: WeiBeiAppearanceMode

    private var paper: Color { Color(nsColor: previewSurface(for: mode)) }
    private var raised: Color { Color(nsColor: WeiBeiNativePalette.paperRaised(for: mode)) }
    private var inset: Color { Color(nsColor: WeiBeiNativePalette.paperInset(for: mode)) }
    private var ink: Color { Color(nsColor: WeiBeiNativePalette.ink(for: mode)) }
    private var hairline: Color { Color(nsColor: WeiBeiNativePalette.hairline(for: mode)) }
    private var cinnabar: Color { Color(nsColor: WeiBeiNativePalette.cinnabar(for: mode)) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            hairlineDivider
            HStack(spacing: 0) {
                readerPane
                hairlineDividerVertical
                agentPane
                hairlineDividerVertical
                notesPane
            }
            .frame(maxHeight: .infinity)
        }
        .background(paper)
        .allowsHitTesting(false)
    }

    /// Slim UnifiedTopBar: left chrome · center pane-toggle cluster · right tools.
    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                iconDot(active: false)
                iconDot(active: false)
                iconDot(active: false)
            }
            .frame(width: 28, alignment: .leading)

            Spacer(minLength: 2)

            // Reader / Chat / Notes toggles — centered like the real top bar.
            HStack(spacing: 3) {
                iconDot(active: true)
                iconDot(active: true)
                iconDot(active: true)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(inset.opacity(0.85))
            )

            Spacer(minLength: 2)

            HStack(spacing: 3) {
                iconDot(active: false)
                iconDot(active: false)
            }
            .frame(width: 22, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(height: 11)
        .background(paper)
    }

    /// Wide reading column — primary surface in WeiBei.
    private var readerPane: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Title + cinnabar underline (reading hierarchy)
            Capsule()
                .fill(ink.opacity(0.42))
                .frame(width: 28, height: 3)
            Capsule()
                .fill(cinnabar.opacity(0.75))
                .frame(width: 12, height: 1.5)
                .padding(.bottom, 1)

            bodyLine(fraction: 0.95)
            bodyLine(fraction: 0.88)
            bodyLine(fraction: 0.92)
            // Rubbing / figure block (distinct from chat bubbles)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ink.opacity(mode.isDark ? 0.22 : 0.10))
                .frame(height: 16)
                .padding(.vertical, 1)
            bodyLine(fraction: 0.78)
            bodyLine(fraction: 0.65)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(paper)
    }

    /// Chat column — bubbles + quiet composer, not the dominant pane.
    private var agentPane: some View {
        VStack(alignment: .leading, spacing: 3) {
            Capsule()
                .fill(ink.opacity(0.22))
                .frame(width: 14, height: 2)
            chatBubble(alignment: .trailing, fill: cinnabar.opacity(mode.isDark ? 0.35 : 0.22), width: 0.72)
            chatBubble(alignment: .leading, fill: inset.opacity(0.95), width: 0.88)
            chatBubble(alignment: .leading, fill: inset.opacity(0.80), width: 0.64)
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(hairline.opacity(0.55), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(raised.opacity(0.55))
                )
                .frame(height: 8)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .frame(width: 36)
        .background(raised.opacity(0.55))
    }

    /// Notes column — markdown lines, quieter than chat.
    private var notesPane: some View {
        VStack(alignment: .leading, spacing: 3) {
            Capsule()
                .fill(ink.opacity(0.28))
                .frame(width: 16, height: 2)
            bodyLine(fraction: 0.90)
            bodyLine(fraction: 0.75)
            bodyLine(fraction: 0.82)
            bodyLine(fraction: 0.55)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .frame(width: 32)
        .background(raised.opacity(0.40))
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(hairline.opacity(0.55))
            .frame(height: 1)
    }

    private var hairlineDividerVertical: some View {
        Rectangle()
            .fill(hairline.opacity(0.50))
            .frame(width: 1)
    }

    private func iconDot(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(active ? cinnabar.opacity(0.85) : ink.opacity(0.22))
            .frame(width: 5, height: 5)
    }

    private func bodyLine(fraction: CGFloat) -> some View {
        Capsule()
            .fill(ink.opacity(0.16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 2)
            .padding(.trailing, max(0, (1 - fraction) * 48))
    }

    private func chatBubble(alignment: HorizontalAlignment, fill: Color, width fraction: CGFloat) -> some View {
        HStack {
            if alignment == .trailing { Spacer(minLength: 0) }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fill)
                .frame(height: 7)
                .frame(maxWidth: .infinity)
                .padding(alignment == .trailing ? .leading : .trailing, max(0, (1 - fraction) * 28))
            if alignment == .leading { Spacer(minLength: 0) }
        }
    }
}

private func previewSurface(for mode: WeiBeiAppearanceMode) -> NSColor {
    mode.isGlass
        ? WeiBeiNativePalette.drawerSurface(for: mode)
        : WeiBeiNativePalette.paper(for: mode)
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
    /// Pass the live mode so SwiftUI re-renders on paper↔xuan / inkstone↔stele.
    var appearanceMode: WeiBeiAppearanceMode = WeiBeiThemeRuntime.mode

    private var isDark: Bool { appearanceMode.isDark }

    var body: some View {
        ZStack {
            if appearanceMode.isGlass {
                Color.clear
            } else if isDark {
                // Match the page/window paper exactly — no paperRaised wash, no warm
                // glassHighlight (those made 墨石/石碑 top bars look gray-brown).
                Rectangle()
                    .fill(WeiBeiTheme.paper)
            } else {
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(materialOpacity)
                Rectangle()
                    .fill(WeiBeiTheme.paperRaised.opacity(paperWashOpacity))
                LinearGradient(
                    colors: [
                        WeiBeiTheme.glassHighlight.opacity(0.20),
                        WeiBeiTheme.glassTint.opacity(0.24),
                        WeiBeiTheme.paperRaised.opacity(0.13),
                        WeiBeiTheme.paper.opacity(0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Rectangle()
                    .fill(WeiBeiTheme.paperInset.opacity(0.018))
            }
        }
    }

    private var paperWashOpacity: Double {
        min(0.48, max(0.20, paperOpacity * 0.42))
    }
}

struct WeiBeiHeaderHandoffFade: View {
    var height: CGFloat = 18
    var opacity: Double = 1
    var appearanceMode: WeiBeiAppearanceMode = WeiBeiThemeRuntime.mode

    var body: some View {
        // Dark: pure paper fade into content (no warm glassTint band under the bar).
        // Light: keep the soft glass handoff.
        let colors: [Color] = appearanceMode.isGlass
            ? [.clear, .clear]
            : appearanceMode.isDark ? [
                WeiBeiTheme.paper.opacity(0.55 * opacity),
                WeiBeiTheme.paper.opacity(0.22 * opacity),
                .clear
            ]
            : [
                WeiBeiTheme.glassTint.opacity(0.16 * opacity),
                WeiBeiTheme.paperRaised.opacity(0.13 * opacity),
                WeiBeiTheme.paper.opacity(0.08 * opacity),
                .clear
            ]
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
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
    var cornerRadius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        WeiBeiIconButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            active: active,
            size: size,
            prominence: prominence,
            cornerRadius: cornerRadius
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
    let cornerRadius: CGFloat
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: size, height: size)
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .background(background(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
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
        let isGlass = WeiBeiThemeRuntime.mode.isGlass
        return self
            .foregroundColor(WeiBeiTheme.ink)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(WeiBeiTheme.paperRaised.opacity(isGlass ? 0.58 : 0.985))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(isGlass ? 0.24 : 0.015)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(isGlass ? Color.clear : WeiBeiTheme.glassHighlight.opacity(0.24))
                    .frame(height: 1)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        WeiBeiTheme.hairline.opacity(isGlass ? 0.22 : 1),
                        lineWidth: 1
                    )
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
