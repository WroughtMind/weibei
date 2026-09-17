import UIKit
import SwiftUI

struct AgentComposerTextEditor: UIViewRepresentable {
    @Environment(\.weiBeiTextScale) private var textScale
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    @Binding var active: Bool
    var focused: FocusState<Bool>.Binding
    var fontSize: CGFloat
    var lineLimit: ClosedRange<Int>?
    var focusRequest: Int
    var appearanceMode: WeiBeiAppearanceMode
    var accessibilityLabel: String
    var submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> ComposerTextView {
        let view = ComposerTextView()
        view.backgroundColor = .clear
        view.delegate = context.coordinator
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.accessibilityIdentifier = "agent-composer-input"
        view.text = text
        view.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.report(view)
        }
        view.onAttachment = { [weak view, weak coordinator = context.coordinator] in
            guard let view else { return }; coordinator?.applyFocus(to: view)
        }
        return view
    }
    func updateUIView(_ view: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        view.font = .systemFont(ofSize: fontSize * textScale)
        view.textColor = WeiBeiNativePalette.ink(for: appearanceMode)
        view.tintColor = view.textColor
        view.accessibilityLabel = accessibilityLabel
        if view.markedTextRange == nil, view.text != text { view.text = text }
        context.coordinator.applyFocus(to: view)
        view.setNeedsLayout()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? uiView.bounds.width)
        return CGSize(width: width, height: Self.heights(uiView, width: width, lineLimit: lineLimit).fitted)
    }
    private static func heights(_ view: UITextView, width: CGFloat, lineLimit: ClosedRange<Int>?) -> (content: CGFloat, fitted: CGFloat) {
        let content = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let line = view.font?.lineHeight ?? 20
        let fitted = lineLimit.map { min(max(content, line * CGFloat($0.lowerBound)), line * CGFloat($0.upperBound)) } ?? max(line, content)
        return (content, fitted)
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AgentComposerTextEditor
        var appliedFocusRequest = 0
        init(_ parent: AgentComposerTextEditor) { self.parent = parent }
        func applyFocus(to view: UITextView) {
            guard view.window != nil, parent.focusRequest != appliedFocusRequest else { return }
            if !view.isFirstResponder { view.becomeFirstResponder() }
            appliedFocusRequest = parent.focusRequest
        }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.active = true; parent.focused.wrappedValue = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.active = false; parent.focused.wrappedValue = false }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", textView.markedTextRange == nil,
                  (textView as? ComposerTextView)?.shiftPressed != true else { return true }
            parent.submit()
            return false
        }
        func report(_ view: UITextView) {
            // SwiftUI probes narrow widths; only the placed editor may update its height.
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, view.bounds.width > 1 else { return }
                let heights = AgentComposerTextEditor.heights(view, width: view.bounds.width, lineLimit: parent.lineLimit)
                let scrolls = heights.content > heights.fitted + 1
                if view.isScrollEnabled != scrolls { view.isScrollEnabled = scrolls }
                if abs(parent.measuredHeight - heights.fitted) > 0.5 {
                    parent.measuredHeight = heights.fitted
                }
            }
        }
    }
    final class ComposerTextView: UITextView {
        var onAttachment: (() -> Void)?
        var onLayout: ((UITextView) -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?(self)
        }
        var shiftPressed = false
        override func didMoveToWindow() { super.didMoveToWindow(); onAttachment?() }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            shiftPressed = presses.contains { $0.key?.modifierFlags.contains(.shift) == true }
            super.pressesBegan(presses, with: event)
        }
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            super.pressesEnded(presses, with: event)
            shiftPressed = false
        }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            super.pressesCancelled(presses, with: event)
            shiftPressed = false
        }
    }
}
