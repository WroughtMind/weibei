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

/// 四组风格：每组自带浅/深一对主题。选风格 + 外观偏好（跟随系统/浅色/深色）
/// 共同决定生效主题，不再让用户在八张主题卡里直接挑具体深浅。
enum WeiBeiAppearanceStyle: String, CaseIterable, Identifiable {
    case paperInk
    case xuanStele
    case clearGlass
    case mistGlass

    var id: String { rawValue }

    var lightMode: WeiBeiAppearanceMode {
        switch self {
        case .paperInk: return .paper
        case .xuanStele: return .xuan
        case .clearGlass: return .glassLight
        case .mistGlass: return .glassMist
        }
    }

    var darkMode: WeiBeiAppearanceMode {
        switch self {
        case .paperInk: return .inkstone
        case .xuanStele: return .stele
        case .clearGlass: return .glassDark
        case .mistGlass: return .glassSlate
        }
    }

    static func of(_ mode: WeiBeiAppearanceMode) -> WeiBeiAppearanceStyle {
        switch mode {
        case .paper, .inkstone: return .paperInk
        case .xuan, .stele: return .xuanStele
        case .glassLight, .glassDark: return .clearGlass
        case .glassMist, .glassSlate: return .mistGlass
        }
    }

    func label(ui: (String, String) -> String) -> String {
        switch self {
        case .paperInk: return ui("纸面 · 墨石", "Paper · Inkstone")
        case .xuanStele: return ui("宣纸 · 石碑", "Xuan · Stele")
        case .clearGlass: return ui("晴璃 · 夜璃", "Clear · Dark Glass")
        case .mistGlass: return ui("雾璃 · 玄璃", "Mist · Slate Glass")
        }
    }
}

extension WorkspaceStore {
    private static let appearancePreferenceKey = "weibei.appearancePreference"
    private static let appearanceStyleKey = "weibei.appearanceStyle"
    private static let glassIntensityKey = "weibei.glassIntensity"

    var appearancePreference: WeiBeiAppearancePreference {
        get {
            if let stored = UserDefaults.standard.string(forKey: Self.appearancePreferenceKey),
               let preference = WeiBeiAppearancePreference(rawValue: stored) {
                return preference
            }
            // 旧用户迁移：从未设置过偏好时，按当前主题的深浅落位，行为零变化。
            return appearanceMode.isDark ? .dark : .light
        }
        set {
            guard newValue != appearancePreference else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.appearancePreferenceKey)
            applyResolvedAppearance()
        }
    }

    var appearanceStyle: WeiBeiAppearanceStyle {
        get {
            if let stored = UserDefaults.standard.string(forKey: Self.appearanceStyleKey),
               let style = WeiBeiAppearanceStyle(rawValue: stored) {
                return style
            }
            return WeiBeiAppearanceStyle.of(appearanceMode)
        }
        set {
            guard newValue != appearanceStyle else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.appearanceStyleKey)
            applyResolvedAppearance()
        }
    }

    /// 按风格 + 外观偏好解析生效主题；与当前不同才走统一的切换通道。
    func applyResolvedAppearance() {
        applyResolvedAppearance(systemIsDark: Self.systemPrefersDarkAppearance)
    }

    func applyResolvedAppearance(systemIsDark: Bool) {
        let target: WeiBeiAppearanceMode
        switch appearancePreference {
        case .system:
            target = systemIsDark ? appearanceStyle.darkMode : appearanceStyle.lightMode
        case .light:
            target = appearanceStyle.lightMode
        case .dark:
            target = appearanceStyle.darkMode
        }
        if appearanceMode != target {
            setAppearanceMode(target)
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
    /// 选中风格卡不触发即时翻转——显式选择优先，下次系统变化才重新配对。
    func refreshAppearanceForSystemChange() {
        guard appearancePreference == .system else { return }
        applyResolvedAppearance(systemIsDark: Self.systemPrefersDarkAppearance)
    }
}
