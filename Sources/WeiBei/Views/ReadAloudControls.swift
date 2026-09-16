import SwiftUI
import WeiBeiCore
import WebKit

struct ReadAloudControls: View {
    let id: String
    var selection: String? = nil
    let load: () async throws -> String
    @ObservedObject private var reader = ReadAloud.shared
    @State private var showsDetails = false
    @State private var settings = WhiteboardMediaSettings()
    @State private var speechKey = ""
    var body: some View {
        HStack(spacing: 6) {
            if reader.sourceID == id {
                Button { reader.togglePause() } label: { Image(systemName: reader.paused ? "play.fill" : "pause.fill") }
                    .help(reader.paused ? "继续朗读" : "暂停朗读").accessibilityLabel(reader.paused ? "继续朗读" : "暂停朗读")
                Button { reader.stop(id: id) } label: { Image(systemName: "stop.fill") }.help("停止朗读").accessibilityLabel("停止朗读")
                Text(reader.paused ? "朗读已暂停" : reader.status).font(.caption).lineLimit(1)
            }
            Button { showsDetails.toggle() } label: { Image(systemName: "speaker.wave.2") }
                .help("朗读正文").accessibilityLabel("朗读正文")
                .popover(isPresented: $showsDetails) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("朗读").font(.headline)
                        SpeechSettingsFields(settings: $settings, speechKey: $speechKey)
                        Text("按段朗读，不改动原文。公式和代码暂时略过；中文动物语保留发音轮廓，系统语音更清晰。").font(.caption).foregroundStyle(.secondary)
                        if let error = reader.failure { Text(error).font(.callout).foregroundStyle(WeiBeiTheme.cinnabar) }
                        HStack {
                            Button("朗读正文") { start(load) }
                            if let selection, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("朗读选文") { start { selection } }
                            }
                        }.disabled(settings.voice == .silent)
                        if reader.sourceID == id { Text(reader.status).font(.caption) }
                        if reader.sourceID == id, let web = reader.web {
                            ReadAloudCompanionView(web: web).frame(height: 174)
                                .onAppear { reader.showCompanion(true) }
                                .onDisappear { reader.showCompanion(false) }
                        }
                    }.padding(20).frame(width: 360).background(WeiBeiTheme.paper)
                    .onAppear {
                        if let data = UserDefaults.standard.data(forKey: "whiteboard.media.settings"),
                           let settings = try? JSONDecoder().decode(WhiteboardMediaSettings.self, from: data) {
                            self.settings = settings
                        }
                        settings.voice = UserDefaults.standard.string(forKey: "readAloud.voice").flatMap(WhiteboardMediaSettings.Voice.init(rawValue:)) ?? .system
                    }
                }
        }.buttonStyle(.borderless)
        .onDisappear { reader.stop(id: id) }
        .onChange(of: id) { previous, _ in reader.stop(id: previous) }
    }
    private func start(_ body: @escaping () async throws -> String) {
        do {
            var shared = settings
            let voice = settings.voice
            if let data = UserDefaults.standard.data(forKey: "whiteboard.media.settings") {
                shared.voice = try JSONDecoder().decode(WhiteboardMediaSettings.self, from: data).voice
            } else { shared.voice = .animalese }
            // Save shared service/speed, retaining the classroom's separate voice choice.
            try settings.validate()
            try shared.save(speechKey: speechKey)
            UserDefaults.standard.set(voice.rawValue, forKey: "readAloud.voice")
            reader.start(id: id, load: body)
        } catch { reader.failure = error.localizedDescription }
    }
}

private struct ReadAloudCompanionView: WhiteboardRepresentable {
    let web: WKWebView
    #if targetEnvironment(macCatalyst)
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ view: WKWebView, context: Context) {}
    #else
    func makeNSView(context: Context) -> WKWebView { web }
    func updateNSView(_ view: WKWebView, context: Context) {}
    #endif
}

struct MaterialReadAloudControls: View {
    @ObservedObject var store: WorkspaceStore
    let item: StudyItem
    var body: some View {
        ReadAloudControls(id: "material-" + item.id,
            selection: store.selectionContext?.itemID == item.id && store.selectionContext?.isNoteSelection == false ? store.selectionContext?.text : nil) {
            let index = store.courseDocumentSearchIndex
            let task = Task.detached(priority: .userInitiated) {
                var result = "", cursor: String?, visited = Set<String>()
                repeat {
                    try Task.checkCancellation()
                    let page = index.read(item: item, location: nil, cursor: cursor, maximumCharacters: 24_000)
                    guard let text = page.text else { throw WhiteboardFailure("文稿正文暂不可读，请检查文件或选择一段文字。") }
                    result += text; cursor = page.nextCursor
                    if let cursor, !visited.insert(cursor).inserted { throw WhiteboardFailure("文稿读取进度重复，已停止。") }
                    if page.isTruncated && cursor == nil { throw WhiteboardFailure("文稿尚未完整读取；可先选中需要朗读的段落。") }
                } while cursor != nil
                return result
            }
            return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        }
    }
}

struct NoteReadAloudControls: View {
    @ObservedObject var store: WorkspaceStore
    var body: some View {
        ReadAloudControls(id: "note-" + store.noteEditingSession.documentID,
            selection: store.selectionContext?.isNoteSelection == true && store.selectionContext?.itemID == store.activeNotebookItemID ? store.selectionContext?.text : nil) {
            try await store.noteEditingSession.snapshot().markdown
        }
    }
}

struct SpeechSettingsFields: View {
    @Binding var settings: WhiteboardMediaSettings
    @Binding var speechKey: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("声音", selection: $settings.voice) {
                Text("系统中文语音").tag(WhiteboardMediaSettings.Voice.system)
                Text("中文动物语").tag(WhiteboardMediaSettings.Voice.animalese)
                Text("静音阅读").tag(WhiteboardMediaSettings.Voice.silent)
                Text("云端语音").tag(WhiteboardMediaSettings.Voice.cloud)
            }
            HStack {
                Text("语速"); Slider(value: $settings.speed, in: 0.5...2, step: 0.25)
                Text("\(settings.speed, specifier: "%.2f")×").monospacedDigit()
            }
            DisclosureGroup("高级：云端语音") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("兼容接口根地址（例如以 /v1 结尾）", text: $settings.speech.baseURL)
                    TextField("模型名称", text: $settings.speech.model)
                    TextField("音色名称", text: $settings.speech.voice)
                    SecureField("密钥（留空保留）", text: $speechKey)
                }.textFieldStyle(.roundedBorder)
            }
            Text("系统中文与动物语无需接口；云端语音按填写的服务合成。声音在下一次朗读生效，语速和服务配置共用。")
                .font(.caption).foregroundStyle(.secondary)
            Text("中文音节：Chen Wang；Hugo Lopez、Nicolas Vion 整理。CC BY-SA 3.0。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
