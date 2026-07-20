import Foundation
import SwiftUI
import WeiBeiCore

/// Lightweight learning-session list for the course workspace.
/// Heavy dual-pane history browsing lives in the chat hover catalog instead —
/// this page is a simple jump board into continuing conversations.
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

    var body: some View {
        Group {
            if sessions.isEmpty {
                CourseEmptyState(
                    title: store.ui("还没有学习记录", "No learning records yet"),
                    detail: store.ui(
                        "有真实对话的会话会出现在这里。日常切换请用对话顶栏 Hover「目录」。",
                        "Sessions with real messages appear here. Day-to-day switching uses the chat hover Catalog."
                    ),
                    systemImage: "bubble.left.and.text.bubble.right"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)
            } else {
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
                                selected: session.id == selectedSessionID
                            ) {
                                selectedSessionID = session.id
                                store.continueCourseSession(session.id)
                            }
                            CourseHairline()
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(WeiBeiTheme.paperRaised.opacity(0.18))
            }
        }
        .overlay(alignment: .bottom) {
            if !sessions.isEmpty {
                Text(store.ui(
                    "点击一行即可继续对话 · 完整目录也在对话顶栏 Hover 菜单中",
                    "Click a row to continue · full catalog also lives in the chat hover menu"
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
                selectedSessionID = sessions.first?.id
            }
        }
    }
}
