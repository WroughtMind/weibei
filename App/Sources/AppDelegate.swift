import UIKit
import SwiftUI
import WeiBeiCore

final class AppDelegate: UIResponder, UIApplicationDelegate {
#if WEIBEI_ACCEPTANCE_CHECKS
    static let checksConversation = CommandLine.arguments.contains("--self-check")
        || Bundle.main.bundleIdentifier?.hasSuffix(".conversationcheck") == true
    static let usesFixture = checksConversation || CommandLine.arguments.contains("--fixtures")
    static var businessCheckEndpoint: String? {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".businesscheck") == true,
              let value = Bundle.main.object(forInfoDictionaryKey: "LabBusinessCheckEndpoint") as? String,
              value.hasPrefix("http://127.0.0.1:") else { return nil }
        return value
    }
#else
    static let checksConversation = false
    static let usesFixture = false
#endif
    static let workspace: WorkspaceStore = {
        WeiBeiPerf.beginLaunch()
        WorkspaceStore.loadPersistedGlassIntensity()
        if Bundle.main.bundleIdentifier == "com.changfenhuang.weibei" {
            return WorkspaceStore()
        }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
        // Set before constructing the original store: library, accounts and sessions
        // must never discover the production workspace through their default paths.
        setenv("WEIBEI_WORKSPACE_DIR", root.path, 1)
        return WorkspaceStore(workspaceDirectory: root,
            noteBackupRootURL: root.appendingPathComponent(NoteBackupRing.subdirectoryName),
            startsAtBlankEntries: true)
    }()
    static let updates = WeiBeiUpdateService()
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var saveTask: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WeiBeiTypography.registerBundledFonts()
        guard !Self.usesFixture else { return true }
        _ = Self.workspace
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveWorkspace() }
        })
        return true
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        guard !Self.usesFixture, builder.system == .main else { return }
        let store = Self.workspace
        func command(_ title: String, _ key: String, _ id: String, modifiers: UIKeyModifierFlags = .command) -> UIKeyCommand {
            let command = UIKeyCommand(title: title, action: #selector(performWorkspaceCommand(_:)), input: key, modifierFlags: modifiers, propertyList: id)
            command.wantsPriorityOverSystemBehavior = id == AppShortcutID.searchInMaterial.rawValue
            return command
        }
        func plainCommand(_ title: String, _ id: String) -> UICommand {
            UICommand(
                title: title,
                image: nil,
                action: #selector(performWorkspaceCommand(_:)),
                propertyList: id,
                alternates: [],
                discoverabilityTitle: nil,
                attributes: [],
                state: .off
            )
        }
        func shortcutCommand(_ id: AppShortcutID) -> UIKeyCommand? {
            guard let chord = store.executableChord(for: id) else { return nil }
            let input: String
            switch chord.key {
            case "return": input = "\r"
            case "up": input = UIKeyCommand.inputUpArrow
            case "down": input = UIKeyCommand.inputDownArrow
            case "left": input = UIKeyCommand.inputLeftArrow
            case "right": input = UIKeyCommand.inputRightArrow
            default: input = chord.key
            }
            return command(id.title(language: store.interfaceLanguage), input, id.rawValue, modifiers: chord.modifiers)
        }
        builder.remove(menu: .textSize)
        builder.replaceChildren(ofMenu: .preferences) { _ in [command(store.ui("设置…", "Settings…"), ",", "settings")] }
        var fileCommands: [UIMenuElement] = [
            command(store.ui("新建空白笔记", "New Blank Note"), "n", "new-note")
        ]
        if let newConversation = shortcutCommand(.newConversation) {
            fileCommands.append(newConversation)
        }
        fileCommands.append(contentsOf: [
            command(store.ui("打开文稿", "Open Document"), "o", "open"),
            command(store.ui("打开课程空间", "Open Course Space"), "0", "courses")
        ])
        builder.replaceChildren(ofMenu: .newScene) { _ in fileCommands }
        let movedToEdit: Set<AppShortcutID> = [.applyAgentAnswerToNote, .copyCurrentReference]
        let placedInFile: Set<AppShortcutID> = [.newConversation]
        let groups = AppShortcutGroup.allCases.map { group in
            UIMenu(
                title: group.title(language: store.interfaceLanguage),
                options: .displayInline,
                children: group.shortcuts.compactMap { id in
                    guard !movedToEdit.contains(id), !placedInFile.contains(id) else { return nil }
                    return shortcutCommand(id)
                }
            )
        }
        builder.insertChild(UIMenu(title: store.ui("工作台", "Workspace"), children: groups), atEndOfMenu: .view)
        // ⌘= is the unlabeled key under ⌘+. It must not reuse propertyList "zoom-in":
        // UIMenuBuilder rejects a second performWorkspaceCommand: with that list.
        let zoomInEquals = command(store.ui("放大文字", "Zoom In"), "=", "zoom-in-equals")
        zoomInEquals.attributes = .hidden
        builder.insertChild(UIMenu(title: store.ui("文字大小", "Text Size"), children: [
            command(store.ui("放大文字", "Zoom In"), "+", "zoom-in"),
            zoomInEquals,
            command(store.ui("缩小文字", "Zoom Out"), "-", "zoom-out"),
            command(store.ui("重置文字大小", "Reset Text Size"), "0", "zoom-reset", modifiers: [.command, .alternate])
        ]), atEndOfMenu: .view)
        let editCommands = [AppShortcutID.applyAgentAnswerToNote, .copyCurrentReference].compactMap(shortcutCommand)
        if !editCommands.isEmpty {
            builder.insertChild(UIMenu(options: .displayInline, children: editCommands), atEndOfMenu: .edit)
        }
        builder.insertChild(UIMenu(options: .displayInline, children: [
            plainCommand(store.ui("检查更新…", "Check for Updates…"), "check-updates")
        ]), atEndOfMenu: .application)
        builder.replaceChildren(ofMenu: .help) { _ in [
            plainCommand(store.ui("反馈问题…", "Report an Issue…"), "help-feedback"),
            plainCommand(store.ui("魏碑官网", "WeiBei Website"), "help-website"),
            plainCommand(store.ui("隐私说明", "Privacy"), "help-privacy")
        ] }
    }

    override func validate(_ command: UICommand) {
        guard let value = command.propertyList as? String else { return }
        let enabled: Bool
        if let id = AppShortcutID(rawValue: value) {
            enabled = Self.shortcutIsEnabled(id)
        } else {
            return
        }
        if enabled {
            command.attributes.remove(.disabled)
        } else {
            command.attributes.insert(.disabled)
        }
    }

    @objc private func performWorkspaceCommand(_ command: UICommand) {
        guard let value = command.propertyList as? String else { return }
        let store = Self.workspace
        switch value {
        case "settings": Self.openSettingsWindow()
        case "check-updates": Self.updates.checkForUpdates()
        case "help-feedback": Self.open(WeiBeiHelpLinks.feedback)
        case "help-website": Self.open(WeiBeiHelpLinks.website)
        case "help-privacy": Self.open(WeiBeiHelpLinks.privacy)
        case "new-note": Self.revealWorkspaceThen { store.promptCreateBlankNotebookNote() }
        case "open": Self.revealWorkspaceThen { store.importFilesFromPanel() }
        case "courses": store.presentCourseWorkspace(.hub)
        case "zoom-in", "zoom-in-equals": if let scale = store.interfaceTextScale.nextLarger { store.setInterfaceTextScale(scale) }
        case "zoom-out": if let scale = store.interfaceTextScale.nextSmaller { store.setInterfaceTextScale(scale) }
        case "zoom-reset": store.setInterfaceTextScale(.standard)
        default:
            guard let id = AppShortcutID(rawValue: value) else { return }
            Self.revealWorkspaceThen {
                if id == .toggleAppearance {
                    store.toggleLightDarkAppearance()
                    return
                }
                withAnimation(WeiBeiMotion.layout) {
                    switch id {
                    case .commandPalette: store.commandPalettePresented.toggle()
                    case .newConversation: _ = store.createStudySession(courseID: nil)
                    case .toggleAppearance: break
                    case .navigateBack: store.navigateBackInWorkspace()
                    case .navigateForward: store.navigateForwardInWorkspace()
                    case .courseIndex: store.toggleLibrary()
                    case .searchInMaterial: store.revealDocumentSearch()
                    case .focusLibrary: store.focus(.library)
                    case .focusReader: store.focus(.reader)
                    case .focusNotes: store.focus(.notes)
                    case .focusChat: store.focus(.agent)
                    case .previousMaterial: store.selectAdjacentItem(step: -1)
                    case .nextMaterial: store.selectAdjacentItem(step: 1)
                    case .toggleRightPane: store.toggleRightPane()
                    case .threePaneWorkspace: store.setLayout(.documentAgentNotes)
                    case .swapThreePaneSecondaryPanes: store.swapThreePaneSecondaryPanes()
                    case .immersiveReading: store.setLayout(.immersiveReading)
                    case .immersiveChat: store.setLayout(.immersiveConversation)
                    case .immersiveWriting: store.setLayout(.immersiveWriting)
                    case .selectionPrompt: store.setAgentSurface(.selectionFloat)
                    case .hideChatOverlay: store.setAgentSurface(.hidden)
                    case .applyAgentAnswerToNote: store.applyLastAgentAnswerToNote()
                    case .replaceNoteSelection: store.replaceSelectionWithLastAgentAnswer()
                    case .applyAgentPatchToEditor: store.applyAgentPatchToEditor()
                    case .copyCurrentReference: store.copyCurrentReference()
                    case .submitAgentDraft:
                        guard Self.agentComposerIsFirstResponder() else { return }
                        store.submitAgentDraft()
                    }
                }
            }
        }
    }

    private static func revealWorkspaceThen(_ action: () -> Void) {
        let store = workspace
        if store.courseWorkspacePresented {
            store.dismissCourseWorkspace()
        }
        action()
    }

    private static func openSettingsWindow() {
        if let scene = settingsScene {
            UIApplication.shared.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil, errorHandler: nil)
            return
        }
        NotificationCenter.default.post(name: .weibeiOpenSettings, object: nil)
    }

    private static var settingsScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first {
            ($0.session.userInfo?["weibei-settings"] as? Bool) == true
        }
    }

    private static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private static func shortcutIsEnabled(_ id: AppShortcutID) -> Bool {
        let store = workspace
        switch id {
        case .commandPalette:
            return !noteEditorIsFirstResponder()
        case .submitAgentDraft:
            return agentComposerIsFirstResponder()
        case .navigateBack:
            return store.canNavigateBack
        case .navigateForward:
            return store.canNavigateForward
        case .searchInMaterial:
            return store.canSearchCurrentDocument
        case .toggleRightPane:
            return store.layout != .immersiveConversation
        case .swapThreePaneSecondaryPanes:
            return store.layout.isDocumentThreePane
        case .applyAgentAnswerToNote, .applyAgentPatchToEditor:
            return store.canApplyAgentAnswer
        case .replaceNoteSelection:
            return store.canReplaceNoteSelection
        case .copyCurrentReference:
            return store.canCopyReference
        case .selectionPrompt:
            return store.canUseSelectionAgentSurface
        case .hideChatOverlay:
            return store.agentSurface != .hidden
        case .newConversation, .toggleAppearance, .courseIndex, .focusLibrary, .focusReader,
             .focusNotes, .focusChat, .previousMaterial, .nextMaterial, .threePaneWorkspace,
             .immersiveReading, .immersiveChat, .immersiveWriting:
            return true
        }
    }

    /// K4: 判断当前第一响应者是否为对话输入框（主对话与选区浮层的 ComposerTextView）。
    private static func agentComposerIsFirstResponder() -> Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let responder = firstResponder(in: window) as? AgentComposerTextEditor.ComposerTextView,
                   responder.submitsAgentDraft {
                    return true
                }
            }
        }
        return false
    }

    /// ⌘K stays with the note editor while it is first responder.
    private static func noteEditorIsFirstResponder() -> Bool {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                guard let responder = firstResponder(in: window) else { continue }
                var view: UIView? = responder
                while let current = view {
                    if String(describing: type(of: current)) == "MarkdownWebView" { return true }
                    view = current.superview
                }
            }
        }
        return false
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }

    // Catalyst lets UIApplication background tasks finish during normal Quit.
    // Keep the original editor snapshot -> note write gate -> workspace save order.
    // https://developer.apple.com/videos/play/wwdc2019/235/
    func saveWorkspace() {
        guard !Self.usesFixture else { return }
        guard saveTask == nil else { return }
        Self.workspace.commitCurrentReaderLocation()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "保存魏碑工作台") { [weak self] in
            MainActor.assumeIsolated {
                self?.saveTask?.cancel()
                _ = Self.workspace.flushPendingWorkspaceSave()
                self?.finishBackgroundSave()
            }
        }
        saveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let store = Self.workspace
            let captured = await store.freshActiveNoteEditorSnapshot()
            guard !Task.isCancelled else { return }
            guard captured else {
                store.showImportantOperationError(store.ui("笔记最新内容尚未安全保存，请保持窗口打开并重试。", "The latest note is not safely saved. Keep the window open and retry."))
                reopenAfterSaveFailure()
                return
            }
            store.flushPendingNotePersistence(flushWorkspace: false)
            guard await store.flushPendingWorkspaceSaveAsync() else {
                reopenAfterSaveFailure()
                return
            }
            finishBackgroundSave()
        }
    }

    private func reopenAfterSaveFailure() {
        saveTask = nil
        UIApplication.shared.requestSceneSessionActivation(UIApplication.shared.openSessions.first, userActivity: nil, options: nil) { error in
            WeiBeiLog.noteRepair.error("code=catalyst_save_reopen_failed reason=\(error.localizedDescription, privacy: .private)")
        }
        // The background assertion ends when the reactivated scene is visible.
    }
    func sceneBecameActive() {
        if saveTask == nil { finishBackgroundSave() }
        Task { await Self.workspace.reconcileActiveNoteEditorWithBackingFile() }
    }
    private func finishBackgroundSave() {
        saveTask = nil
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    func applicationWillTerminate(_ application: UIApplication) {
        guard !Self.usesFixture else { return }
        Self.workspace.cancelAllAgentRequests()
        Self.workspace.commitCurrentReaderLocation()
        _ = Self.workspace.flushPendingWorkspaceSave()
        Self.workspace.shutdownAgentRuntime()
    }
}

