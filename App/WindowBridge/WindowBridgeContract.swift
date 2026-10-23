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
    @MainActor func presentUpdateNotes(contentItem: NSObject, anchor: NSObject,
                                      sourceRect: CGRect, size: CGSize, dark: Bool,
                                      dismissed: @MainActor @escaping () -> Void) -> NSObject?
    @MainActor func updateUpdateNotes(_ presentation: NSObject, sourceRect: CGRect, size: CGSize, dark: Bool)
    @MainActor func dismissUpdateNotes(_ presentation: NSObject)
    @MainActor func registerFloatingResize(id: String, toolbar: NSObject,
        accepts: @MainActor @escaping (CGPoint) -> Bool,
        changed: @MainActor @escaping (CGSize, Bool) -> Void)
    @MainActor func unregisterFloatingResize(id: String)
    func materialWindowCount() -> Int
    @MainActor func registerFileDrop(
        id: String, toolbar: NSObject,
        targeted: @MainActor @escaping (Bool) -> Void,
        receive: @MainActor @escaping ([URL], [URL], [URL], [String]) -> Void
    )
    @MainActor func unregisterFileDrop(id: String)
    @MainActor func currentDraggedFileURLs() -> [URL]
    @MainActor func currentDragContainsFilePromises() -> Bool
#if WEIBEI_ACCEPTANCE_CHECKS
    @MainActor func prepareFileDropCheck(id: String, urls: [URL]) -> [String: Bool]
    @MainActor func finishFileDropCheck()
    @MainActor func setWorkspaceFullScreenForCheck(_ enabled: Bool) -> Bool
    @MainActor func fullScreenWindowStateForCheck() -> [String: Bool]
    @MainActor func fullScreenWindowDiagnosticsForCheck() -> [[String: String]]
    @MainActor func postToolbarClickForCheck(toolbar: NSObject, itemIdentifier: String,
                                           xFraction: Double, yFraction: Double, activateWindow: Bool,
                                           routeThroughWorkspace: Bool) -> [String: String]
    @MainActor func updateNotesVisibleForCheck() -> Bool
    @MainActor func clickUpdateNotesPageSourceForCheck() -> [String: String]
    @MainActor func floatingResizeEventsForCheck() -> [[String: String]]
    @MainActor func floatingResizeStateForCheck() -> [String: Bool]
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
    @MainActor func observeUpdates(_ observer: @escaping (NSDictionary) -> Void)
    @MainActor func checkForUpdates()
    @MainActor func installAvailableUpdate(_ save: @escaping (@escaping (Bool) -> Void) -> Void)
}
