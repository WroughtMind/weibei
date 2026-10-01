import Foundation

public enum ImportFileCollision: Equatable, Sendable {
    case available
    case duplicate
    case conflict(suggestedFileName: String)
}

/// Kernel-side import copying for the course library.
///
/// Dedupe semantics: byte-identical content resolves to the existing library
/// file; a real conflict copies to a unique name. File sizes are compared
/// before any byte read; ordinary files compare in 1 MB chunks. HTML is prepared
/// in memory so its local dependencies can travel with the document.
public enum ImportFileCopy {
    /// Maximum bytes read at once when comparing a suspected duplicate.
    static let comparisonChunkSize = 1 << 20

    public static func copyPreservingOriginal(from sourceURL: URL, into directory: URL) throws -> URL {
        let html = try HTMLResourceImport.dataIfHTML(at: sourceURL)
        switch try collision(from: sourceURL, into: directory, preparedHTML: html) {
        case .available:
            break
        case .duplicate:
            return directory.appendingPathComponent(sourceURL.lastPathComponent)
        case .conflict(let suggestedFileName):
            let target = directory.appendingPathComponent(suggestedFileName)
            if let html {
                try html.write(to: target, options: .withoutOverwriting)
            } else {
                try FileManager.default.copyItem(at: sourceURL, to: target)
            }
            return target
        }
        let preferred = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if let html {
            try html.write(to: preferred, options: .withoutOverwriting)
            return preferred
        }
        try FileManager.default.copyItem(at: sourceURL, to: preferred)
        return preferred
    }

    /// Read-only counterpart of `copyPreservingOriginal`. The confirmation UI
    /// uses the same comparison and naming rules without creating directories
    /// or copying bytes before the user confirms.
    public static func collision(from sourceURL: URL, into directory: URL) throws -> ImportFileCollision {
        try collision(
            from: sourceURL,
            into: directory,
            preparedHTML: HTMLResourceImport.dataIfHTML(at: sourceURL)
        )
    }

    public static func sourcesHaveIdenticalImportedContents(
        _ lhs: URL,
        _ rhs: URL
    ) throws -> Bool {
        let lhsHTML = try HTMLResourceImport.dataIfHTML(at: lhs)
        let rhsHTML = try HTMLResourceImport.dataIfHTML(at: rhs)
        switch (lhsHTML, rhsHTML) {
        case let (.some(lhsData), .some(rhsData)):
            return lhsData == rhsData
        case (.none, .none):
            return try filesHaveIdenticalContents(lhs, rhs)
        default:
            return false
        }
    }

    /// Compare the bytes a source would import with an already imported file.
    /// Do not re-embed HTML resources relative to the copy's new directory.
    public static func sourceHasIdenticalImportedContents(
        _ sourceURL: URL,
        at importedURL: URL
    ) throws -> Bool {
        try importedContentsMatch(
            from: sourceURL,
            at: importedURL,
            preparedHTML: HTMLResourceImport.dataIfHTML(at: sourceURL)
        )
    }

    private static func collision(
        from sourceURL: URL,
        into directory: URL,
        preparedHTML: Data?
    ) throws -> ImportFileCollision {
        let preferred = directory.appendingPathComponent(sourceURL.lastPathComponent)
        guard FileManager.default.fileExists(atPath: preferred.path) else {
            return .available
        }
        if try importedContentsMatch(from: sourceURL, at: preferred, preparedHTML: preparedHTML) {
            return .duplicate
        }
        return .conflict(suggestedFileName: uniqueCopyURL(in: directory, preferred: preferred).lastPathComponent)
    }

    private static func importedContentsMatch(
        from sourceURL: URL,
        at importedURL: URL,
        preparedHTML: Data?
    ) throws -> Bool {
        if let html = preparedHTML {
            guard try importedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize == html.count else {
                return false
            }
            return try Data(contentsOf: importedURL) == html
        }
        return try filesHaveIdenticalContents(sourceURL, importedURL)
    }

    static func filesHaveIdenticalContents(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let lhsSize = try lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        let rhsSize = try rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard lhsSize == rhsSize else { return false }
        guard let lhsHandle = try? FileHandle(forReadingFrom: lhs),
              let rhsHandle = try? FileHandle(forReadingFrom: rhs) else {
            throw CocoaError(.fileReadUnknown)
        }
        defer {
            try? lhsHandle.close()
            try? rhsHandle.close()
        }
        while true {
            let lhsChunk = try lhsHandle.read(upToCount: comparisonChunkSize) ?? Data()
            let rhsChunk = try rhsHandle.read(upToCount: comparisonChunkSize) ?? Data()
            if lhsChunk != rhsChunk { return false }
            if lhsChunk.isEmpty { return true }
        }
    }

    static func uniqueCopyURL(in directory: URL, preferred: URL) -> URL {
        let stem = preferred.deletingPathExtension().lastPathComponent
        let ext = preferred.pathExtension
        var index = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
