import Foundation

/// 磁盘上的一个附件候选，供孤儿回收纯函数判定。
public struct MarkdownAttachmentFile: Equatable, Sendable {
    public var url: URL
    public var relativePath: String
    public var timestamp: Date

    public init(url: URL, relativePath: String, timestamp: Date) {
        self.url = url
        self.relativePath = relativePath
        self.timestamp = timestamp
    }
}

/// 按 markdown 引用回收无引用附件。不碰 WorkspaceStore。
///
/// 规则：只删「全库 markdown 都未引用、且超过宽限期」的附件。
/// 宽限期按文件创建/修改时间的较新者计算，避免编辑中途刚保存的图被立刻收走。
public enum MarkdownAttachmentGC {
    public static let defaultGracePeriod: TimeInterval = 24 * 60 * 60
    public static let notebookAssetsDirectoryName = ".weibei-assets"
    public static let appOwnedAttachmentsDirectoryName = "Attachments"

    public static func referencedRelativePaths(inMarkdownBodies bodies: [String]) -> Set<String> {
        var result = Set<String>()
        for body in bodies {
            result.formUnion(referencedRelativePaths(in: body))
        }
        return result
    }

    public static func referencedRelativePaths(in markdown: String) -> Set<String> {
        var result = Set<String>()
        var searchStart = markdown.startIndex
        while searchStart < markdown.endIndex {
            guard let bang = markdown[searchStart...].range(of: "![") else { break }
            guard let altEnd = markdown[bang.upperBound...].range(of: "](") else {
                searchStart = bang.upperBound
                continue
            }
            var cursor = altEnd.upperBound
            while cursor < markdown.endIndex, markdown[cursor].isWhitespace {
                cursor = markdown.index(after: cursor)
            }
            guard cursor < markdown.endIndex else { break }

            let dest: String
            if markdown[cursor] == "<" {
                let innerStart = markdown.index(after: cursor)
                guard let gt = markdown[innerStart...].firstIndex(of: ">") else {
                    searchStart = bang.upperBound
                    continue
                }
                dest = String(markdown[innerStart..<gt])
            } else {
                let destStart = cursor
                while cursor < markdown.endIndex {
                    let ch = markdown[cursor]
                    if ch == ")" || ch.isWhitespace { break }
                    cursor = markdown.index(after: cursor)
                }
                dest = String(markdown[destStart..<cursor])
            }

            if let normalized = normalizedLocalAttachmentReference(dest) {
                result.insert(normalized)
            }
            searchStart = bang.upperBound
        }
        return result
    }

    public static func urlsEligibleForDeletion(
        files: [MarkdownAttachmentFile],
        referencedRelativePaths: Set<String>,
        now: Date,
        gracePeriod: TimeInterval = defaultGracePeriod
    ) -> [URL] {
        let refs = Set(referencedRelativePaths.flatMap { raw -> [String] in
            let path = normalizeReference(raw)
            guard !path.isEmpty else { return [] }
            return [path, normalizeReference((path as NSString).lastPathComponent)]
        })
        return files.compactMap { file in
            let path = normalizeReference(file.relativePath)
            let name = normalizeReference((file.relativePath as NSString).lastPathComponent)
            if refs.contains(path) || refs.contains(name) {
                return nil
            }
            guard now.timeIntervalSince(file.timestamp) >= gracePeriod else {
                return nil
            }
            return file.url
        }
    }

    static func normalizeReference(_ raw: String) -> String {
        let decoded = raw.removingPercentEncoding ?? raw
        var path = decoded.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path.lowercased()
    }

    private static func normalizedLocalAttachmentReference(_ dest: String) -> String? {
        let trimmed = dest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://")
            || lowered.hasPrefix("https://")
            || lowered.hasPrefix("data:") {
            return nil
        }
        let normalized = normalizeReference(trimmed)
        return normalized.isEmpty ? nil : normalized
    }
}
