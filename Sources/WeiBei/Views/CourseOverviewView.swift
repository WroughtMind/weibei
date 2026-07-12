import Foundation
import SwiftUI
import WeiBeiCore

struct CourseOverviewView: View {
    @EnvironmentObject private var store: WorkspaceStore
    let showUnlinkedNotes: () -> Void
    let showUnlinkedMaterials: () -> Void
    let showMaterialsWithoutReadingPosition: () -> Void
    let showRecords: (UUID?) -> Void

    private var summary: CourseWorkspaceSummary {
        store.courseWorkspaceSummary
    }

    private var recentLocations: [(StudyItem, StudyLocation)] {
        store.courseMaterials
            .compactMap { item in store.studyLocation(for: item.id).map { (item, $0) } }
            .sorted { $0.1.lastStudiedAt > $1.1.lastStudiedAt }
    }

    private var nextSteps: [String] {
        let memorySteps = store.activeCourseMemories
            .filter { $0.kind == .nextStep }
            .map(\.text)
        let flowSteps = store.activeStudySession?.flow.suggestedNext ?? []
        var seen = Set<String>()
        return (memorySteps + flowSteps).filter { seen.insert($0).inserted }.prefix(6).map { $0 }
    }

    private var unresolvedConfusions: [LearningMemoryEntry] {
        store.activeCourseMemories.filter { $0.kind == .confusion }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                overviewLead

                Rectangle()
                    .fill(WeiBeiTheme.hairline.opacity(0.72))
                    .frame(height: 1)
                    .padding(.vertical, 22)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .leading, spacing: 26) {
                            currentContextSection
                            continueSection
                            attentionSection
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 34)

                        Rectangle()
                            .fill(WeiBeiTheme.hairline.opacity(0.66))
                            .frame(width: 1)

