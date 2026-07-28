import Foundation

/// Generated WebEditor resources required by the desktop application.
public struct WebEditorBuildProducts: Equatable, Sendable {
    /// Bundled editor JavaScript.
    public let editorJavaScript: URL
    /// Bundled editor stylesheet.
    public let editorStylesheet: URL
    /// Representative font that proves esbuild copied font assets.
    public let representativeFont: URL

    /// Resolves generated WebEditor product paths for a repository.
    ///
    /// - Parameter repository: Validated repository layout.
    public init(repository: RepositoryLayout) {
        editorJavaScript = repository.editorResourcesDirectory.appendingPathComponent("editor.js")
        editorStylesheet = repository.editorResourcesDirectory.appendingPathComponent("editor.css")
        representativeFont = repository.editorResourcesDirectory
            .appendingPathComponent("fonts/KaTeX_Main-Regular.woff2")
    }

    /// Verifies every required product exists and contains data.
    ///
    /// - Parameter fileManager: File manager used to inspect generated products.
    public func validate(fileManager: FileManager = .default) throws {
        for resource in [editorJavaScript, editorStylesheet, representativeFont] {
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
