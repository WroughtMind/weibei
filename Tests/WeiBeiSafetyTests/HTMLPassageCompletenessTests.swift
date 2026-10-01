import Foundation
import XCTest
import WeiBeiCore

final class HTMLPassageCompletenessTests: XCTestCase {
    func testHeadinglessHTMLKeepsTablesDivsAndParagraphsInFullReadAndSearch() throws {
        let html = """
        <html><body><main><p>paragraphMarker Intro</p>
        <div>divMarker Other explanation</div>
        <table><tr><td>tableMarker Exam answer</td></tr></table>
        <h5>smallHeadingMarker Appendix</h5></main></body></html>
        """
        try withDocument(html) { item, index in
            let full = index.read(item: item, location: nil)
            XCTAssertFalse(full.isTruncated)
            XCTAssertEqual(full.passages.count, 1, "Exact block aliases must not duplicate normal reads")
            for marker in ["paragraphMarker", "divMarker", "tableMarker", "smallHeadingMarker"] {
                XCTAssertTrue(full.text?.contains(marker) == true, marker)
                let matches = index.searchPassages(item: item, query: marker).passages
                XCTAssertEqual(matches.count, 1, marker)
                XCTAssertTrue(matches.first?.text.contains(marker) == true, marker)
                XCTAssertTrue(index.lookup(items: [item], query: marker)[item.id]?.text?.contains(marker) == true, marker)
            }
            let block = try XCTUnwrap(CourseDocumentSearchIndex.htmlPassages(html)
                .first { $0.location.hasPrefix("html-block-") })
            let exact = index.read(item: item, location: block.location)
            XCTAssertEqual(exact.passages.map(\.text), ["paragraphMarker Intro"])
        }
    }

    func testQuotedAttributeAndOptionalEndTagsHaveExactParsedBlockLocations() throws {
        let fixtures = [
            (#"<main><p data-expression="x > y">Visible paragraph</p></main>"#,
             ["Visible paragraph"]),
            ("<main><p>First paragraph<p>Second paragraph</main>",
             ["First paragraph", "Second paragraph"]),
            ("<main><ul><li>First list item<li>Second list item</ul></main>",
             ["First list item", "Second list item"]),
        ]
        for (html, expected) in fixtures {
            try withDocument(html) { item, index in
                let blocks = CourseDocumentSearchIndex.htmlPassages(html)
                    .filter { $0.location.hasPrefix("html-block-") }
                XCTAssertEqual(blocks.map(\.text), expected)
                for block in blocks {
                    XCTAssertEqual(index.read(item: item, location: block.location).passages.map(\.text), [block.text])
                }
                if expected == ["Visible paragraph"] {
                    // The reader's fingerprint of parsed text, rather than attribute text.
                    XCTAssertEqual(blocks.first?.location, "html-block-417ce375")
                }
            }
        }
    }

    func testParsedBlockAliasesUseLeafTextAndDocumentDuplicateOrder() {
        let html = """
        <nav><p>Same paragraph</p></nav><main><p hidden>Same paragraph</p>
        <p>Same paragraph</p><ul><li><p>A&amp;B&nbsp; C <strong>inline</strong> text</p></li></ul>
        <pre>  preformatted\n   code  </pre><p>Same paragraph</p></main>
        """
        let blocks = CourseDocumentSearchIndex.htmlPassages(html)
            .filter { $0.location.hasPrefix("html-block-") }
        XCTAssertEqual(blocks.map(\.text), ["Same paragraph", "Same paragraph", "Same paragraph",
                                             "A&B C inline text", "preformatted code", "Same paragraph"])
        guard let first = blocks.first?.location, blocks.count == 6 else { return }
        XCTAssertEqual(blocks[1].location, first + "-dup-2")
        XCTAssertEqual(blocks[2].location, first + "-dup-3")
        XCTAssertEqual(blocks[5].location, first + "-dup-4")
    }

    private func withDocument(_ html: String, verify: (StudyItem, CourseDocumentSearchIndex) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("weibei-html-passages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("lesson.html")
        try Data(html.utf8).write(to: url)
        let item = StudyItem(id: "file:\(url.path)", title: "HTML lesson", subtitle: url.lastPathComponent,
                             kind: .html, urlPath: url.path, isSample: false)
        let index = CourseDocumentSearchIndex(databaseURL: root.appendingPathComponent("search.sqlite3"))
        try verify(item, index)
    }
}
