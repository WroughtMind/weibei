import SwiftUI
import WeiBeiCore

// MARK: - Model picker (Settings → 对话服务 → 模型)
//
// Replaces the old free-text Model field. After a provider + credential are chosen, it
// fetches the live model catalog via `WorkspaceStore.refreshModelList()` and surfaces it
// as a dropdown. Falls back to the built-in recommended list when listing is unsupported
// (e.g. Codex subscription, undocumented endpoints) or the fetch fails. Always keeps a
// "manual entry" escape hatch so users can type any id.

extension SettingsView {
    /// UI-side entry point (onAppear). Delegates to the Store's race-guarded
    /// scheduler so every fetch — whether from here or from a provider/profile
    /// switch inside the Store — flows through one generation-protected path (S2).
    func requestModelListRefresh() {
        store.scheduleModelListRefresh()
    }

    /// The dropdown + status + manual-entry control for the model id.
    @ViewBuilder
    func agentModelPicker() -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                if store.modelListStatus.isLoading {
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
                    requestModelListRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(WeiBeiTextActionButtonStyle(active: !store.modelListStatus.isLoading))
                .help(store.ui("重新获取模型列表", "Refresh model list"))
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
        // The actual model entries (live list or built-in fallback). Menu items must be
        // title-literal Buttons; the current selection is marked with a ✓ prefix since
        // Menu does not render custom HStack/Button-label children reliably.
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

    /// Short, plain section header. Avoids jargon like "auto-list unavailable".
    private var headerText: String {
        switch store.modelListStatus {
        case .loaded: return store.ui("可用模型", "Available models")
        case .builtin: return store.ui("常用模型", "Common models")
        case .failed: return store.ui("常用模型（获取失败）", "Common models (fetch failed)")
        case .idle, .loading: return store.ui("常用模型", "Common models")
        }
    }

    /// Single source of truth = `store.availableModels`. Only fall back to the built-in
    /// recommended catalog when listing is confirmed unavailable (.builtin / .failed) —
    /// NOT on .idle/.loading, otherwise switching profiles briefly shows the previous
    /// provider's recommended list (looks like stale data).
    private var effectiveModelEntries: [String] {
        // While idle/loading, show nothing — the header reads "loading" and the menu
        // offers only manual entry. Avoids flashing another provider's catalog.
        if case .idle = store.modelListStatus { return [] }
        if case .loading = store.modelListStatus { return [] }
        let current = store.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        var entries = store.availableModels.isEmpty
            ? store.agentProviderID.recommendedModels
            : store.availableModels
        if !current.isEmpty, !entries.contains(current) {
            entries.insert(current, at: 0)
        }
        return entries
    }

    @ViewBuilder
    private var modelStatusLine: some View {
        // Keep a durable status after fetch completes — users need to see that listing
        // worked (not a flash of "Fetching…" that vanishes into silence).
        if !envModelOverride.isEmpty {
            settingsPill(
                title: store.ui("环境变量 \(envModelOverride)", "Env \(envModelOverride)"),
                icon: "lock.fill",
                active: false
            )
        } else {
            switch store.modelListStatus {
            case .idle:
                EmptyView()
            case .loading:
                Text(store.ui("正在获取模型…", "Fetching models…"))
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            case .loaded:
                Text(store.ui(
                    "已获取 \(store.availableModels.count) 个模型",
                    "Fetched \(store.availableModels.count) models"
                ))
                .font(.system(size: 11))
                .foregroundStyle(WeiBeiTheme.tertiaryInk)
            case .builtin:
                Text(store.ui("使用内置推荐列表", "Using built-in recommendations"))
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
            case let .failed(message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(WeiBeiTheme.tertiaryInk)
                    .frame(maxWidth: 260, alignment: .trailing)
                    .lineLimit(2)
            }
        }
    }

    private var envModelOverride: String {
        // Delegates to the Store's single source of truth (see M4).
        store.activeModelEnvOverride
    }
}
