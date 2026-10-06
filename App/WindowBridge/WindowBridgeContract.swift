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
    @MainActor func setWorkspaceToolbarVisible(_ visible: Bool, toolbar: NSObject)
    func materialWindowCount() -> Int
    @MainActor func registerFileDrop(
        id: String, toolbar: NSObject,
        targeted: @MainActor @escaping (Bool) -> Void,
        receive: @MainActor @escaping ([URL]) -> Void
    )
    @MainActor func unregisterFileDrop(id: String)
#if WEIBEI_ACCEPTANCE_CHECKS
    @MainActor func checkFileDrop(id: String, urls: [URL]) -> [String: Bool]
#endif
    @MainActor func presentOpenPanel(
        title: String,
        contentTypeIdentifiers: [String],
        allowsMultipleSelection: Bool,
        canChooseDirectories: Bool,
        canChooseFiles: Bool,
        presentationToolbar: NSObject?,
        completion: @MainActor @escaping ([URL], NSError?) -> Void
    )
    @MainActor func observeUpdates(_ observer: @escaping (String, String?, [String], Bool, URL?) -> Void)
    @MainActor func checkForUpdates()
    @MainActor func installAvailableUpdate()
}
