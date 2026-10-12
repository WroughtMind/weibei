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

    func testInternalWorkspaceDragDoesNotClaimAnExternalTextFile() {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all) { completion in
            completion(Data("讲义正文".utf8), nil); return nil
        }
        // This is the overlap that made generic String destinations eligible.
        XCTAssertTrue(provider.canLoadObject(ofClass: NSString.self))
        XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(WeiBeiWorkspaceDrag.contentType.identifier))
    }

    func testInternalWorkspaceDragKeepsItsIdentityThroughSystemTransfer() async throws {
        for payload in [WeiBeiWorkspaceDrag.course(UUID()), .item("note-id"), .relationMaterial("material-id")] {
            let provider = NSItemProvider()
            provider.register(payload)
            let received: WeiBeiWorkspaceDrag = try await withCheckedThrowingContinuation { continuation in
                provider.loadTransferable(type: WeiBeiWorkspaceDrag.self) { result in
                    continuation.resume(with: result)
                }
            }
            XCTAssertEqual(received, payload)
        }
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

    func testAddressOnlyProviderReceivesAccessibleLocalFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("桌面讲义.txt")
        let bytes = Data("本地文件地址来源".utf8)
        try bytes.write(to: source)
        let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let completed = expectation(description: "A file address is a valid external file representation")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: [source]) { result in
            defer { result.release() }
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(result.urls.first.flatMap { try? Data(contentsOf: $0) }, bytes)
            XCTAssertEqual(try? Data(contentsOf: source), bytes)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }

    func testAddressOnlyFolderPreservesTreeAndCleansReviewCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data("文件夹资料".utf8)
        let file = root.appendingPathComponent("讲义.txt")
        try bytes.write(to: file)
        let provider = NSItemProvider(item: root.absoluteString as NSString, typeIdentifier: UTType.fileURL.identifier)
        let completed = expectation(description: "A file-address folder retains its contents")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: [root]) { result in
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(result.urls.first.flatMap { try? Data(contentsOf: $0.appendingPathComponent("讲义.txt")) }, bytes)
            let directories = result.temporaryDirectories
            result.release()
            XCTAssertTrue(directories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
            XCTAssertEqual(try? Data(contentsOf: file), bytes)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }

    func testFailedExportDoesNotReadAnAddressRepresentationInstead() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("未交出的讲义.txt")
        try Data("不能使用来源信息代替失败的传输".utf8).write(to: file)
        let provider = NSItemProvider(item: file as NSURL, typeIdentifier: UTType.fileURL.identifier)
        provider.registerFileRepresentation(forTypeIdentifier: UTType.plainText.identifier,
            fileOptions: [], visibility: .all) { completion in
            completion(nil, false, CocoaError(.fileReadNoPermission)); return nil
        }
        let completed = expectation(description: "Export failure remains visible")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: [file]) { result in
            XCTAssertTrue(result.urls.isEmpty)
            XCTAssertTrue(result.temporaryDirectories.isEmpty)
            XCTAssertEqual(result.failures.count, 1)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }

    func testDelayedFileRepresentationDoesNotRequireAnExistingSourceAddress() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("松手后生成.txt")
        let bytes = Data("拖放时尚不存在的文件".utf8)
        let provider = NSItemProvider()
        provider.suggestedName = file.lastPathComponent
        provider.registerFileRepresentation(forTypeIdentifier: UTType.plainText.identifier,
            fileOptions: [], visibility: .all) { completion in
            do { try bytes.write(to: file); completion(file, false, nil) }
            catch { completion(nil, false, error) }
            return nil
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let completed = expectation(description: "Delayed export is staged before review")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([provider], sourceURLs: []) { result in
            defer { result.release() }
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(result.urls.first?.lastPathComponent, file.lastPathComponent)
            XCTAssertEqual(result.urls.first.flatMap { try? Data(contentsOf: $0) }, bytes)
            completed.fulfill()
        })
        wait(for: [completed], timeout: 5)
    }

    func testMixedDelayedAndAddressFilesKeepTheirOwnNamesAndBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let exported = root.appendingPathComponent("系统导出临时副本")
        let bytes = Data("延迟导出的文本讲义".utf8)
        try bytes.write(to: exported)
        let address = root.appendingPathComponent("现有资料.pdf")
        let addressBytes = Data("独立地址来源内容".utf8)
        try addressBytes.write(to: address)
        let delayed = NSItemProvider()
        delayed.suggestedName = "延迟讲义.txt"
        delayed.registerFileRepresentation(forTypeIdentifier: UTType.plainText.identifier,
            fileOptions: [], visibility: .all) { completion in
            completion(exported, false, nil); return nil
        }
        let local = NSItemProvider(item: address as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let completed = expectation(description: "Sparse source metadata does not rename another file")
        XCTAssertTrue(WeiBeiDroppedFileURLs.loadTransferredFiles([delayed, local], sourceURLs: [address]) { result in
            defer { result.release() }
            XCTAssertTrue(result.failures.isEmpty)
            XCTAssertEqual(result.urls.map(\.lastPathComponent), ["延迟讲义.txt", "现有资料.pdf"])
            XCTAssertEqual(result.urls.map { try? Data(contentsOf: $0) }, [bytes, addressBytes])
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
