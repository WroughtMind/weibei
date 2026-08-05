import Foundation
import SwiftUI
import WeiBeiCore

/// Learning-session list grouped by course (color tag per course).
struct CourseRecordsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let search: String
    @Binding var selectedSessionID: UUID?
    let isCompact: Bool

    private struct SessionGroup: Identifiable {
        let id: String
        let course: Course?
        let title: String
        let sessions: [StudySession]
    }

    private var filteredSessions: [StudySession] {
        guard let courseID = store.courseWorkspaceCourseID else { return [] }
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessions = store.sessionsTouchingCourse(courseID)
        guard !cleaned.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(cleaned)
                || session.summary.localizedCaseInsensitiveContains(cleaned)
                || session.messages.contains { $0.text.localizedCaseInsensitiveContains(cleaned) }
        }
    }

    private var groups: [SessionGroup] {
        guard let courseID = store.courseWorkspaceCourseID,
              let course = store.course(withID: courseID),
              !filteredSessions.isEmpty else { return [] }
        return [
            SessionGroup(
                id: course.id.uuidString,
                course: course,
                title: course.title,
                sessions: filteredSessions
            ),
        ]
    }

    private var memoryScope: LearningMemoryScope? {
        store.courseWorkspaceCourseID.map(LearningMemoryScope.course)
    }

    private var hasMemories: Bool {
        memoryScope.map { !store.learningMemoryEntries(in: $0).isEmpty } ?? false
    }

    var body: some View {
        Group {
            if groups.isEmpty && !hasMemories {
                CourseEmptyState(
                    title: store.ui("还没有学习记录", "No learning records yet"),
                    detail: store.ui(
                        "本课的学习记忆和真实对话会出现在这里。",
                        "Learning memories and real Chats for this course will appear here."
                    ),
                    systemImage: "bubble.left.and.text.bubble.right"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let memoryScope {
                            LearningMemoryListSection(
                                scope: memoryScope,
                                title: store.ui("本课记忆", "Course Memory"),
                                search: search
                            )
                            if !groups.isEmpty {
                                CourseHairline()
                            }
                        }
                        ForEach(groups) { group in
                            groupHeader(group)
                            ForEach(group.sessions) { session in
                                CourseWorkspaceRow(
                                    icon: "bubble.left.and.text.bubble.right",
                                    title: session.title,
                                    detail: store.ui(
                                        "\(session.messages.count) 条消息 · \(coursePhaseLabel(session.flow.phase, store: store))",
                                        "\(session.messages.count) messages · \(coursePhaseLabel(session.flow.phase, store: store))"
                                    ),
                                    status: courseRelativeDate(session.updatedAt, language: store.interfaceLanguage),
                                    selected: session.id == selectedSessionID
                                ) {
                                    selectedSessionID = session.id
                                    store.continueCourseSession(
                                        session.id,
                                        expectedCourseID: store.courseWorkspaceCourseID,
                                        expectedScopeNeedsReview: false
                                    )
                                }
                                CourseHairline()
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(WeiBeiTheme.paperRaised.opacity(0.18))
            }
        }
        .overlay(alignment: .bottom) {
            if !groups.isEmpty {
                Text(store.ui(
                    "点击一行继续本课对话",
                    "Click a row to continue this course Chat"
                ))
                .font(.system(size: 11))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(WeiBeiTheme.paper.opacity(0.92))
            }
        }
        .onAppear {
            if selectedSessionID == nil {
                selectedSessionID = groups.first?.sessions.first?.id
            }
        }
    }

    private func groupHeader(_ group: SessionGroup) -> some View {
        let accent = group.course.map { courseWorkspaceAccent(colorIndex: $0.colorIndex) } ?? WeiBeiTheme.tertiaryInk
        return HStack(spacing: 8) {
            Capsule()
                .fill(accent)
                .frame(width: 8, height: 8)
            Text(group.title)
                .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 13, weight: .semibold))
                .foregroundStyle(WeiBeiTheme.ink)
            Text(store.ui("\(group.sessions.count) 段", "\(group.sessions.count)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WeiBeiTheme.secondaryInk)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(accent.opacity(0.06))
    }
}

struct LearningMemoryListSection: View {
    @EnvironmentObject private var store: WorkspaceStore
    let scope: LearningMemoryScope
    let title: String
    var search = ""
    @State private var editingMemory: LearningMemoryEntry?

    private var memories: [LearningMemoryEntry] {
        let all = store.orderedLearningMemoryEntries(in: scope)
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return all }
        return all.filter { memory in
            store.learningMemoryKindLabel(memory.kind)
                .localizedCaseInsensitiveContains(cleaned)
                || memory.text.localizedCaseInsensitiveContains(cleaned)
                || memory.evidence.localizedCaseInsensitiveContains(cleaned)
                || memorySource(memory).localizedCaseInsensitiveContains(cleaned)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                Text(title)
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 14, weight: .semibold))
                Spacer()
                Text(store.ui("\(memories.count) 条", "\(memories.count)"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if memories.isEmpty {
                Text(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? store.ui("还没有形成学习记忆。", "No learning memory yet.")
                    : store.ui("没有匹配的学习记忆。", "No matching learning memory."))
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else {
                ForEach(memories) { memory in
                    CourseHairline()
                    memoryRow(memory)
                }
            }
        }
        .sheet(item: $editingMemory) { memory in
            LearningMemoryEditSheet(scope: scope, memory: memory)
                .environmentObject(store)
        }
    }

    private func memoryRow(_ memory: LearningMemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                editingMemory = memory
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(store.learningMemoryKindLabel(memory.kind))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(WeiBeiTheme.cinnabar)
                        if memory.status == .resolved {
                            Text(store.ui("已解决", "Resolved"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        }
                    }
                    Text(memory.text)
                        .font(.system(size: 13))
                        .foregroundStyle(WeiBeiTheme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(memorySource(memory))
                        .font(.system(size: 10.5))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if memory.status == .resolved {
                    store.restoreLearningMemory(memory.id, in: scope)
                } else {
                    store.resolveLearningMemory(memory.id, in: scope)
                }
            } label: {
                Image(systemName: memory.status == .resolved ? "arrow.uturn.backward" : "checkmark.circle")
            }
            .buttonStyle(WeiBeiIconButtonStyle(active: memory.status == .resolved, size: 24))
            .help(store.ui(memory.status == .resolved ? "恢复" : "标为已解决", memory.status == .resolved ? "Restore" : "Resolve"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func memorySource(_ memory: LearningMemoryEntry) -> String {
        let revisionCount = memory.revisions?.count ?? 0
        if let sessionID = memory.sessionID,
           let session = store.studySessions.first(where: { $0.id == sessionID }) {
            return store.ui(
                "来自“\(session.title)” · \(revisionCount) 次修订",
                "From \"\(session.title)\" · \(revisionCount) revisions"
            )
        }
        return store.ui("用户维护 · \(revisionCount) 次修订", "User maintained · \(revisionCount) revisions")
    }
}

private struct LearningMemoryEditSheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let scope: LearningMemoryScope
    let memory: LearningMemoryEntry
    @State private var kind: LearningMemoryKind
    @State private var text: String

    init(scope: LearningMemoryScope, memory: LearningMemoryEntry) {
        self.scope = scope
        self.memory = memory
        _kind = State(initialValue: memory.kind)
        _text = State(initialValue: memory.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.ui("修改学习记忆", "Edit Learning Memory"))
                .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 19, weight: .semibold))

            Picker(store.ui("类型", "Kind"), selection: $kind) {
                ForEach(LearningMemoryKind.allCases, id: \.self) { kind in
                    Text(store.learningMemoryKindLabel(kind)).tag(kind)
                }
            }

            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(minHeight: 110)
                .padding(8)
                .background(WeiBeiTheme.paperInset.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(WeiBeiTheme.hairline, lineWidth: 1)
                }

            Text(store.ui(
                "\(text.count) / 500 字",
                "\(text.count) / 500 characters"
            ))
            .font(.system(size: 10.5))
            .foregroundStyle(text.count > 500 ? WeiBeiTheme.cinnabar : WeiBeiTheme.tertiaryInk)
            .frame(maxWidth: .infinity, alignment: .trailing)

            HStack {
                Spacer()
                Button(store.ui("取消", "Cancel")) {
                    dismiss()
                }
                Button(store.ui("保存修改", "Save")) {
                    if store.updateLearningMemory(memory.id, in: scope, kind: kind, text: text) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || text.trimmingCharacters(in: .whitespacesAndNewlines).count > 500
                )
            }
        }
        .padding(22)
        .frame(width: 460)
    }
}

struct GlobalLearningMemorySheet: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.ui("全局记忆", "Global Memory"))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 19, weight: .semibold))
                Spacer()
                TextField(
                    store.ui("搜索全局记忆", "Search global memory"),
                    text: $search
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                if let saveError = store.workspaceSaveError {
                    Button(action: { _ = store.retryWorkspaceSave() }) {
                        Label(
                            store.ui("保存失败，点此重试", "Save failed, retry"),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                    }
                    .buttonStyle(.plain)
                    .help(saveError)
                }
                Button(store.ui("完成", "Done")) {
                    dismiss()
                }
            }
            .padding(18)

            CourseHairline()

            ScrollView {
                LearningMemoryListSection(
                    scope: .global,
                    title: store.ui("所有对话共用", "Shared by All Chats"),
                    search: search
                )
            }
        }
        .frame(width: 560, height: 500)
        .background(WeiBeiTheme.paper)
    }
}
