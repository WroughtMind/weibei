import AppKit
import SwiftMath
import SwiftUI
import WeiBeiCore

enum NativeChatAttachmentReadingPosition {
    case table(row: Int, offset: CGFloat)
    case code(character: Int, offset: CGFloat)
    case content(offset: CGFloat)
}

/// Prepared resources belong to the attachment, not to a temporary provider view.
@MainActor
final class NativeChatTextAttachment: NSTextAttachment {
    typealias VisualizationView = (String, CGFloat, @escaping (CGFloat) -> Void) -> NSView?
    typealias ImageLoader = (String, @escaping (Data?) -> Void) -> Void
    private(set) var descriptor: NativeChatAttachmentDescriptor
    private(set) var fontSize: CGFloat
    private(set) var isDark: Bool
    private(set) var interfaceLanguage: WeiBeiInterfaceLanguage
    private var appearanceMode = WeiBeiNativePalette.current
    private let providers = NSHashTable<NativeChatAttachmentProvider>.weakObjects()
    let onOpenURL: (URL) -> Void
    let onSizeChange: () -> Void
    let onWillResize: () -> Void
    let visualizationView: VisualizationView?
    let imageLoader: ImageLoader?
    private(set) var preparationCount = 0
    fileprivate var revision = 0
    private var preparedRevision = -1
    private var preparationTask: Task<Void, Never>?
    private var notificationPending = false
    fileprivate var mathNaturalSize: NSSize?
    fileprivate var mathDrawing: MTMathListDisplay?
    fileprivate var mathError: String?
    fileprivate var codeStorage: NSTextStorage?
    fileprivate var codeSelection = NSRange(location: 0, length: 0)
    fileprivate var horizontalOffset: CGFloat = 0
    fileprivate var codeSize = NSSize(width: 240, height: 160)
    private var codeTokens: [NativeChatCodeHighlighter.Token]?
    fileprivate var codeError: String?
    private(set) var tableContent: NativeChatTableContent?
    fileprivate var picture: NSImage?
    fileprivate var imageFailed = false
    private var imageStarted = false
    private var imageGeneration = 0
    private var mathEstimate = NSSize(width: 24, height: 24)
    fileprivate weak var codeView: NativeChatTextView?
    // Dedicated interactive runtimes retain their live state for this message.
    // Plain text, formula views and table cell views are all recyclable.
    fileprivate var runtime: NSView?
    fileprivate var runtimeRevision = -1
    fileprivate var runtimeHeight: CGFloat = 160

    init(descriptor: NativeChatAttachmentDescriptor, fontSize: CGFloat, isDark: Bool,
         onOpenURL: @escaping (URL) -> Void, onSizeChange: @escaping () -> Void,
         onWillResize: @escaping () -> Void = {},
         visualizationView: VisualizationView? = nil, imageLoader: ImageLoader? = nil,
         interfaceLanguage: WeiBeiInterfaceLanguage = .chinese) {
        self.descriptor = descriptor
        self.fontSize = fontSize
        self.isDark = isDark
        self.interfaceLanguage = interfaceLanguage
        self.onOpenURL = onOpenURL
        self.onSizeChange = onSizeChange
        self.onWillResize = onWillResize
        self.visualizationView = visualizationView
        self.imageLoader = imageLoader
        super.init(data: nil, ofType: "com.weibei.chat-attachment")
        allowsTextAttachmentView = true
        updateMathEstimate()
    }
    required init?(coder: NSCoder) { nil }
    deinit { preparationTask?.cancel() }

    // This subclass supplies its own provider; there is no file-type registry entry.
    override var usesTextAttachmentView: Bool { allowsTextAttachmentView }

    override func image(for bounds: CGRect, attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation, textContainer: NSTextContainer?) -> NSImage? {
        // The native provider supplies the content, including during repeated drawing.
        // This attachment has no file representation for AppKit to draw underneath it.
        nil
    }

