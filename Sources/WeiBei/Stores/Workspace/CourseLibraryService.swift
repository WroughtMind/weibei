import Foundation

/// Performs recursive course-library discovery outside the observable store.
actor CourseLibraryService {
    private static let supportedExtensions = Set(["pdf", "html", "htm", "md", "markdown", "txt", "text"])
    private static let markdownExtensions = Set(["md", "markdown"])

    /**
     * Recursively discovers supported course files with stable ordering and deduplication.
     *
     * @param rootURLs - Files or directories chosen by the user
     * @param limit - Maximum number of files returned across all roots
     * @returns Supported regular files sorted by localized path
     */
    func supportedFiles(in rootURLs: [URL], limit: Int = 500) -> [URL] {
        var discovered: [URL] = []
        var seenPaths = Set<String>()
        for rootURL in rootURLs {
            for fileURL in Self.supportedFiles(at: rootURL, limit: max(0, limit - discovered.count)) {
                let path = fileURL.standardizedFileURL.path
                if seenPaths.insert(path).inserted {
                    discovered.append(fileURL)
                }
                if discovered.count == limit { break }
            }
            if discovered.count == limit { break }
        }
        return discovered.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /**
     * Returns whether a file is a Markdown notebook candidate.
     *
     * @param url - Candidate file location
     */
    nonisolated static func isMarkdownFile(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    /**
     * Applies the repository's conservative note-name heuristic.
     *
     * @param url - Markdown file location
     */
    nonisolated static func defaultsToNotebookNote(_ url: URL) -> Bool {
        let description = (url.deletingPathExtension().lastPathComponent + " "
            + url.deletingLastPathComponent().pathComponents.suffix(3).joined(separator: " ")).lowercased()
        return ["笔记", "note", "notes", "notebook"].contains { description.contains($0) }
    }

    private nonisolated static func supportedFiles(at url: URL, limit: Int) -> [URL] {
        guard limit > 0 else { return [] }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue {
            return supportedExtensions.contains(url.pathExtension.lowercased()) ? [url] : []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard supportedExtensions.contains(fileURL.pathExtension.lowercased()),
                  (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            files.append(fileURL)
            if files.count == limit { break }
        }
        return files
    }
}
