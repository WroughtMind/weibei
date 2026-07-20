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
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            sharedWorkspaceStore.handleAppShortcut(event) ? nil : event
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = sender.windows.first(where: { $0.canBecomeKey }) {
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
            } else {
                reopenMainWindow?()
            }
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
        ProcessInfo.processInfo.environment["WEIBEI_SUPPRESS_ACTIVATION"] != "1"
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
                Button(store.ui("打开资料关系台", "Open Course Relations")) { store.presentCourseWorkspace() }
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
        withAnimation(WeiBeiMotion.appearance) {
            action()
        }
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

private struct WeiBeiAppearanceTransition: ViewModifier {
    var mode: WeiBeiAppearanceMode
    @State private var washOpacity = 0.0
    @State private var washColor = Color.clear

    func body(content: Content) -> some View {
        content
            .animation(WeiBeiMotion.appearance, value: mode)
            .overlay {
                washColor
                    .opacity(washOpacity)
                    .allowsHitTesting(false)
            }
            .onChange(of: mode) { oldMode, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    washColor = Color(nsColor: oldMode.windowBackground)
                    washOpacity = 0.36
                }
                DispatchQueue.main.async {
                    withAnimation(WeiBeiMotion.appearance) {
                        washOpacity = 0
                    }
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
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(view.window)
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
        window.isMovableByWindowBackground = true
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Self.capture(window, to: capturePath)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + stageDelay) {
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
        } else {
            payload["actualPNG"] = NSNull()
            payload["actualPNGPath"] = NSNull()
            payload["pngBytes"] = NSNull()
            payload["pngSHA256"] = NSNull()
            payload["pngHash"] = NSNull()
            payload["webViewSnapshotCount"] = NSNull()
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

    private static func capture(
        _ window: NSWindow,
        to capturePath: String,
        completion: @escaping (VerificationCaptureResult?, String?) -> Void = { _, _ in }
    ) {
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
                    webViewSnapshotCount: overlays.count
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
        webView.takeSnapshot(with: nil) { image, error in
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
        let converted = webView.convert(webView.bounds, to: contentView)
        let rect = contentView.isFlipped
            ? NSRect(x: converted.minX, y: contentView.bounds.height - converted.maxY, width: converted.width, height: converted.height)
            : converted
        guard rect.width > 1, rect.height > 1 else {
            captureWebViews(
                webViews,
                at: index + 1,
                relativeTo: contentView,
                overlays: overlays,
                completion: completion
            )
            return
        }
        captureWebViewSnapshot(webView) { image, failureReason in
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

struct SettingsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedSection: SettingsSection = .overview
    @FocusState private var focusedField: Field?

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
                .overlay(WeiBeiTheme.hairline.opacity(0.55))
            settingsDetail
        }
        .frame(width: 860, height: 610)
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .preferredColorScheme(store.appearanceMode.colorScheme)
        .modifier(WeiBeiAppearanceTransition(mode: store.appearanceMode))
        .onAppear {
            selectedSection = .overview
        }
    }

    private enum Field: Hashable {
        case apiKey
        case model
    }

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case overview
        case appearance
        case reading
        case writing
        case agent
        case data
        case shortcuts

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "seal"
            case .appearance: return "slider.horizontal.3"
            case .reading: return "book.pages"
            case .writing: return "square.and.pencil"
            case .agent: return "text.bubble"
            case .data: return "folder"
            case .shortcuts: return "command"
            }
        }

        var code: String {
            switch self {
            case .overview: return "HOME"
            case .appearance: return "LOOK"
            case .reading: return "READ"
            case .writing: return "NOTE"
            case .agent: return "CHAT"
            case .data: return "DATA"
            case .shortcuts: return "KEYS"
            }
        }

        @MainActor
        func title(_ store: WorkspaceStore) -> String {
            switch self {
            case .overview: return store.ui("总览", "Overview")
            case .appearance: return store.ui("外观", "Appearance")
            case .reading: return store.ui("阅读", "Reading")
            case .writing: return store.ui("写作", "Writing")
            case .agent: return store.ui("对话", "Chat")
            case .data: return store.ui("资料与数据", "Library & Data")
            case .shortcuts: return store.ui("快捷键", "Shortcuts")
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.ui("设置", "Settings"))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 28, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(store.brandLatinName)
                        .font(WeiBeiTypography.englishBrandFont(size: 18, weight: .semibold))
                    Text("SETTINGS")
                        .font(WeiBeiTypography.englishBrandFont(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.82))
                }
                .foregroundStyle(WeiBeiTheme.cinnabar.opacity(0.90))
                Text(store.ui("管理魏碑的界面、写作、对话和本地资料。", "Manage WeiBei interface, writing, chat, and local library."))
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)

