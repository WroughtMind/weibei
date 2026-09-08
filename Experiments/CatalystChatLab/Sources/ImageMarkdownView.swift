import UIKit
import ImageIO
import Litext
import MarkdownView

@MainActor
final class LabImages {
    static let shared = LabImages()
    static let didLoad = Notification.Name("org.weibei.CatalystChatLab.imageLoaded")
    var images: [String: UIImage] = [:]
    var errors: [String: String] = [:]
    private var loading: Set<String> = []
    func load(_ source: String) {
        if images[source] != nil || errors[source] != nil { return }
        guard loading.insert(source).inserted else { return }
        Task {
            do {
                let data: Data
                if source == "lab-image://landscape" {
                    guard let url = Bundle.main.url(forResource: "landscape", withExtension: "png") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    data = try await Task.detached { try Data(contentsOf: url) }.value
                } else {
                    guard let url = URL(string: source), url.scheme == "https" else { throw URLError(.unsupportedURL) }
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.httpShouldSetCookies = false
                    let session = URLSession(configuration: configuration)
                    defer { session.invalidateAndCancel() }
                    let (bytes, response) = try await session.data(from: url)
                    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                        throw URLError(.badServerResponse)
                    }
                    data = bytes
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
                images[source] = UIImage(cgImage: decoded.image)
            } catch { errors[source] = error.localizedDescription }
            loading.remove(source)
            NotificationCenter.default.post(name: Self.didLoad, object: source)
        }
    }
}

final class ImageMarkdownView: MarkdownTextView {
    var contentWidth: CGFloat = 680 {
        didSet { if contentWidth != oldValue { invalidateInlineDecoration() } }
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
                    .link: URL(string: "weibei-lab://notes")!
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
        if let image = LabImages.shared.images[source] {
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
            status.text = LabImages.shared.errors[source].map { "图片读取失败：" + $0 } ?? "图片准备中…"
            container.addSubview(status)
            LabImages.shared.load(source)
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
