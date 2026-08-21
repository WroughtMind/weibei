import Foundation

/// Kernel-side import copying for the course library.
///
/// Dedupe semantics: byte-identical content resolves to the existing library
/// file; a real conflict copies to a unique name. File sizes are compared
/// before any byte read and content comparison streams in 1 MB chunks, so a
/// multi-GB import never enters memory whole.
public enum ImportFileCopy {
    /// Maximum bytes read at once when comparing a suspected duplicate.
    static let comparisonChunkSize = 1 << 20

    public static func copyPreservingOriginal(from sourceURL: URL, into directory: URL) throws -> URL {
        let preferred = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: preferred.path) {
            if try filesHaveIdenticalContents(sourceURL, preferred) {
                return preferred
            }
            let unique = uniqueCopyURL(in: directory, preferred: preferred)
            try FileManager.default.copyItem(at: sourceURL, to: unique)
            return unique
        }
        try FileManager.default.copyItem(at: sourceURL, to: preferred)
        return preferred
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