@main
struct CatalystWeiBeiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup("魏碑") {
#if WEIBEI_ACCEPTANCE_CHECKS
            if AppDelegate.usesFixture {
                CatalystFixtureHost()
            } else {
                workspaceContent
            }
#else
            workspaceContent
#endif
        }
        // Catalyst turns defaultSize into fixed native size constraints on macOS 27.
        // CatalystWindowChrome requests the initial frame without restricting later resizing.
        WindowGroup(id: "weibei-settings", for: String.self) { _ in
            SettingsView()
                .weiBeiMotionScoped()
                .environmentObject(AppDelegate.workspace)
                .environmentObject(AppDelegate.updates)
                .background(CatalystWindowChrome(appearanceMode: AppDelegate.workspace.appearanceMode,
                                                initialSize: WeiBeiSettingsLayout.initialSize,
                                                minimumSize: WeiBeiSettingsLayout.minimumSize,
                                                allowsFullScreen: false))
                .background(SettingsSceneMarker())
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    private var workspaceContent: some View {
        // Native size restrictions own the minimum; scrolling panes extend under the toolbar.
        CatalystWorkspaceRoot(store: AppDelegate.workspace, appDelegate: appDelegate)
            .onOpenURL { AppDelegate.workspace.receiveExternalFileForConfirmedImport($0) }
#if WEIBEI_ACCEPTANCE_CHECKS
            .task {
                if CommandLine.arguments.contains("--drag-profile"),
                   Bundle.main.bundleIdentifier?.hasSuffix(".dragprofile") == true {
                    await CatalystBusinessCheck.runDragProfile(store: AppDelegate.workspace)
                } else if let endpoint = AppDelegate.businessCheckEndpoint {
                    if CommandLine.arguments.contains("--quit-save-check") || CommandLine.arguments.contains("--verify-quit-save") {
                        await CatalystBusinessCheck.runQuitSaveCheck(store: AppDelegate.workspace)
                    } else {
                        await CatalystBusinessCheck.run(store: AppDelegate.workspace, endpoint: endpoint)
                    }
                }
            }
#endif
    }
}

