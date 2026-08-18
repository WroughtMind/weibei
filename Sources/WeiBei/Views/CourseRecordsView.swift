import Foundation
import SwiftUI
import WeiBeiCore

enum CourseConversationSection: String, CaseIterable, Identifiable {
    case chats
    case memory

    var id: String { rawValue }

    func label(language: WeiBeiInterfaceLanguage, count: Int) -> String {
        switch self {
        case .chats:
            return language.text("对话 \(count)", "Chats \(count)")
        case .memory:
            return language.text("课程记忆 \(count)", "Course Memory \(count)")
        }
    }
}

/// Course-associated Chats and course-scoped Memory are intentionally shown as
/// two different sections. A Chat is global history that can touch more than
/// one course; Memory is editable state scoped to this course.
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

    private var courseSessions: [StudySession] {
        guard let courseID = store.courseWorkspaceCourseID else { return [] }
        return store.sessionsTouchingCourse(courseID)
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private var filteredSessions: [StudySession] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return courseSessions }
        return courseSessions.filter { session in
            session.title.localizedCaseInsensitiveContains(cleaned)
                || session.summary.localizedCaseInsensitiveContains(cleaned)
                || session.messages.contains {
                    $0.text.localizedCaseInsensitiveContains(cleaned)
                }
        }
    }

    private var groups: [SessionGroup] {
        guard let courseID = store.courseWorkspaceCourseID,
              let course = store.course(withID: courseID),
              !filteredSessions.isEmpty else {
            return []
        }
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

    private var memoryCount: Int {
        memoryScope.map { store.learningMemoryEntries(in: $0).count } ?? 0
    }

    private var cleanedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            chatsContent
        }
        .background(WeiBeiTheme.paper)
        .onAppear(perform: normalizeSelectedSession)
        .onChange(of: store.courseWorkspaceCourseID) { _, _ in
            selectedSessionID = nil
            normalizeSelectedSession()
        }
        .onChange(of: courseSessions.map(\.id)) { _, _ in
            normalizeSelectedSession()
        }
    }

    @ViewBuilder
    private var chatsContent: some View {
        if store.courseWorkspaceCourseID == nil {
            CourseEmptyState(
                title: store.ui("先选择一门课程", "Choose a course first"),
                detail: store.ui(
                    "选择课程后，这里会显示与它有关的全局对话。",
                    "Choose a course to see the global Chats associated with it."
                ),
                systemImage: "bubble.left.and.text.bubble.right",
                alignment: .center
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        } else if filteredSessions.isEmpty {
            CourseEmptyState(
                title: cleanedSearch.isEmpty
                    ? store.ui("这门课还没有关联对话", "No Chats associated with this course")
                    : store.ui("没有匹配的对话", "No matching Chats"),
                detail: cleanedSearch.isEmpty
                    ? store.ui(
                        "从课程概览提问或开始新对话后，对话会出现在这里。对话本身仍保存在全局。",
                        "Ask from the course overview or start a new Chat. The Chat itself remains global."
                    )
                    : store.ui("换一个搜索词再试。", "Try another search term."),
                systemImage: "bubble.left.and.text.bubble.right",
                alignment: .center
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredSessions) { session in
                        CourseWorkspaceRow(
                            icon: "bubble.left.and.text.bubble.right",
                            title: session.title,
                            detail: sessionDetail(session),
                            status: courseRelativeDate(
                                session.updatedAt,
                                language: store.interfaceLanguage
                            ),
                            selected: session.id == selectedSessionID
                        ) {
                            selectedSessionID = session.id
                            store.continueCourseSession(
                                session.id,
                                expectedCourseID: store.courseWorkspaceCourseID,
                                expectedScopeNeedsReview: false
                            )
                        }
                        .background(
                            WeiBeiTheme.paperInset.opacity(
                                session.id == selectedSessionID ? 0.42 : 0.16
                            ),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func sessionDetail(_ session: StudySession) -> String {
        let summary = session.summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lastMessage = session.messages.last?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let preview = summary.isEmpty ? lastMessage : summary
        let metadata = store.ui(
            "\(session.messages.count) 条消息 · \(coursePhaseLabel(session.flow.phase, store: store))",
            "\(session.messages.count) messages · \(coursePhaseLabel(session.flow.phase, store: store))"
        )
        guard !preview.isEmpty else { return metadata }
        return "\(preview.replacingOccurrences(of: "\n", with: " ")) · \(metadata)"
    }

    private func normalizeSelectedSession() {
        let sessionIDs = Set(courseSessions.map(\.id))
        if selectedSessionID.map({ sessionIDs.contains($0) }) != true {
            selectedSessionID = courseSessions.first?.id
        }
    }
}

struct CourseMemoryWorkspaceView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let search: String

    var body: some View {
        Group {
            if let courseID = store.courseWorkspaceCourseID {
                LearningMemoryListSection(
                    scope: .course(courseID),
                    title: store.ui("课程记忆", "Course Memory"),
                    search: search,
                    centerEmptyState: true
                )
            } else {
                CourseEmptyState(
                    title: store.ui("先选择一门课程", "Choose a course first"),
                    detail: store.ui(
                        "课程记忆按当前课程单独保存。",
                        "Course Memory is stored separately for each course."
                    ),
                    systemImage: "brain.head.profile",
                    alignment: .center
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeiBeiTheme.paper)
    }
}

struct LearningMemoryListSection: View {
    @EnvironmentObject private var store: WorkspaceStore
    let scope: LearningMemoryScope
    let title: String
    var search = ""
    var centerEmptyState = false
    @State private var editingMemory: LearningMemoryEntry?
    @State private var memoryPendingDeletion: LearningMemoryEntry?

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
        VStack(alignment: memories.isEmpty && centerEmptyState ? .center : .leading, spacing: 0) {
            if !(memories.isEmpty && centerEmptyState) {
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
            }

            if memories.isEmpty, !centerEmptyState {
                Text(search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? store.ui("还没有形成学习记忆。", "No learning memory yet.")
                    : store.ui("没有匹配的学习记忆。", "No matching learning memory."))
                    .font(.system(size: 12))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else if memories.isEmpty {
                CourseEmptyState(
                    title: search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? store.ui("还没有课程记忆", "No course memory yet")
                        : store.ui("没有匹配的课程记忆", "No matching course memory"),
                    detail: search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? store.ui("学习过程中留下的要点会出现在这里。", "Highlights from study will appear here.")
                        : store.ui("换一个搜索词再试。", "Try another search term."),
                    systemImage: "brain.head.profile",
                    alignment: .center
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                ForEach(memories) { memory in
                    CourseHairline()
                    memoryRow(memory)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: centerEmptyState ? .infinity : nil)
        .sheet(item: $editingMemory) { memory in
            LearningMemoryEditSheet(scope: scope, memory: memory)
                .environmentObject(store)
        }
        .confirmationDialog(
            store.ui("删除这条学习记忆？", "Delete this learning memory?"),
            isPresented: Binding(
                get: { memoryPendingDeletion != nil },
                set: { if !$0 { memoryPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: memoryPendingDeletion
        ) { memory in
            Button(store.ui("删除记忆", "Delete Memory"), role: .destructive) {
                _ = store.deleteLearningMemory(memory.id, in: scope)
                memoryPendingDeletion = nil
            }
            Button(store.ui("取消", "Cancel"), role: .cancel) {
                memoryPendingDeletion = nil
            }
        } message: { _ in
            Text(store.ui(
                "只删除这一条记忆，其他学习记录不受影响。",
                "Only this memory will be deleted. Other learning records are unchanged."
            ))
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

            Button(role: .destructive) {
                memoryPendingDeletion = memory
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(WeiBeiIconButtonStyle(size: 24))
            .help(store.ui("删除记忆", "Delete Memory"))
            .accessibilityLabel(store.ui("删除记忆", "Delete Memory"))
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
