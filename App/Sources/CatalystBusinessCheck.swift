#if WEIBEI_ACCEPTANCE_CHECKS
import UIKit
import SwiftUI
import WebKit
import WeiBeiCore
import MarkdownView
import Litext

/// One isolated product round trip through the production store, HTTP client,
/// editor bridge and write gate. Enabled only in the separately identified check App.
@MainActor
enum CatalystBusinessCheck {
    private static var started = false
    private static var fileDropDiagnostics: [String: Any] = [:]
    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ description: String) { errorDescription = description }
    }
    private static let finalMarker = "【候选真实业务链路结束】"
    private static let noteMarker = "编辑器输入、保存与重开验证：中文 café 👩🏽‍💻。"
    private static let floatingBodyMarker = "WB514_FLOATING_BODY"
    // Executed against the actual mounted GenUI DOM. Diagnostics contain only
    // the synthetic labels, geometry and effective fonts, never the SVG CSS.
    private static let floatingDiagramCheckScript = #"""
    (() => {
      const root = document.querySelector('#genui-content');
      const svg = root?.querySelector('svg');
      const result = {ok: false, stage: 'diagram_root_missing', labels: []};
      if (!root) return result;
      if (!svg) { result.stage = 'diagram_svg_missing'; return result; }
      const rect = svg.getBoundingClientRect();
      const pack = r => [r.left, r.top, r.width, r.height].map(v => Math.round(v * 100) / 100);
      result.width = rect.width; result.height = rect.height;
      result.svg_rect = pack(rect);
      result.observed_labels = Array.from(svg.querySelectorAll('.nodeLabel'))
        .slice(0, 4).map(label => label.textContent.trim().slice(0, 32));
      if (root.querySelector('[data-genui-error]')) { result.stage = 'diagram_render_error'; return result; }
      const text = svg.textContent || '';
      if (!text.includes('WB514_START') || !text.includes('WB514_END') || root.textContent.includes('graph LR')) {
        result.stage = 'diagram_labels_or_raw_source'; return result;
      }
      if (rect.width <= 0 || rect.height <= 0 || rect.left < -1 || rect.right > innerWidth + 1 || rect.top < -1 || rect.bottom > innerHeight + 1) {
        result.stage = 'diagram_svg_bounds'; return result;
      }
      const fits = (r, b, x, y) => (!x || (r.left >= b.left - 1 && r.right <= b.right + 1))
        && (!y || (r.top >= b.top - 1 && r.bottom <= b.bottom + 1));
      const clips = value => ['hidden', 'clip', 'scroll', 'auto', 'overlay'].includes(value);
      const labels = Array.from(svg.querySelectorAll('.nodeLabel'));
      const inspectLabel = expected => {
        const matches = labels.filter(label => label.textContent.trim() === expected);
        const observed = {text: expected, matches: matches.length, visible: false};
        const fail = stage => { observed.stage = stage; return observed; };
        if (matches.length !== 1) return fail('diagram_label_count');
        const label = matches[0];
        const font = getComputedStyle(label);
        observed.font = {family: font.fontFamily.slice(0, 96), size: font.fontSize, line_height: font.lineHeight};
        const foreign = label.closest('foreignObject');
        if (!foreign) return fail('diagram_label_foreign_object_missing');
        const bounds = foreign.getBoundingClientRect();
        observed.foreign_rect = pack(bounds);
        observed.foreign_size = [foreign.getAttribute('width'), foreign.getAttribute('height')];
        const walker = document.createTreeWalker(label, NodeFilter.SHOW_TEXT);
        const ranges = [];
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          if (!node.textContent.trim()) continue;
          const range = document.createRange();
          range.selectNodeContents(node);
          ranges.push(...Array.from(range.getClientRects()).filter(r => r.width > 0 && r.height > 0));
        }
        observed.text_rects = ranges.map(pack);
        observed.label_width = [label.clientWidth, label.scrollWidth];
        if (!ranges.length) return fail('diagram_label_text_empty');
        if (!ranges.every(r => fits(r, bounds, true, true))) {
          return fail('diagram_label_foreign_object_clip');
        }
        observed.clips = [];
        for (let parent = label; parent && root.contains(parent); parent = parent.parentElement) {
          const style = getComputedStyle(parent);
          const clipX = clips(style.overflowX), clipY = clips(style.overflowY);
          if (!clipX && !clipY) continue;
          const parentBounds = parent.getBoundingClientRect();
          const visible = ranges.every(r => fits(r, parentBounds, clipX, clipY));
          observed.clips.push({tag: parent.localName, rect: pack(parentBounds),
            x: style.overflowX, y: style.overflowY, visible});
          if (!visible) return fail('diagram_label_ancestor_clip');
        }
        observed.visible = true; observed.stage = 'passed';
        return observed;
      };
      result.labels = ['WB514_START', 'WB514_END'].map(inspectLabel);
      const failed = result.labels.find(label => !label.visible);
      if (failed) { result.stage = failed.stage; return result; }
      result.ok = true; result.stage = 'passed';
      return result;
    })()
    """#

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
            let courseID = try await store.createCourseInLibraryAsync(title: "退出保存检查")
            guard let chat = store.createStudySession(courseID: courseID),
                  let noteID = await store.createCourseNotebookNote(courseID: courseID, title: "退出保存笔记",
                    markdown: "原始正文", revealInWorkspace: false),
                  let noteURL = store.importedItems.first(where: { $0.id == noteID })?.url else {
                throw Failure("Quit check could not create its isolated note")
            }
            store.associateStudySession(chat.id, with: [courseID])
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

    /// Drives the real three-pane divider the way a pointer does — a new width on
    /// every frame — over a synthetic long conversation, and records the display
    /// callback intervals. Isolated identity only; never the production workspace.
    static func runDragProfile(store: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            UserDefaults.standard.set(true, forKey: "weibei.libraryPlacementConfirmed")
            // --drag-panes=agent-notes (default) | reader-agent | reader-notes
            let panes = CommandLine.arguments.first { $0.hasPrefix("--drag-panes=") }.map { String($0.dropFirst("--drag-panes=".count)) } ?? "agent-notes"
            store.paneState.showReader = true
            store.paneState.showAgent = panes != "reader-notes"
            store.paneState.showNotes = panes != "reader-agent"
            store.setLayout(.documentAgentNotes)
            // --drag-content=full opens a real material in the reader and a real note in the
            // editor, like a working session; default leaves both panes at their empty state.
            if CommandLine.arguments.contains("--drag-content=full") {
                let inputs = store.storageURL.deletingLastPathComponent().appendingPathComponent("DragInputs", isDirectory: true)
                try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
                let materialURL = inputs.appendingPathComponent("拖动采样材料.txt")
                try (0..<80).map { LabFixture.history($0) }.joined(separator: "\n\n").write(to: materialURL, atomically: true, encoding: .utf8)
                let noteURL = inputs.appendingPathComponent("拖动采样笔记.md")
                try ("# 拖动采样笔记\n\n" + (0..<40).map { LabFixture.history($0) }.joined(separator: "\n\n")).write(to: noteURL, atomically: true, encoding: .utf8)
                let materials: [StudyItem] = await withCheckedContinuation { done in store.importFiles([materialURL]) { done.resume(returning: $0) } }
                let notes: [StudyItem] = await withCheckedContinuation { done in store.importFiles([noteURL], markdownAsNotes: true) { done.resume(returning: $0) } }
                guard let material = materials.first, let note = notes.first else { throw Failure("drag inputs") }
                store.openCourseNote(note.id)
                try await until("note editor ready", seconds: 60) {
                    guard !store.activeNoteIsLoading, store.activeNoteItemID == note.id,
                          let editor = await editor(documentID: store.activeNoteEditorDocumentID) else { return false }
                    return (try? await editor.evaluateJavaScript("Boolean(document.querySelector('.ProseMirror'))") as? Bool) == true
                }
                store.select(itemID: material.id)
                try await Task.sleep(for: .milliseconds(1500))
            }
            guard store.createStudySession(courseID: nil) != nil else { throw Failure("session") }
            let history = (0..<240).map { AgentMessage(role: $0 % 4 == 0 ? .user : .assistant, text: LabFixture.history($0), source: nil) }
            store.messages = history
            try await until("history displayed", seconds: 60) {
                conversation()?.messages.count == 240 && conversation()?.messages.last?.id == history.last?.id.uuidString
            }
            let controller = conversation()!
            if panes == "reader-notes" { try await Task.sleep(for: .milliseconds(400)) }
            if CommandLine.arguments.contains("--pane-open-check") {
                // Two panes at an uneven split, then a third opens: the two already on
                // screen must keep their proportion inside the space left to them.
                guard let window = controller.view.window ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first,
                      let split = descendants(window).compactMap({ $0 as? StableDocumentSplitView }).first else { throw Failure("split") }
                store.paneState.showNotes = false
                try await Task.sleep(for: .milliseconds(700))
                let divider = split.dividerViews[0]
                divider.onDragStart?(); divider.onDragChange?(-160); divider.onDragEnd?()
                try await Task.sleep(for: .milliseconds(700))
                let before = [WorkspacePaneRole.reader, .agent].map { split.roleHosts[$0]!.frame.width }
                store.paneState.showNotes = true
                try await Task.sleep(for: .milliseconds(900))
                let after = [WorkspacePaneRole.reader, .agent, .notes].map { split.roleHosts[$0]!.frame.width }
                let ratioBefore = before[0] / before[1], ratioAfter = after[0] / after[1]
                let result: [String: Any] = ["before": before.map { Double($0) }, "after": after.map { Double($0) },
                    "ratio_before": Double(ratioBefore), "ratio_after": Double(ratioAfter),
                    "passed": abs(ratioBefore - ratioAfter) < 0.05 && abs(ratioBefore - 1) > 0.2]
                try FileManager.default.createDirectory(at: LabMetrics.directory, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: LabMetrics.directory.appendingPathComponent("pane-open.json"), options: .atomic)
                exit(result["passed"] as! Bool ? 0 : 1)
            }
            guard let window = controller.view.window ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first,
                  let split = descendants(window).compactMap({ $0 as? StableDocumentSplitView }).first,
                  split.dividerViews.count == 2 else { throw Failure("dividers") }
            try await Task.sleep(for: .milliseconds(600))
            controller.collection.contentOffset.y = controller.collection.contentSize.height / 3
            controller.collection.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(600))
            let divider = split.dividerViews[panes == "agent-notes" ? 1 : 0]
            let metrics = controller.metrics
            metrics.checks["drag_panes"] = panes
            let seconds = 20.0
            let amplitude = CommandLine.arguments.first { $0.hasPrefix("--drag-amplitude=") }.flatMap { Double($0.dropFirst("--drag-amplitude=".count)) } ?? 140
            let themeRevisionBefore = controller.store.themeRevision
            var widths: [CGFloat] = []
            // Per-pane host layout cost, so a stall can be attributed to a pane.
            var hostTimes: [String: [Double]] = [:]
            for (role, host) in split.roleHosts {
                let key = "\(role.rawValue)"
                host.layoutTiming = { hostTimes[key, default: []].append($0 * 1000) }
            }
            defer { for host in split.roleHosts.values { host.layoutTiming = nil } }
            // --drag-nofooters removes the SwiftUI footers (user bubbles / actions) to
            // measure their share; product behaviour is unchanged otherwise.
            let savedAuxiliary = controller.auxiliaryView
            if CommandLine.arguments.contains("--drag-nofooters") {
                controller.auxiliaryView = nil
                controller.collection.reloadData()
                try await Task.sleep(for: .milliseconds(300))
            }
            defer { controller.auxiliaryView = savedAuxiliary }
            let sampler = DisplayIntervalSampler(name: "product_drag", metrics: metrics)
            sampler.start()
            let turns = RunLoopTurnSampler(metrics: metrics)
            turns.start()
            defer { turns.stop() }
            divider.onDragStart?()
            let started = CACurrentMediaTime()
            var frames = 0
            // --drag-hz=60 (default: one event per display frame, like a pointer) | 125 (stress)
            let hz = CommandLine.arguments.first { $0.hasPrefix("--drag-hz=") }.flatMap { Double($0.dropFirst("--drag-hz=".count)) } ?? 60
            var deadline = ContinuousClock.now
            while CACurrentMediaTime() - started < seconds {
                let t = CACurrentMediaTime() - started
                // Back-and-forth like a hand: 1.2 s period, ±amplitude pt, plus small jitter.
                let delta = -amplitude * sin(t * 2 * .pi / 1.2) + CGFloat(frames % 3)
                divider.onDragChange?(delta)
                widths.append(controller.bodyWidth)
                frames += 1
                deadline += .microseconds(Int64(1_000_000 / hz))
                try await Task.sleep(until: deadline, clock: .continuous)
            }
            metrics.record("product_drag_hz", hz)
            divider.onDragChange?(0)
            divider.onDragEnd?()
            try await Task.sleep(for: .milliseconds(800))
            sampler.stop()
            metrics.record("product_drag_events", Double(frames))
            for (key, values) in hostTimes { for value in values { metrics.record("product_drag_host_\(key)_layout_ms", value) } }
            metrics.checks["drag_content"] = CommandLine.arguments.contains("--drag-content=full") ? "full" : "empty"
            metrics.record("product_drag_amplitude", amplitude)
            metrics.record("product_drag_theme_changes", Double(controller.store.themeRevision - themeRevisionBefore))
            metrics.record("product_drag_body_width_min", Double(widths.min() ?? 0))
            metrics.record("product_drag_body_width_max", Double(widths.max() ?? 0))
            metrics.record("product_drag_messages", Double(controller.messages.count))
            _ = try metrics.write(controller: controller)
            exit(0)
        } catch {
            try? error.localizedDescription.write(to: LabMetrics.directory.appendingPathComponent("drag-profile-failure.txt"), atomically: true, encoding: .utf8)
            exit(1)
        }
    }

    /// Wall time and main-thread CPU time per run-loop turn. A long turn with little
    /// CPU means the main thread was blocked (render-server fences, IPC), which the
    /// display-callback intervals alone cannot tell apart from computation.
    @MainActor private final class RunLoopTurnSampler {
        private var observer: CFRunLoopObserver?
        private var turnStart: (wall: CFTimeInterval, cpu: Double)?
        private let metrics: LabMetrics
        init(metrics: LabMetrics) { self.metrics = metrics }
        private static func cpuSeconds() -> Double {
            var info = thread_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
            let thread = mach_thread_self()
            defer { mach_port_deallocate(mach_task_self_, thread) }
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count) }
            }
            guard result == KERN_SUCCESS else { return 0 }
            return Double(info.user_time.seconds + info.system_time.seconds) + Double(info.user_time.microseconds + info.system_time.microseconds) / 1_000_000
        }
        func start() {
            let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
                guard let self else { return }
                if activity == .afterWaiting {
                    self.turnStart = (CACurrentMediaTime(), Self.cpuSeconds())
                } else if let start = self.turnStart {
                    let wall = (CACurrentMediaTime() - start.wall) * 1000
                    let cpu = (Self.cpuSeconds() - start.cpu) * 1000
                    self.metrics.record("product_drag_turn_wall_ms", wall)
                    if wall > 20 {
                        self.metrics.record("product_drag_long_turn_wall_ms", wall)
                        self.metrics.record("product_drag_long_turn_cpu_ms", cpu)
                    }
                    self.turnStart = nil
                }
            }
            self.observer = observer
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
        func stop() {
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            observer = nil
        }
    }

    @MainActor private final class DisplayIntervalSampler: NSObject {
        private var link: CADisplayLink?
        private var previous: CFTimeInterval?
        private let name: String
        private let metrics: LabMetrics
        init(name: String, metrics: LabMetrics) { self.name = name; self.metrics = metrics }
        func start() {
            let link = CADisplayLink(target: self, selector: #selector(fire))
            link.add(to: .main, forMode: .common); self.link = link
        }
        func stop() { link?.invalidate(); link = nil }
        @objc private func fire() {
            let now = CACurrentMediaTime()
            if let previous { metrics.record("\(name)_display_callback_interval_ms", (now - previous) * 1000) }
            previous = now
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
                let renderedMarker = String(decoding: try JSONEncoder().encode(finalMarker), as: UTF8.self)
                try await until("reopened note editor content") {
                    guard let webView = await editor(documentID: store.activeNoteEditorDocumentID) else { return false }
                    return (try? await webView.evaluateJavaScript("document.querySelector('.ProseMirror')?.textContent?.includes(\(renderedMarker)) === true") as? Bool) == true
                }
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
            // Verify that all three control groups live in native toolbar items,
            // rather than being drawn underneath the window's titlebar hit region.
            try await until("native workspace toolbar controls") {
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.contains { scene in
                    let items = scene.titlebar?.toolbar?.items.compactMap { $0 as? NSUIViewToolbarItem } ?? []
                    return items.count == 3 && items.allSatisfy {
                        $0.isEnabled && $0.uiView.isUserInteractionEnabled
                            && $0.uiView.window != nil && !$0.uiView.bounds.isEmpty
                            && !$0.label.isEmpty
                            && (($0.itemMenuFormRepresentation as? UIMenu)?.children.contains { $0 is UIAction } == true)
                    }
                }
            }
            try check("native_workspace_toolbar_controls", true)
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
            var confirmedItems: [StudyItem] = []
            let importSheet = {
                // Catalyst can host the sheet outside connectedScenes.windows.
                CatalystIndependentSheetSizingProbe.Probe.checkInstances.allObjects
                    .first { $0.window?.isHidden == false && !$0.isHidden && $0.contentSize != nil }
            }
            for (url, asNotes) in [(materialURL, false), (noteURL, true)] {
                let previousIDs = Set(store.importedItems.map(\.id))
                let provider = NSItemProvider(item: url.absoluteString as NSString,
                    typeIdentifier: "public.file-url")
                if !asNotes {
                    // Model the real Catalyst payload: content/Finder-node types
                    // on the provider, with the file address on the native board.
                    // This verifies the production UIKit entry; physical cross-app
                    // mouse acceptance is recorded separately.
                    var receiver: WorkspaceFileDropBridge.Probe?
                    try await until("workspace UIKit file-drop registration") {
                        receiver = workspaceFileDropReceiver()
                        return receiver?.registeredInteraction != nil
                    }
                    guard let receiver, let interaction = receiver.registeredInteraction,
                          let target = interaction.view, let window = target.window else {
                        throw Failure("workspace file-drop receiver disappeared")
                    }
                    let contentProvider = NSItemProvider(object: "external text" as NSString)
                    contentProvider.registerDataRepresentation(forTypeIdentifier: "com.apple.finder.node",
                        visibility: .all) { completion in completion(Data(), nil); return nil }
                    let session = FileDropCheckSession(provider: contentProvider, target: target)
                    defer { CatalystDesktopWindow.shared.finishFileDropCheck() }
                    _ = CatalystDesktopWindow.shared.prepareFileDropCheck(id: receiver.registrationID, urls: [])
                    let rejectsText = !receiver.dropInteraction(interaction, canHandle: session)
                    var checks = CatalystDesktopWindow.shared.prepareFileDropCheck(id: receiver.registrationID, urls: [url])
                    checks["content_provider_without_file_url"] = !contentProvider.hasItemConformingToTypeIdentifier("public.file-url")
                    checks["plain_text_rejected"] = rejectsText
                    checks["mounted_root_receiver"] = target === window.rootViewController?.view
                        && target.bounds.width >= window.bounds.width * 0.9
                        && target.bounds.height >= window.bounds.height * 0.9
                    checks["file_accepted_at_uikit_entry"] = receiver.dropInteraction(interaction, canHandle: session)
                    receiver.dropInteraction(interaction, sessionDidEnter: session)
                    checks["drag_guidance_shown"] = receiver.isTargeted?.wrappedValue == true
                    checks["copy_proposed"] = receiver.dropInteraction(interaction, sessionDidUpdate: session).operation == .copy
                    receiver.dropInteraction(interaction, performDrop: session)
                    receiver.dropInteraction(interaction, sessionDidEnd: session)
                    checks["drag_guidance_cleared"] = receiver.isTargeted?.wrappedValue == false
                    fileDropDiagnostics = checks
                    result["file_drop_state"] = checks
                    try check("workspace_file_drop_receiver", checks.count == 11 && checks.values.allSatisfy { $0 })
                } else {
                    guard store.receiveDroppedFiles([provider], asNotes: true) else {
                        throw Failure("note file-drop provider was rejected")
                    }
                }
                try await until("confirmed import review") {
                    store.confirmedFileImport?.stage == .reviewing
                }
                try await until("confirmed import fitted native sheet") {
                    guard let sheet = importSheet(), let size = sheet.contentSize,
                          let window = sheet.window, !window.isHidden,
                          let sceneSize = window.windowScene?.effectiveGeometry.systemFrame.size else { return false }
                    return abs(window.bounds.width - size.width) < 1
                        && abs(window.bounds.height - size.height) < 1
                        && abs(sceneSize.width - size.width) < 1
                        && abs(sceneSize.height - size.height) < 1
                        && size.width > 100 && size.height > 100
                }
                if !asNotes, let window = importSheet()?.window {
                    let snapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    try snapshot.pngData()?.write(to: LabMetrics.directory.appendingPathComponent("confirmed-import.png"))
                }
                store.confirmFileImport()
                try await until("confirmed import completes and dismisses") {
                    store.confirmedFileImport == nil && importSheet() == nil
                }
                let added = store.importedItems.filter { !previousIDs.contains($0.id) }
                guard added.count == 1, let imported = added.first,
                      let copiedURL = store.resolvedLibraryURL(for: imported),
                      try Data(contentsOf: copiedURL) == Data(contentsOf: url) else {
                    throw Failure("confirmed import did not preserve the material/note")
                }
                confirmedItems.append(imported)
            }
            let materials = Array(confirmedItems.prefix(1))
            let notes = Array(confirmedItems.suffix(1))
            try check("confirmed_import_review_copy_and_dismiss", confirmedItems.count == 2)
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
            try await until("note viewport extends under the native toolbar") {
                guard let window = noteEditor.window else { return false }
                return abs(noteEditor.convert(noteEditor.bounds, to: window).minY) < 1
                    && noteEditor.scrollView.contentInsetAdjustmentBehavior == .never
            }
            try await until("conversation viewport extends under the native toolbar") {
                guard let chat = conversation(), let window = chat.collection.window else { return false }
                return chat.collection.contentInsetAdjustmentBehavior == .never
                    && abs(chat.collection.adjustedContentInset.top - chat.collection.contentInset.top) < 1
                    && abs(chat.collection.convert(chat.collection.bounds, to: window).minY) < 1
                    && conversationReachesToolbar(chat)
                    && abs(chat.flow.topInset - chat.view.safeAreaInsets.top) < 1
                    && chat.collection.contentInset.top == 0
            }
            if #available(iOS 26.0, *) {
                try await until("pane edges do not add separate toolbar materials") {
                    guard let window = noteEditor.window, let chat = conversation(),
                          let reader = descendants(window).first(where: { $0.accessibilityIdentifier == "persistent-pane-reader" }),
                          let text = descendants(reader).compactMap({ $0 as? UITextView }).first else { return false }
                    // The shared pane mask owns the effect for all three viewports.
                    let scrolls: [UIScrollView] = [text, chat.collection, noteEditor.scrollView]
                    return scrolls.allSatisfy { $0.topEdgeEffect.isHidden }
                }
            }
            try await until("all three panes fade within the original toolbar") {
                guard let window = noteEditor.window else { return false }
                let panes = descendants(window).compactMap { $0 as? PersistentPaneHost.Container }
                    .filter { !$0.isHidden && $0.bounds.width > 0 }
                return panes.count == 3 && panes.allSatisfy { pane in
                    guard let fade = pane.layer.mask as? CAGradientLayer,
                          let end = fade.locations?.dropLast().last else { return false }
                    let fadeBottom = pane.convert(CGPoint(x: 0, y: CGFloat(end.doubleValue) * pane.bounds.height), to: window).y
                    return fade.frame == pane.bounds && abs(fadeBottom - window.safeAreaInsets.top) < 1
                }
            }
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
            let activeConnection = store.activeAgentProfileID
            try check("active_connection_profile_matches_configuration", store.agentCredentialProfiles.contains {
                $0.id == activeConnection && $0.provider == .custom && $0.authMethod == .apiKey
                    && $0.baseURL == endpoint && $0.modelName == "catalyst-local-check"
            })
            _ = try store.createAgentConnection(provider: .openaiCodex, authMethod: .subscription, baseURL: "")
            store.selectAgentCredentialProfile(activeConnection)
            try check("connection_profile_switch_back", store.activeAgentProfileID == activeConnection
                && store.agentProviderID == .custom && store.agentAuthMethod == .apiKey
                && store.agentBaseURL == endpoint && store.modelName == "catalyst-local-check")
            NotificationCenter.default.post(name: .weibeiOpenSettings, object: nil)
            let settingsScene = {
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .first { ($0.session.userInfo?["weibei-settings"] as? Bool) == true }
            }
            try await until("connection cards in the real settings window") {
                guard let window = settingsScene()?.windows.first(where: { !$0.isHidden }) else { return false }
                return window.bounds.width >= 700 && window.bounds.height >= 600
                    && !AgentAccountService.shared.isRefreshingModels
                    && AgentAccountService.shared.hasLoadedModels(provider: .custom)
                    && AgentAccountService.shared.liveModelIDs.contains("catalyst-local-check")
            }
            guard let scene = settingsScene(), let window = scene.windows.first(where: { !$0.isHidden }) else {
                throw Failure("connection settings window disappeared")
            }
            let settingsSnapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try settingsSnapshot.pngData()?.write(to: LabMetrics.directory.appendingPathComponent("connection-cards.png"))
            try check("connection_cards_settings_and_authenticated_models", true)
            UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil, errorHandler: nil)
            try await until("settings window closes") { settingsScene() == nil }
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

            result["floating_rich_answer"] = try await verifySelectionChat(store, material: material, mainComposer: composer, mainConversation: controller)
            try check("selection_chat_composers_and_citation", true)
            try check("floating_11pt_math_diagram_and_layout", true)

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
            try await verifyDividerLanguage(controller, workspace: store)
            try check("divider_interface_language_updates", true)
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
            result["connection_state"] = [
                "provider": store.agentProviderID.rawValue,
                "auth_method": store.agentAuthMethod.rawValue,
                "model_list_failure": String(describing: AgentAccountService.shared.modelListFailure),
                "live_models": AgentAccountService.shared.liveModelIDs.joined(separator: ","),
                "is_refreshing": String(AgentAccountService.shared.isRefreshingModels)
            ]
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            let sheetProbes = CatalystIndependentSheetSizingProbe.Probe.checkInstances.allObjects
            let sheetProbeStates: [[String: String]] = sheetProbes.map { probe in
                let window = probe.window
                let scene = window?.windowScene
                let root = window?.rootViewController
                let rootView = root?.viewIfLoaded
                let presentation = root?.presentationController
                var state: [String: String] = [:]
                state["frame"] = String(describing: probe.frame)
                state["hidden"] = String(probe.isHidden)
                state["content_size"] = String(describing: probe.contentSize)
                state["window_bounds"] = String(describing: window?.bounds)
                state["window_hidden"] = String(describing: window?.isHidden)
                state["root_controller"] = root.map { String(reflecting: type(of: $0)) } ?? "nil"
                state["root_preferred_size"] = String(describing: root?.preferredContentSize)
                state["root_contains_probe"] = String(rootView.map { probe.isDescendant(of: $0) } ?? false)
                state["root_view_window_matches"] = String(window != nil && rootView?.window === window)
                state["presented_root_matches"] = String(root != nil && presentation?.presentedViewController === root)
                state["root_has_presented_child"] = String(root?.presentedViewController != nil)
                state["presentation_controller"] = presentation.map { String(reflecting: type(of: $0)) } ?? "nil"
                state["rooted_window_count"] = String(scene?.windows.filter { $0.rootViewController != nil }.count ?? 0)
                state["scene_minimum_size"] = String(describing: scene?.sizeRestrictions?.minimumSize)
                state["scene_maximum_size"] = String(describing: scene?.sizeRestrictions?.maximumSize)
                state["geometry_request"] = probe.checkGeometryRequest ?? ""
                state["geometry_error"] = probe.checkGeometryError ?? ""
                state["scene_frame"] = String(describing: scene?.effectiveGeometry.systemFrame)
                state["scene_connected"] = String(scene.map { UIApplication.shared.connectedScenes.contains($0) } ?? false)
                return state
            }
            result["file_drop_state"] = fileDropDiagnostics
            result["confirmed_import_state"] = [
                "stage": store.confirmedFileImport.map { String(describing: $0.stage) } ?? "dismissed",
                "destination_error": store.confirmedFileImport?.destinationError ?? "",
                "candidate_count": store.confirmedFileImport?.candidates.count ?? 0,
                "sheet_probes": sheetProbeStates
            ]
            result["failure_state"] = [
                "application_state": UIApplication.shared.applicationState.rawValue,
                "scene_states": UIApplication.shared.connectedScenes.map { $0.activationState.rawValue },
                "motion_preference": store.motionPreference.rawValue,
                "system_reduce_motion": UIAccessibility.isReduceMotionEnabled,
                "agent_running": store.isAgentRunningInActiveChat,
                "stream_text_count": store.agentStreaming.text.count,
                "messages": store.messages.map { ["role": $0.role.rawValue, "state": $0.completionState.rawValue, "text_count": String($0.text.count)] },
                "views": windows.flatMap(descendants).map { view in
                    var state = ["type": String(reflecting: type(of: view)), "frame": String(describing: view.frame), "hidden": String(view.isHidden)]
                    if #available(iOS 26.0, *), let scroll = view as? UIScrollView {
                        state["top_edge_hidden"] = String(scroll.topEdgeEffect.isHidden)
                    }
                    return state
                }
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
            if let window = sheetProbes.first(where: { $0.window?.isHidden == false })?.window
                ?? conversation()?.view.window ?? windows.first {
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

    private static func verifySelectionChat(_ store: WorkspaceStore, material: StudyItem,
                                            mainComposer: AgentComposerTextEditor.ComposerTextView,
                                            mainConversation: ConversationController) async throws -> [String: Any] {
        guard let mainID = store.activeStudySessionID, let window = mainComposer.window else { throw Failure("main composer unavailable") }
        let mainHistory = store.messages
        let mainDraft = "主会话草稿：稍后比较这段解释。"
        mainComposer.text = mainDraft
        mainComposer.delegate?.textViewDidChange?(mainComposer)
        store.select(itemID: material.id)
        func reader() -> UITextView? {
            descendants(window).compactMap { $0 as? UITextView }.first { $0.delegate is SelectablePlainTextReader.Coordinator }
        }
        func floatingComposer() -> AgentComposerTextEditor.ComposerTextView? {
            descendants(window).compactMap { $0 as? AgentComposerTextEditor.ComposerTextView }.first { $0 !== mainComposer }
        }
        func capture(_ name: String, label: String? = nil) throws {
            guard let content = window.rootViewController?.view,
                  let split = descendants(content).compactMap({ $0 as? StableDocumentSplitView }).first,
                  content.bounds.contains(split.convert(split.bounds, to: content)),
                  content.bounds.contains(mainComposer.convert(mainComposer.bounds, to: content)) else {
                throw Failure("workspace or main composer outside visible content")
            }
            // Capture workspace content; the native toolbar is outside this view.
            let labelHeight: CGFloat = label == nil ? 0 : 32
            let snapshot = UIGraphicsImageRenderer(size: CGSize(width: content.bounds.width, height: content.bounds.height + labelHeight)).image { context in
                if let label {
                    UIColor.white.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: content.bounds.width, height: labelHeight))
                    NSString(string: label).draw(at: CGPoint(x: 10, y: 8), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.black])
                    context.cgContext.translateBy(x: -content.bounds.minX, y: labelHeight - content.bounds.minY)
                }
                content.drawHierarchy(in: content.bounds, afterScreenUpdates: true)
            }
            try snapshot.pngData()?.write(to: LabMetrics.directory.appendingPathComponent(name))
        }
        try await until("selection reader and main draft ready") { reader() != nil && store.composerDraft(for: mainID) == mainDraft }
        let textView = reader()!
        let passage = "候选独立合成资料：内容增长时保留同一处文字。"
        let range = (textView.text as NSString).range(of: passage)
        guard range.location != NSNotFound else { throw Failure("selection passage unavailable") }
        textView.selectedRange = range
        textView.delegate?.textViewDidChangeSelection?(textView)
        try await until("selection attached before asking") {
            store.selectionAttachments.first?.text == passage && store.selectionAnchor != nil
        }
        guard store.activeSelectionAskThreadID == nil else { throw Failure("selection sent a question without asking") }
        let attachments = store.selectionAttachments
        store.askSelection()
        try await until("floating composer receives focus") { floatingComposer()?.isFirstResponder == true }
        guard let threadID = store.activeSelectionAskThreadID, let composer = floatingComposer(),
              threadID != mainID, mainComposer.text == mainDraft, store.selectionAttachments == attachments else {
            throw Failure("Ask changed the main composer or selection")
        }
        try capture("selection-composers.png")
        let originalTextScale = store.interfaceTextScale
        store.setInterfaceTextScale(.standard)
        defer { store.setInterfaceTextScale(originalTextScale) }
        composer.text = "解释刚才选中的原文。WB452_ITEM=\(material.id) WB514_FLOATING_RICH"
        composer.delegate?.textViewDidChange?(composer)
        try await until("floating draft saved") { store.composerDraft(for: threadID) == composer.text }
        _ = composer.delegate?.textView?(composer, shouldChangeTextIn: NSRange(location: composer.text.utf16.count, length: 0), replacementText: "\n")
        try await until("floating answer displayed", seconds: 60) {
            !store.isAgentRunning(in: threadID)
                && store.conversationMessages(in: threadID).last?.text.contains(finalMarker) == true
                && composer.text.isEmpty
        }
        guard store.messages == mainHistory, mainConversation.messages.last?.id == mainHistory.last?.id.uuidString,
              mainComposer.text == mainDraft, store.selectionAttachments == attachments else {
            throw Failure("floating send changed the main conversation")
        }
        guard let richReply = store.conversationMessages(in: threadID).last, richReply.role == .assistant else {
            throw Failure("floating rich answer unavailable")
        }
        let richEvidence = try await verifyFloatingRichAnswer(messageID: richReply.id, in: window)
        try capture("selection-rich-answer-11pt.png", label: "Floating selection answer · 11 pt · native inline/display math + rendered diagram")
        let draft = "浮窗草稿：这一句再展开说明。"
        composer.text = draft
        composer.delegate?.textViewDidChange?(composer)
        try await until("floating follow-up saved") { store.composerDraft(for: threadID) == draft }
        let target = WorkspaceStore.AgentConversationTarget(sessionID: mainID, workingDirectory: store.workspaceDirectory, courseID: nil)
        let discussion = try store.executeDiscussionTool(.discussionRead(chatID: threadID), target: target, focusItemIDs: [material.id])
        guard let source = discussion.discussions?.first?.messages?.first?.source, let messageID = source.messageID else {
            throw Failure("discussion citation unavailable")
        }
        store.dismissFloatingSelectionAgent()
        try await until("floating composer closed") { floatingComposer() == nil }
        guard store.openAgentReplySource(source) else { throw Failure("discussion citation did not open") }
        try await until("citation revealed and floating draft restored") {
            guard store.selectionChatRevealMessageID == nil, floatingComposer()?.text == draft,
                  let message = floatingMessage(messageID, in: window) else { return false }
            return isVisible(message, in: window)
        }
        guard store.activeStudySessionID == mainID, mainComposer.text == mainDraft else { throw Failure("citation replaced the main conversation") }
        try capture("selection-discussion.png")
        mainConversation.quoteText?("主会话引用片段")
        // A2: 引用追加到各自草稿末尾（前面空一行），不再替换已写的草稿。
        let mainQuoted = mainDraft + "\n\n> 主会话引用片段\n\n"
        try await until("main quote appends to its own composer") {
            mainComposer.isFirstResponder && mainComposer.text == mainQuoted && floatingComposer()?.text == draft
        }
        guard let floatingMessage = floatingMessage(messageID, in: window),
              let quotedMessage = store.conversationMessages(in: threadID).first(where: { $0.id == messageID }) else {
            throw Failure("floating message quote action unavailable")
        }
        let floatingQuoted = draft + "\n\n> " + quotedMessage.text.replacingOccurrences(of: "\n", with: "\n> ") + "\n\n"
        floatingMessage.onQuote()
        try await until("floating quote appends to its own composer") {
            floatingComposer()?.isFirstResponder == true && floatingComposer()?.text == floatingQuoted
                && mainComposer.text == mainQuoted
        }
        store.dismissFloatingSelectionAgent()
        store.clearSelectionAttachments()
        // Exercise the real composer with a documented model, using only the isolated fixture endpoint.
        let provider = store.agentProviderID
        let model = store.modelName
        defer { store.setAgentProviderID(provider); store.updateModelName(model) }
        store.setAgentProviderID(.azureOpenAI)
        store.updateModelName("gpt-5.4")
        AgentAccountService.shared.startAPIKeyLogin("catalyst-test-only", provider: .azureOpenAI, baseURL: store.agentBaseURL)
        try await until("reasoning composer configured") {
            AgentProviderReadiness.isConfigured(for: store) && store.agentReasoningEffort == "low"
        }
        store.agentReasoningMode = .think
        guard store.agentReasoningEffort == "high" else { throw Failure("Think default is not high") }
        store.agentReasoningMappings[store.agentReasoningMappingKey(.think)] = "medium"
        guard store.agentReasoningEffort == "medium" else { throw Failure("Think mapping did not apply") }
        store.agentReasoningMappings.removeValue(forKey: store.agentReasoningMappingKey(.think))
        store.agentReasoningMode = .flash
        guard store.agentReasoningEffort == "low" else { throw Failure("Flash default is not low") }
        mainComposer.text = "第一行\n第二行\n第三行"
        mainComposer.delegate?.textViewDidChange?(mainComposer)
        try await until("reasoning composer grows for multiple lines") {
            mainComposer.bounds.height >= (mainComposer.font?.lineHeight ?? 20) * 3 - 2
        }
        mainComposer.text = "解释这段内容。"
        mainComposer.delegate?.textViewDidChange?(mainComposer)
        try await until("reasoning composer shrinks to one line") {
            window.layoutIfNeeded()
            guard let content = window.rootViewController?.view else { return false }
            return mainComposer.bounds.height <= (mainComposer.font?.lineHeight ?? 20) + 2
                && content.bounds.maxY - mainComposer.convert(mainComposer.bounds, to: content).maxY <= 40
        }
        try capture("reasoning-composer.png")
        return richEvidence
    }

    private static func verifyFloatingRichAnswer(messageID: UUID, in window: UIWindow) async throws -> [String: Any] {
        var evidence: [String: Any] = [:]
        var diagnostic: [String: Any] = [:]
        do {
            try await until("floating 11pt text, formula attachments and diagram fit their real views", seconds: 30) {
                window.layoutIfNeeded()
                diagnostic = ["stage": "floating_row_missing"]
                guard let row = floatingMessage(messageID, in: window) else { return false }
                diagnostic["row_frame"] = String(describing: row.convert(row.bounds, to: window))
                diagnostic["stage"] = "floating_row_visibility"
                guard isVisible(row, in: window) else { return false }
                diagnostic["stage"] = "floating_body_missing"
                guard let body = descendants(window).compactMap({ $0 as? MarkdownTextView }).first(where: {
                    $0.window === window && $0.textLabelView.attributedText.string.contains(floatingBodyMarker)
                }) else { return false }
                body.layoutIfNeeded()
                let text = body.textLabelView.attributedText
                let mathImages = body.content.rendered.values.compactMap(\.image)
                let markerRange = (text.string as NSString).range(of: floatingBodyMarker)
                let font = markerRange.location == NSNotFound ? nil
                    : text.attribute(.font, at: markerRange.location, effectiveRange: nil) as? UIFont
                diagnostic["body_frame"] = String(describing: body.convert(body.bounds, to: window))
                diagnostic["font_size_pt"] = font?.pointSize ?? 0
                diagnostic["line_height_pt"] = font?.lineHeight ?? 0
                diagnostic["math_images"] = mathImages.count
                diagnostic["math_images_valid"] = mathImages.allSatisfy { $0.cgImage != nil && $0.size.width > 0 && $0.size.height > 0 }
                diagnostic["stage"] = "floating_body_font"
                guard markerRange.location != NSNotFound,
                      let font, abs(font.pointSize - 11) < 0.01 else { return false }
                diagnostic["stage"] = "floating_math_images"
                guard mathImages.count == 2,
                      mathImages.allSatisfy({ $0.cgImage != nil && $0.size.width > 0 && $0.size.height > 0 }) else { return false }
                diagnostic["stage"] = "floating_raw_math"
                guard !text.string.contains("\\frac"), !text.string.contains("$") else { return false }
                diagnostic["stage"] = "floating_body_visibility"
                guard fullyVisible(body, in: window) else { return false }
                var mathAttachments = 0
                text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
                    if attributes[.litextAttachment] is TextLabel.Attachment,
                       attributes[.litextLineDrawingAction] != nil { mathAttachments += 1 }
                }
                let measured = body.boundingSize(for: body.bounds.width)
                let rowFrame = row.convert(row.bounds, to: window)
                let bodyFrame = body.convert(body.bounds, to: window)
                diagnostic["native_math_attachments"] = mathAttachments
                diagnostic["measured_body_size"] = String(describing: measured)
                diagnostic["stage"] = "floating_math_attachments"
                guard mathAttachments >= 2 else { return false }
                diagnostic["stage"] = "floating_native_layout"
                guard body.bounds.width > 1,
                      measured.height > 1, body.bounds.height + 1 >= measured.height,
                      rowFrame.insetBy(dx: -1, dy: -1).contains(bodyFrame) else { return false }
                diagnostic["stage"] = "floating_diagram_view_missing"
                for webView in descendants(window).compactMap({ $0 as? WKWebView }) {
                    let webFrame = webView.convert(webView.bounds, to: window)
                    guard rowFrame.insetBy(dx: -1, dy: -1).contains(webFrame) else { continue }
                    diagnostic["web_frame"] = String(describing: webFrame)
                    guard fullyVisible(webView, in: window) else {
                        diagnostic["stage"] = "floating_diagram_view_visibility"
                        continue
                    }
                    let diagram: [String: Any]
                    do {
                        guard let value = try await webView.evaluateJavaScript(floatingDiagramCheckScript) as? [String: Any] else {
                            diagnostic["stage"] = "floating_diagram_bridge_result"
                            continue
                        }
                        if value["stage"] as? String == "diagram_root_missing" { continue }
                        diagram = value
                    } catch {
                        diagnostic["stage"] = "floating_diagram_javascript"
                        diagnostic["javascript_error"] = String(error.localizedDescription.prefix(200))
                        continue
                    }
                    diagnostic["diagram"] = diagram
                    diagnostic["stage"] = diagram["stage"] as? String ?? "floating_diagram_result"
                    guard diagram["ok"] as? Bool == true else { continue }
                    evidence = ["body_font_size_pt": font.pointSize, "body_frame": String(describing: bodyFrame),
                                "measured_body_size": String(describing: measured), "math_images": mathImages.count,
                                "native_math_attachments": mathAttachments, "diagram": diagram,
                                "screenshot": "selection-rich-answer-11pt.png"]
                    return true
                }
                return false
            }
        } catch {
            diagnostic["source"] = Bundle.main.object(forInfoDictionaryKey: "WeiBeiGitCommit") as? String ?? ""
            diagnostic["source_dirty"] = Bundle.main.object(forInfoDictionaryKey: "WeiBeiSourceDirty") as? Bool ?? true
            diagnostic["status"] = "failed"
            let path = LabMetrics.directory.appendingPathComponent("floating-rich-diagnostic.json")
            do {
                try FileManager.default.createDirectory(at: LabMetrics.directory, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]).write(to: path, options: .atomic)
            } catch {
                print("floating rich diagnostic could not be saved: \(error.localizedDescription)")
            }
            throw Failure(error.localizedDescription + " (stage: " + (diagnostic["stage"] as? String ?? "unrecorded") + ")")
        }
        return evidence
    }

    private static func fullyVisible(_ view: UIView, in window: UIWindow) -> Bool {
        guard isVisible(view, in: window) else { return false }
        let frame = view.convert(view.bounds, to: window)
        guard window.bounds.insetBy(dx: -1, dy: -1).contains(frame) else { return false }
        var ancestor = view.superview
        while let current = ancestor {
            if current.clipsToBounds && !current.convert(current.bounds, to: window).insetBy(dx: -1, dy: -1).contains(frame) { return false }
            ancestor = current.superview
        }
        return true
    }

    private static func verifyDividerLanguage(_ controller: ConversationController, workspace: WorkspaceStore) async throws {
        guard let window = controller.view.window,
              let split = descendants(window).compactMap({ $0 as? StableDocumentSplitView }).first,
              split.dividerViews.count == 2, split.dividerViews.allSatisfy({ !$0.isHidden }) else {
            throw Failure("three-pane dividers unavailable")
        }
        let originalLanguage = workspace.interfaceLanguage
        defer { workspace.setInterfaceLanguage(originalLanguage) }
        for language in [WeiBeiInterfaceLanguage.english, .chinese] {
            workspace.setInterfaceLanguage(language)
            try await until("divider applies changed interface language") {
                let expected = (
                    language.text("调整分栏宽度", "Resize panes"),
                    language.text("双击均分相邻两栏；按住 Option 松手可跳过吸附。", "Double-click to split the adjacent panes evenly. Hold Option while releasing to skip snapping."),
                    language.text("均分相邻两栏", "Split adjacent panes evenly")
                )
                return split.dividerViews.allSatisfy {
                    $0.interfaceLanguage == language
                        && $0.accessibilityLabel == expected.0
                        && $0.accessibilityHint == expected.1
                        && $0.accessibilityCustomActions?.first?.name == expected.2
                }
                    && controller.collection.accessibilityLabel
                        == language.text("会话消息列表", "Conversation messages")
            }
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
        // The immersive host is a separate SwiftUI branch from the three-pane
        // split; it must extend under the toolbar and carry the fade mask too.
        try await until("immersive conversation pane fades within the original toolbar") {
            guard let window = controller.collection.window,
                  let pane = descendants(window).compactMap({ $0 as? PersistentPaneHost.Container })
                      .first(where: { !$0.isHidden && $0.bounds.width > 0 }),
                  let fade = pane.layer.mask as? CAGradientLayer,
                  let end = fade.locations?.dropLast().last else { return false }
            let fadeBottom = pane.convert(CGPoint(x: 0, y: CGFloat(end.doubleValue) * pane.bounds.height), to: window).y
            return abs(pane.convert(pane.bounds, to: window).minY) < 1
                && abs(fadeBottom - window.safeAreaInsets.top) < 1
                && abs(controller.collection.convert(controller.collection.bounds, to: window).minY) < 1
                && abs(controller.collection.adjustedContentInset.top - controller.collection.contentInset.top) < 1
                && conversationReachesToolbar(controller)
        }
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
    private static func conversationReachesToolbar(_ controller: ConversationController) -> Bool {
        guard let window = controller.collection.window else { return false }
        var ancestor: UIView? = controller.collection
        while let view = ancestor {
            // A viewport at y=0 is insufficient if an intermediate SwiftUI clip
            // still starts below the toolbar. Inspect the complete drawing path.
            if view.clipsToBounds && view.convert(view.bounds, to: window).minY > 1 { return false }
            if view is PersistentPaneHost.Container { return true }
            ancestor = view.superview
        }
        return false
    }
    private static func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private static func workspaceFileDropReceiver() -> WorkspaceFileDropBridge.Probe? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .filter { !$0.isHidden }.flatMap(descendants).compactMap { $0 as? WorkspaceFileDropBridge.Probe }
            .first { $0.window != nil }
    }
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
    private static func conversation(containing messageID: UUID? = nil) -> ConversationController? {
        func children(_ controller: UIViewController) -> [UIViewController] { [controller] + controller.children.flatMap(children) }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .compactMap(\.rootViewController).flatMap(children).compactMap { $0 as? ConversationController }
            .first { controller in messageID.map { id in controller.messages.contains { $0.id == id.uuidString } } ?? true }
    }
    private static func floatingMessage(_ id: UUID, in window: UIWindow) -> CatalystFloatingMessageCheckProbe.Probe? {
        descendants(window).compactMap { $0 as? CatalystFloatingMessageCheckProbe.Probe }
            .first { $0.messageID == id && $0.window === window }
    }
    private static func isVisible(_ view: UIView, in window: UIWindow) -> Bool {
        guard view.window === window, view.bounds.width > 1, view.bounds.height > 1 else { return false }
        var visible = view.convert(view.bounds, to: window).intersection(window.bounds)
        var ancestor: UIView? = view
        while let current = ancestor {
            guard !current.isHidden, current.alpha > 0.01 else { return false }
            if current.clipsToBounds {
                visible = visible.intersection(current.convert(current.bounds, to: window))
            }
            ancestor = current.superview
        }
        return !visible.isNull && visible.width > 1 && visible.height > 1
    }
    private static func waitingStatus(in view: UIView) -> UIView? {
        descendants(view).first {
            $0.accessibilityIdentifier == "agent-thinking-status-layout" && $0.window != nil && !$0.isHidden
        }
    }
}

/// Synthetic external session for the production native drop delegate; no
/// replacement receiver or direct store import is used for the workspace check.
@MainActor private final class FileDropCheckSession: NSObject, UIDropSession {
    let items: [UIDragItem]
    let target: UIView
    let localDragSession: UIDragSession? = nil
    let allowsMoveOperation = false
    let isRestrictedToDraggingApplication = false
    let progress = Progress(totalUnitCount: 1)
    var progressIndicatorStyle: UIDropSessionProgressIndicatorStyle = .none

    init(provider: NSItemProvider, target: UIView) {
        items = [UIDragItem(itemProvider: provider)]
        self.target = target
        super.init()
    }

    func location(in view: UIView) -> CGPoint {
        target.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), to: view)
    }

    func hasItemsConforming(toTypeIdentifiers identifiers: [String]) -> Bool {
        items.contains { item in identifiers.contains { item.itemProvider.hasItemConformingToTypeIdentifier($0) } }
    }

    func canLoadObjects(ofClass aClass: NSItemProviderReading.Type) -> Bool {
        items.contains { $0.itemProvider.canLoadObject(ofClass: aClass) }
    }

    func loadObjects(ofClass aClass: NSItemProviderReading.Type,
        completion: @escaping ([NSItemProviderReading]) -> Void) -> Progress {
        // File addresses come from the native drag board. The provider
        // must not be asked to decode content as a file URL.
        preconditionFailure("Unexpected object loading in the file-drop receiver check")
    }
}

/// Test-only observation of the real SwiftUI row and its production quote action.
/// It does not replace rendering, scrolling, draft mutation, or focus handling.
struct CatalystFloatingMessageCheckProbe: UIViewRepresentable {
    let messageID: UUID
    let onQuote: () -> Void
    final class Probe: UIView {
        var messageID: UUID?
        var onQuote: () -> Void = {}
    }
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.messageID = messageID
        view.onQuote = onQuote
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: Probe, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: proposal.height ?? uiView.bounds.height)
    }
}

#endif
