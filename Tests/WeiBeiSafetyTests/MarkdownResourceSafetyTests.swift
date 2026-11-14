import ImageIO
import XCTest
import UniformTypeIdentifiers
import WebKit
@testable import WeiBei
@testable import WeiBeiCore

private final class RecordingURLSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest

    init(request: URLRequest) {
        self.request = request
    }

    func didReceive(_ response: URLResponse) {}
    func didReceive(_ data: Data) {}
    func didFinish() {}
    func didFailWithError(_ error: Error) {}
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

        handler?.invalidate()
        handler?.invalidate()
        handler = nil
        for _ in 0..<100 {
            if weakHandler == nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(weakHandler)
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
        XCTAssertEqual(MarkdownAttachmentStore.largestFramePixelCount(source), 16)
    }

    func testAttachmentStoreDownscalesOversizedStillImage() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let attachments = fixture.appendingPathComponent("attachments")
        let pixels = try encodedJPEG(width: 8_064, height: 6_048)
        let saved = try MarkdownAttachmentStore.save(
            data: pixels,
            originalName: "iphone.heic",
            mime: "image/jpeg",
            attachmentDirectory: attachments,
            markdownBaseURLString: fixture.absoluteString
        )
        let file = fixture.appendingPathComponent(saved.src)
        let stored = try Data(contentsOf: file)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(stored as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue)
        let height = try XCTUnwrap((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue)
        XCTAssertLessThanOrEqual(max(width, height), MarkdownAttachmentStore.downscaledImageLongEdge)
        XCTAssertTrue(saved.src.hasSuffix(".jpg"))
        XCTAssertLessThanOrEqual(stored.count, MarkdownAttachmentStore.maximumImageByteCount)
    }

    func testAttachmentStoreKeepsLongAnimationWhenEachFrameFits() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let attachments = fixture.appendingPathComponent("attachments")
        let frame = try makeImage(width: 2_000, height: 2_000)
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 11, nil)
        )
        for _ in 0..<11 {
            CGImageDestinationAddImage(destination, frame, nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let saved = try MarkdownAttachmentStore.save(
            data: data as Data,
            originalName: "long.gif",
            mime: "image/gif",
            attachmentDirectory: attachments,
            markdownBaseURLString: fixture.absoluteString
        )
        XCTAssertTrue(saved.src.hasSuffix(".gif"))
        let stored = try Data(contentsOf: fixture.appendingPathComponent(saved.src))
        XCTAssertEqual(stored, data as Data)
        XCTAssertEqual(MarkdownAttachmentStore.validatedImageMIMEType(data: stored,
            suggestedMIMEType: "image/gif", allowsSVG: false), "image/gif")
        let handler = MarkdownImageSchemeHandler()
        handler.update(markdownBaseURLString: URL(fileURLWithPath: fixture.path, isDirectory: true).absoluteString, attachmentDirectory: attachments,
            appearanceMode: .paper, interfaceLanguage: .chinese)
        let loaded: Data? = await withCheckedContinuation { continuation in
            handler.loadImage(source: saved.src) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(loaded, stored)
    }

    func testStoredMultiFrameImageAboveStillImageBudgetLoadsThroughSchemeHandler() async throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let attachments = fixture.appendingPathComponent("attachments")
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 2, nil))
        let frame = try makeImage(width: 3_000, height: 1_000)
        for _ in 0..<2 {
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 1],
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertGreaterThan(data.length, MarkdownAttachmentStore.maximumImageByteCount)
        let saved = try MarkdownAttachmentStore.save(data: data as Data, originalName: "pages.tiff",
            mime: "image/tiff", attachmentDirectory: attachments, markdownBaseURLString: fixture.absoluteString)
        let handler = MarkdownImageSchemeHandler()
        handler.update(markdownBaseURLString: URL(fileURLWithPath: fixture.path, isDirectory: true).absoluteString, attachmentDirectory: attachments,
            appearanceMode: .paper, interfaceLanguage: .chinese)
        let loaded: Data? = await withCheckedContinuation { continuation in
            handler.loadImage(source: saved.src) { continuation.resume(returning: $0) }
        }
        XCTAssertEqual(loaded, data as Data)
    }

    func testAttachmentStoreRasterizesSVGToPNG() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let attachments = fixture.appendingPathComponent("attachments")
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="12">\
        <rect width="24" height="12" fill="red"/></svg>
        """.utf8)
        let saved = try MarkdownAttachmentStore.save(
            data: svg,
            originalName: "diagram.svg",
            mime: "image/svg+xml",
            attachmentDirectory: attachments,
            markdownBaseURLString: fixture.absoluteString
        )
        XCTAssertTrue(saved.src.hasSuffix(".png"))
        let stored = try Data(contentsOf: fixture.appendingPathComponent(saved.src))
        XCTAssertEqual(Array(stored.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testAttachmentStoreRejectsUndecodableImage() throws {
        let fixture = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let attachments = fixture.appendingPathComponent("attachments")
        XCTAssertThrowsError(
            try MarkdownAttachmentStore.save(
                data: Data([0x00, 0x01, 0x02, 0x03]),
                originalName: "broken.png",
                mime: "image/png",
                attachmentDirectory: attachments,
                markdownBaseURLString: fixture.absoluteString
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: attachments.path))
    }

    private func encodedJPEG(width: Int, height: Int) throws -> Data {
        let image = try makeImage(width: width, height: height)
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.8,
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
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
            .appendingPathComponent("weibei-markdown-resource-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
