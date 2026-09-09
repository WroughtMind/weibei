import SwiftUI
import WeiBeiCore

extension Notification.Name {
    /// 菜单 ⌘, → 主窗口里的 openWindow 桥(Commands 拿不到环境 action)。
    static let weibeiOpenSettings = Notification.Name("WeiBeiOpenSettings")
}

extension View {
    @ViewBuilder
    func weiBeiKeyboardShortcut(_ chord: AppShortcutChord?) -> some View {
        if let chord {
            keyboardShortcut(chord.swiftUIKeyEquivalent, modifiers: chord.swiftUIModifiers)
        } else {
            self
        }
    }
}

private extension AppShortcutChord {
    var swiftUIKeyEquivalent: KeyEquivalent {
        switch key {
        case "return": .return
        case "up": .upArrow
        case "down": .downArrow
        case "left": .leftArrow
        case "right": .rightArrow
        default: KeyEquivalent(Character(key))
        }
    }

    var swiftUIModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }
}

// Internal (not private) so SettingsView.swift — now in its own file — can apply
// this modifier. Was `private` when SettingsView lived in this same file (L1).
struct WeiBeiAppearanceTransition: ViewModifier {
    var mode: WeiBeiAppearanceMode
    @State private var washOpacity = 0.0
    @State private var washColor = Color.clear

    func body(content: Content) -> some View {
        // No nested `.animation(value: mode)` here — ContentView / Settings already
        // animate once at the root. A second animation made chrome lag the paper.
        content
            .overlay {
                washColor
                    .opacity(washOpacity)
                    .allowsHitTesting(false)
            }
            .onChange(of: mode) { oldMode, _ in
                // Brief wash only when light↔dark family flips; same-family (纸面↔宣纸)
                // must feel instant without a laggy overlay.
                let crossFamily = oldMode.isDark != mode.isDark
                guard crossFamily else {
                    washOpacity = 0
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    washColor = Color(weiBeiNativeColor: oldMode.windowBackground)
                    washOpacity = 0.16
                }
                withAnimation(WeiBeiMotion.appearance) {
                    washOpacity = 0
                }
            }
    }
}



extension View {
    @ViewBuilder
    func weiBeiOnExitCommand(perform action: @escaping () -> Void) -> some View {
#if targetEnvironment(macCatalyst)
        onKeyPress(.escape) { action(); return .handled }
#else
        onExitCommand(perform: action)
#endif
    }
}
