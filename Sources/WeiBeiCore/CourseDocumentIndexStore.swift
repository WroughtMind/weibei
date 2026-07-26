import AppKit
import CryptoKit
import Darwin
import Foundation
import PDFKit
import SQLite3

extension CourseDocumentSearchIndex {
    func insertChunk(
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
        bind(CourseSearchQuery.terms(in: text).joined(separator: " "), at: 5, in: statement)
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
    
    func deleteIndexedContent(for itemID: String, in database: OpaquePointer) -> Bool {
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
    
    func deleteChunks(
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
    
    func replaceFileRecord(
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
    
    func updateFileProgress(
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
    
    func withWriteTransaction(
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
    
    func pruneMissingItems(validStorageIDs: Set<String>) {
        guard let database = openDatabase() else { return }
        defer { sqlite3_close(database) }
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
    
    func isExpected(signature: String, for storageID: String) -> Bool {
        schedulingLock.lock()
        defer { schedulingLock.unlock() }
        return expectedSignaturesByStorageID[storageID] == signature
    }
    
    func processedPageIndexes(for itemID: String, in database: OpaquePointer) -> Set<Int> {
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
    
    func nativeAttemptedPageIndexes(for itemID: String, in database: OpaquePointer) -> Set<Int> {
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
    
    func markNativeAttempted(
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
    
    func storedPageCount(for itemID: String, in database: OpaquePointer) -> Int? {
        guard let statement = prepare(
            "SELECT page_count FROM files WHERE item_id = ?",
            in: database
        ) else { return nil }
        defer { sqlite3_finalize(statement) }
        bind(itemID, at: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(statement, 0))
    }
    
    func fileState(for itemID: String, in database: OpaquePointer) -> FileState? {
        guard let statement = prepare(
            """
            SELECT signature, is_complete, chunk_count,
                EXISTS(
                    SELECT 1 FROM processed_pages
                    WHERE processed_pages.item_id = files.item_id
                        AND (extraction_kind LIKE '%-partial' OR extraction_kind = 'failed')
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
    
    func fileStates(in database: OpaquePointer) -> [String: FileState] {
        guard let statement = prepare(
            """
            SELECT item_id, signature, is_complete, chunk_count,
                EXISTS(
                    SELECT 1 FROM processed_pages
                    WHERE processed_pages.item_id = files.item_id
                        AND (extraction_kind LIKE '%-partial' OR extraction_kind = 'failed')
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
    
    func persistedItemIDs(in database: OpaquePointer) -> Set<String> {
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
    
    func openDatabase() -> OpaquePointer? {
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
    
    func integerValue(_ sql: String, in database: OpaquePointer) -> Int64? {
        guard let statement = prepare(sql, in: database) else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }
    
    func hasDatabaseCapacity(
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
    
    func execute(_ sql: String, in database: OpaquePointer) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }
    
    func prepare(_ sql: String, in database: OpaquePointer) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        return statement
    }
    
    func bind(_ value: String, at index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, transientDestructor)
    }
    
    func columnText(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }
}
