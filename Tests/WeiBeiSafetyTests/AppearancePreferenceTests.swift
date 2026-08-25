import Foundation
@testable import WeiBei
import WeiBeiCore
import XCTest

@MainActor
final class AppearancePreferenceTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        setenv("WEIBEI_SAFETY_TEST_MODE", "1", 1)
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "weibei.appearancePreference")
        UserDefaults.standard.removeObject(forKey: "weibei.appearanceStyle")
        UserDefaults.standard.removeObject(forKey: "weibei.glassIntensity")
        WeiBeiThemeRuntime.glassIntensity = 1.0
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "weibei.appearancePreference")
        UserDefaults.standard.removeObject(forKey: "weibei.appearanceStyle")
        UserDefaults.standard.removeObject(forKey: "weibei.glassIntensity")
        WeiBeiThemeRuntime.glassIntensity = 1.0
        super.tearDown()
    }

    private func makeStore() throws -> WorkspaceStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("weibei-appearance-pref-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return WorkspaceStore(
            workspaceDirectory: root,
            courseRootBookmarkMaker: { _ in nil },
            courseRootBookmarkResolver: { _ in nil }
        )
    }

    func testStyleMappingCoversAllModes() {
        XCTAssertEqual(WeiBeiAppearanceStyle.of(.paper), .paperInk)
        XCTAssertEqual(WeiBeiAppearanceStyle.of(.inkstone), .paperInk)
        XCTAssertEqual(WeiBeiAppearanceStyle.of(.xuan), .xuanStele)
        XCTAssertEqual(WeiBeiAppearanceStyle.of(.stele), .xuanStele)
        XCTAssertEqual(WeiBeiAppearanceStyle.of(.glassLight), .clearGlass)
        XCTAssertEqual(WeiBeiAppearanceStyle.of(.glassDark), .clearGlass)
        XCTAssertEqual(WeiBeiAppearanceStyle.of(.glassMist), .mistGlass)
        XCTAssertEqual(WeiBeiAppearanceStyle.of(.glassSlate), .mistGlass)
    }

    func testPreferenceDerivesFromCurrentModeForLegacyUsers() throws {
        let store = try makeStore()
        XCTAssertEqual(store.appearancePreference, .light)
        XCTAssertEqual(store.appearanceStyle, .paperInk)

        // 深色老用户：偏好与风格按当前主题落位，解析后保持不变。
        store.setAppearanceMode(.inkstone)
        XCTAssertEqual(store.appearancePreference, .dark)
        store.applyResolvedAppearance(systemIsDark: false)
        XCTAssertEqual(store.appearanceMode, .inkstone)
    }

    func testStyleSelectionResolvesByStaticPreference() throws {
        let store = try makeStore()
        store.appearanceStyle = .xuanStele
        XCTAssertEqual(store.appearanceMode, .xuan)

        store.appearancePreference = .dark
        XCTAssertEqual(store.appearanceMode, .stele)

        store.appearanceStyle = .clearGlass
        XCTAssertEqual(store.appearanceMode, .glassDark)

        store.appearancePreference = .light
        XCTAssertEqual(store.appearanceMode, .glassLight)
    }

    func testFollowSystemFlipsWithinSelectedStyle() throws {
        let store = try makeStore()
        store.appearanceStyle = .mistGlass
        store.appearancePreference = .system
        store.applyResolvedAppearance(systemIsDark: true)
        XCTAssertEqual(store.appearanceMode, .glassSlate)
        store.applyResolvedAppearance(systemIsDark: false)
        XCTAssertEqual(store.appearanceMode, .glassMist)

        // 静态模式下系统变化不动作。
        store.appearancePreference = .light
        store.refreshAppearanceForSystemChange()
        XCTAssertEqual(store.appearanceMode, .glassMist)
    }

    func testGlassIntensityClampsAndPersists() throws {
        let store = try makeStore()
        store.glassIntensity = 1.7
        XCTAssertEqual(store.glassIntensity, 1.0, accuracy: 0.0001)
        XCTAssertNil(
            UserDefaults.standard.object(forKey: "weibei.glassIntensity"),
            "拖动玻璃浓度只改当前窗口，不能在松手前写入偏好。"
        )

        store.glassIntensity = 0.25
        XCTAssertEqual(store.glassIntensity, 0.25, accuracy: 0.0001)
        XCTAssertNil(
            UserDefaults.standard.object(forKey: "weibei.glassIntensity"),
            "拖动中途改浓度不能落盘；否则松手前的中间值会污染下次打开。"
        )

        // 松手才落盘，下次打开仍是这个浓度。
        store.persistGlassIntensity()
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: "weibei.glassIntensity") as? Double ?? -1,
            0.25,
            accuracy: 0.0001
        )

        WeiBeiThemeRuntime.glassIntensity = 1.0
        WorkspaceStore.loadPersistedGlassIntensity()
        XCTAssertEqual(store.glassIntensity, 0.25, accuracy: 0.0001)
    }
}