            VStack(spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    settingsSidebarButton(section)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            VStack(alignment: .leading, spacing: 9) {
                settingsPill(
                    title: store.interfaceLanguage.settingsLabel,
                    icon: "character.book.closed",
                    active: false
                )
                settingsPill(
                    title: store.appearanceMode.label(language: store.interfaceLanguage),
                    icon: store.appearanceMode.systemImage,
                    active: false
                )
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
        }
        .frame(width: 218)
        .background {
            ZStack(alignment: .top) {
                WeiBeiTheme.paperInset.opacity(store.appearanceMode == .inkstone ? 0.62 : 0.80)
                LinearGradient(
                    colors: [
                        WeiBeiTheme.glassHighlight.opacity(store.appearanceMode == .inkstone ? 0.09 : 0.20),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 96)
            }
        }
    }

    private var settingsDetail: some View {
        VStack(spacing: 0) {
            settingsHeader
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedSection {
                    case .overview:
                        overviewSettings
                    case .appearance:
                        appearanceSettings
                    case .reading:
                        readingSettings
                    case .writing:
                        writingSettings
                    case .agent:
                        agentSettings
                    case .data:
                        dataSettings
                    case .shortcuts:
                        shortcutSettings
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 34)
                .animation(WeiBeiMotion.panel, value: selectedSection)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
    }

    private var settingsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedSection.title(store))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 24, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(sectionSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            Spacer()
            settingsAppearanceToggleButton
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background {
            ZStack(alignment: .bottom) {
                WeiBeiGlassHeaderBackground(paperOpacity: 0.66, materialOpacity: 0.10)
                WeiBeiHeaderHandoffFade(height: 12, opacity: 0.22)
            }
        }
    }

    private var settingsAppearanceToggleButton: some View {
        Button {
            withAnimation(WeiBeiMotion.appearance) {
                store.toggleAppearanceMode()
            }
        } label: {
            Image(systemName: store.appearanceMode.toggled.systemImage)
        }
        .buttonStyle(WeiBeiIconButtonStyle(size: 30))
        .accessibilityLabel(Text(store.appearanceMode.actionLabel(language: store.interfaceLanguage)))
        .help(store.appearanceMode.actionLabel(language: store.interfaceLanguage))
    }

    private var sectionSubtitle: String {
        switch selectedSection {
        case .overview:
            return store.ui("先看当前状态，再进入具体设置。", "Start with the current state, then drill into details.")
        case .appearance:
            return store.ui("统一控制语言与主题。", "Control language and theme.")
        case .reading:
            return store.ui("阅读设置只放当前已经接入真实行为的开关。", "Reading settings only expose behavior that is already wired.")
        case .writing:
            return store.ui("设置 Markdown 写作形态和笔记默认视图。", "Set Markdown writing behavior and the default note view.")
        case .agent:
            return store.ui("管理对话、上下文、密钥和默认入口。", "Manage chat, context, API key, and the default entry.")
        case .data:
            return store.ui("管理资料导入、笔记和本地数据入口。", "Manage material import, notes, and local data entry points.")
        case .shortcuts:
            return store.ui("查看当前全键盘交互入口。", "Review the current keyboard workflow.")
        }
    }

    private var overviewSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("连接状态", "Connection")) {
                settingsRow(
                    title: store.ui("提供商", "Provider"),
                    detail: store.ui("当前对话路由。", "Current chat routing.")
                ) {
                    settingsPill(
                        title: store.agentProviderID.label(language: store.interfaceLanguage),
                        icon: "network",
                        active: true
                    )
                }
                settingsRow(
                    title: store.ui("密钥", "API Key"),
                    detail: store.openAIKeyHelpText
                ) {
                    settingsPill(
                        title: store.openAIAPIKey.isEmpty ? store.ui("未配置", "Not set") : store.ui("已配置", "Configured"),
                        icon: store.openAIAPIKey.isEmpty ? "key" : "checkmark.seal",
                        active: !store.openAIAPIKey.isEmpty
                    )
                }
                settingsRow(
                    title: store.ui("模型", "Model"),
                    detail: store.modelName
                ) {
                    settingsPill(title: store.modelName, icon: "cpu", active: true)
                }
            }

