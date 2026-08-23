import AppKit
import Foundation

// MARK: - Customizable app shortcuts
//
// Defaults match the historical hard-coded chords in WorkspaceStore.handleAppShortcut.
// Settings can rebind any of these; overrides persist in UserDefaults.

public enum AppShortcutID: String, CaseIterable, Identifiable, Codable, Sendable {
    case commandPalette
    case toggleAppearance
    case navigateBack
    case navigateForward
    case courseIndex
    case searchInMaterial
    case focusLibrary
    case focusReader
    case focusNotes
    case focusChat
    case immersiveReading
    case immersiveChat
    case immersiveWriting
    case selectionPrompt
    case hideChatOverlay

    public var id: String { rawValue }

    public func title(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .commandPalette: return language.text("命令面板", "Command Palette")
        case .toggleAppearance: return language.text("切换外观主题", "Switch Appearance Theme")
        case .navigateBack: return language.text("后退", "Back")
        case .navigateForward: return language.text("前进", "Forward")
        case .courseIndex: return language.text("课程目录", "Course Index")
        case .searchInMaterial: return language.text("资料内搜索", "Search in Material")
        case .focusLibrary: return language.text("聚焦课程目录", "Focus Course Index")
        case .focusReader: return language.text("聚焦阅读", "Focus Reader")
        case .focusNotes: return language.text("聚焦笔记", "Focus Notes")
        case .focusChat: return language.text("聚焦对话", "Focus Chat")
        case .immersiveReading: return language.text("沉浸阅读", "Immersive Reading")
        case .immersiveChat: return language.text("沉浸对话", "Immersive Chat")
        case .immersiveWriting: return language.text("沉浸写作", "Immersive Writing")
        case .selectionPrompt: return language.text("选区轻提示", "Selection Prompt")
        case .hideChatOverlay: return language.text("隐藏对话浮层", "Hide Chat Overlay")
        }
    }

    public var group: AppShortcutGroup {
        switch self {
        case .commandPalette, .toggleAppearance, .navigateBack, .navigateForward:
            return .global
        case .courseIndex, .searchInMaterial, .focusLibrary, .focusReader, .focusNotes, .focusChat:
            return .navigation
        case .immersiveReading, .immersiveChat, .immersiveWriting, .selectionPrompt, .hideChatOverlay:
            return .immersive
        }
    }

    public var defaultChord: AppShortcutChord {
        switch self {
        case .commandPalette: return AppShortcutChord(key: "k", modifiers: .command)
        case .toggleAppearance: return AppShortcutChord(key: "t", modifiers: [.command, .option])
        case .navigateBack: return AppShortcutChord(key: "[", modifiers: .command)
        case .navigateForward: return AppShortcutChord(key: "]", modifiers: .command)
        case .courseIndex: return AppShortcutChord(key: "b", modifiers: [.command, .option])
        case .searchInMaterial: return AppShortcutChord(key: "f", modifiers: [.command, .option])
        case .focusLibrary: return AppShortcutChord(key: "1", modifiers: .command)
        case .focusReader: return AppShortcutChord(key: "2", modifiers: .command)
        case .focusNotes: return AppShortcutChord(key: "3", modifiers: .command)
        case .focusChat: return AppShortcutChord(key: "4", modifiers: .command)
        case .immersiveReading: return AppShortcutChord(key: "r", modifiers: [.command, .option])
        case .immersiveChat: return AppShortcutChord(key: "a", modifiers: [.command, .option])
        case .immersiveWriting: return AppShortcutChord(key: "n", modifiers: [.command, .option])
        case .selectionPrompt: return AppShortcutChord(key: "3", modifiers: [.control, .option])
        case .hideChatOverlay: return AppShortcutChord(key: "0", modifiers: [.control, .option])
        }
    }
}

public enum AppShortcutGroup: String, CaseIterable, Identifiable, Sendable {
    case global
    case navigation
    case immersive

    public var id: String { rawValue }

