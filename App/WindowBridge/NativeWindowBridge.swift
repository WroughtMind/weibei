import AppKit
import Combine
import UniformTypeIdentifiers

/// Native window services and Sparkle use this bridge; content stays in Catalyst.
@objc(WeiBeiCatalystWindowBridge)
final class NativeWindowBridge: NSObject, CatalystWindowBridge {
    private var mode = "paper"
    private var intensity = 1.0
    private let materials = NSMapTable<NSWindow, NSVisualEffectView>.weakToStrongObjects()
    private let settingsPresentationHandled = NSHashTable<NSWindow>.weakObjects()
    private let settingsPresentationPending = NSHashTable<NSWindow>.weakObjects()
    private var observers: [NSObjectProtocol] = []
    private var activeOpenPanel: NSOpenPanel?
    private var fileDrops: [String: NativeFileDropRegistration] = [:]
#if WEIBEI_ACCEPTANCE_CHECKS
    private var fileDropCheckBoard: NSPasteboard?
    private weak var checkedFullScreenWorkspace: NSWindow?
    private var checkedFullScreenEntered = false
    private var checkedFullScreenExited = false
    private var fullScreenCheckNotifications: [String] = []
    private var fullScreenCheckToolbarChanges: [String] = []
#endif
    private let toolbarVisibility = NSMapTable<NSToolbar, NSNumber>.weakToStrongObjects()
    @MainActor private lazy var updateService = WeiBeiUpdateService()
    @MainActor private var updateObservation: AnyCancellable?

