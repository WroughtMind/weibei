import Foundation

// Objective-C is the public ABI between the Catalyst target and its macOS bundle.
@objc(WeiBeiCatalystWindowBridgeProtocol) protocol CatalystWindowBridge: NSObjectProtocol {
    init()
    func configure(mode: String, intensity: Double)
    func pushCursor(_ name: String)
    func popCursor()
    func setCursor(_ name: String)
    func open(_ url: URL) -> Bool
    func reveal(_ url: URL)
    func materialWindowCount() -> Int
#if WEIBEI_ACCEPTANCE_CHECKS
    @MainActor func acceptanceThinkingStatusFrame() -> CGRect
#endif
    @MainActor func observeUpdates(_ observer: @escaping (String, String?, [String], Bool, URL?) -> Void)
    @MainActor func checkForUpdates()
    @MainActor func installAvailableUpdate()
}
