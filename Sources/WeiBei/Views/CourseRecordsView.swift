import Foundation
import SwiftUI
import WeiBeiCore

struct CourseRecordsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let search: String
    @Binding var selectedSessionID: UUID?
    let isCompact: Bool

    private var sessions: [StudySession] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return store.recentCourseSessions }
        return store.recentCourseSessions.filter { session in
            session.title.localizedCaseInsensitiveContains(cleaned)
                || session.summary.localizedCaseInsensitiveContains(cleaned)
                || session.messages.contains { $0.text.localizedCaseInsensitiveContains(cleaned) }
        }
    }

    private var resolvedSession: StudySession? {
        if let selectedSessionID,
           let session = sessions.first(where: { $0.id == selectedSessionID }) {
            return session
        }
        return sessions.first
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                CourseEmptyState(
                    title: store.ui("还没有学习记录", "No learning records yet"),
                    detail: store.ui("发生过真实对话的学习会话会保存在这里；空白会话不计入。", "Learning sessions with real messages appear here. Empty sessions are not counted."),
                    systemImage: "bubble.left.and.text.bubble.right"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else if isCompact {
                VStack(spacing: 0) {
                    sessionList
                    CourseHairline()
                    CourseSessionDetail(session: resolvedSession)
                        .frame(minHeight: 400)
                }
            } else {
                HStack(spacing: 0) {
                    sessionList
                        .frame(width: 390)
                    Rectangle()
                        .fill(WeiBeiTheme.hairline.opacity(0.72))
                        .frame(width: 1)
                    CourseSessionDetail(session: resolvedSession)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if selectedSessionID == nil {
                selectedSessionID = sessions.first?.id
            }
        }
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sessions) { session in
                    CourseWorkspaceRow(
                        icon: "bubble.left.and.text.bubble.right",
                        title: session.title,
                        detail: store.ui(
                            "\(session.messages.count) 条消息 · \(coursePhaseLabel(session.flow.phase, store: store))",
                            "\(session.messages.count) messages · \(coursePhaseLabel(session.flow.phase, store: store))"
                        ),
                        status: courseRelativeDate(session.updatedAt, language: store.interfaceLanguage),
                        selected: session.id == resolvedSession?.id
                    ) {
                        selectedSessionID = session.id
                    }
                    CourseHairline()
                }
            }
            .padding(.vertical, 6)
        }
        .background(WeiBeiTheme.paperRaised.opacity(0.22))
    }
}
struct CourseSessionDetail: View {
    @EnvironmentObject private var store: WorkspaceStore
    let session: StudySession?

    var body: some View {
        if let session {
            VStack(spacing: 0) {
                CourseRelationDetailHeader(
                    mark: "SESSION",
                    title: session.title,
                    detail: store.ui(
                        "\(session.messages.count) 条消息 · 更新于 \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))",
                        "\(session.messages.count) messages · updated \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))"
                    ),
                    openTitle: store.ui("继续对话", "Continue chat"),
                    open: { store.continueCourseSession(session.id) }
                )

                CourseHairline()

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        CourseDetailSection(title: store.ui("会话摘要", "Session summary")) {
                            Text(session.summary.isEmpty
                                ? store.ui("这次讨论还没有生成摘要。", "This discussion does not have a summary yet.")
                                : session.summary
                            )
                                .font(.system(size: 13))
                                .foregroundStyle(session.summary.isEmpty ? WeiBeiTheme.tertiaryInk : WeiBeiTheme.ink)
                                .lineSpacing(4)
                                .textSelection(.enabled)
                        }

                        if !session.focusItemIDs.isEmpty {
                            CourseDetailSection(title: store.ui("会话中出现过", "Referenced in this session")) {
                                VStack(spacing: 0) {
                                    ForEach(session.focusItemIDs.compactMap(store.item(withID:)), id: \.id) { item in
                                        CourseContextLine(
                                            icon: item.kind.systemImage,
                                            label: item.isNotebookNote ? store.ui("笔记", "Note") : store.ui("资料", "Material"),
                                            value: store.displayTitle(for: item)
                                        )
                                        CourseHairline()
                                    }
                                }
                            }
                        }

                        if !session.flow.suggestedNext.isEmpty {
                            CourseDetailSection(title: store.ui("建议下一步", "Suggested next")) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(session.flow.suggestedNext.enumerated()), id: \.offset) { index, item in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text("\(index + 1)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(WeiBeiTheme.cinnabar)
                                                .frame(width: 18, alignment: .leading)
                                            Text(item)
                                                .font(.system(size: 13))
                                        }
                                    }
                                }
                            }
                        }

                        CourseDetailSection(title: store.ui("最近消息", "Recent messages")) {
                            VStack(spacing: 0) {
                                ForEach(Array(session.messages.suffix(8))) { message in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(message.role == .user ? store.ui("我", "Me") : store.ui("魏碑", "WeiBei"))
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(message.role == .user ? WeiBeiTheme.cinnabar : WeiBeiTheme.secondaryInk)
                                            Spacer()
                                            Text(courseRelativeDate(message.createdAt, language: store.interfaceLanguage))
                                                .font(.system(size: 10))
                                                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                                        }
                                        Text(message.text)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(WeiBeiTheme.ink)
                                            .lineLimit(5)
                                            .lineSpacing(3)
                                            .textSelection(.enabled)
                                    }
                                    .padding(.vertical, 12)
                                    CourseHairline()
                                }
                            }
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: 840, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        } else {
            CourseEmptyState(
                title: store.ui("选择一条学习记录", "Select a learning record"),
                detail: store.ui("这里会显示真实摘要、相关资料和下一步建议。", "See the real summary, referenced items, and next steps here."),
                systemImage: "bubble.left.and.text.bubble.right"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
