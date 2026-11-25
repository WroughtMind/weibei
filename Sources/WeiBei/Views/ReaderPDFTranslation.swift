import PDFKit
import SwiftUI
import WeiBeiCore
#if targetEnvironment(macCatalyst)
import UIKit
#else
import AppKit
#endif

struct ReaderPDFTranslationPage: Equatable {
    struct Paragraph: Identifiable, Equatable {
        let id: Int
        var text: String
        var sourceRects: [SelectionRect]
    }

    let index: Int
    let paragraphs: [Paragraph]

    var translatableParagraphs: [Paragraph] {
        paragraphs.filter { $0.text.contains(where: \.isLetter) }
    }

    init(page: PDFPage, index: Int, ocr: PDFOCRPage?) {
        self.index = index
        let bounds = page.bounds(for: .mediaBox)
        let lines: [(text: String, rect: CGRect)]
        if let ocr {
            lines = ocr.lines.map { line in
                let box = line.boundingBox
                return (line.text, CGRect(
                    x: bounds.minX + box.minX * bounds.width,
                    y: bounds.minY + box.minY * bounds.height,
                    width: box.width * bounds.width,
                    height: box.height * bounds.height
                ))
            }
        } else {
            lines = (page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine() ?? []).compactMap { line in
                guard let text = line.string else { return nil }
                return (text, line.bounds(for: page))
            }
        }

        // PDFKit supplies reading order. Combine wrapped lines without joining
        // columns, headings or lines separated by a paragraph gap.
        var result: [Paragraph] = []
        var previous: CGRect?
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.rect.isEmpty, !text.isEmpty else { continue }
            if let previous,
               Self.continuesParagraph(from: previous, to: line.rect),
               let last = result.indices.last {
                if result[last].text.hasSuffix("\u{00AD}") {
                    result[last].text.removeLast()
                    result[last].text += text
                } else {
                    result[last].text += " " + text
                }
                result[last].sourceRects.append(SelectionRect(line.rect))
            } else {
                result.append(Paragraph(id: result.count, text: text, sourceRects: [SelectionRect(line.rect)]))
            }
            previous = line.rect
        }
        paragraphs = result
    }

    private static func continuesParagraph(from previous: CGRect, to next: CGRect) -> Bool {
        let lineHeight = max(previous.height, next.height)
        let gap = previous.minY - next.maxY
        return next.midY < previous.midY
            && min(previous.height, next.height) >= lineHeight * 0.75
            && gap < lineHeight * 0.65
            && abs(next.minX - previous.minX) <= lineHeight * 1.5
            && min(next.maxX, previous.maxX) > max(next.minX, previous.minX)
    }
}

struct ReaderPDFBilingualPage: View {
    @Environment(\.weiBeiTextScale) private var textScale
    @State private var selectedBlock: TextBlock?

    let page: ReaderPDFTranslationPage
    let translations: [Int: String]
    let status: ReaderTranslationStatus
    let horizontalInset: CGFloat
    let appearanceMode: WeiBeiAppearanceMode
    let isActive: Bool
    var onSelectionChange: (String, SelectionPopoverAnchor?, PDFSelectionAnchor?) -> Void
    var retry: () -> Void
    @Binding var visibleParagraphID: Int?

