import Foundation

enum NoteEditorBridgeProtocol {
    static let version = 2
}

enum NoteEditorCommandType: String, Codable, Sendable {
    case loadDocument
    case requestSnapshot
    case applyMarkdownFragment
    case replaceSelection
    case executeSelectionCommand
    case insertStructuredBlock
    case setTheme
    case setLanguage
    case setEditable
    case focus
    case scrollToHeading
    case restoreCheckpoint
}

struct NoteEditorCommandEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    let protocolVersion: Int
    let commandID: String
    let requestID: String?
    let documentID: String
    let documentGeneration: UInt64
    let minimumRevision: UInt64?
    let type: NoteEditorCommandType
    let payload: Payload

    init(
        commandID: String = UUID().uuidString,
        requestID: String? = nil,
        documentID: String,
        documentGeneration: UInt64,
        minimumRevision: UInt64? = nil,
        type: NoteEditorCommandType,
        payload: Payload
    ) {
        protocolVersion = NoteEditorBridgeProtocol.version
        self.commandID = commandID
        self.requestID = requestID
        self.documentID = documentID
        self.documentGeneration = documentGeneration
        self.minimumRevision = minimumRevision
        self.type = type
        self.payload = payload
    }
}

struct NoteEditorEmptyPayload: Codable, Sendable {}

struct NoteEditorLoadDocumentPayload: Codable, Sendable {
    let markdown: String
    let initialRevision: UInt64
}

struct NoteEditorMarkdownPayload: Codable, Sendable {
    let markdown: String
}

struct NoteEditorSelectionCommandPayload: Codable, Sendable {
    let action: String
    let value: String?
}

struct NoteEditorScrollPayload: Codable, Sendable {
    let index: Int
}

struct NoteEditorThemePayload: Codable, Sendable {
    let theme: String
}

struct NoteEditorLanguagePayload: Codable, Sendable {
    let language: String
}

struct NoteEditorEditablePayload: Codable, Sendable {
    let editable: Bool
}

typealias NoteEditorSnapshotRequest = NoteEditorCommandEnvelope<NoteEditorEmptyPayload>

struct NoteEditorDirtyChangedEvent: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let documentID: String
    let documentGeneration: UInt64
    let revision: UInt64
    let dirty: Bool

    init(
        protocolVersion: Int = NoteEditorBridgeProtocol.version,
        documentID: String,
        documentGeneration: UInt64,
        revision: UInt64,
        dirty: Bool
    ) {
        self.protocolVersion = protocolVersion
        self.documentID = documentID
        self.documentGeneration = documentGeneration
        self.revision = revision
        self.dirty = dirty
    }
}

struct NoteEditorSnapshotReadyEvent: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let requestID: String
    let documentID: String
    let documentGeneration: UInt64
    let revision: UInt64
    let markdown: String

    init(
        protocolVersion: Int = NoteEditorBridgeProtocol.version,
        requestID: String,
        documentID: String,
        documentGeneration: UInt64,
        revision: UInt64,
        markdown: String
    ) {
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.documentID = documentID
        self.documentGeneration = documentGeneration
        self.revision = revision
        self.markdown = markdown
    }
}

struct NoteEditorOutlineItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let index: Int
    let level: Int
    let title: String
    let position: Double
}

struct NoteEditorOutlineChangedEvent: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let documentID: String
    let documentGeneration: UInt64
    let revision: UInt64
    let items: [NoteEditorOutlineItem]
}
