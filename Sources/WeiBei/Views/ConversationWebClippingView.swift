import AppKit
import WebKit

/// 对话内嵌 WebView 的共享裁剪容器:滚动事件让位给外层对话 ScrollView。
/// 富回答旧系统退役时从 RichAnswerWebRuntimeView 迁出,供 genui 链路复用。
final class ConversationWebClippingView: NSView {
    let webView: WKWebView
    var onViewportLayout: ((CGSize) -> Void)?
    private var scrollWheelMonitor: Any?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        webView.wantsLayer = true
        webView.layer?.masksToBounds = true
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        removeScrollWheelMonitor()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        webView.isHidden = false
        enforceScrollClipping()
        DispatchQueue.main.async { [weak self] in
            self?.enforceScrollClipping()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScrollWheelMonitor()
        webView.isHidden = false
        enforceScrollClipping()
        DispatchQueue.main.async { [weak self] in
            self?.enforceScrollClipping()
        }
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
        onViewportLayout?(bounds.size)
        enforceScrollClipping()
        // No per-scroll CALayer mask: bounds observers + mask rebuilds thrash during fling.
        webView.layer?.mask = nil
        webView.isHidden = false
    }

    /// Let the conversation ScrollView own vertical wheel — embedded web UI is not a nested scroller.
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
           let outer = nearestConversationScrollView() {
            outer.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func updateScrollWheelMonitor() {
        guard window != nil else {
            removeScrollWheelMonitor()
            return
        }
        guard scrollWheelMonitor == nil else { return }
        scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.forwardVerticalScroll(event, in: event.window, at: event.locationInWindow) else {
                return event
            }
            return nil
        }
    }

    // AppKit supplies the event's window and coordinates. Keeping that input explicit
    // also lets hidden-window checks exercise this handler without posting desktop events.
    func forwardVerticalScroll(_ event: NSEvent, in eventWindow: NSWindow?, at location: NSPoint) -> Bool {
        guard eventWindow === window,
              abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
              let contentView = window?.contentView,
              let hitView = contentView.hitTest(contentView.convert(location, from: nil)),
              hitView === self || hitView.isDescendant(of: self),
              let outer = nearestConversationScrollView() else { return false }
        outer.scrollWheel(with: event)
        return true
    }

    private func removeScrollWheelMonitor() {
        guard let scrollWheelMonitor else { return }
        NSEvent.removeMonitor(scrollWheelMonitor)
        self.scrollWheelMonitor = nil
    }

    private func nearestConversationScrollView() -> NSScrollView? {
        var candidate: NSView? = superview
        while let view = candidate {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }

    private func enforceScrollClipping() {
        // Clip only — never attach boundsDidChange observers (those froze immersive scroll).
        var ancestor = superview
        while let current = ancestor {
            if let clipView = current as? NSClipView {
                clipView.wantsLayer = true
                clipView.layer?.masksToBounds = true
                return
            }
            if let scrollView = current as? NSScrollView {
                scrollView.contentView.wantsLayer = true
                scrollView.contentView.layer?.masksToBounds = true
                return
            }
            ancestor = current.superview
        }
    }

    func refreshViewportClipping() {
        enforceScrollClipping()
        webView.layer?.mask = nil
        webView.isHidden = false
    }
}