    required override init() {
        super.init()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didEnterFullScreenNotification,
                     NSWindow.didExitFullScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let window = note.object as? NSWindow else { return }
                if note.name == NSWindow.didBecomeKeyNotification,
                   !self.settingsPresentationPending.contains(window) {
                    self.settingsPresentationHandled.remove(window)
                }
#if WEIBEI_ACCEPTANCE_CHECKS
                if note.name == NSWindow.didEnterFullScreenNotification || note.name == NSWindow.didExitFullScreenNotification {
                    self.fullScreenCheckNotifications.append(note.name.rawValue + " "
                        + String(describing: ObjectIdentifier(window)) + " toolbar="
                        + (window.toolbar.map { String(describing: $0.identifier) } ?? "nil"))
                    if self.fullScreenCheckNotifications.count > 16 { self.fullScreenCheckNotifications.removeFirst() }
                }
                if window === self.checkedFullScreenWorkspace {
                    if note.name == NSWindow.didEnterFullScreenNotification { self.checkedFullScreenEntered = true }
                    if note.name == NSWindow.didExitFullScreenNotification { self.checkedFullScreenExited = true }
                }
#endif
                self.apply(to: window)
            })
        }
        // A Catalyst scene can acquire its NSWindow after configure(), and a
        // background/PiP window need not become key. Apply input settings too.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let window = note.object as? NSWindow else { return }
            self.updateFileDrops()
            self.updateToolbarBackground(in: window)
            self.configureSettingsWindow(window)
            guard !window.acceptsMouseMovedEvents
                || (self.mode.hasPrefix("glass") && self.materials.object(forKey: window)?.superview == nil) else { return }
            self.apply(to: window)
        })
    }
    func configure(mode: String, intensity: Double) {
        self.mode = mode; self.intensity = intensity
        NSApp.windows.forEach(apply)
    }
    private func apply(to window: NSWindow) {
        updateFileDrops()
        // Popovers are borderless windows too; their rows need mouse-move events.
        window.acceptsMouseMovedEvents = true
        updateToolbarBackground(in: window)
        configureSettingsWindow(window)
        guard window.styleMask.contains(.titled), let content = window.contentView else { return }
        let glass = ["glassLight", "glassDark", "glassMist", "glassSlate"].contains(mode)
        window.isOpaque = !glass
        guard glass else {
            materials.object(forKey: window)?.removeFromSuperview()
            materials.removeObject(forKey: window)
            return
        }
        let material: NSVisualEffectView
        if let existing = materials.object(forKey: window), existing.superview === content {
            material = existing
        } else {
            material = NSVisualEffectView(frame: content.bounds)
            material.autoresizingMask = [.width, .height]
            material.blendingMode = .behindWindow
            material.state = .active
            content.addSubview(material, positioned: .below, relativeTo: nil)
            materials.setObject(material, forKey: window)
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        let fullScreen = window.styleMask.contains(.fullScreen)
        switch mode {
        case "glassLight":
            material.material = fullScreen ? .windowBackground : .underWindowBackground
            material.alphaValue = (fullScreen ? 0.88 : 0.38) * intensity
        case "glassDark":
            material.material = .hudWindow
            material.alphaValue = 0.58 * intensity
        case "glassMist":
            material.material = .popover
            material.alphaValue = 1
        case "glassSlate":
            material.material = .hudWindow
            material.alphaValue = 1
        default: break
        }
    }
    private func configureSettingsWindow(_ window: NSWindow) {
        guard window.toolbar?.identifier == "weibei.settings" else { return }
        var behavior = window.collectionBehavior
        behavior.subtract([.primary, .canJoinAllApplications, .canJoinAllSpaces,
                           .fullScreenPrimary, .fullScreenNone, .fullScreenAllowsTiling])
        behavior.formUnion([.auxiliary, .fullScreenAuxiliary, .fullScreenDisallowsTiling, .moveToActiveSpace])
        if window.collectionBehavior != behavior { window.collectionBehavior = behavior }
        if window.tabbingMode != .disallowed { window.tabbingMode = .disallowed }
        if window.toolbar?.isVisible == true { window.toolbar?.isVisible = false }
        guard window.isVisible, !settingsPresentationHandled.contains(window) else { return }
        settingsPresentationHandled.add(window)
        guard NSApp.isActive, !window.isOnActiveSpace, fullScreenWorkspaceIsOnActiveSpace else { return }
        // Catalyst can order a new scene on the ordinary desktop before this
        // native utility policy is installed. Present it again after that scene
        // transaction, once per activation; never front it on ordinary updates.
        settingsPresentationPending.add(window)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            defer { self.settingsPresentationPending.remove(window) }
            guard NSApp.isActive, window.isVisible, window.isKeyWindow, !window.isOnActiveSpace,
                  self.fullScreenWorkspaceIsOnActiveSpace else { return }
            self.configureSettingsWindow(window)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var fullScreenWorkspaceIsOnActiveSpace: Bool {
        NSApp.windows.contains {
            $0.toolbar?.identifier == "weibei.workspace"
                && $0.styleMask.contains(.fullScreen) && $0.isOnActiveSpace
        }
    }

#if WEIBEI_ACCEPTANCE_CHECKS
    @MainActor func setWorkspaceFullScreenForCheck(_ enabled: Bool) -> Bool {
        guard let window = checkedFullScreenWorkspace
            ?? NSApp.windows.first(where: { $0.toolbar?.identifier == "weibei.workspace" }) else { return false }
        checkedFullScreenWorkspace = window
        if window.styleMask.contains(.fullScreen) != enabled {
            checkedFullScreenEntered = false
            checkedFullScreenExited = false
            window.toggleFullScreen(nil)
        }
        return true
    }

    @MainActor func fullScreenWindowStateForCheck() -> [String: Bool] {
        let workspace = checkedFullScreenWorkspace
            ?? NSApp.windows.first(where: { $0.toolbar?.identifier == "weibei.workspace" })
        let settings = NSApp.windows.first(where: { $0.toolbar?.identifier == "weibei.settings" })
        var state = ["workspace_found": workspace != nil, "settings_found": settings != nil,
                     "app_active": NSApp.isActive,
                     "workspace_entered_full_screen": checkedFullScreenEntered,
                     "workspace_exited_full_screen": checkedFullScreenExited]
        if let workspace {
            state["workspace_full_screen"] = workspace.styleMask.contains(.fullScreen)
            state["workspace_on_active_space"] = workspace.isOnActiveSpace
        }
        if let settings {
            state["settings_full_screen"] = settings.styleMask.contains(.fullScreen)
            state["settings_on_active_space"] = settings.isOnActiveSpace
            state["settings_visible"] = settings.isVisible
        }
        return state
    }

    @MainActor func fullScreenWindowDiagnosticsForCheck() -> [[String: String]] {
        NSApp.windows.map { window in
            var state = ["class": NSStringFromClass(type(of: window)),
             "window_identity": String(describing: ObjectIdentifier(window)),
             "number": String(window.windowNumber),
             "toolbar": window.toolbar.map { String(describing: $0.identifier) } ?? "",
             "toolbar_identity": window.toolbar.map { String(describing: ObjectIdentifier($0)) } ?? "",
             "parent_toolbar": window.parent?.toolbar.map { String(describing: $0.identifier) } ?? "",
             "collection_behavior": String(window.collectionBehavior.rawValue),
             "style_mask": String(window.styleMask.rawValue),
             "frame": NSStringFromRect(window.frame),
             "visible": String(window.isVisible),
             "main_thread": String(Thread.isMainThread),
             "run_loop_mode": RunLoop.current.currentMode?.rawValue ?? "nil",
             "key": String(window.isKeyWindow),
             "main": String(window.isMainWindow),
             "on_active_space": String(window.isOnActiveSpace)]
            state["delegate"] = NativeFileDropDelegate.describe(window.delegate)
            state["checked_workspace_identity"] = checkedFullScreenWorkspace.map { String(describing: ObjectIdentifier($0)) } ?? "nil"
            state["full_screen_notifications"] = fullScreenCheckNotifications.joined(separator: "\n")
            state["toolbar_visible"] = window.toolbar.map { String($0.isVisible) } ?? "nil"
            state["toolbar_visibility_override"] = window.toolbar.flatMap {
                toolbarVisibility.object(forKey: $0).map { String($0.boolValue) }
            } ?? "nil"
            state["toolbar_visibility_changes"] = fullScreenCheckToolbarChanges.joined(separator: "\n")
            if let delegate = window.delegate as? NativeFileDropDelegate {
                state.merge(delegate.fullScreenDiagnostics) { _, new in new }
            }
            return state
        }
    }
#endif

    private func updateToolbarBackground(in window: NSWindow) {
        let owner = window.toolbar?.identifier == "weibei.workspace" ? window : window.parent
        guard let owner, owner.toolbar?.identifier == "weibei.workspace" else { return }
        // 不设 titlebarAppearsTransparent：macOS 27 beta 上它会吞掉窗口模式的工具栏点击（#21）。
        // 直接清标题栏背景视图的不透明度即可透明，命中链不变（2026-09-20 层级 dump 核实）。
        // 窗口模式背景在本窗口的 NSThemeFrame 下；全屏时 AppKit 把工具栏搬进独立宿主窗口。
        var roots: [NSView] = []
        if let frame = owner.contentView?.superview { roots.append(frame) }
        if let host = owner.toolbar?.items.compactMap({ $0.view?.window }).first, host !== owner,
           let content = host.contentView { roots.append(content) }
        // AppKit resets the fill's alpha during its own layout, so clear only the
        // opacity; keep its layout and the native controls intact.
        func hideBackground(_ view: NSView) {
            if NSStringFromClass(type(of: view)) == "NSTitlebarBackgroundView" {
                if view.alphaValue != 0 { view.alphaValue = 0 }
                return
            }
            view.subviews.forEach(hideBackground)
        }
        roots.forEach(hideBackground)
    }
    func pushCursor(_ name: String) {
        switch name {
        case "openHand": NSCursor.openHand.push()
        case "closedHand": NSCursor.closedHand.push()
        case "resizeLeftRight": NSCursor.resizeLeftRight.push()
        case "resizeUpDown": NSCursor.resizeUpDown.push()
        case "crosshair": NSCursor.crosshair.push()
        default: NSCursor.arrow.push()
        }
    }
    func popCursor() { NSCursor.pop() }
    func setCursor(_ name: String) {
        if name == "pointingHand" { NSCursor.pointingHand.set() }
        else { NSCursor.iBeam.set() }
    }
    func open(_ url: URL) -> Bool { NSWorkspace.shared.open(url) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func materialWindowCount() -> Int { materials.count }
    @MainActor func registerFileDrop(
        id: String, toolbar: NSObject,
        targeted: @MainActor @escaping (Bool) -> Void,
        receive: @MainActor @escaping ([URL]) -> Void
    ) {
        guard let toolbar = toolbar as? NSToolbar else { return }
        unregisterFileDrop(id: id)
        fileDrops[id] = NativeFileDropRegistration(toolbar: toolbar, targeted: targeted, receive: receive)
        updateFileDrops()
    }
    @MainActor func unregisterFileDrop(id: String) {
        fileDrops.removeValue(forKey: id)?.detach()
    }
    @MainActor func setWorkspaceToolbarVisible(_ visible: Bool, toolbar: NSObject) {
        guard let toolbar = toolbar as? NSToolbar else { return }
        toolbarVisibility.setObject(NSNumber(value: visible), forKey: toolbar)
        updateFileDrops()
    }
    private func updateFileDrops() {
        for window in NSApp.windows {
            guard let toolbar = window.toolbar, let visible = toolbarVisibility.object(forKey: toolbar)?.boolValue,
                  toolbar.isVisible != visible else { continue }
#if WEIBEI_ACCEPTANCE_CHECKS
            fullScreenCheckToolbarChanges.append(String(describing: toolbar.identifier) + " "
                + String(toolbar.isVisible) + " -> " + String(visible)
                + " full_screen=" + String(window.styleMask.contains(.fullScreen)))
            if fullScreenCheckToolbarChanges.count > 32 { fullScreenCheckToolbarChanges.removeFirst() }
#endif
            toolbar.isVisible = visible
        }
        fileDrops.values.forEach { $0.attach() }
    }
    @MainActor func currentDraggedFileURLs() -> [URL] {
#if WEIBEI_ACCEPTANCE_CHECKS
        if let board = fileDropCheckBoard { return NativeFileDropDelegate.fileURLs(from: board) }
#endif
        return NativeFileDropDelegate.fileURLs(from: NSPasteboard(name: .drag))
    }
#if WEIBEI_ACCEPTANCE_CHECKS
    @MainActor func prepareFileDropCheck(id: String, urls: [URL]) -> [String: Bool] {
        finishFileDropCheck()
        let checks = fileDrops[id]?.check(urls: urls) ?? [:]
        let board = NSPasteboard.withUniqueName()
        board.writeObjects(urls as [NSURL])
        fileDropCheckBoard = board
        return checks
    }
    @MainActor func finishFileDropCheck() {
        fileDropCheckBoard?.releaseGlobally()
        fileDropCheckBoard = nil
    }
#endif
    @MainActor func presentOpenPanel(
        title: String,
        contentTypeIdentifiers: [String],
        allowsMultipleSelection: Bool,
        canChooseDirectories: Bool,
        canChooseFiles: Bool,
        presentationToolbar: NSObject?,
        completion: @MainActor @escaping ([URL], NSError?) -> Void
    ) {
        guard activeOpenPanel == nil else {
            completeOpenPanelFailure(
                code: 1,
                completion: completion
            )
            return
        }
        let owner: NSWindow
        if let toolbar = presentationToolbar as? NSToolbar {
            let roots = NSApp.windows.filter { $0.toolbar === toolbar }
            guard roots.count == 1, let root = roots.first, root.isVisible else {
                completeOpenPanelFailure(
                    code: 2,
                    completion: completion
                )
                return
            }
            var presentationWindow = root
            while let sheet = presentationWindow.attachedSheet { presentationWindow = sheet }
            owner = presentationWindow
        } else {
            guard let keyWindow = NSApp.keyWindow,
                  keyWindow.isVisible,
                  !keyWindow.isMiniaturized,
                  keyWindow.attachedSheet == nil else {
                completeOpenPanelFailure(
                    code: 3,
                    completion: completion
                )
                return
            }
            owner = keyWindow
        }
        guard !(owner is NSOpenPanel) else {
            completeOpenPanelFailure(
                code: 4,
                completion: completion
            )
            return
        }

        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = canChooseDirectories
        panel.canChooseFiles = canChooseFiles
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = contentTypeIdentifiers.map { UTType($0) ?? UTType(importedAs: $0) }
        activeOpenPanel = panel
        panel.beginSheetModal(for: owner) { [weak self] response in
            let urls = response == .OK ? panel.urls : []
            self?.activeOpenPanel = nil
            // Resume Catalyst on the next main-loop turn, after AppKit has detached the sheet.
            DispatchQueue.main.async { completion(urls, nil) }
        }
    }
    @MainActor private func completeOpenPanelFailure(
        code: Int,
        completion: @MainActor ([URL], NSError?) -> Void
    ) {
        WeiBeiLog.workspace.error("code=native_open_panel_failed reason=\(code, privacy: .public)")
        completion([], NSError(
            domain: "WeiBei.NativeOpenPanel",
            code: code
        ))
    }
    @MainActor func observeUpdates(_ observer: @escaping (String, String?, [String], Bool, URL?) -> Void) {
        updateObservation = updateService.$status.combineLatest(updateService.$availableUpdate)
            .sink { status, update in
                observer(status.rawValue, update?.version, update?.releaseNotesLines ?? [],
                    update?.informationOnly ?? false, update?.informationURL)
            }
    }
    @MainActor func checkForUpdates() { updateService.checkForUpdates() }
    @MainActor func installAvailableUpdate() { updateService.installAvailableUpdate() }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

/// NSWindow forwards drag destination messages to its delegate. Preserve the
/// existing delegate's window behavior while handling file drags at this level.
private final class NativeFileDropRegistration {
    weak var toolbar: NSToolbar?
    let targeted: @MainActor (Bool) -> Void
    let receive: @MainActor ([URL]) -> Void
    private let destinations = NSMapTable<NSWindow, NativeFileDropDelegate>.weakToStrongObjects()

    init(toolbar: NSToolbar, targeted: @MainActor @escaping (Bool) -> Void,
         receive: @MainActor @escaping ([URL]) -> Void) {
        self.toolbar = toolbar
        self.targeted = targeted
        self.receive = receive
    }
    func attach() {
        guard let toolbar else { return }
        var windows = NSApp.windows.filter { $0.toolbar === toolbar }
        // In full screen, AppKit hosts the toolbar in a separate native window.
        for window in toolbar.items.compactMap({ $0.view?.window }) where !windows.contains(window) {
            windows.append(window)
        }
        for window in windows {
            let delegate: NativeFileDropDelegate
            if let existing = destinations.object(forKey: window) {
                guard window.delegate !== existing else { continue }
                existing.original = window.delegate
                delegate = existing
            } else {
                delegate = NativeFileDropDelegate(original: window.delegate, targeted: targeted, receive: receive)
                destinations.setObject(delegate, forKey: window)
            }
            window.delegate = delegate
            window.registerForDraggedTypes([.fileURL])
        }
    }
    @MainActor func detach() {
        for window in destinations.keyEnumerator().allObjects.compactMap({ $0 as? NSWindow }) {
            guard let delegate = destinations.object(forKey: window), window.delegate === delegate else { continue }
            window.delegate = delegate.original
        }
        destinations.removeAllObjects()
        targeted(false)
    }
#if WEIBEI_ACCEPTANCE_CHECKS
    @MainActor func check(urls: [URL]) -> [String: Bool] {
        attach()
        let windows = destinations.keyEnumerator().allObjects.compactMap { $0 as? NSWindow }
        guard let window = windows.first(where: { $0.toolbar === toolbar }),
              let delegate = destinations.object(forKey: window) else { return [:] }
        // Scene transitions may replace AppKit's original delegate. Keep the
        // registration bound and continue forwarding to the latest delegate.
        window.delegate = delegate.original
        attach()
        let rebound = window.delegate === delegate
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects(urls as [NSURL])
        let loaded = NativeFileDropDelegate.fileURLs(from: board)
        // The real Finder payload reaches AppKit as file URLs, even when
        // Catalyst would expose only content-type + Finder node providers.
        let roundTrip = loaded == urls
        board.clearContents()
        board.setString("pane-id", forType: .string)
        let rejectsText = NativeFileDropDelegate.fileURLs(from: board).isEmpty
        board.clearContents()
        board.writeObjects(urls as [NSURL])
        return ["registered_window": window.delegate === delegate,
                "file_urls_preserved": roundTrip, "text_rejected": rejectsText,
                "reattached_after_delegate_change": rebound]
    }
#endif
}

private final class NativeFileDropDelegate: NSObject, NSWindowDelegate, NSDraggingDestination {
#if WEIBEI_ACCEPTANCE_CHECKS
    weak var original: (any NSWindowDelegate)? {
        didSet {
            if original !== oldValue {
                originalChanges.append(Self.describe(oldValue) + " -> " + Self.describe(original))
                if originalChanges.count > 16 { originalChanges.removeFirst() }
            }
        }
    }
    private var originalChanges: [String] = []
    private var fullScreenQueries: [String: String] = [:]
    private var fullScreenForwards: [String: String] = [:]
    static func describe(_ delegate: AnyObject?) -> String {
        guard let delegate else { return "nil" }
        return String(reflecting: type(of: delegate)) + " " + String(describing: ObjectIdentifier(delegate))
    }
    var fullScreenDiagnostics: [String: String] {
        ["file_drop_original_delegate": Self.describe(original),
         "file_drop_original_changes": originalChanges.joined(separator: "\n"),
         "file_drop_full_screen_queries": fullScreenQueries.keys.sorted().map { $0 + ": " + fullScreenQueries[$0]! }.joined(separator: "\n"),
         "file_drop_full_screen_forwards": fullScreenForwards.keys.sorted().map { $0 + ": " + fullScreenForwards[$0]! }.joined(separator: "\n")]
    }
#else
    weak var original: (any NSWindowDelegate)?
#endif
    let targeted: @MainActor (Bool) -> Void
    let receive: @MainActor ([URL]) -> Void
    init(original: (any NSWindowDelegate)?, targeted: @MainActor @escaping (Bool) -> Void,
         receive: @MainActor @escaping ([URL]) -> Void) {
        self.original = original; self.targeted = targeted; self.receive = receive
        super.init()
#if WEIBEI_ACCEPTANCE_CHECKS
        originalChanges = [Self.describe(original)]
#endif
    }
    override func responds(to selector: Selector!) -> Bool {
#if WEIBEI_ACCEPTANCE_CHECKS
        let response = super.responds(to: selector) || original?.responds(to: selector) == true
        if let selector {
            let name = NSStringFromSelector(selector)
            if name.contains("FullScreen") {
                fullScreenQueries[name] = String(response) + " " + Self.describe(original)
            }
        }
        return response
#else
        return super.responds(to: selector) || original?.responds(to: selector) == true
#endif
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
#if WEIBEI_ACCEPTANCE_CHECKS
        let target = original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        if let selector {
            let name = NSStringFromSelector(selector)
            if name.contains("FullScreen") {
                fullScreenForwards[name] = target.map { Self.describe($0 as AnyObject) } ?? "nil"
            }
        }
        return target
#else
        return original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
#endif
    }
    static func fileURLs(from board: NSPasteboard) -> [URL] {
        (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let accepted = !Self.fileURLs(from: sender.draggingPasteboard).isEmpty
        targeted(accepted)
        return accepted ? .copy : []
    }
    func draggingExited(_ sender: (any NSDraggingInfo)?) { targeted(false) }
    func draggingEnded(_ sender: any NSDraggingInfo) { targeted(false) }
    func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        !Self.fileURLs(from: sender.draggingPasteboard).isEmpty
    }
    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { receiveDrop(from: sender.draggingPasteboard) }
    @MainActor func receiveDrop(from board: NSPasteboard) -> Bool {
        targeted(false)
        let urls = Self.fileURLs(from: board)
        guard !urls.isEmpty else { return false }
        receive(urls)
        return true
    }
}