    init(
        page: ReaderPDFTranslationPage,
        translations: [Int: String],
        status: ReaderTranslationStatus,
        horizontalInset: CGFloat,
        appearanceMode: WeiBeiAppearanceMode,
        isActive: Bool,
        visibleParagraphID: Binding<Int?>,
        onSelectionChange: @escaping (String, SelectionPopoverAnchor?, PDFSelectionAnchor?) -> Void,
        retry: @escaping () -> Void
    ) {
        self.page = page
        self.translations = translations
        self.status = status
        self.horizontalInset = horizontalInset
        self.appearanceMode = appearanceMode
        self.isActive = isActive
        _visibleParagraphID = visibleParagraphID
        self.onSelectionChange = onSelectionChange
        self.retry = retry
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(page.paragraphs) { paragraph in
                    VStack(alignment: .leading, spacing: 8) {
                        selectableText(paragraph.text, in: paragraph)
                        if let translation = translations[paragraph.id] {
                            selectableText(translation, in: paragraph, isTranslation: true)
                                .padding(.leading, 12)
                                .overlay(alignment: .leading) {
                                    Rectangle()
                                        .fill(WeiBeiTheme.accent.opacity(0.45))
                                        .frame(width: 2)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(paragraph.id)
                }
                if case let .failed(problem) = status {
                    ReaderTranslationProblemView(problem: problem, offersSettings: true, retry: retry)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, horizontalInset)
            .padding(.top, 56)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $visibleParagraphID, anchor: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isActive) { _, active in
            if !active { clearSelection() }
        }
        .onDisappear(perform: clearSelection)
    }

    private struct TextBlock: Equatable {
        let paragraphID: Int
        let isTranslation: Bool
    }

    private func selectableText(_ text: String, in paragraph: ReaderPDFTranslationPage.Paragraph,
                                isTranslation: Bool = false) -> some View {
        let block = TextBlock(paragraphID: paragraph.id, isTranslation: isTranslation)
        let color = WeiBeiNativePalette.ink(for: appearanceMode)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        let content = NSAttributedString(string: text, attributes: [
            .font: WeiBeiPlatformFont.systemFont(ofSize: 15 * textScale),
            .foregroundColor: isTranslation ? color.withAlphaComponent(0.78) : color,
            .paragraphStyle: style
        ])
        return ReaderPDFSelectableParagraph(content: content) { text, anchor in
            if isActive, let anchor, !text.isEmpty {
                selectedBlock = block
                // Both selections refer to the source paragraph on the PDF page.
                let source = PDFSelectionAnchor(pageIndex: page.index, lineRects: paragraph.sourceRects)
                onSelectionChange(text, anchor, source)
            } else if selectedBlock == block {
                clearSelection()
            }
        }
        .onDisappear {
            if selectedBlock == block { clearSelection() }
        }
    }

    private func clearSelection() {
        guard selectedBlock != nil else { return }
        selectedBlock = nil
        onSelectionChange("", nil, nil)
    }
}

#if targetEnvironment(macCatalyst)
private struct ReaderPDFSelectableParagraph: UIViewRepresentable {
    let content: NSAttributedString
    var onSelectionChange: (String, SelectionPopoverAnchor?) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.contentInsetAdjustmentBehavior = .never
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.attributedText?.isEqual(to: content) != true {
            view.delegate = nil
            let selection = view.text == content.string ? view.selectedRange : nil
            view.attributedText = content
            if let selection { view.selectedRange = selection }
            view.delegate = context.coordinator
        }
        context.coordinator.onSelectionChange = onSelectionChange
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let height = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: ceil(height))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onSelectionChange: (String, SelectionPopoverAnchor?) -> Void = { _, _ in }

        func textViewDidChangeSelection(_ view: UITextView) {
            guard let range = view.selectedTextRange, !range.isEmpty, let text = view.text(in: range) else {
                onSelectionChange("", nil)
                return
            }
            let rect = view.selectionRects(for: range).map(\.rect).reduce(CGRect.null) { $0.union($1) }
            let anchor = rect.isNull ? nil : SelectionAnchorContentPoint.fromLocalPoint(
                CGPoint(x: rect.midX, y: rect.maxY), in: view
            )
            onSelectionChange(text, anchor)
        }
    }
}
#else
private struct ReaderPDFSelectableParagraph: NSViewRepresentable {
    let content: NSAttributedString
    var onSelectionChange: (String, SelectionPopoverAnchor?) -> Void

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        if let storage = view.textStorage, !storage.isEqual(to: content) {
            view.delegate = nil
            let selection = view.string == content.string ? view.selectedRange() : nil
            storage.setAttributedString(content)
            if let selection { view.setSelectedRange(selection) }
            view.delegate = context.coordinator
        }
        context.coordinator.onSelectionChange = onSelectionChange
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let height = content.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        return CGSize(width: width, height: ceil(height))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (String, SelectionPopoverAnchor?) -> Void = { _, _ in }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView,
                  let window = view.window else { return }
            let range = view.selectedRange()
            guard range.length > 0, let stringRange = Range(range, in: view.string) else {
                onSelectionChange("", nil)
                return
            }
            let rect = view.firstRect(forCharacterRange: range, actualRange: nil)
            let anchor = rect.isEmpty ? nil : SelectionAnchorContentPoint.fromScreenPoint(
                CGPoint(x: rect.midX, y: rect.minY), in: window
            )
            onSelectionChange(String(view.string[stringRange]), anchor)
        }
    }
}
#endif