    func update(fontSize: CGFloat, isDark: Bool, interfaceLanguage: WeiBeiInterfaceLanguage? = nil) {
        update(descriptor: descriptor, fontSize: fontSize, isDark: isDark, interfaceLanguage: interfaceLanguage)
    }
    func update(descriptor: NativeChatAttachmentDescriptor) {
        update(descriptor: descriptor, fontSize: fontSize, isDark: isDark)
    }
    func update(descriptor: NativeChatAttachmentDescriptor, fontSize: CGFloat, isDark: Bool,
                interfaceLanguage: WeiBeiInterfaceLanguage? = nil) {
        let language = interfaceLanguage ?? self.interfaceLanguage
        let changedContent = self.descriptor != descriptor
        let changedFont = self.fontSize != fontSize
        let changedLanguage = language != self.interfaceLanguage
        guard language != self.interfaceLanguage || changedContent || changedFont || self.isDark != isDark
            || appearanceMode != WeiBeiNativePalette.current else { return }
        let previous = self.descriptor
        self.descriptor = descriptor
        self.fontSize = fontSize
        self.isDark = isDark
        self.interfaceLanguage = language
        appearanceMode = WeiBeiNativePalette.current
        revision &+= 1
        mathNaturalSize = nil
        mathDrawing = nil
        mathError = nil
        updateMathEstimate()
        if changedContent {
            if case let .code(old, _) = previous, case let .code(source, _) = descriptor, let storage = codeStorage {
                let edit = NativeChatMarkdownEdit.between(.init(runs: [.init(text: old)]), .init(runs: [.init(text: source)]))
                codeSelection = edit.mapSelection(codeSelection)
                storage.replaceCharacters(in: edit.range, with: edit.replacement.map(\.text).joined())
            }
            codeTokens = nil
            if case let .image(oldSource, _) = previous, case let .image(source, _) = descriptor, oldSource != source {
                imageGeneration &+= 1
                picture = nil; imageFailed = false; imageStarted = false
            }
        }
        if case let .code(_, oldLanguage) = previous, case let .code(_, newLanguage) = descriptor,
           (oldLanguage?.lowercased() == "mermaid") != (newLanguage?.lowercased() == "mermaid") {
            runtime = nil; codeStorage = nil
        }
        if case let .visualization(oldID) = previous, case let .visualization(newID) = descriptor, oldID != newID { runtime = nil }
        let tableLanguageChanged: Bool
        if case .table = descriptor { tableLanguageChanged = changedLanguage } else { tableLanguageChanged = false }
        if changedContent || changedFont || tableLanguageChanged { preparedRevision = -1 }
        else {
            preparedRevision = revision
            restyleCode()
            tableContent?.restyle(isDark: isDark, language: language)
        }
        if preparationCount > 0 || !providers.allObjects.isEmpty { prepare() }
        changed()
    }

    /// Called at presentation/preparation boundaries, never from attachmentBounds.
    func prepare() {
        switch descriptor {
        case let .math(latex, display):
            guard mathNaturalSize == nil else { return }
            let label = makeMathLabel(latex: latex, display: display)
            let size = label.intrinsicContentSize
            label.frame.size = NSSize(width: max(1, ceil(size.width)), height: max(1, ceil(size.height)))
            label.layout()
            mathNaturalSize = label.frame.size
            mathDrawing = label.displayList
            mathError = label.error?.localizedDescription
            preparationCount += 1
            changed()
        case let .image(source, _):
            guard !imageStarted, let imageLoader else { return }
            imageStarted = true
            let expected = imageGeneration
            imageLoader(source) { [weak self] data in
                guard let self, self.imageGeneration == expected, case let .image(current, _) = self.descriptor, current == source else { return }
                self.onWillResize()
                self.picture = data.flatMap(NSImage.init(data:)).flatMap { $0.size.width > 0 && $0.size.height > 0 ? $0 : nil }
                self.imageFailed = self.picture == nil
                self.preparationCount += 1
                self.changed()
            }
        case let .code(source, language) where language?.lowercased() != "mermaid":
            if codeStorage == nil { codeStorage = NSTextStorage(string: source); restyleCode() }
            prepareTextResource()
        case .table: prepareTextResource()
        default: break
        }
    }

