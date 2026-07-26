import AppKit
import CryptoKit
import Darwin
import Foundation
import PDFKit
import SQLite3

extension CourseDocumentSearchIndex {
    struct ScheduledItem {
        var item: StudyItem
        var storageID: String
        var signature: String
    }
    
    func schedule(_ scheduled: ScheduledItem) {
        let scheduleKey = "\(scheduled.storageID)#\(scheduled.signature)"
        schedulingLock.lock()
        let inserted = scheduledSignatures.insert(scheduleKey).inserted
        schedulingLock.unlock()
        guard inserted else { return }
    
        indexingQueue.async { [weak self] in
            guard let self else { return }
            if self.index(
                scheduled.item,
                storageID: scheduled.storageID,
                signature: scheduled.signature
            ) {
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
            }
        }
    }
    
    func clearScheduledSignature(_ signature: String) {
        schedulingLock.lock()
        scheduledSignatures.remove(signature)
        schedulingLock.unlock()
    }
    
    func invalidate(storageID: String) {
        schedulingLock.lock()
        expectedSignaturesByStorageID.removeValue(forKey: storageID)
        let validStorageIDs = Set(expectedSignaturesByStorageID.keys)
        schedulingLock.unlock()
        indexingQueue.async { [weak self] in
            self?.pruneMissingItems(validStorageIDs: validStorageIDs)
        }
    }
    
    func refreshChangedItemsForLookup(_ items: [StudyItem]) {
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
    
        let persistedStates: [String: FileState]
        if let database = openDatabase() {
            persistedStates = fileStates(in: database)
            sqlite3_close(database)
        } else {
            persistedStates = [:]
        }
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
    
    func index(
        _ item: StudyItem,
        storageID: String,
        signature: String,
        maximumNativePDFPages: Int? = nil,
        maximumNativePDFSeconds: TimeInterval? = nil
    ) -> Bool {
        guard let itemLock = acquireItemIndexLock(for: storageID) else { return false }
        defer { itemLock.unlock() }
        guard isExpected(signature: signature, for: storageID),
              let database = openDatabase(),
              let url = item.url else { return false }
        defer { sqlite3_close(database) }
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
            return indexPDFTextLayer(
                item: item,
                storageID: storageID,
                url: url,
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
    
    func acquireItemIndexLock(for storageID: String) -> NSLock? {
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
    
    func indexTextFile(
        item: StudyItem,
        storageID: String,
        signature: String,
        in database: OpaquePointer
    ) {
        guard let text = CourseDocumentExtractor.text(for: item) else { return }
        var indexedAllChunks = true
        var indexedChunkCount = 0
        _ = withWriteTransaction(in: database) {
            guard isExpected(signature: signature, for: storageID) else { return false }
            guard deleteIndexedContent(for: storageID, in: database) else { return false }
            var start = text.startIndex
            while start < text.endIndex {
                guard !Task.isCancelled else { return false }
                guard isExpected(signature: signature, for: storageID) else { return false }
                guard hasDatabaseCapacity() else {
                    indexedAllChunks = false
                    break
                }
                let end = text.index(start, offsetBy: 2_000, limitedBy: text.endIndex) ?? text.endIndex
                let chunk = String(text[start..<end])
                guard insertChunk(
                    itemID: storageID,
                    sortOrder: indexedChunkCount,
                    location: "",
                    text: chunk,
                    in: database
                ) else { return false }
                indexedChunkCount += 1
                start = end
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
    
    func indexPDFTextLayer(
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
        let pendingPageIndexes = (0..<nativePageLimit).filter { !nativeAttemptedPages.contains($0) }
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
                   CourseDocumentExtractor.hasMeaningfulText(extraction.text) {
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
    
    func finishPDFOCR(item: StudyItem, storageID: String, signature: String) {
        guard let itemLock = acquireItemIndexLock(for: storageID) else { return }
        defer { itemLock.unlock() }
        guard isExpected(signature: signature, for: storageID),
              Self.fileSignature(for: item) == signature,
              let database = openDatabase(),
              let url = item.url,
              let document = PDFDocument(url: url),
              fileState(for: storageID, in: database)?.signature == signature else { return }
        defer { sqlite3_close(database) }
        let pageCount = max(document.pageCount, 0)
        var processedPages = processedPageIndexes(for: storageID, in: database)
        let nativeAttemptedPages = nativeAttemptedPageIndexes(for: storageID, in: database)
        let pagesToOCR = nativeAttemptedPages.subtracting(processedPages).sorted()
        for pageIndex in pagesToOCR {
            guard hasDatabaseCapacity() else { return }
            guard isExpected(signature: signature, for: storageID),
                  Self.fileSignature(for: item) == signature,
                  fileState(for: storageID, in: database)?.signature == signature else { return }
            let pageText: String
            let extractionKind: String
            switch PDFOCRTextExtractor.pageOutcome(from: document, pageIndex: pageIndex) {
            case let .text(page):
                let rawText = page.text
                pageText = String(rawText.prefix(Self.maximumPDFPageCharacters))
                extractionKind = rawText.count > pageText.count ? "ocr-partial" : "ocr"
            case .empty:
                pageText = ""
                extractionKind = "empty"
            case .failed:
                pageText = ""
                extractionKind = "failed"
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
    
    func hasPendingNativePDFPages(
        item: StudyItem,
        storageID: String,
        signature: String
    ) -> Bool {
        guard isExpected(signature: signature, for: storageID),
              Self.fileSignature(for: item) == signature,
              hasDatabaseCapacity(),
              let database = openDatabase() else { return false }
        defer { sqlite3_close(database) }
        guard let state = fileState(for: storageID, in: database),
              state.signature == signature,
              !state.isComplete,
              let pageCount = storedPageCount(for: storageID, in: database),
              pageCount > 0 else { return false }
        let resolvedPages = nativeAttemptedPageIndexes(for: storageID, in: database)
            .union(processedPageIndexes(for: storageID, in: database))
        return resolvedPages.count < pageCount
    }
    
    func replacePDFPage(
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
}
