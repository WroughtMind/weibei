#if CHAT_RENDERER_LAB || CHAT_RENDERER_BASELINE
import AppKit
import ChatRendererKit
import SwiftUI
import WeiBeiCore

@main
@MainActor
enum ChatRendererEntry {
    static func main() {
        guard ChatRendererExperiment.verificationDirectory != nil else { WeiBeiApp.main(); return }
        let app = NSApplication.shared
        let delegate = VerificationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) { app.run() }
    }
    private final class VerificationDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            WeiBeiTypography.registerBundledFonts()
            ChatRendererExperiment.didLaunch(store: ChatRendererExperiment.makeStore())
        }
    }
}

/// Only compiled into the separately identified experiment app. Requests, note
/// actions, persistence and the visible workspace keep their normal entry points.
@MainActor
enum ChatRendererExperiment {
    static let scenarioTitles = ["长历史 · 384 条", "少量消息 · 长正文与代码", "富内容 · 来源与动作"]
    static var verificationDirectory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(where: { $0 == "--chat-renderer-verify" || $0 == "--chat-renderer-benchmark" }), args.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: args[index + 1], isDirectory: true)
    }
    static func makeStore() -> WorkspaceStore {
        let root = (verificationDirectory ?? WeiBeiAgentDataPaths.applicationSupportRoot)
            .appendingPathComponent("Workspace", isDirectory: true)
        setenv("WEIBEI_WORKSPACE_DIR", root.path, 1)
        return WorkspaceStore(workspaceDirectory: root,
            noteBackupRootURL: root.appendingPathComponent(NoteBackupRing.subdirectoryName),
            startsAtBlankEntries: false)
    }
    static func didLaunch(store: WorkspaceStore) {
        Task { @MainActor in
            do {
                try await seedIfNeeded(store)
                if ProcessInfo.processInfo.arguments.contains("--chat-renderer-benchmark"), let directory = verificationDirectory {
                    try await ChatRendererPaneEvidence.run(store: store, directory: directory)
                    NSApp.terminate(nil)
                    return
                }
#if CHAT_RENDERER_LAB
                if let directory = verificationDirectory {
                    await ChatRendererConversationChecks.run(store: store, directory: directory)
                }
#endif
            } catch {
                if let directory = verificationDirectory {
                    try? String(describing: error).write(to: directory.appendingPathComponent("fatal.txt"), atomically: true, encoding: .utf8)
                    NSApp.terminate(nil)
                } else { NSLog("实验内容初始化失败：%@", error.localizedDescription) }
            }
        }
    }
    static func open(_ title: String, store: WorkspaceStore) {
        guard let session = store.studySessions.first(where: { $0.title == title }) else { return }
        _ = store.activateStudySession(session.id, expectedCourseID: nil, expectedScopeNeedsReview: false)
        store.setLayout(.immersiveConversation)
    }
    static func seedIfNeeded(_ store: WorkspaceStore) async throws {
        guard store.studySessions.allSatisfy({ $0.messages.isEmpty }) else { return }
        let library = store.workspaceDirectory.deletingLastPathComponent().appendingPathComponent("实验资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try await store.configureCourseLibraryAsync(at: library)
        let courseID = try await store.createCourseInLibraryAsync(title: "会话实验")
        guard let noteID = await store.createCourseNotebookNote(courseID: courseID,
            title: "阅读位置实验笔记", markdown: "# 阅读位置实验笔记\n\n这是一份合成笔记，可以试用动作卡的写入和撤销。\n",
            revealInWorkspace: false, conflictResolution: .keepBoth(preferredFileName: nil), presentsError: false)
        else { throw CocoaError(.fileWriteUnknown) }
        let source = AgentReplySource(itemID: noteID, courseID: courseID, kind: .note,
            title: "阅读位置实验笔记", label: "实验笔记", excerpt: "合成内容；图片、操作和写入均位于独立实验资料库。")
        for (scenario, title) in scenarioTitles.enumerated() {
            guard let chat = store.createStudySession(courseID: courseID) else { throw CocoaError(.coderInvalidValue) }
            _ = store.renameStudySession(chat.id, title: title)
            store.associateStudySession(chat.id, with: [courseID])
            func message(_ text: String, role: AgentRole = .assistant, actions: [AgentReplyAction] = [], blocks: [AgentMessageContentBlock] = []) -> AgentMessage {
                AgentMessage(role: role, text: text, contentBlocks: blocks, source: nil,
                    sources: role == .assistant ? [source] : [], actions: actions,
                    origin: .init(requestID: UUID(), chatID: chat.id, courseID: courseID))
            }
            switch scenario {
            case 0:
                store.messages = (0..<384).map { index in
                    let text = index % 32 == 31 ? LabSamples.rich
                        : "第 \(index + 1) 条。" + String(repeating: "阅读时可以上下回看同一段文字；前插历史和尾部增长应保住阅读位置。", count: 2 + index % 6)
                    return message(text, role: index.isMultiple(of: 2) ? .user : .assistant)
                }
            case 1:
                store.messages = [message("请完整展示长正文、公式、代码和表格。", role: .user),
                    message(LabSamples.longAnswer + "\n\n" + LabSamples.rich), message(LabSamples.codeAndTable)]
            default:
                let rich = LabSamples.rich + "\n\n" + extensions(image: imageDataURL)
                let action = AgentReplyAction(kind: .writeNote, targetItemID: noteID,
                    proposedMarkdown: "## 阅读观察\n\n先编辑这段草稿，再滚走回来；确认后应写入实验笔记，并能撤销。")
                let visualization = AgentVisualization(id: "lab-controls", specJSON:
                    #"{"items":[{"type":"text","content":"互动内容使用魏碑原有入口"},{"type":"copy","text":"可复制的实验内容"},{"type":"table","headers":["阶段","内容"],"rows":[["首次","完整准备"],["回看","复用结果"]]}]}"#)
                store.messages = [message("试用来源、图片、提示块、图示和笔记动作。", role: .user),
                    message(rich, actions: [action], blocks: [.text(rich), .visualization(visualization)])]
            }
            store.syncActiveStudySession()
        }
        open(scenarioTitles[2], store: store)
        _ = await store.flushPendingWorkspaceSaveAsync()
    }
    static func extensions(image: String) -> String {
        """
        [[阅读位置实验笔记|打开实验笔记]]

        > [!note]- 可折叠提示
        > 折叠状态应在往返回看后保留。

        ![合成的阅读位置示意图](\(image))

        ```mermaid
        flowchart LR
          A[阅读历史] --> B[内容变化]
          B --> C[继续阅读原处]
        ```
        """
    }
    static var imageDataURL: String {
        let image = NSImage(size: NSSize(width: 720, height: 240), flipped: false) { rect in
            NSColor(calibratedRed: 0.92, green: 0.90, blue: 0.84, alpha: 1).setFill(); rect.fill()
            for index in 0..<5 {
                NSColor(calibratedWhite: 0.30 + Double(index) * 0.08, alpha: 1).setFill()
                NSRect(x: 36, y: 28 + index * 40, width: 640 - index * 28, height: 10).fill()
            }
            return true
        }
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        return "data:image/png;base64," + data.base64EncodedString()
    }
    /// Deterministic input enters the existing per-conversation stream and stop
    /// lifecycle. It is explicitly a replay, never a fabricated model response.
    static func replay(store: WorkspaceStore) {
        guard let chatID = store.activeStudySessionID, !store.isAgentRunningInActiveChat else { return }
        let run = AgentConversationRun(chatID: chatID)
        let requestID = UUID(), replyID = UUID()
        run.activeAgentRequestID = requestID
        run.activeAgentReplyMessageID = replyID
        run.activeAgentReplyChatID = chatID
        run.isAskingAgent = true
        store.agentRuns[chatID] = run
        store.appendAgentMessage(.init(role: .user, text: "合成流式重放", source: nil))
        store.appendAgentMessage(.init(id: replyID, role: .assistant, text: "", source: nil,
            completionState: .generating, retryQuestion: "合成流式重放"))
        run.streaming.begin(messageID: replyID, chatID: chatID)
        store.objectWillChange.send()
        run.agentRequestTask = Task { @MainActor in
            await AgentConversationExecution.$run.withValue(run) {
                let characters = Array(LabSamples.rich)
                do {
                    for end in stride(from: 24, to: characters.count, by: 24) {
                        try Task.checkCancellation()
                        store.applyAgentProgress(.text(String(characters.prefix(end)), []),
                            requestID: requestID, replyMessageID: replyID, chatID: chatID)
                        try await Task.sleep(for: .milliseconds(120))
                    }
                    try Task.checkCancellation()
                    run.latestAgentStreamingText = LabSamples.rich
                    _ = store.updateAgentMessage(replyID, in: chatID) {
                        $0.text = LabSamples.rich; $0.completionState = .completed
                    }
                    run.pump.finish(cumulativeText: LabSamples.rich)
                } catch is CancellationError {
                    // The normal stop entry has already persisted all received text.
                } catch { assertionFailure(String(describing: error)) }
                run.isAskingAgent = false
                if !run.isStoppingAgent { run.agentRequestTask = nil }
                store.objectWillChange.send()
                _ = await store.flushPendingWorkspaceSaveAsync()
            }
        }
    }
}
#endif