            settingsGroup(store.ui("数据", "Data")) {
                settingsRow(
                    title: store.ui("资料", "Material"),
                    detail: store.selectedMaterialItem.map(store.displayTitle) ?? store.ui("还没有打开资料。", "No material is open.")
                ) {
                    settingsPill(
                        title: store.selectedMaterialItem?.kind.label(language: store.interfaceLanguage) ?? store.ui("无", "None"),
                        icon: store.selectedMaterialItem?.kind.systemImage ?? "tray",
                        active: store.selectedMaterialItem != nil
                    )
                }
                settingsRow(
                    title: store.ui("笔记", "Note"),
                    detail: store.selectedItem.map(store.displayTitle) ?? store.ui("当前是新笔记。", "The current note is new.")
                ) {
                    settingsPill(title: store.noteRenderMode.label(language: store.interfaceLanguage), icon: "square.and.pencil", active: true)
                }
                settingsRow(
                    title: store.ui("每日灵感", "Daily Inspiration"),
                    detail: store.ui("关闭后只隐藏语录；文稿、对话和笔记入口始终保留。", "Hides sourced quotations only; document, chat, and notes entries always remain.")
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.showDailyInspiration },
                            set: { store.setDailyInspirationEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(WeiBeiTheme.cinnabar)
                    .accessibilityLabel(Text(store.ui("显示每日灵感", "Show Daily Inspiration")))
                }
            }

            settingsGroup(store.ui("快速进入", "Jump To")) {
                settingsRouteRow(
                    title: store.ui("外观与语言", "Appearance & Language"),
                    detail: store.ui("字体、明暗模式。", "Fonts and theme mode."),
                    target: .appearance
                )
                settingsRouteRow(
                    title: store.ui("对话设置", "Chat Settings"),
                    detail: store.ui("提供商、密钥、模型与 Base URL。", "Provider, key, model, and Base URL."),
                    target: .agent
                )
                settingsRouteRow(
                    title: store.ui("资料与笔记", "Library & Notes"),
                    detail: store.ui("导入资料、当前资料、当前笔记。", "Import, current material, and current note."),
                    target: .data
                )
            }

