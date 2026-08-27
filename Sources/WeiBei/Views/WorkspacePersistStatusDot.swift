import SwiftUI

/// 标题栏角落的未落盘标记：saved 不占位；failed 点亮暖色平涂圆点。
/// 悬停展开上次失败说明和重试；点按圆点也直接重试。
struct WorkspacePersistStatusDot: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var showingDetail = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        if store.lastPersistState == .failed {
            Button {
                showingDetail = false
                _ = store.retryWorkspaceSave()
            } label: {
                Circle()
                    .fill(WeiBeiTheme.cinnabar)
                    .frame(width: 7, height: 7)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(store.ui("保存失败，点此重试", "Save failed, click to retry"))
            )
            .onHover(perform: handleHover)
            .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
                persistFailureDetail
                    .onHover(perform: handleHover)
            }
        }
    }

    private var persistFailureDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.ui("上次保存失败", "Last save failed"))
                .weiBeiText(12, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
            if let detail = store.workspaceSaveError {
                Text(detail)
                    .weiBeiText(11.5, weight: .medium)
                    .foregroundStyle(WeiBeiTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showingDetail = false
                _ = store.retryWorkspaceSave()
            } label: {
                Text(store.ui("重试", "Retry"))
                    .weiBeiText(12, weight: .semibold)
                    .foregroundStyle(WeiBeiTheme.cinnabar)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        WeiBeiTheme.paperRaised,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(WeiBeiTheme.cinnabar.opacity(0.35), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(store.ui("重试保存", "Retry save")))
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
    }

    private func handleHover(_ hovering: Bool) {
        dismissTask?.cancel()
        if hovering {
            showingDetail = true
            return
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            showingDetail = false
        }
    }
}
