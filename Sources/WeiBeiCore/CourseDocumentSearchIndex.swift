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
    public var rank: Double?
    public var availability: CourseDocumentIndexAvailability
    public var nextCursor: String?
    public var sourceRevision: String?
    public var indexedPageCount: Int?
    public var totalPageCount: Int?
    public var uncoveredPageIndexes: [Int]
    public var failedPageIndexes: [Int]
    public var failedPageReasons: [Int: String]

    public init(
        text: String?,
        isTruncated: Bool,
        rank: Double? = nil,
        availability: CourseDocumentIndexAvailability = .ready,
        nextCursor: String? = nil,
        sourceRevision: String? = nil,
        indexedPageCount: Int? = nil,
        totalPageCount: Int? = nil,
        uncoveredPageIndexes: [Int] = [],
        failedPageIndexes: [Int] = [],
        failedPageReasons: [Int: String] = [:]
    ) {
        self.text = text
        self.isTruncated = isTruncated
        self.rank = rank
        self.availability = availability
        self.nextCursor = nextCursor
        self.sourceRevision = sourceRevision
        self.indexedPageCount = indexedPageCount
        self.totalPageCount = totalPageCount
        self.uncoveredPageIndexes = uncoveredPageIndexes
        self.failedPageIndexes = failedPageIndexes
        self.failedPageReasons = failedPageReasons
    }
}

public enum CourseDocumentIndexAvailability: Sendable, Equatable {
    case ready
    case indexing
    case unavailable
}

public typealias CourseNativePDFTextLoader = @Sendable (
    _ url: URL,
    _ pageIndexes: [Int],
    _ maximumCharactersPerPage: Int,
    _ timeout: TimeInterval
) -> [Int: BoundedPDFTextPage]?

public typealias CoursePDFOCRPageLoader = (
    _ document: PDFDocument,
    _ pageIndex: Int
) -> PDFOCRPageOutcome

public final class CourseDocumentSearchIndex: @unchecked Sendable {
    private struct ReadCursor: Codable {
        var version = 1
        var itemID: String
        var sourceRevision: String
        var location: String?
        var sortOrder: Int
        var characterOffset: Int
    }

    private static let maximumDatabaseBytes: UInt64 = 1_024 * 1_024 * 1_024
    private static let maximumSQLiteBytes: UInt64 = 768 * 1_024 * 1_024
    private static let sqlitePageBytes: UInt64 = 4_096
    private static let minimumWriteReserveBytes: UInt64 = 1 * 1_024 * 1_024
    private static let maximumImmediateRefreshItems = 24
    private static let maximumImmediateRefreshSeconds: TimeInterval = 4
    private static let maximumInitialIndexWaitSeconds: TimeInterval = 4
    private static let maximumTextSourceBytes: UInt64 = 32 * 1_024 * 1_024
    private static let maximumForegroundPDFPages = 32
    private static let maximumNativePDFPagesPerWorker = 8
    private static let maximumPDFPageCharacters = 128_000
    private static let foregroundPDFTextBudget: TimeInterval = 2
    private static let backgroundPDFTextBudget: TimeInterval = 20
    private struct FileState {
        var signature: String
        var isComplete: Bool
        var chunkCount: Int
        var hasPartialExtraction: Bool
    }

    private struct PDFIndexStatus {
        var pageCount: Int
        var indexedPageIndexes: Set<Int> = []
        var failedPageIndexes: Set<Int> = []
        var failedPageReasons: [Int: String] = [:]

        var uncoveredPageIndexes: [Int] {
            guard pageCount > 0 else { return [] }
            return Set(0..<pageCount).subtracting(indexedPageIndexes).sorted()
        }
    }

    private struct RankedChunk {
        var sortOrder: Int
        var text: String
        var rank: Double
    }

    private struct TextSection {
        var location: String
        var heading: String?
        var text: String
    }

    private final class VerifiedRegularFile {
        let descriptor: Int32
        let metadata: FileMetadata

        init?(item: StudyItem) {
            guard let url = item.url else { return nil }
            let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard descriptor >= 0 else { return nil }
            var fileStat = Darwin.stat()
            guard Darwin.fstat(descriptor, &fileStat) == 0,
                  (fileStat.st_mode & S_IFMT) == S_IFREG else {
                Darwin.close(descriptor)
                return nil
            }
            let identity = ImportedFileIdentity(
                volumeID: UInt64(fileStat.st_dev),
                fileID: UInt64(fileStat.st_ino),
                birthTimeSeconds: Int64(fileStat.st_birthtimespec.tv_sec),
                birthTimeNanoseconds: Int64(fileStat.st_birthtimespec.tv_nsec)
            )
            if let expectedIdentity = item.importedFileIdentity {
                // identity 只用于找回、永不用于拒绝（计划 §5 阶段5）：不符时
                // 降级为日志照常索引——fd 已先开、读取后 isStillCurrent 复验，
                // TOCTOU 保护不依赖 identity 相等。
                if identity != expectedIdentity {
                    WeiBeiLog.workspace.notice("search_index_identity_refreshed")
                }
            } else {
                switch item.storage {
                case .courseOwned:
                    Darwin.close(descriptor)
                    return nil
                case .common, .bundledSample:
                    break
                }
            }
            self.descriptor = descriptor
            self.metadata = FileMetadata(fileStat)
        }

        deinit {
            Darwin.close(descriptor)
        }

        func readData(afterOpen: (() -> Void)?) -> Data? {
            afterOpen?()
            guard Darwin.lseek(descriptor, 0, SEEK_SET) >= 0 else { return nil }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            guard let data = try? handle.readToEnd(),
                  metadata.isStillCurrent(descriptor),
                  UInt64(data.count) == metadata.size else {
                return nil
            }
            return data
        }
    }

    private let databaseURL: URL
    private let nativePDFTextLoader: CourseNativePDFTextLoader
    private let pdfOCRPageLoader: CoursePDFOCRPageLoader
    private let verifiedFileDidOpen: (@Sendable () -> Void)?
    private let indexingQueue = DispatchQueue(
        label: "com.changfenhuang.weibei.course-index",
        qos: .utility
    )
    private let metadataQueue = DispatchQueue(
        label: "com.changfenhuang.weibei.course-index.metadata",
        qos: .utility
    )
    private let ocrQueue = DispatchQueue(
        label: "com.changfenhuang.weibei.course-index.ocr",
        qos: .background
    )
    private let schedulingLock = NSLock()
    private let databaseWriteLock = NSLock()
    private let databaseCondition = NSCondition()
    private var persistentDatabase: OpaquePointer?
    private var databaseLeaseCount = 0
    private var isDatabaseInvalidated = false
    private let itemIndexLockRegistryLock = NSLock()
    private var scheduledSignatures: Set<String> = []
    private var initialIndexCompletions: [String: DispatchGroup] = [:]
    private var expectedSignaturesByStorageID: [String: String] = [:]
    private var itemIndexLocks: [String: NSLock] = [:]
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(
        databaseURL: URL,
        verifiedFileDidOpen: (@Sendable () -> Void)? = nil,
        nativePDFTextLoader: @escaping CourseNativePDFTextLoader = { url, pageIndexes, maximumCharacters, timeout in
            BoundedPDFTextExtractor.pages(
                from: url,
                pageIndexes: pageIndexes,
                maximumCharactersPerPage: maximumCharacters,
                timeout: timeout
            )
        },
        pdfOCRPageLoader: @escaping CoursePDFOCRPageLoader = { document, pageIndex in
            PDFOCRTextExtractor.pageOutcome(from: document, pageIndex: pageIndex)
        }
    ) {
        self.databaseURL = databaseURL
        self.verifiedFileDidOpen = verifiedFileDidOpen
        self.nativePDFTextLoader = nativePDFTextLoader
        self.pdfOCRPageLoader = pdfOCRPageLoader
        try? FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: databaseURL.deletingLastPathComponent().path
        )
        try? FileManager.default.removeItem(
            at: databaseURL.deletingLastPathComponent()
                .appendingPathComponent("ReadSnapshots", isDirectory: true)
        )
        guard let database = borrowDatabase() else { return }
        defer { returnDatabase() }
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
            "UPDATE processed_pages SET extraction_kind = 'ocr-failed-unknown' WHERE extraction_kind = 'failed'",
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

