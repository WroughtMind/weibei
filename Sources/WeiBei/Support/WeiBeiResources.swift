import Foundation

enum WeiBeiResources {
    static var officeRuntimeURL: URL? {
        bundle.url(forResource: "office-entry", withExtension: "js.deflate", subdirectory: "Editor")
    }

    static var selectionRuntimeURL: URL? {
        bundle.url(forResource: "selection-runtime", withExtension: "js", subdirectory: "Editor")
    }

    static var editorURL: URL? {
        bundle.url(forResource: "index", withExtension: "html", subdirectory: "Editor")
    }

    static let bundle: Bundle = {
#if targetEnvironment(macCatalyst)
        return Bundle.main
#else
        let bundleName = "WeiBei_WeiBei.bundle"
        let packagedURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName)
        let legacyURL = Bundle.main.bundleURL.appendingPathComponent(bundleName)
        return packagedURL.flatMap(Bundle.init(url:))
            ?? Bundle(url: legacyURL)
            ?? Bundle.module
#endif
    }()
}
