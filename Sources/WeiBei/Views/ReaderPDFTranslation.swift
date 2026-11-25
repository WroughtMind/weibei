import PDFKit
import SwiftUI
import WeiBeiCore

struct ReaderPDFTranslationPage: Equatable {
    struct Paragraph: Identifiable, Equatable {
        let id: Int
        var text: String
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
            } else {
                result.append(Paragraph(id: result.count, text: text))
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
    let page: ReaderPDFTranslationPage
    let translations: [Int: String]
    let status: ReaderTranslationStatus
    let horizontalInset: CGFloat
    var retry: () -> Void
    @Binding var visibleParagraphID: Int?

    init(
        page: ReaderPDFTranslationPage,
        translations: [Int: String],
        status: ReaderTranslationStatus,
        horizontalInset: CGFloat,
        visibleParagraphID: Binding<Int?>,
        retry: @escaping () -> Void
    ) {
        self.page = page
        self.translations = translations
        self.status = status
        self.horizontalInset = horizontalInset
        _visibleParagraphID = visibleParagraphID
        self.retry = retry
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(page.paragraphs) { paragraph in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: paragraph.text)
                        if let translation = translations[paragraph.id] {
                            Text(verbatim: translation)
                                .foregroundStyle(WeiBeiTheme.ink.opacity(0.78))
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
        .weiBeiText(15)
        .lineSpacing(5)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
