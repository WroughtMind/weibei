import Foundation

/// Per-session chat body stored beside `workspace.json`.
public struct PersistedStudySessionMessages: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var sessionID: UUID
    public var messages: [AgentMessage]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        sessionID: UUID,
        messages: [AgentMessage]
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.messages = messages
    }
}

public enum StudySessionMessageFile {
    public static let directoryName = "Sessions"
    public static let backupFileName = "workspace.json.pre-externalization"

    public static func directory(in workspaceDirectory: URL) -> URL {
        workspaceDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func fileURL(sessionID: UUID, in workspaceDirectory: URL) -> URL {
        directory(in: workspaceDirectory)
            .appendingPathComponent(
                "\(sessionID.uuidString.lowercased()).json",
                isDirectory: false
            )
    }

    public static func backupURL(in workspaceDirectory: URL) -> URL {
        workspaceDirectory.appendingPathComponent(backupFileName, isDirectory: false)
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}

public struct StudySessionMessageFingerprint: Equatable, Sendable {
    public var sessionID: UUID
    public var messageCount: Int
    public var lastMessageRole: AgentRole?
    public var lastMessageText: String?

    public init(sessionID: UUID, messages: [AgentMessage]) {
        self.sessionID = sessionID
        self.messageCount = messages.count
        self.lastMessageRole = messages.last?.role
        self.lastMessageText = messages.last?.text
    }

    public init(payload: PersistedStudySessionMessages) {
        self.init(sessionID: payload.sessionID, messages: payload.messages)
    }
}

public enum StudySessionMessageMigration {
    /// Session count, per-session message count, and last-message role+text must match.
    public static func validate(
        expectedSessions: [StudySession],
        written: [UUID: PersistedStudySessionMessages]
    ) -> Bool {
        guard written.count == expectedSessions.count else { return false }
        for session in expectedSessions {
            guard let payload = written[session.id],
                  payload.sessionID == session.id else {
                return false
            }
            let expected = StudySessionMessageFingerprint(
                sessionID: session.id,
                messages: session.messages
            )
            guard expected == StudySessionMessageFingerprint(payload: payload) else {
                return false
            }
        }
        return true
    }
}

extension PersistedWorkspace {
    public func strippingEmbeddedStudySessionMessages() -> PersistedWorkspace {
        var next = self
        next.studySessions = (studySessions ?? []).map { session in
            var stripped = session
            stripped.messageCount = session.messages.isEmpty
                ? session.messageCount
                : session.messages.count
            stripped.messages = []
            return stripped
        }
        return next
    }

    public var hasEmbeddedStudySessionMessages: Bool {
        (studySessions ?? []).contains { !$0.messages.isEmpty }
    }
}
