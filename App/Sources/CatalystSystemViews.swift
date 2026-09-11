import UIKit
import SwiftUI
import WebKit
import WeiBeiCore

struct AccessibilityFrameProbe: UIViewRepresentable {
    let identifier: String
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isAccessibilityElement = true
        view.accessibilityLabel = "weibei pane frame anchor"
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { view.accessibilityIdentifier = identifier }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }
}

struct PaletteKeyboardBridge: View {
    var onUp: () -> Void
    var onDown: () -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onUp) { Color.clear }.keyboardShortcut(.upArrow, modifiers: [])
            Button(action: onDown) { Color.clear }.keyboardShortcut(.downArrow, modifiers: [])
            Button(action: onReturn) { Color.clear }.keyboardShortcut(.return, modifiers: [])
            Button(action: onEscape) { Color.clear }.keyboardShortcut(.escape, modifiers: [])
        }.buttonStyle(.plain).frame(width: 0, height: 0).accessibilityHidden(true)
    }
}

struct CatalystShortcutRecorder: UIViewRepresentable {
    var onChord: (AppShortcutChord) -> Void
    var onCancel: () -> Void
    func makeUIView(context: Context) -> Recorder { Recorder() }
    func updateUIView(_ view: Recorder, context: Context) {
        view.onChord = onChord; view.onCancel = onCancel
        if view.window != nil { view.becomeFirstResponder() }
    }
    static func dismantleUIView(_ view: Recorder, coordinator: ()) { view.resignFirstResponder() }
    final class Recorder: UIView {
        var onChord: ((AppShortcutChord) -> Void)?
        var onCancel: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override func didMoveToWindow() { super.didMoveToWindow(); if window != nil { becomeFirstResponder() } }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let key = presses.first?.key else { super.pressesBegan(presses, with: event); return }
            if key.keyCode == .keyboardEscape { onCancel?() }
            else if let chord = AppShortcutChord.from(key: key) { onChord?(chord) }
        }
    }
}

enum CatalystResizeCursor: String {
    case resizeUpDown, resizeLeftRight, crosshair
    @MainActor func push() { CatalystDesktopWindow.shared.pushCursor(rawValue) }
}

final class ConversationWebClippingView: UIView {
    let webView: WKWebView
    var onViewportLayout: ((CGSize) -> Void)?
    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        clipsToBounds = true
        webView.clipsToBounds = true
        webView.scrollView.isScrollEnabled = false
        addSubview(webView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        webView.frame = bounds
        onViewportLayout?(bounds.size)
    }
}
