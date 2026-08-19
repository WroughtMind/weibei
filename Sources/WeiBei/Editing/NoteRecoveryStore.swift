import CryptoKit
import Foundation

struct NoteRecoveryMetadata: Codable, Equatable, Sendable {
    let documentID: String
    let baseFileDigest: String
    let checkpointDigest: String
    let revision: UInt64
    let updatedAt: Date
    let dialectVersion: Int
}

struct NoteRecoveryCheckpoint: Equatable, Sendable {
    let metadata: NoteRecoveryMetadata
    let markdown: String
}

enum NoteRecoveryClassification: Equatable, Sendable {
    case none
    case stale
    case restore(NoteRecoveryCheckpoint)
    case conflict(NoteRecoveryCheckpoint)
    case damaged
}

enum NoteRecoveryStoreError: Error, Equatable, Sendable {
    case damagedCheckpoint
}

actor NoteRecoveryStore {
    private let rootURL: URL
    private var persistedCheckpointDigests: [String: String] = [:]

    init(
        rootURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("WeiBei/Recovery/Notes", isDirectory: true)
    ) {
        self.rootURL = rootURL
    }

    @discardableResult
    func store(
        documentID: String,
        baseFileDigest: String,
        revision: UInt64,
        markdown: String,
        updatedAt: Date = Date(),
        dialectVersion: Int = 1
    ) throws -> NoteRecoveryCheckpoint {
        let checkpointDigest = Self.digest(markdown)
        let metadata = NoteRecoveryMetadata(
            documentID: documentID,
            baseFileDigest: baseFileDigest,
            checkpointDigest: checkpointDigest,
            revision: revision,
            updatedAt: updatedAt,
            dialectVersion: dialectVersion
        )
        if persistedCheckpointDigests[documentID] == checkpointDigest {
            try remove(documentID: documentID)
            return NoteRecoveryCheckpoint(metadata: metadata, markdown: markdown)
        }
        let directory = directoryURL(for: documentID)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let markdownData = Data(markdown.utf8)
        try markdownData.write(
            to: directory.appendingPathComponent("latest-snapshot.md"),
            options: [.atomic]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(metadata).write(
            to: directory.appendingPathComponent("metadata.json"),
            options: [.atomic]
        )
        return NoteRecoveryCheckpoint(metadata: metadata, markdown: markdown)
    }

    func load(documentID: String) throws -> NoteRecoveryCheckpoint? {
        let directory = directoryURL(for: documentID)
        let metadataURL = directory.appendingPathComponent("metadata.json")
        let snapshotURL = directory.appendingPathComponent("latest-snapshot.md")
        let metadataExists = FileManager.default.fileExists(atPath: metadataURL.path)
        let snapshotExists = FileManager.default.fileExists(atPath: snapshotURL.path)
        guard metadataExists || snapshotExists else { return nil }
        guard metadataExists, snapshotExists else {
            throw NoteRecoveryStoreError.damagedCheckpoint
        }

        do {
            let decoder = JSONDecoder()
            let metadata = try decoder.decode(
                NoteRecoveryMetadata.self,
                from: Data(contentsOf: metadataURL)
            )
            let snapshotData = try Data(contentsOf: snapshotURL)
            guard metadata.documentID == documentID,
                  metadata.checkpointDigest == Self.digest(snapshotData),
                  let markdown = String(data: snapshotData, encoding: .utf8) else {
                throw NoteRecoveryStoreError.damagedCheckpoint
            }
            return NoteRecoveryCheckpoint(metadata: metadata, markdown: markdown)
        } catch let error as NoteRecoveryStoreError {
            throw error
        } catch {
            throw NoteRecoveryStoreError.damagedCheckpoint
        }
    }

    func remove(documentID: String) throws {
        let directory = directoryURL(for: documentID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    @discardableResult
    func removeIfCheckpointMatches(
        documentID: String,
        checkpointDigest: String
    ) throws -> Bool {
        persistedCheckpointDigests[documentID] = checkpointDigest
        guard let checkpoint = try load(documentID: documentID),
              checkpoint.metadata.checkpointDigest == checkpointDigest else {
            return false
        }
        try remove(documentID: documentID)
        return true
    }

    func classify(
        documentID: String,
        diskDigest: String
    ) throws -> NoteRecoveryClassification {
        let checkpoint: NoteRecoveryCheckpoint
        do {
            guard let loaded = try load(documentID: documentID) else { return .none }
            checkpoint = loaded
        } catch NoteRecoveryStoreError.damagedCheckpoint {
            return .damaged
        }

        if diskDigest == checkpoint.metadata.checkpointDigest {
            try remove(documentID: documentID)
            return .stale
        }
        if diskDigest == checkpoint.metadata.baseFileDigest {
            return .restore(checkpoint)
        }
        return .conflict(checkpoint)
    }

    private func directoryURL(for documentID: String) -> URL {
        rootURL.appendingPathComponent(Self.directoryName(for: documentID), isDirectory: true)
    }

    nonisolated static func directoryName(for documentID: String) -> String {
        digest(Data(documentID.utf8))
    }

    nonisolated static func digest(_ markdown: String) -> String {
        digest(Data(markdown.utf8))
    }

    private nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
