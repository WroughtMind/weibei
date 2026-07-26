import Foundation
import WeiBeiCore

/// Serializes workspace snapshot writes away from the main actor.
actor WorkspaceRepository {
    typealias SnapshotWriter = (Data, URL) throws -> Void

    private final class SerializedStorage: @unchecked Sendable {
        private let lock = NSLock()
        private let storageURL: URL
        private let writer: SnapshotWriter
        private var latestGeneration: UInt64 = 0

        init(storageURL: URL, writer: @escaping SnapshotWriter) {
            self.storageURL = storageURL
            self.writer = writer
        }

        func save(_ data: Data, generation: UInt64) throws {
            lock.lock()
            defer { lock.unlock() }
            guard generation >= latestGeneration else { return }
            try writer(data, storageURL)
            latestGeneration = generation
        }
    }

    nonisolated private let storage: SerializedStorage

    /**
     * Creates a repository for one workspace snapshot file.
     *
     * @param storageURL - Destination of the encoded workspace snapshot
     * @param writer - Injectable atomic writer used by production and identity self-checks
     */
    init(storageURL: URL, writer: @escaping SnapshotWriter) {
        storage = SerializedStorage(storageURL: storageURL, writer: writer)
    }

    /**
     * Reads and decodes the initial snapshot before the observable store is presented.
     *
     * Initial loading deliberately remains synchronous because `WorkspaceStore` must expose
     * a coherent snapshot immediately after initialization.
     *
     * @param storageURL - Workspace snapshot location
     * @returns The decoded workspace, or `nil` when no valid snapshot exists
     */
    nonisolated static func load(from storageURL: URL) -> PersistedWorkspace? {
        guard let data = try? Data(contentsOf: storageURL) else { return nil }
        return try? JSONDecoder().decode(PersistedWorkspace.self, from: data)
    }

    /**
     * Writes a coalesced snapshot on the repository actor.
     *
     * Older tasks may reach the actor after a newer UI mutation. Generation filtering keeps
     * those stale tasks from replacing the latest snapshot.
     *
     * @param data - Encoded workspace snapshot
     * @param generation - Monotonic generation assigned by `WorkspaceStore`
     */
    func save(_ data: Data, generation: UInt64) throws {
        try storage.save(data, generation: generation)
    }

    /**
     * Performs the explicit durability-boundary write used during app shutdown and retries.
     *
     * @param data - Encoded workspace snapshot
     * @param generation - Monotonic generation that supersedes older queued writes
     */
    nonisolated func saveImmediately(_ data: Data, generation: UInt64) throws {
        try storage.save(data, generation: generation)
    }
}
