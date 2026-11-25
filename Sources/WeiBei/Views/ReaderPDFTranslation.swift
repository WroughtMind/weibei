import PDFKit
import SwiftUI
import WeiBeiCore

struct ReaderPDFTranslationPage: Equatable {
    struct Paragraph: Identifiable, Equatable {
        let id: Int
        var text: String
        var rect: CGRect
    }

    let index: Int
    let paragraphs: [Paragraph]

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
                result[last].rect = result[last].rect.union(line.rect)
            } else {
                result.append(Paragraph(id: result.count, text: text, rect: line.rect))
            }
            previous = line.rect
        }
        paragraphs = result.filter { $0.text.contains(where: \.isLetter) }
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

struct ReaderPDFTranslationReveal: Equatable {
    let id = UUID()
    let index: Int
    let rect: CGRect
}

struct ReaderPDFTranslationPane: View {
    @EnvironmentObject private var store: WorkspaceStore
    let page: ReaderPDFTranslationPage?
    let translations: [Int: String]
    let status: ReaderTranslationStatus
    var reveal: (ReaderPDFTranslationReveal) -> Void
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(page.map { store.ui("第 \($0.index + 1) 页译文", "Page \($0.index + 1) translation") }
                 ?? store.ui("译文", "Translation"))
                .weiBeiText(13, weight: .semibold)
            if let page, !translations.isEmpty { paragraphs(on: page).id(page.index) }
            switch status {
            case .idle, .translating:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.ui("正在翻译…", "Translating…"))
                }
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            case .noText:
                Text(store.ui("本页没有可翻译的文字。", "This page has no translatable text."))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            case let .failed(problem):
                ReaderTranslationProblemView(problem: problem, offersSettings: true, retry: retry)
            case .ready:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
        .weiBeiText(13)
        .padding(.top, 42)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WeiBeiTheme.paperRaised)
        .overlay(alignment: .leading) { Rectangle().fill(WeiBeiTheme.hairline).frame(width: 1) }
    }

    private func paragraphs(on page: ReaderPDFTranslationPage) -> some View {
        let completed = page.paragraphs.compactMap { paragraph in
            translations[paragraph.id].map { (paragraph, $0) }
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(completed, id: \.0.id) { paragraph, translated in
                    Button {
                        reveal(ReaderPDFTranslationReveal(index: page.index, rect: paragraph.rect))
                    } label: {
                        Text(verbatim: translated)
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(store.ui("定位到原文", "Show original passage"))
                    .accessibilityHint(store.ui("定位到原文", "Show original passage"))
                }
            }
        }
    }
}
