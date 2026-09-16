import AVFoundation
import Foundation
import SwiftUI
import WeiBeiCore

@MainActor
final class WhiteboardClassroom: NSObject, ObservableObject {
    @Published var source: WhiteboardSource?
    @Published var session: WhiteboardSession?
    @Published var history: [WhiteboardSession] = []
    @Published var settings = WhiteboardMediaSettings()
    @Published var goal = "用直观图示、分步推导和一个例子讲懂这段材料"
    @Published var question = ""
    @Published var status = ""
    @Published var failure: String?
    @Published var generating = false
    @Published var replying = false
    @Published var playing = false
    @Published var firstBoardSeconds: Double?
    @Published var canvasZoom = 1.0
    @Published var handwriting = false
    @Published var canUndoInk = false
    var busy: Bool { generating || replying }
    var currentAction: WhiteboardAction? { session?.currentAction }
    let archive: WhiteboardSessionStore
    private let provider: AgentProviderID
    private let baseURL, model: String
    private let suppliedAdapter: (any NativeLLMAdapter)?
    private var speechID: String?
    private var gate = WhiteboardActionGate()
    private var runID = UUID(), dispatchID = UUID(), replyID = UUID()
    private var generationWork: Task<Void, Never>?, replyWork: Task<Void, Never>?, dispatchTask: Task<Void, Never>?
    private var speechTasks: [String: Task<Data, Error>] = [:]
    private var renderer: ((String, [String: Any]) -> Void)?
    private var restoring = false, closed = false, autoStartPending = false, generationStopped = false
    private var restoreID = UUID().uuidString
    private var startedAt: Date?
    private var pauseVersion = 0
    private var resumeAfterReply: Int?
    private var replyQueue: [WhiteboardDiscussion] = []

