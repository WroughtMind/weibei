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
    var messages: [AgentMessage]
    var data: Data
    var url: URL
}

@MainActor
final class StudySessionMessagePersistence {
    private let storageURL: URL
    private let workspaceDirectory: URL
    private var loadedIDs = Set<UUID>()
    private var lastWrittenMessages: [UUID: [AgentMessage]] = [:]
    private var lastPersistedSessionIDs: Set<UUID>?
    private(set) var needsWorkspacePersist = false
#if DEBUG
    private(set) var lastPreparationEncodedSessionIDs: [UUID] = []
    private(set) var lastPreparationScannedDirectory = false
    private(set) var lastPreparationRanOnMainThread = false
#endif

    init(storageURL: URL) {
        self.storageURL = storageURL
        workspaceDirectory = storageURL.deletingLastPathComponent().standardizedFileURL
    }

    func resetLoadedSessions() {
        loadedIDs = []
        lastWrittenMessages = [:]
        lastPersistedSessionIDs = nil
    }

    func markLoaded(_ id: UUID) {
        loadedIDs.insert(id)
    }

    func forget(_ id: UUID) {
        loadedIDs.remove(id)
        lastWrittenMessages.removeValue(forKey: id)
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
            lastWrittenMessages[sessionID] = payload.messages
            return payload.messages
        }
        return messagesFromPreExternalizationBackup(sessionID: sessionID) ?? []
    }

    /// Record the messages after the workspace has restored interrupted replies.
    func didLoad(_ session: StudySession) {
        loadedIDs.insert(session.id)
    }

    func annotatingMessageCount(_ session: StudySession) -> StudySession {
        guard loadedIDs.contains(session.id) else { return session }
        var next = session
        next.messageCount = session.messages.count
        return next
    }

    /// Called only after the workspace transaction succeeds for the current generation.
    func noteSuccessfulPersist(
        sessions: [StudySession],
        writes: [StudySessionMessageWrite],
        deletions: [URL]
    ) {
        for write in writes {
            lastWrittenMessages[write.sessionID] = write.messages
            loadedIDs.insert(write.sessionID)
        }
        for url in deletions {
            let name = url.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: name) {
                forget(id)
            }
        }
        lastPersistedSessionIDs = Set(sessions.map(\.id))
        needsWorkspacePersist = false
    }

    func writes(
        for sessions: [StudySession]
    ) async throws -> (writes: [StudySessionMessageWrite], deletions: [URL]) {
        // Snapshot value buffers before leaving the UI actor. Unchanged arrays
        // share their storage; even a changed buffer is compared off the UI thread.
        let prepared = try await Task.detached(priority: .utility) {
            [loadedIDs, lastWrittenMessages, lastPersistedSessionIDs, workspaceDirectory] in
            let ranOnMainThread = pthread_main_np() != 0
            let persistedIDs = Set(sessions.map(\.id))
            var writes: [StudySessionMessageWrite] = []
            for session in sessions {
                guard loadedIDs.contains(session.id) || !session.messages.isEmpty,
                      lastWrittenMessages[session.id] != session.messages else { continue }
                let data = try Self.encodeSessionMessages(
                    sessionID: session.id,
                    messages: session.messages
                )
                writes.append(StudySessionMessageWrite(
                    sessionID: session.id,
                    messages: session.messages,
                    data: data,
                    url: StudySessionMessageFile.fileURL(
                        sessionID: session.id,
                        in: workspaceDirectory
                    )
                ))
            }
            // Reconcile orphan files initially and after a session is added or
            // removed, not after every pane/focus change. Failure keeps this dirty.
            let scansDirectory = lastPersistedSessionIDs != persistedIDs
            let deletions = scansDirectory
                ? Self.sessionMessageFilesOnDisk(in: workspaceDirectory).filter { url in
                    let name = url.deletingPathExtension().lastPathComponent
                    guard let id = UUID(uuidString: name) else { return false }
                    return !persistedIDs.contains(id)
                } : []
            return (writes, deletions, scansDirectory, ranOnMainThread)
        }.value
#if DEBUG
        lastPreparationEncodedSessionIDs = prepared.0.map(\.sessionID)
        lastPreparationScannedDirectory = prepared.2
        lastPreparationRanOnMainThread = prepared.3
#endif
        return (prepared.0, prepared.1)
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
                lastWrittenMessages[session.id] = decoded.messages
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

    nonisolated private static func encodeSessionMessages(
        sessionID: UUID,
        messages: [AgentMessage]
    ) throws -> Data {
        try StudySessionMessageFile.encoder().encode(
            PersistedStudySessionMessages(sessionID: sessionID, messages: messages)
        )
    }

    nonisolated private static func sessionMessageFilesOnDisk(in workspaceDirectory: URL) -> [URL] {
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
