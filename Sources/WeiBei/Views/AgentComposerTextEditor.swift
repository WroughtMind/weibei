import AppKit
import SwiftUI

struct AgentComposerFocusSurface: NSViewRepresentable {
    var focus: () -> Void

    func makeNSView(context: Context) -> AgentComposerFocusNSView {
        AgentComposerFocusNSView(focus: focus)
    }

    func updateNSView(_ view: AgentComposerFocusNSView, context: Context) {
        view.focus = focus
    }
}

final class AgentComposerFocusNSView: NSView {
    var focus: () -> Void

    init(focus: @escaping () -> Void) {
        self.focus = focus
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        focus()
    }
}

struct AgentComposerTextEditor: NSViewRepresentable {
    /// App-wide text tier multiplier — the native input must track the same
    /// tier as the weiBeiText-scaled placeholder drawn above it.
    @Environment(\.weiBeiTextScale) private var textScale
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @Binding var active: Bool
    var focused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var lineLimit: ClosedRange<Int>
    var appearanceMode: WeiBeiAppearanceMode
    var accessibilityLabel: String
    var submit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = AgentComposerNativeTextView()
        textView.delegate = context.coordinator
        textView.focusChanged = { [weak coordinator = context.coordinator] focused in
            coordinator?.setFocused(focused)
        }
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        textView.setAccessibilityIdentifier("agent-composer-input")
        scrollView.documentView = textView
        applyPresentation(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        applyPresentation(to: textView)
        if textView.string != text {
            textView.string = text
        }
        updateFocus(of: textView)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView scrollView: NSScrollView,
        context: Context
    ) -> CGSize? {
        guard let textView = scrollView.documentView as? NSTextView else { return nil }
        let width = max(proposal.width ?? scrollView.bounds.width, 1)
        let heights = Self.heights(for: textView, width: width, lineLimit: lineLimit)
        textView.frame.size = NSSize(width: width, height: max(heights.content, heights.fitted))
        context.coordinator.report(height: heights.fitted)
        return CGSize(width: width, height: heights.fitted)
    }

    static func heights(
        for textView: NSTextView,
        width: CGFloat,
        lineLimit: ClosedRange<Int>
    ) -> (content: CGFloat, fitted: CGFloat) {
        guard let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return (1, 1)
        }
        let resolvedWidth = max(width, 1)
        textView.frame.size.width = resolvedWidth
        textContainer.containerSize = NSSize(
            width: resolvedWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: textContainer)

        let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = layoutManager.defaultLineHeight(for: font)
        let contentHeight = max(
            layoutManager.usedRect(for: textContainer).height,
            layoutManager.extraLineFragmentRect.maxY,
            lineHeight
        )
        let minimumHeight = lineHeight * CGFloat(lineLimit.lowerBound)
        let maximumHeight = lineHeight * CGFloat(lineLimit.upperBound)
        return (
            contentHeight,
            min(max(contentHeight, minimumHeight), maximumHeight)
        )
    }

    private func applyPresentation(to textView: NSTextView) {
        textView.font = NSFont.systemFont(ofSize: fontSize * textScale)
        textView.textColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.insertionPointColor = WeiBeiNativePalette.ink(for: appearanceMode)
        textView.setAccessibilityLabel(accessibilityLabel)
    }

    private func updateFocus(of textView: NSTextView) {
        guard focused.wrappedValue,
              textView.window?.firstResponder !== textView else { return }
        DispatchQueue.main.async { [weak textView] in
            guard let textView, self.focused.wrappedValue else { return }
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentComposerTextEditor

        init(_ parent: AgentComposerTextEditor) {
            self.parent = parent
        }

        func setFocused(_ value: Bool) {
            if parent.active != value {
                parent.active = value
            }
            if parent.focused.wrappedValue != value {
                parent.focused.wrappedValue = value
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            reportCurrentHeight(for: textView)
        }

        func report(height: CGFloat) {
            guard height.isFinite,
                  abs(parent.measuredHeight - height) > 0.5 else { return }
            let measuredHeight = parent.$measuredHeight
            DispatchQueue.main.async {
                if abs(measuredHeight.wrappedValue - height) > 0.5 {
                    measuredHeight.wrappedValue = height
                }
            }
        }

        private func reportCurrentHeight(for textView: NSTextView) {
            guard let scrollView = textView.enclosingScrollView,
                  scrollView.bounds.width > 1 else { return }
            report(height: AgentComposerTextEditor.heights(
                for: textView,
                width: scrollView.bounds.width,
                lineLimit: parent.lineLimit
            ).fitted)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let isReturn = commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            guard isReturn,
                  !textView.hasMarkedText(),
                  NSApp.currentEvent?.modifierFlags.contains(.shift) != true else {
                return false
            }
            parent.submit()
            return true
        }
    }
}

private final class AgentComposerNativeTextView: NSTextView {
    var focusChanged: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { focusChanged?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { focusChanged?(false) }
        return resigned
    }
}