    init(directory: URL, provider: AgentProviderID, baseURL: String, model: String, adapter: (any NativeLLMAdapter)? = nil) {
        archive = WhiteboardSessionStore(directory: directory)
        self.provider = provider; self.baseURL = baseURL
        suppliedAdapter = adapter
        self.model = model.isEmpty ? NativeProviderRouting.route(provider).defaultModel : model
        super.init()
        if let data = UserDefaults.standard.data(forKey: "whiteboard.media.settings") {
            do { settings = try JSONDecoder().decode(WhiteboardMediaSettings.self, from: data) }
            catch { failure = "白板语音配置无法读取，请重新设置。" }
        }
    }
    func loadSource(_ value: WhiteboardSource) {
        source = value
        do { history = try archive.list(itemID: value.itemID) }
        catch { failure = "历史课堂读取失败：\(error.localizedDescription)" }
    }
    private func adapter() async throws -> any NativeLLMAdapter {
        if let suppliedAdapter { return suppliedAdapter }
        guard !model.isEmpty else { throw WhiteboardFailure("请先在设置中选择对话模型。") }
        return try await NativeLLMAdapterFactory.make(provider: provider, model: model,
            endpoint: AgentProviderEndpoint(provider: provider, baseURL: baseURL))
    }
    func generate() {
        guard let source, !busy else { return }
        stopPlayback(); failure = nil; closed = false; generationStopped = false
        let value = WhiteboardSession(source: source, goal: goal, lesson: .init(title: String(goal.prefix(200))))
        do { try archive.save(value) } catch { failure = error.localizedDescription; return }
        session = value; gate = .init(); runID = UUID(); autoStartPending = true
        firstBoardSeconds = nil; startedAt = Date(); status = "正在准备第一块板书…"
        rehydrate(); generatePage()
    }
    private func generatePage() {
        guard !generating, !closed, !generationStopped, let value = session, !value.generationComplete else { return }
        let page = value.generatedPages + 1, token = runID
        generating = true
        generationWork = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await WhiteboardTeacher.generatePage(adapter: adapter(), model: model, source: value.source,
                    goal: value.goal, page: page, session: value, receive: { [weak self] action in try await self?.append(action, run: token) })
                try Task.checkCancellation(); guard runID == token else { return }
                session?.generatedPages = page
                session?.generationComplete = page >= (session?.keyPoints.count ?? 0)
                generating = false; persist(); history = try archive.list(itemID: value.source.itemID)
                pump(); prefetchPage()
            } catch is CancellationError { if runID == token { generating = false } }
            catch {
                if runID == token { generating = false; generationStopped = true; fail(error.localizedDescription) }
            }
        }
    }
    private func append(_ action: WhiteboardAction, run: UUID) throws {
        guard runID == run, !closed else { throw CancellationError() }
        session?.lesson.actions.append(action)
        if action.type == .sessionReady, let title = action.title { session?.lesson.title = title }
        if let value = session { try archive.save(value) }
        if autoStartPending && action.leaves.contains(where: { $0.type == .board || $0.type == .graph }) {
            autoStartPending = false; playing = true; claimSpeech(); renderer?("pause", ["value": false]); status = "开始讲解"
        }
        pump()
    }
    private func prefetchPage() {
        guard !generating, !generationStopped, let value = session, !value.generationComplete else { return }
        // Each completed page immediately starts the next request with the latest answers.
        generatePage()
    }
    func resumeGeneration() {
        generationStopped = false; failure = nil; generatePage()
    }
    func attachRenderer(_ send: @escaping (String, [String: Any]) -> Void) { renderer = send; closed = false; rehydrate() }
    private func rehydrate() {
        guard renderer != nil else { return }
        restoring = true; restoreID = UUID().uuidString
        var actions: [WhiteboardAction] = []
        if let value = session {
            for index in 0...value.cursor {
                actions += value.discussions.filter { $0.insertionCursor == index }.compactMap(\.card)
                if index < value.cursor { actions.append(value.lesson.actions[index]) }
            }
        }
        do { renderer?("restore", ["actions": try json(actions), "state": try json(session?.canvas), "requestID": restoreID]) }
        catch { fail(error.localizedDescription) }
    }
    private func json<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
    }
    func restore(_ value: WhiteboardSession) {
        cancel(); stopPlayback()
        do {
            let saved = try archive.load(value.id)
            closed = false; session = saved; source = saved.source; goal = saved.goal
            gate = .init(cursor: saved.cursor); status = "已恢复，点击继续"; failure = nil
            generationStopped = false; rehydrate()
        } catch { failure = error.localizedDescription }
    }
    func persist() {
        guard var value = session else { return }
        value.updatedAt = Date(); session = value
        do { try archive.save(value) } catch { fail("课堂尚未保存：\(error.localizedDescription)") }
    }
    func play() {
        guard !closed, !replying, session != nil else { return }
        if failure != nil { replay(); return }
        playing = true; claimSpeech(); status = "正在讲解"
        renderer?("pause", ["value": false]); if speechID != nil { SystemNarrator.shared.resume() }; pump(); prefetchPage()
    }
    func pause() { pauseVersion += 1; autoStartPending = false; pausePlayback() }
    private func pausePlayback() {
        renderer?("generationWaiting", ["value": false])
        playing = false; renderer?("pause", ["value": true])
        if speechID != nil { SystemNarrator.shared.pause() }
        if session?.completed == false { status = "已暂停" }
    }
    func stopPlayback() {
        playing = false; dispatchID = UUID(); dispatchTask?.cancel(); dispatchTask = nil
        let hadSpeech = speechID != nil; speechID = nil
        if hadSpeech { SystemNarrator.shared.stop() }
        SpeechFocus.release(self)
        speechTasks.values.forEach { $0.cancel() }; speechTasks = [:]
    }
    func replay() {
        guard !replying else { return }
        stopPlayback(); failure = nil
        if currentAction == nil, (session?.cursor ?? 0) > 0 { session?.cursor -= 1 }
        gate = .init(cursor: session?.cursor ?? 0); persist(); playing = true; claimSpeech(); rehydrate()
    }
    private func pump() {
        guard playing, !restoring, !closed, !replying, dispatchTask == nil, renderer != nil, let value = session else { return }
        guard let (action, ticket) = gate.dispatch(value.lesson.actions) else {
            if value.completed { playing = false; renderer?("generationWaiting", ["value": false]); status = "这堂课讲完了，仍可答题和追问" }
            else if gate.pendingID == nil {
                prefetchPage(); status = "正在准备下一页… 准备好后自动继续"
                renderer?("generationWaiting", ["value": true])
            }
            return
        }
        renderer?("generationWaiting", ["value": false]); status = "正在讲解"
        let token = runID, dispatcher = UUID(); dispatchID = dispatcher
        dispatchTask = Task { [weak self] in
            guard let self else { return }
            defer { if dispatchID == dispatcher { dispatchTask = nil; pump() } }
            do {
                var audio: [String: String] = [:]
                for a in action.leaves where a.type == .speak && settings.voice == .cloud {
                    let data = try await prepareSpeech(a).value
                    audio[a.stepID] = "data:audio/mpeg;base64," + data.base64EncodedString()
                }
                try Task.checkCancellation()
                guard runID == token && gate.ticket == ticket else { return }
                guard playing else { gate.retry(); return }
                renderer?("receive", ["envelope": ["action": try json(action), "ticket": ticket.uuidString,
                    "audio": audio, "voice": settings.voice.rawValue, "silent": settings.voice == .silent, "speed": settings.speed]])
                if settings.voice == .cloud, value.lesson.actions.indices.contains(value.cursor + 1) {
                    for a in value.lesson.actions[value.cursor + 1].leaves where a.type == .speak { _ = prepareSpeech(a) }
                }
            } catch is CancellationError {}
            catch { if runID == token { gate.retry(); fail(error.localizedDescription) } }
        }
    }
    private func prepareSpeech(_ action: WhiteboardAction) -> Task<Data, Error> {
        if let task = speechTasks[action.stepID] { return task }
        let settings = settings
        let task = Task { try await WhiteboardMedia.speech(action.text ?? "", settings: settings) }
        speechTasks[action.stepID] = task; return task
    }
    func receive(_ message: [String: Any]) {
        guard !closed, let type = message["type"] as? String else { return }
        if type == "canvas_controls" {
            if let zoom = message["zoom"] as? Double, (0.5...2).contains(zoom) { canvasZoom = zoom }
            handwriting = message["inking"] as? Bool == true; canUndoInk = message["canUndo"] as? Bool == true
            return
        }
        if type == "restored" {
            guard message["request_id"] as? String == restoreID else { return }
            restoring = false; renderer?("pause", ["value": !playing]); pump(); return
        }
        if type == "sync_whiteboard_state", !restoring, let state = message["whiteboard_state"] {
            do {
                session?.canvas = try JSONDecoder().decode(WhiteboardCanvasState.self, from: JSONSerialization.data(withJSONObject: state)); persist()
            } catch { fail("画布状态没有保存：\(error.localizedDescription)") }; return
        }
        if type == "supplement_complete", message["reply_id"] as? String == replyID.uuidString { finishReply(); return }
        if type == "supplement_failed", message["reply_id"] as? String == replyID.uuidString {
            replying = false; fail(message["message"] as? String ?? "补充板书未完成"); return
        }
        guard let raw = message["ticket"] as? String, let ticket = UUID(uuidString: raw), ticket == gate.ticket else { return }
        if type == "board_revealed", firstBoardSeconds == nil, let startedAt {
            firstBoardSeconds = Date().timeIntervalSince(startedAt)
        }
        if type == "action_step_failed", message["step_id"] as? String == gate.pendingID {
            fail(message["message"] as? String ?? "动作未完成，请重试"); return
        }
        if type == "action_step_complete", let id = message["step_id"] as? String {
            guard gate.acknowledge(stepID: id, ticket: ticket, success: true) else { return }
            if let action = currentAction { for a in action.leaves { speechTasks[a.stepID] = nil } }
            session?.cursor = gate.cursor; persist()
            Task { @MainActor [weak self] in self?.pump(); self?.prefetchPage() }
        } else if (type == "speech_request" || type == "question"), let raw = message["action"] {
            do {
                let action = try JSONDecoder().decode(WhiteboardAction.self, from: JSONSerialization.data(withJSONObject: raw))
                guard currentAction?.leaves.contains(action) == true else { return }
                if type == "question" {
                    if session?.presentedQuestionIDs.contains(action.stepID) == false { session?.presentedQuestionIDs.append(action.stepID); persist() }
                    renderer?("questionDisplayed", ["id": action.stepID])
                } else { speak(action) }
            } catch { fail(error.localizedDescription) }
        }
    }
    private func claimSpeech() { SpeechFocus.claim(self) { [weak self] in self?.pause() } }
    func canvasCommand(_ command: String) { renderer?("canvasCommand", ["command": command]) }
    func applyMediaSettings(_ value: WhiteboardMediaSettings) {
        guard value != settings else { return }
        stopPlayback(); settings = value
        gate = .init(cursor: session?.cursor ?? 0); rehydrate()
    }
    private func speak(_ action: WhiteboardAction) {
        guard settings.voice == .system else { renderer?("speechFinished", ["id": action.stepID, "error": "语音模式不匹配"]); return }
        speechID = action.stepID
        SystemNarrator.shared.speak(action.text ?? "", speed: settings.speed, started: { [weak self] in
            guard let self, speechID == action.stepID else { return }
            renderer?("speechStarted", ["id": action.stepID])
        }, boundary: { [weak self] range in
            guard let self, speechID == action.stepID else { return }
            let text = (action.text ?? "") as NSString
            renderer?("speechBoundary", ["id": action.stepID, "text": text.substring(with: range),
                "progress": Double(range.location) / Double(max(1, text.length))])
        }, completed: { [weak self] error in
            guard let self, speechID == action.stepID else { return }; speechID = nil
            if error is CancellationError { pausePlayback(); gate.retry(); rehydrate(); return }
            var args: [String: Any] = ["id": action.stepID]
            if let error { args["error"] = error.localizedDescription }
            renderer?("speechFinished", args)
        })
        if !playing { SystemNarrator.shared.pause() }
    }
    func answer(_ text: String, to action: WhiteboardAction, correct: Bool? = nil) {
        guard session?.presentedQuestionIDs.contains(action.stepID) == true, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let correction = session?.recordAnswer(text, to: action, correct: correct)
        persist()
        if let correct { renderer?("feedback", ["correct": correct]) }
        if let correction { replyQueue.append(correction); if !replying { beginReply() } }
    }
    func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 8_000, !replying, let value = session,
              value.lesson.actions.prefix(value.cursor).contains(where: { $0.type == .newPage }) else { return }
        let discussion = WhiteboardDiscussion(stepID: currentAction?.stepID ?? "finished", question: text, insertionCursor: value.cursor)
        session?.discussions.append(discussion); persist(); question = ""
        replyQueue.append(discussion); beginReply()
    }
    private func beginReply(continuing: Bool = false) {
        guard !replyQueue.isEmpty, let value = session else { return }
        let discussion = replyQueue.removeFirst(), text = discussion.question
        if !continuing { resumeAfterReply = playing ? pauseVersion : nil }
        pausePlayback(); failure = nil; replying = true
        status = discussion.correctionFor == nil ? "正在回答…" : "正在针对这道题讲解…"
        let token = UUID(); replyID = token
        replyWork = Task { [weak self] in
            guard let self else { return }
            do {
                try await WhiteboardTeacher.reply(adapter: adapter(), model: model, session: value, question: text, correction: discussion.correctionFor != nil,
                    receive: { [weak self] action in try await self?.appendReply(action, discussionID: discussion.id, token: token) })
                try Task.checkCancellation()
                guard replyID == token, let index = session?.discussions.firstIndex(where: { $0.id == discussion.id }) else { return }
                session?.discussions[index].completed = true; persist()
                if let card = session?.discussions[index].card {
                    renderer?("supplement", ["action": try json(card), "replyID": token.uuidString])
                } else { finishReply() }
            } catch is CancellationError {}
            catch { if replyID == token { replying = false; fail(error.localizedDescription); if discussion.correctionFor == nil { question = text } } }
        }
    }
    private func appendReply(_ value: WhiteboardAction, discussionID: UUID, token: UUID) throws {
        guard replyID == token, !closed, let index = session?.discussions.firstIndex(where: { $0.id == discussionID }) else { throw CancellationError() }
        if value.type == .speak {
            let separator = session?.discussions[index].text.isEmpty == true ? "" : "\n\n"
            session?.discussions[index].text += separator + (value.text ?? "")
        }
        else {
            var card = value; card.boardUID = 100_000 + index; card.stepID = "reply-" + discussionID.uuidString
            session?.discussions[index].card = card
        }
        persist()
    }
    private func finishReply() {
        replying = false; status = "回答已显示"
        if !replyQueue.isEmpty { beginReply(continuing: true); return }
        if resumeAfterReply == pauseVersion { resumeAfterReply = nil; play() }
    }
    func fail(_ message: String) { guard !closed else { return }; failure = message; pausePlayback(); status = "尚未完成，可重试当前步骤或继续编排" }
    func cancel() {
        runID = UUID(); replyID = UUID(); generationWork?.cancel(); replyWork?.cancel()
        replyQueue = []
        generating = false; replying = false; autoStartPending = false; generationStopped = true
        stopPlayback(); gate = .init(cursor: session?.cursor ?? 0); rehydrate(); status = "已停止，收到的课堂内容保留"
    }
    func close() {
        guard !closed else { return }
        runID = UUID(); replyID = UUID(); generationWork?.cancel(); replyWork?.cancel()
        replyQueue = []
        generating = false; replying = false; stopPlayback(); closed = true; renderer = nil; persist()
    }
}
