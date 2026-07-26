import AppKit
import CryptoKit
import Darwin
import Foundation
import PDFKit
import SQLite3

private final class CourseIndexCancellationProbe {
    var isCancelled: Bool {
        var cancelled = false
        withUnsafeCurrentTask { task in
            cancelled = task?.isCancelled ?? false
        }
        return cancelled
    }
}

public struct CourseDocumentIndexResult: Sendable {
    public var text: String?
    public var isTruncated: Bool

    public init(text: String?, isTruncated: Bool) {
        self.text = text
        self.isTruncated = isTruncated
    }
}

public typealias CourseNativePDFTextLoader = @Sendable (
    _ url: URL,
    _ pageIndexes: [Int],
    _ maximumCharactersPerPage: Int,
    _ timeout: TimeInterval
) -> [Int: BoundedPDFTextPage]?

public final class CourseDocumentSearchIndex: @unchecked Sendable {
    static let maximumDatabaseBytes: UInt64 = 1_024 * 1_024 * 1_024
    static let maximumSQLiteBytes: UInt64 = 768 * 1_024 * 1_024
    static let sqlitePageBytes: UInt64 = 4_096
    static let minimumWriteReserveBytes: UInt64 = 1 * 1_024 * 1_024
    static let maximumImmediateRefreshItems = 24
    static let maximumImmediateRefreshSeconds: TimeInterval = 4
    static let maximumTextSourceBytes: UInt64 = 32 * 1_024 * 1_024
    static let maximumForegroundPDFPages = 32
    static let maximumNativePDFPagesPerWorker = 8
    static let maximumPDFPageCharacters = 128_000
    static let foregroundPDFTextBudget: TimeInterval = 2
    static let backgroundPDFTextBudget: TimeInterval = 20
    struct FileState {
        var signature: String
        var isComplete: Bool
        var chunkCount: Int
        var hasPartialExtraction: Bool
    }

    struct RankedChunk {
        var sortOrder: Int
        var text: String
    }

