import AppKit
import Foundation

/// 外观跟随偏好：跟随系统 / 浅色 / 深色。存 UserDefaults，不进冻结主文件。
/// 默认浅色（静态）——所有既有用户行为不变，跟随系统是显式选择。
enum WeiBeiAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    func label(ui: (String, String) -> String) -> String {
        switch self {
        case .system: return ui("跟随系统", "Match System")
        case .light: return ui("浅色", "Light")
        case .dark: return ui("深色", "Dark")
        }
    }
}

extension WorkspaceStore {
    private static let appearancePreferenceKey = "weibei.appearancePreference"
    private static let glassIntensityKey = "weibei.glassIntensity"

    var appearancePreference: WeiBeiAppearancePreference {
        get {
            UserDefaults.standard.string(forKey: Self.appearancePreferenceKey)
                .flatMap(WeiBeiAppearancePreference.init(rawValue:)) ?? .light
        }
        set {
            guard newValue != appearancePreference else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.appearancePreferenceKey)
            if newValue == .system {
                refreshAppearanceForSystemChange()
            }
        }
    }

    /// 玻璃主题浓度 0–1；写运行时（通知所有窗后材质即时重放）并持久化。
    var glassIntensity: Double {
        get { WeiBeiThemeRuntime.glassIntensity }
        set {
            WeiBeiThemeRuntime.glassIntensity = min(1, max(0, newValue))
            UserDefaults.standard.set(WeiBeiThemeRuntime.glassIntensity, forKey: Self.glassIntensityKey)
        }
    }

    /// 启动时恢复持久化的玻璃浓度。
    static func loadPersistedGlassIntensity() {
        if let stored = UserDefaults.standard.object(forKey: glassIntensityKey) as? Double {
            WeiBeiThemeRuntime.glassIntensity = min(1, max(0, stored))
        }
    }

    static var systemPrefersDarkAppearance: Bool {
        NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// 系统深浅切换（或切到“跟随系统”）时换到同对伙伴；静态浅色/深色不动。
    /// 选中主题卡不触发即时翻转——显式选择优先，下次系统变化才重新配对。
    func refreshAppearanceForSystemChange() {
        refreshAppearanceForSystemChange(systemIsDark: Self.systemPrefersDarkAppearance)
    }

    func refreshAppearanceForSystemChange(systemIsDark: Bool) {
        guard appearancePreference == .system,
              appearanceMode.isDark != systemIsDark else { return }
        setAppearanceMode(appearanceMode.lightDarkPartner)
    }
}
