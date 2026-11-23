import SwiftUI
import WeiBeiCore

struct AgentReplyProfileUpdateTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    let update: AgentReplyProfileUpdate
    @State private var expanded = false

    /// 收起态直接展示已记录内容的概括，与学习记忆标签一致，不显示计数。
    private var summaryText: String {
        let text = update.texts.prefix(3).joined(separator: "；")
        return text.isEmpty
            ? store.ui("已记录掌握状态", "Mastery noted")
            : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(WeiBeiMotion.visibility(!expanded)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle")
                        .accessibilityHidden(true)
                    Text(summaryText)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .weiBeiText(9.5, weight: .bold)
                        .accessibilityHidden(true)
                }
                .weiBeiText(10.5, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.accent)
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background {
                    Capsule()
                        .fill(WeiBeiTheme.accentSoft.opacity(0.34))
                }
                .overlay {
                    Capsule()
                        .strokeBorder(WeiBeiTheme.accent.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agent-profile-update-tag")

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(update.texts.enumerated()), id: \.offset) { _, text in
                        Text(text)
                            .weiBeiText(10.5)
                            .foregroundStyle(WeiBeiTheme.secondaryInk)
                            .lineLimit(2)
                    }
                }
                .padding(.leading, 9)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(WeiBeiTheme.accent.opacity(0.28))
                        .frame(width: 1)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .weiBeiFadeWhenReducingMotion(expanded)
    }
}

