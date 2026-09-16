import AVFoundation
import SwiftUI
import WebKit
import WeiBeiCore

extension WhiteboardMediaSettings {
    func validate() throws {
        guard (0.5...2).contains(speed) else { throw WhiteboardFailure("语速应在 0.5–2 倍之间。") }
        if !speech.baseURL.isEmpty { _ = try AgentProviderEndpoint(provider: .custom, baseURL: speech.baseURL) }
        if voice == .cloud && (!speech.isConfigured || speech.voice.isEmpty) {
            throw WhiteboardFailure("请填写云端服务地址、模型和音色，或选择系统中文语音。")
        }
    }
    func save(speechKey: String = "") throws {
        try validate()
        if !speechKey.isEmpty {
            try NativeAgentCredentialStore.defaultStore().upsert(.init(
                provider: speech.credentialID(kind: "speech"), apiKey: speechKey, boundEndpoint: speech.baseURL))
        }
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "whiteboard.media.settings")
    }
}

/// One audible source across the app. A classroom yields by pausing its unfinished action.
@MainActor enum SpeechFocus {
    private static var owner: ObjectIdentifier?
    private static var interrupt: (() -> Void)?
    static func claim(_ source: AnyObject, interrupt next: @escaping () -> Void) {
        let id = ObjectIdentifier(source)
        if owner != id { interrupt?() }
        owner = id; interrupt = next
    }
    static func release(_ source: AnyObject) {
        if owner == ObjectIdentifier(source) { owner = nil; interrupt = nil }
    }
}

