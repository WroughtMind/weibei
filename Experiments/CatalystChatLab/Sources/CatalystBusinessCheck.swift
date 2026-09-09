import UIKit
import WebKit
import WeiBeiCore

/// One isolated product round trip through the production store, HTTP client,
/// editor bridge and write gate. Enabled only in the separately identified check App.
@MainActor
enum CatalystBusinessCheck {
    private static var started = false
    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ description: String) { errorDescription = description }
    }
    private static let finalMarker = "【候选真实业务链路结束】"
    private static let noteMarker = "编辑器输入、保存与重开验证：中文 café 👩🏽‍💻。"

    static func run(store: WorkspaceStore, endpoint: String) async {
        guard !started else { return }; started = true
        let root = store.storageURL.deletingLastPathComponent()
        let resultURL = root.appendingPathComponent("business-check.json")
        var result: [String: Any] = [
            "source": Bundle.main.object(forInfoDictionaryKey: "LabSourceRevision") as? String ?? "",
            "source_dirty": Bundle.main.object(forInfoDictionaryKey: "LabSourceDirty") as? String ?? "",
            "bundle_id": Bundle.main.bundleIdentifier ?? "", "platform": "Mac Catalyst",
            "configuration": "Release", "transport": "original client against isolated local SSE fixture; no live model claim",
            "ui_evidence": "in-process behavior checks, not mouse/IME acceptance", "checks": [String: String]()
        ]
        var checks: [String: String] = [:]
        func write(_ status: String) throws {
            result["checks"] = checks; result["status"] = status
            result["recorded_at"] = ISO8601DateFormatter().string(from: Date())
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: resultURL, options: .atomic)
        }
        func check(_ name: String, _ value: Bool) throws {
            checks[name] = value ? "passed" : "failed"
            try write("running")
            if !value { throw Failure(name) }
        }
        do {
            if let previous = try? Data(contentsOf: resultURL),
               let saved = try JSONSerialization.jsonObject(with: previous) as? [String: Any],
               saved["status"] as? String == "awaiting_reopen" {
                result = saved; checks = saved["checks"] as? [String: String] ?? [:]
                store.resumePreviousStudy()
                store.ensureAllStudySessionMessagesLoaded()
                try await until("reopened note editor") { !store.activeNoteIsLoading && store.noteText.contains(noteMarker) }
                let history = store.studySessions.flatMap(\.messages)
                try check("reopen_original_note_and_session_files",
                    store.noteText.contains(finalMarker) && history.contains { $0.text.contains(finalMarker) && $0.completionState == .completed }
                    && history.contains { $0.role == .assistant && $0.completionState == .interrupted && !$0.text.isEmpty })
                try write("passed")
                if CommandLine.arguments.contains("--exit-after-check") { exit(0) }
                return
            }
            try check("mac_idiom_and_isolated_storage", UIDevice.current.userInterfaceIdiom == .mac
                && root.path.contains(".businesscheck/")
                && WeiBeiAgentDataPaths.nativeAgentDirectory.path.contains(".businesscheck/"))
            // This in-process check uses the candidate's own default library.
            // First-launch folder confirmation remains a separate UI check.
            UserDefaults.standard.set(true, forKey: "weibei.libraryPlacementConfirmed")
            let originalStyle = store.appearanceStyle
            store.appearanceStyle = .clearGlass
            try await until("native window material") {
                result["native_window_diagnostics"] = CatalystDesktopWindow.shared.windowFacts()
                return CatalystDesktopWindow.shared.materialWindowCount() > 0
            }
            try check("signed_native_window_material", CatalystDesktopWindow.shared.materialWindowCount() > 0)
            store.appearanceStyle = originalStyle
            let inputs = root.appendingPathComponent("Inputs", isDirectory: true)
            try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
            let materialURL = inputs.appendingPathComponent("候选验证材料.txt")
            try "# 阅读位置\n\n候选独立合成资料：内容增长时保留同一处文字。材料标记 WB452_SOURCE。\n".write(to: materialURL, atomically: true, encoding: .utf8)
            let noteURL = inputs.appendingPathComponent("候选验证笔记.md")
            try "# 候选验证笔记\n\n这是独立测试资料，不是用户笔记。\n".write(to: noteURL, atomically: true, encoding: .utf8)
            let materials: [StudyItem] = await withCheckedContinuation { done in
                store.importFiles([materialURL]) { done.resume(returning: $0) }
            }
            let notes: [StudyItem] = await withCheckedContinuation { done in
                store.importFiles([noteURL], markdownAsNotes: true) { done.resume(returning: $0) }
            }
            guard let material = materials.first, let note = notes.first,
                  let persistedNote = store.resolvedLibraryURL(for: note) else { throw Failure("original import returned no material/note") }
            store.openCourseNote(note.id)
            store.paneState.showReader = true; store.paneState.showAgent = true; store.paneState.showNotes = true
            store.setLayout(.documentAgentNotes)
            try await until("original editor ready") {
                guard !store.activeNoteIsLoading, store.activeNoteItemID == note.id,
                      let editor = await editor(documentID: store.activeNoteEditorDocumentID) else { return false }
                return (try? await editor.evaluateJavaScript("Boolean(document.querySelector('.ProseMirror'))") as? Bool) == true
            }
            let noteEditor = await editor(documentID: store.activeNoteEditorDocumentID)!
            try check("original_import_reader_and_editor", materials.count == 1 && notes.count == 1
                && noteEditor.bounds.width > 100 && noteEditor.bounds.height > 100)
            store.noteEditorCommand = NoteEditorCommand(kind: .insertMarkdown, markdown: "\n\n" + noteMarker)
            try await until("editor command acknowledged") { store.noteEditorCommand == nil && store.noteText.contains(noteMarker) }
            let captured = await store.freshActiveNoteEditorSnapshot()
            store.flushPendingNotePersistence(flushWorkspace: false)
            try check("original_editor_snapshot_and_note_write_gate", captured && (try String(contentsOf: persistedNote, encoding: .utf8)).contains(noteMarker))

            let pdfURL = inputs.appendingPathComponent("bounded-worker.pdf")
            try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 500)).writePDF(to: pdfURL) { context in
                context.beginPage()
                NSString(string: "WB452 PDF text worker").draw(at: CGPoint(x: 24, y: 24), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
            let extracted = await Task.detached { BoundedPDFTextExtractor.page(from: pdfURL, pageIndex: 0, maximumCharacters: 1000)?.text }.value
            try check("signed_bounded_pdf_worker", extracted?.contains("WB452 PDF text worker") == true)

            let attachmentDirectory = store.currentAttachmentDirectory!
            try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
            let imageURL = attachmentDirectory.appendingPathComponent("candidate-image.png")
            try Data(contentsOf: Bundle.main.url(forResource: "landscape", withExtension: "png")!).write(to: imageURL, options: .atomic)
            store.setAgentProviderID(.custom); store.updateAgentBaseURL(endpoint); store.updateModelName("catalyst-local-check")
            AgentAccountService.shared.startAPIKeyLogin("catalyst-test-only", provider: .custom, baseURL: endpoint)
            store.select(itemID: material.id)
            store.agentDraft = "读取这份候选资料，解释阅读位置。WB452_ITEM=\(material.id) WB452_IMAGE=\(imageURL.absoluteString)"
            store.pendingComposerDraft = store.agentDraft
            store.submitAgentDraft()
            try await until("real HTTP stream began") { store.isAgentRunningInActiveChat && store.messages.last?.role == .assistant && (store.messages.last?.text.count ?? 0) > 80 }
            try await until("UIKit received real message") { conversation()?.messages.last?.original?.role == .assistant && conversation()?.messages.last?.blocks.isEmpty == false }
            let controller = conversation()!
            let originalFirstBlock = controller.messages.last!.blocks.first!
            try await until("real HTTP stream completed", seconds: 60) { !store.isAgentRunningInActiveChat && store.messages.last?.text.contains(finalMarker) == true }
            try await until("UIKit final tail") { controller.messages.last?.markdown.contains(finalMarker) == true }
            let reply = store.messages.last!
            try check("original_http_agent_tools_and_uikit_stream", reply.completionState == .completed && !reply.sources.isEmpty
                && controller.messages.last!.blocks.first === originalFirstBlock)
            result["message_count"] = store.messages.count
            result["parse_count"] = controller.store.parseCount
            try check("original_source_navigation", store.openAgentReplySource(reply.sources[0]) && store.selectedItemID == material.id)
            if let imageBlock = controller.messages.last?.blocks.firstIndex(where: { $0.imageSources.contains(imageURL.absoluteString) }) {
                controller.collection.scrollToItem(at: IndexPath(item: imageBlock + 1, section: controller.messages.count - 1), at: .centeredVertically, animated: false)
                controller.collection.layoutIfNeeded()
            }
            try await until("original local image decoded") { controller.store.images.image(for: imageURL.absoluteString) != nil }
            try check("original_attachment_loader", controller.store.images.image(for: imageURL.absoluteString) != nil)
            try await until("image visible in its actual cell") {
                guard let body = controller.collection.visibleCells.compactMap({ ($0 as? MessageCell)?.body })
                    .first(where: { $0.record?.imageSources.contains(imageURL.absoluteString) == true }) else { return false }
                result["image_view_diagnostics"] = "portable=\(body.record?.preparedText != nil) " + descendants(body).map {
                    "\(type(of: $0)) frame=\($0.frame) hidden=\($0.isHidden)"
                }.joined(separator: " | ")
                return descendants(body).compactMap { $0 as? UIImageView }.contains {
                    $0.image != nil && $0.window != nil && !$0.isHidden && $0.bounds.width > 100 && $0.bounds.height > 50
                }
            }
            try check("image_mounted_in_visible_message", true)
            store.openCourseNote(note.id)
            try await until("original note selection completed") {
                store.activeNoteItemID == note.id && !store.activeNoteIsLoading && store.noteText.contains(noteMarker)
            }
            store.applyLastAgentAnswerToNote()
            try await until("original answer saved into note") { store.noteEditorCommand == nil && store.noteText.contains(finalMarker) }
            _ = await store.freshActiveNoteEditorSnapshot()
            store.flushPendingNotePersistence(flushWorkspace: false)
            try check("original_answer_to_note", (try String(contentsOf: persistedNote, encoding: .utf8)).contains(finalMarker))

            store.agentDraft = "WB452_STOP：持续输出，检查停止时保留已收到正文。"
            store.pendingComposerDraft = store.agentDraft
            store.submitAgentDraft()
            try await until("stoppable stream") {
                store.isAgentRunningInActiveChat && store.messages.last?.id != reply.id
                    && store.messages.last?.role == .assistant && store.messages.last?.completionState == .generating
                    && (store.messages.last?.text.count ?? 0) > 180
            }
            let received = store.messages.last!.text
            store.cancelAgentRequest(restoreDraft: false)
            await store.waitForAgentRequestsToStop()
            try await until("stopped message displayed") { !store.isAgentRunningInActiveChat && controller.messages.last?.state == .stopped }
            try check("stop_preserves_received_text", store.messages.last?.completionState == .interrupted
                && store.messages.last?.text.hasPrefix(received) == true && controller.messages.last?.markdown.hasPrefix(received) == true)
            guard await store.flushPendingWorkspaceSaveAsync() else { throw Failure("workspace save failed") }
            result["note_path"] = persistedNote.path
            result["resident_memory_bytes"] = LabMetrics.residentMemory()
            try write("awaiting_reopen")
            if CommandLine.arguments.contains("--exit-after-check") { exit(0) }
        } catch {
            result["failure"] = error.localizedDescription
            try? write("failed")
            store.showImportantOperationError("候选业务检查失败：\(error.localizedDescription)")
            if CommandLine.arguments.contains("--exit-after-check") { exit(1) }
        }
    }

    private static func until(_ description: String, seconds: Double = 20, _ ready: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .milliseconds(Int64(seconds * 1000))
        while !(await ready()) {
            if ContinuousClock.now >= deadline { throw Failure("timeout: " + description) }
            try await Task.sleep(for: .milliseconds(40))
        }
    }
    private static func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private static func editor(documentID: String) async -> MarkdownWebView? {
        let views = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .flatMap(descendants).compactMap { $0 as? MarkdownWebView }.filter { !$0.isHidden && $0.bounds.width > 100 }
        for view in views {
            guard (try? await view.evaluateJavaScript("window.weiBeiMarkdownEditable") as? Bool) == true,
                  (try? await view.evaluateJavaScript("window.weiBeiDocumentID") as? String) == documentID else { continue }
            return view
        }
        return nil
    }
    private static func conversation() -> ConversationController? {
        func children(_ controller: UIViewController) -> [UIViewController] { [controller] + controller.children.flatMap(children) }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .compactMap(\.rootViewController).flatMap(children).compactMap { $0 as? ConversationController }.first
    }
}
