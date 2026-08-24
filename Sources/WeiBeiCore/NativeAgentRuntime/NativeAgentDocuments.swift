import Foundation

public enum NativeDocumentFormat: String, Sendable {
    case html
    case markdown
    case svg
}

public struct NativeCreatedDocument: Equatable, Sendable {
    public var title: String
    public var format: NativeDocumentFormat
    public var fileURL: URL
    public var viewerURL: URL
    public var byteCount: Int
}

public enum NativeDocumentSandbox {
    public static let maximumBytes = 400_000

    public static func write(
        title: String,
        format: NativeDocumentFormat,
        content: String,
        documentsRoot: URL
    ) throws -> NativeCreatedDocument {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw NativeLLMFailure(code: "invalid_document", message: "create_document 需要标题")
        }
        guard content.utf8.count <= maximumBytes else {
            throw NativeLLMFailure(code: "invalid_document", message: "文稿超过 \(maximumBytes) 字节")
        }
        let workspaceRoot = documentsRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        do {
            try WeiBeiAgentDataPaths.ensureOwnedDirectory(
                documentsRoot,
                inside: workspaceRoot
            )
        } catch WeiBeiAgentDataPathError.outsideWorkspace {
            WeiBeiLog.workspace.error(
                "code=unsafe_agent_documents_directory"
            )
            throw NativeLLMFailure(
                code: "unsafe_agent_directory",
                message: "Agent 本地目录不安全，未生成文稿"
            )
        }
        let folder = documentsRoot.appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try WeiBeiAgentDataPaths.ensureOwnedDirectory(folder, inside: workspaceRoot)
        let ext: String
        switch format {
        case .html: ext = "html"
        case .markdown: ext = "md"
        case .svg: ext = "svg"
        }
        let stem = sanitize(trimmedTitle)
        let fileURL = folder.appendingPathComponent("\(stem).\(ext)")
        try Data(content.utf8).write(to: fileURL, options: .atomic)
        let viewerURL = folder.appendingPathComponent("viewer.html")
        try Data(viewerHTML(title: trimmedTitle, format: format, content: content).utf8)
            .write(to: viewerURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: viewerURL.path
        )
        return NativeCreatedDocument(
            title: trimmedTitle,
            format: format,
            fileURL: fileURL,
            viewerURL: viewerURL,
            byteCount: content.utf8.count
        )
    }

    public static func viewerHTML(title: String, format: NativeDocumentFormat, content: String) -> String {
        let escapedTitle = escape(title)
        let body: String
        switch format {
        case .html:
            body = content
        case .svg:
            body = content
        case .markdown:
            body = "<pre>\(escape(content))</pre>"
        }
        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
          <meta charset="utf-8">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'">
          <title>\(escapedTitle)</title>
          <style>
            html, body { margin: 0; padding: 16px; background: #f6f1e8; color: #1f1a14; font: 16px/1.5 ui-serif, Palatino, serif; }
          </style>
        </head>
        <body>
          <h1>\(escapedTitle)</h1>
          \(body)
        </body>
        </html>
        """
    }

    private static func sanitize(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let mapped = title.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let joined = String(mapped)
        return joined.isEmpty ? "document" : String(joined.prefix(40))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
