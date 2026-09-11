#if WEIBEI_ACCEPTANCE_CHECKS
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

    /// Real Quit while a confirmed action is in flight must save both the note and
    /// its executed state. The gate exists only in the isolated acceptance App.
    static func runQuitSaveCheck(store: WorkspaceStore) async {
        guard !started else { return }; started = true
        let path = store.workspaceDirectory.appendingPathComponent("quit-save.json")
        let marker = "【退出时完成笔记动作】"
        do {
            if CommandLine.arguments.contains("--verify-quit-save") {
                var result = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String: Any]
                let chatID = UUID(uuidString: result["chat_id"] as! String)!
                let payload = try StudySessionMessageFile.decoder().decode(PersistedStudySessionMessages.self,
                    from: Data(contentsOf: StudySessionMessageFile.fileURL(sessionID: chatID, in: store.workspaceDirectory)))
                let action = payload.messages.first { $0.id.uuidString == result["message_id"] as? String }?.actions.first
                let body = try String(contentsOfFile: result["note_path"] as! String, encoding: .utf8)
                guard action?.id.uuidString == result["action_id"] as? String,
                      action?.state == .executed,
                      body.components(separatedBy: marker).count == 2,
                      action?.resultContentDigest == WorkspaceStore.noteContentDigest(Data(body.utf8)) else {
                    throw Failure("Quit left note content and action state inconsistent")
                }
                result["status"] = "passed"
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
                exit(0)
            }
            let courseID = try store.createCourseInLibrary(title: "退出保存检查")
            guard let chat = store.createStudySession(courseID: courseID),
                  let noteID = await store.createCourseNotebookNote(courseID: courseID, title: "退出保存笔记",
                    markdown: "原始正文", revealInWorkspace: false),
                  let noteURL = store.importedItems.first(where: { $0.id == noteID })?.url else {
                throw Failure("Quit check could not create its isolated note")
            }
            let action = AgentReplyAction(kind: .writeNote, targetItemID: noteID, proposedMarkdown: marker)
            let reply = AgentMessage(role: .assistant, text: "已确认的笔记动作", source: nil, actions: [action],
                origin: AgentReplyOrigin(requestID: UUID(), chatID: chat.id, courseID: courseID))
            store.appendAgentMessage(reply)
            guard await store.flushPendingWorkspaceSaveAsync() else { throw Failure("Quit check initial save failed") }
            let result: [String: Any] = [
                "source": Bundle.main.object(forInfoDictionaryKey: "WeiBeiGitCommit") as? String ?? "",
                "source_dirty": Bundle.main.object(forInfoDictionaryKey: "WeiBeiSourceDirty") as? Bool ?? true,
                "pid": ProcessInfo.processInfo.processIdentifier, "chat_id": chat.id.uuidString,
                "message_id": reply.id.uuidString, "action_id": action.id.uuidString,
                "note_path": noteURL.path, "status": "awaiting_quit"
            ]
            store.agentActionSaveCheck = {
                try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
                await withCheckedContinuation { done in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { done.resume() }
                }
            }
            await store.confirmAgentReplyAction(messageID: reply.id, actionID: action.id)
            store.agentActionSaveCheck = nil
            // The external CI process requests normal Quit; do not replace it with exit().
        } catch {
            try? error.localizedDescription.write(to: path, atomically: true, encoding: .utf8)
            exit(1)
        }
    }

    static func run(store: WorkspaceStore, endpoint: String) async {
        guard !started else { return }; started = true
        let root = store.storageURL.deletingLastPathComponent()
        let resultURL = root.appendingPathComponent("business-check.json")
        var result: [String: Any] = [
            "source": Bundle.main.object(forInfoDictionaryKey: "WeiBeiGitCommit") as? String ?? "",
            "source_dirty": Bundle.main.object(forInfoDictionaryKey: "WeiBeiSourceDirty") as? Bool ?? true,
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
                store.continueLastWork()
                store.ensureAllStudySessionMessagesLoaded()
                try await until("reopened note editor") { !store.activeNoteIsLoading && store.noteText.contains(noteMarker) }
                let history = store.studySessions.flatMap(\.messages)
                try check("reopen_original_note_and_session_files",
                    store.noteText.contains(finalMarker) && history.contains { $0.text.contains(finalMarker) && $0.completionState == .completed }
                    && history.contains { $0.role == .assistant && $0.completionState == .interrupted && !$0.text.isEmpty })
                try await until("reopened conversation display") {
                    conversation()?.messages.last?.original?.completionState == .interrupted
                }
                if let window = conversation()?.view.window {
                    let snapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    try snapshot.pngData()?.write(to: LabMetrics.directory.appendingPathComponent("workspace.png"))
                }
                try write("passed")
                if CommandLine.arguments.contains("--exit-after-check") { exit(0) }
                return
            }
            try check("mac_idiom_and_isolated_storage", UIDevice.current.userInterfaceIdiom == .mac
                && root.path.contains(".businesscheck/")
                && WeiBeiAgentDataPaths.nativeAgentDirectory.path.contains(".businesscheck/"))
            try check("original_update_service_through_native_bridge", AppDelegate.updates.status != .failed)
            // This in-process check uses the candidate's own default library.
            // First-launch folder confirmation remains a separate UI check.
            UserDefaults.standard.set(true, forKey: "weibei.libraryPlacementConfirmed")
            let originalStyle = store.appearanceStyle
            store.appearanceStyle = .clearGlass
            try await until("native window material") {
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
            try await until("original composer mounted") {
                AgentProviderReadiness.isConfigured(for: store)
                    && conversation()?.view.window.map { descendants($0).contains { $0 is AgentComposerTextEditor.ComposerTextView } } == true
            }
            let composer = descendants(conversation()!.view.window!).compactMap { $0 as? AgentComposerTextEditor.ComposerTextView }.first!
            composer.text = "读取这份候选资料，解释阅读位置。WB452_ITEM=\(material.id) WB452_IMAGE=\(imageURL.absoluteString)"
            composer.delegate?.textViewDidChange?(composer)
            try await until("local composer draft published") { store.pendingComposerDraft == composer.text }
            let question = composer.text!
            // A fast send can publish the draft and its clearing before SwiftUI draws another frame.
            store.agentDraft = question; store.agentDraft = ""
            try await until("composer receives same-frame clearing") { composer.text.isEmpty }
            composer.text = question
            composer.delegate?.textViewDidChange?(composer)
            try await until("next local draft published") { store.pendingComposerDraft == question }
            var answerControl = URLRequest(url: URL(string: endpoint + "/hold-answer")!)
            answerControl.setValue("Bearer catalyst-test-only", forHTTPHeaderField: "Authorization")
            let (_, held) = try await URLSession.shared.data(for: answerControl)
            guard (held as? HTTPURLResponse)?.statusCode == 204 else { throw Failure("test answer hold failed") }
            _ = composer.delegate?.textView?(composer, shouldChangeTextIn: NSRange(location: composer.text.utf16.count, length: 0), replacementText: "\n")
            let originalMotion = store.motionPreference
            do {
                defer { store.motionPreference = originalMotion }
                for preference in [originalMotion, .reduce, .full] {
                    store.motionPreference = preference
                    let reduced = preference.resolvesReduceMotion(systemReduceMotion: UIAccessibility.isReduceMotionEnabled)
                    try await until("waiting status mounted in \(preference.rawValue) motion") {
                        guard let view = conversation()?.view else { return false }
                        return waitingStatus(in: view) != nil
                            && descendants(view).contains { $0 is AgentThinkingOrbitNSView } == !reduced
                    }
                    try await until("waiting status fits its row", seconds: 1.5) {
                        guard let view = conversation()?.view, let indicator = waitingStatus(in: view) else { return false }
                        let frame = indicator.convert(indicator.bounds, to: indicator.window)
                        guard frame.width > 0, frame.height > 0 else { return false }
                        var clippingBounds: [String] = []
                        defer { result["waiting_status_layout"] = ["status": String(describing: frame), "clipping_bounds": clippingBounds] }
                        var parent = indicator.superview
                        while let view = parent {
                            if view.clipsToBounds {
                                let bounds = view.convert(view.bounds, to: view.window)
                                clippingBounds.append(String(describing: bounds))
                                if frame.minY < bounds.minY - 1 || frame.maxY > bounds.maxY + 1 { return false }
                            }
                            parent = view.superview
                        }
                        return true
                    }
                }
            }
            try check("waiting_status_not_clipped", true)
            answerControl.url = URL(string: endpoint + "/continue-answer")!
            let (_, response) = try await URLSession.shared.data(for: answerControl)
            guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw Failure("test answer release failed") }
            try await until("real HTTP stream began") {
                store.isAgentRunningInActiveChat && store.agentStreaming.displayingChatID == store.activeStudySessionID
                    && store.agentStreaming.text.count > 80
            }
            try await until("UIKit received real message") { conversation()?.messages.last?.original?.role == .assistant && conversation()?.messages.last?.blocks.isEmpty == false }
            let controller = conversation()!
            try check("return_clears_original_composer", composer.text.isEmpty)
            try check("status_disappears_at_first_text", waitingStatus(in: controller.view) == nil)
            let originalFirstBlock = controller.messages.last!.blocks.first!
            try await until("real HTTP stream completed", seconds: 60) { !store.isAgentRunningInActiveChat && store.messages.last?.text.contains(finalMarker) == true }
            try await until("UIKit final tail") { controller.messages.last?.markdown.contains(finalMarker) == true }
            let reply = store.messages.last!
            try check("original_http_agent_tools_and_uikit_stream", reply.completionState == .completed && !reply.sources.isEmpty
                && controller.messages.last!.blocks.first === originalFirstBlock)
            result["first_round_message_count"] = store.messages.count
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
                store.isAgentRunningInActiveChat && store.agentStreaming.displayingMessageID != nil
                    && store.agentStreaming.displayingMessageID != reply.id
                    && store.agentStreaming.displayingChatID == store.activeStudySessionID
                    && store.agentStreaming.text.count > 180
            }
            let received = store.agentStreaming.text
            store.cancelAgentRequest(restoreDraft: false)
            await store.waitForAgentRequestsToStop()
            try await until("stopped message displayed") { !store.isAgentRunningInActiveChat && controller.messages.last?.state == .stopped }
            try check("stop_preserves_received_text", store.messages.last?.completionState == .interrupted
                && store.messages.last?.text.hasPrefix(received) == true && controller.messages.last?.markdown.hasPrefix(received) == true)
            try await verifyDividerResize(controller)
            try check("divider_batches_widths_and_reflows_during_drag", true)
            try await verifyConversationAppearance(controller, workspace: store)
            try check("conversation_appearance_and_scale_after_resize", true)
            result["workspace_history"] = try await measureWorkspaceHistory(store)
            try check("history_and_long_answer_through_original_messages", true)
            guard await store.flushPendingWorkspaceSaveAsync() else { throw Failure("workspace save failed") }
            result["note_path"] = persistedNote.path
            result["resident_memory_bytes"] = LabMetrics.residentMemory()
            try write("awaiting_reopen")
            if CommandLine.arguments.contains("--exit-after-check") { exit(0) }
        } catch {
            result["failure"] = error.localizedDescription
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            result["failure_state"] = [
                "application_state": UIApplication.shared.applicationState.rawValue,
                "scene_states": UIApplication.shared.connectedScenes.map { $0.activationState.rawValue },
                "motion_preference": store.motionPreference.rawValue,
                "system_reduce_motion": UIAccessibility.isReduceMotionEnabled,
                "agent_running": store.isAgentRunningInActiveChat,
                "stream_text_count": store.agentStreaming.text.count,
                "messages": store.messages.map { ["role": $0.role.rawValue, "state": $0.completionState.rawValue, "text_count": String($0.text.count)] },
                "views": windows.flatMap(descendants).map { ["type": String(reflecting: type(of: $0)), "frame": String(describing: $0.frame), "hidden": String($0.isHidden)] }
            ]
            if let controller = conversation() {
                let collection = controller.collection
                result["conversation_state"] = [
                    "messages": controller.messages.map { message in
                        ["id": message.id, "state": message.original?.completionState.rawValue ?? "",
                         "blocks": String(message.blocks.count), "auxiliary_height": String(describing: message.auxiliaryHeight)]
                    },
                    "section_items": (0..<collection.numberOfSections).map { collection.numberOfItems(inSection: $0) },
                    "visible_items": collection.indexPathsForVisibleItems.map { [$0.section, $0.item] },
                    "bounds": String(describing: collection.bounds),
                    "content_size": String(describing: collection.contentSize),
                    "follows_latest": controller.followsLatest
                ]
            }
            if let window = conversation()?.view.window ?? windows.first {
                let snapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                try? snapshot.pngData()?.write(to: root.appendingPathComponent("business-failure.png"))
            }
            try? write("failed")
            store.showImportantOperationError("候选业务检查失败：\(error.localizedDescription)")
            if CommandLine.arguments.contains("--exit-after-check") { exit(1) }
        }
    }

    private static func verifyDividerResize(_ controller: ConversationController) async throws {
        guard let window = controller.view.window,
              let split = descendants(window).compactMap({ $0 as? StableDocumentSplitView }).first,
              split.dividerViews.count == 2, split.dividerViews.allSatisfy({ !$0.isHidden }) else {
            throw Failure("three-pane dividers unavailable")
        }
        for (index, divider) in split.dividerViews.enumerated() {
            let originalWidth = controller.bodyWidth
            let measurements = controller.store.measureCount
            divider.onDragStart?()
            do {
                defer { divider.onDragChange?(0); divider.onDragEnd?() }
                for delta in [CGFloat(6), 12, 18] {
                    divider.onDragChange?(index == 0 ? delta : -delta)
                }
                guard controller.store.measureCount == measurements else {
                    throw Failure("intermediate divider widths synchronously remeasured the conversation")
                }
                // Await a display pass while the pointer remains held: text must
                // reflow now, not wait for onDragEnd to catch up.
                try await until("conversation reflows during divider drag") {
                    abs(controller.bodyWidth - originalWidth) > 1
                        && controller.bodyWidth == controller.workspaceBodyWidth
                }
            }
            try await until("divider restores original width") { abs(controller.bodyWidth - originalWidth) < 1 }
        }
    }

    private static func verifyConversationAppearance(_ controller: ConversationController, workspace: WorkspaceStore) async throws {
        let original = (workspace.interfaceTextScale, workspace.appearancePreference, workspace.appearanceStyle)
        let scale: WeiBeiTypography.TextScale = original.0 == .large ? .standard : .large
        let preference: WeiBeiAppearancePreference = original.1 == .dark ? .light : .dark
        let style: WeiBeiAppearanceStyle = original.2 == .clearGlass ? .paperInk : .clearGlass
        defer {
            workspace.setInterfaceTextScale(original.0)
            workspace.appearancePreference = original.1; workspace.appearanceStyle = original.2
        }
        for (scale, preference, style) in [
            (scale, original.1, original.2), (scale, preference, original.2), (scale, preference, style), original
        ] {
            workspace.setInterfaceTextScale(scale)
            workspace.appearancePreference = preference; workspace.appearanceStyle = style
            try await until("conversation applies changed typography and appearance") {
                controller.store.theme == .weiBei(fontSize: 14 * scale.multiplier, appearance: workspace.appearanceMode)
                    && controller.messages.allSatisfy { $0.preparedTheme == controller.store.themeRevision }
            }
        }
    }

    private static func measureWorkspaceHistory(_ store: WorkspaceStore) async throws -> [String: Any] {
        guard let originalSession = store.activeStudySessionID else { throw Failure("missing original session") }
        let originalLayout = store.layout
        store.setLayout(.immersiveConversation)
        guard store.createStudySession(courseID: nil) != nil else { throw Failure("history session creation") }
        let beforeController = conversation()
        let beforePreparation = beforeController?.store.preparationMS ?? [:]
        let history = (0..<720).map { AgentMessage(role: .assistant, text: LabFixture.history($0), source: nil) }
        let started = CACurrentMediaTime()
        store.messages = history
        try await until("original history first page", seconds: 60) {
            conversation()?.messages.count == 240 && conversation()?.messages.last?.id == history.last?.id.uuidString
        }
        let controller = conversation()!
        var measured: [String: Any] = [
            "first_history_page_ms": (CACurrentMediaTime() - started) * 1000,
            "first_page_messages": 240,
            "body_width_pt": controller.bodyWidth,
            "font_size_pt": controller.store.theme.fonts.body.pointSize,
            "cache_state": "first entry to these fixtures in an App that has completed the business round trip; not cold App launch"
        ]
        measured["first_page_preparation_ms"] = controller.store.preparationMS.reduce(into: [String: Double]()) {
            $0[$1.key] = $1.value - (controller === beforeController ? (beforePreparation[$1.key] ?? 0) : 0)
        }
        await controller.revealMessage(history.first!.id)
        guard controller.messages.count == 720 else { throw Failure("original saved history incomplete") }
        let parses = controller.store.parseCount, measurements = controller.store.measureCount
        controller.scrollToLatest()
        controller.collection.contentOffset.y -= 240
        let originalLanguage = controller.interfaceLanguage
        controller.interfaceLanguage = .english
        defer { controller.interfaceLanguage = originalLanguage }
        guard let jump = descendants(controller.view).compactMap({ $0 as? UIButton }).first(where: { $0.accessibilityIdentifier == "chat-scroll-to-latest" }),
              !jump.isHidden, jump.currentTitle == nil, jump.currentImage != nil,
              jump.bounds.size == CGSize(width: 34, height: 34) else { throw Failure("circular jump-to-latest control") }
        jump.sendActions(for: .touchUpInside)
        guard controller.followsLatest, jump.isHidden else { throw Failure("jump-to-latest action") }
        guard controller.collection.panGestureRecognizer.allowedScrollTypesMask == .all else { throw Failure("trackpad or mouse scrolling disabled") }
        if let window = controller.view.window {
            for x in [CGFloat(24), controller.collection.bounds.midX, controller.collection.bounds.maxX - 24] {
                for y in stride(from: CGFloat(40), to: controller.collection.bounds.height - 80, by: 40) {
                    let point = CGPoint(x: x, y: controller.collection.bounds.minY + y)
                    let hit = window.hitTest(controller.collection.convert(point, to: window), with: nil)
                    guard hit?.isDescendant(of: controller.collection) == true else { throw Failure("conversation margin outside scroll view: \(point)") }
                }
            }
        }
        measured["jump_control_and_scroll_hit_region"] = "passed; hit testing and native masks, not physical trackpad acceptance"
        await withCheckedContinuation { continuation in
            controller.sampleScroll(name: "workspace_history") { continuation.resume() }
        }
        guard controller.store.parseCount == parses, controller.store.measureCount == measurements else {
            throw Failure("unchanged history processed during scrolling")
        }
        measured["scroll_new_parses"] = controller.store.parseCount - parses
        measured["scroll_new_measurements"] = controller.store.measureCount - measurements
        measured["scroll_messages"] = controller.messages.count
        let long = AgentMessage(role: .assistant, text: LabFixture.longAnswer, source: nil)
        let beforeLongPreparation = controller.store.preparationMS
        let longStarted = CACurrentMediaTime()
        store.messages = [long]
        try await until("original long answer complete", seconds: 60) {
            guard let value = conversation()?.messages.last else { return false }
            return value.id == long.id.uuidString && value.displayedRevision == value.revision
                && value.markdown.contains("【长回答结束：全部 140 节】") && value.blocks.count > 140
        }
        measured["first_long_answer_ms"] = (CACurrentMediaTime() - longStarted) * 1000
        measured["long_answer_preparation_ms"] = controller.store.preparationMS.reduce(into: [String: Double]()) {
            $0[$1.key] = $1.value - (beforeLongPreparation[$1.key] ?? 0)
        }
        measured["long_answer_utf16_count"] = long.text.utf16.count
        measured["long_answer_blocks"] = controller.messages.last!.blocks.count
        measured["resident_memory_bytes"] = LabMetrics.residentMemory()
        _ = store.activateStudySession(originalSession, expectedCourseID: nil, expectedScopeNeedsReview: false)
        store.setLayout(originalLayout)
        return measured
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
    private static func waitingStatus(in view: UIView) -> UIView? {
        descendants(view).first {
            $0.accessibilityIdentifier == "agent-thinking-status-layout" && $0.window != nil && !$0.isHidden
        }
    }
}

#endif
