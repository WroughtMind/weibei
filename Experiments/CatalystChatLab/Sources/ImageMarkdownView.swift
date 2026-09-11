import UIKit
import ImageIO
import Litext
import MarkdownView

@MainActor
final class LabImages {
    static let shared = LabImages()
    static let didLoad = Notification.Name("org.weibei.CatalystChatLab.imageLoaded")
    private let images = NSCache<NSString, UIImage>()
    private let errors = NSCache<NSString, NSString>()
    private var loading: Set<String> = []
    private let loader: MarkdownImageSchemeHandler
    init(loader: MarkdownImageSchemeHandler = MarkdownImageSchemeHandler()) {
        self.loader = loader
        images.totalCostLimit = 32 * 1024 * 1024
        errors.countLimit = 128
    }
    func image(for source: String) -> UIImage? { images.object(forKey: source as NSString) }
    func error(for source: String) -> String? { errors.object(forKey: source as NSString).map(String.init) }
    func remove(_ source: String) { images.removeObject(forKey: source as NSString); errors.removeObject(forKey: source as NSString) }
    func load(_ source: String) {
        if image(for: source) != nil || error(for: source) != nil { return }
        guard loading.insert(source).inserted else { return }
        Task {
            do {
                let data: Data
                if source == "lab-image://landscape" {
                    guard let url = Bundle.main.url(forResource: "landscape", withExtension: "png") else { throw CocoaError(.fileNoSuchFile) }
                    data = try await Task.detached { try Data(contentsOf: url) }.value
                } else {
                    // Same bounded local-file, redirect and remote-address policy as the original editor.
                    let loader = self.loader
                    guard let loaded = await Task.detached(priority: .utility, operation: {
                        await withCheckedContinuation { continuation in
                            loader.loadImage(source: source) { continuation.resume(returning: $0) }
                        }
                    }).value else { throw CocoaError(.fileReadUnknown) }
                    data = loaded
                }
                struct Decoded: @unchecked Sendable { let image: CGImage }
                let decoded = try await Task.detached {
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 1600,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceShouldCacheImmediately: true
                          ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                    return Decoded(image: image)
                }.value
                images.setObject(UIImage(cgImage: decoded.image), forKey: source as NSString,
                                 cost: decoded.image.bytesPerRow * decoded.image.height)
            } catch { errors.setObject(error.localizedDescription as NSString, forKey: source as NSString) }
            loading.remove(source)
            NotificationCenter.default.post(name: Self.didLoad, object: self, userInfo: ["source": source])
        }
    }
    deinit { loader.invalidate() }
}

final class ImageMarkdownView: MarkdownTextView {
    var containsImages = false
    var images = LabImages.shared {
        didSet { if oldValue !== images { invalidateInlineDecoration() } }
    }
    var contentWidth: CGFloat = 680 {
        didSet { if containsImages && contentWidth != oldValue { invalidateInlineDecoration() } }
    }

    override func decorate(inlineText text: NSAttributedString, theme: MarkdownTheme) -> NSAttributedString {
        let pattern = "\u{E000}IMAGE:([^\u{E001}]+)\u{E001}|\\[\\[([^\\]]+)\\]\\]"
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text.string, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return text }
        let result = NSMutableAttributedString(string: "")
        var cursor = 0
        for match in matches {
            result.append(text.attributedSubstring(from: NSRange(location: cursor, length: match.range.location - cursor)))
            if match.range(at: 1).location != NSNotFound {
                let source = (text.string as NSString).substring(with: match.range(at: 1))
                result.append(imageAttachment(source: source))
            } else {
                let title = (text.string as NSString).substring(with: match.range(at: 2))
                result.append(NSAttributedString(string: title, attributes: [
                    .font: theme.fonts.body, .foregroundColor: theme.colors.highlight,
                    .link: URL(string: "weibei-note:" + (title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))!
                ]))
            }
            cursor = NSMaxRange(match.range)
        }
        result.append(text.attributedSubstring(from: NSRange(location: cursor, length: text.length - cursor)))
        return result
    }

    private func imageAttachment(source: String) -> NSAttributedString {
        let holder = ImageAttachment(source: source)
        let container = UIView()
        if let image = images.image(for: source) {
            let width = min(contentWidth, image.size.width)
            holder.size = CGSize(width: width, height: width * image.size.height / image.size.width)
            let view = UIImageView(image: image)
            view.frame = CGRect(origin: .zero, size: holder.size)
            view.contentMode = .scaleAspectFit
            view.isAccessibilityElement = true
            view.accessibilityLabel = "图片：" + source
            container.addSubview(view)
        } else {
            holder.size = CGSize(width: min(contentWidth, 500), height: 96)
            let status = UILabel(frame: CGRect(origin: .zero, size: holder.size))
            status.numberOfLines = 0
            status.font = .systemFont(ofSize: 14)
            status.textColor = .secondaryLabel
            status.text = images.error(for: source).map { "图片读取失败：" + $0 } ?? "图片准备中…"
            container.addSubview(status)
            images.load(source)
        }
        container.frame.size = holder.size
        holder.view = container
        return holder.attributedString()
    }
}

private final class ImageAttachment: TextLabel.Attachment {
    let source: String
    init(source: String) { self.source = source; super.init() }
    override func attributedStringRepresentation() -> NSAttributedString { NSAttributedString(string: "[图片：\(source)]") }
}
