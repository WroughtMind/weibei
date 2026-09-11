import UIKit
import SwiftUI
import PDFKit
import WeiBeiCore

extension PDFView { var isFlipped: Bool { true } }

final class ReaderPDFView: PDFView {
    var reportCurrentSelection: (() -> Void)?
    var handleAskUnderlineHover: ((CGPoint) -> Void)?
    var handleAskUnderlineClick: ((CGPoint) -> Bool)?
    var onPointerEvent: ((CGPoint?, UIGestureRecognizer.State) -> Void)?
    private var adaptsDocumentColors = true
    private var documentAppearanceMode: WeiBeiAppearanceMode = .paper
    override init(frame: CGRect) {
        super.init(frame: frame)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pointer(_:)))
        pan.cancelsTouchesInView = false; pan.delegate = self
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = self
        addGestureRecognizer(tap)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func pointer(_ gesture: UIGestureRecognizer) {
        onPointerEvent?(gesture.location(in: self), gesture.state)
        reportCurrentSelection?()
    }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        _ = handleAskUnderlineClick?(point)
        onPointerEvent?(point, .ended)
        reportCurrentSelection?()
    }
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) { handleAskUnderlineHover?(gesture.location(in: self)) }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        onPointerEvent?(nil, .began)
        super.pressesBegan(presses, with: event)
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)
        onPointerEvent?(nil, .ended)
    }
    func configureDocumentColorAdaptation(enabled: Bool, appearanceMode: WeiBeiAppearanceMode) {
        guard adaptsDocumentColors != enabled || documentAppearanceMode != appearanceMode else { return }
        adaptsDocumentColors = enabled; documentAppearanceMode = appearanceMode
        layoutDocumentView()
        func redraw(_ view: UIView) { view.setNeedsDisplay(); view.subviews.forEach(redraw) }
        redraw(self)
    }
    override func draw(_ page: PDFPage, to context: CGContext) {
        guard adaptsDocumentColors else { super.draw(page, to: context); return }
        context.saveGState()
        context.setFillColor(WeiBeiNativePalette.documentMaskFill(for: documentAppearanceMode).cgColor)
        context.fill(page.bounds(for: displayBox))
        context.setBlendMode(.multiply)
        page.draw(with: displayBox, to: context)
        context.restoreGState()
    }
}

