import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct MarkdownAttachment: Equatable {
    public var src: String
    public var alt: String

    public init(src: String, alt: String) {
        self.src = src
        self.alt = alt
    }
}

public enum MarkdownAttachmentStore {
    public static let maximumImageByteCount = 20 * 1_024 * 1_024
    public static let maximumDecodedPixelCount = 40_000_000

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
        let encodedSlice = dataURL[dataURL.index(after: commaIndex)...]
        let maximumBase64CharacterCount = ((maximumImageByteCount + 2) / 3) * 4
        guard encodedSlice.utf8.count <= maximumBase64CharacterCount else {
            throw NSError(domain: "WeiBei.MarkdownAttachment", code: 3, userInfo: [NSLocalizedDescriptionKey: "图片超过 20 MB 上限"])
        }
        let encoded = String(encodedSlice)
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
        guard data.count <= maximumImageByteCount else {
            throw NSError(domain: "WeiBei.MarkdownAttachment", code: 3, userInfo: [NSLocalizedDescriptionKey: "图片超过 20 MB 上限"])
        }
        guard validatedImageMIMEType(
            data: data,
            suggestedMIMEType: mime,
            allowsSVG: false
        ) != nil else {
            throw NSError(domain: "WeiBei.MarkdownAttachment", code: 4, userInfo: [NSLocalizedDescriptionKey: "图片格式或尺寸无法安全读取"])
        }
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

    public static func validatedImageMIMEType(
        data: Data,
        suggestedMIMEType: String?,
        allowsSVG: Bool
    ) -> String? {
        guard data.count <= maximumImageByteCount else { return nil }
        let suggested = suggestedMIMEType?.lowercased()
        if allowsSVG, suggested == "image/svg+xml" {
            let prefix = String(decoding: data.prefix(4_096), as: UTF8.self)
                .lowercased()
            return prefix.contains("<svg") ? "image/svg+xml" : nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              decodedPixelsAreWithinLimit(
                  source,
                  maximumPixelCount: maximumDecodedPixelCount
              ) else {
            return nil
        }
        guard let type = CGImageSourceGetType(source),
              let mimeType = UTType(type as String)?.preferredMIMEType,
              mimeType.hasPrefix("image/") else {
            return nil
        }
        return mimeType
    }

    static func decodedPixelsAreWithinLimit(
        _ source: CGImageSource,
        maximumPixelCount: Int
    ) -> Bool {
        var totalPixels = 0
        for frameIndex in 0..<CGImageSourceGetCount(source) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                frameIndex,
                nil
            ) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0,
            height > 0 else {
                return false
            }
            let (framePixels, frameOverflow) = width.multipliedReportingOverflow(by: height)
            let (nextTotal, totalOverflow) = totalPixels.addingReportingOverflow(framePixels)
            guard !frameOverflow,
                  !totalOverflow,
                  nextTotal <= maximumPixelCount else {
                return false
            }
            totalPixels = nextTotal
        }
        return true
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