    public func title(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .global: return language.text("全局", "Global")
        case .navigation: return language.text("导航", "Navigation")
        case .immersive: return language.text("沉浸", "Immersive")
        }
    }

    public var shortcuts: [AppShortcutID] {
        AppShortcutID.allCases.filter { $0.group == self }
    }
}

public struct AppShortcutChord: Codable, Equatable, Hashable, Sendable {
    public var key: String
    /// Normalized raw value of `NSEvent.ModifierFlags` intersection with command/option/control/shift.
    public var modifiersRaw: UInt

    public init(key: String, modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiersRaw = modifiers.intersection(Self.mask).rawValue
    }

    public init(key: String, modifiersRaw: UInt) {
        self.key = key
        self.modifiersRaw = modifiersRaw
    }

    public static let mask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    public var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiersRaw).intersection(Self.mask)
    }

    public var display: String {
        var parts: [String] = []
        let flags = modifiers
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(Self.displayKey(key))
        return parts.joined()
    }

    public static func from(event: NSEvent) -> AppShortcutChord? {
        guard let key = key(from: event) else { return nil }
        let flags = event.modifierFlags.intersection(mask)
        // Require at least one modifier for letter/digit keys to avoid swallowing typing.
        let needsModifier = key.count == 1 && key.rangeOfCharacter(from: .alphanumerics) != nil
        if needsModifier && flags.isEmpty { return nil }
        return AppShortcutChord(key: key, modifiers: flags)
    }

    public static func key(from event: NSEvent) -> String? {
        switch event.keyCode {
        case 0: return "a"
        case 1: return "s"
        case 2: return "d"
        case 3: return "f"
        case 4: return "h"
        case 5: return "g"
        case 6: return "z"
        case 7: return "x"
        case 8: return "c"
        case 9: return "v"
        case 11: return "b"
        case 12: return "q"
        case 13: return "w"
        case 14: return "e"
        case 15: return "r"
        case 16: return "y"
        case 17: return "t"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 25: return "9"
        case 26: return "7"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 33: return "["
        case 36: return "return"
        case 123: return "left"
        case 124: return "right"
        case 125: return "down"
        case 126: return "up"
        default:
            if let chars = event.charactersIgnoringModifiers?.lowercased(),
               let first = chars.first,
               first.isLetter || first.isNumber {
                return String(first)
            }
            return nil
        }
    }

    private static func displayKey(_ key: String) -> String {
        switch key {
        case "return": return "↩"
        case "up": return "↑"
        case "down": return "↓"
        case "left": return "←"
        case "right": return "→"
        default: return key.uppercased()
        }
    }
}

public enum AppShortcutCatalog {
    public static let defaultsKey = "weibei.customAppShortcuts.v1"

    public static func loadOverrides() -> [AppShortcutID: AppShortcutChord] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: AppShortcutChord].self, from: data)
        else { return [:] }
        var result: [AppShortcutID: AppShortcutChord] = [:]
        for (raw, chord) in decoded {
            guard let id = AppShortcutID(rawValue: raw) else { continue }
            result[id] = chord
        }
        return result
    }

    public static func saveOverrides(_ map: [AppShortcutID: AppShortcutChord]) {
        let payload = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    public static func chord(for id: AppShortcutID, overrides: [AppShortcutID: AppShortcutChord]) -> AppShortcutChord {
        overrides[id] ?? id.defaultChord
    }

    /// Resolve which action (if any) matches a pressed chord.
    public static func action(
        matching chord: AppShortcutChord,
        overrides: [AppShortcutID: AppShortcutChord]
    ) -> AppShortcutID? {
        for id in AppShortcutID.allCases {
            if self.chord(for: id, overrides: overrides) == chord {
                return id
            }
        }
        return nil
    }

    /// Another action already using this chord (excluding `excluding`).
    public static func conflict(
        for chord: AppShortcutChord,
        excluding: AppShortcutID,
        overrides: [AppShortcutID: AppShortcutChord]
    ) -> AppShortcutID? {
        for id in AppShortcutID.allCases where id != excluding {
            if self.chord(for: id, overrides: overrides) == chord {
                return id
            }
        }
        return nil
    }
}
