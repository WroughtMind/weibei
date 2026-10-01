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
            if !store.agentReasoningLevels.isEmpty {
                ForEach(AgentReasoningMode.allCases, id: \.self) { mode in
                    settingsRow(title: mode.label, detail: store.ui("当前模型的推理强度", "Reasoning effort for this model")) {
                        compactMenu(AgentReasoningEffort.label(store.agentReasoningEffort(for: mode) ?? mode.defaultEffort, language: store.interfaceLanguage)) {
                            ForEach(store.agentReasoningLevels, id: \.self) { effort in
                                Button(AgentReasoningEffort.label(effort, language: store.interfaceLanguage)) {
                                    store.agentReasoningMappings[store.agentReasoningMappingKey(mode)] = effort
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
