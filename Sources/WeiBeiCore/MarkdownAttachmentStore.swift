import Foundation

public struct MarkdownAttachment: Equatable {
    public var src: String
    public var alt: String

    public init(src: String, alt: String) {
        self.src = src
        self.alt = alt
    }
}

public enum MarkdownAttachmentStore {
    public static func save(
        dataURL: String,
        originalName: String,
        mime: String,
        attachmentDirectory: URL,
        markdownBaseURLString: String
    ) throws -> MarkdownAttachment {
        guard let commaIndex = dataURL.firstIndex(of: ",") else {
            throw NSError(domain: "WeiBei.MarkdownAttachment", code: 1, userInfo: [NSLocalizedDescriptionKey: "图片数据缺少 data URL 头部"])
        }

        let header = String(dataURL[..<commaIndex])
        let encoded = String(dataURL[dataURL.index(after: commaIndex)...])
        guard header.contains(";base64"),
              let data = Data(base64Encoded: encoded) else {
            throw NSError(domain: "WeiBei.MarkdownAttachment", code: 2, userInfo: [NSLocalizedDescriptionKey: "图片数据不是有效的 base64"])
        }

        return try save(
            data: data,
            originalName: originalName,
            mime: mime,
            attachmentDirectory: attachmentDirectory,
            markdownBaseURLString: markdownBaseURLString
        )
    }

    public static func save(
        data: Data,
        originalName: String,
        mime: String,
        attachmentDirectory: URL,
        markdownBaseURLString: String
    ) throws -> MarkdownAttachment {
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        let ext = fileExtension(originalName: originalName, mime: mime)
        let rawStem = originalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "image"
            : URL(fileURLWithPath: originalName).deletingPathExtension().lastPathComponent
        let stem = safeFileStem(rawStem, fallback: "image", limit: 72)

        var target = attachmentDirectory.appendingPathComponent("\(stem).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = attachmentDirectory.appendingPathComponent("\(stem)-\(index).\(ext)")
            index += 1
        }

        try data.write(to: target, options: [.atomic])
        return MarkdownAttachment(
            src: relativePath(to: target, markdownBaseURLString: markdownBaseURLString),
            alt: stem.replacingOccurrences(of: "-", with: " ")
        )
    }

    public static func markdownImage(for attachment: MarkdownAttachment) -> String {
        let alt = attachment.alt
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let src = attachment.src
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: ")", with: "%29")
        return "![\(alt.isEmpty ? "image" : alt)](\(src))"
    }

    public static func safeFileStem(_ value: String, fallback: String = "未命名", limit: Int = 80) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = value.components(separatedBy: invalid)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let stem = parts.joined(separator: "-")
        return stem.isEmpty ? fallback : String(stem.prefix(limit))
    }

    public static func fileExtension(originalName: String, mime: String) -> String {
        let nameExt = URL(fileURLWithPath: originalName).pathExtension.lowercased()
        if isSupportedImageExtension(nameExt) {
            return nameExt
        }
        switch mime.lowercased() {
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/tiff": return "tiff"
        case "image/heic": return "heic"
        default: return "png"
        }
    }

    public static func isSupportedImageExtension(_ value: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "tif", "tiff", "heic"].contains(value.lowercased())
    }

    public static func mimeType(forFileExtension value: String) -> String {
        switch value.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "tif", "tiff": return "image/tiff"
        case "heic": return "image/heic"
        default: return "image/png"
        }
    }

    public static func relativePath(to target: URL, markdownBaseURLString: String) -> String {
        guard let baseURL = URL(string: markdownBaseURLString), baseURL.isFileURL else {
            return target.path
        }
        let basePath = baseURL.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        let prefix = basePath.hasSuffix("/") ? basePath : "\(basePath)/"
        if targetPath.hasPrefix(prefix) {
            return String(targetPath.dropFirst(prefix.count))
        }
        return target.path
    }
}

public enum MarkdownBlockInsertion {
    public static func insert(_ markdown: String, into text: String, replacing range: NSRange) -> (text: String, cursor: Int) {
        let nsText = text as NSString
        let location = max(0, min(range.location, nsText.length))
        let length = max(0, min(range.length, nsText.length - location))
        let before = nsText.substring(to: location)
        let after = nsText.substring(from: location + length)
        let body = markdown.trimmingCharacters(in: .whitespacesAndNewlines)

        var insertion = body
        if !before.isEmpty && !before.hasSuffix("\n\n") {
            insertion = "\(before.hasSuffix("\n") ? "\n" : "\n\n")\(insertion)"
        }
        if !after.isEmpty && !after.hasPrefix("\n\n") {
            insertion = "\(insertion)\(after.hasPrefix("\n") ? "\n" : "\n\n")"
        }

        return ("\(before)\(insertion)\(after)", location + (insertion as NSString).length)
    }
}
