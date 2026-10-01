import SwiftUI
import WeiBeiCore

// MARK: - 对话服务 card (Settings → 对话)
//
// One decision chain: service → authentication → model.

extension SettingsView {
    /// Entry point — used by `agentSettings` in WeiBeiApp.swift.
    /// 连接卡片(2026-09-29 定稿):增删改选都在卡列内,不再有五行表单。
    @ViewBuilder
    func agentSettingsContent() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AgentConnectionCardsView()
        }
        .sheet(isPresented: $showManualModelEntry) {
            agentManualModelSheet
        }
    }

    // MARK: Manual model entry sheet

    private var agentManualModelSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.ui("手动输入模型 ID", "Enter model id"))
                .weiBeiText(15, weight: .semibold)
                .foregroundStyle(WeiBeiTheme.ink)
            TextField(
                "",
                text: Binding(
                    get: { store.modelName },
                    set: { store.updateModelName($0) }
                ),
                prompt: Text(oauthService.models(provider: store.agentProviderID).first ?? "model-id")
                    .foregroundStyle(WeiBeiTheme.placeholderInk)
            )
            .textFieldStyle(.plain)
            .weiBeiText(13)
            .foregroundColor(WeiBeiTheme.ink)
            .weiBeiText(13)
            .weibeiInputSurface(active: true, height: 38)
            HStack {
                Spacer()
                Button(store.ui("完成", "Done")) { showManualModelEntry = false }
                    .buttonStyle(WeiBeiTextActionButtonStyle(active: true))
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(WeiBeiTheme.paper)
        .weiBeiFittedSheet()
    }
}
