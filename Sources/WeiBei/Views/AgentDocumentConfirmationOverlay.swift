import SwiftUI

/// Agent 创建文稿的写盘确认浮层。
/// 视觉沿用笔记提案卡：环境面平涂遮罩，操作件（确认）为亮药丸浮起的卡片。
struct AgentDocumentConfirmationOverlay: View {
    @EnvironmentObject private var store: WorkspaceStore
    @ObservedObject private var center = AgentDocumentConfirmationCenter.shared

    var body: some View {
        Group {
            if let request = center.pendingRequest {
                ZStack {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture { center.cancel() }

                    confirmationCard(request)
                        .padding(.horizontal, 28)
                        .transition(
                            .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
                        )
                }
                .zIndex(130)
                .transition(.opacity)
            }
        }
        .animation(WeiBeiMotion.panel, value: center.pendingRequest?.id)
    }

    private func confirmationCard(_ request: AgentDocumentConfirmationCenter.PendingRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(store.ui(
                    "Agent 想创建一篇文稿",
                    "Agent wants to create a document"
                ))
                .weiBeiText(13, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
            } icon: {
                Image(systemName: "doc.badge.plus")
                    .foregroundStyle(WeiBeiTheme.cinnabar)
            }

            Text(request.title)
                .weiBeiText(12, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
                .lineLimit(2)

            Text(request.summary)
                .weiBeiText(10.5)
                .foregroundStyle(WeiBeiTheme.secondaryInk)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(store.ui(
                "确认后才会写入工作区；取消则不创建，并告知 Agent 未创建。",
                "Nothing is written until you approve. Canceling tells the Agent it was not created."
            ))
            .weiBeiText(9.5)
            .foregroundStyle(WeiBeiTheme.tertiaryInk)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(store.ui("创建文稿", "Create Document")) {
                    center.confirm()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: true))

                Button(store.ui("取消", "Cancel")) {
                    center.cancel()
                }
                .buttonStyle(WeiBeiTextActionButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: 380, alignment: .leading)
        .background {
            WeiBeiEtchedBackdrop(
                shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                fill: WeiBeiTheme.paperRaised.opacity(0.92),
                stroke: WeiBeiTheme.hairline.opacity(0.58),
                showsContactShadow: true
            )
        }
    }
}
