import Foundation

/// Generated Rich Answer resources embedded by the desktop application.
public struct RichAnswerBuildProducts: Equatable, Sendable {
    /// HTML entry point loaded by the application.
    public let html: URL
    /// Bundled runtime JavaScript.
    public let javaScript: URL
    /// Bundled runtime stylesheet.
    public let stylesheet: URL

    /// Resolves generated Rich Answer product paths for a repository.
    ///
    /// - Parameter repository: Validated repository layout.
    public init(repository: RepositoryLayout) {
        let resources = repository.productSourcesDirectory.appendingPathComponent(
            "Resources",
            isDirectory: true
        )
        html = resources.appendingPathComponent("rich-answer.html")
        javaScript = resources.appendingPathComponent("rich-answer-runtime.js")
        stylesheet = resources.appendingPathComponent("rich-answer-runtime.css")
    }

    /// Verifies every required Rich Answer product exists and contains data.
    ///
    /// - Parameter fileManager: File manager used to inspect generated products.
    public func validate(fileManager: FileManager = .default) throws {
        for resource in [html, javaScript, stylesheet] {
            guard fileManager.fileExists(atPath: resource.path),
                  let attributes = try? fileManager.attributesOfItem(atPath: resource.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value > 0
            else {
                throw BuildWorkflowError.missingGeneratedResource(resource)
            }
        }
    }
}