    private func prepareTextResource() {
        guard preparationTask == nil, preparedRevision != revision else { return }
        let expected = revision, input = descriptor, size = fontSize, language = interfaceLanguage
        let tokens = codeTokens
        let priorTable = tableContent
        preparationTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                await NativeChatAttachmentPreparation.make(input, fontSize: size, language: language, codeTokens: tokens)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.preparationTask = nil
            guard self.revision == expected else { self.prepare(); return }
            self.preparedRevision = expected
            self.preparationCount += 1
            self.onWillResize()
            switch result {
            case let .code(tokens, natural, error):
                self.codeTokens = error == nil ? tokens : nil
                self.codeError = error
                self.codeSize = natural
                self.restyleCode()
            case let .table(documents, widths):
                self.tableContent = NativeChatTableContent(documents: documents, widths: widths,
                    fontSize: size, previous: priorTable)
            case .none: break
            }
            self.changed()
        }
    }

    private func restyleCode() {
        guard let storage = codeStorage else { return }
        NativeChatCodeHighlighter.apply(codeTokens ?? [], to: storage,
            font: .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular), isDark: isDark)
    }

    func changed() {
        guard !notificationPending else { return }
        notificationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.notificationPending = false
            for provider in self.providers.allObjects { provider.refresh() }
            self.onSizeChange()
        }
    }

    /// A pure record lookup or initial estimate. No loading, views or text layout.
    func size(for width: CGFloat) -> NSSize {
        if let math = measuredMathSize(for: width) { return math }
        let height: CGFloat
        switch descriptor {
        case let .code(_, language): height = language?.lowercased() == "mermaid" ? runtimeHeight + 28 : codeSize.height + 52
        case let .table(_, rows, _): height = (tableContent?.height ?? CGFloat(rows.count + 1) * (fontSize * 1.5 + 16)) + 44
        case .image:
            let natural = picture?.size ?? NSSize(width: 240, height: 60)
            height = ceil(min(width, natural.width) * natural.height / natural.width) + 28
        case .visualization: height = runtimeHeight
        case .math: height = fontSize * 1.5
        }
        return NSSize(width: width, height: max(1, ceil(height)))
    }

    func measuredMathSize(for width: CGFloat) -> NSSize? {
        guard case let .math(_, display) = descriptor else { return nil }
        let natural = mathNaturalSize ?? mathEstimate
        return NSSize(width: display ? width : min(width, ceil(natural.width)),
            height: ceil(natural.height) + (display ? 28 : 0) + (natural.width > width ? 12 : 0))
    }

    private func updateMathEstimate() {
        if case let .math(latex, _) = descriptor {
            mathEstimate = NSSize(width: max(fontSize, CGFloat(latex.utf16.count) * fontSize * 0.5), height: fontSize * 1.5)
        }
    }

    func makeMathLabel(latex: String, display: Bool) -> MTMathUILabel {
        let label = MTMathUILabel()
        let font = MTFontManager().latinModernFont(withSize: fontSize)
        font?.fallbackFont = NSFont.systemFont(ofSize: fontSize)
        label.font = font
        label.latex = latex
        label.labelMode = display ? .display : .text
        label.textColor = WeiBeiNativePalette.ink()
        label.displayErrorInline = true
        return label
    }

    var readableText: String {
        switch descriptor {
        case let .math(latex, _): return latex
        case let .code(source, _): return source
        case let .table(headers, rows, _): return ([headers] + rows).map { $0.joined(separator: "\t") }.joined(separator: "\n")
        case let .image(source, alt): return alt.isEmpty ? source : "\(alt) (\(source))"
        case let .visualization(id): return id
        }
    }

    func readingPosition(at point: CGPoint, in view: NSView) -> NativeChatAttachmentReadingPosition? {
        providers.allObjects.lazy.compactMap { $0.loadedContent?.readingPosition(at: point, in: view) }.first
    }

    func readingY(for position: NativeChatAttachmentReadingPosition, in view: NSView) -> CGFloat? {
        providers.allObjects.lazy.compactMap { $0.loadedContent?.readingY(for: position, in: view) }.first
    }

    func preparedBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
        textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        let width = max(1, textContainer.map { $0.size.width - 2 * $0.lineFragmentPadding } ?? proposedLineFragment.width)
        let size = size(for: width)
        let inline: Bool
        if case .math(_, false) = descriptor { inline = true } else { inline = false }
        let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: fontSize)
        return CGRect(x: 0, y: inline ? (font.xHeight - size.height) / 2 : 0, width: size.width, height: size.height)
    }

    override func viewProvider(for parentView: NSView?, location: any NSTextLocation,
                               textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
        let provider = NativeChatAttachmentProvider(textAttachment: self, parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager, location: location)
        provider.tracksTextAttachmentViewBounds = true
        providers.add(provider)
        return provider
    }
}

