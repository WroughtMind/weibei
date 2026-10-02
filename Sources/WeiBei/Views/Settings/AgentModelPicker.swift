import SwiftUI
import WeiBeiCore

// MARK: - Model picker (Settings → 对话服务 → 模型)
//
// Reads the native provider catalog and keeps manual model entry.

extension SettingsView {
    /// The dropdown + status + manual-entry control for the model id.
    @ViewBuilder
    func agentModelPicker() -> some View {
        compactMenu(displayedModelName) {
            modelMenuContent
        }
    }

    private var displayedModelName: String {
        let trimmed = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? store.ui("选择模型…", "Select model…") : trimmed
    }

    @ViewBuilder
    private var modelMenuContent: some View {
        let entries = effectiveModelEntries
        if !entries.isEmpty {
            Section(headerText) {
                ForEach(entries, id: \.self) { model in
                    let isSelected = model == store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                    Button((isSelected ? "✓ " : "   ") + model) {
                        store.updateModelName(model)
                    }
                }
            }
        }

        // Always allow typing an arbitrary id.
        Section {
            Button(store.ui("手动输入…", "Enter manually…")) {
                showManualModelEntry = true
            }
        }
    }

    private var headerText: String {
        store.ui("可用模型", "Available models")
    }

    private var effectiveModelEntries: [String] {
        oauthService.models(provider: store.agentProviderID)
    }

    var selectedModelIsMissing: Bool {
        store.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var selectedModelIsUnavailable: Bool {
        let current = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !current.isEmpty
            && oauthService.hasLoadedModels(provider: store.agentProviderID)
            && !effectiveModelEntries.contains(current)
    }
}
