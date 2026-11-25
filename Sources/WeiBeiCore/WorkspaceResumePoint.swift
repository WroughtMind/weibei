import Foundation

/// The user's last open work, separate from the blank launch screen.
public struct WorkspaceResumePoint: Codable, Sendable {
    public var materialID: String?
    public var noteID: String?
    public var chatID: UUID?
    public var draft: String
    public var order: [WorkspacePaneRole]
    public var reader: Bool
    public var notes: Bool
    public var chat: Bool

    public init(materialID: String?, noteID: String?, chatID: UUID?, draft: String, order: [WorkspacePaneRole], reader: Bool, notes: Bool, chat: Bool) {
        self.materialID = materialID
        self.noteID = noteID
        self.chatID = chatID
        self.draft = draft
        self.order = order
        self.reader = reader
        self.notes = notes
        self.chat = chat
    }
}