final class PDFOCRPageOverlayView: UIView {
    private var lines: [OCRLine] = []
    init(page: PDFOCRPage, highlightedLineIndexes: Set<Int>, appearanceMode: WeiBeiAppearanceMode,
         onSelectionChange: @escaping (String, SelectionPopoverAnchor?, CGRect?) -> Void) {
        super.init(frame: .zero)
        backgroundColor = .clear
        lines = page.lines.enumerated().map { index, line in
            let view = OCRLine(text: line.text, box: line.boundingBox, onSelection: onSelectionChange)
            view.backgroundColor = highlightedLineIndexes.contains(index)
                ? WeiBeiNativePalette.selectionFill(for: appearanceMode).withAlphaComponent(0.28) : .clear
            view.tintColor = WeiBeiNativePalette.selectionFill(for: appearanceMode)
            addSubview(view)
            return view
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        for line in lines {
            let box = line.box
            line.frame = CGRect(x: box.minX * bounds.width, y: (1 - box.maxY) * bounds.height,
                width: max(24, box.width * bounds.width), height: max(12, box.height * bounds.height)).insetBy(dx: -1.5, dy: -1)
            line.font = .systemFont(ofSize: max(8, min(22, line.bounds.height * 0.72)))
        }
    }
    private final class OCRLine: UITextView, UITextViewDelegate {
        let box: CGRect
        let onSelection: (String, SelectionPopoverAnchor?, CGRect?) -> Void
        init(text: String, box: CGRect, onSelection: @escaping (String, SelectionPopoverAnchor?, CGRect?) -> Void) {
            self.box = box; self.onSelection = onSelection
            super.init(frame: .zero, textContainer: nil)
            self.text = text; isEditable = false; isSelectable = true; isScrollEnabled = false
            textColor = .clear; textContainerInset = .zero; textContainer.lineFragmentPadding = 0
            delegate = self
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let range = selectedTextRange, !range.isEmpty, let selected = self.text(in: range), let overlay = superview else {
                onSelection("", nil, nil); return
            }
            let rect = selectionRects(for: range).map(\.rect).reduce(CGRect.null) { $0.union($1) }
            guard !rect.isNull, overlay.bounds.width > 0, overlay.bounds.height > 0 else { return }
            let point = SelectionAnchorContentPoint.fromLocalPoint(CGPoint(x: rect.midX, y: rect.maxY), in: self)
            let local = convert(rect, to: overlay)
            let normalized = CGRect(x: local.minX / overlay.bounds.width, y: 1 - local.maxY / overlay.bounds.height,
                width: local.width / overlay.bounds.width, height: local.height / overlay.bounds.height)
            onSelection(selected, point, normalized)
        }
    }
}

struct SelectablePlainTextReader: UIViewRepresentable {
    var text: String
    var searchQuery: String
    var appearanceMode: WeiBeiAppearanceMode
    var underlineSnippets: [String]
    var onSelectionChange: (String, SelectionPopoverAnchor?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true; view.backgroundColor = .clear
        view.textContainerInset = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        view.delegate = context.coordinator
        updateUIView(view, context: context)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.parent.text != text || coordinator.parent.appearanceMode != appearanceMode
            || coordinator.parent.underlineSnippets != underlineSnippets || view.attributedText.length == 0
        coordinator.parent = self
        coordinator.suppressSelection = true
        defer { coordinator.suppressSelection = false }
        view.tintColor = WeiBeiNativePalette.selectionFill(for: appearanceMode)
        if changed {
            let attributed = NSMutableAttributedString(string: text, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: WeiBeiNativePalette.ink(for: appearanceMode)])
            for snippet in underlineSnippets {
                let needle = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
                guard needle.count >= 4 else { continue }
                var search = NSRange(location: 0, length: attributed.length)
                while search.length > 0 {
                    let found = (text as NSString).range(of: needle, range: search)
                    guard found.location != NSNotFound else { break }
                    attributed.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: weiBeiColor(red: 0.56, green: 0.16, blue: 0.12, alpha: 1)], range: found)
                    search = NSRange(location: NSMaxRange(found), length: attributed.length - NSMaxRange(found))
                }
            }
            let selected = view.selectedRange
            view.attributedText = attributed
            if NSMaxRange(selected) <= attributed.length { view.selectedRange = selected }
        }
        let query = ReaderSearch.cleaned(searchQuery)
        if coordinator.query != query {
            coordinator.query = query
            onSelectionChange("", nil)
            if let match = ReaderSearch.firstMatch(in: text, query: query) {
                view.selectedRange = match; view.scrollRangeToVisible(match)
            } else { view.selectedRange = NSRange(location: 0, length: 0) }
        }
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectablePlainTextReader
        var suppressSelection = false
        var query = ""
        init(_ parent: SelectablePlainTextReader) { self.parent = parent }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !suppressSelection else { return }
            guard let range = textView.selectedTextRange, !range.isEmpty, let text = textView.text(in: range) else {
                parent.onSelectionChange("", nil); return
            }
            let rect = textView.selectionRects(for: range).map(\.rect).reduce(CGRect.null) { $0.union($1) }
            let anchor = rect.isNull ? nil : SelectionAnchorContentPoint.fromLocalPoint(CGPoint(x: rect.midX, y: rect.maxY), in: textView)
            parent.onSelectionChange(text, anchor)
        }
    }
}

struct EscapeKeyBridge: View {
    var isEnabled = true
    var onEscape: () -> Void
    var body: some View {
        if isEnabled {
            Button(action: onEscape) { Color.clear.frame(width: 0, height: 0) }
                .buttonStyle(.plain).keyboardShortcut(.escape, modifiers: [])
                .accessibilityHidden(true)
        }
    }
}

enum WeiBeiQuietScrollers {
    static func configureRecursively(in view: UIView, hasVerticalScroller: Bool? = nil, hasHorizontalScroller: Bool? = nil) {
        if let scroll = view as? UIScrollView {
            if let hasVerticalScroller { scroll.showsVerticalScrollIndicator = hasVerticalScroller }
            if let hasHorizontalScroller { scroll.showsHorizontalScrollIndicator = hasHorizontalScroller }
        }
        view.subviews.forEach { configureRecursively(in: $0, hasVerticalScroller: hasVerticalScroller, hasHorizontalScroller: hasHorizontalScroller) }
    }
    static func flashRecursively(in view: UIView, repeatCount: Int = 0) {
        (view as? UIScrollView)?.flashScrollIndicators()
        view.subviews.forEach { flashRecursively(in: $0) }
    }
}
