import UIKit
import SwiftUI
import WeiBeiCore

final class AppDelegate: UIResponder, UIApplicationDelegate {
    static let usesFixture = CommandLine.arguments.contains("--self-check") || CommandLine.arguments.contains("--fixtures")
    static var businessCheckEndpoint: String? {
        guard Bundle.main.bundleIdentifier?.hasSuffix(".businesscheck") == true,
              let value = Bundle.main.object(forInfoDictionaryKey: "LabBusinessCheckEndpoint") as? String,
              value.hasPrefix("http://127.0.0.1:") else { return nil }
        return value
    }
    static let workspace: WorkspaceStore = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
            .appendingPathComponent("Workspace", isDirectory: true)
        // Set before constructing the original store: library, accounts and sessions
        // must never discover the production workspace through their default paths.
        setenv("WEIBEI_WORKSPACE_DIR", root.path, 1)
        WeiBeiPerf.beginLaunch()
        WorkspaceStore.loadPersistedGlassIntensity()
        return WorkspaceStore(workspaceDirectory: root,
            noteBackupRootURL: root.appendingPathComponent(NoteBackupRing.subdirectoryName),
            startsAtBlankEntries: true)
    }()
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
            UIKeyCommand(title: title, action: #selector(performWorkspaceCommand(_:)), input: key, modifierFlags: modifiers, propertyList: id)
        }
        builder.replaceChildren(ofMenu: .preferences) { _ in [command(store.ui("设置…", "Settings…"), ",", "settings")] }
        builder.replaceChildren(ofMenu: .newScene) { _ in [
            command(store.ui("新建空白笔记", "New Blank Note"), "n", "new-note"),
            command(store.ui("打开资料", "Open Material"), "o", "open"),
            command(store.ui("打开课程空间", "Open Course Space"), "0", "courses")
        ] }
        let groups = AppShortcutGroup.allCases.map { group in
            UIMenu(title: group.title(language: store.interfaceLanguage), children: group.shortcuts.compactMap { id in
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
            })
        }
        builder.insertChild(UIMenu(title: store.ui("工作区", "Workspace"), children: groups), atEndOfMenu: .view)
        builder.insertChild(UIMenu(title: store.ui("文字大小", "Text Size"), children: [
            command(store.ui("放大文字", "Zoom In"), "+", "zoom-in"),
            command(store.ui("缩小文字", "Zoom Out"), "-", "zoom-out"),
            command(store.ui("重置文字大小", "Reset Text Size"), "0", "zoom-reset", modifiers: [.command, .alternate])
        ]), atEndOfMenu: .view)
    }

    @objc private func performWorkspaceCommand(_ command: UICommand) {
        guard let value = command.propertyList as? String else { return }
        let store = Self.workspace
        switch value {
        case "settings": NotificationCenter.default.post(name: .weibeiOpenSettings, object: nil)
        case "new-note": store.promptCreateBlankNotebookNote()
        case "open": store.importFilesFromPanel()
        case "courses": store.presentCourseWorkspace(.hub)
        case "zoom-in": if let scale = store.interfaceTextScale.nextLarger { store.setInterfaceTextScale(scale) }
        case "zoom-out": if let scale = store.interfaceTextScale.nextSmaller { store.setInterfaceTextScale(scale) }
        case "zoom-reset": store.setInterfaceTextScale(.standard)
        default:
            guard let id = AppShortcutID(rawValue: value) else { return }
            withAnimation(WeiBeiMotion.layout) {
                switch id {
                case .commandPalette: store.commandPalettePresented.toggle()
                case .toggleAppearance: store.toggleAppearanceMode()
                case .navigateBack: store.navigateBackInWorkspace()
                case .navigateForward: store.navigateForwardInWorkspace()
                case .courseIndex: store.toggleLibrary()
                case .searchInMaterial: store.revealReaderSearch()
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
                case .submitAgentDraft: store.submitAgentDraft()
                }
            }
        }
    }

    // Catalyst lets UIApplication background tasks finish during normal Quit.
    // Keep the original editor snapshot -> note write gate -> workspace save order.
    // https://developer.apple.com/videos/play/wwdc2019/235/
    func saveWorkspace() {
        guard !Self.usesFixture else { return }
        guard saveTask == nil else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "保存魏碑工作区") { [weak self] in
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
        _ = Self.workspace.flushPendingWorkspaceSave()
        Self.workspace.shutdownAgentRuntime()
    }
}

@main
struct CatalystWeiBeiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        WindowGroup("魏碑 · Catalyst 独立候选") {
            if AppDelegate.usesFixture {
                CatalystFixtureHost()
            } else {
                CatalystWorkspaceRoot(store: AppDelegate.workspace, appDelegate: appDelegate)
                    .frame(minWidth: 520, minHeight: 720)
                    .ignoresSafeArea(.container, edges: .top)
                    .onOpenURL { AppDelegate.workspace.importFiles([$0]) }
                    .task {
                        if let endpoint = AppDelegate.businessCheckEndpoint {
                            await CatalystBusinessCheck.run(store: AppDelegate.workspace, endpoint: endpoint)
                        }
                    }
            }
        }
        .defaultSize(width: 1240, height: 760)
        WindowGroup("设置", id: "weibei-settings") {
            SettingsView()
                .weiBeiMotionScoped()
                .environmentObject(AppDelegate.workspace)
                .frame(minWidth: 700, minHeight: 600)
                .background(CatalystWindowChrome(appearanceMode: AppDelegate.workspace.appearanceMode))
                .ignoresSafeArea(.container, edges: .top)
        }
        .defaultSize(width: 900, height: 640)
    }
}

private struct CatalystFixtureHost: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WorkspaceController { WorkspaceController() }
    func updateUIViewController(_ controller: WorkspaceController, context: Context) {}
}

private struct CatalystWorkspaceRoot: View {
    @ObservedObject var store: WorkspaceStore
    let appDelegate: AppDelegate
    @Environment(\.colorScheme) private var systemAppearance
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ContentView()
            .environmentObject(store)
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