@MainActor
private final class NativeChatAttachmentProvider: NSTextAttachmentViewProvider {
    fileprivate weak var loadedContent: NativeChatAttachmentView?
    private weak var formula: NativeChatFormulaView?
    override func loadView() {
        guard let attachment = textAttachment as? NativeChatTextAttachment else { return }
        attachment.prepare()
        if case .math(_, false) = attachment.descriptor {
            let content = NativeChatFormulaView(attachment: attachment)
            formula = content
            view = content
        } else {
            let content = NativeChatAttachmentView(attachment)
            loadedContent = content
            view = content
        }
    }
    func refresh() {
        formula?.needsDisplay = true
        loadedContent?.refresh()
    }

    override func attachmentBounds(for attributes: [NSAttributedString.Key: Any], location: any NSTextLocation,
        textContainer: NSTextContainer?, proposedLineFragment: CGRect, position: CGPoint) -> CGRect {
        guard let attachment = textAttachment as? NativeChatTextAttachment else { return .zero }
        // Querying metrics never touches `view`, whose getter would create rich content.
        return attachment.preparedBounds(for: attributes, location: location, textContainer: textContainer,
            proposedLineFragment: proposedLineFragment, position: position)
    }

}

/// Draw SwiftMath's prepared native display list. No parsing or typesetting during draw.
private final class NativeChatFormulaView: NSView {
    let attachment: NativeChatTextAttachment
    private var overflow: NativeChatHorizontalScrollView?
    init(attachment: NativeChatTextAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        setAccessibilityLabel(attachment.readableText)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { overflow == nil ? nil : super.hitTest(point) }
    override func layout() {
        super.layout()
        let size = attachment.mathNaturalSize ?? bounds.size
        if size.width > bounds.width + 0.5 {
            if overflow == nil {
                let scroll = NativeChatHorizontalScrollView()
                scroll.drawsBackground = false
                scroll.hasHorizontalScroller = true
                scroll.documentView = NativeChatFormulaView(attachment: attachment)
                addSubview(scroll)
                overflow = scroll
            }
            overflow?.frame = bounds
            overflow?.documentView?.frame = NSRect(origin: .zero, size: size)
        } else { overflow?.removeFromSuperview(); overflow = nil }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard overflow == nil else { return }
        if let drawing = attachment.mathDrawing, let context = NSGraphicsContext.current?.cgContext {
            drawing.draw(context)
        } else if let error = attachment.mathError {
            (error as NSString).draw(in: bounds, withAttributes: [.font: NSFont.systemFont(ofSize: attachment.fontSize), .foregroundColor: NSColor.systemRed])
        }
    }
}

@MainActor
private final class NativeChatAttachmentView: NSView, NSTextViewDelegate {
    let attachment: NativeChatTextAttachment
    private let scroll = NativeChatHorizontalScrollView()
    private let document = NativeChatFlippedView()
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let caption = NSTextField(labelWithString: "")
    private var math: NativeChatFormulaView?
    private var code: NativeChatTextView?
    private var table: NativeChatTableView?
    private var picture: NSImageView?
    private var external: NSView?
    private var renderedKind = ""
    private var boundsObserver: NSObjectProtocol?
    private var layingOut = false
    private var hasLaidOut = false
    override var isFlipped: Bool { true }
    private var isInlineMath: Bool { if case .math(_, false) = attachment.descriptor { return true }; return false }
    private var chrome: CGFloat { if case .visualization = attachment.descriptor { return 0 }; return isInlineMath ? 0 : 28 }

