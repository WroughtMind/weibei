import SwiftUI
import WeiBeiCore

struct WhiteboardSessionView: View {
    @ObservedObject var store: WorkspaceStore
    let item: StudyItem
    let selection: SelectionContext?
    @StateObject private var classroom: WhiteboardClassroom
    @Environment(\.dismiss) private var dismiss
    @State private var firstPage: Int
    @State private var lastPage: Int
    @State private var selectionOnly: Bool
    @State private var showsSettings = false
    @State private var sourceBusy = false
    @State private var savedNote = false

    init(store: WorkspaceStore, item: StudyItem, selection: SelectionContext?, pageIndex: Int) {
        self.store = store; self.item = item
        self.selection = selection?.itemID == item.id ? selection : nil
        _selectionOnly = State(initialValue: selection?.itemID == item.id)
        _firstPage = State(initialValue: pageIndex + 1); _lastPage = State(initialValue: pageIndex + 1)
        _classroom = StateObject(wrappedValue: WhiteboardClassroom(
            directory: store.workspaceDirectory.appendingPathComponent("Whiteboard", isDirectory: true),
            provider: store.agentProviderID, baseURL: store.agentBaseURL, model: store.modelName))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if classroom.session == nil {
                preparation
            } else {
                HStack(spacing: 0) {
                    sourcePane.frame(width: 230)
                    Divider()
                    boardPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    discussionPane.frame(width: 260)
                }
            }
            if let failure = classroom.failure {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(failure).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Button("关闭提示") { classroom.failure = nil }
                }.font(.callout).padding(12).foregroundStyle(WeiBeiTheme.cinnabar)
                .background(WeiBeiTheme.paperRaised)
            }
            Divider()
            controls
        }
        .frame(minWidth: 920, idealWidth: 1160, minHeight: 650, idealHeight: 780)
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .sheet(isPresented: $showsSettings) { WhiteboardSettingsView(classroom: classroom) }
        .task { await loadSource() }
        .onDisappear { classroom.close() }
        .onChange(of: classroom.session?.id) { _, _ in savedNote = false }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis").foregroundStyle(WeiBeiTheme.cinnabar)
            Text("白板课堂").font(.headline)
            Text(classroom.session?.lesson.title ?? item.title).lineLimit(1).foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer()
            if classroom.session != nil {
                Button("重新编排") { classroom.generate() }.disabled(classroom.busy)
            }
            Menu {
                if classroom.history.isEmpty { Text("还没有保存的课堂") }
                ForEach(classroom.history) { saved in
                    Button("\(saved.lesson.title) · \(saved.completedKeyPoints.count)/\(saved.keyPoints.count) 个要点") { classroom.restore(saved) }
                }
            } label: { Label("历史", systemImage: "clock.arrow.circlepath") }
            .disabled(classroom.busy)
            Button { classroom.pause(); showsSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .help("讲解语音设置").accessibilityLabel("讲解语音设置")
            Button("完成") { classroom.close(); dismiss() }
        }.buttonStyle(.borderless).padding(16)
    }

    private var preparation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("把这段材料讲明白").font(.system(size: 30, weight: .medium, design: .serif))
                Text("板书逐步展开，随时暂停提问；课堂进度自动保存。")
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                if selection != nil {
                    Toggle("只讲选中的文字", isOn: $selectionOnly)
                }
                if item.kind == .pdf && !selectionOnly {
                    HStack {
                        Stepper("从第 \(firstPage) 页", value: $firstPage, in: 1...9999)
                        Stepper("到第 \(lastPage) 页", value: $lastPage, in: firstPage...max(firstPage, 9999))
                    }
                    Text("每堂课最多选择 8 页；按页保留来源。").font(.caption).foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                HStack {
                    Button("读取所选范围") { Task { await loadSource() } }.disabled(sourceBusy || classroom.busy)
                    if sourceBusy { ProgressView().controlSize(.small) }
                }
                if let source = classroom.source {
                    Text("已读取：\(source.title) · \(source.pages.count) 个来源片段").font(.subheadline)
                    Text(source.pages.map(\.text).joined(separator: "\n").prefix(700) + "…")
                        .font(.callout).textSelection(.enabled).foregroundStyle(WeiBeiTheme.secondaryInk)
                }
                TextField("希望重点讲什么？", text: $classroom.goal, axis: .vertical)
                    .lineLimit(2...4).textFieldStyle(.roundedBorder)
                Text("讲解模型：\(store.modelName.isEmpty ? "当前服务默认模型" : store.modelName)")
                    .font(.caption).foregroundStyle(WeiBeiTheme.secondaryInk)
                Button { classroom.generate() } label: {
                    Label(classroom.busy ? classroom.status : "开始讲解", systemImage: "play.rectangle")
                }.buttonStyle(.borderedProminent).tint(WeiBeiTheme.cinnabar)
                    .disabled(classroom.source == nil || classroom.busy || sourceBusy)
            }.frame(maxWidth: 620, alignment: .leading).padding(36).frame(maxWidth: .infinity)
        }
        .onChange(of: firstPage) { _, value in if lastPage < value { lastPage = value }; classroom.source = nil }
        .onChange(of: lastPage) { _, _ in classroom.source = nil }
        .onChange(of: selectionOnly) { _, _ in classroom.source = nil }
    }

    private func loadSource() async {
        guard !sourceBusy else { return }
        sourceBusy = true; classroom.failure = nil
        defer { sourceBusy = false }
        do {
            let pages: [WhiteboardSource.Page]
            if selectionOnly, let selection {
                guard !selection.text.isEmpty && selection.text.count <= 48_000 else {
                    throw WhiteboardFailure("选文为空或超过 48,000 字，请重新选择。")
                }
                pages = [.init(number: firstPage, text: selection.text)]
            } else {
                guard lastPage >= firstPage, lastPage - firstPage < 8 else {
                    throw WhiteboardFailure("请选择连续的 1–8 页材料。")
                }
                let index = store.courseDocumentSearchIndex
                let indexes = item.kind == .pdf ? Array(firstPage...lastPage) : [1]
                let item = item
                pages = try await Task.detached(priority: .userInitiated) {
                    try indexes.map { number in
                        try Task.checkCancellation()
                        let result = index.read(item: item, page: item.kind == .pdf ? number : nil,
                                                location: nil, maximumCharacters: 48_000)
                        guard let text = result.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            throw WhiteboardFailure("第 \(number) 页没有读取到正文。请确认文件可用，或在阅读器选中文字后进入课堂。")
                        }
                        guard !result.isTruncated else { throw WhiteboardFailure("材料超过单次读取范围，请选中需要讲解的段落；不会静默截断。") }
                        return WhiteboardSource.Page(number: number, text: text)
                    }
                }.value
            }
            guard pages.reduce(0, { $0 + $1.text.count }) <= 64_000 else {
                throw WhiteboardFailure("本次材料超过 64,000 字，请减少页数。")
            }
            classroom.loadSource(.init(itemID: item.id, title: item.title, pages: pages))
        } catch { classroom.failure = error.localizedDescription }
    }

    private var sourcePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("原文依据").font(.headline)
                Text(classroom.session?.source.title ?? "").font(.callout).foregroundStyle(WeiBeiTheme.secondaryInk)
                ForEach(classroom.session?.source.pages ?? [], id: \.number) { page in
                    Button(item.kind == .pdf ? "第 \(page.number) 页 ↗" : "返回来源 ↗") {
                        store.selectedItemID = item.id
                        if item.kind == .pdf { store.requestReaderPDFPage(page.number - 1, recordsLocation: true) }
                        classroom.close(); dismiss()
                    }.buttonStyle(.borderless).foregroundStyle(WeiBeiTheme.cinnabar)
                    Text(page.text).font(.system(size: 13, design: .serif)).lineSpacing(5).textSelection(.enabled)
                }
                Divider()
                Text("这堂课要弄懂").font(.headline)
                ForEach(Array((classroom.session?.keyPoints ?? []).enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top) {
                        Image(systemName: classroom.session?.completedKeyPoints.contains(index) == true ? "checkmark.circle.fill" : "circle")
                        Text(point)
                    }.font(.callout).foregroundStyle(WeiBeiTheme.secondaryInk)
                }
            }.padding(18)
        }.background(WeiBeiTheme.paperRaised.opacity(0.45))
    }

    private var boardPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("课堂板书").font(.headline)
                Spacer()
                Text(classroom.settings.voice == .animalese ? "中文动物语" : classroom.settings.voice == .system ? "系统语音" : classroom.settings.voice == .cloud ? "云端语音" : "静音阅读")
                    .font(.caption).foregroundStyle(WeiBeiTheme.secondaryInk)
            }.padding(16)
            WhiteboardCanvasView(classroom: classroom, isDark: store.appearanceMode.isDark)
            if let narration = classroom.currentAction?.narration, !narration.isEmpty, classroom.settings.voice == .system || classroom.settings.voice == .cloud {
                ScrollView { Text(narration).font(.callout).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                    .frame(maxHeight: 100).background(WeiBeiTheme.paperRaised)
            }
        }
    }

    private var discussionPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("随时追问").font(.headline)
            Text("回答会直接显示在这里，结束后接着讲。").font(.caption).foregroundStyle(WeiBeiTheme.secondaryInk)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(classroom.session?.questions ?? []) { action in
                        WhiteboardQuestionView(classroom: classroom, action: action)
                            .onAppear { classroom.questionDisplayed(action.stepID) }
                        Divider()
                    }
                    ForEach(classroom.session?.discussions ?? []) { discussion in
                        Text(discussion.question).font(.headline).textSelection(.enabled)
                        if !discussion.text.isEmpty {
                            MarkdownPreviewView(markdown: discussion.text, appearanceMode: store.appearanceMode,
                                compact: true, preservesHeightAcrossMarkdownChanges: true)
                        }
                        if !discussion.completed {
                            Text(classroom.replying ? "正在回答…" : "回答尚未完成").font(.caption)
                        }
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField("这一步哪里没听懂？", text: $classroom.question, axis: .vertical)
                .lineLimit(2...6).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("发送") { classroom.ask() }
                    .disabled(classroom.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || classroom.replying || (classroom.session?.cursor ?? 0) < 2)
            }.buttonStyle(.borderless)
            Button(savedNote ? "已保存为新笔记" : "保存为学习笔记") {
                if let session = classroom.session {
                    savedNote = store.saveWhiteboardNote(session)
                }
            }.disabled(savedNote || classroom.busy)
        }.padding(16)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            if classroom.session != nil {
                Button { classroom.playing ? classroom.pause() : classroom.play() } label: {
                    Label(classroom.playing ? "暂停" : "继续", systemImage: classroom.playing ? "pause.fill" : "play.fill")
                }.disabled(classroom.replying || classroom.session?.completed == true)
                Button("重讲这一步") { classroom.replay() }
                if !classroom.generating && classroom.session?.generationComplete == false {
                    Button("继续编排") { classroom.resumeGeneration() }
                }
            }
            if classroom.busy {
                ProgressView().controlSize(.small)
                Button("停止生成") { classroom.cancel() }
            }
            Spacer()
            Text(classroom.status).font(.caption).foregroundStyle(WeiBeiTheme.secondaryInk).lineLimit(1)
        }.buttonStyle(.borderless).padding(16)
    }
}

