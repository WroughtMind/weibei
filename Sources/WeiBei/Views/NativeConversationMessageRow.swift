import AppKit
import SwiftUI
import WeiBeiCore

/// Reusable native text plus a small host for existing message controls.
@MainActor
final class NativeConversationMessageRow: NSTableCellView {
    let textView = NativeChatTextView(usingTextLayoutManager: true)
    private(set) var state: NativeConversationMessageState?
    private let controls = ControlsHost(rootView: AnyView(EmptyView()))
    private let copyButton = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制消息")!, target: nil, action: nil)
    private let retryButton = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "重新生成最后一条回答")!, target: nil, action: nil)
    private let bubble = NSView()
    private weak var store: WorkspaceStore?
    private var wide = false
    private var textScale: CGFloat = 1
    private var activity: String?
    private var onHeight: ((CGFloat) -> Void)?
    private var onOpenSettings: (() -> Void)?
    private var controlsDirty = true
    private var controlsWidth: CGFloat = 0
    private var controlsHeight: CGFloat = 0
    private var tracking: NSTrackingArea?
    private var sourcePopover: NSPopover?
    private lazy var userCopyGesture = NSClickGestureRecognizer(target: self, action: #selector(copyMessage))
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.clipsToBounds = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.addGestureRecognizer(userCopyGesture)
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 12
        addSubview(bubble)
        addSubview(textView)
        controls.sizingOptions = [.intrinsicContentSize]
        controls.onSizeChange = { [weak self] in self?.controlsDirty = true; self?.needsLayout = true }
        addSubview(controls)
        for button in [copyButton, retryButton] {
            button.bezelStyle = .inline
            button.isBordered = false
            button.target = self
            button.alphaValue = 0
            addSubview(button)
        }
        copyButton.action = #selector(copyMessage)
        retryButton.action = #selector(regenerate)
    }
    required init?(coder: NSCoder) { nil }

    func bind(_ state: NativeConversationMessageState) {
        guard self.state !== state else { return }
        unbind()
        self.state = state
        state.renderer.view = textView
        textView.delegate = state.renderer
        textView.onLayout = { [weak self, weak state] in
            guard let self, let state, self.state === state else { return }
            state.renderer.layoutDidChange()
        }
        state.renderer.onHeightChange = { [weak self, weak state] height in
            guard let self, let state, self.state === state else { return }
            state.bodyHeight = height
            self.needsLayout = true
        }
        state.renderer.onOpenURL = { [weak self, weak state] url in
            guard let self, let state, self.state === state else { return }
            self.open(url, state: state)
        }
        setAccessibilityIdentifier("chat-message-\(state.message.id.uuidString)")
        needsLayout = true
    }

    func unbind() {
        sourcePopover?.close()
        sourcePopover = nil
        if state?.renderer.view === textView {
            state?.renderer.view = nil
            state?.renderer.onHeightChange = nil
            state?.renderer.onOpenURL = { _ in }
        }
        textView.onLayout = nil
        textView.delegate = nil
        state = nil
        controls.rootView = AnyView(EmptyView())
        controlsHeight = 0
        controlsDirty = true
    }

    func configure(store: WorkspaceStore, textScale: CGFloat, wide: Bool, activity: String?, onOpenSettings: @escaping () -> Void, onHeight: @escaping (CGFloat) -> Void) {
        self.store = store
        self.textScale = textScale
        self.wide = wide
        self.onHeight = onHeight
        self.onOpenSettings = onOpenSettings
        guard let state else { return }
        let renderer = state.renderer
        let fontSize = resolvedFontSize
        let restyle = renderer.fontSize != fontSize || renderer.appearanceKey != store.appearanceMode.rawValue
            || renderer.interfaceLanguage != store.interfaceLanguage
        renderer.fontSize = fontSize
        renderer.isDark = store.appearanceMode.isDark
        renderer.appearanceKey = store.appearanceMode.rawValue
        renderer.interfaceLanguage = store.interfaceLanguage
        textView.appearance = NSAppearance(named: store.appearanceMode.isDark ? .darkAqua : .aqua)
        textView.linkTextAttributes = [.foregroundColor: WeiBeiNativePalette.link()]
        state.imageHandler.update(markdownBaseURLString: store.currentMarkdownBaseURL?.absoluteString ?? "",
            attachmentDirectory: store.currentAttachmentDirectory, appearanceMode: store.appearanceMode,
            interfaceLanguage: store.interfaceLanguage)
        renderer.imageLoader = { [weak state] source, completion in state?.imageHandler.loadImage(source: source, completion: completion) }
        renderer.visualizationView = { [weak state, weak store] identifier, width, onHeight in
            guard let state, let store else { return nil }
            let host = NSHostingView(rootView: AgentNativeContentAttachment(messageID: state.message.id,
                identifier: identifier.removingPercentEncoding ?? identifier, initialBlocks: state.message.contentBlocks,
                onHeight: onHeight).environmentObject(store).environment(\.weiBeiTextScale, textScale))
            host.sizingOptions = []
            host.frame.size = NSSize(width: width, height: 160)
            return host
        }
        if restyle { renderer.restyle() }
        bubble.isHidden = state.message.role != .user
        textView.isSelectable = state.message.role != .user
        userCopyGesture.isEnabled = state.message.role == .user
        textView.toolTip = state.message.role == .user ? store.ui("点击复制消息", "Click to copy message") : nil
        bubble.layer?.backgroundColor = WeiBeiNativePalette.paperRaised().cgColor
        bubble.layer?.borderWidth = 1
        bubble.layer?.borderColor = WeiBeiNativePalette.hairline().withAlphaComponent(0.4).cgColor
        copyButton.toolTip = store.ui("复制消息", "Copy message")
        copyButton.isHidden = state.message.role == .user
        retryButton.toolTip = store.ui("重新生成最后一条回答", "Regenerate last response")
        retryButton.isHidden = state.message.id != store.lastRegeneratableAgentReplyID
        updateControls(activity: activity)
    }

    func updateControls(activity: String?) {
        self.activity = activity
        guard let state, let store else { return }
        if state.message.role == .user {
            controls.rootView = AnyView(EmptyView())
        } else {
            controls.rootView = AnyView(VStack(alignment: .leading, spacing: 8) {
                if state.message.completionState == .generating && state.renderer.preparedStorage.length == 0 {
                    AgentThinkingIndicator(activityText: activity, chatWideTypography: wide)
                }
                AgentMessageSupplement(message: state.message, citations: state.citations, drafts: state.actionDrafts, onOpenSettings: onOpenSettings)
            }.environmentObject(store).environment(\.weiBeiTextScale, textScale).id(state.message.id))
        }
        controlsDirty = true
        needsLayout = true
    }

    private var resolvedFontSize: CGFloat {
        if state?.message.role == .user { return 14.5 * textScale }
        return (wide || min(960, max(1, bounds.width - 24)) >= 620 ? 16 : 14) * textScale
    }

    override func layout() {
        super.layout()
        guard let state, bounds.width > 1 else { return }
        let user = state.message.role == .user
        let column = min(960, max(1, bounds.width - (wide ? 56 : 24)))
        let contentWidth = user ? min(state.userNaturalWidth ?? 490, max(1, column - 30)) : max(1, column - 28)
        let x = user ? (bounds.width + column) / 2 - contentWidth - 15 : (bounds.width - column) / 2 + 20
        let fontSize = resolvedFontSize
        if state.renderer.fontSize != fontSize {
            state.renderer.fontSize = fontSize
            state.renderer.restyle()
        }
        let body = max(state.renderer.preparedStorage.length == 0 ? 1 : fontSize * 1.5, state.bodyHeight)
        textView.conversationClipView = enclosingScrollView?.contentView
        textView.frame = NSRect(x: x, y: user ? 11 : 10, width: max(1, contentWidth), height: body)
        textView.layoutSubtreeIfNeeded()
        if user, state.userNaturalWidth == nil, let manager = textView.textLayoutManager,
           let content = manager.textContentManager, let viewport = manager.textViewportLayoutController.viewportRange,
           viewport.location.compare(content.documentRange.location) == .orderedSame,
           viewport.endLocation.compare(content.documentRange.endLocation) == .orderedSame,
           manager.usageBoundsForTextContainer.width > 0 {
            state.userNaturalWidth = min(contentWidth, ceil(manager.usageBoundsForTextContainer.width))
            needsLayout = true
        }
        if controlsWidth != contentWidth { controlsWidth = contentWidth; controlsDirty = true }
        if controlsDirty {
            controlsDirty = false
            controls.frame.size.width = contentWidth
            controlsHeight = user ? 0 : ceil(controls.fittingSize.height)
        }
        let gap: CGFloat = controlsHeight > 0 && state.renderer.preparedStorage.length > 0 ? 8 : 0
        controls.frame = NSRect(x: x, y: body + 10 + gap, width: contentWidth, height: max(0, controlsHeight))
        let height = body + (user ? 22 : 20) + controlsHeight + gap
        bubble.frame = NSRect(x: x - 15, y: 0, width: contentWidth + 30, height: height)
        copyButton.frame = NSRect(x: x - 4, y: max(0, height - 22), width: 24, height: 24)
        retryButton.frame = NSRect(x: x + 25, y: max(0, height - 22), width: 24, height: 24)
        state.measuredWidth = contentWidth
        state.measuredFontSize = fontSize
        state.measuredVersion = state.version
        onHeight?(height)
    }

    private func open(_ url: URL, state: NativeConversationMessageState) {
        guard let store else { return }
        if let source = state.sourcePresentation?.source(for: url) {
            _ = store.openAgentReplySource(source)
        } else if let sources = state.sourcePresentation?.additionalSources(for: url), !sources.isEmpty {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: VStack(alignment: .leading, spacing: 0) {
                ForEach(sources) { source in
                    Button { popover.close(); _ = store.openAgentReplySource(source) } label: { AgentReplySourceDetail(source: source) }
                        .buttonStyle(.plain)
                }
            }.frame(width: 340).padding(.vertical, 6).environmentObject(store))
            sourcePopover = popover
            popover.show(relativeTo: textView.visibleRect, of: textView, preferredEdge: .maxY)
        } else if url.scheme == "weibei-note" {
            store.openOrCreateWikiNote(title: String(url.absoluteString.dropFirst("weibei-note:".count)).removingPercentEncoding ?? url.path)
        } else if url.scheme == "weibei-source" {
            store.openSourceReference(String(url.absoluteString.dropFirst("weibei-source:".count)).removingPercentEncoding ?? url.path)
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        } else if let imageURL = state.imageHandler.validatedLocalImageURL(source: url.absoluteString) {
            NSWorkspace.shared.open(imageURL)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        self.tracking = tracking
        addTrackingArea(tracking)
    }
    override func mouseEntered(with event: NSEvent) { copyButton.alphaValue = 1; retryButton.alphaValue = 1 }
    override func mouseExited(with event: NSEvent) { copyButton.alphaValue = 0; retryButton.alphaValue = 0 }
    @objc private func copyMessage() {
        guard let state else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.markdownMemo.outputs(text: state.displayedText,
            sources: state.message.sources, language: state.renderer.interfaceLanguage).display, forType: .string)
    }
    @objc private func regenerate() { store?.regenerateLastAssistantReply() }

    private final class ControlsHost: NSHostingView<AnyView> {
        var onSizeChange: (() -> Void)?
        override func invalidateIntrinsicContentSize() { super.invalidateIntrinsicContentSize(); onSizeChange?() }
    }
}