    init(_ attachment: NativeChatTextAttachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        scroll.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self, self.hasLaidOut, !self.layingOut else { return }
                self.attachment.horizontalOffset = self.scroll.contentView.bounds.minX
            } }
        addSubview(scroll)
        copyButton.target = self
        copyButton.action = #selector(copyContent)
        copyButton.bezelStyle = .inline
        copyButton.font = .systemFont(ofSize: 11)
        addSubview(copyButton)
        caption.font = .systemFont(ofSize: 11)
        addSubview(caption)
        setAccessibilityLabel(attachment.readableText)
        refresh()
    }
    required init?(coder: NSCoder) { nil }
    deinit { if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) } }

    func refresh() {
        let kind: String
        switch attachment.descriptor {
        case .math: kind = "math"
        case let .code(_, language): kind = language?.lowercased() == "mermaid" ? "mermaid" : "code"
        case .table: kind = "table"
        case .image: kind = "image"
        case .visualization: kind = "visualization"
        }
        if renderedKind != kind {
            document.subviews.forEach { $0.removeFromSuperview() }
            math = nil; code = nil; table = nil; picture = nil; external = nil
            renderedKind = kind
        }
        appearance = NSAppearance(named: attachment.isDark ? .darkAqua : .aqua)
        wantsLayer = true
        copyButton.title = attachment.interfaceLanguage.text("复制", "Copy")
        copyButton.isHidden = isInlineMath || chrome == 0
        caption.isHidden = isInlineMath || chrome == 0
        caption.textColor = WeiBeiNativePalette.secondaryInk()
        if case .code = attachment.descriptor { layer?.backgroundColor = WeiBeiNativePalette.codePaper().cgColor }
        else { layer?.backgroundColor = NSColor.clear.cgColor }
        switch attachment.descriptor {
        case .math:
            caption.isHidden = true
            if math == nil {
                let view = NativeChatFormulaView(attachment: attachment)
                math = view; document.addSubview(view)
            }
            math?.needsDisplay = true
        case let .code(source, language):
            if language?.lowercased() == "mermaid" {
                caption.stringValue = attachment.interfaceLanguage.text("流程图 · Mermaid", "Mermaid diagram")
                let preview = mermaidPreview(source)
                if let host = attachment.runtime as? NSHostingView<NativeChatMermaidPreview> {
                    if attachment.runtimeRevision != attachment.revision { host.rootView = preview }
                } else {
                    let host = NSHostingView(rootView: preview)
                    host.sizingOptions = []
                    attachment.runtime = host
                }
                attachment.runtimeRevision = attachment.revision
                bindRuntime()
            } else {
                caption.stringValue = language ?? attachment.interfaceLanguage.text("代码", "Code")
                caption.toolTip = attachment.codeError
                if code == nil {
                    let text = NativeChatTextView(usingTextLayoutManager: true)
                    text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
                    text.clipsToBounds = true
                    text.textContainerInset = .zero
                    text.textContainer?.lineFragmentPadding = 0
                    text.textContainer?.widthTracksTextView = false
                    text.isVerticallyResizable = false
                    text.delegate = self
                    if let previous = attachment.codeView {
                        (previous.textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage = NSTextStorage()
                    }
                    (text.textLayoutManager?.textContentManager as? NSTextContentStorage)?.textStorage = attachment.codeStorage
                    attachment.codeView = text
                    text.setSelectedRange(attachment.codeSelection)
                    code = text; document.addSubview(text)
                }
            }
        case .table:
            caption.stringValue = attachment.interfaceLanguage.text("表格", "Table")
            if table == nil {
                let view = NativeChatTableView(attachment: attachment)
                table = view; document.addSubview(view)
            }
            table?.refresh()
        case let .image(_, alt):
            caption.stringValue = attachment.imageFailed ? attachment.interfaceLanguage.text("图片未能加载", "Could not load image") + " · " + alt : alt
            if picture == nil {
                let view = NSImageView()
                view.imageScaling = .scaleProportionallyUpOrDown
                view.setAccessibilityLabel(alt)
                view.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openImage)))
                picture = view; document.addSubview(view)
            }
            picture?.image = attachment.picture
        case let .visualization(id):
            if attachment.runtime == nil {
                attachment.runtime = attachment.visualizationView?(id, max(1, bounds.width)) { [weak attachment] height in
                    guard let attachment, case let .visualization(currentID) = attachment.descriptor, currentID == id, height.isFinite, height > 0,
                          abs(height - attachment.runtimeHeight) > 0.5 else { return }
                    attachment.onWillResize()
                    attachment.runtimeHeight = ceil(height)
                    attachment.changed()
                }
            }
            bindRuntime()
        }
        needsLayout = true
    }

    private func bindRuntime() {
        guard external !== attachment.runtime else { return }
        external?.removeFromSuperview()
        external = attachment.runtime
        if let external { document.addSubview(external) }
    }
    private func mermaidPreview(_ source: String) -> NativeChatMermaidPreview {
        let expected = attachment.revision
        return NativeChatMermaidPreview(source: source, appearanceMode: WeiBeiNativePalette.current,
            interfaceLanguage: attachment.interfaceLanguage, textScale: attachment.fontSize / 14,
            onHeight: { [weak attachment] height in
                guard let attachment, attachment.revision == expected, height.isFinite, height > 0,
                      abs(max(44, ceil(height)) - attachment.runtimeHeight) > 0.5 else { return }
                attachment.onWillResize()
                attachment.runtimeHeight = max(44, ceil(height))
                attachment.changed()
            }, onFailure: { [weak self] in
                guard let self else { return }
                self.caption.stringValue = self.attachment.interfaceLanguage.text("流程图未能加载", "Could not load diagram")
            })
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if let code { attachment.codeSelection = code.selectedRange() }
    }
    func readingPosition(at point: CGPoint, in source: NSView) -> NativeChatAttachmentReadingPosition? {
        let local = convert(point, from: source)
        guard bounds.contains(local) else { return nil }
        if let table, let data = attachment.tableContent, !data.rowHeights.isEmpty {
            let y = table.convert(local, from: self).y
            let row = data.row(at: y)
            return .table(row: row, offset: y - data.rowOffsets[row])
        }
        if let code, let manager = code.textLayoutManager, let content = manager.textContentManager {
            let point = code.convert(local, from: self)
            if let fragment = manager.textLayoutFragment(for: point),
               let line = fragment.textLineFragment(forVerticalOffset: point.y - fragment.layoutFragmentFrame.minY, requiresExactMatch: false),
               let start = fragment.textElement?.elementRange?.location {
                return .code(character: content.offset(from: content.documentRange.location, to: start) + line.characterRange.location,
                    offset: point.y - fragment.layoutFragmentFrame.minY - line.typographicBounds.minY)
            }
        }
        return .content(offset: local.y)
    }

    func readingY(for position: NativeChatAttachmentReadingPosition, in target: NSView) -> CGFloat? {
        switch position {
        case let .table(row, offset):
            guard let table, let data = attachment.tableContent, data.rowHeights.indices.contains(row) else { return nil }
            return table.convert(CGPoint(x: 0, y: data.rowOffsets[row] + offset), to: target).y
        case let .code(character, offset):
            guard let code, let manager = code.textLayoutManager, let content = manager.textContentManager,
                  let location = content.location(content.documentRange.location, offsetBy: min(character, code.string.utf16.count)),
                  let fragment = manager.textLayoutFragment(for: location),
                  let line = fragment.textLineFragment(for: location, isUpstreamAffinity: false) else { return nil }
            return code.convert(CGPoint(x: 0, y: fragment.layoutFragmentFrame.minY + line.typographicBounds.minY + offset), to: target).y
        case let .content(offset): return convert(CGPoint(x: 0, y: offset), to: target).y
        }
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        attachment.onOpenURL(url); return true
    }
    override func layout() {
        super.layout()
        let horizontalOffset = attachment.horizontalOffset
        layingOut = true
        defer { layingOut = false; hasLaidOut = true }
        copyButton.frame = NSRect(x: max(0, bounds.width - 44), y: 3, width: 40, height: 22)
        caption.frame = NSRect(x: 8, y: 5, width: max(0, bounds.width - 60), height: 20)
        scroll.frame = NSRect(x: 0, y: chrome, width: bounds.width, height: max(1, bounds.height - chrome))
        var documentWidth = bounds.width
        if math != nil { documentWidth = max(documentWidth, attachment.mathNaturalSize?.width ?? 0) }
        if code != nil { documentWidth = max(documentWidth, attachment.codeSize.width + 24) }
        if table != nil { documentWidth = max(documentWidth, attachment.tableContent?.width ?? 0) }
        document.frame = NSRect(x: 0, y: 0, width: documentWidth, height: max(1, bounds.height - chrome))
        if let size = attachment.mathNaturalSize { math?.frame = NSRect(x: max(0, (documentWidth - size.width) / 2), y: 0, width: size.width, height: size.height) }
        code?.conversationClipView = mainConversationClipView
        code?.frame = NSRect(x: 12, y: 8, width: max(1, documentWidth - 24), height: attachment.codeSize.height)
        code?.textContainer?.size = NSSize(width: max(1, documentWidth - 24), height: .greatestFiniteMagnitude)
        table?.frame = NSRect(x: 0, y: 8, width: documentWidth, height: attachment.tableContent?.height ?? 1)
        table?.needsLayout = true
        picture?.frame = document.bounds
        external?.frame = document.bounds
        let target = NSRect(x: horizontalOffset, y: 0, width: scroll.contentView.bounds.width, height: scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(target).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    @objc private func copyContent() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(attachment.readableText, forType: .string)
    }
    @objc private func openImage() {
        if case let .image(source, _) = attachment.descriptor, let url = URL(string: source) { attachment.onOpenURL(url) }
    }
}

