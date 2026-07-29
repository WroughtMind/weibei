import XCTest
@testable import WeiBeiCore

final class ContentRailPolicyTests: XCTestCase {
    /**
     * Verifies that dormant rail presentation is selected only at the magnetic threshold.
     */
    func testRailOnlyPresentationHonorsLayoutCapabilityAndThreshold() {
        XCTAssertEqual(
            ContentRailPolicy.presentation(
                availableWidth: ContentRailPolicy.railOnlyThreshold,
                allowsRailOnly: true
            ),
            .railOnly
        )
        XCTAssertEqual(
            ContentRailPolicy.presentation(
                availableWidth: ContentRailPolicy.railOnlyThreshold + 0.5,
                allowsRailOnly: true
            ),
            .content
        )
        XCTAssertEqual(
            ContentRailPolicy.presentation(availableWidth: 0, allowsRailOnly: false),
            .content
        )
    }

    /**
     * Verifies expansion restoration clamps stale widths into readable product limits.
     */
    func testExpansionWidthClampsRecentWidth() {
        XCTAssertEqual(ContentRailPolicy.expansionWidth(recentWidth: nil), ContentRailPolicy.expansionPreferredWidth)
        XCTAssertEqual(ContentRailPolicy.expansionWidth(recentWidth: 100), ContentRailPolicy.expansionMinimumWidth)
        XCTAssertEqual(ContentRailPolicy.expansionWidth(recentWidth: 900), ContentRailPolicy.expansionMaximumWidth)
        XCTAssertEqual(ContentRailPolicy.expansionWidth(recentWidth: 330), 330)
    }

    /**
     * Verifies preview sizing refuses unusable content widths and caps expansive windows.
     */
    func testPreviewWidthUsesAvailableSpaceAndDormantWidth() {
        XCTAssertNil(ContentRailPolicy.previewWidth(totalWidth: 200, previewLeadingX: 70))
        XCTAssertEqual(ContentRailPolicy.previewWidth(totalWidth: 400, previewLeadingX: 100), 292)
        XCTAssertEqual(ContentRailPolicy.previewWidth(totalWidth: 1_000, previewLeadingX: 100), ContentRailPolicy.previewMaximumWidth)
        XCTAssertEqual(
            ContentRailPolicy.previewWidth(totalWidth: 0, previewLeadingX: 0, isRailOnly: true),
            ContentRailPolicy.dormantPreviewWidth
        )
    }
}
