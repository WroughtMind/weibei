import XCTest
@testable import WeiBei

final class AppearanceThemeTests: XCTestCase {
    func testGlassThemesStayPairedAndTranslucent() {
        XCTAssertEqual(WeiBeiAppearanceMode.allCases.count, 6)
        XCTAssertEqual(WeiBeiAppearanceMode.glassLight.oppositeFamily, .glassDark)
        XCTAssertEqual(WeiBeiAppearanceMode.glassDark.oppositeFamily, .glassLight)
        XCTAssertLessThan(WeiBeiNativePalette.paper(for: .glassLight).alphaComponent, 1)
        XCTAssertLessThan(WeiBeiNativePalette.paper(for: .glassDark).alphaComponent, 1)
        XCTAssertGreaterThan(WeiBeiNativePalette.drawerSurface(for: .glassLight).alphaComponent, 0)
        XCTAssertLessThan(WeiBeiNativePalette.drawerSurface(for: .glassLight).alphaComponent, 1)
        XCTAssertGreaterThan(WeiBeiNativePalette.foregroundWorkspaceSurface(for: .glassDark).alphaComponent, 0)
        XCTAssertLessThan(WeiBeiNativePalette.foregroundWorkspaceSurface(for: .glassDark).alphaComponent, 1)

        for mode in [
            WeiBeiAppearanceMode.paper,
            .xuan,
            .inkstone,
            .stele,
        ] {
            XCTAssertFalse(mode.isGlass)
            XCTAssertEqual(
                WeiBeiNativePalette.paper(for: mode).alphaComponent,
                1,
                accuracy: 0.001
            )
            XCTAssertTrue(
                WeiBeiNativePalette.drawerSurface(for: mode)
                    .isEqual(WeiBeiNativePalette.paper(for: mode))
            )
        }
    }
}
