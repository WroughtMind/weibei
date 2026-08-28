import SwiftUI
import WeiBeiCore

/// 回答末尾的学习记忆更新提示：药丸直接展示已记住内容的概括，
/// 展开后逐条列出回执携带的每条记忆内容，而不是只显示计数。
struct AgentReplyMemoryUpdateTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    let message: AgentMessage
    let update: AgentReplyMemoryUpdate
    @State private var expanded = false

    private var scope: LearningMemoryScope? {
        message.origin?.courseID.map(LearningMemoryScope.course)
    }

    private var courseID: UUID? {
        guard let courseID = message.origin?.courseID,
              store.course(withID: courseID) != nil else {
            return nil
        }
        return courseID
    }

    /// 逐条展示项：优先用回执里的 texts；旧消息没有 texts 时回退到 store 中的修订记录。
    private var items: [(kind: LearningMemoryKind?, text: String)] {
        if update.texts.count == update.memoryIDs.count {
            let entries = scope.map { store.learningMemoryEntries(in: $0) } ?? []
            return zip(update.memoryIDs, update.texts).map { id, text in
                (entries.first(where: { $0.id == id })?.kind, text)
            }
        }
        guard let scope,
              let revisions = update.revisions(
                  for: message.id,
                  in: store.learningMemoryEntries(in: scope)
              ) else {
            return []
        }
        return revisions.map { (Optional($0.kind), $0.text) }
    }

    private var summaryText: String {
        let fallback = update.texts.prefix(3).joined(separator: "；")
        let text = update.summary.isEmpty ? fallback : update.summary
        return text.isEmpty
            ? store.ui("已更新学习记忆", "Learning memory updated")
            : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : WeiBeiMotion.micro) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .accessibilityHidden(true)
                    Text(summaryText)
                        .weiBeiText(10.5, weight: .semibold)
                        .foregroundStyle(WeiBeiTheme.cinnabar)
                        .lineLimit(1)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .weiBeiText(9.5, weight: .bold)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background {
                    Capsule()
                        .fill(WeiBeiTheme.cinnabarSoft.opacity(0.34))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(WeiBeiTheme.cinnabar.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(store.ui(
                expanded ? "已展开" : "已收起",
                expanded ? "Expanded" : "Collapsed"
            )))
            .accessibilityIdentifier("agent-memory-update-tag")

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            if let kind = item.kind {
                                Text(store.learningMemoryKindLabel(kind))
                                    .weiBeiText(10.5, weight: .semibold)
                                    .foregroundStyle(WeiBeiTheme.cinnabar)
                                    .fixedSize()
                            }
                            Text(item.text)
                                .weiBeiText(10.5)
                                .foregroundStyle(WeiBeiTheme.secondaryInk)
                                .lineLimit(2)
                        }
                    }

                    if let courseID {
                        Button(store.ui("查看课程记忆", "View Course Memory")) {
                            store.presentCourseWorkspace(.memory, courseID: courseID)
                        }
                        .buttonStyle(WeiBeiTextActionButtonStyle())
                        .accessibilityIdentifier("agent-memory-update-view-all")
                    }
                }
                .padding(.leading, 9)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(WeiBeiTheme.cinnabar.opacity(0.28))
                        .frame(width: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
