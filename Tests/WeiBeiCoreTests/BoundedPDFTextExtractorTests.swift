import Foundation
import XCTest
@testable import WeiBeiCore

final class BoundedPDFTextExtractorTests: XCTestCase {
    /**
     * Verifies input limits before any worker process is launched.
     */
    func testRejectsInvalidPageAndCharacterBounds() {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist.pdf")

        XCTAssertNil(BoundedPDFTextExtractor.pages(from: missing, pageIndexes: [], maximumCharactersPerPage: 1_000))
        XCTAssertNil(BoundedPDFTextExtractor.pages(from: missing, pageIndexes: [-1], maximumCharactersPerPage: 1_000))
        XCTAssertNil(BoundedPDFTextExtractor.pages(from: missing, pageIndexes: Array(0..<17), maximumCharactersPerPage: 1_000))
        XCTAssertNil(BoundedPDFTextExtractor.pages(from: missing, pageIndexes: [0], maximumCharactersPerPage: 0))
        XCTAssertNil(BoundedPDFTextExtractor.pages(from: missing, pageIndexes: [0], maximumCharactersPerPage: 1_000_001))
    }
}
