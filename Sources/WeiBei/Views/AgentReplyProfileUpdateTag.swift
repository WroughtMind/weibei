import SwiftUI

struct AgentReplyProfileUpdateTag: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.weibeiReduceMotion) private var reduceMotion
    let update: AgentReplyProfileUpdate
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : WeiBeiMotion.micro) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.book.closed")
                        .accessibilityHidden(true)
                    Text(store.ui(
                        "已更新课程知识档案 · \(update.entryIDs.count) 项",
                        "Course profile updated · \(update.entryIDs.count)"
                    ))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .weiBeiText(9.5, weight: .bold)
                        .accessibilityHidden(true)
                }
                .weiBeiText(10.5, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.cinnabar)
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
                        .fill(WeiBeiTheme.cinnabar.opacity(0.28))
                        .frame(width: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

