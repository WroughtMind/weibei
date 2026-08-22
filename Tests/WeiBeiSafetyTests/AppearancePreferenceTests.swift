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
        UserDefaults.standard.removeObject(forKey: "weibei.glassIntensity")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "weibei.appearancePreference")
        UserDefaults.standard.removeObject(forKey: "weibei.glassIntensity")
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

    func testDefaultPreferenceIsStaticLight() throws {
        let store = try makeStore()
        XCTAssertEqual(store.appearancePreference, .light)
        // 静态浅色下系统变深也不翻转。
        store.setAppearanceMode(.paper)
        store.refreshAppearanceForSystemChange(systemIsDark: true)
        XCTAssertEqual(store.appearanceMode, .paper)
    }

    func testFollowSystemFlipsToPairedTheme() throws {
        let store = try makeStore()
        store.appearancePreference = .system
        store.setAppearanceMode(.paper)
        store.refreshAppearanceForSystemChange(systemIsDark: true)
        XCTAssertEqual(store.appearanceMode, .inkstone)
        // 系统回浅色：对称配对保证回到原主题。
        store.refreshAppearanceForSystemChange(systemIsDark: false)
        XCTAssertEqual(store.appearanceMode, .paper)
    }

    func testFollowSystemPairsAllFourFamilies() throws {
        let store = try makeStore()
        store.appearancePreference = .system
        let pairs: [(WeiBeiAppearanceMode, WeiBeiAppearanceMode)] = [
            (.xuan, .stele),
            (.glassLight, .glassDark),
            (.glassMist, .glassSlate),
        ]
        for (light, dark) in pairs {
            store.setAppearanceMode(light)
            store.refreshAppearanceForSystemChange(systemIsDark: true)
            XCTAssertEqual(store.appearanceMode, dark)
            store.refreshAppearanceForSystemChange(systemIsDark: false)
            XCTAssertEqual(store.appearanceMode, light)
        }
    }

    func testGlassIntensityClampsAndPersists() throws {
        let store = try makeStore()
        store.glassIntensity = 1.7
        XCTAssertEqual(store.glassIntensity, 1.0, accuracy: 0.0001)
        store.glassIntensity = 0.25
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: "weibei.glassIntensity") as? Double ?? -1,
            0.25,
            accuracy: 0.0001
        )
    }
}
