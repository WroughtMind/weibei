import Foundation

enum WeiBeiResources {
    static let bundle: Bundle = {
        let bundleName = "WeiBei_WeiBei.bundle"
        let packagedURL = Bundle.main.resourceURL?.appendingPathComponent(bundleName)
        let legacyURL = Bundle.main.bundleURL.appendingPathComponent(bundleName)
        return packagedURL.flatMap(Bundle.init(url:))
            ?? Bundle(url: legacyURL)
            ?? Bundle.module
    }()
}