private struct WhiteboardQuestionView: View {
    @ObservedObject var classroom: WhiteboardClassroom
    let action: WhiteboardAction
    @State private var answer = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("想一想 · " + (action.question ?? "")).font(.headline)
            if let submitted = classroom.session?.answers[action.stepID] {
                Text(submitted).font(.callout).foregroundStyle(WeiBeiTheme.cinnabar)
                Text("解析：" + (action.explanation ?? "")).font(.callout).textSelection(.enabled)
            } else {
                if action.mode == .open {
                    TextField("写下你的理解", text: $answer, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("提交回答") { classroom.answer(answer, to: action) }
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    ForEach(Array((action.options ?? []).enumerated()), id: \.offset) { index, option in
                        Button(option) { classroom.answer("\(option)（\(index == action.correctIndex ? "正确" : "再想一想")）", to: action, correct: index == action.correctIndex) }
                            .buttonStyle(.borderless)
                    }
                }
                Button("跳过") { classroom.answer("已跳过", to: action) }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WhiteboardSettingsView: View {
    @ObservedObject var classroom: WhiteboardClassroom
    @Environment(\.dismiss) private var dismiss
    @State private var speechKey = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("白板讲解语音").font(.title2)
            Text("中文动物语离线合成，适合轻松的课堂氛围；想听清楚每句话可选系统中文语音。").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SpeechSettingsFields(settings: $classroom.settings, speechKey: $speechKey)
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("保存") {
                    do {
                        try classroom.settings.save(speechKey: speechKey)
                        classroom.replay(); classroom.pause()
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 520, height: 570).background(WeiBeiTheme.paper)
    }

}