enum WeiBeiHelpLinks {
    static let feedback = WeiBeiFeedbackLink.newIssue
    static let website = URL(string: "https://wroughtmind.github.io/weibei/")!
    static let privacy = URL(string: "https://github.com/WroughtMind/weibei/blob/main/PRIVACY.md")!
}

private struct SettingsSceneMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> Marker { Marker() }
    func updateUIView(_ view: Marker, context: Context) { view.tagScene() }
    final class Marker: UIView {
        private let toolbar = NSToolbar(identifier: "weibei.settings")
        override func didMoveToWindow() { super.didMoveToWindow(); tagScene() }
        func tagScene() {
            guard let scene = window?.windowScene else { return }
            let session = scene.session
            var info = session.userInfo ?? [:]
            info["weibei-settings"] = true
            session.userInfo = info
            // The native bridge recognizes this utility window before it is ordered front.
            if scene.titlebar?.toolbar !== toolbar { scene.titlebar?.toolbar = toolbar }
            CatalystDesktopWindow.configure(mode: AppDelegate.workspace.appearanceMode)
        }
    }
}

#if WEIBEI_ACCEPTANCE_CHECKS
private struct CatalystFixtureHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WorkspaceController { WorkspaceController() }
    func updateUIViewController(_ controller: WorkspaceController, context: Context) {}
}
#endif

private struct CatalystWorkspaceRoot: View {
    @ObservedObject var store: WorkspaceStore
    let appDelegate: AppDelegate
    @Environment(\.colorScheme) private var systemAppearance
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ContentView()
            .environmentObject(store)
            .environmentObject(AppDelegate.updates)
            .environmentObject(store.libraryDrawer)
            .environmentObject(store.threePaneReorder)
            .environmentObject(store.paneState)
            .environmentObject(store.interaction)
            .preferredColorScheme(store.appearanceMode.colorScheme)
            .environment(\.weiBeiTextScale, store.interfaceTextScale.multiplier)
            .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
            .background(CatalystWindowChrome(appearanceMode: store.appearanceMode))
            .onAppear { store.refreshAppearanceForSystemChange() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { appDelegate.sceneBecameActive() }
                else { appDelegate.saveWorkspace() }
            }
            .onChange(of: store.customShortcutOverrides) { _, _ in UIMenuSystem.main.setNeedsRebuild() }
            .onChange(of: store.interfaceLanguage) { _, _ in UIMenuSystem.main.setNeedsRebuild() }
            .onChange(of: systemAppearance) { _, _ in store.refreshAppearanceForSystemChange() }
    }
}
