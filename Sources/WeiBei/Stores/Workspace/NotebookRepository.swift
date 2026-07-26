import Foundation
import CryptoKit
import WeiBeiCore

/// Owns notebook Markdown and rename-journal disk operations.
actor NotebookRepository {
    enum MarkdownWriteResult: Sendable {
        case written(contentDigest: String)
        case conflict
    }

    typealias MarkdownReader = (URL) throws -> String
    typealias MarkdownWriter = (String, URL) throws -> Void
    typealias FileMover = (URL, URL) throws -> Void

    private final class FileOperations: @unchecked Sendable {
        let renameJournalURL: URL
        let reader: MarkdownReader
        let writer: MarkdownWriter
        let mover: FileMover

        init(
            renameJournalURL: URL,
            reader: @escaping MarkdownReader,
            writer: @escaping MarkdownWriter,
            mover: @escaping FileMover
        ) {
            self.renameJournalURL = renameJournalURL
            self.reader = reader
            self.writer = writer
            self.mover = mover
        }
    }

    nonisolated private let operations: FileOperations

    /**
     * Creates the notebook persistence boundary.
     *
     * @param renameJournalURL - Crash-recovery journal location
     * @param reader - Injectable Markdown reader
     * @param writer - Injectable atomic Markdown writer
     * @param mover - Injectable file move operation
     */
    init(
        renameJournalURL: URL,
        reader: @escaping MarkdownReader,
        writer: @escaping MarkdownWriter,
        mover: @escaping FileMover
    ) {
        operations = FileOperations(
            renameJournalURL: renameJournalURL,
            reader: reader,
            writer: writer,
            mover: mover
        )
    }

    /**
     * Reads Markdown without blocking the main actor.
     *
     * @param url - Markdown file location
     * @returns UTF-8 Markdown contents
     */
    func readMarkdown(at url: URL) throws -> String {
        try operations.reader(url)
    }

    /**
     * Writes Markdown without blocking the main actor.
     *
     * @param markdown - Complete Markdown document
     * @param url - Destination file location
     */
    func writeMarkdown(_ markdown: String, to url: URL) throws {
        try operations.writer(markdown, url)
    }

    /**
     * Checks the backing generation and writes a debounced note as one serialized operation.
     *
     * @param markdown - Complete Markdown document
     * @param url - Backing Markdown location
     * @param expectedContentDigest - Digest captured when editing began
     * @param requiresKnownBaseline - Whether a retained draft requires a known baseline
     * @returns A written digest or a conflict result that leaves the file untouched
     */
    func writeMarkdown(
        _ markdown: String,
        to url: URL,
        expectedContentDigest: String?,
        requiresKnownBaseline: Bool
    ) throws -> MarkdownWriteResult {
        let currentDigest = (try? Data(contentsOf: url)).map(Self.contentDigest)
        let hasConflict: Bool
        if requiresKnownBaseline {
            hasConflict = expectedContentDigest.flatMap { expected in
                currentDigest.map { $0 != expected }
            } ?? true
        } else if let expectedContentDigest {
            hasConflict = currentDigest.map { $0 != expectedContentDigest } ?? true
        } else {
            hasConflict = false
        }
        guard !hasConflict else { return .conflict }
        try operations.writer(markdown, url)
        return .written(contentDigest: Self.contentDigest(Data(markdown.utf8)))
    }

    /**
     * Moves a notebook file as one serialized repository operation.
     *
     * @param sourceURL - Existing notebook location
     * @param destinationURL - New notebook location
     */
    func moveNotebook(from sourceURL: URL, to destinationURL: URL) throws {
        try operations.mover(sourceURL, destinationURL)
    }

    /**
     * Loads a typed rename journal for crash recovery.
     *
     * @param type - Journal payload type
     * @returns Decoded journal, or `nil` when none is recoverable
     */
    func loadRenameJournal<Journal: Decodable>(as type: Journal.Type) -> Journal? {
        guard let data = try? Data(contentsOf: operations.renameJournalURL) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /**
     * Persists a typed rename journal atomically.
     *
     * @param journal - Crash-recovery payload
     */
    func writeRenameJournal<Journal: Encodable>(_ journal: Journal) throws {
        let data = try JSONEncoder().encode(journal)
        try data.write(to: operations.renameJournalURL, options: [.atomic])
    }

    /// Removes the rename journal after both file and workspace state are durable.
    func removeRenameJournal() {
        try? FileManager.default.removeItem(at: operations.renameJournalURL)
    }

    /**
     * Reads Markdown at an explicit synchronous transaction boundary.
     *
     * Rename recovery currently commits file and in-memory identity changes as one main-actor
     * transaction, so it uses this narrow synchronous entry point.
     *
     * @param url - Markdown file location
     * @returns UTF-8 Markdown contents
     */
    nonisolated func readImmediately(at url: URL) throws -> String {
        try operations.reader(url)
    }

    /**
     * Writes Markdown at an explicit synchronous rename transaction boundary.
     *
     * @param markdown - Complete Markdown document
     * @param url - Destination file location
     */
    nonisolated func writeImmediately(_ markdown: String, to url: URL) throws {
        try operations.writer(markdown, url)
    }

    /**
     * Moves a notebook at an explicit synchronous rename transaction boundary.
     *
     * @param sourceURL - Existing notebook location
     * @param destinationURL - New notebook location
     */
    nonisolated func moveImmediately(from sourceURL: URL, to destinationURL: URL) throws {
        try operations.mover(sourceURL, destinationURL)
    }

    /**
     * Reads the crash-recovery journal synchronously during store initialization.
     *
     * @param type - Journal payload type
     * @returns Decoded journal, or `nil` when none is recoverable
     */
    nonisolated func loadRenameJournalImmediately<Journal: Decodable>(as type: Journal.Type) -> Journal? {
        guard let data = try? Data(contentsOf: operations.renameJournalURL) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /**
     * Persists the crash-recovery journal before a rename mutates the source file.
     *
     * @param journal - Crash-recovery payload
     */
    nonisolated func writeRenameJournalImmediately<Journal: Encodable>(_ journal: Journal) throws {
        let data = try JSONEncoder().encode(journal)
        try data.write(to: operations.renameJournalURL, options: [.atomic])
    }

    /// Removes the crash-recovery journal synchronously after a durable workspace save.
    nonisolated func removeRenameJournalImmediately() {
        try? FileManager.default.removeItem(at: operations.renameJournalURL)
    }

    private nonisolated static func contentDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