    deinit {
        databaseCondition.lock()
        isDatabaseInvalidated = true
        while databaseLeaseCount > 0 {
            databaseCondition.wait()
        }
        if let database = persistentDatabase {
            sqlite3_close_v2(database)
            persistentDatabase = nil
        }
        databaseCondition.unlock()
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

    @discardableResult
    public func retryFailedPDFPages(in item: StudyItem) -> Bool {
        guard item.kind == .pdf,
              let scheduled = Self.scheduledItem(item),
              let itemLock = acquireItemIndexLock(for: scheduled.storageID) else { return false }
        defer { itemLock.unlock() }
        guard isExpected(signature: scheduled.signature, for: scheduled.storageID),
              Self.fileSignature(for: item) == scheduled.signature,
              let database = borrowDatabase() else { return false }
        defer { returnDatabase() }
        let reset = withWriteTransaction(in: database) {
            resetFailedPDFPages(
                itemID: scheduled.storageID,
                expectedSignature: scheduled.signature,
                in: database
            )
        }
        if reset { schedule(scheduled) }
        return reset
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

    public func verifiedSnapshot(
        of item: StudyItem,
        maximumBytes: UInt64
    ) -> URL? {
        guard let file = VerifiedRegularFile(item: item),
              file.metadata.size > 0,
              file.metadata.size <= maximumBytes else {
            return nil
        }
        return temporarySnapshot(of: file)
    }

    public func lookup(
        items: [StudyItem],
        query: String,
        maximumCharactersPerItem: Int = 24_000
    ) -> [String: CourseDocumentIndexResult] {
        let scheduledItems = items.compactMap(Self.scheduledItem)
        refreshChangedItemsForLookup(items)
        waitForInitialIndexing(scheduledItems)
        guard !Task.isCancelled else { return [:] }
        guard let database = borrowDatabase() else { return [:] }
        defer { returnDatabase() }
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
        let activeScheduleKeys = scheduledSignatures
        schedulingLock.unlock()
        let states = fileStates(in: database)
        let pdfStatuses = pdfIndexStatuses(in: database)
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
        let terms = Array(Self.searchTerms(in: query).prefix(32))
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
               SELECT item_id, sort_order, text, rank
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
                        text: text,
                        rank: sqlite3_column_double(statement, 3)
                    )
                )
                rankedByStorageID[storageID] = chunks
            }
        }
        for mapping in itemMappings {
            guard validStates[mapping.storageID] != nil else { continue }
            if Self.fileSignature(for: mapping.item) == expectedSignatures[mapping.storageID] {
                liveValidStorageIDs.insert(mapping.storageID)
                staleItemsByStorageID.removeValue(forKey: mapping.storageID)
            } else {
                liveValidStorageIDs.remove(mapping.storageID)
                staleItemsByStorageID[mapping.storageID] = mapping.item
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
            let state = liveValidStorageIDs.contains(mapping.storageID)
                ? validStates[mapping.storageID]
                : nil
            let chunks = state == nil
                ? []
                : (rankedByStorageID[mapping.storageID] ?? []).sorted { $0.sortOrder < $1.sortOrder }
            let joined = chunks.map(\.text).joined(separator: "\n\n")
            let expectedSignature = expectedSignatures[mapping.storageID]
            let scheduleKey = expectedSignature.map {
                "\(mapping.storageID)#\($0)"
            }
            let pdfStatus = state == nil ? nil : pdfStatuses[mapping.storageID]
            let availability: CourseDocumentIndexAvailability
            if state?.isComplete == true {
                availability = .ready
            } else if scheduleKey.map(activeScheduleKeys.contains) == true {
                availability = .indexing
            } else {
                availability = .unavailable
            }
            result[mapping.itemID] = CourseDocumentIndexResult(
                text: joined.isEmpty ? nil : String(joined.prefix(characterLimit)),
                isTruncated: state?.isComplete != true
                    || state?.hasPartialExtraction == true
                    || (state?.chunkCount ?? 0) > chunks.count
                    || joined.count > characterLimit,
                rank: chunks.map(\.rank).min(),
                availability: availability,
                sourceRevision: state == nil ? nil : expectedSignature,
                indexedPageCount: pdfStatus?.indexedPageIndexes.count,
                totalPageCount: pdfStatus?.pageCount,
                uncoveredPageIndexes: pdfStatus?.uncoveredPageIndexes ?? [],
                failedPageIndexes: pdfStatus?.failedPageIndexes.sorted() ?? [],
                failedPageReasons: pdfStatus?.failedPageReasons ?? [:]
            )
        }
    }

    public func read(
        item: StudyItem,
        query: String,
        location: String?,
        cursor: String? = nil,
        maximumCharacters: Int = 24_000
    ) -> CourseDocumentIndexResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = rawLocation?.isEmpty == false ? rawLocation : nil
        if !trimmedQuery.isEmpty, trimmedLocation?.isEmpty ?? true {
            guard cursor == nil else {
                return CourseDocumentIndexResult(
                    text: nil,
                    isTruncated: false,
                    availability: .unavailable
                )
            }
            return lookup(
                items: [item],
                query: trimmedQuery,
                maximumCharactersPerItem: maximumCharacters
            )[item.id] ?? CourseDocumentIndexResult(
                text: nil,
                isTruncated: false,
                availability: .unavailable
            )
        }

        guard let scheduled = Self.scheduledItem(item) else {
            return CourseDocumentIndexResult(
                text: nil,
                isTruncated: false,
                availability: .unavailable
            )
        }
        refreshChangedItemsForLookup([item])
        waitForInitialIndexing([scheduled])
        guard !Task.isCancelled,
              let database = borrowDatabase() else {
            return CourseDocumentIndexResult(
                text: nil,
                isTruncated: false,
                availability: .unavailable
            )
        }
        defer { returnDatabase() }
        schedulingLock.lock()
        let expectedSignature = expectedSignaturesByStorageID[scheduled.storageID]
        let isScheduled = scheduledSignatures.contains(
            "\(scheduled.storageID)#\(scheduled.signature)"
        )
        schedulingLock.unlock()
        guard expectedSignature == scheduled.signature,
              Self.fileSignature(for: item) == scheduled.signature,
              let state = fileState(for: scheduled.storageID, in: database),
              state.signature == scheduled.signature else {
            return CourseDocumentIndexResult(
                text: nil,
                isTruncated: false,
                availability: isScheduled ? .indexing : .unavailable
            )
        }

        let decodedCursor = cursor.flatMap(Self.decodeCursor)
        if cursor != nil,
           decodedCursor.map({
               $0.version == 1
                   && $0.itemID == scheduled.storageID
                   && $0.sourceRevision == scheduled.signature
                   && $0.location == trimmedLocation
                   && $0.sortOrder >= 0
                   && $0.characterOffset >= 0
           }) != true {
            return CourseDocumentIndexResult(
                text: nil,
                isTruncated: false,
                availability: .unavailable,
                sourceRevision: scheduled.signature
            )
        }

        let hasLocation = trimmedLocation != nil
        let sql = hasLocation
            ? """
              SELECT sort_order, location, text
              FROM chunks
              WHERE item_id = ? AND (location = ? OR instr(location, ?) > 0)
                AND sort_order >= ?
              ORDER BY sort_order
              """
            : """
              SELECT sort_order, location, text
              FROM chunks
              WHERE item_id = ? AND sort_order >= ?
              ORDER BY sort_order
              """
        guard let statement = prepare(sql, in: database) else {
            return CourseDocumentIndexResult(
                text: nil,
                isTruncated: false,
                availability: .unavailable
            )
        }
        defer { sqlite3_finalize(statement) }
        bind(scheduled.storageID, at: 1, in: statement)
        if hasLocation, let trimmedLocation {
            bind(trimmedLocation, at: 2, in: statement)
            bind(trimmedLocation, at: 3, in: statement)
            sqlite3_bind_int64(
                statement,
                4,
                sqlite3_int64(decodedCursor?.sortOrder ?? 0)
            )
        } else {
            sqlite3_bind_int64(
                statement,
                2,
                sqlite3_int64(decodedCursor?.sortOrder ?? 0)
            )
        }

        let characterLimit = max(maximumCharacters, 1)
        var output = ""
        var nextCursor: String?
        while !Task.isCancelled, sqlite3_step(statement) == SQLITE_ROW {
            let sortOrder = Int(sqlite3_column_int64(statement, 0))
            guard let text = columnText(statement, at: 2), !text.isEmpty else { continue }
            let chunkLocation = columnText(statement, at: 1) ?? ""
            let chunk = chunkLocation.isEmpty || text.hasPrefix(chunkLocation)
                ? text
                : "\(chunkLocation)\n\(text)"
            let offset = decodedCursor?.sortOrder == sortOrder
                ? decodedCursor?.characterOffset ?? 0
                : 0
            guard offset <= chunk.count else {
                return CourseDocumentIndexResult(
                    text: nil,
                    isTruncated: false,
                    availability: .unavailable,
                    sourceRevision: scheduled.signature
                )
            }
            let separator = output.isEmpty ? "" : "\n\n"
            let remaining = characterLimit - output.count
            guard remaining > separator.count else {
                nextCursor = Self.encodeCursor(
                    itemID: scheduled.storageID,
                    sourceRevision: scheduled.signature,
                    location: trimmedLocation,
                    sortOrder: sortOrder,
                    characterOffset: offset
                )
                break
            }
            output += separator
            let unread = chunk.dropFirst(offset)
            let consumed = min(unread.count, characterLimit - output.count)
            output += unread.prefix(consumed)
            if consumed < unread.count {
                nextCursor = Self.encodeCursor(
                    itemID: scheduled.storageID,
                    sourceRevision: scheduled.signature,
                    location: trimmedLocation,
                    sortOrder: sortOrder,
                    characterOffset: offset + consumed
                )
                break
            }
        }
        let pdfStatus = pdfIndexStatus(for: scheduled.storageID, in: database)
        return CourseDocumentIndexResult(
            text: output.isEmpty ? nil : output,
            isTruncated: state.isComplete != true
                || state.hasPartialExtraction
                || nextCursor != nil,
            availability: state.isComplete
                ? .ready
                : (isScheduled ? .indexing : .unavailable),
            nextCursor: nextCursor,
            sourceRevision: scheduled.signature,
            indexedPageCount: pdfStatus?.indexedPageIndexes.count,
            totalPageCount: pdfStatus?.pageCount,
            uncoveredPageIndexes: pdfStatus?.uncoveredPageIndexes ?? [],
            failedPageIndexes: pdfStatus?.failedPageIndexes.sorted() ?? [],
            failedPageReasons: pdfStatus?.failedPageReasons ?? [:]
        )
    }

    public func outline(
        item: StudyItem,
        maximumEntries: Int = 24
    ) -> [String] {
        guard maximumEntries > 0,
              let scheduled = Self.scheduledItem(item) else { return [] }
        refreshChangedItemsForLookup([item])
        waitForInitialIndexing([scheduled])
        guard !Task.isCancelled,
              let database = borrowDatabase() else { return [] }
        defer { returnDatabase() }
        schedulingLock.lock()
        let expectedSignature = expectedSignaturesByStorageID[scheduled.storageID]
        schedulingLock.unlock()
        guard expectedSignature == scheduled.signature,
              Self.fileSignature(for: item) == scheduled.signature,
              fileState(for: scheduled.storageID, in: database)?.signature
                == scheduled.signature,
              let statement = prepare(
                  """
                  SELECT location
                  FROM chunks
                  WHERE item_id = ? AND location <> ''
                  GROUP BY location
                  ORDER BY MIN(sort_order)
                  LIMIT ?
                  """,
                  in: database
              ) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(scheduled.storageID, at: 1, in: statement)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(min(maximumEntries, 80)))
        var entries: [String] = []
        while !Task.isCancelled, sqlite3_step(statement) == SQLITE_ROW {
            guard let value = columnText(statement, at: 0), !value.isEmpty else { continue }
            entries.append(String(value.prefix(300)))
        }
        return entries
    }

    private static func encodeCursor(
        itemID: String,
        sourceRevision: String,
        location: String?,
        sortOrder: Int,
        characterOffset: Int
    ) -> String? {
        try? JSONEncoder().encode(
            ReadCursor(
                itemID: itemID,
                sourceRevision: sourceRevision,
                location: location,
                sortOrder: sortOrder,
                characterOffset: characterOffset
            )
        ).base64EncodedString()
    }

    private static func decodeCursor(_ value: String) -> ReadCursor? {
        guard value.utf8.count <= 1_024,
              let data = Data(base64Encoded: value) else { return nil }
        return try? JSONDecoder().decode(ReadCursor.self, from: data)
    }

    private struct ScheduledItem {
        var item: StudyItem
        var storageID: String
        var signature: String
    }

    private func schedule(_ scheduled: ScheduledItem) {
        let scheduleKey = "\(scheduled.storageID)#\(scheduled.signature)"
        schedulingLock.lock()
        let inserted = scheduledSignatures.insert(scheduleKey).inserted
        if inserted {
            let completion = DispatchGroup()
            completion.enter()
            initialIndexCompletions[scheduleKey] = completion
        }
        schedulingLock.unlock()
        guard inserted else { return }

        indexingQueue.async { [weak self] in
            guard let self else { return }
            let needsBackgroundCompletion = self.index(
                scheduled.item,
                storageID: scheduled.storageID,
                signature: scheduled.signature
            )
            if needsBackgroundCompletion {
                self.finishInitialIndexing(scheduleKey)
                self.ocrQueue.async { [weak self] in
                    guard let self else { return }
                    self.finishPDFOCR(
                        item: scheduled.item,
                        storageID: scheduled.storageID,
                        signature: scheduled.signature
                    )
                    let needsAnotherNativePass = self.hasPendingNativePDFPages(
                        item: scheduled.item,
                        storageID: scheduled.storageID,
                        signature: scheduled.signature
                    )
                    self.clearScheduledSignature(scheduleKey)
                    if needsAnotherNativePass {
                        self.schedule(scheduled)
                    }
                }
            } else {
                self.clearScheduledSignature(scheduleKey)
                self.finishInitialIndexing(scheduleKey)
            }
        }
    }

    private func finishInitialIndexing(_ scheduleKey: String) {
        schedulingLock.lock()
        let completion = initialIndexCompletions.removeValue(forKey: scheduleKey)
        completion?.leave()
        schedulingLock.unlock()
    }

    private func clearScheduledSignature(_ signature: String) {
        schedulingLock.lock()
        scheduledSignatures.remove(signature)
        schedulingLock.unlock()
    }

    private func waitForInitialIndexing(_ items: [ScheduledItem]) {
        let deadline = Date().addingTimeInterval(Self.maximumInitialIndexWaitSeconds)
        for item in items {
            let scheduleKey = "\(item.storageID)#\(item.signature)"
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { return }
                schedulingLock.lock()
                let completion = initialIndexCompletions[scheduleKey]
                schedulingLock.unlock()
                guard let completion else { break }
                if completion.wait(timeout: .now() + min(0.05, remaining))
                    == .success {
                    break
                }
            }
        }
    }

    private func invalidate(storageID: String) {
        schedulingLock.lock()
        expectedSignaturesByStorageID.removeValue(forKey: storageID)
        let validStorageIDs = Set(expectedSignaturesByStorageID.keys)
        schedulingLock.unlock()
        indexingQueue.async { [weak self] in
            self?.pruneMissingItems(validStorageIDs: validStorageIDs)
        }
    }

    private func refreshChangedItemsForLookup(_ items: [StudyItem]) {
        let scheduledItems = items.compactMap(Self.scheduledItem)
        let requestedStorageIDs = Set(items.filter { $0.url != nil }.map { Self.storageID(for: $0.id) })
        let currentStorageIDs = Set(scheduledItems.map(\.storageID))
        schedulingLock.lock()
        for storageID in requestedStorageIDs.subtracting(currentStorageIDs) {
            expectedSignaturesByStorageID.removeValue(forKey: storageID)
        }
        for scheduled in scheduledItems {
            expectedSignaturesByStorageID[scheduled.storageID] = scheduled.signature
        }
        let validStorageIDs = Set(expectedSignaturesByStorageID.keys)
        schedulingLock.unlock()

        if requestedStorageIDs != currentStorageIDs {
            indexingQueue.async { [weak self] in
                self?.pruneMissingItems(validStorageIDs: validStorageIDs)
            }
        }

        let persistedStates = withDatabase { fileStates(in: $0) } ?? [:]
        var immediateRefreshCount = 0
        let immediateRefreshDeadline = Date().addingTimeInterval(Self.maximumImmediateRefreshSeconds)
        for scheduled in scheduledItems {
            guard !Task.isCancelled else { return }
            let state = persistedStates[scheduled.storageID]
            let shouldIndexImmediately: Bool
            if let state {
                shouldIndexImmediately = state.signature != scheduled.signature
            } else {
                shouldIndexImmediately = true
            }
            if shouldIndexImmediately,
               immediateRefreshCount < Self.maximumImmediateRefreshItems,
               immediateRefreshDeadline.timeIntervalSinceNow > 0 {
                immediateRefreshCount += 1
                let needsBackgroundCompletion = index(
                    scheduled.item,
                    storageID: scheduled.storageID,
                    signature: scheduled.signature,
                    maximumNativePDFPages: Self.maximumForegroundPDFPages,
                    maximumNativePDFSeconds: min(
                        Self.foregroundPDFTextBudget,
                        immediateRefreshDeadline.timeIntervalSinceNow
                    )
                )
                if needsBackgroundCompletion {
                    schedule(scheduled)
                }
            } else if shouldIndexImmediately
                        || state == nil
                        || (state?.isComplete == false && scheduled.item.kind == .pdf) {
                schedule(scheduled)
            }
        }
    }

    private func index(
        _ item: StudyItem,
        storageID: String,
        signature: String,
        maximumNativePDFPages: Int? = nil,
        maximumNativePDFSeconds: TimeInterval? = nil
    ) -> Bool {
        guard let itemLock = acquireItemIndexLock(for: storageID) else { return false }
        defer { itemLock.unlock() }
        guard isExpected(signature: signature, for: storageID),
              let database = borrowDatabase() else { return false }
        defer { returnDatabase() }
        if let state = fileState(for: storageID, in: database),
           state.signature == signature,
           state.isComplete {
            return false
        }
        if let state = fileState(for: storageID, in: database),
           state.signature == signature,
           !state.isComplete,
           item.kind != .pdf {
            return false
        }

        switch item.kind {
        case .pdf:
            guard let file = VerifiedRegularFile(item: item),
                  "v6#\(item.kind.rawValue)#\(file.metadata.modified)#\(file.metadata.size)"
                    == signature,
                  let snapshotURL = temporarySnapshot(of: file) else {
                return false
            }
            defer { try? FileManager.default.removeItem(at: snapshotURL) }
            return indexPDFTextLayer(
                item: item,
                storageID: storageID,
                url: snapshotURL,
                signature: signature,
                maximumPages: maximumNativePDFPages,
                maximumSeconds: maximumNativePDFSeconds,
                in: database
            )
        case .html, .markdown, .text:
            indexTextFile(item: item, storageID: storageID, signature: signature, in: database)
            return false
        }
    }

    private func acquireItemIndexLock(for storageID: String) -> NSLock? {
        itemIndexLockRegistryLock.lock()
        let lock: NSLock
        if let existing = itemIndexLocks[storageID] {
            lock = existing
        } else {
            lock = NSLock()
            itemIndexLocks[storageID] = lock
        }
        itemIndexLockRegistryLock.unlock()
        while !lock.try() {
            guard !Task.isCancelled else { return nil }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return lock
    }

    private func indexTextFile(
        item: StudyItem,
        storageID: String,
        signature: String,
        in database: OpaquePointer
    ) {
        guard let sections = textSections(for: item, expectedSignature: signature) else { return }
        var indexedAllChunks = true
        var indexedChunkCount = 0
        _ = withWriteTransaction(in: database) {
            guard isExpected(signature: signature, for: storageID) else { return false }
            guard deleteIndexedContent(for: storageID, in: database) else { return false }
            for section in sections {
                for body in Self.chunked(section.text, maximumCharacters: 2_000) {
                    guard !Task.isCancelled else { return false }
                    guard isExpected(signature: signature, for: storageID) else { return false }
                    guard hasDatabaseCapacity() else {
                        indexedAllChunks = false
                        break
                    }
                    let chunk = section.heading.map { "# \($0)\n\(body)" } ?? body
                    guard insertChunk(
                        itemID: storageID,
                        sortOrder: indexedChunkCount,
                        location: section.location,
                        text: chunk,
                        in: database
                    ) else { return false }
                    indexedChunkCount += 1
                }
                if !indexedAllChunks { break }
            }
            guard isExpected(signature: signature, for: storageID) else { return false }
            return replaceFileRecord(
                itemID: storageID,
                kind: item.kind,
                signature: signature,
                pageCount: 1,
                processedCount: indexedAllChunks ? 1 : 0,
                isComplete: indexedAllChunks,
                chunkCount: indexedChunkCount,
                in: database
            )
        }
    }

    private func indexPDFTextLayer(
        item: StudyItem,
        storageID: String,
        url: URL,
        signature: String,
        maximumPages: Int?,
        maximumSeconds: TimeInterval?,
        in database: OpaquePointer
    ) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        let pageCount = max(document.pageCount, 0)
        let existingState = fileState(for: storageID, in: database)
        if existingState?.signature != signature || storedPageCount(for: storageID, in: database) != pageCount {
            let reset = withWriteTransaction(in: database) {
                isExpected(signature: signature, for: storageID)
                    && deleteIndexedContent(for: storageID, in: database)
                    && replaceFileRecord(
                        itemID: storageID,
                        kind: item.kind,
                        signature: signature,
                        pageCount: pageCount,
                        processedCount: 0,
                        isComplete: pageCount == 0,
                        chunkCount: 0,
                        in: database
                    )
            }
            guard reset else { return false }
        }

        var processedPages = processedPageIndexes(for: storageID, in: database)
        var nativeAttemptedPages = nativeAttemptedPageIndexes(for: storageID, in: database)
        let nativePageLimit = min(pageCount, maximumPages.map { max($0, 0) } ?? pageCount)
        let extractionDeadline = Date().addingTimeInterval(
            maximumSeconds
                ?? (maximumPages == nil ? Self.backgroundPDFTextBudget : Self.foregroundPDFTextBudget)
        )
        let pendingPageIndexes = (0..<nativePageLimit).filter {
            !nativeAttemptedPages.contains($0)
        }
        var pendingBatches: [[Int]] = []
        var pendingOffset = 0
        while pendingOffset < pendingPageIndexes.count {
            let endOffset = min(
                pendingOffset + Self.maximumNativePDFPagesPerWorker,
                pendingPageIndexes.count
            )
            pendingBatches.append(Array(pendingPageIndexes[pendingOffset..<endOffset]))
            pendingOffset = endOffset
        }
        pendingBatches.reverse()
        while let batch = pendingBatches.popLast() {
            guard !Task.isCancelled else { return true }
            let remainingTime = extractionDeadline.timeIntervalSinceNow
            guard remainingTime > 0 else { break }
            guard isExpected(signature: signature, for: storageID),
                  Self.fileSignature(for: item) == signature else { return false }
            guard hasDatabaseCapacity() else { break }
            guard let extractions = nativePDFTextLoader(
                url,
                batch,
                Self.maximumPDFPageCharacters,
                remainingTime
            ) else {
                guard !Task.isCancelled else { return true }
                guard extractionDeadline.timeIntervalSinceNow > 0 else { break }
                if batch.count > 1 {
                    let midpoint = batch.count / 2
                    pendingBatches.append(Array(batch[midpoint...]))
                    pendingBatches.append(Array(batch[..<midpoint]))
                    continue
                }
                guard let pageIndex = batch.first else { continue }
                if markNativeAttempted(
                    itemID: storageID,
                    expectedSignature: signature,
                    pageIndex: pageIndex,
                    in: database
                ) {
                    nativeAttemptedPages.insert(pageIndex)
                }
                continue
            }
            guard !Task.isCancelled else { return true }
            for pageIndex in batch {
                guard isExpected(signature: signature, for: storageID),
                      Self.fileSignature(for: item) == signature else { return false }
                if let extraction = extractions[pageIndex],
                   Self.hasMeaningfulText(extraction.text) {
                    let extractionKind = extraction.isPartial ? "text-partial" : "text"
                    guard replacePDFPage(
                        itemID: storageID,
                        expectedSignature: signature,
                        pageIndex: pageIndex,
                        pageText: extraction.text,
                        extractionKind: extractionKind,
                        in: database
                    ) else { continue }
                    processedPages.insert(pageIndex)
                }
                guard markNativeAttempted(
                    itemID: storageID,
                    expectedSignature: signature,
                    pageIndex: pageIndex,
                    in: database
                ) else { continue }
                nativeAttemptedPages.insert(pageIndex)
            }
        }
        _ = updateFileProgress(
            itemID: storageID,
            expectedSignature: signature,
            processedCount: processedPages.count,
            isComplete: processedPages.count == pageCount,
            in: database
        )
        return processedPages.count < pageCount
    }

    private func finishPDFOCR(item: StudyItem, storageID: String, signature: String) {
        guard let itemLock = acquireItemIndexLock(for: storageID) else { return }
        defer { itemLock.unlock() }
        guard isExpected(signature: signature, for: storageID),
              Self.fileSignature(for: item) == signature,
              let file = VerifiedRegularFile(item: item),
              "v6#\(item.kind.rawValue)#\(file.metadata.modified)#\(file.metadata.size)"
                == signature,
              let snapshotURL = temporarySnapshot(of: file) else { return }
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        guard let database = borrowDatabase() else { return }
        defer { returnDatabase() }
        guard let document = PDFDocument(url: snapshotURL),
              fileState(for: storageID, in: database)?.signature == signature else { return }
        let pageCount = max(document.pageCount, 0)
        var processedPages = processedPageIndexes(for: storageID, in: database)
        let nativeAttemptedPages = nativeAttemptedPageIndexes(for: storageID, in: database)
        let pagesToOCR = nativeAttemptedPages
            .subtracting(processedPages)
            .sorted()
        for pageIndex in pagesToOCR {
            guard hasDatabaseCapacity() else { return }
            guard isExpected(signature: signature, for: storageID),
                  Self.fileSignature(for: item) == signature,
                  fileState(for: storageID, in: database)?.signature == signature else { return }
            let pageText: String
            let extractionKind: String
            switch pdfOCRPageLoader(document, pageIndex) {
            case let .text(page):
                let rawText = page.text
                pageText = String(rawText.prefix(Self.maximumPDFPageCharacters))
                extractionKind = rawText.count > pageText.count ? "ocr-partial" : "ocr"
            case .empty:
                pageText = ""
                extractionKind = "empty"
            case let .failed(_, reason):
                pageText = ""
                extractionKind = "ocr-failed-\(reason.rawValue)"
            }
            guard replacePDFPage(
                itemID: storageID,
                expectedSignature: signature,
                pageIndex: pageIndex,
                pageText: pageText,
                extractionKind: extractionKind,
                in: database
            ) else { continue }
            processedPages.insert(pageIndex)
            _ = updateFileProgress(
                itemID: storageID,
                expectedSignature: signature,
                processedCount: processedPages.count,
                isComplete: processedPages.count == pageCount,
                in: database
            )
        }
    }

    private func hasPendingNativePDFPages(
        item: StudyItem,
        storageID: String,
        signature: String
    ) -> Bool {
        guard isExpected(signature: signature, for: storageID),
              Self.fileSignature(for: item) == signature,
              hasDatabaseCapacity(),
              let database = borrowDatabase() else { return false }
        defer { returnDatabase() }
        guard let state = fileState(for: storageID, in: database),
              state.signature == signature else { return false }
        guard !state.isComplete,
              let pageCount = storedPageCount(for: storageID, in: database),
              pageCount > 0 else { return false }
        let resolvedPages = nativeAttemptedPageIndexes(for: storageID, in: database)
            .union(processedPageIndexes(for: storageID, in: database))
        return resolvedPages.count < pageCount
    }

    private func replacePDFPage(
        itemID: String,
        expectedSignature: String,
        pageIndex: Int,
        pageText: String,
        extractionKind: String,
        in database: OpaquePointer
    ) -> Bool {
        withWriteTransaction(in: database) {
            guard isExpected(signature: expectedSignature, for: itemID) else { return false }
            let pageRange = (pageIndex * 1_000)...(pageIndex * 1_000 + 999)
            guard deleteChunks(for: itemID, sortOrderRange: pageRange, in: database) else { return false }

            let marker = extractionKind.hasPrefix("ocr") ? "（OCR）" : ""
            let location = "第 \(pageIndex + 1) 页\(marker)"
            var start = pageText.startIndex
            var chunkIndex = 0
            while start < pageText.endIndex {
                guard !Task.isCancelled else { return false }
                let end = pageText.index(start, offsetBy: 1_900, limitedBy: pageText.endIndex)
                    ?? pageText.endIndex
                let chunk = String(pageText[start..<end])
                guard hasDatabaseCapacity(), insertChunk(
                    itemID: itemID,
                    sortOrder: pageIndex * 1_000 + chunkIndex,
                    location: location,
                    text: "\(location)\n\(chunk)",
                    in: database
                ) else { return false }
                chunkIndex += 1
                start = end
            }
            guard let statement = prepare(
                "INSERT OR REPLACE INTO processed_pages (item_id, page_index, extraction_kind) VALUES (?, ?, ?)",
                in: database
            ) else { return false }
            defer { sqlite3_finalize(statement) }
            bind(itemID, at: 1, in: statement)
            sqlite3_bind_int64(statement, 2, sqlite3_int64(pageIndex))
            bind(extractionKind, at: 3, in: statement)
            return sqlite3_step(statement) == SQLITE_DONE
        }
    }

    private func insertChunk(
        itemID: String,
        sortOrder: Int,
        location: String,
        text: String,
        in database: OpaquePointer
    ) -> Bool {
        guard let statement = prepare(
            "INSERT INTO chunks (item_id, sort_order, location, text, terms) VALUES (?, ?, ?, ?, ?)",
            in: database
        ) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(itemID, at: 1, in: statement)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(sortOrder))
        bind(location, at: 3, in: statement)
        bind(text, at: 4, in: statement)
        bind(Self.searchTerms(in: text).joined(separator: " "), at: 5, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { return false }
        let rowID = sqlite3_last_insert_rowid(database)
        guard let metadata = prepare(
            "INSERT INTO chunk_index (chunk_rowid, item_id, sort_order) VALUES (?, ?, ?)",
            in: database
        ) else { return false }
        defer { sqlite3_finalize(metadata) }
        sqlite3_bind_int64(metadata, 1, rowID)
        bind(itemID, at: 2, in: metadata)
        sqlite3_bind_int64(metadata, 3, sqlite3_int64(sortOrder))
        return sqlite3_step(metadata) == SQLITE_DONE
    }

    private func deleteIndexedContent(for itemID: String, in database: OpaquePointer) -> Bool {
        guard deleteChunks(for: itemID, sortOrderRange: nil, in: database) else { return false }
        for sql in [
            "DELETE FROM processed_pages WHERE item_id = ?",
            "DELETE FROM native_attempted_pages WHERE item_id = ?",
            "DELETE FROM files WHERE item_id = ?",
        ] {
            guard let statement = prepare(sql, in: database) else { return false }
            bind(itemID, at: 1, in: statement)
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard result == SQLITE_DONE else { return false }
        }
        return true
    }

    private func deleteChunks(
        for itemID: String,
        sortOrderRange: ClosedRange<Int>?,
        in database: OpaquePointer
    ) -> Bool {
        let predicate = sortOrderRange == nil
            ? "item_id = ?"
            : "item_id = ? AND sort_order BETWEEN ? AND ?"
        for sql in [
            "DELETE FROM chunks WHERE rowid IN (SELECT chunk_rowid FROM chunk_index WHERE \(predicate))",
            "DELETE FROM chunk_index WHERE \(predicate)",
        ] {
            guard let statement = prepare(sql, in: database) else { return false }
            bind(itemID, at: 1, in: statement)
            if let sortOrderRange {
                sqlite3_bind_int64(statement, 2, sqlite3_int64(sortOrderRange.lowerBound))
                sqlite3_bind_int64(statement, 3, sqlite3_int64(sortOrderRange.upperBound))
            }
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard result == SQLITE_DONE else { return false }
        }
        return true
    }

    private func replaceFileRecord(
        itemID: String,
        kind: StudyItemKind,
        signature: String,
        pageCount: Int,
        processedCount: Int,
        isComplete: Bool,
        chunkCount: Int,
        in database: OpaquePointer
    ) -> Bool {
        guard let statement = prepare(
            """
            INSERT OR REPLACE INTO files
                (item_id, signature, kind, page_count, processed_count, is_complete, chunk_count)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            in: database
        ) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(itemID, at: 1, in: statement)
        bind(signature, at: 2, in: statement)
        bind(kind.rawValue, at: 3, in: statement)
        sqlite3_bind_int64(statement, 4, sqlite3_int64(pageCount))
        sqlite3_bind_int64(statement, 5, sqlite3_int64(processedCount))
        sqlite3_bind_int(statement, 6, isComplete ? 1 : 0)
        sqlite3_bind_int64(statement, 7, sqlite3_int64(chunkCount))
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func updateFileProgress(
        itemID: String,
        expectedSignature: String,
        processedCount: Int,
        isComplete: Bool,
        in database: OpaquePointer
    ) -> Bool {
        databaseWriteLock.lock()
        defer { databaseWriteLock.unlock() }
        guard let statement = prepare(
            """
            UPDATE files
            SET processed_count = ?,
                is_complete = ?,
                chunk_count = CASE
                    WHEN ? = 1 THEN (SELECT COUNT(*) FROM chunk_index WHERE item_id = ?)
                    ELSE chunk_count
                END
            WHERE item_id = ? AND signature = ?
            """,
            in: database
        ) else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, sqlite3_int64(processedCount))
        sqlite3_bind_int(statement, 2, isComplete ? 1 : 0)
        sqlite3_bind_int(statement, 3, isComplete ? 1 : 0)
        bind(itemID, at: 4, in: statement)
        bind(itemID, at: 5, in: statement)
        bind(expectedSignature, at: 6, in: statement)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func withWriteTransaction(
        in database: OpaquePointer,
        _ body: () -> Bool
    ) -> Bool {
        databaseWriteLock.lock()
        defer { databaseWriteLock.unlock() }
        guard execute("BEGIN IMMEDIATE", in: database) else { return false }
        guard body() else {
            _ = execute("ROLLBACK", in: database)
            return false
        }
        guard execute("COMMIT", in: database) else {
            _ = execute("ROLLBACK", in: database)
            return false
        }
        return true
    }

    private func pruneMissingItems(validStorageIDs: Set<String>) {
        guard let database = borrowDatabase() else { return }
        defer { returnDatabase() }
        let staleIDs = persistedItemIDs(in: database).subtracting(validStorageIDs)
        guard !staleIDs.isEmpty else { return }
        let pruned = withWriteTransaction(in: database) {
            staleIDs.allSatisfy { deleteIndexedContent(for: $0, in: database) }
        }
        guard pruned else { return }
        databaseWriteLock.lock()
        _ = execute("PRAGMA wal_checkpoint(TRUNCATE)", in: database)
        if hasDatabaseCapacity(reserving: 16 * 1_024 * 1_024) {
            _ = execute("PRAGMA incremental_vacuum(2000)", in: database)
            _ = execute("PRAGMA wal_checkpoint(TRUNCATE)", in: database)
        }
        if hasDatabaseCapacity(reserving: 4 * 1_024 * 1_024) {
            _ = execute("INSERT INTO chunks(chunks, rank) VALUES('merge', 64)", in: database)
            _ = execute("PRAGMA wal_checkpoint(TRUNCATE)", in: database)
        }
        databaseWriteLock.unlock()
    }

    private func isExpected(signature: String, for storageID: String) -> Bool {
        schedulingLock.lock()
        defer { schedulingLock.unlock() }
        return expectedSignaturesByStorageID[storageID] == signature
    }

    private func pdfIndexStatus(for itemID: String, in database: OpaquePointer) -> PDFIndexStatus? {
        pdfIndexStatuses(in: database)[itemID]
    }

    private func pdfIndexStatuses(in database: OpaquePointer) -> [String: PDFIndexStatus] {
        guard let statement = prepare(
            """
            SELECT files.item_id, files.page_count,
                processed_pages.page_index, processed_pages.extraction_kind
            FROM files
            LEFT JOIN processed_pages ON processed_pages.item_id = files.item_id
            WHERE files.kind = 'pdf'
            """,
            in: database
        ) else { return [:] }
        defer { sqlite3_finalize(statement) }
        var statuses: [String: PDFIndexStatus] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let itemID = columnText(statement, at: 0) else { continue }
            var status = statuses[itemID]
                ?? PDFIndexStatus(pageCount: Int(sqlite3_column_int64(statement, 1)))
            if sqlite3_column_type(statement, 2) != SQLITE_NULL,
               let extractionKind = columnText(statement, at: 3) {
                let pageIndex = Int(sqlite3_column_int64(statement, 2))
                if extractionKind.hasPrefix("ocr-failed-") {
                    status.failedPageIndexes.insert(pageIndex)
                    status.failedPageReasons[pageIndex] = Self.pdfFailureReason(
                        in: extractionKind
                    ) ?? "unknown"
                } else if !extractionKind.hasSuffix("-partial") {
                    status.indexedPageIndexes.insert(pageIndex)
                }
            }
            statuses[itemID] = status
        }
        return statuses
    }

    private func processedPageIndexes(for itemID: String, in database: OpaquePointer) -> Set<Int> {
        guard let statement = prepare(
            "SELECT page_index FROM processed_pages WHERE item_id = ?",
            in: database
        ) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(itemID, at: 1, in: statement)
        var indexes: Set<Int> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            indexes.insert(Int(sqlite3_column_int64(statement, 0)))
        }
        return indexes
    }

    private func resetFailedPDFPages(
        itemID: String,
        expectedSignature: String,
        in database: OpaquePointer
    ) -> Bool {
        guard isExpected(signature: expectedSignature, for: itemID),
              fileState(for: itemID, in: database)?.signature == expectedSignature,
              let count = prepare(
                  "SELECT COUNT(*) FROM processed_pages WHERE item_id = ? AND extraction_kind LIKE 'ocr-failed-%'",
                  in: database
              ) else { return false }
        bind(itemID, at: 1, in: count)
        let hasFinalFailures = sqlite3_step(count) == SQLITE_ROW
            && sqlite3_column_int64(count, 0) > 0
        sqlite3_finalize(count)
        guard hasFinalFailures else { return false }
        for sql in [
            """
            DELETE FROM native_attempted_pages
            WHERE item_id = ? AND page_index IN (
                SELECT page_index FROM processed_pages
                WHERE item_id = ? AND extraction_kind LIKE 'ocr-failed-%'
            )
            """,
            "DELETE FROM processed_pages WHERE item_id = ? AND extraction_kind LIKE 'ocr-failed-%'",
        ] {
            guard let statement = prepare(sql, in: database) else { return false }
            bind(itemID, at: 1, in: statement)
            if sql.contains("SELECT page_index") { bind(itemID, at: 2, in: statement) }
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard result == SQLITE_DONE else { return false }
        }
        guard let progress = prepare(
            """
            UPDATE files
            SET processed_count = (
                    SELECT COUNT(*) FROM processed_pages WHERE item_id = ?
                ),
                is_complete = 0
            WHERE item_id = ? AND signature = ?
            """,
            in: database
        ) else { return false }
        defer { sqlite3_finalize(progress) }
        bind(itemID, at: 1, in: progress)
        bind(itemID, at: 2, in: progress)
        bind(expectedSignature, at: 3, in: progress)
        return sqlite3_step(progress) == SQLITE_DONE
    }

    private func nativeAttemptedPageIndexes(for itemID: String, in database: OpaquePointer) -> Set<Int> {
        guard let statement = prepare(
            "SELECT page_index FROM native_attempted_pages WHERE item_id = ?",
            in: database
        ) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(itemID, at: 1, in: statement)
        var indexes: Set<Int> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            indexes.insert(Int(sqlite3_column_int64(statement, 0)))
        }
        return indexes
    }

    private func markNativeAttempted(
        itemID: String,
        expectedSignature: String,
        pageIndex: Int,
        in database: OpaquePointer
    ) -> Bool {
        databaseWriteLock.lock()
        defer { databaseWriteLock.unlock() }
        guard isExpected(signature: expectedSignature, for: itemID),
              fileState(for: itemID, in: database)?.signature == expectedSignature,
              let statement = prepare(
                  "INSERT OR IGNORE INTO native_attempted_pages (item_id, page_index) VALUES (?, ?)",
                  in: database
              ) else { return false }
        defer { sqlite3_finalize(statement) }
        bind(itemID, at: 1, in: statement)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(pageIndex))
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func storedPageCount(for itemID: String, in database: OpaquePointer) -> Int? {
        guard let statement = prepare(
            "SELECT page_count FROM files WHERE item_id = ?",
            in: database
        ) else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(itemID, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func fileState(for itemID: String, in database: OpaquePointer) -> FileState? {
        guard let statement = prepare(
            """
            SELECT signature, is_complete, chunk_count,
                EXISTS(
                    SELECT 1 FROM processed_pages
                    WHERE processed_pages.item_id = files.item_id
                        AND (extraction_kind LIKE '%-partial' OR extraction_kind LIKE '%failed%')
                )
            FROM files
            WHERE item_id = ?
            """,
            in: database
        ) else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(itemID, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW,
              let signature = columnText(statement, at: 0) else { return nil }
        return FileState(
            signature: signature,
            isComplete: sqlite3_column_int(statement, 1) != 0,
            chunkCount: Int(sqlite3_column_int64(statement, 2)),
            hasPartialExtraction: sqlite3_column_int(statement, 3) != 0
        )
    }

    private func fileStates(in database: OpaquePointer) -> [String: FileState] {
        guard let statement = prepare(
            """
            SELECT item_id, signature, is_complete, chunk_count,
                EXISTS(
                    SELECT 1 FROM processed_pages
                    WHERE processed_pages.item_id = files.item_id
                        AND (extraction_kind LIKE '%-partial' OR extraction_kind LIKE '%failed%')
                )
            FROM files
            """,
            in: database
        ) else { return [:] }
        defer { sqlite3_finalize(statement) }
        var states: [String: FileState] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let itemID = columnText(statement, at: 0),
                  let signature = columnText(statement, at: 1) else { continue }
            states[itemID] = FileState(
                signature: signature,
                isComplete: sqlite3_column_int(statement, 2) != 0,
                chunkCount: Int(sqlite3_column_int64(statement, 3)),
                hasPartialExtraction: sqlite3_column_int(statement, 4) != 0
            )
        }
        return states
    }

    private func persistedItemIDs(in database: OpaquePointer) -> Set<String> {
        var itemIDs: Set<String> = []
        for table in ["files", "processed_pages", "native_attempted_pages", "chunk_index"] {
            guard let statement = prepare("SELECT DISTINCT item_id FROM \(table)", in: database) else {
                continue
            }
            while sqlite3_step(statement) == SQLITE_ROW {
                if let itemID = columnText(statement, at: 0) {
                    itemIDs.insert(itemID)
                }
            }
            sqlite3_finalize(statement)
        }
        return itemIDs
    }

    private func withDatabase<T>(_ body: (OpaquePointer) -> T) -> T? {
        guard let database = borrowDatabase() else { return nil }
        defer { returnDatabase() }
        return body(database)
    }

    private func borrowDatabase() -> OpaquePointer? {
        databaseCondition.lock()
        defer { databaseCondition.unlock() }
        guard !isDatabaseInvalidated else { return nil }
        if persistentDatabase == nil {
            persistentDatabase = openDatabase()
        }
        guard let database = persistentDatabase else { return nil }
        databaseLeaseCount += 1
        return database
    }

    private func returnDatabase() {
        databaseCondition.lock()
        databaseLeaseCount -= 1
        if databaseLeaseCount == 0 {
            databaseCondition.broadcast()
        }
        databaseCondition.unlock()
    }

    private func openDatabase() -> OpaquePointer? {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        sqlite3_busy_timeout(database, 2_000)
        let maximumPageCount = Int64(Self.maximumSQLiteBytes / Self.sqlitePageBytes)
        guard execute("PRAGMA page_size=4096", in: database),
              integerValue("PRAGMA page_size", in: database) == Int64(Self.sqlitePageBytes),
              execute("PRAGMA max_page_count=\(maximumPageCount)", in: database),
              integerValue("PRAGMA max_page_count", in: database) == maximumPageCount else {
            sqlite3_close(database)
            return nil
        }
        _ = execute("PRAGMA journal_size_limit=67108864", in: database)
        _ = execute("PRAGMA wal_autocheckpoint=256", in: database)
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ] where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return database
    }

    private func integerValue(_ sql: String, in database: OpaquePointer) -> Int64? {
        guard let statement = prepare(sql, in: database) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func hasDatabaseCapacity(
        reserving reserveBytes: UInt64 = CourseDocumentSearchIndex.minimumWriteReserveBytes
    ) -> Bool {
        let urls = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
        ]
        let bytes = urls.reduce(UInt64(0)) { total, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
                .uint64Value ?? 0
            return total + size
        }
        return bytes <= Self.maximumDatabaseBytes - min(reserveBytes, Self.maximumDatabaseBytes)
    }

    private func execute(_ sql: String, in database: OpaquePointer) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }

    private func prepare(_ sql: String, in database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        return statement
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, transientDestructor)
    }

    private func columnText(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private struct FileMetadata {
        var modified: TimeInterval
        var size: UInt64

        init(_ fileStat: Darwin.stat) {
            modified = TimeInterval(fileStat.st_mtimespec.tv_sec)
                + TimeInterval(fileStat.st_mtimespec.tv_nsec) / 1_000_000_000
            size = UInt64(max(fileStat.st_size, 0))
        }

        func isStillCurrent(_ descriptor: Int32) -> Bool {
            var fileStat = Darwin.stat()
            guard Darwin.fstat(descriptor, &fileStat) == 0 else { return false }
            let current = FileMetadata(fileStat)
            return current.modified == modified && current.size == size
        }
    }

    private func temporarySnapshot(of file: VerifiedRegularFile) -> URL? {
        let directory = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("ReadSnapshots", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            return nil
        }
        var template = Array(
            directory.appendingPathComponent("snapshot-XXXXXX").path.utf8CString
        )
        let outputDescriptor = template.withUnsafeMutableBufferPointer { buffer in
            Darwin.mkstemp(buffer.baseAddress)
        }
        guard outputDescriptor >= 0 else { return nil }
        let path = String(cString: template)
        let url = URL(fileURLWithPath: path)
        var succeeded = false
        defer {
            Darwin.close(outputDescriptor)
            if !succeeded {
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard Darwin.fchmod(outputDescriptor, 0o600) == 0,
              Darwin.lseek(file.descriptor, 0, SEEK_SET) >= 0 else {
            return nil
        }
        verifiedFileDidOpen?()
        guard fcopyfile(
            file.descriptor,
            outputDescriptor,
            nil,
            copyfile_flags_t(COPYFILE_DATA)
        ) == 0,
              file.metadata.isStillCurrent(file.descriptor) else {
            return nil
        }
        var outputStat = Darwin.stat()
        guard Darwin.fstat(outputDescriptor, &outputStat) == 0,
              UInt64(max(outputStat.st_size, 0)) == file.metadata.size else {
            return nil
        }
        succeeded = true
        return url
    }

    private static func fileSignature(for item: StudyItem) -> String? {
        guard let metadata = VerifiedRegularFile(item: item)?.metadata else { return nil }
        return "v6#\(item.kind.rawValue)#\(metadata.modified)#\(metadata.size)"
    }

    private static func scheduledItem(_ item: StudyItem) -> ScheduledItem? {
        guard item.url != nil,
              let metadata = VerifiedRegularFile(item: item)?.metadata else { return nil }
        guard item.kind == .pdf || metadata.size <= maximumTextSourceBytes else { return nil }
        return ScheduledItem(
            item: item,
            storageID: storageID(for: item.id),
            signature: "v6#\(item.kind.rawValue)#\(metadata.modified)#\(metadata.size)"
        )
    }

    private static func storageID(for itemID: String) -> String {
        let digest = SHA256.hash(data: Data(itemID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func textSections(
        for item: StudyItem,
        expectedSignature: String
    ) -> [TextSection]? {
        guard let file = VerifiedRegularFile(item: item),
              "v6#\(item.kind.rawValue)#\(file.metadata.modified)#\(file.metadata.size)"
                == expectedSignature,
              let data = file.readData(afterOpen: verifiedFileDidOpen) else {
            return nil
        }
        switch item.kind {
        case .html:
            return Self.htmlSections(in: data)
        case .markdown:
            return String(data: data, encoding: .utf8).map(Self.markdownSections)
        case .text:
            return String(data: data, encoding: .utf8).map {
                [TextSection(location: "", heading: nil, text: $0)]
            }
        case .pdf:
            return nil
        }
    }

    private static func htmlSections(in data: Data) -> [TextSection] {
        guard let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(
                  pattern: #"<h([1-4])\b[^>]*>(.*?)</h\1\s*>"#,
                  options: [.caseInsensitive, .dotMatchesLineSeparators]
              ) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)
        guard !matches.isEmpty else {
            let text = htmlPlainText(html)
            return text.isEmpty ? [] : [TextSection(location: "", heading: nil, text: text)]
        }
        var sections: [TextSection] = []
        if let first = matches.first, first.range.location > 0,
           let preambleRange = Range(
               NSRange(location: 0, length: first.range.location),
               in: html
           ) {
            let preamble = htmlPlainText(String(html[preambleRange]))
            if !preamble.isEmpty {
                sections.append(
                    TextSection(location: "", heading: nil, text: preamble)
                )
            }
        }
        var locationIDCounts: [String: Int] = [:]
        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges > 2,
                  let matchRange = Range(match.range(at: 2), in: html) else { continue }
            let title = htmlPlainText(String(html[matchRange]))
            if !title.isEmpty {
                let bodyStart = NSMaxRange(match.range)
                let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : range.length
                let body: String
                if bodyStart <= bodyEnd,
                   let bodyRange = Range(NSRange(location: bodyStart, length: bodyEnd - bodyStart), in: html) {
                    body = htmlPlainText(String(html[bodyRange]))
                } else {
                    body = ""
                }
                let baseLocationID = htmlSectionLocationID(title: title, body: body)
                let count = locationIDCounts[baseLocationID, default: 0] + 1
                locationIDCounts[baseLocationID] = count
                let locationID = count == 1 ? baseLocationID : "\(baseLocationID)-dup-\(count)"
                let heading = "[\(locationID)][html-heading-\(index)] \(title.prefix(300))"
                sections.append(
                    TextSection(
                        location: "\(locationID) html-heading-\(index) \(title.prefix(300))",
                        heading: heading,
                        text: body.isEmpty ? title : body
                    )
                )
            }
        }
        return sections
    }

    private static func markdownSections(in text: String) -> [TextSection] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [TextSection] = []
        var body: [String] = []
        var heading: String?
        var location = ""
        var ordinal = 0
        func appendSection() {
            let sectionText = body.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sectionText.isEmpty || heading != nil else { return }
            sections.append(
                TextSection(
                    location: location,
                    heading: heading,
                    text: sectionText
                )
            )
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(
                of: #"^#{1,6}\s+(.+?)\s*#*$"#,
                options: .regularExpression
            ) {
                appendSection()
                body.removeAll(keepingCapacity: true)
                let rawHeading = String(trimmed[range])
                let title = rawHeading
                    .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
                heading = String(title.prefix(300))
                location = "markdown-heading-\(ordinal) \(title.prefix(300))"
                ordinal += 1
            } else {
                body.append(line)
            }
        }
        appendSection()
        return sections
    }

    private static func htmlPlainText(_ fragment: String) -> String {
        let data = Data("<html><body>\(fragment)</body></html>".utf8)
        return (try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ))?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func htmlSectionLocationID(title: String, body: String) -> String {
        let source = "\(title)|\(body)".lowercased()
        let normalized = String(source.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }.map(String.init).joined().prefix(500))
        var hash: UInt32 = 2_166_136_261
        for byte in normalized.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "html-section-%08x", hash)
    }

    private static func hasMeaningfulText(_ text: String) -> Bool {
        text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.count >= 20
    }

    private static func pdfFailureReason(in extractionKind: String) -> String? {
        let prefix = "ocr-failed-"
        guard extractionKind.hasPrefix(prefix) else { return nil }
        return String(extractionKind.dropFirst(prefix.count))
    }

    private static func chunked(_ text: String, maximumCharacters: Int) -> [String] {
        guard text.count > maximumCharacters else { return text.isEmpty ? [] : [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maximumCharacters, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }

    private static func searchTerms(in text: String) -> [String] {
        let lower = text.lowercased()
        var terms = lower
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).inverted)
            .filter { $0.count >= 2 }
        var run = ""
        for scalar in lower.unicodeScalars {
            if (0x4E00...0x9FFF).contains(Int(scalar.value)) {
                run.unicodeScalars.append(scalar)
            } else if !run.isEmpty {
                appendChineseTerms(from: run, to: &terms)
                run = ""
            }
        }
        if !run.isEmpty { appendChineseTerms(from: run, to: &terms) }
        var seen: Set<String> = []
        return terms.filter { term in
            seen.insert(term).inserted
        }
    }

    public static func text(_ text: String, matchesAnyTermIn query: String) -> Bool {
        searchTerms(in: query).contains { text.localizedCaseInsensitiveContains($0) }
    }

    public static func readMarkdown(
        _ markdown: String,
        query: String,
        location: String?,
        cursor: String? = nil,
        sourceID: String = "markdown",
        maximumCharacters: Int = 24_000
    ) -> CourseDocumentIndexResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sections = markdownSections(in: markdown).filter { section in
            if !trimmedLocation.isEmpty {
                return section.location == trimmedLocation
                    || section.location.localizedCaseInsensitiveContains(trimmedLocation)
            }
            guard !trimmedQuery.isEmpty else { return true }
            return text(
                [section.heading, section.text].compactMap { $0 }.joined(separator: "\n"),
                matchesAnyTermIn: trimmedQuery
            )
        }
        let joined = sections.map { section in
            section.heading.map { "# \($0)\n\(section.text)" } ?? section.text
        }.joined(separator: "\n\n")
        let limit = max(maximumCharacters, 1)
        let sourceRevision = sourceRevision(forMarkdown: markdown)
        let scope = [trimmedQuery, trimmedLocation].joined(separator: "\u{1f}")
        let decodedCursor = cursor.flatMap(Self.decodeCursor)
        if cursor != nil,
           decodedCursor.map({
               $0.version == 1
                   && $0.itemID == sourceID
                   && $0.sourceRevision == sourceRevision
                   && $0.location == scope
                   && $0.sortOrder == 0
                   && $0.characterOffset >= 0
                   && $0.characterOffset <= joined.count
           }) != true {
            return CourseDocumentIndexResult(
                text: nil,
                isTruncated: false,
                availability: .unavailable,
                sourceRevision: sourceRevision
            )
        }
        let offset = decodedCursor?.characterOffset ?? 0
        let unread = joined.dropFirst(offset)
        let pageText = String(unread.prefix(limit))
        let nextOffset = offset + pageText.count
        let nextCursor = nextOffset < joined.count
            ? Self.encodeCursor(
                itemID: sourceID,
                sourceRevision: sourceRevision,
                location: scope,
                sortOrder: 0,
                characterOffset: nextOffset
            )
            : nil
        return CourseDocumentIndexResult(
            text: pageText.isEmpty ? nil : pageText,
            isTruncated: nextCursor != nil,
            nextCursor: nextCursor,
            sourceRevision: sourceRevision
        )
    }

    public static func sourceRevision(for item: StudyItem) -> String? {
        fileSignature(for: item)
    }

    public static func sourceRevision(forMarkdown markdown: String) -> String {
        SHA256.hash(data: Data(markdown.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func appendChineseTerms(from run: String, to terms: inout [String]) {
        if run.count <= 20 { terms.append(run) }
        let characters = Array(run)
        guard characters.count >= 2 else { return }
        for index in 0..<(characters.count - 1) {
            terms.append(String(characters[index...index + 1]))
        }
    }
}
