import ImageIO
import XCTest
import UniformTypeIdentifiers
import WebKit
@testable import WeiBei
@testable import WeiBeiCore

private final class RecordingURLSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    private let lock = NSLock()
    private var completions = 0

    init(request: URLRequest) {
        self.request = request
    }

    func didReceive(_ response: URLResponse) {}
    func didReceive(_ data: Data) {}
    func didFinish() { recordCompletion() }
    func didFailWithError(_ error: Error) { recordCompletion() }

    var completionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions
    }

    private func recordCompletion() {
        lock.lock()
        completions += 1
        lock.unlock()
    }
}

final class MarkdownResourceSafetyTests: XCTestCase {
    func testRootedImageReadRejectsOversizeAndSymlinkEscape() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let root = fixture.appendingPathComponent("course", isDirectory: true)
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        let outside = fixture.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        let allowed = assets.appendingPathComponent("allowed.png")
        try Data([1, 2, 3]).write(to: allowed)
        XCTAssertEqual(
            try CourseProjectFileWorker.readBoundedRegularFile(
                at: allowed,
                inside: root,
                maximumByteCount: 3
            ),
            Data([1, 2, 3])
        )
        XCTAssertThrowsError(
            try CourseProjectFileWorker.readBoundedRegularFile(
                at: allowed,
                inside: root,
                maximumByteCount: 2
            )
        )

        let secret = outside.appendingPathComponent("secret.png")
        try Data([9]).write(to: secret)
        let leafLink = assets.appendingPathComponent("leaf.png")
        try FileManager.default.createSymbolicLink(
            at: leafLink,
            withDestinationURL: secret
        )
        XCTAssertThrowsError(
            try CourseProjectFileWorker.readBoundedRegularFile(
                at: leafLink,
                inside: root,
                maximumByteCount: 3
            )
        )

        let directoryLink = root.appendingPathComponent("linked-assets")
        try FileManager.default.createSymbolicLink(
            at: directoryLink,
            withDestinationURL: outside
        )
        XCTAssertThrowsError(
            try CourseProjectFileWorker.readBoundedRegularFile(
                at: directoryLink.appendingPathComponent("secret.png"),
                inside: root,
                maximumByteCount: 3
            )
        )
    }

    func testCourseMarkdownReadRejectsFilePastExistingTextBudget() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let markdownURL = fixture.appendingPathComponent("oversized.md")
        XCTAssertTrue(FileManager.default.createFile(atPath: markdownURL.path, contents: nil))
        let handle = try FileHandle(forWritingTo: markdownURL)
        try handle.truncate(
            atOffset: UInt64(CourseProjectFileWorker.markdownMaximumByteCount + 1)
        )
        try handle.close()
        let identity = try XCTUnwrap(CourseProjectFileWorker.identity(at: markdownURL))

        do {
            _ = try await CourseProjectFileWorker().readMarkdown(
                at: markdownURL,
                expectedIdentity: identity
            )
            XCTFail("oversized Markdown should not be loaded")
        } catch CourseProjectFileWorkerError.fileTooLarge {
            // Expected: the bounded reader rejects before allocating the file.
        }
    }

    func testRemoteImageRequestAllowsPublicHTTPSWithoutAmbientCredentials() throws {
        let request = try XCTUnwrap(
            MarkdownImageSchemeHandler.sanitizedRemoteRequest(
                for: try XCTUnwrap(URL(string: "https://8.8.8.8/image.png"))
            )
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/*")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
        XCTAssertFalse(request.httpShouldHandleCookies)

        for value in [
            "http://8.8.8.8/image.png",
            "https://127.0.0.1/image.png",
            "https://10.0.0.1/image.png",
            "https://169.254.169.254/latest/meta-data",
            "https://[::1]/image.png",
            "https://user:password@8.8.8.8/image.png",
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(
                MarkdownImageSchemeHandler.sanitizedRemoteRequest(for: url),
                value
            )
        }
    }

    @MainActor
    func testRemoteImageSessionInvalidationBreaksDelegateRetention() async throws {
        var components = URLComponents()
        components.scheme = "weibeiimage"
        components.host = "resource"
        components.queryItems = [
            URLQueryItem(name: "src", value: "https://8.8.8.8:65535/image.png")
        ]
        let task = RecordingURLSchemeTask(
            request: URLRequest(url: try XCTUnwrap(components.url))
        )
        var handler: MarkdownImageSchemeHandler? = MarkdownImageSchemeHandler()
        weak var weakHandler = handler
        handler?.webView(WKWebView(), start: task)

        for _ in 0..<100 {
            if handler?.hasActiveRemoteSession == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(handler?.hasActiveRemoteSession == true)

        let completionsBeforeInvalidation = task.completionCount
        handler?.invalidate()
        handler?.invalidate()
        handler = nil
        for _ in 0..<100 {
            if weakHandler == nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(weakHandler)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(task.completionCount, completionsBeforeInvalidation)
    }

    func testAttachmentStoreRejectsOversizedImageBeforeWriting() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let attachments = fixture.appendingPathComponent("attachments")
        XCTAssertThrowsError(
            try MarkdownAttachmentStore.save(
                data: Data(count: MarkdownAttachmentStore.maximumImageByteCount + 1),
                originalName: "large.png",
                mime: "image/png",
                attachmentDirectory: attachments,
                markdownBaseURLString: fixture.absoluteString
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachments.path))
    }

    func testAttachmentStoreCountsEveryFrameAtItsActualSize() throws {
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(
                data,
                UTType.tiff.identifier as CFString,
                2,
                nil
            )
        )
        CGImageDestinationAddImage(destination, try makeImage(width: 1, height: 1), nil)
        CGImageDestinationAddImage(destination, try makeImage(width: 4, height: 4), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let source = try XCTUnwrap(CGImageSourceCreateWithData(data, nil))
        XCTAssertFalse(
            MarkdownAttachmentStore.decodedPixelsAreWithinLimit(
                source,
                maximumPixelCount: 16
            )
        )
        XCTAssertTrue(
            MarkdownAttachmentStore.decodedPixelsAreWithinLimit(
                source,
                maximumPixelCount: 17
            )
        )
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        return try XCTUnwrap(context.makeImage())
    }

    private func makeFixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-markdown-resource-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