    let databaseURL: URL
    let nativePDFTextLoader: CourseNativePDFTextLoader
    let indexingQueue = DispatchQueue(
        label: "com.changfenhuang.weibei.course-index",
        qos: .utility
    )
    let metadataQueue = DispatchQueue(
        label: "com.changfenhuang.weibei.course-index.metadata",
        qos: .utility
    )
    let ocrQueue = DispatchQueue(
        label: "com.changfenhuang.weibei.course-index.ocr",
        qos: .background
    )
    let schedulingLock = NSLock()
    let databaseWriteLock = NSLock()
    let itemIndexLockRegistryLock = NSLock()
    var scheduledSignatures: Set<String> = []
    var expectedSignaturesByStorageID: [String: String] = [:]
    var itemIndexLocks: [String: NSLock] = [:]
    let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(
        databaseURL: URL,
        nativePDFTextLoader: @escaping CourseNativePDFTextLoader = { url, pageIndexes, maximumCharacters, timeout in
            BoundedPDFTextExtractor.pages(
                from: url,
                pageIndexes: pageIndexes,
                maximumCharactersPerPage: maximumCharacters,
                timeout: timeout
            )
        }
    ) {
        self.databaseURL = databaseURL
        self.nativePDFTextLoader = nativePDFTextLoader
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
        guard let database = openDatabase() else { return }
        defer { sqlite3_close(database) }
        _ = execute("PRAGMA page_size=4096", in: database)
        _ = execute(
            "PRAGMA max_page_count=\(Self.maximumSQLiteBytes / Self.sqlitePageBytes)",
            in: database
        )
        _ = execute("PRAGMA auto_vacuum=INCREMENTAL", in: database)
        _ = execute("PRAGMA journal_mode=WAL", in: database)
        _ = execute("PRAGMA synchronous=NORMAL", in: database)
        _ = execute("PRAGMA journal_size_limit=67108864", in: database)
        _ = execute("PRAGMA wal_autocheckpoint=256", in: database)
        _ = execute(
            """
            CREATE TABLE IF NOT EXISTS files (
                item_id TEXT PRIMARY KEY,
                signature TEXT NOT NULL,
                kind TEXT NOT NULL,
                page_count INTEGER NOT NULL DEFAULT 0,
                processed_count INTEGER NOT NULL DEFAULT 0,
                is_complete INTEGER NOT NULL DEFAULT 0,
                chunk_count INTEGER NOT NULL DEFAULT 0
            )
            """,
            in: database
        )
        _ = execute(
            "ALTER TABLE files ADD COLUMN chunk_count INTEGER NOT NULL DEFAULT 0",
            in: database
        )
        _ = execute(
            """
            CREATE TABLE IF NOT EXISTS processed_pages (
                item_id TEXT NOT NULL,
                page_index INTEGER NOT NULL,
                extraction_kind TEXT NOT NULL,
                PRIMARY KEY (item_id, page_index)
            )
            """,
            in: database
        )
        _ = execute(
            """
            CREATE TABLE IF NOT EXISTS native_attempted_pages (
                item_id TEXT NOT NULL,
                page_index INTEGER NOT NULL,
                PRIMARY KEY (item_id, page_index)
            )
            """,
            in: database
        )
        _ = execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(
                item_id UNINDEXED,
                sort_order UNINDEXED,
                location UNINDEXED,
                text UNINDEXED,
                terms,
                tokenize = 'unicode61 remove_diacritics 2'
            )
            """,
            in: database
        )
        _ = execute(
            """
            CREATE TABLE IF NOT EXISTS chunk_index (
                chunk_rowid INTEGER PRIMARY KEY,
                item_id TEXT NOT NULL,
                sort_order INTEGER NOT NULL
            )
            """,
            in: database
        )
        _ = execute(
            "CREATE INDEX IF NOT EXISTS chunk_index_item_sort ON chunk_index(item_id, sort_order)",
            in: database
        )
    }

    public func schedule(_ items: [StudyItem]) {
        metadataQueue.async { [weak self] in
            guard let self else { return }
            let scheduledItems = items.compactMap(Self.scheduledItem)
            self.schedulingLock.lock()
            for scheduled in scheduledItems {
                self.expectedSignaturesByStorageID[scheduled.storageID] = scheduled.signature
            }
            self.schedulingLock.unlock()
            scheduledItems.forEach(self.schedule)
        }
    }

    public func synchronize(_ items: [StudyItem]) {
        metadataQueue.async { [weak self] in
            guard let self else { return }
            let scheduledItems = items.compactMap(Self.scheduledItem)
            let validStorageIDs = Set(scheduledItems.map(\.storageID))
            self.schedulingLock.lock()
            self.expectedSignaturesByStorageID = Dictionary(
                uniqueKeysWithValues: scheduledItems.map { ($0.storageID, $0.signature) }
            )
            self.schedulingLock.unlock()
            self.indexingQueue.async { [weak self] in
                self?.pruneMissingItems(validStorageIDs: validStorageIDs)
            }
            scheduledItems.forEach(self.schedule)
        }
    }

    public func lookup(
        items: [StudyItem],
        query: String,
        maximumCharactersPerItem: Int = 24_000
    ) -> [String: CourseDocumentIndexResult] {
        refreshChangedItemsForLookup(items)
        guard !Task.isCancelled else { return [:] }
        guard let database = openDatabase() else { return [:] }
        defer { sqlite3_close(database) }
        let cancellationProbe = CourseIndexCancellationProbe()
        let cancellationContext = Unmanaged.passRetained(cancellationProbe).toOpaque()
        sqlite3_progress_handler(
            database,
            1_000,
            { context in
                guard let context else { return 0 }
                let probe = Unmanaged<CourseIndexCancellationProbe>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                return probe.isCancelled ? 1 : 0
            },
            cancellationContext
        )
        defer {
            sqlite3_progress_handler(database, 0, nil, nil)
            Unmanaged<CourseIndexCancellationProbe>.fromOpaque(cancellationContext).release()
        }
        guard execute("BEGIN DEFERRED", in: database) else { return [:] }
        defer { _ = execute("COMMIT", in: database) }

        let itemMappings = items.compactMap { item -> (item: StudyItem, itemID: String, storageID: String)? in
            guard item.url != nil else { return nil }
            return (item, item.id, Self.storageID(for: item.id))
        }
        let itemByStorageID = Dictionary(
            uniqueKeysWithValues: itemMappings.map { ($0.storageID, $0.item) }
        )
        schedulingLock.lock()
        let expectedSignatures = expectedSignaturesByStorageID
        schedulingLock.unlock()
        let states = fileStates(in: database)
        let validStates = itemMappings.reduce(into: [String: FileState]()) { result, mapping in
            guard let signature = expectedSignatures[mapping.storageID],
                  let state = states[mapping.storageID],
                  state.signature == signature else { return }
            result[mapping.storageID] = state
        }
        var rankedByStorageID: [String: [RankedChunk]] = [:]
        var liveValidStorageIDs: Set<String> = []
        var checkedStorageIDs: Set<String> = []
        var staleItemsByStorageID: [String: StudyItem] = [:]
        let terms = Array(CourseSearchQuery.terms(in: query).prefix(32))
        if !terms.isEmpty,
           let statement = prepare(
               """
               WITH matches AS (
                   SELECT item_id, sort_order, text, bm25(chunks) AS rank
                   FROM chunks
                   WHERE terms MATCH ?
               ), ranked AS (
                   SELECT item_id, sort_order, text, rank,
                       ROW_NUMBER() OVER (PARTITION BY item_id ORDER BY rank) AS row_number
                   FROM matches
               )
               SELECT item_id, sort_order, text
               FROM ranked
               WHERE row_number <= 12
               ORDER BY rank
               LIMIT 6000
               """,
               in: database
           ) {
            defer { sqlite3_finalize(statement) }
            let expression = terms
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: " OR ")
            bind(expression, at: 1, in: statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard !cancellationProbe.isCancelled else { break }
                guard let storageID = columnText(statement, at: 0),
                      let item = itemByStorageID[storageID],
                      validStates[storageID] != nil,
                      let text = columnText(statement, at: 2),
                      !text.isEmpty else { continue }
                if checkedStorageIDs.insert(storageID).inserted {
                    if let currentSignature = Self.fileSignature(for: item),
                       currentSignature == expectedSignatures[storageID] {
                        liveValidStorageIDs.insert(storageID)
                    } else {
                        staleItemsByStorageID[storageID] = item
                    }
                }
                guard liveValidStorageIDs.contains(storageID) else { continue }
                var chunks = rankedByStorageID[storageID] ?? []
                guard chunks.count < 12 else { continue }
                chunks.append(
                    RankedChunk(
                        sortOrder: Int(sqlite3_column_int64(statement, 1)),
                        text: text
                    )
                )
                rankedByStorageID[storageID] = chunks
            }
        }
        for (storageID, item) in staleItemsByStorageID {
            if Self.fileSignature(for: item) != nil {
                schedule([item])
            } else {
                invalidate(storageID: storageID)
            }
        }

        let characterLimit = max(maximumCharactersPerItem, 1)
        return itemMappings.reduce(into: [String: CourseDocumentIndexResult]()) { result, mapping in
            let state = validStates[mapping.storageID]
            let chunks = (rankedByStorageID[mapping.storageID] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            let joined = chunks.map(\.text).joined(separator: "\n\n")
            result[mapping.itemID] = CourseDocumentIndexResult(
                text: joined.isEmpty ? nil : String(joined.prefix(characterLimit)),
                isTruncated: state?.isComplete != true
                    || state?.hasPartialExtraction == true
                    || (state?.chunkCount ?? 0) > chunks.count
                    || joined.count > characterLimit
            )
        }
    }

    struct FileMetadata {
        var modified: TimeInterval
        var size: UInt64
    }

    static func fileMetadata(for url: URL) -> FileMetadata? {
        let resolvedURL = url.resolvingSymlinksInPath()
        guard let values = try? resolvedURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
        ]), values.isRegularFile == true else { return nil }
        return FileMetadata(
            modified: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            size: UInt64(max(values.fileSize ?? 0, 0))
        )
    }

    static func fileSignature(for item: StudyItem) -> String? {
        guard let url = item.url, let metadata = fileMetadata(for: url) else { return nil }
        return "v5#\(item.kind.rawValue)#\(metadata.modified)#\(metadata.size)"
    }

    static func scheduledItem(_ item: StudyItem) -> ScheduledItem? {
        guard let url = item.url,
              let metadata = fileMetadata(for: url) else { return nil }
        guard item.kind == .pdf || metadata.size <= maximumTextSourceBytes else { return nil }
        return ScheduledItem(
            item: item,
            storageID: storageID(for: item.id),
            signature: "v5#\(item.kind.rawValue)#\(metadata.modified)#\(metadata.size)"
        )
    }

    static func storageID(for itemID: String) -> String {
        let digest = SHA256.hash(data: Data(itemID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

}
