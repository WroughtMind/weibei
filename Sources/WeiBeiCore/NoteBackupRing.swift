import Foundation

/// Silent per-note backup ring used before overwriting external Markdown.
///
/// Layout: `<root>/<sanitizedItemID>/<ISO8601 timestamp>.md`
/// Default root: `~/Library/Application Support/WeiBei/Backups`
///
/// Limits: keep the newest `maxBackupsPerNote` entries per note, and drop the
/// oldest entries across the whole ring until total size ≤ `maxTotalBytes`.
/// All writes use atomic replace so a crash never leaves a half-written backup.
public enum NoteBackupRing {
    public static let maxBackupsPerNote = 20
    public static let maxTotalBytes: Int64 = 50 * 1_024 * 1_024
    public static let subdirectoryName = "Backups"

    public struct Entry: Equatable, Sendable {
        public var url: URL
        public var itemID: String
        public var timestamp: Date
        public var byteCount: Int64

        public init(url: URL, itemID: String, timestamp: Date, byteCount: Int64) {
            self.url = url
            self.itemID = itemID
            self.timestamp = timestamp
            self.byteCount = byteCount
        }
    }

    public static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("WeiBei", isDirectory: true)
            .appendingPathComponent(subdirectoryName, isDirectory: true)
    }

    /// Copy the current on-disk file into the ring before overwriting it.
    /// Returns `nil` when the source is missing (nothing to protect).
    @discardableResult
    public static func capture(
        sourceURL: URL,
        itemID: String,
        rootURL: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> Entry? {
        let sanitizedID = sanitizeItemID(itemID)
        guard !sanitizedID.isEmpty else {
            throw error(code: 1, message: "备份环需要非空笔记 ID")
        }
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        let noteDirectory = rootURL.appendingPathComponent(sanitizedID, isDirectory: true)
        try fileManager.createDirectory(at: noteDirectory, withIntermediateDirectories: true)

        let fileName = backupFileName(for: now, existing: existingBackupURLs(in: noteDirectory, fileManager: fileManager))
        let targetURL = noteDirectory.appendingPathComponent(fileName)
        try data.write(to: targetURL, options: [.atomic])

        let entry = Entry(
            url: targetURL,
            itemID: sanitizedID,
            timestamp: now,
            byteCount: Int64(data.count)
        )
        try prune(rootURL: rootURL, fileManager: fileManager)
        return entry
    }

    /// Capture raw content (used when the caller already holds the bytes that will be replaced).
    @discardableResult
    public static func capture(
        content: Data,
        itemID: String,
        rootURL: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> Entry {
        let sanitizedID = sanitizeItemID(itemID)
        guard !sanitizedID.isEmpty else {
            throw error(code: 1, message: "备份环需要非空笔记 ID")
        }

        let noteDirectory = rootURL.appendingPathComponent(sanitizedID, isDirectory: true)
        try fileManager.createDirectory(at: noteDirectory, withIntermediateDirectories: true)

        let fileName = backupFileName(for: now, existing: existingBackupURLs(in: noteDirectory, fileManager: fileManager))
        let targetURL = noteDirectory.appendingPathComponent(fileName)
        try content.write(to: targetURL, options: [.atomic])

        let entry = Entry(
            url: targetURL,
            itemID: sanitizedID,
            timestamp: now,
            byteCount: Int64(content.count)
        )
        try prune(rootURL: rootURL, fileManager: fileManager)
        return entry
    }

    public static func list(
        itemID: String,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> [Entry] {
        let sanitizedID = sanitizeItemID(itemID)
        let noteDirectory = rootURL.appendingPathComponent(sanitizedID, isDirectory: true)
        guard fileManager.fileExists(atPath: noteDirectory.path) else {
            return []
        }
        return try entries(in: noteDirectory, itemID: sanitizedID, fileManager: fileManager)
            .sorted { $0.timestamp > $1.timestamp }
    }

    public static func listAll(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> [Entry] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }
        let noteDirs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var result: [Entry] = []
        for dir in noteDirs {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            let itemID = dir.lastPathComponent
            result.append(contentsOf: try entries(in: dir, itemID: itemID, fileManager: fileManager))
        }
        return result.sorted { $0.timestamp > $1.timestamp }
    }

    /// Drop oldest backups until per-note and total-size limits hold.
    public static func prune(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }

        var all = try listAll(rootURL: rootURL, fileManager: fileManager)
        // Per-note cap: keep newest N.
        var keptByNote: [String: [Entry]] = [:]
        for entry in all.sorted(by: { $0.timestamp > $1.timestamp }) {
            var list = keptByNote[entry.itemID] ?? []
            if list.count < maxBackupsPerNote {
                list.append(entry)
                keptByNote[entry.itemID] = list
            } else {
                try? fileManager.removeItem(at: entry.url)
            }
        }
        all = keptByNote.values.flatMap { $0 }.sorted { $0.timestamp > $1.timestamp }

        // Global size cap: drop oldest until under budget.
        var total = all.reduce(Int64(0)) { $0 + $1.byteCount }
        if total <= maxTotalBytes {
            removeEmptyNoteDirectories(rootURL: rootURL, fileManager: fileManager)
            return
        }
        for entry in all.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard total > maxTotalBytes else { break }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.byteCount
        }
        removeEmptyNoteDirectories(rootURL: rootURL, fileManager: fileManager)
    }

    // MARK: - Helpers

    public static func sanitizeItemID(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let collapsed = String(mapped)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        if collapsed.isEmpty {
            return "item"
        }
        return String(collapsed.prefix(120))
    }

    private static func backupFileName(for date: Date, existing: [URL]) -> String {
        let formatter = isoFormatter
        var base = formatter.string(from: date) + ".md"
        // ISO8601 may contain ":" which is fine on APFS; still avoid collisions within the same second.
        if !existing.contains(where: { $0.lastPathComponent == base }) {
            return base
        }
        var index = 2
        while true {
            let candidate = formatter.string(from: date) + "-\(index).md"
            if !existing.contains(where: { $0.lastPathComponent == candidate }) {
                return candidate
            }
            index += 1
        }
    }

    private static var isoFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func existingBackupURLs(in noteDirectory: URL, fileManager: FileManager) -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: noteDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func entries(
        in noteDirectory: URL,
        itemID: String,
        fileManager: FileManager
    ) throws -> [Entry] {
        let urls = try fileManager.contentsOfDirectory(
            at: noteDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls.compactMap { url -> Entry? in
            guard url.pathExtension.lowercased() == "md" else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let byteCount = Int64(values?.fileSize ?? 0)
            let timestamp = timestamp(fromFileName: url.lastPathComponent)
                ?? values?.contentModificationDate
                ?? Date.distantPast
            return Entry(url: url, itemID: itemID, timestamp: timestamp, byteCount: byteCount)
        }
    }

    private static func timestamp(fromFileName name: String) -> Date? {
        let stem = (name as NSString).deletingPathExtension
        // Strip optional "-N" collision suffix.
        let core = stem.replacingOccurrences(
            of: "-\\d+$",
            with: "",
            options: .regularExpression
        )
        return isoFormatter.date(from: core) ?? ISO8601DateFormatter().date(from: core)
    }

    private static func removeEmptyNoteDirectories(rootURL: URL, fileManager: FileManager) {
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        for dir in dirs {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            let remaining = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
            if remaining.isEmpty {
                try? fileManager.removeItem(at: dir)
            }
        }
    }

    private static func error(code: Int, message: String) -> NSError {
        NSError(
            domain: "WeiBei.NoteBackupRing",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
