import Foundation
import ImageIO
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

public struct MarkdownAttachment: Equatable {
    public var src: String
    public var alt: String

    public init(src: String, alt: String) {
        self.src = src
        self.alt = alt
    }
}

public enum MarkdownAttachmentStore {
    /// Decode/display bound shared by the reading paths (scheme handler, remote fetch).
    public static let maximumImageByteCount = 20 * 1_024 * 1_024
    public static let maximumDecodedPixelCount = 40_000_000
    /// Saving accepts far larger inputs: oversized still bitmaps are downscaled
    /// and re-encoded instead of being rejected (48 MP phone photos included).
    public static let saveMaximumImageByteCount = 200 * 1_024 * 1_024
    /// Animated images keep their original bytes, so only the file size is capped.
    public static let maximumAnimatedImageByteCount = 50 * 1_024 * 1_024
    /// Long edge applied when a stored still image exceeds the decode bounds.
    public static let downscaledImageLongEdge = 4096

    public static func attachmentError(code: Int, message: String) -> NSError {
        NSError(domain: "WeiBei.MarkdownAttachment", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    public static func save(
        dataURL: String,
        originalName: String,
        mime: String,
        attachmentDirectory: URL,
        markdownBaseURLString: String
    ) throws -> MarkdownAttachment {
        guard let commaIndex = dataURL.firstIndex(of: ",") else {
            throw attachmentError(code: 1, message: "图片数据缺少 data URL 头部")
        }

        let header = String(dataURL[..<commaIndex])
        let encodedSlice = dataURL[dataURL.index(after: commaIndex)...]
        let maximumBase64CharacterCount = ((saveMaximumImageByteCount + 2) / 3) * 4
        guard encodedSlice.utf8.count <= maximumBase64CharacterCount else {
            throw attachmentError(code: 3, message: "图片数据过大")
        }
        let encoded = String(encodedSlice)
        guard header.contains(";base64"),
              let data = Data(base64Encoded: encoded) else {
            throw attachmentError(code: 2, message: "图片数据不是有效的 base64")
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
        let stored = try prepareImageForStorage(data: data, suggestedMIMEType: mime)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        let ext = stored.fileExtension ?? fileExtension(originalName: originalName, mime: mime)
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

        try stored.data.write(to: target, options: [.atomic])
        return MarkdownAttachment(
            src: relativePath(to: target, markdownBaseURLString: markdownBaseURLString),
            alt: stem.replacingOccurrences(of: "-", with: " ")
        )
    }

    /// What actually lands in the attachments directory after admission.
    struct StoredImage {
        let data: Data
        let fileExtension: String?
    }

    /// Relaxed admission (N2): still bitmaps above the decode bounds are
    /// downscaled to a 4096 px long edge and re-encoded rather than rejected;
    /// animated images answer only for single-frame size and a 50 MB file cap;
    /// SVGs are rasterised to PNG so scripts never enter the notes; only
    /// corrupt, undecodable data fails. Decoding always goes through ImageIO
    /// (thumbnail interface) so huge inputs never materialise full bitmaps.
    static func prepareImageForStorage(data: Data, suggestedMIMEType: String?) throws -> StoredImage {
        if looksLikeSVG(data: data, suggestedMIMEType: suggestedMIMEType) {
            return try rasterizedSVG(data: data)
        }
        guard data.count <= saveMaximumImageByteCount else {
            throw attachmentError(code: 5, message: "图片文件过大")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let typeIdentifier = CGImageSourceGetType(source),
              let mimeType = UTType(typeIdentifier as String)?.preferredMIMEType,
              mimeType.hasPrefix("image/") else {
            throw attachmentError(code: 4, message: "图片文件已损坏或无法解码")
        }
        if CGImageSourceGetCount(source) > 1 {
            guard data.count <= maximumAnimatedImageByteCount else {
                throw attachmentError(code: 6, message: "动图文件超过 50 MB 上限")
            }
            guard largestFramePixelCount(source) <= maximumDecodedPixelCount else {
                throw attachmentError(code: 7, message: "动图单帧尺寸过大")
            }
            return StoredImage(data: data, fileExtension: nil)
        }
        let exceedsDecodeBounds = data.count > maximumImageByteCount
            || largestFramePixelCount(source) > maximumDecodedPixelCount
        guard exceedsDecodeBounds else {
            return StoredImage(data: data, fileExtension: nil)
        }
        guard let thumbnail = downscaledThumbnail(source) else {
            throw attachmentError(code: 4, message: "图片文件已损坏或无法解码")
        }
        // Photos re-encode as JPEG; anything else (screenshots, diagrams,
        // transparency) stays PNG, falling back to JPEG only if the PNG still
        // exceeds what the reading paths accept.
        let isPhoto = ["image/jpeg", "image/heic", "image/heif"].contains(mimeType)
        if !isPhoto,
           let png = encodedImage(thumbnail, typeIdentifier: UTType.png.identifier),
           png.count <= maximumImageByteCount {
            return StoredImage(data: png, fileExtension: "png")
        }
        if let jpeg = encodedImage(thumbnail, typeIdentifier: UTType.jpeg.identifier),
           jpeg.count <= maximumImageByteCount {
            return StoredImage(data: jpeg, fileExtension: "jpg")
        }
        throw attachmentError(code: 8, message: "图片过大，无法收纳")
    }

    static func looksLikeSVG(data: Data, suggestedMIMEType: String?) -> Bool {
        if suggestedMIMEType?.lowercased() == "image/svg+xml" { return true }
        let prefix = String(decoding: data.prefix(4_096), as: UTF8.self).lowercased()
        return prefix.contains("<svg")
    }

    /// Rasterises SVG artwork to PNG — no script-capable vector ever reaches disk.
    static func rasterizedSVG(data: Data) throws -> StoredImage {
        #if canImport(AppKit)
        let undecodable = attachmentError(code: 4, message: "SVG 图片无法解码")
        guard let image = NSImage(data: data),
              image.size.width > 0, image.size.height > 0 else { throw undecodable }
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw undecodable
        }
        let longEdge = max(cgImage.width, cgImage.height)
        if longEdge > downscaledImageLongEdge {
            guard let fitted = downscaledThumbnail(CGImageSourceCreateWithData(
                (encodedImage(cgImage, typeIdentifier: UTType.png.identifier) ?? Data()) as CFData,
                nil
            )) else { throw undecodable }
            guard let png = encodedImage(fitted, typeIdentifier: UTType.png.identifier) else { throw undecodable }
            return StoredImage(data: png, fileExtension: "png")
        }
        guard let png = encodedImage(cgImage, typeIdentifier: UTType.png.identifier) else { throw undecodable }
        return StoredImage(data: png, fileExtension: "png")
        #else
        throw attachmentError(code: 4, message: "此平台无法保存 SVG 图片")
        #endif
    }

    /// Largest single-frame pixel count; unreadable frame metadata is treated as
    /// unbounded so such files go through the downscale path (and fail there if
    /// they really are corrupt).
    static func largestFramePixelCount(_ source: CGImageSource) -> Int {
        var largest = 0
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
                return Int.max
            }
            let (framePixels, frameOverflow) = width.multipliedReportingOverflow(by: height)
            if frameOverflow { return Int.max }
            largest = max(largest, framePixels)
        }
        return largest
    }

    /// ImageIO thumbnail decode: memory stays proportional to the target size,
    /// never to the source resolution.
    static func downscaledThumbnail(_ source: CGImageSource?) -> CGImage? {
        guard let source else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: downscaledImageLongEdge,
        ] as [CFString: Any]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func encodedImage(_ image: CGImage, typeIdentifier: String) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            typeIdentifier as CFString,
            1,
            nil
        ) else { return nil }
        var properties: [CFString: Any] = [:]
        if typeIdentifier == UTType.jpeg.identifier {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.85
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
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
