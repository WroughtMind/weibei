import Foundation

@MainActor
enum CatalystDesktopWindow {
    private static let bundle = Bundle(url: Bundle.main.builtInPlugInsURL!.appendingPathComponent("WeiBeiWindowBridge.bundle"))!
    static let shared: CatalystWindowBridge = {
        do { try bundle.loadAndReturnError() }
        catch { fatalError("Cannot load the signed Catalyst window bridge: \(error)") }
        guard let type = bundle.principalClass as? CatalystWindowBridge.Type else {
            fatalError("The Catalyst window bridge has no valid entry point")
        }
        return type.init()
    }()
    static func configure(mode: WeiBeiAppearanceMode) {
        shared.configure(mode: mode.rawValue, intensity: WeiBeiThemeRuntime.appliedGlassIntensity)
    }
}