private final class NativeChatFlippedView: NSView { override var isFlipped: Bool { true } }
private final class NativeChatHorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || event.modifierFlags.contains(.shift) { super.scrollWheel(with: event) }
        else { nextResponder?.scrollWheel(with: event) }
    }
}
extension NSView {
    var mainConversationClipView: NSClipView? {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? NSScrollView, scroll.hasVerticalScroller { return scroll.contentView }
            ancestor = view.superview
        }
        return nil
    }
}

/// Only the Mermaid attachment uses the existing dedicated web renderer.
/// Updating this value preserves the hosting view and its underlying web view.
private struct NativeChatMermaidPreview: View {
    let source: String
    let appearanceMode: WeiBeiAppearanceMode
    let interfaceLanguage: WeiBeiInterfaceLanguage
    let textScale: CGFloat
    let onHeight: (CGFloat) -> Void
    let onFailure: () -> Void

    private var markdown: String {
        let longestFence = source.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
        let fence = String(repeating: "`", count: max(3, longestFence + 1))
        return "\(fence)mermaid\n\(source)\n\(fence)"
    }

    var body: some View {
        MarkdownPreviewView(markdown: markdown, markdownBaseURL: nil,
            appearanceMode: appearanceMode, interfaceLanguage: interfaceLanguage, compact: true,
            preservesHeightAcrossMarkdownChanges: true,
            onRenderFailure: onFailure, onMeasuredHeight: onHeight)
            .environment(\.weiBeiTextScale, textScale)
    }
}
