import CoreGraphics
import Foundation

public enum AgentSurface: String, Codable, CaseIterable, Identifiable {
    case selectionFloat
    case hidden

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // Legacy surfaces (bottomDrawer / cornerPanel / quietInsight) fall back to hidden.
        self = AgentSurface(rawValue: raw) ?? .hidden
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .selectionFloat:
            return language.text("选区轻提示", "Selection Prompt")
        case .hidden:
            return language.text("隐藏对话", "Hide Chat")
        }
    }

    public func actionLabel(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .hidden:
            return label(language: language)
        case .selectionFloat:
            return language.text("使用\(label(language: language))", "Use \(label(language: language))")
        }
    }
}

public enum NoteRenderMode: String, Codable, CaseIterable, Identifiable {
    case rich
    case split
    case source
    case preview

    public var id: String { rawValue }
    public static let visibleCases: [NoteRenderMode] = [.rich, .split, .source]

    public var visibleMode: NoteRenderMode {
        self == .preview ? .rich : self
    }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .rich:
            return language.text("写作", "Write")
        case .split:
            return language.text("对照", "Compare")
        case .source:
            return language.text("源码", "Source")
        case .preview:
            return language.text("预览", "Preview")
        }
    }
}

public struct NoteEditorCommand: Identifiable, Hashable {
    public enum Kind: String, Hashable {
        case replaceSelection
        case applyAgentPatch
        case insertMarkdown
        case scrollToHeading
    }

    public var id: UUID
    public var kind: Kind
    public var markdown: String

    public init(id: UUID = UUID(), kind: Kind, markdown: String) {
        self.id = id
        self.kind = kind
        self.markdown = markdown
    }
}
