import AppKit
import SwiftUI

/// Candidate generated mapping for `Sources/WeiBei/Support/Theme.swift`.
/// Merge into the existing theme instead of keeping a second runtime token type.
enum WeiBeiDesignToken {
    enum Typography {
        static func brandLatin(size: CGFloat) -> Font {
            .custom("WeiBeiStele-Regular", size: size)
        }

        static func brandMono(size: CGFloat) -> Font {
            .custom("WeiBeiSteleMono-Regular", size: size)
        }
    }

    enum ColorToken {
        static let paper = adaptive(0xF4EAD5, 0x0F0F0F)
        static let paperRaised = adaptive(0xF9F1DE, 0x151515)
        static let paperInset = adaptive(0xE8DBBF, 0x1C1C1C)
        static let ink = adaptive(0x1D1814, 0xD7CBB0)
        static let secondaryInk = adaptive(0x55493E, 0x9B9178)
        static let tertiaryInk = adaptive(0x7D6E5D, 0x6F6655)
        static let cinnabar = adaptive(0x91261B, 0xA6362B)
        static let link = adaptive(0x305469, 0xC8B98A)
        static let moss = adaptive(0x3B624C, 0xB88A42)

        static let brandPaper = Color(hex: 0xF2E2CA)
        static let brandInk = Color(hex: 0x231F1C)
        static let brandCinnabar = Color(hex: 0xAA2A23)

        private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }

    enum Metric {
        static let sidebarMin: CGFloat = 220
        static let sidebarMax: CGFloat = 430
        static let contentReadableMin: CGFloat = 560
        static let contentReadableMax: CGFloat = 780
        static let splitterHitWidth: CGFloat = 10
        static let splitterLineWidth: CGFloat = 1
        static let railDormantWidth: CGFloat = 28
        static let railReadableThreshold: CGFloat = 240
        static let railDefaultExpanded: CGFloat = 420
    }

    enum Motion {
        static let press = Animation.spring(response: 0.18, dampingFraction: 0.82)
        static let micro = Animation.easeOut(duration: 0.14)
        static let hover = Animation.spring(response: 0.20, dampingFraction: 0.86)
        static let reveal = Animation.spring(response: 0.24, dampingFraction: 0.88)
        static let panel = Animation.spring(response: 0.30, dampingFraction: 0.88)
        static let layout = Animation.spring(response: 0.38, dampingFraction: 0.90)
        static let appearance = Animation.easeInOut(duration: 0.42)
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}