@MainActor final class SystemNarrator: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SystemNarrator()
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    private var started: (() -> Void)?
    private var boundary: ((NSRange) -> Void)?
    private var completed: ((Error?) -> Void)?
    private var watchdog: Task<Void, Never>?
    private var lastProgress = Date()
    private var pauseRequested = false
    override init() { super.init(); synthesizer.delegate = self }
    func speak(_ text: String, speed: Double, started: @escaping () -> Void, boundary: ((NSRange) -> Void)? = nil, completed: @escaping (Error?) -> Void) {
        stop()
        guard let voice = AVSpeechSynthesisVoice(language: "zh-CN") else { completed(WhiteboardFailure("系统中文语音不可用")); return }
        let value = AVSpeechUtterance(string: text); value.voice = voice
        value.rate = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        utterance = value; self.started = started; self.boundary = boundary; self.completed = completed
        lastProgress = Date(); synthesizer.speak(value)
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, utterance === value else { return }
                if pauseRequested || synthesizer.isPaused { lastProgress = Date() }
                else if Date().timeIntervalSince(lastProgress) > 30 { stop(WhiteboardFailure("系统朗读没有继续播放，请重试。")); return }
            }
        }
    }
    func pause() { pauseRequested = true; if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .immediate) } }
    func resume() { pauseRequested = false; synthesizer.continueSpeaking() }
    func stop(_ error: Error = CancellationError()) {
        watchdog?.cancel(); watchdog = nil
        pauseRequested = false
        let callback = completed; utterance = nil; started = nil; boundary = nil; completed = nil
        synthesizer.stopSpeaking(at: .immediate); callback?(error)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart value: AVSpeechUtterance) {
        Task { @MainActor in if utterance === value {
            lastProgress = Date(); if pauseRequested { self.synthesizer.pauseSpeaking(at: .immediate) }; started?()
        } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel value: AVSpeechUtterance) {
        Task { @MainActor in if utterance === value { stop() } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance value: AVSpeechUtterance) {
        Task { @MainActor in if utterance === value { lastProgress = Date(); boundary?(range) } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish value: AVSpeechUtterance) {
        Task { @MainActor in guard utterance === value else { return }; utterance = nil; watchdog?.cancel(); watchdog = nil
            let callback = completed; completed = nil; started = nil; boundary = nil; callback?(nil) }
    }
}

@MainActor final class ReadAloud: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = ReadAloud()
    @Published private(set) var sourceID: String?
    @Published private(set) var status = ""
    @Published private(set) var paused = false
    @Published var failure: String?
    private var settings = WhiteboardMediaSettings()
    private var token = UUID().uuidString
    private var work: Task<Void, Never>?
    @Published private(set) var web: WKWebView?
    private var ready = false
    private var readyWaiters: [CheckedContinuation<Void, Error>] = []
    private var pauseWaiter: CheckedContinuation<Void, Never>?

    func start(id: String, load: @escaping () async throws -> String) {
        stop(); failure = nil; sourceID = id; status = "正在准备朗读…"
        SpeechFocus.claim(self) { [weak self] in self?.stop() }
        let run = token
        work = Task { [weak self] in
            guard let self else { return }
            do {
                if let data = UserDefaults.standard.data(forKey: "whiteboard.media.settings") { settings = try JSONDecoder().decode(WhiteboardMediaSettings.self, from: data) }
                settings.voice = UserDefaults.standard.string(forKey: "readAloud.voice").flatMap(WhiteboardMediaSettings.Voice.init(rawValue:)) ?? .system
                guard settings.voice != .silent else { throw WhiteboardFailure("当前为静音模式，请在朗读设置中选择声音。") }
                let markdown = try await load(); try check(run)
                try await loadRuntime(); try check(run)
                let prepared = try await call("return window.WeiBeiReadingVoice.prepare(markdown)", ["markdown": markdown]) as? [String: Any]
                guard let paragraphs = prepared?["paragraphs"] as? [String], !paragraphs.isEmpty else { throw WhiteboardFailure("没有可朗读的正文；公式和代码暂不朗读。") }
                for (index, text) in paragraphs.enumerated() {
                    try check(run)
                    if paused { await withCheckedContinuation { self.pauseWaiter = $0 } }
                    try check(run)
                    status = "正在朗读 \(index + 1)/\(paragraphs.count) 段" + (prepared?["skipped"] as? Bool == true ? " · 已略过公式和代码" : "")
                    if settings.voice == .system {
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            SystemNarrator.shared.speak(text, speed: self.settings.speed, started: { [weak self] in
                                self?.send("window.WeiBeiReadingVoice.systemStarted(run, value)", ["run": run, "value": self?.paused ?? false])
                            }, boundary: { [weak self] range in
                                self?.send("window.WeiBeiReadingVoice.systemBoundary(text, run)", ["text": (text as NSString).substring(with: range), "run": run])
                            }, completed: { [weak self] error in
                                self?.send("window.WeiBeiReadingVoice.systemFinished(run)", ["run": run])
                                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                            })
                        }
                    } else {
                        var cloud = ""
                        if settings.voice == .cloud {
                            let data = try await WhiteboardMedia.speech(text, settings: settings); try check(run)
                            cloud = "data:audio/mpeg;base64," + data.base64EncodedString()
                        }
                        if paused { await withCheckedContinuation { self.pauseWaiter = $0 } }
                        try check(run)
                        _ = try await call("return await window.WeiBeiReadingVoice.play(text, mode, speed, run, cloud)",
                            ["text": text, "mode": settings.voice.rawValue, "speed": settings.speed, "run": run, "cloud": cloud])
                    }
                }
                try check(run); status = "朗读完成"; sourceID = nil; SpeechFocus.release(self)
            } catch {
                if token == run { failure = error.localizedDescription; status = "朗读未完成"; sourceID = nil; SpeechFocus.release(self) }
            }
        }
    }
    private func check(_ run: String) throws { try Task.checkCancellation(); if token != run { throw CancellationError() } }
    func showCompanion(_ visible: Bool) { send("window.WeiBeiReadingVoice.visible(value)", ["value": visible]) }
    func togglePause() {
        guard sourceID != nil else { return }; paused.toggle()
        if settings.voice == .system { paused ? SystemNarrator.shared.pause() : SystemNarrator.shared.resume() }
        send("window.WeiBeiReadingVoice.pause(value, run)", ["value": paused, "run": token])
        if !paused { pauseWaiter?.resume(); pauseWaiter = nil }
    }
    func stop(id: String? = nil) {
        if let id, id != sourceID { return }
        let old = token; token = UUID().uuidString; work?.cancel(); work = nil
        if sourceID != nil && settings.voice == .system { SystemNarrator.shared.stop() }
        send("window.WeiBeiReadingVoice.stop(run)", ["run": old])
        pauseWaiter?.resume(); pauseWaiter = nil; sourceID = nil; paused = false; status = "已停止"
        SpeechFocus.release(self)
    }
    private func loadRuntime() async throws {
        if ready { return }
        if web == nil {
            guard let url = WeiBeiResources.bundle.url(forResource: "reading-voice", withExtension: "html", subdirectory: "Editor") else { throw WhiteboardFailure("朗读资源缺失，请重新构建应用。") }
            let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
            configuration.mediaTypesRequiringUserActionForPlayback = []; configuration.userContentController.add(self, name: "readingVoice")
            let value = WKWebView(frame: .zero, configuration: configuration); web = value; value.navigationDelegate = self
            value.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            Task { [weak self, weak value] in
                try? await Task.sleep(for: .seconds(20))
                if let self, let value, web === value, !ready { runtimeFailed(WhiteboardFailure("朗读播放器加载超时，请重试。")) }
            }
        }
        try await withCheckedThrowingContinuation { readyWaiters.append($0) }
    }
    private func call(_ code: String, _ arguments: [String: Any]) async throws -> Any? {
        guard let web else { throw WhiteboardFailure("朗读播放器尚未就绪") }
        return try await web.callAsyncJavaScript(code, arguments: arguments, in: nil, contentWorld: .page)
    }
    private func send(_ code: String, _ arguments: [String: Any]) {
        guard ready else { return }
        let current = token
        Task { [weak self] in do { _ = try await self?.call(code, arguments) }
            catch { if self?.token == current { self?.failure = "朗读控制失败：\(error.localizedDescription)" } } }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let value = message.body as? [String: Any] else { return }
        if value["type"] as? String == "ready" { ready = true; readyWaiters.forEach { $0.resume() }; readyWaiters = [] }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.request.url?.isFileURL == true ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { runtimeFailed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { runtimeFailed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { runtimeFailed(WhiteboardFailure("朗读进程中断，请重新播放。")) }
    private func runtimeFailed(_ error: Error) {
        stop(); ready = false; web?.configuration.userContentController.removeAllScriptMessageHandlers(); web = nil
        readyWaiters.forEach { $0.resume(throwing: error) }; readyWaiters = []; failure = error.localizedDescription
    }
}
