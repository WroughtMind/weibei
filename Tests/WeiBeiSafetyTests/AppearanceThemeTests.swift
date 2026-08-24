import Observation
import XCTest
@testable import WeiBei

final class AppearanceThemeTests: XCTestCase {
    func testGlassThemesStayPairedAndTranslucent() {
        XCTAssertEqual(WeiBeiAppearanceMode.allCases.count, 8)
        XCTAssertEqual(WeiBeiAppearanceMode.glassLight.oppositeFamily, .glassDark)
        XCTAssertEqual(WeiBeiAppearanceMode.glassDark.oppositeFamily, .glassLight)
        XCTAssertEqual(WeiBeiAppearanceMode.glassMist.oppositeFamily, .glassSlate)
        XCTAssertEqual(WeiBeiAppearanceMode.glassSlate.oppositeFamily, .glassMist)
        XCTAssertEqual(WeiBeiAppearanceMode.glassLight.webThemeName, "glassLight")
        XCTAssertEqual(WeiBeiAppearanceMode.glassDark.webThemeName, "glassDark")
        for mode in [
            WeiBeiAppearanceMode.glassLight,
            .glassDark,
            .glassMist,
            .glassSlate,
        ] {
            XCTAssertTrue(mode.isGlass)
            XCTAssertLessThan(WeiBeiNativePalette.paper(for: mode).alphaComponent, 1)
            XCTAssertGreaterThan(WeiBeiNativePalette.drawerSurface(for: mode).alphaComponent, 0)
            XCTAssertLessThan(WeiBeiNativePalette.drawerSurface(for: mode).alphaComponent, 1)
            XCTAssertGreaterThan(WeiBeiNativePalette.foregroundWorkspaceSurface(for: mode).alphaComponent, 0)
            XCTAssertLessThan(WeiBeiNativePalette.foregroundWorkspaceSurface(for: mode).alphaComponent, 1)
        }

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

    func testThemeTokensTrackRuntimeModeChanges() {
        assertThemeObservation(from: .paper, to: .xuan) {
            _ = WeiBeiTheme.ink
        }
        assertThemeObservation(from: .inkstone, to: .stele) {
            _ = WeiBeiTheme.paper
        }
        assertThemeObservation(from: .paper, to: .inkstone) {
            _ = WeiBeiTheme.secondaryInk
        }
    }

    private func assertThemeObservation(
        from source: WeiBeiAppearanceMode,
        to target: WeiBeiAppearanceMode,
        readThemeToken: () -> Void
    ) {
        let originalMode = WeiBeiThemeRuntime.mode
        defer { WeiBeiThemeRuntime.mode = originalMode }

        WeiBeiThemeRuntime.mode = source
        var didObserveChange = false
        withObservationTracking {
            readThemeToken()
        } onChange: {
            didObserveChange = true
        }

        WeiBeiThemeRuntime.mode = target
        XCTAssertTrue(
            didObserveChange,
            "Expected theme token observation for \(source.rawValue) -> \(target.rawValue)"
        )
    }
}
