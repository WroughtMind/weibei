import AppKit
import CryptoKit
import SwiftUI
import WebKit
import WeiBeiCore

private let runsImportedIdentitySelfCheck = ProcessInfo.processInfo.arguments.contains("--self-check-imported-identity")
private let importedIdentitySelfCheckBootstrapDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("weibei-imported-identity-bootstrap-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)

@MainActor private let sharedWorkspaceStore = runsImportedIdentitySelfCheck
    ? WorkspaceStore(workspaceDirectory: importedIdentitySelfCheckBootstrapDirectory)
    : WorkspaceStore()

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var shortcutMonitor: Any?
    var reopenMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        WeiBeiTypography.registerBundledFonts()
        NSApp.setActivationPolicy(.regular)
        if shouldActivateOnLaunch {
            NSApp.activate(ignoringOtherApps: true)
        }
        if shouldActivateOnLaunch {
            shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                sharedWorkspaceStore.handleAppShortcut(event) ? nil : event
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let reusableWindow = sender.windows.first(where: { $0.canBecomeKey })
        switch MainWindowReopenPolicy.action(hasVisibleWindows: flag, hasReusableWindow: reusableWindow != nil) {
        case .none:
            break
        case .showExistingWindow:
            if let window = reusableWindow {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            }
        case .openMainWindow:
            reopenMainWindow?()
        }
        if shouldActivateOnLaunch {
            NSApp.activate(ignoringOtherApps: true)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        sharedWorkspaceStore.flushPendingNotePersistence()
        sharedWorkspaceStore.flushPendingWorkspaceSave()
        sharedWorkspaceStore.shutdownAgentRuntime()
        if let shortcutMonitor {
            NSEvent.removeMonitor(shortcutMonitor)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Durability + less work at quit: flush pending note/workspace saves on focus loss.
        sharedWorkspaceStore.flushPendingNotePersistence()
        sharedWorkspaceStore.flushPendingWorkspaceSave()
    }

    private var shouldActivateOnLaunch: Bool {
        AppLaunchPolicy.shouldActivate(environment: ProcessInfo.processInfo.environment)
    }
}

@main
struct WeiBeiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = sharedWorkspaceStore

    init() {
        if runsImportedIdentitySelfCheck {
            defer { try? FileManager.default.removeItem(at: importedIdentitySelfCheckBootstrapDirectory) }
            do {
                try ImportedIdentitySelfCheck.run()
                print("WeiBei imported identity self-checks passed")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("WeiBei imported identity self-check failed: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        WeiBeiTypography.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup("魏碑", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(store.libraryDrawer)
                .environmentObject(store.threePaneReorder)
                .preferredColorScheme(store.appearanceMode.colorScheme)
                .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
                .background(WindowChromeConfigurator(appearanceMode: store.appearanceMode))
                .background(MainWindowReopenBridge(appDelegate: appDelegate))
                .onOpenURL { url in
                    store.importFiles([url])
                }
                .onAppear {
                    Task { await store.runVerificationScenarioIfNeeded() }
                }
                .frame(minWidth: 1120, minHeight: 720)
                .ignoresSafeArea(.container, edges: .top)
        }
        .defaultSize(width: 1240, height: 760)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu(store.appDisplayName) {
                Button(store.ui("打开课程空间", "Open Course Space")) { store.presentCourseWorkspace(.hub) }
                    .keyboardShortcut("0")

                Divider()

                Button(store.ui("打开资料", "Open Material")) { store.importFilesFromPanel() }
                    .keyboardShortcut("o")

                Button(store.ui("新建空白笔记", "New Blank Note")) { animateLayout { store.promptCreateBlankNotebookNote() } }
                    .keyboardShortcut("n")
                if store.hasSelectedMaterial {
                    Button(store.ui("从当前资料开笔记", "Note from Current Material")) {
                        animateLayout { store.promptCreateNotebookNoteFromCurrentMaterial() }
                    }
                }

                Divider()

                Button(store.ui("聚焦课程目录", "Focus Course Index")) { animateLayout { store.focus(.library) } }
                    .keyboardShortcut("1")
                Button(store.ui("聚焦阅读", "Focus Reader")) { animateLayout { store.focus(.reader) } }
                    .keyboardShortcut("2")
                Button(store.ui("聚焦笔记", "Focus Notes")) { animateLayout { store.focus(.notes) } }
                    .keyboardShortcut("3")
                Button(store.ui("聚焦对话", "Focus Chat")) { animateLayout { store.focus(.agent) } }
                    .keyboardShortcut("4")

                Divider()

                Button(store.ui("上一份资料", "Previous Material")) { animateLayout { store.selectAdjacentItem(step: -1) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button(store.ui("下一份资料", "Next Material")) { animateLayout { store.selectAdjacentItem(step: 1) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Divider()

                Button(store.showLibrary ? store.ui("收起课程目录", "Hide Course Index") : store.ui("打开课程目录", "Show Course Index")) {
                    store.toggleLibrary()
                }
                    .keyboardShortcut("b")
                if store.layout.hasCollapsibleRightPane {
                    Button(store.showRightPane ? store.ui("收起辅助栏", "Hide Assistant Pane") : store.ui("展开辅助栏", "Show Assistant Pane")) {
                        animateLayout {
                            store.toggleRightPane()
                        }
                    }
                    .keyboardShortcut("j")
                }

                Divider()

                Button(store.ui("三栏工作台", "Three-Pane Workspace")) { setLayout(.documentAgentNotes) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button(WorkspaceLayout.documentNotesSplit.label(language: store.interfaceLanguage)) { setLayout(.documentNotesSplit) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                if store.layout.isDocumentThreePane {
                    Button(store.ui("交换笔记与对话", "Swap Notes and Chat")) {
                        animateLayout {
                            store.swapThreePaneSecondaryPanes()
                        }
                    }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                }
                Button(WorkspaceLayout.immersiveReading.label(language: store.interfaceLanguage)) { setLayout(.immersiveReading) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Button(WorkspaceLayout.immersiveConversation.label(language: store.interfaceLanguage)) { setLayout(.immersiveConversation) }
                    .keyboardShortcut("a", modifiers: [.command, .option])
                Button(WorkspaceLayout.immersiveWriting.label(language: store.interfaceLanguage)) { setLayout(.immersiveWriting) }
                    .keyboardShortcut("n", modifiers: [.command, .option])

                Divider()

                Button(store.appearanceMode.actionLabel(language: store.interfaceLanguage)) {
                    animateAppearance {
                        store.toggleAppearanceMode()
                    }
                }
                    .keyboardShortcut("t", modifiers: [.command, .option])

                Divider()

                if store.canUseSelectionAgentSurface {
                    Button(AgentSurface.selectionFloat.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.selectionFloat) }
                        .keyboardShortcut("3", modifiers: [.control, .option])
                }
                Button(AgentSurface.hidden.actionLabel(language: store.interfaceLanguage)) { setAgentSurface(.hidden) }
                    .keyboardShortcut("0", modifiers: [.control, .option])

                Divider()

                Button(store.ui("笔记原地写作", "Live Markdown Writing")) { setNoteRenderMode(.rich) }
                    .keyboardShortcut("1", modifiers: [.control, .command])
                Button(store.ui("笔记源码对照", "Source Compare")) { setNoteRenderMode(.split) }
                    .keyboardShortcut("2", modifiers: [.control, .command])
                Button(store.ui("笔记源码", "Note Source")) { setNoteRenderMode(.source) }
                    .keyboardShortcut("3", modifiers: [.control, .command])

                if store.canApplyAgentAnswer {
                    Divider()

                    Button(store.ui("写入回答到笔记", "Write Answer to Note")) { animatePanel { store.applyLastAgentAnswerToNote() } }
                        .keyboardShortcut("a", modifiers: [.command, .shift])
                    if store.canReplaceNoteSelection {
                        Button(store.ui("替换笔记选区", "Replace Note Selection")) { animatePanel { store.replaceSelectionWithLastAgentAnswer() } }
                            .keyboardShortcut("r", modifiers: [.command, .shift])
                    }
                    Button(store.ui("追加整理建议", "Append Organization Suggestion")) { animatePanel { store.applyAgentPatchToEditor() } }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                }

                Divider()

                Button(store.ui("命令面板", "Command Palette")) {
                    animatePanel {
                        store.commandPalettePresented.toggle()
                    }
                }
                    .keyboardShortcut("k")

                Divider()

                if store.canCopyReference {
                    Button(store.copyReferenceActionTitle) { store.copyCurrentReference() }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                }
                if store.hasSelectedMaterial {
                    Button(store.ui("打开资料内搜索", "Search in Material")) {
                        animatePanel {
                            store.revealReaderSearch()
                        }
                    }
                    .keyboardShortcut("f")
                }
                if store.isAskingAgent || !store.agentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(store.sendAgentActionTitle) {
                        store.isAskingAgent ? store.cancelAgentRequest() : store.askAgent()
                    }
                        .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }

    private func animateLayout(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.layout) {
            action()
        }
    }

    private func animatePanel(_ action: () -> Void) {
        withAnimation(WeiBeiMotion.panel) {
            action()
        }
    }

    private func animateAppearance(_ action: () -> Void) {
        // Theme animation is owned by WorkspaceStore.setAppearanceMode.
        action()
    }

    private func setLayout(_ layout: WorkspaceLayout) {
        animateLayout {
            store.setLayout(layout)
        }
    }

    private func setAgentSurface(_ surface: AgentSurface) {
        animatePanel {
            store.setAgentSurface(surface)
        }
    }

    private func setNoteRenderMode(_ mode: NoteRenderMode) {
        animatePanel {
            store.setNoteRenderMode(mode)
        }
    }
}

private struct MainWindowReopenBridge: View {
    @Environment(\.openWindow) private var openWindow
    weak var appDelegate: AppDelegate?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate?.reopenMainWindow = {
                    openWindow(id: "main")
                }
            }
    }
}

// Internal (not private) so SettingsView.swift — now in its own file — can apply
// this modifier. Was `private` when SettingsView lived in this same file (L1).
struct WeiBeiAppearanceTransition: ViewModifier {
    var mode: WeiBeiAppearanceMode
    @State private var washOpacity = 0.0
    @State private var washColor = Color.clear

    func body(content: Content) -> some View {
        // No nested `.animation(value: mode)` here — ContentView / Settings already
        // animate once at the root. A second animation made chrome lag the paper.
        content
            .overlay {
                washColor
                    .opacity(washOpacity)
                    .allowsHitTesting(false)
            }
            .onChange(of: mode) { oldMode, _ in
                // Brief wash only when light↔dark family flips; same-family (纸面↔宣纸)
                // must feel instant without a laggy overlay.
                guard AppearanceTransitionPolicy.stagesWash(from: oldMode, to: mode) else {
                    washOpacity = 0
                    return
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    washColor = Color(nsColor: oldMode.windowBackground)
                    washOpacity = 0.16
                }
                withAnimation(WeiBeiMotion.appearance) {
                    washOpacity = 0
                }
            }
    }
}

@MainActor
private struct WindowChromeConfigurator: NSViewRepresentable {
    private static var scheduledVerificationCaptures: Set<String> = []
    private static var scheduledVerificationCaptureChannels: Set<String> = []
    private static var processedVerificationCaptureRequests: Set<String> = []
    private static let webViewSnapshotTimeoutSeconds: TimeInterval = 4

    var appearanceMode: WeiBeiAppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Apply immediately when the window is already attached; otherwise one async hop.
        if let window = view.window {
            configure(window)
        } else {
            DispatchQueue.main.async {
                configure(view.window)
            }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Sync chrome with the theme publish — async defer made the titlebar lag panes.
        if let window = view.window {
            configure(window)
        } else {
            DispatchQueue.main.async {
                configure(view.window)
            }
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
        window.isOpaque = true
        window.backgroundColor = appearanceMode.windowBackground
        window.appearance = NSAppearance(named: appearanceMode.isDark ? .darkAqua : .aqua)
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = ProcessInfo.processInfo.environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1"
        applyVerificationWindowSize(to: window)
        captureVerificationWindowIfRequested(window)
        listenForVerificationCaptureRequestsIfRequested(window)
    }

    private func applyVerificationWindowSize(to window: NSWindow) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1",
              let rawSize = environment["WEIBEI_VERIFY_WINDOW_SIZE"] else { return }
        let parts = rawSize.lowercased().split(separator: "x", maxSplits: 1)
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width >= 600,
              height >= 400 else { return }

        let target = NSSize(width: width, height: height)
        let current = window.contentLayoutRect.size
        guard abs(current.width - target.width) > 1 || abs(current.height - target.height) > 1 else { return }
        window.setContentSize(target)
        window.center()
    }

    private func captureVerificationWindowIfRequested(_ window: NSWindow) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1",
              let capturePath = environment["WEIBEI_VERIFY_CAPTURE_PATH"],
              !capturePath.isEmpty,
              Self.scheduledVerificationCaptures.insert(capturePath).inserted else { return }

        let scenario = environment["WEIBEI_VERIFY_SCENARIO"] ?? ""
        if [
            "pi-learning-flow",
            "pi-course-memory-flow",
            "pane-toggle-continuity-flow",
            "reader-scroll-persistence-flow",
            "course-workspace-overview-flow",
            "course-workspace-workflow-flow",
        ].contains(scenario),
           let workspaceDirectory = environment["WEIBEI_WORKSPACE_DIR"] {
            let stateURL = URL(fileURLWithPath: workspaceDirectory)
                .appendingPathComponent("verification-state.txt")
            Self.waitForVerificationCompletion(
                in: window,
                capturePath: capturePath,
                stateURL: stateURL,
                remainingAttempts: scenario == "pane-toggle-continuity-flow" ? 1_800 : 600
            )
            return
        }

        Self.waitForSingleCaptureReadiness(in: window, remainingAttempts: 50) { result in
            switch result {
            case .ready:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    Self.capture(window, to: capturePath)
                }
            case .failed(let failureReason):
                fputs("WeiBei verification legacy single capture failed: \(failureReason)\n", stderr)
            }
        }
    }

    private struct VerificationCaptureRequest: Decodable {
        var id: String
        var capturePath: String
        var stage: String?
    }

    private struct VerificationCaptureResult {
        var pngPath: String
        var bytes: Int
        var sha256: String
        var capturedAt: String
        var webViewSnapshotCount: Int
        var workspaceStateAtStart: VerificationWorkspaceState
        var workspaceStateAtEnd: VerificationWorkspaceState
    }

    private struct VerificationWorkspaceState: Equatable {
        var layout: String
        var showReader: Bool
        var showAgent: Bool
        var showNotes: Bool
        var selectedItemID: String?
        var visiblePanes: [String]
        var paneFrames: [String: CGRect]

        var payload: [String: Any] {
            [
                "layout": layout,
                "showReader": showReader,
                "showAgent": showAgent,
                "showNotes": showNotes,
                "selectedItemID": selectedItemID ?? NSNull(),
                "visiblePanes": visiblePanes,
                "paneFrames": paneFrames.mapValues { frame in
                    [
                        "x": frame.minX,
                        "y": frame.minY,
                        "width": frame.width,
                        "height": frame.height,
                    ]
                },
            ]
        }

        var diagnosticDescription: String {
            "layout=\(layout),reader=\(showReader),agent=\(showAgent),notes=\(showNotes),visible=\(visiblePanes.joined(separator: ",")),selected=\(selectedItemID ?? "none")"
        }
    }

    private func listenForVerificationCaptureRequestsIfRequested(_ window: NSWindow) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WEIBEI_SUPPRESS_ACTIVATION"] == "1",
              let rawChannelPath = environment["WEIBEI_VERIFY_CAPTURE_REQUEST_DIR"],
              !rawChannelPath.isEmpty,
              let rawOutputPath = environment["WEIBEI_VERIFY_CAPTURE_OUTPUT_DIR"],
              !rawOutputPath.isEmpty else { return }

        let channelURL = URL(fileURLWithPath: rawChannelPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let outputURL = URL(fileURLWithPath: rawOutputPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let channelID = "\(channelURL.path)#\(ObjectIdentifier(window).hashValue)"
        guard Self.scheduledVerificationCaptureChannels.insert(channelID).inserted else { return }
        guard Self.isSafeVerificationOutputRoot(outputURL) else {
            fputs("WeiBei verification capture output root is unsafe: \(outputURL.path)\n", stderr)
            return
        }
        guard Self.isCaptureURL(channelURL, inside: outputURL) else {
            fputs("WeiBei verification capture channel must stay inside output root: \(channelURL.path)\n", stderr)
            return
        }

        try? FileManager.default.createDirectory(at: channelURL, withIntermediateDirectories: true)
        Self.scheduleVerificationCapturePoll(
            in: window,
            channelURL: channelURL,
            outputURL: outputURL
        )
    }

    private static func scheduleVerificationCapturePoll(
        in window: NSWindow,
        channelURL: URL,
        outputURL: URL
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
            guard let window else { return }
            pollVerificationCaptureRequests(
                in: window,
                channelURL: channelURL,
                outputURL: outputURL
            )
        }
    }

    private static func pollVerificationCaptureRequests(
        in window: NSWindow,
        channelURL: URL,
        outputURL: URL
    ) {
        let requestURL = channelURL.appendingPathComponent("request.json")
        guard let data = try? Data(contentsOf: requestURL),
              let request = try? JSONDecoder().decode(VerificationCaptureRequest.self, from: data),
              !request.id.isEmpty else {
            scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
            return
        }

        let requestKey = "\(channelURL.path)::\(request.id)"
        guard processedVerificationCaptureRequests.insert(requestKey).inserted else {
            scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
            return
        }

        let captureURL = URL(fileURLWithPath: request.capturePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard isCaptureURL(captureURL, inside: outputURL),
              captureURL.pathExtension.lowercased() == "png" else {
            writeVerificationCaptureAcknowledgement(
                request: request,
                status: "failed",
                failureReason: "capture path must be a PNG inside the configured output directory",
                channelURL: channelURL
            )
            scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
            return
        }

        let verificationStage = request.stage?.lowercased()
        if verificationStage == "single" {
            waitForSingleCaptureReadiness(in: window, remainingAttempts: 50) { result in
                switch result {
                case .ready:
                    completeVerificationCaptureRequest(
                        request: request,
                        in: window,
                        captureURL: captureURL,
                        channelURL: channelURL,
                        outputURL: outputURL,
                        delay: 0.25
                    )
                case .failed(let failureReason):
                    writeVerificationCaptureAcknowledgement(
                        request: request,
                        status: "failed",
                        failureReason: failureReason,
                        channelURL: channelURL
                    )
                    scheduleVerificationCapturePoll(
                        in: window,
                        channelURL: channelURL,
                        outputURL: outputURL
                    )
                }
            }
            return
        }

        let stageDelay: TimeInterval
        if let verificationStage, ["overview", "before", "after"].contains(verificationStage) {
            NotificationCenter.default.post(
                name: .weiBeiRichAnswerVerificationStage,
                object: nil,
                userInfo: ["stage": verificationStage]
            )
            stageDelay = verificationStage == "after" ? 1.1 : 0.8
        } else {
            stageDelay = 0
        }
        completeVerificationCaptureRequest(
            request: request,
            in: window,
            captureURL: captureURL,
            channelURL: channelURL,
            outputURL: outputURL,
            delay: stageDelay
        )
    }

    private static func completeVerificationCaptureRequest(
        request: VerificationCaptureRequest,
        in window: NSWindow,
        captureURL: URL,
        channelURL: URL,
        outputURL: URL,
        delay: TimeInterval
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(window, to: captureURL.path) { captureResult, failureReason in
                writeVerificationCaptureAcknowledgement(
                    request: request,
                    status: failureReason == nil ? "succeeded" : "failed",
                    failureReason: failureReason,
                    captureResult: captureResult,
                    channelURL: channelURL
                )
                scheduleVerificationCapturePoll(in: window, channelURL: channelURL, outputURL: outputURL)
            }
        }
    }

    private static func isSafeVerificationOutputRoot(_ outputURL: URL) -> Bool {
        let resolvedURL = outputURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        let allowedRoots = [
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
            FileManager.default.temporaryDirectory,
        ].map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        return allowedRoots.contains { rootPath in
            let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
            let prefix = normalizedRoot + "/"
            guard resolvedURL.path.hasPrefix(prefix) else { return false }
            let relativePath = resolvedURL.path.dropFirst(prefix.count)
            guard let evidenceRoot = relativePath.split(separator: "/").first else { return false }
            return evidenceRoot.hasPrefix("weibei-rich-answer-")
        }
    }

    private static func isCaptureURL(_ captureURL: URL, inside outputURL: URL) -> Bool {
        let rootPath = outputURL.standardizedFileURL.resolvingSymlinksInPath().path
        let captureParentPath = captureURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return isPath(captureParentPath, insideDirectory: rootPath)
    }

    private static func isPath(_ path: String, insideDirectory rootPath: String) -> Bool {
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        let prefix = normalizedRoot + "/"
        return path == normalizedRoot || path.hasPrefix(prefix)
    }

    private static func writeVerificationCaptureAcknowledgement(
        request: VerificationCaptureRequest,
        status: String,
        failureReason: String?,
        captureResult: VerificationCaptureResult? = nil,
        channelURL: URL
    ) {
        let acknowledgementURL = channelURL.appendingPathComponent("ack.json")
        var payload: [String: Any] = [
            "id": request.id,
            "requestID": request.id,
            "requestCapturePath": request.capturePath,
            "stage": request.stage ?? NSNull(),
            "capturePath": captureResult?.pngPath ?? request.capturePath,
            "status": status,
            "failureReason": failureReason ?? NSNull(),
            "acknowledgedAt": iso8601String(Date()),
            "renderReady": renderReadyEvidencePayload(),
            "webViewSnapshotTimeoutSeconds": webViewSnapshotTimeoutSeconds,
            "workspaceState": verificationWorkspaceState().payload,
        ]
        if let captureResult {
            payload["actualPNG"] = [
                "path": captureResult.pngPath,
                "bytes": captureResult.bytes,
                "sha256": captureResult.sha256,
                "hash": "sha256:\(captureResult.sha256)",
                "capturedAt": captureResult.capturedAt,
            ]
            payload["actualPNGPath"] = captureResult.pngPath
            payload["pngBytes"] = captureResult.bytes
            payload["pngSHA256"] = captureResult.sha256
            payload["pngHash"] = "sha256:\(captureResult.sha256)"
            payload["webViewSnapshotCount"] = captureResult.webViewSnapshotCount
            payload["captureWorkspaceState"] = [
                "start": captureResult.workspaceStateAtStart.payload,
                "end": captureResult.workspaceStateAtEnd.payload,
                "stable": captureResult.workspaceStateAtStart == captureResult.workspaceStateAtEnd,
            ]
        } else {
            payload["actualPNG"] = NSNull()
            payload["actualPNGPath"] = NSNull()
            payload["pngBytes"] = NSNull()
            payload["pngSHA256"] = NSNull()
            payload["pngHash"] = NSNull()
            payload["webViewSnapshotCount"] = NSNull()
            payload["captureWorkspaceState"] = NSNull()
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        do {
            try data.write(to: acknowledgementURL, options: .atomic)
        } catch {
            fputs("WeiBei verification capture acknowledgement failed: \(error.localizedDescription)\n", stderr)
        }
    }

    private static func renderReadyEvidencePayload() -> [String: Any] {
        let observedAt = iso8601String(Date())
        guard let workspaceDirectory = ProcessInfo.processInfo.environment["WEIBEI_WORKSPACE_DIR"],
              !workspaceDirectory.isEmpty else {
            return [
                "seen": false,
                "observedAt": observedAt,
                "failureReason": "WEIBEI_WORKSPACE_DIR is unavailable",
            ]
        }
        let markerURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .appendingPathComponent("rich-answer-renderer-ready.txt")
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return [
                "seen": false,
                "path": markerURL.path,
                "observedAt": observedAt,
                "failureReason": "renderer-ready marker is absent",
            ]
        }
        guard let markerData = try? Data(contentsOf: markerURL),
              !markerData.isEmpty else {
            return [
                "seen": false,
                "path": markerURL.path,
                "observedAt": observedAt,
                "failureReason": "renderer-ready marker is empty or unreadable",
            ]
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: markerURL.path)
        let modifiedAt = (attributes?[.modificationDate] as? Date).map(iso8601String)
        let sha256 = sha256Hex(for: markerData)
        return [
            "seen": true,
            "path": markerURL.path,
            "bytes": markerData.count,
            "sha256": sha256,
            "signature": "sha256:\(sha256)",
            "readyAt": modifiedAt ?? observedAt,
            "observedAt": observedAt,
            "modifiedAt": modifiedAt ?? NSNull(),
        ]
    }

    private static func verificationWorkspaceState() -> VerificationWorkspaceState {
        let visiblePaneRoles = sharedWorkspaceStore.visibleDocumentPaneOrder
        let frameList = sharedWorkspaceStore.threePaneReorderFrameList(
            order: visiblePaneRoles,
            fallback: []
        )
        let frames: [String: CGRect]
        if frameList.count == visiblePaneRoles.count {
            frames = Dictionary(uniqueKeysWithValues: zip(visiblePaneRoles, frameList).map { role, frame in
                (role.rawValue, frame)
            })
        } else {
            frames = [:]
        }
        return VerificationWorkspaceState(
            layout: sharedWorkspaceStore.layout.rawValue,
            showReader: sharedWorkspaceStore.showReader,
            showAgent: sharedWorkspaceStore.showAgent,
            showNotes: sharedWorkspaceStore.showNotes,
            selectedItemID: sharedWorkspaceStore.selectedItemID,
            visiblePanes: visiblePaneRoles.map(\.rawValue),
            paneFrames: frames
        )
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func waitForVerificationCompletion(
        in window: NSWindow,
        capturePath: String,
        stateURL: URL,
        remainingAttempts: Int
    ) {
        let stages = (try? String(contentsOf: stateURL, encoding: .utf8)) ?? ""
        if stages.split(separator: "\n").contains("completed") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                capture(window, to: capturePath)
            }
            return
        }
        guard remainingAttempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            waitForVerificationCompletion(
                in: window,
                capturePath: capturePath,
                stateURL: stateURL,
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    private enum SingleCaptureReadinessResult {
        case ready
        case failed(String)
    }

    private struct CompactPreviewReadiness {
        var compactCount: Int
        var pendingCount: Int
        var evaluationFailureCount: Int
        var measuredHeights: [Int]

        var isReady: Bool {
            pendingCount == 0 && evaluationFailureCount == 0
        }

        func isStable(comparedTo previous: CompactPreviewReadiness) -> Bool {
            isReady
                && previous.isReady
                && compactCount == previous.compactCount
                && measuredHeights == previous.measuredHeights
        }
    }

    private static func waitForSingleCaptureReadiness(
        in window: NSWindow,
        remainingAttempts: Int,
        previousReadiness: CompactPreviewReadiness? = nil,
        completion: @escaping (SingleCaptureReadinessResult) -> Void
    ) {
        guard let contentView = window.contentView else {
            completion(.failed("window content view is unavailable while waiting for compact preview readiness"))
            return
        }
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let webViews = visibleWebViews(in: contentView)
        guard !webViews.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                completion(.ready)
            }
            return
        }
        compactPreviewReadiness(in: webViews) { readiness in
            if let previousReadiness,
               readiness.isStable(comparedTo: previousReadiness) {
                completion(.ready)
                return
            }
            guard remainingAttempts > 0 else {
                completion(
                    .failed(
                        "compact preview readiness timed out "
                            + "(compact: \(readiness.compactCount), "
                            + "pending: \(readiness.pendingCount), "
                            + "evaluation failures: \(readiness.evaluationFailureCount))"
                    )
                )
                return
            }
            let nextPreviousReadiness = readiness.isReady ? readiness : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                waitForSingleCaptureReadiness(
                    in: window,
                    remainingAttempts: remainingAttempts - 1,
                    previousReadiness: nextPreviousReadiness,
                    completion: completion
                )
            }
        }
    }

    private static func compactPreviewReadiness(
        in webViews: [WKWebView],
        completion: @escaping (CompactPreviewReadiness) -> Void
    ) {
        compactPreviewReadiness(
            in: webViews,
            at: 0,
            current: CompactPreviewReadiness(
                compactCount: 0,
                pendingCount: 0,
                evaluationFailureCount: 0,
                measuredHeights: []
            ),
            completion: completion
        )
    }

    private static func compactPreviewReadiness(
        in webViews: [WKWebView],
        at index: Int,
        current: CompactPreviewReadiness,
        completion: @escaping (CompactPreviewReadiness) -> Void
    ) {
        guard webViews.indices.contains(index) else {
            completion(current)
            return
        }
        let script = """
        (() => {
          const compact = window.weiBeiMarkdownCompactPreview === true
            || document.documentElement.dataset.weibeiCompactPreview === 'true';
          if (!compact) return { compact: false, ready: true };
          const nodes = [
            document.querySelector('#editor'),
            document.querySelector('.milkdown'),
            document.querySelector('.ProseMirror')
          ].filter(Boolean);
          const nodeHeight = (node) => {
            const rect = node.getBoundingClientRect?.();
            return Math.max(
              0,
              node.scrollHeight || 0,
              node.offsetHeight || 0,
              node.clientHeight || 0,
              rect?.height || 0
            );
          };
          const height = Math.ceil(Math.max(0, ...nodes.map(nodeHeight)));
          const reportedHeight = Number(window.WeiBeiCompactPreviewHeight || 0);
          const measuredAt = Number(window.WeiBeiCompactPreviewMeasuredAt || 0);
          const ready = nodes.length > 0
            && Number.isFinite(height)
            && height > 0
            && Number.isFinite(reportedHeight)
            && reportedHeight > 0
            && Math.abs(reportedHeight - height) <= 1
            && Number.isFinite(measuredAt)
            && measuredAt > 0;
          return { compact: true, ready, height, reportedHeight, measuredAt };
        })();
        """
        webViews[index].evaluateJavaScript(script) { result, error in
            var next = current
            if error != nil {
                next.evaluationFailureCount += 1
            } else if let payload = result as? [String: Any],
                      let isCompact = payload["compact"] as? Bool {
                guard isCompact else {
                    compactPreviewReadiness(
                        in: webViews,
                        at: index + 1,
                        current: next,
                        completion: completion
                    )
                    return
                }
                next.compactCount += 1
                if payload["ready"] as? Bool == true,
                   let height = payload["height"] as? NSNumber,
                   height.doubleValue.isFinite,
                   height.doubleValue > 0 {
                    next.measuredHeights.append(height.intValue)
                } else {
                    next.pendingCount += 1
                }
            } else {
                next.evaluationFailureCount += 1
            }
            compactPreviewReadiness(
                in: webViews,
                at: index + 1,
                current: next,
                completion: completion
            )
        }
    }

    private static func capture(
        _ window: NSWindow,
        to capturePath: String,
        completion: @escaping (VerificationCaptureResult?, String?) -> Void = { _, _ in }
    ) {
        let workspaceStateAtStart = verificationWorkspaceState()
        guard !FileManager.default.fileExists(atPath: capturePath) else {
            completion(nil, "capture target already exists")
            return
        }
        guard let contentView = window.contentView else {
            completion(nil, "window content view is unavailable")
            return
        }
        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bounds = contentView.bounds
        guard bounds.width >= 600,
              bounds.height >= 400 else {
            completion(nil, "window content bounds are smaller than the verification minimum")
            return
        }
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            completion(nil, "window content bitmap could not be allocated")
            return
        }
        contentView.cacheDisplay(in: bounds, to: bitmap)
        let baseImage = NSImage(size: bounds.size)
        baseImage.addRepresentation(bitmap)
        let webViews = visibleWebViews(in: contentView)
        captureWebViews(webViews, at: 0, relativeTo: contentView, overlays: []) { overlays, webViewFailure in
            if let webViewFailure {
                completion(nil, webViewFailure)
                return
            }
            let workspaceStateAtEnd = verificationWorkspaceState()
            guard workspaceStateAtStart == workspaceStateAtEnd else {
                completion(
                    nil,
                    "workspace state changed during capture: \(workspaceStateAtStart.diagnosticDescription) -> \(workspaceStateAtEnd.diagnosticDescription)"
                )
                return
            }
            let composite = NSImage(size: bounds.size)
            composite.lockFocus()
            baseImage.draw(in: bounds)
            for overlay in overlays {
                overlay.image.draw(in: overlay.rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            composite.unlockFocus()
            guard let tiff = composite.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiff),
                  let png = representation.representation(using: .png, properties: [:]) else {
                completion(nil, "captured window could not be encoded as PNG")
                return
            }
            let captureURL = URL(fileURLWithPath: capturePath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            do {
                try png.write(to: captureURL, options: .atomic)
            } catch {
                completion(nil, "captured PNG could not be written: \(error.localizedDescription)")
                return
            }
            guard let writtenData = try? Data(contentsOf: captureURL),
                  !writtenData.isEmpty else {
                completion(nil, "captured PNG could not be verified after write")
                return
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: captureURL.path)
            let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? writtenData.count
            completion(
                VerificationCaptureResult(
                    pngPath: captureURL.path,
                    bytes: bytes,
                    sha256: sha256Hex(for: writtenData),
                    capturedAt: iso8601String(Date()),
                    webViewSnapshotCount: overlays.count,
                    workspaceStateAtStart: workspaceStateAtStart,
                    workspaceStateAtEnd: workspaceStateAtEnd
                ),
                nil
            )
        }
    }

    private final class WebViewSnapshotState {
        var isCompleted = false
    }

    private static func completeWebViewSnapshotOnce(
        state: WebViewSnapshotState,
        completion: @escaping (NSImage?, String?) -> Void,
        image: NSImage?,
        failureReason: String?
    ) {
        guard !state.isCompleted else { return }
        state.isCompleted = true
        completion(image, failureReason)
    }

    private static func captureWebViewSnapshot(
        _ webView: WKWebView,
        rect: NSRect,
        completion: @escaping (NSImage?, String?) -> Void
    ) {
        let state = WebViewSnapshotState()
        DispatchQueue.main.asyncAfter(deadline: .now() + webViewSnapshotTimeoutSeconds) {
            completeWebViewSnapshotOnce(
                state: state,
                completion: completion,
                image: nil,
                failureReason: "web content snapshot timed out after \(String(format: "%.1f", webViewSnapshotTimeoutSeconds)) seconds"
            )
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        webView.takeSnapshot(with: configuration) { image, error in
            DispatchQueue.main.async {
                if let error {
                    completeWebViewSnapshotOnce(
                        state: state,
                        completion: completion,
                        image: nil,
                        failureReason: "web content snapshot failed: \(error.localizedDescription)"
                    )
                    return
                }
                guard let image else {
                    completeWebViewSnapshotOnce(
                        state: state,
                        completion: completion,
                        image: nil,
                        failureReason: "web content snapshot returned no image"
                    )
                    return
                }
                completeWebViewSnapshotOnce(
                    state: state,
                    completion: completion,
                    image: image,
                    failureReason: nil
                )
            }
        }
    }

    private static func visibleRect(
        of webView: WKWebView,
        relativeTo contentView: NSView
    ) -> NSRect {
        var visibleRect = webView.convert(webView.bounds, to: contentView)
            .intersection(contentView.bounds)
        var ancestor = webView.superview
        while let view = ancestor, view !== contentView, !visibleRect.isNull {
            visibleRect = visibleRect.intersection(view.convert(view.bounds, to: contentView))
            ancestor = view.superview
        }
        return visibleRect
    }

    private struct WebViewSnapshot {
        var rect: NSRect
        var image: NSImage
    }

    private static func visibleWebViews(in view: NSView) -> [WKWebView] {
        view.subviews.flatMap { child -> [WKWebView] in
            var matches = child.isHidden ? [] : visibleWebViews(in: child)
            if let webView = child as? WKWebView, !webView.isHidden, webView.window != nil {
                matches.insert(webView, at: 0)
            }
            return matches
        }
    }

    private static func captureWebViews(
        _ webViews: [WKWebView],
        at index: Int,
        relativeTo contentView: NSView,
        overlays: [WebViewSnapshot],
        completion: @escaping ([WebViewSnapshot], String?) -> Void
    ) {
        guard webViews.indices.contains(index) else {
            completion(overlays, nil)
            return
        }
        let webView = webViews[index]
        let converted = visibleRect(of: webView, relativeTo: contentView)
        let rect = contentView.isFlipped
            ? NSRect(x: converted.minX, y: contentView.bounds.height - converted.maxY, width: converted.width, height: converted.height)
            : converted
        guard !converted.isNull, rect.width > 1, rect.height > 1 else {
            captureWebViews(
                webViews,
                at: index + 1,
                relativeTo: contentView,
                overlays: overlays,
                completion: completion
            )
            return
        }
        let snapshotRect = webView.convert(converted, from: contentView)
            .intersection(webView.bounds)
        guard !snapshotRect.isNull, snapshotRect.width > 1, snapshotRect.height > 1 else {
            captureWebViews(
                webViews,
                at: index + 1,
                relativeTo: contentView,
                overlays: overlays,
                completion: completion
            )
            return
        }
        captureWebViewSnapshot(webView, rect: snapshotRect) { image, failureReason in
            if let failureReason {
                completion(overlays, failureReason)
                return
            }
            guard let image else {
                completion(overlays, "web content snapshot returned no image")
                return
            }
            var nextOverlays = overlays
            nextOverlays.append(WebViewSnapshot(rect: rect, image: image))
            captureWebViews(
                webViews,
                at: index + 1,
                relativeTo: contentView,
                overlays: nextOverlays,
                completion: completion
            )
        }
    }
}
