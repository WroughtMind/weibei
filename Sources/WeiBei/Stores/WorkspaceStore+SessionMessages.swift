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

@MainActor
final class StudySessionMessagePersistence {
    var loadedIDs = Set<UUID>()
    var lastWrittenData: [UUID: Data] = [:]
    var needsWorkspacePersist = false

    func annotatingMessageCount(_ session: StudySession) -> StudySession {
        guard loadedIDs.contains(session.id) else { return session }
        var next = session
        next.messageCount = session.messages.count
        return next
    }
}

struct StudySessionMessageWrite: Sendable {
    var sessionID: UUID
    var data: Data
    var url: URL
}

@MainActor
extension WorkspaceStore {
    func applyStudySessionsFromSnapshot(_ snapshot: PersistedWorkspace) {
        let incoming = (snapshot.studySessions ?? []).map { session in
            interruptedGeneratingMessages(in: session)
        }
        studySessions = incoming
        sessionMessagePersistence.loadedIDs = []
        sessionMessagePersistence.lastWrittenData = [:]
        let hadEmbeddedMessages = incoming.contains { !$0.messages.isEmpty }
        if hadEmbeddedMessages {
            for session in incoming {
                sessionMessagePersistence.loadedIDs.insert(session.id)
            }
            migrateEmbeddedStudySessionMessagesIfNeeded(incoming)
        } else {
            if let activeID = snapshot.activeStudySessionID {
                ensureStudySessionMessagesLoaded(activeID)
            }
        }
    }

    func loadStudySessionForActivation(_ id: UUID?) -> StudySession? {
        guard let id else { return nil }
        ensureStudySessionMessagesLoaded(id)
        return studySessions.first { $0.id == id }
    }

    func markStudySessionMessagesLoaded(_ id: UUID) {
        sessionMessagePersistence.loadedIDs.insert(id)
    }

    func forgetStudySessionMessages(_ id: UUID) {
        sessionMessagePersistence.loadedIDs.remove(id)
        sessionMessagePersistence.lastWrittenData.removeValue(forKey: id)
    }

    func ensureStudySessionMessagesLoaded(_ id: UUID) {
        guard let index = studySessions.firstIndex(where: { $0.id == id }) else {
            return
        }
        if sessionMessagePersistence.loadedIDs.contains(id) {
            return
        }
        let messages = readStudySessionMessages(sessionID: id)
        studySessions[index].messages = interruptingGenerating(messages)
        studySessions[index].messageCount = studySessions[index].messages.count
        sessionMessagePersistence.loadedIDs.insert(id)
        if let data = try? encodeSessionMessages(
            sessionID: id,
            messages: studySessions[index].messages
        ) {
            sessionMessagePersistence.lastWrittenData[id] = data
        }
    }

    func ensureAllStudySessionMessagesLoaded() {
        for session in studySessions where session.hasChatHistory {
            ensureStudySessionMessagesLoaded(session.id)
        }
    }

    func noteSuccessfulSessionMessagePersist(
        writes: [StudySessionMessageWrite],
        deletions: [URL]
    ) {
        for write in writes {
            sessionMessagePersistence.lastWrittenData[write.sessionID] = write.data
            sessionMessagePersistence.loadedIDs.insert(write.sessionID)
        }
        for url in deletions {
            let name = url.deletingPathExtension().lastPathComponent
            if let id = UUID(uuidString: name) {
                sessionMessagePersistence.lastWrittenData.removeValue(forKey: id)
                sessionMessagePersistence.loadedIDs.remove(id)
            }
        }
        sessionMessagePersistence.needsWorkspacePersist = false
    }

    func sessionMessageWrites(
        for sessions: [StudySession]
    ) throws -> (writes: [StudySessionMessageWrite], deletions: [URL]) {
        let persistedIDs = Set(sessions.map(\.id))
        var writes: [StudySessionMessageWrite] = []
        for session in sessions {
            guard sessionMessagePersistence.loadedIDs.contains(session.id)
                || !session.messages.isEmpty else {
                continue
            }
            let data = try encodeSessionMessages(
                sessionID: session.id,
                messages: session.messages
            )
            if sessionMessagePersistence.lastWrittenData[session.id] == data {
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

    private func migrateEmbeddedStudySessionMessagesIfNeeded(
        _ sessions: [StudySession]
    ) {
        let backupURL = StudySessionMessageFile.backupURL(in: workspaceDirectory)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: backupURL.path),
           fileManager.fileExists(atPath: storageURL.path) {
            do {
                try fileManager.copyItem(at: storageURL, to: backupURL)
            } catch {
                reportSessionMessageExternalizationFailure(error)
                return
            }
        }
        do {
            try fileManager.createDirectory(
                at: StudySessionMessageFile.directory(in: workspaceDirectory),
                withIntermediateDirectories: true
            )
        } catch {
            reportSessionMessageExternalizationFailure(error)
            return
        }
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
                sessionMessagePersistence.lastWrittenData[session.id] = try
                    StudySessionMessageFile.encoder().encode(decoded)
            }
        } catch {
            restoreWorkspaceSnapshotFromPreExternalizationBackup()
            reportSessionMessageExternalizationFailure(error)
            return
        }
        guard StudySessionMessageMigration.validate(
            expectedSessions: sessions,
            written: written
        ) else {
            restoreWorkspaceSnapshotFromPreExternalizationBackup()
            reportSessionMessageExternalizationFailure(nil)
            return
        }
        sessionMessagePersistence.needsWorkspacePersist = true
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

    private func reportSessionMessageExternalizationFailure(_ error: Error?) {
        WeiBeiLog.workspace.error(
            "code=session_message_externalization_failed path=\(self.storageURL.path, privacy: .private) reason=\(error?.localizedDescription ?? "validation", privacy: .private)"
        )
        _ = reportWorkspaceSaveFailure(
            .sessionMessageExternalizationFailed,
            ui(
                "聊天记录外置没有完成，已用原来的工作区继续。本次修改仍在当前会话中。",
                "Chat history was not moved into per-session files; WeiBei kept the original workspace. This change remains in the current session."
            ),
            reason: error?.localizedDescription
        )
        sessionMessagePersistence.needsWorkspacePersist = false
    }

    private func readStudySessionMessages(sessionID: UUID) -> [AgentMessage] {
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

    private func interruptedGeneratingMessages(in session: StudySession) -> StudySession {
        var bounded = session
        bounded.messages = interruptingGenerating(session.messages)
        return bounded
    }

    private func interruptingGenerating(_ messages: [AgentMessage]) -> [AgentMessage] {
        var next = messages
        for index in next.indices where next[index].completionState == .generating {
            recoveredInterruptedAgentReply = true
            next[index].completionState = .interrupted
            next[index].failureKind = .cancelled
            if next[index].retryQuestion == nil {
                next[index].retryQuestion = next[..<index]
                    .last(where: { $0.role == .user })?
                    .text
            }
        }
        return next
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
