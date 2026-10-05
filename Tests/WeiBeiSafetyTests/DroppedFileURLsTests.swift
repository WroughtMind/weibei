import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import WeiBei

final class DroppedFileURLsTests: XCTestCase {
    private let source = URL(fileURLWithPath: "/tmp/拖入讲义.pdf")

    func testFileAddressAsStringReachesImport() {
        assertDelivered(NSItemProvider(item: source.absoluteString as NSString,
            typeIdentifier: UTType.fileURL.identifier))
    }

    func testFileAddressAsURLReachesImport() {
        assertDelivered(NSItemProvider(item: source as NSURL,
            typeIdentifier: UTType.fileURL.identifier))
    }

    func testFileAddressAsDataReachesImport() {
        assertDelivered(NSItemProvider(item: source.dataRepresentation as NSData,
            typeIdentifier: UTType.fileURL.identifier))
    }

    func testRejectedFileAddressStillCompletesWithFailure() {
        let completed = expectation(description: "Rejected drop reports a failure")
        XCTAssertTrue(WeiBeiDroppedFileURLs.load([
            NSItemProvider(item: "https://example.com/lecture.pdf" as NSString,
                typeIdentifier: UTType.fileURL.identifier)
        ]) { result in
            XCTAssertTrue(result.urls.isEmpty)
            XCTAssertTrue(result.securityScopedURLs.isEmpty)
            XCTAssertEqual(result.failures.count, 1)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 3)
    }

    func testProviderFailureIsReportedInsteadOfBeingSwallowed() {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            completion(nil, NSError(domain: "DroppedFileURLsTests", code: 1))
            return nil
        }
        let completed = expectation(description: "Provider failure completes")
        XCTAssertTrue(WeiBeiDroppedFileURLs.load([provider]) { result in
            XCTAssertTrue(result.urls.isEmpty)
            XCTAssertEqual(result.failures.count, 1)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 3)
    }

    func testMixedDropKeepsValidFilesAndReportsRejectedItem() {
        let completed = expectation(description: "Mixed drop is accounted for")
        XCTAssertTrue(WeiBeiDroppedFileURLs.load([
            NSItemProvider(item: source.absoluteString as NSString, typeIdentifier: UTType.fileURL.identifier),
            NSItemProvider(item: "https://example.com" as NSString, typeIdentifier: UTType.fileURL.identifier)
        ]) { result in
            defer { result.securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
            XCTAssertEqual(result.urls, [self.source])
            XCTAssertEqual(result.failures.count, 1)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 3)
    }

    func testTextReorderingIsNotClaimedAsAFileDrop() {
        XCTAssertFalse(WeiBeiDroppedFileURLs.load([NSItemProvider(object: "pane-id" as NSString)]) { _ in
            XCTFail("Plain text must not enter the file import flow")
        })
    }

    private func assertDelivered(_ provider: NSItemProvider) {
        let completed = expectation(description: "File address reaches import")
        XCTAssertTrue(WeiBeiDroppedFileURLs.load([provider]) { result in
            defer { result.securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
            XCTAssertEqual(result.urls, [self.source])
            XCTAssertTrue(result.failures.isEmpty)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 3)
    }
}