            settingsGroup(store.ui("关于", "About")) {
                settingsRow(
                    title: store.ui("版本", "Version"),
                    detail: store.ui("正式法律文案与许可证在发布 closeout 前定稿，此处只保留信息架构。", "Final legal copy and license land at release closeout; this is the info architecture only.")
                ) {
                    settingsPill(
                        title: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
                        icon: "info.circle",
                        active: false
                    )
                }
                settingsRow(
                    title: store.ui("隐私占位", "Privacy placeholder"),
                    detail: store.ui("密钥存本机钥匙串；材料仅在用户发问时发送给所选提供商。最终隐私文案待发布定稿。", "Keys stay in the local keychain; materials are sent only when the user asks. Final privacy copy is deferred.")
                ) {
                    settingsPill(title: store.ui("待定稿", "TBD"), icon: "hand.raised", active: false)
                }
            }
        }
    }

    private var appearanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("语言", "Language")) {
                settingsRow(
                    title: store.ui("界面语言", "Interface Language"),
                    detail: store.ui("切换后菜单、按钮、状态提示和内置样例标题会同步更新。", "Menus, buttons, status hints, and built-in sample titles update together.")
                ) {
                    segmented(WeiBeiInterfaceLanguage.allCases, active: store.interfaceLanguage) { language in
                        language.settingsLabel
                    } action: { language in
                        withAnimation(WeiBeiMotion.appearance) {
                            store.setInterfaceLanguage(language)
                        }
                    }
                }
            }

            settingsGroup(store.ui("外观", "Appearance")) {
                settingsRow(
                    title: store.ui("明暗模式", "Theme Mode"),
                    detail: store.ui("亮色偏宣纸，暗色偏墨石；切换时保留柔和过渡。", "Light mode leans warm paper; dark mode leans inkstone, with a soft transition.")
                ) {
                    segmented(WeiBeiAppearanceMode.allCases, active: store.appearanceMode) { mode in
                        mode.label(language: store.interfaceLanguage)
                    } action: { mode in
                        withAnimation(WeiBeiMotion.appearance) {
                            store.setAppearanceMode(mode)
                        }
                    }
                }
            }

            settingsGroup(store.ui("工作区", "Workspace")) {
                settingsRow(
                    title: store.ui("布局说明", "Layout Notes"),
                    detail: store.ui("栏位用顶栏显隐与拖拽重排；沉浸阅读/对话/写作用 ⌥⌘R / ⌥⌘A / ⌥⌘N。设置页不再切换布局预设。", "Use top-bar pane toggles and drag-reorder for columns; immersive reading/chat/writing use ⌥⌘R / ⌥⌘A / ⌥⌘N. Settings no longer switches layout presets.")
                ) {
                    settingsPill(
                        title: store.layout.label(language: store.interfaceLanguage),
                        icon: "rectangle.split.3x1",
                        active: false
                    )
                }

                settingsRow(
                    title: store.ui("每日灵感", "Daily Inspiration"),
                    detail: store.ui("只控制空工作区里的出处内容；文稿、对话和笔记入口始终保留。", "Controls sourced material on the empty workspace only; document, chat, and notes entries always remain.")
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { store.showDailyInspiration },
                            set: { store.setDailyInspirationEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(WeiBeiTheme.cinnabar)
                    .accessibilityLabel(Text(store.ui("显示每日灵感", "Show Daily Inspiration")))
                }
            }
        }
    }

    private var readingSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("阅读入口", "Reader Entry")) {
                settingsRow(
                    title: store.ui("资料内搜索", "Search in Material"),
                    detail: store.ui("打开当前材料搜索框；没有资料时不会显示无效入口。", "Opens search for the current material; unavailable entries stay hidden.")
                ) {
                    if store.hasSelectedMaterial {
                        Button(store.ui("打开搜索", "Open Search")) {
                            withAnimation(WeiBeiMotion.panel) {
                                store.revealReaderSearch()
                            }
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: store.showReaderSearch))
                    } else {
                        Text(store.ui("未选择资料", "No material selected"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                }

                settingsRow(
                    title: store.ui("当前阅读位置", "Current Reader Position"),
                    detail: store.currentReferenceTitle
                ) {
                    Text(store.hasSelectedMaterial ? store.ui("可引用", "Reference ready") : store.ui("等待资料", "Waiting"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(store.hasSelectedMaterial ? WeiBeiTheme.link : WeiBeiTheme.tertiaryInk)
                }
            }

            settingsGroup(store.ui("选区", "Selection")) {
                settingsRow(
                    title: store.ui("选区入口", "Selection Entry"),
                    detail: store.ui("当前选区会进入对话补丁组件；正文输入框保持干净。", "Selections attach as context chips so the composer stays clean.")
                ) {
                    settingsPill(
                        title: store.hasSelectionAttachments ? store.ui("\(store.selectionAttachments.count) 个片段", "\(store.selectionAttachments.count) fragments") : store.ui("无片段", "None"),
                        icon: "text.bubble",
                        active: store.hasSelectionAttachments
                    )
                }

            }
        }
    }

    private var writingSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("Markdown", "Markdown")) {
                settingsRow(
                    title: store.ui("笔记模式", "Note Mode"),
                    detail: store.ui("主模式是原地 Markdown 写作，源码只作为辅助检查。", "Live Markdown writing is primary; source is only for checking.")
                ) {
                    segmented(NoteRenderMode.visibleCases, active: store.noteRenderMode.visibleMode) { mode in
                        mode.label(language: store.interfaceLanguage)
                    } action: { mode in
                        withAnimation(WeiBeiMotion.panel) {
                            store.setNoteRenderMode(mode)
                        }
                    }
                }

                settingsRow(
                    title: store.ui("新建笔记", "New Note"),
                    detail: store.ui("空白笔记和资料笔记分开创建，避免误改当前材料或当前笔记。", "Create blank notes and material-based notes separately to avoid changing the current material or note by accident.")
                ) {
                    HStack(spacing: 8) {
                        Button(store.ui("空白", "Blank")) {
                            withAnimation(WeiBeiMotion.panel) {
                                store.promptCreateBlankNotebookNote()
                            }
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())

                        if store.hasSelectedMaterial {
                            Button(store.ui("当前资料", "Current Material")) {
                                withAnimation(WeiBeiMotion.panel) {
                                    store.promptCreateNotebookNoteFromCurrentMaterial()
                                }
                            }
                            .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                    }
                }

                if store.canUseSelectedMarkdownAsNotebookNote {
                    settingsRow(
                        title: store.ui("Markdown 资料", "Markdown Material"),
                        detail: store.ui("把当前 Markdown 文件移到笔记区原地编辑。", "Move the current Markdown file into the note editor.")
                    ) {
                        Button(store.ui("作为笔记编辑", "Edit as Note")) {
                            store.useSelectedMarkdownAsNotebookNote()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                    }
                }
            }

            settingsGroup(store.ui("编辑器外观", "Editor Appearance")) {
                settingsRow(
                    title: store.ui("编辑器主题", "Editor Theme"),
                    detail: store.ui("当前跟随魏碑全局外观，覆盖背景、正文、标题、代码、公式、Callout 和选区。", "Currently follows WeiBei appearance across background, text, headings, code, math, callouts, and selection.")
                ) {
                    settingsPill(title: store.appearanceMode.label(language: store.interfaceLanguage), icon: store.appearanceMode.systemImage, active: true)
                }
            }
        }
    }

    private var agentSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("提供商与模型", "Provider & Model")) {
                settingsRow(
                    title: store.ui("提供商", "Provider"),
                    detail: store.ui("通过 Pi 透传；自定义需填写 Base URL。", "Routed through Pi; custom providers need a Base URL.")
                ) {
                    compactMenu(store.agentProviderID.label(language: store.interfaceLanguage)) {
                        ForEach(AgentProviderID.allCases) { provider in
                            Button(provider.label(language: store.interfaceLanguage)) {
                                withAnimation(WeiBeiMotion.panel) {
                                    store.setAgentProviderID(provider)
                                }
                            }
                        }
                    }
                }

                settingsRow(
                    title: store.ui("对话密钥", "Chat API Key"),
                    detail: store.openAIKeyHelpText
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        SecureField(
                            "",
                            text: $store.openAIAPIKey,
                            prompt: Text(store.ui("对话密钥", "Chat API key"))
                                .font(.system(size: 13))
                                .foregroundStyle(WeiBeiTheme.placeholderInk)
                        )
                        .textFieldStyle(.plain)
                        .foregroundColor(WeiBeiTheme.ink)
                        .focused($focusedField, equals: .apiKey)
                        .font(.system(size: 13))
                        .weibeiInputSurface(active: focusedField == .apiKey, height: 38)
                        .frame(width: 250)
                        .onSubmit { store.saveOpenAIAPIKey() }
                        .onChange(of: focusedField) { _, field in
                            // Persist when leaving the key field so typed keys are not lost.
                            if field != .apiKey {
                                store.saveOpenAIAPIKey()
                            }
                        }

                        HStack(spacing: 8) {
                            Button(store.ui("保存到钥匙串", "Save to Keychain")) { store.saveOpenAIAPIKey() }
                                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                            Button(store.ui("清除", "Clear")) { store.clearOpenAIAPIKey() }
                                .buttonStyle(WeiBeiTextActionButtonStyle())
                        }
                    }
                }

                if let status = store.openAIKeyStatus {
                    settingsNote(status, icon: "checkmark.seal")
                }

                settingsRow(
                    title: store.ui("模型", "Model"),
                    detail: store.ui("本机环境 WEIBEI_OPENAI_MODEL / WEIBEI_PI_MODEL 会覆盖这里。", "Local WEIBEI_OPENAI_MODEL / WEIBEI_PI_MODEL override this field.")
                ) {
                    TextField(
                        "",
                        text: Binding(
                            get: { store.modelName },
                            set: { store.updateModelName($0) }
                        ),
                        prompt: Text(store.agentProviderID.defaultModelHint)
                            .font(.system(size: 13))
                            .foregroundStyle(WeiBeiTheme.placeholderInk)
                    )
                    .textFieldStyle(.plain)
                    .foregroundColor(WeiBeiTheme.ink)
                    .focused($focusedField, equals: .model)
                    .font(.system(size: 13))
                    .weibeiInputSurface(active: focusedField == .model, height: 38)
                    .frame(width: 250)
                }

                if store.agentProviderID == .custom || !store.agentBaseURL.isEmpty {
                    settingsRow(
                        title: store.ui("Base URL", "Base URL"),
                        detail: store.ui("写入 Pi models.json；OpenAI 兼容接口。", "Written into Pi models.json for OpenAI-compatible APIs.")
                    ) {
                        TextField(
                            "",
                            text: Binding(
                                get: { store.agentBaseURL },
                                set: { store.updateAgentBaseURL($0) }
                            ),
                            prompt: Text("https://api.example.com/v1")
                                .font(.system(size: 13))
                                .foregroundStyle(WeiBeiTheme.placeholderInk)
                        )
                        .textFieldStyle(.plain)
                        .foregroundColor(WeiBeiTheme.ink)
                        .font(.system(size: 13))
                        .weibeiInputSurface(active: false, height: 38)
                        .frame(width: 280)
                    }
                }
            }

            settingsGroup(store.ui("对话入口", "Chat Entry")) {
                settingsRow(
                    title: store.ui("入口说明", "Entry Notes"),
                    detail: store.ui("完整对话在主栏与沉浸对话布局；选区轻提示仅作临时入口，可 ⌃⌥0 隐藏。", "Full chat lives in the agent pane and immersive conversation; selection prompt is temporary and can be hidden with ⌃⌥0.")
                ) {
                    settingsPill(
                        title: store.agentSurface.label(language: store.interfaceLanguage),
                        icon: "bubble.left.and.bubble.right",
                        active: store.agentSurface == .selectionFloat
                    )
                }
            }
        }
    }

    private var shortcutSettings: some View {
        settingsGroup(store.ui("当前快捷键", "Current Shortcuts")) {
            ForEach(shortcutRows, id: \.0) { title, shortcut, detail in
                settingsRow(title: title, detail: detail) {
                    Text(shortcut)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(WeiBeiTheme.paperRaised.opacity(0.52))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
                        }
                }
            }
        }
    }

    private var shortcutRows: [(String, String, String)] {
        [
            (store.ui("命令面板", "Command Palette"), "⌘K", store.ui("搜索并执行魏碑动作。", "Search and run WeiBei actions.")),
            (store.ui("课程目录", "Course Index"), "⌘B", store.ui("打开或收起课程目录。", "Show or hide the course index.")),
            (store.ui("资料内搜索", "Search in Material"), "⌘F", store.ui("搜索当前打开的资料。", "Search the current material.")),
            (store.ui("聚焦课程目录", "Focus Course Index"), "⌘1", store.ui("把键盘焦点交给课程目录。", "Move keyboard focus to the course index.")),
            (store.ui("聚焦阅读", "Focus Reader"), "⌘2", store.ui("把键盘焦点交给阅读区。", "Move keyboard focus to the reader.")),
            (store.ui("聚焦笔记", "Focus Notes"), "⌘3", store.ui("把键盘焦点交给笔记区。", "Move keyboard focus to notes.")),
            (store.ui("聚焦对话", "Focus Chat"), "⌘4", store.ui("把键盘焦点交给对话区。", "Move keyboard focus to chat.")),
            (store.ui("沉浸阅读", "Immersive Reading"), "⌥⌘R", store.ui("进入沉浸阅读布局。", "Enter immersive reading layout.")),
            (store.ui("沉浸对话", "Immersive Chat"), "⌥⌘A", store.ui("进入沉浸对话布局。", "Enter immersive conversation layout.")),
            (store.ui("沉浸写作", "Immersive Writing"), "⌥⌘N", store.ui("进入沉浸写作布局。", "Enter immersive writing layout.")),
            (store.ui("选区轻提示", "Selection Prompt"), "⌃⌥3", store.ui("在有选区时打开选区浮层。", "Open the selection float when a selection exists.")),
            (store.ui("隐藏对话浮层", "Hide Chat Overlay"), "⌃⌥0", store.ui("隐藏选区轻提示。", "Hide the selection prompt.")),
            (store.ui("明暗切换", "Toggle Theme"), "⌥⌘T", store.ui("在纸面和墨石之间切换。", "Switch between paper and inkstone.")),
            (store.ui("后退", "Back"), "⌘[", store.ui("回到上一个工作区位置。", "Go back in workspace history.")),
            (store.ui("前进", "Forward"), "⌘]", store.ui("前进到下一个工作区位置。", "Go forward in workspace history.")),
        ]
    }

    private var dataSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup(store.ui("课程资料", "Course Materials")) {
                settingsRow(
                    title: store.ui("导入资料", "Import Material"),
                    detail: store.ui("导入 HTML、PDF、Markdown 或文本文件。", "Import HTML, PDF, Markdown, or text files.")
                ) {
                    Button(store.ui("导入", "Import")) {
                        store.importFilesFromPanel()
                    }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
                }

                settingsRow(
                    title: store.ui("当前资料", "Current Material"),
                    detail: store.selectedMaterialItem.map(store.displayTitle) ?? store.ui("未选择资料", "No material selected")
                ) {
                    settingsPill(
                        title: store.selectedMaterialItem?.kind.label(language: store.interfaceLanguage) ?? store.ui("无", "None"),
                        icon: store.selectedMaterialItem?.kind.systemImage ?? "tray",
                        active: store.selectedMaterialItem != nil
                    )
                }
            }

            settingsGroup(store.ui("笔记", "Notes")) {
                settingsRow(
                    title: store.ui("当前笔记", "Current Note"),
                    detail: store.selectedItem.map(store.displayTitle) ?? store.ui("新笔记", "New Note")
                ) {
                    settingsPill(title: store.noteRenderMode.label(language: store.interfaceLanguage), icon: "square.and.pencil", active: true)
                }

                settingsRow(
                    title: store.ui("选区上下文", "Selection Context"),
                    detail: store.ui("已选文本片段只作为上下文传给对话，不塞进输入框正文。", "Selected fragments are passed as context, not inserted into the composer text.")
                ) {
                    if store.hasSelectionAttachments {
                        Button(store.ui("清空片段", "Clear Fragments")) {
                            store.clearSelectionAttachments()
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                    } else {
                        Text(store.ui("无片段", "None"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    }
                }
            }
        }
    }

    private func settingsRouteRow(title: String, detail: String, target: SettingsSection) -> some View {
        settingsRow(title: title, detail: detail) {
            Button {
                withAnimation(WeiBeiMotion.panel) {
                    selectedSection = target
                }
            } label: {
                HStack(spacing: 7) {
                    Text(target.code)
                        .font(WeiBeiTypography.englishBrandFont(size: 9, weight: .semibold))
                        .tracking(0.9)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(WeiBeiTextActionButtonStyle())
        }
    }

    private func settingsSidebarButton(_ section: SettingsSection) -> some View {
        let active = selectedSection == section
        return Button {
            withAnimation(WeiBeiMotion.panel) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(section.title(store))
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                Spacer()
                Text(section.code)
                    .font(WeiBeiTypography.englishBrandFont(size: 8.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(active ? WeiBeiTheme.cinnabar.opacity(0.82) : WeiBeiTheme.tertiaryInk.opacity(0.72))
            }
            .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.secondaryInk)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(active ? WeiBeiTheme.paperRaised.opacity(0.62) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(active ? WeiBeiTheme.cinnabar.opacity(0.82) : .clear)
                    .frame(width: 2, height: 16)
                    .padding(.leading, 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(section.title(store)))
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(WeiBeiTheme.paperRaised.opacity(store.appearanceMode == .inkstone ? 0.20 : 0.36))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(WeiBeiTheme.hairline.opacity(0.42), lineWidth: 1)
            }
        }
    }

    private func settingsRow<Control: View>(title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(WeiBeiTheme.ink)
                Text(detail)
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 18)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WeiBeiTheme.hairline.opacity(0.28))
                .frame(height: 1)
                .padding(.leading, 14)
        }
    }

    private func settingsNote(_ text: String, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.link)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func settingsPill(title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(active ? WeiBeiTheme.ink : WeiBeiTheme.tertiaryInk)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(active ? WeiBeiTheme.paperRaised.opacity(0.54) : WeiBeiTheme.paperInset.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(WeiBeiTheme.hairline.opacity(active ? 0.46 : 0.24), lineWidth: 1)
        }
    }

    private func segmented<Item: Identifiable & Hashable>(
        _ items: [Item],
        active: Item,
        label: @escaping (Item) -> String,
        action: @escaping (Item) -> Void
    ) -> some View {
        HStack(spacing: 5) {
            ForEach(items) { item in
                Button(label(item)) {
                    action(item)
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: item == active))
            }
        }
    }

    private func compactMenu<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(WeiBeiTheme.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(WeiBeiTheme.paperRaised.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(WeiBeiTheme.hairline.opacity(0.48), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 12, weight: .semibold))
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
    }
}
