import Foundation
import WeiBeiCore

#if DEBUG
enum StudySessionMessageExternalizationTesting {
    static var corruptSessionIDAfterMigrationWrite: UUID?

    static func reset() {
        corruptSessionIDAfterMigrationWrite = nil
    }
}
#endif

struct StudySessionMessageWrite: Sendable {
    var sessionID: UUID
    var data: Data
    var url: URL
}

@MainActor
final class StudySessionMessagePersistence {
    private let storageURL: URL
    private let workspaceDirectory: URL
    private var loadedIDs = Set<UUID>()
    private var lastWrittenData: [UUID: Data] = [:]
    private(set) var needsWorkspacePersist = false

    init(storageURL: URL) {
        self.storageURL = storageURL
        workspaceDirectory = storageURL.deletingLastPathComponent().standardizedFileURL
    }

    func resetLoadedSessions() {
        loadedIDs = []
        lastWrittenData = [:]
    }

    func markLoaded(_ id: UUID) {
        loadedIDs.insert(id)
    }

    func forget(_ id: UUID) {
        loadedIDs.remove(id)
        lastWrittenData.removeValue(forKey: id)
    }

    func messagesIfNeeded(for sessionID: UUID) -> [AgentMessage]? {
        guard !loadedIDs.contains(sessionID) else { return nil }
        let url = StudySessionMessageFile.fileURL(
            sessionID: sessionID,
            in: workspaceDirectory
        )
        if let data = try? Data(contentsOf: url),
           let payload = try? StudySessionMessageFile.decoder()
            .decode(PersistedStudySessionMessages.self, from: data),
           payload.sessionID == sessionID {
            return payload.messages
        }
        return messagesFromPreExternalizationBackup(sessionID: sessionID) ?? []
    }

    /// Record the messages after the workspace has restored interrupted replies.
    func didLoad(_ session: StudySession) {
        loadedIDs.insert(session.id)
        if let data = try? encodeSessionMessages(
            sessionID: session.id,
            messages: session.messages
        ) {
            lastWrittenData[session.id] = data
        }
    }

    func annotatingMessageCount(_ session: StudySession) -> StudySession {
        guard loadedIDs.contains(session.id) else { return session }
        var next = session
        next.messageCount = session.messages.count
        return next
    }

    /// Called only after the workspace transaction succeeds for the current generation.
    func noteSuccessfulPersist(
        writes: [StudySessionMessageWrite],
        deletions: [URL]
    ) {
        for write in writes {
            lastWrittenData[write.sessionID] = write.data
            loadedIDs.insert(write.sessionID)
        }
        for url in deletions {
            let name = url.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: name) {
                forget(id)
            }
        }
        needsWorkspacePersist = false
    }

    func writes(
        for sessions: [StudySession]
    ) throws -> (writes: [StudySessionMessageWrite], deletions: [URL]) {
        let persistedIDs = Set(sessions.map(\.id))
        var writes: [StudySessionMessageWrite] = []
        for session in sessions {
            guard loadedIDs.contains(session.id)
                || !session.messages.isEmpty else {
                continue
            }
            let data = try encodeSessionMessages(
                sessionID: session.id,
                messages: session.messages
            )
            if lastWrittenData[session.id] == data {
                continue
            }
            writes.append(
                StudySessionMessageWrite(
                    sessionID: session.id,
                    data: data,
                    url: StudySessionMessageFile.fileURL(
                        sessionID: session.id,
                        in: workspaceDirectory
                    )
                )
            )
        }
        let deletions = sessionMessageFilesOnDisk().filter { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name) else { return false }
            return !persistedIDs.contains(id)
        }
        return (writes, deletions)
    }

    /// Returns false when the written messages fail the existing migration validation.
    func migrateEmbeddedMessages(_ sessions: [StudySession]) throws -> Bool {
        loadedIDs.formUnion(sessions.map(\.id))
        needsWorkspacePersist = false
        let backupURL = StudySessionMessageFile.backupURL(in: workspaceDirectory)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: backupURL.path),
           fileManager.fileExists(atPath: storageURL.path) {
            try fileManager.copyItem(at: storageURL, to: backupURL)
        }
        try fileManager.createDirectory(
            at: StudySessionMessageFile.directory(in: workspaceDirectory),
            withIntermediateDirectories: true
        )
        var written: [UUID: PersistedStudySessionMessages] = [:]
        do {
            for session in sessions {
                let payload = PersistedStudySessionMessages(
                    sessionID: session.id,
                    messages: session.messages
                )
                let data = try StudySessionMessageFile.encoder().encode(payload)
                let url = StudySessionMessageFile.fileURL(
                    sessionID: session.id,
                    in: workspaceDirectory
                )
                try data.write(to: url, options: [.atomic])
#if DEBUG
                if StudySessionMessageExternalizationTesting
                    .corruptSessionIDAfterMigrationWrite == session.id {
                    try Data("not-a-session".utf8).write(to: url, options: [.atomic])
                }
#endif
                let verified = try Data(contentsOf: url)
                let decoded = try StudySessionMessageFile.decoder()
                    .decode(PersistedStudySessionMessages.self, from: verified)
                written[session.id] = decoded
                lastWrittenData[session.id] = try
                    StudySessionMessageFile.encoder().encode(decoded)
            }
        } catch {
            restoreWorkspaceSnapshotFromPreExternalizationBackup()
            throw error
        }
        guard StudySessionMessageMigration.validate(
            expectedSessions: sessions,
            written: written
        ) else {
            restoreWorkspaceSnapshotFromPreExternalizationBackup()
            return false
        }
        needsWorkspacePersist = true
        return true
    }

    private func restoreWorkspaceSnapshotFromPreExternalizationBackup() {
        let backupURL = StudySessionMessageFile.backupURL(in: workspaceDirectory)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: backupURL.path) else { return }
        do {
            if fileManager.fileExists(atPath: storageURL.path) {
                try fileManager.removeItem(at: storageURL)
            }
            try fileManager.copyItem(at: backupURL, to: storageURL)
        } catch {
            WeiBeiLog.workspace.error(
                "code=session_message_externalization_rollback_failed reason=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func messagesFromPreExternalizationBackup(sessionID: UUID) -> [AgentMessage]? {
        let backupURL = StudySessionMessageFile.backupURL(in: workspaceDirectory)
        guard let data = try? Data(contentsOf: backupURL),
              let snapshot = try? JSONDecoder().decode(PersistedWorkspace.self, from: data),
              let session = snapshot.studySessions?.first(where: { $0.id == sessionID })
        else {
            return nil
        }
        return session.messages
    }

    private func encodeSessionMessages(
        sessionID: UUID,
        messages: [AgentMessage]
    ) throws -> Data {
        try StudySessionMessageFile.encoder().encode(
            PersistedStudySessionMessages(sessionID: sessionID, messages: messages)
        )
    }

    private func sessionMessageFilesOnDisk() -> [URL] {
        let directory = StudySessionMessageFile.directory(in: workspaceDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return names.filter { $0.pathExtension.lowercased() == "json" }
    }
}
