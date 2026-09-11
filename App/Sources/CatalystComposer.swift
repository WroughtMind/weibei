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
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ComposerTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? uiView.bounds.width)
        let content = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let line = uiView.font?.lineHeight ?? 20
        let height = lineLimit.map { min(max(content, line * CGFloat($0.lowerBound)), line * CGFloat($0.upperBound)) } ?? max(line, content)
        uiView.isScrollEnabled = content > height + 1
        context.coordinator.report(height)
        return CGSize(width: width, height: height)
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AgentComposerTextEditor
        var appliedFocusRequest = 0
        init(_ parent: AgentComposerTextEditor) { self.parent = parent }
        func applyFocus(to view: UITextView) {
            guard view.window != nil, parent.focused.wrappedValue || parent.focusRequest != appliedFocusRequest else { return }
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
        func report(_ height: CGFloat) {
            let binding = parent.$measuredHeight
            guard abs(binding.wrappedValue - height) > 0.5 else { return }
            DispatchQueue.main.async { if abs(binding.wrappedValue - height) > 0.5 { binding.wrappedValue = height } }
        }
    }
    final class ComposerTextView: UITextView {
        var onAttachment: (() -> Void)?
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
