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
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return store.recentCourseSessions }
        return store.recentCourseSessions.filter { session in
            session.title.localizedCaseInsensitiveContains(cleaned)
                || session.summary.localizedCaseInsensitiveContains(cleaned)
                || session.messages.contains { $0.text.localizedCaseInsensitiveContains(cleaned) }
        }
    }

    private var groups: [SessionGroup] {
        let globalSessions = filteredSessions.filter {
            $0.courseID == nil && $0.scopeNeedsReview == false
        }
        let pendingSessions = filteredSessions.filter { $0.scopeNeedsReview == true }
        var result: [SessionGroup] = []
        if !globalSessions.isEmpty {
            result.append(
                SessionGroup(
                    id: "global",
                    course: nil,
                    title: store.ui("全局", "Global"),
                    sessions: globalSessions
                )
            )
        }
        result += store.courses.compactMap { course in
            let sessions = filteredSessions.filter {
                $0.courseID == course.id && $0.scopeNeedsReview == false
            }
            guard !sessions.isEmpty else { return nil }
            return SessionGroup(
                id: course.id.uuidString,
                course: course,
                title: course.title,
                sessions: sessions
            )
        }
        if !pendingSessions.isEmpty {
            result.append(
                SessionGroup(
                    id: "pending",
                    course: nil,
                    title: store.ui("待归类", "Needs Course"),
                    sessions: pendingSessions
                )
            )
        }
        return result
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                CourseEmptyState(
                    title: store.ui("还没有学习记录", "No learning records yet"),
                    detail: store.ui(
                        "有真实对话的会话会出现在这里，并按课程归类。",
                        "Sessions with messages appear here, grouped by course."
                    ),
                    systemImage: "bubble.left.and.text.bubble.right"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            groupHeader(group)
                            ForEach(group.sessions) { session in
                                CourseWorkspaceRow(
                                    icon: "bubble.left.and.text.bubble.right",
                                    title: session.title,
                                    detail: store.ui(
                                        "\(session.scopeNeedsReview == true ? "待归类 · " : "")\(session.messages.count) 条消息 · \(coursePhaseLabel(session.flow.phase, store: store))",
                                        "\(session.scopeNeedsReview == true ? "Needs course · " : "")\(session.messages.count) messages · \(coursePhaseLabel(session.flow.phase, store: store))"
                                    ),
                                    status: courseRelativeDate(session.updatedAt, language: store.interfaceLanguage),
                                    selected: session.id == selectedSessionID
                                ) {
                                    selectedSessionID = session.id
                                    store.continueCourseSession(
                                        session.id,
                                        expectedCourseID: session.courseID,
                                        expectedScopeNeedsReview: session.scopeNeedsReview == true
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
                    "同色标签表示同一课程 · 点击一行继续对话",
                    "Matching tags share a course · click a row to continue"
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
