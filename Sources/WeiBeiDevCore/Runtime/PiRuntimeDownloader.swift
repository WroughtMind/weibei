import Foundation

/// Downloads PI release archives to a caller-owned staging URL.
public protocol PiRuntimeDownloading: Sendable {
    /// Downloads a remote archive and atomically publishes it at the destination.
    ///
    /// - Parameters:
    ///   - sourceURL: Release archive URL.
    ///   - destinationURL: File URL that must contain the completed download on success.
    func download(from sourceURL: URL, to destinationURL: URL) async throws
}

/// A PI archive downloader backed by `URLSession`.
public struct URLSessionPiRuntimeDownloader: PiRuntimeDownloading {
    private let session: URLSession

    /// Creates a URLSession-backed downloader.
    ///
    /// - Parameter session: Session used for the release download.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Downloads a release archive with URLSession and publishes it at the destination.
    public func download(from sourceURL: URL, to destinationURL: URL) async throws {
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 300
        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP status \(status)"])
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }
}
