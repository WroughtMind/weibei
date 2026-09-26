import Foundation
import XCTest
import ZIPFoundation
import WeiBeiCore

final class PowerPointReadingLocationTests: XCTestCase {
    func testVisibleSlideReadsEveryParagraphWithoutIncludingAnotherSlide() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PowerPointReadingLocation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ns = "http://schemas.openxmlformats.org"
        let rel = "\(ns)/officeDocument/2006/relationships"
        let parts = [
            "_rels/.rels": "<Relationships xmlns=\"\(ns)/package/2006/relationships\"><Relationship Id=\"main\" Type=\"\(rel)/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>",
            "ppt/presentation.xml": "<p:presentation xmlns:p=\"\(ns)/presentationml/2006/main\" xmlns:r=\"\(rel)\"><p:sldIdLst><p:sldId id=\"256\" r:id=\"first\"/><p:sldId id=\"257\" r:id=\"other\"/></p:sldIdLst></p:presentation>",
            "ppt/_rels/presentation.xml.rels": "<Relationships xmlns=\"\(ns)/package/2006/relationships\"><Relationship Id=\"first\" Type=\"\(rel)/slide\" Target=\"slides/slide1.xml\"/><Relationship Id=\"other\" Type=\"\(rel)/slide\" Target=\"slides/slide10.xml\"/></Relationships>",
            "ppt/slides/slide1.xml": "<p:sld xmlns:p=\"\(ns)/presentationml/2006/main\" xmlns:a=\"\(ns)/drawingml/2006/main\"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>本页第一段</a:t></a:r></a:p><a:p><a:r><a:t>本页第二段</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>",
            "ppt/slides/slide10.xml": "<p:sld xmlns:p=\"\(ns)/presentationml/2006/main\" xmlns:a=\"\(ns)/drawingml/2006/main\"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>别页不能混入</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>",
        ]
        let archive = try Archive(data: Data(), accessMode: .create)
        for (path, xml) in parts {
            let data = Data(xml.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count)) { offset, count in
                data.subdata(in: Int(offset)..<(Int(offset) + count))
            }
        }
        let url = root.appendingPathComponent("课件.pptx")
        try XCTUnwrap(archive.data).write(to: url)
        let item = StudyItem(id: "slides", title: "课件", subtitle: "", kind: .pptx,
                             urlPath: url.path, isSample: false)
        let index = CourseDocumentSearchIndex(databaseURL: root.appendingPathComponent("index.sqlite"))
        let reference = SourceReferenceTitle.parse("课件，章节标识：ppt/slides/slide1.xml，章节：第 1 页")
        let location = try XCTUnwrap(reference.sectionLocationID)
        let page = index.read(item: item, location: location)
        XCTAssertEqual(page.passages.map(\.text), ["本页第一段", "本页第二段"])
        XCTAssertEqual(page.passages.map(\.location), ["ppt/slides/slide1.xml#p0", "ppt/slides/slide1.xml#p1"])

        let paragraph = index.read(item: item, location: "\(location)#p1")
        XCTAssertEqual(paragraph.passages.map(\.text), ["本页第二段"])
        XCTAssertTrue(index.read(item: item, location: "ppt/slides/slide").passages.isEmpty)

        var cursor: String?
        var text = ""
        repeat {
            let chunk = index.read(item: item, location: location, cursor: cursor, maximumCharacters: 3)
            text += chunk.text ?? ""
            cursor = chunk.nextCursor
        } while cursor != nil && text.count < 100
        XCTAssertNil(cursor)
        XCTAssertEqual(text, "本页第一段本页第二段")
    }
}
