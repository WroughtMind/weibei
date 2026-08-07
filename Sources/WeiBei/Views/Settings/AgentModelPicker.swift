import SwiftUI
import WeiBeiCore

// MARK: - Model picker (Settings → 对话服务 → 模型)
//
// Reads the catalog from WeiBei's embedded Pi runtime and keeps manual model entry.

extension SettingsView {
    func requestModelListRefresh(force: Bool = false) {
        if force {
            store.shutdownAgentRuntime()
        }
        oauthService.refreshCatalog(force: force)
    }

    /// The dropdown + status + manual-entry control for the model id.
    @ViewBuilder
    func agentModelPicker() -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                if oauthService.isRefreshingCatalog {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WeiBeiTheme.tertiaryInk)
                        // Continuous spin while loading: drive via a monotonically increasing
                        // angle that animates itself each cycle.
                        .rotationEffect(.degrees(spinAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                                spinAngle += 360
                            }
                        }
                }
                compactMenu(displayedModelName) {
                    modelMenuContent
                }
                Button {
                    requestModelListRefresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: !oauthService.isRefreshingCatalog))
                .help(store.ui("重新读取内置 Pi 模型列表", "Reload embedded Pi models"))
            }

            // Inline status line under the control.
            modelStatusLine
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
        if oauthService.catalogError != nil {
            return store.ui("模型（读取失败）", "Models (load failed)")
        }
        return oauthService.catalog == nil
            ? store.ui("模型", "Models")
            : store.ui("内置 Pi 模型", "Embedded Pi models")
    }

    private var effectiveModelEntries: [String] {
        if oauthService.isRefreshingCatalog, oauthService.catalog == nil { return [] }
        let current = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries = oauthService.models(providerID: store.agentProviderID.piProviderName)
        if !current.isEmpty, !entries.contains(current) {
            entries.insert(current, at: 0)
        }
        return entries
    }

    @ViewBuilder
    private var modelStatusLine: some View {
        if oauthService.isRefreshingCatalog {
            Text(store.ui("正在读取内置 Pi 模型…", "Reading embedded Pi models…"))
                .font(.system(size: 11))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
        } else if let message = oauthService.catalogError {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
                .frame(maxWidth: 260, alignment: .trailing)
                .lineLimit(2)
        } else if oauthService.catalog != nil {
            let count = oauthService.models(providerID: store.agentProviderID.piProviderName).count
            Text(store.ui("内置 Pi 提供 \(count) 个模型", "Embedded Pi provides \(count) models"))
                .font(.system(size: 11))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
        }
    }
}
