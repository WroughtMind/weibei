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

    func testTransferredFileUsesExportedBytesInsteadOfProtectedSourceAddress() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = root.appendingPathComponent("传输副本.txt")
        let bytes = Data("微信传输的原始内容".utf8)
        try bytes.write(to: exported)
        let metadata = root.appendingPathComponent("无法直接访问/原始讲义.txt")
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.plainText.identifier,
            fileOptions: [], visibility: .all) { completion in
            completion(exported, false, nil)
            return nil
        }
        let completed = expectation(description: "Transferred file is retained for review")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: [metadata]) { result in
            defer { result.release() }
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(result.urls.first?.lastPathComponent, metadata.lastPathComponent)
            XCTAssertEqual(result.temporaryDirectories.count, 1)
            if let received = result.urls.first {
                XCTAssertEqual(try? Data(contentsOf: received), bytes)
                XCTAssertEqual(received.deletingLastPathComponent(), result.temporaryDirectories.first)
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.path))
            XCTAssertEqual(try? Data(contentsOf: exported), bytes)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }

    func testProviderTemporaryFileCanDisappearAfterCallbackWithoutLosingReviewCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("临时传输.txt")
        let bytes = Data("必须在提供器回调内保留".utf8)
        try bytes.write(to: source)
        let provider = EphemeralFileProvider(source: source)
        let completed = expectation(description: "Provider lifetime does not expire the review copy")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: [source]) { result in
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
            XCTAssertEqual(result.urls.first.flatMap { try? Data(contentsOf: $0) }, bytes)
            let directories = result.temporaryDirectories
            result.release()
            XCTAssertTrue(directories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }

    func testTransferredProviderFailureCompletesWithoutStaging() {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.plainText.identifier,
            fileOptions: [], visibility: .all) { completion in
            completion(nil, false, NSError(domain: "DroppedFileURLsTests", code: 2))
            return nil
        }
        let completed = expectation(description: "Failed file transfer is reported")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: [source]) { result in
            XCTAssertTrue(result.urls.isEmpty)
            XCTAssertTrue(result.temporaryDirectories.isEmpty)
            XCTAssertEqual(result.failures.count, 1)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }

    func testTransferredFolderPreservesFilesAndOriginalDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = root.appendingPathComponent("讲义.txt")
        let bytes = Data("文件夹中的内容".utf8)
        try bytes.write(to: sourceFile)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.folder.identifier,
            fileOptions: .openInPlace, visibility: .all) { completion in
            completion(root, true, nil)
            return nil
        }
        let completed = expectation(description: "Folder representation survives review")
        let metadata = URL(fileURLWithPath: "/protected/课程文件夹", isDirectory: true)
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: [metadata]) { result in
            defer { result.release() }
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(result.urls.first?.lastPathComponent, metadata.lastPathComponent)
            XCTAssertEqual(result.urls.first.flatMap { try? Data(contentsOf: $0.appendingPathComponent("讲义.txt")) }, bytes)
            XCTAssertEqual(try? Data(contentsOf: sourceFile), bytes)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }

    func testTransferredHTMLRetainsLocalImageBeforeLeavingProviderContext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let page = root.appendingPathComponent("网页.html")
        let original = "<html><body><img src=\"asset.png\"></body></html>"
        try original.write(to: page, atomically: true, encoding: .utf8)
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("asset.png"))
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.html.identifier,
            fileOptions: .openInPlace, visibility: .all) { completion in
            completion(page, true, nil)
            return nil
        }
        let completed = expectation(description: "HTML keeps its received local image")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: [page]) { result in
            defer { result.release() }
            XCTAssertTrue(result.failures.isEmpty)
            let received = result.urls.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            XCTAssertTrue(received?.contains("data:image/png;base64,") == true)
            XCTAssertEqual(try? String(contentsOf: page, encoding: .utf8), original)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
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

private final class EphemeralFileProvider: NSItemProvider, @unchecked Sendable {
    let source: URL
    init(source: URL) {
        self.source = source
        super.init()
        registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(Data(), nil)
            return nil
        }
    }
    override func loadInPlaceFileRepresentation(forTypeIdentifier typeIdentifier: String,
        completionHandler: @escaping (URL?, Bool, Error?) -> Void) -> Progress {
        completionHandler(source, false, nil)
        try? FileManager.default.removeItem(at: source)
        return Progress(totalUnitCount: 1)
    }
}
