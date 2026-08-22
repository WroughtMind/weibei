import XCTest
import WeiBeiCore
@testable import WeiBei

/// 2026-08-22 assembled-app crash: a bare `Bundle.module` access in the
/// calligraphy loader hit the Swift 6.2 accessor's fatalError ("could not
/// load resource bundle") because the compiled-in dev fallback path was gone.
/// These resources must keep resolving through WeiBeiResources' non-fatal
/// Bundle(url:) chain instead.
final class InspirationResourceSafetyTests: XCTestCase {
    func testCalligraphyAssetsLoadThroughSafeBundleResolver() {
        for item in EmptyWorkspaceInspirationCatalog.items {
            guard case let .calligraphy(assetName) = item.presentation else { continue }
            XCTAssertNotNil(
                EmptyWorkspaceCalligraphyResource.image(named: assetName),
                "calligraphy asset failed to load: \(assetName)"
            )
        }
    }

    func testSourcesLedgerResolvesThroughSafeBundleResolver() {
        let bundle = WeiBeiResources.bundle
        XCTAssertNotNil(
            bundle.url(forResource: "SOURCES", withExtension: "md", subdirectory: "Inspiration")
                ?? bundle.url(forResource: "SOURCES", withExtension: "md"),
            "SOURCES.md ledger must stay bundled and resolvable"
        )
    }
}