                        VStack(alignment: .leading, spacing: 26) {
                            nextStepSection
                            recentDiscussionSection
                        }
                        .frame(width: 390, alignment: .leading)
                        .padding(.leading, 34)
                    }

                    VStack(alignment: .leading, spacing: 28) {
                        currentContextSection
                        continueSection
                        attentionSection
                        nextStepSection
                        recentDiscussionSection
                    }
                }
            }
            .frame(maxWidth: 1260, alignment: .leading)
            .padding(.horizontal, 42)
            .padding(.top, 34)
            .padding(.bottom, 54)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(WeiBeiTheme.paper)
    }

    private var overviewLead: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.ui("把这门课重新看清楚", "See the whole course clearly"))
                    .font(WeiBeiTypography.brandFont(language: store.interfaceLanguage, size: 25, weight: .semibold))
                Text(store.ui(
                    "打开只是当前动作，关联才是长期关系。",
                    "Opening is temporary. Linking creates a durable relationship."
                ))
                    .font(.system(size: 13))
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
            }

            Spacer()

            Text(store.ui(
                "\(summary.materialCount) 份资料 · \(summary.noteCount) 份笔记 · \(summary.studySessionCount) 次讨论",
                "\(summary.materialCount) materials · \(summary.noteCount) notes · \(summary.studySessionCount) discussions"
            ))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
        }
    }

    private var currentContextSection: some View {
        CourseDetailSection(title: store.ui("此刻", "Right now")) {
            VStack(spacing: 0) {
                CourseContextLine(
                    icon: "doc.text",
                    label: store.ui("正在阅读", "Reading"),
                    value: store.selectedMaterialItem.map(store.displayTitle) ?? store.ui("还没有打开资料", "No material open")
                )
                CourseHairline()
                CourseContextLine(
                    icon: "note.text",
                    label: store.ui("正在写", "Writing"),
                    value: store.activeNoteItem.map(store.displayTitle) ?? store.ui("还没有当前笔记", "No current note")
                )
            }
        }
    }

    @ViewBuilder
    private var continueSection: some View {
        if let latest = recentLocations.first {
            CourseDetailSection(title: store.ui("继续上次", "Continue")) {
                CourseActionRow(
                    icon: latest.0.kind.systemImage,
                    title: store.displayTitle(for: latest.0),
                    detail: "\(courseLocationLabel(latest.1, store: store)) · \(courseRelativeDate(latest.1.lastStudiedAt, language: store.interfaceLanguage))",
                    actionTitle: store.ui("继续阅读", "Continue reading")
                ) {
                    store.openCourseMaterial(latest.0.id)
                }
            }
        }
    }

    private var attentionSection: some View {
        CourseDetailSection(title: store.ui("待整理", "Needs attention")) {
            VStack(spacing: 0) {
                CourseAttentionRow(
                    title: store.ui("尚未建立资料关联的笔记", "Notes without material links"),
                    count: summary.unlinkedNoteCount,
                    detail: store.ui("明确哪些资料长期支撑这些笔记", "Choose which materials support these notes"),
                    action: showUnlinkedNotes
                )
                CourseHairline()
                CourseAttentionRow(
                    title: store.ui("还没有进入任何笔记的资料", "Materials not linked to any note"),
                    count: summary.unlinkedMaterialCount,
                    detail: store.ui("这不代表没有阅读，只代表尚未建立关系", "This means no relationship has been recorded"),
                    action: showUnlinkedMaterials
                )
                CourseHairline()
                CourseAttentionRow(
                    title: store.ui("尚无阅读位置的资料", "Materials without a reading position"),
                    count: store.courseMaterialsWithoutReadingPosition.count,
                    detail: store.ui("应用还没有记录到页码或章节", "No page or section has been recorded"),
                    action: showMaterialsWithoutReadingPosition
                )
                if summary.unresolvedConfusionCount > 0 {
                    CourseHairline()
                    CourseAttentionRow(
                        title: store.ui("还没有解决的困惑", "Unresolved questions"),
                        count: summary.unresolvedConfusionCount,
                        detail: unresolvedConfusions.first?.text ?? "",
                        action: { showRecords(unresolvedConfusions.first?.sessionID) }
                    )
                }
            }
        }
    }

    private var nextStepSection: some View {
        CourseDetailSection(title: store.ui("下一步", "Next steps")) {
            if nextSteps.isEmpty {
                CourseEmptyState(
                    title: store.ui("还没有明确的下一步", "No next step yet"),
                    detail: store.ui("继续阅读或对话后，课程台会把真实建议放在这里。", "Continue reading or chatting to build the next step."),
                    systemImage: "arrow.forward"
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(nextSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(WeiBeiTheme.cinnabar)
                                .frame(width: 18, alignment: .leading)
                            Text(step)
                                .font(.system(size: 13))
                                .foregroundStyle(WeiBeiTheme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var recentDiscussionSection: some View {
        CourseDetailSection(title: store.ui("最近讨论", "Recent discussions")) {
            if store.recentCourseSessions.isEmpty {
                CourseEmptyState(
                    title: store.ui("还没有课程讨论", "No course discussions yet"),
                    detail: store.ui("对话记录会按学习会话保存在这里。", "Conversations will appear here by learning session."),
                    systemImage: "bubble.left.and.text.bubble.right"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.recentCourseSessions.prefix(4).enumerated()), id: \.element.id) { index, session in
                        CourseActionRow(
                            icon: "bubble.left.and.text.bubble.right",
                            title: session.title,
                            detail: store.ui(
                                "\(session.messages.count) 条消息 · \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))",
                                "\(session.messages.count) messages · \(courseRelativeDate(session.updatedAt, language: store.interfaceLanguage))"
                            ),
                            actionTitle: store.ui("查看", "View")
                        ) {
                            showRecords(session.id)
                        }
                        if index < min(store.recentCourseSessions.count, 4) - 1 {
                            CourseHairline()
                        }
                    }
                }
            }
        }
    }
}
