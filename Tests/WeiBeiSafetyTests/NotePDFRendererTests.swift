import PDFKit
import XCTest
@testable import WeiBei

final class NotePDFRendererTests: XCTestCase {
    @MainActor
    func testExportPreservesTableAndLongParagraphAcrossPhysicalPages() async throws {
        let rows = (0..<40).map { "| Row\($0)End | 跨页表格 |" }.joined(separator: "\n")
        let paragraph = (0..<30).map {
            "Part\($0)End " + String(repeating: "文字可以从 PDF 中选择。", count: 5)
        }.joined(separator: " ")
        let source = NotePDFSource(
            title: "FileOnlyTitle",
            markdown: """
                ## 导出检查

                | 记录 | 内容 |
                | --- | --- |
                \(rows)

                \(paragraph)

                [来源](https://example.org/)
                """,
            baseURL: nil,
            attachments: nil
        )
        var options = NotePDFOptions(theme: .paper, textScale: 1)
        options.paper = .a5
        options.landscape = true

        let data = try await NotePDFRenderer().render(source, options: options, language: .chinese)
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 1)
        let pages = (0..<document.pageCount).compactMap(document.page(at:))
        let text = pages.compactMap(\.string).joined(separator: "\n")
        XCTAssertFalse(text.contains(source.title), "The filename must not become an extra heading")
        for token in (0..<40).map({ "Row\($0)End" }) + (0..<30).map({ "Part\($0)End" }) {
            XCTAssertEqual(text.components(separatedBy: token).count, 2, token)
        }
        for (index, page) in pages.enumerated() {
            XCTAssertEqual(page.bounds(for: .mediaBox).width, options.pageSize.width, accuracy: 0.1)
            XCTAssertEqual(page.bounds(for: .mediaBox).height, options.pageSize.height, accuracy: 0.1)
            XCTAssertTrue(page.string?.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("\n\(index + 1)") == true)
        }
        let links = pages.flatMap(\.annotations).compactMap { ($0.action as? PDFActionURL)?.url }
        XCTAssertTrue(links.contains(URL(string: "https://example.org/")!))
    }
}
