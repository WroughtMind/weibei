import Foundation

enum WeiBeiResources {
    static var selectionRuntimeURL: URL? {
#if targetEnvironment(macCatalyst)
        bundle.url(forResource: "selection-runtime", withExtension: "js", subdirectory: "Editor")
#else
        bundle.url(forResource: "selection-runtime", withExtension: "js")
#endif
    }

    static var editorURL: URL? {
#if targetEnvironment(macCatalyst)
        bundle.url(forResource: "index", withExtension: "html", subdirectory: "Editor")
#else
        bundle.url(forResource: "index", withExtension: "html")
#endif
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
