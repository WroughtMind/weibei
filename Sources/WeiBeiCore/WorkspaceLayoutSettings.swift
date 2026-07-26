import CoreGraphics
import Foundation

public enum WorkspaceLayout: String, Codable, CaseIterable, Identifiable {
    case documentAgentNotes
    case documentNotesAgent
    case documentNotesSplit
    case immersiveReading
    case immersiveConversation
    case immersiveWriting

    public var id: String { rawValue }

    public func label(language: WeiBeiInterfaceLanguage) -> String {
        switch self {
        case .documentAgentNotes:
            return language.text("阅读-对话-笔记", "Reader-Chat-Notes")
        case .documentNotesAgent:
            return language.text("阅读-笔记-对话", "Reader-Notes-Chat")
        case .documentNotesSplit:
            return language.text("阅读/笔记对半", "Reader / Notes")
        case .immersiveReading:
            return language.text("沉浸阅读", "Immersive Reading")
        case .immersiveConversation:
            return language.text("沉浸对话", "Immersive Chat")
        case .immersiveWriting:
            return language.text("沉浸写笔记", "Immersive Writing")
        }
    }

    public var hasCollapsibleRightPane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit, .immersiveConversation:
            return true
        case .immersiveReading, .immersiveWriting:
            return false
        }
    }

    public var isDocumentThreePane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent:
            return true
        case .documentNotesSplit, .immersiveReading, .immersiveConversation, .immersiveWriting:
            return false
        }
    }

    /// Document family (multi-pane) vs immersive single-pane — used so SwiftUI only animates family switches,
    /// not every document-internal pane toggle (those are animated by AppKit).
    public var isImmersiveFamily: Bool {
        switch self {
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return true
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return false
        }
    }

    public var allowsRailOnlyPanes: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .documentNotesSplit:
            return true
        case .immersiveReading, .immersiveConversation, .immersiveWriting:
            return false
        }
    }

    public var defaultThreePaneOrder: [WorkspacePaneRole]? {
        switch self {
        case .documentAgentNotes:
            return [.reader, .agent, .notes]
        case .documentNotesAgent:
            return [.reader, .notes, .agent]
        case .documentNotesSplit, .immersiveReading, .immersiveConversation, .immersiveWriting:
            return nil
        }
    }

    public var systemImage: String {
        switch self {
        case .documentAgentNotes:
            return "rectangle.split.3x1"
        case .documentNotesAgent:
            return "rectangle.split.3x1.fill"
        case .documentNotesSplit:
            return "rectangle.split.2x1"
        case .immersiveReading:
            return "doc.text.magnifyingglass"
        case .immersiveConversation:
            return "bubble.left.and.text.bubble.right"
        case .immersiveWriting:
            return "square.and.pencil"
        }
    }

    public var hasPrimaryAgentPane: Bool {
        switch self {
        case .documentAgentNotes, .documentNotesAgent, .immersiveConversation:
            return true
        case .documentNotesSplit, .immersiveReading, .immersiveWriting:
            return false
        }
    }
}

/// Conversation presentation overlays retained for 1.0.
/// Primary chat lives in the immersive conversation layout / agent pane;
/// only selection-float and hidden remain as `AgentSurface` cases.
/// How a provider is typically configured in Pi (subscription OAuth vs API key vs local/custom).
