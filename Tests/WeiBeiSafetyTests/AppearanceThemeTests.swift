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
            // 玻璃模式前景面有意全透明:整窗玻璃片唯一负责可读性,
            // 第二层面会叠深玻璃(材质分工定案)。
            XCTAssertEqual(
                WeiBeiNativePalette.foregroundWorkspaceSurface(for: mode).alphaComponent,
                0,
                accuracy: 0.001
            )
            XCTAssertEqual(
                WeiBeiNativePalette.searchPanelFill(for: mode).alphaComponent,
                1,
                accuracy: 0.001
            )
            XCTAssertTrue(
                WeiBeiNativePalette.searchPanelFill(for: mode)
                    .isEqual(WeiBeiNativePalette.glassTint(for: mode))
            )
            XCTAssertGreaterThan(WeiBeiNativePalette.searchFieldFill(for: mode).alphaComponent, 0.15)
            XCTAssertGreaterThan(WeiBeiNativePalette.searchFieldStroke(for: mode).alphaComponent, 0.4)
            XCTAssertTrue(
                WeiBeiNativePalette.searchFieldStroke(for: mode, active: true)
                    .isEqual(WeiBeiNativePalette.searchFieldStroke(for: mode))
            )
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
            XCTAssertTrue(
                WeiBeiNativePalette.searchPanelFill(for: mode)
                    .isEqual(WeiBeiNativePalette.paperRaised(for: mode))
            )
            XCTAssertEqual(
                WeiBeiNativePalette.searchFieldFill(for: mode).alphaComponent,
                1,
                accuracy: 0.001
            )
        }
    }

    func testFrostedIntensityChangesTintAcrossTheSliderWithoutChangingInk() {
        let original = WeiBeiThemeRuntime.glassIntensity
        defer { WeiBeiThemeRuntime.glassIntensity = original }
        for mode in [WeiBeiAppearanceMode.glassMist, .glassSlate] {
            let ink = WeiBeiNativePalette.ink(for: mode)
            var previousAlpha: CGFloat = -1
            for intensity in [0.0, 0.2, 0.4, 0.7, 1.0] {
                WeiBeiThemeRuntime.glassIntensity = intensity
                let alpha = WeiBeiNativePalette.glassBaseTint(for: mode).alphaComponent
                XCTAssertGreaterThan(alpha, previousAlpha)
                XCTAssertLessThan(alpha, 1)
                XCTAssertEqual(WeiBeiNativePalette.ink(for: mode), ink)
                previousAlpha = alpha
            }
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

    func testCustomAccentUpdatesNativeAndWebPalettesAcrossAllThemes() throws {
        let original = WeiBeiThemeRuntime.accentPreference
        defer { WeiBeiThemeRuntime.accentPreference = original }
        WeiBeiThemeRuntime.accentPreference = .themeDefault
        let preference = WeiBeiAccentPreference(direction: .indigo, brightness: 0.5)
        let defaults = WeiBeiAppearanceMode.allCases.map { WeiBeiNativePalette.accent(for: $0) }
        let changed = expectation(description: "Accent consumers observed the color change")
        withObservationTracking {
            _ = WeiBeiTheme.accent
        } onChange: { changed.fulfill() }

        WeiBeiThemeRuntime.accentPreference = preference
        wait(for: [changed], timeout: 1)

        for (mode, defaultAccent) in zip(WeiBeiAppearanceMode.allCases, defaults) {
            let custom = try XCTUnwrap(preference.customColor(for: mode))
            let accent = WeiBeiNativePalette.accent(for: mode)
            XCTAssertEqual(WeiBeiAccentColor(platformColor: accent), custom)
            XCTAssertEqual(WeiBeiAccentColor(platformColor: WeiBeiNativePalette.accentSoft(for: mode)), custom)
            XCTAssertEqual(WeiBeiAccentColor(platformColor: WeiBeiNativePalette.selectionFill(for: mode)), custom)
            XCTAssertEqual(WeiBeiNativePalette.cssHex(for: mode).accent, weiBeiCSSColor(accent))
            XCTAssertEqual(agentVisualizationTheme(for: mode, textScale: 1)["accent"], weiBeiCSSColor(accent))
            XCTAssertEqual(WeiBeiNativePalette.defaultAccent(for: mode), defaultAccent)
        }

        WeiBeiThemeRuntime.accentPreference = .themeDefault
        XCTAssertEqual(WeiBeiAppearanceMode.allCases.map { WeiBeiNativePalette.accent(for: $0) }, defaults)
    }

    func testPresetDirectionsAdaptToThemeAndAllowBrightnessChanges() {
        for direction in WeiBeiAccentDirection.allCases {
            XCTAssertNotEqual(direction.color(for: .paper), direction.color(for: .inkstone))
            for mode in WeiBeiAppearanceMode.allCases {
                let color = direction.color(for: mode)
                XCTAssertLessThan(color.adjustedBrightness(-1, for: mode).rawValue, color.rawValue)
                XCTAssertGreaterThan(color.adjustedBrightness(1, for: mode).rawValue, color.rawValue)
                XCTAssertEqual(color.adjustedBrightness(0, for: mode), color)
            }
        }
    }

    func testTextOnCustomAccentUsesTheHigherContrastColor() throws {
        let light = try XCTUnwrap(WeiBeiAccentColor(rawValue: 0xFFE000))
        let dark = try XCTUnwrap(WeiBeiAccentColor(rawValue: 0x322264))
        XCTAssertEqual(WeiBeiAccentColor(platformColor: light.contrastingForeground)?.rawValue, 0x000000)
        XCTAssertEqual(WeiBeiAccentColor(platformColor: dark.contrastingForeground)?.rawValue, 0xFFFFFF)
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
