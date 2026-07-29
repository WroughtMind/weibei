import Foundation
import XCTest
@testable import WeiBeiCore

final class CourseDocumentSearchIndexTests: XCTestCase {
    /**
     * Verifies that a late Markdown section is indexed, persisted, and reusable after reopening.
     */
    func testMarkdownIndexPersistsLateMatchingSection() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("weibei-course-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let documentURL = root.appendingPathComponent("course.md")
        let token = "PERSISTENT_INDEX_TOKEN"
        try (String(repeating: "ordinary course paragraph\n\n", count: 1_500) + token)
            .write(to: documentURL, atomically: true, encoding: .utf8)
        let item = StudyItem(
            id: "file:\(documentURL.path)",
            title: "Course",
            subtitle: documentURL.lastPathComponent,
            kind: .markdown,
            urlPath: documentURL.path,
            isSample: false
        )
        let databaseURL = root.appendingPathComponent("search.sqlite3")
        let index = CourseDocumentSearchIndex(databaseURL: databaseURL)

        let initial = index.lookup(items: [item], query: token)[item.id]

        XCTAssertTrue(initial?.text?.contains(token) == true)
        XCTAssertEqual(initial?.isTruncated, true)

        let reopened = CourseDocumentSearchIndex(databaseURL: databaseURL)
        let persisted = reopened.lookup(items: [item], query: token)[item.id]
        XCTAssertTrue(persisted?.text?.contains(token) == true)
        XCTAssertEqual(persisted?.isTruncated, true)
    }

    /**
     * Verifies that changed file content invalidates stale matches during foreground lookup.
     */
    func testLookupRefreshesChangedTextFile() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("weibei-course-refresh-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let documentURL = root.appendingPathComponent("lesson.txt")
        try "ORIGINAL_RATE_TOKEN".write(to: documentURL, atomically: true, encoding: .utf8)
        var item = StudyItem(
            id: "file:\(documentURL.path)",
            title: "Lesson",
            subtitle: documentURL.lastPathComponent,
            kind: .text,
            urlPath: documentURL.path,
            isSample: false
        )
        let index = CourseDocumentSearchIndex(databaseURL: root.appendingPathComponent("search.sqlite3"))
        XCTAssertTrue(index.lookup(items: [item], query: "ORIGINAL_RATE_TOKEN")[item.id]?.text?.contains("ORIGINAL_RATE_TOKEN") == true)

        try "REVISED_RATE_TOKEN with longer content".write(to: documentURL, atomically: true, encoding: .utf8)
        item.subtitle = "lesson-updated.txt"
        let revised = index.lookup(items: [item], query: "REVISED_RATE_TOKEN")[item.id]

        XCTAssertTrue(revised?.text?.contains("REVISED_RATE_TOKEN") == true)
        XCTAssertNil(index.lookup(items: [item], query: "ORIGINAL_RATE_TOKEN")[item.id]?.text)
    }

    /**
     * Verifies that non-file workspace items cannot leak into the persistent search index.
     */
    func testLookupIgnoresItemsWithoutBackingFiles() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-course-memory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = StudyItem(
            id: "sample:lesson",
            title: "Sample",
            subtitle: "Bundled",
            kind: .markdown,
            urlPath: nil,
            isSample: true
        )
        let index = CourseDocumentSearchIndex(databaseURL: root.appendingPathComponent("search.sqlite3"))

        XCTAssertTrue(index.lookup(items: [item], query: "Sample").isEmpty)
    }
}
