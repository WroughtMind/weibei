import SwiftUI
import WeiBeiCore

struct WhiteboardSessionView: View {
    @ObservedObject var store: WorkspaceStore
    let item: StudyItem
    let selection: SelectionContext?
    @StateObject private var classroom: WhiteboardClassroom
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var firstPage: Int
    @State private var lastPage: Int
    @State private var selectionOnly: Bool
    @State private var showsSettings = false
    @State private var resumeAfterSettings = false
    @State private var sourceReadID = UUID()
    @State private var sourceBusy = false
    @State private var savedNote = false
    @State private var showsSource = false
    @State private var showsDiscussion = true

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
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        boardPane.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if showsDiscussion { Divider(); discussionPane.frame(width: min(360, max(280, geometry.size.width * 0.30))) }
                    }
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
            if classroom.session != nil { Divider(); controls }
        }
        .frame(minWidth: 800, idealWidth: 1160, minHeight: 600, idealHeight: 780)
        .background(WeiBeiTheme.paper)
        .foregroundStyle(WeiBeiTheme.ink)
        .sheet(isPresented: $showsSettings, onDismiss: {
            if resumeAfterSettings { classroom.play() }
            resumeAfterSettings = false
        }) { WhiteboardSettingsView(classroom: classroom) }
        .task(id: "\(firstPage)-\(lastPage)-\(selectionOnly)") { if classroom.session == nil { await loadSource() } }
        .onDisappear { classroom.close() }
        .onChange(of: classroom.session?.id) { _, _ in savedNote = false }
        .onChange(of: classroom.session?.discussions.count) { _, _ in showsDiscussion = true }
        .onChange(of: classroom.session?.presentedQuestionIDs.count) { _, _ in showsDiscussion = true }
        .onChange(of: classroom.status) { _, text in if !text.isEmpty { AccessibilityNotification.Announcement(text).post() } }
        .onChange(of: classroom.failure) { _, text in if let text { AccessibilityNotification.Announcement(text).post() } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis").foregroundStyle(WeiBeiTheme.cinnabar)
            Text("白板课堂").font(.headline)
            Text(classroom.session?.lesson.title ?? item.title).lineLimit(1).foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer()
            if classroom.session != nil {
                Button { showsSource.toggle() } label: { Label("原文", systemImage: "sidebar.leading") }
                    .accessibilityValue(showsSource ? "已展开" : "已收起")
                    .popover(isPresented: $showsSource) { sourcePane.frame(width: 320, height: 460) }
                Button { showsDiscussion.toggle() } label: { Label("问答", systemImage: "sidebar.trailing") }
                    .accessibilityValue(showsDiscussion ? "已展开" : "已收起")
                Menu {
                    Button(savedNote ? "已保存为新笔记" : "保存为学习笔记") {
                        if let session = classroom.session { savedNote = store.saveWhiteboardNote(session) }
                    }.disabled(savedNote || classroom.busy)
                    Button("重新讲解这份材料") { classroom.generate() }.disabled(classroom.busy)
                    if classroom.generating { Button("停止准备后续讲解") { classroom.stopGeneration() } }
                } label: { Image(systemName: "ellipsis") }.help("课堂操作").accessibilityLabel("课堂操作")
            }
            Menu {
                if classroom.history.isEmpty { Text("还没有保存的课堂") }
                ForEach(classroom.history) { saved in
                    Button("\(saved.lesson.title) · \(saved.completedKeyPoints.count)/\(saved.keyPoints.count) 个要点") { classroom.restore(saved) }
                }
            } label: { Label("历史", systemImage: "clock.arrow.circlepath") }
            .disabled(classroom.busy)
            Button { resumeAfterSettings = classroom.playing; classroom.pause(); showsSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .help("讲解语音设置").accessibilityLabel("讲解语音设置")
            Button("完成") { classroom.close(); dismiss() }
        }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
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
                if sourceBusy { HStack { ProgressView().controlSize(.small); Text("正在读取材料…").font(.callout) } }
                else if classroom.source == nil { Button("重新读取材料") { Task { await loadSource() } } }
                if let source = classroom.source {
                    Text("已读取：\(source.title) · \(source.pages.count) 个来源片段").font(.subheadline)
                    DisclosureGroup("查看材料内容") {
                        Text(source.pages.map(\.text).joined(separator: "\n"))
                            .font(.callout).textSelection(.enabled).foregroundStyle(WeiBeiTheme.secondaryInk)
                    }
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
        let ticket = UUID(); sourceReadID = ticket
        sourceBusy = true; classroom.source = nil; classroom.failure = nil
        defer { if sourceReadID == ticket { sourceBusy = false } }
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
            try Task.checkCancellation(); guard sourceReadID == ticket else { return }
            classroom.loadSource(.init(itemID: item.id, title: item.title, pages: pages))
        } catch is CancellationError {}
        catch { if sourceReadID == ticket { classroom.failure = error.localizedDescription } }
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
            }.padding(18)
        }.background(WeiBeiTheme.paperRaised.opacity(0.45))
    }

    private var boardPane: some View {
        VStack(spacing: 0) {
            WhiteboardCanvasTools(classroom: classroom).disabled(classroom.restoring)
            WhiteboardCanvasView(classroom: classroom, isDark: store.appearanceMode.isDark)
                .overlay(alignment: .topLeading) {
                    if classroom.restoring || (classroom.generating && classroom.session?.hasTeachingContent != true) {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(classroom.restoring ? "正在恢复板书…" : classroom.session?.keyPoints.isEmpty == true ? "正在整理讲解思路…" : "正在准备第一组讲解…").font(.callout)
                        }.padding(16).allowsHitTesting(false)
                    }
                }
            if let narration = classroom.currentAction?.narration, !narration.isEmpty, classroom.settings.voice == .system || classroom.settings.voice == .cloud {
                ScrollView { Text(narration).font(.callout).lineSpacing(4).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16) }
                    .frame(maxHeight: 100).background(WeiBeiTheme.paperRaised)
            }
        }
    }

    private var discussionPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("课堂问答").font(.headline)
                Spacer()
                if classroom.replying { Button("停止回答") { classroom.stopReply() }.font(.caption) }
            }
            ScrollViewReader { proxy in
              ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach((classroom.session?.questions ?? []).filter { classroom.session?.answers[$0.stepID] == nil }) { action in
                        WhiteboardQuestionView(classroom: classroom, action: action)
                        Divider()
                    }
                    ForEach((classroom.session?.discussions ?? []).reversed()) { discussion in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(discussion.correctionFor.flatMap { id in classroom.session?.questions.first { $0.stepID == id }?.question } ?? discussion.question).font(.headline).textSelection(.enabled)
                            if !discussion.text.isEmpty {
                                discussionText(discussion)
                            }
                            if !discussion.completed {
                                if classroom.replying { Label("正在回答…", systemImage: "ellipsis").font(.caption).foregroundStyle(WeiBeiTheme.secondaryInk) }
                                else { Button("继续回答") { classroom.retryReply(discussion) }.font(.caption) }
                            }
                            Divider()
                        }.frame(maxWidth: .infinity, alignment: .leading).id(discussion.id)
                    }
                    let answered = (classroom.session?.questions ?? []).filter { classroom.session?.answers[$0.stepID] != nil }
                    if !answered.isEmpty {
                        DisclosureGroup("已答自测 · \(answered.count)") {
                            ForEach(answered) { action in WhiteboardQuestionView(classroom: classroom, action: action).padding(.vertical, 8) }
                        }.font(.callout)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
              }
              .onChange(of: classroom.session?.discussions.last?.id) { _, id in
                  if let id { DispatchQueue.main.async { proxy.scrollTo(id, anchor: .top) } }
              }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("这一步哪里没听懂？", text: $classroom.question, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder)
                Button { classroom.ask() } label: { Image(systemName: "arrow.up").frame(width: 18, height: 22) }
                    .buttonStyle(.borderedProminent).tint(WeiBeiTheme.cinnabar)
                    .help("发送追问").accessibilityLabel("发送追问")
                    .disabled(classroom.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || classroom.replying || classroom.session?.hasTeachingContent != true)
            }
        }.padding(16)
    }

    @ViewBuilder private func discussionText(_ discussion: WhiteboardDiscussion) -> some View {
        // Reuse chat's native renderer: a short answer must not boot another editor WebView.
        #if targetEnvironment(macCatalyst)
        CatalystMessageMarkdown(markdown: discussion.text, fontSize: 14,
            appearanceMode: store.appearanceMode, openLink: { openURL($0) })
        #else
        NativeChatMarkdownView(markdown: discussion.text, messageID: discussion.id, fontSize: 14,
            isDark: store.appearanceMode.isDark, appearanceKey: store.appearanceMode.rawValue,
            onOpenURL: { openURL($0) })
        #endif
    }

    private var controls: some View {
        HStack(spacing: 16) {
            if classroom.session != nil {
                if classroom.session?.completed == true {
                    Text("已讲完").foregroundStyle(WeiBeiTheme.secondaryInk)
                } else {
                    Button { classroom.playing ? classroom.pause() : classroom.play() } label: {
                        Label(classroom.playing ? "暂停" : "继续", systemImage: classroom.playing ? "pause.fill" : "play.fill")
                    }.disabled(classroom.restoring || (classroom.replying && !classroom.playing))
                }
                Button(classroom.session?.completed == true ? "复习最后一步" : "重讲这一步") { classroom.replay() }
                    .disabled(classroom.replying || classroom.restoring)
            }
            if !classroom.playing && classroom.generating { ProgressView().controlSize(.small) }
            if let session = classroom.session, !session.keyPoints.isEmpty {
                Menu {
                    ForEach(Array(session.keyPoints.enumerated()), id: \.offset) { index, point in
                        Label(point, systemImage: session.completedKeyPoints.contains(index) ? "checkmark.circle.fill" : "circle")
                    }
                } label: { Text("\(session.completedKeyPoints.count)/\(session.keyPoints.count) 要点") }
                .help("查看这堂课的讲解提纲")
            }
            Spacer()
            Text(classroom.restoring ? "正在恢复板书…" : classroom.status)
                .font(.caption).foregroundStyle(WeiBeiTheme.secondaryInk).lineLimit(1)
        }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
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
                let correct = classroom.session?.studentEvents?.last { $0.questionID == action.stepID }?.correct
                Label(submitted, systemImage: correct == true ? "checkmark.circle" : correct == false ? "arrow.uturn.backward.circle" : "checkmark")
                    .font(.callout).foregroundStyle(correct == true ? Color.green : correct == false ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                Text("解析：" + (action.explanation ?? "")).font(.callout).textSelection(.enabled)
            } else {
                if action.mode == .open {
                    TextField("写下你的理解", text: $answer, axis: .vertical).textFieldStyle(.roundedBorder)
                    Button("提交回答") { classroom.answer(answer, to: action) }
                        .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    ForEach(Array((action.options ?? []).enumerated()), id: \.offset) { index, option in
                        Button { classroom.answer(option, to: action, correct: index == action.correctIndex) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(String(UnicodeScalar(65 + index)!)).font(.caption.monospaced()).foregroundStyle(WeiBeiTheme.secondaryInk)
                                Text(option).frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 5)
                        }.buttonStyle(.bordered).tint(WeiBeiTheme.ink)
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
    @State private var settings: WhiteboardMediaSettings
    init(classroom: WhiteboardClassroom) {
        self.classroom = classroom; _settings = State(initialValue: classroom.settings)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("白板讲解语音").font(.title2)
            Text("中文动物语离线合成，适合轻松的课堂氛围；想听清楚每句话可选系统中文语音。").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SpeechSettingsFields(settings: $settings, speechKey: $speechKey)
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    do {
                        try settings.save(speechKey: speechKey)
                        classroom.applyMediaSettings(settings)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 460, height: 500).background(WeiBeiTheme.paper).tint(WeiBeiTheme.cinnabar)
    }

}
